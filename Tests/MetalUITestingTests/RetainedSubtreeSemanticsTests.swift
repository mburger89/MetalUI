import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Observation
import Testing

// C14b lane 1 (`SB-D`…`SB-M`): what a retained subtree must not change, through real windows.
// Every test here draws two windows from one builder, one with replay and one without
// (`Window.testingRetainedSubtrees`), and compares what the frame hands the platform. Counts,
// never time. Tests 1.2, 1.4, 1.6, 1.8, 1.9, 1.10 and 1.15 of the design spec.

@Observable @MainActor final class RSModel {
    var n = 0
    var tint = 0
}

/// Whether the run is under `METALUI_VERIFY_RETAINED=1`: a hit is painted as a miss (nested occurrences included), so a
/// test that reads replayed or skipped counts is switched off there; the differentials keep running (record §109 §6).
let rsVerifying = ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1"

/// Lets the observation hop of a platform without a synchronous `onChange` land before the next explicit
/// draw (`HT-I`; on Linux a main-actor test does not run on the main thread, so every change takes one hop).
@MainActor func rsSettle() async {
    for _ in 0..<4 { await Task.yield() }
}

// MARK: The tree

/// A card: text, a button (a hitbox, a focus stop and an accessibility record) and a bar, in a clipped
/// rounded surface. Equatable on its inputs.
private struct RSCard: Component, @MainActor Equatable {
    let title: String
    let shade: Int
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text(title).frame(width: Pixels(80), height: Pixels(14))
            Button("go \(title)") {}.frame(width: Pixels(50), height: Pixels(18))
            Box().frame(width: Pixels(Float(20 + shade * 4)), height: Pixels(8)).background(.accent)
                .opacity(shade % 2 == 0 ? 1 : 0.6)
        }
        .padding(Edges(all: Pixels(4)))
        .background(Color.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: Pixels(6)))
        .clipShape(RoundedRectangle(cornerRadius: Pixels(6)))
    }
}

/// A non-equatable child with `@State`, inside an equatable parent (`SB-K`).
private struct RSCounter: Component {
    @State var count = 0
    var content: some ElementGroup {
        Button("count \(count)") { count += 1 }.frame(width: Pixels(70), height: Pixels(20))
            .background(count % 2 == 0 ? Color.accent : Color.red)
    }
}

private struct RSHolder: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text("holder").frame(width: Pixels(70), height: Pixels(14))
            RSCounter()
        }
    }
    static func == (l: RSHolder, r: RSHolder) -> Bool { true }
}

/// A child that reads `@Observable` state in its own getter, inside a parent that is always `==` (`SB-D`).
private struct RSObservedChild: Component {
    let model: RSModel
    var content: some ElementGroup {
        // Text only: a colour that changes with `n` would write the element's `$anim-color` slot and
        // invalidate the record through the bind journal, hiding the observation window under test.
        Text("n\(model.n)").frame(width: Pixels(60), height: Pixels(14))
    }
}

private struct RSObservedParent: Component, @MainActor Equatable {
    let model: RSModel
    var content: some ElementGroup {
        VStack(spacing: 0) { RSObservedChild(model: model) }
    }
    static func == (l: RSObservedParent, r: RSObservedParent) -> Bool { true }
}

/// A hover region (a tally the record must replay): the log records the window's hover events.
private struct RSHoverCard: Component, @MainActor Equatable {
    let log: HarnessLog
    var content: some ElementGroup {
        Text("hover me").frame(width: Pixels(70), height: Pixels(20)).onHover { [log] inside in
            log.add(inside ? "in" : "out")
        }
    }
    static func == (l: RSHoverCard, r: RSHoverCard) -> Bool { l.log === r.log }
}

/// Sliders, a toggle, a material (a backdrop primitive) and a button: the inspector of the fixture, small.
private struct RSInspector: Component, @MainActor Equatable {
    @State var on = true
    @State var a = 0.3
    var content: some ElementGroup {
        VStack(spacing: 4) {
            Text("inspector").frame(width: Pixels(90), height: Pixels(14))
            Slider(value: $a, in: 0...1).frame(width: Pixels(90), height: Pixels(18))
            Toggle("on", isOn: $on)
            Button("apply") {}.frame(width: Pixels(60), height: Pixels(18))
        }
        .padding(Edges(all: Pixels(6)))
        .background(.regularMaterial)
    }
    static func == (l: RSInspector, r: RSInspector) -> Bool { true }
}

/// The differential's tree: cards under outer effects (an offset, a shadow, a rotation), a stateful holder,
/// an observed reader, an inspector with a backdrop.
@MainActor private func rsRoot(_ model: RSModel, _ log: HarnessLog) -> some Element {
    VStack(spacing: 6) {
        HStack(spacing: 6) {
            RSCard(title: "A", shade: model.n % 3).equatable()
            ZStack { RSCard(title: "B", shade: 1).equatable() }.offset(x: Pixels(3))
            ZStack { RSCard(title: "C", shade: 2).equatable() }.shadow(radius: Pixels(4))
            ZStack { RSCard(title: "D", shade: 0).equatable() }.rotationEffect(.degrees(4))
            // A composite scope outside holds the card's leaves until the group closes: no final-primitive shortcut (`SB-AB`).
            ZStack { RSCard(title: "H", shade: 1).equatable() }.compositingGroup().shadow(radius: Pixels(3))
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    RSCard(title: "E", shade: 2).equatable()
                    RSCard(title: "F", shade: 1).equatable()
                    RSCard(title: "G", shade: 0).equatable()
                }
            }.frame(width: Pixels(100), height: Pixels(70))
        }
        HStack(spacing: 6) {
            RSHolder().equatable()
            RSObservedParent(model: model).equatable()
            RSInspector().equatable()
            RSHoverCard(log: log).equatable()
        }
    }
}

// MARK: The pair

@MainActor private final class RSSnapshot {
    let rects: Data, glyphs: Data, images: Data
    let counts: [Int]
    let tree: AccessibilityTree
    let hitboxes: [String]
    let tabOrder: [GlobalElementID]
    let bounds: [GlobalElementID: Bounds<Pixels>]

    init(_ window: TestWindow) throws {
        func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
        rects = bytes(window.scene.rects); glyphs = bytes(window.scene.glyphs); images = bytes(window.scene.images)
        counts = [window.scene.rects.count, window.scene.glyphs.count, window.scene.images.count]
        tree = try window.accessibilityTree
        hitboxes = window.window.testingHitboxes.map { "\($0.id)|\($0.bounds)|\($0.layer)|\($0.opaque)" }
        tabOrder = window.window.testingTabOrder
        bounds = window.window.testingElementBounds
    }

