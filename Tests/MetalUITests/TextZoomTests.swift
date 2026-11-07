import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import Foundation
import MetalUIText
import MetalUITextSystem
@testable import MetalUI

// R4-5 PR E lane 2 (ruling prefix `TZ-`, record 222; probe `docs/probes/swiftui-text-under-transform.swift`, arms `Z0`..`Z7`):
// text under a flattening effect is rasterized at the scale it is drawn at, on a ladder of `2^(1/8)`, and re-keyed at
// `Frame.insertIntoScene` (divergence 106 narrowed). Counts are work and geometry, never pixels (the render arm is
// `TextZoomRenderTests`); nothing here sleeps.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let linear1 = Animation.linear(duration: 1)

/// A `TextSystem` counting `rasterize` calls, over the CoreText system.
final class RasterCountingTextSystem: TextSystem, @unchecked Sendable {
    let base = CoreTextTextSystem()
    var rasterized = 0
    func resolveFont(_ descriptor: FontDescriptor) -> FontKey { base.resolveFont(descriptor) }
    func fontMetrics(_ font: FontKey) -> TextFontMetrics { base.fontMetrics(font) }
    func measure(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions) -> TextMeasurement {
        base.measure(string, font: font, wrappingAt: width, options: options)
    }
    func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        base.placeGlyphs(string, font: font, wrappingAt: width, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func caretOffsets(_ string: String, font: FontKey) -> [Double] { base.caretOffsets(string, font: font) }
    func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions) -> [Range<Int>] {
        base.lineRanges(string, font: font, wrappingAt: width, options: options)
    }
    func rasterize(_ key: GlyphKey) -> GlyphImage { rasterized += 1; return base.rasterize(key) }
    func measure(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions) -> StyledTextMeasurement {
        base.measure(text, wrappingAt: width, options: options)
    }
    func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
                origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        base.layOut(text, wrappingAt: width, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics { base.decorationMetrics(font) }
    func beginFrame() { base.beginFrame() }
    func endFrame() { base.endFrame() }
}

/// Frames built over one atlas and one counting text system, as a window holds them (`TransitionHarness`'s shape).
@MainActor final class ZoomHarness {
    let table = StateTable()
    let store = AnimationStore()
    let system = RasterCountingTextSystem()
    let atlas: GlyphAtlas
    var scaleFactor: Float = 1
    init(atlas: GlyphAtlas = Window.makeGlyphAtlas()) { self.atlas = atlas }

    @discardableResult
    func frame<E: Element>(_ element: E, t: Double = 0, animation: Animation? = nil, side: Float = 200) -> Frame {
        var root = element
        let frame = Frame(contentSize: Size(width: Pixels(side), height: Pixels(side)), scaleFactor: scaleFactor,
                          stateTable: table, textSystem: system, glyphAtlas: atlas, timestamp: t, transaction: animation,
                          animationStore: store)
        frame.render(&root)
        return frame
    }
}

@MainActor private func label() -> Text { Text("Aa").font(size: 12) }

/// The atlas rectangle sizes of a scene's glyphs, in emission order.
private func slots(_ scene: Scene) -> [(w: Float, h: Float)] { scene.glyphs.map { ($0.atlasBounds.size.width, $0.atlasBounds.size.height) } }

// MARK: - 9. scale

/// **9 (`TZ-A`, divergence 106 narrowed; replaces `aTextUnderScaleEffectIsResampledNotReRasterized`, probe `Z0`/`Z1`).** Under
/// `scaleEffect(2)` (on the ladder) every glyph's atlas slot is about twice the plain slot (the ink padding is 1 pixel a side, so
/// within 2) and is drawn 1:1 (`|bounds.w - slot.w| < 1e-3`); every glyph was re-keyed and none fell back. Mutations **T1** (the
/// re-key disabled) and **T2** (`f` ignored, the raster scale taken from the transform alone: `scaleEffect` flattens, so no
/// transform is left and the slots stay plain).
@Test @MainActor func aTextUnderScaleEffectIsReRasterizedAtTheEffectiveScale() throws {
    let native = ZoomHarness().frame(Text("Aa").font(size: 24)).finalizedScene()
    let plain = ZoomHarness().frame(label()).finalizedScene()
    let h = ZoomHarness()
    let frame = h.frame(label().scaleEffect(2))
    let scaled = frame.finalizedScene()
    try #require(!plain.glyphs.isEmpty && plain.glyphs.count == scaled.glyphs.count, "the same glyphs")
    for (n, s) in zip(slots(native), slots(scaled)) {
        #expect(abs(s.w - n.w) <= 1 && abs(s.h - n.h) <= 1, "slot \(s) against real 24 pt text \(n)")
    }
    for (p, s) in zip(slots(plain), slots(scaled)) { #expect(s.w > 1.5 * p.w && s.h > 1.5 * p.h, "slot \(s) is not the plain \(p)") }
    for g in scaled.glyphs {
        #expect(abs(g.bounds.size.width - g.atlasBounds.size.width) < 1e-3
                && abs(g.bounds.size.height - g.atlasBounds.size.height) < 1e-3, "drawn 1:1: \(g.bounds.size) of \(g.atlasBounds.size)")
    }
    #expect(frame.glyphsRekeyed == scaled.glyphs.count && frame.glyphRekeyFallbacks == 0,
            "re-keyed \(frame.glyphsRekeyed) of \(scaled.glyphs.count), fallbacks \(frame.glyphRekeyFallbacks)")
}

