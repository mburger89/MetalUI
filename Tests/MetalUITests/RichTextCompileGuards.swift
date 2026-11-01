import Testing
import MetalUITestSupport

// Rich text, lane 2 — what an external module can write (spec §4.2 tests 2.24,
// 2.25; rulings RT-E, `RT-O` items 8–9). `typecheckFile` with a plain
// `import MetalUI` (`SA-P`): a `@testable` test cannot see an access level.
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `RT GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **2.24** (ruling RT-E items 3–4, `RT-O` item 8). SwiftUI's text modifiers
/// compose on `Text` and return `Text`: bold, underline with a colour and
/// SwiftUI's full `underline(_:pattern:color:)` spelling, kerning, tracking,
/// baseline offset, monospaced, `Font.monospaced()`, `+` (inside a deprecated
/// function); and one spelling does **not** compile — a `+` whose operand is
/// an environment scope (`lineLimit` on `Text` is a view modifier). The dashed
/// patterns compile since `TM-B` (`theLinePatternsAreSwiftUIs`). Red before: none
/// of it existed. Mutations: **MG2.24b** a `+` taking an
/// `EnvironmentScope<Text>` (the `lineLimit` arm), **MG2.24c** drop
/// `pattern:` from `underline` (the compiling arm).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theTextModifiersComposeAsSwiftUIs() throws {
    let compiles = try typecheckFile("""
        @available(*, deprecated, message: "the guard's own use of the deprecated +")
        @MainActor public func concatenated() -> Text {
            Text("a").bold().underline(color: .red).kerning(1) + Text("b")
        }
        @MainActor public func modifiers() {
            let font: Font = Font.body.monospaced()
            let full: Text = Text("a").underline(true, pattern: .solid, color: .red)
            let struck: Text = Text("a").strikethrough(false, pattern: .solid, color: nil)
            let spaced: Text = Text("a").tracking(1).baselineOffset(2).monospaced().bold(false)
            let verbatim: Text = Text(verbatim: "**a**")
            let substring: Text = Text("abc".dropFirst())
            let style: Text.LineStyle = Text.LineStyle(pattern: .solid, color: .red)
            let single: Text.LineStyle = .single
            let proposal: ProposalText = ProposalText("a").bold().underline().kerning(1).tracking(1)
                .baselineOffset(1).monospaced().strikethrough(color: .blue)
            _ = (font, full, struck, spaced, verbatim, substring, style, single, proposal)
        }
        """, importing: "MetalUI")
    print("RT GUARD 2.24 compiles: succeeded=\(compiles.succeeded) messages=[\(compiles.messages)]")
    #expect(compiles.succeeded && !compiles.messages.contains("warning"),
            "SwiftUI's spellings must compile with no warning:\n\(compiles.output)")

    let refusals: [(String, String, String)] = [
        ("a + over a lineLimit scope", """
            @available(*, deprecated, message: "the guard's own use of the deprecated +")
            @MainActor public func probe() -> Text { Text("a").lineLimit(1) + Text("b") }
            """, "'EnvironmentScope<Text>' to expected argument type 'Text'"),
    ]
    for (name, source, mention) in refusals {
        let result = try typecheckFile(source, importing: "MetalUI")
        print("RT GUARD 2.24 refuses \(name): succeeded=\(result.succeeded) messages=[\(result.messages)]")
        #expect(!result.succeeded && result.messages.contains(mention),
                "\(name) must not compile, for its own reason:\n\(result.output)")
    }
}

/// **2.25** (ruling RT-E item 1). `Text("a") + Text("b")` in an ordinary
/// function compiles with exactly one warning, SwiftUI's deprecation message.
/// Red before: no `+`. Mutation **MG2.25**: remove the `@available(*,
/// deprecated…)`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theConcatenationOperatorIsDeprecated() throws {
    let result = try typecheckFile("""
        @MainActor public func probe() -> Text { Text("a") + Text("b") }
        """, importing: "MetalUI")
    print("RT GUARD 2.25: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    let message = "'+' is deprecated: Use string interpolation on `Text` instead: `Text(\"Hello \\(name)\")`"
    #expect(result.succeeded, "the concatenation compiles:\n\(result.output)")
    #expect(result.messages.components(separatedBy: message).count - 1 == 1,
            "one deprecation warning with SwiftUI's message:\n\(result.output)")
}

/// **TM-1** (rulings `TM-A`, `TM-B`, `TM-F`). SwiftUI's declarations compile from a plain import:
/// all five `Text.LineStyle.Pattern`s, `underline`/`strikethrough` with a pattern on `Text`,
/// `ProposalText` and over a container (`View`'s), and the view-level `bold`, `italic`, `kerning`,
/// `tracking`, `baselineOffset`, `monospaced` over a container and over a `Button`. Red before:
/// `.dash` and the container spellings did not exist. Mutations: **MG-TM1a** make `Pattern.dot`
/// `internal` (the pattern arm), **MG-TM1b** drop `pattern:` from the container `underline` (the
/// container arm).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theLinePatternsAndViewLevelTextModifiersAreSwiftUIs() throws {
    let compiles = try typecheckFile("""
        @MainActor public func modifiers() {
            let patterns: [Text.LineStyle.Pattern] = [.solid, .dot, .dash, .dashDot, .dashDotDot]
            let style: Text.LineStyle = Text.LineStyle(pattern: .dashDot, color: .red)
            let text: Text = Text("a").underline(true, pattern: .dash, color: .red)
                .strikethrough(pattern: .dot)
            let proposal: ProposalText = ProposalText("a").underline(pattern: .dashDotDot)
                .strikethrough(true, pattern: .dash, color: nil)
            _ = (patterns, style, text, proposal)
            _ = Column { Text("a") }
                .bold().bold(false).italic().italic(false)
                .underline().underline(false).underline(true, pattern: .dash, color: .red)
                .strikethrough().strikethrough(true, pattern: .dot)
                .kerning(1).tracking(1).baselineOffset(2).monospaced().monospaced(false)
            _ = Button("b") {}.kerning(2).bold().underline(pattern: .dashDot)
        }
        """, importing: "MetalUI")
    print("TM GUARD 1 compiles: succeeded=\(compiles.succeeded) messages=[\(compiles.messages)]")
    #expect(compiles.succeeded && !compiles.messages.contains("warning"),
            "SwiftUI's spellings must compile with no warning:\n\(compiles.output)")
}
