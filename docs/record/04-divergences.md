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

Record §38; rulings `LR-CT`…`LR-DE` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. **The table
stays at fifty-eight; no number is retired, added or amended.** Stage 6a
deprecates the public `LayoutPass.requestNode`/`requestLeaf` and moves every
in-repo test caller off them, but touches `Sources/` only with two
`@available` attributes and one `owningStage` literal
(`.customElement` → `"9"`) — none of it changes what production does or
what a legacy-vs-SwiftUI comparison reads. The entry measurement's own
classification (root placement, `hidden()`, CSS answers — record §38 §4) is
new *evidence for stage 6b and 7b's future rulings*, not a divergence in its
own right: nothing in it is reachable outside a test today, since
`LayoutAuthority.proposal` stays inert in production until stage 6b (record
§05's row, unchanged — see that file's own 2026-09-23 section).

## 2026-09-23: 4 amended (plan task 7 stage 6b, the root switch)

Record §41; rulings `LR-DF`…`LR-DR` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. **No number is
retired and none is added** — the table stays at **fifty-eight**. Stage 6b
throws the switch: `Frame.defaultLayoutAuthority` is now `.proposal`, so
production runs the proposal engine by default, and this is the first stage
whose ruling on divergence 4 is production-visible rather than a
proposal-authority-only evidence row.

- **4** (ruling `CS-I`: an `auto` root axis takes the offered extent and sits
  at (0, 0), where a browser fills the inline axis and shrink-wraps the block
  one). **Becomes legacy-authority only.** `LR-DG` rules that production's
  root placement is `CN-J`, not `CS-I`: a native root is measured at the
  window's proposal and centred at its own answer, unchanged by the switch
  (`computeRootLayout`'s native branch is untouched; `docs/probes/swiftui-stack-algorithms.swift`'s
  R control/R1–R4, re-run 2026-09-23, back SwiftUI's centred answer). Every
  legacy root now lowers to a native one under the default authority, so
  `CS-I` is reachable only through an explicit `.legacy` `Frame`/`Window` —
  pinned by its own CSS-engine tests
  (`anAutoRootWithNoOfferedExtentMeasuresItsContent` and the root-sizing tests
  in `MetalUILayoutTests`), which stay green because they construct that
  authority explicitly. The row is not retired here: it retires with those
  CSS-engine tests at 7b (`LR-DG` item 2), alongside the 15 tests this stage
  pinned `.legacy` for 7b (12 CSS, 1 RP+CSS-frame, the 2 of `LR-DQ` item 2);
  its other 5 pins (3 N9, 2 tokenizer tests) are stage 9's (`LR-DQ` item 2:
  20 pins in all). **What it costs if wrong**: a hugging production root
  that regressed to `CS-I`'s top-left, window-filling answer would move every
  such root from the window's centre back to its top-left corner — loud on
  the first frame, and pinned by `aHuggingLegacyRootIsCentredInAProductionWindow`
  (record §41 §12.2–§12.5; mutations M2a, top-leading, and M2b, the window
  rect, each redden it and every other root-placement-reading test).

## 2026-09-23: 55 amended (plan task 7 stage 7a, the goldens retired)

Record §48; rulings `LR-DS`…`LR-EB` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. **No number is
retired and none is added** — the table stays at **fifty-eight**. Stage 7a
deletes the 97 WebKit goldens and their consumers; every golden has a row in
record §48 §4. Only one live row cited the goldens as its pin:

