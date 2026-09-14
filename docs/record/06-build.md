## Build

`swift build` · `swift test` — **811 tests** and 87 browser fixtures, warning-free
(re-measured 2026-09-03 `--no-parallel`, unfiltered, at the `Component`
milestone's whole-branch fix wave: `Test run with 811 tests in 1 suite passed
after 17.108 seconds.`, `find Tests -name "*.json" | wc -l` = 87, and a
full-log `grep -ci "warning:"` of 0 on both the test log and a `swift build`
log. **810 was the count through `32542d7` and `ca33d88`**, re-measured twice
there — `Test run with 810 tests in 1 suite passed after 15.688 seconds.` and,
on an independent second run, `…after 19.289 seconds.` — and the fix wave's one
added test is `layoutPassStyleAccessorsAreNotPublic`, a typecheck guard; 791 and 87 was that milestone's own
baseline, 782 and 87 the reactivity milestone's, 755 and 87 the tombstones
milestone's, and 752 and 86 the sizing
milestone's before its whole-branch fix wave). Per rulings CS-M/CS-N/SI-H: a
count is stale the moment a test is added, so it is taken at the latest commit
rather than at the commit that first quoted it.

**Erratum 2026-09-14 (at `7cfcddc`; record §09): the counts above are dated.**
The latest measurement was taken by the orchestrator on `feat/review-fixes`:
**993 tests**, **97** goldens, **39** typecheck guards, and 0 `error:` / 0
`warning:` from `swift test --no-parallel`, which printed a single summary line.
The intermediate reading was 923 / 97 / 35 at `7f58db9` (2026-09-11).
`a15ec83..7cfcddc` added 70 `@Test`s and removed none. The 97 goldens did not
move although `Sources/MetalUILayout/` changed; the new code is the proposal
engine, and no fixture reaches it.

**87 goldens is the `Component` milestone's exit criterion 4, as it was the
reactivity milestone's 5 and the tombstones milestone's 2 — not a by-product any
of the three times.** None of them touches the layout engine:
`git diff --name-only b36195d..HEAD -- Sources/MetalUILayout/` is **empty for
the whole `Component` branch** — re-run at `32542d7` — as `aab0e6a..HEAD` was
for the reactivity one and `2f8994b..HEAD` for the tombstones one, so
a moved golden would mean something reached the engine
that should not have. None moved and none was added: 87 before, 87 after, three
times.

**That the `Component` branch leaves `Sources/MetalUILayout/` untouched is
worth one extra sentence, because its headline feature is a STYLE AMENDMENT.**
`StyledComponent` writes through `LayoutTree.setStyle` — whose **first
production caller** this is (ruling `CO-V`; `git grep -n "setStyle" b36195d --
Sources/` returns three lines, all inside `LayoutTree.swift` itself, none a
call) — but the call is made from `MetalUI`, and the engine already had the API.
`display: contents`, the one thing this milestone considered that *would* have
moved a golden, was deferred for exactly that reason (`CO-R`).

**Two tests are gated and DO count toward the 811 — a claim this paragraph got
wrong for one milestone and which is corrected here rather than quietly
edited.** It previously said the 100k test "is disabled by default and does not
run in the count above", which conflates two things. Measured:
`swift test --no-parallel --filter aListsWorkIsTheSameFor100kRowsAsFor500`
reports `Test run with 1 test in 1 suite passed`, and a full-log grep for
`skipped` finds exactly two tests — `regenerateAllGoldens` and that one, both
re-confirmed skipped in the 811-test run above (`grep -i skipped` over the full
log returns six lines, of which four are two ordinary tests whose *names*
contain the word — re-run at the fix wave, same six). **A
`.enabled(if:)` skip counts toward the total and is reported as skipped; what
is disabled is what RUNS, 809 of the 811 by default.** The distinction matters
because the reflex when the summary line moves is to look for an added or
deleted test, and a gate changes neither number.

**`aListsWorkIsTheSameFor100kRowsAsFor500`
(`Tests/MetalUITests/MeasurePerformanceTests.swift`) is skipped by default.**
It times M3's exit-criterion cold frame at
the real 100,000 rows (ruling MP-I) and alone adds ~42 s debug / ~17 s release
to the suite's wall clock — gated the same way `regenerateAllGoldens`
(`Tests/MetalUILayoutTests/GeneratorTests.swift`) gates an expensive
deliberate act rather than a per-run one. Run it deliberately:

```
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
```

**Naming that command here is the gate's precondition rather than a
convenience (ruling `TB-L`)**: the whole objection to gating a milestone
deliverable is that it rots unrun, and the mitigation is that the command lives
in the one document a reader starts from. The gate itself recovered **66.833 s
→ 14.790 s** of suite wall clock (Task 8's fix round's figures, reproduced twice
more there at 14.837 and 14.774). **Three independent full runs at the
documentation task read 14.903, 14.981 and 15.117 s** — the same regime, on the
same machine, one milestone-task later; the 66.8 s figure is the one nobody has
re-run, and it would require reverting the gate to see again.

**Typecheck guards: 34 today, and across FIVE files rather than four. The
breakdown immediately below is the TOMBSTONES milestone's 32**, kept because the
argument it makes is about the fifth *file*; today's 34 and the counting trap
that comes with it are two paragraphs down — 19
`PhaseSeparationTests` + 7 `ErasureCompileGuards` + 1 `ElementGroupTrapTests`
+ 2 `Tests/MetalUICoreTests/UnitSafetyTests.swift` (a bare `grep -c` there
reads 3; one is a comment) + **3 `Tests/MetalUITests/AXNodeTests.swift`**, the
new fifth file. Re-counted by grep at this milestone's last commit, per file,
rather than carried. **It was 29 across four files for eight milestones and
this is the second time it has moved at all**; see "When CI lands" item 3,
which argues at length that the guard count does *not* track the suite count —
this is a data point for that argument, not an exception to it. The three new
guards exist because `AXNodeTests.swift` uses `@testable import`, which widens
`internal` and therefore **cannot** demonstrate an access-level narrowing —
ruling `TB-N`, and taxonomy shape 16 in the practices doc. **Re-counted by grep
per file at the reactivity milestone's last commit (suite 791): still 32** —
19 + 7 + 1 + 2 + 3, unchanged. That milestone added nine tests, no guard and no
file, which is the "When CI lands" argument arriving once more as a data point
rather than an exception: 791 does not say 32 and nothing here claims it does.

**It is 34 as of the `Component` milestone's fix wave (suite 811), and the
fifth file is still the last one** — 19 `PhaseSeparationTests` + **9**
`ErasureCompileGuards` + 1 `ElementGroupTrapTests` + 2 `UnitSafetyTests` + 3
`AXNodeTests`, re-counted by per-file `grep -c canTypecheck` at the fix wave's
commit. **A `grep -rl canTypecheck Tests/` returns SIX paths and only five of
them carry guards**: the sixth is `Tests/MetalUITestSupport/Typecheck.swift`,
where the single hit is `canTypecheck`'s own declaration. Count guards per file,
not files.

**Two guards landed in this milestone, one per round.** The task-round one is
`backgroundCannotBeCalledOnAComponent`, asserting that
`Leafless().background(.accent)` does **not** compile — a regression that adds
the modifier makes the probe *compile*, which no runtime test could see (ruling
`CO-W`). The fix wave's is `layoutPassStyleAccessorsAreNotPublic`, which is the
**only** artifact that can demonstrate that fix wave's narrowing of
`LayoutPass.style(_:)`/`setStyle(_:_:)` from `public` to `internal`: those two
read back and overwrite the `Style` of any `LayoutNodeID` a caller can name —
a sibling's, a parent's — during the request phase, for one in-module caller
(`StyledComponent`). **The mutation was run, not predicted**: restoring `public`
on both and rebuilding reddens *both* of that test's assertions. Note that it
must probe through a **plain** import, which `typecheck(_:importing:)` supplies
by construction — `@testable` widens `internal` and so cannot demonstrate a
narrowing at all (taxonomy shape 16, ruling `TB-N`).

Same pattern as every previous move: a guard written in the same change that
could have introduced the hazard it guards against, and 811 does not say 34 any
more than 791 said 32. **One honest qualifier on that, since this move is the
weakest data point in the series rather than the strongest**: the fix wave's
guard is itself a `@Test`, so it moved the suite count and the guard count
together, by one each. The independence claim rests on the other five moves and
on the milestones where the suite grew and the count did not.

**The `Component` milestone's own climb, task by task** (baseline **791** tests,
87 goldens, 32 guards, warning-free — the reactivity milestone's own
end-of-milestone count, which reproduced exactly). **Each figure below is the
summary line the task itself read at its own commit; only the final 810 was
re-run by this documentation task, twice.** They are corroborated rather than
trusted, by the same net `@Test`-declaration delta the paragraphs below use —
for each commit, `git show <c> -- 'Tests/*' | grep -c "^+.*@Test"` minus the same
with `"^-.*@Test"`, accumulated from 791 — which reproduces every intermediate
figure and lands exactly on the re-measured 810.
**795** after Task 1 (`d32b25c`, the protocol, `ComponentLayout` and the
extension — **red-first by construction**, since the file does not compile until
the conformance is complete) and 795 through its fix round (`a98bb03`) and
through the two doc commits the SwiftUI probes forced (`b9d6895`, `b8f9918`).
**801** after Task 2 (`8000f51`, `@State` inside a component and the four
mutations that pin it — the plan expected 800; the sixth test is ruling `CO-F`'s
`contentIsMaterializedExactlyOncePerFrame`, which Task 1's review demanded and
the plan lacked) and **802** after its first fix round (`f74688e`, ruling
`CO-I`'s coverage gap). **806** after Task 3 (`87891a3`, distribution: three
tests plus the `.background()` typecheck guard, taking guards 32 → 33) and 806
through Task 2's second fix round (`dda81bc`, the whole-table re-take, comments
only). **810** after Task 3's fix round (`32542d7`, chained modifiers composing
— ruling `CO-N`, four tests), and **810** unchanged through its scoped
re-review's comment-only follow-up (`ca33d88`, which walks an honest negative
back to the test's own doc comment; `git show ca33d88 -- 'Tests/*' | grep -c
"^+.*@Test"` reads 0). This documentation task adds none, so 810
reproduces exactly. Ten commits, `b36195d..ca33d88`.

**The whole-branch fix wave then added exactly ONE test and NO golden — 810 →
**811**, 87 unchanged — and that one test is a `swiftc -typecheck` guard, taking
guards 33 → 34.** Both numbers moved, and by the same one line: a
`.enabled(if:)` compile guard is a `@Test` like any other and counts toward the
suite total, so "the fix wave added no test" would be false. (The guard count
and the suite count are still independent in the sense "When CI lands" item 3
argues — five of the six guard moves came with unrelated suite growth or none —
but this particular move is the one case where a single commit moved both by
one, and saying otherwise would be tidier and wrong.) The review returned "ready
to merge with fixes" with **no Critical findings**; the mechanism had been
verified by probe rather than argued, so there was no *coverage* gap to close,
and the guard closes an access-level one instead. Three
findings were **measured** rather than reasoned, and none of the three had been
written down anywhere: a caller's modifier silently overwrites a component's own
internal sizing (30/50 → **70/70**); `.padding()` on a leaf-only component is
**completely inert** (a marker leaf's `x` reads 13.0 both ways), which is the
inert table's leaf row composing with distribution; and `Deferred` and `List`
**reject a component outright**, so `Component` composes with five of seven
containers. The other half was correcting two refuted claims that were still
standing in shipped source, four sites in the plan that still *instructed* the
refuted design — two of them forward-looking instructions rather than history —
and three stale record sites (a deleted `ComponentLayout.id`, a spurious
`@MainActor`, a "14 tests" denominator that had become 18; that last mutation
was **re-run**, and it still reddens the same 10 issues across the same six
tests). Everything measured was walked back to the line, per the practices doc's
first record-mechanism.

**Three steps in that list are worth reading rather than counting.** Task 1's
review found **three load-bearing lines reddening NOTHING on 795 tests** —
`cursor += 1`, threading the outer cursor, and `prepaintGroup` re-evaluating
`content` — so the "opaque to identity" half of the design was entirely unguarded
at that point and was carried to Task 2 as a requirement rather than patched
(`CO-F`). Task 2's fix round then produced the branch's cleanest instance of
practices mechanism 3: **re-taking the whole four-row mutation table found two
rows moved and two unchanged**, and had only the one flagged row been corrected,
two of the four would still be wrong today. And Task 3's fix round exists because
`swiftc -typecheck` found that the three forwarded modifiers **did not compose**
— `Leafless().width(…).height(…)` was a type error, undetected because no test
exercised `width` or `height` at all, which is this file's own recurring lesson
verbatim: *a feature that works alone and a feature that works alone can be wrong
together* (`CO-X`).

**And one thing the branch measured that it deliberately refused to predict.**
`.padding(4).padding(8)` — **the second call wins outright**, width 16 = 2×8. It
does not accumulate (24) and the first does not survive (8). The mutation that
pins the composition (drop `previous(&style)` from all three chained overloads)
reddens **2 issues on `widthAndHeightComposeOnAChainedModifier`**, and the
implementer reported unprompted that `chainedPaddingReplacesRatherThanAccumulates`
**stays green** under it, because same-field replace-versus-compose is
indistinguishable. Stating what a test cannot see is the half most reports omit.

**The reactivity milestone's own climb, task by task** (baseline **782** tests,
87 goldens, 32 guards, warning-free — the tombstones milestone's own
end-of-milestone count, which reproduced exactly). **Each figure below is the
summary line the task itself read at its own commit; only the final 791 was
re-run by this documentation task.** They are corroborated rather than trusted,
by the same net `@Test`-declaration delta the paragraph below uses — for each
commit, `git show <c> -- 'Tests/*' | grep -c "^+.*@Test"` minus the same with
`"^-.*@Test"`, accumulated from 782 — which reproduces every intermediate figure
and lands exactly on the re-measured 791.
**782** after Tasks 1+2's first commit (`b1e7deb`, the sentinel and the two
counters — dispatched as one unit with Task 2 because its diff is dead code by
construction, ruling `RX-A`) and **784** after its second (`2b616e3`, the
tracked frame build; one of its two tests is **green on arrival by design**,
asserting an absence, ruling `RX-B`). **787** after Task 3 (`616f108`, the
accumulation bound, the flush guard and waking a paused window — both mutations
run and both discriminating: sentinel removed gives 200 against 1 and moves
nothing else, `isFlushing` deleted gives 199 against 0). **791** after Task 4
(`3eadcc1`, both hop branches, `@State`/`@Observable` composition and the
windowed-`List` consequence) and **791** unchanged through both of its fix
rounds (`0588863`, replacing an assertion that pinned the scheduler rather than
the code, ruling `RX-I`; `d3aa92c`, adding the off-screen test's positive
control). **791** after Task 5 (`9ea6062`, the demo's `showModal` on an
`@Observable` model plus the exit-counter summary; no test). This documentation
task adds none, so 791 reproduces exactly. Seven commits, `aab0e6a..9ea6062`.

**Two steps in that list are worth reading rather than counting, and both are
about a prediction that failed.** Task 3's `isFlushing` mutation was run
specifically to confirm that `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt`
**stays green**, which is the corrected form of a spec assertion; Task 4 then
found the *same* test green under the always-hop mutation the spec's §4.2
argument had predicted it would catch — six others failed instead, and the
reason is structural blindness rather than insensitivity (ruling `RX-H`, and the
reactivity spec's §4.2 now carries the correction). And Task 4's fix round
produced the branch's sharpest measurement, which is not a test count at all:
collapsing `markDirtyFromObservation` to a bare `MainActor.assumeIsolated`
**crashes the suite with SIGTRAP, signal 5, and no summary line** rather than
reddening anything — taxonomy shape 13 as a live result.

**The tombstones-and-AX milestone's own climb, task by task** (baseline
**755** tests, 87 goldens, 29 guards, warning-free). **Each figure below is the
summary line the task itself read at its own commit; only the final 782 was
re-run by the documentation task.** They are corroborated rather than trusted:
a net `@Test`-declaration delta computed over each commit's own diff — for each
commit, `git show <c> -- 'Tests/*' | grep -c "^+.*@Test"` minus the same with
`"^-.*@Test"`, accumulated from 755 — reproduces every intermediate figure and
lands exactly on the re-measured 782.
**757** after Task 1 (`b542206`, the sweep retaining unmarked entries as
tombstones — seven pre-existing tests reddened and each was *inverted with its
history kept*, never deleted, ruling `TB-A`) and 757 again after its
comment-only fix round (`cabd9bd`). **758** after Task 2 (`2d1eb37`, the reap
and its two constants — the assertion was **red on arrival by design**, first
as a compile error, ruling `TB-C`) and 758 again after its comment-only fix
round (`84799a9`). **760** after Task 3 (`454b374`, divergence 12's bounded
pin — and a *second*, deliberately unrealistic single-entry test, because the
realistic `List` fixture holds the size gate permanently true and therefore
cannot see it, ruling `TB-H`). **762** after Task 4 (`319f362`, divergence 17
on the same table rather than a second grace period). **764** after Task 8
(`c5496db`, merged `fe0e0d9`, the 100k cold-frame and steady-state work — run
early and in a worktree, ruling `TB-I`) and 764 after its fix round
(`093be2a`, which shrank the resident-set test to 10k and gated the timing
one; the *total* did not move because a skip still counts, which is the
correction three paragraphs up). **771** then **773** after Task 5's fix round
(`2f59fd8`, `abed015` — the `AXNode` type and its emission, plus the two
plain-import compile guards `@testable` made necessary). **777** then **779**
after Task 6's fix round (`f9d7613`, `0a10d53` — validity from
`StateTable.isLive`, a third compile guard, and the slot-distinctness test that
`TB-R` argues is worth more than its size). **782** after Task 7 (`47439a7`,
a virtualized `List` reporting its full logical count) and **782** unchanged
through both of its doc-only fix rounds (`fd62e63`, `84c0baa`). This
documentation task adds no test, so 782 reproduces exactly.

**The whole-branch fix wave added NO test and NO golden — 782 and 87 before and
after — and that is a result rather than an omission.** The whole-branch review
ran **17 mutations** against the branch's load-bearing lines and every one
reddened something naming the property it mutated, so the wave had no coverage
gap to close. What it produced instead was five record findings, and the largest
is **divergence 18**: this branch shipped a real behaviour change — a `@State` in
a removed conditional subtree is no longer reset, and below `sweepThreshold` not
ever — that no divergence entry covered, because the whole record was framed
around the `List` case the milestone was built for. **A general mechanism was
documented only at its motivating case.** The wave also corrected two mutation
claims in source docs, one of which was wrong in *kind*: an exclusivity claim
("reddens exactly this test and nothing else in the 777-test suite") had become
false because a later test in the same file grew sensitivity to the same line.
See the practices doc's third record-mechanism for why an exclusivity claim rots
worse than a count.

**Two steps in that list are worth reading rather than counting.** Task 3's
`+2` is one test the task was asked for and one it was not: the brief assigned
a mutation to a fixture that **cannot catch it**, proven by running it — the
mutation reddens 0 tests with only the `List` fixture present. And Task 8's
whole contribution rests on a mutation the implementer ran rather than
reported: **disabling the reap gate and re-running**, which fails at exactly
`count == 100001`, is what says the cold-frame spike actually falls.

**The sizing milestone's own climb, task by task** (baseline **741** tests, 81
goldens, 29 guards, warning-free — this milestone's own ledger's first line).
**Fixture-first means the suite was deliberately RED for most of it**: a
fixture-writing task commits a comparison test that fails against today's
engine on arrival, and a later fix task is what turns it green — a red count
below is the method working, not a broken tree. 742 tests, 2 issues after
Task 1 (the root-percentage fixture, intentionally red) and 742 passing after
Task 2 (the root-percentage fix, ruling `SZ-A`) — goldens 81 → 82 at Task 1,
unmoved since. 743 tests, 2 issues after Task 3 (the BM-4 fixture; its own
fixture task discovered that BM-4 and FS-3 compose on the same tree, `SZ-G`'s
ancestor) and 749 tests, 1 issue after Task 4 (the BM-4 fix, five call sites
rather than the one its brief named, `SZ-D`/`SZ-E`/`SZ-F`/`SZ-J`) — goldens
83. **Task 4's own fixture could not go green at Task 4**: BM-4 alone raises
the item's floor to 120, but the pre-existing content-only automatic minimum
still floors it higher, at 130, so the fixture stayed red on its width axis
(130 vs WebKit's 120) until Task 6 implemented FS-3's used-value reading —
the one residual issue is carried, named, through Tasks 5 and 9 below. 750
tests, 5 issues after Task 5 (the FS-3 fixture; both of its numeric
predictions held) — goldens 84. 751 tests, 0 issues after Task 6 (the FS-3
fix, closing both its own fixture and Task 4's carried residual in the same
commit — `SZ-G`/`SZ-H`/`SZ-I`, plus a second fixture,
`sizing_specified_suggestion_is_used_value`, because the first did not
actually discriminate the used-vs-declared reading) and its own fix round
(`ad30a3c`, dropping a stray `FlexEngine.swift.orig` a `git add -A` had swept
in) — goldens 85, one of which (`sizing_over_constrained_grows.json`) is a
legitimate move: the fixture's own HTML was corrected to declare
`display: flex` so the Swift tree and the browser tree describe the same
thing (`SZ-I`), and the golden was regenerated against the corrected HTML,
not against the engine's prior answer. 751 tests, still passing, after Task 9
(demo fallout, run in an isolated worktree in parallel with Task 6's review —
`SZ-K`, `SZ-L`; no test added). 752 tests, 1 issue (ruled) after Task 7 (the
TX-H fixture) and **752 tests, 0 issues** after Task 8 (the TX-H fix, run in
a second worktree in parallel with Task 10 writing the decisions doc —
`SZ-M`, `SZ-N`) — goldens 86. Task 10 (the decisions doc) and this task, Task
11 (CLAUDE.md), touch no `Sources/`/`Tests/` code beyond a two-word ruling-id
rename and reproduce 752/0 exactly.

**The whole-branch fix wave then added three tests and one golden, reaching
755 and 87 — and one of the three closed a REGRESSION this branch shipped**
(ruling `SZ-O`). TX-H's re-measure updated an item's cross size and nothing
above it: the item's *line* extent and the container's `contentCross` were
both computed from the pre-flex sizes and never recomputed, so an
`auto`-height row containing a 40-tall flexed child reported **20**, and a
wrapping container's second line stacked 20pt too high — **overlapping
siblings, a visible rendering defect rather than a wrong number.** Both were
new: with the re-measure disabled the engine is internally consistent and
uniformly wrong, so TX-H made the item right and left the tree incoherent.
The fix is CSS Flexbox's own step order — §9.7 and the re-measure move
*above* the line and container measurement, which is safe because §9.7 reads
no cross-axis field at all (`grep -n
"crossSize\|marginCross\|minCross\|maxCross\|stretchEligible"
Sources/MetalUILayout/ResolveFlexibleLengths.swift` returns nothing) — and it
moved **no golden**: all 87 were regenerated against live WebKit for a zero
`git diff`. Pinned by `crossSizeAfterFlexPropagatesToAnAutoContainer` and
`crossSizeAfterFlexPropagatesToTheLine`, which discriminate rather than
merely cover: moving `contentCross` alone back above the flex loop reddens
only the first, moving the line-size loop alone reddens only the second.
The third test and the golden are
`percentageMainAgainstAnIndefiniteContainerMatchesWebKit` /
`sizing_percent_main_against_indefinite`, closing FS-3's second guard clause
— a percentage main size against an indefinite container, which was live,
reachable, browser-correct and reddened **nothing** under a mutation that
moved geometry three ways.

**All four sizing divergences are closed**, and divergence 3, 5 and 6's
entries are retired above.

**The input-and-state milestone's climb is kept below as its own record.**

**The input-and-state milestone's own climb, task by task** (baseline **609**,
the measure-performance milestone's own end-of-milestone count, which reproduced
exactly — **not 577**, which is that milestone's *own* baseline and is the
number this milestone's task-11 brief carried forward by mistake): 613 after
Task 1 (`@State`'s storage and slot ids), 617 then **618** after Task 2's fix
round (reflection-driven seeding, plus a pin for the ordinal being the `Mirror`
index rather than the position among `@State` children), 622 then **623** after
Task 3's fix round (the dirty flag and the `onWrite` hook, plus the unguarded
`marked.insert` a review found by mutation), **623** after Task 4 — which added
**no test and no commit**, and is a real result rather than a skipped task:
`ScrollRoutingTests` already pinned all four properties the brief named, and the
implementer verified that *by mutation* rather than by reading test names. 631
after Task 5 (the hitbox list) and 631 again after its fix round (a
sort → `.max` rewrite that added no test), 637 then **640** after Task 6's fix
round (hover and active, the `NSTrackingArea`, and two phase guards — the first
time the typecheck-guard count had moved in eight milestones), 644 both before
and after Task 7 (folding scroll regions into the one list; its fix round is
entirely comments), 658 both before and after Task 8 (click dispatch and
`Handlers`), 674 then **676** after Task 9's fix round (the focus tree), 725
then **729** after Task 10's fix round (actions, keymaps, context predicates and
two-stroke — the milestone's largest task at 49 tests). Task 11 is the counter
demo, the documentation and the human-verification record; it adds **seven** —
five in the new `PointerStatePaintTests` for the hover/focus token swaps, one
`swiftc -typecheck` guard for the element-keyed `isHovered` overload, and
divergence 15's deliberately-wrong pin in the new `NestedClipTests` — reaching
**736**. **The whole-branch fix wave then added three, reaching 739**: two in
`FocusTests` for the guarded focus read-back (ruling `IN-X`) — one that focuses
from *inside* a frame and one that pins the in-frame call still being validated
by the next frame — and one in `InputDispatchTests` for click dispatch
inheriting the vanishing-`if` identity adoption, which asserts both the wrong
answer and the naming that removes it. Goldens: **81 before, 81 after, and no
existing golden file modified at
any point in the milestone**, which is exit criterion 2 and the standing check
that input never reached the layout engine.

**Three of those steps are worth reading rather than counting.** Task 4's zero
is the strongest: "already covered" was proved by mutating the ranking walk, the
layer key and the offset clamp and watching named tests redden, one of which
(`aDeferredScrollViewTakesTheWheelFromAnOverlappingSiblingBeneathIt`) reddened
*alone* under the layer mutation while both same-layer tests stayed green — a
discriminating result, which is the hard one to fake. Task 6's +3 includes a
test written because a mutation reddened **nothing**: `mousePosition:
lastMousePosition → nil` in `drawFrameIfNeeded` left 637 tests green, because
every hover test either built a `Frame` with a literal `mousePosition:` or drove
`resolveHover` by hand, so the one line connecting a real mouse event to a
resolved hover was uncovered. And Task 8's whole worth rests on one check:
swapping the two lines that read `active` before `updatePointerState` clears it
reddens **23 issues across 11 test functions**, which is what says `onClick` is
wired through the real input path rather than driven by a test helper.

**The measure-performance milestone's climb is kept below as its own record.**

**The measure-performance milestone's own climb, task by task** (baseline 577,
the absolute-positioning milestone's own end-of-milestone count, which
reproduced exactly): 579 after Task 1 (the counting harness, two of whose three
assertions were **red on arrival by design** — a performance harness that passes
before the work is done is measuring nothing), 581 after Task 2 (the min-content
memo), 581 after Task 3 (docs and the `MP-A`/`MP-B` rulings; it adds no test),
583 then **588** after Task 4's review round (`List` itself, plus five for row
flooring, identity distinctness, an empty list and a modifier reaching the
layout node), 590 then **592** after Task 5's review round (the ambient scroll
context), 595 then **600** after Task 6's review round (windowing — this is the
task that turns the LAST of the harness's red assertions green — the other one,
`aWarmFrameTokenizesEachDistinctStringAtMostOnce`, went green at Task 2 when the
memo landed, so only `aListsWorkIsTheSameFor160RowsAsFor40` survived to here),
603 then **604** after
Task 7's review round (both shaping caches bounded by a generation sweep). Task
8 is the demo and the documentation and adds no test, so 604 reproduced exactly.
**The whole-branch review's fix round then added five, reaching 609**: three in
`ListTests` — one per half of the scroll-context defect the review found, being
the axis clause (MP-M), `Deferred`'s layout-phase escape (MP-N) and divergence
14's deliberately-wrong pin (MP-L) — and two in `ShapingCacheTests`, one pinning
`staleAfterGenerations` at exactly 2 from both sides and one pinning that
`Shaper.unbreakableRunCalls` ignored calls made off the main thread — the
guard that made a bare `@MainActor` global safe from a *nonisolated* caller
at the time. **Both the symbol and that guard are gone now**: the
tokenizer-counter flake fix replaced the global with a task-local sink
(`Shaper.runCallCounter`, `UnbreakableRuns.swift`) and renamed the pinning
test, because the guard never protected against two `@MainActor` tests
racing each other's own window — see that fix's own record for the measured
flake this closes. **Goldens did not move at any
point in this milestone: 81 before, 81 after, and no existing golden file
modified** — which is the milestone's own second exit
criterion, since it touches the measure path and a moved golden would mean
something reached the engine that should not have.

**The absolute-positioning milestone's climb is kept below as its own record.**

**The absolute-positioning milestone's own climb, task by task** (baseline 538,
the Stack milestone's own end-of-milestone count, which reproduced exactly):
540 after Task 1 (`AbsolutePositioningTests`' two placeholders), 541 after Task
2 (the two placeholders replaced by three flow-filter tests), 544 after Task 3
(containing blocks), 549 after Task 4 (insets, including a regression test for
a 0×0 sizing bug Task 3 shipped — ruling AP-E), 555 after Task 5 (five browser
fixtures plus divergence 9's pin), 561 after Task 6 (`DrawListTests`) and then
**560** when that task's review round deleted a test it had proved redundant,
565 after Task 7 (`DeferredTests`) and **569** after Task 7's second review
round (a `Deferred` identity differential, nested-layer idempotence, and the
prepaint and paint halves of a real `ScrollView` escape). Task 8 is the demo
and the documentation and adds no test, so 569 reproduced exactly. **The
whole-branch review's fix round then added eight, reaching 577**: five in
`AbsolutePositioningTests` for live clauses of the absolute pass that no test
reached (each found by a mutation the 569-test suite passed under), one in the
new `AbsoluteOverlayTests` pinning divergence 11, and two in
`ScrollRoutingTests` for the scroll-region layer key. **Goldens
climbed 76 → 81 in Task 5 and moved nowhere else in the milestone** — five new
`abs_*` fixtures, and **no golden that existed before this branch was
modified**, verified at every task. Stated that precisely because one of the
five *was* regenerated within the milestone: `abs_over_constrained.json` landed
in `385c035` and was regenerated in `ee06f84` after its own HTML was reordered
(its `top: 0; bottom: 0` made "stretch between two insets" and "fill the
containing block" the same number, so the fixture pinned nothing on its
vertical axis until it became `top: 10px; bottom: 20px`). Same shape as the
Stack milestone's "two of the 75 were also regenerated after their HTML was
reordered".

**One count in that list goes DOWN, and it is the interesting one.** Task 6's
review found two tests in `DrawListTests` with byte-identical fixtures, so they
reddened together under every mutation; the resolution was not to keep both but
to redesign the survivor's fixture (conflicting `order` values across primitive
kinds, so only `layer` can produce the expected result) and delete the twin.
A test that catches nothing its neighbour does not catch is not coverage.

**The Stack milestone's climb is kept below as its own record, not folded into
the numbers above.**

**The Stack milestone's own climb, task by task** (baseline 504, measured by
Task 1's bisect against the clipping-and-scroll paragraph's stale 489 — an
unrecorded `ScrollView.scrollIndicators(_:)` commit landed between that
milestone and this one and moved the true starting point): 506 after Task 1
(`StackLayoutTests`), 510 then **512** after Task 2's fix round
(`aStackSizesAnAutoChildFromItsOwnContent`,
`aStackChildsMinWidthClampsItsDeclaredSize`), 517 after Task 3 (all nine
alignments), 522 then **524** after Task 4's fix round (the auto-only
`stretch` engine bug, below), 527 after Task 5 (the `Stack` element and the
`Stack.swift`/`Flex.swift` rename), 529 after Task 6 (nesting fixtures). Task
7 is docs and the demo and adds no test, so 529 reproduced
exactly. The whole-branch review's fix round then added **nine**, reaching
**538**: one browser-fixture test for the percentage bug below, and eight
`StackLayoutTests` cases for clauses that were live and unreached (both
`maxSize` clamps, the measured `minSize` height, the mixed known/auto measure
axis, `containingBlockWidth` at each of the two stack sites, the `?? .stretch`
fallback and `AlignItems.baseline`). Goldens climbed 67 → 72 → **73** (Task 4
and its fix round) → 75 (Task 6) → **76** (the review's fix round; two of the
75 were also regenerated after their HTML was reordered, and no other golden
moved). Every number here was itself re-measured rather
than summed by hand — treat a ±1 against this paragraph as a stale doc, not a
missing test, and re-measure.

**Two findings from that review are worth carrying rather than only counting.**
First, `layOutStack` folded an **unresolvable percentage to 0** where WebKit
content-measures it, and *both* the ruling (ST-E) and the code comment stated
the engine's behaviour backwards — the ruling generalised from a probe whose
percentage child was empty, a shape under which the right and wrong rules give
the same number. Fixed, fixtured, and recorded as an error in
`docs/superpowers/2026-08-28-stack-decisions.md`. Second, **seven of the nine
`Alignment` cases were unguarded**: `allNineAlignmentsMapToDistinctPairs`
asserted distinctness only, which every permutation preserves, so
`Stack(alignment: .leading)` could have shipped drawing on the right. It now
asserts each case's `(alignItems, justifyItems)` pair *and* keeps the
distinctness `#require`, because the two catch different bugs.

The clipping-and-scroll paragraph below is kept as its own milestone's
record, not folded into the numbers above:
Task 10 was docs and the demo and added no test, so Task 9's 482 reproduced
exactly; the whole-branch review's fix round then added **six** — a `ScrollView`
text pin for ruling CL-C, a rect pre-projection clip test, an
unfinalized-scene trap and its positive control, an indicator fade/token
assertion and a horizontal-indicator geometry one — reaching 488 at the
milestone's own last commit. The wrap-investigation record-and-pin work that
followed added **one** —
`roundingCanMakePaintWrapAShrinkWrappedTextThatLayoutMeasuredAsOneLine`,
divergence 8's pin — bringing it to 489. (**That test no longer exists**: it
asserted the wrong answer on purpose, the divergence was fixed on 2026-08-30,
and it was replaced by
`paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox`. The sentence is kept
as the history it is — do not grep for the old name and conclude a test was
lost.) Read the summary lines, never
the exit status — shape 11. **This said "the summary line", singular, until
the documentation task corrected it below (Build section): a current `swift
test` prints one per test target — six today — and only their sum is the
suite total.**
The milestone started at **445** (M2's own end-of-milestone count) and climbed
task by task: 451 after Task 1 (`DrawListTests`), 452 after Task 2, 455 after
Task 3 (`ClipTests`), 458 after Task 4, 463 after Task 5 (`ClipStackTests`),
468 after Task 6 (`ScrollViewTests`/`ScrollLayoutTests`), 474 after Task 7
(`ScrollRoutingTests`), 477 after Task 8, 482 after Task 9 (`ScrollIndicatorTests`).
Every one of those was itself re-measured rather than summed by hand at the
time — treat a ±1 against this list as a stale doc rather than a missing test,
and re-measure).
**Eight** non-test targets with strictly one-way dependencies: `MetalUICore`,
`MetalUILayout`, `MetalUIText`, `MetalUIShaderTypes`, `MetalUIRender`,
`MetalUIPlatform`, `MetalUI`, `MetalUIDemo`. **`MetalUITestSupport` is a ninth
`.target` in `Package.swift` and is not one of them** — it lives under `Tests/`,
ships in no product, and holds the single copy of the `swiftc -typecheck`
machinery the negative type-system guards shell out to (ruling EP-1). Count with
`grep -cE "^ +\.(target|executableTarget)\(" Package.swift`, which returns 9
(`.testTarget(` does not match), and subtract `MetalUITestSupport`.

