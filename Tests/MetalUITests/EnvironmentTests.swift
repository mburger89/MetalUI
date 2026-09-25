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
// rulings `EV-A`…`EV-C`, `EV-G`…`EV-M`, `EV-O`, `EV-P`, `EV-U`, `EV-V`), and
// lane 2b's E12 arm and E22–E24 (rulings `EV-B`, `EV-X`, `EV-Y`), and lane 3's
// D10 arm of E5 (the rest of lane 3 is in `DisabledTests.swift`).
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

/// A leaf that reads `pass.environment` in all three phases.
///
/// **A native 10×10 leaf since stage 6a** (record §38, disposition R), as is
/// `PropertyRecorder` below: the tests reading them are about the environment,
/// which reads no authority, so each test whose tree holds a legacy container
/// ran under the proposal authority explicitly until stage 9 made it the only
/// one. No assertion moved.
private struct EnvRecorder: Element {
    let label: String
    let log: EnvLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.layout[label] = pass.environment
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
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
///
/// A `ProposalElement` since the modifier-composition merge (ruling MC-G): the
/// marker-plus-`Element` shape it had on `feat/environment` no longer compiles.
/// Its layout reading stays inside `requestProposalLayout` (ruling EV-W item 1).
private struct NativeEnvRecorder: ProposalElement {
    let label: String
    let log: EnvLog

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        log.layout[label] = pass.environment
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
        return (node, ())
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
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
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
    Box().cssWidth(px(width)).cssHeight(px(10)).background(.surface)
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
///
/// **A declared-size native leaf** (`declaredSizeNativeLeaf`). It registered
/// through `Frame`'s internal legacy registrar from stage 6a (record §38,
/// disposition P-6b) and was a Dual leaf from stage 6b (`LR-DI`) until stage 9
/// deleted that registrar.
private struct ClickCounter: Element {
    @State var n = 0
    let log: CounterLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (declaredSizeNativeLeaf(fixedStyle(20, 20), pass), ())
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
    var flag = false
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
/// mutation — a value-keyed `EitherGroup` writer resets `n`.
///
/// **The `.disabled(model.flag)` arm (lane 3, spec D10; rulings EV-B, EV-D,
/// EV-E).** The same counter under `.disabled(model.flag)` keeps `n` across a
/// flip to disabled and back, and a click while disabled does not increment
/// it; a click after re-enabling does (the control that the click point still
/// lands). Every draw after a model change is forced, so a reading is never a
/// stale frame's.
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): both `Row` roots declare the 64x64 window's
/// extent on their two auto axes, so the counter sits at x 0…20, y 22…42 on
/// both authorities and (10, 32) lands on it; the counter is a Dual leaf.
@MainActor
@Test func changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let model = EnvModel()
    let log = CounterLog()
    let (window, platform) = try makeFakeWindow(device: device) {
        Row { ClickCounter(log: log).environment(\.probe, model.value) }
            .frame(width: px(64), height: px(64), alignment: .leading)
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

    // D10: the `.disabled` arm.
    let disabledLog = CounterLog()
    let (disabledWindow, disabledPlatform) = try makeFakeWindow(device: device) {
        Row { ClickCounter(log: disabledLog).disabled(model.flag) }
            .frame(width: px(64), height: px(64), alignment: .leading)
    }
    disabledWindow.drawFrameIfNeeded()
    click(disabledPlatform, at: centre)
    disabledWindow.drawFrameIfNeeded()
    click(disabledPlatform, at: centre)
    disabledWindow.drawFrameIfNeeded()
    try #require(disabledLog.readings.last == 2, "the control: two enabled clicks count 2")

    model.flag = true
    disabledWindow.setNeedsRedraw()
    disabledWindow.drawFrameIfNeeded()
    #expect(disabledLog.readings.last == 2, "disabling reset the state below the writer")
    click(disabledPlatform, at: centre)
    disabledWindow.setNeedsRedraw()
    disabledWindow.drawFrameIfNeeded()
    #expect(disabledLog.readings.last == 2, "a click while disabled incremented the counter")

    model.flag = false
    disabledWindow.setNeedsRedraw()
    disabledWindow.drawFrameIfNeeded()
    #expect(disabledLog.readings.last == 2, "re-enabling reset the state below the writer")
    click(disabledPlatform, at: centre)
    disabledWindow.setNeedsRedraw()
    disabledWindow.drawFrameIfNeeded()
    #expect(disabledLog.readings.last == 3, "re-enabled, a click counts again")
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

// MARK: - E22, E23: transparency on the proposal path (EV-B, lane 2b)

/// **E22.** E4 on the proposal path: a scope over proposal content inside an
/// `HStack` contributes no node and consumes no index — the stack still has
/// three children, and A, B and C keep the ids they have without the scope.
///
/// **Passes on arrival, stated** (ruling EV-B): today one
/// `requestGroupLayout` serves both paths, so E4 already covers this. It exists
/// for the modifier-composition merge, where the proposal path gets its own
/// typed entry, hand-written at integration; a `cursor += 1` or a fresh child
/// id there would redden none of E4, E5 or E10. Its mutations were run here
/// against the shared entry to prove the instrument sees, and are **re-run at
/// integration against the typed entry** (ruling EV-W item 1).
///
/// The bare stack's child count is `try #require`d first: if the explicit
/// `Pair` flattened differently from the scoped spelling, the comparison of
/// counts would say nothing.
@MainActor
@Test func aScopeOverProposalContentContributesNoNodeAndConsumesNoIndex() throws {
    let bareLog = EnvLog()
    let bareNodes = NodeLog()
    var bare = NodeProbe(inner: HStack(spacing: px(0)) {
        Pair(NativeEnvRecorder(label: "A", log: bareLog), NativeEnvRecorder(label: "B", log: bareLog))
        NativeEnvRecorder(label: "C", log: bareLog)
    }, label: "stack", log: bareNodes)
    let bareFrame = frame()
    bareFrame.render(&bare)
    let bareStack = try #require(bareNodes.nodes["stack"])
    try #require(bareFrame.tree.children(bareStack).count == 3)

    let scopedLog = EnvLog()
    let scopedNodes = NodeLog()
    var scoped = NodeProbe(inner: HStack(spacing: px(0)) {
        Pair(NativeEnvRecorder(label: "A", log: scopedLog), NativeEnvRecorder(label: "B", log: scopedLog))
            .environment(\.probe, 1)
        NativeEnvRecorder(label: "C", log: scopedLog)
    }, label: "stack", log: scopedNodes)
    let scopedFrame = frame()
    scopedFrame.render(&scoped)

    let stack = try #require(scopedNodes.nodes["stack"])
    #expect(scopedFrame.tree.children(stack).count == 3)
    for label in ["A", "B", "C"] {
        let scopedID = try #require(scopedLog.ids[label])
        let bareID = try #require(bareLog.ids[label])
        #expect(scopedID == bareID, "\(label)'s id moved under the scope")
    }
    try #require(scopedLog.paint["A"]?.probe == 1, "the scope must reach its proposal content")
}

@MainActor
private final class NativeCounterLog {
    var readings: [Int] = []
    var bounds: Bounds<Pixels>?
}

/// E11's shape — a `ProposalElement` with a native leaf (ported from the
/// marker-plus-`Element` shape at the modifier-composition merge, ruling MC-G)
/// — as a click counter: `@State var n`, incremented by an `onClick`
/// registered through `pass.registerHandlers`, logged in paint.
private struct NativeClickCounter: ProposalElement {
    @State var n = 0
    let log: NativeCounterLog

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.bounds = bounds
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

/// **E23.** E5 on the proposal path: a `@State` counter under a scope whose
/// value changes keeps its count — probe D1, where SwiftUI's counter survives
/// a changing environment value.
///
/// **Passes on arrival, as E5 did**: nothing can lose the state until a scope
/// mints an identity level. Its mutation — the scope's id keyed by its values —
/// reads 0. Re-run at integration against the typed entry (ruling EV-W
/// item 1). The click lands at the centre of the bounds the counter reported,
/// not at a computed guess, and two clicks must count 2 before the value moves.
@MainActor
@Test func aProposalStateCounterKeepsItsCountAcrossAChangingScope() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let model = EnvModel()
    let log = NativeCounterLog()
    let (window, platform) = try makeFakeWindow(device: device) {
        HStack { NativeClickCounter(log: log).environment(\.probe, model.value) }
    }

    window.drawFrameIfNeeded()
    let bounds = try #require(log.bounds)
    let centre = Point(x: bounds.origin.x + bounds.size.width / 2,
                       y: bounds.origin.y + bounds.size.height / 2)
    click(platform, at: centre)
    window.drawFrameIfNeeded()
    click(platform, at: centre)
    window.drawFrameIfNeeded()
    try #require(log.readings.last == 2, "the control: two clicks count 2")

    model.value = 7
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(log.readings.last == 2, "a changed environment value reset the proposal state below it")
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

/// **E8.** An `@Environment` inside `AnyElement` is bound (plan task 8, ruling
/// ID-E): `AnyElementBox` binds its concrete element in layout, prepaint and
/// paint, so it reads the scope's 5 in every phase. Until task 8 this test was
/// `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`, pinned
/// inert at `[[0], [0], [0]]` (record §55, lane 1's retirement row).
///
/// **An `@Environment` that was never bound still returns the key's default
/// silently** (a value built outside any frame), and builds a fresh
/// `EnvironmentValues()` on every access — whose locale is
/// `Locale(identifier: "")`, not the window's `Locale.current` (ruling EV-Y).
@MainActor
@Test func anEnvironmentPropertyInsideAnyElementReadsItsScope() {
    let log = PropertyLog()
    var root = Row { AnyElement(PropertyRecorder(log: log)).environment(\.probe, 5) }
    frame().render(&root)
    #expect([log.layout, log.prepaint, log.paint] == [[5], [5], [5]])
}

private struct EnvComponent: Component {
    @Environment(\.probe) var probe
    var content: some ElementGroup {
        Box().cssWidth(px(10)).cssHeight(px(10)).background(probe == 1 ? .accent : .surface)
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
///
/// **Ported at the modifier-composition merge** (ruling EV-W item 1): its
/// recorder is a `ProposalElement` whose layout reading sits inside
/// `requestProposalLayout`, so the layout slot is served by
/// `EnvironmentScope`'s typed `requestProposalGroupLayout`. This test **is**
/// the composition track's owed `aProposalContainerReadsTheEnvironmentDuringLayout`
/// (that name is deliberately not added): its arm 2 puts the scope outside an
/// inner `HStack` rather than around the leaf, and its no-writer control reads
/// the key's default, so a recorder that always reads 7 cannot pass. Arm 2 is
/// nested in an outer `HStack` because `Frame.render` takes an `Element` and a
/// scope is only an `ElementGroup`. Mutation at integration: the typed entry
/// without `withEnvironment` reddens the layout slot of both the `hstack` and
/// `scroll` arms and of arm 2 (record §13).
@MainActor
@Test func proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase() {
    let log = EnvLog()
    var control = HStack {
        NativeEnvRecorder(label: "control", log: log)
    }
    frame(100, 50).render(&control)
    #expect(log.probes("control") == [0, 0, 0], "no writer reads the key's default")

    var stack = HStack {
        Rectangle(width: px(5), height: px(5))
        NativeEnvRecorder(label: "hstack", log: log).environment(\.probe, 7)
    }
    frame(100, 50).render(&stack)
    #expect(log.probes("hstack") == [7, 7, 7])

    var outside = HStack {
        HStack { NativeEnvRecorder(label: "outside", log: log) }.environment(\.probe, 7)
    }
    frame(100, 50).render(&outside)
    #expect(log.probes("outside") == [7, 7, 7], "the scope outside an inner HStack")

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
///
/// **The after-`.theme` arm (lane 2b, ruling EV-X).** A modifier written after
/// a scope sits outside it: in `surfaceBox(13).theme(.dark).frame(14×10).background(.surface)`
/// the 13pt box paints dark and the 14pt frame layer paints **light**, the
/// enclosing theme — SwiftUI's O6 (a background after an `.environment` writer
/// reads the default) and F2. `.frame(width:height:)` is an `ElementGroup`
/// extension, so this compiles although `.padding` directly on a scope does
/// not. **The disagreeing spelling** moves `.theme(.dark)` after the frame's
/// background (15pt and 16pt), and both read dark — so the arm is shown to
/// tell inside the scope from outside it, not to read light everywhere.
///
/// **Under both authorities from plan task 7 stage 5 lane 3 to stage 9** (spec
/// 3.8, `LR-CO`): a plain `Frame` with diagnostics on, requiring an empty report
/// before anything is read (`LR-BX`). The `Deferred` is **in-flow**;
/// the presentation-shaped twin is
/// `aPresentationKeepsItsDeclaringScopesEnvironment` (`PresentationWindowTests`). Colours only are read, so the proposal root's
/// centring (`CN-J`) does not reach an assertion.
@MainActor
@Test
func aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope() throws {
    let f = Frame(contentSize: Size(width: px(200), height: px(50)), scaleFactor: 1,
                  stateTable: StateTable(), theme: .light, reportsUnlowerableFields: true)
    var root = Row {
        surfaceBox(10).theme(.dark)
        surfaceBox(11)
        Deferred { surfaceBox(12) }.theme(.dark)
        surfaceBox(13).theme(.dark).frame(width: px(14), height: px(10)).background(.surface)
        surfaceBox(15).frame(width: px(16), height: px(10)).background(.surface).theme(.dark)
    }
    f.render(&root)
    try #require(f.unlowerableFields.isEmpty, "\(f.unlowerableFields)")

    let rects = f.finalizedScene().rects
    func colour(_ width: Float) throws -> Hsla {
        hsla(try #require(rects.first { $0.bounds.size.width == width }).background)
    }
    try #require(Theme.dark.surface != Theme.light.surface)
    #expect(try colour(10) == Theme.dark.surface)
    #expect(try colour(11) == Theme.light.surface)
    #expect(try colour(12) == Theme.dark.surface)

    // EV-X: inside the scope dark, the frame layer written after it light.
    #expect(try colour(13) == Theme.dark.surface)
    #expect(try colour(14) == Theme.light.surface, "a modifier after a scope must sit outside it (EV-X)")
    // The disagreeing spelling: the same layers, the scope written last.
    #expect(try colour(15) == Theme.dark.surface)
    #expect(try colour(16) == Theme.dark.surface)
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
    // Stage 6b (`LR-DG`, R-fill): the 64x64 window's extent declared on the
    // childless root's two auto axes — a proposal `Box()` with none answers
    // 0x0 and paints nothing at the centre; the legacy root filled them itself.
    func tree() -> Box<EmptyGroup> { Box().background(.background).cssWidth(px(64)).cssHeight(px(64)) }

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

/// **E24.** A bare `EnvironmentValues()` holds SwiftUI's **bare** locale,
/// `Locale(identifier: "")`, and a window stamps `Locale.current` over it
/// (ruling EV-Y) — probe `swiftui-environment-pixel-length.swift` V0/V2 (bare:
/// '' and `== Locale(identifier: "")` true) against X0 and scoping probe C (a
/// hosted window: `en_US`), and X2 (a `\.self` reset in a window reads '').
///
/// - (i) the bare value. The `try #require` makes the comparison
///   discriminate: on a machine whose current locale were the root locale,
///   every arm would pass for either implementation.
/// - (ii) a fresh window's root, and a reader with no writer under it.
/// - (iii) in the same window, a `\.self` reset reads '' while its unscoped
///   sibling still reads the window's — so the recorder is shown to see the
///   difference between the two sources.
@MainActor
@Test func aBareEnvironmentValuesHoldsTheRootLocaleAndAWindowStampsTheCurrentOne() throws {
    try #require(Locale.current != Locale(identifier: ""))
    try #require(Locale.current.identifier != "")
    #expect(EnvironmentValues().locale == Locale(identifier: ""))
    #expect(EnvironmentValues().locale.identifier == "")

    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let log = EnvLog()
    let (window, _) = try makeFakeWindow(device: device) {
        Row {
            EnvRecorder(label: "window", log: log)
            EnvRecorder(label: "reset", log: log).environment(\.self, EnvironmentValues())
        }
    }
    #expect(window.environment.locale == Locale.current)
    window.drawFrameIfNeeded()
    #expect(log.paint["window"]?.locale.identifier == Locale.current.identifier)
    #expect(log.paint["reset"]?.locale.identifier == "")

    // (iv) and (v), added at integration (EV-Y's two unpinned claims; the
    // second verification round's mutants m1 and m2 left the suite green).
    // A `Frame` built without a window roots at the bare locale...
    let windowless = EnvLog()
    var bare = Row { EnvRecorder(label: "w", log: windowless) }
    frame().render(&bare)
    #expect(windowless.paint["w"]?.locale.identifier == "", "a windowless Frame roots at EnvironmentValues()")
    // ...and an `@Environment` that was never bound reads the bare default.
    let unbound = Environment(\.locale)
    #expect(unbound.wrappedValue.identifier == "", "an unbound @Environment reads EnvironmentValues()'s locale")
}

// MARK: - E15, E20: work counts (EV-O, EV-V)

private typealias Leaf = ModifiedElement<Box<EmptyGroup>>
private typealias Level3 = Box<ArrayGroup<Leaf>>
private typealias Level2 = Box<ArrayGroup<Level3>>

@MainActor
private func branching(_ a: Int, _ b: Int, _ c: Int) -> ArrayGroup<Level2> {
    ArrayGroup((0..<a).map { _ in
        Box(content: ArrayGroup((0..<b).map { _ in
            Box(content: ArrayGroup((0..<c).map { _ in
                Box().frame(width: px(1), height: px(1))
            }))
        }))
    })
}

@MainActor
private func counts<C: ElementGroup>(_ content: C)
    throws -> (push: Int, snapshot: Int, transform: Int) {
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

/// A `Text`'s measured size under the **proposal** authority, read off
/// `Frame.elementBounds` (stage 7b, record §49 rows 236–237): `ideal` in a
/// 4000-wide frame — wider than any string here at 26pt, so the leaf answers
/// its one-line width, the answer it gives a nil width — and `broken` in a
/// 20-wide frame, narrower than every word, so the leaf breaks and answers the
/// proposal's width with its broken lines' height (`proposalTextMeasurement`,
/// `LR-AU`). `content` wraps the `Text` in the environment write under test;
/// an `EnvironmentScope` is identity-transparent, so the `Text` is the `Row`'s
/// child 0 either way. Each frame reports rather than traps, and the report is
/// required empty.
@MainActor
private func proposalTextMeasure<C: ElementGroup>(_ content: (Text) -> C, _ text: Text)
    throws -> (ideal: Size<Pixels>, broken: Size<Pixels>) {
    let rowID = GlobalElementID.child(of: nil, at: 0, name: nil)
    let textID = GlobalElementID.child(of: rowID, at: 0, name: nil)
    func measured(width: Float) throws -> Size<Pixels> {
        let f = Frame(contentSize: Size(width: px(width), height: px(1000)), scaleFactor: 1, reportsUnlowerableFields: true,
                      recordsElementBounds: true)
        var root = Row { content(text) }
        f.render(&root)
        try #require(f.unlowerableFields.isEmpty,
                     "the text reported \(f.unlowerableFields.map(\.description))")
        return try #require(f.elementBounds[textID], "the text recorded no bounds").size
    }
    return (try measured(width: 4000), try measured(width: 20))
}

/// **E16 under the proposal authority** (stage 7b, record §49 row 236, N3.1):
/// `dynamicTypeSize` changes no text measurement — probe G, where a SwiftUI
/// `.body` text measures 120×16 at the default and at `accessibility5` (EV-I).
/// The retired `dynamicTypeSizeChangesNoTextMeasurement` read the legacy
/// leaf's CSS `MeasureFunction`; this reads the lowered leaf's answer at its
/// ideal and at a broken width. **Positive control**: a 26pt font measures
/// differently at both, `#require`d first.
///
/// Red-before (record §49 §6.3, M3.1): the lowered `Text`'s measurement scaled
/// by 2 when `environment.dynamicTypeSize != .large`.
@MainActor
@Test func dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority() throws {
    let text = Text("Hello, dynamic type")
    let bare = try proposalTextMeasure({ $0 }, text)
    let large = try proposalTextMeasure({ $0.dynamicTypeSize(.accessibility5) }, text)
    let control = try proposalTextMeasure({ $0 }, text.font(size: 26))

    try #require(control.ideal != bare.ideal && control.broken != bare.broken,
                 "the control font must measure differently: \(control) vs \(bare)")
    #expect(large.ideal == bare.ideal)
    #expect(large.broken == bare.broken)
}

/// **E21 under the proposal authority** (stage 7b, record §49 row 237, N3.2).
/// **PINNED INERT** (EV-H): a locale reaches no text measurement — `Text`'s
/// tokenizer and typesetter never receive it. Not claimed as aligned: no probe
/// measured SwiftUI text under a locale. Thai is the sample because its word
/// breaks come from a dictionary, the one place a locale-aware breaker could
/// plausibly move the broken answer. **Positive control**: a 26pt font
/// measures differently at both widths, `#require`d first.
///
/// Red-before (record §49 §6.3, M3.2): the lowered `Text`'s measurement scaled
/// by 2 when the environment's locale is `th_TH`.
@MainActor
@Test func aLocaleChangesNoTextMeasurementUnderTheProposalAuthority() throws {
    let text = Text("กรุงเทพมหานคร อมรรัตนโกสินทร์")
    let bare = try proposalTextMeasure({ $0 }, text)
    let thai = try proposalTextMeasure({ $0.environment(\.locale, Locale(identifier: "th_TH")) }, text)
    let english = try proposalTextMeasure({ $0.environment(\.locale, Locale(identifier: "en_US")) }, text)
    let control = try proposalTextMeasure({ $0 }, text.font(size: 26))

    try #require(control.ideal != bare.ideal && control.broken != bare.broken,
                 "the control font must measure differently: \(control) vs \(bare)")
    #expect(thai.ideal == bare.ideal)
    #expect(thai.broken == bare.broken)
    #expect(english.ideal == bare.ideal)
    #expect(english.broken == bare.broken)
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
