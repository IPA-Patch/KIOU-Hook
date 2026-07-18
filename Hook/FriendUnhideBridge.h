#pragma once

#import <Foundation/Foundation.h>
#import <stdbool.h>
#import <stdint.h>

// ===========================================================================
// Hook/FriendUnhideBridge.h — private bridge surface for Hook/FriendUnhide.m.
//
// Everything below is consumed only by FriendUnhide.m — the shared header
// KIOU-Hook consumers include is Hook/Common.h, which already exposes the
// two truly public entry points (KIOUEditorReconButtonImage and
// KIOUEditorApplyTitleSpriteToClone).
//
// The split exists because FriendUnhide.m's il2cpp / Unity bridging layer
// runs to ~800 lines on its own. Keeping it in the same TU as the hook body
// pushed the file past 1100 lines, well over the project's 600-line
// hard-split threshold. The bridge lives here so the hook body stays the
// concise ~230-line file it wants to be.
//
// If you are a KIOU-Hook consumer (KiouEditor / KiouForge / ...) you should
// never need to import this header. It only ships with Hook/FriendUnhide.m
// as an internal implementation detail.
// ===========================================================================

// ---------------------------------------------------------------------------
// One-shot bootstrap the hook installer runs before wiring the two RVAs.
// Resolves the il2cpp runtime symbols (runtime_invoke, class lookup, method
// lookup, string_new) via dlsym and stashes UnityFramework's base address
// so the direct-ABI helpers below can reach RVA-addressed functions.
// Safe to call more than once.
// ---------------------------------------------------------------------------
void FriendUnhideBridgeInit(uintptr_t unityBase);

// ---------------------------------------------------------------------------
// Component / GameObject / Transform bridging.
//
// Each helper caches its il2cpp method pointer on first fire (per unique
// klass; the caches are keyed by "first klass this method was seen on")
// and hits a `dlsym`-resolved il2cpp_runtime_invoke or a direct-ABI call
// after that. NULL is returned when the bridge is not fully resolved.
// ---------------------------------------------------------------------------

// Component.get_gameObject.
void *gameObjectOf(void *componentObj);
// Component.get_transform — cached on the Component klass side.
void *transformOf(void *componentObj);
// GameObject.get_transform — cached on the GameObject klass side (distinct
// method handle from Component.get_transform).
void *goTransformOf(void *gameObject);
// GameObject.SetActive(bool).
void setActive(void *gameObject, bool value);

// Transform.get_parent.
void *transformParentOf(void *transformObj);
// Transform.SetParent(Transform parent, bool worldPositionStays) — direct
// ABI because runtime_invoke hangs on the invoker for this signature.
void transformSetParent(void *transformObj, void *newParent, bool worldPositionStays);
// Transform.GetSiblingIndex — direct ABI (int32 return).
int32_t transformGetSiblingIndex(void *transformObj);
// Transform.SetSiblingIndex(int) — direct ABI.
void transformSetSiblingIndex(void *transformObj, int32_t idx);

// ---------------------------------------------------------------------------
// UI recon + clone bridging. Used both to log the live hierarchies and to
// mutate the freshly instantiated clone.
// ---------------------------------------------------------------------------

// Walk the Transform tree under `tfObj`, log each node's name with
// indentation. Depth-capped for readability.
void dumpHierarchy(void *tfObj, int depth, int maxDepth);

// Log Image.m_Sprite name on the clone. Recon-only.
void reconSpriteName(void *cloneTf);

// Probe every GameObject in the clone tree for a TMPro / uGUI text
// component and log which ones carry one. Recon-only.
void reconTextComponents(void *cloneTf);

// Zero out the clone's Image alpha + call SetAllDirty so the visual is
// invisible while the raycast target remains live (taps still fire).
void hideCloneImage(void *cloneTf);

// Object.Instantiate(Object original) — direct call into MethodInfo->
// methodPointer, bypassing runtime_invoke's crashy invoker path.
void *instantiateCloneDirect(void *originalObj);

// ---------------------------------------------------------------------------
// State shared between the bridge and the hook body.
//
// - g_friendGo: the friend button's GameObject captured at HUP.ctor time.
//   Compared against `this.gameObject` in the OnPointerClick hook so the
//   friend tap can be routed to KIOUEditorPresentSettings instead of the
//   retail "Coming soon" popup.
//
// - g_cloneGo / g_lastClonedView: legacy state for the menu-button clone
//   path (currently disabled). Kept so the disabled branch in
//   FriendUnhide.m still compiles.
// ---------------------------------------------------------------------------

extern void *g_friendGo;
extern void *g_cloneGo;
extern void *g_lastClonedView;
