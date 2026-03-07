// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipForge",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClipForge",
            path: "Sources/ClipForge",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
