// swift-tools-version: 6.0
import PackageDescription

// No MetalUI dependency, by construction: this package must build where
// Metal, CoreText and AppKit do not exist. It only reads recorded fixtures.
let package = Package(
    name: "SDLGPUPortable",
    platforms: [.macOS(.v14)],  // Apple-only floor; Linux/Windows are unconstrained
    products: [
        .library(name: "SDLBridge", targets: ["SDLBridge"]),
        .library(name: "ReplayFixture", targets: ["ReplayFixture"]),
        .executable(name: "PortableReplay", targets: ["PortableReplay"])
    ],
    targets: [
        .systemLibrary(name: "CSDL", pkgConfig: "sdl3",
                       providers: [.brew(["sdl3"]), .apt(["libsdl3-dev"])]),
        .target(name: "SDLBridge", dependencies: ["CSDL"]),
        .target(name: "ReplayFixture"),
        .executableTarget(name: "PortableReplay", dependencies: ["SDLBridge", "ReplayFixture"]),
        .testTarget(name: "ReplayFixtureTests", dependencies: ["ReplayFixture"])
    ]
)
