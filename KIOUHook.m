#import "KIOUHook.h"
#import <string.h>

// ===========================================================================
// KIOUHook.m — name → (hook_id, site_rva) catalog and installer helpers.
//
// The lookup table here is the only place in KIOU-Hook where symbolic hook
// names are mapped to the catalog enum / RVA macros. Hook authors call the
// name-based API; everything below this line keeps the per-binary catalog
// concerns out of the hook bodies.
//
// On JB, KIOUHookInstall maintains a tiny static array of `orig` pointers
// keyed by hook_id so KIOUHookOrig can return them after install.
// ===========================================================================

// Hook name string definitions — storage for the externs in KIOUHook.h.
const char KIOU_HOOK_NAME_SET_TARGET_FRAMERATE[]      = "set_target_framerate";
const char KIOU_HOOK_NAME_NSS_SETHASHSIZE[]           = "nss_set_hash_size";
const char KIOU_HOOK_NAME_NSS_SETSKILLEVEL[]          = "nss_set_skill_level";
const char KIOU_HOOK_NAME_NSS_SEARCHFULL[]            = "nss_search_full";
const char KIOU_HOOK_NAME_ACCOUNT_EXISTS[]            = "account_exists";
const char KIOU_HOOK_NAME_LOGIN_ARGS_CREATE[]         = "login_args_create";
const char KIOU_HOOK_NAME_REGISTER_USER_ARGS_CREATE[] = "register_user_args_create";
const char KIOU_HOOK_NAME_RUN_LOGIN_SEQ_MOVENEXT[]    = "run_login_seq_movenext";
const char KIOU_HOOK_NAME_GET_SELF_PROFILE_MOVENEXT[] = "get_self_profile_movenext";
const char KIOU_HOOK_NAME_HTTPMSGINVOKER_SEND_ASYNC[] = "httpmsginvoker_send_async";
const char KIOU_HOOK_NAME_AI_END[]                    = "ai_match_on_match_end";
const char KIOU_HOOK_NAME_CPUSTREAM_END[]             = "cpustream_on_match_end";
const char KIOU_HOOK_NAME_LOCAL_END[]                 = "local_pvp_on_match_end";
const char KIOU_HOOK_NAME_ONLINE_END[]                = "online_pvp_on_match_end";
const char KIOU_HOOK_NAME_REPLAY_END[]                = "record_replay_on_match_end";
const char KIOU_HOOK_NAME_BACK_TO_TITLE_RUN_ASYNC[]   = "back_to_title_run_async";

// hook_id < 0 → not an entry hook (no g_inject_entry slot, e.g. observer
// caves or a site that's only invoked directly via KIOUHookSiteAddr).
typedef struct {
    const char *name;
    int         hook_id;
    uintptr_t   site_rva;
} KIOUHookEntry;

