// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplatThatMoji",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SplatThatMoji", targets: ["SplatThatMoji"]),
        .library(name: "KaomojiKit", targets: ["KaomojiKit"]),
    ],
    targets: [
        // Database loading and search. No AppKit, so it's easy to test.
        .target(name: "KaomojiKit"),
        // The menu bar app: hotkey, picker panel, insertion, settings.
        .executableTarget(
            name: "SplatThatMoji",
            dependencies: ["KaomojiKit"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "KaomojiKitTests", dependencies: ["KaomojiKit"]),
    ]
)
