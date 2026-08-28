# Clipping and Scroll Containers — Design

**Status:** approved in brainstorming 2026-08-28. Successor to M2 (text).
**Position:** the first of the sub-projects M3 decomposes into.

M3's scope line in the design spec (§12) is nine things — hitboxes, mouse
dispatch, hover/active, focus, keymaps, actions, scroll containers,
virtualization, AX nodes and identity. That is not one milestone. This spec
takes the first piece, chosen because it is a hard prerequisite for most of
the rest and because it ends in something runnable.

---

## 1. Scope

**In:**

1. **Interleaved batching** — `Scene` learns to order primitives across types,
   which §7.3 already specifies and the current implementation does not do.
2. **Clipping** — `MUIRect.contentMask` becomes live; `MUIGlyph` gains one.
3. **A clip/translate stack** on `Frame`, exposed to prepaint and paint.
4. **A `ScrollView` element**, with scroll offset in the state table.
5. **A scroll-region registry** in prepaint, and `scrollWheel` routing.
6. **An overlay scroll indicator**, which borrows two M4 primitives (§8).

**Out, deliberately:**

- **Virtualization** (§4.7). The next sub-project. `ScrollView` here holds real
  children, all of them realized.
- **General hit testing** (§8.1). The registry in §7 is scroll-only and is
  named as the seed of the general one, not as the general one.
- Dragging the indicator's thumb; the indicator widening on hover (both need
  hit testing); keyboard scrolling (needs focus); scroll-into-view;
  programmatic or animated scrolling.
- Rounded *clip* corners on anything but the container's own painted
  background — see §4.

---

## 2. Renderer: ordering

### 2.1 What was wrong before Task 2

**Fixed by Task 1 and pinned by Task 2** (`anOpaqueRectAtAHigherOrderCoversTheTextBeneathIt`,
`GlyphABITests.swift`) — this section is the design rationale that motivated
both, kept for that reason even though the quote below no longer describes the
code.

`Scene` held one array per primitive type and `finalize()` sorted **within**
each. `Renderer.encode` then drew all rects, then all glyphs. Its own doc
comment stated the consequence:

> `order` sorts WITHIN a primitive type and not between them. Every glyph is
> drawn after every rect regardless of order … it is wrong for a rect that
> should occlude text beneath it, which needs either a depth buffer or an
> interleaved batch-per-order encode. Named here rather than left to be
> discovered: **nothing in this repo can see a glyph painted through a rect.**

Design spec §7.3 promises something else:

> At submit, the scene sorts by order and **groups consecutive runs of the same
> type into one instanced draw call**. Draw-call count is the number of *type
> transitions* in z-order.

So the two-bucket implementation is a simplification of §7.3, not an
implementation of it. An overlay scroll indicator is precisely "a rect that
should occlude text beneath it", which is what forces the correction now.

### 2.2 The design

`Scene` keeps its per-type arrays — they map one-to-one onto pipelines and
instanced draws, and a heterogeneous array would be re-partitioned every frame,
which is the reason the arrays are split in the first place.

`finalize()` additionally produces a **draw list**:

```swift
public enum PrimitiveKind: Sendable { case rect, glyph }

public struct DrawRun: Sendable {
    public let kind: PrimitiveKind
    public let start: Int      // index into that kind's array
    public let count: Int
}

public private(set) var drawList: [DrawRun] = []
```

`finalize()`:

1. Builds a merged index of `(order, insertionSequence, kind, indexWithinKind)`.
2. Stable-sorts it by `(order, insertionSequence)`.
3. Permutes each type array into that global order, so every run of one kind is
   contiguous within its own array.
4. Walks the sorted index, emitting one `DrawRun` per maximal same-kind run.

`encode` walks `drawList` and issues one instanced draw per run, binding the
pipeline only when `kind` changes.

**The insertion-sequence tiebreak is load-bearing and must not be dropped.**
The existing sort is stable and its comment says why — "painters at the same
layer must stack predictably." A merged sort across two arrays has no inherent
stable order between them, so the sequence number has to be explicit.

