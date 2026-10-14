import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Observation
import Testing

// C14b-2 lane 2 (`RK-B`, `RK-F`, `RK-N`; record 110): the graft. An `.equatable()` occurrence whose content memo hit, whose
// prepaint ledger and paint record are valid and whose build-visible context is equal does not run its build recursion:
// its layout rows are copied from the last build and the calls that build made on the tables are applied again. Every
// differential draws two windows from one builder, one grafting and one retaining nothing, and compares what the frame
// hands the platform and the state table's entries. Counts, never time. The kernel's side is
// `MetalUILayoutTests/GraftKernelTests.swift`.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

// MARK: 16 — the build recursion is skipped

/// 16 — on the bracket node drag the occurrences that did not change skip their build recursion: what ran plus what the grafts
/// stood for is `fb9a7e42`'s 798 element requests in every arm, and the graft-off arm (prepaint replay on, lane 1's tree)
/// reads 798 with nothing skipped. **Red before:** `retainedGrafts` and `retainedSkippedRequests` read 0 (the graft off).
/// **Mutation:** `graftsBuild` forced off reddens the `> 0` arms; `skippedRequests` not counted reddens the sum.
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
func theBuildRecursionIsSkippedForAnUnchangedSubtree(arm: BracketArm) throws {
    let off = try bracketDragFrames(arm: arm, steps: 20, retained: true, prepaint: true, graft: false).frames[10]
    #expect(off.elementRequests == 798 && off.retainedSkippedRequests == 0 && off.retainedGrafts == 0)
    let on = try bracketDragFrames(arm: arm, steps: 20, retained: true, prepaint: true, graft: true).frames[10]
    #expect(on.elementRequests + on.retainedSkippedRequests == 798, "conservation against fb9a7e42: \(on.elementRequests) + \(on.retainedSkippedRequests)")
    if arm != .environment {
        #expect(on.retainedGrafts > 0 && on.retainedSkippedRequests > 0 && on.retainedGraftedNodes > 0)
        #expect(on.elementRequests < off.elementRequests)
    }
    #expect(on.retainedRedos == 0, "a node drag changes no ambient and moves no unchanged subtree: \(on.retainedRedos)")
}

// MARK: 22 — the node drag, counted after the graft

/// One arm's per-frame work at the node drag's tenth frame with the graft: taken by this test's first run on the lane-2
/// tree (record 110 §8) and pinned as literals, **red on arrival** against lane 1's tree (where `elementRequests` reads
/// 798 and nothing is grafted). Everything the graft must not move is compared against `fb9a7e42`'s frame in the same
/// breath: the layout counts, the scene, the paints.
private struct AfterGraftFrame {
    let arm: BracketArm
    let requests: Int, skippedRequests: Int, grafts: Int, graftIneligible: Int, graftedNodes: Int
    let prepaints: Int, prepaintHits: Int
}
private let afterGraftFrames: [AfterGraftFrame] = [
    AfterGraftFrame(arm: .value, requests: 208, skippedRequests: 590, grafts: 29, graftIneligible: 0, graftedNodes: 590, prepaints: 219, prepaintHits: 29),
    AfterGraftFrame(arm: .environment, requests: 760, skippedRequests: 38, grafts: 19, graftIneligible: 0, graftedNodes: 38, prepaints: 829, prepaintHits: 19),
    AfterGraftFrame(arm: .panels, requests: 167, skippedRequests: 631, grafts: 30, graftIneligible: 1, graftedNodes: 641, prepaints: 176, prepaintHits: 30),
]

@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
func theBracketNodeDragIsCountedAfterTheGraft(arm: BracketArm) throws {
    let expected = try #require(afterGraftFrames.first { $0.arm == arm })
    let f = try bracketDragFrames(arm: arm, steps: 20, retained: true, prepaint: true, graft: true).frames[10]
    #expect(f.builds == 1)
    #expect(f.elementRequests == expected.requests)
    #expect(f.retainedSkippedRequests == expected.skippedRequests)
    #expect(f.retainedGrafts == expected.grafts)
    #expect(f.retainedGraftIneligible == expected.graftIneligible)
    #expect(f.retainedGraftedNodes == expected.graftedNodes)
    #expect(f.elementPrepaints == expected.prepaints)
    #expect(f.retainedPrepaintHits == expected.prepaintHits)
    #expect(f.retainedRedos == 0 && f.retainedBackoffFrames == 0)
    // What the graft must not move: the scene and the paints are lane 1's.
    #expect(f.rects == 182 && f.glyphs == 550 && f.images == 6)
}

