"""KIOU patch constants for app version 1.0.1 (CFBundleVersion 11).

RVAs verified against assets/1.0.1/dump.cs.index.json on 2026-06-15.
Note: account switching / gRPC header swap are not supported on 1.0.1.

KiouEditor's 18 CAVE_ENTRY sites (slot indices 10..27 in the unified
KIOU-Hook entry slot table) are appended below. AFK suppression on
1.0.1 also moves to a CAVE_ENTRY here (GAME_ORCHESTRATOR_IS_AFK), so
``AFK_SITE`` / ``AFK_ORIG_8`` are left as no-op stubs — the consumer
tweak owns the AFK behaviour through its hook body.
"""

from recipes.common import CAVE_ENTRY, CAVE_OBSERVER

BUILD = 11

CAVE_REGION         = (0x8268024, 0x826C000)
HOOK_SLOT_RVA       = 0x8F90C80
PROBED_HOOK_SLOT_RVA = HOOK_SLOT_RVA

INJECT_ENTRY_TABLE_RVA        = 0x8F90C00
PROBED_INJECT_ENTRY_TABLE_RVA = 0x8F90C00
ENTRY_SLOT_BASE_RVA           = 0x091E91B8
ZERO_REGION_END_RVA           = 0x091F5978

# AFK is now a CAVE_ENTRY hook owned by the consumer (KiouEditor's
# Hook_AfkDisable). Inline patch is disabled for 1.0.1 — keep the
# constants as None/"" so the recipes/__init__ loader stays compatible.
AFK_SITE   = None
AFK_ORIG_8 = ""

