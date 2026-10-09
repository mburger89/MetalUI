import MetalUICore
import MetalUILayout
import MetalUIPrimitives

/// Transitions' bookkeeping, captures and progress (plan task 13, ruling
/// `AN-AE` as amended by `AN-AH`, lane 3's `AN-AK`; spec §6.5), held by the
/// window's `AnimationStore`.
///
/// **What it tracks, per frame.** Every conditional and loop notes that it was
/// evaluated, with the animation in effect AT it (X13, X14), and which of its
/// units it produced: an `if`'s slot, an `if`/`else` branch id, a `ForEach`
/// element's scope, a `for` loop's extent. A `TransitionGroup` claims its
/// position when its parent is such a unit (the outermost group of inserted
/// content, X15), and records itself. The frame's `afterLayout` compares the
/// frame with the last COMPLETED one:
///
/// - **insertion**: a claimed group whose conditional was evaluated last frame
///   and did not produce its unit — never content in a first render, under a
///   newly evaluated parent, or in a `List` row entering its window (X17);
/// - **removal**: a group recorded last frame whose conditional was evaluated
///   THIS frame and did not produce its unit — never a group whose conditional
///   was not evaluated (a `List` row out of its window, `TB-AH`).
///
/// **Why its own tracking, not a `StateTable` query** (`AN-AK`): the table
/// keeps the slots produced last frame but not the ones evaluated absent, nor a
/// loop's evaluation by its slot, and an insertion needs both; keeping the
/// transition's own two frames here adds no `StateTable` entry and leaves
/// every reset path untouched.
///
/// A tree with no `.transition` claims nothing and captures nothing
/// (`lastFrameCapturedPrimitives == 0`); its conditionals still note (a
/// dictionary write each, per frame), because an insertion needs the
/// conditional's previous frame before any group exists (X17c).
@MainActor
final class TransitionStore {
    init() {}

    // MARK: Noting (this frame, and the last completed frame)

    /// Evaluators noted this frame — an `if`'s slot, both branch ids of an
    /// `if`/`else`, a loop's slot — with the animation in effect at each.
    private var evaluated: [GlobalElementID: Animation?] = [:]
    private var previousEvaluated: [GlobalElementID: Animation?] = [:]

    /// Units produced this frame, each with its evaluator: an `if`'s slot (its
    /// own evaluator), a taken branch (its own), a `ForEach` element's scope
    /// (the loop slot).
    private var produced: [GlobalElementID: GlobalElementID] = [:]
    private var previousProduced: [GlobalElementID: GlobalElementID] = [:]

    /// `for` loops noted this frame, by slot, with the extent they consumed
    /// (`Int.max` while the loop is still registering its iterations).
    private var arrayExtents: [GlobalElementID: Int] = [:]
    private var previousArrayExtents: [GlobalElementID: Int] = [:]

    /// An `if` (untyped or typed copy) was evaluated at `slot`.
    func noteOptional(_ slot: GlobalElementID, produced isProduced: Bool, animation: Animation?) {
        evaluated[slot] = .some(animation)
        if isProduced { produced[slot] = slot }
    }

    /// An `if`/`else` (untyped or typed copy) was evaluated: `taken` produced,
    /// `untaken` not.
    func noteEither(taken: GlobalElementID, untaken: GlobalElementID, animation: Animation?) {
        evaluated[taken] = .some(animation)
        evaluated[untaken] = .some(animation)
        produced[taken] = taken
    }

    /// A loop (a `ForEach`, either entry) was evaluated at `slot`.
    func noteLoop(_ slot: GlobalElementID, animation: Animation?) {
        evaluated[slot] = .some(animation)
    }

    /// A `ForEach` produced the element whose scope is `scope` under `slot`.
    func noteLoopElement(_ scope: GlobalElementID, of slot: GlobalElementID) {
        produced[scope] = slot
    }

    /// A `for` loop (either copy) is being evaluated at `slot`: its iterations
    /// sit directly under the slot, a unit per cursor index.
    func beginArrayLoop(_ slot: GlobalElementID, animation: Animation?) {
        evaluated[slot] = .some(animation)
        arrayExtents[slot] = Int.max
    }

    /// The `for` loop at `slot` consumed `extent` indices.
    func endArrayLoop(_ slot: GlobalElementID, extent: Int) {
        arrayExtents[slot] = extent
    }

