import MetalUICore
import MetalUIPlatform

// Wheel latching and the guaranteed terminal scroll phase (input follow-ups,
// rulings `IF-G`, `IF-H`, `IF-M`; spec
// `docs/superpowers/specs/2026-10-10-input-followups-design.md` lane 2).
// MetalUI's own design: `.onScrollWheel` is MetalUI-only, so there is no
// SwiftUI behaviour to diverge from. The dispatch is `Window.applyScroll`.

/// Where a trackpad scroll that has begun is going: the cover of the lookup at
/// its `.began`, and which stage of the scroll is still in flight. One stored
/// optional on `Window`; plain data, no closures.
struct ScrollLatch {
    /// The cover's identity (`applyScroll`'s cover at the `.began`).
    var cover: GlobalElementID
    /// The cover's hit layer.
    var layer: Int
    /// From `.began` until the finger stage's `.ended`/`.cancelled`.
    var fingerInFlight: Bool
    /// From the first momentum event until its `.ended`/`.cancelled`.
    var momentumInFlight: Bool
    /// The last event seen (position, modifiers, precision and timestamp are
    /// what a synthesized terminal event repeats).
    var last: ScrollEvent

    /// The latch a `.began` at `cover` creates.
    init(cover: Hitbox, event: ScrollEvent) {
        self.cover = cover.id
        self.layer = cover.layer
        self.fingerInFlight = true
        self.momentumInFlight = false
        self.last = event
    }

    /// Whether `event` is one the latch dispatches (`IF-G` item 2): a
    /// `.changed`/`.ended`/`.cancelled` phase, or any momentum phase. A
    /// `.began` replaces the latch; a `.mayBegin` and a phaseless event never
    /// consult it.
    static func isGestureEvent(_ event: ScrollEvent) -> Bool {
        switch event.phase {
        case .changed, .ended, .cancelled: return true
        default: return event.momentumPhase != .none
        }
    }

    /// Advances the in-flight stages with `event` (already dispatched).
    /// Returns `false` when the latch is over (momentum ended or cancelled).
    mutating func advance(with event: ScrollEvent) -> Bool {
        last = event
        switch event.momentumPhase {
        case .began, .changed, .mayBegin:
            fingerInFlight = false
            momentumInFlight = true
        case .ended, .cancelled:
            return false
        case .none:
            switch event.phase {
            case .changed: fingerInFlight = true
            case .ended, .cancelled: fingerInFlight = false
            default: break
            }
        }
        return true
    }

    /// The terminal event to synthesize (`IF-H`), `nil` when no stage is in
    /// flight: delta zero, `.cancelled` in the stage under way.
    var terminalEvent: ScrollEvent? {
        guard fingerInFlight || momentumInFlight else { return nil }
        var event = last
        event.delta = Point(x: Pixels(0), y: Pixels(0))
        event.phase = momentumInFlight ? .none : .cancelled
        event.momentumPhase = momentumInFlight ? .cancelled : .none
        return event
    }
}
