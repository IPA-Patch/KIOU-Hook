#import "Hook/Common.h"
#import "Account/Persistence.h"
#import "logging.h"

// ===========================================================================
// Hook/MatchingPlayer.m — ShogiMatchingPlayerStatus.InternalMergeFrom.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_MatchingPlayer.m.
// KIOUSelfUserId / KIOUSetSelfUserId now live in Account/Persistence.
//
// The match-room server sends this DTO once per player (blackPlayer +
// whitePlayer) when a match starts. It's the source of truth for the
// avatar shown on the match screen, which is a DIFFERENT path from the
// title-screen "current character" Sync. The SelectCharacter swap is
// invisible here, so without this hook the avatar reverts to
// KIOU_SAFE_SKIN_ID during matches.
//
// Strategy: only rewrite the SELF player's character. Identify self via:
//   - NSUserDefaults key (exact UUID match) — reliable.
//   - Fallback heuristic when self_user_id is unset: skip userId == "cpu"
//     or empty, then treat any remaining entry whose skin id equals
//     KIOU_SAFE_SKIN_ID as self (we forced ourselves to SAFE_ID via
//     HOOK 4, so the match-room reflects that for us). Works for CPU
//     matches and PvP where the opponent picked something other than
//     SAFE_ID. Logs the userId we acted on so the user can lock it in
//     via KIOUSetSelfUserId for stricter PvP behavior later.
//
// Fields (dump.cs, Dto.ShogiMatchingPlayerStatus):
//                          <= 1.1.0   >= 1.5.0
//   +0x18 userId            String*    openUserId_ (same slot; the JWT-sub
//                                      userId_ was removed in 1.5.0)
//   mstCharacterId  (int32) 0x38       0x3C   <- rewritten
//   mstCharacterSkinId      0x40       0x48   <- rewritten
//   enableBeginnerSupport   0x68       0x90   <- forced to 1 for self
//     (bool; 1.5.0 added currentWinStreak_ / mstCharacterIsContract_ /
//      mstCharacterSkinLimitBreakLevel_ / mstShogiFinishBgmId_ /
//      favoriteStrategy_ / favoriteCastling_, shifting everything past rank_)
//   NOTE: the 1.1.0 dump puts enableBeginnerSupport_ at 0x70 (it inserted a
//   field ahead of aiSpecialSupport*Count_); build 15 still uses 0x68 here.
//
// Self identity, build >= 22: the +0x18 value is an openUserId, so it is
// compared with the active account's openId (KIOUActiveAccountOpenId), not
// the JWT-sub userId. KIOUSelfUserId / KIOUSetSelfUserId are not used there:
// that key is shared with older builds and holds a JWT-sub, so storing an
// openId in it would corrupt their stale-check. Without a captured openId
// the SAFE_ID skin heuristic applies and nothing is persisted.
//
// We rewrite ONLY mstCharacterId + mstCharacterSkinId. Icon / frame /
// title / piece / board / BGM are decorations the user actually owns
// server-side, so touching them here would diverge from the server's
// real state.
// ===========================================================================

#define OFF_MP_USER_ID                 0x18
#if KIOU_HOOK_TARGET_BUILD >= 22
#define OFF_MP_MST_CHAR_ID             0x3C
#define OFF_MP_MST_SKIN_ID             0x48
#define OFF_MP_ENABLE_BEGINNER_SUPPORT 0x90
#else
#define OFF_MP_MST_CHAR_ID             0x38
#define OFF_MP_MST_SKIN_ID             0x40
#define OFF_MP_ENABLE_BEGINNER_SUPPORT 0x68
#endif

static NSString *const kCpuUserIdSentinel = @"cpu";

typedef void (*ReplyMergeFrom_t)(void *self, void *parseContext);

static ReplyMergeFrom_t s_origMatchingPlayer_merge = NULL;

// mstCharacterId owning a skin. Observed skin table (1.5.0 SyncItemList):
// 1..16 -> same id, 10001 -> 1, 20001 -> 2, 60001 -> 6, i.e. the skin id's
// 10000s digit. Assumes the table's mstCharId keeps matching that. Older
// builds wrote skin == char, which is the same for skins 1..16. A char id
// that does not exist makes the client abort the match (error 50001).
static inline int32_t charIdForSkinId(int32_t skinId) {
    return skinId >= 10000 ? skinId / 10000 : skinId;
}

