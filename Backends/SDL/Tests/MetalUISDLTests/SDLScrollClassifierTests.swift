import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL

// SDL precise scroll, lane 1, tests T1-T12 (rulings `TP-B`, `TP-C`, `TP-F`, `TP-M`; spec
// `docs/superpowers/specs/2026-10-24-sdl-precise-scroll-design.md` section 4). The classifier is pure and
// time is injected, so no test sleeps and none needs SDL, a window or a presented frame.

private let t0 = 100.0
private let quiet = SDLScrollClassifier.quietInterval

private func fresh(_ mode: SDLScrollPrecision = .automatic) -> SDLScrollClassifier {
    SDLScrollClassifier(mode: mode)
}

/// **T1** (`TP-B`). A whole notch is a wheel and opens no stream.
/// Mutation: tolerance test `> 1e-4` becomes `>= 0` (a whole number then reads fractional).
@Test func aWholeNotchIsNotPreciseAndOpensNoStream() {
    var c = fresh()
    let r = c.classify(dx: 0, dy: -1, at: t0)
    #expect(!r.isPrecise)
    #expect(r.phase == .none)
    #expect(!r.closedStale)
    #expect(c.deadline == nil)
}

/// **T2** (`TP-B`, `TP-C`). A fractional event is precise and opens a stream.
/// Mutation: classify by truncation (`Int(v) != 0`), which reads 0.25 as whole.
@Test func aFractionalEventIsPreciseAndBegins() throws {
    var c = fresh()
    let r = c.classify(dx: 0, dy: 0.25, at: t0)
    #expect(r.isPrecise)
    #expect(r.phase == .began)
    let deadline = try #require(c.deadline)
    #expect(abs(deadline - (t0 + quiet)) < 1e-9)
}

/// **T3** (`TP-C`). A second event inside the interval changes and moves the deadline.
/// Mutation: always `.began`.
@Test func aSecondEventInsideTheQuietIntervalChanges() throws {
    var c = fresh()
    _ = c.classify(dx: 0, dy: 0.25, at: t0)
    let r = c.classify(dx: 0, dy: 0.5, at: t0 + 0.05)
    #expect(r.isPrecise)
    #expect(r.phase == .changed)
    #expect(!r.closedStale)
    let deadline = try #require(c.deadline)
    #expect(abs(deadline - (t0 + 0.05 + quiet)) < 1e-9)
}

/// **T4** (`TP-C`). An integral event inside a stream stays precise.
/// Mutation: drop the sticky clause (precise iff fractional).
@Test func anIntegralEventInsideAStreamStaysPrecise() {
    var c = fresh()
    _ = c.classify(dx: 0, dy: 0.3, at: t0)
    let r = c.classify(dx: 0, dy: 1, at: t0 + 0.05)
    #expect(r.isPrecise)
    #expect(r.phase == .changed)
}

/// **T5** (`TP-C`, `TP-M`). A notch after the quiet interval is a wheel again, and the old stream closes first.
/// Mutation: `quietInterval` 0.15 becomes 1.5 (the notch then stays precise).
@Test func aNotchAfterTheQuietIntervalIsAWheelAgain() {
    var c = fresh()
    _ = c.classify(dx: 0, dy: 0.3, at: t0)
    let r = c.classify(dx: 0, dy: -1, at: t0 + 0.4)
    #expect(!r.isPrecise)
    #expect(r.phase == .none)
    #expect(r.closedStale)
    #expect(c.deadline == nil)
}

/// **T6** (`TP-M`). A fractional event after the deadline begins a new stream and reports the stale end.
/// Mutation: never set `closedStale`.
@Test func anEventAfterTheDeadlineBeginsANewStreamAndReportsTheStaleEnd() {
    var c = fresh()
    _ = c.classify(dx: 0, dy: 0.3, at: t0)
    let r = c.classify(dx: 0, dy: 0.3, at: t0 + 1)
    #expect(r.closedStale)
    #expect(r.isPrecise)
    #expect(r.phase == .began)
}

/// **T7** (`TP-F`). `expire` ends a stream exactly once, at the boundary.
/// Mutation: `>` for `>=`; not clearing the stream (a second `true`).
@Test func expireEndsAStreamExactlyOnceAtTheBoundary() {
    var c = fresh()
    _ = c.classify(dx: 0, dy: 0.3, at: t0)
    let end = c.deadline ?? 0
    let early = c.expire(at: end - 0.001)
    let atEnd = c.expire(at: end)
    let again = c.expire(at: end)
    #expect(!early)
    #expect(atEnd)
    #expect(!again)
    #expect(c.deadline == nil)
}

