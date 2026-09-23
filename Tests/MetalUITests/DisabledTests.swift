import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

// Plan task 9, lane 3: the disabled control state
// (`docs/superpowers/specs/2026-09-15-environment-design.md`, tests D1–D16;
// rulings `EV-D`, `EV-E`, `EV-F`, `EV-T`, `EV-X`). D10 is an arm of E5,
// `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter`, in
// `EnvironmentTests.swift`.
//
// **One gate, in `Frame.registerHandlers`, reads `environment.isEnabled`.** A
// disabled element registers no hitbox (so a click over it reaches an enabled
// ancestor, or an enabled sibling under it), no focus, action handlers, raw
// `onKey` or `keyContext`, and its declared AX node carries `.disabled`.
//
// **This file imports `Metal`, so it declares no `Dimension`-typed fixture**
// (`Fakes.swift`'s note on `AnimationTests.swift`); sizes go through
// `.width(_:)`/`.height(_:)` and `.length(.pixels(_:))`.
//
// **Every window root is an `Element` container** (`Row`, `ZStack`, `HStack`),
// because a scope is not an `Element` and cannot be a root (ruling EV-B).
//
// **Every disabled arm has a control that must move the other way.** Where a
// test is parameterised by a `Bool`, the control spells `.disabled(false)`
// rather than deleting the modifier: probe B2 reads `.disabled(false)` as
// enabled, so the two halves differ in one value and share one structure and
// one set of ids, and a click point that missed would redden the control
// rather than pass the disabled half.
//
// **Every recorder is a reference type**: `makeFakeWindow`'s content closure
// builds fresh element values each frame, so nothing stored on an element
// survives one.
//
// The mutations run against these tests, and the tests each one reddened, are
// recorded under the ruling each cites in the decisions doc and in
// `docs/record/11-environment.md`.

// MARK: - Fixtures

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: b.origin.x + b.size.width / 2, y: b.origin.y + b.size.height / 2)
}

private func key(_ c: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: modifiers,
                      timestamp: 0))
}

@MainActor
private final class ClickLog {
    var names: [String] = []
    func count(_ name: String) -> Int { names.filter { $0 == name }.count }
}

/// What a `TargetProbe` saw of the element it wraps.
@MainActor
private final class ProbeLog {
    var ids: [String: GlobalElementID] = [:]
    var bounds: [String: Bounds<Pixels>] = [:]
    var active: [String: Bool] = [:]
    var enabled: [String: Bool] = [:]
}

/// Forwards every phase to `inner` **under the same id**, as `NodeProbe` does
/// (`EnvironmentTests.swift`), and records that id, the bounds, `isActive` and
/// `isEnabled`. So `inner`'s own `registerHandlers` registers under the id this
/// records, and a focus request on it targets `inner`.
private struct TargetProbe<Inner: Element>: Element {
    var inner: Inner
    let label: String
    let log: ProbeLog

    init(_ label: String, _ log: ProbeLog, _ inner: Inner) {
        self.inner = inner
        self.label = label
        self.log = log
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Inner.LayoutState) {
        inner.requestLayout(id, pass: &pass)
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Inner.LayoutState,
                           pass: inout PrepaintPass) -> Inner.PrepaintState {
        log.ids[label] = id
        log.bounds[label] = bounds
        return inner.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Inner.LayoutState, prepaint: inout Inner.PrepaintState,
                        pass: inout PaintPass) {
        log.active[label] = pass.isActive(id)
        log.enabled[label] = pass.environment.isEnabled
        inner.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// A fixed 10×10 leaf that records `pass.environment.isEnabled` in paint.
///
/// **A native leaf since stage 6a** (record §38, disposition R): its one test
/// reads the environment, which reads no authority, and runs under the proposal
/// authority.
private struct EnabledRecorder: Element {
    let label: String
    let log: ProbeLog

    init(_ label: String, _ log: ProbeLog) {
        self.label = label
        self.log = log
    }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.enabled[label] = pass.environment.isEnabled
    }
}

@MainActor
private final class FlagModel {
    var disabled = false
    var present = true
}

private struct Datum: Identifiable { let id: Int }

/// A component whose content is a 40×40 `onClick` box — D2's `Component` arm.
private struct ClickComponent: Component {
    let log: ClickLog
    var content: some ElementGroup {
        Box().width(px(40)).height(px(40)).onClick { log.names.append("component") }
    }
}

private struct Increment: Action {}
private struct PaneAction: Action {}

@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor
private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

@MainActor
private func device() throws -> any MTLDevice {
    try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
}

/// The rect in `scene` of exactly this size; each fixture below gives the rects
/// it keys on distinct sizes, so emission order does not matter.
private func rect(_ scene: Scene, _ width: Float, _ height: Float) throws -> MUIRect {
    try #require(scene.rects.first {
        $0.bounds.size.width == width && $0.bounds.size.height == height
    })
}

/// Whether `rect` was filled with `token` out of `theme`, component-wise
/// (`MUIHsla` has no `Equatable`).
private func isFilled(_ rect: MUIRect, with token: ColorToken, in theme: Theme) -> Bool {
    let want = theme[token]
    return rect.background.h == want.h && rect.background.s == want.s
        && rect.background.l == want.l && rect.background.a == want.a
}

// MARK: - D1, D4: the value and the gate (EV-D)

