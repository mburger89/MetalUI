import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIShaderTypes
@testable import MetalUI

// Plan task 9, lane 2: scoped environment values
// (`docs/superpowers/specs/2026-09-15-environment-design.md`, tests E1–E21;
// rulings `EV-A`…`EV-C`, `EV-G`…`EV-M`, `EV-O`, `EV-P`, `EV-U`, `EV-V`).
//
// **This file imports `Metal`, so it must declare no `Dimension`-typed
// fixture** (`Fakes.swift`'s note on `AnimationTests.swift`): Foundation's
// `Dimension` is ambiguous against `MetalUICore.Dimension`. Styles here are
// written with `.length(.pixels(_:))`, which never spells the type.
//
// **Every recorder is a reference type**, as `ClickLog` is
// (`InputDispatchTests.swift`): element values do not survive a frame, so a
// reading stored on the struct would be lost with it.
//
// The mutations run against each test, and the tests each one reddened, are
// recorded under the ruling it cites in the decisions doc and in
// `docs/record/11-environment.md`.

// MARK: - Fixtures

private struct ProbeKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// The fixture key every test below writes and reads.
    fileprivate var probe: Int {
        get { self[ProbeKey.self] }
        set { self[ProbeKey.self] = newValue }
    }
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func fixedStyle(_ width: Float, _ height: Float) -> Style {
    var style = Style()
    style.size = Size(width: .length(.pixels(px(width))), height: .length(.pixels(px(height))))
    return style
}

/// Whole `EnvironmentValues` snapshots per label per phase, and the id each
/// labelled element was visited under.
@MainActor
private final class EnvLog {
    var layout: [String: EnvironmentValues] = [:]
    var prepaint: [String: EnvironmentValues] = [:]
    var paint: [String: EnvironmentValues] = [:]
    var ids: [String: GlobalElementID] = [:]

    func probes(_ label: String) -> [Int?] {
        [layout[label]?.probe, prepaint[label]?.probe, paint[label]?.probe]
    }
}

/// A legacy leaf that reads `pass.environment` in all three phases.
private struct EnvRecorder: Element {
    let label: String
    let log: EnvLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.layout[label] = pass.environment
        return (pass.requestNode(style: fixedStyle(10, 10), children: []), ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.prepaint[label] = pass.environment
        log.ids[label] = id
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.paint[label] = pass.environment
    }
}

/// A proposal leaf that reads `pass.environment.probe` in all three phases.
private struct NativeEnvRecorder: Element {
    let label: String
    let log: EnvLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.layout[label] = pass.environment
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.prepaint[label] = pass.environment
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.paint[label] = pass.environment
    }
}

extension NativeEnvRecorder: ProposalElementGroup {}

/// `@Environment` readings, appended in visit order per phase.
@MainActor
private final class PropertyLog {
    var layout: [Int] = []
    var prepaint: [Int] = []
    var paint: [Int] = []
    func reset() { layout = []; prepaint = []; paint = [] }
}

/// A leaf that reads `@Environment(\.probe)` in all three phases and never
/// touches `pass.environment`, so the only snapshots it causes are its binds.
private struct PropertyRecorder: Element {
    @Environment(\.probe) var probe
    let log: PropertyLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.layout.append(probe)
        return (pass.requestNode(style: fixedStyle(1, 1), children: []), ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.prepaint.append(probe)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.paint.append(probe)
    }
}

@MainActor
private final class NodeLog {
    var nodes: [String: LayoutNodeID] = [:]
}

/// Forwards every phase to `inner` and records the node it registered.
private struct NodeProbe<Inner: Element>: Element {
    var inner: Inner
    let label: String
    let log: NodeLog

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Inner.LayoutState) {
        let (node, state) = inner.requestLayout(id, pass: &pass)
        log.nodes[label] = node
        return (node, state)
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Inner.LayoutState,
                           pass: inout PrepaintPass) -> Inner.PrepaintState {
        inner.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Inner.LayoutState, prepaint: inout Inner.PrepaintState,
                        pass: inout PaintPass) {
        inner.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

@MainActor
private func surfaceBox(_ width: Float) -> Box<EmptyGroup> {
    Box().width(px(width)).height(px(10)).background(.surface)
}

private func hsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }

