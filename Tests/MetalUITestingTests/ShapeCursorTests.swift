import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing
@testable import MetalUI

// Presentation extras, lane 2: `PointerStyle.shape(_:eoFill:size:hotSpot:fill:outline:)` (rulings `BG-K`...`BG-M`,
// divergence 735; spec `docs/superpowers/specs/2026-10-22-presentation-extras-design.md` tests 27-36). The shape is
// rasterized on the CPU through `MetalUIPath` at the window's integer display scale and reaches the platform as the
// image cursor it already serves (`IC-`), so every read is at the seam: the `PlatformCursorImage` the headless window
// recorded. Geometry as in `ImageCursorTests`: a 50 x 50 box centred at (175, 150) in the 400 x 300 window.
// Red before: `PointerStyle.shape` does not exist, so the file does not compile.

/// The cursor image the window last sent, or `nil` when the last style is not an image.
@MainActor private func sentShape(_ window: TestWindow) -> PlatformCursorImage? {
    guard case .image(let cursor)? = window.pointerStyle else { return nil }
    return cursor
}

/// One box under `style`, hovered, at `scale`.
@MainActor private func shapeWindow(scale: Float = 1,
                                    _ style: @escaping @MainActor () -> PointerStyle) throws -> TestWindow {
    let window = try harnessWindow(scaleFactor: scale) {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(50), height: Pixels(50)).onClick {}.pointerStyle(style())
            Box().frame(width: Pixels(50), height: Pixels(50))
        }
    }
    window.hover(at: pt(175, 150))
    return window
}

/// The straight RGBA of a premultiplied cursor pixel (rounded), `(r, g, b, a)`.
private func pixel(_ cursor: PlatformCursorImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let i = (y * cursor.pixelWidth + x) * 4
    let p = cursor.texture.pixels
    let a = Int(p[i + 3])
    guard a > 0 else { return (0, 0, 0, 0) }
    func straight(_ c: UInt8) -> Int { min(255, (Int(c) * 255 + a / 2) / a) }
    return (straight(p[i]), straight(p[i + 1]), straight(p[i + 2]), a)
}

/// A 20 x 20 square frame: an outer and an inner rectangle wound the same way, so nonzero fills the
/// inner one and even-odd leaves it a hole.
@MainActor private func donut() -> Path {
    var path = Path()
    path.addRect(Bounds(origin: pt(0, 0), size: sz(20, 20)))
    path.addRect(Bounds(origin: pt(6, 6), size: sz(8, 8)))
    return path
}

/// 27 (`BG-L`) - the cursor is the shape rasterized at the display scale: `(size * scale) + 2 * ceil(scale)`
/// pixels a side, `size + 2` points, the centre black and opaque, the corner clear, the outline white.
/// Mutation: rasterize at scale 1 whatever the display.
@Test @MainActor func aShapeCursorIsAnImageCursorOfTheShapeRasterizedAtTheDisplayScale() throws {
    for scale in [Float(1), 2] {
        let window = try shapeWindow(scale: scale) { .shape(Circle(), size: sz(20, 20)) }
        let cursor = try #require(sentShape(window), "\(String(describing: window.pointerStyle))")
        let side = Int(20 * scale) + 2 * Int(scale)
        #expect(cursor.pixelWidth == side && cursor.pixelHeight == side, "scale \(scale): \(cursor.pixelWidth)")
        #expect(cursor.scale == scale)
        #expect(cursor.pointWidth == 22 && cursor.pointHeight == 22)
        let centre = pixel(cursor, side / 2, side / 2)
        #expect(centre.r == 0 && centre.g == 0 && centre.b == 0 && centre.a == 255, "\(centre)")
        #expect(pixel(cursor, 0, 0).a == 0, "the corner is clear")
        let ring = pixel(cursor, 0, side / 2)
        #expect(ring.a >= 200 && ring.r >= 200 && ring.g >= 200 && ring.b >= 200, "the outline ring: \(ring)")
    }
}

