import Foundation
import MetalUI
import MetalUICore
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14b-3 lane B (`RW-`): the converted call sites (scroll, list, field, editor) and the replayed anchors, each against a
// retention-off twin of the same window. A differential that replays nothing proves nothing, so every test also reads what
// the retaining side replayed. Counts, never time.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"

// MARK: The twin: one retaining orbit window and one that retains nothing

@MainActor struct PanelTwin {
    let on: BracketOrbit
    let off: BracketOrbit
    var frames: [FrameWork] = []
    /// The centre of the library list's first rows, read once before anything scrolls.
    let listPoint: Point<Pixels>

    init(warm: Int = 5, graft: Bool = true) throws {
        on = try BracketOrbit(arm: .panels, retained: true, prepaint: true, graft: graft)
        off = try BracketOrbit(arm: .panels, retained: false)
        // Both windows share one clock: each anchors its keyframe clock to the wall clock otherwise (`RK-AD`).
        on.window.window.testingTimelineClockOffset = 0
        off.window.window.testingTimelineClockOffset = 0
        for _ in 0..<warm { on.orbitFrame(); off.orbitFrame() }
        on.window.resetFrameWork()
        let row = try on.window.element(label: "Operation 1")
        listPoint = Point(x: Pixels(row.visibleFrame.origin.x.value + row.visibleFrame.size.width.value / 2),
                          y: Pixels(row.visibleFrame.origin.y.value + row.visibleFrame.size.height.value / 2))
    }

    /// One orbit frame on both windows.
    mutating func orbit() {
        on.orbitFrame(); off.orbitFrame()
        frames.append(on.window.lastFrameWork)
    }

    /// Runs `input` against both windows, then one frame on each.
    mutating func act(_ input: (TestWindow) throws -> Void) throws {
        for w in [on.window, off.window] { try input(w) }
        for w in [on.window, off.window] { w.window.setNeedsRedraw(); w.tick() }
        frames.append(on.window.lastFrameWork)
    }

    /// Moves the pointer out of the window on both sides: a panel the pointer rests in never replays (`SB-X`), so a test that
    /// reads a replay after an input that left the pointer there first leaves.
    mutating func leavePointer() throws { try act { $0.exitPointer() } }

    /// Tabs on both sides until the focused element is a slider, which lives in the inspector (a field's next Tab stop is another control
    /// of the graph panel, and a focused element under a panel is `SB-X`, and Tab wraps rather than leaves): bounded.
    mutating func focusTheInspector() throws {
        var presses = 0
        while try on.window.focusedElement?.role != .slider, presses < 80 {
            try act { $0.typeKey(.tab) }
            presses += 1
        }
        try #require(try on.window.focusedElement?.role == .slider && off.window.focusedElement?.role == .slider,
                     "Tab reached the inspector after \(presses) presses")
    }

    /// Whether the graph panel (and so the field in it) replayed in the last orbit frame: a replayed panel's 31 nested nodes are
    /// not evaluated, a panel that ran lets them count their own hits. Another panel may hold the focus.
    var graphPanelReplays: Bool {
        guard let f = frames.last else { return false }
        return f.retainedHits <= 3 && f.retainedIneligible == 0 && f.retainedPrepaintIneligible == 0
    }

    mutating func advance(_ seconds: Double) {
        for w in [on.window, off.window] { w.advance(by: seconds) }
        frames.append(on.window.lastFrameWork)
    }

    /// Scene, accessibility tree, hitboxes, tallies, Tab order, bounds and the state table's entries (versions and
    /// liveness are the sweep's own, so they differ by design: only the keys and values compare) equal on both sides.
    func compare(_ step: String) throws {
        let differences = try RPSnapshot(on.window).differences(from: RPSnapshot(off.window))
        #expect(differences.isEmpty, "after \(step): \(differences)")
        #expect(on.window.window.testingStateEntries == off.window.window.testingStateEntries, "state table after \(step)")
        #expect(off.window.lastFrameWork.retainedHits == 0 && off.window.lastFrameWork.retainedPrepaintHits == 0)
    }

    func text(_ s: String) throws -> TestElement { try on.window.element(label: s) }

    /// Whether the last orbit frame replayed the three panels (the top bar, the graph panel, the inspector): a replaying panel's
    /// nested nodes are not evaluated, so the frame counts exactly three hits; a panel that runs lets its 31 nested nodes count
    /// their own (34 hits), which is why a `>= 3` read cannot tell the two apart.
    var panelsReplay: Bool {
        guard let f = frames.last else { return false }
        return f.retainedHits == 3 && f.retainedMisses == 0 && f.retainedIneligible == 0 && f.retainedPrepaintIneligible == 0
    }
}

