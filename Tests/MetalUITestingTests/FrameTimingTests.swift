import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
import Observation
import Testing

// Frame instrumentation (ruling `FP-A`..`FP-H`): `Window.frameTiming`, `FrameTiming`, `FrameTimingSample`. Portable:
// the headless platform has the same stamps as a real one. No test sleeps or compares a wall-clock threshold; the
// instrument is read for ORDER, COUNT and IDENTITY.

/// A model a view reads and an `onFrame` callback writes.
@Observable @MainActor private final class TimingModel {
    var width: Float = 20
    var show = false
}

/// A focusable box counting its key presses in a `@State`: a key press that dirties the window.
private struct TimingKeyBox: Component {
    @State var presses = 0
    var content: some ElementGroup {
        Box().frame(width: Pixels(20 + Float(presses)), height: Pixels(20)).background(.accent)
            .focusable()
            .onKeyPress("a") { presses += 1; return .handled }
    }
}

@MainActor private func timedWindow(_ timing: FrameTiming?, hasKeyBox: Bool = true) throws -> TestWindow {
    let window = try harnessWindow { VStack(spacing: 0) { TimingKeyBox() } }
    window.window.frameTiming = timing
    window.typeKey(.tab)   // focus the box; the frame this draws is recorded too when timing is set
    return window
}

/// The phases in order AND each stamped: a stamp never taken stays at the frame's start, which a real phase
/// (microseconds of work) is strictly after.
private func ordered(_ s: FrameTimingSample) -> Bool {
    s.buildStart < s.layoutEnd && s.layoutEnd < s.prepaintEnd && s.prepaintEnd < s.paintEnd && s.paintEnd < s.commit
}

/// 1.1 — a key then a tick: one sample, input kind `.key`, the input no later than the frame start, every phase in
/// order, and frame indices counting up. Mutations: the layout and prepaint stamps swapped; `commitFrame` not
/// writing the ring; the input kind of a key mapped to `.text`.
@Test @MainActor func aKeyThenATickRecordsOneOrderedSample() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    let before = timing.samples.count
    window.typeKey("a")
    let samples = timing.samples
    #expect(samples.count == before + 1, "one frame, one sample")
    let sample = try #require(samples.last)
    #expect(sample.inputKind == .key)
    #expect(sample.inputCount >= 1)
    let received = try #require(sample.inputReceived)
    let stamp = try #require(sample.inputTimestamp)
    #expect(stamp <= received && received <= sample.buildStart, "input <= receive <= frame start")
    #expect(ordered(sample), "buildStart <= layoutEnd <= prepaintEnd <= paintEnd <= commit")
    #expect(sample.presented == nil, "the headless renderer reports no presentation")
    #expect(samples.map(\.frameIndex) == Array(samples.first!.frameIndex ..< samples.first!.frameIndex + UInt64(samples.count)))
    window.typeKey("a")
    #expect(timing.samples.last!.frameIndex == sample.frameIndex + 1, "indices count up")
    #expect(sample.inputToCommit != nil && sample.frameDuration == sample.commit - sample.buildStart)
}

/// 1.2 — a frame no input caused has no input; an event that left the window clean does not become a later
/// frame's input; the earliest of two dirtying events wins and both are counted. Mutations: `settleInput` ignoring
/// `dirtied`; the later event replacing the pending one.
@Test @MainActor func inputAttributionIsTheEarliestDirtyingEvent() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    window.window.setNeedsRedraw()
    window.tick()
    #expect(try #require(timing.last).inputKind == nil, "a state-less redraw has no input")

    // Modifiers unchanged: handled without dirtying anything.
    window.send(.modifiersChanged([]))
    window.window.setNeedsRedraw()
    window.tick()
    #expect(try #require(timing.last).inputKind == nil, "a clean event is not carried to the next frame")

    window.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "a", characters: "a", timestamp: 0)))
    window.send(.mouseMoved(MouseEvent(position: pt(10, 10))))
    window.tick()
    let sample = try #require(timing.last)
    #expect(sample.inputKind == .key, "the earliest event wins")
    #expect(sample.inputCount == 2)
}

/// 1.3 — every event family maps to its kind. Mutation: `.scrollWheel` mapped to `.pointer`.
@Test @MainActor func inputKindsFollowTheEventFamily() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    window.window.onInput = { _ in true }
    let events: [(InputEvent, FrameInputKind)] = [
        (.textInput("x"), .text),
        (.scrollWheel(ScrollEvent(position: pt(5, 5), delta: pt(0, 3))), .wheel),
        (.mouseDown(MouseEvent(position: pt(5, 5))), .pointer),
        (.keyUp(KeyEvent(charactersIgnoringModifiers: "q", characters: "q", timestamp: 0)), .key),
    ]
    for (event, kind) in events {
        window.send(event)
        window.tick()
        #expect(try #require(timing.last).inputKind == kind, "\(event)")
    }
}

/// 1.4 — an event timestamp on the stamp clock (AppKit's `NSEvent.timestamp`) is the attribution time; one off it
/// (a test's, SDL's) falls back to the receive time. Mutation: the plausibility window removed.
@Test @MainActor func aPlatformTimestampOnOurClockIsUsedAndOtherwiseTheReceiveTime() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    let earlier = Double(FrameTiming.now()) / 1e9 - 0.004
    window.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "q", characters: "q", timestamp: earlier)))
    window.tick()
    var sample = try #require(timing.last)
    let received = try #require(sample.inputReceived), stamp = try #require(sample.inputTimestamp)
    #expect(stamp < received && received - stamp >= 3_000_000, "stamped at the event's own, earlier time")
    window.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "q", characters: "q", timestamp: 12.5)))
    window.tick()
    sample = try #require(timing.last)
    #expect(sample.inputTimestamp == sample.inputReceived, "an off-clock timestamp falls back to the receive time")
}

