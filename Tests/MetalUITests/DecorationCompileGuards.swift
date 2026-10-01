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
/// through `Box(decoration:)` (`Box(style:decoration:)` until plan task 15
/// narrowed `style:` to `package`, `CX-D`), so `var d = Decoration(); d.opacity = 2`
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
    #expect(opacity.messages.contains("'opacity' setter is inaccessible"),
            "`Decoration.opacity` must be rejected for its SETTER's access level:\n\(opacity.output)")
    #expect(widths.messages.contains("'widths' setter is inaccessible"),
            "`BorderStyle.widths` must be rejected for its SETTER's access level:\n\(widths.output)")
}

/// **The new legacy modifiers do not collide with the proposal path's
/// same-named ones**, and each one's receiver still infers the type its own
/// path uses.
///
/// `.background`, `.border`, `.opacity`, `.clip` and `.allowsHitTesting`
/// already exist on `ProposalElementGroup`; lane 2 adds `.border`, `.opacity`
/// and `.clipped` to `extension StyledElement`, and **lane 3 adds
/// `.allowsHitTesting(_:)` and the two `.contentShape(inset:)` overloads**. No
/// type conforms to both protocols today, so the two sets cannot be ambiguous —
/// but nothing said so, and "no type conforms to both" is a fact about the
/// current tree rather than a rule. This fixture states it as one: a `Box`
/// chain must resolve to `Box`, and an `HStack` chain to the proposal wrapper,
/// in one file that imports both surfaces.
///
/// **`allowsHitTesting(_:)` is the first name to exist on both surfaces with
/// the same spelling AND the same argument type** — `.border` differs in its
/// arguments, `.clipped`/`.clip` in their names — so the legacy half of the
/// `both` fixture carries it, and the legacy-only `contentShape(inset:)` gets
/// a disagreeing fixture of its own beside `crossed`.
///
/// Mutated red once (record §15, mutation **G3b**): declaring `clipped()` on
/// `ElementGroup` — where a proposal element sees it too — makes the `crossed`
/// fixture compile, the two fixtures agree, and the `#require` fires.
///
/// **Re-answered by plan task 11 part 2 (a T row, `TE-AJ` item 1; record §61
/// §4):** `clipped()` is no longer legacy-only — SwiftUI's `.clipped()` exists
/// on the proposal path too (probe C3), as `.clip()`. So `HStack { … }.clipped()`
/// now compiles and moves into `both`'s proposal half (still inferring the
/// proposal wrapper, where the legacy half's `clipped()` still infers `Box`),
/// and `crossed` is re-spelled with `hoverBackground(_:)`, still legacy-only.
/// G3b's twin for the new spelling — `hoverBackground` declared on
/// `ElementGroup` — makes `crossed` compile.
///
/// **The obvious mutation does NOT redden it, and that is worth knowing**
/// (G3, measured): declaring the legacy `opacity(_:)` on `ElementGroup` rather
/// than on `StyledElement` leaves `HStack { … }.opacity(0.5)` **unambiguous**,
/// because `ProposalElementGroup` refines `ElementGroup` and Swift's overload
/// resolution prefers a more refined protocol's extension. So the collision
/// this guard is named for cannot be produced by adding a member to a
/// SUPERprotocol at all; what it does state is that `clipped()` stays
/// legacy-only and that a legacy chain keeps inferring its concrete type.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theLegacyAndProposalDecorationModifiersDoNotCollide() throws {
    let both = try typecheckFile("""
        @MainActor func legacy() -> Box<EmptyGroup> {
            Box().border(.accent, width: Pixels(2)).opacity(0.5).clipped()
                .allowsHitTesting(false).contentShape(inset: Pixels(2))
        }
        @MainActor func proposal() -> some Element {
            HStack { ProposalText("hi") }.border(.accent, width: Pixels(2)).opacity(0.5)
                .allowsHitTesting(false).clipped()
        }
        """, importing: "MetalUI")
    // The disagreeing half: a spelling that must NOT compile, so "it all
    // type-checks" is not the only thing this instrument can say.
    let crossed = try typecheckFile("""
        @MainActor func crossed() -> some Element {
            HStack { ProposalText("hi") }.hoverBackground(.accent)
        }
        """, importing: "MetalUI")
    // The same, for lane 3's legacy-only modifier. A second fixture rather
    // than a second call inside `crossed`, so a failure names which modifier
    // leaked.
    let crossedShape = try typecheckFile("""
        @MainActor func crossed() -> some Element {
            HStack { ProposalText("hi") }.contentShape(inset: Pixels(2))
        }
        """, importing: "MetalUI")

    print("""
        OM-B/OM-N/OM-T collision: both succeeded=\(both.succeeded) messages=[\(both.messages)]; \
        crossed succeeded=\(crossed.succeeded) messages=[\(crossed.messages)]; \
        crossedShape succeeded=\(crossedShape.succeeded) messages=[\(crossedShape.messages)]
        """)

    try #require(both.succeeded != crossed.succeeded && both.succeeded != crossedShape.succeeded,
                 """
                 the fixtures must disagree, or this guard accepts or rejects everything:
                 both:
                 \(both.output)
                 crossed:
                 \(crossed.output)
                 crossedShape:
                 \(crossedShape.output)
                 """)
    #expect(both.succeeded,
            """
            a legacy chain must infer `Box` and a proposal chain the proposal wrapper, with \
            no ambiguity between the two `.border`/`.opacity`/`.allowsHitTesting` surfaces:
            \(both.output)
            """)
    #expect(!crossed.succeeded,
            "`hoverBackground(_:)` is legacy-only; a proposal element must not see it:\n\(crossed.output)")
    #expect(!crossedShape.succeeded,
            """
            `contentShape(inset:)` is legacy-only until task 12; a proposal element must not \
            see it:
            \(crossedShape.output)
            """)
}

