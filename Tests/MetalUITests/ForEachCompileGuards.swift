import Testing
import MetalUITestSupport

// Plan task 10, part 1, lane 1, guards G1.1–G1.2 (ruling `DD-B`). Whole-file
// Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`, ruling SA-P): what an
// external module may write with `ForEach`.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `FOREACH GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.1 — an external module can write `ForEach` over Identifiable data, a
/// key path and a range, in a legacy and a proposal container.** SwiftUI's three
/// initialisers (`DD-B` item 1). The control misspells the range initialiser's
/// argument type (a `ClosedRange`, which SwiftUI's range initialiser does not
/// take either), and the two arms are `#require`d to disagree first.
///
/// Mutation that must redden it: the `Range` initialiser made `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anExternalModuleCanWriteForEachOverIdentifiableKeyPathAndRangeData() throws {
    let positive = try typecheckFile("""
        public struct Person: Identifiable, Sendable { public let id: Int; public let name: String }

        @MainActor public func legacy(_ people: [Person], _ names: [String]) {
            _ = Column {
                ForEach(people) { person in Text(person.name) }
                ForEach(names, id: \\.self) { name in Text(name) }
                ForEach(0..<3) { i in Text("\\(i)") }
            }
        }

        @MainActor public func proposal(_ people: [Person], _ names: [String]) {
            _ = HStack {
                ForEach(people) { _ in Rectangle() }
                ForEach(names, id: \\.self) { _ in Rectangle() }
                ForEach(0..<3) { _ in Rectangle() }
            }
        }
        """, importing: "MetalUI")
    print("FOREACH GUARD G1.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let control = try typecheckFile("""
        @MainActor public func bad() {
            _ = HStack { ForEach(0...3) { _ in Rectangle() } }
        }
        """, importing: "MetalUI")
    print("FOREACH GUARD G1.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "all three initialisers must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "a closed range has no initialiser:\n\(control.output)")
}

/// **G1.2 — a `ForEach` of legacy content does not compile inside a proposal
/// stack.** `ForEach` is a `ProposalElementGroup` only when its content is
/// (`DD-B` item 1), so `HStack { ForEach([1, 2], id: \.self) { _ in Box() } }`
/// is a compile error, not an `SA-G` trap. The control is the same `ForEach`
/// over `Rectangle()`. Both arms use the `id:` key-path initialiser, not the
/// `Range` one, so G1.1's mutation (the `Range` initialiser made `internal`)
/// leaves this guard green and the two guards discriminate separately.
///
/// Mutation that must redden it: the `ProposalElementGroup` conformance made
/// unconditional (with a trapping body).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aForEachOfLegacyContentDoesNotCompileInsideAProposalStack() throws {
    let legacy = try typecheckFile("""
        @MainActor public func bad() {
            _ = HStack { ForEach([1, 2], id: \\.self) { _ in Box() } }
        }
        """, importing: "MetalUI")
    print("FOREACH GUARD G1.2 legacy: succeeded=\(legacy.succeeded)\n\(legacy.messages)")

    let control = try typecheckFile("""
        @MainActor public func good() {
            _ = HStack { ForEach([1, 2], id: \\.self) { _ in Rectangle() } }
        }
        """, importing: "MetalUI")
    print("FOREACH GUARD G1.2 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(legacy.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(legacy.output)\n\(control.output)")
    #expect(!legacy.succeeded, "legacy content must not enter a proposal stack through a ForEach:\n\(legacy.output)")
    #expect(legacy.messages.contains("ProposalElementGroup"),
            "rejected FOR the conformance:\n\(legacy.output)")
}
