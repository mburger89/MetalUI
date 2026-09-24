// swift-tools-version: 6.4
import PackageDescription

// Targets that import no Apple framework come first and are declared on every
// platform, so `swift build` and `swift test` work on Linux and Windows
// (roadmap item 5, ruling PC-A). Everything that needs AppKit, CoreText or
// Metal — including the portable text oracles, which compare against
// CoreText — is declared only on macOS, below.
var products: [Product] = [
        // Platform-free per-frame data (ruling PS-A), for backends outside this
        // package; first consumer: Backends/SDL.
        .library(name: "MetalUIScene", targets: ["MetalUIScene"]),
        // FreeType glyph rasterizer (ruling FT-B), for non-Apple backends.
        .library(name: "MetalUIFreeType", targets: ["MetalUIFreeType"]),
        // HarfBuzz shaper (ruling SH-B), for non-Apple text.
        .library(name: "MetalUIHarfBuzz", targets: ["MetalUIHarfBuzz"]),
        // The portable text pipeline (ruling PT-A).
        .library(name: "MetalUIPortableText", targets: ["MetalUIPortableText"]),
        // The platform's installed fonts as a PortableFontResolver (SF-A).
        .library(name: "MetalUISystemFonts", targets: ["MetalUISystemFonts"]),
        // The text seam (ruling TS-A).
        .library(name: "MetalUITextSystem", targets: ["MetalUITextSystem"]),
        // The platform protocols, for platforms outside this package
        // (Backends/SDL; ruling RS-A).
        .library(name: "MetalUIPlatform", targets: ["MetalUIPlatform"]),
        .library(name: "MetalUICore", targets: ["MetalUICore"]),
        // The framework itself, on every platform (ruling XP-A), and the
        // demo's content, which `Backends/SDL`'s demo draws (roadmap item 10).
        .library(name: "MetalUI", targets: ["MetalUI"]),
        .library(name: "MetalUIDemoContent", targets: ["MetalUIDemoContent"]),

]

var metalUIDependencies: [Target.Dependency] = [
    "MetalUICore", "MetalUILayout", "MetalUITextSystem", "MetalUIPlatform", "MetalUIPrimitives",
]
#if os(macOS)
metalUIDependencies += ["MetalUIText", "MetalUIRender", "MetalUIAppKit"]
#endif

var targets: [Target] = [
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

        // HarfBuzz 14.5.0, vendored (ruling SH-A; Sources/CHarfBuzz/VENDORED.md).
        // Only the amalgamation compiles; it #includes the rest of src/. No
        // optional backend (no FreeType, ICU, GLib, CoreText): HarfBuzz reads
        // the font's own tables.
        .target(
            name: "CHarfBuzz",
            exclude: ["COPYING", "VENDORED.md"],
            sources: ["src/harfbuzz.cc"]
        ),

        // libunibreak 8.0, vendored (ruling LB-A; Sources/CUnibreak/VENDORED.md):
        // UAX #14 line breaking only. The two *data.c files are #included by
        // the sources, not compiled on their own.
        .target(
            name: "CUnibreak",
            exclude: ["LICENCE", "VENDORED.md", "src/linebreakauxdata.c",
                      "src/eastasianwidthdata.c"],
            sources: ["src"]
        ),

        // FreeType 2.14.3, vendored (ruling FT-A; Sources/CFreeType/VENDORED.md).
        // Only the per-module amalgamation files compile; each #includes the
        // rest of its module.
        // SheenBidi 3.0.0, vendored (ruling BD-A; Sources/CSheenBidi/VENDORED.md):
        // UAX #9 and script runs. Upstream's unity build: one file, which
        // #includes the rest.
        .target(
            name: "CSheenBidi",
            exclude: ["LICENSE", "VENDORED.md"],
            sources: ["Source/SheenBidi.c"],
            publicHeadersPath: "Headers",
            cSettings: [.define("SB_CONFIG_UNITY"), .headerSearchPath("Source")]
        ),

        .target(
            name: "CFreeType",
            exclude: ["LICENSE.TXT", "FTL.TXT", "VENDORED.md"],
            sources: [
                "src/base/ftbase.c", "src/base/ftinit.c", "src/base/ftsystem.c",
                "src/base/ftdebug.c", "src/base/ftbbox.c", "src/base/ftbitmap.c",
                "src/base/ftmm.c",
                "src/sfnt/sfnt.c", "src/truetype/truetype.c", "src/cff/cff.c",
                "src/psaux/psaux.c", "src/psnames/psnames.c", "src/smooth/smooth.c",
            ],
            // No unsafeFlags: SwiftPM refuses them in any package depended on
            // by URL. The one warning the default build system raises in
            // FreeType is silenced in its ftoption.h instead (VENDORED.md).
            cSettings: [.define("FT2_BUILD_LIBRARY")]
        ),

        // String -> MUIGlyphs + atlas coverage with no Apple framework
        // (rulings PT-A, PT-D): HarfBuzz shapes, FreeType rasterizes.
        .target(name: "MetalUIPortableText",
                dependencies: ["MetalUIScene", "MetalUIHarfBuzz", "MetalUIFreeType",
                               "CUnibreak", "MetalUITextSystem", "CSheenBidi"]),

        // Installed fonts, discovered and registered lazily (rulings SF-A…SF-D).
        // The one portable text target with a file system: imports Foundation
        // (swift-corelibs-foundation off Apple), MetalUIFreeType and
        // MetalUIPortableText.
        .target(name: "MetalUISystemFonts", dependencies: ["MetalUIPortableText", "MetalUIFreeType"]),
        .testTarget(name: "MetalUISystemFontsTests", dependencies: ["MetalUISystemFonts"]),

        // Shaping with no Apple framework (rulings SH-B, SH-K): imports only
        // CHarfBuzz. One run: no line breaking, bidi, itemization or fallback.
        .target(name: "MetalUIHarfBuzz", dependencies: ["CHarfBuzz"]),

        // Glyph rasterization with no Apple framework (rulings FT-B, FT-K):
        // imports only MetalUIScene and CFreeType.
        .target(name: "MetalUIFreeType", dependencies: ["MetalUIScene", "CFreeType"]),

        // The C structs shared with the shaders; MetalUIScene imports them.
        .target(name: "MetalUIShaderTypes"),

        // The seam `Text` measures and draws through (ruling TS-A): one
        // protocol, a CoreText implementation in MetalUIText and a portable
        // one in MetalUIPortableText. Imports only MetalUIScene.
        .target(name: "MetalUITextSystem", dependencies: ["MetalUIScene"]),

        // The platform protocols — windows, input, accessibility, and the
        // `WindowRenderer` a window draws with (ruling RS-A). Portable: the
        // AppKit implementation is `MetalUIAppKit`, the SDL one `Backends/SDL`.
        .target(name: "MetalUIPlatform", dependencies: ["MetalUICore", "MetalUIScene"]),

        // MetalUICore's geometry and colours as the shader ABI's structs
        // (`MUIRect`, `MUIGlyph`, …) — what `Frame` builds a `Scene` from.
        // Portable (ruling XP-A); re-exported by MetalUIRender.
        .target(name: "MetalUIPrimitives", dependencies: ["MetalUICore", "MetalUIScene"]),

        // The framework (ruling XP-A): portable on its own; on macOS it also
        // depends on CoreText, Metal and AppKit — appended below — for
        // `CoreTextTextSystem` (the default text system) and `AppKitPlatform`.
        .target(name: "MetalUI", dependencies: metalUIDependencies),
        // The demo's content, a library so `MetalUITests` can import it (ruling
        // LR-S) and `Backends/SDL`'s demo can draw it.
        .target(name: "MetalUIDemoContent", dependencies: ["MetalUI"]),
        // The whole framework's frame, pinned byte-for-byte across platforms
        // (ruling XP-C): runs on macOS, Linux and Windows.
        .testTarget(name: "MetalUICrossPlatformTests",
                    dependencies: ["MetalUI", "MetalUIDemoContent", "MetalUIPortableText"]),

]

