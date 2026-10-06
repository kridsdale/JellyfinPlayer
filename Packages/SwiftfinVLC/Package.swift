// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinVLC",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18)],
    products: [.library(name: "SwiftfinVLC", targets: ["SwiftfinVLC"])],
    dependencies: [
        .package(path: "../KidsDiagnostics"),
        .package(url: "https://github.com/harflabs/SwiftVLC", exact: "1.0.0")
    ],
    targets: [
        .target(name: "SwiftfinVLC", dependencies: [
            .product(name: "KidsDiagnostics", package: "KidsDiagnostics"),
            .product(name: "SwiftVLC", package: "SwiftVLC")
        ]),
        .testTarget(name: "SwiftfinVLCTests", dependencies: ["SwiftfinVLC"])
    ]
)
