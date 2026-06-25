#pragma once

#import <Foundation/Foundation.h>
#import <stdint.h>

// ===========================================================================
// KIOUHook.h — KIOU binary catalog (RVAs, hook-id enum, cave geometry) and
// dispatcher externs shared by every consumer tweak. Keep this file free of
// Chinlan-specific includes so it stays compilable in isolation; consumers
// import il2cpp.h / logging.h / chinlan.h explicitly in the .m files that
// need them.
//
// Pair-of-truth note: the `enum kiou_kf_hook_id` and `KIOU_KF_SITE_RVA_*`
// macros mirror `recipes/common.py` HOOK_IDS and the per-version SITES
// tables. Update both sides together.
//
// Hook authors should NOT reference the enum or RVA macros directly. Use
// the name-based API below (KIOUHookOrig / KIOUHookInstall / KIOUHookSiteAddr)
// keyed by KIOU_HOOK_NAME_* string constants instead. The enum + RVA macros
// stay public only because per-tweak ChinlanDispatcher.m needs them to
// publish the entry slot table and switch on hook_id.
// ===========================================================================

// ---------------------------------------------------------------------------
// Hook engine selection.
//
// IPA_CHINLAN is set by the consumer's chinlan build target. The catalog
// header pulls in the matching hook-engine header so consumer .m files can
// use MSHookFunction without an extra include.
// ---------------------------------------------------------------------------
#if IPA_CHINLAN
#import "chinlan.h"
#else
#import "hookengine.h"
#endif

// ---------------------------------------------------------------------------
// Cave geometry and dispatcher slot RVAs.
// ---------------------------------------------------------------------------

// Single observer-dispatcher slot. Every CAVE_OBSERVER cave loads this
// pointer, BLRs it with W6 = hook_id, and routes through dispatch_one.
#define KIOU_KF_HOOK_SLOT_RVA            0x8F90C80

// Entry-cave slot table. Slot N at +N*8 holds the function pointer the
// CAVE_ENTRY cave BLRs directly (no dispatcher).
#define KIOU_KF_ENTRY_SLOT_BASE_RVA      0x091E91B8

// Cave payload region (matches recipes/common.py + per-version CAVE_REGION).
#define KIOU_KF_CAVE_REGION_START        0x826F5E8
#define KIOU_KF_CAVE_SIZE                84
#define KIOU_KF_CAVE_BYPASS_OFFSET       (KIOU_KF_CAVE_SIZE - 8)

// ---------------------------------------------------------------------------
// Hook id enum — one row per cave site. CAVE_OBSERVER caves embed this id in
// the cave's MOVZ W6,#imm so dispatch_one can switch on it. CAVE_ENTRY caves
// don't dispatch by id, but they still get an enum entry so the bypass index
// (cave allocation order) matches the enum value.
//
// Hook authors: do NOT use these constants in hook bodies. Use
// KIOU_HOOK_NAME_* + KIOUHookOrig() instead. The enum is published so the
// per-tweak ChinlanDispatcher.m can switch on hook_id.
// ---------------------------------------------------------------------------
enum kiou_kf_hook_id {
    // Entry caves (route through entry slot table)
    KIOU_KF_HOOK_SET_TARGET_FRAMERATE = 0,
    KIOU_KF_HOOK_NSS_SETHASHSIZE,
    KIOU_KF_HOOK_NSS_SETSKILLEVEL,
    KIOU_KF_HOOK_NSS_SEARCHFULL,
    KIOU_KF_HOOK_ACCOUNT_EXISTS,
    KIOU_KF_HOOK_LOGIN_ARGS_CREATE,
    KIOU_KF_HOOK_REGISTER_USER_ARGS_CREATE,
    KIOU_KF_HOOK_RUN_LOGIN_SEQ_MOVENEXT,
    KIOU_KF_HOOK_GET_SELF_PROFILE_MOVENEXT,
    KIOU_KF_HOOK_HTTPMSGINVOKER_SEND_ASYNC,
    // Observer caves (routed by dispatch_one's switch)
    KIOU_KF_HOOK_KIFU_AI_END,
    KIOU_KF_HOOK_KIFU_CPUSTREAM_END,
    KIOU_KF_HOOK_KIFU_LOCAL_END,
    KIOU_KF_HOOK_KIFU_ONLINE_END,
    KIOU_KF_HOOK_KIFU_REPLAY_END,