### 2.3 What this buys, stated so it can be checked

Draw-call count becomes exactly the number of type transitions in z-order.
That is directly assertable from `drawList.count`, so §7.3 stops being a claim
about the renderer and becomes a property of it.

**Expected counts, to be pinned as tests:**

| scene | runs |
|---|---|
| rects only | 1 |
| glyphs only | 1 |
| a `Text` (background rect, then its glyphs) | 2 |
| list rows (rect, glyphs) × N, interleaved by order | 2N |
| the same list under one clip, indicator last | 2N + 1 |

The 2N row is the honest cost of correct ordering and must be written down
rather than discovered: **a list of N text rows that alternate rect and glyph
in z-order costs 2N draw calls, not 2.** §7.3 already says the mitigation is a
z-order layout choice (it names the M5 node graph putting all wires beneath all
node bodies); the same applies to lists, and a future optimisation is to paint
all row backgrounds before all row text where the design allows.

---

## 3. Renderer: clipping

### 3.1 Mechanism, and why not `[[clip_distance]]`

§7.3 says:

> Clipping is per-primitive via `[[clip_distance]]`, not scissor rects. Scissor
> clipping would force a state change and therefore a batch break at every clip
> boundary; clip distances make clipping free and composable with instancing.

**This spec implements a fragment-stage mask instead, and treats §7.3 as
amended rather than diverged from.** The reason §7.3 gives for rejecting
scissor rects is *batch breaks*. A per-primitive `contentMask` carried in the
instance buffer causes no pipeline state change either — it is data, not state
— so it meets that requirement. Three things then favour it:

1. **`clip_distance` cannot clip to a rounded container.** It cuts on straight
   planes. `rect_fragment` already computes a rounded-rect SDF, so intersecting
   a mask there is a few lines and rounded clipping comes nearly free.
2. **The plumbing exists.** Both fragment shaders already receive
   `pixelPosition` and re-read their primitive from the instance buffer by
   index. `MUIRect.contentMask` is already in the ABI and already round-trips
   (`abi_probe` reads it); it is one of the four inert fields CLAUDE.md tracks.
3. **Antialiasing comes from code already present.** A hard cutoff jags on
   fractional boundaries. The existing smoothstep gives a clean edge.

**The cost, recorded now rather than discovered:** fragments outside the clip
are still rasterized and shaded before being masked to zero. For a scroll
viewport that is a thin band around the content and is negligible. It would
stop being negligible for a clip that hides most of a very large primitive —
if that ever appears, revisit.

**Not `discard_fragment()`** — returning zero alpha instead. There is no depth
buffer, so `discard` buys nothing, and on some GPUs it disables early-Z for the
whole shader.

### 3.2 `MUIGlyph` gains a `contentMask`

The header currently says:

> There is deliberately NO `contentMask` here. `MUIRect` carries one that
> `rect_fragment` never reads, and a second inert field would be a second thing
> that looks implemented from the outside.

That reasoning expires here, and the *task that adds the field must also make
it live* — the field and its first reader land in the same commit. This is the
rule CLAUDE.md's "declared but inert" table exists to enforce, applied forward.

**This is an ABI change to `MetalUIShaderTypes.h`.** Consequences:

- `swift package clean` is mandatory after the edit. The header reaches the C
  target through a symlink SwiftPM does not track, so Swift's view goes stale
  while Metal's refreshes; the symptom is a vanished primitive that looks
  exactly like a shader bug.
- `abi_probe` in `shaders.metal` must gain the new field, and the ABI tests
  must be extended, or the offset change is unguarded.
- `MUIGlyph`'s `_reserved` field exists. Whether the mask fits in the current
  stride or grows it is a measurement for the implementer, not an assumption
  for this spec.

### 3.3 Semantics

`contentMask` is an axis-aligned `MUIBounds` in the same space as `bounds`. A
primitive is drawn where it intersects its mask and masked to zero outside.

**The default must be the whole surface, not zero.** `Frame.fill` already
passes the full surface, which is why every existing rect keeps drawing when
the fragment shader starts reading the field. This is what makes the change
non-breaking for the 67 goldens and the existing pixel tests.

