// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinAccountModels",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinAccountModels", targets: ["SwiftfinAccountModels"])],
    dependencies: [.package(path: "../SwiftfinLocalization")],
    targets: [
        .target(
            name: "SwiftfinAccountModels",
            dependencies: [.product(name: "SwiftfinLocalization", package: "SwiftfinLocalization")]
        ),
        .testTarget(name: "SwiftfinAccountModelsTests", dependencies: ["SwiftfinAccountModels"], resources: [.process("Fixtures")])
    ]
)
