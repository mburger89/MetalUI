import MetalUICore
import MetalUILayout
import MetalUIScene

// The expand/collapse splice animation of a content `List` (outline lane 7, rulings `OG-H` and `OG-P`; record 320).
//
// SwiftUI's outline is an `NSOutlineView`: a chevron click, the arrow keys and an accessibility press expand a group by
// SLIDING the rows below it over about 245 ms with AppKit's row curve, whatever animation the write sits in, while a bare
// binding write snaps (probe `P-N1`..`P-N4`). MetalUI lays the rows out at their FINAL positions at once and animates the
// PAINT: the rows after the splice are drawn displaced by `(old - new) * (1 - p)`, the inserted rows fade in, and a removed
// row ghosts out from the previous frame's scene (`XF-H`'s slicing). Nothing here touches `StateTable`, layout or the
// content flatten cache (`OG-O`): an animating frame evaluates and rebuilds nothing, and the clock is
// `Frame.noteActiveAnimation()`, never `wantsAnotherFrame`.
//
// **The record is a diff of two painted frames** (`SpliceStore`): each list keeps the realised rows of the last completed
// frame (key, unit index, list-local y, scene range). A frame whose unit count differs from it, and whose cause was input
// (`OutlineSplice.noteInput`: a chevron, a key, an accessibility press, a cascade request) or a `withAnimation` write
// (`Frame.transaction`), is classified: the rows that kept their key and moved are SLID, the new keys between the last
// unmoved row and the first shifted one are INSERTED, the old keys there are REMOVED. A bare write is not classified, so it
// snaps. A splice whose rows are all outside the realised window finds no unmoved row beside the shifted one and is not
// animated (divergence 1088).

/// The splice animation's constants and the input marks that say a toggle came from the user (`OG-P`).
@MainActor
enum OutlineSplice {
    /// How long the rows slide (`P-N1`..`P-N4`: moving from about 15 ms to about 259 ms, a 244 ms span; `N3`/`N3b` show a
    /// SwiftUI animation's own duration is ignored).
    static let duration: Double = 0.245
    /// AppKit's row curve as fitted to the 14 recorded samples of each of five runs (record 320): `cubic-bezier(0.25, 0.1,
    /// 0.25, 1)`, root-mean-square error 0.78 pt of the 64 pt travelled when the animation starts 10.6 ms before the first
    /// sample, 1.7 pt when it starts at the first (15 ms). Front-loaded: 65 % of the travel in the first 37 % of the time.
    static let curve = Animation.Curve.bezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)

    /// The disclosure groups (or lists, for a cascade request) input toggled since the lists last painted: a splice caused by
    /// one of them animates. A static, as `OutlineCascade.context` is: an input handler has no frame. Keyed by element id so
    /// a mark only reaches the list it is under.
    private static var marks: [GlobalElementID] = []

    /// Input toggled the group at `group` (a chevron click, ← or →, an accessibility press) or asked a cascade there.
    static func noteInput(_ group: GlobalElementID) {
        if marks.count > 64 { marks.removeFirst(marks.count - 32) }   // a mark nobody painted for: bounded
        marks.append(group)
    }

    private static func isUnder(_ id: GlobalElementID, _ list: GlobalElementID) -> Bool {
        var cursor: GlobalElementID? = id
        while let node = cursor {
            if node == list { return true }
            cursor = node.parent
        }
        return false
    }

    static func hasMark(under list: GlobalElementID) -> Bool {
        marks.contains { isUnder($0, list) }
    }

    static func consumeMarks(under list: GlobalElementID) {
        if marks.isEmpty { return }
        marks.removeAll { isUnder($0, list) }
    }

    /// The eased progress after `elapsed` seconds, and whether the animation has run its course.
    static func progress(elapsed: Double) -> (value: Double, isFinished: Bool) {
        if elapsed >= duration { return (1, true) }
        return (curve.progress(at: Swift.max(0, elapsed) / duration), false)
    }
}

/// One realised row of a list's painted frame.
struct SpliceRow {
    var unit: Int
    var key: AnyHashable
    /// Where the row was drawn, from the list's top, in points: its laid-out place plus the paint offset it had.
    var y: Double
    /// The scene sequence range the row painted, `nil` when the frame replayed it or the scene is gone.
    var range: Range<Int>?
}

/// A row that left, ghosting out where it was.
struct SpliceGhost {
    var captures: [CapturedPrimitive]
    /// The list's top-left in the scene's device pixels when the ghost was captured, so a scroll moves it with the list.
    var origin: (x: Double, y: Double)
}

/// One splice in flight.
@MainActor
final class SpliceActive {
    let start: Double
    let reduceMotion: Bool
    /// For each kept row that moves, how far above (negative) or below (positive) its final place it starts, in points.
    var slides: [AnyHashable: Double]
    var inserted: Set<AnyHashable>
    var ghosts: [SpliceGhost]

