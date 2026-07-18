#import "Hook/Common.h"
#import "Hook/FriendUnhideBridge.h"
#import "Hook/FriendUnhideBridge_Private.h"
#import "logging.h"

// ===========================================================================
// Hook/FriendUnhideBridgeUI.m — sprite ops, hide-image, hierarchy recon,
// Instantiate variants, and the two public strong-symbol implementations
// KIOUEditorReconButtonImage / KIOUEditorApplyTitleSpriteToClone.
//
// Second half of the bridge whose first half sits in
// Hook/FriendUnhideBridge.m. The split exists purely to keep both files
// under the 600-line hard-split threshold; the shared internals cross
// through Hook/FriendUnhideBridge_Private.h.
// ===========================================================================

typedef struct { float x, y, z; } UVec3;
typedef struct { float x, y; } UVec2;

typedef UVec3 (*Tf_get_position_HFA_t)(void *self, void *methodInfo);
typedef UVec2 (*Rt_get_sizeDelta_HFA_t)(void *self, void *methodInfo);

static void *g_method_Tf_get_position  = NULL;
static void *g_method_Rt_get_sizeDelta = NULL;

// RectTransformUtility.WorldToScreenPoint(Camera cam, Vector3 worldPoint).
// Static, takes a null camera for ScreenSpaceOverlay canvases and returns
// the screen pixel position with bottom-left origin. Direct call with
// NULL methodInfo — same pattern as GameObject.GetComponent(string). The
// site address is resolved via KIOUHookSiteAddr against the
// version-appropriate catalog entry (KIOU_HOOK_NAME_RTU_WORLDTOSCREENPOINT)
// rather than hard-coded, so it stays correct across 1.0.1 / 1.0.2.
typedef UVec2 (*RtU_WorldToScreenPoint_t)(void *cam, UVec3 worldPoint, void *methodInfo);

static UVec2 unityWorldToScreen(UVec3 worldPoint) {
    UVec2 zero = {0};
    if (g_unityBaseAddr == 0) return zero;
    uintptr_t addr = KIOUHookSiteAddr(
        KIOU_HOOK_NAME_RTU_WORLDTOSCREENPOINT, g_unityBaseAddr);
    if (addr == 0) return zero;
    RtU_WorldToScreenPoint_t fn = (RtU_WorldToScreenPoint_t)addr;
    return fn(NULL, worldPoint, NULL);
}

// Resolve via class_get_method_from_name so we pass the real MethodInfo*
// trailing arg the codegen wrapper expects. Direct RVA + NULL methodInfo
// crashed inside the IL2CPP P/Invoke marshalling for the value-type
// returns, so we let il2cpp hand us the proper handle.
static bool readCloneScreenRect(void *cloneTf,
                                UVec3 *outPos, UVec2 *outSize) {
    if (!ptrLooksValid(cloneTf)) return false;
    if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return false;

    if (!g_method_Tf_get_position || !g_method_Rt_get_sizeDelta) {
        void *klass = p_il2cpp_object_get_class(cloneTf);
        if (!klass) return false;
        if (!g_method_Tf_get_position) {
            g_method_Tf_get_position =
                p_il2cpp_class_get_method_from_name(klass, "get_position", 0);
        }
        if (!g_method_Rt_get_sizeDelta) {
            g_method_Rt_get_sizeDelta =
                p_il2cpp_class_get_method_from_name(klass, "get_sizeDelta", 0);
        }
        IPALog([NSString stringWithFormat:
                  @"[CLONE-RECT] cached get_position=%p get_sizeDelta=%p (klass=%p)",
                  g_method_Tf_get_position, g_method_Rt_get_sizeDelta, klass]);
    }
    if (!g_method_Tf_get_position || !g_method_Rt_get_sizeDelta) return false;

    void *posPtr = *(void **)g_method_Tf_get_position;
    void *sizePtr = *(void **)g_method_Rt_get_sizeDelta;
    if (!posPtr || !sizePtr) return false;

    *outPos = ((Tf_get_position_HFA_t)posPtr)(cloneTf, g_method_Tf_get_position);
    *outSize = ((Rt_get_sizeDelta_HFA_t)sizePtr)(cloneTf, g_method_Rt_get_sizeDelta);
    IPALog([NSString stringWithFormat:
              @"[CLONE-RECT] pos=(%g,%g,%g) sizeDelta=(%g,%g)",
              outPos->x, outPos->y, outPos->z, outSize->x, outSize->y]);
    return true;
}

