import Testing
import MetalUITestSupport

// Plan task 12, part 1, lane 3, guard G3.1 (ruling `IX-J`). Whole-file Swift 6
// against a PLAIN `import MetalUI` (`typecheckFile`, ruling SA-P): what an
// external module may write with the focus-state surface.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `FOCUS STATE GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G3.1 — the `@FocusState` spellings compile from a plain import**: a
/// Boolean and an optional-enum `@FocusState` in a `Component`, read and
/// written, `.focused($flag)` and `.focused($field, equals: .a)` on a `Box`, a
/// `FocusState<Bool>.Binding` handed to a child. **Negative arm**: a
/// `@FocusState var count: Int` — neither `Bool` nor optional, so no
/// initialiser applies (SwiftUI's own two).
///
/// Mutation that must redden it (mutated red once, `IX-S`): one spelling made
/// `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theFocusStateSpellingsCompileFromAPlainImport() throws {
    let positive = try typecheckFile("""
        public enum Field: Hashable { case a, b }
        public struct Child: Component {
            let flag: FocusState<Bool>.Binding
            public var content: some ElementGroup { Box().focusable().focused(flag) }
        }
        public struct Form: Component {
            @FocusState var flag: Bool
            @FocusState var field: Field?
            public var content: some ElementGroup {
                Box().focusable().focused($flag)
                Box().focusable().focused($field, equals: .a)
                Child(flag: $flag)
                Box().onClick { flag = !flag; field = .b; $field.wrappedValue = nil }
            }
        }
        """, importing: "MetalUI")
    print("FOCUS STATE GUARD G3.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let integer = try typecheckFile("""
        public struct Counted: Component {
            @FocusState var count: Int
            public var content: some ElementGroup { Box() }
        }
        """, importing: "MetalUI")
    print("FOCUS STATE GUARD G3.1 negative: int=\(integer.succeeded)")
    try #require(positive.succeeded != integer.succeeded,
                 """
                 the arms must disagree, or the guard measures nothing:
                 \(positive.output)
                 \(integer.output)
                 """)
    #expect(positive.succeeded, "every focus-state spelling must compile from a plain import:\n\(positive.output)")
    #expect(!integer.succeeded, "a non-Bool, non-optional FocusState has no initialiser:\n\(integer.output)")
}
