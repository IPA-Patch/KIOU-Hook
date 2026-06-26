#import "KIOUHook.h"
#import "Account/Persistence.h"
#import "il2cpp.h"
#import "logging.h"
#import <dlfcn.h>

// ===========================================================================
// Hook/GrpcLogging.m — swap x-user-id gRPC header on account switch.
//
// KIOU's gRPC stack passes an x-user-id request header that identifies the
// logged-in user.  When KFSwitchAccount arms pending_device_id, LoginArgs
// sends a different deviceId to the server, but the header still names the
// previous user — the server rejects with -40004.
//
// Fix: hook HttpMessageInvoker.SendAsync (the virtual base that every gRPC
// call routes through). Rewrite the header to match the target account
// before calling orig.
//
// Hook site (resolved by name at install time):
//   HttpMessageInvoker.SendAsync
//
// Helper RVAs (assumed stable enough to stay local for now — promote to
// catalog if a second consumer needs them):
// ===========================================================================

#define RVA_HTTPHEADERS_TRYADD   0x608E9B8
#define RVA_HTTPHEADERS_REMOVE   0x608EE70

// HttpRequestMessage field offset (dump.cs line 1540968).
#define OFF_REQ_HEADERS  0x10

// ---------------------------------------------------------------------------
// Function pointer types
//
// IL2CPP instance methods are called with a trailing MethodInfo* in x3 (or
// the next available arg register).  Omitting it leaves x3 polluted, and
// orig crashes the moment it dereferences MethodInfo.  Keep these signatures
// in lockstep with AnalysisTune.m's `..., void *mi` convention.
// ---------------------------------------------------------------------------
typedef bool  (*HttpHeadersTryAdd_t)(void *headers, void *name, void *value, void *mi);
typedef bool  (*HttpHeadersRemove_t)(void *headers, void *name, void *mi);
typedef void *(*GrpcIl2CppStringNew_t)(const char *utf8);
typedef void *(*GenericSendAsync_t)(void *self, void *request, void *ct, void *mi);

static HttpHeadersTryAdd_t   g_HttpHeadersTryAdd   = NULL;
static HttpHeadersRemove_t   g_HttpHeadersRemove   = NULL;
static GrpcIl2CppStringNew_t g_GrpcStringNew       = NULL;
static GenericSendAsync_t    s_origHttpMsgInvokerSendAsync = NULL;

// ---------------------------------------------------------------------------
// Resolve the target userId for the pending device switch.
// Returns nil if no switch is armed.
//
// We trust active_user_id (set by Settings UI when the user picks an
// account) rather than reverse-mapping deviceId -> userId via the saved
// accounts list — the latter falls over when the same uuid is shared by
// multiple userIds.
// ---------------------------------------------------------------------------
static NSString *targetUserIdForPendingDevice(void) {
    if (KFPendingDeviceId().length == 0) return nil;
    return KFActiveAccountUserId();
}

// ---------------------------------------------------------------------------
// Swap x-user-id header to the target account's userId.
// No-op when no switch is armed or helpers are not yet resolved.
// ---------------------------------------------------------------------------
static void swapUserIdHeader(void *request) {
    if (!request || !g_HttpHeadersTryAdd || !g_HttpHeadersRemove ||
        !g_GrpcStringNew) return;
    NSString *targetUserId = targetUserIdForPendingDevice();
    if (targetUserId.length == 0) return;
    void *headers = readPtr(request, OFF_REQ_HEADERS);
    if (!headers) return;
    void *nameStr  = g_GrpcStringNew("x-user-id");
    void *valueStr = g_GrpcStringNew(targetUserId.UTF8String);
    if (!nameStr || !valueStr) return;
    @try {
        g_HttpHeadersRemove(headers, nameStr, NULL);
        g_HttpHeadersTryAdd(headers, nameStr, valueStr, NULL);
        IPALog([NSString stringWithFormat:
                  @"[GRPC] x-user-id swapped → %@", targetUserId]);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:@"[GRPC] x-user-id swap threw: %@", e]);
    } @catch (id e) {
        IPALog([NSString stringWithFormat:
                  @"[GRPC] x-user-id swap threw (non-NSException): %@", e]);
    }
}

// IL2CPP calls this with (self, request, ct, MethodInfo*) — the trailing mi
// must be forwarded to orig or orig will dereference garbage in x3.  The
// outer @try/@catch guarantees orig SendAsync is always invoked, even when
// the header swap blows up, so login can proceed (with the stale x-user-id)
// instead of the whole process aborting.
void *KFHookHttpMsgInvokerSendAsync(void *self, void *request, void *ct, void *mi) {
    @try {
        swapUserIdHeader(request);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                  @"[GRPC] swapUserIdHeader escaped (NSException): %@", e]);
    } @catch (id e) {
        IPALog([NSString stringWithFormat:
                  @"[GRPC] swapUserIdHeader escaped (id): %@", e]);
    }
    return s_origHttpMsgInvokerSendAsync
        ? s_origHttpMsgInvokerSendAsync(self, request, ct, mi)
        : NULL;
}

void KFInstallGrpcLoggingHook(uintptr_t unityBase) {
    g_HttpHeadersTryAdd =
        (HttpHeadersTryAdd_t)(unityBase + RVA_HTTPHEADERS_TRYADD);
    g_HttpHeadersRemove =
        (HttpHeadersRemove_t)(unityBase + RVA_HTTPHEADERS_REMOVE);
    if (!g_GrpcStringNew)
        g_GrpcStringNew =
            (GrpcIl2CppStringNew_t)dlsym(RTLD_DEFAULT, "il2cpp_string_new");

    s_origHttpMsgInvokerSendAsync = (GenericSendAsync_t)
        KIOUHookInstall(KIOU_HOOK_NAME_HTTPMSGINVOKER_SEND_ASYNC,
                         (void *)KFHookHttpMsgInvokerSendAsync, unityBase);

    IPALog([NSString stringWithFormat:
              @"[GRPC] hook resolved: orig=%p tryAdd=%p remove=%p strNew=%p",
              s_origHttpMsgInvokerSendAsync, g_HttpHeadersTryAdd,
              g_HttpHeadersRemove, g_GrpcStringNew]);
}
