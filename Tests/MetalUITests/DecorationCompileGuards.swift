import Testing
import MetalUITestSupport

// Compile-time guards for lane 2 of
// `docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`: the paint-only
// decoration surface — `border`/`hoverBorder`/`focusBorder`, `opacity`,
// `clipped()` — and the two removals and one narrowing that come with it
// (rulings `OM-M`, `OM-Y`).
//
// **Every fixture uses `typecheckFile`**: a whole file in the Swift 6 language
// mode against a PLAIN `import MetalUI`, as an external module writes it. This
// file's own imports are irrelevant (practices shape 16); the fixture's import
// is the one that counts. A `@testable` test cannot demonstrate a *narrowing* —
// it sees the internal setter — which is why `OM-Y`'s `private(set)` claim is
// here rather than in `DecorationPaintTests.swift`.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "When CI lands"). All three were mutated red once on a
// `swift build --build-system native` build; the red lines are in record §15's
// lane 2 section.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **Both `borderWidth` overloads are gone** (ruling `OM-M`).
///
/// They wrote `Style.border`, which the engine consumed inside `contentBox` and
/// discarded: on a content-sized box they moved the layout and on any box they
/// painted nothing, which is worse than inert — CLAUDE.md's declared-but-inert
/// table existed to remove that shape rather than annotate it. The name now
/// belongs to a paint-only `.border(_:width:)` that is layout-neutral, as
/// SwiftUI's is (probe `swiftui-outer-modifier-order` L2).
///
/// **Three fixtures, and the third is what makes the first two mean anything.**
/// A negative alone passes against a module that failed to import, against a
/// `Box` that does not exist, against a typo in `Pixels`. The positive is the
/// *same expression shape* with a live modifier in the same extension, so the
/// pair disagrees only about the name.
///
/// Mutated red once (record §15): pointing the two negatives at `padding`
/// instead — a modifier that does exist — makes both compile and the
/// `#require` fires.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func borderWidthIsNoLongerSpellable() throws {
    let points = try typecheckFile("""
        @MainActor func probe() -> some Element { Box().borderWidth(Pixels(4)) }
        """, importing: "MetalUI")
    let edges = try typecheckFile("""
        @MainActor func probe() -> some Element {
            Box().borderWidth(Edges(all: Length.pixels(Pixels(4))))
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        @MainActor func probe() -> some Element { Box().padding(Pixels(4)) }
        """, importing: "MetalUI")

    print("""
        OM-M borderWidth removal: points succeeded=\(points.succeeded) \
        messages=[\(points.messages)]; edges succeeded=\(edges.succeeded) \
        messages=[\(edges.messages)]; control succeeded=\(control.succeeded) \
        messages=[\(control.messages)]
        """)

    try #require(control.succeeded && !points.succeeded && !edges.succeeded,
                 """
                 the control must compile and both negatives must not, or this guard \
                 cannot fail:
                 control:
                 \(control.output)
                 points:
                 \(points.output)
                 """)
    #expect(points.messages.contains("borderWidth"),
            "the points overload must be rejected FOR ITS NAME:\n\(points.output)")
    #expect(edges.messages.contains("borderWidth"),
            "the edges overload must be rejected FOR ITS NAME:\n\(edges.output)")
}