// MARK: The fixtures

/// A nested occurrence with `@State` of its own: a write below an outer occurrence must rebuild it.
struct RGInner: Component, @MainActor Equatable {
    let n: Int
    let log: HarnessLog
    @State var taps = 0
    var content: some ElementGroup {
        HStack(spacing: 2) {
            Text("inner \(n) taps \(taps)").frame(width: Pixels(80), height: Pixels(12))
            Button("tap \(n)") { taps += 1; log.add("tap \(n)") }.frame(width: Pixels(40), height: Pixels(14))
        }
    }
    static func == (l: RGInner, r: RGInner) -> Bool { l.n == r.n && l.log === r.log }
}

/// The occurrence under test: text, two nested occurrences, a `ForEach`, a named element, a conditional and a button
/// with a context menu: every channel a graft's journal must carry (marks, produced slots, names, loop extents, memo touches).
struct RGCard: Component, @MainActor Equatable {
    let title: String
    let shade: Int
    let log: HarnessLog
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text(title).frame(width: Pixels(90), height: Pixels(14))
            RGInner(n: 1, log: log).equatable()
            RGInner(n: 2, log: log).equatable()
            ForEach(Array(0..<3), id: \.self) { i in
                Box().frame(width: Pixels(Float(10 + i * shade * 6)), height: Pixels(6)).background(.accent)
            }
            Text("named").id("named-\(shade)").frame(width: Pixels(60), height: Pixels(12))
            if shade > 0 { Box().frame(width: Pixels(20), height: Pixels(4)).background(.accent) }
            Button("go \(title)") { log.add("go \(title)") }.frame(width: Pixels(50), height: Pixels(16))
                .contextMenu { Button("menu \(title)") { log.add("menu \(title)") } }
        }
        .padding(Edges(all: Pixels(4)))
        .background(Color.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: Pixels(6)))
    }
    static func == (l: RGCard, r: RGCard) -> Bool { l.title == r.title && l.shade == r.shade && l.log === r.log }
}

/// The script's root: a conditional and a reorderable `ForEach` before the card (so each step also moves the card), the
/// card, and a lifecycle scope after it. `model.n` drives the first two, `model.tint` the card's title.
struct RGRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        let model = side.model, log = side.log
        VStack(spacing: 4) {
            if model.n % 3 == 1 { Text("flag").frame(width: Pixels(40), height: Pixels(10)) }
            ForEach(model.n % 2 == 0 ? [0, 1, 2] : [2, 0, 1], id: \.self) { i in
                Text("item \(i)").frame(width: Pixels(50), height: Pixels(10))
            }
            RGCard(title: "A\(model.tint)", shade: 1, log: log).equatable()
            Text("tail").frame(width: Pixels(30), height: Pixels(10)).onAppear { log.add("tail appear") }
        }
    }
}

/// A card only: stable, in a fixed place, so every frame after the first few grafts it.
struct RGStable: Component {
    let side: RPSide
    var content: some ElementGroup {
        VStack(spacing: 4) {
            Text("count \(side.model.n)").frame(width: Pixels(60), height: Pixels(12))
            RGCard(title: "S", shade: 1, log: side.log).equatable()
        }
    }
}

@MainActor private func stateAgrees(_ pair: RPPair<some Element>, _ step: String) {
    #expect(pair.on.window.testingStateEntries == pair.off.window.testingStateEntries, "state table after \(step)")
    #expect(pair.on.window.testingContentMemos.entryCount == pair.off.window.testingContentMemos.entryCount, "memo entries after \(step)")
}

// MARK: 15 — the sweeps stay exact

