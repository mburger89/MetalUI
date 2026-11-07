// Block structure over UTF-8 bytes (rulings BM-A, BM-B): a port of cmark-gfm's
// line-by-line container matching (open containers, then new block starts, then
// the text of the line) onto an index-linked arena, so a parse allocates one
// array of nodes instead of one object per block.

struct BlockNode {
    enum Kind: UInt8 { case document, blockQuote, list, item, paragraph, heading, code, thematicBreak, table }
    var kind: Kind
    var parent: Int
    var firstChild = -1
    var lastChild = -1
    var next = -1
    var isOpen = true
    var lastLineBlank = false
    var startLine: Int
    /// Absolute offset of the first byte of the line that opened this block.
    var startOffset: Int
    // list and item
    var ordered = false
    var marker: UInt8 = 0
    var start = 1
    var tight = true
    var markerOffset = 0
    var padding = 0
    // heading
    var level = 0
    var setext = false
    // code
    var fenced = false
    var fenceChar: UInt8 = 0
    var fenceLength = 0
    var fenceOffset = 0
    var closed = false
    var info: [UInt8] = []
    // paragraph, code and heading text (every line ends in "\n")
    var content: [UInt8] = []
    /// Paragraph: the absolute start offset of each content line (a table header may be the last of them).
    var lineStarts: [Int] = []
    // table
    var tableIndex = -1
    /// Paragraph: a delimiter row has already failed to match this paragraph's last line (`tryOpenTable`).
    var tableRefused = false
}

struct TableData {
    var alignments: [MarkdownTableAlignment]
    var header: [[UInt8]]
    var rows: [[[UInt8]]] = []
}

struct ParsedBlock {
    var kind: MarkdownBlock.Kind
    /// Offset of the first byte of the line the top-level block starts on.
    var start: Int
}

struct BlockParser {
    let b: [UInt8]
    var nodes: [BlockNode] = []
    var tables: [TableData] = []
    var current = 0

    var lineNumber = 0
    var lineStart = 0
    var lineEnd = 0
    var offset = 0
    var column = 0
    var firstNonspace = 0
    var firstNonspaceColumn = 0
    var indent = 0
    var blank = false
    var partiallyConsumedTab = false

    init(bytes: [UInt8]) {
        b = bytes
        nodes.append(BlockNode(kind: .document, parent: -1, startLine: 0, startOffset: 0))
    }

    // MARK: Entry

    /// The top-level blocks of `bytes` with their ids unassigned and the offset each starts at.
    static func parse(_ bytes: [UInt8]) -> [ParsedBlock] {
        MarkdownParseStats.bytesScanned += bytes.count
        var parser = BlockParser(bytes: bytes)
        parser.run()
        return parser.topLevel()
    }

    mutating func run() {
        var i = 0
        let n = b.count
        while i < n {
            var j = i
            while j < n, b[j] != 10, b[j] != 13 { j += 1 }
            processLine(start: i, end: j)
            if j < n, b[j] == 13, j + 1 < n, b[j + 1] == 10 { i = j + 2 } else { i = j + 1 }
        }
        while current >= 0 { current = finalize(current) }
    }

    // MARK: Line state

    @inline(__always) func peek(_ i: Int) -> UInt8 { i >= lineStart && i < lineEnd ? b[i] : 0 }

    @inline(__always) func isSpaceOrTab(_ c: UInt8) -> Bool { c == 32 || c == 9 }

    mutating func findFirstNonspace() {
        var charsToTab = 4 - (column % 4)
        if firstNonspace <= offset {
            firstNonspace = offset
            firstNonspaceColumn = column
            while firstNonspace < lineEnd {
                let c = b[firstNonspace]
                if c == 32 {
                    firstNonspace += 1
                    firstNonspaceColumn += 1
                    charsToTab -= 1
                    if charsToTab == 0 { charsToTab = 4 }
                } else if c == 9 {
                    firstNonspace += 1
                    firstNonspaceColumn += charsToTab
                    charsToTab = 4
                } else {
                    break
                }
            }
        }
        indent = firstNonspaceColumn - column
        blank = firstNonspace >= lineEnd
    }

