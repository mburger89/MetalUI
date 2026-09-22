// swift-tools-version: 6.4
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
        // targets. The ten non-test targets *here* are MetalUICore,
        // MetalUILayout, MetalUIScene, MetalUIText, MetalUIShaderTypes,
        // MetalUIRender, MetalUIPlatform, MetalUI, MetalUIDemoContent and
        // MetalUIDemo — which is not §3.1's list:
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
        // What a GPU backend consumes per frame — the scene and the glyph atlas
        // — with no Apple framework import, so it builds on Linux and Windows
        // (ruling PS-A). Re-exported by MetalUIText and MetalUIRender (PS-B).
        .target(name: "MetalUIScene", dependencies: ["MetalUIShaderTypes"]),

        .target(name: "MetalUIText", dependencies: ["MetalUICore", "MetalUIScene"]),
        .testTarget(name: "MetalUITextTests", dependencies: ["MetalUIText"]),

        .target(name: "MetalUIShaderTypes"),

        // The `MetalUIText` edge is one-way and points this way on purpose (M2
        // text design §3.1): the renderer uploads the CPU-side `GlyphAtlas` to
        // an `MTLTexture`, and `MetalUIText` never learns that Metal exists.
        // Reversing it would put the shelf packer behind a device and leave it
        // with no CI.
        .target(
            name: "MetalUIRender",
            dependencies: ["MetalUICore", "MetalUIShaderTypes", "MetalUIScene", "MetalUIText"],
            resources: [.copy("Shaders")]
        ),
        // `MetalUIText` is a dependency of `MetalUIRender` already; it is named
        // again so the glyph tests may build a real `GlyphAtlas` and read its
        // `pixels` back as the oracle for what the GPU should have sampled.
        .testTarget(name: "MetalUIRenderTests",
                    dependencies: ["MetalUIRender", "MetalUIScene", "MetalUIText"]),

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
        // `MetalUIDemoContent` is named so the tests import the demo's own tree
        // (`demoContent()`, the counter, the proposal preview) rather than a copy
        // of it (plan task 7, stage 1, lane 5; ruling LR-S).
        .testTarget(
            name: "MetalUITests",
            dependencies: ["MetalUI", "MetalUIText", "MetalUITestSupport", "MetalUIDemoContent"]
        ),
        // The demo's content, a library so `MetalUITests` can import it (ruling
        // LR-S). In no product: it is demo content, not framework API. It makes
        // the non-test targets nine; CLAUDE.md's "eight" is the Docs phase's.
        .target(name: "MetalUIDemoContent", dependencies: ["MetalUI"]),
        .executableTarget(name: "MetalUIDemo", dependencies: ["MetalUI", "MetalUIDemoContent"]),
    ],
    swiftLanguageModes: [.v6]
)
