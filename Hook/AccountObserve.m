#import "KIOUHook.h"
#import "Account/Persistence.h"
#import "il2cpp.h"
#import "logging.h"
#import <dlfcn.h>

// ===========================================================================
// Hook/AccountObserve.m — account identity observation + switching.
//
// Bodies use the name-based API (KIOUHookOrig / KIOUHookInstall) and never
// reference KIOU_HOOK_ID_* enum or KIOU_HOOK_RVA_* directly.
//
// Hook sites (resolved by name at install time):
//
//   UserSaveDataExtensions.AccountExists
//   ILoginArgs.Create
//   IRegisterUserArgs.Create
//   RunLoginSequenceAsync.MoveNext
//   GetSelfUserProfileAsync.MoveNext
//   TitleMenuPopupPresenter.RunResetUserDataSequenceAsync   (raw site, not in catalog)
//   TitleMenuPopupPresenter.RunDeleteAccountSequenceAsync   (raw site, not in catalog)
// ===========================================================================

// RunReset / RunDelete are not in the catalog (not binpatched / not part
// of the cave system); keep their RVAs local so the hook installer can
// MSHookFunction them on JB.
#define KF_RVA_RUN_RESET_USER_DATA_SEQ       0x5DCC204
#define KF_RVA_RUN_DELETE_ACCOUNT_SEQ        0x5DCC2B4

// ---------------------------------------------------------------------------
// Field offsets
// ---------------------------------------------------------------------------
#define OFF_USER_SAVE_DATA_USER_NAME  0x10
#define OFF_USER_SAVE_DATA_OPEN_ID    0x18
#define OFF_USER_SAVE_DATA_USER_ID    0x20
#define OFF_USER_SAVE_DATA_DEVICE_ID  0x28

#define OFF_LOGIN_REPLY_ACCESS_TOKEN  0x18
#define OFF_LOGIN_REPLY_SESSION_ID    0x20
#define OFF_LOGIN_REPLY_DEVICE_ID     0x28
#define OFF_LOGIN_REPLY_USER_NAME     0x30

#define OFF_SM_LOGIN_STATE     0x00
#define OFF_SM_LOGIN_RESULT_D  0x50  // confirmed on KIOU 1.0.1 build 11

#define OFF_GET_SELF_PROFILE_REPLY_PROFILE  0x18
#define OFF_SELF_PROFILE_USER_NAME          0x18
#define OFF_SELF_PROFILE_OPEN_USER_ID       0x20
#define OFF_SELF_PROFILE_RANK_LIST          0x28
#define OFF_REPEATED_ARRAY                  0x10
#define OFF_REPEATED_COUNT                  0x18
#define OFF_RANK_STATUS_MATCH_TYPE     0x18
#define OFF_RANK_STATUS_RANK_RULE_TYPE 0x1C
#define OFF_RANK_STATUS_RANK           0x24
#define OFF_RANK_STATUS_RATING         0x28

// ---------------------------------------------------------------------------
// Observed state
// ---------------------------------------------------------------------------
static NSString *volatile g_latestObservedUserId = nil;

// il2cpp_string_new resolved via dlsym at install time.
typedef void *(*Il2CppStringNew_t)(const char *utf8);
static Il2CppStringNew_t g_il2cpp_string_new = NULL;

// Function pointer types for orig storage.
typedef bool         (*AccountExists_t)(void *data, void *mi);
typedef void *       (*LoginArgsCreate_t)(void *deviceId, void *distinctId, void *mi);
typedef void *       (*RegisterUserArgsCreate_t)(void *userName, void *distinctId, void *mi);
typedef void         (*MoveNextVoid_t)(void *self, void *mi);
typedef KFUniTaskRet (*RunResetSeq_t)(void *ct, void *mi);

