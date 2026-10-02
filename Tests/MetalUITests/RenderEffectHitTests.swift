import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// Paths, shadows and transforms, lane 2 — hit testing, accessibility and
// point consumers under render effects (rulings `GX-I`, `GX-P`; spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §8,
// tests 2.10–2.15 and 2.27–2.31). SwiftUI's side is
// `docs/probes/swiftui-paths-shadows-transforms.swift`, arms H1–H7, X1–X5.
//
// Every window is 200 × 200 at scale 1, its root centred (`CN-J`): a 160 × 20
// bar spans x 20…180, y 90…110, and turned 90° about its centre x 90…110,
// y 20…180 — so (100, 40) is on the drawn bar and (40, 100) only on its
// unturned frame (H1's coordinates).

// MARK: - Fixtures

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

@MainActor
private final class HitLog { var entries: [String] = [] }

@MainActor
private func hitWindow<Root: Element>(size: Int = 200, _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: size, startsDisplayLink: true,
                                                content: content)
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// Clicks (press and release) at each point; whether `log` grew at each.
@MainActor
private func clicks(_ platform: FakePlatformWindow, _ window: Window, _ log: HitLog,
                    _ points: [Point<Pixels>]) -> [Bool] {
    points.map { p in
        let before = log.entries.count
        platform.simulateInput(.mouseDown(MouseEvent(position: p)))
        platform.simulateInput(.mouseUp(MouseEvent(position: p)))
        window.drawFrameIfNeeded()
        return log.entries.count > before
    }
}

private let deg90 = Angle.degrees(90)

// MARK: - 2.10 (H1, H6)

/// **2.10** (H1, H1c, H6). A tap inside a 90° rotation, on both
/// vocabularies, runs at (100, 40) — on the drawn bar — and not at (40, 100);
/// the unrotated control answers the opposite. Mutation **M2j**: `insertHitbox`
/// drops the transform.
@Test @MainActor func aRotatedHitboxIsHitWhereItIsDrawn() throws {
    let points = [pt(100, 40), pt(40, 100)]
    let log = HitLog()
    let (w0, p0) = try hitWindow { fxBar().onTapGesture { log.entries.append("tap") } }
    try #require(clicks(p0, w0, log, points) == [false, true], "control: the unturned bar")
    let (w1, p1) = try hitWindow { fxBar().onTapGesture { log.entries.append("tap") }.rotationEffect(deg90) }
    #expect(clicks(p1, w1, log, points) == [true, false], "proposal: hit where drawn")
    let (w2, p2) = try hitWindow { fxLegacyBar().onClick { log.entries.append("click") }.rotationEffect(deg90) }
    #expect(clicks(p2, w2, log, points) == [true, false], "legacy: hit where drawn")
    withExtendedLifetime((w0, w1, w2)) {}
}

// MARK: - 2.11 (H7)

/// **2.11** (H7). An 80 × 80 square turned 45°: a corner of its frame (65, 65)
/// misses, the diamond's tip (100, 48) hits. Mutation **M2k**: hit testing
/// against the transformed bounding box.
@Test @MainActor func aRotatedSquaresFrameCornerMissesAndItsTipHits() throws {
    let log = HitLog()
    let (window, platform) = try hitWindow {
        fxBar(80, 80).onTapGesture { log.entries.append("tap") }.rotationEffect(.degrees(45))
    }
    #expect(clicks(platform, window, log, [pt(65, 65), pt(100, 48)]) == [false, true])
}

// MARK: - 2.12 (H2–H4)

/// **2.12** (H2, H3, H4). A 160 × 160 square under `scaleEffect(0.5)` hits at
/// (100, 100) and not (30, 100); a 60 × 60 one under `scaleEffect(2)` hits at
/// (50, 100); under `offset(x: 60)` at (160, 100) and not (80, 100). Mutation
/// **M2j**.
@Test @MainActor func scaleAndOffsetMoveTheHitRegion() throws {
    let log = HitLog()
    let (w1, p1) = try hitWindow { fxBar(160, 160).onTapGesture { log.entries.append("t") }.scaleEffect(0.5) }
    #expect(clicks(p1, w1, log, [pt(100, 100), pt(30, 100)]) == [true, false], "H2")
    let (w2, p2) = try hitWindow { fxBar(60, 60).onTapGesture { log.entries.append("t") }.scaleEffect(2) }
    #expect(clicks(p2, w2, log, [pt(100, 100), pt(50, 100)]) == [true, true], "H3")
    let (w3, p3) = try hitWindow { fxBar(60, 60).onTapGesture { log.entries.append("t") }.offset(x: px(60)) }
    #expect(clicks(p3, w3, log, [pt(160, 100), pt(80, 100)]) == [true, false], "H4")
    withExtendedLifetime((w1, w2, w3)) {}
}

