import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import Observation

// C14b (`SB-A`…`SB-AA`): retained subtrees. One record per `.equatable()` occurrence, hung off its
// content-memo entry: the scene operations its **paint** produced and the cache touches that paint made,
// replayed instead of run while its replay key is equal. The build recursion still runs, so a miss is always
// safe: every element's layout record exists. C14b-2 adds the **prepaint** half beside it
// (`RetainedPrepaint.swift`, `RK-C`…`RK-E`): a ledger of what the occurrence's prepaint registered, replayed
// while the prepaint key is equal, with a redo of the frame when a replayed prepaint meets a paint-only
// ambient (an opacity, a shadow or blur scope — pushed by an ancestor's paint, after every prepaint) that
// differs from the record's (`SB-AA` is why the decision cannot be taken at prepaint alone).
// Spec `docs/superpowers/specs/2026-10-13-retained-subtrees-design.md` and
// `2026-10-13-retained-build-skip-design.md`, rulings `docs/superpowers/2026-10-13-retained-subtrees-decisions.md`
// and `2026-10-13-retained-build-skip-decisions.md`.

/// The work counters of retained subtrees for one build (`SB-`): work, never time.
package struct RetainedCounters: Sendable, Equatable {
    /// Occurrences whose paint was replayed from a record.
    package var hits = 0
    /// Occurrences that ran paint and left a record (first sight, or a key, version or observation that
    /// no longer matched), or ran because the pointer, a press or focus is inside them.
    package var misses = 0
    /// Occurrences that ran paint and left no record: a channel a record cannot replay moved
    /// (`SB-J`), or a context the key cannot hold was open.
    package var ineligible = 0
    /// Element prepaints a prepaint replay stood for (`RK-E`): the work of the ledgers replayed.
    package var skippedPrepaints = 0
    /// Element paints a hit stood for (the conservation law of test 1.1).
    package var skippedPaints = 0
    /// Ledger snapshots taken (two per recorded occurrence: before and after its paint).
    package var ledgerSnapshots = 0
    /// Recorded scene operations replayed.
    package var replayedOps = 0
    /// Occurrences whose prepaint was replayed from a record (`RK-E`).
    package var prepaintHits = 0
    /// Occurrences whose prepaint ran and left no prepaint record: a channel a record cannot replay
    /// moved, or a context the prepaint key cannot hold was open (`RK-E`, by name in the trace).
    package var prepaintIneligible = 0
    /// Frames redone because a replayed prepaint met a paint-only ambient that differed (`RK-D`, `RK-M`).
    package var redos = 0
    /// Builds that ran with prepaint replay suspended after a redo (`RK-D` item 3).
    package var backoffFrames = 0
    /// Occurrences replayed at a translated position (`RK-G`).
    package var translated = 0
    /// Occurrences whose move by a translation failed the gate and missed (`RK-G`).
    package var translationRefused = 0
    /// Occurrences whose build recursion did not run: their layout rows were copied and the build journal applied again
    /// (`RK-B`, `RK-F`).
    package var grafts = 0
    /// Occurrences that built and could leave no graft record, by channel in the trace (`RK-F`).
    package var graftIneligible = 0
    /// Element requests the grafts stood for: `elementRequests + skippedRequests` is a graft-off frame's count.
    package var skippedRequests = 0
    /// Layout nodes the grafts appended instead of registering.
    package var graftedNodes = 0
    package init() {}
}

/// Whether `METALUI_TRACE_RETAINED=1` (read once): every miss prints why its record did not match, and
/// every ineligible occurrence the channel that moved. A diagnostic, never read by a test.
let retainedTraces: Bool = ProcessInfo.processInfo.environment["METALUI_TRACE_RETAINED"] == "1"

/// Whether `METALUI_VERIFY_RETAINED=1` (read once, `SB-W`): a hit also runs the fresh paint and traps if
/// its products differ from the record's.
let retainedVerifiesFromEnvironment: Bool =
    ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1"

// MARK: - The log

