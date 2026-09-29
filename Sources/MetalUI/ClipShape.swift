import MetalUICore
import MetalUILayout

// Clipping to a shape and backgrounds in a shape (plan task 11, part 2;
// rulings `TE-AJ`, `TE-AK`, `TE-AQ` items 3–5).

extension ProposalElementGroup {
    /// Clips this subtree to `shape`'s geometry in its bounds — SwiftUI's
    /// `clipShape(_:)` (probes C2, C7). One paint-only layer, like
    /// ``clip(cornerRadius:)``: it changes no layout (C8), and a hitbox inside
    /// is clipped to the geometry's **bounding rect** (MetalUI's existing rule,
    /// `TE-AQ` item 4). An ellipse geometry traps (divergence 91).
    public func clipShape<S: Shape>(_ shape: S) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.clipShape(shape))
    }

    /// Clips this subtree to its bounds — SwiftUI's `clipped()` (probe C3);
    /// ``clip(cornerRadius:)`` with no radius.
    public func clipped() -> ModifiedContent<ProposalBase, LayoutModifier> {
        clip()
    }

    /// Clips this subtree to a rounded rectangle — SwiftUI's
    /// `cornerRadius(_:)`, which is `clipShape(RoundedRectangle(cornerRadius:))`
    /// (probes C1, C4). The legacy `StyledElement.cornerRadius(_:)` stays
    /// paint-only (divergence 47, `TE-AJ` item 3).
    public func cornerRadius(_ radius: Pixels) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.clipShape(Rectangle()))
    }
}

extension StyledElement {
    /// Clips this element's children to `shape`'s geometry in its own box —
    /// the legacy `clipShape(_:)` (`TE-AJ` item 2). A `Decoration` field,
    /// returning `Self`: no layer and no identity level. `& Hashable` because
    /// `Decoration` is `Hashable` (`TE-AQ` item 3); every built-in shape is.
    /// It clips hitboxes as ``clipped()`` does, snaps under animation, and an
    /// ellipse geometry traps (divergence 91).
    public func clipShape<S: Shape & Hashable>(_ shape: S) -> Self {
        self
    }
}

/// A `Hashable` box over a legacy `clipShape`'s shape, so `Decoration` stays
/// `Sendable, Hashable` (`TE-AQ` item 3).
struct ClipShapeBox: Sendable, Hashable {
    let shape: any Shape & Hashable

    init(_ shape: some Shape & Hashable) {
        self.shape = shape
    }

    static func == (lhs: ClipShapeBox, rhs: ClipShapeBox) -> Bool {
        sameShape(lhs.shape, rhs.shape)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type(of: shape)))
        shape.hash(into: &hasher)
    }
}

private func sameShape<A: Shape & Hashable>(_ lhs: A, _ rhs: any Shape & Hashable) -> Bool {
    guard let rhs = rhs as? A else { return false }
    return lhs == rhs
}

extension ElementGroup {
    /// Places `shape`, filled with `token`, behind this view — SwiftUI's
    /// `background(_:in:)`, the same as `background { shape.fill(token) }`
    /// (probe O2, 0 px).
    public func background<S: Shape>(_ token: ColorToken, in shape: S)
        -> BackgroundModifier<Self, ShapeView<S>> {
        BackgroundModifier(content: self) { shape.fill(token) }
    }

    /// Places `shape`, filled with the window's canvas token `.background`,
    /// behind this view — SwiftUI's `background(in:)`, whose default style
    /// paints (probe O6, `TE-AQ` item 5).
    public func background<S: Shape>(in shape: S) -> BackgroundModifier<Self, ShapeView<S>> {
        BackgroundModifier(content: self) { shape.fill(.surface) }
    }
}
