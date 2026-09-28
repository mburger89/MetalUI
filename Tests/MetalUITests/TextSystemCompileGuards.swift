import Testing
import MetalUITestSupport

// Compile-time guards for plan task 11 part 1's text seam
// (`docs/superpowers/specs/2026-09-28-text-semantics-design.md` §4, §8 lane 1,
// G1.1; ruling `TE-C`). Whole-file, Swift 6, a PLAIN `import MetalUITextSystem`,
// as a backend or an app writes it (`SA-P`; practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUITextSystem not found — guard skipped"

/// **G1.1.** The seam's new spellings are public — `TextLayoutOptions`'
/// initialiser and its enums, `fontMetrics`, and `measure`/`placeGlyphs`/
/// `lineRanges` with `options:` — and the spellings every caller used before
/// ruling TE-C still compile (the protocol extension). **Positive control**:
/// a truncation mode the seam does not have (`.ellipsis`) fails, so the file
/// is typechecked against the real declarations, not waved through.
///
/// Mutation: **MG1** `TextLayoutOptions.init` made `internal` (the positive
/// fixture stops compiling).
@MainActor
@Test(.enabled(if: canTypecheck(module: "MetalUITextSystem"), skipReason))
func theSeamsNewSpellingsArePublicAndTheOldOnesStillCompile() throws {
    let uses = """
        @MainActor
        func use(_ system: some TextSystem, _ font: FontKey) {
            let options = TextLayoutOptions(maxLines: 2, truncation: .middle, alignment: .trailing)
            let _: TextLayoutOptions = TextLayoutOptions()
            let _: TextFontMetrics = system.fontMetrics(font)
            let _: TextMeasurement = system.measure("a", font: font, wrappingAt: 10, options: options)
            let _: TextMeasurement = system.measure("a", font: font, wrappingAt: nil)
            let _: [TextGlyph] = system.placeGlyphs("a", font: font, wrappingAt: 10, options: options,
                                                    origin: (0, 0), scaleFactor: 2)
            let _: [TextGlyph] = system.placeGlyphs("a", font: font, wrappingAt: nil, origin: (0, 0), scaleFactor: 1)
            let _: [Range<Int>] = system.lineRanges("a", font: font, wrappingAt: 10, options: options)
            let _: [Range<Int>] = system.lineRanges("a", font: font, wrappingAt: nil)
            let _: [TextTruncation] = [.tail, .head, .middle]
            let _: [TextLineAlignment] = [.leading, .center, .trailing]
            let metrics = TextFontMetrics(ascent: 1, descent: 1, leading: 0, lineHeight: 2)
            _ = (metrics.ascent, metrics.descent, metrics.leading, metrics.lineHeight)
        }
        """
    let control = "let _ = TextLayoutOptions(truncation: .ellipsis)"
    let positive = try typecheckFile(uses, importing: "MetalUITextSystem")
    let negative = try typecheckFile(control, importing: "MetalUITextSystem")
    print("""
        TE-C seam spellings: positive succeeded=\(positive.succeeded) messages=[\(positive.messages)]; \
        control succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(!negative.succeeded, "the control must fail, or this guard cannot: \(negative.messages)")
    #expect(negative.messages.contains("ellipsis"), "the control fails for the missing case: \(negative.messages)")
    #expect(positive.succeeded, "the seam's spellings must compile from a plain import: \(positive.messages)")
}
