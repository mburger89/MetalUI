import Foundation
import MetalUIPlatform
#if canImport(os)
import os
#endif

// Opt-in frame instrumentation (ruling `FP-A`..`FP-H`, `docs/superpowers/2026-11-07-frame-signposts-decisions.md`).
// Off by default: a `Window` with no `FrameTiming` pays one optional check per input event and per frame, and
// allocates nothing (pinned by `FrameTimingTests`).

/// The kind of input that started a frame's latency clock (``FrameTimingSample/inputKind``).
///
/// MetalUI-only (`FP-A`): SwiftUI has no frame instrumentation.
public enum FrameInputKind: Sendable, Equatable {
    /// A key press or release, or a modifier change.
    case key
    /// Committed text or an input method's marked text.
    case text
    /// A pointer press, release, move, drag, pinch, rotation or drop.
    case pointer
    /// A scroll wheel or trackpad scroll step.
    case wheel
    /// Anything else that dirtied the window: a menu, dialog, alert or toolbar answer.
    case other
}

/// One frame's timestamps (ruling `FP-B`): when the input that caused it arrived, when each phase ended, when the
/// frame was committed to the platform and, later and only where the platform reports it, when it reached the
/// screen. Every time is **nanoseconds on ``FrameTiming/now()``'s clock**.
///
/// MetalUI-only (`FP-A`).
public struct FrameTimingSample: Sendable, Equatable {
    /// This frame's index since the ``FrameTiming`` was created: 0 for the first frame it recorded.
    public var frameIndex: UInt64
    /// The earliest input event handled since the previous frame that left the window dirty, or `nil` for a
    /// frame no input caused (an animation, a timer, a state write from a task).
    public var inputKind: FrameInputKind?
    /// When that input event occurred, for latency attribution: the platform's own event timestamp when it is on
    /// ``FrameTiming/now()``'s clock (AppKit's `NSEvent.timestamp`), else ``inputReceived``. `nil` with no input.
    public var inputTimestamp: UInt64?
    /// When the window received that event (``FrameTiming/now()`` read as the platform handed it over). `nil`
    /// with no input. ``inputTimestamp`` is at or before this.
    public var inputReceived: UInt64?
    /// How many input events dirtied the window since the previous frame (this frame covers all of them).
    public var inputCount: Int
    /// When the display-link callback that drove this frame ran (``FrameTiming/now()``'s clock), or `nil` for a
    /// frame not driven by a tick (a direct `drawFrameIfNeeded()`). With ``inputReceived`` this is the wait for
    /// the next tick: the largest single term of key-to-screen latency on a display-link-paced window.
    public var tickStart: UInt64?
    /// The display link's `targetTimestamp` for that tick: when the frame being built is expected on screen
    /// (``FrameTiming/now()``'s clock), or `nil` where the platform reports none or off our clock.
    public var tickTarget: UInt64?
    /// The frame function started drawing (before the platform's drawable is acquired, so a stalled
    /// `nextDrawable()` shows as the gap before ``drawableAcquired``).
    public var buildStart: UInt64
    /// The platform's drawable (Metal: `CAMetalLayer.nextDrawable()`) was acquired. ``drawableAcquired`` minus
    /// ``buildStart`` is the time `nextDrawable()` blocked.
    public var drawableAcquired: UInt64
    /// Layout finished (the last build, when a frame builds more than once).
    public var layoutEnd: UInt64
    /// Prepaint finished (hitboxes, hover and focus resolved).
    public var prepaintEnd: UInt64
    /// Paint finished: the scene is built, nothing is encoded yet.
    public var paintEnd: UInt64
    /// `WindowRenderer.finishFrame` returned: on Metal the command buffer is committed, on SDL the frame is
    /// submitted. Not the time pixels changed — see ``presented``.
    public var commit: UInt64
    /// When the frame reached the screen, where the platform reports it (Metal: the drawable's
    /// `presentedTime`); `nil` where it does not (SDL, the headless renderer by default), when the frame was
    /// dropped, and until the platform reports it (the sample in the ring is updated in place).
    public var presented: UInt64?
    /// The frame's GPU execution time in nanoseconds (`FP-P`): its command buffer's `gpuEndTime - gpuStartTime`
    /// on Metal (one buffer per window frame, so no summing), `nil` where the renderer reports none (SDL, the
    /// headless renderer by default), when the GPU failed the frame, and **until the platform reports it** (the
    /// sample in the ring is updated in place, usually before ``presented``, possibly after).
    public var gpuNanos: UInt64?

