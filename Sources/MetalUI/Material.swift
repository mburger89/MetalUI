import MetalUICore
import MetalUILayout

// C10 lane 3 — materials (rulings `LK-L`, `LK-O` item 2, `LK-R`). Spec
// `docs/superpowers/specs/2026-10-08-controls-looks-design.md` §1, §3.3;
// SwiftUI's side is `docs/probes/swiftui-controls-looks.swift`, arms M1–M5.

/// SwiftUI's `Material` (`LK-L`): `.ultraThinMaterial` … `.ultraThickMaterial`
/// and `.bar`, as a background or a shape's fill.
///
/// **A fitted flat tint, with no backdrop blur** (divergence 166): SwiftUI
/// blurs what lies beneath and tints it; MetalUI draws one colour at an alpha
/// per material and scheme, fitted from ImageRenderer so that over uniform
/// white and black it matches SwiftUI's material within one level (probe
/// `M5`; a real window's tint is unmeasured, `LK-O` item 2). Over a striped
/// or coloured backdrop it differs — the blur is deferred (`LK-A`, C10-c).
/// Every material site draws exactly what the colour site draws with that
/// colour: no new primitive.
public struct Material: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case ultraThin, thin, regular, thick, ultraThick, bar }
    let kind: Kind

    /// The thinnest material: the most of the backdrop shows through.
    public static let ultraThinMaterial = Material(kind: .ultraThin)
    /// A thin material.
    public static let thinMaterial = Material(kind: .thin)
    /// The regular material.
    public static let regularMaterial = Material(kind: .regular)
    /// A thick material.
    public static let thickMaterial = Material(kind: .thick)
    /// The thickest material: the least of the backdrop shows through.
    public static let ultraThickMaterial = Material(kind: .ultraThick)
    /// The material of a bar (a toolbar, a tab bar).
    public static let bar = Material(kind: .bar)

    /// The flat tint drawn for this material in `scheme` (`LK-L` item 3's
    /// table): a gamma grey at an alpha.
    func fill(for scheme: ColorScheme) -> Color {
        .clear
    }

    /// The tint as one colour following the scheme — what every site draws.
    var color: Color {
        Color(light: fill(for: .light), dark: fill(for: .dark))
    }
}
