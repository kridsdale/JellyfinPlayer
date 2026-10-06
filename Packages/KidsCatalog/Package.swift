// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsCatalog",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsCatalog", targets: ["KidsCatalog"])],
    dependencies: [
        .package(path: "../KidsDomain"),
        .package(path: "../KidsDiagnostics")
    ],
    targets: [
        .target(
            name: "KidsCatalog",
            dependencies: [
                .product(name: "KidsDomain", package: "KidsDomain"),
                .product(name: "KidsDiagnostics", package: "KidsDiagnostics")
            ]
        ),
        .testTarget(name: "KidsCatalogTests", dependencies: ["KidsCatalog"])
    ]
)
