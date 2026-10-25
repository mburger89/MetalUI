import MetalUICore
import MetalUILayout

// SwiftUI's Liquid Glass surface (rulings `LG-A`...`LG-M`; spec `docs/superpowers/specs/2026-10-23-liquid-glass-design.md`;
// probe `docs/probes/swiftui-liquid-glass.swift`). A glass is a `.backdrop` record with a glass tail (`LG-B`): the blurred
// backdrop under a fitted tint, with MetalUI's own lens and rim near the edge. SwiftUI has these APIs from macOS 26;
// MetalUI has no availability annotations.

/// SwiftUI's `Glass`: a glass effect's configuration. `.regular`, `.clear` and `.identity`, with a tint and an
/// interactive flag. `Equatable` and `Sendable`, **not** `Hashable`, and no public initialiser, as the SDK's (probe
/// A14, A15).
///
/// `.identity` draws nothing: a view with it renders exactly as the bare view (probe W2). A tint composites
/// source-over on the finished glass colour (`LG-E`), where SwiftUI's `regular.tint` was measured colour-independent
/// (divergence 825).
public struct Glass: Equatable, Sendable {
    enum Variant: Equatable, Sendable { case regular, clear, identity }

    let variant: Variant
    let tintColor: Color?
    let isInteractive: Bool

    init(variant: Variant, tintColor: Color? = nil, isInteractive: Bool = false) {
        self.variant = variant
        self.tintColor = tintColor
        self.isInteractive = isInteractive
    }

    /// The regular glass: a strong blur and tint of what is behind it.
    public static var regular: Glass { Glass(variant: .regular) }
    /// The clear glass: more of the backdrop shows through.
    public static var clear: Glass { Glass(variant: .clear) }
    /// No glass: the view is drawn as if the modifier were absent.
    public static var identity: Glass { Glass(variant: .identity) }

    /// This glass with `color` composited over it (`nil` removes a tint).
    public func tint(_ color: Color?) -> Glass {
        Glass(variant: variant, tintColor: color, isInteractive: isInteractive)
    }

    /// This glass responding to a press: on a control that registers its own pointer target (a `Button` with
    /// `.buttonStyle(.glass)`) the tint lifts while it is pressed (`LG-J`). On non-control content it is inert
    /// (divergence 827): a bare `glassEffect` registers no hitbox.
    public func interactive(_ isEnabled: Bool = true) -> Glass {
        Glass(variant: variant, tintColor: tintColor, isInteractive: isEnabled)
    }
}

/// SwiftUI's `GlassEffectTransition`: how a glass effect enters and leaves under a conditional. MetalUI draws all
/// three as the standard opacity transition (`.identity` snaps): there is no morph between shapes (`LG-K`, divergence
/// 828).
public struct GlassEffectTransition: Sendable {
    enum Kind: Sendable { case matchedGeometry, materialize, identity }
    let kind: Kind

    /// SwiftUI's matched-geometry transition; MetalUI cross-fades it (divergence 828).
    public static var matchedGeometry: GlassEffectTransition { GlassEffectTransition(kind: .matchedGeometry) }
    /// The glass fades in and out.
    public static var materialize: GlassEffectTransition { GlassEffectTransition(kind: .materialize) }
    /// No transition: the glass appears and disappears at once.
    public static var identity: GlassEffectTransition { GlassEffectTransition(kind: .identity) }

    var transition: AnyTransition { kind == .identity ? .identity : .opacity }
}

/// A `Hashable` box over a legacy glass background's glass and shape, so `Decoration` stays `Sendable, Hashable`
/// (`ClipShapeBox`'s precedent): `Glass` itself is not `Hashable` (probe A15).
struct GlassBox: Sendable, Hashable {
    let glass: Glass
    let shape: any Shape & Hashable

    init(_ glass: Glass, _ shape: some Shape & Hashable) {
        self.glass = glass
        self.shape = shape
    }

