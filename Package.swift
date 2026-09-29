// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bartrans",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "bartrans",
            path: "Sources/bartrans",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