@MainActor
private func frame(_ width: Float = 200, _ height: Float = 50, scale: Float = 1,
                   theme: Theme = .light, table: StateTable = StateTable()) -> Frame {
    Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: scale,
          stateTable: table, theme: theme)
}

// MARK: - E1–E3: precedence and phases (EV-A, EV-L)

/// **E1.** The nearest writer wins and a scope ends with its subtree — probe
/// arms A0–A6 of `docs/probes/swiftui-environment-scoping.swift`, which read
/// `[0, 1, 2, 1, 2, 1, 0]` in SwiftUI. Read in paint.
@MainActor
@Test func theNearestWriterWinsAndAScopeEndsWithItsSubtree() {
    let log = EnvLog()
    var root = Row {
        EnvRecorder(label: "A0", log: log)
        EnvRecorder(label: "A1", log: log).environment(\.probe, 1)
        EnvRecorder(label: "A2", log: log).environment(\.probe, 2).environment(\.probe, 1)
        Pair(Pair(EnvRecorder(label: "A3", log: log),
                  EnvRecorder(label: "A4", log: log).environment(\.probe, 2)),
             EnvRecorder(label: "A5", log: log))
            .environment(\.probe, 1)
        EnvRecorder(label: "A6", log: log)
    }
    frame().render(&root)

    let readings = ["A0", "A1", "A2", "A3", "A4", "A5", "A6"].map { log.paint[$0]?.probe }
    #expect(readings == [0, 1, 2, 1, 2, 1, 0])
}

/// **E2.** A transform composes with what it inherits (probe A7: `+10` inside
/// `+100` reads 110), and a plain write below a transform replaces it (A8: 5).
@MainActor
@Test func aTransformComposesWithTheInheritedValueAndAWriteBelowItReplacesIt() {
    let log = EnvLog()
    var root = Row {
        EnvRecorder(label: "A7", log: log)
            .transformEnvironment(\.probe) { $0 += 10 }
            .transformEnvironment(\.probe) { $0 += 100 }
        EnvRecorder(label: "A8", log: log)
            .environment(\.probe, 5)
            .transformEnvironment(\.probe) { $0 += 100 }
    }
    frame().render(&root)

    #expect([log.paint["A7"]?.probe, log.paint["A8"]?.probe] == [110, 5])
}

/// **E3.** One scope answers identically in layout, prepaint and paint
/// (ruling EV-L) — so a scope that skipped its push in one phase reddens one
/// slot of one triple.
@MainActor
@Test func anEnvironmentValueReadsIdenticallyInAllThreePhases() {
    let log = EnvLog()
    var root = Row {
        Pair(EnvRecorder(label: "inner", log: log).environment(\.probe, 2),
             EnvRecorder(label: "sibling", log: log))
            .environment(\.probe, 1)
        EnvRecorder(label: "outside", log: log)
    }
    frame().render(&root)

    #expect(log.probes("inner") == [2, 2, 2])
    #expect(log.probes("sibling") == [1, 1, 1])
    #expect(log.probes("outside") == [0, 0, 0])
}

// MARK: - E4, E5, E10: transparency (EV-B)

/// **E4.** A scope contributes no layout node and consumes no cursor index:
/// the row still has three children, and both a scoped element and the
/// sibling after the scope keep the ids they have without it.
@MainActor
@Test func anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex() throws {
    let scopedLog = EnvLog()
    let scopedNodes = NodeLog()
    var scoped = NodeProbe(inner: Row {
        Pair(EnvRecorder(label: "A", log: scopedLog), EnvRecorder(label: "B", log: scopedLog))
            .environment(\.probe, 1)
        EnvRecorder(label: "C", log: scopedLog)
    }, label: "row", log: scopedNodes)
    let scopedFrame = frame()
    scopedFrame.render(&scoped)

    let bareLog = EnvLog()
    let bareNodes = NodeLog()
    var bare = NodeProbe(inner: Row {
        Pair(EnvRecorder(label: "A", log: bareLog), EnvRecorder(label: "B", log: bareLog))
        EnvRecorder(label: "C", log: bareLog)
    }, label: "row", log: bareNodes)
    frame().render(&bare)

    let row = try #require(scopedNodes.nodes["row"])
    #expect(scopedFrame.tree.children(row).count == 3)
    for label in ["A", "B", "C"] {
        let scopedID = try #require(scopedLog.ids[label])
        let bareID = try #require(bareLog.ids[label])
        #expect(scopedID == bareID, "\(label)'s id moved under the scope")
    }
}