    // MARK: Groups

    /// One claimed group this frame (or the last).
    struct Record {
        let unit: GlobalElementID
        let evaluator: GlobalElementID
        /// The cursor index of a `for`-loop unit, `nil` for every other kind.
        let arrayIndex: Int?
        let transition: AnyTransition
        let reduceMotion: Bool
        var nodes: [LayoutNodeID] = []
        /// The content's laid-out rectangle (engine points, untranslated).
        var rect: Bounds<Pixels>?
        /// The same in the scene's device pixels, where it painted.
        var surfaceRect: MUIBounds?
        var captures: [CapturedPrimitive] = []
    }

    private var records: [GlobalElementID: Record] = [:]
    private var previousRecords: [GlobalElementID: Record] = [:]

    /// An insertion in flight: activeness moving from `from` to 0.
    struct Insertion {
        let start: Double
        let animation: Animation
        let from: Double
        let atoms: [TransitionAtom]
    }

    /// A removal in flight: the last capture replayed, activeness moving from
    /// `from` to 1.
    struct Ghost {
        let start: Double
        let animation: Animation
        let from: Double
        let atoms: [TransitionAtom]
        let rect: MUIBounds
        let captures: [CapturedPrimitive]
    }

    private var insertions: [GlobalElementID: Insertion] = [:]
    /// Ghosts in the order their removals began — the order they paint in.
    private var ghosts: [(key: GlobalElementID, ghost: Ghost)] = []

    private var capturedThisFrame = 0

    /// Primitives the last completed frame captured for a possible ghost — a
    /// work counter (spec 3.16): 0 for a tree with no `.transition`.
    private(set) var lastFrameCapturedPrimitives = 0

    /// Insertions and ghosts in flight.
    var liveCount: Int { insertions.count + ghosts.count }

    /// Ghosts in flight.
    var ghostCount: Int { ghosts.count }

    /// Each live ghost's key and its group's position (`key.parent`) — read by
    /// the lifecycle after `paintGhosts`, so a landed ghost is already gone
    /// (ruling `LC-H`).
    var liveGhosts: [(key: GlobalElementID, position: GlobalElementID)] {
        ghosts.map { ($0.key, $0.key.parent!) }
    }

    /// The store key of the group at `cursor` under `parent` — the position it
    /// sits at, `.animation(_:value:)`'s keying (`AN-Y`), so it collides with
    /// no id its content mints.
    static func key(under parent: GlobalElementID?, at cursor: Int) -> GlobalElementID {
        .child(of: .child(of: parent, at: cursor, name: nil), at: 0, name: ElementID("$transition"))
    }

    /// Claims the position `(parent, cursor)` for a group carrying `transition`
    /// when its parent is a unit a conditional or loop noted this frame, and
    /// no group at the same position claimed it first (the outer of two
    /// stacked `.transition`s wins). Returns whether it did.
    func claim(key: GlobalElementID, under parent: GlobalElementID?, at cursor: Int,
               transition: AnyTransition, reduceMotion: Bool) -> Bool {
        guard let parent, records[key] == nil else { return false }
        let unit: GlobalElementID, evaluator: GlobalElementID, arrayIndex: Int?
        if arrayExtents[parent] != nil {
            unit = .child(of: parent, at: cursor, name: nil)
            evaluator = parent
            arrayIndex = cursor
        } else if let e = produced[parent] {
            unit = parent
            evaluator = e
            arrayIndex = nil
        } else {
            return false
        }
        records[key] = Record(unit: unit, evaluator: evaluator, arrayIndex: arrayIndex,
                              transition: transition, reduceMotion: reduceMotion)
        return true
    }

    /// The claimed group's content registered `nodes`.
    func setNodes(_ nodes: [LayoutNodeID], for key: GlobalElementID) {
        records[key]?.nodes = nodes
    }

    private func wasProduced(_ record: Record, previous: Bool) -> Bool {
        if let index = record.arrayIndex {
            let extents = previous ? previousArrayExtents : arrayExtents
            return index < (extents[record.evaluator] ?? 0)
        }
        return (previous ? previousProduced : produced)[record.unit] != nil
    }

    private func ghostIndex(_ key: GlobalElementID) -> Int? {
        ghosts.firstIndex { $0.key == key }
    }

