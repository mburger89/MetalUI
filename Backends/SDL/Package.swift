// swift-tools-version: 6.0
import PackageDescription

// Depends only on MetalUI's MetalUIScene product — Scene, the glyph atlas and
// the shader structs, with no Apple framework import (ruling PS-A) — so this
// package builds where Metal, CoreText and AppKit do not exist.
let package = Package(
    name: "MetalUISDL",
    platforms: [.macOS(.v14)],  // Apple-only floor; Linux/Windows are unconstrained
    products: [
        // The SDL GPU WindowRenderer (ruling RS-D).
        .library(name: "MetalUISDL", targets: ["MetalUISDL"]),
        .library(name: "SDLBridge", targets: ["SDLBridge"]),
        .library(name: "ReplayFixture", targets: ["ReplayFixture"]),
        .library(name: "SDLReplay", targets: ["SDLReplay"]),
        .executable(name: "PortableReplay", targets: ["PortableReplay"]),
        .executable(name: "DemoCapture", targets: ["DemoCapture"]),
        .executable(name: "MetalUISDLDemo", targets: ["MetalUISDLDemo"])
    ],
    dependencies: [.package(name: "MetalUI", path: "../..")],
    targets: [
        .systemLibrary(name: "CSDL", pkgConfig: "sdl3",
                       providers: [.brew(["sdl3"]), .apt(["libsdl3-dev"])]),
        // Declared here, not only in CSDL's module map: that `link` applies
        // only where Swift imports CSDL, and nothing does. Without pkg-config
        // (Windows) nothing else asks for SDL3.
        .target(name: "SDLBridge", dependencies: ["CSDL"], linkerSettings: [.linkedLibrary("SDL3")]),
        // AccessKit's C API (ruling AX-A): run scripts/fetch-accesskit.py, then
        // build with PKG_CONFIG_PATH=.accesskit (Linux, macOS) or its -Xcc/-Xlinker
        // flags (Windows).
        .systemLibrary(name: "CAccessKit", pkgConfig: "accesskit"),
        .target(name: "ReplayFixture", dependencies: [.product(name: "MetalUIScene", package: "MetalUI")]),
        .target(name: "SDLReplay", dependencies: ["SDLBridge", "ReplayFixture",
                                                  .product(name: "MetalUIScene", package: "MetalUI")]),
        .target(name: "MetalUISDL", dependencies: ["SDLBridge", "CAccessKit",
                                                   .product(name: "MetalUIPlatform", package: "MetalUI"),
                                                   .product(name: "MetalUICore", package: "MetalUI"),
                                                   .product(name: "MetalUIScene", package: "MetalUI")],
                // What AccessKit's Rust static library needs on Windows, where
                // no pkg-config file says so (Linux and macOS: accesskit.pc).
                linkerSettings: ["bcrypt", "ntdll", "propsys", "runtimeobject", "uiautomationcore",
                                 "userenv", "ws2_32", "ole32", "oleaut32", "user32", "advapi32"]
                    .map { .linkedLibrary($0, .when(platforms: [.windows])) }),
        .testTarget(name: "MetalUISDLTests", dependencies: ["MetalUISDL", "SDLReplay",
                                                           .product(name: "MetalUIScene", package: "MetalUI"),
                                                           .product(name: "MetalUIPortableText", package: "MetalUI")]),
        .executableTarget(name: "PortableReplay", dependencies: ["SDLReplay", "ReplayFixture"]),
        // The demo on this platform, checked against macOS (ruling DC-B).
        .executableTarget(name: "DemoCapture", dependencies: [
            "MetalUISDL", "ReplayFixture",
            .product(name: "MetalUI", package: "MetalUI"),
            .product(name: "MetalUIDemoContent", package: "MetalUI"),
            .product(name: "MetalUIPortableText", package: "MetalUI")]),
        // The demo in an SDL window (ruling DC-C).
        .executableTarget(name: "MetalUISDLDemo", dependencies: [
            "MetalUISDL",
            .product(name: "MetalUISystemFonts", package: "MetalUI"),
            .product(name: "MetalUI", package: "MetalUI"),
            .product(name: "MetalUIDemoContent", package: "MetalUI"),
            .product(name: "MetalUIPortableText", package: "MetalUI")]),
        .testTarget(name: "ReplayFixtureTests", dependencies: ["ReplayFixture",
                                                               .product(name: "MetalUIScene", package: "MetalUI")])
    ]
)
