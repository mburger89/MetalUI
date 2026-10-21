import Testing
import MetalUITestSupport

// Lazy containers, lane 1, guards G.1 and G.2 (rulings `LZ-A`, `LZ-N`; spec section 5).
// Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import: a `@testable` test cannot
// prove what an external module can spell. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for `LZ-A spellings`
// and `LZ-B seam` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found - guard skipped"

/// **G.1** (`LZ-A`, `LZ-N`). SwiftUI's lazy stack spellings typecheck from an external module
/// (the control arm: `alignment:`, `spacing:` and a trailing builder on both stacks), and
/// `pinnedViews:` does not: it is not offered. Mutation **MG.1**: add a `pinnedViews:` parameter to
/// `LazyVStack.init` (the second arm now compiles and the first message check fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func lazyInitHasNoPinnedViewsParameter() throws {
    let spellings = try typecheckFile("""
        @MainActor func tree() -> some Element {
            ProposalScrollView {
                LazyVStack(alignment: .leading, spacing: Pixels(4)) {
                    ForEach(0..<3) { index in Text("\\(index)") }
                }
                LazyHStack(alignment: .top) { Text("a"); Text("b") }
                LazyVStack { Text("c") }
            }
        }
        """, importing: "MetalUI")
    print("LZ-A spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]")
    #expect(spellings.succeeded, "the lazy stack spellings must compile:\n\(spellings.output)")

    let pinned = try typecheckFile("""
        @MainActor func tree() -> some Element {
            LazyVStack(pinnedViews: []) { Text("a") }
        }
        """, importing: "MetalUI")
    #expect(!pinned.succeeded, "pinnedViews: is not offered (LZ-N):\n\(pinned.output)")
    #expect(pinned.messages.contains("extra arguments at positions #1, #2 in call"),
            "rejected, but not for the extra argument:\n\(pinned.output)")
}

/// **G.2** (`LZ-B`, `LZ-C`). The lazy core's seam is unreachable outside the module: the unit source
/// protocol, the origin state and the unit box. Mutation **MG.2**: make `LazyOrigin` `public` (its
/// line stops failing and the message check fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theLazyCoreIsUnreachableOutsideTheModule() throws {
    for name in ["LazyUnitSource", "LazyOrigin", "LazyUnitBox", "LazyLinePlanner", "LazyWork"] {
        let result = try typecheckFile("""
            @MainActor func reach() { _ = \(name).self }
            """, importing: "MetalUI")
        print("LZ-B seam \(name): succeeded=\(result.succeeded)")
        #expect(!result.succeeded, "\(name) must not be spellable outside MetalUI:\n\(result.output)")
        #expect(result.messages.contains("cannot find '\(name)' in scope"),
                "\(name) rejected, but not as an unknown name:\n\(result.output)")
    }
}
