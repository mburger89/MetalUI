import Foundation
import MetalUICore
import MetalUILayout

// C14b-2 lane 2 (`RK-A`, `RK-B`, `RK-F`, `RK-X`…): the graft. An `.equatable()` occurrence whose content memo hit,
// whose prepaint ledger and paint record are valid and whose build-visible context is equal does not run its
// build recursion: the rows its last build registered (`LayoutSegment`) are appended to the new tree, the
// **build journal** (the calls that build made on the `StateTable`, the transition and animation stores and the
// content memo, in order) is applied again through those stores' own functions, and the occurrence hands back a
// `ComponentLayout` with no element payload (`RK-B`): its prepaint and paint are replays, and a replay that
// cannot be taken asks the window to build the frame again with every replay off (`RK-C`, `RK-D`).
// Spec `docs/superpowers/specs/2026-10-13-retained-build-skip-design.md` §2 (M2), rulings
// `docs/superpowers/2026-10-13-retained-build-skip-decisions.md`.

// MARK: - The journal

/// The calls a build recorded while an occurrence's window was open (`RK-F`), in order, shared by every open
/// window: a window remembers the length where it opened and keeps the slice. **Nothing is appended while no
/// window is open**, so a frame that grafts nothing pays one integer test per funnel.
@MainActor
final class BuildJournal {
    enum Event {
        case mark(GlobalElementID)
        case produced(GlobalElementID)
        case absent(GlobalElementID)
        case named(GlobalElementID, Int)
        case loop(GlobalElementID, Int)
        case windowedParent(GlobalElementID)
        case focusState(any FocusStateReconciling, GlobalElementID)
        /// A `withState` on an animation baseline: the entry stays live, its value is what the build wrote.
        case liveState(GlobalElementID)
        /// A read-only or peeked entry and the version it had (`RW-D`): replayed as a read, checked by the graft.
        case stateRead(GlobalElementID, UInt64)
        case memoTouch(ContentMemoStore.Key)
        case animationTouch(GlobalElementID)
        case transitionEvaluated(GlobalElementID, Animation?)
        case transitionProduced(GlobalElementID, GlobalElementID, Bool)
        case transitionArray(GlobalElementID, Int)
        /// A lifecycle scope's store note: `(write, scope, owner, order)` (`RL-C`). The order is the build's while the journal
        /// records and relative to the window's first reserved order in a `GraftRecord`.
        case lifecycleNote(LifecycleWrite?, GlobalElementID, GlobalElementID, Int)
        /// A closed code-driven menu's presentation record (`RW-V`): replayed as the same note, and checked by the graft
        /// (its binding must still read closed).
        case presentationNote(PresentationRecord)
        /// A window preference the build reported (`RW-X`): replayed through the same first-wins report.
        case windowPreference(WindowPreferenceReport)
        /// The scroll context a layout read, and the depth of the context stack it was read at (record 419): checked by the graft against the
        /// context in effect where the occurrence sits, for the reads made outside every scroller the occurrence itself opens.
        case scrollContextRead(ScrollContext?, Int)
    }

    var events: [Event] = []
    /// The open windows, outermost first.
    var open: [GraftRecorder] = []
    /// The closed windows whose graft records are not made yet (`RK-AH`): each holds a range of `events`, so the journal is not
    /// cleared while any is pending. `ContentMemoStore.pendingGrafts` keeps it equal to its own count.
    var held = 0

    /// Empties the events (the capacity stays) when no window is open and no closed window still reads them. The buffer is
    /// uniquely referenced here: nothing keeps a slice of it, so the clear allocates nothing.
    func clearIfIdle() {
        if open.isEmpty && held == 0 { events.removeAll(keepingCapacity: true) }
    }

