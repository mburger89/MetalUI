import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// Overlays and coordinates (C15), lane A — named coordinate spaces, the hover
// coordinate space and the window size in the environment: tests A1–A18
// (rulings `OV-D`…`OV-H`, `OV-L`…`OV-P`; spec
// `docs/superpowers/specs/2026-10-10-overlays-coords-design.md` §4.1).
// SwiftUI's side is `docs/probes/swiftui-overlays-coords.swift`, arms G1–G7;
// each test names the arm it follows. SwiftUI's `.global` in a titled window
// reads 32 points lower than MetalUI's content space (divergence 139), so the
// probe's global y values appear here 32 smaller.
//
// **No test sleeps**: windows are `makeFakeWindowOnDefaultDevice` windows
// driven by `drawFrameIfNeeded()`, `simulateInput`, `simulateResize(to:)` and
// model writes. Red before, for every test: the file does not compile at
// `ebcf3c7` (no `.named`, no `coordinateSpace(_:)`, no `windowSize`); the red
// was also taken against the lane-A stub (the API compiles, a named space
// resolves as `.global`, hover ignores the space, `windowSize` unstamped,
// presentation spaces not carried), recorded in the lane's red commit.

// MARK: - Harness

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h)))
}
private func mv(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func ldown(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y))) }
private func ldrag(_ x: Float, _ y: Float) -> InputEvent { .mouseDragged(MouseEvent(position: pt(x, y))) }
private func lup(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y))) }
private func wheel(_ dy: Float, at p: Point<Pixels> = pt(100, 100)) -> InputEvent {
    .scrollWheel(ScrollEvent(position: p, delta: pt(0, dy)))
}

/// Whether two rects agree to 0.01 point on every field.
private func near(_ a: Bounds<Pixels>?, _ b: Bounds<Pixels>) -> Bool {
    guard let a else { return false }
    return abs(a.origin.x.value - b.origin.x.value) < 0.01 && abs(a.origin.y.value - b.origin.y.value) < 0.01
        && abs(a.size.width.value - b.size.width.value) < 0.01
        && abs(a.size.height.value - b.size.height.value) < 0.01
}

private func near(_ a: Point<Pixels>?, _ b: Point<Pixels>) -> Bool {
    guard let a else { return false }
    return abs(a.x.value - b.x.value) < 0.01 && abs(a.y.value - b.y.value) < 0.01
}

/// Every frame a tree reported, in order, by tag.
@MainActor private final class CSLog {
    var frames: [String: [Bounds<Pixels>]] = [:]
    var points: [Point<Pixels>] = []
    var phases: [HoverPhase] = []
    var reports = 0
    func add(_ tag: String, _ b: Bounds<Pixels>) { frames[tag, default: []].append(b) }
}

@Observable @MainActor private final class CSModel {
    var offset: Float = 0
    var inner: Float = 30
}

/// A window `size` square over `content`, drawn until clean.
@MainActor private func csWindow<Root: Element>(size: Int = 300,
                                                _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: size, content: content)
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

/// The probe's leaf: a 40 × 20 rectangle reporting its global frame and its
/// frames in `.named("outer")` and `.named("missing")`, tagged.
@MainActor private func geoLeaf(_ log: CSLog, _ tag: String) -> some ProposalElementGroup {
    Rectangle().frame(width: px(40), height: px(20))
        .onGeometryChange(for: [Bounds<Pixels>].self, of: { p in
            [p.frame(in: .global), p.frame(in: .named("outer")), p.frame(in: .named("missing"))]
        }) { v in
            log.add(tag + " global", v[0]); log.add(tag + " outer", v[1]); log.add(tag + " missing", v[2])
        }
}

/// The probe's placement: `content` at (50, 40) in a 300 × 300 root that fills
/// the window, top-leading.
@MainActor private func placed<C: ProposalElementGroup>(_ content: C) -> some Element {
    HStack {
        content.padding(Edges(top: px(40), right: px(0), bottom: px(0), left: px(50)))
            .frame(width: px(300), height: px(300), alignment: .topLeading)
    }
}

// MARK: - A1–A5: what a named frame is (G1–G7)

