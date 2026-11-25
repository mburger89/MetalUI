import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
@testable import MetalUI

// C14-h lane 1 (`RL-A`...`RL-D`, record 131): lifecycle scopes (`onAppear`, `onDisappear`, `onChange`, `.task`) and a modifier-key
// scope inside an `.equatable()` occurrence no longer refuse the graft (`BuildAudit.lifecycle`) or taint the prepaint ledger
// (`"modifierKeys"`): the graft journals the scopes' store notes and the ledger records the modifier note, a replay re-notes each into
// the `LifecycleStore` as a build would, and the store's own diff decides every delivery. Counts and delivered sequences only; the
// oracle is a window with `testingRetainedSubtrees = false`.
//
// Red on arrival at c55d44e8 (the lines are in record 131 section 3): tests 1, 2, 11 (the counters), 9 (no graft record to damage).
// Tests 3-6 and 8 are differentials that are green at c55d44e8 (nothing retained, so nothing differs); their mutations are what
// redden them (header of each).

@MainActor final class RLLog {
    var entries: [String] = []
}

@MainActor final class RLModel {
    var pad: Float = 10
    var value = 0
    var taskID = 0
    var shown = true
    var tag = 0
    var counter = 0
}

enum RLMode { case lifecycle, modifier, both }

/// One observed panel. Every lifecycle kind, the task and a shift-masked modifier scope, each logging its delivery.
private struct RLPanel: Component, @MainActor Equatable {
    let id: Int
    let mode: RLMode
    let value: Int
    let taskID: Int
    let tag: Int
    let log: RLLog
    let counter: Binding<Int>
    static func == (l: RLPanel, r: RLPanel) -> Bool {
        l.id == r.id && l.mode == r.mode && l.value == r.value && l.taskID == r.taskID && l.tag == r.tag
    }
    var content: some ElementGroup {
        switch mode {
        case .lifecycle:
            lifecycleBase
        case .modifier:
            Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
                .onModifierKeysChanged(mask: [.shift]) { o, n in log.entries.append("mod\(id) \(o.rawValue)>\(n.rawValue)") }
        case .both:
            lifecycleBase
                .onModifierKeysChanged(mask: [.shift]) { o, n in log.entries.append("mod\(id) \(o.rawValue)>\(n.rawValue)") }
        }
    }
    private var lifecycleBase: some ElementGroup {
        Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
            .onAppear { log.entries.append("appear\(id)") }
            .onDisappear { log.entries.append("disappear\(id)") }
            .onChange(of: value) { o, n in log.entries.append("c1-\(id) \(o)>\(n) counter=\(counter.wrappedValue)") }
            .onChange(of: value) { o, n in log.entries.append("c2-\(id) \(o)>\(n)") }
            .task(id: taskID) { log.entries.append("task\(id) start \(taskID)") }
    }
}

/// An outer occurrence holding an inner one (test 6).
private struct RLOuter: Component, @MainActor Equatable {
    let value: Int
    let tag: Int
    let log: RLLog
    let counter: Binding<Int>
    static func == (l: RLOuter, r: RLOuter) -> Bool { l.value == r.value && l.tag == r.tag }
    var content: some ElementGroup {
        VStack(spacing: 1) {
            RLPanel(id: 10, mode: .both, value: value, taskID: 0, tag: tag, log: log, counter: counter).equatable()
            Box().frame(width: Pixels(40), height: Pixels(10)).background(.accent)
                .onAppear { log.entries.append("outerAppear") }
        }
    }
}

