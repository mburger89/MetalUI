@testable import MetalUI
import MetalUITesting
import Testing

// R3-5 — gesture composition (rulings `GE-A`…, `docs/superpowers/2026-10-31-gesture-composition-decisions.md`).
// `sequenced(before:)` and `SequenceGesture.Value`, composed `updating`/`onChanged`/`onEnded`, a custom `Gesture`
// with a `body`, and `DragGesture.Value`'s `time`/`velocity`/`predictedEnd*`. Everything runs through the real
// `Window` over `MetalUITesting` (portable); nothing sleeps: the clock is `TestWindow`'s and every pointer event
// carries the timestamp the test gives it. Probe arms (`docs/probes/swiftui-gesture-composition.swift`, header):
// S1…S7b sequenced, X1…X2b composed, C1…C5 custom, D0…D15 the drag value, recorded 2026-10-31.
// Geometry: a 400 × 300 window, a 200 × 200 chip centred at (200, 150); local = window − (100, 50).

@MainActor private final class GCLog {
    var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
    /// The log with consecutive duplicates collapsed: one event may build more than once (a settle build).
    var distinct: [String] {
        var out: [String] = []
        for entry in entries where out.last != entry { out.append(entry) }
        return out
    }
}

private func at(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }
private let center = at(200, 150)
private func down(_ p: Point<Pixels> = center, count: Int = 1, t: Double? = nil) -> InputEvent {
    .mouseDown(MouseEvent(position: p, clickCount: count, timestamp: t))
}
private func dragged(_ p: Point<Pixels>, t: Double? = nil) -> InputEvent {
    .mouseDragged(MouseEvent(position: p, timestamp: t))
}
private func up(_ p: Point<Pixels> = center, count: Int = 1, t: Double? = nil) -> InputEvent {
    .mouseUp(MouseEvent(position: p, clickCount: count, timestamp: t))
}

@MainActor private func chipWindow<C: ElementGroup>(_ chip: @escaping @MainActor () -> C) throws -> TestWindow {
    try harnessWindow { Column { chip() } }
}

@MainActor private func chip<G: Gesture>(_ gesture: G) -> some ElementGroup {
    Rectangle().frame(width: Pixels(200), height: Pixels(200)).gesture(gesture)
}

private func f(_ x: Pixels) -> String { String(format: "%.1f", Double(x.value)) }

private func drag(_ v: DragGesture.Value) -> String {
    "start=(\(f(v.startLocation.x)),\(f(v.startLocation.y))) loc=(\(f(v.location.x)),\(f(v.location.y)))"
}

private typealias PressDrag = SequenceGesture<LongPressGesture, DragGesture>

private func seq(_ v: PressDrag.Value) -> String {
    switch v {
    case .first(let held): return "first(\(held))"
    case .second(let held, let value): return "second(\(held), \(value.map(drag) ?? "nil"))"
    }
}

/// A long press (0.3 s, 20 pt) then a drag, logging every `onChanged` and `onEnded`.
@MainActor private func pressThenDrag(_ log: GCLog, dragMinimum: Float = 0) -> PressDrag {
    LongPressGesture(minimumDuration: 0.3, maximumDistance: Pixels(20))
        .sequenced(before: DragGesture(minimumDistance: Pixels(dragMinimum)))
}

private struct LoggedSequence: Component {
    let log: GCLog
    let dragMinimum: Float
    var content: some ElementGroup {
        chip(pressThenDrag(log, dragMinimum: dragMinimum)
            .onChanged { log.add("changed \(seq($0))") }
            .onEnded { log.add("ended \(seq($0))") })
    }
}

// MARK: - 1: sequenced(before:) values (S1, S2, S4, S4b, S5b)

/// **1.1** (`S1`). Press, hold past 0.3 s, move, move, release: `.first(true)` at the press, `.second(true, nil)` when
/// the long press ends while held, then the drag's values — **its start is the first pointer event after the long
/// press ended**, here the first move — and `onEnded` with the last. Mutation: gate the second member open from the
/// press (its start is then the press).
@Test @MainActor func aLongPressThenDragReportsFirstThenSecondWithTheDragStartingAtTheFirstEventAfter() throws {
    let log = GCLog()
    let window = try chipWindow { LoggedSequence(log: log, dragMinimum: 0) }
    window.send(down()); window.tick()
    #expect(log.entries == ["changed first(true)"], "\(log.entries)")
    window.advance(by: 0.5)
    window.send(dragged(at(210, 150))); window.tick()
    window.send(dragged(at(230, 150))); window.tick()
    window.send(up(at(230, 150))); window.tick()
    #expect(log.entries == [
        "changed first(true)",
        "changed second(true, nil)",
        "changed second(true, start=(110.0,100.0) loc=(110.0,100.0))",
        "changed second(true, start=(110.0,100.0) loc=(130.0,100.0))",
        "ended second(true, start=(110.0,100.0) loc=(130.0,100.0))",
    ], "\(log.entries)")
}

