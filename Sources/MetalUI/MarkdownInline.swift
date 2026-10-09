// Rich text, lane 3 — MetalUI's own inline Markdown parser (ruling RT-B).
// Pure Swift, no Foundation: `AttributedString(markdown:)` does not exist on
// Linux (`L2`), so one parser runs on every platform, macOS included, and the
// suite holds it to Foundation's answers on macOS (spec test 3.2).
//
// The grammar is SwiftUI's, which is Foundation's
// `.inlineOnlyPreservingWhitespace` parse — cmark-gfm's inline parser with the
// strikethrough and autolink extensions, whitespace kept as written. This file
// follows cmark-gfm's algorithm step for step (its names in comments) so that
// the oracle corpus agrees run for run: a node list with a delimiter stack and
// a bracket stack (`inlines.c`), `process_emphasis` with CommonMark's rule of
// 3, the extensions' `~` delimiters and extended autolinks, and the e-mail
// post-pass over consolidated text. Then Foundation's conversion of the tree
// into runs: everything inside a link or an image is flattened to plain text
// carrying only the attributes outside it (`M22`).
//
// An interpolated value is a **placeholder unit** (ruling RT-C item 3): never
// markup, never part of a link destination, an autolink, an entity or raw
// HTML, and — for the delimiter rules — neither whitespace nor punctuation
// (ruling RT-T item 3).

/// One unit of a format: a Unicode scalar, or the position of an interpolated
/// value (ruling RT-C item 3).
enum MarkdownUnit: Equatable, Sendable {
    case scalar(Unicode.Scalar)
    case placeholder(Int)
}

/// One run of parsed inline Markdown: its text and the attributes the
/// Markdown gave it (ruling RT-B item 5).
struct MarkdownRun: Equatable, Sendable, CustomStringConvertible {
    var text: String
    var bold = false
    var italic = false
    var strikethrough = false
    var code = false
    /// A link's destination (`RT-K`), as Foundation's `URL.absoluteString`
    /// prints it.
    var link: String?

    var description: String {
        var parts = [text.debugDescription]
        if bold { parts.append("bold") }
        if italic { parts.append("italic") }
        if strikethrough { parts.append("strike") }
        if code { parts.append("code") }
        if let link { parts.append("link=\(link)") }
        return "[" + parts.joined(separator: " ") + "]"
    }

    /// Whether every attribute but the text equals `other`'s.
    func hasSameAttributes(as other: MarkdownRun) -> Bool {
        bold == other.bold && italic == other.italic && strikethrough == other.strikethrough
            && code == other.code && link == other.link
    }
}

/// One piece of a parsed format: text, or the interpolated value at that
/// position (its index), each with the attributes the Markdown gave it.
struct MarkdownPiece: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case text(String)
        case placeholder(Int)
    }
    var content: Content
    var attributes: MarkdownRun
}

/// `source` parsed as SwiftUI's inline Markdown (ruling RT-B): runs in order,
/// neighbours with equal attributes joined.
func parseInlineMarkdown(_ source: String) -> [MarkdownRun] {
    joinedMarkdownRuns(parseInlineMarkdown(units: source.unicodeScalars.map { .scalar($0) }).compactMap { piece in
        guard case .text(let text) = piece.content else { return nil }
        var run = piece.attributes
        run.text = text
        return run
    })
}

/// `runs` with neighbours whose attributes agree joined, and empty runs
/// dropped.
func joinedMarkdownRuns(_ runs: [MarkdownRun]) -> [MarkdownRun] {
    var result: [MarkdownRun] = []
    for run in runs where !run.text.isEmpty {
        if let last = result.last, last.hasSameAttributes(as: run) {
            result[result.count - 1].text += run.text
        } else {
            result.append(run)
        }
    }
    return result
}

/// Whether `format` can hold Markdown at all (`RT-O` item 14, amended by
/// ruling RT-T item 4): a delimiter (`*`, `_`, `~`, a backtick), a bracket,
/// `<`, `&`, a backslash, `@`, `://` (every extended URL autolink, whatever its
/// scheme or its case) or `www.`. A format with none parses to itself, so it
/// never reaches the parser.
func markdownMayApply(_ format: String) -> Bool {
    var last3: (Unicode.Scalar, Unicode.Scalar, Unicode.Scalar) = (" ", " ", " ")
    for scalar in format.unicodeScalars {
        switch scalar {
        case "*", "_", "~", "`", "[", "<", "&", "\\", "@": return true
        case "/" where last3.1 == ":" && last3.2 == "/": return true
        case "." where last3 == ("w", "w", "w"): return true
        default: break
        }
        last3 = (last3.1, last3.2, scalar)
    }
    return false
}

/// `units` parsed as one inline Markdown format (rulings RT-B, RT-C item 3):
/// pieces in order, a placeholder at each value's position carrying the
/// attributes the format gives it there.
func parseInlineMarkdown(units: [MarkdownUnit]) -> [MarkdownPiece] {
    var parser = InlineMarkdownParser(units)
    parser.parse()
    return parser.pieces()
}

// MARK: - Character classes (cmark's utf8proc helpers)

private extension MarkdownUnit {
    /// The scalar, `nil` for a placeholder.
    var scalar: Unicode.Scalar? {
        if case .scalar(let s) = self { return s }
        return nil
    }

    /// `cmark_utf8proc_is_space`; a placeholder is not.
    var isSpace: Bool { scalar.map(markdownIsSpace) ?? false }

    /// `cmark_utf8proc_is_punctuation`; a placeholder is not (ruling RT-T item 3).
    var isPunctuation: Bool { scalar.map(markdownIsPunctuation) ?? false }

    /// `cmark_isspace` (ASCII whitespace).
    var isASCIISpace: Bool {
        guard let s = scalar else { return false }
        return s == " " || s == "\t" || s == "\n" || s == "\u{0B}" || s == "\u{0C}" || s == "\r"
    }

    var isASCIIAlpha: Bool {
        guard let s = scalar else { return false }
        return (s >= "a" && s <= "z") || (s >= "A" && s <= "Z")
    }

    var isASCIIDigit: Bool {
        guard let s = scalar else { return false }
        return s >= "0" && s <= "9"
    }

    var isASCIIAlphanumeric: Bool { isASCIIAlpha || isASCIIDigit }

    var isASCIIPunctuation: Bool { scalar.map(markdownIsASCIIPunctuation) ?? false }

    func `is`(_ s: Unicode.Scalar) -> Bool { scalar == s }
}

