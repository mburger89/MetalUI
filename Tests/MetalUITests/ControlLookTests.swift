import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12, part 1, lane 2 — the controls' disabled look, their key-window
// accent and their focus ring (rulings `IX-G` item 2, `IX-H`; spec §6, tests
// 2.10–2.12). SwiftUI's disabled look and ring are unmeasured (`PX2`, `PX6`,
// `PX8`, `PX10`, `PX12`, `F7` = `F8`), so both are MetalUI's choice; the accent
// rule is measured for `.key` against `.inactive` (`PX17`–`PX20`) and `.active`
// is MetalUI's (never measured: the probe's process is never active, `PX23`).

// MARK: - Fixtures

/// Every control the looks cover, each in a fixed state so a render is
/// deterministic: `Button` in its four styles, an on `Toggle`, a half-full
/// `Slider`, a bounded `Stepper` and a radio-group `Picker` with a selection.
@MainActor
private enum LookControl: CaseIterable {
    case buttonAutomatic, buttonBordered, buttonBorderless, buttonPlain, toggle, slider, stepper, picker

    /// The control in a `controlRoot`, `disabled` or not.
    func root(disabled: Bool) -> any Element {
        switch self {
        case .buttonAutomatic: wrap(Button("Go") {}.buttonStyle(.automatic), disabled)
        case .buttonBordered: wrap(Button("Go") {}.buttonStyle(.bordered), disabled)
        case .buttonBorderless: wrap(Button("Go") {}.buttonStyle(.borderless), disabled)
        case .buttonPlain: wrap(Button("Go") {}.buttonStyle(.plain), disabled)
        case .toggle: wrap(Toggle("Wi-Fi", isOn: .constant(true)), disabled)
        case .slider: wrap(Slider(value: .constant(0.5)), disabled)
        case .stepper: wrap(Stepper("Qty", value: .constant(1), in: 0...3), disabled)
        case .picker:
            wrap(Picker("Size", selection: .constant(1)) {
                Text("S").tag(0)
                Text("M").tag(1)
            }.pickerStyle(.radioGroup), disabled)
        }
    }

    private func wrap<E: Element>(_ element: E, _ disabled: Bool) -> any Element {
        disabled ? controlRoot { element.disabled(true) } : controlRoot { element }
    }
}

/// A window over one fixed root value (the existential opened here).
@MainActor
private func lookWindow<E: Element>(_ root: E) throws -> (Window, FakePlatformWindow) {
    try controlWindow { root }
}

// MARK: - 2.10 disabled

/// **2.10** (`IX-G` item 2). Under `.disabled(true)` each built-in control
/// paints its whole subtree inside one `PaintPass.opacity(0.5)` scope: the
/// same primitives at the same places, every alpha halved; enabled, it paints
/// no such scope (the bordered fill at its token's own alpha). M2j (the scope
/// gated on `!isFocused` instead of `!isEnabled`) reddens every control.
@Test @MainActor func aDisabledControlPaintsInsideOneHalfOpacityScope() throws {
    for control in LookControl.allCases {
        let enabled = try controlRender(control.root(disabled: false)).finalizedScene()
        let disabled = try controlRender(control.root(disabled: true)).finalizedScene()
        try #require(!enabled.rects.isEmpty || !enabled.glyphs.isEmpty, "\(control) paints something")
        try #require(enabled.rects.count == disabled.rects.count, "\(control): the same rects")
        try #require(enabled.glyphs.count == disabled.glyphs.count, "\(control): the same glyphs")
        for (e, d) in zip(enabled.rects, disabled.rects) {
            #expect(ixBounds(e) == ixBounds(d), "\(control): a rect moved")
            #expect(abs(d.background.a - e.background.a * 0.5) < 1e-5,
                    "\(control): a fill at \(d.background.a), not half of \(e.background.a)")
            #expect(abs(d.borderColor.a - e.borderColor.a * 0.5) < 1e-5, "\(control): a border not halved")
        }
        for (e, d) in zip(enabled.glyphs, disabled.glyphs) {
            #expect(abs(d.color.a - e.color.a * 0.5) < 1e-5, "\(control): a glyph not halved")
        }
    }
    // Enabled paints no scope: the bordered chrome's fill is its token's alpha.
    let bordered = try controlRender(LookControl.buttonBordered.root(disabled: false)).finalizedScene()
    let fill = try #require(bordered.rects.first, "the bordered chrome fills")
    #expect(abs(fill.background.a - Theme.light[.surfaceSecondary].a) < 1e-5, "enabled: no opacity scope")
}

