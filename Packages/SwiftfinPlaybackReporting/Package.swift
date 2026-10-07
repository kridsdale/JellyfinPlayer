// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinPlaybackReporting", platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinPlaybackReporting", targets: ["SwiftfinPlaybackReporting"])],
    dependencies: [
        .package(path: "../SwiftfinNetworking"),
        .package(path: "../SwiftfinAsyncStreams"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0"),
        .package(url: "https://github.com/kean/Get", exact: "2.2.1")
    ],
    targets: [
        .target(
            name: "SwiftfinPlaybackReporting",
            dependencies: [
                "SwiftfinNetworking", "SwiftfinAsyncStreams",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        ),
        .testTarget(
            name: "SwiftfinPlaybackReportingTests",
            dependencies: [
                "SwiftfinPlaybackReporting",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        )
    ]
)
