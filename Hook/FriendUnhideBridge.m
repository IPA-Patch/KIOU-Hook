#import "Hook/Common.h"
#import "Hook/FriendUnhideBridge.h"
#import "logging.h"
#import <dlfcn.h>
#import "Hook/FriendUnhideBridge_Private.h"

// ===========================================================================
// Hook/FriendUnhideBridge.m — il2cpp + Unity bridging layer for the friend
// button unhide + settings redirect hook body in Hook/FriendUnhide.m.
//
// Split out of FriendUnhide.m to keep both files under the project's
// 600-line hard-split threshold. See Hook/FriendUnhideBridge.h for the
// tiny external surface; every other declaration inside this file stays
// TU-private (static).
// ===========================================================================

// ---------------------------------------------------------------------------
// il2cpp runtime bridge (Phase 1a: resolved but unused; Phase 1b will call
// invoke + class_from_name + class_get_method_from_name for SetActive).
// ---------------------------------------------------------------------------

typedef void *(*il2cpp_runtime_invoke_t)(void *method, void *obj, void **params, void **exc);
typedef void *(*il2cpp_class_from_name_t)(void *image, const char *ns, const char *name);
typedef void *(*il2cpp_string_new_t)(const char *s);
il2cpp_string_new_t p_il2cpp_string_new = NULL;

// UnityFramework load address - captured at install. Used to direct-call
// methods by RVA (GameObject.GetComponent(string) at 0x6BCA6AC).
uintptr_t g_unityBaseAddr = 0;
typedef void *(*il2cpp_class_get_method_from_name_t)(void *klass, const char *name, int argc);
typedef void *(*il2cpp_object_get_class_t)(void *obj);
typedef void *(*il2cpp_class_get_parent_t)(void *klass);
typedef void *(*il2cpp_class_get_methods_t)(void *klass, void **iter);
typedef const char *(*il2cpp_method_get_name_t)(void *method);
typedef uint32_t (*il2cpp_method_get_param_count_t)(void *method);
typedef bool (*il2cpp_method_is_generic_t)(void *method);

il2cpp_runtime_invoke_t             p_il2cpp_runtime_invoke = NULL;
il2cpp_class_from_name_t            p_il2cpp_class_from_name = NULL;
il2cpp_class_get_method_from_name_t p_il2cpp_class_get_method_from_name = NULL;
il2cpp_object_get_class_t           p_il2cpp_object_get_class = NULL;
il2cpp_class_get_parent_t           p_il2cpp_class_get_parent = NULL;
il2cpp_class_get_methods_t          p_il2cpp_class_get_methods = NULL;
il2cpp_method_get_name_t            p_il2cpp_method_get_name = NULL;
il2cpp_method_get_param_count_t     p_il2cpp_method_get_param_count = NULL;
il2cpp_method_is_generic_t          p_il2cpp_method_is_generic = NULL;

