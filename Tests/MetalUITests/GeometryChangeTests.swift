import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// `onGeometryChange(for:of:action:)` — key and focus scoping, lane B (rulings
// `KF-J`, `KF-S`, `KF-V` item 1; spec
// `docs/superpowers/specs/2026-10-08-key-focus-design.md` §5.2, B1–B14).
// SwiftUI's side is `docs/probes/swiftui-key-focus.swift`, arms G1–G7; each
// test names the arm it follows.
//
// **No test sleeps**: windows are `makeFakeWindowOnDefaultDevice` windows
// driven by `drawFrameIfNeeded()`, `simulateResize(to:)` and model writes.
// Red before, for every test: the file does not compile at `c62d6ba` (no
// `onGeometryChange`); the red was taken against the lane-B stub (the API
// compiles, the scope notes nothing), recorded in the lane's red commit.

// MARK: - Harness

/// Every action a tree fired, in order.
@MainActor final class GCLog {
    var entries: [String] = []
    var transforms = 0
    var actions = 0
    func add(_ entry: String) { entries.append(entry) }
}

/// The model a window test writes between frames — an `@Observable`, so a
/// write dirties the window as a click handler's would.
@Observable @MainActor final class GCModel {
    var shown = true
    var tick = 0
    var width: Float = 1
    var size = Size<Pixels>(width: Pixels(0), height: Pixels(0))
}

@MainActor func gcWindow<Root: Element>(size: Int = 200, startsDisplayLink: Bool = false,
                                        _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    try makeFakeWindowOnDefaultDevice(size: size, startsDisplayLink: startsDisplayLink, content: content)
}

/// A `w × h` accent tile.
@MainActor func gcTile(_ w: Float, _ h: Float) -> some StyledElement {
    Box().frame(width: Pixels(w), height: Pixels(h)).background(.accent)
}

/// The width of the one presented rect `height` tall, or `nil`.
@MainActor func gcWidth(_ window: Window, height: Float) -> Float? {
    let matches = window.lastScene.rects.filter { $0.bounds.size.height == height }
    return matches.count == 1 ? matches[0].bounds.size.width : nil
}

private func gcSize(_ w: Float, _ h: Float) -> Size<Pixels> {
    Size(width: Pixels(w), height: Pixels(h))
}

private func gcText(_ s: Size<Pixels>) -> String { "\(Int(s.width.value))x\(Int(s.height.value))" }

private let gcRoot = GlobalElementID.child(of: nil, at: 0, name: nil)

