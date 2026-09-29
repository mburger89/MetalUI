import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIRender
@testable import MetalUI
#if canImport(ImageIO)
import Foundation
import ImageIO
import CoreGraphics
#endif

// Plan task 11, part 2, lane 3: `Image`, `ImageBitmap`, `aspectRatio` with no
// ratio and `scaledToFit`/`scaledToFill` (spec
// `docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md` §8 lane 3,
// rulings `TE-AL`, `TE-AM`, `TE-AQ` item 9). Every expected value is a probe
// reading (`docs/probes/swiftui-shapes-and-rendering.swift`, the arm named on
// each test) or derived from one before the run. The kernel half of
// `aspectRatio(nil)` is `Tests/MetalUILayoutTests/AspectRatioIdealTests.swift`
// (portable). Helpers `kernelAnswers`, `s1Proposals` and `proposal` are
// `ShapeTests.swift`'s; probe I1's five proposals are S1's, in S1's order.

/// A `width × height` opaque bitmap, its left half red and right half blue —
/// probe I1's two-colour image.
private func twoColour(_ width: Int, _ height: Int) -> ImageBitmap {
    var rgba: [UInt8] = []
    for _ in 0..<height {
        for x in 0..<width {
            rgba += x < width / 2 ? [255, 0, 0, 255] : [0, 0, 255, 255]
        }
    }
    return ImageBitmap(width: width, height: height, rgba: rgba)
}

private func size(_ w: Double, _ h: Double) -> SizeD { SizeD(width: w, height: h) }

/// Renders `root` into a `width × height` frame at `scaleFactor` and returns
/// its finalized scene. A root is placed centred at its own answer (`CN-J`).
@MainActor
private func scene<E: Element>(_ width: Float, _ height: Float, scaleFactor: Float = 1,
                               _ root: E) -> Scene {
    var root = root
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)),
                      scaleFactor: scaleFactor)
    frame.render(&root)
    return frame.finalizedScene()
}

private func floats(_ b: MUIBounds) -> [Float] {
    [b.origin.x, b.origin.y, b.size.width, b.size.height]
}

// MARK: - 3.1–3.3 sizing and the textured quad

/// **3.1 — an image answers its point size, `pixels ÷ scale`, at every
/// proposal** (probes I1, I9): a 40×20-pixel bitmap at scale 1 and an
/// 80×40-pixel one at scale 2 both answer 40×20 at I1's five proposals.
///
/// Mutation: **M3a** `scale` ignored (the scale-2 image answers 80×40).
@Test @MainActor func anImageAnswersItsPointSizeAtEveryProposal() throws {
    let expected = Array(repeating: size(40, 20), count: 5)
    #expect(kernelAnswers(Image(decorative: twoColour(40, 20), scale: 1)) == expected, "I1")
    #expect(kernelAnswers(Image(decorative: twoColour(80, 40), scale: 2)) == expected, "I9")
}

/// **3.2 — a resizable image answers its proposal, a nil axis its point
/// size** (probe I2's row: nil×nil → 40×20, 100×60 → 100×60, 0×0 → 0×0,
/// ∞×∞ → ∞×∞, 100×nil → 100×20).
///
/// Mutation: **M3b** `resizable()` a no-op (the row reads 40×20 five times).
@Test @MainActor func aResizableImageAnswersItsProposal() throws {
    let inf = Double.infinity
    let i2 = [size(40, 20), size(100, 60), size(0, 0), size(inf, inf), size(100, 20)]
    #expect(kernelAnswers(Image(decorative: twoColour(40, 20), scale: 1).resizable()) == i2, "I2")
    #expect(kernelAnswers(Image(decorative: twoColour(80, 40), scale: 2).resizable()) == i2,
            "I2 at scale 2: the nil axis is the point size, not the pixel size")
}

/// **3.3 — an image paints one textured quad over its bounds, at the frame's
/// scale** (`TE-AF`, `TE-AL`): an 80×40-pixel bitmap at image scale 2 is
/// 40×20 pt, centred in a 100×60 frame at (30, 20); at scale factor 2 the
/// `MUIImage` is (60, 40, 80, 40) device pixels, and the scene's one texture is
/// the bitmap's own.
///
/// Mutation: **M3c** the quad drawn at the bitmap's pixel size rather than its
/// bounds (reads (60, 40, 160, 80)).
@Test @MainActor func anImagePaintsOneTexturedQuadOverItsBoundsAtTheScale() throws {
    let bitmap = twoColour(80, 40)
    let painted = scene(100, 60, scaleFactor: 2, Image(decorative: bitmap, scale: 2))
    try #require(painted.images.count == 1, "one quad: \(painted.images.count)")
    #expect(floats(painted.images[0].bounds) == [60, 40, 80, 40],
            "bounds \(floats(painted.images[0].bounds))")
    #expect(painted.textures.count == 1 && painted.textures.first === bitmap.texture,
            "the scene carries the bitmap's texture")
    #expect(painted.images[0].opacity == 1)
    #expect(painted.rects.isEmpty, "an image paints no rect")
}

