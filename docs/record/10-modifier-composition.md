## Modifier composition (plan task 3) — `feat/modifier-composition`, from 2026-09-15

The record for plan task 3. Spec
`docs/superpowers/specs/2026-09-15-modifier-composition-design.md`; rulings
`MC-A`…`MC-S` in
`docs/superpowers/2026-09-15-modifier-composition-decisions.md` (next unused
`MC-T`). The track runs in its own worktree,
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

#### Verifier-fix round after lane 1, 2026-09-15 (from `14d53d9`)

The lane-1 verifier could run nothing (Bash was blocked partway) and returned
two blockers and three minors. What was done:

- **Blocker, uncommitted lane-2 edits in the worktree.** `git status --short`
  at the start of this round showed the eight lane-2 paths the verifier listed
  (`Box.swift`, `ElementGroup.swift`, `FrameModifier.swift` deleted,
  `main.swift`, `ComponentTests.swift`, `NativeLayoutIntegrationTests.swift`
  modified; `ModifiedElement.swift`, `ModifiedElementTests.swift` untracked);
  no process was running in this worktree. They were set aside, not
  discarded: `git stash push -u -m "lane-2 WIP (ModifiedElement) set aside for
  lane-1 verification fixes, 2026-09-15"`, with a `git diff` patch and copies
  of the two untracked files in the session scratchpad first. **The stash is
  left in place** (`git stash list`); lane 2 resumes with `git stash pop`.
  Every measurement below is lane 1's tree with no lane-2 edit in it.
- **Blocker, nothing was run.** Re-taken in this round, on this tree:
  `swift build --build-system native` (so the guards run against current
  modules), then `swift test --no-parallel`: `Test run with 1095 tests in 1
  suite passed after 25.587 seconds`, 0 `error:`, 0 `warning:` (1094 plus
  test 11). Goldens 97, `git diff --stat f64e58a -- '*.json'` empty. Guards
  by `grep -c canTypecheck`: 19, 10, 5, 3 (one a comment), 3, 6 — 45, no
  guard added. Overlay mutations, each applied to
  `NativeOverlayModifier.swift`, run with `--filter
  ModifierCompositionProofTests` (11 tests), the file restored from a copy and
  `git status --short` showing only the test file afterwards:

  | mutation | issues | tests reddened |
  |---|---|---|
  | R2 overlay under the modifier's own id, cursor at 0 | 12 | test 1 at `:266`, `:268`, `:287`; test 2 at `:320`, `:325`, `:326`; test 3 at `:357`, `:362`; test 9 at `:933-935`; test 11 at `:1092` (its structural `#expect`) |
  | R1 `MC-E`'s threaded cursor (`overlaySide = id`, `at: &contentCursor`) | 6 | test 1 at `:268`, `:287`; test 9 at `:933-935`; test 11 at `:1092` only — its bubble assertion stays green, as it should: the overlay is still a descendant of the holder. Tests 2 and 3 green. One `warning:` (the unused `overlayCursor`), mutant only |
  | M12 overlay-side id detached, `.child(of: nil, at: -1)` | 7 | test 1 at `:268`, `:287`; test 9 at `:933-935` (`overlayLive: false`); **test 11 at `:1092` and `:1110`: events `["overlay saw x"]`, the holder never saw the key** |

  **Line numbers moved by +1 from this round on** (one header line added):
  the `:267`/`:286`/`:932-934` citations in the critic round's table are
  correct at `39f6237` and read `:268`/`:287`/`:933-935` here. M2-M11 and
  R3-R5 were **not** re-taken in this round.
- **Minor, red-run line numbers.** No code change; cite R1/R2 at `39f6237`
  (critic round) or this round, not lane 1's `6d89906` red run at
  `:836-838`, as test 9's red-first evidence.
