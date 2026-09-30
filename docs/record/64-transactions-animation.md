# 64 — Transactions and animation (plan task 13)

Branch `feat/transactions-animation` from `2de0973` (master, plan task 12
part 2 landed, record §63). Spec
`docs/superpowers/specs/2026-09-30-transactions-animation-design.md`;
rulings `AN-X`…`AN-AK` appended to the existing animation decisions doc,
`docs/superpowers/2026-09-03-animation-decisions.md` (next unused `AN-AL`).
Probe `docs/probes/swiftui-transactions-animation.swift` (new; arm ids `C…`
controls, `W…`/`P…` which wrapper animates and as what/whether layout re-runs
mid-flight, `T…` transactions, `X…` transitions, `R…` Reduce Motion;
revision 2 after the critic round added arms X17/X17c).

**Status: LANDED — plan task 13 is TICKED.** All three lanes verified `ok:
true`; this Record phase's independent close (§6) re-took the suite, guard
and golden counts, the fourteen-image comparison, `Backends/SDL`, a
`swift:6.4-noble` container and the lock probe. Every clause of the plan's
task-13 text closes on this branch (§9): modifier wrappers participate in
transactions at their correct phase (lane 2), Reduce Motion is
environment-driven (lane 1's source, lane 3's transition consumer), the
supported transition surface is documented (`AnyTransition`'s doc comment,
`CLAUDE.md`), the layout/paint distinction is retained (`AN-AA`'s rule,
unmoved), and every test drives `simulateTick(timestamp:)` — none sleeps.
Per the spec's own ruling (`AN-AG`), the still-owed real-window capture does
not gate the tick: the plan's text asks for no look, and every behaviour
here is pinned headless.

## §1 Design (2026-09-30, `e46a21d`, critic round `d3013ac`)

**Baseline** re-taken at `2de0973` in this worktree: `swift build
--build-system native --build-tests` 0 `error:`, the one SwiftPM deprecation
`warning:`; unfiltered `swift test --build-system native --no-parallel` →
`Test run with 1880 tests in 3 suites passed after 117.409 seconds`, `FR-J
no-argument frame: succeeded=true` present. 116 guards, 0 goldens, 68 live
divergences, next label 96. The probe ran with the screen locked
(`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`); `CustomAnimation`
is driven by SwiftUI in-process regardless of the lock (control C0), so no
arm depended on it.

**The inventory** (spec §2): `Transaction`, `withTransaction`,
`.transaction(_:)`, `.animation(_:value:)`, `Binding.animation`/
`.transaction`, transitions of any kind, and Reduce Motion were all absent.
Present: `withAnimation`'s pending/parked transaction, the layout helper
`animated(_:_:for:pass:)` (25 `Style` numbers + `cornerRadius`), the paint
helper `animatedColor`/`animatedBackground`, `hasActiveAnimations`, seven
reserved `StateTable` slot names. Snapping: the five paint-only `Decoration`
fields, every proposal `LayoutModifier` (no `$anim`, no record), a caller's
modifier on a `Component` (B-7), `Grid`/`GridRow`/stacks/leaves, an element
returning inside an `if`/loop, a structure change, any `Dimension` case
change.