    init(start: Double, reduceMotion: Bool, slides: [AnyHashable: Double], inserted: Set<AnyHashable>, ghosts: [SpliceGhost]) {
        self.start = start
        self.reduceMotion = reduceMotion
        self.slides = slides
        self.inserted = inserted
        self.ghosts = ghosts
    }
}

/// One list's record: the last painted frame's rows and the splice in flight.
@MainActor
final class SpliceList {
    var rows: [SpliceRow] = []
    var count = 0
    var hasSnapshot = false
    var origin: (x: Double, y: Double) = (0, 0)
    var active: SpliceActive?
    // This frame's, written by prepaint and paint, committed by `endFrame` (an abandoned build commits nothing).
    var touched = false
    var nextRows: [SpliceRow] = []
    var nextCount = 0
    var nextOrigin: (x: Double, y: Double) = (0, 0)
    var frameActive: SpliceActive?
    var frameStartedNew = false
    var ranges: [AnyHashable: Range<Int>] = [:]
    var painted = false
}

/// What one list's frame paints with: the splice in force at the frame's timestamp.
@MainActor
final class SplicePlan {
    let list: SpliceList
    let active: SpliceActive?
    /// The eased progress and whether the splice has run its course at this frame's timestamp.
    let progress: Double
    let isFinished: Bool

    init(list: SpliceList, active: SpliceActive?, now: Double) {
        self.list = list
        self.active = active
        if let active {
            let p = OutlineSplice.progress(elapsed: now - active.start)
            progress = p.value
            isFinished = p.isFinished
        } else {
            progress = 1
            isFinished = true
        }
    }

    /// Whether something is still moving or fading: the frame keeps the display link awake.
    var isRunning: Bool { active != nil && !isFinished }

    /// How far above or below its final place the kept row `key` is drawn now, in points.
    func offset(of key: AnyHashable) -> Double {
        guard let active, !isFinished, !active.reduceMotion, let slide = active.slides[key] else { return 0 }
        return slide * (1 - progress)
    }

    /// The opacity of the inserted row `key`, `nil` when it is not fading in.
    func insertionAlpha(of key: AnyHashable) -> Float? {
        guard let active, !isFinished, active.inserted.contains(key) else { return nil }
        return Float(progress)
    }

    /// Draws the removed rows' ghosts at their old places, fading out. Inserted straight into the scene, as `XF-F` ghosts are.
    func paintGhosts(frame: Frame, origin: (x: Double, y: Double)) {
        guard let active, !isFinished, !active.ghosts.isEmpty else { return }
        for ghost in active.ghosts where !ghost.captures.isEmpty {
            let move = Affine2D(a: 1, b: 0, c: 0, d: 1, tx: origin.x - ghost.origin.x, ty: origin.y - ghost.origin.y)
            let effect = RenderEffect(alpha: Float(1 - progress), affine: move)
            frame.insertLeaves(ghost.captures.compactMap { effect.apply(to: $0, flattens: true, outer: nil) })
        }
    }

    /// A row painted `range` of the frame's emission sequence.
    func noteRange(_ key: AnyHashable, _ range: Range<Int>) {
        list.ranges[key] = range
    }
}

/// The window's splice records (`AnimationStore.splices`).
@MainActor
final class SpliceStore {
    private var lists: [GlobalElementID: SpliceList] = [:]
    /// The last completed frame's own unfinalized scene, kept while a list recorded ranges in it (`XF-H`'s `previousScene`).
    private var previousScene: Scene?

    /// Lists with a splice in flight or a snapshot: a work counter for the tests.
    var listCount: Int { lists.count }
    var activeCount: Int { lists.values.filter { $0.active != nil }.count }

    /// The frame's splice plan for the list `id` (prepaint).
    ///
    /// - Parameters:
    ///   - rows: the realised rows, in unit order: unit index, key and laid-out y from the list's top.
    ///   - count: the number of units.
    func plan(for id: GlobalElementID, rows: [(unit: Int, key: AnyHashable, y: Double)], count: Int,
              origin: (x: Double, y: Double), frame: Frame) -> SplicePlan {
        let list = lists[id] ?? SpliceList()
        lists[id] = list
        list.touched = true
        list.nextCount = count
        list.nextOrigin = origin
        list.ranges.removeAll(keepingCapacity: true)
        list.painted = false
        list.frameActive = list.active
        list.frameStartedNew = false
        let now = frame.timestamp
        let animates = frame.transaction != nil || OutlineSplice.hasMark(under: id)
        if list.hasSnapshot, count != list.count, animates {
            let reduce = frame.environmentTop.accessibilityReduceMotion
            if let started = classify(list: list, rows: rows, count: count, now: now, reduceMotion: reduce) {
                list.frameActive = started
                list.frameStartedNew = true
            }
        }
        let plan = SplicePlan(list: list, active: list.frameActive, now: now)
        list.nextRows = rows.map { SpliceRow(unit: $0.unit, key: $0.key, y: $0.y + plan.offset(of: $0.key), range: nil) }
        return plan
    }