private struct RLRoot: Component {
    let model: RLModel
    let log: RLLog
    let mode: RLMode
    let panels: Int
    var nested = false
    var siblings = false
    var content: some ElementGroup {
        let counter = Binding<Int>(get: { model.counter }, set: { model.counter = $0 })
        VStack(spacing: 2) {
            Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(model.pad))
            if siblings && model.shown {
                Box().frame(width: Pixels(40), height: Pixels(10)).background(.accent)
                    .onDisappear { log.entries.append("preD") }
                    .onChange(of: model.value) { o, n in log.entries.append("pre \(o)>\(n)") }
                    .onChange(of: model.value) { o, n in log.entries.append("pre2 \(o)>\(n)") }
            }
            if model.shown {
                if nested {
                    RLOuter(value: model.value, tag: model.tag, log: log, counter: counter).equatable()
                } else {
                    ForEach(0..<panels, id: \.self) { i in
                        RLPanel(id: i, mode: mode, value: model.value, taskID: model.taskID, tag: model.tag, log: log,
                                counter: counter).equatable()
                    }
                }
            }
            if siblings && model.shown {
                Box().frame(width: Pixels(40), height: Pixels(10)).background(.accent)
                    .onDisappear { log.entries.append("postD") }
                    .onChange(of: model.value) { o, n in log.entries.append("post \(o)>\(n)") }
            }
        }
    }
}

@MainActor
private func rlWindow(_ mode: RLMode, panels: Int = 2, nested: Bool = false, siblings: Bool = false, retained: Bool = true)
    throws -> (TestWindow, RLModel, RLLog) {
    let model = RLModel(), log = RLLog()
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(260))) {
        VStack(spacing: 0) { RLRoot(model: model, log: log, mode: mode, panels: panels, nested: nested, siblings: siblings) }
    }
    w.window.testingRetainedSubtrees = retained
    return (w, model, log)
}

@MainActor private func rlRedraw(_ w: TestWindow, _ n: Int = 1) async {
    for _ in 0..<n {
        w.window.setNeedsRedraw(); w.tick()
        for _ in 0..<2 { await Task.yield() }   // a task body started off the immediate path (macOS 14-25, Linux)
    }
}

private let rlVerifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"

private var rlVerifying: Bool {
    ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1"
}

/// 1 (`RL-A`, `RL-C`). Two panels with lifecycle scopes: on a steady frame neither refuses the graft by name `lifecycle` and both graft.
/// Red at c55d44e8: `testingGraftRefusals` holds `lifecycle` twice, `retainedGrafts == 0`, `retainedIneligibleReasons["lifecycle"] == 2`.
/// Mutation: drop the journal append in `LifecycleStore.note`.
@Test(.enabled(if: !rlVerifying, rlVerifyNote)) @MainActor
func aSteadyOccurrenceWithLifecycleScopesGrafts() async throws {
    let (w, _, log) = try rlWindow(.lifecycle)
    await rlRedraw(w, 8)
    let f = w.lastFrameWork
    #expect(!w.window.testingGraftRefusals.contains("lifecycle"), "\(w.window.testingGraftRefusals)")
    #expect(f.retainedIneligibleReasons["lifecycle", default: 0] == 0, "\(f.retainedIneligibleReasons)")
    #expect(f.retainedGrafts == 2, "both panels graft: \(f.retainedGrafts)")
    #expect(log.entries.filter { $0.hasPrefix("appear") }.count == 2, "\(log.entries)")
}

/// 2 (`RL-B`). Two panels with a modifier scope only: the ledger is not tainted by name `modifierKeys` and both prepaints replay.
/// Red at c55d44e8: `retainedIneligibleReasons["modifierKeys"] == 2`, `retainedPrepaintHits == 0`.
/// Mutation: restore `prepaintLog?.taint("modifierKeys")` in `ModifierKeysScope.prepaintGroup`.
@Test(.enabled(if: !rlVerifying, rlVerifyNote)) @MainActor
func aSteadyOccurrenceWithAModifierScopeReplaysItsLedger() async throws {
    let (w, _, _) = try rlWindow(.modifier)
    await rlRedraw(w, 8)
    let f = w.lastFrameWork
    #expect(f.retainedIneligibleReasons["modifierKeys", default: 0] == 0, "\(f.retainedIneligibleReasons)")
    #expect(f.retainedPrepaintIneligible == 0, "\(f.retainedPrepaintIneligible)")
    #expect(f.retainedPrepaintHits == 2, "both prepaints replay: \(f.retainedPrepaintHits)")
}