/// **D1.** `.disabled` composes as an AND and a raw write overrides it — probe
/// arm B of `docs/probes/swiftui-environment-scoping.swift`, which reads
/// `[true, false, true, false, false, true, false, false, false]` for B0–B8 in
/// SwiftUI. Read in paint. B3 and B6 are what a plain-write `.disabled` gets
/// wrong; B5 is what an AND-everything `.environment(\.isEnabled, …)` gets
/// wrong; B8 is a grandchild.
@MainActor
@Test func disabledComposesAsAnAndAndARawWriteOverridesIt() {
    let log = ProbeLog()
    var root = Row {
        EnabledRecorder("B0", log)
        EnabledRecorder("B1", log).disabled(true)
        EnabledRecorder("B2", log).disabled(false)
        EnabledRecorder("B3", log).disabled(false).disabled(true)
        EnabledRecorder("B4", log).disabled(true).disabled(false)
        EnabledRecorder("B5", log).environment(\.isEnabled, true).disabled(true)
        EnabledRecorder("B6", log).disabled(false).environment(\.isEnabled, false)
        EnabledRecorder("B7", log).disabled(true).environment(\.isEnabled, true)
        Row { Row { EnabledRecorder("B8", log) } }.disabled(true)
    }
    Frame(contentSize: Size(width: px(200), height: px(50)), scaleFactor: 1,
          stateTable: StateTable(), theme: .light, layoutAuthority: .proposal).render(&root)

    let labels = ["B0", "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8"]
    #expect(labels.map { log.enabled[$0] } == [true, false, true, false, false, true, false, false, false])
}

/// **D4.** The gate reads the environment VALUE, not the modifier — probe
/// `swiftui-disabled-interaction.swift` P8 (a tap under a raw `true` write
/// inside `.disabled(true)` fires, 1) and P9 (a tap under a raw `false` write
/// with no `.disabled` is blocked, 0). A gate counting `.disabled` scopes gets
/// both backwards.
///
/// Stage 6b (`LR-DG`, R-fill): every `auto` axis of the window's root carries
/// the window's extent (`.width`/`.height`, `Self`-returning — no layer, no id
/// level). The legacy root filled those axes itself (`CS-I`, divergence 4) and
/// sat at (0, 0); under the proposal authority a hugging root is centred at its
/// own answer (`CN-J`), so the literals below — written for a top-left root —
/// hold on both authorities only with the fill spelled.
@MainActor
@Test func theGateReadsTheEnvironmentValueNotTheModifier() throws {
    let device = try device()
    let log = ClickLog()

    let (p8, p8Platform) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box().width(px(40)).height(px(40)).onClick { log.names.append("P8") }
                .environment(\.isEnabled, true)
                .disabled(true)
        }.width(px(100)).height(px(100))
    }
    p8.drawFrameIfNeeded()
    click(p8Platform, at: pt(10, 50))
    #expect(log.count("P8") == 1, "a raw isEnabled = true below .disabled(true) re-enables (P8)")

    let (p9, p9Platform) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box().width(px(40)).height(px(40)).onClick { log.names.append("P9") }
                .environment(\.isEnabled, false)
        }.width(px(100)).height(px(100))
    }
    p9.drawFrameIfNeeded()
    click(p9Platform, at: pt(10, 50))
    #expect(log.count("P9") == 0, "a raw isEnabled = false with no .disabled blocks (P9)")
}

// MARK: - D2, D3: the pointer (EV-E, EV-X)

