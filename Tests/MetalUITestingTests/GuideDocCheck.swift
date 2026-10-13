import Foundation
import Testing

// The doc-check for `docs/guides/` (rulings `DG-C`…`DG-E`, `DG-K`, `DG-M`; spec
// `2026-10-12-guides-design.md` §3 and §5). A guide's ```swift fence is a complete
// file-scope fragment; it is copied BY HAND, byte for byte, between
// `// guide: <name> #<n>` and `// end guide` in a `GuideMirrors*.swift` file of this
// target, which the ordinary build compiles on every platform. These tests parse the
// guides and the mirrors and fail when they differ, when a cited pin or divergence
// does not exist, when a link is dead, when a guide names an unmerged API, or when a
// sentence makes a behaviour claim without a pin. The helper is `GuideDocs`; lane 2's
// mirror file and `theGuideSetIsComplete` use it. It reads the repository from
// `#filePath` and never writes.

/// The parser and the checks, as pure functions of text so a synthetic input can
/// prove them before any guide is trusted (`T7`).
enum GuideDocs {
    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    /// One fenced code block: the marker character, the info string, the content
    /// lines (the fence's own indent removed) and the 1-based line of its opener.
    struct Fence: Equatable {
        var marker: Character
        var info: String
        var lines: [String]
        var line: Int
        var text: String { lines.joined(separator: "\n") }
    }

    /// A parsed guide: its fences in order and its prose lines (outside every fence).
    struct Parsed {
        var fences: [Fence]
        var prose: [(line: Int, text: String)]
    }

    /// One mirrored block.
    struct Region: Equatable {
        var guide: String
        var number: Int
        var text: String
        var file: String
    }

    /// CRLF to LF (`DG-K`); nothing else is normalised.
    static func normalise(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    static func lines(of text: String) -> [String] {
        normalise(text).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// The fence a line opens: marker, length, indent and info string.
    private static func opener(_ line: String) -> (marker: Character, length: Int, indent: Int, info: String)? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let rest = line.dropFirst(indent)
        guard let marker = rest.first, marker == "`" || marker == "~" else { return nil }
        let length = rest.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }
        let info = rest.dropFirst(length).trimmingCharacters(in: .whitespaces)
        if marker == "`" && info.contains("`") { return nil }
        return (marker, length, indent, info)
    }

    private static func closes(_ line: String, marker: Character, length: Int) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        let run = trimmed.prefix { $0 == marker }.count
        return run >= length && trimmed.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// Fences (backtick and tilde, at any indent, so those nested in lists are found)
    /// and the prose between them. An unterminated fence throws.
    static func parse(_ markdown: String) throws -> Parsed {
        var fences: [Fence] = []
        var prose: [(line: Int, text: String)] = []
        var open: (marker: Character, length: Int, indent: Int, info: String, line: Int, lines: [String])?
        for (offset, line) in lines(of: markdown).enumerated() {
            if var current = open {
                if closes(line, marker: current.marker, length: current.length) {
                    fences.append(Fence(marker: current.marker, info: current.info, lines: current.lines, line: current.line))
                    open = nil
                } else {
                    var stripped = Substring(line)
                    var remaining = current.indent
                    while remaining > 0, let first = stripped.first, first == " " || first == "\t" {
                        stripped = stripped.dropFirst()
                        remaining -= 1
                    }
                    current.lines.append(String(stripped))
                    open = current
                }
            } else if let found = opener(line) {
                open = (found.marker, found.length, found.indent, found.info, offset + 1, [])
            } else {
                prose.append((offset + 1, line))
            }
        }
        if let current = open {
            throw ParseError(description: "the fence opened at line \(current.line) is never closed")
        }
        return Parsed(fences: fences, prose: prose)
    }

