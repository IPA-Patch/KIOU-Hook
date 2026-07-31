"""KIOU patch constants for app version 1.1.0 (CFBundleVersion 15).

Ported from v1_0_2.py with ``tools.port_recipe`` against
assets/1.1.0/dump.cs.index.json on 2026-07-31; every RVA and prologue
below was resolved by anchor name and read back from
assets/1.1.0/Kiou-1.1.0.ipa. __TEXT grew from 0x8274000 to 0x94BC000, so
no address carries over from 1.0.2.
"""

from recipes.common import CAVE_ENTRY, CAVE_OBSERVER

BUILD = 15

# Cave payload region (zero-fill tail of UnityFramework __TEXT).
# Same shape as 1.0.2: starts *after* __oslogstring
# (0x94B8000..0x94B8023) and runs to the end of __TEXT. Verified all-zero
# across its 0x3FDC B, which holds ~194 caves — comfortably more than the
# 56 SITES below. The __eh_frame..__oslogstring gap is only 0x1C50 B and
# is skipped for the same reason it was on 1.0.2.
CAVE_REGION         = (0x94B8024, 0x94BC000)

# Observer dispatcher slot — chinlan caves load this single 8-byte pointer.
# Placed at the same distance from the end of __DATA.__common as on 1.0.2
# (end - 0xC5C0), keeping it clear of __bss, which il2cpp/UnityRuntime
# overwrites during lazy init. __common ends at 0xA522A28 here.
HOOK_SLOT_RVA       = 0x0A516468
PROBED_HOOK_SLOT_RVA = HOOK_SLOT_RVA

# Entry-cave slot table — ENTRY_SLOT_BASE_RVA + idx*8 holds each hook fn ptr.
INJECT_ENTRY_TABLE_RVA        = 0xA2BDBF8
PROBED_INJECT_ENTRY_TABLE_RVA = 0xA2BDBF8
ENTRY_SLOT_BASE_RVA           = 0x0A516268
ZERO_REGION_END_RVA           = 0x0A522A28

# GameOrchestrator.IsAfkEnabled is handled via CAVE_ENTRY (see SITES
# below) on every supported version. Consumers that want the historic
# "always disabled" behaviour without wiring KIOUEditorFeatureEnabled
# can call KIOUInstallAfkSuppressHook(unityBase) — see KIOUHook.h.
AFK_SITE   = None
AFK_ORIG_8 = ""

