import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import MetalUIDemoContent
@testable import MetalUI

// Paths, shadows and transforms, lane 2 — render effects in paint (rulings
// `GX-G`, `GX-H`; spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §8,
// tests 2.1–2.9, 2.18–2.26). SwiftUI's side is
// `docs/probes/swiftui-paths-shadows-transforms.swift`, arms T1–T11.
//
// Every arm renders headless `Frame`s (`TransitionHarness`, a 200-point
// square at scale 1 unless it says otherwise — points and device pixels agree)
// and reads the scene: a primitive under a flattened effect has moved bounds
// and transform index 0; one under a record keeps its local bounds and names
// an entry of `scene.transforms`.

// MARK: - Fixtures

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor func isToken(_ c: MUIHsla, _ token: ColorToken) -> Bool {
    let t = Theme.light[token]
    return abs(c.h - t.h) < 0.001 && abs(c.s - t.s) < 0.001 && abs(c.l - t.l) < 0.001 && c.a > 0
}

/// Every rect `frame` painted in `token`, in emission order.
@MainActor func effectRects(_ scene: Scene, _ token: ColorToken = .accent) -> [MUIRect] {
    scene.rects.filter { isToken($0.background, token) }
}

/// The transform record a rect names, or `nil` for index 0.
func effectRecord(_ rect: MUIRect, in scene: Scene) -> MUITransform? {
    let index = Int(rect.transformIndex)
    guard index > 0, index <= scene.transforms.count else { return nil }
    return scene.transforms[index - 1]
}

func fxDescribe(_ b: MUIBounds) -> String {
    "(\(b.origin.x), \(b.origin.y), \(b.size.width)×\(b.size.height))"
}

func fxDescribe(_ t: MUITransform?) -> String {
    guard let t else { return "nil" }
    return "[a \(t.a) b \(t.b) c \(t.c) d \(t.d) tx \(t.tx) ty \(t.ty) s \(t.pixelScale) outer \(fxDescribe(t.outerMask))]"
}

/// A record's affine as an `Affine2D`.
func fxAffine(_ t: MUITransform) -> Affine2D {
    Affine2D(a: Double(t.a), b: Double(t.b), c: Double(t.c), d: Double(t.d), tx: Double(t.tx), ty: Double(t.ty))
}

/// Whether `t` is `expected` within `tolerance` on every coefficient.
func fxMatches(_ t: MUITransform?, _ expected: Affine2D, tolerance: Double = 1e-3) -> Bool {
    guard let t else { return false }
    let a = fxAffine(t)
    return abs(a.a - expected.a) < tolerance && abs(a.b - expected.b) < tolerance
        && abs(a.c - expected.c) < tolerance && abs(a.d - expected.d) < tolerance
        && abs(a.tx - expected.tx) < tolerance && abs(a.ty - expected.ty) < tolerance
}

/// Where `rect`'s four corners land on screen — through its record, if any. A
/// flattened inner effect moves the bounds and an outer record maps them, so
/// two emissions are compared by this, not by their records alone.
func fxQuad(_ rect: MUIRect, in scene: Scene) -> [(Double, Double)] {
    let m = effectRecord(rect, in: scene).map(fxAffine) ?? .identity
    let b = rect.bounds
    let x = Double(b.origin.x), y = Double(b.origin.y), w = Double(b.size.width), h = Double(b.size.height)
    return [m.apply(x, y), m.apply(x + w, y), m.apply(x, y + h), m.apply(x + w, y + h)].map { ($0.x, $0.y) }
}

/// Whether `rect` lands where `expected` maps `plain` (each corner within 1e-3).
func fxLands(_ rect: MUIRect, in scene: Scene, as expected: Affine2D, from plain: MUIBounds) -> Bool {
    let x = Double(plain.origin.x), y = Double(plain.origin.y)
    let w = Double(plain.size.width), h = Double(plain.size.height)
    let want = [expected.apply(x, y), expected.apply(x + w, y), expected.apply(x, y + h), expected.apply(x + w, y + h)]
    let got = fxQuad(rect, in: scene)
    return zip(got, want).allSatisfy { abs($0.0 - $1.x) < 1e-3 && abs($0.1 - $1.y) < 1e-3 }
}

/// One headless frame of `element` in a fresh harness (200 × 200, scale 1).
@MainActor @discardableResult
func effectFrame<E: Element>(_ element: E, side: Float = 200, scaleFactor: Float = 1,
                             accessibility: Bool = false) -> Frame {
    let h = TransitionHarness()
    h.accessibility = accessibility
    return h.frame(0, nil, element, side: side, scaleFactor: scaleFactor)
}

/// A proposal bar of `w × h` filled with `.accent`.
@MainActor func fxBar(_ w: Float = 160, _ h: Float = 20) -> ModifiedContent<Color, LayoutModifier> {
    Color(.accent).frame(width: px(w), height: px(h))
}

/// A legacy box of `w × h` filled with `.accent`.
@MainActor func fxLegacyBar(_ w: Float = 160, _ h: Float = 20) -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(w), height: px(h)).background(.accent)
}

private let deg90 = Angle.degrees(90)
private let linear1 = Animation.linear(duration: 1)

// MARK: - 2.1 (T1, T6b)

/// **2.1** (T1, T6b). `HStack { a.rotationEffect(45°); b }`: `b` paints where
/// it paints with no effect (the layer answers its content's size), and `a`'s
/// rect keeps its own bounds and carries a record rotating 45° about its
/// centre. Red before: no record. Mutation **M2a**: the layer answers the
/// rotated bounding box.
@Test @MainActor func aRotationEffectChangesPaintAndNotLayout() throws {
    func tree(_ angle: Double?) -> some Element {
        HStack(spacing: 0) {
            if let angle { fxBar(100, 20).rotationEffect(.degrees(angle)) } else { fxBar(100, 20) }
            Color(.separator).frame(width: px(40), height: px(20))
        }
    }
    let plain = effectFrame(tree(nil)).finalizedScene()
    let turned = effectFrame(tree(45)).finalizedScene()
    let bPlain = try #require(effectRects(plain, .separator).first)
    let bTurned = try #require(effectRects(turned, .separator).first)
    #expect(fxDescribe(bTurned.bounds) == fxDescribe(bPlain.bounds), "b unmoved: \(fxDescribe(bTurned.bounds))")
    let aPlain = try #require(effectRects(plain).first)
    let a = try #require(effectRects(turned).first)
    #expect(fxDescribe(a.bounds) == fxDescribe(aPlain.bounds), "a keeps its local bounds")
    let record = effectRecord(a, in: turned)
    let cx = Double(a.bounds.origin.x + a.bounds.size.width / 2)
    let cy = Double(a.bounds.origin.y + a.bounds.size.height / 2)
    #expect(fxMatches(record, .rotation(radians: Double.pi / 4, about: cx, cy)),
            "a 45° record about its centre: \(fxDescribe(record))")
    #expect(effectRecord(bTurned, in: turned) == nil, "b untransformed")
}

// MARK: - 2.2 (T2)

