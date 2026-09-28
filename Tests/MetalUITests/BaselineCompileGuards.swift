import Testing
import MetalUITestSupport

// Compile-time guard for plan task 11 part 1, lane 2 (spec row G2.1; ruling
// TE-K item 1): `VerticalAlignment` has SwiftUI's two text baselines and
// `HorizontalAlignment` none. Whole-file, Swift 6, a PLAIN `import MetalUI`,
// as an app writes it (`SA-P`; practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1.** `HStack(alignment: .firstTextBaseline)` and `.lastTextBaseline`
/// compile, and so does `GridRow(alignment: .firstTextBaseline)` (it traps at
/// run time instead, divergence 88 — the parameter is SwiftUI's
/// `VerticalAlignment`). **Positive control**: `VStack(alignment:
/// .firstTextBaseline)` fails, since `HorizontalAlignment` has no baseline in
/// SwiftUI either.
///
/// Mutation: **MG2** `firstTextBaseline` added to `HorizontalAlignment` — the
/// control compiles and the guard reddens (record §59 §3).
@MainActor
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aTextBaselineIsAVerticalAlignmentButNotAHorizontalOne() throws {
    let uses = """
        @MainActor
        func use() {
            _ = HStack(alignment: .firstTextBaseline) { Spacer() }
            _ = HStack(alignment: .lastTextBaseline, spacing: Pixels(4)) { Spacer() }
            _ = Grid { GridRow(alignment: .firstTextBaseline) { Spacer() } }
            let cases: [VerticalAlignment] = [.top, .center, .bottom, .firstTextBaseline, .lastTextBaseline]
            _ = cases
        }
        """
    let control = """
        @MainActor
        func use() {
            _ = VStack(alignment: .firstTextBaseline) { Spacer() }
        }
        """
    let positive = try typecheckFile(uses, importing: "MetalUI")
    let negative = try typecheckFile(control, importing: "MetalUI")
    print("""
        TE-K baseline alignment: positive succeeded=\(positive.succeeded) messages=[\(positive.messages)]; \
        control succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(!negative.succeeded, "the control must fail, or this guard cannot: \(negative.messages)")
    #expect(negative.messages.contains("firstTextBaseline"),
            "the control fails for the missing case: \(negative.messages)")
    #expect(positive.succeeded, "the text baselines must be spellable from a plain import: \(positive.messages)")
}