    func differences(from other: RSSnapshot) -> [String] {
        var out: [String] = []
        if rects != other.rects { out.append("rects") }
        if glyphs != other.glyphs { out.append("glyphs") }
        if images != other.images { out.append("images") }
        if counts != other.counts { out.append("counts \(counts) vs \(other.counts)") }
        if tree != other.tree { out.append("accessibility tree") }
        if hitboxes != other.hitboxes { out.append("hitboxes") }
        if tabOrder != other.tabOrder { out.append("tab order") }
        if bounds != other.bounds { out.append("element bounds") }
        return out
    }
}

/// Two windows over one builder: `on` replays, `off` does not.
@MainActor private final class RSPair {
    let on: TestWindow, off: TestWindow
    let onModel = RSModel(), offModel = RSModel()
    let onLog = HarnessLog(), offLog = HarnessLog()
    var hits = 0, misses = 0, ineligible = 0

    init(size: Size<Pixels> = sz(420, 200), scale: Float = 1, colorScheme: ColorScheme = .light) throws {
        let onModel = self.onModel, offModel = self.offModel, onLog = self.onLog, offLog = self.offLog
        on = try TestWindow(size: size, colorScheme: colorScheme, scaleFactor: scale, textSystem: harnessTextSystem) {
            rsRoot(onModel, onLog)
        }
        off = try TestWindow(size: size, colorScheme: colorScheme, scaleFactor: scale, textSystem: harnessTextSystem) {
            rsRoot(offModel, offLog)
        }
        off.window.testingRetainedSubtrees = false
        redraw(); redraw()
    }

    func redraw() {
        for w in [on, off] { w.window.setNeedsRedraw(); w.tick() }
        let f = on.lastFrameWork
        hits += f.retainedHits; misses += f.retainedMisses; ineligible += f.retainedIneligible
    }

    func compare(_ step: String) throws {
        let differences = try RSSnapshot(on).differences(from: RSSnapshot(off))
        #expect(differences.isEmpty, "after \(step): \(differences)")
        #expect(onLog.entries == offLog.entries, "hover events after \(step): \(onLog.entries) vs \(offLog.entries)")
        #expect(off.lastFrameWork.retainedHits == 0)
    }
}

// MARK: 1.2 — the differential

/// 1.2 — a retained frame equals a fresh frame (`SB-M` item 2): the same tree with and without replay,
/// over a script that moves every kind of key component: a model write, a hover entering and leaving a
/// card's button, a press, a Tab to a focus stop, a click on a descendant's `@State` button, a quiet
/// frame, a resize, an appearance switch, a scale change. After every frame the scene (rect, glyph and
/// image arrays byte for byte), the accessibility tree, the hitbox list, the Tab order and the element
/// bounds are equal. The retained side must have hit, or the test proves nothing. Mutation: any one
/// component dropped from the key (1.3 names them); a replay appended at the end of the frame (1.15).
@Test @MainActor func aRetainedFrameEqualsAFreshFrameOverAScript() async throws {
    let pair = try RSPair(size: sz(640, 200))
    try pair.compare("the first frames")
    func centre(_ w: TestWindow, _ label: String) throws -> Point<Pixels> {
        let f = try w.element(label: label).frame
        return pt(f.origin.x.value + f.size.width.value / 2, f.origin.y.value + f.size.height.value / 2)
    }
    let script: [(String, () throws -> Void)] = [
        ("a quiet frame", {}),
        ("a model write", { pair.onModel.n += 1; pair.offModel.n += 1 }),
        ("a hover over card B's button", {
            pair.on.hover(at: try centre(pair.on, "go B")); pair.off.hover(at: try centre(pair.off, "go B")) }),
        ("a quiet frame under the pointer", {}),
        ("the pointer over the hover card", {
            pair.on.hover(at: try centre(pair.on, "hover me")); pair.off.hover(at: try centre(pair.off, "hover me")) }),
        ("the pointer off the hover card", {
            pair.on.hover(at: pt(2, 2)); pair.off.hover(at: pt(2, 2)) }),
        ("the pointer leaving", { pair.on.exitPointer(); pair.off.exitPointer() }),
        ("a click on card A's button", {
            pair.on.click(at: try centre(pair.on, "go A")); pair.off.click(at: try centre(pair.off, "go A")) }),
        ("a Tab to the first focus stop", { pair.on.typeKey(.tab); pair.off.typeKey(.tab) }),
        ("a Tab to the second", { pair.on.typeKey(.tab); pair.off.typeKey(.tab) }),
        ("a click on the holder's counter", {
            pair.on.click(at: try centre(pair.on, "count 0")); pair.off.click(at: try centre(pair.off, "count 0")) }),
        ("a scroll of the scroll view", {
            pair.on.scroll(at: try centre(pair.on, "go F"), byDeltaX: 0, deltaY: -25)
            pair.off.scroll(at: try centre(pair.off, "go F"), byDeltaX: 0, deltaY: -25) }),
        ("a second scroll", {
            pair.on.scroll(at: try centre(pair.on, "go F"), byDeltaX: 0, deltaY: -10)
            pair.off.scroll(at: try centre(pair.off, "go F"), byDeltaX: 0, deltaY: -10) }),
        ("a tint write (no reader)", { pair.onModel.tint += 1; pair.offModel.tint += 1 }),
        ("the observed child's model write", { pair.onModel.n += 1; pair.offModel.n += 1 }),
        ("a resize", { pair.on.resize(to: sz(380, 220)); pair.off.resize(to: sz(380, 220)) }),
        ("dark appearance", { pair.on.setAppearance(.dark); pair.off.setAppearance(.dark) }),
        ("a scale change", { pair.on.setScaleFactor(2); pair.off.setScaleFactor(2) }),
        ("light appearance", { pair.on.setAppearance(.light); pair.off.setAppearance(.light) }),
        ("a quiet frame at the end", {}),
    ]
    for (name, step) in script {
        try step()
        await rsSettle()
        pair.redraw()
        try pair.compare(name)
    }
    #expect(pair.hits > 0, "the retained side replayed nothing: the differential would prove nothing")
}

// MARK: 1.4 — pointer, press and focus

