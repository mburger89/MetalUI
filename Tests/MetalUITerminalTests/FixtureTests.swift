import Foundation
import Testing
@testable import MetalUITerminal

/// The `*.vtfix` conformance corpus (spec section 8), authored here with no third-party fixtures.
///
/// A fixture is line oriented; `#` starts a comment line.
///
///     size <cols> <rows>            required
///     scrollback <n>                optional, default 10000
///     input "<escaped bytes>"       one or more; concatenated
///     text                          then one `|row|` line per screen row (trailing blanks are not compared)
///     history                       then one `|row|` line per retained scrollback row, oldest first
///     cursor <row> <col> [pending]  viewport coordinates
///     modes <name>=<value> ...      TerminalModes members: on/off, tracking/encoding names, cursorStyle
///                                   (`block`, `bar-blinking`, ...)
///     attr <row> <col> <token> ...  the cell's whole rendition: `plain`, `bold dim italic blink inverse hidden
///                                   strike`, `underline=single|double|curly|dotted|dashed`, and `fg= bg= ul=`
///                                   with `default`, an index `N` or `R,G,B`; unlisted members are default
///     replies "<escaped bytes>"     the concatenated `.reply` events, in order
///     events <name> ...             the other events, in order: `bell`, `title:T`, `cwd:/path`, `link:ID:URI`
///                                   (no spaces inside a name); `link=N` in an `attr` is the hyperlink id
///
/// Escapes in `input` and in `|row|` lines: `\e \r \n \t \\ \"`, `\xHH` (one raw byte), `\u{H...}` (that scalar
/// as UTF-8). Every fixture is run whole, byte at a time and split at every position; all must agree.
struct Fixture {
    var name: String
    var cols = 0, rows = 0, scrollback = 10_000
    var input: [UInt8] = []
    var text: [String]?
    var history: [String]?
    var cursor: (row: Int, col: Int, pending: Bool)?
    var modes: [String: String] = [:]
    var attrs: [(row: Int, col: Int, expected: TerminalAttributes)] = []
    var replies: [UInt8]?
    var events: [String]?

    static func color(_ text: String) -> TerminalColor {
        if text == "default" { return .default }
        let n = text.split(separator: ",").compactMap { UInt8($0) }
        return n.count == 3 ? .rgb(n[0], n[1], n[2]) : .indexed(n[0])
    }

    static func attributes(_ tokens: [String]) -> TerminalAttributes {
        var a = TerminalAttributes()
        for token in tokens {
            let kv = token.split(separator: "=").map(String.init)
            switch kv[0] {
            case "plain": break
            case "bold": a.bold = true
            case "dim": a.dim = true
            case "italic": a.italic = true
            case "blink": a.blink = true
            case "inverse": a.inverse = true
            case "hidden": a.hidden = true
            case "strike": a.strikethrough = true
            case "underline":
                a.underlineStyle = ["single": .single, "double": .double, "curly": .curly, "dotted": .dotted,
                                    "dashed": .dashed][kv[1]] ?? .none
            case "fg": a.foreground = color(kv[1])
            case "bg": a.background = color(kv[1])
            case "ul": a.underlineColor = color(kv[1])
            case "link": a.hyperlink = UInt32(kv[1])
            default: Issue.record("unknown attribute token \(token)")
            }
        }
        return a
    }

    static func unescape(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        let chars = Array(s.unicodeScalars)
        var i = 0
        func hex(_ range: Range<Int>) -> UInt32 { UInt32(String(String.UnicodeScalarView(chars[range])), radix: 16) ?? 0 }
        while i < chars.count {
            let c = chars[i]
            guard c == "\\", i + 1 < chars.count else {
                out.append(contentsOf: Array(String(c).utf8))
                i += 1
                continue
            }
            let n = chars[i + 1]
            switch n {
            case "e": out.append(0x1B); i += 2
            case "r": out.append(0x0D); i += 2
            case "n": out.append(0x0A); i += 2
            case "t": out.append(0x09); i += 2
            case "x": out.append(UInt8(hex((i + 2)..<(i + 4)))); i += 4
            case "u":
                var j = i + 3
                while chars[j] != "}" { j += 1 }
                if let scalar = Unicode.Scalar(hex((i + 3)..<j)) {
                    out.append(contentsOf: Array(String(scalar).utf8))
                } else {
                    Issue.record("\\u{...} escape is not a Unicode scalar: \(String(String.UnicodeScalarView(chars[i..<j])))")
                }
                i = j + 1
            default: out.append(contentsOf: Array(String(n).utf8)); i += 2
            }
        }
        return out
    }

    /// An integer field of a fixture file; a malformed one is recorded and read as 0.
    static func integer<S: StringProtocol>(_ text: S, in name: String) -> Int {
        guard let value = Int(text) else { Issue.record("\(name): \(text) is not an integer"); return 0 }
        return value
    }