/// 15 — a script around a grafted card (a conditional appearing and disappearing above it, a `ForEach` reorder, a nested
/// occurrence, a lifecycle scope, a title change): after every step the grafting window equals the retention-off window in
/// scene, accessibility tree, hitboxes, Tab order, the log, the state table's entries and the memo store's entry count, and it
/// grafted at least once (a differential that grafts nothing proves nothing). **Red before:** `retainedGrafts` reads 0 in
/// every frame. **Mutations:** the journal not applied again (a nested memo entry is swept: the entry count differs), the
/// produced-slot or the named-position events skipped (a reset fires or does not: the state entries differ), the nested memo
/// touches skipped (the entry count).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aGraftedFrameKeepsTheStateTableSweepsExact() async throws {
    let pair = try RPPair(size: sz(260, 260), warm: 5) { side in VStack(spacing: 0) { RGRoot(side: side) } }
    try pair.compare("warm")
    stateAgrees(pair, "warm")
    pair.redraw()
    #expect(pair.frames.last?.retainedGrafts ?? 0 >= 1, "the card grafts on a steady frame: \(String(describing: pair.frames.last))")
    var grafts = 0
    for step in 0..<8 {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw()
        grafts += pair.frames.last?.retainedGrafts ?? 0
        try pair.compare("step \(step)")
        stateAgrees(pair, "step \(step)")
        // Long enough to leave the window-wide backoff a redo starts (nine builds) and graft again.
        for settled in 0..<11 {
            pair.redraw()
            grafts += pair.frames.last?.retainedGrafts ?? 0
            if settled % 3 == 0 || settled == 10 {
                try pair.compare("step \(step) settled \(settled)")
                stateAgrees(pair, "step \(step) settled \(settled)")
            }
        }
    }
    #expect(grafts > 0, "the script grafted nothing")
    pair.onSide.model.tint += 1; pair.offSide.model.tint += 1
    await rsSettle()
    pair.redraw(); pair.redraw()
    try pair.compare("a new title")
    stateAgrees(pair, "a new title")
    #expect(pair.onSide.log.entries == pair.offSide.log.entries && pair.onSide.log.entries.filter { $0 == "tail appear" }.count == 1)
}

// MARK: 19 — a changed value builds, a changed state below rebuilds

/// 19 — a card whose value changed builds that frame (one content evaluation, no graft of it) and grafts again on the next: its
/// build left a graft record beside the paint record. A write to the `@State` of a nested occurrence moves a version the card's
/// record holds, so the card builds again (a stale count would draw the old text); the sibling occurrence that did not change
/// still grafts inside that rebuild. **Red before:** the grafts read 0 throughout. **Mutation:** the version compare skipped in
/// `graftRecord(for:)` (the stale text: the scene differs from the retention-off window's).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aGraftWithAChangedValueBuildsAndAGraftAfterItGrafts() async throws {
    let pair = try RPPair(size: sz(200, 220), warm: 5) { side in VStack(spacing: 0) { RGRoot(side: side) } }
    pair.redraw(); pair.redraw()
    try #require((pair.frames.last?.retainedGrafts ?? 0) >= 1, "grafting before the change: \(String(describing: pair.frames.last))")
    pair.onSide.model.tint += 1; pair.offSide.model.tint += 1
    await rsSettle()
    pair.redraw()
    let changed = try #require(pair.frames.last)
    #expect(changed.contentEvaluations == 1, "the card's content ran once: \(changed.contentEvaluations)")
    try pair.compare("the changed value")
    pair.redraw()
    #expect((pair.frames.last?.retainedGrafts ?? 0) >= 1, "it grafts again after its build: \(String(describing: pair.frames.last))")
    try pair.compare("grafting again")
}

@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aStateWriteBelowAGraftedOccurrenceRebuildsIt() async throws {
    let pair = try RPPair(size: sz(200, 220), warm: 5) { side in VStack(spacing: 0) { RGStable(side: side) } }
    pair.redraw(); pair.redraw()
    try #require((pair.frames.last?.retainedGrafts ?? 0) >= 1, "grafting before the write: \(String(describing: pair.frames.last))")
    for w in [pair.on, pair.off] { try w.click(w.element(label: "tap 1")) }
    pair.redraw()
    let after = try #require(pair.frames.last)
    #expect(after.retainedGrafts == 1, "only the untouched sibling nested occurrence grafts inside the rebuild: \(after.retainedGrafts)")
    try pair.compare("after the tap")
    stateAgrees(pair, "after the tap")
    #expect(pair.onSide.log.entries == ["tap 1"] && pair.offSide.log.entries == ["tap 1"])
    _ = try pair.on.element(label: "inner 1 taps 1")   // the new count is drawn
    pair.redraw(); pair.redraw()
    #expect((pair.frames.last?.retainedGrafts ?? 0) >= 1, "the card grafts again once it has rebuilt")
    try pair.compare("grafting again")
}