    /// A sample whose phases all read `start`; the window stamps the rest.
    package init(frameIndex: UInt64, start: UInt64) {
        self.frameIndex = frameIndex
        inputKind = nil; inputTimestamp = nil; inputReceived = nil; inputCount = 0
        tickStart = nil; tickTarget = nil
        buildStart = start; drawableAcquired = start; layoutEnd = start; prepaintEnd = start; paintEnd = start; commit = start
        presented = nil; gpuNanos = nil
    }

    /// Input to commit in nanoseconds, or `nil` for a frame no input caused: the keystroke-to-submit latency.
    public var inputToCommit: UInt64? {
        guard let inputTimestamp else { return nil }
        return commit >= inputTimestamp ? commit - inputTimestamp : 0
    }

    /// Input to screen in nanoseconds, or `nil` with no input or no presentation time.
    public var inputToPresented: UInt64? {
        guard let inputTimestamp, let presented else { return nil }
        return presented >= inputTimestamp ? presented - inputTimestamp : 0
    }

    /// Input arrival to the display-link tick that built the frame, in nanoseconds, or `nil` with no input or no
    /// tick: how long the event waited for the next tick.
    public var inputToTick: UInt64? {
        guard let inputReceived, let tickStart else { return nil }
        return tickStart >= inputReceived ? tickStart - inputReceived : 0
    }

    /// How long acquiring the platform's drawable took, in nanoseconds (`nextDrawable()` blocks when every
    /// drawable is in flight).
    public var drawableWait: UInt64 { drawableAcquired >= buildStart ? drawableAcquired - buildStart : 0 }

    /// Frame start to commit in nanoseconds: what the frame cost the process.
    public var frameDuration: UInt64 { commit >= buildStart ? commit - buildStart : 0 }
}

/// A fixed-capacity ring of ``FrameTimingSample``s for one ``Window`` (ruling `FP-B`), plus the opt-in macOS
/// signposts (`FP-E`). Assign one to ``Window/frameTiming`` to start recording; set it back to `nil` to stop.
///
/// **Zero cost off** (`FP-C`): a window with no `FrameTiming` makes one optional check per input event and per
/// frame, reads no clock and allocates nothing. **Zero allocation on**, too, in steady state: the ring is
/// allocated here, once, and each frame overwrites its slot in place.
///
/// **Never written from a phase** (`FP-D`): input is noted by the platform's event handler, a frame's phase
/// stamps are four clock reads, and ``onFrame`` and ``onPresented`` run after the frame, outside every phase, so
/// a state write in either schedules the next frame like any input.
///
/// ```swift
/// let timing = FrameTiming()
/// window.frameTiming = timing
/// // … type, scroll …
/// let worst = timing.samples.compactMap(\.inputToCommit).max()
/// ```
///
/// MetalUI-only (`FP-A`).
@MainActor
public final class FrameTiming {
    /// The capacity ``init(capacity:emitsSignposts:)`` uses by default.
    public static let defaultCapacity = 512

    /// How many samples the ring keeps; older ones are overwritten.
    public let capacity: Int
    /// Called after each frame is committed, with its sample (``FrameTimingSample/presented`` still `nil`). Runs at
    /// the end of the frame function, outside every phase.
    public var onFrame: (@MainActor (FrameTimingSample) -> Void)?
    /// Called when the platform reports a frame's presentation, with the sample updated in the ring. Never called
    /// where the platform reports none. Runs on the main actor, outside every phase.
    public var onPresented: (@MainActor (FrameTimingSample) -> Void)?
    /// How many frames this timing has recorded, including those the ring has since overwritten; also the next
    /// frame's ``FrameTimingSample/frameIndex``.
    public private(set) var framesRecorded: UInt64 = 0