/// 1.5 — the ring keeps the newest `capacity` samples, oldest first, and keeps counting. Mutations: the slot index
/// not wrapped (`% capacity` dropped); `samples` returning slot order.
@Test @MainActor func theRingWrapsAndKeepsTheNewest() throws {
    let timing = FrameTiming(capacity: 4)
    let window = try timedWindow(timing)
    for _ in 0..<10 { window.window.setNeedsRedraw(); window.tick() }
    #expect(timing.framesRecorded == 11, "10 ticks plus the Tab frame")
    let samples = timing.samples
    #expect(samples.map(\.frameIndex) == [7, 8, 9, 10], "the last four, oldest first")
    #expect(timing.last?.frameIndex == 10)
    timing.removeAll()
    #expect(timing.samples.isEmpty && timing.last == nil && timing.framesRecorded == 11)
    window.window.setNeedsRedraw(); window.tick()
    #expect(timing.samples.map(\.frameIndex) == [11], "indices keep counting")
}

/// A box whose width is a `@State` the test writes through the binding it captures at build: a write that reaches
/// the window synchronously, as input's does (an `@Observable` write reaches a Linux window one main-actor hop
/// later).
@MainActor private final class WidthHolder { var binding: Binding<Float>?; var show: Binding<Bool>? }
private struct WidthBox: Component {
    let holder: WidthHolder
    let builds: BuildLog?
    var onAppearWrite: Bool = false
    @State var width: Float = 20
    @State var show = false
    var content: some ElementGroup {
        let _ = holder.binding = $width
        let _ = holder.show = $show
        let _ = builds?.times.append(FrameTiming.now())
        Box().frame(width: Pixels(width), height: Pixels(10)).background(.accent)
        if show {
            Box().frame(width: Pixels(5), height: Pixels(5)).onAppear { if onAppearWrite { width = 40 } }
        }
    }
}

/// 1.6 — `onFrame` runs after the frame (the frame is already counted and committed), outside any phase, and a
/// write it makes schedules the next frame, which shows it. Mutations: `deliverFrame` moved before the commit;
/// the callback run inside the build.
@Test @MainActor func onFrameRunsAfterTheFrameAndItsWriteIsNotStale() throws {
    let holder = WidthHolder()
    let timing = FrameTiming()
    let window = try harnessWindow { VStack(spacing: 0) { WidthBox(holder: holder, builds: nil) } }
    window.window.frameTiming = timing
    var seen: [(frames: Int, committed: UInt64, dirty: Bool)] = []
    timing.onFrame = { sample in
        seen.append((window.framesDrawn, sample.commit, window.window.needsRedraw))
        if let width = holder.binding, width.wrappedValue == 20 { width.wrappedValue = 30 }   // a write after the frame
    }
    window.window.setNeedsRedraw()
    window.tick()
    let first = try #require(seen.first)
    #expect(first.frames == window.framesDrawn, "framesDrawn was already advanced: the frame is over")
    #expect(first.committed == timing.samples.last!.commit && first.committed > 0)
    #expect(first.dirty == false, "nothing had dirtied the window before the write")
    #expect(window.window.needsRedraw, "the callback's write scheduled the next frame")
    window.tick()
    #expect(rects(window, height: 10).map { $0.bounds.size.width } == [30], "and that frame shows it")
    #expect(seen.count == 2)
}

@MainActor private final class BuildLog { var times: [UInt64] = [] }

/// 1.7 — a frame that builds twice (an `onAppear` write) keeps the LAST build's stamps, in order: its layout ended
/// after the second build's content was evaluated. Mutation: the layout stamp taken once (first build only).
@Test @MainActor func aFrameThatBuildsTwiceKeepsTheLastBuildsStamps() throws {
    let holder = WidthHolder()
    let builds = BuildLog()
    let timing = FrameTiming()
    let window = try harnessWindow {
        VStack(spacing: 0) { WidthBox(holder: holder, builds: builds, onAppearWrite: true) }
    }
    window.window.frameTiming = timing
    builds.times = []
    // The box with the `onAppear` appears in this frame; its write forces a second build inside it.
    holder.show?.wrappedValue = true
    window.tick()
    #expect(builds.times.count >= 2, "the onAppear write must have forced a second build")
    let sample = try #require(timing.last)
    #expect(ordered(sample))
    #expect(sample.layoutEnd >= builds.times.last!, "layoutEnd belongs to the second build")
    #expect(sample.buildStart <= builds.times.first!, "buildStart precedes the first")
}

