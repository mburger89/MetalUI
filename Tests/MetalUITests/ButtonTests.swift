import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 10, part 2, lane 1: `Button` (ruling `DD-R`, `DD-T`; spec
// `2026-09-26-controls-and-selection-design.md` §4, §5, tests 1.1–1.8).
// Literals are derived before the run from MetalUI's own measured `Text` sizes
// (`controlTextSize`), never from SwiftUI's points, except where the number is
// structural (padding, strut height, gap).
//
// **The shared helpers below are internal, not private**, and prefixed
// `control`: `ToggleTests`, `PickerTests` and `ControlAccessibilityTests` read
// them too.
//
// **Footing.** Every layout fixture is `Row { control }` with the window's
// extent declared on the root, so the root sits at (0, 0) and the control at
// x = 0 — which is what makes `textW + 24` exact after the engine's rounding
// (a rounded edge at an integral origin plus an integral offset rounds by the
// same amount).

// MARK: - Shared helpers

func controlPx(_ v: Float) -> Pixels { Pixels(v) }

/// The id at `path` under the root: `[0]` is the root, `[0, 0]` its first child.
func controlID(_ path: [Int]) -> GlobalElementID {
    var id = GlobalElementID.child(of: nil, at: path[0], name: nil)
    for index in path.dropFirst() { id = GlobalElementID.child(of: id, at: index, name: nil) }
    return id
}

/// `content` in a `Row` root declaring the frame's extent, so its first child
/// sits at x = 0.
@MainActor
func controlRoot<C: ElementGroup>(width: Float = 400, height: Float = 200,
                                  @ElementBuilder _ content: () -> C) -> Row<C> {
    Row { content() }.cssWidth(controlPx(width)).cssHeight(controlPx(height))
}

/// Renders `root` into a reporting, bounds-recording `Frame` and requires the
/// report empty.
@MainActor
func controlRender<E: Element>(_ root: E, width: Float = 400, height: Float = 200,
                               collectsAccessibility: Bool = false) throws -> Frame {
    var root = root
    let frame = Frame(contentSize: Size(width: controlPx(width), height: controlPx(height)), scaleFactor: 1,
                      collectsAccessibility: collectsAccessibility,
                      reportsUnlowerableFields: true, recordsElementBounds: true)
    frame.render(&root)
    try #require(frame.unlowerableFields.isEmpty,
                 "the fixture reported \(frame.unlowerableFields.map(\.description))")
    return frame
}

/// A `Text`'s rounded size at x = 0 in the same root shape the controls use.
@MainActor
func controlTextSize(_ string: String) throws -> Size<Pixels> {
    let frame = try controlRender(controlRoot { Text(string) })
    return try #require(frame.elementBounds[controlID([0, 0])], "the text recorded no bounds").size
}

@MainActor
func controlBounds(_ frame: Frame, _ id: GlobalElementID) throws -> Bounds<Pixels> {
    try #require(frame.elementBounds[id], "\(id) recorded no bounds")
}

func controlKey(_ name: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0))
}

func controlCentre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: controlPx(b.origin.x.value + b.size.width.value / 2),
          y: controlPx(b.origin.y.value + b.size.height.value / 2))
}

@MainActor
func controlClick(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor
func controlRedraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

/// A window over `content`, bounds recorded, one frame drawn.
@MainActor
func controlWindow<Root: Element>(size: Int = 400, _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: size, content: content)
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// The last published tree after activating a client and drawing twice.
@MainActor
func controlTree(_ window: Window, _ platform: FakePlatformWindow) throws -> AccessibilityTree {
    platform.simulateAccessibilityRequest(.activate)
    controlRedraw(window)
    controlRedraw(window)
    return try #require(platform.publishedAccessibilityTrees.last, "no tree published")
}

@MainActor
final class ControlModel {
    var count = 0
    var keys: [String] = []
}

// MARK: - 1.1–1.2 layout (BT0, BT4, BT5)

/// **1.1.** `Button("Go")` is its label padded 12 a side, and 24 tall by its
/// strut (BT0: SwiftUI's 41×24 over a 17×16 label). Mutation M1a (padding 12 →
/// 11) must redden it.
@Test @MainActor func aButtonIsItsLabelPaddedTwelveASideAndTwentyFourTall() throws {
    let text = try controlTextSize("Go")
    let frame = try controlRender(controlRoot { Button("Go") {} })
    let button = try controlBounds(frame, controlID([0, 0]))
    let label = try controlBounds(frame, controlID([0, 0, 0]))
    #expect(button.size.width.value == text.width.value + 24,
            "textW + 2·12: \(button.size.width.value) vs \(text.width.value) + 24")
    #expect(button.size.height.value == max(text.height.value, 24))
    #expect(label.origin.x.value - button.origin.x.value == 12, "the label sits 12 in")
    #expect(label.size.width.value == text.width.value, "the label keeps its own width")
}

