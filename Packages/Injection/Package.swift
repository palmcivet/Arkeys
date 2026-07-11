// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Injection",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Injection", targets: ["Injection"]),
    ],
    dependencies: [
        .package(path: "../Targeting"),
    ],
    targets: [
        .target(name: "Injection", dependencies: ["Targeting"]),
    ]
)
