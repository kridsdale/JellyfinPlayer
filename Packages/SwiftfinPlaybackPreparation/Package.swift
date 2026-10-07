// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinPlaybackPreparation", platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinPlaybackPreparation", targets: ["SwiftfinPlaybackPreparation"])],
    dependencies: [
        .package(path: "../SwiftfinNetworking"),
        .package(path: "../SwiftfinPlaybackReporting"),
        .package(path: "../SwiftfinMediaTracks"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0"),
        .package(url: "https://github.com/kean/Get", exact: "2.2.1")
    ],
    targets: [
        .target(
            name: "SwiftfinPlaybackPreparation",
            dependencies: [
                "SwiftfinNetworking",
                "SwiftfinPlaybackReporting",
                "SwiftfinMediaTracks",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        ),
        .testTarget(
            name: "SwiftfinPlaybackPreparationTests",
            dependencies: [
                "SwiftfinPlaybackPreparation",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        )
    ]
)
