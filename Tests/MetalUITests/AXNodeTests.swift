import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
import MetalUITestSupport
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: px(x), y: px(y))
}

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h)))
}

/// A bare `Frame` with no element tree — most of this file drives
/// `PrepaintPass` directly, on `HitboxTests.swift`'s own footing: an
/// `AXNode` is emitted in prepaint and read back off the frame, and the
/// dictionary contract (`Frame.axNodes`) is testable without an element at
/// all.
@MainActor private func bareFrame(_ side: Float = 300) -> Frame {
    Frame(contentSize: Size(width: px(side), height: px(side)),
          scaleFactor: 1, stateTable: StateTable(),
          shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
          theme: Theme.forAppearance(.light))
}

/// Distinct element ids, named rather than positional so they can never
/// collide with a frame's own root path — `HitboxTests.swift`'s `eid`.
@MainActor private func eid(_ name: String) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID(name))
}

/// A `Frame` sharing a caller-supplied `StateTable` and, optionally, a
/// `focusedElement` — `bareFrame`'s own shape, but with the two things a
/// single bare frame cannot vary: a table that survives across several
/// `Frame` instances (the way `Window` really threads one across frames),
/// and a focused id (`private(set)` on `Frame`, settable only at `init`).
/// Exists for `theSevenRetentionSlotsAreMutuallyDistinct` below (named
/// `theThreeRetentionSlotsAreMutuallyDistinct` until the animation
/// milestone's Task 3 extended it to four, then Task 4's own fix round to
/// six, then Task 4b to seven), which needs several frames sharing one table
/// to reproduce `Frame.render`'s own two-sweep shape.
///
/// **`theme` is a parameter because Task 4b's `$anim-color` arm needs one**:
/// the seventh slot's mid-flight value is a colour, and `Theme.light`'s
/// `background`/`accent` pair is too close in hue and saturation for a
/// componentwise assertion to separate an intact slot from a clobbered one
/// with any margin. A purpose-built pair is.
@MainActor private func sharedFrame(_ table: StateTable, focusedElement: GlobalElementID? = nil,
                                    side: Float = 300, timestamp: Double = 0,
                                    theme: Theme = Theme.forAppearance(.light)) -> Frame {
    Frame(contentSize: Size(width: px(side), height: px(side)),
          scaleFactor: 1, stateTable: table,
          shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
          theme: theme, timestamp: timestamp, focusedElement: focusedElement)
}

/// The `$anim-color` arm's own theme (Task 4b). Two colours differing in every
/// RGB component, whose midpoint is far from both endpoints on every component
/// asserted — `AnimationTests.swift`'s `probeTheme` for the same reason, kept
/// local rather than shared because these two files are compiled together but
/// their fixtures are not one another's business.
@MainActor private func slotProbeTheme() -> Theme {
    Theme(background: Rgba(r: 0.10, g: 0.20, b: 0.80).toHsla(),
          surface: Rgba(r: 0.05, g: 0.55, b: 0.15).toHsla(),
          surfaceSecondary: Rgba(r: 0.25, g: 0.05, b: 0.45).toHsla(),
          accent: Rgba(r: 0.90, g: 0.70, b: 0.30).toHsla(),
          separator: Rgba(r: 0.60, g: 0.10, b: 0.90).toHsla(),
          textPrimary: Rgba(r: 0.85, g: 0.15, b: 0.05).toHsla(),
          scrollIndicator: Rgba(r: 0.15, g: 0.85, b: 0.65).toHsla(),
          scrim: Rgba(r: 0.45, g: 0.35, b: 0.95).toHsla())
}

// MARK: - The API contract, driven directly against `PrepaintPass`

/// The node's own step 1 test: an element emitting a node, retrievable by its
/// `GlobalElementID`, and a second, independent emission at a different id
/// does not disturb the first — a mutation that collapsed every emission onto
/// one dictionary entry (or ignored `id` and always overwrote the same key)
/// would still pass a single-node test but fails this one.
@Test @MainActor func anEmittedNodeIsRetrievableByItsGlobalElementID() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    pass.emitAXNode(AXNode(role: .button, label: "Go"), at: rect(0, 0, 40, 20),
                    id: eid("a"), children: [])
    pass.emitAXNode(AXNode(role: .text, label: "Hi"), at: rect(0, 30, 40, 20),
                    id: eid("b"), children: [])

    let a = try #require(frame.axNodes[eid("a")])
    let b = try #require(frame.axNodes[eid("b")])
    #expect(a.role == .button && a.label == "Go")
    #expect(b.role == .text && b.label == "Hi")
    #expect(frame.axNodes[eid("c")] == nil, "nothing was emitted under this id")
}