    /// Called once per frame after the root layout is computed, before
    /// prepaint: each claimed group's rectangle, its insertion if it is one,
    /// and a ghost for each group last frame recorded that this frame removed.
    func afterLayout(_ frame: Frame) {
        let now = frame.timestamp
        for key in Array(records.keys) {
            guard var record = records[key] else { continue }
            record.rect = record.nodes.reduce(nil) { (union: Bounds<Pixels>?, node) in
                let b = frame.bounds(of: node)
                guard let u = union else { return b }
                let minX = min(u.origin.x.value, b.origin.x.value), minY = min(u.origin.y.value, b.origin.y.value)
                let maxX = max(u.origin.x.value + u.size.width.value, b.origin.x.value + b.size.width.value)
                let maxY = max(u.origin.y.value + u.size.height.value, b.origin.y.value + b.size.height.value)
                return Bounds(origin: Point(x: Pixels(minX), y: Pixels(minY)),
                              size: Size(width: Pixels(maxX - minX), height: Pixels(maxY - minY)))
            }
            records[key] = record
            let ghost = ghostIndex(key)
            if insertions[key] == nil,
               previousEvaluated[record.evaluator] != nil,
               !wasProduced(record, previous: true),
               let animation = evaluated[record.evaluator] ?? nil {
                let atoms = record.transition.atoms(insertion: true, reduceMotion: record.reduceMotion)
                if !atoms.isEmpty {
                    // An insertion during a removal starts from the ghost's progress.
                    let from = ghost.map { activeness(of: ghosts[$0].ghost, at: now).value } ?? 1
                    insertions[key] = Insertion(start: now, animation: animation, from: from, atoms: atoms)
                }
            }
            if let ghost { ghosts.remove(at: ghost) }
        }
        for (key, previous) in previousRecords where records[key] == nil {
            // A removal during an insertion starts from the insertion's progress.
            let from = insertions.removeValue(forKey: key).map { activeness(of: $0, at: now).value } ?? 0
            guard let entry = evaluated[previous.evaluator], let animation = entry,
                  !wasProduced(previous, previous: false),
                  let rect = previous.surfaceRect, !previous.captures.isEmpty else { continue }
            let atoms = previous.transition.atoms(insertion: false, reduceMotion: previous.reduceMotion)
            guard !atoms.isEmpty else { continue }
            if let stale = ghostIndex(key) { ghosts.remove(at: stale) }
            ghosts.append((key, Ghost(start: now, animation: animation, from: from, atoms: atoms,
                                      rect: rect, captures: previous.captures)))
        }
    }

    private func activeness(of insertion: Insertion, at now: Double) -> (value: Double, isFinished: Bool) {
        let r = insertion.animation.value(at: now - insertion.start, from: insertion.from, to: 0, initialVelocity: 0)
        return (r.value, r.isFinished)
    }

    private func activeness(of ghost: Ghost, at now: Double) -> (value: Double, isFinished: Bool) {
        let r = ghost.animation.value(at: now - ghost.start, from: ghost.from, to: 1, initialVelocity: 0)
        return (r.value, r.isFinished)
    }

    /// Opens a claimed group's paint: its insertion's effect at this frame's
    /// timestamp (identity when none is in flight), capturing what it emits.
    func beginPaint(_ key: GlobalElementID, frame: Frame) -> PaintScope? {
        guard let record = records[key] else { return nil }
        let scaleFactor = frame.scaleFactor
        let offset = frame.activeOffset
        let surfaceRect = record.rect.map { r in
            MUIBounds(origin: MUIPoint(x: (r.origin.x.value + offset.x.value) * scaleFactor,
                                       y: (r.origin.y.value + offset.y.value) * scaleFactor),
                      size: MUISize(width: r.size.width.value * scaleFactor,
                                    height: r.size.height.value * scaleFactor))
        }
        records[key]?.surfaceRect = surfaceRect
        var effect = RenderEffect.identity
        if let insertion = insertions[key] {
            let a = activeness(of: insertion, at: frame.timestamp)
            if a.isFinished {
                insertions[key] = nil
            } else {
                frame.noteActiveAnimation()
                if let surfaceRect {
                    effect = RenderEffect(atoms: insertion.atoms, activeness: a.value,
                                              rect: surfaceRect, scaleFactor: scaleFactor)
                }
            }
        }
        return PaintScope(effect: effect, entryClipDepth: frame.clipDepth)
    }

