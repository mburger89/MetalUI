## Layout cost — measured, and content sizing multiplied it by ~4.9x

`computeLayout` costs **~40 us per node in debug and ~5 us in release**, flat
from 8 k to 88 k nodes. The same trees cost ~8 us and ~1.2 us per node before
content sizing, so **the complexity is unchanged and the constant factor is
~4.9x**. Both figures were re-measured 2026-08-29 after the measure-performance
milestone and still hold — see the re-measurement below for why a milestone
that made the measure path faster moved neither of them. **They also still
hold after the sizing milestone's TX-H fix, on these exact trees — and the
reason needs its own paragraph, immediately below the table, because the
straightforward re-measurement is a false negative (ruling `SZ-N`).**

**Measured during the content-sizing milestone's Task 6 (2026-08-26), on that
machine; debug build unless a column says release.** A performance figure drifts
more quietly than a behavioural one — re-measure before deciding anything on
these.

| tree | nodes | debug before → after | release before → after |
|---|---|---|---|
| depth 12, branch 2 | 8,191 | 72.8 → **372.0 ms** | 10.2 → **45.0 ms** |
| depth 10, branch 3 | 88,573 | 708.4 → **3,504.4 ms** | 96.3 → **456.9 ms** |

**Corroborated 2026-08-27** on the structural-identity branch, and it is
corroboration rather than a re-run: a whole `Frame.render` — element walk,
`computeLayout`, prepaint and paint — over the same node counts cost **369.5 ms**
and **3,540 ms** in debug, **51.6 ms** and **520.7 ms** in release. Those bracket
the `computeLayout`-only figures above from the correct side, so the table has
not rotted on this machine; it has not been re-taken with the same harness.

**RE-MEASURED 2026-08-29** with the table's own harness rebuilt (same shapes,
same `available:`, best of 5 and 3 runs; MacBookPro18,2 / Apple M1 Max, macOS
26.6.2, Swift 6.3.3), after the measure-performance milestone changed the
measure path:

| tree | nodes | debug | release |
|---|---|---|---|
| depth 12, branch 2 | 8,191 | **362.8 ms** (44.3 us/node) | **41.6 ms** (5.08 us/node) |
| depth 10, branch 3 | 88,573 | **3,467.6 ms** (39.2 us/node) | **414.5 ms** (4.68 us/node) |

**RE-MEASURED a third time, 2026-08-31, after the sizing milestone's TX-H fix
(ruling `SZ-M`) — and on these SAME two trees under their default style, the
before/after is noise, not a finding.** `Style.alignItems == nil` resolves to
CSS's initial `stretch`, and a stretch-eligible item is excluded outright by
TX-H's new recompute guard (`SZ-M`) — its cross size comes from the line, not
from content, so the fix's whole code path never fires for a tree built with
no `alignItems` set. Measured anyway, before/after, best of 5: debug 8,191n
440.05→430.65 ms (**-2.1%**), 88,573n 3961.00→4007.64 ms (**+1.2%**); release
8,191n 46.23→50.69 ms (**+9.6%**, noisy at this small an absolute time),
88,573n 443.40→448.48 ms (**+1.2%**) — a benchmark of a configuration in which
the new code is unreachable, the measure-performance milestone's "measure on
a branching tree, never a chain" lesson arriving one level up (ruling `SZ-N`,
`docs/superpowers/2026-08-30-sizing-decisions.md`; also carried into
`docs/practices/verifying-tests-can-fail.md`). **The two tables above this
paragraph — CLAUDE.md's own canonical "~40 us/~5 us, flat 8k-88k" figures —
are therefore still accurate for exactly the tree shape they were taken on**:
a container tree with no `alignItems` declared pays nothing for TX-H, because
it never reaches the branch.

