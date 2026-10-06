// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsArtwork",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsArtwork", targets: ["KidsArtwork"])],
    dependencies: [
        .package(path: "../KidsDomain"),
        .package(path: "../KidsCatalog"),
        .package(path: "../KidsDiagnostics")
    ],
    targets: [
        .target(
            name: "KidsArtwork",
            dependencies: [
                .product(name: "KidsDomain", package: "KidsDomain"),
                .product(name: "KidsCatalog", package: "KidsCatalog"),
                .product(name: "KidsDiagnostics", package: "KidsDiagnostics")
            ]
        ),
        .testTarget(name: "KidsArtworkTests", dependencies: ["KidsArtwork"])
    ]
)
