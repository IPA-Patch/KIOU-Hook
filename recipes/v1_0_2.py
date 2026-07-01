"""KIOU patch constants for app version 1.0.2 (CFBundleVersion 12).

RVAs verified against assets/1.0.2/dump.cs.index.json on 2026-06-24.
"""

from recipes.common import CAVE_ENTRY, CAVE_OBSERVER

BUILD = 12

# Cave payload region (zero-fill tail of UnityFramework __TEXT).
CAVE_REGION         = (0x826F5E8, 0x8274000)

# Observer dispatcher slot — chinlan caves load this single 8-byte pointer.
# Sits just past the entry-slot table inside __DATA.__common. The old
# 0x8F90C80 landed in __DATA.__bss, which il2cpp/UnityRuntime overwrites
# during lazy init (verified crash: cave BLR X16 jumped to garbage after
# publish). __common survives publish — entry slots (0x091E91B8..) do.
HOOK_SLOT_RVA       = 0x091E92B8
PROBED_HOOK_SLOT_RVA = HOOK_SLOT_RVA

# Entry-cave slot table — ENTRY_SLOT_BASE_RVA + idx*8 holds each hook fn ptr.
INJECT_ENTRY_TABLE_RVA        = 0x8F90C00
PROBED_INJECT_ENTRY_TABLE_RVA = 0x8F90C00
ENTRY_SLOT_BASE_RVA           = 0x091E91B8
ZERO_REGION_END_RVA           = 0x091F5978

# GameOrchestrator.IsAfkEnabled is now handled via CAVE_ENTRY (see SITES
# below). The inline patch is retired so both 1.0.1 and 1.0.2 route AFK
# through the same hook-body path. Consumers that want the historic
# "always disabled" behaviour without wiring KIOUEditorFeatureEnabled
# can call KIOUAfkDisableAlwaysFalseInstall(unityBase) — see KIOUHook.h.
AFK_SITE   = None
AFK_ORIG_8 = ""

