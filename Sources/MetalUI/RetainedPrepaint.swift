import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene

// C14b-2 lane 1 (`RK-C`…`RK-E`, `RK-M`, `RK-O`): prepaint replay and the redo. A retained occurrence keeps, beside
// the paint record `SB-B` made, a **prepaint ledger**: what its prepaint registered on the frame (hitboxes in
// registration order, focus registrations, accessibility records and nodes, press-only actions, context menus,
// element bounds, the region tallies), replayed instead of run while the **prepaint key** is equal. The build
// recursion still runs (lane 2's graft is the item that skips it), so every miss is safe except one: a replayed
// prepaint leaves no element prepaint state, so paint of that occurrence must be a replay too, and a paint-only
// ambient (an opacity, a shadow, a blur or a composite scope an ancestor pushes at paint) that differs from the
// record's cannot be repaired in place. That frame is abandoned before anything after the root's paint runs and
// built again by the window with every prepaint replay off (`RK-D`, `RK-M`).
// Spec `docs/superpowers/specs/2026-10-13-retained-build-skip-design.md`, rulings
// `docs/superpowers/2026-10-13-retained-build-skip-decisions.md`.

/// Whether `METALUI_TRACE_RETAINED=1` also traces prepaint decisions (`retainedTraces`, read once).

// MARK: - The journal

/// What every open prepaint recorder shares (`RK-E`): the calls the frame's registration funnels make while a
/// recorder is open, in order. A recorder remembers the journal's lengths where its window opened and closed and
/// keeps the slice. **`Frame.prepaintLog` is `nil` unless a recorder is open.**
@MainActor
final class PrepaintLog {
    enum FocusCall {
        case register(Handlers, GlobalElementID)
        case shortcut(Handlers, GlobalElementID)
        case binding(FocusBindingTarget, GlobalElementID)
    }

    struct Marks: Equatable {
        var focus = 0, axNodes = 0, pressOnly = 0, contextMenus = 0, elementBounds = 0
    }

    var recorders: [PrepaintRecorder] = []
    var focus: [FocusCall] = []
    var axNodes: [(GlobalElementID, AXNode)] = []
    var pressOnly: [(GlobalElementID, @MainActor () -> Void)] = []
    var contextMenus: [(GlobalElementID, ContextMenuRecord)] = []
    var elementBounds: [(GlobalElementID, Bounds<Pixels>)] = []
    /// Depth of `withState` calls a replay reproduces itself (the accessibility node's retention slot).
    var allowedStateWrites = 0

    var current: Marks {
        Marks(focus: focus.count, axNodes: axNodes.count, pressOnly: pressOnly.count,
              contextMenus: contextMenus.count, elementBounds: elementBounds.count)
    }

    /// Marks every open recorder as unable to leave a ledger, naming the first reason.
    func taint(_ reason: String) {
        for recorder in recorders where recorder.taint == nil { recorder.taint = reason }
    }

    /// A share patch (`GX-P`) rewrote a hitbox registered before a recorder's window opened: the registration is
    /// not that recorder's alone, so it cannot be replayed on its own.
    func notePatch(hitbox index: Int) {
        for recorder in recorders where index < recorder.hitboxLow && recorder.taint == nil {
            recorder.taint = "sharePatchesOutside"
        }
    }

    func notePatch(accessibility index: Int) {
        for recorder in recorders where index < recorder.axLow && recorder.taint == nil {
            recorder.taint = "sharePatchesOutside"
        }
    }
}

/// One occurrence's open prepaint window.
@MainActor
final class PrepaintRecorder {
    var taint: String?
    var from = PrepaintLog.Marks()
    var hitboxLow = 0, axLow = 0
    var tallies = RegionTallies()
    var prepaints = 0
    var audit = PrepaintAudit()
}

// MARK: - The key and the ledger

/// Everything an occurrence's prepaint reads that is not in the subtree (`RK-E`): the absolute rects and the layout
/// under it, the clip, offset, layer, scale, environment and transaction (the paint key's ambient as read at
/// prepaint, where the paint-only stacks are empty) and the prepaint-visible context.
struct PrepaintKey: Equatable {
    var rects: [Float]
    var interior: Int
    var nodeCount: Int
    var ambient: AmbientKey
    var extras: PrepaintExtras
}