**Spec §3.1 says "seven targets", and it is a different seven.** Its list is
the module *layering* — `MetalUI`, `MetalUILayout`, **`MetalUIText`**,
`MetalUIRender`, `MetalUIPlatform`, `MetalUICore`, `MetalUIShaderTypes` — which
excludes `MetalUIDemo`, an executable rather than a layer. **The two counts used
to agree and no longer do**: M2 Task 1 landed `MetalUIText`, which this section
had already named as the coincidence's expiry date. Eight here against §3.1's
seven is the expected state. Do not "reconcile" one list to the other.

Four constraints that are easy to violate silently:

- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored
  pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **Every `LayoutTree` that could ever exchange ids with another must have a
  distinct `generation`** (m1a ruling C-3, closed in the element pipeline's task
  4). `LayoutNodeID` carries the generation of the tree that issued it and every
  accessor rejects a foreign one, but the *uniqueness* of the generation is the
  constructor's obligation: `LayoutTree.init(generation:)` has no default
  precisely so that obligation is visible at each call site. In `Sources/` the
  only constructor is `Frame`, which draws from a `@MainActor` counter — check
  with `grep -rn "LayoutTree(" Sources/`. Layout tests pass `0` because their
  trees never exchange ids; a test that puts two trees in one function and moves
  an id between them must not.
