import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import Observation

// C14b (`SB-A`…`SB-R`): retained subtrees. One record per `.equatable()` occurrence, hung off
// its content-memo entry: the hitboxes, focus registrations, accessibility records, scene
// operations and cache touches its prepaint and paint produced, replayed instead of run while its
// replay key is equal. Lane 1 (this file) leaves the build recursion running, so a miss is always
// safe: every element's layout record exists and prepaint and paint run as they always did.
// Spec `docs/superpowers/specs/2026-10-13-retained-subtrees-design.md`, rulings
// `docs/superpowers/2026-10-13-retained-subtrees-decisions.md`.

/// The work counters of retained subtrees for one build (`SB-`): work, never time.
package struct RetainedCounters: Sendable, Equatable {
    /// Occurrences whose prepaint and paint were replayed from a record.
    package var hits = 0
    /// Occurrences that ran prepaint and paint and left a record (first sight, or a key,
    /// version or observation that no longer matched), or ran because a pointer, press or focus
    /// is inside them.
    package var misses = 0
    /// Occurrences that ran and left no record: a channel outside the replayable set moved
    /// (`SB-J`), or a context the key cannot hold was open.
    package var ineligible = 0
    /// Element prepaints and paints a hit stood for (the conservation law of test 1.1).
    package var skippedPrepaints = 0
    package var skippedPaints = 0
    /// Ledger snapshots taken (four per recorded occurrence).
    package var ledgerSnapshots = 0
    /// Recorded operations replayed (hitboxes, registrations, accessibility records, scene
    /// operations).
    package var replayedOps = 0
    package init() {}
}

/// Whether `METALUI_TRACE_RETAINED=1` (read once): every miss prints why its record did not match, and
/// every ineligible occurrence the channel that moved. A diagnostic, never read by a test.
let retainedTraces: Bool = ProcessInfo.processInfo.environment["METALUI_TRACE_RETAINED"] == "1"

/// Whether `METALUI_VERIFY_RETAINED=1` (read once, `SB-M`): a hit also runs the fresh prepaint and
/// paint and traps if its products differ from the record's.
let retainedVerifiesFromEnvironment: Bool =
    ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1"

// MARK: - The log

/// What every open recorder shares (`SB-D`): the calls the frame's few funnels make while a
/// recorder is open, in order. A recorder remembers the log's lengths where its window opened and
/// closed and keeps the slice. **`Frame.retainLog` is `nil` unless a recorder is open**, so every
/// hook is one nil check on a frame that retains nothing.
@MainActor
final class RetainLog {
    enum FocusOp {
        case register(Handlers, GlobalElementID)
        case shortcut(Handlers, GlobalElementID)
        case binding(FocusBindingTarget, GlobalElementID)
    }

    enum Touch {
        case touch(GlobalElementID)
        case set(GlobalElementID, Any)
    }

    /// The leaves as they stand where a recorder's own paint scopes end (`boundary` scopes still
    /// to process, counting from the outermost), and the clip depth they were emitted at.
    struct SceneOp {
        let boundary: Int
        let leaves: [([CapturedPrimitive], [Int]?)]
        let depth: Int
    }

    struct Marks: Equatable {
        var focus = 0, bounds = 0, scene = 0, marks = 0, touches = 0
        var axNodes = 0, pressOnly = 0, contextMenus = 0, withStates = 0
    }

    var recorders: [SubtreeRecorder] = []
    var focus: [FocusOp] = []
    var bounds: [(GlobalElementID, Bounds<Pixels>)] = []
    var scene: [SceneOp] = []
    var marks: [GlobalElementID] = []
    var touches: [Touch] = []
    var axNodes: [(GlobalElementID, AXNode)] = []
    var pressOnly: [(GlobalElementID, @MainActor () -> Void)] = []
    var contextMenus: [(GlobalElementID, ContextMenuRecord)] = []
    var withStates: [GlobalElementID] = []