/// **1.2.** `controlSize` reaches the chrome — paddings 8/10/12/14/18 and
/// strut heights 13/20/24/28/36 (BT4 − BT5, halved) — but not the label's font
/// (divergence 76, amended): the label is the same size in every chrome. M1b
/// (the chrome reads `.regular` whatever the environment) must redden it.
@Test @MainActor func aButtonReadsControlSizeForItsChromeButNotItsLabelsFont() throws {
    let text = try controlTextSize("Go")
    let table: [(ControlSize, Float, Float)] = [
        (.mini, 8, 13), (.small, 10, 20), (.regular, 12, 24), (.large, 14, 28), (.extraLarge, 18, 36),
    ]
    var labelWidths: [Float] = []
    for (size, padding, height) in table {
        let frame = try controlRender(controlRoot { Button("Go") {}.controlSize(size) })
        let button = try controlBounds(frame, controlID([0, 0]))
        let label = try controlBounds(frame, controlID([0, 0, 0]))
        #expect(button.size.width.value == text.width.value + 2 * padding,
                "\(size): width textW + 2·\(padding), read \(button.size.width.value)")
        // The tallest child spans the button's edges, so this is exact.
        #expect(button.size.height.value == max(label.size.height.value, height),
                "\(size): height max(textH, \(height)), read \(button.size.height.value)")
        #expect(abs(label.size.height.value - text.height.value) <= 1, "\(size): the label's height")
        labelWidths.append(label.size.width.value)
    }
    #expect(Set(labelWidths).count == 1 && labelWidths.first == text.width.value,
            "the label is its unshrunk self at every size: \(labelWidths)")
}

// MARK: - 1.3–1.6 pointer and keys

@MainActor
private func buttonWindow(_ model: ControlModel, disabled: Bool = false,
                          onKey: (@MainActor (KeyEvent) -> Bool)? = nil) throws -> (Window, FakePlatformWindow) {
    try controlWindow {
        var button = Button("Go") { model.count += 1 }
        if let onKey { button = button.onKey(onKey) }
        return controlRoot { button.disabled(disabled) }
    }
}

/// **1.3.** A click runs the action once; a press inside released outside runs
/// nothing. M1c (`Button` leaves `onClick` unset) reddens it, 1.5, 1.7, 1.8
/// and both registry arms — not 1.4: the activation keys run the action
/// directly (`DD-AD` item 3).
@Test @MainActor func aButtonRunsItsActionOncePerClickAndNotOnAPressReleasedOutside() throws {
    let model = ControlModel()
    let (window, platform) = try buttonWindow(model)
    let button = try controlBounds(window.lastFrameBounds(), controlID([0, 0]))
    controlClick(platform, at: controlCentre(button))
    #expect(model.count == 1, "one click, one action")
    controlRedraw(window)
    platform.simulateInput(.mouseDown(MouseEvent(position: controlCentre(button))))
    platform.simulateInput(.mouseUp(MouseEvent(position: Point(x: controlPx(390), y: controlPx(5)))))
    #expect(model.count == 1, "a press released outside is not a click")
}

/// **1.4.** Activation keys (`DD-T`, `ControlKeys`): Space on Apple, Space and
/// Return elsewhere; through a real window on the host platform. M1d (Return
/// activates on Apple) must redden it.
@Test @MainActor func aFocusedButtonActivatesOnSpaceAndOnReturnOnlyOffApple() throws {
    func event(_ name: String, _ modifiers: Modifiers = []) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0)
    }
    #expect(ControlKeys.activatesButton(event(" "), platform: .mac))
    #expect(!ControlKeys.activatesButton(event("\r"), platform: .mac), "Return is not a Mac button's key")
    #expect(ControlKeys.activatesButton(event(" "), platform: .other))
    #expect(ControlKeys.activatesButton(event("\r"), platform: .other))
    #expect(!ControlKeys.activatesButton(event(" ", .command), platform: .mac), "no modifiers")
    #expect(!ControlKeys.activatesButton(event("a"), platform: .other))

    let model = ControlModel()
    let (window, platform) = try buttonWindow(model)
    let id = controlID([0, 0])
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "the button must take focus")
    platform.simulateInput(controlKey(" "))
    #expect(model.count == 1, "Space activates")
    platform.simulateInput(controlKey("\r"))
    #expect(model.count == (TextEditing.platform == .mac ? 1 : 2), "Return activates only off Apple")
}

/// **1.5.** A button is focusable, and a click does not focus it (the focus
/// rule stands; `DD-T` item 1). M1e (`isFocusable` false) must redden it.
@Test @MainActor func aButtonIsFocusableButAClickDoesNotFocusIt() throws {
    let model = ControlModel()
    let (window, platform) = try buttonWindow(model)
    let id = controlID([0, 0])
    #expect(window.lastFocusRegistry.isFocusable(id), "a button is focusable")
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    window.drawFrameIfNeeded()
    try #require(model.count == 1, "set up: the click landed")
    #expect(window.focusedElement == nil, "clicking does not focus")
}