// Hide the clone's Image by zeroing its m_Color alpha and calling
// SetAllDirty so the canvas rebuild picks up the new color. Keeps the
// raycast target so the OnPointerClick hook still sees taps; the actual
// visual is rendered by a UIKit overlay above the Unity layer.
typedef void (*Graphic_SetAllDirty_t)(void *self, void *methodInfo);
static void *g_method_Graphic_SetAllDirty = NULL;

void hideCloneImage(void *cloneTf) {
    if (!ptrLooksValid(cloneTf)) return;
    void *contentTf = transformChildByName(cloneTf, "Content");
    if (!ptrLooksValid(contentTf)) return;
    void *imageTf = transformChildByName(contentTf, "Image");
    if (!ptrLooksValid(imageTf)) imageTf = transformChildByName(contentTf, "IconImage");
    if (!ptrLooksValid(imageTf)) return;
    void *imageGo = gameObjectOf(imageTf);
    if (!ptrLooksValid(imageGo)) return;
    void *imageComp = componentByTypeName(imageGo, "UnityEngine.UI.Image");
    if (!ptrLooksValid(imageComp)) return;

    // Graphic.m_Color @ 0x28 (Color = 4 floats RGBA).
    float *color = (float *)((uint8_t *)imageComp + 0x28);
    color[0] = 1.0f;
    color[1] = 1.0f;
    color[2] = 1.0f;
    color[3] = 0.0f;
    IPALog([NSString stringWithFormat:
              @"[CLONE-HIDE] imageComp=%p m_Color set to (1,1,1,0)", imageComp]);

    if (!g_method_Graphic_SetAllDirty) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return;
        void *klass = p_il2cpp_object_get_class(imageComp);
        if (!klass) return;
        g_method_Graphic_SetAllDirty = p_il2cpp_class_get_method_from_name(klass, "SetAllDirty", 0);
        IPALog([NSString stringWithFormat:
                  @"[CLONE-HIDE] cached Graphic.SetAllDirty method=%p (klass=%p)",
                  g_method_Graphic_SetAllDirty, klass]);
    }
    if (!g_method_Graphic_SetAllDirty) return;
    void *methodPtr = *(void **)g_method_Graphic_SetAllDirty;
    if (!methodPtr) return;
    ((Graphic_SetAllDirty_t)methodPtr)(imageComp, g_method_Graphic_SetAllDirty);
    IPALog(@"[CLONE-HIDE] SetAllDirty invoked");
}

