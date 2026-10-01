import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// Drag and drop, lane 2, tests 2.10–2.14 (rulings `DN-J`, `DN-H` item 4,
// `DN-U` items 3 and 6; spec
// `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md` §6.4b). The
// preview's look is a human check (group N); every number here is MetalUI's
// own, ruled — SwiftUI's opacity, shadow and anchor are unmeasured
// (`DN-J` item 2).
//
// Everything runs through a real `Window` on a `FakePlatformWindow` resized to
// 400 × 200 at scale 1 (points and device pixels agree), the display link
// driven by `simulateTick(timestamp:)` — nothing sleeps.

// MARK: - Fixtures

@MainActor
private final class PLog {
    var entries: [String] = []
}

@MainActor
private final class Shown {
    var value = true
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func down(_ p: Point<Pixels>) -> InputEvent { .mouseDown(MouseEvent(position: p)) }
private func up(_ p: Point<Pixels>) -> InputEvent { .mouseUp(MouseEvent(position: p)) }
private func drag(_ p: Point<Pixels>) -> InputEvent { .mouseDragged(MouseEvent(position: p)) }
private func moved(_ p: Point<Pixels>, _ dx: Float, _ dy: Float = 0) -> Point<Pixels> {
    pt(p.x.value + dx, p.y.value + dy)
}

/// A 400 × 200 window over `content`, one frame drawn. A `Window` is held only
/// weakly by its platform window, so every caller keeps the returned window
/// alive for its scope (`DN-V` item 4).
@MainActor
private func previewWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true,
                                                content: content)
    platform.simulateResize(to: Size(width: px(400), height: px(200)))
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// A 200 × 200 box filled with `.accent`.
@MainActor
private func filledSquare() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200)).background(.accent)
}

/// A 200 × 200 `String` destination logging into `log`.
@MainActor
private func well(_ log: PLog) -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200)).dropDestination(for: String.self, action: { items, _ in
        log.entries.append("drop(\(items))"); return true
    })
}

private func bounds(_ b: MUIBounds) -> [Float] { [b.origin.x, b.origin.y, b.size.width, b.size.height] }
private func shifted(_ b: MUIBounds, _ dx: Float, _ dy: Float) -> [Float] {
    [b.origin.x + dx, b.origin.y + dy, b.size.width, b.size.height]
}

/// A rect's identity for a scene comparison: bounds, mask, colours.
private func fingerprint(_ r: MUIRect) -> String {
    "\(bounds(r.bounds)) m\(bounds(r.contentMask)) bg(\(r.background.h),\(r.background.s),\(r.background.l),\(r.background.a)) "
        + "bc(\(r.borderColor.a))"
}

private func fingerprint(_ g: MUIGlyph) -> String {
    "\(bounds(g.bounds)) m\(bounds(g.contentMask)) a\(g.color.a)"
}

/// Every hitbox carrying a draggable, opaque or not — the source's region.
@MainActor
private func sourceRegion(_ window: Window) -> Hitbox? {
    window.lastHitboxes.last { $0.handlers.gestures.contains { $0.isDraggable } }
}

/// Presses at `from`, moves 1 pt (which begins the drag, `P17`) and then to
/// `from + (dx, dy)`, then draws.
@MainActor
private func beginDrag(_ window: Window, _ platform: FakePlatformWindow, from p: Point<Pixels>,
                       by dx: Float, _ dy: Float = 0) {
    platform.simulateInput(down(p))
    platform.simulateInput(drag(moved(p, 1)))
    platform.simulateInput(drag(moved(p, dx, dy)))
    window.drawFrameIfNeeded()
}

// MARK: - 2.10: the default preview