    var current: Marks {
        Marks(focus: focus.count, bounds: bounds.count, scene: scene.count, marks: marks.count,
              touches: touches.count, axNodes: axNodes.count, pressOnly: pressOnly.count,
              contextMenus: contextMenus.count, withStates: withStates.count)
    }

    /// Marks every open recorder (or, with `scopeIndex`, every one whose own scopes include
    /// that index) as unable to leave a record, naming the first reason.
    func taint(_ reason: String, scopeIndex: Int? = nil) {
        for recorder in recorders {
            if let scopeIndex, recorder.entryHeight > scopeIndex { continue }
            if recorder.taint == nil { recorder.taint = reason }
        }
    }

    /// A shared-registration patch (`Frame.shareWithEnclosingWrappers`) reached a hitbox or an
    /// accessibility record registered before a recorder's window opened: its record would be
    /// incomplete, so it is not made.
    func notePatch(hitbox: Int?, axEmission: Int?) {
        for recorder in recorders {
            if let hitbox, hitbox < recorder.before.hitboxes, recorder.taint == nil { recorder.taint = "sharedPatch" }
            if let axEmission, axEmission < recorder.before.axEmissions, recorder.taint == nil {
                recorder.taint = "sharedPatch"
            }
        }
    }

    func noteBoundary(_ boundary: Int, _ leaves: [([CapturedPrimitive], [Int]?)], _ depth: Int) {
        for recorder in recorders where recorder.recordsScene && recorder.entryHeight == boundary {
            scene.append(SceneOp(boundary: boundary, leaves: leaves, depth: depth))
            return
        }
    }

    func noteDirect(_ primitive: CapturedPrimitive, depth: Int) {
        noteBoundary(0, [([primitive], nil)], depth)
    }
}

/// One occurrence's recording of one phase.
@MainActor
final class SubtreeRecorder {
    var taint: String?
    /// The paint scopes open where the paint window opened: the height the scene is recorded at.
    var entryHeight = 0
    /// Only the paint window records scene operations.
    var recordsScene = false
    var from = RetainLog.Marks()
    var before = LedgerSnapshot()
}

// MARK: - The ledger

/// The counts a recorder reads before and after a phase (`SB-E`, about thirty integer reads).
struct LedgerSnapshot {
    // Replayable: the difference is the product.
    var hitboxes = 0, axEmissions = 0, hitboxSpaces = 0, namedSnapshots = 0
    var hover = 0, pointerStyle = 0, key = 0, focusOnPress = 0, resign = 0
    // Pinned: a change makes the occurrence ineligible.
    var presentationRecords = 0, presentationAnchors = 0, presentationSpaces = 0
    var presentationOccurrences = 0, toolbarRecords = 0, openPopovers = 0, surfaceRequests = 0
    var unlowerable = 0, scrollKeys = 0, portals = 0, timeNotes = 0, interpolations = 0
    var accessibilityRetry = false
    /// Work a replay stands for: elements run, plus those nested hits stood for.
    var work = 0

    /// The first pinned channel that moved from `self` to `other`, or `nil`.
    func movedChannel(to other: LedgerSnapshot) -> String? {
        if presentationRecords != other.presentationRecords { return "presentationRecords" }
        if presentationAnchors != other.presentationAnchors { return "presentationAnchors" }
        if presentationSpaces != other.presentationSpaces { return "presentationSpaces" }
        if presentationOccurrences != other.presentationOccurrences { return "presentationOccurrences" }
        if toolbarRecords != other.toolbarRecords { return "toolbarRecords" }
        if openPopovers != other.openPopovers { return "openPopovers" }
        if surfaceRequests != other.surfaceRequests { return "surfaceRequests" }
        if unlowerable != other.unlowerable { return "unlowerableFields" }
        if scrollKeys != other.scrollKeys { return "scrollKeys" }
        if portals != other.portals { return "portals" }
        if timeNotes != other.timeNotes { return "timeNotes" }
        if interpolations != other.interpolations { return "interpolations" }
        if accessibilityRetry != other.accessibilityRetry { return "accessibilityRetry" }
        return nil
    }
}

// MARK: - The replay key