private func markdownIsSpace(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 9, 10, 12, 13, 32, 160, 5760, 8192...8202, 8239, 8287, 12288: true
    default: false
    }
}

private func markdownIsASCIIPunctuation(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 33...47, 58...64, 91...96, 123...126: true
    default: false
    }
}

private func markdownIsPunctuation(_ s: Unicode.Scalar) -> Bool {
    if s.isASCII { return markdownIsASCIIPunctuation(s) }
    switch s.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
         .finalPunctuation, .otherPunctuation:
        return true
    default:
        return false
    }
}

/// `units` as a string, placeholders dropped.
private func markdownString(_ units: some Sequence<MarkdownUnit>) -> String {
    var s = ""
    for u in units { if case .scalar(let scalar) = u { s.unicodeScalars.append(scalar) } }
    return s
}

/// Whether `units` starts with exactly the scalars of `prefix`.
private func markdownHasPrefix(_ units: ArraySlice<MarkdownUnit>, _ prefix: String) -> Bool {
    var i = units.startIndex
    for s in prefix.unicodeScalars {
        guard i < units.endIndex, units[i] == .scalar(s) else { return false }
        i += 1
    }
    return true
}

// MARK: - The parser (cmark-gfm `inlines.c`)

/// An inline node in an arena: a doubly linked tree, as cmark's.
private struct InlineNode {
    enum Kind: Equatable {
        case root, text, code, emphasis, strong, strikethrough, link(String), image, lineBreak, html
    }
    var kind: Kind
    var units: [MarkdownUnit] = []
    var parent = -1, first = -1, last = -1, prev = -1, next = -1
}

/// A delimiter run on the stack (`delimiter`).
private struct Delimiter {
    var node: Int
    var character: Unicode.Scalar
    /// The run's original length (cmark-gfm's `length`, read by the rule of 3).
    var length: Int
    var canOpen: Bool
    var canClose: Bool
    /// The source offset just past the run.
    var position: Int
}

/// An open bracket (`bracket`).
private struct Bracket {
    var node: Int
    var position: Int
    var image: Bool
    var active = true
}

private struct InlineMarkdownParser {
    let input: [MarkdownUnit]
    var pos = 0
    var nodes = [InlineNode(kind: .root)]
    var delimiters: [Delimiter] = []
    var brackets: [Bracket] = []

    init(_ input: [MarkdownUnit]) { self.input = input }

    // MARK: Tree operations

    mutating func makeNode(_ kind: InlineNode.Kind, _ units: [MarkdownUnit] = []) -> Int {
        nodes.append(InlineNode(kind: kind, units: units))
        return nodes.count - 1
    }

    mutating func unlink(_ n: Int) {
        let node = nodes[n]
        if node.prev >= 0 { nodes[node.prev].next = node.next }
        if node.next >= 0 { nodes[node.next].prev = node.prev }
        if node.parent >= 0 {
            if nodes[node.parent].first == n { nodes[node.parent].first = node.next }
            if nodes[node.parent].last == n { nodes[node.parent].last = node.prev }
        }
        nodes[n].parent = -1
        nodes[n].prev = -1
        nodes[n].next = -1
    }

    mutating func appendChild(_ parent: Int, _ child: Int) {
        unlink(child)
        let last = nodes[parent].last
        nodes[child].parent = parent
        nodes[child].prev = last
        if last >= 0 { nodes[last].next = child } else { nodes[parent].first = child }
        nodes[parent].last = child
    }

    mutating func insertAfter(_ anchor: Int, _ node: Int) {
        unlink(node)
        let parent = nodes[anchor].parent
        let next = nodes[anchor].next
        nodes[node].parent = parent
        nodes[node].prev = anchor
        nodes[node].next = next
        nodes[anchor].next = node
        if next >= 0 { nodes[next].prev = node } else if parent >= 0 { nodes[parent].last = node }
    }

    mutating func insertBefore(_ anchor: Int, _ node: Int) {
        unlink(node)
        let parent = nodes[anchor].parent
        let prev = nodes[anchor].prev
        nodes[node].parent = parent
        nodes[node].next = anchor
        nodes[node].prev = prev
        nodes[anchor].prev = node
        if prev >= 0 { nodes[prev].next = node } else if parent >= 0 { nodes[parent].first = node }
    }

    mutating func appendText(_ units: [MarkdownUnit]) {
        appendChild(0, makeNode(.text, units))
    }

    func scalars(_ string: String) -> [MarkdownUnit] { string.unicodeScalars.map { .scalar($0) } }

    func unit(at i: Int) -> MarkdownUnit? { i >= 0 && i < input.count ? input[i] : nil }

    // MARK: The main loop (`parse_inline`)

    mutating func parse() {
        while pos < input.count {
            guard let c = input[pos].scalar else {
                appendText([input[pos]])
                pos += 1
                continue
            }
            switch c {
            case "`": handleBackticks()
            case "\\": handleBackslash()
            case "&": handleEntity()
            case "<": handlePointyBrace()
            case "*", "_": handleDelimiter(c)
            case "~": handleTilde()
            case "[":
                pos += 1
                let node = makeNode(.text, scalars("["))
                appendChild(0, node)
                brackets.append(Bracket(node: node, position: pos, image: false))
            case "]": handleCloseBracket()
            case "!" where unit(at: pos + 1)?.is("[") == true:
                pos += 2
                let node = makeNode(.text, scalars("!["))
                appendChild(0, node)
                brackets.append(Bracket(node: node, position: pos, image: true))
            case ":" where brackets.isEmpty && urlMatch():
                break
            case "w" where brackets.isEmpty && wwwMatch():
                break
            default:
                appendText([input[pos]])
                pos += 1
            }
        }
        processEmphasis(stackBottom: 0)
        consolidateText(0)
        linkEmailAddresses(0)
    }

    // MARK: Code spans (`handle_backticks`)

    mutating func handleBackticks() {
        let start = pos
        while unit(at: pos)?.is("`") == true { pos += 1 }
        let openLength = pos - start
        var scan = pos
        while scan < input.count {
            guard input[scan].is("`") else {
                scan += 1
                continue
            }
            let runStart = scan
            while unit(at: scan)?.is("`") == true { scan += 1 }
            if scan - runStart == openLength {
                appendChild(0, makeNode(.code, normalizedCode(Array(input[pos..<runStart]))))
                pos = scan
                return
            }
        }
        appendText(Array(input[start..<pos]))
    }

