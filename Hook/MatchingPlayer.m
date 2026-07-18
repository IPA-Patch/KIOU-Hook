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
// Fields:
//   +0x18 userId            (il2cpp String*)
//   +0x30 mstIconId         (int32)
//   +0x38 mstCharacterId    (int32) <- rewritten
//   +0x40 mstCharacterSkinId(int32) <- rewritten
//   +0x68 enableBeginnerSupport (bool) <- forced to 1 for self
//
// We rewrite ONLY mstCharacterId + mstCharacterSkinId. Icon / frame /
// title / piece / board / BGM are decorations the user actually owns
// server-side, so touching them here would diverge from the server's
// real state.
// ===========================================================================

#define OFF_MP_USER_ID                 0x18
#define OFF_MP_MST_CHAR_ID             0x38
#define OFF_MP_MST_SKIN_ID             0x40
#define OFF_MP_ENABLE_BEGINNER_SUPPORT 0x68

static NSString *const kCpuUserIdSentinel = @"cpu";

typedef void (*ReplyMergeFrom_t)(void *self, void *parseContext);

static ReplyMergeFrom_t s_origMatchingPlayer_merge = NULL;

static void hook_MatchingPlayer_merge(void *self, void *parseContext) {
    if (s_origMatchingPlayer_merge) {
        s_origMatchingPlayer_merge(self, parseContext);
    }
    if (!ptrLooksValid(self)) return;

    @try {
        void *userIdStr = readPtr(self, OFF_MP_USER_ID);
        NSString *userId = il2cppStringToNSString(userIdStr);
        if (userId.length == 0) return;
        if ([userId isEqualToString:kCpuUserIdSentinel]) return;

        int32_t curSkinId = readI32(self, OFF_MP_MST_SKIN_ID);
        int32_t curCharId = readI32(self, OFF_MP_MST_CHAR_ID);

        NSString *configuredSelf = KIOUSelfUserId();
        BOOL isSelf;
        if (configuredSelf) {
            isSelf = [userId isEqualToString:configuredSelf];
        } else {
            // No locked-in self: assume the player carrying SAFE_ID is us
            // (SelectCharacter forces every outgoing select to SAFE_ID).
            isSelf = (curSkinId == KIOU_SAFE_SKIN_ID);
        }

        if (!isSelf) {
            IPALog([NSString stringWithFormat:
                    @"[MATCH] skip non-self userId=%@ skin=%d char=%d",
                    userId, curSkinId, curCharId]);
            return;
        }

        // First-ever heuristic hit: lock the UUID in so subsequent matches
        // (including PvP where both players might wear SAFE_ID) use a
        // strict userId comparison instead of the skin-based guess.
        if (!configuredSelf) {
            KIOUSetSelfUserId(userId);
            IPALog([NSString stringWithFormat:
                    @"[MATCH] self_user_id captured: %@ (heuristic -> strict)",
                    userId]);
        }

        // Force assist-on for self, even when the CPU-match toggle is off.
        // Done regardless of whether a persisted skin override is active.
        if (KIOUEditorFeatureEnabled(KIOU_FEATURE_MATCH_ASSIST)) {
            uint8_t curBSE = readU8(self, OFF_MP_ENABLE_BEGINNER_SUPPORT);
            if (curBSE != 1) {
                writeU8(self, OFF_MP_ENABLE_BEGINNER_SUPPORT, 1);
                IPALog([NSString stringWithFormat:
                        @"[MATCH] enableBeginnerSupport %d -> 1 (self)",
                        (int)curBSE]);
            }
        }

        // Skin / character rewrite gated on a persisted SelectCharacter pick.
        if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_CHAR_BYPASS)) return;
        int32_t target = KIOUEditorPersistedSelection();
        if (target == 0) return;
        if (curSkinId == target && curCharId == target) return;

        writeI32(self, OFF_MP_MST_SKIN_ID, target);
        writeI32(self, OFF_MP_MST_CHAR_ID, target);  // 1:1 mapping skin <-> char

        IPALog([NSString stringWithFormat:
                @"[MATCH] self=%@ skin %d->%d char %d->%d (self_locked=%@)",
                userId, curSkinId, target, curCharId, target,
                configuredSelf ? @"YES" : @"NO->YES"]);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[MATCH] exception: %@", e]);
    }
}

void KIOUEditorInstallMatchingPlayerHook(uintptr_t unityBase) {
    s_origMatchingPlayer_merge = (ReplyMergeFrom_t)KIOUHookInstall(
        KIOU_HOOK_NAME_MATCHING_PLAYER_MERGE,
        (void *)hook_MatchingPlayer_merge, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_MATCHING_PLAYER_MERGE, hook_MatchingPlayer_merge);
    NSString *configured = KIOUSelfUserId();
    IPALog([NSString stringWithFormat:
            @"[MATCH] installed: orig=%p self_user_id=%@",
            (void *)s_origMatchingPlayer_merge,
            configured ?: @"(unset, using heuristic)"]);
}
