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
    /// The frame function started drawing (before the platform's drawable is acquired, so a stalled
    /// `nextDrawable()` shows as the gap before ``layoutEnd``).
    public var buildStart: UInt64
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

    /// A sample whose phases all read `start`; the window stamps the rest.
    package init(frameIndex: UInt64, start: UInt64) {
        self.frameIndex = frameIndex
        inputKind = nil; inputTimestamp = nil; inputReceived = nil; inputCount = 0
        buildStart = start; layoutEnd = start; prepaintEnd = start; paintEnd = start; commit = start
        presented = nil
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
        guard let value = getenv("METALUI_SIGNPOSTS"), String(cString: value) == "1" else { return nil }
        return FrameTiming(emitsSignposts: true)
    }

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
        defer { candidate = nil }
        guard dirtied, let candidate else { return }
        if var existing = pending {
            existing.count += 1
            pending = existing
        } else {
            pending = (candidate.kind, candidate.received, candidate.stamp, 1)
            #if canImport(os)
            signposts?.beginInput(kind: candidate.kind)
            #endif
        }
    }

    /// A frame starts: takes the pending input.
    func beginFrame() {
        var sample = FrameTimingSample(frameIndex: framesRecorded, start: Self.now())
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

    /// The platform reported frame `index` on screen at `time` (`nil`: dropped). Updates its slot while the ring
    /// still holds it.
    func notePresented(index: UInt64, at time: UInt64?) {
        let slot = Int(index % UInt64(capacity))
        guard index < framesRecorded, ring[slot].frameIndex == index, ring[slot].presented == nil, let time else {
            return
        }
        ring[slot].presented = time
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
