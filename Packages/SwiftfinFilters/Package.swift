// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinFilters",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinFilters", targets: ["SwiftfinFilters"])],
    dependencies: [
        .package(path: "../SwiftfinNetworking"), .package(path: "../SwiftfinMediaCatalog"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0"),
        .package(url: "https://github.com/kean/Get", exact: "2.2.1")
    ],
    targets: [
        .target(
            name: "SwiftfinFilters",
            dependencies: ["SwiftfinNetworking", "SwiftfinMediaCatalog", .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift")]
        ),
        .testTarget(
            name: "SwiftfinFiltersTests",
            dependencies: [
                "SwiftfinFilters",
                "SwiftfinNetworking",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get")
            ]
        )
    ]
)
