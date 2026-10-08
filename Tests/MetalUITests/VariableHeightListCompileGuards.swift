import Testing
import MetalUITestSupport

// Variable-height `List`, guard 2.19 (ruling `VL-A`; spec
// `docs/superpowers/specs/2026-10-08-variable-height-list-design.md` §5).
// Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import — a
// `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `VL-A spellings` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **2.19** (`VL-A`, probe `S1`). SwiftUI's `List` spellings typecheck from an
/// external module: `List(items) { … }`, `List(items, selection: $one) { … }`
/// (an optional id), `List(items, selection: $many) { … }` (a set),
/// `List(items, estimatedRowHeight: 40) { … }` and the labelled
/// `List(items, rowContent: { … })` — beside the uniform
/// `List(items, rowHeight: 28) { … }`, unchanged.
///
/// Mutation **MG2.19**: rename the new initialisers' `rowContent:` label to
/// `content:` (the labelled spelling fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theVariableListSpellingsCompileFromAPlainImport() throws {
    let result = try typecheckFile("""
        struct Item: Identifiable { let id: Int }
        @MainActor func tree(_ items: [Item], _ one: Binding<Int?>, _ many: Binding<Set<Int>>) -> some Element {
            ScrollView {
                Column {
                    List(items) { item in Text("\\(item.id)") }
                    List(items, selection: one) { item in Text("\\(item.id)") }
                    List(items, selection: many) { item in Text("\\(item.id)") }
                    List(items, estimatedRowHeight: Pixels(40)) { item in Text("\\(item.id)") }
                    List(items, selection: many, estimatedRowHeight: Pixels(40)) { item in Text("\\(item.id)") }
                    List(items, rowContent: { item in Text("\\(item.id)") })
                    List(items, rowHeight: Pixels(28)) { item in Text("\\(item.id)") }
                }
            }
        }
        """, importing: "MetalUI")
    print("VL-A spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "every variable List spelling must compile:\n\(result.output)")
}
