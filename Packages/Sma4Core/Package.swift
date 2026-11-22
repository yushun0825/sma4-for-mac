// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sma4Core",
    defaultLocalization: "ja",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Sma4Core", targets: ["Sma4Core"]),
        .executable(name: "sma4render", targets: ["sma4render"]),
    ],
    targets: [
        .target(name: "Sma4Core"),
        .executableTarget(name: "sma4render", dependencies: ["Sma4Core"]),
        .testTarget(
            name: "Sma4CoreTests",
            dependencies: ["Sma4Core"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