/// One occurrence's prepaint products (`RK-E`), replayed in the order a fresh prepaint makes them.
@MainActor
final class PrepaintLedger {
    let key: PrepaintKey
    var hitboxes: [Hitbox] = []
    var axEmissions: [AXEmission] = []
    var focus: [PrepaintLog.FocusCall] = []
    var axNodes: [(GlobalElementID, AXNode)] = []
    var pressOnly: [(GlobalElementID, @MainActor () -> Void)] = []
    var contextMenus: [(GlobalElementID, ContextMenuRecord)] = []
    var elementBounds: [(GlobalElementID, Bounds<Pixels>)] = []
    var tallies = RegionTallies()
    /// The element prepaints the replay stands for (`FrameWork.retainedSkippedPrepaints`).
    var prepaints = 0

    init(key: PrepaintKey) { self.key = key }
}

/// What the prepaint of an occurrence does (`RK-C`).
enum RetainedPrepaintMode {
    /// Replay the ledger; the occurrence's `component.prepaintGroup` does not run.
    case replay(PrepaintLedger)
    /// Run prepaint, recording a ledger when a recorder is given.
    case run(PrepaintRecorder?)
}

// MARK: - Frame: key, decision, windows

extension Frame {
    /// The prepaint key of `build` at this point of prepaint, or `nil` when the context cannot be keyed
    /// (`prepaintRefusal`).
    func retainedPrepaintKey(_ phase: RetainedPhase) -> PrepaintKey {
        PrepaintKey(rects: phase.rects, interior: phase.interior, nodeCount: phase.nodeCount,
                    ambient: retainedAmbientKey(), extras: prepaintExtras())
    }

    /// Whether the pointer is inside a hitbox the ledger registered (`RK-C`'s prepaint half of `SB-X`): hover
    /// resolves after prepaint, so the decision reads the pointer position against the record's own hitboxes, a
    /// superset of the paint rule's "the hovered element is under me".
    private func retainedPointerIsInside(_ ledger: PrepaintLedger) -> Bool {
        guard let point = mousePosition else { return false }
        return ledger.hitboxes.contains { $0.contains(point) }
    }