/// **G2.2 (plan task 12 part 1, lane 2; ruling `IX-L` item 1) — a proposal
/// element cannot spell `.contentShape(_:)` before its tap.** On the proposal
/// path the shape is written **after** the tap or gesture, on the wrapper that
/// owns the hitbox (`OnTapModifier`, `GestureModifier`); spelled on the bare
/// proposal element it would configure a node that registers no hitbox. The
/// control arm writes it after `.onTap { }` and after `.onTapGesture { }`, and
/// on a legacy `Box`, where it is a `StyledElement` modifier.
///
/// Mutation that must redden it (mutated red once, `IX-R`): `contentShape(_:)`
/// declared on `ProposalElementGroup`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aProposalElementCannotSpellContentShapeBeforeItsTap() throws {
    let before = try typecheckFile("""
        @MainActor func before() -> some Element {
            HStack { ProposalText("hi") }.contentShape(Circle()).onTap { }
        }
        """, importing: "MetalUI")
    let after = try typecheckFile("""
        @MainActor func after() -> some Element {
            HStack { ProposalText("hi") }.onTap { }.contentShape(Circle())
        }
        @MainActor func gesture() -> some Element {
            HStack { ProposalText("hi") }.onTapGesture { }.contentShape(RoundedRectangle(cornerRadius: Pixels(4)))
        }
        @MainActor func legacy() -> Box<EmptyGroup> {
            Box().contentShape(Circle()).onClick { }
        }
        """, importing: "MetalUI")
    print("IX-L contentShape order: before succeeded=\(before.succeeded) messages=[\(before.messages)]; "
          + "after succeeded=\(after.succeeded) messages=[\(after.messages)]")
    try #require(before.succeeded != after.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(before.output)\n\(after.output)")
    #expect(!before.succeeded, "a proposal element must not spell contentShape before its tap:\n\(before.output)")
    #expect(after.succeeded, "contentShape after a proposal tap or gesture, and on a Box, compiles:\n\(after.output)")
}
