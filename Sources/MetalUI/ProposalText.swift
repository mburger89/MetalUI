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
    /// What this text shows: one plain string, or segments (spec §1.3).
    var content: TextContent
    /// The rich `Text`-level fields (ruling RT-E item 3), as `Text`'s.
    var rich = TextRichFields()

    /// The text drawn — every segment's, concatenated (`RT-L` item 1).
    /// Writing it replaces the content with one plain string.
    public var string: String {
        get { content.string }
        set { content = .plain(newValue) }
    }
    /// The text's own colour; `nil` inherits the foreground style.
    public var foregroundColor: Color?
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

    /// A proposal-layout text leaf showing `content` verbatim, measured and
    /// drawn through the frame's text system (`TS-A`) — `Text`'s
    /// disfavoured `StringProtocol` initialiser (ruling RT-C).
    @_disfavoredOverload
    public init<S: StringProtocol>(_ content: S) {
        self.init(content: .plain(String(content)))
    }

    /// A proposal-layout text leaf showing `content` exactly as written.
    public init(verbatim content: String) {
        self.init(content: .plain(content))
    }

    /// A proposal-layout text leaf over `content`.
    init(content: TextContent) {
        self.content = content
        foregroundColor = nil
    }

    /// An explicit font: `.custom(family, size:)`, or `.system(size:)` for a
    /// `nil` family (TE-B item 5).
    public func font(family: String? = nil, size: Double) -> ProposalText {
        var copy = self
        copy.fontRequest = .legacy(family: family, size: size)
        return copy
    }

    /// This text's own colour, `nil` to inherit — SwiftUI's
    /// `foregroundColor(_:)` with its optional (`CR-E` item 4).
    public func foregroundColor(_ color: Color?) -> ProposalText {
        var copy = self
        copy.foregroundColor = color
        return copy
    }

    /// The semantic token used to tint this run's glyphs.
    /// The `ColorToken` spelling, kept (`CR-E` item 1).
    @_disfavoredOverload
    public func foregroundColor(_ token: ColorToken) -> ProposalText {
        foregroundColor(Color(token))
    }

    public struct Layout { var node: LayoutNodeID }

    var styleRequest: TextStyleRequest {
        TextStyleRequest(font: fontRequest, weight: fontWeight, italic: isItalic, foreground: foregroundColor)
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let system = pass.textSystem
        guard let plain = plainTextForm(content, own: styleRequest, rich: rich) else {
            // The styled path, as `Text`'s (RT-F item 3).
            let resolved = resolveRichText(content, own: styleRequest, rich: rich, in: pass.environment,
                                           system: system)
            let node = pass.requestNativeLeaf { proposal in
                MainActor.assumeIsolated {
                    richTextMeasurement(resolved, system: system, proposal: proposal)
                }
            }
            return (node, Layout(node: node.layoutNodeID))
        }
        // One resolution for layout and paint (spec §3): same environment,
        // same answer. The closure captures the key and the resolved style —
        // values — never the request.
        let style = resolveTextStyle(plain.request, in: pass.environment)
        let key = system.resolveFont(style.descriptor)
        let string = plain.string
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
        let width = max(pass.measuredWidth(of: layout.node), smallestWrapWidth)
        guard let plain = plainTextForm(content, own: styleRequest, rich: rich) else {
            pass.drawStyledText(resolveRichText(content, own: styleRequest, rich: rich, in: pass.environment,
                                                system: system),
                                origin: bounds.origin, width: width, height: Double(bounds.size.height.value))
            return
        }
        let string = plain.string
        let style = resolveTextStyle(plain.request, in: pass.environment)
        let font = system.resolveFont(style.descriptor)
        // The line cap from the box the leaf was placed in (TE-H item 2): its
        // own answer, so the lines layout measured.
        let laid = textLines(string, font: font, system: system, wrappingAt: width,
                             height: Double(bounds.size.height.value), style: style)
        let color = pass.resolve(style.foreground)
        pass.drawGlyphs(system.placeGlyphs(string, font: font, wrappingAt: width, options: laid.options,
                                           origin: (x: Double(bounds.origin.x.value),
                                                    y: Double(bounds.origin.y.value)),
                                           scaleFactor: pass.scaleFactor), color: color)
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
    /// Converts this text to the proposal-layout bridge without changing its
    /// content, font, colour or rich fields (its segments included, RT-E).
    public func proposalLayout() -> ProposalText {
        var result = ProposalText(content: content)
        result.rich = rich
        result.fontRequest = fontRequest
        result.fontWeight = fontWeight
        result.isItalic = isItalic
        result.foregroundColor = foregroundColor
        return result
    }
}
