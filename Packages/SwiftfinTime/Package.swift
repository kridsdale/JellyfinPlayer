// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinTime",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinTime", targets: ["SwiftfinTime"])],
    dependencies: [],
    targets: [
        .target(name: "SwiftfinTime", dependencies: []),
        .testTarget(name: "SwiftfinTimeTests", dependencies: ["SwiftfinTime"])
    ]
)
