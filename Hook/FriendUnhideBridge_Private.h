#pragma once

#import <Foundation/Foundation.h>
#import <stdbool.h>
#import <stdint.h>

// ===========================================================================
// Hook/FriendUnhideBridge_Private.h — declarations shared between
// Hook/FriendUnhideBridge.m and Hook/FriendUnhideBridgeUI.m.
//
// The two .m files were split out of the 1121-line Hook/FriendUnhide.m
// to keep every translation unit under the 600-line hard threshold. Both
// halves are logically one bridge; this header exists only so the split
// compiles.
//
// PRIVATE: not a public API of KIOU-Hook. Consumer tweaks continue to
// import Hook/Common.h + Hook/FriendUnhideBridge.h.
// ===========================================================================

// il2cpp runtime bridge state — resolved via dlsym inside
// FriendUnhideBridgeInit() (Bridge.m).
typedef void *(*il2cpp_runtime_invoke_t)(void *method, void *obj, void **params, void **exc);
typedef void *(*il2cpp_class_from_name_t)(void *image, const char *ns, const char *name);
typedef void *(*il2cpp_string_new_t)(const char *s);
typedef void *(*il2cpp_class_get_method_from_name_t)(void *klass, const char *name, int argc);
typedef void *(*il2cpp_object_get_class_t)(void *obj);
typedef void *(*il2cpp_class_get_parent_t)(void *klass);
typedef void *(*il2cpp_class_get_methods_t)(void *klass, void **iter);
typedef const char *(*il2cpp_method_get_name_t)(void *method);
typedef uint32_t (*il2cpp_method_get_param_count_t)(void *method);
typedef bool (*il2cpp_method_is_generic_t)(void *method);

extern il2cpp_string_new_t                    p_il2cpp_string_new;
extern il2cpp_runtime_invoke_t                p_il2cpp_runtime_invoke;
extern il2cpp_class_from_name_t               p_il2cpp_class_from_name;
extern il2cpp_class_get_method_from_name_t    p_il2cpp_class_get_method_from_name;
extern il2cpp_object_get_class_t              p_il2cpp_object_get_class;
extern il2cpp_class_get_parent_t              p_il2cpp_class_get_parent;
extern il2cpp_class_get_methods_t             p_il2cpp_class_get_methods;
extern il2cpp_method_get_name_t               p_il2cpp_method_get_name;
extern il2cpp_method_get_param_count_t        p_il2cpp_method_get_param_count;
extern il2cpp_method_is_generic_t             p_il2cpp_method_is_generic;

// UnityFramework base captured at install; used by direct-ABI callers.
extern uintptr_t g_unityBaseAddr;

// Internal helpers shared across the split. Not part of the public bridge
// header (Hook/FriendUnhideBridge.h) — consumers never call these.
void *invoke0(void *method, void *obj);
NSString *objectName(void *unityObj);
void *transformChildByName(void *parentTf, const char *targetName);
void *componentByTypeName(void *gameObject, const char *typeName);
int32_t transformChildCount(void *transformObj);
void *transformGetChild(void *transformObj, int32_t idx);
void *findIconImageTransform(void *btnTf);

// Sprite ops used across the split. `g_titleMenuSprite` is captured by
// KIOUEditorReconButtonImage (BridgeUI.m) on the title side and later
// swapped onto the home clone via swapImageSpriteOnGo (Bridge.m).
extern void *g_titleMenuSprite;
bool swapImageSpriteOnGo(void *imageHostGo, void *newSprite, const char *tag);

// il2cpp method-handle caches shared between the split. Defined in
// FriendUnhideBridge.m; used from FriendUnhideBridgeUI.m as well because
// the sibling / instantiate / get_transform paths span both files.
extern void *g_method_get_transform;      // Component.get_transform
extern void *g_method_Instantiate2;       // UnityEngine.Object.Instantiate(Object, Transform)
extern void *g_method_Instantiate1NonGen; // UnityEngine.Object.Instantiate(Object) non-generic
extern void *g_method_Tf_SetSiblingIndex; // Transform.SetSiblingIndex(int)
