// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinConnections",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinConnections", targets: ["SwiftfinConnections"])],
    dependencies: [.package(path: "../SwiftfinAccountModels")],
    targets: [
        .target(name: "SwiftfinConnections", dependencies: ["SwiftfinAccountModels"]),
        .testTarget(name: "SwiftfinConnectionsTests", dependencies: ["SwiftfinConnections", "SwiftfinAccountModels"])
    ]
)