/// **1.2** (`S2`, `S5b`). With `minimumDistance: 10` the drag still starts at the first event after the long press: a
/// 3 pt move sets the start, the 20 pt one reports; a move made before the long press ended is not the start.
/// Mutation: start the drag at the press point.
@Test @MainActor func theDragMinimumIsMeasuredFromTheFirstEventAfterTheLongPress() throws {
    let log = GCLog()
    let window = try chipWindow { LoggedSequence(log: log, dragMinimum: 10) }
    window.send(down()); window.tick()
    window.send(dragged(at(203, 150))); window.tick()   // before the long press ends: no start
    window.advance(by: 0.5)
    window.send(dragged(at(213, 150))); window.tick()   // the first event after: the start
    #expect(log.entries == ["changed first(true)", "changed second(true, nil)"], "\(log.entries)")
    window.send(dragged(at(230, 150))); window.tick()
    window.send(up(at(230, 150))); window.tick()
    #expect(log.entries.suffix(2) == [
        "changed second(true, start=(113.0,100.0) loc=(130.0,100.0))",
        "ended second(true, start=(113.0,100.0) loc=(130.0,100.0))",
    ], "\(log.entries)")
}

/// **1.3** (`S4`, `S4b`). Held, then released without moving: a drag with no minimum ends at that release with a value
/// and no change before it; one with a minimum never begins, so nothing ends. Mutation: fail the drag when it was never
/// reported.
@Test @MainActor func aReleaseRightAfterTheLongPressEndsOnlyADragWithNoMinimum() throws {
    let zero = GCLog()
    let w0 = try chipWindow { LoggedSequence(log: zero, dragMinimum: 0) }
    w0.send(down()); w0.tick(); w0.advance(by: 0.5)
    w0.send(up()); w0.tick()
    #expect(zero.entries == ["changed first(true)", "changed second(true, nil)",
                             "ended second(true, start=(100.0,100.0) loc=(100.0,100.0))"], "\(zero.entries)")

    let ten = GCLog()
    let w10 = try chipWindow { LoggedSequence(log: ten, dragMinimum: 10) }
    w10.send(down()); w10.tick(); w10.advance(by: 0.5)
    w10.send(up()); w10.tick()
    #expect(ten.entries == ["changed first(true)", "changed second(true, nil)"], "\(ten.entries)")
}

// MARK: - 2: a failed first member fails the sequence (S3, S5)

/// **2.1** (`S3`, `S5`). A release before the long press, or a move past its `maximumDistance`, fails the whole
/// sequence: the drag that follows reports nothing, and `onEnded` never runs. Mutation: leave the second member
/// gated-open after the first fails.
@Test @MainActor func aFailedFirstGestureFailsTheSequence() throws {
    let early = GCLog()
    let w1 = try chipWindow { LoggedSequence(log: early, dragMinimum: 0) }
    w1.send(down()); w1.tick(); w1.advance(by: 0.1)
    w1.send(up()); w1.tick(); w1.advance(by: 0.5)
    #expect(early.entries == ["changed first(true)"], "\(early.entries)")

    let far = GCLog()
    let w2 = try chipWindow { LoggedSequence(log: far, dragMinimum: 0) }
    w2.send(down()); w2.tick(); w2.advance(by: 0.15)
    w2.send(dragged(at(320, 150))); w2.tick(); w2.advance(by: 0.35)
    w2.send(dragged(at(330, 150))); w2.tick()
    w2.send(up(at(330, 150))); w2.tick()
    #expect(far.entries == ["changed first(true)"], "\(far.entries)")
}

// MARK: - 3: updating on a sequence (S6, S6b, S6c)

private struct SequenceStateChip: Component {
    let log: GCLog
    @GestureState var s = 0
    var content: some ElementGroup {
        let _ = log.add("body s=\(s)")
        chip(pressThenDrag(log)
            .updating($s) { v, st, _ in st += 1; log.add("upd \(seq(v))") }
            .onEnded { log.add("ended \(seq($0))") })
    }
}

