#import "Hook/Common.h"
#import "Hook/FriendUnhideBridge.h"
#import "logging.h"

// ===========================================================================
// Hook/FriendUnhide.m — HomeUtilityPresenter.ctor unhides the friend button;
// UIButtonBase.OnPointerClick routes friend-button taps to KiouEditor's
// settings sheet.
//
// The il2cpp / Unity bridging layer this hook depends on lives in
// Hook/FriendUnhideBridge.m and Hook/FriendUnhideBridgeUI.m (behind
// Hook/FriendUnhideBridge.h) so the hook body stays close to the tamper
// logic itself. See FriendUnhideBridge.h for the exported bridge surface.
//
// HomeUtilityView (Project.Menu) layout from dump.cs:
//   +0x20 _menuButton    (UIButtonBase)
//   +0x28 _giftButton    (UIButtonBase)
//   +0x30 _giftBadgeView (BadgeWithCountView)
//   +0x38 _friendButton  (UIButtonBase) - hidden in the retail layout
//
// Phase 1a (recon) confirmed all three button pointers populate at ctor
// time. Phase 1b calls UnityEngine.Component.get_gameObject on the friend
// button and then UnityEngine.GameObject.SetActive(true) on the result via
// il2cpp_runtime_invoke. Methods are resolved off the runtime object's own
// klass (get_gameObject is inherited from Component) and the resulting
// GameObject's klass, then cached for subsequent ctor fires.
// ===========================================================================

#define RVA_HOME_UTILITY_PRESENTER_CTOR 0x5A9F298
#define RVA_UIBUTTONBASE_ONPOINTERCLICK 0x5DD1E08

#define OFF_HUV_MENU_BUTTON   0x20
#define OFF_HUV_GIFT_BUTTON   0x28
#define OFF_HUV_FRIEND_BUTTON 0x38

typedef void (*HUP_ctor_t)(void *self, void *view);
typedef void (*UIBtn_OnPointerClick_t)(void *self, void *eventData, void *methodInfo);

static HUP_ctor_t             orig_HUP_ctor             = NULL;
static UIBtn_OnPointerClick_t orig_UIBtn_OnPointerClick = NULL;

// UIButtonBase.IPointerClickHandler.OnPointerClick fires for every
// UIButtonBase-derived button (including UIButton, since UIButton does not
// override slot 17). We compare each call's `this.gameObject` against the
// friend button GameObject captured at HUP.ctor time; on match, dispatch
// to the KiouEditor settings UI and skip orig (the retail friend button
// only shows a "Coming soon" popup, so bypassing it is the desired UX).
static void hook_UIBtn_OnPointerClick(void *self, void *eventData, void *methodInfo) {
    @try {
        if (ptrLooksValid(self)) {
            void *thisGo = gameObjectOf(self);
            if (g_friendGo && thisGo == g_friendGo) {
                IPALog([NSString stringWithFormat:
                          @"[HOME] friend tap -> settings (self=%p go=%p)",
                          self, thisGo]);
                KIOUEditorPresentSettings();
                return;
            }
            // Legacy: menu-button clone path is disabled (see hook_HUP_ctor
            // below), kept only so the guard still passes if someone ever
            // re-enables the branch for testing.
            if (g_cloneGo && thisGo == g_cloneGo) {
                IPALog([NSString stringWithFormat:
                          @"[HOME] clone tap -> settings (self=%p go=%p)",
                          self, thisGo]);
                KIOUEditorPresentSettings();
                return;
            }
        }
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                  @"[HOME] OnPointerClick exc: %@", e]);
    }
    if (orig_UIBtn_OnPointerClick) {
        orig_UIBtn_OnPointerClick(self, eventData, methodInfo);
    }
}

