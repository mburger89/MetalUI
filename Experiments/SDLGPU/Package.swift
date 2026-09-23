// swift-tools-version: 6.4
import PackageDescription

// The Apple half: draws fixtures with the production Metal renderer, compares
// SDL live, and records fixtures for Portable/, which builds without MetalUI.
let package = Package(
    name: "SDLGPUExperiment",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "MetalUI", path: "../.."),
        .package(name: "MetalUISDL", path: "../../Backends/SDL")
    ],
    targets: [
        .executableTarget(name: "Replay", dependencies: [
            .product(name: "SDLReplay", package: "MetalUISDL"),
            .product(name: "ReplayFixture", package: "MetalUISDL"),
            .product(name: "MetalUI", package: "MetalUI"),
            // Frame 4's text (ruling PT-G): HarfBuzz + FreeType, no CoreText.
            .product(name: "MetalUIPortableText", package: "MetalUI"),
            .product(name: "MetalUIDemoContent", package: "MetalUI")
        ])
    ]
)