    /// The `// guide: <name> #<n>` … `// end guide` regions of a mirror file.
    static func regions(in source: String, file: String) throws -> [Region] {
        var found: [Region] = []
        var open: (guide: String, number: Int, lines: [String], line: Int)?
        let header = try NSRegularExpression(pattern: #"^// guide: ([a-z0-9-]+) #([0-9]+)$"#)
        for (offset, line) in lines(of: source).enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if line == "// end guide" {
                guard let current = open else {
                    throw ParseError(description: "\(file):\(offset + 1): `// end guide` closes nothing")
                }
                found.append(Region(guide: current.guide, number: current.number,
                                    text: current.lines.joined(separator: "\n"), file: file))
                open = nil
            } else if let match = header.firstMatch(in: line, range: range) {
                if let current = open {
                    throw ParseError(description: "\(file):\(offset + 1): the region of \(current.guide) #\(current.number) (line \(current.line)) is not closed")
                }
                let name = String(line[Range(match.range(at: 1), in: line)!])
                let number = Int(line[Range(match.range(at: 2), in: line)!])!
                open = (name, number, [], offset + 1)
            } else if var current = open {
                current.lines.append(line)
                open = current
            }
        }
        if let current = open {
            throw ParseError(description: "\(file): the region of \(current.guide) #\(current.number) (line \(current.line)) is never closed")
        }
        return found
    }

    // MARK: Prose checks