static void hook_HUP_ctor(void *self, void *view) {
    if (orig_HUP_ctor) {
        orig_HUP_ctor(self, view);
    }
    @try {
        if (!ptrLooksValid(view)) {
            IPALog(@"[HOME] presenter.ctor: view ptr invalid");
            return;
        }
        void *menuBtn   = readPtr(view, OFF_HUV_MENU_BUTTON);
        void *giftBtn   = readPtr(view, OFF_HUV_GIFT_BUTTON);
        void *friendBtn = readPtr(view, OFF_HUV_FRIEND_BUTTON);
        (void)menuBtn; (void)giftBtn;
        IPALog([NSString stringWithFormat:
                  @"[HOME] HomeUtilityView@%p buttons: menu=%p gift=%p friend=%p",
                  view, menuBtn, giftBtn, friendBtn]);

        // Friend button is always SetActive(true) because it doubles as
        // the settings entry. No feature flag — turning it off would lock
        // the user out of the KiouEditor sheet.
        if (ptrLooksValid(friendBtn)) {
            void *friendGo = gameObjectOf(friendBtn);
            if (ptrLooksValid(friendGo)) {
                IPALog([NSString stringWithFormat:
                          @"[HOME] friend gameObject=%p -> SetActive(true)", friendGo]);
                setActive(friendGo, true);
                // Snapshot the friend GO so the OnPointerClick hook above
                // can recognise the tap and route to settings instead of
                // the "Coming soon" popup the orig handler shows.
                g_friendGo = friendGo;
            } else {
                IPALog(@"[HOME] friend gameObject lookup failed");
            }
        }

        // Menu-button clone path is disabled — the friend button now doubles
        // as the settings entry so the clone is no longer needed. Kept as
        // dead code (guarded by `if (0)`) so the workflow can be
        // reactivated for testing if the friend-button UX needs to move.
        // Every helper it references still exists in FriendUnhideBridgeUI.m.
        if (0 /* disabled: menu-button clone */
            && view != g_lastClonedView
            && ptrLooksValid(menuBtn) && ptrLooksValid(friendBtn)) {
            IPALog([NSString stringWithFormat:
                      @"[HOME] presenter.ctor on main thread=%d (view %p -> %p)",
                      (int)[NSThread isMainThread],
                      g_lastClonedView, view]);
            static bool s_homeMenuReconDone = false;
            if (!s_homeMenuReconDone) {
                KIOUEditorReconButtonImage(menuBtn, "home-menu");
                s_homeMenuReconDone = true;
            }
            void *menuGo = gameObjectOf(menuBtn);
            if (ptrLooksValid(menuGo)) {
                void *cloneGo = instantiateCloneDirect(menuGo);
                if (ptrLooksValid(cloneGo)) {
                    g_lastClonedView = view;
                    g_cloneGo = cloneGo;
                    IPALog([NSString stringWithFormat:
                              @"[HOME] direct: clone gameObject=%p", cloneGo]);
                    static bool s_textReconDone = false;
                    if (!s_textReconDone) {
                        void *cloneTfRecon = goTransformOf(cloneGo);
                        reconSpriteName(cloneTfRecon);
                        reconTextComponents(cloneTfRecon);
                        s_textReconDone = true;
                    }
                    void *cloneTfForLayout = goTransformOf(cloneGo);
                    hideCloneImage(cloneTfForLayout);

                    void *friendTf = transformOf(friendBtn);
                    void *cloneTf  = goTransformOf(cloneGo);
                    IPALog([NSString stringWithFormat:
                              @"[HOME] phase2b: friendTf=%p cloneTf=%p",
                              friendTf, cloneTf]);
                    if (ptrLooksValid(friendTf) && ptrLooksValid(cloneTf)) {
                        void *parentTf = transformParentOf(friendTf);
                        IPALog([NSString stringWithFormat:
                                  @"[HOME] phase2b: parentTf=%p", parentTf]);
                        if (ptrLooksValid(parentTf)) {
                            transformSetParent(cloneTf, parentTf, false);
                            int32_t friendIdx = transformGetSiblingIndex(friendTf);
                            IPALog([NSString stringWithFormat:
                                      @"[HOME] phase2b: friend siblingIndex=%d", friendIdx]);
                            if (friendIdx >= 0) {
                                transformSetSiblingIndex(cloneTf, friendIdx + 1);
                                IPALog([NSString stringWithFormat:
                                          @"[HOME] phase2b: clone -> siblingIndex=%d",
                                          friendIdx + 1]);
                            }
                        }
                    }

                    IPALog(@"[HOME] phase2c recon: dump clone hierarchy");
                    dumpHierarchy(cloneTf, 0, 6);
                    IPALog(@"[HOME] phase2c recon: dump menu (original) hierarchy");
                    void *menuTf = transformOf(menuBtn);
                    dumpHierarchy(menuTf, 0, 6);
                    IPALog(@"[HOME] phase2c recon: dump friend (live) hierarchy");
                    dumpHierarchy(friendTf, 0, 6);
                } else {
                    IPALog(@"[HOME] direct: Instantiate returned NULL/invalid");
                }
            }
        }
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:@"[HOME] hook exception: %@", e]);
    }
}

// ---------------------------------------------------------------------------
// Installer. FriendUnhideBridgeInit() must run before KIOUHookInstall so the
// il2cpp bridge is live for the hook bodies' first fire.
// ---------------------------------------------------------------------------
void KIOUEditorInstallFriendUnhideHook(uintptr_t unityBase) {
    FriendUnhideBridgeInit(unityBase);

    orig_HUP_ctor = (HUP_ctor_t)KIOUHookInstall(
        KIOU_HOOK_NAME_HOME_UTILITY_PRESENTER_CTOR,
        (void *)hook_HUP_ctor, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_HOME_UTILITY_PRESENTER_CTOR, hook_HUP_ctor);

    orig_UIBtn_OnPointerClick = (UIBtn_OnPointerClick_t)KIOUHookInstall(
        KIOU_HOOK_NAME_UIBUTTONBASE_ONPOINTERCLICK,
        (void *)hook_UIBtn_OnPointerClick, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase, KIOU_HOOK_SLOT_UIBUTTONBASE_ONPOINTERCLICK, hook_UIBtn_OnPointerClick);

    IPALog([NSString stringWithFormat:
            @"[FRIEND] installed: HUP.ctor orig=%p UIBtn.OnPointerClick orig=%p",
            (void *)orig_HUP_ctor, (void *)orig_UIBtn_OnPointerClick]);
}
