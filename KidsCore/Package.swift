// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsCore",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [
        .library(name: "KidsCore", targets: ["KidsCore"]),
        .library(name: "KidsPersistence", targets: ["KidsPersistence"]),
        .executable(name: "KidsStateTool", targets: ["KidsStateTool"])
    ],
    targets: [
        .target(name: "KidsCore"),
        .target(name: "KidsPersistence", dependencies: ["KidsCore"]),
        .executableTarget(name: "KidsStateTool", dependencies: ["KidsCore", "KidsPersistence"]),
        .testTarget(name: "KidsCoreTests", dependencies: ["KidsCore"]),
        .testTarget(name: "KidsPersistenceTests", dependencies: ["KidsPersistence", "KidsCore"])
    ]
)