/// Everything prepaint and paint read that is not in the subtree (`SB-F`, spec §4.2), as flat
/// `Equatable` parts. **Every part has a separating arm in `everyKeyComponentSeparates`.**
struct AmbientKey: Equatable {
    var clip: [Float]
    var offset: [Float]
    var layerOpacityScale: [Float]
    var depths: [Int]
    var scopes: [[Double]]
    var effect: [Double]
    var namedSpaces: [NamedSpace]
    var suppression: [GlobalElementID?]
    var collectsAccessibility: Bool
    var stackAxis: ProposalStackAxis?
    var environment: EnvironmentFingerprint
    var snappingTransaction: Bool
    var disablesAnimations: Bool
}

struct ReplayKey: Equatable {
    var rects: [Float]
    var interior: Int
    var nodeCount: Int
    var ambient: AmbientKey
}

// MARK: - The record

/// One occurrence's render products (`SB-B`): everything its prepaint and paint registered,
/// recorded or journalled, replayed in registration order.
@MainActor
final class RetainedRecord {
    var key: ReplayKey
    /// `ContentMemoStore.Entry.serial` of the getter evaluation the record was made under.
    var contentSerial = 0
    /// The `@State` slots bound under the component and their versions (`SB-K`).
    var versions: [(GlobalElementID, UInt64)] = []

    // Prepaint products.
    var hitboxes: [Hitbox] = []
    var hitboxSpaces: [(Int, [NamedSpace])] = []
    var namedSnapshots = 0
    var axEmissions: [AXEmission] = []
    var axNodes: [(GlobalElementID, AXNode)] = []
    var pressOnly: [(GlobalElementID, @MainActor () -> Void)] = []
    var contextMenus: [(GlobalElementID, ContextMenuRecord)] = []
    var focus: [RetainLog.FocusOp] = []
    var bounds: [(GlobalElementID, Bounds<Pixels>)] = []
    var prepaintMarks: [GlobalElementID] = []
    var prepaintTouches: [RetainLog.Touch] = []
    var tallies = RetainedTallies()
    var prepaintWork = 0
    var owned: Set<GlobalElementID> = []

    // Paint products.
    var scene: [RetainLog.SceneOp] = []
    var paintMarks: [GlobalElementID] = []
    var paintTouches: [RetainLog.Touch] = []
    var paintWork = 0

    init(key: ReplayKey) { self.key = key }
}

struct RetainedTallies: Equatable {
    var hover = 0, pointerStyle = 0, key = 0, focusOnPress = 0, resign = 0
}

// MARK: - Observation sessions

/// One observation window of an occurrence (`SB-D`): the build recursion, prepaint or paint.
final class RetainedSession {
    let token = ContentMemoToken()
    var serial = 0

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
        entry.observedChange = true
        store.markDirty?()
    }
}

// MARK: - The build window

/// What the build recursion of one occurrence leaves for its prepaint (`SB-K`): kept in the
/// component's layout box.
@MainActor
final class RetainedBuild {
    let key: ContentMemoStore.Key
    let topNodes: [LayoutNodeID]
    let bindIDs: [GlobalElementID]
    let timeVarying: Bool

    init(key: ContentMemoStore.Key, topNodes: [LayoutNodeID], bindIDs: [GlobalElementID], timeVarying: Bool) {
        self.key = key
        self.topNodes = topNodes
        self.bindIDs = bindIDs
        self.timeVarying = timeVarying
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

    func finish(frame: Frame, key: ContentMemoStore.Key, nodes: [LayoutNodeID]) -> RetainedBuild {
        let journal = frame.stateTable.markJournal
        var seen = Set<GlobalElementID>()
        var ids: [GlobalElementID] = []
        for id in journal[journalLow...] where seen.insert(id).inserted { ids.append(id) }
        let now = frame.timeVaryingNotes &+ frame.animationStore.interpolationsSoFar
        return RetainedBuild(key: key, topNodes: nodes, bindIDs: ids, timeVarying: now != notes)
    }
}

// MARK: - The phase object

/// What the decision in prepaint hands to paint (`SB-`): carried in `ComponentPrepaint`'s box.
@MainActor
final class RetainedPhase {
    enum Mode {
        /// Replay the record's prepaint (done) and paint.
        case hit(RetainedRecord)
        /// Prepaint and paint run, recording; `old` is the record verify mode compares against.
        case record(old: RetainedRecord?)
        /// Prepaint and paint run, nothing recorded (ineligible now).
        case plain
    }

