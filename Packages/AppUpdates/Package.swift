// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppUpdates",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppUpdates", targets: ["AppUpdates"]),
    ],
    targets: [
        .target(name: "AppUpdates"),
        .testTarget(name: "AppUpdatesTests", dependencies: ["AppUpdates"]),
    ]
)
