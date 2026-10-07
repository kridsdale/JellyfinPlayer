// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinMediaCatalog",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinMediaCatalog", targets: ["SwiftfinMediaCatalog"])],
    dependencies: [
        .package(path: "../SwiftfinNetworking"), .package(path: "../SwiftfinCollections"), .package(path: "../SwiftfinTime"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0"),
        .package(url: "https://github.com/kean/Get", exact: "2.2.1")
    ],
    targets: [
        .target(
            name: "SwiftfinMediaCatalog",
            dependencies: [
                "SwiftfinNetworking",
                "SwiftfinCollections",
                "SwiftfinTime",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        ),
        .testTarget(
            name: "SwiftfinMediaCatalogTests",
            dependencies: [
                "SwiftfinMediaCatalog",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ],
            resources: [.process("Fixtures")]
        )
    ]
)
