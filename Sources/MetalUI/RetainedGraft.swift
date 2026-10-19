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
        case transitionProduced(GlobalElementID, GlobalElementID)
        case transitionArray(GlobalElementID, Int)
    }

    var events: [Event] = []
    /// The open windows, outermost first.
    var open: [GraftRecorder] = []

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
}

// MARK: - The key and the record

/// Everything the build recursion of an occurrence reads that is not in the occurrence's value (`RK-C`): the
/// built-in environment, the scale and window size (also in the fingerprint), the transaction, the stack axis
/// a linear container pushed, the accessibility and bounds recording flags and the depths of the scopes the
/// build keys its records by. **Optimistic by design:** what the build cannot see (the occurrence's absolute
/// rects, the paint-only ambient) is checked at prepaint and paint, and a mismatch there is the redo.
struct BuildKey: Equatable {
    var environment: EnvironmentFingerprint
    var scale: Float
    var contentSize: Size<Pixels>
    var snapping: Bool
    var disablesAnimations: Bool
    var stackAxis: ProposalStackAxis?
    var collectsAccessibility: Bool
    var depths: [Int]
}

/// The counts of the channels a build can write that the journal does not replay (`RK-F`): any that moves between
/// a window's open and close makes the occurrence graft-ineligible, by the channel's name.
struct BuildAudit: Equatable {
    var timeVarying = 0, presentations = 0, hiddenNodes = 0
    var scrollKeys = 0, elementBounds = 0, presentationRecords = 0, toolbarRecords = 0, openURLs = 0
    var navigation = 0, colorScheme = 0, limits = 0, anotherFrame = 0, unlowerable = 0
    var lifecycle = 0, timeline = 0, transitions = 0, surfaces = 0, hasScrollRequests = 0

    func movedChannel(to other: BuildAudit) -> String? {
        if timeVarying != other.timeVarying { return "timeVarying" }
        if presentations != other.presentations || presentationRecords != other.presentationRecords { return "presentation" }
        if hiddenNodes != other.hiddenNodes { return "hiddenNodes" }
        if scrollKeys != other.scrollKeys { return "scrollKeys" }
        if elementBounds != other.elementBounds { return "elementBounds" }
        if toolbarRecords != other.toolbarRecords { return "toolbar" }
        if openURLs != other.openURLs || navigation != other.navigation { return "windowMetadata" }
        if colorScheme != other.colorScheme { return "colorScheme" }
        if limits != other.limits { return "contentLimits" }
        if anotherFrame != other.anotherFrame { return "anotherFrame" }
        if unlowerable != other.unlowerable { return "unlowerable" }
        if lifecycle != other.lifecycle { return "lifecycle" }
        if timeline != other.timeline { return "timeline" }
        if transitions != other.transitions { return "transitionGroup" }
        if surfaces != other.surfaces { return "surface" }
        return nil
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
    /// `Frame.elementRequests` the build made: what a graft stands for.
    let requests: Int
    /// Nested occurrences' memo entries, `@State` entries kept live and animation entries touched: they must
    /// still be there, and the nested entries unchanged, for the graft to stand (`RK-F`).
    let nestedKeys: [ContentMemoStore.Key]
    let liveStates: [GlobalElementID]
    let animationIDs: [GlobalElementID]
    /// The entries the build read and their versions (`RW-D`), from the journal's `.stateRead` events.
    let stateReads: [(GlobalElementID, UInt64)]
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
        for event in events {
            switch event {
            case .memoTouch(let key): nested.append(key)
            case .liveState(let id): live.append(id)
            case .stateRead(let id, let version): reads.append((id, version))
            case .animationTouch(let id): animation.append(id)
            default: break
            }
        }
        nestedKeys = nested
        liveStates = live
        animationIDs = animation
        stateReads = reads
    }
}

// MARK: - Frame: key, audit, window

extension Frame {
    func graftBuildKey() -> BuildKey {
        BuildKey(environment: environmentTop.retainedFingerprint, scale: scaleFactor, contentSize: contentSize,
                 snapping: transactionTop.animation == nil, disablesAnimations: transactionTop.disablesAnimations,
                 stackAxis: stackAxis, collectsAccessibility: collectsAccessibility,
                 depths: [lifecycleDepth, presentationDepth, transactionDepth, animationStore.keyframeDepth,
                          activeScrollContext == nil ? 0 : 1])
    }

