#pragma once

#import <Foundation/Foundation.h>
#import <stdbool.h>

// ===========================================================================
// Account/Persistence.h — KIOU account identity storage.
//
// NSUserDefaults-backed catalog of saved accounts plus the pending-switch
// state machine. Consumers (KiouForge settings UI, KiouEditor when migrated)
// read this surface and drive the AccountObserve hooks via the pending
// device-id / distinct-id keys.
//
// Storage layout (NSUserDefaults under "kiou_forge.account.accounts"):
//   NSArray<NSDictionary> — each entry:
//     uuid:       NSString   (LoginArgs.deviceId substitution target)
//     userName:   NSString   (display name)
//     openId:     NSString   (XXXX-YYYY-ZZZZ-WWWW)
//     userId:     NSString   (JWT.sub — primary key)
//     distinctId: NSString   (TDAnalytics UUID)
//     savedAt:    NSNumber   (UNIX seconds)
//     ranks:      NSArray    (optional)
//
// The "kiou_forge." key prefix is preserved across the KIOU-Hook extraction
// so existing installs keep their saved accounts. Multiple tweaks share the
// same NSUserDefaults domain (one user, one device), so the schema is the
// single source of truth across consumers.
// ===========================================================================

// Notification posted on any account state change.
extern NSString *const KIOUAccountStateChangedNotification;

// Save or refresh an account. Primary key is `userId`.
void KIOUSaveAccount(NSString *uuid,
                   NSString *userName,
                   NSString *openId,
                   NSString *userId,
                   NSString *distinctId);

// Return saved accounts in insertion order.
NSArray<NSDictionary *> *KIOUListAccounts(void);

// Delete an account by userId. No-op if not found.
void KIOUDeleteAccount(NSString *userId);

// Merge openId + ranks into the saved entry for userId.
void KIOUUpdateAccountProfile(NSString *userId,
                            NSString *openId,
                            NSArray<NSDictionary *> *ranks);

// Most recently observed active account userId.
NSString *KIOUActiveAccountUserId(void);
void      KIOUSetActiveAccountUserId(NSString *userId);

// When true, next AccountExists check returns false unconditionally,
// routing KIOU into the name-entry Register flow.
bool KIOUForceRegisterOnNextLaunch(void);
void KIOUSetForceRegisterOnNextLaunch(bool enabled);

// Pending deviceId override — swapped into LoginArgs.Create.
NSString *KIOUPendingDeviceId(void);
void      KIOUSetPendingDeviceId(NSString *uuid);

// Pending distinctId override — swapped into RegisterUserArgs.Create.
NSString *KIOUPendingDistinctId(void);
void      KIOUSetPendingDistinctId(NSString *uuid);

// Arm the pending_device_id for account switching.
// Refuses if pending_distinct_id is already set (mid-Register flow).
void KIOUSwitchAccount(NSString *uuid);