@MainActor
private final class CounterLog {
    var readings: [Int] = []
}

/// An `onClick` leaf whose `@State` counts its clicks, and records the count
/// in paint.
private struct ClickCounter: Element {
    @State var n = 0
    let log: CounterLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNode(style: fixedStyle(20, 20), children: []), ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        let state = _n
        var handlers = Handlers()
        handlers.onClick = { state.wrappedValue += 1 }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.readings.append(n)
    }
}

@MainActor
private final class EnvModel {
    var value = 0
}

@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

/// **E5.** Changing a scope's value keeps the `@State` below it — probe D1,
/// where SwiftUI's counter reads 5 → 6 → 7 across a value change.
///
/// **Passes on arrival for this arm, stated and accepted**: before the
/// mechanism exists there is nothing that could lose state. It exists for its
/// mutation — a value-keyed `EitherGroup` writer resets `n`. Lane 3 adds a
/// `.disabled(model.flag)` arm to this same test (spec D10).
@MainActor
@Test func changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let model = EnvModel()
    let log = CounterLog()
    let (window, platform) = try makeFakeWindow(device: device) {
        Row { ClickCounter(log: log).environment(\.probe, model.value) }
    }
    let centre = Point(x: px(10), y: px(32))

    window.drawFrameIfNeeded()
    click(platform, at: centre)
    window.drawFrameIfNeeded()
    click(platform, at: centre)
    window.drawFrameIfNeeded()
    try #require(log.readings.last == 2, "the control: two clicks count 2")

    model.value = 7
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(log.readings.last == 2, "a changed environment value reset the state below it")
}

/// A component whose own `@State` counts materializations of its content.
private struct CountingComponent: Component {
    @State var count = 0
    var content: some ElementGroup {
        count += 1
        return EmptyGroup()
    }
}

/// **E10.** Wrapping a component in a scope keeps its identity and state — the
/// `addingAModifierDoesNotResetAComponentsState` shape, one modifier over.
@MainActor
@Test func anEnvironmentScopeOverAComponentKeepsItsIdentityAndState() {
    let table = StateTable()
    var bare = Box(content: CountingComponent())
    frame(100, 100, table: table).render(&bare)
    frame(100, 100, table: table).render(&bare)

    var scoped = Box(content: CountingComponent().environment(\.probe, 1))
    frame(100, 100, table: table).render(&scoped)

    #expect(scoped.content.content.count == 3,
            "a scope must not reset the component's @State; got \(scoped.content.content.count)")
}

// MARK: - E6–E9: @Environment binding (EV-M)

/// **E6.** An `@Environment` property is bound to the nearest scope in every
/// phase and re-read each frame. The same element VALUE is reused across both
/// frames, so a binder that kept an old snapshot would be seen.
///
/// Its mutation (c) — deleting the re-bind in `paintGroup` — is expected to
/// stay green here: paint then reads the layout-phase snapshot, which cannot
/// differ within one frame. That is this instrument's limit; E7 covers it.
@MainActor
@Test func anEnvironmentPropertyIsBoundToTheNearestScopeInEveryPhaseAndRereadEachFrame() {
    let log = PropertyLog()
    let recorder = PropertyRecorder(log: log)

    var first = Row { recorder.environment(\.probe, 3) }
    frame().render(&first)
    #expect([log.layout, log.prepaint, log.paint] == [[3], [3], [3]])

    log.reset()
    var second = Row { recorder.environment(\.probe, 4) }
    frame().render(&second)
    #expect([log.layout, log.prepaint, log.paint] == [[4], [4], [4]])
}