**TX-H's real cost was measured on the same two trees with `alignItems:
.flexStart` on every interior node instead**, so every auto-cross item is a
recompute candidate whenever its main size actually moves — which is
pervasive in a wide, deep, row-branching tree shrinking under an 800x600
offer. That is a DIFFERENT tree from the two tables above (styled, not
styleless) and its numbers are not comparable to them line-for-line; they
answer "what does TX-H cost when its code path actually runs" rather than
"did this milestone change the flat per-node figure":

| tree | nodes | debug before → after | release before → after |
|---|---|---|---|
| depth 12, branch 2 | 8,191 | 463.724 → 459.048 ms (56.62 → 56.05 us/node, **-1.0%**) | 51.133 → 51.712 ms (6.24 → 6.31 us/node, **+1.1%**) |
| depth 10, branch 3 | 88,573 | 4173.606 → 4272.613 ms (47.13 → 48.24 us/node, **+2.4%**) | 476.815 → 492.135 ms (5.38 → 5.56 us/node, **+3.2%**) |

The larger, more stable sample (88,573 nodes) shows a consistent **+2.4%
(debug) / +3.2% (release)** cost when TX-H's recompute path is exercised on
essentially every eligible item — a worse case than most real trees hit,
since most flex layouts are not universally `flexStart` with universal
shrinking. The 8,191-node debug delta (-1.0%) is within run-to-run noise at
that tree's absolute cost (~460 ms). **Nothing here moves the ~40 us/node
debug / ~5 us/node release order of magnitude the canonical tables above
record** — that figure describes the default-style tree, which TX-H does not
touch at all.

**The table above is confirmed, not corrected — and the reason it did not move
is the thing to carry.** This milestone memoized the min-content width of a
**string**, in `ShapingCache`; these trees contain no `Text` at all (interior
nodes are auto-sized flex containers, leaves are 10x10 boxes), so not one call
in them reaches the memo. A tree of boxes costs today what it cost before, and
anyone reading "the measure path got faster" as "these numbers got smaller"
would be reading a text optimisation into a tree with no text in it.

**Where the milestone's change actually shows is a tree with `Text` in it, and
the demo is the one to quote.** The whole `Frame.render` over
`Sources/MetalUIDemo/main.swift`'s real element tree at 920x560, release, best
of 200 warm renders on the machine above:

| demo list | base commit `adaab87` (a `for` loop over every row) | today (`List`, windowed) |
|---|---|---|
| 40 rows | 5.366 ms | **1.279 ms** |
| 500 rows | 50.498 ms | **1.273 ms** |

Debug, same tree: 15.295 / 145.463 ms before, **5.069 / 5.060 ms** today. Two
independent effects are stacked in that table and it is worth keeping them
apart. **The 40-row column is the memo** — the same rows, ~4.2x cheaper, because
each `Text`'s min-content width is now a dictionary hit instead of a tokenizer
walk. **The 500-row row is the window** — flat in row count, because `List`
builds only the rows the viewport intersects. Neither number says anything
about the box-tree table above, and vice versa.

**Re-measured 2026-08-29 after the input-and-state milestone put a counter in
that tree, and the question it answers is whether hitbox registration undid any
of the above.** Same machine, same 920x560, release, best of 200 warm renders
after 10 warm-ups, both arms in one process so the comparison is not across
runs. "OLD" is this branch's base commit `76a878a` — the demo *without* the
counter — rebuilt beside the current tree rather than quoted from the row above:

| demo tree | 40 rows | 500 rows |
|---|---|---|
| OLD, no counter (base `76a878a`) | 1.340 ms | 1.347 ms |
| NEW, counter with **no handlers at all** | 1.562 ms | 1.564 ms |
| NEW, counter as shipped | **1.571 ms** | **1.570 ms** |

**Registration is ~0.01 ms — about **4%** of what the panel costs and ~0.6% of a
frame.** (From the table's own numbers: (1.571 − 1.562) / (1.562 − 1.340) = 4.1%,
and 0.009 / 1.571 = 0.57%. This sentence gave the frame ratio twice and
understated the panel ratio sevenfold until it was recomputed.) The third row differs from the second only by an `onClick` on each
button, `.focusable()`, `.keyContext(_:)` and two `.onAction(_:_:)` handlers, so
the gap between them is the whole cost of putting an element into the hitbox
list, the focus registry and the action registry. The 0.22 ms between the first
two rows is the panel *itself* — three more `Text` leaves, each measured by the
tokenizer, plus four boxes — and has nothing to do with input.

**The flatness in row count is untouched, which is the property that mattered:**
1.571 ms at 40 rows against 1.570 at 500.

**The OLD arm reads 1.340/1.347 where the row above records 1.279/1.273 for the
same tree.** ~5%, one milestone and one harness apart, on the same machine. The
conclusion is unaffected either way, but the numbers to reproduce are the ones
in *this* table, taken by the method it describes.

**The cause is §4.5's automatic minimum, which now probes EVERY item** —
`min-width: auto` is CSS's default — and an `auto`-cross item probes again, so a
container's children are each measured up to three times per layout. Whoever
optimises this starts there: it is the probe that fires unconditionally. The
memo cache in `LayoutContext` is what keeps this a constant multiplier instead
of the depth-exponential ~700x the design spec predicted without it, and
`theCacheIsActuallyConsulted` is the only test that can see the cache working.

**Measure on a BRANCHING tree, never a chain.** A chain has one child per level,
so the three probes per item collapse onto the same few cache keys and the cost
looks linear and cheap — which is exactly what the during-task measurement
showed, and why this number went unrecorded until the milestone's last task.
Absolute figures are this machine's; the ratio is the part that transfers.
Release is ~8x faster in absolute terms with the same ratio. For scale, Yoga and
Taffy are quoted in the 0.1-0.5 us/node range.

### The 100k cold frame is 16.84 s in RELEASE, and M3's exit criterion is met for scrolling and not for appearing

**Measured 2026-09-01 on the tombstones-and-AX branch: 41.86 s debug / 16.84 s
release for frame 0 at 100,000 rows**, reproduced at **16.53 s** release on a
later, independent run — the same number twice on different runs, which is what
makes it a measurement rather than a sample. Ruling `TB-K`. **Both figures are
Task 8's and its fix round's, not the documentation task's**: reproducing them
means running the env-gated test named below, which nobody has done since. The
command is in the Build section precisely so that stays cheap.

**This is ruling MP-I's cost, scaled, and it is not a new mechanism.** A
`ScrollView`'s viewport extent is not measured until its own `prepaint` has run
once, so the first frame builds *every* row. MP-I already records that as 76 ms
release / 188 ms debug at 500 rows; at 100,000 rows it scales roughly linearly
to sixteen and a half seconds.

**So state M3's exit criterion at exactly its strength.** "A 100k-row
virtualized list scrolling smoothly" is met for **scrolling** — steady-state
tokenizer calls and shaping-cache entries are *equal* at 500 rows and at
100,000, and the resident `StateTable` set collapses from the cold frame's
`n + 2` to well under a thousand within ten scroll frames and stays there. It is
not met for **appearing**: the list hangs for ~17 seconds the first time it is
shown. Both are true and only the first is what the criterion literally asks
about, so a reader who takes "100k works" to mean "usable at 100k" is reading
past the measurement.

**The collapse is asserted at 10,000 rows rather than 100,000, and the reason
is worth keeping** (ruling `TB-L`): the checkpoint counts depend on the *window
size* and on `staleAfterGenerations`, not on total row count, so 10k and 100k
give byte-identical checkpoints and the 100k version bought nothing but wall
clock. `theResidentEntrySetStaysBoundedWhileScrolling10kRows` asserts a cold
peak of exactly `n + 2` (10,002 — every row, plus the scroller's `ScrollState`,
plus the `List`'s own `$ax` retention slot) and then `count < n / 10` at three
checkpoints over 300 large-jump scroll frames. It **prints** the actual values,
which on the run this section was re-measured from were **77 / 127 / 99** at
frames 10 / 100 / 299 — read them out of the run rather than quoting them, since
they are printed and not asserted. The `+ 2` rather than `+ 1` is Task 7's AX
emission: **one extra entry per `List`, flat in row count**, verified by scaling
(+2 at 50, 200 and 800 rows; +3 with two `List`s) rather than by reading the
diff, which is ruling `TB-X`.

**Not fixed here, and the reason is the one MP-I already gives**: the remedy is
a two-pass layout, or a resolved viewport threaded into a phase defined to run
before geometry exists — a different layout architecture, explicitly larger than
this milestone. The number is in the record rather than in a test assertion,
because `ContinuousClock` output on a shared machine is a flaky thing to
`#expect` on; `aListsWorkIsTheSameFor100kRowsAsFor500` prints it and asserts
only counts. **That test is env-gated** and its command is in the Build section
— it alone costs ~42 s debug / ~17 s release, which is ruling `TB-L`.

