// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Targeting",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Targeting", targets: ["Targeting"]),
    ],
    targets: [
        .target(name: "Targeting"),
    ]
)
