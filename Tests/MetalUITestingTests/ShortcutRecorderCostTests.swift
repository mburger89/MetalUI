import Foundation
import MetalUI
import MetalUITesting
import Testing

// What `ShortcutRecorder` costs (ruling `KF-AK`, record 366). PLAIN imports, the harness text system, counters and
// never a clock. The recorder is a component of one proposal chain with a keyboard layer (`focusable`, `focused`,
// `keyCapture`, `onKeyPress`), two lifecycle scopes (`onChange`) and the accessibility layers; those are the literals
// below. Off Darwin the number of frames a keystroke or a press spans depends on the main-actor hop, so frame-
// sensitive literals are compared per frame there (`perFrameEquals`).

private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, evaluations = 0, skips = 0, refusals = 0, frames = 0
    init(requests: Int, evaluations: Int, skips: Int, refusals: Int, frames: Int) {
        self.requests = requests; self.evaluations = evaluations; self.skips = skips
        self.refusals = refusals; self.frames = frames
    }
    init(_ work: [FrameWork]) {
        requests = work.reduce(0) { $0 + $1.elementRequests }
        evaluations = work.reduce(0) { $0 + $1.contentEvaluations }
        skips = work.reduce(0) { $0 + $1.contentSkips }
        refusals = work.reduce(0) { $0 + $1.contentRefusals }
        frames = work.count
    }
    func perFrameEquals(_ o: Cost) -> Bool {
        frames > 0 && o.frames > 0
            && requests * o.frames == o.requests * frames && evaluations * o.frames == o.evaluations * frames
            && skips * o.frames == o.skips * frames && refusals * o.frames == o.refusals * frames
    }
    var description: String {
        "requests \(requests) evaluations \(evaluations) skips \(skips) refusals \(refusals) frames \(frames)"
    }
}

@MainActor private final class CostModel {
    var shortcut: KeyboardShortcut?
    var text = ""
    var probeEvaluations = 0
}

/// An unrelated `Equatable` sibling: it counts how many times its `content` ran.
private struct Probe: Component, @MainActor Equatable {
    let model: CostModel
    var content: some ElementGroup {
        model.probeEvaluations += 1
        return Text("probe")
    }
    static func == (l: Probe, r: Probe) -> Bool { l.model === r.model }
}

/// A parent whose `@State` counter changes without touching the recorder.
private struct CostHost: Component {
    let model: CostModel
    let equatable: Bool
    let withRecorder: Bool
    @State var counter = 0

    var content: some ElementGroup {
        let model = model, counter = $counter
        let recorder = ShortcutRecorder(model.shortcut, onRecord: { model.shortcut = $0 }, onClear: {}, onCancel: {})
        return VStack(spacing: Pixels(8)) {
            Text("count \(counter.wrappedValue)").onTapGesture { counter.wrappedValue += 1 }
            if withRecorder {
                if equatable { recorder.equatable() } else { recorder }
            }
            Probe(model: model).equatable()
            TextField("name", text: model.text) { model.text = $0 }
        }
    }
}

@MainActor private func open(equatable: Bool = false, withRecorder: Bool = true) async throws
    -> (TestWindow, CostModel) {
    let model = CostModel()
    let w = try harnessWindow(size: sz(300, 200)) {
        VStack { CostHost(model: model, equatable: equatable, withRecorder: withRecorder) }
    }
    w.window.focus(nil); w.tick()
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    return (w, model)
}

@MainActor private func idle(_ w: TestWindow) async throws -> Cost {
    w.resetFrameWork()
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    return Cost(w.frameWork)
}

@MainActor private func steady(equatable: Bool = false, withRecorder: Bool = true) async throws -> Cost {
    let (w, _) = try await open(equatable: equatable, withRecorder: withRecorder)
    defer { withExtendedLifetime(w) {} }
    return try await idle(w)
}

/// The cost of a keystroke typed into the `TextField`, after a settling frame.
@MainActor private func keystroke(equatable: Bool = false, withRecorder: Bool = true) async throws -> Cost {
    let (w, _) = try await open(equatable: equatable, withRecorder: withRecorder)
    defer { withExtendedLifetime(w) {} }
    try w.click(try w.elements(role: .textField)[0])
    for _ in 0..<2 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    w.typeText("a")
    try await w.runUntilIdle()
    return Cost(w.frameWork)
}

private let unit = Cost(requests: 0, evaluations: 0, skips: 0, refusals: 0, frames: 1)

