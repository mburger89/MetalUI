import MetalUIMarkdown

/// A compact, id-free rendering of a block tree, so an expectation reads as one string.
///
/// `p'text'`, `h2'text'`, `code(lang,open|closed)'text'`, `bq[...]`, `ul/tight[[item] [item]]`, `ol3/loose[...]`,
/// `hr`, `table(n,l,c,r){head|head}{cell|cell}...`; newlines inside text print as `¶`.
func render(_ blocks: [MarkdownBlock]) -> String {
    blocks.map(render).joined(separator: " ")
}

func render(_ block: MarkdownBlock) -> String {
    func q(_ s: String) -> String { "'" + s.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "¶") + "'" }
    switch block.kind {
    case .paragraph(let t): return "p" + q(t)
    case .heading(let level, let t): return "h\(level)" + q(t)
    case .codeBlock(let language, let code, let isClosed): return "code(\(language ?? "-"),\(isClosed ? "closed" : "open"))" + q(code)
    case .blockQuote(let c): return "bq[" + render(c) + "]"
    case .list(let ordered, let start, let tight, let items):
        let head = (ordered ? "ol\(start)" : "ul") + (tight ? "/tight" : "/loose")
        return head + "[" + items.map { "[" + render($0) + "]" }.joined(separator: " ") + "]"
    case .thematicBreak: return "hr"
    case .table(let alignments, let header, let rows):
        let a = alignments.map { x -> String in
            switch x { case .none: return "n"; case .left: return "l"; case .center: return "c"; case .right: return "r" }
        }.joined(separator: ",")
        return "table(\(a)){" + header.joined(separator: "|") + "}" + rows.map { "{" + $0.joined(separator: "|") + "}" }.joined()
    }
}

func parse(_ text: String) -> String { render(MarkdownDocument.parseWhole(text)) }

/// A fixed-seed generator so a corpus is the same on every run and platform.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