    mutating func advance(_ count: Int, columns: Bool) {
        var count = count
        while count > 0, offset < lineEnd {
            if b[offset] == 9 {
                let charsToTab = 4 - (column % 4)
                if columns {
                    partiallyConsumedTab = charsToTab > count
                    let step = charsToTab > count ? count : charsToTab
                    column += step
                    offset += partiallyConsumedTab ? 0 : 1
                    count -= step
                } else {
                    partiallyConsumedTab = false
                    column += charsToTab
                    offset += 1
                    count -= 1
                }
            } else {
                partiallyConsumedTab = false
                offset += 1
                column += 1
                count -= 1
            }
        }
    }

    mutating func addLine(_ n: Int) {
        if partiallyConsumedTab {
            offset += 1
            let charsToTab = 4 - (column % 4)
            nodes[n].content.append(contentsOf: repeatElement(UInt8(32), count: charsToTab))
        }
        if offset < lineEnd { nodes[n].content.append(contentsOf: b[offset..<lineEnd]) }
        nodes[n].content.append(10)
    }

    // MARK: The line

    mutating func processLine(start: Int, end: Int) {
        lineNumber += 1
        lineStart = start
        lineEnd = end
        offset = start
        column = 0
        firstNonspace = start
        firstNonspaceColumn = 0
        indent = 0
        blank = false
        partiallyConsumedTab = false

        var allMatched = false
        guard let lastMatched = checkOpenBlocks(&allMatched) else { return }
        var container = lastMatched
        openNewBlocks(&container, allMatched: allMatched)
        addTextToContainer(container, lastMatched: lastMatched)
    }

    /// Walks the open blocks while the line continues them. Returns the last block that matched, or nil when
    /// the line was a closing fence and is fully consumed.
    mutating func checkOpenBlocks(_ allMatched: inout Bool) -> Int? {
        allMatched = false
        var container = 0
        while nodes[container].lastChild >= 0, nodes[nodes[container].lastChild].isOpen {
            container = nodes[container].lastChild
            findFirstNonspace()
            var matches = true
            switch nodes[container].kind {
            case .code:
                if nodes[container].fenced {
                    var matched = 0
                    if indent <= 3, peek(firstNonspace) == nodes[container].fenceChar {
                        matched = scanCloseFence(firstNonspace)
                    }
                    if matched >= nodes[container].fenceLength {
                        nodes[container].closed = true
                        current = finalize(container)
                        return nil
                    }
                    var i = nodes[container].fenceOffset
                    while i > 0, isSpaceOrTab(peek(offset)) {
                        advance(1, columns: true)
                        i -= 1
                    }
                } else if indent >= 4 {
                    advance(4, columns: true)
                } else if blank {
                    advance(firstNonspace - offset, columns: false)
                } else {
                    matches = false
                }
            case .blockQuote:
                if indent <= 3, peek(firstNonspace) == 62 {
                    advance(firstNonspace + 1 - offset, columns: false)
                    if isSpaceOrTab(peek(offset)) { advance(1, columns: true) }
                } else {
                    matches = false
                }
            case .item:
                if indent >= nodes[container].markerOffset + nodes[container].padding {
                    advance(nodes[container].markerOffset + nodes[container].padding, columns: true)
                } else if blank, nodes[container].firstChild >= 0 {
                    advance(firstNonspace - offset, columns: false)
                } else {
                    matches = false
                }
            case .heading, .thematicBreak:
                matches = false
            case .paragraph:
                if blank { matches = false }
            case .table:
                if rowCells(from: firstNonspace).isEmpty { matches = false }
            case .list, .document:
                break
            }
            if !matches {
                return nodes[container].parent
            }
        }
        allMatched = true
        return container
    }