    KIOU_KF_HOOK__COUNT,
};

// Entry-slot enum — one per CAVE_ENTRY row. Slot N's function pointer lives
// at unityBase + KIOU_KF_ENTRY_SLOT_BASE_RVA + N*8.
enum kiou_kf_entry_slot_id {
    KIOU_KF_ENTRY_SLOT_SET_TARGET_FRAMERATE = 0,
    KIOU_KF_ENTRY_SLOT_NSS_SETHASHSIZE,
    KIOU_KF_ENTRY_SLOT_NSS_SETSKILLEVEL,
    KIOU_KF_ENTRY_SLOT_NSS_SEARCHFULL,
    KIOU_KF_ENTRY_SLOT_ACCOUNT_EXISTS,
    KIOU_KF_ENTRY_SLOT_LOGIN_ARGS_CREATE,
    KIOU_KF_ENTRY_SLOT_REGISTER_USER_ARGS_CREATE,
    KIOU_KF_ENTRY_SLOT_RUN_LOGIN_SEQ_MOVENEXT,
    KIOU_KF_ENTRY_SLOT_GET_SELF_PROFILE_MOVENEXT,
    KIOU_KF_ENTRY_SLOT_HTTPMSGINVOKER_SEND_ASYNC,

    KIOU_KF_ENTRY_SLOT__COUNT,
};

// ---------------------------------------------------------------------------
// Site RVAs — used by KIOUHookSiteAddr to compute target addresses.
// Hook authors: don't reference these directly. Use KIOUHookSiteAddr(name).
// ---------------------------------------------------------------------------
#define KIOU_KF_SITE_RVA_SET_TARGET_FRAMERATE       0x6B718A4
#define KIOU_KF_SITE_RVA_GAME_ORCHESTRATOR_IS_AFK   0x594A034
#define KIOU_KF_SITE_RVA_NSS_SETHASHSIZE            0x5D379DC
#define KIOU_KF_SITE_RVA_NSS_SETSKILLEVEL           0x5D37968
#define KIOU_KF_SITE_RVA_NSS_SEARCHFULL             0x5D37A74
#define KIOU_KF_SITE_RVA_AI_END                     0x59EA720
#define KIOU_KF_SITE_RVA_CPUSTREAM_END              0x59F15D4
#define KIOU_KF_SITE_RVA_LOCAL_END                  0x5A046B4
#define KIOU_KF_SITE_RVA_ONLINE_END                 0x5A06158
#define KIOU_KF_SITE_RVA_REPLAY_END                 0x5A30320
#define KIOU_KF_SITE_RVA_ACCOUNT_EXISTS             0x5922CD0
#define KIOU_KF_SITE_RVA_LOGIN_ARGS_CREATE          0x5B9DC04
#define KIOU_KF_SITE_RVA_REGISTER_USER_ARGS_CREATE  0x5B9DC94
#define KIOU_KF_SITE_RVA_RUN_LOGIN_SEQ_MOVENEXT     0x58152BC
#define KIOU_KF_SITE_RVA_GET_SELF_PROFILE_MOVENEXT  0x5BB99DC
#define KIOU_KF_SITE_RVA_HTTPMSGINVOKER_SEND_ASYNC  0x6082AC0
#define KIOU_KF_SITE_RVA_BACK_TO_TITLE_RUN_ASYNC    0x5CFC394

// ---------------------------------------------------------------------------
// Dispatcher state — defined by the consumer's ChinlanDispatcher.m.
// ---------------------------------------------------------------------------

// Per-site cave-bypass addresses so hook bodies can call orig without
// re-entering the cave. Sized by KIOU_KF_HOOK__COUNT; unused slots stay zero.
#if IPA_CHINLAN
extern void * volatile g_inject_entry[KIOU_KF_HOOK__COUNT];
#endif

void KFChinlanPublish(uintptr_t unityBase);

// UnityFramework base captured at install time. Consumers set this in their
// Tweak entry point before any KIOU-Hook installer runs.
extern uintptr_t g_unityBase;

// ===========================================================================
// Name-based hook API — hook authors use these instead of the enum / RVA
// macros above.
// ===========================================================================

