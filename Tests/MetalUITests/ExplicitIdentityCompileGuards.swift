import Testing
import MetalUITestSupport

// Plan task 8, lane 3, guards G3.1–G3.3 (rulings `ID-G`, `ID-J`). Whole-file
// Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`, ruling SA-P): what
// an external module may write, and which overload it gets.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `EXPLICIT IDENTITY GUARD` to know it
// ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G3.1 — an `.id` on a `StyledElement` still returns its own type.**
/// `ElementGroup.id(_:) -> IdentifiedGroup<Self>` (`ID-G`) must not take a
/// `StyledElement`'s call: `StyledElement.id(_:) -> Self` is more specific and
/// wins, so `Box().id("x")` is still a `Box` and a legacy chain's `.id` is still
/// its `ModifiedContent<…, ModifierLayer>` — their paths (a name REPLACING a
/// position) are unchanged. Each positive binds the call with no type context
/// and then checks its type, so the overload is chosen by ranking alone.
///
/// Control: the same unconstrained `Box().id("x")` bound to
/// `IdentifiedGroup<Box<EmptyGroup>>` must be rejected; the two arms are
/// `#require`d to disagree, so a fixture broken for another reason cannot pass.
///
/// The positive's third line, a `Rectangle` (no `StyledElement`) taking
/// `IdentifiedGroup`, makes the positive depend on `ID-G` too.
///
/// Red before: both arms rejected, so the `#require` fails (`value of type
/// 'Rectangle' has no member 'id'`, `cannot find type 'IdentifiedGroup' in
/// scope`). Mutation **M3e** (a second `id(_:) -> IdentifiedGroup<Self>` on
/// `StyledElement`) makes the positive ambiguous.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anIDOnAStyledElementStillReturnsItsOwnType() throws {
    let positive = try typecheckFile("""
        @MainActor public func styled() {
            let b = Box().id("x")
            let _: Box<EmptyGroup> = b
            let m = Box().padding(Pixels(4)).id("x")
            let _: ModifiedContent<Box<EmptyGroup>, ModifierLayer> = m
            let r = Rectangle().id("x")
            let _: IdentifiedGroup<Rectangle> = r
        }
        """, importing: "MetalUI")
    print("EXPLICIT IDENTITY GUARD G3.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let control = try typecheckFile("""
        @MainActor public func styled() {
            let b = Box().id("x")
            let _: IdentifiedGroup<Box<EmptyGroup>> = b
        }
        """, importing: "MetalUI")
    print("EXPLICIT IDENTITY GUARD G3.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "a StyledElement's .id must keep its own type:\n\(positive.output)")
    #expect(!control.succeeded, "Box().id must not resolve to IdentifiedGroup:\n\(control.output)")
    #expect(control.messages.contains("IdentifiedGroup"),
            "rejected, but not for the reason this guard is about:\n\(control.output)")
}

/// **G3.2 — an `.id` on a proposal group enters a proposal container.**
/// `IdentifiedGroup: ProposalElementGroup where Content: ProposalElementGroup`
/// (`ID-G`), so a named `Rectangle`, a named `GridRow` inside a `Grid` and a
/// named proposal `Component` are proposal content. Control: a legacy chain's
/// `.id` — `HStack { Box().padding(Pixels(4)).id("x") }` — must still be
/// rejected (it is a `StyledElement`'s own type, not proposal content); the two
/// arms are `#require`d to disagree.
///
/// Red before: the positive does not compile (no `id` on `Rectangle`, `GridRow`
/// or a `Component`). Mutation **M3f** (delete the conditional
/// `ProposalElementGroup` conformance) rejects the positive.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anIDOnAProposalGroupEntersAProposalContainer() throws {
    let positive = try typecheckFile("""
        public struct Card: Component, ProposalElementGroup {
            public init() {}
            public var content: some ProposalElementGroup { Rectangle() }
        }

        @MainActor public func containers() {
            _ = HStack { Rectangle(width: Pixels(10), height: Pixels(10)).id("x") }
            _ = Grid { GridRow { Rectangle() }.id("r") }
            _ = VStack { Card().id("c") }
            _ = HStack { HStack { Rectangle(); Rectangle() }.id("g") }
        }
        """, importing: "MetalUI")
    print("EXPLICIT IDENTITY GUARD G3.2 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let control = try typecheckFile("""
        @MainActor public func bad() {
            _ = HStack { Box().padding(Pixels(4)).id("x") }
        }
        """, importing: "MetalUI")
    print("EXPLICIT IDENTITY GUARD G3.2 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "a named proposal group must enter a proposal container:\n\(positive.output)")
    #expect(!control.succeeded, "a named legacy chain must not enter a proposal container:\n\(control.output)")
}

/// **G3.3 — the legacy background keeps the token overload and the proposal
/// spelling.** One `.background(alignment:content:)` on `ElementGroup` (`ID-J`):
///
/// - a legacy primary takes it (`Box().background(alignment:) { Box() }`, and a
///   `Component` — `ID-I` item 6 as amended by `ID-M` item 1);
/// - `Box().background(.accent)`, unconstrained, still resolves to the
///   `ColorToken` overload and is still a `Box`;
/// - a proposal chain still infers `BackgroundModifier<Rectangle, Rectangle>`
///   and enters an `HStack`.
///
/// Control: `HStack { Box().background { Box() } }` — legacy on both sides — must
/// be rejected (the result is proposal content only when both sides are);
/// `#require`d to disagree with the positive.
///
/// Red before: the positive does not compile (the legacy spelling:
/// `BackgroundModifier` requires `ProposalElementGroup` content). Mutation
/// **M3j** (the `Content` parameter's `ProposalElementGroup`-only constraint
/// restored on the method) rejects the legacy lines.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theLegacyBackgroundKeepsTheTokenOverloadAndTheProposalSpelling() throws {
    let positive = try typecheckFile("""
        public struct Pair: Component {
            public init() {}
            public var content: some ElementGroup { Box(); Box() }
        }

        @MainActor public func backgrounds() {
            let token = Box().background(.accent)
            let _: Box<EmptyGroup> = token
            _ = Box().background(alignment: .topLeading) { Box() }
            _ = Pair().background { Box() }
            let proposal = Rectangle().background { Rectangle() }
            let _: BackgroundModifier<Rectangle, Rectangle> = proposal
            _ = HStack { Rectangle().background { Rectangle() } }
        }
        """, importing: "MetalUI")
    print("EXPLICIT IDENTITY GUARD G3.3 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let control = try typecheckFile("""
        @MainActor public func bad() {
            _ = HStack { Box().background { Box() } }
        }
        """, importing: "MetalUI")
    print("EXPLICIT IDENTITY GUARD G3.3 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the legacy, token and proposal spellings must all compile:\n\(positive.output)")
    #expect(!control.succeeded, "a legacy background must not enter a proposal container:\n\(control.output)")
}