    mutating func openNewBlocks(_ container: inout Int, allMatched: Bool) {
        var maybeLazy = nodes[current].kind == .paragraph
        var contKind = nodes[container].kind
        while contKind != .code {
            findFirstNonspace()
            let indented = indent >= 4
            var matched = 0
            if !indented, peek(firstNonspace) == 62 {
                let quoteStart = firstNonspace
                advance(firstNonspace + 1 - offset, columns: false)
                if isSpaceOrTab(peek(offset)) { advance(1, columns: true) }
                container = addChild(container, .blockQuote)
                _ = quoteStart
            } else if !indented, case let m = scanAtxStart(firstNonspace), m > 0 {
                var level = 0
                var p = firstNonspace
                while peek(p) == 35 { level += 1; p += 1 }
                advance(firstNonspace + m - offset, columns: false)
                container = addChild(container, .heading)
                nodes[container].level = level
            } else if !indented, case let m = scanOpenFence(firstNonspace), m > 0 {
                let fenceStart = firstNonspace
                container = addChild(container, .code)
                nodes[container].fenced = true
                nodes[container].fenceChar = peek(fenceStart)
                nodes[container].fenceLength = m
                nodes[container].fenceOffset = firstNonspace - offset
                advance(firstNonspace + m - offset, columns: false)
                var s = offset
                var e = lineEnd
                while s < e, isSpaceOrTab(b[s]) { s += 1 }
                while e > s, isSpaceOrTab(b[e - 1]) { e -= 1 }
                nodes[container].info = Array(b[s..<e])
            } else if !indented, contKind == .paragraph, case let lev = scanSetext(firstNonspace), lev > 0 {
                nodes[container].kind = .heading
                nodes[container].level = lev
                nodes[container].setext = true
                advance(lineEnd - offset, columns: false)
            } else if !indented, !(contKind == .paragraph && !allMatched), scanThematicBreak(firstNonspace) {
                container = addChild(container, .thematicBreak)
                advance(lineEnd - offset, columns: false)
            } else if !indented || contKind == .list, indent < 4,
                      let marker = parseListMarker(firstNonspace, interruptsParagraph: nodes[container].kind == .paragraph) {
                matched = marker.length
                advance(firstNonspace + matched - offset, columns: false)
                let savedTab = partiallyConsumedTab
                let savedOffset = offset
                let savedColumn = column
                while column - savedColumn <= 5, isSpaceOrTab(peek(offset)) { advance(1, columns: true) }
                let i = column - savedColumn
                var padding = 0
                if i >= 5 || i < 1 || offset >= lineEnd {
                    padding = matched + 1
                    offset = savedOffset
                    column = savedColumn
                    partiallyConsumedTab = savedTab
                    if i > 0 { advance(1, columns: true) }
                } else {
                    padding = matched + i
                }
                let markerOffset = indent
                if nodes[container].kind != .list
                    || nodes[container].ordered != marker.ordered || nodes[container].marker != marker.marker {
                    container = addChild(container, .list)
                    nodes[container].ordered = marker.ordered
                    nodes[container].marker = marker.marker
                    nodes[container].start = marker.start
                }
                container = addChild(container, .item)
                nodes[container].markerOffset = markerOffset
                nodes[container].padding = padding
            } else if indented, !maybeLazy, !blank {
                advance(4, columns: true)
                container = addChild(container, .code)
                nodes[container].fenced = false
            } else if !indented, nodes[container].kind == .paragraph, let table = tryOpenTable(container) {
                container = table
            } else if !indented, nodes[container].kind == .table, tryAddTableRow(container) {
                // the row is consumed; the table stays the container
            } else {
                break
            }
            let kind = nodes[container].kind
            if kind == .paragraph || kind == .heading || kind == .code { break }
            contKind = kind
            maybeLazy = false
        }
    }

