// swift-tools-version: 6.0
import PackageDescription

/// ControlCenterKit — everything the Mac helper, the iPad/iPhone app and the
/// widget extension share: the wire protocol, the models, the context engine
/// and the crypto. No third-party dependencies.
let package = Package(
    name: "ControlCenterKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CCCore", targets: ["CCCore"]),
        .library(name: "CCNet", targets: ["CCNet"]),
    ],
    targets: [
        .target(name: "CCCore"),
        .target(name: "CCNet", dependencies: ["CCCore"]),
        .testTarget(name: "CCCoreTests", dependencies: ["CCCore"]),
        .testTarget(name: "CCNetTests", dependencies: ["CCNet", "CCCore"]),
    ]
)
