# KidsApplication

Owns the main-actor application coordinator for the curated child experience: approved catalog publication, parent authorization, account activation, local/cloud progress application and selection of an authorized playback session. It composes the focused domain, catalog, artwork, persistence, account-port and session libraries. It contains no Jellyfin SDK, native player, SwiftUI screen, Factory or Keychain implementation.

Production construction requires an explicit `KidsAccountHost` and `KidsPlaybackSessionFactory`. The app owns those adapters. Screen code observes read-only catalog, progress, playback, gate and failure state; edits pass through methods that enforce their existing authorization and persistence rules. Category, focus and presentation selections remain writable UI state. `accountRevision` is an opaque invalidation signal: URL/server/user/token replacement changes it; a server display-name change does not. The token-bearing account identity is internal.

Parent-PIN policy is delegated to KidsAccounts. Storage failure keeps the locked-parent route, denies setup/sign-in/replacement and displays an availability error without counting a wrong-PIN attempt. Successful secure storage precedes granting parent access, including verified same-account/library recovery. This policy does not establish asynchronous sign-in admission ownership, which remains under review.

Playback dismissal takes the exact presented controller, preventing an old sheet from stopping a replacement stream. Parent actions authorize before updating progress or native tracks. Fresh Play still performs exact selected-item authorization; no media bytes are warmed up. SwiftData schema/model identities and the cloud namespace belong to KidsPersistence and are unchanged.

DEBUG previews use synthetic state. They cannot activate/sign out accounts, set real PINs, perform media IO or save progress. Tests beside the library verify identity revision, preview isolation, parent authorization, independent show state, denial cleanup and stale presentation dismissal. Because this module uses UIKit, the same test sources are explicitly included in the tvOS `KidsValidation` test host; they are not skipped as if a native macOS run proved UIKit behavior.

Extend a dependency through its existing port or add a narrow, injected port for a genuinely new external responsibility. Keep SDK/account-storage objects out of screen-facing state and avoid an aggregate re-export facade.

Sign-in and sign-out now share a KidsAccountAdmission owner. Catalog/policy/player suspensions and local binding publication check the exact current attempt; parent relocking retires it. Credential preparation and native activation receive the same checkpoint, and the host resolves the exact server/user pair before publication. Obsolete errors are cancellation. These changes do not establish live GUI/network/credential behavior or complete the inherited global session-flow audit.