/// **E7.** One element value placed twice under two scopes reads each scope in
/// paint — divergence 19's read half, for `@Environment`.
@MainActor
@Test func oneElementValuePlacedTwiceUnderTwoScopesReadsEachScopeInPaint() {
    let log = PropertyLog()
    let recorder = PropertyRecorder(log: log)
    var root = Row {
        recorder.environment(\.probe, 1)
        recorder.environment(\.probe, 2)
    }
    frame().render(&root)
    #expect(log.paint == [1, 2])
}

/// **E8. PINNED INERT ON PURPOSE** (ruling EV-M). An `@Environment` inside
/// `AnyElement` is never bound — `Mirror` cannot see through the box, as for
/// `@State` — so it reads the key's default, 0, under a scope writing 5.
///
/// **This is one case of the general rule: an `@Environment` that was never
/// bound returns the key's default silently**, with no diagnostic, and builds
/// a fresh `EnvironmentValues()` (reading `Locale.current`) on every access.
/// Legitimate unbound reads — a handler reading an erased element after the
/// frame, a value built outside any frame — look identical to a forgotten
/// bind, which is why no diagnostic was designed. It flips when `AnyElement`
/// binding lands (plan task 8).
@MainActor
@Test func anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault() {
    let log = PropertyLog()
    var root = Row { AnyElement(PropertyRecorder(log: log)).environment(\.probe, 5) }
    frame().render(&root)
    #expect([log.layout, log.prepaint, log.paint] == [[0], [0], [0]])
}

private struct EnvComponent: Component {
    @Environment(\.probe) var probe
    var content: some ElementGroup {
        Box().width(px(10)).height(px(10)).background(probe == 1 ? .accent : .surface)
    }
}

/// **E9.** A `Component` reads the nearest environment while building its
/// `content`, in layout.
@MainActor
@Test func aComponentReadsTheNearestEnvironmentInItsContent() throws {
    let scopedFrame = frame()
    var scoped = Row { EnvComponent().environment(\.probe, 1) }
    scopedFrame.render(&scoped)

    let bareFrame = frame()
    var bare = Row { EnvComponent() }
    bareFrame.render(&bare)

    let scopedRect = try #require(scopedFrame.finalizedScene().rects.first)
    let bareRect = try #require(bareFrame.finalizedScene().rects.first)
    try #require(Theme.light.accent != Theme.light.surface)
    #expect(hsla(scopedRect.background) == Theme.light.accent)
    #expect(hsla(bareRect.background) == Theme.light.surface)
}

// MARK: - E11: proposal content

/// **E11.** Proposal content reads the environment through a scope in every
/// phase — inside an `HStack` and inside a `ProposalScrollView`.
///
/// **All three slots, and the layout slot is the one a merge could break**
/// (ruling EV-W): when `ProposalElementGroup` gains
/// `requestProposalGroupLayout`, a bare forwarding implementation skips the
/// layout-phase push, and only the first slot of each triple sees it.
@MainActor
@Test func proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase() {
    let log = EnvLog()
    var stack = HStack {
        Rectangle(width: px(5), height: px(5))
        NativeEnvRecorder(label: "hstack", log: log).environment(\.probe, 7)
    }
    frame(100, 50).render(&stack)
    #expect(log.probes("hstack") == [7, 7, 7])

    var scroll = ProposalScrollView(.vertical) {
        NativeEnvRecorder(label: "scroll", log: log).environment(\.probe, 7)
    }
    frame(100, 50).render(&scroll)
    #expect(log.probes("scroll") == [7, 7, 7])
}

// MARK: - E12, E13, E18, E19: theme and root (EV-G, EV-H, EV-P, EV-U)

