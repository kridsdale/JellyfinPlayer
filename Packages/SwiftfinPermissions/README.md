# SwiftfinPermissions

Owns system permission status/query/request policy and private LocalAuthentication/CoreLocation drivers. Public status and error values are checked Sendable; the two public request/query namespaces use the main actor. The app retains display titles, usage-description strings and localized fallback errors.

Each request creates a fresh SDK driver. A checked lock-backed receipt coordinates cancellation and foreign-executor callbacks, resumes a waiter once, and clears the continuation. Pending location notifications do not complete the request; cancellation completes even when the SDK is silent. Main-actor cleanup invalidates authentication and clears location callback/delegate leases. Location's public SDK cannot withdraw an authorization dialog already requested, so cleanup claims only delegate/callback retirement, not dialog dismissal.

Native tests inject fake drivers and synthetic errors. They open no OS dialog, permission query, location service or biometric session. Current simulator testing remains held; physical system prompt behavior is unverified. No SDK source, household media or server state is changed.