static void hook_MatchingPlayer_merge(void *self, void *parseContext) {
    if (s_origMatchingPlayer_merge) {
        s_origMatchingPlayer_merge(self, parseContext);
    }
    if (!ptrLooksValid(self)) {
        IPALog(@"[MATCH] skipped: reason=selfPtrInvalid");
        return;
    }

    @try {
        void *userIdStr = readPtr(self, OFF_MP_USER_ID);
        NSString *userId = il2cppStringToNSString(userIdStr);
        int32_t dbgSkinId = readI32(self, OFF_MP_MST_SKIN_ID);
        int32_t dbgCharId = readI32(self, OFF_MP_MST_CHAR_ID);
#if KIOU_HOOK_TARGET_BUILD >= 22
        IPALog([NSString stringWithFormat:
                @"[MATCH] fire: openUserId=%@ skin=%d char=%d persisted=%d",
                userId.length ? userId : @"(empty)",
                dbgSkinId, dbgCharId, KIOUEditorPersistedSelection()]);
#else
        IPALog([NSString stringWithFormat:
                @"[MATCH] fire: userId=%@ skin=%d char=%d persisted=%d",
                userId.length ? userId : @"(empty)",
                dbgSkinId, dbgCharId, KIOUEditorPersistedSelection()]);
#endif

        if (userId.length == 0) return;
        if ([userId isEqualToString:kCpuUserIdSentinel]) return;

        int32_t curSkinId = dbgSkinId;
        int32_t curCharId = dbgCharId;

#if KIOU_HOOK_TARGET_BUILD >= 22
        NSString *configuredSelf = KIOUActiveAccountOpenId();
        if (configuredSelf.length == 0) {
            configuredSelf = nil;
            IPALog(@"[MATCH] fallback: reason=openIdUnset next=skinHeuristic");
        }
#else
        // Prefer KIOUActiveAccountUserId (refreshed on every AccountExists
        // observation) over the heuristic-captured KIOUSelfUserId. On
        // account switch (or when a stale self_user_id was captured by a
        // previous install), the locked-in value can disagree with the
        // active account — reconcile by adopting active as the new self.
        NSString *activeUserId  = KIOUActiveAccountUserId();
        NSString *configuredSelf = KIOUSelfUserId();
        if (activeUserId.length > 0 &&
            configuredSelf.length > 0 &&
            ![activeUserId isEqualToString:configuredSelf]) {
            IPALog([NSString stringWithFormat:
                    @"[MATCH] refresh: field=selfUserId reason=stale from=%@ to=%@",
                    configuredSelf, activeUserId]);
            KIOUSetSelfUserId(activeUserId);
            configuredSelf = activeUserId;
        } else if (!configuredSelf && activeUserId.length > 0) {
            IPALog([NSString stringWithFormat:
                    @"[MATCH] applied: field=selfUserId source=active value=%@",
                    activeUserId]);
            KIOUSetSelfUserId(activeUserId);
            configuredSelf = activeUserId;
        }
#endif
        BOOL isSelf;
        if (configuredSelf) {
            isSelf = [userId isEqualToString:configuredSelf];
        } else {
            // No locked-in self and no known active: assume the player
            // carrying SAFE_ID is us (SelectCharacter forces every outgoing
            // select to SAFE_ID).
            isSelf = (curSkinId == KIOU_SAFE_SKIN_ID);
        }

        if (!isSelf) {
            IPALog([NSString stringWithFormat:
                    @"[MATCH] skipped: reason=nonSelf userId=%@ skin=%d char=%d",
                    userId, curSkinId, curCharId]);
            return;
        }

        // First-ever heuristic hit: lock the UUID in so subsequent matches
        // (including PvP where both players might wear SAFE_ID) use a
        // strict userId comparison instead of the skin-based guess.
#if KIOU_HOOK_TARGET_BUILD < 22
        if (!configuredSelf) {
            KIOUSetSelfUserId(userId);
            IPALog([NSString stringWithFormat:
                    @"[MATCH] applied: field=selfUserId source=heuristic userId=%@ next=strict",
                    userId]);
        }
#endif

        // Force assist-on for self, even when the CPU-match toggle is off.
        // Done regardless of whether a persisted skin override is active.
        if (KIOUEditorFeatureEnabled(KIOU_FEATURE_MATCH_ASSIST)) {
            uint8_t curBSE = readU8(self, OFF_MP_ENABLE_BEGINNER_SUPPORT);
            if (curBSE != 1) {
                writeU8(self, OFF_MP_ENABLE_BEGINNER_SUPPORT, 1);
                IPALog([NSString stringWithFormat:
                        @"[MATCH] applied: field=enableBeginnerSupport value=%d->1 scope=self",
                        (int)curBSE]);
            }
        }

        // Skin / character rewrite gated on a persisted SelectCharacter pick.
        if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_CHAR_BYPASS)) return;
        int32_t target = KIOUEditorPersistedSelection();
        if (target == 0) return;
        int32_t targetChar = charIdForSkinId(target);
        if (curSkinId == target && curCharId == targetChar) return;

        writeI32(self, OFF_MP_MST_SKIN_ID, target);
        writeI32(self, OFF_MP_MST_CHAR_ID, targetChar);

        IPALog([NSString stringWithFormat:
                @"[MATCH] applied: userId=%@ skin=%d->%d char=%d->%d selfLocked=%@",
                userId, curSkinId, target, curCharId, targetChar,
                configuredSelf ? @"YES" : @"NO->YES"]);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[MATCH] exception: error=%@", e]);
    }
}

void KIOUEditorInstallMatchingPlayerHook(uintptr_t unityBase) {
    s_origMatchingPlayer_merge = (ReplyMergeFrom_t)KIOUHookInstall(
        KIOU_HOOK_NAME_MATCHING_PLAYER_MERGE,
        (void *)hook_MatchingPlayer_merge, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_MATCHING_PLAYER_MERGE, hook_MatchingPlayer_merge);
#if KIOU_HOOK_TARGET_BUILD >= 22
    NSString *configured = KIOUActiveAccountOpenId();
#else
    NSString *configured = KIOUSelfUserId();
#endif
    IPALog([NSString stringWithFormat:
            @"[MATCH] installed: orig=%p selfUserId=%@",
            (void *)s_origMatchingPlayer_merge,
            configured ?: @"(unset, using heuristic)"]);
}
