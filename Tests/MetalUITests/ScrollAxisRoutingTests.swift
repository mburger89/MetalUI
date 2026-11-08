import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Per-axis wheel routing (Alloy gap G5, rulings `XS-E`, `XS-F`, `XS-G`; probe
// `docs/probes/swiftui-two-axis-scroll.swift`). A wheel event goes WHOLE to one axis (the locked one, else the
// dominant component of the event), to the nearest scroller on the chain that declares that axis, has content past
// its viewport and has room in the wheel's direction; a scroller that cannot passes it on.
//
// Geometry (200-point window): an outer scroller 200 tall over 600 (a 150 box, the inner scroller at y 150..250, a
// 350 box), the inner 200 x 100 over 500 in the other axis. The pointer is at (100, 180), on the inner while the outer
// has moved less than 70. Everything runs on a `FakePlatformWindow`; nothing sleeps; offsets are analytic.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private let onInner = pt(100, 180)

private func phaseless(_ at: Point<Pixels>, dx: Float = 0, dy: Float = 0, timestamp: Double = 1) -> InputEvent {
    .scrollWheel(ScrollEvent(position: at, delta: pt(dx, dy), phase: .none, momentumPhase: .none,
                             isPrecise: true, timestamp: timestamp))
}

private func phased(_ at: Point<Pixels>, _ phase: InputPhase, _ momentum: InputPhase = .none,
                    dx: Float = 0, dy: Float = 0) -> InputEvent {
    .scrollWheel(ScrollEvent(position: at, delta: pt(dx, dy), phase: phase, momentumPhase: momentum,
                             isPrecise: true, timestamp: 1))
}

@MainActor
private final class Seen {
    var events: [ScrollEvent] = []
    var claims = false
}

@MainActor
private func windowFor<Root: Element>(_ content: @escaping @MainActor () -> Root) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 200, content: content)
    settle(window)
    return (window, platform)
}

