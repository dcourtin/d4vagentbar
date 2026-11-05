// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "D4vAgentBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "D4vAgentBar",
            path: "Sources/D4vAgentBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "D4vAgentBarTests",
            dependencies: ["D4vAgentBar"],
            path: "Tests/D4vAgentBarTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
