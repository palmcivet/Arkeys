// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputRuntime",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InputRuntime", targets: ["InputRuntime"]),
    ],
    dependencies: [
        .package(path: "../KeymapCore"),
        .package(path: "../Injection"),
        .package(path: "../Targeting"),
    ],
    targets: [
        .target(
            name: "InputRuntime",
            dependencies: ["KeymapCore", "Injection", "Targeting"]
        ),
    ]
)
