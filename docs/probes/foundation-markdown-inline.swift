// Foundation probe: what `AttributedString(markdown:)` answers for the inline
// corpus `swiftui-rich-text.swift` rendered (arms M1–M29), and whether it —
// and `AttributedString` itself — exist off Apple.
//
// Evidence for rulings RT-B and RT-C in
// docs/superpowers/2026-10-08-rich-text-decisions.md.
//
// HOW TO RUN, from the repository root:
//
//   macOS:  xcrun swiftc docs/probes/foundation-markdown-inline.swift -o /tmp/md-probe && /tmp/md-probe
//   Linux:  docker run --rm -v "$PWD":/w -w /w swift:6.4-noble bash -c \
//             'swiftc -D LINUX_PROBE docs/probes/foundation-markdown-inline.swift -o /tmp/p && /tmp/p'
//
// The Linux form compiles only the `LINUX_PROBE` half: an `AttributedString`
// with a custom `AttributeScope` (dynamic member lookup) and Foundation's
// `link` attribute. The markdown initialiser is not spelled there, because it
// does not exist: compiling `try AttributedString(markdown: "**b**")` against
// `swift:6.4-noble` (Swift 6.4-RELEASE, aarch64) fails with "no exact matches
// in call to initializer" under both `import Foundation` and
// `import FoundationEssentials`, and `inlinePresentationIntent` "cannot be
// resolved without a contextual type" (L2, L3 below — recorded by hand,
// since a probe that does not compile prints nothing).
//
// RECORDED 2026-10-08 by the rich-text design session.
//
// Linux (swift:6.4-noble, `-D LINUX_PROBE`, both `import Foundation` and
// `import FoundationEssentials` builds):
//
//     L1 run "hello " foreground=nil link=Optional(https://x.org)
//     L1 run "world" foreground=Optional(MColor(r: 1.0)) link=Optional(https://x.org)
//     L2 AttributedString(markdown:) — does not compile (no exact matches in call to initializer)
//     L3 inlinePresentationIntent — does not compile (cannot be resolved without a contextual type)
//
// macOS 27.0 (compiled; intent raw values 1 emphasized, 2 stronglyEmphasized,
// 3 both, 4 code, 32 strikethrough, 128 lineBreak). Every row agrees with the
// SwiftUI render of the same arm in `swiftui-rich-text.swift`, M22 included
// (the link text's strong emphasis is dropped by the parser itself; the N rows were not rendered, except N1, N3
// and N13 as SwiftUI arms M32–M34, and N21 as M35 — which agree):
//
//     M1 "**b**" → ["b" intent=2]
//     M3a "*i*" → ["i" intent=1]
//     M3b "_i_" → ["i" intent=1]
//     M4 "~~s~~" → ["s" intent=32]
//     M4b "~s~" → ["s" intent=32]
//     M5 "`code`" → ["code" intent=4]
//     M6 "[link](https://x.org)" → ["link" link=https://x.org]
//     M7 "***bi***" → ["bi" intent=3]
//     M8a "# H" → ["# H"]
//     M8b "- a" → ["- a"]
//     M8c "1. a" → ["1. a"]
//     M8d "> q" → ["> q"]
//     M9 "\\*a\\*" → ["*a*"]
//     M12a "snake_case_name" → ["snake_case_name"]
//     M12b "a*b*c" → ["a"] ["b" intent=1] ["c"]
//     M12c "2 * 3 * 4" → ["2 * 3 * 4"]
//     M13 "a  b\nc" → ["a  b\nc"]
//     M15 "<https://x.org>" → ["https://x.org" link=https://x.org]
//     M15b "https://x.org" → ["https://x.org" link=https://x.org]
//     M16 "**a _b_**" → ["a " intent=2] ["b" intent=3]
//     M17 "**unclosed" → ["**unclosed"]
//     M18 "a&amp;b" → ["a&b"]
//     M19 "![alt](https://x.org/i.png)" → ["alt" image=https://x.org/i.png]
//     M20 "www.x.org" → ["www.x.org" link=http://www.x.org]
//     M21 "a@b.org" → ["a@b.org" link=mailto:a@b.org]
//     M22 "[**b**](https://x.org)" → ["b" link=https://x.org]
//     M23 "&#65;&copy;" → ["A©"]
//     M24 "a\\\nb" → ["a"] ["\n" intent=128] ["b"]
//     M25 "`**x**`" → ["**x**" intent=4]
//     M26 "http://x.org/a_b_c" → ["http://x.org/a_b_c" link=http://x.org/a_b_c]
//     M27 "__b__" → ["b" intent=2]
//     M28 "[a](relative/path)" → ["a" link=relative/path]
//     N1 "<b>x</b>" → ["<b>" intent=256] ["x"] ["</b>" intent=256]
//     N2 "[a][r]" → ["[a][r]"]
//     N3 "a  \nb" → ["a  \nb"]
//     N4 "[a](<u v>)" → ["a" link=u%20v]
//     N5 "[a](u \"t\")" → ["a" link=u]
//     N6 "``a`b``" → ["a`b" intent=4]
//     N7 "*a **b** c*" → ["a " intent=1] ["b" intent=3] [" c" intent=1]
//     N8 "**a*" → ["*"] ["a" intent=1]
//     N9 "_a_b" → ["_a_b"]
//     N10 "(www.x.org)" → ["("] ["www.x.org" link=http://www.x.org] [")"]
//     N11 "https://x.org." → ["https://x.org" link=https://x.org] ["."]
//     N12 "&bogus;" → ["&bogus;"]
//     N13 "&nbsp;x" → [" x"]
//     N14 "\\`" → ["`"]
//     N15 "~~~a~~~" → ["~~~a~~~"]
//     N16 "[a]" → ["[a]"]
//     N17 "a\tb" → ["a\tb"]
//     N18 "`` a ``" → ["a" intent=4]
//     N19 "*a*b*" → ["a" intent=1] ["b*"]
//     N20 "x_y_ z" → ["x_y_ z"]
//     N21 "&alpha;&hearts;&ThickSpace;" → ["α♥  "]