/// What every open recorder shares (`SB-D`): the calls the frame's few paint funnels make while a recorder
/// is open, in order. A recorder remembers the log's lengths where its window opened and closed and keeps
/// the slice. **`Frame.retainLog` is `nil` unless a recorder is open**, so every hook is one nil check on a
/// frame that retains nothing.
@MainActor
final class RetainLog {
    enum Touch {
        case touch(GlobalElementID)
        case set(GlobalElementID, Any)
    }

    /// The leaves as they stand where a recorder's own paint scopes end (`boundary` scopes still to
    /// process, counting from the outermost), and the clip depth they were emitted at (`SB-T`).
    struct SceneOp {
        let boundary: Int
        let leaves: [([CapturedPrimitive], [Int]?)]
        let depth: Int
    }

    struct Marks: Equatable {
        var scene = 0, marks = 0, touches = 0
    }

    var recorders: [SubtreeRecorder] = []
    var scene: [SceneOp] = []
    var marks: [GlobalElementID] = []
    var touches: [Touch] = []

    var current: Marks {
        Marks(scene: scene.count, marks: marks.count, touches: touches.count)
    }

    /// Whether any open recorder can still leave a record: one that is already tainted wants nothing
    /// from a nested replay, which may then skip the scopes (`SB-AB`).
    var needsLeaves: Bool { recorders.contains { $0.taint == nil } }

    /// Marks every open recorder (or, with `scopeIndex`, every one whose own scopes include that index)
    /// as unable to leave a record, naming the first reason.
    func taint(_ reason: String, scopeIndex: Int? = nil) {
        for recorder in recorders {
            if let scopeIndex, recorder.entryHeight > scopeIndex { continue }
            if recorder.taint == nil { recorder.taint = reason }
        }
    }

    /// Notes the leaves at `boundary` when an open recorder's own scopes end there, and at boundary 0
    /// (the scene itself) for the final-primitive stream a plain-effect replay uses (`SB-AB`).
    func noteBoundary(_ boundary: Int, _ leaves: [([CapturedPrimitive], [Int]?)], _ depth: Int) {
        for recorder in recorders where recorder.entryHeight == boundary || boundary == 0 {
            scene.append(SceneOp(boundary: boundary, leaves: leaves, depth: depth))
            return
        }
    }

    func noteDirect(_ primitive: CapturedPrimitive, depth: Int) {
        noteBoundary(0, [([primitive], nil)], depth)
    }
}

/// One occurrence's recording of its paint.
@MainActor
final class SubtreeRecorder {
    var taint: String?
    /// The paint scopes open where the paint window opened: the height the scene is recorded at.
    var entryHeight = 0
    var from = RetainLog.Marks()
    var before = LedgerSnapshot()
}

// MARK: - The ledger

/// The counts a recorder reads before and after a paint (`SB-E`).
struct LedgerSnapshot {
    var surfaceRequests = 0, timeNotes = 0, interpolations = 0
    /// Work a replay stands for: element paints run, plus those nested hits stood for.
    var work = 0

    /// The first pinned channel that moved from `self` to `other`, or `nil`.
    func movedChannel(to other: LedgerSnapshot) -> String? {
        if surfaceRequests != other.surfaceRequests { return "surfaceRequests" }
        if timeNotes != other.timeNotes { return "timeNotes" }
        if interpolations != other.interpolations { return "interpolations" }
        return nil
    }
}

// MARK: - The replay key

/// Everything paint reads that is not in the subtree (`SB-F`, spec §4.2), as flat `Equatable` parts.
/// **Every part has a separating arm in `everyKeyComponentSeparates` or is covered twice** (the scale factor and the window
/// size by the environment fingerprint, the rects and the interior by each other; record 109 §5).
struct AmbientKey: Equatable {
    /// The kind word of an effect scope in `scopes` (`retainedAmbientKey`), index 0 of its vector.
    static let effectKind = Double(PaintScope.Kind.effect.hashValue)

    var clip: [Float]
    var offset: [Float]
    var layerOpacityScale: [Float]
    var depths: [Int]
    var scopes: [[Double]]
    var environment: EnvironmentFingerprint
    var snappingTransaction: Bool
    var disablesAnimations: Bool
}