/// The emitted node's `frame` is the resolved bounds `emitAXNode` was given —
/// **not** whatever the caller's own `AXNode` value happened to carry, which
/// is what proves `frame`/`children` are overwritten on the way in rather than
/// read from the declared value. `AXNode`'s own doc calls this out as the
/// reason a declared value carries neither meaningfully.
@Test @MainActor func anEmittedNodesFrameIsTheResolvedBoundsNotWhateverItDeclared() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    // `frame`/`children` are `internal(set)` — unreachable through the public
    // initializer at all (see `AXNode`'s own doc) — so this file, which is
    // `@testable import`, reaches them the only way anything can: direct
    // property assignment from inside the module, after construction.
    var declaredButIgnored = AXNode(role: .button)
    declaredButIgnored.frame = rect(999, 999, 1, 1)
    declaredButIgnored.children = [eid("stale")]
    let resolvedBounds = rect(10, 20, 30, 40)
    pass.emitAXNode(declaredButIgnored, at: resolvedBounds, id: eid("target"), children: [])

    let node = try #require(frame.axNodes[eid("target")])
    #expect(node.frame == resolvedBounds,
            "the resolved bounds passed to `at:`, not the declared value's own stale frame")
    #expect(node.children.isEmpty,
            "the empty `children:` passed in, not the declared value's stale child")
}

/// Children come back in exactly the order they were declared — not sorted,
/// not reversed, not deduplicated. Ids are chosen out of alphabetical order
/// (`z`, `a`, `m`) so an implementation that silently sorted the array would
/// redden this and not a test using already-sorted names.
@Test @MainActor func childrenAreRetainedInDeclarationOrder() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let declared = [eid("z"), eid("a"), eid("m")]
    pass.emitAXNode(AXNode(role: .container), at: rect(0, 0, 10, 10),
                    id: eid("parent"), children: declared)

    let node = try #require(frame.axNodes[eid("parent")])
    #expect(node.children == declared,
            "declaration order preserved verbatim, including the out-of-order names")
    #expect(node.children.first == eid("z") && node.children.last == eid("m"),
            "sanity: `z` first and `m` last pins the actual order, not just set membership")
}

/// `emitAXNode` returns the resolved node, so a caller assembling a parent's
/// own children list from what its children just emitted needs no second
/// lookup into `Frame.axNodes` — see `PrepaintPass.emitAXNode`'s own doc.
@Test @MainActor func emitAXNodeReturnsTheResolvedValue() {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let resolved = pass.emitAXNode(AXNode(role: .image), at: rect(1, 2, 3, 4),
                                   id: eid("returned"), children: [eid("kid")])
    #expect(resolved.role == .image)
    #expect(resolved.frame == rect(1, 2, 3, 4))
    #expect(resolved.children == [eid("kid")])
}

// MARK: - Validity: a handle survives the sweep as a tombstone (design spec §9)
//
// `Frame.axNodes` (the dictionary the tests above read) is rebuilt from
// scratch every frame — an id not produced THIS frame is simply absent from
// it, which is a plain dictionary miss and cannot be told apart from "never
// existed". `Frame.axNode(for:)` is the durable query: it survives the
// sweep and reports `.isValid` from `StateTable.isLive`, the same query
// Task 4 already rides for focus retention — not a second liveness notion.

/// The step 1 case from this task's own brief, stated as literally as
/// possible: emit a node, hold its id, stop producing the element (nothing
/// re-emits under `eid("a")` on the next sweep), sweep, and the handle must
/// report itself invalid — not trap (a plain `Optional`, no force-unwrap
/// anywhere in `axNode(for:)`), not vanish (`try #require` below fails the
/// test if it does), and not silently keep reporting the stale value as
/// current (the whole point of `.isValid`).
///
/// **One half of the required two-sided assertion. The "and it alone" half of
/// this comment was TRUE WHEN WRITTEN AND IS FALSE NOW — corrected rather than
/// renumbered, because it is wrong in KIND and not merely stale by a count.**
/// It said a mutation that always reports `isValid = true` "reddens exactly
/// this test and nothing else in the 777-test suite". Re-run 2026-09-02
/// (deleting `node.isValid = stateTable.isLive(slot)` from
/// `Frame.axNode(for:)`): it reddens **two tests, 2 issues out of 782** — this
/// one *and* `theSevenRetentionSlotsAreMutuallyDistinct` (named
/// `theThreeRetentionSlotsAreMutuallyDistinct` at the time this was measured;
/// the animation milestone's Task 3 later extended it to a fourth slot and
/// Task 4's own fix round to a sixth), which landed in this same file two
/// commits later and reads validity back through the same production
/// accessor.
///
/// **What survives is the claim that actually mattered**: this test is the one
/// that catches the always-`true` direction, `aHandleToAProducedElementReportsValid`
/// below catches always-`false`, and neither catches the other — the two-sided
/// split is intact and was verified by running both rather than reasoned. What
/// does not survive is *exclusivity*, and the reason is the ordinary one: a
/// later test in the same file grew sensitivity to the same line. **An
/// exclusivity claim is a claim about the whole suite at one moment, so it
/// expires whenever any test is added anywhere** — which is why the surviving
/// claim above is worded as a differential between two named tests instead.
@Test @MainActor func aHandleToAnUnproducedElementReportsInvalid() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    pass.emitAXNode(AXNode(role: .button, label: "Go"), at: rect(0, 0, 40, 20),
                    id: eid("a"), children: [])

    // Two sweeps, not one — `TombstoneTests`/`FocusTests`' own two-frame
    // idiom. `withState` (what `emitAXNode` writes through) marks the slot
    // live IMMEDIATELY, before any sweep runs, so the sweep that closes the
    // producing frame only CONFIRMS liveness — it does not yet observe
    // absence. The first sweep below ends the frame that produced the node;
    // nothing marks the slot again before the second sweep, which ends the
    // frame the element was NOT produced in — that is the one that must
    // observe invalidity. One sweep here would assert a wrong reason for a
    // right-looking implementation; two is what the mechanism actually needs
    // (verified: a single-sweep version of this test fails against today's
    // correct implementation, which is why it is not written this way — see
    // this task's report for the exact failure).
    frame.stateTable.sweep()
    frame.stateTable.sweep()

    let tombstoned = try #require(frame.axNode(for: eid("a")),
        "the handle must survive the sweep as a tombstone, not vanish")
    #expect(!tombstoned.isValid,
        "the element was not produced this frame — the handle must report itself invalid")
    // The tombstone still carries the last-known data, on `StateTable`'s own
    // tombstone contract (`peek` after `sweep()` still returns a value) —
    // asserted here so a future reader does not mistake `.isValid == false`
    // for the fields themselves having been cleared.
    #expect(tombstoned.role == .button && tombstoned.label == "Go")
}

