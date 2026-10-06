// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinPlaybackProfiles",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinPlaybackProfiles", targets: ["SwiftfinPlaybackProfiles"])],
    dependencies: [
        .package(path: "../SwiftfinCollections"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0")
    ],
    targets: [
        .target(name: "SwiftfinPlaybackProfiles", dependencies: [
            .product(name: "SwiftfinCollections", package: "SwiftfinCollections"),
            .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift")
        ]),
        .testTarget(
            name: "SwiftfinPlaybackProfilesTests",
            dependencies: ["SwiftfinPlaybackProfiles", .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift")],
            resources: [.process("Fixtures")]
        )
    ]
)