// Probe each GameObject in the clone tree for a text component and log
// it. Helps us figure out where the inherited "メニュー" label lives so we
// can blank it on the clone. Recon-only, no mutations.
void reconTextComponents(void *cloneTf) {
    if (!ptrLooksValid(cloneTf)) return;
    void *cloneGo = gameObjectOf(cloneTf);
    void *contentTf = transformChildByName(cloneTf, "Content");
    void *contentGo = ptrLooksValid(contentTf) ? gameObjectOf(contentTf) : NULL;
    void *imageTf = ptrLooksValid(contentTf) ? transformChildByName(contentTf, "Image") : NULL;
    if (!ptrLooksValid(imageTf) && ptrLooksValid(contentTf)) {
        imageTf = transformChildByName(contentTf, "IconImage");
    }
    void *imageGo = ptrLooksValid(imageTf) ? gameObjectOf(imageTf) : NULL;

    void *grayTf = ptrLooksValid(imageTf) ? transformChildByName(imageTf, "GrayoutCover_Toggle") : NULL;
    void *grayGo = ptrLooksValid(grayTf) ? gameObjectOf(grayTf) : NULL;

    const char *names[] = {
        "TMPro.TextMeshProUGUI",
        "UnityEngine.UI.Text",
        "TMPro.TextMeshPro",
    };
    struct { const char *tag; void *go; } pts[] = {
        { "button-go",  cloneGo },
        { "content-go", contentGo },
        { "image-go",   imageGo },
        { "gray-go",    grayGo },
    };
    for (int p = 0; p < 4; p++) {
        if (!ptrLooksValid(pts[p].go)) continue;
        for (int n = 0; n < 3; n++) {
            void *c = componentByTypeName(pts[p].go, names[n]);
            IPALog([NSString stringWithFormat:
                      @"[TEXT-RECON] %s GetComponent(\"%s\")=%p",
                      pts[p].tag, names[n], c]);
        }
    }
}

// Read the m_Sprite (offset 0xD8) of the Image component on uiButton's
// Content/Image leaf. Used by callers that want to harvest a sprite handle
// from a sibling button without going through the full recon logger.
static void *spriteOfButton(void *uiButton) {
    if (!ptrLooksValid(uiButton)) return NULL;
    void *btnGo = gameObjectOf(uiButton);
    if (!ptrLooksValid(btnGo)) return NULL;
    void *btnTf = goTransformOf(btnGo);
    void *imageTf = findIconImageTransform(btnTf);
    if (!ptrLooksValid(imageTf)) return NULL;
    void *imageGo = gameObjectOf(imageTf);
    if (!ptrLooksValid(imageGo)) return NULL;
    void *imageComp = componentByTypeName(imageGo, "UnityEngine.UI.Image");
    if (!ptrLooksValid(imageComp)) return NULL;
    return readPtr(imageComp, 0xD8);
}

// Apply a sibling sprite to a freshly cloned home utility button. The
// caller passes the gift / friend / menu button as a sprite source; this
// avoids the title atlas-unload trap until a permanent sprite source (a
// bundled PNG / SF Symbol generated Texture2D) is wired up.
static bool applySiblingSpriteToClone(void *cloneGo, void *sourceBtn, const char *sourceTag) {
    if (!ptrLooksValid(cloneGo) || !ptrLooksValid(sourceBtn)) return false;
    void *sprite = spriteOfButton(sourceBtn);
    if (!ptrLooksValid(sprite)) {
        IPALog([NSString stringWithFormat:
                  @"[SPRITE-SWAP clone] no sprite on %s source", sourceTag]);
        return false;
    }
    void *cloneTf = goTransformOf(cloneGo);
    void *imageTf = findIconImageTransform(cloneTf);
    if (!ptrLooksValid(imageTf)) return false;
    void *imageGo = gameObjectOf(imageTf);
    IPALog([NSString stringWithFormat:
              @"[SPRITE-SWAP clone] source=%s sprite=%p", sourceTag, sprite]);
    return swapImageSpriteOnGo(imageGo, sprite, "clone");
}

// Phase 0 verification: apply the gift sprite to the clone. Gift sits on
// the same home strip as the clone, so the atlas is guaranteed loaded for
// the duration the clone is alive. If the clone renders gift icon visibly,
// set_sprite + canvas invalidation work; the white title-swap result was
// purely the title atlas getting unloaded post-scene-transition.
//
// Currently this also still tries the title sprite if no gift swap target
// was passed in - title path is left in place for direct comparison.
void KIOUEditorApplyTitleSpriteToClone(void *cloneGo) {
    (void)cloneGo;
    // Kept as a no-op placeholder so the call site in the clone path stays
    // unchanged while we route through the new sibling sprite helper.
    // The actual swap is now driven from hook_HUP_ctor via giftBtn.
}