/// **`BorderStyle.widths` and `Decoration.opacity` are `public private(set)`**
/// (ruling `OM-Y`): readable from outside the module, writable only through the
/// validating `init`s, `withWidths(_:)` and `setOpacity(_:)`.
///
/// **Why a typecheck guard and not an exit test.** The exit tests next door
/// (`aNegativeBorderWidthTraps`, `anOpacityAboveOneTraps`,
/// `aBorderWidthSetAfterInitIsStillValidated`,
/// `anOpacitySetAfterInitIsStillValidated`) pin the *traps*; they cannot see
/// whether a door exists beside the window. `Decoration` is public and reachable
/// through `Box(style:decoration:)`, so `var d = Decoration(); d.opacity = 2`
/// would reach paint unchecked, and a `@testable` test sees the internal setter
/// and would pass either way (taxonomy shape 16).
///
/// Mutated red once (record §15): making either field a plain `public var`
/// makes its negative compile and the `#require` fires.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theValidatedDecorationFieldsAreNotAssignableFromOutsideTheModule() throws {
    let opacity = try typecheckFile("""
        @MainActor func probe() -> Decoration {
            var d = Decoration()
            d.opacity = 2
            return d
        }
        """, importing: "MetalUI")
    let widths = try typecheckFile("""
        @MainActor func probe() -> BorderStyle {
            var b = BorderStyle(.accent, width: Pixels(1))
            b.widths = Edges(all: Pixels(-5))
            return b
        }
        """, importing: "MetalUI")
    // The same two fields READ, and the two sanctioned writes, in one file: a
    // rejection that were really "no such member" or "no such type" would take
    // this down with it.
    let control = try typecheckFile("""
        @MainActor func probe() -> (Float, Edges<Pixels>) {
            var d = Decoration()
            d.setOpacity(0.5)
            let b = BorderStyle(.accent, width: Pixels(1)).withWidths(Edges(all: Pixels(2)))
            return (d.opacity, b.widths)
        }
        """, importing: "MetalUI")

    print("""
        OM-Y private(set): opacity succeeded=\(opacity.succeeded) messages=[\(opacity.messages)]; \
        widths succeeded=\(widths.succeeded) messages=[\(widths.messages)]; \
        control succeeded=\(control.succeeded) messages=[\(control.messages)]
        """)

    try #require(control.succeeded && !opacity.succeeded && !widths.succeeded,
                 """
                 reading both fields and calling both sanctioned setters must compile while \
                 both direct assignments must not, or this guard cannot fail:
                 control:
                 \(control.output)
                 opacity:
                 \(opacity.output)
                 widths:
                 \(widths.output)
                 """)
    #expect(opacity.messages.contains("setter for 'opacity' is inaccessible"),
            "`Decoration.opacity` must be rejected for its SETTER's access level:\n\(opacity.output)")
    #expect(widths.messages.contains("setter for 'widths' is inaccessible"),
            "`BorderStyle.widths` must be rejected for its SETTER's access level:\n\(widths.output)")
}

/// **The new legacy modifiers do not collide with the proposal path's
/// same-named ones**, and each one's receiver still infers the type its own
/// path uses.
///
/// `.background`, `.border`, `.opacity` and `.clip` already exist on
/// `ProposalElementGroup`; lane 2 adds `.border`, `.opacity` and `.clipped` to
/// `extension StyledElement`. No type conforms to both protocols today, so the
/// two sets cannot be ambiguous — but nothing said so, and "no type conforms to
/// both" is a fact about the current tree rather than a rule. This fixture
/// states it as one: a `Box` chain must resolve to `Box`, and an `HStack` chain
/// to the proposal wrapper, in one file that imports both surfaces.
///
/// Mutated red once (record §15): declaring the legacy `opacity(_:)` on
/// `ElementGroup` instead of `StyledElement` — where `HStack` would also see it
/// — makes the `HStack` arm ambiguous and the fixture fails to compile.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theLegacyAndProposalDecorationModifiersDoNotCollide() throws {
    let both = try typecheckFile("""
        @MainActor func legacy() -> Box<EmptyGroup> {
            Box().border(.accent, width: Pixels(2)).opacity(0.5).clipped()
        }
        @MainActor func proposal() -> some Element {
            HStack { ProposalText("hi") }.border(.accent, width: Pixels(2)).opacity(0.5)
        }
        """, importing: "MetalUI")
    // The disagreeing half: a spelling that must NOT compile, so "it all
    // type-checks" is not the only thing this instrument can say.
    let crossed = try typecheckFile("""
        @MainActor func crossed() -> some Element {
            HStack { ProposalText("hi") }.clipped()
        }
        """, importing: "MetalUI")

    print("""
        OM-B/OM-N collision: both succeeded=\(both.succeeded) messages=[\(both.messages)]; \
        crossed succeeded=\(crossed.succeeded) messages=[\(crossed.messages)]
        """)

    try #require(both.succeeded != crossed.succeeded,
                 """
                 the two fixtures must disagree, or this guard accepts or rejects everything:
                 both:
                 \(both.output)
                 crossed:
                 \(crossed.output)
                 """)
    #expect(both.succeeded,
            """
            a legacy chain must infer `Box` and a proposal chain the proposal wrapper, with \
            no ambiguity between the two `.border`/`.opacity` surfaces:
            \(both.output)
            """)
    #expect(!crossed.succeeded,
            "`clipped()` is legacy-only; a proposal element must not see it:\n\(crossed.output)")
}
