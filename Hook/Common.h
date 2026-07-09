#pragma once

#import <Foundation/Foundation.h>
#import <stdbool.h>
#import <stdint.h>

// ===========================================================================
// Hook/Common.h — shared surface for the KiouEditor-derived hook bodies.
//
// Migrated from KiouEditor's Sources/KiouEditor/Internal.h. Each block is
// annotated with its original owner so a reader can trace back to the JB
// tweak sources when needed.
//
// This header pulls in the KIOU-Hook catalog transitively, so consumer .m
// files only need `#import "Hook/Common.h"` to get catalog names, the write
// helpers, and every shared prototype below.
//
// Symbols left extern here (feature flags, assist-tuning getters,
// FriendUnhide sprite helpers) are DEFINED IN THE CONSUMER TWEAK — hook
// bodies compiled from KIOU-Hook cannot link standalone against Common.m.
// That's intentional: KIOU-Hook is a source-share library, and consumers
// wire up their own persistence + UI-driven toggles.
// ===========================================================================

#import "KIOUHook.h"
#import "il2cpp.h"

// ---------------------------------------------------------------------------
// Consumer-provided version tags. Consumers stamp these via `-D` in their
// Makefile (KiouEditor / KiouForge / ...). Fallbacks keep the KIOU-Hook
// bodies self-linkable when the consumer forgot to define them.
// ---------------------------------------------------------------------------

#ifndef KIOU_EDITOR_COMMIT
#define KIOU_EDITOR_COMMIT "unknown"
#endif

#ifndef KIOU_EDITOR_VERSION
#define KIOU_EDITOR_VERSION "dev"
#endif

// ---------------------------------------------------------------------------
// Reentrancy guard shared between SyncItemList / Collection hook bodies.
// Definition lives in Hook/Common.m.
// ---------------------------------------------------------------------------

extern volatile int g_inHook;

// ---------------------------------------------------------------------------
// IL2CPP write helpers — opt-in via this header so observation-only tweaks
// that never include Hook/Common.h stay structurally read-only. Same
// volatile-qualification pattern the KiouEditor hooks have always used.
// ---------------------------------------------------------------------------

static inline void writeU8(void *base, uintptr_t off, uint8_t val) {
    if (!ptrLooksValid(base)) return;
    *(volatile uint8_t *)((uint8_t *)base + off) = val;
}

static inline void writeI32(void *base, uintptr_t off, int32_t val) {
    if (!ptrLooksValid(base)) return;
    *(volatile int32_t *)((uint8_t *)base + off) = val;
}

// ---------------------------------------------------------------------------
// SelectCharacter persistence — the target skin id the user actually
// picked, kept on-device while the server sees only KIOU_SAFE_SKIN_ID.
// Definitions live in Hook/Common.m so both SelectCharacter and
// SyncItemList hooks can reach them.
// ---------------------------------------------------------------------------

#define KIOU_SAFE_SKIN_ID 1

int32_t KIOUEditorPersistedSelection(void);
void    KIOUEditorSetPersistedSelection(int32_t skinId);

// Rewrite is_selected entries in the given character + character-skin
// RepeatedField arrays so they advertise the persisted user choice instead
// of whatever the server returned. Both arrays may be NULL/empty.
//
//   charArr / charCount  - updatedCharacterList     (CharacterStatus[],
//                          mstCharacterId @0x18, isSelected @0x45)
//   skinArr / skinCount  - updatedCharacterSkinList (CharacterSkinStatus[],
//                          mstSkinId @0x18, mstCharacterId @0x1C,
//                          isSelected @0x21)
void KIOUEditorApplyPersistedSelectionToLists(void *charArr, int32_t charCount,
                                        void *skinArr, int32_t skinCount);

// ---------------------------------------------------------------------------
// FriendUnhide UI helpers — full definitions land alongside the
// FriendUnhide hook body in a follow-up PR. Common.m ships stub no-op
// definitions so PR-A2 links; the stubs are replaced with the real
// il2cpp bridge when Hook/FriendUnhide.m arrives.
// ---------------------------------------------------------------------------

// Sprite recon: walks uiButton -> gameObject.transform -> "Content" -> "Image"
// child, calls GameObject.GetComponent("UnityEngine.UI.Image") on the leaf
// GameObject, and logs the m_Sprite (field +0xD8) pointer. Tag distinguishes
// title vs home callsites in the log.
void KIOUEditorReconButtonImage(void *uiButton, const char *tag);

// Once the title screen has captured its menu button's sprite, this swaps
// it onto a freshly cloned home utility button's Image leaf. No-op if the
// title sprite has not been captured yet.
void KIOUEditorApplyTitleSpriteToClone(void *cloneGo);

// UIKit-side settings presenter. Called from Hook/FriendUnhide.m's
// OnPointerClick body to show the tweak's settings when the (unhidden +
// remapped) friend button is tapped. The consumer tweak (KiouEditor)
// defines this in its Hook_SettingsUI.m; KIOU-Hook ships a weak no-op
// stub so consumers that pull in FriendUnhide.m without wiring the
// UIKit surface still link cleanly.
void KIOUEditorPresentSettings(void);