/// **2.2** (T2). 90° about `.topLeading` maps local (100, 0) from the anchor
/// to (0, 100) — positive degrees are clockwise in y-down coordinates. Mutation
/// **M2b**: the sign flipped.
@Test @MainActor func positiveDegreesRotateClockwiseAboutTheAnchor() throws {
    let scene = effectFrame(fxBar(100, 20).rotationEffect(deg90, anchor: .topLeading)).finalizedScene()
    let a = try #require(effectRects(scene).first)
    let record = try #require(effectRecord(a, in: scene), "a record")
    let ox = Double(a.bounds.origin.x), oy = Double(a.bounds.origin.y)
    let mapped = fxAffine(record).apply(ox + 100, oy)
    #expect(abs(mapped.x - ox) < 1e-3 && abs(mapped.y - (oy + 100)) < 1e-3,
            "(100, 0) from the anchor lands at (0, 100): \(mapped) from (\(ox), \(oy))")
}

// MARK: - 2.3 (T3, T6)

/// **2.3** (T3, T6). `scaleEffect(2)` and `offset(x: 30, y: 10)` are flattened
/// on the CPU: bounds mapped, transform index 0, `scene.transforms` empty — on
/// both vocabularies. Mutation **M2c**: always a record.
@Test @MainActor func aUniformScaleAndAnOffsetAreFlattenedOnTheCPU() throws {
    let plain = try #require(effectRects(effectFrame(fxBar(40, 20)).finalizedScene()).first)
    let cx = plain.bounds.origin.x + 20, cy = plain.bounds.origin.y + 10

    let scaled = effectFrame(fxBar(40, 20).scaleEffect(2)).finalizedScene()
    let s = try #require(effectRects(scaled).first)
    #expect(fxDescribe(s.bounds) == fxDescribe(MUIBounds(origin: MUIPoint(x: cx - 40, y: cy - 20),
                                                     size: MUISize(width: 80, height: 40))),
            "scale 2 about the centre: \(fxDescribe(s.bounds))")
    #expect(scaled.transforms.isEmpty && s.transformIndex == 0, "flattened: \(scaled.transforms.count)")

    let moved = effectFrame(fxBar(40, 20).offset(x: px(30), y: px(10))).finalizedScene()
    let o = try #require(effectRects(moved).first)
    #expect(o.bounds.origin.x == plain.bounds.origin.x + 30 && o.bounds.origin.y == plain.bounds.origin.y + 10,
            "offset moves the bounds: \(fxDescribe(o.bounds))")
    #expect(moved.transforms.isEmpty, "flattened")

    let legacy = effectFrame(fxLegacyBar(40, 20).offset(x: px(30), y: px(10))).finalizedScene()
    let l = try #require(effectRects(legacy).first)
    #expect(l.bounds.origin.x == plain.bounds.origin.x + 30 && legacy.transforms.isEmpty,
            "the legacy offset is flattened too: \(fxDescribe(l.bounds))")
}

// MARK: - 2.4 (T4, T5)

/// **2.4** (T4, T5). A non-uniform scale, a negative (flipping) scale and a
/// rotation are records; the bounds stay local. Mutation **M2d**: a non-uniform
/// scale flattened.
@Test @MainActor func aNonUniformNegativeOrRotatingEffectIsARecord() throws {
    let plain = try #require(effectRects(effectFrame(fxBar(40, 20)).finalizedScene()).first)
    func check(_ name: String, _ element: some Element) throws {
        let scene = effectFrame(element).finalizedScene()
        let r = try #require(effectRects(scene).first, "\(name)")
        #expect(effectRecord(r, in: scene) != nil, "\(name): a record")
        #expect(fxDescribe(r.bounds) == fxDescribe(plain.bounds), "\(name): local bounds \(fxDescribe(r.bounds))")
    }
    try check("x2 y0.5", fxBar(40, 20).scaleEffect(x: 2, y: 0.5))
    try check("x -1", fxBar(40, 20).scaleEffect(x: -1))
    try check("−1", fxBar(40, 20).scaleEffect(-1))
    try check("30°", fxBar(40, 20).rotationEffect(.degrees(30)))
    let squash = effectFrame(fxBar(40, 20).scaleEffect(x: 2, y: 0.5)).finalizedScene()
    let r = try #require(effectRects(squash).first)
    let cx = Double(plain.bounds.origin.x + 20), cy = Double(plain.bounds.origin.y + 10)
    #expect(fxMatches(effectRecord(r, in: squash), .scale(x: 2, y: 0.5, about: cx, cy)),
            "T4's map about the centre: \(fxDescribe(effectRecord(r, in: squash)))")
}

// MARK: - 2.5 (T4b, T6c)

/// **2.5** (T4b, T6c). `scaleEffect(SizeD(2, 0.5))` draws exactly what
/// `scaleEffect(x: 2, y: 0.5)` does, and `offset(Size(30, 10))` what
/// `offset(x: 30, y: 10)` does. Mutation **M2e**: the size forms drop `height`.
@Test @MainActor func scaleEffectSizeEqualsXYAndOffsetSizeEqualsXY() throws {
    func record(_ e: some Element) throws -> String {
        let scene = effectFrame(e).finalizedScene()
        let r = try #require(effectRects(scene).first)
        return fxDescribe(r.bounds) + fxDescribe(effectRecord(r, in: scene))
    }
    let sizeForm = try record(fxBar(40, 20).scaleEffect(SizeD(width: 2, height: 0.5)))
    let xy = try record(fxBar(40, 20).scaleEffect(x: 2, y: 0.5))
    let widthOnly = try record(fxBar(40, 20).scaleEffect(x: 2, y: 1))
    try #require(xy != widthOnly, "the arms must disagree")
    #expect(sizeForm == xy, "size form \(sizeForm) vs x:y: \(xy)")
    let offsetSize = try record(fxBar(40, 20).offset(Size(width: px(30), height: px(10))))
    let offsetXY = try record(fxBar(40, 20).offset(x: px(30), y: px(10)))
    let offsetX = try record(fxBar(40, 20).offset(x: px(30)))
    try #require(offsetXY != offsetX, "the offset arms must disagree")
    #expect(offsetSize == offsetXY, "offset size \(offsetSize) vs x:y: \(offsetXY)")
    let legacySize = try record(fxLegacyBar(40, 20).scaleEffect(SizeD(width: 2, height: 0.5)))
    let legacyXY = try record(fxLegacyBar(40, 20).scaleEffect(x: 2, y: 0.5))
    #expect(legacySize == legacyXY, "legacy size form \(legacySize) vs \(legacyXY)")
}

// MARK: - 2.6 (T5b)

/// **2.6** (T5b). `scaleEffect(0)` draws nothing; `scaleEffect(1)` draws the
/// bar. Mutation **M2f**: a zero scale emitted.
@Test @MainActor func aZeroScaleDrawsNothing() throws {
    let one = effectFrame(fxBar(40, 20).scaleEffect(1)).finalizedScene()
    try #require(effectRects(one).count == 1, "control: scale 1 draws the bar")
    let zero = effectFrame(fxBar(40, 20).scaleEffect(0)).finalizedScene()
    #expect(effectRects(zero).isEmpty, "scale 0 draws nothing: \(effectRects(zero).map { fxDescribe($0.bounds) })")
    let legacyZero = effectFrame(fxLegacyBar(40, 20).scaleEffect(x: 0, y: 1)).finalizedScene()
    #expect(effectRects(legacyZero).isEmpty, "a legacy zero factor draws nothing")
}

// MARK: - 2.7 (T11)

