// swift-tools-version: 6.0
import PackageDescription

// Cross-platform determinism for the non-Apple text targets: FreeType's
// rasterizer (ruling FT-J), the HarfBuzz shaper (ruling SH-I) and the portable
// text pipeline that joins them (ruling PT-H). Depends only
// on the root package's MetalUIFreeType, MetalUIHarfBuzz, MetalUIPortableText
// and MetalUIScene products — no CoreText, no Metal — so it runs on Linux and Windows, where the
// root package's own test bundle (which includes the Metal tests) cannot. Its
// expected values were recorded on macOS; CI asserts them on Linux
// x86_64/aarch64 and Windows.
let package = Package(
    name: "PortableTests",
    platforms: [.macOS(.v14)],  // Apple-only floor; Linux/Windows are unconstrained
    dependencies: [.package(name: "MetalUI", path: "../..")],
    targets: [
        .testTarget(name: "FreeTypeDeterminismTests", dependencies: [
            .product(name: "MetalUIFreeType", package: "MetalUI"),
            .product(name: "MetalUIScene", package: "MetalUI"),
        ]),
        // SH-I. MetalUIFreeType is here for the one end-to-end case: shape,
        // then rasterize every glyph the shaper returned.
        .testTarget(name: "HarfBuzzDeterminismTests", dependencies: [
            .product(name: "MetalUIHarfBuzz", package: "MetalUI"),
            .product(name: "MetalUIFreeType", package: "MetalUI"),
            .product(name: "MetalUIScene", package: "MetalUI"),
        ]),
        // PT-H. The whole portable text pipeline: string -> MUIGlyphs + atlas.
        .testTarget(name: "PortableTextDeterminismTests", dependencies: [
            .product(name: "MetalUIPortableText", package: "MetalUI"),
            .product(name: "MetalUIScene", package: "MetalUI"),
        ]),
    ]
)