/// **3.1** (`S6`). `updating` on a sequence runs on every value the sequence reports — `.first`, `.second(_, nil)`,
/// each drag change — rising 1, 2, 3, 4 and resetting to 0 at the end. Mutation: skip the composite's `addFinish`.
@Test @MainActor func updatingOnASequenceRunsForEachValueAndResetsAtTheEnd() throws {
    let log = GCLog()
    let window = try chipWindow { SequenceStateChip(log: log) }
    window.send(down()); window.tick(); window.advance(by: 0.5)
    window.send(dragged(at(210, 150))); window.tick()
    window.send(dragged(at(230, 150))); window.tick()
    window.send(up(at(230, 150))); window.tick()
    #expect(log.entries.filter { $0.hasPrefix("upd") } == [
        "upd first(true)", "upd second(true, nil)",
        "upd second(true, start=(110.0,100.0) loc=(110.0,100.0))",
        "upd second(true, start=(110.0,100.0) loc=(130.0,100.0))",
    ], "\(log.entries)")
    #expect(log.distinct.filter { $0.hasPrefix("body") } == ["body s=0", "body s=1", "body s=2", "body s=3", "body s=4",
                                                            "body s=0"], "\(log.distinct)")
}

/// **3.2** (`S6b`, `S6c`). A sequence that fails (released before the long press) resets at the failure; one released
/// right after the long press resets at its end. Mutation: skip the settle of a failed composite.
@Test @MainActor func aSequenceThatFailsOrEndsWithoutMovingStillResetsItsState() throws {
    let failing = GCLog()
    let w1 = try chipWindow { SequenceStateChip(log: failing) }
    w1.send(down()); w1.tick(); w1.advance(by: 0.1)
    w1.send(up()); w1.tick()
    #expect(failing.distinct.filter { $0.hasPrefix("body") } == ["body s=0", "body s=1", "body s=0"], "\(failing.distinct)")

    let quiet = GCLog()
    let w2 = try chipWindow { SequenceStateChip(log: quiet) }
    w2.send(down()); w2.tick(); w2.advance(by: 0.5)
    w2.send(up()); w2.tick()
    #expect(quiet.distinct.filter { $0.hasPrefix("body") } == ["body s=0", "body s=1", "body s=2", "body s=0"],
            "\(quiet.distinct)")
    #expect(quiet.entries.contains("ended second(true, start=(100.0,100.0) loc=(100.0,100.0))"), "\(quiet.entries)")
}

// MARK: - 4: a tap first (S7, S7b)

/// **4.1** (`S7`, `S7b`). `tap.sequenced(before: drag)` with no minimum: the tap ends at the release and the drag, its
/// first event that same release, ends with it. A tap that never completes ends nothing. Mutation: do not replay the
/// event that opened the gate.
@Test @MainActor func aTapThenADragEndsOnTheReleaseThatEndedTheTap() throws {
    let log = GCLog()
    let window = try chipWindow {
        chip(TapGesture().sequenced(before: DragGesture(minimumDistance: 0)).onEnded { v in
            switch v {
            case .first: log.add("ended first")
            case .second(_, let value): log.add("ended second \(value.map(drag) ?? "nil")")
            }
        })
    }
    window.send(down()); window.tick()
    window.send(up()); window.tick()
    #expect(log.entries == ["ended second start=(100.0,100.0) loc=(100.0,100.0)"], "\(log.entries)")

    let moved = GCLog()
    let w2 = try chipWindow {
        chip(TapGesture().sequenced(before: DragGesture(minimumDistance: 0)).onEnded { _ in moved.add("ended") })
    }
    w2.send(down()); w2.tick(); w2.send(dragged(at(230, 150))); w2.tick(); w2.send(up(at(230, 150))); w2.tick()
    #expect(moved.entries.isEmpty, "a tap that moved 30 pt failed: \(moved.entries)")
}

// MARK: - 5: simultaneous and exclusive values (X1, X2, X2b)

