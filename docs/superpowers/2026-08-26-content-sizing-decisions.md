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

| CS-I | **An `auto` root axis keeps the space it was offered; only the case with NO offered extent measures.** Spec §1 lists `resolveRootSize`'s `auto` axis as one of the four constant-substituting sites, and the constant it names — "falls back to the offered space" — turns out to be **two** constants: the offered extent when there is one, and a hardcoded 0 when there is not. Only the second is replaced. CSS's answer for the first was implemented and measured before being reverted: a block-level root fills its inline axis and shrink-wraps its block axis, WebKit gives **800 × 40** for an 800×600 viewport holding one 100×40 child, and taking that answer reddened **six** element-pipeline and frame-loop tests (`paddingEdgesAreNotTransposed`, `marginEdgesAreNotTransposed`, `alignItemsAndAlignSelfBothReachTheEngine`, `resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize`, `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows`, and one more in the same file) — all because a `Row { … }` rendered into a `Frame` declares no height and the window's root would collapse. Ruling **EP-5** (SwiftUI's answer over CSS's) and **EP-6** (`Column`/`Row` keep `stretch` so a root fills its surface) are the governing rulings, and `computeLayout`'s `available:` is a window rather than a viewport. Recorded as CLAUDE.md's **fourth** known divergence, with WebKit's numbers. | The framework's root silently stops filling its window, and the six tests that catch it are in a different target from the change. Conversely, if this ruling is wrong, an app that *wants* a shrink-wrapped root has no way to ask for one — the workaround is an explicit size, which every fixture already uses. |
| CS-J | **Only a literal `auto` cross size is measured; an unresolvable percentage stays 0.** CSS says a percentage against an indefinite basis behaves as `auto`, which would put it through `measureNode` too. WebKit does not: a `height: 50%` child of an auto-height flex item measures **0**, not its content (probed). So `ownCross` switches on the declaration, not on whether `resolveNodeSize` returned something. The same rule already governs `resolveRootSize` (a percentage root size keeps the offered-space fallback, spec §2). | Percentage cross sizes silently acquire content sizing, moving every nested percentage layout away from WebKit — and no fixture in the corpus would notice, because a percentage cross size against a *definite* container resolves and never reaches this branch. |
| CS-K | **The hypothetical cross size is measured at max-content, with the item's HYPOTHETICAL main size as `known` — three separate choices, each probed.** (1) `known` main is `hypothetical`, not `base`: §9.4 step 7 says "perform layout with the **used** main size", which at that point is the base size already clamped by the item's own main min/max. The two differ exactly when a min/max binds. (2) The cross axis is offered `.maxContent` and never `.definite(containerCross)` — `measureNode` turns a definite available extent into the measured node's OWN extent (its `probe`), so offering the container's cross extent would make the item that tall and let its children's cross percentages resolve against it, which CS-J's probe shows WebKit does not do. (3) `.maxContent` rather than fit-content: an item whose content is 150 tall inside an 80-tall row measures **150** in WebKit and overflows. The mode is hardcoded rather than taken from `intrinsic`, for the same reason §4.5's probe is — the hypothetical cross size is a property of the item, not of the question the container was asked, and ruling CS-H's lesson is that a fourth propagation site would need a fourth guard test. | (2) is the one that fails silently: the returned border box would still be items-derived and correct, and only the *percentages inside the measured subtree* would be resolved against a fiction. No existing test has a percentage inside an auto-cross item. |
| CS-L | **`LayoutContext.maxDepth` falls from 64 to 16, and the number is a re-measurement rather than a decision.** Wiring made `measureNode` recurse for real, and one tree level now costs `measureNode` → `layOutChildren` → `collectItems` → its item closure → `flexBaseSize` → `measureNode` on top of `placeNode` → `positionItems`. Bisected with the constant raised out of the way: a **256 KB thread reaches 26 levels and SIGBUSes at 27** (was ~110), a Swift Testing task reaches **53 and dies at 54** (was 196), an 8 MB thread clears 400. `layingOutATreeDeeperThanTheLimitTraps` went RED on the wiring commit — the stack won and the guard never printed — which is exactly the failure the 64 decision existed to prevent, arriving from the direction that decision predicted ("Task 4's measurement recursion adds frames per level"). 16 keeps that decision's criterion (fire before the stack dies on the *smallest* stack measured) at the same margin: 64/110 and 16/27 are both ≈0.58. | A 17-deep UI tree now traps with a cycle message that names no cycle. The alternative is worse — an unattributed SIGBUS — but the real fix is to shrink the per-level frames or make the descent iterative, not to raise the constant, and this is the first time the guard's ceiling has been *below* a plausible real tree. |

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

