# Absolute positioning and overlays — decisions taken during execution

Rulings from the milestone that made `Style.position` and `Style.inset` live and gave
the framework its first portal, `Deferred`. Prefixed **`AP-`** and **lettered**
(`AP-A`, `AP-B`, …) per this repo's convention for `CL-`/`CS-`/`SI-`/`ST-`/`TX-` — a
bare `AP-3` is a typo, not a citation. Read alongside
`docs/superpowers/specs/2026-08-28-absolute-positioning-design.md` (the design this
milestone built), CLAUDE.md's declared-but-inert table (which loses two rows here and
gains one) and its divergence list (which gains 9, 10 and — from the whole-branch
review — 11, the other direction of 10's seam).

Two halves that ship together and share no code: **absolute positioning** decides where
a box sits, **layer hoisting** decides what it paints above. The design keeps them
separate and so does this document — `AP-A`…`AP-F` are the engine, `AP-G`…`AP-K` are
paint, `AP-L` is the public surface both reach through, `AP-M` is the declared-but-inert
row `Position.relative` takes as `position` leaves that table, and `AP-N` was added by
the whole-branch review — the scroll-routing layer key that made the prepaint hoist live.

---

## AP-A — `Position` needs three cases, and `.static` is the default

**The choice.** `Position` gained a `.static` case, made first in declaration order, and
`Style.position`'s default moved from `.relative` to `.static`.

**Why two cases could not work.** An `.absolute` box is placed against the nearest
ancestor whose `position` is not `.static`. With only `relative`/`absolute`, *every*
ancestor qualifies, so an absolute box can never reach past its immediate parent — a
modal buried four levels down could not cover the window, which is the one thing the
milestone exists to make possible. `.static` is what makes "skip this ancestor"
expressible, and `.relative` is then the opt-in: it makes a box a containing block
without moving it.

**What it costs if wrong.** This is a semantic change to a *live* property, and at the
moment it was made nothing in the repo was `.absolute` — so the change was inert and
the risk was that "inert" was assumed rather than measured. It was measured: zero
goldens moved, and the whole suite passed at 540. Had it not been inert, every ancestor
chain in the corpus would have shifted at once.

**One assertion moved with it, and it was wrong before rather than after.**
`StyleTests`' `defaultStyleMatchesCSSInitialValues` asserted `s.position == .relative`.
CSS's actual initial value for `position` is `static`, so that line had been false
against the standard it names since it was written; the default-move is what made it
fail. Corrected in the same commit rather than worked around.

## AP-B — the flow filter goes in *both* collection sites, and neither is redundant

**The choice.** `collectItems` (the flex path) and `layOutStack`'s item loop (the stack
path) each gained `position != .absolute` alongside the `display != .none` they already
had. Absolute children stay in `tree.children` and are placed by a separate pass in
`placeNode`, after the container's own size is known — an inset resolves against the
containing block, which must be sized first.