/// 1.8 — the presented time lands in the ring slot of the right frame, later, from outside any frame; where the
/// renderer reports none it stays `nil`. Attaching a timing after frames were drawn maps tokens by base.
/// Mutations: the token not offset by the base; the sample updated before the commit; `onPresented` not called.
@Test @MainActor func presentationReachesTheRightFrameLater() throws {
    let window = try harnessWindow { VStack(spacing: 0) { TimingKeyBox() } }
    window.window.setNeedsRedraw(); window.tick()   // frames drawn before the timing exists
    let renderer = window.platformWindow.headlessRenderer
    renderer.reportsPresentation = true
    let timing = FrameTiming()
    var announced: [UInt64] = []
    timing.onPresented = { announced.append($0.frameIndex) }
    window.window.frameTiming = timing
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(timing.samples.map(\.presented) == [nil, nil, nil], "not reported yet")
    renderer.deliverPresentations(at: 5_000)
    #expect(timing.samples.map(\.presented) == [5_000, 5_000, 5_000])
    #expect(announced == [0, 1, 2])
    window.window.setNeedsRedraw(); window.tick()
    renderer.deliverPresentations(at: 9_000)
    #expect(timing.samples.map(\.presented) == [5_000, 5_000, 5_000, 9_000], "frame 3 only")
    // Detached, then attached again: the renderer counts from 0 again and the base maps it to frame 4.
    window.window.frameTiming = nil
    window.window.setNeedsRedraw(); window.tick()
    window.window.frameTiming = timing
    window.window.setNeedsRedraw(); window.tick()
    renderer.deliverPresentations(at: 11_000)
    #expect(timing.samples.map(\.presented) == [5_000, 5_000, 5_000, 9_000, 11_000], "frame 4 only")
    // A renderer that reports nothing leaves `presented` nil.
    let quiet = FrameTiming()
    renderer.reportsPresentation = false
    window.window.frameTiming = quiet
    window.window.setNeedsRedraw(); window.tick()
    renderer.deliverPresentations(at: 1)
    #expect(quiet.samples.map(\.presented) == [nil])
}

/// 1.9 — signposts are an opt-in of the timing: requested, they are on where `os` exists; frames record the same
/// either way. Mutation: `emitsSignposts` always false.
@Test @MainActor func signpostsAreOnlyEmittedWhenAskedFor() throws {
    #expect(FrameTiming().emitsSignposts == false)
    let loud = FrameTiming(emitsSignposts: true)
    #if canImport(os)
    #expect(loud.emitsSignposts)
    #else
    #expect(!loud.emitsSignposts)
    #endif
    let window = try timedWindow(loud)
    window.typeKey("a")
    #expect(ordered(try #require(loud.last)) && loud.last?.inputKind == .key)
}

#if canImport(Darwin)
/// 1.10 — the instrument costs no allocation: a frame and an input with no timing allocate exactly what the same
/// frame and input allocate with a timing recording (the ring is allocated up front), and a window with no timing
/// has recorded nothing. Mutations: the ring write appending to an array; the disabled path allocating.
@Test @MainActor func recordingAndNotRecordingAllocateTheSame() throws {
    let off = try timedWindow(nil)
    let on = try timedWindow(FrameTiming())
    func work(_ window: TestWindow) {
        window.window.setNeedsRedraw()
        window.send(.modifiersChanged([]))
        window.tick()
    }
    // Warm both windows' caches, then measure the same steady frames.
    for _ in 0..<4 { work(off); work(on) }
    var offCounts: [Int] = [], onCounts: [Int] = []
    for _ in 0..<5 {
        offCounts.append(try #require(countAllocations { work(off) }))
        onCounts.append(try #require(countAllocations { work(on) }))
    }
    #expect(offCounts.min() == onCounts.min(), "off \(offCounts) vs on \(onCounts)")
    #expect(off.window.frameTiming == nil)
}
#endif

/// 1.11 — the latency stages: a key then a tick stamps the tick after the input and no later than the frame
/// start, the drawable between frame start and layout end, and a frame no tick drove has no tick. Mutations:
/// `noteTick` not called by the window's tick closure; `stampDrawableAcquired` not called; the tick taken after
/// `beginFrame`.
@Test @MainActor func aKeyThenATickStampsTheTickAndTheDrawableInOrder() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    window.typeKey("a")
    let s = try #require(timing.last)
    let received = try #require(s.inputReceived), tick = try #require(s.tickStart)
    #expect(received <= tick && tick <= s.buildStart, "input <= tick <= frame start")
    #expect(s.buildStart <= s.drawableAcquired && s.drawableAcquired <= s.layoutEnd, "drawable between start and layout")
    #expect(s.inputToTick != nil && s.drawableWait == s.drawableAcquired - s.buildStart)
    // Not driven by a tick: drawn directly, no tick stamp.
    window.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "a", characters: "a", timestamp: 0)))
    window.window.drawFrameIfNeeded()
    #expect(timing.last?.tickStart == nil && timing.last?.inputToTick == nil)
}

/// 1.12 — the trace writes a header then one line per input-caused, presented frame, stages in order, and the
/// refresh interval is the shortest gap between tick targets on our clock. Mutations: a line for a frame without
/// input; the header written per line; the interval taken as the longest gap.
@Test @MainActor func theLatencyTraceWritesAHeaderThenOneLinePerPresentedInputFrame() throws {
    let window = try harnessWindow { VStack(spacing: 0) { TimingKeyBox() } }
    window.platformWindow.headlessRenderer.reportsPresentation = true
    let timing = FrameTiming()
    var lines: [String] = []
    timing.traceSink = { lines.append($0) }
    window.window.frameTiming = timing
    window.typeKey(.tab)
    let base = Double(FrameTiming.now()) / 1e9
    window.platformWindow.simulateTick(timestamp: base)
    window.platformWindow.simulateTick(timestamp: base + 1.0 / 30)
    window.platformWindow.simulateTick(timestamp: base + 1.0 / 30 + 1.0 / 60)
    #expect(timing.refreshInterval.map { abs(Double($0) - 1e9 / 60) < 1e5 } == true, "shortest gap")
    window.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "a", characters: "a", timestamp: 0)))
    window.tick()
    window.window.setNeedsRedraw(); window.tick()   // a frame no input caused
    window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 10_000_000)
    #expect(lines.first == FrameTiming.traceHeader)
    let body = Array(lines.dropFirst())
    #expect(body.count == timing.samples.filter { $0.inputKind != nil }.count && !body.isEmpty)
    #expect(body.allSatisfy { $0.hasPrefix("metalui-latency ") })
    #expect(body.last?.contains(" key ") == true)
    let sample = try #require(timing.samples.last { $0.inputKind == .key })
    let line = FrameTiming.traceLine(for: sample, interval: 16_666_667)
    let total = try #require(sample.inputToPresented)
    #expect(line.hasSuffix(String(format: " | %.2f %.2f", Double(total) / 1e6, Double(total) / 16_666_667)))
    #expect(FrameTiming.traceLine(for: sample, interval: nil).hasSuffix(" -"))
}