// Public recon entry. Walks uiButton -> btnGo -> btnTf -> "Content" ->
// "Image" -> GO -> GetComponent("UnityEngine.UI.Image") -> m_Sprite@+0xD8.
// Logs every step so we can see where it bails when something is missing.
void KIOUEditorReconButtonImage(void *uiButton, const char *tag) {
    if (!ptrLooksValid(uiButton)) {
        IPALog([NSString stringWithFormat:
                  @"[SPRITE-RECON %s] button ptr invalid (%p)", tag, uiButton]);
        return;
    }
    void *btnGo = gameObjectOf(uiButton);
    void *btnTf = goTransformOf(btnGo);
    IPALog([NSString stringWithFormat:
              @"[SPRITE-RECON %s] btn=%p go=%p tf=%p",
              tag, uiButton, btnGo, btnTf]);
    if (!ptrLooksValid(btnTf)) return;

    void *imageTf = findIconImageTransform(btnTf);
    if (!ptrLooksValid(imageTf)) {
        IPALog([NSString stringWithFormat:
                  @"[SPRITE-RECON %s] no Image/IconImage leaf - dumping btnTf:",
                  tag]);
        dumpHierarchy(btnTf, 0, 3);
        return;
    }
    void *imageGo = gameObjectOf(imageTf);
    IPALog([NSString stringWithFormat:
              @"[SPRITE-RECON %s] imageTf=%p imageGo=%p",
              tag, imageTf, imageGo]);
    if (!ptrLooksValid(imageGo)) return;

    void *imageComp = componentByTypeName(imageGo, "UnityEngine.UI.Image");
    IPALog([NSString stringWithFormat:
              @"[SPRITE-RECON %s] GetComponent(\"UnityEngine.UI.Image\")=%p",
              tag, imageComp]);
    if (!ptrLooksValid(imageComp)) return;

    void *sprite = readPtr(imageComp, 0xD8);
    IPALog([NSString stringWithFormat:
              @"[SPRITE-RECON %s] m_Sprite=%p", tag, sprite]);

    // Title side: cache the sprite so the home clone hook can swap it in.
    if (tag && strcmp(tag, "title-menu") == 0 && ptrLooksValid(sprite)) {
        g_titleMenuSprite = sprite;
        IPALog([NSString stringWithFormat:
                  @"[SPRITE-RECON %s] cached title menu sprite for clone swap",
                  tag]);
    }
}

typedef void (*Tf_SetSiblingIndex_directABI_t)(void *thisTf, int32_t idx, void *methodInfo);

void transformSetSiblingIndex(void *transformObj, int32_t idx) {
    if (!ptrLooksValid(transformObj)) return;
    if (!g_method_Tf_SetSiblingIndex) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return;
        void *klass = p_il2cpp_object_get_class(transformObj);
        if (!klass) return;
        g_method_Tf_SetSiblingIndex = p_il2cpp_class_get_method_from_name(klass, "SetSiblingIndex", 1);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached Transform.SetSiblingIndex method=%p (klass=%p)",
                  g_method_Tf_SetSiblingIndex, klass]);
    }
    if (!g_method_Tf_SetSiblingIndex) return;
    void *methodPtr = *(void **)g_method_Tf_SetSiblingIndex;
    if (!methodPtr) {
        IPALog(@"[HOME] Tf.SetSiblingIndex direct: methodPointer NULL");
        return;
    }
    ((Tf_SetSiblingIndex_directABI_t)methodPtr)(transformObj, idx, g_method_Tf_SetSiblingIndex);
}

// Component.get_transform - returns this.transform.
void *transformOf(void *componentObj) {
    if (!ptrLooksValid(componentObj)) return NULL;
    if (!g_method_get_transform) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return NULL;
        void *klass = p_il2cpp_object_get_class(componentObj);
        if (!klass) return NULL;
        g_method_get_transform = p_il2cpp_class_get_method_from_name(klass, "get_transform", 0);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached get_transform method=%p (klass=%p)",
                  g_method_get_transform, klass]);
    }
    return invoke0(g_method_get_transform, componentObj);
}