/// **E12.** A scoped theme repaints only its subtree, and a `Deferred` declared
/// inside a scope keeps it: a portal escapes clip, offset and layer, not scope
/// (probe F1).
@MainActor
@Test func aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope() throws {
    let f = frame()
    var root = Row {
        surfaceBox(10).theme(.dark)
        surfaceBox(11)
        Deferred { surfaceBox(12) }.theme(.dark)
    }
    f.render(&root)

    let rects = f.finalizedScene().rects
    func colour(_ width: Float) throws -> Hsla {
        hsla(try #require(rects.first { $0.bounds.size.width == width }).background)
    }
    try #require(Theme.dark.surface != Theme.light.surface)
    #expect(try colour(10) == Theme.dark.surface)
    #expect(try colour(11) == Theme.light.surface)
    #expect(try colour(12) == Theme.dark.surface)
}

/// **E13.** The frame's root environment carries its theme and scale, and an
/// in-module overwrite of the root is re-stamped (ruling EV-H).
///
/// The scale-2 arm is what discriminates: the fake surface is scale 1, where
/// `1 / scale` and `scale` agree.
@MainActor
@Test func theFramesRootEnvironmentCarriesItsThemeAndScale() throws {
    let log = EnvLog()
    let retina = frame(scale: 2, theme: .dark)
    var root = Row { surfaceBox(10); EnvRecorder(label: "px", log: log) }
    retina.render(&root)
    #expect(hsla(try #require(retina.finalizedScene().rects.first).background) == Theme.dark.surface)
    #expect(log.paint["px"]?.pixelLength == 0.5)

    let captureLog = EnvLog()
    var plain = Row { EnvRecorder(label: "px", log: captureLog) }
    frame(scale: 1).render(&plain)
    let captured = try #require(captureLog.paint["px"])
    #expect(captured.pixelLength == 1)

    let overwritten = frame(scale: 2, theme: .dark)
    overwritten.rootEnvironment = captured
    var again = Row { surfaceBox(10); EnvRecorder(label: "px", log: log) }
    overwritten.render(&again)
    #expect(hsla(try #require(overwritten.finalizedScene().rects.first).background) == Theme.dark.surface)
    #expect(log.paint["px"]?.pixelLength == 0.5)
}

private struct ToggleThemeFixture: Action {}

/// The BGRA bytes at the centre of a 64×64 fake surface.
@MainActor
private func centrePixel(_ platform: FakePlatformWindow) -> [UInt8] {
    let pixels = platform.fakeSurface.readPixels()
    let offset = (32 * 64 + 32) * 4
    return Array(pixels[offset..<offset + 4])
}

/// **E18.** The Space-key theme swap, through the fake platform, read back as
/// rendered pixels (ruling EV-P). The demo's wiring minus its executable
/// target: a `KeyBinding("space", …)` whose `onAction` flips `window.theme`.
///
/// **The two reference windows must disagree first** (shape 15): if light and
/// dark rendered the same centre pixel, `before == lightRef` and
/// `after == darkRef` would hold for a swap that never happened.
@MainActor
@Test func theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    func tree() -> Box<EmptyGroup> { Box().background(.background) }

    let (lightWindow, lightPlatform) = try makeFakeWindow(device: device) { tree() }
    lightWindow.theme = .light
    lightWindow.drawFrameIfNeeded()
    let lightRef = centrePixel(lightPlatform)

    let (darkWindow, darkPlatform) = try makeFakeWindow(device: device) { tree() }
    darkWindow.theme = .dark
    darkWindow.drawFrameIfNeeded()
    let darkRef = centrePixel(darkPlatform)
    try #require(lightRef != darkRef, "the two references must disagree")

    let (window, platform) = try makeFakeWindow(device: device) { tree() }
    window.theme = .light
    window.keymap = Keymap { KeyBinding("space", ToggleThemeFixture()) }
    window.onAction = { [weak window] action in
        guard action is ToggleThemeFixture, let window else { return false }
        window.theme = window.theme == .light ? .dark : .light
        return true
    }
    window.drawFrameIfNeeded()
    let before = centrePixel(platform)

    let handled = platform.simulateInput(.keyDown(KeyEvent(charactersIgnoringModifiers: " ",
                                                           characters: " ", timestamp: 0)))
    #expect(handled)
    window.drawFrameIfNeeded()
    let after = centrePixel(platform)

    #expect(before == lightRef)
    #expect(after == darkRef)
}