#if LINUX_PROBE
import Foundation
struct MColor: Hashable, Sendable { var r: Double; static let red = MColor(r: 1) }
extension AttributeScopes {
    struct ProbeAttributes: AttributeScope {
        let foregroundColor: ForegroundColorAttribute
        let foundation: AttributeScopes.FoundationAttributes
        enum ForegroundColorAttribute: AttributedStringKey {
            typealias Value = MColor
            static let name = "Probe.foregroundColor"
        }
    }
}
extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.ProbeAttributes, T>) -> T {
        self[T.self]
    }
}
var a = AttributedString("hello world")
a[a.range(of: "world")!].foregroundColor = .red
a.link = URL(string: "https://x.org")
for run in a.runs {
    print("L1 run \(String(a[run.range].characters).debugDescription) foreground=\(run.foregroundColor as Any) link=\(run.link as Any)")
}
#else
import Foundation

let corpus: [(String, String)] = [
    ("M1", "**b**"), ("M3a", "*i*"), ("M3b", "_i_"), ("M4", "~~s~~"), ("M4b", "~s~"), ("M5", "`code`"),
    ("M6", "[link](https://x.org)"), ("M7", "***bi***"), ("M8a", "# H"), ("M8b", "- a"), ("M8c", "1. a"),
    ("M8d", "> q"), ("M9", "\\*a\\*"), ("M12a", "snake_case_name"), ("M12b", "a*b*c"), ("M12c", "2 * 3 * 4"),
    ("M13", "a  b\nc"), ("M15", "<https://x.org>"), ("M15b", "https://x.org"), ("M16", "**a _b_**"),
    ("M17", "**unclosed"), ("M18", "a&amp;b"), ("M19", "![alt](https://x.org/i.png)"), ("M20", "www.x.org"),
    ("M21", "a@b.org"), ("M22", "[**b**](https://x.org)"), ("M23", "&#65;&copy;"), ("M24", "a\\\nb"),
    ("M25", "`**x**`"), ("M26", "http://x.org/a_b_c"), ("M27", "__b__"), ("M28", "[a](relative/path)"),
    ("N1", "<b>x</b>"), ("N2", "[a][r]"), ("N3", "a  \nb"), ("N4", "[a](<u v>)"), ("N5", "[a](u \"t\")"),
    ("N6", "``a`b``"), ("N7", "*a **b** c*"), ("N8", "**a*"), ("N9", "_a_b"), ("N10", "(www.x.org)"),
    ("N11", "https://x.org."), ("N12", "&bogus;"), ("N13", "&nbsp;x"), ("N14", "\\`"), ("N15", "~~~a~~~"),
    ("N16", "[a]"), ("N17", "a\tb"), ("N18", "`` a ``"), ("N19", "*a*b*"), ("N20", "x_y_ z"),
    ("N21", "&alpha;&hearts;&ThickSpace;"),
]

let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
for (id, source) in corpus {
    do {
        let parsed = try AttributedString(markdown: source, options: options)
        let runs = parsed.runs.map { run -> String in
            var parts = [String(parsed[run.range].characters).debugDescription]
            if let intent = run.inlinePresentationIntent { parts.append("intent=\(intent.rawValue)") }
            if let link = run.link { parts.append("link=\(link.absoluteString)") }
            if let image = run.imageURL { parts.append("image=\(image.absoluteString)") }
            return "[" + parts.joined(separator: " ") + "]"
        }
        print("\(id) \(source.debugDescription) → \(runs.joined(separator: " "))")
    } catch {
        print("\(id) \(source.debugDescription) → throws \(error)")
    }
}
#endif