// MARK: - 10. rotation

/// **10 (`TZ-A`; `Z3`: SwiftUI is vector-exact under rotation, so this is 106's residue).** `rotationEffect(30 degrees)` leaves the
/// device-scale raster alone: slots equal the plain slots, nothing is re-keyed. Mutation **T3**: the snap removed (every `f` off 1
/// by a hair re-keys) is not reachable here (a rotation has `f` = 1 exactly), so the arm also carries a `scaleEffect(1.03)` that
/// the snap must leave alone (within 1/16 of an octave).
@Test @MainActor func aRotationOnlyKeepsTheDeviceScaleRasterAndLooksNothingUp() throws {
    let plain = ZoomHarness().frame(label()).finalizedScene()
    func check<E: Element>(_ name: String, _ element: E) {
        let frame = ZoomHarness().frame(element)
        let scene = frame.finalizedScene()
        #expect(slots(scene).map(\.w) == slots(plain).map(\.w) && slots(scene).map(\.h) == slots(plain).map(\.h), "\(name): the plain slots")
        #expect(frame.glyphsRekeyed == 0 && frame.glyphRekeyFallbacks == 0, "\(name): nothing re-keyed \(frame.glyphsRekeyed)")
    }
    check("rotation", label().rotationEffect(.degrees(30)))
    check("a 3 percent scale", label().scaleEffect(1.03))
}

// MARK: - 11. order