    /// `S_normalize_code`: line endings become spaces; one space is stripped
    /// from each end when both ends are spaces and the content is not all
    /// spaces.
    func normalizedCode(_ content: [MarkdownUnit]) -> [MarkdownUnit] {
        var out: [MarkdownUnit] = []
        var containsNonSpace = false
        for (i, u) in content.enumerated() {
            if u.is("\r") {
                if i + 1 >= content.count || !content[i + 1].is("\n") { out.append(.scalar(" ")) }
            } else if u.is("\n") {
                out.append(.scalar(" "))
            } else {
                out.append(u)
            }
            if !u.is(" "), !u.is("\n"), !u.is("\r") { containsNonSpace = true }   // a line ending reads as its space
        }
        if containsNonSpace, out.count >= 2, out.first?.is(" ") == true, out.last?.is(" ") == true {
            return Array(out.dropFirst().dropLast())
        }
        return out
    }

    // MARK: Backslash (`handle_backslash`)

    mutating func handleBackslash() {
        pos += 1
        if let next = unit(at: pos), next.isASCIIPunctuation {
            appendText([next])
            pos += 1
        } else if let next = unit(at: pos), next.is("\n") || next.is("\r") {
            pos += 1
            if next.is("\r"), unit(at: pos)?.is("\n") == true { pos += 1 }
            appendChild(0, makeNode(.lineBreak))
        } else {
            appendText(scalars("\\"))
        }
    }

    // MARK: Entities (`handle_entity`, houdini; the named subset — divergence 153)

    mutating func handleEntity() {
        pos += 1
        if let (decoded, length) = decodeEntity(at: pos) {
            appendText(decoded)
            pos += length
        } else {
            appendText(scalars("&"))
        }
    }

    /// The entity after a `&`, from `start`: its scalars and how many units it
    /// spans (the `;` included), or `nil`.
    func decodeEntity(at start: Int) -> ([MarkdownUnit], Int)? {
        guard let first = unit(at: start) else { return nil }
        if first.is("#") {
            var i = start + 1
            var codepoint: UInt32 = 0
            var digits = 0
            if unit(at: i)?.isASCIIDigit == true {
                while let s = unit(at: i)?.scalar, s >= "0", s <= "9" {
                    codepoint = min(codepoint * 10 + (s.value - 48), 0x110000)
                    i += 1
                }
                digits = i - start - 1
            } else if unit(at: i)?.is("x") == true || unit(at: i)?.is("X") == true {
                i += 1
                while let s = unit(at: i)?.scalar, let v = hexValue(s) {
                    codepoint = min(codepoint * 16 + v, 0x110000)
                    i += 1
                }
                digits = i - start - 2
            }
            guard digits >= 1, digits <= 8, unit(at: i)?.is(";") == true else { return nil }
            if codepoint == 0 || (codepoint >= 0xD800 && codepoint < 0xE000) || codepoint >= 0x110000 {
                codepoint = 0xFFFD
            }
            return ([.scalar(Unicode.Scalar(codepoint) ?? "\u{FFFD}")], i - start + 1)
        }
        var name = ""
        var i = start
        while i - start < 32, let u = unit(at: i), u.isASCIIAlphanumeric, let s = u.scalar {
            name.unicodeScalars.append(s)
            i += 1
        }
        guard !name.isEmpty, unit(at: i)?.is(";") == true, let value = markdownNamedEntities[name] else { return nil }
        return ([.scalar(value)], i - start + 1)
    }

    func hexValue(_ s: Unicode.Scalar) -> UInt32? {
        switch s {
        case "0"..."9": s.value - 48
        case "a"..."f": s.value - 87
        case "A"..."F": s.value - 55
        default: nil
        }
    }

    /// Entity-decoded `units` (`houdini_unescape_html_f`).
    func entityDecoded(_ units: [MarkdownUnit]) -> [MarkdownUnit] {
        var out: [MarkdownUnit] = []
        var i = 0
        let sub = InlineMarkdownParser(units)
        while i < units.count {
            if units[i].is("&"), let (decoded, length) = sub.decodeEntity(at: i + 1) {
                out += decoded
                i += 1 + length
            } else {
                out.append(units[i])
                i += 1
            }
        }
        return out
    }

    // MARK: `<` — autolinks and raw HTML (`handle_pointy_brace`)

    mutating func handlePointyBrace() {
        pos += 1
        if let length = scanAutolinkURI(at: pos) {
            let decoded = entityDecoded(Array(input[pos..<(pos + length - 1)]))
            let link = makeNode(.link(markdownString(decoded)))
            appendChild(link, makeNode(.text, decoded))
            appendChild(0, link)
            pos += length
        } else if let length = scanAutolinkEmail(at: pos) {
            let decoded = entityDecoded(Array(input[pos..<(pos + length - 1)]))
            let link = makeNode(.link("mailto:" + markdownString(decoded)))
            appendChild(link, makeNode(.text, decoded))
            appendChild(0, link)
            pos += length
        } else if let length = scanHTMLTag(at: pos) {
            appendChild(0, makeNode(.html, Array(input[(pos - 1)..<(pos + length)])))
            pos += length
        } else {
            appendText(scalars("<"))
        }
    }

    /// `scan_autolink_uri`: `scheme ':' [^\x00-\x20<>]* '>'` — the length,
    /// the `>` included.
    func scanAutolinkURI(at start: Int) -> Int? {
        var i = start
        guard unit(at: i)?.isASCIIAlpha == true else { return nil }
        i += 1
        while let u = unit(at: i), u.isASCIIAlphanumeric || u.is("+") || u.is(".") || u.is("-") { i += 1 }
        guard (2...32).contains(i - start), unit(at: i)?.is(":") == true else { return nil }
        i += 1
        while let u = unit(at: i) {
            guard let s = u.scalar else { return nil }
            if s == ">" { return i - start + 1 }
            if s.value <= 0x20 || s == "<" { return nil }
            i += 1
        }
        return nil
    }

    /// `scan_autolink_email` — the length, the `>` included.
    func scanAutolinkEmail(at start: Int) -> Int? {
        var i = start
        let localSpecials = Set(".!#$%&'*+/=?^_`{|}~-".unicodeScalars)
        while let u = unit(at: i), u.isASCIIAlphanumeric || (u.scalar.map(localSpecials.contains) ?? false) { i += 1 }
        guard i > start, unit(at: i)?.is("@") == true else { return nil }
        i += 1
        while true {
            // A label: [a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
            guard unit(at: i)?.isASCIIAlphanumeric == true else { return nil }
            let labelStart = i
            i += 1
            while let u = unit(at: i), u.isASCIIAlphanumeric || u.is("-") { i += 1 }
            while i > labelStart + 1, unit(at: i - 1)?.is("-") == true { i -= 1 }
            guard i - labelStart <= 63 else { return nil }
            guard unit(at: i)?.is(".") == true, unit(at: i + 1)?.isASCIIAlphanumeric == true else { break }
            i += 1
        }
        guard unit(at: i)?.is(">") == true else { return nil }
        return i - start + 1
    }