    let mode: Mode
    let build: RetainedBuild
    let entry: ContentMemoStore.Entry
    let key: ReplayKey?
    let recorder: SubtreeRecorder?
    var record: RetainedRecord?

    init(mode: Mode, build: RetainedBuild, entry: ContentMemoStore.Entry, key: ReplayKey?, recorder: SubtreeRecorder?) {
        self.mode = mode
        self.build = build
        self.entry = entry
        self.key = key
        self.recorder = recorder
    }
}

// MARK: - Frame: the key, the ledger, windows, replay

extension Frame {
    /// A snapshot of the ledger channels (`SB-E`).
    func ledgerSnapshot() -> LedgerSnapshot {
        var s = LedgerSnapshot()
        s.hitboxes = hitboxes.count
        s.axEmissions = axEmissions.count
        s.hitboxSpaces = hitboxNamedSpaces.count
        s.namedSnapshots = namedSpaceSnapshots
        s.hover = hoverRegionCount
        s.pointerStyle = pointerStyleRegionCount
        s.key = keyRegionCount
        s.focusOnPress = focusOnPressCount
        s.resign = resignRegionCount
        s.presentationRecords = presentationRecords.count
        s.presentationAnchors = presentationAnchors.count
        s.presentationSpaces = presentationSpaces.count
        s.presentationOccurrences = presentationOccurrences.count
        s.toolbarRecords = toolbarRecords.count
        s.openPopovers = openPopovers.count
        s.surfaceRequests = surfaceRequests.count
        s.unlowerable = unlowerableFields.count
        s.scrollKeys = scrollKeys.count
        s.portals = portalCount
        s.timeNotes = timeVaryingNotes
        s.interpolations = animationStore.interpolationsSoFar
        s.accessibilityRetry = wantsAccessibilityRetry
        let retained = stateTable.contentMemos.retained
        s.work = elementPrepaints &+ elementPaints &+ retained.skippedPrepaints &+ retained.skippedPaints
        return s
    }

    /// Why this occurrence cannot be keyed now, or `nil` (`SB-J`): contexts the key cannot hold.
    func retainedEntryRefusal(build: RetainedBuild) -> String? {
        if build.timeVarying { return "timeVarying" }
        if leafGroup != nil { return "leafGroup" }
        if presentationDepth != 0 { return "presentation" }
        if hasUnresolvedScrollRequests { return "scrollRequests" }
        if activeScrollContext != nil || activeScrollerFrame != nil { return "scroller" }
        if dragSourceID != nil { return "dragSource" }
        if environmentTop.customKeyCount > 0 { return "customEnvironmentKey" }
        if transactionTop.animation != nil { return "transaction" }
        if !shareCollecting.isEmpty { return "shareCollecting" }
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

    /// The ambient half of the replay key (spec §4.2).
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
        var effect: [Double] = [Double(prepaintEffects.count)]
        if let top = prepaintEffects.last {
            effect += flat(top.composed)
            if let inverse = top.inverse { effect += [1] + flat(inverse) } else { effect += [0] }
            effect += flat(top.outerClip).map(Double.init) + [Double(top.savedClipBase)]
        }
        return AmbientKey(
            clip: flat(activeClip) + [radii.topLeft.value, radii.topRight.value, radii.bottomRight.value,
                                      radii.bottomLeft.value],
            offset: [activeOffset.x.value, activeOffset.y.value],
            layerOpacityScale: [Float(activeLayer), activeOpacity, scaleFactor,
                                contentSize.width.value, contentSize.height.value],
            depths: [clipStack.count, clipBase, flatteningClipBase ?? -1, shareFloor, shareFloorAtEntry,
                     shareCandidates.count, hitTestingDisabledDepth, keyboardHiddenDepth, portalStack.last ?? -1,
                     paintScopes.count],
            scopes: scopeVectors,
            effect: effect,
            namedSpaces: namedSpaces,
            suppression: accessibilitySuppressionExceptions,
            collectsAccessibility: collectsAccessibility,
            stackAxis: stackAxis,
            environment: environmentTop.retainedFingerprint,
            snappingTransaction: transactionTop.animation == nil,
            disablesAnimations: transactionTop.disablesAnimations)
    }

