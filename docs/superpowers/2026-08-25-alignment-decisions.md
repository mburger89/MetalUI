# Alignment — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-25-metalui-alignment.md`, in order. Each says
what was decided, why, and what it costs if wrong.

**7 rulings.** Every defect found during execution was in a plan, a test, a
fixture or a comment — **not one was in engine behaviour**. That is now the
fourth consecutive milestone with that result, and again essentially all of them
were found by *mutation* rather than by reading.

**Ruling IDs here are prefixed `AL-`** (alignment). `PF-`/`C-` belong to m1a,
`FS-` to flex sizing, and a bare `F-n` is ambiguous across m0, m1a and flex
sizing. Prefix every future milestone's rulings the same way.

## Pre-flight (from scanning the plan before any code)

| # | Ruling | Cost if wrong |
|---|---|---|
| AL-1 | **The plan says "six" main-axis-only golden comparisons. There are twelve.** Counted, not estimated — my error when writing the plan. Task 3's work is proportionally larger, not different in kind. | None; it is a count. |
| AL-2 | **Stretch breaks two existing tests, and they must be *retargeted*, not deleted.** `autoSizedChildWithNoMeasureFunctionIsZero` and `autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot` assert an auto item's **cross** size is 0. Once `align-items` defaults to stretch that becomes 100 and 600 — correct CSS, matching WebKit. But both are the killing pins for **FS-1** (the root reads `available`; a flex item does not), so deleting them would drop that guarantee at the exact moment it stopped being visible. Retargeted to the **main** axis, which stretch does not touch; the old cross assertion became a stretch assertion. | FS-1 goes unpinned and the container-extent fallback can creep back into the item path — the regression m1a's PF-3 and FS-1 both exist to prevent. |
| AL-3 | **The stretch rule must be axis-general, not row-only.** Both column fixtures stretch on the *width* axis; `flex_column_grow_with_max`'s golden holds `width: 100` per child while our engine gave 0. Verified rather than assumed. | Column containers silently ignore stretch. |

## During execution

| # | Ruling | Cost if wrong |
|---|---|---|
| AL-4 | **We follow both engines over the spec's letter on negative free space.** See below. | A centred-overhang line under `space-around` where CSS's letter wants one. Matches every shipping browser, so the risk is theoretical. |
| AL-5 | **Add the `gap` + `space-between` fixture.** The trailing-gap bug had exactly one killing test, and it called `lineContentSize` directly — bypassing `positionItems` and `computeLayout` entirely. The plan's own fixture template caused this: I wrote it without a gap. | The trailing-gap hole reopens with nothing end-to-end watching it. |
| AL-6 | **The task that makes an API inert records its table row; the task that makes one live deletes it.** I had told Task 1 that Task 3 owned CLAUDE.md, but the plan has Task 2 adding the `baseline` row. A row is collateral of whichever task changes an API's liveness — so Task 2 added `baseline` (it is what makes a baseline row lay out silently as flex-start) and Task 3 kept the deletions and the count. | One row added a task early. Trivial beside a silently inert alignment value. |
| AL-7 | **The column blind spot becomes a constraint on Task 4, not a footnote in Task 3's report.** The corpus had **no column fixture with a definite main size on any child**, so hardwiring the stretch rule's cross-dimension lookup to `.height` still found `.auto`, still stretched, and produced identical output — caught by one hand-written test and no fixture. Task 4 was adding column fixtures anyway; one of them now carries an explicit `height`. | A single hand-written test stands alone in that gap. |

## AL-4: two engines outrank the spec's letter

CSS Box Alignment says `space-around` with negative free space is *identical to
`center`*. Our code clamps the distributed portion to zero instead. Measured on a
2×80px line in a 100px container (free space −60):

| | `space-around` | `space-evenly` | `space-between` | `center` |
|---|---|---|---|---|
| WebKit | `[0, 80]` | `[0, 80]` | `[0, 80]` | `[-30, 50]` |
| Blink | `[0, 80]` | `[0, 80]` | `[0, 80]` | `[-30, 50]` |
| Spec letter | `[-30, 50]` | — | — | `[-30, 50]` |
| MetalUI | `[0, 80]` | `[0, 80]` | `[0, 80]` | `[-30, 50]` |

Both engines clamp; neither follows the spec's letter. `center` and `flex-end` do
honour negative free space, in all three.

**This is the mirror image of ruling FS-9**, where Blink and the spec agreed and
WebKit was the lone dissenter — there we kept the spec. Together the two cases
give a rule rather than two ad hoc calls:

> **Two independent engines agreeing outrank the spec's letter. One engine alone
> does not outrank the spec.**

FS-9 kept the spec because WebKit was alone *and* internally inconsistent. AL-4
follows the engines because they agree with each other.

## Rulings by reviewers and implementers that were accepted

Recorded because they corrected *me*, and the reasoning generalises.

- **"This mutation will redden nothing" is itself a claim worth checking.** I
  predicted the `alignItems ?? .flexStart` mutation would redden nothing until
  stretch landed. It reddened one test — the unit assertion pins the resolver's
  *returned enum*, not the layout, so it catches the change even where placement
  collapses. I had reasoned about placement and forgotten the test.
- **Enumerate the independent decisions a line makes, not the lines.** A green
  hole survived two mutation rounds because the stretch clamp's two lines do
  *three* independent jobs — exist, pick an axis, pick a percentage basis — and a
  plan built by walking lines covered two of them and read as thorough.
- **FS-1 lives in `flexBaseSize`, not `resolveNodeSize`.** I sent a reviewer to
  the wrong function to verify AL-2. An item's main size has not come from
  `resolveNodeSize` since the flex-sizing milestone. Now named in the tests'
  comments, with the mutation that actually reddens.
- **The reverse-design rationale was wrong twice.** The plan claimed reversing
  the items array would corrupt `space-between`'s leading offset; it would not —
  `distributeMainAxis` has no per-item notion of "first", and `space-between`'s
  leading is 0. My first correction was also wrong. The real discriminator is
  **`leading == trailing`**, not `leading == 0`: array-reversal needs a
  compensating flip only for the *asymmetric* distributions, `flex-start` and
  `flex-end`. A reviewer proved it by implementing array-reversal and finding a
  `row-reverse` + `space-around` probe still matched WebKit exactly.

## What the corpus kept failing to see

Continuing the previous milestone's table. Every one of these was a fixture or
test too uniform to distinguish the thing it claimed to pin:

| Blindness | What it hid |
|---|---|
| No fixture set a `gap` alongside `justify-content` | Whether a trailing gap reaches the engine at all — the one killing test bypassed `positionItems` |
| Every alignment fixture was a **row** | Cross alignment for every `.column` container; also both `containerCross` axis selections |
| Three of five `AlignSelf → AlignItems` arms unexercised | A `.stretch` typo would have silently disabled stretch for every explicit `align-self: stretch` |
| No column child had a definite **main** size | Which of an item's two size dimensions the stretch rule reads — both being `.auto` makes the wrong one look right |
| No test resolved a **percentage** cross bound | Whether `max-height: 50%` resolves against the cross extent or the main one |

**Before committing a fixture, change the declaration it is named for to its
nearest sibling, regenerate, and confirm the numbers move.**

## Carried risk

- **`layOutChildren`, `collectItems` and `positionItems` each derive `isRow`,
  `gap`, `containerMain`/`containerCross` and now `resolvedAlignment`
  independently.** A unilateral change to any one is caught by tests, but nothing
  states that they must agree. *(`layoutContainer` became `layOutChildren` +
  `placeNode` in the content-sizing milestone. Two things changed for this risk
  and neither reduced it: `containerMain`/`containerCross` are now `Double?` in
  `layOutChildren` and `collectItems` — where `nil` means indefinite, ruling
  CS-D — while `positionItems` still takes a definite `SizeD`, so the three
  derivations no longer even have the same type; and `contentMain` added a
  fourth re-derivation of the outer-sizes-with-gaps total, unguarded until
  `measuringAWrappedContainerCountsGapsAndMargins`.)*
- **`ResolveFlexibleLengths.swift` re-implements `lineContentSize`'s gap
  arithmetic** rather than calling it. The two do not currently cancel — mutating
  both still reddens — but they are one edit apart from doing so.
- **`distributeMainAxis`' `guard itemCount > 0` is unreachable** and has no
  killing test.
- **`flex_row_justify_between_gap`'s golden is byte-identical to its no-gap
  sibling** by design, because `gap` cancels exactly under a correct
  `space-between`. Its in-fixture comment is the only thing stopping someone
  deleting the corpus's sole end-to-end trailing-gap guard as a duplicate.
- **Content-based cross sizing (§9.4's other half) is still 0**, and no fixture
  can reach it until M2 measures content.
- **`min-width: auto` still has exactly one killing test** (carried from FS).
- **`LayoutNodeID` has no generation counter** (m1a ruling C-3).
- **Two guarantees lapse under plausible CI configurations** — the ABI probe
  skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only
  live-WebKit consumer. Both must be required, non-gateable jobs.