/// A window of the four cards only, each with a button.
@MainActor private func rsCards() throws -> TestWindow {
    let window = try TestWindow(size: sz(420, 120), textSystem: harnessTextSystem) {
        HStack(spacing: 6) {
            RSCard(title: "A", shade: 0).equatable()
            RSCard(title: "B", shade: 1).equatable()
            RSCard(title: "C", shade: 2).equatable()
            RSCard(title: "D", shade: 3).equatable()
        }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    return window
}

@MainActor private func rsFrame(_ window: TestWindow) -> FrameWork {
    window.window.setNeedsRedraw(); window.tick()
    return window.lastFrameWork
}

@MainActor private func rsCentre(_ window: TestWindow, _ label: String) throws -> Point<Pixels> {
    let f = try window.element(label: label).frame
    return pt(f.origin.x.value + f.size.width.value / 2, f.origin.y.value + f.size.height.value / 2)
}

/// 1.4 — a subtree the pointer is inside, a press is on or focus is in re-paints, and the three others
/// replay; once the pointer has left it, it re-records once and replays again (`SB-F` item 4). The
/// harness draws a frame for each action, so the action's own frame is read with `lastFrameWork`.
/// The pointer, press and focus rules are exact (`SB-F` item 4, `SB-AA`): the hovered, pressed or focused
/// element must be the occurrence or under it. Mutation: the pointer test forced false
/// (the hovered card replays a stale frame and 1.2 reddens with it); forced true (a quiet frame misses).
@Test @MainActor func aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays() throws {
    let window = try rsCards()
    let quiet = rsFrame(window)
    #expect(quiet.retainedHits == 4 && quiet.retainedMisses == 0 && quiet.retainedIneligible == 0)
    // Pointer: card B's button.
    window.hover(at: try rsCentre(window, "go B"))
    var f = window.lastFrameWork
    #expect(f.retainedHits == 3 && f.retainedMisses == 1, "the pointer is inside card B: \(f.retainedHits)/\(f.retainedMisses)")
    f = rsFrame(window)
    #expect(f.retainedHits == 3 && f.retainedMisses == 1, "and stays a miss while it is inside")
    window.exitPointer()
    f = window.lastFrameWork
    #expect(f.retainedHits == 3 && f.retainedMisses == 1, "the frame it leaves in repaints once")
    f = rsFrame(window)
    #expect(f.retainedHits == 4 && f.retainedMisses == 0, "and then replays")
    // Press: card C's button, held.
    let c = try rsCentre(window, "go C")
    _ = window.send(.mouseDown(MouseEvent(position: c)))
    f = rsFrame(window)
    #expect(f.retainedMisses == 1 && f.retainedHits == 3, "a press is on card C")
    // The pointer leaves while the button is held: the press alone keeps card C re-painting.
    _ = window.send(.mouseDragged(MouseEvent(position: pt(4, 110))))
    _ = rsFrame(window)   // a miss records an incomplete record (`SB-V`): one more frame before a hit could happen
    f = rsFrame(window)
    #expect(f.retainedMisses == 1 && f.retainedHits == 3, "the press holds card C with the pointer away: \(f.retainedHits)/\(f.retainedMisses)")
    _ = window.send(.mouseUp(MouseEvent(position: c)))
    window.exitPointer()
    _ = rsFrame(window)
    f = rsFrame(window)
    #expect(f.retainedHits == 4, "released and away: all replay")
    // Focus: Tab to the first stop.
    window.typeKey(.tab)
    f = window.lastFrameWork
    #expect(f.retainedMisses == 1 && f.retainedHits == 3, "focus is in the first card: \(f.retainedHits)/\(f.retainedMisses)")
    f = rsFrame(window)
    #expect(f.retainedMisses == 1 && f.retainedHits == 3, "and stays there")
    window.typeKey(.tab)
    f = rsFrame(window)
    #expect(f.retainedMisses == 1 && f.retainedHits == 3, "focus moved to the second card: still exactly one")
    let first = try window.element(label: "go A")
    #expect(!first.isFocused, "and the first card, no longer focused, replays")
}

// MARK: 1.6 — a descendant's @State beats the record

/// 1.6 — a non-equatable counter inside an always-equal parent: the click changes the counter's colour;
/// the retained frame shows it (`SB-K`). The parent's record is invalid when a bound slot's version
/// moved, so the click's frame is a miss and the next quiet frame a hit. Mutation: the bind journal's
/// version compare skipped — the click's frame replays the old colour and `count 1` is missing.
@Test @MainActor func aDescendantStateChangeInvalidatesTheRecord() throws {
    let window = try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { RSHolder().equatable() }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(rsFrame(window).retainedHits == 1)
    func bytes() -> Data { window.scene.rects.withUnsafeBytes { Data($0) } }
    let before = bytes()
    try window.click(window.element(label: "count 0"))
    _ = try window.element(label: "count 1")
    #expect(bytes() != before, "the button's background changed with the count")
    // The click changes the button's background (a colour snap writes the element's `$anim-color` slot, which
    // a record cannot replay, `SB-J`): the occurrence is ineligible on the frame that shows it, records on
    // the next and replays from the third. The pointer is still inside the button, so it also misses.
    #expect(window.lastFrameWork.retainedHits == 0, "the click's frame replays nothing")
    window.exitPointer()
    #expect(window.lastFrameWork.retainedMisses == 1, "the frame the pointer leaves in records the new frame")
    #expect(rsFrame(window).retainedHits == 1, "and the next quiet frame replays it")
    _ = try window.element(label: "count 1")
}

/// A non-equatable child whose `@State` shows only in a label (no colour, so no `$anim-color` write) and
/// changes from a keyboard shortcut: no pointer, press or focus is inside the holder.
private struct RSShortcutCounter: Component {
    @State var count = 0
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text("tally \(count)").frame(width: Pixels(70), height: Pixels(14))
            Button("bump") { count += 1 }.keyboardShortcut("j").frame(width: Pixels(40), height: Pixels(14))
        }
    }
}

private struct RSShortcutHolder: Component, @MainActor Equatable {
    var content: some ElementGroup { VStack(spacing: 0) { RSShortcutCounter() } }
    static func == (l: RSShortcutHolder, r: RSShortcutHolder) -> Bool { true }
}

