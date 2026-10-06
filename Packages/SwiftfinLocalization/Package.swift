// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinLocalization",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinLocalization", targets: ["SwiftfinLocalization"])],
    targets: [
        .target(name: "SwiftfinLocalization", resources: [.process("Resources")], plugins: [.plugin(name: "GenerateLocalizedStrings")]),
        .executableTarget(name: "LocalizationCodegen", path: "Tools/LocalizationCodegen"),
        .plugin(name: "GenerateLocalizedStrings", capability: .buildTool(), dependencies: ["LocalizationCodegen"]),
        .testTarget(name: "SwiftfinLocalizationTests", dependencies: ["SwiftfinLocalization"])
    ]
)