// MARK: Latency trace in an app (`FP-J`)

/// Runs `body` with `METALUI_LATENCY_TRACE` set to a fresh file path, then restores the environment.
@MainActor private func withTraceEnvironment(_ body: (String) throws -> Void) rethrows {
    let path = NSTemporaryDirectory() + "metalui-trace-\(UUID().uuidString).txt"
    let old = getenv("METALUI_LATENCY_TRACE").map { String(cString: $0) }
    setTestEnvironment("METALUI_LATENCY_TRACE", path)
    defer {
        if let old { setTestEnvironment("METALUI_LATENCY_TRACE", old) } else { unsetTestEnvironment("METALUI_LATENCY_TRACE") }
        try? FileManager.default.removeItem(atPath: path)
    }
    try body(path)
}

private func readTrace(_ path: String) -> [String] {
    ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
}

/// 1.13 — a committed-text input frame (`insertText`, the `.textInput` event) reaches the trace file once its
/// presentation arrives through the renderer's observer, the path a real window uses; the file is read back with
/// no close. Mutations: `.textInput` mapped to no kind; the sink not called from `notePresented`.
@Test @MainActor func aTextInputFrameWritesATraceLineToTheFile() throws {
    try withTraceEnvironment { path in
        let window = try harnessWindow { VStack(spacing: 0) { TimingKeyBox() } }
        window.platformWindow.headlessRenderer.reportsPresentation = true
        window.window.frameTiming = FrameTiming()
        window.window.onInput = { _ in true }
        window.send(.textInput("x"))
        window.tick()
        window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
        let lines = readTrace(path)
        #expect(lines.first == FrameTiming.traceHeader)
        #expect(lines.contains { $0.hasPrefix("metalui-latency ") && $0.contains(" text ") }, "\(lines)")
    }
}

/// 1.14 — the environment applies to any `FrameTiming(capacity:)`, so an app that replaces `Window.frameTiming`
/// with its own recorder still traces; explicit `enableTrace` works without the environment. Mutation: the
/// environment read only in `fromEnvironment()`.
@Test @MainActor func anAppBuiltFrameTimingTracesWhenTheEnvironmentIsSet() throws {
    try withTraceEnvironment { path in
        let window = try harnessWindow { VStack(spacing: 0) { TimingKeyBox() } }
        window.platformWindow.headlessRenderer.reportsPresentation = true
        window.window.frameTiming = FrameTiming(capacity: 8192)
        window.typeKey(.tab)
        window.typeKey("a")
        window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
        #expect(readTrace(path).count >= 2, "header and a line")
    }
    let explicit = NSTemporaryDirectory() + "metalui-trace-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: explicit) }
    let window = try harnessWindow { VStack(spacing: 0) { TimingKeyBox() } }
    window.platformWindow.headlessRenderer.reportsPresentation = true
    let timing = FrameTiming(capacity: 64)
    timing.enableTrace(destination: explicit)
    window.window.frameTiming = timing
    window.typeKey(.tab)
    window.typeKey("a")
    window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    #expect(readTrace(explicit).count >= 2)
}

/// 1.15 — enabling writes the header at once (before any frame), a line is on disk the moment it is produced,
/// and two timings on one file neither repeat the header nor overwrite each other. Mutations: the header left
/// lazy; a per-timing file offset instead of an appending shared descriptor.
@Test @MainActor func theTraceHeaderIsWrittenOnEnableAndLinesAreOnDiskAsProduced() throws {
    try withTraceEnvironment { path in
        let first = FrameTiming(), second = FrameTiming()
        #expect(readTrace(path) == [FrameTiming.traceHeader], "header at enable, once for two timings")
        first.traceSink?("one"); second.traceSink?("two"); first.traceSink?("three")
        #expect(readTrace(path) == [FrameTiming.traceHeader, "one", "two", "three"])
    }
}

// MARK: Re-entrant attribution and the summary (`FP-K`)

/// 1.16 — a handler that dispatches another event re-entrantly keeps the outer event as the candidate: the inner
/// one (clean) used to replace it and the outer one's defer then settled nothing. Fails before `FP-K`.
@Test @MainActor func aReentrantDispatchDoesNotClobberTheOuterInput() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    window.window.onInput = { [unowned window] event in
        guard case .keyDown = event else { return false }   // inner: unclaimed, so clean
        window.send(.modifiersChanged([]))
        return true   // outer: claimed, so the window is dirtied
    }
    window.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "z", characters: "z", timestamp: 0)))
    window.tick()
    let sample = try #require(timing.last)
    #expect(sample.inputKind == .key)
    #expect(sample.inputCount == 1)
}

