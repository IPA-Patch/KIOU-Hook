"""KIOU patch constants for app version 1.0.2 (CFBundleVersion 12).

RVAs verified against assets/1.0.2/dump.cs.index.json on 2026-06-24.
"""

from recipes.common import CAVE_ENTRY, CAVE_OBSERVER

BUILD = 12

# Cave payload region (zero-fill tail of UnityFramework __TEXT).
CAVE_REGION         = (0x826F5E8, 0x8274000)

# Observer dispatcher slot — chinlan caves load this single 8-byte pointer.
HOOK_SLOT_RVA       = 0x8F90C80
PROBED_HOOK_SLOT_RVA = HOOK_SLOT_RVA

# Entry-cave slot table — ENTRY_SLOT_BASE_RVA + idx*8 holds each hook fn ptr.
INJECT_ENTRY_TABLE_RVA        = 0x8F90C00
PROBED_INJECT_ENTRY_TABLE_RVA = 0x8F90C00
ENTRY_SLOT_BASE_RVA           = 0x091E91B8
ZERO_REGION_END_RVA           = 0x091F5978

# GameOrchestrator.IsAfkEnabled — inline-patched to return false.
AFK_SITE   = 0x594A034
AFK_ORIG_8 = "f44fbea9fd7b01a9"

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
]
# fmt: on
