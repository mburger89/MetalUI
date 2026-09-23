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
        .executable(name: "PortableReplay", targets: ["PortableReplay"])
    ],
    dependencies: [.package(name: "MetalUI", path: "../..")],
    targets: [
        .systemLibrary(name: "CSDL", pkgConfig: "sdl3",
                       providers: [.brew(["sdl3"]), .apt(["libsdl3-dev"])]),
        // Declared here, not only in CSDL's module map: that `link` applies
        // only where Swift imports CSDL, and nothing does. Without pkg-config
        // (Windows) nothing else asks for SDL3.
        .target(name: "SDLBridge", dependencies: ["CSDL"], linkerSettings: [.linkedLibrary("SDL3")]),
        .target(name: "ReplayFixture", dependencies: [.product(name: "MetalUIScene", package: "MetalUI")]),
        .target(name: "SDLReplay", dependencies: ["SDLBridge", "ReplayFixture",
                                                  .product(name: "MetalUIScene", package: "MetalUI")]),
        .target(name: "MetalUISDL", dependencies: ["SDLBridge",
                                                   .product(name: "MetalUIPlatform", package: "MetalUI"),
                                                   .product(name: "MetalUICore", package: "MetalUI"),
                                                   .product(name: "MetalUIScene", package: "MetalUI")]),
        .testTarget(name: "MetalUISDLTests", dependencies: ["MetalUISDL", "SDLReplay",
                                                           .product(name: "MetalUIScene", package: "MetalUI"),
                                                           .product(name: "MetalUIPortableText", package: "MetalUI")]),
        .executableTarget(name: "PortableReplay", dependencies: ["SDLReplay", "ReplayFixture"]),
        .testTarget(name: "ReplayFixtureTests", dependencies: ["ReplayFixture",
                                                               .product(name: "MetalUIScene", package: "MetalUI")])
    ]
)