/// 1.17 — an input that truly causes nothing gets no frame and no line, and the counters say why. Mutation:
/// `settleInput` keeping every clean input.
@Test @MainActor func aTrulyNoOpInputWritesNoLineAndIsCounted() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    window.platformWindow.headlessRenderer.reportsPresentation = true
    window.window.setNeedsRedraw(); window.tick()   // flush the setup frames' presentations first
    window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    var lines: [String] = []
    timing.traceSink = { lines.append($0) }
    let noInputBefore = timing.presentedNoInputCount
    let before = timing.settledCleanCount
    window.send(.modifiersChanged([]))
    window.window.setNeedsRedraw()   // a timer frame, not the input
    window.tick()
    window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    #expect(timing.last?.inputKind == nil)
    #expect(!lines.contains { $0.hasPrefix("metalui-latency ") })
    #expect(timing.settledCleanCount == before + 1)
    #expect(timing.presentedNoInputCount == noInputBefore + 1)
}

/// 1.18 — the summary line: stable field order, on demand and every 100 presentation reports. Mutation: the
/// automatic write removed; `traceLinesWritten` not incremented.
@Test @MainActor func theTraceSummaryCountsAndIsWrittenOnDemandAndEveryHundredReports() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    window.platformWindow.headlessRenderer.reportsPresentation = true
    var lines: [String] = []
    timing.traceSink = { lines.append($0) }
    window.typeKey("a")
    window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    #expect(timing.traceLinesWritten == 1)
    timing.writeTraceSummary()
    #expect(lines.last == "metalui-latency-summary written=1 presentedNoInput=\(timing.presentedNoInputCount) "
        + "dropped=0 settledClean=\(timing.settledCleanCount) gpuMissing=0")
    lines.removeAll()
    for _ in 0..<FrameTiming.summaryInterval {
        window.window.setNeedsRedraw()
        window.tick()
        window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    }
    #expect(lines.contains { $0.hasPrefix("metalui-latency-summary ") }, "automatic summary")
}

// MARK: Immediate input (`FP-L`, `FP-M`)

private func keyA() -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: "a", characters: "a", timestamp: 0))
}

/// The pacing clock a test drives by hand, in nanoseconds.
@MainActor private final class PacingClock {
    var now: UInt64 = 1_000_000_000
    func advance(by nanos: UInt64) { now += nanos }
}

/// A window with immediate input on, a hand-driven clock, and a settled (clean, link paused) first state.
@MainActor private func immediateWindow(_ timing: FrameTiming?) throws -> (TestWindow, PacingClock) {
    let window = try timedWindow(timing)
    let clock = PacingClock()
    window.window.immediateInputClock = { clock.now }
    window.window.drawsImmediatelyOnInput = true
    window.tick()   // idle: clean, nothing animating
    clock.advance(by: 1_000_000_000)   // long after any frame: the first key after idle
    return (window, clock)
}

private let interval = ImmediateInput.fallbackInterval

/// 1.20 — an idle window draws a key's frame inside the input; the tick that follows draws none (no double draw)
/// and the sample has no tick. Off (the harness default), the same key draws nothing until the tick. Mutations:
/// the idle check dropped (a dirty window draws too); `drawImmediatelyAfterInput` not run; the draw placed before
/// `settleInput` (the sample then has no input); `discardTick` removed (the sample claims the idle tick).
@Test @MainActor func immediateInputDrawsInsideTheHandlerAndTheTickDrawsNothingMore() throws {
    let timing = FrameTiming()
    let (window, _) = try immediateWindow(timing)
    let before = window.window.framesDrawn
    window.send(keyA())
    #expect(window.window.framesDrawn == before + 1, "drawn synchronously, before any tick")
    let sample = try #require(timing.last)
    #expect(sample.inputKind == .key && sample.tickStart == nil, "the input is claimed; no tick drove the frame")
    window.tick()
    #expect(window.window.framesDrawn == before + 1, "the following tick draws no duplicate")

    window.window.drawsImmediatelyOnInput = false
    window.send(keyA())
    #expect(window.window.framesDrawn == before + 1, "off: nothing is drawn until the tick")
    window.tick()
    #expect(window.window.framesDrawn == before + 2)
}

/// 1.21 — never inside a frame, never for a pointer move. Mutation: the `isDrawingFrame` guard dropped (the
/// nested send draws a frame inside the frame).
@Test @MainActor func immediateInputNeverDrawsInsideAFrameOrForAMove() throws {
    let timing = FrameTiming()
    let (window, clock) = try immediateWindow(timing)
    var nestedDraws: [Int] = []
    timing.onFrame = { [unowned window, unowned clock] _ in
        clock.advance(by: 10 * interval)
        let drawn = window.window.framesDrawn
        window.send(keyA())   // dispatched while the frame is still running
        nestedDraws.append(window.window.framesDrawn - drawn)
    }
    window.window.setNeedsRedraw()
    window.window.drawFrameIfNeeded()
    #expect(nestedDraws == [0], "no frame inside a frame")
    timing.onFrame = nil
    window.window.drawFrameIfNeeded()   // the dirtied window's next frame
    window.tick()
    clock.advance(by: 10 * interval)
    let before = window.window.framesDrawn
    window.send(.mouseMoved(MouseEvent(position: pt(3, 3))))
    #expect(window.window.framesDrawn == before, "a move keeps the display link's pacing")
}

