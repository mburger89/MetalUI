import Testing
import MetalUICore
@testable import MetalUI

// Plan task 10, part 1, lane 1 (`docs/superpowers/specs/2026-09-25-data-and-scrolling-design.md`
// §4, rulings `DD-B`, `DD-C`, `DD-L`): `ForEach` over identified data, and the
// loop reset rule that retires divergence 74 for `ForEach` and `for` alike.
// SwiftUI's answers are probe arms F1–F10 of
// `docs/probes/swiftui-data-and-scrolling.swift` and S6 of
// `docs/probes/swiftui-scrollviewreader-scope.swift`.
//
// Every frame is driven through `Frame.render`, whose `stateTable.sweep()` is
// where the loop rule runs — a layout-only frame never resets.
//
// **Four minting copies note a loop** (`ArrayGroup`'s untyped and typed entries,
// `ForEach`'s untyped and typed entries): each test names the copy its mutation
// is applied to, and each copy is mutated on its own.
//
// State is read through `ConditionalCounter`/`ProposalConditionalCounter`
// (`ConditionalIdentityTests.swift`): a count that steps by `step` per frame, so
// a retained entry reads more than one step on a returning element's first
// frame back, and an adopted count differs from an own one when steps differ.

private let size = Size<Pixels>(width: Pixels(200), height: Pixels(100))
private let root = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func named(_ parent: GlobalElementID, _ name: String) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: 0, name: ElementID(name))
}

/// Renders `make(step)` for each step against one table, through `Frame.render`.
@MainActor
@discardableResult
private func render<Root: Element, Step>(_ steps: [Step], table: StateTable = StateTable(),
                                         _ make: (Step) -> Root) -> StateTable {
    for step in steps {
        var tree = make(step)
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    return table
}

// MARK: - The `for` loop's reset (`DD-C`): 1.12, 1.13

/// **1.12 — a `for` loop's NAMED iteration dropped at the tail starts fresh on
/// its return.** `Row { for x in xs { C.id(x) } }` over [a, b], [a], [a, b]: b
/// reads **1**, a reads 3.
///
/// A name nothing replaces is not departed by `ID-R` (its position is simply
/// not evaluated), so until `DD-C` b's entries were retained and handed back —
/// **red before: 2**. The loop rule's named-children half resets it.
/// Mutation **M1h** (the sweep's named-children half removed, the positional
/// half kept) reddens this.
@MainActor
@Test func aForLoopsNamedIterationDroppedAtTheTailStartsFreshOnReturn() {
    let reads = ConditionalReads()
    render([["a", "b"], ["a"], ["a", "b"]]) { xs in
        Row {
            for x in xs { ConditionalCounter(x, reads).id(x) }
        }
    }
    let loop = child(root, 0)
    #expect(reads.ids["b"] == child(named(loop, "b"), 0), "\(String(describing: reads.ids["b"]))")
    #expect(reads.values["b"] == 1, "the dropped named iteration starts fresh (2 is retention): \(reads.values)")
    #expect(reads.values["a"] == 3, "the surviving iteration keeps counting: \(reads.values)")
}

/// **1.13 — a `for` loop inside a PROPOSAL container resets its dropped tail.**
/// `HStack { for i in 0..<n { P } }`, n 2 → 1 → 2, goes through the TYPED
/// `ArrayGroup` copy (`ProposalElementGroup.swift`): iteration 1 reads **1**,
/// iteration 0 reads 3.
///
/// **Red before: 2** (the typed copy never reset either). Mutation **M1i** (the
/// typed `ArrayGroup` copy's `noteLoop` removed) reddens this test alone — the
/// untyped copy's tests go through `Row`.
@MainActor
@Test func aForLoopInsideAProposalContainerResetsItsDroppedTail() {
    let reads = ConditionalReads()
    let table = StateTable()
    for n in [2, 1, 2] {
        var tree = HStack(spacing: Pixels(0)) {
            for i in 0..<n { ProposalConditionalCounter("\(i)", reads) }
        }
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    let loop = child(root, 0)
    #expect(reads.ids["1"] == child(loop, 1), "\(String(describing: reads.ids["1"]))")
    #expect(reads.values["1"] == 1, "the dropped iteration starts fresh (2 is retention): \(reads.values)")
    #expect(reads.values["0"] == 3, "the surviving iteration keeps counting: \(reads.values)")
}
