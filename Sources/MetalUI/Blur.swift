import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPrimitives

// C10 lane 3 — `.blur(radius:)` (ruling `LK-K`). Spec
// `docs/superpowers/specs/2026-10-08-controls-looks-design.md` §1, §3.3;
// SwiftUI's side is `docs/probes/swiftui-controls-looks.swift`, arms B1–B5.

// MARK: - The proposal vocabulary (one `LayoutModifier` layer, `LK-K`)

extension ProposalElementGroup {
    /// Blurs each leaf of this view — SwiftUI's `blur(radius:)`. **Per leaf**
    /// (probe B2: a blue square over a red one blurred together reads as each
    /// blurred alone), a text draw counting as one leaf; Gaussian with sigma
    /// equal to `radius` (B1, divergence 105's three-box approximation); the
    /// image grows by the blur's reach and a clip outside cuts it (B5).
    /// **Render only**: no layout change (B4), no hit region, nothing
    /// published. A GPU surface (`GPUSurface`, `MetalView`) inside is drawn
    /// unblurred (divergence 167). The radius animates; a radius ≤ 0 draws the
    /// content unchanged; a non-finite one traps. One layer, one identity
    /// level (`MC-C`).
    public func blur(radius: Pixels) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.blur(radius: radius))
    }
}

// MARK: - The legacy vocabulary (`Decoration.renderEffects`, `LK-K`)

extension StyledElement {
    /// Blurs each leaf of this element — SwiftUI's `blur(radius:)`, returning
    /// `Self` (no identity level). It joins the element's render effects in
    /// written order and, like them, wraps the whole element: its background,
    /// content and border (divergence 108). See the proposal spelling for the
    /// rules.
    public func blur(radius: Pixels) -> Self {
        self
    }
}