/// 1.25 — pacing: at most one immediate frame per refresh interval. The first key after idle draws at once; keys
/// inside the interval (a key repeat, a burst) draw nothing and leave the window dirty for the tick, which draws
/// them as ONE frame; a key a whole interval after that frame draws at once again. Mutations: the interval check
/// removed (the second key draws); `lastCommitForPacing` not stamped (every key draws); the comparison
/// reversed.
@Test @MainActor func immediateInputDrawsAtMostOneFramePerRefreshInterval() throws {
    let (window, clock) = try immediateWindow(nil)
    let w = window.window
    let start = w.framesDrawn
    window.send(keyA())
    #expect(w.framesDrawn == start + 1, "the first key after idle")
    for _ in 0..<5 {
        clock.advance(by: interval / 10)
        window.send(keyA())
    }
    #expect(w.framesDrawn == start + 1, "a burst inside one interval draws no more immediately")
    #expect(w.needsRedraw, "left dirty for the tick")
    window.tick()
    #expect(w.framesDrawn == start + 2, "the tick draws the burst as one frame")
    clock.advance(by: interval - 1)
    window.send(keyA())
    #expect(w.framesDrawn == start + 2, "one nanosecond short of an interval")
    window.tick()
    clock.advance(by: interval)
    window.send(keyA())
    #expect(w.framesDrawn == start + 4, "an interval later it draws at once")
}

/// 1.26 — the interval is the display link's: the smallest gap between tick targets of 2 to 50 ms, 60 Hz until
/// known. At 8 ms (120 Hz) a key 9 ms after the last frame draws; at 60 Hz it would not. Mutation: the learned
/// interval ignored (the fallback used).
@Test @MainActor func theImmediateInputPacingFollowsTheDisplayLinksInterval() throws {
    let window = try timedWindow(nil)
    let w = window.window
    let clock = PacingClock()
    w.immediateInputClock = { clock.now }
    w.drawsImmediatelyOnInput = true
    let unknown: UInt64? = w.displayLinkInterval
    #expect(unknown == nil)
    window.advance(by: 0.008); window.advance(by: 0.008); window.advance(by: 0.5)   // the long gap is not an interval
    let learned: UInt64? = w.displayLinkInterval
    let expected: UInt64 = 8_000_000
    #expect(learned == expected)
    w.setNeedsRedraw(); w.drawFrameIfNeeded()   // stamps the last commit at `clock.now`
    window.tick()
    clock.advance(by: 9_000_000)
    let before = w.framesDrawn
    window.send(keyA())
    #expect(w.framesDrawn == before + 1, "9 ms is past 8 ms")
}

/// 1.27 — IME: composition behaves like text input. The first composition update at an idle window draws, the
/// next ones inside the interval do not (the tick draws them once), and the commit an interval later draws.
/// Mutation: `.textComposition` dropped from the immediate kinds (the first update waits for the tick).
@Test @MainActor func compositionUpdatesDrawAtMostOncePerIntervalAndTheCommitDraws() throws {
    let (window, clock) = try immediateWindow(nil)
    let w = window.window
    let start = w.framesDrawn
    window.send(.textComposition(TextComposition(text: "k", selection: 1..<1)))
    #expect(w.framesDrawn == start + 1, "the first update draws")
    clock.advance(by: interval / 4)
    window.send(.textComposition(TextComposition(text: "ka", selection: 2..<2)))
    clock.advance(by: interval / 4)
    window.send(.textComposition(TextComposition(text: "kan", selection: 3..<3)))
    #expect(w.framesDrawn == start + 1, "updates inside the interval wait")
    window.tick()
    #expect(w.framesDrawn == start + 2, "one frame for both")
    clock.advance(by: interval)
    window.send(.textInput("kan"))
    #expect(w.framesDrawn == start + 3, "the commit draws at once")
}

private struct AnimatingBox: Component {
    @State var wide = false
    var content: some ElementGroup {
        Box().frame(width: Pixels(wide ? 100 : 20), height: Pixels(20)).background(.accent)
            .focusable()
            .onKeyPress("a") { withAnimation(.linear(duration: 1)) { wide.toggle() }; return .handled }
    }
}

/// 1.28 — an animation in flight keeps the tick path: a window with a running animation does not draw a key
/// immediately. Mutation: `hasActiveAnimations` dropped from the idle check.
@Test @MainActor func immediateInputYieldsToARunningAnimation() throws {
    let window = try harnessWindow { VStack(spacing: 0) { AnimatingBox() } }
    let w = window.window
    let clock = PacingClock()
    w.immediateInputClock = { clock.now }
    window.typeKey(.tab)
    window.tick()
    window.send(keyA())   // starts the 1 s animation (immediate input still off: the tick draws it)
    window.tick()
    w.drawsImmediatelyOnInput = true
    #expect(w.hasActiveAnimations, "the animation is running")
    clock.advance(by: 10 * interval)
    let before = w.framesDrawn
    window.send(keyA())
    #expect(w.framesDrawn == before, "tick path while animating")
    window.advance(by: 0.1)
    #expect(w.framesDrawn > before)
}

/// 1.29 — idle cost: after an immediate frame, any number of idle ticks draw nothing and the display link pauses
/// (each idle tick re-pauses it; none wakes it). Mutations: the immediate path leaving the window dirty (the
/// tick draws again); `setDisplayLinkPaused(true)` removed from the idle branch.
@Test @MainActor func idleTicksAfterAnImmediateFrameDrawNothingAndTheLinkPauses() throws {
    let (window, _) = try immediateWindow(nil)
    let w = window.window
    window.send(keyA())
    let drawn = w.framesDrawn
    let pauses = w.pausesEntered
    for _ in 0..<20 { window.tick() }
    #expect(w.framesDrawn == drawn, "no frame from an idle tick")
    #expect(!w.needsRedraw)
    #expect(w.pausesEntered == pauses + 20, "each idle tick pauses the link")
    #expect(window.platformWindow.displayLinkPauses.last == true, "and the last word to the link is pause")
}

