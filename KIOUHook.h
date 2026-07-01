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
// Pair-of-truth note: the `enum kiou_hook_id` and `KIOU_HOOK_RVA_*`
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
//
// Placement: sits inside __DATA.__common just past the entry-slot table
// capacity (ENTRY_SLOT_BASE_RVA + ENTRY_SLOT_CAPACITY * 8 = 0x091E92B8).
// The old 0x8F90C80 landed in __DATA.__bss, which UnityRuntime / il2cpp
// overwrites during lazy init — publishing dispatch_one there survived
// startup but got clobbered before the first observer fire, so the cave
// BLR X16 jumped to garbage and crashed with a PC alignment fault. See
// recipes/v1_0_2.py for the __common vs __bss note.
#define KIOU_HOOK_OBSERVER_SLOT_RVA            0x091E92B8

// Entry-cave slot table. Slot N at +N*8 holds the function pointer the
// CAVE_ENTRY cave BLRs directly (no dispatcher).
#define KIOU_HOOK_ENTRY_SLOT_BASE_RVA      0x091E91B8

// Cave payload region (matches recipes/common.py + per-version CAVE_REGION).
#define KIOU_HOOK_CAVE_REGION_START        0x826F5E8
#define KIOU_HOOK_CAVE_SIZE                84
#define KIOU_HOOK_CAVE_BYPASS_OFFSET       (KIOU_HOOK_CAVE_SIZE - 8)

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
enum kiou_hook_id {
    // Entry caves (route through entry slot table)
    KIOU_HOOK_ID_SET_TARGET_FRAMERATE = 0,
    KIOU_HOOK_ID_NSS_SETHASHSIZE,
    KIOU_HOOK_ID_NSS_SETSKILLEVEL,
    KIOU_HOOK_ID_NSS_SEARCHFULL,
    KIOU_HOOK_ID_ACCOUNT_EXISTS,
    KIOU_HOOK_ID_LOGIN_ARGS_CREATE,
    KIOU_HOOK_ID_REGISTER_USER_ARGS_CREATE,
    KIOU_HOOK_ID_RUN_LOGIN_SEQ_MOVENEXT,
    KIOU_HOOK_ID_GET_SELF_PROFILE_MOVENEXT,
    KIOU_HOOK_ID_HTTPMSGINVOKER_SEND_ASYNC,
    // Observer caves (routed by dispatch_one's switch)
    KIOU_HOOK_ID_KIFU_AI_END,
    KIOU_HOOK_ID_KIFU_CPUSTREAM_END,
    KIOU_HOOK_ID_KIFU_LOCAL_END,
    KIOU_HOOK_ID_KIFU_ONLINE_END,
    KIOU_HOOK_ID_KIFU_REPLAY_END,
    // Additional entry caves.
    KIOU_HOOK_ID_HEADER_PROVIDER_SET_OR_UPDATE_HEADER,
    // Entry caves contributed by KiouEditor — 1.0.1-pinned RVAs. All
    // CAVE_ENTRY. The KF prefix is retained for consistency; treat it as
    // "KIOU framework" rather than KiouForge-specific.
    KIOU_HOOK_ID_SYNC_ITEM_LIST_MERGE,
    KIOU_HOOK_ID_COLLECTION_PRESET_MERGE,
    KIOU_HOOK_ID_SELECT_CHAR_ASYNC,
    KIOU_HOOK_ID_SELECT_CHAR_REPLY_MERGE,
    KIOU_HOOK_ID_MATCHING_PLAYER_MERGE,
    KIOU_HOOK_ID_HISTORY_DETAIL_MERGE,
    KIOU_HOOK_ID_HISTORY_GET_PREMIUM,
    KIOU_HOOK_ID_KIFU_DETAIL_IS_PREMIUM,
    KIOU_HOOK_ID_VOICE_PLAYER_SATISFIES,
    KIOU_HOOK_ID_VOICE_CELL_GET_IS_LOCKED,
    KIOU_HOOK_ID_BSE_CTOR,
    KIOU_HOOK_ID_BSE_ENSURE_INITIALIZED,
    KIOU_HOOK_ID_RBSUPPORT_GET_ENABLED,
    KIOU_HOOK_ID_RBSUPPORT_GET_DEPTH,
    KIOU_HOOK_ID_HOME_UTILITY_PRESENTER_CTOR,
    KIOU_HOOK_ID_UIBUTTONBASE_ONPOINTERCLICK,
    KIOU_HOOK_ID_TITLE_SCENE_MOVENEXT,
    KIOU_HOOK_ID_GAME_ORCHESTRATOR_IS_AFK,

