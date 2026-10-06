// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinNativePlayback",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinNativePlayback", targets: ["SwiftfinNativePlayback"])],
    targets: [
        .target(name: "SwiftfinNativePlayback"),
        .testTarget(name: "SwiftfinNativePlaybackTests", dependencies: ["SwiftfinNativePlayback"])
    ]
)