/// **A1** (G1, G2). `frame(in: .named("outer"))` is relative to the nearest
/// ancestor so named: the leaf padded 30 in a space at (50, 40) reads
/// (30, 30, 40x20), its global (80, 70); two nested spaces both named `outer`
/// (the inner at +10) still read (30, 30) — the outermost would read (40, 40).
/// Red on the stub: the named frame is the global one. Mutation: `namedSpace`
/// resolution takes the outermost match (`first(where:)`).
@MainActor
@Test func frameInNamedSpaceIsRelativeToTheNearestAncestorSoNamed() throws {
    let log = CSLog()
    let (window, _) = try csWindow {
        placed(VStack(alignment: .leading, spacing: px(0)) {
            geoLeaf(log, "G1").padding(Edges(all: px(30))).coordinateSpace(.named("outer"))
            geoLeaf(log, "G2").padding(Edges(all: px(30))).coordinateSpace(.named("outer"))
                .padding(Edges(all: px(10))).coordinateSpace(.named("outer"))
        })
    }
    #expect(near(log.frames["G1 global"]?.first, rect(80, 70, 40, 20)), "\(log.frames)")
    #expect(near(log.frames["G1 outer"]?.first, rect(30, 30, 40, 20)), "G1: \(log.frames)")
    // G2's outer container is at (50, 120) (below G1's 80-tall one), the inner at (60, 130).
    #expect(near(log.frames["G2 global"]?.first, rect(90, 160, 40, 20)), "\(log.frames)")
    #expect(near(log.frames["G2 outer"]?.first, rect(30, 30, 40, 20)), "G2, the nearest: \(log.frames)")
    withExtendedLifetime(window) {}
}

/// **A2** (G1's `missing`, G5). A name no ancestor declares reads `.global`,
/// and so does a name declared on a sibling. Red on the stub: green for the
/// missing arm (the stub falls back everywhere), red nowhere — the sibling arm
/// reddens under its mutation. Mutation: the scope never pops its entry (the
/// sibling's space stays open for the leaf after it).
@MainActor
@Test func aNameNoAncestorDeclaresFallsBackToGlobal() throws {
    let log = CSLog()
    let (window, _) = try csWindow {
        placed(HStack(spacing: px(0)) {
            Rectangle().frame(width: px(20), height: px(20)).coordinateSpace(.named("outer"))
            geoLeaf(log, "G5")
        })
    }
    let global = try #require(log.frames["G5 global"]?.first)
    #expect(near(global, rect(70, 40, 40, 20)), "\(global)")
    #expect(near(log.frames["G5 missing"]?.first, global), "missing → global: \(log.frames)")
    #expect(near(log.frames["G5 outer"]?.first, global), "a sibling's name → global: \(log.frames)")
    withExtendedLifetime(window) {}
}

/// **A3** (G3). An `.offset(x: 7, y: 9)` written after `coordinateSpace`
/// moves `.global` to (87, 79) but not the named frame, still (30, 30).
/// Red on the stub: named = global. Mutation: the entry built without the
/// composed map (`localSpace` from the scrolled origin alone).
@MainActor
@Test func aNamedSpaceMovesWithAnOffsetOnItsContainer() throws {
    let log = CSLog()
    let (window, _) = try csWindow {
        placed(geoLeaf(log, "G3").padding(Edges(all: px(30))).coordinateSpace(.named("outer"))
            .offset(x: px(7), y: px(9)))
    }
    #expect(near(log.frames["G3 global"]?.first, rect(87, 79, 40, 20)), "\(log.frames)")
    #expect(near(log.frames["G3 outer"]?.first, rect(30, 30, 40, 20)), "\(log.frames)")
    withExtendedLifetime(window) {}
}