/// 1.6b — the bind journal's versions alone (`SB-K`): a descendant's `@State` changes from a shortcut while
/// the pointer, a press and focus are elsewhere, nothing is observed and no state is written in paint, so
/// the only thing that moved is the version of a slot bound under the holder. Mutation: the versions
/// compare in `retainedPaintDecision` made `true` — the old label is replayed.
@Test @MainActor func aDescendantStateChangeFromAShortcutInvalidatesTheRecordByVersion() throws {
    func make(_ on: Bool) throws -> TestWindow {
        let w = try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
            VStack(spacing: 0) { RSShortcutHolder().equatable() }
        }
        w.window.testingRetainedSubtrees = on
        for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
        return w
    }
    let on = try make(true), off = try make(false)
    func glyphs(_ w: TestWindow) -> Data { w.scene.glyphs.withUnsafeBytes { Data($0) } }
    try #require(rsFrame(on).retainedHits == 1)
    for w in [on, off] { w.typeKey("j", modifierFlags: [.primary]) }
    _ = try on.element(label: "tally 1")
    #expect(on.lastFrameWork.retainedHits == 0, "the shortcut's frame replays nothing")
    #expect(glyphs(on) == glyphs(off), "and draws the new label")
}

// MARK: 1.8 — a child's observed read beats its parent's record

/// 1.8 — the child's getter reads `model.n`; the parent is `==` and its getter is skipped; the
/// parent's record must still die (`SB-D` item 4): the build window's session covers the child's
/// getter. Mutation: the build session dropped (`finishComponent` run outside `run`) — the new text
/// is not drawn.
@Test @MainActor func aChildGetterReadInvalidatesItsEquatableParentsRecord() async throws {
    let model = RSModel()
    let window = try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { RSObservedParent(model: model).equatable() }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(rsFrame(window).retainedHits == 1)
    _ = try window.element(label: "n0")
    model.n = 5
    await rsSettle()
    window.window.setNeedsRedraw(); window.tick()
    _ = try window.element(label: "n5")
    #expect(window.lastFrameWork.retainedHits == 0, "the write's frame replays nothing")
    var hit = false
    for _ in 0..<3 { hit = hit || rsFrame(window).retainedHits == 1 }
    #expect(hit, "and the new frame is recorded and replays")
    // A second change is seen too (the sequence 1.8c pins frame by frame).
    model.n = 9
    await rsSettle()
    window.window.setNeedsRedraw(); window.tick()
    _ = try window.element(label: "n9")
    #expect(window.lastFrameWork.retainedHits == 0, "the second write's frame replays nothing")
}

/// 1.8c — the frame right after a miss is a hit (`DM-C`, moved from 0 hits by lane 2 of C14-j: the change frame opened its windows, so its
/// record is complete) and **a second write after that hit is still seen** (the sessions that record armed fire). Mutations:
/// `needsObservation` without the certain-miss terms (the frame after the miss is no hit: red); `coverageComplete` left out of the hit
/// test, or the change frame's coverage declared with its windows closed — the second write replays stale (red).
@Test @MainActor func aFrameRightAfterAMissObservesAgainSoASecondWriteIsSeen() async throws {
    let model = RSModel()
    let window = try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { RSObservedParent(model: model).equatable() }
    }
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    model.n = 5
    await rsSettle()
    window.window.setNeedsRedraw(); window.tick()      // the miss: its windows are open, so the record is complete
    window.window.setNeedsRedraw(); window.tick()      // hits
    #expect(window.lastFrameWork.retainedHits == 1, "the frame after a miss is a hit (DM-C)")
    model.n = 9
    await rsSettle()
    window.window.setNeedsRedraw(); window.tick()
    _ = try window.element(label: "n9")
    #expect(window.lastFrameWork.retainedHits == 0)
}

// MARK: 1.8b — a skipped descendant's later change beats the ancestor's record

/// An equatable leaf that reads one of the model's counters and is always `==`, inside an equatable
/// parent that is always `==`.
private struct RSMemoLeaf: Component, @MainActor Equatable {
    let model: RSModel
    let second: Bool
    var content: some ElementGroup {
        Text(second ? "t\(model.tint)" : "m\(model.n)").frame(width: Pixels(60), height: Pixels(14))
    }
    static func == (l: RSMemoLeaf, r: RSMemoLeaf) -> Bool { true }
}

private struct RSMemoParent: Component, @MainActor Equatable {
    let model: RSModel
    var content: some ElementGroup {
        VStack(spacing: 0) {
            RSMemoLeaf(model: model, second: false).equatable()
            RSMemoLeaf(model: model, second: true).equatable()
        }
    }
    static func == (l: RSMemoParent, r: RSMemoParent) -> Bool { true }
}

/// 1.8b (`SB-AC`) — the first leaf changes, so the parent records again in a frame where the second leaf's
/// content is skipped by the content memo: the parent's windows never subscribed to the second leaf's read.
/// The second leaf then changes: its own memo re-evaluates it, and the parent must not replay the old text.
/// Found by `METALUI_VERIFY_RETAINED=1` over `anEqualComponentSkipsItsContent`. Mutation: the
/// `evaluationsSoFar` comparison in `EquatableComponent.requestGroupLayout` removed — the stale text is drawn.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the paint-skipped counts this test pins are not its to read")) @MainActor func aSkippedDescendantsLaterChangeInvalidatesItsAncestorsRecord() async throws {
    let onModel = RSModel(), offModel = RSModel()
    let on = try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { RSMemoParent(model: onModel).equatable() }
    }
    let off = try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { RSMemoParent(model: offModel).equatable() }
    }
    off.window.testingRetainedSubtrees = false
    func draw(_ times: Int) {
        for _ in 0..<times { for w in [on, off] { w.window.setNeedsRedraw(); w.tick() } }
    }
    func glyphs(_ w: TestWindow) -> Data { w.scene.glyphs.withUnsafeBytes { Data($0) } }
    draw(4)
    onModel.n = 3; offModel.n = 3
    await rsSettle()
    draw(4)
    #expect(glyphs(on) == glyphs(off))
    #expect(on.lastFrameWork.retainedHits == 1, "the parent replays again; the second leaf was skipped when it was recorded")
    onModel.tint = 7; offModel.tint = 7
    await rsSettle()
    draw(1)
    #expect(glyphs(on) == glyphs(off), "the second leaf's new text is drawn, not the recorded one")
}

// MARK: 1.5 — a channel outside the replayable set makes the subtree ineligible