@MainActor private func element(_ w: TestWindow, _ label: String) throws -> TestElement { try w.element(label: label) }

@MainActor private func fieldValue(_ w: TestWindow) throws -> String? {
    try w.elements(role: .textField).first?.value
}

// MARK: Test 4 — a wheel inside a retained panel

/// **Test 4** (`RW-H`, `RW-B`): a wheel over the retained panel's list. The frame after the wheel is a counted **miss**
/// (the scroller's `ScrollState` version moved: the read set, not the `@State` slots, is what names it), the scene,
/// accessibility tree and hitboxes equal a fresh window's at every step, and once the indicator has faded the panel
/// replays again. **Red before** (lane A): the panel was ineligible (`stateWrite`), so the retaining window never hit.
/// **Mutation:** `readState`'s read not appended to the read journal (`StateTable.noteRead` returning early) — the hit
/// after the wheel replays the old offset and the scene differs.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aWheelInsideARetainedPanelMissesOnTheScrollStateVersionAndMatchesAFreshWindow() throws {
    var twin = try PanelTwin()
    try twin.compare("warm")
    twin.orbit()
    #expect(twin.panelsReplay, "the panel replays before the wheel: \(String(describing: twin.frames.last))")

    // The wheel, then the frame it dirties.
    try twin.act { [p = twin.listPoint] w in w.scroll(at: p, byDeltaX: 0, deltaY: -60) }
    let afterWheel = try #require(twin.frames.last)
    // The scrolled panel does not replay: its version moved (a miss), and while the indicator fades it asks for another frame
    // (counted ineligible by name, `RW-H`); its 31 nested nodes then count their own hits.
    #expect(!twin.panelsReplay, "the scrolled panel runs: hits \(afterWheel.retainedHits) misses \(afterWheel.retainedMisses)")
    #expect(afterWheel.retainedMisses + afterWheel.retainedIneligible >= 1)
    try twin.compare("the frame after the wheel")
    try twin.leavePointer()

    // Through the fade and past it.
    for step in 0..<4 { twin.advance(0.4); try twin.compare("fade step \(step)") }
    for step in 0..<3 { twin.orbit(); try twin.compare("orbit \(step) after the fade") }
    let settled = try #require(twin.frames.last)
    #expect(twin.panelsReplay, "the panel replays again once the indicator has faded: \(settled.retainedHits)")
    #expect(settled.retainedGraftIneligible == 0)

    // Wheel back up: a second miss, equal again.
    try twin.act { [p = twin.listPoint] w in w.scroll(at: p, byDeltaX: 0, deltaY: 60) }
    try twin.compare("the wheel back")
    twin.advance(2); twin.orbit(); twin.orbit()
    try twin.compare("settled again")
}

// MARK: Test 5 — a list window is a function of the state it reads