/// 1.30 — the switch: `METALUI_IMMEDIATE_INPUT` `1` and `0` override the platform default, anything else keeps
/// it; a harness window starts tick-driven; the trace header names the switch. Mutations: `0` ignored; the
/// default inverted.
@Test @MainActor func theImmediateInputSwitchOverridesThePlatformDefault() throws {
    let on = ["METALUI_IMMEDIATE_INPUT": "1"], off = ["METALUI_IMMEDIATE_INPUT": "0"]
    let junk = ["METALUI_IMMEDIATE_INPUT": "yes"]
    #expect(ImmediateInput.isEnabled(platformDefault: true, environment: [:]))
    #expect(!ImmediateInput.isEnabled(platformDefault: false, environment: [:]))
    #expect(ImmediateInput.isEnabled(platformDefault: false, environment: on))
    #expect(!ImmediateInput.isEnabled(platformDefault: true, environment: off))
    #expect(ImmediateInput.isEnabled(platformDefault: true, environment: junk))
    #expect(!ImmediateInput.isEnabled(platformDefault: false, environment: junk))
    let window = try harnessWindow { VStack(spacing: 0) { TimingKeyBox() } }
    #expect(!window.window.drawsImmediatelyOnInput, "the harness stays tick-driven until a test opts in")
    #expect(FrameTiming.header(immediate: "on").hasSuffix(" immediate=on"))
}

/// 1.31 — a presentation report of 0 (dropped, or macOS giving no time) still writes the input's line: `-` for
/// `commit>screen` and `total`; the summary counts it as written and dropped. Mutations: the nil path returning
/// before the trace write (no line); the line not counted in `written`.
@Test @MainActor func aZeroPresentationReportStillWritesTheInputsLine() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    let renderer = window.platformWindow.headlessRenderer
    renderer.reportsPresentation = true
    var lines: [String] = []
    timing.traceSink = { lines.append($0) }
    let written = timing.traceLinesWritten, dropped = timing.droppedCount
    window.typeKey("a")   // (the renderer's first report token maps to the setup frame that took the Tab: it has input)
    renderer.deliverUnreportedPresentations()
    let line = try #require(lines.first { $0.hasPrefix("metalui-latency ") && !$0.contains(" idx ") })
    let columns = line.components(separatedBy: " | ")
    #expect(columns.count == 3 && columns[2].hasPrefix("- "), "total is -: \(line)")
    let stages = columns[1].split(separator: " ")
    #expect(stages.count == 9 && stages[6] == "-", "commit>screen is -: \(line)")
    #expect(timing.traceLinesWritten == written + 1 && timing.droppedCount == dropped + 1)
    timing.writeTraceSummary()
    #expect(lines.last == "metalui-latency-summary written=\(written + 1) presentedNoInput=\(timing.presentedNoInputCount) "
        + "dropped=\(dropped + 1) settledClean=\(timing.settledCleanCount) gpuMissing=0")
}

/// 1.24 — the vsync estimate is the first tick target at or after the commit, in whole intervals, from the
/// frame's tick or else the last seen one; unknown without an interval; and it is its own column. Mutations:
/// rounding down; the estimate written into `commit>screen`.
@Test @MainActor func theVsyncEstimateIsTheFirstTickAtOrAfterTheCommit() {
    var s = FrameTimingSample(frameIndex: 0, start: 1_000)
    s.commit = 1_000 + 20_000_000
    s.tickTarget = 1_000 + 16_000_000
    // Compared outside `#expect`: the macro's expansion of an optional-`UInt64` comparison crashes the Windows
    // Swift 6.4 compiler (SILGen reabstraction thunk through `AnyHashable`).
    let fromTick: UInt64? = FrameTiming.estimatedVsync(for: s, interval: 16_000_000, phase: nil)
    let expectedFromTick: UInt64 = 1_000 + 32_000_000
    let fromTickMatches = fromTick == expectedFromTick
    #expect(fromTickMatches, "missed one: \(String(describing: fromTick))")
    s.tickTarget = nil
    let fromPhase: UInt64? = FrameTiming.estimatedVsync(for: s, interval: 16_000_000, phase: 1_000 + 48_000_000)
    let expectedFromPhase: UInt64 = 1_000 + 32_000_000   // `FP-O`: stepped back from the later tick, not that tick
    let fromPhaseMatches = fromPhase == expectedFromPhase
    #expect(fromPhaseMatches, "\(String(describing: fromPhase))")
    let unknown: UInt64? = FrameTiming.estimatedVsync(for: s, interval: nil, phase: 1)
    let isUnknown = unknown == nil
    #expect(isUnknown)
    let line = FrameTiming.traceLine(for: s, interval: 16_000_000, vsyncPhase: 1_000 + 48_000_000)
    #expect(line.contains(" - 12.00 - | "), "commit>screen unreported (-), est>screen 12.00")
}