    /// The events of `range` as a graft record keeps them: a lifecycle note's order is relative to the window's first reserved
    /// order (`RL-C`). One copy, made for a window that earned a record (`RK-AH`).
    func rebased(_ range: Range<Int>, lifecycleBase: Int) -> [Event] {
        var out: [Event] = []
        out.reserveCapacity(steadyCapacity(range.count))   // `G52`
        for index in range {
            if case .lifecycleNote(let write, let scope, let owner, let order) = events[index] {
                out.append(.lifecycleNote(write, scope, owner, order - lifecycleBase))
            } else {
                out.append(events[index])
            }
        }
        return out
    }

    var isRecording: Bool { !open.isEmpty }

    @inline(__always)
    func record(_ event: @autoclosure () -> Event) {
        if !open.isEmpty { events.append(event()) }
    }

    /// Marks every open window as unable to leave a graft record, naming the first reason.
    func taint(_ reason: String) {
        for recorder in open where recorder.taint == nil { recorder.taint = reason }
    }
}

/// One occurrence's open build window.
@MainActor
final class GraftRecorder {
    var taint: String?
    var start = 0
    var lower = 0
    var orderStart = 0
    var requests = 0
    var audit = BuildAudit()
    /// `LifecycleStore.nextRegistrationOrder` where the window opened (`RL-C`).
    var lifecycleBase = 0
}

// MARK: - The key and the record

/// Everything the build recursion of an occurrence reads that is not in the occurrence's value (`RK-C`): the
/// built-in environment, the scale and window size (also in the fingerprint), the transaction, the stack axis
/// a linear container pushed, the accessibility and bounds recording flags and the depths of the scopes the
/// build keys its records by. **Optimistic by design:** what the build cannot see (the occurrence's absolute
/// rects, the paint-only ambient) is checked at prepaint and paint, and a mismatch there is the redo.
struct BuildKey: Equatable {
    /// Shared by reference with the prepaint and paint keys of the frame (`G47`).
    var shared: SharedFingerprint
    var scale: Float
    var contentSize: Size<Pixels>
    var snapping: Bool
    var disablesAnimations: Bool
    var stackAxis: ProposalStackAxis?
    var collectsAccessibility: Bool
    var depths: [Int]
    /// `GlyphAtlas.layoutGeneration` (`GL-D`). A graft does not paint, but it stands for a build whose paint the
    /// prepaint key (which carries the generation) will refuse after a rebuild: a graft the prepaint then refuses is
    /// a redo of the whole frame (`RK-C`), so it is refused here, one decision earlier and at no cost.
    var atlasGeneration = 0

    init(shared: SharedFingerprint, scale: Float, contentSize: Size<Pixels>, snapping: Bool, disablesAnimations: Bool,
         stackAxis: ProposalStackAxis?, collectsAccessibility: Bool, depths: [Int], atlasGeneration: Int = 0) {
        self.shared = shared; self.scale = scale; self.contentSize = contentSize; self.snapping = snapping
        self.disablesAnimations = disablesAnimations; self.stackAxis = stackAxis
        self.collectsAccessibility = collectsAccessibility; self.depths = depths; self.atlasGeneration = atlasGeneration
    }

    init(environment: EnvironmentFingerprint, scale: Float, contentSize: Size<Pixels>, snapping: Bool, disablesAnimations: Bool,
         stackAxis: ProposalStackAxis?, collectsAccessibility: Bool, depths: [Int], atlasGeneration: Int = 0) {
        self.init(shared: SharedFingerprint(environment), scale: scale, contentSize: contentSize, snapping: snapping,
                  disablesAnimations: disablesAnimations, stackAxis: stackAxis, collectsAccessibility: collectsAccessibility,
                  depths: depths, atlasGeneration: atlasGeneration)
    }

    var environment: EnvironmentFingerprint {
        get { shared.value }
        set { shared = SharedFingerprint(newValue) }
    }
}

