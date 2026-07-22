// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UsageBar", targets: ["UsageBar"]),
        .library(name: "UsageBarCore", targets: ["UsageBarCore"])
    ],
    targets: [
        .target(
            name: "UsageBarCore"
        ),
        .executableTarget(
            name: "UsageBar",
            dependencies: ["UsageBarCore"],
            path: "Sources/UsageBar"
        ),
        .testTarget(
            name: "UsageBarCoreTests",
            dependencies: ["UsageBarCore"]
        )
    ]
)