static const KIOUHookEntry kCatalog[] = {
    { KIOU_HOOK_NAME_SET_TARGET_FRAMERATE,      KIOU_KF_HOOK_SET_TARGET_FRAMERATE,      KIOU_KF_SITE_RVA_SET_TARGET_FRAMERATE      },
    { KIOU_HOOK_NAME_NSS_SETHASHSIZE,           KIOU_KF_HOOK_NSS_SETHASHSIZE,           KIOU_KF_SITE_RVA_NSS_SETHASHSIZE           },
    { KIOU_HOOK_NAME_NSS_SETSKILLEVEL,          KIOU_KF_HOOK_NSS_SETSKILLEVEL,          KIOU_KF_SITE_RVA_NSS_SETSKILLEVEL          },
    { KIOU_HOOK_NAME_NSS_SEARCHFULL,            KIOU_KF_HOOK_NSS_SEARCHFULL,            KIOU_KF_SITE_RVA_NSS_SEARCHFULL            },
    { KIOU_HOOK_NAME_ACCOUNT_EXISTS,            KIOU_KF_HOOK_ACCOUNT_EXISTS,            KIOU_KF_SITE_RVA_ACCOUNT_EXISTS            },
    { KIOU_HOOK_NAME_LOGIN_ARGS_CREATE,         KIOU_KF_HOOK_LOGIN_ARGS_CREATE,         KIOU_KF_SITE_RVA_LOGIN_ARGS_CREATE         },
    { KIOU_HOOK_NAME_REGISTER_USER_ARGS_CREATE, KIOU_KF_HOOK_REGISTER_USER_ARGS_CREATE, KIOU_KF_SITE_RVA_REGISTER_USER_ARGS_CREATE },
    { KIOU_HOOK_NAME_RUN_LOGIN_SEQ_MOVENEXT,    KIOU_KF_HOOK_RUN_LOGIN_SEQ_MOVENEXT,    KIOU_KF_SITE_RVA_RUN_LOGIN_SEQ_MOVENEXT    },
    { KIOU_HOOK_NAME_GET_SELF_PROFILE_MOVENEXT, KIOU_KF_HOOK_GET_SELF_PROFILE_MOVENEXT, KIOU_KF_SITE_RVA_GET_SELF_PROFILE_MOVENEXT },
    { KIOU_HOOK_NAME_HTTPMSGINVOKER_SEND_ASYNC, KIOU_KF_HOOK_HTTPMSGINVOKER_SEND_ASYNC, KIOU_KF_SITE_RVA_HTTPMSGINVOKER_SEND_ASYNC },
    { KIOU_HOOK_NAME_AI_END,                    KIOU_KF_HOOK_KIFU_AI_END,               KIOU_KF_SITE_RVA_AI_END                    },
    { KIOU_HOOK_NAME_CPUSTREAM_END,             KIOU_KF_HOOK_KIFU_CPUSTREAM_END,        KIOU_KF_SITE_RVA_CPUSTREAM_END             },
    { KIOU_HOOK_NAME_LOCAL_END,                 KIOU_KF_HOOK_KIFU_LOCAL_END,            KIOU_KF_SITE_RVA_LOCAL_END                 },
    { KIOU_HOOK_NAME_ONLINE_END,                KIOU_KF_HOOK_KIFU_ONLINE_END,           KIOU_KF_SITE_RVA_ONLINE_END                },
    { KIOU_HOOK_NAME_REPLAY_END,                KIOU_KF_HOOK_KIFU_REPLAY_END,           KIOU_KF_SITE_RVA_REPLAY_END                },
    // Direct-call sites (no chinlan cave / no hook id):
    { KIOU_HOOK_NAME_BACK_TO_TITLE_RUN_ASYNC,   -1,                                     KIOU_KF_SITE_RVA_BACK_TO_TITLE_RUN_ASYNC   },
    { NULL,                                      0,                                     0                                          },
};

static const KIOUHookEntry *findEntry(const char *name) {
    if (!name) return NULL;
    for (const KIOUHookEntry *e = kCatalog; e->name; e++) {
        if (e->name == name || strcmp(e->name, name) == 0) return e;
    }
    return NULL;
}

// On JB, store orig pointers indexed by hook_id so KIOUHookOrig can return
// them. Sized to KIOU_KF_HOOK__COUNT; only the slots that get installed are
// non-NULL.
#if !IPA_CHINLAN
static void *s_jbOrig[KIOU_KF_HOOK__COUNT] = {0};
#endif

uintptr_t KIOUHookSiteAddr(const char *name, uintptr_t unityBase) {
    const KIOUHookEntry *e = findEntry(name);
    return e ? unityBase + e->site_rva : 0;
}

void *KIOUHookOrig(const char *name) {
    const KIOUHookEntry *e = findEntry(name);
    if (!e || e->hook_id < 0) return NULL;
#if IPA_CHINLAN
    return g_inject_entry[e->hook_id];
#else
    return s_jbOrig[e->hook_id];
#endif
}

void *KIOUHookInstall(const char *name, void *replacement, uintptr_t unityBase) {
    const KIOUHookEntry *e = findEntry(name);
    if (!e) return NULL;
#if IPA_CHINLAN
    // chinlan: caves are wired by ChinlanDispatcher's KFChinlanPublish.
    // The caller passes `replacement` for symmetry but we ignore it; we
    // just return the bypass entry so the caller can store it as their
    // orig pointer and call it from the hook body.
    (void)replacement;
    (void)unityBase;
    if (e->hook_id < 0) return NULL;
    return g_inject_entry[e->hook_id];
#else
    if (!replacement || e->hook_id < 0) return NULL;
    uintptr_t addr = unityBase + e->site_rva;
    void *orig = NULL;
    MSHookFunction((void *)addr, replacement, &orig);
    s_jbOrig[e->hook_id] = orig;
    return orig;
#endif
}