/// **D2.** Every handler-registering spelling suppresses its click when
/// disabled — the disabled twin of `onClickIsLiveOnEveryConformerThatCanRegisterOne`
/// (`InputDispatchTests.swift`).
///
/// **Arms are defined by their spelling, not by the type they produce.** The
/// gate is central today (`Frame.registerHandlers`), so ONE mutation reddens
/// every arm and there is no per-site mutation to run. **The arm list is this
/// test's stated purpose, not measured per-site coverage**: it exists for a
/// FUTURE site that registers a click without the gated method — the
/// modifier-composition track's `ModifiedElement`, which replaces the
/// `.frame(width:height:)` layer, and, after the accessibility-bridge merge, a
/// gate placed in the 5-argument `registerHandlers` that `Text` and
/// `OnTapModifier`'s 3-argument call would bypass (ruling EV-W items 3 and 4).
///
/// **Two `List` arms**, because a scope is not an `Element` and cannot be a
/// row: `list-row` disables a box inside a wrapper `Box` row (the wrapper is in
/// both halves); `list` disables the whole `List`.
///
/// **The `EV-X` arm must FIRE.** In
/// `Box().disabled(true).frame(width: 40, height: 40).onClick {}` the handler
/// belongs to the frame layer, which is written after the scope and so sits
/// outside it (probe `swiftui-disabled-ancestor-and-order.swift` O2). Its
/// **disagreeing spelling**, `….frame(…).onClick {}.disabled(true)`, fires 0
/// (O1) — so the arm is shown to tell inside the scope from outside it.
///
/// The proposal arm is 100×100 in a 100×100 window, so the click lands on it
/// wherever an `HStack` root places it; every legacy arm sits at the start of a
/// `Row` root, which centres its 100pt cross axis (ruling EP-8), so (10, 50) is
/// inside every 40×40 and 20×20 arm.
///
/// Stage 6b (`LR-DG`, R-fill): every `auto` axis of the window's root carries
/// the window's extent (`.width`/`.height`, `Self`-returning — no layer, no id
/// level). The legacy root filled those axes itself (`CS-I`, divergence 4) and
/// sat at (0, 0); under the proposal authority a hugging root is centred at its
/// own answer (`CN-J`), so the literals below — written for a top-left root —
/// hold on both authorities only with the fill spelled.
@MainActor
@Test func everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled() throws {
    let device = try device()
    let log = ClickLog()

    func fired<Root: Element>(_ name: String, at point: Point<Pixels>,
                              _ content: @escaping @MainActor () -> Root) throws -> Int {
        log.names.removeAll()
        let (window, platform) = try makeFakeWindow(device: device, size: 100, content: content)
        window.drawFrameIfNeeded()
        click(platform, at: point)
        return log.count(name)
    }

    func arm<Root: Element>(_ name: String, at point: Point<Pixels> = pt(10, 50),
                            _ make: @escaping @MainActor (Bool) -> Root) throws {
        let control = try fired(name, at: point) { make(false) }
        let disabled = try fired(name, at: point) { make(true) }
        #expect(control == 1, "\(name): the control must fire once (the click missed, or the arm registers nothing)")
        #expect(disabled == 0, "\(name): a disabled arm fired")
    }

    try arm("box") { d in
        Row { Box().width(px(40)).height(px(40)).onClick { log.names.append("box") }.disabled(d) }.width(px(100)).height(px(100))
    }
    try arm("column") { d in
        Row {
            Column { Box().width(px(40)).height(px(40)) }
                .width(px(40)).height(px(40)).onClick { log.names.append("column") }.disabled(d)
        }.width(px(100)).height(px(100))
    }
    try arm("row") { d in
        Row {
            Row { Box().width(px(40)).height(px(40)) }
                .width(px(40)).height(px(40)).onClick { log.names.append("row") }.disabled(d)
        }.width(px(100)).height(px(100))
    }
    try arm("stack") { d in
        Row {
            Stack { Box().width(px(40)).height(px(40)) }
                .width(px(40)).height(px(40)).onClick { log.names.append("stack") }.disabled(d)
        }.width(px(100)).height(px(100))
    }
    try arm("text") { d in
        Row { Text("x").width(px(40)).height(px(40)).onClick { log.names.append("text") }.disabled(d) }.width(px(100)).height(px(100))
    }
    // The `onClick` is on the inner (padding) layer; the frame layer outside it.
    try arm("padding-frame") { d in
        Row {
            Box().width(px(12)).height(px(12)).padding(px(4))
                .onClick { log.names.append("padding-frame") }
                .frame(width: px(20), height: px(20))
                .disabled(d)
        }.width(px(100)).height(px(100))
    }
    try arm("proposal", at: pt(50, 50)) { d in
        HStack {
            Rectangle(width: px(100), height: px(100)).onTap { log.names.append("proposal") }.disabled(d)
        }
    }
    try arm("component") { d in
        Row { ClickComponent(log: log).disabled(d) }.width(px(100)).height(px(100))
    }
    try arm("list-row") { d in
        Row {
            List([Datum(id: 0)], rowHeight: px(40)) { _ in
                Box {
                    Box().width(px(40)).height(px(40)).onClick { log.names.append("list-row") }.disabled(d)
                }
            }
            .width(px(40))
        }.width(px(100)).height(px(100))
    }
    try arm("list") { d in
        Row {
            List([Datum(id: 0)], rowHeight: px(40)) { _ in Box() }
                .width(px(40)).height(px(40)).onClick { log.names.append("list") }.disabled(d)
        }.width(px(100)).height(px(100))
    }

    // EV-X: after the scope fires (O2); the same layers with the scope written
    // last do not (O1), and that spelling's own control does.
    let after = try fired("after", at: pt(10, 50)) {
        Row {
            Box().width(px(20)).height(px(20)).disabled(true)
                .frame(width: px(40), height: px(40)).onClick { log.names.append("after") }
        }.width(px(100)).height(px(100))
    }
    #expect(after == 1, "a handler written after .disabled sits outside the scope and fires (EV-X, O2)")
    try arm("inside") { d in
        Row {
            Box().width(px(20)).height(px(20))
                .frame(width: px(40), height: px(40)).onClick { log.names.append("inside") }
                .disabled(d)
        }.width(px(100)).height(px(100))
    }
}