// MARK: - 2.13

/// **2.13** (`GX-I`). A rotated hitbox is still cut by the clip outside the
/// effect: the turned bar under a 200 × 60 clip (y 70…130) hits at (100, 100)
/// and not at (100, 40), drawn but clipped away. Mutation **M2l**: the outer
/// clip dropped from the hitbox.
@Test @MainActor func aTransformedHitboxIsStillCutByTheOuterClip() throws {
    let log = HitLog()
    let (window, platform) = try hitWindow {
        fxBar().onTapGesture { log.entries.append("tap") }.rotationEffect(deg90)
            .frame(width: px(200), height: px(60)).clipped()
    }
    #expect(clicks(platform, window, log, [pt(100, 100), pt(100, 40)]) == [true, false])
}

// MARK: - 2.14

/// **2.14** (`GX-I`). Hover and the gesture arena follow the transform: a
/// rotated legacy bar's hover background shows with the pointer at (100, 40)
/// and not at (40, 100), and a `DragGesture` on a rotated proposal bar begins
/// from (100, 40) and not from (40, 100). Mutation **M2j**.
@Test @MainActor func hoverAndGestureArenasFollowTheTransform() throws {
    let (window, platform) = try hitWindow {
        Box().frame(width: px(160), height: px(20)).hoverBackground(.accent).onClick {}.rotationEffect(deg90)
    }
    func hovered(at p: Point<Pixels>) -> Bool {
        platform.simulateInput(.mouseMoved(MouseEvent(position: p)))
        window.drawFrameIfNeeded()
        return !effectRects(window.lastScene).isEmpty
    }
    #expect(hovered(at: pt(100, 40)), "hovered on the drawn bar")
    #expect(!hovered(at: pt(40, 100)), "not on its unturned frame")

    let log = HitLog()
    let (w2, p2) = try hitWindow {
        fxBar().gesture(DragGesture().onChanged { _ in log.entries.append("chg") }).rotationEffect(deg90)
    }
    func drags(from p: Point<Pixels>) -> Bool {
        let before = log.entries.count
        p2.simulateInput(.mouseDown(MouseEvent(position: p)))
        p2.simulateInput(.mouseDragged(MouseEvent(position: Point(x: p.x, y: px(p.y.value + 20)))))
        p2.simulateInput(.mouseUp(MouseEvent(position: Point(x: p.x, y: px(p.y.value + 20)))))
        w2.drawFrameIfNeeded()
        return log.entries.count > before
    }
    #expect(drags(from: pt(100, 40)), "a drag begins on the drawn bar")
    #expect(!drags(from: pt(40, 100)), "not on its unturned frame")
}

// MARK: - 2.15 (X1, X2, X4, X5)

