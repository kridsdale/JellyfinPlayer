// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsPersistence",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsPersistence", targets: ["KidsPersistence"])],
    dependencies: [
        .package(path: "../KidsDomain"),
        .package(path: "../KidsDiagnostics")
    ],
    targets: [
        .target(
            name: "KidsPersistence",
            dependencies: [
                .product(name: "KidsDomain", package: "KidsDomain"),
                .product(name: "KidsDiagnostics", package: "KidsDiagnostics")
            ]
        ),
        .testTarget(name: "KidsPersistenceTests", dependencies: ["KidsPersistence"])
    ]
)