/// **2.10** (`DN-J` items 1–2, `P18`). After a 50-pt move the scene holds the
/// source's rect unchanged at its place **and** a copy translated by (50, 0)
/// at alpha × 0.7, on a layer above every other primitive's, masked to the
/// translated snapshot bounds; the move itself asks for a frame; the copy is
/// gone after the drop.
/// Mutations **M2j** (replay at opacity 1) and **M2k** (replay untranslated).
@MainActor
@Test func theDefaultPreviewReplaysTheSourceAboveEverythingAtSeventyPercent() throws {
    let log = PLog()
    let (window, platform) = try previewWindow { Row { filledSquare().draggable("s"); well(log) } }
    defer { withExtendedLifetime(window) {} }
    let before = window.lastScene
    let sources = before.rects.filter { bounds($0.bounds) == [0, 0, 200, 200] }
    try #require(sources.count == 1, "set up: the source paints one rect: \(before.rects.map(fingerprint))")
    let source = sources[0]
    try #require(source.background.a > 0, "set up: the source's fill is visible")

    platform.simulateInput(down(pt(100, 100)))
    platform.simulateInput(drag(pt(101, 100)))
    try #require(window.dragSession != nil, "set up: the drag began")
    window.drawFrameIfNeeded()
    platform.simulateInput(drag(pt(150, 100)))
    #expect(window.needsRedraw, "a move during a session asks for a frame (the preview follows)")
    window.drawFrameIfNeeded()

    let scene = window.lastScene
    let originals = scene.rects.indices.filter { fingerprint(scene.rects[$0]) == fingerprint(source) }
    #expect(originals.count == 1, "P18: the source keeps drawing where it is")
    let copies = scene.rects.indices.filter { bounds(scene.rects[$0].bounds) == shifted(source.bounds, 50, 0) }
    try #require(copies.count == 1, "one translated copy: \(scene.rects.map(fingerprint))")
    let copy = scene.rects[copies[0]]
    #expect(abs(copy.background.a - source.background.a * 0.7) < 1e-5,
            "DN-J item 2: alpha × 0.7 (\(copy.background.a) vs \(source.background.a))")
    #expect(copy.background.h == source.background.h && copy.background.l == source.background.l,
            "the same colour")
    #expect(bounds(copy.contentMask) == shifted(source.bounds, 50, 0),
            "masked to the translated snapshot bounds: \(bounds(copy.contentMask))")
    let copyLayer = scene.layer(of: .rect, at: copies[0])
    let others = scene.rects.indices.filter { $0 != copies[0] }.map { scene.layer(of: .rect, at: $0) }
        + scene.glyphs.indices.map { scene.layer(of: .glyph, at: $0) }
    #expect(others.allSatisfy { $0 < copyLayer }, "above every other primitive: \(copyLayer) over \(others)")

    platform.simulateInput(up(pt(300, 100)))
    #expect(log.entries == ["drop([\"s\"])"], "set up: the drag dropped")
    window.drawFrameIfNeeded()
    #expect(!window.lastScene.rects.contains { bounds($0.bounds) == shifted(source.bounds, 50, 0) },
            "gone after the drop")
    #expect(window.lastScene.rects.count == before.rects.count, "the scene is the no-drag scene again")
}

// MARK: - 2.11: a custom preview

/// A preview element counting its layouts in a `@State` (`DN-U` item 3).
private struct PreviewCounter: Element {
    @State var count = 0
    let log: PLog
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        count += 1
        log.entries.append("count=\(count)")
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID,
                ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// **2.11** (`P18b`; `DN-J` item 3, `DN-U` item 3). `draggable("s") { 60×60
/// accent }`: while the drag is open the scene holds the 60 × 60 fill with
/// its top-left at the pointer less the press point's offset into the source,
/// alpha × 0.7, and no copy of the source. A `@State` inside the preview reads
/// its initial value again on the next session.
/// Mutations **M2l** (emit the snapshot as well) and **M2m** (keep the
/// preview's slot out of `ID-C`'s reset).
@MainActor
@Test func aCustomPreviewReplacesTheSnapshot() throws {
    let log = PLog()
    let counts = PLog()
    let (window, platform) = try previewWindow {
        Row {
            Box().frame(width: px(200), height: px(200)).background(.separator).draggable("s") {
                Rectangle().fill(.accent).frame(width: px(60), height: px(60))
                PreviewCounter(log: counts)
            }
            well(log)
        }
    }
    defer { withExtendedLifetime(window) {} }
    let before = window.lastScene
    try #require(counts.entries.isEmpty, "set up: no preview is laid out without a session")
    let sourceRects = before.rects.filter { bounds($0.bounds) == [0, 0, 200, 200] }
    try #require(sourceRects.count == 1, "set up: the source paints one rect")

    // Press at (100, 100) — offset (100, 100) into the source — and move to
    // (150, 120): the preview's top-left is (50, 20).
    beginDrag(window, platform, from: pt(100, 100), by: 50, 20)
    let scene = window.lastScene
    let previews = scene.rects.filter { bounds($0.bounds) == [50, 20, 60, 60] }
    try #require(previews.count == 1, "the preview at the pointer: \(scene.rects.map(fingerprint))")
    let accent = window.theme[.accent]
    #expect(abs(previews[0].background.a - accent.a * 0.7) < 1e-5, "opacity 0.7: \(previews[0].background.a)")
    #expect(scene.rects.filter { $0.bounds.size.width == 200 && $0.bounds.size.height == 200 }.count == 1,
            "P18b: no copy of the source")

