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
    /// whole subtree faded once. `TextField`/`TextEditor` do not take it:
    /// SwiftUI's disabled field keeps its chrome unchanged and dims only its
    /// text (probe `swiftui-field-chrome.swift` `PX disabled` = `PX default`,
    /// `TX`; ruling `MD-E` item 3) — `FieldChrome.disabledTextFactor`.
    func paintControl(disabled: Bool, _ body: () -> Void) {
        if disabled { opacity(0.5, body) } else { body() }
    }
}

/// The field chrome's geometry and look (port gaps, medium, rulings `MD-D`,
/// `MD-E`, `MD-F`; probe `docs/probes/swiftui-field-chrome.swift`).
///
/// **Measured**: the insets — `NS roundedBorder`'s cell drawing rect (4, 4,
/// 112, 16) in a 120×24 frame plus AppKit's 2-point line-fragment padding is 6
/// leading/trailing and 4 top/bottom, matching `SZ`'s ideal of text + 12 by
/// line + 8; `CS1`'s small field insets 3.5 vertically — the corner radius
/// (`PX`'s corner curve spans ~12 device pixels at 2×: about 6 points), and the
/// disabled text at about a third (`TX`: #212121 enabled, #B5B5B5 disabled).
/// **MetalUI's choice**: the colours are theme tokens — `.surface`,
/// `.separator` — not AppKit's bezel (its outside edge and 97.6 % fill), and
/// the focus ring is the controls' ring (SwiftUI's is unmeasurable offscreen):
/// divergence 132.
enum FieldChrome {
    /// The bordered field's corner radius, in points (`MD-E` item 1).
    static let cornerRadius = Pixels(6)
    /// The leading and trailing inset of a bordered field's content (`MD-D`).
    static let horizontalInset = 6.0
    /// The alpha factor of a disabled bordered field's text, placeholder and
    /// caret (`MD-E` item 3); a `.plain` field takes none (`MD-W` item 1).
    static let disabledTextFactor: Float = 0.33

    /// The top and bottom inset of a bordered field's content at `size`: 3.5
    /// at `.small` (`CS1`), 4 otherwise (`MD-D` items 1 and 4).
    static func verticalInset(_ size: ControlSize) -> Double {
        size == .small ? 3.5 : 4
    }

    /// The content insets of a field drawn in `style` at `size`: `(0, 0)` for
    /// `.plain`.
    static func insets(_ style: TextFieldStyle, _ size: ControlSize) -> (horizontal: Double, vertical: Double) {
        style.isBordered ? (horizontalInset, verticalInset(size)) : (0, 0)
    }

    /// `bounds` inset by `insets` on each side, never negative.
    static func contentRect(_ bounds: Bounds<Pixels>,
                            _ insets: (horizontal: Double, vertical: Double)) -> Bounds<Pixels> {
        let h = Float(insets.horizontal), v = Float(insets.vertical)
        return Bounds(origin: Point(x: Pixels(bounds.origin.x.value + h), y: Pixels(bounds.origin.y.value + v)),
                      size: Size(width: Pixels(max(0, bounds.size.width.value - 2 * h)),
                                 height: Pixels(max(0, bounds.size.height.value - 2 * v))))
    }
}

extension PaintPass {
    /// A field's chrome around `content` (`MD-E`, `MD-F`): a `.surface` fill at
    /// `bounds` with corner `radius` — with a 1-point `.separator` border inside
    /// the bounds when `bordered` — then `content`, then the control focus ring
    /// (`controlRing(_:)`, `IX-H`) at the same radius while `focused`, unless the
    /// caller declared a `focusBorder` (`callerRing`), which wins through the
    /// decoration as on every control. Called only for a style that draws
    /// chrome (never `.plain`). Drawn inside `paintDecoration`'s content
    /// closure, so a caller's `.background` paints beneath it and a caller's
    /// `.border` over it (`DN-X`, `OM-AI` unchanged).
    func paintFieldChrome(bounds: Bounds<Pixels>, bordered: Bool, radius: Pixels, focused: Bool,
                          callerRing: Bool, _ content: () -> Void) {
        let radii = Corners(all: radius)
        if bordered {
            fill(bounds, color: resolve(Color(.surface)), cornerRadii: radii,
                 borderColor: resolve(Color(.separator)), borderWidths: Edges(all: Pixels(1)))
        } else {
            fill(bounds, color: resolve(Color(.surface)), cornerRadii: radii)
        }
        content()
        if focused && !callerRing {
            let ring = controlRing(environment)
            fill(bounds, color: .transparent, cornerRadii: radii,
                 borderColor: resolve(ring.color), borderWidths: ring.widths)
        }
    }
}