    private var ring: ContiguousArray<FrameTimingSample>
    private var current: FrameTimingSample?
    private var candidate: (kind: FrameInputKind, received: UInt64, stamp: UInt64)?
    /// Handlers currently running between ``noteInput(_:)`` and ``settleInput(dirtied:)``: more than one means a
    /// handler dispatched another event re-entrantly (`FP-K`).
    private var inputDepth = 0

    private var pending: (kind: FrameInputKind, received: UInt64, stamp: UInt64, count: Int)?
    private var inFlight: (kind: FrameInputKind, received: UInt64, stamp: UInt64, count: Int)?
    #if canImport(os)
    private let signposts: Signposts?
    #endif

    /// A timing keeping the last `capacity` frames (at least 1). `emitsSignposts` also emits the Instruments
    /// signposts documented in `docs/guides/frame-timing.md` (macOS and other `os` platforms; ignored elsewhere,
    /// see ``emitsSignposts``).
    public init(capacity: Int = FrameTiming.defaultCapacity, emitsSignposts: Bool = false) {
        let capacity = max(1, capacity)
        self.capacity = capacity
        ring = ContiguousArray(repeating: FrameTimingSample(frameIndex: 0, start: 0), count: capacity)
        #if canImport(os)
        signposts = emitsSignposts ? Signposts() : nil
        #endif
        // `FP-J`: the environment applies to every timing, not only the one a window builds by default, so an
        // app that assigns its own recorder to `Window.frameTiming` still traces.
        if let destination = Self.environmentTraceDestination() { enableTrace(destination: destination) }
    }

    /// Whether this timing emits `OSSignposter` signposts: `true` only where the `os` framework exists and the
    /// initialiser asked.
    public var emitsSignposts: Bool {
        #if canImport(os)
        return signposts != nil
        #else
        return false
        #endif
    }

    /// The timing `METALUI_SIGNPOSTS=1` asks for (signposts on), else `nil`. Read once per window.
    static func fromEnvironment() -> FrameTiming? {
        let signposts = getenv("METALUI_SIGNPOSTS").map { String(cString: $0) == "1" } ?? false
        guard signposts || Self.environmentTraceDestination() != nil else { return nil }
        return FrameTiming(emitsSignposts: signposts)   // `init` applies `METALUI_LATENCY_TRACE`
    }

    // MARK: Latency trace (`METALUI_LATENCY_TRACE`)

    /// Receives one line per input-caused frame once it is presented, plus a header before the first. `nil`: no
    /// trace. Set by ``enableTrace(destination:)``; a test sets it directly.
    package var traceSink: ((String) -> Void)?
    private var traceHeaderWritten = false
    private var lastTickTarget: UInt64?
    /// The shortest gap seen between consecutive tick targets: the display's refresh interval, nanoseconds.
    package private(set) var refreshInterval: UInt64?
    private var pendingTick: (start: UInt64, target: UInt64?)?
    /// Whether the renderer reports GPU times (`FP-P`): set by the window when it installs the GPU observer. When
    /// `true` a trace line waits (bounded) for its frame's GPU time.
    package var expectsGPUTime = false
    /// Frames whose GPU report arrived (with or without a value) and whose line is not yet written.
    private var gpuSettled: Set<UInt64> = []
    /// Lines waiting for their GPU time (`FP-P`), oldest first: the sample, and the interval and phase the line
    /// is formatted with, taken when the presentation arrived.
    private var heldLines: [(sample: FrameTimingSample, interval: UInt64?, phase: UInt64?)] = []

    /// `METALUI_LATENCY_TRACE`'s destination, or `nil` when it is unset, empty or `0`.
    private static func environmentTraceDestination() -> String? {
        let trace = getenv("METALUI_LATENCY_TRACE").map { String(cString: $0) } ?? ""
        return trace.isEmpty || trace == "0" ? nil : trace
    }

