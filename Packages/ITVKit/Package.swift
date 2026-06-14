// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ITVKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ITVKit", targets: ["ITVKit"]),
    ],
    targets: [
        .target(
            name: "ITVKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ITVKitTests",
            dependencies: ["ITVKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
