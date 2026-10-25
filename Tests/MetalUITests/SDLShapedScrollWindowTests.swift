import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// SDL precise scroll, lane 2 — the `Window` pins W1-W4 (ruling `TP-H`, spec
// `docs/superpowers/specs/2026-10-24-sdl-precise-scroll-design.md` section 4).
//
// `Window` is unchanged by `TP-`: these run the stream SDL now produces
// (synthesized `.began`, `.changed`, a zero-delta `.ended`, `isPrecise` true,
// momentum `.none`) through a real `Window`, so they are green on arrival and
// red only under the mutations each names. Nothing sleeps.
// Geometry: a 100 x 100 window, root column of two 100 x 40 rows (A above B)
// centred at y 10...90, so A is at (50, 30) and B at (50, 70).

@MainActor
private final class SLog {
    var entries: [String] = []
    var events: [ScrollEvent] = []
    var claims = true
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private let atA = pt(50, 30)
private let atB = pt(50, 70)

/// An event as `SDLWindow` now delivers it: precise, momentum none.
private func sdl(_ at: Point<Pixels>, _ phase: InputPhase, dy: Float, timestamp: Double = 1) -> InputEvent {
    .scrollWheel(ScrollEvent(position: at, delta: pt(0, dy), phase: phase, momentumPhase: .none,
                             isPrecise: true, timestamp: timestamp))
}

/// A hand-built phaseless event: what a wheel notch is, and what no SDL event
/// inside an open stream can be (`TP-C`, `TP-H`).
private func phaseless(_ at: Point<Pixels>, dy: Float) -> InputEvent {
    .scrollWheel(ScrollEvent(position: at, delta: pt(0, dy), phase: .none, momentumPhase: .none,
                             isPrecise: false, timestamp: 1))
}

@MainActor
private func sWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 100, content: content)
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

@MainActor
private func twoRows(_ log: SLog) -> some Element {
    Column {
        Box().frame(width: px(100), height: px(40))
            .onScrollWheel { event in log.entries.append("A"); log.events.append(event); return log.claims }
        Box().frame(width: px(100), height: px(40))
            .onScrollWheel { event in log.entries.append("B"); log.events.append(event); return log.claims }
    }
}

/// **W1** (`TP-H`). A synthesized `.began` over A latches A as AppKit's does:
/// a `.changed` with the pointer over B and the zero-delta `.ended` still reach
/// A. **The `.ended` itself does not clear the latch** (only a momentum end, a
/// phaseless event or a new `.began` does, `IF-G` item 3, which SDL never sends
/// a momentum for): the next phaseless event dispatches by the pointer and
/// ends it, and a new `.began` replaces it, so a stale latch is never reached
/// from SDL (the spec's "ended clears it" was inexact, `TP-Q`).
/// Mutations: `ScrollLatch.isGestureEvent` false for `.changed`; delete
/// `applyScroll`'s `phase == .none` reset (reddens the second half).
@MainActor
@Test func aSyntheticBeganLatchesTheCoverAndTheNextEventEndsOrReplacesIt() throws {
    let log = SLog()
    let (window, platform) = try sWindow { twoRows(log) }
    platform.simulateInput(sdl(atA, .began, dy: -5))
    platform.simulateInput(sdl(atB, .changed, dy: -5))
    platform.simulateInput(sdl(atB, .ended, dy: 0))
    #expect(log.entries == ["A", "A", "A"], "the latch followed the stream: \(log.entries)")
    #expect(log.events.last?.delta.y.value == 0 && log.events.last?.phase == .ended, "\(String(describing: log.events.last))")
    log.entries = []
    platform.simulateInput(phaseless(atB, dy: -1))
    #expect(log.entries == ["B"], "a notch after the end is dispatched by the pointer: \(log.entries)")
    log.entries = []
    platform.simulateInput(sdl(atB, .changed, dy: -5))
    #expect(log.entries == ["B"], "and it ended the latch: \(log.entries)")
    // A new stream after an ended replaces the latch.
    log.entries = []
    platform.simulateInput(sdl(atA, .began, dy: -5))
    platform.simulateInput(sdl(atA, .ended, dy: 0))
    platform.simulateInput(sdl(atB, .began, dy: -5))
    platform.simulateInput(sdl(atA, .changed, dy: -5))
    #expect(log.entries == ["A", "A", "B", "B"], "a began replaces the standing latch: \(log.entries)")
    withExtendedLifetime(window) {}
}