    mutating func addTextToContainer(_ containerIn: Int, lastMatched: Int) {
        var container = containerIn
        findFirstNonspace()
        if blank, nodes[container].lastChild >= 0 { nodes[nodes[container].lastChild].lastLineBlank = true }

        let kind = nodes[container].kind
        let lastLineBlank = blank && kind != .blockQuote && kind != .heading && kind != .thematicBreak
            && kind != .table && !(kind == .code && nodes[container].fenced)
            && !(kind == .item && nodes[container].firstChild < 0 && nodes[container].startLine == lineNumber)
        nodes[container].lastLineBlank = lastLineBlank
        var t = nodes[container].parent
        while t >= 0 {
            nodes[t].lastLineBlank = false
            t = nodes[t].parent
        }

        if current != lastMatched, container == lastMatched, !blank, nodes[current].kind == .paragraph {
            // a lazy continuation line
            advance(firstNonspace - offset, columns: false)
            nodes[current].lineStarts.append(lineStart)
            addLine(current)
        } else {
            while current != lastMatched { current = finalize(current) }
            switch nodes[container].kind {
            case .code:
                if nodes[container].fenced, nodes[container].startLine == lineNumber {
                    break  // the opening line: its remainder is the info string
                }
                addLine(container)
            case _ where blank:
                break
            case .paragraph:
                advance(firstNonspace - offset, columns: false)
                nodes[container].lineStarts.append(lineStart)
                addLine(container)
            case .heading:
                advance(firstNonspace - offset, columns: false)
                if nodes[container].setext {
                    addLine(container)
                } else {
                    var e = lineEnd
                    while e > offset, isSpaceOrTab(b[e - 1]) { e -= 1 }
                    var n = e - 1
                    while n >= offset, b[n] == 35 { n -= 1 }
                    if n != e - 1, n < offset || isSpaceOrTab(b[n]) {
                        e = max(n + 1, offset)
                        while e > offset, isSpaceOrTab(b[e - 1]) { e -= 1 }
                    }
                    if e > offset { nodes[container].content.append(contentsOf: b[offset..<e]) }
                    nodes[container].content.append(10)
                }
            default:
                container = addChild(container, .paragraph)
                advance(firstNonspace - offset, columns: false)
                nodes[container].lineStarts.append(lineStart)
                addLine(container)
            }
            current = container
        }
    }

    // MARK: Tree

    func canContain(_ parent: Int, _ child: BlockNode.Kind) -> Bool {
        switch nodes[parent].kind {
        case .document, .blockQuote, .item: return child != .item
        case .list: return child == .item
        default: return false
        }
    }

    mutating func addChild(_ parentIn: Int, _ kind: BlockNode.Kind) -> Int {
        var parent = parentIn
        while !canContain(parent, kind) { parent = finalize(parent) }
        let index = nodes.count
        var node = BlockNode(kind: kind, parent: parent, startLine: lineNumber, startOffset: lineStart)
        if nodes[parent].lastChild >= 0 { nodes[nodes[parent].lastChild].next = index } else { nodes[parent].firstChild = index }
        nodes[parent].lastChild = index
        node.isOpen = true
        nodes.append(node)
        return index
    }

    mutating func finalize(_ n: Int) -> Int {
        nodes[n].isOpen = false
        switch nodes[n].kind {
        case .code where !nodes[n].fenced:
            // drop trailing blank lines
            var content = nodes[n].content
            while content.count >= 1 {
                var e = content.count - 1  // index of the final newline
                var s = e
                while s > 0, content[s - 1] != 10 { s -= 1 }
                var allBlank = true
                var k = s
                while k < e { if !isSpaceOrTab(content[k]) { allBlank = false; break }; k += 1 }
                if allBlank { content.removeSubrange(s...e); e = s } else { break }
            }
            nodes[n].content = content
        case .list:
            var tight = true
            var item = nodes[n].firstChild
            outer: while item >= 0 {
                if nodes[item].lastLineBlank, nodes[item].next >= 0 { tight = false; break }
                var sub = nodes[item].firstChild
                while sub >= 0 {
                    if (nodes[item].next >= 0 || nodes[sub].next >= 0), endsWithBlankLine(sub) { tight = false; break outer }
                    sub = nodes[sub].next
                }
                item = nodes[item].next
            }
            nodes[n].tight = tight
        default:
            break
        }
        return nodes[n].parent
    }

