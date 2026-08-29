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
left `auto`, matching the real demo (the row closure inside `List` in
`Sources/MetalUIDemo/main.swift`; the line numbers this once cited moved when
that loop became a `List`, so it is quoted by construct rather than by line).

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

---

## MP-D — a `List` row takes identity from its datum, and `String(describing:)`'s non-injectivity is accepted rather than fixed

**The choice.** `List` requires `Data.Element: Identifiable` and wraps each row
under `.id(String(describing: datum.id))`. Two distinct ids that describe to the
same string — `AnyHashable("1")` and `AnyHashable(1)`, both `"1"` — land on the
same `GlobalElementID` and silently share one `StateTable` entry. That collision
is recorded (in `List`'s type doc and at the call site) and not fixed.

**Reasoning.** Identity in this framework is structural: a `.positional(Int)`
component is assigned by the cursor walking the *built* children, and a windowed
row's position among its built siblings changes every time the window slides. A
name replaces a position rather than joining it, so a data-derived name is the
only thing that makes a row that scrolls away and back land on the same id —
`Identifiable` is a load-bearing requirement, not a convenience. The bridge to a
name has to be a `String` because `ElementID` is `String`-backed; changing that
is a framework-wide job with nothing to do with windowing.

**What it costs if wrong.** A caller whose `Data.Element.ID` is not string-shaped
(an `AnyHashable`, an enum with duplicate descriptions) gets two rows sharing one
state entry, with no trap and no failing test — the same silent-sharing failure
the `cachedHash`/`==` bullet in CLAUDE.md exists to prevent, arriving through a
different door. Pinned in the *other* direction only:
`distinctRowsGetDistinctIdentities` (`Tests/MetalUITests/ListTests.swift`) shows
distinct ids stay distinct, which is exactly the case `String(describing:)` gets
right. Nothing guards the collision itself.

---

## MP-E — a row's height is pinned by REMOVING the automatic minimum, not by declaring a height

**The choice.** `List.requestLayout` sets three things on every row's wrapping
`Box`, not one: `size.height = rowHeight`, `minSize.height = 0` and
`flexShrink = 0`.

**Reasoning.** A declared height alone does not hold. CSS Sizing §4.5's automatic
minimum — the *content* half, the half this engine implements (CLAUDE.md
divergence 5) — floors a flex item at its content's size, so a row whose text is
taller than `rowHeight` grows past it and every later row's `index * rowHeight`
position is wrong. And a default `flexShrink: 1` lets negative free space
(padding on `List` shrinking its own content box) pull every row back below it.
These are the identical two lines `ScrollView.requestLayout` sets on its content
node for the same mechanism (ruling CL-C). Uniform row height is what makes the
window computable by division, so anything that lets a row differ from
`rowHeight` breaks windowing itself, not just that row's appearance.

**What it costs if wrong.** Measured with each line removed, on a three-row list:
without `minSize.height` a row whose leaf measures 60 lays out at 60 and the rows
land at `[0, 60, 120]` instead of `[0, 28, 56]`; without `flexShrink` a
`.padding(10)` list lands them at `[10, 31, 53]` with heights `21, 22, 21`.
Either way `List`'s own window arithmetic — which never lays a row out to find
where it is — points at rows that are not there. Pinned by
`aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` and
`paddingOnAListDoesNotShrinkItsRowsBelowRowHeight`.

---

## MP-F — the ambient scroll context publishes the RAW offset and LAST frame's viewport extent

**The choice.** `ScrollView.requestLayout` pushes a `ScrollContext` carrying the
*unclamped* stored offset and the viewport extent its own **previous** frame's
`prepaint` measured. `List` clamps the offset itself, against its own exact
content extent.

**Reasoning.** The offset is resolved and clamped in `prepaint` today, and
`requestLayout` — where a windowed child must decide what to build — runs before
it. Publishing a clamped offset from `requestLayout` would mean clamping against
a viewport the layout has not produced yet, i.e. inventing a bound. Publishing
the raw value keeps the one number that is *current* current, and hands the clamp
to the one participant that knows its own content extent without waiting for a
layout: `List` knows it is `count * rowHeight` by construction. The viewport
extent has no such escape — it genuinely is last frame's — and that is
CLAUDE.md's **divergence 13**.

**What it costs if wrong.** Scrolling stays exact either way, because the offset
is current; only a *resize* can make the window briefly wrong, by one frame, and
the two-row overscan absorbs a viewport that grew by up to two rows. A resize
that grows the viewport by more than the overscan shows a strip of missing rows
for one frame. Making it exact needs a two-pass layout, which is larger than this
milestone; the alternative of clamping in `requestLayout` is *worse* than
one-frame staleness, because a wrong clamp is wrong every frame rather than on
the frame after a resize. Pinned by
`rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange` and
`scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`
(`Tests/MetalUITests/ScrollRoutingTests.swift`).

---

## MP-G — a zero `rowHeight` falls back to building every row rather than trapping

**The choice.** `visibleRange`'s guard reads `rowHeight.value > 0` alongside its
two context checks; a zero or negative row height declines to window and builds
everything. It is not a `precondition`.

**Reasoning.** `rowHeight` is the divisor in both `offset / rowExtent` and
`(offset + viewportExtent) / rowExtent`, so zero gives `.infinity` (or `NaN` at
`offset == 0`) and converting either to `Int` traps — reproduced before the fix:
signal 5, **no summary line**, which is taxonomy shape 11's own failure mode. But
`Pixels(0)` was legal, silently-accepted input before windowing existed: a
zero-height list sized every row and itself to zero and drew nothing. Adding a
`precondition` would make previously-valid usage a process abort, which is a new
trap on old code rather than a fix to new code. Building every row is what
`List` did before windowing, so declining to window keeps that input exactly as
quiet as it always was.

**What it costs if wrong.** An accidental `Pixels(0)` costs O(n) per frame,
quietly — the very cost this milestone exists to remove, restored with no
diagnostic. That is the deliberate trade: a silent slow frame over a crash on
input the type used to accept. If a future reader decides the trap is the better
signal, note that they are changing the contract for callers who never opted in,
and that the failure mode they are choosing has no summary line. Pinned by
`aZeroRowHeightDoesNotTrapOnceAScrollContextIsPresent`.

---

## MP-H — a leading spacer places the window, not an absolute inset per row — and this was reasoned, not measured

**The choice.** The rows that are not built are replaced by one childless `Box`
of height `window.lowerBound * rowHeight`, so the first built row lands at its
true absolute offset through ordinary flex placement. The alternative —
`.position(.absolute).inset(top:)` on every row — was not built and not
benchmarked.

**Reasoning.** Absolute positioning would pull every row out of flow, so each
row's position would resolve against `List`'s own containing block instead of
falling out of the column it is already in; the spacer buys not having to reason
about containing blocks inside a list, for the cost of one extra `Box` per frame.
CLAUDE.md's divergence 11 does name the absolute composition as viable (an
absolute box inside a `ScrollView` stays clipped and translated by it, which is
what a windowed row wants), so this is a preference between two workable designs
and not a correctness argument.

