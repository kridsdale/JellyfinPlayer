// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinAccountStore",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinAccountStore", targets: ["SwiftfinAccountStore"])],
    dependencies: [
        .package(path: "../SwiftfinAccountModels"),
        .package(path: "../SwiftfinStorage"),
        .package(path: "../SwiftfinStoredValues"),
        .package(path: "../SwiftfinCredentials"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.2.0"),
        .package(url: "https://github.com/sindresorhus/Defaults", exact: "9.0.9")
    ],
    targets: [
        .target(name: "SwiftfinAccountStore", dependencies: [
            "SwiftfinAccountModels", "SwiftfinStorage", "SwiftfinStoredValues", "SwiftfinCredentials",
            .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
            .product(name: "Defaults", package: "Defaults")
        ]),
        .testTarget(name: "SwiftfinAccountStoreTests", dependencies: [
            "SwiftfinAccountStore", "SwiftfinAccountModels", "SwiftfinStorage", "SwiftfinStoredValues", "SwiftfinCredentials",
            .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
            .product(name: "Defaults", package: "Defaults")
        ])
    ]
)