    func endsWithBlankLine(_ node: Int) -> Bool {
        var cur = node
        while cur >= 0 {
            if nodes[cur].lastLineBlank { return true }
            if nodes[cur].kind == .list || nodes[cur].kind == .item { cur = nodes[cur].lastChild } else { cur = -1 }
        }
        return false
    }

    // MARK: Scanners

    func scanAtxStart(_ pos: Int) -> Int {
        var p = pos
        var n = 0
        while peek(p) == 35, n < 7 { p += 1; n += 1 }
        if n < 1 || n > 6 { return 0 }
        if p >= lineEnd { return n }
        guard isSpaceOrTab(peek(p)) else { return 0 }
        while isSpaceOrTab(peek(p)) { p += 1 }
        return p - pos
    }

    func scanOpenFence(_ pos: Int) -> Int {
        let c = peek(pos)
        guard c == 96 || c == 126 else { return 0 }
        var p = pos
        while peek(p) == c { p += 1 }
        let n = p - pos
        if n < 3 { return 0 }
        if c == 96 {
            var q = p
            while q < lineEnd { if b[q] == 96 { return 0 }; q += 1 }
        }
        return n
    }

    func scanCloseFence(_ pos: Int) -> Int {
        let c = peek(pos)
        var p = pos
        while peek(p) == c { p += 1 }
        let n = p - pos
        if n < 3 { return 0 }
        while p < lineEnd { if !isSpaceOrTab(b[p]) { return 0 }; p += 1 }
        return n
    }

    func scanSetext(_ pos: Int) -> Int {
        let c = peek(pos)
        guard c == 61 || c == 45 else { return 0 }
        var p = pos
        while peek(p) == c { p += 1 }
        while p < lineEnd { if !isSpaceOrTab(b[p]) { return 0 }; p += 1 }
        return c == 61 ? 1 : 2
    }

    func scanThematicBreak(_ pos: Int) -> Bool {
        let c = peek(pos)
        guard c == 42 || c == 45 || c == 95 else { return false }
        var count = 0
        var p = pos
        while p < lineEnd {
            let ch = b[p]
            if ch == c { count += 1 } else if !isSpaceOrTab(ch) { return false }
            p += 1
        }
        return count >= 3
    }

    struct ListMarker { var length: Int; var ordered: Bool; var marker: UInt8; var start: Int }

    func parseListMarker(_ pos: Int, interruptsParagraph: Bool) -> ListMarker? {
        var p = pos
        let c = peek(p)
        func isSpace(_ x: UInt8) -> Bool { x == 0 || x == 32 || x == 9 }
        func restBlank(_ from: Int) -> Bool {
            var i = from
            while isSpaceOrTab(peek(i)) { i += 1 }
            return i >= lineEnd
        }
        if c == 42 || c == 45 || c == 43 {
            p += 1
            guard isSpace(peek(p)) else { return nil }
            if interruptsParagraph, restBlank(p) { return nil }
            return ListMarker(length: p - pos, ordered: false, marker: c, start: 1)
        } else if c >= 48 && c <= 57 {
            var start = 0
            var digits = 0
            repeat {
                start = 10 * start + Int(peek(p) - 48)
                p += 1
                digits += 1
            } while digits < 9 && peek(p) >= 48 && peek(p) <= 57
            let d = peek(p)
            guard d == 46 || d == 41 else { return nil }
            p += 1
            guard isSpace(peek(p)) else { return nil }
            if interruptsParagraph {
                if start != 1 { return nil }
                if restBlank(p) { return nil }
            }
            return ListMarker(length: p - pos, ordered: true, marker: d, start: start)
        }
        return nil
    }

