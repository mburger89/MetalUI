// swift-tools-version: 6.1
import PackageDescription

// The SDL backend's tools and tests. The backend itself — `CSDL`, `CAccessKit`,
// `SDLBridge` and `MetalUISDL`, whose sources are in this directory — is
// declared by MetalUI's root package behind its `SDL` and `AccessKit` traits
// (ruling PX-H), so a package depending on MetalUI by URL reaches it. This
// package is its first consumer: it depends on the root by path with both
// traits on, and builds where Metal, CoreText and AppKit do not exist.
//
// SDL3 and AccessKit come from the compiler's default paths or from
// `-Xcc -I… -Xlinker -L…` (ruling PX-I; `scripts/fetch-accesskit.py
// --print-flags` prints AccessKit's): no pkg-config.
let package = Package(
    name: "MetalUISDL",
    platforms: [.macOS(.v14)],  // Apple-only floor; Linux/Windows are unconstrained
    products: [
        .library(name: "ReplayFixture", targets: ["ReplayFixture"]),
        .library(name: "SDLReplay", targets: ["SDLReplay"]),
        .executable(name: "PortableReplay", targets: ["PortableReplay"]),
        .executable(name: "DemoCapture", targets: ["DemoCapture"]),
        .executable(name: "MetalUISDLDemo", targets: ["MetalUISDLDemo"]),
        // The main-queue drain, checked from top-level code (ruling SV-H).
        .executable(name: "MainQueueDrainCheck", targets: ["MainQueueDrainCheck"])
    ],
    dependencies: [.package(name: "MetalUI", path: "../..", traits: ["SDL", "AccessKit"])],
    targets: [
        .target(name: "ReplayFixture", dependencies: [.product(name: "MetalUIScene", package: "MetalUI")]),
        .target(name: "SDLReplay", dependencies: ["ReplayFixture",
                                                  .product(name: "SDLBridge", package: "MetalUI"),
                                                  .product(name: "MetalUIScene", package: "MetalUI")]),
        // `MetalUI` for the lifecycle tests (ruling `LC-O`'s lane 2: an `App`
        // over `SDLPlatform`, spec tests 10.2 and 10.3).
        .testTarget(name: "MetalUISDLTests", dependencies: ["SDLReplay", "ReplayFixture",
                                                           .product(name: "MetalUISDL", package: "MetalUI"),
                                                           .product(name: "SDLBridge", package: "MetalUI"),
                                                           .product(name: "MetalUI", package: "MetalUI"),
                                                           .product(name: "MetalUIScene", package: "MetalUI"),
                                                           .product(name: "MetalUIPortableText", package: "MetalUI")]),
        .executableTarget(name: "PortableReplay", dependencies: ["SDLReplay", "ReplayFixture"]),
        // The demo on this platform, checked against macOS (ruling DC-B).
        .executableTarget(name: "DemoCapture", dependencies: [
            "ReplayFixture",
            .product(name: "MetalUISDL", package: "MetalUI"),
            .product(name: "MetalUI", package: "MetalUI"),
            .product(name: "MetalUIDemoContent", package: "MetalUI"),
            .product(name: "MetalUIPortableText", package: "MetalUI")]),
        // The demo in an SDL window (ruling DC-C).
        .executableTarget(name: "MetalUISDLDemo", dependencies: [
            .product(name: "MetalUISDL", package: "MetalUI"),
            .product(name: "MetalUISystemFonts", package: "MetalUI"),
            .product(name: "MetalUI", package: "MetalUI"),
            .product(name: "MetalUIDemoContent", package: "MetalUI"),
            .product(name: "MetalUIPortableText", package: "MetalUI")]),
        // The SDL loop's main-queue drain in a process of its own (ruling
        // SV-H item 3): `SDLMainQueueDrainTests` launches it. `MetalUI` and
        // `MetalUIPortableText` for the `.task` modes (ruling PX-L item 2).
        .executableTarget(name: "MainQueueDrainCheck", dependencies: [
            .product(name: "MetalUISDL", package: "MetalUI"),
            .product(name: "SDLBridge", package: "MetalUI"),
            .product(name: "MetalUIPlatform", package: "MetalUI"),
            .product(name: "MetalUICore", package: "MetalUI"),
            .product(name: "MetalUI", package: "MetalUI"),
            .product(name: "MetalUIPortableText", package: "MetalUI")]),
        .testTarget(name: "ReplayFixtureTests", dependencies: ["ReplayFixture",
                                                               .product(name: "MetalUIScene", package: "MetalUI")])
    ]
)