struct ReplayKey: Equatable {
    var rects: [Float]
    var interior: Int
    var nodeCount: Int
    var ambient: AmbientKey

    /// Whether this (the new) key is `old` with only the translation of outer render-effect scopes moved (`RK-G`,
    /// `RK-S`): the recorded leaves are those before any outer scope applies, so replaying them through the live
    /// scopes is arithmetic-for-arithmetic what a fresh paint does at the new translation.
    func differsOnlyByEffectTranslation(from old: ReplayKey) -> Bool {
        guard rects == old.rects, interior == old.interior, nodeCount == old.nodeCount,
              ambient.scopes.count == old.ambient.scopes.count else { return false }
        var moved = false
        var normalized = ambient
        for index in ambient.scopes.indices where ambient.scopes[index] != old.ambient.scopes[index] {
            let new = ambient.scopes[index], was = old.ambient.scopes[index]
            guard new.count == was.count, new.count >= 10, new[0] == AmbientKey.effectKind else { return false }
            var a = new, b = was
            a[8] = 0; a[9] = 0; b[8] = 0; b[9] = 0
            guard a == b else { return false }
            moved = true
            normalized.scopes[index] = was
        }
        return moved && normalized == old.ambient
    }
}

// MARK: - The record

/// One occurrence's paint products (`SB-B`), replayed in the order a fresh paint makes them.
@MainActor
final class RetainedRecord {
    var key: ReplayKey
    /// `ContentMemoStore.Entry.serial` of the getter evaluation the record was made under.
    var contentSerial = 0
    /// The `@State` slots bound under the component and their versions (`SB-K`).
    var versions: [(GlobalElementID, UInt64)] = []
    /// The leaves where the occurrence's own paint scopes end, for a replay inside another recording or
    /// under an outer scope that captures, shadows, blurs or composites.
    var scene: [RetainLog.SceneOp] = []
    /// The primitives as they reached the scene, for a replay with no other recorder open when every
    /// outer scope is a plain effect (a pure map the key holds): the scopes are not processed again
    /// (`SB-AB`). `nil` when an outer scope is not a plain effect.
    var finalScene: [RetainLog.SceneOp]?
    var marks: [GlobalElementID] = []
    var touches: [RetainLog.Touch] = []
    var paintWork = 0
    /// Whether the build, prepaint and paint windows were all observed when the record was made
    /// (`SB-V`). A record made on a frame that skipped the build and prepaint sessions (the frame a
    /// valid record missed on) covers only its paint, so it is not replayed: the next frame observes
    /// all three and records again.
    var coverageComplete = true
    /// What the occurrence's prepaint registered (`RK-E`), or `nil` when it could not be recorded.
    var prepaint: PrepaintLedger?

    init(key: ReplayKey) { self.key = key }
}

// MARK: - Observation sessions

/// One observation window of an occurrence (`SB-V`): the build recursion, prepaint or paint.
final class RetainedSession {
    let token = ContentMemoToken()
    var serial = 0
    let label: String
    init(_ label: String) { self.label = label }

    /// Runs `body` inside a fresh session; the previous one is retired first (the serial moves on,
    /// then the token write fires it, and its handler finds a stale serial — `IV-L` item 5).
    @MainActor
    func run<R>(entry: ContentMemoStore.Entry, store: ContentMemoStore, _ body: () -> R) -> R {
        serial &+= 1
        token.tick &+= 1
        let handle = RetainedHandle(entry: entry, store: store, session: self, serial: serial)
        return withObservationTracking({
            _ = token.tick
            return body()
        }, onChange: {
            handle.fire()
        })
    }
}

private final class RetainedHandle: @unchecked Sendable {
    let entry: ContentMemoStore.Entry
    let store: ContentMemoStore
    let session: RetainedSession
    let serial: Int

    init(entry: ContentMemoStore.Entry, store: ContentMemoStore, session: RetainedSession, serial: Int) {
        self.entry = entry
        self.store = store
        self.session = session
        self.serial = serial
    }