/// A function-holding value: **uncomparable**, so a key of it keeps an occurrence ineligible (`EE-B`, `EE-F`; an Int
/// key no longer does: its value compares).
struct RSChannelValue { var channel: () -> Int }
private enum RSChannelKey: EnvironmentKey { static var defaultValue: RSChannelValue { RSChannelValue(channel: { 0 }) } }
extension EnvironmentValues {
    fileprivate var rsChannel: RSChannelValue {
        get { self[RSChannelKey.self] }
        set { self[RSChannelKey.self] = newValue }
    }
}

enum RSChannel: String, CaseIterable, CustomTestStringConvertible {
    case scrollRegion, surface, activeAnimation, spinner, customEnvironmentKey, stateWrite, popover
    var testDescription: String { rawValue }
}

@Observable @MainActor final class RSFlag { var on = false }

private struct RSChannelProbe: Component, @MainActor Equatable {
    let channel: RSChannel
    let flag: RSFlag
    @State var text = ""
    var content: some ElementGroup {
        switch channel {
        case .scrollRegion:
            ScrollView(.vertical) { Text("scrolled").frame(width: Pixels(60), height: Pixels(14)) }
                .frame(width: Pixels(80), height: Pixels(30))
        case .surface:
            GPUSurface(redraw: .onDemand, value: 0) { _ in }.frame(width: Pixels(40), height: Pixels(30))
        case .activeAnimation:
            Box().frame(width: Pixels(40), height: Pixels(10)).background(.accent)
                .opacity(flag.on ? 1 : 0.2)
                .animation(.linear(duration: 1), value: flag.on)
        case .spinner:
            // An indeterminate spinner notes a live animation from paint, not from the build.
            ProgressView().frame(width: Pixels(24), height: Pixels(24))
        case .customEnvironmentKey:
            Text("custom").frame(width: Pixels(60), height: Pixels(14))
        case .stateWrite:
            PlainWriteLeaf().frame(width: Pixels(80), height: Pixels(24))
        case .popover:
            Text("anchor").frame(width: Pixels(60), height: Pixels(20))
                .popover(isPresented: Binding(get: { true }, set: { _ in })) { Text("popover") }
        }
    }
    static func == (l: RSChannelProbe, r: RSChannelProbe) -> Bool { l.channel == r.channel }
}

/// 1.5 — one arm per ledger channel: the occurrence's paint writes or raises something a record cannot
/// replay, so it paints as today, is counted `retainedIneligible` and is tried again (`SB-J`). Each arm
/// first shows a plain neighbour of the same window replaying, so "ineligible" is not "nothing replays".
/// Mutation, per arm: the channel removed from the ledger comparison or its taint call — the arm's
/// occurrence is recorded (`retainedMisses == 1`) and, but for the scene, nothing else notices.
@Test(arguments: RSChannel.allCases) @MainActor func everyLedgerChannelMakesTheSubtreeIneligible(channel: RSChannel) async throws {
    let flag = RSFlag()
    let window = try TestWindow(size: sz(300, 120), textSystem: harnessTextSystem) {
        VStack(spacing: 4) {
            RSCard(title: "plain", shade: 1).equatable()
            if channel == .customEnvironmentKey {
                RSChannelProbe(channel: channel, flag: flag).equatable().environment(\.rsChannel, RSChannelValue(channel: { 3 }))
            } else {
                RSChannelProbe(channel: channel, flag: flag).equatable()
            }
        }
    }
    if channel == .activeAnimation { flag.on = true; await rsSettle() }
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    let f = rsFrame(window)
    if channel == .scrollRegion {   // read-only scroll state since `RW-H`: the scroller replays like its neighbour
        #expect(f.retainedHits == 2 && f.retainedIneligible == 0 && f.retainedMisses == 0, "both replay: \(f.retainedHits)/\(f.retainedIneligible)/\(f.retainedMisses)")
        return
    }
    #expect(f.retainedHits == 1, "the plain neighbour replays: \(f.retainedHits)")
    #expect(f.retainedIneligible == 1, "the \(channel.rawValue) occurrence is ineligible: \(f.retainedIneligible)")
    #expect(f.retainedMisses == 0)
}

// MARK: 1.10 — animation

private struct RSAnimated: Component, @MainActor Equatable {
    let flag: RSFlag
    var content: some ElementGroup {
        Box().frame(width: Pixels(40), height: Pixels(10)).background(.accent)
            .opacity(flag.on ? 1 : 0.2)
            .animation(.linear(duration: 1), value: flag.on)
    }
    static func == (l: RSAnimated, r: RSAnimated) -> Bool { true }
}

private struct RSIdleKeyframes: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Text("shake").frame(width: Pixels(60), height: Pixels(14))
            .keyframeAnimator(initialValue: 0.0, trigger: 0) { content, x in
                content.offset(x: Pixels(Float(x)))
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(4, duration: 0.05)
                    LinearKeyframe(0, duration: 0.05)
                }
            }
    }
    static func == (l: RSIdleKeyframes, r: RSIdleKeyframes) -> Bool { true }
}

/// 1.10 — a live animation never replays, and an idle keyframe animator does (`SB-J`, spec §6 item 4).
/// The flag flips under a view `==` always says is unchanged and whose `.animation(value:)` reads it
/// from a model (`flag` is a class: the value does not carry it). While the opacity is interpolating the
/// occurrence is time-varying (`timeVaryingNotes` in its build) and every frame is ineligible or a miss
/// without a record; when it settles the record is made once and the next frame hits.
/// Mutation: `hasActiveAnimations`/`timeVaryingNotes` left out of the build window — a replay during the
/// animation freezes the opacity at its first frame; the differential in 1.2 does not animate.
@Test @MainActor func aLiveAnimationNeverReplaysAndAnIdleKeyframeSubtreeDoes() async throws {
    let flag = RSFlag()
    let window = try TestWindow(size: sz(200, 80), textSystem: harnessTextSystem) {
        VStack(spacing: 4) {
            RSAnimated(flag: flag).equatable()
            RSIdleKeyframes().equatable()
        }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    var f = rsFrame(window)
    #expect(f.retainedHits == 2, "idle: both replay (the keyframe animator is idle): \(f.retainedHits)")
    flag.on = true
    await rsSettle()
    window.window.setNeedsRedraw()
    var opacities: [Float] = []
    for _ in 0..<6 {
        window.tick()
        opacities.append(window.scene.rects.last?.background.a ?? 0)
        f = window.lastFrameWork
        window.advance(by: 0.15)
        window.window.setNeedsRedraw()
    }
    #expect(Set(opacities).count > 3, "the opacity moves every frame while animating: \(opacities)")
    window.advance(by: 2)
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    f = rsFrame(window)
    #expect(f.retainedHits == 2, "settled: both replay again: \(f.retainedHits)/\(f.retainedMisses)/\(f.retainedIneligible)")
}

// MARK: 1.10c — a transition in flight inside a subtree

private struct RSTransitioning: Component, @MainActor Equatable {
    let model: RSModel
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text("base").frame(width: Pixels(60), height: Pixels(14))
            if model.n % 2 == 1 { Text("shown").frame(width: Pixels(60), height: Pixels(14)).transition(.opacity) }
        }
    }
    static func == (l: RSTransitioning, r: RSTransitioning) -> Bool { true }
}