# fmt: off
SITES = [
    # --- Entry caves (CAVE_ENTRY) ---
    (0x7A9A020, "f44fbea9", "KIOU_HOOK_ID_SET_TARGET_FRAMERATE",      CAVE_ENTRY, "Application.set_targetFrameRate"),
    (0x6C58720, "ff0301d1", "KIOU_HOOK_ID_NSS_SETHASHSIZE",           CAVE_ENTRY, "NativeSyncSession.SetHashSize"),
    (0x6C5B64C, "ff0301d1", "KIOU_HOOK_ID_NSS_SETSKILLEVEL",          CAVE_ENTRY, "NativeSyncSession.SetSkillLevel"),
    (0x6C5B6E4, "ffc305d1", "KIOU_HOOK_ID_NSS_SEARCHFULL",            CAVE_ENTRY, "NativeSyncSession.SearchFull"),
    (0x682FF8C, "fd7bbfa9", "KIOU_HOOK_ID_ACCOUNT_EXISTS",            CAVE_ENTRY, "UserSaveDataExtensions.AccountExists"),
    (0x6AB29B0, "f85fbca9", "KIOU_HOOK_ID_LOGIN_ARGS_CREATE",         CAVE_ENTRY, "ILoginArgs.Create"),
    (0x6AB2A5C, "f657bda9", "KIOU_HOOK_ID_REGISTER_USER_ARGS_CREATE", CAVE_ENTRY, "IRegisterUserArgs.Create"),
    (0x66CED7C, "ff8302d1", "KIOU_HOOK_ID_RUN_LOGIN_SEQ_MOVENEXT",    CAVE_ENTRY, "AuthServiceExtensions+<RunLoginSequenceAsync>d__1.MoveNext"),
    (0x6ACF014, "ff4302d1", "KIOU_HOOK_ID_GET_SELF_PROFILE_MOVENEXT", CAVE_ENTRY, "GameService+<GetSelfUserProfileAsync>d__38.MoveNext"),
    (0x6FA5DDC, "000840f9", "KIOU_HOOK_ID_HTTPMSGINVOKER_SEND_ASYNC", CAVE_ENTRY, "HttpMessageInvoker.SendAsync"),

    # --- Observer caves (CAVE_OBSERVER): IMatchMode.OnMatchEndAsync x 5 ---
    (0x68F4988, "f657bda9", "KIOU_HOOK_ID_KIFU_AI_END",        CAVE_OBSERVER, "AIMatchMode.OnMatchEndAsync"),
    (0x68FCD78, "ff8301d1", "KIOU_HOOK_ID_KIFU_CPUSTREAM_END", CAVE_OBSERVER, "CPUStreamMode.OnMatchEndAsync"),
    (0x69103D4, "f44fbea9", "KIOU_HOOK_ID_KIFU_LOCAL_END",     CAVE_OBSERVER, "LocalPvPMode.OnMatchEndAsync"),
    (0x6911E8C, "ff8301d1", "KIOU_HOOK_ID_KIFU_ONLINE_END",    CAVE_OBSERVER, "OnlinePvPMode.OnMatchEndAsync"),
    (0x693DE6C, "f85fbca9", "KIOU_HOOK_ID_KIFU_REPLAY_END",    CAVE_OBSERVER, "RecordReplayMode.OnMatchEndAsync"),

    # --- Entry cave (CAVE_ENTRY): HeaderProvider.SetOrUpdateHeader ---
    # Upstream site for x-user-id swap on account switch. Avoids the
    # HttpMessageInvoker.SendAsync / Yaha borrow path that crashes when
    # the request or HttpHeaders internal dictionary is touched.
    (0x6AEF65C, "f657bda9", "KIOU_HOOK_ID_HEADER_PROVIDER_SET_OR_UPDATE_HEADER", CAVE_ENTRY, "Project.Network.HeaderProvider.SetOrUpdateHeader(string, string)"),

    # --- KiouEditor entry caves (CAVE_ENTRY) ---
    (0x6B58E3C, "fc6fbaa9", "KIOU_HOOK_ID_SYNC_ITEM_LIST_MERGE",        CAVE_ENTRY, "SyncItemListReply.InternalMergeFrom"),
    (0x6B625EC, "fa67bba9", "KIOU_HOOK_ID_COLLECTION_PRESET_MERGE",     CAVE_ENTRY, "UpdateCollectionPresetReply.InternalMergeFrom"),
    (0x6BCBFA8, "ffc302d1", "KIOU_HOOK_ID_SELECT_CHAR_ASYNC",           CAVE_ENTRY, "SelectCharacterAsync"),
    (0x6B48BD4, "fc6fbaa9", "KIOU_HOOK_ID_SELECT_CHAR_REPLY_MERGE",     CAVE_ENTRY, "SelectCharacterReply.InternalMergeFrom"),
    (0x6A61C94, "fc6fbaa9", "KIOU_HOOK_ID_MATCHING_PLAYER_MERGE",       CAVE_ENTRY, "ShogiMatchingPlayerStatus.InternalMergeFrom"),
    (0x6B22EE0, "fc6fbaa9", "KIOU_HOOK_ID_HISTORY_DETAIL_MERGE",        CAVE_ENTRY, "GetShogiHistoryDetailListReply.InternalMergeFrom"),
    (0x6B22940, "00804039", "KIOU_HOOK_ID_HISTORY_GET_PREMIUM",         CAVE_ENTRY, "GetShogiHistoryDetailListReply.get_IsPremiumUser"),
    (0x6756674, "00004139", "KIOU_HOOK_ID_KIFU_DETAIL_IS_PREMIUM",      CAVE_ENTRY, "KifuDetailModel.IsPremiumUser"),
    (0x6722C4C, "e80300aa", "KIOU_HOOK_ID_VOICE_PLAYER_SATISFIES",      CAVE_ENTRY, "CharacterVoicePlayer.SatisfiesRule"),
    (0x6741F94, "00704039", "KIOU_HOOK_ID_VOICE_CELL_GET_IS_LOCKED",    CAVE_ENTRY, "CharacterVoiceScrollerCellModel.get_IsLocked"),
    (0x6888898, "f85fbca9", "KIOU_HOOK_ID_BSE_CTOR",                    CAVE_ENTRY, "BeginnerSupportEvaluator.ctor"),
    # 1.1.0 replaced the NNUE evaluator with a policy model:
    # EnsureInitializedLocked, TryBorrowSession and the NativeSyncSession
    # field are all gone, and with them the hash-size knob this cave
    # existed to apply. The row stays as a placeholder (site = None) so
    # every later hook keeps its cave index — see Hook/AssistTune.m.
    (None,      "f657bda9", "KIOU_HOOK_ID_BSE_ENSURE_INITIALIZED",      CAVE_ENTRY, "BeginnerSupportEvaluator.EnsureInitializedLocked"),
    (0x684C374, "00404039", "KIOU_HOOK_ID_RBSUPPORT_GET_ENABLED",       CAVE_ENTRY, "ResolvedBeginnerSupport.get_Enabled"),
    (0x684C394, "002040b9", "KIOU_HOOK_ID_RBSUPPORT_GET_DEPTH",         CAVE_ENTRY, "ResolvedBeginnerSupport.get_Depth"),
    (0x69A5A70, "fc6fbaa9", "KIOU_HOOK_ID_HOME_UTILITY_PRESENTER_CTOR", CAVE_ENTRY, "HomeUtilityPresenter.ctor"),
    (0x6CFB5C4, "f44fbea9", "KIOU_HOOK_ID_UIBUTTONBASE_ONPOINTERCLICK", CAVE_ENTRY, "UIButtonBase.OnPointerClick"),
    (0x6CF5EF4, "ff0303d1", "KIOU_HOOK_ID_TITLE_SCENE_MOVENEXT",        CAVE_ENTRY, "TitleScene+<OnActivateAsync>d__10.MoveNext"),
    (0x6854064, "f44fbea9", "KIOU_HOOK_ID_GAME_ORCHESTRATOR_IS_AFK",    CAVE_ENTRY, "GameOrchestrator.IsAfkEnabled"),
    (0x6888A9C, "ff4302d1", "KIOU_HOOK_ID_BSE_EVALUATE_ASYNC",          CAVE_ENTRY, "BeginnerSupportEvaluator.EvaluateAsync"),

    # --- KiouEditor 棋桜覚醒 (AI Special Support) UI-unlock caves. ------------
    # Server-side reject on the network still applies; this is UI unlock only.
    (0x6A650DC, "00204339", "KIOU_HOOK_ID_MOVE_RESULT_CAN_USE_SPECIAL",  CAVE_ENTRY, "ShogiMoveResultStatus.get_CanUseAiSpecialSupport"),
    (0x6A650AC, "00bc40b9", "KIOU_HOOK_ID_MOVE_RESULT_FREE_REMAINING",   CAVE_ENTRY, "ShogiMoveResultStatus.get_AiSpecialSupportRemainingFreeCount"),
    (0x6A650BC, "00c040b9", "KIOU_HOOK_ID_MOVE_RESULT_TICKET_REMAINING", CAVE_ENTRY, "ShogiMoveResultStatus.get_AiSpecialSupportRemainingTicketCount"),
    (0x6A60ECC, "006840b9", "KIOU_HOOK_ID_MP_FREE_REMAINING",            CAVE_ENTRY, "ShogiMatchingPlayerStatus.get_AiSpecialSupportFreeRemainingCount"),
    (0x6A60EDC, "006c40b9", "KIOU_HOOK_ID_MP_PAID_AVAILABLE",            CAVE_ENTRY, "ShogiMatchingPlayerStatus.get_AiSpecialSupportPaidAvailableCount"),

    # --- KiouEditor preferred-seat filter (ported from KiouEngineBridge). ----
    # Reject a MatchFound if it puts the user on the "wrong" seat, then
    # send ConnectionFailed to the matching server so it re-queues.
    (0x6C23BF0, "ff0301d1", "KIOU_HOOK_ID_MATCH_GET_VALID_FOUND",          CAVE_ENTRY, "MatchingHandler.GetValidMatchFoundStatus"),
    (0x6C2586C, "ff0303d1", "KIOU_HOOK_ID_MATCH_RECEIVE_TIMEOUT_MOVENEXT", CAVE_ENTRY, "MatchingHandler+<ReceiveWithTimeoutAsync>d__6.MoveNext"),
    (0x6AE500C, "fc6fbaa9", "KIOU_HOOK_ID_MATCH_STREAM_ARGS_CREATE",       CAVE_ENTRY, "IShogiMatchStreamArgs.Create"),
    # d__3 wraps the caller state around StartMatchingAsyncInternal — we
    # snapshot its <>8__1 (DisplayClass3_0) pointer so the seat-filter
    # reject branch can Cancel() its matchingCts and let the game's own
    # TryLeaveQueueAsync unwind the popup cleanly.
    (0x6C26EF0, "ffc305d1", "KIOU_HOOK_ID_MATCH_START_D3_MOVENEXT",        CAVE_ENTRY, "MatchingHandler+<StartMatchingAsync>d__3.MoveNext"),
    # ShogiMatchStreamHandler.SendAsync — every outgoing frame the game
    # writes to the matching stream (Heartbeat every 3 s, JoinQueue,
    # LeaveQueue, ConnectionFailed) flows through this call. We hook the
    # entry so we can (a) log every outbound frame and (b) capture the
    # MethodInfo argument (x2) into a global so the seat-filter reject
    # branch can call SendAsync directly with a valid MethodInfo instead
    # of NULL (which crashes the il2cpp method body).
    (0x6AE5820, "f657bda9", "KIOU_HOOK_ID_MATCH_STREAM_HANDLER_SEND_ASYNC", CAVE_ENTRY, "ShogiMatchStreamHandler.SendAsync"),

    # --- Universal gRPC wire logger (protobuf serialize/parse bottlenecks) ---
    # The serialize path reaches ToByteArray or WriteTo(IBufferWriter<byte>);
    # the deserialize path reaches MessageParser<T>.ParseFrom(ROSeq), which
    # tail-calls MessageExtensions.MergeFrom(msg, ROSeq, bool,
    # ExtensionRegistry). The stream / byte[] overloads never fire on the
    # KIOU gRPC path, so they are skipped; MergeFrom(CodedInputStream)
    # covers any residual CIS-based path (nested submessage parses fall
    # under it too, giving a coverage backstop).
    (0x617A650, "f657bda9", "KIOU_HOOK_ID_MSG_EXT_TO_BYTE_ARRAY",       CAVE_ENTRY, "Google.Protobuf.MessageExtensions.ToByteArray(IMessage)"),
    (0x617ACEC, "ff0302d1", "KIOU_HOOK_ID_MSG_EXT_WRITE_TO_BUFFER",     CAVE_ENTRY, "Google.Protobuf.MessageExtensions.WriteTo(IMessage, IBufferWriter<byte>)"),
    (0x617A360, "ff4304d1", "KIOU_HOOK_ID_MSG_EXT_MERGE_FROM_ROSEQ",    CAVE_ENTRY, "Google.Protobuf.MessageExtensions.MergeFrom(IMessage, ReadOnlySequence<byte>, bool, ExtensionRegistry)"),
    (0x617BA4C, "ffc301d1", "KIOU_HOOK_ID_MSG_PARSER_MERGE_FROM_CODED", CAVE_ENTRY, "Google.Protobuf.MessageParser.MergeFrom(IMessage, CodedInputStream)"),

    # ShogiMatchStreamHandler.DisposeAsync — appended AFTER the MSG_* rows so
    # its position in SITES matches its HOOK_ID (49). ChinlanDispatcher's
    # bypassEntryForHook(id) computes `cave_start + id * cave_size` and the
    # patcher allocates cave memory in SITES order — the two must agree, so
    # new hooks always go at the end.
    #
    # This is the full-teardown primitive for the matching stream. The
    # server only marks the seat as gone when the underlying gRPC HTTP/2
    # duplex call is closed (LeaveQueue frames without a stream close are
    # ignored — same match_room_id keeps getting served). We hook the entry
    # to capture the MethodInfo so the seat-filter reject branch can invoke
    # DisposeAsync directly on the cached handler self.
    (0x6AE5634, "ff4302d1", "KIOU_HOOK_ID_MATCH_STREAM_HANDLER_DISPOSE_ASYNC", CAVE_ENTRY, "ShogiMatchStreamHandler.DisposeAsync"),

    # --- NativeSyncSession Search* variants ---
    # BSE.EvaluateAsync fans out over legal candidates via SearchMulti /
    # SearchMultiWithPV, NOT the single-position SearchFull that
    # FrameworkPassthrough already covers. Adding these 5 catches every
    # engine invocation the game side can issue so the KiouEditor logger
    # sees each search's per-move score + PV.
    (0x6C5B6C0, "ffc300d1", "KIOU_HOOK_ID_NSS_SEARCH",              CAVE_ENTRY, "NativeSyncSession.Search"),
    (0x6C5C090, "ffc302d1", "KIOU_HOOK_ID_NSS_SEARCHMULTI",         CAVE_ENTRY, "NativeSyncSession.SearchMulti"),
    (0x6C5CD8C, "ff4302d1", "KIOU_HOOK_ID_NSS_SEARCHMULTIPV",       CAVE_ENTRY, "NativeSyncSession.SearchMultiPV"),
    (0x6C5D2F8, "ff4303d1", "KIOU_HOOK_ID_NSS_SEARCHMULTIWITHPV",   CAVE_ENTRY, "NativeSyncSession.SearchMultiWithPV"),
    (0x6C59AFC, "ff8302d1", "KIOU_HOOK_ID_NSS_SEARCHMULTIPVWITHPV", CAVE_ENTRY, "NativeSyncSession.SearchMultiPVWithPV"),
    (0x6C57848, "ff8301d1", "KIOU_HOOK_ID_NSS_SETOPTION",            CAVE_ENTRY, "NativeSyncSession.SetOption"),
]
# fmt: on