**What it costs if wrong.** One `Box` per frame is not a measured cost, and the
comparison this ruling declines to run is the only thing that would say whether
the spacer's flex participation costs more than absolute placement. If a profile
ever says it does, nothing about `List`'s public interface changes — this is an
internal placement mechanism. The spacer *does* carry one non-obvious
requirement: `flexShrink = 0`, without which padding on `List` makes the spacer
absorb the deficit and pull every built row up by however much it lost (measured:
a full 84pt shift). Pinned by `aScrolledListsSpacerDoesNotShrinkUnderPadding`.

---

## MP-I — overscan is a private constant of 2, and the first frame builds everything

**The choice.** Two rows are built beyond the window on each side. `overscan` is
`private static var overscan: Int { 2 }` — not an `init` parameter — and a
present context whose `viewportExtent == 0` (a `ScrollView`'s first frame, before
its `prepaint` has ever measured one) builds every row instead of windowing.

**Reasoning.** A public knob nothing reads back is the exact shape CLAUDE.md's
declared-but-inert table exists to keep out of this API, and no caller has a case
for a different value yet; `init`'s signature stays unchanged, so nothing using
`List` today needs an edit when a case appears. The first-frame carve-out is
about a *flash*, not a trap: `viewportExtent` is only ever a numerator, so zero
divides nothing, but the offset on that frame is whatever was last scrolled to
and a naive window bounds almost nothing around it — measured with the guard
removed, a real first frame built exactly the two rows overscan allows. One slow
frame beats a visible flash.

