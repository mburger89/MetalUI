// swift-tools-version: 6.1
import PackageDescription

// Jotter: MetalUI's sample app. The manifest is the one `metalui new
// --cross-platform` writes, with the checkout as a path dependency (docs/packaging.md).

// MetalUI's SDL backend (`MetalUISDL`) is compiled only when its `SDL` trait
// is on - here, on Linux and Windows; `AccessKit` is its screen-reader
// bridge. macOS uses AppKit and needs neither.
#if os(Linux) || os(Windows)
let metalUITraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
#else
let metalUITraits: Set<Package.Dependency.Trait> = [.defaults]
#endif

let package = Package(
    name: "Jotter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Jotter", targets: ["Jotter"]),
        .library(name: "JotterKit", targets: ["JotterKit"]),
    ],
    dependencies: [
        .package(name: "MetalUI", path: "../..", traits: metalUITraits),
    ],
    targets: [
        // Everything but the entry point, so a test imports it plainly.
        .target(
            name: "JotterKit",
            dependencies: [
                .product(name: "MetalUI", package: "MetalUI"),
            ]
        ),
        .executableTarget(
            name: "Jotter",
            dependencies: [
                "JotterKit",
                .product(name: "MetalUI", package: "MetalUI"),
                .product(name: "MetalUISDL", package: "MetalUI", condition: .when(platforms: [.linux, .windows])),
                // On every platform (SG-D): a target naming these fails to build on macOS
                // when they are conditional here ("unable to resolve module dependency: 'CFreeType'").
                .product(name: "MetalUIPortableText", package: "MetalUI"),
                .product(name: "MetalUISystemFonts", package: "MetalUI"),
            ]
        ),
        .testTarget(
            name: "JotterTests",
            dependencies: [
                "JotterKit",
                .product(name: "MetalUI", package: "MetalUI"),
                .product(name: "MetalUITesting", package: "MetalUI"),
                .product(name: "MetalUIPortableText", package: "MetalUI"),
                .product(name: "MetalUISystemFonts", package: "MetalUI"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