/// The other half. A handle to an element that IS still being produced must
/// report itself valid — checked here, independently of the test above, so
/// a mutation that always reports `isValid = false` has something to redden
/// on its own. **Measured to redden ALONE**: with that mutation applied, this
/// test fails (both assertions below) and
/// `aHandleToAnUnproducedElementReportsInvalid` above still passes — the two
/// tests are not accidentally redundant, each catches exactly one direction.
@Test @MainActor func aHandleToAProducedElementReportsValid() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    pass.emitAXNode(AXNode(role: .text, label: "Hi"), at: rect(0, 0, 40, 20),
                    id: eid("b"), children: [])

    let node = try #require(frame.axNode(for: eid("b")))
    #expect(node.isValid, "just emitted, and never swept without being re-marked — must be valid")

    // A sweep that DOES re-mark it (a second emission before the sweep, the
    // ordinary "produced again next frame" case) must keep it valid — not
    // only "valid before the first sweep ever runs", which a narrower
    // implementation could satisfy by accident (e.g. defaulting `isValid` to
    // `true` and never actually consulting `StateTable.isLive` at all).
    pass.emitAXNode(AXNode(role: .text, label: "Hi"), at: rect(0, 0, 40, 20),
                    id: eid("b"), children: [])
    frame.stateTable.sweep()
    let stillLive = try #require(frame.axNode(for: eid("b")))
    #expect(stillLive.isValid, "produced again before the sweep — must still report valid")
}

/// An id that was never emitted at all is `nil`, not a tombstone — the
/// differential that proves `axNode(for:)` distinguishes "genuinely never
/// existed" from "existed and stopped", the same distinction `StateTable`
/// already draws between an absent key and a tombstoned one.
@Test @MainActor func aHandleThatWasNeverEmittedIsNilNotATombstone() {
    let frame = bareFrame()
    #expect(frame.axNode(for: eid("never")) == nil)
}

/// `emitAXNode` normalises `.isValid` to `true` on the way in, regardless of
/// what the input `node` carried — the line at `Frame.swift`'s `resolved.isValid
/// = true`. Constructed via `@testable`'s access-widening (this file's own
/// established use of it, same as `anEmittedNodesFrameIsTheResolvedBoundsNotWhateverItDeclared`'s
/// stale `.frame`/`.children`) to hand `emitAXNode` a node whose `isValid` is
/// already `false` — the one shape that can tell "normalises unconditionally"
/// apart from "the field just defaults to `true` and nothing touches it",
/// which is what left the line itself uncovered until this test.
@Test @MainActor func emitAXNodeNormalisesIsValidToTrueRegardlessOfInput() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    var stale = AXNode(role: .button)
    stale.isValid = false

    let resolved = pass.emitAXNode(stale, at: rect(0, 0, 10, 10), id: eid("c"), children: [])
    #expect(resolved.isValid, "emitAXNode must normalise isValid to true on the way in")
    let fromDict = try #require(frame.axNodes[eid("c")])
    #expect(fromDict.isValid, "the same normalisation on the copy Frame.axNodes stores")
}

