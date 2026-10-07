# KidsAccounts

Owns the main-actor account host port, immutable authorization identity, prepared account activation and parent-PIN authorization. SDK authentication, native credentials and session activation are injected by the app; catalog authorization belongs to KidsCatalog. The package depends on KidsDomain and the existing SwiftfinAsyncStreams ticket owner, plus Combine/Foundation.

`KidsAccountHost.parentPIN` is a throwing read: `nil` means the store successfully reported no PIN. A read failure keeps `hasParentPIN` true for presentation and denies setup, matching and replacement with `KidsParentPINError.unavailable`. UI actions use the throwing methods rather than relying on the presentation hint. `replaceParentPIN` validates 4–8 numeric characters, requires an unlocked parent when a PIN exists, and reports write failures before the caller grants access. No credentials appear in error descriptions.

Recovery admission does not grant authority to replace a locked PIN. The coordinator must first verify the same previous account and both exact library identities, then explicitly authorize replacement; unreadable storage still denies it. Gate timing, cooldowns and durable progress remain in their existing domain/persistence owners.

The 25 macOS contracts use a fake host, including eight PIN policy tests for missing/configured/unavailable storage, matching, setup, formatting, locked replacement, read/write failures and recovery. Application integration tests compile with the tvOS test host; simulator execution and native Keychain interoperability are separate acceptance gates.

`KidsAccountAdmission` owns one relevant sign-in/sign-out attempt. Check after suspension and immediately before effects. Synchronous main-actor identity signals reject account/URL/token changes and ABA; the exact authenticated target remains valid during its own credential replacement and activation. Sign-out admits nil and a delayed logout cannot clear a newer account. Parent relocking retires pending admission. This owner starts no tasks and performs no storage or network work.

`KidsAuthenticatedAccount` receives a checkpoint in storage/activation callbacks. Preparation always revokes previous preparation, even on failure; activation consumes its binding before suspension. The host checks immediately before each later effect and carries the callback through native session preparation. Committed storage/settings/publication effects are not transactional and are not undone on later cancellation. Full global session routing and live acceptance remain separate review gates.
