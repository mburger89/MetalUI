import MetalUICore
import MetalUILayout
#if canImport(MetalUIText)
import MetalUIText
#endif
import MetalUITextSystem

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
        let system = pass.textSystem
        let key = system.resolveFont(family: fontFamily, size: fontSize)
        let string = string
        let node = pass.requestNativeLeaf { proposal in
            MainActor.assumeIsolated {
                proposalTextMeasurement(string, font: key, system: system, proposal: proposal)
            }
        }
        return (node, Layout(node: node.layoutNodeID))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        let system = pass.textSystem
        let font = system.resolveFont(family: fontFamily, size: fontSize)
        let width = max(pass.measuredWidth(of: layout.node), smallestWrapWidth)
        let color = pass.theme[foregroundColor ?? .textPrimary]
        for glyph in system.placeGlyphs(string, font: font, wrappingAt: width,
                                        origin: (x: Double(bounds.origin.x.value),
                                                 y: Double(bounds.origin.y.value)),
                                        scaleFactor: pass.scaleFactor) {
            pass.draw(glyph, color: color)
        }
    }
}

/// Measures a text run from a SwiftUI-style proposal: a concrete width wraps
/// the run, while an unspecified width asks for its intrinsic one-line width.
/// The height proposal does not truncate or scale text, matching the measured
/// SwiftUI custom-Layout behavior.
#if canImport(MetalUIText)
@MainActor
func proposalTextMeasurement(_ string: String, font: ResolvedFont,
                             cache: ShapingCache, proposal: ProposedSize) -> LayoutMeasurement {
    cache.registerFont(font)
    return proposalTextMeasurement(string, font: font.key, system: CoreTextTextSystem(cache: cache),
                                   proposal: proposal)
}
#endif

@MainActor
func proposalTextMeasurement(_ string: String, font: FontKey,
                             system: any TextSystem, proposal: ProposedSize) -> LayoutMeasurement {
    let wrappingAt = proposal.width.map { max($0, smallestWrapWidth) }
    let shaped = system.measure(string, font: font, wrappingAt: wrappingAt)
    // The answer never exceeds a finite proposal (`LR-AU`; stage-2 probe group
    // Y, and stage 1's T3/T4). The typesetter breaks inside a word it cannot
    // fit, but the line it produces can still be wider than the proposal — one
    // character plus the space the typesetter hangs on its line below a word's
    // width (T3/T4: 11.18 against a 5 proposal), and 33.31 against 30 at Y8.
    // SwiftUI answers the proposal there, and reports the widest line only
    // while that line fits. SwiftUI ceils its answer and this does not (Y2
    // reads 19 against 18.17), which `LR-F` leaves to the shaping cache rather
    // than to a literal.
    let width = proposal.width.map { Swift.min($0, shaped.widestLine) } ?? shaped.widestLine
    return LayoutMeasurement(size: SizeD(width: width, height: shaped.totalHeight))
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
