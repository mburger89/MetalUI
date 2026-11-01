import MetalUICore

// SwiftUI's text modifiers (plan task 11, part 1; rulings TE-B, TE-D, TE-H,
// TE-I, TE-J). On any `ElementGroup` each is an **environment write**, an
// `EnvironmentScope` — layout- and identity-transparent, nearest writer wins —
// because SwiftUI's are `View` modifiers; a `Text` below reads them in layout
// and in paint through one resolution function (`TextStyleResolution.swift`).
// On `Text` and `ProposalText`, `font`, `fontWeight`, `italic` and
// `foregroundStyle` set the element's OWN value instead, which wins over the
// environment (probes F6b, C4, C5).

extension ElementGroup {
    /// The font every text below resolves when it names none (TE-B item 2).
    /// `nil` writes the default font back (a text below takes it unless it
    /// names its own).
    public func font(_ font: Font?) -> EnvironmentScope<Self> {
        environment(\.font, font)
    }

    /// A weight over whichever font each text below resolves (TE-B item 3;
    /// probe F6d). `nil` removes an outer override.
    public func fontWeight(_ weight: Font.Weight?) -> EnvironmentScope<Self> {
        environment(\.fontWeight, weight)
    }

    /// The italic face of whichever font each text below resolves (TE-B
    /// item 3). `false` removes an outer override.
    public func italic(_ isActive: Bool = true) -> EnvironmentScope<Self> {
        environment(\.italic, isActive)
    }

    /// The bold weight over whichever font each text below resolves — SwiftUI's
    /// `View.bold(_:)` (ruling `TM-F`). **A weight a text, an outer or inner
    /// `fontWeight` or the font itself names wins over it** (probe `W`: a `.light`
    /// font stays light under `.bold()`, in either order); `false` removes an outer
    /// `bold()`.
    public func bold(_ isActive: Bool = true) -> EnvironmentScope<Self> {
        environment(\.isBold, isActive)
    }