    /// `scan_html_tag`, after the `<`: an open or closing tag, a comment, a
    /// processing instruction, a declaration or CDATA — the length.
    func scanHTMLTag(at start: Int) -> Int? {
        guard let first = unit(at: start)?.scalar else { return nil }
        func isSpaceChar(_ i: Int) -> Bool { unit(at: i)?.isASCIISpace ?? false }
        func tagName(_ i: inout Int) -> Bool {
            guard unit(at: i)?.isASCIIAlpha == true else { return false }
            i += 1
            while let u = unit(at: i), u.isASCIIAlphanumeric || u.is("-") { i += 1 }
            return true
        }
        /// Advances past the first `terminator`; `false` at the end or a placeholder.
        func scan(_ i: inout Int, through terminator: String) -> Bool {
            while i < input.count {
                guard input[i].scalar != nil else { return false }
                if markdownHasPrefix(input[i...], terminator) {
                    i += terminator.unicodeScalars.count
                    return true
                }
                i += 1
            }
            return false
        }
        var i = start
        switch first {
        case "/":
            i += 1
            guard tagName(&i) else { return nil }
            while isSpaceChar(i) { i += 1 }
            guard unit(at: i)?.is(">") == true else { return nil }
            return i - start + 1
        case "?":
            i += 1
            return scan(&i, through: "?>") ? i - start : nil
        case "!":
            i += 1
            if markdownHasPrefix(input[i...], "--") {
                i += 2
                if markdownHasPrefix(input[i...], ">") || markdownHasPrefix(input[i...], "->") { return nil }
                let bodyStart = i
                guard scan(&i, through: "-->") else { return nil }
                let body = input[bodyStart..<(i - 3)]
                for j in body.indices.dropLast() where body[j].is("-") && body[j + 1].is("-") { return nil }
                if body.last?.is("-") == true { return nil }
                return i - start
            }
            if markdownHasPrefix(input[i...], "[CDATA[") {
                i += 7
                return scan(&i, through: "]]>") ? i - start : nil
            }
            guard let s = unit(at: i)?.scalar, s >= "A", s <= "Z" else { return nil }
            while let s = unit(at: i)?.scalar, s >= "A", s <= "Z" { i += 1 }
            guard isSpaceChar(i) else { return nil }
            return scan(&i, through: ">") ? i - start : nil
        default:
            guard tagName(&i) else { return nil }
            // attribute*: spacechar+ name (spacechar* '=' spacechar* value)?
            while isSpaceChar(i) {
                var j = i
                while isSpaceChar(j) { j += 1 }
                guard let u = unit(at: j), u.isASCIIAlpha || u.is("_") || u.is(":") else { break }
                j += 1
                while let u = unit(at: j), u.isASCIIAlphanumeric || u.is(":") || u.is(".") || u.is("_") || u.is("-") {
                    j += 1
                }
                var k = j
                while isSpaceChar(k) { k += 1 }
                if unit(at: k)?.is("=") == true {
                    k += 1
                    while isSpaceChar(k) { k += 1 }
                    guard let q = unit(at: k)?.scalar else { return nil }
                    if q == "\"" || q == "'" {
                        k += 1
                        while let u = unit(at: k), !u.is(q) {
                            guard u.scalar != nil else { return nil }
                            k += 1
                        }
                        guard unit(at: k) != nil else { return nil }
                        k += 1
                    } else {
                        let valueStart = k
                        while let u = unit(at: k), let s = u.scalar, !"\"'=<>`".unicodeScalars.contains(s),
                              !u.isASCIISpace { k += 1 }
                        guard k > valueStart else { return nil }
                    }
                    j = k
                }
                i = j
            }
            while isSpaceChar(i) { i += 1 }
            if unit(at: i)?.is("/") == true { i += 1 }
            guard unit(at: i)?.is(">") == true else { return nil }
            return i - start + 1
        }
    }

    // MARK: Emphasis delimiters (`handle_delim`, `scan_delims`)

    /// The run of `c` at `pos`, consumed: its length, flanking and neighbours
    /// (the start and end read as a newline; a placeholder is neither space
    /// nor punctuation).
    ///
    /// For `*` and `_` (`skippingTildes`), cmark-gfm's **skip characters**
    /// apply: the strikethrough extension registers `~` as an emphasis
    /// character, so the neighbour before a run is found by walking back over
    /// every `~` and the one after it by walking forward over every `~`; the
    /// start or the end reached that way reads as a newline (measured against
    /// Foundation: `*_**~` emphasises where `*_**!` does not, and `**~~** `
    /// is bold `~~` — ruling RT-T item 2).
    mutating func scanDelimiters(_ c: Unicode.Scalar, max: Int = .max, skippingTildes: Bool = false)
        -> (count: Int, left: Bool, right: Bool, before: MarkdownUnit?, after: MarkdownUnit?) {
        var before = unit(at: pos - 1)
        if skippingTildes, pos > 0 {
            var j = pos - 1
            while j > 0, input[j].is("~") { j -= 1 }
            before = input[j].is("~") ? nil : input[j]
        }
        var count = 0
        while count < max, unit(at: pos)?.is(c) == true {
            count += 1
            pos += 1
        }
        var after = unit(at: pos)
        if skippingTildes {
            var j = pos
            while unit(at: j)?.is("~") == true { j += 1 }
            after = unit(at: j)
        }
        let beforeSpace = before?.isSpace ?? true, afterSpace = after?.isSpace ?? true
        let beforePunct = before?.isPunctuation ?? false, afterPunct = after?.isPunctuation ?? false
        let left = count > 0 && !afterSpace && (!afterPunct || beforeSpace || beforePunct)
        let right = count > 0 && !beforeSpace && (!beforePunct || afterSpace || afterPunct)
        return (count, left, right, before, after)
    }