**What the probe measured** (spec §4, the load-bearing finding): SwiftUI
lays out once at the final values and interpolates each view's *placed
geometry* and *render effects* — a `.frame(width:)` change animates a
geometry pair (W1), a child `Layout` is proposed only the final width (P1),
a re-wrapping `Text` interpolates its geometry and cross-fades its content
(P2), a sibling below a removed view slides (X00). MetalUI keeps
interpolating the *declared input* and re-running layout every frame
(`AN-E`'s existing model, now extended to proposal layers) — the two agree
for a wrapper's own rectangle and differ where a child re-lays out or a
sibling moves. Kept, **divergence 96**, owner none (`AN-X`); switching to
geometry interpolation was considered and rejected — every hitbox,
accessibility frame, clip and scroll region is registered from laid-out
geometry in prepaint, and choosing which geometry each of those consumers
should see is a bigger, unmeasured, must-not-move-adjacent question.

**Thirteen items were addressed to plan task 13** (spec §3, `AN-AF`;
disposed in full at §7 below), plus the project memory's seven
animation-milestone follow-ups (disposed at §8).

**Three lanes, at most, run in order** (`AN-AG`): lane 1 (transactions, the
store, Reduce Motion, the platforms) creates `TransitionStore.swift` as a
stub with the frame's three call sites, which lane 3 owns thereafter; lane 2
(modifier wrappers at their phase); lane 3 (transitions and the surface).
The demo is expected unchanged (0 px against `2de0973`); task 13 is ticked
by the Record phase only if all three lanes land.

## §2 Critic round (2026-09-30, `d3013ac`, ruling `AN-AH`)

One agent, critic and reviser. The probe re-ran byte for byte (all 223
recorded lines, `diff` against the header empty, twice) before the round
appended arms X17/X17c (revision 2, 227 lines, two runs `cmp`-identical).
Six findings, each amending the spec in place:

1. **`.scale`/`.scale(scale:anchor:)` are supported**, refuting the design's
   unmeasured "the renderer has no transform" (shape 14): both Metal's
   `glyph_vertex` and SDL's `replay.hlsl` glyph vertex stage compute
   `atlasPosition` from the primitive's own atlas lanes independently of the
   destination `bounds`, through a linear-filtered sampler — a scaled glyph
   quad resamples its atlas slot cleanly. The mechanism is a post-transform
   of the scene range a `TransitionGroup` emitted.
2. **Content present in the first render, or under a newly evaluated
   parent, is not an insertion** (probe X17/X17c): the design's "not
   produced by the last completed frame" would have faded every
   `.transition`ed conditional on a window's first frame, and every `List`
   row scrolled into its window. Insertion now needs the conditional to
   have been evaluated **last** frame.
3. **The legacy border-colour track lives in the `AnimationStore`, not on an
   eighth `StateTable` slot** — the design's own `$anim-border` would have
   moved `TB-AH`'s eviction point and every pinned table count, on this
   task's own must-not-move list, for no behaviour the store cannot give;
   `AN-AB` already rejects `StateTable` for proposal tracks on the same
   ground. The reserved names stay **seven**.
4. **`TransitionGroup` is identity-transparent**, not a level of its own:
   its captures live in the `AnimationStore` under `.named("$transition")`
   at its position, the same keying `.animation(_:value:)` already uses, so
   no `StateTable` collision and no `@State`/focus/`$anim` reset when
   `.transition` is added.
5. **SwiftUI's conformances** (typechecked in the probe header):
   `Transaction` is neither `Equatable` nor `Sendable`; `AnyTransition` is
   not `Sendable`. MetalUI's `Transaction` drops `Equatable` (additive to add
   later) and keeps `Sendable` on both (required for Swift 6 `static let`s
   and the value-typed stack).
6. **A pin that could not be red** — 3.13's mutation ("let every group
   inside inserted content transition") changes nothing in a tree with no
   `.transition`; re-spelled as "give an unannotated conditional's content a
   default `.opacity` transition".

