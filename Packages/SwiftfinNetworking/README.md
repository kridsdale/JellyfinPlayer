# SwiftfinNetworking

Owns mutable Jellyfin SDK clients and native socket sessions. Exact existing SDK pins: Jellyfin 3.2.0 and Get 2.2.1.

`JellyfinTransport` is a main-actor HTTP/auth/discovery/URL adapter. Device identity is supplied as a value; Pulse and UIKit stay at app composition. Metadata has no credential field. Public DTOs remain typed SDK values, while raw clients, native socket events and subscription tokens remain private/internal.

`JellyfinSocketController` exposes typed AsyncStreams for connection state, commands, sessions, activities and tasks. It owns fresh start generations/wake streams, backoff/refusal behavior and scoped native subscription cancellation. Streams release their own claim on cancellation. The static weak-owner worker never retains its controller across native waits.

Run `swift test --package-path Packages/SwiftfinNetworking` for actual SDK request/header/decode/denial/credential-isolation contracts and deterministic native-driver lifecycle tests. Fixtures use synthetic credentials and no LAN/media access.
