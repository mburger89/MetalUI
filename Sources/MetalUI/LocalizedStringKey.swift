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
            requireTextOperand(text, "interpolated")
            segments.append(.runs(text.pushedRuns))
        }

        /// An `AttributedString`'s runs (`RT-O` item 4, `I3`), read as
        /// `Text(_:)` reads them — never its description.
        public mutating func appendInterpolation(_ attributedString: AttributedString) {
            segments.append(.runs(textRunRequests(attributedString)))
        }

        /// **Not offered — traps**: SwiftUI draws an interpolated image inline
        /// (`I4`); MetalUI has no `Text(Image)` (ruling RT-A). Deprecated, so
        /// the call site warns with this message, and trapping, so the image's
        /// description is never drawn: an `@available(*, unavailable)`
        /// overload cannot refuse it at compile time, because the generic
        /// overload outranks an unavailable one (ruling RT-T item 1, amending
        /// `RT-O` item 5).
        @available(*, deprecated, message: "interpolating an Image into Text is not offered (Text(Image) is deferred, ruling RT-A); it traps")
        public mutating func appendInterpolation(_ image: Image) {
            preconditionFailure("interpolating an Image into Text is not offered (Text(Image) is deferred, ruling RT-A)")
        }
    }
}

/// How many times a key's format went through the Markdown parser — a work
/// counter (`RT-O` item 14, spec test 3.16): a format with no trigger
/// character never does. Behind a lock, not the main actor: a `Text` is built
/// wherever its tree is (a 1 MB thread in
/// `everyProductionTreeBuildsOnAOneMegabyteThread`), and a main-actor counter
/// read from the parse would put a runtime isolation check in every literal's
/// initialiser (ruling RT-T item 5).
var markdownParserRuns: Int { markdownParserCounter.value }

/// The counter behind `markdownParserRuns`.
private final class MarkdownParserCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private let markdownParserCounter = MarkdownParserCounter()

extension LocalizedStringKey {
    /// The content a `Text` made from this key shows (ruling RT-B): the format
    /// parsed as inline Markdown with each value inserted verbatim in the
    /// format's style at its position.
    var textContent: TextContent {
        var runs: [TextRunRequest] = []
        let parses = segments.contains { segment in
            if case .format(let format) = segment { return markdownMayApply(format) }
            return false
        }
        if !parses {
            // No trigger character in the format (`RT-O` item 14): no parser.
            for segment in segments {
                switch segment {
                case .format(let string), .value(let string): runs.append(TextRunRequest(string: string))
                case .runs(let segmentRuns): runs += segmentRuns
                }
            }
            return collapsedTextContent(runs)
        }
        markdownParserCounter.increment()
        var units: [MarkdownUnit] = []
        var values: [Segment] = []
        for segment in segments {
            if case .format(let format) = segment {
                units += format.unicodeScalars.map { .scalar($0) }
            } else {
                units.append(.placeholder(values.count))
                values.append(segment)
            }
        }
        for piece in parseInlineMarkdown(units: units) {
            switch piece.content {
            case .text(let string):
                runs.append(markdownRunRequest(string, piece.attributes))
            case .placeholder(let index):
                switch values[index] {
                case .value(let string), .format(let string):
                    runs.append(markdownRunRequest(string, piece.attributes))
                case .runs(let valueRuns):
                    // The value's own fields win; the format's reach the unset
                    // ones (`M10b`, ruling RT-E item 2).
                    runs += valueRuns.map { markdownFilled($0, piece.attributes) }
                }
            }
        }
        return collapsedTextContent(runs)
    }
}

/// A run of `string` with the attributes Markdown gave it (ruling RT-B item
/// 5): strong → bold, emphasis → italic, strikethrough, code → monospaced,
/// link → `link`.
func markdownRunRequest(_ string: String, _ attributes: MarkdownRun) -> TextRunRequest {
    markdownFilled(TextRunRequest(string: string), attributes)
}

/// `run` with the Markdown attributes filling the fields it left unset.
func markdownFilled(_ run: TextRunRequest, _ attributes: MarkdownRun) -> TextRunRequest {
    var run = run
    if attributes.bold, run.weight == nil { run.weight = .bold }
    if attributes.italic, run.italic == nil { run.italic = true }
    if attributes.strikethrough, run.strikethrough == nil { run.strikethrough = .single }
    if attributes.code, run.monospaced == nil { run.monospaced = true }
    if let link = attributes.link, run.link == nil { run.link = link }
    return run
}

/// `runs` as a `Text`'s content: empty runs dropped, neighbours that agree
/// joined (`TextContent.joined`), and a single run that sets no field the
/// plain content it is.
func collapsedTextContent(_ runs: [TextRunRequest]) -> TextContent {
    let joined = TextContent.joined(runs.filter { !$0.string.isEmpty })
    if joined.isEmpty { return .plain("") }
    if joined.count == 1, joined[0] == TextRunRequest(string: joined[0].string) { return .plain(joined[0].string) }
    return .runs(joined)
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