/// **E19.** A whole-value write cannot reset the theme or the pixel length
/// (ruling EV-U). `.environment(\.self, EnvironmentValues())` compiles outside
/// the module (guard G3's positive half), and so does writing back a captured
/// snapshot; both are re-stamped. **The control**: the same write does land —
/// it resets `probe` from 3 to 0, while a sibling under 3 alone reads 3.
@MainActor
@Test func aWholeValueWriteCannotResetTheThemeOrThePixelLength() throws {
    let captureLog = EnvLog()
    var plain = Row { EnvRecorder(label: "c", log: captureLog) }
    frame(scale: 1).render(&plain)
    let captured = try #require(captureLog.paint["c"])

    let resetLog = EnvLog()
    let resetFrame = frame(scale: 2)
    var reset = Row {
        Pair(surfaceBox(10), EnvRecorder(label: "r", log: resetLog))
            .environment(\.self, EnvironmentValues())
            .environment(\.probe, 3)
            .theme(.dark)
        EnvRecorder(label: "control", log: resetLog).environment(\.probe, 3).theme(.dark)
    }
    resetFrame.render(&reset)
    #expect(hsla(try #require(resetFrame.finalizedScene().rects.first).background) == Theme.dark.surface)
    #expect(resetLog.paint["r"]?.pixelLength == 0.5)
    #expect(resetLog.paint["r"]?.probe == 0, "the \\.self write did not land")
    #expect(resetLog.paint["control"]?.probe == 3)

    let restoreLog = EnvLog()
    let restoreFrame = frame(scale: 2)
    var restore = Row {
        Pair(surfaceBox(10), EnvRecorder(label: "r", log: restoreLog))
            .transformEnvironment(\.self) { $0 = captured }
            .environment(\.probe, 3)
            .theme(.dark)
    }
    restoreFrame.render(&restore)
    #expect(hsla(try #require(restoreFrame.finalizedScene().rects.first).background) == Theme.dark.surface)
    #expect(restoreLog.paint["r"]?.pixelLength == 0.5)
    #expect(restoreLog.paint["r"]?.probe == 0, "the captured snapshot was not written back")
}

// MARK: - E14: the window's environment (EV-H)

/// **E14.** `Window.environment` reaches the frame, a write repaints, and —
/// **pinned as a stated cost** — a no-op write repaints too: `EnvironmentValues`
/// holds custom keys as `Any` and cannot be compared (ruling EV-H). A change
/// that skips dirtying on equal built-in fields must face this pin and say how
/// it compares custom keys.
@MainActor
@Test func theWindowsEnvironmentReachesTheFrameAndASetRepaints() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let log = EnvLog()
    let (window, _) = try makeFakeWindow(device: device) {
        Row { EnvRecorder(label: "w", log: log) }
    }

    // Defaults on a fresh window, matching probe C.
    #expect(window.environment.isEnabled)
    #expect(window.environment.layoutDirection == .leftToRight)
    #expect(window.environment.locale.identifier == Locale.current.identifier)
    #expect(window.environment.dynamicTypeSize == .large)

    window.drawFrameIfNeeded()
    #expect(window.needsRedraw == false)
    #expect(log.paint["w"]?.locale.identifier == Locale.current.identifier)

    let other = Locale.current.identifier == "de_DE" ? "fr_FR" : "de_DE"
    try #require(other != Locale.current.identifier)
    window.environment.locale = Locale(identifier: other)
    #expect(window.needsRedraw == true)
    window.drawFrameIfNeeded()
    #expect(log.paint["w"]?.locale.identifier == other)

    #expect(window.needsRedraw == false)
    let unchanged = window.environment
    window.environment = unchanged
    #expect(window.needsRedraw == true, "a no-op write is pinned to dirty the window (EV-H)")
}