Plus the migration spelling for `PlatformWindow`'s new pair
(`accessibilityReduceMotion`/`onAccessibilityReduceMotionChange`, no default
implementation, `EV-AB`'s precedent) and three rejections recorded in
`AN-AH` (T11 has no separating arm — refuted, T5 separates it; switch to
geometry interpolation — rejected for `AN-X`'s reason; lane 1 too large —
kept, its platform half shares files with the transaction plumbing).

## §3 Lane 1 — transactions, the store, Reduce Motion, the platforms (2026-09-30)

Commits: red `58ff4ff`, green `f35ecf3`, ruling `60d1ea7`/`AN-AI`; fix round
red `af53882`, green (docs) `d2b5308`.

**Built** (`AN-AI` item 1): `Transaction` (`Sendable`, not `Equatable`),
`withTransaction`, SwiftUI's generic `withAnimation` — both through one
`parkTransaction` (`AN-C`'s predicate byte-for-byte, `disablesAnimations`
parked and rolled back beside the animation); the frame's transaction stack
(`Frame.transactionTop`, `withTransactionScope`), read by both passes'
`transaction`; `TransactionScope<Content>` (transparent, pushes in layout
and paint, a separate typed-entry copy); `.animation(_:value:)`, keyed
`.named("$anim-value<depth>")` in the `AnimationStore`; the store itself
(drops untouched entries at the frame's end; a read marks as a write does);
`TransitionStore`'s stub and the frame's three call sites (lane 3's to
fill); `Binding.transaction`/`animation(_:)`/`transaction(_:)`, with a
source flag (`Binding.stateSource`, set only by `State.projectedValue`) that
every derived binding inherits, so a write through any number of hops still
runs inside the source's transaction; `accessibilityReduceMotion`
(`public internal(set)`), the defaultless `PlatformWindow` pair on AppKit
(`NSWorkspace.accessibilityDisplayShouldReduceMotion`, re-read on its
display-options notification, an injectable `workspaceNotificationCenter`)
and SDL (`false`, never fires — documented, a roadmap item), stamped by
`Window` beside `controlActiveState`.

**112.5 measured as 112** (`AN-AF` item 9, `AN-AI` item 5): mutation 33
re-run on this tree reads `got Optional(112.0)`. Instrumented at
`roundLayout` (not committed): the interpolated width really is 112.5
(`linear(4)` at 0.5 s over 100 → 200), the fixture's `Column` centres it at
x = 93.75, and layout rounds each *edge* — 93.75 → 94, 206.25 → 206 — so the
scene's width is 112. Divergence 77's whole-point rounding; the hypothesis
held. `Animation.swift`'s comment is corrected in place.

**Lane 1's mutation table** (each on the committed tree `f35ecf3`, restored
from a copy, full unfiltered suite of 1898, `git status --short` clean after
every one — 21 rows, `AN-AI` item 6): M1.1–M1.19 and MG1.14/MG1.15 each
redden a named test (the full table is `AN-AI`'s; every clause has a
mutation). `AN-C`'s must-not-move mutations 28–34 were re-run: 31, 33, 34
each reproduce their named figure exactly (200.0, 112.0, 100.0); 28–30
redden **more** issues than the original table recorded, which is the
suite's growth since `b869253` (every window-driven test added since), not
a regression.

**Fix round** (verifier round, `af53882`/`d2b5308`; 1898 → **1901**, +3 new,
one extended): five previously-unpinned clauses now each have a mutation —
V1 (`?? false` → `?? true` in `Frame.scopedTransaction`, a first sighting
would animate) reddens `anAnimationScopesFirstSightingSnapsOverASurvivingBaseline`
alone; V2 (the store never filters at `endFrame`) reddens
`anAnimationScopeThatLeavesForAFrameLeavesTheStore` and 1.3b's set-up
`#require`; V9 (drop the disables-flag rollback in `parkTransaction`) and
V10 (`takeParkedTransaction` stops clearing it) each redden
`aDisablingTransactionReachesExactlyOneBuildAndRollsBack`'s two arms; V5
(`derived` drops the source flag), V11 (the unwrapping initialiser builds a
plain `Binding(get:set:)`) and V12 (the dynamic-member subscript does the
same) each redden `aBindingAnimationAnimatesAStateWrite`'s corresponding
arm. Two new tests (1.3b, 1.12b) plus 1.19's rewording.

**Counts**: `Test run with 1901 tests in 3 suites passed`, guards 118 (+2:
1.14, 1.15, both whole-file `typecheckFile`), 0 goldens. `Backends/SDL`
22 + 33 (M1.18: SDL answers `false` for Reduce Motion, never fires). 0 px
against `2de0973` in all fourteen offscreen images. Cost if wrong (item 4):
a production path that built a frame inside a `withAnimation` body would let
the lexical fallback override a scope's explicit `nil` — untested because
production never reaches that configuration (`pendingTransaction` is
restored before the display link builds).

## §4 Lane 2 — modifier wrappers at their phase (2026-09-30)

Commits: red `220a88c`, green `924fca8`, ruling `df52d29`/`AN-AJ`; fix round
red `40cd873`, green (docs) `b354a59`.

**Built** (`AN-AJ` item 1): `LayoutModifier._requestLayout` rewrites its
numeric case first (`animate(for:pass:)`, `ProposalAnimation.swift`) —
`.frame`'s width/height, `.flexibleFrame`'s six finite bounds, `.padding`'s
four insets, `.opacity`, `.clip`'s radius, `.border`'s width — one
`AnimationStore` entry per layer (`$anim-layer.<case>` under the layer's
id); `_paint` fades `.background` and the border's colour on store token
tracks. The legacy `animated(_:_:for:pass:)` now interpolates
`Decoration.opacity` and the four widths of each of `border`/`hoverBorder`/
`focusBorder` from the existing `$anim` baseline (a border appearing or
vanishing snaps); the resolved legacy border colour runs on a store track
(`$anim-border`, a store key, **not** an eighth `StateTable` slot —
`AN-AH` item 3). `StyledComponent.requestGroupLayout` interpolates each op
(`.padding`, `.width`, `.height`) per member in the store, keyed by the
member index and op index — the member's own `$anim` baseline is never
touched, fixing **B-7** (`AN-AC`): a caller's modifier on a `Component` now
animates through the store, changing arm (c) of
`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` from
snap to animates. Clamps sit where a precondition would otherwise trip on
an overshooting spring: opacity to `0...1`, border widths and frame sizes to
`≥ 0`, a flexible frame's bounds re-ordered `min ≤ ideal ≤ max`.

**One file outside the lane's list**: `Box.swift` gains
`Decoration.setInterpolatedOpacity(_:)` — the per-frame animated value must
keep the caller's declared write order (`escapesOpacity`), so it needs its
own internal setter beside the public, trap-on-out-of-order one.

**No `StateTable` count moved** (`AN-AH` item 3): the whole suite is green
with no table literal re-derived; 2.11 and 2.15 pin that the proposal layers
and the border track mint no `StateTable` entry.

**Mutation 16 re-taken** (`AN-AF` item 11): stage 10 deleted `aspectRatio`
and `Style.border`'s four fields, so "25 of the 28" `Style` assignments
`animated()` interpolates is now **21 of 24** — 52 issues across 15 named
tests (the full list is `AN-AJ` item 6). Strides recorded at their lines
(debug arm64): `Decoration` 128, `Style` 180, `AnimatedElementState` 320,
`AnimatedFieldState` 88, `AnimatedColorState` 120 (`ColorAnimation` 112),
`StoredNumberTracks` 16, a store entry a 32-byte `Any`.

**Lane 2's mutation table** (18 rows + M16, each on the committed tree
`924fca8`, restored from a copy, full unfiltered suite of 1919, `git status
--short` clean after every one — `AN-AJ` item 9): M2.1 (skip the helper for
`.frame`) through M2.18 (key every component member as member 0) each redden
a named test or set (the full table is `AN-AJ`'s); M2.16 (resolve the border
track from the plain field) is the widest, reddening 20 issues across seven
tests, since hover/focus border colour flows through it everywhere.

