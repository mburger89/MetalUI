import Testing
import MetalUITestSupport

// Public image decoding, lane 1, guard G-IB1 (rulings `IB-A`, `IB-E`; spec 2026-10-13-image-decode-api
// §5 test 15). Whole-file Swift 6 against a PLAIN `import MetalUI` (`SA-P`): a `@testable` test cannot
// prove what an external module can write.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards");
// grep the log for `IB-A reachability` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func fixture(_ body: String) -> String {
    """
    import MetalUI

    func probe(_ data: [UInt8]) {
    \(body)
    }
    """
}

/// **G-IB1** (`IB-A`). From a plain import the whole decode surface is reachable — the type, both
/// formats, every member, `Image.Orientation`'s MetalUI-only members, `ImageBitmap(_:)` — and
/// `ImageBitmap.texture` still is not (the bitmap keeps premultiplied texels private). The positive
/// control is the first fixture; the negative must be refused FOR `texture`.
///
/// Mutation: make `ImageBitmap.texture` `public` (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theDecodeSurfaceIsReachableAndTheBitmapsTextureIsNot() throws {
    let with = try typecheckFile(fixture("""
        guard let image = DecodedImage(data: .init(data), format: .grey) ?? DecodedImage(contentsOfFile: "x") else { return }
        let _: Int = image.width + image.height + image.bytesPerRow + image.pixels.count
        let _: DecodedImage.Format = image.format
        let _: Image.Orientation = image.orientation
        let _: (width: Int, height: Int) = image.orientedSize
        let upright: DecodedImage = image.applyingOrientation()
        let _ = ImageBitmap(upright)
        let _ = Image.Orientation(exifValue: 6)?.exifValue
        let _ = Image.Orientation.right.swapsAxes
        """), importing: "MetalUI")
    let without = try typecheckFile(fixture("""
        guard let image = DecodedImage(data: .init(data)) else { return }
        let bitmap = ImageBitmap(image)
        let _ = bitmap.texture
        """), importing: "MetalUI")
    print("""
        IB-A reachability: with succeeded=\(with.succeeded) messages=[\(with.messages)]; \
        without succeeded=\(without.succeeded) messages=[\(without.messages)]
        """)
    try #require(with.succeeded && !without.succeeded,
                 """
                 the control must compile and the negative must not, or this guard cannot fail:
                 with:
                 \(with.output)
                 without:
                 \(without.output)
                 """)
    #expect(without.messages.contains("texture"),
            "the negative must be refused FOR texture:\n\(without.output)")
}
