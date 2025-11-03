// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SKManager",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SKManager",
            targets: ["SKManager"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/markbattistella/SimpleLogger", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "SKManager",
            dependencies: ["SimpleLogger"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
