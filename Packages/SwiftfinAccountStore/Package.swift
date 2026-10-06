// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinAccountStore",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinAccountStore", targets: ["SwiftfinAccountStore"])],
    dependencies: [
        .package(path: "../SwiftfinAccountModels"),
        .package(path: "../SwiftfinStorage"),
        .package(path: "../SwiftfinStoredValues"),
        .package(path: "../SwiftfinCredentials")
    ],
    targets: [
        .target(name: "SwiftfinAccountStore", dependencies: [
            "SwiftfinAccountModels", "SwiftfinStorage", "SwiftfinStoredValues", "SwiftfinCredentials"
        ]),
        .testTarget(name: "SwiftfinAccountStoreTests", dependencies: [
            "SwiftfinAccountStore", "SwiftfinAccountModels", "SwiftfinStorage", "SwiftfinStoredValues", "SwiftfinCredentials"
        ])
    ]
)