/// **Test 5** (`RW-I`): scroll the list a long way, resize the window, scroll back; after every step the built rows
/// (read as the accessibility tree's rows), the state table (TB-AH ageing of out-of-window rows' entries) and the scene equal
/// a retention-off window's, with the graft on. **Mutation:** `ListOrigin`'s `peek` read at `List.swift` `noteOriginAndStaleness`'s
/// neighbour (`:460`) not recorded, or `ListOrigin.sameEntry` always true (the stored offset never follows) — the window sticks.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aListWindowIsAFunctionOfTheStateItReads() throws {
    var twin = try PanelTwin()
    try twin.compare("warm")
    for dy in [Float(-300), -800, -2000] {
        try twin.act { [p = twin.listPoint] w in w.scroll(at: p, byDeltaX: 0, deltaY: dy) }
        try twin.compare("scroll \(dy)")
        twin.advance(1.5); twin.orbit(); twin.orbit()
        try twin.compare("settled after \(dy)")
    }
    // The row the list now shows differs from the first window's rows: the window moved.
    let rows = try twin.on.window.elements(role: .staticText).filter { ($0.value ?? "").hasPrefix("Operation") }
    #expect(!rows.isEmpty)
    for w in [twin.on.window, twin.off.window] { w.resize(to: Size(width: Pixels(1440), height: Pixels(700))) }
    twin.orbit(); twin.orbit()
    try twin.compare("resized shorter")
    for w in [twin.on.window, twin.off.window] { w.resize(to: bracketWindowSize) }
    twin.orbit(); twin.orbit()
    try twin.compare("resized back")
}

// MARK: Test 6 — an unfocused field keeps its state across many replays

/// **Test 6** (`RW-E`, `RW-J`): a field is focused, typed into and left; 300 orbit frames replay its panel; the field's
/// state entry is still present, live, with the same caret and value as the twin's. **Mutations (three):** the paint record's
/// `lives` replay, the prepaint ledger's `liveStates` replay or the graft's `.liveState` re-application removed — the entry
/// is swept after a few replays and the field's text, caret and scroll reset (the state table differs from the twin's).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func anUnfocusedFieldKeepsItsStateAcrossThreeHundredReplays() throws {
    var twin = try PanelTwin()
    try twin.act { w in try w.typeText("abc", into: try w.elements(role: .textField)[0]) }
    try twin.focusTheInspector()   // leaves the field and every other stop
    try twin.leavePointer()
    try twin.compare("typed and left")
    #expect(try fieldValue(twin.on.window) == "abc")
    for _ in 0..<5 { twin.orbit() }
    try twin.compare("five replays")
    let before = twin.on.window.window.testingStateEntries
    var hits = 0
    for frame in 0..<300 {
        twin.orbit()
        if twin.graphPanelReplays { hits += 1 }
        if frame % 100 == 99 { try twin.compare("replay \(frame + 1)") }
    }
    #expect(hits >= 295, "the unfocused field's panel replays through the run: \(hits) of 300")
    #expect(twin.on.window.window.testingStateEntries == before, "the field's entry survived unchanged")
    #expect(try fieldValue(twin.on.window) == "abc")
}

// MARK: Test 7 — a focused field misses; typing works

/// **Test 7** (`RW-J`, `SB-X`): focus the field, type, backspace, compose with the input method, commit, and leave. Every
/// step's scene and accessibility value equal the twin's; the panel is a counted miss (not a hit) while the field holds focus and
/// replays again one frame after it is left. **Mutation:** `SB-X`'s focused-under test (`RetainedSubtree`'s focused descendant
/// check) made false — a typed character does not appear in the retaining window.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aFocusedFieldInsideARetainedPanelMissesAndTypingWorks() throws {
    var twin = try PanelTwin()
    twin.orbit()
    #expect(twin.panelsReplay)
    try twin.act { w in try w.click(try w.elements(role: .textField)[0]) }
    try twin.compare("focused")
    for step in ["a", "bc", "d"] {
        try twin.act { w in w.typeText(step) }
        try twin.compare("typed \(step)")
        let f = try #require(twin.frames.last)
        #expect(!twin.graphPanelReplays, "a focused field's panel is not replayed: hits \(f.retainedHits)")
    }
    try twin.act { w in w.typeKey(.delete) }
    try twin.compare("backspace")
    twin.orbit(); twin.orbit()
    try twin.compare("orbit while focused")
    #expect(try fieldValue(twin.on.window) == (try fieldValue(twin.off.window)))
    var composed = 0
    try twin.act { w in if w.setMarkedText("é", selectedRange: 0..<1) { composed += 1 } }
    try twin.compare("composing")
    try twin.act { w in _ = w.commitMarkedText() }
    try twin.compare("committed")
    #expect(composed == 2, "both windows composed")
    try twin.focusTheInspector()
    try twin.leavePointer()
    try twin.compare("left the field")
    twin.orbit(); twin.orbit(); twin.orbit()
    try twin.compare("orbit after leaving")
    let after = try #require(twin.frames.last)
    #expect(twin.graphPanelReplays, "the panel replays once the field is left: \(after.retainedHits)")
    #expect(try fieldValue(twin.on.window) == (try fieldValue(twin.off.window)))
}