static void resolveIl2cppBridge(void) {
    if (p_il2cpp_runtime_invoke) return;
    p_il2cpp_runtime_invoke = (il2cpp_runtime_invoke_t)dlsym(RTLD_DEFAULT, "il2cpp_runtime_invoke");
    p_il2cpp_class_from_name = (il2cpp_class_from_name_t)dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    p_il2cpp_class_get_method_from_name = (il2cpp_class_get_method_from_name_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    p_il2cpp_object_get_class = (il2cpp_object_get_class_t)dlsym(RTLD_DEFAULT, "il2cpp_object_get_class");
    p_il2cpp_class_get_parent = (il2cpp_class_get_parent_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_parent");
    p_il2cpp_class_get_methods = (il2cpp_class_get_methods_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_methods");
    p_il2cpp_method_get_name = (il2cpp_method_get_name_t)dlsym(RTLD_DEFAULT, "il2cpp_method_get_name");
    p_il2cpp_method_get_param_count = (il2cpp_method_get_param_count_t)dlsym(RTLD_DEFAULT, "il2cpp_method_get_param_count");
    p_il2cpp_method_is_generic = (il2cpp_method_is_generic_t)dlsym(RTLD_DEFAULT, "il2cpp_method_is_generic");
    IPALog([NSString stringWithFormat:
              @"[HOME] il2cpp bridge: runtime_invoke=%p class_from_name=%p class_get_method_from_name=%p object_get_class=%p class_get_parent=%p class_get_methods=%p method_get_name=%p method_get_param_count=%p method_is_generic=%p",
              p_il2cpp_runtime_invoke,
              p_il2cpp_class_from_name,
              p_il2cpp_class_get_method_from_name,
              p_il2cpp_object_get_class,
              p_il2cpp_class_get_parent,
              p_il2cpp_class_get_methods,
              p_il2cpp_method_get_name,
              p_il2cpp_method_get_param_count,
              p_il2cpp_method_is_generic]);
}

// ---------------------------------------------------------------------------
// Cached method pointers - resolved from the live objects' klasses on the
// first ctor fire, then reused. The il2cpp method pointers are stable for
// the lifetime of the dylib so caching is safe.
// ---------------------------------------------------------------------------

static void *g_method_get_gameObject     = NULL;  // Component.get_gameObject
static void *g_method_get_transform      = NULL;  // Component.get_transform (cached off Component-derived obj)
static void *g_method_GO_get_transform   = NULL;  // GameObject.get_transform
static void *g_method_SetActive          = NULL;  // GameObject.SetActive
static void *g_method_Instantiate2       = NULL;  // UnityEngine.Object.Instantiate(Object, Transform)
static void *g_method_Instantiate1NonGen = NULL;  // UnityEngine.Object.Instantiate(Object) non-generic
static void *g_method_Tf_get_parent      = NULL;  // Transform.get_parent
static void *g_method_Tf_SetParent       = NULL;  // Transform.SetParent(Transform,bool)
static void *g_method_Tf_GetSiblingIndex = NULL;  // Transform.GetSiblingIndex
static void *g_method_Tf_SetSiblingIndex = NULL;  // Transform.SetSiblingIndex(int)
static void *g_method_Tf_get_childCount  = NULL;  // Transform.get_childCount
static void *g_method_Tf_GetChild        = NULL;  // Transform.GetChild(int)
static void *g_method_Obj_get_name       = NULL;  // UnityEngine.Object.get_name

// HomeUtilityView pointer the clone is currently parented under. Kept for
// historical reasons - the menu-button clone path is disabled in favor of
// repurposing the existing friend button as the settings entry point.
void *g_lastClonedView = NULL;

// GameObject pointer of the current menu-button clone (unused now that the
// clone code path is disabled). Preserved so the dead helpers in this file
// still compile.
void *g_cloneGo = NULL;

// Friend button GameObject. The retail friend button has no live wiring
// (taps trigger a "Coming soon" popup), so we redirect its OnPointerClick
// to the KiouEditor settings sheet instead. Captured every time the
// HomeUtilityPresenter ctor fires, so it stays current across scene
// re-entries.
void *g_friendGo = NULL;

// One-time guard for the Instantiate-method enumeration recon (Phase 2a
// debug). After the first fire we know which method handle is the
// non-generic Object.Instantiate so we do not need to re-walk every time.
static bool g_reconLogged = false;

// Invoke instance method 0-arg returning a managed object pointer.
void *invoke0(void *method, void *obj) {
    if (!p_il2cpp_runtime_invoke || !method) return NULL;
    return p_il2cpp_runtime_invoke(method, obj, NULL, NULL);
}

// Invoke instance method that takes a single bool argument.
static void invokeSetActive(void *method, void *obj, bool value) {
    if (!p_il2cpp_runtime_invoke || !method) return;
    bool v = value;
    void *params[1] = { &v };
    p_il2cpp_runtime_invoke(method, obj, params, NULL);
}

void *gameObjectOf(void *componentObj) {
    if (!ptrLooksValid(componentObj)) return NULL;
    if (!g_method_get_gameObject) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return NULL;
        void *klass = p_il2cpp_object_get_class(componentObj);
        if (!klass) return NULL;
        g_method_get_gameObject = p_il2cpp_class_get_method_from_name(klass, "get_gameObject", 0);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached get_gameObject method=%p (klass=%p)",
                  g_method_get_gameObject, klass]);
    }
    return invoke0(g_method_get_gameObject, componentObj);
}

void setActive(void *gameObject, bool value) {
    if (!ptrLooksValid(gameObject)) return;
    if (!g_method_SetActive) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return;
        void *klass = p_il2cpp_object_get_class(gameObject);
        if (!klass) return;
        g_method_SetActive = p_il2cpp_class_get_method_from_name(klass, "SetActive", 1);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached SetActive method=%p (klass=%p)",
                  g_method_SetActive, klass]);
    }
    invokeSetActive(g_method_SetActive, gameObject, value);
}

