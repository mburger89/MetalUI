import MetalUITextSystem

/// SwiftUI's `Font` (ruling TE-B): a request for a face, resolved by the
/// frame's text system through a ``MetalUITextSystem/FontDescriptor``.
///
/// ```swift
/// Text("Title").font(.title)
/// Column { … }.font(.system(size: 15, weight: .semibold))
/// Text("Mono").font(.custom("Menlo", size: 12)).italic()
/// ```
///
/// **A text style is a fixed face on macOS** (probe
/// `swiftui-text-semantics.swift` F1): `.largeTitle` is 26 pt, `.title` 22,
/// `.title2` 17, `.title3` 15, `.headline` 13 bold, `.subheadline` 11,
/// `.body` 13, `.callout` 12, `.footnote` 10, `.caption` 10 and `.caption2`
/// 10 medium — the same table on every text system, since the mapping is this
/// type's, not a platform query. **No style responds to `dynamicTypeSize`**,
/// which is SwiftUI's macOS answer (F7, ruling TE-E); `custom(_:fixedSize:)`
/// and `custom(_:size:relativeTo:)` measure as `custom(_:size:)` (F5b, F5c).
///
/// **Not offered** (TE-B item 6): `Font.leading(_:)`, `Font(_ ctFont:)`,
/// `.monospacedDigit()`, widths. `Text.bold()` is not offered either (item 4);
/// `Font.bold()` and `.fontWeight(.bold)` are the spellings.
public struct Font: Hashable, Sendable {
    enum Base: Hashable, Sendable {
        case system(size: Double)
        case textStyle(TextStyle)
        case custom(name: String, size: Double)
    }

    var base: Base
    var design: Design?
    var weightOverride: Weight?
    var isItalic: Bool

    init(base: Base, design: Design? = nil, weight: Weight? = nil, italic: Bool = false) {
        self.base = base
        self.design = design
        self.weightOverride = weight
        self.isItalic = italic
    }

    /// The system face at `size` points (SwiftUI's
    /// `.system(size:weight:design:)`; probe F2, F3).
    public static func system(size: Double, weight: Weight? = nil, design: Design? = nil) -> Font {
        Font(base: .system(size: size), design: design, weight: weight)
    }

    /// A text style, optionally in another design or weight (probe F1).
    public static func system(_ style: TextStyle, design: Design? = nil, weight: Weight? = nil) -> Font {
        Font(base: .textStyle(style), design: design, weight: weight)
    }

    public static let largeTitle = Font(base: .textStyle(.largeTitle))
    public static let title = Font(base: .textStyle(.title))
    public static let title2 = Font(base: .textStyle(.title2))
    public static let title3 = Font(base: .textStyle(.title3))
    public static let headline = Font(base: .textStyle(.headline))
    public static let subheadline = Font(base: .textStyle(.subheadline))
    public static let body = Font(base: .textStyle(.body))
    public static let callout = Font(base: .textStyle(.callout))
    public static let footnote = Font(base: .textStyle(.footnote))
    public static let caption = Font(base: .textStyle(.caption))
    public static let caption2 = Font(base: .textStyle(.caption2))

    /// The face `name` names — a PostScript, family or full name, as
    /// `CTFontCreateWithName` reads it; an unmatched name substitutes (F5).
    public static func custom(_ name: String, size: Double) -> Font {
        Font(base: .custom(name: name, size: size))
    }

    /// As ``custom(_:size:)``: no size responds to dynamic type on macOS (F5b).
    public static func custom(_ name: String, fixedSize: Double) -> Font {
        Font(base: .custom(name: name, size: fixedSize))
    }

    /// As ``custom(_:size:)``: no size responds to dynamic type on macOS (F5c).
    public static func custom(_ name: String, size: Double, relativeTo textStyle: TextStyle) -> Font {
        Font(base: .custom(name: name, size: size))
    }

    /// This font at `weight`, replacing any weight it had (a text style's
    /// own included: `.headline.weight(.light)` is light).
    public func weight(_ weight: Weight) -> Font {
        var copy = self
        copy.weightOverride = weight
        return copy
    }

    /// `weight(.bold)` — SwiftUI's `Font.bold()` exactly (probe X1c).
    public func bold() -> Font { weight(.bold) }

    /// This font's italic face; a family with none keeps its upright face,
    /// nothing is synthesised (F4, F4b).
    public func italic() -> Font {
        var copy = self
        copy.isItalic = true
        return copy
    }

