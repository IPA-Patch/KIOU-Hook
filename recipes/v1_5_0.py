"""KIOU patch constants for app version 1.5.0 (CFBundleVersion 22).

Ported from v1_1_0.py with ``tools.port_recipe`` against
assets/1.5.0/dump.cs.index.json; every RVA and prologue below was resolved
by anchor name and read back from assets/1.5.0/Kiou-1.5.0.ipa. __TEXT
shrank from 0x94BC000 to 0x7FFC000, so no address carries over from 1.1.0.
Rows that could not be resolved are placeholders (site = None); see the
comments at BSE_ENSURE_INITIALIZED and the NativeSyncSession.Search* block.
"""

from recipes.common import CAVE_ENTRY, CAVE_OBSERVER

BUILD = 22

# Cave payload region (zero-fill tail of UnityFramework __TEXT).
# Same shape as 1.0.2 / 1.1.0: starts *after* __oslogstring
# (0x7FF8000..0x7FF8023) and runs to the end of __TEXT. Verified all-zero
# across its 0x3FDC B, which holds ~194 caves — comfortably more than the
# 56 SITES below (placeholder rows still reserve a cave). The
# __eh_frame..__oslogstring gap is skipped for the same reason as on 1.0.2.
CAVE_REGION         = (0x7FF8024, 0x7FFC000)

# Observer dispatcher slot — chinlan caves load this single 8-byte pointer.
# Placed at the same distance from the end of __DATA.__common as on 1.0.2
# (end - 0xC5C0), keeping it clear of __bss, which il2cpp/UnityRuntime
# overwrites during lazy init. __common ends at 0x8D3F238 here.
HOOK_SLOT_RVA       = 0x08D32C78
PROBED_HOOK_SLOT_RVA = HOOK_SLOT_RVA

# Entry-cave slot table — ENTRY_SLOT_BASE_RVA + idx*8 holds each hook fn ptr.
# Nothing reads INJECT_ENTRY_TABLE_RVA beyond the re-export in
# recipes/__init__.py, so this value is an approximation: on 1.0.2
# (0x8F90C00) and 1.1.0 (0xA2BDBF8) it sits exactly 0xC8C0 below the end of
# __DATA.__bss, and the same distance is applied here (__bss ends at
# 0x8AE6DB8).
INJECT_ENTRY_TABLE_RVA        = 0x8ADA4F8
PROBED_INJECT_ENTRY_TABLE_RVA = 0x8ADA4F8
ENTRY_SLOT_BASE_RVA           = 0x08D32A78
ZERO_REGION_END_RVA           = 0x08D3F238

# GameOrchestrator.IsAfkEnabled is handled via CAVE_ENTRY (see SITES
# below) on every supported version. Consumers that want the historic
# "always disabled" behaviour without wiring KIOUEditorFeatureEnabled
# can call KIOUInstallAfkSuppressHook(unityBase) — see KIOUHook.h.
AFK_SITE   = None
AFK_ORIG_8 = ""

