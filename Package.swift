// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MtoG",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MtoGMac", targets: ["MtoGMac"]),
        .executable(name: "MtoGExternalDisplayWorker", targets: ["MtoGExternalDisplayWorker"])
    ],
    targets: [
        .executableTarget(
            name: "MtoGMac",
            path: "Sources/MtoGMac"
        ),
        .executableTarget(
            name: "MtoGExternalDisplayWorker",
            path: "Sources/MtoGExternalDisplayWorker"
        )
    ]
)