private struct SimultaneousChip: Component {
    let log: GCLog
    @GestureState var s = 0
    var content: some ElementGroup {
        let _ = log.add("body s=\(s)")
        chip(DragGesture(minimumDistance: 0)
            .simultaneously(with: LongPressGesture(minimumDuration: 0.3, maximumDistance: Pixels(100)))
            .updating($s) { v, st, _ in
                st += 1
                log.add("upd first=\(v.first.map(drag) ?? "nil") second=\(v.second.map { "\($0)" } ?? "nil")")
            }
            .onEnded { v in log.add("ended first=\(v.first != nil) second=\(v.second.map { "\($0)" } ?? "nil")") })
    }
}

/// **5.1** (`X1`). `updating` on a simultaneous composite sees both members' latest values — **once per event**, the
/// press's one update carrying the drag's change and the long press's `true` together — keeps the long press's `true`
/// after it ended, and `onEnded` runs once at the release. Mutation: emit per member instead of per event.
@Test @MainActor func aSimultaneousCompositeReportsBothLatestValuesOncePerEvent() throws {
    let log = GCLog()
    let window = try chipWindow { SimultaneousChip(log: log) }
    window.send(down()); window.tick()
    window.send(dragged(at(210, 150))); window.tick(); window.advance(by: 0.5)
    window.send(dragged(at(220, 150))); window.tick()
    window.send(up(at(220, 150))); window.tick()
    #expect(log.entries.filter { $0.hasPrefix("upd") || $0.hasPrefix("ended") } == [
        "upd first=start=(100.0,100.0) loc=(100.0,100.0) second=true",
        "upd first=start=(100.0,100.0) loc=(110.0,100.0) second=true",
        "upd first=start=(100.0,100.0) loc=(120.0,100.0) second=true",
        "ended first=true second=true",
    ], "\(log.entries)")
    #expect(log.distinct.filter { $0.hasPrefix("body") } == ["body s=0", "body s=1", "body s=2", "body s=3", "body s=0"],
            "\(log.distinct)")
}

private struct ExclusiveChip: Component {
    let log: GCLog
    @GestureState var s = 0
    var content: some ElementGroup {
        let _ = log.add("body s=\(s)")
        chip(LongPressGesture(minimumDuration: 0.3, maximumDistance: Pixels(100))
            .exclusively(before: DragGesture(minimumDistance: 0))
            .updating($s) { v, st, _ in
                st += 1
                switch v {
                case .first(let held): log.add("upd first(\(held))")
                case .second(let value): log.add("upd second \(drag(value))")
                }
            }
            .onEnded { v in
                switch v {
                case .first(let held): log.add("ended first(\(held))")
                case .second(let value): log.add("ended second \(drag(value))")
                }
            })
    }
}

/// **5.2** (`X2`, `X2b`). An exclusive composite whose first member wins reports `.first`, and `onEnded` is the
/// winner's, the state reset before it. Mutation: report the second member while the first is undecided.
@Test @MainActor func anExclusiveCompositeReportsTheWinningMembersValue() throws {
    let log = GCLog()
    let window = try chipWindow { ExclusiveChip(log: log) }
    window.send(down()); window.tick(); window.advance(by: 0.5)
    window.send(dragged(at(210, 150))); window.tick()
    window.send(up(at(210, 150))); window.tick()
    #expect(log.entries.filter { $0.hasPrefix("upd") || $0.hasPrefix("ended") } == ["upd first(true)", "ended first(true)"],
            "\(log.entries)")
    #expect(log.distinct.filter { $0.hasPrefix("body") } == ["body s=0", "body s=1", "body s=0"], "\(log.distinct)")

    let quick = GCLog()
    let w2 = try chipWindow { ExclusiveChip(log: quick) }
    w2.send(down()); w2.tick()
    w2.send(dragged(at(210, 150))); w2.tick()
    w2.send(up(at(210, 150))); w2.tick()
    #expect(!quick.entries.contains { $0.hasPrefix("ended") || $0.hasPrefix("upd second") },
            "the long press is still undecided at the release, so the drag behind it never reports: \(quick.entries)")
}

// MARK: - 6: a custom Gesture with a body (C1…C5)

private struct HoldGesture: Gesture {
    var log: GCLog
    var seconds = 0.3
    var body: _EndedGesture<LongPressGesture> {
        LongPressGesture(minimumDuration: seconds).onEnded { _ in log.add("inner ended") }
    }
}

private struct PressThenDragGesture: Gesture {
    var body: SequenceGesture<LongPressGesture, DragGesture> {
        LongPressGesture(minimumDuration: 0.3, maximumDistance: Pixels(20)).sequenced(before: DragGesture(minimumDistance: 0))
    }
}