// MARK: - 3.5–3.7 aspect ratio over an image

/// **3.5 — a fixed child keeps its size under `aspectRatio(nil)`** (probes
/// A4, I7): a fixed 40×20 frame and a non-resizable 40×20 image, each under
/// `.aspectRatio(contentMode: .fit)`/`.scaledToFit()`, answer 40×20 at all five
/// proposals — the node answers its child's answer to the ratio-shaped
/// proposal, never the proposal itself.
///
/// Mutation: **M3e** the node answers the ratio-shaped proposal (100×60 reads
/// 100×50).
@Test @MainActor func aFixedChildKeepsItsSizeUnderAspectRatioNil() throws {
    let expected = Array(repeating: size(40, 20), count: 5)
    #expect(kernelAnswers(Rectangle().frame(width: Pixels(40), height: Pixels(20))
                              .aspectRatio(contentMode: .fit)) == expected, "A4")
    #expect(kernelAnswers(Image(decorative: twoColour(40, 20), scale: 1).scaledToFit()) == expected,
            "I7")
}

/// **3.6 — `scaledToFit()` and `scaledToFill()` are `aspectRatio(nil)`**
/// (probes I3–I5): a resizable 40×20 image in a 100×60 frame fits at
/// (0, 5, 100, 50) and fills at (−10, 0, 120, 60) — its ideal ratio, 2, read
/// from its answer at nil×nil.
///
/// Mutation: **M3f** `scaledToFill` mapped to `.fit` (fill reads fit's rect).
@Test @MainActor func scaledToFitAndScaledToFillAreAspectRatioNil() throws {
    let image = Image(decorative: twoColour(40, 20), scale: 1).resizable()
    let fit = scene(100, 60, image.scaledToFit().frame(width: Pixels(100), height: Pixels(60)))
    let fill = scene(100, 60, image.scaledToFill().frame(width: Pixels(100), height: Pixels(60)))
    let explicitFit = scene(100, 60, image.aspectRatio(contentMode: .fit)
                                .frame(width: Pixels(100), height: Pixels(60)))
    try #require(fit.images.count == 1 && fill.images.count == 1 && explicitFit.images.count == 1)
    #expect(floats(fit.images[0].bounds) == [0, 5, 100, 50], "I3 fit \(floats(fit.images[0].bounds))")
    #expect(floats(fill.images[0].bounds) == [-10, 0, 120, 60], "I4 fill \(floats(fill.images[0].bounds))")
    #expect(floats(explicitFit.images[0].bounds) == floats(fit.images[0].bounds),
            "I5: scaledToFit is aspectRatio(contentMode: .fit)")
}

/// **3.7 — a filling image overflows its frame unless clipped** (probe I10):
/// in a 200×100 window a 100×60 frame sits at (50, 20) and its filling image
/// at (40, 20, 120, 60). Unclipped, the quad's mask is the surface
/// (0, 0, 200, 100); under `.clipped()` it is the frame, (50, 20, 100, 60).
///
/// Mutation: **M3g** the image clips itself to its own bounds (the unclipped
/// mask reads (40, 20, 120, 60)).
@Test @MainActor func aFillImageOverflowsItsFrameUnlessClipped() throws {
    let framed = Image(decorative: twoColour(40, 20), scale: 1).resizable().scaledToFill()
        .frame(width: Pixels(100), height: Pixels(60))
    let unclipped = scene(200, 100, framed)
    let clipped = scene(200, 100, framed.clipped())
    try #require(unclipped.images.count == 1 && clipped.images.count == 1)
    #expect(floats(unclipped.images[0].bounds) == [40, 20, 120, 60])
    #expect(floats(unclipped.images[0].contentMask) == [0, 0, 200, 100],
            "unclipped mask \(floats(unclipped.images[0].contentMask))")
    #expect(floats(clipped.images[0].contentMask) == [50, 20, 100, 60],
            "clipped mask \(floats(clipped.images[0].contentMask))")
}

// MARK: - 3.8 interpolation

/// **3.8 — `.none` samples nearest, every other interpolation bilinear**
/// (probes I8, I11). **Divergence 93's pin**: SwiftUI's `.high` differs from
/// its default by 880 px (I8); MetalUI draws it bilinear, filter 0.
///
/// Mutation: **M3h** `.none` → filter 0.
@Test @MainActor func interpolationNoneIsNearestAndEveryOtherLinear() throws {
    let image = Image(decorative: twoColour(2, 1), scale: 1).resizable()
    func filter(_ image: Image) throws -> UInt32 {
        let painted = scene(100, 10, image)
        try #require(painted.images.count == 1)
        return painted.images[0].filter
    }
    #expect(try filter(image.interpolation(.none)) == ImageFilter.nearest.rawValue, ".none")
    #expect(try filter(image) == ImageFilter.linear.rawValue, "the default")
    #expect(try filter(image.interpolation(.low)) == ImageFilter.linear.rawValue, ".low")
    #expect(try filter(image.interpolation(.medium)) == ImageFilter.linear.rawValue, ".medium")
    #expect(try filter(image.interpolation(.high)) == ImageFilter.linear.rawValue,
            ".high — divergence 93")
}

