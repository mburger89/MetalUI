import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
#if canImport(Darwin)
import MetalUITestSupport
#endif
import Testing

// Record 443 (`RK-AS`): a graft stands under a steady focus. `graftRecord` asks that the focus under the occurrence now is the one its paint record and its prepaint
// ledger were made with (`nil` included), so Alloy's focused composer grafts while the column above it is tainted every step by the scroller's glide or fade. The
// backoff of `RK-AQ` applies to standing taints only. Every graft refusal is named. The fixture is `FocusGraftFixture.swift`; counts are work, never time.

private let verifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read; the differential runs under it"

private func sum(_ frames: [FrameWork], _ key: KeyPath<FrameWork, Int>) -> Int { frames.reduce(0) { $0 + $1[keyPath: key] } }

/// What a step costs: the counters a focused window must share with an unfocused one.
private struct StepWork: Equatable, CustomStringConvertible {
    var requests: Int, skipped: Int, grafts: Int, prepaints: Int, paints: Int, hits: Int, misses: Int, redos: Int
    init(_ frames: [FrameWork]) {
        requests = sum(frames, \.elementRequests); skipped = sum(frames, \.retainedSkippedRequests); grafts = sum(frames, \.retainedGrafts)
        prepaints = sum(frames, \.elementPrepaints); paints = sum(frames, \.elementPaints)
        hits = sum(frames, \.retainedHits); misses = sum(frames, \.retainedMisses); redos = sum(frames, \.retainedRedos)
    }
    var description: String { "requests \(requests) skipped \(skipped) grafts \(grafts) prepaints \(prepaints) paints \(paints) hits \(hits) misses \(misses) redos \(redos)" }
}

/// A pair for the fixture with the glide started when asked.
@MainActor private func chat(focused: Bool, glide: Bool, spinner: Bool = false) throws -> FGPair<some Element> {
    let fg = try fgPair(focused: focused, spinner: spinner)
    if glide { fgStartGlide(fg) }
    return fg
}

// MARK: 1 - the composer grafts

/// **1** Under a scroll (a wheel, whose indicator fade taints the column every step, and a glide) the focused composer grafts on every step: the column above it
/// builds (tainted: `activeAnimation` or `stateWrite`), the composer does not. No redo, no focus refusal, and the window equals the retention-off one. On master
/// the composer was refused under focus (16 grafts a step against the unfocused 17, 13 requests against 5). **Mutation:** the graft's focus rule back to `nil` only (M1).
@Test(.enabled(if: !rsVerifying, verifyNote), arguments: [false, true]) @MainActor func aFocusedComposerGraftsWhileTheColumnAboveItIsTainted(glide: Bool) throws {
    let fg = try chat(focused: true, glide: glide)
    #expect(fg.pair.on.window.focusedElement != nil, "the click focused the field")
    for step in 0..<20 {
        var lines: [String] = []
        RetainedTrace.sink = { lines.append($0) }
        fgStep(fg, step, glide: glide)
        RetainedTrace.sink = nil
        let frames = fg.pair.on.frameWork
        // Held plain by a backoff (a transient taint under the focus, as on master) or recorded and refused: either way the scroller's taint is the reason.
        let tainted = lines.contains { ($0.contains("ineligible") || $0.contains("focusBackoff")) && ($0.contains("because activeAnimation") || $0.contains("because stateWrite")) }
        #expect(tainted, "step \(step): the column is tainted by the scroller")
        #expect(sum(frames, \.retainedGrafts) >= 17, "step \(step): grafts \(sum(frames, \.retainedGrafts))")
        #expect(sum(frames, \.retainedRedos) == 0, "step \(step): redos")
        #expect(!fg.pair.on.window.testingGraftRefusals.contains("focusMoved"), "step \(step): \(fg.pair.on.window.testingGraftRefusals)")
        try fg.pair.compare("step \(step)")
    }
}

// MARK: 2 - the cost