// GameObject.get_transform - returns the GameObject's transform. Separate
// from the Component.get_transform cache because they live on different
// klasses and the il2cpp method handles are not interchangeable.
void *goTransformOf(void *gameObject) {
    if (!ptrLooksValid(gameObject)) return NULL;
    if (!g_method_GO_get_transform) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return NULL;
        void *klass = p_il2cpp_object_get_class(gameObject);
        if (!klass) return NULL;
        g_method_GO_get_transform = p_il2cpp_class_get_method_from_name(klass, "get_transform", 0);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached GameObject.get_transform method=%p (klass=%p)",
                  g_method_GO_get_transform, klass]);
    }
    return invoke0(g_method_GO_get_transform, gameObject);
}

// Transform.get_parent - the Transform parent in the scene hierarchy.
void *transformParentOf(void *transformObj) {
    if (!ptrLooksValid(transformObj)) return NULL;
    if (!g_method_Tf_get_parent) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return NULL;
        void *klass = p_il2cpp_object_get_class(transformObj);
        if (!klass) return NULL;
        g_method_Tf_get_parent = p_il2cpp_class_get_method_from_name(klass, "get_parent", 0);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached Transform.get_parent method=%p (klass=%p)",
                  g_method_Tf_get_parent, klass]);
    }
    return invoke0(g_method_Tf_get_parent, transformObj);
}

// Transform.SetParent(Transform parent, bool worldPositionStays).
// runtime_invoke hung the main thread on this method (same invoker_method
// problem the static Instantiate hit), so we go through methodPointer.
// IL2CPP instance-method ABI for this signature:
//   void (Transform* this, Transform* parent, bool wps, MethodInfo* method)
typedef void (*Tf_SetParent_directABI_t)(void *thisTf, void *parent, bool wps, void *methodInfo);

void transformSetParent(void *transformObj, void *newParent, bool worldPositionStays) {
    if (!ptrLooksValid(transformObj)) return;
    if (!g_method_Tf_SetParent) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return;
        void *klass = p_il2cpp_object_get_class(transformObj);
        if (!klass) return;
        g_method_Tf_SetParent = p_il2cpp_class_get_method_from_name(klass, "SetParent", 2);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached Transform.SetParent(Tf,bool) method=%p (klass=%p)",
                  g_method_Tf_SetParent, klass]);
    }
    if (!g_method_Tf_SetParent) return;
    void *methodPtr = *(void **)g_method_Tf_SetParent;
    if (!methodPtr) {
        IPALog(@"[HOME] Tf.SetParent direct: methodPointer NULL");
        return;
    }
    IPALog([NSString stringWithFormat:
              @"[HOME] Tf.SetParent direct: methodPtr=%p this=%p parent=%p wps=%d",
              methodPtr, transformObj, newParent, (int)worldPositionStays]);
    ((Tf_SetParent_directABI_t)methodPtr)(transformObj, newParent, worldPositionStays, g_method_Tf_SetParent);
}

// Transform.GetSiblingIndex -> Int32. Direct call instead of runtime_invoke
// for the same reason as above; this also dodges the boxed value-type
// return path entirely (the direct ABI just returns int32 by value).
typedef int32_t (*Tf_GetSiblingIndex_directABI_t)(void *thisTf, void *methodInfo);

int32_t transformGetSiblingIndex(void *transformObj) {
    if (!ptrLooksValid(transformObj)) return -1;
    if (!g_method_Tf_GetSiblingIndex) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return -1;
        void *klass = p_il2cpp_object_get_class(transformObj);
        if (!klass) return -1;
        g_method_Tf_GetSiblingIndex = p_il2cpp_class_get_method_from_name(klass, "GetSiblingIndex", 0);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached Transform.GetSiblingIndex method=%p (klass=%p)",
                  g_method_Tf_GetSiblingIndex, klass]);
    }
    if (!g_method_Tf_GetSiblingIndex) return -1;
    void *methodPtr = *(void **)g_method_Tf_GetSiblingIndex;
    if (!methodPtr) {
        IPALog(@"[HOME] Tf.GetSiblingIndex direct: methodPointer NULL");
        return -1;
    }
    return ((Tf_GetSiblingIndex_directABI_t)methodPtr)(transformObj, g_method_Tf_GetSiblingIndex);
}

typedef int32_t (*Tf_get_childCount_directABI_t)(void *thisTf, void *methodInfo);
typedef void *(*Tf_GetChild_directABI_t)(void *thisTf, int32_t idx, void *methodInfo);
typedef void *(*Obj_get_name_directABI_t)(void *thisObj, void *methodInfo);

