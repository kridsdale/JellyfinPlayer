// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinStoredValues",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinStoredValues", targets: ["SwiftfinStoredValues"])],
    dependencies: [
        .package(path: "../SwiftfinAccountModels"),
        .package(path: "../SwiftfinStorage"),
        .package(path: "../SwiftfinPlaybackProfiles"),
        .package(url: "https://github.com/sindresorhus/Defaults", exact: "9.0.9")
    ],
    targets: [
        .target(
            name: "SwiftfinStoredValues",
            dependencies: [
                .product(name: "SwiftfinAccountModels", package: "SwiftfinAccountModels"),
                .product(name: "SwiftfinStorage", package: "SwiftfinStorage"),
                .product(name: "SwiftfinPlaybackProfiles", package: "SwiftfinPlaybackProfiles"),
                .product(name: "Defaults", package: "Defaults")
            ]
        ),
        .testTarget(
            name: "SwiftfinStoredValuesTests",
            dependencies: [
                "SwiftfinStoredValues",
                .product(name: "SwiftfinAccountModels", package: "SwiftfinAccountModels"),
                .product(name: "SwiftfinStorage", package: "SwiftfinStorage"),
                .product(name: "SwiftfinPlaybackProfiles", package: "SwiftfinPlaybackProfiles"),
                .product(name: "Defaults", package: "Defaults")
            ]
        )
    ]
)