/// **2** Per step, a focused chat does the work of an unfocused one: element requests, skipped requests, grafts, prepaints, paints, hits, misses and redos are equal.
/// Master's focused wheel step: 13 requests, 32 skipped, 16 grafts against 5, 40 and 17. **Mutation:** M1, M4.
@Test(.enabled(if: !rsVerifying, verifyNote), arguments: [false, true]) @MainActor func aFocusedChatCostsWhatAnUnfocusedOneCostsWithGraftsOn(glide: Bool) throws {
    let focused = try chat(focused: true, glide: glide), plain = try chat(focused: false, glide: glide)
    for step in 0..<12 {
        fgStep(focused, step, glide: glide); fgStep(plain, step, glide: glide)
        let a = StepWork(focused.pair.on.frameWork), b = StepWork(plain.pair.on.frameWork)
        #expect(a == b, "step \(step): focused \(a) against unfocused \(b)")
    }
    try focused.pair.compare("focused")
}

// MARK: 3 - the backoff

/// **3** A backoff made for a transient taint (a fade, a glide, a state write) is lifted by the first quiet frame (`RK-AS`): during a scroll the tainted chain may be held
/// plain, as on master (the unfocused window records instead, so requests may differ by nothing: the composer grafts either way); after it the first quiet frame leaves
/// no backoff (`testingFocusBackoffCount == 0`), the focused window lags the unfocused one by two frames (frame 0 builds, frame 1 captures from the record frame 0 made, frame 2 grafts: measured 5, 5, 0 requests against 0, 0, 0), and then every frame equals it. **Mutation:** M5 (the lift removed).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func theFocusedChainRecordsTheFrameAfterTheFadeEnds() throws {
    let focused = try chat(focused: true, glide: false), plain = try chat(focused: false, glide: false)
    for step in 0..<6 { fgStep(focused, step, glide: false); fgStep(plain, step, glide: false) }
    for w in [focused.pair.on, plain.pair.on, focused.pair.off, plain.pair.off] { w.advance(by: 0.5); w.advance(by: 2) }
    var table: [String] = []
    for frame in 0..<7 {
        focused.pair.on.resetFrameWork(); plain.pair.on.resetFrameWork()
        focused.pair.redraw(); plain.pair.redraw()
        let a = StepWork(focused.pair.on.frameWork), b = StepWork(plain.pair.on.frameWork)
        table.append("frame \(frame): focused \(a) | unfocused \(b) | backoffs \(focused.pair.on.window.testingFocusBackoffCount)")
        if frame < 2 { #expect(a.requests <= 5 && a.redos == 0, "the lag is two frames (the first quiet frame lifts the backoff and builds, the second captures from the record it made): focused \(a)") }
        else { #expect(a == b, "frame \(frame): focused \(a) against unfocused \(b)") }
        #expect(focused.pair.on.window.testingFocusBackoffCount == 0, "no transient backoff survives the first quiet frame (frame \(frame))")
    }
    #expect(table.count == 7, "\(table.joined(separator: "\n"))")
    try focused.pair.compare("settled")
}

// MARK: 4 - typing

/// **4** A key into a grafted composer: the key frame refuses by name and redoes nothing, the text is typed on both windows, and the graft comes back after
/// two quiet frames (the first captures from the record the frame before hit, the second grafts). **Mutation:** M3 (a capture on the key frame).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aTypedKeyIntoAGraftedComposerMissesOnceAndGraftsAgain() throws {
    let fg = try chat(focused: true, glide: false)
    for step in 0..<3 { fgStep(fg, step, glide: false) }
    let pair = fg.pair
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.typeText("a") }
    let key = pair.on.frameWork
    #expect(pair.onSide.inputs.text == "a" && pair.offSide.inputs.text == "a", "typed: \(pair.onSide.inputs.text)")
    #expect(sum(key, \.retainedRedos) == 0, "no redo on the key frame")
    #expect(sum(key, \.retainedGraftCaptures) == 0, "the key frame's records are new: no capture, \(sum(key, \.retainedGraftCaptures))")
    try pair.compare("typed")
    var captures: [Int] = [], grafts: [Int] = []
    for _ in 0..<3 {
        pair.on.resetFrameWork(); pair.redraw()
        captures.append(sum(pair.on.frameWork, \.retainedGraftCaptures)); grafts.append(sum(pair.on.frameWork, \.retainedGrafts))
    }
    #expect(captures.dropFirst().allSatisfy { $0 == 0 }, "captures after the first quiet frame: \(captures)")
    #expect(grafts.last ?? 0 > grafts.first ?? 0, "the composer grafts again: \(grafts)")
    try pair.compare("quiet")
}