// MARK: Test 8 — a selection change inside a retained list

@Observable @MainActor final class RWSelectionModel {
    var selection: Int? = nil
    var multi: Set<Int> = []
}

struct RWRow: Identifiable { let id: Int }

/// A selectable `List` in an `.equatable()` component whose value is its model's identity: the selection is an observed read
/// of the model, so a change is a content miss, never a stale replay.
struct RWSelectableCard: Component, @MainActor Equatable {
    let model: RWSelectionModel
    static func == (l: RWSelectableCard, r: RWSelectableCard) -> Bool { l.model === r.model }
    var content: some ElementGroup {
        VStack(spacing: 4) {
            Text("selected \(model.multi.sorted().map(String.init).joined(separator: ","))")
            ScrollView(.vertical) {
                List((0..<12).map(RWRow.init), selection: Binding(get: { model.multi }, set: { model.multi = $0 }),
                     rowHeight: Pixels(20)) { r in Text("Row \(r.id)") }
            }
            .frame(width: Pixels(180), height: Pixels(120))
        }
    }
}

/// **Test 8** (`RW-I`): click a row, shift-click another, command-click a third, then write the binding from code; each step's scene,
/// accessibility tree and state table equal the twin's and the retaining side replays between the steps (a differential that
/// replays nothing proves nothing). **Mutation:** the replayed ledger's key handler capturing a stale `data`/binding — not
/// reachable without editing the ledger; the instrument is the observed-read miss: `RetainedLedger`'s observed-read check removed
/// leaves the selection line stale.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aSelectionChangeInsideARetainedListMisses() throws {
    let onModel = RWSelectionModel(), offModel = RWSelectionModel()
    let size = Size(width: Pixels(260), height: Pixels(220))
    let on = try TestWindow(size: size, textSystem: harnessTextSystem) { VStack(spacing: 0) { RWSelectableCard(model: onModel).equatable() } }
    let off = try TestWindow(size: size, textSystem: harnessTextSystem) { VStack(spacing: 0) { RWSelectableCard(model: offModel).equatable() } }
    off.window.testingRetainedSubtrees = false
    for w in [on, off] { for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() } }
    on.resetFrameWork()
    var replays = 0
    func step(_ name: String, _ input: (TestWindow) throws -> Void) throws {
        for w in [on, off] { try input(w) }
        for w in [on, off] { w.window.setNeedsRedraw(); w.tick() }
        let d = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(d.isEmpty, "after \(name): \(d)")
        #expect(on.window.testingStateEntries == off.window.testingStateEntries, "state after \(name)")
        #expect(onModel.multi == offModel.multi, "selection after \(name)")
    }
    func idle() throws {
        for w in [on, off] { w.window.setNeedsRedraw(); w.tick() }
        if on.lastFrameWork.retainedHits > 0 { replays += 1 }
        let d = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(d.isEmpty, "idle: \(d)")
    }
    try idle(); try idle()
    try step("click") { w in try w.click(try element(w, "Row 2")) }
    #expect(onModel.multi == [2])
    try idle(); try idle()
    try step("shift-click") { w in try w.click(try element(w, "Row 4"), modifierFlags: .shift) }
    #expect(onModel.multi == [2, 3, 4])
    try idle(); try idle()
    try step("command-click") { w in try w.click(try element(w, "Row 5"), modifierFlags: .command) }
    try idle(); try idle()
    try step("written from code") { w in
        let m = (w === on) ? onModel : offModel
        m.multi = [0, 11]
    }
    #expect(onModel.multi == [0, 11])
    try idle(); try idle()
    // The card replays while nothing is focused (the first two idles); a click focuses the selectable list, and a focused
    // list is under `SB-X` (the card runs, correctly, for the rest of the run).
    #expect(replays >= 2, "the card replays before the click focuses its list: \(replays)")
}

