// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vinyl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Vinyl",
            path: "Sources/Vinyl",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
