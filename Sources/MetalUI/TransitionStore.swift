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

    /// A produced unit: its evaluator and whether it fades by default (`XF-H`).
    struct Produced {
        let evaluator: GlobalElementID
        let fades: Bool
    }

    /// Units produced this frame, each with its evaluator: an `if`'s slot (its
    /// own evaluator), a taken branch (its own), a `ForEach` element's scope
    /// (the loop slot). `fades` is set by a builder's `if`/`else` and a non-lazy `ForEach` element, never by
    /// a framework slot built with `OptionalGroup(_:)` or a `for` loop (`XF-H` item 1).
    private var produced: [GlobalElementID: Produced] = [:]
    private var previousProduced: [GlobalElementID: Produced] = [:]

    /// Whether any conditional or loop noted an animation this frame (`XF-H` item 4): the gate of the default fade's
    /// `afterLayout` work, so a frame with no animation iterates no unit.
    private(set) var notedAnimationThisFrame = false

    /// `for` loops noted this frame, by slot, with the extent they consumed
    /// (`Int.max` while the loop is still registering its iterations).
    private var arrayExtents: [GlobalElementID: Int] = [:]
    private var previousArrayExtents: [GlobalElementID: Int] = [:]

    /// An `if` (untyped or typed copy) was evaluated at `slot`.
    func noteOptional(_ slot: GlobalElementID, produced isProduced: Bool, animation: Animation?, fades: Bool = false) {
        buildJournal?.record(.transitionEvaluated(slot, animation))
        evaluated[slot] = .some(animation)
        if animation != nil { notedAnimationThisFrame = true }
        if isProduced {
            buildJournal?.record(.transitionProduced(slot, slot, fades))
            produced[slot] = Produced(evaluator: slot, fades: fades)
        }
    }

    /// An `if`/`else` (untyped or typed copy) was evaluated: `taken` produced,
    /// `untaken` not.
    func noteEither(taken: GlobalElementID, untaken: GlobalElementID, animation: Animation?) {
        buildJournal?.record(.transitionEvaluated(taken, animation))
        buildJournal?.record(.transitionEvaluated(untaken, animation))
        buildJournal?.record(.transitionProduced(taken, taken, true))
        evaluated[taken] = .some(animation)
        evaluated[untaken] = .some(animation)
        if animation != nil { notedAnimationThisFrame = true }
        produced[taken] = Produced(evaluator: taken, fades: true)
    }

    /// A loop (a `ForEach`, either entry) was evaluated at `slot`.
    func noteLoop(_ slot: GlobalElementID, animation: Animation?) {
        buildJournal?.record(.transitionEvaluated(slot, animation))
        evaluated[slot] = .some(animation)
        if animation != nil { notedAnimationThisFrame = true }
    }

    /// A `ForEach` produced the element whose scope is `scope` under `slot`.
    func noteLoopElement(_ scope: GlobalElementID, of slot: GlobalElementID) {
        buildJournal?.record(.transitionProduced(scope, slot, true))
        produced[scope] = Produced(evaluator: slot, fades: true)
    }

    /// A `for` loop (either copy) is being evaluated at `slot`: its iterations
    /// sit directly under the slot, a unit per cursor index.
    func beginArrayLoop(_ slot: GlobalElementID, animation: Animation?) {
        buildJournal?.record(.transitionEvaluated(slot, animation))
        buildJournal?.record(.transitionArray(slot, Int.max))
        evaluated[slot] = .some(animation)
        if animation != nil { notedAnimationThisFrame = true }
        arrayExtents[slot] = Int.max
    }

    /// The `for` loop at `slot` consumed `extent` indices.
    func endArrayLoop(_ slot: GlobalElementID, extent: Int) {
        buildJournal?.record(.transitionArray(slot, extent))
        arrayExtents[slot] = extent
    }

    /// The window's build journal (`RK-F`), attached by the animation store.
    var buildJournal: BuildJournal?

    /// Claimed groups and captures of the build in progress (`RK-F`): a graft window that moves it cannot be replayed.
    var buildActivity: Int { records.count &+ capturedThisFrame }

    /// Applies a journalled note (`RK-F`): the same writes the build made, recorded again for an enclosing window.
    func replayEvaluated(_ slot: GlobalElementID, _ animation: Animation?) {
        buildJournal?.record(.transitionEvaluated(slot, animation))
        evaluated[slot] = .some(animation)
        if animation != nil { notedAnimationThisFrame = true }
    }

    func replayProduced(_ unit: GlobalElementID, _ evaluator: GlobalElementID, _ fades: Bool) {
        buildJournal?.record(.transitionProduced(unit, evaluator, fades))
        produced[unit] = Produced(evaluator: evaluator, fades: fades)
    }

    func replayArray(_ slot: GlobalElementID, _ extent: Int) {
        buildJournal?.record(.transitionArray(slot, extent))
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
        /// The scene sequence range this annotated group painted, `nil` before its paint or under a composite
        /// scope (`XF-H` item 3): a default ghost carves it out of its unit's range.
        var sequences: Range<Int>?
        var sequenceStart = 0
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
        /// What the removal does; a matched-geometry leaver's ghost gains a translation (`XF-M`).
        var atoms: [TransitionAtom]
        let rect: MUIBounds
        var captures: [CapturedPrimitive]
        /// The element whose run this ghost is drawn in (`XF-F`): the nearest ancestor of the ghost's position that was
        /// prepainted, resolved once by `resolveAnchors` in the frame that made the ghost. `nil` until then, and for
        /// good when no ancestor was prepainted (the ghost is then drawn after the root, counted as unanchored).
        var anchor: GlobalElementID?
        /// Whether this frame's paint already drew the ghost at its anchor. Part of what a redo puts back
        /// (`rollbackBuild`) and cleared by `paintGhosts` at the end of every frame.
        var drawn = false
        /// Positions whose disappearances this ghost does not park (`XF-H`): the annotated members of a default
        /// ghost's unit, which park under their own ghosts, or nowhere for a `.identity` one.
        var exempt: [GlobalElementID] = []
        /// The emission sequence of each of `captures` in the frame they were sliced from (`XF-H` item 10), parallel to
        /// it; empty for an annotated ghost. What a matched-geometry handoff carves a leaver's member out by.
        var captureSequences: [Int] = []
        /// The default unit a matched-geometry leaver's own ghost was carved out of (`XF-M`), so the unit's
        /// reappearance takes it down with the unit's ghost; `nil` for every other ghost.
        var carvedFrom: GlobalElementID?
    }

    private var insertions: [GlobalElementID: Insertion] = [:]
    /// Ghosts in the order their removals began — the order they paint in.
    private var ghosts: [(key: GlobalElementID, ghost: Ghost)] = []

    private var capturedThisFrame = 0

    /// The scene ranges the fading units painted this frame, and the last completed frame's with its scene (`XF-H`
    /// item 3). The scene is the frame's own **unfinalized** one, kept only while a unit drew, so a removal slices it.
    private(set) var ranges: [UnitRange] = []
    private var previousRanges: [UnitRange] = []
    private var previousScene: Scene?

    /// A unit painted `start..<end` of the frame's emission sequence.
    @inline(__always)
    func noteRange(_ unit: GlobalElementID, start: Int, end: Int) {
        ranges.append(UnitRange(unit: unit, start: start, end: end))
    }

    /// Re-notes a recorded occurrence's unit ranges at the sequence its replay started at (`XF-H` item 8).
    func renoteRanges(_ recorded: [UnitRange], base: Int) {
        for r in recorded { ranges.append(UnitRange(unit: r.unit, start: r.start + base, end: r.end + base)) }
    }

    /// Primitives the last completed frame captured for a possible ghost — a
    /// work counter (spec 3.16): 0 for a tree with no `.transition`.
    private(set) var lastFrameCapturedPrimitives = 0

    /// The unit ranges the last completed frame noted (`XF-H`): a work counter, one per fading unit that painted (or whose
    /// replay was re-noted), 0 for a tree with no builder `if`, `if`/`else` branch or `ForEach` element.
    var lastFrameUnitRanges: Int { previousRanges.count }

    /// Insertions and ghosts in flight.
    var liveCount: Int { insertions.count + ghosts.count }

    /// Ghosts in flight.
    var ghostCount: Int { ghosts.count }

    /// Whether any ghost has a resolved anchor (`XF-F`): what `Frame.hasGhostAnchors` is set from each frame.
    var hasAnchoredGhosts: Bool { ghosts.contains { $0.ghost.anchor != nil } }

    /// Each live ghost's anchor, in removal order (`nil` until resolved, or for good when no ancestor was prepainted).
    var ghostAnchors: [GlobalElementID?] { ghosts.map { $0.ghost.anchor } }

    /// Ghosts the last completed frame drew after the root instead of at their container (`XF-F`): a work counter.
    /// Zero in an ordinary tree; non-zero when the container left, was hidden, or paints through a path that
    /// reaches no hook.
    private(set) var lastFrameUnanchoredGhosts = 0

    /// Each live ghost's key and its group's position (`key.parent`) — read by
    /// the lifecycle after `paintGhosts`, so a landed ghost is already gone
    /// (ruling `LC-H`).
    var liveGhosts: [(key: GlobalElementID, position: GlobalElementID, exempt: [GlobalElementID])] {
        ghosts.map { ($0.key, $0.key.parent!, $0.ghost.exempt) }
    }

    /// Whether any insertion is in flight, annotated or default: the gate of `beginFade`'s dictionary read.
    var hasLiveInsertions: Bool { !insertions.isEmpty }

    /// Whether the group recorded at `key` last frame carries a transition that removes it at once — an
    /// explicit `.identity` (or any transition with nothing to play on removal): `matchedGeometryEffect`'s
    /// leaver hands its frame over only when SwiftUI would keep it on screen (probe S2, `MG-B`).
    func removalWasAnnotatedInstant(_ key: GlobalElementID) -> Bool {
        guard let record = previousRecords[key] else { return false }
        return record.transition.atoms(insertion: false, reduceMotion: record.reduceMotion).isEmpty
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
        } else if let p = produced[parent] {
            unit = parent
            evaluator = p.evaluator
            arrayIndex = nil
        } else {
            return false
        }
        records[key] = Record(unit: unit, evaluator: evaluator, arrayIndex: arrayIndex,
                              transition: transition, reduceMotion: reduceMotion)
        return true
    }

    /// The unit a claimed group sits in, `nil` when it is not claimed (`XF-H`).
    func unit(of key: GlobalElementID) -> GlobalElementID? { records[key]?.unit }

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
                  !wasProduced(previous, previous: false) else { continue }
            let atoms = previous.transition.atoms(insertion: false, reduceMotion: previous.reduceMotion)
            guard !atoms.isEmpty else { continue }
            // A ghost always exists (`XF-G`, `T1e2`): content that drew nothing, or laid out no node, still holds its
            // `onDisappear` for the animation. It draws nothing; the zero rect is never read by a primitive.
            let rect = previous.surfaceRect ?? MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0))
            if let stale = ghostIndex(key) { ghosts.remove(at: stale) }
            ghosts.append((key, Ghost(start: now, animation: animation, from: from, atoms: atoms,
                                      rect: rect, captures: previous.captures)))
            frame.pendingGhostAnchors = true   // its container is found after prepaint (`XF-F`)
        }
        advanceDefaultUnits(frame)
    }

    // MARK: Default units (`XF-H`)

    /// The key of the ghost a removed default unit leaves.
    static func defaultKey(_ unit: GlobalElementID) -> GlobalElementID {
        .child(of: unit, at: 0, name: ElementID("$default-transition"))
    }

    private static let zeroRect = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0))

    /// Default insertions and removals (`XF-H` item 4), after the annotated groups'. Gated on an animation having been
    /// noted this frame, or a default ghost standing (a unit produced again cancels it): a frame with neither
    /// iterates no unit.
    private func advanceDefaultUnits(_ frame: Frame) {
        guard notedAnimationThisFrame || !ghosts.isEmpty else { return }
        let now = frame.timestamp
        for (unit, p) in produced where p.fades {
            let ghost = ghostIndex(Self.defaultKey(unit))
            if notedAnimationThisFrame,
               insertions[unit] == nil,
               previousEvaluated[p.evaluator] != nil,
               previousProduced[unit] == nil,
               let animation = evaluated[p.evaluator] ?? nil {
                // An insertion during a removal starts from the ghost's progress.
                let from = ghost.map { activeness(of: ghosts[$0].ghost, at: now).value } ?? 1
                insertions[unit] = Insertion(start: now, animation: animation, from: from, atoms: [.opacity])
            }
            if let ghost {
                ghosts.remove(at: ghost)
                ghosts.removeAll { $0.ghost.carvedFrom == unit }   // `XF-M`: its leavers' own ghosts go with it
            }
        }
        guard notedAnimationThisFrame else { return }
        for (unit, p) in previousProduced where p.fades && produced[unit] == nil {
            // A removal during an insertion: the slice has the insertion's alpha baked in, so the ghost starts at 0.
            insertions[unit] = nil
            guard let entry = evaluated[p.evaluator], let animation = entry else { continue }
            let (slice, annotated, exempt) = defaultSlice(of: unit)
            let captures = slice.primitives
            // A unit whose members are all annotated leaves no default ghost: each parks under its own (`XF-H` item 4).
            if captures.isEmpty && annotated { continue }
            let key = Self.defaultKey(unit)
            if let stale = ghostIndex(key) { ghosts.remove(at: stale) }
            var ghost = Ghost(start: now, animation: animation, from: 0, atoms: [.opacity],
                              rect: Self.zeroRect, captures: captures)
            ghost.exempt = exempt
            ghost.captureSequences = slice.sequences
            ghosts.append((key, ghost))
            frame.pendingGhostAnchors = true
        }
    }

    /// The last frame's primitives of `unit` minus its annotated members' (`XF-H` item 3), whether the unit has an
    /// annotated member, and those members' positions. Empty when the scene or the range is gone (an atlas rebuild,
    /// a dropped replay): the ghost then draws nothing and still parks.
    private func defaultSlice(of unit: GlobalElementID)
        -> (slice: (primitives: [CapturedPrimitive], sequences: [Int]), annotated: Bool, exempt: [GlobalElementID]) {
        var carved: [Range<Int>] = [], exempt: [GlobalElementID] = []
        var annotated = false
        for record in previousRecords.values where record.unit == unit {
            annotated = true
            if let sequences = record.sequences { carved.append(sequences) }
        }
        if annotated {
            for (key, record) in previousRecords where record.unit == unit {
                if let position = key.parent { exempt.append(position) }
            }
        }
        guard let scene = previousScene, let range = previousRanges.last(where: { $0.unit == unit }),
              range.end > range.start else { return (([], []), annotated, exempt) }
        return (scene.capturedPrimitives(inSequences: range.start..<range.end, excluding: carved), annotated, exempt)
    }

    /// The key of the ghost a matched-geometry leaver gets of its own (`XF-M`): under the leaver's position, so the
    /// anchor walk of `XF-F` and the lifecycle's parking (`key.parent`) read it as they read an annotated ghost's.
    static func leaverKey(_ position: GlobalElementID) -> GlobalElementID {
        .child(of: position, at: 0, name: ElementID("$matched-leaver"))
    }

    /// A matched-geometry leaver moves toward the group's source as it fades out (`XF-M`, divergence 897, probes `S1`,
    /// `S9`, `S12`): `(dx, dy)` points, the leaver keeping its own size.
    ///
    /// - An **annotated** leaver's ghost (`transitionKey`) gains the translation when it fades (`.opacity`).
    /// - An **unannotated** leaver's primitives (`range`, the scene sequences its group drew) are carved out of the
    ///   default ghost of its unit into a ghost of their own, which fades and moves; the unit's ghost no longer
    ///   parks the leaver's position, the new one does (`Ghost.exempt`).
    ///
    /// The atom shares the ghost's activeness, so the fade and the move are one curve. Does nothing when no ghost
    /// holds the leaver (the removal was not animated, or its sequences were not recorded).
    func leaverMoves(transitionKey: GlobalElementID, sequences range: Range<Int>?, dx: Double, dy: Double, frame: Frame) {
        let move = TransitionAtom.translate(sizeX: 0, sizeY: 0, x: dx, y: dy)
        if let index = ghostIndex(transitionKey) {
            if ghosts[index].ghost.atoms.contains(.opacity) { ghosts[index].ghost.atoms.append(move) }
            return
        }
        guard let range, let position = transitionKey.parent else { return }
        var captures: [CapturedPrimitive] = [], sequences: [Int] = []
        var donor: (key: GlobalElementID, ghost: Ghost)?
        for index in ghosts.indices where !ghosts[index].ghost.captureSequences.isEmpty {
            var keep: [CapturedPrimitive] = [], keptSequences: [Int] = []
            let ghost = ghosts[index].ghost
            var carved = false
            for (primitive, sequence) in zip(ghost.captures, ghost.captureSequences) {
                if range.contains(sequence) {
                    captures.append(primitive)
                    sequences.append(sequence)
                    carved = true
                } else {
                    keep.append(primitive)
                    keptSequences.append(sequence)
                }
            }
            guard carved else { continue }
            ghosts[index].ghost.captures = keep
            ghosts[index].ghost.captureSequences = keptSequences
            ghosts[index].ghost.exempt.append(position)
            if donor == nil { donor = ghosts[index] }
        }
        guard let donor else { return }
        var own = Ghost(start: donor.ghost.start, animation: donor.ghost.animation, from: donor.ghost.from,
                        atoms: [.opacity, move], rect: Self.zeroRect, captures: captures)
        own.captureSequences = sequences
        own.carvedFrom = donor.key.parent
        ghosts.append((Self.leaverKey(position), own))
        frame.pendingGhostAnchors = true
    }

    /// Opens the non-capturing fade of the default insertion of `unit`, if one is in flight (`XF-H` item 7). Keeps the
    /// display link awake and ends a landed one.
    func beginFade(_ unit: GlobalElementID, frame: Frame) -> PaintScope? {
        guard let insertion = insertions[unit] else { return nil }
        let a = activeness(of: insertion, at: frame.timestamp)
        if a.isFinished {
            insertions[unit] = nil
            return nil
        }
        frame.noteActiveAnimation()
        let effect = RenderEffect(atoms: insertion.atoms, activeness: a.value, rect: Self.zeroRect,
                                  scaleFactor: frame.scaleFactor)
        let scope = PaintScope(kind: .fade, effect: effect, entryClipDepth: frame.clipDepth)
        scope.fadeUnit = unit
        return scope
    }

    /// Suspends the open default fade of `unit` for the duration of `body` (`XF-H` item 4): an annotated member of a
    /// mixed unit keeps its own transition and is not faded by the unit's default (`XF5`). The scope stays on the stack,
    /// so every index and recorder height is unmoved; `processScopes` skips a suspended scope.
    func suspendingFade(of unit: GlobalElementID, in frame: Frame, _ body: () -> Void) {
        guard insertions[unit] != nil else { return body() }
        var suspended: [PaintScope] = []
        for scope in frame.paintScopes where scope.kind == .fade && scope.fadeUnit == unit && !scope.suspended {
            scope.suspended = true
            suspended.append(scope)
        }
        body()
        for scope in suspended { scope.suspended = false }
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
        records[key]?.sequenceStart = frame.scene.nextEmissionSequence
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
    func endPaint(_ key: GlobalElementID, scope: PaintScope, sequenceEnd: Int, composite: Bool) {
        capturedThisFrame += scope.captures.count
        records[key]?.captures = scope.captures
        if let start = records[key]?.sequenceStart, !composite { records[key]?.sequences = start..<sequenceEnd }
    }

    /// Draws `ghost` at `activeness`: its capture replayed with its removal effect, straight into the scene (a ghost
    /// bypasses every live scope, so it stays frozen at its last place).
    private func draw(_ ghost: Ghost, activeness value: Double, frame: Frame) {
        let effect = RenderEffect(atoms: ghost.atoms, activeness: value, rect: ghost.rect,
                                  scaleFactor: frame.scaleFactor)
        // Through `insertLeaves`, so a group the removed unit held fades as one group (`GO-G`).
        frame.insertLeaves(ghost.captures.compactMap { effect.apply(to: $0, flattens: true, outer: nil) })
    }

    /// Finds the container of each ghost that has none (`XF-F`): the nearest ancestor of its position that is in
    /// `seen`, the ids `recordElementBounds` noted this frame. Called once per frame that made a ghost, after
    /// prepaint and before paint.
    func resolveAnchors(seen: Set<GlobalElementID>) {
        for index in ghosts.indices where ghosts[index].ghost.anchor == nil {
            var cursor = ghosts[index].key.parent?.parent   // the position's parent
            while let id = cursor {
                if seen.contains(id) { ghosts[index].ghost.anchor = id; break }
                cursor = id.parent
            }
        }
    }

    /// Draws every unfinished ghost anchored at `id`, in the order their removals began, at the position the caller
    /// is painting (`XF-F`): the first sublayer of the container's run, as SwiftUI places a leaver (`XF10`). A ghost
    /// is inserted directly, so it bypasses the paint recorder: an enclosing retained occurrence that drew one must
    /// not record (`ghostInRun`), or its replay would be frozen without the ghost.
    func paintGhosts(anchoredAt id: GlobalElementID, frame: Frame) {
        for index in ghosts.indices where ghosts[index].ghost.anchor == id && !ghosts[index].ghost.drawn {
            let ghost = ghosts[index].ghost
            let a = activeness(of: ghost, at: frame.timestamp)
            guard !a.isFinished else { continue }
            ghosts[index].ghost.drawn = true
            frame.retainLog?.taint("ghostInRun")
            draw(ghost, activeness: a.value, frame: frame)
        }
    }

    /// Called once per frame after the tree has painted, before the glyph
    /// atlas's frame bracket closes: every live ghost not already drawn at its
    /// container, replayed with its removal effect on the layer it had, in the
    /// order the removals began (above the root: a ghost whose container was not
    /// reached, `lastFrameUnanchoredGhosts`). A landed ghost is dropped and not drawn.
    func paintGhosts(_ pass: inout PaintPass) {
        lastFrameUnanchoredGhosts = 0
        guard !ghosts.isEmpty else { return }
        let frame = pass.frame
        ghosts.removeAll { activeness(of: $0.ghost, at: frame.timestamp).isFinished }
        for index in ghosts.indices {
            frame.noteActiveAnimation()
            if ghosts[index].ghost.drawn { ghosts[index].ghost.drawn = false; continue }
            lastFrameUnanchoredGhosts += 1
            let ghost = ghosts[index].ghost
            draw(ghost, activeness: activeness(of: ghost, at: frame.timestamp).value, frame: frame)
        }
    }

    /// What a redo restores of this store (`RK-M`): the insertions and ghosts in flight, which `afterLayout`
    /// advances, and the capture counter.
    struct Checkpoint {
        let insertions: [GlobalElementID: Insertion]
        let ghosts: [(key: GlobalElementID, ghost: Ghost)]
        let captured: Int
    }

    func checkpoint() -> Checkpoint { Checkpoint(insertions: insertions, ghosts: ghosts, captured: capturedThisFrame) }

    /// Forgets the build in progress (`RK-M`): this frame's notes and claimed groups are empty at the start of a
    /// build (`endFrame` swaps and clears) — a claim answers `false` for a key already recorded — and the
    /// insertions and ghosts return to what they were before `afterLayout` advanced them.
    func rollbackBuild(_ saved: Checkpoint) {
        evaluated.removeAll(keepingCapacity: true)
        produced.removeAll(keepingCapacity: true)
        arrayExtents.removeAll(keepingCapacity: true)
        records.removeAll(keepingCapacity: true)
        ranges.removeAll(keepingCapacity: true)
        notedAnimationThisFrame = false
        insertions = saved.insertions
        ghosts = saved.ghosts
        capturedThisFrame = saved.captured
    }

    /// Forgets every captured sprite - the last frame's and each ghost's - because
    /// the glyph atlas was emptied and a captured glyph names a rect in the
    /// atlas it was painted against (`GL-D` item 3). A group captured so ghosts
    /// nothing (its removal starts a ghost that draws nothing, `XF-G`, still
    /// parking its `onDisappear`; a ghost in flight draws nothing) until its
    /// next paint captures it again; insertions and progress stay.
    func forgetCapturedPrimitives() {
        for key in Array(records.keys) { records[key]?.captures = [] }
        for key in Array(previousRecords.keys) { previousRecords[key]?.captures = [] }
        for index in ghosts.indices { ghosts[index].ghost.captures = []; ghosts[index].ghost.captureSequences = [] }
        // The kept scene names atlas slots too (`XF-H` item 9): a removal after it is a ghost that draws nothing.
        previousScene = nil
        previousRanges.removeAll()
        ranges.removeAll()
    }

    /// Called once per frame at its end, before the `AnimationStore` drops
    /// untouched entries: this frame's notes and records become the last
    /// completed frame's.
    func endFrame(scene: Scene) {
        swap(&ranges, &previousRanges)
        ranges.removeAll(keepingCapacity: true)
        previousScene = previousRanges.isEmpty ? nil : scene
        notedAnimationThisFrame = false
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

extension Frame {
    /// Draws the removal ghosts anchored at `id` (`XF-F`). Called by each element's paint, the content of each
    /// styled element's decoration, each modifier chain's innermost layer, `AnyElement`'s entry and the root, behind
    /// `hasGhostAnchors`.
    func paintAnchoredGhosts(at id: GlobalElementID) {
        animationStore.transitions.paintGhosts(anchoredAt: id, frame: self)
    }
}

/// One open paint scope (`Frame.paintScopes`, ruling `GX-G`): a claimed
/// transition group's (plan task 13, `AN-AE`), a render effect's (`GX-H`), a
/// drag source's capture (`DN-J`), or a `Deferred`'s barrier, past which an
/// outer effect does not reach (`GX-G`; a portal is not transformed), or a
/// `compositingGroup()`'s composite (`PF-E`), which collects what reaches it
/// and re-emits it as one leaf when it closes. Each
/// processes every primitive emitted inside it, innermost first: the effect
/// applied, and — for a transition or a capture — what it received kept
/// (before its own effect) for a ghost or a preview.
@MainActor
final class PaintScope {
    enum Kind { case transition, effect, capture, barrier, shadow, blur, composite, fade }

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
    /// A blur scope's radius (device pixels of the space it was pushed in)
    /// and the clip at its entry (`LK-K`), `nil` for every other kind.
    var blur: Blur?

    /// A blur scope's radius in device pixels of the space it was pushed in,
    /// and the clip at its entry (`LK-K`).
    struct Blur {
        var radius: Double
        var mask: MUIBounds
        var radii: MUICorners
    }
    var captures: [CapturedPrimitive] = []
    /// A default insertion's fade scope names its unit (`XF-H` item 7); `nil` for every other kind.
    var fadeUnit: GlobalElementID?
    /// Whether `processScopes` skips this scope for now: a `.fade` while an annotated member of its unit paints.
    var suspended = false
    /// A composite scope's collected primitives' emission clip depths, one per
    /// entry of `captures` (`PF-E`): what `maskDepth(emittedAt:)` reads when
    /// the collection goes through the scopes outside it.
    var captureDepths: [Int] = []
    /// A composite scope that exists for a shadow or blur outside it (`PF-E`): it degrades a backdrop to its flat tint.
    var leafEffect = false
    /// A composite scope that composites an opacity (`GO-A`): its leaves leave it marked with `entryOpacity`.
    var groupsOpacity = false
    /// The opacity in force where the group starts, which becomes the mark's alpha (`GO-A`).
    var entryOpacity: Float = 1
    /// A composite scope that masks (`CM-A`): the shape's primitive, in the space the scope was entered in. Its leaves
    /// leave it marked with this mask; `nil` for every other scope.
    var mask: CapturedPrimitive?
    /// The token of the group a flattening effect's crossing clips share (`CM-B`): one per scope, so every primitive whose
    /// clip crosses the entry clip joins the same masked group. Made on first use.
    lazy var crossingMaskToken = GroupToken()

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
