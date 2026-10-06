// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinUIState",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinUIState", targets: ["SwiftfinUIState"])],
    targets: [
        .target(name: "SwiftfinUIState"),
        .testTarget(name: "SwiftfinUIStateTests", dependencies: ["SwiftfinUIState"])
    ]
)
