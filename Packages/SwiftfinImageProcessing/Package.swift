// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinImageProcessing",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinImageProcessing", targets: ["SwiftfinImageProcessing"])],
    targets: [
        .target(name: "SwiftfinImageProcessing"),
        .testTarget(name: "SwiftfinImageProcessingTests", dependencies: ["SwiftfinImageProcessing"], resources: [.process("Fixtures")])
    ]
)
