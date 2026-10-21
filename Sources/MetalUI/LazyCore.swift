import MetalUICore
import MetalUILayout

// Lazy containers, the shared core (item L1, rulings `LZ-C`, `LZ-E`, `LZ-G`, `LZ-O`; spec 3.2).
//
// **Lines.** A lazy stack's line is one unit; a lazy grid's line is a row (lane 2). The planner
// mirrors `List.variableWindow`, `rebuildKeepingAnchor` and `prepaintVariableRows` step for step
// (`VL-E` to `VL-H`, `VL-O`, `VL-P`) over the SAME `RowExtentIndex` (a class, unchanged; the id of
// a line is its first unit's key) and does not edit `List.swift` (`LZ-C`: List windowing, `TB-AH`
// and the `VL-` pins must not move in this item). Two copies of the anchor arithmetic is the
// named cost; a fix to one must be made in the other.

/// The window's constants.
enum LazyWindow {
    /// `List.overscan`'s value: lines realised beyond the viewport on each side (divergence 637).
    static let overscan = 2
    /// Lines a cold frame (a scroller whose viewport is not yet known) realises (`LZ-E`).
    static let coldLines = 32
}

/// What a frame's lazy containers did (`LZ-I`): counted per build, never timed.
struct LazyWork: Equatable {
    /// Units realised.
    var unitsRealized = 0
    /// Lines realised (a stack's units, a grid's rows).
    var linesRealized = 0
    /// Containers that realised everything: no scroller, the other axis, a `Deferred`, an eager member.
    var unbounded = 0
}

/// A lazy container's origin within its scroller's content, in points along the scrolling axis,
/// last frame's measurement, stored at the container's own id (`DD-F` item 1's twin: a separate
/// type so `ListOrigin` does not move).
struct LazyOrigin: @unchecked Sendable {
    var offset: Double = 0
    /// The container's extent across the scrolling axis last frame (lane 2's column count input).
    var crossExtent: Double = 0
    /// The `RowExtentIndex<AnyHashable>`, held as `AnyObject` because this type is not generic.
    var extents: AnyObject?

    /// Whether two entries are the same value (`RW-I`): offsets by value, the index by identity.
    static func sameEntry(_ a: LazyOrigin, _ b: LazyOrigin) -> Bool {
        a.offset == b.offset && a.crossExtent == b.crossExtent && a.extents === b.extents
    }
}

/// How a container's window was decided.
enum LazyPlanMode {
    /// A scroller on the container's axis with a known viewport: viewport plus overscan.
    case bounded
    /// A scroller on the container's axis whose viewport is not yet known: the first `coldLines`.
    case cold
    /// No scroller, the other axis, a `Deferred`: every line.
    case unbounded
}

/// `scrollTo`'s refinement key, carried to the next frame by the container that resolved a request
/// against an estimate (`VL-P`'s `ListLeadReveal`, for a lazy container).
struct LazyReveal: Hashable {
    let container: GlobalElementID
    let key: AnyHashable
}

/// A window decision.
struct LazyLinePlan {
    var mode: LazyPlanMode
    /// The lines to realise.
    var window: Range<Int>
    /// The line the window is anchored to and its offset from the content's top, as the index stood.
    var anchorLine: Int
    var anchorOffset: Double
    /// The extent after the window (lines not realised), `VL-` `trailingExtent`.
    var trailing: Double
    /// The index (stored, or fresh for prepaint to store); `nil` when unbounded with none.
    var index: RowExtentIndex<AnyHashable>?
    /// The anchor `(line, y)` prepaint corrects against; `nil` when unbounded or empty.
    var anchor: (index: Int, y: Double)?
}