---

## 4. The clip/translate stack

Lives on `Frame`. Exposed on **both** `PrepaintPass` and `PaintPass` in one
closure form:

```swift
public func clipped(to bounds: Bounds<Pixels>,
                    offsetBy offset: Point<Pixels>,
                    _ body: () -> Void)
```

Balanced by construction — an unbalanced push/pop is not expressible.

**It is on `PrepaintPass` as well as `PaintPass` because a scroll region's
on-screen position depends on ancestor scrolls.** A nested `ScrollView` that
its parent has scrolled out of view must not receive wheel events.

### 4.1 The rule that makes this work

**Translation and clipping are properties of the emission, not of the
geometry.**

- `bounds(of:)` keeps returning untranslated engine geometry. It is what the
  layout engine computed and elements reason about it.
- `fill` and `draw` apply the active translation and the active (intersected)
  clip on the way into the `Scene`.

So a child that does `pass.fill(pass.bounds(of: node))` scrolls correctly while
knowing nothing about scrolling. This mirrors how `fill` already owns the scale
factor: the pass deliberately exposes no `scaleFactor` because a caller who
found one would double-apply it. Translation is the same hazard and gets the
same answer.

### 4.2 Nesting

The stack intersects. `contentMask` is a single `MUIBounds` and §4.7 requires
nested scrollers, so the stack collapses on the CPU to one rect per primitive
and the GPU never sees a stack. Translations compose by addition.

**Intersection is what makes nesting correct, not clamping.** An inner clip
larger than its outer one must not widen the outer.

`Passes.swift` already anticipates this shape:

> `Frame` owns no hitbox, focus, scroll or accessibility store … Adding a
> registry means a store on `Frame` and a method here.

---

## 5. `ScrollView`

### 5.1 Shape

SwiftUI's answer, per the standing directive that SwiftUI is the design
authority and CSS is the substrate (ruling EP-5):

```swift
ScrollView(.vertical) {
    Column { /* rows */ }
}
```

**Not `Box.overflow(.scroll)`.** `Style.overflow` remains the substrate the
element writes into, exactly as `Column.init` writes `alignItems` without
`Style`'s default moving (ruling EP-8).

### 5.2 Two layout nodes, and the measured reason

`ScrollView` emits a **viewport** node containing a **content** node:

- **viewport** — takes the offered size; carries `overflow: .scroll`.
- **content** — `flexShrink: 0`, and an `auto` size on the scroll axis.

**Measured against the real engine, 2026-08-28**, five 40pt rows in a 200×100
viewport:

| content node | content height | overflows? |
|---|---|---|
| default (`min-height: auto`), `flexShrink: 0` | 200 | yes |
| default (`min-height: auto`), `flexShrink` default | 200 | yes |
| `min-height: 0`, `flexShrink: 0` | 200 | yes |
| `min-height: 0`, `flexShrink` default | **100** | **no — scrolling dead** |

**The overflow comes from CSS Sizing §4.5's automatic minimum, not from
`flexShrink: 0`.** `min-height: auto` floors the content node at its content
size — the same mechanism divergence FS-3 describes. The first draft of this
design asserted `flexShrink: 0` was what did it; the differential above
falsified that, and the rows are kept so the claim cannot silently revert to
the wrong one.

`flexShrink: 0` is still specified, as the belt to the automatic minimum's
braces: it is the only one of the two that survives an explicit `min-height: 0`
somewhere up the chain. **Neither is redundant on its own evidence** — row 4 is
what a reader needs to see to know why both are there.

**No engine change is required.** Overflow is what the engine already does.

### 5.3 Offset, clamping, state

`contentSize = bounds(of: contentNode).size`. The offset clamps to
`0 ... max(0, contentExtent - viewportExtent)` on the scroll axis and is 0 on
the other.

Offset persists in the `StateTable` through `withState`, keyed by
`GlobalElementID` — the structure structural identity built, used for the first
time here by something other than a test.