/// **11 (`TZ-A`; reworked from the plan: the scale factor is the flattening scale alone, the transform contributes 1).** A scale
/// that flattens (`scaleEffect(2)` inside the rotation) re-rasterizes at 2 and the rotation resamples that raster; a scale outside
/// the rotation does not flatten (the rotation between keeps it a transform), so its glyphs keep the plain raster and are drawn
/// twice as large. SwiftUI is vector-exact for both (probe `Z4`, 0 px apart), so the second is 106's residue and this pins today's
/// answer for it. Mutation **T4**: `f` not applied to the rung (the flattening scale dropped from the raster scale).
@Test @MainActor func aScaleInsideARotationRasterizesAtTwoAndOneOutsideItKeepsTheDeviceRaster() throws {
    let plain = ZoomHarness().frame(label()).finalizedScene()
    let inner = ZoomHarness().frame(label().scaleEffect(2).rotationEffect(.degrees(30)))
    let innerScene = inner.finalizedScene()
    let outer = ZoomHarness().frame(label().rotationEffect(.degrees(30)).scaleEffect(2))
    let outerScene = outer.finalizedScene()
    try #require(innerScene.glyphs.count == plain.glyphs.count && outerScene.glyphs.count == plain.glyphs.count, "the same glyphs")
    for (p, s) in zip(slots(plain), slots(innerScene)) { #expect(s.w > 1.5 * p.w && s.h > 1.5 * p.h, "scale inside: slot \(s) of plain \(p)") }
    #expect(inner.glyphsRekeyed == plain.glyphs.count, "scale inside: re-keyed \(inner.glyphsRekeyed)")
    #expect(slots(outerScene).map(\.w) == slots(plain).map(\.w) && slots(outerScene).map(\.h) == slots(plain).map(\.h), "scale outside: the plain slots")
    #expect(outer.glyphsRekeyed == 0, "scale outside: nothing re-keyed \(outer.glyphsRekeyed)")
    for g in innerScene.glyphs { #expect(g.transform != 0, "scale inside: the rotation is a record") }
}

// MARK: - 12. projection

/// **12 (`TZ-A`; probe `Z5`: a projection alone is a resample, `Z5b`: a projection of a scaled text rasterizes at the scale).**
/// `rotation3DEffect` of unscaled text keeps the device-scale raster; with `scaleEffect(2)` inside it the raster is twice as large
/// (the flattening scale, never the projective Jacobian). Mutation **T5**: the raster scale taken from the projection
/// (`f * |a|` of the homography), which would re-key the unscaled arm.
@Test @MainActor func aProjectedUnscaledTextKeepsTheDeviceScaleRaster() throws {
    let plain = ZoomHarness().frame(label()).finalizedScene()
    let projected = ZoomHarness().frame(label().rotation3DEffect(.degrees(40), axis: (x: 0, y: 1, z: 0), perspective: 1))
    let scene = projected.finalizedScene()
    #expect(slots(scene).map(\.w) == slots(plain).map(\.w) && slots(scene).map(\.h) == slots(plain).map(\.h), "the plain slots")
    #expect(projected.glyphsRekeyed == 0, "nothing re-keyed: \(projected.glyphsRekeyed)")
    let both = ZoomHarness().frame(label().scaleEffect(2).rotation3DEffect(.degrees(40), axis: (x: 0, y: 1, z: 0), perspective: 1))
    let scaledScene = both.finalizedScene()
    for (p, s) in zip(slots(plain), slots(scaledScene)) { #expect(s.w > 1.5 * p.w && s.h > 1.5 * p.h, "scaled then projected: slot \(s) of \(p)") }
    #expect(both.glyphsRekeyed == plain.glyphs.count, "scaled then projected: re-keyed \(both.glyphsRekeyed)")
}

// MARK: - 13. animation

/// **13 (`TZ-A`, `TZ-C`).** `scaleEffect` 1 to 2 over 120 ticks rasterizes at most one raster per glyph per rung per subpixel
/// variant (8 rungs by 4 variants, plus the 4 base variants), not one per tick; a steady frame at 2 rasterizes nothing. Mutation
/// **T6**: the exact scale as the raster scale (no ladder): about one raster per tick.
@Test @MainActor func anAnimatingZoomRasterizesEachRungOnce() throws {
    func tree(_ scale: Double) -> some Element { Text("H").font(size: 12).frame(width: px(40), height: px(20)).scaleEffect(scale) }
    let h = ZoomHarness()
    h.frame(tree(1))
    let base = h.system.rasterized
    h.frame(tree(2), t: 0, animation: linear1)
    for i in 1...120 { h.frame(tree(2), t: Double(i) / 120) }
    let during = h.system.rasterized - base
    #expect(during <= 8 * 4, "rasters during the zoom: \(during)")
    #expect(during >= 5, "set up: the zoom crossed its rungs (\(during) rasters)")
    let before = h.system.rasterized
    let steady = h.frame(tree(2), t: 3)
    #expect(h.system.rasterized == before, "a steady frame rasterizes nothing: \(h.system.rasterized - before)")
    #expect(steady.glyphsRekeyed == 1, "the steady frame is re-keyed: \(steady.glyphsRekeyed)")
}

// MARK: - 14. cap

/// **14 (`TZ-C`; probe `Z7`: SwiftUI shows no cap, so the cap is MetalUI's).** `scaleEffect(40)` of 12 pt text: the raster stops at
/// 256 device pixels of em (slot height at most 256) and the slot is resampled by the remainder (`bounds = slot * f / k`).
/// Mutation **T7**: the cap removed (the slot is then about 360 pixels tall).
@Test @MainActor func aScaleBeyondTheCapResamplesTheCapRaster() throws {
    let frame = ZoomHarness().frame(Text("H").font(size: 12).scaleEffect(40))
    let scene = frame.finalizedScene()
    let g = try #require(scene.glyphs.first, "a glyph")
    #expect(g.atlasBounds.size.height <= 256 && g.atlasBounds.size.width <= 256, "slot \(g.atlasBounds.size)")
    #expect(g.bounds.size.height > g.atlasBounds.size.height * 1.5, "resampled by the remainder: \(g.bounds.size) of \(g.atlasBounds.size)")
    let k = pow(2, Double(Int((log2(256.0 / 12.0) * 8).rounded(.down))) / 8)
    let expected = Double(g.atlasBounds.size.width) * 40 / k
    #expect(abs(Double(g.bounds.size.width) - expected) < 0.5, "bounds \(g.bounds.size.width) against slot * 40 / k \(expected)")
    #expect(TextZoom.rasterScale(0.01, emPixels: 12) == 0.25, "the floor is a quarter")
}

// MARK: - 15. refusal

/// **15 (`TZ-C`).** An atlas that cannot grow and has no room for the larger rasters draws every glyph from its base raster and
/// counts the fallback. Mutation **T8**: a refused glyph dropped (the glyph count falls).
@Test @MainActor func aGlyphTheAtlasRefusesFallsBackToItsBaseRaster() throws {
    let text = Text("ABCDEFGHIJ").font(size: 20)
    let plain = ZoomHarness(atlas: GlyphAtlas(width: 256, height: 256)).frame(text).finalizedScene()
    let frame = ZoomHarness(atlas: GlyphAtlas(width: 256, height: 256)).frame(text.scaleEffect(8))
    let scene = frame.finalizedScene()
    #expect(scene.glyphs.count == plain.glyphs.count, "the same glyphs: \(scene.glyphs.count) of \(plain.glyphs.count)")
    #expect(frame.glyphRekeyFallbacks > 0 && frame.glyphsRekeyed > 0, "re-keyed \(frame.glyphsRekeyed), fell back \(frame.glyphRekeyFallbacks)")
    #expect(frame.glyphsRekeyed + frame.glyphRekeyFallbacks == plain.glyphs.count, "every glyph is one or the other")
}

// MARK: - 17. a ghost

/// **17 (`TZ-A`).** A removal ghost half-way through `.scale` is drawn from the 0.5 rung: its slots are about half the settled
/// slots. Mutation **T10**: the ghost inserted with `scene.insert` directly.
@Test @MainActor func aScaleTransitionGhostRekeys() throws {
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { Text("Aa").font(size: 24).transition(.scale) }
            }
        }
    }
    let h = ZoomHarness()
    let rest = h.frame(tree(true)).finalizedScene()
    h.frame(tree(false), t: 0, animation: linear1)
    let mid = h.frame(tree(false), t: 0.5)
    let scene = mid.finalizedScene()
    try #require(!rest.glyphs.isEmpty && scene.glyphs.count == rest.glyphs.count, "set up: the ghost paints its glyphs (\(scene.glyphs.count))")
    for (r, s) in zip(slots(rest), slots(scene)) { #expect(s.w < 0.7 * r.w && s.h < 0.7 * r.h, "slot \(s) against settled \(r)") }
    #expect(mid.glyphsRekeyed == scene.glyphs.count, "re-keyed \(mid.glyphsRekeyed)")
}

// MARK: - 19. no scope

/// **19 (`TZ-A`).** Text at its device scale costs nothing extra: plain, in an opacity group and under a rotation, no frame
/// re-keys or reads the slot-to-key map (`RT-M`). Mutation **T12**: the lookup moved ahead of the rung check, so it also runs for
/// glyphs at their device scale.
@Test @MainActor func plainTextOutsideEveryScopeIsUnchanged() throws {
    func check<E: Element>(_ name: String, _ element: E) {
        let frame = ZoomHarness().frame(element)
        #expect(!frame.scene.glyphs.isEmpty, "\(name): paints glyphs")
        #expect(frame.glyphsRekeyed == 0 && frame.glyphRekeyFallbacks == 0 && frame.glyphRekeyLookups == 0,
                "\(name): \(frame.glyphsRekeyed) \(frame.glyphRekeyFallbacks) \(frame.glyphRekeyLookups)")
    }
    check("plain", label())
    check("opacity", label().opacity(0.5))
    check("rotation", label().rotationEffect(.degrees(20)))
    check("offset", label().offset(x: 10, y: 4))
}