// MARK: - 3.9–3.11 ImageBitmap

/// **3.9 — `ImageBitmap` takes straight alpha and premultiplies** (probe I12,
/// `TE-AL`): straight (200, 100, 50, 128) is stored (100, 50, 25, 128).
///
/// Mutation: **M3i** the bytes copied as given.
@Test func anImageBitmapPremultipliesStraightAlpha() throws {
    let bitmap = ImageBitmap(width: 1, height: 1, rgba: [200, 100, 50, 128])
    #expect(bitmap.texture.pixels == [100, 50, 25, 128], "\(bitmap.texture.pixels)")
    #expect(bitmap.width == 1 && bitmap.height == 1)
}

/// **3.10 (exit) — a wrong byte count or a zero side traps, naming
/// `ImageBitmap`** — one `@Test`, two children. The message is asserted so the
/// texture's own precondition, one layer further in, cannot stand in for it.
///
/// Mutation: **M3j** `ImageBitmap`'s precondition removed (both children still
/// die, in `ImageTexture`, and neither names `ImageBitmap`).
@Test func anImageBitmapOfTheWrongByteCountOrAZeroSideTraps() async {
    let count = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        _ = ImageBitmap(width: 2, height: 1, rgba: [0, 0, 0, 0])
    }
    let countStderr = String(decoding: count?.standardErrorContent ?? [], as: UTF8.self)
    #expect(countStderr.contains("ImageBitmap"), "byte count: \(countStderr)")

    let zero = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        _ = ImageBitmap(width: 0, height: 1, rgba: [])
    }
    let zeroStderr = String(decoding: zero?.standardErrorContent ?? [], as: UTF8.self)
    #expect(zeroStderr.contains("ImageBitmap"), "zero side: \(zeroStderr)")
}

/// **3.10b (exit) — a scale that is not finite and positive traps** (SA-J:
/// `pixels ÷ scale` would be infinite or negative at every proposal, and a
/// stored rect may not be infinite). SwiftUI's answer is unprobed; the rule is
/// `SA-J`'s, not a SwiftUI claim (`TE-AU`).
///
/// Mutation: the precondition removed (both children exit 0).
@Test func anImageOfANonPositiveOrNonFiniteScaleTraps() async {
    let zero = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = Image(decorative: ImageBitmap(width: 1, height: 1, rgba: [0, 0, 0, 255]), scale: 0)
        }
    }
    let zeroStderr = String(decoding: zero?.standardErrorContent ?? [], as: UTF8.self)
    #expect(zeroStderr.contains("scale"), "zero: \(zeroStderr)")

    let infinite = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = Image(decorative: ImageBitmap(width: 1, height: 1, rgba: [0, 0, 0, 255]), scale: .infinity)
        }
    }
    let infiniteStderr = String(decoding: infinite?.standardErrorContent ?? [], as: UTF8.self)
    #expect(infiniteStderr.contains("scale"), "infinite: \(infiniteStderr)")
}

#if canImport(ImageIO)
/// **3.11 (macOS) — `ImageBitmap(contentsOfFile:)` decodes a PNG through
/// ImageIO** (`TE-AL`): a 2×2 PNG written by ImageIO here from straight RGBA
/// decodes to the same bytes, premultiplied. **Two rows, not the spec's 2×1**
/// (`TE-AU`): a one-row image cannot tell top-down from bottom-up, so M3k
/// could not redden. Opaque texels and one transparent one, so the
/// premultiply is exact on every path (a translucent texel's rounding is
/// CoreGraphics', not ours).
///
/// Mutation: **M3k** the rows read bottom-up.
@Test func anImageBitmapDecodesAPNGThroughImageIO() throws {
    let straight: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                             0, 0, 255, 255, 10, 20, 30, 0]
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("metalui-image-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }

    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let provider = try #require(CGDataProvider(data: Data(straight) as CFData))
    let cgImage = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                                       bytesPerRow: 8, space: space,
                                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                       provider: provider, decode: nil, shouldInterpolate: false,
                                       intent: .defaultIntent))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString,
                                                                   1, nil))
    CGImageDestinationAddImage(destination, cgImage, nil)
    try #require(CGImageDestinationFinalize(destination), "the PNG was written")

    let decoded = try #require(ImageBitmap(contentsOfFile: url.path), "the PNG decodes")
    #expect(decoded.width == 2 && decoded.height == 2)
    #expect(decoded.texture.pixels == [255, 0, 0, 255, 0, 255, 0, 255,
                                       0, 0, 255, 255, 0, 0, 0, 0],
            "decoded \(decoded.texture.pixels)")
    #expect(ImageBitmap(contentsOfFile: url.path + ".missing") == nil, "a missing file is nil")
}
#endif