// Orig pointers — filled by KIOUHookInstall at install time on both JB and
// chinlan. On chinlan these hold the cave-bypass entries; on JB they hold
// the MSHookFunction orig.
static AccountExists_t          s_origAccountExists       = NULL;
static LoginArgsCreate_t        s_origLoginArgsCreate     = NULL;
static RegisterUserArgsCreate_t s_origRegisterUserArgsCreate = NULL;
static MoveNextVoid_t           s_origRunLoginSeqMoveNext = NULL;
static MoveNextVoid_t           s_origGetSelfProfileMoveNext = NULL;
static RunResetSeq_t            s_origRunResetSeq         = NULL;
static RunResetSeq_t            s_origRunDeleteAccountSeq = NULL;

// ---------------------------------------------------------------------------
// JWT helper — extract "sub" claim from HS256 JWT.
// ---------------------------------------------------------------------------
static NSString *extractJWTSub(NSString *jwt) {
    if (jwt.length == 0) return nil;
    NSArray<NSString *> *parts = [jwt componentsSeparatedByString:@"."];
    if (parts.count < 2) return nil;
    NSString *payload = parts[1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payload.length % 4) payload = [payload stringByAppendingString:@"="];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    id sub = ((NSDictionary *)obj)[@"sub"];
    return [sub isKindOfClass:[NSString class]] ? (NSString *)sub : nil;
}

// ---------------------------------------------------------------------------
// il2cpp string reader
// ---------------------------------------------------------------------------
static NSString *readIl2CppStr(void *strObj) {
    if (!strObj) return nil;
    @try {
        int32_t len = readI32(strObj, 0x10);
        if (len <= 0 || len > 4096) return nil;
        const uint16_t *chars = (const uint16_t *)((uint8_t *)strObj + 0x14);
        return [NSString stringWithCharacters:chars length:(NSUInteger)len];
    } @catch (...) { return nil; }
}

// ---------------------------------------------------------------------------
// Rank label helper
// ---------------------------------------------------------------------------
static const char *kfRankLabel(int32_t rank) {
    if (rank < 2) return "?";
    static const char *labels[] = {
        "10Kyu","9Kyu","8Kyu","7Kyu","6Kyu","5Kyu","4Kyu","3Kyu","2Kyu","1Kyu",
        "1Dan","2Dan","3Dan","4Dan","5Dan","6Dan","7Dan","8Dan","9Dan",
    };
    int idx = rank - 2;
    if (idx < 0 || idx >= (int)(sizeof(labels)/sizeof(labels[0]))) return "?";
    return labels[idx];
}

// ===========================================================================
// RegisterUserArgs.Create — distinctId substitution
// ===========================================================================
static void *kfSwapRegisterDistinctId(void *userName, void *distinctId) {
    NSString *pending = KFPendingDistinctId();
    if (pending.length > 0 && g_il2cpp_string_new) {
        void *newStr = g_il2cpp_string_new(pending.UTF8String);
        if (newStr) {
            IPALog([NSString stringWithFormat:
                      @"[ACCOUNT] RegisterUserArgs.Create distinctId → %@", pending]);
            return newStr;
        }
    }
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] RegisterUserArgs.Create userName=%@ distinctId=%@",
              readIl2CppStr(userName) ?: @"(nil)",
              readIl2CppStr(distinctId) ?: @"(nil)"]);
    return distinctId;
}

void *KFHookRegisterUserArgsCreate(void *userName, void *distinctId, void *mi) {
    void *useDistinctId = kfSwapRegisterDistinctId(userName, distinctId);
    return s_origRegisterUserArgsCreate
        ? s_origRegisterUserArgsCreate(userName, useDistinctId, mi)
        : NULL;
}

// ===========================================================================
// LoginArgs.Create — deviceId substitution
// ===========================================================================
static void *kfSwapLoginDeviceId(void *deviceId, void *distinctId) {
    NSString *pending = KFPendingDeviceId();
    if (pending.length > 0 && g_il2cpp_string_new) {
        void *newStr = g_il2cpp_string_new(pending.UTF8String);
        if (newStr) {
            IPALog([NSString stringWithFormat:
                      @"[ACCOUNT] LoginArgs.Create deviceId → %@", pending]);
            return newStr;
        }
    }
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] LoginArgs.Create deviceId=%@ distinctId=%@",
              readIl2CppStr(deviceId) ?: @"(nil)",
              readIl2CppStr(distinctId) ?: @"(nil)"]);
    return deviceId;
}