// MARK: - 20. reclaim

/// **20 (`TZ-A`).** After `reclaim()` an old slot names no key; before, it names the key it was packed for. Mutation **T13**: the
/// map not cleared by `reclaim()`.
@Test func reclaimForgetsTheSlotKeys() throws {
    let atlas = GlyphAtlas(width: 64, height: 64)
    let key = GlyphKey(font: FontKey(resolvedPostScriptName: "TZ-Test", size: 12, variations: [], matrix: .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)), glyph: 5, size: 12, subpixelVariant: 0, scaleFactor: 1)
    let image = GlyphImage(width: 4, height: 4, bytes: [UInt8](repeating: 255, count: 16), left: 0, top: 4)
    let packed = try #require(atlas.packed(for: key) { image })
    #expect(atlas.key(forSlot: packed.slot) == key, "the slot names its key")
    atlas.reclaim()
    #expect(atlas.key(forSlot: packed.slot) == nil, "reclaimed: the slot names nothing")
}

// MARK: - 18. gradient text

/// **18 (`TZ-A`, `TG-C`).** A gradient text under `scaleEffect(2)` re-keys the glyphs of its ink mask: the mask scene's slots equal
/// those of real 40 pt gradient text (within 1), not the 20 pt ones. Mutation **T11**: the re-key only for the root scene
/// (skipped in `collectingIntoFreshScene`).
@Test @MainActor func aGradientTextUnderScaleRekeysItsInkMask() throws {
    let sweep = LinearGradient(colors: [Color(Hsla(h: 0, s: 1, l: 0.5, a: 1)), Color(Hsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1))],
                               startPoint: .leading, endPoint: .trailing)
    func blocks(_ size: Double) -> Text { Text("\u{2588}\u{2588}").font(size: size).foregroundStyle(sweep) }
    func maskSlots(_ scene: Scene) -> [(w: Float, h: Float)] {
        scene.groupMasks.compactMap { $0 }.first.map { slots($0) } ?? []
    }
    let native = maskSlots(ZoomHarness().frame(blocks(40)).finalizedScene())
    let plain = maskSlots(ZoomHarness().frame(blocks(20)).finalizedScene())
    let frame = ZoomHarness().frame(blocks(20).scaleEffect(2))
    let scaled = maskSlots(frame.finalizedScene())
    try #require(!native.isEmpty && native.count == scaled.count && plain.count == scaled.count, "set up: a mask of glyphs")
    for (n, s) in zip(native, scaled) { #expect(abs(s.w - n.w) <= 1 && abs(s.h - n.h) <= 1, "mask slot \(s) against real 40 pt \(n)") }
    for (p, s) in zip(plain, scaled) { #expect(s.w > 1.5 * p.w, "mask slot \(s) is not the 20 pt \(p)") }
    #expect(frame.glyphsRekeyed >= scaled.count, "re-keyed \(frame.glyphsRekeyed)")
}