// MARK: 5, 6 - focus moving

/// **5** Focus moving into and out of a grafted composer: each move's frame redoes nothing and equals the retention-off window. The composer holds a `@FocusState`,
/// whose version a move bumps (the refusal is then `versions`, which comes first); `focusMoved` is reached by a plain field (5b). **Mutation:** M9.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func focusMovingIntoOrOutOfAGraftedComposerRedoesNothing() throws {
    let fg = try chat(focused: false, glide: false)
    let pair = fg.pair
    for step in 0..<3 { fgStep(fg, step, glide: false) }
    for w in [pair.on, pair.off] { w.click(at: pt(60, 580)); w.exitPointer() }
    pair.redraw()
    #expect(pair.on.window.focusedElement != nil)
    #expect(sum(pair.frames, \.retainedRedos) == 0, "no redo into the focus")
    try pair.compare("focused in")
    for _ in 0..<4 { pair.redraw() }
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.window.focus(nil) }
    for _ in 0..<2 { pair.redraw() }
    #expect(pair.on.window.focusedElement == nil)
    #expect(sum(pair.frames, \.retainedRedos) == 0, "no redo out of the focus")
    try pair.compare("focused out")
}

/// **5b** A box with no state grafts unfocused; `focus(nil)` out of it names `focusMoved` (the frame Tab moves the focus in finds no graft record yet) (a graft record made under another focus is not
/// stood on), redo nothing, and the frames equal the retention-off window's. **Mutation:** M8 (the name dropped), M1.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func focusMovingIntoOrOutOfAGraftedFieldRefusesByName() throws {
    let pair = try fgPlainPair()
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    var names: [[String]] = []
    for w in [pair.on, pair.off] { w.typeKey(.tab) }
    pair.redraw(); names.append(pair.on.window.testingGraftRefusals)
    #expect(pair.on.window.focusedElement != nil)
    try pair.compare("tabbed in")
    for _ in 0..<4 { pair.redraw() }
    for w in [pair.on, pair.off] { w.window.focus(nil) }
    pair.redraw(); names.append(pair.on.window.testingGraftRefusals)
    try pair.compare("focused out")
    #expect(names.last?.contains("focusMoved") == true, "named: \(names)")
    #expect(lines.contains { $0.contains("retained graft refused") && $0.contains("because focusMoved") }, "traced")
    #expect(sum(pair.frames, \.retainedRedos) == 0, "no redo")
}

/// **6** A `@FocusState` write after grafted frames moves the focus: the composer's Done button sets it false, the focus is nil on both windows and the frames equal.
/// **Mutation:** M9.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFocusStateWriteAfterAGraftedFrameMovesTheFocus() throws {
    let fg = try chat(focused: true, glide: false)
    let pair = fg.pair
    for step in 0..<4 { fgStep(fg, step, glide: false) }
    for w in [pair.on, pair.off] {
        // The Done button is the rightmost hitbox of the composer's row.
        let done = try #require(w.window.lastHitboxes.filter { $0.bounds.origin.y.value > 540 }.max { $0.bounds.origin.x.value < $1.bounds.origin.x.value })
        w.click(at: pt(done.bounds.origin.x.value + done.bounds.size.width.value / 2, done.bounds.origin.y.value + done.bounds.size.height.value / 2))
        w.exitPointer()
    }
    for _ in 0..<3 { pair.redraw() }
    #expect(pair.on.window.focusedElement == nil && pair.off.window.focusedElement == nil, "the write blurred the field")
    #expect(sum(pair.frames, \.retainedRedos) == 0)
    try pair.compare("done")
}