**A consequence that must be documented in the element's own doc comment:** a
`ScrollView` inside a vanishing `if` hands its scroll position to the trailing
sibling, per the adoption behaviour CLAUDE.md pins and
`anElementAfterAVanishingIfAdoptsTheVanishedElementsState` measures. A list
silently inheriting another list's scroll position is a confusing thing to meet
cold. The remedy is the counter-intuitive one that milestone established:
name the **trailing sibling**, not the conditional content.

### 5.4 Clamping when content shrinks

If content shrinks between frames (rows removed) the stored offset may exceed
the new maximum. **Clamp on read, not on write** — the offset is written by an
event handler that has no access to the current layout, and the layout that
would validate it does not exist until the next frame.

---

## 6. Painting a `ScrollView`

In `paint`:

1. Fill the container background at the viewport bounds, with corner radii if
   any. This rect is **not** clipped by the scroll clip — it *is* the container.
2. `pass.clipped(to: viewportBounds, offsetBy: -offset) { paint children }`.
3. Paint the indicator, outside the clip block, at a higher order.

Step 3 being outside the clip is deliberate: the indicator is positioned in
viewport space and must not scroll with the content.

---

## 7. Input routing

```swift
// PrepaintPass
public func registerScrollRegion(_ bounds: Bounds<Pixels>, id: GlobalElementID)
```

Writes the **clipped** bounds into a store on `Frame`, in prepaint order.

`Window` handles `.scrollWheel(event)` by walking the store **in reverse** — so
the last-registered (topmost) region containing the point wins — adding the
delta to that id's stored offset, and calling `setNeedsRedraw()`.

**This is a hitbox list scoped to scroll, and this spec calls it that.** §8.1's
eventual signature is `pass.insertHitbox(bounds, contentMask, opaque:)`, which
takes exactly the clip stack's product. The next sub-project generalizes this;
it does not replace it with something unrelated.

