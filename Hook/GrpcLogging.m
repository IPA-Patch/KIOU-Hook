#import "KIOUHook.h"
#import "Account/Persistence.h"
#import "il2cpp.h"
#import "logging.h"
#import <dlfcn.h>

// ===========================================================================
// Hook/GrpcLogging.m — swap x-user-id gRPC header on account switch.
//
// The swap runs at Project.Network.HeaderProvider.SetOrUpdateHeader, which
// is the upstream managed-only site where the app registers its request
// headers (well before HttpMessageInvoker.SendAsync hands the request to
// Cysharp Yaha's Rust FFI). Doing the swap there avoids the crash class
// where touching the request / self+0x10 / HttpHeaders internal dictionary
// after the SendAsync boundary blows up inside HttpHeaders.GetEnumerator
// on a 0x20025xxx truncated-32-bit pointer.
//
// The HttpMessageInvoker.SendAsync hook is kept as a bare passthrough so
// its cave / entry slot stays wired — useful for future cave-integrity
// bisection — but the body itself does nothing beyond forwarding to orig.
//
// Hook sites (resolved by name at install time):
//   Project.Network.HeaderProvider.SetOrUpdateHeader
//   HttpMessageInvoker.SendAsync
// ===========================================================================

// il2cpp string helper resolved via dlsym.
typedef void *(*GrpcIl2CppStringNew_t)(const char *utf8);
static GrpcIl2CppStringNew_t g_GrpcStringNew = NULL;

// Orig cave-bypasses.
typedef void *(*GenericSendAsync_t)(void *self, void *request, void *ct, void *mi);
typedef void  (*HeaderProviderSetOrUpdate_t)(void *self, void *keyStr, void *valueStr, void *mi);
static GenericSendAsync_t          s_origHttpMsgInvokerSendAsync    = NULL;
static HeaderProviderSetOrUpdate_t s_origHeaderProviderSetOrUpdate  = NULL;

// ---------------------------------------------------------------------------
// Resolve the target userId for the pending device switch. Returns nil when
// no switch is armed, or when the pending deviceId is a fresh UUID (Register
// flow) that isn't in the saved-accounts catalog — in that case the server
// is expected to see the previous (empty) x-user-id.
// ---------------------------------------------------------------------------
static bool pendingDeviceIsSavedAccount(NSString *pending) {
    if (pending.length == 0) return false;
    for (NSDictionary *acc in KIOUListAccounts()) {
        id uuid = acc[@"uuid"];
        if ([uuid isKindOfClass:[NSString class]] &&
            [(NSString *)uuid isEqualToString:pending]) {
            return true;
        }
    }
    return false;
}

static NSString *targetUserIdForPendingDevice(void) {
    NSString *pending = KIOUPendingDeviceId();
    if (pending.length == 0) return nil;
    if (!pendingDeviceIsSavedAccount(pending)) return nil;
    return KIOUActiveAccountUserId();
}

// il2cpp string reader — mirrors readIl2CppStr in AccountObserve.m. Kept
// local to avoid pulling in an extra shared header for one caller; if a
// third consumer appears, promote this to a shared util.
static NSString *readIl2CppStrLocal(void *strObj) {
    if (!strObj) return nil;
    @try {
        int32_t len = readI32(strObj, 0x10);
        if (len <= 0 || len > 4096) return nil;
        const uint16_t *chars = (const uint16_t *)((uint8_t *)strObj + 0x14);
        return [NSString stringWithCharacters:chars length:(NSUInteger)len];
    } @catch (NSException *e) {
        (void)e; return nil;
    } @catch (id e) {
        (void)e; return nil;
    }
}

// ---------------------------------------------------------------------------
// Project.Network.HeaderProvider.SetOrUpdateHeader(string key, string value)
// Managed-only signature (self + 2 il2cpp strings + MethodInfo*) — no HTTP
// / Yaha types anywhere, so this hook cannot trip the SendAsync-borrow
// crash pattern.
//
// When key == "x-user-id" and an account switch is armed, we replace the
// value argument with a freshly-allocated il2cpp string carrying the
// target account's userId. Otherwise pass through untouched.
// ---------------------------------------------------------------------------
void KIOUHookHeaderProviderSetOrUpdate(void *self, void *keyStr, void *valueStr, void *mi) {
    NSString *key = readIl2CppStrLocal(keyStr);
    if ([key isEqualToString:@"x-user-id"]) {
        NSString *target = targetUserIdForPendingDevice();
        if (target.length > 0 && g_GrpcStringNew) {
            void *newValue = g_GrpcStringNew(target.UTF8String);
            if (newValue) {
                valueStr = newValue;
                IPALog([NSString stringWithFormat:
                          @"[HEADER] x-user-id swapped → %@", target]);
            }
        }
    }
    if (s_origHeaderProviderSetOrUpdate) {
        s_origHeaderProviderSetOrUpdate(self, keyStr, valueStr, mi);
    }
}

// ---------------------------------------------------------------------------
// HttpMessageInvoker.SendAsync — bare passthrough. See file header for why
// we don't touch request/self here.
// ---------------------------------------------------------------------------
void *KIOUHookHttpMsgInvokerSendAsync(void *self, void *request, void *ct, void *mi) {
    return s_origHttpMsgInvokerSendAsync
        ? s_origHttpMsgInvokerSendAsync(self, request, ct, mi)
        : NULL;
}

void KIOUInstallGrpcLoggingHook(uintptr_t unityBase) {
    (void)unityBase;
    if (!g_GrpcStringNew)
        g_GrpcStringNew =
            (GrpcIl2CppStringNew_t)dlsym(RTLD_DEFAULT, "il2cpp_string_new");

    s_origHttpMsgInvokerSendAsync = (GenericSendAsync_t)
        KIOUHookInstall(KIOU_HOOK_NAME_HTTPMSGINVOKER_SEND_ASYNC,
                         (void *)KIOUHookHttpMsgInvokerSendAsync, unityBase);

    s_origHeaderProviderSetOrUpdate = (HeaderProviderSetOrUpdate_t)
        KIOUHookInstall(KIOU_HOOK_NAME_HEADER_PROVIDER_SET_OR_UPDATE_HEADER,
                         (void *)KIOUHookHeaderProviderSetOrUpdate, unityBase);

    IPALog([NSString stringWithFormat:
              @"[GRPC] hook resolved: origSendAsync=%p origSetOrUpdate=%p strNew=%p",
              s_origHttpMsgInvokerSendAsync,
              s_origHeaderProviderSetOrUpdate,
              g_GrpcStringNew]);
}
