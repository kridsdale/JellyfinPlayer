// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsCore",
    platforms: [.macOS(.v13), .tvOS(.v17)],
    products: [.library(name: "KidsCore", targets: ["KidsCore"])],
    targets: [.target(name: "KidsCore"), .testTarget(name: "KidsCoreTests", dependencies: ["KidsCore"])]
)
