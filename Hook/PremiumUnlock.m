#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/PremiumUnlock.m — force isPremiumUser = true across the kifu-detail
// flow.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_PremiumUnlock.m.
//
// Three call sites:
//   a) KifuDetailModel.IsPremiumUser()                       (getter)
//   b) GetShogiHistoryDetailListReply.InternalMergeFrom      (protobuf reply
//      carrying the server's premium flag at +0x20 — writing 1 there right
//      after decode means every later reader sees true)
//   c) GetShogiHistoryDetailListReply.get_IsPremiumUser      (belt-and-braces
//      getter for reply paths that don't hit InternalMergeFrom)
//
// Net effect on the match-history detail popup:
//   - the bottom "_analysisPassBuyButton" purchase banner disappears
//   - tapping the analyse button runs RunAnalysisFlowAsync (local NNUE)
//     instead of RunPassPurchaseFlowAsync
// All client-side; no outbound request changes.
// ===========================================================================

#define OFF_SHOGI_HISTORY_DETAIL_REPLY_IS_PREMIUM_USER   0x20

typedef bool (*IsPremiumUser_t)(void *self);
typedef void (*ReplyMergeFrom_t)(void *self, void *parseContext);

static IsPremiumUser_t  s_origKifuDetailModel_IsPremiumUser    = NULL;
static IsPremiumUser_t  s_origHistoryDetailReply_IsPremiumUser = NULL;
static ReplyMergeFrom_t s_origHistoryDetailReply_merge         = NULL;

static bool hook_KifuDetailModel_IsPremiumUser(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_PREMIUM_UNLOCK)) {
        return s_origKifuDetailModel_IsPremiumUser
            ? s_origKifuDetailModel_IsPremiumUser(self) : false;
    }
    (void)self;
    return true;
}

static bool hook_HistoryDetailReply_IsPremiumUser(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_PREMIUM_UNLOCK)) {
        return s_origHistoryDetailReply_IsPremiumUser
            ? s_origHistoryDetailReply_IsPremiumUser(self) : false;
    }
    (void)self;
    return true;
}

static void hook_HistoryDetailReply_merge(void *self, void *parseContext) {
    if (s_origHistoryDetailReply_merge) {
        s_origHistoryDetailReply_merge(self, parseContext);
    }
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_PREMIUM_UNLOCK)) return;
    if (!ptrLooksValid(self)) return;
    @try {
        uint8_t before = readU8(self, OFF_SHOGI_HISTORY_DETAIL_REPLY_IS_PREMIUM_USER);
        if (before != 1) {
            writeU8(self, OFF_SHOGI_HISTORY_DETAIL_REPLY_IS_PREMIUM_USER, 1);
            IPALog([NSString stringWithFormat:
                    @"[PREMIUM] HistoryDetailReply.isPremiumUser %d -> 1",
                    (int)before]);
        }
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[PREMIUM] HistoryDetailReply merge exception: %@", e]);
    }
}

void KIOUEditorInstallPremiumUnlockHook(uintptr_t unityBase) {
    s_origKifuDetailModel_IsPremiumUser = (IsPremiumUser_t)KIOUHookInstall(
        KIOU_HOOK_NAME_KIFU_DETAIL_IS_PREMIUM,
        (void *)hook_KifuDetailModel_IsPremiumUser, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_KIFU_DETAIL_IS_PREMIUM, hook_KifuDetailModel_IsPremiumUser);
    s_origHistoryDetailReply_merge = (ReplyMergeFrom_t)KIOUHookInstall(
        KIOU_HOOK_NAME_HISTORY_DETAIL_MERGE,
        (void *)hook_HistoryDetailReply_merge, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_HISTORY_DETAIL_MERGE, hook_HistoryDetailReply_merge);
    s_origHistoryDetailReply_IsPremiumUser = (IsPremiumUser_t)KIOUHookInstall(
        KIOU_HOOK_NAME_HISTORY_GET_PREMIUM,
        (void *)hook_HistoryDetailReply_IsPremiumUser, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_HISTORY_GET_PREMIUM, hook_HistoryDetailReply_IsPremiumUser);
    IPALog([NSString stringWithFormat:
            @"[PREMIUM] installed: KifuDetail.IsPremium orig=%p, "
            @"HistoryDetail.merge orig=%p, HistoryDetail.get_IsPremium orig=%p",
            (void *)s_origKifuDetailModel_IsPremiumUser,
            (void *)s_origHistoryDetailReply_merge,
            (void *)s_origHistoryDetailReply_IsPremiumUser]);
}
