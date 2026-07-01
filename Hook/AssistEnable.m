#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/AssistEnable.m — ResolvedBeginnerSupport gate overrides.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_AssistEnable.m.
//
// GameSetup.BeginnerSupport is a ResolvedBeginnerSupport struct whose
// Enabled bool gates whether GameOrchestrator wires the in-game
// BeginnerSupportEvaluator + BookHintProvider into BoardPresenter /
// EffectPresenter. In modes where the assist isn't normally offered
// (e.g. ranked) the resolved struct comes back with Enabled = false and
// the evaluator/provider stay unused.
//
// The depth override here is belt-and-braces; the BSE itself is also
// pinned by Hook/AssistTune (depth=16, skillLevel=20). Whichever path
// the engine uses, it lands on the same number.
// ===========================================================================

typedef bool    (*BSupportGetBool_t)(void *self);
typedef int32_t (*BSupportGetI32_t)(void *self);

static BSupportGetBool_t s_origRBS_getEnabled = NULL;
static BSupportGetI32_t  s_origRBS_getDepth   = NULL;

static bool hook_RBS_getEnabled(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_ASSIST_ENABLE)) {
        return s_origRBS_getEnabled ? s_origRBS_getEnabled(self) : false;
    }
    (void)self;
    return true;
}

static int32_t hook_RBS_getDepth(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_ASSIST_ENABLE)) {
        return s_origRBS_getDepth ? s_origRBS_getDepth(self) : 0;
    }
    (void)self;
    return KIOUEditorAssistDepth();
}

void KIOUEditorInstallAssistEnableHook(uintptr_t unityBase) {
    s_origRBS_getEnabled = (BSupportGetBool_t)KIOUHookInstall(
        KIOU_HOOK_NAME_RBSUPPORT_GET_ENABLED,
        (void *)hook_RBS_getEnabled, unityBase);
    s_origRBS_getDepth = (BSupportGetI32_t)KIOUHookInstall(
        KIOU_HOOK_NAME_RBSUPPORT_GET_DEPTH,
        (void *)hook_RBS_getDepth, unityBase);
    IPALog([NSString stringWithFormat:
            @"[ASSIST-EN] installed: get_Enabled orig=%p get_Depth orig=%p (depth=%d)",
            (void *)s_origRBS_getEnabled, (void *)s_origRBS_getDepth,
            (int)KIOUEditorAssistDepth()]);
}