/// **2.7** (T11). Rotation-then-offset is `T · R`, offset-then-rotation
/// `R · T` (R about the layer's own centre, which an offset does not move) —
/// the bar's corners land where those matrices put them, on both vocabularies
/// (an inner offset is flattened into the bounds, so corners, not records,
/// are compared). Mutation
/// **M2g**: composition reversed.
@Test @MainActor func effectsComposeInWrittenOrder() throws {
    let plain = try #require(effectRects(effectFrame(fxBar(100, 20)).finalizedScene()).first)
    let cx = Double(plain.bounds.origin.x + 50), cy = Double(plain.bounds.origin.y + 10)
    let r = Affine2D.rotation(radians: Double.pi / 4, about: cx, cy)
    let t = Affine2D.translation(x: 30, y: 0)
    let rotateThenOffset = t.concatenating(r), offsetThenRotate = r.concatenating(t)
    try #require(!(abs(rotateThenOffset.tx - offsetThenRotate.tx) < 1e-3
                   && abs(rotateThenOffset.ty - offsetThenRotate.ty) < 1e-3), "the predictions disagree")
    func lands(_ e: some Element, as expected: Affine2D) throws -> Bool {
        let scene = effectFrame(e).finalizedScene()
        return fxLands(try #require(effectRects(scene).first), in: scene, as: expected, from: plain.bounds)
    }
    #expect(try lands(fxBar(100, 20).rotationEffect(.degrees(45)).offset(x: px(30)), as: rotateThenOffset),
            "proposal rotation then offset")
    #expect(try lands(fxBar(100, 20).offset(x: px(30)).rotationEffect(.degrees(45)), as: offsetThenRotate),
            "proposal offset then rotation")
    #expect(try lands(fxLegacyBar(100, 20).rotationEffect(.degrees(45)).offset(x: px(30)), as: rotateThenOffset),
            "legacy rotation then offset")
    #expect(try lands(fxLegacyBar(100, 20).offset(x: px(30)).rotationEffect(.degrees(45)), as: offsetThenRotate),
            "legacy offset then rotation")
}

// MARK: - 2.8 (T7, T7b)

/// **2.8** (T7, T7b). A clip written inside a rotation turns with it — the
/// rect's `contentMask` is the clip in local space and the record's outer mask
/// the surface — and one written outside stays: the outer mask is the clip in
/// screen space and the local mask unbounded. Mutation **M2h**: the clip not
/// split at the effect's entry.
@Test @MainActor func aClipInsideAnEffectTurnsWithItAndOneOutsideStays() throws {
    let inside = effectFrame(fxBar(40, 20).clipped().rotationEffect(deg90)).finalizedScene()
    let a = try #require(effectRects(inside).first)
    let ra = try #require(effectRecord(a, in: inside), "inside: a record")
    #expect(fxDescribe(a.contentMask) == fxDescribe(a.bounds), "inside: the local mask is the clip: \(fxDescribe(a.contentMask))")
    #expect(ra.outerMask.size.width >= 200 && ra.outerMask.size.height >= 200,
            "inside: the outer mask is the surface: \(fxDescribe(ra.outerMask))")

    let outside = effectFrame(fxBar(40, 20).rotationEffect(deg90).clipped()).finalizedScene()
    let b = try #require(effectRects(outside).first)
    let rb = try #require(effectRecord(b, in: outside), "outside: a record")
    #expect(fxDescribe(rb.outerMask) == fxDescribe(b.bounds), "outside: the outer mask is the clip on screen: \(fxDescribe(rb.outerMask))")
    #expect(b.contentMask.size.width > 10_000, "outside: the local mask is unbounded: \(fxDescribe(b.contentMask))")
}

// MARK: - 2.9 (T8)

/// **2.9** (T8). A background written after a proposal effect is outside it
/// (index 0); one written before is inside (a record). Mutation **M2i**: the
/// scope pushed around the whole chain.
@Test @MainActor func aBackgroundAfterAProposalEffectIsNotTransformed() throws {
    let after = effectFrame(fxBar(40, 20).rotationEffect(deg90).background(.separator)).finalizedScene()
    let bgAfter = try #require(effectRects(after, .separator).first)
    let barAfter = try #require(effectRects(after).first)
    #expect(effectRecord(bgAfter, in: after) == nil, "after: the background untransformed")
    #expect(effectRecord(barAfter, in: after) != nil, "after: the bar rotated")
    let before = effectFrame(fxBar(40, 20).background(.separator).rotationEffect(deg90)).finalizedScene()
    let bgBefore = try #require(effectRects(before, .separator).first)
    #expect(effectRecord(bgBefore, in: before) != nil, "before: the background rotated too")
}

// MARK: - 2.18

/// **2.18**. A removal ghost of rotated content replays its transform: the
/// ghost's rect names a record equal to the live frame's. Mutation **M2p**:
/// `CapturedPrimitive` drops its transform.
@Test @MainActor func aGhostOfRotatedContentReplaysItsTransform() throws {
    func stage(_ shown: Bool) -> some Element {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown { fxLegacyBar(50, 30).rotationEffect(.degrees(30)).transition(.opacity) }
        }
    }
    let h = TransitionHarness()
    let rest = h.frame(0, nil, stage(true), side: 300).finalizedScene()
    let live = try #require(effectRects(rest).first)
    let liveRecord = try #require(effectRecord(live, in: rest), "set up: the live tile is rotated")
    _ = h.frame(0, linear1, stage(false), side: 300)
    let mid = h.frame(0.5, nil, stage(false), side: 300).finalizedScene()
    let ghost = try #require(effectRects(mid).first, "a ghost half-way")
    let ghostRecord = effectRecord(ghost, in: mid)
    #expect(fxMatches(ghostRecord, fxAffine(liveRecord)), "the ghost turns as the live tile did: \(fxDescribe(ghostRecord))")
    #expect(abs(ghost.background.a - live.background.a * 0.5) < 0.01, "and fades: \(ghost.background.a)")
}

// MARK: - 2.19

/// **2.19**. A drag preview of rotated content replays its transform composed
/// with the preview's translation. Mutation **M2p**.
@Test @MainActor func aDragPreviewOfRotatedContentReplaysItsTransform() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        Row {
            Box().frame(width: px(200), height: px(200)).background(.accent)
                .rotationEffect(.degrees(30)).draggable("s")
            Box().frame(width: px(200), height: px(200))
        }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateResize(to: Size(width: px(400), height: px(200)))
    window.drawFrameIfNeeded()
    let source = try #require(effectRects(window.lastScene).first)
    let sourceRecord = try #require(effectRecord(source, in: window.lastScene), "set up: the source is rotated")
    func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(100, 100))))
    platform.simulateInput(.mouseDragged(MouseEvent(position: pt(101, 100))))
    platform.simulateInput(.mouseDragged(MouseEvent(position: pt(150, 100))))
    window.drawFrameIfNeeded()
    let rects = effectRects(window.lastScene)
    try #require(rects.count == 2, "the source and its preview: \(rects.count)")
    let preview = rects[1]
    let expected = Affine2D.translation(x: 50, y: 0).concatenating(fxAffine(sourceRecord))
    #expect(fxMatches(effectRecord(preview, in: window.lastScene), expected),
            "the preview turns and moves: \(fxDescribe(effectRecord(preview, in: window.lastScene)))")
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(150, 100))))
}

// MARK: - 2.20

