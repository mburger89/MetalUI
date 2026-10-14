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
    var timeVarying = 0, loweringItems = 0, loweringAliases = 0, textLeaves = 0, presentations = 0, hiddenNodes = 0
    var scrollKeys = 0, elementBounds = 0, presentationRecords = 0, toolbarRecords = 0, openURLs = 0
    var navigation = 0, colorScheme = 0, limits = 0, anotherFrame = 0, unlowerable = 0
    var lifecycle = 0, timeline = 0, transitions = 0, surfaces = 0, hasScrollRequests = 0

    func movedChannel(to other: BuildAudit) -> String? {
        if timeVarying != other.timeVarying { return "timeVarying" }
        if loweringItems != other.loweringItems || loweringAliases != other.loweringAliases
            || textLeaves != other.textLeaves { return "loweredItems" }
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
    let segment: LayoutSegment
    let events: [BuildJournal.Event]
    /// `Frame.elementRequests` the build made: what a graft stands for.
    let requests: Int
    /// Nested occurrences' memo entries, `@State` entries kept live and animation entries touched: they must
    /// still be there, and the nested entries unchanged, for the graft to stand (`RK-F`).
    let nestedKeys: [ContentMemoStore.Key]
    let liveStates: [GlobalElementID]
    let animationIDs: [GlobalElementID]

    init(key: BuildKey, contentSerial: Int, segment: LayoutSegment, events: [BuildJournal.Event], requests: Int) {
        self.key = key
        self.contentSerial = contentSerial
        self.segment = segment
        self.events = events
        self.requests = requests
        var nested: [ContentMemoStore.Key] = []
        var live: [GlobalElementID] = []
        var animation: [GlobalElementID] = []
        for event in events {
            switch event {
            case .memoTouch(let key): nested.append(key)
            case .liveState(let id): live.append(id)
            case .animationTouch(let id): animation.append(id)
            default: break
            }
        }
        nestedKeys = nested
        liveStates = live
        animationIDs = animation
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
        a.loweringItems = lowering.items.count
        a.loweringAliases = lowering.aliasCount
        a.textLeaves = lowering.textLeaves.count
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
        recorder.requests = elementRequests
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
        if recordsElementBounds { return (nil, "elementBounds") }
        let (segment, refusal) = tree.captureSegment(from: recorder.lower, tops: tops)
        guard let segment else { return (nil, refusal ?? "segment") }
        let record = GraftRecord(key: key, contentSerial: contentSerial, segment: segment,
                                 events: Array(journal.events[recorder.start...]),
                                 requests: elementRequests - recorder.requests)
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
