#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/SelectCharacter.m — server-clean skin selection (2 sites).
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_SelectCharacter.m at
// SHA 4d137803. Same semantics; only the hook engine wiring changed —
// bodies now use the KIOU-Hook name-based API instead of the KiouEditor
// binpatch slot table.
//
// Strategy:
//   - SelectCharacterAsync (RVA_SELECT_CHAR_ASYNC): if the user asked for
//     a skin other than KIOU_SAFE_SKIN_ID, remember that intent in
//     NSUserDefaults and rewrite the outgoing Args.mstCharacterSkinId_ to
//     KIOU_SAFE_SKIN_ID. The server sees only a legal request and never
//     returns -40302.
//   - SelectCharacterReply.InternalMergeFrom (RVA_SELECT_CHAR_REPLY_MERGE):
//     after the original decode, walk updatedCharacterList_ +
//     updatedCharacterSkinList_ and rewrite is_selected entries to
//     advertise the persisted skin id.
//
// Persistence lives in Hook/Common.m so Hook/SyncItemList.m can reuse it.
// ===========================================================================

// ---------------------------------------------------------------------------
// Field offsets — Args + Reply DTOs.
// ---------------------------------------------------------------------------
#define OFF_ARGS_SKIN_ID     0x18
#define OFF_REPLY_CHAR_LIST  0x18
#define OFF_REPLY_SKIN_LIST  0x20

// ---------------------------------------------------------------------------
// Orig signatures.
// ---------------------------------------------------------------------------
typedef void *(*SelectCharacterAsync_t)(void *self, void *args, void *opts,
                                        void *a3, void *a4, void *a5);
typedef void  (*ReplyMergeFrom_t)(void *self, void *parseContext);

static SelectCharacterAsync_t s_origSelectCharacterAsync   = NULL;
static ReplyMergeFrom_t       s_origSelectCharacterReplyMerge = NULL;

// ---------------------------------------------------------------------------
// HOOK: SelectCharacterAsync request swap.
//
// arm64 calling convention, x0 = self (client), x1 = args. We rewrite
// args->mstCharacterSkinId_ in place before forwarding, so the server
// only ever receives KIOU_SAFE_SKIN_ID.
// ---------------------------------------------------------------------------

static void *hook_SelectCharacterAsync(void *self, void *args, void *opts,
                                       void *a3, void *a4, void *a5) {
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_CHAR_BYPASS)) {
        return s_origSelectCharacterAsync(self, args, opts, a3, a4, a5);
    }
    if (ptrLooksValid(args)) {
        int32_t requested = readI32(args, OFF_ARGS_SKIN_ID);
        if (requested > 0 && requested != KIOU_SAFE_SKIN_ID) {
            KIOUEditorSetPersistedSelection(requested);
            writeI32(args, OFF_ARGS_SKIN_ID, KIOU_SAFE_SKIN_ID);
            IPALog([NSString stringWithFormat:
                    @"[SELECT][REQ] user=%d -> server=%d (persisted)",
                    requested, KIOU_SAFE_SKIN_ID]);
        } else if (requested == KIOU_SAFE_SKIN_ID) {
            // The user explicitly picked the safe skin. Drop any override.
            if (KIOUEditorPersistedSelection() != 0) {
                KIOUEditorSetPersistedSelection(0);
                IPALog(@"[SELECT][REQ] user picked SAFE_ID; cleared persisted override");
            } else {
                IPALog([NSString stringWithFormat:
                        @"[SELECT][REQ] passthrough skinId=%d", requested]);
            }
        }
    }
    return s_origSelectCharacterAsync(self, args, opts, a3, a4, a5);
}

// ---------------------------------------------------------------------------
// HOOK: SelectCharacterReply.InternalMergeFrom.
//
// Let the original decode complete, then rewrite is_selected entries in
// both returned lists via the shared helper in Hook/Common.m.
// ---------------------------------------------------------------------------

static void hook_SelectCharacterReplyMerge(void *self, void *parseContext) {
    if (s_origSelectCharacterReplyMerge) {
        s_origSelectCharacterReplyMerge(self, parseContext);
    }
    if (!KIOUEditorFeatureEnabled(KIOU_FEATURE_CHAR_BYPASS)) return;
    if (!ptrLooksValid(self)) return;

    @try {
        void *charArr = NULL;
        int32_t charCount = 0;
        readRepeatedField(self, OFF_REPLY_CHAR_LIST, &charArr, &charCount);

        void *skinArr = NULL;
        int32_t skinCount = 0;
        readRepeatedField(self, OFF_REPLY_SKIN_LIST, &skinArr, &skinCount);

        IPALog([NSString stringWithFormat:
                @"[SELECT][RESP] charCount=%d skinCount=%d persisted=%d",
                charCount, skinCount, KIOUEditorPersistedSelection()]);

        KIOUEditorApplyPersistedSelectionToLists(charArr, charCount, skinArr, skinCount);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[SELECT][RESP] exception: %@", e]);
    }
}

// ---------------------------------------------------------------------------
// Installer.
// ---------------------------------------------------------------------------

void KIOUEditorInstallSelectCharacterHook(uintptr_t unityBase) {
    s_origSelectCharacterAsync = (SelectCharacterAsync_t)KIOUHookInstall(
        KIOU_HOOK_NAME_SELECT_CHAR_ASYNC,
        (void *)hook_SelectCharacterAsync, unityBase);
    s_origSelectCharacterReplyMerge = (ReplyMergeFrom_t)KIOUHookInstall(
        KIOU_HOOK_NAME_SELECT_CHAR_REPLY_MERGE,
        (void *)hook_SelectCharacterReplyMerge, unityBase);
    IPALog([NSString stringWithFormat:
            @"[SELECT] installed: Async orig=%p Reply.merge orig=%p "
            @"SAFE_ID=%d persisted=%d",
            (void *)s_origSelectCharacterAsync,
            (void *)s_origSelectCharacterReplyMerge,
            KIOU_SAFE_SKIN_ID, KIOUEditorPersistedSelection()]);
}