    mutating func handleDelimiter(_ c: Unicode.Scalar) {
        let run = scanDelimiters(c, skippingTildes: true)
        let canOpen: Bool, canClose: Bool
        if c == "_" {
            canOpen = run.left && (!run.right || (run.before?.isPunctuation ?? false))
            canClose = run.right && (!run.left || (run.after?.isPunctuation ?? false))
        } else {
            canOpen = run.left
            canClose = run.right
        }
        let node = makeNode(.text, Array(repeating: .scalar(c), count: run.count))
        appendChild(0, node)
        if canOpen || canClose {
            delimiters.append(Delimiter(node: node, character: c, length: run.count, canOpen: canOpen,
                                        canClose: canClose, position: pos))
        }
    }

    /// The strikethrough extension's `match`: `~` or `~~` (never three or
    /// more), opening and closing by flanking alone.
    mutating func handleTilde() {
        let run = scanDelimiters("~", max: 100)
        let node = makeNode(.text, Array(repeating: .scalar("~"), count: run.count))
        appendChild(0, node)
        if run.left || run.right, run.count == 1 || run.count == 2 {
            delimiters.append(Delimiter(node: node, character: "~", length: run.count, canOpen: run.left,
                                        canClose: run.right, position: pos))
        }
    }

    // MARK: `process_emphasis`

    mutating func processEmphasis(stackBottom: Int) {
        var openersBottom: [Int: Int] = [:]
        func key(_ d: Delimiter) -> Int { (d.length % 3) << 8 | Int(d.character.value & 0xFF) }
        var closer = delimiters.firstIndex { $0.position >= stackBottom } ?? delimiters.count
        while closer < delimiters.count {
            let c = delimiters[closer]
            guard c.canClose else {
                closer += 1
                continue
            }
            let bottom = max(stackBottom, openersBottom[key(c)] ?? stackBottom)
            var opener = closer - 1
            var found = false
            while opener >= 0, delimiters[opener].position >= bottom {
                let o = delimiters[opener]
                // Rule of 3: an interior run of one length cannot close another
                // unless their sum is no multiple of 3.
                if o.canOpen, o.character == c.character,
                   !(c.canOpen || o.canClose) || c.length % 3 == 0 || (o.length + c.length) % 3 != 0 {
                    found = true
                    break
                }
                opener -= 1
            }
            if found {
                closer = c.character == "~" ? insertStrikethrough(opener, closer) : insertEmphasis(opener, closer)
            } else {
                openersBottom[key(c)] = c.position
                if c.canOpen { closer += 1 } else { delimiters.remove(at: closer) }
            }
        }
        delimiters.removeAll { $0.position >= stackBottom }
    }

    /// `S_insert_emph`: wraps what lies between the two runs; the index of the
    /// next closer to consider.
    mutating func insertEmphasis(_ opener: Int, _ closer: Int) -> Int {
        let openerNode = delimiters[opener].node, closerNode = delimiters[closer].node
        let use = nodes[closerNode].units.count >= 2 && nodes[openerNode].units.count >= 2 ? 2 : 1
        nodes[openerNode].units.removeLast(use)
        nodes[closerNode].units.removeLast(use)
        delimiters.removeSubrange((opener + 1)..<closer)
        var closerIndex = opener + 1
        let emphasis = makeNode(use == 1 ? .emphasis : .strong)
        var node = nodes[openerNode].next
        while node >= 0, node != closerNode {
            let next = nodes[node].next
            appendChild(emphasis, node)
            node = next
        }
        insertAfter(openerNode, emphasis)
        if nodes[openerNode].units.isEmpty {
            unlink(openerNode)
            delimiters.remove(at: opener)
            closerIndex -= 1
        }
        if nodes[closerNode].units.isEmpty {
            unlink(closerNode)
            delimiters.remove(at: closerIndex)
        }
        return closerIndex
    }

    /// The strikethrough extension's `insert` (equal runs only): the index of
    /// the next closer.
    mutating func insertStrikethrough(_ opener: Int, _ closer: Int) -> Int {
        let openerNode = delimiters[opener].node, closerNode = delimiters[closer].node
        if nodes[openerNode].units.count == nodes[closerNode].units.count {
            nodes[openerNode].kind = .strikethrough
            nodes[openerNode].units = []
            var node = nodes[openerNode].next
            while node >= 0, node != closerNode {
                let next = nodes[node].next
                appendChild(openerNode, node)
                node = next
            }
            unlink(closerNode)
        }
        delimiters.removeSubrange(opener...closer)
        return opener
    }

    // MARK: Links (`handle_close_bracket`)

    mutating func handleCloseBracket() {
        pos += 1
        let initialPos = pos
        guard let opener = brackets.last else {
            appendText(scalars("]"))
            return
        }
        guard opener.active else {
            brackets.removeLast()
            appendText(scalars("]"))
            return
        }
        // An inline link: '(' spaces destination (spaces title)? spaces ')'.
        if unit(at: pos)?.is("(") == true {
            let afterSpaces = skipSpaceChars(pos + 1)
            if let (destination, length) = scanLinkDestination(at: afterSpaces) {
                let endURL = afterSpaces + length
                let startTitle = skipSpaceChars(endURL)
                let endTitle = startTitle == endURL ? startTitle : startTitle + scanLinkTitle(at: startTitle)
                let endAll = skipSpaceChars(endTitle)
                if unit(at: endAll)?.is(")") == true {
                    pos = endAll + 1
                    let url = markdownString(backslashUnescaped(entityDecoded(trimmed(destination))))
                    let link = makeNode(opener.image ? .image : .link(url))
                    insertBefore(opener.node, link)
                    var node = nodes[opener.node].next
                    while node >= 0 {
                        let next = nodes[node].next
                        appendChild(link, node)
                        node = next
                    }
                    unlink(opener.node)
                    processEmphasis(stackBottom: opener.position)
                    brackets.removeLast()
                    if !opener.image {
                        // No link inside a link: earlier `[` openers deactivate.
                        for i in brackets.indices.reversed() where !brackets[i].image {
                            if !brackets[i].active { break }
                            brackets[i].active = false
                        }
                    }
                    return
                }
            }
        }
        // No reference definitions inline, so a reference link never matches.
        brackets.removeLast()
        pos = initialPos
        appendText(scalars("]"))
    }

    /// `scan_spacechars`.
    func skipSpaceChars(_ start: Int) -> Int {
        var i = start
        while unit(at: i)?.isASCIISpace == true { i += 1 }
        return i
    }