void *KFHookLoginArgsCreate(void *deviceId, void *distinctId, void *mi) {
    void *useDeviceId = kfSwapLoginDeviceId(deviceId, distinctId);
    return s_origLoginArgsCreate
        ? s_origLoginArgsCreate(useDeviceId, distinctId, mi)
        : NULL;
}

// ===========================================================================
// RunLoginSequenceAsync.MoveNext — capture LoginReply
// ===========================================================================
static void observeRunLoginSeqCompletion(void *self) {
    if (!self) return;
    if (readI32(self, OFF_SM_LOGIN_STATE) != -2) return;

    uintptr_t offsets[] = { 0x38, 0x40, 0x48, OFF_SM_LOGIN_RESULT_D };
    for (size_t i = 0; i < sizeof(offsets)/sizeof(offsets[0]); i++) {
        void *candidate = readPtr(self, offsets[i]);
        if (!candidate) continue;
        NSString *accessToken = readIl2CppStr(readPtr(candidate, OFF_LOGIN_REPLY_ACCESS_TOKEN));
        NSString *deviceId    = readIl2CppStr(readPtr(candidate, OFF_LOGIN_REPLY_DEVICE_ID));
        NSString *userName    = readIl2CppStr(readPtr(candidate, OFF_LOGIN_REPLY_USER_NAME));
        if (!userName && !deviceId) continue;
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] LoginReply @0x%lx userName=%@ deviceId=%@",
                  (unsigned long)offsets[i], userName ?: @"(nil)", deviceId ?: @"(nil)"]);

        NSString *userId = extractJWTSub(accessToken);
        if (userId.length == 0) userId = g_latestObservedUserId;
        if (userId.length > 0 && deviceId.length > 0) {
            KFSaveAccount(deviceId, userName, @"", userId, deviceId);
            KFSetActiveAccountUserId(userId);
        }
        KFSetPendingDeviceId(nil);
        KFSetPendingDistinctId(nil);
        KFSetForceRegisterOnNextLaunch(false);
        return;
    }
}

void KFHookRunLoginSeqMoveNext(void *self, void *mi) {
    if (s_origRunLoginSeqMoveNext) {
        @try { s_origRunLoginSeqMoveNext(self, mi); }
        @catch (NSException *e) {
            IPALog([NSString stringWithFormat:
                      @"[ACCOUNT] RunLoginSeq.MoveNext orig threw: %@", e]);
            return;
        }
    }
    observeRunLoginSeqCompletion(self);
}

// ===========================================================================
// GetSelfUserProfileAsync.MoveNext — capture rank / openId
// ===========================================================================
static void observeGetSelfProfileCompletion(void *self) {
    if (!self) return;
    if (readI32(self, 0x00) != -2) return;

    for (uintptr_t off = 0x30; off <= 0x60; off += 0x08) {
        void *reply = readPtr(self, off);
        if (!reply) continue;
        void *profile = readPtr(reply, OFF_GET_SELF_PROFILE_REPLY_PROFILE);
        if (!profile) continue;
        NSString *userName   = readIl2CppStr(readPtr(profile, OFF_SELF_PROFILE_USER_NAME));
        NSString *openUserId = readIl2CppStr(readPtr(profile, OFF_SELF_PROFILE_OPEN_USER_ID));
        if (userName.length == 0 && openUserId.length == 0) continue;

        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] SelfProfile @0x%lx userName=%@ openUserId=%@",
                  (unsigned long)off, userName ?: @"(nil)", openUserId ?: @"(nil)"]);

        NSMutableArray<NSDictionary *> *rankDicts = [NSMutableArray array];
        void *rankListObj = readPtr(profile, OFF_SELF_PROFILE_RANK_LIST);
        void *array = readPtr(rankListObj, OFF_REPEATED_ARRAY);
        int32_t count = readI32(rankListObj, OFF_REPEATED_COUNT);
        if (array && count > 0 && count < 32) {
            for (int32_t ri = 0; ri < count; ri++) {
                void *entry = *(void **)((uint8_t *)array + 0x20 + ri * 8);
                if (!entry) continue;
                int32_t matchType = readI32(entry, OFF_RANK_STATUS_MATCH_TYPE);
                int32_t ruleType  = readI32(entry, OFF_RANK_STATUS_RANK_RULE_TYPE);
                int32_t rank      = readI32(entry, OFF_RANK_STATUS_RANK);
                int32_t rating    = readI32(entry, OFF_RANK_STATUS_RATING);
                [rankDicts addObject:@{
                    @"matchType": @(matchType),
                    @"ruleType":  @(ruleType),
                    @"rank":      @(rank),
                    @"rankLabel": @(kfRankLabel(rank)),
                    @"rating":    @(rating),
                }];
            }
        }

        NSString *activeUserId = KFActiveAccountUserId();
        if (activeUserId.length > 0)
            KFUpdateAccountProfile(activeUserId, openUserId, rankDicts);
        return;
    }
}

