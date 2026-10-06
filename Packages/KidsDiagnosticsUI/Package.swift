// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KidsDiagnosticsUI",
    platforms: [.iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "KidsDiagnosticsUI", targets: ["KidsDiagnosticsUI"])],
    dependencies: [.package(path: "../KidsDiagnostics")],
    targets: [.target(name: "KidsDiagnosticsUI", dependencies: [.product(name: "KidsDiagnostics", package: "KidsDiagnostics")])]
)