    /// Underlines every text below that sets no underline of its own — SwiftUI's
    /// `View.underline(_:pattern:color:)` (ruling `TM-A`). `false` is an explicit "none"
    /// an outer `underline()` does not reach; a `Text`'s own underline, of any
    /// pattern or colour, replaces this one whole (probe `W`).
    public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid,
                          color: Color? = nil) -> EnvironmentScope<Self> {
        environment(\.textUnderline, isActive ? Text.LineStyle(pattern: pattern, color: color) : .none)
    }

    /// Strikes through every text below that sets no strikethrough of its own, as
    /// ``underline(_:pattern:color:)`` (ruling `TM-A`).
    public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid,
                              color: Color? = nil) -> EnvironmentScope<Self> {
        environment(\.textStrikethrough, isActive ? Text.LineStyle(pattern: pattern, color: color) : .none)
    }

    /// `kerning` points after every grapheme of every text below that sets none of
    /// its own, ligatures kept — SwiftUI's `View.kerning(_:)` (ruling `TM-A`). The
    /// nearest writer wins, `0` included (probe `W`).
    public func kerning(_ kerning: Double) -> EnvironmentScope<Self> {
        environment(\.textKerning, kerning)
    }

    /// `tracking` points after every grapheme of every text below that sets none of
    /// its own, optional ligatures off — SwiftUI's `View.tracking(_:)` (ruling `TM-A`).
    public func tracking(_ tracking: Double) -> EnvironmentScope<Self> {
        environment(\.textTracking, tracking)
    }

    /// Raises the glyphs of every text below that sets no offset of its own
    /// `baselineOffset` points — SwiftUI's `View.baselineOffset(_:)` (ruling `TM-A`).
    public func baselineOffset(_ baselineOffset: Double) -> EnvironmentScope<Self> {
        environment(\.textBaselineOffset, baselineOffset)
    }

    /// The system face's `.monospaced` design over every text below that sets none of
    /// its own — SwiftUI's `View.monospaced(_:)` (ruling `TM-A`). A custom font ignores it.
    public func monospaced(_ isActive: Bool = true) -> EnvironmentScope<Self> {
        environment(\.textMonospaced, isActive)
    }

    /// The glyph colour of every text below that names none (TE-D; probes
    /// C2, C6) — a `Color`, not a `ShapeStyle` (`CR-E`; a leading-dot
    /// `.secondary` is `Color.secondary`, divergence 119, `CR-U`).
    public func foregroundStyle(_ color: Color) -> EnvironmentScope<Self> {
        environment(\.foregroundStyle, color)
    }

    /// The glyph colour of every text below that names none (TE-D; probes
    /// C2, C6). The `ColorToken` spelling, kept (`CR-E` item 1).
    @_disfavoredOverload
    public func foregroundStyle(_ token: ColorToken) -> EnvironmentScope<Self> {
        foregroundStyle(Color(token))
    }

    /// ``foregroundStyle(_:)`` under SwiftUI's older name (probe C3), with its
    /// optional: `nil` clears an outer writer's colour, so a text below that
    /// names none paints the default `textPrimary` (`CR-E` item 4).
    public func foregroundColor(_ color: Color?) -> EnvironmentScope<Self> {
        environment(\.foregroundStyle, color)
    }

    /// ``foregroundStyle(_:)`` under SwiftUI's older name (probe C3). The
    /// `ColorToken` spelling, kept (`CR-E` item 1).
    @_disfavoredOverload
    public func foregroundColor(_ token: ColorToken) -> EnvironmentScope<Self> {
        foregroundColor(Color(token))
    }

    /// At most `number` lines (`nil`: no limit), the last truncated
    /// (TE-H; probe L1). 0 or below acts as 1.
    public func lineLimit(_ number: Int?) -> EnvironmentScope<Self> {
        environment(\.textLineLimit, TextLineLimit(min: nil, max: number))
    }

    /// At most `limit` lines; with `reservesSpace`, the text is always `limit`
    /// lines tall (probe L2), its width and last baseline its own.
    public func lineLimit(_ limit: Int, reservesSpace: Bool) -> EnvironmentScope<Self> {
        environment(\.textLineLimit, TextLineLimit(min: reservesSpace ? limit : nil, max: limit))
    }

    /// Between `limit`'s bounds: at most the upper, and at least the lower
    /// bound's height (probe L3).
    public func lineLimit(_ limit: ClosedRange<Int>) -> EnvironmentScope<Self> {
        environment(\.textLineLimit, TextLineLimit(min: limit.lowerBound, max: limit.upperBound))
    }

    /// At least `limit.lowerBound` lines tall, no upper bound (probe L3).
    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> EnvironmentScope<Self> {
        environment(\.textLineLimit, TextLineLimit(min: limit.lowerBound, max: nil))
    }

    /// At most `limit.upperBound` lines (probe L3).
    public func lineLimit(_ limit: PartialRangeThrough<Int>) -> EnvironmentScope<Self> {
        environment(\.textLineLimit, TextLineLimit(min: nil, max: limit.upperBound))
    }

    /// Which end of a truncated line keeps its text (TE-I).
    public func truncationMode(_ mode: Text.TruncationMode) -> EnvironmentScope<Self> {
        environment(\.truncationMode, mode)
    }

    /// How each line of a multi-line text sits in its box (TE-J; probe A4).
    public func multilineTextAlignment(_ alignment: TextAlignment) -> EnvironmentScope<Self> {
        environment(\.multilineTextAlignment, alignment)
    }
}

extension Text {
    /// This text's own font, winning over the environment's (probe F6b).
    /// **`nil` is the default font, not the inherited one** (F6c).
    public func font(_ font: Font?) -> Text {
        var copy = self
        // No closure (ruling `SG-J`): one here is main-actor isolated and
        // checks its executor, so a tree setting a font built off the main
        // thread (`everyProductionTreeBuildsOnAOneMegabyteThread`) trapped.
        if let font { copy.fontRequest = .explicit(font) } else { copy.fontRequest = .defaultFont }
        return copy
    }

    /// A weight over whichever font this text resolves — its own, the
    /// environment's or the default (TE-B item 3). `nil` removes it.
    public func fontWeight(_ weight: Font.Weight?) -> Text {
        var copy = self
        copy.fontWeight = weight
        return copy
    }

    /// The italic face of whichever font this text resolves (TE-B item 3).
    /// `false` adds nothing (an italic font stays italic), as in SwiftUI.
    public func italic(_ isActive: Bool = true) -> Text {
        var copy = self
        copy.isItalic = isActive
        return copy
    }

    /// This text's own glyph colour, winning over the environment's (probes
    /// C1, C4, C5) — the same field as ``foregroundColor(_:)``. A `Color`
    /// since the colour work (`CR-E`).
    public func foregroundStyle(_ color: Color) -> Text {
        var copy = self
        copy.foregroundColor = color
        return copy
    }

