// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinFormatting",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinFormatting", targets: ["SwiftfinFormatting"])],
    dependencies: [.package(path: "../SwiftfinValues"), .package(path: "../SwiftfinLocalization")],
    targets: [
        .target(
            name: "SwiftfinFormatting",
            dependencies: [
                .product(name: "SwiftfinValues", package: "SwiftfinValues"),
                .product(name: "SwiftfinLocalization", package: "SwiftfinLocalization")
            ]
        ),
        .testTarget(
            name: "SwiftfinFormattingTests",
            dependencies: ["SwiftfinFormatting", .product(name: "SwiftfinLocalization", package: "SwiftfinLocalization")],
            resources: [.process("Fixtures")]
        )
    ]
)