@MainActor
enum LazyLinePlanner {
    /// `variableWindow` over lines (spec 3.2).
    ///
    /// **Unbounded**: every line, no anchor; a stored index whose count differs is rebuilt by key
    /// first so prepaint's records land at the right indices. **Cold**: the first `coldLines`, from
    /// a fresh or stored index so the extent after them is known. **Bounded**: the anchor is the
    /// line holding `top` (the scroller's offset minus the container's origin, clamped), the window
    /// anchor - overscan ..< the line holding the viewport's bottom + 1 + overscan; a data change
    /// rebuilds the index by key (once, the window recomputed) and the anchor follows its key,
    /// placed at its OLD offset (`VL-G` item 3, `VL-O`).
    static func plan(lineCount count: Int, key: (Int) -> AnyHashable, stored: LazyOrigin?, origin: Double,
                     context: ScrollContext?, axis: ScrollAxis) -> LazyLinePlan {
        let storedIndex = stored?.extents as? RowExtentIndex<AnyHashable>
        guard let context, context.axis == axis else {
            if let storedIndex, storedIndex.count != count { storedIndex.rebuild(ids: (0..<count).lazy.map(key)) }
            return LazyLinePlan(mode: .unbounded, window: 0..<count, anchorLine: 0, anchorOffset: 0,
                                trailing: 0, index: storedIndex, anchor: nil)
        }
        let index = storedIndex ?? RowExtentIndex(count: count, declaredEstimate: nil)
        guard context.viewportExtent > 0 else {
            if index.count != count { index.rebuild(ids: (0..<count).lazy.map(key)) }
            let window = 0..<Swift.min(LazyWindow.coldLines, count)
            return LazyLinePlan(mode: .cold, window: window, anchorLine: 0, anchorOffset: 0,
                                trailing: index.totalExtent - index.offset(of: window.upperBound), index: index,
                                anchor: count > 0 ? (0, 0) : nil)
        }
        let viewport = context.viewportExtent
        var total = index.totalExtent
        let top = Swift.min(Swift.max(0, context.offset - origin), Swift.max(0, total - viewport))
        var anchorIndex = index.index(containing: top)
        let anchorY = index.offset(of: anchorIndex)
        // After a rebuild the anchor sits at `anchorY` while the index puts it at
        // `offset(of: anchorIndex)`; the window is found `shift` further on.
        var shift = 0.0
        var rebuilt = false
        func rebuild() {
            anchorIndex = rebuildKeepingAnchor(index, oldAnchor: anchorIndex, count: count, key: key)
            shift = index.offset(of: anchorIndex) - anchorY
            total = index.totalExtent
            rebuilt = true
        }
        func window() -> Range<Int> {
            let first = Swift.min(Swift.max(0, anchorIndex - LazyWindow.overscan), count)
            let last = Swift.min(Swift.max(first, index.index(containing: top + shift + viewport) + 1
                                           + LazyWindow.overscan), count)
            return first..<last
        }
        if index.count != count { rebuild() }
        var built = window()
        if !rebuilt && realisedKeysDiffer(index, in: built, key: key) {
            rebuild()
            built = window()
        }
        let trailing = total - index.offset(of: built.upperBound)
        return LazyLinePlan(mode: .bounded, window: built, anchorLine: anchorIndex, anchorOffset: anchorY,
                            trailing: trailing, index: index, anchor: count > 0 ? (anchorIndex, anchorY) : nil)
    }

    /// Whether a line about to be realised carries a key other than the one recorded at its index
    /// (`VL-E` item 3's second detection), `O(window)`.
    private static func realisedKeysDiffer(_ index: RowExtentIndex<AnyHashable>, in window: Range<Int>,
                                           key: (Int) -> AnyHashable) -> Bool {
        for position in window {
            if let recorded = index.id(at: position), recorded != key(position) { return true }
        }
        return false
    }