/// **D3.** A disabled click target registers no hitbox, so the click reaches
/// what is under it (ruling EV-E).
///
/// - **Ancestor — aligned** (probe `swiftui-disabled-ancestor-and-order.swift`
///   N1/N2: a disabled child does not block its tappable card, parent 1). The
///   control (child enabled) moves the other way, child 1 and parent 0, as N0/N3
///   do: `dispatchClick` does not bubble past the topmost hitbox.
/// - **Sibling under it — a DIVERGENCE, and not a new one** (probe
///   `swiftui-disabled-interaction.swift` P2f/P2m: SwiftUI's disabled or
///   gesture-less SHAPE blocks the sibling under it). MetalUI has no hit shape
///   apart from `onClick`: an enabled `Box` with no `onClick` over a clickable
///   sibling already lets the click through, and a disabled one now does the
///   same. The **reference** arm makes that concrete with
///   `.allowsHitTesting(false)`, which reads exactly as the disabled arm does.
///
/// Stage 6b (`LR-DG`, R-fill): every `auto` axis of the window's root carries
/// the window's extent (`.width`/`.height`, `Self`-returning — no layer, no id
/// level). The legacy root filled those axes itself (`CS-I`, divergence 4) and
/// sat at (0, 0); under the proposal authority a hugging root is centred at its
/// own answer (`CN-J`), so the literals below — written for a top-left root —
/// hold on both authorities only with the fill spelled.
@MainActor
@Test func aDisabledClickTargetPassesTheClickToWhatIsUnderIt() throws {
    let device = try device()
    let log = ClickLog()

    func clicks<Root: Element>(at point: Point<Pixels>,
                               _ content: @escaping @MainActor () -> Root) throws -> [String] {
        log.names.removeAll()
        let (window, platform) = try makeFakeWindow(device: device, size: 100, content: content)
        window.drawFrameIfNeeded()
        click(platform, at: point)
        return log.names
    }

    // Ancestor. The child is the parent box's first child, at its top-left:
    // (0, 30)…(20, 50) in the row's centred 40pt band, centre (10, 40).
    func ancestor(_ d: Bool) -> some Element {
        Row {
            Box {
                Box().width(px(20)).height(px(20)).onClick { log.names.append("child") }.disabled(d)
            }
            .width(px(40)).height(px(40)).onClick { log.names.append("parent") }
        }.width(px(100)).height(px(100))
    }
    #expect(try clicks(at: pt(10, 40)) { ancestor(false) } == ["child"],
            "control (N0/N3): an enabled child takes the click and the parent does not")
    #expect(try clicks(at: pt(10, 40)) { ancestor(true) } == ["parent"],
            "a disabled child passes the click to its enabled ancestor (N1/N2)")

    // Sibling under it. 100×100, so the click lands wherever the root places it.
    func sibling(_ d: Bool) -> some Element {
        ZStack {
            Rectangle(width: px(100), height: px(100)).onTap { log.names.append("under") }
            Rectangle(width: px(100), height: px(100)).onTap { log.names.append("over") }.disabled(d)
        }
    }
    #expect(try clicks(at: pt(50, 50)) { sibling(false) } == ["over"],
            "control: the enabled top sibling takes the click")
    #expect(try clicks(at: pt(50, 50)) { sibling(true) } == ["under"],
            "a disabled top sibling passes the click to the one under it (a divergence from P2f)")
    #expect(try clicks(at: pt(50, 50)) {
        ZStack {
            Rectangle(width: px(100), height: px(100)).onTap { log.names.append("under") }
            Rectangle(width: px(100), height: px(100)).onTap { log.names.append("over") }
                .allowsHitTesting(false)
        }
    } == ["under"], "reference: .allowsHitTesting(false) reads exactly as the disabled arm")
}

// MARK: - D5–D9, D11, D13, D14: the keyboard and focus (EV-F)

/// **D5.** A disabled element cannot acquire focus and sees no key — probe K1.
/// The control (enabled) is focused and its `onKey` runs once.
@MainActor
@Test func aDisabledElementCannotAcquireFocus() throws {
    let device = try device()

    func run(_ d: Bool) throws -> (focused: Bool, keys: Int) {
        let log = ClickLog()
        let probes = ProbeLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                TargetProbe("x", probes, Box().width(px(20)).height(px(20)).focusable()
                        .onKey { _ in log.names.append("x"); return true })
                    .disabled(d)
            }
        }
        window.drawFrameIfNeeded()
        let id = try #require(probes.ids["x"])
        window.focus(id)
        window.drawFrameIfNeeded()
        let focused = window.focusedElement == id
        platform.simulateInput(key("a"))
        return (focused, log.count("x"))
    }

    let control = try run(false)
    #expect(control.focused, "control: an enabled focusable box keeps a focus request")
    #expect(control.keys == 1, "control: its onKey runs")
    let disabled = try run(true)
    #expect(!disabled.focused, "a disabled element must not acquire focus (K1)")
    #expect(disabled.keys == 0, "a disabled element must see no key (K1)")
}

/// **D6. A DIVERGENCE PIN** (ruling EV-F). A focused element that becomes
/// disabled loses focus at once, and re-enabling does not restore it.
///
/// **SwiftUI measured the opposite** (probe `swiftui-disabled-interaction.swift`
/// K2: "focused before=1 after=1 onKeyPress after disabling=1 isEnabled seen by
/// the focused view after disabling=0", and "re-enabled: focused=1"). Kept
/// because the brief requires disabled to suppress focus — not for lack of a
/// signal: `Window.lastFocusRegistry` holds the previous frame's registry, and
/// keeping focus for an id disabled now and focusable there is about five
/// lines, which redden this test alone (EV-F's Mutations, EV-Q).
@MainActor
@Test func aFocusedElementThatBecomesDisabledLosesFocusAtOnce() throws {
    let device = try device()
    let model = FlagModel()
    let probes = ProbeLog()
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Row { TargetProbe("x", probes, Box().width(px(20)).height(px(20)).focusable()).disabled(model.disabled) }
    }
    window.drawFrameIfNeeded()
    let id = try #require(probes.ids["x"])
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "the control: enabled, the focus request holds")

    model.disabled = true
    redraw(window)
    #expect(window.focusedElement == nil, "disabling a focused element clears focus at once (divergence from K2)")

    model.disabled = false
    redraw(window)
    #expect(window.focusedElement == nil, "re-enabling does not restore it (divergence from K2)")
}

