#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/VoiceUnlock.m — voice unlock, two-pronged.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_VoiceUnlock.m.
//
// (a) CharacterVoicePlayer.SatisfiesRule(VoiceRuleType) -> bool.
//     The playback-side chokepoint — called from TryPlay / PlayInternal
//     and from FindRule. Forcing it true lets the underlying cue actually
//     fire when we hand the button event through.
//
// (b) CharacterVoiceScrollerCellModel.get_IsLocked() -> bool.
//     The UI-side chokepoint — the cell model is constructed with
//     `isLocked` baked in from the player's SatisfiesRule check at the
//     moment the list was built. That snapshot is what drives the lock
//     badge and disables the _playVoiceButton via _isLockedSwitcher.
//     SatisfiesRule alone is not enough here, because the cell can be
//     built with the player created against a stale _intimacyLevel
//     snapshot. Pinning the getter to false re-enables the button and
//     hides the condition badge.
//
// VoiceRuleType:
//   Invalid=0 Unspecified=1 Default=2 Level1=3..Level5=7 Complete=8 Unused=9
// Rule 9 (Unused) is forwarded to orig SatisfiesRule because it means
// "no cue mapped" — flipping it would let TryPlay walk into a NULL cue
// handle. IsLocked has no such trap; the cue lookup still goes through
// SatisfiesRule.
// ===========================================================================

typedef bool (*SatisfiesRule_t)(void *self, int32_t rule);
typedef bool (*GetIsLocked_t)(void *self);

static SatisfiesRule_t s_origCharacterVoicePlayer_SatisfiesRule = NULL;
static GetIsLocked_t   s_origVoiceCellModel_get_IsLocked        = NULL;

static bool hook_CharacterVoicePlayer_SatisfiesRule(void *self, int32_t rule) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_VOICE_UNLOCK)) {
        return s_origCharacterVoicePlayer_SatisfiesRule
            ? s_origCharacterVoicePlayer_SatisfiesRule(self, rule) : false;
    }
    (void)self;
    // Unused (9) means "no cue exists" — flipping it would let TryPlay
    // walk into a NULL cue handle. Forward to orig so it returns false.
    if (rule == 9) {
        if (s_origCharacterVoicePlayer_SatisfiesRule) {
            return s_origCharacterVoicePlayer_SatisfiesRule(self, rule);
        }
        return false;
    }
    return true;
}

static bool hook_VoiceCellModel_get_IsLocked(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_VOICE_UNLOCK)) {
        return s_origVoiceCellModel_get_IsLocked
            ? s_origVoiceCellModel_get_IsLocked(self) : false;
    }
    (void)self;
    return false;
}

void KIOUEditorInstallVoiceUnlockHook(uintptr_t unityBase) {
    s_origCharacterVoicePlayer_SatisfiesRule = (SatisfiesRule_t)KIOUHookInstall(
        KIOU_HOOK_NAME_VOICE_PLAYER_SATISFIES,
        (void *)hook_CharacterVoicePlayer_SatisfiesRule, unityBase);
    s_origVoiceCellModel_get_IsLocked = (GetIsLocked_t)KIOUHookInstall(
        KIOU_HOOK_NAME_VOICE_CELL_GET_IS_LOCKED,
        (void *)hook_VoiceCellModel_get_IsLocked, unityBase);
    IPALog([NSString stringWithFormat:
            @"[VOICE] installed: SatisfiesRule orig=%p CellModel.get_IsLocked orig=%p",
            (void *)s_origCharacterVoicePlayer_SatisfiesRule,
            (void *)s_origVoiceCellModel_get_IsLocked]);
}
