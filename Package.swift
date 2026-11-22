// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Platewise",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Platewise",
            path: "Sources/Platewise",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
            ]
        )
    ]
)