// Hook name string constants. Use these as the `name` argument to
// KIOUHookOrig / KIOUHookInstall / KIOUHookSiteAddr. The string identity
// (not pointer equality) is what's looked up, so direct literal use also
// works — the macros exist mainly to catch typos at the call site.
extern const char KIOU_HOOK_NAME_SET_TARGET_FRAMERATE[];
extern const char KIOU_HOOK_NAME_NSS_SETHASHSIZE[];
extern const char KIOU_HOOK_NAME_NSS_SETSKILLEVEL[];
extern const char KIOU_HOOK_NAME_NSS_SEARCHFULL[];
extern const char KIOU_HOOK_NAME_ACCOUNT_EXISTS[];
extern const char KIOU_HOOK_NAME_LOGIN_ARGS_CREATE[];
extern const char KIOU_HOOK_NAME_REGISTER_USER_ARGS_CREATE[];
extern const char KIOU_HOOK_NAME_RUN_LOGIN_SEQ_MOVENEXT[];
extern const char KIOU_HOOK_NAME_GET_SELF_PROFILE_MOVENEXT[];
extern const char KIOU_HOOK_NAME_HTTPMSGINVOKER_SEND_ASYNC[];
extern const char KIOU_HOOK_NAME_AI_END[];
extern const char KIOU_HOOK_NAME_CPUSTREAM_END[];
extern const char KIOU_HOOK_NAME_LOCAL_END[];
extern const char KIOU_HOOK_NAME_ONLINE_END[];
extern const char KIOU_HOOK_NAME_REPLAY_END[];
extern const char KIOU_HOOK_NAME_BACK_TO_TITLE_RUN_ASYNC[];

// Resolve the orig function pointer for a hook by symbolic name.
//
//   - On chinlan ENTRY hooks: returns the cave-bypass entry from
//     g_inject_entry[lookup_id(name)]. Call this to invoke orig from a
//     hook body without re-entering the cave.
//   - On JB: returns the orig pointer stored by a previous KIOUHookInstall
//     call. Call this to invoke orig from a hook body when MSHookFunction
//     has redirected the original site.
//   - For OBSERVER hooks or names not in the catalog: returns NULL.
void *KIOUHookOrig(const char *hook_name);

// Install a JB hook by symbolic name (no-op on chinlan beyond returning
// the bypass for caller convenience).
//
//   - On JB: resolves site address (unityBase + site_rva), calls
//     MSHookFunction(site, replacement, &orig), stores `orig` so
//     KIOUHookOrig(name) returns it, and returns `orig` to the caller for
//     storage in a static function pointer.
//   - On chinlan: looks up g_inject_entry[lookup_id(name)] and returns it.
//     The chinlan dispatcher (per-tweak ChinlanDispatcher.m) is what
//     actually wires the cave entry slot to `replacement`, so the
//     `replacement` arg is ignored on chinlan.
//
// Returns NULL on unknown name. The caller stores the returned pointer in
// a static `orig_X` so hook bodies can invoke orig without re-resolving.
void *KIOUHookInstall(const char *hook_name,
                       void *replacement,
                       uintptr_t unityBase);

// Compute the absolute address of a hook site (unityBase + site_rva).
// Used by consumers that need a raw function pointer rather than going
// through MSHookFunction — e.g. calling a static method like
// BackToTitleSequence.RunAsync. Returns 0 on unknown name.
uintptr_t KIOUHookSiteAddr(const char *hook_name, uintptr_t unityBase);

// ---------------------------------------------------------------------------
// Shared installer prototypes.
// ---------------------------------------------------------------------------
void KFInstallAccountObserveHook(uintptr_t unityBase);
void KFInstallGrpcLoggingHook(uintptr_t unityBase);

// Drive BackToTitleSequence.RunAsync — called by consumer settings UIs after
// the user confirms an account switch so KIOU re-runs AccountExists → Login
// with the pending_device_id substitution in effect (no app relaunch needed).
void KFNavigateToTitleScene(void);

// ---------------------------------------------------------------------------
// UniTask ABI shape — 16-byte struct (IUniTaskSource* + short token); on
// arm64 it returns in {x0, x1}. Hook bodies that match a UniTask-returning
// site declare their function pointer using this struct.
// ---------------------------------------------------------------------------
typedef struct { void *r0; void *r1; } KFUniTaskRet;