/// **A4** (G6, `OV-M` item 1). The named container rotated **30°**: global is
/// the rotated bounding box (77.68, 61.34, 44.64x37.32) — the probe's
/// (77.7, 93.3, 44.6x37.3) less the 32-point title bar — and the named frame
/// stays exactly (30, 30, 40x20). Red on the stub: named = global.
/// Mutations: (a) `toSpace` as "minus the bounding box's origin" (A3 stays
/// green: separating); (b) the boxed global frame mapped back through the
/// space (≈ 57 × 51; at G4's 90° the two rules coincide).
@MainActor
@Test func aRotatedNamedSpaceReportsTheUnrotatedFrame() throws {
    let log = CSLog()
    let (window, _) = try csWindow {
        placed(geoLeaf(log, "G6").padding(Edges(all: px(30))).coordinateSpace(.named("outer"))
            .rotationEffect(.degrees(30)))
    }
    #expect(near(log.frames["G6 global"]?.first, rect(77.679, 61.340, 44.641, 37.321)), "\(log.frames)")
    #expect(near(log.frames["G6 outer"]?.first, rect(30, 30, 40, 20)), "G6: \(log.frames)")
    #expect(near(log.frames["G6 missing"]?.first, rect(77.679, 61.340, 44.641, 37.321)))
    withExtendedLifetime(window) {}
}

/// **A4b** (G7, `OV-M` item 1). The same 30° on the leaf inside the named
/// container — an effect between the space and the element: the same global,
/// and the named frame is its bounding box in the space,
/// (27.68, 21.34, 44.64x37.32). Red on the stub: named = global. Mutation: the
/// element's own effect dropped from the composed map (`map = toSpace`).
@MainActor
@Test func anEffectBetweenTheSpaceAndTheElementReportsItsBoxInTheSpace() throws {
    let log = CSLog()
    let (window, _) = try csWindow {
        placed(geoLeaf(log, "G7").rotationEffect(.degrees(30))
            .padding(Edges(all: px(30))).coordinateSpace(.named("outer")))
    }
    #expect(near(log.frames["G7 global"]?.first, rect(77.679, 61.340, 44.641, 37.321)), "\(log.frames)")
    #expect(near(log.frames["G7 outer"]?.first, rect(27.679, 21.340, 44.641, 37.321)), "G7: \(log.frames)")
    withExtendedLifetime(window) {}
}

/// The named frame a tile in a 200 × 100 scroller reports, before and after a
/// 20-point scroll; `inside` declares the space on the scroller's content,
/// otherwise around the scroller.
@MainActor private func scrolledNamedFrames(inside: Bool) throws -> [Bounds<Pixels>] {
    let log = CSLog()
    let watched = Box().frame(width: px(200), height: px(10)).background(.accent)
        .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .named("c")) }) { log.add("tile", $0) }
    @MainActor func content() -> some ElementGroup {
        Column {
            Box().frame(width: px(200), height: px(30)).background(.accent)
            watched
            Box().frame(width: px(200), height: px(400)).background(.accent)
        }
    }
    let (window, platform) = try csWindow(size: 200) {
        Column {
            if inside {
                Box { ScrollView(.vertical) { content().coordinateSpace(.named("c")) } }
                    .frame(width: px(200), height: px(100))
            } else {
                Box { ScrollView(.vertical) { content() } }
                    .frame(width: px(200), height: px(100))
                    .coordinateSpace(.named("c"))
            }
        }
    }
    platform.simulateInput(wheel(-20))
    window.drawFrameIfNeeded()
    withExtendedLifetime(window) {}
    return log.frames["tile"] ?? []
}

/// **A5** (`OV-E` item 2). A space declared on a scroller's content moves with
/// the scroll: the tile's named frame is the same before and after; a space
/// declared around the scroller does not: the tile's frame in it moves by the
/// offset (−20). Red on the stub: both read global (the inside arm moves).
/// Mutation: the entry's origin unscrolled (`localSpace` without `scrolled`).
@MainActor
@Test func aNamedSpaceInsideAScrollerFollowsTheScroll() throws {
    let inside = try scrolledNamedFrames(inside: true)
    try #require(inside.count == 1, "one report, the frame never moved in its space: \(inside)")
    #expect(near(inside[0], rect(0, 30, 200, 10)), "\(inside)")
    let outside = try scrolledNamedFrames(inside: false)
    try #require(outside.count == 2, "the initial frame and the scrolled one: \(outside)")
    #expect(near(outside[0], rect(0, 30, 200, 10)), "\(outside)")
    #expect(near(outside[1], rect(0, 10, 200, 10)), "\(outside)")
}