    /// `manual_scan_link_url`: the destination's units and the length scanned;
    /// a placeholder ends the scan unmatched (ruling RT-T item 3).
    func scanLinkDestination(at start: Int) -> ([MarkdownUnit], Int)? {
        var i = start
        if unit(at: i)?.is("<") == true {
            i += 1
            while i < input.count {
                let u = input[i]
                guard u.scalar != nil else { return nil }
                if u.is(">") {
                    i += 1
                    guard i < input.count else { return nil }
                    return (Array(input[(start + 1)..<(i - 1)]), i - start)
                } else if u.is("\\") {
                    i += 2
                } else if u.is("\n") || u.is("<") {
                    return nil
                } else {
                    i += 1
                }
            }
            return nil
        }
        var parens = 0
        while i < input.count {
            let u = input[i]
            guard u.scalar != nil else { return nil }
            if u.is("\\"), unit(at: i + 1)?.isASCIIPunctuation == true {
                i += 2
            } else if u.is("(") {
                parens += 1
                i += 1
                if parens > 32 { return nil }
            } else if u.is(")") {
                if parens == 0 { break }
                parens -= 1
                i += 1
            } else if u.isASCIISpace {
                if i == start { return nil }
                break
            } else {
                i += 1
            }
        }
        guard i < input.count else { return nil }
        return (Array(input[start..<i]), i - start)
    }

    /// `scan_link_title`: the length of a quoted or parenthesised title, else 0.
    func scanLinkTitle(at start: Int) -> Int {
        guard let open = unit(at: start)?.scalar else { return 0 }
        let close: Unicode.Scalar
        switch open {
        case "\"": close = "\""
        case "'": close = "'"
        case "(": close = ")"
        default: return 0
        }
        var i = start + 1
        while let u = unit(at: i) {
            guard u.scalar != nil else { return 0 }
            if u.is("\\"), unit(at: i + 1)?.isASCIIPunctuation == true {
                i += 2
                continue
            }
            if u.is(close) { return i - start + 1 }
            if open == "(", u.is("(") { return 0 }
            i += 1
        }
        return 0
    }

    func trimmed(_ units: [MarkdownUnit]) -> [MarkdownUnit] {
        var slice = units[...]
        while slice.first?.isASCIISpace == true { slice.removeFirst() }
        while slice.last?.isASCIISpace == true { slice.removeLast() }
        return Array(slice)
    }

    /// `cmark_strbuf_unescape`: a backslash before ASCII punctuation drops.
    func backslashUnescaped(_ units: [MarkdownUnit]) -> [MarkdownUnit] {
        var out: [MarkdownUnit] = []
        var i = 0
        while i < units.count {
            if units[i].is("\\"), i + 1 < units.count, units[i + 1].isASCIIPunctuation {
                out.append(units[i + 1])
                i += 2
            } else {
                out.append(units[i])
                i += 1
            }
        }
        return out
    }

    // MARK: Extended autolinks (cmark-gfm `autolink.c`)

    /// `www_match` at a `w`: a `www.` link, preceded by the start, whitespace
    /// or one of `*_~(`.
    mutating func wwwMatch() -> Bool {
        if pos > 0 {
            guard let before = input[pos - 1].scalar,
                  "*_~(".unicodeScalars.contains(before) || input[pos - 1].isASCIISpace else { return false }
        }
        guard markdownHasPrefix(input[pos...], "www.") else { return false }
        let data = Array(input[pos...])
        var linkEnd = checkDomain(data[...], allowShort: false)
        guard linkEnd > 0 else { return false }
        linkEnd = extendedLinkEnd(data, from: linkEnd)
        guard linkEnd > 0 else { return false }
        let text = Array(data[..<linkEnd])
        let link = makeNode(.link("http://" + markdownString(text)))
        appendChild(link, makeNode(.text, text))
        appendChild(0, link)
        pos += linkEnd
        return true
    }

    /// `url_match` at a `:`: `http://`, `https://` or `ftp://` in any case,
    /// its scheme taken back from the text before it.
    mutating func urlMatch() -> Bool {
        let data = Array(input[pos...])
        guard data.count >= 4, data[1].is("/"), data[2].is("/") else { return false }
        var rewind = 0
        while rewind < pos, input[pos - rewind - 1].isASCIIAlpha { rewind += 1 }
        guard autolinkIsSafe(input[(pos - rewind)...]) else { return false }
        let domainLength = checkDomain(data[3...], allowShort: true)
        guard domainLength > 0 else { return false }
        let linkEnd = extendedLinkEnd(data, from: 3 + domainLength)
        guard linkEnd > 0 else { return false }
        unput(rewind)
        let text = Array(input[(pos - rewind)..<(pos + linkEnd)])
        let link = makeNode(.link(markdownString(text)))
        appendChild(link, makeNode(.text, text))
        appendChild(0, link)
        pos += linkEnd
        return true
    }

    /// An extended link runs to whitespace, a `<` or a placeholder, then
    /// `autolink_delim` trims its end.
    func extendedLinkEnd(_ data: [MarkdownUnit], from start: Int) -> Int {
        var linkEnd = start
        while linkEnd < data.count, data[linkEnd].scalar != nil, !data[linkEnd].isASCIISpace, !data[linkEnd].is("<") {
            linkEnd += 1
        }
        return autolinkDelimiter(data, linkEnd)
    }

    /// `cmark_node_unput`: drops `count` units from the end of the trailing
    /// text nodes.
    mutating func unput(_ count: Int) {
        var n = count
        var node = nodes[0].last
        while n > 0, node >= 0, nodes[node].kind == .text {
            let length = nodes[node].units.count
            if length < n {
                n -= length
                nodes[node].units = []
            } else {
                nodes[node].units.removeLast(n)
                n = 0
            }
            node = nodes[node].prev
        }
    }

    /// `sd_autolink_issafe`: the scheme, case-insensitively, then an
    /// alphanumeric.
    func autolinkIsSafe(_ link: ArraySlice<MarkdownUnit>) -> Bool {
        for scheme in ["http://", "https://", "ftp://"] {
            let expected = Array(scheme.unicodeScalars)
            guard link.count > expected.count else { continue }
            var matches = true
            for (offset, e) in expected.enumerated() {
                guard let c = link[link.startIndex + offset].scalar else {
                    matches = false
                    break
                }
                let lower = c >= "A" && c <= "Z" ? Unicode.Scalar(c.value + 32)! : c
                if lower != e {
                    matches = false
                    break
                }
            }
            if matches, link[link.startIndex + expected.count].isASCIIAlphanumeric { return true }
        }
        return false
    }