    // `DN-U` item 3: two more frames of the session, then a drop and a
    // frame without one; the next session's preview starts fresh.
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    try #require(counts.entries.last == "count=3", "set up: the counter ran three frames: \(counts.entries)")
    platform.simulateInput(up(pt(300, 100)))
    window.drawFrameIfNeeded()
    counts.entries = []
    beginDrag(window, platform, from: pt(100, 100), by: 50, 20)
    #expect(counts.entries == ["count=1"], "DN-U item 3: the preview's @State starts fresh: \(counts.entries)")
    platform.simulateInput(up(pt(300, 100)))
}

// MARK: - 2.12: every draggable site captures

private struct Named: Identifiable, Hashable {
    let id: Int
    let name: String
}

/// **2.12** (`DN-U` item 6, `OM-AI`'s shape). Every draggable site, dragged
/// 50 pt, replays a non-empty copy of what it painted, translated by (50, 0)
/// at alpha × 0.7: a `Box`, a `Stack`, a `Text`, a `.padding(8)`
/// `ModifiedElement`, a `Button`, a `Toggle`, a `Picker`, a `Stepper`, a
/// `List`, a proposal `Rectangle()`.
/// Mutations **M2n** (skip the capture in `paintDecoration`) and **M2o**
/// (skip it in `DraggableModifier.paint`).
@MainActor
@Test func everyDraggableStyledSiteCapturesItsPreview() throws {
    let rows = [Named(id: 1, name: "one"), Named(id: 2, name: "two")]
    let arms: [(String, @MainActor () -> AnyElement)] = [
        ("Box", { AnyElement(Box().background(.accent).cssWidth(px(100)).cssHeight(px(100)).draggable("s")) }),
        ("Stack", { AnyElement(Stack { Text("stack") }.background(.accent)
                .cssWidth(px(100)).cssHeight(px(100)).draggable("s")) }),
        ("Text", { AnyElement(Text("Drag me").draggable("s")) }),
        ("padding", { AnyElement(Box().background(.accent).cssWidth(px(100)).cssHeight(px(100))
                .padding(px(8)).draggable("s")) }),
        ("Button", { AnyElement(Button("Drag") {}.draggable("s")) }),
        ("Toggle", { AnyElement(Toggle("T", isOn: .constant(true)).draggable("s")) }),
        ("Picker", { AnyElement(Picker("P", selection: .constant(0)) {
                Text("a").tag(0); Text("b").tag(1)
            }.draggable("s")) }),
        ("Stepper", { AnyElement(Stepper("S", value: .constant(1), in: 0...5).draggable("s")) }),
        ("List", { AnyElement(ScrollView {
                List(rows, rowHeight: px(20)) { row in Text(row.name) }.draggable("s")
            }.frame(width: px(200), height: px(100))) }),
        ("proposal Rectangle", { AnyElement(HStack {
                Rectangle().fill(.accent).frame(width: px(100), height: px(100)).draggable("s")
            }) }),
    ]
    for (name, source) in arms {
        let (window, platform) = try previewWindow { Row { source() } }
        defer { withExtendedLifetime(window) {} }
        let region = try #require(sourceRegion(window), "\(name): the source registered a draggable")
        let p = pt(region.bounds.origin.x.value + 5, region.bounds.origin.y.value + 5)
        beginDrag(window, platform, from: p, by: 50)
        try #require(window.dragSession != nil, "\(name): the drag began")
        let snapshot = window.dragSession?.snapshot ?? []
        #expect(!snapshot.isEmpty, "\(name): the source's paint was captured")
        #expect(window.lastDragCapturedPrimitives == snapshot.count, "\(name): this frame captured it")
        let scene = window.lastScene
        let rects = Set(scene.rects.map(fingerprint))
        let glyphs = Set(scene.glyphs.map(fingerprint))
        for primitive in snapshot {
            switch primitive {
            case .rect(var r, _, _):
                r.bounds = MUIBounds(origin: MUIPoint(x: r.bounds.origin.x + 50, y: r.bounds.origin.y),
                                     size: r.bounds.size)
                r.background.a *= 0.7
                r.borderColor.a *= 0.7
                #expect(scene.rects.contains { bounds($0.bounds) == bounds(r.bounds)
                        && abs($0.background.a - r.background.a) < 1e-5 },
                        "\(name): a translucent translated copy of \(fingerprint(r)) in \(rects)")
            case .glyph(var g, _, _):
                g.bounds = MUIBounds(origin: MUIPoint(x: g.bounds.origin.x + 50, y: g.bounds.origin.y),
                                     size: g.bounds.size)
                #expect(scene.glyphs.contains { bounds($0.bounds) == bounds(g.bounds)
                        && abs($0.color.a - g.color.a * 0.7) < 1e-5 },
                        "\(name): a translucent translated copy of \(fingerprint(g)) in \(glyphs)")
            case .image:
                Issue.record("\(name): no site here paints an image")
            }
        }
        platform.simulateInput(up(moved(p, 50)))
    }
}

