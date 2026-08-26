// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MetalUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetalUI", targets: ["MetalUI"]),
        .executable(name: "MetalUIDemo", targets: ["MetalUIDemo"]),
    ],
    targets: [
        // Test-support only: the single copy of the `swiftc -typecheck` machinery
        // that the negative type-system guards shell out to (ruling EP-1). It is
        // in **no product** and is **not** one of spec §3.1's seven layering
        // targets. The seven non-test targets *here* are MetalUICore,
        // MetalUILayout, MetalUIShaderTypes, MetalUIRender, MetalUIPlatform,
        // MetalUI and MetalUIDemo — which is not §3.1's list: that one has
        // MetalUIText, which does not exist yet, and no MetalUIDemo, which is an
        // executable rather than a layer. The counts matching today is a
        // coincidence that expires when Text lands. See CLAUDE.md's Build section.
        .target(name: "MetalUITestSupport", path: "Tests/MetalUITestSupport"),

        .target(name: "MetalUICore"),
        .testTarget(
            name: "MetalUICoreTests",
            dependencies: ["MetalUICore", "MetalUITestSupport"]
        ),

        .target(name: "MetalUILayout", dependencies: ["MetalUICore"]),
        .testTarget(
            name: "MetalUILayoutTests",
            dependencies: ["MetalUILayout"],
            resources: [.copy("Fixtures"), .copy("Golden")]
        ),

        .target(name: "MetalUIShaderTypes"),

        .target(
            name: "MetalUIRender",
            dependencies: ["MetalUICore", "MetalUIShaderTypes"],
            resources: [.copy("Shaders")]
        ),
        .testTarget(name: "MetalUIRenderTests", dependencies: ["MetalUIRender"]),

        .target(
            name: "MetalUIPlatform",
            dependencies: ["MetalUICore", "MetalUIRender"]
        ),
        .testTarget(name: "MetalUIPlatformTests", dependencies: ["MetalUIPlatform"]),

        .target(
            name: "MetalUI",
            dependencies: ["MetalUICore", "MetalUILayout", "MetalUIRender", "MetalUIPlatform"]
        ),
        .testTarget(
            name: "MetalUITests",
            dependencies: ["MetalUI", "MetalUITestSupport"]
        ),
        .executableTarget(name: "MetalUIDemo", dependencies: ["MetalUI"]),
    ],
    swiftLanguageModes: [.v6]
)
