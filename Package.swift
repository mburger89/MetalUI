// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MetalUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetalUICore", targets: ["MetalUICore"]),
    ],
    targets: [
        .target(name: "MetalUICore"),
        .testTarget(name: "MetalUICoreTests", dependencies: ["MetalUICore"]),

        .target(name: "MetalUIShaderTypes"),

        .target(
            name: "MetalUIRender",
            dependencies: ["MetalUICore", "MetalUIShaderTypes"],
            resources: [.copy("Shaders")]
        ),
        .testTarget(name: "MetalUIRenderTests", dependencies: ["MetalUIRender"]),
    ],
    swiftLanguageModes: [.v6]
)
