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

// Whether `METALUI_TRACE_RETAINED=1` also traces prepaint decisions (`retainedTraces`, read once).

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
        /// The focused element was produced under the window (`RK-AQ`): replay sets `focusedElementProducedThisFrame` when `focusedElement` is still `id`
        /// and, when `retains`, repeats the plain `$focus` retention write the producing call made.
        case focused(GlobalElementID, retains: Bool)
    }

    struct Marks: Equatable {
        var focus = 0, axNodes = 0, pressOnly = 0, contextMenus = 0, elementBounds = 0, lives = 0, anchors = 0, geometry = 0, modifiers = 0, inertBlockers = 0, liveValues = 0, regions = 0
        /// The clips noted so far (`FS-X`).
        var clips = 0
    }

    var recorders: [PrepaintRecorder] = []
    var focus: [FocusCall] = []
    var axNodes: [(GlobalElementID, AXNode)] = []
    /// Lock-step with `axNodes`: the pre-effect rect of each node, `nil` outside an effect (`AT-A`).
    var axNodeLocals: [AXLocalRects?] = []
    var pressOnly: [(GlobalElementID, @MainActor () -> Void)] = []
    /// Live accessibility values declared under the prepaint, in lock-step with the nodes they refresh (`TRM-BH`).
    var liveValues: [(GlobalElementID, @MainActor () -> String)] = []
    /// Disabled controls' chrome-only rects (`AS-S`).
    var inertBlockers: [Bounds<Pixels>] = []
    var contextMenus: [(GlobalElementID, ContextMenuRecord)] = []
    /// The selectable `Text`s' regions registered under the prepaint, each naming its hitbox by the frame's absolute index
    /// (`TXS-C`, `TXS-I` item 3).
    var regions: [SelectableTextRegion] = []
    var elementBounds: [(GlobalElementID, Bounds<Pixels>)] = []
    /// Presentation anchors recorded under the prepaint, window-space (`RW-K`).
    var anchors: [(GlobalElementID, Bounds<Pixels>)] = []
    /// Geometry notes made under the prepaint, in note order (`RG-A`).
    var geometry: [GeometryNoteRecord] = []
    /// Modifier-key notes made under the prepaint, in note order (`RL-B`).
    var modifiers: [ModifierNoteRecord] = []
    /// Depth of `withState` calls a replay reproduces itself (the accessibility node's retention slot).
    /// Entries read-only accesses kept live under the prepaint (`RW-E`).
    var lives: [GlobalElementID] = []
    var allowedStateWrites = 0
    /// The clips pushed while a recorder is open, in push order, with absolute layout bounds and the **frame's** hitbox and emission
    /// counts as their ranges (`FS-X`); a ledger keeps the slice of its window, relative to its own origin and low marks. Empty for a
    /// window that pushes none, which allocates nothing.
    var clips: [PrepaintClip] = []
    /// The index in `clips` of the innermost push not yet popped, or -1.
    var openClip: Int32 = -1
    /// Clips noted since the process began: a `package` counter for the tests that pin which ledgers keep theirs (`FS-X`).
    package nonisolated(unsafe) static var pushCount = 0

    var current: Marks {
        Marks(focus: focus.count, axNodes: axNodes.count, pressOnly: pressOnly.count,
              contextMenus: contextMenus.count, elementBounds: elementBounds.count, lives: lives.count,
              anchors: anchors.count, geometry: geometry.count, modifiers: modifiers.count,
              inertBlockers: inertBlockers.count, liveValues: liveValues.count, regions: regions.count,
              clips: clips.count)
    }

    /// A clip pushed while a recorder is open (`FS-X`): `bounds` and `offset` are `pushClip`'s own arguments, `hitboxes` and `emissions`
    /// the frame's counts now, where its ranges open.
    func notePush(bounds: Bounds<Pixels>, offset: Point<Pixels>, radii: Corners<Pixels>, atFlatteningEntry: Bool, depth: Int,
                  root: Bool = false, hitboxes: Int, emissions: Int) {
        var flags: UInt8 = 0
        if atFlatteningEntry { flags |= InnerClip.flatteningEntryFlag }
        if root { flags |= InnerClip.rootFlag }
        Self.pushCount += 1
        clips.append(PrepaintClip(
            clip: InnerClip(x: bounds.origin.x.value, y: bounds.origin.y.value, width: bounds.size.width.value,
                            height: bounds.size.height.value, offsetX: offset.x.value, offsetY: offset.y.value,
                            topLeft: radii.topLeft.value, topRight: radii.topRight.value,
                            bottomRight: radii.bottomRight.value, bottomLeft: radii.bottomLeft.value,
                            parent: openClip, depth: Int32(depth), lo: Int32(hitboxes), hi: Int32(hitboxes), flags: flags),
            axLo: Int32(emissions), axHi: Int32(emissions)))
        openClip = Int32(clips.count - 1)
    }

    /// The innermost open clip is popped: its ranges close here.
    func notePop(hitboxes: Int, emissions: Int) {
        guard openClip >= 0 else { return }
        let top = Int(openClip)
        clips[top].clip.hi = Int32(hitboxes)
        clips[top].axHi = Int32(emissions)
        openClip = clips[top].clip.parent
    }

    /// A replayed ledger's clips, closed as they stand (`FS-X`): at `origin` where the occurrence stands now, the ranges at the bases its
    /// hitboxes and emissions were appended at, the clips pushed at its entry depth inside the clip open here.
    func noteReplayed(_ replayed: [PrepaintClip], origin: (x: Float, y: Float), hitboxBase: Int, emissionBase: Int) {
        let base = Int32(clips.count)
        for stored in replayed {
            var copy = stored
            copy.clip = stored.clip.moved(byX: origin.x, y: origin.y)
            copy.clip.parent = stored.clip.parent >= 0 ? stored.clip.parent + base : openClip
            copy.clip.lo += Int32(hitboxBase); copy.clip.hi += Int32(hitboxBase)
            copy.axLo += Int32(emissionBase); copy.axHi += Int32(emissionBase)
            clips.append(copy)
        }
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

/// One clip pushed inside a recorded prepaint (`FS-X`): `clip.lo..<clip.hi` is the range of the occurrence's hitboxes registered while it
/// was open, `axLo..<axHi` that of its accessibility emissions, both relative to the recorder's low marks. In a ledger the bounds are
/// relative to the first top node's layout origin (they move with it); while recording they are absolute and the ranges the frame's.
struct PrepaintClip: Equatable {
    var clip: InnerClip
    var axLo: Int32, axHi: Int32
}

/// One `onGeometryChange` note a prepaint made (`RG-A`): what `Frame.noteGeometry` handed `LifecycleStore.noteGeometry`, kept so an
/// equal-key replay notes it again. `global` is the frame the proxy was made from (the value is a function of it and the key).
struct GeometryNoteRecord {
    let watch: GeometryWatch
    let key: GlobalElementID
    let owner: GlobalElementID
    let value: Any
    let global: Bounds<Pixels>
    /// The operands of the proxy the value was computed from (`RL-E`): a translated replay rebuilds the proxy from them against the
    /// translated position and runs the transform again. `moved` is the union after the scroll offset, before any effect; `composed`
    /// the innermost open effect's map; `chain` the effects open at the note; `namedSpaces` the spaces in force (all declared
    /// inside the occurrence, since an outer one refuses the ledger, `RL-O`).
    let size: Size<Pixels>
    let moved: Bounds<Pixels>
    let composed: Homography2D?
    let chain: AXEffectChain
    let namedSpaces: [NamedSpace]
}

/// One `onModifierKeysChanged` note a prepaint made (`RL-B`): the position and watch only. **No value**: the note's value is the
/// window's current modifiers, read when it is made again, so a replay delivers a change a recorded value would miss.
struct ModifierNoteRecord {
    let watch: ModifierKeysWatch
    let key: GlobalElementID
    let owner: GlobalElementID
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
    /// `var` for `rebase(to:_:)` (`G47`), the one writer after the ledger is closed.
    var key: PrepaintKey
    var hitboxes: [Hitbox] = []
    /// The clips the occurrence pushed that cut a hitbox or an emission deeper than its entry, relative to the first top node (`FS-X`);
    /// `nil` when nothing sits at an inner depth, which is nearly every ledger.
    var innerClips: [PrepaintClip]?
    /// Lock-step with `hitboxes` when any hitbox sat under an effect, else empty: the effect chain each was registered under (`RL-I`).
    var hitboxChains: [AXEffectChain?] = []
    var axEmissions: [AXEmission] = []
    var focus: [PrepaintLog.FocusCall] = []
    var axNodes: [(GlobalElementID, AXNode)] = []
    var axNodeLocals: [AXLocalRects?] = []
    var pressOnly: [(GlobalElementID, @MainActor () -> Void)] = []
    /// Live accessibility values, re-registered on replay beside their nodes (`TRM-BH`).
    var liveValues: [(GlobalElementID, @MainActor () -> String)] = []
    /// Disabled controls' chrome-only rects, replayed as recorded (`AS-S`); a translation refuses.
    var inertBlockers: [Bounds<Pixels>] = []
    var contextMenus: [(GlobalElementID, ContextMenuRecord)] = []
    /// Selectable `Text` regions, each naming its hitbox relative to the occurrence's first (`TXS-I` item 3): a replay appends the
    /// hitboxes and then these at the new base, so neither is orphaned.
    var regions: [SelectableTextRegion] = []
    var elementBounds: [(GlobalElementID, Bounds<Pixels>)] = []
    /// Presentation anchors, window-space, replayed through `Frame.replayPresentationAnchor` (`RW-K`).
    var anchors: [(GlobalElementID, Bounds<Pixels>)] = []
    /// Geometry notes, replayed in order into the lifecycle store (`RG-A`).
    var geometry: [GeometryNoteRecord] = []
    /// Modifier-key notes, made again in order against the current modifiers (`RL-B`).
    var modifiers: [ModifierNoteRecord] = []
    var tallies = RegionTallies()
    /// The element prepaints the replay stands for (`FrameWork.retainedSkippedPrepaints`).
    var prepaints = 0

    /// Entries read-only accesses kept live (`RW-E`), replayed through `StateTable.touchLive`.
    var liveStates: [GlobalElementID] = []
    /// The entries the prepaint read (`RW-D`), noted again by a replay so an enclosing window sees them.
    var reads: [GlobalElementID] = []

    init(key: PrepaintKey) {
        self.key = key
        Self.madeCount += 1
    }
}

extension PrepaintKey {
    /// Every part of this key that differs from `other` (`METALUI_TRACE_RETAINED=1`), `ledgerKey.<field>`.
    func describeDifference(from other: PrepaintKey) -> [String] {
        var why: [String] = []
        if rects != other.rects { why.append("ledgerKey.rects") }
        if interior != other.interior { why.append("ledgerKey.interior") }
        if shapeInterior != other.shapeInterior { why.append("ledgerKey.shapeInterior") }
        if nodeCount != other.nodeCount { why.append("ledgerKey.nodeCount") }
        for member in ambient.differences(from: other.ambient) { why.append("ledgerKey.ambient.\(member)") }
        if extras != other.extras {
            var x = extras, y = other.extras
            if x.scroller.count > 7, y.scroller.count > 7 { x.zeroScrollOffsets(); y.zeroScrollOffsets() }
            if x != y {
                if x.effects != y.effects { why.append("ledgerKey.extras.effects") }
                if x.scroller != y.scroller { why.append("ledgerKey.extras.scroller") }
                if x.share != y.share { why.append("ledgerKey.extras.share") }
                if x.suppression != y.suppression { why.append("ledgerKey.extras.suppression") }
                if x.hiddenNodes != y.hiddenNodes { why.append("ledgerKey.extras.hiddenNodes") }
                if x.scrollerID != y.scrollerID { why.append("ledgerKey.extras.scrollerID") }
                if x.collectsAccessibility != y.collectsAccessibility || x.hitTestingDisabled != y.hitTestingDisabled
                    || x.keyboardHidden != y.keyboardHidden || x.portal != y.portal { why.append("ledgerKey.extras.gates") }
            }
        }
        return why
    }

    /// Whether this key is `old` but for the translation of its prepaint effects (`RK-G`).
    func differsOnlyByEffectTranslation(to other: PrepaintKey) -> Bool {
        rects == other.rects && interior == other.interior && nodeCount == other.nodeCount
            && ambient == other.ambient && extras.effects.count == other.extras.effects.count
    }

    /// Whether this key is `old` but for its prepaint effects, their number included (`RZ-B`): the gate of the effect arm, whose
    /// `PrepaintExtras.change(from:)` then names what changed.
    func differsOnlyByEffects(to other: PrepaintKey) -> Bool {
        rects == other.rects && interior == other.interior && nodeCount == other.nodeCount && ambient == other.ambient
    }
}

/// What the prepaint of an occurrence does (`RK-C`).
enum RetainedPrepaintMode {
    /// Replay the ledger; the occurrence's `component.prepaintGroup` does not run. With hitboxes: the ledger moved
    /// by the translation of the render effects around the occurrence (`RK-G`, `RK-S`), hitbox transforms rewritten.
    case replay(PrepaintLedger, moved: [Hitbox]?, elementBounds: [(GlobalElementID, Bounds<Pixels>)]? = nil,
                accessibility: AXTranslation? = nil, geometry: [GeometryNoteRecord]? = nil,
                windowShift: (dx: Float, dy: Float)? = nil, layoutOrigin: (x: Float, y: Float)? = nil)
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

    /// The decision of `EquatableComponent.prepaintGroup` (`RK-C`, `RK-E`): replay, run and record, or run. A decision that does
    /// not replay prints one `retained prepaint miss` line naming why (`DM-F`).
    func retainedPrepaintDecision(_ phase: RetainedPhase) -> RetainedPrepaintMode {
        phase.prepaintNote = nil
        phase.prepaintInvalidation = []
        let mode = retainedPrepaintDecisionInner(phase)
        if case .run = mode, RetainedTrace.active, phase.prepaintNote != "traced" {
            RetainedTrace.emit(prepaintMissLine(phase))
        }
        return mode
    }

    private func prepaintMissLine(_ phase: RetainedPhase) -> String {
        var why = phase.prepaintInvalidation
        if let note = phase.prepaintNote { why.append(note) }
        if why.isEmpty {
            why = ["unclassified"]
            RetainedTrace.unclassified += 1
        }
        let cause = phase.prepaintInvalidation.contains("observed") || phase.prepaintInvalidation.contains("serial")
            ? RetainedTrace.causeSuffix(of: phase.entry) : ""
        let owner = phase.prepaintInvalidation.contains("quarantine") ? " quarantinedBy: \(stateTable.contentMemos.quarantineOwner(of: phase.entry, id: phase.build.key.id))" : ""
        return "retained prepaint miss \(RetainedTrace.path(phase.build.key.id)) reasons=[\(why.joined(separator: ", "))]\(cause)\(owner) frame: grafted=\(phase.grafted)"
    }

    /// Names why a prepaint that passed its guard still runs (trace only).
    private func noteRun(_ phase: RetainedPhase, _ note: @autoclosure () -> String) {
        if RetainedTrace.active { phase.prepaintNote = note() }
    }

    private func retainedPrepaintDecisionInner(_ phase: RetainedPhase) -> RetainedPrepaintMode {
        let memos = stateTable.contentMemos
        guard memos.replaysPrepaint else { return .run(nil) }
        let build = phase.build, entry = phase.entry
        if let reason = prepaintRefusal() ?? retainedPrepaintEntryRefusal(build: build) {
            RetainedTrace.emit("retained prepaint refused \(RetainedTrace.path(build.key.id)) because \(reason)")
            phase.prepaintNote = "traced"
            memos.retained.noteIneligible(.prepaint, reason: reason)
            return .run(nil)
        }
        if retainedSubtreeHasPointerPressOrFocus(under: build.key.id) {
            noteRun(phase, "pointer/press/focus under the occurrence")
            return .run(nil)
        }
        let key = retainedPrepaintKey(phase).transactionNormalised   // `AM-D`, `AM-L`
        phase.prepaintKey = key
        let old = entry.record
        let ledgerOfRecord = old?.prepaint
        var inputs = PrepaintInvalidation.Inputs()
        inputs.replayDisallowed = !memos.prepaintReplayAllowed
        inputs.quarantined = entry.quarantineUntil > memos.buildSerial || memos.isInQuarantinedScope(build.key.id)
        inputs.scopedRedo = memos.isInRedoScope(build.key.id)
        inputs.hasRecord = old != nil
        inputs.hasLedger = ledgerOfRecord != nil
        inputs.observedChange = entry.observedChange
        inputs.coverageBuild = old?.coverageBuild ?? true
        inputs.coveragePrepaint = old?.coveragePrepaint ?? true
        inputs.serialMatches = old.map { $0.contentSerial == entry.serial } ?? true
        inputs.versionsUnchanged = old.map { retainedVersionsUnchanged($0.versions) } ?? true
        inputs.pointerInLedger = ledgerOfRecord.map { retainedPointerIsInside($0) } ?? false
        let invalidation = PrepaintInvalidation(inputs)
        if RetainedTrace.active { phase.prepaintInvalidation = invalidation.names }
        if invalidation.isReplayable, let old, let ledger = ledgerOfRecord {
            // The paint record may stand where the occurrence was before it moved: a replayed prepaint leaves nothing to
            // paint from, so the record must be movable here too, or the frame would be redone (`FS-D`).
            // A changed entry clip is part of the record's move only where the ledger's key relates by it too (`FS-Y`): the prepaint's ambient is
            // then the paint record's but for the clip and the offset, and nothing under an effect that changed is read as a clip change.
            let clipRelated = memos.translatesLayout && memos.relatesChangedClip && ledger.key.ambient.clip != key.ambient.clip && ledger.key.clippedShift(to: key) != nil
            let recordMoves = memos.translatesLayout ? recordShiftAtPrepaint(old, phase: phase, key: key, clipRelated: clipRelated) : nil
            if let recordMoves, case .refused = paintTranslation(of: old, shift: recordMoves, key: retainedReplayKeyForTranslation(phase, key), phase: phase) {
                noteRun(phase, "recordCannotMove")
                return .run(phase.grafted ? nil : openPrepaintWindow())
            }
            if ledger.key == key {
                memos.retained.prepaintHits += 1
                memos.retained.skippedPrepaints += ledger.prepaints
                return .replay(ledger, moved: nil)
            }
            // The occurrence moved by layout or by a scroll since the ledger was made (`FS-D`, K1 and K2): its registrations
            // are replayed moved by the add, unless one cannot be moved exactly (refused by name). The entry clip may have changed with the move
            // (`FS-Y`, a zero move included): the same add, every cut made again from the new clip.
            let layoutShift = ledger.key.shift(to: key) ?? (memos.relatesChangedClip ? ledger.key.clippedShift(to: key) : nil)
            if layoutShift == nil {
                noteRun(phase, ledger.key.describeDifference(from: key).joined(separator: ", "))
            }
            if memos.translatesLayout, let shift = layoutShift {
                switch movedPrepaintLedger(ledger, shift: shift, clip: key.ambient.clip, to: key) {
                case .moved(let translation):
                    // Hover resolves after prepaint: the pointer is read against the hitboxes where they will stand, not where they stood.
                    if let point = mousePosition, translation.hitboxes.contains(where: { $0.contains(point) }) {
                        noteRun(phase, "pointerInMovedLedger")
                        return .run(phase.grafted ? nil : openPrepaintWindow())
                    }
                    memos.ledgerMoves += 1
                    memos.retained.prepaintHits += 1
                    memos.retained.skippedPrepaints += ledger.prepaints
                    if !retainedVerifiesFromEnvironment {
                        // Made over in place (`G47`): the record's ledger is the record's alone, so the next frame at this position
                        // finds the same object at the new key, and no ledger is allocated per translated cell per frame.
                        ledger.rebase(to: key, translation)
                        return .replay(ledger, moved: nil)
                    }
                    return .replay(ledger, moved: translation.hitboxes, elementBounds: translation.elementBounds,
                                   accessibility: translation.accessibility, geometry: translation.geometry,
                                   layoutOrigin: key.rects.count >= 2 ? (key.rects[0], key.rects[1]) : nil)
                case .refused(let reason):
                    noteRun(phase, "translationRefused: \(reason)")
                    memos.retained.noteTranslationRefused(reason: reason)
                    return .run(phase.grafted ? nil : openPrepaintWindow())
                }
            }
            // The same occurrence under render effects that moved by a translation (`RK-G`, `RK-S`): its
            // registrations are replayed moved, its accessibility records recomputed against the current effect
            // from their recorded pre-effect rects (`AT-A`), unless one cannot be (refused by name).
            if ledger.key.differsOnlyByEffects(to: key) {
                // A pure pan keeps the translation arm (`RK-G`); a zoom or rotation re-derives everything from the current effect
                // (`RZ-A`, `RZ-D`), with no delta; anything else is refused by name (`RZ-B`).
                let delta: (dx: Double, dy: Double)?
                switch key.extras.change(from: ledger.key.extras) {
                case .translation(let dx, let dy): delta = (dx, dy)
                case .affine:
                    delta = nil
                    // Window-space rects the replay does not recompute (`RZ-F`).
                    if !ledger.anchors.isEmpty { return refuseEffect("presentationAnchor", build: build, phase: phase) }
                    if !ledger.contextMenus.isEmpty { return refuseEffect("contextMenus", build: build, phase: phase) }
                case .refused(let reason):
                    return refuseEffect(reason, build: build, phase: phase)
                }
                // A noted frame moved with the effect: the transform runs again against the rebuilt proxy (`RL-E`, was `RG-C`).
                var movedGeometry: [GeometryNoteRecord]?
                if !ledger.geometry.isEmpty {
                    switch translatedGeometryNotes(ledger.geometry, ledger: ledger, affine: delta == nil) {
                    case .moved(let notes): movedGeometry = notes
                    case .refused(let reason): return refuseEffect(reason, build: build, phase: phase)
                    }
                }
                switch translatedAccessibility(of: ledger) {
                case .success(let accessibility):
                    if let moved = translatedHitboxes(of: ledger, by: delta) {
                        // Hover resolves after prepaint: the pointer is read against the hitboxes where they will stand (`RZ-D`).
                        if let point = mousePosition, moved.contains(where: { $0.contains(point) }) {
                            noteRun(phase, "pointerInMovedLedger")
                            return .run(phase.grafted ? nil : openPrepaintWindow())
                        }
                        memos.retained.prepaintHits += 1
                        memos.retained.skippedPrepaints += ledger.prepaints
                        // The anchors and context-menu records are drawn window rects (`MA-B`): a pure translation of the effects moves
                        // each by exactly that amount (`MA-H`). An affine change refused them above.
                        return .replay(ledger, moved: moved, elementBounds: nil, accessibility: accessibility, geometry: movedGeometry,
                                       windowShift: delta.map { (Float($0.dx), Float($0.dy)) })
                    }
                    noteRun(phase, "translationRefused: hitboxes \(ledger.hitboxes.count)")
                    memos.retained.noteTranslationRefused(reason: "hitboxes")
                case .failure(let refusal):
                    noteRun(phase, "translationRefused: \(refusal.reason)")
                    memos.retained.noteTranslationRefused(reason: refusal.reason)
                }
            } else if memos.translatesLayout, let combined = ledger.key.shiftAndEffects(to: key), let change = combined.effect {
                // The layout origin (or scroll offset) **and** the render effects around the occurrence moved together (`EL-B`, FS-O,
                // was a counted refusal `effectAndLayoutMoved`).
                return combinedPrepaintMode(ledger, shift: combined.shift, change: change, key: key, build: build, phase: phase)
            }
        }
        return .run(phase.grafted ? nil : openPrepaintWindow())
    }

    /// The prepaint decision of an occurrence whose layout moved and whose outer effects changed together (`EL-B`..`EL-G`): the
    /// ledger made over by `movedCombinedLedger` (the delta in the occurrence's own space, then the effect now in force), or run
    /// with the refusal counted by name. The effect refusals of the zoom arm are inherited as they are; a presentation anchor or a
    /// context-menu record refuses for a translation too (`EL-F`: its window shift would be the linear part times the delta).
    private func combinedPrepaintMode(_ ledger: PrepaintLedger, shift: LayoutShift, change: EffectChange, key: PrepaintKey,
                                      build: RetainedBuild, phase: RetainedPhase) -> RetainedPrepaintMode {
        let memos = stateTable.contentMemos
        if case .refused(let reason) = change {
            phase.effectRefusalCounted = true   // the paint's own count of the same relation is not repeated (`EL-M`)
            return refuseEffect(reason, build: build, phase: phase)
        }
        switch movedCombinedLedger(ledger, shift: shift, clip: key.ambient.clip, to: key) {
        case .refused(let reason):
            return refuseEffect(reason, build: build, phase: phase)
        case .moved(let translation):
            // Hover resolves after prepaint: the pointer is read against the hitboxes where they will stand (`FS-P`, `RZ-D`).
            if let point = mousePosition, translation.hitboxes.contains(where: { $0.contains(point) }) {
                noteRun(phase, "pointerInMovedLedger")
                return .run(phase.grafted ? nil : openPrepaintWindow())
            }
            memos.ledgerMoves += 1
            memos.retained.prepaintHits += 1
            memos.retained.skippedPrepaints += ledger.prepaints
            if !retainedVerifiesFromEnvironment {
                // Rebased to the whole new key, effect numbers included, with the moved hitboxes, locals and notes: the next frame
                // at this position is an exact hit (`EL-G`).
                let rebased = ledger.rebased(to: key, translation)
                phase.entry.record?.prepaint = rebased
                return .replay(rebased, moved: nil)
            }
            return .replay(ledger, moved: translation.hitboxes, elementBounds: translation.elementBounds,
                           accessibility: translation.accessibility, geometry: translation.geometry,
                           layoutOrigin: key.rects.count >= 2 ? (key.rects[0], key.rects[1]) : nil)
        }
    }

    /// The prepaint of an occurrence under an effect change a replay cannot carry: counted by name, run (`RZ-B`).
    private func refuseEffect(_ reason: String, build: RetainedBuild, phase: RetainedPhase) -> RetainedPrepaintMode {
        noteRun(phase, "translationRefused: \(reason)")
        stateTable.contentMemos.retained.noteTranslationRefused(reason: reason)
        return .run(phase.grafted ? nil : openPrepaintWindow())
    }

    /// How far the paint record stands from where the occurrence is now, when only its origin or scroll offset differ (`FS-D`):
    /// the geometric part of the paint key's relation, which is all a prepaint can read (the paint-only ambient is open later).
    func recordShiftAtPrepaint(_ old: RetainedRecord, phase: RetainedPhase, key: PrepaintKey, clipRelated: Bool = false) -> LayoutShift? {
        // A changed entry clip of the same count relates too, and a zero move with it, once the ledger's key relates by it (`FS-Y`): the paint
        // record is cut again from the new clip.
        let clipChanged = old.key.ambient.clip != key.ambient.clip
        guard !clipChanged || (clipRelated && old.key.ambient.clip.count == key.ambient.clip.count) else { return nil }
        return RetainedShape.shift(newRects: phase.rects, newNodeCount: phase.nodeCount, newShape: phase.shapeInterior,
                                   newOffset: key.ambient.offset, oldRects: old.key.rects, oldNodeCount: old.key.nodeCount,
                                   oldShape: old.key.shapeInterior, oldOffset: old.key.ambient.offset, allowZero: clipChanged)
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
        guard let log = prepaintLog else { preconditionFailure("the log was made above when absent") }
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
        guard let log = prepaintLog else { preconditionFailure("a prepaint window closed with none open") }
        log.recorders.removeAll { $0 === recorder }
        let to = log.current
        defer {
            if log.recorders.isEmpty { prepaintLog = nil }
        }
        let memos = stateTable.contentMemos
        if recorder.taint == nil, let moved = recorder.audit.movedChannel(to: prepaintAudit()) { recorder.taint = moved }
        let hitboxes = hitboxes(from: recorder.hitboxLow)
        if recorder.taint == nil,
           hitboxes.contains(where: { $0.handlers.hasDraggable }) {
            recorder.taint = "dragAndDrop"
        }
        guard recorder.taint == nil, let key = phase.prepaintKey else {
            RetainedTrace.emit("retained prepaint ineligible \(RetainedTrace.path(phase.build.key.id)) because \(recorder.taint ?? "unkeyed")")
            memos.retained.noteIneligible(.prepaint, reason: recorder.taint ?? "unkeyed")
            return nil
        }
        let ledger = PrepaintLedger(key: key)
        ledger.hitboxes = hitboxes
        if prepaintLog != nil, !hitboxChains.isEmpty {
            let chains = (recorder.hitboxLow..<hitboxCount).map { hitboxChains[$0] }
            if chains.contains(where: { $0 != nil }) { ledger.hitboxChains = chains }
        }
        ledger.axEmissions = axEmissions(from: recorder.axLow)
        let from = recorder.from
        // The clips of the window, kept only when a registration sits deeper than the entry (`FS-X`): the rest need none.
        if to.clips > from.clips, key.rects.count >= 2 {
            let entryDepth = key.ambient.depths.first ?? -1
            if hitboxes.contains(where: { $0.clipDepth != entryDepth }) || ledger.axEmissions.contains(where: { $0.clipDepth != entryDepth }) {
                var relative = Array(log.clips[from.clips..<to.clips])
                for index in relative.indices {
                    var c = relative[index]
                    c.clip = c.clip.moved(byX: -key.rects[0], y: -key.rects[1])
                    c.clip.parent = c.clip.parent >= Int32(from.clips) ? c.clip.parent - Int32(from.clips) : -1
                    c.clip.lo -= Int32(recorder.hitboxLow); c.clip.hi -= Int32(recorder.hitboxLow)
                    c.axLo -= Int32(recorder.axLow); c.axHi -= Int32(recorder.axLow)
                    relative[index] = c
                }
                ledger.innerClips = relative
            }
        }
        ledger.focus = Array(log.focus[from.focus..<to.focus])
        ledger.axNodes = Array(log.axNodes[from.axNodes..<to.axNodes])
        ledger.axNodeLocals = Array(log.axNodeLocals[from.axNodes..<to.axNodes])
        ledger.pressOnly = Array(log.pressOnly[from.pressOnly..<to.pressOnly])
        ledger.liveValues = Array(log.liveValues[from.liveValues..<to.liveValues])
        ledger.inertBlockers = Array(log.inertBlockers[from.inertBlockers..<to.inertBlockers])
        ledger.contextMenus = Array(log.contextMenus[from.contextMenus..<to.contextMenus])
        ledger.regions = log.regions[from.regions..<to.regions].map {
            SelectableTextRegion(id: $0.id, hitbox: $0.hitbox - recorder.hitboxLow, string: $0.string)
        }
        ledger.elementBounds = Array(log.elementBounds[from.elementBounds..<to.elementBounds])
        ledger.anchors = Array(log.anchors[from.anchors..<to.anchors])
        ledger.geometry = Array(log.geometry[from.geometry..<to.geometry])
        ledger.modifiers = Array(log.modifiers[from.modifiers..<to.modifiers])
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
    func requestRedo(_ entry: ContentMemoStore.Entry, site: String, phase: RetainedPhase) {
        redoEntries.append(entry)
        // `RK-AP`: the line that names the cause (built only while something listens): the site that could not replay, then what the prepaint and paint decisions found.
        RetainedTrace.emit("retained redo requested \(RetainedTrace.path(phase.build.key.id)) at \(site) because "
            + "prepaint [\((phase.prepaintInvalidation + [phase.prepaintNote].compactMap { $0 }).joined(separator: ", "))] "
            + "paint [\(phase.paintNote ?? "none")] grafted=\(phase.grafted) replayed=\(phase.replayed != nil)")
    }

    /// A channel this attempt wrote that a rollback cannot undo (`RK-AM`): the redo is window-wide, every replay off, as before. Nothing declares one
    /// today (the census of record 419 found none); a new store of that kind owes this call.
    func noteUnrestorable(_ channel: String) {
        unrestorableChannels.append(channel)
    }
}

// MARK: - The window's side of the redo

extension ContentMemoStore {
    /// Whether prepaint replay is in force for the build in progress: on, not in a redo, not backed off (`RK-D`).
    var prepaintReplayAllowed: Bool {
        replaysPrepaint && windowRedoes && (!redoInProgress || !redoScopes.isEmpty) && buildSerial >= prepaintSuspendedUntil
    }

    /// The frame was abandoned for `entries` (`RK-D` item 3): prepaint replay is suspended window-wide for the
    /// next eight builds, each entry for 8, 16 … 256, and this build's counters restart (the abandoned attempt's
    /// work was thrown away; `redos` counts the redo).
    func noteRedo(_ entries: [Entry], scoped: Bool = false) {
        let serial = buildSerial
        // A scoped redo leaves the window replaying (`RK-AM`); only a window-wide one (an escalation, an unrestorable channel, verify mode) suspends it.
        if !scoped, redoBackoff { prepaintSuspendedUntil = serial + 9 }
        var seen = Set<ObjectIdentifier>()
        for entry in entries where seen.insert(ObjectIdentifier(entry)).inserted {
            entry.quarantineUntil = serial + 1 + (8 << entry.redoExponent)
            RetainedTrace.emit("retained redo quarantine \(entry.id.map { RetainedTrace.path($0) } ?? "unkeyed") for \(entry.quarantineUntil - serial - 1) builds "
                + "until build \(entry.quarantineUntil) exponent \(entry.redoExponent) scoped=\(scoped && entry.id != nil)")
            if scoped, let id = entry.id { quarantine(id, until: entry.quarantineUntil) }
            entry.redoExponent = min(entry.redoExponent + 1, 5)
        }
        let evaluated = evaluations   // `CF-C`: the one loss with no repeat
        resetBuildCounters()
        carriedEvaluations = evaluated
        retained.redos = 1
    }

    /// Trace only: who holds `id` in quarantine, as `self until build N` or the scope's path (`RK-AP`).
    func quarantineOwner(of entry: Entry, id: GlobalElementID) -> String {
        if entry.quarantineUntil > buildSerial { return "self until build \(entry.quarantineUntil)" }
        if let scope = quarantinedScopes.first(where: { $0.until > buildSerial && id.isOrDescends(from: $0.id) }) {
            return "\(RetainedTrace.path(scope.id)) until build \(scope.until)"
        }
        return "none"
    }

    /// Keeps `id` and everything under it out of graft and prepaint replay until `until` (`RK-AN`): at most 64 scopes, the soonest to expire dropped first.
    func quarantine(_ id: GlobalElementID, until: Int) {
        quarantinedScopes.removeAll { $0.until <= buildSerial || $0.id == id }
        if quarantinedScopes.count >= Self.quarantinedScopeLimit {
            if let soonest = quarantinedScopes.indices.min(by: { quarantinedScopes[$0].until < quarantinedScopes[$1].until }) { quarantinedScopes.remove(at: soonest) }
        }
        quarantinedScopes.append(QuarantinedScope(id: id, until: until))
    }
}

// MARK: - Verify mode (`RK-N`)

/// What a frame holds after the root's paint, as comparable values (`RK-N`): the scene's arrays byte for byte, every
/// hitbox's fingerprint in order, the Tab order and focus registrations' effect, the accessibility records, the tallies
/// and the registrations of context menus, press-only actions and element bounds.
final class VerifySnapshotBox {
    let value: RetainedVerifySnapshot
    init(_ value: RetainedVerifySnapshot) { self.value = value }
}

struct RetainedVerifySnapshot {
    let rects: [MUIRect], glyphs: [MUIGlyph], images: [MUIImage], backdrops: [MUIBackdrop], transforms: [MUITransform]
    let counts: [Int]
    /// The scene's groups, recursively (`FS-Z`): per group the quad, its filter, and the bytes of its mask scene's and its content scene's rects, glyphs and images.
    /// The arrays above are the top level only, and under a clip that crosses the whole transcript is one group quad.
    let groups: [String]
    /// The unit ranges the frame noted (`animationStore.transitions.ranges`, `XF-H`): a replay that drops them loses the default fade of the next removal (`FS-Z`).
    let unitRanges: [String]
    let hitboxes: [String]
    let tabOrder: [GlobalElementID]
    let accessibility: [String]
    let axNodes: Set<GlobalElementID>
    let tallies: RegionTallies
    let contextMenus: Set<GlobalElementID>
    let regions: [String]
    let pressOnly: Set<GlobalElementID>
    let inertBlockers: [String]
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
        if groups != other.groups {
            let pairs = Array(zip(groups, other.groups))
            let at = pairs.firstIndex { $0.0 != $0.1 }.map { (offset: $0, element: pairs[$0]) }
            return "scene groups (\(groups.count) vs \(other.groups.count)) first difference \(String(describing: at))"
        }
        if unitRanges != other.unitRanges {
            let pairs = Array(zip(unitRanges, other.unitRanges))
            let at = pairs.firstIndex { $0.0 != $0.1 }.map { (offset: $0, element: pairs[$0]) }
            return "unit ranges (\(unitRanges.count) vs \(other.unitRanges.count)) first difference \(String(describing: at))"
        }
        if hitboxes != other.hitboxes {
            let first = zip(hitboxes.indices, zip(hitboxes, other.hitboxes)).first { $0.1.0 != $0.1.1 }
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
        if regions != other.regions { return "selectable text regions \(regions) vs \(other.regions)" }
        if pressOnly != other.pressOnly { return "press-only actions" }
        if inertBlockers != other.inertBlockers { return "inert chrome blockers" }
        if bounds != other.bounds { return "element bounds" }
        if tree != other.tree {
            let first = zip(tree.indices, zip(tree, other.tree)).first { $0.1.0 != $0.1.1 }
            return "layout tree (\(tree.count) vs \(other.tree.count) nodes) first difference \(String(describing: first))"
        }
        if let d = other.channels.difference(from: channels) { return "build calls on the tables: \(d)" }
        return nil
    }
}

extension Frame {
    /// `scene`'s groups as one line each, recursing into the group scenes and the mask scenes (`FS-Z`): the quad, the filter, and a hash of the bytes of each
    /// scene's rects, glyphs, images and group quads. Read in verify mode only.
    static func groupDigest(of scene: Scene, path: String) -> [String] {
        func hash<T>(_ array: [T]) -> Int {
            array.withUnsafeBytes { buffer in
                var hasher = Hasher()
                hasher.combine(bytes: buffer)
                return hasher.finalize()
            }
        }
        var out: [String] = []
        if scene.groups.isEmpty { return out }
        out.append("\(path) rects \(hash(scene.rects)) glyphs \(hash(scene.glyphs)) images \(hash(scene.images)) groups \(hash(scene.groups)) filters \(scene.groupFilters)")
        for index in scene.groups.indices {
            out.append(contentsOf: groupDigest(of: scene.groupScenes[index], path: path + "/g\(index)"))
            if let mask = scene.groupMasks[index] {
                out.append("\(path)/m\(index) rects \(hash(mask.rects)) glyphs \(hash(mask.glyphs)) images \(hash(mask.images))")
            }
            let content = scene.groupScenes[index]
            if content.groups.isEmpty {
                out.append("\(path)/g\(index) rects \(hash(content.rects)) glyphs \(hash(content.glyphs)) images \(hash(content.images))")
            }
        }
        return out
    }

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
            groups: Self.groupDigest(of: s, path: ""),
            unitRanges: animationStore.transitions.ranges.map { "\(sbPath($0.unit)) \($0.start) \($0.end)" },
            hitboxes: hitboxes(from: 0).map(\.fingerprint), tabOrder: focusRegistry.tabOrder,
            accessibility: axEmissions(from: 0).map {
                "\($0.id)|\($0.declared)|\(String(describing: $0.text))|\($0.isClickable)|\($0.isEnabled)|\($0.synthesizes)|\($0.portal)|\($0.geometry)|\($0.declaresAction)"
            },
            axNodes: Set(axNodes.keys), tallies: regionTallies, contextMenus: Set(contextMenuRecords.keys),
            regions: selectableTextRegions.map { "\($0.id)|\($0.hitbox)|\($0.string)" },
            pressOnly: Set(accessibilityPressOnly.keys), inertBlockers: inertChromeBlockers.map { "\($0)" }, bounds: elementBounds, tree: tree.structureDigest(),
            channels: stateTable.buildChannels(animation: animationStore))
    }
}