    /// One open append-only descriptor per destination, shared by every timing in the process (several windows
    /// must not each hold an offset into one file), and the destinations whose header is already written.
    private static var traceFiles: [String: FileHandle] = [:]
    private static var traceHeadersWritten: Set<String> = []

    /// Turns the latency trace on (ruling `FP-J`): one line per input-caused frame once the platform reports it
    /// presented, preceded by a header. `destination` `"1"` writes to standard error; any other value is a file
    /// path lines are appended to (created if absent; an unwritable path falls back to standard error). The
    /// header is written at once and each line when it is produced, unbuffered, so the file is readable while
    /// the app runs and survives a kill. `METALUI_LATENCY_TRACE` does this for every new ``FrameTiming``;
    /// call this to turn it on from code. MetalUI-only.
    public func enableTrace(destination: String) {
        let handle: FileHandle
        if destination == "1" {
            handle = .standardError
        } else if let shared = Self.traceFiles[destination] {
            handle = shared
        } else {
            // Foundation only, no POSIX `open` (the Windows CRT's `_open` aborts on Unix mode bits). One handle
            // per path, shared by every timing in the process and positioned at the end, so lines append.
            if !FileManager.default.fileExists(atPath: destination) {
                _ = FileManager.default.createFile(atPath: destination, contents: nil)
            }
            if let file = FileHandle(forWritingAtPath: destination), (try? file.seekToEnd()) != nil {
                handle = file
                Self.traceFiles[destination] = handle
            } else {
                handle = .standardError
            }
        }
        traceSink = { line in try? handle.write(contentsOf: Data((line + "\n").utf8)) }
        traceHeaderWritten = true
        if Self.traceHeadersWritten.insert(destination).inserted { traceSink?(Self.traceHeader) }
    }

    /// Counters that explain a trace (`FP-K`, `FP-M`), always kept: lines written, presented frames no input caused,
    /// frames the platform reported with no presentation time (`presentedTime` 0: dropped, or on macOS every
    /// frame; their input lines are still written and counted in `written` too), inputs whose handler left the
    /// window clean.
    package private(set) var traceLinesWritten = 0
    package private(set) var presentedNoInputCount = 0
    package private(set) var droppedCount = 0
    package private(set) var settledCleanCount = 0
    /// Written lines whose `gpu` is `-` although the renderer reports GPU times: the report failed or came after
    /// the next presentation (`FP-P`).
    package private(set) var gpuMissingCount = 0
    private var reportsSinceSummary = 0

    /// Presentation reports between automatic summary lines.
    package static let summaryInterval = 100

    private func noteReport() {
        reportsSinceSummary += 1
        if reportsSinceSummary >= Self.summaryInterval { writeTraceSummary() }
    }

    /// The summary line: `metalui-latency-summary written=N presentedNoInput=N dropped=N settledClean=N gpuMissing=N`.
    /// Fields never reorder; new ones are appended.
    package var traceSummary: String {
        "metalui-latency-summary written=\(traceLinesWritten) presentedNoInput=\(presentedNoInputCount) "
            + "dropped=\(droppedCount) settledClean=\(settledCleanCount) gpuMissing=\(gpuMissingCount)"
    }

    /// Writes ``traceSummary`` to the trace now (nothing when tracing is off). Also written by itself after every
    /// 100 presentation reports, so a trace explains why it has few lines (`FP-K`). MetalUI-only.
    public func writeTraceSummary() {
        reportsSinceSummary = 0
        traceSink?(traceSummary)
    }

    /// The header ``traceLine(for:interval:)``'s columns follow.
    package static var traceHeader: String { header(immediate: ImmediateInput.label) }