// MARK: - A6–A8: transparency and cost

/// The ids of the click targets a tree registered.
@MainActor private func clickIDs<Root: Element>(_ content: @escaping @MainActor () -> Root) throws -> [GlobalElementID] {
    let (window, _) = try csWindow(size: 200, content)
    defer { withExtendedLifetime(window) {} }
    return window.lastHitboxes.filter(\.opaque).map(\.id)
}

/// **A6** (`OV-E` item 1). `coordinateSpace` adds no node and no identity
/// level: a click target's id is the same with and without it, on both
/// vocabularies; the separating control (`.padding(0)`, one layer) moves it.
/// Mutation: the scope numbers its content from 0 under a new level.
@MainActor
@Test func coordinateSpaceAddsNoNodeAndNoIdentityLevel() throws {
    let typed = try clickIDs { HStack { Rectangle().frame(width: px(40), height: px(40)).onTapGesture {} } }
    let typedScoped = try clickIDs {
        HStack { Rectangle().frame(width: px(40), height: px(40)).onTapGesture {}.coordinateSpace(.named("x")) }
    }
    let typedPadded = try clickIDs {
        HStack { Rectangle().frame(width: px(40), height: px(40)).onTapGesture {}.padding(Edges(all: px(0))) }
    }
    try #require(typed.count == 1 && typedPadded.count == 1 && typed != typedPadded,
                 "the control must separate: \(typed) \(typedPadded)")
    #expect(typedScoped == typed, "\(typedScoped) vs \(typed)")
    let legacy = try clickIDs { Column { Box().frame(width: px(40), height: px(40)).onClick {} } }
    let legacyScoped = try clickIDs {
        Column { Box().frame(width: px(40), height: px(40)).onClick {}.coordinateSpace(.named("x")) }
    }
    try #require(legacy.count == 1)
    #expect(legacyScoped == legacy, "\(legacyScoped) vs \(legacy)")
}

/// `count` 10 × 10 click targets in a column.
@MainActor private func targets(_ count: Int) -> some ElementGroup {
    Column { ForEach(0..<count, id: \.self) { _ in Box().frame(width: px(10), height: px(10)).onClick {} } }
}

/// **A7** (`OV-E` item 3). No named space means no snapshots: a tree of five
/// click targets and no scope takes 0; K = 2 scopes over H = 3 targets each,
/// beside two targets outside any scope, take K × H = 6 (literals derived
/// before the run). Mutation: snapshot on every registration (the 0 arm reads
/// 5, the 6 arm 8).
@MainActor
@Test func noNamedSpaceMeansNoSnapshots() throws {
    let (plain, _) = try csWindow(size: 200) { Column { targets(3); targets(2) } }
    try #require(plain.lastHitboxes.filter(\.opaque).count == 5)
    #expect(plain.lastNamedSpaceSnapshots == 0)
    #expect(plain.lastHitboxNamedSpaces.isEmpty)
    let (scoped, _) = try csWindow(size: 200) {
        Column {
            targets(3).coordinateSpace(.named("a"))
            targets(3).coordinateSpace(.named("b"))
            targets(2)
        }
    }
    try #require(scoped.lastHitboxes.filter(\.opaque).count == 8)
    #expect(scoped.lastNamedSpaceSnapshots == 6)
    #expect(scoped.lastHitboxNamedSpaces.count == 6)
    withExtendedLifetime((plain, scoped)) {}
}