    /// Inline code spans removed: a word inside backticks is a name, not a claim.
    static func withoutInlineCode(_ text: String) -> String {
        text.replacingOccurrences(of: #"`[^`]*`"#, with: "``", options: .regularExpression)
    }

    /// The pin names a text cites: `pin:` followed by backticked names, wherever it sits
    /// (`(pin: \`a\`)`, `(divergence 78; pin: \`a\`, \`b\`)`).
    static func pins(in text: String) -> [String] {
        var names: [String] = []
        for group in captures(pinPattern, in: text) {
            for name in captures(#"`([^`]+)`"#, in: group[0]) { names.append(name[0]) }
        }
        return names
    }

    private static let pinPattern = #"\bpin:\s*((?:`[^`]+`(?:,\s*)?)+)"#

    /// How many `pin:` markers do not parse as a pin (no backticked name after the colon):
    /// such a citation would otherwise be skipped without a word. The word is therefore
    /// not written with a colon in prose that is not a citation.
    static func malformedPinCount(in text: String) -> Int {
        let markers = captures(#"\bpin:"#, in: text).count
        return markers - captures(pinPattern, in: text).count
    }

    /// Divergence labels a text cites: `divergence 52`, `divergences 145–147`,
    /// `divergences 94, 110 and 139`.
    static func divergenceLabels(in text: String) -> [Int] {
        var labels: [Int] = []
        let list = #"(?:\d+(?:\s*[–-]\s*\d+)?)(?:\s*(?:,|and|, and)\s*\d+(?:\s*[–-]\s*\d+)?)*"#
        for group in captures(#"[Dd]ivergences?\s+("# + list + ")", in: text) {
            for item in captures(#"(\d+)(?:\s*[–-]\s*(\d+))?"#, in: group[0]) {
                let low = Int(item[0])!
                if item.count > 1, let high = Int(item[1]), high >= low, high - low <= 50 {
                    labels.append(contentsOf: low...high)
                } else {
                    labels.append(low)
                }
            }
        }
        return labels
    }

    /// Relative link targets (file part only) of `[text](target)`.
    static func relativeLinks(in text: String) -> [String] {
        captures(#"\]\(\s*([^)\s]+)\s*\)"#, in: text).map { $0[0] }.compactMap { target in
            if target.hasPrefix("http://") || target.hasPrefix("https://") || target.hasPrefix("mailto:") || target.hasPrefix("#") {
                return nil
            }
            return String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        }
    }

    /// Paragraph-ish blocks of prose, wrapped lines joined: a blank line, a list item, a
    /// table row or a heading starts a new one. The pin, label and link checks read these,
    /// so a citation broken across two lines is still seen.
    static func blocks(of prose: [(line: Int, text: String)]) -> [(line: Int, text: String)] {
        var blocks: [(line: Int, text: String)] = []
        var current: (line: Int, text: String)?
        func flush() {
            if let block = current { blocks.append(block) }
            current = nil
        }
        for (line, text) in prose {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let startsBlock = trimmed.isEmpty || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("|") || trimmed.hasPrefix("#") || trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil
            if startsBlock { flush() }
            if trimmed.isEmpty { continue }
            if let block = current {
                current = (block.line, block.text + " " + trimmed)
            } else {
                current = (line, trimmed)
            }
        }
        flush()
        return blocks
    }

    /// The blocks split into sentences (each keeps its block's first line).
    static func sentences(of prose: [(line: Int, text: String)]) -> [(line: Int, text: String)] {
        var out: [(line: Int, text: String)] = []
        for block in blocks(of: prose) {
            let parts = block.text.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\u{1}", options: .regularExpression)
                .split(separator: "\u{1}").map(String.init)
            for part in parts { out.append((block.line, part)) }
        }
        return out
    }

    static let behaviourPattern =
        #"\b(reset|resets|cancel|cancels|cancelled|retain|retains|retained|focuses|dismiss|dismisses|dismissed)\b"#

    /// Sentences that make a behaviour claim and cite no pin (`DG-E`).
    static func unpinnedBehaviourSentences(in prose: [(line: Int, text: String)]) -> [(line: Int, text: String)] {
        sentences(of: prose).filter { sentence in
            let bare = withoutInlineCode(sentence.text)
            let claims = bare.range(of: behaviourPattern, options: [.regularExpression, .caseInsensitive]) != nil
            return claims && pins(in: sentence.text).isEmpty
        }
    }

    static let deniedNames = ["resignsFocusOnPress", "TextMeasurer", "PhaseAnimator"]

    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let all = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: all).map { match in
            (1..<max(match.numberOfRanges, 2)).compactMap { index in
                guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    // MARK: Repository

    /// The repository root, from this file's place in it.
    static let root: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static var guidesDirectory: URL { root.appendingPathComponent("docs/guides") }

    struct Guide {
        var name: String
        var url: URL
        var parsed: Parsed
        var source: String
    }

    /// Every `docs/guides/*.md` except the README, parsed.
    static func guides() throws -> [Guide] {
        let names = try FileManager.default.contentsOfDirectory(atPath: guidesDirectory.path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }.sorted()
        return try names.map { file in
            let url = guidesDirectory.appendingPathComponent(file)
            let source = try String(contentsOf: url, encoding: .utf8)
            do {
                return Guide(name: String(file.dropLast(3)), url: url, parsed: try parse(source), source: source)
            } catch let error as ParseError {
                throw ParseError(description: "\(file): \(error.description)")
            }
        }
    }

    /// The README, parsed like a guide for the link and divergence checks.
    static func readme() throws -> Guide {
        let url = guidesDirectory.appendingPathComponent("README.md")
        let source = try String(contentsOf: url, encoding: .utf8)
        return Guide(name: "README", url: url, parsed: try parse(source), source: source)
    }

    /// Every mirrored region of every `GuideMirrors*.swift` file in this target.
    static func mirrorRegions() throws -> [Region] {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("GuideMirrors") && $0.hasSuffix(".swift") }.sorted()
        var all: [Region] = []
        for file in files {
            let source = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            all.append(contentsOf: try regions(in: source, file: file))
        }
        return all
    }

    /// The source of every Swift file under `Tests/`, skipping build directories.
    static let testSources: String = {
        var text = ""
        let tests = root.appendingPathComponent("Tests")
        guard let walker = FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil) else { return text }
        for case let url as URL in walker {
            if url.pathComponents.contains(".build") { walker.skipDescendants(); continue }
            if url.pathExtension == "swift", let source = try? String(contentsOf: url, encoding: .utf8) {
                text += source
                text += "\n"
            }
        }
        return text
    }()

    /// Every `func name` declared under `Tests/`, read once.
    static let testFunctionNames: Set<String> = {
        var names: Set<String> = []
        for match in captures(#"func ([A-Za-z0-9_]+)"#, in: testSources) { names.insert(match[0]) }
        return names
    }()

    static func testExists(_ name: String) -> Bool {
        testFunctionNames.contains(name)
    }

    static let divergenceRows: Set<Int> = {
        let url = root.appendingPathComponent("docs/divergences.md")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var rows: Set<Int> = []
        for line in lines(of: source) {
            if let match = captures(#"^\|\s*(\d+)\s*\|"#, in: line).first, let number = Int(match[0]) { rows.insert(number) }
        }
        return rows
    }()

    /// Every guide plus the README, for the checks that read prose only.
    static func everyDocument() throws -> [Guide] {
        try guides() + [readme()]
    }
}

// MARK: - T1

/// **T1.** Per guide, the swift fences equal the mirror regions in order, byte for
/// byte (CRLF normalised, `DG-K`), and each guide has at least one. Red before: the
/// guides directory does not exist. Mutations: one character changed in a guide
/// block; one in the mirror; a `// end guide` deleted; an unmirrored swift fence.
@Test func everyGuideBlockIsCompiledVerbatim() throws {
    let guides = try GuideDocs.guides()
    try #require(!guides.isEmpty, "docs/guides holds no guide")
    let regions = try GuideDocs.mirrorRegions()
    let names = Set(guides.map(\.name))
    for region in regions {
        #expect(names.contains(region.guide), "\(region.file) mirrors \(region.guide) #\(region.number), which has no guide")
    }
    for guide in guides {
        let blocks = guide.parsed.fences.filter { $0.info == "swift" }
        try #require(!blocks.isEmpty, "\(guide.name) has no swift block")
        let mirrored = regions.filter { $0.guide == guide.name }.sorted { $0.number < $1.number }
        #expect(mirrored.map(\.number) == (0..<mirrored.count).map { $0 + 1 },
                "\(guide.name): mirror numbers \(mirrored.map(\.number)) are not 1…\(mirrored.count)")
        #expect(mirrored.count == blocks.count,
                "\(guide.name): \(blocks.count) swift blocks, \(mirrored.count) mirrored")
        for (index, block) in blocks.enumerated() where index < mirrored.count {
            let copy = GuideDocs.normalise(mirrored[index].text)
            #expect(block.text == copy,
                    "\(guide.name) block \(index + 1) (line \(block.line)) differs from its copy in \(mirrored[index].file)")
        }
    }
}

// MARK: - T2

/// **T2.** A fence is exactly ```swift, ```text or ```sh: no other info string, no
/// tilde fence (`DG-D`'s extractor would not see what it cannot name).
@Test func aSwiftFenceCarriesNoInfoStringAndOtherFencesAreNamed() throws {
    let documents = try GuideDocs.everyDocument()
    for document in documents {
        for fence in document.parsed.fences {
            #expect(fence.marker == "`", "\(document.name):\(fence.line): a tilde fence")
            #expect(["swift", "text", "sh"].contains(fence.info),
                    "\(document.name):\(fence.line): the info string `\(fence.info)` is not swift, text or sh")
        }
    }
}

