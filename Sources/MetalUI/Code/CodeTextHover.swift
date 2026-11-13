import MetalUICodeBuffer
import MetalUICore
import MetalUILayout

/// Where a hover over a ``CodeView``'s text is (`CV-AS`, Alloy G35 F): see ``CodeView/onTextHover(delay:perform:)``.
/// MetalUI-only (class `M`, no divergence).
public enum CodeHoverPhase: Equatable, Sendable {
    /// The pointer rested on text for the delay: reported once per hover, with what is under it.
    case active(CodeHit)
    /// While active, the pointer moved onto other text: reported at once, with what is under it now.
    case moved(CodeHit)
    /// The hover ended: the pointer left the text or the view, or a press, a key, typed text, an edit or a wheel
    /// scroll ended it. Reported only after an ``active(_:)``.
    case ended
}

/// What ``CodeView/onTextHover(delay:perform:)`` stores: the delay in seconds and the callback.
struct CodeTextHover {
    let delay: Double
    let perform: @MainActor (CodeHoverPhase) -> Void

    /// How long a hover is held after the pointer leaves the text while a text-anchored presentation of the view is
    /// open (`CV-AS`), so the pointer can travel to the popover; seconds.
    static let grace = 0.15
}

/// The hover's bookkeeping in ``CodeViewState`` (`CV-AS`). Written from input when the hovered grapheme changes and
/// by prepaint (compared) to stamp a timer and to fire the delay or the grace: a view with no handler never writes it.
struct CodeHoverTrack: Equatable {
    enum Phase: UInt8 {
        /// No hover.
        case idle
        /// The pointer rests on `over`; the delay runs from `timerStart`.
        case pending
        /// `.active` was reported; the pointer is on text.
        case active
        /// The pointer left the text while a presentation was open: `.ended` is held for the grace, or while the
        /// pointer is in the presentation's panel.
        case holding
    }

    var phase = Phase.idle
    /// The grapheme under the pointer, UTF-8 bytes.
    var over: Range<Int>?
    /// The pointer in bounds space (what the plan hits in).
    var pointX = 0.0
    var pointY = 0.0
    /// The frame time the delay or the grace runs from; `nil` until the next prepaint stamps it (input has no clock).
    var timerStart: Double?
    /// Whether the pointer is in the open presentation's panel.
    var inPanel = false
    /// The buffer's version when the hover began: an edit ends it.
    var version: UInt64 = 0
    /// While idle: the grapheme a hover was ended on by a press, a key, a wheel or a dismissal, which does not start
    /// another by resting on it again; moving to another grapheme or off the text clears it.
    var suppressed: Range<Int>?
}

/// The input side of a view's text hover: the pointer and the panel's hover callbacks and every hard end, over the
/// plan of the frame they were registered in. Built in prepaint only for a view with a handler.
@MainActor
final class CodeTextHoverRuntime {
    let id: GlobalElementID
    let table: StateTable
    let plan: CodeViewPlan
    let origin: Point<Pixels>
    let buffer: CodeBuffer
    let perform: @MainActor (CodeHoverPhase) -> Void
    weak var box: CodeTextAnchorBox?

    init(id: GlobalElementID, table: StateTable, plan: CodeViewPlan, origin: Point<Pixels>, buffer: CodeBuffer,
         perform: @escaping @MainActor (CodeHoverPhase) -> Void, box: CodeTextAnchorBox?) {
        self.id = id
        self.table = table
        self.plan = plan
        self.origin = origin
        self.buffer = buffer
        self.perform = perform
        self.box = box
    }

    private func track() -> CodeHoverTrack {
        table.readState(id, initial: CodeViewState()).hover   // a read, not a write (`RW-J`)
    }

    private func update(_ body: (inout CodeHoverTrack) -> Void) {
        table.withState(id, initial: CodeViewState()) { body(&$0.hover) }
    }

    /// The view's hover callback (view-local points, `.local`).
    func pointer(_ phase: HoverPhase) {
        guard case .active(let local) = phase else {
            leave()
            return
        }
        let point = Point(x: local.x + origin.x, y: local.y + origin.y)
        let hit = plan.hit(at: point)
        guard hit.region == .text, let character = hit.character else {
            leave()
            return
        }
        let current = track()
        let changed = current.over != character
        switch current.phase {
        case .idle:
            if current.suppressed == character { return }
            let version = buffer.version
            update {
                $0 = CodeHoverTrack(phase: .pending, over: character, pointX: Double(point.x.value),
                                    pointY: Double(point.y.value), timerStart: nil, inPanel: false, version: version)
            }
        case .pending:
            guard changed else { return }   // the same grapheme: the delay keeps running
            update {
                $0.over = character
                $0.pointX = Double(point.x.value)
                $0.pointY = Double(point.y.value)
                $0.timerStart = nil
            }
        case .active, .holding:
            guard changed || current.phase == .holding else { return }
            update {
                $0.phase = .active
                $0.over = character
                $0.pointX = Double(point.x.value)
                $0.pointY = Double(point.y.value)
                $0.timerStart = nil
                $0.inPanel = false
            }
            if changed { perform(.moved(hit)) }
        }
    }

