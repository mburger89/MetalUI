# Wrapping — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-25-metalui-wrapping.md`, in order. Each says what
was decided, why, and what it costs if wrong.

**Ruling IDs here are prefixed `WR-`.** `PF-`/`C-` belong to m1a, `FS-` to flex
sizing, `AL-` to alignment, `BM-` to the box model. A bare `F-n` is ambiguous
across three documents — sweep for stray citations **case-insensitively**, since a
`Ruling F-3` survived two branches' greps for lowercase `ruling`.

## Pre-flight

| # | Ruling | Cost if wrong |
|---|---|---|
| WR-1 | **`row-gap` was inert on a row, and wrapping is what makes it live.** Both `gap` call sites read `isRow ? gap.horizontal : gap.vertical` — always the **main** axis — so a row silently dropped its `row-gap` and a column its `column-gap`. It never earned a "declared but inert" row because neither component is dead: each is read in one direction. `gapUsesTheMainAxisOfTheContainer` reads as full coverage while saying nothing about the dropped half. Wrapping gives the cross gap its meaning — the space between lines — so Task 1 implements it rather than documenting it. | Multi-line layouts stack lines with the wrong gap, or none. |
| WR-2 | **`collectLines` returns `[[FlexItem]]`; the engine assembles `FlexLine`.** The plan declared both without saying how they relate. The break decision stays a **pure function over items** — no cross sizes, no styles — so it is testable alone and reusable by Grid, the same reason `lineContentSize` takes `[Double]` rather than `[FlexItem]`. | A pure function acquires engine state and stops being either. |

## During execution

| # | Ruling | Cost if wrong |
|---|---|---|
| WR-3 | **`wrap-reverse` converts at the point of use in *both* places, not by reversing the lines array.** The main axis already sets this precedent, and the reason carries: the array's order is document order and the break decision depends on it. The second half is the part that is easy to miss — WebKit flips the **whole cross axis**, so the `align-content` leading offset *and* each item's `crossAxisOffset` need flipping. Task 3 measured both halves separately: dropping the per-item flip reddens 7 tests, dropping the line-start flip reddens 6. | Lines stack from the right end while items sit at the wrong edge inside them — a layout that looks half-reversed. |
| WR-4 | **CLAUDE.md's auto-cross-size row is false in both halves; correct it, do not implement it here.** The row scopes the gap to a **non-stretched** item and asserts "no fixture can catch this … needs the M2 text system". Two probe agents independently disproved both: the item can be `stretch`-aligned (the size is lost in §9.4.8 line measurement, which runs *before* stretch), and a **nested flex container** has a content cross size with no text in it, so a fixture catches it today. Content-based cross sizing is out of scope for this branch and the fix is recursive subtree measurement, not a clamp — so the row gets corrected and the behaviour gets pinned with WebKit's numbers named, the BM-4 treatment. | A reader trusts a mitigation whose stated scope is wrong, and skips a fixture that would work. |
| WR-5 | **`Resolve.swift`'s precision claim is falsified; correct the comment, leave the behaviour.** It says the `Float` percentage product carries "~1e-4pt of error … roughly 130x below WebKit's 1/64 quantum, **so it never reaches a fixture**." It reaches one: 60% of a 350 content box is `210.00001525878906`, dragging an exact 285.5 to `285.49999618` — the wrong side of `roundLayout`'s .5 boundary. WebKit gives 286/328, the engine 285/327. The arithmetic is right and the conclusion is wrong: **cumulative rounding amplifies the error at a .5 boundary**, which "130x below the quantum" does not account for. Predates this branch, reproduces under `nowrap`, and reproduces via `Float` `flexGrow`/`flexShrink` with no percentages at all — so it belongs to whoever owns units precision. | The next person to see a 1px disagreement trusts the comment and looks in the layout algorithm, where the bug is not. |

**WR-4 and WR-5 are the same shape, and it is a shape this project has not named
before.** Neither is a defect in what the engine *does*. Both are defects in what
the repo *believes about itself* — a mitigation or a limitation whose documented
**scope** is wrong, so a reader correctly follows it to a wrong conclusion. Every
previous milestone's findings were either code that misbehaved or tests that could
not fail; these are comments that were true when written, stayed true in their
arithmetic, and became false in their *reach* as the engine grew around them.

