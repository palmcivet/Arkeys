// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EditorKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EditorKit", targets: ["EditorKit"]),
    ],
    dependencies: [
        .package(path: "../KeymapCore"),
        .package(path: "../Targeting"),
    ],
    targets: [
        .target(name: "EditorKit", dependencies: ["KeymapCore", "Targeting"]),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit"]),
    ]
)
