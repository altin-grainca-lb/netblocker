// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetBlocker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "NetBlocker", path: "Sources/NetBlocker")
    ]
)
