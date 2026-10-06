// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinImages",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinImages", targets: ["SwiftfinImages"])],
    dependencies: [.package(url: "https://github.com/kean/Nuke", exact: "13.0.6")],
    targets: [
        .target(name: "SwiftfinImages", dependencies: [.product(name: "Nuke", package: "Nuke")]),
        .testTarget(name: "SwiftfinImagesTests", dependencies: ["SwiftfinImages", .product(name: "Nuke", package: "Nuke")])
    ]
)
