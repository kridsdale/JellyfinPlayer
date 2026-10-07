// swift-tools-version: 6.0
import PackageDescription

// Development-only state tool and cross-package integration checks.
let package = Package(
    name: "KidsValidationTools",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [.executable(name: "KidsStateTool", targets: ["KidsStateTool"])],
    dependencies: [
        .package(path: "../Packages/KidsDomain"),
        .package(path: "../Packages/KidsPersistence"),
        .package(path: "../Packages/KidsPlayback"),
        .package(path: "../Packages/SwiftfinItemMetadata"),
        .package(path: "../Packages/SwiftfinMediaCatalog"),
        .package(path: "../Packages/SwiftfinMediaTracks"),
        .package(path: "../Packages/SwiftfinUserMediaState"),
        .package(path: "../Packages/SwiftfinTime"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0")
    ],
    targets: [
        .executableTarget(name: "KidsStateTool", dependencies: [
            .product(name: "KidsDomain", package: "KidsDomain"),
            .product(name: "KidsPersistence", package: "KidsPersistence")
        ]),
        .testTarget(name: "KidsIntegrationTests", dependencies: [
            .product(name: "KidsDomain", package: "KidsDomain"),
            .product(name: "KidsPersistence", package: "KidsPersistence"),
            .product(name: "KidsPlayback", package: "KidsPlayback"),
            .product(name: "SwiftfinItemMetadata", package: "SwiftfinItemMetadata"),
            .product(name: "SwiftfinMediaCatalog", package: "SwiftfinMediaCatalog"),
            .product(name: "SwiftfinMediaTracks", package: "SwiftfinMediaTracks"),
            .product(name: "SwiftfinUserMediaState", package: "SwiftfinUserMediaState"),
            .product(name: "SwiftfinTime", package: "SwiftfinTime"),
            .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift")
        ], resources: [.process("Fixtures")])
    ]
)
