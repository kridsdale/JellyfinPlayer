// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinStorage",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinStorage", targets: ["SwiftfinStorage"])],
    dependencies: [.package(url: "https://github.com/JohnEstropia/CoreStore.git", exact: "9.2.0")],
    targets: [
        .target(name: "SwiftfinStorage", dependencies: [.product(name: "CoreStore", package: "CoreStore")]),
        .testTarget(
            name: "SwiftfinStorageTests",
            dependencies: ["SwiftfinStorage", .product(name: "CoreStore", package: "CoreStore")]
        )
    ]
)
