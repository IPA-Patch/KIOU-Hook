#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/AssistTune.m — BeginnerSupportEvaluator parameter override.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_AssistTune.m.
//
// The evaluator was rebuilt in KIOU 1.1.0 (build 15). Up to 1.0.2 it ran
// an Rshogi NNUE search, so the knobs were search depth, engine skill
// level, and transposition-table size. From 1.1.0 it runs a policy-model
// inference (PolicyEngine.PolicyTopK) and those three no longer exist —
// what is left is how many candidate moves the policy head returns.
//
// Hooks, by target:
//
//   A) BSE.ctor — both eras. Let orig run (it allocates caches, captures
//      the model/eval path and reads the ScriptableObject), then widen
//      the assist:
//        <= 1.0.2  +0x18 _analysisDepth    -> KIOUEditorAssistDepth()
//                  +0x28 _engineSkillLevel -> KIOUEditorAssistSkillLevel()
//        >= 1.1.0  +0x18 _normalHintTopN   -> KIOUEditorAssistTopN()
//                  +0x1C _firstHintTopN    -> KIOUEditorAssistTopN()
//
//   B) BSE.EnsureInitializedLocked — <= 1.0.2 only. The lazy bring-up that
//      allocates the NativeSyncSession into _session (+0x38) on the first
//      EvaluateAsync. Nothing in the retail path calls SetHashSize, so
//      Rshogi ran on its tiny default; we piggy-back here to size the TT
//      once the session pointer is live. 1.1.0 removed the method (and the
//      session), so there is nothing to hook and no hash size to set.
//
// The direct SetHashSize call site is looked up via
// KIOUHookSiteAddr(KIOU_HOOK_NAME_NSS_SETHASHSIZE_DIRECT) — hook_id=-1 in
// the catalog, so it isn't installed as a hook, just resolved as a raw
// function pointer.
// ===========================================================================

#define KIOU_ASSIST_POLICY_ERA  (KIOU_HOOK_TARGET_BUILD >= 15)

#if KIOU_ASSIST_POLICY_ERA
#define OFF_BSE_NORMAL_HINT_TOPN     0x18
#define OFF_BSE_FIRST_HINT_TOPN      0x1C
#else
#define OFF_BSE_ANALYSIS_DEPTH       0x18
#define OFF_BSE_ENGINE_SKILL_LEVEL   0x28
#define OFF_BSE_SESSION              0x38
#endif

typedef void (*BSECtor_t)(void *self, void *modelPath, void *settings);
typedef void (*BSEEvaluateAsync_t)(void *self, void *position, void *methodInfo);

static BSECtor_t          s_origBSE_ctor           = NULL;
static BSEEvaluateAsync_t s_origBSE_evaluateAsync  = NULL;
static uintptr_t          g_unityBaseForAssist     = 0;

#if !KIOU_ASSIST_POLICY_ERA
typedef void (*BSEEnsureInit_t)(void *self);
typedef void (*NSS_SetHashSize_directABI_t)(void *thisSession, int32_t mb, void *methodInfo);

static BSEEnsureInit_t    s_origBSE_ensureInit     = NULL;
#endif

static void hook_BSE_ctor(void *self, void *modelPath, void *settings) {
    if (s_origBSE_ctor) {
        s_origBSE_ctor(self, modelPath, settings);
    }
    // Feed the consumer the raw path il2cpp String* so it can spin up a
    // diagnostic USI session against the same weights. Consumer-side guard
    // ensures the dump only fires once per boot.
    KIOUEditorNotifyBseEvalPath(modelPath);
    // Tune evaluator parameters regardless of ASSIST_ENABLE; the user
    // controls the engaged hint arrow via that flag in Hook/AssistEnable.
    if (!ptrLooksValid(self)) return;
    @try {
#if KIOU_ASSIST_POLICY_ERA
        int32_t targetTopN = KIOUEditorAssistTopN();
        int32_t origNormal = readI32(self, OFF_BSE_NORMAL_HINT_TOPN);
        int32_t origFirst  = readI32(self, OFF_BSE_FIRST_HINT_TOPN);
        if (origNormal != targetTopN) {
            writeI32(self, OFF_BSE_NORMAL_HINT_TOPN, targetTopN);
        }
        if (origFirst != targetTopN) {
            writeI32(self, OFF_BSE_FIRST_HINT_TOPN, targetTopN);
        }
        IPALog([NSString stringWithFormat:
                @"[ASSIST-TUNE] applied: scope=bseCtor normalTopN=%d->%d firstTopN=%d->%d",
                origNormal, targetTopN, origFirst, targetTopN]);
#else
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
                @"[ASSIST-TUNE] applied: scope=bseCtor depth=%d->%d skillLevel=%d->%d",
                origDepth, targetDepth, origSkill, targetSkill]);
#endif
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[ASSIST-TUNE] exception: scope=bseCtor error=%@", e]);
    }
}

