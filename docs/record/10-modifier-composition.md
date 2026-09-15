## Modifier composition (plan task 3) — `feat/modifier-composition`, from 2026-09-15

The record for plan task 3. Spec
`docs/superpowers/specs/2026-09-15-modifier-composition-design.md`; rulings
`MC-A`…`MC-Q` in
`docs/superpowers/2026-09-15-modifier-composition-decisions.md` (next unused
`MC-R`). The track runs in its own worktree,
`/Users/maxburger/Developer/MetalUI-modifier-composition`, beside two parallel
tracks, and is merged by an integration step that owns `CLAUDE.md`, the plan,
`docs/record/README.md` and the SA decisions doc. **Nothing in this file has
been copied into those yet.**

### Design session, 2026-09-14/15, at `f64e58a`

No source change was committed. What was run, and where its output lives:

| run | result | where recorded |
|---|---|---|
| SwiftUI probe `docs/probes/swiftui-modifier-identity.swift`, `/usr/bin/swift` and compiled `swiftc` | byte-identical stdout, exit 0. Arms: T (types nest), A/B controls, C/D2 value change keeps state, D1/D3 length change resets, E/F/G overlay/background views own distinct state, H control | the probe's header; `MC-A`, `MC-C`, `MC-E` |
| scratch test `scratchMeasureOverlayIdentity` (uncommitted, `--filter`, deleted) | primary and overlay ids **equal**; three clicks on the primary → primary 3, **overlay 3**; hover on the primary → **2** hover fills, 60 and 10pt | `MC-E` |
| the same, with the overlay's cursor threaded from the primary's | ids unequal; primary 3, overlay 0; 1 hover fill (60pt) | `MC-E` |
| whole suite with only that fix, `swift test --build-system native --no-parallel` | `Test run with 1085 tests in 1 suite passed` (1084 + the scratch test); no `error:`, no `warning:` | `MC-E` |
| scratch test `scratchMeasureOrphanLegacyNode` (deleted) | a marker conformer registering an unattached legacy node beside a native leaf renders with no trap: prepaint bounds 10×10, 1 rect | `MC-G` hole 2 |
| typecheck skeleton `docs/probes/modifier-composition-skeletons/FlatChainOverloads.swift` | chains infer `ModifiedElement<Text>`, `ModifiedElement<Two>`, `Row<ModifiedElement<Text>>`; a contextual nested annotation also typechecks. **Superseded at design review**: this overload shape's type-checking time is exponential | the file's header; `MC-A`, `MC-B` |
| typecheck skeleton `TypedNodeKit.swift` + eight clients, plain import, Swift 6 | five lies rejected with named diagnostics; `liar4` and an overriding `requestLayout` compile; `ProposalElement` must restate `associatedtype LayoutState` | the file's header; `MC-G` |

**Restores.** `NativeOverlayModifier.swift` was restored from a `cp` backup
after the fix trial. `git status --short` then showed only the untracked probe
files, and the scratch test file was deleted before commit.

**Toolchains.** macOS 26.6.2 (25G83); `swiftc` Apple Swift 6.3.3
(swift-6.3.3-RELEASE); `/usr/bin/swift` Apple Swift 6.4
(swiftlang-6.4.0.33.1).

### Design review, 2026-09-15, at `f64e58a` (design commit `1c6f686`)

Twelve critic findings, all applied (`MC-N` has each disposition). No source
change was committed. Every scratch test was created in `Tests/MetalUITests/`,
run with `swift test --build-system native --skip-build --filter`, and deleted.
`git status --short` was empty after each deletion.

