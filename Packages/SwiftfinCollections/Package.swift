// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinCollections",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinCollections", targets: ["SwiftfinCollections"])],
    dependencies: [.package(url: "https://github.com/apple/swift-collections.git", exact: "1.6.0")],
    targets: [
        .target(name: "SwiftfinCollections", dependencies: [.product(name: "OrderedCollections", package: "swift-collections")]),
        .testTarget(
            name: "SwiftfinCollectionsTests",
            dependencies: ["SwiftfinCollections", .product(name: "OrderedCollections", package: "swift-collections")]
        )
    ]
)
