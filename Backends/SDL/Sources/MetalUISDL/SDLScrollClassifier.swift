// SDL gives a wheel event no device class and no phase (ruling `TP-A`), so MetalUI infers both from the
// granularity of the delta and the time between events (rulings `TP-B`, `TP-C`, `TP-F`). Pure: time is a
// parameter, nothing sleeps, nothing here touches SDL.
#if SDL
import MetalUIPlatform

/// Classifies SDL wheel events as a wheel notch or a precise (trackpad) stream, and numbers a stream's phases.
///
/// An event is **fractional** when an axis is not a whole number (`|v - v.rounded()| > 1e-4`, finite values
/// only). A fractional event opens a stream, and every event in the next 0.15 s, whole or not, continues it
/// (`isPrecise`, sticky); a whole event with no open stream is a wheel. Any event arriving at or after the open
/// stream's deadline reports it `closedStale` first, so the window delivers the old stream's `.ended` before
/// the event (ruling `TP-M`).
struct SDLScrollClassifier {
    /// Seconds with no event after which a stream is over (ruling `TP-C`: a ruling, unmeasured).
    static let quietInterval = 0.15
    /// An axis is fractional beyond this distance from the nearest whole number (ruling `TP-B`).
    static let fractionTolerance: Float = 1e-4

    struct Result: Equatable {
        /// The event belongs to a precise stream.
        var isPrecise: Bool
        /// `.began` for a stream's first event, `.changed` for the rest, `.none` for a wheel.
        var phase: InputPhase
        /// The stream open before this event is over: deliver its `.ended` first.
        var closedStale: Bool
    }

    var mode: SDLScrollPrecision
    /// When the open stream ends, or `nil` with none.
    private(set) var deadline: Double?

    init(mode: SDLScrollPrecision = .automatic) { self.mode = mode }

    private static func isFractional(_ v: Float) -> Bool {
        abs(v - v.rounded()) > fractionTolerance   // NaN and infinity compare false: not fractional
    }

    mutating func classify(dx: Float, dy: Float, at now: Double) -> Result {
        guard mode == .automatic else { return Result(isPrecise: false, phase: .none, closedStale: false) }
        var stale = false
        if let deadline, now >= deadline {
            stale = true
            self.deadline = nil
        }
        let open = deadline != nil
        guard open || Self.isFractional(dx) || Self.isFractional(dy) else {
            return Result(isPrecise: false, phase: .none, closedStale: stale)
        }
        deadline = now + Self.quietInterval
        return Result(isPrecise: true, phase: open ? .changed : .began, closedStale: stale)
    }

    /// Ends the open stream when `now` has reached its deadline; `true` exactly once per stream.
    mutating func expire(at now: Double) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self.deadline = nil
        return true
    }

    /// Drops the stream with no end (focus loss, close; ruling `TP-F`).
    mutating func reset() { deadline = nil }
}
#endif