    static func parse(_ source: String, name: String) -> Fixture {
        var f = Fixture(name: name)
        var block: String?
        for raw in source.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("|") {
                let row = String(decoding: unescape(String(line.dropFirst().dropLast())), as: UTF8.self)
                if block == "text" { f.text = (f.text ?? []) + [row] } else if block == "history" { f.history = (f.history ?? []) + [row] }
                continue
            }
            block = nil
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "size":
                let n = parts[1].split(separator: " ").compactMap { Int($0) }
                f.cols = n[0]; f.rows = n[1]
            case "scrollback": f.scrollback = integer(parts[1], in: name)
            case "input": f.input += unescape(String(parts[1].dropFirst().dropLast()))
            case "text": block = "text"; f.text = []
            case "history": block = "history"; f.history = []
            case "cursor":
                let n = parts[1].split(separator: " ")
                f.cursor = (integer(n[0], in: name), integer(n[1], in: name), n.count > 2 && n[2] == "pending")
            case "attr":
                let n = parts[1].split(separator: " ").map(String.init)
                f.attrs.append((integer(n[0], in: name), integer(n[1], in: name), attributes(Array(n.dropFirst(2)))))
            case "replies": f.replies = unescape(String(parts[1].dropFirst().dropLast()))
            case "events": f.events = parts.count > 1 ? parts[1].split(separator: " ").map(String.init) : []
            case "modes":
                for pair in parts[1].split(separator: " ") {
                    let kv = pair.split(separator: "=").map(String.init)
                    f.modes[kv[0]] = kv[1]
                }
            default: Issue.record("\(name): unknown key \(parts[0])")
            }
        }
        return f
    }

    func modeValue(_ m: TerminalModes, _ key: String) -> String? {
        func b(_ v: Bool) -> String { v ? "on" : "off" }
        switch key {
        case "autowrap": return b(m.autowrap)
        case "cursorVisible": return b(m.cursorVisible)
        case "bracketedPaste": return b(m.bracketedPaste)
        case "applicationCursorKeys": return b(m.applicationCursorKeys)
        case "applicationKeypad": return b(m.applicationKeypad)
        case "focusEvents": return b(m.focusEvents)
        case "mouseTracking": return "\(m.mouseTracking)"
        case "mouseEncoding": return "\(m.mouseEncoding)"
        case "originMode": return b(m.originMode)
        case "alternateScreen": return b(m.alternateScreen)
        case "cursorStyle": return "\(m.cursorStyle.shape)" + (m.cursorStyle.blinking ? "-blinking" : "")
        default: return nil
        }
    }

    /// Runs the fixture with the input cut at `cuts`, returning problems.
    func run(cuts: [Int]) -> [String] {
        let e = TerminalEmulator(cols: cols, rows: rows, scrollback: scrollback)
        var start = 0
        for cut in cuts + [input.count] {
            e.feed(Array(input[start..<cut]))
            start = cut
        }
        var problems: [String] = []
        let tag = "\(name) cuts=\(cuts.prefix(3))"
        if let text, text != e.screenLines { problems.append("\(tag): text \(e.screenLines) != \(text)") }
        if let history, history != e.historyLines { problems.append("\(tag): history \(e.historyLines) != \(history)") }
        if let cursor {
            let c = e.cursorPosition
            if c.row != cursor.row || c.col != cursor.col || c.pending != cursor.pending {
                problems.append("\(tag): cursor \(c) != \(cursor)")
            }
        }
        for (key, want) in modes {
            let got = modeValue(e.modes, key)
            if got != want { problems.append("\(tag): mode \(key) = \(got ?? "unknown") != \(want)") }
        }
        let drained = e.drainEvents()
        if let replies {
            let got = drained.flatMap { event -> [UInt8] in if case .reply(let bytes) = event { return bytes } else { return [] } }
            if got != replies {
                problems.append("\(tag): replies \(String(decoding: got, as: UTF8.self).debugDescription) != "
                                + "\(String(decoding: replies, as: UTF8.self).debugDescription)")
            }
        }
        if let events {
            let got = drained.compactMap { event -> String? in
                switch event {
                case .bell: return "bell"
                case .reply: return nil
                case .title(let text): return "title:\(text)"
                case .workingDirectory(let url): return "cwd:\(url.path)"
                case .hyperlink(let id, let uri): return "link:\(id):\(uri)"
                }
            }
            if got != events { problems.append("\(tag): events \(got) != \(events)") }
        }
        for check in attrs {
            let got = e.screen[check.row].cell(at: check.col).attributes
            if got != check.expected { problems.append("\(tag): attr \(check.row),\(check.col) \(got) != \(check.expected)") }
        }
        return problems
    }
}

private let fixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

private func loadFixtures() -> [Fixture] {
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)) ?? [])
        .filter { $0.hasSuffix(".vtfix") }.sorted()
    return names.compactMap { name in
        (try? String(contentsOf: fixtureDirectory.appendingPathComponent(name), encoding: .utf8))
            .map { Fixture.parse($0, name: name) }
    }
}

@Suite struct FixtureTests {
    @Test func theCorpusIsPresent() {
        #expect(loadFixtures().count >= 40)
    }

    @Test func everyFixtureHoldsWholeByteAtATimeAndSplitAtEveryPosition() {
        for fixture in loadFixtures() {
            #expect(fixture.run(cuts: []) == [], "\(fixture.name)")
            #expect(fixture.run(cuts: Array(0..<fixture.input.count)) == [], "\(fixture.name) byte at a time")
            for cut in 0...fixture.input.count {
                #expect(fixture.run(cuts: [cut]) == [], "\(fixture.name) cut \(cut)")
            }
        }
    }

    @Test func theFixtureReaderUnderstandsItsEscapes() {
        #expect(Fixture.unescape("a\\e\\x9b\\u{E9}\\\\") == [0x61, 0x1B, 0x9B, 0xC3, 0xA9, 0x5C])
    }
}
