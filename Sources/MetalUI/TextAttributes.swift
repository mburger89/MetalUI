import Foundation
import MetalUICore

// Rich text, lane 3 — `Text(AttributedString)` over MetalUI's own attribute
// scope (ruling RT-D). Foundation's `AttributedString` exists on every
// platform (`L1`); SwiftUI's scope does not, so MetalUI declares SwiftUI's
// keys over its own types. What crosses the text seam is still the neutral run
// model (`RT-F`): the conversion lives here, where Foundation is allowed.

extension AttributeScopes {
    /// The attributes a ``Text`` made from an `AttributedString` reads —
    /// SwiftUI's keys over MetalUI's types (ruling RT-D item 2), plus
    /// Foundation's (`link`). Attributes outside it are ignored (item 6).
    public struct MetalUIAttributes: AttributeScope {
        /// The run's font (``Font``) — `Text.font(_:)`.
        public let font: FontAttribute
        /// The run's glyph colour — `Text.foregroundColor(_:)`.
        public let foregroundColor: ForegroundColorAttribute
        /// The run's background, filled across the run by its line box (`RT-J`).
        public let backgroundColor: BackgroundColorAttribute
        /// The run's underline — `Text.underline(_:pattern:color:)`.
        public let underlineStyle: UnderlineStyleAttribute
        /// The run's strikethrough — `Text.strikethrough(_:pattern:color:)`.
        public let strikethroughStyle: StrikethroughStyleAttribute
        /// Points after every grapheme, ligatures kept — `Text.kerning(_:)`.
        public let kern: KerningAttribute
        /// Points after every grapheme, ligatures off — `Text.tracking(_:)`.
        public let tracking: TrackingAttribute
        /// Points the run is raised — `Text.baselineOffset(_:)`.
        public let baselineOffset: BaselineOffsetAttribute
        /// Foundation's attributes: `link` (styled, inert — `RT-K`).
        public let foundation: AttributeScopes.FoundationAttributes

        /// The `font` key.
        public enum FontAttribute: AttributedStringKey {
            /// A ``Font``.
            public typealias Value = Font
            /// `"MetalUI.font"`.
            public static let name = "MetalUI.font"
        }
        /// The `foregroundColor` key.
        public enum ForegroundColorAttribute: AttributedStringKey {
            /// A ``Color``.
            public typealias Value = Color
            /// `"MetalUI.foregroundColor"`.
            public static let name = "MetalUI.foregroundColor"
        }
        /// The `backgroundColor` key.
        public enum BackgroundColorAttribute: AttributedStringKey {
            /// A ``Color``.
            public typealias Value = Color
            /// `"MetalUI.backgroundColor"`.
            public static let name = "MetalUI.backgroundColor"
        }
        /// The `underlineStyle` key.
        public enum UnderlineStyleAttribute: AttributedStringKey {
            /// A ``Text/LineStyle``.
            public typealias Value = Text.LineStyle
            /// `"MetalUI.underlineStyle"`.
            public static let name = "MetalUI.underlineStyle"
        }
        /// The `strikethroughStyle` key.
        public enum StrikethroughStyleAttribute: AttributedStringKey {
            /// A ``Text/LineStyle``.
            public typealias Value = Text.LineStyle
            /// `"MetalUI.strikethroughStyle"`.
            public static let name = "MetalUI.strikethroughStyle"
        }
        /// The `kern` key.
        public enum KerningAttribute: AttributedStringKey {
            /// Points.
            public typealias Value = Double
            /// `"MetalUI.kern"`.
            public static let name = "MetalUI.kern"
        }
        /// The `tracking` key.
        public enum TrackingAttribute: AttributedStringKey {
            /// Points.
            public typealias Value = Double
            /// `"MetalUI.tracking"`.
            public static let name = "MetalUI.tracking"
        }
        /// The `baselineOffset` key.
        public enum BaselineOffsetAttribute: AttributedStringKey {
            /// Points; positive raises.
            public typealias Value = Double
            /// `"MetalUI.baselineOffset"`.
            public static let name = "MetalUI.baselineOffset"
        }
    }

    /// MetalUI's attribute scope (ruling RT-D item 2).
    public var metalUI: MetalUIAttributes.Type { MetalUIAttributes.self }
}