/// The counts of the channels a build can write that the journal does not replay (`RK-F`): any that moves between
/// a window's open and close makes the occurrence graft-ineligible, by the channel's name.
struct BuildAudit: Equatable {
    var timeVarying = 0, presentations = 0, hiddenNodes = 0
    var scrollKeys = 0, elementBounds = 0, presentationRecords = 0, toolbarRecords = 0
    var colorScheme = 0, limits = 0, anotherFrame = 0, unlowerable = 0
    var lifecycle = 0, timeline = 0, transitions = 0, matched = 0, surfaces = 0, hasScrollRequests = 0
    /// `ViewThatFits` containers registered (`VF-H`): their spans, elisions and retractions are made by the build.
    var fitContainers = 0

    func movedChannel(to other: BuildAudit) -> String? {
        if timeVarying != other.timeVarying { return "timeVarying" }
        if presentations != other.presentations || presentationRecords != other.presentationRecords { return "presentation" }
        if hiddenNodes != other.hiddenNodes { return "hiddenNodes" }
        if scrollKeys != other.scrollKeys { return "scrollKeys" }
        if elementBounds != other.elementBounds { return "elementBounds" }
        if toolbarRecords != other.toolbarRecords { return "toolbar" }
        if colorScheme != other.colorScheme { return "colorScheme" }
        if limits != other.limits { return "contentLimits" }
        if anotherFrame != other.anotherFrame { return "anotherFrame" }
        if unlowerable != other.unlowerable { return "unlowerable" }
        if lifecycle != other.lifecycle { return "lifecycle" }
        if timeline != other.timeline { return "timeline" }
        if transitions != other.transitions { return "transitionGroup" }
        if matched != other.matched { return "matchedGeometry" }
        if surfaces != other.surfaces { return "surface" }
        if fitContainers != other.fitContainers { return "viewThatFits" }
        return nil
    }
}

/// What an occurrence's closed window leaves for `flushPendingGrafts` to make a record of (`RK-AG`).
struct PendingGraft {
    let entry: ContentMemoStore.Entry
    let marks: SegmentMarks
    let key: BuildKey
    let contentSerial: Int
    /// The window's slice of the journal, not copied (`RK-AH`): `flushPendingGrafts` copies it for an occurrence that earned a
    /// record, and the journal is not cleared until then (`BuildJournal.held`).
    let events: Range<Int>
    let lifecycleBase: Int
    let requests: Int
    let lifecycleOrders: Int
    var topItems: [(index: Int, item: LoweredItem, originOffset: Int?)] = []

    init(entry: ContentMemoStore.Entry, marks: SegmentMarks, key: BuildKey, contentSerial: Int,
         events: Range<Int>, lifecycleBase: Int, requests: Int, lifecycleOrders: Int) {
        self.entry = entry; self.marks = marks; self.key = key; self.contentSerial = contentSerial
        self.events = events; self.lifecycleBase = lifecycleBase
        self.requests = requests; self.lifecycleOrders = lifecycleOrders
    }
}

/// What a recorded build leaves for a later frame to graft (`RK-B`, `RK-F`), one per memo entry.
@MainActor
final class GraftRecord {
    let key: BuildKey
    /// `ContentMemoStore.Entry.serial` of the getter evaluation the build ran under.
    let contentSerial: Int
    var segment: LayoutSegment
    var events: [BuildJournal.Event]
    /// The lifecycle orders the build reserved, scopes with no content included (`RL-C`).
    var lifecycleOrders = 0
    /// `Frame.elementRequests` the build made: what a graft stands for.
    let requests: Int
    /// Nested occurrences' memo entries, `@State` entries kept live and animation entries touched: they must
    /// still be there, and the nested entries unchanged, for the graft to stand (`RK-F`).
    let nestedKeys: [ContentMemoStore.Key]
    let liveStates: [GlobalElementID]
    let animationIDs: [GlobalElementID]
    /// The entries the build read and their versions (`RW-D`), from the journal's `.stateRead` events.
    let stateReads: [(GlobalElementID, UInt64)]
    /// The closed menus' records the build noted (`RW-V`): the graft stands only while each binding still reads closed.
    let presentationNotes: [PresentationRecord]
    /// The lowered-item records of the top-level nodes, by top index (`RK-F`): a legacy top is consumed by its parent
    /// container after the occurrence returns, so the graft records it again for the new node. The interior
    /// records are consumed and never read again.
    var topItems: [(index: Int, item: LoweredItem, originOffset: Int?)] = []

