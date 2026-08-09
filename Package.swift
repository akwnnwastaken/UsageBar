// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UsageBar", targets: ["UsageBar"]),
        .library(name: "UsageBarCore", targets: ["UsageBarCore"]),
        .library(name: "UsageBarLocalAPI", targets: ["UsageBarLocalAPI"])
    ],
    targets: [
        .target(
            name: "UsageBarCore"
        ),
        .target(
            name: "UsageBarProcessLauncher",
            publicHeadersPath: "include"
        ),
        .target(
            name: "UsageBarLocalAPI",
            dependencies: ["UsageBarCore"]
        ),
        .executableTarget(
            name: "UsageBar",
            dependencies: ["UsageBarCore", "UsageBarLocalAPI", "UsageBarProcessLauncher"],
            path: "Sources/UsageBar"
        ),
        .testTarget(
            name: "UsageBarCoreTests",
            dependencies: ["UsageBarCore"]
        ),
        .testTarget(
            name: "UsageBarLocalAPITests",
            dependencies: ["UsageBarLocalAPI", "UsageBarCore"]
        )
    ]
)