**That trade was re-examined when the demo went from 40 rows to 500, and it is
still taken — but its cost is 12.5x what the sentence above was written
against, so the number is recorded rather than left implied.** The carve-out
means frame 0 builds *every* row: on the demo's own tree that frame emits 516
rects and 15,703 glyphs at 500 rows, against 23 and 514 once the window is
known. Measured, 25 cold trials, median:

| build | 40 rows | 500 rows |
|---|---|---|
| release | 7.87 ms | **76.26 ms** |
| debug | 19.32 ms | **188.30 ms** |

Kept, for three reasons. The hitch is one frame **at launch**, not during
interaction, so it costs a moment of startup rather than a stutter under the
hand. Demonstrating windowing in the artifact humans actually look at is the
point of shipping 500. And the alternative — windowing the first frame against
a *guessed* viewport — is new mechanism, and a guess wrong in the other
direction is the flash this carve-out exists to prevent.

**What it costs if wrong, restated at 500 rows**: ~188 ms in debug is roughly
eleven dropped frames at launch, and nothing in the suite can tell whether that
reads as a slow start or as a broken one. That is now item 4 of the human
report list in CLAUDE.md's own open-criterion entry — the only instrument there
is. A `List` whose data is larger again (5,000 rows, say) scales this linearly
and would need the first frame windowed for real.

**What it costs if wrong.** Two rows of overscan is a guess: nothing in this
suite can observe scroll jank, so the number was picked to satisfy "a row or two"
and never tuned. Too small shows a gap at a partially-scrolled edge while a frame
is in flight (and shortens the resize grace MP-F depends on); too large costs
rows nobody sees. A `List` inside a viewport that grows by more than two rows
between frames is the case to re-measure against. Pinned by
`aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan` (asserting the exact
built set, both that the overscan rows are present and that the next ones are
not) and `aPresentContextWithZeroViewportExtentBuildsEveryRow`.

---

## MP-J — `sweepThreshold` is a sweep TRIGGER, not a ceiling

**The choice.** `ShapingCache.sweepThreshold` (256) gates whether `endFrame()`
sweeps a dictionary at all; the sweep then drops only entries stamped older than
`staleAfterGenerations` (2). `count <= sweepThreshold` is **not** an enforced
invariant, and the constant was renamed from `entryBound` because that name
asserted one.

**Reasoning.** A ceiling would have to evict something a live frame is using the
moment the working set exceeds it. This one cannot: an entry touched this frame
carries `generation == currentGeneration`, which can never be stale, so the sweep
structurally cannot drop it — and a live working set larger than the threshold
simply settles above it and stays there, correctly. Measured: with this constant
set to **1**, so the sweep fires every frame, `demoLikeRows(40)` settles at **64
`storage` and 16 `minContent`** resident entries from frame 3 onward rather than
thrashing — that is the live working set, and no threshold can push it lower.
That is what makes a small threshold safe and a ceiling unnecessary. (At the
shipped 256 the same workload sits at **207 and 40** forever, because the first
frame builds every row and nothing is ever over the threshold to sweep.)
The true invariant is narrower and is what the doc comment now states: *nothing
older than `staleAfterGenerations` survives a frame in which the dictionary was
over this threshold.*

**What it costs if wrong.** Read as a ceiling, the number invites two mistakes.
Lowering it "to save memory" does nothing below the live working set and only
adds sweep frequency; and a test asserting `count <= sweepThreshold` as a general
property would be pinning a workload rather than the type — which is why
`theShapingCacheStaysNearTheSweepThresholdAcrossAWidthSweep` says in its own doc
comment that its `<=` assertion holds for *that* workload's small per-frame
footprint. The test that guards the real invariant is
`aSweepNeverDropsAnEntryTheCurrentFrameTouched`.