    /// `check_domain`: how much of `data` is a domain (its first unit taken as
    /// valid; the last unit never examined, as cmark-gfm's loop), `0` when an
    /// underscore sits in one of its last two labels or — unless
    /// `allowShort` — it has no dot.
    func checkDomain(_ data: ArraySlice<MarkdownUnit>, allowShort: Bool) -> Int {
        let units = Array(data)
        var i = 1, dots = 0, underscoresBefore = 0, underscores = 0
        while i < units.count - 1 {
            if units[i].is("\\"), i < units.count - 2 { i += 1 }
            let u = units[i]
            if u.is("_") {
                underscores += 1
            } else if u.is(".") {
                underscoresBefore = underscores
                underscores = 0
                dots += 1
            } else if u.is("-") {
                // valid
            } else if let s = u.scalar, !markdownIsSpace(s), !markdownIsPunctuation(s) {
                if !s.isASCII {
                    // cmark-gfm reads bytes: a multi-byte character's first byte
                    // is valid and its next one is not, so the domain ends there.
                    i += 1
                    break
                }
            } else {
                break
            }
            i += 1
        }
        if underscoresBefore > 0 || underscores > 0 { return 0 }
        return allowShort || dots > 0 ? i : 0
    }

    /// `autolink_delim`: the link's end with trailing punctuation, unbalanced
    /// closing parentheses and an entity-like `&…;` trimmed.
    func autolinkDelimiter(_ data: [MarkdownUnit], _ end: Int) -> Int {
        var linkEnd = end
        var opening = 0, closing = 0
        for i in 0..<linkEnd {
            if data[i].is("<") {
                linkEnd = i
                break
            } else if data[i].is("(") {
                opening += 1
            } else if data[i].is(")") {
                closing += 1
            }
        }
        while linkEnd > 0 {
            guard let last = data[linkEnd - 1].scalar else { return linkEnd }
            switch last {
            case ")":
                if closing <= opening { return linkEnd }
                closing -= 1
                linkEnd -= 1
            case "?", "!", ".", ",", ":", "*", "_", "~", "'", "\"":
                linkEnd -= 1
            case ";":
                var newEnd = linkEnd - 2
                while newEnd > 0, data[newEnd].isASCIIAlpha { newEnd -= 1 }
                if newEnd >= 0, newEnd < linkEnd - 2, data[newEnd].is("&") {
                    linkEnd = newEnd
                } else {
                    linkEnd -= 1
                }
            default:
                return linkEnd
            }
        }
        return linkEnd
    }

    // MARK: The post-pass: consolidation and e-mail autolinks

    /// `cmark_consolidate_text_nodes`: adjacent text nodes join.
    mutating func consolidateText(_ parent: Int) {
        var node = nodes[parent].first
        while node >= 0 {
            if nodes[node].kind == .text {
                var next = nodes[node].next
                while next >= 0, nodes[next].kind == .text {
                    nodes[node].units += nodes[next].units
                    let after = nodes[next].next
                    unlink(next)
                    next = after
                }
            } else {
                consolidateText(node)
            }
            node = nodes[node].next
        }
    }

    /// The autolink extension's `postprocess`: an e-mail address in text
    /// outside every link becomes a `mailto:` link.
    mutating func linkEmailAddresses(_ parent: Int) {
        var node = nodes[parent].first
        while node >= 0 {
            let next = nodes[node].next
            switch nodes[node].kind {
            case .link: break
            case .text: linkEmailAddresses(inText: node)
            default: linkEmailAddresses(node)
            }
            node = next
        }
    }

    /// `postprocess_text` over one text node, split around each address.
    mutating func linkEmailAddresses(inText textNode: Int) {
        let data = nodes[textNode].units
        var pieces: [(units: [MarkdownUnit], url: String?)] = []
        var cut = 0
        var offset = 0
        while offset < data.count {
            guard let at = data[offset...].firstIndex(where: { $0.is("@") }) else { break }
            let maxRewind = at - offset
            var rewind = 0
            var autoMailto = true
            var isXMPP = false
            while rewind < maxRewind {
                let c = data[at - rewind - 1]
                if c.isASCIIAlphanumeric || c.is(".") || c.is("+") || c.is("-") || c.is("_") {
                    rewind += 1
                    continue
                }
                if c.is(":") {
                    if validProtocol("mailto:", data, at: at, rewind: rewind, maxRewind: maxRewind) {
                        autoMailto = false
                        rewind += 1
                        continue
                    }
                    if validProtocol("xmpp:", data, at: at, rewind: rewind, maxRewind: maxRewind) {
                        autoMailto = false
                        isXMPP = true
                        rewind += 1
                        continue
                    }
                }
                break
            }
            guard rewind > 0 else {
                offset = at + 1
                continue
            }
            let tail = Array(data[at...])
            var linkEnd = 0, ats = 0, dots = 0
            scan: while linkEnd < tail.count {
                let c = tail[linkEnd]
                if c.isASCIIAlphanumeric {
                    // part of the address
                } else if c.is("@") {
                    ats += 1
                } else if c.is("."), linkEnd < tail.count - 1, tail[linkEnd + 1].isASCIIAlphanumeric {
                    dots += 1
                } else if c.is("/"), isXMPP {
                    // an XMPP resource
                } else if !c.is("-"), !c.is("_") {
                    break scan
                }
                linkEnd += 1
            }
            if linkEnd < 2 || ats != 1 || dots == 0 || (!tail[linkEnd - 1].isASCIIAlpha && !tail[linkEnd - 1].is(".")) {
                offset = at + 1
                continue
            }
            linkEnd = autolinkDelimiter(tail, linkEnd)
            guard linkEnd > 0 else {
                offset = at + 1
                continue
            }
            let start = at - rewind
            if start > cut { pieces.append((Array(data[cut..<start]), nil)) }
            let text = Array(data[start..<(at + linkEnd)])
            pieces.append((text, (autoMailto ? "mailto:" : "") + markdownString(text)))
            cut = at + linkEnd
            offset = cut
        }
        guard !pieces.isEmpty else { return }
        if cut < data.count { pieces.append((Array(data[cut...]), nil)) }
        var anchor = textNode
        for piece in pieces {
            let node: Int
            if let url = piece.url {
                node = makeNode(.link(url))
                appendChild(node, makeNode(.text, piece.units))
            } else {
                node = makeNode(.text, piece.units)
            }
            insertAfter(anchor, node)
            anchor = node
        }
        unlink(textNode)
    }

    /// `validate_protocol`: whether `scheme` (its `:` last) ends just before
    /// the rewound run, at the window's start or after a non-alphanumeric.
    func validProtocol(_ scheme: String, _ data: [MarkdownUnit], at: Int, rewind: Int, maxRewind: Int) -> Bool {
        let length = scheme.unicodeScalars.count
        guard length <= maxRewind - rewind else { return false }
        let start = at - rewind - length
        guard markdownHasPrefix(data[start...], scheme) else { return false }
        if length == maxRewind - rewind { return true }
        return !data[start - 1].isASCIIAlphanumeric
    }