    func buildAudit() -> BuildAudit {
        var a = BuildAudit()
        a.timeVarying = timeVaryingNotes &+ animationStore.interpolationsSoFar
        a.presentations = lowering.presentations.count
        a.hiddenNodes = hiddenNodes.count
        a.scrollKeys = scrollKeyCount
        a.elementBounds = elementBounds.count
        a.presentationRecords = presentationRecords.count
        a.toolbarRecords = toolbarRecords.count
        a.openURLs = openURLHandlers.count
        a.navigation = (collectedNavigationTitle == nil ? 0 : 1) + (collectedNavigationDocument == nil ? 0 : 1)
        a.colorScheme = collectedColorSchemePreference == nil ? 0 : 1
        a.limits = (contentMinimum == nil ? 0 : 1) + (contentMaximum == nil ? 0 : 1)
        a.anotherFrame = (wantsAnotherFrame ? 1 : 0) + (hasActiveAnimations ? 1 : 0)
        a.unlowerable = unlowerableFields.count
        a.lifecycle = animationStore.lifecycle.buildActivity
        a.timeline = animationStore.timeline.buildActivity
        a.transitions = animationStore.transitions.buildActivity
        a.surfaces = surfaceRegistry.buildActivity
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
        journal.open.append(recorder)
        return recorder
    }

    /// Closes the window and answers the record it made, or `nil` with the name of what stopped it.
    func closeGraftWindow(_ recorder: GraftRecorder, tops: [LayoutNodeID], contentSerial: Int,
                          key: BuildKey) -> (record: GraftRecord?, refusal: String?) {
        let journal = stateTable.contentMemos.journal
        journal.open.removeAll { $0 === recorder }
        defer { if journal.open.isEmpty { journal.events.removeAll(keepingCapacity: true) } }
        if let reason = recorder.taint { return (nil, reason) }
        if let moved = recorder.audit.movedChannel(to: buildAudit()) { return (nil, moved) }
        let (segment, refusal) = tree.captureSegment(from: recorder.lower, tops: tops)
        guard let segment else { return (nil, refusal ?? "segment") }
        let record = GraftRecord(key: key, contentSerial: contentSerial, segment: segment,
                                 events: Array(journal.events[recorder.start...]),
                                 requests: elementRequests &+ stateTable.contentMemos.retained.skippedRequests - recorder.requests)
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
                record.topItems.append((topIndex, item, offset))
            } else if !item.consumed, item.kind != .presentation, item.reportsFieldsIfUnconsumed {
                return (nil, "interiorItemUnconsumed")   // diagnostics would report it; a graft must not hide that
            }
        }
        return (record, nil)
    }

    /// Applies a journal through the stores' own functions (`RK-F`): the calls the build made, in the order it made them.
    func reapply(_ events: [BuildJournal.Event]) {
        let memos = stateTable.contentMemos
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
            case .transitionProduced(let unit, let evaluator): animationStore.transitions.replayProduced(unit, evaluator)
            case .transitionArray(let slot, let extent): animationStore.transitions.replayArray(slot, extent)
            }
        }
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
        guard entry.quarantineUntil <= memos.buildSerial, !entry.observedChange, old.coverageComplete,
              old.contentSerial == entry.serial, graft.contentSerial == entry.serial, graft.key == key else {
            return nil
        }
        guard prepaintRefusal() == nil, environmentTop.uncomparableCustomCount == 0, transactionTop.animation == nil else {
            return nil
        }
        guard old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }) else { return nil }
        guard !retainedSubtreeHasPointerPressOrFocus(under: id), !retainedPointerIsInside(ledger) else { return nil }
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
        reapply(record.events)
        let retained = stateTable.contentMemos.retained
        _ = retained
        stateTable.contentMemos.retained.grafts += 1
        stateTable.contentMemos.retained.skippedRequests += record.requests
        stateTable.contentMemos.retained.graftedNodes += record.segment.nodeCount
        for node in tops { tree.markPlacementRoot(node) }
        return tops
    }
}