// MARK: Test 10 — a picker anchor survives a replay

/// **Test 10** (`RW-K`): the top bar's `Picker` and `Menu` record a presentation anchor every frame, closed. After orbit frames
/// that replay the bar, and again after a window resize, the window's anchors equal a fresh window's; opening the picker
/// afterwards draws the same frame. **Red before:** the top bar was prepaint-ineligible (`presentationAnchor`).
/// **Mutation:** the ledger's anchors dropped (`replayPrepaintLedger`'s `anchors` loop) — the window has no anchor for the
/// picker after a replayed frame and the comparison differs.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aPickerOpensFromAReplayedAnchorWhereAFreshWindowOpensIt() throws {
    var twin = try PanelTwin()
    twin.orbit(); twin.orbit()
    let f = try #require(twin.frames.last)
    #expect(f.retainedPrepaintHits >= 1 && f.retainedPrepaintIneligible == 0, "the bar replays its prepaint: \(f.retainedPrepaintHits)/\(f.retainedPrepaintIneligible)")
    let anchors = twin.on.window.window.testingPresentationAnchors
    #expect(!anchors.isEmpty, "the closed Picker and Menu recorded anchors")
    #expect(anchors == twin.off.window.window.testingPresentationAnchors)
    for w in [twin.on.window, twin.off.window] { w.resize(to: Size(width: Pixels(1500), height: Pixels(920))) }
    twin.orbit(); twin.orbit()
    #expect(twin.on.window.window.testingPresentationAnchors == twin.off.window.window.testingPresentationAnchors, "after the resize")
    #expect(twin.on.window.window.testingPresentationAnchors != anchors, "the resize moved them: a replay of the old ones would be wrong")
    try twin.compare("resized")
    twin.orbit()
    #expect((twin.frames.last?.retainedPrepaintHits ?? 0) >= 1, "and the bar replays again")
    try twin.act { w in
        let picker = try w.elements(role: .button).first { $0.label == "Mode" } ?? w.element(label: "Mode")
        try w.click(picker)
    }
    try twin.compare("picker opened")
}

// MARK: Test 11 — a scripted session equals a fresh window at every frame