    // MARK: Tables (GFM)

    /// The cells of a table row on `lineEnd`'s line from `from`: an optional leading pipe, cells split at
    /// unescaped pipes (`\|` is a literal pipe), an optional trailing pipe, each cell trimmed.
    func rowCells(from: Int) -> [[UInt8]] {
        Self.splitRow(b, from, lineEnd)
    }

    static func splitRow(_ b: [UInt8], _ from: Int, _ to: Int) -> [[UInt8]] {
        var s = from
        var e = to
        while s < e, b[s] == 32 || b[s] == 9 { s += 1 }
        while e > s, b[e - 1] == 32 || b[e - 1] == 9 { e -= 1 }
        if s >= e { return [] }
        var i = s
        if b[i] == 124 { i += 1 }
        var cells: [[UInt8]] = []
        while i < e {
            var cell: [UInt8] = []
            while i < e, b[i] != 124 {
                if b[i] == 92, i + 1 < e, b[i + 1] == 124 {
                    cell.append(124)
                    i += 2
                } else {
                    cell.append(b[i])
                    i += 1
                }
            }
            cells.append(trimmed(cell))
            if i < e { i += 1 }  // the pipe
        }
        return cells
    }

    static func trimmed(_ x: [UInt8]) -> [UInt8] {
        var s = 0
        var e = x.count
        while s < e, x[s] == 32 || x[s] == 9 { s += 1 }
        while e > s, x[e - 1] == 32 || x[e - 1] == 9 { e -= 1 }
        return Array(x[s..<e])
    }

    /// The alignments of a delimiter row (`|:--|:-:|--:|`), or nil when the line is not one.
    func delimiterRow(from: Int) -> [MarkdownTableAlignment]? {
        Self.delimiterAlignments(b, from, lineEnd)
    }

    static func delimiterAlignments(_ b: [UInt8], _ from: Int, _ to: Int) -> [MarkdownTableAlignment]? {
        func isSpaceOrTab(_ c: UInt8) -> Bool { c == 32 || c == 9 }
        var s = from
        var e = to
        while s < e, isSpaceOrTab(b[s]) { s += 1 }
        while e > s, isSpaceOrTab(b[e - 1]) { e -= 1 }
        var i = s
        if i < e, b[i] == 124 { i += 1 }
        var result: [MarkdownTableAlignment] = []
        while i < e {
            while i < e, isSpaceOrTab(b[i]) { i += 1 }
            var left = false
            var right = false
            if i < e, b[i] == 58 { left = true; i += 1 }
            var dashes = 0
            while i < e, b[i] == 45 { dashes += 1; i += 1 }
            if dashes == 0 { return nil }
            if i < e, b[i] == 58 { right = true; i += 1 }
            while i < e, isSpaceOrTab(b[i]) { i += 1 }
            result.append(left && right ? .center : left ? .left : right ? .right : .none)
            if i < e {
                guard b[i] == 124 else { return nil }
                i += 1
            }
        }
        return result.isEmpty ? nil : result
    }

