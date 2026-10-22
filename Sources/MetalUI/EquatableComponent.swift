/// A `Component` whose `content` is not evaluated again while its value is
/// unchanged (SwiftUI's `View.equatable()`, `IV-B`), and whose **prepaint and
/// paint** are replayed while nothing they read has changed (retained subtrees,
/// `SB-B`, `RK-E`); made by ``Component/equatable()``.
///
/// The component keeps its identity level, `@State` slots and cursor index: the
/// wrapper adds none of its own. The build recursion (`requestGroupLayout`) and
/// layout run exactly as for the bare component. **Prepaint** registers the
/// subtree's hitboxes, focus stops, accessibility records, context menus and
/// region tallies; they are recorded once and replayed in the same order while
/// the occurrence's rectangles and the layout under it, the clip, offset, layer,
/// render effects, built-in environment and pointer gates around it are equal
/// (a translation of the render effects around it replays too, `RK-S`).
/// **Paint** runs, once, when the occurrence is first drawn or anything it
/// depends on changes, and is then replayed from a record of the scene
/// primitives it made, in the order a fresh run makes them. What it depends on
/// is the **replay key**: the occurrence's rectangles and the layout under it,
/// the clip, offset, layer, opacity and open paint scopes at paint, the built-in
/// environment and theme, the window's scale and size, and whether the pointer, a
/// press or focus is inside it. If a replayed prepaint meets a paint-time
/// ambient that differs (an ancestor's opacity or shadow changed), the window
/// builds the frame again with every replay off (`RK-D`).
///
/// There is no initialiser: make one with `equatable()`.
public struct EquatableComponent<C: Component & Equatable>: ElementGroup {
    var component: C

    init(component: C) { self.component = component }