    func retainedKey(build: RetainedBuild) -> ReplayKey {
        var rects: [Float] = []
        rects.reserveCapacity(build.topNodes.count * 4)
        for node in build.topNodes { rects += flat(bounds(of: node)) }
        let (hash, count) = tree.subtreeSignature(of: build.topNodes)
        return ReplayKey(rects: rects, interior: hash, nodeCount: count, ambient: retainedAmbientKey())
    }

    // MARK: Windows

    func openRecorderWindow(_ recorder: SubtreeRecorder, recordsScene: Bool) {
        if retainLog == nil { retainLog = RetainLog() }
        let log = retainLog!
        recorder.recordsScene = recordsScene
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
        log.recorders.removeAll { $0 === recorder }
        return (to, after)
    }

    func releaseRetainLogIfIdle() {
        if let log = retainLog, log.recorders.isEmpty { retainLog = nil }
    }

    // MARK: Replay

    static func axSlot(_ id: GlobalElementID) -> GlobalElementID {
        .child(of: id, at: 0, name: ElementID("$ax"))
    }

    func replayPrepaint(_ r: RetainedRecord) {
        let base = hitboxes.count
        hitboxes.append(contentsOf: r.hitboxes)
        for (offset, spaces) in r.hitboxSpaces { hitboxNamedSpaces[base + offset] = spaces }
        namedSpaceSnapshots += r.namedSnapshots
        axEmissions.append(contentsOf: r.axEmissions)
        for (id, node) in r.axNodes {
            axNodes[id] = node
            stateTable.withState(Self.axSlot(id), initial: node) { $0 = node }
            retainLog?.axNodes.append((id, node))
        }
        for (id, action) in r.pressOnly {
            accessibilityPressOnly[id] = action
            retainLog?.pressOnly.append((id, action))
        }
        for (id, record) in r.contextMenus {
            contextMenuRecords[id] = record
            retainLog?.contextMenus.append((id, record))
        }
        for op in r.focus {
            switch op {
            case .register(let handlers, let id): focusRegistry.register(handlers, id: id)
            case .shortcut(let handlers, let id): focusRegistry.registerShortcut(handlers, id: id)
            case .binding(let binding, let id): focusRegistry.registerFocusBinding(binding, id: id)
            }
            retainLog?.focus.append(op)
        }
        for (id, rect) in r.bounds {
            elementBounds[id] = rect
            retainLog?.bounds.append((id, rect))
        }
        for id in r.prepaintMarks { stateTable.mark(id) }
        for touch in r.prepaintTouches { animationStore.replay(touch) }
        hoverRegionCount += r.tallies.hover
        pointerStyleRegionCount += r.tallies.pointerStyle
        keyRegionCount += r.tallies.key
        focusOnPressCount += r.tallies.focusOnPress
        resignRegionCount += r.tallies.resign
        stateTable.contentMemos.retained.skippedPrepaints += r.prepaintWork
        stateTable.contentMemos.retained.replayedOps +=
            r.hitboxes.count + r.axEmissions.count + r.axNodes.count + r.focus.count
    }

    func replayPaint(_ r: RetainedRecord) {
        for op in r.scene { processScopes(op.leaves, from: op.boundary, depth: op.depth) }
        for id in r.paintMarks { stateTable.mark(id) }
        for touch in r.paintTouches { animationStore.replay(touch) }
        stateTable.contentMemos.retained.skippedPaints += r.paintWork
        stateTable.contentMemos.retained.replayedOps += r.scene.count
    }