    /// Rebuilds `index` for the current keys and returns where the anchor went (`VL-G` item 3,
    /// `VL-O` item 1): the old anchor's key at its new index; if gone, the first key recorded after
    /// the old anchor that is still present, else the last one before it that is, else
    /// `min(oldAnchor, count - 1)`. `O(n)`, as the rebuild is.
    private static func rebuildKeepingAnchor(_ index: RowExtentIndex<AnyHashable>, oldAnchor: Int, count: Int,
                                             key: (Int) -> AnyHashable) -> Int {
        let oldIDs = (0..<index.count).map { index.id(at: $0) }
        let lookup = index.rebuild(ids: (0..<count).lazy.map(key))
        func present(_ position: Int) -> Int? {
            guard let id = oldIDs[position] else { return nil }
            return lookup[id]
        }
        if oldIDs.indices.contains(oldAnchor), let found = present(oldAnchor) { return found }
        if oldAnchor + 1 < oldIDs.count {
            for position in (oldAnchor + 1)..<oldIDs.count {
                if let found = present(position) { return found }
            }
        }
        var position = Swift.min(oldAnchor - 1, oldIDs.count - 1)
        while position >= 0 {
            if let found = present(position) { return found }
            position -= 1
        }
        return Swift.max(0, Swift.min(oldAnchor, index.count - 1))
    }

