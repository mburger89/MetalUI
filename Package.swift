// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MetalUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetalUI", targets: ["MetalUI"]),
        .executable(name: "MetalUIDemo", targets: ["MetalUIDemo"]),
    ],
    targets: [
        .target(name: "MetalUICore"),
        .testTarget(name: "MetalUICoreTests", dependencies: ["MetalUICore"]),

        .target(name: "MetalUILayout", dependencies: ["MetalUICore"]),
        .testTarget(name: "MetalUILayoutTests", dependencies: ["MetalUILayout"]),

        .target(name: "MetalUIShaderTypes"),

        .target(
            name: "MetalUIRender",
            dependencies: ["MetalUICore", "MetalUIShaderTypes"],
            resources: [.copy("Shaders")]
        ),
        .testTarget(name: "MetalUIRenderTests", dependencies: ["MetalUIRender"]),

        .target(
            name: "MetalUIPlatform",
            dependencies: ["MetalUICore", "MetalUIRender"]
        ),
        .testTarget(name: "MetalUIPlatformTests", dependencies: ["MetalUIPlatform"]),

        .target(
            name: "MetalUI",
            dependencies: ["MetalUICore", "MetalUIRender", "MetalUIPlatform"]
        ),
        .testTarget(name: "MetalUITests", dependencies: ["MetalUI"]),
        .executableTarget(name: "MetalUIDemo", dependencies: ["MetalUI"]),
    ],
    swiftLanguageModes: [.v6]
)
