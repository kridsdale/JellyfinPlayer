# SwiftfinText

Owns text transformations, exact display constants, optional raw-value parsing, Foundation URL parsing, UTF-8/Base64 and legacy SHA1 string encoding. Depends only on Foundation and system CryptoKit; no application, UI, storage, SDK, transport or settings dependency. These operations have no mutable shared state or actor assumptions. SHA1 is retained for legacy value compatibility, not password storage.

Application display/list conformances and list views remain in composition. Consumers explicitly import this owner; it re-exports no dependencies. Regex replacement uses the entire UTF-16 range, while left padding/initials use Swift grapheme clusters. The original partial-tail suffix semantics remain. Random text handles empty/negative requests without a range trap; nonempty requests retain the original alphabet and bounds.

Run `swift test --package-path Packages/SwiftfinText`; all fixtures are synthetic, with no server, simulator or filesystem traversal.