// MARK: 7, 8 - the input method and the focus slot

/// **7** The input method's caret rect after each grafted step is the retention-off window's.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aGraftedFocusedFieldKeepsTheInputMethodsCaretRect() throws {
    let fg = try chat(focused: true, glide: false)
    for step in 0..<8 {
        fgStep(fg, step, glide: false)
        #expect(fg.pair.on.platformWindow.textInputAreas.last == fg.pair.off.platformWindow.textInputAreas.last, "step \(step)")
    }
    #expect(fg.pair.on.platformWindow.textInputAreas.last != nil, "the field reported an area")
}

/// **8** `FocusKeyedReplayTests` 7 with grafts on: the focused field's retention slot stays live across sweeps while its composer grafts.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aGraftedFocusedFieldKeepsItsFocusSlotLive() throws {
    let fg = try chat(focused: true, glide: false)
    let pair = fg.pair
    let focus = try #require(pair.on.window.focusedElement)
    let slot = Frame.focusRetentionSlot(for: focus)
    for w in [pair.on, pair.off] {
        for index in 0..<(StateTable.sweepThreshold + 44) {
            w.window.stateTable.withState(.child(of: focus, at: index, name: ElementID("$fgseed\(index)")), initial: 0) { _ in }
        }
    }
    pair.frames = []
    for _ in 0..<(Int(StateTable.staleAfterGenerations) * 2 + 2) { pair.redraw() }
    #expect(sum(pair.frames, \.retainedGrafts) > 0, "the composer grafted")
    for (name, w) in [("on", pair.on), ("off", pair.off)] {
        #expect(w.window.stateTable.peek(slot, as: Bool.self) != nil, "\(name): the focus slot is kept")
        #expect(w.window.focusedElement == focus, "\(name): the focus is kept")
    }
}

// MARK: 9 - the blink

private struct FGBlinkLeaf: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false).codeCaretBlink(.on)
    }
    static func == (l: FGBlinkLeaf, r: FGBlinkLeaf) -> Bool { l.buffer === r.buffer }
}
private struct FGBlinkMid: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    var content: some ElementGroup { FGBlinkLeaf(buffer: buffer).equatable() }
    static func == (l: FGBlinkMid, r: FGBlinkMid) -> Bool { l.buffer === r.buffer }
}
private struct FGBlinkOuter: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    var content: some ElementGroup { FGBlinkMid(buffer: buffer).equatable() }
    static func == (l: FGBlinkOuter, r: FGBlinkOuter) -> Bool { l.buffer === r.buffer }
}

/// **9** A focused, blinking `CodeView` under three occurrences with the graft on: its caret taints every paint record (`taintRetention`, standing), so the
/// backoff holds the chain plain, no record is left to graft from, nothing is grafted or redone, and the ledgers stay at most 9. An active backoff implies the
/// entry holds no record (`RK-AS`), which is why a graft never meets one. **Mutation:** M6, M7.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aBlinkingFocusedCodeViewIsNeverGrafted() throws {
    let buffer = CodeBuffer("hello\nworld\n")
    let w = try harnessWindow(size: sz(400, 200)) { VStack(spacing: 0) { FGBlinkOuter(buffer: buffer).equatable() } }
    w.window.testingRetainedGraft = true
    w.click(at: pt(60, 6)); w.exitPointer()
    buffer.selections = [CodeSelection(caret: 0)]
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    let made = PrepaintLedger.madeCount
    w.resetFrameWork()
    for _ in 0..<40 { w.advance(by: 0.5) }
    #expect(sum(w.frameWork, \.retainedGrafts) == 0, "never grafted")
    #expect(sum(w.frameWork, \.retainedRedos) == 0)
    #expect(PrepaintLedger.madeCount - made <= 9, "three attempts of three: \(PrepaintLedger.madeCount - made)")
    #expect(w.frameWork.reduce(0) { $0 + ($1.retainedIneligibleReasons["codeCaretBlink"] ?? 0) } == 120, "the ineligibles master counted")
}