/// **2.15** (X1, X2, X4, X5). The accessibility frame is the transformed
/// frame's bounding box: offset (50, 20) moves it; 90° swaps its sides about
/// the centre; scale 2 doubles it about the centre; scale 0.5 at
/// `.topLeading` halves it from the corner; at 45° it is the bounding box,
/// not SwiftUI's smaller square (divergence 107). Mutation **M2m**: the
/// untransformed bounds published.
@Test @MainActor func theAccessibilityFrameIsTheTransformedBoundingBox() throws {
    func frameOf(_ e: some Element) throws -> Bounds<Pixels> {
        let f = effectFrame(e, accessibility: true)
        let record = try #require(f.axEmissions.first { $0.declared.label == "x" }, "the labelled record")
        return record.geometry.frame
    }
    func label() -> AccessibilityModifier<ModifiedContent<Color, LayoutModifier>> {
        fxBar(33, 24).accessibilityLabel("x")
    }
    let plain = try frameOf(label())
    let o = plain.origin, cx = o.x.value + 16.5, cy = o.y.value + 12
    func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> String {
        "\(Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h))))"
    }
    #expect("\(try frameOf(label().offset(x: px(50), y: px(20))))" == rect(o.x.value + 50, o.y.value + 20, 33, 24), "X1")
    #expect("\(try frameOf(label().rotationEffect(deg90)))" == rect(cx - 12, cy - 16.5, 24, 33), "X2")
    // The visible frame on both written orders (review round): no clip, so
    // it is the frame itself.
    func visible(_ order: String, _ element: some Element) throws {
        let f = effectFrame(element, accessibility: true)
        let record = try #require(f.axEmissions.first { $0.declared.label == "x" })
        #expect("\(record.geometry.visibleFrame)" == rect(cx - 12, cy - 16.5, 24, 33),
                "X2 \(order): visible frame \(record.geometry.visibleFrame)")
    }
    try visible("inside", label().rotationEffect(deg90))
    try visible("after", fxBar(33, 24).rotationEffect(deg90).accessibilityLabel("x"))
    #expect("\(try frameOf(label().scaleEffect(2)))" == rect(cx - 33, cy - 24, 66, 48), "X4")
    #expect("\(try frameOf(label().scaleEffect(0.5, anchor: .topLeading)))" == rect(o.x.value, o.y.value, 16.5, 12), "X5")
    // Divergence 107's pin: at 45° MetalUI still answers the bounding box,
    // (33 + 24) / √2 = 40.305 square, where SwiftUI reports 35.358 (X3).
    let turned = try frameOf(label().rotationEffect(.degrees(45)))
    #expect(abs(turned.size.width.value - 40.305) < 0.01 && abs(turned.size.height.value - 40.305) < 0.01
                && abs(turned.origin.x.value - (cx - 20.1525)) < 0.01,
            "divergence 107: the 45° bounding box: \(turned)")
}

// MARK: - 2.27 (H1b, GX-P item 1)

/// **2.27** (H1b, `GX-P` item 1). A tap, a `TapGesture` and a drop destination
/// written AFTER the rotation share its rectangle and so its transform: hit at
/// (100, 40), not at (40, 100). Mutation **M2x**: no outward propagation.
@Test @MainActor func aTapWrittenAfterAnEffectHitsTheTransformedFrame() throws {
    let points = [pt(100, 40), pt(40, 100)]
    let log = HitLog()
    let (w1, p1) = try hitWindow { fxBar().rotationEffect(deg90).onTapGesture { log.entries.append("tap") } }
    #expect(clicks(p1, w1, log, points) == [true, false], "onTapGesture after the effect")
    let (w2, p2) = try hitWindow {
        fxBar().rotationEffect(deg90).gesture(TapGesture().onEnded { log.entries.append("tg") })
    }
    #expect(clicks(p2, w2, log, points) == [true, false], "gesture(TapGesture()) after the effect")
    let (w3, _) = try hitWindow {
        fxBar().rotationEffect(deg90).dropDestination(for: String.self, action: { _, _ in true })
    }
    let region = try #require(w3.lastHitboxes.first { $0.handlers.dropDestination != nil && !$0.opaque })
    #expect(region.contains(pt(100, 40)) && !region.contains(pt(40, 100)), "the drop region turns too")
    withExtendedLifetime((w1, w2, w3)) {}
}

// MARK: - 2.28 (divergence 41 amended, GX-P item 2)

/// **2.28** (divergence 41 amended). A handler outside a padding over an effect
/// hits its own axis-aligned, padded frame: (40, 100) hits, (100, 40) does
/// not. Mutation **M2y**: propagation through a rect-changing layer.
@Test @MainActor func aHandlerOutsideAPaddingOverAnEffectHitsItsAxisAlignedFrame() throws {
    let log = HitLog()
    let (window, platform) = try hitWindow {
        fxBar().rotationEffect(deg90).padding(Edges(all: px(10))).onTapGesture { log.entries.append("tap") }
    }
    #expect(clicks(platform, window, log, [pt(40, 100), pt(100, 40)]) == [true, false])
}

