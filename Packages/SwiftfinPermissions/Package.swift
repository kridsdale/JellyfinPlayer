// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinPermissions",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinPermissions", targets: ["SwiftfinPermissions"])],
    targets: [
        .target(name: "SwiftfinPermissions"),
        .testTarget(name: "SwiftfinPermissionsTests", dependencies: ["SwiftfinPermissions"])
    ]
)
