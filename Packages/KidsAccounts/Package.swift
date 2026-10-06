// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KidsAccounts",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsAccounts", targets: ["KidsAccounts"])],
    dependencies: [.package(path: "../KidsDomain")],
    targets: [
        .target(name: "KidsAccounts", dependencies: [.product(name: "KidsDomain", package: "KidsDomain")]),
        .testTarget(name: "KidsAccountsTests", dependencies: ["KidsAccounts"])
    ]
)
