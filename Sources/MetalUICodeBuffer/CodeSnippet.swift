/// A snippet: the text to insert and the tab stops inside it (`CV-BP`).
///
/// A snippet is a pure value. `init(parsing:)` reads the LSP / TextMate snippet syntax, so a language
/// server's `insertText` (with `insertTextFormat` 2) becomes one; `init(text:tabStops:)` builds one directly.
/// Offsets are UTF-8 bytes into `text`, the unit every other range in this module uses. The session that
/// walks the stops is a later ruling (`CV-BQ`); this type only holds and reads them.
///
/// **Syntax read by `init(parsing:)`** (VS Code's `SnippetParser` is the reference):
/// - `$n`, `${n}` and `${n:default}` are tab stops; the default may hold text and nested stops
///   (`${1:a ${2:b}}`). `n` is a decimal number; `$0` is the final stop.
/// - `\$`, `\}` and `\\` are the characters `$`, `}` and `\`. A backslash before anything else stays a
///   backslash.
/// - `${n|a,b,c|}` is a choice: a stop whose text is its first option (`\,`, `\|` and `\\` escape inside it).
/// - A variable (`$NAME`, `${NAME}`, `${NAME:default}`) is **plain text, never a stop**: its default when it
///   has one (nested stops in the default stay stops), otherwise nothing. MetalUI resolves no variables, so
///   every variable is unknown, and this is the empty-or-default rule of an unknown variable.
/// - A transform (`${n/regex/format/options}`, on a stop or a variable) is parsed and dropped: a stop with a
///   transform is a plain mirror of its index, a variable with one is empty.
/// - Defaults nest 64 deep; a deeper `${n:` is literal text.
/// - Anything malformed is kept as literal text (`${`, `${1:`, an unclosed default, a lone `$`, a trailing
///   `\`, `${1|a,b}`): parsing never fails.
/// - A template with no `$0` gets one at the end of the text.
/// - Stops with the same index are mirrors. The first occurrence (in text order, outer before inner) with a
///   non-empty default gives that text to every other stop of its index, wherever they stand; a mirror
///   copies the text only, not any stop nested in it.
public struct CodeSnippet: Hashable, Sendable {
    /// One tab stop: an index and the range it covers in `text`.
    public struct TabStop: Hashable, Sendable {
        /// The stop's number. Stops with the same index are linked mirrors; index 0 is the final stop.
        public var index: Int
        /// The bytes the stop covers, as UTF-8 offsets into ``CodeSnippet/text``; empty for a bare `$n`.
        public var range: Range<Int>

        /// A stop numbered `index` covering `range`.
        public init(index: Int, range: Range<Int>) {
            self.index = index
            self.range = range
        }
    }

    /// The text to insert, with every escape, default and choice already resolved.
    public var text: String
    /// The tab stops, ordered by start (an enclosing stop before the ones inside it). Ranges are nested or
    /// disjoint. Index 0 is the final stop; `init(parsing:)` always produces one.
    public var tabStops: [TabStop]

    /// A snippet of `text` with these stops.
    ///
    /// - Precondition: every range lies within `text`'s UTF-8 bytes on scalar boundaries, every index is
    ///   non-negative, and any two ranges are nested or disjoint (never partly overlapping).
    public init(text: String, tabStops: [TabStop]) {
        precondition(Self.isValid(text: text, tabStops: tabStops),
                     "CodeSnippet: tab stop ranges must lie in the text and be nested or disjoint")
        self.text = text
        self.tabStops = tabStops
    }

    /// The snippet a template in the LSP / TextMate syntax describes. Never fails: malformed syntax stays
    /// literal text. See the type's documentation for the rules.
    public init(parsing template: String) {
        var parser = SnippetParser(Array(template.utf8))
        let (bytes, stops) = parser.run()
        text = String(decoding: bytes, as: UTF8.self)
        tabStops = stops
    }

    /// Whether `text` and `tabStops` satisfy `init(text:tabStops:)`'s precondition. The non-trapping form,
    /// so tests can reach every branch.
    static func isValid(text: String, tabStops: [TabStop]) -> Bool {
        let utf8 = text.utf8
        let count = utf8.count
        func isBoundary(_ offset: Int) -> Bool {
            if offset == count { return true }
            return utf8[utf8.index(utf8.startIndex, offsetBy: offset)] & 0xC0 != 0x80
        }
        for s in tabStops {
            guard s.index >= 0, s.range.lowerBound >= 0, s.range.upperBound <= count,
                  isBoundary(s.range.lowerBound), isBoundary(s.range.upperBound) else { return false }
        }
        // Sorted by start, longer first: each range must then lie inside the innermost open range or start
        // at or after its end.
        let sorted = tabStops.map(\.range).sorted {
            $0.lowerBound != $1.lowerBound ? $0.lowerBound < $1.lowerBound : $0.upperBound > $1.upperBound
        }
        var open: [Range<Int>] = []
        for r in sorted {
            while let top = open.last, top.upperBound <= r.lowerBound {
                open.removeLast()
            }
            if let top = open.last, r.upperBound > top.upperBound { return false }
            open.append(r)
        }
        return true
    }
}

