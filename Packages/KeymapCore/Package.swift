// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeymapCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeymapCore", targets: ["KeymapCore"]),
    ],
    targets: [
        .target(name: "KeymapCore"),
        .testTarget(name: "KeymapCoreTests", dependencies: ["KeymapCore"]),
    ]
)
