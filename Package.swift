// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "maccafe",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "maccafe",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit")]
        ),
        .testTarget(name: "maccafeTests", dependencies: ["maccafe"]),
    ]
)
