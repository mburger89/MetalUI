# Measure-path performance — decisions taken during execution

Rulings from the milestone that memoized `Text`'s min-content width and re-measured
whether reducing probe *count* was still worth pursuing after that. Prefixed **`MP-`**
and **lettered** (`MP-A`, `MP-B`, …) per this repo's convention — a bare `MP-3` is a
typo, not a citation. Read alongside
`docs/superpowers/specs/2026-08-28-measure-performance-design.md` (§8 in particular,
the section these rulings close) and `.superpowers/sdd/2026-08-28-measure-performance/`
(task-1 and task-2 reports, which this document's numbers build on).

---

## MP-A — the probe count is out of scope; the milestone stops after Task 2

**The choice.** Task 2's memoization is where this milestone's min-content work ends.
The count of probes per `Text` is not reduced, and no further code change is made to
touch it.

**What was measured, on `demoLikeRows(40)`, release, the same tree and construction
Task 2 used (a `StateTable`/`ShapingCache`/`GlyphAtlas` shared across renders, one
warm-up render first, matching `Window`'s real per-frame construction):**

| quantity | value |
|---|---|
| probes per `Text` per frame | **2.0** (80 calls / 40 `Text`, confirmed by a call counter on `ShapingCache.minContentWidth`, not inferred from `Shaper.unbreakableRunCalls`) |
| of those 80, cache hits in steady state | **80 (100%)** — 0 misses, confirming Task 2's report that a persistent, `Window`-shared cache sees zero repeat tokenizing in production |
| cost of one warm probe (a hit) | **~241 ns** (240, 241, 247 ns across three isolated runs, `ContinuousClock`, 2,000,000 iterations each) |
| cost of one probe before Task 2 (a miss) | **30,660 ns** (design spec §2.1/§8's own figure). Re-measured in isolation on today's code, same mechanism, different string and methodology (a shared cache, a never-before-seen string each call, so genuinely cold): **~41,707 ns** — same order of magnitude, confirming the miss path is untouched by Task 2 as expected; not a literal reproduction, since the spec's number came from a different harness measuring a different string in place inside a full pipeline |
| speedup, warm vs. the historical miss cost | 30,660 / 241 ≈ **127x**, a **99.2%** reduction — better than §8's predicted ~98% (~604 ns, ~50x) |
| remaining probe traffic per frame | 80 × 241 ns ≈ **19,280 ns ≈ 0.019 ms** |
| warm release frame cost, `demoLikeRows(40)` | **1.566, 1.626, 1.632 ms** across three runs (mean **1.61 ms**) — consistent with Task 2's independently reproduced 1.578 ms / 1.536 ms / 1.546 ms |
| remaining probe traffic as a fraction of the frame | 0.019 / 1.61 ≈ **1.2%** |

**The design spec's own bar (§8) is ~5%: this measures at ~1.2%, comfortably under
it.** §8 predicted the fix's value would fall by ~98% and that the count question
should be re-measured before deciding whether to pursue it further, explicitly
flagging that reducing the *count* means changing what the engine measures and when,
with 81 goldens downstream of that path. The measurement confirms the prediction's
direction and beats its magnitude (99.2% vs. ~98%), and the remaining cost is small
enough that further work here would be optimising noise.

**Reasoning.** A 1.2% frame cost bought by reordering when the engine measures a
node's automatic minimum is not a trade worth 81 goldens' risk. The two probes
per `Text` do not come from redundant work at the call-count level (see `MP-B`) —
they come from two genuinely different questions the flex algorithm asks (an
ancestor's own content-based flex-basis, and this item's own floor for the freeze
loop), asked at two different points in one layout pass. Collapsing them into one
would mean either caching across those two call sites (a correctness hazard: the
second call's result must reflect the first call's answer being consulted at a
point where the tree's resolved sizes are not the ones the first call saw — see
`MP-B`'s stack trace evidence) or restructuring the algorithm so the same
information is computed once and threaded through — real reach into `FlexEngine`,
for a return of ~19 microseconds a frame.

**What it costs if wrong.** If a future workload makes probe *count* itself the
bottleneck — e.g. a list an order of magnitude larger than 160 rows, or a tree
with many more `Text` items per row — this ruling's ~1.2% figure will have moved
and should be re-measured before being trusted again; it is a property of
`demoLikeRows(40)`'s shape (80 calls, ~241 ns/call, ~1.6 ms frame), not a
constant. If skipped, the risk is small: the alternative this ruling declines is
itself unbuilt, so declining it costs nothing beyond leaving ~19 microseconds a
frame on the table, which is the entire finding.

---

## MP-B — the "two call sites" the last review named are not what fires; both probes trace to one line, called twice

**The choice.** Recording this as a correction rather than silently fixing the
citation, because Task 3's own brief carried the assumption forward
(`Text.swift:80` as one site, `FlexEngine.swift:1921`'s cross-axis fit-content
probe as the other) and a later reader would otherwise inherit it.

**What was measured.** Two independent counters were added (temporarily) at
`FlexEngine.swift`'s two candidate `.minContent`-producing call sites — the §4.5
automatic-minimum content-suggestion probe (`collectItems`'s `minMain` closure,
around line 1687: `let probe = measureNode(ctx, tree, kid, known: .unspecified,
available: AvailableSpaceSize(width: isRow ? .minContent : .maxContent, …))`,
gated on `isRow`) and the cross-axis fit-content probe (`collectItems`'s
`ownCross` closure, around line 1921: `value = max(measure(cross:
.minContent).width, available)`, gated on `!isRow` and `value > available`) —
on a steady-state render of `demoLikeRows(40)`:

- **Of the 80 `minContentWidth` calls, 40 trace through a stack containing
  `flexBaseSize` and never `placeNode`, and the other 40 through
  `placeNode`/`computeRootLayout` and never `flexBaseSize`** — an exact 40/40
  split between the two callers named below, independently reproduced under
  the reviewer's own call-stack instrumentation. **A raw firing count for the
  automatic-minimum probe *line itself* (line ~1687) is deliberately not
  reported here.** A first attempt at that count, using symbol-name matching
  on `Thread.callStackSymbols` rather than a reproducible per-frame counter,
  read 121; independent re-measurement read 485 — a 4x disagreement neither
  side could explain, so the number is dropped rather than kept and flagged.
  The claim this ruling actually needs is the 80/40/40 split above, which
  reproduced exactly; nothing below depends on how many times the source line
  fires at intermediate nesting levels on the way to a leaf.
- **The cross-axis fit-content probe (line ~1921) fired exactly 1 time**, and a
  `Thread.callStackSymbols` capture on `ShapingCache.minContentWidth`'s two calls
  per `Text` showed neither of them originating there. This is the pinned-width
  fix from Task 1 working exactly as recorded in `demoLikeRows`'s own comment —
  the row `Box`'s cross axis (width) is `.width(Pixels(420))`, not `.auto`, so
  `ownCross`'s `guard case .auto = crossDim else { … }` returns immediately and
  the probe inside it is unreachable for the 40 row boxes. What is newly
  established here is that with the pin in place this site is effectively
  **dead** for this tree, not merely reduced from the three-probe count Task 1
  measured without it.
- **A captured call stack on both of a `Text`'s two `cache.minContentWidth`
  calls** shows they are the *same source line* (the automatic-minimum probe,
  line ~1687), reached from two different callers:
  1. **`flexBaseSize`**, computing the row `Box` item's own content-based
     flex-basis within the content column's layout — an intrinsic-sizing
     *probe* over the row `Box`'s subtree, which recurses down into the row
     `Box`'s own `collectItems` call for its `Text` child and hits the
     automatic minimum there.
  2. **The real positioning pass** — `computeLayout` → `Frame.computeRootLayout`
     → … → `positionItems` → `placeNode` → `layOutChildren` → `collectItems` —
     laying out the row `Box`'s children for real, which independently
     re-derives `Text`'s automatic minimum to floor/clamp its main size for
     §9.7's freeze loop.

  `Text.swift:80` (`cache.minContentWidth(string, font: font)`, inside
  `textMeasure`'s `.minContent` case) is not a third, independent site — it is
  the one place any caller's request for a leaf's min-content width actually
  lands, since it is the body of `Text`'s own attached `MeasureFunction`. Both
  call chains above pass through it because both eventually ask the leaf a
  question, not because it originates two probes on its own.

**Why this matters beyond correcting a citation.** It rules out the reading
that the second probe is *redundant* work an obvious cache could remove for
free. It is two different questions — "what does this container's content
want" and "what is this item's floor" — asked from two different points in one
pass, on the same node. `MP-A`'s reasoning about `FlexEngine` reach for ~19
microseconds a frame rests on this: there is no free win sitting between the
two calls, because the two calls are not the same request made twice — they
are the automatic-minimum computation genuinely needed twice, at two points
where the tree's provisional sizes differ (the probe's ancestor-content-basis
pass happens before the item's real position and clamp are known).

**What it costs if wrong.** If a future reader trusts the un-verified
"`Text.swift:80` + `FlexEngine.swift:1921`" framing and goes looking for a fix
at the cross-axis fit-content site, they will find nothing to change — that
site does not fire for this tree at all with the width pin in place — and may
conclude (wrongly) that the milestone's own finding was fabricated rather than
that the citation was wrong. Re-measure with the method above (call-site
counters plus a captured call stack on `ShapingCache.minContentWidth`) before
trusting either this correction or the original claim on a different tree
shape — the 80/40/40 split is specific to `demoLikeRows(40)`'s nesting, and a
differently-shaped tree should not be assumed to keep it. Use a reproducible
per-frame counter for any further count on this mechanism, not symbol-name
matching on a captured stack trace: that method is what produced the 121-vs-485
disagreement this ruling declined to resolve.

---

## MP-C — an auto cross size costs an extra §4.5 probe per item, and this is reusable, not milestone-scoped

**The finding, carried forward from Task 1's A/B (not independently re-measured
here — recorded because it belongs beside `MP-A`/`MP-B` as the reusable half of
this milestone's probe-count knowledge, and because CLAUDE.md's own instruction
for this task named it explicitly):**

| row shape | probes/`Text` |
|---|---|
| auto width + `alignItems(.stretch)` | 3.0 |
| auto width + `alignItems(.center)` | 3.0 (rules out `alignItems` as the cause) |
| `.width(Pixels(420))` pinned | 2.0 |

Without a declared width, a row is an auto-cross item of its own container, so
`collectItems`' `ownCross` fit-content probe (`FlexEngine.swift` ~1921, the
site `MP-B` shows is otherwise dead on the pinned tree) recurses into §4.5's
automatic minimum a third time. `demoLikeRows`'s own comment already carries
this as the reason its rows are pinned to `.width(Pixels(420))` rather than
left `auto`, matching the real demo (`Sources/MetalUIDemo/main.swift:391-397`).

**Why this belongs here rather than only in CLAUDE.md.** It is the one concrete,
generally-applicable optimisation this milestone found: **declaring a width
removes a third of the probe traffic on that subtree**, independent of whether
`MP-A`'s cost analysis ever changes. A future caller measuring their own tree's
probe count should check for auto-width items before assuming the count is
fixed by the engine's algorithm.

**What it costs if wrong.** Nothing changes in production code from this
ruling — it is a record, not an implementation. The risk is a stale citation if
`ownCross`'s gating (`guard case .auto = crossDim`, `if !isRow`) is ever
restructured: re-verify the three-row table above against the oracle before
citing it in a design that depends on the exact 3.0/2.0 split, the same
caution `MP-B` gives for its own counts.
