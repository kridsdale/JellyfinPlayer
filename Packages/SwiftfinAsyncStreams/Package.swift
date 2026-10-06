// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinAsyncStreams",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinAsyncStreams", targets: ["SwiftfinAsyncStreams"])],
    targets: [
        .target(name: "SwiftfinAsyncStreams"),
        .testTarget(name: "SwiftfinAsyncStreamsTests", dependencies: ["SwiftfinAsyncStreams"])
    ]
)