**Why not one shared filter.** The two sites enumerate a container's children for two
different algorithms with two different accumulations (§9.2's flex base sizes against
`layOutStack`'s independent max-over-children), and this milestone did not have licence
to unify them — `ST-B` had already ruled the two item types apart for the same reason.

**Measured, and this is the whole argument for two tests instead of one.** Filtering
only in `collectItems` reddens exactly `anAbsoluteChildDoesNotContributeToAStacksSize`;
filtering only in `layOutStack` reddens exactly the two flex tests. Each site's fix is
detected only by the test that exercises *that* site. Inverting the comparison at both
sites — dropping every in-flow child instead — reddens **214 tests and 1329
expectations** out of 541, which is what says the filter is load-bearing rather than
decorative.

**What it costs if wrong.** A half-fix is invisible in the half of the framework you
are not looking at: a `Stack` would silently size itself to a modal that is supposed to
contribute nothing, and no flex fixture in the corpus could see it.

## AP-C — the containing block is threaded downward, and it is the ancestor's padding box

**The choice.** `placeNode` computes a `ContainingBlock { origin, size }` for its own
descendants and passes it down; a node replaces the threaded value with its own box
only when its `position` is not `.static`. There is no parent pointer on `LayoutTree`
and no upward walk at placement time.

**Why not walk up from the absolute child.** `LayoutTree` has children but not parents,
so an upward walk would mean adding a parent link to every node for the benefit of the
rare absolute one — and it would have to re-derive each ancestor's resolved padding
box, which is only known *during* that ancestor's own layout. Threading downward gets
the value from the one place it already exists, at the cost of one struct in
`placeNode`'s signature and in `positionItems`/`positionStackItems`, which pass it
through unchanged.

**The padding box, not the content box or the border box.** `childOrigin` is already
the content box's absolute origin (leading padding + border), so the padding box is
that expanded back out by **padding alone** — border is what separates the two. The
resolved padding comes from `layOutChildren`, which had already computed it and thrown
it away; `ContainerLayout` now carries it rather than `placeNode` re-resolving
`Style.padding` against a basis that is easy to get wrong. That last point is CLAUDE.md's
percentage-inset constraint applied at the one site where it does hold.

**What it costs if wrong.** Every absolute child shifts by the ancestor's border width
— a small, uniform error that reads as a rounding problem rather than as a rule
mistake. Using the content box instead reddens **two** tests and four
expectations: `theContainingBlockIsThePaddingBoxNotTheBorderBox` (by 3 on each
axis) and `absContainingBlockSkipsStaticMatchesWebKit` (by 5 on each axis),
whose fixture Task 5 added after this ruling was first written.

**This paragraph said "exactly `theContainingBlockIsThePaddingBoxNotTheBorderBox`"
until the whole-branch review re-measured it**, and the under-count is the
CS-N/SI-H staleness shape rather than a new fact: the number was taken before a
later task added a second test sensitive to the same line, so it was true when
written and stale by the end of the milestone. Both tests are named here rather
than only counted, which is the half of CS-N that survives a re-measurement —
a name still identifies the pin after the count moves.

**A brief's own fixture was impossible under this rule, which is worth carrying.**
Task 3's brief expected `abs.x == 5` from a containing block with `padding: 5px` and no
border. Padding never moves a containing block's own origin — it moves where in-flow
content starts, which is a different thing — so with zero border the padding box
coincides with the border box at (0, 0). The fixture was fixed to use `border: 5px`,
which preserves every number the brief asserted, since in-flow positions depend on
padding + border combined and only the containing block's origin depends on border
alone.

## AP-D — insets resolve per axis, and the implementation must not cite CLAUDE.md's constraint

**The choice.** `left`/`right` resolve percentages against the containing block's
**width**; `top`/`bottom` against its **height**. Position, per axis: the leading inset
wins whenever it is given, regardless of the trailing one.

**Why the "leading wins" rule rather than a special case for over-constrained boxes.**
CSS says an over-constrained absolute box (both insets plus a size) ignores `right` in
LTR. Applying "leading wins" uniformly *is* that rule, and it falls out of the sizing
branch that already ignores the trailing inset once a size is declared — one read for
both, instead of a size branch and a separate over-constrained branch that have to
agree with each other.

**The documentation trap, named here because it was live during execution.**
CLAUDE.md's Build section said "a percentage inset resolves against the CONTAINING
BLOCK's width — not the box's own width, and not a height." That sentence is correct
for what it was written about (`padding` and `border`, where CSS does resolve every
percentage against width) and wrong for `Style.inset` on two of four edges, while using
the word "inset". The design spec instructed the implementation not to cite it, and
this milestone's Task 8 narrowed the sentence to name padding and border. Following it
literally reddens exactly `percentageInsetsResolveAgainstWidthForXAndHeightForY` and
`abs_percent_insets_nonsquare` — and only because those two are built on a **non-square**
containing block. On a square one the two bases give the same number and the mistake is
invisible, which is the uniformity hazard `ST-E` and divergence 6 were both produced by.

**What it costs if wrong.** Every vertical percentage inset in the framework is off by
the ratio of the containing block's width to its height — correct on square containers,
wrong everywhere else, and silent in both.

## AP-E — an absolute box's declared size is resolved before its content is measured

**The choice.** `placeAbsolute` resolves a non-`auto` `Style.size` from the node's own
style first, clamped by its own min/max, and reaches `measureNode` only for an axis
that is genuinely `auto` *and* not bounded by two insets.

**Why this is a ruling and not a bug fix.** It was shipped as a bug — Task 3 called
`measureNode(known: .unspecified, …)` unconditionally, and for a childless node with no
`MeasureFunction` that takes `measureNode`'s container branch and returns
`contentSize + edges`, which is 0 for an empty container. `Box().width(20)` placed
absolutely measured **0×0**. Nothing reddened, because the three tests that existed
asserted only `x`/`y`. The rule it now follows is the one every other
constant-substituting site in `FlexEngine.swift` follows (`resolveNodeSize` for a flex
item's cross axis): the node's own style answers first, and `measureNode` answers only
what the style left open.

**What it costs if wrong.** An absolutely-positioned box with a declared size paints
nothing, at the right coordinates — the failure mode CLAUDE.md's EP-8 entry calls a
*louder* one than a wrongly-filling rectangle, but only if someone is looking.

## AP-F — static position is cut, and the divergence is recorded rather than hidden

**The choice.** All-`auto` insets place a box at the containing block's **padding-box
origin**. CSS places it at its *static position* — where it would have sat had it
stayed in flow.

**Why not implement it.** Static position means laying the box out in flow, recording
where it landed, and then removing it: a second pass over exactly the children the
first pass filtered out, for a case modals, popovers and tooltips do not use — all
three set insets.

**Measured against the oracle rather than assumed** (a throwaway probe, deliberately not
committed): a 40×20 in-flow sibling followed by an inset-less 20×10 absolute box in a
200×100 `position: relative` root gives **WebKit (0, 20)** and **this engine (0, 0)**.
Pinned by `allAutoInsetsPlaceAtTheContainingBlockOriginNotTheStaticPosition`, and
recorded as CLAUDE.md's divergence 9.

**No fixture and no golden encode it, deliberately** — on the footing of BM-4, FS-3 and
TX-H. A golden would record this engine's answer as correct and a future fix should
move nothing in the corpus.

**What it costs if wrong.** A caller who writes `.position(.absolute)` and no inset
gets a box in the top-left corner of its containing block instead of where it was
sitting. That is a visible, immediate wrong answer rather than a subtle one, which is
part of why it was acceptable to leave.

## AP-G — layer is CPU-side sort metadata, and the parallel array is permuted like `sequence`

**The choice.** `Scene` carries a `layer: [PrimitiveKind: [Int]]` parallel to the
existing `sequence`, and `finalize()`'s sort key grew from `(order, sequence)` to
`(layer, order, sequence)`. The GPU never sees it: no `MetalUIShaderTypes.h` edit, no
`abi_probe` extension, no `sizeof` change.

**Why the sort key and not a second draw pass.** A second pass over hoisted primitives
would need its own draw-list construction, its own run-splitting by kind, and would
have to interleave correctly with the existing one. Ordering is what a layer *means*,
`finalize()` already orders, and adding a leading key component is the whole change.

**The permutation discipline, which is `PF-1` from the clipping milestone repeated.**
`finalize()` reorders the primitives, so every parallel array has to be rebuilt from
the sorted order in the same pass. A `layer` array sorted once but never permuted
passes every single-`finalize()` test — the array is still in emission order after the
first pass — and only shows on a *second* call. `finalizingTwiceWithDistinctLayersStaysStable`
is the only test that can see it.

**What it costs if wrong.** Nothing on a frame; a wrong paint order on the next
`finalize()` of the same scene, which is the shape of bug that survives an entire test
suite.

**Amended 2026-09-10 (lane renderer, item scene-arrays).** The storage changed shape,
not meaning: `Scene` now holds four plain `[Int]` side tables (`rectSequence`,
`glyphSequence`, `rectLayer`, `glyphLayer`) instead of two `[PrimitiveKind: [Int]]`
dictionaries, and `finalize()` rebuilds all four in the same single walk that permutes
`rects`/`glyphs`. The permutation discipline is unchanged. The exclusivity claim above
is no longer true: leaving the layer tables unpermuted reddens
`finalizingTwiceWithDistinctLayersStaysStable` AND
`aSecondFinalizeReproducesTheCapturedOutput` (SceneFinalizeIdentityTests.swift);
leaving the sequence tables unpermuted reddens `finalizingTwiceGivesTheSameDrawList`
and that same test, and neither of the first two reddens the other's mutation.

## AP-H — `Deferred` is a portal: one hoist to one root layer, not a stacking-context system

**The choice.** `Frame.pushLayer()` always pushes the same constant, `Frame.rootLayer = 1`.
Nested `Deferred` all land on layer 1; there is no `z-index`, no ordered layer stack and
no per-subtree stacking context.

**Why.** `z-index` is explicitly out of the design's scope (§1), and a single hoist
covers the motivating features — a modal, a popover, a tooltip each need to be *above
everything*, not above a particular thing. Adding ordered layers later is additive: the
sort key already carries an `Int`.

**Measured:** `pushLayer()` written as `layerStack.append(activeLayer + rootLayer)` —
the natural "nest one deeper" reading — reddens exactly
`nestedDeferredsAllLandOnTheSameRootLayer`.

**What it costs if wrong.** Two nested portals paint in an order nobody declared, and
the framework acquires an implicit stacking model that no document describes.

## AP-I — `pushRootClip()` resets the accumulated scroll offset, not only the clip bounds

**The choice.** `Frame.pushRootClip()` pushes the whole surface **with zero offset**,
where `pushClip` intersects the bounds and *composes* the offset. `Deferred` uses the
former.

**The reasoning.** The clipping-and-scroll milestone established that translation and
clipping are both properties of the emission and are carried on the same stack. A
portal that escaped an ancestor `ScrollView`'s clip but kept its accumulated
translation would be a half-portal: the modal would cover the window on the frame it
appeared and then slide away as the list scrolled underneath it. "Escape the clip" and
"escape the scroll" are the same escape, because they are the same stack entry.

**Why it needed a ruling.** The design spec says only "resets the clip stack to the
whole surface", which names one of the two fields the stack entry holds. Resetting one
and inheriting the other was a live reading of that sentence.

**What it costs if wrong.** A modal that ignores scroll where some caller wanted it to
follow — recoverable by not wrapping that subtree in `Deferred`, since an unhoisted
subtree still tracks its ancestors' scroll exactly as before. The reverse (a portal
that slides) has no workaround at all.

## AP-J — `Deferred` takes exactly one child

**The choice.** `Deferred<Content: Element>`, not `Deferred<Content: ElementGroup>`.
`Deferred { A(); B() }` does not compile; `Deferred { Stack { A(); B() } }` does.

**The reasoning.** `Deferred` is a **paint modifier**, not a layout container. It
contributes no `Style` and no layout node — its resolved node *is* its child's. Two
children would force it to answer how they lay out relative to each other, which is the
question `Column`, `Row` and `Stack` exist to answer, and it would have to answer it
without a `Style` to answer it from. SwiftUI's `.overlay` takes one view for the same
reason.

**What it costs if wrong.** One wrapper container per call site — visible at the call
site, and trivially reversible in either direction later.

## AP-K — `Deferred` derives its content's identity rather than sharing its own

**The choice.** `Deferred.requestLayout` calls
`content.requestGroupLayout(under: id, at: &cursor, pass:)` and returns the single node
that comes back, exactly as `Box` and `ScrollView` do for their children — it does not
forward its own `id` to `content.requestLayout`.

**Why it matters even though `Deferred` adds no node.** Contributing no *layout* node is
not the same as contributing no *identity* component. Forwarding the id outright means a
named child under `Deferred` resolves to `Deferred`'s own positional path rather than to
its own `.named(…)` one, so `Deferred { ScrollView(elementID: "list") { … } }` and
`Box { ScrollView(elementID: "list") { … } }` disagree about where that `ScrollView`'s
scroll offset lives. Pinned by `aNamedChildUnderDeferredResolvesTheSameAsUnderABox`,
which is the differential: the same named element at the same sibling position under
each wrapper must resolve to the same `GlobalElementID`.

**What it costs if wrong.** A `ScrollView`, or any future stateful element, silently
loses its cross-frame state the day someone wraps it in a `Deferred` — and the wrap is
a paint decision, so nothing about the call site suggests state should move.

## AP-L — `position(_:)` and `inset(_:)` land with the rows they delete, and `inset` takes `Dimension`

**The choice.** `StyledElement` gained `position(_:)`, `inset(_ edges: Edges<Dimension>)`
and `inset(_ points: Pixels)` in the same change that deleted `position` and `inset`
from CLAUDE.md's declared-but-inert table.

**Why in the same change.** Ruling AL-6 says the task that makes an API inert records
it in that table and the task that makes one live deletes the row; `StyledElement`'s own
doc comment then read "there are deliberately none for `position`, `inset`, `overflow`
or `aspectRatio`: those four are CLAUDE.md's remaining inert rows." Deleting the rows
without adding the modifiers leaves a live engine feature unreachable from the public
API and a doc comment citing a table that no longer says what it cites; adding the
modifiers without deleting the rows is the exact "a modifier for an inert property"
hazard that comment exists to prevent. They are one edit.

**Why `inset` takes `Dimension` where `margin` takes `Length`.** `margin(_:)`'s
parameter type is what keeps `.auto` — which resolves to 0 rather than to CSS's
behaviour — out of reach, and CLAUDE.md records that as the one inert case a type can
guard instead of document. `inset`'s `.auto` is different: it is the property's
**default**, it is reachable whether or not a modifier accepts it (leaving an edge
unspecified *is* `.auto`), and its behaviour is defined rather than absent. Taking
`Length` would have made partial insets — `left` and `top` only, the common case —
unspellable, since the other two edges have to stay `.auto`.

**What it costs if wrong.** `.auto` becomes writable at a call site where the writer
expects CSS's static position and gets the containing block's origin (divergence 9).
The modifier's doc comment names that divergence for exactly this reason.

## AP-M — `Position.relative` enters the declared-but-inert table as the rows for `position` leave it

**The choice.** Deleting the `position`, `inset` row is not the same as declaring every
case of `Position` implemented. `.relative` does one of the two things CSS gives it: it
makes a box a containing block (live, load-bearing, read by `placeNode`'s `childCB`),
and it does **not** shift the box by its own inset while reserving its in-flow space. A
row now says so.

**Why a row rather than silence.** `position(_:)` takes the whole enum, so
`.position(.relative)` is writable today and lays out identically to `.static` plus the
containing-block effect. CLAUDE.md's own precedent is `AlignItems.baseline`: "a whole
enum leaving is not the same as its every case leaving", and that row is the standing
counter-example this one now joins.

**What it costs if wrong.** A caller writes `.position(.relative).inset(...)` expecting
CSS's relative offset and gets no movement at all, with the box's containing-block role
silently changed underneath them — two surprises where the table would have given one
sentence.

## AP-N — the scroll registration carries its layer, and routing orders by it

**The choice.** `Frame.scrollRegions` gained a fourth field, `layer`, stamped from
`activeLayer` at registration; `Window.applyScroll` picks the candidate with the
greatest `(layer, registration index)` instead of the last one that contains the point.

**Why it is a ruling and not a scope choice.** `PrepaintPass.deferred` already called
`frame.pushLayer()`/`popLayer()`, and its own doc comment justified existing on that
pass by hit-testing — "a tooltip that paints above its siblings while receiving wheel
events as though it were beneath them is worse than one that does neither." Nothing
read the result. **Measured at the whole-branch review: deleting both lines passed all
569 tests**, while the same mutation shape on the paint side is caught immediately
(`pushLayer()` → `activeLayer + rootLayer` reddens `nestedDeferredsAllLandOnTheSameRootLayer`).
Two dead lines behind a stated rationale are the "declared but inert" shape CLAUDE.md's
whole table exists to prevent, and design spec §4.2 puts `deferred` on `PrepaintPass`
*for* this, so the gap was spec non-compliance rather than a deferred decision.

**The failure it closes, reproduced before the fix.** Two overlapping full-window
`ScrollView`s in a stack, the `Deferred` one declared first:

```
PROBE-REGION[0] (0,0) 200x200  id=named("modal")       <- hoisted, paints last
PROBE-REGION[1] (0,0) 200x200  id=named("background")
wheel at (100,100): background offset 37, modal 0
```

The modal painted on top and the scroller beneath took the wheel. Registration order
alone cannot express the fix: a hoisted subtree is still *emitted* where it was
declared, so it can register before something it paints over.

**Ties stay exactly as they were, and that is checked rather than asserted.** The index
is unique, so no two candidates compare equal and `max(by:)`'s tie behaviour is never
reached; within one layer the greatest index is the last registration, which is the rule
`theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove` already pinned at layer 0.
Ordering by layer **alone** reddens that test and the new
`withinOneLayerTheLastRegisteredRegionStillWins` (which repeats the tie at the hoisted
layer, so the layer key did not quietly become the only key); reverting to plain
last-registered-wins reddens `aDeferredScrollViewTakesTheWheelFromAnOverlappingSiblingBeneathIt`
alone; deleting the prepaint hoist again reddens both new tests.

**What it does NOT buy, measured because a reader will assume otherwise.** A `Deferred`
subtree that does not itself scroll registers **no region**, so it cannot block a wheel
event: a scrim over a list leaves the list scrolling underneath it (probed — one region,
layer 0, offset 37). `Frame.scrollRegions` is the only hitbox list this framework has,
and blocking needs §8.1's general one. The layer key orders scrollers against each other;
it does not make an overlay opaque to input. The demo's exit-criterion instructions now
ask the human to wheel over the scrim and report this, so the limitation is on the record
from the look and not only from a probe.

**What it costs if wrong.** A modal's own list scrolls the page behind it — the exact
symptom `PrepaintPass.deferred`'s doc comment describes, and one that no rect assertion
can see, since layer moves no geometry.