/// The template reader behind `CodeSnippet.init(parsing:)`: a recursive descent over the UTF-8 bytes (every
/// delimiter is ASCII, so no scalar is ever split) into a tree, then a render that resolves mirrors.
struct SnippetParser {
    indirect enum Node {
        case text([UInt8])
        case stop(id: Int, index: Int, children: [Node])
    }

    let b: [UInt8]
    var i = 0
    var nextID = 0
    /// How many defaults deep the cursor is. Past `maxDepth` a `${n:` is literal text, so hostile input
    /// cannot exhaust the stack.
    var depth = 0
    static let maxDepth = 64
    /// Results of `$` attempts by start position. A failed attempt restores the cursor and re-reads the
    /// remainder as text, which would retry the same inner attempts (exponential on `${1:${1:${1:`).
    var memo: [Int: (nodes: [Node]?, end: Int)] = [:]

    init(_ bytes: [UInt8]) { b = bytes }

    mutating func run() -> ([UInt8], [CodeSnippet.TabStop]) {
        let tree = sequence(nested: false)
        var sources: [Int: (id: Int, children: [Node])] = [:]
        collectSources(tree, &sources)
        var out: [UInt8] = []
        var stops: [CodeSnippet.TabStop] = []
        render(tree, sources, &out, &stops)
        if !stops.contains(where: { $0.index == 0 }) {
            stops.append(.init(index: 0, range: out.count..<out.count))
        }
        return (out, stops)
    }

    // MARK: Parse

    static func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
    static func isNameStart(_ c: UInt8) -> Bool { c == 0x5F || (c | 0x20 >= 0x61 && c | 0x20 <= 0x7A) }
    static func isNameChar(_ c: UInt8) -> Bool { isNameStart(c) || isDigit(c) }

    /// Reads text and constructs up to the end of input, or (nested) up to an unescaped `}`, which it leaves.
    mutating func sequence(nested: Bool) -> [Node] {
        var nodes: [Node] = []
        var run: [UInt8] = []
        func flush() { if !run.isEmpty { nodes.append(.text(run)); run = [] } }
        while i < b.count {
            let c = b[i]
            if nested && c == 0x7D { break }
            if c == 0x5C {  // backslash
                if i + 1 < b.count, [0x24, 0x7D, 0x5C].contains(b[i + 1]) { run.append(b[i + 1]); i += 2 } else { run.append(c); i += 1 }
            } else if c == 0x24 {  // dollar
                let start = i
                if let (n, end) = attempt(at: start) {
                    flush(); nodes += n; i = end
                } else {
                    run.append(c); i = start + 1
                }
            } else {
                run.append(c); i += 1
            }
        }
        flush()
        return nodes
    }

    mutating func attempt(at p: Int) -> ([Node], Int)? {
        if let cached = memo[p] { return cached.nodes.map { ($0, cached.end) } }
        i = p
        let r = dollar()
        memo[p] = (nodes: r, end: i)
        return r.map { ($0, i) }
    }

    mutating func number(_ at: inout Int) -> Int? {
        var j = at
        var v = 0
        while j < b.count, Self.isDigit(b[j]) {
            let (m, o1) = v.multipliedReportingOverflow(by: 10)
            let (s, o2) = m.addingReportingOverflow(Int(b[j] - 0x30))
            if o1 || o2 { return nil }
            v = s; j += 1
        }
        if j == at { return nil }
        at = j
        return v
    }

    mutating func stop(_ index: Int, _ children: [Node]) -> [Node] {
        nextID += 1
        return [.stop(id: nextID, index: index, children: children)]
    }

