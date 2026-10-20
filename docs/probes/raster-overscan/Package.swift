// swift-tools-version: 6.0
// Prof: the release timing harness for P4 (record 124). Run through ab.sh, which points
// `path:` at a checkout by symlinking ./MetalUI (ignored by git) at it.
import PackageDescription
let package = Package(
    name: "Prof", platforms: [.macOS(.v15)],
    dependencies: [.package(path: "MetalUI")],
    targets: [.executableTarget(name: "Prof", dependencies: [
        .product(name: "MetalUI", package: "MetalUI"),
        .product(name: "MetalUITesting", package: "MetalUI"),
        .product(name: "MetalUIDemoContent", package: "MetalUI")],
        swiftSettings: [.unsafeFlags(["-g"])])])
