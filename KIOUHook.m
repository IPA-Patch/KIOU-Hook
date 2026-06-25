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
// KiouEditor hook sites (1.0.1).
const char KIOU_HOOK_NAME_SYNC_ITEM_LIST_MERGE[]         = "sync_item_list_merge";
const char KIOU_HOOK_NAME_COLLECTION_PRESET_MERGE[]      = "collection_preset_merge";
const char KIOU_HOOK_NAME_SELECT_CHAR_ASYNC[]            = "select_character_async";
const char KIOU_HOOK_NAME_SELECT_CHAR_REPLY_MERGE[]      = "select_character_reply_merge";
const char KIOU_HOOK_NAME_MATCHING_PLAYER_MERGE[]        = "matching_player_merge";
const char KIOU_HOOK_NAME_HISTORY_DETAIL_MERGE[]         = "history_detail_merge";
const char KIOU_HOOK_NAME_HISTORY_GET_PREMIUM[]          = "history_get_premium";
const char KIOU_HOOK_NAME_KIFU_DETAIL_IS_PREMIUM[]       = "kifu_detail_is_premium";
const char KIOU_HOOK_NAME_VOICE_PLAYER_SATISFIES[]       = "voice_player_satisfies";
const char KIOU_HOOK_NAME_VOICE_CELL_GET_IS_LOCKED[]     = "voice_cell_get_is_locked";
const char KIOU_HOOK_NAME_BSE_CTOR[]                     = "bse_ctor";
const char KIOU_HOOK_NAME_BSE_ENSURE_INITIALIZED[]       = "bse_ensure_initialized";
const char KIOU_HOOK_NAME_RBSUPPORT_GET_ENABLED[]        = "rbsupport_get_enabled";
const char KIOU_HOOK_NAME_RBSUPPORT_GET_DEPTH[]          = "rbsupport_get_depth";
const char KIOU_HOOK_NAME_HOME_UTILITY_PRESENTER_CTOR[]  = "home_utility_presenter_ctor";
const char KIOU_HOOK_NAME_UIBUTTONBASE_ONPOINTERCLICK[]  = "uibuttonbase_on_pointer_click";
const char KIOU_HOOK_NAME_TITLE_SCENE_MOVENEXT[]         = "title_scene_movenext";
const char KIOU_HOOK_NAME_GAME_ORCHESTRATOR_IS_AFK[]     = "game_orchestrator_is_afk";
// Direct-ABI helpers (KiouEditor, 1.0.1). hook_id = -1 in the catalog.
const char KIOU_HOOK_NAME_NSS_SETHASHSIZE_DIRECT[]       = "nss_set_hash_size_direct";
const char KIOU_HOOK_NAME_GAMEOBJECT_GETCOMPONENT[]      = "game_object_get_component";
const char KIOU_HOOK_NAME_RTU_WORLDTOSCREENPOINT[]       = "rectxform_world_to_screen_point";

// hook_id < 0 → not an entry hook (no g_inject_entry slot, e.g. observer
// caves or a site that's only invoked directly via KIOUHookSiteAddr).
typedef struct {
    const char *name;
    int         hook_id;
    uintptr_t   site_rva;
} KIOUHookEntry;

