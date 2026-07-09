#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/AssistTune.m — BeginnerSupportEvaluator parameter override.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_AssistTune.m.
//
// Two hooks:
//
//   A) BSE.ctor — public void .ctor(string evalPath, BeginnerSupportSettings)
//      Let orig run (it allocates caches, captures eval path, reads the
//      ScriptableObject), then overwrite:
//        +0x18 _analysisDepth     -> KIOUEditorAssistDepth()    (default 16)
//        +0x28 _engineSkillLevel  -> KIOUEditorAssistSkillLevel() (default 20)
//
//   B) BSE.EnsureInitializedLocked — the lazy bring-up that allocates the
//      Rshogi NativeSyncSession into _session (+0x38) on the first
//      EvaluateAsync. Nothing in the retail path calls
//      NativeSyncSession.SetHashSize, so Rshogi runs on its tiny default.
//      Piggy-back here: once orig finishes and the session pointer is
//      live, invoke SetHashSize(MB) via direct ABI.
//
// The direct SetHashSize call site is looked up via
// KIOUHookSiteAddr(KIOU_HOOK_NAME_NSS_SETHASHSIZE_DIRECT) — hook_id=-1 in
// the catalog, so it isn't installed as a hook, just resolved as a raw
// function pointer.
// ===========================================================================

#define OFF_BSE_ANALYSIS_DEPTH       0x18
#define OFF_BSE_ENGINE_SKILL_LEVEL   0x28
#define OFF_BSE_SESSION              0x38

typedef void (*BSECtor_t)(void *self, void *evalPath, void *settings);
typedef void (*BSEEnsureInit_t)(void *self);
typedef void (*NSS_SetHashSize_directABI_t)(void *thisSession, int32_t mb, void *methodInfo);

static BSECtor_t       s_origBSE_ctor        = NULL;
static BSEEnsureInit_t s_origBSE_ensureInit  = NULL;
static uintptr_t       g_unityBaseForAssist  = 0;

static void hook_BSE_ctor(void *self, void *evalPath, void *settings) {
    if (s_origBSE_ctor) {
        s_origBSE_ctor(self, evalPath, settings);
    }
    // Tune evaluator parameters regardless of ASSIST_ENABLE; the user
    // controls the engaged hint arrow via that flag in Hook/AssistEnable.
    if (!ptrLooksValid(self)) return;
    @try {
        int32_t targetDepth = KIOUEditorAssistDepth();
        int32_t targetSkill = KIOUEditorAssistSkillLevel();
        int32_t origDepth = readI32(self, OFF_BSE_ANALYSIS_DEPTH);
        int32_t origSkill = readI32(self, OFF_BSE_ENGINE_SKILL_LEVEL);
        if (origDepth != targetDepth) {
            writeI32(self, OFF_BSE_ANALYSIS_DEPTH, targetDepth);
        }
        if (origSkill != targetSkill) {
            writeI32(self, OFF_BSE_ENGINE_SKILL_LEVEL, targetSkill);
        }
        IPALog([NSString stringWithFormat:
                @"[ASSIST-TUNE] BSE tuned: depth %d -> %d, skillLevel %d -> %d",
                origDepth, targetDepth, origSkill, targetSkill]);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[ASSIST-TUNE] BSE ctor override exception: %@", e]);
    }
}

static void hook_BSE_ensureInit(void *self) {
    if (s_origBSE_ensureInit) {
        s_origBSE_ensureInit(self);
    }
    if (!ptrLooksValid(self) || g_unityBaseForAssist == 0) return;
    @try {
        void *session = readPtr(self, OFF_BSE_SESSION);
        if (!session) {
            // Orig didn't bring the session up (eval path missing, etc.).
            // Nothing to size; let the next EvaluateAsync retry.
            return;
        }
        uintptr_t setHashAddr = KIOUHookSiteAddr(
            KIOU_HOOK_NAME_NSS_SETHASHSIZE_DIRECT, g_unityBaseForAssist);
        if (setHashAddr == 0) {
            IPALog(@"[ASSIST-TUNE] SetHashSize site unresolved — skipping");
            return;
        }
        int32_t mb = KIOUEditorAssistHashMB();
        NSS_SetHashSize_directABI_t setHash =
            (NSS_SetHashSize_directABI_t)setHashAddr;
        setHash(session, mb, NULL);
        IPALog([NSString stringWithFormat:
                @"[ASSIST-TUNE] EnsureInitializedLocked: SetHashSize(%d) ok session=%p",
                mb, session]);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[ASSIST-TUNE] EnsureInitializedLocked SetHashSize exception: %@", e]);
    }
}

void KIOUEditorInstallAssistTuneHook(uintptr_t unityBase) {
    g_unityBaseForAssist = unityBase;
    s_origBSE_ctor = (BSECtor_t)KIOUHookInstall(
        KIOU_HOOK_NAME_BSE_CTOR,
        (void *)hook_BSE_ctor, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_BSE_CTOR, hook_BSE_ctor);
    s_origBSE_ensureInit = (BSEEnsureInit_t)KIOUHookInstall(
        KIOU_HOOK_NAME_BSE_ENSURE_INITIALIZED,
        (void *)hook_BSE_ensureInit, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_BSE_ENSURE_INITIALIZED, hook_BSE_ensureInit);
    IPALog([NSString stringWithFormat:
            @"[ASSIST-TUNE] installed: BSE.ctor orig=%p EnsureInit orig=%p "
            @"(depth=%d skill=%d hash=%d MB)",
            (void *)s_origBSE_ctor, (void *)s_origBSE_ensureInit,
            (int)KIOUEditorAssistDepth(), (int)KIOUEditorAssistSkillLevel(),
            (int)KIOUEditorAssistHashMB()]);
}
