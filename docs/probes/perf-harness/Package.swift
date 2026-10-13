// swift-tools-version: 6.0
// Throwaway harness for docs/probes/perf-baselines.sh (record 105, BL-A): public
// API only, so it needs no Sources/ hook. Never part of the root package.
import PackageDescription

let package = Package(
    name: "PerfBaselines",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../MetalUI")],
    targets: [
        .executableTarget(
            name: "PerfBaselines",
            dependencies: [
                .product(name: "MetalUI", package: "MetalUI"),
                .product(name: "MetalUITesting", package: "MetalUI"),
                .product(name: "MetalUIDemoContent", package: "MetalUI"),
            ]
        )
    ]
)