**One correction worth carrying, on the same footing as `MP-B`.** The held-back
assertion this milestone's plan drafted for the sweep could not fail: it swept
the outer `Frame`'s width over `demoLikeRows(40)`, whose every internal width is
pinned, so the cache reached a one-time warm-up value and then read
byte-identically on every later iteration — measured `distinct=[207]` across all
120 frames, with no bound and no sweep implemented. A test that passes against a
stub is not evidence about the stub. The shipped test sweeps a *row* width and a
per-frame-unique row string instead, which moves both dictionaries' keys the way
a real drag and a real scroll do.

---

## MP-K — a `Dictionary` may be swept where the glyph atlas may not

**The choice.** `ShapingCache` evicts on a generation sweep wired into
`Frame.render`'s per-frame brackets, mirroring `GlyphAtlas`'s `beginFrame`/
`endFrame` contract — while `GlyphAtlas.evictUnusedSince` itself still has zero
production callers.

**Reasoning, stated because the neighbouring type's rule looks like it should
apply.** The atlas's hazard is structural: its shelf packer never revisits a
closed shelf, so freeing a `GlyphKey` strands its pixels and the next request for
that glyph packs a second copy further down — eviction there makes the atlas fill
*faster*, which is why CLAUDE.md's declared-but-inert table says a caller would
make things worse. A `Dictionary` has no such structure to violate:
`removeValue(forKey:)` frees the slot outright and a later re-touch is an
ordinary miss followed by an ordinary insert. There is nothing to strand, so
there is nothing to trap on. The bracket is wider than the atlas's for a
different reason: a `Text` shapes during `requestLayout` and re-shapes in
`paint`, so `ShapingCache`'s frame spans layout *and* paint where the atlas's
spans paint only.

**What it costs if wrong.** If the sweep ever dropped an entry the current frame
was still using, the cost is a re-shape — a slow frame, not a wrong pixel, which
is the other half of why this is safe where the atlas's is not (a stranded atlas
region is a wrong pixel or a dropped glyph). The failure that *is* worth watching
is the reverse: a future cache whose values are handed out by reference rather
than by value would make eviction a lifetime question rather than a cost
question, and this ruling would not cover it.

---

## MP-L — a `List` must be its scroller's only layout-contributing child; the wrong-origin window is RECORDED, not fixed

**The choice.** `List.visibleRange` reads the ambient `ScrollContext.offset` as
"how far this `List` has scrolled" when what it actually is is "how far the
enclosing `ScrollView`'s content has moved under its viewport". The two are the
same number only when the `List` begins exactly at the scroller's content
origin. Rather than approximate the difference, this milestone makes "the only
layout-contributing child of its `ScrollView`" a stated requirement of `List`,
of the same rank as `Data.Element: Identifiable` and a uniform `rowHeight`, and
records the violation as CLAUDE.md **divergence 14**.

**Reasoning, and it is a phase contract rather than an oversight.** Correcting
the window needs the `List`'s own y-offset within the scroller's content, and
`requestLayout` has no position at all — that is what makes the phase
composable, and the same fact that makes `ScrollContext.viewportExtent` one
frame stale (MP-F). Supplying a position means one of two things, both larger
than a performance milestone: lay the `ScrollView` out once to resolve its
children's positions and again to build the windows, or thread resolved
geometry into a phase defined to run before geometry exists. The second is not
a bigger version of this milestone's work; it is a different layout
architecture.

**The failure is silent and total, which is why the note is loud.** Measured: a
300pt header above a 40-row list at `rowHeight` 28, viewport 112, scrolled to
300 — the rows on screen are 0 through 3 and the rows built are 8 through 16.
Through a real `ScrollView` those nine rows paint at y 224 through 448 under a
content mask of (0, 0) 100x112, so **nothing is drawn where the list is**. Two
`List`s in one `ScrollView` fail the same way by construction, since at most
one of them can start at the content origin. An absolutely-positioned `List`
fails it too — measured: at `.position(.absolute)` with `inset(top: 300)` it
builds the identical rows 8 through 16, since the ambient offset is what drives
the window either way.

**"Layout-contributing" rather than "only child", and the demo is the reason.**
`Sources/MetalUIDemo/main.swift` declares a `Deferred` modal before its `List`
inside the same `ScrollView` and is not in violation: the modal's box is
`.position(.absolute)`, the flow filter removes it from the content node's item
list, and the list's rows still start at y = 0 (measured). A sibling that
occupies flow is what shifts the origin; one that does not is free.

