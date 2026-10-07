// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinMPV",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18)],
    products: [.library(name: "SwiftfinMPV", targets: ["SwiftfinMPV"])],
    dependencies: [.package(url: "https://github.com/LePips/MPVUI", exact: "0.1.1")],
    targets: [
        .target(name: "SwiftfinMPV", dependencies: [.product(name: "MPVUI", package: "MPVUI")]),
        .testTarget(name: "SwiftfinMPVTests", dependencies: ["SwiftfinMPV", .product(name: "MPVUI", package: "MPVUI")])
    ]
)