    init(key: BuildKey, contentSerial: Int, segment: LayoutSegment, events: [BuildJournal.Event], requests: Int) {
        self.key = key
        self.contentSerial = contentSerial
        self.segment = segment
        self.events = events
        self.requests = requests
        var nested: [ContentMemoStore.Key] = []
        var live: [GlobalElementID] = []
        var animation: [GlobalElementID] = []
        var reads: [(GlobalElementID, UInt64)] = []
        var notes: [PresentationRecord] = []
        for event in events {
            switch event {
            case .memoTouch(let key): nested.append(key)
            case .liveState(let id): live.append(id)
            case .stateRead(let id, let version): reads.append((id, version))
            case .animationTouch(let id): animation.append(id)
            case .presentationNote(let note): notes.append(note)
            default: break
            }
        }
        nestedKeys = nested
        liveStates = live
        animationIDs = animation
        stateReads = reads
        presentationNotes = notes
    }
}

// MARK: - Frame: key, audit, window

extension Frame {
    func graftBuildKey() -> BuildKey {
        BuildKey(shared: sharedEnvironmentFingerprint(), scale: scaleFactor, contentSize: contentSize,
                 snapping: transactionTop.animation == nil, disablesAnimations: transactionTop.disablesAnimations,
                 stackAxis: stackAxis, collectsAccessibility: collectsAccessibility,
                 depths: [lifecycleDepth, presentationDepth, transactionDepth, animationStore.keyframeDepth,
                          activeScrollContext == nil ? 0 : 1],
                 atlasGeneration: glyphAtlas.layoutGeneration)
    }

    func buildAudit() -> BuildAudit {
        var a = BuildAudit()
        a.timeVarying = timeVaryingNotes &+ animationStore.interpolationsSoFar
        a.presentations = lowering.presentations.count
        a.hiddenNodes = hiddenNodes.count
        a.scrollKeys = scrollKeyCount
        a.elementBounds = elementBounds.count
        a.presentationRecords = presentationRecords.count - journaledPresentationNotes
        a.toolbarRecords = toolbarRecords.count
        a.colorScheme = collectedColorSchemePreference == nil ? 0 : 1
        a.limits = (contentMinimum == nil ? 0 : 1) + (contentMaximum == nil ? 0 : 1)
        a.anotherFrame = (wantsAnotherFrame ? 1 : 0) + (hasActiveAnimations ? 1 : 0)
        a.unlowerable = unlowerableFields.count
        a.lifecycle = animationStore.lifecycle.buildActivity
        a.timeline = animationStore.timeline.buildActivity
        a.transitions = animationStore.transitions.buildActivity
        a.matched = animationStore.matched.buildActivity
        a.surfaces = surfaceRegistry.buildActivity
        a.fitContainers = fitSpans.count
        return a
    }

    /// Opens the journal window of an occurrence about to run its build recursion.
    func openGraftWindow() -> GraftRecorder {
        let journal = stateTable.contentMemos.journal
        if animationStore.buildJournal !== journal { animationStore.attach(journal) }
        let recorder = GraftRecorder()
        recorder.start = journal.events.count
        recorder.lower = tree.nodeCount
        recorder.orderStart = lowering.order.count
        recorder.requests = elementRequests &+ stateTable.contentMemos.retained.skippedRequests
        recorder.audit = buildAudit()
        recorder.lifecycleBase = animationStore.lifecycle.nextRegistrationOrder
        // `VF-H`: a window opened inside a `ViewThatFits` candidate would stand for a build whose notes a graft
        // cannot journal for retraction.
        if fitDepth > 0 { recorder.taint = "viewThatFits" }
        journal.open.append(recorder)
        return recorder
    }