/// 1.10c — an element with a `.transition` pushes a capturing paint scope inside the occurrence every frame it is
/// present, running or not: the occurrence is ineligible while the transition runs (time is noted too) **and after it
/// settles**, when the capturing scope is the only reason (`SB-J`, spec §6 item 3; a conservative refusal, carried to
/// lane 2 with the finer scopes). Mutation: the capturing-scope taint in `processScopes` removed — the settled frames
/// are recorded and replay (`hits == 1`).
@Test @MainActor func aSubtreeHoldingATransitionIsIneligibleInFlightAndSettled() async throws {
    let model = RSModel()
    let window = try TestWindow(size: sz(200, 80), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { RSTransitioning(model: model).equatable() }
    }
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    try #require(rsFrame(window).retainedHits == 1)
    withAnimation(.linear(duration: 1)) { model.n = 1 }
    await rsSettle()
    for _ in 0..<4 {
        window.window.setNeedsRedraw(); window.tick()
        let f = window.lastFrameWork
        #expect(f.retainedHits == 0 && f.retainedMisses == 0, "no replay and no record while the transition runs")
        window.advance(by: 0.1)
    }
    window.advance(by: 2)
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    let f = rsFrame(window)
    #expect(f.retainedHits == 0 && f.retainedIneligible == 1, "settled, the transition's own scope still refuses: \(f.retainedHits)/\(f.retainedMisses)/\(f.retainedIneligible)")
}

// MARK: 1.10b — a replay keeps the animation store's entries alive

/// A legacy box whose border colour follows `tint` under `.animation(value:)`, always `==`.
private struct RSTinted: Component, @MainActor Equatable {
    let model: RSModel
    var content: some ElementGroup {
        Box().border(model.tint == 0 ? Color.black : Color.white, width: Pixels(2))
            .frame(width: Pixels(40), height: Pixels(10))
            .animation(.linear(duration: 1), value: model.tint)
    }
    static func == (l: RSTinted, r: RSTinted) -> Bool { true }
}

/// 1.10b (`SB-I`) — a legacy border's colour track (`$anim-border`) lives in the window's `AnimationStore` and is swept when a
/// frame does not touch it. A replayed frame paints nothing, so the record replays the touch; without it a
/// subtree settled for a few frames loses its entry, and the next change snaps instead of animating.
/// Mutation: the recorded touches not replayed — the flip is at its target after 0.3 s.
@Test @MainActor func aReplayKeepsTheAnimationStoresEntriesSoTheNextChangeAnimates() async throws {
    let model = RSModel()
    let window = try TestWindow(size: sz(200, 60), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { RSTinted(model: model).equatable() }
    }
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    var f = rsFrame(window)
    try #require(f.retainedHits == 1, "settled and replaying")
    for _ in 0..<6 { window.window.setNeedsRedraw(); window.tick() }
    let start = window.scene.rects.last?.borderColor.l ?? -1
    model.tint = 1
    await rsSettle()
    window.window.setNeedsRedraw(); window.tick()
    window.advance(by: 0.3)
    window.window.setNeedsRedraw(); window.tick()
    f = window.lastFrameWork
    let c = window.scene.rects.last?.borderColor
    let now = c?.l ?? -1
    #expect(now > start + 0.05 && now < 0.95, "mid-animation after 0.3 s, not snapped: lightness \(now) from \(start)")
}

// MARK: 1.3 — every key component separates

enum RSKeyArm: String, CaseIterable, CustomTestStringConvertible {
    // Geometry (spec §4.1).
    case topRect, flexRect
    // Ambient context at paint (spec §4.2, `SB-AA`).
    case clip, opacity, shadow, blur, rotation, offsetEffect, scroll, foreground, font, disabled
    // The whole window.
    case colorScheme, scaleFactor, contentSize
    var testDescription: String { rawValue }
    /// Arms that move the control's context too (the whole window, or a padding that shifts its neighbour).
    var isGlobal: Bool { self == .colorScheme || self == .scaleFactor || self == .contentSize || self == .topRect }
    /// Arms whose action draws the frame that shows the reaction (the window's own events).
    var actsOnTheWindow: Bool { self == .colorScheme || self == .scaleFactor || self == .contentSize || self == .scroll }
}

/// A component of one painting node that takes its proposal: its top rect moves alone, there is no interior.
private struct RSFlex: Component, @MainActor Equatable {
    var content: some ElementGroup { Box().background(.accent) }
}

/// The probe card under one arm's modifier, `flip` toggling the one input the arm changes.
@MainActor @ElementBuilder
private func rsProbe(_ arm: RSKeyArm, flip: Bool) -> some ElementGroup {
    switch arm {
    case .topRect:
        ZStack { RSCard(title: "P", shade: 1).equatable() }.padding(Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(0), left: Pixels(flip ? 6 : 0)))
    case .flexRect:
        // The single node takes the proposal's width: its rect moves, nothing else in the subtree does.
        RSFlex().equatable().frame(width: Pixels(flip ? 120 : 100), height: Pixels(20))
    case .clip:
        ZStack { RSCard(title: "P", shade: 1).equatable() }.clipShape(RoundedRectangle(cornerRadius: Pixels(flip ? 3 : 9)))
    case .opacity:
        ZStack { RSCard(title: "P", shade: 1).equatable() }.opacity(flip ? 0.5 : 0.9)
    case .shadow:
        ZStack { RSCard(title: "P", shade: 1).equatable() }.shadow(radius: Pixels(flip ? 3 : 5))
    case .blur:
        ZStack { RSCard(title: "P", shade: 1).equatable() }.blur(radius: Pixels(flip ? 1 : 2))
    case .rotation:
        ZStack { RSCard(title: "P", shade: 1).equatable() }.rotationEffect(.degrees(flip ? 3 : 5))
    case .offsetEffect:
        ZStack { RSCard(title: "P", shade: 1).equatable() }.offset(x: Pixels(flip ? 1 : 2))
    case .scroll:
        // The card keeps its rect in the content; scrolling moves only the paint offset (`activeOffset`).
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                RSCard(title: "P", shade: 1).equatable()
                Box().frame(width: Pixels(60), height: Pixels(400))
            }
        }.frame(width: Pixels(120), height: Pixels(100))
    case .foreground:
        RSCard(title: "P", shade: 1).equatable().foregroundColor(flip ? Color.red : Color.blue)
    case .font:
        RSCard(title: "P", shade: 1).equatable().font(Font.system(size: flip ? 12 : 14))
    case .disabled:
        RSCard(title: "P", shade: 1).equatable().disabled(flip)
    case .colorScheme, .scaleFactor, .contentSize:
        RSCard(title: "P", shade: 1).equatable()
    }
}

