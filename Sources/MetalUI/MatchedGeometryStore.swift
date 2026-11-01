import MetalUICore
import MetalUILayout

/// `matchedGeometryEffect`'s bookkeeping, flights and paint maps (round 3 item R3-2, ruling family `MG-`),
/// held by the window's `AnimationStore` beside the ``TransitionStore``.
///
/// **What it tracks, per frame.** Every `matchedGeometryEffect` group claims the position it sits at, with its
/// namespace, id, properties, anchor, `isSource` and the transaction's animation in effect at it, and records
/// its content's nodes. The frame's `afterLayout` (after the transitions') then, for each `(namespace, id)`:
///
/// - **the source** is the last record in tree order with `isSource` (probe P1); every other record of the
///   group is a **follower**, drawn at the source's frame (P2, P3) as `properties` select — with no source
///   nothing is shared (P4);
/// - **the handoff**: a record new this frame (its position was not claimed last frame) takes the frame a
///   **source** record of the same group drew at last frame, when that record's position is no longer claimed
///   (S1, S3, S11) — and not when its leaver is removed at once by an explicit identity transition (S2, S4–S8)
///   nor when the leaver was not a source (S12, S13) — and only under an animation: it starts a **flight** from
///   there to its own frame.
///
/// **Paint only.** The flight and a follower's placement are an affine map from the view's laid-out rectangle
/// to the rectangle it is drawn at, opened as a render-effect scope around the content (`GX-G`); hit testing,
/// focus and accessibility use the laid-out geometry, as an inserting transition's do (`AN-AE` item 5).
///
/// **Why its own store, not the transition store's.** The two share nothing but the position key's shape: a
/// group may sit anywhere, not only as the outermost group of inserted content.
@MainActor
final class MatchedGeometryStore {
    init() {}

    /// A rectangle in engine points, root space.
    struct Rect: Equatable {
        var x, y, w, h: Double

        init(x: Double, y: Double, w: Double, h: Double) { (self.x, self.y, self.w, self.h) = (x, y, w, h) }

        init(_ b: Bounds<Pixels>) {
            self.init(x: Double(b.origin.x.value), y: Double(b.origin.y.value),
                      w: Double(b.size.width.value), h: Double(b.size.height.value))
        }

        static func union(_ a: Rect?, _ b: Rect) -> Rect {
            guard let a else { return b }
            let minX = min(a.x, b.x), minY = min(a.y, b.y)
            return Rect(x: minX, y: minY, w: max(a.x + a.w, b.x + b.w) - minX, h: max(a.y + a.h, b.y + b.h) - minY)
        }

        func lerp(to other: Rect, _ t: Double) -> Rect {
            Rect(x: x + (other.x - x) * t, y: y + (other.y - y) * t,
                 w: w + (other.w - w) * t, h: h + (other.h - h) * t)
        }
    }

    /// What one group declares.
    struct Spec {
        let namespace: Namespace.ID
        let id: AnyHashable
        let properties: MatchedGeometryProperties
        let anchor: UnitPoint
        let isSource: Bool
    }

    private struct GroupKey: Hashable {
        let namespace: Namespace.ID
        let id: AnyHashable
    }

    /// One claimed group this frame (or the last).
    struct Record {
        let spec: Spec
        /// Claim order in this frame: tree order.
        let order: Int
        /// The transaction's animation at the group when it claimed (`AN-AI` item 4's order).
        let animation: Animation?
        /// The ``TransitionStore`` key of the same position: a transition written on the same content records
        /// there.
        let transitionKey: GlobalElementID
        var nodes: [LayoutNodeID] = []
        /// The content's laid-out rectangle.
        var rect: Rect?
        /// Where it is drawn before any flight: its own rectangle, or a followed source's.
        var target: Rect?
        /// Where it was drawn this frame, after any flight (a leaver's last place, and the start of an
        /// interrupting flight).
        var displayed: Rect?
    }

    /// A newcomer's flight: from the rectangle it starts at to its `target`.
    struct Flight {
        let start: Double
        let animation: Animation
        let from: Rect
    }

    private var records: [GlobalElementID: Record] = [:]
    private var previousRecords: [GlobalElementID: Record] = [:]
    private var flights: [GlobalElementID: Flight] = [:]
    private var claimOrder = 0

    /// Flights in progress.
    var liveCount: Int { flights.count }

    /// Claimed groups of the build in progress (`RK-F`): a graft window that moves it cannot be replayed.
    var buildActivity: Int { records.count }

    /// The store key of the group at `cursor` under `parent`.
    static func key(under parent: GlobalElementID?, at cursor: Int) -> GlobalElementID {
        .child(of: .child(of: parent, at: cursor, name: nil), at: 0, name: ElementID("$matched"))
    }

    /// Claims the position for a group; `false` when another group already holds it (two stacked modifiers:
    /// the first, the inner, wins).
    func claim(key: GlobalElementID, spec: Spec, animation: Animation?, transitionKey: GlobalElementID) -> Bool {
        guard records[key] == nil else { return false }
        records[key] = Record(spec: spec, order: claimOrder, animation: animation, transitionKey: transitionKey)
        claimOrder += 1
        return true
    }

    func setNodes(_ nodes: [LayoutNodeID], for key: GlobalElementID) {
        records[key]?.nodes = nodes
    }

