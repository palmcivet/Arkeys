// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeymapPlayCover",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeymapPlayCover", targets: ["KeymapPlayCover"]),
    ],
    dependencies: [
        .package(path: "../KeymapCore"),
    ],
    targets: [
        .target(name: "KeymapPlayCover", dependencies: ["KeymapCore"]),
        .testTarget(
            name: "KeymapPlayCoverTests",
            dependencies: ["KeymapPlayCover"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