    /// Closes the window and answers what the occurrence's build left to capture, or `nil` with the name of what stopped it.
    /// **The copy of the rows is not made here** (`RK-AG`): the marks, the journal and the top-level items are taken now, because a
    /// container built after this occurrence may write to them; the children and kernel cases, which nothing writes after
    /// registration, are copied by `flushPendingGrafts` at the end of the frame, and only for an occurrence whose paint and
    /// prepaint left records, the only kind a later frame can graft from.
    func closeGraftWindow(_ recorder: GraftRecorder, entry: ContentMemoStore.Entry, tops: [LayoutNodeID], contentSerial: Int,
                          key: BuildKey) -> (pending: PendingGraft?, refusal: String?) {
        let journal = stateTable.contentMemos.journal
        journal.open.removeAll { $0 === recorder }
        defer { journal.clearIfIdle() }
        if let reason = recorder.taint { return (nil, reason) }
        if let moved = recorder.audit.movedChannel(to: buildAudit()) { return (nil, moved) }
        let (marks, refusal) = tree.captureSegmentMarks(from: recorder.lower, tops: tops)
        guard let marks else { return (nil, refusal ?? "segment") }
        var pending = PendingGraft(entry: entry, marks: marks, key: key, contentSerial: contentSerial,
                                   events: recorder.start..<journal.events.count, lifecycleBase: recorder.lifecycleBase,
                                   requests: elementRequests &+ stateTable.contentMemos.retained.skippedRequests - recorder.requests,
                                   lifecycleOrders: animationStore.lifecycle.nextRegistrationOrder - recorder.lifecycleBase)
        // Items of the nodes the window registered: a top's is carried, an interior one must be consumed (a record no
        // container consumed would be reported by name at the end of the frame, `LR-AQ`: not a graft's to hide).
        let range = recorder.lower..<tree.nodeCount
        for node in lowering.order[recorder.orderStart...] {
            guard let item = lowering.items[node] else { continue }
            let index = tree.nodeIndex(of: node)
            guard range.contains(index) else { continue }   // a forwarded record keyed at an outer node: not ours
            if let topIndex = tops.firstIndex(of: node) {
                var offset: Int?
                if let origin = item.origin {
                    let originIndex = tree.nodeIndex(of: origin)
                    guard range.contains(originIndex) else { return (nil, "itemOriginOutside") }
                    offset = originIndex - recorder.lower
                }
                pending.topItems.append((topIndex, item, offset))
            } else if !item.consumed, item.kind != .presentation, item.reportsFieldsIfUnconsumed {
                return (nil, "interiorItemUnconsumed")   // diagnostics would report it; a graft must not hide that
            }
        }
        journal.held += 1   // released when `pendingGrafts` empties (`RK-AH`)
        return (pending, nil)
    }

    /// Makes the records of the occurrences whose windows closed this frame (`RK-AG`), at the end of the frame, after paint:
    /// a record a later frame cannot graft from is not made. **Exact:** `graftRecord` answers `nil` unless the entry holds a paint
    /// record with a prepaint ledger and complete coverage, and nothing writes those between this point and that call but the
    /// paint of an occurrence the later build has already passed; an entry that holds none now cannot graft in the frame after
    /// this one, whether a graft record exists or not.
    func flushPendingGrafts() {
        let memos = stateTable.contentMemos
        guard !memos.pendingGrafts.isEmpty else { return }
        let pending = memos.pendingGrafts
        // The journal's events are read below and cleared when the list empties (`RK-AH`).
        defer { memos.pendingGrafts = [] }
        for item in pending {
            let entry = item.entry
            guard let record = entry.record, record.prepaint != nil, record.coverageComplete,
                  record.focusedUnder == nil, record.prepaint?.focusedUnder == nil else {
                memos.retained.graftCapturesSkipped += 1
                continue
            }
            memos.retained.graftCaptures += 1
            let (segment, refusal) = tree.completeSegment(item.marks)
            guard let segment else {
                entry.graft = nil
                memos.retained.noteIneligible(.graft, reason: refusal ?? "segment")
                memos.graftRefusals.append(refusal ?? "segment")
                RetainedTrace.emit("retained graft ineligible \(entry.id.map { RetainedTrace.path($0) } ?? "?") because \(refusal ?? "?")")
                continue
            }
            let events = memos.journal.rebased(item.events, lifecycleBase: item.lifecycleBase)
            let graft = GraftRecord(key: item.key, contentSerial: item.contentSerial, segment: segment, events: events,
                                    requests: item.requests)
            graft.lifecycleOrders = item.lifecycleOrders
            graft.topItems = item.topItems
            entry.graft = graft
        }
    }

