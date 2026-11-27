import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
#if canImport(Darwin)
import MetalUITestSupport
#endif
import Testing

// Record 440 (`RK-AQ`): a retained occurrence is keyed on **which element under it is focused**, not refused whenever one is. A ledger stores the
// focus it was made under, a record the focus it was painted under; both replay only while the focus now is that one, so every focus read inside
// the occurrence (only the focused element reads focus) is a function of one id. The focused leaf's frame effects are ledger entries. The fixture is
// Alloy's chat (`AlloyTranscriptFixture.swift`): a transcript over a composer, the composer's field focused. Counts are work, never time.

private let verifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read; the differential runs under it"

private func sum(_ frames: [FrameWork], _ key: KeyPath<FrameWork, Int>) -> Int { frames.reduce(0) { $0 + $1[keyPath: key] } }

/// What a step costs, the counters a focused window must share with an unfocused one.
private struct StepWork: Equatable, CustomStringConvertible {
    var prepaints: Int, paints: Int, prepaintHits: Int, hits: Int, requests: Int, redos: Int
    init(_ frames: [FrameWork]) {
        prepaints = sum(frames, \.elementPrepaints); paints = sum(frames, \.elementPaints)
        prepaintHits = sum(frames, \.retainedPrepaintHits); hits = sum(frames, \.retainedHits)
        requests = sum(frames, \.elementRequests); redos = sum(frames, \.retainedRedos)
    }
    var description: String { "prepaints \(prepaints) paints \(paints) prepaintHits \(prepaintHits) hits \(hits) requests \(requests) redos \(redos)" }
}

// MARK: 1 - the ancestors replay

/// **1** The field is focused by a click, the pointer leaves, and the frames settle: every redraw after that misses nowhere, and the session (the
/// composer's ancestor) replays its prepaint. On master: the three occurrences above the field missed every frame.
/// **Mutation:** `focusMoved` forced true (misses 3 a frame); the paint store rule restored (the record is discarded).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFocusedComposersAncestorsReplayWhileFocusStays() throws {
    let pair = try atPair(focused: true)
    #expect(pair.on.window.focusedElement != nil, "the click focused the field")
    for step in 0..<10 {
        pair.redraw()
        let f = try #require(pair.frames.last)
        #expect(f.retainedMisses == 0 && f.retainedPrepaintHits >= 1 && f.retainedRedos == 0, "frame \(step): misses \(f.retainedMisses) prepaint hits \(f.retainedPrepaintHits)")
    }
    try pair.compare("ten redraws")
}

// MARK: 2 - the cost

/// **2** Per stream step and per wheel step, a window with the field focused does the work of one with nothing focused (graft off on both sides,
/// so the builds that run are counted). Master: the focused pair built, prepainted and painted the composer's three ancestors every frame.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFocusedComposerCostsWhatAnUnfocusedOneCosts() async throws {
    let focused = try atPair(focused: true), plain = try atPair(focused: false)
    for step in 0..<4 {
        let a = StepWork(await atStream(focused)), b = StepWork(await atStream(plain))
        #expect(a == b, "stream \(step): focused \(a) against unfocused \(b)")
    }
    for step in 0..<4 {
        atWheel(focused, dy: step.isMultiple(of: 2) ? 24 : -16); atWheel(plain, dy: step.isMultiple(of: 2) ? 24 : -16)
        let a = StepWork(focused.on.frameWork), b = StepWork(plain.on.frameWork)
        #expect(a == b, "wheel \(step): focused \(a) against unfocused \(b)")
    }
    try focused.compare("focused")
}

// MARK: 3 - the trace

/// **3** No miss names the pointer, a press or focus with the pointer away, and after the first settled frame none names focus at all: what is left
/// is the work the unfocused window does (`serial`, `observed`, `versions`). The trace text is the rule's: `pointer/press under the occurrence`.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func noPrepaintMissNamesFocusWithThePointerAway() async throws {
    let pair = try atPair(focused: true)
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    pair.redraw()
    _ = await atStream(pair)
    let settled = lines.count
    atWheel(pair, dy: 24)   // the wheel's pointer is over the transcript: its hover is its own, never focus
    RetainedTrace.sink = nil
    #expect(!lines[..<settled].contains { $0.contains("pointer/press") }, "no line names the pointer or a press: \(lines.filter { $0.contains("pointer/press") }.prefix(3))")
    let misses = lines.filter { $0.contains("retained prepaint miss") || $0.contains("retained paint miss") }
    for line in misses {
        let reasons = traceReasons(line) ?? []
        #expect(!reasons.contains("focus"), "no miss is for focus: \(line.prefix(200))")
        if lines.firstIndex(of: line).map({ $0 < settled }) ?? false {
            #expect(!reasons.contains("pointer") && !reasons.contains("pointerInLedger"), "no settled miss is for the pointer: \(line.prefix(200))")
        }
    }
    #expect(!misses.isEmpty, "the stream and the wheel miss for the work they do")
}

