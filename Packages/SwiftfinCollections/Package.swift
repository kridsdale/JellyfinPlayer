// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinCollections",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinCollections", targets: ["SwiftfinCollections"])],
    targets: [.target(name: "SwiftfinCollections"), .testTarget(name: "SwiftfinCollectionsTests", dependencies: ["SwiftfinCollections"])]
)