/// 28 (`BG-L`) - `eoFill` leaves the hole of an overlapping path transparent; the same path nonzero is
/// filled (the separating arm). Mutation: always nonzero.
@Test @MainActor func eoFillLeavesTheHoleOfAnOverlappingPathTransparent() throws {
    let even = try shapeWindow { .shape(donut(), eoFill: true, size: sz(20, 20)) }
    let evenCursor = try #require(sentShape(even))
    #expect(pixel(evenCursor, 11, 11).a == 0, "the hole is clear under even-odd: \(pixel(evenCursor, 11, 11))")
    #expect(pixel(evenCursor, 3, 11).a == 255, "the ring of the frame is filled")
    let nonzero = try shapeWindow { .shape(donut(), eoFill: false, size: sz(20, 20)) }
    let filled = try #require(sentShape(nonzero))
    #expect(pixel(filled, 11, 11).a == 255, "nonzero fills the inner rectangle: \(pixel(filled, 11, 11))")
}

/// 29 (`BG-M`, `IC-A`, `IC-F`) - a shape rebuilt in every build is one style: one send, one texture identity,
/// one raster. Mutation: key the style or the cache by the closure or a fresh id.
@Test @MainActor func aShapeRebuiltEveryFrameIsOneCursorWithOneTexture() throws {
    let window = try shapeWindow { .shape(Circle(), size: sz(20, 20)) }
    let first = try #require(sentShape(window))
    for _ in 0..<5 {
        window.window.setNeedsRedraw()
        window.tick()
    }
    #expect(window.platformWindow.pointerStyles.count == 1, "\(window.platformWindow.pointerStyles.count) sends")
    #expect(try #require(sentShape(window)).texture === first.texture)
    #expect(window.window.shapeCursors.rasterCount == 1, "\(window.window.shapeCursors.rasterCount) rasters")
}

/// 30 (`BG-M`) - a different size, scale, hot spot, fill or outline is another cursor: each arm one more
/// raster and one more send. Mutation: leave `outline` (or any one field) out of the key.
@Test @MainActor func aDifferentSizeScaleHotSpotOrColourIsAnotherCursor() throws {
    let variant = ShapeCell<Int>(0)
    let window = try shapeWindow {
        switch variant.value {
        case 1: .shape(Circle(), size: sz(24, 24))
        case 2: .shape(Circle(), size: sz(20, 20), hotSpot: .topLeading)
        case 3: .shape(Circle(), size: sz(20, 20), fill: .red)
        case 4: .shape(Circle(), size: sz(20, 20), outline: .blue)
        default: .shape(Circle(), size: sz(20, 20))
        }
    }
    var sends = window.platformWindow.pointerStyles.count
    var rasters = window.window.shapeCursors.rasterCount
    #expect(sends == 1 && rasters == 1)
    for arm in 1...4 {
        variant.value = arm
        window.window.setNeedsRedraw()
        window.tick()
        #expect(window.platformWindow.pointerStyles.count == sends + 1, "arm \(arm): one more send")
        #expect(window.window.shapeCursors.rasterCount == rasters + 1, "arm \(arm): one more raster")
        sends += 1
        rasters += 1
    }
}

/// 31 (`BG-K`, `BG-L`) - the hot spot is the shape's centre by default (the outline margin added), and a hot
/// spot outside the unit square clamps per axis. Mutation: the hot spot from the bitmap origin.
@Test @MainActor func theShapeCursorHotSpotIsTheCentreByDefaultAndClampsOutsideTheUnitSquare() throws {
    let centred = try #require(sentShape(shapeWindow { .shape(Circle(), size: sz(20, 10)) }))
    #expect(centred.hotSpotX == 11 && centred.hotSpotY == 6, "(\(centred.hotSpotX), \(centred.hotSpotY))")
    let corner = try #require(sentShape(shapeWindow {
        .shape(Circle(), size: sz(20, 10), hotSpot: UnitPoint(x: 0, y: 0))
    }))
    #expect(corner.hotSpotX == 1 && corner.hotSpotY == 1, "the shape's own top-left, past the margin")
    let outside = try #require(sentShape(shapeWindow {
        .shape(Circle(), size: sz(20, 10), hotSpot: UnitPoint(x: 3, y: -2))
    }))
    #expect(outside.hotSpotX == 21 && outside.hotSpotY == 1, "clamped to the shape's right and top")
}