Both were found the same way: by measuring the thing the comment said not to
bother measuring.

## The compositions probed against WebKit but not committed

Task 1's brief required it to answer taxonomy shape 9's question: of every
(wrapping × already-shipped feature) pair, which are fixtured, which are untested,
and which are *untested-and-correct-by-construction*?

**This table is the answer, and it is here rather than in the task report because
that report lives under `.superpowers/`, which is git-ignored.** Every measurement
below was taken against the live WebKit oracle during Task 1 with throwaway
fixtures that were deliberately not committed; a reviewer independently re-probed
seven of them and got 7/7 exact.

**CLOSED — Task 3 committed all seven, plus four more.** The `Fixture` column
below names the file that now holds each one; every golden is
browser-generated, and every one matched the numbers hand-derived in its
fixture's comment on first generation. Nothing in this table is in the
*measured-correct-but-uncommitted* state any more, which is the state the box
model's first two bugs were in the day before someone probed them.

| Pair | Probe | Result | Fixture (Task 3) |
|---|---|---|---|
| wrapping × **flex-grow** | `flex: 1 1 140px` ×3 in a 300-wide wrap row | a 0,0 150×20 · b 150,0 150×30 · c **0,30 300×40** — a line grows into the *container's* main extent, alone | `flex_wrap_grow_and_shrink` |
| wrapping × **justify-content** | `space-between`, lines with 120 and 90 free | a 0,0 · b **220**,0 · c 0,30 · d **240**,30 — each line justifies independently | `flex_wrap_justify_between` |
| wrapping × **align-items / align-self** | `align-items: center` + one `align-self: flex-end`, lines 60 and 90 tall in a 240-tall container | a 0,**20** — centred in *line* 0, not the container · c 0,60 · d 120,**90** | `flex_wrap_align_items_self` |
| wrapping × **row-reverse** (× gap × margin) | `row-reverse; wrap; gap: 7px 11px`, `.a{margin-left:9px}` | a **160**,0 · b **20**,0 · c **170,42** — lines assigned in DOM order, placed right-to-left | `flex_wrap_row_reverse_gap_margin` |
| wrapping × **column direction** | `column; wrap; gap: 6px 13px`, 130 tall | a 0,0 · b 0,56 · c **83**,0 · d **126**,0 — lines stack horizontally, the cross gap is `column-gap`, and 45+6+80 = 131 > 130 breaks by one pixel | `flex_wrap_align_content_center` (Task 2) and `flex_wrap_column_reverse` |
| wrapping × **main-axis min/max** | `min-width: 180` on a 100px item, `max-width: 100` on a 250px item | the break uses the **clamped** hypothetical size: a 180 alone on line 0 | `flex_wrap_main_sizing` |
| wrapping × **nesting + percentage padding** | wrapped container inside a wrapped container, `padding: 5%` on the inner | mid 8,6 200×70 · g1 27,25 · g3 **27,43** — the inner's percentage padding still resolves against its containing block, and its own lines stack inside its content box | `flex_wrap_nested_percent_padding` |

**Two of these are worse than untested — they are unpinned by anything.** The Task 1
reviewer built two mutations of its own and both left all 184 tests green:

- growing into the **line's used extent** instead of the container's main extent, multi-line only;
- taking `justify-content`'s free space from the **line** rather than the container.

Both are shape 9's tell exactly: a mutation that reddens nothing, in code that is
demonstrably right, means the composition it lives in has no fixture. They were
Task 3's first two fixtures, and **both mutations now redden exactly one test
each** — the fixture written for them, and nothing else:

| Mutation (scoped to multi-line, as the reviewer's were) | Reddens |
|---|---|
| §9.7 flexes into `lineContentSize(hypothetical sizes)` instead of `containerMain` | `wrapGrowAndShrinkMatchesWebKit` |
| `justify-content`'s free space forced to 0 on a wrapped line | `wrapJustifyContentIsPerLineMatchesWebKit` |

Pairs left **untested**, with the honest label for each:

| Pair | Label |
|---|---|
| wrapping × **flex-shrink** | **Fixtured** (`flex_wrap_grow_and_shrink`'s `.d`). The near-vacuity argument stands and is now measured rather than argued: the break decision uses *outer hypothetical* sizes, so `collectLines` guarantees `hypotheticalTotal + gaps ≤ containerMain − totalMargin` on any multi-item line, and the only reachable shrink under wrapping is a single item that exceeds the container alone. `.d` is that item — 380 hypothetical in a 300 container, shrunk to 300 |
| wrapping × **column-reverse** | **Fixtured** (`flex_wrap_column_reverse`). It got its own file rather than inheriting the row-reverse one for the reason `flex_row_reverse_margins` and `flex_column_reverse_margins` are two files |
| wrapping × **percentage main sizes** | **Fixtured** (`flex_wrap_main_sizing`), together with the min/max clamps, because they are the same claim about the same number. The root carries 20px of horizontal padding so the percentage basis (content box, not border box) is load-bearing |
| wrapping × **`display: none`** | **Still untested, deliberately.** Correct by construction and cheap to see: `collectItems` filters before `collectLines` runs, so a hidden child cannot occupy a line or create one. A fixture would pin `collectItems`' filter, which `nowrap` fixtures already reach, and would say nothing about wrapping |
| wrapping × **content-based cross sizing** | Unreachable until M2, and **newly more dangerous**: a line whose items are all auto-cross measures 0 tall, so the whole line collapses and every line below shifts up — where previously one item within a line was wrong. Recorded in CLAUDE.md |
| wrapping × **`margin: auto`** | Inert (resolves to 0), unchanged by Task 3, already a CLAUDE.md row. Out of scope by the plan |

## Two divergences Task 1 knowingly shipped, both scoped and pinned

**Divergence 1 is CLOSED — Task 2 implemented `align-content`.** The paragraph
below is kept as the record of what Task 1 shipped and what closing it cost, not
as a description of the engine today: `layOutChildren` (which is what
`layoutContainer`'s sizing half became in the content-sizing milestone) now
defaults `alignContent` to `.stretch`, `distributeLines`/`lineStretchAmount` live in
`Alignment.swift`, `wrappedLinesPackFromCrossStartRatherThanStretching` is
deleted, and WebKit's 125/125 below is what
`aStretchedLineChangesWhatItsStretchedItemsFill` now asserts on that exact tree.
The three fixtures' `align-content: flex-start` declarations were kept and their
comments rewritten: they are pins of `flex-start` now, not workarounds.
**Divergence 2 (`wrap-reverse`) is CLOSED too — Task 3 implemented the flip.**
See the paragraph below it.

1. **`align-content` is unimplemented, and that is now a real divergence rather
   than a vacuous one.** *(Closed — see above.)* There are multiple lines; the engine stacks them from
   cross-start with leftover cross space unused, which is `align-content:
   flex-start`, while CSS's initial value is **`stretch`**. Measured in WebKit on a
   260×300 `wrap` row holding 120×40 / 120×auto / 120×90: WebKit gives the auto
   child **125** tall and puts line 1 at **y = 125**; this engine gives 40 and 40.
   Pinned by `wrappedLinesPackFromCrossStartRatherThanStretching`, and **no golden
   encodes it** — every wrapped fixture declares `align-content: flex-start`
   explicitly, and that declaration is load-bearing: stripping it moves every box
   in all three fixtures. Task 2 implements the property and deletes both the test
   and the CLAUDE.md row.

**What Task 3 actually reversed — measured, not assumed.** The Task 2
reviewer drove live WebKit on `align-content` × `wrap-reverse` and found the
engine differed on every value, entirely because reversal was unimplemented. The
important finding is *how* WebKit reverses: it flips the **whole cross axis**, not
just the order lines are stacked in. So `flex-start` packs lines to the container's
**bottom**, `flex-end` packs them to the top, and `stretch` grows lines and fills
from the bottom. Each item then sits at its line's *flipped* cross-start — its
line's bottom edge.

Both consequences were implemented, in `positionItems`, as **two conversions at
the point of use** rather than a reordering — the exact cross-axis mirrors of
the main axis's `containerMain - cursor - outerMain(item)`, one per nesting
level:

- `linePhysicalCrossStart = containerCross - lineCrossStart - lineCross`, which
  flips the whole stack including whatever leading offset `align-content` gave
  it;
- `outerPhysicalCrossStart = lineCross - crossAxisOffset(...) - outerCross`,
  which flips each item inside its own line.

`collectLines` is untouched and still breaks in **document order**, which is
CSS's rule and not a shortcut: §8.3 reverses the cross axis, not the assignment
of items to lines. `wrapReverseBreaksLinesInDocumentOrder` asserts that half
directly, because positions cannot distinguish "broke differently" from "placed
differently".

Two facts that the fixtures had to be designed around, and that a reviewer
should not have to rediscover:

- On the pinned 260×300 tree (`120×40 / 120×30 / 120×90`), `a` and `b` land at
  **260 and 270** — they differ from each other despite sharing a line, because
  each is pinned to its own bottom edge inside a 40-tall line. **No
  forward-wrapping fixture can exhibit that**, which is why this pair needed its
  own fixture rather than inheriting confidence from the `wrap` ones.
- **Only `flex-start` and `flex-end` can distinguish flipping the cursor from
  reversing the lines array.** Every symmetric distribution — `center`, both
  `space-*` pairs, and `space-between` — puts equal space at both ends, so the
  stack reads identically upside down. That is why
  `flex_wrap_reverse_align_content_end` declares `flex-end` and not
  `space-between`; with `space-between` the array-reversal mutation reddens
  nothing. (`positionItems`' main-axis comment records the same discriminator
  for `row-reverse`: it is `leading == trailing`, not `leading == 0`.)

Three fixtures pin it — `flex_wrap_reverse` (the two flips separated, with
`align-items`/`align-self`), `flex_wrap_reverse_align_content_end`, and
`flex_wrap_reverse_row_reverse` (both axes at once, over `stretch`-grown lines,
with physical margins on each axis). CLAUDE.md's `FlexWrap.wrapReverse` row is
deleted and `wrapReverseCollectsLinesButDoesNotReverseThemYet` is replaced by
five tests that assert the real behaviour.

2. **`wrap-reverse` is a half-rule — live code with a wrong answer.**
   *(Closed — see the paragraph above.)* `collectLines` tested only
   `wrap != .noWrap`, so `.wrapReverse` collected lines identically to `.wrap`
   and nothing stacked them from the cross-end. An API that *half* works is more
   dangerous than one that does nothing, which is why it had both a test naming
   CSS's answer and a CLAUDE.md row — and why both are gone rather than
   softened.

## Carried risk

- **Wrapping's own compositions were the branch's main risk**, not its algorithm. *(Closed by Task 3 — eleven fixtures; the two provably-unpinned mutations each now redden exactly one test.)* Two pairs remain deliberately unfixtured and are recorded as such above: `display: none` (the filter runs before line collection, so a fixture would pin `collectItems` and say nothing about wrapping) and `margin: auto` (inert, and out of the plan's scope).
- **What Task 3 got wrong was documentation, not code.** All eleven goldens matched the engine on first generation, but four of the sixteen sibling-swap differentials the fixture comments claimed were wrong — every one of them hand-derived rather than run. Predicting which numbers move does not satisfy "change the declaration and confirm the numbers move".
- **BM-4's over-constrained box** is a deliberate, documented divergence.
- **The root's percentage width** falls back to the available space where WebKit uses the containing block. Do not fix one site without the other.
- **FS-9 and AL-4 together state one rule** — two independent engines agreeing outrank the spec's letter; one engine alone does not.
- **`LayoutNodeID` has no generation counter** (m1a ruling C-3).
- **Two guarantees lapse under plausible CI configurations** — the ABI probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only live-WebKit consumer. Both must be required, non-gateable jobs.