    public typealias GroupLayout = ComponentLayout<C>
    public typealias GroupPrepaint = ComponentPrepaint<C>

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], ComponentLayout<C>) {
        let frame = pass.frame
        let table = frame.stateTable
        let store = table.contentMemos
        // The build window opens before the component binds its own `@State` (`SB-K`).
        let window = store.retainsSubtrees ? RetainedBuildWindow(frame: frame) : nil
        // `StateBinder.bind` collects the readings of the declared `@Environment`s in its one pass (`EE-A`).
        frame.environmentReadings = []
        let id = component.enterComponent(under: parent, at: &cursor, pass: &pass)
        let readings = frame.environmentReadings ?? []
        frame.environmentReadings = nil
        var materialized: C.Content
        var entry: ContentMemoStore.Entry?
        let key = ContentMemoStore.Key(id: id, type: ObjectIdentifier(C.self))
        if let stateOrdinals = StateBinder.memoShape(of: C.self),
           !readings.contains(where: \.isUncomparable) {   // an uncomparable reading is refused (`EE-B`)
            let stateIDs = stateOrdinals.map {
                GlobalElementID.child(of: id, at: $0, name: ElementID("$state\($0)"))
            }
            materialized = store.materialize(component, id: id, stateIDs: stateIDs, table: table, readings: readings) {
                component.content
            }
            entry = store.entry(for: key)
        } else {
            store.noteRefusal()
            materialized = component.content
        }
        guard let window, let entry else {
            return component.finishComponent(&materialized, id: id, pass: &pass)
        }
        // A grafted occurrence skips the build recursion (`RK-B`): its rows are copied from the last build's segment
        // and the journal of that build is applied again. Its prepaint and paint are replays, or the frame is redone.
        let buildKey = frame.graftBuildKey()
        if let record = frame.graftRecord(for: entry, id: id, key: buildKey) {
            let tops = frame.graftOccurrence(record)
            let layout = ComponentLayout<C>(grafted: RetainedGraft(record: record))
            layout.storage.retained = window.finish(frame: frame, key: key, nodes: tops, observed: false)
            return (tops, layout)
        }
        // The build recursion runs in an observation window of its own (`SB-D`): a descendant
        // getter that reads an `@Observable` invalidates this occurrence's record.
        let observed = entry.needsObservation
        let evaluationsBefore = store.evaluationsSoFar
        let graftWindow = store.recordsGrafts ? frame.openGraftWindow() : nil
        let result: ([LayoutNodeID], ComponentLayout<C>)
        if observed {
            RetainedTestingHooks.buildWindowsOpened += 1
            result = entry.buildSession.run(entry: entry, store: store) {
                component.finishComponent(&materialized, id: id, pass: &pass)
            }
        } else {
            result = component.finishComponent(&materialized, id: id, pass: &pass)
        }
        // A descendant whose content ran this frame may have changed what the record holds, though this
        // occurrence's own windows never saw its reads (it was skipped when they were open): no replay.
        // `DM-L`: when only this happened (this window was closed because the standing record was complete and clean: no fire, serial equal),
        // the build's own reads are those the record's still-armed build session covers, so the record this miss makes keeps its build
        // half instead of forcing a second miss on `coverage.build`; the prepaint window opens (`observedChange` is set) and covers the rest.
        let descendantRan = store.evaluationsSoFar != evaluationsBefore
        if descendantRan { entry.observedChange = true }
        // The subtree placement memo (`SB-AD`) restores these roots' rects where they stand.
        for node in result.0 { frame.tree.markPlacementRoot(node) }
        result.1.storage.retained = window.finish(frame: frame, key: key, nodes: result.0, observed: observed || descendantRan)
        if let graftWindow {
            let closed = frame.closeGraftWindow(graftWindow, tops: result.0, contentSerial: entry.serial, key: buildKey)
            if let record = closed.record {
                entry.graft = record
            } else {
                entry.graft = nil
                store.retained.noteIneligible(.graft, reason: closed.refusal ?? "unknown")
                store.graftRefusals.append(closed.refusal ?? "unknown")
                RetainedTrace.emit("retained graft ineligible \(RetainedTrace.path(id)) because \(closed.refusal ?? "?")")
            }
        }
        return result
    }

    public mutating func prepaintGroup(layout: inout ComponentLayout<C>,
                                       pass: inout PrepaintPass) -> ComponentPrepaint<C> {
        let grafted = layout.storage.graft != nil
        guard let build = layout.storage.retained,
              let phase = pass.frame.retainedPrepaintPhase(build: build) else {
            return component.prepaintGroup(layout: &layout, pass: &pass)   // traps by name for a graft (`RK-B`)
        }
        phase.grafted = grafted
        let frame = pass.frame
        // The ledger of what the prepaint registered replays while the prepaint key is equal (`RK-C`, `RK-E`);
        // the occurrence's element prepaint does not run, so its paint must be a replay too (`RK-B`).
        let mode = frame.retainedPrepaintDecision(phase)
        if case .replay(let ledger, let moved, let movedBounds, let accessibility, let geometry) = mode {
            frame.replayPrepaintLedger(ledger, hitboxes: moved, elementBounds: movedBounds, accessibility: accessibility,
                                       geometry: geometry)
            phase.replayed = ledger
            return ComponentPrepaint<C>(replayedBy: phase)
        }
        // A grafted occurrence has no element layout to prepaint: the prepaint key (or the pointer, the
        // keyboard focus, a quarantine) decided against the replay the graft counted on, so the frame is built
        // again with every graft and replay off (`RK-C`, `RK-D`).
        if grafted {
            frame.requestRedo(phase.entry)
            phase.abandoned = true
            return ComponentPrepaint<C>(replayedBy: phase)
        }
        var recorder: PrepaintRecorder?
        if case .run(let r) = mode { recorder = r }
        // Prepaint runs in an observation window of its own (`SB-V`): an `@Observable` read there that a
        // prepaint state carries into paint kills the record.
        let result: ComponentPrepaint<C>
        let readLow = frame.stateTable.readJournal.count
        defer { phase.prepaintReads = readLow..<frame.stateTable.readJournal.count }
        if phase.prepaintObserved {
            RetainedTestingHooks.prepaintWindowsOpened += 1
            result = phase.entry.prepaintSession.run(entry: phase.entry, store: frame.stateTable.contentMemos) {
                component.prepaintGroup(layout: &layout, pass: &pass)
            }
        } else {
            result = component.prepaintGroup(layout: &layout, pass: &pass)
        }
        if let recorder { phase.ledger = frame.closePrepaintWindow(recorder, phase: phase) }
        result.storage.retained = phase
        return result
    }

    public mutating func paintGroup(layout: inout ComponentLayout<C>,
                                    prepaint: inout ComponentPrepaint<C>,
                                    pass: inout PaintPass) {
        guard let phase = prepaint.storage.retained else {
            component.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
            return
        }
        let frame = pass.frame
        if phase.abandoned { return }   // the frame is being redone (`RK-C`)
        switch frame.retainedPaintDecision(phase) {
        case .hit(let record):
            frame.replayPaint(record, translated: phase.translatedPaint, scene: phase.translatedScene)
        case .plain:
            if phase.replayed != nil || phase.grafted { frame.requestRedo(phase.entry); return }
            component.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
        case .record(let recorder, let key, let old):
            // A replayed prepaint left no element state to paint from: the frame is redone (`RK-C`).
            if phase.replayed != nil || phase.grafted { frame.requestRedo(phase.entry); return }
            frame.openRecorderWindow(recorder)
            phase.entry.paintSession.run(entry: phase.entry, store: frame.stateTable.contentMemos) {
                component.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
            }
            frame.finishRetainedPaint(phase, recorder: recorder, key: key, old: old)
        }
    }
}

