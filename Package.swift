// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MtoG",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MtoGCore", targets: ["MtoGCore"]),
        .library(name: "MtoGMedia", targets: ["MtoGMedia"]),
        .executable(name: "MtoGMac", targets: ["MtoGMac"]),
        .executable(name: "MtoGExternalDisplayWorker", targets: ["MtoGExternalDisplayWorker"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            exact: "0.12.0"
        )
    ],
    targets: [
        .testTarget(name: "MtoGMacTests", dependencies: ["MtoGMac", .product(name: "Testing", package: "swift-testing")]),
        .testTarget(name: "MtoGWorkerTests", dependencies: ["MtoGExternalDisplayWorker", "MtoGCore", .product(name: "Testing", package: "swift-testing")]),
        .executableTarget(name: "MtoGVideoBenchmark", dependencies: ["MtoGCore", "MtoGMedia"]),
        .target(name: "MtoGPlatform", dependencies: ["MtoGCore"]),
        .testTarget(name: "MtoGPlatformTests", dependencies: ["MtoGPlatform", .product(name: "Testing", package: "swift-testing")]),
        .target(
            name: "MtoGCore",
            path: "Sources/MtoGCore"
        ),
        .target(
            name: "MtoGMedia",
            dependencies: ["MtoGCore"],
            path: "Sources/MtoGMedia"
        ),
        .executableTarget(
            name: "MtoGMac",
            dependencies: ["MtoGCore", "MtoGPlatform"],
            path: "Sources/MtoGMac"
        ),
        .executableTarget(
            name: "MtoGExternalDisplayWorker",
            dependencies: ["MtoGCore", "MtoGMedia", "MtoGPlatform"],
            path: "Sources/MtoGExternalDisplayWorker"
        ),
        .testTarget(
            name: "MtoGCoreTests",
            dependencies: [
                "MtoGCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/MtoGCoreTests"
        ),
        .testTarget(
            name: "MtoGMediaTests",
            dependencies: [
                "MtoGCore",
                "MtoGMedia",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/MtoGMediaTests"
        )
    ]
)