# fmt: off
SITES = [
    # --- Entry caves (CAVE_ENTRY) ---
    (0x68B3EB4, "f44fbea9", "KIOU_HOOK_ID_SET_TARGET_FRAMERATE",      CAVE_ENTRY, "Application.set_targetFrameRate"),
    (0x5E73770, "ff0301d1", "KIOU_HOOK_ID_NSS_SETHASHSIZE",           CAVE_ENTRY, "NativeSyncSession.SetHashSize"),
    (0x5E7669C, "ff0301d1", "KIOU_HOOK_ID_NSS_SETSKILLEVEL",          CAVE_ENTRY, "NativeSyncSession.SetSkillLevel"),
    (0x5E76734, "ffc305d1", "KIOU_HOOK_ID_NSS_SEARCHFULL",            CAVE_ENTRY, "NativeSyncSession.SearchFull"),
    (0x5A04D18, "fd7bbfa9", "KIOU_HOOK_ID_ACCOUNT_EXISTS",            CAVE_ENTRY, "UserSaveDataExtensions.AccountExists"),
    (0x5CC6264, "f85fbca9", "KIOU_HOOK_ID_LOGIN_ARGS_CREATE",         CAVE_ENTRY, "ILoginArgs.Create"),
    (0x5CC6310, "f657bda9", "KIOU_HOOK_ID_REGISTER_USER_ARGS_CREATE", CAVE_ENTRY, "IRegisterUserArgs.Create"),
    (0x5851CD0, "ff0303d1", "KIOU_HOOK_ID_RUN_LOGIN_SEQ_MOVENEXT",    CAVE_ENTRY, "AuthServiceExtensions+<RunLoginSequenceAsync>d__1.MoveNext"),
    (0x5CE37E8, "ff4302d1", "KIOU_HOOK_ID_GET_SELF_PROFILE_MOVENEXT", CAVE_ENTRY, "GameService+<GetSelfUserProfileAsync>d__40.MoveNext"),
    (0x615C8DC, "000840f9", "KIOU_HOOK_ID_HTTPMSGINVOKER_SEND_ASYNC", CAVE_ENTRY, "HttpMessageInvoker.SendAsync"),

    # --- Observer caves (CAVE_OBSERVER): IMatchMode.OnMatchEndAsync x 5 ---
    (0x5AE4728, "f657bda9", "KIOU_HOOK_ID_KIFU_AI_END",        CAVE_OBSERVER, "AIMatchMode.OnMatchEndAsync"),
    (0x5AED5A4, "ff8301d1", "KIOU_HOOK_ID_KIFU_CPUSTREAM_END", CAVE_OBSERVER, "CPUStreamMode.OnMatchEndAsync"),
    (0x5AFF99C, "f44fbea9", "KIOU_HOOK_ID_KIFU_LOCAL_END",     CAVE_OBSERVER, "LocalPvPMode.OnMatchEndAsync"),
    (0x5B028C4, "ff8301d1", "KIOU_HOOK_ID_KIFU_ONLINE_END",    CAVE_OBSERVER, "OnlinePvPMode.OnMatchEndAsync"),
    (0x5B360F4, "f85fbca9", "KIOU_HOOK_ID_KIFU_REPLAY_END",    CAVE_OBSERVER, "RecordReplayMode.OnMatchEndAsync"),

    # --- Entry cave (CAVE_ENTRY): HeaderProvider.SetOrUpdateHeader ---
    # Upstream site for x-user-id swap on account switch. Avoids the
    # HttpMessageInvoker.SendAsync / Yaha borrow path that crashes when
    # the request or HttpHeaders internal dictionary is touched.
    (0x5D236B8, "f657bda9", "KIOU_HOOK_ID_HEADER_PROVIDER_SET_OR_UPDATE_HEADER", CAVE_ENTRY, "Project.Network.HeaderProvider.SetOrUpdateHeader(string, string)"),

    # --- KiouEditor entry caves (CAVE_ENTRY) ---
    (0x5D6F944, "fc6fbaa9", "KIOU_HOOK_ID_SYNC_ITEM_LIST_MERGE",        CAVE_ENTRY, "SyncItemListReply.InternalMergeFrom"),
    (0x5D7931C, "fa67bba9", "KIOU_HOOK_ID_COLLECTION_PRESET_MERGE",     CAVE_ENTRY, "UpdateCollectionPresetReply.InternalMergeFrom"),
    (0x5DE6F5C, "ffc302d1", "KIOU_HOOK_ID_SELECT_CHAR_ASYNC",           CAVE_ENTRY, "SelectCharacterAsync"),
    (0x5D5F2B8, "fc6fbaa9", "KIOU_HOOK_ID_SELECT_CHAR_REPLY_MERGE",     CAVE_ENTRY, "SelectCharacterReply.InternalMergeFrom"),
    (0x5C71448, "fc6fbaa9", "KIOU_HOOK_ID_MATCHING_PLAYER_MERGE",       CAVE_ENTRY, "ShogiMatchingPlayerStatus.InternalMergeFrom"),
    (0x5D3C2A8, "fc6fbaa9", "KIOU_HOOK_ID_HISTORY_DETAIL_MERGE",        CAVE_ENTRY, "GetShogiHistoryDetailListReply.InternalMergeFrom"),
    (0x5D3BD08, "00804039", "KIOU_HOOK_ID_HISTORY_GET_PREMIUM",         CAVE_ENTRY, "GetShogiHistoryDetailListReply.get_IsPremiumUser"),
    (0x5962E68, "00004139", "KIOU_HOOK_ID_KIFU_DETAIL_IS_PREMIUM",      CAVE_ENTRY, "KifuDetailModel.IsPremiumUser"),
    (0x5929B58, "08008052", "KIOU_HOOK_ID_VOICE_PLAYER_SATISFIES",      CAVE_ENTRY, "CharacterVoicePlayer.SatisfiesRule"),
    (0x594DBC4, "00704039", "KIOU_HOOK_ID_VOICE_CELL_GET_IS_LOCKED",    CAVE_ENTRY, "CharacterVoiceScrollerCellModel.get_IsLocked"),
    (0x5A709F4, "f85fbca9", "KIOU_HOOK_ID_BSE_CTOR",                    CAVE_ENTRY, "BeginnerSupportEvaluator.ctor"),
    # 1.1.0 replaced the NNUE evaluator with a policy model:
    # EnsureInitializedLocked, TryBorrowSession and the NativeSyncSession
    # field are all gone, and with them the hash-size knob this cave
    # existed to apply. The row stays as a placeholder (site = None) so
    # every later hook keeps its cave index — see Hook/AssistTune.m.
    # Still absent on 1.5.0.
    (None,      "f657bda9", "KIOU_HOOK_ID_BSE_ENSURE_INITIALIZED",      CAVE_ENTRY, "BeginnerSupportEvaluator.EnsureInitializedLocked"),
    (0x5A20FE0, "00404039", "KIOU_HOOK_ID_RBSUPPORT_GET_ENABLED",       CAVE_ENTRY, "ResolvedBeginnerSupport.get_Enabled"),
    (0x5A20FF8, "002040b9", "KIOU_HOOK_ID_RBSUPPORT_GET_DEPTH",         CAVE_ENTRY, "ResolvedBeginnerSupport.get_Depth"),
    (0x5B9F748, "fc6fbaa9", "KIOU_HOOK_ID_HOME_UTILITY_PRESENTER_CTOR", CAVE_ENTRY, "HomeUtilityPresenter.ctor"),
    (0x5EEC504, "f44fbea9", "KIOU_HOOK_ID_UIBUTTONBASE_ONPOINTERCLICK", CAVE_ENTRY, "UIButtonBase.OnPointerClick"),
    (0x5EE643C, "ff0303d1", "KIOU_HOOK_ID_TITLE_SCENE_MOVENEXT",        CAVE_ENTRY, "TitleScene+<OnActivateAsync>d__10.MoveNext"),
    (0x5A29B94, "f44fbea9", "KIOU_HOOK_ID_GAME_ORCHESTRATOR_IS_AFK",    CAVE_ENTRY, "GameOrchestrator.IsAfkEnabled"),
    (0x5A711CC, "ff4302d1", "KIOU_HOOK_ID_BSE_EVALUATE_ASYNC",          CAVE_ENTRY, "BeginnerSupportEvaluator.EvaluateAsync"),

    # --- KiouEditor 棋桜覚醒 (AI Special Support) UI-unlock caves. ------------
    # Server-side reject on the network still applies; this is UI unlock only.
    (0x5C748C4, "00204339", "KIOU_HOOK_ID_MOVE_RESULT_CAN_USE_SPECIAL",  CAVE_ENTRY, "ShogiMoveResultStatus.get_CanUseAiSpecialSupport"),
    (0x5C74894, "00bc40b9", "KIOU_HOOK_ID_MOVE_RESULT_FREE_REMAINING",   CAVE_ENTRY, "ShogiMoveResultStatus.get_AiSpecialSupportRemainingFreeCount"),
    (0x5C748A4, "00c040b9", "KIOU_HOOK_ID_MOVE_RESULT_TICKET_REMAINING", CAVE_ENTRY, "ShogiMoveResultStatus.get_AiSpecialSupportRemainingTicketCount"),
    (0x5C6FF74, "008840b9", "KIOU_HOOK_ID_MP_FREE_REMAINING",            CAVE_ENTRY, "ShogiMatchingPlayerStatus.get_AiSpecialSupportFreeRemainingCount"),
    (0x5C6FF84, "008c40b9", "KIOU_HOOK_ID_MP_PAID_AVAILABLE",            CAVE_ENTRY, "ShogiMatchingPlayerStatus.get_AiSpecialSupportPaidAvailableCount"),

    # --- KiouEditor preferred-seat filter (ported from KiouEngineBridge). ----
    # Reject a MatchFound if it puts the user on the "wrong" seat, then
    # send ConnectionFailed to the matching server so it re-queues.
    (0x5E3DE84, "ff0301d1", "KIOU_HOOK_ID_MATCH_GET_VALID_FOUND",          CAVE_ENTRY, "MatchingHandler.GetValidMatchFoundStatus"),
    (0x5E3F71C, "ff0303d1", "KIOU_HOOK_ID_MATCH_RECEIVE_TIMEOUT_MOVENEXT", CAVE_ENTRY, "MatchingHandler+<ReceiveWithTimeoutAsync>d__6.MoveNext"),
    (0x5CF9204, "fc6fbaa9", "KIOU_HOOK_ID_MATCH_STREAM_ARGS_CREATE",       CAVE_ENTRY, "IShogiMatchStreamArgs.Create"),
    # d__3 wraps the caller state around StartMatchingAsyncInternal — we
    # snapshot its <>8__1 (DisplayClass3_0) pointer so the seat-filter
    # reject branch can Cancel() its matchingCts and let the game's own
    # TryLeaveQueueAsync unwind the popup cleanly.
    (0x5E40DA0, "ffc305d1", "KIOU_HOOK_ID_MATCH_START_D3_MOVENEXT",        CAVE_ENTRY, "MatchingHandler+<StartMatchingAsync>d__3.MoveNext"),
    # ShogiMatchStreamHandler.SendAsync — every outgoing frame the game
    # writes to the matching stream (Heartbeat every 3 s, JoinQueue,
    # LeaveQueue, ConnectionFailed) flows through this call. We hook the
    # entry so we can (a) log every outbound frame and (b) capture the
    # MethodInfo argument (x2) into a global so the seat-filter reject
    # branch can call SendAsync directly with a valid MethodInfo instead
    # of NULL (which crashes the il2cpp method body).
    (0x5CF9A18, "f657bda9", "KIOU_HOOK_ID_MATCH_STREAM_HANDLER_SEND_ASYNC", CAVE_ENTRY, "ShogiMatchStreamHandler.SendAsync"),

    # --- Universal gRPC wire logger (protobuf serialize/parse bottlenecks) ---
    # The serialize path reaches ToByteArray or WriteTo(IBufferWriter<byte>);
    # the deserialize path reaches MessageParser<T>.ParseFrom(ROSeq), which
    # tail-calls MessageExtensions.MergeFrom(msg, ROSeq, bool,
    # ExtensionRegistry). The stream / byte[] overloads never fire on the
    # KIOU gRPC path, so they are skipped; MergeFrom(CodedInputStream)
    # covers any residual CIS-based path (nested submessage parses fall
    # under it too, giving a coverage backstop).
    (0x539F2D8, "f657bda9", "KIOU_HOOK_ID_MSG_EXT_TO_BYTE_ARRAY",       CAVE_ENTRY, "Google.Protobuf.MessageExtensions.ToByteArray(IMessage)"),
    (0x539F974, "ff0302d1", "KIOU_HOOK_ID_MSG_EXT_WRITE_TO_BUFFER",     CAVE_ENTRY, "Google.Protobuf.MessageExtensions.WriteTo(IMessage, IBufferWriter<byte>)"),
    (0x539EFE8, "ff4304d1", "KIOU_HOOK_ID_MSG_EXT_MERGE_FROM_ROSEQ",    CAVE_ENTRY, "Google.Protobuf.MessageExtensions.MergeFrom(IMessage, ReadOnlySequence<byte>, bool, ExtensionRegistry)"),
    (0x53A06D4, "ffc301d1", "KIOU_HOOK_ID_MSG_PARSER_MERGE_FROM_CODED", CAVE_ENTRY, "Google.Protobuf.MessageParser.MergeFrom(IMessage, CodedInputStream)"),

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
    (0x5CF982C, "ff4302d1", "KIOU_HOOK_ID_MATCH_STREAM_HANDLER_DISPOSE_ASYNC", CAVE_ENTRY, "ShogiMatchStreamHandler.DisposeAsync"),

    # --- NativeSyncSession Search* variants ---
    # BSE.EvaluateAsync fans out over legal candidates via SearchMulti /
    # SearchMultiWithPV, NOT the single-position SearchFull that
    # FrameworkPassthrough already covers. Adding these 5 catches every
    # engine invocation the game side can issue so the KiouEditor logger
    # sees each search's per-move score + PV.
    #
    # 1.5.0 dropped SearchMulti / SearchMultiPV / SearchMultiWithPV from
    # NativeSyncSession (only Search, SearchFull, SearchMultiPVWithPV,
    # SetOption, SetHashSize and SetSkillLevel remain). Those three rows
    # stay as placeholders (site = None) for the same reason as
    # BSE_ENSURE_INITIALIZED: caves are handed out in SITES order and
    # ChinlanDispatcher computes `cave_start + id * cave_size`, so deleting
    # a row would shift every later hook id off its cave. The prologue
    # column is carried over from 1.1.0 and is never checked (no site).
    (0x5E76710, "ffc300d1", "KIOU_HOOK_ID_NSS_SEARCH",              CAVE_ENTRY, "NativeSyncSession.Search"),
    (None,      "ffc302d1", "KIOU_HOOK_ID_NSS_SEARCHMULTI",         CAVE_ENTRY, "NativeSyncSession.SearchMulti"),
    (None,      "ff4302d1", "KIOU_HOOK_ID_NSS_SEARCHMULTIPV",       CAVE_ENTRY, "NativeSyncSession.SearchMultiPV"),
    (None,      "ff4303d1", "KIOU_HOOK_ID_NSS_SEARCHMULTIWITHPV",   CAVE_ENTRY, "NativeSyncSession.SearchMultiWithPV"),
    (0x5E74B4C, "ff8302d1", "KIOU_HOOK_ID_NSS_SEARCHMULTIPVWITHPV", CAVE_ENTRY, "NativeSyncSession.SearchMultiPVWithPV"),
    (0x5E72898, "ff8301d1", "KIOU_HOOK_ID_NSS_SETOPTION",            CAVE_ENTRY, "NativeSyncSession.SetOption"),
]
# fmt: on
