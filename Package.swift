// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoEditor",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "VideoEditor",
            path: "Sources/VideoEditor",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