- **Minor, the synthetic ancestor's walkers.** Added test 11,
  `aKeyAFocusedOverlayDeclinesBubblesThroughTheOverlaySideIDToItsHolder`: a
  node-less `KeyHandling` wrapper (`OnTapModifier`'s shape) holds a primary
  whose overlay is a focusable `KeyHandling` claiming only `o`; the holder
  claims `x`. Real `Window`, `Window.focus`, a confirming frame, `keyDown`
  through `simulateInput`. Green on arrival (a coverage gap, not a defect);
  the M12 row above is its red. Its structural check is an `#expect`, not a
  `#require`, so a detached id reports the behavioural failure too rather than
  stopping at the structure. **Still owed:** an AX-emitting arm, at merge with
  `feat/ax-bridge` (MC-P's cost list). For the sweep, `grep -n parent
  Sources/MetalUI/StateTable.swift` finds only a comment (`:37`), so nothing
  there walks ancestry — a grep, not a run; test 9's `overlayLive`
  is the run evidence that the overlay's slots stay live.
- **Minor, stale MARK.** `// MARK: - 1-3: the overlay's identity (ruling MC-E
  as revised by MC-P)`; the file header now lists test 11.

No `Sources/` file changed in this round, so the demo capture was not
re-taken.

#### Lane 2 — `ModifiedElement`, 2026-09-15 (from `b675451`)

One agent in the worktree. The lane-2 skeleton was restored from `git stash pop`
(the verifier round had left it stashed). The session was locked with the
display asleep for the whole lane. Toolchains as above: the suite and PATH
`swiftc` are swift.org 6.3.3; `xcrun` is Apple Swift 6.4.

**Commits.**

| commit | what |
|---|---|
| `e9248c3` | skeleton `ModifiedElement.swift` (flat type, outermost-only phases), `FrameModifier.swift` deleted, `Box.swift`'s two `padding` signatures and docs, `ElementGroup.swift`'s `LayerBase`/`_wrap`; `ModifiedElementTests.swift` tests 1–5; `ModifiedElementCompileGuards.swift` guards 6 and 7; `Typecheck.swift`'s `typecheckFile(_:importing:frontendArguments:)`; six `MC-I` arms; `ComponentTests`, `NativeLayoutIntegrationTests` and `main.swift` doc/type lines — red |
| `5fe5a30` | `ModifiedElement`'s real phases; `aModifierChainAllocatesABoundedAmountOverNestedBoxes` |
| `49270c7` | test 2's flat padding-8 spelled with `Edges` (`MC-R` item 3) |
| docs commit | doc comments at the lines the mutations taught (`ModifiedElementTests`, `ModifiedElementCompileGuards`, `ModifierCompositionProofTests`); spec; `MC-A`/`MC-B`/`MC-C`/`MC-I`/`MC-J`/`MC-K` Mutations lines; `MC-R`; this section |

**Red run on skeleton S1** (`e9248c3`, `swift test --build-system native
--no-parallel`): `Test run with 1102 tests in 1 suite failed after 27.193
seconds with 40 issues.` Issue lines, abbreviated:

- `aGenericWrapOverAChainIsIdenticalToTheFlatChain` (test 2), 14 issues at
  `:389-395` for both chains: leaf id; leaf bounds (8, 90) 20×20; hitboxes
  `[positional(0)@0,82 36x36, positional(0)@8,90 20x20]` against the oracle's
  `[@0,72 76x56, @8,80 60x40, @28,90 20x20]`; rects; `nodeCount → 3 == 5`;
  layer ids; `animLive → [true]` against `[true, true, true]`.
- `addingALayerAtRunTimeResetsTheWrappedElementsState` (test 3) at `:439`
  (the content did not move a level) and `:441` `(log.taps["leaf"] → 3) == 0`.
- `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` (test 5) at `:543-548`:
  `atStart → 4.0 == 8`, `halfway → 6.0 == 10`, `settled → 8.0 == 12`,
  `p0LiveAtOne → false`, `taps → 3 == 0`.
- `legacyModifierChainsInferOneConcreteType` (test 1) at `:278`
  `(frame.tree.nodeCount → 3) == 4` — only its node-count half; its type names
  were green on the flat skeleton.
- The six `MC-I` inner arms: `AXEmitSiteTests.swift:147` (no node emitted);
  `AnimationTests.swift:1064` `(start?.inner == .pixels(4) → false)`;
  `AnimationTests.swift:2697` `(frame.scene.rects → []).first → nil`;
  `BackgroundChainTests.swift:49` (no 40×40 rect), in both guards;
  `InputDispatchTests.swift:367` `(log.names → []) == (["modified inner layer"])`.
- Lane 1's `aModifierChainIsIdenticalToHandBuiltNestedBoxes` (7 issues, the
  same observations), `stateSurvivesFramesUnderALegacyModifierChain` at `:658`
  (no third ancestor), `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` at
  `:998` (`o3 → 36.0x36.0 at (8.0, 8.0)) != (o4 → …)` — its `#require`).
- Existing: `chainedFramesRemainConcreteAndNestTheirLayoutNodes`
  `(nodeCount → 4) == 5`; `chainedPaddingCreatesNestedWrappers`
  `(nodeCount → 3) == 4` and the leaf at (8, 15) against (12, 15).

A first S1 run read the same 40 issues with one `warning: no calls to throwing
functions occur within 'try' expression` in the new style arm; the arm was
rewritten twice (`MC-R` item 7) before the recorded run.

