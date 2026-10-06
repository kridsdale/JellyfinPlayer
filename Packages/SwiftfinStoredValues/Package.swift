// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinStoredValues",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinStoredValues", targets: ["SwiftfinStoredValues"])],
    dependencies: [
        .package(path: "../SwiftfinStorage"),
        .package(url: "https://github.com/sindresorhus/Defaults", exact: "9.0.9")
    ],
    targets: [
        .target(
            name: "SwiftfinStoredValues",
            dependencies: [
                .product(name: "SwiftfinStorage", package: "SwiftfinStorage"),
                .product(name: "Defaults", package: "Defaults")
            ]
        ),
        .testTarget(
            name: "SwiftfinStoredValuesTests",
            dependencies: [
                "SwiftfinStoredValues",
                .product(name: "SwiftfinStorage", package: "SwiftfinStorage"),
                .product(name: "Defaults", package: "Defaults")
            ]
        )
    ]
)
