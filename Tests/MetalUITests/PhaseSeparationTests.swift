import Testing
import MetalUITestSupport

// Spec §4.1: "`LayoutPass` / `PrepaintPass` / `PaintPass` are thin structs over
// one `@MainActor final class Frame`, exposing only what is legal in that phase
// — emitting a rect during layout is a compile error."
//
// That is a claim about the **type system**, and no ordinary test can observe
// it: if `LayoutPass` grew a `fill`, every runtime test in the repo would stay
// green. So each property here is checked by compiling a fixture that imports
// `MetalUI` as an outside client would, exactly as `UnitSafetyTests` does for
// units. The machinery is shared, not copied — ruling EP-1.
//
// **Every negative test is paired with a positive one, and asserts the failure
// mentions the symbol it is about.** A fixture with a typo also "fails to
// compile", and so does a fixture naming a method that exists nowhere: a bare
// `#expect(!succeeded)` passes in both cases and guards nothing.
//
// Scope of the guarantee, stated as a mechanism rather than a hope: the pass
// structs' initialisers and `Frame`'s are `internal`, so code outside `MetalUI`
// can only ever use a pass it was handed by the phase it is in. Inside the
// module the compiler does not stop you — `codeOutsideTheFrameworkCannotFabricateAPaintPass`
// is what pins the outside half.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — phase-separation guard skipped"

/// A `Bounds<Pixels>` literal for fixtures. Deliberately non-square and
/// non-zero: a fixture that says `10x10` cannot tell width from height if a
/// later signature change transposes them.
private let sampleBounds = """
let box = Bounds(origin: Point(x: Pixels(3), y: Pixels(7)),
                 size: Size(width: Pixels(40), height: Pixels(25)))
"""

// MARK: - Painting is legal only in paint

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func emittingAPrimitiveDuringLayoutDoesNotCompile() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout LayoutPass) {
            \(sampleBounds)
            pass.fill(box, color: .white)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "LayoutPass exposes a way to emit a primitive; §4.1 says that must not compile")
    #expect(result.messages.contains("fill"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func emittingAPrimitiveDuringPrepaintDoesNotCompile() throws {
    // Prepaint has resolved bounds but must still precede painting: hitboxes,
    // culling and overlay hoisting all run before the first primitive.
    let result = try typecheck("""
        @MainActor func probe(pass: inout PrepaintPass) {
            \(sampleBounds)
            pass.fill(box, color: .white)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded)
    #expect(result.messages.contains("fill"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func emittingAPrimitiveDuringPaintCompiles() throws {
    // The load-bearing half. Without it, both tests above pass just as well
    // when `fill` does not exist on any pass at all.
    let result = try typecheck("""
        @MainActor func probe(pass: inout PaintPass) {
            \(sampleBounds)
            pass.fill(box, color: .white)
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "painting must be legal in the paint phase, or the negative tests above mean nothing:\n\(result.output)")
}

// MARK: - Registering a layout node is legal only in layout

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func registeringALayoutNodeDuringPaintDoesNotCompile() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PaintPass) -> LayoutNodeID {
            pass.requestNode(style: Style(), children: [])
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "the tree's shape is fixed once layout has run; PaintPass must not extend it")
    #expect(result.messages.contains("requestNode"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func registeringALayoutNodeDuringLayoutCompiles() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout LayoutPass) -> LayoutNodeID {
            pass.requestNode(style: Style(), children: [])
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "registering a layout node is the whole point of the layout phase:\n\(result.output)")
}