/// **T8**. A horizontal fraction is precise.
/// Mutation: test `y` only.
@Test func aHorizontalFractionIsPrecise() {
    var c = fresh()
    let r = c.classify(dx: 0.2, dy: 0, at: t0)
    #expect(r.isPrecise)
    #expect(r.phase == .began)
}

/// **T9** (characterizes divergence 845). A hi-res wheel step (1/120 of a notch) reads precise, by design.
/// Mutation: tolerance `1e-2` (it then reads a wheel).
@Test func aHiResWheelStepIsPreciseByDesign() {
    var c = fresh()
    let r = c.classify(dx: 0, dy: 1.0 / 120.0, at: t0)
    #expect(r.isPrecise)
}

/// **T10** (`TP-D`). `.disabled` is today's behaviour: false, `.none`, no stream.
/// Mutation: ignore the mode.
@Test func disabledModeIsTodaysBehaviour() {
    var c = fresh(.disabled)
    let r = c.classify(dx: 0, dy: 0.25, at: t0)
    #expect(!r.isPrecise)
    #expect(r.phase == .none)
    #expect(!r.closedStale)
    #expect(c.deadline == nil)
    let expired = c.expire(at: t0 + 10)
    #expect(!expired)
}

/// **T11** (`TP-M`). A non-finite delta is not precise and does not trap. A characterization pin: NaN and
/// infinity compare false against the tolerance with no guard, so no mutation can redden it.
@Test func aNonFiniteDeltaIsNotPreciseAndDoesNotTrap() {
    var c = fresh()
    let a = c.classify(dx: .nan, dy: 0, at: t0)
    let b = c.classify(dx: 0, dy: .infinity, at: t0)
    let d = c.classify(dx: -.infinity, dy: .nan, at: t0)
    #expect(!a.isPrecise && !b.isPrecise && !d.isPrecise)
    #expect(c.deadline == nil)
}

/// **T12** (`TP-F`). `reset` drops a stream with no end.
/// Mutation: reset leaves the deadline.
@Test func resetDropsTheStreamWithoutAnEnd() {
    var c = fresh()
    _ = c.classify(dx: 0, dy: 0.3, at: t0)
    c.reset()
    #expect(c.deadline == nil)
    let expired = c.expire(at: t0 + 10)
    #expect(!expired)
}

// MARK: - P2-P6: the platform and window (`TP-F`, `TP-I`, `TP-D`)
// `handleWheel` and `expireScrollStreams(now:)` take injected times, so none sleeps. P1 is test 1.16 in
// `SDLInputAPITests` (a real pushed event; `mui_push_event` stamps SDL's own `SDL_GetTicksNS` clock, which is
// `mui_now`'s).

@MainActor
private func scrollWindow(_ options: SDLPlatform.Options = Options0.hidden) throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(options: options)
    let window = try platform.openSDLWindow(title: "MetalUI scroll test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    platform.pumpEvents()
    return (platform, window)
}

private enum Options0 { static let hidden = SDLPlatform.Options(hidesWindows: true) }

@MainActor
private func record(_ window: SDLWindow) -> ScrollLog {
    let log = ScrollLog()
    window.onInput = { event in
        if case .scrollWheel(let s) = event { log.events.append(s) }
        return true
    }
    return log
}

@MainActor private final class ScrollLog { var events: [ScrollEvent] = [] }

private let pos = Point(x: Pixels(7), y: Pixels(9))

/// **P2**. A precise stream is ended once by expiry: one zero-delta `.ended`, precise, the last position and
/// modifiers; a second expiry delivers none.
/// Mutation: expiry delivers nothing, or twice.
@MainActor
@Test func aPreciseStreamIsEndedOnceByExpiry() throws {
    let (platform, window) = try scrollWindow()
    let log = record(window)
    window.handleWheel(dx: 0, dy: 0.25, timestamp: t0, modifiers: [.shift], position: pos)
    try #require(log.events.count == 1)
    platform.expireScrollStreams(now: t0 + 0.05)
    #expect(log.events.count == 1)
    platform.expireScrollStreams(now: t0 + 0.2)
    try #require(log.events.count == 2)
    let ended = log.events[1]
    #expect(ended.phase == .ended)
    #expect(ended.isPrecise)
    #expect(ended.delta == Point(x: Pixels(0), y: Pixels(0)))
    #expect(ended.position == pos)
    #expect(ended.modifiers == [.shift])
    #expect(ended.momentumPhase == .none)
    platform.expireScrollStreams(now: t0 + 5)
    #expect(log.events.count == 2)
}

