// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinText",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinText", targets: ["SwiftfinText"])],
    targets: [
        .target(name: "SwiftfinText"),
        .testTarget(name: "SwiftfinTextTests", dependencies: ["SwiftfinText"])
    ]
)