void KFHookGetSelfProfileMoveNext(void *self, void *mi) {
    if (s_origGetSelfProfileMoveNext) {
        @try { s_origGetSelfProfileMoveNext(self, mi); }
        @catch (NSException *e) {
            IPALog([NSString stringWithFormat:
                      @"[ACCOUNT] GetSelfProfile.MoveNext orig threw: %@", e]);
            return;
        }
    }
    observeGetSelfProfileCompletion(self);
}

// ===========================================================================
// AccountExists — observe + Force Register override
// ===========================================================================
static void observeAccountExistsData(void *data) {
    if (!data) return;
    NSString *userName = readIl2CppStr(readPtr(data, OFF_USER_SAVE_DATA_USER_NAME));
    NSString *openId   = readIl2CppStr(readPtr(data, OFF_USER_SAVE_DATA_OPEN_ID));
    NSString *userId   = readIl2CppStr(readPtr(data, OFF_USER_SAVE_DATA_USER_ID));
    NSString *deviceId = readIl2CppStr(readPtr(data, OFF_USER_SAVE_DATA_DEVICE_ID));

    if (userId.length > 0) g_latestObservedUserId = userId;

    if (userId.length > 0 && deviceId.length > 0) {
        KFSaveAccount(deviceId, userName, openId, userId, deviceId);
        if (KFActiveAccountUserId().length == 0)
            KFSetActiveAccountUserId(userId);
    }
}

bool KFHookAccountExists(void *data, void *mi) {
    bool origResult = false;
    if (s_origAccountExists) {
        @try { origResult = s_origAccountExists(data, mi); }
        @catch (NSException *e) {
            IPALog([NSString stringWithFormat:@"[ACCOUNT] AccountExists orig threw: %@", e]);
        }
    }
    observeAccountExistsData(data);
    bool forceRegister = KFForceRegisterOnNextLaunch();
    bool result = forceRegister ? false : origResult;
    if (forceRegister) {
        IPALog(@"[ACCOUNT] AccountExists overridden false (force_register)");
    }
    return result;
}

// ===========================================================================
// RunResetUserDataSequenceAsync — generate fresh UUID for new account
// ===========================================================================
KFUniTaskRet KFHookRunResetUserDataSeq(void *ct, void *mi) {
    NSString *freshUuid = [[NSUUID UUID] UUIDString].lowercaseString;
    KFSetPendingDistinctId(freshUuid);
    KFSetPendingDeviceId(freshUuid);
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] RunResetUserDataSequenceAsync armed fresh_uuid=%@", freshUuid]);
    return s_origRunResetSeq ? s_origRunResetSeq(ct, mi) : (KFUniTaskRet){0, 0};
}

KFUniTaskRet KFHookRunDeleteAccountSeq(void *ct, void *mi) {
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] RunDeleteAccountSequenceAsync (active=%@)",
              KFActiveAccountUserId() ?: @"(none)"]);
    return s_origRunDeleteAccountSeq ? s_origRunDeleteAccountSeq(ct, mi) : (KFUniTaskRet){0, 0};
}

