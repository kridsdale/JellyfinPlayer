// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsDiagnostics",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsDiagnostics", targets: ["KidsDiagnostics"])],
    dependencies: [.package(path: "../KidsDomain")],
    targets: [
        .target(name: "KidsDiagnostics", dependencies: [.product(name: "KidsDomain", package: "KidsDomain")]),
        .testTarget(name: "KidsDiagnosticsTests", dependencies: ["KidsDiagnostics"])
    ]
)