/// **2.20** (`GX-G`). A `Deferred` inside a rotated element is not rotated: its
/// primitives name index 0 and its hitboxes store no transform, while a
/// sibling outside the `Deferred` is rotated. Mutation **M2q**: `Deferred`
/// keeps the stack.
@Test @MainActor func aDeferredInsideAnEffectIsNotTransformed() throws {
    let frame = effectFrame(
        Column {
            Box().frame(width: px(60), height: px(20)).background(.separator).onClick {}
            Deferred { Box().frame(width: px(50), height: px(30)).background(.accent).onClick {} }
        }
        .frame(width: px(160), height: px(100))
        .rotationEffect(.degrees(30)))
    let scene = frame.finalizedScene()
    let sibling = try #require(effectRects(scene, .separator).first)
    try #require(effectRecord(sibling, in: scene) != nil, "control: the sibling is rotated")
    let portal = try #require(effectRects(scene).first)
    #expect(effectRecord(portal, in: scene) == nil, "the portal's rect is not rotated")
    let clickable = frame.hitboxes.filter { $0.handlers.onClick != nil }
    try #require(clickable.count == 2, "two click targets: \(clickable.count)")
    #expect(clickable[0].transform != nil, "the sibling's hitbox is transformed")
    #expect(clickable[1].transform == nil, "the portal's hitbox is plain")
}

// MARK: - 2.21

/// **2.21** (`GX-G`). The demo through a `Window` pushes no effect scope and
/// its scene has no transform; a tree with one effect pushes some. Mutation
/// **M2r**: a scope pushed for every element.
@Test @MainActor func aTreeWithoutEffectsPushesNoScope() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (control, _) = try makeFakeWindow(device: device, size: 200) { fxBar(40, 20).rotationEffect(deg90) }
    control.drawFrameIfNeeded()
    try #require(control.lastEffectScopesPushed > 0, "control: an effect pushes a scope")
    let (window, _) = try makeFakeWindow(device: device, size: 800) { demoContent() }
    window.drawFrameIfNeeded()
    #expect(window.lastEffectScopesPushed == 0, "the demo pushes none: \(window.lastEffectScopesPushed)")
    #expect(window.lastScene.transforms.isEmpty, "and records no transform")
}

// MARK: - 2.22

/// **2.22** (`GX-H`). The legacy vocabulary keeps written order among effects
/// (`rotation.offset` ≠ `offset.rotation`, each the predicted matrix) and moves
/// no id: the click target's id equals the effect-free tree's. Mutation
/// **M2s**: the list sorted.
@Test @MainActor func theLegacyVocabularyKeepsWrittenOrderAmongEffectsAndMovesNoID() throws {
    let plainFrame = effectFrame(fxLegacyBar(100, 20).onClick {})
    let plain = try #require(effectRects(plainFrame.finalizedScene()).first)
    let cx = Double(plain.bounds.origin.x + 50), cy = Double(plain.bounds.origin.y + 10)
    let r = Affine2D.rotation(radians: Double.pi / 4, about: cx, cy)
    let t = Affine2D.translation(x: 30, y: 0)
    let f1 = effectFrame(fxLegacyBar(100, 20).onClick {}.rotationEffect(.degrees(45)).offset(x: px(30)))
    let f2 = effectFrame(fxLegacyBar(100, 20).onClick {}.offset(x: px(30)).rotationEffect(.degrees(45)))
    let s1 = f1.finalizedScene(), s2 = f2.finalizedScene()
    #expect(fxLands(try #require(effectRects(s1).first), in: s1, as: t.concatenating(r), from: plain.bounds),
            "rotation then offset")
    #expect(fxLands(try #require(effectRects(s2).first), in: s2, as: r.concatenating(t), from: plain.bounds),
            "offset then rotation")
    let ids = [plainFrame, f1, f2].map { $0.hitboxes.filter { $0.handlers.onClick != nil }.map(\.id) }
    #expect(ids[0].count == 1 && ids[1] == ids[0] && ids[2] == ids[0], "no id moves: \(ids)")
}

// MARK: - 2.23 (divergence 108)

/// **2.23** (divergence 108). A legacy effect wraps the whole element whatever
/// the written order: a background written after the effect is still
/// transformed, and so is a border. Mutation **M2t**: the background excluded.
@Test @MainActor func aLegacyEffectWrapsTheWholeElementWhateverTheOrder() throws {
    let after = effectFrame(Box().frame(width: px(40), height: px(20)).rotationEffect(deg90).background(.accent))
        .finalizedScene()
    let a = try #require(effectRects(after).first)
    #expect(effectRecord(a, in: after) != nil, "a background written after the effect is rotated")
    let bordered = effectFrame(Box().frame(width: px(40), height: px(20)).background(.accent)
        .border(.separator, width: px(2)).rotationEffect(deg90)).finalizedScene()
    let ring = try #require(bordered.rects.first { $0.borderWidths.top > 0 }, "the border ring")
    #expect(effectRecord(ring, in: bordered) != nil, "the border is rotated too")
}

// MARK: - 2.24 (divergence 109)

/// **2.24** (divergence 109). A clip between two nested rotations becomes its
/// screen bounding box: the 40 × 20 clip under the outer 90° is the 20 × 40
/// rect about the same centre, and that is the composed record's outer mask.
/// Mutation **M2u**: the middle clip dropped.
@Test @MainActor func aClipBetweenTwoNestedRotationsIsItsScreenBoundingBox() throws {
    let scene = effectFrame(fxBar(40, 20).rotationEffect(deg90).clipped().rotationEffect(deg90)).finalizedScene()
    let r = try #require(effectRects(scene).first)
    let record = try #require(effectRecord(r, in: scene), "a record")
    let cx = r.bounds.origin.x + 20, cy = r.bounds.origin.y + 10
    let expected = MUIBounds(origin: MUIPoint(x: cx - 10, y: cy - 20), size: MUISize(width: 20, height: 40))
    #expect(abs(record.outerMask.origin.x - expected.origin.x) < 1e-3
                && abs(record.outerMask.origin.y - expected.origin.y) < 1e-3
                && abs(record.outerMask.size.width - 20) < 1e-3 && abs(record.outerMask.size.height - 40) < 1e-3,
            "the outer mask is the clip's screen bounding box: \(fxDescribe(record.outerMask))")
    #expect(fxMatches(record, .rotation(radians: Double.pi, about: Double(cx), Double(cy))), "180° in all")
}

// MARK: - 2.25 (MC-C)

/// **2.25** (`MC-A`/`MC-C`). A proposal effect is one identity level: the
/// content's ids under `.rotationEffect` equal those under a one-layer
/// `.padding(0)` chain, and differ from the bare content's. Mutation **M2v**:
/// the layer not counted.
@Test @MainActor func aProposalEffectIsOneIdentityLevel() throws {
    // Inside a stack, not at the root: the root has no parent, so a layer that
    // handed its content its parent's level would give the root's own id
    // back and could not be told apart (M2v's first spelling stayed green).
    func tapIDs(_ e: some ProposalElementGroup) -> [GlobalElementID] {
        effectFrame(VStack { e }).hitboxes.filter { $0.handlers.gestures.count > 0 }.map(\.id)
    }
    let bare = tapIDs(fxBar(40, 20).onTapGesture {})
    let padded = tapIDs(fxBar(40, 20).onTapGesture {}.padding(Edges(all: px(0))))
    let rotated = tapIDs(fxBar(40, 20).onTapGesture {}.rotationEffect(deg90))
    let scaled = tapIDs(fxBar(40, 20).onTapGesture {}.scaleEffect(2))
    let moved = tapIDs(fxBar(40, 20).onTapGesture {}.offset(x: px(3)))
    try #require(bare.count == 1 && padded.count == 1 && bare != padded, "the arms disagree: \(bare) \(padded)")
    #expect(rotated == padded && scaled == padded && moved == padded,
            "one level each: \(rotated) \(scaled) \(moved) vs \(padded)")
}