// MARK: 4 - typing

/// **4** Typing "abc" into the focused field: the text appears, the two windows draw the same, each key frame misses the chain (the field's state
/// moved: `versions`), and the frames after the keys replay again.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aTypedCharacterAppearsAndOnlyTheKeyFrameMisses() throws {
    let pair = try atPair(focused: true)
    for character in ["a", "b", "c"] {
        pair.on.resetFrameWork()
        for w in [pair.on, pair.off] { w.typeText(character) }
        let keyFrames = pair.on.frameWork
        #expect(sum(keyFrames, \.retainedMisses) >= 1, "the key frame misses the chain: \(sum(keyFrames, \.retainedMisses))")
        #expect(sum(keyFrames, \.retainedRedos) == 0)
        try pair.compare("typed \(character)")
    }
    #expect(pair.onSide.inputs.text == "abc" && pair.offSide.inputs.text == "abc", "the text is typed: \(pair.onSide.inputs.text)")
    for _ in 0..<2 { pair.redraw() }
    pair.redraw()
    #expect(pair.frames.last?.retainedMisses == 0, "the next quiet frame replays: \(String(describing: pair.frames.last?.retainedMisses))")
    try pair.compare("after typing")
}

// MARK: 5 - focus moving inside one occurrence

private struct FKTwoFields: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup {
        let side = self.side
        VStack(spacing: 4) {
            TextField("one", text: Binding(get: { side.inputs.text }, set: { side.inputs.text = $0 })).frame(width: Pixels(200), height: Pixels(24))
            TextField("two", text: Binding(get: { "" }, set: { _ in })).frame(width: Pixels(200), height: Pixels(24))
        }
    }
    static func == (l: FKTwoFields, r: FKTwoFields) -> Bool { l.side === r.side }
}

/// **5** Tab from the first field to the second, both under one occurrence: that frame misses once (`focus`), the ring moves (the two windows draw
/// the same), and once the focus stays the occurrence replays. **Mutation:** `focusMoved` forced false (the ring is stale: `compare` reddens).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func focusMovingBetweenTwoFieldsInOneOccurrenceRepaintsItOnce() throws {
    let pair = try RPPair(size: sz(260, 140), accessibility: false) { side in VStack(spacing: 0) { FKTwoFields(side: side).equatable() } }
    for w in [pair.on, pair.off] { w.typeKey(.tab) }
    for _ in 0..<3 { pair.redraw() }
    #expect(pair.frames.last?.retainedMisses == 0, "the first field's focus replays")
    try pair.compare("focused")
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.typeKey(.tab) }
    RetainedTrace.sink = nil
    let moved = pair.on.frameWork
    #expect(sum(moved, \.retainedMisses) == 1 && sum(moved, \.retainedRedos) == 0, "the tab frame misses once: \(sum(moved, \.retainedMisses))")
    #expect(lines.contains { (traceReasons($0) ?? []).contains("focus") }, "and names focus: \(lines.map { $0.prefix(120) })")
    try pair.compare("tabbed")
    for _ in 0..<3 { pair.redraw() }
    #expect(pair.frames.last?.retainedMisses == 0, "then it replays")
    try pair.compare("settled")
}

// MARK: 6 - focus leaving

/// **6** The field is blurred: the chain repaints once, never redoes, and replays after. With the graft on, no graft is taken from a record made
/// under a focus (the frame after the blur builds). **Mutation:** the graft's `focusedUnder` check removed (a redo).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func focusLeavingTheChainRepaintsOnceAndNeverRedoes() throws {
    let pair = try atPair(focused: true, graft: true)
    for _ in 0..<3 { pair.redraw() }
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.window.focus(nil) }
    for _ in 0..<4 { pair.redraw() }
    let frames = pair.on.frameWork
    #expect(sum(frames, \.retainedRedos) == 0 && sum(pair.frames, \.retainedRedos) == 0, "the blur redoes nothing")
    #expect(sum(pair.frames, \.retainedMisses) >= 1, "the chain repaints for the blur")
    #expect(pair.frames.last?.retainedMisses == 0, "and replays after")
    try pair.compare("blurred")
}