# fmt: off
SITES = [
    # --- Entry caves (CAVE_ENTRY) ---
    (0x6B6B758, "f44fbea9", "KIOU_HOOK_ID_SET_TARGET_FRAMERATE",     CAVE_ENTRY, "Application.set_targetFrameRate"),
    (0x5D320E0, "ff0301d1", "KIOU_HOOK_ID_NSS_SETHASHSIZE",          CAVE_ENTRY, "NativeSyncSession.SetHashSize"),
    (0x5D3206C, "ff0301d1", "KIOU_HOOK_ID_NSS_SETSKILLEVEL",         CAVE_ENTRY, "NativeSyncSession.SetSkillLevel"),
    (0x5D32178, "ffc305d1", "KIOU_HOOK_ID_NSS_SEARCHFULL",           CAVE_ENTRY, "NativeSyncSession.SearchFull"),

    # --- Observer caves (CAVE_OBSERVER): IMatchMode.OnMatchEndAsync × 5 ---
    (0x59E5958, "f657bda9", "KIOU_HOOK_ID_KIFU_AI_END",        CAVE_OBSERVER, "AIMatchMode.OnMatchEndAsync"),
    (0x59EC818, "ff8301d1", "KIOU_HOOK_ID_KIFU_CPUSTREAM_END", CAVE_OBSERVER, "CPUStreamMode.OnMatchEndAsync"),
    (0x59FF8F8, "f44fbea9", "KIOU_HOOK_ID_KIFU_LOCAL_END",     CAVE_OBSERVER, "LocalPvPMode.OnMatchEndAsync"),
    (0x5A0139C, "ff8301d1", "KIOU_HOOK_ID_KIFU_ONLINE_END",    CAVE_OBSERVER, "OnlinePvPMode.OnMatchEndAsync"),
    (0x5A2B564, "f85fbca9", "KIOU_HOOK_ID_KIFU_REPLAY_END",    CAVE_OBSERVER, "RecordReplayMode.OnMatchEndAsync"),

    # --- KiouEditor entry caves (CAVE_ENTRY) ---
    # Prologues captured from clean Kiou-1.0.1 build 11 UnityFramework
    # (2026-06-15). None are PC-relative; each first-4-bytes can be
    # relocated verbatim into the cave tail.
    (0x5C37034, "fc6fbaa9", "KIOU_HOOK_ID_SYNC_ITEM_LIST_MERGE",        CAVE_ENTRY, "SyncItemListReply.InternalMergeFrom"),
    (0x5C4065C, "fa67bba9", "KIOU_HOOK_ID_COLLECTION_PRESET_MERGE",     CAVE_ENTRY, "UpdateCollectionPresetReply.InternalMergeFrom"),
    (0x5CA7C90, "ffc302d1", "KIOU_HOOK_ID_SELECT_CHAR_ASYNC",           CAVE_ENTRY, "SelectCharacterAsync"),
    (0x5C26DCC, "fc6fbaa9", "KIOU_HOOK_ID_SELECT_CHAR_REPLY_MERGE",     CAVE_ENTRY, "SelectCharacterReply.InternalMergeFrom"),
    (0x5B4CAEC, "fc6fbaa9", "KIOU_HOOK_ID_MATCHING_PLAYER_MERGE",       CAVE_ENTRY, "ShogiMatchingPlayerStatus.InternalMergeFrom"),
    (0x5C01328, "fc6fbaa9", "KIOU_HOOK_ID_HISTORY_DETAIL_MERGE",        CAVE_ENTRY, "GetShogiHistoryDetailListReply.InternalMergeFrom"),
    (0x5C00D88, "00804039", "KIOU_HOOK_ID_HISTORY_GET_PREMIUM",         CAVE_ENTRY, "GetShogiHistoryDetailListReply.get_IsPremiumUser"),
    (0x585B25C, "00004139", "KIOU_HOOK_ID_KIFU_DETAIL_IS_PREMIUM",      CAVE_ENTRY, "KifuDetailModel.IsPremiumUser"),
    (0x582B88C, "e80300aa", "KIOU_HOOK_ID_VOICE_PLAYER_SATISFIES",      CAVE_ENTRY, "CharacterVoicePlayer.SatisfiesRule"),
    (0x584ADC0, "00704039", "KIOU_HOOK_ID_VOICE_CELL_GET_IS_LOCKED",    CAVE_ENTRY, "CharacterVoiceScrollerCellModel.get_IsLocked"),
    (0x597A448, "f85fbca9", "KIOU_HOOK_ID_BSE_CTOR",                    CAVE_ENTRY, "BeginnerSupportEvaluator.ctor"),
    (0x597BAFC, "f657bda9", "KIOU_HOOK_ID_BSE_ENSURE_INITIALIZED",      CAVE_ENTRY, "BeginnerSupportEvaluator.EnsureInitializedLocked"),
    (0x593E630, "00404039", "KIOU_HOOK_ID_RBSUPPORT_GET_ENABLED",       CAVE_ENTRY, "ResolvedBeginnerSupport.get_Enabled"),
    (0x593E650, "002040b9", "KIOU_HOOK_ID_RBSUPPORT_GET_DEPTH",         CAVE_ENTRY, "ResolvedBeginnerSupport.get_Depth"),
    (0x5A9F298, "fc6fbaa9", "KIOU_HOOK_ID_HOME_UTILITY_PRESENTER_CTOR", CAVE_ENTRY, "HomeUtilityPresenter.ctor"),
    (0x5DD1E08, "f44fbea9", "KIOU_HOOK_ID_UIBUTTONBASE_ONPOINTERCLICK", CAVE_ENTRY, "UIButtonBase.OnPointerClick"),
    (0x5DCC728, "ff0303d1", "KIOU_HOOK_ID_TITLE_SCENE_MOVENEXT",        CAVE_ENTRY, "TitleScene+<OnActivateAsync>d__10.MoveNext"),
    (0x59455D4, "f44fbea9", "KIOU_HOOK_ID_GAME_ORCHESTRATOR_IS_AFK",    CAVE_ENTRY, "GameOrchestrator.IsAfkEnabled"),
]
# fmt: on
