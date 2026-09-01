// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MtoG",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MtoGCore", targets: ["MtoGCore"]),
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
        .executableTarget(
            name: "MtoGMac",
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
        )
    ]
)