    /// Applies a journal through the stores' own functions (`RK-F`): the calls the build made, in the order it made them.
    func reapply(_ events: [BuildJournal.Event], lifecycleOrders: Int = 0) {
        let memos = stateTable.contentMemos
        let lifecycleBase = animationStore.lifecycle.nextRegistrationOrder
        for event in events {
            switch event {
            case .mark(let id): stateTable.mark(id)
            case .produced(let slot): stateTable.noteProduced(slot)
            case .absent(let slot): stateTable.noteAbsent(slot)
            case .named(let id, let index): stateTable.noteNamed(id, at: index)
            case .loop(let slot, let extent): stateTable.noteLoop(slot, extent: extent)
            case .windowedParent(let parent): stateTable.noteWindowedParent(parent)
            case .focusState(let state, let slot): stateTable.noteFocusState(state, at: slot)
            case .liveState(let id): stateTable.markLive(id)
            case .stateRead(let id, _): stateTable.noteRead(id)
            case .memoTouch(let key): memos.touch(key)
            case .animationTouch(let id): animationStore.touch(id)
            case .transitionEvaluated(let slot, let animation): animationStore.transitions.replayEvaluated(slot, animation)
            case .transitionProduced(let unit, let evaluator, let fades): animationStore.transitions.replayProduced(unit, evaluator, fades)
            case .transitionArray(let slot, let extent): animationStore.transitions.replayArray(slot, extent)
            case .lifecycleNote(let write, let scope, let owner, let order):
                animationStore.lifecycle.note(write, scope: scope, owner: owner, order: lifecycleBase + order)   // `RL-A`, `RL-C`
            case .presentationNote(let note): replayPresentationNote(note)   // `RW-V`
            case .windowPreference(let report): reportWindowPreference(report)   // `RW-X`
            case .scrollContextRead: stateTable.contentMemos.journal.record(event)   // an enclosing window depends on it too
            }
        }
        animationStore.lifecycle.advanceOrder(by: lifecycleOrders)
    }

    /// Whether the entries a graft record depends on are all still there and unchanged (`RK-F`).
    func graftDependenciesHold(_ record: GraftRecord) -> Bool {
        let memos = stateTable.contentMemos
        for key in record.nestedKeys {
            guard let entry = memos.entry(for: key), !entry.stale, !entry.observedChange else { return false }
        }
        for id in record.liveStates where !stateTable.hasEntry(id) { return false }
        for id in record.animationIDs where !animationStore.hasEntry(id) { return false }
        for (id, version) in record.stateReads where stateTable.entryVersion(id) != version { return false }
        // A lazy container, a `List` or a table body read the scroller's offset while it windowed: the graft stands only while that scroller still says the same.
        for case .scrollContextRead(let context, let depth) in record.events where depth <= scrollContextDepth && context != activeScrollContext { return false }
        // `RW-V`: a menu opened from code since the build (its binding turned true) is a presentation: the build runs.
        for note in record.presentationNotes where note.isPresented.wrappedValue != note.isShown { return false }
        return true
    }
}

