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
            dependencies: ["MtoGCore"],
            path: "Sources/MtoGMac"
        ),
        .executableTarget(
            name: "MtoGExternalDisplayWorker",
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
