// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SDLGPUExperiment",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "MetalUI", path: "../..")],
    targets: [
        .systemLibrary(name: "CSDL", pkgConfig: "sdl3", providers: [.brew(["sdl3"])]),
        .target(name: "SDLBridge", dependencies: ["CSDL"]),
        .executableTarget(name: "Replay", dependencies: [
            "SDLBridge", .product(name: "MetalUI", package: "MetalUI")
        ])
    ]
)