// MARK: 10 - a perpetual animation

/// **10** A `ProgressView` beside the focused composer raises a transient taint on every frame: the backoff holds the chain plain, as on master, and the window equals the
/// retention-off one; requests equal the unfocused chat's, and on Darwin (10b) allocations are no more than master's, in a child process with a fixed hash seed (below).
/// **Mutation:** M6 (the backoff removed: focused 28,309 against 19,0xx).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aPerpetualAnimationBesideAFocusedFieldCostsWhatItCostsOnMaster() throws {
    let focused = try chat(focused: true, glide: false, spinner: true), plain = try chat(focused: false, glide: false, spinner: true)
    for step in 0..<6 {
        fgStep(focused, step, glide: false); fgStep(plain, step, glide: false)
        let a = StepWork(focused.pair.on.frameWork), b = StepWork(plain.pair.on.frameWork)
        #expect(a.requests == b.requests && a.redos == b.redos, "step \(step): focused \(a) against unfocused \(b)")
    }
    try focused.pair.compare("spinner")
}

#if canImport(Darwin)
/// What master measures in `fgChildMeasures`' form (a child process with `SWIFT_DETERMINISTIC_HASHING=1`; thirty runs: the focused count 19,021 every time, the largest of the differences, which still move by
/// one: spinner 10,085, wheel 9,791, glide 10,011, stream 1,856): see record 443. Relative or fixed-seed forms, so a different machine's allocator moves the
/// retaining and retention-off windows together.
let fgMastersMeasures: FGMeasures = {
    var m = FGMeasures()
    m.spinnerFocused = 19_021; m.spinnerDelta = 10_085; m.wheel = 9_791; m.glide = 10_011; m.stream = 1_856
    return m
}()

/// **10b** and **12b** The allocations of the unfocused chats' steps, as the difference between the retaining window and the retention-off one (least of eight steps, least of
/// three fresh fixtures), and the focused spinner chain's, no more than master's. The refusal names, the taint classification, the ping-pong of the names and the backoff lift
/// add none. **Mutation:** the trace line's autoclosure built eagerly (M11b), the backoff removed (M6: focused spinner 28,309).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func theChatsStepsAllocateNoMoreThanMastersInAFixedSeedChild() async {
    guard let m = await fgChildMeasures() else { Issue.record("the child did not see SWIFT_DETERMINISTIC_HASHING"); return }
    let master = fgMastersMeasures
    #expect(m.spinnerFocused <= master.spinnerFocused, "focused spinner: \(m.spinnerFocused) against master's \(master.spinnerFocused)")
    #expect(m.spinnerDelta <= master.spinnerDelta, "spinner, retaining over retention off: \(m.spinnerDelta) against master's \(master.spinnerDelta)")
    #expect(m.wheel <= master.wheel, "wheel: \(m.wheel) against master's \(master.wheel)")
    #expect(m.glide <= master.glide, "glide: \(m.glide) against master's \(master.glide)")
    #expect(m.stream <= master.stream, "stream: \(m.stream) against master's \(master.stream)")
}
#endif

// MARK: 10c - a state write on every paint

/// An element whose paint writes state every time: a transient taint raised during paint (`stateWrite`).
private struct FGPaintWriter: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 10)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        pass.withState(id, initial: 0) { $0 += 1 }
        pass.fill(bounds, color: Hsla(h: 0.3, s: 1, l: 0.5, a: 1))
    }
}

private struct FGWriterCard: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup {
        let side = self.side
        VStack(spacing: 2) {
            TextField("write", text: Binding(get: { side.inputs.text }, set: { side.inputs.text = $0 })).frame(width: Pixels(200), height: Pixels(24))
            FGPaintWriter()
        }
    }
    static func == (l: FGWriterCard, r: FGWriterCard) -> Bool { l.side === r.side }
}

private struct FGWriterOuter: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup { FGWriterCard(side: side).equatable() }
    static func == (l: FGWriterOuter, r: FGWriterOuter) -> Bool { l.side === r.side }
}

