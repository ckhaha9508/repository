// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NestLauncher",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NestLauncher",
            path: "Sources/NestLauncher",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NestLauncherTests",
            dependencies: ["NestLauncher"],
            path: "Tests/NestLauncherTests"
        )
    ]
)