// MARK: 7 - the focus slot stays live

/// **7** A replayed ledger keeps the `$focus` slot live: with the state table above `sweepThreshold`, frames of a replaying session run past
/// `staleAfterGenerations`, and the focused field's retention entry is still there, as it is in the window that retains nothing. **Mutation:** the
/// `.focused` entry not replayed (the slot is reaped; verify mode's marked-set channel reddens too).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aReplayedLedgerKeepsTheFocusSlotLive() throws {
    let pair = try atPair(focused: true)
    let focus = try #require(pair.on.window.focusedElement)
    let slot = Frame.focusRetentionSlot(for: focus)
    for w in [pair.on, pair.off] {
        for index in 0..<(StateTable.sweepThreshold + 44) {
            w.window.stateTable.withState(.child(of: focus, at: index, name: ElementID("$fkseed\(index)")), initial: 0) { _ in }
        }
    }
    pair.frames = []
    for _ in 0..<(Int(StateTable.staleAfterGenerations) * 2 + 2) { pair.redraw() }
    #expect(sum(pair.frames, \.retainedMisses) == 0, "the frames replay: \(sum(pair.frames, \.retainedMisses))")
    for (name, w) in [("on", pair.on), ("off", pair.off)] {
        #expect(w.window.stateTable.peek(slot, as: Bool.self) != nil, "\(name): the focus slot is kept")
        #expect(w.window.focusedElement == focus, "\(name): the focus is kept")
    }
}

// MARK: 8 - a boundary change

private struct FKTapCard: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Box().frame(width: Pixels(60), height: Pixels(20)).background(.accent).onTapGesture {}
            Text("card").frame(width: Pixels(60), height: Pixels(14))
        }
    }
    static func == (l: FKTapCard, r: FKTapCard) -> Bool { true }
}

/// **8** `Window.focus(x)` on a produced, enabled element that is not focusable, inside a replaying occurrence: the prepaint sees the request, the
/// boundary clears it, and the two windows end with no focus. Nothing is redone (a ledger made before the request is not replayed under it).
/// **Mutation:** the prepaint compares only the ledger's focus, not the record's.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFocusBoundaryChangeNeverRedoes() throws {
    let pair = try RPPair(size: sz(200, 120), accessibility: false) { _ in VStack(spacing: 0) { FKTapCard().equatable() } }
    for _ in 0..<3 { pair.redraw() }
    let target = try #require(pair.on.window.lastHitboxes.first { !$0.handlers.isFocusable && $0.handlers.isPointerTarget }?.id)
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.window.focus(target); w.window.setNeedsRedraw(); w.tick() }
    for _ in 0..<3 { pair.redraw() }
    #expect(pair.on.window.focusedElement == nil && pair.off.window.focusedElement == nil, "the boundary cleared the request in both windows")
    #expect(sum(pair.on.frameWork, \.retainedRedos) == 0 && sum(pair.frames, \.retainedRedos) == 0, "nothing is redone")
    try pair.compare("a focus request")
}

// MARK: 9 - a moved text input

private struct FKHidden: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup {
        let side = self.side
        TextField("quiet", text: Binding(get: { side.inputs.text }, set: { side.inputs.text = $0 }))
            .frame(width: Pixels(200), height: Pixels(24)).allowsHitTesting(false)
    }
    static func == (l: FKHidden, r: FKHidden) -> Bool { l.side === r.side }
}

/// **9** A header above a hit-test-disabled field grows by 4: the occurrence moves, its ledger holds a text input's focus stop (the field has no
/// hitbox to refuse the move), so the move is refused by name (`focusTextInput`) and the input method's caret rect is the one a fresh window reports.
/// **Mutation:** the `focusTextInput` refusal removed (a stale caret rect).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aMovedAncestorOfAHitTestDisabledFieldRefusesFocusTextInput() throws {
    let pair = try RPPair(size: sz(260, 140), accessibility: false) { side in
        VStack(spacing: 0) {
            Box().frame(width: Pixels(100), height: Pixels(20 + side.inputs.offset))
            FKHidden(side: side).equatable()
        }
    }
    for w in [pair.on, pair.off] { w.typeKey(.tab) }
    for _ in 0..<3 { pair.redraw() }
    #expect(pair.on.window.focusedElement != nil, "the tab reached the field without a hitbox")
    pair.on.resetFrameWork()
    pair.onSide.inputs.offset = 4; pair.offSide.inputs.offset = 4
    pair.redraw()
    #expect(pair.on.frameWork.reduce(0) { $0 + ($1.retainedTranslationRefusedReasons["focusTextInput"] ?? 0) } >= 1, "the move is refused by name")
    #expect(pair.on.platformWindow.textInputAreas.last == pair.off.platformWindow.textInputAreas.last, "the caret rect follows the field: \(String(describing: pair.on.platformWindow.textInputAreas.last)) vs \(String(describing: pair.off.platformWindow.textInputAreas.last))")
    try pair.compare("moved")
}

