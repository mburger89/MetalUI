import MetalUICore

// Hierarchical styles (round 4 item R4-4 PR A, rulings `HY-`, divergence 119 retired): `.secondary` as a
// factor of the style a view inherits, as SwiftUI's `HierarchicalShapeStyle`. Probe
// `swiftui-hierarchical-paint.swift` records the readings every constant here comes from.

/// A level of the style a view inherits — SwiftUI's `HierarchicalShapeStyle` (ruling `HY-A`).
///
/// `.foregroundStyle(.secondary)` is not the grey `Color.secondary`: it is a **factor of the parent style**.
/// Under a red parent the five levels are red at 1, .5, .25, .18 and .18 of its alpha (probe `RL1`…`RL5`,
/// `RD1`…`RD5`); with no parent they are the theme's text colour at SwiftUI's own label alphas (`NL`, `ND`).
/// Levels never compound (two `.secondary` are one), a `Color` is never a level (`Color.secondary` stays the
/// grey under any parent), and every sink reads the parent: `fill`, `stroke`, `strokeBorder`, `background`,
/// `border` and `foregroundStyle`.
///
/// A leading-dot `.secondary` infers this type at every site that takes a generic `some ShapeStyle` because
/// `Color.primary` and `Color.secondary` are `@_disfavoredOverload` members (`HY-C`): the generic solution
/// `S == HierarchicalShapeStyle` carries no disfavoured member and beats the concrete `Color` overload's
/// solution that carries one. No sink's overloads changed. Write `Color.secondary`, a `Color` value or
/// `foregroundColor(.secondary)` for the grey. A gradient or material parent is lowered to its first stop or flat
/// tint before the factor applies (divergence 975); `foregroundStyle(_:_:)` and the instance members
/// `ShapeStyle.secondary` stay carried (`SS-G`). Unlike SwiftUI's it is `Equatable`, so an erased level compares
/// equal to itself and a retained subtree holding one stays retained (`AnyShapeStyle`).
public struct HierarchicalShapeStyle: ShapeStyle, Equatable, Sendable {
    /// Which of the five levels a style is.
    enum Level: Int, Hashable, Sendable {
        case primary, secondary, tertiary, quaternary, quinary

        /// The level's alpha factor: over a parent (`RL`/`RD`: 1, .5, .25, .18, .18, the same in both schemes),
        /// or over nothing, the theme's text colour times SwiftUI's label alphas divided by the primary's
        /// .847 (`NL`: 1, .588, .306, .116, .0555; `ND`: 1, .648, .292, .116, .0555).
        func factor(overParent: Bool, scheme: ColorScheme) -> Float {
            if overParent {
                switch self {
                case .primary: return 1
                case .secondary: return 0.5
                case .tertiary: return 0.25
                case .quaternary, .quinary: return 0.18
                }
            }
            switch (self, scheme) {
            case (.primary, _): return 1
            case (.secondary, .dark): return 0.648
            case (.secondary, _): return 0.588
            case (.tertiary, .dark): return 0.292
            case (.tertiary, _): return 0.306
            case (.quaternary, _): return 0.116
            case (.quinary, _): return 0.0555
            }
        }
    }

    let level: Level

    init(_ level: Level) { self.level = level }

    /// The most prominent level: the inherited style itself.
    public static let primary = HierarchicalShapeStyle(.primary)
    /// The second level: half the inherited style's alpha.
    public static let secondary = HierarchicalShapeStyle(.secondary)
    /// The third level: a quarter of the inherited style's alpha.
    public static let tertiary = HierarchicalShapeStyle(.tertiary)
    /// The fourth level: .18 of the inherited style's alpha.
    public static let quaternary = HierarchicalShapeStyle(.quaternary)
    /// The fifth level: .18 of the inherited style's alpha, as SwiftUI's.
    public static let quinary = HierarchicalShapeStyle(.quinary)

    /// This level over the style `environment` inherits, resolved (`HY-B`).
    public func resolve(in environment: EnvironmentValues) -> ResolvedShapeStyle {
        ResolvedShapeStyle(.color(Color(level: level, over: environment.foregroundStyle)))
    }
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    /// The most prominent level of the inherited style.
    public static var primary: HierarchicalShapeStyle { HierarchicalShapeStyle(.primary) }
    /// The second level of the inherited style.
    public static var secondary: HierarchicalShapeStyle { HierarchicalShapeStyle(.secondary) }
    /// The third level of the inherited style.
    public static var tertiary: HierarchicalShapeStyle { HierarchicalShapeStyle(.tertiary) }
    /// The fourth level of the inherited style.
    public static var quaternary: HierarchicalShapeStyle { HierarchicalShapeStyle(.quaternary) }
    /// The fifth level of the inherited style.
    public static var quinary: HierarchicalShapeStyle { HierarchicalShapeStyle(.quinary) }
}