// MARK: - Resolved bounds exist only after layout has run

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func readingResolvedBoundsDuringLayoutDoesNotCompile() throws {
    // Reading a rect before the engine has run would read the zero it was
    // initialised with — a silent wrong answer, which is exactly the shape the
    // phase split exists to make impossible.
    let result = try typecheck("""
        @MainActor func probe(pass: inout LayoutPass, node: LayoutNodeID) -> Bounds<Pixels> {
            pass.bounds(of: node)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded)
    #expect(result.messages.contains("bounds"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func readingResolvedBoundsDuringPrepaintCompiles() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PrepaintPass, node: LayoutNodeID) -> Bounds<Pixels> {
            pass.bounds(of: node)
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "prepaint runs after layout precisely so it can read resolved bounds:\n\(result.output)")
}

// MARK: - The guarantee's foundation

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func codeOutsideTheFrameworkCannotFabricateAPaintPass() throws {
    // Every test above assumes an element cannot simply build the pass it wants.
    // If `PaintPass.init` were public, an element could paint from `requestLayout`
    // in one line and the whole phase split would be advisory.
    let result = try typecheck("""
        @MainActor func probe(frame: Frame) -> PaintPass {
            PaintPass(frame: frame)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "PaintPass is constructible from outside MetalUI; the phase split is then advisory, not enforced")
    #expect(result.messages.contains("PaintPass"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
    // The discriminator this one needs and the others do not: "cannot find type
    // 'PaintPass' in scope" *also* contains "PaintPass", so deleting the type
    // outright would satisfy the check above. An inaccessible initialiser is a
    // different message from an absent type.
    #expect(!result.messages.contains("cannot find type"),
            "PaintPass does not exist at all, so this proves nothing about its initialiser:\n\(result.output)")
}

// MARK: - Cross-frame state is reachable; the Frame behind it is not

/// `withState` must be callable by element authors **outside** the module.
///
/// Two mutations left the whole suite green before this guard existed: making
/// `frame` public on all three passes, and replacing the three duplicated
/// `withState` methods with an *internal* `StatefulPass` protocol — which
/// compiles fine and silently makes `withState` inaccessible to anyone outside
/// `MetalUI`. Every other pass member is guarded by an external typecheck; these
/// two were not, which is why nothing noticed.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func withStateIsReachableFromOutsideTheModule() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PrepaintPass, id: GlobalElementID) {
            pass.withState(id, initial: 0) { $0 += 1 }
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "withState is not reachable from outside MetalUI:\n\(result.output)")
}

/// The `Frame` behind a pass must **not** be reachable from outside.
///
/// This is the constraint that forced three duplicated `withState` methods
/// instead of a public `StatefulPass` protocol: a public protocol requirement
/// forces `frame` public on all three passes, and `Frame.scaleFactor` is public,
/// so `pass.frame.scaleFactor` would compile. `PaintPass` deliberately does not
/// expose `scaleFactor` — `fill` has already applied it, and a caller who
/// applies it again double-scales.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theFrameBehindAPassIsNotReachableFromOutsideTheModule() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PaintPass) -> Float {
            pass.frame.scaleFactor
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "pass.frame is reachable externally; the whole Frame surface is exposed")
    #expect(result.messages.contains("frame"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

// MARK: - The theme is reachable only where a colour can be used