    /// The pointer left the text, or the view (or was covered by the panel).
    private func leave() {
        let current = track()
        switch current.phase {
        case .holding:
            return
        case .idle:
            if current.suppressed != nil { update { $0.suppressed = nil } }
        case .pending:
            update { $0 = CodeHoverTrack() }
        case .active:
            if box?.isPresented == true {
                update { $0.phase = .holding; $0.timerStart = nil }
            } else {
                update { $0 = CodeHoverTrack() }
                perform(.ended)
            }
        }
    }

    /// The pointer entered or left the open presentation's panel.
    func panel(_ inside: Bool) {
        let current = track()
        guard current.phase == .active || current.phase == .holding, current.inPanel != inside else { return }
        update {
            $0.inPanel = inside
            if !inside { $0.timerStart = nil }
        }
    }

    /// Ends the hover now whatever the grace: a press, a key, typed text, a wheel, a dismissal.
    func hardEnd() {
        let current = track()
        switch current.phase {
        case .idle:
            return
        case .pending:
            update { $0 = CodeHoverTrack(suppressed: current.over) }
        case .active, .holding:
            update { $0 = CodeHoverTrack(suppressed: current.over) }
            perform(.ended)
        }
    }
}

extension CodeView {
    /// Calls `perform` while the pointer hovers text (`CV-AS`, Alloy G35 F): `.active(hit)` once after it has rested over
    /// the text of a buffer row (``CodeHit/region`` `.text`, a grapheme under it) for `delay`; while active,
    /// `.moved(hit)` at once whenever it moves onto another grapheme (the app decides whether to ask again); and
    /// `.ended` when the hover ends. Moving to another grapheme before the delay is up restarts the delay and reports
    /// nothing.
    ///
    /// **A hover ends** when the pointer leaves the text (past a line's end, the gutter, a virtual row) or the view,
    /// on a press, on a key or typed text the view receives, on an insert or any edit of the buffer, and on a wheel
    /// scroll. **Grace:** when the pointer leaves the text while a text-anchored presentation of this view
    /// (``CodeView/popover(isPresented:attachmentAnchor:arrowEdge:content:)``) is open, `.ended` is held for 150 ms,
    /// and while the pointer is inside the presentation (it can be selected and scrolled) and for 150 ms after it
    /// leaves; the pointer back on text goes on with `.moved` (or nothing, on the same grapheme). A press outside, a
    /// key, an edit, Escape and any other dismissal end it at once. Without such a presentation, leaving ends at once.
    ///
    /// The delay costs no display link: the view asks for one frame at its end (`CV-AC`'s deadline), and `perform`
    /// runs after that frame, outside every phase, so it may write state (as `onScroll`'s does); `.moved` and
    /// `.ended` run from input. A view with no handler does none of this. The view's own
    /// ``StyledElement/onContinuousHover(coordinateSpace:perform:)`` keeps running beside it when it is `.local`.
    public func onTextHover(delay: Duration = .milliseconds(500),
                            perform: @escaping @MainActor (CodeHoverPhase) -> Void) -> CodeView {
        var copy = self
        let parts = delay.components
        copy.textHover = CodeTextHover(delay: max(0, Double(parts.seconds) + Double(parts.attoseconds) / 1e18), perform: perform)
        return copy
    }

    /// Advances the hover's timers for this frame (`CV-AS`): stamps a timer input started, fires `.active` or the held
    /// `.ended` when due (through the lifecycle queue, outside every phase), ends a hover an edit outdated, and asks
    /// the timeline store for a frame at the next due time. A hover that is not idle keeps retained replay off, so the
    /// input closures it registered are this frame's.
    @MainActor
    func advanceTextHover(_ track: inout CodeHoverTrack, _ hover: CodeTextHover, id: GlobalElementID,
                          plan: CodeViewPlan, frame: Frame) {
        guard track.phase != .idle else { return }
        frame.taintRetention("codeTextHover")
        let perform = hover.perform
        func report(_ phase: CodeHoverPhase) {
            frame.animationStore.lifecycle.enqueue(LifecycleEvent(owner: id, action: {
                MainActor.assumeIsolated { perform(phase) }
            }, departed: nil))
        }
        if track.version != buffer.version {   // an edit ends it
            let was = track.phase
            track = CodeHoverTrack()
            if was == .active || was == .holding { report(.ended) }
            return
        }
        let now = frame.timestamp
        switch track.phase {
        case .idle, .active:
            return
        case .pending:
            let start = track.timerStart ?? now
            track.timerStart = start
            let due = start + hover.delay
            if now < due {
                frame.animationStore.timeline.noteDeadline(atTimestamp: due, owner: id, stateTable: frame.stateTable)
                return
            }
            let hit = plan.hit(at: Point(x: Pixels(Float(track.pointX)), y: Pixels(Float(track.pointY))))
            if hit.region == .text, let character = hit.character {
                track.phase = .active
                track.over = character
                report(.active(hit))
            } else {
                track = CodeHoverTrack()
            }
        case .holding:
            if track.inPanel { return }
            let start = track.timerStart ?? now
            track.timerStart = start
            let due = start + CodeTextHover.grace
            if now < due {
                frame.animationStore.timeline.noteDeadline(atTimestamp: due, owner: id, stateTable: frame.stateTable)
                return
            }
            track = CodeHoverTrack()
            report(.ended)
        }
    }
}