/// **10c** A focused field beside an element whose paint writes state on every frame, under two occurrences: every frame raises the transient taint, so the backoff must stay
/// (a frame held plain raises it through its paint's state write, not through a recorder): over 20 frames the chain makes no more ledgers than master's (`fgWriterLedgersOnMaster`)
/// and no more paint attempts. Without the held paint's flag a backoff is lifted by every frame it holds plain, and the chain records and fails every other frame.
/// **Mutation:** M13 (`heldPaintDepth` not consulted).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aStateWriteOnEveryPaintBesideAFocusedFieldKeepsTheBackoff() throws {
    let side = RPSide()
    let w = try harnessWindow(size: sz(300, 120)) { VStack(spacing: 0) { FGWriterOuter(side: side).equatable() } }
    w.window.testingRetainedGraft = true
    w.typeKey(.tab)
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    #expect(w.window.focusedElement != nil, "the field is focused")
    let made = PrepaintLedger.madeCount
    w.resetFrameWork()
    var held = 0
    for _ in 0..<20 { w.window.setNeedsRedraw(); w.tick(); held += w.window.testingFocusBackoffCount > 0 ? 1 : 0 }
    let attempts = w.frameWork.reduce(0) { $0 + ($1.retainedIneligibleReasons["stateWrite"] ?? 0) }
    try? "ledgers \(PrepaintLedger.madeCount - made) paint attempts \(attempts) framesHeld \(held) redos \(w.frameWork.reduce(0) { $0 + $1.retainedRedos })\n".write(
        toFile: "/private/tmp/claude-501/-Users-maxburger-Developer-MetalUI/6204b926-398d-4909-80ba-c86fcdf2e673/scratchpad/focus-graft-agent/writer-\(ProcessInfo.processInfo.environment["FGD_TAG"] ?? "x").txt", atomically: true, encoding: .utf8)
    #expect(PrepaintLedger.madeCount - made <= fgWriterOnMaster.ledgers, "ledgers made over 20 frames: \(PrepaintLedger.madeCount - made) against master's \(fgWriterOnMaster.ledgers)")
    #expect(attempts <= fgWriterOnMaster.attempts, "paint attempts over 20 frames: \(attempts) against master's \(fgWriterOnMaster.attempts)")
}

/// What master makes of 10c's scenario (`fgWriterOnMaster`): measured by the same test on master `Sources/`.
private let fgWriterOnMaster = (ledgers: 2, attempts: 40)

// MARK: 11 - the names

/// **11** Every graft refusal is named, in `testingGraftRefusals` and in a `retained graft refused ... because <name>` trace line, and a quiet frame names none (the control).
/// The arms reach `focusMoved` (5b), `versions` (the composer's `@FocusState` bumped by a move of the focus) and `paintRecord`/`prepaintLedger`'s absence from a steady frame.
/// The other names are covered where their cause is made (`geometryGraft`, `scopedRedo`: `RetainedTranslationCarryTests`, `ScopedRedoTests`).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func everyGraftRefusalIsNamed() throws {
    let fg = try chat(focused: false, glide: false)
    let pair = fg.pair
    for step in 0..<4 { fgStep(fg, step, glide: false) }
    pair.redraw()
    #expect(pair.on.window.testingGraftRefusals.isEmpty, "the control: \(pair.on.window.testingGraftRefusals)")
    var names = Set<String>()
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    func note() { names.formUnion(pair.on.window.testingGraftRefusals) }
    for w in [pair.on, pair.off] { w.click(at: pt(60, 580)); w.exitPointer() }
    note()
    for _ in 0..<4 { pair.redraw(); note() }
    for w in [pair.on, pair.off] { w.window.focus(nil) }
    for _ in 0..<2 { pair.redraw(); note() }
    #expect(names.contains("versions"), "named: \(names)")
    for name in names {
        #expect(lines.contains { $0.contains("retained graft refused") && $0.contains("because \(name)") }, "a trace line for \(name)")
    }
}

