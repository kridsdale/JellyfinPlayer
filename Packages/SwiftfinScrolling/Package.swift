// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinScrolling",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinScrolling", targets: ["SwiftfinScrolling"])],
    targets: [
        .target(name: "SwiftfinScrolling"),
        .testTarget(name: "SwiftfinScrollingTests", dependencies: ["SwiftfinScrolling"])
    ]
)
