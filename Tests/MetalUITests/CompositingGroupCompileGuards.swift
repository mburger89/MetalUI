import Testing
import MetalUITestSupport

// C13 / PERF-a, lane 2 guard (ruling `PF-E`; spec
// `2026-10-09-shadow-cache-design.md` §8, "Guard"). The fixture compiles
// against a PLAIN `import MetalUI` as whole-file Swift 6 (`typecheckFile`,
// ruling SA-P), so it can fail only for its spellings.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `COMPOSITING GROUP GUARD` to know it
// ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **L2.G** (`PF-E` item 2) — `compositingGroup()` is spellable from outside
/// the module on both vocabularies, chained before a shadow and a blur: a
/// proposal view, a proposal chain, and a legacy `Box` (returning `Self`, so a
/// legacy decoration still follows it). The control writes `.drawingGroup()`,
/// which is not built (divergence row of `GX-A`'s deferred list) and must not
/// compile.
///
/// Mutation that reddened it once (record §90; native build, full suite over
/// `ab65ef3`'s sources): the LEGACY `StyledElement.compositingGroup()` declared
/// `internal` — the positive arm read `succeeded=false` and this test failed.
/// (The proposal spelling cannot be narrowed alone: `MetalUIDemoContent`'s
/// LooksDemo spells it, so the package stops building.)
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func compositingGroupIsSpellableOnBothVocabularies() throws {
    func source(_ member: String) -> String {
        """
        public struct Grouped: Component {
            public init() {}
            public var content: some ElementGroup {
                VStack {
                    Circle().fill(.red).\(member)().shadow(radius: Pixels(4))
                    Text("pair").padding(Pixels(4)).\(member)().blur(radius: Pixels(2))
                }
                Box().background(.surface).\(member)().shadow(radius: Pixels(3)).cornerRadius(Pixels(4))
            }
        }
        """
    }
    let positive = try typecheckFile(source("compositingGroup"), importing: "MetalUI")
    print("COMPOSITING GROUP GUARD L2.G positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let control = try typecheckFile(source("drawingGroup"), importing: "MetalUI")
    print("COMPOSITING GROUP GUARD L2.G control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "compositingGroup() must be spellable outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "drawingGroup() is not built and must not compile:\n\(control.output)")
}