/// **6.1** (`C1`, `C2`). A struct whose `body` is a gesture is a gesture: its body's callbacks run, and `onEnded` on it
/// receives the body's value (`Bool` for a long press). Mutation: have `_recognizers()` ignore `body`.
@Test @MainActor func aCustomGestureRunsItsBodyAndTakesOnEnded() throws {
    let log = GCLog()
    let window = try chipWindow { chip(HoldGesture(log: log).onEnded { held in log.add("outer ended \(held)") }) }
    window.send(down()); window.tick(); window.advance(by: 0.5)
    window.send(up()); window.tick()
    #expect(log.entries == ["inner ended", "outer ended true"], "\(log.entries)")
}

private struct CustomStateChip: Component {
    let log: GCLog
    @GestureState var s = 0
    var content: some ElementGroup {
        let _ = log.add("body s=\(s)")
        chip(HoldGesture(log: log).updating($s) { held, st, _ in st = held ? 1 : 0; log.add("upd \(held)") })
    }
}

/// **6.2** (`C3`). `updating` on a custom gesture runs at the press with `true` and resets when the body's long press
/// ends. Mutation: do not queue the leaf's finish hook for a wrapped leaf.
@Test @MainActor func updatingOnACustomGestureWrapsItsBodyAndResets() throws {
    let log = GCLog()
    let window = try chipWindow { CustomStateChip(log: log) }
    window.send(down()); window.tick(); window.advance(by: 0.5)
    #expect(log.distinct.filter { $0.hasPrefix("body") } == ["body s=0", "body s=1", "body s=0"], "\(log.distinct)")
    #expect(log.entries.filter { $0.hasPrefix("upd") } == ["upd true"], "\(log.entries)")
    window.send(up()); window.tick()
}

/// **6.3** (`C4`). A custom gesture whose body is a sequence reports the sequence's values to its own `onChanged` and
/// `onEnded`. Mutation: do not tap a composite node.
@Test @MainActor func aCustomGestureWhoseBodyIsASequenceReportsTheSequenceValue() throws {
    let log = GCLog()
    let window = try chipWindow {
        chip(PressThenDragGesture()
            .onChanged { log.add("changed \(seq($0))") }
            .onEnded { log.add("ended \(seq($0))") })
    }
    window.send(down()); window.tick(); window.advance(by: 0.5)
    window.send(dragged(at(210, 150))); window.tick()
    window.send(up(at(210, 150))); window.tick()
    #expect(log.entries == [
        "changed first(true)", "changed second(true, nil)",
        "changed second(true, start=(110.0,100.0) loc=(110.0,100.0))",
        "ended second(true, start=(110.0,100.0) loc=(110.0,100.0))",
    ], "\(log.entries)")
}

/// **6.4** (`C5`). A custom gesture composes with `simultaneously(with:)` like any other.
/// Mutation: make `Gesture.body`'s default `_recognizers()` return an empty node.
@Test @MainActor func aCustomGestureComposesWithTheCombinators() throws {
    let log = GCLog()
    let window = try chipWindow {
        chip(HoldGesture(log: log).simultaneously(with: DragGesture(minimumDistance: 0).onChanged { _ in log.add("drag") }))
    }
    window.send(down()); window.tick(); window.advance(by: 0.5)
    window.send(up()); window.tick()
    #expect(log.entries == ["drag", "inner ended"], "\(log.entries)")
}

// MARK: - 7: DragGesture.Value time, velocity, predictedEnd (D1…D15)

private struct DragRecord {
    var time: Double
    var location: Float
    var velocity: Float
    var velocityY: Float
    var predictedTranslation: Float
    var predictedLocation: Float
    var ended: Bool
}

private typealias Sample = (x: Float, y: Float, t: Double)

/// Samples at `x` positions (y fixed), `dt` apart from `t0`.
private func line(_ xs: [Float], y: Float = 100, dt: Double = 0.02, t0: Double = 1000) -> [Sample] {
    var out: [Sample] = []
    for (index, x) in xs.enumerated() { out.append((x: x, y: y, t: t0 + Double(index) * dt)) }
    return out
}