// Recon: walk every method on UnityEngine.Object (resolved via parent klass
// of any GameObject we already hold) and log each "Instantiate" variant
// with (name, argc, is_generic, method_ptr). From the log we can pick the
// non-generic method handle directly and invoke it later without racing
// the generic ones via get_method_from_name. Pure logging - no invoke.
static void logInstantiateMethods(void *anyGo) {
    if (!p_il2cpp_object_get_class
        || !p_il2cpp_class_get_parent
        || !p_il2cpp_class_get_methods
        || !p_il2cpp_method_get_name
        || !p_il2cpp_method_get_param_count) {
        IPALog(@"[HOME] enum recon: bridge incomplete, skipping");
        return;
    }
    void *goKlass = p_il2cpp_object_get_class(anyGo);
    if (!goKlass) return;
    void *objKlass = p_il2cpp_class_get_parent(goKlass);
    if (!objKlass) return;
    IPALog([NSString stringWithFormat:
              @"[HOME] enum: walking Object klass=%p", objKlass]);
    void *iter = NULL;
    void *method = NULL;
    int hits = 0;
    while ((method = p_il2cpp_class_get_methods(objKlass, &iter)) != NULL) {
        const char *name = p_il2cpp_method_get_name(method);
        if (!name) continue;
        if (strstr(name, "nstantiate") == NULL) continue;
        uint32_t argc = p_il2cpp_method_get_param_count(method);
        int isGeneric = -1;
        if (p_il2cpp_method_is_generic) {
            isGeneric = (int)p_il2cpp_method_is_generic(method);
        }
        IPALog([NSString stringWithFormat:
                  @"[HOME] enum:   %s argc=%u generic=%d method=%p",
                  name, argc, isGeneric, method]);
        hits++;
    }
    IPALog([NSString stringWithFormat:
              @"[HOME] enum: %d Instantiate variants found", hits]);
}

// Walk a klass's methods and return the first one matching name + argc that
// is NOT generic. Hand-rolled because il2cpp_class_get_method_from_name has
// no generic filter and races the generic Instantiate descriptors first.
static void *findNonGenericMethod(void *klass, const char *targetName, uint32_t targetArgc) {
    if (!klass) return NULL;
    if (!p_il2cpp_class_get_methods
        || !p_il2cpp_method_get_name
        || !p_il2cpp_method_get_param_count
        || !p_il2cpp_method_is_generic) return NULL;
    void *iter = NULL;
    void *method = NULL;
    while ((method = p_il2cpp_class_get_methods(klass, &iter)) != NULL) {
        const char *name = p_il2cpp_method_get_name(method);
        if (!name) continue;
        if (strcmp(name, targetName) != 0) continue;
        if (p_il2cpp_method_get_param_count(method) != targetArgc) continue;
        if (p_il2cpp_method_is_generic(method)) continue;
        return method;
    }
    return NULL;
}

// Object.Instantiate(Object original) - explicit non-generic match.
// Clone goes to root scene with null parent. Use SetParent in a later phase
// to slot it into the home layout.
static void *instantiateCloneNonGeneric(void *originalGo) {
    if (!ptrLooksValid(originalGo)) return NULL;
    if (!p_il2cpp_runtime_invoke
        || !p_il2cpp_object_get_class
        || !p_il2cpp_class_get_parent) return NULL;
    if (!g_method_Instantiate1NonGen) {
        void *goKlass = p_il2cpp_object_get_class(originalGo);
        if (!goKlass) return NULL;
        void *objKlass = p_il2cpp_class_get_parent(goKlass);
        if (!objKlass) return NULL;
        g_method_Instantiate1NonGen = findNonGenericMethod(objKlass, "Instantiate", 1);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached non-generic Instantiate(Object) method=%p (objKlass=%p)",
                  g_method_Instantiate1NonGen, objKlass]);
    }
    if (!g_method_Instantiate1NonGen) return NULL;
    void *originalRef = originalGo;
    void *params[1] = { &originalRef };
    return p_il2cpp_runtime_invoke(g_method_Instantiate1NonGen, NULL, params, NULL);
}