// MARK: - 2.26 (GX-R item 2)

/// **2.26** (`GX-R` item 2). The `.scale` and `.move` transitions' emitted
/// rects half-way, at scale 2, equal literals recorded at `dc96395`'s
/// arithmetic: generalizing `TransitionEffect` into `RenderEffect` moved no
/// byte. Green on arrival (a pin). Mutation **M2w′**: the transition's affine
/// composes its translation before its scale.
@Test @MainActor func aTransitionsCapturedBytesDoNotMove() throws {
    func stage(_ shown: Bool, _ transition: AnyTransition) -> some Element {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown {
                Box().frame(width: px(50), height: px(30)).background(.accent).cornerRadius(px(6))
                    .border(.separator, width: px(3)).transition(transition)
            }
        }
    }
    func midway(_ transition: AnyTransition) -> String {
        let h = TransitionHarness()
        h.frame(0, nil, stage(false, transition), side: 300, scaleFactor: 2)
        h.frame(0, linear1, stage(true, transition), side: 300, scaleFactor: 2)
        let scene = h.frame(0.5, nil, stage(true, transition), side: 300, scaleFactor: 2).finalizedScene()
        return scene.rects.filter { $0.background.a > 0 || $0.borderWidths.top > 0 }.map {
            "\(fxDescribe($0.bounds)) r\($0.cornerRadii.topLeft) w\($0.borderWidths.top) m\(fxDescribe($0.contentMask))"
        }.joined(separator: " | ")
    }
    let scale = midway(.scale(scale: 0.5, anchor: .bottomTrailing))
    let move = midway(.move(edge: .leading))
    let both = midway(AnyTransition.scale.combined(with: .offset(x: px(10), y: px(4))))
    #expect(scale == "(275.0, 285.0, 75.0×45.0) r9.0 w0.0 m(0.0, 0.0, 600.0×600.0) | (275.0, 285.0, 75.0×45.0) r9.0 w4.5 m(0.0, 0.0, 600.0×600.0)", "scale: \(scale)")
    #expect(move == "(200.0, 270.0, 100.0×60.0) r12.0 w0.0 m(0.0, 0.0, 600.0×600.0) | (200.0, 270.0, 100.0×60.0) r12.0 w6.0 m(0.0, 0.0, 600.0×600.0)", "move: \(move)")
    #expect(both == "(285.0, 289.0, 50.0×30.0) r6.0 w0.0 m(0.0, 0.0, 600.0×600.0) | (285.0, 289.0, 50.0×30.0) r6.0 w3.0 m(0.0, 0.0, 600.0×600.0)", "both: \(both)")
}

// MARK: - LF-a (GX-X): a clip inside a flattening effect

/// The LF-a stage (`GX-X`): a 100 × 100 clip at (50, 50) — `.frame` then
/// `.clipped()` — around a `ZStack` whose content is `inner`. The window is the
/// 200-point square at scale 1, so points are device pixels.
@MainActor private func lfaStage<C: Element>(_ inner: C) -> some Element {
    ZStack(alignment: .topLeading) { inner }
        .frame(width: px(100), height: px(100)).clipped().padding(px(50))
}

private func lfaBounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> String {
    fxDescribe(MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h)))
}

/// **LF-a 1** (`GX-X`, MetalCreator's repro). A 40 × 40 bar at (80, 80) with
/// its own `.clipped()`, moved up 60 by an `.offset` inside the 100 × 100 clip
/// at (50, 50): it paints at (80, 20), and its mask is its own clip moved with
/// it **cut by the clip outside the effect** — (80, 50) 40 × 10, not (80, 20)
/// 40 × 40. Both vocabularies (a legacy effect wraps the whole element, its
/// `.clipped()` included, divergence 108; the legacy clip is a `Box`'s over its
/// bar child). Red before: the mask (80, 20)
/// 40 × 40 on both arms. Mutation **M-X1**: the flattened inner mask not cut by
/// the entry clip.
@Test @MainActor func aClipInsideAnOffsetIsStillCutByTheClipOutsideIt() throws {
    let control = effectFrame(lfaStage(fxBar(40, 40).offset(x: px(0), y: px(-60)))).finalizedScene()
    let c = try #require(effectRects(control).first, "control: the bar")
    try #require(fxDescribe(c.bounds) == lfaBounds(80, 20, 40, 40), "control: the bar at \(fxDescribe(c.bounds))")
    try #require(fxDescribe(c.contentMask) == lfaBounds(50, 50, 100, 100),
                 "control: no inner clip, the outer one: \(fxDescribe(c.contentMask))")

    let proposal = effectFrame(lfaStage(fxBar(40, 40).clipped().offset(x: px(0), y: px(-60)))).finalizedScene()
    let p = try #require(effectRects(proposal).first, "proposal: the bar")
    #expect(fxDescribe(p.bounds) == lfaBounds(80, 20, 40, 40), "proposal: moved: \(fxDescribe(p.bounds))")
    #expect(fxDescribe(p.contentMask) == lfaBounds(80, 50, 40, 10),
            "proposal: the inner clip cut by the outer one: \(fxDescribe(p.contentMask))")
    #expect(proposal.transforms.isEmpty, "proposal: still flattened")

    let legacy = effectFrame(lfaStage(Box { fxLegacyBar(40, 40) }.frame(width: px(40), height: px(40)).clipped().offset(x: px(0), y: px(-60)))).finalizedScene()
    let l = try #require(effectRects(legacy).first, "legacy: the bar")
    #expect(fxDescribe(l.bounds) == lfaBounds(80, 20, 40, 40), "legacy: moved: \(fxDescribe(l.bounds))")
    #expect(fxDescribe(l.contentMask) == lfaBounds(80, 50, 40, 10),
            "legacy: the inner clip cut by the outer one: \(fxDescribe(l.contentMask))")
}

/// **LF-a 2** (`GX-X`). The same bar under `.scaleEffect(4)` about its centre
/// (100, 100): bounds (20, 20) 160 × 160, mask the outer clip (50, 50)
/// 100 × 100 — its own clip scaled with it, then cut. Both vocabularies. Red
/// before: the mask (20, 20) 160 × 160. Mutation **M-X1**.
@Test @MainActor func aClipInsideAUniformScaleIsStillCutByTheClipOutsideIt() throws {
    let proposal = effectFrame(lfaStage(fxBar(40, 40).clipped().scaleEffect(4))).finalizedScene()
    let p = try #require(effectRects(proposal).first, "proposal: the bar")
    #expect(fxDescribe(p.bounds) == lfaBounds(20, 20, 160, 160), "proposal: scaled: \(fxDescribe(p.bounds))")
    #expect(fxDescribe(p.contentMask) == lfaBounds(50, 50, 100, 100),
            "proposal: cut by the outer clip: \(fxDescribe(p.contentMask))")

    let legacy = effectFrame(lfaStage(Box { fxLegacyBar(40, 40) }.frame(width: px(40), height: px(40)).clipped().scaleEffect(4))).finalizedScene()
    let l = try #require(effectRects(legacy).first, "legacy: the bar")
    #expect(fxDescribe(l.bounds) == lfaBounds(20, 20, 160, 160), "legacy: scaled: \(fxDescribe(l.bounds))")
    #expect(fxDescribe(l.contentMask) == lfaBounds(50, 50, 100, 100),
            "legacy: cut by the outer clip: \(fxDescribe(l.contentMask))")
}

