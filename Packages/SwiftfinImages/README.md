# SwiftfinImages

Owns inherited image sources/options, installed cache-key generation, native Nuke pipeline/disk-cache policies and a compiler-checked server identity index. Exact existing dependency: Nuke 13.0.6.

The main-actor `ImagePipelines` constructor accepts a fresh data-loader factory and an immutable-value identity index. App composition supplies Pulse logging, transport policy and saved connection observations. No app globals, account objects, stored-value access, SDK credentials or media requests enter this library. Native cache callbacks run off the UI actor and read only checked locked values.

Installed SHA1 path/query keys, max-width suffixes, splashscreen suffix behavior, poster cache name/limit and persistent local cache path are preserved. Nuke pipelines are an explicit UI interoperability API; no hidden dependency re-exports are used. The separate KidsArtwork library retains exact authorization/caching policy.

Run `swift test --package-path Packages/SwiftfinImages`. Tests use synthetic URLs and temporary cache directories.