/// **A8** (`GeometryChange` B14's shape). The untyped entry (a scope over a
/// legacy `Column`) and the typed entry (over a `VStack` in an `HStack`) each
/// declare their space: a tile 10 below each container's top reads y = 10.
/// Red on the stub: both read global. Mutation: break each entry's node record
/// (`nodes: []`, no space pushed) in turn — only that arm reddens.
@MainActor
@Test func theTypedAndUntypedScopeEntriesAreEachPinned() throws {
    let log = CSLog()
    let (window, _) = try csWindow(size: 200) {
        Column {
            Column {
                Box().frame(width: px(20), height: px(10)).background(.accent)
                Box().frame(width: px(20), height: px(10)).background(.accent)
                    .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .named("u")) }) { log.add("u", $0) }
            }
            .coordinateSpace(.named("u"))
            HStack {
                VStack(spacing: px(0)) {
                    Rectangle().frame(width: px(20), height: px(10))
                    Rectangle().frame(width: px(20), height: px(10))
                        .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .named("t")) }) { log.add("t", $0) }
                }
                .coordinateSpace(.named("t"))
            }
        }
    }
    #expect(near(log.frames["u"]?.first, rect(0, 10, 20, 10)), "untyped: \(log.frames)")
    #expect(near(log.frames["t"]?.first, rect(0, 10, 20, 10)), "typed: \(log.frames)")
    withExtendedLifetime(window) {}
}

// MARK: - A9–A11: the hover coordinate space (OV-F)

/// **A9** (`OV-F`). `onContinuousHover(coordinateSpace: .global)` reports the
/// window point: a 40 × 40 tile offset 30 reports (115, 100) at (115, 100)
/// where `.local` reports (5, 20). Red on the stub: (5, 20). Mutation: hover
/// ignores the space (always `.local`).
@MainActor
@Test func continuousHoverReportsTheGlobalPoint() throws {
    let log = CSLog()
    let (window, platform) = try csWindow(size: 200) {
        Column {
            Box().frame(width: px(40), height: px(40)).background(.accent)
                .onContinuousHover(coordinateSpace: .global) { log.phases.append($0) }
                .offset(x: px(30))
        }
    }
    platform.simulateInput(mv(115, 100))
    platform.simulateInput(mv(190, 100))
    #expect(log.phases == [.active(pt(115, 100)), .ended], "\(log.phases)")
    withExtendedLifetime(window) {}
}

/// **A10** (`OV-F`, `OV-E` item 3). `.named` hover through the hitbox's
/// snapshot: a 200 × 400 region 20 below the top of a scroller's content,
/// which declares `c`; the window point (100, 100) is (100, 50) in `c` (the
/// root is centred, content at y 50) where `.local` reads (100, 30), and after
/// a 20-point scroll (100, 101) is (100, 71). Red on the stub: the local
/// point. Mutation: `.named` treated as `.global` in hover (reads (100, 100),
/// (100, 101)).
@MainActor
@Test func continuousHoverReportsTheNamedPointUnderAScroll() throws {
    let log = CSLog()
    let (window, platform) = try csWindow(size: 200) {
        Box {
            ScrollView(.vertical) {
                Column {
                    Box().frame(width: px(200), height: px(20)).background(.accent)
                    Box().frame(width: px(200), height: px(400)).background(.accent)
                        .onContinuousHover(coordinateSpace: .named("c")) { log.phases.append($0) }
                }
                .coordinateSpace(.named("c"))
            }
        }
        .frame(width: px(200), height: px(100))
    }
    platform.simulateInput(mv(100, 100))
    try #require(log.phases.last == .active(pt(100, 50)), "\(log.phases)")
    platform.simulateInput(wheel(-20))
    window.drawFrameIfNeeded()
    platform.simulateInput(mv(100, 101))
    #expect(log.phases.last == .active(pt(100, 71)), "\(log.phases)")
    withExtendedLifetime(window) {}
}

/// **A11** (`OV-F`). The default space is `.local` — (5, 20) on the A9 tile —
/// and a later `.onHover` keeps the continuous callback **and its space**: a
/// `.global` callback followed by `.onHover` still reports (115, 100).
/// Mutations: the default `.global` (this test's first arm and
/// `onContinuousHoverReportsLocalPointsAndEnded` redden); `HoverAttachment.hover`
/// dropping the space (the second arm reads (5, 20)).
@MainActor
@Test func continuousHoverDefaultsToLocalAndALaterOnHoverKeepsTheSpace() throws {
    let log = CSLog()
    var entered: [Bool] = []
    let (window, platform) = try csWindow(size: 200) {
        Column {
            Box().frame(width: px(40), height: px(40)).background(.accent)
                .onContinuousHover { log.phases.append($0) }
                .offset(x: px(30))
        }
    }
    platform.simulateInput(mv(115, 100))
    #expect(log.phases == [.active(pt(5, 20))], "\(log.phases)")
    let later = CSLog()
    let (kept, keptPlatform) = try csWindow(size: 200) {
        Column {
            Box().frame(width: px(40), height: px(40)).background(.accent)
                .onContinuousHover(coordinateSpace: .global) { later.phases.append($0) }
                .onHover { entered.append($0) }
                .offset(x: px(30))
        }
    }
    keptPlatform.simulateInput(mv(115, 100))
    #expect(later.phases == [.active(pt(115, 100))], "\(later.phases)")
    #expect(entered == [true])
    withExtendedLifetime((window, kept)) {}
}