    func fire() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.fireOnMain() }
        } else {
            Task { @MainActor in self.fireOnMain() }
        }
    }

    @MainActor private func fireOnMain() {
        guard session.serial == serial else { return }
        if retainedTraces { print("retained session fired: \(session.label)") }
        entry.observedChange = true
        store.markDirty?()
    }
}

// MARK: - The build window

/// What the build recursion of one occurrence leaves for its paint (`SB-K`): kept in the component's
/// layout box.
@MainActor
final class RetainedBuild {
    let key: ContentMemoStore.Key
    let topNodes: [LayoutNodeID]
    /// The range of `StateTable.markJournal` the build covered: the slots bound under the component,
    /// read only when a record is made.
    let journal: Range<Int>
    let timeVarying: Bool
    /// Whether the build ran inside an observation window (`SB-V`).
    let observed: Bool

    init(key: ContentMemoStore.Key, topNodes: [LayoutNodeID], journal: Range<Int>, timeVarying: Bool, observed: Bool) {
        self.key = key
        self.topNodes = topNodes
        self.journal = journal
        self.timeVarying = timeVarying
        self.observed = observed
    }
}

/// The open build window of one occurrence.
@MainActor
struct RetainedBuildWindow {
    let journalLow: Int
    let notes: Int

    init(frame: Frame) {
        journalLow = frame.stateTable.markJournal.count
        notes = frame.timeVaryingNotes &+ frame.animationStore.interpolationsSoFar
    }

    func finish(frame: Frame, key: ContentMemoStore.Key, nodes: [LayoutNodeID], observed: Bool) -> RetainedBuild {
        let now = frame.timeVaryingNotes &+ frame.animationStore.interpolationsSoFar
        return RetainedBuild(key: key, topNodes: nodes, journal: journalLow..<frame.stateTable.markJournal.count,
                             timeVarying: now != notes, observed: observed)
    }
}

// MARK: - The phase object

/// What prepaint hands to paint (`SB-`): carried in `ComponentPrepaint`'s box.
@MainActor
final class RetainedPhase {
    let build: RetainedBuild
    let entry: ContentMemoStore.Entry
    /// Whether prepaint ran inside an observation window, as the build did.
    let prepaintObserved: Bool
    /// The occurrence's rects and layout signature, read once at prepaint and shared by both keys.
    var rects: [Float] = []
    var interior = 0
    var nodeCount = 0
    /// The prepaint key this frame computed, and the ledger this frame's prepaint made (`nil` when it was
    /// refused or tainted) or replayed (`RK-E`).
    var prepaintKey: PrepaintKey?
    var ledger: PrepaintLedger?
    var replayed: PrepaintLedger?
    /// Whether the paint decision replayed the record at a translated position (`RK-G`, `RK-S`).
    var translatedPaint = false
    /// Whether the occurrence was grafted (`RK-B`): no element layout, so prepaint and paint can only replay.
    var grafted = false
    /// Whether its prepaint asked for the frame to be redone: paint then does nothing.
    var abandoned = false

    init(build: RetainedBuild, entry: ContentMemoStore.Entry, prepaintObserved: Bool) {
        self.build = build
        self.entry = entry
        self.prepaintObserved = prepaintObserved
    }
}

/// What paint does with an occurrence (`SB-AA`).
enum RetainedPaintMode {
    /// Replay the record.
    case hit(RetainedRecord)
    /// Run paint under a recorder; `old` is the record verify mode compares against.
    case record(SubtreeRecorder, ReplayKey, old: RetainedRecord?)
    /// Run paint, record nothing (ineligible now).
    case plain
}

// MARK: - Frame: the key, the ledger, windows, replay

extension Frame {
    /// A snapshot of the ledger channels (`SB-E`).
    func ledgerSnapshot() -> LedgerSnapshot {
        var s = LedgerSnapshot()
        s.surfaceRequests = surfaceRequests.count
        s.timeNotes = timeVaryingNotes
        s.interpolations = animationStore.interpolationsSoFar
        let retained = stateTable.contentMemos.retained
        s.work = elementPaints &+ retained.skippedPaints
        return s
    }