- **55** (`CN-P` 4, G1: CSS shrinks items by base-size-weighted factors where
  SwiftUI compresses without weights). Its pin column read "— (covered by the
  CSS goldens; task 7)". The goldens that carried the CSS side
  (`flex_row_shrink`, `flex_row_fractional_shrink`, `flex_row_shrink_to_zero`,
  `flex_row_shrink_padded_weighting`, `flex_row_explicit_min`) are retired as
  **D** rows (record §48 §4, rows 23, 27, 45–47). The row is now pinned by
  name on both sides: the CSS engine's weighting by `shrinkIsWeightedByBaseSize`
  (`FreezeLoopTests`, a CSS-engine test that stays until 7b), and the proposal
  authority's unweighted answer by
  `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren`,
  `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`,
  `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt` (stage
  2's pins, above) and stage 7a's
  `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`, whose
  `flex_row_shrink_padded_weighting` arm pins the golden's own tree at the
  native answer (a 200, b 200 at 200). It retires with the CSS engine (7b/9).

Every other row's pin was checked by grep against the names of the 96 removed
consumer tests and the eight removed `GeneratorTests`/`OracleTests`: none
cites one. The prose paragraphs above that say "no fixture or golden encodes"
a divergence stay true, and are now true of every divergence.

## 2026-09-24: 4 retired; 9's legacy pin moves; 48, 52, 53 and 55 keep their fact with a new pin (plan task 7 stage 7b)

Record §49; rulings `LR-EC`…`LR-EP` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. Stage 7b
retires the non-golden CSS-engine tests of spec §2.6's 24 files and the
element tests stages 6a/6b pinned `.legacy` with a 7b owner (245-row table,
record §49 §4). Every pin below was checked against that table by grep for
its exact name.

- **4 retires** (58 → 57 live; joins the never-reused list, alongside 3, 5–8,
  12, 15, 17, 36, 37, 40, 59). Its two CSS-engine tests
  (`autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot`,
  `anAutoRootWithNoOfferedExtentMeasuresItsContent`, both D, record §49 rows
  56–57) and `RootSwitchTests`' `.legacy` arm (row 245, T) are gone. **This is
  not "no pin left"**, corrected from record §49's own first draft (`LR-EP`):
  `CS-I`'s behaviour — a hugging legacy root fills the offered extent from
  (0, 0) — stays exercised, unnamed, by the `.legacy` arm of roughly thirty
  `AuthorityCoverage`-parameterised tests (measured by mutating
  `Frame.computeRootLayout`'s legacy branch: 43 issues, 30 tests, record §49
  §8) until stage 9 deletes the legacy authority and those arms with it. The
  row retires because nothing names `CS-I` any more by a CSS-engine-subject
  test, not because the behaviour is gone.
- **9** (an all-`auto`-inset absolute box sits at its containing block's
  origin, not CSS's static position). **Unchanged**, but its pre-stage-5
  legacy pin, `allAutoInsetsPlaceAtTheContainingBlockOriginNotTheStaticPosition`
  (`AbsolutePositioningTests.swift`), is retired (R, record §49 row 141) along
  with the whole file. The fact is unaffected: stage 5's amendment (above)
  already added the live pin,
  `PresentationLoweringTests`' 1.1 (its `.proposal` arm), and row 141's own
  replacement, `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`'s
  "no insets, after an in-flow sibling (divergence 9)" arm, carries the
  legacy answer that the retired test used to.
- **48, 52, 53 and 55 keep their fact; each loses the single-authority test
  that used to be its only CSS-engine pin, superseded by a still-live
  differential test that already asserted both engines' answers in one body.**
  None of these divergences is *about* the legacy-vs-proposal split — 48 and
  55 are legacy-vs-SwiftUI facts still true under an explicit `.legacy`
  `Frame`/`Window` (production reaches neither since stage 6b); 52 and 53 are
  `Row`/`Column`-vs-`HStack`/`VStack` container-identity facts, true under
  *either* authority, since a lowered `Row`/`Column` still defaults to 0 and a
  lowered `Stack` still offers fit-content (`aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault`'s
  own `expectFullAgreement` checks legacy and lowered **agree** at the Row/Column
  default). Retired pin → surviving pin, each checked by reading the
  surviving test's body for both engines' numbers:
  - **48**: `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` (D, row
    219) → `LoweringComponentTests.aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`,
    whose `lane4Rects` calls read both `legacy:` and `lowered:` rects per
    member (already cited as 48's proposal-side pin since stage 3; now its
    only pin).
  - **52**: `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`
    (R, row 226) → `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault`
    (both engines' gap-0 and gap-8 arms) plus
    `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` (the
    `HStack`/`VStack` half; record §49 §6.2's own reading of this row).
  - **53**: `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` (R,
    row 227) → `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`
    (4.2; both engines in one body; stack-algorithms A5, re-run 2026-09-24).
  - **55**: `shrinkIsWeightedByBaseSize` (D, row 112, `FreezeLoopTests` —
    deleted whole) → `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`
    (already cited by 7a's amendment; its `legacyA`/lowered pair in one body
    is both sides at once, so nothing is lost).
  **56** needed no amendment: its 2026-09-16 pins
  (`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`,
  `chainedFramesRemainConcreteAndNestTheirLayoutNodes`) are retired (R, rows
  208–209) but stage 3 had already replaced them with
  `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`,
  which is not in this stage's retirement scope (a `Lowering*` differential,
  not a CSS-engine-subject test) and stands unchanged.

**What it costs if wrong.** Divergences 48, 52, 53 and 55 read as unpinned to
a reader who greps only for their original 2026-09-16 test names — each now
has a live pin, named above; a reader following the frozen table's original
column without this section would conclude wrongly that the fact went
untested.

## 2026-09-24: no row changed (plan task 7 stage 8)

Record §50; rulings `LR-ER`…`LR-FB` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. **The table
stays at fifty-seven; no number is retired, added or amended.** Stage 8
deprecates the eight `StyledElement` sizing modifiers toward `.frame` and
converts every in-repo caller by class (F to `.frame`, K to
`CSSSizing.swift`'s same-closure-body helpers, D into a deprecated witness),
no converted call site's assertion is edited (`LR-EW`'s F rule, `LR-FB`'s K
rule; the seven T rows re-derive demo literals and G4's control arm, none a
divergence pin) and no test is retired (class R is empty). Divergence **48**'s pin,
`LoweringComponentTests.aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`,
is about `Component.width`, which stage 8 does **not** deprecate (`LR-ER` item
2: it neither writes an element's own box nor returns `Self`) — the file's
other, `StyledElement`-typed sizing calls move to `css*` spellings (K1, lane
2), but the pin's own subject and assertion are untouched. No other row's
named pin calls one of the eight either (checked by grep against record §04's
table above): 52/53 are about `Row`/`Column`/`Stack`/`ZStack` container
defaults, 55 about `flexShrink` compression, 9 about absolute-box placement,
4 already retired at 7b.

**Divergence 52's owner moves, its row does not** (`LR-ER` item 3 as amended by
`LR-EY` item 2): `Row`/`Column` default spacing leaves plan task 7 for **plan
task 15** (closeout), because every remaining stage of task 7 exits at 0 px
against its predecessor and closing 52 moves every default-gap caller's pixels.

## 2026-09-24: 11 retired; 4's loose end closes; 9, 10, 13, 14, 48, 52, 53, 55 and 56 re-read on the one authority; 18 untouched (plan task 7 stage 9)

Record §51; rulings `LR-FC`…`LR-FL` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. Stage 9 deletes
the CSS engine, the layout authority and the legacy registrars (spec
`specs/2026-09-24-engine-stage-9-design.md` §8); the frame goes 57 → **56
live**.

- **11 retires** (56 live; joins the never-reused list, alongside 3, 4, 5–8,
  12, 15, 17, 36, 37, 40, 59). Divergence 11 was already **legacy-only** since
  stage 5 (an absolute box inside a `ScrollView` is still clipped and scrolled
  by it under the CSS engine; the escape is `Deferred`) — it retires now
  because the legacy engine it describes is gone.
  `AbsoluteOverlayTests.anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`
  is deleted (record §51 §6.1, row L1-15); a comment in its place names the
  row and its replacements. **This is a genuine retirement, not "no pin
  left"**: unlike divergence 4, 11's own definition names the legacy engine's
  behaviour as its subject, so once that engine is gone there is nothing left
  to observe, named or not. The proposal-side fact it sat beside —
  `[box.position, box.inset]` reported at the consumer for an absolute box in
  a `ScrollView` with no `Deferred` — survives as its own thing, now the only
  answer: `PresentationLoweringTests.aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName`'s
  "absolute in a `ScrollView`, no `Deferred`" arm (was item 1.5's seventh row);
  the `Deferred` escape half that always existed beside it is
  `DeferredTests.aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScroll`
  and the portal mask tests, unaffected by this stage.
- **4's loose end closes.** 4 retired at 7b as a row (no CSS-engine-subject
  test named `CS-I` any more), but its behaviour stayed exercised, unnamed, by
  the `.legacy` arm of roughly thirty `AuthorityCoverage`-parameterised tests
  until "stage 9 deletes the legacy authority and those arms with it" (7b's
  own wording). Stage 9 does exactly that: `AuthorityCoverage` and every
  `.legacy` arm it drove are deleted (lanes 1 and 2, record §51 §5.2, §6.1).
  No new number moves — 4 was already retired — but the CSS engine's hugging
  behaviour is now gone from the suite in every sense, named or not.
- **9** (an all-`auto`-inset absolute box sits at its containing block's
  origin, not CSS's static position). **Survives, on the one authority.**
  Its subject was never the split between two engines, only the placement
  rule the lowering reproduces — collapsing the differential harness to one
  authority (`LR-FI` item 1) does not touch it.
  `PresentationLoweringTests.aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`'s
  "no insets, after an in-flow sibling (divergence 9)" arm keeps its literal
  (`pBounds(0, 0, 30, 20)`), asserted once now rather than against a second
  engine.
- **10** (`Deferred` escapes every ancestor clip regardless of containing
  block; no way to ask for CSS's answer). **Unchanged, on the one authority.**
  `PresentationWindowTests`' must-not-move set and `DeferredTests`' hoisted
  scenarios (both collapsed to a single assertion by lane 1, record §51
  §5.2/§5.3) still exercise the same escape through the lowering, the only
  path there has ever practically been in production since stage 6b and now
  the only one that exists at all.
- **13** (a `List`'s window is computed against a one-frame-stale viewport
  extent) and **14** (a `List` windows against its scroller's origin, so a
  `List` with a flow sibling above it renders blank). **Both survive,
  unchanged, now pinned once instead of twice.** `ListTests`' 21
  `AuthorityCoverage`-parameterised scenarios, 14's pin
  (`aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`) among
  them, are collapsed to their single, `.proposal`-shaped assertion (lane 1,
  record §51 §5.2); the fact each divergence names is exactly what that
  single assertion still gets wrong. `MP-L`'s blocker (`requestLayout` has no
  position) is unaffected.
- **18** (a `@State` behind a removed `if` is retained, not reset). **Not
  touched by this stage.** 18 was never about the layout authority — its
  stage-4 amendment was the legacy windowing spacer's own structural change,
  unrelated to the engine deletion — and nothing in stage 9's diff moves
  `demoLikeRows(_:)`'s formula or the crossing row.
- **48, 52, 53, 55 and 56 keep their fact; each loses the "both engines in
  one differential body" shape 7b gave it, collapsed to that body's single
  surviving answer by lane 1's rule** (literals kept, agreement assertions
  deleted, `LR-FI` item 1). None of the five is *about* the authority split,
  so none is touched in substance — only the pin's name, in three of five
  cases (checked by grep against this file's table and record §51 §5.3's
  rename list):
  - **48**: `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`
    → **renamed** `LoweringComponentTests.aComponentsWidthFramesEachMember`
    (record §51 §5.3); the `Component.width`-overwrites-each-member fact is
    the same assertion, now against the lowering's own answer alone.
  - **52**: `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault`
    (`LoweringDistributionTests.swift`) keeps its name — it is one of the base
    site-coverage set's own tests (probe file `## base`/`## head`), not a
    collapsed registry scenario — plus
    `ContainerIntegrationTests.aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer`
    for the `HStack`/`VStack` half, also untouched.
  - **53**: `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`
    → **renamed** `LoweringStackAndLayerTests.aLoweredStackOffersItsChildItsProposal`
    (record §51 §5.3, which notes "the collapsed test no longer asserts the
    legacy half"): the lowered `Stack`'s fit-content answer is now this
    test's whole subject; the `ZStack`-offers-its-proposal side of the
    contrast is carried by `swiftui-stack-algorithms.swift`'s A5 (SwiftUI
    evidence, unaffected by this stage) rather than by a second answer in the
    same test body.
  - **55**: `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`
    (`LoweringItemTests.swift`) keeps its name, its `legacyA`/lowered pair
    collapsed to the lowered answer alone (the fact — `flexShrink`
    compression weighted by base size — is unaffected).
  - **56**: `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`
    → **renamed** `LoweringComponentTests.aFrameOverAMultiMemberComponentFramesEachMember`
    (record §51 §5.3); unchanged in substance, per stage 8's note that this
    pin already stood outside that stage's own retirement scope.

**What it costs if wrong.** A reader following 48, 52, 53 or 56 by the name
7b's or earlier sections give would find no such test at this commit; the
renames above are the fix. 11's row looks orphaned without this section's
note that it is a genuine retirement, not another "no pin left" correction
like 4's.

## 2026-09-24: no row changed; 54's live pin named (plan task 7 stage 10)

Record §53; rulings `LR-FM`…`LR-FU` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. **The table
stays at fifty-six; no number is retired, added or amended.** Stage 10 deletes
`Style`'s fields no lowering reads (`aspectRatio`, `overflow`, `flexWrap`,
`alignContent`, `border`, `Position.relative`), narrows the rest to `package`
and makes every inherited `Style`-field report a permanent refusal by name
(`UnlowerableField.owner`, `LR-FO`). Spec §9 asked for 9, 10 and 54 to be
re-read against that wording; the stage's Record phase said it had (record
§53 §6.4) but no commit touched this file, so the branch check (`LR-FU`) made
the re-read and wrote this section:

- **9** (an all-`auto`-inset absolute box sits at its containing block's
  origin). **Unchanged.** Its pin,
  `PresentationLoweringTests.aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`,
  is not in either lane's T list and its body is unedited; the only
  `PresentationLoweringTests` change (`T1.2`) is to
  `aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName`, whose
  `.relative` arm goes with `Position.relative` and whose `…absolute` owner
  reads `nil`. An absolute box outside a `Deferred` still reports
  `[box.position, box.inset]` — now a permanent refusal, not stage 10's work.
- **10** (`Deferred` escapes every ancestor clip). **Unchanged.**
  `PresentationWindowTests` and `DeferredTests` are unedited; the offscreen
  fourteen images and a real-window capture read 0 differing against
  `8095fd9` (record §53 §7).
- **54** (a `ScrollView` takes its cross axis from its parent where SwiftUI's
  takes its content's). **Unchanged in fact; the table's pin name is stale
  since 7b, not since this stage.** The row above names
  `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents`,
  retired at 7b (record §49 row 228, R) and replaced by
  `LoweringScrollTests.divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`
  (the stage-3 section above already names it) and
  `aLoweredScrollViewFillsItsProposalOnTheScrollingAxis`. Both are green and
  unedited at stage 10; `T1.3` changes only the neighbouring
  `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`'s
  owner line (`owningStage == "3"` → `owner == nil`).

**What it costs if wrong.** A reader following 54 by the table's name finds no
such test; the name above is the fix. A reader expecting a stage-10 section
because record §53 §6.4 promised one found none until this one.

## 2026-09-25: 45 retired; 54 and 56's remainder re-owned (plan task 7 stage 11, modifier unification)

Record §54; rulings `LR-FV`…`LR-GG` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. **The table
moves from fifty-six to fifty-five live; 45 joins the never-reused list.**

- **45 retires** (a legacy `.opacity(0.5).background(x)` left the fill
  faded, where SwiftUI leaves it outside the scope, `OM-N`/`OM-AA` a). The
  write-order bug — `.opacity` and `.background` are fields of one
  `Decoration` whose write order was lost — is fixed on both paths by
  `Decoration.escapesOpacity` (one member per slot, inserted by a write only
  while `opacity < 1`, emptied by `.opacity`), and `paintDecoration` now
  emits an escaped fill before its opacity scope opens and an escaped border
  after it closes (`LR-FW`). The old pin,
  `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot`, is renamed
  `aBackgroundOrBorderWrittenAfterOpacityEscapesIt` and now asserts the fix
  rather than the bug (T2.1, record §54 §9.1); its H2 arm (the border's own
  divergence) retires with it, so the row's citation moving to "G3/G4, H1/H2,
  now retired" is one row's worth of two SwiftUI arms, not two divergences.
  `theOpacityOrderAnswersTheSameOnBothPathsThroughTheUnifiedType`
  (`OpacityOrderTests`, N2.1) is the new cross-path pin `OM-AA` a's clause
  asked for. Divergence 46 (a second `.opacity` replaces the first,
  `OM-AH`) is untouched — `OM-AH`'s reasons stand, and no row of this stage
  hands it here.
- **54's remainder re-owned.** Spec §6.5 (`LR-GA` item 5) hands it from
  "stage 11 / task 10's" (record §04's 2026-09-22 section) to **plan task 10
  alone**: the fix is a scrolling answer that moves every legacy
  `ScrollView`'s cross axis, not a modifier question, so stage 11 disposes
  of nothing here. Its pins are unedited by this stage.
- **56's remainder re-owned.** A `.frame` on a multi-member `Component`
  stays one flex item in its parent (`TB-M`), where SwiftUI's `Group` makes
  each framed member its own. Spec §6.2 reconciles `Component.width`/`height`
  versus `.frame` by ruling with no API change, but making `.frame` itself
  distribute per member is `Group` semantics — **re-owned to plan task 8**
  (`CN-Q`), not closed here.

- **35's pin named** (the adversarial branch check, `LR-GG` item 5 b). The
  row's listed pin, `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`,
  was retired at 7b (record §49 row 196, "divergence 35's legacy side") and
  no later section said what pins the row. Its live pin is
  `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`
  (`LoweringStackAndLayerTests`): the lowered flexible frame is greedy,
  SwiftUI's answer, in the only engine since stage 9. Its owner is no longer
  task 7 (`CN-Q`'s hand-off is answered, `LR-L`); whether it — like 53 and 55,
  "SwiftUI's answer … already" — leaves the live count is a counting decision
  left to **plan task 15**. The count stays fifty-five.

**What it costs if wrong.** A reader who still expects 45 to be pinned wrong
on purpose will find its test now asserting the opposite fact and conclude a
regression where there is a fix; the renamed test name is the tell.

## 2026-09-25: 18, 19, 48 and 69 retire; 71–74 added; 56 amended (plan task 8, composition and identity)

Record §55; rulings `ID-A`…`ID-Q` in
`docs/superpowers/2026-09-25-composition-identity-decisions.md`. **The table
moves from fifty-five to fifty-five live**: four retire, four are added.

- **18 retires** (a `@State` behind a removed `if` is retained rather than
  reset). SwiftUI resets an evaluated conditional's content (probe V5, V9);
  `ID-C` makes `OptionalGroup`/`EitherGroup` do the same when the absent slot
  **was produced the previous frame**, deleting every `StateTable` entry under
  it except a `.named("$focus")`/`.named("$ax")` component (focus and
  accessibility retention are untouched, by design — `TB-J`/`AB-U`). The old
  pin is gone; the new one is
  `anElementAfterAVanishingIfKeepsItsOwnState`/the animation row's
  `aReturningAnimatingElementSnapsInsideAnIfAndResumesInsideALoop` (record §55
  §6.3's retirement table). **Two retentions are kept, by design, and neither
  is 18's old shape**: an element a `for` loop stops producing keeps its state
  (new divergence **74**, below) and a conditional that is **not evaluated**
  (a `List` row out of its window) is untouched (`TB-AH`, unchanged).
- **19 retires** (a handler that writes one element value placed twice writes
  the *last-bound* occurrence, not its own). SwiftUI resolves each occurrence
  independently (probe S1, S4). `ID-F`: a `State.Box`/`Environment.Box` bound
  to more than one slot in a generation remembers every slot, and
  `StateDispatch.owner` (new; `Sources/MetalUI/StateDispatch.swift`) lets
  `wrappedValue`'s get/set resolve to the occurrence that is actually
  dispatching — every enumerated handler path (click, key, action, the two
  accessibility handlers, edit, submit) wraps its callback in
  `StateDispatch.dispatching(to:)`. The old pin,
  `aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt`, is renamed
  `aClosureRunOutsideInputDispatchWritesTheLastBoundOccurrence` (assertions
  unchanged) because its old name now describes the *fixed* behaviour, not
  the bug; the fixed behaviour is pinned by `O1.1`–`O1.8`
  (`OccurrenceIdentityTests.swift`). **Divergence 71 is added for what
  `ID-F` deliberately leaves alone**: a write from **outside** input dispatch
  (a phase, or a raw closure call with no `StateDispatch.dispatching`
  wrapper) still reaches the *last-bound* occurrence, where SwiftUI writes
  each occurrence's own storage there too (probe S5, with S6 as its
  two-different-values control; *corrected 2026-09-25 by the branch check,
  record §55 §9 — this bullet first said "SwiftUI has no analogue"*) — pinned
  by the renamed test itself (1 / 102) and by
  `aComponentsEnvironmentKeepsTheFirstOccurrencesSnapshot`/
  `aFrameBuiltInsideADispatchedHandlerReadsEachOccurrencesBinding` (lane 1's
  review round, `ID-O`).
- **48 retires** (a `Component`'s `.width`/`.height` overwrote each member's
  own declared width — the CSS engine's answer — where SwiftUI frames each
  member, probe component-distribution G7/G8; the proposal path has framed
  each member since stage 3, so this was already agreement, kept on the books
  past its own fix). `ID-K` retires it explicitly as this task's to count: the fact
  (`aComponentsWidthFramesEachMember`) has been SwiftUI's answer since plan
  task 7 stage 3 (`LR-BG`) and needed only this audit's bookkeeping to close.
- **69 retires** (a vanishing grid cell or row hands its state to the next
  one). `ID-B`'s one-structural-slot fix for `if`/`for` extends to
  `GridRow`'s untaken cell and `Grid`'s untaken row exactly as `EitherGroup`'s
  branch already worked (`SI-F`): the vanished cell/row no longer hands
  anything on, because there is no "next one" left holding its slot. Old
  pins `removingACellFromARowHandsItsStateToTheNextCell`/
  `removingAWholeGridRowHandsItsStateToTheNextRow` are renamed
  `removingACellFromARowLeavesTheNextCellsStateAlone`/
  `removingAWholeGridRowLeavesTheNextRowsStateAlone` (record §55 §6.3),
  asserting the opposite fact.
- **72 is added** (kept, `ID-H`): two siblings with the same `.id`/name still
  share one `GlobalElementID`, one `StateTable` entry, one hitbox id and one
  accessibility node, and it is still not a trap — where SwiftUI's explicit
  id keeps two same-named siblings distinct (probe X2). MetalUI's name
  **replaces** its structural position (the same mechanism a reordered named
  `for`-loop item relies on to keep its state, `ID-H`'s reasoning), so scoping
  the name by position would reset every named loop item on reorder. Pinned
  by `twoSiblingsWithTheSameIDShareOneStateEntry` and, for element groups,
  lane 3's E3.7.
- **73 is added** (kept, `ID-I` item 3): the content-taking `.overlay { }`
  and `.background { }` on a primary of zero or several nodes
  **traps**, naming the count, where SwiftUI attaches one instance **per
  member**, each with its own state (probe G3–G6). A modifier layer is one
  node and one identity level (`MC-A`); distributing per member is available
  as `.width`/`.height` (one frame per member, unchanged since stage 3) and
  inside the component's own body. Pinned by the legacy overlay's N1.7 and
  the new legacy background's B3.3.
- **74 is added** (kept, owner **plan task 10**, `ForEach`): an element a
  `for` loop stops producing keeps its state, and gets it back if the loop
  regrows to the same index, where SwiftUI's `ForEach` gives a shrunk-then-
  regrown element new state (probe V10 — a residual serial survives). This
  is `18`'s "not evaluated" cousin rather than 18 itself: an `ArrayGroup`'s
  member count shrinking does not evaluate-away any one member's slot the
  way an `if` going false does, so `ID-C`'s reset rule does not reach it, and
  data identity (a `ForEach`-style keyed loop) is where a scoped answer
  belongs — plan task 10's, not this task's, to fix.
- **56 is amended, kept, owner none** (`ID-I` items 1–2): a `.frame` on a
  multi-member `Component` is one layer over a row of per-member frames. In a
  horizontal parent that equals SwiftUI (probe L3, 140×10); in a vertical one
  SwiftUI stacks the framed members (L1/L2, 70×20) where MetalUI rows them;
  over **zero** members MetalUI's frame still occupies its parent (70×0)
  where SwiftUI's adds nothing (L5, `EmptyView` control L6). **The row's
  cross-axis alignment** is the frame's own in MetalUI, the **parent's** in
  SwiftUI: probe L8 — `.frame(width: 70, alignment: .top)` in a
  centre-aligned `HStack` leaves the short member at minY **10**, the
  parent's centre, as with no frame (L9), while L10 (`HStack(alignment:
  .top)`, minY 0) shows the instrument can see a top-aligned member;
  MetalUI's row puts it at 0. New test `N3.1`
  (`aMultiMemberFrameRowAlignsItsMembersByTheFramesOwnAlignment`,
  `LoweringComponentTests.swift`) pins MetalUI's kept answer (`TB-M`,
  re-owned to this task by record §54 §10.3 and closed here with no fix).
  *Corrected 2026-09-25 by the branch check (record §55 §9): this bullet
  first described only the alignment sub-row, and misread L8 as a
  top-aligned parent.*

**What it costs if wrong.** A reader following 18, 19, 48 or 69 by an older
section's name finds no such test, or a test that now asserts the opposite of
what the row used to describe; the renamed/new names above are the fix. A
reader who does not know 71 exists might read `O1.1`–`O1.8`'s green run as
"19 unfixed" — it fixes only the dispatched half; 71 is the two-values
control (S5/S6) that shows the residual case is real, not a leftover bug.

**Corrections by the branch check (2026-09-25, record §55 §9).** Four bullets
above were re-worded against the probe header and the tests: 48 had said the
width "overwrites" each member "where a custom view's SwiftUI modifier does
the same" (SwiftUI frames each member; overwriting was the CSS engine's
answer); 71 had said SwiftUI "has no analogue" (probe S5: SwiftUI writes each
occurrence's own storage outside dispatch too); 73 had named "both the token
and content-taking forms" (no token `.overlay` exists, and the token
`.background(_:)` is not offered on a multi-member `Component`); 56 had
described only the alignment sub-row. **One state-retention difference is
not in this table yet**: a group or element whose `.id` changes and then
**returns** to an earlier name gets its old state back within `TB-AH`'s
bound, where SwiftUI gives it new state (probe X9–X11, revision 3; MetalUI
measured by a throwaway test at `da2d820`, record §55 §9.3). It owes a ruling
(fix or keep) and, if kept, a number (next unused label **75**) and a pin.

## 2026-09-25 (closeout): no row added — the returning-name row is fixed (plan task 8, `ID-R`)

Record §55 §10; ruling `ID-R`. **The table stays at fifty-five live; label 75
stays unused.** The state-retention difference the section above left open —
a name that changes and then **returns** got its old state back within
`TB-AH`'s bound, where SwiftUI gives it new state (probe X9–X11, revision 3,
re-run byte-identical at `89a8337`) — is **fixed to SwiftUI's answer**, so it
never became a numbered row: a name an evaluated position leaves is reset
unless the frame produced it elsewhere (`StateTable.noteNamed`, `sweep()`),
`$focus`/`$ax` kept as `ID-C` keeps them. Pinned by
`anIDThatReturnsToAnEarlierNameStartsFresh`,
`aNameThatMovesToASiblingsPositionKeepsItsState` and
`everyNamingSiteStartsAReturningNameFresh` (`ExplicitIdentityTests.swift`).
**74 is unchanged**: a loop shrinking at its tail evaluates no position, so its
dropped element — named or not — departs nothing and keeps its state (plan task
10). **`TB-AH` is unchanged**: a `List`'s rows are exempt, because a row out of
its window is not evaluated (mutation MRc, the exemption dropped, reddens the
two `List` excursion tests).

**What it costs if wrong.** A reader looking for divergence 75 finds nothing —
by design; the row this section's predecessor named is closed here, not
numbered.