// MARK: - 2.29 (GX-P item 3)

/// **2.29** (`GX-P` item 3). Point consumers read the declarer's local point: a
/// 100-wide `Slider` under `scaleEffect(x: 2, anchor: .leading)` pressed where
/// its drawn track is 75 % along reads 7.5 of 0…10; a `DragGesture` under a 90°
/// rotation dragged +20 in window x reports translation (0, −20); a drop's
/// action location under `offset(x: 40)` is destination-local. Mutation
/// **M2z**: `Window` passes the raw window point.
@Test @MainActor func pointConsumersReadTheDeclarersLocalPoint() throws {
    final class Level { var value = 0.0 }
    let level = Level()
    let binding = Binding(get: { level.value }, set: { level.value = $0 })
    let (w1, p1) = try hitWindow(size: 300) {
        controlRoot(width: 300, height: 300) {
            Slider(value: binding, in: 0...10).frame(width: px(100)).scaleEffect(x: 2, anchor: .leading)
        }
    }
    // Local x 10 + 0.75 × 80 = 70 on the slider's own 100-pt box at x 0; drawn ×2 → window 140.
    p1.simulateInput(.mouseDown(MouseEvent(position: pt(140, 150))))
    p1.simulateInput(.mouseUp(MouseEvent(position: pt(140, 150))))
    #expect(abs(level.value - 7.5) < 1e-6, "the slider reads its local point: \(level.value)")

    final class Drags { var translations: [Size<Pixels>] = [] }
    let drags = Drags()
    let (w2, p2) = try hitWindow {
        fxBar().gesture(DragGesture().onChanged { drags.translations.append($0.translation) }).rotationEffect(deg90)
    }
    p2.simulateInput(.mouseDown(MouseEvent(position: pt(100, 60))))
    p2.simulateInput(.mouseDragged(MouseEvent(position: pt(120, 60))))
    let last = try #require(drags.translations.last, "the drag changed")
    #expect(abs(last.width.value) < 1e-3 && abs(last.height.value + 20) < 1e-3,
            "window +20 x is local −20 y: \(last)")
    p2.simulateInput(.mouseUp(MouseEvent(position: pt(120, 60))))

    final class Where { var location: Point<Pixels>? }
    let got = Where()
    let (w3, p3) = try hitWindow {
        fxBar(60, 60).dropDestination(for: String.self, action: { _, location in got.location = location; return true })
            .offset(x: px(40))
    }
    let utf8 = PasteboardType(identifier: "public.utf8-plain-text",
                              conformsTo: ["public.plain-text", "public.text", "public.data", "public.item"])
    let item = DropItem(types: [utf8]) { _ in Array("x".utf8) }
    _ = p3.simulateDrop(.entered(position: pt(150, 100), items: [item]))
    _ = p3.simulateDrop(.performed(position: pt(150, 100), items: [item]))
    // The 60 × 60 well sits at (70, 70); drawn at (110, 70); window (150, 100) is local (40, 30).
    let location = try #require(got.location, "the drop was delivered")
    #expect(location == pt(40, 30), "destination-local under the offset: \(location)")
    withExtendedLifetime((w1, w2, w3)) {}
}

// MARK: - 2.30 (GX-P item 4)

