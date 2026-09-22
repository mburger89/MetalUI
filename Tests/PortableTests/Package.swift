// swift-tools-version: 6.0
import PackageDescription

// FreeType determinism across platforms (ruling FT-J). Depends only on the
// root package's MetalUIFreeType and MetalUIScene products — no CoreText, no
// Metal — so it runs on Linux and Windows, where the root package's own test
// bundle (which includes the Metal tests) cannot. Its expected values were
// recorded on macOS; CI asserts them on Linux x86_64/aarch64 and Windows.
let package = Package(
    name: "PortableTests",
    platforms: [.macOS(.v14)],  // Apple-only floor; Linux/Windows are unconstrained
    dependencies: [.package(name: "MetalUI", path: "../..")],
    targets: [
        .testTarget(name: "FreeTypeDeterminismTests", dependencies: [
            .product(name: "MetalUIFreeType", package: "MetalUI"),
            .product(name: "MetalUIScene", package: "MetalUI"),
        ])
    ]
)