@MainActor private func recordDrag(minimum: Float = 0, _ points: [Sample]) throws -> [DragRecord] {
    var out: [DragRecord] = []
    let window = try chipWindow {
        chip(DragGesture(minimumDistance: Pixels(minimum)).onChanged { v in
            out.append(DragRecord(time: v.time.timeIntervalSinceReferenceDate, location: v.location.x.value,
                                  velocity: v.velocity.width.value, velocityY: v.velocity.height.value,
                                  predictedTranslation: v.predictedEndTranslation.width.value,
                                  predictedLocation: v.predictedEndLocation.x.value, ended: false))
        }.onEnded { v in
            out.append(DragRecord(time: v.time.timeIntervalSinceReferenceDate, location: v.location.x.value,
                                  velocity: v.velocity.width.value, velocityY: v.velocity.height.value,
                                  predictedTranslation: v.predictedEndTranslation.width.value,
                                  predictedLocation: v.predictedEndLocation.x.value, ended: true))
        })
    }
    for (index, p) in points.enumerated() {
        let position = at(p.x + 100, p.y + 50)
        if index == 0 { window.send(down(position, t: p.t)) }
        else if index == points.count - 1 { window.send(up(position, t: p.t)) }
        else { window.send(dragged(position, t: p.t)) }
    }
    return out
}

/// **7.1** (`D1`, `D4`, `D5`). A steady drag reports its speed from the second event on: 10 pt every 0.02 s is
/// 500 pt/s, and `predictedEndTranslation`/`predictedEndLocation` lie a quarter of a second of that velocity ahead
/// (125 pt). The first event reports no velocity. Mutation: change the 1/4 to 1/5.
@Test @MainActor func aSteadyDragReportsItsVelocityAndAQuarterSecondPrediction() throws {
    let records = try recordDrag(line([20, 30, 40, 50, 60, 70, 80, 90, 100]))
    try #require(records.count == 9)
    #expect(records[0].velocity == 0 && records[0].predictedTranslation == 0)
    for record in records.dropFirst() {
        #expect(record.velocity == 500, "\(record)")
        #expect(abs(record.predictedLocation - (record.location + 125)) < 0.001, "\(record)")
    }
    #expect(records[1].predictedTranslation == 135, "10 pt moved + 125: \(records[1])")
    #expect(records.last?.ended == true)
    let slow = try recordDrag(line([20, 22, 24, 26]))
    #expect(slow.dropFirst().map(\.velocity) == [100, 100, 100], "\(slow)")
    let fast = try recordDrag(line([20, 60, 100, 140]))
    #expect(fast.dropFirst().map(\.velocity) == [2000, 2000, 2000] && fast[1].predictedTranslation == 540, "\(fast)")
}

/// **7.2** (`D6`, `D7`, `D11`). The velocity is `0.75 × the previous interval's speed + 0.25 × this interval's`: an
/// accelerating drag lags its instantaneous speed, a stop reads 375 (not 0) at its first still event and 0 at the next,
/// a burst after a slow start reads 287.5 then 1000. Mutation: use the interval's speed alone; swap the weights.
@Test @MainActor func theVelocityIsAThreeToOneBlendOfTheLastTwoIntervals() throws {
    let accelerating = try recordDrag(line([20, 22, 28, 38, 52, 70]))
    #expect(accelerating.map(\.velocity) == [0, 100, 150, 350, 550, 750], "\(accelerating.map(\.velocity))")

    let still = try recordDrag(line([20, 30, 40, 50, 60, 60, 60, 60, 60, 60]))
    #expect(still.map(\.velocity) == [0, 500, 500, 500, 500, 375, 0, 0, 0, 0], "\(still.map(\.velocity))")

    let burst = try recordDrag(line([20, 21, 22, 23, 24, 25, 26, 27, 47, 67, 87]))
    #expect(burst.suffix(3).map(\.velocity) == [287.5, 1000, 1000], "\(burst.map(\.velocity))")
}

/// **7.3** (`D8`, `D12`). A release long after the last move is a zero-displacement interval: 375, not decayed
/// (D8, 0.3 s later); a drag of one move then the release reads 600, then 450. Mutation: decay the velocity by the
/// release's age.
@Test @MainActor func aLateReleaseBlendsAZeroIntervalAndDoesNotDecay() throws {
    let late = try recordDrag(line([20, 30, 40, 50, 60]) + [(x: 60, y: 100, t: 1000.38)])
    #expect(late.last?.velocity == 375 && late.last?.ended == true, "\(late)")
    let single = try recordDrag([(x: 20, y: 100, t: 1000), (x: 50, y: 100, t: 1000.05), (x: 50, y: 100, t: 1000.06)])
    #expect(single.map(\.velocity) == [0, 600, 450], "\(single)")
}