    /// SwiftUI's nine weights. `value` is CoreText's weight trait, what the
    /// seam's ``MetalUITextSystem/FontDescriptor/weight`` reads (ruling TE-B
    /// item 1).
    public struct Weight: Hashable, Sendable {
        public let value: Double
        init(_ value: Double) { self.value = value }

        public static let ultraLight = Weight(-0.8)
        public static let thin = Weight(-0.6)
        public static let light = Weight(-0.4)
        public static let regular = Weight(0)
        public static let medium = Weight(0.23)
        public static let semibold = Weight(0.3)
        public static let bold = Weight(0.4)
        public static let heavy = Weight(0.56)
        public static let black = Weight(0.62)
    }

    /// A system face's design (F3). A custom font ignores it.
    public enum Design: Hashable, Sendable {
        case `default`, serif, rounded, monospaced
    }

    /// SwiftUI's eleven text styles (F1).
    public enum TextStyle: Hashable, Sendable, CaseIterable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2

        /// F1's macOS table: the size and, where it is not regular, the
        /// weight. Fixed — no dynamic type (TE-E).
        var metrics: (size: Double, weight: Weight?) {
            switch self {
            case .largeTitle: (26, nil)
            case .title: (22, nil)
            case .title2: (17, nil)
            case .title3: (15, nil)
            case .headline: (13, .bold)
            case .subheadline: (11, nil)
            case .body: (13, nil)
            case .callout: (12, nil)
            case .footnote: (10, nil)
            case .caption: (10, nil)
            case .caption2: (10, .medium)
            }
        }
    }

    /// The seam request, with `weight` and `italic` from `.fontWeight(_:)`/
    /// `.italic(_:)` applied over this font's own (TE-B item 3): an override
    /// weight wins over the font's, and italic is either's.
    func descriptor(weight override: Weight? = nil, italic: Bool = false) -> FontDescriptor {
        let slanted = isItalic || italic
        switch base {
        case .system(let size):
            return FontDescriptor(size: size, weight: (override ?? weightOverride)?.value,
                                  italic: slanted, design: design?.seam ?? .default)
        case .textStyle(let style):
            let metrics = style.metrics
            return FontDescriptor(size: metrics.size, weight: (override ?? weightOverride ?? metrics.weight)?.value,
                                  italic: slanted, design: design?.seam ?? .default)
        case .custom(let name, let size):
            return FontDescriptor(family: name, size: size, weight: (override ?? weightOverride)?.value,
                                  italic: slanted)
        }
    }

    /// The family and size `fontFamily`/`fontSize` read back (TE-B item 5).
    var familyAndSize: (family: String?, size: Double) {
        switch base {
        case .system(let size): (nil, size)
        case .textStyle(let style): (nil, style.metrics.size)
        case .custom(let name, let size): (name, size)
        }
    }
}

extension Font.Design {
    var seam: FontDesign {
        switch self {
        case .default: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
}

/// How each line of a multi-line text sits in the text's box — SwiftUI's
/// `TextAlignment` (ruling TE-J). `.leading` is the left edge: nothing mirrors
/// under right-to-left yet (EV-K, divergence 25).
public enum TextAlignment: Hashable, Sendable {
    case leading, center, trailing
}

extension Text {
    /// Which end of a truncated line keeps its text — SwiftUI's
    /// `Text.TruncationMode` (ruling TE-I). `.tail` by default.
    public enum TruncationMode: Hashable, Sendable {
        case head, tail, middle
    }
}

/// A text's own font request (ruling TE-B item 2): inherit the environment's,
/// the default font whatever the environment says (`Text.font(nil)`, F6c), or
/// an explicit font.
enum TextFontRequest: Hashable, Sendable {
    case inherit
    case defaultFont
    case explicit(Font)

    /// What `fontFamily`/`fontSize` read: the explicit font's family and size,
    /// else `nil` and 13 — what an unconfigured `Text` read before (TE-B item 5).
    var familyAndSize: (family: String?, size: Double) {
        if case .explicit(let font) = self { return font.familyAndSize }
        return (nil, 13)
    }

    /// The explicit font `font(family:size:)` and a write to `fontFamily`/
    /// `fontSize` set: `.custom` for a family, `.system` for none.
    static func legacy(family: String?, size: Double) -> TextFontRequest {
        .explicit(family.map { .custom($0, size: size) } ?? .system(size: size))
    }
}