| run | result | where recorded |
|---|---|---|
| `chain-typecheck-timing.py`: three wrapper designs × 8/12/16/24 modifiers × `Pixels(i)`/integer literals, plus a demo-shaped builder, `xcrun swiftc` 6.4 `-debug-time-function-bodies` | today's nested and the single-overload design both stay at 0.5–2 ms up to 24 modifiers (6 ms for the builder). The first `MC-A` design reads 4.8 ms → 184 ms → **44.9 s** at 8/12/16 `Pixels`, and at 24 integer literals prints "the compiler is unable to type-check this expression in reasonable time" after 6.6 s. The swift.org 6.3.3 cross-check agrees | the script's header; `MC-A` |
| `LayerBaseKit.swift` + five clients, plain import | a chain infers `ModifiedElement<Leaf>` (3 layers); a generic `.padding` over a chain appends (2 layers); the proposal `frame` still wins on a proposal type; the nested spelling is rejected in both forms; the initializer is inaccessible; **the `_wrap` forwarding liar compiles (a hole)** | the file's header; `MC-A`, `MC-B` |
| `CombinedKit.swift`: `TypedNodeKit` + `LayerBase` | the kit builds; all eight typed clients print their recorded diagnostics unchanged; a layered client typechecks; no extra associated-type restatement is needed | the file's header; `MC-A`, `MC-G` |
| `TypedNodeKit.swift` re-run under `xcrun swiftc` 6.4 and PATH `swiftc` 6.3.3 | identical eight results under each (the first recording's toolchain attribution is not established) | the file's header |
| `LayerAllocationModel.swift`, `-Onone`/`-O`, both toolchains, and a `consuming` variant | per chain, swift.org `-Onone`: nested 2/3/4 and flat 2/6/9 for 1/2/3 layers; `-O`: nested 0/0/0 and flat 1/3/4. Construction alone costs k−1 buffers. `consuming` gives identical numbers. Calibration read 16 of 16 (32 under swiftlang `-Onone`) | the file's header; `MC-K` |
| SwiftUI probe `swiftui-modifier-order.swift`, `/usr/bin/swift` and compiled `swiftc` | byte-identical stdout, exit 0, empty stderr. K0 20×20 (0,0); K1 36×36 (8,8); K2 52×52 (16,16); O1 60×60 (20,20); O2 76×76 (28,28); O3 56×56 (18,18); O4 64×64 (22,22) | the probe's header; `MC-L` |
| scratch `zzScratchLegacyModifierOrder` (today's `Box`/`FrameModifier`) | all seven arms equal SwiftUI's numbers | the probe's header; spec lane 1 test 10 |
| scratch `zzScratchDuplicateInOneContainer` | `requestNativeLinearStack(children: [leaf, leaf])`: no trap; stack (60, 0, 20×10); leaf (70, 0, 10×10); measure calls 1; `nodeCount` 4 | `MC-G` hole 4 |
| scratch `zzScratchOneChildTwoContainers` | one leaf in a 30×30 top-leading frame and a 50×50 bottom-trailing frame: no trap; stack (30, 0, 80×50); leaf (100, 40, 10×10); measure calls 2; `nodeCount` 6 | `MC-G` hole 4 |
| scratch `zzScratchOrphanLegacySubtree` | a discarded `Box { StatefulLegacyLeaf() }` laid out through `requestGroupLayout`: no trap; 0 rects; `nodeCount` 5; the orphan `Box`'s `$anim` slot live. With the leaf only declaring `@State` (then only reading it), its `$state0` entry did not exist (`peek` nil). With the leaf writing it 7 → 8 in `requestLayout`: `peek` 8, live | `MC-G` hole 6 |

**Scratch-test fixes along the way**, recorded so the shapes are reproducible:
`pass.fill` takes an `Hsla`, so the orphan leaf's fill resolved its token as
`pass.theme[.accent]`. Two earlier spellings failed to build and ran nothing:
`.accent`, and `pass.theme.resolve(.accent)`.

**Toolchains, corrected.** `xcrun swiftc` and `/usr/bin/swift` report Apple
Swift 6.4 (swiftlang-6.4.0.33.1); PATH `swiftc` (swiftly) reports Apple Swift
6.3.3. The design session's two skeleton headers attributed 6.3.3 to
`xcrun swiftc`, which is not what `xcrun` reports today. `TypedNodeKit.swift`'s
header now says so, and `FlatChainOverloads.swift`'s carries the superseded
note.

### Lanes

*Each lane appends here: its commits, red runs (quoted lines), mutation runs
with the tests each reddened, the suite/guard/golden counts it re-took, and, for
lanes 2 and 3, the demo captures (`MC-J`): image dimensions, differing-pixel
count and coordinates, and the logged pointer position.*

#### Lane 1 — proofs, and the overlay fix, 2026-09-15

**Commits.**

| commit | what |
|---|---|
| `6d89906` | `Tests/MetalUITests/ModifierCompositionProofTests.swift`: the ten tests, red first |
| `6ff2d31` | `Sources/MetalUI/NativeOverlayModifier.swift`: one cursor through primary and overlay, with its doc comment (`MC-E`) |
| `2571d4a` | `Tests/MetalUITests/NativeLayoutIntegrationTests.swift`: four indexed rect counts made `try #require` (`MC-O` item 5) |

Every run below is `swift test --build-system native --no-parallel`, whole
suite, one agent in the worktree, read by its `Test run with N tests` line.

**Red run, at `6d89906`** (tests committed, fix not yet applied): `Test run with
1094 tests in 1 suite failed after 25.299 seconds with 11 issues.` The failing
tests were exactly the four overlay tests; tests 4-8 and 10 were green on
arrival. The issue lines, verbatim apart from truncation:

- `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities()` at `:261`:
  "Expectation failed: (primary → MetalUI.GlobalElementID) != (overlay →
  MetalUI.GlobalElementID)"; at `:262`: "(overlay → MetalUI.GlobalElementID) ==
  (GlobalElementID.child(of: primary.parent, at: 1, name: nil) → …)"; at `:280`
  (the `HStack` arm): "(overlay → …) == (GlobalElementID.child(of: modifier, at:
  1, name: nil) → …)".