    KIOU_HOOK_ID__COUNT,
};

// Entry-slot enum — one per CAVE_ENTRY row. Slot N's function pointer lives
// at unityBase + KIOU_HOOK_ENTRY_SLOT_BASE_RVA + N*8.
enum kiou_hook_slot_id {
    KIOU_HOOK_SLOT_SET_TARGET_FRAMERATE = 0,
    KIOU_HOOK_SLOT_NSS_SETHASHSIZE,
    KIOU_HOOK_SLOT_NSS_SETSKILLEVEL,
    KIOU_HOOK_SLOT_NSS_SEARCHFULL,
    KIOU_HOOK_SLOT_ACCOUNT_EXISTS,
    KIOU_HOOK_SLOT_LOGIN_ARGS_CREATE,
    KIOU_HOOK_SLOT_REGISTER_USER_ARGS_CREATE,
    KIOU_HOOK_SLOT_RUN_LOGIN_SEQ_MOVENEXT,
    KIOU_HOOK_SLOT_GET_SELF_PROFILE_MOVENEXT,
    KIOU_HOOK_SLOT_HTTPMSGINVOKER_SEND_ASYNC,
    // Additional entry slots.
    KIOU_HOOK_SLOT_HEADER_PROVIDER_SET_OR_UPDATE_HEADER,
    // KiouEditor entry slots (1.0.1).
    KIOU_HOOK_SLOT_SYNC_ITEM_LIST_MERGE,
    KIOU_HOOK_SLOT_COLLECTION_PRESET_MERGE,
    KIOU_HOOK_SLOT_SELECT_CHAR_ASYNC,
    KIOU_HOOK_SLOT_SELECT_CHAR_REPLY_MERGE,
    KIOU_HOOK_SLOT_MATCHING_PLAYER_MERGE,
    KIOU_HOOK_SLOT_HISTORY_DETAIL_MERGE,
    KIOU_HOOK_SLOT_HISTORY_GET_PREMIUM,
    KIOU_HOOK_SLOT_KIFU_DETAIL_IS_PREMIUM,
    KIOU_HOOK_SLOT_VOICE_PLAYER_SATISFIES,
    KIOU_HOOK_SLOT_VOICE_CELL_GET_IS_LOCKED,
    KIOU_HOOK_SLOT_BSE_CTOR,
    KIOU_HOOK_SLOT_BSE_ENSURE_INITIALIZED,
    KIOU_HOOK_SLOT_RBSUPPORT_GET_ENABLED,
    KIOU_HOOK_SLOT_RBSUPPORT_GET_DEPTH,
    KIOU_HOOK_SLOT_HOME_UTILITY_PRESENTER_CTOR,
    KIOU_HOOK_SLOT_UIBUTTONBASE_ONPOINTERCLICK,
    KIOU_HOOK_SLOT_TITLE_SCENE_MOVENEXT,
    KIOU_HOOK_SLOT_GAME_ORCHESTRATOR_IS_AFK,

    KIOU_HOOK_SLOT__COUNT,
};