- **Pixel format is `bgra8Unorm`, never `_sRGB`.** An `_sRGB` target makes the
  hardware blend in linear space; this framework composites in gamma-encoded sRGB
  by design (§7.8). It would look fine now and make text rendering wrong later.
- **A percentage `padding` or `border` resolves against the CONTAINING BLOCK's
  width — not the box's own width, and not a height. `Style.inset` is the
  exception and takes its own basis per axis.** Both halves of the first
  sentence have been wrong in this repo, and neither failed a test at the time.
  `contentBox` resolved percentage `padding`/`border` against the box's own
  border-box width until the box model's third task; WebKit puts a 200-wide
  `.mid { padding: 10% }` inside a 270-wide content box at **27**, not 20. The
  vertical `padding`/`border` edges take the same *width* basis, which a square
  container cannot distinguish — that is why `flex_percent_padding_nonsquare` is
  400×100 inside an 800×600 viewport, so that all three candidate bases give
  three different answers on every edge. `flex_nested_percent_padding` does the
  same one level down, where the containing block is not the viewport.

  **This constraint used to say "a percentage inset" and it was a trap
  (ruling AP-D).** It was written about `padding` and `border` — where CSS
  really does resolve every percentage against width — but it used the word
  "inset", and `Style.inset` does not follow that rule: `left`/`right` resolve
  against the containing block's **width**, `top`/`bottom` against its
  **height**. Following the old wording literally is wrong on two of four edges,
  and the absolute-positioning design had to instruct its own implementation not
  to cite this bullet. `placeAbsolute` (`FlexEngine.swift`) carries the per-axis
  rule at the one site that reads `Style.inset`; `abs_percent_insets_nonsquare`
  (200×100, so `left: 10%` is 20 and `top: 10%` is 10) is the fixture that can
  see the difference, and a square containing block cannot.