// MARK: - T3

/// **T3.** Each `(pin: \`name\`)` names a `func` under `Tests/` (`DG-E`, `DG-M`).
/// Mutations: a misspelt name; a renamed pinned test.
@Test func everyCitedPinNamesATestThatExists() throws {
    let documents = try GuideDocs.everyDocument()
    var cited = 0
    for document in documents {
        for (line, text) in GuideDocs.blocks(of: document.parsed.prose) {
            #expect(GuideDocs.malformedPinCount(in: text) == 0, "\(document.name):\(line): a `pin:` that is not followed by a backticked test name")
            for name in GuideDocs.pins(in: text) {
                cited += 1
                #expect(GuideDocs.testExists(name), "\(document.name):\(line): the pin `\(name)` names no test")
            }
        }
    }
    try #require(cited > 0, "no guide cites a pin")
}

// MARK: - T4

/// **T4.** Each cited divergence label has a row in `docs/divergences.md`.
/// Mutation: cite 999.
@Test func everyCitedDivergenceHasARow() throws {
    let documents = try GuideDocs.everyDocument()
    try #require(GuideDocs.divergenceRows.count > 100, "divergences.md was not read")
    var cited = 0
    for document in documents {
        for (line, text) in GuideDocs.blocks(of: document.parsed.prose) {
            for label in GuideDocs.divergenceLabels(in: text) {
                cited += 1
                #expect(GuideDocs.divergenceRows.contains(label), "\(document.name):\(line): divergence \(label) has no row")
            }
        }
    }
    try #require(cited > 0, "no guide cites a divergence")
}

