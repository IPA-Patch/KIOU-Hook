#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/Common.m — shared state for KiouEditor-derived hook bodies.
//
// Contains ONLY definitions that are logically KIOU-Hook-side (reentrancy
// guard, SelectCharacter persistence, list rewrite helper). Feature-flag
// storage and assist-tuning storage stay in the consumer tweak because
// they're UI-driven; Common.h externs them so hook bodies compile.
//
// FriendUnhide's il2cpp-bridge helpers (KIOUEditorReconButtonImage /
// KIOUEditorApplyTitleSpriteToClone) get temporary no-op definitions
// here so PR-A2 links. They're replaced by the real definitions when
// Hook/FriendUnhide.m lands.
// ===========================================================================

// ---------------------------------------------------------------------------
// Reentrancy guard. Owned by Common now, not the consumer's Tweak.m.
// ---------------------------------------------------------------------------

volatile int g_inHook = 0;

// ---------------------------------------------------------------------------
// SelectCharacter persistence (moved from KiouEditor's
// Sources/KiouEditor/Hook_SelectCharacter.m).
//
// The server only ever sees KIOU_SAFE_SKIN_ID being equipped; the user's
// intended skin id is kept on-device in NSUserDefaults and stitched back
// into is_selected entries in every relevant reply.
//
// Key preserved to survive the KIOU-Hook migration on existing installs.
// ---------------------------------------------------------------------------

static NSString *const kPersistedSelectionKey = @"kiou_editor.persisted_skin_id";

int32_t KIOUEditorPersistedSelection(void) {
    NSInteger v = [[NSUserDefaults standardUserDefaults]
                   integerForKey:kPersistedSelectionKey];
    if (v <= 0 || v > 100000) return 0;
    return (int32_t)v;
}

void KIOUEditorSetPersistedSelection(int32_t skinId) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (skinId <= 0) {
        [d removeObjectForKey:kPersistedSelectionKey];
    } else {
        [d setInteger:skinId forKey:kPersistedSelectionKey];
    }
    [d synchronize];
}

// ---------------------------------------------------------------------------
// Character + skin list rewrite. Shared with Hook/SyncItemList.
//
// Hybrid strategy:
//   - If the target id already exists in the list (e.g. SyncItemList full
//     inventory): MOVE the is_selected flag onto that entry. Avoids
//     duplicate ids which broke client-side validation (the "tap to start"
//     generic error).
//   - Else (e.g. SelectCharacterReply partial list that only carries the
//     SAFE_ID swap result): REWRITE the currently-selected entry's id to
//     target. Best-effort UI override when no target entry is in the list.
// ---------------------------------------------------------------------------

#define OFF_CHAR_MST_ID          0x18
#define OFF_CHAR_IS_ACQUIRED     0x30
#define OFF_CHAR_IS_SELECTED     0x45

#define OFF_SKIN_MST_SKIN_ID     0x18
#define OFF_SKIN_MST_CHAR_ID     0x1C
#define OFF_SKIN_IS_ACQUIRED     0x20
#define OFF_SKIN_IS_SELECTED     0x21

void KIOUEditorApplyPersistedSelectionToLists(void *charArr, int32_t charCount,
                                        void *skinArr, int32_t skinCount) {
    int32_t target = KIOUEditorPersistedSelection();
    if (target == 0) return;  // no override active

    int32_t flagMoves = 0;
    int32_t idRewrites = 0;

    {
        int32_t curIdx = -1, tgtIdx = -1;
        for (int32_t i = 0; i < skinCount; i++) {
            void *elem = readArrayElem(skinArr, i);
            if (!elem) continue;
            if (readU8(elem, OFF_SKIN_IS_SELECTED) == 1) curIdx = i;
            if (readI32(elem, OFF_SKIN_MST_SKIN_ID) == target) tgtIdx = i;
        }
        if (tgtIdx >= 0) {
            if (curIdx != tgtIdx) {
                if (curIdx >= 0) {
                    writeU8(readArrayElem(skinArr, curIdx),
                            OFF_SKIN_IS_SELECTED, 0);
                }
                void *tgt = readArrayElem(skinArr, tgtIdx);
                writeU8(tgt, OFF_SKIN_IS_SELECTED, 1);
                if (readU8(tgt, OFF_SKIN_IS_ACQUIRED) == 0) {
                    writeU8(tgt, OFF_SKIN_IS_ACQUIRED, 1);
                }
                flagMoves++;
            }
        } else if (curIdx >= 0) {
            void *cur = readArrayElem(skinArr, curIdx);
            writeI32(cur, OFF_SKIN_MST_SKIN_ID, target);
            writeI32(cur, OFF_SKIN_MST_CHAR_ID, target);
            if (readU8(cur, OFF_SKIN_IS_ACQUIRED) == 0) {
                writeU8(cur, OFF_SKIN_IS_ACQUIRED, 1);
            }
            idRewrites++;
        }
    }

    {
        int32_t curIdx = -1, tgtIdx = -1;
        for (int32_t i = 0; i < charCount; i++) {
            void *elem = readArrayElem(charArr, i);
            if (!elem) continue;
            if (readU8(elem, OFF_CHAR_IS_SELECTED) == 1) curIdx = i;
            if (readI32(elem, OFF_CHAR_MST_ID) == target) tgtIdx = i;
        }
        if (tgtIdx >= 0) {
            if (curIdx != tgtIdx) {
                if (curIdx >= 0) {
                    writeU8(readArrayElem(charArr, curIdx),
                            OFF_CHAR_IS_SELECTED, 0);
                }
                void *tgt = readArrayElem(charArr, tgtIdx);
                writeU8(tgt, OFF_CHAR_IS_SELECTED, 1);
                if (readU8(tgt, OFF_CHAR_IS_ACQUIRED) == 0) {
                    writeU8(tgt, OFF_CHAR_IS_ACQUIRED, 1);
                }
                flagMoves++;
            }
        } else if (curIdx >= 0) {
            void *cur = readArrayElem(charArr, curIdx);
            writeI32(cur, OFF_CHAR_MST_ID, target);
            if (readU8(cur, OFF_CHAR_IS_ACQUIRED) == 0) {
                writeU8(cur, OFF_CHAR_IS_ACQUIRED, 1);
            }
            idRewrites++;
        }
    }

    if (flagMoves > 0 || idRewrites > 0) {
        IPALog([NSString stringWithFormat:
                @"[SELECT] applied persisted skinId=%d (flag_moves=%d id_rewrites=%d)",
                target, flagMoves, idRewrites]);
    }
}