`LayoutContext.maxDepth` was 256 and is now **64**. This is not a ruling because
nothing was decided: the number was measured, and 256 failed.

Raising the constant out of the way and laying out N nested nodes gives, by
bisection: **196 levels lay out and 197 dies with SIGBUS** on a Swift Testing
exit-test task; review measured ~110 on an explicit 256 KB thread, and the main
thread's 8 MB reaching 256 and trapping properly. So at 256 the guard fired on
the main thread alone, and on every other stack the `placeNode` →
`positionItems` recursion exhausted the stack first — the exact unattributed
crash the guard exists to prevent.

**The lapse was invisible to the tests that existed**, and that is the part to
carry: both depth tests entered the context by hand, so neither ever ran a real
recursion and neither could see how far one gets.
`layingOutATreeDeeperThanTheLimitTraps` now lays out `maxDepth + 1` **real**
nested nodes and asserts the guard's own message on stderr — green at 64, red at
256 — so the next change to the constant is a measurement rather than a claim.
The boundary moves with frame size, and Task 4's measurement recursion adds
frames per level.


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

| mutation | reddens, of 334 | golden comparisons among them |
|---|---|---|
| `measureNode` returns 0 for a container (the pre-milestone bug, restored) | **15** | **0** |
| `.minContent` / `.maxContent` swapped at the two sites that name them | **3** | **1** |

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
was impossible.

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
5. a `wrap` container where **min-content and max-content genuinely differ** —
   still the mutation the corpus cannot redden (see the carried risk).
6. a **percentage cross size inside an auto-cross item**, which ruling CS-J
   decides against measuring and which nothing pins but a probe.

### The hand-written tests that DID move

| test | before | after | site |
|---|---|---|---|
| `autoCrossNestedContainerCollapsesItsLineUnlikeWebKit` → renamed `…MeasuresItsLineLikeWebKit` | `x` 120×**0**, `y` at y=**0** | `x` 120×**50**, `y` at y=**50** — WebKit's own numbers | 3 |
| `autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot` | root 800×600 | **unchanged**, after ruling CS-I reverted the CSS answer | 4 |
| `layingOutATreeDeeperThanTheLimitTraps` | green at `maxDepth = 64` | red — SIGBUS before the guard; green again at `maxDepth = 16` | ruling CS-L |

Three tests were added and none deleted: `anAutoRootWithNoOfferedExtentMeasuresItsContent`,
`aContainerItemsBaseSizeComesFromItsChildren`,
`aContainerItemIsFlooredByItsChildrensWidth`. Suite: **331 → 334**, and the
direction is the one ruling CS-B cares about.

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

  Measured, on 334 tests (see ruling CS-L's sibling note on why each half is
  reverted alone):

  | mutation | reddens | of which golden comparisons |
  |---|---|---|
  | §4.5 probe modes swapped | 4 | **2** (`wrapNestedPercentPaddingMatchesWebKit`, `wrapAlignContentAroundAndEvenlyMatchWebKit`) |
  | `flexBaseSize`'s main-axis `?? .maxContent` → `.minContent` | 2 | 0 |
  | both together | 3 | 1 |

  **The composite is weaker than either half**, which is the reason to revert
  sites one at a time: `aContainersIntrinsicQueryReachesItsChildren` and
  `automaticMinimumSizeUsesContentSizeNotFlexBasis` each go green again when
  the other site is also wrong. A single "swap everything" mutation would have
  reported 3 and hidden a site.

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