### Identity path construction — measured 2026-08-27, and it is ~0.4% of a frame

**Measured 2026-08-27 on the structural-identity branch, debug unless a column
says release**, with a throwaway spike deleted in the same task. Re-measure
before deciding anything on these. The counterfactual is the pre-milestone array
representation (`(parent?.path ?? []) + [component]`) reconstructed beside the
shipping linked list and timed on the same trees in the same process; best of
five, one path per node.

**The `depth` column counts LEVELS here and EDGES in the table above** — the two
harnesses were written a day apart and disagree. The **node count** is the
unambiguous key, and it is deliberately the same 8,191 and 88,573, so the rows
line up despite the labels.

| tree | nodes | avg depth | linked us/node | array us/node | ratio |
|---|---|---|---|---|---|
| 13 levels, branch 2 | 8,191 | ~12 | **0.154** / 0.093 rel | 0.697 / 0.300 rel | 4.5x / 3.2x rel |
| 11 levels, branch 3 | 88,573 | ~10 | **0.150** / 0.088 rel | 0.660 / 0.272 rel | 4.4x / 3.1x rel |
| 3 levels, branch 90 | 8,191 | ~3 | **0.144** / 0.084 rel | 0.501 / 0.141 rel | 3.5x / 1.7x rel |

**The third row is the control**, and it is what makes this a measurement of the
O(1)-vs-O(depth) claim rather than of the tree: same 8,191 nodes, average depth
~3 instead of ~12.

**Release is the load-bearing column for the O(1) claim, and an independent
re-run is why this clause exists.** In debug the linked list's own depth
sensitivity across the control (−6% here, −25% in the re-run) is comparable to
the array form's (−28% here, −18% there), so the debug rows do not separate the
two models cleanly — allocation and retain/release traffic dominate both. In
release they do separate: array 0.300 → 0.141 against linked 0.093 → 0.084. Read
the release figures for the claim and the debug figures for the absolute cost.

**End to end the win is at or below noise, and that is the honest headline.**
Path construction is 0.3-0.4% of a debug `Frame.render` and ~1.5% of a release
one. The saving over the array form is 4.5 ms on the 8,191-node tree against a
7.2 ms run-to-run spread — **not visible above noise** — and 45 ms against a 19
ms spread on the 88,573-node tree, which is measurable and still ~1.3% of the
frame. The linked list is the right structure for the reason it was chosen (it
removes a depth factor from a per-frame cost for one allocation's price), but
nobody should expect a frame-time change from it while `computeLayout` costs
~40 us/node.