// MARK: 12 - an unfocused chat costs what it did

/// **12** An unfocused chat, graft on, costs what it did on master: the work literals of the fixture's wheel and glide and of Alloy's markdown transcript
/// (`AlloyTranscriptFixture`). The allocations are 10b's. **Mutation:** M11.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func anUnfocusedChatsSteadyFrameCostsWhatItDid() async throws {
    for glide in [false, true] {
        let fg = try chat(focused: false, glide: glide)
        for step in 0..<6 {
            fgStep(fg, step, glide: glide)
            let w = StepWork(fg.pair.on.frameWork)
            #expect(w.requests == 5 && w.skipped == 40 && w.grafts == 17 && w.redos == 0, "glide \(glide) step \(step): \(w)")
        }
    }
    for wheel in [true, false] {
        let pair = try atPair(focused: false, graft: true)
        for i in 0..<9 {
            pair.on.resetFrameWork()
            if wheel { pair.on.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: i.isMultiple(of: 2) ? 24 : -16) }
            else { pair.onSide.inputs.offset += 1; await rsSettle(); pair.on.window.setNeedsRedraw(); pair.on.tick() }
            let w = StepWork(pair.on.frameWork)
            guard i >= 6 else { continue }
            if wheel { #expect(w.requests == 6 && w.skipped == 150 && w.grafts == 11 && w.misses == 0, "wheel \(i): \(w)") }
            else { #expect(w.requests == 11 && w.skipped == 140 && w.grafts == 10 && w.misses == 3, "stream \(i): \(w)") }
        }
    }
}

// MARK: 13 - idle

/// **13** A focused, grafted composer idles with no frame: once the scroller's fade is out, five seconds draw none, and on Darwin allocate nothing the unfocused
/// window does not.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aGraftedFocusedComposerIdlesWithNoFrame() throws {
    let focused = try chat(focused: true, glide: false), plain = try chat(focused: false, glide: false)
    for step in 0..<4 { fgStep(focused, step, glide: false); fgStep(plain, step, glide: false) }
    for fg in [focused, plain] { for w in [fg.pair.on] { w.advance(by: 3); w.advance(by: 1) } }
    for fg in [focused, plain] {
        let drawn = fg.pair.on.framesDrawn
        fg.pair.on.advance(by: 5)
        #expect(fg.pair.on.framesDrawn == drawn, "frames drawn while idle: \(fg.pair.on.framesDrawn - drawn)")
    }
    #if canImport(Darwin)
    let a = try #require(countAllocations { focused.pair.on.advance(by: 5) }), b = try #require(countAllocations { plain.pair.on.advance(by: 5) })
    #expect(a <= b, "idle allocations: focused \(a) against unfocused \(b)")
    #endif
}

// MARK: 14 - the differential and verify mode

/// **14** The focused chat equals a window that retains nothing at every step of a wheel and a glide, focused or not. Under `METALUI_VERIFY_RETAINED=1` every graft and
/// replay is built twice and compared (the focused element, the input method's target and the focus bindings included).
@Test(arguments: [true, false], [false, true]) @MainActor func theFocusedChatEqualsAFreshWindowAtEveryStepWithGraftsOn(focused: Bool, glide: Bool) throws {
    let fg = try chat(focused: focused, glide: glide)
    for step in 0..<10 {
        fgStep(fg, step, glide: glide)
        try fg.pair.compare("step \(step)")
    }
    #expect(sum(fg.pair.frames, \.retainedRedos) == 0 || rsVerifying, "nothing is redone: \(sum(fg.pair.frames, \.retainedRedos))")
}

/// A window of the composer alone, inside an occurrence of its own (the `.focusState` journal event is made by a `@FocusState` bound inside an open graft window), focused by Tab and drawn until its graft stands.
@MainActor private func fgSoloWindow() throws -> TestWindow {
    let side = RPSide()
    let window = try TestWindow(size: sz(300, 120), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { FGHost(side: side).equatable() }
    }
    _ = try? window.accessibilityTree
    window.typeKey(.tab)
    for _ in 0..<8 { window.window.setNeedsRedraw(); window.tick() }
    return window
}

