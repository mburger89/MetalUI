import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Variable-height `List`, lane 1 (rulings `VL-G` item 2, `VL-H`, `VL-P`): the
// `Frame` hooks a variable list calls from `prepaint`, driven here by a probe
// leaf inside a real `ScrollView` in a fake window — no `List` yet.
//
// - `Frame.noteScrollAnchorAdjustment(scroller:delta:)`: summed per scroller,
//   added after paint (after any `scrollTo` resolution for that scroller) to
//   the stored offset through `withState`, one more frame asked for; a zero
//   delta is never recorded.
// - `ScrollRequestQueue.carry(_:)`: appends without `onEnqueue`, so a phase
//   never dirties the window.
// - `Frame.unresolvedScrollRequestsWithScope(enclosing:)`: a pending request's
//   scope and anchor, which a list needs to carry a refinement.
//
// Fixture: a 100 × 100 window; a reader over a vertical `ScrollView` whose
// content column is a 200pt spacer, a 10pt row `.id("t")` (content y 200), a
// 1000pt spacer and the 10pt probe — 1220pt of content, so any offset up to
// 1120 is unclamped. Red-before: the hooks first land as no-ops (record §82 §3).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func sized(width: Float? = nil, height: Float? = nil, column: Bool = false) -> Style {
    var s = Style()
    if column { s.flexDirection = .column }
    if let width { s.size.width = .length(.pixels(px(width))); s.flexShrink = 0 }
    if let height { s.size.height = .length(.pixels(px(height))); s.flexShrink = 0 }
    return s
}

/// What the probe does on its next prepaint, and what it saw.
@MainActor
private final class ProbeScript {
    /// Called once with this delta on the next prepaint (nil: not called).
    var delta: Double?
    /// Carried once on the next prepaint.
    var carry: ScrollRequest?
    /// The offset the enclosing scroller frame carried at each prepaint —
    /// the offset that frame paints at (prepaint bounds are layout space,
    /// unscrolled: measured, they read 1210 at every offset).
    var offsets: [Double] = []
    /// How many times the hook was called.
    var hookCalls = 0
    /// Each prepaint's `unresolvedScrollRequestsWithScope` answer.
    var requests: [[(key: AnyHashable, scope: GlobalElementID, anchor: UnitPoint?)]] = []
    /// The reader's proxy.
    var proxy: ScrollViewProxy?
    func keep(_ proxy: ScrollViewProxy) -> Bool {
        self.proxy = proxy
        return true
    }
}

