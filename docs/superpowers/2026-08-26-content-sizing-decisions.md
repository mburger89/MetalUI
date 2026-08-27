# Content sizing — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-26-metalui-content-sizing.md`, in order. Each
says what was decided, why, and what it costs if wrong.

**Ruling IDs here are prefixed `CS-` and are LETTERED, `CS-A`…`CS-L`.** A bare
`CS-3` is therefore a typo, not a citation. `PF-`/`C-` belong to m1a, `FS-` to
flex sizing, `AL-` to alignment, `BM-` to the box model, `WR-` to wrapping,
`EP-` to the element pipeline. A bare `F-n` is ambiguous across three documents
— sweep for stray citations **case-insensitively**, since a `Ruling F-3`
survived two branches' greps for lowercase `ruling`.

## During execution

| # | Ruling | Cost if wrong |
|---|---|---|
| CS-A | **`collectItems` and `flexBaseSize` do not take `LayoutContext` yet.** Task 4 wires the four constant-substituting sites and needs `ctx` at both to recurse; Task 2 does not, and adding a parameter one task early means a task's worth of code where it exists and is unused — this repo's most-repeated bug shape (taxonomy shape 4). Task 2's `layOutChildren` calls both with their existing `rootFontSize:` signature. *(Task 2 did change `collectItems`' `containerSize:` from `SizeD` to `OptionalSizeD`, which CS-D forced and which is not what this ruling is about.)* | A parameter that exists and does nothing reads, from outside, exactly like an implemented one. |
| CS-B | **A predicted test count is a prediction, never a target.** The Task 2 brief predicted 309 → 314; Task 1's fix round had already made it 310, and the task shipped at 318. The measured number wins, always, and a test is never adjusted, added or deleted to reach a predicted one. What *is* load-bearing is the direction: a count that **falls** without a deletion you can name is taxonomy shape 11 — a truncated run — and must be treated as a failure until explained. | A number in a plan quietly becomes an instruction, and someone deletes a real test to hit it. |
| CS-C | **A test that asserts something does NOT trap must run in a subprocess** — `await #expect(processExitsWith: .success) { … }`, matching `usingAnIdAgainstItsOwnTreeDoesNotTrap`. Task 1 shipped `layoutClearsTheGuardWhenItFinishes` with a bare `setStyle` call after `computeLayout`; mutating the guard it protected killed the test process with signal 5, printing **no summary line at all** and destroying every other test's result (taxonomy shape 11). In-process, the mutation's diagnosis is "the suite vanished"; in a subprocess it is one red test. `#expect(processExitsWith:)` bodies are non-capturing, so each call site is written out in full rather than sharing a helper. | The mutation that proves a guard works also destroys the evidence that anything else does. |
| CS-D | **An indefinite axis is `nil`. Never `.infinity`, never a large finite stand-in.** `measureNode`'s first version probed an unbounded axis with `.infinity`; `layOutChildren` then did arithmetic on it. Three ten-line containers — a `flex-grow: 1` child, a `width: 50%` child, and a percentage `gap` — each drove §9.7's freeze loop past its pass cap and `assertionFailure`d the **process**, signal 5, no summary line. `inf - inf` and `inf * 0` are NaN, every comparison against a NaN is false, so no item registers a violation and nothing ever freezes. The fix is CSS's own rule **for the definite-vs-indefinite question**: percentages against an indefinite basis are unresolvable and already resolve to `nil` in `resolveDimension`, and §9.4 step 8 / §9.4.8's single-line clause are keyed on the word *definite* in the spec itself. **What replaces §9.7 is a substitute, not a citation** — every item keeps its hypothetical main size, which equals §9.9.1's answer only while the chosen flex fraction is ≤ 0. See the carried risk below; that difference is the finding, and confusing the two halves of this ruling is how it would get lost. The one place a missing extent still becomes a number is `collectLines`' budget, where `.infinity` is a *comparison bound* and no arithmetic touches it. | The engine kills the process on a shape as ordinary as a `flex-grow` child — and in a release build, where the assertion is compiled out, silently returns NaN rects instead. |
| CS-E | **The commit that corrects stale claims is the likeliest place to introduce one.** Second occurrence on this project: Task 2's fixup deleted two false comments and introduced a third — a justification citing "`measureNode` probes with `.infinity`", which that same commit had just made false. The element-pipeline milestone did it twice. The rule is not "do not correct"; it is that a correction round gets the same mutation-and-measurement treatment as new code, because it reads as strictly safe and is not. | A correction round ships a fresh falsehood under the cover of removing two, and it inherits the credibility of the fix around it. |
| CS-F | **`LayoutContext.MeasureKey` must include `containingBlockWidth`, not only `known`/`available`.** Task 3's first cut (transcribed faithfully from the plan's spec text) omitted it. `measureNode` passes `containingBlockWidth` straight to `layOutChildren`, where it is the basis for the container's own percentage padding/border and so changes the border box `measureNode` returns — so the same node measured once against an indefinite containing block (a parent's speculative measure) and once against a definite one (real placement) shared a cache entry and a **hit returned a wrong answer, not a recompute**, falsifying the key's own "never a wrong answer" docstring. Reviewer-measured: a container with `10%` padding on all four edges, `containingBlockWidth: 100` then `400` in the same `LayoutContext`, gave `220×220` both times where the second call's correct answer is `280×280`. **Becomes reachable in Task 4**: a node measured once during a parent's speculative measure (`containingBlockWidth: nil`) and again during placement (a real width) is exactly this shape. Fixed by adding the field to `MeasureKey`'s `==`/`hash` (by `bitPattern`, like the other `Double`s); guarded by `aCacheHitRespectsTheContainingBlockWidth` in `MeasureCacheTests.swift`, which reddens against the pre-fix key with the numbers above. | A cache hit silently returns the wrong border box for any node whose percentage padding/border is measured against two different containing-block widths in one run — invisible until Task 4 wires real recursive measurement, at which point it is every such node. |
| CS-G | **Spec §2's headline scope was unreachable, and the plan could not have delivered it.** A container could not distinguish min-content from max-content: the query died at `definiteExtent` inside `measureNode`, and `AvailableSpaceSize` existed nowhere below that line — so changing `FlexBaseSize`'s hardcoded `.maxContent`, which is what the plan told the wiring task to do, would have fixed nothing. Propagation is **three** sites, and the third had been named by nobody: `collectLines`' budget, because under `.minContent` the budget is zero and each item lines alone (§9.9.1.1), which is a wrapping fact no base-size work reaches. Given its own task, sequenced **before** the re-baseline. | The re-baseline's golden diff acquires two independent causes; and the failure is silent, because every fixture is a pixel-sized empty div where the two modes coincide, so the live-WebKit gate stays green either way. |
| CS-H | **The query is threaded as an `IntrinsicQuery` (a per-axis `IntrinsicMode?`), not as an `AvailableSpaceSize`.** Task 4's brief left the choice open. `AvailableSpaceSize` can also be `.definite`, so threading it below `measureNode` would carry the definite extents a **second** time alongside `containerSize`, with nothing keeping the two agreed and a precedence rule at every consumer. `IntrinsicMode` cannot express `.definite` at all, and `IntrinsicQuery(known:available:)` establishes the invariant the consumers rely on — **an axis has a mode iff that axis of the probe is `nil`** — so each consuming site reads "the extent if there is one, otherwise the question" with no third case. `contentBox` maps `nil` to `nil` per axis, so the invariant survives into the content box. **No `MeasureKey` field**: the query is a pure function of `known` and `available`, both already in the key with `.minContent`/`.maxContent` distinct — the rule recorded at the key is that if that constructor ever reads anything else, that thing belongs in the key. **Review-verified at every consumer, and it buys a proof:** `containerCross == nil` and "the cross mode is non-nil" are the same condition, so `flexBaseSize`'s cross-axis `?? .maxContent` is unreachable — measured, `fatalError()` there leaves the suite green. It stays as a total-function default and says so. | Two sources of truth for a container's extent, and a stale cache entry the moment the query stops being derived from the key's own fields. |

