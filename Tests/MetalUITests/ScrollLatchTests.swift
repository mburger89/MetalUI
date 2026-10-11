import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Input follow-ups, lane 2 — wheel latching and the guaranteed terminal scroll
// phase, tests 2.1–2.10 (rulings `IF-G`, `IF-H`; spec
// `docs/superpowers/specs/2026-10-10-input-followups-design.md` §3).
//
// Everything runs on a `FakePlatformWindow`; nothing sleeps. Geometry: a 100 ×
// 100 window whose root column of two 100 × 40 rows (A above B) is centred at
// y 10…90, so A is at (50, 30) and B at (50, 70).

@MainActor
private final class LLog {
    var entries: [String] = []
    var events: [ScrollEvent] = []
    var showA = true
    var claims = true
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private let atA = pt(50, 30)
private let atB = pt(50, 70)

private func scroll(_ at: Point<Pixels>, _ phase: InputPhase, _ momentum: InputPhase = .none,
                    dy: Float = -5, timestamp: Double = 1) -> InputEvent {
    .scrollWheel(ScrollEvent(position: at, delta: pt(0, dy), phase: phase, momentumPhase: momentum,
                             isPrecise: true, timestamp: timestamp))
}

@MainActor
private func latchWindow<Root: Element>(size: Int = 100, _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: size, content: content)
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

@MainActor
private func settleLatch(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor
private func twoRows(_ log: LLog) -> some Element {
    Column {
        if log.showA {
            Box().frame(width: px(100), height: px(40))
                .onScrollWheel { event in log.entries.append("A"); log.events.append(event); return log.claims }
        }
        Box().frame(width: px(100), height: px(40))
            .onScrollWheel { event in log.entries.append("B"); log.events.append(event); return log.claims }
    }
}

/// **2.1** (`IF-G` items 1, 2). A trackpad scroll that began over A goes to A
/// for every later event, the glide included, though the pointer is over B.
/// Mutation: dispatch every event by the pointer.
@MainActor
@Test func aTrackpadScrollsMomentumGoesToTheElementItBeganOver() throws {
    let log = LLog()
    let (window, platform) = try latchWindow { twoRows(log) }
    platform.simulateInput(scroll(atA, .began))
    platform.simulateInput(scroll(atB, .changed))
    platform.simulateInput(scroll(atB, .ended))
    platform.simulateInput(scroll(atB, .none, .began))
    platform.simulateInput(scroll(atB, .none, .changed))
    platform.simulateInput(scroll(atB, .none, .ended))
    #expect(log.entries == ["A", "A", "A", "A", "A", "A"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **2.2** (`IF-G` item 3). A new `.began` replaces the latch. Mutation: never
/// replace.
@MainActor
@Test func aNewBeganReplacesTheLatch() throws {
    let log = LLog()
    let (window, platform) = try latchWindow { twoRows(log) }
    platform.simulateInput(scroll(atA, .began))
    platform.simulateInput(scroll(atB, .changed))
    platform.simulateInput(scroll(atB, .began))
    platform.simulateInput(scroll(atA, .changed))
    #expect(log.entries == ["A", "A", "B", "B"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **2.3** (`IF-G` item 3). A wheel mouse (no phase, no momentum) is never
/// latched and clears a latch: it goes to the pointer's element, and the next
/// phased event does too. Mutation: latch on any event.
@MainActor
@Test func aWheelMouseIsNeverLatchedAndClearsTheLatch() throws {
    let log = LLog()
    let (window, platform) = try latchWindow { twoRows(log) }
    platform.simulateInput(scroll(atA, .began))
    platform.simulateInput(scroll(atB, .none))
    platform.simulateInput(scroll(atB, .changed))
    #expect(log.entries == ["A", "B", "B"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **2.4** (`IF-G` item 2). A latched `ScrollView` keeps scrolling when the
/// pointer leaves it: the offset advances off its bounds. Mutation: keep the
/// `contains` test on the latched path.
@MainActor
@Test func aLatchedScrollViewKeepsScrollingWhenThePointerLeavesIt() throws {
    let (window, platform) = try latchWindow {
        Column {
            ScrollView(.vertical) {
                Column { Box().frame(width: px(100), height: px(40)); Box().frame(width: px(100), height: px(40))
                    Box().frame(width: px(100), height: px(40)) }
            }.frame(width: px(100), height: px(60))
            Box().frame(width: px(100), height: px(40))
        }
    }
    func offset() throws -> Double {
        let region = try #require(window.lastHitboxes.first { $0.scroll != nil }, "the scroller")
        var value = 0.0
        window.stateTable.withState(region.id, initial: ScrollState()) { value = $0.offset }
        return value
    }
    platform.simulateInput(scroll(pt(50, 20), .began))
    #expect(try offset() == 5)
    platform.simulateInput(scroll(pt(50, 90), .changed))
    platform.simulateInput(scroll(pt(50, 90), .none, .changed))
    #expect(try offset() == 15, "off its bounds the latched scroller still moved")
    platform.simulateInput(scroll(pt(50, 90), .none))
    #expect(try offset() == 15, "a wheel mouse off the scroller does not")
    withExtendedLifetime(window) {}
}

/// **2.5** (`IF-G` item 3). The latch ends at the momentum's end (that event
/// still goes to the latch), and a `.mayBegin` latches nothing. Mutations:
/// never clear; latch `.mayBegin`.
@MainActor
@Test func theLatchEndsAtMomentumEndedAndAMayBeginLatchesNothing() throws {
    let log = LLog()
    let (window, platform) = try latchWindow { twoRows(log) }
    platform.simulateInput(scroll(atA, .began))
    platform.simulateInput(scroll(atB, .ended))
    platform.simulateInput(scroll(atB, .none, .began))
    platform.simulateInput(scroll(atB, .none, .ended))
    platform.simulateInput(scroll(atB, .changed))
    #expect(log.entries == ["A", "A", "A", "A", "B"], "\(log.entries)")
    log.entries = []
    platform.simulateInput(scroll(atA, .mayBegin))
    platform.simulateInput(scroll(atB, .changed))
    #expect(log.entries == ["A", "B"], "the mayBegin was dispatched by the pointer and latched nothing: \(log.entries)")
    withExtendedLifetime(window) {}
}

/// **2.6** (`IF-G` item 3). A latched element that left the frame falls back to
/// the pointer, without a trap. Mutation: trap or ignore on a missing id.
@MainActor
@Test func aLatchedElementThatLeftTheFrameFallsBackToThePointer() throws {
    let log = LLog()
    let (window, platform) = try latchWindow { twoRows(log) }
    platform.simulateInput(scroll(atA, .began))
    log.showA = false
    settleLatch(window)
    platform.simulateInput(scroll(atA, .changed))   // B is now at A's old place
    #expect(log.entries == ["A", "B"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **2.7** (`IF-H`). Leaving key mid-scroll sends exactly one synthesized
/// terminal event to the latched element's handler: the finger stage a
/// `.cancelled` phase, the glide a `.cancelled` momentum phase, delta 0.
/// Mutation: skip the hook; synthesize twice.
@MainActor
@Test func leavingKeyMidScrollSynthesizesOneCancelledToTheHandler() throws {
    let log = LLog()
    let (window, platform) = try latchWindow { twoRows(log) }
    platform.simulateInput(scroll(atA, .began))
    platform.simulateInput(scroll(atB, .changed))
    log.entries = []; log.events = []
    platform.simulateControlActiveStateChange(to: .inactive)
    platform.simulateControlActiveStateChange(to: .key)
    platform.simulateControlActiveStateChange(to: .inactive)
    #expect(log.entries == ["A"], "once: \(log.entries)")
    var got = try #require(log.events.first)
    #expect(got.phase == .cancelled && got.momentumPhase == .none && got.delta.y.value == 0, "\(got)")
    // The glide stage.
    platform.simulateInput(scroll(atA, .began))
    platform.simulateInput(scroll(atA, .ended))
    platform.simulateInput(scroll(atB, .none, .began))
    log.entries = []; log.events = []
    platform.simulateControlActiveStateChange(to: .key)
    platform.simulateControlActiveStateChange(to: .inactive)
    #expect(log.entries == ["A"], "once: \(log.entries)")
    got = try #require(log.events.first)
    #expect(got.phase == .none && got.momentumPhase == .cancelled && got.delta.y.value == 0, "\(got)")
    withExtendedLifetime(window) {}
}

/// **2.8** (`IF-H`). A scroll that ended normally, and events with no phase at
/// all (SDL's shape), synthesize nothing. Mutation: synthesize unconditionally.
@MainActor
@Test func aScrollThatEndedNormallySynthesizesNothingAndPhaselessEventsNeverDo() throws {
    let log = LLog()
    let (window, platform) = try latchWindow { twoRows(log) }
    platform.simulateInput(scroll(atA, .began))
    platform.simulateInput(scroll(atA, .ended))
    platform.simulateInput(scroll(atA, .none, .began))
    platform.simulateInput(scroll(atA, .none, .ended))
    platform.simulateControlActiveStateChange(to: .inactive)
    #expect(log.entries == ["A", "A", "A", "A"], "ended normally: \(log.entries)")
    log.entries = []
    platform.simulateControlActiveStateChange(to: .key)
    platform.simulateInput(scroll(atA, .none))
    platform.simulateInput(scroll(atA, .none))
    platform.simulateControlActiveStateChange(to: .inactive)
    #expect(log.entries == ["A", "A"], "no phases: \(log.entries)")
    withExtendedLifetime(window) {}
}

/// **2.9** (`IF-H`). The synthesized event reaches the wheel handlers only: a
/// handler that declines does not let the enclosing `ScrollView` take it (its
/// offset and its last-scroll stamp are unchanged), and the handler's answer is
/// ignored. Mutation: route it through `scroll(_:by:)`.
@MainActor
@Test func aSynthesizedCancelMovesNoScroller() throws {
    let log = LLog()
    log.claims = false
    let (window, platform) = try latchWindow {
        ScrollView(.vertical) {
            Column {
                Box().frame(width: px(100), height: px(40))
                    .onScrollWheel { event in log.entries.append("row"); log.events.append(event); return log.claims }
                Box().frame(width: px(100), height: px(40)); Box().frame(width: px(100), height: px(40))
            }
        }
    }
    let region = try #require(window.lastHitboxes.first { $0.scroll != nil }, "the scroller")
    func state() -> (Double, Double) {
        var value = (0.0, 0.0)
        window.stateTable.withState(region.id, initial: ScrollState()) { value = ($0.offset, $0.lastScrollTime) }
        return value
    }
    platform.simulateInput(scroll(pt(50, 20), .began, timestamp: 7))
    let before = state()
    #expect(before.0 == 5 && before.1 == 7, "the declined began scrolled: \(before)")
    log.entries = []; log.events = []
    platform.simulateControlActiveStateChange(to: .inactive)
    #expect(log.entries == ["row"], "\(log.entries)")
    let after = state()
    #expect(after.0 == before.0 && after.1 == before.1, "unmoved: \(after) vs \(before)")
    withExtendedLifetime(window) {}
}

/// **2.10** (`IF-H`). Closing mid-scroll synthesizes the cancel too. Mutation:
/// omit the close path.
@MainActor
@Test func closingMidScrollSynthesizesTheCancel() throws {
    let log = LLog()
    let (window, platform) = try latchWindow { twoRows(log) }
    platform.simulateInput(scroll(atA, .began))
    log.entries = []; log.events = []
    window.runDisappearancesForClose()
    #expect(log.entries == ["A"], "\(log.entries)")
    #expect(log.events.first?.phase == .cancelled, "\(String(describing: log.events.first))")
    withExtendedLifetime(window) {}
}
