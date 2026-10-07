// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinItemMetadata", platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinItemMetadata", targets: ["SwiftfinItemMetadata"])],
    dependencies: [
        .package(path: "../SwiftfinNetworking"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0"),
        .package(url: "https://github.com/kean/Get", exact: "2.2.1")
    ],
    targets: [
        .target(
            name: "SwiftfinItemMetadata",
            dependencies: [
                "SwiftfinNetworking",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        ),
        .testTarget(
            name: "SwiftfinItemMetadataTests",
            dependencies: [
                "SwiftfinItemMetadata",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        )
    ]
)