**Reverse order is the same rule §8.1 states** ("dispatch walks them in reverse
so the topmost opaque hit wins"), arriving early because scroll needs it.

`ScrollEvent.isMomentum` already exists and `AppKitPlatform` already populates
it from `NSEvent.momentumPhase`. Momentum deltas are applied identically to
direct ones — the OS does the physics. **No inertia simulation of our own**;
that arrives with iOS and with programmatic scrolling, and building it now
means building it twice.

**Not handled here:** an unconsumed scroll event does not bubble to an ancestor
`ScrollView` when the inner one is already at its limit. Nested-scroll chaining
is a dispatch concern and belongs with the general hit-test work. Recorded so
that its absence is a decision.

---

## 8. The indicator, and the two M4 primitives it borrows

A rounded rect over the content, on the scroll axis, sized by the
viewport/content ratio and positioned by the offset. It fades out after
scrolling stops.

A fade is time-based. Frame-count fades are wrong at 120Hz against 60Hz, so
this needs two things that belong to M4:

1. **`Frame.timestamp`** — `CADisplayLink.timestamp` plumbed through
   `PlatformWindow.startDisplayLink`, whose callback takes no argument today.
2. **A request-another-frame hook** — an element must be able to say "again
   next frame". Dirty tracking and display-link pausing already work
   (`setNeedsRedraw` unpauses; `drawFrameIfNeeded` pauses when clean); what is
   missing is only the element-facing way to ask.

**These are the inputs to animation, not an animation system.** No easing
curves, no animator, no interpolation machinery: one `Double` and one `Bool`.
When M4 builds animation properly it consumes these rather than replacing them.

**The borrow is recorded here so M4's plan does not re-scope them.**

---

## 9. What no test in this repo can see

Following spec §4.2's practice of naming these rather than implying coverage.

1. **Whether the clip edge is antialiased correctly.** A pixel test can assert
   that pixels outside the mask are zero and inside are not; the quality of the
   half-covered boundary pixels is a look, not an assertion.
2. **Whether the indicator's fade timing feels right.** Time-based and
   subjective. The human check is the only instrument.
3. **Whether scrolling *feels* native.** Momentum pass-through is either wired
   or not, which is checkable; whether the result feels like other Mac apps is
   not.

**What IS newly checkable, and was not before:** a rect drawn over text.
`Scene.finalize`'s comment says "nothing in this repo can see a glyph painted
through a rect" — after §2 that sentence must be deleted, because the draw list
makes it visible and a pixel test must pin it. **Deleting that sentence is part
of the work**, on the same rule as the inert table: a stale "nothing can see
this" reads as a live hazard.

---

## 10. Verification

- **Draw-list ordering** — unit tests on `drawList` for the five scenes in
  §2.3, plus a pixel test of an opaque rect over a glyph, which is the whole
  point and cannot be done any other way.
- **Clipping** — pixel tests through `renderOffscreen`: a rect and a glyph each
  half-clipped, asserting zero outside and unchanged inside. **Build the
  expected values from the atlas and the fill colour, never from the primitive's
  own mask** — taxonomy shape 12, four instances of which came from M2's
  equivalent tests.
- **Clip stack** — nested clips intersect; an inner clip larger than its outer
  does not widen it; translation composes by addition.
- **`ScrollView` layout** — the four-row table in §5.2 becomes a test, since
  three of its four rows are what stop the mechanism claim reverting.
- **Routing** — a synthetic `scrollWheel` at a point inside a region moves that
  region's offset; at a point outside, it does not; with two overlapping
  regions, the later-registered one wins.
- **Clamping** — offset cannot exceed content − viewport, cannot go below zero,
  and is clamped on read after content shrinks.
- **No golden may move.** The 67 browser fixtures exercise the flex engine,
  which this project does not touch. A moved golden means something reached the
  engine that should not have — stop and report, do not regenerate.

**The mutation discipline applies as in M2:** every new guard is mutated and
the reddened tests are **named**, not counted (ruling SI-H — three of five
recorded counts on the structural-identity branch were stale by the end of the
task). A mutation that reddens nothing is a broken instrument or it is the
finding; prove the mutant behaves differently before banking a coverage gap.

---

## 11. Exit criteria

1. `swift package clean`, a warning-free build, and a full `swift test`
   **summary line** read (never the exit status — shape 11).
2. No golden moved; the live-WebKit oracle test still passes.
3. A rect painted over text occludes it, pinned by a pixel test, and
   `Scene.finalize`'s "nothing in this repo can see" sentence is deleted.
4. `drawList.count` equals type transitions for the §2.3 table.
5. `MUIRect.contentMask` leaves CLAUDE.md's declared-but-inert table, and
   `MUIGlyph.contentMask` never enters it.
6. `Style.overflow` leaves the inert table, or — if `ScrollView` turns out not
   to need the engine to read it — **stays, with a row saying so honestly.**
   Section 5.2's measurement suggests the latter is likely: `overflow: .scroll`
   moved no number in the probe. Whichever way it lands, the table is correct
   afterwards.
7. A `ScrollView` of text rows in `MetalUIDemo`: clipped, scrollable by
   trackpad with momentum, with a fading indicator, inside a rounded container.
8. **A human runs the demo and reports on it**, because §9's three are all
   looks. The record must state what the look could *not* establish, as M2's
   does.

---

## 12. Decomposition into tasks

Roughly, for the plan to refine:

1. Draw list in `Scene` + `encode` walking runs. No behaviour change visible
   yet except ordering.
2. Pixel test: rect over glyph. Delete the stale sentence.
3. `contentMask` live in `rect_fragment`, with AA.
4. `MUIGlyph.contentMask` — ABI, `abi_probe`, `swift package clean`,
   `glyph_fragment`.
5. Clip/translate stack on `Frame` + both passes.
6. `ScrollView` layout and offset state.
7. Scroll-region registry and `Window` routing.
8. `Frame.timestamp` + request-another-frame.
9. Indicator.
10. Demo, CLAUDE.md table updates, human verification.

Tasks 1–4 are renderer and have no element-facing surface; 5–9 build on all of
them. Task 4 is the one with the `swift package clean` hazard.