// MARK: - The marker

/// What a grafted occurrence leaves instead of an element payload (`RK-B`): its prepaint and paint can only be replays.
@MainActor
final class RetainedGraft {
    let record: GraftRecord
    init(record: GraftRecord) { self.record = record }
}


// MARK: - The decision and the graft

extension Frame {
    /// The graft record this occurrence may stand on in this build, or `nil` (`RK-B`, `RK-C`): its paint record, prepaint
    /// ledger and graft record all describe the content it holds now, nothing it reads moved, and the prepaint
    /// and paint decisions the occurrence will face cannot be known to fail. The rects and the paint-only
    /// ambient are **not** known here: a mismatch is the redo (`RK-C`, `RK-D`).
    func graftRecord(for entry: ContentMemoStore.Entry, id: GlobalElementID, key: BuildKey) -> GraftRecord? {
        let memos = stateTable.contentMemos
        guard memos.graftAllowed, let graft = entry.graft, let old = entry.record, let ledger = old.prepaint else {
            return nil
        }

        // A ledger holding a geometry note a translation cannot recompute would redo the whole frame and back replay off for eight
        // builds (`RG-J`): the refusal stays for such a ledger only (`RL-G`); a recomputable one moves like any other.
        if !geometryNotesRecomputable(ledger) { memos.graftRefusals.append("geometryGraft"); return nil }
        // `RK-AM`, `RK-AN`: at, under or above the failing occurrences of a scoped redo, or under a scope still quarantined, the build runs.
        if memos.isInRedoScope(id) || memos.isInQuarantinedScope(id) { memos.graftRefusals.append("scopedRedo"); return nil }
        guard entry.quarantineUntil <= memos.buildSerial, !entry.observedChange, old.coverageComplete,
              old.contentSerial == entry.serial, graft.contentSerial == entry.serial, graft.key == key else {
            return nil
        }
        // No `uncomparableCustomCount` conjunct (C14-c4, `FS-H`): an uncomparable custom reading equals nothing, itself
        // included, so `BuildKey.environment` never equals the key a record under it was made with (`graft.key == key`
        // above), and the paint and prepaint refusals leave such an occurrence no record to stand on.
        guard prepaintRefusal() == nil, transactionTop.animation == nil else {
            return nil
        }
        guard old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }) else { return nil }
        guard !retainedSubtreeHasPointerPressOrFocus(under: id), !retainedPointerIsInside(ledger) else { return nil }
        // `RK-AQ`: a record or a ledger made under a focus is not a graft's to stand on (a graft under a steady focus is carried over).
        guard old.focusedUnder == nil, ledger.focusedUnder == nil else { return nil }
        guard graftDependenciesHold(graft) else { return nil }
        return graft
    }

    /// Stands `record` in for the build recursion (`RK-B`): its rows are appended under this tree's generation, the
    /// journal is applied again, the counters say what was skipped. Answers the new top-level nodes.
    func graftOccurrence(_ record: GraftRecord) -> [LayoutNodeID] {
        let tops = tree.graft(record.segment)
        // The top-level nodes' lowered items, for the parent container that consumes them (`RK-F`).
        if !record.topItems.isEmpty {
            let first = tree.nodeCount - record.segment.nodeCount
            for (index, item, offset) in record.topItems {
                var carried = item
                if let offset { carried.origin = tree.nodeID(atIndex: first + offset) }
                lowering.record(carried, for: tops[index])
            }
        }
        reapply(record.events, lifecycleOrders: record.lifecycleOrders)
        let retained = stateTable.contentMemos.retained
        _ = retained
        stateTable.contentMemos.retained.grafts += 1
        stateTable.contentMemos.retained.skippedRequests += record.requests
        stateTable.contentMemos.retained.graftedNodes += record.segment.nodeCount
        for node in tops { tree.markPlacementRoot(node) }
        return tops
    }
}