/// **LF-a 3** (`GX-X`). An effect in an effect: the bar's clip inside two
/// `.offset(y: -30)`s ends at (80, 20) and is cut by the clip outside both —
/// (80, 50) 40 × 10. Red before: (80, 20) 40 × 40. Mutation **M-X1**.
@Test @MainActor func aClipInsideNestedFlatteningEffectsIsCutByTheClipOutsideBoth() throws {
    let scene = effectFrame(lfaStage(fxBar(40, 40).clipped().offset(x: px(0), y: px(-30))
        .offset(x: px(0), y: px(-30)))).finalizedScene()
    let r = try #require(effectRects(scene).first, "the bar")
    #expect(fxDescribe(r.bounds) == lfaBounds(80, 20, 40, 40), "moved 60: \(fxDescribe(r.bounds))")
    #expect(fxDescribe(r.contentMask) == lfaBounds(80, 50, 40, 10),
            "cut by the outer clip: \(fxDescribe(r.contentMask))")
}

/// **LF-a 4** (`GX-X`). The other half of the same mistake: content laid out
/// **outside** the outer clip (a 220-tall `ZStack` overflowing the 100 × 100
/// frame puts the bar at (50, −10)) and moved **into** it by `.offset(y: 80)`
/// paints at (50, 70), its own clip moved with it — (50, 70) 40 × 40. Red
/// before: the inner clip was intersected with the outer one in the content's
/// pre-effect space, an empty mask (50, 50) 40 × 0, so the bar drew nothing.
/// Mutation **M-X2**: the clip not split at a flattening effect's entry.
@Test @MainActor func contentMovedIntoTheOuterClipByAnOffsetKeepsItsOwnClip() throws {
    let scene = effectFrame(lfaStage(ZStack(alignment: .topLeading) {
        Color.clear.frame(width: px(100), height: px(220))
        fxBar(40, 40).clipped().offset(x: px(0), y: px(80))
    })).finalizedScene()
    let r = try #require(effectRects(scene).first, "the bar")
    #expect(fxDescribe(r.bounds) == lfaBounds(50, 70, 40, 40), "moved in: \(fxDescribe(r.bounds))")
    #expect(fxDescribe(r.contentMask) == lfaBounds(50, 70, 40, 40),
            "its own clip, moved with it: \(fxDescribe(r.contentMask))")
}

/// **LF-a 5** (`GX-X`). A transformed primitive's outer mask follows the same
/// rule: a rotated bar with a `.clipped()` outside the rotation and inside an
/// `.offset(y: -60)` names a record whose outer mask is that clip moved up 60
/// and cut by the clip outside the offset — (80, 50) 40 × 10. Red before:
/// (80, 20) 40 × 40. Mutation **M-X3**: the transform branch's mapped outer
/// mask not cut.
@Test @MainActor func aRecordsOuterMaskInsideAnOffsetIsCutByTheClipOutsideIt() throws {
    let scene = effectFrame(lfaStage(fxBar(40, 40).rotationEffect(deg90).clipped()
        .offset(x: px(0), y: px(-60)))).finalizedScene()
    let r = try #require(effectRects(scene).first, "the bar")
    let record = try #require(effectRecord(r, in: scene), "a record")
    #expect(fxDescribe(record.outerMask) == lfaBounds(80, 50, 40, 10),
            "the outer mask cut by the outer clip: \(fxDescribe(record.outerMask))")
}

// MARK: - The merge with C10 (`GX-X` × `LK-J`/`LK-K`)

/// Where an image run can draw: its quad cut by its mask.
private func lfaVisible(_ image: MUIImage) -> String {
    let b = image.bounds, m = image.contentMask
    let x0 = max(b.origin.x, m.origin.x), y0 = max(b.origin.y, m.origin.y)
    let x1 = min(b.origin.x + b.size.width, m.origin.x + m.size.width)
    let y1 = min(b.origin.y + b.size.height, m.origin.y + m.size.height)
    return lfaBounds(x0, y0, max(0, x1 - x0), max(0, y1 - y0))
}

/// **LF-a merge 1** (`GX-X` × `LK-J`). A gradient-filled 40 × 40 rectangle
/// with its own `.clipped()`, moved up 60 by an `.offset` inside the 100 × 100
/// clip at (50, 50), draws only inside (80, 50) 40 × 10 — its own clip moved
/// with it and cut by the clip outside the effect — on both raster paths (the
/// axis-aligned strip and the diagonal full raster). Red without
/// `cutToEntryClip`'s `.gradient` arm: (80, 20) 40 × 40.
@Test @MainActor func aClippedGradientInsideAnOffsetIsCutByTheClipOutsideIt() throws {
    for (name, gradient) in [
        ("strip", LinearGradient(colors: [lkRed, lkBlue], startPoint: .top, endPoint: .bottom)),
        ("full", LinearGradient(colors: [lkRed, lkBlue], startPoint: .topLeading, endPoint: .bottomTrailing)),
    ] {
        let scene = effectFrame(lfaStage(Rectangle().fill(gradient).frame(width: px(40), height: px(40))
            .clipped().offset(x: px(0), y: px(-60)))).finalizedScene()
        let images = gxImages(scene)
        try #require(images.count == 1, "\(name): one image")
        #expect(lfaVisible(images[0].image) == lfaBounds(80, 50, 40, 10),
                "\(name): cut by the outer clip: quad \(fxDescribe(images[0].image.bounds)) mask \(fxDescribe(images[0].image.contentMask))")
        #expect(scene.transforms.isEmpty, "\(name): still flattened")
    }
}

/// **LF-a merge 2** (`GX-X` × `LK-K`). A `.blur(radius: 4)`-ed 40 × 40 square
/// with a `.clipped()` outside the blur, moved up 60 by an `.offset` inside
/// the 100 × 100 clip at (50, 50): the blur's image is cut by its own clip
/// moved with it and then by the clip outside the effect — it draws only
/// inside (80, 50) 40 × 10. Red without `cutToEntryClip`'s `.blur` arm:
/// (80, 20) 40 × 40.
@Test @MainActor func aClippedBlurInsideAnOffsetIsCutByTheClipOutsideIt() throws {
    let scene = effectFrame(lfaStage(Color(white: 0).frame(width: px(40), height: px(40))
        .blur(radius: px(4)).clipped().offset(x: px(0), y: px(-60)))).finalizedScene()
    let images = gxImages(scene)
    try #require(images.count == 1, "one image")
    #expect(lfaVisible(images[0].image) == lfaBounds(80, 50, 40, 10),
            "cut by the outer clip: quad \(fxDescribe(images[0].image.bounds)) mask \(fxDescribe(images[0].image.contentMask))")
    #expect(scene.transforms.isEmpty, "still flattened")
}