**Adding an AppKit or WebKit test? Run the WHOLE suite and read the summary
lines — `--filter` is a different program.** Every test target runs in **one
process**, so an AppKit test and the WebKit layout-oracle tests share a main run
loop. That composition has already crashed the suite once: two
`MetalUIPlatformTests` cases ended in `defer { nsWindow.close() }`, and
`NSWindow(contentRect:…)` defaults `isReleasedWhenClosed` to **true** — an
over-release of a window ARC already owns, which AppKit defers into an
autorelease pool that CoreAnimation pops from a run-loop observer. Alone the
process exited before that pool popped; alongside a test that `await`s it landed
in `-[_NSWindowTransformAnimation dealloc]` as `EXC_BAD_ACCESS`, and `swift test`
died with **297 of 303 tests reported and no summary line**. Fixed at the source
(`AppKitWindow.init` now sets `isReleasedWhenClosed = false`) and pinned by
`closingAWindowDoesNotOverReleaseTheOneARCAlreadyOwns`. **Serializing the two
targets would not have fixed it** — a single `--no-parallel` test that closes a
window and then drives the oracle crashes with no interleaving at all. The full
write-up is under shape 11 in `docs/practices/verifying-tests-can-fail.md`; the
short rule is that a test touching a process-wide host (AppKit windows, WebKit,
CoreAnimation, the main run loop) is only verified by an unfiltered run whose
counts you read.