| CS-I | **An `auto` root axis keeps the space it was offered; only the case with NO offered extent measures.** Spec §1 names `resolveRootSize`'s `auto` axis as one of the four sites, and the constant it names — "falls back to the offered space" — is really **two** constants: the offered extent when there is one, and a hardcoded 0 when there is not. Only the second is replaced. **The justification is `computeLayout`'s contract**: the engine's root is not a block box in a CSS initial containing block, it is a node whose size its host supplies, and `.definite(w)` on an axis of `available:` is the host saying "this axis is w". A browser has no equivalent — its root's containing block is the viewport by construction and it is never *told* a size. **Not EP-5**, whose own text ends "the WebKit corpus stays the oracle for the engine; this ruling binds everything above it" — `resolveRootSize` is inside the engine, and citing EP-5 here reads it past its boundary and weakens it. The evidence is behavioural: CSS's answer (WebKit **800 × 40** for an 800×600 viewport holding one 100×40 child) was implemented and reverted because it reddens **six** element-pipeline and frame-loop tests, all because a `Row { … }` rendered into a `Frame` declares no height and the window root would collapse. **The engine can still express CSS's answer** — a host offering `.maxContent` on the block axis takes the measuring branch and gets 40 — so this is an interpretation of one call shape, not a disagreement with WebKit. Recorded as CLAUDE.md's **fourth** known divergence. | The framework's root silently stops filling its window, and the six tests that catch it are in a different target from the change. Conversely, if this is wrong, a host that wants a shrink-wrapped root must ask with `.maxContent` rather than with a definite extent — which is expressible, but undiscoverable from the signature. |
| CS-J | **Only a literal `auto` cross size is measured; an unresolvable percentage stays 0.** CSS says a percentage against an indefinite basis behaves as `auto`, which would put it through `measureNode` too. WebKit does not: a `height: 50%` child of an auto-height flex item measures **0**, not its content (probed). So `ownCross` switches on the declaration, not on whether `resolveNodeSize` returned something. The same rule already governs `resolveRootSize` (a percentage root size keeps the offered-space fallback, spec §2). | Percentage cross sizes silently acquire content sizing, moving every nested percentage layout away from WebKit — and no fixture in the corpus would notice, because a percentage cross size against a *definite* container resolves and never reaches this branch. |
| CS-K | **The hypothetical cross size is measured at max-content, with the item's HYPOTHETICAL main size as `known` — three separate choices, each probed.** (1) `known` main is `hypothetical`, not `base`: §9.4 step 7 says "perform layout with the **used** main size", which at that point is the base size already clamped by the item's own main min/max. The two differ exactly when a min/max binds. (2) The cross axis is offered `.maxContent` and never `.definite(containerCross)` — `measureNode` turns a definite available extent into the measured node's OWN extent (its `probe`), so offering the container's cross extent would make the item that tall and let its children's cross percentages resolve against it, which CS-J's probe shows WebKit does not do. (3) `.maxContent` rather than fit-content: an item whose content is 150 tall inside an 80-tall row measures **150** in WebKit and overflows. The mode is hardcoded rather than taken from `intrinsic`, for the same reason §4.5's probe is — the hypothetical cross size is a property of the item, not of the question the container was asked, and ruling CS-H's lesson is that a fourth propagation site would need a fourth guard test. | (2) is the one that fails silently: the returned border box would still be items-derived and correct, and only the *percentages inside the measured subtree* would be resolved against a fiction. No existing test has a percentage inside an auto-cross item. |
| CS-L | **`LayoutContext.maxDepth` stays 64, and the measurement behind the number is now stated as a DEBUG figure.** Wiring made `measureNode` recurse for real: one tree level costs `measureNode` → `layOutChildren` → `collectItems` → its item closure → `flexBaseSize` → `measureNode` on top of `placeNode` → `positionItems`, and the stack ceilings fell ~4×. `layingOutATreeDeeperThanTheLimitTraps` went red on the wiring commit — SIGBUS, empty stderr, the stack winning before the guard could name anything. **The first fix was to drop the constant to 16, and that was wrong.** It bisected on a Swift Testing exit-test task and on an explicit 256 KB thread, and **neither is a stack this framework runs on** — `Frame.computeRootLayout` is `@MainActor`, so the floor is a 1 MB iOS main thread. A test harness was setting a production capability limit, `precondition` is live in `-O`, and `Column { Row { Box { … } } }` reaches 17 trivially: 16 was a shipping crash that would have reported "the child lists contain a cycle" for a tree with no cycle. The fix is to size the *test's* stack instead — `layingOutATreeDeeperThanTheLimitTraps` now runs its layout on an explicit 4 MB `Thread` — and to keep 64, which is 64/107 against the smallest **real** stack's debug ceiling: the same 0.60 margin the original 64 decision used. Measured ceilings (bisected, this branch): 256 KB **27 debug / 167 release**, 1 MB **107 / 654**; per level ~9,800 B debug and ~1,600 B release, i.e. **release is ~6× cheaper**. Quoting only the debug figure is how the next person re-measures in `-O`, gets a sixth of it, and concludes the table is wrong. | A guard whose ceiling is set by whichever stack the test harness happens to hand over. In one direction that is an unattributed SIGBUS in production; in the other — the direction this actually went — it is a `precondition` firing on an ordinary three-deep UI. |