extension Component where Self: Equatable {
    /// Skips this component's `content` getter while its value is `==` to the
    /// value of its last evaluation (SwiftUI's `View.equatable()`), and replays its
    /// paint while nothing it reads has changed.
    ///
    /// The content is a function of the value, the component's own `@State` and
    /// the `@Observable` properties it reads; `==` decides for every stored
    /// property, closures and class references included. An `@Observable` read
    /// of the last evaluation that changes, or a write to the component's own
    /// `@State`, re-evaluates it whatever `==` says. A `Binding` input is a value:
    /// if `content` reads `binding.wrappedValue`, include it in `==`. **A component that
    /// declares `@Environment` is skipped while the values it declares are unchanged**: the
    /// window compares what each declared property reads at the component's position — an
    /// `Equatable` value by `==`, a class by identity, an `@Observable` object by instance
    /// (its read properties by the observation session) — and a synthesized `==` cannot see
    /// an `Environment` property, so write `==` over the stored inputs. A declared property
    /// the getter never reads still counts. **A `@FocusState` is a
    /// slot like `@State`**: a focus change the window reconciles writes it, so the component
    /// is evaluated again when its own focus state moves and skipped otherwise. **A component
    /// is evaluated every frame and counted as a refusal** when it reads an environment value
    /// that cannot be compared (a closure, a struct holding one, `\.self`).
    ///
    /// **What is saved.** The getter, and — when the occurrence is laid out where it
    /// was and its surroundings at paint are unchanged — the paint of everything
    /// under it. **The contract that buys the second half:** the subtree's picture is
    /// a function of the value, the component's `@State`, the `@Observable`
    /// properties its elements read in a getter, `prepaint` or `paint`, and the
    /// built-in environment; an element under it that draws from anything else (a
    /// global, a `Binding` read in `paint`, the clock) must not be under an
    /// `.equatable()` that cannot see the change. The build recursion and layout
    /// still run every frame; hit testing, focus and accessibility are replayed from
    /// the registrations of the frame the subtree last ran, in the same order. A
    /// subtree that scrolls, edits text, animates, shows a popover, draws a
    /// `GPUSurface` or sits under a custom environment key whose value cannot be compared
    /// paints and prepaints as it always did (counted in `FrameWork.retainedIneligible` and
    /// `retainedPrepaintIneligible`).
    public func equatable() -> EquatableComponent<Self> {
        EquatableComponent(component: self)
    }
}