// MARK: - 2.13: a vanished source

/// **2.13** (`DN-H` item 4). Toggling the source's `if` off mid-drag: the
/// replay is unchanged frame over frame until the drop.
/// Mutation **M2p** (clear the snapshot when the source is not painted).
@MainActor
@Test func aVanishedSourceKeepsItsLastSnapshot() throws {
    let log = PLog()
    let shown = Shown()
    let (window, platform) = try previewWindow {
        Row {
            if shown.value { filledSquare().draggable("s") }
            well(log)
        }
    }
    defer { withExtendedLifetime(window) {} }
    func translucent() -> [String] {
        window.lastScene.rects.filter { $0.background.a > 0 && $0.background.a < 0.75 }.map(fingerprint)
    }
    beginDrag(window, platform, from: pt(100, 100), by: 50)
    let replay = translucent()
    try #require(replay.count == 1, "set up: the replay drew: \(window.lastScene.rects.map(fingerprint))")
    shown.value = false
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    try #require(window.lastDragCapturedPrimitives == 0, "set up: the source did not paint")
    #expect(translucent() == replay, "the replay survives the source")
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(translucent() == replay, "frame over frame")
    platform.simulateInput(up(pt(150, 100)))
    window.drawFrameIfNeeded()
    #expect(translucent().isEmpty, "gone after the session")
}

// MARK: - 2.14: no session, no work

/// **2.14** (`DN-J` item 1: a frame with no session pays nothing). With a
/// draggable and a destination but no session, the frame captures nothing
/// and its scene equals the same tree without the two modifiers.
/// Mutation **M2q** (push the capture scope for every `paintDecoration`).
@MainActor
@Test func aFrameWithoutASessionCapturesNothing() throws {
    let log = PLog()
    let (with, _) = try previewWindow { Row { filledSquare().draggable("s"); well(log).background(.separator) } }
    let (without, _) = try previewWindow {
        Row { filledSquare(); Box().frame(width: px(200), height: px(200)).background(.separator) }
    }
    defer { withExtendedLifetime((with, without)) {} }
    #expect(with.lastDragCapturedPrimitives == 0, "nothing captured without a session")
    #expect(with.lastScene.rects.map(fingerprint) == without.lastScene.rects.map(fingerprint),
            "the same scene as the tree without the modifiers")
    #expect(!with.lastScene.rects.isEmpty, "control: the scene is not empty")
}
