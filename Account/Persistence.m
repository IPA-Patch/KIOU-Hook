#import "Account/Persistence.h"
#import "logging.h"

// ===========================================================================
// Account/Persistence.m — NSUserDefaults-backed account storage.
//
// Pure Foundation + Chinlan logging. No KIOUHook.h dependency.
// ===========================================================================

NSString *const KIOUAccountStateChangedNotification =
    @"KIOUAccountStateChangedNotification";

static inline void kfPostAccountStateChanged(void) {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:KIOUAccountStateChangedNotification object:nil];
}

static NSString *const kKeyAccounts          = @"kiou_forge.account.accounts";
static NSString *const kKeyActiveUserId      = @"kiou_forge.account.active_user_id";
static NSString *const kKeyForceRegister     = @"kiou_forge.account.force_register_on_next_launch";
static NSString *const kKeyPendingDeviceId   = @"kiou_forge.account.pending_device_id";
static NSString *const kKeyPendingDistinctId = @"kiou_forge.account.pending_distinct_id";

static NSString *const kFieldUuid       = @"uuid";
static NSString *const kFieldUserName   = @"userName";
static NSString *const kFieldOpenId     = @"openId";
static NSString *const kFieldUserId     = @"userId";
static NSString *const kFieldDistinctId = @"distinctId";
static NSString *const kFieldSavedAt    = @"savedAt";

NSArray<NSDictionary *> *KIOUListAccounts(void) {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kKeyAccounts];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:raw.count];
    for (id e in raw) {
        if ([e isKindOfClass:[NSDictionary class]]) [result addObject:e];
    }
    return result;
}

void KIOUSaveAccount(NSString *uuid, NSString *userName, NSString *openId,
                   NSString *userId, NSString *distinctId) {
    if (userId.length == 0) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] save skipped: missing userId (uuid=%@ userName=%@)",
                  uuid ?: @"", userName ?: @""]);
        return;
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *existing = KIOUListAccounts();
    NSMutableArray<NSDictionary *> *next =
        [NSMutableArray arrayWithCapacity:existing.count + 1];
    BOOL replaced = NO;
    NSDictionary *fresh = @{
        kFieldUuid:       uuid       ?: @"",
        kFieldUserName:   userName   ?: @"",
        kFieldOpenId:     openId     ?: @"",
        kFieldUserId:     userId,
        kFieldDistinctId: distinctId ?: @"",
        kFieldSavedAt:    @((NSInteger)[[NSDate date] timeIntervalSince1970]),
    };
    for (NSDictionary *e in existing) {
        NSString *eId = e[kFieldUserId];
        if ([eId isKindOfClass:[NSString class]] && [eId isEqualToString:userId]) {
            NSMutableDictionary *merged = [fresh mutableCopy];
            if (uuid.length       == 0) merged[kFieldUuid]       = e[kFieldUuid]       ?: @"";
            if (userName.length   == 0) merged[kFieldUserName]   = e[kFieldUserName]   ?: @"";
            if (openId.length     == 0) merged[kFieldOpenId]     = e[kFieldOpenId]     ?: @"";
            if (distinctId.length == 0) merged[kFieldDistinctId] = e[kFieldDistinctId] ?: @"";
            [next addObject:merged];
            replaced = YES;
        } else {
            [next addObject:e];
        }
    }
    if (!replaced) [next addObject:fresh];
    [d setObject:next forKey:kKeyAccounts];
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] saved userId=%@ userName=%@ uuid=%@ total=%lu",
              userId, userName ?: @"", uuid ?: @"", (unsigned long)next.count]);
    kfPostAccountStateChanged();
}

void KIOUUpdateAccountProfile(NSString *userId, NSString *openId,
                            NSArray<NSDictionary *> *ranks) {
    if (userId.length == 0) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *existing = KIOUListAccounts();
    BOOL found = NO;
    NSMutableArray<NSDictionary *> *next =
        [NSMutableArray arrayWithCapacity:existing.count];
    for (NSDictionary *e in existing) {
        NSString *eId = e[kFieldUserId];
        if ([eId isKindOfClass:[NSString class]] && [eId isEqualToString:userId]) {
            NSMutableDictionary *merged = [e mutableCopy];
            if (openId.length > 0) merged[kFieldOpenId] = openId;
            if (ranks.count   > 0) merged[@"ranks"] = ranks;
            [next addObject:merged];
            found = YES;
        } else {
            [next addObject:e];
        }
    }
    if (!found) return;
    [d setObject:next forKey:kKeyAccounts];
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] profile updated userId=%@ openId=%@ ranks=%lu",
              userId, openId ?: @"", (unsigned long)ranks.count]);
    kfPostAccountStateChanged();
}