**Fix round** (`40cd873`/`b354a59`; 1919 → **1929**, +10): pins the four
clamp exit tests plus their separating arm
(`theClampPinsSpringOvershootsPastEachBound`, which measures through
`Animation.value(at:…)` that the spring genuinely overshoots each bound at a
sampled frame) — C1, C2, G, H each reddening the matching test;
`escapesOpacity`'s mid-flight rule (D reddens
`aFillWrittenAfterAnAnimatingOpacityStaysOutsideItMidFlight`); the lexical
fallback, one arm per copy (E1–E3, `aFrameRenderedInsideWithAnimationAnimatesThroughTheLexicalFallback`,
kept though production never reaches the configuration — not ruled
unreachable, since it is the fallback's own direct-render path); hover/focus
border widths (F reddens `aHoverBorderAnimatesItsWidth`/
`aFocusRingAnimatesItsWidth`). **The settled-frame cost, measured**: at
920×560, three settled frames, the demo's tree holds **0** store entries
(legacy, no border drawn, no track ever created); the proposal preview holds
**12**, steady, 0 interpolations. A settled entry costs one key
construction, one dictionary lookup, one `touched` insert, no `set`. No
allocation count taken — **re-owned to plan task 15** with the per-entry
memory harness.

**Counts**: `Test run with 1929 tests in 3 suites passed after 119.008
seconds`, guards 118 unmoved (no guard this lane), 0 goldens. 0 px against
`2de0973` in all fourteen offscreen images, controls non-zero
(`compare.sh 2de0973 924fca8`). `Backends/SDL` 22 + 33 (no source touched).
A `swift:6.4-noble` container: 0 `error:`/`warning:`, 199 + 10 + 22 + 6,
unmoved. Still snapping, unchanged by this lane: `ScrollView`'s own
`cornerRadius` (a stored `Pixels`, never through the helper — MetalUI-only)
and divergence 97's list. Cost if wrong: `setInterpolatedOpacity`'s clamp
(rather than trap) is the one hole a package-internal caller could exploit —
only the animation helper calls it.

## §5 Lane 3 — transitions and the documented surface (2026-09-30)

Commits: red `b6eb0e2`, green `470d1de`, ruling `6f78202`/`AN-AK`; fix round
red `98d04cf`, green (docs) `ed0e3b1`.

**Built** (`AN-AK` item 1, `AnyTransition`): `.identity`, `.opacity`,
`.move(edge:)`, `.slide`, `.offset(x:y:)`, `.scale`/`.scale(scale:anchor:)`,
`.push(from:)`, `.asymmetric(insertion:removal:)`, `.combined(with:)`, for an
`if`'s content, an `if`/`else`/`switch` branch and a `ForEach`/`for` element.
`TransitionGroup` (identity-transparent, `AN-AH` item 4), a `.transition(_:)`
modifier on `Element` and `ProposalElementGroup`. **The transition store
keeps its own two frames; no `StateTable` query was added** (amending the
design's "read before paint through a non-mutating `StateTable` query", item
2): each recording copy — `OptionalGroup`, `EitherGroup`, `ArrayGroup`
(untyped and typed), `ForEach`'s two entries — notes to
`AnimationStore.transitions` beside its existing `StateTable` note, so the
removal set is exactly the evaluated set `ID-C`/`DD-C` already reset, with
no new table entry, reset path or pinned count. Cost: one dictionary write
per frame per conditional, whether or not a `.transition` exists.

**Two files outside the lane's list**: `Frame.swift`'s three emitters
(`fill`, `drawImage`, `drawSprite`) build their primitive into a `let` and
insert it as before **when `transitionScopes` is empty**, otherwise routing
through the open groups innermost-first (each captures, then applies its
effect); plus `clipDepth` and `insertIntoScene` for ghosts.
`ProposalElementGroup.swift` gains the typed copies' notes. `MetalUIScene`
is untouched — the effect applies at emission, not as a scene-range
post-transform.

**Claiming**: a `TransitionGroup` claims its position when its parent is a
unit noted this frame (an `if`'s slot, a branch id, a `ForEach` scope, or a
`for` loop's slot); anything deeper is inert. Two stacked `.transition`s at
one position: the outer claims first, the inner is inert (MetalUI's choice,
unprobed). **A changed `.id(_:)` outside a loop is not a removal** — a
transition applies only to content a conditional or loop inserts/removes,
so an `.id` change on other content transitions nothing (listed unsupported
on the doc comment). **Ghosts paint above their layer**, in the order their
removals began — a ghost replays after the tree paints, on the layer each
primitive had, so within that layer it draws above everything painted this
frame; SwiftUI's own z-order for a removed view is unprobed (spec §6.5's
own stated cost).

**Progress arithmetic**: activeness runs 1 → 0 for an insertion and 0 → 1
for a ghost on the conditional's animation, so springs overshoot and
opacity is clamped to `0...1`. A removal during an insertion starts the
ghost at the insertion's current activeness; an insertion during a removal
starts from the ghost's. A landed ghost is dropped without drawing; a
landed insertion paints identity.

**Lane 3's mutation table** (28 rows + MG3.19, each on the committed tree
`470d1de`, restored from a copy, full unfiltered suite of 1953, `git status
--short` clean after each — `AN-AK` item 8): M3.1 (skip insertion) is
widest, reddening 38 issues across 15 tests; MG3.19 (add `.blurReplace`)
reddens 3.19 alone; the full table is `AN-AK`'s.