// MARK: - E15, E20: work counts (EV-O, EV-V)

private typealias Leaf = Box<EmptyGroup>
private typealias Level3 = Box<ArrayGroup<Leaf>>
private typealias Level2 = Box<ArrayGroup<Level3>>

@MainActor
private func branching(_ a: Int, _ b: Int, _ c: Int) -> ArrayGroup<Level2> {
    ArrayGroup((0..<a).map { _ in
        Box(content: ArrayGroup((0..<b).map { _ in
            Box(content: ArrayGroup((0..<c).map { _ in
                Box().width(px(1)).height(px(1))
            }))
        }))
    })
}

@MainActor
private func counts<C: ElementGroup>(_ content: C) throws -> (push: Int, snapshot: Int, transform: Int) {
    let f = frame(400, 400)
    var root = Box(content: content)
    f.render(&root)
    return (f.environmentPushCount, f.environmentSnapshotCount, f.environmentTransformCount)
}

/// **E15. Performance, counted as work** (ruling EV-O), on a branching 4×5×3
/// tree of fixed-size `Box`es and the same writers over a 1×1×1 tree.
///
/// - **Pushes** scale with writers, not descendants: 0, 3 (one writer, one
///   push per phase), 6 (two), identical on both trees.
/// - **Snapshots** are 0 on both trees with no reader, writers or not — the
///   claim a first pass could not see, because every bind built a value.
/// - **Positive control**: one `@Environment` reader leaf takes snapshots to 3
///   (one bind per phase) on both trees, so the counter can move.
/// - **Transforms**: one per writer per frame.
@MainActor
@Test func environmentWorkScalesWithWritersAndReadersNotWithTheirDescendants() throws {
    for (a, b, c) in [(4, 5, 3), (1, 1, 1)] {
        let none = try counts(branching(a, b, c))
        try #require(none.push == 0)
        try #require(none.snapshot == 0)
        try #require(none.transform == 0)

        let one = try counts(branching(a, b, c).environment(\.probe, 1))
        #expect(one.push == 3, "tree \(a)x\(b)x\(c)")
        #expect(one.snapshot == 0, "tree \(a)x\(b)x\(c)")
        #expect(one.transform == 1, "tree \(a)x\(b)x\(c)")

        let two = try counts(branching(a, b, c).environment(\.probe, 1)
                                .transformEnvironment(\.probe) { $0 += 1 })
        #expect(two.push == 6, "tree \(a)x\(b)x\(c)")
        #expect(two.snapshot == 0, "tree \(a)x\(b)x\(c)")
        #expect(two.transform == 2, "tree \(a)x\(b)x\(c)")

        let log = PropertyLog()
        let read = try counts(Pair(branching(a, b, c), PropertyRecorder(log: log))
                                 .environment(\.probe, 1))
        #expect(read.push == 3, "tree \(a)x\(b)x\(c)")
        #expect(read.snapshot == 3, "tree \(a)x\(b)x\(c): one bind per phase")
        #expect(log.paint == [1], "tree \(a)x\(b)x\(c): the reader must see the scope")
    }
}

@MainActor
private final class TransformCounter {
    var n = 0
}

/// **E20.** Each scope's transform runs once per frame, and all three phases
/// read its one result (ruling EV-V) — even though this transform returns a
/// different number every time it runs.
@MainActor
@Test func eachScopesTransformRunsOncePerFrame() {
    let counter = TransformCounter()
    let log = EnvLog()
    func tree() -> Row<EnvironmentScope<EnvRecorder>> {
        Row {
            EnvRecorder(label: "t", log: log).transformEnvironment(\.probe) {
                counter.n += 1
                $0 = counter.n
            }
        }
    }

    var first = tree()
    let firstFrame = frame()
    firstFrame.render(&first)
    #expect(counter.n == 1)
    #expect(log.probes("t") == [1, 1, 1])
    #expect(firstFrame.environmentTransformCount == 1)

    var second = tree()
    let secondFrame = frame()
    secondFrame.render(&second)
    #expect(counter.n == 2)
    #expect(log.probes("t") == [2, 2, 2])
    #expect(secondFrame.environmentTransformCount == 1)
}