/// A nested occurrence whose getter reads an `@Observable` the outer never reads: its memo entry goes stale when the model
/// changes, and an outer graft must not stand over it.
private struct RGObsInner: Component, @MainActor Equatable {
    let model: RSModel
    var content: some ElementGroup { Text("observed \(model.n)").frame(width: Pixels(90), height: Pixels(12)) }
    static func == (l: RGObsInner, r: RGObsInner) -> Bool { l.model === r.model }
}

private struct RGObsOuter: Component, @MainActor Equatable {
    let model: RSModel
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("outer").frame(width: Pixels(60), height: Pixels(12))
            RGObsInner(model: model).equatable()
        }
    }
    static func == (l: RGObsOuter, r: RGObsOuter) -> Bool { l.model === r.model }
}

/// 19c — an `@Observable` read by a **nested** occurrence's getter that changes rebuilds the grafted outer: the outer's value is equal and
/// its own reads did not change, but the nested memo entry is stale, so `graftDependenciesHold` refuses and the outer builds (one
/// content evaluation: the nested getter). **Red before:** the grafts read 0 throughout. **Mutation:** `graftDependenciesHold`
/// answering true (the outer grafts over the stale entry and draws the old text: the scene differs from the retention-off window's).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aNestedOccurrencesObservedChangeRebuildsTheGraftedOuter() async throws {
    let pair = try RPPair(size: sz(160, 80), warm: 5) { side in VStack(spacing: 0) { RGObsOuter(model: side.model).equatable() } }
    pair.redraw(); pair.redraw()
    try #require((pair.frames.last?.retainedGrafts ?? 0) >= 1, "grafting before the change: \(String(describing: pair.frames.last))")
    pair.onSide.model.n += 1; pair.offSide.model.n += 1
    await rsSettle()
    pair.redraw()
    let f = try #require(pair.frames.last)
    #expect(f.retainedGrafts == 0, "the outer builds over a stale nested entry: \(f.retainedGrafts)")
    #expect(f.contentEvaluations == 1, "the nested getter ran once: \(f.contentEvaluations)")
    try pair.compare("the observed change")
    _ = try pair.on.element(label: "observed 1")
    for _ in 0..<2 { pair.redraw() }
    #expect((pair.frames.last?.retainedGrafts ?? 0) >= 1, "it grafts again once rebuilt")
    try pair.compare("grafting again")
}

// MARK: 18 — what a graft refuses, by name

enum RGKind: String, CaseIterable {
    case control, hidden, lifecycle, timeline, scroll, popover
    /// The channel the refusal names: `nil` for the control (it grafts).
    var channel: String? {
        switch self {
        case .control: nil
        case .hidden: "hiddenNodes"
        case .lifecycle: "lifecycle"
        case .timeline: "timeVarying"
        case .scroll: "stateWrite"
        case .popover: "presentation"
        }
    }
}

private struct RGKindCard: Component, @MainActor Equatable {
    let kind: RGKind
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("kind").frame(width: Pixels(60), height: Pixels(12))
            switch kind {
            case .control: Box().frame(width: Pixels(20), height: Pixels(6)).background(.accent)
            case .hidden: Box().frame(width: Pixels(20), height: Pixels(6)).hidden()
            case .lifecycle: Box().frame(width: Pixels(20), height: Pixels(6)).onAppear {}
            case .timeline: TimelineView(.animation) { _ in Box().frame(width: Pixels(20), height: Pixels(6)) }
            case .scroll: ScrollView(.vertical) { Text("scrolled").frame(width: Pixels(40), height: Pixels(40)) }
                    .frame(width: Pixels(60), height: Pixels(20))
            case .popover: Box().frame(width: Pixels(20), height: Pixels(6)).popover(isPresented: .constant(true)) { Text("pop") }
            }
        }
    }
    static func == (l: RGKindCard, r: RGKindCard) -> Bool { l.kind == r.kind }
}