@MainActor
private func settle(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// (outer, inner) stored offsets; the outer registers first.
@MainActor
private func offsets(_ window: Window) throws -> (outer: Double, inner: Double) {
    let regions = window.lastScrollRegions
    try #require(regions.count == 2, "outer and inner each register one region")
    func stored(_ id: GlobalElementID) -> Double { window.stateTable.peek(id, as: ScrollState.self)?.offset ?? 0 }
    return (stored(regions[0].id), stored(regions[1].id))
}

@MainActor
private func lastScrollTimes(_ window: Window) throws -> (outer: Double, inner: Double) {
    let regions = window.lastScrollRegions
    try #require(regions.count == 2)
    func stamp(_ id: GlobalElementID) -> Double { window.stateTable.peek(id, as: ScrollState.self)?.lastScrollTime ?? -.infinity }
    return (stamp(regions[0].id), stamp(regions[1].id))
}

/// Outer vertical over 600, an inner horizontal scroller 200 x 100 over `innerWidth` at y 150.
@MainActor
private func verticalOuter(innerWidth: Float = 500, around: Seen? = nil) -> some Element {
    ScrollView(.vertical) {
        Column {
            Box().frame(width: px(200), height: px(150))
            ScrollView(.horizontal) { Row { Box().frame(width: px(innerWidth), height: px(100)) } }
                .frame(width: px(200), height: px(100))
                .onScrollWheel { event in around?.events.append(event); return around?.claims ?? false }
            Box().frame(width: px(200), height: px(350))
        }
    }
}

/// Outer vertical over 600, an inner VERTICAL scroller 200 x 100 over `innerHeight` at y 150.
@MainActor
private func verticalInVertical(innerHeight: Float) -> some Element {
    ScrollView(.vertical) {
        Column {
            Box().frame(width: px(200), height: px(150))
            ScrollView(.vertical) { Column { Box().frame(width: px(200), height: px(innerHeight)) } }
                .frame(width: px(200), height: px(100))
            Box().frame(width: px(200), height: px(350))
        }
    }
}

/// **R1** (`XS-F`, probe `N1`). A vertical wheel over a horizontal scroller inside a vertical one reaches the outer.
/// Mutation: a scroller claims whatever its axis (`if region.scroll == axis` -> `if true`): the inner takes it and moves
/// 0, the outer stays 0.
@Test @MainActor func aVerticalWheelOverAHorizontalScrollerInsideAVerticalOneMovesTheOuter() throws {
    let (window, platform) = try windowFor { verticalOuter() }
    platform.simulateInput(phaseless(onInner, dy: -30))
    settle(window)
    let o = try offsets(window)
    #expect(o.outer == 30 && o.inner == 0, "\(o)")
}

/// **R2** (`XS-F`, probe `N3`, `A3`). A diagonal phaseless wheel goes WHOLE to the dominant axis, the other component
/// is dropped (not split between the two scrollers). Mutation: `dominantAxis` returns `nil` for a non-zero delta (every
/// event takes the all-zero path, the innermost scroller): the inner takes the dx, the outer stays 0.
@Test @MainActor func aDiagonalWheelGoesWholeToTheDominantAxis() throws {
    let (window, platform) = try windowFor { verticalOuter() }
    platform.simulateInput(phaseless(onInner, dx: -20, dy: -30))
    settle(window)
    var o = try offsets(window)
    #expect(o.outer == 30 && o.inner == 0, "y-dominant: \(o)")
    platform.simulateInput(phaseless(onInner, dx: -40, dy: -10))
    settle(window)
    o = try offsets(window)
    #expect(o.outer == 30 && o.inner == 40, "x-dominant: the inner takes dx, dy is dropped: \(o)")
    platform.simulateInput(phaseless(onInner, dx: -25, dy: -25))
    settle(window)
    o = try offsets(window)
    #expect(o.outer == 55 && o.inner == 40, "a tie is vertical (probe A7): \(o)")
}

/// **R3** (probe `N2`, `N5`). A horizontal wheel over the inner moves the inner only. Mutation: let the outer take the x
/// too (`scrollTakes` ignored on an unrelated axis) cannot happen for a vertical outer; the mutation here is
/// `dominantAxis` always vertical: the dx never reaches the inner.
@Test @MainActor func aHorizontalWheelMovesTheInnerOnly() throws {
    let (window, platform) = try windowFor { verticalOuter() }
    platform.simulateInput(phaseless(onInner, dx: -20))
    settle(window)
    let o = try offsets(window)
    #expect(o.outer == 0 && o.inner == 20, "\(o)")
}

/// **R4** (probe `N7`). The mirror case: a vertical wheel stays in a vertical inner scroller, a horizontal one reaches
/// the horizontal outer. Mutation: as R1 (a scroller claims whatever its axis).
@Test @MainActor func aHorizontalWheelOverAVerticalScrollerInsideAHorizontalOneMovesTheOuter() throws {
    let (window, platform) = try windowFor {
        ScrollView(.horizontal) {
            Row {
                Box().frame(width: px(100), height: px(200))
                ScrollView(.vertical) { Column { Box().frame(width: px(100), height: px(500)) } }
                    .frame(width: px(100), height: px(200))
                Box().frame(width: px(400), height: px(200))
            }
        }
    }
    let at = pt(110, 100)
    platform.simulateInput(phaseless(at, dx: -30))
    settle(window)
    var o = try offsets(window)
    #expect(o.outer == 30 && o.inner == 0, "dx reaches the outer: \(o)")
    platform.simulateInput(phaseless(at, dy: -25))
    settle(window)
    o = try offsets(window)
    #expect(o.outer == 30 && o.inner == 25, "dy stays in the inner: \(o)")
}

/// **R5** (`XS-G`, probe `A4c`, `A5`, `N10`). A trackpad scroll is locked to the dominant axis of its first event and
/// keeps it through later x-dominant events and momentum. Mutation: drop the lock (`lock: nil` in `applyScroll`): the
/// x-dominant events then reach the inner (inner 90).
@Test @MainActor func aTrackpadScrollStaysLockedToItsFirstAxisIncludingMomentum() throws {
    let (window, platform) = try windowFor { verticalOuter() }
    platform.simulateInput(phased(onInner, .began, dx: -3, dy: -30))
    for _ in 0..<3 { platform.simulateInput(phased(onInner, .changed, dx: -30, dy: -3)) }
    platform.simulateInput(phased(onInner, .ended))
    platform.simulateInput(phased(onInner, .none, .began, dx: -30, dy: -3))
    settle(window)
    let o = try offsets(window)
    #expect(o.inner == 0, "locked to y: the inner never moves: \(o)")
    #expect(o.outer == 30 + 3 * 3 + 3, "y components only, through momentum: \(o)")
}

/// **R6** (`XS-G`). The lock is for scrollers: an `.onScrollWheel` handler around the inner sees the raw event, dx
/// included. Mutation: zero the other component before the handlers run (`local.delta.x = 0` when the axis is vertical).
@Test @MainActor func aWheelHandlerSeesTheRawEventNotTheLockedOne() throws {
    let seen = Seen()
    let (window, platform) = try windowFor { verticalOuter(around: seen) }
    platform.simulateInput(phased(onInner, .began, dx: -3, dy: -30))
    platform.simulateInput(phased(onInner, .changed, dx: -3, dy: -30))
    #expect(seen.events.map { $0.delta.x.value } == [-3, -3], "\(seen.events.map(\.delta))")
    #expect(seen.events.map { $0.delta.y.value } == [-30, -30])
    withExtendedLifetime(window) {}
}

/// **R7** (`XS-F`, `LD-E`). A right-to-left inner scroller keeps its mirrored x sign, and a vertical wheel still passes
/// to the outer. Mutation: `Window.scroll` ignoring `scrollMirrored` reddens the first pair.
@Test @MainActor func aRightToLeftInnerScrollerKeepsItsSignAndPassesTheVerticalWheel() throws {
    let (window, platform) = try windowFor { verticalOuter().environment(\.layoutDirection, .rightToLeft) }
    platform.simulateInput(phaseless(onInner, dx: 20))
    settle(window)
    var o = try offsets(window)
    #expect(o.inner == 20 && o.outer == 0, "fingers right scroll a right-to-left scroller forward: \(o)")
    platform.simulateInput(phaseless(onInner, dy: -30))
    settle(window)
    o = try offsets(window)
    #expect(o.inner == 20 && o.outer == 30, "\(o)")
}

/// **R8** (`XS-F`). A handler around the inner that claims the wheel stops the pass-on: it runs before the outer scroller
/// sees the event. Mutation: look for the scroller before the handlers at each id.
@Test @MainActor func aClaimingHandlerAroundTheInnerStopsTheWheelReachingTheOuter() throws {
    let seen = Seen()
    seen.claims = true
    let (window, platform) = try windowFor { verticalOuter(around: seen) }
    platform.simulateInput(phaseless(onInner, dy: -30))
    settle(window)
    let o = try offsets(window)
    #expect(seen.events.count == 1 && o.outer == 0 && o.inner == 0, "\(o), \(seen.events.count)")
}

/// **R9** (`TI-H`, `XS-F`). A `TextEditor` inside a horizontal scroller scrolls its own lines on a vertical wheel and
/// passes a horizontal one to the scroller. Mutation: restore the unconditional editor claim (drop `axis != .horizontal`):
/// the dx is swallowed, the outer stays 0.
@Test @MainActor func aTextEditorTakesTheVerticalWheelAndPassesTheHorizontalOne() throws {
    @MainActor final class Notes { var text = (1...60).map { "line \($0)" }.joined(separator: "\n") }
    let notes = Notes()
    let (window, platform) = try windowFor {
        ScrollView(.horizontal) {
            TextEditor(text: notes.text) { notes.text = $0 }.frame(width: px(400), height: px(200))
        }
    }
    let editor = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    let target = try #require(editor.handlers.textInput)
    #expect(target.maxScrollY > 0)
    let at = pt(100, 100)
    platform.simulateInput(phaseless(at, dx: -30))
    settle(window)
    let outer = try #require(window.lastScrollRegions.first)
    #expect(window.stateTable.peek(outer.id, as: ScrollState.self)?.offset == 30, "dx reaches the horizontal scroller")
    platform.simulateInput(phaseless(at, dy: -50))
    settle(window)
    let after = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    #expect(Double(after.bounds.origin.y.value) - (after.handlers.textInput?.originY ?? 0) == 50, "dy scrolls the lines")
    #expect(window.stateTable.peek(outer.id, as: ScrollState.self)?.offset == 30, "and leaves the scroller")
}

/// **R10** (`IF-H`). An all-zero event keeps its old answer: it stamps the innermost scroller only, wherever the
/// axes. Mutation: `dominantAxis` returns vertical for a zero delta: the inner (horizontal) passes it and the outer is
/// stamped instead.
@Test @MainActor func anAllZeroEventStampsTheInnermostScrollerOnly() throws {
    let (window, platform) = try windowFor { verticalOuter() }
    platform.simulateInput(phaseless(onInner, timestamp: 9))
    settle(window)
    let stamps = try lastScrollTimes(window)
    #expect(stamps.inner == 9 && stamps.outer == -.infinity, "\(stamps)")
}

/// **R11** (`XS-E`, probe `N6b`). A same-axis inner scroller whose content fits its viewport passes the wheel to the
/// outer. Mutation: take by the declared axes (`scrollAxes`) instead of `scrollTakes` AND ignore the room: the
/// fitting inner takes it, the outer stays 0 (swapping `scrollTakes` alone stays green: a scroller whose content fits has no
/// room either, so the room test says the same thing, `LR-X`). The control: an overflowing inner keeps it (probe `N6c`).
@Test @MainActor func aFittingSameAxisInnerScrollerPassesTheWheelUp() throws {
    let (fitting, platform) = try windowFor { verticalInVertical(innerHeight: 60) }
    platform.simulateInput(phaseless(onInner, dy: -30))
    settle(fitting)
    let o = try offsets(fitting)
    #expect(o.outer == 30 && o.inner == 0, "\(o)")
    let (overflowing, platform2) = try windowFor { verticalInVertical(innerHeight: 400) }
    platform2.simulateInput(phaseless(onInner, dy: -30))
    settle(overflowing)
    let c = try offsets(overflowing)
    #expect(c.outer == 0 && c.inner == 30, "\(c)")
}

/// **R12** (`XS-F`, probe `N8`, `N8b`, `N8c`). A one-axis scroller at its end in the wheel's direction passes the wheel
/// to the scroller above, and takes it again in the other direction. Mutation: ignore the room (`scrollRoom.allows`
/// always true): the inner keeps the wheel at its end (outer stays 0).
@Test @MainActor func aOneAxisScrollerAtItsEndPassesTheWheelUp() throws {
    let (window, platform) = try windowFor { verticalInVertical(innerHeight: 400) }
    // Inner 100 over 400: its end is at 300.
    platform.simulateInput(phaseless(onInner, dy: -300))
    settle(window)
    var o = try offsets(window)
    #expect(o.inner == 300 && o.outer == 0, "\(o)")
    platform.simulateInput(phaseless(onInner, dy: -30))
    settle(window)
    o = try offsets(window)
    #expect(o.inner == 300 && o.outer == 30, "at its end the wheel goes up: \(o)")
    platform.simulateInput(phaseless(pt(100, 150), dy: 40))
    settle(window)
    o = try offsets(window)
    #expect(o.inner == 260 && o.outer == 30, "the other direction is the inner's again: \(o)")
}

/// **R13** (`XS-F`). With nobody above to take it, a scroller at its end keeps the wheel: it stamps (the indicator) and
/// banks for the prepaint clamp, as before. Mutation: drop the fallback: nothing is stamped.
@Test @MainActor func aScrollerAtItsEndWithNobodyAboveStillTakesTheWheel() throws {
    let (window, platform) = try windowFor { ScrollView(.vertical) { Column { Box().frame(width: px(200), height: px(500)) } } }
    platform.simulateInput(phaseless(pt(100, 100), dy: -300, timestamp: 4))
    settle(window)
    platform.simulateInput(phaseless(pt(100, 100), dy: -20, timestamp: 5))
    let region = try #require(window.lastScrollRegions.first)
    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.lastScrollTime == 5)
    settle(window)
    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 300, "clamped back by prepaint")
}