    /// The header with `immediate=` set to `label` (`FP-M`): `on` or `off` when `METALUI_IMMEDIATE_INPUT` says so,
    /// `default` for the platform's choice (on for AppKit, off for SDL). `commit>screen` is the platform's
    /// report, `-` when it reports 0 (macOS does here); `est>screen` is MetalUI's own estimate (commit to the
    /// first vsync at or after it, from the display link's tick targets), never mixed into the other and `-`
    /// without a known interval.
    package static func header(immediate label: String) -> String {
        "metalui-latency idx kind n | ms: ev>recv recv>tick tick>build drawable build "
            + "encode commit>screen est>screen gpu | total frames immediate=\(label)"
    }

    /// One line: each stage's duration in milliseconds, the input-to-screen total and that total in refresh
    /// intervals (`-` when no interval is known). Stages with no stamp print `-`.
    package static func traceLine(for s: FrameTimingSample, interval: UInt64?, vsyncPhase: UInt64? = nil) -> String {
        func ms(_ ns: UInt64?) -> String { ns.map { String(format: "%.2f", Double($0) / 1e6) } ?? "-" }
        func gap(_ a: UInt64?, _ b: UInt64?) -> UInt64? {
            guard let a, let b else { return nil }
            return b >= a ? b - a : 0
        }
        let total = s.inputToPresented
        let frames: String
        if let total, let interval, interval > 0 {
            frames = String(format: "%.2f", Double(total) / Double(interval))
        } else { frames = "-" }
        let kind = s.inputKind.map { String(describing: $0) } ?? "none"
        return "metalui-latency \(s.frameIndex) \(kind) \(s.inputCount) | "
            + [ms(gap(s.inputTimestamp, s.inputReceived)), ms(s.inputToTick),
               ms(gap(s.tickStart, s.buildStart)), ms(s.drawableWait),
               ms(gap(s.drawableAcquired, s.paintEnd)), ms(gap(s.paintEnd, s.commit)),
               ms(gap(s.commit, s.presented)), ms(gap(s.commit, estimatedVsync(for: s, interval: interval, phase: vsyncPhase))),
               ms(s.gpuNanos)]
                .joined(separator: " ")
            + " | \(ms(total)) \(frames)"
    }

    /// The first vsync at or after the commit: the frame's own tick target (or `phase`, the last one seen) moved
    /// by whole refresh intervals, **forward or back** (`FP-O`). A tick target after the commit is stepped back
    /// to the earliest vsync still at or after it: a frame drawn outside a tick (an immediate-input frame) is
    /// reported after later ticks have moved `phase` on, and returning that tick was 21-32 ms off. Unknown (`nil`)
    /// without an interval or a reference, and when the reference is more than ``maxPhaseDistance`` from the
    /// commit (a stale phase: the error of the interval multiplies). An estimate from the display link, not a
    /// presentation time (`FP-L`).
    package static func estimatedVsync(for s: FrameTimingSample, interval: UInt64?, phase: UInt64?) -> UInt64? {
        guard let interval, interval > 0, let reference = s.tickTarget ?? phase else { return nil }
        if reference >= s.commit {
            guard reference - s.commit <= maxPhaseDistance else { return nil }
            return reference - (reference - s.commit) / interval * interval
        }
        guard s.commit - reference <= maxPhaseDistance else { return nil }
        let intervals = (s.commit - reference + interval - 1) / interval
        return reference + intervals * interval
    }

    /// How far a phase may lie from the commit it estimates for: one second.
    package static let maxPhaseDistance: UInt64 = 1_000_000_000

    // MARK: Reading

    /// The recorded samples, oldest first: at most ``capacity``. Allocates the array it returns.
    public var samples: [FrameTimingSample] {
        let count = Int(min(framesRecorded - retainedFrom, UInt64(capacity)))
        guard count > 0 else { return [] }
        let first = Int(framesRecorded) - count
        return (0..<count).map { ring[(first + $0) % capacity] }
    }

    /// The newest recorded sample, or `nil` before the first frame.
    public var last: FrameTimingSample? {
        framesRecorded == retainedFrom ? nil : ring[Int((framesRecorded - 1) % UInt64(capacity))]
    }