    // MARK: Decision and recording

    /// The decision of `EquatableComponent.prepaintGroup` (spec §3.1): replay, record, or run
    /// plain. `nil`: not a retaining occurrence (retention off), nothing counted.
    func retainedPrepaintDecision(build: RetainedBuild) -> RetainedPhase? {
        let memos = stateTable.contentMemos
        guard let entry = memos.entry(for: build.key) else { return nil }
        guard memos.retainsSubtrees else {
            entry.record = nil
            return nil
        }
        if retainedEntryRefusal(build: build) != nil {
            entry.record = nil
            memos.retained.ineligible += 1
            return RetainedPhase(mode: .plain, build: build, entry: entry, key: nil, recorder: nil)
        }
        let key = retainedKey(build: build)
        if let old = entry.record {
            if !entry.observedChange, old.contentSerial == entry.serial, old.key == key,
               old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }),
               !retainedRecordOwnsPointerPressOrFocus(old) {
                memos.retained.hits += 1
                if retainedVerifiesFromEnvironment {
                    return RetainedPhase(mode: .record(old: old), build: build, entry: entry, key: key,
                                         recorder: SubtreeRecorder())
                }
                return RetainedPhase(mode: .hit(old), build: build, entry: entry, key: key, recorder: nil)
            }
        }
        if retainedTraces, let old = entry.record {
            var why: [String] = []
            if entry.observedChange { why.append("observed") }
            if old.contentSerial != entry.serial { why.append("serial") }
            if old.key != key {
                if old.key.rects != key.rects { why.append("rects") }
                if old.key.interior != key.interior { why.append("interior") }
                if old.key.ambient != key.ambient {
                    let a = old.key.ambient, b = key.ambient
                    if a.clip != b.clip { why.append("clip") }
                    if a.offset != b.offset { why.append("offset") }
                    if a.layerOpacityScale != b.layerOpacityScale { why.append("layerOpacityScale") }
                    if a.depths != b.depths { why.append("depths \(a.depths) \(b.depths)") }
                    if a.scopes != b.scopes { why.append("scopes") }
                    if a.effect != b.effect { why.append("effect") }
                    if a.namedSpaces != b.namedSpaces { why.append("namedSpaces") }
                    if a.suppression != b.suppression { why.append("suppression") }
                    if a.environment != b.environment {
                        let x = a.environment, y = b.environment
                        for (name, differs) in [("isEnabled", x.isEnabled != y.isEnabled), ("layoutDirection", x.layoutDirection != y.layoutDirection),
                            ("locale", x.locale != y.locale), ("dynamicTypeSize", x.dynamicTypeSize != y.dynamicTypeSize),
                            ("displayScale", x.displayScale != y.displayScale), ("controlActiveState", x.controlActiveState != y.controlActiveState),
                            ("reduceMotion", x.accessibilityReduceMotion != y.accessibilityReduceMotion),
                            ("titleBarInsets", "\(x.titleBarInsets)" != "\(y.titleBarInsets)"), ("windowSize", x.windowSize != y.windowSize),
                            ("colorScheme", x.colorScheme != y.colorScheme), ("controlSize", x.controlSize != y.controlSize),
                            ("font", x.font != y.font), ("foreground", x.foregroundStyle != y.foregroundStyle), ("theme", x.theme != y.theme),
                            ("textSystem", x.hasTextSystem != y.hasTextSystem), ("objects", x.objects != y.objects), ("custom", x.customKeyCount != y.customKeyCount)]
                        where differs { why.append("env.\(name)") }
                    }
                    if a.collectsAccessibility != b.collectsAccessibility { why.append("collects") }
                }
            }
            if !old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }) { why.append("versions") }
            if retainedRecordOwnsPointerPressOrFocus(old) { why.append("pointer/focus/active") }
            print("retained miss \(build.key.id) \(why)")
        }
        if retainedTraces, entry.record == nil {
            print("retained first-or-dropped \(sbPath(build.key.id))")
        }
        entry.record = nil
        return RetainedPhase(mode: .record(old: nil), build: build, entry: entry, key: key, recorder: SubtreeRecorder())
    }

    func retainedRecordOwnsPointerPressOrFocus(_ record: RetainedRecord) -> Bool {
        if let focused = focusedElement, record.owned.contains(focused) { return true }
        if let active = activeElement, record.owned.contains(active) { return true }
        if let point = mousePosition, record.hitboxes.contains(where: { $0.contains(point) }) { return true }
        return false
    }

    /// Closes the prepaint window of a recording phase and keeps what it produced.
    func finishRetainedPrepaint(_ phase: RetainedPhase) {
        guard let recorder = phase.recorder, let key = phase.key else { return }
        let (to, after) = closeRecorderWindow(recorder)
        let log = retainLog!
        let from = recorder.from
        let before = recorder.before
        let record = RetainedRecord(key: key)
        record.versions = phase.build.bindIDs.map { ($0, stateTable.entryVersion($0)) }
        record.contentSerial = phase.entry.serial
        record.hitboxes = Array(hitboxes[before.hitboxes..<after.hitboxes])
        for index in before.hitboxes..<after.hitboxes {
            if let spaces = hitboxNamedSpaces[index] { record.hitboxSpaces.append((index - before.hitboxes, spaces)) }
        }
        record.namedSnapshots = after.namedSnapshots - before.namedSnapshots
        record.axEmissions = Array(axEmissions[before.axEmissions..<after.axEmissions])
        record.axNodes = Array(log.axNodes[from.axNodes..<to.axNodes])
        record.pressOnly = Array(log.pressOnly[from.pressOnly..<to.pressOnly])
        record.contextMenus = Array(log.contextMenus[from.contextMenus..<to.contextMenus])
        record.focus = Array(log.focus[from.focus..<to.focus])
        record.bounds = Array(log.bounds[from.bounds..<to.bounds])
        record.prepaintMarks = Array(log.marks[from.marks..<to.marks])
        record.prepaintTouches = Array(log.touches[from.touches..<to.touches])
        record.tallies = RetainedTallies(hover: after.hover - before.hover,
                                         pointerStyle: after.pointerStyle - before.pointerStyle,
                                         key: after.key - before.key,
                                         focusOnPress: after.focusOnPress - before.focusOnPress,
                                         resign: after.resign - before.resign)
        record.prepaintWork = after.work - before.work
        // The state a prepaint wrote must be the accessibility retention slots and nothing else.
        let allowed = Set(record.axNodes.map { Self.axSlot($0.0) })
        for id in log.withStates[from.withStates..<to.withStates] where !allowed.contains(id) {
            if recorder.taint == nil { recorder.taint = "stateWrite" }
        }
        // A hitbox that scrolls registered a scroll region.
        if record.hitboxes.contains(where: { $0.scroll != nil }), recorder.taint == nil { recorder.taint = "scrollRegion" }
        var owned = Set<GlobalElementID>()
        for box in record.hitboxes { owned.insert(box.id) }
        for op in record.focus {
            switch op {
            case .register(_, let id), .shortcut(_, let id), .binding(_, let id): owned.insert(id)
            }
        }
        for (id, _) in record.axNodes { owned.insert(id) }
        record.owned = owned
        phase.record = record
        releaseRetainLogIfIdle()
    }

    /// Opens the paint window of a recording phase.
    func beginRetainedPaint(_ phase: RetainedPhase) {
        guard let recorder = phase.recorder else { return }
        openRecorderWindow(recorder, recordsScene: true)
    }

    /// Closes the paint window; stores the record, or counts why not.
    func finishRetainedPaint(_ phase: RetainedPhase) {
        guard let recorder = phase.recorder, let record = phase.record else { return }
        let (to, after) = closeRecorderWindow(recorder)
        let log = retainLog!
        let from = recorder.from
        let before = recorder.before
        record.scene = log.scene[from.scene..<to.scene].filter { $0.boundary == recorder.entryHeight }
        record.paintMarks = Array(log.marks[from.marks..<to.marks])
        record.paintTouches = Array(log.touches[from.touches..<to.touches])
        record.paintWork = after.work - before.work
        if !log.withStates[from.withStates..<to.withStates].isEmpty, recorder.taint == nil {
            recorder.taint = "stateWrite"
        }
        releaseRetainLogIfIdle()
        let memos = stateTable.contentMemos
        if case .record(let old) = phase.mode, let old {
            // Verify mode: the record made now must equal the one a replay would have used.
            if let reason = recorder.taint {
                preconditionFailure("METALUI_VERIFY_RETAINED: a replayed subtree is ineligible now (\(reason))")
            }
            if let difference = old.differences(from: record) {
                preconditionFailure("METALUI_VERIFY_RETAINED: replay differs from a fresh run: \(difference)")
            }
            phase.entry.record = record
            return
        }
        if let reason = recorder.taint {
            if retainedTraces {
                print("retained ineligible \(sbPath(phase.build.key.id).suffix(60)) because \(reason)")
            }
            phase.entry.record = nil
            memos.retained.ineligible += 1
            return
        }
        memos.retained.misses += 1
        if retainedRecordOwnsPointerPressOrFocus(record) {
            if retainedTraces {
                print("retained volatile \(sbPath(phase.build.key.id)) boxes=\(record.hitboxes.map { "\($0.bounds)" }) mouse=\(String(describing: mousePosition))")
            }
            phase.entry.record = nil
        } else {
            phase.entry.record = record
            phase.entry.observedChange = false
        }
    }
}