/// 18 — an occurrence whose build wrote a channel the journal does not replay builds every frame and is counted by name; the control
/// grafts. Each frame equals the retention-off window's. **Red before:** `testingGraftRefusals` is empty (nothing is
/// recorded or refused). **Mutation:** the channel's audit line removed from `BuildAudit.movedChannel` (the occurrence grafts and
/// the arm's differential or its refusal count reddens), one run per channel.
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: RGKind.allCases) @MainActor
func aGraftIneligibleBuildIsCountedByName(kind: RGKind) throws {
    let pair = try RPPair(size: sz(160, 120), warm: 5) { _ in VStack(spacing: 0) { RGKindCard(kind: kind).equatable() } }
    try pair.compare("warm")
    pair.redraw()
    let f = try #require(pair.frames.last)
    if let channel = kind.channel {
        #expect(f.retainedGrafts == 0, "\(kind): no graft")
        #expect(f.retainedGraftIneligible >= 1, "\(kind): counted")
        #expect(pair.on.window.testingGraftRefusals.contains { $0.hasPrefix(channel) }, "\(kind) names \(channel): \(pair.on.window.testingGraftRefusals)")
    } else {
        #expect(f.retainedGrafts == 1 && f.retainedGraftIneligible == 0, "the control grafts: \(f.retainedGrafts)/\(f.retainedGraftIneligible)")
    }
    try pair.compare("the steady frame")
}

// MARK: 20 — a redo after a graft restores everything

/// A card that moves when a sibling above it appears or grows: its rects change under a graft that cannot know.
private struct RGMoving: Component {
    let side: RPSide
    var content: some ElementGroup {
        let model = side.model
        VStack(spacing: 4) {
            Text("pad").frame(width: Pixels(40), height: Pixels(Float(10 + (model.n % 2) * 12)))
            ZStack { RGCard(title: "M", shade: 1, log: side.log).equatable() }.opacity(model.tint % 2 == 1 ? 0.5 : 1)
        }
    }
}

/// 20 — a graft that cannot paint (a paint-only ambient above it changed) or cannot prepaint (the occurrence moved: its rects are not
/// the ledger's) asks the window to build the frame again with every graft and replay off: the redo's frame equals the
/// retention-off frame in scene, tree, log and **state table**, counts one redo, grafts nothing in the redo, and the grafts resume
/// after the backoff. **Red before:** `retainedRedos` reads 0 and the frame is wrong (a grafted occurrence cannot be drawn).
/// **Mutations:** the redo's `graftAllowed` not suspended (a grafted redo asks for a redo: the assertion or the scene), the
/// abandoned frame adopted (hitboxes), the checkpoint's animation entries not restored.
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: ["opacity above", "moved by a sibling"]) @MainActor
func aRedoAfterAGraftMismatchRestoresEverything(arm: String) async throws {
    let pair = try RPPair(size: sz(220, 260), warm: 5) { side in VStack(spacing: 0) { RGMoving(side: side) } }
    try pair.compare("warm")
    pair.redraw()
    try #require((pair.frames.last?.retainedGrafts ?? 0) >= 1, "grafting before the change: \(String(describing: pair.frames.last))")
    for side in [pair.onSide, pair.offSide] { if arm == "opacity above" { side.model.tint += 1 } else { side.model.n += 1 } }
    await rsSettle()
    pair.redraw()
    let f = try #require(pair.frames.last)
    #expect(f.retainedRedos == 1, "\(arm): the frame was redone once: \(f.retainedRedos)")
    #expect(f.retainedGrafts == 0, "\(arm): the redo grafts nothing: \(f.retainedGrafts)")
    try pair.compare(arm)
    stateAgrees(pair, arm)
    for index in 1...8 {
        pair.redraw()
        #expect(pair.frames.last?.retainedGrafts == 0, "\(arm): backoff build \(index)")
        try pair.compare("\(arm), backoff build \(index)")
        stateAgrees(pair, "\(arm), backoff build \(index)")
    }
    pair.redraw(); pair.redraw()
    #expect((pair.frames.last?.retainedGrafts ?? 0) >= 1, "\(arm): the grafts resume after the backoff: \(String(describing: pair.frames.last))")
    try pair.compare("\(arm), after the backoff")
    #expect(pair.onSide.log.entries == pair.offSide.log.entries)
}

// MARK: 20b — a graft the prepaint cannot replay

