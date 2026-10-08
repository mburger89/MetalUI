import Foundation
import MetalUICore

// Rich text, lane 3 — the string-literal front end (rulings RT-B, RT-C; `RT-O`
// items 4–6 and 14). A string literal handed to `Text` lands on
// `Text.init(_ key: LocalizedStringKey)`: its format is parsed as inline
// Markdown by MetalUI's own parser (`MarkdownInline.swift`), and every
// interpolated value is inserted verbatim afterwards, taking the format's
// attributes at its position (`M10`, `M10b`). A `String` value reaches the
// disfavoured `init<S: StringProtocol>` and is never parsed (`M2`).

/// A string literal handed to ``Text`` — SwiftUI's `LocalizedStringKey`, as a
/// carrier of inline Markdown and interpolated values (rulings RT-B, RT-C).
///
/// **No string tables** (`RT-C` item 5): the key is never looked up; its
/// format is parsed as inline Markdown — `**bold**`, `_italic_`, `~~struck~~`,
/// `` `code` ``, `[links](…)` and bare URLs — when a `Text` is made from it.
/// An interpolated value is written verbatim with `String(describing:)`
/// (divergences 151, 156), never parsed, in the format's style at its
/// position; an interpolated `Text` or `AttributedString` keeps its runs.
/// `Text(verbatim:)` and a `String` value are never parsed.
public struct LocalizedStringKey: ExpressibleByStringInterpolation, Equatable, Sendable {
    /// One piece of a key, in order: format text as written, a value's
    /// description, or the runs of an interpolated `Text`/`AttributedString`.
    enum Segment: Equatable, Sendable {
        case format(String)
        case value(String)
        case runs([TextRunRequest])
    }

    /// The pieces, in order.
    var segments: [Segment]

    /// A key whose format is `value` — parsed as inline Markdown, unlike a
    /// `String` handed to `Text` directly (`M14`).
    public init(_ value: String) {
        segments = [.format(value)]
    }

    /// A key whose format is the literal `value`.
    public init(stringLiteral value: String) {
        segments = [.format(value)]
    }

    /// A key built by an interpolated literal: its format pieces and values.
    public init(stringInterpolation: StringInterpolation) {
        segments = stringInterpolation.segments
    }

    /// The pieces of an interpolated literal: format text, and each value
    /// verbatim (ruling RT-C item 3).
    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var segments: [Segment] = []

        /// Room for `literalCapacity` characters and `interpolationCount` values.
        public init(literalCapacity: Int, interpolationCount: Int) {
            segments.reserveCapacity(2 * interpolationCount + 1)
        }

        /// A piece of the literal's format — parsed as Markdown with the rest.
        public mutating func appendLiteral(_ literal: String) {
            guard !literal.isEmpty else { return }
            segments.append(.format(literal))
        }

        /// `value`'s `String(describing:)`, verbatim (ruling RT-C item 3):
        /// integers print as SwiftUI prints them, a floating-point value its
        /// Swift description (`3.5`, where SwiftUI prints `3.500000` —
        /// divergence 151). **Not deprecated** (divergence 156, `RT-O` item 6):
        /// SwiftUI deprecates this overload for types with no dedicated one.
        public mutating func appendInterpolation<T>(_ value: T) {
            segments.append(.value(String(describing: value)))
        }

        /// A `Text`'s runs (ruling RT-C item 4, `C14`): the same runs
        /// `Text + Text` would keep, styled by the format at its position where
        /// a run left a field unset. **A `Text` that carries anything but text
        /// traps** — a style, decoration, id or handler (ruling RT-E item 4,
        /// divergence 155).
        @MainActor
        public mutating func appendInterpolation(_ text: Text) {
            segments.append(.value(text.string))
        }

        /// An `AttributedString`'s runs (`RT-O` item 4, `I3`), read as
        /// `Text(_:)` reads them — never its description.
        public mutating func appendInterpolation(_ attributedString: AttributedString) {
            segments.append(.value(String(attributedString.characters)))
        }

        /// **Not offered**: SwiftUI draws an interpolated image inline (`I4`);
        /// MetalUI has no `Text(Image)` (ruling RT-A, `RT-O` item 5).
        @available(*, unavailable,
                   message: "interpolating an Image into Text is not offered (Text(Image) is deferred, ruling RT-A)")
        public mutating func appendInterpolation(_ image: Image) {}
    }
}

/// How many times a key's format went through the Markdown parser — a work
/// counter (`RT-O` item 14, spec test 3.16): a format with no trigger
/// character never does.
@MainActor var markdownParserRuns = 0

extension LocalizedStringKey {
    /// The content a `Text` made from this key shows (ruling RT-B): the format
    /// parsed as inline Markdown with each value inserted verbatim in the
    /// format's style at its position.
    @MainActor
    var textContent: TextContent {
        .plain(segments.map { segment in
            switch segment {
            case .format(let string), .value(let string): string
            case .runs(let runs): runs.map(\.string).joined()
            }
        }.joined())
    }
}

extension Text {
    /// A text leaf over a string literal (ruling RT-B; SwiftUI's
    /// `Text(_ key: LocalizedStringKey)`): the literal's format is parsed as
    /// inline Markdown — bold, italic, strikethrough, code, links and bare
    /// URLs — and each interpolated value is inserted verbatim in the format's
    /// style. A literal with no Markdown trigger character takes the plain
    /// path unparsed (`RT-O` item 14). `Text(verbatim:)` keeps a literal as
    /// written.
    public init(_ key: LocalizedStringKey) {
        self.init(content: key.textContent)
    }
}

extension ProposalText {
    /// A proposal-layout text leaf over a string literal, parsed as
    /// `Text`'s literal initialiser parses it (ruling RT-B).
    public init(_ key: LocalizedStringKey) {
        self.init(content: key.textContent)
    }
}
