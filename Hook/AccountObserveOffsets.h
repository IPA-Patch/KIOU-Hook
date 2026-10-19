#pragma once

// ===========================================================================
// Hook/AccountObserveOffsets.h — il2cpp field offsets read by
// Hook/AccountObserve.m. Offsets that differ between builds are selected on
// KIOU_HOOK_TARGET_BUILD (KIOUHook.h, which AccountObserve.m includes first).
// ===========================================================================

// ---------------------------------------------------------------------------
// Field offsets
// ---------------------------------------------------------------------------
#define OFF_USER_SAVE_DATA_USER_NAME  0x10
#define OFF_USER_SAVE_DATA_OPEN_ID    0x18
#define OFF_USER_SAVE_DATA_USER_ID    0x20
#define OFF_USER_SAVE_DATA_DEVICE_ID  0x28

#define OFF_LOGIN_REPLY_ACCESS_TOKEN  0x18
#define OFF_LOGIN_REPLY_SESSION_ID    0x20
#define OFF_LOGIN_REPLY_DEVICE_ID     0x28
#define OFF_LOGIN_REPLY_USER_NAME     0x30

// RunLoginSequenceAsync.<d__1> state machine. The LoginReply is read out of
// the UniTask.Awaiter<ILoginReply> (<>u__1) hoisted local, 0x18 past the
// awaiter's dump.cs offset (0x50 confirmed on KIOU 1.0.1 build 11, where
// <>u__1 sits at 0x38). 1.5.0 hoisted <>8__1 / <userSaveData>5__2 /
// <sessionData>5__3 ahead of the awaiter, moving <>u__1 to 0x48 and the
// result slot with it to 0x60.
#define OFF_SM_LOGIN_STATE     0x00
#if KIOU_HOOK_TARGET_BUILD >= 22
#define OFF_SM_LOGIN_AWAITER   0x48
#else
#define OFF_SM_LOGIN_AWAITER   0x38
#endif
#define OFF_SM_LOGIN_RESULT_D  (OFF_SM_LOGIN_AWAITER + 0x18)

#define OFF_GET_SELF_PROFILE_REPLY_PROFILE  0x18
#define OFF_SELF_PROFILE_USER_NAME          0x18
#define OFF_SELF_PROFILE_OPEN_USER_ID       0x20
// dump.cs SelfUserProfileStatus.rankList_: 0x28 on 1.0.x, 0x30 on 1.1.0 and
// 1.5.0 (userAttribute_ inserted at 0x28). Build 15 keeps its historical
// value here; only the new build takes 0x30.
#if KIOU_HOOK_TARGET_BUILD >= 22
#define OFF_SELF_PROFILE_RANK_LIST          0x30
#else
#define OFF_SELF_PROFILE_RANK_LIST          0x28
#endif
#define OFF_REPEATED_ARRAY                  0x10
#define OFF_REPEATED_COUNT                  0x18
#define OFF_RANK_STATUS_MATCH_TYPE     0x18
#define OFF_RANK_STATUS_RANK_RULE_TYPE 0x1C
#define OFF_RANK_STATUS_RANK           0x24
#define OFF_RANK_STATUS_RATING         0x28