    static func == (lhs: GlassBox, rhs: GlassBox) -> Bool {
        lhs.glass == rhs.glass && glassSameShape(lhs.shape, rhs.shape)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(glass.variant == .regular ? 0 : glass.variant == .clear ? 1 : 2)
        hasher.combine(glass.tintColor)
        hasher.combine(glass.isInteractive)
        hasher.combine(ObjectIdentifier(type(of: shape)))
        shape.hash(into: &hasher)
    }
}

private func glassSameShape<A: Shape & Hashable>(_ lhs: A, _ rhs: any Shape & Hashable) -> Bool {
    guard let rhs = rhs as? A else { return false }
    return lhs == rhs
}

extension ProposalElementGroup {
    /// Draws `glass` in `shape` behind this subtree — SwiftUI's `glassEffect(_:in:)` (probe A4, A5, A9; no
    /// `isEnabled:`, the SDK has none, `LG-A`). The default shape is a capsule (SwiftUI's `DefaultGlassEffectShape`,
    /// probe P). One paint-only layer, like `.background(_:)`: no layout, hit-test or accessibility change.
    ///
    /// Inside a ``GlassEffectContainer`` the glass registers with the container and merges with its neighbours
    /// (`LG-G`). A `Path` shape draws its flat tint as that path's fill (divergence 829); under Reduce Transparency
    /// it is an opaque grey (`LG-F`).
    public func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S = Capsule())
        -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.glassEffect(glass, shape))
    }
}

extension StyledElement {
    /// Draws `glass` in `shape` behind this element, painted where a background is — the legacy spelling of
    /// ``ProposalElementGroup/glassEffect(_:in:)`` (a `Decoration` field, `Self` back; `LG-A`). `& Hashable` because
    /// `Decoration` is `Hashable`; every built-in shape is. It replaces a colour, gradient or material background
    /// written before it. A legacy element inside a ``GlassEffectContainer`` draws its own record and does not merge
    /// (`LG-U`). Not animated: a change snaps.
    public func glassEffect<S: Shape & Hashable>(_ glass: Glass = .regular, in shape: S = Capsule()) -> Self {
        decorating {
            $0.backgroundGlass = GlassBox(glass, shape)
            $0.background = nil; $0.backgroundGradient = nil; $0.backgroundMaterial = nil
            $0.noteWrite(.plainFill)
        }
    }
}

extension ElementGroup {
    /// Applies `transition` when a conditional or loop inserts or removes this group — SwiftUI's
    /// `glassEffectTransition(_:)`: `.materialize` and `.matchedGeometry` are the opacity transition, `.identity`
    /// snaps (`LG-K`, divergence 828).
    public func glassEffectTransition(_ transition: GlassEffectTransition) -> TransitionGroup<Self> {
        self.transition(transition.transition)
    }

    /// Tags the glass effects inside this group with `id` in `namespace` — SwiftUI's `glassEffectID(_:in:)`
    /// (probe A19; any `Hashable & Sendable` id, an optional one accepted). The tag is carried and read by nothing:
    /// MetalUI does not morph between shapes of one id (`LG-K`, divergence 828). Transparent: no node, no identity
    /// level.
    public func glassEffectID<ID: Hashable & Sendable>(_ id: ID?, in namespace: Namespace.ID)
        -> GlassTagScope<Self> {
        GlassTagScope(content: self, tag: GlassTag(id: id.map { AnyHashable($0) }, namespace: namespace, isUnion: false))
    }

    /// Joins the glass effects inside this group with the same `id` in `namespace` into one blob — SwiftUI's
    /// `glassEffectUnion(id:namespace:)`, read by the enclosing ``GlassEffectContainer`` (`LG-H`): the members merge
    /// **regardless of distance**, where SwiftUI measured one circle between them (divergence 826). A `nil` id joins
    /// nothing. Transparent: no node, no identity level.
    public func glassEffectUnion<ID: Hashable & Sendable>(id: ID?, namespace: Namespace.ID)
        -> GlassTagScope<Self> {
        GlassTagScope(content: self, tag: GlassTag(id: id.map { AnyHashable($0) }, namespace: namespace, isUnion: true))
    }
}