## EP-6 is unblocked — recorded, not re-decided

**This is the milestone's stated purpose, and it was about to go unrecorded at
the moment it was achieved.** The element-pipeline decisions doc's ruling EP-6
keeps `Column`/`Row` on CSS's `stretch` cross-axis default, and its reason is a
mechanism rather than a preference:

> an `auto` cross size resolves to **0** in this engine … so a centred child
> with no explicit cross size would measure 0 and **paint nothing at all** …
> EP-5's stack half is *blocked on* recursive subtree measurement: it is a
> prerequisite, not an application.

**Task 5 supplied that prerequisite.** An `auto` cross size now measures its
subtree (`collectItems`' `ownCross`), so a centred child with content no longer
paints nothing. EP-6's blocking reason is gone and the stack-default question —
SwiftUI centres, CSS stretches — is open for a deliberate re-decision.

**It is deliberately not re-decided here.** Changing `Column`/`Row`'s default is
an API change in `MetalUI`, not an engine change, and it belongs with whoever
takes EP-5's stack half; content sizing's whole scope was the prerequisite. Two
things a re-decision must not assume:

- **A childless `Box` still measures 0.** The demo's sidebar boxes have no
  children, so they would paint nothing under `center` today exactly as they
  would have before. What changed is that a child *with content* no longer
  does — the default is now a choice rather than a workaround.
- **A leaf still has no production `MeasureFunction`** (`newLeaf` has no caller
  in `Sources/`), so "content" means "a subtree of nodes" until M2, not text.

Three places paraphrased EP-6 as "keeps `Column`/`Row` on stretch so a root
fills its surface", which is not what it says and is not why: `FlexEngine.swift`'s
`resolveRootSize`, CLAUDE.md's fourth divergence, and ruling CS-I. All three are
corrected, and `Sources/MetalUIDemo/main.swift` — the only citation in shipping
code — now records that the reason expired.

**A letter collision, resolved here rather than left to a grep.** Task 3's
report and commit called the `MeasureKey` ruling **CS-E**; the branch log
(`progress.md`) had already spent `CS-E` on the correction-round practice and
called the key ruling **CS-F**. This table now follows the branch log — the key
ruling is **CS-F** — and the two rulings that lived only in the branch log
(**CS-E**, **CS-G**) are rows above, so every letter A-H names exactly one
thing. **A stray `CS-E` citing the cache key means CS-F.** Sweep
case-insensitively; a `Ruling F-3` once survived two branches' greps.

**CS-D was found by a reviewer's ten-line probe, not by the 318-test suite**, and
the reason is worth keeping: every test in `MeasureNodeTests.swift` at the time
sized its children in pixels with no gap and no margin, which is the one
configuration for which `.infinity` and "indefinite" agree. The task's own report
had even written the failure down as a limitation — "reports an infinite content
size … no test here can see it" — which was wrong in both halves and is exactly
taxonomy shape 10: a prediction about measurement, dressed as a fact about the
code, that tells the reader not to look.

## The depth guard's ceiling — a measurement, not a ruling

**Superseded by ruling CS-L above; kept for the history, which is the part that
repeated.** This section recorded `maxDepth` going 256 → 64 after a bisection
found 196 levels laying out and 197 dying with SIGBUS on a Swift Testing
exit-test task, ~110 on an explicit 256 KB thread, and 256 reached only on the
main thread — so at 256 the guard fired on the roomiest stack alone.

Content sizing invalidated every number in it. The current ceilings, and the
current constant, are in ruling CS-L. What did **not** change is the lesson
underneath, and it caught this branch out twice in opposite directions:

> **The lapse was invisible to the tests that existed**, because both depth
> tests entered the context by hand and neither ever ran a real recursion.

`layingOutATreeDeeperThanTheLimitTraps` was written to close that, and it
worked — it is what caught the wiring. But it laid out on whatever stack the
harness handed over, so the *fix* it prompted was to shrink the production
limit to fit the harness. It now sizes its own thread. **A depth guard is a
statement about the stacks the framework runs on, and a test that measures the
harness will keep proposing the harness's answer.**

## The re-baseline — what moved, and the finding that the diff is empty

**Every one of the 57 goldens is byte-identical after
`METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens`, and
that was inevitable rather than informative.** A golden is browser output;
regenerating re-drives WebKit over an unchanged fixture, so an engine change
cannot move one. `git diff --stat Tests/MetalUILayoutTests/Golden` is empty and
would have been empty for any engine.

The plan and the design spec both say "read the golden diff as evidence" (spec
§5.1: *"A golden that moves exercised auto sizing; one that does not, did
not"*). **That instruction cannot be followed as written**, and this is the
same shape the practices doc calls taxonomy 10: a prediction about what
measurement will show, which tells the reader where to look and points at the
wrong place. The evidence that exists is the **engine-vs-golden comparison**
tests in `FlexEngineTests`, `AlignmentTests`, `BoxModelTests` and
`WrappingTests`, which build the fixture's tree by hand, run `computeLayout`,
and compare against the committed golden. Those are what would redden if the
engine moved away from WebKit.

### Fixtures whose engine-vs-golden comparison MOVED: 0 of 57

None. The wiring was run against the suite **before** regenerating, exactly as
the plan asks, and no golden comparison recorded an issue. The three tests that
did fail are hand-written and are listed below.

### Fixtures that did NOT move: all 57

This is the map of what the corpus never covered, and it is uniform enough to
give by mechanism rather than one line each. Both groups fail to reach the new
code for reasons visible in the fixture source, not for reasons discovered
afterwards.

**Group A — 53 fixtures, two levels deep: a root and empty leaf children.**

`flex_column_grow_with_max`, `flex_column_justify_center`,
`flex_column_padding_asymmetric`, `flex_column_reverse_justify_end`,
`flex_column_reverse_margins`, `flex_column_three_fixed`,
`flex_percent_child_in_padded`, `flex_percent_padding_nonsquare`,
`flex_row_align_center`, `flex_row_align_end_with_self`,
`flex_row_explicit_min`, `flex_row_fixed_and_grow`,
`flex_row_fractional_grow`, `flex_row_fractional_grow_clamped`,
`flex_row_fractional_shrink`, `flex_row_gap`, `flex_row_grow_nonzero_basis`,
`flex_row_grow_space_between_margins`, `flex_row_grow_uneven`,
`flex_row_grow_with_max`, `flex_row_justify_around`, `flex_row_justify_between`,
`flex_row_justify_between_gap`, `flex_row_justify_evenly`,
`flex_row_margin_with_grow`, `flex_row_margins`, `flex_row_padding_border`,
`flex_row_percent_basis`, `flex_row_reverse`, `flex_row_reverse_margins`,
`flex_row_reverse_stretch`, `flex_row_seven_equal`, `flex_row_shrink`,
`flex_row_shrink_to_zero`, `flex_row_stretch_min_height_margins`,
`flex_row_stretch_mixed`, `flex_row_stretch_with_margins`,
`flex_row_three_fixed`, `flex_wrap_align_content_between`,
`flex_wrap_align_content_center`, `flex_wrap_align_content_stretch`,
`flex_wrap_align_items_self`, `flex_wrap_column_reverse`,
`flex_wrap_grow_and_shrink`, `flex_wrap_justify_between`,
`flex_wrap_main_sizing`, `flex_wrap_reverse`,
`flex_wrap_reverse_align_content_end`, `flex_wrap_reverse_row_reverse`,
`flex_wrap_row_reverse_gap_margin`, `flex_wrap_stretch_auto_cross`,
`flex_wrap_uneven`, `flex_wrap_with_margins_and_padding`

Every child is an empty `div`. Its content size is 0, and 0 is exactly the
constant each site substituted, so all four sites are **reached and return the
same number**:

- site 1 (`flexBaseSize` step 3) — reached only by a child with no definite
  `flex-basis` and no definite main size, and it returns 0 for an empty div,
  as the old `else { return 0 }` did;
- site 2 (§4.5 automatic minimum) — the content suggestion is now `0` where it
  was `nil`, which `clamp` and §9.7.4.d's `max(0, …)` cannot distinguish for any
  non-negative size;
- site 3 (`auto` cross) — `flex_wrap_stretch_auto_cross` is the one fixture
  built around this, and its `.b`/`.d`/`.f` are still empty divs: measured cross
  0, then stretched by the line exactly as before;
- site 4 (`resolveRootSize`) — **no fixture root has an `auto` axis at all**;
  all 57 declare both a `width` and a `height`. That is a convention, not
  something the harness enforces: `FixtureHygieneError` checks only that the
  root box lands at (0, 0). A fixture *could* declare an `auto` root — and it
  would fail, because it would encode ruling CS-I's divergence. The corpus
  deliberately holds no such fixture, on the same footing as WebKit's flex
  sub-one clause (CLAUDE.md divergence 2), and the divergence is pinned by a
  named test instead.

**Group B — 4 fixtures, three levels deep, with a real nested container.**

`flex_nested_padding`, `flex_nested_percent_padding`,
`flex_wrap_align_content_around_evenly`, `flex_wrap_nested_percent_padding`

These are the only fixtures where a *container* is a flex item, and they still
do not reach sites 1 or 3: `.mid`, `#around` and `#evenly` each declare **both**
a `width` and a `height`, so `flexBaseSize` returns at its step-2 definite main
size and `ownCross` takes `resolveNodeSize`'s declared value. Site 2 does
compute a real content-based floor for them for the first time, and it binds on
none of the four — nothing in these fixtures overflows its container, so no item
shrinks far enough to meet a floor.

### The mutations, measured

Design §5.2 lists five mutations that must redden. The two the re-baseline owns:

All figures `--no-parallel`, on 334 tests.

| mutation | reddens | golden comparisons among them |
|---|---|---|
| `measureNode` returns 0 for a container (the pre-milestone bug, restored) | **15** | **0** |
| `.minContent` / `.maxContent` swapped at the two sites that name them | **6** | **2** |

**"Returns 0 for a container" has two readings, and both were measured**, since
the weaker one is the honest test of the guards: an unconditional `SizeD(0, 0)`
and a `known`-respecting `SizeD(known.width ?? 0, known.height ?? 0)` redden the
**same 15 tests**, differing by a single expectation (28 issues vs 27). The
`known`-respecting spelling is what a real regression would look like, and it is
caught just as well.

**`--no-parallel` is load-bearing on these numbers.** The parallel runner drops
failing-test *names* from the log when failures print concurrently: the
composite mode swap reported **3** tests in a parallel run and **6** under
`--no-parallel`, with an identical issue count both times. The summary line's
issue count is the stable number; a test count scraped from the log body is not
— taxonomy shape 11 one level in, since the summary line was right and the
thing read instead of it was wrong.

The first is the important number and the important zero. Fifteen tests see the
bug this milestone exists to fix and **not one of them is a fixture** —
`autoCrossNestedContainerMeasuresItsLineLikeWebKit`,
`aContainerItemIsFlooredByItsChildrensWidth`,
`aContainerItemsBaseSizeComesFromItsChildren` and
`anAutoRootWithNoOfferedExtentMeasuresItsContent` cover one site each, and all
four are hand-written. The plan predicted "the auto-cross **fixture** reddens
specifically"; there is no auto-cross fixture, which is the whole content of
the non-mover list above.

The second is broken out per site in the carried risk below, where the surprise
is: the §4.5 half **does** redden two goldens, which the carried risk had said
was impossible. The composite is the exact **union** of its two halves — there
is no masking effect on this branch, and the first version of this document
claimed there was.

### What that list is for

**Task 6's fixture list is the complement of the two groups above**, and the
gaps are now named rather than guessed. In rough order of what the engine can
get wrong without anything noticing:

1. a nested container with an **`auto` cross size** — the divergence this
   milestone is named for. Covered today only by
   `autoCrossNestedContainerMeasuresItsLineLikeWebKit`, hand-written.
2. a nested container **shrinking onto its `min-width: auto` floor**. WebKit
   numbers already measured: `#root { width: 160px }`, `.a { flex: 0 1 200px }`
   holding a 120px child, `.b { width: 120px }` gives `a=120, b=40`; with
   `min-width: 0` on `.a` it gives `a=100, b=60`. Hand-written as
   `aContainerItemIsFlooredByItsChildrensWidth`.
3. a nested container with **`auto` on its main axis** (site 1), which no
   fixture and no committed test currently exercises through `computeLayout`.
4. **auto height at two levels**, per spec §5.2.
5. a `wrap` container whose **own reported size** differs between the two
   queries. Note this is narrower than it was first written: §4.5's probe half
   of the mode swap *does* redden two goldens (Group B), so what is missing is
   specifically `flexBaseSize`'s half — see the carried risk.
6. a **percentage cross size inside an auto-cross item**, which ruling CS-J
   decides against measuring and which nothing pins but a probe.

### The hand-written tests that DID move

| test | before | after | site |
|---|---|---|---|
| `autoCrossNestedContainerCollapsesItsLineUnlikeWebKit` → renamed `…MeasuresItsLineLikeWebKit` | `x` 120×**0**, `y` at y=**0** | `x` 120×**50**, `y` at y=**50** — WebKit's own numbers | 3 |
| `autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot` | root 800×600 | **unchanged**, after ruling CS-I reverted the CSS answer | 4 |
| `layingOutATreeDeeperThanTheLimitTraps` | green at `maxDepth = 64`, laying out on the harness's own stack | red — SIGBUS before the guard could print; green again at 64 once the layout runs on an explicit 4 MB `Thread` | ruling CS-L |

Three tests were added and none deleted: `anAutoRootWithNoOfferedExtentMeasuresItsContent`,
`aContainerItemsBaseSizeComesFromItsChildren`,
`aContainerItemIsFlooredByItsChildrensWidth`. Suite: **331 → 334**, and the
direction is the one ruling CS-B cares about.

**Two tests were renamed, and a rename is a change a reviewer tracks even when
no number moves.** `autoCrossNestedContainerCollapsesItsLineUnlikeWebKit` →
`…MeasuresItsLineLikeWebKit` is in the table above because its numbers did
move. `FlexBaseSizeTests.autoBasisWithNoMeasureFunctionIsZero` →
`autoBasisWithNoMeasureFunctionOrChildrenIsZero` is **not**, because its answer
is still 0 — but the *reason* changed from "there is no measure function" to
"measuring a childless node returns its padding and border", and the old name
asserted the old reason. Its cross-reference in `FlexEngineTests` was missed on
the first pass and is fixed.
## The cost of measuring — the milestone's largest unrecorded consequence

Not a defect and not a ruling: a measurement, recorded next to CS-L because the
two share a cause. §4.5's automatic minimum probes **every** item
(`min-width: auto` is CSS's default), and an `auto`-cross item probes again, so
a container's children are each measured up to three times per layout.

Branching trees, `depth` levels of `branch` children each, interior nodes
auto-sized flex containers and leaves 10×10. "Before" is the same engine with
`measureNode` returning early, i.e. the pre-milestone cost profile:

| tree | nodes | debug before | debug after | release before | release after |
|---|---|---|---|---|---|
| depth 12, branch 2 | 8,191 | 72.8 ms | **372.0 ms** | 10.2 ms | **45.0 ms** |
| depth 10, branch 3 | 88,573 | 708.4 ms | **3,504.4 ms** | 96.3 ms | **456.9 ms** |

**Complexity is unchanged — the constant factor is ~4.9×.** Per node: ~8 µs
before and ~40 µs after in debug, ~1.2 µs and ~5.3 µs in release, and each is
flat from 8 k to 88 k nodes, which is the evidence the memo cache is doing its
job. Design §3.3 predicted "~700× at depth 6" without memoization; the cache
turns that into a constant multiplier instead of a depth-exponential one, which
is exactly what it was specified to do.

**The single-chain measurement taken during the task showed linearity correctly
and could not have shown this**, because a chain has one child per level and
the three probes per item collapse onto the same few cache keys. A branching
tree is what makes the per-item probe count visible. Whoever optimises this
should start there: the §4.5 probe is the one that fires unconditionally.

Release figures are ~8× faster in absolute terms but the ratio is the same, so
quoting only the debug numbers would overstate the absolute cost and understate
nothing.

## Carried risk

- **Under intrinsic sizing the engine skips §9.7 where CSS runs §9.9.1, and
  §9.9.1 applies `flex-grow`.** This is the one place the engine is knowingly
  not CSS after CS-D, and it is the item Task 4 inherits.

  The spec's own worked example, measured against this engine
  (`flex-basis: 100px`, `min-width: 0`, a `MeasureFunction` returning 200 wide,
  measured at `.maxContent`):

  | | engine | CSS §9.9.1 |
  |---|---|---|
  | `flex-grow: 0` | 100 | 100 |
  | `flex-grow: 1` | **100** | **200** |

  CSS Flexbox §9.9.1.1 says it outright: *"when the item is `flex-grow: 0`, the
  flex container is 100px wide, but when the item is `flex-grow: 1` or higher,
  the flex container (and flex item) is 200px wide."* The mechanism is that CSS
  does not run §9.7 under intrinsic sizing at all — it runs §9.9.1, which sums
  each item's max-content **contribution** and *does* let a flex fraction grow
  them. `layOutChildren`'s "keep the hypothetical main size" substitute equals
  that only while every item's max-content contribution is at most its outer
  flex base size, i.e. while the chosen flex fraction is ≤ 0.

  **Unreachable in production by a nameable mechanism, not by a milestone:**
  `flexBaseSize`'s content branch is the only route to a max-content
  contribution larger than the base size, and it needs `tree.measure(item)` to
  be non-nil — `newLeaf` is the only thing that populates it and has no
  production caller. It is reachable from a test today (the table above is
  one), and Task 4 is what puts it in the path.

  **Task 4 landed and left it exactly where it was — re-measured, not
  assumed.** The propagation changes what the container *asks*; §9.7's
  indefinite-main branch, which is where the divergence lives, is untouched.
  Re-running the worked example through `measureNode` after the change gives
  `grow: 0 -> 100` and `grow: 1 -> 100` under `.maxContent`, the same two
  numbers as before, and `100`/`100` under `.minContent` as well — a definite
  `flex-basis: 100px` wins at `flexBaseSize`'s **first** branch, so the content
  branch this task rewired is never reached on this shape at all. Neither
  better nor worse; §9.9.1's growth rule remains unimplemented and deliberate.

  **Task 5 wired the four sites and left it where it was too — re-measured
  again, and the second measurement is the interesting one.** The four numbers
  above are unchanged (`100` for both grow values at both queries). Respelling
  the same example with **`flex-basis: auto`**, so that the rewired content
  branch is the one that runs, gives **200 for both `flex-grow: 0` and
  `flex-grow: 1`** — the item's max-content contribution *is* its outer flex
  base size there, so the chosen flex fraction is ≤ 0 and the substitute and
  §9.9.1 agree by construction. **Wiring therefore did not make the divergence
  reachable in production; it is still gated on the same mechanism**, a
  `MeasureFunction` on a leaf, which `newLeaf` alone attaches and nothing in
  `Sources/` calls. A *container* item reaches `flexBaseSize`'s content branch
  now, but its max-content contribution is what the branch returns as the base
  size, so the two can never disagree for one. That is a narrower statement
  than "unreachable", and it is the one the measurement supports.

- ~~**`measureNode` cannot tell `.minContent` from `.maxContent` for a
  container.**~~ **Closed by Task 4** (ruling CS-G, CS-H). The two still leave
  the axis indefinite — `containerSize` cannot carry the difference and does
  not try to; the question travels beside it as an `IntrinsicQuery` and lands
  at `flexBaseSize`'s content branch and `collectLines`' budget.
  `IntrinsicModeTests.swift` guards the **three** sites independently — the
  main-axis literal, the cross-axis fallback and the line budget each redden
  exactly one test when reverted alone. It was two until review: the
  cross-axis edit shipped wired but unguarded, reverting it reddened 0 of 330,
  and the fix's own doc comment claimed coverage of it. **A wired-but-unguarded
  edit is not taxonomy shape 4** — shape 4 is a silent no-op, and this was a
  wrong answer nobody could see, which is worse. The practices doc's criterion
  is observability, and it was observable at exactly the level of the two
  committed tests: a column container asked `.minContent` in its cross axis,
  with `min-height: 0` to switch off §4.5's own max-content probe. Design §5.2's "`.minContent` and `.maxContent` swapped
  at a call site" is now a mutation that *can* redden something.

  **The second half of this risk — "it still cannot redden a fixture, because
  every fixture in the corpus is a pixel-sized empty div for which the two
  modes coincide" — is FALSE after the wiring, and was measured rather than
  re-asserted.** It is the third claim of this shape on this branch. Swapping
  the modes at **`collectItems`' §4.5 probe** reddens `wrap_nested_percent_padding`
  and `wrap_align_content_around_evenly` — two real golden comparisons — because
  the probed item is a **nested `wrap` container**, whose min-content width
  (each child on its own line) and max-content width (all on one) genuinely
  differ, and §4.5's floor clamps the `hypotheticalMainSize` that
  `collectLines` then breaks on. An empty div cannot tell the modes apart; a
  container can, and Group B put four of them in the corpus before this
  milestone existed.

  Measured on 334 tests, `--no-parallel`, each site reverted alone:

  | mutation | reddens | issues | of which golden comparisons |
  |---|---|---|---|
  | §4.5 probe modes swapped | 4 | 20 | **2** (`wrapNestedPercentPaddingMatchesWebKit`, `wrapAlignContentAroundAndEvenlyMatchWebKit`) |
  | `flexBaseSize`'s main-axis `?? .maxContent` → `.minContent` | 2 | 2 | 0 |
  | both together | **6** | **22** | **2** — the exact union |

  **There is no masking effect, and the first version of this paragraph claimed
  one.** It said the composite was "weaker than either half" and named
  `aContainersIntrinsicQueryReachesItsChildren` and
  `automaticMinimumSizeUsesContentSizeNotFlexBasis` as going green again when
  both sites are wrong. Both are **red** in the composite. The composite is the
  exact union — 4 + 2 = 6 tests, 20 + 2 = 22 issues, 2 goldens — and the 22 was
  in the original data, where it should have been read as the union and was
  not.

  **The cause was a bad measurement method, and it is worth more than the
  claim was.** The failing-test count was extracted by grepping the *parallel*
  streaming log, which drops names when failures print concurrently: the same
  mutation reported **3** tests in one run and **6** under `--no-parallel`,
  with the issue count identical in both. Every number in this document's
  mutation tables is now a `--no-parallel` measurement. The taxonomy's shape 11
  says to read the summary line rather than the exit status; this is the
  sharper form — **the summary line's issue count is the stable number, and a
  test count scraped from the log body is not**.

  Reverting sites one at a time is still the right practice, because a
  composite *can* mask. It simply does not here, and there is no evidence for
  it on this branch.

  What still has no fixture is a container whose **own reported size** differs
  between the two queries — the `flexBaseSize` row above, 0 goldens. That is
  item 5 on Task 6's list.
- **`measureNode`'s purity is not enforced by the type system.** A `setLayout`
  anywhere beneath it returns the right size and passes every golden;
  `measuringWritesNoLayout` is the only thing that sees it, and it asserts on
  the stored rects of *every* node in the subtree, not just the container's.
- **`contentMain` is a fourth independent re-derivation** of "outer main sizes
  with gaps between", after `lineContentSize`, `positionItems`' `content` and
  `ResolveFlexibleLengths`' `totalGap`. Carried forward from FS's and AL's own
  carried-risk sections, which now say so.
- **`ResolveFlexibleLengths`' pass cap is reachable without a bug in
  §9.7.4.e** — hand it a non-finite `containerMain` and nothing freezes. CS-D
  closed the one caller that did; the comment and the assertion message now name
  the mechanism, and in a release build that path returns NaN silently.
- **Two guarantees still lapse under plausible CI configurations** — the ABI
  probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is
  the only live-WebKit consumer. Both must be required, non-gateable jobs.
