// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinPlaybackPreviews",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinPlaybackPreviews", targets: ["SwiftfinPlaybackPreviews"])],
    targets: [
        .target(name: "SwiftfinPlaybackPreviews"),
        .testTarget(name: "SwiftfinPlaybackPreviewsTests", dependencies: ["SwiftfinPlaybackPreviews"], resources: [.process("Fixtures")])
    ]
)
