# KIOU-Hook

Shared catalog of the KIOU iOS binary surface — RVAs, hook-site definitions, cave geometry — plus reusable Objective-C hook implementations against KIOU's account and gRPC machinery.

Consumed as a git submodule at `vendor/KIOU-Hook/` by every IPA-Patch tweak that targets KIOU.

## What lives here

- `KIOUHook.h` — the single C header that every consumer `#import`s. Declares the hook-id and entry-slot enums, the per-version `KIOU_KF_SITE_RVA_*` constants, cave geometry, and the dispatcher externs (`g_inject_entry[]`, `g_unityBase`, `KFChinlanPublish`).
- `Account/Persistence.{h,m}` — NSUserDefaults-backed account storage (saved accounts, active userId, pending device/distinct ids, force-register flag). Pure Foundation + Chinlan logging.
- `Hook/AccountObserve.m` — installs the account-switching hooks (`AccountExists`, `ILoginArgs.Create`, `IRegisterUserArgs.Create`, `RunLoginSequenceAsync.MoveNext`, `GetSelfUserProfileAsync.MoveNext`, `RunResetUserDataSequenceAsync`, `RunDeleteAccountSequenceAsync`). Provides `KFNavigateToTitleScene` for the consumer's settings UI to drive `BackToTitleSequence.RunAsync` after a switch.
- `Hook/GrpcLogging.m` — `HttpMessageInvoker.SendAsync` entry hook that rewrites the `x-user-id` request header to match the pending account when a device-id switch is armed. Prevents the server's `-40004` rejection during account switching.
- `recipes/` — Python catalog consumed by `tools.patch_macho` and `tools.verify_sites` (from Kanade). Mirrors the C-side hook-id enum 1:1; `TARGET_VERSION=1.0.1 \| 1.0.2` selects the per-version `SITES` table.

## What does NOT live here

- Tweak-specific feature hooks (FPS override, AFK suppression, analysis tuning, kifu autosave, settings UI). Those stay in each tweak's own repo.
- The Chinlan dispatcher (`ChinlanDispatcher.m`) — it's tweak-specific (it switches on the subset of hook IDs the tweak actually wires).
- Gray-area hooks. KIOU-Hook is a clean catalog; tweaks that need gray-area hooks own them locally.

## Consumer wiring (KiouForge style)

Add the submodule:

```
git submodule add git@github.com:IPA-Patch/KIOU-Hook.git vendor/KIOU-Hook
```

In the tweak's `Makefile`, cherry-pick which shared `.m` files to compile in:

```
$(TWEAK_NAME)_FILES  += vendor/KIOU-Hook/Account/Persistence.m \
                        vendor/KIOU-Hook/Hook/AccountObserve.m \
                        vendor/KIOU-Hook/Hook/GrpcLogging.m
$(TWEAK_NAME)_CFLAGS += -Ivendor/KIOU-Hook
```

In the tweak's own header, bring in the catalog at the top:

```c
#import "KIOUHook.h"
```

For Python tooling, ensure `PYTHONPATH` includes `vendor/KIOU-Hook` so `recipes.__init__` resolves.

## Versioning

The catalog tracks the latest KIOU build of every supported binary version. When KIOU ships a new build, RVAs change here once; each consumer bumps its submodule pointer in a follow-up PR.

No tags / GitHub releases yet — consumers pin to commit SHAs on `main`. Tagging will start when there is a second active consumer.
