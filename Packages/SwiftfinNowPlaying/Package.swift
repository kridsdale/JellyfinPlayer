// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinNowPlaying",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinNowPlaying", targets: ["SwiftfinNowPlaying"])],
    targets: [
        .target(name: "SwiftfinNowPlaying"),
        .testTarget(name: "SwiftfinNowPlayingTests", dependencies: ["SwiftfinNowPlaying"])
    ]
)