/// **Test 11** (`RW-B`..`RW-K`): orbit, wheel, click and type in the field, drag a slider, toggle, resize and orbit again;
/// every frame's scene, accessibility tree, hitboxes, Tab order, element bounds and state entries equal a retention-off
/// window's, and the retaining side replayed between the inputs. The instrument for every mutation of the lane.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aScriptedSessionOnThePanelsArmEqualsAFreshWindowEveryFrame() throws {
    var twin = try PanelTwin()
    var hits = 0
    func orbits(_ n: Int, _ step: String) throws {
        for i in 0..<n {
            twin.orbit()
            if twin.graphPanelReplays { hits += 1 }
            try twin.compare("\(step) \(i)")
        }
    }
    try orbits(3, "orbit")
    try twin.act { [p = twin.listPoint] w in w.scroll(at: p, byDeltaX: 0, deltaY: -120) }
    try twin.compare("wheel")
    try twin.leavePointer()
    try orbits(2, "orbit after the wheel")
    twin.advance(2)
    try orbits(2, "orbit after the fade")
    try twin.act { w in try w.typeText("xy", into: try w.elements(role: .textField)[0]) }
    try twin.compare("typed")
    try orbits(2, "orbit while focused")
    try twin.focusTheInspector()
    try twin.compare("left")
    try twin.leavePointer()
    try orbits(2, "orbit after leaving")
    try twin.act { w in
        let slider = try w.elements(role: .slider)[0]
        let start = Point(x: slider.visibleFrame.origin.x + slider.visibleFrame.size.width * 0.3,
                          y: slider.visibleFrame.origin.y + slider.visibleFrame.size.height / 2)
        let end = Point(x: slider.visibleFrame.origin.x + slider.visibleFrame.size.width * 0.8, y: start.y)
        w.drag(from: start, to: end)
    }
    try twin.compare("slider drag")
    try twin.leavePointer()
    try orbits(2, "orbit after the slider")
    try twin.act { w in try w.click(try w.elements(role: .checkBox)[0]) }
    try twin.compare("toggle")
    try twin.leavePointer()
    try orbits(2, "orbit after the toggle")
    for w in [twin.on.window, twin.off.window] { w.resize(to: Size(width: Pixels(1500), height: Pixels(920))) }
    try orbits(3, "orbit after the resize")
    #expect(hits >= 8, "the retaining window replayed the panels between the inputs: \(hits) frames")
}

// MARK: Test 14 — every state write site is classified

/// **Test 14** (`RW-C`): every `withState(` call in `Sources/MetalUI` is spelled plain, with `unchanged:` or as a `readState`,
/// and the count per file equals the table below (spec §2), so a new framework site must choose one of the three. The first
/// number is the plain `withState`s, the second the compared ones, the third the `readState`s. Comment lines and the declarations in
/// `Passes.swift`/`StateTable.swift` are not call sites. **Mutation:** a plain `withState(` added to any file (or a conversion
/// reverted) moves that file's row.
@Test func everyStateWriteSiteIsClassified() throws {
    let expected: [String: (plain: Int, compared: Int, reads: Int)] = [
        "AnimatedColor.swift": (2, 0, 0), "AnimatedStyle.swift": (2, 0, 0), "FocusState.swift": (1, 0, 0),
        "Frame.swift": (5, 0, 0), "LazyCore.swift": (0, 1, 0), "List.swift": (3, 2, 0), "ProposalScrollView.swift": (0, 0, 1),
        "ScrollChrome.swift": (0, 1, 2), "ScrollView.swift": (0, 0, 1), "TestingHooks.swift": (1, 0, 0),
        "TextEditor.swift": (1, 1, 2), "TextField.swift": (1, 1, 2), "Window.swift": (5, 0, 0),
    ]
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/MetalUI")
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }.sorted()
    try #require(names.contains("StateTable.swift"), "the scan found the sources at \(dir.path)")
    var found: [String: (plain: Int, compared: Int, reads: Int)] = [:]
    for name in names where name != "Passes.swift" && name != "StateTable.swift" {
        let lines = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var row = (plain: 0, compared: 0, reads: 0)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if line.contains("withState(") && !line.contains("func withState") {
                let statement = lines[index..<min(index + 3, lines.count)].joined(separator: " ")
                if statement.contains("unchanged:") { row.compared += 1 } else { row.plain += 1 }
            }
            if line.contains("readState(") && !line.contains("func readState") { row.reads += 1 }
        }
        if row != (0, 0, 0) { found[name] = row }
    }
    #expect(Set(found.keys) == Set(expected.keys), "files with a state access: \(found.keys.sorted())")
    for (name, want) in expected.sorted(by: { $0.key < $1.key }) {
        let got = found[name] ?? (0, 0, 0)
        #expect(got == want, "\(name): plain/compared/reads \(got) != \(want)")
    }
}