    /// This text's own glyph colour, winning over the environment's (probes
    /// C1, C4, C5) — the same field as ``foregroundColor(_:)``. The
    /// `ColorToken` spelling, kept (`CR-E` item 1).
    @_disfavoredOverload
    public func foregroundStyle(_ token: ColorToken) -> Text {
        foregroundStyle(Color(token))
    }
}

extension Text {
    /// How an underline or strikethrough is drawn — SwiftUI's `Text.LineStyle`
    /// (ruling RT-E item 3): a pattern and an optional colour (`nil`: the
    /// run's foreground, `RT-J` item 4). Drawn as a filled rect at the face's
    /// own position and thickness (`RT-J` item 2, divergence 152).
    public struct LineStyle: Hashable, Sendable {
        /// A line's dash pattern — SwiftUI's `Text.LineStyle.Pattern` (ruling `TM-B`).
        /// Lengths are multiples of the line's thickness and the phase is the line's
        /// own (probe `text-line-patterns.swift`, `TM-C`, `TM-D`).
        public struct Pattern: Hashable, Sendable {
            /// The five shapes SwiftUI offers.
            enum Kind: UInt8, Hashable, Sendable {
                case solid, dot, dash, dashDot, dashDotDot
            }
            let kind: Kind

            /// One unbroken line.
            public static let solid = Pattern(kind: .solid)
            /// Dots: 3 thicknesses on, 3 off.
            public static let dot = Pattern(kind: .dot)
            /// Dashes: 10 thicknesses on, 5 off.
            public static let dash = Pattern(kind: .dash)
            /// A dash and a dot: 10 on, 3 off, 3 on, 3 off.
            public static let dashDot = Pattern(kind: .dashDot)
            /// A dash and two dots: 10 on, 3 off, then (3 on, 3 off) twice.
            public static let dashDotDot = Pattern(kind: .dashDotDot)
        }

        /// The line's pattern.
        public var pattern: Pattern
        /// The line's colour; `nil` is the run's foreground.
        public var color: Color?
        /// `false` is an explicit "no line" — `underline(false)` — which an
        /// outer `Text`'s line does not override (RT-E item 2).
        var isActive = true

        /// A line in `pattern`, coloured `color` (`nil`: the foreground).
        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }

        /// A solid line in the foreground colour.
        public static let single = LineStyle()

        /// The explicit "no line" of `underline(false)`.
        static let none: LineStyle = {
            var style = LineStyle()
            style.isActive = false
            return style
        }()
    }

    /// The bold weight over whichever font this text resolves — SwiftUI's
    /// `Text.bold()`, the same field as ``fontWeight(_:)`` (ruling RT-E item 3).
    public func bold() -> Text { bold(true) }

    /// The bold weight when `isActive`; `false` removes this text's own weight.
    public func bold(_ isActive: Bool) -> Text {
        fontWeight(isActive ? .bold : nil)
    }

    /// Underlines this text (ruling RT-E item 3; `RT-O` item 8): at the face's
    /// underline position and thickness, across each line's visible extent
    /// (`RT-J`). `false` is an explicit "none" an outer `Text`'s underline does
    /// not reach. Takes the styled path (`RT-F` item 3).
    public func underline(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid,
                          color: Color? = nil) -> Text {
        var copy = self
        copy.rich.underline = isActive ? LineStyle(pattern: pattern, color: color) : .none
        return copy
    }

    /// Strikes this text through at half the face's x-height (ruling RT-E
    /// item 3, `RT-J` item 2); `false` is an explicit "none".
    public func strikethrough(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid,
                              color: Color? = nil) -> Text {
        var copy = self
        copy.rich.strikethrough = isActive ? LineStyle(pattern: pattern, color: color) : .none
        return copy
    }

    /// `kerning` points after every grapheme, ligatures kept (rulings RT-H
    /// item 3, `RT-P` item 4). `0` is no extra space and keeps the face's pair
    /// kerning (`K1`), but still takes the styled path.
    public func kerning(_ kerning: Double) -> Text {
        var copy = self
        copy.rich.kerning = kerning
        return copy
    }

    /// `tracking` points after every grapheme, optional ligatures off (rulings
    /// RT-H item 3, `C8e`).
    public func tracking(_ tracking: Double) -> Text {
        var copy = self
        copy.rich.tracking = tracking
        return copy
    }

    /// Raises this text's glyphs `baselineOffset` points (negative lowers);
    /// the line grows to hold them (rulings RT-G item 1, RT-H item 4).
    public func baselineOffset(_ baselineOffset: Double) -> Text {
        var copy = self
        copy.rich.baselineOffset = baselineOffset
        return copy
    }

    /// The system face's `.monospaced` design over this text's font (ruling
    /// RT-E item 3; `TE-B`). A custom font ignores it.
    public func monospaced(_ isActive: Bool = true) -> Text {
        var copy = self
        copy.rich.monospaced = isActive
        return copy
    }
}