/// **P3** (`TP-M`). A stale stream is ended before the next `.began`: an event after the deadline with no poll
/// between reaches the window as began, ended, began.
/// Mutation: skip `closedStale`.
@MainActor
@Test func aStaleStreamIsEndedBeforeTheNextBegan() throws {
    let (_, window) = try scrollWindow()
    let log = record(window)
    window.handleWheel(dx: 0, dy: 0.25, timestamp: t0, modifiers: [], position: pos)
    window.handleWheel(dx: 0, dy: 0.25, timestamp: t0 + 1, modifiers: [], position: pos)
    #expect(log.events.map(\.phase) == [.began, .ended, .began])
    // and a notch after a stale stream: the end comes first, the notch is phaseless
    window.handleWheel(dx: 0, dy: -1, timestamp: t0 + 3, modifiers: [], position: pos)
    try #require(log.events.count == 5)
    #expect(log.events.map(\.phase) == [.began, .ended, .began, .ended, .none])
    #expect(!log.events[4].isPrecise)
}

/// **P4** (`TP-F`). Closing, or losing focus, drops a stream with no `.ended` (`IF-H` owns the cancel).
/// Mutation: do not reset.
@MainActor
@Test func closingOrLosingFocusDropsTheStreamWithoutEnded() throws {
    let (platform, window) = try scrollWindow()
    let log = record(window)
    window.handleWheel(dx: 0, dy: 0.25, timestamp: t0, modifiers: [], position: pos)
    window.focusLost()
    platform.expireScrollStreams(now: t0 + 5)
    #expect(log.events.map(\.phase) == [.began])
    window.handleWheel(dx: 0, dy: 0.25, timestamp: t0 + 6, modifiers: [], position: pos)
    #expect(log.events.map(\.phase) == [.began, .began])
    window.close()
    // a closed window leaves the platform's list, so ask the window itself
    window.expireScrollStream(now: t0 + 10)
    #expect(log.events.map(\.phase) == [.began, .began])
    #expect(window.scrollDeadline == nil)
}

/// **P5** (`TP-I`). The idle wait shortens while a stream is open: 250 with none, the remaining milliseconds
/// rounded up with one, never below 1.
/// Mutation: constant 250.
@MainActor
@Test func theIdleWaitShortensWhileAStreamIsOpen() throws {
    let (platform, window) = try scrollWindow()
    _ = record(window)
    #expect(platform.scrollWaitTimeoutMilliseconds(now: t0) == 250)
    window.handleWheel(dx: 0, dy: 0.25, timestamp: t0, modifiers: [], position: pos)
    #expect(platform.scrollWaitTimeoutMilliseconds(now: t0) == 150)
    #expect(platform.scrollWaitTimeoutMilliseconds(now: t0 + 0.1005) == 50)
    #expect(platform.scrollWaitTimeoutMilliseconds(now: t0 + 0.2) == 1)
    platform.expireScrollStreams(now: t0 + 0.2)
    #expect(platform.scrollWaitTimeoutMilliseconds(now: t0 + 0.2) == 250)
}

/// **P6** (`TP-D`). `scrollPrecision: .disabled` through the platform keeps the old wheel: a fraction is
/// phaseless and not precise, no stream, no `.ended`, the wait stays 250.
/// Mutation: ignore the option.
@MainActor
@Test func scrollPrecisionDisabledKeepsTheOldWheel() throws {
    let (platform, window) = try scrollWindow(SDLPlatform.Options(hidesWindows: true, scrollPrecision: .disabled))
    let log = record(window)
    window.handleWheel(dx: 0, dy: 0.25, timestamp: t0, modifiers: [], position: pos)
    platform.expireScrollStreams(now: t0 + 5)
    try #require(log.events.count == 1)
    #expect(!log.events[0].isPrecise)
    #expect(log.events[0].phase == .none)
    #expect(platform.scrollWaitTimeoutMilliseconds(now: t0) == 250)
    #expect(SDLPlatform.Options.default.scrollPrecision == .automatic)
}