**"The summary line", singular, is now WRONG on this toolchain, and it was
repeated in more than one place in this section before being caught.** A
current `swift test` (verified 2026-09-03, Swift 6.3.3, six `.testTarget`
declarations in `Package.swift`) prints one summary per test target rather than
one for the whole run:

```
Test run with 47 tests in 0 suites passed after …
Test run with 398 tests in 1 suite passed after …
Test run with 50 tests in 0 suites passed after …
Test run with 6 tests in 0 suites passed after …
Test run with 288 tests in 0 suites passed after …
Test run with 22 tests in 0 suites passed after …
```

47 + 398 + 50 + 6 + 288 + 22 = **811**, the count this file's Build section
quotes — but reading only the instruction's literal "the summary line" sends a
reader to the **last** one printed, which reads **22**. That is not a rounding
error, it is the opposite conclusion from the one the old instruction was
written to support: a reader who trusts it will believe the suite has
collapsed from 811 to 22, which is a false alarm rather than a missed
regression, and the worst possible one — it fires on every single healthy run,
because the last target printed (`MetalUICoreTests`, 22 tests) is always the
smallest. **The instruction's intent is unchanged and still correct — read the
printed counts, never the exit status — only the number of lines to sum
changed.** Sum them instead of reading one:

```
swift test --no-parallel 2>&1 | grep -oE "Test run with [0-9]+ tests" | grep -oE "[0-9]+" | paste -sd+ - | bc
```