int32_t transformChildCount(void *transformObj) {
    if (!ptrLooksValid(transformObj)) return 0;
    if (!g_method_Tf_get_childCount) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return 0;
        void *klass = p_il2cpp_object_get_class(transformObj);
        if (!klass) return 0;
        g_method_Tf_get_childCount = p_il2cpp_class_get_method_from_name(klass, "get_childCount", 0);
    }
    if (!g_method_Tf_get_childCount) return 0;
    void *methodPtr = *(void **)g_method_Tf_get_childCount;
    if (!methodPtr) return 0;
    return ((Tf_get_childCount_directABI_t)methodPtr)(transformObj, g_method_Tf_get_childCount);
}

void *transformGetChild(void *transformObj, int32_t idx) {
    if (!ptrLooksValid(transformObj)) return NULL;
    if (!g_method_Tf_GetChild) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return NULL;
        void *klass = p_il2cpp_object_get_class(transformObj);
        if (!klass) return NULL;
        g_method_Tf_GetChild = p_il2cpp_class_get_method_from_name(klass, "GetChild", 1);
    }
    if (!g_method_Tf_GetChild) return NULL;
    void *methodPtr = *(void **)g_method_Tf_GetChild;
    if (!methodPtr) return NULL;
    return ((Tf_GetChild_directABI_t)methodPtr)(transformObj, idx, g_method_Tf_GetChild);
}

// UnityEngine.Object.get_name -> System.String. Walks up the klass chain
// once on first hit since Transform's klass redeclares get_name only if
// overridden - but get_method_from_name searches parents too in IL2CPP.
NSString *objectName(void *unityObj) {
    if (!ptrLooksValid(unityObj)) return nil;
    if (!g_method_Obj_get_name) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return nil;
        void *klass = p_il2cpp_object_get_class(unityObj);
        if (!klass) return nil;
        g_method_Obj_get_name = p_il2cpp_class_get_method_from_name(klass, "get_name", 0);
        IPALog([NSString stringWithFormat:
                  @"[HOME] cached Object.get_name method=%p (klass=%p)",
                  g_method_Obj_get_name, klass]);
    }
    if (!g_method_Obj_get_name) return nil;
    void *methodPtr = *(void **)g_method_Obj_get_name;
    if (!methodPtr) return nil;
    void *strObj = ((Obj_get_name_directABI_t)methodPtr)(unityObj, g_method_Obj_get_name);
    return il2cppStringToNSString(strObj);
}

// Walk the Transform tree under `tfObj`, log each node's name with
// indentation. The clone is brand new so we cap depth to keep the log
// readable. Used purely as a recon pass for Phase 2c (label rewrite).
void dumpHierarchy(void *tfObj, int depth, int maxDepth) {
    if (!ptrLooksValid(tfObj)) return;
    if (depth > maxDepth) return;
    NSString *name = objectName(tfObj);
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    IPALog([NSString stringWithFormat:
              @"[HOME] hier %@tf=%p name=%@",
              indent, tfObj, name ?: @"<null>"]);
    int32_t cc = transformChildCount(tfObj);
    for (int32_t i = 0; i < cc; i++) {
        void *child = transformGetChild(tfObj, i);
        dumpHierarchy(child, depth + 1, maxDepth);
    }
}

// Find the immediate child Transform whose Object.get_name matches.
void *transformChildByName(void *parentTf, const char *targetName) {
    if (!ptrLooksValid(parentTf) || !targetName) return NULL;
    int32_t cc = transformChildCount(parentTf);
    NSString *needle = [NSString stringWithUTF8String:targetName];
    for (int32_t i = 0; i < cc; i++) {
        void *child = transformGetChild(parentTf, i);
        if (!ptrLooksValid(child)) continue;
        NSString *name = objectName(child);
        if ([name isEqualToString:needle]) return child;
    }
    return NULL;
}

// GameObject.GetComponent(string type) at UnityFramework + 0x6BCA6AC. The
// codegen wrapper here is a thin FreeFunction marshal to native
// Scripting::GetScriptingWrapperOfComponentOfGameObject - probably ignores
// MethodInfo* so passing NULL is OK. If it crashes we'll revisit with proper
// klass-walked MethodInfo* resolution.
#define RVA_GO_GETCOMPONENT_STRING 0x6BCA6AC

typedef void *(*GO_GetComponent_string_directABI_t)(void *thisGo, void *typeStr, void *methodInfo);

void *componentByTypeName(void *gameObject, const char *typeName) {
    if (!ptrLooksValid(gameObject) || !typeName) return NULL;
    if (!p_il2cpp_string_new || g_unityBaseAddr == 0) return NULL;
    void *typeStr = p_il2cpp_string_new(typeName);
    if (!typeStr) return NULL;
    GO_GetComponent_string_directABI_t fn =
        (GO_GetComponent_string_directABI_t)(g_unityBaseAddr + RVA_GO_GETCOMPONENT_STRING);
    return fn(gameObject, typeStr, NULL);
}