// ---------------------------------------------------------------------------
// Runtime feature toggles. Each hook body gates its tamper logic on its
// own flag; flipping a flag off causes the hook to fall through to orig()
// and behave like vanilla. Consumer tweak owns storage + defaults.
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, KiouFeature) {
    KIOU_FEATURE_ITEM_UNLOCK = 0,    // Hook/SyncItemList ownership writes
    KIOU_FEATURE_CHAR_BYPASS,        // Hook/SelectCharacter SAFE_ID swap
    KIOU_FEATURE_PREMIUM_UNLOCK,     // Hook/PremiumUnlock forced true
    KIOU_FEATURE_MATCH_ASSIST,       // Hook/MatchingPlayer enable beginner support
    KIOU_FEATURE_VOICE_UNLOCK,       // Hook/VoiceUnlock + SyncItemList intimacy pin
    KIOU_FEATURE_ASSIST_ENABLE,      // Hook/AssistEnable force enabled + depth
    KIOU_FEATURE_DISABLE_AFK,        // Hook/AfkDisable suppress AFK warning + auto-surrender
    // Consumer-owned tweak-specific features. Defined here so the shared
    // KIOUEditorFeatureEnabled surface can gate them, but the hook bodies
    // that consume these flags live in the consumer tweak (KiouEditor)
    // because the sites are tweak-local and not part of the shared catalog.
    KIOU_FEATURE_INGAME_ANALYSIS,    // KiouEditor Hook_AssistTune BSE.EvaluateAsync suppression
    KIOU_FEATURE_AI_SPECIAL_SUPPORT, // KiouEditor Hook_AiSpecialSupport 棋桜覚醒 unlock (default off)
    KIOU_FEATURE_KIFU_AUTOSAVE,      // KiouEditor Kif/ pipeline — write .kif on OnMatchEndAsync
    KIOU_FEATURE_COUNT,
};

bool KIOUEditorFeatureEnabled(KiouFeature f);
void KIOUEditorSetFeatureEnabled(KiouFeature f, bool enabled);
NSString *KIOUEditorFeatureLabel(KiouFeature f);

// ---------------------------------------------------------------------------
// Engine tuning (BeginnerSupportEvaluator).
//   depth      1 .. 36  (default 16; retail BSE default is 5, 36 is the
//                        practical ceiling the NNUE engine will actually
//                        reach in a reasonable timeframe)
//   skillLevel 1 .. 20  (default 20)
//   hashIndex  0 .. 4   (default 1 = 128 MB; index into the preset table
//                        {64, 128, 256, 512, 1024} MB)
//
// The hash size feeds NativeSyncSession.SetHashSize(int mb) — see
// Hook/AssistTune.m for the call site. Rshogi's compiled-in default is
// small (~16 MB) and no engine path sets it; the user-picked preset is
// applied inside EnsureInitializedLocked once the native session is alive.
// ---------------------------------------------------------------------------

int32_t KIOUEditorAssistDepth(void);
void    KIOUEditorSetAssistDepth(int32_t v);
int32_t KIOUEditorAssistSkillLevel(void);
void    KIOUEditorSetAssistSkillLevel(int32_t v);
int32_t KIOUEditorAssistHashIndex(void);
void    KIOUEditorSetAssistHashIndex(int32_t idx);
int32_t KIOUEditorAssistHashMB(void);

// ---------------------------------------------------------------------------
// Chinlan slot publish helper.
//
// KIOUHookInstall() on the chinlan branch does NOT write the entry slot the
// cave will BLR through — it only returns the cave-bypass entry. Each hook
// installer must therefore ALSO write its slot before UnityFramework's
// first call reaches the cave. This macro keeps the pattern one-liner and
// no-ops on JB / jailed where MSHookFunction already rewrote the site.
//
// Usage inside an installer:
//   s_orig = (fn_t)KIOUHookInstall(NAME, (void *)hook_fn, unityBase);
//   KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_X, hook_fn);
// ---------------------------------------------------------------------------
#if IPA_CHINLAN
#define KIOU_HOOK_PUBLISH_SLOT(unityBase, slot_id, hook_fn) do {                 \
    void * volatile *_entrySlots =                                                \
        (void * volatile *)((unityBase) + KIOU_HOOK_ENTRY_SLOT_BASE_RVA);         \
    _entrySlots[(slot_id)] = (void *)(hook_fn);                                   \
} while (0)
#else
#define KIOU_HOOK_PUBLISH_SLOT(unityBase, slot_id, hook_fn) do {                 \
    (void)(unityBase); (void)(slot_id); (void)(hook_fn);                          \
} while (0)
#endif

// ---------------------------------------------------------------------------
// Per-module hook installers. Each takes the UnityFramework base and calls
// KIOUHookInstall for every site it owns. Safe to call multiple times;
// guarded by KIOUHookInstall's own idempotency.
// ---------------------------------------------------------------------------

void KIOUEditorInstallAfkDisableHook(uintptr_t unityBase);
void KIOUEditorInstallAssistEnableHook(uintptr_t unityBase);
void KIOUEditorInstallAssistTuneHook(uintptr_t unityBase);
void KIOUEditorInstallCollectionHook(uintptr_t unityBase);
void KIOUEditorInstallMatchingPlayerHook(uintptr_t unityBase);
void KIOUEditorInstallPremiumUnlockHook(uintptr_t unityBase);
void KIOUEditorInstallSelectCharacterHook(uintptr_t unityBase);
void KIOUEditorInstallSyncItemListHook(uintptr_t unityBase);
void KIOUEditorInstallVersionHook(uintptr_t unityBase);
void KIOUEditorInstallVoiceUnlockHook(uintptr_t unityBase);
void KIOUEditorInstallFriendUnhideHook(uintptr_t unityBase);
void KIOUEditorInstallAiSpecialSupportHook(uintptr_t unityBase);