/// **D7.** A disabled element's action handler does not claim a keymap action.
///
/// A **context-free** `cmd-i` binding; the parent `Box` handles `Increment`
/// inside `.disabled(true)`, and holds a focusable child re-enabled by a raw
/// `.environment(\.isEnabled, true)`. With the child focused, cmd-I reaches
/// `Window.onAction` (1) and not the parent (0). The control (parent enabled)
/// reads parent 1, window 0.
///
/// **The routing is MetalUI's, not probed**: a `KeyBinding` belongs to the
/// window's keymap, so an action no ENABLED element claims reaches
/// `Window.onAction` like any unclaimed action. K4's analogue (a disabled
/// Button's `.keyboardShortcut` does not fire) is that the element's handler
/// does not run. A **context-scoped** binding under a disabled pane does not
/// match at all — D9.
@MainActor
@Test func aDisabledElementsActionHandlerDoesNotClaimAKeymapAction() throws {
    let device = try device()

    func run(_ d: Bool) throws -> (parent: Int, window: Int) {
        let log = ClickLog()
        let probes = ProbeLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                Box {
                    TargetProbe("child", probes, Box().width(px(20)).height(px(20)).focusable())
                        .environment(\.isEnabled, true)
                }
                .width(px(40)).height(px(40))
                .onAction(Increment.self) { _ in log.names.append("parent") }
                .disabled(d)
            }
        }
        window.keymap = Keymap { KeyBinding("cmd-i", Increment()) }
        window.onAction = { action in
            if action is Increment { log.names.append("window") }
            return true
        }
        window.drawFrameIfNeeded()
        let child = try #require(probes.ids["child"])
        window.focus(child)
        window.drawFrameIfNeeded()
        try #require(window.focusedElement == child, "the re-enabled child must hold focus")
        platform.simulateInput(key("i", .command))
        return (log.count("parent"), log.count("window"))
    }

    let control = try run(false)
    #expect(control.parent == 1 && control.window == 0,
            "control: the enabled parent claims the action (parent \(control.parent), window \(control.window))")
    let disabled = try run(true)
    #expect(disabled.parent == 0, "a disabled parent's onAction must not run")
    #expect(disabled.window == 1, "the unclaimed action reaches Window.onAction")
}

/// **D8. A DIVERGENCE PIN** (ruling EV-F). A disabled ancestor's raw `onKey`
/// does not see a key its enabled, focused descendant leaves unhandled; the key
/// reaches `Window.onInput`.
///
/// **SwiftUI measured the opposite** (probe K6: a disabled parent's
/// `.onKeyPress` runs exactly as an enabled one's, K6 = K5). Kept because the
/// brief requires disabled to suppress keys, and a disabled pane that kept its
/// raw shortcuts but lost its actions would be half live.
///
/// The child's own `onKey` runs in both halves (it returns `false`), so the
/// child is shown to be focused and the key to have entered the chain.
@MainActor
@Test func aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey() throws {
    let device = try device()

    func run(_ d: Bool) throws -> (child: Int, parent: Int, window: Int) {
        let log = ClickLog()
        let probes = ProbeLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                Box {
                    TargetProbe("child", probes, Box().width(px(20)).height(px(20)).focusable()
                            .onKey { _ in log.names.append("child"); return false })
                        .environment(\.isEnabled, true)
                }
                .width(px(40)).height(px(40))
                .onKey { _ in log.names.append("parent"); return true }
                .disabled(d)
            }
        }
        window.onInput = { event in
            if case .keyDown = event { log.names.append("window") }
            return false
        }
        window.drawFrameIfNeeded()
        let child = try #require(probes.ids["child"])
        window.focus(child)
        window.drawFrameIfNeeded()
        try #require(window.focusedElement == child, "the re-enabled child must hold focus")
        platform.simulateInput(key("a"))
        return (log.count("child"), log.count("parent"), log.count("window"))
    }

    let control = try run(false)
    #expect(control.child == 1 && control.parent == 1 && control.window == 0,
            "control: the enabled parent claims the key (child \(control.child), parent \(control.parent), window \(control.window))")
    let disabled = try run(true)
    #expect(disabled.child == 1, "the focused child's own handler still runs")
    #expect(disabled.parent == 0, "a disabled ancestor's raw onKey must not run (divergence from K6)")
    #expect(disabled.window == 1, "the unclaimed key reaches Window.onInput")
}

/// **D9.** A disabled pane contributes no `keyContext`, so a binding scoped to
/// it does not match at all: neither the re-enabled child's handler nor
/// `Window.onAction` sees it. **MetalUI's choice; SwiftUI has no comparable
/// concept** (ruling EV-S). The control (pane enabled) reaches the child.
@MainActor
@Test func aDisabledPaneContributesNoKeyContext() throws {
    let device = try device()

    func run(_ d: Bool) throws -> (child: Int, window: Int) {
        let log = ClickLog()
        let probes = ProbeLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                Box {
                    TargetProbe("child", probes, Box().width(px(20)).height(px(20)).focusable()
                            .onAction(PaneAction.self) { _ in log.names.append("child") })
                        .environment(\.isEnabled, true)
                }
                .width(px(40)).height(px(40))
                .keyContext("Pane")
                .disabled(d)
            }
        }
        window.keymap = Keymap { KeyBinding("cmd-k", PaneAction(), context: "Pane") }
        window.onAction = { action in
            if action is PaneAction { log.names.append("window") }
            return true
        }
        window.drawFrameIfNeeded()
        let child = try #require(probes.ids["child"])
        window.focus(child)
        window.drawFrameIfNeeded()
        try #require(window.focusedElement == child, "the re-enabled child must hold focus")
        platform.simulateInput(key("k", .command))
        return (log.count("child"), log.count("window"))
    }

    let control = try run(false)
    #expect(control.child == 1 && control.window == 0,
            "control: the pane's context matches and the child handles it (child \(control.child), window \(control.window))")
    let disabled = try run(true)
    #expect(disabled.child == 0, "a binding scoped to a disabled pane must not reach the child")
    #expect(disabled.window == 0, "nor fall through to Window.onAction: it does not match at all")
}