/// The delivery log of a script, one entry per step, for a window with retention `retained`.
@MainActor private func rlScript(retained: Bool, mode: RLMode = .both, siblings: Bool = false) async throws -> [String] {
    let (w, model, log) = try rlWindow(mode, siblings: siblings, retained: retained)
    var out: [String] = []
    func step(_ name: String, _ act: () async -> Void) async {
        let before = log.entries.count
        await act()
        out.append("\(name): \(log.entries[before...].joined(separator: " | "))")
    }
    await rlRedraw(w, 6)
    out.append("warm: \(log.entries.joined(separator: " | "))")
    await step("steady") { await rlRedraw(w, 4) }
    await step("value") { model.counter = 7; model.value += 1; await rlRedraw(w, 3) }
    await step("steady2") { await rlRedraw(w, 3) }
    await step("taskID") { model.taskID += 1; await rlRedraw(w, 3) }
    await step("shift down") { w.pressModifiers([.shift]); await rlRedraw(w, 3) }
    await step("command down") { w.pressModifiers([.shift, .command]); await rlRedraw(w, 2) }
    await step("all up") { w.pressModifiers([]); await rlRedraw(w, 3) }
    await step("shift again") { w.pressModifiers([.shift]); await rlRedraw(w, 2) }
    await step("hide") { model.shown = false; await rlRedraw(w, 3) }
    await step("hidden steady") { await rlRedraw(w, 2) }
    await step("show") { model.shown = true; await rlRedraw(w, 3) }
    await step("steady3") { await rlRedraw(w, 4) }
    await step("everything") { model.value += 1; model.taskID += 1; w.pressModifiers([]); await rlRedraw(w, 3) }
    return out
}

/// 3 (`RL-A`, `RL-B`, `RL-L`). Retention on delivers exactly the callbacks, in the order, a window with retention off does over appear,
/// steady frames, an `onChange` value change (its action reads a `Binding` live), a task id change, a masked and an unmasked modifier
/// change, a disappearance and a re-insertion. Mutations: (i) skip the lifecycle re-note in `Frame.reapply` (a spurious disappear and
/// appear), (ii) re-note the modifier from a recorded value (a modifier change is missed), (iii) re-note at order 0.
@Test @MainActor
func lifecycleDeliveriesThroughRetentionEqualAnUnretainedWindow() async throws {
    let on = try await rlScript(retained: true)
    let off = try await rlScript(retained: false)
    #expect(on == off, "\non:  \(on)\noff: \(off)")
    let joined = on.joined(separator: "\n")
    #expect(joined.contains("c1-0 0>1 counter=7"), "the action reads the binding live: \(on)")
    #expect(joined.contains("mod0 0>1024") || joined.contains("mod0 0>"), "the shift change delivers: \(on)")
    #expect(on.first(where: { $0.hasPrefix("steady:") }) == "steady: ", "a steady frame delivers nothing: \(on)")
    #expect(on.first(where: { $0.hasPrefix("hide:") })?.contains("disappear0") == true, "\(on)")
    #expect(on.first(where: { $0.hasPrefix("show:") })?.contains("appear0") == true, "\(on)")
}

/// 4 (`RL-C`). Simultaneous changes in the occurrence and in siblings before and after it, and then their disappearances (the panels graft), deliver in `LC-F`'s order (reverse
/// pre-order) exactly as an unretained window does. Mutation (iii): the re-note ignores `base + rel`.
@Test @MainActor
func aGraftedOccurrenceKeepsLifecycleOrderAmongSiblings() async throws {
    func run(retained: Bool) async throws -> [String] {
        let (w, model, log) = try rlWindow(.lifecycle, siblings: true, retained: retained)
        await rlRedraw(w, 6)
        log.entries.removeAll()
        model.value += 1
        await rlRedraw(w, 2)
        let changed = log.entries
        await rlRedraw(w, 6)   // the panels graft again before they leave
        log.entries.removeAll()
        model.shown = false; await rlRedraw(w, 2)
        let hidden = log.entries
        log.entries.removeAll()
        model.shown = true; await rlRedraw(w, 2)
        return changed + ["--"] + hidden + ["--"] + log.entries
    }
    let on = try await run(retained: true), off = try await run(retained: false)
    #expect(on == off, "\non:  \(on)\noff: \(off)")
    #expect(on.contains { $0.hasPrefix("pre") } && on.contains { $0.hasPrefix("post") } && on.contains { $0.hasPrefix("c1-1") },
            "the script delivers from all three places: \(on)")
    // The disappearances of grafted panels sort among the siblings' by the orders the graft re-noted (`RL-C`).
    let hiddenLog = on.drop { $0 != "--" }.dropFirst().prefix { $0 != "--" }
    #expect(Array(hiddenLog) == ["postD", "disappear1", "disappear0", "preD"], "\(hiddenLog)")
    // Reverse pre-order (`LC-F`): the later sibling first, the panels' scopes between (the later panel first), the earlier sibling's last (the order unretained windows measure).
    let changed = on.prefix { $0 != "--" }.map { String($0.prefix { $0 != " " }) }
    #expect(changed == ["post", "c1-1", "c2-1", "c1-0", "c2-0", "pre", "pre2"], "\(changed)")
}

