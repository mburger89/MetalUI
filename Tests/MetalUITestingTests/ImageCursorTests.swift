import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// Image cursors through the headless platform (rulings `IC-A`...`IC-F`, `IC-I`; spec
// `docs/superpowers/specs/2026-10-14-cursors-headless-design.md` §5 tests 1-6). Plain imports of
// `MetalUI`, `MetalUIPlatform` and `MetalUITesting`, as an app's test target writes them: the
// window answers with the `PlatformCursorImage` it sent, so the size, the hot spot and the
// identity are read at the seam. No pixels, no GPU. Geometry: a 50 x 50 box left of a 50 x 50
// spacer in the 400 x 300 window, so the box is centred at (175, 150).

/// A `side` x `side` bitmap whose bytes vary with `seed`, so two seeds are two different pictures.
private func bitmap(side: Int, seed: UInt8 = 1) -> ImageBitmap {
    var rgba: [UInt8] = []
    for i in 0..<(side * side) { rgba += [seed &+ UInt8(i % 7), 40, 200, 255] }
    return ImageBitmap(width: side, height: side, rgba: rgba)
}

/// The cursor image the window last sent, or `nil` when the last style is not an image.
@MainActor private func sentImage(_ window: TestWindow) -> PlatformCursorImage? {
    guard case .image(let cursor)? = window.pointerStyle else { return nil }
    return cursor
}

/// One box under `style`, hovered.
@MainActor private func hoveredWindow(_ style: @escaping @MainActor () -> PointerStyle) throws -> TestWindow {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(50), height: Pixels(50)).onClick {}.pointerStyle(style())
            Box().frame(width: Pixels(50), height: Pixels(50))
        }
    }
    window.hover(at: pt(175, 150))
    return window
}

/// 1 - the point size is `pixels / scale` and the centre hot spot is half of it (`IC-C` 1, probe
/// `I1`, `I4`): a 32 px bitmap at scale 2 is 16 pt, hot spot (8, 8).
/// Mutations: lower with the pixel size instead of `pixels / scale`; multiply the hot spot by pixels.
@Test @MainActor func anImageCursorSendsItsPointSizeAndHotSpot() throws {
    let source = bitmap(side: 32)
    let window = try hoveredWindow {
        .image(Image(decorative: source, scale: 2), hotSpot: .center)
    }
    let cursor = try #require(sentImage(window), "\(String(describing: window.pointerStyle))")
    #expect(cursor.pixelWidth == 32 && cursor.pixelHeight == 32)
    #expect(cursor.pointWidth == 16 && cursor.pointHeight == 16)
    #expect(cursor.hotSpotX == 8 && cursor.hotSpotY == 8)
    #expect(cursor.scale == 2)
}

/// 2 - a hot spot outside the unit square clamps per axis (`IC-C` 2, divergence 465): `(2, -1)` on a
/// 16 pt image is (16, 0). Mutation: remove the clamp.
@Test @MainActor func aHotSpotOutsideTheUnitSquareClampsToTheImage() throws {
    let source = bitmap(side: 16)
    let window = try hoveredWindow {
        .image(Image(decorative: source, scale: 1), hotSpot: UnitPoint(x: 2, y: -1))
    }
    let cursor = try #require(sentImage(window))
    #expect(cursor.hotSpotX == 16 && cursor.hotSpotY == 0)
}

/// 3 - an `Image` rebuilt from the same bitmap in every build is one style: the window sends once
/// (`IC-F`). Mutation: key the style's equality on a fresh id per `Image`.
@Test @MainActor func aBitmapRebuiltEveryFrameSendsOneCursor() throws {
    let source = bitmap(side: 16)
    let window = try hoveredWindow {
        .image(Image(decorative: source, scale: 1), hotSpot: .center)
    }
    for _ in 0..<3 {
        window.window.setNeedsRedraw()
        window.tick()
    }
    #expect(window.platformWindow.pointerStyles.count == 1, "\(window.platformWindow.pointerStyles.count)")
}

/// 4 - identity, not bytes (`IC-A` 2): two bitmaps with equal pixels are two cursors, one bitmap is one.
/// Mutation: hash and compare the pixels.
@Test @MainActor func twoBitmapsWithEqualBytesAreTwoCursors() {
    let a = bitmap(side: 8), b = bitmap(side: 8)
    let styleA = PointerStyle.image(Image(decorative: a, scale: 1), hotSpot: .center)
    #expect(styleA == .image(Image(decorative: a, scale: 1), hotSpot: .center))
    #expect(styleA != .image(Image(decorative: b, scale: 1), hotSpot: .center))
    #expect(styleA != .image(Image(decorative: a, scale: 1), hotSpot: .zero), "the hot spot is part of the value")
    #expect(styleA != .image(Image(decorative: a, scale: 2), hotSpot: .center), "the scale is part of the value")
}

/// 5a - `nil` attaches nothing, so an enclosing image cursor stays (probe `P12`, `I7`).
/// 5b - an inner `.link` beats an outer image cursor (`CI-AH` item 2).
/// Mutation: resolve the outermost style first.
@Test @MainActor func aNilStyleOutsideAnImageCursorKeepsItAndAnInnerStyleBeatsAnOuterImage() throws {
    let source = bitmap(side: 16)
    let image = PointerStyle.image(Image(decorative: source, scale: 1), hotSpot: .center)
    let keeps = try harnessWindow {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(50), height: Pixels(50)).onClick {}.pointerStyle(nil)
        }.pointerStyle(image)
    }
    keeps.hover(at: pt(200, 150))
    #expect(sentImage(keeps) != nil, "\(String(describing: keeps.pointerStyle))")

    let inner = try harnessWindow {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(50), height: Pixels(50)).onClick {}.pointerStyle(.link)
        }.pointerStyle(image)
    }
    inner.hover(at: pt(200, 150))
    #expect(inner.pointerStyle == .pointingHand, "\(String(describing: inner.pointerStyle))")
}

/// 6 - `resizable()`, `interpolation` and the rest are ignored (`IC-B`, probe `I5`): the cursor is the
/// bitmap at its own size. Mutation: read `isResizable` into the size.
@Test @MainActor func anImageIgnoresResizableAndInterpolation() {
    let source = bitmap(side: 16)
    let plain = PointerStyle.image(Image(decorative: source, scale: 1), hotSpot: .center)
    let dressed = PointerStyle.image(Image(decorative: source, scale: 1).resizable().interpolation(.none),
                                     hotSpot: .center)
    #expect(plain == dressed)
}