// MARK: - 2.11 accent

/// The rects filled with `token`'s colour.
@MainActor
private func filled(_ window: Window, _ token: ColorToken) -> [MUIRect] {
    let colour = window.theme[token]
    return window.lastScene.rects.filter { ixSame(ixHsla($0.background), colour) }
}

/// **2.11** (PX17/PX19: accent with `controlActiveState` `.key`; PX18/PX20: no
/// accent pixel with `.inactive`; `.active` is MetalUI's, treated as not key).
/// `Toggle`'s on indicator, `Slider`'s filled track and a radio `Picker`'s
/// selected circle paint `.accent` only in the key window and `.separator`
/// otherwise, driven through the platform window's active-state change. M2k
/// (`!= .inactive` in place of `== .key`) reddens the `.active` arm.
@Test @MainActor func aControlsAccentIsPaintedOnlyInTheKeyWindow() throws {
    let (window, platform) = try controlWindow {
        Column {
            Toggle("Wi-Fi", isOn: .constant(true))
            Slider(value: .constant(0.5))
            Picker("Size", selection: .constant(1)) {
                Text("S").tag(0)
                Text("M").tag(1)
            }.pickerStyle(.radioGroup)
        }.cssWidth(controlPx(400)).cssHeight(controlPx(200))
    }
    window.theme = .light
    for state in [ControlActiveState.key, .active, .inactive, .key] {
        platform.simulateControlActiveStateChange(to: state)
        controlRedraw(window)
        let accent = filled(window, .accent)
        let separatorDots = filled(window, .separator).filter {
            $0.bounds.size.width == 14 && $0.bounds.size.height == 14
        }
        if state == .key {
            #expect(accent.count == 3, "key: the indicator, the fill and the selected radio are accent (\(accent.count))")
            #expect(separatorDots.isEmpty, "key: no 14-pt mark is .separator")
        } else {
            #expect(accent.isEmpty, "\(state): no accent pixel (PX18, PX20), found \(accent.count)")
            #expect(separatorDots.count == 2, "\(state): the indicator and the selected radio are .separator")
        }
    }
}

// MARK: - 2.12 ring

/// **2.12** (`IX-H` item 2; SwiftUI's ring unmeasured). Each of the five
/// focusable controls draws a 2-pt ring in the key accent around its own box
/// while focused, and none while not; in a non-key window the focused ring
/// is `.separator` (`controlAccent(_:)`). M2l (the ring's token `.separator`
/// always) reddens every control; V10 (the ring `.accent` always) reddens the
/// `.inactive` arm.
@Test @MainActor func aFocusedControlDrawsItsRingAndAnUnfocusedOneDoesNot() throws {
    for control in [LookControl.buttonAutomatic, .toggle, .stepper, .picker, .slider] {
        let (window, platform) = try lookWindow(control.root(disabled: false))
        window.theme = .light
        controlRedraw(window)
        let id = controlID([0, 0])
        let box = try #require(window.lastElementBounds[id], "\(control)'s bounds")
        let accent = window.theme[.accent]
        func rings() -> [MUIRect] {
            window.lastScene.rects.filter {
                ixSame(ixHsla($0.borderColor), accent) && $0.borderWidths.top == 2 && $0.borderWidths.left == 2
            }
        }
        #expect(rings().isEmpty, "\(control) unfocused: no ring")
        window.focus(id)
        controlRedraw(window)
        try #require(window.focusedElement == id, "\(control) takes focus")
        let ring = rings()
        #expect(ring.count == 1, "\(control) focused: one ring (\(ring.count))")
        if let r = ring.first { #expect(ixBounds(r) == box, "\(control): the ring is the control's own box") }
        platform.simulateControlActiveStateChange(to: .inactive)
        controlRedraw(window)
        let separator = window.theme[.separator]
        let inactiveRings = window.lastScene.rects.filter {
            ixSame(ixHsla($0.borderColor), separator) && $0.borderWidths.top == 2 && $0.borderWidths.left == 2
        }
        #expect(rings().isEmpty, "\(control) focused, inactive window: no accent ring")
        #expect(inactiveRings.count == 1, "\(control) focused, inactive window: one .separator ring")
        platform.simulateControlActiveStateChange(to: .key)
        controlRedraw(window)
        window.focus(nil)
        controlRedraw(window)
        #expect(rings().isEmpty, "\(control) unfocused again: no ring")
    }
}
