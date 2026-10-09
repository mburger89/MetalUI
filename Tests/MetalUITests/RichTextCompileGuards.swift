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
/// function); and three spellings do **not** compile — a `+` whose operand is
/// an environment scope (`lineLimit` on `Text` is a view modifier), a dashed
/// pattern, and `Text.LineStyle.Pattern.dash` (only `.solid` is offered,
/// `C10d`). Red before: none of it existed. Mutations: **MG2.24a** declare a
/// `dash` pattern (the two dash arms), **MG2.24b** a `+` taking an
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
        ("underline(pattern: .dash)", """
            @MainActor public func probe() -> Text { Text("a").underline(pattern: .dash) }
            """, "dash"),
        ("Text.LineStyle.Pattern.dash", """
            public func probe() -> Text.LineStyle.Pattern { Text.LineStyle.Pattern.dash }
            """, "dash"),
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