    /// Why this occurrence cannot be keyed now, or `nil` (`SB-J`): contexts the key cannot hold.
    func retainedEntryRefusal(build: RetainedBuild) -> String? {
        if build.timeVarying { return "timeVarying" }
        if leafGroup != nil { return "leafGroup" }
        if environmentTop.uncomparableCustomCount > 0 { return "uncomparableEnvironmentKey" }
        if transactionTop.animation != nil { return "transaction" }
        return nil
    }

    private func flat(_ b: Bounds<Pixels>) -> [Float] {
        [b.origin.x.value, b.origin.y.value, b.size.width.value, b.size.height.value]
    }

    private func flat(_ a: Affine2D) -> [Double] { [a.a, a.b, a.c, a.d, a.tx, a.ty] }

    private func flat(_ m: MUIBounds) -> [Double] {
        [Double(m.origin.x), Double(m.origin.y), Double(m.size.width), Double(m.size.height)]
    }

    private func flat(_ c: MUICorners) -> [Double] {
        [Double(c.topLeft), Double(c.topRight), Double(c.bottomRight), Double(c.bottomLeft)]
    }

    /// The ambient half of the replay key (spec §4.2), read **at paint**: the paint-only stacks (opacity,
    /// scopes) exist only there.
    func retainedAmbientKey() -> AmbientKey {
        let radii = activeClipRadii
        var scopeVectors: [[Double]] = []
        scopeVectors.reserveCapacity(paintScopes.count)
        for scope in paintScopes {
            var v: [Double] = [Double(scope.kind.hashValue), Double(scope.effect.alpha), Double(scope.entryClipDepth),
                               scope.flattens ? 1 : 0]
            v += flat(scope.effect.affine)
            if let outer = scope.outer {
                v += [1] + flat(outer.bounds) + flat(outer.radii) + [Double(outer.depth)]
            } else {
                v += [0]
            }
            if let shadow = scope.shadow {
                v += [1, Double(shadow.color.h), Double(shadow.color.s), Double(shadow.color.l), Double(shadow.color.a),
                      shadow.radius, shadow.dx, shadow.dy] + flat(shadow.mask) + flat(shadow.radii)
            } else {
                v += [0]
            }
            if let blur = scope.blur { v += [1, blur.radius] + flat(blur.mask) + flat(blur.radii) } else { v += [0] }
            scopeVectors.append(v)
        }
        return AmbientKey(
            clip: flat(activeClip) + [radii.topLeft.value, radii.topRight.value, radii.bottomRight.value,
                                      radii.bottomLeft.value],
            offset: [activeOffset.x.value, activeOffset.y.value],
            layerOpacityScale: [Float(activeLayer), activeOpacity, scaleFactor,
                                contentSize.width.value, contentSize.height.value],
            depths: [clipDepth, clipBase, flatteningClipBase ?? -1, paintScopes.count],
            scopes: scopeVectors,
            environment: environmentTop.retainedFingerprint,
            snappingTransaction: transactionTop.animation == nil,
            disablesAnimations: transactionTop.disablesAnimations)
    }

    func retainedKey(_ phase: RetainedPhase) -> ReplayKey {
        ReplayKey(rects: phase.rects, interior: phase.interior, nodeCount: phase.nodeCount, ambient: retainedAmbientKey())
    }

    /// Reads the occurrence's rects and layout signature into `phase` (once per occurrence per frame).
    func readRetainedGeometry(into phase: RetainedPhase) {
        var rects: [Float] = []
        rects.reserveCapacity(phase.build.topNodes.count * 4)
        for node in phase.build.topNodes { rects += flat(bounds(of: node)) }
        let (hash, count) = tree.subtreeSignature(of: phase.build.topNodes)
        phase.rects = rects; phase.interior = hash; phase.nodeCount = count
    }