    /// Closes a claimed group's paint: its capture becomes the group's record.
    func endPaint(_ key: GlobalElementID, scope: PaintScope) {
        capturedThisFrame += scope.captures.count
        records[key]?.captures = scope.captures
    }

    /// Called once per frame after the tree has painted, before the glyph
    /// atlas's frame bracket closes: every live ghost's capture replayed with
    /// its removal effect, on the layer it had, in the order the removals
    /// began. A landed ghost is dropped and not drawn.
    func paintGhosts(_ pass: inout PaintPass) {
        guard !ghosts.isEmpty else { return }
        let frame = pass.frame
        ghosts.removeAll { activeness(of: $0.ghost, at: frame.timestamp).isFinished }
        for (_, ghost) in ghosts {
            frame.noteActiveAnimation()
            let a = activeness(of: ghost, at: frame.timestamp)
            let effect = RenderEffect(atoms: ghost.atoms, activeness: a.value, rect: ghost.rect,
                                      scaleFactor: frame.scaleFactor)
            for primitive in ghost.captures {
                guard let replayed = effect.apply(to: primitive, flattens: true, outer: nil) else { continue }
                frame.insertIntoScene(replayed)
            }
        }
    }

    /// Called once per frame at its end, before the `AnimationStore` drops
    /// untouched entries: this frame's notes and records become the last
    /// completed frame's.
    func endFrame() {
        swap(&evaluated, &previousEvaluated)
        evaluated.removeAll(keepingCapacity: true)
        swap(&produced, &previousProduced)
        produced.removeAll(keepingCapacity: true)
        swap(&arrayExtents, &previousArrayExtents)
        arrayExtents.removeAll(keepingCapacity: true)
        swap(&records, &previousRecords)
        records.removeAll(keepingCapacity: true)
        lastFrameCapturedPrimitives = capturedThisFrame
        capturedThisFrame = 0
    }
}

/// One open paint scope (`Frame.paintScopes`, ruling `GX-G`): a claimed
/// transition group's (plan task 13, `AN-AE`), a render effect's (`GX-H`), a
/// drag source's capture (`DN-J`), or a `Deferred`'s barrier, past which an
/// outer effect does not reach (`GX-G`; a portal is not transformed). Each
/// processes every primitive emitted inside it, innermost first: the effect
/// applied, and — for a transition or a capture — what it received kept
/// (before its own effect) for a ghost or a preview.
@MainActor
final class PaintScope {
    enum Kind { case transition, effect, capture, barrier, shadow }

    /// A shadow scope's shadow (`GX-J`): its colour, radius and offset in
    /// device pixels of the space it was pushed in, and the clip at its entry.
    struct Shadow {
        var color: Hsla
        var radius: Double
        var dx: Double
        var dy: Double
        var mask: MUIBounds
        var radii: MUICorners
    }

    let kind: Kind
    let effect: RenderEffect
    let entryClipDepth: Int
    /// Whether a plain primitive is mapped on the CPU (every transition and
    /// capture; an effect whose map is a translation plus a uniform positive
    /// scale) rather than given a transform record.
    let flattens: Bool
    /// An effect's outer mask: the clip at its entry. A flattening effect's
    /// cuts the masks pushed inside it once mapped (`GX-X`); a transition's is
    /// `nil`.
    let outer: OuterMask?
    /// A shadow scope's shadow, `nil` for every other kind.
    let shadow: Shadow?
    var captures: [CapturedPrimitive] = []

    var capturing: Bool { kind == .transition || kind == .capture }

    init(kind: Kind, effect: RenderEffect, entryClipDepth: Int, flattens: Bool = true, outer: OuterMask? = nil,
         shadow: Shadow? = nil) {
        self.kind = kind
        self.effect = effect
        self.entryClipDepth = entryClipDepth
        self.flattens = flattens
        self.outer = outer
        self.shadow = shadow
    }

    /// A claimed transition group's scope.
    convenience init(effect: RenderEffect, entryClipDepth: Int) {
        self.init(kind: .transition, effect: effect, entryClipDepth: entryClipDepth)
    }
}