// MARK: - T5

/// **T5.** Each relative link in a guide resolves to a file or directory.
/// Mutation: break a link.
@Test func everyRelativeLinkResolves() throws {
    let documents = try GuideDocs.everyDocument()
    var checked = 0
    for document in documents {
        let directory = document.url.deletingLastPathComponent()
        for (line, text) in GuideDocs.blocks(of: document.parsed.prose) {
            for target in GuideDocs.relativeLinks(in: text) where !target.isEmpty {
                checked += 1
                let resolved = URL(fileURLWithPath: target, relativeTo: directory).standardizedFileURL
                #expect(FileManager.default.fileExists(atPath: resolved.path),
                        "\(document.name):\(line): the link `\(target)` resolves to nothing")
            }
        }
    }
    try #require(checked > 0, "no guide links anywhere")
}

// MARK: - T6

/// **T6.** No guide names an API that is not on master (`DG-F`). Mutation: add one.
@Test func noGuideNamesAnApiThatIsNotOnMaster() throws {
    for document in try GuideDocs.everyDocument() {
        for name in GuideDocs.deniedNames {
            #expect(!document.source.contains(name), "\(document.name) names \(name), which is not on master")
        }
    }
}

// MARK: - behaviour words

/// A sentence with a behaviour word (resets, cancels, retains, focuses, dismisses and
/// their forms, outside inline code) cites a pin (`DG-E`). Mutation: delete a pin.
@Test func aBehaviourWordHasAPinOnItsLine() throws {
    let documents = try GuideDocs.everyDocument()
    for document in documents {
        for sentence in GuideDocs.unpinnedBehaviourSentences(in: document.parsed.prose) {
            #expect(Bool(false), "\(document.name):\(sentence.line): a behaviour claim without a pin: \(sentence.text)")
        }
    }
}

// MARK: - T7

/// **T7.** The extractor on synthetic input, so a broken parser reddens here before
/// any guide: an indented fence in a list, a tilde fence (named, so T2 can refuse it),
/// CRLF, an unterminated fence (an error), a longer closing run, an inline triple tick.
@Test func theExtractorFindsFencesNestedInListsAndIgnoresTildesAndCRLF() throws {
    let nested = "1. Step\n\n   ```swift\n   let a = 1\n     let b = 2\n   ```\n\nafter\n"
    let parsed = try GuideDocs.parse(nested)
    #expect(parsed.fences.count == 1)
    #expect(parsed.fences.first?.info == "swift")
    #expect(parsed.fences.first?.text == "let a = 1\n  let b = 2", "the fence's own indent is removed, deeper indent kept")
    #expect(parsed.prose.map(\.text).contains("after"))
    #expect(!parsed.prose.map(\.text).contains("   let a = 1"), "fence content is not prose")

    let crlf = "```swift\r\nlet a = 1\r\nlet b = 2\r\n```\r\n"
    #expect(try GuideDocs.parse(crlf).fences.first?.text == "let a = 1\nlet b = 2", "CRLF is normalised")
    #expect(GuideDocs.normalise("a\r\nb") == "a\nb")
    #expect(GuideDocs.normalise("a \r\nb") != "a\nb", "trailing whitespace is not normalised")

    let tilde = try GuideDocs.parse("~~~swift\nlet x = 1\n~~~\n")
    #expect(tilde.fences.count == 1 && tilde.fences[0].marker == "~", "a tilde fence is found and named, for T2 to refuse")

    let longer = try GuideDocs.parse("````text\n```\nstill inside\n````\nprose\n")
    #expect(longer.fences.count == 1 && longer.fences[0].lines == ["```", "still inside"],
            "a closing run must be as long as the opener")
    #expect(longer.fences[0].info == "text")

    let inline = try GuideDocs.parse("Write ```swift``` inline.\n")
    #expect(inline.fences.isEmpty, "an inline triple tick is not a fence")

    #expect(throws: GuideDocs.ParseError.self) { try GuideDocs.parse("```swift\nlet a = 1\n") }

    let region = "x\n// guide: layout #1\nlet a = 1\n// end guide\n// guide: layout #2\n\n// end guide\n"
    let found = try GuideDocs.regions(in: region, file: "f")
    #expect(found.map(\.number) == [1, 2] && found[0].text == "let a = 1" && found[1].text == "")
    #expect(throws: GuideDocs.ParseError.self) { try GuideDocs.regions(in: "// guide: layout #1\nlet a = 1\n", file: "f") }
    #expect(throws: GuideDocs.ParseError.self) { try GuideDocs.regions(in: "// end guide\n", file: "f") }
    #expect(throws: GuideDocs.ParseError.self) {
        try GuideDocs.regions(in: "// guide: layout #1\n// guide: layout #2\n// end guide\n", file: "f")
    }
}