/// **D11.** Re-enabling restores clicks at once, and not a focus requested
/// while disabled. Frame N (disabled): a focus request is cleared and a click
/// runs nothing. Frame N+1 (enabled): a click runs the handler once, and focus
/// stays `nil`.
@MainActor
@Test func reEnablingRestoresClicksButNotFocus() throws {
    let device = try device()
    let model = FlagModel()
    model.disabled = true
    let log = ClickLog()
    let probes = ProbeLog()
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        Row {
            TargetProbe("x", probes, Box().width(px(40)).height(px(40)).focusable()
                    .onClick { log.names.append("x") })
                .disabled(model.disabled)
        }
    }
    window.drawFrameIfNeeded()
    let id = try #require(probes.ids["x"])
    let point = centre(try #require(probes.bounds["x"]))
    window.focus(id)
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "frame N: disabled, the focus request is cleared")
    click(platform, at: point)
    #expect(log.count("x") == 0, "frame N: disabled, the click runs nothing")

    model.disabled = false
    redraw(window)
    click(platform, at: point)
    #expect(log.count("x") == 1, "frame N+1: re-enabled, the click runs the handler")
    #expect(window.focusedElement == nil, "the focus requested while disabled is not restored")
}

/// **D13.** A focus request on a disabled element leaves no `$focus`
/// retention slot (ruling EV-F), so after the element is removed a second
/// request on its id does not stick.
///
/// **Instrument arm, PINNED WRONG ON PURPOSE**: the same sequence on an enabled
/// element that is merely NOT `.focusable()` DOES stick — the known hazard in
/// `Frame.registerHandlers`' `$focus` paragraph, reachable through
/// `Window.focus` on a produced non-focusable element. It proves this
/// instrument can see a sticky focus; `.disabled` does not reach that hazard
/// because the slot write is gated on `isEnabled`.
///
/// Both arms stay below `StateTable.sweepThreshold`, where a slot is never
/// reaped (`try #require`d, or a reap would hide the difference).
@MainActor
@Test func aFocusRequestWhileDisabledLeavesNoRetentionSlot() throws {
    let device = try device()

    func secondRequestSticks<Root: Element>(
        _ content: @escaping @MainActor (FlagModel, ProbeLog) -> Root) throws -> Bool {
        let model = FlagModel()
        let probes = ProbeLog()
        let (window, _) = try makeFakeWindow(device: device, size: 100) { content(model, probes) }
        window.drawFrameIfNeeded()
        let id = try #require(probes.ids["x"])
        window.focus(id)
        window.drawFrameIfNeeded()
        try #require(window.focusedElement == nil, "produced but not focusable: the first request is cleared")

        model.present = false
        redraw(window)
        window.focus(id)
        window.drawFrameIfNeeded()
        try #require(window.stateTable.count < StateTable.sweepThreshold)
        return window.focusedElement == id
    }

    let hazard = try secondRequestSticks { model, probes in
        Row { if model.present { TargetProbe("x", probes, Box().width(px(20)).height(px(20))) } }
    }
    #expect(hazard, "instrument (pinned wrong on purpose): a non-focusable enabled element's slot makes the second request stick")

    let disabled = try secondRequestSticks { model, probes in
        Row {
            if model.present {
                TargetProbe("x", probes, Box().width(px(20)).height(px(20)).focusable()).disabled(true)
            }
        }
    }
    #expect(!disabled, "a disabled element must leave no $focus slot, so the second request does not stick")
}

/// **D14.** A disabled scope reaches into `Deferred` content: a portal escapes
/// clip, offset and layer, not scope (ruling EV-G's `Deferred` half, applied to
/// the gate). The scope sits outside the `Deferred`, whose content must be an
/// `Element`. The control (enabled) clicks once and is focused.
@MainActor
@Test func aDisabledScopeReachesIntoDeferredContent() throws {
    let device = try device()

    func run(_ d: Bool) throws -> (clicks: Int, focused: Bool) {
        let log = ClickLog()
        let probes = ProbeLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                Row {
                    Deferred {
                        TargetProbe("x", probes, Box().width(px(40)).height(px(40)).focusable()
                                .onClick { log.names.append("x") })
                    }
                }
                .disabled(d)
            }
        }
        window.drawFrameIfNeeded()
        let id = try #require(probes.ids["x"])
        click(platform, at: centre(try #require(probes.bounds["x"])))
        window.focus(id)
        window.drawFrameIfNeeded()
        return (log.count("x"), window.focusedElement == id)
    }

    let control = try run(false)
    #expect(control.clicks == 1 && control.focused,
            "control: the portal's box clicks (\(control.clicks)) and holds focus (\(control.focused))")
    let disabled = try run(true)
    #expect(disabled.clicks == 0, "a disabled scope must reach the click target inside Deferred")
    #expect(!disabled.focused, "a disabled scope must reach the focus target inside Deferred")
}