/// 5 (`RL-B`). A modifier change across a replayed ledger delivers once; a masked-out one delivers nothing; both equal an unretained
/// window's. Mutation (ii): replay the recorded value.
@Test(.enabled(if: !rlVerifying, rlVerifyNote)) @MainActor
func aModifierChangeAcrossAReplayedLedgerDelivers() async throws {
    func run(retained: Bool) async throws -> (log: [String], hits: Int) {
        let (w, _, log) = try rlWindow(.modifier, retained: retained)
        await rlRedraw(w, 6)
        log.entries.removeAll()
        w.pressModifiers([.shift])
        let hits = w.lastFrameWork.retainedPrepaintHits
        await rlRedraw(w, 2)
        w.pressModifiers([.shift, .command])   // masked out: nothing
        await rlRedraw(w, 2)
        w.pressModifiers([])
        await rlRedraw(w, 2)
        return (log.entries, hits)
    }
    let on = try await run(retained: true), off = try await run(retained: false)
    #expect(on.log == off.log, "\(on.log) vs \(off.log)")
    #expect(on.log.count == 4, "two panels, down and up: \(on.log)")
    #expect(on.hits == 2, "the change frame replays both ledgers: \(on.hits)")
}

/// A root whose panels sit under a render-effect `.offset` pan (`pan`) or under a header the layout shifts (`!pan`), `model.pad` the amount.
private struct RLShiftRoot: Component {
    let model: RLModel
    let log: RLLog
    let pan: Bool
    var content: some ElementGroup {
        let counter = Binding<Int>(get: { model.counter }, set: { model.counter = $0 })
        if pan {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { i in
                        RLPanel(id: i, mode: .modifier, value: 0, taskID: 0, tag: 0, log: log, counter: counter).equatable()
                    }
                }
                .offset(x: Pixels(model.pad), y: Pixels(model.pad / 2))
            }
            .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading)
        } else {
            VStack(spacing: 2) {
                Box().frame(height: Pixels(model.pad))
                ForEach(0..<2, id: \.self) { i in
                    RLPanel(id: i, mode: .modifier, value: 0, taskID: 0, tag: 0, log: log, counter: counter).equatable()
                }
            }
        }
    }
}