/// **14b** A graft or a replayed ledger that leaves the focus state or the input method's target different from a fresh build traps, naming it (`RK-AS`): the
/// child drops the graft's `.focusState` events, or moves the ledger's text input caret by 1, and draws. **Mutation:** M9 (the `.focusState` replay dropped, the control
/// then fails to differ: no, it differs: `focus states` is the trap), M10 (the verify field dropped: the child exits normally and the arm reddens).
@Test(.serialized, arguments: [("focusStates", "build calls on the tables: focus states"), ("textInput", "text input")]) @MainActor
func aVerifiedFocusedGraftThatDiffersTraps(arm: (channel: String, word: String)) async {
    setTestEnvironment("FG_VERIFY_CHANNEL", arm.channel)
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            guard let window = try? fgSoloWindow() else { return }
            let channel = ProcessInfo.processInfo.environment["FG_VERIFY_CHANNEL"] ?? "focusStates"
            let damaged = channel == "focusStates" ? window.window.testingCorruptGraftRecords(channel) : window.window.testingCorruptPrepaintLedgers(channel)
            guard damaged > 0 else { print("nothing to damage"); return }
            window.window.setNeedsRedraw(); window.tick()
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("a replayed prepaint differs from a fresh one: \(arm.word)") || stderr.contains(arm.word), "the trap names \(arm.word): \(stderr.suffix(400))")
}

/// **14c** The control: an undamaged focused composer under verify mode draws normally (the exit tests above would pass for any crash).
@Test @MainActor func anUndamagedVerifiedFocusedGraftDrawsNormally() async {
    await #expect(processExitsWith: .success) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            guard let window = try? fgSoloWindow() else { exit(2) }
            for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
        }
    }
}

// MARK: 15 - the readers of the focus

/// **15** Every file under `Sources/` that reads `focusedElement` or `isFocused` outside a comment is named, by the phase it reads in. A graft stands under a focus because
/// every focus read of the build it skips is versioned (`TextEditState`, a `@FocusState`'s slot) or a function of `retainedFocus(under:)`: a new reader in a build owes
/// `RK-AS` a look. Mutation: a read added to any other file.
@Test func everyReaderOfTheFocusedElementIsNamed() throws {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources")
    let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var readers = Set<String>()
    for case let url as URL in walker where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("//") { continue }
            if line.contains("focusedElement") || line.contains("isFocused") { readers.insert(url.lastPathComponent); break }
        }
    }
    // By phase. Build: `TableBody` (compared with its own ids: a function of `retainedFocus(under:)`), `TerminalView` (a `@FocusState`, versioned). Prepaint: `TextField`, `TextEditor`,
    // `CodeViewPlan` (ledger and record keyed on the focus), `Frame` (registration, `$focus`), `RetainedPrepaint`, `RetainedSubtree`, `Window`. Paint: `AnimatedColor`, `Passes`
    // (`PaintPass.isFocused`), `Stack`. Outside every phase: `HoverKeyRegion`, `MenuBarStrip`, `SelectableText`, `KeyCapture`. Test support and accessors: `TestingHooks`,
    // `TestElement`, `TestWindow`, `TestWindowQueries`, `AppKitAccessibility`, the demos.
    let named: Set<String> = [
        "TableBody.swift", "TerminalView.swift", "TextField.swift", "TextEditor.swift", "CodeViewPlan.swift", "Frame.swift", "RetainedPrepaint.swift",
        "RetainedSubtree.swift", "Window.swift", "AnimatedColor.swift", "Passes.swift", "HoverKeyRegion.swift", "MenuBarStrip.swift", "SelectableText.swift",
        "KeyCapture.swift", "TestingHooks.swift", "TestElement.swift", "TestWindowQueries.swift", "AppKitAccessibility.swift"
    ]
    #expect(readers == named, "a new reader: \(readers.subtracting(named).sorted()); one gone: \(named.subtracting(readers).sorted())")
}