// ---------------------------------------------------------------------------
// Site RVAs — used by KIOUHookSiteAddr to compute target addresses.
// Hook authors: don't reference these directly. Use KIOUHookSiteAddr(name).
// ---------------------------------------------------------------------------
#define KIOU_HOOK_RVA_SET_TARGET_FRAMERATE       0x6B718A4
#define KIOU_HOOK_RVA_NSS_SETHASHSIZE            0x5D379DC
#define KIOU_HOOK_RVA_NSS_SETSKILLEVEL           0x5D37968
#define KIOU_HOOK_RVA_NSS_SEARCHFULL             0x5D37A74
#define KIOU_HOOK_RVA_AI_END                     0x59EA720
#define KIOU_HOOK_RVA_CPUSTREAM_END              0x59F15D4
#define KIOU_HOOK_RVA_LOCAL_END                  0x5A046B4
#define KIOU_HOOK_RVA_ONLINE_END                 0x5A06158
#define KIOU_HOOK_RVA_REPLAY_END                 0x5A30320
#define KIOU_HOOK_RVA_ACCOUNT_EXISTS             0x5922CD0
#define KIOU_HOOK_RVA_LOGIN_ARGS_CREATE          0x5B9DC04
#define KIOU_HOOK_RVA_REGISTER_USER_ARGS_CREATE  0x5B9DC94
#define KIOU_HOOK_RVA_RUN_LOGIN_SEQ_MOVENEXT     0x58152BC
#define KIOU_HOOK_RVA_GET_SELF_PROFILE_MOVENEXT  0x5BB99DC
#define KIOU_HOOK_RVA_HTTPMSGINVOKER_SEND_ASYNC  0x6082AC0
#define KIOU_HOOK_RVA_BACK_TO_TITLE_RUN_ASYNC    0x5CFC394
#define KIOU_HOOK_RVA_HEADER_PROVIDER_SET_OR_UPDATE_HEADER  0x5BD9EE8

// --- KiouEditor hook sites (1.0.1 RVAs) ----------------------------------
// These pin to KIOU 1.0.1 build 11 because KiouEditor is 1.0.1-only. If a
// future port maps the same semantic site to a 1.0.2 RVA, the macros above
// will need version-aware dispatch — for now KiouForge (1.0.2) callers
// don't reference these.
#define KIOU_HOOK_RVA_SYNC_ITEM_LIST_MERGE          0x5C37034
#define KIOU_HOOK_RVA_COLLECTION_PRESET_MERGE       0x5C4065C
#define KIOU_HOOK_RVA_SELECT_CHAR_ASYNC             0x5CA7C90
#define KIOU_HOOK_RVA_SELECT_CHAR_REPLY_MERGE       0x5C26DCC
#define KIOU_HOOK_RVA_MATCHING_PLAYER_MERGE         0x5B4CAEC
#define KIOU_HOOK_RVA_HISTORY_DETAIL_MERGE          0x5C01328
#define KIOU_HOOK_RVA_HISTORY_GET_PREMIUM           0x5C00D88
#define KIOU_HOOK_RVA_KIFU_DETAIL_IS_PREMIUM        0x585B25C
#define KIOU_HOOK_RVA_VOICE_PLAYER_SATISFIES        0x582B88C
#define KIOU_HOOK_RVA_VOICE_CELL_GET_IS_LOCKED      0x584ADC0
#define KIOU_HOOK_RVA_BSE_CTOR                      0x597A448
#define KIOU_HOOK_RVA_BSE_ENSURE_INITIALIZED        0x597BAFC
#define KIOU_HOOK_RVA_RBSUPPORT_GET_ENABLED         0x593E630
#define KIOU_HOOK_RVA_RBSUPPORT_GET_DEPTH           0x593E650
#define KIOU_HOOK_RVA_HOME_UTILITY_PRESENTER_CTOR   0x5A9F298
#define KIOU_HOOK_RVA_UIBUTTONBASE_ONPOINTERCLICK   0x5DD1E08
#define KIOU_HOOK_RVA_TITLE_SCENE_MOVENEXT          0x5DCC728
#define KIOU_HOOK_RVA_GAME_ORCHESTRATOR_IS_AFK      0x59455D4

// --- Direct-ABI helper RVAs (1.0.1) --------------------------------------
// Not hook sites; KiouEditor bodies look these up via KIOUHookSiteAddr to
// call the underlying functions directly. NSS_SETHASHSIZE_DIRECT is the
// 1.0.1 RVA of NativeSyncSession.SetHashSize — distinct from the
// NSS_SETHASHSIZE hook above whose macro carries the 1.0.2 RVA used by
// KiouForge. Catalog rows for these have hook_id = -1.
#define KIOU_HOOK_RVA_NSS_SETHASHSIZE_DIRECT        0x5D320E0
#define KIOU_HOOK_RVA_GAMEOBJECT_GETCOMPONENT       0x6BCA6AC
#define KIOU_HOOK_RVA_RTU_WORLDTOSCREENPOINT        0x6F20040