    /// Forgets the recorded samples; ``framesRecorded`` and the frame index keep counting.
    public func removeAll() { retainedFrom = framesRecorded }
    private var retainedFrom: UInt64 = 0

    /// The clock every timestamp is read from: nanoseconds of the system's monotonic uptime
    /// (`DispatchTime.now().uptimeNanoseconds`).
    ///
    /// **Why this one** (`FP-B`): it is `mach_absolute_time` on Apple platforms — the clock of
    /// `NSEvent.timestamp`, `CACurrentMediaTime()` and `MTLDrawable.presentedTime`, so an AppKit event's own
    /// timestamp and Metal's presentation time compare directly with the stamps taken here — and
    /// `CLOCK_MONOTONIC` elsewhere. It never goes backwards and does not follow the wall clock. (Swift's
    /// `ContinuousClock` also counts sleep and has no relation to those event clocks.) Reading it is a few
    /// dozen nanoseconds.
    public nonisolated static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    // MARK: Driver (called by `Window`, `Frame`, the renderer observer)

    /// The platform's event timestamp, seconds, where the event carries one.
    private static func platformTimestamp(of event: InputEvent) -> Double? {
        switch event {
        case .keyDown(let e), .keyUp(let e): return e.timestamp
        case .scrollWheel(let e): return e.timestamp
        case .mouseDown(let e), .mouseUp(let e), .mouseMoved(let e), .mouseDragged(let e),
             .rightMouseDown(let e), .rightMouseUp(let e), .rightMouseDragged(let e),
             .otherMouseDown(let e), .otherMouseDragged(let e), .otherMouseUp(let e): return e.timestamp
        case .magnify(let e): return e.timestamp
        case .rotate(let e): return e.timestamp
        default: return nil
        }
    }

    private static func kind(of event: InputEvent) -> FrameInputKind {
        switch event {
        case .keyDown, .keyUp, .modifiersChanged: return .key
        case .textInput, .textComposition: return .text
        case .scrollWheel: return .wheel
        case .mouseDown, .mouseUp, .mouseMoved, .mouseDragged, .rightMouseDown, .rightMouseUp,
             .rightMouseDragged, .otherMouseDown, .otherMouseDragged, .otherMouseUp, .magnify, .rotate,
             .drop, .pointerExited: return .pointer
        default: return .other
        }
    }

    /// An input event arrived. It becomes the next frame's input only if ``settleInput(dirtied:)`` says it
    /// dirtied the window.
    func noteInput(_ event: InputEvent) {
        inputDepth += 1
        // `FP-K`: a re-entrant dispatch (a handler sending another event) must not replace the outer event:
        // the outer one is the earlier.
        if candidate != nil { return }
        let received = Self.now()
        var stamp = received
        // The platform's own timestamp counts only when it is on our clock: within the second before now.
        if let seconds = Self.platformTimestamp(of: event), seconds > 0 {
            let nanos = seconds * 1_000_000_000
            if nanos.isFinite, nanos < Double(received), received - UInt64(nanos) <= 1_000_000_000 {
                stamp = UInt64(nanos)
            }
        }
        candidate = (Self.kind(of: event), received, stamp)
    }

    /// The handler for the last ``noteInput(_:)`` returned. A dirtied window keeps it as input to the next frame
    /// (the earliest such event wins, the rest are counted); a clean one drops it: it caused no frame.
    func settleInput(dirtied: Bool) {
        inputDepth -= 1
        guard inputDepth <= 0 else { return }   // `FP-K`: the outermost handler settles for all that ran inside it
        inputDepth = 0
        defer { candidate = nil }
        guard let candidate else { return }
        guard dirtied else {
            settledCleanCount += 1
            return
        }
        addPending(candidate)
    }

    private func addPending(_ input: (kind: FrameInputKind, received: UInt64, stamp: UInt64)) {
        if var existing = pending {
            existing.count += 1
            pending = existing
        } else {
            pending = (input.kind, input.received, input.stamp, 1)
            #if canImport(os)
            signposts?.beginInput(kind: input.kind)
            #endif
        }
    }