@MainActor private func rsKeyWindow(arm: RSKeyArm, model: RSModel, retained: Bool) throws -> TestWindow {
    let window = try TestWindow(size: sz(300, 160), textSystem: harnessTextSystem) {
        HStack(spacing: 6) {
            RSCard(title: "Q", shade: 2).equatable()
            rsProbe(arm, flip: model.n % 2 == 1)
        }
    }
    window.window.testingRetainedSubtrees = retained
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    return window
}

/// 1.3 — **each component of the replay key has a separating arm** (`SB-F`; the offset effect's translation is
/// since `RK-S` the exception, which replays translated — its arm reads the translated hit instead): between two frames exactly one
/// input moves (a modifier outside the probe card, or the window), and the probe misses (a global arm
/// makes the control miss too) while the retained scene, hitbox list and accessibility tree equal an
/// unretained window's. Mutation: that component made constant in `retainedAmbientKey()` / `retainedKey`
/// — the probe replays the old frame, and the scene (or the miss count) differs. Recorded per arm in §109.
/// The `scroll` arm is the paint offset's: the card keeps its rect in the content, only `activeOffset` moves.
@Test(arguments: RSKeyArm.allCases) @MainActor func everyKeyComponentSeparates(arm: RSKeyArm) async throws {
    let onModel = RSModel(), offModel = RSModel()
    let on = try rsKeyWindow(arm: arm, model: onModel, retained: true)
    let off = try rsKeyWindow(arm: arm, model: offModel, retained: false)
    func apply() {
        switch arm {
        case .colorScheme: on.setAppearance(.dark); off.setAppearance(.dark)
        case .scaleFactor: on.setScaleFactor(2); off.setScaleFactor(2)
        case .contentSize: on.resize(to: sz(280, 150)); off.resize(to: sz(280, 150))
        case .scroll:
            // Below the card, on the filler: the pointer is not in the probe.
            let at = pt(230, 125)
            on.scroll(at: at, byDeltaX: 0, deltaY: -12); off.scroll(at: at, byDeltaX: 0, deltaY: -12)
        default: onModel.n += 1; offModel.n += 1
        }
    }
    let quiet = rsFrame(on); _ = rsFrame(off)
    #expect(quiet.retainedHits == 2, "both cards replay while nothing moves: \(quiet.retainedHits)")
    apply()
    await rsSettle()
    // A window event draws its own frame (the reaction); a model write waits for the next tick.
    if !arm.actsOnTheWindow { on.window.setNeedsRedraw(); on.tick(); off.window.setNeedsRedraw(); off.tick() }
    let f = on.lastFrameWork
    let reaction = f.retainedMisses + f.retainedIneligible
    #expect(f.retainedHits + reaction == 2)
    if arm == .offsetEffect || arm == .rotation {
        // `RK-S`: the translation of an outer effect no longer separates; the probe replays at its new place (translated) and
        // the scene equals the fresh one (the differential below). Since C14-i (`RZ-B`) the same holds for an affine change of
        // the effect, a rotation from 5 to 3 degrees here: the live scopes are entered with the new map.
        if !rsVerifying { #expect(reaction == 0 && f.retainedTranslated == 1, "\(arm.rawValue): hits \(f.retainedHits) translated \(f.retainedTranslated)") }
    } else if arm == .topRect || arm == .flexRect {
        // `FS-D` (C14-d): an occurrence that only **moved** (neither its size nor its subtree changed) replays translated, so the
        // neighbour of a padding or of a resized sibling no longer misses; these two arms used to read that miss as the
        // reaction. The probe of `flexRect` is a zero-size node that stays at the middle of its frame, so it hits unmoved.
        // Size is still a key component: the separating arm is `aShiftThatAlsoResizesTheOccurrenceMisses`.
        if !rsVerifying {
            let moved = arm == .topRect ? 2 : 1
            #expect(reaction == 0 && f.retainedTranslated == moved, "\(arm.rawValue): hits \(f.retainedHits) translated \(f.retainedTranslated) misses \(f.retainedMisses)")
        }
    } else {
        #expect(reaction >= (arm.isGlobal ? 2 : 1), "\(arm.rawValue): hits \(f.retainedHits) misses \(f.retainedMisses) ineligible \(f.retainedIneligible)")
        if !arm.isGlobal { #expect(f.retainedHits >= 1, "the control card still replays") }
    }
    let differences = try RSSnapshot(on).differences(from: RSSnapshot(off))
    #expect(differences.isEmpty, "\(arm.rawValue): \(differences)")
}

// MARK: 1.13 — rasters, 1.14 — backdrops and outer scopes

private struct RSWire: Component, @MainActor Equatable {
    let seed: Int
    var content: some ElementGroup {
        RSWireShape(a: Float(seed))
            .stroke(Color.accent, lineWidth: Pixels(2))
            .frame(width: Pixels(80), height: Pixels(40))
    }
}

private struct RSWireShape: Shape, Equatable {
    var a: Float
    func path(in rect: Bounds<Pixels>) -> Path {
        var p = Path()
        p.move(to: Point(x: Pixels(2), y: Pixels(2)))
        p.addCurve(to: Point(x: Pixels(76), y: Pixels(36)), control1: Point(x: Pixels(30 + a), y: Pixels(2)),
                   control2: Point(x: Pixels(40), y: Pixels(36)))
        return p
    }
}

/// 1.13 — a replayed path keeps its raster: the same `ImageTexture` for the next frame, nothing
/// rasterized and no new texture (`SB-I`; the replay goes through `insertIntoScene`, which looks the raster
/// up and so touches it, `GX-K`). Mutation: the path ops dropped from the replay — the scene loses its image.
@Test @MainActor func aReplayTouchesItsRastersSoTheyAreNotDropped() throws {
    let window = try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { RSWire(seed: 3).equatable() }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let images = window.scene.images.count
    try #require(images >= 1, "the stroke is an image")
    window.resetFrameWork()
    for _ in 0..<6 { window.window.setNeedsRedraw(); window.tick() }
    let w = window.frameWork
    let sum = w.dropFirst().reduce(w[0], +)
    #expect(sum.retainedHits == 6)
    #expect(sum.rasterizedPixels == 0 && sum.newTextures == 0, "no raster redone, no texture made")
    #expect(sum.images == 6 * images)
}

private struct RSLogCard: Component, @MainActor Equatable {
    let title: String
    let log: HarnessLog
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Button("\(title)") { [log, title] in log.add(title) }.frame(width: Pixels(80), height: Pixels(40))
        }
    }
    static func == (l: RSLogCard, r: RSLogCard) -> Bool { l.title == r.title && l.log === r.log }
}