/// 1.26 — `FP-O`: the estimate is the first vsync after the commit whichever side of it the phase lies on. A
/// phase later than the commit (a tick that ran before the frame was reported) steps back; a phase stale by more
/// than a second, and an exact hit, are handled. Mutation: the step back removed (the later tick is returned,
/// 21-32 ms for a 16.7 ms display); the distance cap removed.
@Test @MainActor func theVsyncEstimateStepsBackFromALaterPhaseAndIsUnknownWhenStale() {
    let period: UInt64 = 16_666_667
    var s = FrameTimingSample(frameIndex: 0, start: 1_000)
    s.commit = 5_000_000_000
    for k: UInt64 in 0...3 {   // a later tick k periods past the first vsync after the commit
        let first = s.commit + 4_000_000
        let result: UInt64? = FrameTiming.estimatedVsync(for: s, interval: period, phase: first + k * period)
        let matches = result == first
        #expect(matches, "k=\(k): \(String(describing: result))")
    }
    let exact: UInt64? = FrameTiming.estimatedVsync(for: s, interval: period, phase: s.commit + 2 * period)
    let exactMatches = exact == s.commit
    #expect(exactMatches, "a vsync at the commit itself")
    let earlier: UInt64? = FrameTiming.estimatedVsync(for: s, interval: period, phase: s.commit - 3 * period + 1)
    let earlierMatches = earlier == s.commit + 1
    #expect(earlierMatches, "an earlier phase steps forward: \(String(describing: earlier))")
    let stale: UInt64? = FrameTiming.estimatedVsync(for: s, interval: period, phase: 1_000)
    let staleIsUnknown = stale == nil
    #expect(staleIsUnknown, "a phase seconds away is no phase")
    let line = FrameTiming.traceLine(for: s, interval: period, vsyncPhase: 1_000)
    #expect(line.contains(" - - - | "), "est>screen is - for a stale phase: \(line)")
}

// MARK: GPU time (`FP-P`)

/// 1.40 — a frame's GPU time lands in its sample and in the trace line's `gpu` column; a line whose GPU time
/// has not arrived when the frame is presented waits for it (lines stay ordered), and one that never arrives
/// is written with `-` before the next frame's line and counted in `gpuMissing`. Mutations: the hold removed
/// (the line prints `-` although the time comes next); `noteGPU` not writing the held line (it is lost); the
/// flush removed (a later line overtakes it).
@Test @MainActor func aFramesGPUTimeJoinsItsTraceLineEvenWhenItArrivesAfterThePresentation() throws {
    let timing = FrameTiming()
    let window = try timedWindow(nil)
    let renderer = window.platformWindow.headlessRenderer
    renderer.reportsPresentation = true
    renderer.reportsGPUTime = true
    window.window.frameTiming = timing   // bound at the next frame, with the GPU observer on
    var lines: [String] = []
    timing.traceSink = { lines.append($0) }
    func gpuColumn(_ line: String) -> String {
        line.components(separatedBy: " | ")[1].split(separator: " ").last.map(String.init) ?? ""
    }
    // GPU first, then presentation.
    window.typeKey("a")
    renderer.deliverGPUTimes(nanos: 2_500_000)
    renderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    var data = lines.filter { $0.hasPrefix("metalui-latency ") && !$0.contains(" idx ") }
    #expect(data.count == 1 && gpuColumn(data[0]) == "2.50", "\(data)")
    let stored: UInt64? = timing.last?.gpuNanos   // compared outside `#expect` (Windows compiler)
    let storedMatches = stored == 2_500_000
    #expect(storedMatches)
    // Presentation first: the line waits, then is written by the GPU report.
    lines.removeAll()
    window.typeKey("b")
    renderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    data = lines.filter { $0.hasPrefix("metalui-latency ") }
    #expect(data.isEmpty, "the line waits for its GPU time")
    renderer.deliverGPUTimes(nanos: 4_000_000)
    data = lines.filter { $0.hasPrefix("metalui-latency ") }
    #expect(data.count == 1 && gpuColumn(data[0]) == "4.00", "\(data)")
    // A GPU time that never comes: the next presentation writes the older line first, with `-`.
    lines.removeAll()
    let missingBefore = timing.gpuMissingCount
    window.typeKey("c")
    renderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    window.typeKey("d")
    renderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    data = lines.filter { $0.hasPrefix("metalui-latency ") }
    #expect(data.count >= 1 && gpuColumn(data[0]) == "-", "\(data)")
    #expect(timing.gpuMissingCount > missingBefore)
    let indices = data.compactMap { Int($0.split(separator: " ")[1]) }
    #expect(indices == indices.sorted(), "lines stay in frame order")
}

/// 1.41 — a renderer that reports no GPU time (SDL, headless by default) leaves `gpuNanos` `nil`, prints `-`
/// and never holds a line. Mutation: `expectsGPUTime` defaulting to `true` (the lines wait forever).
@Test @MainActor func aRendererWithNoGPUTimePrintsADashAndHoldsNothing() throws {
    let timing = FrameTiming()
    let window = try timedWindow(timing)
    window.platformWindow.headlessRenderer.reportsPresentation = true
    var lines: [String] = []
    timing.traceSink = { lines.append($0) }
    window.typeKey("a")
    window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000)
    let line = try #require(lines.first { $0.hasPrefix("metalui-latency ") && !$0.contains(" idx ") })
    #expect(line.components(separatedBy: " | ")[1].hasSuffix(" -"), "\(line)")
    let none = timing.last?.gpuNanos == nil
    #expect(none)
    #expect(timing.gpuMissingCount == 0)
    var sample = FrameTimingSample(frameIndex: 0, start: 1)
    #expect(FrameTiming.traceLine(for: sample, interval: nil).contains(" - | "))
    sample.gpuNanos = 1_234_000
    #expect(FrameTiming.traceLine(for: sample, interval: nil).contains(" 1.23 | "))
    #expect(FrameTiming.traceHeader.contains("est>screen gpu | total"))
}
