// swift-tools-version: 6.0
import PackageDescription

// Development-only state tool and cross-package integration checks.
let package = Package(
    name: "KidsValidationTools",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [.executable(name: "KidsStateTool", targets: ["KidsStateTool"])],
    dependencies: [
        .package(path: "../Packages/KidsDomain"),
        .package(path: "../Packages/KidsPersistence"),
        .package(path: "../Packages/KidsPlayback")
    ],
    targets: [
        .executableTarget(name: "KidsStateTool", dependencies: [
            .product(name: "KidsDomain", package: "KidsDomain"),
            .product(name: "KidsPersistence", package: "KidsPersistence")
        ]),
        .testTarget(name: "KidsIntegrationTests", dependencies: [
            .product(name: "KidsDomain", package: "KidsDomain"),
            .product(name: "KidsPersistence", package: "KidsPersistence"),
            .product(name: "KidsPlayback", package: "KidsPlayback")
        ])
    ]
)