    /// The decision of `EquatableComponent.prepaintGroup` (`RK-C`, `RK-E`): replay, run and record, or run.
    func retainedPrepaintDecision(_ phase: RetainedPhase) -> RetainedPrepaintMode {
        let memos = stateTable.contentMemos
        guard memos.replaysPrepaint else { return .run(nil) }
        let build = phase.build, entry = phase.entry
        if let reason = prepaintRefusal() ?? retainedPrepaintEntryRefusal(build: build) {
            if retainedTraces { print("retained prepaint refused \(sbPath(build.key.id).suffix(60)) because \(reason)") }
            memos.retained.prepaintIneligible += 1
            return .run(nil)
        }
        if retainedSubtreeHasPointerPressOrFocus(under: build.key.id) { return .run(nil) }
        let key = retainedPrepaintKey(phase)
        phase.prepaintKey = key
        if memos.prepaintReplayAllowed, entry.quarantineUntil <= memos.buildSerial, let old = entry.record,
           let ledger = old.prepaint, !entry.observedChange, old.coverageComplete,
           old.contentSerial == entry.serial, old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }),
           ledger.key == key, !retainedPointerIsInside(ledger) {
            memos.retained.prepaintHits += 1
            memos.retained.skippedPrepaints += ledger.prepaints
            return .replay(ledger)
        }
        return .run(openPrepaintWindow())
    }

    /// Why this occurrence's prepaint cannot be keyed now, or `nil`: the paint refusals that are visible at
    /// prepaint (`SB-J`'s `retainedEntryRefusal` without the paint-only `leafGroup`).
    private func retainedPrepaintEntryRefusal(build: RetainedBuild) -> String? {
        if build.timeVarying { return "timeVarying" }
        if environmentTop.customKeyCount > 0 { return "customEnvironmentKey" }
        if transactionTop.animation != nil { return "transaction" }
        return nil
    }

    // MARK: Windows

    func openPrepaintWindow() -> PrepaintRecorder {
        if prepaintLog == nil { prepaintLog = PrepaintLog() }
        let log = prepaintLog!
        let recorder = PrepaintRecorder()
        recorder.from = log.current
        recorder.hitboxLow = hitboxCount
        recorder.axLow = axEmissionCount
        recorder.tallies = regionTallies
        recorder.prepaints = elementPrepaints
        recorder.audit = prepaintAudit()
        log.recorders.append(recorder)
        return recorder
    }

    /// Closes the recorder's window and returns the ledger it made, or `nil` (counted ineligible, by name).
    func closePrepaintWindow(_ recorder: PrepaintRecorder, phase: RetainedPhase) -> PrepaintLedger? {
        let log = prepaintLog!
        log.recorders.removeAll { $0 === recorder }
        let to = log.current
        defer {
            if log.recorders.isEmpty { prepaintLog = nil }
        }
        let memos = stateTable.contentMemos
        if recorder.taint == nil, let moved = recorder.audit.movedChannel(to: prepaintAudit()) { recorder.taint = moved }
        let hitboxes = hitboxes(from: recorder.hitboxLow)
        if recorder.taint == nil,
           hitboxes.contains(where: { $0.handlers.hasDraggable || $0.handlers.dropDestination != nil }) {
            recorder.taint = "dragAndDrop"
        }
        guard recorder.taint == nil, let key = phase.prepaintKey else {
            if retainedTraces {
                print("retained prepaint ineligible \(sbPath(phase.build.key.id).suffix(60)) because \(recorder.taint ?? "unkeyed")")
            }
            memos.retained.prepaintIneligible += 1
            return nil
        }
        let ledger = PrepaintLedger(key: key)
        ledger.hitboxes = hitboxes
        ledger.axEmissions = axEmissions(from: recorder.axLow)
        let from = recorder.from
        ledger.focus = Array(log.focus[from.focus..<to.focus])
        ledger.axNodes = Array(log.axNodes[from.axNodes..<to.axNodes])
        ledger.pressOnly = Array(log.pressOnly[from.pressOnly..<to.pressOnly])
        ledger.contextMenus = Array(log.contextMenus[from.contextMenus..<to.contextMenus])
        ledger.elementBounds = Array(log.elementBounds[from.elementBounds..<to.elementBounds])
        let now = regionTallies
        ledger.tallies = RegionTallies(hover: now.hover - recorder.tallies.hover,
                                       pointerStyle: now.pointerStyle - recorder.tallies.pointerStyle,
                                       key: now.key - recorder.tallies.key,
                                       focusOnPress: now.focusOnPress - recorder.tallies.focusOnPress,
                                       resign: now.resign - recorder.tallies.resign)
        ledger.prepaints = elementPrepaints - recorder.prepaints
        return ledger
    }

    // MARK: The redo

    /// A replayed prepaint cannot paint under this frame's ambient: the frame is abandoned after paint (`RK-C`).
    func requestRedo(_ entry: ContentMemoStore.Entry) {
        redoEntries.append(entry)
    }
}

// MARK: - The window's side of the redo

extension ContentMemoStore {
    /// Whether prepaint replay is in force for the build in progress: on, not in a redo, not backed off (`RK-D`).
    var prepaintReplayAllowed: Bool {
        replaysPrepaint && windowRedoes && !redoInProgress && buildSerial >= prepaintSuspendedUntil
    }

    /// The frame was abandoned for `entries` (`RK-D` item 3): prepaint replay is suspended window-wide for the
    /// next eight builds, each entry for 8, 16 … 256, and this build's counters restart (the abandoned attempt's
    /// work was thrown away; `redos` counts the redo).
    func noteRedo(_ entries: [Entry]) {
        let serial = buildSerial
        prepaintSuspendedUntil = serial + 9
        var seen = Set<ObjectIdentifier>()
        for entry in entries where seen.insert(ObjectIdentifier(entry)).inserted {
            entry.quarantineUntil = serial + 1 + (8 << entry.redoExponent)
            entry.redoExponent = min(entry.redoExponent + 1, 5)
        }
        resetBuildCounters()
        retained.redos = 1
    }
}
