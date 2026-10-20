// swift-tools-version: 6.0
// Throwaway harness for docs/probes/warm-settle/cold-profile.sh (C14-e (b), CF-F): public API only, so the same sources build
// against 6273e3a4 and 679f5d7d. Never part of the root package.
import PackageDescription

let package = Package(
    name: "ColdFrames",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../MetalUI")],
    targets: [
        .executableTarget(
            name: "ColdFrames",
            dependencies: [
                .product(name: "MetalUI", package: "MetalUI"),
                .product(name: "MetalUITesting", package: "MetalUI"),
            ]
        )
    ]
)
