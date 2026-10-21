// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LiveWall",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LiveWall",
            path: "Sources/LiveWall"
        )
    ]
)