    /// The display link fired; `target` is its `targetTimestamp` in seconds. The next ``beginFrame()`` takes it.
    func noteTick(target: Double) {
        let now = Self.now()
        var targetNanos: UInt64?
        let nanos = target * 1_000_000_000
        // On our clock only: within a second either side of now (a test's arbitrary timestamp is dropped).
        if nanos.isFinite, nanos > 0, abs(nanos - Double(now)) <= 1_000_000_000 { targetNanos = UInt64(nanos) }
        if let targetNanos {
            if let last = lastTickTarget, targetNanos > last {
                let gap = targetNanos - last
                if gap >= 2_000_000, gap <= 50_000_000 { refreshInterval = min(refreshInterval ?? gap, gap) }
            }
            lastTickTarget = targetNanos
        }
        pendingTick = (now, targetNanos)
    }

    /// The tick that just ran drew nothing (`FP-L`): forget it, so a frame drawn outside a tick (an immediate-input
    /// frame, `FP-M`) does not claim it.
    func discardTick() { pendingTick = nil }

    /// The drawable was acquired (or the platform has none to acquire).
    func stampDrawableAcquired() {
        current?.drawableAcquired = Self.now()
        #if canImport(os)
        signposts?.event("Drawable")
        #endif
    }

    /// A frame starts: takes the pending input.
    func beginFrame() {
        var sample = FrameTimingSample(frameIndex: framesRecorded, start: Self.now())
        if let tick = pendingTick { sample.tickStart = tick.start; sample.tickTarget = tick.target }
        pendingTick = nil
        if let input = pending {
            sample.inputKind = input.kind; sample.inputReceived = input.received
            sample.inputTimestamp = input.stamp; sample.inputCount = input.count
            inFlight = input
            pending = nil
        } else {
            inFlight = nil
        }
        current = sample
        #if canImport(os)
        signposts?.beginFrame(index: sample.frameIndex)
        #endif
    }

    /// The frame did not commit (no drawable, `finishFrame` refused): its input stays pending for the retry.
    func abandonFrame() {
        if let inFlight, pending == nil { pending = inFlight }
        inFlight = nil
        current = nil
        #if canImport(os)
        signposts?.endFrame()
        #endif
    }

    func stampLayoutEnd() {
        current?.layoutEnd = Self.now()
        #if canImport(os)
        signposts?.event("Layout")
        #endif
    }

    func stampPrepaintEnd() {
        current?.prepaintEnd = Self.now()
        #if canImport(os)
        signposts?.event("Prepaint")
        #endif
    }

    func stampPaintEnd() {
        current?.paintEnd = Self.now()
        #if canImport(os)
        signposts?.event("Paint")
        #endif
    }

    /// `finishFrame` returned `true`: stamps the commit and writes the sample into the ring.
    func commitFrame() {
        guard var sample = current else { return }
        sample.commit = Self.now()
        ring[Int(sample.frameIndex % UInt64(capacity))] = sample
        framesRecorded = sample.frameIndex + 1
        current = nil
        inFlight = nil
        #if canImport(os)
        signposts?.endFrame()
        signposts?.endInput()
        #endif
    }

    /// Runs ``onFrame`` for the sample just committed; called at the end of the frame function.
    func deliverFrame() {
        guard let onFrame, let sample = last else { return }
        onFrame(sample)
    }

    private func writeTraceLine(_ sample: FrameTimingSample, interval: UInt64?, phase: UInt64?) {
        guard let traceSink else { return }
        if !traceHeaderWritten { traceHeaderWritten = true; traceSink(Self.traceHeader) }
        if expectsGPUTime, sample.gpuNanos == nil { gpuMissingCount += 1 }
        traceSink(Self.traceLine(for: sample, interval: interval, vsyncPhase: phase))
        traceLinesWritten += 1
    }