#if os(macOS)
products += [
        .executable(name: "MetalUIDemo", targets: ["MetalUIDemo"]),

]

targets += [
        .testTarget(name: "MetalUIPortableTextTests",
                    dependencies: ["MetalUIPortableText", "MetalUIText"]),

        .testTarget(name: "MetalUIHarfBuzzTests", dependencies: ["MetalUIHarfBuzz", "MetalUIFreeType"]),

        // Fonts load from Tests/Fonts by #filePath, not as resources (FT-G).
        .testTarget(name: "MetalUIFreeTypeTests", dependencies: ["MetalUIFreeType", "MetalUIText"]),

        .target(name: "MetalUIText", dependencies: ["MetalUICore", "MetalUIScene", "MetalUITextSystem"]),
        .testTarget(name: "MetalUITextTests", dependencies: ["MetalUIText"]),

        // The `MetalUIText` edge is one-way and points this way on purpose (M2
        // text design §3.1): the renderer uploads the CPU-side `GlyphAtlas` to
        // an `MTLTexture`, and `MetalUIText` never learns that Metal exists.
        // Reversing it would put the shelf packer behind a device and leave it
        // with no CI.
        .target(
            name: "MetalUIRender",
            dependencies: ["MetalUICore", "MetalUIShaderTypes", "MetalUIScene", "MetalUIText",
                           "MetalUIPlatform", "MetalUIPrimitives"],
            resources: [.copy("Shaders")]
        ),
        // `MetalUIText` is a dependency of `MetalUIRender` already; it is named
        // again so the glyph tests may build a real `GlyphAtlas` and read its
        // `pixels` back as the oracle for what the GPU should have sampled.
        .testTarget(name: "MetalUIRenderTests",
                    dependencies: ["MetalUIRender", "MetalUIScene", "MetalUIText"]),

        // AppKit: the macOS `Platform` and `PlatformWindow`, drawing through
        // `MetalWindowRenderer` (ruling RS-C).
        .target(
            name: "MetalUIAppKit",
            dependencies: ["MetalUICore", "MetalUIPlatform", "MetalUIRender"]
        ),
        .testTarget(name: "MetalUIPlatformTests",
                    dependencies: ["MetalUIPlatform", "MetalUIAppKit", "MetalUIRender"]),

        // `MetalUIText` is a dependency of `MetalUI` already; it is named again
        // here so the tests may `@testable import` it. `ShapingCache.misses` is
        // internal, and the two-frame cache test is the only thing in the repo
        // that can see a per-frame cache — see `Frame.shapingCache`.
        // `MetalUIDemoContent` is named so the tests import the demo's own tree
        // (`demoContent()`, the counter, the proposal preview) rather than a copy
        // of it (plan task 7, stage 1, lane 5; ruling LR-S).
        .testTarget(
            name: "MetalUITests",
            dependencies: ["MetalUI", "MetalUIText", "MetalUITestSupport", "MetalUIDemoContent",
                           "MetalUIPortableText", "MetalUIAppKit"]
        ),
        // The demo's content, a library so `MetalUITests` can import it (ruling
        // LR-S). In no product: it is demo content, not framework API. It makes
        // the non-test targets nine; CLAUDE.md's "eight" is the Docs phase's.
        .executableTarget(name: "MetalUIDemo", dependencies: ["MetalUI", "MetalUIDemoContent"]),

]
#endif

let package = Package(
    name: "MetalUI",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
