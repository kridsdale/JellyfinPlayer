// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinImageProcessing",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinImageProcessing", targets: ["SwiftfinImageProcessing"])],
    dependencies: [
        .package(url: "https://github.com/SVGKit/SVGKit", exact: "3.0.0"),
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", exact: "3.9.1")
    ],
    targets: [
        .target(name: "SwiftfinImageProcessing", dependencies: [
            .product(name: "SVGKit", package: "SVGKit", condition: .when(platforms: [.iOS, .tvOS])),
            .product(name: "CocoaLumberjack", package: "CocoaLumberjack", condition: .when(platforms: [.iOS, .tvOS]))
        ]),
        .testTarget(name: "SwiftfinImageProcessingTests", dependencies: ["SwiftfinImageProcessing"], resources: [.process("Fixtures")])
    ]
)
