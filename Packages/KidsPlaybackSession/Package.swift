// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KidsPlaybackSession",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsPlaybackSession", targets: ["KidsPlaybackSession"])],
    dependencies: [.package(path: "../KidsDomain"), .package(path: "../KidsPlayback"), .package(path: "../KidsDiagnostics")],
    targets: [
        .target(name: "KidsPlaybackSession", dependencies: ["KidsDomain", "KidsPlayback", "KidsDiagnostics"]),
        .testTarget(name: "KidsPlaybackSessionTests", dependencies: ["KidsPlaybackSession", "KidsDomain"])
    ]
)
