// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LiveWall",
    platforms: [.macOS(.v14)],
    targets: [
        // Decisions with no UI or system access, so they can be tested directly.
        .target(name: "LiveWallCore", path: "Sources/LiveWallCore"),
        .executableTarget(name: "LiveWall", dependencies: ["LiveWallCore"], path: "Sources/LiveWall"),
        .testTarget(name: "LiveWallCoreTests", dependencies: ["LiveWallCore"], path: "Tests/LiveWallCoreTests"),
    ]
)
