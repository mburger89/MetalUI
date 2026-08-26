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

## The compositions probed against WebKit but not committed

Task 1's brief required it to answer taxonomy shape 9's question: of every
(wrapping × already-shipped feature) pair, which are fixtured, which are untested,
and which are *untested-and-correct-by-construction*?

**This table is the answer, and it is here rather than in the task report because
that report lives under `.superpowers/`, which is git-ignored.** Every measurement
below was taken against the live WebKit oracle during Task 1 with throwaway
fixtures that were deliberately not committed; a reviewer independently re-probed
seven of them and got 7/7 exact. Task 3 commits them as real fixtures. Until it
does, they are *measured-correct today* — which is exactly the state the box
model's first two bugs were in the day before someone probed them.

| Pair | Probe | Result |
|---|---|---|
| wrapping × **flex-grow** | `flex: 1 1 140px` ×3 in a 300-wide wrap row | a 0,0 150×20 · b 150,0 150×30 · c **0,30 300×40** — a line grows into the *container's* main extent, alone |
| wrapping × **justify-content** | `space-between`, lines with 120 and 90 free | a 0,0 · b **220**,0 · c 0,30 · d **240**,30 — each line justifies independently |
| wrapping × **align-items / align-self** | `align-items: center` + one `align-self: flex-end`, lines 60 and 90 tall in a 240-tall container | a 0,**20** — centred in *line* 0, not the container · c 0,60 · d 120,**90** |
| wrapping × **row-reverse** (× gap × margin) | `row-reverse; wrap; gap: 7px 11px`, `.a{margin-left:9px}` | a **160**,0 · b **20**,0 · c **170,42** — lines assigned in DOM order, placed right-to-left |
| wrapping × **column direction** | `column; wrap; gap: 6px 13px`, 130 tall | a 0,0 · b 0,56 · c **83**,0 · d **126**,0 — lines stack horizontally, the cross gap is `column-gap`, and 45+6+80 = 131 > 130 breaks by one pixel |
| wrapping × **main-axis min/max** | `min-width: 180` on a 100px item, `max-width: 100` on a 250px item | the break uses the **clamped** hypothetical size: a 180 alone on line 0 |
| wrapping × **nesting + percentage padding** | wrapped container inside a wrapped container, `padding: 5%` on the inner | mid 8,6 200×70 · g1 27,25 · g3 **27,43** — the inner's percentage padding still resolves against its containing block, and its own lines stack inside its content box |

**Two of these are worse than untested — they are unpinned by anything.** The Task 1
reviewer built two mutations of its own and both left all 184 tests green:

- growing into the **line's used extent** instead of the container's main extent, multi-line only;
- taking `justify-content`'s free space from the **line** rather than the container.

Both are shape 9's tell exactly: a mutation that reddens nothing, in code that is
demonstrably right, means the composition it lives in has no fixture. They are
Task 3's first two fixtures.

Pairs left **untested**, with the honest label for each:

| Pair | Label |
|---|---|
| wrapping × **flex-shrink** | Untested, and **near-vacuous by construction — argument verified**. The break decision uses *outer hypothetical* sizes, so a wrapped line can only overflow when a **single item alone** exceeds the container. The reviewer confirmed this from the code: `usingGrow` keys on `hypotheticalTotal`, and `collectLines` guarantees `hypotheticalTotal + gaps ≤ containerMain − totalMargin` on any multi-item line. Cheap to fixture anyway |
| wrapping × **column-reverse** | Untested. Row-reverse and column are each probed separately and the reverse conversion is axis-blind — but "two features that work alone" is the argument the box model disproved twice. The Task 1 reviewer probed it: correct |
| wrapping × **percentage main sizes** | Untested. Percentages resolve against the container's content-box main extent, which line collection does not change — but the break decision consumes the resolved number. The Task 1 reviewer probed it: correct |
| wrapping × **`display: none`** | Correct by construction and cheap to see: `collectItems` filters before `collectLines` runs, so a hidden child cannot occupy a line or create one |
| wrapping × **content-based cross sizing** | Unreachable until M2, and **newly more dangerous**: a line whose items are all auto-cross measures 0 tall, so the whole line collapses and every line below shifts up — where previously one item within a line was wrong. Recorded in CLAUDE.md |
| wrapping × **`margin: auto`** | Inert (resolves to 0), unchanged by this task, already a CLAUDE.md row |

## Two divergences Task 1 knowingly shipped, both scoped and pinned

**Divergence 1 is CLOSED — Task 2 implemented `align-content`.** The paragraph
below is kept as the record of what Task 1 shipped and what closing it cost, not
as a description of the engine today: `layoutContainer` now defaults
`alignContent` to `.stretch`, `distributeLines`/`lineStretchAmount` live in
`Alignment.swift`, `wrappedLinesPackFromCrossStartRatherThanStretching` is
deleted, and WebKit's 125/125 below is what
`aStretchedLineChangesWhatItsStretchedItemsFill` now asserts on that exact tree.
The three fixtures' `align-content: flex-start` declarations were kept and their
comments rewritten: they are pins of `flex-start` now, not workarounds.
Divergence 2 (`wrap-reverse`) is still open and still Task 3's.

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

**What Task 3 must actually reverse — measured, not assumed.** The Task 2
reviewer drove live WebKit on `align-content` × `wrap-reverse` and found the
engine differs on every value, entirely because reversal is unimplemented. The
important finding is *how* WebKit reverses: it flips the **whole cross axis**, not
just the order lines are stacked in. So `flex-start` packs lines to the container's
**bottom**, `flex-end` packs them to the top, and `stretch` grows lines and fills
from the bottom. Each item then sits at its line's *flipped* cross-start — its
line's bottom edge.

Two consequences for Task 3:

- Reversing the **line order** alone is not enough. The `align-content` leading
  offset and the per-item `crossAxisOffset` both need flipping.
- On the pinned 260×300 tree (`120×40 / 120×30 / 120×90`), `a` and `b` land at
  **260 and 270** — they differ from each other despite sharing a line, because
  each is pinned to its own bottom edge inside a 40-tall line. **No
  forward-wrapping fixture can exhibit that**, which is why this pair needs its
  own fixture rather than inheriting confidence from the `wrap` ones.

The exact numbers are inlined in CLAUDE.md's `FlexWrap.wrapReverse` row and in
`wrapReverseCollectsLinesButDoesNotReverseThemYet`'s comment — both re-derived
rather than copied, after an earlier hand-computed version of that comment shipped
wrong under both `align-content` values.

2. **`wrap-reverse` is a half-rule — live code with a wrong answer.**
   `collectLines` tests only `wrap != .noWrap`, so `.wrapReverse` collects lines
   identically to `.wrap` and nothing stacks them from the cross-end. An API that
   *half* works is more dangerous than one that does nothing, which is why it has
   both a test naming CSS's answer and a CLAUDE.md row. Task 3 owns it.

## Carried risk

- **Wrapping's own compositions are the branch's main risk**, not its algorithm. Seven are measured-correct and uncommitted; two are provably unpinned. Task 3 exists to close that list.
- **BM-4's over-constrained box** is a deliberate, documented divergence.
- **The root's percentage width** falls back to the available space where WebKit uses the containing block. Do not fix one site without the other.
- **FS-9 and AL-4 together state one rule** — two independent engines agreeing outrank the spec's letter; one engine alone does not.
- **`LayoutNodeID` has no generation counter** (m1a ruling C-3).
- **Two guarantees lapse under plausible CI configurations** — the ABI probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only live-WebKit consumer. Both must be required, non-gateable jobs.