/// A component whose `@State` its own geometry action writes: the label (a
/// rect 7 tall) is a quarter of the greedy area's width (B3, B4, B10).
private struct GCResizer: Component {
    let log: GCLog
    @State var seen: Float = 1
    var content: some ElementGroup {
        Column {
            Box().frame(width: Pixels(seen), height: Pixels(7)).background(.accent)
            Box().frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: Float.self, of: { $0.size.width.value }) { width in
                    log.add("w:\(Int(width))")
                    seen = width / 4
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Two proposal views, 50 and 30 tall, and no wrapper: a two-view group (G6).
private struct GCPair: Component {
    var content: some ProposalElementGroup {
        Rectangle().frame(width: Pixels(20), height: Pixels(50))
        Rectangle().frame(width: Pixels(20), height: Pixels(30))
    }
}

// MARK: - SwiftUI's semantics (B1–B7)

/// **B1** (G1: `g:200x180->200x180,appear`). The initial value is reported
/// once, before `onAppear`. Red on the stub: `["appear"]`. Mutation: hand the
/// lifecycle events before the geometry events in `takeEvents`.
@MainActor
@Test func theInitialValueIsReportedOnceBeforeOnAppear() throws {
    let log = GCLog()
    let (window, _) = try gcWindow {
        Column {
            gcTile(20, 10)
                .onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { log.add("g:\(gcText($0))") }
                .onAppear { log.add("appear") }
        }
    }
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(log.entries == ["g:20x10", "appear"], "\(log.entries)")
}

/// **B2** (G1, old and new form). The two-argument form passes the initial
/// value as both old and new. Red on the stub: nothing. Mutation: pass a
/// default `old` (a zero size) on the initial call.
@MainActor
@Test func theTwoArgumentFormPassesOldEqualNewInitially() throws {
    let log = GCLog()
    let (window, _) = try gcWindow {
        Column {
            gcTile(20, 10).onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { old, new in
                log.add("\(gcText(old))->\(gcText(new))")
            }
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["20x10->20x10"], "\(log.entries)")
}

/// **B3** (`KF-J` item 4). A resize is reported in the frame presenting it:
/// the action's `@State` write is in the scene after ONE `simulateResize` and
/// ONE `drawFrameIfNeeded` (the drain's settle build). Red on the stub: the
/// label stays 1 wide. Mutation: run geometry events after `finishFrame`
/// (queued for the next frame).
@MainActor
@Test func aResizeIsReportedInTheFramePresentingIt() throws {
    let log = GCLog()
    let (window, platform) = try gcWindow(size: 200) { Box { GCResizer(log: log) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    window.drawFrameIfNeeded()
    #expect(gcWidth(window, height: 7) == 50, "200 / 4 in the first presented frame")
    platform.simulateResize(to: gcSize(320, 200))
    window.drawFrameIfNeeded()
    #expect(gcWidth(window, height: 7) == 80, "320 / 4 in the frame presenting the resize")
    #expect(log.entries == ["w:200", "w:320"], "\(log.entries)")
}

/// **B4** (G5: one call per resize step). Five resize steps, each drawn, are
/// five calls after the initial one. Red on the stub: none. Mutation: drop
/// every change event after the first (a reported flag per entry).
@MainActor
@Test func eachResizeStepIsReportedOnce() throws {
    let log = GCLog()
    let (window, platform) = try gcWindow(size: 200) { Box { GCResizer(log: log) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    window.drawFrameIfNeeded()
    for width in [210, 220, 230, 240, 250] {
        platform.simulateResize(to: gcSize(Float(width), 200))
        window.drawFrameIfNeeded()
    }
    #expect(log.entries == ["w:200", "w:210", "w:220", "w:230", "w:240", "w:250"], "\(log.entries)")
}

/// **B5** (G3: an unchanged value is not reported). Frames redrawn by an
/// unrelated write report nothing. Red on the stub: the initial call is
/// missing. Mutation: compare nothing (report every build).
@MainActor
@Test func anUnchangedValueIsNotReported() throws {
    let log = GCLog(), m = GCModel()
    let (window, _) = try gcWindow {
        Column {
            gcTile(20, 10).onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { log.add("g:\(gcText($0))") }
            gcTile(Float(10 + m.tick), 3)
        }
    }
    window.drawFrameIfNeeded()
    for _ in 0..<3 {
        m.tick += 1
        window.drawFrameIfNeeded()
    }
    #expect(gcWidth(window, height: 3) == 13, "the unrelated write was drawn")
    #expect(log.entries == ["g:20x10"], "\(log.entries)")
}

/// **B6** (G6: `h:88` on a `Group` of 50 and 30 with spacing 8). A group
/// reports the union of its nodes, once. Red on the stub: nothing. Mutation:
/// report the first node's bounds (50).
@MainActor
@Test func aGroupReportsTheUnionOnce() throws {
    let log = GCLog()
    let (window, _) = try gcWindow {
        VStack(spacing: Pixels(8)) {
            GCPair().onGeometryChange(for: Float.self, of: { $0.size.height.value }) { log.add("h:\(Int($0))") }
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["h:88"], "\(log.entries)")
}

/// **B7** (G7: initial again on re-insertion). Content that leaves and
/// returns reports its initial value again. Red on the stub: nothing.
/// Mutation: keep a dropped key's last value (the return compares equal).
@MainActor
@Test func reinsertionReportsTheInitialValueAgain() throws {
    let log = GCLog(), m = GCModel()
    let (window, _) = try gcWindow {
        Column {
            if m.shown {
                gcTile(20, 10).onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { old, new in
                    log.add("\(gcText(old))->\(gcText(new))")
                }
            }
            gcTile(5, 3)
        }
    }
    window.drawFrameIfNeeded()
    m.shown = false
    window.drawFrameIfNeeded()
    m.shown = true
    window.drawFrameIfNeeded()
    #expect(log.entries == ["20x10->20x10", "20x10->20x10"], "\(log.entries)")
}

// MARK: - Coordinate spaces (B8, B9)

/// The `.global` frame one tile reports under `wrap`.
@MainActor private func globalFrame<Root: Element>(_ root: @escaping @MainActor (GCLog) -> Root,
                                                   scrollBy dy: Float? = nil) throws -> [Bounds<Pixels>] {
    var frames: [Bounds<Pixels>] = []
    let log = GCLog()
    let (window, platform) = try gcWindow { root(log) }
    window.drawFrameIfNeeded()
    if let dy {
        platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: Pixels(100), y: Pixels(100)),
                                                        delta: Point(x: Pixels(0), y: Pixels(dy)))))
        window.drawFrameIfNeeded()
    }
    for entry in log.entries {
        let parts = entry.split(separator: ",").compactMap { Float($0) }
        frames.append(Bounds(origin: Point(x: Pixels(parts[0]), y: Pixels(parts[1])),
                             size: Size(width: Pixels(parts[2]), height: Pixels(parts[3]))))
    }
    return frames
}

@MainActor private func gcGlobalWatcher(_ log: GCLog) -> (Bounds<Pixels>) -> Void {
    { b in log.add("\(b.origin.x.value),\(b.origin.y.value),\(b.size.width.value),\(b.size.height.value)") }
}

/// **B8** (G4a: `.offset(x: 10)` written after the modifier moves the global
/// frame 0 → 10; G4b its idle control). `frame(in: .global)` includes an
/// enclosing render effect and an enclosing scroll offset. Red on the stub:
/// no frame is reported. Mutations: drop the composed affine (the offset
/// arm reads 0); drop `activeOffset` (the scroll arm reads 0).
@MainActor
@Test func frameInGlobalIncludesAnEnclosingOffsetAndScroll() throws {
    let plain = try globalFrame { log in
        HStack {
            Rectangle().frame(width: Pixels(20), height: Pixels(10))
                .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) }, action: gcGlobalWatcher(log))
        }
    }
    let offset = try globalFrame { log in
        HStack {
            Rectangle().frame(width: Pixels(20), height: Pixels(10))
                .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) }, action: gcGlobalWatcher(log))
                .offset(x: Pixels(10))
        }
    }
    let p = try #require(plain.first), o = try #require(offset.first)
    #expect(plain.count == 1 && offset.count == 1, "\(plain) \(offset)")
    #expect(o.origin.x.value - p.origin.x.value == 10, "G4a: \(p) → \(o)")
    #expect(o.size == p.size)

    // The scroll arm: content scrolled 20 up reports a frame 20 higher.
    let scrolled = try globalFrame({ log in
        Box {
            ScrollView(.vertical) {
                Column {
                    gcTile(20, 10).onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) },
                                                    action: gcGlobalWatcher(log))
                    gcTile(20, 400)
                }
            }
        }
        .frame(width: Pixels(200), height: Pixels(100))
    }, scrollBy: -20)
    try #require(scrolled.count == 2, "the initial frame and the scrolled one: \(scrolled)")
    #expect(scrolled[1].origin.y.value - scrolled[0].origin.y.value == -20, "\(scrolled)")
    #expect(scrolled[1].origin.x == scrolled[0].origin.x)
}