/// §7.9's theme is "propagated through the frame context, so no element reads
/// global state" — and the propagation stops at `PaintPass`.
///
/// The positive half is the load-bearing one: without it, the two negatives
/// below pass just as well against a `Theme` that reaches no pass at all, which
/// is a thing a refactor could plausibly do while every colour assertion in
/// `ThemeTests` keeps passing through `Frame.theme` directly.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func readingTheThemeDuringPaintCompiles() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PaintPass) -> Hsla {
            pass.theme[.accent]
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "paint is the only phase that can consume a colour, so it must be able to read one:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func readingTheThemeDuringLayoutDoesNotCompile() throws {
    // Not a phase-ordering rule like `fill` — nothing would be *wrong* about a
    // colour during layout, there is simply nothing in `Style` for one to go
    // into. The guard is against the API existing with no reader, which is
    // CLAUDE.md's inert-declaration shape. When a layout rule acquires a use for
    // the theme, delete this test in the same change that adds the property.
    let result = try typecheck("""
        @MainActor func probe(pass: inout LayoutPass) -> Hsla {
            pass.theme[.accent]
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded)
    #expect(result.messages.contains("theme"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func readingTheThemeDuringPrepaintDoesNotCompile() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PrepaintPass) -> Hsla {
            pass.theme[.accent]
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded)
    #expect(result.messages.contains("theme"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

// MARK: - Hover, active and focus are queryable only in paint (§3.3, §3.4, §4.2)
//
// **Worse to get wrong than `theme` above, and that is why these three exist as
// their own guards rather than being folded into "read-only state" in
// general.** A colour read during prepaint would simply fail to compile —
// there is nothing in `Style` for one to come from, so no implementation
// could make it silently wrong.
//
// **The FOUR below do NOT all rest on the same footing, and reading them as
// though they did is the specific mistake this paragraph exists to prevent.**
// Three are measured lies and one is placement insurance. Anyone adding a fifth
// `PaintPass` query should work out which category it falls into rather than
// adding a guard by symmetry with these — a guard for an API that would answer
// correctly is cargo cult, and the brief for the `isFocused` work said so
// explicitly.
//
// (This block said "the three below" and "a fourth" until the input-and-state
// milestone's last task added the element-keyed `isHovered` guard *inside* its
// scope — leaving an enumeration that silently omitted the newest guard and an
// instruction addressed to whoever adds a fourth that read as still unfilled.
// A guard added below must gain a bullet here in the same change.)
//
// - **`isHovered` — a measured lie, returning a silently wrong `false`**, for
//   two independent reasons. `Frame.hoveredHitbox` is still `nil` during
//   prepaint, because `resolveHover(at:)` runs at the prepaint/paint boundary,
//   *after* `prepaint` returns. And the hitbox list is still being **built** at
//   that point — `PrepaintPass.insertHitbox` is what fills it — so even a hover
//   that had somehow already resolved would have ranked against a partial list,
//   which is §3.3's own reason for resolving once at the boundary rather than
//   during registration: "topmost wins" is not knowable until every hitbox has
//   registered.
//
// - **`isActive` — NOT a lie today, and this comment claimed it was.**
//   `PaintPass.isActive` is `frame.activeElement == id`, and
//   `Frame.activeElement` is a `let` assigned once in `init` and never mutated;
//   it consults neither of hover's two mechanisms. A prepaint-time `isActive`
//   would answer **correctly**. Its guard is kept anyway, as *placement
//   insurance*: `active` is the one of the three that could plausibly acquire a
//   boundary-resolution step later (a press that must rank against the finished
//   hitbox list, say), and on that day the guard would become load-bearing with
//   nobody having to notice. Cheap insurance is a different justification from
//   a measured lie, and stating it as one was wrong.
//
// - **`isHovered(_ id: GlobalElementID)` — the same measured lie as the first
//   bullet, in a second SPELLING.** `Frame.hoveredElement` is a derived view of
//   `hoveredHitbox`, so it inherits both of that bullet's mechanisms exactly.
//   It gets its own guard rather than being folded into the first because the
//   two probes are not interchangeable: with the hazard added, the `HitboxID`
//   probe fails on its *message* assertion only (its diagnostic becomes a
//   type-conversion error) while this one fails on both. The differential is
//   measured at that guard, and it corrects a claim this file made before it
//   was run.
//
// - **`isFocused` — a measured lie in the opposite direction**, returning a
//   wrong `true`. The numbers are at its own guard below, because the
//   measurement is what makes that guard non-cargo-cult and it should not be
//   findable only from here.
//
// Together these make "queryable only during paint" a compiler fact rather
// than a placement convention nothing enforces if someone later moves or
// duplicates one of the methods onto `PrepaintPass`.

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func queryingHoverDuringPrepaintDoesNotCompile() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PrepaintPass, id: HitboxID) -> Bool {
            pass.isHovered(id)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded)
    #expect(result.messages.contains("isHovered"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

/// The **element-keyed** `isHovered` overload is paint-only too, and this guard
/// is not symmetry with the one above.
///
/// `queryingHoverDuringPrepaintDoesNotCompile` probes `isHovered(_:)` with a
/// `HitboxID`. This one probes the `GlobalElementID` spelling, which is the one
/// every `StyledElement` conformer reaches for and therefore the plausible
/// place to add the hazard.
///
/// **What the differential actually is, MEASURED — and the first version of
/// this comment got it wrong.** It said adding only the `GlobalElementID`
/// overload to `PrepaintPass` "would leave that guard green". Running that
/// mutation shows otherwise, and the true picture is narrower:
///
/// - the older guard **fails, on one assertion of two**. Its primary
///   `#expect(!result.succeeded)` still *passes* — the `HitboxID` probe still
///   does not compile — and it is the message assertion that breaks, because
///   the diagnostic changes from "no member `isHovered`" to `cannot convert
///   value of type 'HitboxID' to expected argument type 'GlobalElementID'`. So
///   it reports the hazard as **its own probe having become ill-typed**, which
///   is its "rejected, but not for the reason this test is about" message doing
///   its job — a tripwire, not a detection.
/// - this guard **fails on both assertions**, which is the detection.
///
/// The suite is therefore not silently green under the hazard, and the reason
/// to keep two probes is sharper than "one would miss it": without this one,
/// nothing in the repo *says* what went wrong, and the only red is a test
/// complaining that its own fixture no longer type-checks.
///
/// The hazard is the same one, measured the same way: `Frame.hoveredElement`
/// reads `hoveredHitbox`, which `resolveHover(at:)` does not write until
/// `prepaint` has returned, so a prepaint-time call answers `nil` — a silently
/// wrong `false` for every element, including the one under the pointer — and
/// would rank against a half-built list even if it did not.
///
/// **Delete this guard, and its `HitboxID` sibling, if hover stops resolving at
/// the prepaint/paint boundary** — that is, if `Frame.resolveHover(at:)` ever
/// runs before `prepaint` *and* the hitbox list is complete before `prepaint`
/// begins. Both halves are needed: the first makes `hoveredHitbox` non-`nil`,
/// the second makes ranking against it meaningful. That is the same shape of
/// contingent justification `queryingFocusDuringPrepaintDoesNotCompile` carries
/// for `resolveFocus()`, and stating it is what keeps this from becoming a
/// guard nobody can evaluate.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func queryingElementKeyedHoverDuringPrepaintDoesNotCompile() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PrepaintPass, id: GlobalElementID) -> Bool {
            pass.isHovered(id)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded)
    #expect(result.messages.contains("isHovered"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func queryingActiveDuringPrepaintDoesNotCompile() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PrepaintPass, id: GlobalElementID) -> Bool {
            pass.isActive(id)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded)
    #expect(result.messages.contains("isActive"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

/// `isFocused` is paint-only too — and this guard was added on a
/// **measurement**, not on symmetry with the two above.
///
/// The question worth asking of any new guard here is whether the phase it
/// excludes would actually give a wrong answer, since focus is window state
/// that is fully known before the frame starts and might therefore have been
/// safe to read at any point. It is not. `Frame.resolveFocus()` runs at the
/// prepaint/paint boundary, after every element's `prepaint` has contributed to
/// the focus registry, and *clears* a focused id this frame did not produce —
/// so during `prepaint` the frame still holds the pre-clearing value.
///
/// Measured with a throwaway element that read `pass.frame.focusedElement`
/// during its own `prepaint` (exactly what a `PrepaintPass.isFocused(_:)` would
/// return) and `pass.isFocused` during its own `paint`, over three frames of one
/// window — unfocused, focused, then still produced but no longer `.focusable()`:
///
/// ```
/// ["prepaint=false", "paint=false",
///  "prepaint=true",  "paint=true",
///  "prepaint=true",  "paint=false"]   // <- the frame that drops focus
/// ```
///
/// The third pair is the finding: a prepaint-time query returns a silently
/// wrong `true` for an element the same frame has already decided is not
/// focused. That is `isHovered`'s failure with the sign flipped, and it is what
/// this guard exists for rather than tidiness.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func queryingFocusDuringPrepaintDoesNotCompile() throws {
    let result = try typecheck("""
        @MainActor func probe(pass: inout PrepaintPass, id: GlobalElementID) -> Bool {
            pass.isFocused(id)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded)
    #expect(result.messages.contains("isFocused"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

// MARK: - A background is a token, never a literal (§7.9)

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aBackgroundCannotBeWrittenAsAColourLiteral() throws {
    // §7.9: "Colors in element code are semantic tokens … never literals." A
    // literal would paint identically in both appearances while looking exactly
    // like a themed call at the site, so the type is what keeps it out of reach —
    // the same device that keeps `margin: .auto` unspellable.
    let result = try typecheck("""
        @MainActor func probe() -> Box<EmptyGroup> {
            Box().background(Hsla.white)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "background(_:) accepts a literal colour, so a call site can opt out of the theme invisibly")
    #expect(result.messages.contains("background") || result.messages.contains("Hsla"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aBackgroundCanBeWrittenAsAToken() throws {
    let result = try typecheck("""
        @MainActor func probe() -> Box<EmptyGroup> {
            Box().background(.surfaceSecondary)
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "the token form must work, or the negative above proves nothing:\n\(result.output)")
}