void KIOUDeleteAccount(NSString *userId) {
    if (userId.length == 0) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *existing = KIOUListAccounts();
    NSMutableArray<NSDictionary *> *next =
        [NSMutableArray arrayWithCapacity:existing.count];
    for (NSDictionary *e in existing) {
        NSString *eId = e[kFieldUserId];
        if ([eId isKindOfClass:[NSString class]] && [eId isEqualToString:userId]) continue;
        [next addObject:e];
    }
    [d setObject:next forKey:kKeyAccounts];
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] deleted userId=%@ remaining=%lu",
              userId, (unsigned long)next.count]);
    kfPostAccountStateChanged();
}

NSString *KIOUActiveAccountUserId(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyActiveUserId];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

void KIOUSetActiveAccountUserId(NSString *userId) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (userId.length == 0) {
        [d removeObjectForKey:kKeyActiveUserId];
    } else {
        [d setObject:userId forKey:kKeyActiveUserId];
    }
    IPALog([NSString stringWithFormat:@"[ACCOUNT] active_user_id=%@",
              userId.length > 0 ? userId : @"(none)"]);
    kfPostAccountStateChanged();
}

bool KIOUForceRegisterOnNextLaunch(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyForceRegister];
    return v ? [v boolValue] : false;
}

void KIOUSetForceRegisterOnNextLaunch(bool enabled) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (enabled) {
        [d setBool:YES forKey:kKeyForceRegister];
    } else {
        [d removeObjectForKey:kKeyForceRegister];
    }
    IPALog([NSString stringWithFormat:@"[ACCOUNT] force_register=%s",
              enabled ? "true" : "false"]);
}

NSString *KIOUPendingDeviceId(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyPendingDeviceId];
    return ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) ? v : nil;
}

void KIOUSetPendingDeviceId(NSString *uuid) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (uuid.length == 0) {
        [d removeObjectForKey:kKeyPendingDeviceId];
        IPALog(@"[ACCOUNT] pending_device_id cleared");
    } else {
        [d setObject:uuid forKey:kKeyPendingDeviceId];
        IPALog([NSString stringWithFormat:@"[ACCOUNT] pending_device_id=%@", uuid]);
    }
    kfPostAccountStateChanged();
}

NSString *KIOUPendingDistinctId(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyPendingDistinctId];
    return ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) ? v : nil;
}

void KIOUSetPendingDistinctId(NSString *uuid) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (uuid.length == 0) {
        [d removeObjectForKey:kKeyPendingDistinctId];
        IPALog(@"[ACCOUNT] pending_distinct_id cleared");
    } else {
        [d setObject:uuid forKey:kKeyPendingDistinctId];
        IPALog([NSString stringWithFormat:@"[ACCOUNT] pending_distinct_id=%@", uuid]);
    }
    kfPostAccountStateChanged();
}

void KIOUSwitchAccount(NSString *uuid) {
    NSString *armedDistinct = KIOUPendingDistinctId();
    if (armedDistinct.length > 0) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] KIOUSwitchAccount refused: Register flow in progress "
                  @"(pending_distinct_id=%@)", armedDistinct]);
        return;
    }
    KIOUSetPendingDeviceId(uuid);
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] KIOUSwitchAccount armed pending_device_id=%@", uuid ?: @"(nil)"]);
}

// ---------------------------------------------------------------------------
// Self user UUID (moved from KiouEditor's Hook_MatchingPlayer.m).
// Key preserved to survive the KIOU-Hook migration on existing installs.
// ---------------------------------------------------------------------------

static NSString *const kKeySelfUserId = @"kiou_editor.self_user_id";

NSString *KIOUSelfUserId(void) {
    NSString *uid = [[NSUserDefaults standardUserDefaults] stringForKey:kKeySelfUserId];
    return uid.length > 0 ? uid : nil;
}

void KIOUSetSelfUserId(NSString *uid) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (uid.length == 0) {
        [d removeObjectForKey:kKeySelfUserId];
    } else {
        [d setObject:uid forKey:kKeySelfUserId];
    }
    [d synchronize];
}
