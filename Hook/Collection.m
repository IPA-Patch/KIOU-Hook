#import "Hook/Common.h"
#import "logging.h"

// ===========================================================================
// Hook/Collection.m — UpdateCollectionPresetReply.InternalMergeFrom.
//
// Migrated from KiouEditor's Sources/KiouEditor/Hook_Collection.m.
//
//   self + 0x18 = updatedUserCollectionList_ (RepeatedField<UserCollectionStatus>)
//   UserCollectionStatus + 0x20 = presetList_ (RepeatedField<UserCollectionPresetStatus>)
//   UserCollectionPresetStatus: +0x18 presetNumber, +0x1C mstIconId,
//     +0x20 mstIconFrameId, +0x24 mstAchievementId, +0x28 mstShogiPieceId,
//     +0x2C mstShogiBoardId, +0x30 mstShogiIngameBgmId (all int32)
//
// OBSERVATION ONLY. No writes.
// ===========================================================================

typedef void (*InternalMergeFrom_t)(void *self, void *parseContext);

static InternalMergeFrom_t s_origCollectionPresetReply_merge = NULL;

static void hook_CollectionPresetReply_merge(void *self, void *parseContext) {
    if (s_origCollectionPresetReply_merge) {
        s_origCollectionPresetReply_merge(self, parseContext);
    }

    if (g_inHook) return;
    g_inHook = 1;
    @try {
        if (ptrLooksValid(self)) {
            void *collArr = NULL;
            int32_t collCount = 0;
            if (readRepeatedField(self, 0x18, &collArr, &collCount)) {
                IPALog([NSString stringWithFormat:
                        @"[UpdateCollectionPresetReply] updatedUserCollectionList count=%d",
                        collCount]);
                for (int32_t i = 0; i < collCount; i++) {
                    void *coll = readArrayElem(collArr, i);
                    if (!coll) continue;
                    void *presetArr = NULL;
                    int32_t presetCount = 0;
                    if (!readRepeatedField(coll, 0x20, &presetArr, &presetCount)) {
                        IPALog([NSString stringWithFormat:
                                @"[UpdateCollectionPresetReply]   [%d] presetList unreadable/empty",
                                i]);
                        continue;
                    }
                    IPALog([NSString stringWithFormat:
                            @"[UpdateCollectionPresetReply]   [%d] presetList count=%d",
                            i, presetCount]);
                    for (int32_t j = 0; j < presetCount; j++) {
                        void *preset = readArrayElem(presetArr, j);
                        if (!preset) continue;
                        int32_t presetNumber        = readI32(preset, 0x18);
                        int32_t mstIconId           = readI32(preset, 0x1C);
                        int32_t mstIconFrameId      = readI32(preset, 0x20);
                        int32_t mstAchievementId    = readI32(preset, 0x24);
                        int32_t mstShogiPieceId     = readI32(preset, 0x28);
                        int32_t mstShogiBoardId     = readI32(preset, 0x2C);
                        int32_t mstShogiIngameBgmId = readI32(preset, 0x30);
                        IPALog([NSString stringWithFormat:
                                @"[UpdateCollectionPresetReply]     preset[%d] num=%d icon=%d "
                                @"frame=%d achievement=%d piece=%d board=%d bgm=%d",
                                j, presetNumber, mstIconId, mstIconFrameId,
                                mstAchievementId, mstShogiPieceId, mstShogiBoardId,
                                mstShogiIngameBgmId]);
                    }
                }
            } else {
                IPALog(@"[UpdateCollectionPresetReply] updatedUserCollectionList unreadable/empty");
            }
        }
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                @"[UpdateCollectionPresetReply] exception: %@", e]);
    }
    g_inHook = 0;
}

void KIOUEditorInstallCollectionHook(uintptr_t unityBase) {
    s_origCollectionPresetReply_merge = (InternalMergeFrom_t)KIOUHookInstall(
        KIOU_HOOK_NAME_COLLECTION_PRESET_MERGE,
        (void *)hook_CollectionPresetReply_merge, unityBase);
    IPALog([NSString stringWithFormat:
            @"[COLLECTION] installed: orig=%p (observation only)",
            (void *)s_origCollectionPresetReply_merge]);
}
