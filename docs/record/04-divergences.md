## Eleven known divergences, numbered 1, 2, 4, 9-11, 13-16 and 18 — expected, measured, not defects

**The labels are stable ids, not a running count, and there are now SEVEN
retired labels.** There are **eleven** entries and the highest label ever
assigned is **18**, which is also the highest still present. Seven labels are
permanently retired, for **four** different reasons, which is worth knowing
before assuming a gap means a lost entry:

**18 is new, and it was added by the same milestone that retired 12 and 17 —
which is the shape to notice rather than a coincidence.** The mechanism that
closed those two is a *general* change to `StateTable.sweep()`, and a general
change has consequences outside the case it was built for. 12 and 17 were
`List`-windowing limitations; 18 is what the same retention does to **every
conditional subtree in the framework**, and it disagrees with SwiftUI rather
than with CSS. A milestone that retires two entries and adds one has not
necessarily come out ahead by one; read 18 before concluding it has.

- **12 and 17 were retired by the tombstones-and-AX milestone (2026-09-01),
  and they are the first two entries retired by a fix that is DELIBERATELY
  BOUNDED rather than absolute — which is a fourth reason, not an instance of
  the third.** Both were `List`-windowing limitations with one mechanism: a row
  outside the window is not produced, so nothing marks its `GlobalElementID`,
  and `StateTable.sweep()` deleted its entry outright. **12** was the row's own
  `@State` being lost; **17** was a *focused* row losing focus, recorded as the
  worse of the two because `@State` is recoverable from the datum and focus is
  not. `sweep()` now retains an unmarked entry with its value and only clears
  its `isLive` flag (`TB-AE`); focus rides the same table through a dedicated
  `$focus` retention slot rather than a second grace period (`TB-J`, design spec
  §5's own instruction).

  **Read the closure at exactly its strength: it is "closed for two
  generations", not "closed" (ruling `TB-AH`, spec §3 and §8 risk 2).** An entry
  survives being unmarked for `StateTable.staleAfterGenerations` — **2** — so an
  excursion of exactly two generations keeps its state and its focus and an
  excursion of three keeps neither. **And the reap only engages once
  `storage.count > sweepThreshold` (256) at all**, so below that a stale entry
  is retained indefinitely; the bound bites on a large list and not on a small
  one. "Fixed" and "fixed for N generations" are different claims and the second
  is the true one — anywhere this closure is cited, it is cited with the bound
  attached. **The old remedy therefore still stands for long excursions**: a
  value a long scroll must not lose belongs in the **data**, which is where a
  windowed list wants it anyway.

  **Both halves are pinned, and the pins are asymmetric on purpose** —
  `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`
  (`Tests/MetalUITests/TombstoneTests.swift`) and
  `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`
  (`Tests/MetalUITests/FocusTests.swift`). Each asserts a two-generation
  excursion surviving *and* a three-generation one not surviving, and in each
  the two halves redden under *different* mutations. For the state one:
  reverting `sweep()` to deleting reddens **only** the short half (the row is
  deleted the very next sweep, long before it is due back) and leaves the long
  half alone, since both policies discard a row gone three generations. For the
  focus one: reverting to unconditional-clear reddens **only** the short half,
  and making `resolveFocus` a no-op reddens **only** the long half. If one
  mutation reddened both halves of either test, the second half would be
  proving nothing about boundedness — the asymmetry is the whole evidence. **A third test carries the part neither of those
  can see** —
  `aStaleEntryIsRetainedForeverWhileStorageStaysAtOrBelowSweepThreshold`, which
  is the only thing pinning that the reap is *gated on the size at all*: both
  excursion fixtures hold the table above 256 throughout, so the gate is always
  true in them and whether it is consulted is unobservable (ruling `TB-H`, ruling
  MP-J's shape a third time). **Every mutation result in this bullet was run
  twice during the milestone — once by the implementer and once, independently,
  by that task's reviewer — and NOT re-run by the documentation task**, which
  verified only that the three tests exist under these names and that the suite
  is green at 782. Rulings `TB-AE`, `TB-AF`, `TB-AH`, `TB-D`, `TB-J`
  and `TB-H` in `docs/superpowers/2026-09-01-tombstones-decisions.md`.

  **Divergences 13 and 14 did NOT go with them and are unchanged.** They are
  `List`-windowing limitations with entirely different causes — a one-frame-stale
  viewport extent and a window placed against the scroller's origin — and
  neither is touched by anything the sweep does. 14 in particular can still make
  a list render **blank**; retiring its neighbours changes nothing about it.
- **3, 5 and 6 were freed by the sizing milestone (2026-08-31), which closed
  all three of this framework's remaining sizing divergences at once.**
  **3** was ruling BM-4, an over-constrained box refusing to grow its border
  box; fixed by flooring every used-size call site at
  `max(clamp(resolved, min:, max:), floor)` — the floor applied *after* the
  clamp, settled against the oracle rather than chosen (a `max-*` smaller than
  a box's own padding+border does not win in either axis) — and pinned by
  `anOverConstrainedBoxGrowsToFitItsPaddingAndBorder` (`BoxModelTests.swift`).
  **5** was ruling FS-3, an item's automatic minimum ignoring its own
  specified size; fixed by reading the specified size suggestion from the
  node's **used**, post-BM-4 size rather than its raw declaration — floors
  compose by `max` and BM-4's floor cannot be undone by FS-3's — and pinned by
  `anItemsAutomaticMinimumIsTheSmallerOfItsSpecifiedAndContentSizes`
  (`FlexEngineTests.swift`) plus two browser fixtures,
  `sizing_specified_suggestion` and `sizing_specified_suggestion_is_used_value`.
  The second of those two exists because the first does not discriminate the
  specified-vs-declared reading on its own tree: a floor BM-4 has already
  raised to 120 is untouched by either a 100 or a 130 automatic minimum, and
  only a fixture with a shrinking sibling can tell the two rules apart —
  measured, not assumed, after the plan's own claim that the first fixture
  guarded this choice turned out false. A second gap in the same formula — the
  automatic minimum was never clamped by a definite `max-*` — was found by the
  post-merge review and fixed without a divergence number:
  `sizing_max_clamps_content_suggestion` (WebKit 50, engine 200 before) and
  `sizing_max_below_floor_keeps_automatic_minimum` (the clamp must not take an
  item below its padding and border). **6** was ruling TX-H, an item's cross
  size measured before §9.7 flexes it; fixed by re-running the fit-content
  cross measurement for any non-stretched item whose used main size differs
  from its hypothetical one, and pinned by
  `anItemsCrossSizeIsMeasuredFromItsUsedMainSizeMatchingWebKit`
  (`FlexEngineTests.swift`). All three fixes, and the findings along the way,
  are recorded in `docs/superpowers/2026-08-30-sizing-decisions.md`: BM-4 is
  rulings `SZ-D`, `SZ-E`, `SZ-F` and `SZ-J`; FS-3 is `SZ-G`, `SZ-H` and `SZ-I`;
  TX-H is `SZ-M`.
- **7** was freed by a *renumbering*, before this milestone. The *original*
  divergence 6 — an unrelated, already-fixed bug, not the TX-H one just
  retired above — was `ownCross` measuring **max-content** on whichever axis
  was the cross one, so a **column** (whose cross axis is the *inline* axis,
  where CSS shrink-wraps) laid a wrapping child out 200 wide at `x = -40`
  inside a 120-wide centring column, and `Column { Text(…) }` 270 wide at
  `x = -75`. It was fixed by computing CSS's fit-content —
  `min(max(min-content, available), max-content)` — on a column's cross axis
  (still max-content on a row's, correctly, since a row's cross axis is the
  block axis), and the original divergence 7 moved down into the slot that
  fix emptied — which is why "divergence 6" in an old document could mean
  either this bug or the TX-H one, depending on date, and why both are
  retired labels now rather than one. The fix's own first evidence was weak:
  every box in the 61-fixture corpus at the time was an empty div whose
  min-content and max-content widths were the same number, so nothing could
  regress or validate it. Six fixtures with wrapping children
  (`flex_column_fit_content*`, `flex_row_block_axis_max_content`,
  `FitContentFixtureTests`) were added afterward to close that gap, and found
  two of the fix's four clauses wrong before they were measured — the
  available space is the container's cross extent minus the item's own cross
  margins, and the `max` with min-content is a real floor that overflows.
- **8** was freed by a *fix*, on 2026-08-30, and its entry was deleted rather
  than renumbered. `Text.paint` now wraps at the width layout measured at
  (`LayoutTree.measuredWidth(_:)`) instead of re-deriving one from the rounded
  box, so paint and layout no longer disagree about how many lines a
  shrink-wrapped string has. Measured on the shape it was reported in: **31 of
  40 list rows wrapped before the fix and 0 after**, and a centred `"Count N"`
  label wrapped on ten of the first thirteen counts and now wraps on none.
  Pinned by `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox`,
  `aCentredShrinkWrappedLabelNeverWrapsAtAnyValue` and
  `aTextShrunkByFlexStillWrapsAtItsShrunkWidth` in `GlyphEmitterTests.swift`,
  and **confirmed in a real window by a human on 2026-08-30** — which matters
  because every other figure for this fix is a glyph count out of a headless
  `Frame`, and the defect was originally *reported* by eye rather than found by
  a test. **The retired TX-H entry (label 6, above) used to carry a paragraph
  calling a second spill "a second spill with the same symptom and an
  UNIDENTIFIED site" — a sidebar label breaking mid-word inside a `Column`
  that is itself a flex item. The sizing milestone identified it: that site
  is this one, not a third bug.** `"Library"`'s max-content width is
  **42.2436**; the sidebar column floors it to 70.24, rounds to 70; the
  text's own box rounds down to 42; and before this fix, paint character-broke
  there (ruling TX-F). Re-measured with the fix landed: it renders as 7 glyphs
  on one baseline, ink 13.5pt. There is no unidentified spill site left.

**None of the seven retired labels is ever reused** — the same rule `EP-2`/`EP-4`
follow — so a citation written against "divergence 3", "5", "6" (the TX-H one;
see the label-7 bullet above for the *other* thing "divergence 6" used to
mean), "8", "12" or "17" in an older commit message or document points at a
retired entry rather than silently rebinding to a different one. **12 and 17
are the two most likely to be cited from outside this file**, because both were
recorded at `List`'s own type doc and in several test comments before they were
retired; a citation of either is a citation of a *bounded* closure, not of a
live limitation. A reader who counts to the highest label ever assigned gets
eighteen, a reader who counts to the highest label still present gets eighteen,
and a reader who counts entries gets eleven; the heading says all three because
they answer different questions. (**Those first two coincide today and did not
before divergence 18** — the highest label was seventeen and retired, so the
two questions had different answers. They will diverge again the moment 18 is
retired; that is why the heading still asks all three.)

**Not every entry is a disagreement with WebKit, and 10 was the first that
never was one.** 1, 2, 4 and 9 are places this engine answers differently
from an oracle. (The retired 8 was the one entry where the disagreement was
not with WebKit at all but between this engine's own layout and its own paint
— which is also why it was the one that could simply be fixed.) **10, 11, 16 and 18 are design choices recorded here because a reader comparing
this framework to CSS — or, for 18, to SwiftUI — will otherwise read them as
bugs** — 10 and 11 are the two directions
of one seam and each entry names the other, and 16 is the price of the rule
that closes the modal-scrim case. **13 and 14 are a third kind again:
neither a disagreement nor a design preference, but accepted limitations
of `List`'s windowing**, each with a named mechanism that would remove it and
a reason that mechanism is larger than this framework has built. (**This kind
had four members until the tombstones milestone retired 12 and 17** by
building one of those named mechanisms — which is the argument for naming
them: the two that got fixed are the two whose blocker was written down as a
mechanism rather than as a mood.) 14 is the
one of the two that can make a list render **blank** rather than merely
stale, so read it before putting a `List` in a scroller that
holds anything else. **15 is a fourth kind and the only one of its own: a
defect this framework has and has deliberately not fixed yet**, recorded here
rather than left latent because its symptom — a subtree that draws nothing at
all — reads as anything but a clipping bug. **18 sits in the design-choice
family with 10, 11 and 16 but is the only entry in this list whose disagreement
is with SwiftUI rather than with CSS or with an oracle**, which matters because
this project's standing rule takes SwiftUI's answer where the two differ
(ruling EP-5). It is recorded as accepted rather than as settled: nothing about
it is a browser question, so there is no oracle to appeal to, and the reason it
is accepted is written into the entry rather than assumed.

**One thing the reactivity milestone deliberately did NOT add to this list, said
here because silence in this section reads as an oversight (ruling `RX-P`).**
An off-screen `List` row's model reads are not tracked, so mutating its datum
marks nothing dirty — the same "not produced ⇒ not seen" mechanism as the
retired 12 and 17 and the live 13 and 14, in a **third** place. It is **not** a
divergence and does not get a label: **SwiftUI's `List` does the identical thing
for the identical reason**, so unlike 18 there is no SwiftUI disagreement, and
unlike 1, 2, 4 and 9 there is no oracle disagreement either. **Read that
SwiftUI claim at its strength, because it is the sole justification for
withholding a label and it is DERIVED rather than measured** (ruling `RX-P`): it
follows from SwiftUI's documented laziness, and **no probe was run** — unlike
divergences 2 and 9, whose oracle claims were each measured through a throwaway
probe before being written. Measuring it needs a SwiftUI harness this repo does
not have and should not grow for one claim, so the shortfall is labelled rather
than glossed. **If SwiftUI turns out to differ, label 19 is still available and
nothing here forecloses it.** It is correct
behaviour — nothing on screen to redraw, self-healing on scroll, with the value
living in the datum `List` re-reads every frame — and it is written up in the
`List` bullet at the top of this file and pinned by
`anOffScreenListRowsModelReadIsNotTracked`. A reader who finds it and reaches
for label 19 should stop here.

**Erratum 2026-09-14 (at `7cfcddc`; record §09):** "label 19 is still
available" is stale. Label 19 has since been assigned to "One element VALUE
placed twice shares one `@State` box" (`git show a15ec83:CLAUDE.md`, line 458).
If SwiftUI turns out to differ here, the next unused label is needed (20 in that
table, which has no higher one), not 19; labels 3, 5, 6, 7, 8, 12 and 17 are retired and never reused.

**1. Colour.** The layer's colorspace is Display P3 (spec §7.8) while
`Hsla.rgb(_:)` authors in sRGB, so `0x38BDF8` renders somewhat more saturated
than the hex implies.

**2. WebKit's flex sub-one clause.** The layout corpus treats WebKit as the
oracle, and there is exactly one place the engine knowingly does not follow it:
CSS Flexbox §9.7.4.b's magnitude test, in `ResolveFlexibleLengths.swift`.

Reproduce with:

```html
#root { display: flex; flex-direction: row; width: 400px; }
.a { flex: 0.25 1 0; min-width: 350px; }
.b { flex: 0.25 1 0; }
```

The spec says `b` is **50** — the sub-one scaling may only reduce the remaining
free space, never enlarge it, and on the second pass the scaled 100 exceeds the
remaining 50. **Blink says 50. WebKit says 100** and overflows the container to
450. Two engines and the specification against one: this is a WebKit bug, and
the engine follows the spec.

The divergence is narrower than it looks — it needs positive free space *and* a
min/max violation to force a second pass. `flex_row_fractional_shrink` exercises
the identical `abs` guard with negative free space and WebKit agrees with us
there.

**No fixture or golden encodes WebKit's answer.** The probe above was generated
against the oracle and then deliberately not committed, precisely so that a
future WebKit fix moves nothing in the corpus and changes no test. Do not add
one, and do not "correct" `subOneScalingNeverExceedsTheRemainingFreeSpace`
towards WebKit — it is pinning the settled answer, not a provisional guess.

**4. Ruling CS-I — an `auto` root axis takes the space it was offered, where
CSS shrink-wraps the block one.** The root is a block-level box in the initial
containing block, so a browser fills its inline axis and shrink-wraps its block
axis. Measured: an 800×600 viewport holding `#root { display: flex }` with one
100×40 child gives WebKit **800 × 40**. This engine gives **800 × 600**.

**The justification is `computeLayout`'s contract, not a ruling from a layer
above.** The engine's root is not a block box in a CSS initial containing
block; it is a node whose size its host supplies, and `.definite(w)` on an axis
of `available:` is the host saying "this axis is w". A browser has no
equivalent — its root's containing block is the viewport by construction, and
it is never *told* a size. **Do not cite EP-5 here**: that ruling ends "the
WebKit corpus stays the oracle for the engine; this ruling binds everything
above it", and `resolveRootSize` is inside the engine.

The evidence is behavioural. CSS's answer was implemented and reverted, and it
reddens six element-pipeline and frame-loop tests at once, all for one reason —
a `Row { … }` rendered into a `Frame` declares no height, so the window's root
would collapse to its content and every `flexGrow(1)` child would stretch into 0.

**The engine can still express CSS's answer**, which is what makes this "we
interpret one call shape differently" rather than "we disagree with WebKit": a
host that offers `.maxContent` on the block axis takes the measuring branch and
gets the shrink-wrapped 40. Only the meaning of a *definite* offered extent on
an `auto` axis differs.

**A fixture could hold this one; the corpus deliberately has none.**
`#root { display: flex }` with no `width` or `height` is perfectly expressible,
and its golden would say 800×40 and fail — same footing as WebKit's flex
sub-one clause above. That all 86 fixture roots declare both axes explains why no
*existing* fixture notices, not why one could not exist;
`FixtureHygieneError` does not enforce it, it only checks the root lands at
(0, 0).

What content sizing *did* change here is the other constant in the same branch
— an `auto` axis with **no offered extent at all** was a hardcoded 0 and is now
the subtree's own size, pinned by
`anAutoRootWithNoOfferedExtentMeasuresItsContent`.

**9. Ruling AP-F — an absolute box with no insets at all sits at its containing
block's origin, where CSS uses its static position.** CSS places an
all-`auto`-inset absolutely-positioned box where it *would* have been in flow —
its static position. This engine places it at the containing block's
**padding-box origin**, ignoring its in-flow siblings entirely.

Reproduce with:

```html
#root { position: relative; width: 200px; height: 100px; }
.before { width: 40px; height: 20px; }
.abs { position: absolute; width: 20px; height: 10px; }   /* no insets */
```

| | x | y |
|---|---|---|
| WebKit (static position) | 0 | **20** |
| this engine (containing block's origin) | 0 | **0** |

Measured through the oracle with a throwaway probe, deliberately not committed.

**Not implemented, and the reason is a second pass rather than reach.** Static
position means laying the box out in flow, recording where it landed, then
removing it — over exactly the children the flow filter (`collectItems`,
`layOutStack`) just excluded. The motivating features all set insets: a modal, a
popover and a tooltip each name at least one edge, and an inset-less absolute
box is closer to a mistake than to a case.

**No fixture and no golden encode it**, on the same footing as divergence 2's
WebKit sub-one clause above: a golden would record this engine's answer as
correct, and a future fix should move nothing in the corpus. Pinned by
`allAutoInsetsPlaceAtTheContainingBlockOriginNotTheStaticPosition` in
`AbsolutePositioningTests.swift`, which is the only pin — implementing static
position must redden exactly it.

**10. A `Deferred` subtree is not clipped by an ancestor CSS would clip it
with — and this one is a design choice, not a measurement.** Every entry above
is this engine answering a question differently from an oracle. This is the
framework deciding to answer a *different* question, and it is recorded here
only because a reader who knows CSS will otherwise file it as a bug.

CSS couples clipping to positioning: `overflow: hidden` clips an
absolutely-positioned descendant **unless its containing block sits outside the
clipper**. So whether a modal escapes a scroller is a consequence of where it is
positioned, and reproducing it means paint emitting a subtree at its containing
block's clip level rather than at its tree level — a second kind of hoisting,
entangled with containing-block resolution (design spec §2).

This framework decouples them instead, and states the rule in one line:
**layer decides paint order, the containing block decides position, and
`Deferred` escapes both.** A subtree wrapped in `Deferred` escapes every
ancestor clip and every ancestor scroll translation regardless of where its
containing block is — including the case where CSS would clip it, and including
the case where it has no absolute positioning at all.

**What it costs, stated because "deliberate" is not "free".** There is no way to
ask for CSS's answer: a subtree either escapes everything or nothing, and a
caller who wanted a portal clipped by one particular ancestor has no spelling
for it. Nothing here is `position: fixed` or `sticky` either — `Deferred` covers
the escape-to-the-window case and those two were left out rather than
approximated.

**No fixture and no golden encode it, and none could** — CSS's stacking and clip
rules are not what `Deferred` implements, so there is no browser answer to
compare against. Pinned at the scene level instead, by
`aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface` and
`aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll` in
`DeferredTests.swift`.

**Divergence 11 is the OTHER direction of this same seam** — a subtree escaping
a clip CSS would apply is this entry; a subtree being clipped where CSS would
not is that one. A reader who finds one of the two has found half the picture.

**11. An absolute box is still clipped and translated by an ancestor
`ScrollView`, even when its containing block sits outside that scroller.** The
mirror image of 10, and the one that bites: 10 is a portal escaping a clip CSS
would apply, and this is an ordinary box *not* escaping a clip CSS would lift.
Both fall out of the same decoupling — layer decides paint order, the
containing block decides position, `Deferred` escapes both — so neither is
fixable without the coupling design spec §2 rejects.

Layout places an `.absolute` box against its containing block. Paint knows
nothing about containing blocks: a clip and a scroll offset live on `Frame`'s
clip stack, which is **structural**, so every ancestor's
`clipped(to:offsetBy:)` applies to everything emitted beneath it. Put an
absolute box inside a `ScrollView` and the two disagree.

Measured — a 41×60 viewport at `(60, 30)` inside a 200×200 frame, holding an
absolute child with `inset(top: 5, left: 5)` and no `Deferred`:

```
absolute bounds = (5, 5) 22×20        // window space, per the containing block
absolute mask   = (60, 30) 41×60      // the viewport, per the tree
```

The rect lies entirely outside its own mask, so it **draws nothing at all**.
Scroll the list 12pt and it also moves to `y = −7`, off the top of the window,
tracking a scroll it is not in flow for. CSS clips neither: the box's containing
block is the root, which is outside the clipper, so a browser would paint it
over the whole page.

**The escape is `Deferred`**, and it is a separate spelling on purpose:
`Deferred { Box().position(.absolute)… }` resets the clip stack to the whole
surface and the offset to zero, and the identical box then paints at `(5, 5)`
with the full 200×200 mask. Recorded at `Box.position(_:)`'s own doc comment as
well, since that is where a caller writing `.position(.absolute)` will be
looking.

**No fixture and no golden encode it**, on the footing of 9 and 10 — a golden
would record this engine's answer as correct, and a coupling implemented later
should move nothing in the corpus. Pinned by
`anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt` in
`AbsoluteOverlayTests.swift`, which asserts the disjoint rect and mask, the
scroll translation, and the `Deferred` escape as the differential.

**13. A `List`'s window is computed against a one-frame-stale viewport
extent.** Scrolling is exact; only resizing is briefly wrong.

`List` decides what to build in `requestLayout`, and a `ScrollView`'s viewport
extent is not known until its own `prepaint` has measured one — the phase after.
So the ambient `ScrollContext` a `ScrollView` publishes carries a **current**
offset (which `Window.applyScroll` has already written by then) and the
viewport extent measured **last** frame (ruling MP-F). The offset being current
is what makes scrolling exact: however fast the list moves, the window is
computed from the offset the frame is actually about to be drawn at.

A resize is the case that goes wrong, for one frame. Drag the window edge so
the viewport grows, and that frame's window is sized for the old, smaller
viewport — the two rows of overscan absorb a viewport that grew by up to two
rows, and a bigger jump than that shows a strip of unbuilt rows at the bottom
for a single frame before the next frame corrects it.

**Not fixed, and the mechanism is a two-pass layout**: resolving the viewport
before the children that window against it are built means either laying the
`ScrollView` out twice or giving `requestLayout` a resolved size it does not
have. Both are larger than this milestone, and the failure they would remove
lasts one frame and is bounded by overscan.

**The contract is pinned; its consequence is not.** That a `ScrollView`
publishes last frame's extent is asserted directly, by
`scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`
(`Tests/MetalUITests/ScrollRoutingTests.swift`) — so a change that made it
current would redden a test. What no test reaches is the *effect*: every
windowing test pushes a `ScrollContext` by hand with an extent it chose, so
none of them renders the resize frame on which the window is briefly wrong.

**14. A `List` windows against its SCROLLER's origin, not its own — so a
`List` that is not its `ScrollView`'s only layout-contributing child renders
blank.** The sharpest of the three `List` limitations, and the only one whose
failure is total rather than gradual.

`ScrollContext.offset` says how far the enclosing `ScrollView`'s content has
moved under its viewport. `List.visibleRange` reads it as how far *this list*
has scrolled. Those are the same number only when the `List` begins exactly at
the scroller's content origin — which it does in the demo, and in every test
written before this entry, and in nothing else.

Reproduce with a header above the list:

```swift
ScrollView(.vertical) {
    Box(style: .init()).height(Pixels(300))       // anything with a height
    List(rows, rowHeight: Pixels(28)) { … }       // 40 rows
}
```

Scrolled to 300 with a 112pt viewport, the rows on screen are **0 through 3**
and the rows built are **8 through 16** — measured, and through a real
`ScrollView` those nine rows paint at y 224 through 448 under a content mask of
(0, 0) 100x112, so **nothing is drawn where the list is**. Two `List`s in one
`ScrollView` fail the same way by construction, since at most one of them can
start at the content origin. An absolutely-positioned `List` fails it too, and
that was measured rather than reasoned: the same list at `.position(.absolute)`
with `inset(top: 300)` builds the identical rows 8 through 16.

**"Layout-contributing" is the load-bearing word, and the demo is why.**
`Sources/MetalUIDemo/main.swift` declares a `Deferred` modal *before* its
`List`, inside the same `ScrollView`, and is **not** in violation — measured:
the list's rows still start at y = 0. The modal's box is
`.position(.absolute)`, so the flow filter removes it from the content node's
item list and it adds no height for the list to be offset by. An out-of-flow
sibling, or a `.hidden()` one, is free; anything that occupies flow is not.

**Not fixed, and the blocker is a phase contract rather than reach** (ruling
MP-L). Correcting the window needs the `List`'s own offset within the scroller's
content, and `requestLayout` has no position at all — the same fact that makes
`ScrollContext.viewportExtent` one frame stale (divergence 13). Supplying one
means laying the `ScrollView` out twice, or threading resolved geometry into a
phase defined to run before geometry exists; the second is a different layout
architecture, not a bigger version of this milestone.

**So it is a stated requirement of the type instead**: a `List` must be its
`ScrollView`'s only layout-contributing child. That is recorded at `List`'s own
type doc, where a caller will look, and in the `List` bullet at the top of this
file as the fourth load-bearing requirement beside `Identifiable`, a uniform
`rowHeight` and an enclosing `ScrollView`.

**Pinned, and the pin asserts the WRONG answer on purpose** —
`aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`
(`Tests/MetalUITests/ListTests.swift`) says so in its own failure message, so
whoever fixes this gets a red test rather than a surprise and knows to delete or
invert it. **Two neighbouring defects found by the same review WERE fixed and
are not divergences**: a horizontal `ScrollContext` used to window a vertical
`List` against a viewport *width* (ruling MP-M), and a `Deferred` subtree used
to inherit the scroll context of the scroller it had escaped (ruling MP-N). Both
were one condition each; this one is not.

**15. A `ScrollView` nested inside a SCROLLED `ScrollView` gets an empty content
mask, so nothing inside it draws.** Not a disagreement with any oracle and not a
design choice — a defect this framework has, found by measurement and
deliberately left for a milestone that owns paint.

`Frame.pushClip` intersects the incoming rect into `activeClip` **without
translating it by `activeOffset` first**, where `Frame.insertHitbox` — the
routing side — does translate. So the inner viewport's clip is computed in the
engine's untranslated space while `activeClip` is already in surface space, and
the two are compared as though they were the same thing.

Measured through a real `Window`, a 200x200 frame holding a vertical
`ScrollView` over 400pt of content (a 300pt filler above a 100pt box holding a
second `ScrollView`), the outer driven to its 200pt ceiling:

```
inner's three rows paint at y = 100, 150, 200      // correct
inner's registered scroll region = (0, 100) 200x100 // correct
inner's content mask             = (0, 300) 200x0   // EMPTY
```

So the inner scroller is laid out correctly, painted at the right window
positions and routes wheel events exactly right — and draws nothing.

**Its routing twin WAS fixed and is not a divergence** (ruling IN-F):
`registerScrollRegion` had the identical missing term, and unifying it on
`insertHitbox`'s translating convention is pinned by
`aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`.

**Not fixed, and the reason is blast radius rather than difficulty** (ruling
IN-G). The fix is one line — translate the incoming bounds by `activeOffset`
before intersecting — and applying it reddens the pin below and **nothing else**:
re-measured during the whole-branch fix wave at 739 tests, 6 issues, all of them
that one test, with the inner content mask moving `(0, 300) 200x0` →
`(0, 100) 200x100`, which is where its rows actually paint. (The same
measurement was taken at 736 before the fix wave added three tests; both
counts are recorded so the figure can be dated.)

**Read that as weak evidence and the structural argument as strong, and the
entry carried only the first for a milestone.** The suite half is weak for the
reason ruling IN-F records: no other fixture in the repo puts a scroller inside a
scrolled scroller and reads its mask back, so "nothing else reddens" is a
statement about the corpus rather than about the fix. What was missing is the
bound on the fix's *reach*, which is checkable and narrow:

- `pushClip` is reached in `Sources/` only through
  `PrepaintPass`/`PaintPass.clipped(to:offsetBy:)` — the two calls at
  `Passes.swift`, one per pass, each the single line of its own `clipped`.
  `Deferred` does not come through here at all; it uses `pushRootClip`.
- `grep -rn "\.clipped(to:" Sources/` returns **seven** lines, of which
  **three are calls** — all in `ScrollView.swift` (310, 326, 403) — and four are
  doc comments naming the method (`Box.swift`, `Passes.swift` twice,
  `Frame.swift`). Run it and read all seven; the count and the "three call
  sites" claim are two assertions and only the second was checked when this
  paragraph was first drafted.
- The added term is `+ activeOffset`, so the fix is a **no-op wherever
  `activeOffset == 0`** — which is every non-nested `ScrollView` in existence
  and everything under a `Deferred`. Its behavioural reach is *exactly* the
  nested-inside-a-scrolled-scroller case, which is the defect.

So "the clip stack every clipped subtree goes through" — what this entry used
to say — overstates it: every clipped subtree goes through the *function*, and
almost none of them through the *changed behaviour*. **The ship decision stands
anyway**: it was found inside a milestone whose entire test surface is input
rather than paint, and a paint change belongs to a milestone that can look at
pixels. Whoever picks it up should have the bound above rather than rediscover
it.

**Pinned, and the pin asserts the WRONG answer on purpose** —
`aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask`
(`Tests/MetalUITests/NestedClipTests.swift`), which says so in each of its own
failure messages, exactly as divergence 14's does. Delete or invert it; do not
repair it.

**16. An `onClick` inside a `ScrollView` swallows that scroller's wheel, where a
browser scrolls.** A design choice, on 10 and 11's footing — recorded because a
reader who knows a browser will file it as a bug.

A wheel event stops at the **topmost opaque hitbox** under the pointer and
scrolls only if that record is itself a scroller. Every `onClick` registers an
opaque hitbox. So a button inside a list blocks the list over its own rect:

```swift
ScrollView(.vertical) {
    List(rows, rowHeight: …) { row in
        Box { … }.onClick { … }          // the wheel stops here
    }
}
```

**Non-opaque was rejected and the reason is the case this rule exists to
close.** A modal scrim must swallow *clicks* aimed at what is under it, and a
non-opaque hitbox is skipped by `topmostOpaqueHitbox(in:at:)` entirely — so
making click targets non-opaque would undo the scrim property in order to fix
the button one. Design spec exit criterion 4 is the scrim half, and it is met.

**The fix is named rather than left as a mystery, and it needs no new state.** A
wheel should stop at an opaque hitbox only when that hitbox is on a **higher
layer** than the topmost scroller under the same point. `Deferred` hoists a
scrim to the root layer; a button inside a `ScrollView` shares its scroller's
layer — so the `layer` key already on every `Hitbox` separates the two cases
with no ancestor walk. It is written into `Window.applyScroll`'s own doc.
Deliberately not implemented in the milestone that introduced click handling:
`applyScroll` is the site of two shipped intermittent scroll defects that only a
human found, and does not get an unreviewed refinement during a task about
clicks.

**The mitigation in use today is placement.** `Sources/MetalUIDemo/main.swift`
puts its counter in the main pane and not in the `ScrollView`, and says so at
the call site.

**Pinned by `aClickTargetInsideAScrollViewSwallowsTheWheel`**, which asserts the
wrong answer on purpose and says so in its own message. No fixture or golden
encodes it and none could — CSS's wheel routing is not what this implements.

**18. A `@State` in a removed conditional subtree is NOT reset the way SwiftUI
resets it — it is retained, and below `sweepThreshold` it is retained
indefinitely.** The only entry in this list whose disagreement is with
**SwiftUI**, and the only one added by the same milestone that retired two.

SwiftUI destroys a view's `@State` when the view leaves the tree; bring it back
and the counter is 0 again. This framework, since 2026-09-01, does not.
`StateTable.sweep()` retains an unmarked entry with its value and clears only
`isLive`; the **reap** that would eventually discard it runs *only* on a sweep
where `storage.count > StateTable.sweepThreshold` (**256**). A tree whose `storage.count` stays at or below
**256** therefore never reaps anything at all.

> **Corrected 2026-09-10.** This sentence used to read "**256** — which is the
> demo, and most applications — therefore never reaps". That is no longer true
> and the reason is the animation milestone, not this one:
> `animated(_:_:for:pass:)` mints a `$anim` entry on first sight of every
> registering element **unconditionally** (`AnimatedStyle.swift:309`), so an
> element costs a `StateTable` entry whether or not it declares `@State`.
> Measured on the committed `demoLikeRows(_:)` fixture, whose rows carry no
> `@State` at all: `storage.count == 2n + 7` — 87 at 40 rows, **257 at 125**,
> 1007 at 500. The demo's list is 500 rows, so **the demo crosses the gate**.
> Ruling `AN-O` anticipated the pressure but its stated remedy (peek before
> writing) bounds `writeCount`, not `count`, because the first-sighting insert
> is unconditional. The divergence itself is unchanged — retention below the
> gate is still indefinite — but "most applications" sit below it is not a
> claim this record can still make. **`storage.count`, not the live count**: tombstones are still
entries, so an app that churns conditional subtrees crosses the gate without
ever holding 257 live elements at once. `theColdFrameSpikeIsReapedRatherThanRetainedForever`
reaps with **19** live entries, which is this distinction as a green test.

Measured through a real `Window`, with the content closure re-evaluated per
frame so this is the production shape rather than a stored-tree one:

```swift
Box { if flag.on { Counter() } }.id("root")
```

Three frames producing give counts **1, 2, 3**. Set `flag.on = false` and render
**500** more frames. Set it back and render one: the counter reads **4**, not a
fresh 1. `StateTable.count` sat at **1** the whole time, so the reap never
engaged once.

**This is a different claim from divergences 12 and 17's retirement, and
conflating them is the mistake this entry exists to prevent.** Those two are
recorded as closed "for two generations", and that is the *ceiling* — the
behaviour a table over 256 entries gets. It is not what a small tree gets, and
it is not what the phrase suggests. Read together: **`staleAfterGenerations`
bounds retention only once `sweepThreshold` has opened the gate; below the gate
there is no bound.** Every one of this milestone's excursion fixtures inserts
**260 ballast ids** for exactly that reason — to force the gate open so the
bound is observable at all.

**Which is also the coverage statement, and it is a gap rather than a
subtlety.** `aStaleEntryIsRetainedForeverWhileStorageStaysAtOrBelowSweepThreshold`
(`TombstoneTests.swift`) pins the sub-threshold behaviour of the **raw table**,
and nothing pins the **element-level** consequence — that a `@State` in a
vanished `if` comes back holding its old value. No test in the 782 asserts it,
and the two tests a reader would expect to (`TombstoneTests`' and `FocusTests`'
excursion pair) are ballasted above threshold and therefore cannot see it.
Recorded per taxonomy shape 4: silence at a behaviour reads as "not the
behaviour".

**Why it is accepted rather than fixed, stated because "deliberate" is not
"free".** Reaping unconditionally — dropping the `sweepThreshold` gate — makes
every frame walk the whole table, which is the cost the gate exists to avoid and
which `ShapingCache`'s own threshold has the same shape for. Resetting on
removal *instead of* retaining is the SwiftUI answer and is precisely what
divergences 12 and 17 were retired for not doing; it cannot be had at the same
time as their closure without a second notion of "gone", which design spec §5
rejects for the reason the `dispatchClick` identity bullet gives. **So this is a
real trade and not an oversight: SwiftUI's reset and a windowed row's surviving
excursion are the same mechanism pointed in opposite directions.** What would
resolve it honestly is an *element-scoped* removal signal — something that knows
a subtree was removed from the tree rather than merely not produced this frame —
which this framework does not have and which is the same missing distinction
that keeps exit transitions unbuilt (design spec §4.3's correction block).

**What it costs a caller today.** A `@State` counter, a text-field draft, a
disclosure state, or an animation progress in a subtree behind an `if` survives
being dismissed and reappears with its old value. That is *usually* invisible
and occasionally wrong — a modal that re-opens showing the previous session's
half-typed input is the shape to watch for. **The remedy is the same one
divergence 12's entry gave and it did not go away with that entry**: a value
that must be fresh on re-entry belongs in the data, or must be reset explicitly
when the branch is taken. Recorded at `OptionalGroup`'s own doc
(`ElementGroup.swift`), which is where a reader of the vanishing-`if` rule will
be looking.

**The focus half is the same mechanism and is written up in the focus bullet
above rather than as its own entry**, because it is the identical retention with
a different observable: a focused element removed behind an `if` keeps focus
indefinitely below threshold, and its still-produced ancestors keep claiming its
keystrokes.


---

## 2026-09-15: divergences 20–34 (tasks 3, 9 and 12, integrated)

Added to `CLAUDE.md`'s table at integration (record §13). Labels 20 onward were
never used before. Each entry's full mechanism, probe arms and pins live in the
ruling it cites; they are not repeated here.

| # | kind | ruling (decisions doc) | pin |
|---|---|---|---|
| 20 | design | `MC-C` (modifier composition) | `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`; `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne` |
| 21 | vs SwiftUI | `EV-F` (a), probe K2 | `aFocusedElementThatBecomesDisabledLosesFocusAtOnce` |
| 22 | vs SwiftUI | `EV-F` (b), probe K6 | `aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`, `aDisabledPaneContributesNoKeyContext` |
| 23 | vs SwiftUI | `EV-E`, probes P2f/P2g | `aDisabledClickTargetPassesTheClickToWhatIsUnderIt` |
| 24 | vs SwiftUI | `EV-J`, `EV-U`, pixel-length X1/X2 | — |
| 25 | vs SwiftUI | `EV-K`, probe H | E17, pinned wrong on purpose |
| 26 | vs SwiftUI | probe K5 (environment track) | — (pre-existing, measured) |
| 27 | vs SwiftUI | `AB-G`, arms 7, 8 | — |
| 28 | vs SwiftUI | `AB-H`, P0/P1 | `aPressIsRefusedWhereHitTestingIsDisabled` |
| 29 | vs SwiftUI | `AB-G`, R7 | — |
| 30 | vs SwiftUI | `AB-T`, C1, C5, C5i | arm 7 of `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| 31 | vs SwiftUI | `AB-J`, arm 13 | — |
| 32 | vs SwiftUI | `AB-L`, R16 | — |
| 33 | vs SwiftUI | `AB-F`, 10b, R6, R11 | — |
| 34 | vs SwiftUI | `AB-P`, arm 4 | unpinned |

## 2026-09-16: divergences 35–50, and 15 retired (tasks 4 and 5, integrated)

Added to `CLAUDE.md`'s table at integration (record §16). Each entry's full
mechanism, probe arms and pins live in the ruling it cites.

| # | kind | ruling (decisions doc) | pin |
|---|---|---|---|
| 35 | vs SwiftUI | `FR-E`, frame probe D4 | `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`, wrong on purpose |
| 36 | vs SwiftUI | `FR-N`, A5 | `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`, wrong on purpose |
| 37 | vs SwiftUI | `FR-B`, D12 | `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` (deliberate) |
| 38 | vs SwiftUI | `FR-L`, `FR-R`, `SA-J`; negative-sizes H6, H10 | — (task 7) |
| 39 | vs SwiftUI | `FR-D`, C1 | `anIdealDimensionOnTheLegacyFrameTraps` |
| 40 | unfixed defect | `FR-T` | `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`, wrong on purpose |
| 41 | vs SwiftUI | `OM-I`, content-shape H1 | `metalUIsDefaultHitRegionIsTheElementsWholeFrame` |
| 42 | vs SwiftUI | `OM-K`, P1/P2 | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` |
| 43 | vs SwiftUI | `OM-AJ`, H6 | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` |
| 44 | vs SwiftUI | `OM-AL`, X1–X3 | `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`, wrong on purpose |
| 45 | vs SwiftUI | `OM-N`, `OM-AA` a (folded in: the same fact seen from both paths), G3/G4 | `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot` |
| 46 | vs SwiftUI | `OM-AH`, G1/G2 | `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies` |
| 47 | vs SwiftUI | `OM-G`, border-clip C1 | `aBareCornerRadiusDoesNotClipTheChildren` (C3/D1 orders unpinned) |
| 48 | vs SwiftUI | `OM-F`, component G7/G8 | `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` |
| 49 | vs SwiftUI | `OM-W`, D2 vs M1 | `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot` |
| 50 | vs SwiftUI | record §16; content-shape S1 (S2 agrees, S3 the control) | `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`, wrong on purpose |

**15 retired** (`OM-U`): `pushClip` now adds `activeOffset`, so a `ScrollView`
inside a scrolled `ScrollView` gets its own mask. Pins:
`aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` (inverted, name
kept) and `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints`. Never reuse
the label.

## 2026-09-16: divergences 36, 37 and 40 retired, 51–58 added (plan task 6, containers)

Added to `CLAUDE.md`'s table by the containers Docs phase (record §17). Rulings
are in `docs/superpowers/2026-09-16-containers-decisions.md`; probe arms in
`docs/probes/swiftui-stack-algorithms.swift` unless stated.

| # | kind | ruling | pin |
|---|---|---|---|
| 51 | vs SwiftUI | `CN-H`, probe S (text edges font-derived) | `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing` (task 11) |
| 52 | vs SwiftUI | `CN-P` 1, probe S | `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight` (task 7) |
| 53 | vs SwiftUI | `CN-P` 2, A5 | `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` (task 7) |
| 54 | vs SwiftUI | `CN-P` 3, SC2 | `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` (task 7) |
| 55 | vs SwiftUI | `CN-P` 4, G1 | — (covered by the CSS goldens; task 7) |
| 56 | vs SwiftUI | `CN-N`, component G7 | `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`, `chainedFramesRemainConcreteAndNestTheirLayoutNodes`, as it stands (task 7) |
| 57 | vs SwiftUI | `CN-K`, `swiftui-overlay-presentation.swift` H3 | unpinned (task 12) |
| 58 | design | `CN-E` | `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` |

**36 retired** (`CN-N`): a legacy frame over exactly one node lowers to a
one-cell `display: .stack`, so an oversized child keeps its size and overflows
both axes as SwiftUI's A5 does. Its pin
`aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows` was replaced by
`aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes`. A frame over
several nodes keeps the flex row (divergence 56).

**37 retired** (`CN-F`, reversing `FR-B`): the kernel's frame with an infinite
maximum answers ∞ at an infinite proposal, as SwiftUI's D12 does. Its pin
`aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` was deleted and
replaced by `anInfiniteProposalIsAnsweredWithInfinity`.

**40 retired** (`CN-O`, resolving `FR-T`): the sizing modifiers always took a
fraction; they are now spelled `width(fraction:)`, `height(fraction:)` and
`flexBasis(fraction:)`, and the `percent:` spellings are deprecated renames
forwarding unchanged (guard
`thePercentSizingModifiersAreDeprecatedRenamesOfFraction`). Its pin
`aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock` is now
`aFractionSizeResolvesAgainstItsContainingBlock`.

**35's owner** moves from task 6 to task 7 (`CN-Q`). Never reuse 36, 37 or 40.

## 2026-09-17: divergence 59, and owners amended (plan task 7 stage 1)

Added to `CLAUDE.md`'s table at the stage-1 Docs phase (record §18). No
divergence is retired: production frames still run under the legacy authority.

| # | kind | ruling (decisions doc) | pin |
|---|---|---|---|
| 59 | vs SwiftUI | `LR-X`, `swiftui-engine-replacement-stage1.swift` T3/T4 | `aProposalTextBelowItsNarrowestWordAnswersItsWidestCharacterWhereSwiftUIAnswersTheProposal`, wrong on purpose (task 7 stage 2) |

**Amended, not retired:**

- **39**: the trap moved from construction to legacy registration (`LR-H`); the
  pin `anIdealDimensionOnTheLegacyFrameTraps` was amended to render the frame.
  Under the proposal authority the ideals lower onto the kernel frame; stage 6b.
- **35, 53, 55**: SwiftUI's answer under the proposal authority already, pinned
  by `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`,
  `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` and
  `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren`; production at stage
  6b (`LR-L`).
- **52** → task 7 stage 2; **54** and **56** → stage 3 (`LR-L`).

## 2026-09-21: 59 retired, 60–70 added (plan task 7 stages 2 and G, integrated)

Added to `CLAUDE.md`'s table at the `integrate/stage-2-grids` Docs phase
(records §21, §22, §23). The table goes from forty-eight entries to
**fifty-eight**: 59 out, 60–70 in. Production frames still run under the legacy
authority, so **nothing here is production-visible yet** except 60, which is
about a measurement both the proposal path and the future production path use.

**Retired, and never reused:**

- **59** — a text measurement proposed a width below its narrowest word.
  Stage 2's lane 3 clamps every text answer to `min(proposal, widest line)`
  (`LR-AU`), which is SwiftUI's answer, so `ProposalText` and a lowered `Text`
  now agree with SwiftUI here. The test was renamed and now pins the agreement:
  `aProposalTextBelowItsWidestBrokenLineAnswersTheProposal` and
  `aProposalTextBreaksInsideAWordAndAnswersItsWidestLineUpToTheProposal`.
  The **lowered** half of that clamp was pinned by nothing until the
  integration's X3 (record §23, mutation XM4).

| # | kind | ruling (decisions doc) | pin |
|---|---|---|---|
| 60 | vs SwiftUI | `LR-AY` item 4, `swiftui-engine-replacement-stage2.swift` group Y | **unpinned** (task 11; must be settled before stage 6b) |
| 61 | vs SwiftUI | `GR-O` 1 | test 2.9 `theModelsDisagreementsWithSwiftUIArePinned`, wrong on purpose (task 15) |
| 62 | vs SwiftUI | `GR-O` 2, `GR-AH` item 4 (arm O1) | `theModelsDisagreementsWithSwiftUIArePinned`, `theModelDisagreesWithSwiftUIOnTheDivergenceCorpus`, wrong on purpose (task 15) |
| 63 | vs SwiftUI | `GR-O` 3 | `gridCellColumnsZeroLaysOutAsOne` |
| 64 | vs SwiftUI | `GR-O` 4 | guard `aGridCellAnchorIsNinePoint` |
| 65 | vs SwiftUI | `GR-O` 5 | `textRowsTakeTheDefaultRowSpacing`, wrong on purpose |
| 66 | vs SwiftUI | `GR-O` 6 | `aModifierOnAMultiCellGridRowTraps` |
| 67 | vs SwiftUI | `GR-O` 7, `GR-S` | `aColumnCountAboveInt32MaxTraps` |
| 68 | limit | `GR-S` | unpinned; `aColumnCountAboveInt32MaxTraps`' doc comment records it |
| 69 | design | `GR-O` 9, `GR-AF` | `removingACellFromARowHandsItsStateToTheNextCell`, `removingAWholeGridRowHandsItsStateToTheNextRow`, wrong on purpose (task 8) |
| 70 | vs SwiftUI | `GR-X`, `GR-O` 8 | `aStackServesItsLeastFlexibleChildFirst`, grid tests 2.10/2.11 — **owned by task 6**, found by the grid corpus |

**Amended, not retired:**

- **52**: owner "task 7 stage 2" → **"task 7 stage 8"**. Stage 2's test 5.8
  characterizes the gap-vs-spacing default; closing it is a vocabulary change
  (`LR-AL`), not a lowering.
- **55**: gains two pins beside `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren`
  — `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` and
  `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`.
- **53**: unchanged; still "lowered under the proposal authority, production at
  stage 6b".

**Not numbered, deliberately.** Stage 2's other new disagreements are
**proposal-authority only** and are pinned by name rather than numbered: growers
share equally (2.2); a zero-basis `Text` grower breaks inside its word (2.4); a
`Text`'s `Style.padding` pads it (4.2); a declared size below the padding +
border sum keeps its frame (4.3); a negative margin past its own box clamps at 0
(4.5); an animated `flexGrow` snaps its structure (2.13, now in `CLAUDE.md`'s
animation snap list).

## 2026-09-22: 48, 54 and 56 amended (plan task 7 stage 3)

Record §25; rulings in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
**No number is retired and none is added** — the table stays at **fifty-eight**.
All three amendments are **proposal-authority only**: production still runs the
legacy authority until stage 6b, so nothing here is production-visible yet.

- **48** (`.width` on a `Component` overwrites its members' declared width).
  **Answered under the proposal authority** by stage 3 lane 4 (`LR-BG`): the
  amend is one native frame per member, aligned per axis, so each member keeps
  its own width and is centred in its own 70 — SwiftUI's G7/G8. Still wrong on
  purpose under the legacy authority; retirement is stage 6b's. New pins:
  `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`,
  `aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares`.
- **54** (a `ScrollView` takes its cross axis from its parent where a
  `ProposalScrollView` takes its content's). **Survives the stage-3 lowering**,
  and stage 3's first writing of `LR-BC` was wrong to say it closed: a lowered
  `ScrollView` records a `LoweredItem`, so stage 2 wraps it in a stretch item
  frame whose rect is aliased as the element's; `ProposalScrollView` records
  none. Now pinned as a literal by
  `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`, and
  **removed from stage 6b's retirement row** — it is stage 11 / task 10's.
- **56** (a `.frame` over a multi-member `Component` squeezes its members).
  **Answered under the proposal authority** by stage 3 lane 5 (`LR-BH`): a row
  of per-member frames at spacing 0, so the members keep 30 and 50 rather than
  being shrunk to 26 and 44. The 140 against SwiftUI's 148 is the enclosing
  stack's own 8pt spacing, and framed members staying one flex item is `TB-M`'s,
  stage 11. Still wrong on purpose under the legacy authority. New pin:
  `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`.

## 2026-09-23: 13, 14 and 18 amended (plan task 7 stage 4)

Record §27; rulings `LR-BQ`…`LR-CG` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
**No number is retired and none is added** — the table stays at **fifty-eight**.
13 and 14 gain text, not numbers; 18's *numbers* move, and its divergence does
not.

- **13** (a `List`'s window is computed against a one-frame-stale viewport
  extent). **Survives stage 4 unchanged.** The windowed `ProposalLayout` reads
  the same `ScrollContext` at the same phase — the window is still decided in
  `requestLayout` against last frame's extent — so the one-frame resize error
  and its two rows of overscan are identical on both authorities. The contract
  pin (`scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`)
  is untouched, and the *effect* is still reached by no test.
- **14** (a `List` windows against its SCROLLER's origin, so a `List` with a
  flow sibling above it renders blank). **Survives stage 4 unchanged, and its
  pin now runs under both authorities.**
  `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` is one of the
  20 `ListTests` scenarios lane 3 parameterised, so the wrong answer is
  asserted **twice**, once per engine — whoever fixes this must delete or
  invert **both arms**. `MP-L`'s blocker is unchanged: `requestLayout` still
  has no position, and the windowed layout does not give it one.
- **18** (a `@State` behind a removed `if` is retained, not reset). **The
  divergence is unchanged; its numbers move by one**, because stage 4 demoted
  the legacy windowing spacer from a `Box` element to a bare node, so it no
  longer mints a `$anim` entry. On the committed `demoLikeRows(_:)` fixture the
  formula goes **`2n + 7` → `2n + 6`**, the crossing of `sweepThreshold`
  **125 → 126** rows, and the count at 500 rows **1007 → 1006**. Measured on a
  fresh `StateTable` per row — `demoLikeRows(n)` cold, then three frames of
  `demoLikeRows(0)`, past `staleAfterGenerations` (2), so only the size gate can
  keep the rows (record §27 §6.3):

  | *n* | before, cold | reaped? | after, cold | reaped? |
  |---|---|---|---|---|
  | 40 | 87 | no | 86 | no |
  | 124 | 255 | no | 254 | no |
  | 125 | 257 | **yes** | 256 | **no** |
  | 126 | 259 | yes | 258 | **yes** |
  | 127 | 261 | yes | 260 | yes |
  | 500 | 1007 | yes | 1006 | yes |

  The gate is `storage.count > sweepThreshold` with `sweepThreshold == 256`, so
  crossing needs 257. **The before column reproduces this entry's own `2n + 7`,
  125 and 1007 exactly**, which is what says the instrument is the right one
  rather than a differently-shaped fixture. The **element-level consequence is
  still unpinned**, exactly as the entry says: no test asserts that a `@State`
  in a vanished `if` comes back holding its old value.

## 2026-09-23: 9, 10 and 11 amended (plan task 7 stage 5)

Record §29; rulings `LR-CH`…`LR-CS` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. **No number is
retired and none is added** — the table stays at **fifty-eight**. All three
amendments are **proposal-authority only**: production still runs the legacy
authority until stage 6b, so nothing here is production-visible yet.

- **9** (an all-`auto`-inset absolute box sits at its containing block's
  origin, not CSS's static position). **Survives, on both authorities.**
  Stage 5 makes a `Deferred` whose one content node is `.position(.absolute)`
  a presentation root; inside it, the element lowers to the legacy answer —
  the containing-block origin, not a static position (`LR-CI`). A new arm of
  `PresentationLoweringTests`' 1.1 pins it under `.proposal` alongside the
  existing legacy pin.
- **10** (`Deferred` escapes every ancestor clip regardless of containing
  block; no way to ask for CSS's answer). **Unchanged**, and its pins now run
  under both authorities — lane 3's must-not-move set
  (`PresentationWindowTests`) and lane 2's hoisted `DeferredTests` scenarios
  exercise the same escape through the proposal lowering, not a second
  mechanism. The row gains SwiftUI evidence it lacked: probe
  `swiftui-overlay-presentation.swift` group P/Q shows this agrees with
  SwiftUI's **presentation** (a sheet/popover, P4/P5 — outside the presenting
  view's layout and render tree) and disagrees with SwiftUI's **overlay**
  (`.overlay`/`.zIndex`, P1/P2 — an in-flow sibling that paints on top, not a
  portal). Stage 5's design narrowed the probe claim from "SwiftUI has no
  in-flow portal at all" to "no probed SwiftUI spelling is an in-flow portal"
  (`LR-CP` item 5); this row's SwiftUI comparison is stated at that narrower
  strength.
- **11** (an absolute box inside a `ScrollView` is still clipped and scrolled
  by it; the escape is `Deferred`). **Becomes legacy-only from here.** Under
  the proposal authority an absolute box outside a `Deferred` is removed
  (`LR-CK`): it reports `[<site>.position, <site>.inset]` by name (owner stage
  10) rather than lower to a different answer, so `AbsoluteOverlayTests`'
  `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`'s `.proposal`
  arm asserts the report, not the clip. The divergence itself — the legacy
  engine's behaviour — is unretired; it retires with the legacy authority at
  stage 9, the same stage that deletes the `deferred.*` reports (`LR-CL`).

**An erratum to record §27, found while measuring these:** §27 §8.2 says
`aListInsideADeferredIgnoresTheEscapedScrollersOffset` "aborts" under
`.proposal`. Measured at `e5caefb` (record §29 §2.3), switched to `.proposal`
it **passes**; the claim was never run. It was not a divergence row and
retracts nothing here — noted because it was found by the same measurement
pass.

## 2026-09-23: no row changed (plan task 7 stage 6a)

Record §30; rulings `LR-CT`…`LR-DE` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. **The table
stays at fifty-eight; no number is retired, added or amended.** Stage 6a
deprecates the public `LayoutPass.requestNode`/`requestLeaf` and moves every
in-repo test caller off them, but touches `Sources/` only with two
`@available` attributes and one `owningStage` literal
(`.customElement` → `"9"`) — none of it changes what production does or
what a legacy-vs-SwiftUI comparison reads. The entry measurement's own
classification (root placement, `hidden()`, CSS answers — record §30 §4) is
new *evidence for stage 6b and 7b's future rulings*, not a divergence in its
own right: nothing in it is reachable outside a test today, since
`LayoutAuthority.proposal` stays inert in production until stage 6b (record
§05's row, unchanged — see that file's own 2026-09-23 section).
