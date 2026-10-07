// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsPlayback",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsPlayback", targets: ["KidsPlayback"])],
    dependencies: [
        .package(path: "../KidsDiagnostics"),
        .package(path: "../SwiftfinAsyncStreams")
    ],
    targets: [
        .target(
            name: "KidsPlayback",
            dependencies: [
                .product(name: "KidsDiagnostics", package: "KidsDiagnostics"),
                .product(name: "SwiftfinAsyncStreams", package: "SwiftfinAsyncStreams")
            ]
        ),
        .testTarget(name: "KidsPlaybackTests", dependencies: ["KidsPlayback"])
    ]
)
