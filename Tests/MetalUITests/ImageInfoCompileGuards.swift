import Testing
import MetalUITestSupport

// Header-only image read, guard G-IH1 (rulings `IH-A`, `IH-H`; spec 2026-10-14-image-info-design §5
// test 18). Whole-file Swift 6 against a PLAIN `import MetalUI` (`SA-P`): a `@testable` test cannot
// prove what an external module can write.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards");
// grep the log for `IH-A reachability` to know it ran.

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

/// **G-IH1** (`IH-A`, `IH-H`). From a plain import the whole header surface is reachable — `ImageInfo`,
/// its formats and fields, `DecodedImage.Limits` and the two limited initialisers — and the walk's
/// machinery (`HeaderSource`, the memberwise `ImageInfo` initialiser) is not. The positive control is
/// the first fixture; each negative must be refused FOR its name.
///
/// Mutation: make `HeaderSource` `public` (the first negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theHeaderSurfaceIsReachableAndTheWalkIsNot() throws {
    let with = try typecheckFile(fixture("""
        guard let info = ImageInfo(data: Data(data)) ?? ImageInfo(contentsOfFile: "x") else { return }
        let _: ImageInfo.Format = info.format
        let _: Int = info.width + info.height + info.bitDepth + info.channelCount
        let _: Image.Orientation = info.orientation
        let _: (width: Int, height: Int) = info.orientedSize
        var limits = DecodedImage.Limits(maxInputBytes: 1, maxSide: 2, maxPixels: 3)
        limits.maxSide = nil
        let _: DecodedImage? = DecodedImage(data: Data(data), format: .grey, limits: limits)
        let _: DecodedImage? = DecodedImage(contentsOfFile: "x", limits: limits)
        func sendable<T: Sendable & Hashable>(_: T) {}
        sendable(info)
        sendable(limits)
        """), importing: "MetalUI")
    let source = try typecheckFile(fixture("""
        func reach(_ source: any HeaderSource) {}
        """), importing: "MetalUI")
    let memberwise = try typecheckFile(fixture("""
        let _ = ImageInfo(format: .png, width: 1, height: 1, orientation: .up, bitDepth: 8, channelCount: 4)
        """), importing: "MetalUI")
    let walk = try typecheckFile(fixture("""
        let _ = readImageInfo
        """), importing: "MetalUI")
    print("""
        IH-A reachability: with succeeded=\(with.succeeded) messages=[\(with.messages)]; \
        source succeeded=\(source.succeeded) memberwise succeeded=\(memberwise.succeeded) walk succeeded=\(walk.succeeded)
        """)
    try #require(with.succeeded, "the control must compile, or this guard cannot fail:\n\(with.output)")
    #expect(!source.succeeded && source.messages.contains("HeaderSource"),
            "HeaderSource must be refused FOR its name:\n\(source.output)")
    #expect(!memberwise.succeeded && memberwise.messages.contains("no exact matches in call to initializer"),
            "the memberwise initialiser must be refused:\n\(memberwise.output)")
    #expect(!walk.succeeded && walk.messages.contains("readImageInfo"),
            "the walk must be refused FOR its name:\n\(walk.output)")
}
