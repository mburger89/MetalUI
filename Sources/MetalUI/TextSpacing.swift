import MetalUILayout
import MetalUITextSystem

// The text edge of the default stack and grid spacing (rulings `DS-E`..`DS-H`, record 203).
//
// A text leaf hands the layout tree its resolved font's metrics as plain doubles when it registers
// (`Frame.markTextSpacing`); the kernel's edge walk (`LayoutTree.spacingEdges`) reads them and
// `ProposalSpacing.defaultGap(after:before:axis:)` decides the gap. Nothing in a layout phase reads the
// environment or the text system.

/// The spacing metrics of a font (`DS-F`): `capHeight` nil removes the cap term.
func textSpacingMetrics(_ metrics: TextFontMetrics) -> TextSpacingMetrics {
    TextSpacingMetrics(ascent: metrics.ascent, descent: metrics.descent, leading: metrics.leading,
                       capHeight: metrics.capHeight)
}

/// The vertical edge of a plain text: its font's metrics, or zero for an empty string (probe `DS6`).
@MainActor
func textSpacingEdge(font: FontKey, string: String, system: any TextSystem) -> SpacingEdge {
    string.isEmpty ? .zero : .text(textSpacingMetrics(system.fontMetrics(font)))
}

/// The vertical edge of a styled text: the largest of its runs' fonts (probe `DS6` `mixedSum`), or zero
/// for an empty string.
@MainActor
func richTextSpacingEdge(_ resolved: ResolvedRichText, system: any TextSystem) -> SpacingEdge {
    guard !resolved.text.string.isEmpty else { return .zero }
    var largest: TextSpacingMetrics?
    for run in resolved.text.runs {
        let metrics = textSpacingMetrics(system.fontMetrics(run.style.font))
        if metrics.extent > (largest?.extent ?? -1) { largest = metrics }
    }
    return largest.map { .text($0) } ?? .standard
}

extension Frame {
    /// Marks a text leaf's vertical default-spacing edge (`DS-E`).
    func markTextSpacing(_ node: LayoutNodeID, _ edge: SpacingEdge) {
        tree.markTextSpacing(node, edge)
    }

    /// Makes a control's root node opaque to the default-spacing walk: it presents the standard edge on
    /// both axes whatever text it holds (probe `DS7`; `DS-H`), while the gaps inside it stay the text rule's.
    /// Returns `node` for chaining.
    @discardableResult
    func markControlSpacing(_ node: LayoutNodeID) -> LayoutNodeID {
        tree.markControlSpacing(node)
        return node
    }
}
