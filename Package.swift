// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bartrans",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "bartrans",
            path: "Sources/bartrans"
        )
    ]
)