#if !KIOU_ASSIST_POLICY_ERA
// Cache the (session, mb) tuple we last programmed so EnsureInitializedLocked
// firing on every EvaluateAsync doesn't re-zero the transposition table each
// move. Reallocating 256 MB per move stalls the render loop far more than the
// search itself. When session ptr rolls over (new BSE instance) or the user
// changes the hashMB setting, we reprogram; otherwise skip.
static void *   s_lastSizedSession = NULL;
static int32_t  s_lastSizedMB      = 0;

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
        int32_t mb = KIOUEditorAssistHashMB();
        if (session == s_lastSizedSession && mb == s_lastSizedMB) {
            // Already programmed on this session at this MB — skip. Prevents
            // per-move TT re-zero storms flagged in FrameworkPassthrough logs.
            return;
        }
        uintptr_t setHashAddr = KIOUHookSiteAddr(
            KIOU_HOOK_NAME_NSS_SETHASHSIZE_DIRECT, g_unityBaseForAssist);
        if (setHashAddr == 0) {
            IPALog(@"[ASSIST-TUNE] skipped: reason=setHashSizeSiteUnresolved");
            return;
        }
        NSS_SetHashSize_directABI_t setHash =
            (NSS_SetHashSize_directABI_t)setHashAddr;
        setHash(session, mb, NULL);
        s_lastSizedSession = session;
        s_lastSizedMB      = mb;
        IPALog([NSString stringWithFormat:
                @"[ASSIST-TUNE] applied: scope=ensureInitializedLocked hashSizeMB=%d session=%p",
                mb, session]);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[ASSIST-TUNE] exception: scope=ensureInitializedLocked error=%@", e]);
    }
}
#endif  // !KIOU_ASSIST_POLICY_ERA

// BSE.EvaluateAsync — drop the on-device NNUE evaluation entirely when the
// user has KIOU_FEATURE_INGAME_ANALYSIS off. The BSE object stays allocated
// so surrounding lifecycle code is unaffected; only the expensive search
// path is suppressed, which quiets the CPU and prevents device heating.
static void hook_BSE_evaluate_async(void *self, void *position, void *methodInfo) {
    BOOL gate = KIOUEditorFeatureEnabled(KIOU_FEATURE_INGAME_ANALYSIS);
    IPALog([NSString stringWithFormat:
            @"[BSE] evaluate: enter gate=%d self=%p position=%p origResolved=%d",
            (int)gate, self, position, s_origBSE_evaluateAsync != NULL]);
    if (!gate) {
        return;
    }
    if (s_origBSE_evaluateAsync) {
        s_origBSE_evaluateAsync(self, position, methodInfo);
    }
}

void KIOUEditorInstallAssistTuneHook(uintptr_t unityBase) {
    g_unityBaseForAssist = unityBase;
    s_origBSE_ctor = (BSECtor_t)KIOUHookInstall(
        KIOU_HOOK_NAME_BSE_CTOR,
        (void *)hook_BSE_ctor, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_BSE_CTOR, hook_BSE_ctor);
#if !KIOU_ASSIST_POLICY_ERA
    s_origBSE_ensureInit = (BSEEnsureInit_t)KIOUHookInstall(
        KIOU_HOOK_NAME_BSE_ENSURE_INITIALIZED,
        (void *)hook_BSE_ensureInit, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_BSE_ENSURE_INITIALIZED, hook_BSE_ensureInit);
#endif
    s_origBSE_evaluateAsync = (BSEEvaluateAsync_t)KIOUHookInstall(
        KIOU_HOOK_NAME_BSE_EVALUATE_ASYNC,
        (void *)hook_BSE_evaluate_async, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_BSE_EVALUATE_ASYNC, hook_BSE_evaluate_async);
#if KIOU_ASSIST_POLICY_ERA
    IPALog([NSString stringWithFormat:
            @"[ASSIST-TUNE] installed: engine=policy bseCtorOrig=%p "
            @"evaluateAsyncOrig=%p topN=%d ingameAnalysisGate=%d",
            (void *)s_origBSE_ctor, (void *)s_origBSE_evaluateAsync,
            (int)KIOUEditorAssistTopN(),
            (int)KIOUEditorFeatureEnabled(KIOU_FEATURE_INGAME_ANALYSIS)]);
#else
    IPALog([NSString stringWithFormat:
            @"[ASSIST-TUNE] installed: engine=nnue bseCtorOrig=%p ensureInitOrig=%p "
            @"evaluateAsyncOrig=%p depth=%d skill=%d hashMB=%d "
            @"ingameAnalysisGate=%d",
            (void *)s_origBSE_ctor, (void *)s_origBSE_ensureInit,
            (void *)s_origBSE_evaluateAsync,
            (int)KIOUEditorAssistDepth(), (int)KIOUEditorAssistSkillLevel(),
            (int)KIOUEditorAssistHashMB(),
            (int)KIOUEditorFeatureEnabled(KIOU_FEATURE_INGAME_ANALYSIS)]);
#endif
}
