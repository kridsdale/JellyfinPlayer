# SwiftfinCollections

Owns synchronous collection projections, safe index/mutation helpers, subset-case contracts and ArrayBuilder. Dependencies are Foundation and pinned OrderedCollections value types; no media SDK, settings, UI or app imports. Public helpers are stateless operations executed by their caller. Arbitrary generic elements and callbacks do not become Sendable by passing through these helpers.

The optional-key comparator now returns false for nil/nil, restoring strict ordering while keeping nil values last. Tests exercise nonzero slice indices, empty removal, equal-nil stability, mixed result-builder expressions and ordered dictionary projections.

Run `swift test --package-path Packages/SwiftfinCollections`.

The unused mutable Trie type was removed after checking every app and package source; its only caller was its own test. `keyed(using:)` retains the standard unique-key precondition of Dictionary(uniqueKeysWithValues:). Collection helpers create no tasks, retain no callbacks and access no process globals.