/// 20b — a pan of three equal occurrences under a live accessibility client: the prepaint translation is refused for a ledger that holds
/// accessibility records (`RK-S`), so a grafted occurrence has no element layout to fall back on and the frame is redone (lane 1's
/// tree, which builds every frame, counts a refusal and prepaints fresh). Every step equals the retention-off frame, in scene,
/// tree, hitboxes and state table, and the redos are counted. **Red before:** `retainedRedos` reads 0 (the graft off).
/// **Mutation:** the grafted occurrence's `.run` arm returning the old prepaint state (a trap by name: no payload).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aGraftedOccurrenceUnderARefusedTranslationRedoesTheFrame() async throws {
    let pair = try RPPair(size: sz(320, 150), scale: 2, warm: 4, accessibility: true) { side in
        VStack(spacing: 0) { RPPanRoot(side: side) }
    }
    try pair.compare("warm")
    var redos = 0
    for (index, pan) in rpPanScript.enumerated() {
        pair.onSide.inputs.offset = pan; pair.offSide.inputs.offset = pan
        await rsSettle()
        pair.redraw()
        redos += pair.frames.last?.retainedRedos ?? 0
        try pair.compare("pan step \(index) (\(pan))")
        stateAgrees(pair, "pan step \(index)")
    }
    #expect(redos >= 1, "the refused translation redid a grafted frame: \(redos)")
}

// MARK: Verify mode over the graft (`RK-N`)

/// The channels a damaged graft differs in and the words the trap must carry for each.
let rkGraftVerifyChannels: [(channel: String, word: String)] = [
    ("leafKeys", "a replayed prepaint differs from a fresh one: layout tree"),
    ("marks", "a replayed prepaint differs from a fresh one: build calls on the tables: marks"),
    ("produced", "a replayed prepaint differs from a fresh one: build calls on the tables: produced slots"),
    ("named", "a replayed prepaint differs from a fresh one: build calls on the tables: produced names"),
    ("loops", "a replayed prepaint differs from a fresh one: build calls on the tables: loop extents"),
    ("memoTouches", "a replayed prepaint differs from a fresh one: build calls on the tables: memo entries kept"),
]

/// 23 — a verified graft that differs from a build traps, naming the channel (`RK-N`): the child process sets the variable, warms a
/// window until the card's graft record exists, damages that record in one channel and draws the next frame. Mutation: the
/// comparison of the channel removed (`BuildChannels.difference`, or `RetainedVerifySnapshot.difference` for the tree) — the
/// child exits normally and the exit test reddens for that arm.
@Test(.serialized, arguments: rkGraftVerifyChannels) @MainActor
func aVerifiedGraftThatDiffersTraps(arm: (channel: String, word: String)) async {
    setenv("RK_VERIFY_GRAFT_CHANNEL", arm.channel, 1)
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setenv("METALUI_VERIFY_RETAINED", "1", 1)
        await MainActor.run {
            let log = HarnessLog()
            guard let window = try? TestWindow(size: sz(200, 260), textSystem: harnessTextSystem, content: {
                VStack(spacing: 0) { RGCard(title: "V", shade: 1, log: log).equatable() }
            }) else { return }
            _ = try? window.accessibilityTree
            for _ in 0..<6 { window.window.setNeedsRedraw(); window.tick() }
            let damaged = window.window.testingCorruptGraftRecords(
                ProcessInfo.processInfo.environment["RK_VERIFY_GRAFT_CHANNEL"] ?? "marks")
            guard damaged > 0 else { print("no graft record to damage"); return }
            window.window.setNeedsRedraw(); window.tick()
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains(arm.word), "the trap names \(arm.word): \(stderr)")
}

/// 23b — the control: an undamaged graft under verify mode draws normally.
@Test @MainActor func anUndamagedVerifiedGraftDrawsNormally() async {
    await #expect(processExitsWith: .success) {
        setenv("METALUI_VERIFY_RETAINED", "1", 1)
        await MainActor.run {
            let log = HarnessLog()
            guard let window = try? TestWindow(size: sz(200, 260), textSystem: harnessTextSystem, content: {
                VStack(spacing: 0) { RGCard(title: "V", shade: 1, log: log).equatable() }
            }) else { exit(2) }
            _ = try? window.accessibilityTree
            for _ in 0..<8 { window.window.setNeedsRedraw(); window.tick() }
        }
    }
}