/// **The invariant `axRetentionSlot`/`focusRetentionSlot`/`animRetentionSlot`/
/// `animColorRetentionSlot` are all built to preserve — pinned here because
/// nothing else does.** The seven retention slot names (`"$ax"`, `"$focus"`,
/// `"$anim"`, `"$state\(n)"`, `"$anim-content"`, `"$anim-viewport"`,
/// `"$anim-color"`) are mutually distinct at
/// construction (`GlobalElementID.child(of:at:name:)` makes any two distinct
/// `.named` strings distinct components under the same parent), but nothing
/// enforced that until this test: renaming `axRetentionSlot`'s `"$ax"` to
/// `"$focus"` reddened 0 of 777 before this test existed.
///
/// **Renamed from `theThreeRetentionSlotsAreMutuallyDistinct` and extended to
/// four by the animation milestone's Task 3 (ruling J,
/// `docs/superpowers/specs/2026-09-03-animation-design.md` §6/§7 item 10):**
/// `$anim` is a fourth reserved child slot (`AnimatedStyle.swift`) and
/// inherits this exact collision risk — guarding three names while leaving a
/// fourth open would read as though the fourth were safe.
///
/// **Extended to six by Task 4's own fix round.** `ScrollView.requestLayout`
/// registers two nodes from one element id and cannot pass that id to
/// `animated(_:_:for:)` twice without colliding the two nodes' fields under
/// one `$anim` slot (`animRetentionSlot(for:)` derives one slot per id, not
/// per call), so it names each node's id `"$anim-content"`/`"$anim-viewport"`
/// — two MORE reserved names carrying the identical unguarded risk.
/// `ScrollView.swift`'s own comment already says they are "on the same
/// footing as `$state`, `$focus` and `$ax`" — this is what actually puts
/// them on it.
///
/// **Extended to seven by Task 4b.** `$anim-color` (`AnimatedColor.swift`) is
/// the paint-side colour helper's own slot, a direct named child of the
/// element's id exactly as `$anim` is. Colour could not go through `$anim`:
/// that helper runs in `LayoutPass`, which deliberately has no theme, and two
/// `ColorToken`s interpolate through their theme-resolved `Hsla` (spec §4's
/// third rule).
///
/// **Those two are id PREFIXES, not slots, and this doc said "both DIRECT
/// children of the element's own id, on the same level as
/// `$state\(n)`/`$focus`/`$ax`/`$anim`" until Task 4's fix round 2 checked
/// it against the code.** Nothing is ever stored at `$anim-content` itself:
/// `ScrollView` passes `scrollViewContentAnimID(for: id)` *to*
/// `animated(_:_:for:pass:)`, which derives `animRetentionSlot(for:)` from
/// it, so the stored value lives at `child(child(id, "$anim-content"),
/// "$anim")` — a **grandchild**, one level deeper than the other four. This
/// test is unaffected and its subject is unchanged: a hand-written
/// `.id("$anim-content")` child mints the identical prefix, and that child's
/// own `$anim` slot then collides with the `ScrollView` content node's, so
/// the hazard is equivalent and the six names must still be mutually
/// distinct. Only the shape was described wrongly, in this doc and in
/// CLAUDE.md's own reserved-name paragraph, which is corrected in the same
/// pass.
/// Reproduces the review's own probe: one element that is focused,
/// AX-emitting, AND mid-animation, across the same two-sweep shape
/// `Frame.render` uses (confirm, then vanish). `focusRetentionSlot`/
/// `axRetentionSlot`/`animRetentionSlot` are all `private`/file-private —
/// unreachable even through `@testable` — so this drives the three
/// PRODUCTION paths that read each slot back (`resolveFocus()` for `$focus`,
/// `axNode(for:)` for `$ax`, `animated(_:_:for:pass:)` for `$anim`) rather
/// than the key constructors themselves.
///
/// **Measured to redden under the collision it guards against**: renaming
/// `Frame.axRetentionSlot`'s `"$ax"` to `"$focus"` makes the `AXNode` written
/// last (`emitAXNode` runs after `registerHandlers`, matching `Box.prepaint`'s
/// own order) clobber the `Bool` `registerHandlers` wrote — `resolveFocus()`'s
/// `peek(…, as: Bool.self)` then reads `nil` from the stored `AXNode` and
/// clears focus, which reddens the assertion below. See this task's fix-round
/// report for the exact run.
///
/// **The `$anim` half was originally written to a SETTLED value and it was
/// wrong — corrected in the same fix round that found it, not just in the
/// report (practices doc mechanism 1).** A settled `$anim` read (the
/// original shape: change with no transaction, read back the plain
/// declared value) is indistinguishable from a FULLY CLOBBERED slot: under a
/// `"$anim"` → `"$focus"` collision, `animated`'s `peek` returns `nil` (its
/// map was overwritten by `$focus`'s `Bool`), which this helper treats as a
/// first sighting and returns the **declared** value unchanged — exactly
/// what an intact settled slot also returns. Measured: the rename mutation
/// reddened **0 of 837** against the original settled-readback shape, the
/// identical silent-miss shape ruling `TB-R` records for `"$ax"` → `"$focus"`.
/// The fix is to assert a value only an INTACT slot can produce: start the
/// animation under a real transaction and read back MID-FLIGHT, at a
/// timestamp the animation has not yet finished at. A clobbered slot has no
/// interpolation state to resume — it can only ever answer with the
/// currently-declared value (100 here), never the true interpolated one
/// (50) — so the two cases are now observably different. See this task's
/// fix-round report for the reproduced rename-mutation count against this
/// corrected shape.
@Test @MainActor func theSevenRetentionSlotsAreMutuallyDistinct() throws {
    let table = StateTable()
    let theme = slotProbeTheme()
    let id = eid("shared")
    // `ScrollView`'s own two extra names — direct NAMED children of `id`,
    // exactly where `$state\(n)`/`$focus`/`$ax`/`$anim` live.
    let contentAnimID = scrollViewContentAnimID(for: id)
    let viewportAnimID = scrollViewViewportAnimID(for: id)

    // Frame 1: `id` becomes `focusedElement`, the subject of an `AXNode`
    // emission, AND starts a real, still-running animation, in
    // `Box.prepaint`'s own order (`animated` runs earlier still, inside
    // `requestLayout`, before `registerHandlers`/`emitAXNode` in `prepaint`).
    // The FIRST `animated` call (flexGrow 0, no transaction) is a plain
    // first-sighting baseline — transaction-independent by construction, so
    // it needs no special shape. The SECOND is what makes this test able to
    // tell an intact slot from a clobbered one: a linear animation begun at
    // this frame's timestamp (0) and read back half a second later.
    let frame1 = sharedFrame(table, focusedElement: id, theme: theme)
    var layoutPass1 = LayoutPass(frame: frame1)
    var style = Style()
    style.flexGrow = 0
    _ = animated(style, Decoration(), for: id, pass: &layoutPass1)
    style.flexGrow = 100
    withAnimation(.linear(duration: 1)) {
        _ = animated(style, Decoration(), for: id, pass: &layoutPass1)
    }

    // The two `ScrollView`-node slots, exercised the identical way, under
    // named children of the same `id` — the collision this extension exists
    // to rule out. Distinct targets (42 vs -7) so a collision between the
    // two of THEM, not only against the original four, would also show up
    // as a wrong halfway value below.
    var contentStyle = Style()
    contentStyle.flexShrink = 0
    _ = animated(contentStyle, Decoration(), for: contentAnimID, pass: &layoutPass1)
    contentStyle.flexShrink = 42
    withAnimation(.linear(duration: 1)) {
        _ = animated(contentStyle, Decoration(), for: contentAnimID, pass: &layoutPass1)
    }

    var viewportStyle = Style()
    _ = animated(viewportStyle, Decoration(), for: viewportAnimID, pass: &layoutPass1)
    viewportStyle.flexGrow = -7
    withAnimation(.linear(duration: 1)) {
        _ = animated(viewportStyle, Decoration(), for: viewportAnimID, pass: &layoutPass1)
    }

    // The SEVENTH name (Task 4b): `$anim-color`, the paint-side colour
    // helper's own slot under the same `id`. Same shape as the `$anim` arm —
    // a real transaction begun at this frame's timestamp, read back
    // mid-flight — because a settled colour readback is indistinguishable
    // from a fully clobbered slot for the identical reason ruling `TB-R`
    // records: a clobbered slot reads as a first sighting and answers with
    // the currently-declared colour, which is exactly what an intact settled
    // slot answers too.
    var colorPass1 = PaintPass(frame: frame1)
    _ = animatedColor(.background, for: id, pass: &colorPass1)
    withAnimation(.linear(duration: 1)) {
        _ = animatedColor(.accent, for: id, pass: &colorPass1)
    }

    let pass1 = PrepaintPass(frame: frame1)
    var handlers = Handlers()
    handlers.isFocusable = true
    pass1.registerHandlers(handlers, at: rect(0, 0, 10, 10), id: id)
    pass1.emitAXNode(AXNode(role: .button, label: "Go"), at: rect(0, 0, 10, 10),
                     id: id, children: [])
    table.sweep()

    // Frame 2: nothing touches `id` at all — it stopped being produced.
    table.sweep()

    // Frame 3: reads all five slots back through their own production
    // consumers, half a second after the animations started — still
    // mid-flight (`linear(duration: 1)` at elapsed 0.5 == halfway).
    let frame3 = sharedFrame(table, focusedElement: id, timestamp: 0.5, theme: theme)
    frame3.resolveFocus()
    #expect(frame3.focusedElement == id, """
            the $focus retention slot must still hold its Bool — a collision with \
            $ax, $anim, $anim-content or $anim-viewport would clobber it and clear focus here
            """)

    let tombstoned = try #require(frame3.axNode(for: id),
        "the $ax retention slot must still hold its AXNode")
    #expect(!tombstoned.isValid && tombstoned.role == .button && tombstoned.label == "Go",
            "the AXNode data must be the one this test wrote, not a Bool or animation state coerced through Any")

    var layoutPass3 = LayoutPass(frame: frame3)
    let (out3, _) = animated(style, Decoration(), for: id, pass: &layoutPass3)
    #expect(out3.flexGrow == 50, """
            the $anim retention slot must still hold its own MID-FLIGHT state (50, halfway \
            through a linear(duration: 1)) — a collision with $focus or $ax clobbers the map \
            outright, which reads as a first sighting and returns the declared value (100) \
            instead; only an intact slot can produce 50 here
            """)

    let (contentOut3, _) = animated(contentStyle, Decoration(), for: contentAnimID, pass: &layoutPass3)
    #expect(contentOut3.flexShrink == 21, """
            the $anim slot derived from the $anim-content PREFIX (child(child(id, "$anim-content"), \
            "$anim"), a grandchild — not a sibling of $state/$focus/$ax/$anim) \
            must still hold its own mid-flight state (21, halfway from 0 to 42) — a collision with \
            any of the other five slots reads as a first sighting and returns 42 instead
            """)

    let (viewportOut3, _) = animated(viewportStyle, Decoration(), for: viewportAnimID, pass: &layoutPass3)
    #expect(viewportOut3.flexGrow == -3.5, """
            the $anim-viewport retention slot must still hold its own mid-flight state (-3.5, \
            halfway from 0 to -7) — a collision with any of the other five slots (including \
            $anim-content, its own sibling) reads as a first sighting and returns -7 instead
            """)

    // The seventh. Hand-computed from `slotProbeTheme`, by the arithmetic the
    // helper is meant to perform rather than by reading it back out of the
    // helper (taxonomy shape 12):
    //   background (0.10, 0.20, 0.80) -> accent (0.90, 0.70, 0.30)
    //   midpoint (0.50, 0.45, 0.55): max=0.55 (b), min=0.45 (g), delta=0.10
    //       l = 0.50, s = 0.10, h = (0.50 - 0.45)/0.10 + 4 = 4.5, /6 = 0.75
    // A clobbered slot answers with the DECLARED `accent` instead
    // (l = 0.60, s = 0.75, h = 0.111111), so every component separates the
    // two cases by a wide margin.
    var colorPass3 = PaintPass(frame: frame3)
    let colorOut3 = try #require(animatedColor(.accent, for: id, pass: &colorPass3))
    #expect(abs(colorOut3.l - 0.50) < 2e-4 && abs(colorOut3.s - 0.10) < 2e-4
            && abs(colorOut3.h - 0.75) < 2e-4, """
            the $anim-color retention slot must still hold its own MID-FLIGHT state \
            (h 0.75, s 0.10, l 0.50 — halfway through a linear(duration: 1)); a collision with \
            any of the other six slots reads as a first sighting and answers with the declared \
            accent (h 0.111111, s 0.75, l 0.60) instead. Got h \(colorOut3.h) s \(colorOut3.s) \
            l \(colorOut3.l)
            """)
}

// MARK: - `AXNode.isEmpty`

/// The default value is empty and a declared one is not — `Handlers`' own
/// "empty means not a hit target" rule, checked at the type it was copied to.
@Test func aDefaultAXNodeIsEmptyAndADeclaredOneIsNot() {
    #expect(AXNode().isEmpty)
    #expect(!AXNode(label: "anything").isEmpty)
    #expect(!AXNode(role: .button).isEmpty)
}

// MARK: - Wired through a real `Box`, via a real `Frame.render`

/// A `Box` that declared an `AXNode` emits it, at its own resolved bounds,
/// under its own root id — the end-to-end path through `Box.prepaint` rather
/// than `PrepaintPass` driven by hand.
@Test @MainActor func aBoxWithADeclaredAXNodeEmitsItAtItsOwnResolvedBounds() throws {
    var box = Box(style: sized(40, 20), content: EmptyGroup())
    box.elementID = ElementID("root")
    box.handlers.axNode = AXNode(role: .button, label: "Go")

    let frame = bareFrame()
    frame.render(&box)

    // Named explicitly, rather than left `nil`, so this id is `.named("root")`
    // and cannot coincide with a mutation that hard-codes the unnamed root's
    // own key, `.positional(0)` — an unnamed `Box()` would make this test pass
    // under such a mutation by accident, which a probe found.
    let rootID = GlobalElementID.child(of: nil, at: 0, name: box.elementID)
    let node = try #require(frame.axNodes[rootID])
    #expect(node.role == .button && node.label == "Go")
    #expect(node.frame == rect(0, 0, 40, 20), "the box's own resolved bounds")
    #expect(node.children.isEmpty,
            "Box cannot yet enumerate its own children's ids — see Box.prepaint's own comment")
}

/// A `Box` that declared nothing accessible emits no node at all — the
/// positive control for the gate above, and the differential the "make
/// emission a no-op" mutation in this task's brief is checked against from
/// the other side.
@Test @MainActor func aBoxWithNoDeclaredAXNodeEmitsNothing() {
    var box = Box(style: sized(40, 20), content: EmptyGroup())

    let frame = bareFrame()
    frame.render(&box)

    #expect(frame.axNodes.isEmpty, "no AXNode was declared, so none should be emitted")
}

private func sized(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: .length(.pixels(px(w))), height: .length(.pixels(px(h))))
    return s
}

// MARK: - Virtualization: a `List`'s logical count vs. its realized rows (design spec §9, Task 7)

/// A row's own datum for the virtualization tests below — an `Int` id is
/// enough, on `ListTests.swift`'s own `Item` footing.
private struct AXListRow: Identifiable {
    let id: Int
}

/// A minimal row element that emits its OWN `AXNode` during prepaint —
/// deliberately, since `List`'s row-wrapping `Box` (`List.requestLayout`'s
/// `rowStyle`) declares no `AXNode` of its own. This task's brief rules that
/// `AXNode.children` cannot observe the realized set (Task 5's review found
/// reconstructing child order from ids provably ambiguous) and that the
/// realized set must instead be read off `Frame.axNodes` — the true set of
/// nodes actually emitted this frame. That is only observable if SOMETHING
/// per row emits a node, so this fixture opts every row in explicitly; a
/// production `List` does not do this for its rows on its own (only for its
/// own container node — see `List.requestLayout`), and this fixture is not
/// claiming otherwise.
private struct AXListLeaf: Element {
    let datum: AXListRow
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        (pass.requestNode(style: Style(), children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {
        pass.emitAXNode(AXNode(role: .text, label: "Row \(datum.id)"), at: bounds,
                        id: id, children: [])
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// Runs the full three-phase pipeline over `list` with `context` pushed onto
/// `frame`'s scroll-context stack before `requestLayout` runs —
/// `ListTests.swift`'s own `renderWindowed`, reproduced here because that one
/// is `private` to its own file.
@MainActor
private func renderListWindowed<Data: RandomAccessCollection, Row: Element>(
    _ list: inout List<Data, Row>, context: ScrollContext
) -> Frame where Data.Element: Identifiable {
    let frame = bareFrame(600)
    frame.pushScrollContext(context)
    let rootID = GlobalElementID.child(of: nil, at: 0, name: list.elementID)
    var layoutPass = LayoutPass(frame: frame)
    let (root, layoutState) = list.requestLayout(rootID, pass: &layoutPass)
    frame.popScrollContext()
    var state = layoutState

    frame.computeRootLayout(root: root)
    let rootBounds = frame.bounds(of: root)

    var prepaintPass = PrepaintPass(frame: frame)
    var prepaintState = list.prepaint(rootID, bounds: rootBounds, layout: &state,
                                      pass: &prepaintPass)
    var paintPass = PaintPass(frame: frame)
    list.paint(rootID, bounds: rootBounds, layout: &state, prepaint: &prepaintState,
              pass: &paintPass)
    return frame
}

/// **This task's own step 1 test, and the ruling that corrects its brief.**
/// The brief asked to assert "its realized children are ~17" through
/// `AXNode.children` — impossible, per this task's ruling above `AXNode.children`
/// is always `[]` this milestone. The realized set is read off `Frame.axNodes`
/// instead: the count of `.text`-role nodes actually emitted this frame, which
/// only the rows inside the window contribute (`AXListLeaf.prepaint` above).
///
/// 500 rows at `rowHeight` 28, offset 140 (row 5's top), viewport 364 (13
/// rows): window is rows 3..<20 — 17 rows, by the identical arithmetic
/// `aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan`
/// (`ListTests.swift`) already pins for this milestone's `visibleRange`.
///
/// **Both halves are asserted, and they are different numbers** — the ruling's
/// own requirement: a test that only checks 500 would pass against a `List`
/// that realized every row, which is exactly the regression windowing exists
/// to prevent.
@Test @MainActor func aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount() throws {
    let data = (0..<500).map { AXListRow(id: $0) }
    var list = List(data, rowHeight: px(28)) { AXListLeaf(datum: $0) }
    list.elementID = ElementID("list")

    let context = ScrollContext(offset: 140, viewportExtent: 364, axis: .vertical)
    let frame = renderListWindowed(&list, context: context)

    let listID = GlobalElementID.child(of: nil, at: 0, name: list.elementID)
    let listNode = try #require(frame.axNodes[listID], "the List's own container node")
    #expect(listNode.role == .container)
    #expect(listNode.logicalCount == 500,
            "the FULL logical count — spec §9's '500' half of '3 of 500'")

    let realizedRowCount = frame.axNodes.values.filter { $0.role == .text }.count
    #expect(realizedRowCount == 17,
            "13 rows intersecting the 364pt viewport, widened by overscan 2 on each side")

    #expect(listNode.logicalCount != realizedRowCount,
            """
            the two halves of spec §9's '3 of 500' must be different numbers — a List \
            that realized every row would make this equal 500 and pass the two checks \
            above for the wrong reason
            """)
}

/// The positive control for the mutation the brief names in Step 5: report
/// the realized count as the logical count. If `List.requestLayout` set
/// `logicalCount` to `rows.count` (what was actually built) instead of
/// `count` (`data.count`), this test would read `logicalCount == 17` and
/// still be internally consistent with `realizedRowCount`, so a same-file
/// mutant needs a second, undisturbed signal — `logicalCount` is checked here
/// against the raw `data.count` literal (500) rather than against
/// `realizedRowCount`'s own value, which is what actually catches that
/// mutant (see this task's report for the mutation run).
@Test @MainActor func aVirtualizedListsLogicalCountIsTheFullDataCountEvenWhenEveryRowFits() throws {
    let data = (0..<5).map { AXListRow(id: $0) }
    var list = List(data, rowHeight: px(28)) { AXListLeaf(datum: $0) }
    list.elementID = ElementID("list")

    // No scroll context at all: `visibleRange` builds everything, so this is
    // the "realizes every row" shape — logicalCount must still read 5, not
    // merely "whatever was built", which this small fixture cannot tell
    // apart on its own without the differential test above.
    let frame = bareFrame(600)
    frame.render(&list)

    let listID = GlobalElementID.child(of: nil, at: 0, name: list.elementID)
    let listNode = try #require(frame.axNodes[listID])
    #expect(listNode.logicalCount == 5)
    let realizedRowCount = frame.axNodes.values.filter { $0.role == .text }.count
    #expect(realizedRowCount == 5, "no scroll context — every row is built")
}

/// **A mutation gap found and closed, not merely reported.** Rewriting
/// `List.requestLayout`'s `if listHandlers.axNode.isEmpty` guard to `if true`
/// — always overwrite with `role: .container` — reddened NOTHING in the
/// 781-test suite before this test existed: nothing anywhere sets
/// `list.handlers.axNode` before rendering, so the guard's "already declared"
/// branch was never exercised. `handlers` is a normal `public var` on `List`
/// (there is no `.axNode(_:)` modifier yet — `AXNode.swift`'s own doc), so a
/// caller CAN reach in and declare a role/label today; this pins that a
/// caller's own declaration survives `List` adding `logicalCount`, rather
/// than being silently clobbered to `.container`.
@Test @MainActor func aCallerDeclaredAXNodeOnAListSurvivesLogicalCountBeingAdded() throws {
    let data = (0..<3).map { AXListRow(id: $0) }
    var list = List(data, rowHeight: px(28)) { AXListLeaf(datum: $0) }
    list.elementID = ElementID("list")
    list.handlers.axNode = AXNode(role: .button, label: "Custom")

    let frame = bareFrame(600)
    frame.render(&list)

    let listID = GlobalElementID.child(of: nil, at: 0, name: list.elementID)
    let listNode = try #require(frame.axNodes[listID])
    #expect(listNode.role == .button && listNode.label == "Custom",
            "the caller's own declared role/label must survive, not be overwritten to .container")
    #expect(listNode.logicalCount == 3, "logicalCount is still added on top")
}

// MARK: - `AXNode.frame`/`.children`/`.isValid` are unreachable from a REAL external caller
//
// Every test above imports `MetalUI` with `@testable`, which grants this whole
// file `internal`-level access — so it could still write `n.frame = …` despite
// `internal(set)`, and would prove nothing about the actual public surface an
// app author sees. These compile a fixture against the *built module*,
// imported plainly, the way `ErasureCompileGuards.swift` and
// `PhaseSeparationTests.swift` pin every other "this must not compile" claim
// in this repo (ruling EP-1) — `@testable`'s access widening cannot reach in
// here at all. `isValid` joins `frame`/`children` here on Ruling N's own
// footing (this milestone's Task 5 review): a `@testable`-only test cannot
// demonstrate ANY access-level narrowing, `isValid` is `internal(set)` exactly
// like its two neighbours, and this task's own tests above (all `@testable`)
// prove nothing about whether a plain importer could set it.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — AXNode guard skipped"

/// The load-bearing positive: a plain, non-`@testable` importer can still
/// construct and read an `AXNode` at all, `isValid` included. Without this,
/// the negatives below would pass just as well if `AXNode` did not exist, or
/// `MetalUI` failed to import, or `role`/`label` were also unreachable — none
/// of which is the claim this trio exists to isolate.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImporterCanConstructAndReadAnAXNode() throws {
    let result = try typecheck("""
        let node = AXNode(role: .button, label: "Go")
        _ = node.frame
        _ = node.children
        _ = node.isValid
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "a plain importer must be able to construct and READ an AXNode:\n\(result.output)")
}