// ---------------------------------------------------------------------------
// FriendUnhide sprite helpers — stubs. The real definitions arrive with
// Hook/FriendUnhide.m in the follow-up PR. Logs when called so the stub
// is visible in the field.
// ---------------------------------------------------------------------------

__attribute__((weak))
void KIOUEditorReconButtonImage(void *uiButton, const char *tag) {
    (void)uiButton;
    IPALog([NSString stringWithFormat:
            @"[COMMON] KIOUEditorReconButtonImage stub called (tag=%s) — "
            @"FriendUnhide not yet ported",
            tag ? tag : "(null)"]);
}

__attribute__((weak))
void KIOUEditorApplyTitleSpriteToClone(void *cloneGo) {
    (void)cloneGo;
    IPALog(@"[COMMON] KIOUEditorApplyTitleSpriteToClone stub called — "
           @"FriendUnhide not yet ported");
}

// Consumer-provided UIKit settings presenter. Real definition lives in
// the tweak's own SettingsUI.m; this stub logs and no-ops so KIOU-Hook
// links standalone when a consumer pulls in Hook/FriendUnhide.m but
// hasn't wired the UIKit side yet.
__attribute__((weak))
void KIOUEditorPresentSettings(void) {
    IPALog(@"[COMMON] KIOUEditorPresentSettings stub called — "
           @"consumer tweak did not wire the UIKit settings surface");
}

// ---------------------------------------------------------------------------
// Feature-flag / assist-tuning fallbacks. Consumer tweaks (KiouEditor) own
// the real storage — settings UI, NSUserDefaults, defaults. These weak
// stubs let KIOU-Hook-side hook bodies link cleanly against consumers
// that don't wire the API (typical during compile-test from KiouForge,
// which cherry-picks these .m files but never installs the hooks).
//
// Every stub is safe-by-default:
//   - features return false so hooks fall through to orig() and behave
//     like vanilla even if a consumer forgets an installer guard
//   - assist getters return the same defaults KiouEditor's Persistence.m
//     uses (depth=16, skillLevel=20, hash=128 MB)
//
// A consumer that provides a strong symbol wins.
// ---------------------------------------------------------------------------

__attribute__((weak))
bool KIOUEditorFeatureEnabled(KiouFeature f) {
    (void)f;
    return false;
}

__attribute__((weak))
void KIOUEditorSetFeatureEnabled(KiouFeature f, bool enabled) {
    (void)f; (void)enabled;
}

__attribute__((weak))
NSString *KIOUEditorFeatureLabel(KiouFeature f) {
    switch (f) {
    case KIOU_FEATURE_ITEM_UNLOCK:    return @"Item Unlock";
    case KIOU_FEATURE_CHAR_BYPASS:    return @"Character Bypass";
    case KIOU_FEATURE_PREMIUM_UNLOCK: return @"Premium Unlock";
    case KIOU_FEATURE_MATCH_ASSIST:   return @"Match Assist";
    case KIOU_FEATURE_VOICE_UNLOCK:   return @"Voice Unlock";
    case KIOU_FEATURE_ASSIST_ENABLE:  return @"Assist Enable";
    case KIOU_FEATURE_DISABLE_AFK:    return @"Disable AFK";
    case KIOU_FEATURE_INGAME_ANALYSIS:    return @"In-Game Analysis";
    case KIOU_FEATURE_AI_SPECIAL_SUPPORT: return @"AI Special Support";
    default:                          return @"(unknown)";
    }
}

__attribute__((weak)) int32_t KIOUEditorAssistDepth(void)      { return 16; }
__attribute__((weak)) void    KIOUEditorSetAssistDepth(int32_t v) { (void)v; }
__attribute__((weak)) int32_t KIOUEditorAssistSkillLevel(void) { return 20; }
__attribute__((weak)) void    KIOUEditorSetAssistSkillLevel(int32_t v) { (void)v; }
__attribute__((weak)) int32_t KIOUEditorAssistHashIndex(void)  { return 1; }
__attribute__((weak)) void    KIOUEditorSetAssistHashIndex(int32_t idx) { (void)idx; }
__attribute__((weak)) int32_t KIOUEditorAssistHashMB(void)     { return 128; }
