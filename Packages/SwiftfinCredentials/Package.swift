// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinCredentials",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinCredentials", targets: ["SwiftfinCredentials"])],
    targets: [
        .target(name: "SwiftfinCredentials"),
        .testTarget(name: "SwiftfinCredentialsTests", dependencies: ["SwiftfinCredentials"])
    ]
)
