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
        Text("n\(model.n)").frame(width: Pixels(60), height: Pixels(14))
            .background(model.n % 2 == 0 ? Color.accent : Color.red)
    }
}

private struct RSObservedParent: Component, @MainActor Equatable {
    let model: RSModel
    var content: some ElementGroup {
        VStack(spacing: 0) { RSObservedChild(model: model) }
    }
    static func == (l: RSObservedParent, r: RSObservedParent) -> Bool { true }
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
@MainActor private func rsRoot(_ model: RSModel) -> some Element {
    VStack(spacing: 6) {
        HStack(spacing: 6) {
            RSCard(title: "A", shade: model.n % 3).equatable()
            ZStack { RSCard(title: "B", shade: 1).equatable() }.offset(x: Pixels(3))
            ZStack { RSCard(title: "C", shade: 2).equatable() }.shadow(radius: Pixels(4))
            ZStack { RSCard(title: "D", shade: 0).equatable() }.rotationEffect(.degrees(4))
        }
        HStack(spacing: 6) {
            RSHolder().equatable()
            RSObservedParent(model: model).equatable()
            RSInspector().equatable()
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
    var hits = 0, misses = 0, ineligible = 0

    init(size: Size<Pixels> = sz(420, 200), scale: Float = 1, colorScheme: ColorScheme = .light) throws {
        let onModel = self.onModel, offModel = self.offModel
        on = try TestWindow(size: size, colorScheme: colorScheme, scaleFactor: scale, textSystem: harnessTextSystem) {
            rsRoot(onModel)
        }
        off = try TestWindow(size: size, colorScheme: colorScheme, scaleFactor: scale, textSystem: harnessTextSystem) {
            rsRoot(offModel)
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
    let pair = try RSPair()
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
        ("the pointer leaving", { pair.on.exitPointer(); pair.off.exitPointer() }),
        ("a click on card A's button", {
            pair.on.click(at: try centre(pair.on, "go A")); pair.off.click(at: try centre(pair.off, "go A")) }),
        ("a Tab to the first focus stop", { pair.on.typeKey(.tab); pair.off.typeKey(.tab) }),
        ("a Tab to the second", { pair.on.typeKey(.tab); pair.off.typeKey(.tab) }),
        ("a click on the holder's counter", {
            pair.on.click(at: try centre(pair.on, "count 0")); pair.off.click(at: try centre(pair.off, "count 0")) }),
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
        await Task.yield()
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
/// A focused subtree is **ineligible** rather than a miss: the focused element's `$focus` retention
/// write is a state write a record cannot replay (`SB-J`). Mutation: the pointer test forced false
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
    _ = window.send(.mouseUp(MouseEvent(position: c)))
    window.exitPointer()
    _ = rsFrame(window)
    f = rsFrame(window)
    #expect(f.retainedHits == 4, "released and away: all replay")
    // Focus: Tab to the first stop.
    window.typeKey(.tab)
    f = window.lastFrameWork
    #expect(f.retainedIneligible == 1 && f.retainedHits == 3, "focus is in the first card: \(f.retainedHits)/\(f.retainedIneligible)")
    f = rsFrame(window)
    #expect(f.retainedIneligible == 1 && f.retainedHits == 3, "and stays there")
    window.typeKey(.tab)
    f = rsFrame(window)
    #expect(f.retainedIneligible == 1 && f.retainedHits == 3, "focus moved to the second card: still exactly one")
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
    await Task.yield()
    window.window.setNeedsRedraw(); window.tick()
    _ = try window.element(label: "n5")
    #expect(window.lastFrameWork.retainedHits == 0, "the write's frame replays nothing")
    var hit = false
    for _ in 0..<3 { hit = hit || rsFrame(window).retainedHits == 1 }
    #expect(hit, "and the new frame is recorded and replays")
}

// MARK: 1.5 — a channel outside the replayable set makes the subtree ineligible

private enum RSChannelKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    fileprivate var rsChannel: Int {
        get { self[RSChannelKey.self] }
        set { self[RSChannelKey.self] = newValue }
    }
}

enum RSChannel: String, CaseIterable, CustomTestStringConvertible {
    case scrollRegion, surface, geometryChange, activeAnimation, customEnvironmentKey, stateWrite
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
        case .geometryChange:
            Text("geometry").frame(width: Pixels(60), height: Pixels(14))
                .onGeometryChange(for: Double.self, of: { Double($0.size.width.value) }) { _ in }
        case .activeAnimation:
            Box().frame(width: Pixels(40), height: Pixels(10)).background(.accent)
                .opacity(flag.on ? 1 : 0.2)
                .animation(.linear(duration: 1), value: flag.on)
        case .customEnvironmentKey:
            Text("custom").frame(width: Pixels(60), height: Pixels(14))
        case .stateWrite:
            TextField("t", text: $text).frame(width: Pixels(80), height: Pixels(24))
        }
    }
    static func == (l: RSChannelProbe, r: RSChannelProbe) -> Bool { l.channel == r.channel }
}

/// 1.5 — one arm per ledger channel: the occurrence registers or writes something a record cannot
/// replay, so it runs as today, is counted `retainedIneligible` and is tried again (`SB-J`). Each arm
/// first shows a plain neighbour of the same window replaying, so "ineligible" is not "nothing replays".
/// Mutation, per arm: the channel removed from the ledger comparison or its taint call — the arm's
/// occurrence is recorded (`retainedMisses == 1`) and, but for the scene, nothing else notices.
@Test(arguments: RSChannel.allCases) @MainActor func everyLedgerChannelMakesTheSubtreeIneligible(channel: RSChannel) throws {
    let flag = RSFlag()
    let window = try TestWindow(size: sz(300, 120), textSystem: harnessTextSystem) {
        VStack(spacing: 4) {
            RSCard(title: "plain", shade: 1).equatable()
            if channel == .customEnvironmentKey {
                RSChannelProbe(channel: channel, flag: flag).equatable().environment(\.rsChannel, 3)
            } else {
                RSChannelProbe(channel: channel, flag: flag).equatable()
            }
        }
    }
    if channel == .activeAnimation { flag.on = true }
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    let f = rsFrame(window)
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