    /// The rectangle a view with laid-out rectangle `own` is drawn at when it takes `source`'s as `properties`
    /// select, `anchor` naming the point of each rectangle put on the other's (probe S9, P5: `.position` is
    /// the centre, the size kept; `.size` keeps the centre; MG-D reads the anchor for both).
    static func shown(own: Rect, source: Rect, properties: MatchedGeometryProperties, anchor: UnitPoint) -> Rect {
        let ax = Double(anchor.x), ay = Double(anchor.y)
        let takesPosition = properties.contains(.position), takesSize = properties.contains(.size)
        let size = takesSize ? (w: source.w, h: source.h) : (w: own.w, h: own.h)
        // The point of the shown rectangle at `anchor` is on the source's when position is taken, else on
        // the own rectangle's.
        let pivot = takesPosition ? (x: source.x + ax * source.w, y: source.y + ay * source.h)
                                  : (x: own.x + ax * own.w, y: own.y + ay * own.h)
        return Rect(x: pivot.x - ax * size.w, y: pivot.y - ay * size.h, w: size.w, h: size.h)
    }

    /// Called once per frame after the root layout is computed (after the transitions'): rectangles, sources and
    /// followers, and the handoff into a flight.
    func afterLayout(_ frame: Frame, transitions: TransitionStore) {
        let now = frame.timestamp
        for key in flights.keys where records[key] == nil { flights[key] = nil }
        guard !records.isEmpty else { return }
        for key in Array(records.keys) {
            guard var record = records[key] else { continue }
            record.rect = record.nodes.reduce(nil) { (union: Rect?, node) in Rect.union(union, Rect(frame.bounds(of: node))) }
            records[key] = record
        }
        var sources: [GroupKey: GlobalElementID] = [:]
        for (key, record) in records.sorted(by: { $0.value.order < $1.value.order })
        where record.spec.isSource && record.rect != nil {
            sources[GroupKey(namespace: record.spec.namespace, id: record.spec.id)] = key
        }
        for (key, record) in records {
            guard let own = record.rect else { continue }
            var target = own
            if let sourceKey = sources[GroupKey(namespace: record.spec.namespace, id: record.spec.id)],
               sourceKey != key, let source = records[sourceKey]?.rect {
                target = Self.shown(own: own, source: source, properties: record.spec.properties, anchor: record.spec.anchor)
            }
            records[key]?.target = target
        }
        // The handoff: new records take a source leaver's frame, in tree order, each leaver once.
        var spent: Set<GlobalElementID> = []
        for (key, record) in records.sorted(by: { $0.value.order < $1.value.order })
        where previousRecords[key] == nil && flights[key] == nil {
            guard let animation = record.animation, let own = record.rect, let target = record.target else { continue }
            let group = GroupKey(namespace: record.spec.namespace, id: record.spec.id)
            let leaver = previousRecords
                .filter { leaverKey, old in
                    records[leaverKey] == nil && !spent.contains(leaverKey) && old.spec.isSource
                        && GroupKey(namespace: old.spec.namespace, id: old.spec.id) == group
                        && old.displayed != nil && !transitions.removalWasAnnotatedInstant(old.transitionKey)
                }
                .max { $0.value.order < $1.value.order }
            guard let leaver, let from = leaver.value.displayed else { continue }
            spent.insert(leaver.key)
            let start = Self.shown(own: own, source: from, properties: record.spec.properties, anchor: record.spec.anchor)
            if start != target {
                flights[key] = Flight(start: now, animation: animation, from: start)
            }
        }
    }

    /// The device-pixel map of a claimed group's paint at this frame's timestamp, or `nil` when it is drawn
    /// where it is laid out. Ends a landed flight and keeps the display link awake for a live one.
    func beginPaint(_ key: GlobalElementID, frame: Frame) -> Affine2D? {
        guard let record = records[key], let own = record.rect, let target = record.target else { return nil }
        var shown = target
        if let flight = flights[key] {
            let r = flight.animation.value(at: frame.timestamp - flight.start, from: 0, to: 1, initialVelocity: 0)
            if r.isFinished {
                flights[key] = nil
            } else {
                frame.noteActiveAnimation()
                shown = flight.from.lerp(to: target, r.value)
            }
        }
        records[key]?.displayed = shown
        guard shown != own, own.w > 0, own.h > 0 else { return nil }
        let scale = Double(frame.scaleFactor)
        let offset = frame.activeOffset
        let ox = (own.x + Double(offset.x.value)) * scale, oy = (own.y + Double(offset.y.value)) * scale
        let sx = shown.w / own.w, sy = shown.h / own.h
        let dx = (shown.x + Double(offset.x.value)) * scale, dy = (shown.y + Double(offset.y.value)) * scale
        return Affine2D(a: sx, d: sy, tx: dx - sx * ox, ty: dy - sy * oy)
    }

    struct Checkpoint { let flights: [GlobalElementID: Flight] }

    func checkpoint() -> Checkpoint { Checkpoint(flights: flights) }

    /// Forgets the build in progress (`RK-M`): this frame's claims are empty at a build's start and the flights
    /// return to what they were before `afterLayout` advanced them.
    func rollbackBuild(_ saved: Checkpoint) {
        records.removeAll(keepingCapacity: true)
        claimOrder = 0
        flights = saved.flights
    }

    /// Called once per frame at its end: this frame's records become the last completed frame's.
    func endFrame() {
        swap(&records, &previousRecords)
        records.removeAll(keepingCapacity: true)
        claimOrder = 0
    }
}
