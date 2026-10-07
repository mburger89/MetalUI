import MetalUICore
import MetalUILayout

// Ruling `PE-F` item 1 (`docs/superpowers/2026-10-06-proposal-controls-decisions.md`):
// the proposal-only modifiers a control needs in a SwiftUI stack —
// `layoutPriority`, `fixedSize` and the four grid-cell modifiers — on legacy
// content. Each adopts the receiver as `LegacyContent` (`PE-C`) and applies the
// `ProposalElementGroup` spelling, so the result is one proposal layer over a
// legacy element (`LR-T`): in a proposal container exactly what the same
// modifier on proposal content is, and in a legacy container a new capability,
// not a change.
//
// **No name here exists on `StyledElement` or `ElementGroup`** (spec §1.1), so
// nothing becomes ambiguous; on proposal content the `ProposalElementGroup`
// spelling wins by refinement, as `.frame` already does. Not offered:
// `aspectRatio`/`scaledToFit`/`scaledToFill` (no control needs them, spec §11).

extension ElementGroup {
    /// SwiftUI's `layoutPriority(_:)` on legacy content: a stack serves this
    /// subtree before lower priorities when it must divide less main-axis space
    /// than its children ask. NaN traps (SA-J); ±∞ is accepted.
    public func layoutPriority(_ value: Double) -> ModifiedContent<LegacyContent<Self>, LayoutModifier> {
        LegacyContent(self).layoutPriority(value)
    }

    /// SwiftUI's `fixedSize(horizontal:vertical:)` on legacy content: the named
    /// axes are proposed `nil`, so the content takes its ideal size there.
    public func fixedSize(horizontal: Bool = true, vertical: Bool = true)
        -> ModifiedContent<LegacyContent<Self>, LayoutModifier> {
        LegacyContent(self).fixedSize(horizontal: horizontal, vertical: vertical)
    }

    /// SwiftUI's `gridCellColumns(_:)` on legacy content: how many columns this
    /// cell spans (`GR-O` 3, `GR-S`).
    public func gridCellColumns(_ count: Int) -> GridCellModifier<LegacyContent<Self>> {
        LegacyContent(self).gridCellColumns(count)
    }

    /// SwiftUI's `gridCellAnchor(_:)` on legacy content, the nine-point spelling.
    public func gridCellAnchor(_ anchor: ProposalAlignment) -> GridCellModifier<LegacyContent<Self>> {
        LegacyContent(self).gridCellAnchor(anchor)
    }

    /// SwiftUI's `gridCellAnchor(_:)` on legacy content with a `UnitPoint`;
    /// disfavoured so a nine-point leading-dot spelling stays unambiguous
    /// (`DD-P` item 4).
    @_disfavoredOverload
    public func gridCellAnchor(_ anchor: UnitPoint) -> GridCellModifier<LegacyContent<Self>> {
        LegacyContent(self).gridCellAnchor(anchor)
    }

    /// SwiftUI's `gridColumnAlignment(_:)` on legacy content: the horizontal
    /// alignment of this cell's column (the first declaration wins, GL6).
    public func gridColumnAlignment(_ alignment: HorizontalAlignment) -> GridCellModifier<LegacyContent<Self>> {
        LegacyContent(self).gridColumnAlignment(alignment)
    }

    /// SwiftUI's `gridCellUnsizedAxes(_:)` on legacy content: the named axes are
    /// proposed this cell's current slot (`GR-H`).
    public func gridCellUnsizedAxes(_ axes: ProposalAxes) -> GridCellModifier<LegacyContent<Self>> {
        LegacyContent(self).gridCellUnsizedAxes(axes)
    }
}
