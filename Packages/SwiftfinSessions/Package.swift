// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftfinSessions",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "SwiftfinSessions", targets: ["SwiftfinSessions"])],
    dependencies: [.package(path: "../SwiftfinAsyncStreams")],
    targets: [
        .target(name: "SwiftfinSessions", dependencies: ["SwiftfinAsyncStreams"]),
        .testTarget(name: "SwiftfinSessionsTests", dependencies: ["SwiftfinSessions"])
    ]
)