/// **B9** (`KF-J` item 3). `size` is the untransformed layout size: a
/// `scaleEffect(2)` written after the modifier leaves it 20 × 10 while the
/// global frame (its bounding box) is 40 × 20. Red on the stub: nothing.
/// Mutation: take `size` from the transformed box.
@MainActor
@Test func sizeIgnoresAScaleEffect() throws {
    let log = GCLog()
    let (window, _) = try gcWindow {
        HStack {
            Rectangle().frame(width: Pixels(20), height: Pixels(10))
                .onGeometryChange(for: String.self, of: { proxy in
                    "\(gcText(proxy.size)) \(gcText(proxy.frame(in: .global).size))"
                }) { log.add($0) }
                .scaleEffect(2)
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["20x10 40x20"], "\(log.entries)")
}

// MARK: - Timing and work (B10–B13)

/// **B10** (`KF-J` item 4, `LC-E`). A geometry action's `@State` write is not
/// a phase write: after the settle, the next frame finds nothing to do and
/// the display link pauses. Mutation: run the action inside `prepaintGroup`
/// (a phase write keeps the window dirty forever).
@MainActor
@Test func aGeometryWriteLetsTheDisplayLinkPause() throws {
    let log = GCLog()
    let (window, _) = try gcWindow(size: 200) { Box { GCResizer(log: log) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    window.drawFrameIfNeeded()
    try #require(gcWidth(window, height: 7) == 50)
    let pauses = window.pausesEntered
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(window.pausesEntered >= pauses + 1, "the window paused")
    #expect(!window.needsRedraw)
    #expect(log.entries == ["w:200"], "\(log.entries)")
}

/// **B11** (`KF-J` item 5). A steady frame with K = 3 scopes calls each
/// transform once and runs no action: an unrelated write's frame counts 3
/// transforms and 0 actions. Mutation: call the action on every build.
@MainActor
@Test func aSteadyFrameRunsKTransformsAndNoAction() throws {
    let log = GCLog(), m = GCModel()
    func watched(_ w: Float) -> some ElementGroup {
        gcTile(w, 10).onGeometryChange(for: Float.self, of: { proxy in
            log.transforms += 1
            return proxy.size.width.value
        }) { _ in log.actions += 1 }
    }
    let (window, _) = try gcWindow {
        Column {
            watched(10)
            watched(20)
            watched(30)
            gcTile(Float(10 + m.tick), 3)
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.actions == 3, "three initial calls")
    let (transforms, actions) = (log.transforms, log.actions)
    m.tick += 1
    window.drawFrameIfNeeded()
    try #require(window.lastDrawBuildCount == 1, "one build: the actions wrote nothing")
    #expect(log.transforms - transforms == 3)
    #expect(log.actions - actions == 0)
}

/// **B12** (`LC-E` item 1). A geometry action runs under its scope's
/// `StateDispatch`: the owner is the scope's position, and the frame is not
/// rendering. Red on the stub: nothing runs. Mutation: drop `StateDispatch`
/// in the drain path (run `event.action()` bare).
@MainActor
@Test func geometryActionsRunUnderStateDispatch() throws {
    var owner: GlobalElementID?
    let (window, _) = try gcWindow {
        Column {
            gcTile(20, 10).onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in
                owner = StateDispatch.owner
            }
        }
    }
    window.drawFrameIfNeeded()
    #expect(owner == GlobalElementID.child(of: gcRoot, at: 0, name: nil), "\(String(describing: owner))")
}

/// **B13** (M4-a end to end). A `MetalView` viewport knows its size in the
/// first presented frame: its geometry action stores the size in a model, and
/// an overlay label (a rect 7 tall, a quarter of the viewport's width) reads
/// it. Red on the stub: the label is 0 wide (absent). Mutation: B3's.
@MainActor
@Test func aViewportKnowsItsSizeInTheFirstPresentedFrame() throws {
    let m = GCModel()
    let (window, platform) = try gcWindow(size: 200) {
        ZStack(alignment: .topLeading) {
            MetalView(redraw: .continuous) { _ in }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { m.size = $0 }
            Box().frame(width: Pixels(m.size.width.value / 4), height: Pixels(7)).background(.accent)
        }
    }
    window.drawFrameIfNeeded()
    #expect(gcWidth(window, height: 7) == 50, "the first presented frame carries the viewport's size")
    platform.simulateResize(to: gcSize(280, 200))
    window.drawFrameIfNeeded()
    #expect(gcWidth(window, height: 7) == 70, "and the frame presenting a live resize")
}

// MARK: - Both entries (B14)

/// **B14** (`LC` test 1.10's shape). The untyped entry (the scope in a legacy
/// `Column`) and the typed entry (over proposal content in an `HStack`) each
/// report. Red on the stub: nothing. Mutation: break the typed entry's key
/// (note nothing from it) — the `HStack` arm reddens alone.
@MainActor
@Test func theTypedAndUntypedEntriesAreEachPinned() throws {
    let log = GCLog()
    let (window, _) = try gcWindow {
        Column {
            gcTile(20, 10).onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { log.add("untyped \(gcText($0))") }
            HStack {
                Rectangle().frame(width: Pixels(30), height: Pixels(10))
                    .onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { log.add("typed \(gcText($0))") }
            }
        }
    }
    window.drawFrameIfNeeded()
    #expect(Set(log.entries) == ["untyped 20x10", "typed 30x10"], "\(log.entries)")
    #expect(log.entries.count == 2)
}

// MARK: - Order (B15)

/// **B15** (`KF-Y` item 3; `LC-F`'s order, a two-layer chain per `OM-AD`).
/// Geometry actions run in reverse note order, children first: an inner and
/// an outer `.onGeometryChange` on one rectangle, an `.offset` between them,
/// run `inner` then `outer` on the first frame. Mutation Bx-order-forward:
/// sort `closeGeometry`'s events ascending (`outer` runs first).
@MainActor
@Test func geometryActionsRunChildrenFirst() throws {
    let log = GCLog()
    let (window, _) = try gcWindow {
        HStack {
            Rectangle().frame(width: Pixels(20), height: Pixels(10))
                .onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in log.add("inner") }
                .offset(x: Pixels(5))
                .onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in log.add("outer") }
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["inner", "outer"], "\(log.entries)")
}