    /// Whether the hovered element, the pressed one or the focused one is the component or under it (`SB-F`
    /// item 4): identity is structural, so an element inside the occurrence has its component's id as an
    /// ancestor. Exact where the design's "pointer inside an owned hitbox" was conservative: a hover that is
    /// elsewhere (another node on top of this one) costs this occurrence nothing.
    func retainedSubtreeHasPointerPressOrFocus(under id: GlobalElementID) -> Bool {
        if let hovered = hoveredElement, hovered.isOrDescends(from: id) { return true }
        if let active = activeElement, active.isOrDescends(from: id) { return true }
        if let focused = focusedElement, focused.isOrDescends(from: id) { return true }
        return false
    }

    // MARK: Windows

    func openRecorderWindow(_ recorder: SubtreeRecorder) {
        if retainLog == nil { retainLog = RetainLog() }
        let log = retainLog!
        recorder.entryHeight = paintScopes.count
        recorder.from = log.current
        recorder.before = ledgerSnapshot()
        stateTable.contentMemos.retained.ledgerSnapshots += 1
        log.recorders.append(recorder)
    }

    /// Closes the recorder's window and returns what it covered.
    func closeRecorderWindow(_ recorder: SubtreeRecorder) -> (to: RetainLog.Marks, after: LedgerSnapshot) {
        let log = retainLog!
        let to = log.current
        let after = ledgerSnapshot()
        stateTable.contentMemos.retained.ledgerSnapshots += 1
        if let reason = recorder.before.movedChannel(to: after), recorder.taint == nil { recorder.taint = reason }
        return (to, after)
    }

    // MARK: Replay

    func replayPaint(_ r: RetainedRecord, translated: Bool = false) {
        // A record replayed at a translated position goes through the live scopes (`RK-S`): the final stream holds
        // the old translation in its coordinates.
        if !translated, retainLog?.needsLeaves != true, let final = r.finalScene {
            // No other live recorder wants the leaves where an outer scope would pass them: straight in.
            for op in final { for (group, _) in op.leaves { for primitive in group { insertIntoScene(primitive) } } }
        } else {
            for op in r.scene { processScopes(op.leaves, from: op.boundary, depth: op.depth) }
        }
        for id in r.marks { stateTable.mark(id) }
        for touch in r.touches { animationStore.replay(touch) }
        stateTable.contentMemos.retained.skippedPaints += r.paintWork
        stateTable.contentMemos.retained.replayedOps += r.scene.count
    }

    // MARK: Decision and recording

    /// What prepaint hands to paint: the phase of an occurrence that retains, or `nil` (retention off,
    /// or no memo entry).
    func retainedPrepaintPhase(build: RetainedBuild) -> RetainedPhase? {
        let memos = stateTable.contentMemos
        guard let entry = memos.entry(for: build.key) else { return nil }
        guard memos.retainsSubtrees else {
            entry.record = nil
            return nil
        }
        let phase = RetainedPhase(build: build, entry: entry, prepaintObserved: entry.needsObservation)
        readRetainedGeometry(into: phase)
        return phase
    }

