// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsDomain",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsDomain", targets: ["KidsDomain"])],
    dependencies: [

    ],
    targets: [
        .target(name: "KidsDomain", dependencies: []),
        .testTarget(name: "KidsDomainTests", dependencies: ["KidsDomain"])
    ]
)