static const KIOUHookEntry kCatalog[] = {
    { KIOU_HOOK_NAME_SET_TARGET_FRAMERATE,      KIOU_HOOK_ID_SET_TARGET_FRAMERATE,      KIOU_HOOK_RVA_SET_TARGET_FRAMERATE      },
    { KIOU_HOOK_NAME_NSS_SETHASHSIZE,           KIOU_HOOK_ID_NSS_SETHASHSIZE,           KIOU_HOOK_RVA_NSS_SETHASHSIZE           },
    { KIOU_HOOK_NAME_NSS_SETSKILLEVEL,          KIOU_HOOK_ID_NSS_SETSKILLEVEL,          KIOU_HOOK_RVA_NSS_SETSKILLEVEL          },
    { KIOU_HOOK_NAME_NSS_SEARCHFULL,            KIOU_HOOK_ID_NSS_SEARCHFULL,            KIOU_HOOK_RVA_NSS_SEARCHFULL            },
    { KIOU_HOOK_NAME_ACCOUNT_EXISTS,            KIOU_HOOK_ID_ACCOUNT_EXISTS,            KIOU_HOOK_RVA_ACCOUNT_EXISTS            },
    { KIOU_HOOK_NAME_LOGIN_ARGS_CREATE,         KIOU_HOOK_ID_LOGIN_ARGS_CREATE,         KIOU_HOOK_RVA_LOGIN_ARGS_CREATE         },
    { KIOU_HOOK_NAME_REGISTER_USER_ARGS_CREATE, KIOU_HOOK_ID_REGISTER_USER_ARGS_CREATE, KIOU_HOOK_RVA_REGISTER_USER_ARGS_CREATE },
    { KIOU_HOOK_NAME_RUN_LOGIN_SEQ_MOVENEXT,    KIOU_HOOK_ID_RUN_LOGIN_SEQ_MOVENEXT,    KIOU_HOOK_RVA_RUN_LOGIN_SEQ_MOVENEXT    },
    { KIOU_HOOK_NAME_GET_SELF_PROFILE_MOVENEXT, KIOU_HOOK_ID_GET_SELF_PROFILE_MOVENEXT, KIOU_HOOK_RVA_GET_SELF_PROFILE_MOVENEXT },
    { KIOU_HOOK_NAME_HTTPMSGINVOKER_SEND_ASYNC, KIOU_HOOK_ID_HTTPMSGINVOKER_SEND_ASYNC, KIOU_HOOK_RVA_HTTPMSGINVOKER_SEND_ASYNC },
    { KIOU_HOOK_NAME_AI_END,                    KIOU_HOOK_ID_KIFU_AI_END,               KIOU_HOOK_RVA_AI_END                    },
    { KIOU_HOOK_NAME_CPUSTREAM_END,             KIOU_HOOK_ID_KIFU_CPUSTREAM_END,        KIOU_HOOK_RVA_CPUSTREAM_END             },
    { KIOU_HOOK_NAME_LOCAL_END,                 KIOU_HOOK_ID_KIFU_LOCAL_END,            KIOU_HOOK_RVA_LOCAL_END                 },
    { KIOU_HOOK_NAME_ONLINE_END,                KIOU_HOOK_ID_KIFU_ONLINE_END,           KIOU_HOOK_RVA_ONLINE_END                },
    { KIOU_HOOK_NAME_REPLAY_END,                KIOU_HOOK_ID_KIFU_REPLAY_END,           KIOU_HOOK_RVA_REPLAY_END                },
    // KiouEditor sites (1.0.1, CAVE_ENTRY):
    { KIOU_HOOK_NAME_SYNC_ITEM_LIST_MERGE,        KIOU_HOOK_ID_SYNC_ITEM_LIST_MERGE,        KIOU_HOOK_RVA_SYNC_ITEM_LIST_MERGE        },
    { KIOU_HOOK_NAME_COLLECTION_PRESET_MERGE,     KIOU_HOOK_ID_COLLECTION_PRESET_MERGE,     KIOU_HOOK_RVA_COLLECTION_PRESET_MERGE     },
    { KIOU_HOOK_NAME_SELECT_CHAR_ASYNC,           KIOU_HOOK_ID_SELECT_CHAR_ASYNC,           KIOU_HOOK_RVA_SELECT_CHAR_ASYNC           },
    { KIOU_HOOK_NAME_SELECT_CHAR_REPLY_MERGE,     KIOU_HOOK_ID_SELECT_CHAR_REPLY_MERGE,     KIOU_HOOK_RVA_SELECT_CHAR_REPLY_MERGE     },
    { KIOU_HOOK_NAME_MATCHING_PLAYER_MERGE,       KIOU_HOOK_ID_MATCHING_PLAYER_MERGE,       KIOU_HOOK_RVA_MATCHING_PLAYER_MERGE       },
    { KIOU_HOOK_NAME_HISTORY_DETAIL_MERGE,        KIOU_HOOK_ID_HISTORY_DETAIL_MERGE,        KIOU_HOOK_RVA_HISTORY_DETAIL_MERGE        },
    { KIOU_HOOK_NAME_HISTORY_GET_PREMIUM,         KIOU_HOOK_ID_HISTORY_GET_PREMIUM,         KIOU_HOOK_RVA_HISTORY_GET_PREMIUM         },
    { KIOU_HOOK_NAME_KIFU_DETAIL_IS_PREMIUM,      KIOU_HOOK_ID_KIFU_DETAIL_IS_PREMIUM,      KIOU_HOOK_RVA_KIFU_DETAIL_IS_PREMIUM      },
    { KIOU_HOOK_NAME_VOICE_PLAYER_SATISFIES,      KIOU_HOOK_ID_VOICE_PLAYER_SATISFIES,      KIOU_HOOK_RVA_VOICE_PLAYER_SATISFIES      },
    { KIOU_HOOK_NAME_VOICE_CELL_GET_IS_LOCKED,    KIOU_HOOK_ID_VOICE_CELL_GET_IS_LOCKED,    KIOU_HOOK_RVA_VOICE_CELL_GET_IS_LOCKED    },
    { KIOU_HOOK_NAME_BSE_CTOR,                    KIOU_HOOK_ID_BSE_CTOR,                    KIOU_HOOK_RVA_BSE_CTOR                    },
    { KIOU_HOOK_NAME_BSE_ENSURE_INITIALIZED,      KIOU_HOOK_ID_BSE_ENSURE_INITIALIZED,      KIOU_HOOK_RVA_BSE_ENSURE_INITIALIZED      },
    { KIOU_HOOK_NAME_RBSUPPORT_GET_ENABLED,       KIOU_HOOK_ID_RBSUPPORT_GET_ENABLED,       KIOU_HOOK_RVA_RBSUPPORT_GET_ENABLED       },
    { KIOU_HOOK_NAME_RBSUPPORT_GET_DEPTH,         KIOU_HOOK_ID_RBSUPPORT_GET_DEPTH,         KIOU_HOOK_RVA_RBSUPPORT_GET_DEPTH         },
    { KIOU_HOOK_NAME_HOME_UTILITY_PRESENTER_CTOR, KIOU_HOOK_ID_HOME_UTILITY_PRESENTER_CTOR, KIOU_HOOK_RVA_HOME_UTILITY_PRESENTER_CTOR },
    { KIOU_HOOK_NAME_UIBUTTONBASE_ONPOINTERCLICK, KIOU_HOOK_ID_UIBUTTONBASE_ONPOINTERCLICK, KIOU_HOOK_RVA_UIBUTTONBASE_ONPOINTERCLICK },
    { KIOU_HOOK_NAME_TITLE_SCENE_MOVENEXT,        KIOU_HOOK_ID_TITLE_SCENE_MOVENEXT,        KIOU_HOOK_RVA_TITLE_SCENE_MOVENEXT        },
    { KIOU_HOOK_NAME_GAME_ORCHESTRATOR_IS_AFK,    KIOU_HOOK_ID_GAME_ORCHESTRATOR_IS_AFK,    KIOU_HOOK_RVA_GAME_ORCHESTRATOR_IS_AFK    },
    // Direct-call sites (no chinlan cave / no hook id):
    { KIOU_HOOK_NAME_BACK_TO_TITLE_RUN_ASYNC,     -1,                                       KIOU_HOOK_RVA_BACK_TO_TITLE_RUN_ASYNC     },
    { KIOU_HOOK_NAME_NSS_SETHASHSIZE_DIRECT,      -1,                                       KIOU_HOOK_RVA_NSS_SETHASHSIZE_DIRECT      },
    { KIOU_HOOK_NAME_GAMEOBJECT_GETCOMPONENT,     -1,                                       KIOU_HOOK_RVA_GAMEOBJECT_GETCOMPONENT     },
    { KIOU_HOOK_NAME_RTU_WORLDTOSCREENPOINT,      -1,                                       KIOU_HOOK_RVA_RTU_WORLDTOSCREENPOINT      },
    { NULL,                                        0,                                       0                                            },
};

static const KIOUHookEntry *findEntry(const char *name) {
    if (!name) return NULL;
    for (const KIOUHookEntry *e = kCatalog; e->name; e++) {
        if (e->name == name || strcmp(e->name, name) == 0) return e;
    }
    return NULL;
}

// On JB, store orig pointers indexed by hook_id so KIOUHookOrig can return
// them. Sized to KIOU_HOOK_ID__COUNT; only the slots that get installed are
// non-NULL.
#if !IPA_CHINLAN
static void *s_jbOrig[KIOU_HOOK_ID__COUNT] = {0};
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
