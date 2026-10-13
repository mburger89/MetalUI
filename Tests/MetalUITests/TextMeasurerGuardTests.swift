import Testing
import MetalUITestSupport

// C23 lane 1, guard 1.11 (`GT-D`): what an external module may write about the
// measurer. Whole-file Swift 6 against a PLAIN import (`typecheckFile`,
// ruling SA-P). Grep the log for `GT GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **1.11 — the measurer has no public initialiser and no setter.** The positive
/// arm reads and measures; the controls construct one and write the property.
/// Mutation that must redden it: the property made settable (or an initialiser
/// made public).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theMeasurerHasNoPublicInitialiserAndNoSetter() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings(env: EnvironmentValues) -> Size<Pixels> {
            let resolved = env.textMeasurer.resolve(Text("x"))
            _ = env.textMeasurer.resolve(ProposalText("x"))
            return resolved.measure(in: Size(width: Pixels.infinity, height: Pixels.infinity))
        }
        """, importing: "MetalUI")
    print("GT GUARD 1.11 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let construct = try typecheckFile("""
        @MainActor public func bad() { _ = TextMeasurer() }
        """, importing: "MetalUI")
    let write = try typecheckFile("""
        @MainActor public func bad(env: inout EnvironmentValues, m: TextMeasurer) { env.textMeasurer = m }
        """, importing: "MetalUI")
    print("GT GUARD 1.11 construct: succeeded=\(construct.succeeded) write: succeeded=\(write.succeeded)")
    try #require(positive.succeeded != construct.succeeded && positive.succeeded != write.succeeded,
                 "the arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(construct.output)")
    #expect(positive.succeeded, "the reading spellings must compile:\n\(positive.output)")
    #expect(!construct.succeeded, "TextMeasurer has no public initialiser")
    #expect(!write.succeeded, "textMeasurer is get-only")
}