/// **LF-a merge 3** (`GX-X` × `LK-K`, the other nesting). An `.offset` inside
/// a blur scope: the square's own clip, moved up 60 and cut by the clip outside
/// the offset, shapes the leaf **before** it is blurred — a 40 × 10 band at
/// (80, 50) — and the blur's image is cut by the clip at the blur's entry,
/// (50, 50) 100 × 100. So 2.5 below the band's top edge reads half-dark, not
/// the black of a 40-tall leaf, and nothing draws above y 50. Red under
/// `GX-X`'s **M-X1** (the rect arm not cut): the band 40 tall.
@Test @MainActor func anOffsetInsideABlurIsCutBeforeItBlurs() throws {
    let scene = effectFrame(lfaStage(Color(white: 0).frame(width: px(40), height: px(40))
        .clipped().offset(x: px(0), y: px(-60)).blur(radius: px(4)))).finalizedScene()
    let images = gxImages(scene)
    try #require(images.count == 1, "one image")
    let v = images[0].image
    #expect(v.bounds.origin.y >= 50 || v.contentMask.origin.y >= 50,
            "nothing above the outer clip: quad \(fxDescribe(v.bounds)) mask \(fxDescribe(v.contentMask))")
    // Measured on the merge: 74, 53, 93, 255 — a 10-tall band blurred.
    for (y, want) in [(52.5, 74), (55.5, 53), (58.5, 93), (75.5, 255)] {
        let got = lkComposite(scene, 100.5, y)[0]
        #expect(abs(got - want) <= 8, "y \(y): \(got) vs \(want)")
    }
}

// MARK: - LF-b (GX-Y): a clip inside NESTED flattening effects

/// The LF-b stage (`GX-Y`, MetalCreator's node canvas): in the 400-point
/// window, a 40-tall top bar and 20 of padding put a 300 × 320 canvas at
/// (20, 60), `.clipped()` — the clip C. Inside it a `ZStack` of `nodes` (each
/// 60 × 40 at the canvas origin before its own effects) under the canvas's
/// **outer** flattening effect, `.scaleEffect(zoom, anchor: .topLeading)` then
/// `.offset(pan)`; each node carries its own **inner** flattening `.offset`.
/// So the outer map is x' = 20 + zoom(x − 20) + pan.x, y' = 60 + zoom(y − 60) + pan.y.
@MainActor private func lfbCanvas<N: ProposalElementGroup>(zoom: Double, pan: (Float, Float),
                                                         @ProposalContentBuilder _ nodes: () -> N) -> some Element {
    VStack(alignment: .leading, spacing: px(0)) {
        Color.clear.frame(width: px(360), height: px(40))
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: px(300), height: px(320))
            ZStack(alignment: .topLeading) { nodes() }
                .scaleEffect(zoom, anchor: .topLeading).offset(x: px(pan.0), y: px(pan.1))
        }.clipped()
    }.padding(Edges(all: px(20)))
}

/// A proposal node: a 60 × 40 bar clipped to a radius-6 rounded rectangle,
/// then moved by its own `.offset`.
@MainActor private func lfbNode(_ x: Float, _ y: Float) -> some ProposalElementGroup {
    fxBar(60, 40).clipShape(RoundedRectangle(cornerRadius: px(6))).offset(x: px(x), y: px(y))
}

/// The same node in the legacy vocabulary: a `Box`'s rounded clip over its bar
/// child, the legacy `.offset` wrapping the whole element (divergence 108).
@MainActor private func lfbLegacyNode(_ x: Float, _ y: Float) -> some Element {
    Box { fxLegacyBar(60, 40) }.frame(width: px(60), height: px(40))
        .clipShape(RoundedRectangle(cornerRadius: px(6))).offset(x: px(x), y: px(y))
}

/// Each accent rect's bounds and mask, in emission order.
@MainActor private func lfbMasks(_ element: some Element) -> [String] {
    effectRects(effectFrame(element, side: 400).finalizedScene()).map {
        "\(fxDescribe($0.bounds)) m\(fxDescribe($0.contentMask)) r\($0.maskCornerRadii.topLeft)"
    }
}

/// **LF-b 1** (`GX-Y`, MetalCreator's over-clip after `GX-X`). Zoom 1, pan
/// (50, 20). Node A at offset (−40, 10) sits at (−20, 70) before the canvas's
/// effect and paints wholly inside the canvas at (30, 90) 60 × 40: its mask is
/// its own rounded clip moved with it — (30, 90) 60 × 40, radius 6. Node B at
/// offset (220, 50) paints at (290, 130), straddling the canvas's right edge
/// (x 320): its mask is its own clip cut by C — (290, 130) 30 × 40 (the cut
/// meets the rounding, so the radii follow `intersect`). Both vocabularies.
/// Red on `0b400b4`: A's mask (70, 90) 20 × 40 — the inner `.offset`'s cut used
/// C, a window-space clip, in the outer effect's pre-effect space, where A's
/// clip lies at x −20…40 and C keeps only 20…40, then the pan moved that
/// sliver right. Mutation **M-Y1**.
@Test @MainActor func aClipInsideNestedFlatteningEffectsIsCutOnlyByTheOutermostEntryClip() throws {
    let proposal = lfbMasks(lfbCanvas(zoom: 1, pan: (50, 20)) { lfbNode(-40, 10); lfbNode(220, 50) })
    try #require(proposal.count == 2, "proposal: two nodes: \(proposal)")
    #expect(proposal[0] == "\(lfaBounds(30, 90, 60, 40)) m\(lfaBounds(30, 90, 60, 40)) r6.0",
            "proposal A: its own clip, moved: \(proposal[0])")
    #expect(proposal[1].hasPrefix("\(lfaBounds(290, 130, 60, 40)) m\(lfaBounds(290, 130, 30, 40))"),
            "proposal B: its own clip cut by the canvas: \(proposal[1])")

    let legacy = lfbMasks(lfbCanvas(zoom: 1, pan: (50, 20)) { lfbLegacyNode(-40, 10); lfbLegacyNode(220, 50) })
    try #require(legacy.count == 2, "legacy: two nodes: \(legacy)")
    #expect(legacy[0] == "\(lfaBounds(30, 90, 60, 40)) m\(lfaBounds(30, 90, 60, 40)) r6.0",
            "legacy A: its own clip, moved: \(legacy[0])")
    #expect(legacy[1].hasPrefix("\(lfaBounds(290, 130, 60, 40)) m\(lfaBounds(290, 130, 30, 40))"),
            "legacy B: its own clip cut by the canvas: \(legacy[1])")
}

