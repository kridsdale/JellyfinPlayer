// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinMediaTracks",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinMediaTracks", targets: ["SwiftfinMediaTracks"])],
    dependencies: [
        .package(path: "../SwiftfinPlaybackProfiles"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0")
    ],
    targets: [
        .target(name: "SwiftfinMediaTracks", dependencies: [
            .product(name: "SwiftfinPlaybackProfiles", package: "SwiftfinPlaybackProfiles"),
            .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift")
        ]),
        .testTarget(
            name: "SwiftfinMediaTracksTests",
            dependencies: [
                "SwiftfinMediaTracks",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "SwiftfinPlaybackProfiles", package: "SwiftfinPlaybackProfiles")
            ],
            resources: [.process("Fixtures")]
        )
    ]
)