// MARK: 10 - idle

/// **10** A focused composer draws no frame while nothing happens: its caret does not blink (`TextField`), so no deadline is asked for.
@Test @MainActor func aFocusedComposerIdlesWithNoFrame() throws {
    let pair = try atPair(focused: true)
    let drawn = pair.on.framesDrawn
    pair.on.advance(by: 5)
    #expect(pair.on.framesDrawn == drawn, "frames drawn while idle: \(pair.on.framesDrawn - drawn)")
}

// MARK: 11 - the blink

private struct FKBlinkLeaf: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false).codeCaretBlink(.on)
    }
    static func == (l: FKBlinkLeaf, r: FKBlinkLeaf) -> Bool { l.buffer === r.buffer }
}
private struct FKBlinkMid: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    var content: some ElementGroup { FKBlinkLeaf(buffer: buffer).equatable() }
    static func == (l: FKBlinkMid, r: FKBlinkMid) -> Bool { l.buffer === r.buffer }
}
private struct FKBlinkOuter: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    var content: some ElementGroup { FKBlinkMid(buffer: buffer).equatable() }
    static func == (l: FKBlinkOuter, r: FKBlinkOuter) -> Bool { l.buffer === r.buffer }
}

/// **11** A focused, blinking `CodeView` under three nested occurrences, the pointer away, 40 toggles: its caret taints every paint record, so
/// without a bound every frame would make three ledgers and three records and store none. The backoff (8 builds, doubling) leaves it a few attempts:
/// 40 frames, at most 9 ledgers, the same 120 `codeCaretBlink` ineligibles master counted, and allocations no more than master's 35,588 (measured at
/// step 0; the unbounded first version made 120 ledgers and 38,828). **Mutation:** the backoff removed (ledgers 120).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFocusedCodeViewsBlinkFramesCostNoMoreThanToday() throws {
    let buffer = CodeBuffer("hello\nworld\n")
    let w = try harnessWindow(size: sz(400, 200)) { VStack(spacing: 0) { FKBlinkOuter(buffer: buffer).equatable() } }
    w.click(at: pt(60, 6)); w.exitPointer()
    buffer.selections = [CodeSelection(caret: 0)]
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    let drawn = w.framesDrawn, made = PrepaintLedger.madeCount
    w.resetFrameWork()
    #if canImport(Darwin)
    let allocations = try #require(countAllocations { for _ in 0..<40 { w.advance(by: 0.5) } })
    #else
    for _ in 0..<40 { w.advance(by: 0.5) }
    #endif
    #expect(w.framesDrawn - drawn == 40, "one frame a toggle: \(w.framesDrawn - drawn)")
    #expect(PrepaintLedger.madeCount - made <= 9, "three attempts of three: \(PrepaintLedger.madeCount - made)")
    #expect(sum(w.frameWork, \.retainedRedos) == 0)
    #expect(w.frameWork.reduce(0) { $0 + ($1.retainedIneligibleReasons["codeCaretBlink"] ?? 0) } == 120, "the ineligibles master counted")
    #if canImport(Darwin)
    #expect(allocations <= 35_588, "allocations over the 40 toggles: \(allocations) (master 35,588)")
    #endif
}

// MARK: 12 - the whole chat

/// **12** Alloy's chat with the composer focused equals a window that retains nothing at every step of a stream and a scroll, under verify mode too
/// (a replay is built twice there and compared, the focused element after `resolveFocus` included).
@Test(arguments: [true, false]) @MainActor func theAlloyTranscriptEqualsAFreshWindowAtEveryStep(focused: Bool) async throws {
    let pair = try atPair(focused: focused)
    for step in 0..<4 {
        _ = await atStream(pair)
        try pair.compare("stream \(step)")
    }
    for step in 0..<4 {
        atWheel(pair, dy: step.isMultiple(of: 2) ? 24 : -16)
        try pair.compare("wheel \(step)")
    }
    #expect(sum(pair.frames, \.retainedRedos) == 0 || rsVerifying, "nothing is redone: \(sum(pair.frames, \.retainedRedos))")
}
