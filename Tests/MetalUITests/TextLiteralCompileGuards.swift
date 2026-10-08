import Testing
import MetalUITestSupport

// Rich text, lane 3 — what an external module can write with a string
// literal, an interpolation and an attributed string (spec §4.3 tests 3.10,
// 3.12; rulings RT-C, RT-D, `RT-O` items 5–6). `typecheckFile` with a plain
// `import MetalUI` (`SA-P`). **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the
// log for `RT GUARD 3.` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **3.10** (ruling RT-C item 2, `RT-O` items 5–6, divergence 156). SwiftUI's
/// three initialisers: a literal (and a literal with a Unicode escape, which
/// `AttributedString`'s own literal conformance would make ambiguous), a
/// substring, `verbatim:`, an interpolation of a `Double` and a `Text`, a
/// `LocalizedStringKey` literal, `ProposalText`'s three; and an interpolated
/// value of a type with no dedicated overload compiles **with no warning**
/// (SwiftUI deprecates it, `I1`/`I2`). An interpolated `Image` compiles
/// **with a deprecation warning naming the absence** (`I4`; `Text(Image)` is
/// deferred) and traps at run time (3.10b): an `@available(*, unavailable)`
/// overload loses to the generic one and the image's description would be
/// written silently — the red stub's spelling, which compiled with no message
/// (ruling RT-T item 1). Red before: the Image arm (unavailable stub).
/// Mutations **MG3.10a** remove `@_disfavoredOverload`
/// from `init<S>` (the literal arm turns ambiguous), **MG3.10b** deprecate the
/// generic interpolation (the no-warning arm), **MG3.10c** delete the
/// deprecated `Image` overload (the `Image` arm), **MG3.10d** remove
/// `@_disfavoredOverload` from `Text(_: AttributedString)` (the escape arm).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theInitialisersReachSwiftUIsOverloads() throws {
    let compiles = try typecheckFile("""
        public struct Plain {}
        @MainActor public func initialisers() {
            let literal: Text = Text("lit")
            let escaped: Text = Text(" \\u{2304}")
            let substring: Text = Text("abc".dropFirst())
            let value = "**v**"
            let fromValue: Text = Text(value)
            let verbatim: Text = Text(verbatim: "**a**")
            let interpolated: Text = Text("n \\(1.5) \\(Text("b").bold())")
            let key: LocalizedStringKey = "x"
            let fromKey: Text = Text(key)
            let described: Text = Text("v \\(Plain())")
            let proposal: ProposalText = ProposalText("**lit**")
            let proposalValue: ProposalText = ProposalText(value)
            let proposalVerbatim: ProposalText = ProposalText(verbatim: value)
            _ = (literal, escaped, substring, fromValue, verbatim, interpolated, key, fromKey, described)
            _ = (proposal, proposalValue, proposalVerbatim)
        }
        """, importing: "MetalUI")
    print("RT GUARD 3.10 compiles: succeeded=\(compiles.succeeded) messages=[\(compiles.messages)]")
    // `messages` drops the severity markers, so "no warning" is "no message".
    #expect(compiles.succeeded && compiles.messages.isEmpty,
            "SwiftUI's spellings must compile with no warning:\n\(compiles.output)")

    let image = try typecheckFile("""
        @MainActor public func probe(_ image: Image) -> Text { Text("v \\(image)") }
        """, importing: "MetalUI")
    print("RT GUARD 3.10 warns on an interpolated Image: succeeded=\(image.succeeded) messages=[\(image.messages)]")
    #expect(image.succeeded && image.messages.contains("is deprecated: interpolating an Image into Text is not offered"),
            "an interpolated Image must warn, naming the absence (RT-T item 1):\n\(image.output)")
}

/// The attributed-string fixture of 3.12, under `imports`.
private func attributedFixture(_ imports: String) -> String {
    """
    \(imports)
    @MainActor public func probe() -> Text {
        var s = AttributedString("x")
        s.font = .body
        s.foregroundColor = .red
        s.backgroundColor = .yellow
        s.underlineStyle = .single
        s.strikethroughStyle = .single
        s.kern = 1
        s.tracking = 1
        s.baselineOffset = 1
        s.link = URL(string: "https://x.org")
        s.underlineStyle = Text.LineStyle(pattern: .solid, color: .red)
        return Text(s)
    }
    """
}

/// **3.12** (ruling RT-D item 3, `SA-P`). Every key of MetalUI's scope is
/// writable by its dynamic-member spelling from an external module — beside
/// Foundation (which names `AttributedString`; MetalUI does not re-export it,
/// `RT-T`) and again beside AppKit, whose scope declares the same names over
/// AppKit's types (probe `swift-attribute-scope-ambiguity`). Green on arrival:
/// the red commit already declared the scope with its per-key subscripts (a
/// guard, proven by its mutation). Mutation **MG3.12**: delete the per-key
/// `foregroundColor` subscript.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func everyAttributeKeyIsWritableWithAPlainImport() throws {
    for (arm, imports) in [("Foundation", "import Foundation"), ("AppKit", "import Foundation\nimport AppKit")] {
        let result = try typecheckFile(attributedFixture(imports), importing: "MetalUI")
        print("RT GUARD 3.12 \(arm): succeeded=\(result.succeeded) messages=[\(result.messages)]")
        #expect(result.succeeded && result.messages.isEmpty,
                "every key is writable beside \(arm):\n\(result.output)")
    }
}
