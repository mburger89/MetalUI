import Testing
import MetalUITestSupport

// Plan task 10, part 2, lane 3, guard G3.1 (rulings `DD-Z`, `DD-AA`). The
// fixture compiles against a PLAIN `import MetalUI` — this file's own imports
// are irrelevant (shape 16) — as whole-file Swift 6 (`typecheckFile`, ruling
// SA-P), so it can fail only for its spelling.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `SELECTION GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G3.1 — the lane-3 spellings compile from outside the module** (spec §3):
/// `List(_:selection:rowHeight:row:)` over a `@State` projection of an optional
/// id and of a `Set` of ids, and `ForEach($items) { $item in … }` over a
/// `MutableCollection` of `Identifiable` elements, writing through the element
/// binding's key path. The control passes a plain `Set` where the set binding
/// goes.
///
/// Mutation that must redden it (MG3.1): the `Set` initialiser made internal.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSelectionAndBindingForEachSpellingsCompileFromOutsideTheModule() throws {
    func source(_ many: String) -> String {
        """
        public struct Chore: Identifiable {
            public var id: Int
            public var done: Bool
        }
        public struct Chores: Component {
            @State var chores = [Chore(id: 0, done: false), Chore(id: 1, done: true)]
            @State var one: Int? = nil
            @State var many: Set<Int> = []
            public init() {}
            public var content: some ElementGroup {
                ScrollView {
                    List(chores, selection: $one, rowHeight: Pixels(20)) { chore in Text("\\(chore.id)") }
                    List(chores, selection: \(many), rowHeight: Pixels(20)) { chore in Text("\\(chore.id)") }
                }
                Column {
                    ForEach($chores) { $chore in
                        Toggle("Chore \\(chore.id)", isOn: $chore.done)
                    }
                }
            }
        }
        """
    }
    let positive = try typecheckFile(source("$many"), importing: "MetalUI")
    print("SELECTION GUARD G3.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let control = try typecheckFile(source("many"), importing: "MetalUI")
    print("SELECTION GUARD G3.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the SwiftUI spellings must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "a plain Set is not a binding:\n\(control.output)")
}