// MARK: - A12–A13: gestures in a named space (OV-H)

/// A 200 × 200 rectangle carrying `gesture`, padded 10 inside a space `c`:
/// the space at (40, 40), the rectangle at (50, 50) in a 300 window.
@MainActor private func gestureTree<G: Gesture>(_ gesture: G) -> some Element {
    HStack {
        Rectangle().frame(width: px(200), height: px(200)).gesture(gesture)
            .padding(Edges(all: px(10))).coordinateSpace(.named("c"))
    }
}

/// **A12** (`OV-H`). A `DragGesture(coordinateSpace: .named("c"))` reports
/// named locations: a press at (60, 70) dragged to (80, 90) has
/// `startLocation` (20, 30) and `location` (40, 50) — the space is at (40, 40).
/// Red on the stub: (60, 70)/(80, 90). Mutation: `point(_:in:)` maps `.named`
/// as `.global`.
@MainActor
@Test func aDragGestureInANamedSpaceReportsNamedLocations() throws {
    var values: [DragGesture.Value] = []
    let (window, platform) = try csWindow {
        gestureTree(DragGesture(minimumDistance: px(1), coordinateSpace: .named("c")).onChanged { values.append($0) })
    }
    platform.simulateInput(ldown(60, 70))
    platform.simulateInput(ldrag(80, 90))
    platform.simulateInput(lup(80, 90))
    let last = try #require(values.last)
    #expect(near(last.startLocation, pt(20, 30)), "\(values)")
    #expect(near(last.location, pt(40, 50)), "\(values)")
    #expect(last.translation == Size(width: px(20), height: px(20)))
    withExtendedLifetime(window) {}
}

/// **A13** (`OV-H`). A `SpatialTapGesture(coordinateSpace: .named("c"))`
/// reports the release in the space: a tap at (60, 70) is (20, 30). Red on
/// the stub: (60, 70). Mutation: A12's (the same site).
@MainActor
@Test func aSpatialTapInANamedSpaceReportsTheNamedPoint() throws {
    var locations: [Point<Pixels>] = []
    let (window, platform) = try csWindow {
        gestureTree(SpatialTapGesture(coordinateSpace: .named("c")).onEnded { locations.append($0.location) })
    }
    platform.simulateInput(ldown(60, 70))
    platform.simulateInput(lup(60, 70))
    #expect(locations.count == 1 && near(locations.first, pt(20, 30)), "\(locations)")
    withExtendedLifetime(window) {}
}

// MARK: - A14–A15: the window size (OV-G, OV-O)

/// Two bars sized from `@Environment(\.windowSize)`: one 7 tall, a quarter of
/// the width wide; one 9 tall, a quarter of the height wide.
private struct WindowSizeBars: Component {
    @Environment(\.windowSize) var size
    var content: some ElementGroup {
        Column {
            Box().frame(width: Pixels(size.width.value / 4), height: Pixels(7)).background(.accent)
            Box().frame(width: Pixels(size.height.value / 4), height: Pixels(9)).background(.accent)
        }
    }
}

/// Whether `id` is the drawn toolbar strip's root or lies under it.
@MainActor private func isUnderStrip(_ id: GlobalElementID) -> Bool {
    var cursor: GlobalElementID? = id
    while let current = cursor {
        if current == ToolbarStrip.rootID { return true }
        cursor = current.parent
    }
    return false
}

