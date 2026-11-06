// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToreScan",
    platforms: [.iOS(.v17), .macOS(.v14), .visionOS(.v1)],
    products: [
        .library(name: "ToreScan", targets: ["ToreScan"]),
        .library(name: "ToreScanCore", targets: ["ToreScanCore"]),
    ],
    targets: [
        .target(name: "ToreScanCore"),
        .target(name: "ToreScan", dependencies: ["ToreScanCore"]),
        .testTarget(name: "ToreScanCoreTests", dependencies: ["ToreScanCore"]),
        .testTarget(name: "ToreScanTests", dependencies: ["ToreScan"]),
    ]
)
