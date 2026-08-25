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
    ],
    swiftLanguageModes: [.v6]
)