/// 5b (`RL-B`). A modifier scope inside an occurrence that translates while steady (a whole-pixel `.offset` pan, or a layout shift from a
/// growing header): the rebased ledger carries its modifier note, so a modifier change after the shift delivers once per panel and no
/// spurious report or disappearance is delivered, equal to an unretained window's. Mutation: delete `copy.modifiers = modifiers` in
/// `PrepaintLedger.rebased`.
@Test(.enabled(if: !rlVerifying, rlVerifyNote), arguments: [false, true]) @MainActor
func aRebasedLedgerCarriesItsModifierNote(pan: Bool) async throws {
    func run(retained: Bool) async throws -> (log: [String], translated: Int, hits: Int) {
        let model = RLModel(), log = RLLog()
        let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(260))) {
            VStack(spacing: 0) { RLShiftRoot(model: model, log: log, pan: pan) }
        }
        w.window.testingRetainedSubtrees = retained
        await rlRedraw(w, 6)
        w.pressModifiers([.shift]); await rlRedraw(w, 2)
        var translated = 0, hits = 0
        func shift() async {
            model.pad += 4
            w.window.setNeedsRedraw()
            w.resetFrameWork()
            await rlRedraw(w)
            translated += w.lastFrameWork.retainedTranslated; hits += w.lastFrameWork.retainedPrepaintHits
        }
        for _ in 0..<2 { await shift() }          // the first rebases, the second replays the rebased ledger
        w.pressModifiers([]); await rlRedraw(w, 2)
        for _ in 0..<2 { await shift() }
        w.pressModifiers([.shift]); await rlRedraw(w, 2)
        await shift()
        w.pressModifiers([]); await rlRedraw(w, 2)
        return (log.entries, translated, hits)
    }
    let on = try await run(retained: true), off = try await run(retained: false)
    #expect(on.log == off.log, "\(on.log) vs \(off.log)")
    #expect(on.log.count == 8, "two panels, shift down, up, down, up: \(on.log)")
    #expect(on.translated > 0 && on.hits > 0, "the shifts replay translated: \(on.translated) / \(on.hits)")
}

/// 6 (`RL-C`). An inner occurrence inside an outer one that grafts: the inner notes are journaled once, no scope appears twice and the
/// deliveries equal an unretained window's over a value change and a re-insertion. Mutation: let `reapply`'s re-note journal twice.
@Test @MainActor
func aNestedOccurrencesLifecycleNotesAreJournaledOnce() async throws {
    func run(retained: Bool) async throws -> [String] {
        let (w, model, log) = try rlWindow(.both, nested: true, retained: retained)
        await rlRedraw(w, 8)
        model.value += 1
        await rlRedraw(w, 3)
        model.shown = false; await rlRedraw(w, 2)
        model.shown = true; await rlRedraw(w, 3)
        await rlRedraw(w, 4)
        return log.entries
    }
    let on = try await run(retained: true), off = try await run(retained: false)
    #expect(on == off, "\non:  \(on)\noff: \(off)")
    #expect(on.filter { $0 == "outerAppear" }.count == 2, "appears at the start and at the re-insertion only: \(on)")
}

/// 8 (`TF-A`, `PX-F`). A task id change through a graft cancels the running task and starts the new one: one task runs, the starts are
/// the ids in order, and the box is carried across grafted frames. Mutation: re-note a fresh `Entry` (no running box carried).
@Test @MainActor
func aTaskIdChangeThroughAGraftCancelsThenStarts() async throws {
    func run(retained: Bool) async throws -> (log: [String], running: Int, grafts: Int) {
        let (w, model, log) = try rlWindow(.lifecycle, panels: 1, retained: retained)
        await rlRedraw(w, 8)
        let grafts = w.lastFrameWork.retainedGrafts
        model.taskID = 5
        await rlRedraw(w, 3)
        await rlRedraw(w, 4)
        return (log.entries.filter { $0.hasPrefix("task") }, w.window.animationStore.lifecycle.runningTaskCount, grafts)
    }
    let on = try await run(retained: true), off = try await run(retained: false)
    #expect(on.log == off.log && on.log == ["task0 start 0", "task0 start 5"], "\(on.log) vs \(off.log)")
    #expect(on.running == off.running && on.running == 1, "one task runs: \(on.running) vs \(off.running)")
    if !rlVerifying { #expect(on.grafts == 1, "the panel grafted: \(on.grafts)") }
}

/// 9 (`RK-N`, `RL-D`). A verified graft whose lifecycle notes were dropped traps, naming `lifecycle`. Mutation: remove the
/// `lifecycleStore` comparison from `BuildChannels.difference`.
@Test @MainActor
func verifyChannelNamesALifecycleStoreMismatch() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setenv("METALUI_VERIFY_RETAINED", "1", 1)
        await MainActor.run {
            guard let (w, _, _) = try? rlWindow(.lifecycle, panels: 1) else { return }
            for _ in 0..<8 { w.window.setNeedsRedraw(); w.tick() }
            let damaged = w.window.testingCorruptGraftRecords("lifecycleNotes")
            guard damaged > 0 else { print("no graft record to damage"); return }
            w.window.setNeedsRedraw(); w.tick()
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("build calls on the tables: lifecycle"), "the trap names the channel: \(stderr)")
}

