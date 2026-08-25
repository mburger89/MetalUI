# Flex sizing — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-25-metalui-flex-sizing.md`, in order. Each says
what was decided, why, and what it costs if wrong.

**12 rulings. Nineteen findings. Every one was in a plan, a test, a fixture or a
comment — not one was a defect in engine behaviour.** That is now the third
consecutive milestone with that result, and as before, essentially all of them
were found by *mutation* rather than by reading.

**Ruling IDs here are prefixed `FS-`** (flex sizing). Plain `F-n` in the m0 and
m1a decisions docs are different rulings entirely; three code comments on this
branch originally cited bare `F-1`/`F-2`/`F-3` and resolved to the wrong
document. Prefix every future milestone's rulings the same way.

## Pre-flight (from scanning the plan before any code)

| # | Ruling | Cost if wrong |
|---|---|---|
| FS-1 | **The root keeps the available-space fallback; flex items do not.** Deleting it wholesale, as the plan said, would leave `computeLayout`'s *public* `available:` parameter read by nothing — and no test could see it, since every root in the suite has an explicit size. Split along the CSS grain instead: a root is a block box in the initial containing block, so `width: auto` fills it; a flex item is content-sized (§9.2) and does not. | A root sized by `available` where the caller wanted 0. Visible immediately in the demo; one branch to delete. |
| FS-2 | **Implement §9.7.4.b's sub-one flex factor clause, which the plan omits, and add a browser fixture for it.** Without it a lone `flex: 0.5` silently takes *all* free space instead of half. Chosen over documenting it as a gap because this clause is browser-checkable: leaving it out means the oracle agrees with us today and disagrees the moment anyone writes a fractional factor. | ~10 lines and one fixture of extra scope. |
| FS-3 | **Document, do not implement, CSS §4.5's specified-size suggestion.** The automatic minimum is properly `min(specified, content)`; only the content half is built. The two cannot be distinguished until something measures content in production, which is M2. | An item with an explicit size smaller than its content floors too high. Unreachable until measure functions exist in production. |
| FS-4 | **Replace Task 1's mutation 2.** The plan mutated to an undefined identifier and grepped for a *compile* error — that tests the Swift compiler, not this suite. Mutate `resolved ?? 0` to `resolved ?? 300` instead. That the old fallback cannot be restored without re-plumbing a parameter is the structural point of the split; a compile error does not demonstrate it. | None. |
| FS-5 | **Drop `resolveFlexibleLengths`' `container` parameter.** Declared by the plan, read by nothing. | None. |
| FS-6 | **`swift package clean`, never `rm -rf .build`.** The plan's Task 3 says otherwise; its own Global Constraints say this. Constraints win. | None. |

## During execution

| # | Ruling | Cost if wrong |
|---|---|---|
| FS-7 | **Record `FlexItem`'s unread fields at the declaration, not in CLAUDE.md's inert table.** The reviewer was right that `baseSize`/`hypotheticalMainSize`/`frozen` were written-but-unread (taxonomy shape 4), but that table describes API state that outlives a branch, and these fields went live two commits later. A table that churns stops being read; the hazard belongs where the next author is looking. | A reader of CLAUDE.md alone believes the freeze loop exists. Bounded — the fields went live before merge. |
| FS-8 | **Amends my own earlier instruction to leave CLAUDE.md alone.** The inert row said `flexGrow`, `flexShrink`, `flexBasis` had "0 uses" while `FlexBaseSize.swift` read `flexBasis` — so the row was **false**, not merely stale, and CLAUDE.md's own rule is "when you implement one, delete its row". Stale can wait for the end of a plan; false cannot. | A row edited twice instead of once. |
| FS-9 | **Keep the spec on §9.7.4.b's magnitude test. WebKit is the outlier.** See "The WebKit divergence" below. | On Apple platforms our flex layout differs from Safari's in one edge case. Bounded, documented, and ours is the non-overflowing direction. |
| FS-10 | **Add a bounded iteration cap to the freeze loop.** Deleting the zero-violation branch, or swapping the freeze signs, made the loop *hang* rather than fail. Termination is provable — every pass freezes at least one item, so passes ≤ `count + 1` — which is exactly why a cap costs nothing when correct and converts a wedged CI job into a named diagnosis. A hang is the worst failure mode for a guarantee that is otherwise sound. | None. Unreachable unless the freezing logic is broken. |
| FS-11 | **Rewrite the divergence record rather than merely keeping it.** It framed the spec choice as provisional, and one test instructed a future reviewer to "delete the guard and invert this test" if the oracle won — an instruction that, after Blink settled the question, pointed straight at a regression. | A future maintainer "fixes" us toward a WebKit bug. |
| FS-12 | **Three of Task 4's stated expectations are arithmetically wrong, and its browser fixture does not exercise what it claims.** See "The plan's arithmetic" below. | The implementer derives different numbers and the browser breaks the tie — the process working, not a failure. |

## The WebKit divergence (FS-9, FS-11)

The corpus's standing rule is "where we disagree with the browser, the browser is
right." This branch breaks that rule once, deliberately.

With `.a { flex: .25 1 0; min-width: 350px }` and `.b { flex: .25 1 0 }` in a
400px row — the case where §9.7.4.b's magnitude test must **reject** the scaled
value rather than select it:

| | `a` | `b` | total |
|---|---|---|---|
| CSS spec | 350 | 50 | 400 |
| Blink (headless Chrome) | 350 | 50 | 400 |
| MetalUI | 350 | 50 | 400 |
| **WebKit** | 350 | **100** | **450**, overflowing |

Two independent pieces of evidence say WebKit is wrong rather than reading the
spec differently:

1. **Blink agrees with the spec.** It shares no layout code with WebKit.
2. **WebKit is inconsistent with itself.** `flex_row_fractional_shrink` shows it
   *honouring* the same magnitude guard when free space is negative, while
   ignoring it when positive. That is a bug, not an alternative interpretation.

Nothing committed encodes WebKit's answer, so a future WebKit fix moves no
golden. The reproducer is in `CLAUDE.md`; the Blink half is not reproducible from
anything committed, which is a small gap worth closing if this ever matters
again.

**The standing rule now has a stated limit:** the browser is right *because* it is
the reference implementation. Where two engines disagree, the spec breaks the tie.

## The plan's arithmetic (FS-12)

Three of Task 4's expected values were wrong, and were only discoverable once the
freeze loop existed — the plan was written when nothing could evaluate them.

- `automaticMinimumSizeUsesContentSizeNotFlexBasis` asserted `a == 80` in a 200px
  row with bases 300/100. Overflow is 200 and the weighted factors are 300/100,
  so `a` shrinks to **150** and its 80 floor never binds: the test would have
  failed against a *correct* implementation. A ~100px row makes it bind.
- `anExplicitMinSizeOverridesTheAutomaticOne` asserted `120 / 180` from **equal**
  250px bases. Equal bases shrink equally — both land on 150 — and 120/180 is not
  reachable by proportional distribution at all.
- `flex_row_explicit_min.html` had the same flaw: `a` is 150, so its `min-width`
  declaration was **inert**. Proved differentially in WebKit — the fixture
  measures 150/150 both with and without the declaration. Its replacement
  measures 100/200 without and 150/150 with.

## Rulings by implementers that were accepted

Recorded because they corrected *me*, and the reasoning generalises.

- **A column test cannot pin a cross-axis mutation.** I predicted one
  column-direction test would close three mutations at once. Forcing
  `available`'s `height:` branch to `.maxContent` is invisible in a column —
  that branch already *is* `.maxContent` there — so it is observable only from a
  row. I had assumed the axis with the interesting main-axis behaviour is also
  where a cross-axis mutation shows; it is the opposite by construction.
- **The grow/shrink choice is Flexbox L1 step 1, not §9.7.2** (step 2 is "size
  inflexible items"), and the spec text reads "if the sum is *less than* one",
  matching the implemented `<`. My citations were wrong in both places and would
  have propagated into the code.
- **`assertionFailure` over `precondition` for FS-10's cap.** A shipped app
  degrading to a partial layout beats trapping in a user's face, and debug builds
  still catch it. The release behaviour is documented at the cap site.
- **Inert-table rows are collateral of any task that lights up an API**, not only
  of the task that names them. An implementer deleted a second false row
  (`MeasureFunction` / `tree.measure()`) that the same change had falsified, which
  I had not spotted.
- **The deepest defect in the plan, found by an implementer unprompted.** Task 4's
  Step 4, implemented literally, computes the automatic minimum in `collectItems`
  and then **discards it**: §9.7.4.d re-resolves min/max *from style* inside the
  loop, where `min-width: auto` resolves to nil, so the floor vanishes exactly
  when it should bind. Fixed structurally — `minMain`/`maxMain` now live on
  `FlexItem`, resolved once — which also removed the axis parameter that an
  earlier mutation had been about.

## What the corpus kept failing to see

Four of the nineteen findings were the same shape: **a fixture too uniform to
distinguish the thing it claimed to pin.**

| Fixture blindness | What it hid |
|---|---|
| Equal base sizes in the shrink tests | Whether shrink is weighted by base size at all — weighted `200:400` and unweighted `1:2` are the same ratio |
| Every growing item in the corpus had `flex-basis: 0` | Whether grow *adds to* the base or replaces it — `flex: 1 1 100px`, the most ordinary flex declaration there is, was entirely unguarded |
| A `min-width` that never binds | Whether explicit minimums are honoured; the fixture produced identical output with the declaration deleted |
| No percentage flex-basis anywhere | Whether `flexBaseSize` is *wired* to the main axis — the axis choice was pinned inside the function, never at its call site |

The lesson is not "write more fixtures". It is that a corpus grown from
convenient cases converges on uniform values, and uniform values cannot
distinguish a formula from its degenerate case. **Before committing a fixture,
delete the declaration it is named for, regenerate, and confirm the numbers
move.**

## Carried risk

- **`layoutContainer`, `collectItems` and `positionItems` each re-derive
  `isRow` and `gap`** from the container's style independently. Only
  `gapUsesTheMainAxisOfTheContainer` notices if two of them ever disagree.
- **`LayoutNodeID` still has no generation counter** (m1a ruling C-3). A stale ID
  after `reset()` traps safely if the new tree is smaller but **silently
  addresses a different node** if larger. Nothing calls `reset()` mid-flight yet.
- **The automatic minimum size rule has exactly one killing test**, and no fixture
  can reach it until M2 populates measure functions. Stated at the test, at
  `collectItems`, and in CLAUDE.md's table.
- **Two guarantees still lapse under plausible CI configurations** — the ABI probe
  skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only
  live-WebKit consumer. Both must be required, non-gateable jobs.