/// The negative: a plain importer cannot WRITE `.frame` — the public
/// initializer takes no `frame:` parameter and the property's setter is
/// `internal`, so this must fail exactly the way writing to any other
/// module's `internal(set)` property would.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImporterCannotSetAnAXNodesFrame() throws {
    let result = try typecheck("""
        var node = AXNode(role: .button)
        node.frame = node.frame
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "`frame` is `internal(set)` — a plain importer must not be able to assign it")
    // Verified against the real diagnostic rather than guessed: `swiftc` says
    // "cannot assign to property: 'frame' setter is inaccessible" — checked
    // here so a future change that breaks the fixture for an unrelated reason
    // (a typo, `AXNode` losing `role`) fails this assertion rather than
    // passing for the wrong cause, `messages`-not-`output`'s own reason
    // (`TypecheckResult.messages`'s own doc).
    #expect(result.messages.contains("setter is inaccessible") && result.messages.contains("frame"),
            "must fail because the setter is inaccessible, not for an unrelated reason:\n\(result.output)")
}

/// The same negative, for `.isValid` — this task's own field, and the one
/// `Ruling N` says a `@testable` test cannot demonstrate on its own.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImporterCannotSetAnAXNodesIsValid() throws {
    let result = try typecheck("""
        var node = AXNode(role: .button)
        node.isValid = node.isValid
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "`isValid` is `internal(set)` — a plain importer must not be able to assign it")
    #expect(result.messages.contains("setter is inaccessible") && result.messages.contains("isValid"),
            "must fail because the setter is inaccessible, not for an unrelated reason:\n\(result.output)")
}