@MainActor private func barWidth(_ window: Window, height: Float) -> Float? {
    let matches = window.lastScene.rects.filter { $0.bounds.size.height == height }
    return matches.count == 1 ? matches[0].bounds.size.width : nil
}

/// **A14** (`OV-G`, `OV-O`). `windowSize` is in the first presented frame and
/// follows a resize — 200 × 200 then 280 × 200 — and equals `contentSize`
/// under the drawn toolbar strip too (a fake answering `setToolbar` `false`):
/// the height bar stays 50, the strip included. Red on the stub: no bar (0
/// wide). Mutations: drop the stamp; stamp the root's size below the strip
/// (the strip arm's height bar reads 40.25).
@MainActor
@Test func windowSizeIsInTheFirstPresentedFrameAndFollowsAResize() throws {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200) { Column { WindowSizeBars() } }
    window.drawFrameIfNeeded()
    #expect(barWidth(window, height: 7) == 50, "the first presented frame")
    #expect(barWidth(window, height: 9) == 50)
    platform.simulateResize(to: Size(width: px(280), height: px(200)))
    window.drawFrameIfNeeded()
    #expect(barWidth(window, height: 7) == 70, "the frame presenting the resize")

    let (strip, stripPlatform) = try makeFakeWindowOnDefaultDevice(size: 200) {
        Column {
            WindowSizeBars().toolbar { ToolbarItem { Button("A") {} } }
        }
    }
    stripPlatform.toolbarIsNative = false
    strip.drawFrameIfNeeded()
    for _ in 0..<4 where strip.needsRedraw { strip.drawFrameIfNeeded() }
    try #require(strip.lastHitboxes.contains { isUnderStrip($0.id) }, "the strip is drawn")
    #expect(barWidth(strip, height: 9) == 50, "the strip included: contentSize's height")
    withExtendedLifetime((window, strip)) {}
}

/// **A15** (`OV-G`). Stamping `windowSize` leaves a steady window clean: after
/// the first draw nothing is dirty and a further draw builds nothing
/// (`lastDrawBuildCount` counts the last draw's builds). Red on the stub:
/// green (no stamp) — the mutation is the instrument. Mutation:
/// stamp through `Window.environment` (every build dirties the next).
@MainActor
@Test func stampingWindowSizeLeavesASteadyWindowClean() throws {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 200) { Column { WindowSizeBars() } }
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw, "the first draw left nothing dirty")
    try #require(window.lastDrawBuildCount >= 1, "the first draw built")
    window.drawFrameIfNeeded()
    #expect(window.lastDrawBuildCount == 0, "a steady draw builds nothing")
    withExtendedLifetime(window) {}
}

// MARK: - A16–A18: reporting and presentations

/// **A16** (`KF-J`). A named frame is reported once and on change: moving the
/// container (an offset after the scope) leaves the named frame — and the
/// report count — unchanged, moving the leaf inside it reports once. Red on
/// the stub: the container's move re-reports (named = global). Mutation: the
/// entry built without the composed map (A3's site; a container move then
/// changes the value).
@MainActor
@Test func aNamedGeometryValueIsReportedOnceAndOnChange() throws {
    let log = CSLog(), m = CSModel()
    let (window, _) = try csWindow {
        placed(Rectangle().frame(width: px(40), height: px(20))
            .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .named("outer")) }) { log.add("leaf", $0) }
            .padding(Edges(all: px(m.inner))).coordinateSpace(.named("outer"))
            .offset(x: px(m.offset)))
    }
    try #require(log.frames["leaf"]?.count == 1, "the initial report: \(log.frames)")
    m.offset = 25
    window.drawFrameIfNeeded()
    #expect(log.frames["leaf"]?.count == 1, "the container moved, the named frame did not: \(log.frames)")
    m.inner = 35
    window.drawFrameIfNeeded()
    #expect(log.frames["leaf"]?.count == 2, "\(log.frames)")
    #expect(near(log.frames["leaf"]?.last, rect(35, 35, 40, 20)), "\(log.frames)")
    withExtendedLifetime(window) {}
}

