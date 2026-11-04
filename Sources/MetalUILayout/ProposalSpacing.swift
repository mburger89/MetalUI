/// SwiftUI's platform-default stack spacing and `Spacer` minimum on macOS.
///
/// `Spacer()`'s nil minimum is this constant, not the gap its neighbours would
/// get (probe `docs/probes/swiftui-stack-algorithms.swift` SP1, SP6, K1;
/// ruling CN-C in `docs/superpowers/2026-09-16-containers-decisions.md`),
/// and it stays 8 between two texts at every size (probe
/// `swiftui-default-spacing.swift` `DS11`).
/// It is also the default stack spacing between two views (S; ruling CN-H):
/// a linear stack registered with `spacing: nil` puts it between each adjacent
/// pair that has no zero-spacing edge (a spacer's, through its wrappers),
/// **except at a vertical text edge**, where the gap is the font's own
/// (``defaultGap(after:before:axis:)``, rulings `DS-E`..`DS-H`).
public enum ProposalSpacing {
    /// 8 points.
    public static let platformDefault: Double = 8
}

/// The four font metrics the default vertical gap at a text edge reads, in
/// points, captured when a text leaf registers (rulings `DS-E`, `DS-F`): plain
/// doubles, so `MetalUILayout` imports no text module and no layout phase reads
/// the environment.
package struct TextSpacingMetrics: Hashable, Sendable {
    /// Distance from the baseline to the top of the line.
    package var ascent: Double
    /// Distance from the baseline to the bottom of the line, positive.
    package var descent: Double
    /// The font's line gap.
    package var leading: Double
    /// The cap height; equal to `ascent` when the font does not report one, which
    /// removes the cap term (`DS-F` item 1).
    package var capHeight: Double

    package init(ascent: Double, descent: Double, leading: Double, capHeight: Double?) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
        self.capHeight = capHeight ?? ascent
    }

    /// The size used to pick the larger of two text edges (`DS9`: the larger font's wins).
    package var extent: Double { ascent + descent }
}

/// What one edge of a node takes from the default spacing along a stack's axis
/// (rulings CN-H and `DS-G`): nothing (a spacer's), the standard 8, or a
/// text's own metrics.
package enum SpacingEdge: Hashable, Sendable {
    case zero
    case standard
    case text(TextSpacingMetrics)

    /// The edge of a composite whose children's edges are `edges`, where a zero
    /// child makes the composite's edge zero (a stack across its axis, a custom
    /// layout): else the text edge of the largest font, else the standard one
    /// (`DS9`).
    package static func acrossUnion(_ edges: [SpacingEdge]) -> SpacingEdge {
        if edges.contains(.zero) { return .zero }
        return best(edges)
    }

    /// The edge of a composite where it is zero only when every child's is (a `ZStack`).
    package static func overlayUnion(_ edges: [SpacingEdge]) -> SpacingEdge {
        if edges.allSatisfy({ $0 == .zero }) { return .zero }
        return best(edges.filter { $0 != .zero })
    }

    /// The text edge of the largest font among `edges` (the first on a tie), else standard.
    private static func best(_ edges: [SpacingEdge]) -> SpacingEdge {
        var chosen: TextSpacingMetrics?
        for case .text(let metrics) in edges where metrics.extent > (chosen?.extent ?? -1) { chosen = metrics }
        return chosen.map { .text($0) } ?? .standard
    }

    /// A text edge turned standard (a fixed frame or a non-zero inset touches it, `DS8`).
    package var standardisingText: SpacingEdge {
        if case .text = self { return .standard }
        return self
    }
}

extension ProposalSpacing {
    /// The default gap between a node whose trailing edge is `upper` and the next
    /// whose leading edge is `lower`, along `axis` (probe `swiftui-default-spacing.swift`,
    /// macOS 27.2; rulings `DS-E`, `DS-F`). With a = ascent, d = descent, c = capHeight,
    /// l = leading:
    ///
    /// - a zero edge on either side: 0;
    /// - **horizontal, or no text edge: 8**;
    /// - standard above text: `d + ceil((a + d) / 10)` of the lower text;
    /// - text above standard: that, from the upper text, `+ (a - c)`;
    /// - text above text: `ceil(l)` of the lower text.
    package static func defaultGap(after upper: SpacingEdge, before lower: SpacingEdge,
                                   axis: ProposalStackAxis) -> Double {
        if upper == .zero || lower == .zero { return 0 }
        guard axis == .vertical else { return platformDefault }
        switch (upper, lower) {
        case (.text, .text(let below)):
            return below.leading.rounded(.up)
        case (.standard, .text(let below)):
            return rectAboveText(below)
        case (.text(let above), .standard):
            return rectAboveText(above) + (above.ascent - above.capHeight)
        default:
            return platformDefault
        }
    }

    private static func rectAboveText(_ metrics: TextSpacingMetrics) -> Double {
        metrics.descent + ((metrics.ascent + metrics.descent) / 10).rounded(.up)
    }
}