// MARK: - D15, D16: press, release, hover (EV-T)

/// **D15.** A click needs its target enabled at press AND at release — probe
/// `swiftui-disabled-interaction.swift` R, for a plain `Button` and for
/// `.onTapGesture` alike: R0 (enabled throughout, the control) 1; R1 (pressed
/// disabled, released enabled) 0; R2 (pressed enabled, released disabled) 0;
/// R3 (disabled throughout) 0.
///
/// No `Window` edit reaches this: with no hitbox for a disabled target, a press
/// over it makes nothing `active` (R1), and a release over it finds no hitbox
/// with the pressed id (R2) — `dispatchClick`'s `hit.id == pressed`.
///
/// Stage 6b (`LR-DG`, R-fill): every `auto` axis of the window's root carries
/// the window's extent (`.width`/`.height`, `Self`-returning — no layer, no id
/// level). The legacy root filled those axes itself (`CS-I`, divergence 4) and
/// sat at (0, 0); under the proposal authority a hugging root is centred at its
/// own answer (`CN-J`), so the literals below — written for a top-left root —
/// hold on both authorities only with the fill spelled.
@MainActor
@Test func aClickNeedsTheTargetEnabledAtPressAndAtRelease() throws {
    let device = try device()

    func clicks(pressDisabled: Bool, releaseDisabled: Bool) throws -> Int {
        let model = FlagModel()
        model.disabled = pressDisabled
        let log = ClickLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                Box().width(px(40)).height(px(40)).onClick { log.names.append("x") }
                    .disabled(model.disabled)
            }.width(px(100)).height(px(100))
        }
        window.drawFrameIfNeeded()
        platform.simulateInput(.mouseDown(MouseEvent(position: pt(20, 50))))
        model.disabled = releaseDisabled
        redraw(window)
        platform.simulateInput(.mouseUp(MouseEvent(position: pt(20, 50))))
        return log.count("x")
    }

    #expect(try clicks(pressDisabled: false, releaseDisabled: false) == 1, "R0 control: enabled throughout")
    #expect(try clicks(pressDisabled: true, releaseDisabled: false) == 0, "R1: pressed disabled, released enabled")
    #expect(try clicks(pressDisabled: false, releaseDisabled: true) == 0, "R2: pressed enabled, released disabled")
    #expect(try clicks(pressDisabled: true, releaseDisabled: true) == 0, "R3: disabled throughout")
}

/// **D16.** A disabled target is neither hovered nor pressed (ruling EV-T): its
/// `hoverBackground` does not paint under the pointer and `isActive` reads
/// `false` during a held press. The control (enabled) paints `.accent` and
/// reads `true`. **Not probe-backed** (ruling EV-S): SwiftUI's hover look under
/// `.disabled` is unprobed.
///
/// **Consequence arm — MetalUI's, unprobed.** The same disabled box inside a
/// 40×40 `onClick` parent with its own `hoverBackground`: with the pointer over
/// the disabled child, the PARENT is the hitbox under it and paints `.accent`,
/// as it does over any child without an `onClick`. Its control (child enabled)
/// moves both rects the other way.
///
/// Stage 6b (`LR-DG`, R-fill): every `auto` axis of the window's root carries
/// the window's extent (`.width`/`.height`, `Self`-returning — no layer, no id
/// level). The legacy root filled those axes itself (`CS-I`, divergence 4) and
/// sat at (0, 0); under the proposal authority a hugging root is centred at its
/// own answer (`CN-J`), so the literals below — written for a top-left root —
/// hold on both authorities only with the fill spelled.
@MainActor
@Test func aDisabledTargetIsNeitherHoveredNorPressed() throws {
    let device = try device()

    func run(_ d: Bool) throws -> (hovered: Bool, active: Bool?) {
        let probes = ProbeLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                TargetProbe("x", probes, Box().width(px(40)).height(px(40)).onClick {}
                        .hoverBackground(.accent).background(.surface))
                    .disabled(d)
            }.width(px(100)).height(px(100))
        }
        window.drawFrameIfNeeded()
        platform.simulateInput(.mouseMoved(MouseEvent(position: pt(20, 50))))
        redraw(window)
        let box = try rect(window.lastScene, 40, 40)
        try #require(isFilled(box, with: .accent, in: window.theme)
                        || isFilled(box, with: .surface, in: window.theme),
                     "the box paints one of its two tokens")
        let hovered = isFilled(box, with: .accent, in: window.theme)

        platform.simulateInput(.mouseDown(MouseEvent(position: pt(20, 50))))
        redraw(window)
        let active = probes.active["x"]
        platform.simulateInput(.mouseUp(MouseEvent(position: pt(20, 50))))
        return (hovered, active)
    }

    let control = try run(false)
    #expect(control.hovered, "control: the enabled box under the pointer paints its hover token")
    #expect(control.active == true, "control: the enabled box reads isActive during a held press")
    let disabled = try run(true)
    #expect(!disabled.hovered, "a disabled box must not paint its hover token")
    #expect(disabled.active == false, "a disabled box must not read isActive during a held press")

    // Consequence: the parent under the pointer is what is hovered.
    func consequence(_ d: Bool) throws -> (parentHovered: Bool, childHovered: Bool) {
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                Box {
                    Box().width(px(20)).height(px(20)).onClick {}
                        .hoverBackground(.accent).background(.surface)
                        .disabled(d)
                }
                .width(px(40)).height(px(40)).onClick {}
                .hoverBackground(.accent).background(.surface)
            }.width(px(100)).height(px(100))
        }
        window.drawFrameIfNeeded()
        platform.simulateInput(.mouseMoved(MouseEvent(position: pt(10, 40))))
        redraw(window)
        let parent = try rect(window.lastScene, 40, 40)
        let child = try rect(window.lastScene, 20, 20)
        return (isFilled(parent, with: .accent, in: window.theme),
                isFilled(child, with: .accent, in: window.theme))
    }

    let enabledChild = try consequence(false)
    #expect(!enabledChild.parentHovered && enabledChild.childHovered,
            "control: over an enabled child, the child is hovered and the parent is not")
    let disabledChild = try consequence(true)
    #expect(disabledChild.parentHovered, "over a disabled child, the enabled parent is the hovered hitbox")
    #expect(!disabledChild.childHovered, "the disabled child is not hovered")
}

