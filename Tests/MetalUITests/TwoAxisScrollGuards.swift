import Testing
import MetalUITestSupport

// Alloy gap G5, PR 2, ruling `XS-A`. Whole-file Swift 6 against a PLAIN import (`typecheckFile`, ruling SA-P): what an external
// module may write. **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log
// for `XS GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **X7 — every spelling of the scroll axes compiles outside the module, with no ambiguity.** `ScrollView(.horizontal)` and
/// `ScrollView {}` keep resolving to the ``ScrollAxis`` initialiser (stop condition 3: the `Axis.Set` one is
/// `@_disfavoredOverload`), an array literal, a set value and `[]` resolve to `Axis.Set`, the four `ProposalScrollView` twins do
/// the same, and `axes` / `axis` read. The control asks for a `ScrollAxis` out of `axes`, which must not typecheck, and is
/// `#require`d to disagree with the positive arm first.
///
/// Mutation that must redden it: `@_disfavoredOverload` removed from the `Axis.Set` initialiser (an ambiguity error at
/// `ScrollView(.horizontal)`).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func everySpellingOfTheScrollAxesCompilesFromAPlainImport() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() {
            _ = ScrollView(.horizontal) { Box() }
            _ = ScrollView { Box() }
            _ = ScrollView(.vertical, elementID: nil) { Box() }
            _ = ScrollView([.horizontal, .vertical]) { Box() }
            let a: Axis.Set = .vertical
            _ = ScrollView(a) { Box() }
            _ = ScrollView([]) { Box() }
            _ = ScrollView(Axis.Set.horizontal) { Box() }
            _ = ProposalScrollView(.horizontal) { Spacer() }
            _ = ProposalScrollView { Spacer() }
            _ = ProposalScrollView([.horizontal, .vertical]) { Spacer() }
            _ = ProposalScrollView(a) { Spacer() }
            _ = ProposalScrollView([]) { Spacer() }
            let both = ScrollView([.horizontal, .vertical]) { Box() }
            let axes: Axis.Set = both.axes
            let axis: ScrollAxis = ScrollView(.horizontal) { Box() }.axis
            let proposal: Axis.Set = ProposalScrollView(a) { Spacer() }.axes
            _ = (axes, axis, proposal)
        }
        """, importing: "MetalUI")
    print("XS GUARD X7 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let control = try typecheckFile("""
        @MainActor public func bad() {
            let _: ScrollAxis = ScrollView([.horizontal, .vertical]) { Box() }.axes
        }
        """, importing: "MetalUI")
    print("XS GUARD X7 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "every spelling must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "axes is an Axis.Set, not a ScrollAxis:\n\(control.output)")
}