extension ProposalText {
    /// The bold weight (ruling RT-E item 3), as ``Text/bold()``.
    public func bold() -> ProposalText { bold(true) }

    /// The bold weight when `isActive`, as ``Text/bold(_:)``.
    public func bold(_ isActive: Bool) -> ProposalText {
        fontWeight(isActive ? .bold : nil)
    }

    /// Underlines this text, as ``Text/underline(_:pattern:color:)``.
    public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid,
                          color: Color? = nil) -> ProposalText {
        var copy = self
        copy.rich.underline = isActive ? Text.LineStyle(pattern: pattern, color: color) : .none
        return copy
    }

    /// Strikes this text through, as ``Text/strikethrough(_:pattern:color:)``.
    public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid,
                              color: Color? = nil) -> ProposalText {
        var copy = self
        copy.rich.strikethrough = isActive ? Text.LineStyle(pattern: pattern, color: color) : .none
        return copy
    }

    /// Kerning, as ``Text/kerning(_:)``.
    public func kerning(_ kerning: Double) -> ProposalText {
        var copy = self
        copy.rich.kerning = kerning
        return copy
    }

    /// Tracking, as ``Text/tracking(_:)``.
    public func tracking(_ tracking: Double) -> ProposalText {
        var copy = self
        copy.rich.tracking = tracking
        return copy
    }

    /// A baseline offset, as ``Text/baselineOffset(_:)``.
    public func baselineOffset(_ baselineOffset: Double) -> ProposalText {
        var copy = self
        copy.rich.baselineOffset = baselineOffset
        return copy
    }

    /// The `.monospaced` design, as ``Text/monospaced(_:)``.
    public func monospaced(_ isActive: Bool = true) -> ProposalText {
        var copy = self
        copy.rich.monospaced = isActive
        return copy
    }
}

extension ProposalText {
    /// This text's own font; `nil` is the default font (F6b, F6c).
    public func font(_ font: Font?) -> ProposalText {
        var copy = self
        // No closure (ruling `SG-J`): one here is main-actor isolated and
        // checks its executor, so a tree setting a font built off the main
        // thread (`everyProductionTreeBuildsOnAOneMegabyteThread`) trapped.
        if let font { copy.fontRequest = .explicit(font) } else { copy.fontRequest = .defaultFont }
        return copy
    }

    /// A weight over whichever font this text resolves (TE-B item 3).
    public func fontWeight(_ weight: Font.Weight?) -> ProposalText {
        var copy = self
        copy.fontWeight = weight
        return copy
    }

    /// The italic face of whichever font this text resolves (TE-B item 3).
    public func italic(_ isActive: Bool = true) -> ProposalText {
        var copy = self
        copy.isItalic = isActive
        return copy
    }

    /// This text's own glyph colour (TE-D), a `Color` (`CR-E`).
    public func foregroundStyle(_ color: Color) -> ProposalText {
        var copy = self
        copy.foregroundColor = color
        return copy
    }

    /// This text's own glyph colour (TE-D). The `ColorToken` spelling, kept
    /// (`CR-E` item 1).
    @_disfavoredOverload
    public func foregroundStyle(_ token: ColorToken) -> ProposalText {
        foregroundStyle(Color(token))
    }
}

extension TextField {
    /// The field's own font; `nil` is the default font (TE-F item 2).
    public func font(_ font: Font?) -> TextField {
        var copy = self
        // No closure (ruling `SG-J`): one here is main-actor isolated and
        // checks its executor, so a tree setting a font built off the main
        // thread (`everyProductionTreeBuildsOnAOneMegabyteThread`) trapped.
        if let font { copy.fontRequest = .explicit(font) } else { copy.fontRequest = .defaultFont }
        return copy
    }
}

extension TextEditor {
    /// The editor's own font; `nil` is the default font (TE-F item 2).
    public func font(_ font: Font?) -> TextEditor {
        var copy = self
        // No closure (ruling `SG-J`): one here is main-actor isolated and
        // checks its executor, so a tree setting a font built off the main
        // thread (`everyProductionTreeBuildsOnAOneMegabyteThread`) trapped.
        if let font { copy.fontRequest = .explicit(font) } else { copy.fontRequest = .defaultFont }
        return copy
    }
}