    /// `prepaintVariableRows` over lines (spec 3.2, in this order): inside a scroller on the
    /// container's axis, store the origin and the index (created now if the entry holds none, only
    /// here, through `withState`, never `write`: no `isDirty`), forget every extent when the cross
    /// extent changed, record each realised line's extent under its key; then the anchor
    /// correction (`VL-G` item 2); then staleness (one more frame when the window the updated
    /// index gives is not contained in the built one). Returns the index and the adjustment for
    /// `scrollTo`'s resolution.
    static func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, axis: ScrollAxis, lineCount count: Int,
                         made: RowExtentIndex<AnyHashable>?, key: (Int) -> AnyHashable,
                         realised: [(line: Int, extent: Double)], builtWindow: Range<Int>, builtCold: Bool,
                         anchor: (index: Int, y: Double)?, pass: PrepaintPass)
        -> (index: RowExtentIndex<AnyHashable>?, adjustment: Double) {
        guard let scroller = pass.frame.activeScrollerFrame, scroller.axis == axis else { return (nil, 0) }
        let vertical = axis == .vertical
        let origin = Double(vertical ? bounds.origin.y.value - scroller.contentOrigin.y.value
                                     : bounds.origin.x.value - scroller.contentOrigin.x.value)
        let cross = Double(vertical ? bounds.size.width.value : bounds.size.height.value)
        var held: RowExtentIndex<AnyHashable>?
        pass.withState(id, initial: LazyOrigin(), unchanged: LazyOrigin.sameEntry) { entry in   // `RW-I`
            entry.offset = origin
            entry.crossExtent = cross
            if let existing = entry.extents as? RowExtentIndex<AnyHashable> {
                held = existing
            } else {
                let fresh = made ?? RowExtentIndex(count: count, declaredEstimate: nil)
                entry.extents = fresh
                held = fresh
            }
        }
        guard let extents = held else { return (nil, 0) }
        if extents.count != count { extents.rebuild(ids: (0..<count).lazy.map(key)) }
        if extents.width != cross { extents.forgetMeasurements(width: cross) }
        for line in realised { extents.record(line.extent, at: line.line, id: key(line.line)) }
        var adjustment = 0.0
        if let anchor {
            adjustment = extents.offset(of: anchor.index) - anchor.y
            pass.frame.noteScrollAnchorAdjustment(scroller: scroller.scrollerID, delta: adjustment)
        }
        let fresh: Range<Int>
        if scroller.viewportExtent > 0 {
            let viewport = scroller.viewportExtent
            let top = Swift.min(Swift.max(0, scroller.offset + adjustment - origin),
                                Swift.max(0, extents.totalExtent - viewport))
            let first = Swift.min(Swift.max(0, extents.index(containing: top) - LazyWindow.overscan), count)
            let last = Swift.min(Swift.max(first, extents.index(containing: top + viewport) + 1
                                           + LazyWindow.overscan), count)
            fresh = first..<last
        } else {
            fresh = 0..<Swift.min(LazyWindow.coldLines, count)
        }
        let contained = fresh.isEmpty
            || (builtWindow.lowerBound <= fresh.lowerBound && fresh.upperBound <= builtWindow.upperBound)
        // A cold slice was a guess made before the viewport was known (`LZ-E`): once it is known, the next
        // frame realises exactly the window, so a settled container holds O(viewport) lines, not 32.
        if !contained || (builtCold && scroller.viewportExtent > 0) { pass.frame.requestAnotherFrame() }
        return (extents, adjustment)
    }

    /// `resolveVariableScrollRequests` over lines (`LZ-O`, `VL-H`, `VL-P`): a pending request whose
    /// key is a `ForEach` unit's id targets that unit's line at `offset(of:)` with the index's extent,
    /// in THIS frame's coordinates (`- adjustment`); when the line was unmeasured and the request is
    /// not already a refinement, a refinement for the same line, scope and anchor is carried into
    /// the next frame, so a target lands in at most two resolutions. Walks every unit's id, but only
    /// while a request is pending.
    static func resolveScrollRequests(_ id: GlobalElementID, bounds: Bounds<Pixels>, axis: ScrollAxis,
                                      unitCount: Int, line: (Int) -> Int, rawID: (Int) -> AnyHashable,
                                      index: RowExtentIndex<AnyHashable>?, adjustment: Double,
                                      realisedBounds: (Int) -> Bounds<Pixels>?, pass: PrepaintPass) {
        let pending = pass.frame.unresolvedScrollRequestsWithScope(enclosing: id)
        guard !pending.isEmpty else { return }
        typealias Match = (index: Int, refined: Bool, scope: GlobalElementID, anchor: UnitPoint?)
        let reveals = pending.compactMap { request -> (key: AnyHashable, match: Match)? in
            guard let reveal = request.key.base as? LazyReveal, reveal.container == id else { return nil }
            return (reveal.key, (request.index, true, request.scope, request.anchor))
        }
        let vertical = axis == .vertical
        for unit in 0..<unitCount {
            let key = rawID(unit)
            if key.base is LazyStaticUnitID { continue }   // a static unit is a target only while realised
            let matching: [Match] = pending.filter { $0.key == key }.map { ($0.index, false, $0.scope, $0.anchor) }
                + reveals.filter { $0.key == key }.map(\.match)
            for request in matching where !pass.frame.isScrollRequestResolved(request.index) {
                let target: Bounds<Pixels>
                let position = line(unit)
                if let index {
                    let along = (vertical ? Double(bounds.origin.y.value) : Double(bounds.origin.x.value))
                        + index.offset(of: position) - adjustment
                    let extent = Pixels(Float(index.extent(at: position)))
                    target = vertical
                        ? Bounds(origin: Point(x: bounds.origin.x, y: Pixels(Float(along))),
                                 size: Size(width: bounds.size.width, height: extent))
                        : Bounds(origin: Point(x: Pixels(Float(along)), y: bounds.origin.y),
                                 size: Size(width: extent, height: bounds.size.height))
                    if !request.refined && !index.isMeasured(position) {
                        pass.frame.scrollRequestQueue.carry(
                            ScrollRequest(scope: request.scope,
                                          key: AnyHashable(LazyReveal(container: id, key: key)),
                                          anchor: request.anchor))
                    }
                } else if let realised = realisedBounds(unit) {
                    target = realised
                } else {
                    target = Bounds(origin: bounds.origin,
                                    size: vertical ? Size(width: bounds.size.width, height: Pixels(0))
                                                   : Size(width: Pixels(0), height: bounds.size.height))
                }
                pass.frame.resolveScrollRequest(request.index, target: target)
            }
        }
    }
}
