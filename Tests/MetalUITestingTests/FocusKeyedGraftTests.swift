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
        let tainted = lines.contains { $0.contains("ineligible") && ($0.contains("because activeAnimation") || $0.contains("because stateWrite")) }
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

/// **3** A transient taint (a fade, a glide) is not a failure under a focus: during the scroll no occurrence is held plain (`testingFocusBackoffCount` 0, no
/// `focusBackoff` line; master: 40 lines in 12 steps), and the frame the fade ends in records as the unfocused window's does. **Mutation:** M5.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func theFocusedChainRecordsTheFrameTheFadeEnds() throws {
    let focused = try chat(focused: true, glide: false), plain = try chat(focused: false, glide: false)
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    for step in 0..<6 {
        fgStep(focused, step, glide: false); fgStep(plain, step, glide: false)
        #expect(focused.pair.on.window.testingFocusBackoffCount == 0, "step \(step)")
    }
    RetainedTrace.sink = nil
    #expect(!lines.contains { $0.contains("focusBackoff") }, "no backoff line: \(lines.filter { $0.contains("focusBackoff") }.prefix(2))")
    for _ in 0..<2 { for w in [focused.pair.on, plain.pair.on, focused.pair.off, plain.pair.off] { w.advance(by: 0.5) } }
    for w in [focused.pair.on, plain.pair.on, focused.pair.off, plain.pair.off] { w.advance(by: 2) }
    for frame in 0..<4 {
        focused.pair.on.resetFrameWork(); plain.pair.on.resetFrameWork()
        focused.pair.redraw(); plain.pair.redraw()
        let a = StepWork(focused.pair.on.frameWork), b = StepWork(plain.pair.on.frameWork)
        // The frame the fade ends in stores the column's record in both windows; under a focus the capture waits for a frame that hits it (`RK-AS`, c2): one frame later.
        if frame == 0 { #expect(a.requests <= 5 && a.redos == 0, "the frame the fade ends in: focused \(a)") }
        else { #expect(a == b, "settled frame \(frame): focused \(a) against unfocused \(b)") }
    }
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

/// **10** A `ProgressView` beside the focused composer animates on every frame (a standing taint in effect: it never ends): the focused chat does what the unfocused one
/// does, in requests and allocations, which prices the choice to back off only standing taints. **Mutation:** M5.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aPerpetualAnimationBesideAFocusedFieldCostsWhatItCostsUnfocused() throws {
    let focused = try chat(focused: true, glide: false, spinner: true), plain = try chat(focused: false, glide: false, spinner: true)
    for step in 0..<6 {
        fgStep(focused, step, glide: false); fgStep(plain, step, glide: false)
        let a = StepWork(focused.pair.on.frameWork), b = StepWork(plain.pair.on.frameWork)
        #expect(a.requests <= b.requests && a.redos == b.redos, "step \(step): focused \(a) against unfocused \(b)")
    }
    #if canImport(Darwin)
    func least(_ fg: FGPair<some Element>) throws -> Int {
        var counts: [Int] = []
        for step in 6..<14 { counts.append(try #require(countAllocations { fgStep(fg, step, glide: false, retainingOnly: true) })) }
        return counts.min() ?? 0
    }
    let a = try least(focused), b = try least(plain)
    #expect(a <= b, "allocations a step: focused \(a) against unfocused \(b)")
    #endif
}

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

#if canImport(Darwin)
private let fgAllocationsOnMaster = (wheel: 27_026, glide: 27_145, atWheel: 28_196, atStream: 29_395)

/// The allocations of an unfocused chat's steps, the least of eight, against master's; `nil` when none is over. Run in a child process: an allocation count depends on
/// what the process shaped and cached before (the same steps measure 36 more after a dozen other windows have drawn), and master's literals were measured in a fresh one.
@MainActor private func fgAllocationsOverMaster() async throws -> String? {
    var over: [String] = []
    for glide in [false, true] {
        let fg = try chat(focused: false, glide: glide)
        for step in 0..<6 { fgStep(fg, step, glide: glide, retainingOnly: true) }
        var counts: [Int] = []
        for step in 6..<14 { counts.append(try #require(countAllocations { fgStep(fg, step, glide: glide, retainingOnly: true) })) }
        let limit = glide ? fgAllocationsOnMaster.glide : fgAllocationsOnMaster.wheel
        if (counts.min() ?? .max) > limit { over.append("glide \(glide): \(counts) against master's \(limit)") }
    }
    for wheel in [true, false] {
        let pair = try atPair(focused: false, graft: true)
        func step(_ i: Int) async {
            if wheel { pair.on.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: i.isMultiple(of: 2) ? 24 : -16) }
            else { pair.onSide.inputs.offset += 1; await rsSettle(); pair.on.window.setNeedsRedraw(); pair.on.tick() }
        }
        for i in 0..<6 { await step(i) }
        var counts: [Int] = []
        for i in 6..<14 {
            var c: Int?
            if wheel { c = countAllocations { pair.on.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: i.isMultiple(of: 2) ? 24 : -16) } }
            else { pair.onSide.inputs.offset += 1; await rsSettle(); c = countAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() } }
            if let c { counts.append(c) }
        }
        let limit = wheel ? fgAllocationsOnMaster.atWheel : fgAllocationsOnMaster.atStream
        if (counts.min() ?? .max) > limit { over.append("transcript wheel \(wheel): \(counts) against master's \(limit)") }
    }
    return over.isEmpty ? nil : over.joined(separator: "; ")
}
#endif

/// **12** An unfocused chat, graft on, costs what it did on master: the work literals of the fixture's wheel and glide and of Alloy's markdown transcript
/// (`AlloyTranscriptFixture`), and (12b, Darwin) allocations a step, the least of eight, no more than master's measured at step 0 in a fresh process: the fixture 27,026 and
/// 27,145, Alloy's transcript 28,196 and 29,395. The refusal names, the taint classification and the ping-pong of the names add none. **Mutation:** M11 (the ping-pong back
/// to `= []`, or the trace line's autoclosure built eagerly: +19 a frame).
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

#if canImport(Darwin)
/// **12b** The allocation half of 12, in a child process (see `fgAllocationsOverMaster`).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func anUnfocusedChatsStepAllocatesNoMoreThanMasterDid() async {
    let result = await #expect(processExitsWith: .success, observing: [\.standardErrorContent]) {
        let over = try await fgAllocationsOverMaster()
        FileHandle.standardError.write(Data(("FG-ALLOCATIONS " + (over.map { "OVER " + $0 } ?? "OK")).utf8))
    }
    let report = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(report.contains("FG-ALLOCATIONS OK"), "\(report.suffix(600))")
}
#endif

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
