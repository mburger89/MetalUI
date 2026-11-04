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
/// (rulings CN-H, `DS-G` and its overturning `DS-G2`): nothing (a spacer's), the
/// standard 8, a text's own metrics, or **mixed**: a composite across its axis (or
/// an overlay) that holds both a standard and a text edge, which reads like a text
/// edge beside a standard neighbour and like a standard edge beside a text one
/// (probe `swiftui-default-spacing.swift` `DS9`, `DS9b`).
package enum SpacingEdge: Hashable, Sendable {
    case zero
    case standard
    case text(TextSpacingMetrics)
    /// A standard and a text edge together; the metrics are the largest font's.
    case mixed(TextSpacingMetrics)

    /// The edge of a composite whose children's edges are `edges`, where a zero
    /// child makes the composite's edge zero (a stack across its axis, a custom
    /// layout): else the union of `union(_:)`.
    package static func acrossUnion(_ edges: [SpacingEdge]) -> SpacingEdge {
        if edges.contains(.zero) { return .zero }
        return union(edges)
    }

    /// The edge of a composite where it is zero only when every child's is (a `ZStack`).
    package static func overlayUnion(_ edges: [SpacingEdge]) -> SpacingEdge {
        if edges.allSatisfy({ $0 == .zero }) { return .zero }
        return union(edges.filter { $0 != .zero })
    }

    /// Standard if only standard edges, the text edge of the largest font if only text
    /// edges, else mixed with the largest font's metrics (`DS9b`).
    private static func union(_ edges: [SpacingEdge]) -> SpacingEdge {
        var standard = false, text = false
        var largest: TextSpacingMetrics?
        for edge in edges {
            switch edge {
            case .zero: break
            case .standard: standard = true
            case .text(let metrics): text = true; largest = larger(largest, metrics)
            case .mixed(let metrics): standard = true; text = true; largest = larger(largest, metrics)
            }
        }
        guard text, let largest else { return .standard }
        return standard ? .mixed(largest) : .text(largest)
    }

    private static func larger(_ current: TextSpacingMetrics?, _ metrics: TextSpacingMetrics) -> TextSpacingMetrics {
        guard let current, current.extent >= metrics.extent else { return metrics }
        return current
    }

    /// A text or mixed edge turned standard (a fixed frame or a non-zero inset touches it, `DS8`).
    package var standardisingText: SpacingEdge {
        switch self {
        case .text, .mixed: return .standard
        case .zero, .standard: return self
        }
    }
}

extension ProposalSpacing {
    /// The default gap between a node whose trailing edge is `upper` and the next
    /// whose leading edge is `lower`, along `axis` (probe `swiftui-default-spacing.swift`,
    /// macOS 27.2; rulings `DS-E`, `DS-F`, `DS-G2`). With a = ascent, d = descent, c = capHeight,
    /// l = leading:
    ///
    /// - a zero edge on either side: 0;
    /// - **horizontal, or no text edge: 8**;
    /// - standard above text: `d + ceil((a + d) / 10)` of the lower text;
    /// - text above standard: that, from the upper text, `+ (a - c)`;
    /// - text above text: `ceil(l)` of the lower text;
    /// - **a mixed edge is a standard and a text component**: the gap is the largest of the
    ///   component pairs, except that two standard components alone are never counted when
    ///   either side is mixed (`DS9b`: `{rect; text}` beside a rect is the text above a rect,
    ///   a rect beside it the rect above a text, beside a text the standard above that text,
    ///   beside itself the larger of the two).
    package static func defaultGap(after upper: SpacingEdge, before lower: SpacingEdge,
                                   axis: ProposalStackAxis) -> Double {
        if upper == .zero || lower == .zero { return 0 }
        guard axis == .vertical else { return platformDefault }
        let involvesMixed: Bool
        if case .mixed = upper { involvesMixed = true } else if case .mixed = lower { involvesMixed = true } else { involvesMixed = false }
        var best: Double?
        for up in components(upper) {
            for low in components(lower) {
                if involvesMixed, up == nil, low == nil { continue }
                let gap: Double
                switch (up, low) {
                case (nil, nil): gap = platformDefault
                case (nil, let below?): gap = rectAboveText(below)
                case (let above?, nil): gap = rectAboveText(above) + (above.ascent - above.capHeight)
                case (_?, let below?): gap = below.leading.rounded(.up)
                }
                best = Swift.max(best ?? gap, gap)
            }
        }
        return best ?? platformDefault
    }

    /// An edge's components: nil is a standard one, a value a text one.
    private static func components(_ edge: SpacingEdge) -> [TextSpacingMetrics?] {
        switch edge {
        case .zero, .standard: return [nil]
        case .text(let metrics): return [metrics]
        case .mixed(let metrics): return [nil, metrics]
        }
    }

    private static func rectAboveText(_ metrics: TextSpacingMetrics) -> Double {
        metrics.descent + ((metrics.ascent + metrics.descent) / 10).rounded(.up)
    }
}