/// 1.15 — registration order is a fresh frame's: two overlapping cards, the later above the earlier; the
/// retained window and the unretained one agree on the hitbox list and on who a click in the overlap
/// reaches (the later one), after the cards have replayed. Mutation: a replay that appends at the end of
/// the frame (`replayPrepaint` called from the window instead of the group) swaps the order.
@Test @MainActor func aReplayedHitboxKeepsTheRankingAtAnOverlap() throws {
    func make(retained: Bool, log: HarnessLog) throws -> TestWindow {
        let w = try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
            ZStack(alignment: .topLeading) {
                RSLogCard(title: "A", log: log).equatable()
                ZStack(alignment: .topLeading) { RSLogCard(title: "B", log: log).equatable() }.offset(x: Pixels(30), y: Pixels(0))
            }
        }
        w.window.testingRetainedSubtrees = retained
        for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
        return w
    }
    let onLog = HarnessLog(), offLog = HarnessLog()
    let on = try make(retained: true, log: onLog), off = try make(retained: false, log: offLog)
    on.window.setNeedsRedraw(); on.tick()
    #expect(on.lastFrameWork.retainedHits == 2)
    #expect(try RSSnapshot(on).differences(from: RSSnapshot(off)).isEmpty)
    // The overlap: from B's left edge to A's right edge (the root is centred, so ask for the frames).
    let a = try on.element(label: "A").frame, b = try on.elements(role: .button).map(\.frame).max { $0.origin.x.value < $1.origin.x.value }!
    let inOverlap = pt(b.origin.x.value + 10, a.origin.y.value + 10)
    let onlyA = pt(a.origin.x.value + 5, a.origin.y.value + 10)
    on.click(at: inOverlap); off.click(at: inOverlap)
    #expect(onLog.entries == offLog.entries && onLog.entries == ["B"], "\(onLog.entries) vs \(offLog.entries)")
    on.click(at: onlyA); off.click(at: onlyA)
    #expect(onLog.entries == offLog.entries && onLog.entries == ["B", "A"])
}

/// 1.14 — a backdrop inside a replayed subtree and a replay inside an outer shadow are byte for byte a fresh
/// frame's (`SB-D`, `BB-H`): the inspector's material and a shadowed card, compared with the same tree
/// unretained after the frames in which they replay. Mutation: `emit` bypassed in the replay with
/// `scene.insert` — the shadowed card loses its shadow image.
@Test @MainActor func aBackdropInsideAReplayedSubtreeIsByteIdentical() throws {
    func make(retained: Bool) throws -> TestWindow {
        let w = try TestWindow(size: sz(300, 200), textSystem: harnessTextSystem) {
            HStack(spacing: 8) {
                RSInspector().equatable()
                ZStack { RSCard(title: "S", shade: 1).equatable() }.shadow(radius: Pixels(5))
            }
        }
        w.window.testingRetainedSubtrees = retained
        for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
        return w
    }
    let on = try make(retained: true), off = try make(retained: false)
    on.window.setNeedsRedraw(); on.tick()
    #expect(on.lastFrameWork.retainedHits >= 1, "something replayed: \(on.lastFrameWork.retainedHits)")
    func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
    #expect(bytes(on.scene.backdrops) == bytes(off.scene.backdrops))
    #expect(!on.scene.backdrops.isEmpty, "the material drew a backdrop")
    #expect(try RSSnapshot(on).differences(from: RSSnapshot(off)).isEmpty)
    #expect(on.scene.images.count == off.scene.images.count && on.scene.images.count >= 1, "the card's shadow is an image")
}

// MARK: 1.16 — the cost of a miss

/// 1.16 — a miss pays the old work plus two ledger snapshots (before and after its paint) and nothing else a
/// counter sees; a hit takes none. Mutation: a snapshot taken per element — the count reads far above 2
/// per occurrence.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the paint-skipped counts this test pins are not its to read")) @MainActor func aMissCostsTheOldWorkPlusTwoSnapshots() throws {
    func make(retained: Bool) throws -> TestWindow {
        let w = try TestWindow(size: sz(420, 120), textSystem: harnessTextSystem, content: {
            HStack(spacing: 6) {
                RSCard(title: "A", shade: 0).equatable()
                RSCard(title: "B", shade: 1).equatable()
                RSCard(title: "C", shade: 2).equatable()
            }
        })
        w.window.testingRetainedSubtrees = retained
        return w
    }
    // Set the switch before the first frame is drawn is not possible through the initializer; compare the
    // first recorded frame of each window, which the switch (set right after open) leaves a record-only frame.
    let on = try make(retained: true), off = try make(retained: false)
    let history = on.frameWork
    let totals = history.dropFirst().reduce(history[0], +)
    let recorded = totals.retainedMisses + totals.retainedIneligible
    #expect(recorded >= 3)
    #expect(totals.retainedLedgerSnapshots == 2 * recorded, "\(totals.retainedLedgerSnapshots) snapshots for \(recorded) recorded occurrences")
    // A hit takes none.
    on.window.setNeedsRedraw(); on.tick(); on.window.setNeedsRedraw(); on.tick()
    #expect(on.lastFrameWork.retainedHits == 3 && on.lastFrameWork.retainedLedgerSnapshots == 0)
    _ = off
}