    /// Classifies the change from the last painted frame into a splice, or `nil` when it is not one this list can animate.
    @inline(never)
    private func classify(list: SpliceList, rows: [(unit: Int, key: AnyHashable, y: Double)], count: Int,
                          now: Double, reduceMotion: Bool) -> SpliceActive? {
        let delta = count - list.count
        guard delta != 0 else { return nil }
        var old: [AnyHashable: SpliceRow] = [:]
        for row in list.rows { old[row.key] = row }
        // The kept rows: those whose key is in both frames, and how far each moved.
        struct Kept { var unit: Int; var oldUnit: Int; var shift: Int; var from: Double; var to: Double }
        var kept: [AnyHashable: Kept] = [:]
        var lastUnmoved = -1
        var firstShifted: Kept?
        for row in rows {
            guard let before = old[row.key] else { continue }
            let shift = row.unit - before.unit
            guard shift == 0 || shift == delta else { return nil }   // something else changed the rows: not a splice
            kept[row.key] = Kept(unit: row.unit, oldUnit: before.unit, shift: shift, from: before.y, to: row.y)
            if shift == 0 { lastUnmoved = Swift.max(lastUnmoved, row.unit) }
            else if firstShifted == nil || before.unit < firstShifted!.oldUnit {
                firstShifted = kept[row.key]
            }
        }
        guard lastUnmoved >= 0 else { return nil }   // the splice is outside the realised window
        let block = abs(delta)
        let oldLast = list.rows.last?.unit ?? -1
        var slides: [AnyHashable: Double] = [:]
        var inserted = Set<AnyHashable>()
        var removed: [SpliceRow] = []
        if delta > 0 {
            if let firstShifted { guard firstShifted.oldUnit == lastUnmoved + 1 else { return nil } }
            else { guard oldLast == lastUnmoved else { return nil } }
            for row in rows where row.unit > lastUnmoved && row.unit <= lastUnmoved + block {
                guard old[row.key] == nil else { return nil }
                inserted.insert(row.key)
            }
        } else {
            if let firstShifted { guard firstShifted.oldUnit == lastUnmoved + 1 + block else { return nil } }
            else { guard oldLast <= lastUnmoved + block else { return nil } }
            removed = list.rows.filter { $0.unit > lastUnmoved && $0.unit <= lastUnmoved + block }
        }
        // Rows the splice pushed into the window from beyond it slide with the rest.
        let reference = firstShifted.map { $0.from - $0.to }
        for row in rows {
            if let moved = kept[row.key] {
                let offset = moved.from - moved.to
                if abs(offset) > 0.01 { slides[row.key] = offset }
            } else if row.unit > lastUnmoved + (delta > 0 ? block : 0), !inserted.contains(row.key), let reference,
                      abs(reference) > 0.01 {
                slides[row.key] = reference
            }
        }
        guard !slides.isEmpty || !inserted.isEmpty || !removed.isEmpty else { return nil }
        var ghosts: [SpliceGhost] = []
        if let scene = previousScene {
            for row in removed {
                guard let range = row.range, range.count > 0 else { continue }
                let slice = scene.capturedPrimitives(inSequences: range, excluding: []).primitives
                if !slice.isEmpty { ghosts.append(SpliceGhost(captures: slice, origin: list.origin)) }
            }
        }
        return SpliceActive(start: now, reduceMotion: reduceMotion, slides: slides, inserted: inserted, ghosts: ghosts)
    }

    /// Called once per completed frame after paint, as `TransitionStore.endFrame` is: this frame's rows become the last
    /// completed frame's, a splice that started becomes the one in flight and one that ran its course ends.
    func endFrame(scene: Scene, timestamp: Double) {
        var kept = false
        for (id, list) in lists {
            guard list.touched else { lists[id] = nil; continue }
            list.touched = false
            list.rows = list.nextRows.map { row in
                var row = row
                row.range = list.painted ? list.ranges[row.key] : nil
                return row
            }
            if list.painted { kept = true }
            list.count = list.nextCount
            list.origin = list.nextOrigin
            list.hasSnapshot = true
            if list.frameStartedNew { list.active = list.frameActive }
            if let active = list.active, timestamp - active.start >= OutlineSplice.duration { list.active = nil }
            list.frameActive = nil
            list.frameStartedNew = false
            OutlineSplice.consumeMarks(under: id)
        }
        previousScene = kept ? scene : nil
    }

    /// The atlas was emptied: a captured glyph names a rect in the old one (`GL-D` item 3).
    func forgetCapturedPrimitives() {
        previousScene = nil
        for list in lists.values {
            for index in list.rows.indices { list.rows[index].range = nil }
            if let active = list.active { for index in active.ghosts.indices { active.ghosts[index].captures = [] } }
            if let active = list.frameActive { for index in active.ghosts.indices { active.ghosts[index].captures = [] } }
        }
    }
}