- `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState()` at `:312`:
  "(log.taps["overlay"] → 3) == 0"; at `:317`: "(log.taps["primary"] → 4) ==
  3"; at `:318`: "(log.taps["overlay"] → 4) == 1".
- `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay()` at `:349`:
  "(hoverFillWidths() → [60.0, 10.0]) == ([60] → [60.0])"; at `:354`:
  "(hoverFillWidths() → [60.0, 10.0]) == ([10] → [10.0])".
- `anOverlaysIdentityFollowsTheIndicesItsPrimaryConsumed()` at `:836-838`: all
  three readings "Reading(component: Optional(MetalUI.PathComponent.positional(0)),
  taps: Optional(3), indexTwoLive: false)".

A second, identical red run was taken by accident at the same commit (an edit
to the source had not applied): the same 11 issues.

**Green, at `6ff2d31`:** `Test run with 1094 tests in 1 suite passed after
25.380 seconds.` No `error:`, no `warning:`.

**Test 9's measured readings** (first run after the fix, unchanged since):

| step | overlay id component | overlay `taps` | index-2 `$state0` slot live |
|---|---|---|---|
| `flag` true, 3 clicks at (5, 5) | `.positional(2)` | 3 | true |
| `flag` false, one frame | `.positional(1)` | 0 | false |
| `flag` true, one frame | `.positional(2)` | 3 | true |

They equal the spec's prediction.

**Mutations.** Each applied by a script that `cp`-backs up the file, replaces
one anchor that must occur exactly once, appends a `// MUTATION <label>`
marker, runs the whole suite, restores from the backup, and prints
`git status --short` (empty after every run) and a grep for the marker (empty
after every run).

| # | mutation | at | summary line | tests reddened |
|---|---|---|---|---|
| M1 | overlay's second cursor restored | `6ff2d31` | 1094, 11 issues | tests 1, 2, 3, 9 (= the red run) |
| M2 | `FrameModifier.prepaint` registers after its content | `6ff2d31` | 1094, 1 issue | test 4 (hitbox order) |
| M3 | `FrameModifier` content cursor starts at 1 | `6ff2d31` | 1094, 1 issue | test 5 (padding 4 reads `.positional(1)`); **not** test 4 (`MC-O` item 6) |
| M4 | `ModifiedContent` content cursor starts at 1 | `6ff2d31` | 1094, 3 issues | test 6 (three components `.positional(1)`) |
| M5 | `allowsHitTesting` branch prepaints content twice | `6ff2d31` | 1094, 2 issues | test 7: `allowsHitTesting(true)`, `(false)` read `[1, 2, 1]` |
| M6 | `clip` paint branch loses its `else` | `6ff2d31` | 1094, 1 issue | test 7: `clip` reads `[1, 1, 2]` |
| M7 | `OverlayModifier.paint` skips `overlay.paintGroup` | `6ff2d31` | **none: "Fatal error: Index out of range"**, `swiftpm-testing-helper` exited with signal 5 | before the crash: tests 2, 3, 7, 9; the crash was `nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt` indexing after a failed count |
| M7b | M7 again, after `2571d4a` | `2571d4a` | 1094, 8 issues | test 7: `overlay, overlay side` `[1, 1, 0]`; tests 2, 3, 9; `nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt` (`rects.count → 1`) |
| M8 | `FrameModifier.prepaint` calls its content twice | `6ff2d31` | 1094, 3 issues | test 7: `legacy frame`, `legacy three-modifier chain` `[1, 2, 1]`; test 4 (a duplicate leaf hitbox) |
| M9 | `Box.prepaint` registers after its content | `2571d4a` | 1094, 5 issues | test 8 (hitbox order; the in-leaf click ran `outer`); test 4; `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire` |
| M10 | overlay under a reserved `.named("$overlay")` id, own cursor | `2571d4a` | 1094, 5 issues | test 1 (index 0, both arms); test 9 (index 0, 3 taps at every step); tests 2 and 3 stay green |
| M11 | `FrameModifier.init` drops `justifyContent = .center` | `2571d4a` | 1094, 11 issues | test 10 (O1-O4 leaf x 8, 8, 12, 12); test 4; `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`; `chainedFramesRemainConcreteAndNestTheirLayoutNodes` |