extension AttributeDynamicLookup {
    /// `attributed.<key>` for every key of MetalUI's scope (ruling RT-D).
    public subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, T>
    ) -> T {
        self[T.self]
    }

    // One NON-generic subscript per key (ruling RT-D item 3): with only the
    // generic one, `attributed.foregroundColor = .red` is ambiguous in any
    // module that imports MetalUI — AppKit's scope leaks through MetalUI's own
    // `import AppKit`, and its `@_disfavoredOverload` subscript still ties with
    // a second generic one (probe `swift-attribute-scope-ambiguity`, `generic
    // UsePlain`). Guard: `everyAttributeKeyIsWritableWithAPlainImport`.

    /// `attributed.font` — non-generic, so it wins over AppKit's scope
    /// (ruling RT-D item 3).
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.FontAttribute>
    ) -> AttributeScopes.MetalUIAttributes.FontAttribute {
        self[AttributeScopes.MetalUIAttributes.FontAttribute.self]
    }

    /// `attributed.foregroundColor` — non-generic, so it wins over AppKit's scope
    /// (ruling RT-D item 3).
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.ForegroundColorAttribute>
    ) -> AttributeScopes.MetalUIAttributes.ForegroundColorAttribute {
        self[AttributeScopes.MetalUIAttributes.ForegroundColorAttribute.self]
    }

    /// `attributed.backgroundColor` — non-generic, so it wins over AppKit's scope
    /// (ruling RT-D item 3).
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.BackgroundColorAttribute>
    ) -> AttributeScopes.MetalUIAttributes.BackgroundColorAttribute {
        self[AttributeScopes.MetalUIAttributes.BackgroundColorAttribute.self]
    }

    /// `attributed.underlineStyle` — non-generic, so it wins over AppKit's scope
    /// (ruling RT-D item 3).
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.UnderlineStyleAttribute>
    ) -> AttributeScopes.MetalUIAttributes.UnderlineStyleAttribute {
        self[AttributeScopes.MetalUIAttributes.UnderlineStyleAttribute.self]
    }

    /// `attributed.strikethroughStyle` — non-generic, so it wins over AppKit's scope
    /// (ruling RT-D item 3).
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.StrikethroughStyleAttribute>
    ) -> AttributeScopes.MetalUIAttributes.StrikethroughStyleAttribute {
        self[AttributeScopes.MetalUIAttributes.StrikethroughStyleAttribute.self]
    }

    /// `attributed.kern` — non-generic, so it wins over AppKit's scope
    /// (ruling RT-D item 3).
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.KerningAttribute>
    ) -> AttributeScopes.MetalUIAttributes.KerningAttribute {
        self[AttributeScopes.MetalUIAttributes.KerningAttribute.self]
    }

    /// `attributed.tracking` — non-generic, so it wins over AppKit's scope
    /// (ruling RT-D item 3).
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.TrackingAttribute>
    ) -> AttributeScopes.MetalUIAttributes.TrackingAttribute {
        self[AttributeScopes.MetalUIAttributes.TrackingAttribute.self]
    }

    /// `attributed.baselineOffset` — non-generic, so it wins over AppKit's scope
    /// (ruling RT-D item 3).
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.BaselineOffsetAttribute>
    ) -> AttributeScopes.MetalUIAttributes.BaselineOffsetAttribute {
        self[AttributeScopes.MetalUIAttributes.BaselineOffsetAttribute.self]
    }
}

/// `attributed`'s runs as `Text` segments (ruling RT-D item 4): MetalUI's
/// keys and Foundation's `link` from each run, and on Apple platforms
/// `inlinePresentationIntent` (item 5) where a key left the field unset;
/// every other attribute ignored (item 6).
func textRunRequests(_ attributed: AttributedString) -> [TextRunRequest] {
    typealias Keys = AttributeScopes.MetalUIAttributes
    return attributed.runs.map { run in
        var request = TextRunRequest(string: String(attributed[run.range].characters))
        request.font = run[Keys.FontAttribute.self].map { .explicit($0) }
        request.foreground = run[Keys.ForegroundColorAttribute.self]
        request.background = run[Keys.BackgroundColorAttribute.self]
        request.underline = run[Keys.UnderlineStyleAttribute.self]
        request.strikethrough = run[Keys.StrikethroughStyleAttribute.self]
        request.kerning = run[Keys.KerningAttribute.self]
        request.tracking = run[Keys.TrackingAttribute.self]
        request.baselineOffset = run[Keys.BaselineOffsetAttribute.self]
        request.link = run.link?.absoluteString
        #if canImport(Darwin)
        if let intent = run.inlinePresentationIntent {
            request = markdownFilled(request, MarkdownRun(text: "", bold: intent.contains(.stronglyEmphasized),
                                                          italic: intent.contains(.emphasized),
                                                          strikethrough: intent.contains(.strikethrough),
                                                          code: intent.contains(.code)))
        }
        #endif
        return request
    }
}

extension Text {
    /// A text leaf over an `AttributedString` (ruling RT-D): each run's
    /// MetalUI attributes — font, colours, underline, strikethrough, kerning,
    /// tracking, baseline offset — and Foundation's `link` (styled, inert,
    /// divergence 150); on Apple platforms also `inlinePresentationIntent`
    /// (bold, italic, strikethrough, code — `C12c`), so
    /// `Text(try AttributedString(markdown:))` draws what SwiftUI draws.
    /// Attributes outside MetalUI's scope are ignored. **Disfavoured**:
    /// `AttributedString` is `ExpressibleByStringLiteral`, so a string literal
    /// would otherwise be ambiguous between this and the
    /// `LocalizedStringKey` initialiser; a literal is a key (ruling RT-B).
    @_disfavoredOverload
    public init(_ attributedContent: AttributedString) {
        self.init(content: collapsedTextContent(textRunRequests(attributedContent)))
    }
}

extension ProposalText {
    /// A proposal-layout text leaf over an `AttributedString`, read as
    /// `Text(_:)` reads it (ruling RT-D). Disfavoured, as `Text`'s.
    @_disfavoredOverload
    public init(_ attributedContent: AttributedString) {
        self.init(content: collapsedTextContent(textRunRequests(attributedContent)))
    }
}