/// **7.4** (`D13`). The estimator sees the moves made before the drag reaches its `minimumDistance`: the first reported
/// change (a 20 pt step after 3 pt ones) reads 362.5 = 0.75 × 150 + 0.25 × 1000. Mutation: start sampling at the
/// first reported change.
@Test @MainActor func movesBeforeTheMinimumDistanceFeedTheEstimator() throws {
    let records = try recordDrag(minimum: 10, line([20, 23, 26, 29, 49, 69, 89]))
    #expect(records.first?.velocity == 362.5, "\(records)")
}

/// **7.5** (`D14`, `D15`). An event with the timestamp of the one before replaces its sample instead of dividing by
/// zero: 20 → 30 → 40 at the same instant reads 1000 (20 pt in one interval), then 875. A move stamped with the press
/// leaves the press's start location but samples nothing. Mutation: append instead of replace.
@Test @MainActor func anEventAtTheSameInstantReplacesTheLastSample() throws {
    let records = try recordDrag([(x: 20, y: 100, t: 1000), (x: 30, y: 100, t: 1000.02), (x: 40, y: 100, t: 1000.02),
                                  (x: 50, y: 100, t: 1000.04), (x: 50, y: 100, t: 1000.05)])
    #expect(records.map(\.velocity) == [0, 500, 1000, 875, 375], "\(records)")
    let press = try recordDrag([(x: 20, y: 100, t: 1000), (x: 30, y: 100, t: 1000), (x: 40, y: 100, t: 1000.02),
                                (x: 40, y: 100, t: 1000.03)])
    #expect(press.map(\.velocity) == [0, 0, 500, 375], "\(press)")
    #expect(press[1].predictedTranslation == 10, "a still estimator predicts no travel: \(press[1])")
}

/// **7.6** (`D9`, `D10`). The velocity has a sign per axis, y down, in the gesture's space: 10 right and 20 down per
/// 0.02 s reads (500, 1000); leftward reads −500. Mutation: negate the vertical axis.
@Test @MainActor func theVelocityIsPerAxisAndSigned() throws {
    let diagonal = try recordDrag(line([20, 30, 40, 50]).enumerated().map { (x: $1.x, y: Float(20 + $0 * 20), t: $1.t) })
    #expect(diagonal.dropFirst().map(\.velocity) == [500, 500, 500] && diagonal.dropFirst().map(\.velocityY) == [1000, 1000, 1000],
            "\(diagonal)")
    let left = try recordDrag(line([120, 110, 100, 90]))
    #expect(left.dropFirst().map(\.velocity) == [-500, -500, -500] && left[1].predictedTranslation == -135, "\(left)")
}

/// **7.7** (`D0`, `D2`, `D3`). `time` is the event's own timestamp, as a `Date` since the reference date, never the wall
/// clock: events 0.02 s apart in their stamps read 0.02 s apart however fast the test sent them, and the velocity
/// follows the stamps. Mutation: read the window's clock instead of the event's.
@Test @MainActor func timeFollowsTheEventTimestampsNotTheWallClock() throws {
    let records = try recordDrag(line([20, 30, 40, 50], t0: 5000))
    let expected: [Double] = [0, 1, 2, 3].map { 5000 + Double($0) * 0.02 }
    #expect(records.map(\.time) == expected, "\(records.map(\.time))")
}

/// **7.8** (`GE-D`). A pointer event with no timestamp is stamped with the window's last display-link time: a value
/// built that way reports no velocity from a still pointer and never traps, and `Value`'s own initialisers report
/// zero velocity and the reference date. Mutation: trap on a nil timestamp.
@Test @MainActor func anUnstampedPointerEventStillProducesAValue() throws {
    var values: [DragGesture.Value] = []
    let window = try chipWindow { chip(DragGesture(minimumDistance: 0).onChanged { values.append($0) }) }
    window.send(down()); window.tick()
    window.send(dragged(at(210, 150))); window.tick()
    try #require(values.count == 2)
    #expect(values[0].velocity == Size(width: Pixels(0), height: Pixels(0)))
    let built = DragGesture.Value(startLocation: at(1, 1), location: at(3, 1))
    #expect(built.velocity == Size(width: Pixels(0), height: Pixels(0)) && built.predictedEndLocation == at(3, 1)
            && built.predictedEndTranslation == Size(width: Pixels(2), height: Pixels(0)))
}
