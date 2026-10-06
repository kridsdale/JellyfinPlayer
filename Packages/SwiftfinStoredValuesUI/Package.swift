// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinStoredValuesUI",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinStoredValuesUI", targets: ["SwiftfinStoredValuesUI"])],
    dependencies: [.package(path: "../SwiftfinStoredValues")],
    targets: [
        .target(
            name: "SwiftfinStoredValuesUI",
            dependencies: [.product(name: "SwiftfinStoredValues", package: "SwiftfinStoredValues")]
        ),
        .testTarget(
            name: "SwiftfinStoredValuesUITests",
            dependencies: [
                "SwiftfinStoredValuesUI",
                .product(name: "SwiftfinStoredValues", package: "SwiftfinStoredValues")
            ]
        )
    ]
)