/// **C1** An idle recorder costs nothing extra on a rebuilt frame **by default**, with no caller `.equatable()`: the
/// public type wraps its field in `.equatable()`, so the field is skipped (one skip more than the window's own, the
/// `Probe`'s) and the request count is the window's own (3); an explicit caller `.equatable()` costs the same.
/// Mutation: return `field` without `.equatable()` from `ShortcutRecorder.content` (the default frame is 7 requests, 1
/// skip); or make `==` always false (the frame then evaluates).
@Test @MainActor func anIdleRecorderCostsAFixedSteadyFrameAndEquatableReplaysIt() async throws {
    let plain = try await steady(), replayed = try await steady(equatable: true), without = try await steady(withRecorder: false)
    #if canImport(Darwin)
    #expect(plain == Cost(requests: 3, evaluations: 0, skips: 2, refusals: 0, frames: 1), "plain \(plain)")
    #expect(replayed == Cost(requests: 3, evaluations: 0, skips: 2, refusals: 0, frames: 1), "equatable \(replayed)")
    #expect(without == Cost(requests: 3, evaluations: 0, skips: 1, refusals: 0, frames: 1), "without \(without)")
    #else
    #expect(plain.perFrameEquals(Cost(requests: 3, evaluations: 0, skips: 2, refusals: 0, frames: 1)), "plain \(plain)")
    #expect(replayed.perFrameEquals(Cost(requests: 3, evaluations: 0, skips: 2, refusals: 0, frames: 1)), "equatable \(replayed)")
    #expect(without.perFrameEquals(Cost(requests: 3, evaluations: 0, skips: 1, refusals: 0, frames: 1)), "without \(without)")
    #endif
}

/// **C3** A keystroke into a `TextField` beside an idle recorder costs what a steady frame beside it costs, and
/// with `.equatable()` exactly what the same window costs without a recorder: the recorder adds no work to a
/// keystroke. Mutation: a recorder that re-renders on every key (an `@State` write in the capture path, or the key
/// handler registered outside the recorder's layer).
@Test @MainActor func aKeystrokeBesideAnIdleRecorderCostsTheSameAsWithoutIt() async throws {
    let plain = try await keystroke(), replayed = try await keystroke(equatable: true), without = try await keystroke(withRecorder: false)
    let plainSteady = try await steady()
    #if canImport(Darwin)
    #expect(plain.requests == without.requests && plain.evaluations == without.evaluations,
            "default \(plain) vs without \(without)")
    #expect(replayed.requests == without.requests && replayed.evaluations == without.evaluations,
            "with \(replayed) vs without \(without)")
    #expect(plain == plainSteady, "keystroke \(plain) vs steady \(plainSteady)")
    #expect(plain.requests == without.requests, "default \(plain) vs without \(without)")
    #else
    #expect(replayed.requests * without.frames == without.requests * replayed.frames
                && replayed.evaluations * without.frames == without.evaluations * replayed.frames,
            "with \(replayed) vs without \(without)")
    #expect(plain.perFrameEquals(plainSteady), "keystroke \(plain) vs steady \(plainSteady)")
    #endif
}

/// **C4** Starting a recording and ending one re-render only the recorder: an unrelated `Equatable` sibling is not
/// evaluated, and the recorder's own content is evaluated a fixed number of times (one at the start, one at the end).
/// Mutation: write the recorder's end flag through `@State` (an extra evaluation at each end); or read focus in the
/// parent (the sibling re-evaluates).
@Test @MainActor func startingAndEndingARecordingReRendersOnlyTheRecorder() async throws {
    let (w, model) = try await open()
    defer { withExtendedLifetime(w) {} }
    let probe = model.probeEvaluations
    w.resetFrameWork()
    try w.click(try w.element(label: "Shortcut"))
    try await w.runUntilIdle()
    let start = Cost(w.frameWork)
    #expect(start.evaluations == 1, "start: \(start)")
    #expect(model.probeEvaluations == probe, "the sibling ran on start")
    w.resetFrameWork()
    w.typeKey(KeyEquivalent("j"), modifierFlags: .command)
    try await w.runUntilIdle()
    let end = Cost(w.frameWork)
    #expect(end.evaluations == 1, "end: \(end)")   // one frame: the new shortcut's text and the focus change together
    #expect(model.probeEvaluations == probe, "the sibling ran on end")
}

/// **C5** An unrelated parent state change with `.equatable()` re-enters nothing of the recorder: the content is
/// skipped (no evaluation) and the frame costs what the same change costs in a window without a recorder.
/// Mutation: drop `==` (the default memberwise compare cannot see closures, so the recorder re-evaluates) or compare
/// the closures.
@Test @MainActor func anUnrelatedParentChangeWithEquatableReEntersNothing() async throws {
    func tap(withRecorder: Bool) async throws -> Cost {
        let (w, _) = try await open(equatable: true, withRecorder: withRecorder)
        defer { withExtendedLifetime(w) {} }
        w.resetFrameWork()
        try w.click(try w.element(label: "count 0"))
        try await w.runUntilIdle()
        return Cost(w.frameWork)
    }
    let with = try await tap(withRecorder: true), without = try await tap(withRecorder: false)
    #expect(with.evaluations == 0 && with.skips >= 1, "recorder re-entered: \(with)")
    #if canImport(Darwin)
    #expect(with.requests == without.requests, "with \(with) vs without \(without)")
    #else
    #expect(with.perFrameEquals(without), "with \(with) vs without \(without)")
    #endif
}