/// 32 (`BG-L`) - a non-finite or non-positive size is the arrow; a side over 128 points clamps to 128.
/// Mutation: no clamp (the pixel size reads 1000 and more).
@Test @MainActor func aNonFiniteOrEmptySizeFallsBackToTheArrowAndAnOversizedOneClampsTo128() throws {
    #expect(PointerStyle.shape(Circle(), size: sz(0, 20)) == .default)
    #expect(PointerStyle.shape(Circle(), size: sz(20, -1)) == .default)
    #expect(PointerStyle.shape(Circle(), size: sz(.nan, 20)) == .default)
    #expect(PointerStyle.shape(Circle(), size: sz(.infinity, 20)) == .default)
    let big = try #require(sentShape(shapeWindow { .shape(Circle(), size: sz(1000, 300)) }))
    #expect(big.pointWidth == 130 && big.pointHeight == 130, "128 + the outline's two points")
    #expect(big.pixelWidth == 130)
}

/// 33 (`BG-M`) - the cache keeps the eight most recently used: nine shapes then the first again is a ninth
/// raster. Mutation: no eviction (the first is still held, no ninth raster).
@Test @MainActor func theShapeCursorCacheKeepsTheEightMostRecentlyUsed() throws {
    let which = ShapeCell<Int>(0)
    let window = try shapeWindow { .shape(Circle(), size: sz(Float(10 + which.value), 12)) }
    for index in 1...8 {
        which.value = index
        window.window.setNeedsRedraw()
        window.tick()
    }
    #expect(window.window.shapeCursors.rasterCount == 9, "nine distinct shapes (0...8)")
    #expect(window.window.shapeCursors.count == 8, "eight held")
    which.value = 0
    window.window.setNeedsRedraw()
    window.tick()
    #expect(window.window.shapeCursors.rasterCount == 10, "the first was evicted: a tenth raster")
    which.value = 8
    window.window.setNeedsRedraw()
    window.tick()
    #expect(window.window.shapeCursors.rasterCount == 10, "the most recent stayed")
}

/// 34 (`BG-L`) - a cursor is not a frame leaf: sending one moves neither the window's raster cache counters nor
/// its texture count. Mutation: route the cursor through `animationStore.rasters`.
@Test @MainActor func aShapeCursorCostsNoFrameRasterWork() throws {
    let window = try shapeWindow { .shape(Circle(), size: sz(20, 20)) }
    _ = try #require(sentShape(window))
    window.window.setNeedsRedraw()
    window.tick()
    let rasters = window.window.animationStore.rasters
    #expect(rasters.lastRasterizedPixels == 0 && rasters.lastTexturesMade == 0)
    #expect(rasters.textureCount == 0, "\(rasters.textureCount) textures")
}

/// 35 (`BG-M`) - a window moved to another display re-sends the shape once at the new scale; the same scale
/// again sends nothing. Mutation: leave `resolvedPointerStyle` alone on a scale change.
@Test @MainActor func aShapeCursorUnderAScaleChangeIsReSentOnceAtTheNewScale() throws {
    let window = try shapeWindow { .shape(Circle(), size: sz(20, 20)) }
    #expect(try #require(sentShape(window)).scale == 1)
    window.setScaleFactor(2)
    #expect(window.platformWindow.pointerStyles.count == 2, "one re-send")
    let moved = try #require(sentShape(window))
    #expect(moved.scale == 2 && moved.pixelWidth == 44)
    window.setScaleFactor(2)
    window.window.setNeedsRedraw()
    window.tick()
    #expect(window.platformWindow.pointerStyles.count == 2, "an equal scale sends nothing")
}

/// A mutable cell a fixture's closure reads.
@MainActor private final class ShapeCell<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
