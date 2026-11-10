// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WExplorer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WExplorer", path: "Sources/WExplorer", exclude: ["Localization/README.md"])
    ]
)
