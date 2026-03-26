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
    targets: [
        .target(
            name: "SlickShotCore"
        ),
        .executableTarget(
            name: "SlickShotApp",
            dependencies: ["SlickShotCore"],
            linkerSettings: [
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