**Fix round** (`98d04cf`/`ed0e3b1`; 1953 → **1959**, +6): the reviewer's six
green mutations of the per-primitive rules now each redden a new test —
V1–V3 (a glyph/image/border colour does not fade) and V13 (a ghost captures
only rects) all redden **3.25** (a rich tile — glyph, image, 4-point
separator border, 6-point radii on its accent fill — inserted and removed
under `.opacity`); V4 (points not converted at scale factor 2) reddens
**3.27**; V11/V12 (corner radii/border widths not scaled) redden **3.26**
(the same tile under `.scale`); V5 (an insertion during a removal starts
from 1, not the ghost's progress) reddens **3.28**, the mirror of 3.21; V8
(the inner of two stacked transitions claims and wins) reddens **3.29**,
item 4's stacked rule. **`.id(_:)` outside `.transition` is documented
unsupported, not fixed** (3.30 pins it with the inside spelling as its
control): `IdentifiedGroup` numbers its content under the named id, so a
`TransitionGroup`'s parent is no longer the conditional's unit and its claim
fails — letting the claim see through an `IdentifiedGroup` would rest on an
unprobed SwiftUI claim.

**Counts**: `Test run with 1959 tests in 3 suites passed` (1953 + 6), guards
119 (+1: `MG3.19`'s `theUnsupportedTransitionsDoNotCompile`), 0 goldens. 0 px
against `2de0973` in all fourteen offscreen images. `Backends/SDL` 22 + 33
unmoved. A `swift:6.4-noble` container: 0 `error:`/`warning:`,
199 + 10 + 22, `MetalUILayout` imports only `MetalUICore` unmoved. Cost if
wrong (item 5, the visible one): a ghost overlapping a sibling that moved
into its place draws above it where SwiftUI, by index, may draw below — a
probe arm with an opaque sibling would settle it, unrun here.

## §6 Record phase close (2026-09-30)

All three lanes verified `ok: true`. Independent re-take of the suite,
guard and golden counts, the pixel comparison, `Backends/SDL`, a
`swift:6.4-noble` container and the lock probe.

**Suite**, from a clean tree (`swift package clean`): `swift build
--build-system native --build-tests` → 0 `error:`, the one SwiftPM
deprecation `warning:`. Unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1959 tests in 3 suites passed after
120.416 seconds`**, one summary line, `FR-J no-argument frame:
succeeded=true` present (guards ran). **1959 = 1880 + 21 + 18 + 10 + 24 +
6**: lane 1's 21 (1901 − 1880, its own fix round included), lane 2's 18
(1919 − 1901) then its fix round's 10 (1929 − 1919), lane 3's 24
(1953 − 1929) then its fix round's 6 (1959 − 1953) — matching each lane's
own close, re-verified rather than re-derived.
`goldensUnchanged` for the whole task: 0 goldens throughout (`find
Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0); **no test
retired**; one `@Test` renamed with its answer flipped by ruling
(`theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate` →
`thePaintOnlyDecorationFieldsAnimateAndClipSnaps`, `AN-AA`, `DecorationPaintTests`)
and one retained arm's answer flipped by ruling (arm (c) of
`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, 320/320
→ 196/258, B-7 fixed, `AN-AC`) — both named here by the branch check,
2026-09-30, which found this paragraph omitting them; one mutation-table row
corrected (mutation 16's table row, corrected with the measured 21-of-24/52-issues/15-tests figure,
`AN-AF` item 11), two literal corrections (`Animation.swift`'s `112.5` →
`112.0` comment and its two `AnimationTests.swift` copies, `AN-AF` item 9).
No other `@Test` was added, removed, renamed or changed its answer beyond
the three lanes' own tables and fix rounds.
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theDemoFrameMatchesTheValuesRecordedOnMacOS` and
`theSevenRetentionSlotsAreMutuallyDistinct` all green (independently re-run,
above). `MetalUILayout` imports only `MetalUICore` (one line, unmoved).

**Guards**: `grep -c canTypecheck` across every guard file CLAUDE.md names
(37 files, including the two new `TransactionCompileGuards` and
`TransitionCompileGuards`) reads **120** raw hits, less `UnitSafetyTests`'s
one comment hit = **119**, matching every lane's own close. New this task:
`TransactionCompileGuards` (2, both whole-file `typecheckFile`:
`aScopeCannotWriteReduceMotion`, `aPlatformWindowWithoutTheReduceMotionPairDoesNotCompile`
— lane 1's 1.14/1.15) and `TransitionCompileGuards` (1, whole-file:
`theUnsupportedTransitionsDoNotCompile` — lane 3's 3.19, `MG3.19`). **119 =
116 + 2 + 1**, lane 2 adding none. The `typecheckFile`-based helper count
moves **77 → 80**; the `typecheck`-based helper count stays **39**;
39 + 80 = 119.

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> 2de0973 HEAD` (zsh,
its `${0:A:h}` syntax), independently re-taken by this Record phase:
controls exactly as recorded since stage 9 (light vs dark 1048576, default
vs modal 1031003, default vs animation 454895, f0 vs f3 0, preview
1048576, chrome pair 0, distinct 544 and 216, prod default vs modal 491221,
prod distinct 529, indicator rects 0); **0 differing pixels, scene
identical, in all fourteen images**. `DemoFrameDeterminismTests`'
`Expected.swift` unedited.

**`Backends/SDL`** (`PKG_CONFIG_PATH=$PWD/.accesskit`): `swift build
--build-tests` → 0 `error:` (the `sdl` pkg-config rpath warning and the
SDL3-dylib version notice are this machine's own, present on an unmodified
checkout too); `swift test --skip-build` → **`Test run with 22 tests in 0
suites passed`** then **`Test run with 33 tests in 0 suites passed`** —
**22 + 33** — one more than `2de0973`'s 22 + 32: lane 1's
`anSDLWindowReportsNoReduceMotion` (`SDLReduceMotionTests.swift`, the only
`Backends/SDL` test this task adds; branch check, 2026-09-30).

**A `swift:6.4-noble` (aarch64) container** (`docker run --rm -v "$PWD":/work
-w /work swift:6.4-noble …`): the root package builds with 0
`error:`/`warning:` and runs `MetalUILayoutTests` **199**,
`MetalUICrossPlatformTests` **10**, `MetalUICoreTests` **22** — **199 + 10 +
22**, unmoved since record §63 (no lane of this task adds a test to those three
suites; every source file it edits is under `Sources/MetalUI`,
`Sources/MetalUIAppKit` and `Sources/MetalUIPlatform`'s Reduce Motion pair —
`MetalUI` and `MetalUIPlatform` **are** portable targets, built on Linux and
Windows since `XP-A`, so the container's 0 `error:`/`warning:` build is what
shows the new transaction, store and transition code compiles off Apple;
corrected by the branch check, 2026-09-30, which re-took the container:
0 `error:`/`warning:`, 199 + 10 + 22).

**Lock probe**: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` at
this close, as at every check across design, the critic round and all three
lanes — `docs/probes/window-capture/capture.sh` was never run this task.
The transitions, Reduce Motion's cross-fade and `.scale`'s soft mid-flight
glyphs join the still-open real-window capture as looks a human owes (§8;
record §03).

## §7 Items addressed to plan task 13, disposed (spec §3, `AN-AF`)

| # | item | disposition |
|---|---|---|
| 1 | proposal animation ("animation on proposal wrappers, wrappers joining transactions") | **built**, lane 2 (`AN-AB`) |
| 2 | the five paint-only `Decoration` fields snap | **built** for `opacity` and the three borders; `clipsContent` **snaps by ruling** (a `Bool` has no midpoint; SwiftUI's only animation of an added clip is the default cross-fade of a structure change). Lane 2 (`AN-AA`) |
| 3 | the `$anim` end-to-end per-entry figures | **re-taken by lane 2** as `MemoryLayout` strides of every retention payload; the isolated-process per-entry harness **re-owned to plan task 15** |
| 4 | Reduce Motion as an environment key; system accessibility settings | Reduce Motion **built**, lane 1 (`AN-AD`). Increase Contrast and the other system settings **re-owned to plan task 15** — task 13's text names Reduce Motion only |
| 5 | `Binding.transaction`/`animation(_:)` | **built**, lane 1 (`AN-Z`) |
| 6 | animated `scrollTo`/an animated scroll offset | **kept snapping, re-owned to plan task 15**, SwiftUI unmeasured (AppKit scrolling, invisible to the recorder); listed unsupported |
| 7 | followup: `aTransactionWhoseBodyDirtiesNothing…` wants a `try #require` | lane 1 |
| 8 | followup: `Window.aFrameBuildIsPending` prunes while reading | lane 1, split and pinned (test 1.19) |
| 9 | followup: `112.5` reads `112.0` | lane 1 re-runs mutation 33, corrects `Animation.swift`; lane 2 corrects the two test lines; mechanism measured (§3 above) |
| 10 | followup: the guards run only under `--build-system native` | **re-owned to plan task 15** |
| 11 | followup: decisions doc mutation table row 16 omits its post-fixture re-take | lane 2 re-takes it; this record corrects the row (§4 above) |
| 12 | followup: the animation spec's §3 "all thirteen animating tests green" is uncaveated | this record adds `AN-B`'s lower-bound caveat |
| 13 | followup: `CLAUDE.md`'s dated-counts line cites `b869253` | **already gone** — `CLAUDE.md` was rewritten 2026-09-21; frozen §19 keeps it by design |
| 14 | followup "also open": the spring's overshoot and the reverse direction | **already closed** 2026-09-10 by a scripted measurement (record §19); the re-take stays a human look (record §03), not this task's |
| 15 | `AN-W`'s unmeasured nesting/two-calls items | **now measured** (T9, T10): SwiftUI attributes each write to its own call; MetalUI's one-transaction-per-build does not — **divergence 99**, kept (`AN-Y`) |

## §8 The seven animation-milestone follow-ups, disposed

(`~/.claude/projects/-Users-maxburger-Developer-MetalUI/memory/animation-followups.md`,
recorded 2026-09-10; each is item 7–13 of §7's table above, restated by its
own wording and marked here for the memory file's own edit.)

1. `aTransactionWhoseBodyDirtiesNothing…`'s missing `try #require` — **closed**, lane 1.
2. `Window.aFrameBuildIsPending` pruning while reading — **closed**, lane 1 (test 1.19).
3. `112.5` at `Animation.swift:553` and twice in `AnimationTests.swift` — **closed**, measured as `112.0` with its mechanism (edge rounding, divergence 77) rather than merely asserted.
4. The guards running only under `--build-system native` — **re-owned to plan task 15**; `CLAUDE.md`'s hazard paragraph stays.
5. The decisions doc's mutation table row 16 omitting its post-fixture re-take — **closed**, this record.
6. The animation spec's uncaveated "all thirteen animating tests green" — **closed**, this record.
7. `CLAUDE.md`'s dated-counts line citing `b869253` — **already moot**, `CLAUDE.md` was rewritten 2026-09-21.
8. The "also open" spring overshoot/reverse-direction look — **already closed** 2026-09-10 (record §19); the re-take is a human look, record §03, not this task's.

All eight (the file's four code items plus its three doc items plus the
"also open" note) are disposed; none is re-derived from scratch by a later
reader.

## §9 The plan's clauses, closed (spec §9, this record's own check)

| clause | closed by |
|---|---|
| modifier wrappers participate in transactions at their correct phase | lane 2 (legacy paint-only fields, proposal layers, component ops) on lane 1's transaction stack and `.animation(_:value:)`/`.transaction` |
| environment-driven Reduce Motion | lane 1 (environment, platforms), lane 3 (what it changes: transitions) |
| document the supported transition surface | lane 3 (`AnyTransition`'s doc comment), this record (`CLAUDE.md`) |
| retain the layout/paint distinction | `AN-AA`'s phase rule; `AN-F` untouched |
| timestamps, not sleeps | every test drives `simulateTick(timestamp:)`; grep of the new test files for `sleep(` is empty |

**Every clause closes. Plan task 13 is ticked** by this Record phase
(`AN-AG`'s own criterion: all three lanes land; human looks do not gate the
tick, since the plan's text asks for none and every behaviour here is
pinned headless).

## §10 Divergences, declared-but-inert, and human looks (for CLAUDE.md and records 03/04/05)

**Divergences** (record §04's own dated section, added by this task, spec
§10): **96 added, kept, owner none** (geometry vs input interpolation —
SwiftUI lays out once at final values and interpolates placed geometry and
render effects; MetalUI interpolates the declared input and re-runs layout
every frame — probes W1/W11/P1/P2/X00, `AN-X`); **97 added, kept, owner
none** (what still snaps where SwiftUI animates: `nil` ↔ value, finite ↔
infinite, `fixedSize`, `layoutPriority`, `aspectRatio`,
`allowsHitTesting`, alignment, a `clipShape`'s shape — §6.3's list,
`AN-AB`); **98 added, kept, owner none** (no default transition — SwiftUI
cross-fades an unannotated insertion/removal, MetalUI's is instant — a
default would make every conditional in every tree capture primitives every
frame for a ghost it almost never draws, `AN-AE`); **99 added, kept, owner
none** (one transaction per build — SwiftUI attributes each write to its own
`withAnimation`/`.animation` call, T9/T10; MetalUI's frame rebuild cannot
attribute a write to its call, so nested/sequential calls share the one
parked curve — `.animation(_:value:)` is the per-value remedy, `AN-Y`). None
retires. Live **68 → 72**, next label **100**.

**Declared but inert**: **no row added** (record §05's own dated section,
spec §10) — `EnvironmentValues.accessibilityReduceMotion` is read by the
transition code (and by `propertyAnimationsRunUnchangedUnderReduceMotion`'s
own set-up), so it is not inert; `ScrollIndicatorVisibility`'s cases were
already wired at plan task 10 part 1 and are untouched here.

**Human looks owed** (record §03's own dated section): the transitions, the
Reduce Motion cross-fade, and `.scale`'s soft mid-flight glyphs join the
still-open real-window capture — the lock probe read locked at every check
across design, the critic round, all three lanes and this close, so
`capture.sh` was never run this task. None of the looks named at earlier
tasks are closed or reopened by this one.

## §11 Deferred, with owners

- **The isolated-process per-entry memory harness** (item 3) and **the
  allocation count for a settled-frame store entry** (lane 2's fix round)
  — owner plan task 15, alongside the arithmetic bound already carried.
- **Increase Contrast and the other system accessibility settings**
  (`colorSchemeContrast`, reduce transparency, differentiate without
  colour) — owner plan task 15; each needs its own probe and a consumer
  (the theme) this task does not touch.
- **An animated scroll offset / animated `scrollTo`** — owner plan task 15,
  SwiftUI unmeasured (AppKit's own scrolling is invisible to the in-process
  recorder); listed unsupported on the relevant doc comment.
- **The typecheck guards running only under `--build-system native`** —
  owner plan task 15; `CLAUDE.md`'s hazard paragraph is unchanged.
- **A ghost's paint order among siblings** (lane 3's own cost, item 5): a
  ghost draws above everything painted this frame on its own layer, which
  may disagree with SwiftUI's by-index order for an opaque sibling moving
  into its place — unprobed; owner none.
- **Two stacked `.transition`s: the outer claims, the inner is inert** —
  MetalUI's own choice, unprobed against SwiftUI; owner none.
- **`.id(_:)` written outside `.transition`** — documented unsupported
  (3.30), not fixed; letting the claim see through an `IdentifiedGroup`
  rests on an unprobed SwiftUI claim; owner none.
- **Divergence 99's nested/sequential-transaction gap** — `.animation(_:value:)`
  is the per-value remedy and matches SwiftUI; the gap itself (MetalUI
  cannot attribute one write to one call) has no owner, since attributing
  writes to calls is a different architecture.

## §12 CLAUDE.md, plan and record updates made alongside this record

See the commit that carries this file for the full diff. In short:
`CLAUDE.md` gains the counts entry below; the `AN-` prefix's next-unused
letter moves to `AN-AL`; the record map gains this file (§64); the
"Animation (`AN-`)" paragraph is rewritten for the narrowed snap list,
`Transaction`/`withTransaction`/`.animation(_:value:)`/`.transaction`, the
`Binding.animation`/`.transaction` clause, Reduce Motion beside
`controlActiveState`/`displayScale`, and a new transitions paragraph naming
the supported/unsupported surface; the guard list gains
`TransactionCompileGuards` and `TransitionCompileGuards`, and the
`typecheckFile` helper count moves 77 → 80. `docs/record/04-divergences.md`,
`05-declared-but-inert.md` and `03-verified-on-real-hardware.md` each gain a
dated 2026-09-30 section (§10 above is their content). `docs/record/README.md`
gains a row for this file. The plan's task 13 entry is **ticked**, with a
dated progress note. The top-level `README.md`'s milestones paragraph and
divergence count move task 13 from "Open" to "Done" and 68 → 72. The
`animation-followups` memory file is marked disposed in full (§8 above).
`cp CLAUDE.md AGENTS.md` and `cmp` confirm byte-identity.

## §13 Counts (final, this task)

**1959 tests, 0 goldens, 119 typecheck guards**, 0 `error:` on both build
systems, the one `warning:` SwiftPM's deprecation notice under native (0
under the default one). `1959 = 1880 + 21 + 18 + 10 + 24 + 6` (lane totals
above, §6). `Backends/SDL` **22 + 33** on macOS. A `swift:6.4-noble`
container: root package 0 `error:`/`warning:`, runs **199 + 10 + 22**. 0 px
against `2de0973` in all fourteen offscreen images. Live divergences
**68 → 72**, next label **100**. Real-window capture: locked at every check
this task; the still-open capture gains three more states (transitions,
Reduce Motion's cross-fade, `.scale`'s soft glyphs), all owed. **Plan task
13 is ticked.**
