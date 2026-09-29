import MetalUICore

// Plan task 12 part 1, lane 2 — the built-in controls' shared looks (rulings
// `IX-G` item 2, `IX-H`): the key-window accent, the focus ring and the
// disabled scope, in one place so `Button`, `Toggle`, `Slider`, `Stepper` and
// `Picker` cannot disagree. **Every look here is MetalUI's choice** except the
// accent's `.key`/`.inactive` split: SwiftUI's disabled look and focus ring
// are unmeasured (the probe's offscreen capture draws no text or ring, `PX2`,
// `F7` = `F8`).

/// The token a control paints its accent in: `.accent` when the window is key,
/// `.separator` otherwise (`IX-H` item 1; probe `swiftui-interaction` PX17 and
/// PX19 read accent at `.key`, PX18 and PX20 none at `.inactive`; `.active` —
/// never measured, the probe's process is never active — is treated as not
/// key). Every offscreen harness and fake window reads `.key`, so no existing
/// pixel moves.
func controlAccent(_ environment: EnvironmentValues) -> ColorToken {
    environment.controlActiveState == .key ? .accent : .separator
}

/// The focus ring a built-in control draws while focused (`IX-H` item 2): a
/// 2-point border in the accent colour of `controlAccent(_:)`, resolved through
/// `Decoration.focusBorder` — so it outranks the control's own border only
/// while focused, and a disabled control, which is never focused (`EV-F`),
/// never draws it. A caller's own `focusBorder` wins.
func controlRing(_ environment: EnvironmentValues) -> BorderStyle {
    BorderStyle(controlAccent(environment), width: Pixels(2))
}

extension PaintPass {
    /// Runs `body` inside one `opacity(0.5)` scope when `disabled`, and bare
    /// otherwise — a built-in control's disabled look (`IX-G` item 2), the
    /// whole subtree faded once. `TextField`/`TextEditor` do not take it.
    func paintControl(disabled: Bool, _ body: () -> Void) {
        if disabled { opacity(0.5, body) } else { body() }
    }
}
