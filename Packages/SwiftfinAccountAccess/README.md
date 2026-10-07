# SwiftfinAccountAccess

Owns public server/login queries, immutable authentication-result validation,
current-user identity verification, password/Quick Connect commands and account
image URLs. All capabilities use the same bound transport. The app composes
local account/credential persistence and UI policy evaluation through existing
owners. Tests use synthetic transports; no real credentials or accounts change.
