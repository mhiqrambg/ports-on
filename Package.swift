// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortsOn",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "PortsOn",
            path: "Sources/PortsOn"
        ),
        .testTarget(
            name: "PortsOnTests",
            dependencies: ["PortsOn"],
            path: "Tests/PortsOnTests"
        )
    ]
)