// ---------------------------------------------------------------------------
// Dispatcher state — defined by the consumer's ChinlanDispatcher.m.
// ---------------------------------------------------------------------------

// Per-site cave-bypass addresses so hook bodies can call orig without
// re-entering the cave. Sized by KIOU_HOOK_ID__COUNT; unused slots stay zero.
#if IPA_CHINLAN
extern void * volatile g_inject_entry[KIOU_HOOK_ID__COUNT];
#endif

void KIOUChinlanPublish(uintptr_t unityBase);

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
extern const char KIOU_HOOK_NAME_HEADER_PROVIDER_SET_OR_UPDATE_HEADER[];
// KiouEditor hook sites (1.0.1).
extern const char KIOU_HOOK_NAME_SYNC_ITEM_LIST_MERGE[];
extern const char KIOU_HOOK_NAME_COLLECTION_PRESET_MERGE[];
extern const char KIOU_HOOK_NAME_SELECT_CHAR_ASYNC[];
extern const char KIOU_HOOK_NAME_SELECT_CHAR_REPLY_MERGE[];
extern const char KIOU_HOOK_NAME_MATCHING_PLAYER_MERGE[];
extern const char KIOU_HOOK_NAME_HISTORY_DETAIL_MERGE[];
extern const char KIOU_HOOK_NAME_HISTORY_GET_PREMIUM[];
extern const char KIOU_HOOK_NAME_KIFU_DETAIL_IS_PREMIUM[];
extern const char KIOU_HOOK_NAME_VOICE_PLAYER_SATISFIES[];
extern const char KIOU_HOOK_NAME_VOICE_CELL_GET_IS_LOCKED[];
extern const char KIOU_HOOK_NAME_BSE_CTOR[];
extern const char KIOU_HOOK_NAME_BSE_ENSURE_INITIALIZED[];
extern const char KIOU_HOOK_NAME_RBSUPPORT_GET_ENABLED[];
extern const char KIOU_HOOK_NAME_RBSUPPORT_GET_DEPTH[];
extern const char KIOU_HOOK_NAME_HOME_UTILITY_PRESENTER_CTOR[];
extern const char KIOU_HOOK_NAME_UIBUTTONBASE_ONPOINTERCLICK[];
extern const char KIOU_HOOK_NAME_TITLE_SCENE_MOVENEXT[];
extern const char KIOU_HOOK_NAME_GAME_ORCHESTRATOR_IS_AFK[];
// Direct-ABI helper lookups (KiouEditor, 1.0.1). hook_id = -1 in the catalog.
extern const char KIOU_HOOK_NAME_NSS_SETHASHSIZE_DIRECT[];
extern const char KIOU_HOOK_NAME_GAMEOBJECT_GETCOMPONENT[];
extern const char KIOU_HOOK_NAME_RTU_WORLDTOSCREENPOINT[];

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
void KIOUInstallAccountObserveHook(uintptr_t unityBase);
void KIOUInstallGrpcLoggingHook(uintptr_t unityBase);

// Publish a hook body that unconditionally returns false for
// GameOrchestrator.IsAfkEnabled. This is the "AFK is always off"
// convenience installer for consumers that want the historic
// inline-patch behaviour without wiring the KIOUEditor feature-flag
// surface. Cave slot is populated after this call, so any consumer
// building against a recipe that carries the AFK site as
// CAVE_ENTRY (v1_0_1 and later v1_0_2) can call this once at
// startup and be done. See Hook/AfkDisable.m for the
// feature-flag-gated variant (KIOUEditorInstallAfkDisableHook).
void KIOUAfkDisableAlwaysFalseInstall(uintptr_t unityBase);

// Drive BackToTitleSequence.RunAsync — called by consumer settings UIs after
// the user confirms an account switch so KIOU re-runs AccountExists → Login
// with the pending_device_id substitution in effect (no app relaunch needed).
void KIOUNavigateToTitleScene(void);

// ---------------------------------------------------------------------------
// UniTask ABI shape — 16-byte struct (IUniTaskSource* + short token); on
// arm64 it returns in {x0, x1}. Hook bodies that match a UniTask-returning
// site declare their function pointer using this struct.
// ---------------------------------------------------------------------------
typedef struct { void *r0; void *r1; } KIOUUniTaskRet;