    /// The decision of `EquatableComponent.paintGroup` (spec §3.1, `SB-AA`): replay, record, or run plain.
    func retainedPaintDecision(_ phase: RetainedPhase) -> RetainedPaintMode {
        let build = phase.build, entry = phase.entry
        let memos = stateTable.contentMemos
        if let reason = retainedEntryRefusal(build: build) {
            if retainedTraces { print("retained refused \(sbPath(build.key.id).suffix(60)) because \(reason)") }
            entry.record = nil
            memos.retained.ineligible += 1
            return .plain
        }
        let key = retainedKey(phase)
        let underPointer = retainedSubtreeHasPointerPressOrFocus(under: build.key.id)
        if let old = entry.record {
            let valid = !entry.observedChange && old.coverageComplete && old.contentSerial == entry.serial
                && old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }) && !underPointer
                && (phase.replayed == nil || old.prepaint === phase.replayed)
            let translated = valid && old.key != key && memos.replaysPrepaint && key.differsOnlyByEffectTranslation(from: old.key)
            if valid && (old.key == key || translated) {
                memos.retained.hits += 1
                if translated { memos.retained.translated += 1; phase.translatedPaint = true }
                if phase.replayed != nil { entry.redoExponent = 0 }
                // A prepaint-replayed occurrence has no element prepaint state to paint from: verify mode checks
                // it at the window, by building the frame again with replay off (`RK-N`).
                if retainedVerifiesFromEnvironment, phase.replayed == nil { return .record(SubtreeRecorder(), key, old: old) }
                return .hit(old)
            }
            if retainedTraces { traceMiss(old, key: key, build: build, entry: entry, underPointer: underPointer) }
        } else if retainedTraces {
            print("retained first-or-dropped \(sbPath(build.key.id).suffix(60))")
        }
        entry.record = nil
        return .record(SubtreeRecorder(), key, old: nil)
    }

    private func traceMiss(_ old: RetainedRecord, key: ReplayKey, build: RetainedBuild, entry: ContentMemoStore.Entry,
                           underPointer: Bool) {
        var why: [String] = []
        if entry.observedChange { why.append("observed") }
        if old.contentSerial != entry.serial { why.append("serial") }
        if old.key.rects != key.rects { why.append("rects") }
        if old.key.interior != key.interior { why.append("interior") }
        if old.key.ambient != key.ambient {
            let a = old.key.ambient, b = key.ambient
            if a.clip != b.clip { why.append("clip") }
            if a.offset != b.offset { why.append("offset") }
            if a.layerOpacityScale != b.layerOpacityScale { why.append("layerOpacityScale") }
            if a.depths != b.depths { why.append("depths") }
            if a.scopes != b.scopes { why.append("scopes") }
            if a.environment != b.environment { why.append("environment") }
            if a.snappingTransaction != b.snappingTransaction || a.disablesAnimations != b.disablesAnimations {
                why.append("transaction")
            }
        }
        if !old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }) { why.append("versions") }
        if underPointer { why.append("pointer/press/focus") }
        print("retained miss \(sbPath(build.key.id).suffix(60)) \(why)")
    }

    /// Closes the paint window; stores the record, or counts why not.
    func finishRetainedPaint(_ phase: RetainedPhase, recorder: SubtreeRecorder, key: ReplayKey, old: RetainedRecord?) {
        let (to, after) = closeRecorderWindow(recorder)
        let log = retainLog!
        log.recorders.removeAll { $0 === recorder }
        let from = recorder.from, before = recorder.before
        let record = RetainedRecord(key: key)
        var seen = Set<GlobalElementID>()
        for id in stateTable.markJournal[phase.build.journal] where seen.insert(id).inserted {
            record.versions.append((id, stateTable.entryVersion(id)))
        }
        record.coverageComplete = phase.build.observed && phase.prepaintObserved
        record.prepaint = phase.ledger
        record.contentSerial = phase.entry.serial
        let ops = log.scene[from.scene..<to.scene]
        record.scene = ops.filter { $0.boundary == recorder.entryHeight }
        // The final stream is valid only when every outer scope is a plain effect: a pure map of the leaf
        // by parameters the key holds. A shadow, blur, composite, capture or barrier outside needs the
        // leaves handed to it.
        if paintScopes.allSatisfy({ $0.kind == .effect }) {
            record.finalScene = ops.filter { $0.boundary == 0 }
        }
        record.marks = Array(log.marks[from.marks..<to.marks])
        record.touches = Array(log.touches[from.touches..<to.touches])
        record.paintWork = after.work - before.work
        if log.recorders.isEmpty { retainLog = nil }
        let memos = stateTable.contentMemos
        if let old {
            // Verify mode: the record made now must equal the one a replay would have used.
            if let reason = recorder.taint {
                preconditionFailure("METALUI_VERIFY_RETAINED: a replayed subtree is ineligible now (\(reason))")
            }
            if let difference = old.differences(from: record, ignoringFinalStream: phase.translatedPaint) {
                preconditionFailure("METALUI_VERIFY_RETAINED: replay differs from a fresh run at \(sbPath(phase.build.key.id).suffix(80)) (observed \(phase.entry.observedChange), serial \(phase.entry.serial)): \(difference)")
            }
            // The old record stays: it is equal, and it covers the build and prepaint this frame did not observe.
            return
        }
        if let reason = recorder.taint {
            if retainedTraces { print("retained ineligible \(sbPath(phase.build.key.id).suffix(60)) because \(reason)") }
            phase.entry.record = nil
            memos.retained.ineligible += 1
            return
        }
        memos.retained.misses += 1
        if retainedSubtreeHasPointerPressOrFocus(under: phase.build.key.id) {
            phase.entry.record = nil
        } else {
            phase.entry.record = record
            phase.entry.observedChange = false
        }
    }
}

