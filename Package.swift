// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PocketOllama",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PocketOllamaCore",
            targets: ["PocketOllamaCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PocketOllamaCore",
            path: "PocketOllama",
            exclude: ["Resources/Info.plist", "Resources/PocketOllama.entitlements"],
            swiftSettings: [
                .define("GGML_USE_METAL"),
                .define("SWIFT_PACKAGE")
            ]
        ),
        .testTarget(
            name: "PocketOllamaTests",
            dependencies: ["PocketOllamaCore"]
        ),
    ]
)
