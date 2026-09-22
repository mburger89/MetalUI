// swift-tools-version: 6.4
import PackageDescription

// The Apple half: draws fixtures with the production Metal renderer, compares
// SDL live, and records fixtures for Portable/, which builds without MetalUI.
let package = Package(
    name: "SDLGPUExperiment",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "MetalUI", path: "../.."),
        .package(name: "SDLGPUPortable", path: "Portable")
    ],
    targets: [
        .executableTarget(name: "Replay", dependencies: [
            .product(name: "SDLBridge", package: "SDLGPUPortable"),
            .product(name: "ReplayFixture", package: "SDLGPUPortable"),
            .product(name: "MetalUI", package: "MetalUI")
        ])
    ]
)