// Direct call into MethodInfo->methodPointer (offset 0 on Unity 6 IL2CPP),
// bypassing runtime_invoke entirely. IL2CPP appends a MethodInfo* slot to
// every method's native signature; the C ABI for the static one-arg
// Object.Instantiate(Object) is:
//   Object* (Object* original, const MethodInfo* method)
// Tried because the runtime_invoke path crashes inside the invoker even
// after the recon confirmed we hold the non-generic method handle. The
// methodPointer is the actually-generated native function, no invoker
// trampoline involved.
typedef void *(*Instantiate1_directABI_t)(void *original, void *methodInfo);

void *instantiateCloneDirect(void *originalGo) {
    if (!ptrLooksValid(originalGo)) return NULL;
    if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_parent) return NULL;
    if (!g_method_Instantiate1NonGen) {
        void *goKlass = p_il2cpp_object_get_class(originalGo);
        if (!goKlass) return NULL;
        void *objKlass = p_il2cpp_class_get_parent(goKlass);
        if (!objKlass) return NULL;
        g_method_Instantiate1NonGen = findNonGenericMethod(objKlass, "Instantiate", 1);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached non-generic Instantiate(Object) method=%p (objKlass=%p)",
                  g_method_Instantiate1NonGen, objKlass]);
    }
    if (!g_method_Instantiate1NonGen) return NULL;
    void *methodPtr = *(void **)g_method_Instantiate1NonGen;
    if (!methodPtr) {
        IPALog(@"[HOME] direct: methodPointer at offset 0 is NULL");
        return NULL;
    }
    IPALog([NSString stringWithFormat:
              @"[HOME] direct call: methodPtr=%p methodInfo=%p original=%p",
              methodPtr, g_method_Instantiate1NonGen, originalGo]);
    return ((Instantiate1_directABI_t)methodPtr)(originalGo, g_method_Instantiate1NonGen);
}

// UnityEngine.Object.Instantiate(Object original, Transform parent) - static.
// 2-arg overload picked over the argc=1 version because the argc=1 path
// matched the generic Instantiate<T>(T) descriptor and runtime_invoke
// crashed inside the un-inflated generic call. The 2-arg non-generic
// overload coexists with a generic counterpart too, so we still race the
// lookup; if this also crashes we will need to enumerate methods and
// filter by il2cpp_method_is_generic.
static void *instantiateCloneWithParent(void *originalGo, void *parentTransform) {
    if (!ptrLooksValid(originalGo)) return NULL;
    if (!p_il2cpp_runtime_invoke
        || !p_il2cpp_object_get_class
        || !p_il2cpp_class_get_parent
        || !p_il2cpp_class_get_method_from_name) return NULL;
    if (!g_method_Instantiate2) {
        void *goKlass = p_il2cpp_object_get_class(originalGo);
        if (!goKlass) return NULL;
        void *objKlass = p_il2cpp_class_get_parent(goKlass);
        if (!objKlass) {
            IPALog(@"[HOME] Instantiate lookup: parent klass NULL");
            return NULL;
        }
        g_method_Instantiate2 = p_il2cpp_class_get_method_from_name(objKlass, "Instantiate", 2);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached Instantiate(Obj,Tf) method=%p (goKlass=%p objKlass=%p)",
                  g_method_Instantiate2, goKlass, objKlass]);
    }
    if (!g_method_Instantiate2) return NULL;
    void *originalRef = originalGo;
    void *parentRef = parentTransform;
    void *params[2] = { &originalRef, &parentRef };
    return p_il2cpp_runtime_invoke(g_method_Instantiate2, NULL, params, NULL);
}

