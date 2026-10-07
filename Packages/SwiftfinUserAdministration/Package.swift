// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinUserAdministration", platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinUserAdministration", targets: ["SwiftfinUserAdministration"])],
    dependencies: [
        .package(path: "../SwiftfinNetworking"), .package(path: "../SwiftfinCollections"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0"),
        .package(url: "https://github.com/kean/Get", exact: "2.2.1")
    ],
    targets: [
        .target(
            name: "SwiftfinUserAdministration",
            dependencies: [
                "SwiftfinNetworking",
                "SwiftfinCollections",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        ),
        .testTarget(
            name: "SwiftfinUserAdministrationTests",
            dependencies: [
                "SwiftfinUserAdministration",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        )
    ]
)