**`--no-parallel` is still required, and it is now a separate concern from the
summary-line count rather than the same one.** A tokenizer-counter flake that
failed 8 of 10 plain (parallel) runs was fixed on 2026-09-03 by making the
counter task-local rather than global, but that fix is about test isolation
under concurrency, not about how many lines `swift test` prints; the split into
per-target summaries happens under `--no-parallel` too, as the six lines above
were. Both instructions stand and are independent of each other.

**After editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, run
`swift package clean`.** The header reaches its C target through a symlink SwiftPM
does not track, so Swift's view goes stale while Metal's refreshes — the symptom is
a vanished rect that looks exactly like a shader bug.

**A second, distinct mechanism produces the same class of failure, and it has now
hit three consecutive milestones on this specific signature — four counting the
symlink case above as the family's first member.** Adding a case to a public enum,
or a stored property to a public struct, that crosses module boundaries
(`MetalUILayout` or `MetalUIRender` → `MetalUI`/its test targets) can leave
separately-cached incremental compilations of the two sides disagreeing about the
type's layout or discriminator. **The symptom is not a compile error** — it is
either a `SIGSEGV` or a silent truncation with **no test summary line**, or an
assertion comparing against a value **its own source cannot produce**. The four
occurrences, oldest first:

1. **The symlink case above** — `MetalUIShaderTypes.h` reaching its C target
   through a symlink SwiftPM does not track. A different mechanism with the same
   shape, which is why it is counted as the family's first member and not as an
   instance of this one.