    /// The paragraph `p` followed by a delimiter row becomes a table when its last line has as many cells
    /// as the delimiter row has columns; the paragraph's earlier lines stay a paragraph before it.
    mutating func tryOpenTable(_ p: Int) -> Int? {
        // Measured against Foundation (probe arms B18-B21): once a delimiter-looking line has failed to turn a
        // paragraph into a table, later delimiter rows cannot either.
        guard !nodes[p].tableRefused, let alignments = delimiterRow(from: firstNonspace) else { return nil }
        let content = nodes[p].content
        // the header is the paragraph's last line
        var headerStart = content.count - 1  // index of the final newline
        var hs = headerStart
        while hs > 0, content[hs - 1] != 10 { hs -= 1 }
        headerStart = hs
        let header = Self.splitRow(content, headerStart, content.count - 1)
        guard header.count == alignments.count else {
            nodes[p].tableRefused = true
            return nil
        }
        let table = TableData(alignments: alignments, header: header)
        tables.append(table)
        let lines = nodes[p].lineStarts
        let headerLineStart = lines.last ?? nodes[p].startOffset
        advance(lineEnd - offset, columns: false)
        if headerStart == 0 {
            nodes[p].kind = .table
            nodes[p].content = []
            nodes[p].lineStarts = []
            nodes[p].tableIndex = tables.count - 1
            return p
        }
        nodes[p].content = Array(content[0..<headerStart])
        nodes[p].lineStarts = Array(lines.dropLast())
        nodes[p].isOpen = false
        let parent = nodes[p].parent
        let t = addChild(parent, .table)
        nodes[t].tableIndex = tables.count - 1
        nodes[t].startOffset = headerLineStart
        return t
    }

    mutating func tryAddTableRow(_ t: Int) -> Bool {
        if blank { return false }
        var cells = rowCells(from: firstNonspace)
        if cells.isEmpty { return false }
        let columns = tables[nodes[t].tableIndex].header.count
        if cells.count > columns { cells.removeSubrange(columns...) }
        while cells.count < columns { cells.append([]) }
        tables[nodes[t].tableIndex].rows.append(cells)
        advance(lineEnd - offset, columns: false)
        return true
    }

    // MARK: Output

    func topLevel() -> [ParsedBlock] {
        var result: [ParsedBlock] = []
        var child = nodes[0].firstChild
        while child >= 0 {
            result.append(ParsedBlock(kind: kind(of: child), start: nodes[child].startOffset))
            child = nodes[child].next
        }
        return result
    }

    func blocks(of parent: Int) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var child = nodes[parent].firstChild
        while child >= 0 {
            result.append(MarkdownBlock(id: result.count, kind: kind(of: child)))
            child = nodes[child].next
        }
        return result
    }

    static func string(_ bytes: ArraySlice<UInt8>) -> String { String(decoding: bytes, as: UTF8.self) }
    static func string(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    func trimmedText(_ n: Int) -> String {
        var e = nodes[n].content.count
        while e > 0, nodes[n].content[e - 1] == 10 || nodes[n].content[e - 1] == 32 || nodes[n].content[e - 1] == 9 { e -= 1 }
        return Self.string(nodes[n].content[0..<e])
    }

    func kind(of n: Int) -> MarkdownBlock.Kind {
        let node = nodes[n]
        switch node.kind {
        case .paragraph:
            return .paragraph(trimmedText(n))
        case .heading:
            return .heading(level: node.level, text: trimmedText(n))
        case .thematicBreak:
            return .thematicBreak
        case .blockQuote:
            return .blockQuote(blocks(of: n))
        case .list:
            var items: [[MarkdownBlock]] = []
            var item = node.firstChild
            while item >= 0 {
                items.append(blocks(of: item))
                item = nodes[item].next
            }
            return .list(ordered: node.ordered, start: node.start, tight: node.tight, items: items)
        case .code:
            var content = node.content
            if content.last == 10 { content.removeLast() }
            var language: String?
            if node.fenced {
                var e = 0
                while e < node.info.count, node.info[e] != 32, node.info[e] != 9 { e += 1 }
                if e > 0 { language = Self.string(node.info[0..<e]) }
            }
            return .codeBlock(language: language, code: Self.string(content), isClosed: node.fenced ? node.closed : true)
        case .table:
            let t = tables[node.tableIndex]
            return .table(alignments: t.alignments, header: t.header.map(Self.string),
                          rows: t.rows.map { $0.map(Self.string) })
        case .item, .document:
            return .paragraph("")
        }
    }
}
