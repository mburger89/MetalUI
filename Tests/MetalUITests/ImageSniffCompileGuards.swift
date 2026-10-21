import Testing
import MetalUITestSupport

// Image format sniff, guard G-IS1 (rulings `IS-A`, `IS-F`; spec 2026-10-20-image-sniff-design §5 test 10).
// Whole-file Swift 6 against a PLAIN `import MetalUI` (`SA-P`).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**; grep the log for
// `IS-A reachability` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func fixture(_ body: String) -> String {
    """
    import MetalUI
    import Foundation

    func probe(_ data: [UInt8]) {
    \(body)
    }
    """
}

/// **G-IS1** (`IS-A`, `IS-F`). From a plain import the enum, its nine cases and both statics are
/// reachable; `HeaderSource` and `sniffImageFormat` are not. The first fixture is the positive control.
///
/// Mutation: make `sniffImageFormat` `public` (the second negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSniffSurfaceIsReachableAndItsWalkIsNot() throws {
    let with = try typecheckFile(fixture("""
        let a: ImageFileFormat = ImageInfo.sniffedFormat(of: Data(data))
        let b: ImageFileFormat = ImageInfo.sniffedFormat(ofFile: "x")
        let all: [ImageFileFormat] = ImageFileFormat.allCases
        let _: [ImageFileFormat] = [.png, .jpeg, .gif, .tiff, .bmp, .webp, .heif, .avif, .unknown]
        func sendable<T: Sendable & Hashable>(_: T) {}
        sendable(a)
        _ = (b, all)
        switch a {
        case .png, .jpeg, .gif, .tiff, .bmp, .webp, .heif, .avif, .unknown: break
        }
        """), importing: "MetalUI")
    let source = try typecheckFile(fixture("""
        func reach(_ source: any HeaderSource) {}
        """), importing: "MetalUI")
    let walk = try typecheckFile(fixture("""
        let _ = sniffImageFormat(MemoryHeaderSource(bytes: UnsafeRawBufferPointer(start: nil, count: 0)))
        """), importing: "MetalUI")
    print("""
        IS-A reachability: with succeeded=\(with.succeeded) messages=[\(with.messages)]; \
        source succeeded=\(source.succeeded) walk succeeded=\(walk.succeeded)
        """)
    try #require(with.succeeded, "the control must compile, or this guard cannot fail:\n\(with.output)")
    #expect(!source.succeeded && source.messages.contains("HeaderSource"),
            "HeaderSource must be refused FOR its name:\n\(source.output)")
    #expect(!walk.succeeded && walk.messages.contains("sniffImageFormat"),
            "the sniff walk must be refused FOR its name:\n\(walk.output)")
}
