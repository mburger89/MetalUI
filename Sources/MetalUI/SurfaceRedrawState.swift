import Foundation
import MetalUICore
import MetalUIPlatform
import MetalUIScene

/// A window's surface-scoped redraw bookkeeping (`TRM-P`…`TRM-R`): the last presented frame's surface requests,
/// which surfaces a ``SurfaceRedrawTrigger`` invalidated, the timed requests, and what the last frame was drawn
/// at, so `Window.drawFrameIfNeeded` can re-encode `lastScene` and run only the invalidated draws.
///
/// **Window-owned, one per window**, beside `SurfaceRegistry`. Not a `StateTable` entry. A window with no
/// trigger-driven surface holds empty collections here and pays one empty-set check per tick.
@MainActor
final class SurfaceRedrawState {
    private struct Bound {
        let id: SurfaceID
        let trigger: SurfaceRedrawTrigger
    }

    /// The last presented full frame's requests, in paint order — what a surface-only frame draws from.
    private(set) var lastRequests: [SurfaceDrawRequest] = []
    private var bound: [Bound] = []
    /// Surfaces a trigger invalidated since the last frame that drew them.
    private(set) var pending: Set<SurfaceID> = []
    /// Timed requests, by surface (`TRM-R`).
    private(set) var deadlines: [SurfaceID: Date] = [:]

    /// What the last full frame was presented at (`TRM-P` item 4): a surface-only frame reuses its scene only
    /// while none of these moved.
    private var presented: (scale: Float, contentSize: Size<Pixels>, resizes: Int, atlasGeneration: Int)?

    /// Surface-only frames presented, over the window's life.
    private(set) var surfaceOnlyFrames = 0
    /// Whether the frame being handed to the renderer is a surface-only one — read by the test harness.
    private(set) var isPresentingSurfaceOnly = false

    /// The frame clock's now (`TW-A`): set by the window.
    var now: () -> Date = { Date() }
    /// Whether the clock is the harness's simulated one: no wake is scheduled, the display-link tick fires due
    /// deadlines (`DX-A`'s shape).
    var isSimulated = false
    /// Schedules `fire` at a date and answers how to cancel it; tests never reach it.
    var scheduler: TimelineStore.Scheduler = TimelineStore.taskScheduler
    private var scheduled: (date: Date, cancel: () -> Void)?
    /// Called when a request needs the display link running: the window unpauses it.
    var wakeLink: () -> Void = {}

    /// Whether a surface-only frame is owed.
    var hasPending: Bool { !pending.isEmpty }
    /// The timed requests outstanding — test observability.
    var deadlineCount: Int { deadlines.count }
    /// The date the next timed request fires at — test observability.
    var nextDeadline: Date? { deadlines.values.min() }

    // MARK: requests

    /// A trigger's request for `id`, on the main actor: immediate marks it pending; a delay joins the surface's
    /// deadline, the earlier winning. (A trigger is bound only to a surface the last frame painted, so this is
    /// never called for another; a pending id that left is dropped by ``surfaceOnlyRequests(at:)``.)
    func note(_ request: SurfaceRedrawTrigger.Pending, for id: SurfaceID) {
        if request.immediate { pending.insert(id) }
        if let delay = request.after {
            let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
            let date = now().addingTimeInterval(max(0, seconds))
            if let known = deadlines[id], known <= date {} else { deadlines[id] = date }
            reschedule()
        }
        wakeLink()
    }

    /// Moves every deadline `date` has reached into `pending`; answers whether any did.
    @discardableResult
    func fireDue(at date: Date) -> Bool {
        var fired = false
        for (id, due) in deadlines where due <= date {
            deadlines[id] = nil
            pending.insert(id)
            fired = true
        }
        if fired { reschedule() }
        return fired
    }

    private func reschedule() {
        guard !isSimulated else { return }
        guard let earliest = deadlines.values.min() else {
            scheduled?.cancel()
            scheduled = nil
            return
        }
        if let scheduled, scheduled.date == earliest { return }
        scheduled?.cancel()
        let cancel = scheduler(earliest) { [weak self] in
            guard let self else { return }
            self.scheduled = nil
            if self.fireDue(at: Date()) || !self.deadlines.isEmpty { self.wakeLink() }
            self.reschedule()
        }
        scheduled = (earliest, cancel)
    }

    // MARK: frames

    /// The frame's requests with every pending surface forced (`TRM-P` item 3); the array itself when nothing
    /// is pending.
    func forcing(_ requests: [SurfaceDrawRequest], at time: Double) -> [SurfaceDrawRequest] {
        forcedByFullFrame = pending
        guard !pending.isEmpty else { return requests }
        return requests.map { pending.contains($0.target.id) ? $0.forced(at: time) : $0 }
    }

    /// The surfaces the full frame being presented forces.
    private var forcedByFullFrame: Set<SurfaceID> = []

    /// Whether the last presented frame's scene may be re-encoded as it is (`TRM-P` item 4): a frame was
    /// presented, and the scale, the content size, the resize count and the atlas layout are what it was.
    func canReuseScene(scale: Float, contentSize: Size<Pixels>, resizes: Int, atlas: GlyphAtlas) -> Bool {
        guard let presented, !atlas.wantsReclaim else { return false }
        return presented.scale == scale && presented.contentSize == contentSize
            && presented.resizes == resizes && presented.atlasGeneration == atlas.layoutGeneration
    }

    /// The pending surfaces' requests, forced at `time`, in paint order. Drops pending ids the last frame did
    /// not paint.
    func surfaceOnlyRequests(at time: Double) -> [SurfaceDrawRequest] {
        let requests = lastRequests.filter { pending.contains($0.target.id) }.map { $0.forced(at: time) }
        if requests.count != pending.count { pending = Set(requests.map(\.target.id)) }
        return requests
    }

    /// Marks the frame handed to the renderer as surface-only for the harness's per-frame record.
    func presenting(surfaceOnly: Bool) { isPresentingSurfaceOnly = surfaceOnly }

    /// A surface-only frame was presented: what it drew is no longer pending.
    func didPresentSurfaceOnly(_ drawn: [SurfaceDrawRequest]) {
        for request in drawn { pending.remove(request.target.id) }
        surfaceOnlyFrames += 1
    }

    /// A full frame was presented (`TRM-P` item 5): the requests it handed over (every pending surface it painted
    /// was forced), the triggers of the surfaces it painted rebound and the rest unbound, and the deadlines of
    /// surfaces it did not paint dropped.
    func didPresentFullFrame(requests: [SurfaceDrawRequest], triggers: [(SurfaceID, SurfaceRedrawTrigger)],
                             scale: Float, contentSize: Size<Pixels>, resizes: Int, atlas: GlyphAtlas,
                             hop: @escaping @Sendable (SurfaceRedrawTrigger, SurfaceID) -> Void) {
        lastRequests = requests
        presented = (scale, contentSize, resizes, atlas.layoutGeneration)
        let painted = Set(requests.map(\.target.id))
        pending.subtract(forcedByFullFrame)   // drawn (or not painted, so gone); a request made since stays
        if !deadlines.isEmpty {
            deadlines = deadlines.filter { painted.contains($0.key) }
            reschedule()
        }
        let keep = Set(triggers.map { ObjectIdentifier($0.1) })
        for old in bound where !keep.contains(ObjectIdentifier(old.trigger)) { old.trigger.unbind() }
        bound = triggers.map { Bound(id: $0.0, trigger: $0.1) }
        for entry in bound {
            let trigger = entry.trigger, id = entry.id
            trigger.bind { hop(trigger, id) }
        }
    }
}