M1-M6 and M8 were taken before `2571d4a`, which changed only four count
assertions in `NativeLayoutIntegrationTests.swift`; none of those runs reached
them (each printed its summary line).

**Counts at `2571d4a`.** Tests 1094 (1084 + 10). Guards 45: `grep -c
canTypecheck` reads 19 (`PhaseSeparationTests`), 10 (`ErasureCompileGuards`),
5 (`ElementGroupTrapTests`), 3 (`UnitSafetyTests`, one a comment), 3
(`AXNodeTests`), 6 (`ProposalLayoutCompileGuards`), and 1 in
`Typecheck.swift` (the declaration). Lane 1 adds no guard. Goldens 97 (`find
Tests -name '*.json' | wc -l`); `git diff --stat f64e58a -- '*.json'` empty.

**Final run, after the docs commit's one test doc-comment edit:** `Test run with
1094 tests in 1 suite passed` under `--build-system native`, and again under the
default build system (`swift test --no-parallel`); 0 `error:` and 0 `warning:`
in each log.

**Deferred by lane 1.** Nothing from its spec section. Owed elsewhere: the
proposal `@State` test's `MC-H` mutations (lane 3); every lane-2 mutation named
in the spec's lane 1 table (lane 2); a sweep of other test files for the
shape-13 count-then-index pattern (`MC-O` item 5, not taken).

#### Critic round after lane 1, 2026-09-15 (`MC-P`, `MC-Q`)

Eight findings against `ec65da6`; dispositions in `MC-Q`. Run by the designer,
one agent in the worktree.

**The paused lane-2 skeleton.** The worktree held uncommitted lane-2 skeleton
edits (`ModifiedElement.swift`, `ModifiedElementTests.swift` untracked;
`FrameModifier.swift` staged deleted; `Box.swift`, `ElementGroup.swift`,
`main.swift`, `ComponentTests.swift`, `NativeLayoutIntegrationTests.swift`
modified). Before any build they were copied to the scratchpad
(`lane2-wip-backup/`: a `git diff HEAD` patch and the two untracked files) and
saved with `git stash push -u`; this round built and committed on a tree
without them, and `git stash pop` restored them afterwards. None was edited.
`swift package clean` before the first recorded run, since the skeleton had
deleted and added public types.

**Commits.**

| commit | what |
|---|---|
| `661efd9` | `NativeOverlayModifier.swift`: overlay under `.child(of: id, at: -1)` with its own cursor (`MC-P`) and its doc comment; `ModifierCompositionProofTests.swift`: tests 1 and 9 inverted (9 renamed, P5 control added), test 4's `BoxWithoutAnimated` oracle, test 10's scope doc; `docs/probes/swiftui-overlay-primary-shape.swift` |
| `39f6237` | test 9's readings carry printable path components instead of an opaque `GlobalElementID` (the first R1 run printed `MetalUI.GlobalElementID` on both sides) |
| docs commit | `chain-solver-scope-guard.sh`; spec, decisions (`MC-A`, `MC-B`, `MC-E` struck in place, `MC-G` hole 7, `MC-L`, `MC-M`, new `MC-P`, `MC-Q`), this record |

**Probes.**

| run | result | where recorded |
|---|---|---|
| `swiftui-overlay-primary-shape.swift`, `/usr/bin/swift` 6.4 and compiled `swiftc` 6.3.3 | byte-identical stdout (`cmp`), exit 0, empty stderr. Controls: A 1,1,1; B 2,3,4; P5 `c` 9/absent/11 with `o` 10,10,10; Q 12,13,14. Arms P1–P4: the overlay keeps its serial through the primary's flip (5,5,5 … 8,8,8); every `n=1` | the probe's header; `MC-P` |
| `chain-solver-scope-guard.sh`, `/usr/bin/xcrun swiftc` 6.4 and PATH `swiftc` 6.3.3 | identical under both. Minimum passing `-solver-scope-threshold`, whole-file model: nested and assoc 60/116/172 at 8/16/24; flat 1321 at 8, 338 601 at 16. Two-module guard shape: positive minimum 190; at 1000 positive rc 0, negative rc 1 "unable to type-check this expression in reasonable time" at `client-neg.swift:3:3`, ~0.1 s each; negative fails at every threshold searched up to 10⁶, and at 4 194 304 after 12.8 s (6.4) / 16.2 s (6.3.3). A first attempt mis-split the compiler command under zsh (`$1` holding `"/usr/bin/xcrun swiftc"`), so every 6.4 row read `>4194304`; re-run with `${=1}` and recorded from that run | the script's header; `MC-A`, `MC-Q` finding 3 |

**Whole-suite runs** (`swift test --build-system native --no-parallel`, read by
the summary line; each mutation applied by `mutate.py` in the scratchpad:
`cp` backup, one anchor replaced that must occur exactly once, a `// MUTATION`
marker appended, the suite run, the file restored; `git status --short` and the
marker grep were empty after every run).