**What it costs if wrong.** If the requirement is quietly violated the list
renders blank, and no assertion in this repo would notice — every windowing
test builds the `List` as the scroller's only child. The pin is
`aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`
(`Tests/MetalUITests/ListTests.swift`), which asserts today's **wrong** answer
on purpose and says so in its own failure message: whoever gives `requestLayout`
a position must delete or invert it. If instead this ruling is wrong in the
other direction — if a cheap correction exists that nobody found — the cost is a
requirement documented on a type that did not need one, which is recoverable by
deleting three paragraphs. The asymmetry is why it was written down rather than
left open.

---

## MP-M — a scroll context on an axis `List` does not stack on falls back to building everything

**The choice.** `visibleRange` windows only when `ScrollContext.axis ==
.vertical`; a horizontal context takes the same escape hatch as no context at
all.

**Reasoning.** `ScrollContext.axis` had **zero production readers** before this,
found by mutation during the whole-branch review, and the consequence was not a
rounding error: `ScrollView(.horizontal) { List { … } }` windowed a column of
rows against a horizontal distance and a viewport *width*. Measured on a 40-row
list at `rowHeight` 28 under `ScrollContext(offset: 240, viewportExtent: 300,
axis: .horizontal)`: rows 6 through 21 were built while rows 0 onward were on
screen. There is no better answer available, either — a `List` stacks on the
block axis by construction, so a horizontal offset selects no subset of its
rows and there is nothing to window *with*. Building everything is what a `List`
outside every `ScrollView` already does (MP-G's hatch), and a vertical list
inside a horizontal scroller — a row of columns — is a real composition rather
than a mistake to be punished.

**What it costs if wrong.** A vertical `List` of many rows inside a horizontal
`ScrollView` builds every row, every frame — the pre-windowing cost, which is
this milestone's whole subject. That is a slow frame rather than a wrong one,
and it is the same trade MP-G already took for a zero `rowHeight`. Pinned by
`aVerticalListInsideAHorizontalScrollViewBuildsEveryRow`, whose second half
asserts the identical numbers on the vertical axis DO window — without that
differential the test would also pass under a mutation that stopped windowing
altogether.

---

## MP-N — `Deferred` escapes the ambient scroll context too, by pushing an ABSENT one

**The choice.** `Deferred.requestLayout` runs its subtree inside
`LayoutPass.withoutScrollContext`, which pushes `nil` onto `Frame`'s scroll-
context stack. A `List` inside a portal therefore builds every row.

**Reasoning, and ruling AP-I already contains it.** AP-I says escaping an
ancestor's clip without escaping its scroll translation "is a half-portal"; the
same sentence applies one phase earlier. `pass.deferred` resets the clip and the
accumulated offset for `prepaint` and `paint`, so a `Deferred` subtree does not
move with the content around it — but nothing reset the layout phase's ambient
context, so a `List` inside the portal was still told how far a scroller it does
not move with had scrolled. Measured at offset 280: the window slid to rows 8
through 15 while paint placed them at 224…420, below a viewport ending at 112 —
the portal's list empties out as the list behind it is scrolled. The layout half
is the counterpart of resetting the *translation*, not of resetting the clip.

**Absent rather than popped, and the distinction is load-bearing.** Popping the
enclosing entry would expose the *next* `ScrollView` out in a nested pair, which
is a different wrong answer; a portal escapes all of them. That is why
`Frame.scrollContextStack` became `[ScrollContext?]` rather than gaining a
pop-and-restore spelling — `pushAbsentScrollContext` is the exact counterpart of
`pushRootClip`, one level pushed and one level popped.

**What it costs if wrong.** A `Deferred { List }` builds every row, which is the
pre-windowing cost again and the right answer for a portal — a portal is not
scrolled, so there is no window to compute. If the reverse were shipped (a
portal inheriting the context) the list silently empties as the page scrolls,
and **nothing in the suite would see it**: `Deferred` contributes no layout node,
so the rects of whatever it does build are byte-identical either way. Pinned by
`aListInsideADeferredIgnoresTheEscapedScrollersOffset`, with the unwrapped list
under the identical context as its differential.
