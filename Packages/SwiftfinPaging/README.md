# SwiftfinPaging

Owns generic main-actor browse/search collections, consumed-row cursors, ordered ID deduplication, page-flight coalescing, refresh/search generations, stale-binding checks, random selection, and monotonic delayed refresh scheduling. Foundation/Combine only; no UI, Jellyfin SDK, factories, settings, persistent state or credentials.

Composition supplies an opaque stable binding UUID, exact transport-validity predicate and immutable page/search/random loaders. Main/search have independent request generations. Replacement bindings and invalidation clear both collections; old completions cannot clear or overwrite a replacement. Failed requests preserve cursors for retry. Non-paged sources load once. Filtering can supply raw consumed-row counts rather than display counts. Notification removal preserves cursors. Every result is checked for caller cancellation and current binding before publication or random-selection delivery.

The app retains presentation, SDK DTO notification mapping, account/transport composition and library-specific request adapters. The complete inherited query/presentation split is a separate remaining requirement; this library is not a catch-all feature facade.