/// A 100 × 10 lowered leaf that runs `script` in its `prepaint`.
private struct AnchorProbe: Element {
    let script: ProbeScript

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let node = pass.lowerLegacyLeaf(Style(), declared: Style(), site: .box) {
            pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 100, height: 10)) }
        }
        return (node, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        if let scroller = pass.frame.activeScrollerFrame { script.offsets.append(scroller.offset) }
        script.requests.append(pass.frame.unresolvedScrollRequestsWithScope(enclosing: id)
            .map { (key: $0.key, scope: $0.scope, anchor: $0.anchor) })
        if let delta = script.delta, let scroller = pass.frame.activeScrollerFrame {
            pass.frame.noteScrollAnchorAdjustment(scroller: scroller.scrollerID, delta: delta)
            script.hookCalls += 1
            script.delta = nil
        }
        if let request = script.carry {
            pass.frame.scrollRequestQueue.carry(request)
            script.carry = nil
        }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// The fixture, drawn until clean; the viewport required at 100.
@MainActor
private func probeWindow(_ script: ProbeScript) throws -> Window {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
        Box(style: sized(width: 100, height: 100, column: true)) {
            ScrollViewReader { proxy in
                let _ = script.keep(proxy)
                ScrollView {
                    Box(style: sized(width: 100, column: true)) {
                        Box(style: sized(width: 100, height: 200))
                        Box(style: sized(width: 100, height: 10)).id("t")
                        Box(style: sized(width: 100, height: 1000))
                        AnchorProbe(script: script)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
    settle(window)
    let region = try #require(window.lastScrollRegions.first)
    try #require(region.bounds.size.height.value == 100, "control: a 100pt viewport")
    try #require(!window.needsRedraw, "control: a settled window")
    return window
}

@MainActor
private func settle(_ window: Window) {
    var frames = 0
    while window.needsRedraw && frames < 6 {
        window.drawFrameIfNeeded()
        frames += 1
    }
}

@MainActor
private func scrollerID(_ window: Window) throws -> GlobalElementID {
    try #require(window.lastScrollRegions.first).id
}

@MainActor
private func storedOffset(_ window: Window) throws -> Double {
    window.stateTable.peek(try scrollerID(window), as: ScrollState.self)?.offset ?? 0
}

/// Draws exactly one frame, dirty or not.
@MainActor
private func drawOne(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

/// **1.11 (`VL-G` item 2).** At offset 100, a delta of 30 noted in prepaint:
/// this frame still paints at 100 (its scroller frame carries 100),
/// the stored offset is 130 after the frame, and the window wants another
/// frame; that frame paints at 130 and asks for nothing. Mutations: (a) the
/// adjustment not applied (stored 100); (b) no `requestAnotherFrame` — each
/// reddens it.
@Test @MainActor
func anAnchorAdjustmentMovesTheStoredOffsetAfterPaintAndAsksForAFrame() throws {
    let script = ProbeScript()
    let window = try probeWindow(script)
    try #require(script.offsets.last == 0, "control: the settled fixture is at 0")
    let id = try scrollerID(window)
    window.stateTable.withState(id, initial: ScrollState()) { $0.offset = 100 }
    script.delta = 30
    drawOne(window)
    try #require(script.hookCalls == 1, "control: the probe called the hook")
    #expect(script.offsets.last == 100, "this frame paints at the old offset")
    #expect(try storedOffset(window) == 130)
    #expect(window.needsRedraw, "an adjustment asks for the next frame")
    window.drawFrameIfNeeded()
    #expect(script.offsets.last == 130, "the next frame paints at the adjusted offset")
    #expect(!window.needsRedraw)
}

/// **1.12 (`VL-G` item 2).** A `scrollTo("t", anchor: .top)` resolving to 200
/// (row t's content y) and a delta of 30 in the same frame: the delta is added
/// after the resolution — 230. Mutation: the absolute resolution applied after
/// (overriding) the adjustment (reads 200).
@Test @MainActor
func anAnchorAdjustmentAddsToAScrollToResolutionInTheSameFrame() throws {
    let script = ProbeScript()
    let window = try probeWindow(script)
    let proxy = try #require(script.proxy)
    proxy.scrollTo("t", anchor: .top)
    script.delta = 30
    window.drawFrameIfNeeded()
    try #require(script.hookCalls == 1, "control: the probe called the hook")
    #expect(try storedOffset(window) == 230)
}

/// **1.13 (`VL-G` item 2).** A zero delta is never recorded: no write and no
/// frame asked for. Mutation: record and request unconditionally (the window
/// stays dirty).
@Test @MainActor
func aZeroAdjustmentWritesNothingAndAsksForNoFrame() throws {
    let script = ProbeScript()
    let window = try probeWindow(script)
    let id = try scrollerID(window)
    window.stateTable.withState(id, initial: ScrollState()) { $0.offset = 50 }
    script.delta = 0
    drawOne(window)
    try #require(script.hookCalls == 1, "control: the probe called the hook")
    #expect(try storedOffset(window) == 50)
    #expect(!window.needsRedraw, "a zero adjustment asks for no frame")
}

/// **1.14 (`VL-H`).** A request carried from prepaint dirties nothing (the
/// window is clean after the frame, the request waits in the queue) and is
/// resolved by the next frame drawn: row t at `.top` → 200. Mutation: `carry`
/// calls `onEnqueue` (the window is dirty after the frame).
@Test @MainActor
func aCarriedScrollRequestDirtiesNothingAndResolvesNextFrame() throws {
    let script = ProbeScript()
    let window = try probeWindow(script)
    let proxy = try #require(script.proxy)
    script.carry = ScrollRequest(scope: proxy.scope, key: AnyHashable("t"), anchor: .top)
    drawOne(window)
    #expect(!window.needsRedraw, "a carried request dirties nothing")
    #expect(window.scrollRequests.pending.count == 1, "the request waits for the next frame")
    #expect(try storedOffset(window) == 0, "not resolved by the frame that carried it")
    drawOne(window)
    #expect(try storedOffset(window) == 200, "resolved by the next frame")
}

/// **1.15 (`VL-P`).** `scrollTo("nothing", anchor: .bottom)` under the reader:
/// the probe (inside the reader, so enclosed by its scope) reads one pending
/// request with key "nothing", the reader's scope and `.bottom`. Mutation: the
/// accessor answers `anchor: nil`.
@Test @MainActor
func anUnresolvedRequestCarriesItsScopeAndAnchorToTheList() throws {
    let script = ProbeScript()
    let window = try probeWindow(script)
    let proxy = try #require(script.proxy)
    proxy.scrollTo("nothing", anchor: .bottom)
    window.drawFrameIfNeeded()
    let seen = try #require(script.requests.last)
    try #require(seen.count == 1, "one pending request: \(seen.count)")
    #expect(seen[0].key == AnyHashable("nothing"))
    #expect(seen[0].scope == proxy.scope)
    #expect(seen[0].anchor == .bottom)
}