/// **1.6.** A caller's `onKey` runs before the activation (spec §4): one that
/// claims Space suppresses the action; one that declines lets it run. M1f (the
/// activation replaces the caller's `onKey`) must redden it.
@Test @MainActor func aCallersOnKeyRunsBeforeTheButtonsActivation() throws {
    for claims in [true, false] {
        let model = ControlModel()
        let (window, platform) = try buttonWindow(model) { event in
            model.keys.append(event.charactersIgnoringModifiers)
            return claims
        }
        let id = controlID([0, 0])
        window.focus(id)
        window.drawFrameIfNeeded()
        try #require(window.focusedElement == id)
        platform.simulateInput(controlKey(" "))
        #expect(model.keys == [" "], "claims \(claims): the caller saw the key first")
        #expect(model.count == (claims ? 0 : 1), "claims \(claims): the activation ran only if declined")
    }
}

/// **1.6b.** A caller's `.onClick` on a `Button` **replaces** its action (spec
/// §4, the one-field rule): a click, a focused Space and an accessibility
/// `.press` each run the caller's handler once and the action never. V16
/// (`let activate = action`, the caller's `onClick` overwritten) must redden
/// it (`DD-AE` item 1).
@Test @MainActor func aCallersOnClickReplacesTheButtonsAction() throws {
    let model = ControlModel()
    let (window, platform) = try controlWindow {
        controlRoot { Button("Go") { model.count += 1 }.onClick { model.keys.append("caller") } }
    }
    let id = controlID([0, 0])
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    #expect(model.keys == ["caller"] && model.count == 0, "a click runs the caller's handler, not the action")
    controlRedraw(window)
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id)
    platform.simulateInput(controlKey(" "))
    #expect(model.keys == ["caller", "caller"] && model.count == 0, "Space runs what the click runs")
    let tree = try controlTree(window, platform)
    let button = try #require(tree.nodes.first { $0.value.role == .button }, "no button published")
    #expect(platform.simulateAccessibilityRequest(.press(button.key)))
    #expect(model.keys == ["caller", "caller", "caller"] && model.count == 0,
            "a press runs the caller's handler: \(model.keys), action ran \(model.count)")
}

// MARK: - 1.7–1.8 accessibility and disabled

/// **1.7.** One `.button`, labelled by its label, no children, `.press`; a
/// `.press` request runs the action once (BA0, BA2; `AB-G`'s fold — no
/// declared node). M1c must redden it.
@Test @MainActor func aButtonPublishesOneAXButtonLabelledByItsLabel() throws {
    let model = ControlModel()
    let (window, platform) = try buttonWindow(model)
    let tree = try controlTree(window, platform)
    let buttons = tree.nodes.filter { $0.value.role == .button }
    try #require(buttons.count == 1, "one button: \(tree.nodes.values.map(\.role))")
    let (nodeID, node) = try #require(buttons.first)
    #expect(node.label == "Go" && node.children.isEmpty && node.actions.contains(.press))
    #expect(tree.nodes.count == 1, "the label folds into the button; the strut says nothing")
    #expect(platform.simulateAccessibilityRequest(.press(nodeID)))
    #expect(model.count == 1, "a press runs the action once")
}

/// **1.8.** Disabled: a click, a focused Space and a `.press` all run nothing,
/// and the button publishes disabled (BA1). M1g (the `enabled` conjunct removed
/// from `Frame.registerHandlers`' hitbox insert and focus registration) must
/// redden it.
@Test @MainActor func aDisabledButtonRunsNothingAndPublishesDisabled() throws {
    let model = ControlModel()
    let (window, platform) = try buttonWindow(model, disabled: true)
    let id = controlID([0, 0])
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    window.focus(id)
    window.drawFrameIfNeeded()
    platform.simulateInput(controlKey(" "))
    let tree = try controlTree(window, platform)
    let button = try #require(tree.nodes.first { $0.value.role == .button })
    platform.simulateAccessibilityRequest(.press(button.key))
    #expect(model.count == 0, "nothing ran while disabled")
    #expect(window.focusedElement == nil, "a disabled button takes no focus")
    #expect(button.value.isEnabled == false, "published disabled")
}

extension Window {
    /// A frame's element bounds, as a `Frame`-shaped read for `controlBounds`.
    @MainActor func lastFrameBounds() -> ControlBoundsSource { ControlBoundsSource(bounds: lastElementBounds) }
}

struct ControlBoundsSource { let bounds: [GlobalElementID: Bounds<Pixels>] }

@MainActor
func controlBounds(_ source: ControlBoundsSource, _ id: GlobalElementID) throws -> Bounds<Pixels> {
    try #require(source.bounds[id], "\(id) recorded no bounds")
}
