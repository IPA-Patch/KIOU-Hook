#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/AfkDisable.m — GameOrchestrator.IsAfkEnabled -> force false.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_AfkDisable.m.
//
// The in-game GameOrchestrator drives an AFK state machine: after ~60 s of
// no input the orchestrator pops a warning popup and ~15 s later starts
// ForceSurrenderByAfkAsync. All paths (Update / OnApplicationPause /
// OnApplicationFocus) gate through IsAfkEnabled(); suppressing that
// predicate disables the warning dialog AND the auto-surrender without
// rewiring any async state machine.
// ===========================================================================

typedef bool (*GameOrchestratorIsAfkEnabled_t)(void *self);

static GameOrchestratorIsAfkEnabled_t s_origGO_IsAfkEnabled = NULL;

static bool hook_GO_IsAfkEnabled(void *self) {
    if (KIOUEditorFeatureEnabled(KIOU_FEATURE_DISABLE_AFK)) {
        // Force-disable. Don't chain back — letting the engine re-evaluate
        // would just re-arm the same gate this hook is here to suppress.
        return false;
    }
    return s_origGO_IsAfkEnabled ? s_origGO_IsAfkEnabled(self) : true;
}

void KIOUEditorInstallAfkDisableHook(uintptr_t unityBase) {
    s_origGO_IsAfkEnabled = (GameOrchestratorIsAfkEnabled_t)KIOUHookInstall(
        KIOU_HOOK_NAME_GAME_ORCHESTRATOR_IS_AFK,
        (void *)hook_GO_IsAfkEnabled, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_GAME_ORCHESTRATOR_IS_AFK, hook_GO_IsAfkEnabled);
    IPALog([NSString stringWithFormat:
            @"[AFK] installed: orig=%p (toggled by KIOU_FEATURE_DISABLE_AFK)",
            (void *)s_origGO_IsAfkEnabled]);
}