/// **A17** (`OV-M` item 2). A presentation's content inherits its declarer's
/// named spaces: a popover's content inside `outer` reports its frame in
/// `outer` as its global frame less the space's origin (50, 60) — the
/// declarer's container, centred in a 200 window. Red on the stub: named =
/// global. Mutation: `PrepaintPass.deferred` clears the stack.
@MainActor
@Test func aPresentationsContentResolvesItsDeclarersNamedSpace() throws {
    let log = CSLog()
    let (window, _) = try csWindow(size: 200) {
        HStack {
            Rectangle().frame(width: px(40), height: px(20))
                .popover(isPresented: .constant(true)) {
                    Box().frame(width: px(10), height: px(10)).background(.accent)
                        .onGeometryChange(for: [Bounds<Pixels>].self, of: {
                            [$0.frame(in: .global), $0.frame(in: .named("outer"))]
                        }) { log.add("global", $0[0]); log.add("outer", $0[1]) }
                }
                .padding(Edges(all: px(30))).coordinateSpace(.named("outer"))
        }
    }
    let global = try #require(log.frames["global"]?.last)
    let named = try #require(log.frames["outer"]?.last)
    #expect(near(named, Bounds(origin: pt(global.origin.x.value - 50, global.origin.y.value - 60),
                               size: global.size)), "global \(global), named \(named)")
    withExtendedLifetime(window) {}
}

/// What a `SpaceRecorder` saw.
@MainActor private final class SpaceLog {
    var previous: [NamedSpace?] = []
    var recorded: [NamedSpace] = []
}

/// A 40 × 40 leaf that records a presentation space in its prepaint —
/// its own (`.local`) or the one named `outer` — and logs the last frame's.
private struct SpaceRecorder: ProposalElement {
    let log: SpaceLog
    let named: Bool

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 40, height: 40)) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        let frame = pass.frame
        log.previous.append(frame.previousPresentationSpaces[id])
        let space = named ? frame.namedSpace("outer") : frame.localSpace(of: bounds)
        if let space {
            log.recorded.append(space)
            frame.recordPresentationSpace(space, for: id)
        }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// **A18** (`OV-N`, `OV-P`). A declarer's presentation space is carried to the
/// next frame: `.local` under a `.scaleEffect(2)` maps its (10, 10) to the
/// window's (80, 80) — the leaf at (80, 80) scaled about (100, 100) — and the
/// next frame's `previousPresentationSpaces` holds it (and
/// `Window.lastPresentationSpaces`); `.named` records the space `outer`, whose
/// origin is the container's (75, 75). Red on the stub: nothing carried.
/// Mutations: not carried (`previousPresentationSpaces` never handed in);
/// `localSpace` without the composed map (reads (90, 90)).
@MainActor
@Test func presentationSpacesAreCarriedToTheNextFrame() throws {
    let local = SpaceLog()
    let (window, _) = try csWindow(size: 200) { HStack { SpaceRecorder(log: local, named: false).scaleEffect(2) } }
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let first = try #require(local.recorded.first)
    #expect(near(first.toWindow.apply(pt(10, 10)), pt(80, 80)), "\(first.toWindow)")
    #expect(near(first.toSpace?.apply(pt(80, 80)), pt(10, 10)))
    try #require(local.previous.count >= 2)
    #expect(local.previous[0] == nil, "the first frame has no last frame")
    #expect(local.previous.last! == local.recorded[local.recorded.count - 2], "carried: \(local.previous)")
    #expect(window.lastPresentationSpaces.values.first == local.recorded.last)

    let named = SpaceLog()
    let (namedWindow, _) = try csWindow(size: 200) {
        HStack { SpaceRecorder(log: named, named: true).padding(Edges(all: px(5))).coordinateSpace(.named("outer")) }
    }
    namedWindow.setNeedsRedraw()
    namedWindow.drawFrameIfNeeded()
    let space = try #require(named.recorded.first)
    #expect(near(space.toWindow.apply(pt(0, 0)), pt(75, 75)), "the 50 × 50 container at (75, 75): \(space.toWindow)")
    #expect(named.previous.last! == named.recorded[named.recorded.count - 2])
    withExtendedLifetime((window, namedWindow)) {}
}
