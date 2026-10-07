// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KidsAccounts",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsAccounts", targets: ["KidsAccounts"])],
    dependencies: [.package(path: "../KidsDomain"), .package(path: "../SwiftfinAsyncStreams")],
    targets: [
        .target(name: "KidsAccounts", dependencies: [
            .product(name: "KidsDomain", package: "KidsDomain"),
            .product(name: "SwiftfinAsyncStreams", package: "SwiftfinAsyncStreams")
        ]),
        .testTarget(name: "KidsAccountsTests", dependencies: ["KidsAccounts"])
    ]
)