// MARK: - Verify mode

extension RetainedRecord {
    /// How `other` (a fresh run's record) differs from this one, or `nil` (`SB-M`): bounds, ids,
    /// layers, scene operations and registration order, element for element.
    func differences(from other: RetainedRecord) -> String? {
        func describe(_ boxes: [Hitbox]) -> [String] {
            boxes.map { box in
                let handlers = Mirror(reflecting: box.handlers).children.map { child -> String in
                    let m = Mirror(reflecting: child.value)
                    return m.displayStyle == .optional && m.children.isEmpty ? "-" : "+"
                }.joined()
                return "\(box.id)|\(box.bounds)|\(box.layer)|\(box.opaque)|\(String(describing: box.scroll))|\(box.origin)|\(String(describing: box.transform?.inverse))|\(String(describing: box.transform?.outerClip))|\(box.contextualEnabled)|\(handlers)"
            }
        }
        if describe(hitboxes) != describe(other.hitboxes) { return "hitboxes" }
        if axEmissions.count != other.axEmissions.count { return "axEmissions.count" }
        for (a, b) in zip(axEmissions, other.axEmissions)
        where "\(a.id)|\(String(describing: a.text))|\(a.geometry)|\(a.portal)|\(a.isEnabled)|\(a.isClickable)"
            != "\(b.id)|\(String(describing: b.text))|\(b.geometry)|\(b.portal)|\(b.isEnabled)|\(b.isClickable)" {
            return "axEmissions"
        }
        if axNodes.map({ "\($0.0)" }) != other.axNodes.map({ "\($0.0)" }) { return "axNodes" }
        if focus.count != other.focus.count { return "focus.count" }
        for (a, b) in zip(focus, other.focus) {
            switch (a, b) {
            case (.register(_, let x), .register(_, let y)), (.shortcut(_, let x), .shortcut(_, let y)),
                 (.binding(_, let x), .binding(_, let y)):
                if x != y { return "focus order" }
            default: return "focus kind"
            }
        }
        if bounds.count != other.bounds.count { return "bounds.count" }
        if zip(bounds, other.bounds).contains(where: { $0.0 != $1.0 || "\($0.1)" != "\($1.1)" }) { return "bounds" }
        if tallies != other.tallies { return "tallies" }
        if prepaintMarks != other.prepaintMarks { return "prepaint marks" }
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
        if prepaintWork != other.prepaintWork { return "prepaintWork \(prepaintWork) vs \(other.prepaintWork)" }
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
