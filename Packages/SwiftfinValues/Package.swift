// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinValues",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinValues", targets: ["SwiftfinValues"])],
    dependencies: [],
    targets: [
        .target(name: "SwiftfinValues", dependencies: []),
        .testTarget(name: "SwiftfinValuesTests", dependencies: ["SwiftfinValues"])
    ]
)
