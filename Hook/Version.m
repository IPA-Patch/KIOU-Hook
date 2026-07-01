#import "Hook/Common.h"
#import "logging.h"
#import <dlfcn.h>

// ===========================================================================
// Hook/Version.m — TitleScene.<OnActivateAsync>d__10.MoveNext.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_Version.m.
//
// Title-screen version label is rendered as:
//   _appVersionText.SetTextFormat(_appVersionFormat, Application.version)
// We tamper _appVersionFormat (TitleScene+0x40, il2cpp String*) before the
// original MoveNext runs the SetTextFormat call. Appending "+ (commit)"
// to the format string is rendered verbatim by string.Format (no
// positional placeholder), so the displayed text becomes e.g.
// "v1.0.1+ (b5544ef)".
//
//   sm + 0x20 = TitleScene*
//
// The patch is guarded by a hasSuffix check on the current format string
// instead of a process-wide once-flag. This makes it idempotent within an
// async state machine (MoveNext is invoked on every await resumption) AND
// automatically re-patches when TitleScene is regenerated (e.g. on a
// back-to-title navigation).
// ===========================================================================

typedef void (*TitleSceneMoveNext_t)(void *sm);
typedef void *(*il2cpp_string_new_t)(const char *s);

static TitleSceneMoveNext_t s_origTitleSceneMoveNext = NULL;
static il2cpp_string_new_t  s_il2cpp_string_new      = NULL;

static bool g_titleSpriteReconDone = false;

static void hook_TitleSceneMoveNext(void *sm) {
    if (ptrLooksValid(sm) && s_il2cpp_string_new) {
        @try {
            void *titleScene = readPtr(sm, 0x20);
            if (titleScene) {
                if (!g_titleSpriteReconDone) {
                    void *titleMenuBtn = readPtr(titleScene, 0x30);
                    // Stubbed in Hook/Common.m until Hook/FriendUnhide.m
                    // lands with the real il2cpp bridge.
                    KIOUEditorReconButtonImage(titleMenuBtn, "title-menu");
                    g_titleSpriteReconDone = true;
                }
                void *origFormatStr = readPtr(titleScene, 0x40);
                NSString *origFormat = il2cppStringToNSString(origFormatStr);
                if (origFormat.length > 0) {
                    NSString *suffix = [NSString stringWithFormat:
                                        @"+ (%s)", KIOU_EDITOR_COMMIT];
                    if (![origFormat hasSuffix:suffix]) {
                        NSString *newFormat = [origFormat stringByAppendingString:suffix];
                        void *newStr = s_il2cpp_string_new(newFormat.UTF8String);
                        if (ptrLooksValid(newStr)) {
                            *(void *volatile *)((uint8_t *)titleScene + 0x40) = newStr;
                            IPALog([NSString stringWithFormat:
                                    @"[VERSION] _appVersionFormat: \"%@\" -> \"%@\"",
                                    origFormat, newFormat]);
                        }
                    }
                }
            }
        } @catch (NSException *e) {
            IPALog([NSString stringWithFormat:
                    @"[VERSION] format patch exception: %@", e]);
        }
    }

    if (s_origTitleSceneMoveNext) {
        s_origTitleSceneMoveNext(sm);
    }
}

void KIOUEditorInstallVersionHook(uintptr_t unityBase) {
    s_il2cpp_string_new =
        (il2cpp_string_new_t)dlsym(RTLD_DEFAULT, "il2cpp_string_new");
    if (!s_il2cpp_string_new) {
        IPALog(@"[VERSION] dlsym(il2cpp_string_new) failed — format patch will NOP");
        // Continue and still publish the hook; the body NULL-guards on
        // s_il2cpp_string_new and falls through to orig.
    }
    s_origTitleSceneMoveNext = (TitleSceneMoveNext_t)KIOUHookInstall(
        KIOU_HOOK_NAME_TITLE_SCENE_MOVENEXT,
        (void *)hook_TitleSceneMoveNext, unityBase);
    IPALog([NSString stringWithFormat:
            @"[VERSION] installed: orig=%p commit=%s",
            (void *)s_origTitleSceneMoveNext, KIOU_EDITOR_COMMIT]);
}
