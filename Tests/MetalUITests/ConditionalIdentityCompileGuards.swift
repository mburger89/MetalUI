import Testing
import MetalUITestSupport

// Plan task 8, lane 2, guard G2.1 (ruling `ID-D`). Whole-file Swift 6 against a
// PLAIN `import MetalUI` (`typecheckFile`, ruling SA-P): what an external module
// may write inside a proposal container.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `CONDITIONAL GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1 — an `if`/`else` and a `switch` compile in every proposal container.**
/// `EitherGroup: ProposalElementGroup` when both branches are (`ID-D`), so an
/// `if`/`else` and a three-case `switch` (nested `EitherGroup`s) are proposal
/// content inside `HStack`, `VStack`, `ZStack`, `Grid`, `GridRow` and a proposal
/// `.overlay`'s content. The control — legacy content in the branches,
/// `HStack { if f { Box() } else { Box() } }` — must still be rejected, and the
/// two arms are `#require`d to disagree first, so a fixture broken for an
/// unrelated reason cannot pass.
///
/// Red before: the positive does not compile (`generic struct 'HStack' requires
/// that 'EitherGroup<Rectangle, Rectangle>' conform to 'ProposalElementGroup'`).
/// Mutation that must redden it: delete the conformance.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anIfElseAndASwitchCompileInEveryProposalContainer() throws {
    let positive = try typecheckFile("""
        public enum Three: Sendable { case a, b, c }

        @MainActor public func stacks(_ f: Bool, _ t: Three) {
            _ = HStack { if f { Rectangle() } else { Rectangle() } }
            _ = VStack { if f { Rectangle() } else { Rectangle() } }
            _ = ZStack { if f { Rectangle() } else { Rectangle() } }
            _ = HStack {
                switch t {
                case .a: Rectangle()
                case .b: Rectangle()
                case .c: Rectangle()
                }
            }
            _ = VStack {
                switch t {
                case .a: Rectangle()
                case .b: Rectangle()
                case .c: Rectangle()
                }
            }
        }

        @MainActor public func grids(_ f: Bool, _ t: Three) {
            _ = Grid {
                if f { GridRow { Rectangle() } } else { GridRow { Rectangle() } }
                GridRow {
                    if f { Rectangle() } else { Rectangle() }
                    switch t {
                    case .a: Rectangle()
                    case .b: Rectangle()
                    case .c: Rectangle()
                    }
                }
            }
        }

        @MainActor public func overlays(_ f: Bool) {
            _ = HStack {
                Rectangle().overlay { if f { Rectangle() } else { Rectangle() } }
            }
        }
        """, importing: "MetalUI")
    print("CONDITIONAL GUARD G2.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let control = try typecheckFile("""
        @MainActor public func bad(_ f: Bool) {
            _ = HStack { if f { Box() } else { Box() } }
        }
        """, importing: "MetalUI")
    print("CONDITIONAL GUARD G2.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "if/else and switch must compile in every proposal container:\n\(positive.output)")
    #expect(!control.succeeded, "legacy branches must not enter a proposal container:\n\(control.output)")
}