// MARK: - Verify mode

extension RetainedRecord {
    /// How `other` (a fresh run's record) differs from this one, or `nil` (`SB-W`): every scene
    /// operation (kind, layer, masks, texture identity, raster key), the marks and touches, and the
    /// element work the record stands for.
    func differences(from other: RetainedRecord, ignoringFinalStream: Bool = false) -> String? {
        if scene.count != other.scene.count { return "scene.count \(scene.count) vs \(other.scene.count)" }
        func kindDescription(_ kind: CapturedPrimitive.Kind) -> String {
            switch kind {
            case .image(let i, let t): return "image \(i) \(ObjectIdentifier(t))"
            case .surface: return "surface"
            case .path(let p):
                return "path \(p.geometry.hashValue) \(p.mode) \(p.local) \(p.color) \(p.contentMask) \(p.maskCornerRadii)"
            case .shadow(let sh):
                return "shadow \(sh.leaf.map { kindDescription($0.kind) }) \(sh.color) \(sh.radius) \(sh.dx) \(sh.dy) \(sh.local) \(sh.contentMask) \(sh.entryDepth)"
            default: return "\(kind)"
            }
        }
        func describe(_ op: RetainLog.SceneOp) -> String {
            var s = "\(op.boundary)|\(op.depth)|"
            for (group, depths) in op.leaves {
                s += "[\(String(describing: depths))"
                for p in group {
                    s += "{\(p.layer)|\(p.innerMask)|\(p.outerMaskInner)|\(String(describing: p.transform?.record))|"
                    s += kindDescription(p.kind)
                    s += "}"
                }
                s += "]"
            }
            return s
        }
        for (a, b) in zip(scene, other.scene) where describe(a) != describe(b) {
            return "scene op \(describe(a)) vs \(describe(b))"
        }
        if !ignoringFinalStream, (finalScene == nil) != (other.finalScene == nil) { return "finalScene presence" }
        if !ignoringFinalStream, let x = finalScene, let y = other.finalScene {
            if x.count != y.count { return "finalScene.count \(x.count) vs \(y.count)" }
            for (a, b) in zip(x, y) where describe(a) != describe(b) { return "final op \(describe(a)) vs \(describe(b))" }
        }
        if marks != other.marks { return "marks" }
        // A first sighting touches and stores (two touches), a later frame only touches: the same entry kept
        // alive, so the comparison is of the ids, not of the touch count.
        func ids(_ touches: [RetainLog.Touch]) -> Set<GlobalElementID> {
            var out = Set<GlobalElementID>()
            for touch in touches {
                switch touch {
                case .touch(let id): out.insert(id)
                case .set(let id, _): out.insert(id)
                }
            }
            return out
        }
        if ids(touches) != ids(other.touches) { return "touched entries" }
        if paintWork != other.paintWork { return "paintWork \(paintWork) vs \(other.paintWork)" }
        return nil
    }
}

/// Debug path of an identity (the `METALUI_TRACE_RETAINED` prints).
func sbPath(_ id: GlobalElementID) -> String {
    var parts: [String] = []
    var current: GlobalElementID? = id
    while let c = current { parts.append("\(c.component)"); current = c.parent }
    return parts.reversed().joined(separator: "/")
}