# fmt: off
SITES = [
    # --- Entry caves (CAVE_ENTRY) ---
    (0x6B718A4, "f44fbea9", "KIOU_HOOK_ID_SET_TARGET_FRAMERATE",      CAVE_ENTRY, "Application.set_targetFrameRate"),
    (0x5D379DC, "ff0301d1", "KIOU_HOOK_ID_NSS_SETHASHSIZE",           CAVE_ENTRY, "NativeSyncSession.SetHashSize"),
    (0x5D37968, "ff0301d1", "KIOU_HOOK_ID_NSS_SETSKILLEVEL",          CAVE_ENTRY, "NativeSyncSession.SetSkillLevel"),
    (0x5D37A74, "ffc305d1", "KIOU_HOOK_ID_NSS_SEARCHFULL",            CAVE_ENTRY, "NativeSyncSession.SearchFull"),
    (0x5922CD0, "fd7bbfa9", "KIOU_HOOK_ID_ACCOUNT_EXISTS",            CAVE_ENTRY, "UserSaveDataExtensions.AccountExists"),
    (0x5B9DC04, "f657bda9", "KIOU_HOOK_ID_LOGIN_ARGS_CREATE",         CAVE_ENTRY, "ILoginArgs.Create"),
    (0x5B9DC94, "f657bda9", "KIOU_HOOK_ID_REGISTER_USER_ARGS_CREATE", CAVE_ENTRY, "IRegisterUserArgs.Create"),
    (0x58152BC, "ff8302d1", "KIOU_HOOK_ID_RUN_LOGIN_SEQ_MOVENEXT",    CAVE_ENTRY, "AuthServiceExtensions+<RunLoginSequenceAsync>d__1.MoveNext"),
    (0x5BB99DC, "ff4302d1", "KIOU_HOOK_ID_GET_SELF_PROFILE_MOVENEXT", CAVE_ENTRY, "GameService+<GetSelfUserProfileAsync>d__36.MoveNext"),
    (0x6082AC0, "000840f9", "KIOU_HOOK_ID_HTTPMSGINVOKER_SEND_ASYNC", CAVE_ENTRY, "HttpMessageInvoker.SendAsync"),

    # --- Observer caves (CAVE_OBSERVER): IMatchMode.OnMatchEndAsync x 5 ---
    (0x59EA720, "f657bda9", "KIOU_HOOK_ID_KIFU_AI_END",        CAVE_OBSERVER, "AIMatchMode.OnMatchEndAsync"),
    (0x59F15D4, "ff8301d1", "KIOU_HOOK_ID_KIFU_CPUSTREAM_END", CAVE_OBSERVER, "CPUStreamMode.OnMatchEndAsync"),
    (0x5A046B4, "f44fbea9", "KIOU_HOOK_ID_KIFU_LOCAL_END",     CAVE_OBSERVER, "LocalPvPMode.OnMatchEndAsync"),
    (0x5A06158, "ff8301d1", "KIOU_HOOK_ID_KIFU_ONLINE_END",    CAVE_OBSERVER, "OnlinePvPMode.OnMatchEndAsync"),
    (0x5A30320, "f85fbca9", "KIOU_HOOK_ID_KIFU_REPLAY_END",    CAVE_OBSERVER, "RecordReplayMode.OnMatchEndAsync"),

    # --- Entry cave (CAVE_ENTRY): HeaderProvider.SetOrUpdateHeader ---
    # Upstream site for x-user-id swap on account switch. Avoids the
    # HttpMessageInvoker.SendAsync / Yaha borrow path that crashes when
    # the request or HttpHeaders internal dictionary is touched.
    (0x5BD9EE8, "f657bda9", "KIOU_HOOK_ID_HEADER_PROVIDER_SET_OR_UPDATE_HEADER", CAVE_ENTRY, "Project.Network.HeaderProvider.SetOrUpdateHeader"),

    # --- KiouEditor entry caves (CAVE_ENTRY, 1.0.2 port of the 1.0.1 sites) ---
    # RVAs verified against assets/1.0.2/dump.cs on 2026-07-01. Prologues
    # captured from assets/1.0.2/Kiou-1.0.2.ipa UnityFramework. None are
    # PC-relative; each first-4-bytes can be relocated verbatim into the
    # cave tail.
    (0x5C3C29C, "fc6fbaa9", "KIOU_HOOK_ID_SYNC_ITEM_LIST_MERGE",        CAVE_ENTRY, "SyncItemListReply.InternalMergeFrom"),
    (0x5C458C4, "fa67bba9", "KIOU_HOOK_ID_COLLECTION_PRESET_MERGE",     CAVE_ENTRY, "UpdateCollectionPresetReply.InternalMergeFrom"),
    (0x5CACEF8, "ffc302d1", "KIOU_HOOK_ID_SELECT_CHAR_ASYNC",           CAVE_ENTRY, "SelectCharacterAsync"),
    (0x5C2C034, "fc6fbaa9", "KIOU_HOOK_ID_SELECT_CHAR_REPLY_MERGE",     CAVE_ENTRY, "SelectCharacterReply.InternalMergeFrom"),
    (0x5B51C3C, "fc6fbaa9", "KIOU_HOOK_ID_MATCHING_PLAYER_MERGE",       CAVE_ENTRY, "ShogiMatchingPlayerStatus.InternalMergeFrom"),
    (0x5C06590, "fc6fbaa9", "KIOU_HOOK_ID_HISTORY_DETAIL_MERGE",        CAVE_ENTRY, "GetShogiHistoryDetailListReply.InternalMergeFrom"),
    (0x5C05FF0, "00804039", "KIOU_HOOK_ID_HISTORY_GET_PREMIUM",         CAVE_ENTRY, "GetShogiHistoryDetailListReply.get_IsPremiumUser"),
    (0x585E000, "00004139", "KIOU_HOOK_ID_KIFU_DETAIL_IS_PREMIUM",      CAVE_ENTRY, "KifuDetailModel.IsPremiumUser"),
    (0x582E614, "e80300aa", "KIOU_HOOK_ID_VOICE_PLAYER_SATISFIES",      CAVE_ENTRY, "CharacterVoicePlayer.SatisfiesRule"),
    (0x584DB64, "00704039", "KIOU_HOOK_ID_VOICE_CELL_GET_IS_LOCKED",    CAVE_ENTRY, "CharacterVoiceScrollerCellModel.get_IsLocked"),
    (0x597E608, "f85fbca9", "KIOU_HOOK_ID_BSE_CTOR",                    CAVE_ENTRY, "BeginnerSupportEvaluator.ctor"),
    (0x5980890, "f657bda9", "KIOU_HOOK_ID_BSE_ENSURE_INITIALIZED",      CAVE_ENTRY, "BeginnerSupportEvaluator.EnsureInitializedLocked"),
    (0x5942AA0, "00404039", "KIOU_HOOK_ID_RBSUPPORT_GET_ENABLED",       CAVE_ENTRY, "ResolvedBeginnerSupport.get_Enabled"),
    (0x5942AC0, "002040b9", "KIOU_HOOK_ID_RBSUPPORT_GET_DEPTH",         CAVE_ENTRY, "ResolvedBeginnerSupport.get_Depth"),
    (0x5AA4054, "fc6fbaa9", "KIOU_HOOK_ID_HOME_UTILITY_PRESENTER_CTOR", CAVE_ENTRY, "HomeUtilityPresenter.ctor"),
    (0x5DD7F54, "f44fbea9", "KIOU_HOOK_ID_UIBUTTONBASE_ONPOINTERCLICK", CAVE_ENTRY, "UIButtonBase.OnPointerClick"),
    (0x5DD2874, "ff0303d1", "KIOU_HOOK_ID_TITLE_SCENE_MOVENEXT",        CAVE_ENTRY, "TitleScene+<OnActivateAsync>d__10.MoveNext"),
    (0x594A034, "f44fbea9", "KIOU_HOOK_ID_GAME_ORCHESTRATOR_IS_AFK",    CAVE_ENTRY, "GameOrchestrator.IsAfkEnabled"),
]
# fmt: on