// ===========================================================================
// Public entry — drive BackToTitleSequence.RunAsync. Called by Settings UI
// after the user confirms the account-switch dialog so KIOU navigates back
// to the title scene, re-running AccountExists → LoginAsync with the
// pending_device_id substitution in effect (no app relaunch needed).
// ===========================================================================
typedef KFUniTaskRet (*BackToTitleRunAsync_t)(void *ct, void *mi);

void KFNavigateToTitleScene(void) {
    if (g_unityBase == 0) {
        IPALog(@"[ACCOUNT] KFNavigateToTitleScene: unityBase not yet set");
        return;
    }
    uintptr_t addr = KIOUHookSiteAddr(KIOU_HOOK_NAME_BACK_TO_TITLE_RUN_ASYNC, g_unityBase);
    if (addr == 0) {
        IPALog(@"[ACCOUNT] KFNavigateToTitleScene: site address unknown");
        return;
    }
    BackToTitleRunAsync_t fn = (BackToTitleRunAsync_t)addr;
    @try {
        (void)fn(NULL, NULL);
        IPALog(@"[ACCOUNT] BackToTitleSequence.RunAsync invoked");
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] BackToTitleSequence.RunAsync threw: %@", e]);
    }
}

// ===========================================================================
// Installer
// ===========================================================================
void KFInstallAccountObserveHook(uintptr_t unityBase) {
    if (!g_il2cpp_string_new)
        g_il2cpp_string_new = (Il2CppStringNew_t)dlsym(RTLD_DEFAULT, "il2cpp_string_new");

    s_origAccountExists = (AccountExists_t)
        KIOUHookInstall(KIOU_HOOK_NAME_ACCOUNT_EXISTS, (void *)KFHookAccountExists, unityBase);
    s_origLoginArgsCreate = (LoginArgsCreate_t)
        KIOUHookInstall(KIOU_HOOK_NAME_LOGIN_ARGS_CREATE, (void *)KFHookLoginArgsCreate, unityBase);
    s_origRegisterUserArgsCreate = (RegisterUserArgsCreate_t)
        KIOUHookInstall(KIOU_HOOK_NAME_REGISTER_USER_ARGS_CREATE, (void *)KFHookRegisterUserArgsCreate, unityBase);
    s_origRunLoginSeqMoveNext = (MoveNextVoid_t)
        KIOUHookInstall(KIOU_HOOK_NAME_RUN_LOGIN_SEQ_MOVENEXT, (void *)KFHookRunLoginSeqMoveNext, unityBase);
    s_origGetSelfProfileMoveNext = (MoveNextVoid_t)
        KIOUHookInstall(KIOU_HOOK_NAME_GET_SELF_PROFILE_MOVENEXT, (void *)KFHookGetSelfProfileMoveNext, unityBase);

#if IPA_CHINLAN
    (void)KF_RVA_RUN_RESET_USER_DATA_SEQ;
    (void)KF_RVA_RUN_DELETE_ACCOUNT_SEQ;
    IPALog(@"[ACCOUNT] chinlan: catalog hooks resolved; raw-RVA hooks (Reset/Delete) skipped");
#else
    // RunReset / RunDelete are JB-only sites (no chinlan cave for them).
    {
        uintptr_t addr = unityBase + KF_RVA_RUN_RESET_USER_DATA_SEQ;
        void *orig = NULL;
        MSHookFunction((void *)addr, (void *)KFHookRunResetUserDataSeq, &orig);
        s_origRunResetSeq = (RunResetSeq_t)orig;
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] hooked RunResetUserDataSeq @0x%lx", (unsigned long)addr]);
    }
    {
        uintptr_t addr = unityBase + KF_RVA_RUN_DELETE_ACCOUNT_SEQ;
        void *orig = NULL;
        MSHookFunction((void *)addr, (void *)KFHookRunDeleteAccountSeq, &orig);
        s_origRunDeleteAccountSeq = (RunResetSeq_t)orig;
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] hooked RunDeleteAccountSeq @0x%lx", (unsigned long)addr]);
    }
    IPALog(@"[ACCOUNT] hooks installed");
#endif
}
