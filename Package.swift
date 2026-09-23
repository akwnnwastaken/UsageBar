// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [
        .macOS(.v13),
        // The iPhone companion reuses UsageBarSync rather than growing a second
        // implementation of schema v1. UsageBarCore and UsageBarSync import
        // only Foundation and CoreGraphics (CGFloat/CGPoint/CGRect), all of
        // which exist on iOS, so this declaration adds a platform without
        // changing a line of macOS behaviour. The desktop-only targets --
        // UsageBar, UsageBarProcessLauncher, UsageBarSyncTransport and
        // UsageBarMobileSyncHost -- are simply never built for iOS.
        //
        // Spelled as a version string rather than `.iOS(.v18)`: the enum case
        // requires swift-tools-version 6.0, and bumping the manifest would move
        // the whole package into the Swift 6 language mode. That is a change to
        // how the macOS targets compile, which this integration must not make.
        .iOS("18.0")
    ],
    products: [
        .executable(name: "UsageBar", targets: ["UsageBar"]),
        .library(name: "UsageBarCore", targets: ["UsageBarCore"]),
        // The mobile sync boundary: one schema-v1 model, validator and
        // serializer, shared by the Mac host and the iPhone app.
        .library(name: "UsageBarSync", targets: ["UsageBarSync"]),
        .library(name: "UsageBarSyncTransport", targets: ["UsageBarSyncTransport"]),
        // Shared by the Mac and the iPhone app: one implementation of the
        // pairing wire format, so a QR the Mac writes and a QR the phone reads
        // cannot drift apart.
        .library(name: "UsageBarPairing", targets: ["UsageBarPairing"]),
        .library(name: "UsageBarMobileSyncHost", targets: ["UsageBarMobileSyncHost"])
    ],
    targets: [
        .target(
            name: "UsageBarCore"
        ),
        .target(
            name: "UsageBarSync",
            dependencies: ["UsageBarCore"]
        ),
        .target(
            name: "UsageBarSyncTransport",
            dependencies: ["UsageBarSync"]
        ),
        // Foundation only, so it builds for iOS as well as macOS.
        .target(
            name: "UsageBarPairing"
        ),
        // Mobile Sync: live snapshot publication, long-lived mobile
        // authentication, one-time pairing and the listener lifecycle.
        //
        // Separated from the UsageBar executable on purpose. Authentication,
        // Keychain access and transport lifecycle are the parts most worth
        // testing, and none of them can be tested inside an AppKit
        // `main.swift`. The executable depends on this; nothing here depends
        // on the executable.
        //
        // Linking it is not the same as running it: MobileSyncIdentity gates
        // every entry point on the running bundle identifier, and the
        // preference it reads defaults to off.
        .target(
            name: "UsageBarMobileSyncHost",
            dependencies: ["UsageBarCore", "UsageBarSync", "UsageBarSyncTransport", "UsageBarPairing"]
        ),
        .target(
            name: "UsageBarProcessLauncher",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "UsageBar",
            dependencies: [
                "UsageBarCore",
                "UsageBarPairing",
                "UsageBarProcessLauncher",
                "UsageBarMobileSyncHost"
            ],
            path: "Sources/UsageBar"
        ),
        .testTarget(
            name: "UsageBarCoreTests",
            dependencies: ["UsageBarCore"]
        ),
        .testTarget(
            name: "UsageBarSyncTests",
            dependencies: ["UsageBarSync"]
        ),
        .testTarget(
            name: "UsageBarSyncTransportTests",
            dependencies: ["UsageBarSyncTransport"]
        ),
        .testTarget(
            name: "UsageBarPairingTests",
            dependencies: ["UsageBarPairing"]
        ),
        .testTarget(
            name: "UsageBarMobileSyncHostTests",
            dependencies: ["UsageBarMobileSyncHost"]
        )
    ]
)