// Walks a UIButton-shaped hierarchy for the leaf that owns the icon sprite.
// HomeUtilityButton* puts the icon at Content/Image while TitleScene's
// _titleMenuButton uses Content/IconImage. Try both.
void *findIconImageTransform(void *btnTf) {
    if (!ptrLooksValid(btnTf)) return NULL;
    void *contentTf = transformChildByName(btnTf, "Content");
    if (!ptrLooksValid(contentTf)) return NULL;
    void *imageTf = transformChildByName(contentTf, "Image");
    if (!ptrLooksValid(imageTf)) {
        imageTf = transformChildByName(contentTf, "IconImage");
    }
    return imageTf;
}

// Sprite captured from the TitleScene._titleMenuButton on the first title
// MoveNext fire. NULL until then (and during fresh launches that drop the
// user directly into a non-title screen).
void *g_titleMenuSprite = NULL;


// UnityEngine.UI.Image.set_sprite resolved off the live Image component's
// klass once we have one; reused per clone Image swap. set_sprite has only
// one overload so class_get_method_from_name is unambiguous here.
typedef void (*Image_set_sprite_directABI_t)(void *thisImg, void *sprite, void *methodInfo);
static void *g_method_Image_set_sprite = NULL;

bool swapImageSpriteOnGo(void *imageHostGo, void *newSprite, const char *tag) {
    if (!ptrLooksValid(imageHostGo) || !ptrLooksValid(newSprite)) return false;
    void *imageComp = componentByTypeName(imageHostGo, "UnityEngine.UI.Image");
    if (!ptrLooksValid(imageComp)) {
        IPALog([NSString stringWithFormat:
                  @"[SPRITE-SWAP %s] no Image component on go=%p", tag, imageHostGo]);
        return false;
    }
    if (!g_method_Image_set_sprite) {
        if (!p_il2cpp_object_get_class || !p_il2cpp_class_get_method_from_name) return false;
        void *klass = p_il2cpp_object_get_class(imageComp);
        if (!klass) return false;
        g_method_Image_set_sprite =
            p_il2cpp_class_get_method_from_name(klass, "set_sprite", 1);
        IPALog([NSString stringWithFormat:
                  @"[SPRITE-SWAP %s] cached Image.set_sprite method=%p (klass=%p)",
                  tag, g_method_Image_set_sprite, klass]);
    }
    if (!g_method_Image_set_sprite) return false;
    void *methodPtr = *(void **)g_method_Image_set_sprite;
    if (!methodPtr) {
        IPALog([NSString stringWithFormat:
                  @"[SPRITE-SWAP %s] set_sprite methodPointer is NULL", tag]);
        return false;
    }
    IPALog([NSString stringWithFormat:
              @"[SPRITE-SWAP %s] applying sprite=%p to imageComp=%p (was m_Sprite=%p)",
              tag, newSprite, imageComp, readPtr(imageComp, 0xD8)]);
    ((Image_set_sprite_directABI_t)methodPtr)(imageComp, newSprite, g_method_Image_set_sprite);
    return true;
}

// Read the m_Sprite name on the clone's Image so we can tell whether the
// "メニュー" label is baked into the sprite (sprite name suggests a
// combined icon+text texture) or actually rendered separately somewhere.
void reconSpriteName(void *cloneTf) {
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
    void *sprite = readPtr(imageComp, 0xD8);
    if (!ptrLooksValid(sprite)) return;
    NSString *name = objectName(sprite);
    IPALog([NSString stringWithFormat:
              @"[SPRITE-NAME] clone Image.m_Sprite=%p name=\"%@\"",
              sprite, name ?: @"<null>"]);
}

// ---------------------------------------------------------------------------
// FriendUnhideBridgeInit — one-shot bootstrap called from
// KIOUEditorInstallFriendUnhideHook before the two RVAs are installed.
// Resolves the il2cpp bridge and stashes UnityFramework's base address so
// the direct-ABI helpers in FriendUnhideBridgeUI.m have their inputs ready.
// Safe to call multiple times; each call is idempotent.
// ---------------------------------------------------------------------------
void FriendUnhideBridgeInit(uintptr_t unityBase) {
    resolveIl2cppBridge();
    g_unityBaseAddr = unityBase;
    if (!p_il2cpp_string_new) {
        p_il2cpp_string_new = (il2cpp_string_new_t)dlsym(RTLD_DEFAULT, "il2cpp_string_new");
    }
}
