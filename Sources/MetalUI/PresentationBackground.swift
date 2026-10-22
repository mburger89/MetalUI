import MetalUICore
import MetalUILayout

// Presentation extras, lane 1 (`BG-A`...`BG-F`, record 144; spec
// `docs/superpowers/specs/2026-10-22-presentation-extras-design.md`): SwiftUI's
// `presentationBackground(_:)` for MetalUI's one presentation that has a panel, the
// `.popover`. Like `navigationTitle` it is an `EnvironmentScope` that changes no value and
// reports to the frame after its content builds (`BG-B`); unlike it, the report is kept in a
// slot the presentation's own bracket opens and `AnchoredPresentation` reads, so a use
// outside a popover's content (the declarer, an in-flow tree) reports nothing (probe `B4`).

/// What a `.presentationBackground` reports: the fill of an enclosing popover's panel
/// (`BG-C`), or content drawn over it (`BG-E`).
struct PresentationBackgroundSpec {
    enum Kind {
        /// A colour or a colour token (resolved at paint, so a token follows the scheme).
        case color(Color)
        /// A material, drawn through `Frame.fillMaterial` (`MT-`).
        case material(Material)
        /// A linear or radial gradient, drawn through the gradient image path (`LK-J`).
        case gradient(GradientFill)
        /// Content proposed the panel's size and placed by `alignment`, as the content
        /// spelling of SwiftUI's `presentationBackground(alignment:content:)` (probe `B3`, `B8`).
        case content(alignment: ProposalAlignment, make: @MainActor () -> AnyElement)
    }
    var kind: Kind
}

extension PresentationBackgroundSpec {
    /// The id of the content spelling's node under a presentation's own id (`BG-E`): a name, never
    /// `-1` (`MC-P`) and never a `StateTable` slot.
    static let contentName = ElementID("$presentationbackground")
}

extension ElementGroup {
    /// Fills the panel of the popover this content is in with `color` -- SwiftUI's
    /// `presentationBackground(_:)` (ruling `BG-A`...`BG-D`, probe `swiftui-presentation-extras.swift`
    /// `B2`). The panel keeps its 1-pt border, its corner radius and its shadow (`B1`).
    ///
    /// **The innermost report wins** (`B7`), and a modifier written outside the popover's content
    /// -- on the declarer, or anywhere in the main tree -- does nothing (`B4`). An
    /// `anchoredOverlay` has no panel and ignores
    /// it; the drawn alert and menu panels are not views and never see it (`BG-A`).
    /// There is no `ShapeStyle` generic (divergence 119): each style is its own overload.
    public func presentationBackground(_ color: Color) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .presentationBackground(.init(kind: .color(color))))
    }

    /// The `ColorToken` spelling of the `Color` overload: the token resolves at paint,
    /// so it follows the colour scheme.
    @_disfavoredOverload
    public func presentationBackground(_ token: ColorToken) -> EnvironmentScope<Self> {
        presentationBackground(Color(token))
    }

    /// Fills the popover's panel with `material`: a backdrop blur and tint through `Frame.fillMaterial`
    /// (`MT-`), the border drawn over it as its own stroke. A material panel has **no drop shadow**
    /// (`BG-P`): a shadow scope would degrade the backdrop to its flat tint (`BB-H`, divergence 248).
    /// Under Reduce Transparency it is the opaque grey of the material, with the shadow.
    public func presentationBackground(_ material: Material) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .presentationBackground(.init(kind: .material(material))))
    }

    /// Fills the popover's panel with a linear gradient over the panel's rectangle.
    public func presentationBackground(_ gradient: LinearGradient) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .presentationBackground(.init(kind: .gradient(.linear(gradient)))))
    }

    /// Fills the popover's panel with a radial gradient over the panel's rectangle.
    public func presentationBackground(_ gradient: RadialGradient) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .presentationBackground(.init(kind: .gradient(.radial(gradient)))))
    }

    /// Draws `content` over the popover's panel fill and under its content -- SwiftUI's
    /// `presentationBackground(alignment:content:)` (probes `B3`, `B8`). The content is proposed the
    /// panel's size and placed by `alignment`; it never changes the panel's size, and is cut to the
    /// panel's rounded rectangle. Its node is the named child `$presentationbackground` of the
    /// presentation (`BG-E`), so its `@State` resets when the popover closes.
    public func presentationBackground<Background: ElementGroup>(
        alignment: ProposalAlignment = .center,
        @ProposalContentBuilder content: () -> Background
    ) -> EnvironmentScope<Self> {
        let background = content()
        return EnvironmentScope(content: self, write: .presentationBackground(.init(kind: .content(
            alignment: alignment, make: { AnyElement(Box(content: background)) }))))
    }
}

/// What `AnchoredPresentation` keeps of a content background between phases (`BG-E`).
struct PanelBackgroundContent {
    var element: AnyElement
    let id: GlobalElementID
    let node: LayoutNodeID
}