    /// At a `$`. Leaves `i` after the construct on success.
    mutating func dollar() -> [Node]? {
        var j = i + 1
        guard j < b.count else { return nil }
        let c = b[j]
        if Self.isDigit(c) {
            guard let n = number(&j) else { return nil }
            i = j
            return stop(n, [])
        }
        if Self.isNameStart(c) {
            while j < b.count, Self.isNameChar(b[j]) { j += 1 }
            i = j
            return []
        }
        guard c == 0x7B else { return nil }
        j += 1
        guard j < b.count else { return nil }
        if Self.isDigit(b[j]) {
            guard let n = number(&j), j < b.count else { return nil }
            switch b[j] {
            case 0x7D: i = j + 1; return stop(n, [])
            case 0x3A:
                i = j + 1
                guard let kids = closedSequence() else { return nil }
                return stop(n, kids)
            case 0x7C:
                guard let first = choice(from: j + 1) else { return nil }
                return stop(n, first.isEmpty ? [] : [.text(first)])
            case 0x2F:
                guard transform(from: j + 1) else { return nil }
                return stop(n, [])
            default: return nil
            }
        }
        if Self.isNameStart(b[j]) {
            while j < b.count, Self.isNameChar(b[j]) { j += 1 }
            guard j < b.count else { return nil }
            switch b[j] {
            case 0x7D: i = j + 1; return []
            case 0x3A:
                i = j + 1
                return closedSequence()
            case 0x2F:
                return transform(from: j + 1) ? [] : nil
            default: return nil
            }
        }
        return nil
    }

    /// A nested sequence that must end at `}`, which it consumes.
    mutating func closedSequence() -> [Node]? {
        guard depth < Self.maxDepth else { return nil }
        depth += 1
        let kids = sequence(nested: true)
        depth -= 1
        guard i < b.count, b[i] == 0x7D else { return nil }
        i += 1
        return kids
    }

    /// After `|`: options up to an unescaped `|}`; returns the first option and moves `i` past `}`.
    mutating func choice(from start: Int) -> [UInt8]? {
        var j = start
        var first: [UInt8] = []
        var inFirst = true
        while j < b.count {
            let c = b[j]
            if c == 0x5C, j + 1 < b.count, [0x2C, 0x7C, 0x5C].contains(b[j + 1]) {
                if inFirst { first.append(b[j + 1]) }
                j += 2
            } else if c == 0x7C, j + 1 < b.count, b[j + 1] == 0x7D {
                i = j + 2
                return first
            } else if c == 0x2C {
                inFirst = false; j += 1
            } else {
                if inFirst { first.append(c) }
                j += 1
            }
        }
        return nil
    }

    /// After the first `/` of `${x/regex/format/options}`: skips regex, format and options up to `}`.
    mutating func transform(from start: Int) -> Bool {
        var j = start
        for _ in 0..<2 {  // regex, then format, each ended by an unescaped `/`
            while j < b.count, b[j] != 0x2F { j += b[j] == 0x5C ? 2 : 1 }
            guard j < b.count else { return false }
            j += 1
        }
        while j < b.count, (b[j] | 0x20) >= 0x61, (b[j] | 0x20) <= 0x7A { j += 1 }
        guard j < b.count, b[j] == 0x7D else { return false }
        i = j + 1
        return true
    }

    // MARK: Mirrors and render

    /// Per index, the first stop in text order (outer before inner) whose default is non-empty.
    func collectSources(_ nodes: [Node], _ sources: inout [Int: (id: Int, children: [Node])]) {
        for node in nodes {
            guard case let .stop(id, index, kids) = node else { continue }
            if sources[index] == nil, !flat(kids, sources, [index]).isEmpty { sources[index] = (id, kids) }
            collectSources(kids, &sources)
        }
    }

    /// The text of `nodes` with every stop reduced to text: a stop of an index not being expanded takes its
    /// index's source text. `expanding` stops a stop from containing itself.
    func flat(_ nodes: [Node], _ sources: [Int: (id: Int, children: [Node])], _ expanding: Set<Int>) -> [UInt8] {
        var out: [UInt8] = []
        for node in nodes {
            switch node {
            case let .text(t): out += t
            case let .stop(_, index, kids):
                if !expanding.contains(index), let s = sources[index] {
                    out += flat(s.children, sources, expanding.union([index]))
                } else {
                    out += flat(kids, sources, expanding)
                }
            }
        }
        return out
    }

    func render(_ nodes: [Node], _ sources: [Int: (id: Int, children: [Node])], _ out: inout [UInt8], _ stops: inout [CodeSnippet.TabStop]) {
        for node in nodes {
            switch node {
            case let .text(t): out += t
            case let .stop(id, index, kids):
                let slot = stops.count
                let start = out.count
                stops.append(.init(index: index, range: start..<start))
                if let s = sources[index], s.id != id {
                    out += flat(s.children, sources, [index])
                } else {
                    render(kids, sources, &out, &stops)
                }
                stops[slot].range = start..<out.count
            }
        }
    }
}
