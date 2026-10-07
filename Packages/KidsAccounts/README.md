# KidsAccounts

Owns the main-actor account host port, immutable authorization identity, prepared account activation and parent-PIN authorization. SDK authentication, native credentials and session activation are injected by the app; catalog authorization belongs to KidsCatalog. The package depends only on KidsDomain and Combine/Foundation.

`KidsAccountHost.parentPIN` is a throwing read: `nil` means the store successfully reported no PIN. A read failure keeps `hasParentPIN` true for presentation and denies setup, matching and replacement with `KidsParentPINError.unavailable`. UI actions use the throwing methods rather than relying on the presentation hint. `replaceParentPIN` validates 4–8 numeric characters, requires an unlocked parent when a PIN exists, and reports write failures before the caller grants access. No credentials appear in error descriptions.

Recovery admission does not grant authority to replace a locked PIN. The coordinator must first verify the same previous account and both exact library identities, then explicitly authorize replacement; unreadable storage still denies it. Gate timing, cooldowns and durable progress remain in their existing domain/persistence owners.

The 14 macOS contracts use a fake host, including eight PIN policy tests for missing/configured/unavailable storage, matching, setup, formatting, locked replacement, read/write failures and recovery. Application integration tests compile with the tvOS test host; simulator execution and native Keychain interoperability are separate acceptance gates.