// MARK: - D12: accessibility

/// **D12.** A disabled element's declared AX node carries `.disabled`; the
/// control (enabled) does not. `handlers.axNode` is set directly, as
/// `AXEmitSiteTests.swift` does — there is no AX modifier.
///
/// **D12 cannot see the accessibility-bridge merge**: it reads a frame that is
/// not collecting for the bridge, so it stays green whatever the bridge's
/// record says about `isEnabled`. That is the joint test's job,
/// `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`
/// (`TrackInteractionTests.swift`), written at integration (ruling EV-W item 4;
/// it supersedes the third pass's name for it).
@MainActor
@Test func aDisabledElementsAXNodeCarriesTheDisabledTrait() throws {
    func traits(_ d: Bool) throws -> Set<AXTrait> {
        var declared = Box().width(px(30)).height(px(30))
        declared.handlers.axNode = AXNode(role: .button, label: "b")
        let box = declared
        let probes = ProbeLog()
        var root = Row { TargetProbe("b", probes, box).disabled(d) }
        let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                          stateTable: StateTable(), theme: .light)
        frame.render(&root)
        let id = try #require(probes.ids["b"])
        let node = try #require(frame.axNode(for: id), "the declared node must be emitted in both halves")
        try #require(node.label == "b")
        return node.traits
    }

    #expect(try !traits(false).contains(.disabled), "control: an enabled element's node has no .disabled trait")
    #expect(try traits(true).contains(.disabled), "a disabled element's node carries .disabled")
}

// MARK: - Scroll regions are outside the gate

/// **A `.disabled` `ScrollView` still scrolls on the wheel**, pinned as it
/// stands at integration (environment track, second verification round):
/// `Frame.registerScrollRegion` inserts its hitbox directly, not through
/// `registerHandlers`, so the disabled gate never sees it. SwiftUI's answer is
/// **unmeasured** (ruling EV-Q's task-10 item); this pins MetalUI's, so a change
/// either way is a decision rather than an accident. Control: the same scroller
/// enabled reads the same offset, and a wheel that misses reads 0, so the
/// instrument can tell a scroll from none.
///
/// Stage 6b (`LR-DG`, R-fill): every `auto` axis of the window's root carries
/// the window's extent (`.width`/`.height`, `Self`-returning — no layer, no id
/// level). The legacy root filled those axes itself (`CS-I`, divergence 4) and
/// sat at (0, 0); under the proposal authority a hugging root is centred at its
/// own answer (`CN-J`), so the literals below — written for a top-left root —
/// hold on both authorities only with the fill spelled.
@MainActor
@Test func aDisabledScrollViewStillScrollsOnTheWheel() throws {
    let device = try device()
    func offset(disabled: Bool, at point: Point<Pixels>) throws -> Double {
        let (window, platform) = try makeFakeWindow(device: device, size: 200) {
            Row {
                Box {
                    ScrollView(.vertical, elementID: ElementID("list")) { Box().width(px(40)).height(px(400)) }
                        .disabled(disabled)
                }
                .width(px(120)).height(px(120))
            }.width(px(200)).height(px(200))
        }
        window.drawFrameIfNeeded()
        platform.simulateInput(.scrollWheel(ScrollEvent(position: point, delta: Point(x: px(0), y: px(-37)))))
        window.drawFrameIfNeeded()
        let root = GlobalElementID.child(of: nil, at: 0, name: nil)
        let box = GlobalElementID.child(of: root, at: 0, name: nil)
        let scroller = GlobalElementID.child(of: box, at: 0, name: ElementID("list"))
        return window.stateTable.peek(scroller, as: ScrollState.self)?.offset ?? 0
    }
    let missed = try offset(disabled: false, at: pt(180, 190))
    let enabled = try offset(disabled: false, at: pt(20, 100))
    try #require(missed == 0 && enabled > 0, "the instrument: a miss reads \(missed), a hit \(enabled)")
    let disabled = try offset(disabled: true, at: pt(20, 100))
    #expect(disabled == enabled, "a disabled ScrollView scrolls as an enabled one does (unpinned choice, EV-Q)")
}