/// The prose checks on synthetic input (`T7`'s companion): pins, labels, links and the
/// behaviour-word rule find what they should and nothing else.
@Test func theProseChecksReadPinsLabelsLinksAndBehaviourWords() throws {
    #expect(GuideDocs.pins(in: "It holds (pin: `aTest`) and (pin: `b`, `c`).") == ["aTest", "b", "c"])
    #expect(GuideDocs.pins(in: "No pin here (see `aTest`).").isEmpty)
    #expect(GuideDocs.pins(in: "(divergence 110; pin: `aTest`)") == ["aTest"], "a pin after a semicolon is seen")
    #expect(GuideDocs.malformedPinCount(in: "(pin: `a`; and more) (pin: `b`) (pin: c) and pin: .") == 2, "a pin that does not parse is counted")
    #expect(GuideDocs.malformedPinCount(in: "(pin: `a`, `b`) and (pin: `c`)") == 0)
    #expect(GuideDocs.divergenceLabels(in: "divergence 52, divergences 145–147 and divergences 94, 110 and 139.")
        == [52, 145, 146, 147, 94, 110, 139])
    #expect(GuideDocs.divergenceLabels(in: "a divergence from SwiftUI, 12 rows").isEmpty)
    #expect(GuideDocs.relativeLinks(in: "[a](../divergences.md#x) [b](https://x.y) [c](#top) [d](f.md)")
        == ["../divergences.md", "f.md"])

    let wrapped: [(line: Int, text: String)] = [(1, "A claim (pin:"), (2, "`aTest`) and a divergence"), (3, "52 and a [link]("), (4, "x.md)."), (5, ""), (6, "- next item")]
    let joined = GuideDocs.blocks(of: wrapped)
    #expect(joined.map(\.line) == [1, 6], "read \(joined)")
    #expect(GuideDocs.pins(in: joined[0].text) == ["aTest"], "a pin broken across lines is seen in its block")
    #expect(GuideDocs.divergenceLabels(in: joined[0].text) == [52], "so is a label")
    #expect(GuideDocs.relativeLinks(in: joined[0].text) == ["x.md"], "and a link")

    let prose: [(line: Int, text: String)] = [
        (1, "State resets when the branch is evaluated (pin: `aTest`). A `reset` name is code."),
        (2, ""),
        (3, "A second sentence retains nothing"),
        (4, ""),
        (5, "- A list item that cancels the press."),
        (6, "- A list item that cancels the press (pin: `x`)."),
    ]
    let flagged = GuideDocs.unpinnedBehaviourSentences(in: prose)
    #expect(flagged.map(\.line) == [3, 5], "read \(flagged)")
    #expect(GuideDocs.unpinnedBehaviourSentences(in: [(1, "The `onCancelled` closure runs.")]).isEmpty,
            "a name in code is not a claim")
}