| run | at | summary | tests reddened |
|---|---|---|---|
| green, after `swift package clean` | `661efd9` (uncommitted then) | `Test run with 1094 tests in 1 suite passed after 25.081 seconds`; 0 `error:`, 0 `warning:` | — |
| green | `39f6237` (uncommitted then) | `… 1094 tests … passed after 25.138 seconds`; 0 `error:`, 0 `warning:` | — |
| R1 `MC-E`'s threaded cursor restored | `661efd9`, then again at `39f6237` | 1094, 5 issues (both runs) | test 1 at `:267` and `:286`; test 9 at `:932-934`: path `[positional(2), positional(0)]` 3 taps, `[positional(1), positional(0)]` **0** taps, `[positional(2), positional(0)]` 3 taps, `overlayLive: false` each. Tests 2 and 3 green |
| R2 overlay under the modifier's own id, cursor at 0 (the original collision) | `39f6237` | 1094, 11 issues | tests 1 (3 issues), 2 (3), 3 (2), 9 (3; path `[positional(0), positional(0)]`, taps 3) |
| R3 overlay side `.named("$overlay")` | `39f6237` | 1094, 5 issues | test 1 (both arms); test 9 on path (`named("$overlay")`) and id only, taps 3 at every step |
| R4 `FrameModifier.requestLayout` skips `animated` | `39f6237` | 1094, 2 issues | test 4 at `:620` (`chain.animLive → [true, false, true]` vs `[true, true, true]`); `stateSurvivesFramesUnderALegacyModifierChain` at `:663` (an ancestor's `$anim` slot not live) |
| R5 `BoxWithoutAnimated` calls `animated` | `39f6237` | 1094, 1 issue | test 4's `#require` at `:608` (`animSkipped.animLive → [true, true, true]`) |

**Counts after this round.** Tests 1094 (no test added or removed; test 9
renamed). Guards 45, unchanged (no guard added). Goldens 97; `git diff --stat
f64e58a -- '*.json'` empty. Final run before the docs commit, default build system
(`swift test --no-parallel`): `Test run with 1094 tests in 1 suite passed after
25.018 seconds`, 0 `error:`, 0 `warning:`. Guards by `grep -c canTypecheck`:
19, 10, 5, 3 (one a comment), 3, 6, plus the declaration in `Typecheck.swift`
— 45. The overlay probe's script form re-run after its header was written:
stdout identical (`cmp`).

**Not run, by reading only:** `MC-G` hole 7's trap path; the AB-O gap
(`feat/ax-bridge` at `53d3bf6`); the environment facts (`feat/environment` at
`f4dcad8`: `StateReflection.swift:104`, `EnvironmentTests.swift:468`,
`EnvironmentScope.swift`, `docs/record/11-environment.md:258-259`); that no
cursor produces `-1`; the parent walkers' tolerance of the synthetic overlay
ancestor.

### For the integration step

Collected here so the merge does not have to re-derive them:

- **`FrameModifier` is deleted by lane 2.** `CLAUDE.md`'s Animation section
  counts registering sites and `pass.fill` sites; record §09's "It is live in
  three places the per-site guards were written to watch" and "Owed before
  this work is cited as done: `FrameModifier` arms" both change.
- **Record §09's hazard 3 (the overlay id collision) is closed by lane 1**
  (`MC-E`, `6ff2d31`), and plan task 3's open-proof bullet "`OverlayModifier`
  gives its primary element and its overlay element the same id, by reading"
  is measured and fixed. The other two open proofs lane 1 closes on today's
  code: "No test checks `@State` across chained modifiers" (tests 5-6, `MC-D`)
  and "No test checks once-per-phase delegation" (tests 7-8, `MC-F`).
- **An overlay's elements number under a synthetic `.positional(-1)` child of
  the modifier** (`MC-P`, `661efd9`, pinned by
  `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`), so the
  overlay's state is independent of the primary's shape, as SwiftUI's is —
  for CLAUDE.md's identity section. Lane 1's earlier note here, "the overlay's
  index now depends on its primary's index count … the trailing-sibling
  rule", is **withdrawn**: it described `MC-E`'s threaded cursor, which the
  probe `swiftui-overlay-primary-shape.swift` shows diverged from SwiftUI.
- **A practices-doc instance** (shape 13, `MC-O` item 5): a mutation truncated
  the suite through a count `#expect` followed by indexing in
  `NativeLayoutIntegrationTests.swift`; four instances fixed at `2571d4a`.
- **`SA-R`'s amended criterion is met by lane 3** (`MC-G`), with **seven**
  named holes (the design review added holes 4, 5 and 6; the critic round
  after lane 1 added hole 7, a stored typed id, backstopped by C-3's trap). The
  SA decisions doc is not edited by this track.
- **The guard count moves 45 → 47 (lane 2) → 53 (lane 3) by design** (lane 2
  test 6 became a guard after the critic round). Re-count per file. Lane 2's
  test 6 guard passes `-Xfrontend -solver-scope-threshold=T`; CI's toolchain
  must accept that frontend flag.
- **`ElementGroup` gains two defaulted requirements** in lane 2
  (`associatedtype LayerBase = Self`, `_wrap`), and `Element`'s default entry
  calls lane 3's `GroupMember.swift` helper.
- **Collisions with the environment track at `f4dcad8`** (spec merge notes, in
  full; revised after the critic round against that branch's commits):
  1. **`EnvironmentScope: ProposalElementGroup` stops compiling at merge**
     (EV-W names it). The typed entry must resolve once and push, as the
     untyped one does. **The check already exists:** E11
     `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase`
     (`EnvironmentTests.swift:468`, `[7, 7, 7]` under `HStack` and
     `ProposalScrollView`); a bare-forward typed entry reddens its layout slot.
     The test this record previously said was owed is withdrawn.
  2. **`StateBinder.bind(_:in:id:)`** (`StateReflection.swift:104`). Lane 3
     adds no call sites: the helper replaces `ElementGroup.swift:112`, and must
     call `bind(element, in: pass.frame, id: id)`. `Component.swift:130`
     remains that track's own edit. **That track's record
     (`11-environment.md:258-259`) still says this track adds two call sites**;
     integration corrects it.
  3. **`EnvironmentScope` arms owed in `everyModifierWrapperDelegatesEachPhaseExactlyOnce`**,
     legacy and proposal, each `[1, 1, 1]`.
- **AB-O and per-layer hooks (AX-bridge track):** any hook in `Element`'s group
  defaults is mirrored per layer in `ModifiedElement`; AB-O's `display: none`
  suppression moves into one helper called by `Element.prepaintGroup` and per
  layer; the owed test compares `Frame.axEmissions` for
  `Text("x").padding(4).hidden().frame(width: 60)` against hand-built boxes,
  mutation "remove the per-layer call" (spec merge notes).
- **`NativeTappable.swift`:** lane 3's typed `OnTapModifier` entry and AX lane
  3's one-line `OnTapModifier.prepaint` edit conflict textually; keep both.
- **`FrameModifier` in other tracks' lists:**
  - the environment track's D2 "frame" arm;
  - the AX-bridge spec's in-scope emit site and its "untouched" line;
  - the shared arm lists in `InputDispatchTests.swift` and
    `AXEmitSiteTests.swift`.

  **Change each arm to a two-layer `ModifiedElement`; never delete it**
  (`MC-I`).
- **A candidate divergence** (`MC-C`, lane 2 test 5): a layer added to a chain
  at run time is adopted by the new outermost layer, which takes over its
  `$anim` baseline and its hitbox id. No SwiftUI analogue.
- **A new hole** (`MC-A`): an `ElementGroup` conformer that declares
  `LayerBase` and forwards `_wrap` compiles, and its `.padding` drops the
  receiver.
- **`MC-K`'s named cost, for task 4:** about +3 allocations per 2-layer chain
  and +5 per 3-layer chain per frame build, over nested boxes, in the model's
  debug build. Lane 2 re-measures this in the real build.
