import Testing
import MetalUITestSupport

// Lazy containers, lane 2, guard G.3 (rulings `LZ-A`, `LZ-N`, `LZ-W`; spec section 5). Whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import: a `@testable` test cannot prove what an external
// module can spell. **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md,
// "Guards"); grep the log for `LZ-A grid spellings` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found - guard skipped"

/// **G.3** (`LZ-A`, `LZ-N`, `LZ-W`). SwiftUI's lazy grid spellings typecheck from an external module
/// (`GridItem(.adaptive(minimum:))`, `GridItem(.flexible(minimum:maximum:), spacing:, alignment:)`,
/// `.fixed`, `LazyVGrid(columns:alignment:spacing:)`, `LazyHGrid(rows:...)`), `GridItem`'s members read back,
/// and `pinnedViews:` is not offered on either grid. Mutation **MG.3**: rename `LazyVGrid`'s `columns:` to
/// `items:` (the first arm fails), and add `pinnedViews:` to `LazyHGrid.init` (the second arm's message
/// check fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func gridItemAndTheLazyGridsHaveSwiftUIsSpellings() throws {
    let spellings = try typecheckFile("""
        @MainActor func tree() -> some Element {
            ProposalScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], alignment: .leading, spacing: 12) {
                    ForEach(0..<3) { index in Text("\\(index)") }
                }
                LazyVGrid(columns: [GridItem(.fixed(30), spacing: 4, alignment: .topLeading),
                                    GridItem(.flexible(minimum: 20, maximum: 60), spacing: 6, alignment: .bottomTrailing),
                                    GridItem(.adaptive(minimum: 30, maximum: 80))]) {
                    Text("a")
                }
                LazyHGrid(rows: [GridItem(.flexible()), GridItem()], alignment: .top, spacing: 8) { Text("b") }
            }
        }
        @MainActor func members(_ item: GridItem) -> (GridItem.Size, Pixels?, ProposalAlignment?) {
            (item.size, item.spacing, item.alignment)
        }
        """, importing: "MetalUI")
    print("LZ-A grid spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]")
    #expect(spellings.succeeded, "the lazy grid spellings must compile:\n\(spellings.output)")

    for source in ["LazyVGrid(columns: [], pinnedViews: []) { Text(\"a\") }",
                   "LazyHGrid(rows: [], pinnedViews: []) { Text(\"a\") }"] {
        let pinned = try typecheckFile("""
            @MainActor func tree() -> some Element { \(source) }
            """, importing: "MetalUI")
        #expect(!pinned.succeeded, "pinnedViews: is not offered (LZ-N):\n\(pinned.output)")
        #expect(pinned.messages.contains("extra arguments at positions #2, #3 in call"),
                "rejected, but not for the extra argument:\n\(pinned.output)")
    }
}
