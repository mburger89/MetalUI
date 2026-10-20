import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes

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
        var focus = 0, axNodes = 0, pressOnly = 0, contextMenus = 0, elementBounds = 0, lives = 0, anchors = 0, geometry = 0
    }

    var recorders: [PrepaintRecorder] = []
    var focus: [FocusCall] = []
    var axNodes: [(GlobalElementID, AXNode)] = []
    var pressOnly: [(GlobalElementID, @MainActor () -> Void)] = []
    var contextMenus: [(GlobalElementID, ContextMenuRecord)] = []
    var elementBounds: [(GlobalElementID, Bounds<Pixels>)] = []
    /// Presentation anchors recorded under the prepaint, window-space (`RW-K`).
    var anchors: [(GlobalElementID, Bounds<Pixels>)] = []
    /// Geometry notes made under the prepaint, in note order (`RG-A`).
    var geometry: [GeometryNoteRecord] = []
    /// Depth of `withState` calls a replay reproduces itself (the accessibility node's retention slot).
    /// Entries read-only accesses kept live under the prepaint (`RW-E`).
    var lives: [GlobalElementID] = []
    var allowedStateWrites = 0

    var current: Marks {
        Marks(focus: focus.count, axNodes: axNodes.count, pressOnly: pressOnly.count,
              contextMenus: contextMenus.count, elementBounds: elementBounds.count, lives: lives.count,
              anchors: anchors.count, geometry: geometry.count)
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

/// One `onGeometryChange` note a prepaint made (`RG-A`): what `Frame.noteGeometry` handed `LifecycleStore.noteGeometry`, kept so an
/// equal-key replay notes it again. `global` is the frame the proxy was made from (the value is a function of it and the key).
struct GeometryNoteRecord {
    let watch: GeometryWatch
    let key: GlobalElementID
    let owner: GlobalElementID
    let value: Any
    let global: Bounds<Pixels>
}

/// One occurrence's open prepaint window.
@MainActor
final class PrepaintRecorder {
    var taint: String?
    var from = PrepaintLog.Marks()
    var hitboxLow = 0, axLow = 0
    /// `StateTable.readJournal.count` where the prepaint window opened (`RW-D`).
    var readLow = 0
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
    /// The subtree's signature relative to the first top node's origin (`FS-D`).
    var shapeInterior: Int
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
    /// Presentation anchors, window-space, replayed through `Frame.replayPresentationAnchor` (`RW-K`).
    var anchors: [(GlobalElementID, Bounds<Pixels>)] = []
    /// Geometry notes, replayed in order into the lifecycle store (`RG-A`).
    var geometry: [GeometryNoteRecord] = []
    var tallies = RegionTallies()
    /// The element prepaints the replay stands for (`FrameWork.retainedSkippedPrepaints`).
    var prepaints = 0

    /// Entries read-only accesses kept live (`RW-E`), replayed through `StateTable.touchLive`.
    var liveStates: [GlobalElementID] = []
    /// The entries the prepaint read (`RW-D`), noted again by a replay so an enclosing window sees them.
    var reads: [GlobalElementID] = []

    init(key: PrepaintKey) { self.key = key }
}

extension PrepaintKey {
    /// The parts of this key that differ from `other` (`METALUI_TRACE_RETAINED=1`).
    func describeDifference(from other: PrepaintKey) -> String {
        var why: [String] = []
        if rects != other.rects { why.append("rects") }
        if interior != other.interior { why.append("interior") }
        if shapeInterior != other.shapeInterior { why.append("shapeInterior") }
        if nodeCount != other.nodeCount { why.append("nodeCount") }
        if ambient.offset != other.ambient.offset { why.append("offset") }
        var a = ambient, b = other.ambient
        a.offset = b.offset
        if a != b { why.append("ambient") }
        if extras != other.extras {
            var x = extras, y = other.extras
            if x.scroller.count > 7, y.scroller.count > 7 { x.scroller[7] = 0; y.scroller[7] = 0 }
            if x != y {
                if x.effects != y.effects { why.append("extras.effects") }
                if x.scroller != y.scroller { why.append("extras.scroller \(x.scroller) vs \(y.scroller)") }
                if x.share != y.share { why.append("extras.share") }
                if x.suppression != y.suppression { why.append("extras.suppression") }
                if x.hiddenNodes != y.hiddenNodes { why.append("extras.hiddenNodes") }
                if x.scrollerID != y.scrollerID { why.append("extras.scrollerID") }
                if x.collectsAccessibility != y.collectsAccessibility || x.hitTestingDisabled != y.hitTestingDisabled
                    || x.keyboardHidden != y.keyboardHidden || x.portal != y.portal { why.append("extras.gates") }
            }
        }
        return why.joined(separator: ", ")
    }

    /// Whether this key is `old` but for the translation of its prepaint effects (`RK-G`).
    func differsOnlyByEffectTranslation(to other: PrepaintKey) -> Bool {
        rects == other.rects && interior == other.interior && nodeCount == other.nodeCount
            && ambient == other.ambient && extras.effects.count == other.extras.effects.count
    }
}

/// What the prepaint of an occurrence does (`RK-C`).
enum RetainedPrepaintMode {
    /// Replay the ledger; the occurrence's `component.prepaintGroup` does not run. With hitboxes: the ledger moved
    /// by the translation of the render effects around the occurrence (`RK-G`, `RK-S`), hitbox transforms rewritten.
    case replay(PrepaintLedger, moved: [Hitbox]?, elementBounds: [(GlobalElementID, Bounds<Pixels>)]? = nil)
    /// Run prepaint, recording a ledger when a recorder is given.
    case run(PrepaintRecorder?)
}

// MARK: - Frame: key, decision, windows

extension Frame {
    /// The prepaint key of `build` at this point of prepaint, or `nil` when the context cannot be keyed
    /// (`prepaintRefusal`).
    func retainedPrepaintKey(_ phase: RetainedPhase) -> PrepaintKey {
        PrepaintKey(rects: phase.rects, interior: phase.interior, shapeInterior: phase.shapeInterior, nodeCount: phase.nodeCount,
                    ambient: retainedAmbientKey(), extras: prepaintExtras())
    }

    /// Whether the pointer is inside a hitbox the ledger registered (`RK-C`'s prepaint half of `SB-X`): hover
    /// resolves after prepaint, so the decision reads the pointer position against the record's own hitboxes, a
    /// superset of the paint rule's "the hovered element is under me".
    func retainedPointerIsInside(_ ledger: PrepaintLedger) -> Bool {
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
            memos.retained.noteIneligible(.prepaint, reason: reason)
            return .run(nil)
        }
        if retainedSubtreeHasPointerPressOrFocus(under: build.key.id) { return .run(nil) }
        let key = retainedPrepaintKey(phase)
        phase.prepaintKey = key
        if memos.prepaintReplayAllowed, entry.quarantineUntil <= memos.buildSerial, let old = entry.record,
           let ledger = old.prepaint, !entry.observedChange, old.coverageComplete,
           old.contentSerial == entry.serial, old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }),
           !retainedPointerIsInside(ledger) {
            // The paint record may stand where the occurrence was before it moved: a replayed prepaint leaves nothing to
            // paint from, so the record must be movable here too, or the frame would be redone (`FS-D`).
            let recordMoves = memos.translatesLayout ? recordShiftAtPrepaint(old, phase: phase, key: key) : nil
            if let recordMoves, case .refused = paintTranslation(of: old, shift: recordMoves, key: retainedReplayKeyForTranslation(phase, key), phase: phase) {
                return .run(phase.grafted ? nil : openPrepaintWindow())
            }
            if ledger.key == key {
                memos.retained.prepaintHits += 1
                memos.retained.skippedPrepaints += ledger.prepaints
                return .replay(ledger, moved: nil)
            }
            // The occurrence moved by layout or by a scroll since the ledger was made (`FS-D`, K1 and K2): its registrations
            // are replayed moved by the add, unless one cannot be moved exactly (refused by name).
            if retainedTraces, ledger.key != key, ledger.key.shift(to: key) == nil {
                print("retained prepaint not a translation \(sbPath(build.key.id).suffix(40)): " + ledger.key.describeDifference(from: key))
            }
            if memos.translatesLayout, let shift = ledger.key.shift(to: key) {
                switch movedPrepaintLedger(ledger, shift: shift, clip: key.ambient.clip) {
                case .moved(let translation):
                    // Hover resolves after prepaint: the pointer is read against the hitboxes where they will stand, not where they stood.
                    if let point = mousePosition, translation.hitboxes.contains(where: { $0.contains(point) }) {
                        return .run(phase.grafted ? nil : openPrepaintWindow())
                    }
                    memos.ledgerMoves += 1
                    memos.retained.prepaintHits += 1
                    memos.retained.skippedPrepaints += ledger.prepaints
                    if !retainedVerifiesFromEnvironment {
                        let rebased = ledger.rebased(to: key, translation)
                        old.prepaint = rebased
                        return .replay(rebased, moved: nil)
                    }
                    return .replay(ledger, moved: translation.hitboxes, elementBounds: translation.elementBounds)
                case .refused(let reason):
                    if retainedTraces { print("retained prepaint translation refused \(sbPath(build.key.id).suffix(60)): \(reason)") }
                    memos.retained.noteTranslationRefused(reason: reason)
                    return .run(phase.grafted ? nil : openPrepaintWindow())
                }
            }
            // The same occurrence under render effects that moved by a translation (`RK-G`, `RK-S`): its
            // registrations are replayed moved, unless an accessibility record (frames are computed boxes)
            // or a hitbox that cannot be moved exactly is in the ledger.
            if ledger.key.differsOnlyByEffectTranslation(to: key), let delta = key.extras.translation(from: ledger.key.extras) {
                if !ledger.geometry.isEmpty {
                    // A noted frame moved with the effect: the transform would have to run again (`RG-C`).
                    memos.retained.noteTranslationRefused(reason: "geometryTranslated")
                    return .run(phase.grafted ? nil : openPrepaintWindow())
                }
                if ledger.axEmissions.isEmpty, ledger.axNodes.isEmpty,
                   let moved = translatedHitboxes(of: ledger, by: delta) {
                    memos.retained.prepaintHits += 1
                    memos.retained.skippedPrepaints += ledger.prepaints
                    return .replay(ledger, moved: moved, elementBounds: nil)
                }
                if retainedTraces {
                    print("retained translation refused \(sbPath(build.key.id).suffix(60)): ax \(ledger.axEmissions.count)/\(ledger.axNodes.count), hitboxes \(ledger.hitboxes.count), moved \(translatedHitboxes(of: ledger, by: delta) != nil)")
                }
                memos.retained.noteTranslationRefused(reason: ledger.axEmissions.isEmpty && ledger.axNodes.isEmpty ? "hitboxes" : "accessibilityRecords")
            }
        }
        return .run(phase.grafted ? nil : openPrepaintWindow())
    }

    /// How far the paint record stands from where the occurrence is now, when only its origin or scroll offset differ (`FS-D`):
    /// the geometric part of the paint key's relation, which is all a prepaint can read (the paint-only ambient is open later).
    func recordShiftAtPrepaint(_ old: RetainedRecord, phase: RetainedPhase, key: PrepaintKey) -> LayoutShift? {
        guard old.key.ambient.clip == key.ambient.clip else { return nil }
        return RetainedShape.shift(newRects: phase.rects, newNodeCount: phase.nodeCount, newShape: phase.shapeInterior,
                                   newOffset: key.ambient.offset, oldRects: old.key.rects, oldNodeCount: old.key.nodeCount,
                                   oldShape: old.key.shapeInterior, oldOffset: old.key.ambient.offset)
    }

    /// The position part of a replay key for a record that is only being asked whether it can move (`FS-D`).
    func retainedReplayKeyForTranslation(_ phase: RetainedPhase, _ key: PrepaintKey) -> ReplayKey {
        ReplayKey(rects: phase.rects, interior: phase.interior, shapeInterior: phase.shapeInterior,
                  nodeCount: phase.nodeCount, ambient: key.ambient)
    }

    /// Why this occurrence's prepaint cannot be keyed now, or `nil`: the paint refusals that are visible at
    /// prepaint (`SB-J`'s `retainedEntryRefusal` without the paint-only `leafGroup`).
    private func retainedPrepaintEntryRefusal(build: RetainedBuild) -> String? {
        if build.timeVarying { return "timeVarying" }
        if environmentTop.uncomparableCustomCount > 0 { return "uncomparableEnvironmentKey" }
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
        recorder.readLow = stateTable.readJournal.count
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
            memos.retained.noteIneligible(.prepaint, reason: recorder.taint ?? "unkeyed")
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
        ledger.anchors = Array(log.anchors[from.anchors..<to.anchors])
        ledger.geometry = Array(log.geometry[from.geometry..<to.geometry])
        ledger.liveStates = Array(log.lives[from.lives..<to.lives])
        var seenReads = Set<GlobalElementID>()
        for index in recorder.readLow..<stateTable.readJournal.count {
            let id = stateTable.readJournal[index]
            if seenReads.insert(id).inserted { ledger.reads.append(id) }
        }
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

// MARK: - Verify mode (`RK-N`)

/// What a frame holds after the root's paint, as comparable values (`RK-N`): the scene's arrays byte for byte, every
/// hitbox's fingerprint in order, the Tab order and focus registrations' effect, the accessibility records, the tallies
/// and the registrations of context menus, press-only actions and element bounds.
struct RetainedVerifySnapshot {
    let rects: [MUIRect], glyphs: [MUIGlyph], images: [MUIImage], backdrops: [MUIBackdrop], transforms: [MUITransform]
    let counts: [Int]
    let hitboxes: [String]
    let tabOrder: [GlobalElementID]
    let accessibility: [String]
    let axNodes: Set<GlobalElementID>
    let tallies: RegionTallies
    let contextMenus: Set<GlobalElementID>
    let pressOnly: Set<GlobalElementID>
    let bounds: [GlobalElementID: Bounds<Pixels>]
    /// Every node the tree holds, line by line (`RK-N`): children, kernel case, leaf key, spacer axis, parent, grid marks and
    /// the rect and measured width of the layout, so a graft that registered anything differently from a build is a
    /// difference by node.
    let tree: [String]
    /// What the build left in the table's sweep-visible sets, read before the sweep (`RK-N`): the rebuild only adds to what
    /// the first build left, so a call a graft's journal missed is a difference here.
    let channels: BuildChannels

    /// The first channel that differs from `other`, named, or `nil`.
    func difference(from other: RetainedVerifySnapshot) -> String? {
        func first<T>(_ a: [T], _ b: [T]) -> String? {
            guard a.count == b.count else { return "count \(a.count) vs \(b.count)" }
            for index in a.indices {
                let same = withUnsafeBytes(of: a[index]) { x in withUnsafeBytes(of: b[index]) { y in x.elementsEqual(y) } }
                if !same { return "element \(index): \(a[index]) vs \(b[index])" }
            }
            return nil
        }
        if let d = first(rects, other.rects) { return "scene rects \(d)" }
        if let d = first(glyphs, other.glyphs) { return "scene glyphs \(d)" }
        if let d = first(images, other.images) { return "scene images \(d)" }
        if let d = first(backdrops, other.backdrops) { return "scene backdrops \(d)" }
        if let d = first(transforms, other.transforms) { return "scene transforms \(d)" }
        if counts != other.counts { return "scene counts \(counts) vs \(other.counts)" }
        if hitboxes != other.hitboxes {
            let first = zip(hitboxes, other.hitboxes).enumerated().first { $0.element.0 != $0.element.1 }
            return "hitboxes (\(hitboxes.count) vs \(other.hitboxes.count)) first difference \(String(describing: first))"
        }
        if tabOrder != other.tabOrder { return "tab order" }
        if accessibility != other.accessibility { return "accessibility records (\(accessibility.count) vs \(other.accessibility.count))" }
        if axNodes != other.axNodes {
            let a = Set(axNodes.map { sbPath($0) }), b = Set(other.axNodes.map { sbPath($0) })
            return "accessibility nodes (\(axNodes.count) vs \(other.axNodes.count)) only in the replay \(a.subtracting(b).sorted()), only in the rebuild \(b.subtracting(a).sorted())"
        }
        if tallies != other.tallies { return "region tallies \(tallies) vs \(other.tallies)" }
        if contextMenus != other.contextMenus { return "context menus" }
        if pressOnly != other.pressOnly { return "press-only actions" }
        if bounds != other.bounds { return "element bounds" }
        if tree != other.tree {
            let first = zip(tree, other.tree).enumerated().first { $0.element.0 != $0.element.1 }
            return "layout tree (\(tree.count) vs \(other.tree.count) nodes) first difference \(String(describing: first))"
        }
        if let d = other.channels.difference(from: channels) { return "build calls on the tables: \(d)" }
        return nil
    }
}

extension Frame {
    /// Verify mode presents the second build and reports the first's work (`RK-V`): the element counters too.
    func adoptElementWork(of other: Frame) {
        elementRequests = other.elementRequests
        elementPrepaints = other.elementPrepaints
        elementPaints = other.elementPaints
    }

    func captureRetainedVerifySnapshot() -> RetainedVerifySnapshot {
        let s = finalizedScene()
        return RetainedVerifySnapshot(
            rects: s.rects, glyphs: s.glyphs, images: s.images, backdrops: s.backdrops, transforms: s.transforms,
            counts: [s.rects.count, s.glyphs.count, s.images.count, s.surfaces.count, s.textures.count, s.drawList.count],
            hitboxes: hitboxes(from: 0).map(\.fingerprint), tabOrder: focusRegistry.tabOrder,
            accessibility: axEmissions(from: 0).map {
                "\($0.id)|\($0.declared)|\(String(describing: $0.text))|\($0.isClickable)|\($0.isEnabled)|\($0.synthesizes)|\($0.portal)|\($0.geometry)|\($0.declaresAction)"
            },
            axNodes: Set(axNodes.keys), tallies: regionTallies, contextMenus: Set(contextMenuRecords.keys),
            pressOnly: Set(accessibilityPressOnly.keys), bounds: elementBounds, tree: tree.structureDigest(),
            channels: stateTable.buildChannels(animation: animationStore))
    }
}
