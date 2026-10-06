# SwiftfinCollections

Owns collection projections, safe index/mutation helpers, subset-case contracts, ArrayBuilder and a synchronous prefix trie. Foundation only; no SDK, settings, UI or app imports. Public helpers are stateless value operations. Trie is deliberately not Sendable and has one owner; app editing callers retain their existing ownership.

The optional-key comparator now returns false for nil/nil, restoring strict ordering while keeping nil values last. Tests exercise nonzero slice indices, empty removal, equal-nil stability, mixed result-builder expressions and prefix ordering.

Run `swift test --package-path Packages/SwiftfinCollections`.
