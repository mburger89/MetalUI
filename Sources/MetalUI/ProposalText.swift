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
    /// The text drawn.
    public var string: String
    /// The text's own colour; `nil` inherits the foreground style.
    public var foregroundColor: ColorToken?
    /// This text's own font request, weight and slope (ruling TE-B), as
    /// `Text`'s.
    var fontRequest: TextFontRequest = .inherit
    var fontWeight: Font.Weight?
    var isItalic = false

    /// The explicit font's family; computed over the request (TE-B item 5).
    public var fontFamily: String? {
        get { fontRequest.familyAndSize.family }
        set { fontRequest = .legacy(family: newValue, size: fontSize) }
    }
    /// The explicit font's size, 13 without one; computed (TE-B item 5).
    public var fontSize: Double {
        get { fontRequest.familyAndSize.size }
        set { fontRequest = .legacy(family: fontFamily, size: newValue) }
    }

    /// A proposal-layout text leaf showing `string`, measured and drawn through
    /// the frame's text system (`TS-A`).
    public init(_ string: String) {
        self.string = string
        foregroundColor = nil
    }

    /// An explicit font: `.custom(family, size:)`, or `.system(size:)` for a
    /// `nil` family (TE-B item 5).
    public func font(family: String? = nil, size: Double) -> ProposalText {
        var copy = self
        copy.fontRequest = .legacy(family: family, size: size)
        return copy
    }

    /// The semantic token used to tint this run's glyphs.
    public func foregroundColor(_ token: ColorToken) -> ProposalText {
        var copy = self
        copy.foregroundColor = token
        return copy
    }

    public struct Layout { var node: LayoutNodeID }

    var styleRequest: TextStyleRequest {
        TextStyleRequest(font: fontRequest, weight: fontWeight, italic: isItalic, foreground: foregroundColor)
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let system = pass.textSystem
        // One resolution for layout and paint (spec §3): same environment,
        // same answer. The closure captures the key and the resolved style —
        // values — never the request.
        let style = resolveTextStyle(styleRequest, in: pass.environment)
        let key = system.resolveFont(style.descriptor)
        let string = string
        let node = pass.requestNativeLeaf { proposal in
            MainActor.assumeIsolated {
                proposalTextMeasurement(string, font: key, system: system, proposal: proposal, style: style)
            }
        }
        return (node, Layout(node: node.layoutNodeID))
    }

    /// Records its string for an accessibility client (plan task 12 part 2,
    /// `IX-AB` item 1): a static text, SwiftUI's answer for a text in a stack or
    /// grid (P1, P2) — the whole string, whatever is drawn (X1–X4). No hitbox,
    /// focus entry or `StateTable` slot; nothing at all while no client
    /// collects.
    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {
        guard !string.isEmpty else { return }
        pass.frame.recordAccessibility(text: string, declared: AXNode(), at: bounds, id: id)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        let system = pass.textSystem
        let style = resolveTextStyle(styleRequest, in: pass.environment)
        let font = system.resolveFont(style.descriptor)
        let width = max(pass.measuredWidth(of: layout.node), smallestWrapWidth)
        // The line cap from the box the leaf was placed in (TE-H item 2): its
        // own answer, so the lines layout measured.
        let laid = textLines(string, font: font, system: system, wrappingAt: width,
                             height: Double(bounds.size.height.value), style: style)
        let color = pass.theme[style.foreground]
        for glyph in system.placeGlyphs(string, font: font, wrappingAt: width, options: laid.options,
                                        origin: (x: Double(bounds.origin.x.value),
                                                 y: Double(bounds.origin.y.value)),
                                        scaleFactor: pass.scaleFactor) {
            pass.draw(glyph, color: color)
        }
    }
}

/// Measures a run in a font resolved by the caller, unstyled: no line limit,
/// tail, leading (spec §3's measurement with ``ResolvedTextStyle/unstyled``) —
/// a finite height still limits its lines (ruling TE-H item 2, probe L5; the
/// sentence "the height proposal does not truncate or scale text" this doc
/// comment carried until TE-H was unprobed and is refuted).
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
    proposalTextMeasurement(string, font: font, system: system, proposal: proposal, style: .unstyled)
}

extension Text {
    /// Converts this run to the proposal-layout bridge without changing its
    /// font or foreground-token configuration.
    public func proposalLayout() -> ProposalText {
        var result = ProposalText(string)
        result.fontRequest = fontRequest
        result.fontWeight = fontWeight
        result.isItalic = isItalic
        result.foregroundColor = foregroundColor
        return result
    }
}
