// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SlickShot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SlickShotApp", targets: ["SlickShotApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "SlickShotCore"
        ),
        .executableTarget(
            name: "SlickShotApp",
            dependencies: [
                "SlickShotCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "SlickShotAppTests",
            dependencies: ["SlickShotApp", "SlickShotCore"]
        ),
        .testTarget(
            name: "SlickShotCoreTests",
            dependencies: ["SlickShotApp", "SlickShotCore"]
        )
    ]
)
