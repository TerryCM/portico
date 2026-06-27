// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portico",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PorticoCore"),
        .executableTarget(
            name: "Portico",
            dependencies: ["PorticoCore"]
        ),
        .testTarget(
            name: "PorticoCoreTests",
            dependencies: ["PorticoCore"]
        ),
    ]
)
