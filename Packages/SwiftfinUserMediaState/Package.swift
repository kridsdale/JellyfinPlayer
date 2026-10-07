// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinUserMediaState", platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinUserMediaState", targets: ["SwiftfinUserMediaState"])],
    dependencies: [
        .package(path: "../SwiftfinNetworking"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0"),
        .package(url: "https://github.com/kean/Get", exact: "2.2.1")
    ],
    targets: [
        .target(
            name: "SwiftfinUserMediaState",
            dependencies: [
                "SwiftfinNetworking",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        ),
        .testTarget(
            name: "SwiftfinUserMediaStateTests",
            dependencies: [
                "SwiftfinUserMediaState",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        )
    ]
)