**Skeleton S2** (uncommitted; `MC-R` item 1): `swift build --build-system
native --build-tests` failed at `ComponentTests.swift:644:53` ("cannot convert
result builder result type 'ModifiedElement<ModifiedElement<TwoLeaves>>' to
return type 'ModifiedElement<TwoLeaves>'") and at `ModifiedElementTests.swift`
`:271:69`, `:273:52`, `:301:37`, `:311:33`, `:408:23` (each "cannot assign
value of type" / "cannot convert return expression of type" a nested
`ModifiedElement`). With that file moved aside and the stored type patched,
`--filter ModifiedElementCompileGuards`: `Test run with 2 tests in 0 suites
failed … with 1 issue`, at `ModifiedElementCompileGuards.swift:155`
(`genericFlat.succeeded != genericNested.succeeded → false`); printed
"annotated succeeded=true messages=[]", "generic nested succeeded=false
messages=[cannot convert return expression of type 'ModifiedElement<T.LayerBase>'
to return type 'ModifiedElement<T>']", and the positive's `use()` rejected with
"cannot convert return expression of type 'ModifiedElement<ModifiedElement<Leaf>>'
to return type 'ModifiedElement<Leaf>'". Guard 6 green on S2. Both files
restored from `cp` copies; `git status --short` showed only the lane's
uncommitted files, no marker.

**Green**, after `swift package clean` (a public type deleted, two requirements
added): `Test run with 1102 tests in 1 suite passed after 26.876 seconds`, 0
`error:`, 0 `warning:` besides SwiftPM's deprecation notice; both guards'
printed diagnostics present. With the allocation test (`5fe5a30`): `Test run
with 1103 tests in 1 suite passed after 27.608 seconds`.

**Mutations** (`49270c7`, each `swift test --build-system native --no-parallel`
whole suite by `mutate.py` in the scratchpad: `cp` backup, each anchor replaced
exactly once, a `// MC2-MUTATION <label>` marker, restore; `git status --short`
empty and the marker grep empty after all 19). Every run printed its summary
line; issue lines are quoted in the rulings.

| # | mutation | summary | tests reddened |
|---|---|---|---|
| T1 | concrete `padding(_: Pixels) -> ModifiedElement<Self>` on `ModifiedElement` | 1103, 4 issues | test 1 (`ModifiedElement<ModifiedElement<ChainComp>>`); guard 7; guard 6 (the positive now exceeds 1000 scopes) |
| T2 | `_wrap` replaces `outermost` instead of appending | 1103, 29 issues | tests 1, 2, 3, 5; lane 1 tests 4, 5, 10; all six `MC-I` guards; `chainedFramesRemainConcreteAndNestTheirLayoutNodes`, `chainedPaddingCreatesNestedWrappers` |
| T3 | content laid out under the outermost id | 1103, 17 issues | tests 2, 3, 5; lane 1 tests 4, 5; the style guard's inner arm |
| T4 | unnamed inner layer named by its style | 1103, 17 issues | tests 2, 4, 5; lane 1 tests 4, 5; the style and AX guards; the allocation test |
| T5 | outermost id keyed on the layer count | 1103, 12 issues | test 5 (betweenness `#require` at `:545`); tests 2, 3; lane 1 tests 4, 5 |
| T5b | test 5's `setNeedsRedraw()` moved out of the `withAnimation` body | 1103, 1 issue | test 5 alone (`:545`) |
| T6 | the first design's three overloads in `ModifiedElement.swift` | 1103, 1 issue | guard 6 alone ("fixture.swift:21:5: error: the compiler is unable to type-check this expression in reasonable time") |
| I1 | inner layers skip `animated` | 1103, 7 issues | the style guard (inner); tests 2, 5; lane 1 tests 4, 5 |
| I2 | inner layers resolve the background token without `animatedBackground` | 1103, 15 issues | `everyBackgroundPaintingSiteAnimatesItsColour`, `…HonoursHoverAndFocus`, `…FadesItsResolvedHoverAndFocusColour` |
| I3 | inner layers skip `registerHandlers` | 1103, 7 issues | the click, AX and both `BackgroundChainTests` guards; tests 2; lane 1 test 4 |
| L1 | inner layers take the outermost id | 1103, 13 issues | tests 2, 5; lane 1 tests 4, 5; the style, AX and hover-fade guards |
| L2 | `.id` lands on the wrong layer | 1103, 9 issues | test 2; lane 1 test 4 |
| L3 | layers registered innermost-first, before the content | 1103, 3 issues | test 2; lane 1 test 4 |
| L4 | a layer registers after everything inside it | 1103, 5 issues | test 2; lane 1 tests 4, 8 |
| L5 | fills painted after the content (NOT the inner loop reversed; see N8) | 1103, 4 issues | test 2; lane 1 tests 4, 8 |
| L6 | content painted once per inner layer | 1103, 4 issues | test 2; lane 1 tests 4, 7 (chain arm `[1, 1, 3]`) |
| L7 | layer styles minted outermost-first | 1103, 25 issues | tests 2, 5; lane 1 tests 4, 10 (O1/O2 swapped); the style, AX and both `BackgroundChainTests` guards; `chainedFramesRemainConcreteAndNestTheirLayoutNodes`; the allocation test |
| K1 | a `requestLayout`-local array of every layer | 1103, 3 issues | the allocation test's three arms (one-layer 18 002 vs 17 002) |
| K2 | one extra array over the inner layers per `requestLayout` | 1103, 2 issues | the allocation test's two- and three-layer arms only |

**Test 5's measured readings**, implementation: x = 8 at t = 0, 10 at t = 0.5,
12 settled; `P`'s `$anim` slot live at both generations; `P/0`'s not live at
generation 0, live at generation 1; taps 0. The prediction exactly.

**Solver-scope threshold** (guard 6), binary search of the positive fixture
against the real module: **186** under PATH `swiftc` 6.3.3 (package modules)
and under `xcrun swiftc` 6.4 (a scratch-path `MetalUI` built by 6.4). The
negative (`+ firstDesignOverloads`) exited 1 at 500, 1000, 2000 and 5000 under
both. At the default threshold the negative took 5.79 s and failed; the
positive 0.15 s. At 1000: positive rc 0, 0.16 s; negative rc 1, 0.16 s,
"neg.swift:22:5: error: the compiler is unable to type-check this expression in
reasonable time".

**Type-check time** (`-warn-long-expression-type-checking=100`,
`-warn-long-function-bodies=100`, parallel builds): `f64e58a`'s demo and this
lane's demo print no warning; this lane's tests print 44 distinct lines and
`b675451`'s tests 35, none an expression containing a `.padding`/`.frame`
chain. Chain-containing function bodies: `aModifierChainIsIdenticalToHandBuiltNestedBoxes`
207 → 228 ms, `everyRegisteringSiteAnimatesItsStyle` 100/110 → 128/136 ms (an
arm added), `stateSurvivesFramesUnderAProposalModifierChain` 100 → 112 ms; new:
`aGenericWrapOverAChainIsIdenticalToTheFlatChain` 184 ms,
`aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` 122 ms. Unrelated bodies
moved by similar amounts (`NestedClipTests` 127 → 181 ms), so this is
contention, not a measured regression (`MC-A`).

**Allocations** (`MC-K`): per 500 builds, 6.3.3: nested 17 002 / 27 001 /
37 004, flat 17 002 / 28 501 / 39 504 (+0, +3, +5 per chain); 6.4: nested
17 502 / 27 501 / 37 504, flat 17 502 / 29 501 / 41 004 (+0, +4, +7), the
strict half reported NOT CHECKED (loop floor 67). **Parallel hazard**, measured:
`xcrun swift test --scratch-path … --filter
"aModifierChainAllocatesABoundedAmountOverNestedBoxes|freezeLoopAllocationsDoNotGrow"`
WITHOUT `--no-parallel` failed `freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine`
at its calibration `#require`; with `--no-parallel` both passed. One whole-suite
run without `--no-parallel` (6.3.3): `Test run with 1103 tests in 1 suite
passed after 12.820 seconds` (`MC-R` item 6).

**The default demo (`MC-J`): the window capture was NOT taken.**

- Baseline: `git archive f64e58a` into the scratchpad (`mc-base`; the shader
  header symlink present), `swift build -c release --product MetalUIDemo`:
  "Build of product 'MetalUIDemo' complete! (35.33s)".
- Launched (no input sent, pointer not moved; pointer (1090.18, 339.99) before
  each launch): window 828×533 at (614, 259), not frontmost.
  `screencapture -x -R614,259,828,533` → "could not create image from rect";
  `screencapture -x -o -l<id>` → "could not create image from window"; a full
  `screencapture -x` wrote a 4112×2658 all-black PNG. `CGSSessionScreenIsLocked`
  1, `CGDisplayIsAsleep` 1, `CGPreflightScreenCaptureAccess` true; re-checked
  later in the lane, unchanged. No capture of either build exists.
- **Stand-in: offscreen scene dumps.** Scratch copies of `f64e58a` and
  `49270c7`, each `main.swift` given `@testable import MetalUI`,
  `import MetalUIText`, `import MetalUIRender` and its final `try runDemo()`
  replaced by a harness rendering `demoContent()` through `Frame` (920×560,
  scale 2, three frames each under light and dark, one shared state table,
  shaping cache and atlas) and printing every `MUIRect`, `MUIGlyph` and hitbox.
  Debug builds. Output: 18 838 lines each, `cmp` identical. Frame 0: 2036
  nodes, 518 rects, 15 711 glyphs, 3 hitboxes; frames after: 60 nodes, 24
  rects, 493 glyphs, 3 hitboxes. Disagreeing control: `49270c7`'s copy with
  `ModifiedElement.paint`'s fills emitted after its content → 87 differing diff
  lines; restored → identical again.
- **Owed:** the release-window capture against `f64e58a`, by `MC-J`'s method,
  when a display is available.

**Counts at the docs commit.** Tests 1103 (1095 + 5 tests + 2 guards + the
allocation test). Guards 47: `grep -c canTypecheck` reads 19, 10, 5, 3 (one a
comment), 3, 6, 2 (`ModifiedElementCompileGuards`), plus the declaration in
`Typecheck.swift`. Goldens 97; `git diff --stat f64e58a -- '*.json'` empty.
Final runs, after the docs commit `c52f782` (whose test
files changed only in doc comments): `swift build --build-system native
--build-tests`, then `swift test --build-system native --no-parallel`: `Test
run with 1103 tests in 1 suite passed after 29.513 seconds`, 0 `error:`, 0
`warning:`, both new guards' diagnostics printed; then `swift test
--no-parallel` (default build system, whose guards read the native build's
modules): `Test run with 1103 tests in 1 suite passed after 26.470 seconds`, 0
`error:`, 0 `warning:`. `swift build -c release --product MetalUIDemo` in the
worktree: complete, for the owed capture. The session was still locked
(`CGSSessionScreenIsLocked` 1, display asleep) at the end of the lane.

**Not run, by reading only:** that `Element`'s group defaults do nothing per
element that a layer would need (they enter the id and bind `@State`); the
AB-O mirroring's future shape around `prepaintLayer`; `Component.swift`'s stale
`Box.swift` line citations (`MC-R` item 9).

**Deferred by lane 2.** The default demo's window capture (`MC-R` item 5; the offscreen stand-in sees one-layer chains only). A
shared, locked allocation counter for the two `malloc_logger` tests (`MC-R`
item 6). Everything `MC-L` already defers.

#### Lane 2 verifier-fix round, 2026-09-15 (from `6d0ea97`)

The verifier's mutations at `6d0ea97` found two changes to `ModifiedElement`
that left the whole suite green (1103 tests passed each time): **N8**, the
inner-layer paint loop run innermost-first, and **N3**, an inner layer's fill
given the outermost layer's corner radius. Its scratch tests showed each
mutant really differs from nested `Box`es. Both are closed in the test files
only; no `Sources/` change.

- **Tests changed** (`aModifierChainIsIdenticalToHandBuiltNestedBoxes`, lane 1
  test 4, and `aGenericWrapOverAChainIsIdenticalToTheFlatChain`, lane 2 test 2,
  identically): `RectShape` gains `radii` (all four corners) and
  `withoutRadii`; the chain and every arm gain `.background(.surfaceSecondary)
  .cornerRadius(3)` on padding 4, `.cornerRadius(5)` on the frame and
  `.cornerRadius(9)` on padding 8; two disagreeing checks are `try #require`d —
  a `radiiSwapped` arm (3 and 9 exchanged) that differs from the oracle and
  equals it with radii zeroed, and the oracle's rects with entries 1 and 2
  exchanged, after `oracle.rects.count == 4`.
- **Green unmutated:** `swift build --build-system native --build-tests`, then
  `--filter` over the two tests: `Test run with 2 tests in 0 suites passed`.
- **Red under the mutants, whole suite** (`mut.py` in the scratchpad: `cp`
  backup, one anchor replaced exactly once with a `// MC2-MUTATION` marker,
  `swift test --build-system native --no-parallel`, restore; `git status
  --short` showed only the two test files and the marker grep read 0):

| # | mutation | summary | tests reddened | reading |
|---|---|---|---|---|
| N3 | inner fill `cornerRadii: Corners(all: outermost.decoration.cornerRadius)` | 1103, 3 issues, 0 `error:` | test 2 (flat and generic); lane 1 test 4 | chain radii 9, 9, 9, 0; oracle 9, 5, 3, 0 |
| N8 | `ModifiedElement.paint`'s inner loop `for k in inner.indices` (not `.reversed()`) | 1103, 3 issues, 0 `error:` | the same | chain 76×56, **28×28, 60×40**, 20×20; oracle 76×56, 60×40, 28×28, 20×20 |

- **Spec corrected:** lane 1 test 8's row named "the layer loop reversed in
  prepaint, and separately in paint", which its one-padding-layer chain cannot
  see; the row now names L4 and L5 and says where L3 and N8 are caught.
- **Final runs** (tests and docs as committed): `swift test --build-system
  native --no-parallel`: `Test run with 1103 tests in 1 suite passed after
  32.942 seconds`, 0 `error:`, 0 `warning:`; `swift test --no-parallel`:
  `Test run with 1103 tests in 1 suite passed after 28.320 seconds`, 0
  `error:`, 0 `warning:`. Counts unchanged (no test added): tests 1103, guards
  47, goldens 97, `git diff --stat f64e58a -- '*.json'` empty.
- **Not done:** the release-window capture (`MC-R` item 5) — still locked:
  `ioreg` reports `IOConsoleLocked` and `CGSSessionScreenIsLocked` true. The
  offscreen stand-in exercises only one-layer chains (every legacy `.padding`
  in the demo is a single layer). The `malloc_logger` parallel hazard (`MC-R`
  item 6) stays for the integration step.

#### Lane 3 — the typed native node id, 2026-09-15 (from `40566de`)

One agent in the worktree. The session was locked with the display asleep for
the whole lane (`CGSSessionScreenIsLocked` 1, `CGDisplayIsAsleep` 1,
`IOConsoleLocked` true; `screencapture -x -R0,0,100,100` → "could not create
image from rect"). Suite and PATH `swiftc`: swift.org 6.3.3. Base count at
`40566de`, `swift test --build-system native --no-parallel`: `Test run with
1103 tests in 1 suite passed after 26.009 seconds`, 0 `error:`.

**Commits.**

| commit | what |
|---|---|
| `41a8634` | `ProposalNodeIDCompileGuards.swift`, guards 1–6 — red |
| `f9e2c62` | `ProposalNodeID.swift` (`ProposalNodeID`, `ProposalElement`, its two defaults, `Component`'s typed default), `GroupMember.swift`, `ElementGroup.swift`'s entry through the helper (and `AnyElement`'s doc), `ProposalElementGroup.swift`'s requirement and builder-group implementations, `Passes.swift`'s registrar block, every proposal element and wrapper, the demo's two preview declarations, the test helpers and SA-F fixtures, `ProposalNodeIDTests.swift` tests 7–9 |
| `b320ee7` | lane 1 test 6 also reads each value during layout (`CompositionLog.layoutTaps`), after mutation H2 left the suite green |
| docs commit | doc comments at the lines the mutations taught (`ProposalNodeID.swift`, `GroupMember.swift`, test 6); spec; `MC-G`/`MC-H` Mutations lines; `MC-J`'s lane 3 result; `MC-S`; this section |

**Red runs.**

- **Guards, on the unchanged tree** (`40566de` plus the guard file, `swift test
  --build-system native --no-parallel --filter ProposalNodeIDCompileGuards`):
  `Test run with 6 tests in 0 suites failed after 1.928 seconds with 9 issues.`
  - guard 1 at `:65` `!(result.succeeded → true)` and `:67` (messages empty);
    printed `succeeded=true`;
  - guard 2 at `:91` `(minted.succeeded → false) != (read.succeeded → false)`;
    printed "cannot find type 'ProposalNodeID' in scope" and "value of type
    'LayoutNodeID' has no member 'layoutNodeID'";
  - guard 3 at `:131` (all three fixtures `succeeded=true`);
  - guard 4 at `:161` `(legacy.succeeded → true) != (native.succeeded → true)`;
  - guard 5 at `:223` `(untyped.succeeded → false) != (typed.succeeded →
    false)` (neither `ProposalElement` nor the typed entry existed);
  - guard 6 at `:277` (the liar failed: "fixture.swift:10:82: error: cannot
    find type 'ProposalNodeID' in scope"), `:278` and `:280` (the negative
    compiled).
- **Tests 7–9 do not compile before lane 3.** The file added to the same tree,
  `swift build --build-system native --build-tests`: 51 errors in
  `ProposalNodeIDTests.swift`, the first
  `ProposalNodeIDTests.swift:26:75: error: cannot find type 'ProposalNodeID' in
  scope`, then `:39:34: error: cannot find type 'ProposalElement' in scope`.
  The file was removed before `41a8634` (`MC-S` item 1).

**Green** (`f9e2c62`), after `swift package clean` (public signatures changed
across modules): `Test run with 1112 tests in 1 suite passed after 28.093
seconds`, 0 `error:`, 0 `warning:`. Only the two env-gated tests skipped. Every
guard printed its diagnostic; the real diagnostics, all matching the spec's
skeleton fragments:

- guard 1: "type 'Liar' does not conform to protocol 'ProposalElementGroup'",
  noting "protocol requires function 'requestProposalGroupLayout(under:at:pass:)'
  with type '(GlobalElementID?, inout Int, inout LayoutPass) -> ([ProposalNodeID],
  SingleElementLayout<Liar>)'";
- guard 2: "'ProposalNodeID' initializer is inaccessible due to 'internal'
  protection level"; the read `succeeded=true`;
- guard 3: "type 'LegacyComp' does not conform to protocol
  'ProposalElementGroup'" ("candidate would match if 'Text' conformed to
  'ProposalElementGroup'"), the same for `OpaqueComp` ("… if 'some ElementGroup'
  conformed …"); `ProposalComp` `succeeded=true`;
- guard 4: "cannot convert value of type 'LayoutNodeID' to expected argument
  type 'ProposalNodeID'"; the native child `succeeded=true`;
- guard 5: "cannot convert value of type '[LayoutNodeID]' to expected argument
  type '[ProposalNodeID]'"; the typed container `succeeded=true`;
- guard 6: the liar `succeeded=true`; without its typed entry "type 'Liar' does
  not conform to protocol 'ProposalElementGroup'".

**Tests 7–9's readings** (all as the design review measured with untyped ids,
now through the typed registrars):

- test 7 arm a (`MC-G` hole 2): the typed leaf prepaints at (65, 0) 10×10; one
  rect, the 5×5 `Rectangle`; `nodeCount` 5; measure calls 1;
- test 7 arm b (hole 6): the typed leaf at (65, 0) 10×10; one rect, 5×5;
  `nodeCount` 6; the orphan leaf's `$state0` reads 8 and is live; the orphan
  `Box`'s `$anim` slot is live. Its disagreeing oracle (the same `Box` as a
  root) paints its 30×30 rect;
- test 8 arm a (hole 4): stack (60, 0) 20×10; leaf (70, 0) 10×10; measure
  calls 1; `nodeCount` 4. Arm b: stack (30, 0) 80×50; leaf (100, 40) 10×10;
  measure calls 2; `nodeCount` 6;
- test 9 (hole 7): stderr `MetalUILayout/LayoutTree.swift:561: Precondition
  failed: LayoutNodeID from generation 1 used against a LayoutTree at
  generation 2 — the id outlived the tree that issued it (ruling C-3)`; the
  control exits 0.

**Mutations** (`mutate.py` in the scratchpad: `cp` backup, each anchor replaced
exactly once with a `// MUTATION <label>` marker, `swift test --build-system
native --no-parallel` whole suite, restore; `git status --short` empty of
sources and the marker grep empty after every run).

| # | mutation | commit | summary | tests reddened |
|---|---|---|---|---|
| G1 | the spec's unconstrained trapping `ProposalElementGroup` default | `f9e2c62` | **build failed**: `main.swift:928:1: error: type 'PreviewToggle' does not conform to protocol 'ProposalElementGroup'` (two unordered witnesses) | none ran (`MC-S` item 5) |
| G1b | the same default `where Self: Element` | `b320ee7` | 1112, 2 issues | guard 1 (`:65`, `:67`) |
| G2 | `ProposalNodeID.init` `public` | `f9e2c62` | 1112, 1 issue | guard 2 (`:91`) |
| G3 | unconstrained trapping `Component` default | `f9e2c62` | 1112, 1 issue | guard 3 (`:131`) |
| G4 | `requestNativeFrame(child: LayoutNodeID, …)` overload | `f9e2c62` | 1112, 1 issue | guard 4 (`:161`) |
| G5 | `requestNativeLayout(_:children: [LayoutNodeID])` overload | `f9e2c62` | 1112, 1 issue | guard 5 (`:223`) |
| G6 | guard 6's positive without its typed entry | `f9e2c62` | 1112, 1 issue | guard 6 (`:275`) |
| F1 | `ProposalElement`'s `requestLayout` default `internal` (the SA-F row) | `f9e2c62` | **build failed**: `NativeElements.swift:13:15: error: method 'requestLayout(_:pass:)' must be declared public because it matches a requirement in public protocol 'Element'` | none ran |
| F1b | `LayoutPass.requestNativeLayout` `internal` | `b320ee7` | 1112, 2 issues | `anExternalModuleCanBuildACustomLeafAndContainerFromPublicAPI` (`:159`); guard 5 (`:223`) |
| T7 | orphan check: a counter around the typed default's `requestProposalLayout`, `precondition(counter == 0)` in `LayoutPass.requestNode` | `f9e2c62` | **no summary line**: trapped in test 7 ("Passes.swift:33: Precondition failed: MUTATION T7 …") after 953 passed | `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer` (fragment) before the trap |
| T8 | duplicate-parent precondition in `LayoutTree.appendNode` | `f9e2c62` | **no summary line**: trapped in test 8 ("LayoutTree.swift:150: Precondition failed: MUTATION T8: duplicate parent") after 955 passed | none before the trap |
| T9 | test 9's trapping arm registers afresh on frame 2 | `f9e2c62` | 1112, 2 issues | test 9 (`:342`, `:355`) |
| S1 | `newNativeLinearStack`'s child loop deleted | `f9e2c62` | 1112, 3 issues | `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`, `aLegacyNodeRegisteredUnderANativeStackTraps`; test 9 green |
| S2 | `setStyle`'s native check deleted | `f9e2c62` | 1112, 3 issues | `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`, `aStyleWrittenOntoANativeNodeTraps` |
| H1 | the helper's bind deleted | `f9e2c62` | 1112, 19 issues | test 6 at `c` only (`a` read 3); legacy `@State` tests; test 7 arm b |
| **H2** | `ProposalElement`'s typed default bypasses the helper | `f9e2c62` | **1112 passed** | **none** — the finding `b320ee7` answers (`MC-H`) |
| H3 | `Component`'s typed default bypasses the helper | `f9e2c62` | 1112, 1 issue | test 6 at `c` |
| H4 | the helper's `cursor += 1` deleted | `f9e2c62` | 1112, 25 issues | test 6 at `b` (2); identity, dispatch, hover tests |
| H1 | re-taken | `b320ee7` | 1112, 21 issues | test 6 (`taps["c"]`, `layoutTaps["a"]`, `layoutTaps["c"]` → 0); test 7 arm b (`$state0` nil, not live); seven legacy `@State` tests (`MC-H`) |
| H2 | re-taken | `b320ee7` | 1112, 1 issue | test 6 alone (`layoutTaps["a"] → 0`) |
| H3 | re-taken | `b320ee7` | 1112, 2 issues | test 6 alone (`taps["c"]`, `layoutTaps["c"]` → 0) |
| H4 | re-taken | `b320ee7` | 1112, 26 issues | test 6 (`taps["b"]`, `layoutTaps["b"]` → 2); lane 1 test 9's control; the sibling-index tests (`MC-H`) |

After every run `git status --short` showed no source change and the marker grep
was empty (the docs files the lane was editing in between appear in the later
runs' status lines, and no mutation touched them).

**The demo (`MC-J`): neither window was captured.** Locked as above; pointer
(1090.18, 339.99), not moved, no input sent, nothing launched.

- **Stand-in: offscreen scene dumps**, `MC-R` item 5's harness extended with
  `HARNESS_ROOT=preview` rendering `nativeLayoutPreviewContent()`. Scratch copies
  `git archive f64e58a` (`mc3-base`) and `git archive f9e2c62` (`mc3-head`),
  each `main.swift` given `@testable import MetalUI`, `import MetalUIText`,
  `import MetalUIRender` and its `try runDemo()` replaced; debug builds
  (`swift build --build-system native --product MetalUIDemo`); 920×560 at
  scale 2, three frames under light and three under dark, one shared state
  table, shaping cache and atlas; every `MUIRect`, `MUIGlyph` and hitbox
  printed.
- **Default:** 18 838 lines each, `cmp` identical (frame 0: 2036 nodes, 518
  rects, 15 711 glyphs, 3 hitboxes; later frames 60 / 24 / 493 / 3).
- **Preview:** 696 lines each, `cmp` identical (every frame: 31 nodes, 16
  rects, 97 glyphs, 2 hitboxes).
- **The instrument can disagree, for the preview:** `mc3-head` with `Pair`'s
  typed entry returning `secondNodes + firstNodes` → 1332 differing diff lines
  (rects move from the dump's fifth line on). **It cannot see the helper:** `mc3-head`
  with the helper's `cursor += 1` deleted → 0 differing lines in both dumps
  (no input, so no state or hitbox id is exercised). Restored (diff against
  `git show f9e2c62:` empty), rebuilt, both dumps `cmp` identical to the
  baseline again.
- **Owed:** both release-window captures against `f64e58a`, by `MC-J`'s method.

**Counts.** Tests 1112 (1103 + six guards + tests 7–9). Guards 53:
`grep -c canTypecheck` reads 19 (`PhaseSeparationTests`), 10
(`ErasureCompileGuards`), 6 (`ProposalNodeIDCompileGuards`), 6
(`ProposalLayoutCompileGuards`), 5 (`ElementGroupTrapTests`), 3
(`UnitSafetyTests`, one a comment), 3 (`AXNodeTests`), 2
(`ModifiedElementCompileGuards`), plus the declaration in `Typecheck.swift`.
Goldens 97; `git diff --stat f64e58a -- '*.json'` empty.

**Final runs**, on the tree of the docs commit (its `Sources/` and `Tests/`
changes against `b320ee7` are doc comments only): `swift test --build-system
native --no-parallel`: `Test run with 1112 tests in 1 suite passed after 28.153
seconds`, 0 `error:`, 0 `warning:`, all six guards' diagnostics printed; then
`swift test --no-parallel` (default build system, whose guards read the native
build's modules): `Test run with 1112 tests in 1 suite passed after 29.146
seconds`, 0 `error:`, 0 `warning:`, the guards' diagnostics printed again.

**`SA-R`'s amended criterion is met** by `MC-G`: a `ProposalElementGroup`
conformer that registers a legacy node, in every shape the design names, is a
compile error, with the seven holes pinned or cited (hole 1 guard 6; holes 2
and 6 test 7; hole 3 the rewritten trap test; hole 4 test 8; hole 5
`aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`; hole 7 test 9).
The SA decisions doc is not edited here.

**Not run, by reading only:** `MC-S` item 8's per-call array in the multi-child
registrars; that `EnvironmentScope`'s typed entry on `feat/environment` is the
merge's (the spec's merge notes).

**Deferred by lane 3.** Both demo window captures (`MC-S` item 7), with lane
2's still owed. Closing any of `MC-G`'s seven holes. An orphan check (hole 2)
and a duplicate-parent check (hole 4), each measured here to truncate the suite
rather than redden a test, so whoever adds one converts the pinning test to an
exit test first.

#### Lane 2 verifier-fix round 2, 2026-09-15 (from `c922457`)

One agent in the worktree, with lane 3's verifier-fix round present and
uncommitted (`ProposalElementGroup.swift`, this file, the decisions doc and an
untracked `ProposalGroupEntryTests.swift`); none of it is lane 2's and none of
it was staged here. Counts below include that untracked test. The session was
still locked (`ioreg`: `IOConsoleLocked` true; `screencapture -x
-R0,0,50,50` → "could not create image from rect").

The verifier at `c922457` found one major and three lane-2 minors:

| # | finding | outcome |
|---|---|---|
| major | dropping an inner layer's (V1) or the outermost layer's (V11) animated `Decoration` in `ModifiedElement.requestLayout` left 1115 green; an animated `cornerRadius` on a `.padding`/`.frame` layer snaps | **fixed** — a `ModifiedElement` arm in `decorationSubstitutionReachesTheElementOnBoxAndStack`; `MC-I`'s list is now seven |
| minor | the allocation test was not red on arrival | **recorded** as `MC-R` item 10, with K1/K2 standing in |
| minor | `.id` on a chain's OUTERMOST layer seen only by the AX guard (V9) | **fixed** — `anIDAfterAChainsLastWrapperNamesTheOutermostLayer` (`ModifiedElementTests.swift`) |
| minor | release-window capture owed | **still owed**: locked, as above |

- **The decoration arm.** A two-layer chain
  `Box().width(10).height(10).padding(4).cornerRadius(r₁).padding(8).cornerRadius(r₂)`
  through a real `LayoutPass`, baseline radii 0/0, then 20/40 inside
  `withAnimation(.linear(duration: 1))` at t = 0 and again at t = 0.5; it reads
  `inner[0].decoration` and `outermost.decoration` back (what `paint` reads
  later the same frame) and `#require`s `layerCount == 2`. Different targets
  per layer, so a swapped or shared baseline is a mismatch.
- **The id test.** `Row { sibling; chain.id("outer") }` against the same Row
  of nested `Box`es with `.id("outer")` on the outermost; the disagreeing
  oracle drops that name (V9's effect) and is `try #require`d to differ in
  leaf id, layer ids and hitbox ids. Its layer-count precondition reads
  `outermost.elementID` directly, not the getter under test, so V9 reddens the
  expectations rather than the precondition (a first version read the getter
  and stopped at the `#require`).
- **Green unmutated:** filtered, `Test run with 2 tests in 0 suites passed`.
- **Red under the mutants, whole suite** (`swift test --build-system native
  --no-parallel`; one anchor replaced exactly once with a `/* MC2-MUTATION */`
  marker, backup in the scratchpad, restored; `git diff --stat -- Sources/`
  afterwards showed only lane 3's `ProposalElementGroup.swift`):

| # | mutation | summary | tests reddened | reading |
|---|---|---|---|---|
| V1 | `(inner[k].style, _) = animated(` | 1115, 1 issue | `decorationSubstitutionReachesTheElementOnBoxAndStack` only | INNER: expected 0 then 10, got `Optional(20.0) then 20.0` |
| V11 | `(outermost.style, _) = animated(` | 1115, 1 issue | the same only | outermost: expected 0 then 20, got `Optional(40.0) then 40.0` |
| V9 | `ModifiedElement.elementID`'s `get { nil }` | 1116, 5 issues | `anIDAfterAChainsLastWrapperNamesTheOutermostLayer` (3: leaf id, layer ids, hitboxes — `positional(1)` where the oracle has `named("outer")`), `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` (2) | — |

- **Final runs** (tests and docs as committed, plus lane 3's uncommitted
  files): `swift test --build-system native --no-parallel`: `Test run with
  1116 tests in 1 suite passed after 26.883 seconds`, 0 `error:`, 0
  `warning:`, both `ModifiedElementCompileGuards` diagnostics printed (MC-A
  positive succeeded, negative "unable to type-check"; MC-B annotated
  succeeded=false), `MC-K-ALLOC` nested [17002, 27001, 37004], flat [17002,
  28501, 39504], loop floor 0. `swift test --no-parallel`: `Test run with 1116
  tests in 1 suite passed after 27.304 seconds`, 0 `error:`, 0 `warning:`.
  Tests 1115 → 1116; guards 53 (`grep -c canTypecheck`: 19, 10, 6, 6, 5, 3
  with one a comment, 3, 2), unchanged; goldens 97, `git diff --stat f64e58a
  -- '*.json'` empty. No `Sources/` change.

### For the integration step

Collected here so the merge does not have to re-derive them:

- **`FrameModifier` is deleted by lane 2** (`e9248c3`). `CLAUDE.md`'s Animation section
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
- **`SA-R`'s amended criterion is met by lane 3** (`MC-G`, `f9e2c62`), with
  **seven** named holes (the design review added holes 4, 5 and 6; the critic
  round after lane 1 added hole 7, a stored typed id, backstopped by C-3's
  trap), each pinned or cited — for the plan's task 3 entry, the SA doc's
  `SA-R` status and CLAUDE.md's holes list. The SA decisions doc is not edited
  by this track.
- **Every proposal element's layout signature changed once** (lane 3): an
  element is a `ProposalElement` writing `requestProposalLayout(_:pass:) ->
  (ProposalNodeID, LayoutState)`; a container calls
  `content.requestProposalGroupLayout`; the native registrars take and return
  `ProposalNodeID`; a `Component` over proposal content spells it
  `some ProposalElementGroup`. Any other track's proposal element (e.g. one
  adding AX, focus or environment reads) stops compiling at merge until
  converted — loud, not silent.
- **For CLAUDE.md's `@State` section** (lane 3, `MC-H`): `Element.prepaintGroup`
  and `paintGroup` re-bind an element's `@State`, so the group entry's bind is
  observable only by a LAYOUT-time read. A test of a bind that reads only in
  paint cannot fail (measured: the typed default bypassing the helper left the
  suite green until lane 1 test 6 read during layout, `b320ee7`).
- **Closing hole 2 or hole 4 truncates the suite** unless the pinning test
  (`anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected`,
  `aNativeNodeRegisteredTwiceIsNotRejected`) is first made an exit test —
  measured by lane 3's T7 and T8 (no summary line).
- **The guard count moves 45 → 47 (lane 2) → 53 (lane 3)**, re-counted by lane
  3 at 53 (lane 2 test 6 became a guard after the critic round). Re-count per
  file. Lane 2's
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
- **`ProposalElementGroup.swift`'s 13 conformance lines now read
  `extension X: ProposalElement {}`**, and `ProposalText`,
  `ProposalScrollView` and `ProposalLayoutContainer` conform in their own
  files; a track adding a proposal type adds it as a `ProposalElement`.
- **Owed by lane 3 as well as lane 2:** the preview window's release capture
  against `f64e58a` (`MC-J`, `MC-S` item 7); both offscreen dumps were
  byte-identical.
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
- **`MC-K`'s named cost, for task 4:** +3 allocations per 2-layer chain and +5
  per 3-layer chain per frame build over nested boxes, **measured by lane 2 in
  the real debug test build** (swift.org 6.3.3; +4 and +7 under swiftlang 6.4),
  equal to the model's. Pinned by `aModifierChainAllocatesABoundedAmountOverNestedBoxes`.
- **Owed by lane 2, for whoever has a display:** the default demo's
  release-window capture against `f64e58a` (`MC-J`, `MC-R` item 5); an
  offscreen scene comparison stood in, byte-identical.
- **A parallel-run hazard** (`MC-R` item 6): two tests now install libmalloc's
  process-wide `malloc_logger`; without `--no-parallel` they can corrupt each
  other's counts (measured once).
- **Lane 2's per-site accounting.** `FrameModifier`'s layout and background
  sites are gone; `ModifiedElement` is ONE layout site (`animated` per layer in
  `requestLayout`) and ONE background site (`animatedBackground` per layer in
  `paint`), each looping over its layers, with inner- and outermost-layer arms
  in all seven guards (`MC-I`; the seventh, the `Decoration` write-back, added
  by lane 2's second verifier-fix round). The legacy path's `pass.fill` sites CLAUDE.md counts become
  `Box.paint`, `Stack.paint`, `Text.paint`, `ModifiedElement.paint` (two calls,
  the outermost layer's and the inner layers') and `ScrollView`'s indicator;
  the proposal path's native fills (`NativeElements.swift`,
  `NativeModifiedContent.swift`, `NativeTappable.swift`,
  `ProposalScrollView.swift`) are outside that count, by grep.
