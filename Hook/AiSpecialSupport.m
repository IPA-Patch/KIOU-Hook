#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/AiSpecialSupport.m — 棋桜覚醒 (AI Special Support) UI unlock.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook/AiSpecialSupport.m so
// the chinlan flavour can actually dispatch these caves. The historical
// "paid-feature stays out of the shared catalog" policy from the README
// was relaxed once KiouEditor picked up a KIOU_FEATURE_AI_SPECIAL_SUPPORT
// toggle (default off) that gates every one of these hooks — the shared
// catalog only publishes the site plumbing; the user still has to opt in
// through KiouEditor's settings sheet for anything to change.
//
// Five getters gate the button on the client:
//
//   ShogiMoveResultStatus:
//     get_CanUseAiSpecialSupport           -> bool (server allow-flag)
//     get_AiSpecialSupportRemainingFreeCount  -> int32
//     get_AiSpecialSupportRemainingTicketCount-> int32
//   ShogiMatchingPlayerStatus:
//     get_AiSpecialSupportFreeRemainingCount  -> int32
//     get_AiSpecialSupportPaidAvailableCount  -> int32
//
// When the toggle is on we force CanUse -> true and pin the four
// count getters to KIOU_AI_SPECIAL_SUPPORT_MAX_COUNT (255). The server
// can still reject the request at the network layer — this is UI
// unlock only, no state or currency change.
// ===========================================================================

#define KIOU_AI_SPECIAL_SUPPORT_MAX_COUNT   255

typedef bool    (*GetBool_t)(void *self);
typedef int32_t (*GetI32_t)(void *self);

static GetBool_t s_origMoveResult_CanUse          = NULL;
static GetI32_t  s_origMoveResult_FreeRemaining   = NULL;
static GetI32_t  s_origMoveResult_TicketRemaining = NULL;
static GetI32_t  s_origMP_FreeRemaining           = NULL;
static GetI32_t  s_origMP_PaidAvailable           = NULL;

static bool hook_MoveResult_CanUse(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_AI_SPECIAL_SUPPORT)) {
        return s_origMoveResult_CanUse ? s_origMoveResult_CanUse(self) : false;
    }
    (void)self;
    return true;
}

static int32_t hook_MoveResult_FreeRemaining(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_AI_SPECIAL_SUPPORT)) {
        return s_origMoveResult_FreeRemaining
            ? s_origMoveResult_FreeRemaining(self) : 0;
    }
    (void)self;
    return KIOU_AI_SPECIAL_SUPPORT_MAX_COUNT;
}

static int32_t hook_MoveResult_TicketRemaining(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_AI_SPECIAL_SUPPORT)) {
        return s_origMoveResult_TicketRemaining
            ? s_origMoveResult_TicketRemaining(self) : 0;
    }
    (void)self;
    return KIOU_AI_SPECIAL_SUPPORT_MAX_COUNT;
}

static int32_t hook_MP_FreeRemaining(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_AI_SPECIAL_SUPPORT)) {
        return s_origMP_FreeRemaining ? s_origMP_FreeRemaining(self) : 0;
    }
    (void)self;
    return KIOU_AI_SPECIAL_SUPPORT_MAX_COUNT;
}

static int32_t hook_MP_PaidAvailable(void *self) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_AI_SPECIAL_SUPPORT)) {
        return s_origMP_PaidAvailable ? s_origMP_PaidAvailable(self) : 0;
    }
    (void)self;
    return KIOU_AI_SPECIAL_SUPPORT_MAX_COUNT;
}

void KIOUEditorInstallAiSpecialSupportHook(uintptr_t unityBase) {
    s_origMoveResult_CanUse = (GetBool_t)KIOUHookInstall(
        KIOU_HOOK_NAME_MOVE_RESULT_CAN_USE_SPECIAL,
        (void *)hook_MoveResult_CanUse, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase,
        KIOU_HOOK_SLOT_MOVE_RESULT_CAN_USE_SPECIAL,
        hook_MoveResult_CanUse);

    s_origMoveResult_FreeRemaining = (GetI32_t)KIOUHookInstall(
        KIOU_HOOK_NAME_MOVE_RESULT_FREE_REMAINING,
        (void *)hook_MoveResult_FreeRemaining, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase,
        KIOU_HOOK_SLOT_MOVE_RESULT_FREE_REMAINING,
        hook_MoveResult_FreeRemaining);

    s_origMoveResult_TicketRemaining = (GetI32_t)KIOUHookInstall(
        KIOU_HOOK_NAME_MOVE_RESULT_TICKET_REMAINING,
        (void *)hook_MoveResult_TicketRemaining, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase,
        KIOU_HOOK_SLOT_MOVE_RESULT_TICKET_REMAINING,
        hook_MoveResult_TicketRemaining);

    s_origMP_FreeRemaining = (GetI32_t)KIOUHookInstall(
        KIOU_HOOK_NAME_MP_FREE_REMAINING,
        (void *)hook_MP_FreeRemaining, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase,
        KIOU_HOOK_SLOT_MP_FREE_REMAINING,
        hook_MP_FreeRemaining);

    s_origMP_PaidAvailable = (GetI32_t)KIOUHookInstall(
        KIOU_HOOK_NAME_MP_PAID_AVAILABLE,
        (void *)hook_MP_PaidAvailable, unityBase);
    KIOU_HOOK_PUBLISH_SLOT(unityBase,
        KIOU_HOOK_SLOT_MP_PAID_AVAILABLE,
        hook_MP_PaidAvailable);

    IPALog([NSString stringWithFormat:
            @"[AI-SPECIAL] installed: CanUse orig=%p FreeRem=%p TicketRem=%p "
            @"MP.Free=%p MP.Paid=%p (feature gate=%d)",
            (void *)s_origMoveResult_CanUse,
            (void *)s_origMoveResult_FreeRemaining,
            (void *)s_origMoveResult_TicketRemaining,
            (void *)s_origMP_FreeRemaining,
            (void *)s_origMP_PaidAvailable,
            (int)KIOUEditorFeatureEnabled(KIOU_FEATURE_AI_SPECIAL_SUPPORT)]);
}
