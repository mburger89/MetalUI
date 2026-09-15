import MetalUICore
import MetalUILayout
import MetalUIText

/// The proposal-layout bridge for ``Text`` during the layout migration.
///
/// `Text` remains a legacy styled leaf until its overlapping modifier surface
/// can be migrated without source ambiguity. This value preserves Text's font,
/// shaping-cache, and glyph-paint behavior while registering a native leaf, so
/// it can participate in an otherwise proposal-only subtree today.
public struct ProposalText: ProposalElement {
    public var string: String
    public var fontFamily: String?
    public var fontSize: Double
    public var foregroundColor: ColorToken?

    public init(_ string: String) {
        self.string = string
        fontFamily = nil
        fontSize = 13
        foregroundColor = nil
    }

    /// The face and size this run is shaped at.
    public func font(family: String? = nil, size: Double) -> ProposalText {
        var copy = self
        copy.fontFamily = family
        copy.fontSize = size
        return copy
    }

    /// The semantic token used to tint this run's glyphs.
    public func foregroundColor(_ token: ColorToken) -> ProposalText {
        var copy = self
        copy.foregroundColor = token
        return copy
    }

    public struct Layout { var node: LayoutNodeID }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let cache = pass.shapingCache
        let font = cache.resolveFont(family: fontFamily, size: fontSize)
        cache.registerFont(font)
        let key = font.key
        let string = string
        let node = pass.requestNativeLeaf { proposal in
            MainActor.assumeIsolated {
                guard let font = cache.font(for: key) else {
                    preconditionFailure("ProposalText registered no font for its proposal measurement")
                }
                return proposalTextMeasurement(string, font: font, cache: cache, proposal: proposal)
            }
        }
        return (node, Layout(node: node.layoutNodeID))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        let font = pass.shapingCache.resolveFont(family: fontFamily, size: fontSize)
        let width = max(pass.measuredWidth(of: layout.node), smallestWrapWidth)
        let shaped = pass.shapingCache.shaped(string, font: font, wrappingAt: width)
        let color = pass.theme[foregroundColor ?? .textPrimary]
        for glyph in shaped.placedGlyphs(
            at: (x: Double(bounds.origin.x.value), y: Double(bounds.origin.y.value)),
            font: font,
            scaleFactor: pass.scaleFactor
        ) {
            pass.draw(glyph, color: color)
        }
    }
}

/// Measures a text run from a SwiftUI-style proposal: a concrete width wraps
/// the run, while an unspecified width asks for its intrinsic one-line width.
/// The height proposal does not truncate or scale text, matching the measured
/// SwiftUI custom-Layout behavior.
@MainActor
func proposalTextMeasurement(_ string: String, font: ResolvedFont,
                             cache: ShapingCache, proposal: ProposedSize) -> LayoutMeasurement {
    let wrappingAt = proposal.width.map { max($0, smallestWrapWidth) }
    let shaped = cache.shaped(string, font: font, wrappingAt: wrappingAt)
    return LayoutMeasurement(size: SizeD(width: shaped.widestLine, height: shaped.totalHeight))
}

extension Text {
    /// Converts this run to the proposal-layout bridge without changing its
    /// font or foreground-token configuration.
    public func proposalLayout() -> ProposalText {
        var result = ProposalText(string)
        result.fontFamily = fontFamily
        result.fontSize = fontSize
        result.foregroundColor = foregroundColor
        return result
    }
}
