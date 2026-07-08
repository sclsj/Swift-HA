// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "NativeHA",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "NativeHACore",
            targets: ["NativeHACore"]
        ),
        .executable(
            name: "NativeHA",
            targets: ["NativeHA"]
        )
    ],
    targets: [
        .target(
            name: "NativeHACore",
            dependencies: []
        ),
        .executableTarget(
            name: "NativeHA",
            dependencies: ["NativeHACore"]
        ),
        .testTarget(
            name: "NativeHATests",
            dependencies: ["NativeHACore", "NativeHA"]
        )
    ]
)
