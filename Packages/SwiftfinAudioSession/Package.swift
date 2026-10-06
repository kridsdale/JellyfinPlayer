// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinAudioSession",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinAudioSession", targets: ["SwiftfinAudioSession"])],
    dependencies: [.package(path: "../KidsDiagnostics")],
    targets: [
        .target(name: "SwiftfinAudioSession", dependencies: [.product(name: "KidsDiagnostics", package: "KidsDiagnostics")]),
        .testTarget(name: "SwiftfinAudioSessionTests", dependencies: ["SwiftfinAudioSession"])
    ]
)