/// **W2** (`TP-H`). A phaseless event ends an open latch (`IF-G` item 3), as a
/// notch after the quiet interval does; SDL cannot send one inside a stream,
/// so the event is hand-built. Mutation: delete `Window.applyScroll`'s
/// `phase == .none` latch reset.
@MainActor
@Test func aNotchDuringAPreciseStreamEndsTheLatch() throws {
    let log = SLog()
    let (window, platform) = try sWindow { twoRows(log) }
    platform.simulateInput(sdl(atA, .began, dy: -5))
    platform.simulateInput(phaseless(atB, dy: -10))
    platform.simulateInput(sdl(atB, .changed, dy: -5))
    #expect(log.entries == ["A", "B", "B"], "the notch ended the latch: \(log.entries)")
    withExtendedLifetime(window) {}
}

/// **W3** (`TP-H`). A precise SDL stream scrolls a `ScrollView` by its summed
/// deltas; the zero-delta `.ended` leaves the offset where it is.
/// Mutation: apply `.ended` with a nonzero repeat of the last delta.
@MainActor
@Test func aPreciseSDLStreamScrollsAScrollViewByItsDelta() throws {
    let (window, platform) = try sWindow {
        ScrollView(.vertical) {
            Column { Box().frame(width: px(100), height: px(40)); Box().frame(width: px(100), height: px(40))
                Box().frame(width: px(100), height: px(40)); Box().frame(width: px(100), height: px(40)) }
        }.frame(width: px(100), height: px(100))
    }
    func offset() throws -> Double {
        let region = try #require(window.lastHitboxes.first { $0.scroll != nil }, "the scroller")
        var value = 0.0
        window.stateTable.withState(region.id, initial: ScrollState()) { value = $0.offset }
        return value
    }
    platform.simulateInput(sdl(pt(50, 50), .began, dy: -5))
    platform.simulateInput(sdl(pt(50, 50), .changed, dy: -7.5))
    platform.simulateInput(sdl(pt(50, 50), .changed, dy: -2.5))
    #expect(try offset() == 15, "offsets equal the summed deltas")
    platform.simulateInput(sdl(pt(50, 50), .ended, dy: 0))
    #expect(try offset() == 15, "a zero-delta ended scrolls nothing")
    withExtendedLifetime(window) {}
}

/// **W4** (`CI-AH` unchanged). A handler on a `ScrollView`'s content runs
/// before the scrolling and vetoes it for a precise stream as for a wheel.
/// Mutation: consult the chain's scroll regions before any handler (the
/// dispatch order flipped).
@MainActor
@Test func aHandlerAboveAScrollViewVetoStillWorksForAPreciseStream() throws {
    let log = SLog()
    let (window, platform) = try sWindow {
        ScrollView(.vertical) {
            Column { Box().frame(width: px(100), height: px(40)); Box().frame(width: px(100), height: px(40))
                Box().frame(width: px(100), height: px(40)); Box().frame(width: px(100), height: px(40)) }
                .onScrollWheel { event in log.entries.append("content"); log.events.append(event); return log.claims }
        }.frame(width: px(100), height: px(100))
    }
    func offset() throws -> Double {
        let region = try #require(window.lastHitboxes.first { $0.scroll != nil }, "the scroller")
        var value = 0.0
        window.stateTable.withState(region.id, initial: ScrollState()) { value = $0.offset }
        return value
    }
    platform.simulateInput(sdl(pt(50, 50), .began, dy: -5))
    platform.simulateInput(sdl(pt(50, 50), .changed, dy: -5))
    platform.simulateInput(sdl(pt(50, 50), .ended, dy: 0))
    #expect(log.entries == ["content", "content", "content"], "\(log.entries)")
    #expect(try offset() == 0, "the claiming handler vetoed every event")
    log.claims = false
    platform.simulateInput(sdl(pt(50, 50), .began, dy: -5))
    platform.simulateInput(sdl(pt(50, 50), .changed, dy: -5))
    #expect(try offset() == 10, "declined, so it scrolled by the deltas")
    withExtendedLifetime(window) {}
}