// MARK: - E16, E17, E21: carried values with no built-in effect (EV-I, EV-K, EV-H)

@MainActor
private func textMeasure<C: ElementGroup>(_ content: (NodeProbe<Text>) -> C, _ text: Text)
    throws -> (min: SizeD, max: SizeD) {
    let nodes = NodeLog()
    let f = frame(400, 100)
    var root = Row { content(NodeProbe(inner: text, label: "text", log: nodes)) }
    f.render(&root)
    let node = try #require(nodes.nodes["text"])
    let measure = try #require(f.tree.measure(node))
    let min = measure(.unspecified, AvailableSpaceSize(width: .minContent, height: .maxContent))
    let max = measure(.unspecified, AvailableSpaceSize(width: .maxContent, height: .maxContent))
    return (min, max)
}

/// **E16.** `dynamicTypeSize` changes no text measurement — probe G, where a
/// SwiftUI `.body` text measures 120×16 at the default and at
/// `accessibility5`. Aligned behaviour on macOS, not an inert API (ruling
/// EV-I); pinned so a later "fix" has to face the probe. **Positive control**:
/// a 26pt font measures differently.
@MainActor
@Test func dynamicTypeSizeChangesNoTextMeasurement() throws {
    let text = Text("Hello, dynamic type")
    let bare = try textMeasure({ $0 }, text)
    let large = try textMeasure({ $0.dynamicTypeSize(.accessibility5) }, text)
    let control = try textMeasure({ $0 }, text.font(size: 26))

    try #require(control.max != bare.max, "the control font must measure differently")
    #expect(large.max == bare.max)
    #expect(large.min == bare.min)
}

/// **E17. PINNED WRONG ON PURPOSE** (ruling EV-K). Under `.rightToLeft`
/// SwiftUI mirrors: probe H places a 10pt and a 20pt child at x **90** and
/// **70** in a 100pt leading frame. MetalUI does not mirror yet and places them
/// at 0 and 10, as left-to-right does. It flips in the change that implements
/// mirroring (plan task 6).
@MainActor
@Test func aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack() throws {
    let f = frame(100, 10)
    var root = ZStack {
        HStack(spacing: px(0)) {
            Rectangle(width: px(10), height: px(10))
            Rectangle(width: px(20), height: px(10))
        }
        .frame(width: px(100), alignment: .leading)
        .environment(\.layoutDirection, .rightToLeft)
    }
    f.render(&root)

    let rects = f.finalizedScene().rects
    let ten = try #require(rects.first { $0.bounds.size.width == 10 })
    let twenty = try #require(rects.first { $0.bounds.size.width == 20 })
    #expect(ten.bounds.origin.x == 0)
    #expect(twenty.bounds.origin.x == 10)
}

/// **E21. PINNED INERT** (ruling EV-H). A locale reaches no text measurement:
/// `Text`'s tokenizer and typesetter never receive it. **Not claimed as
/// aligned** — no probe measured SwiftUI text under a locale. Thai is the
/// sample because its word breaks come from a dictionary, the one place a
/// locale-aware tokenizer could plausibly move min-content. **Positive
/// control**: a 26pt font measures differently.
@MainActor
@Test func aLocaleChangesNoTextMeasurement() throws {
    let text = Text("กรุงเทพมหานคร อมรรัตนโกสินทร์")
    let bare = try textMeasure({ $0 }, text)
    let thai = try textMeasure({ $0.environment(\.locale, Locale(identifier: "th_TH")) }, text)
    let english = try textMeasure({ $0.environment(\.locale, Locale(identifier: "en_US")) }, text)
    let control = try textMeasure({ $0 }, text.font(size: 26))

    try #require(control.max != bare.max, "the control font must measure differently")
    #expect(thai.min == bare.min)
    #expect(thai.max == bare.max)
    #expect(english.min == bare.min)
    #expect(english.max == bare.max)
}