    private func flushHeldLines() {
        guard !heldLines.isEmpty else { return }
        let held = heldLines
        heldLines = []
        for line in held { writeTraceLine(line.sample, interval: line.interval, phase: line.phase) }
    }

    /// The renderer reported frame `index`'s GPU time (`FP-P`), in nanoseconds, or `nil` when the GPU failed the
    /// frame. Called on the main actor after the frame was committed, before or after its presentation. Fills the
    /// slot while the ring still holds it; if the frame's trace line was waiting, writes it now.
    func noteGPU(index: UInt64, nanos: UInt64?) {
        let slot = Int(index % UInt64(capacity))
        if index < framesRecorded, ring[slot].frameIndex == index { ring[slot].gpuNanos = nanos }
        if let at = heldLines.firstIndex(where: { $0.sample.frameIndex == index }) {
            // Lines stay ordered: everything older than this one goes first.
            var held = heldLines
            held[at].sample.gpuNanos = nanos
            heldLines = []
            for line in held[...at] { writeTraceLine(line.sample, interval: line.interval, phase: line.phase) }
            heldLines = Array(held[(at + 1)...])
            return
        }
        // Not presented yet: remember that the report came, so the presentation does not wait for it.
        gpuSettled.insert(index)
        if gpuSettled.count > capacity { gpuSettled.removeAll() }
    }

    /// The platform reported frame `index` on screen at `time` (`nil`: dropped). Updates its slot while the ring
    /// still holds it.
    func notePresented(index: UInt64, at time: UInt64?) {
        let slot = Int(index % UInt64(capacity))
        guard index < framesRecorded, ring[slot].frameIndex == index, ring[slot].presented == nil else { return }
        // `FP-M`: a report of 0 (dropped, or macOS giving no time for a windowed layer) still writes the input's
        // line, with `-` for `commit>screen` and `total` and the `est>screen` estimate filled; it also counts as
        // `dropped`. Before, such a run wrote no lines at all.
        if time == nil { droppedCount += 1 } else { ring[slot].presented = time }
        if traceSink != nil {
            flushHeldLines()   // `FP-P`: a line still waiting for its GPU time is written, with `-`, before a later frame's
            if ring[slot].inputKind != nil {
                if expectsGPUTime, ring[slot].gpuNanos == nil, !gpuSettled.contains(index) {
                    heldLines.append((ring[slot], refreshInterval, lastTickTarget))   // written by `noteGPU`
                } else {
                    writeTraceLine(ring[slot], interval: refreshInterval, phase: lastTickTarget)
                }
            } else if time != nil {
                presentedNoInputCount += 1
            }
        }
        gpuSettled.remove(index)
        noteReport()
        guard time != nil else { return }
        #if canImport(os)
        signposts?.event("Present")
        #endif
        onPresented?(ring[slot])
    }
}

#if canImport(os)
/// The `OSSignposter` side of ``FrameTiming`` (ruling `FP-E`): subsystem `com.metalui`, category `Frame`.
/// Intervals `Input→Frame` and `Frame`; events `Layout`, `Prepaint`, `Paint` (each marks the phase's end,
/// inside `Frame`) and `Present`.
@MainActor
final class Signposts {
    private let signposter = OSSignposter(subsystem: "com.metalui", category: "Frame")
    private var inputState: OSSignpostIntervalState?
    private var frameState: OSSignpostIntervalState?

    func beginInput(kind: FrameInputKind) {
        guard inputState == nil else { return }
        inputState = signposter.beginInterval("Input→Frame", id: signposter.makeSignpostID(),
                                              "\(String(describing: kind), privacy: .public)")
    }

    func endInput() {
        guard let inputState else { return }
        signposter.endInterval("Input→Frame", inputState)
        self.inputState = nil
    }

    func beginFrame(index: UInt64) {
        guard frameState == nil else { return }
        frameState = signposter.beginInterval("Frame", id: signposter.makeSignpostID(), "\(index)")
    }

    func endFrame() {
        guard let frameState else { return }
        signposter.endInterval("Frame", frameState)
        self.frameState = nil
    }

    func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
#endif
