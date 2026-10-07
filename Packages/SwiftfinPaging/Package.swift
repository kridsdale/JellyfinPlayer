// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinPaging",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinPaging", targets: ["SwiftfinPaging"])],
    targets: [
        .target(name: "SwiftfinPaging"),
        .testTarget(name: "SwiftfinPagingTests", dependencies: ["SwiftfinPaging"])
    ]
)
