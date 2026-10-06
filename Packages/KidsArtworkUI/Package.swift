// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KidsArtworkUI",
    platforms: [.iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsArtworkUI", targets: ["KidsArtworkUI"])],
    dependencies: [
        .package(path: "../KidsDomain"),
        .package(path: "../KidsCatalog"),
        .package(path: "../KidsDiagnostics"),
        .package(path: "../KidsArtwork")
    ],
    targets: [.target(name: "KidsArtworkUI", dependencies: [
        .product(name: "KidsDomain", package: "KidsDomain"),
        .product(name: "KidsCatalog", package: "KidsCatalog"),
        .product(name: "KidsDiagnostics", package: "KidsDiagnostics"),
        .product(name: "KidsArtwork", package: "KidsArtwork")
    ])]
)