/// **LF-b 2** (`GX-Y`). Zoom 1.5, pan (80, 20): node A's (−20, 70) 60 × 40
/// paints at (40, 95) 90 × 60, mask the same, radius 9; and with an inner
/// **uniform scale** too — `.scaleEffect(0.5, anchor: .topLeading)` before its
/// `.offset`, so a flattening scale in a flattening offset in the canvas's
/// scale — it is (−20, 70) 30 × 20 before the canvas's effect and paints at
/// (40, 95) 45 × 30, radius 4.5. Both vocabularies. Red on `0b400b4`: the mask
/// (100, 95) 30 × 60, and empty for the half-size node. Mutation **M-Y1**.
@Test @MainActor func aClipInsideAScaleInAScaledCanvasIsCutOnlyByTheOutermostEntryClip() throws {
    let proposal = lfbMasks(lfbCanvas(zoom: 1.5, pan: (80, 20)) { lfbNode(-40, 10) })
    try #require(proposal.count == 1, "proposal: one node: \(proposal)")
    #expect(proposal[0] == "\(lfaBounds(40, 95, 90, 60)) m\(lfaBounds(40, 95, 90, 60)) r9.0",
            "proposal: its own clip, scaled and moved: \(proposal[0])")

    let legacy = lfbMasks(lfbCanvas(zoom: 1.5, pan: (80, 20)) { lfbLegacyNode(-40, 10) })
    try #require(legacy.count == 1, "legacy: one node: \(legacy)")
    #expect(legacy[0] == "\(lfaBounds(40, 95, 90, 60)) m\(lfaBounds(40, 95, 90, 60)) r9.0",
            "legacy: its own clip, scaled and moved: \(legacy[0])")

    let half = lfbMasks(lfbCanvas(zoom: 1.5, pan: (80, 20)) {
        fxBar(60, 40).clipShape(RoundedRectangle(cornerRadius: px(6)))
            .scaleEffect(0.5, anchor: .topLeading).offset(x: px(-40), y: px(10))
    })
    try #require(half.count == 1, "scale in scale: one node: \(half)")
    #expect(half[0] == "\(lfaBounds(40, 95, 45, 30)) m\(lfaBounds(40, 95, 45, 30)) r4.5",
            "scale in scale: its own clip through three maps: \(half[0])")

    let legacyHalf = lfbMasks(lfbCanvas(zoom: 1.5, pan: (80, 20)) {
        Box { fxLegacyBar(60, 40) }.frame(width: px(60), height: px(40))
            .clipShape(RoundedRectangle(cornerRadius: px(6)))
            .scaleEffect(0.5, anchor: .topLeading).offset(x: px(-40), y: px(10))
    })
    try #require(legacyHalf.count == 1, "legacy scale in scale: one node: \(legacyHalf)")
    #expect(legacyHalf[0] == "\(lfaBounds(40, 95, 45, 30)) m\(lfaBounds(40, 95, 45, 30)) r4.5",
            "legacy scale in scale: its own clip through three maps: \(legacyHalf[0])")
}

/// **LF-b 3** (`GX-Y`). The same nesting with **no clip anywhere**: the outer
/// flattening effect opens at clip depth 0, where the clip in force is the
/// window itself. A node laid out at the origin, `.offset(x: −100, y: 10)`
/// inside an `.offset(x: 150)`, paints at (50, 10) 60 × 40 with its own
/// rounded clip moved with it — (50, 10) 60 × 40, radius 6. Red on `0b400b4`:
/// an empty mask, the window rect cut in the outer effect's pre-effect space
/// (x −100…−40). Mutations **M-Y2** (depth 0 read as "no flattening scope
/// open"), **M-Y3** (`atFlatteningEntry`'s `>=` as `>`).
///
/// The second arm is the same depth-0 mistake in `pushClip`, one effect deep:
/// a 460-tall root (a 420-tall spacer over the bar) is placed centred at y −30,
/// so the bar is laid out at (0, 390), past the window's bottom edge, and an
/// `.offset(y: −100)` brings it to (0, 290) 60 × 40. Its first clip inside
/// the offset must not intersect the window rect in the pre-effect space —
/// mask (0, 290) 60 × 40, not (0, 290) 60 × 10. Mutation **M-Y4**: `pushClip`
/// reading 0 as "no flattening scope" (the `GX-X` spelling).
@Test @MainActor func aClipInsideNestedFlatteningEffectsAtDepthZeroIsNotCutByTheWindow() throws {
    let rows = lfbMasks(ZStack(alignment: .topLeading) {
        Color.clear.frame(width: px(400), height: px(400))
        ZStack(alignment: .topLeading) { lfbNode(-100, 10) }.offset(x: px(150), y: px(0))
    })
    try #require(rows.count == 1, "one node: \(rows)")
    #expect(rows[0] == "\(lfaBounds(50, 10, 60, 40)) m\(lfaBounds(50, 10, 60, 40)) r6.0",
            "its own clip, moved twice: \(rows[0])")

    let below = lfbMasks(ZStack(alignment: .topLeading) {
        Color.clear.frame(width: px(400), height: px(400))
        VStack(alignment: .leading, spacing: px(0)) {
            Color.clear.frame(width: px(60), height: px(420))
            fxBar(60, 40).clipShape(RoundedRectangle(cornerRadius: px(6)))
        }.offset(x: px(0), y: px(-100))
    })
    try #require(below.count == 1, "one bar: \(below)")
    #expect(below[0] == "\(lfaBounds(0, 290, 60, 40)) m\(lfaBounds(0, 290, 60, 40)) r6.0",
            "laid out past the window, moved in: its own clip: \(below[0])")
}

/// **LF-b 4** (`GX-Y`, MetalCreator's measured repro on the LF-a stage). The
/// bar's pre-effect position lies outside the 100 × 100 clip at (50, 50) and an
/// outer flattening effect brings it into view; the panel offset is irrelevant.
/// `.clipped().offset(x: −60).offset(x: 60)` paints at (80, 80) 40 × 40, wholly
/// inside the clip: its mask is its own clip, (80, 80) 40 × 40, as on
/// `67a579e`. The same under a `ZStack`'s `.scaleEffect(1, anchor:
/// .topLeading).offset(x: 60)`; under `.scaleEffect(0.5, …)` the bar is
/// (110, 80) 20 × 20 and so is its mask. Red on `0b400b4`: (110, 80) 10 × 40,
/// (110, 80) 10 × 40 and (125, 80) 5 × 20. Mutation **M-Y1**.
@Test @MainActor func aBarMovedOutAndBackByNestedFlatteningEffectsKeepsItsOwnClip() throws {
    func row(_ element: some Element) throws -> String {
        let r = try #require(effectRects(effectFrame(element).finalizedScene()).first, "the bar")
        return "\(fxDescribe(r.bounds)) m\(fxDescribe(r.contentMask))"
    }
    let control = try row(lfaStage(fxBar(40, 40).offset(x: px(-60), y: px(0)).offset(x: px(60), y: px(0))))
    try #require(control == "\(lfaBounds(80, 80, 40, 40)) m\(lfaBounds(50, 50, 100, 100))",
                 "control: no inner clip, the outer one: \(control)")
    let offsets = try row(lfaStage(fxBar(40, 40).clipped().offset(x: px(-60), y: px(0)).offset(x: px(60), y: px(0))))
    #expect(offsets == "\(lfaBounds(80, 80, 40, 40)) m\(lfaBounds(80, 80, 40, 40))", "two offsets: \(offsets)")
    let scale1 = try row(lfaStage(ZStack(alignment: .topLeading) { fxBar(40, 40).clipped().offset(x: px(-60), y: px(0)) }
        .scaleEffect(1, anchor: .topLeading).offset(x: px(60), y: px(0))))
    #expect(scale1 == "\(lfaBounds(80, 80, 40, 40)) m\(lfaBounds(80, 80, 40, 40))", "scale 1: \(scale1)")
    let scaleHalf = try row(lfaStage(ZStack(alignment: .topLeading) { fxBar(40, 40).clipped().offset(x: px(-60), y: px(0)) }
        .scaleEffect(0.5, anchor: .topLeading).offset(x: px(60), y: px(0))))
    #expect(scaleHalf == "\(lfaBounds(110, 80, 20, 20)) m\(lfaBounds(110, 80, 20, 20))", "scale 0.5: \(scaleHalf)")
}