    // MARK: Foundation's conversion into runs

    /// The tree as pieces: text and placeholders with their attributes. Inside
    /// a link or an image everything is flattened to plain text carrying only
    /// the attributes outside it (Foundation, `M22`; an image is its alt text,
    /// `M19`).
    func pieces() -> [MarkdownPiece] {
        var out: [MarkdownPiece] = []
        emit(0, MarkdownRun(text: ""), into: &out)
        return out
    }

    func emit(_ parent: Int, _ attributes: MarkdownRun, into out: inout [MarkdownPiece]) {
        var node = nodes[parent].first
        while node >= 0 {
            let n = nodes[node]
            var a = attributes
            switch n.kind {
            case .text, .html:
                emitUnits(n.units, a, into: &out)
            case .code:
                a.code = true
                emitUnits(n.units, a, into: &out)
            case .lineBreak:
                emitUnits([.scalar("\n")], a, into: &out)
            case .emphasis:
                a.italic = true
                emit(node, a, into: &out)
            case .strong:
                a.bold = true
                emit(node, a, into: &out)
            case .strikethrough:
                a.strikethrough = true
                emit(node, a, into: &out)
            case .link(let url):
                a.link = foundationURLString(url)
                emitUnits(flattened(node), a, into: &out)
            case .image:
                emitUnits(flattened(node), a, into: &out)
            case .root:
                break
            }
            node = n.next
        }
    }

    /// A node's descendants as plain units.
    func flattened(_ parent: Int) -> [MarkdownUnit] {
        var out: [MarkdownUnit] = []
        var node = nodes[parent].first
        while node >= 0 {
            switch nodes[node].kind {
            case .text, .html, .code: out += nodes[node].units
            case .lineBreak: out.append(.scalar("\n"))
            default: out += flattened(node)
            }
            node = nodes[node].next
        }
        return out
    }

    func emitUnits(_ units: [MarkdownUnit], _ attributes: MarkdownRun, into out: inout [MarkdownPiece]) {
        var text = ""
        for u in units {
            switch u {
            case .scalar(let s):
                text.unicodeScalars.append(s)
            case .placeholder(let index):
                if !text.isEmpty { out.append(MarkdownPiece(content: .text(text), attributes: attributes)) }
                text = ""
                out.append(MarkdownPiece(content: .placeholder(index), attributes: attributes))
            }
        }
        if !text.isEmpty { out.append(MarkdownPiece(content: .text(text), attributes: attributes)) }
    }
}

/// A link destination as Foundation's `URL(string:)` keeps it (its
/// `absoluteString`): a character a URL cannot hold is percent-encoded as
/// UTF-8 — a `%` that starts no escape, a second `#`, brackets outside an
/// authority and every `@` in it but the last included; `nil` for an empty
/// destination or a port that is not digits, where `URL(string:)` fails and
/// Foundation sets no link (`[a]()`).
func foundationURLString(_ destination: String) -> String? {
    guard !destination.isEmpty else { return nil }
    let scalars = Array(destination.unicodeScalars)
    let allowed = Set("-._~:/?#[]@!$&'()*+,;=".unicodeScalars)
    let hexDigits = Array("0123456789ABCDEF".unicodeScalars)
    func isHex(_ s: Unicode.Scalar) -> Bool {
        (s >= "0" && s <= "9") || (s >= "a" && s <= "f") || (s >= "A" && s <= "F")
    }
    // The authority: after the first "://", up to the next "/", "?" or "#".
    var authority = 0..<0
    if let colon = scalars.indices.first(where: { i in
        scalars[i] == ":" && i + 2 < scalars.count && scalars[i + 1] == "/" && scalars[i + 2] == "/"
    }) {
        let start = colon + 3
        let end = scalars[start...].firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? scalars.count
        authority = start..<end
        // The port, after the host's first ":", must be digits — else
        // `URL(string:)` fails and Foundation sets no link.
        let host = (scalars[authority].lastIndex(of: "@").map { $0 + 1 } ?? start)..<end
        if !scalars[host].contains("["), let portColon = scalars[host].firstIndex(of: ":"),
           !scalars[(portColon + 1)..<end].allSatisfy({ $0 >= "0" && $0 <= "9" }) {
            return nil
        }
    }
    let lastAt = scalars[authority].lastIndex(of: "@")
    var out = ""
    var sawFragment = false
    for (i, s) in scalars.enumerated() {
        let alphanumeric = (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || (s >= "0" && s <= "9")
        var keep = alphanumeric || allowed.contains(s)
            || (s == "%" && i + 2 < scalars.count && isHex(scalars[i + 1]) && isHex(scalars[i + 2]))
        if s == "#" {
            keep = !sawFragment
            sawFragment = true
        }
        if s == "[" || s == "]" { keep = authority.contains(i) }
        if s == "@", authority.contains(i) { keep = i == lastAt }
        if keep {
            out.unicodeScalars.append(s)
        } else {
            for byte in String(s).utf8 {
                out.unicodeScalars.append("%")
                out.unicodeScalars.append(hexDigits[Int(byte >> 4)])
                out.unicodeScalars.append(hexDigits[Int(byte & 0xF)])
            }
        }
    }
    return out
}

/// The named character references MetalUI decodes (ruling RT-B item 4,
/// divergence 153): the five XML entities and 29 common HTML ones — 34. Any
/// other name stays literal.
let markdownNamedEntities: [String: Unicode.Scalar] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
    "nbsp": "\u{A0}", "copy": "\u{A9}", "reg": "\u{AE}", "trade": "\u{2122}", "hellip": "\u{2026}",
    "mdash": "\u{2014}", "ndash": "\u{2013}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}",
    "rdquo": "\u{201D}", "bull": "\u{2022}", "middot": "\u{B7}", "deg": "\u{B0}", "plusmn": "\u{B1}",
    "times": "\u{D7}", "divide": "\u{F7}", "euro": "\u{20AC}", "pound": "\u{A3}", "yen": "\u{A5}",
    "cent": "\u{A2}", "sect": "\u{A7}", "para": "\u{B6}", "laquo": "\u{AB}", "raquo": "\u{BB}",
    "larr": "\u{2190}", "rarr": "\u{2192}", "uarr": "\u{2191}", "darr": "\u{2193}",
]
