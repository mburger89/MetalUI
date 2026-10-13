// swift-tools-version: 6.0
// Layout-kernel-only harness for docs/probes/perf-baselines.sh (record 105, BL-A).
// MetalUICore and MetalUILayout are the checkout's own sources, linked in by the
// script as Sources/MetalUICore and Sources/MetalUILayout, so the executable can
// read `package` API (lastNativeLayoutWork) without a Sources/ hook.
import PackageDescription

let package = Package(
    name: "PerfLayout",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "MetalUICore"),
        .target(name: "MetalUILayout", dependencies: ["MetalUICore"]),
        .executableTarget(name: "LayoutOnly", dependencies: ["MetalUILayout", "MetalUICore"]),
    ]
)