/// **2.30** (`GX-P` item 4). An effect in a scrolled scroller turns about its
/// SCROLLED anchor: scrolled by 30, the bar laid out at y 100…120 paints about
/// (100, 80), and both the paint record and the tap's hitbox fix that point.
/// Mutation **M2aa**: the anchor omits `activeOffset`.
@Test @MainActor func anEffectInAScrolledScrollerTurnsAboutItsScrolledAnchor() throws {
    let (window, platform) = try hitWindow {
        ProposalScrollView(.vertical) {
            VStack(spacing: 0) {
                Color(.separator).frame(width: px(200), height: px(100))
                fxBar().onTapGesture {}.rotationEffect(deg90)
                Color(.separator).frame(width: px(200), height: px(400))
            }
        }
        .frame(width: px(200), height: px(200))
    }
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(100, 100), delta: Point(x: px(0), y: px(-30)))))
    window.drawFrameIfNeeded()
    let scene = window.lastScene
    let bar = try #require(effectRects(scene).first)
    try #require(bar.bounds.origin.y == 70, "set up: scrolled by 30: \(fxDescribe(bar.bounds))")
    let record = try #require(effectRecord(bar, in: scene))
    let fixed = fxAffine(record).apply(100, 80)
    #expect(abs(fixed.x - 100) < 1e-3 && abs(fixed.y - 80) < 1e-3, "paint turns about the scrolled centre: \(fixed)")
    let hitbox = try #require(window.lastHitboxes.first { !$0.handlers.gestures.isEmpty })
    let local = hitbox.localPoint(pt(100, 80))
    #expect(abs(local.x.value - 100) < 1e-3 && abs(local.y.value - 80) < 1e-3, "and so does the hitbox: \(local)")
}

// MARK: - 2.31

/// **2.31** (`GX-P` item 1). An accessibility record written after an effect
/// follows it: `.rotationEffect(90°).accessibilityLabel("x")` on the 160 × 20
/// bar publishes the turned 20 × 160 bounding box. Mutation **M2x**.
@Test @MainActor func anAccessibilityRecordWrittenAfterAnEffectFollowsIt() throws {
    // Both written orders publish the same frame AND visible frame (review
    // round): the shared record's visible frame is the bounding box of its
    // pre-effect visible rect, not that rect cut by the new bounding box.
    let turned = "\(Bounds(origin: pt(90, 20), size: Size(width: px(20), height: px(160))))"
    func check(_ order: String, _ element: some Element) throws {
        let f = effectFrame(element, accessibility: true)
        let record = try #require(f.axEmissions.first { $0.declared.label == "x" })
        #expect("\(record.geometry.frame)" == turned, "\(order): the turned bounding box: \(record.geometry.frame)")
        #expect("\(record.geometry.visibleFrame)" == turned,
                "\(order): the turned visible frame: \(record.geometry.visibleFrame)")
    }
    try check("after", fxBar().rotationEffect(deg90).accessibilityLabel("x"))
    try check("before", fxBar().accessibilityLabel("x").rotationEffect(deg90))
}

// MARK: - 2.32 (GX-U, review round)

/// **2.32** (`GX-U`). A wrapper whose content is a `ZStack` or an `.overlay`
/// does not share an effect on one of their children, even at an equal rect:
/// the corner (53, 53) of the unrotated square beside a rotated one still hits
/// the tap outside the stack (divergence 41's axis-aligned frame), as it does
/// with no rotation. Mutation **MU1**: the share floor ignored.
@Test @MainActor func aWrapperOverAZStackOrOverlayDoesNotShareAChildsEffect() throws {
    let points = [pt(53, 53), pt(100, 100)]
    let log = HitLog()
    func square(_ token: ColorToken) -> ModifiedContent<Color, LayoutModifier> {
        Color(token).frame(width: px(100), height: px(100))
    }
    let (w0, p0) = try hitWindow {
        ZStack { square(.accent); square(.separator) }.onTapGesture { log.entries.append("tap") }
    }
    try #require(clicks(p0, w0, log, points) == [true, true], "control: no rotation")
    let (w1, p1) = try hitWindow {
        ZStack { square(.accent); square(.separator).rotationEffect(.degrees(45)) }
            .onTapGesture { log.entries.append("tap") }
    }
    #expect(clicks(p1, w1, log, points) == [true, true], "a ZStack's rotated child")
    let (w2, p2) = try hitWindow {
        square(.accent).overlay { square(.separator).rotationEffect(.degrees(45)) }
            .onTapGesture { log.entries.append("tap") }
    }
    #expect(clicks(p2, w2, log, points) == [true, true], "an overlay's rotated content")
    let (w3, p3) = try hitWindow {
        square(.accent).background { square(.separator).rotationEffect(.degrees(45)) }
            .onTapGesture { log.entries.append("tap") }
    }
    #expect(clicks(p3, w3, log, points) == [true, true], "a background's rotated content")
    withExtendedLifetime((w0, w1, w2, w3)) {}
}