/// 11 (`RL-A`, `RL-B`). A ViewportView-shaped tree (three panels, each with lifecycle scopes and a modifier scope) is eligible on a steady
/// frame in all three channels and grafts every panel. Red at c55d44e8: ineligible reasons `lifecycle` and `modifierKeys` > 0, grafts 0.
@Test(.enabled(if: !rlVerifying, rlVerifyNote)) @MainActor
func aViewportShapedTreeIsRetainedEligible() async throws {
    let (w, _, _) = try rlWindow(.both, panels: 3)
    await rlRedraw(w, 8)
    let f = w.lastFrameWork
    #expect(f.retainedIneligible == 0 && f.retainedPrepaintIneligible == 0 && f.retainedGraftIneligible == 0,
            "\(f.retainedIneligible)/\(f.retainedPrepaintIneligible)/\(f.retainedGraftIneligible) \(f.retainedIneligibleReasons)")
    #expect(f.retainedGrafts == 3, "\(f.retainedGrafts)")
}

/// 7 (`RL-C`, `RL-D`). A redo's rollback leaves the store with no registration and no unjournaled activity, and a twin build holds one note
/// per key: the journal's own counter is reset with the rest. Mutation: drop `journaledActivity = 0` from `LifecycleStore.rollbackBuild`
/// (`buildActivity` reads negative, so the next window would refuse by name `lifecycle`).
@Test @MainActor
func aRedoDropsJournaledLifecycleNotes() {
    let journal = BuildJournal(), store = LifecycleStore()
    store.buildJournal = journal
    journal.open.append(GraftRecorder())
    var ran = 0
    let scope = GlobalElementID.child(of: nil, at: 0, name: ElementID("$lifecycle0"))
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    func build() { store.note(.appear { ran += 1 }, scope: scope, owner: owner, order: store.reserveOrder()) }
    build()
    #expect(journal.events.count == 1 && store.buildActivity == 0, "journaled: \(journal.events.count) \(store.buildActivity)")
    store.rollbackBuild()
    #expect(store.buildActivity == 0, "a rollback resets the journal's counter: \(store.buildActivity)")
    build()
    #expect(store.buildActivity == 0, "\(store.buildActivity)")
    store.endFrame(liveGhosts: [], departed: nil)
    #expect(store.takeEvents().count == 1, "one appearance, not two")
}

@MainActor enum RLBypass { static var store: LifecycleStore? }

private struct RLBypassCard: Component, @MainActor Equatable {
    let tag: Int
    static func == (l: RLBypassCard, r: RLBypassCard) -> Bool { l.tag == r.tag }
    var content: some ElementGroup { RLBypassInner() }
}

/// Built inside the card's graft window (the card's own getter runs before it opens).
private struct RLBypassInner: Component {
    var content: some ElementGroup {
        let _ = RLBypass.store?.testingBypassJournal()
        Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
    }
}

/// 10 (`RL-D`). The tripwire: a registration that bypasses the journal inside an occurrence's build window refuses the graft by name
/// `lifecycle`; the control (no bypass) refuses nothing. Mutation: delete the `lifecycle` comparison in `BuildAudit.movedChannel`.
@Test(.enabled(if: !rlVerifying, rlVerifyNote)) @MainActor
func anUnjournaledRegistrationRefusesTheGraftByName() async throws {
    let model = RLModel()
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(100))) {
        VStack(spacing: 0) { RLBypassCard(tag: model.tag).equatable() }
    }
    await rlRedraw(w, 8)
    #expect(w.lastFrameWork.retainedGrafts == 1)
    model.tag += 1
    await rlRedraw(w, 1)
    #expect(!w.window.testingGraftRefusals.contains("lifecycle"), "the control: \(w.window.testingGraftRefusals)")
    RLBypass.store = w.window.animationStore.lifecycle
    defer { RLBypass.store = nil }
    model.tag += 1
    await rlRedraw(w, 1)
    #expect(w.window.testingGraftRefusals == ["lifecycle"], "\(w.window.testingGraftRefusals)")
}