2. **Clipping and scroll, Task 1** — `Scene` gained stored properties; an
   assertion compared against a value its own construction could not have built.
3. **The Stack milestone, twice in one milestone** — a subprocess inside
   `ElementGroupTrapTests`' `#expect(processExitsWith:)` machinery crashed
   deterministically after `Display` gained the `.stack` case, and
   `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` failed because the
   *expected* value it built from a closure containing no reference to `.stack`
   somehow held `display: .stack`.
4. **Absolute positioning, Task 6** — `Scene` gained the `layer` stored property,
   crossing `MetalUIRender` → `MetalUI`. The run truncated mid-suite with no
   summary line, immediately after `bufferIndicesAreStable()` passed. Not chased
   as a logic bug; `swift package clean` and a rebuild gave a clean, repeatable
   561/561.

**`Scene` is the site twice**, which is the closest thing to a predictor this
list offers: it is the one public struct that crosses a module boundary and is
still growing stored properties.

**A third dated instance, 2026-09-10, item scene-arrays:** `Scene`'s private
stored properties changed from two `[PrimitiveKind: [Int]]` dictionaries to four
`[Int]` arrays. Private stored properties still set the public struct's layout,
so this is the same hazard; clean after merging it.

**Also 2026-09-10, item atlas-fold:** `FontKey` (public, `MetalUIText` → `MetalUI`) gained the
stored property `precomputedHash`, so `GlyphKey` and `PlacedGlyph` grew with it. Both this and the
`Scene` change above were cleaned before any test ran — in each fix lane's worktree and again at
integration — so **neither produced an observed failure**. They are recorded as hazards, not as
members of the observed list above, which still has four entries.

Both symptoms point at a code defect; neither is one. `swift package clean`
followed by a full rebuild has resolved it every time, and the isolated change
then passed cleanly and repeatably. **Recognise it by the shape**: an ordinary
Swift source edit (no `.metal`/`.h` touched, so the symlink hazard above is not
it) that produces a crash or a truncation with no summary line, or a test failure
whose *expected* side contains a value its own construction could not have
produced. Try `swift package clean` before debugging the "impossible" result as a
logic bug.

