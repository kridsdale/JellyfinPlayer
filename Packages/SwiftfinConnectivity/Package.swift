// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinConnectivity",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinConnectivity", targets: ["SwiftfinConnectivity"])],
    dependencies: [.package(path: "../SwiftfinAccountModels")],
    targets: [
        .target(name: "SwiftfinConnectivity", dependencies: [
            .product(name: "SwiftfinAccountModels", package: "SwiftfinAccountModels")
        ]),
        .testTarget(name: "SwiftfinConnectivityTests", dependencies: ["SwiftfinConnectivity"])
    ]
)
