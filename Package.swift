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
        // targets. The eight non-test targets *here* are MetalUICore,
        // MetalUILayout, MetalUIText, MetalUIShaderTypes, MetalUIRender,
        // MetalUIPlatform, MetalUI and MetalUIDemo — which is not §3.1's list:
        // that one has seven, excluding MetalUIDemo, which is an executable
        // rather than a layer. **The two counts used to agree and no longer do**
        // — M2 Task 1 landed MetalUIText, which was the coincidence's expiry
        // date. Do not reconcile one list to the other; see CLAUDE.md's Build
        // section.
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

        // Font resolution, shaping, metrics and (from Task 5) glyph
        // rasterization and atlas packing. **Imports no Metal** — spec §3.1 of
        // the M2 text design: this project verifies headlessly, and a packer
        // reachable only behind a Metal device is a packer with no CI.
        // `MetalUILayout` deliberately does NOT depend on this: the engine never
        // learns what text is, it calls a `MeasureFunction`.
        //
        // The `MetalUICore` edge is declared by the plan and, as of Task 1, is
        // **imported by nothing** — font resolution needs only CoreText. It is
        // an unused edge rather than an unused API, so it changes no call site;
        // delete it if the milestone ends without one.
        .target(name: "MetalUIText", dependencies: ["MetalUICore"]),
        .testTarget(name: "MetalUITextTests", dependencies: ["MetalUIText"]),

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
            dependencies: [
                "MetalUICore", "MetalUILayout", "MetalUIText", "MetalUIRender", "MetalUIPlatform",
            ]
        ),
        // `MetalUIText` is a dependency of `MetalUI` already; it is named again
        // here so the tests may `@testable import` it. `ShapingCache.misses` is
        // internal, and the two-frame cache test is the only thing in the repo
        // that can see a per-frame cache — see `Frame.shapingCache`.
        .testTarget(
            name: "MetalUITests",
            dependencies: ["MetalUI", "MetalUIText", "MetalUITestSupport"]
        ),
        .executableTarget(name: "MetalUIDemo", dependencies: ["MetalUI"]),
    ],
    swiftLanguageModes: [.v6]
)
