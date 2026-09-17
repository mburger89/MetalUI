# 18 — Engine replacement, stage 1 (plan task 7)

`feat/engine-replacement`, from `c2290fc`. Design:
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`; rulings `LR-A`…
in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`; probe
`docs/probes/swiftui-engine-replacement-stage1.swift`.

This section holds the **design round's** measurements. Lanes append below it.
The summary sections from "What landed, in one place" to the end were written by
the record pass at `95234ae`; "For the integrator", the last section, says what
CLAUDE.md, the plan, README and the two tables should say. **All five lanes
verified `ok: true`** (lane 5 with four open minor issues).
Every prototype named here was applied in the worktree, run, and reverted with
`git checkout Sources Tests` (new files deleted); `git status --short` afterwards
showed only the design's docs and probe. Patches and outputs are in the design
session's scratchpad (`lr/`), not in the repository.

## Baseline (2026-09-16, PDT)

- `swift build --build-system native --build-tests` → `Build complete!`; then
  `swift test --build-system native --no-parallel` →
  `Test run with 1357 tests in 1 suite passed after 41.968 seconds.`
  `grep -c "error:"` on the log: 0. `warning:` lines: SwiftPM's
  `'--build-system native' has been deprecated` notice only. Skipped:
  `regenerateAllGoldens`, `aListsWorkIsTheSameFor100kRowsAsFor500`. The
  `CONTAINER GUARD` lines printed, so the typecheck guards ran.
- Goldens: `find Tests -name "*.json" | wc -l` → 97.
- Guards: per-file `grep -c canTypecheck` → `UnitSafetyTests` 3 (one a
  comment), `AXNodeTests` 3, `PhaseSeparationTests` 19, `EnvironmentCompileGuards`
  8, `ErasureCompileGuards` 10, `ProposalNodeIDCompileGuards` 6,
  `DecorationCompileGuards` 3, `ContainerCompileGuards` 4,
  `ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5,
  `ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2 → **70**
  (`Typecheck.swift`'s declaration excluded).

## Instrument I1 — who reaches the legacy engine

A counter in `Frame.requestNode`/`requestLeaf` keyed by the caller's `#fileID`
(threaded through `LayoutPass`'s public forwarders as a defaulted parameter), a
counter per root kind in `Frame.computeRootLayout`, and a counter in
`computeLayout`; printed by an `atexit` handler. One unfiltered run: `Test run
with 1357 tests in 1 suite passed`. (Exit-test child processes print to their
own streams, which the parent does not capture, so their frames are not
counted.)

```
root legacy 2414
root native 237
engine computeLayout 4443
node MetalUI/Box.swift 70166
node MetalUI/ModifiedElement.swift 12401
leaf MetalUI/Text.swift 12061
node MetalUI/ScrollView.swift 1124
node MetalUI/Stack.swift 56
node MetalUI/Component.swift 32
node MetalUITests/MeasurePerformanceTests.swift 17494
node MetalUITests/FrameSizingTests.swift 305
node MetalUITests/ListTests.swift 224      (+ leaf 3)
node MetalUITests/StateTests.swift 91
node MetalUITests/ComponentTests.swift 69
node MetalUITests/ModifierCompositionProofTests.swift 51
node MetalUITests/EnvironmentTests.swift 50
node MetalUITests/StateTableTests.swift 41
node MetalUITests/TombstoneTests.swift 38
node MetalUITests/ElementLayoutTests.swift 33
node MetalUITests/ModifiedElementTests.swift 32
node MetalUITests/AXNodeTests.swift 25
node MetalUITests/PipelineTests.swift 20
node (DisabledTests 9, ScrollRoutingTests 9, FocusTests 8, HitboxTests 8,
      ContainerIntegrationTests 7, ElementGroupTrapTests 4, IdentityTests 4,
      FrameClockTests 3, FrameLoopTests 3, ProposalNodeIDTests 3, GlyphEmitterTests 2)
```

`computeLayout` minus legacy roots: 4 443 − 2 414 = **2 029** direct engine runs
from `MetalUILayoutTests`. Custom test elements: 18 533 nodes in 24 files, plus
3 leaves.

## Prototype P1 — lowering under a frame flag

`ScratchLowering.swift`: a `Frame.scratchAuthority` flag; `Frame.requestNode`/
`requestLeaf` preconditions under it; `LayoutPass.scratchLower(style:children:)`
lowering a `Style` to a native leaf (no children) / linear stack (`flexDirection`,
main-axis `gap`, cross alignment from `alignItems`) / overlay (`display: .stack`),
then native padding, then a fixed frame (`size`), then a flexible frame
(`minSize`/`maxSize`), with frame alignment from `justifyContent`/`alignItems`
(stack: `justifyItems`/`alignItems`), recording (not trapping) every field it
could not lower. Branches in `Box`, `Stack`, `ModifiedElement` (both registrars)
and `Text` (native leaf measured by `proposalTextMeasurement`). Bounds recorded
per `GlobalElementID` in `Element.prepaintGroup`, at the root in `Frame.render`,
and per inner layer in `ModifiedElement.prepaintLayer`.

### Scratch differential, run 1 — each tree as the frame's root

| tree | window | elements | agreeing |
|---|---|---|---|
| T0 `Row(gap 10){20×20; 30×10}` | 300×100 | 3 | 0 |
| T0b the same as a `Column` | 300×100 | 3 | 0 |
| T1 counter button (`Box{Text}` 36×36, centre/centre) | 300×100 | 2 | 0 |
| T1b counter chrome (`Box(style: row gap 12 padding 12 centre)`) | 400×100 | 7 | 0 |
| T2 demo header (`Row{40×40; h12 grow}` centre, grow, padding 16, h72) | 600×200 | 4 | 0 |
| T3 demo stack cluster | 600×300 | 5 | **4** |
| T4 demo sidebar (`Column{Text; 2× h26}` stretch, grow, padding 14, w196) | 600×400 | 5 | 0 |
| T5 text column | 400×400 | 3 | 0 |
| T5b text column, padded | 400×400 | 4 | 0 |
| T6 `Box{Text}.padding(8).frame(100×40)` | 300×200 | 4 | 0 |
| T7 nested rows | 600×200 | 8 | 0 |
| T8 `Column{Text(long)}.width(60)` | 300×400 | 2 | 0 |
| **total** | | **50** | **4** |

Representative lines: T0's root `legacy (0,0 300×100) lowered (120,40 60×20)`
(the legacy root fills the window, the native root is centred); T7's children
differ by exactly (0, +75). T5b also showed a 1pt width difference (legacy 117,
lowered 116) that moved with the root's origin: cumulative-edge rounding at a
different fractional origin.

### Scratch differential, run 2 — inside `Stack(alignment: .topLeading){…}.width(W).height(H)` on both sides

```
T0 row of fixed boxes: elements=4 same=4 differ=0 gaps=[]
T0b column of fixed boxes: elements=4 same=4 differ=0 gaps=[]
T1 counter button: elements=3 same=3 differ=0 gaps=[]
T1b counter chrome: elements=8 same=8 differ=0 gaps=[]
T2 demo header: elements=5 same=5 differ=0 gaps=[alignItems.stretch: 1, flexGrow: 2]
T3 demo stack cluster: elements=6 same=6 differ=0 gaps=[]
T4 demo sidebar: elements=6 same=2 differ=4 gaps=[alignItems.stretch: 2, flexGrow: 1]
   legacy (14,76 168×26) lowered (14,76 0×26)
   legacy (14,14 168×88) lowered (14,14 42×88)
   legacy (14,40 168×26) lowered (14,40 0×26)
   legacy (14,14 168×16) lowered (14,14 42×16)
T5 text column: elements=4 same=4 differ=0 gaps=[]
T5b text column centred padded: elements=5 same=5 differ=0 gaps=[alignItems.stretch: 1]
T6 padded frame over text: elements=5 same=5 differ=0 gaps=[alignItems.stretch: 2]
T7 nested rows: elements=9 same=9 differ=0 gaps=[]
T8 text in narrow fixed column: elements=3 same=2 differ=1 gaps=[]
   legacy (0,0 60×112) lowered (8,0 44×112)
```

**57 of 62** agree (45 of 50 excluding the twelve harness roots). T2 agreed
despite two `flexGrow` gaps because a fit-content root leaves no free space to
grow into — which is why stage 1 does not lower `flexGrow` on the strength of
T2 (`LR-E`).

**Control** (`SCRATCH_CONTROL=1`: lowered stack spacing + 1), same trees:
T0 2/4, T0b 2/4, T1 3/3, T1b 3/8, T2 2/5, T3 6/6, T4 1/6, T5 2/4, T5b 2/5,
T6 5/5, T7 2/9, T8 2/3 — the instrument sees a one-point lowering change
wherever a stack has two or more children.

### Pipeline parity (counter chrome, 400×100, scale 2, pointer at (30, 30), accessibility on)

The chrome: minus and plus buttons with `.hoverBackground(.accent).onClick {}`
and `accessibilityLabel`, a readout, all in `Box(style: row)` with a surface
decoration, `.focusBackground`, `.focusable()`, `.keyContext("Counter")`,
`.padding(5).background(.accent)`, inside the harness `Stack`.

```
proposal=false states=11          proposal=true states=11
rects 3/3 equal=true              (control: equal=false)
glyphs 8/8 equal=true             (control: equal=false)
hitboxes 2/2 equal=true           (control: equal=false)
ax 6/6 equal=true                 (control: equal=true — id, node, text only; no geometry compared)
bounds equal=true                 (control: equal=false)
```

### Animation parity

`Box().height(20).width(w).background(.accent)` in the harness root; frames at
(t, w, transaction) = (0, 196, nil), (0, 320, `.linear(duration: 1)`),
(0.5, 320, nil), one `StateTable`:

```
legacy=[196.0, 196.0, 258.0] lowered=[196.0, 196.0, 258.0]
```

### The demo outside its scroll area

`demoContent()` with `CounterPanel` omitted and the `ScrollView` box replaced by
`Box().width(420).flexGrow(1).flexBasis(0).minHeight(0).background(.surface)`,
rendered as the root at 920×560:

```
elements=21/21 same=0 differ=21
gaps=[alignItems.stretch: 8, alignSelf.flexStart: 1, flexBasis: 1, flexGrow: 8]
```

(P1 lowered `minHeight` as a flexible frame, so it is absent from the list;
stage 1 reports `minSize` by name, `LR-E`.)

## Conformance measurement C1

`Sources/MetalUI/ScratchConformance.swift`:
`extension Text: ProposalElement { … fatalError() }`,
`extension Box: ProposalElement where Content: ProposalElementGroup { … }`,
`extension Box: ProposalElementGroup where Content: ProposalElementGroup {}`
(the first attempt without the last line failed with `conditional conformance
… does not imply conformance to inherited protocol`).

- `swift build --build-system native --build-tests`: stops in `MetalUIDemo`,
  `main.swift:429:14: error: ambiguous use of 'background'` (candidates
  `NativeModifiedContent.swift:206` and `Box.swift`'s).
- `swift build --build-system native --target MetalUITests`: **83** distinct
  `error:` lines in 13 files — `DecorationPaintTests` 32,
  `FrameDecorationInteractionTests` 16, `OuterModifierMatrixTests` 9,
  `ThemeTests` 7, `HitRegionTests` 5, `FrameLoopTests` 3, `AnimationTests` 2,
  `DeferredTests` 2, `DisabledTests` 2, `NestedClipTests` 2,
  `AbsoluteOverlayTests` 1, `EnvironmentTests` 1, `TextMeasureTests` 1. By
  message: `ambiguous use of 'background'` 66, `'opacity'` 3,
  `'allowsHitTesting'` 3, `unable to type-check this expression in reasonable
  time` 3, and 8 singletons.
- Reverted; `swift build --build-system native --build-tests` then printed 0
  `error:` lines.

## Pixels

`CN-R`'s harness (`scratchpad/harness/gen.py`, `cmp.py`; `DEMO_PIXELS_SMALL=1`),
generated into the P1 tree (default authority) and, after reverting, into
`c2290fc`:

```
animation-dark: 0 differing pixels; scene identical
animation-light: 0 differing pixels; scene identical
default-dark-f0: 0 differing pixels; scene identical
default-dark-f3: 0 differing pixels; scene identical
default-light-f0: 0 differing pixels; scene identical
default-light-f3: 0 differing pixels; scene identical
modal-dark: 0 differing pixels; scene identical
modal-light: 0 differing pixels; scene identical
preview-dark: 0 differing pixels; scene identical
preview-light: 0 differing pixels; scene identical
small560-default-light: 0 differing pixels; scene identical
small560-preview-light: 0 differing pixels; scene identical
```

Controls on `c2290fc`'s images: `default-light-f0` vs `default-dark-f0`
1 048 576; vs `modal-light` 1 030 498; vs `animation-light` 210 027; vs
`default-light-f3` 0; `preview-light` vs `preview-dark` 1 048 576 — record
§16/§17's figures. The generated `ZZDemoPixels.swift` was deleted after each
run.

## Screen lock (real-window captures not attempted)

20:36:28 PDT: `ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` → `<false/>`.
`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift` → run:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`, `displayActive main: 0`,
`preflightScreenCaptureAccess: true`. By `FR-V` the session dictionary decides;
no demo was launched and no `screencapture` was run.

## Probe

`/usr/bin/swift docs/probes/swiftui-engine-replacement-stage1.swift` → exit 0,
61 lines; a second run's output `diff`s empty against the first; the header
carries the output and its reading. `/usr/bin/swift --version`: Apple Swift
version 6.4 (swiftlang-6.4.0.33.1 clang-2100.3.33.1); `sw_vers`: macOS 27.0
(26A428).

## Critic round 1 (2026-09-16, 21:05–21:30 PDT)

The critic reviewed `59fd180` read-only and reported 24 findings; dispositions in
`LR-W`. Everything below was measured in this round.

### Prototype P2

P1 re-applied from `lr/prototype.diff` (it applied cleanly at `59fd180`), plus the
instruments `LR-O` lists. Saved as `lr/prototype-p2.diff`,
`lr/ScratchLowering-p2.swift`, `lr/ScratchDifferentialTests-p2.swift`. Reverted
with `git checkout Sources Tests`, the three new files deleted; `git status
--short` then read ` M docs/probes/swiftui-engine-replacement-stage1.swift`
only; `swift build --build-system native --build-tests` → `Build complete!`.

**P1's figures reproduce under P2** (the scratch tests filtered): the twelve
trees inside the harness root 57 of 62 with the same five disagreements, the
pipeline parity lines, and the animation widths `[196.0, 196.0, 258.0]` on both
sides.

**Unfiltered suite with the depth instruments** (no `SCRATCH_*` variable):
`Test run with 1365 tests in 1 suite passed after 48.571 seconds` (1357 + 7
scratch tests + the generated harness), and

```
SCRATCHDEPTH legacyRoots=2440 maxLegacyDepth=13 maxLoweredEstimate=22 rootsOver88=0 rootsLoweredOver64=0 maxNativeRun=12
```

The harness alone (`--filter zzDemoPixels`): `legacyRoots=9 maxLegacyDepth=13
maxLoweredEstimate=22 … maxNativeRun=10` — so the suite's deepest legacy element
tree is the demo's, and the preview's native run is 10.

### The demo minus its scroll area, inside the harness root (finding 11)

```
DEMO in root: elements=22 same=2 differ=20 missing=0
  gaps=[alignItems.stretch: 8, alignSelf.flexStart: 1, flexBasis: 1, flexGrow: 8]
SCRATCHDIFFDEPTH DEMO in root: maxNative=12
```

Scratch-tree native depths: T0 5, T0b 5, T1 5, T1b 7, T2 8, T3 6, T4 8, T5 4, T5b
6, T6 9, T7 6, T8 5.

### Text in stacks, kernel with and without the clamp (finding 10)

`HStack(spacing: 0)` of `ProposalText`s as the frame's root (width as named,
height 300); rects are every recorded element, sorted by x then width (the
`.layoutPriority` wrapper records the same rect as its text):

```
W0 control at 400 clamp=false: (131,142 105x16) (131,142 138x16) (236,142 33x16)
W0 control at 400 clamp=true:  (131,142 105x16) (131,142 138x16) (236,142 33x16)
W1 G18 at 80 clamp=false: (1,126 45x48) (1,126 78x48) (46,142 33x16)
W1 G18 at 80 clamp=true:  (1,126 45x48) (1,126 78x48) (46,142 33x16)
W2 long prio1 at 80 clamp=false: (-2,134 76x32) (-2,134 76x32) (-2,110 84x80) (74,110 8x80)
W2 long prio1 at 80 clamp=true:  (0,134 75x32) (0,134 75x32) (0,110 80x80) (75,110 5x80)
W3 short prio1 at 80 clamp=false: (1,126 45x48) (1,126 78x48) (46,142 33x16) (46,142 33x16)
W3 short prio1 at 80 clamp=true:  (1,126 45x48) (1,126 78x48) (46,142 33x16) (46,142 33x16)
W4 text and fixed 40 at 80 clamp=false: (3,118 34x64) (3,118 74x64) (37,145 40x10)
W4 text and fixed 40 at 80 clamp=true:  (3,118 34x64) (3,118 74x64) (37,145 40x10)
W5 two words at 40 clamp=false: (1,118 20x64) (1,118 38x64) (21,126 18x48)
W5 two words at 40 clamp=true:  (1,118 20x64) (1,118 38x64) (21,126 18x48)
```

SwiftUI (probe revision 2, group W): W0 105/34, W1 46×48/34, W2 59×32/18×32
(77), W3 = W1, W4 34×64 + 40, W5 20/19. The clamp moves W2 only.

### Pixels (findings 8, 19)

The `CN-R` harness generated into P2 (`gen.py`), `DEMO_PIXELS_SMALL=1`, against
`lr/base` (the design round's `c2290fc` images):

- default environment: **12 of 12 read 0 differing pixels, scene identical**;
- `SCRATCH_PADCHILD=1` (`SA-N` item 4: a native padding places its child at
  origin + inset at the child's own measured size): **12 of 12 read 0, scene
  identical**, including both preview images and the 560² preview.

Instrument check for the second run: `negativePaddingIsAcceptedAndItsResponseClampsPerAxis`
filtered reads `passed` with `SCRATCH_PADCHILD=0` and `failed … expected exit
status ".success", but ".signal(SIGTRAP)"` with `SCRATCH_PADCHILD=1` — the
variable reaches the kernel and changes an outcome. (That the negative-padding
arm then **traps** is itself a stage-2 finding: placing a child at its own size
under negative insets reaches a checkpoint.)

### Diagnostics census of the later stages' exit suites (finding 20)

Each suite filtered with `SCRATCH_ALL=1` (every frame under the proposal
authority; legacy registrars answer a 0×0 native leaf and count their caller's
file; `Component` amends skipped and counted; the depth guard records). Counts are
occurrences over every frame each suite builds. Two runs: the first without
`minSize`/`maxSize` reporting, the second with it (the other counts were
identical).

| suite | result | census |
|---|---|---|
| `zzDemoPixels` (the eight legacy images, two preview, no small) | passed | stretch 8 084, `flexGrow` 4 066, `flexShrink` 4 008, `minSize` 4 008, `alignSelf.flexStart` 16, `flexBasis` 8, `position.absolute` 2, `inset` 2, `ScrollView.swift` 16; max native run 12 |
| `ScrollRoutingTests` | 16 tests, 20 issues | stretch 35, `stack.stretch` 4, `minSize` 3, `ScrollView.swift` 70, `ScrollRoutingTests.swift` 9; run 2 |
| `ScrollIndicatorTests` | 14 tests, 16 issues | stretch 11, `ScrollView.swift` 38; run 3 |
| `DeferredTests` | 9 tests, 3 issues | stretch 3, `ScrollView.swift` 10; run 3 |
| `AbsoluteOverlayTests` | 1 test, 1 issue | stretch 2, `minSize` 1, `position.absolute` 1, `inset` 1, `ScrollView.swift` 2; run 6 |
| `ListTests` | 29 tests, 16 issues | stretch 251, `flexShrink` 249, `minSize` 222, `ListTests.swift` 224 nodes + 3 leaves; run 8 |

No `component.amend` was counted in any of them.

### Mixed tree (finding 21)

```
SCRATCHMIXED proposal=true gaps=[] regions=1 (135,81 30x10) (100,81 100x138) (150,95 20x20) (130,95 20x20) (130,95 40x20) (100,119 100x100) (100,119 100x100) (100,119 100x400) (100,119 100x400)
```

### `dlsym` (finding 17)

In the test process, `dlsym(RTLD_DEFAULT, …)`:

```
$s13MetalUILayout13computeLayout_4root9available0E8FontSizeyAA0D4TreeC_AA0D6NodeIDVAA014AvailableSpaceH0VSdtF -> true
$s13MetalUILayout13computeLayout_4root9available0E8FontSizeyAA0D4TreeC_AA0D6NodeIDVAA014AvailableSpaceH0VSdtX -> false
definitelyNotASymbolXYZ -> false
```

identical under `swift build --build-system native --build-tests` + `swift test
--build-system native` and under `swift build --build-tests` + `swift test` (the
default build system; `Build complete! (28.53 sec)`). The name came from `nm` on
`.build/arm64-apple-macosx/debug/MetalUIPackageTests.xctest/Contents/MacOS/MetalUIPackageTests`.

### Counts re-taken (findings 16, 23)

- `MetalUILayoutTests`: 440 `@Test`s; per-file tests / `computeLayout(` sites in
  spec §2.6 (`grep -c "@Test"`, `grep -c "computeLayout("`).
- `wc -l Sources/MetalUI/AnimatedStyle.swift` → 568.
- Guard files: the twelve the baseline lists (the design's "13 files" counted
  `Typecheck.swift`).

### Probe revision 2

Group W appended to `docs/probes/swiftui-engine-replacement-stage1.swift`;
`/usr/bin/swift` exit 0, run three times, byte-identical, 79 lines; the output
minus W's lines `diff`s empty against revision 1's 61-line block.

### Screen lock

21:16:37 PDT: `ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` → `<true/>`. No
capture attempted. The design round's skip at 20:36 (`<false/>`) is recorded as an
override of the orchestrator's trigger (`LR-M`).

## Lane 1 — authority, every site's own check, bounds log, harness

Commits: `4ceb3e0` (tests, red: does not compile), `68200dc` (implementation),
then the verifier round: `ea7ac56` (tests; 1.9 arm d red), `a155251` (harness
fix), and this record.

### Red first

- `4ceb3e0`: a `git archive` of the commit fails to build, 72 error lines, all
  naming the missing lane-1 API (`UnlowerableField`, `lowersToProposal`,
  `LayoutAuthority`, `elementBounds`, `StateTable.ids`, the new `Frame` init
  arguments). `68200dc`'s only test edits are a `@MainActor` closure annotation
  and a doc comment. Measured by the lane-1 verifier.
- `ea7ac56`: `swift test --build-system native --no-parallel --filter
  LayoutAuthorityTests` → 11 tests, one issue:
  `theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState` at arm (d),
  `Expectation failed: d.scenesEqual == false`. The harness compared
  `Frame.scene`'s emission bytes only; two leaves whose emitted rects are
  byte-identical, the first on a raised layer under the proposal authority,
  read equal. `1.5b` (`aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop`) and
  1.5's amend arm moved into a child process both pin existing code and passed
  on arrival; their mutations are below.

### Suite

- `68200dc`, after `swift package clean` and a native build (verifier): 0
  `error:`, the only `warning:` SwiftPM's `--build-system native` deprecation
  notice; `Test run with 1368 tests in 1 suite passed after 41.914 seconds`
  (1357 + 11). Goldens 97; no `*.json` changed since `c2290fc`. The new guard
  prints `LAYOUT-AUTHORITY GUARD G1 choose: succeeded=false` and `control:
  succeeded=true`, so it ran.
- `a155251` (committed 22:17 PDT; no stored property on a public type changed, so no
  clean): build 0 `error:`; `Test run with 1369 tests in 1 suite passed after
  41.643 seconds` (1368 + `1.5b`). Goldens 97; `git diff --stat c2290fc --
  '*.json'` empty.

### Mutations

Each: committed tree, file copied, mutant applied, full unfiltered suite,
restored from the copy, `git status --short` empty afterwards. M1b–M1l, G1 and
the unnamed rows were run by the lane-1 verifier on `68200dc`; M1d′ (second
run), the skip-removed variant (second run), M1m, M1n and M1n′ on `a155251`.

| mutation | reddened |
|---|---|
| M1b `Window` builds its `Frame` without `layoutAuthority:` | `aWindowBuildsEveryFrameUnderItsLayoutAuthority` |
| `Window.layoutAuthority`'s `didSet` no longer dirties | `aWindowBuildsEveryFrameUnderItsLayoutAuthority` |
| M1c `LayoutPass.requestNode`'s `customElement` check removed | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| M1c′ the same in `LayoutPass.requestLeaf` | the same two |
| M1d `List`'s `noteUnlowerable(list.noLowering)` removed | `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| M1d′ the amend's authority check removed (`setStyle` always runs) — **at `68200dc`** | `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority`, then **the suite truncated with no summary line**: `LayoutTree.swift:603: Precondition failed: setStyle on a native layout node` inside 1.5's in-process amend arm (practices shape 13). Spec §6 had claimed 1.4 only |
| M1d′ — **at `a155251`**, 1.5's amend arm in a child process | `Test run with 1369 tests … failed … with 4 issues`: `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (the child exits on `SA-G`'s precondition) |
| the amend records its entry but still calls `setStyle` — at `68200dc` | **suite truncated, no summary line** (same precondition, same test) |
| the same — at `a155251` | `… failed … with 2 issues`: `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| `StyledComponent`'s wrap check forced false | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| M1e `ScrollView` registers a native leaf without recording | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| M1e′ variant: `List` builds its real window under diagnostics (row `Box`es appear) | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| `Box`'s, `Stack`'s, `Text`'s, the inner-layer and the outermost `ModifiedElement` registrars' own checks, each forced false separately (five runs) | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` each |
| M1f per-inner-layer `recordElementBounds` removed from `prepaintLayer` | `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer` |
| M1g the root's `recordElementBounds` removed from `Frame.render` | `theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement`, `theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities`, `theElementBoundsLogIsEmptyUnlessRequested`, `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer` |
| `Element.prepaintGroup`'s `recordElementBounds` removed | the same four |
| M1h `recordElementBounds` ignores `recordsElementBounds` | `theElementBoundsLogIsEmptyUnlessRequested` |
| `Frame.init`'s `reportsUnlowerableFields` defaults to `true` | `aFrameAndAWindowDefaultToTheLegacyAuthority`, `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority`, `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` |
| M1i `compare` renders the legacy authority twice | `theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState`, `theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement` |
| M1j `hitboxesEqual` returns `true` | `theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState` |
| `scenesEqual` returns `true` | the same |
| `accessibilityEqual` returns `true` | the same |
| M1l `stateSlotsEqual` returns `true` | the same |
| M1k `DifferentialRoot`'s proposal-side overlay aligned `.center` | `theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement`, `theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities` |
| `noteUnlowerable` never traps | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority`, `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` |
| M1n `Frame.requestNode`'s backstop guard removed — **at `68200dc`** | **nothing**: `Test run with 1368 tests in 1 suite passed`. Not equivalent: a site that forgets its own check would register a real legacy node under the proposal authority. The gap `1.5b` closes |
| M1n — at `a155251` | `… failed … with 3 issues`: `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` (child exits 0; no backstop message; the diagnostics arm's node is not native) |
| M1n′ `Frame.requestLeaf`'s backstop guard removed — at `a155251` | `… failed … with 3 issues`: `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` |
| M1m the scene comparison reads emission bytes only (the finalized rects, glyphs and `drawList` clauses deleted) — at `a155251` | `… failed … with 1 issue`: `theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState` (arm d) |
| G1 `LayoutAuthority` and `Window.layoutAuthority` made `public` | `aPlainImportCannotChooseTheLayoutAuthority` |

Not separately pinned: the `drawList` clause of `scenesEqual` (no harness arm
emits glyphs, so no arm differs in the rect/glyph interleave alone). 1.1's
defaults claim no mutation (spec §6).

### Pixels

`CN-R`'s harness (`DEMO_PIXELS_SMALL=1`), re-taken by the lane-1 verifier from
`git archive`s of `c2290fc` and `68200dc`, twelve images each: **12 of 12 read 0
differing pixels, scene identical.** Controls on `c2290fc`: `default-light-f0`
vs `default-dark-f0` 1 048 576; vs `modal-light` 1 030 498; vs
`animation-light` 210 027; `preview-light` vs `preview-dark` 1 048 576 —
record §16/§17's figures. `git diff --stat 68200dc a155251 -- Sources` is empty
(the verifier round touched `Tests/` and docs only), so that measurement is
the one for this lane's final tree; it was not re-run.

### Probe

`/usr/bin/swift docs/probes/swiftui-engine-replacement-stage1.swift` → exit 0,
79 lines, matching the header's output block line for line (verifier).

### Screen lock

`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` → `<true/>` at both of the
verifier's checks and at 22:22:01 PDT on this round. No real-window capture
was attempted.

### Verifier round dispositions

1. **major** — lane 1 not closed out: this section; the unreverted M1b the
   verifier found in the worktree was reverted by the verifier.
2. **minor** — the amend mutations truncate the run: recorded above, and 1.5's
   amend arm now runs in a child process, so both variants redden 1.5 by name.
3. **minor** — the backstop is unpinned: `1.5b`
   `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` (two exit children, one
   in-process diagnostics loop); M1n and M1n′ redden it.
4. **minor** — `scenesEqual` ignored paint order and layer: it now also compares
   `finalizedScene()`'s rects, glyphs and `drawList`; `LR-D`, the harness doc and
   spec §6 say so; arm 1.9d was red first.

## Lane 2 — the leaf half: childless `Box`, `Text`

Commits: `4e15733` (tests, red), `57c6250` (implementation), `913680b` (2.8's
new arms and child process, red on `57c6250`), `8a28c4d` (the wrap-width fix and
`measuredNode` removed, `LR-X`), and this record.

### Red first

- `4e15733`, on lane 1's `e95cb5f` sources (`swift test --build-system native
  --no-parallel --filter "LoweringLeafTests|everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn"`):
  `Test run with 9 tests in 0 suites failed after 0.298 seconds with 195
  issues` — 2.1 12 issues, 2.2 9, 2.3 29, 2.4 96, 2.5 32, 2.6 2, 2.8 10, and 1.5
  5 (its amended `Box`, `Text`, both `ModifiedElement` and `List` arms). Every
  failure reads the site-level `box.noLowering`/`text.noLowering` entry or its
  0×0 rect (e.g. `LoweringLeafTests.swift:82:5: Expectation failed:
  pxReport.loweredBounds[leafID] == bounds(0, 0, 30, 20)`; 2.6's `:284:5
  report.unlowerable.isEmpty` and `:291:5 lowered.size.width == …`; 2.6's
  `legacy.size.width == px(60)` passed, so the legacy side measured 60 as
  predicted). 2.7 passed on arrival (characterization).
- **2.7 measured before its literal was written:** `proposalTextMeasurement` at
  widths 0 and 5 → `SizeD(width: 11.1845703125, height: 592.0)`; tokenizer
  min-content 40.44091796875; the widest single character unwrapped 7.9091796875.
  The spec's "widest word" was wrong: each line is one character, and a word's
  last character carries the hung space. The test's oracle shapes those 37 lines
  one at a time (`LR-X`).
- `913680b`, on `57c6250` sources (filtered): `Test run with 1 test … failed …
  with 2 issues` — `LANE2-2.8 width(30) agrees=false scenes=false
  disagreeing=[] unlowerable=[]` and `width(5) agrees=false scenes=false`;
  `width(100)` and `height(40)` `agrees=true`.

### Suite

- `57c6250`, after `swift package clean` (`Text.Layout` gained `measuredNode`):
  `Test run with 1377 tests in 1 suite passed after 41.918 seconds` (1369 + 8);
  0 `error:`; the one `warning:` is SwiftPM's `--build-system native` notice.
- `8a28c4d`, after `swift package clean` (`measuredNode` removed): `Test run with
  1377 tests in 1 suite passed after 41.972 seconds`; 0 `error:`, one `warning:`
  (the same notice). Goldens: `find Tests -name "*.json" | wc -l` → 97; `git diff
  --stat c2290fc -- '*.json'` empty. No guard added (70 + G1 = 71, unchanged by
  this lane).

### Mutations

Each: committed tree, file copied aside, mutant applied, `swift build
--build-system native --build-tests`, full unfiltered `swift test
--build-system native --no-parallel --skip-build`, restored from the copy, `git
status --short` empty after every one.

**Round 1, on `57c6250`:** M2a–M2g as below (same reddened tests); **M2h**
(`Text` returned `lowered.content` as its node and layout node) — **the suite
truncated, no summary line**: `LayoutTree.swift:717: Precondition failed: native
layout node 0 registered under a second parent (node 2)` inside 2.8 (the root
overlay registered the leaf its frame already held; practices shape 13);
**M2i** (paint wraps at `layout.node` instead of `layout.measuredNode`) — `Test
run with 1377 tests in 1 suite passed`. Proving the M2i mutant different
(practices, "a mutation that reddens nothing"): `Text(long).width(w)` through the
harness, both spellings, `w` ∈ {5, 30, 45, 100}:

```
measuredNode (57c6250): w=5 scenes=false  w=30 scenes=false  w=45 scenes=true  w=100 scenes=true   (disagreeing=[] and 37 glyphs a side throughout)
layout.node (M2i):      w=5 scenes=true   w=30 scenes=true   w=45 scenes=true  w=100 scenes=true
```

So the mutant was the correct spelling and the design wrong; `LR-X`, `913680b`
(red), `8a28c4d` (fix).

**Round 2, on `8a28c4d`** (the lane's final tree):

| mutation | reddened |
|---|---|
| M2a rem lowered as px (× 1) | `aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation` (5 issues) |
| M2b padding registered outside the size frame | `aLoweredBoxPaddingSitsInsideItsDeclaredSize` (3) |
| M2c the `margin` check deleted | `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (2) |
| M2d `.rowReverse` reported on a leaf | `everyContainerFieldIsIgnoredOnALoweredLeaf` (8) |
| M2e the lowered leaf measures at 13pt whatever `fontSize` | `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth` (12) |
| M2f the lowered leaf answers the proposed width | `everyContainerFieldIsIgnoredOnALoweredLeaf`, `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`, `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock`, `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin` (43) |
| M2g `min(widest, proposal)` clamp in `proposalTextMeasurement` | `aProposalTextBelowItsNarrowestWordAnswersItsWidestCharacterWhereSwiftUIAnswersTheProposal` (4) |
| M2h the text leaf returned as the element's node (frame still registered around it) | `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin` (5; the child exits on `CN-L`'s precondition) — no truncation |
| M2i paint wraps at the leaf's answer to the frame's width (the `measuredNode` design, re-spelled in `paintGlyphs`) | `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin` (2) |
| M2k the leaf's size frame aligned `.center` | **nothing** (`passed`). Equivalent by reading, not demonstrated: in stage 1 nothing reads the rect of a node inside a leaf's frame — `elementBounds`, hitboxes, decoration and glyph origin all read the element's node, and glyphs wrap at its width. It becomes observable when a `Text` gains lowered padding (stage 2) |
| M2m `Text`'s authority check forced false (legacy registration under the proposal authority) | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`, `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf`, `everyContainerFieldIsIgnoredOnALoweredLeaf`, `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`, `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock`, `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin` (81) |
| M2n the `padding.text` check deleted | `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (1) |

### Verifier round 1

The verifier (suite 1377 at `73ce03f`, 12 of 12 images 0 differing pixels) found
four sub-clauses green under mutation, each proven non-equivalent by a scratch
run: **V3** the height half of `padding.floor` deleted (100×10 box padded 8
vertically: legacy 100×16, lowered 100×10, nothing reported); **V4** `display:
none` appended rather than returned alone; **V5** the `dropLast()` recording loop
deleted (only the last field recorded; production would trap on it); **V7** `Box`
lowering its declared style. Tests added in `a9fceb5` (committed before any
mutation, no source change): 2.3 gains four combined rows on both sites (floor
width-only, floor height-only, `display.none` + margin → `[display.none]`, margin
+ flexGrow → `[margin, flexGrow]`; `try #require(arms.count == 37)`), exit test
2.3b `aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction`, and 2.3c
`aLoweredBoxRegistersItsAnimatedWidth` (20 at the transaction's start, 60
half-way, under both authorities). They pin current behaviour, so each was
reddened by its mutation rather than on arrival. Each mutation as in round 2
(copy aside, full unfiltered suite with `--skip-build`, restored, `git status
--short` empty):

| mutation | reddened |
|---|---|
| V3 the floor check's height branch deleted | `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (2: Box and Text height-only arms) |
| V4 `display.none` appended, other checks run | `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (2) |
| V5 the `dropLast()` `noteUnlowerable` loop deleted | `aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction`, `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (4) |
| V7 `Box` passes `declared` as the lowered style | `aLoweredBoxRegistersItsAnimatedWidth` (2) |

Suite on `a9fceb5` (no stored property changed, so no clean): `Test run with 1379
tests in 1 suite passed after 41.802 seconds` (1377 + 2); 0 `error:`, one
`warning:` (SwiftPM's `--build-system native` notice). Goldens 97, untouched. No
source changed, so the pixel comparison below stands.

### Pixels

`CN-R`'s harness (`gen.py`, `DEMO_PIXELS_SMALL=1`) generated into a `git archive`
of the lane's tree, twelve images, compared with lane 1's `c2290fc` images
(`lr1-px-base`, generated by lane 1 from a `c2290fc` archive): **12 of 12 read
0 differing pixels, scene identical** — at `57c6250` and again at `8a28c4d`
(after `swift package clean` in the archive). Controls, re-read on both the base
and `8a28c4d`'s images: `default-light-f0` vs `default-dark-f0` 1 048 576; vs
`modal-light` 1 030 498; vs `animation-light` 210 027; vs `default-light-f3` 0;
`preview-light` vs `preview-dark` 1 048 576. Expected: no production root is
under the proposal authority, and the legacy branch of `Box` and `Text` changed
only by capturing `declared` (`Box`) and its `Layout` initializer.

### Probe

`/usr/bin/swift docs/probes/swiftui-engine-replacement-stage1.swift` → exit 0,
79 lines, `diff` empty against the header's output block. Lane 2 makes no new
SwiftUI claim; the arms it cites (T2, T3, T4, B1) are from that run.

### Screen lock

`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` → `<true/>` at 22:42 and
22:54 PDT. No real-window capture was attempted.

## Lane 3 — containers: `Row`, `Column`, `Box` with children; mixed trees

Commits: `ae2027a` (tests, red), `35c588e` (implementation), `24fa898` (3.5's
`display: .stack` arm, after M3l), and this record with spec and `LR-Y`.

### Red first

- `ae2027a`, on lane 2's `a74ce8a` sources (`swift test --build-system native
  --no-parallel --filter "LoweringContainerTests|everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn"`):
  `Test run with 8 tests in 0 suites failed after 0.271 seconds with 144
  issues` — 3.1 36, 3.2 9, 3.3 54, 3.4 14, 3.5 25, 3.6 4, 3.7 1, and 1.5 1 (its
  amended `List` arm: the zero-row `Box` still read `box.noLowering`). Every
  failure reads the site-level entry or its 0×0 rect, e.g.
  `LoweringContainerTests.swift:89:32: Expectation failed: r.unlowerable.isEmpty`,
  `:322:5: twoChild.unlowerable == [field(.box, "alignItems.stretch")]`, and all
  fifteen 3.5 report arms at `:383:9`. 3.6's four legacy literals passed on
  arrival (legacy 50/50 at x 0 and 50, row 100×20), so the legacy side measured
  as derived.
- **The first red run truncated** (no summary line):
  `MetalUI/Frame.swift:1531: Fatal error: MetalUI: box.noLowering has no proposal
  lowering` — 3.7's `Window` half renders **without** diagnostics, and the report
  check above it was an `#expect`, so the test went on to drive the window
  (practices shape 13). The check became a `try #require` before the commit; the
  run above is the second.

### Suite

- `35c588e` (no stored property on a public type changed, so no clean): `Test run
  with 1386 tests in 1 suite passed after 41.892 seconds` (1379 + 7); 0 `error:`;
  the one `warning:` is SwiftPM's `--build-system native` notice.
- `24fa898` + this record's docs (Sources unchanged since `35c588e`), 23:58 PDT:
  `Test run with 1386 tests in 1 suite passed after 41.965 seconds`; 0 `error:`, no
  `warning:` besides the notice (also after touching the four changed files and
  rebuilding); the `CONTAINER GUARD` lines printed (7), so the guards ran.
  Goldens: 97; `git diff --stat c2290fc -- '*.json'` empty. No guard added.

### Mutations

Each on the committed tree (M3a–M3k, M3m–M3s on `35c588e`; M3l's second run on
`24fa898`): `LegacyLowering.swift` copied aside, mutant applied, `swift build
--build-system native --build-tests`, full unfiltered `swift test --build-system
native --no-parallel --skip-build`, restored from the copy, `git status --short`
empty after every one. Issue counts in parentheses.

| mutation | reddened |
|---|---|
| M3a the stack's cross factor `1 − f` (`flexStart` ↔ `flexEnd`) | `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren` (16), `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems` (24) |
| M3b stack spacing 0 | 3.1 (12), `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis` (6), `aLoweredContainerPaddingSitsInsideItsDeclaredSize` (5), `aProposalElementInsideALoweredContainerLaysOutUnderTheProposalAuthorityAndTrapsUnderTheLegacyOne` (5) |
| M3c the gap's axes swapped | 3.2 (6) |
| M3d the size frame's main and cross factors swapped | 3.3 (24), `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren` (2) |
| M3e padding registered outside the size frame (shared with the leaf path) | 3.4 (6), `aLoweredBoxPaddingSitsInsideItsDeclaredSize` (3) |
| M3f stretch always lowerable | `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (3) |
| M3g the container's size frame aligned `.center` | 3.3 (32), 3.4 (2), 3.6 (2) |
| M3h a native child reported as `box.nativeChild` | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (1), 3.1 (36), 3.2 (9), 3.3 (54), 3.4 (14), 3.5 (10), 3.6 (4), 3.7 (1) — every child is native under this authority, so it cannot single out 3.7 |
| M3i the `gap.percent` check deleted | 3.5 (1) |
| M3j `space-*` reported whatever the main size | 3.5 (3) |
| M3k stretch's declared-cross-size half deleted | 3.5 (1) |
| M3l the `display: .stack` → `noLowering` check deleted — on `35c588e` | **nothing** (`Test run with 1386 tests in 1 suite passed`). Not equivalent: the report goes from `[box.noLowering]` to empty and the children lower as a flex row instead of an overlay. `24fa898` added the arm |
| M3l — on `24fa898` | 3.5 (1) |
| M3m the every-node rows not appended for a container | 3.5 (2: `margin`, `padding.floor`) |
| M3n `display.none` not checked first | 3.5 (1: the hidden reverse arm reads `reverse`, …) |
| M3o the `reverse` check deleted | 3.5 (2) |
| M3p the `alignItems.baseline` check deleted | 3.5 (1) |
| M3q the `flexWrap` check deleted | 3.5 (1) |
| M3r the `alignContent` check deleted | 3.5 (1) |
| M3s the axis inverted (`!isRow`) | 3.1 (24), 3.2 (6), 3.3 (36), 3.4 (5), 3.5 (4), 3.6 (3), 3.7 (7) |

### Pixels

`CN-R`'s harness (`gen.py`, `DEMO_PIXELS_SMALL=1`) generated into a `git archive`
of `35c588e` (built in the scratchpad, outside the worktree, while M3b–M3h ran in
the worktree; the archive is a pinned, isolated tree), compared with lane 1's
`c2290fc` images (`lr1-px-base`): **12 of 12 read 0 differing pixels, scene
identical.** Controls on the head images: `default-light-f0` vs `default-dark-f0`
1 048 576; vs `modal-light` 1 030 498; vs `animation-light` 210 027; vs
`default-light-f3` 0; `preview-light` vs `preview-dark` 1 048 576. `24fa898`
changed only `Tests/`, so the measurement stands for the lane's final Sources.

### Probe

Lane 3 makes no new SwiftUI claim; 3.6 cites stack-algorithms G9/X13 and 3.4
stage-1 B1/B3, from their recorded runs. Not re-run.

### Screen lock

`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` → `<true/>` at 23:41 and 23:59
PDT. No real-window capture was attempted.

### Verifier round 1

The verifier (suite 1386 at `3489561`, 12 of 12 images 0 differing pixels) found
two sub-clauses green under mutation, each proven non-equivalent by a scratch
run: **V1** the container branch laying out `declared` (size frame, padding and
`declared.gap`) — container animation snaps under the proposal authority (a row
animating width 40→120 read 120 on the start and half-way frames, legacy 80);
**V2** `legacyLeafDiagnostics(…) + fields`, which reorders `LR-Y`'s report so
production traps on an every-node field. It also found §5.4's report-order
paragraph splitting the containers table (moved below the table's last row).

Tests added in `6b8fda1` (committed before any mutation, no source change):
3.8 `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap` — a row `Box` over
two 10×10 children, width 40→120, padding 0→8, gap 0→20 under
`.linear(duration: 1)`: the transaction's start frame reads 40×10 with b at x 10,
half-way reads 80×18 with a at (4, 4) and b at (24, 4), under both authorities
(literals derived before the run); 3.9
`aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`
— `Box { a; b }` with `rowReverse`, `flexWrap`, `margin(3)`, `flexGrow(1)`
reports `[reverse, flexWrap, margin, flexGrow]`, and an exit test with
diagnostics off traps naming `box.reverse has no proposal lowering` and not
`box.margin`. Both pin current behaviour and passed on arrival (filtered: `Test
run with 2 tests in 0 suites passed`), so each was reddened by its mutation.
Each mutation as above (copy aside, native build, full unfiltered suite with
`--skip-build`, restored, `git status --short` empty):

| mutation | reddened |
|---|---|
| V1 the container branch passes `declared` to `paddedAndSized` and reads `declared.gap` | `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap` (2: the start and half-way frames) — `Test run with 1388 tests in 1 suite failed … with 2 issues` |
| V2 `return legacyLeafDiagnostics(declared, site: site) + fields` | `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` (3: the report, the trap's `box.reverse`, its absent `box.margin`) |
| V2b the `flexWrap` check moved above `reverse` | `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` (2: the report, the trap's `box.reverse`) |

Suite on the restored `6b8fda1` sources, rebuilt (no stored property changed, so
no clean), 00:16 PDT: `Test run with 1388 tests in 1 suite passed after 41.850
seconds` (1386 + 2); 0 `error:`, one `warning:` (SwiftPM's `--build-system
native` notice). Goldens 97, `git diff --stat c2290fc -- '*.json'` empty. No
guard added. `Sources/` is unchanged since `35c588e`, so the pixel comparison
above stands; the probe was not re-run (no new SwiftUI claim).

## Lane 4 — `Stack` and `ModifiedElement` layers; ideal under the proposal authority

Commits: `6d0d910` (tests, red), `4446336` (implementation, with 4.6's proposal
arm respelled — below), and this record with spec and `LR-Z`.

### Red first

- `6d0d910`, on lane 3's `918bbc3` sources (`swift test --build-system native
  --no-parallel --skip-build --filter
  "LoweringStackAndLayerTests|everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn|stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem|anIdealDimensionOnTheLegacyFrameTraps"`):
  `Test run with 12 tests in 0 suites failed after 0.512 seconds with 199 issues`
  — 4.1 71, 4.2 3, 4.3 18, 4.4 76, 4.5 6, 4.6 2, 4.7 6, 4.8 8, 4.9 5; 1.5 3 (its
  `Stack` and two `ModifiedElement` arms still read `noLowering`); 3.5 1 (its
  `display: .stack` `Box` arm read `[box.noLowering]`); the amended ideal pin
  passed (the construction trap still names `idealWidth`). Every lowering failure
  reads the site-level entry or its 0×0 rect, e.g.
  `LoweringStackAndLayerTests.swift:127:28: Expectation failed: r.unlowerable.isEmpty`
  (4.1), `:292:32` (4.4), `:486:9: entries == expected` (4.8); 4.6's
  `:378:26: expected exit status ".success", but ".signal(SIGTRAP)"` — the child
  hit the construction trap. No legacy-side literal failed (4.2's legacy 60, 4.5's
  legacy 40 at x 30 and 20 at x 40, 4.4's legacy rects), so the legacy side
  measured as derived.
- **The first red run truncated** (no summary line): `MetalUI/NativeModifiedContent.swift:110:
  Precondition failed: a native outer modifier must wrap exactly one native layout
  node` — 4.4's zero-node arm was spelled `EmptyGroup().frame(…)`, and `EmptyGroup`
  is a `ProposalElementGroup`, so it resolved to the **proposal** frame. Respelled
  over a component with no node (`NoNodes`) before the commit; the run above is
  the second.
- **4.6's proposal arm was wrong as first written**, found green-side: after the
  implementation it read `20×20`, not `80×20`. It put the frame in a lowered
  `Row`, and the kernel stack proposes its own finite proposal, where an ideal-only
  frame answers its child (frame probe C control). The arm now measures under a
  test-only `NilProposal` layout (`LR-Z`), in a child process as before, with the
  native root centred at its answer (`CN-J`): frames (60, 90) 80×20 and
  (90, 60) 20×80, box (90, 90). Its red, re-taken on a `git archive` of
  `6d0d910` with the respelled test file copied in: `Test run with 1 test … failed
  … with 2 issues` — `:440:26 expected exit status ".success", but
  ".signal(SIGTRAP)"` and `:461:5 out.contains(expected)`.
- **The amendment's evidence**: `918bbc3`'s construction-only
  `anIdealDimensionOnTheLegacyFrameTraps`, run on a `git archive` of `4446336`:
  `failed … with 3 issues` — both failure arms `expected exit status ".failure",
  but ".exitCode(EXIT_SUCCESS)"` and the missing `idealWidth` message. The
  amended pin renders and passes.

### Suite

- `4446336` after `swift package clean` (`ModifierLayer` gained a stored property
  and lost one): `Test run with 1397 tests in 1 suite passed after 42.125 seconds`
  (1388 + 9); 0 `error:`; the one `warning:` is SwiftPM's `--build-system native`
  notice. Goldens 97; `git diff --stat c2290fc -- '*.json'` empty. No guard added.
- After the mutation round, sources restored (`git diff -- Sources Tests` empty) and
  rebuilt, 00:53 PDT: `Test run with 1397 tests in 1 suite passed after 42.195
  seconds`; 0 `error:` in build and test logs; no `warning:` besides the notice.

### Mutations

Each on `4446336`: mutant applied by script (the target string asserted unique),
native build, full unfiltered `swift test --build-system native --no-parallel
--skip-build`, the file restored from `git show HEAD:<file>` copied aside before
the build, `git status --short` showing only this lane's uncommitted docs after
every one. Issue counts in parentheses.

| mutation | reddened |
|---|---|
| M4a the stack's horizontal and vertical factors swapped | `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` (24) |
| M4b each lowered stack child wrapped in a native `fixedSize` | `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` (2) |
| M4c native padding's top and bottom insets swapped (shared by every lowering) | `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (6), 4.1 (18), `aLoweredContainerPaddingSitsInsideItsDeclaredSize` (4) |
| M4d the frame layer's alignment forced `.center` | `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` (32) |
| M4e the maxima not passed to the kernel frame | `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps` (1: the `try #require` disagreement of the first arm, which then stops the test) |
| M4f the ideals not passed | `anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne` (1) |
| M4g bounds read from `FrameSpec` alone | `aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries` (2: the start and half-way frames) |
| M4g′ the check compares the animated style | 4.7 (4) |
| M4h the check compares `frameSpec.style()` without `lowered` | 4.4 (72), 4.5 (6), 4.6 (1), 4.7 (6), `aSizingModifierWrittenAfterAFrameIsReportedOnTheFrameLayer` (4) |
| M4i `display.none` checked after the comparison | `aHiddenFrameLayerIsReportedAsDisplayNone` (4) |
| M4j the legacy registration's ideal trap removed (`ModifiedElement.swift`) | `anIdealDimensionOnTheLegacyFrameTraps` (3), 4.6 (4) — 7 issues |
| M4k the `frame.multipleNodes` check deleted | 4.9 (1) |
| M4l the stack's `justifyItems.stretch` row deleted | 4.1 (1), `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (1) |
| M4m the every-node rows not appended for a stack | 4.1 (1), `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (1) |
| M4o the stack's `alignItems.baseline` row deleted | 4.1 (1) |
| M4p the stack branch disabled (a stack lowers as a flex row) | 4.1 (38) |

Every mutation reddened at least the test the spec names; none left the suite
green.

### Pixels

`CN-R`'s harness (`gen.py`, `DEMO_PIXELS_SMALL=1`) generated into a `git archive`
of `4446336` (built in the scratchpad), compared with lane 1's `c2290fc` images
(`lr1-px-base`): **12 of 12 read 0 differing pixels, scene identical.** Controls on
the head images: `default-light-f0` vs `default-dark-f0` 1 048 576; vs
`modal-light` 1 030 498; vs `animation-light` 210 027; vs `default-light-f3` 0;
`preview-light` vs `preview-dark` 1 048 576. The respelled 4.6 changed only
`Tests/` before `4446336`, and nothing in `Sources/` changed after it.

### Probe

Re-run this lane under `/usr/bin/swift`, exit 0:
`docs/probes/swiftui-frame-semantics.swift` (291 lines) and
`docs/probes/swiftui-stack-algorithms.swift` (787 lines); every output line appears
verbatim in the file's recorded header. Arms cited: frame A5, B9 (60×40), C control
(`frame(idealWidth: 80)` at 300×200 → 20×20), C1 (at nil → 80×20), D control
(`minWidth 40, maxWidth 80` at 100×100 → 80×20); stack-algorithms A5 (`ZStack` of
a greedy child at 100×80 → 100×80), G9 and X13 (160×20).

### Screen lock

`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` → `<true/>` at 00:40 PDT. No
real-window capture was attempted.

### Findings for later phases

- CLAUDE.md's "stack children get a nil main offer" (proposal path, "Unprobed
  kernel behaviour") does not describe the kernel stack at this commit: a lowered
  `Row` proposed its finite proposal to an ideal-only frame (4.6's first spelling).
  Docs phase.
- `EmptyGroup` is a `ProposalElementGroup`, so `EmptyGroup().frame(…)` is the
  proposal frame and traps on zero nodes (`SA-R`'s single-child precondition).

### Verifier round 1

The verifier (suite 1397 at `1b89197` after a clean, 12 of 12 images 0 differing
pixels, frame probe re-run) found three sub-clauses green under mutation, each
proven non-equivalent by a scratch witness: **V4** the `Stack` branch of
`lowerLegacyNode` passing `declared` to `paddedAndSized` (an animated stack width
snaps under the proposal authority); **V2** a frame layer's `minWidth` read from
`FrameSpec` instead of the animated `style.minSize` (4.7 pins only the fixed
width); **V6** the 0×0 stand-in leaf under a frame over no node answering 10×10
(4.4's arm is fixed on both axes, where the leaf cannot show).

Tests added in `cb3dc10` (committed before any mutation, no source change; literals
derived by hand before the run, filtered run `Test run with 3 tests in 0 suites
passed` on arrival, so each was reddened by its mutation):

- 4.10 `aLoweredStackLaysOutItsAnimatedWidthAndPadding` — a `.topLeading` `Stack`
  over a 10×10 box, height 20, animating width 40→120 and `Style.padding` 0→8
  under `.linear(duration: 1)`: before and at the transaction's start 40×20 with the
  box at (0, 0); half-way 80×20 with the box at (4, 4) (padding inside the declared
  size, `LR-E`), under both authorities;
- 4.11 `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle` — per axis
  and per bound, each 40→80: `.frame(minWidth:)` over 10×10 (40×10, 40×10, 60×10),
  `.frame(minHeight:)` over 10×10, `.frame(maxWidth:)` over a 100×10 box and
  `.frame(maxHeight:)` over a 10×100 box (larger than the maximum, so the legacy
  clamp and the lowered greedy maximum agree), under both authorities;
- 4.12 `aFrameOverNoNodeFixedOnOneAxisOrMinOnlyIsZeroOnTheOther` —
  `NoNodes().frame(width: 40)` and `NoNodes().frame(minWidth: 40)`, each with a
  background: 40×0 on both sides, full agreement (scenes, hitboxes, accessibility,
  state slots). This is `LR-Z`'s "fixed or min-only" row made observable.

Each mutation: sources copied aside, the edit, native build, full unfiltered suite,
restored from the copy, `git status --short` empty:

| mutation | reddened |
|---|---|
| V4 `paddedAndSized(overlay, declared, alignment:)` in the `Stack` branch | `aLoweredStackLaysOutItsAnimatedWidthAndPadding` (2: proposal transaction start and half-way) — `Test run with 1400 tests in 1 suite failed … with 2 issues` |
| V2 `minWidth: spec.minWidth.map { Double($0.value) }` | `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle` (1: `minWidth .proposal`) |
| V2h the same for `minHeight` | 4.11 (1: `minHeight .proposal`) |
| V2x the same for `maxWidth` | 4.11 (1: `maxWidth .proposal`) |
| V2y the same for `maxHeight` | 4.11 (1: `maxHeight .proposal`) |
| V6 the stand-in leaf answers 10×10 | `aFrameOverNoNodeFixedOnOneAxisOrMinOnlyIsZeroOnTheOther` (6: disagreement, scenes and the lowered rect, in each of its two arms) |

Suite on the restored sources at `cb3dc10`, rebuilt (tests only, no stored property
changed, so no clean), 01:12 PDT: `Test run with 1400 tests in 1 suite passed after
42.170 seconds` (1397 + 3); 0 `error:`, one `warning:` (SwiftPM's `--build-system
native` notice). Goldens 97, `git diff --name-only c2290fc` lists no `.json`. No
guard added. `Sources/` is unchanged since `4446336`, so the pixel comparison above
stands, and no new SwiftUI claim was made, so no probe was re-run.
`IOConsoleLocked` read `<true/>` at 01:13 PDT; no real-window capture.

## Lane 5 — demo content as a library; corpus; pipeline parity; depth and work

Commits: `f508003` (the library move alone), `abd424d` (tests, red: does not
compile), `d863ede` (implementation), `44f6e21` (window tests pre-flight their
trees, after a mutant truncated the run), and this record with the spec's lane-5
rows, `LR-AA` and doc comments that cited `main.swift` for moved content.

### The move (`f508003`, `LR-S`)

Everything in `Sources/MetalUIDemo/main.swift` before `runDemo()` moved to
`Sources/MetalUIDemoContent/DemoContent.swift`, a library target in no product;
`MetalUIDemo` and `MetalUITests` depend on it. `@MainActor` on `demoModel`,
`demoRows`, `demoWindow`, `counterID`, `didFocusCounter`; `public` only where
`main.swift` reads a name (`DemoModel` and its two properties, `demoModel`, the
eight actions with `public init()`, `demoWindow`, `counterID`, `demoContent()`,
`nativeLayoutPreviewContent()`); the two doc comments that said "top-level code in
`main.swift`" and the comments that pointed "below" at `runDemo`'s code rewritten.

- Suite: `Test run with 1400 tests in 1 suite passed after 42.212 seconds`
  (unchanged); build 0 `error:`, only SwiftPM's `--build-system native` notice.
- Pixels: the `CN-R` harness's generator rewritten to **import** the library
  (`scratchpad/harness/gen-lib.py`: `@testable import MetalUIDemoContent`, no copy
  of `main.swift`, no `nonisolated(unsafe)` rewrite), generated into a `git
  archive` of `f508003`, `DEMO_PIXELS_SMALL=1`, compared with lane 1's `c2290fc`
  images (`lr1-px-base`): **12 of 12 read 0 differing pixels, scene identical.**
  Controls on the head images: light vs dark f0 1 048 576; vs modal-light
  1 030 498; vs animation-light 210 027; f0 vs f3 0; preview light vs dark
  1 048 576 — the §1 baseline's figures.

### Red first

- **5.1**, run on `f508003` with `LoweringCorpusTests.swift` alone (the parity
  file not yet written): `Test run with 3 tests in 0 suites failed … with 1
  issue` — `LoweringCorpusTests.swift:320:9: Expectation failed:
  withBranch.elements == 11`. The transparent-groups tree recorded 10 elements:
  `AnyElement`'s own `prepaintGroup` did not record bounds (`LR-AA`). Every other
  corpus tree, 5.2 and 5.3 passed on arrival — lanes 2–4 did the lowering, so they
  are characterization, proven by their mutations below.
- **5.4–5.6**, at `abd424d` after `swift package clean`: the test target does not
  compile — `LayoutDifferential.swift:265:20: error: value of type 'Window' has no
  member 'recordsElementBounds'`, `:285:31` and `:285:69` `… 'lastElementBounds'`
  (with two follow-on `type '_' is not optional` at `:295:19`, `:296:19`),
  `LoweringPipelineParityTests.swift:151:33`, `:152:33`, `:277:63` `…
  'lastElementBounds'`, `:275:16` `… 'recordsElementBounds'`.
- **5.7**: the literals (16 nodes, 118 misses, 94 hits, 4 calls) were derived by
  hand in the test's doc comment before the first run; the first run matched all
  four.
- **5.8, 5.9** pin the existing guard; their mutations below are their evidence.

**Findings from the first runs** (before commit, recorded in `LR-AA`): the demo's
`CounterPanel` chrome reports `box.alignSelf`; the demo's header, in its own
spelling, reports `modifierLayer.alignItems.stretch` (a dump of the scratch run:
`header: elements=5 agree=1 differ=4 … unlowerable=[modifierLayer.alignItems.stretch]`);
the first 5.6 found no `$state0` id before the count was written and no `$ax` slot
on the unlabelled counter (the "+" button has one); `CountingLeaf` (the
modifier-composition chain's leaf) is a custom element, so the corpus chain is
over a `Box`.

### 5.3's measured census

`demoContent()` at 920×560 in the harness root, diagnostics on, modal and
animation off: 20 entries, in registration order — `box.flexGrow` (header bar),
`box.flexGrow` (header row), `modifierLayer.alignItems.stretch` (header padding
layer), `box.alignItems.stretch`, `box.flexGrow` (sidebar column),
`stack.alignSelf` (stack cluster), `box.alignSelf` (counter chrome),
`list.noLowering`, `box.flexShrink` (the `List`'s zero-row `Box`),
`scrollView.noLowering`, `box.minSize`, `box.flexGrow`, `box.flexBasis` (the box
around the scroller), `box.alignItems.stretch`, `box.flexGrow` (main pane column),
`modifierLayer.flexGrow` (main pane padding layer), `box.alignItems.stretch`,
`box.flexGrow` (body row), `box.alignItems.stretch`, `box.flexGrow` (outer
column). As a multiset: `box.flexGrow` 7, `box.alignItems.stretch` 4, one each of
the other nine. The same run: 2 036 element ids, 2 000 of them legacy-only (the
legacy side builds the list's rows; the lowered `List` reports before any row).

### Suite

- `d863ede` after `swift package clean` (`Window` gained stored properties):
  `Test run with 1409 tests in 1 suite passed after 46.143 seconds` (1400 + 9); 0
  `error:`; the one `warning:` is the `--build-system native` notice.
- Final tree (this record's commit: docs, and doc comments only under
  `Sources/`), 02:05 PDT: `Test run with 1409 tests in 1 suite passed after
  46.062 seconds`; 0 `error:` in build and test logs; no other `warning:`.
  Goldens 97, `git diff --name-only c2290fc` lists no `.json`. Guards 71 (no guard
  added this lane).

### Mutations

Each: mutant applied by script (target asserted unique), file copied aside first,
native build, full unfiltered `swift test --build-system native --no-parallel
--skip-build`, restored from the copy, `git status --short` empty after every one.
M5a, M2e, M2f, M3b and M5c ran on `d863ede`; the rest on `44f6e21`. Issue counts
in parentheses.

| mutation | reddened |
|---|---|
| **M5a** the proposal-side harness root proposes nil×nil (a native `fixedSize` under its frame) | `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (4), `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` (3), `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock` (1) |
| **M2e** (lane 2's, re-run) the lowered text measured at 13pt whatever its size | 5.1 (9), `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements` (8), `aLoweredWindowPublishesTheSameAccessibilityTree` (3), `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth` (12), `aLoweredContainerPaddingSitsInsideItsDeclaredSize` (3) |
| **M2f** = **M5b** the lowered text answers the proposed width | `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm` (1), 5.1 (18), 5.4 (8), 5.5 (3), `everyContainerFieldIsIgnoredOnALoweredLeaf` (24), `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth` (16), `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (6), `aLoweredContainerPaddingSitsInsideItsDeclaredSize` (3), `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` (2), `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock` (2), `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin` (1) |
| **M3b** (lane 3's, re-run) stack spacing dropped | 5.1 (23), 5.4 (18), 5.5 (1), `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths` (2), and lane 3's 3.1 (12), 3.2 (6), 3.4 (5), 3.7 (5), 3.8 (1) |
| **M4h** (lane 4's, re-run) the frame-layer check compares `frameSpec.style()` without `lowered` | **first run on `d863ede`: no summary line** — `MetalUI/Frame.swift:1532: Fatal error: MetalUI: modifierLayer.style has no proposal lowering`, inside 5.6's window (1 095 test lines printed). After `44f6e21`'s pre-flight: 5.1 (11), 5.2 (3), 5.6 (1, its pre-flight), and lane 4's 4.4 (72), 4.5 (6), 4.6 (1), 4.7 (6), 4.8 (4), 4.11 (16) |
| **M5c** two-child stretch made lowerable | `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (1), `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (2) |
| **M5d** lowered stack spacing + 50 | 5.4 (18), 5.5 (1), 5.6 (2), 5.1 (23), 5.2 (1), 5.7 (3), and lane 3's 3.1 (24), 3.2 (6), 3.3 (36), 3.4 (5), 3.5 (4), 3.6 (1), 3.7 (6), 3.8 (3) — 133 issues |
| **M5e** `Box` lowers its declared style | 5.6 (1), `aLoweredBoxRegistersItsAnimatedWidth` (2), `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap` (2) |
| **M5f** = **M5g** every lowered `Box` wrapped in a native `padding(0)` | 5.7 (3), `aLoweredChainAtTheNativeDepthLimitLaysOut` (2) |
| **M5h** `NativeLayoutRun.maxDepth` 96 | `aLoweredChainOneLevelPastTheNativeDepthLimitTraps` (2) |
| **MA** `AnyElement`'s bounds record removed | 5.1 (1) |
| **MW** `Window.lastElementBounds` not captured | 5.4 (1), 5.6 (2) |

Every mutation reddened the test the spec names; none left the suite green; after
`44f6e21` none truncated it.

### Pixels

- **The twelve** (`gen-lib.py`, into a `git archive` of `d863ede`, the last
  commit changing behaviour under `Sources/`; later `Sources/` changes are doc
  comments), against `lr1-px-base` (`c2290fc`): **12 of 12 read 0 differing
  pixels, scene identical**; controls as for the move, figure for figure.
- **The two-authority chrome pair** (`LR-M`): `DifferentialRoot(560×560) {
  StageOneCorpus.counterChrome() }` through a 560² fake `Window` under each
  authority: **`chrome-legacy` vs `chrome-proposal` 0 differing pixels, scene
  files byte-identical**; the image is not blank (216 distinct pixel values; vs
  `small560-default-light` 308 354). **Control, M5d** applied to a `git archive` of
  `44f6e21`: `chrome-legacy` vs `chrome-proposal` **8 214** differing pixels, scene
  files differ; the twelve's controls on that tree unchanged (1 048 576,
  1 030 498, 210 027, 0, 1 048 576).

### Probe

Re-run this lane under `/usr/bin/swift`, exit 0 each:
`swiftui-engine-replacement-stage1.swift` (79 lines), `swiftui-frame-semantics.swift`
(291), `swiftui-stack-algorithms.swift` (787); every output line appears verbatim in
the file's recorded header. Arms cited by 5.2: stage-1 **T2** (`Text(long) @60xnil:
size 45x112`), **T7** (text frame 60x112, `geometry text: (7.50, 0) 45x112`);
stack-algorithms **A5** (`ZStack{…} at 100x80 @100x80: size 100x80`), **G9** and
**X13** (160x20); frame **D control** (`frame(minWidth: 40, maxWidth: 80), proposal
100x100: size 80.0x20.0`).

### Screen lock

`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` → `<true/>` at 02:01 PDT. No
real-window capture was attempted.

### Findings for later phases

- The demo's own `CounterPanel` and header do not lower in stage 1
  (`box.alignSelf`; `modifierLayer.alignItems.stretch` from `.height(72)` after
  `.padding`): stage 2's exit test replaces `LowerableCounter` with
  `CounterPanel()` and the corpus's respellings with the demo's (`LR-AA`).
- `AnyElement`'s group entry, by reading, also skips `AB-O`'s
  `suppressingAccessibilityIfHidden`; unmeasured.
- 5.6 found no `StateTable` id for a declared, read, never-written `@State` in
  `LowerableCounter`; CLAUDE.md's "`@State` … seeding marks" paragraph should be
  checked against it (not investigated further). Docs phase.
- CLAUDE.md's non-test target count ("eight") is nine after `LR-S`; its citations
  of `main.swift` for demo content now point at `DemoContent.swift`. Docs phase.
- A window test under the proposal authority traps rather than reports; any later
  stage's window test needs `WindowPair`'s pre-flight or an exit test.

### Verifier round (lane 5)

**Verdict `ok: true`, four minor issues, no fix round.** Quoted from the
verifier (at `95234ae`): after `swift package clean`, `swift build
--build-system native --build-tests` → `Build complete!`, no `error:`, the only
`warning:` SwiftPM's `--build-system native` notice; the full unfiltered `swift
test --build-system native --no-parallel` → `Test run with 1409 tests in 1 suite
passed after 51.270 seconds.` Goldens 97, `git diff --name-only c2290fc` lists no
`.json`. `grep canTypecheck` 73 hits: 71 guards, the declaration and one comment;
lane 5 added no guard. A release build of `MetalUIDemo` on a `git archive` of
HEAD completes.

- **Red first, re-read.** Commit order `f508003` (the move), `abd424d` (tests
  referencing `Window.recordsElementBounds`/`lastElementBounds` before they
  exist), `d863ede` (implementation); 5.1's "10 vs 11" matches what MA
  reproduces.
- **Probe.** `/usr/bin/swift docs/probes/swiftui-engine-replacement-stage1.swift`
  exit 0, 79 lines, every one verbatim in the header, including T2 `45x112` and
  T7 `60x112`.
- **Pixels, independently.** The verifier did not reuse `lr1-px-base`: it rebuilt
  the baseline from a `git archive` of `c2290fc` with `gen.py` and the head from a
  `git archive` of HEAD with `gen-lib.py`, `DEMO_PIXELS_SMALL=1`. **12 of 12
  read 0 differing pixels, scenes identical.** Controls on the head: light vs dark
  f0 1 048 576; vs modal-light 1 030 498; vs animation-light 210 027; f0 vs f3 0;
  preview light vs dark 1 048 576; the default image has 544 distinct pixel
  values. The chrome pair: `chrome-legacy` vs `chrome-proposal` 0, scenes
  identical, 216 distinct values.
- **Screen lock.** `IOConsoleLocked` `<true/>` at 02:12 PDT; no real-window
  capture.

Each mutation: file copied aside, full build, full unfiltered suite, restored,
`git status --short` empty; none truncated the run.

| mutation | reddened |
|---|---|
| V5-1 (= MA) `AnyElement.prepaintGroup`'s `recordElementBounds` removed | `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (1: `withBranch.elements == 11`) |
| V5-2 (a different line from MW) `Window` passes `recordsElementBounds: false` to every `Frame` | `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements` (1), `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths` (2) — **not** 5.5 (minor 4) |
| V5-3 `NativeLayoutRun.maxDepth` 88 → 89 | `aLoweredChainOneLevelPastTheNativeDepthLimitTraps` (1: the stderr message check only; the 90-level chain still traps) — minor 1 |
| V5-4 the counter chrome's gap 12 → 14 in `DemoContent.swift` (the library, not a test copy) | 5.1 (1), 5.4 (2), `aLoweredWindowPublishesTheSameAccessibilityTree` (1) |
| V5-5 the stack cluster's `.alignSelf(.flexStart)` removed from `demoContent()` | `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (1) |
| V5-6 the outermost `ModifiedElement` layer lowers from its declared style | 5.6 (1), `aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries` (2), `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle` (4) |
| V5-7 `Frame.render` does not record the root's bounds | 29 issues across 26 tests: lane 5's 5.1, 5.2, 5.4; lane 1's `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer`, `theElementBoundsLogIsEmptyUnlessRequested`, `theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities`, `theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement`; lanes 2–4's `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin` (4) and 18 others at 1 each. The summary line printed (interleaved with SwiftPM's warning) |

**The four minor issues, open at this record's commit** (the record writer
changed no test or doc comment; each is carried in "Deferred" and "For the
integrator"):

1. **5.8/5.9 bracket the depth boundary between 87 and 90; they do not pin
   it.** V5-3 reddened only 5.9's message check; no test runs an 88- or 89-level
   lowered chain, and `maxDepth = 87` would by the same arithmetic leave 5.8
   green. 5.8's doc comment (`LoweringPipelineParityTests.swift:405`, "87 native
   levels, the deepest `NativeLayoutRun.maxDepth` (88) allows") is wrong: 88
   levels are allowed; 87 is the deepest multiple of 3. `LR-AA` item 7 repeats it.
   Required: reword both (the exact boundary rests on 5.9's message check and
   `SA-L`'s own pins), or add an arm whose innermost element costs 1 or 2 levels
   so a chain reaches exactly 88 (lays out) and 89 (traps).
2. **`LayoutDifferential.compareInWindows` has no caller.** `grep -rn
   compareInWindows Tests Sources` finds its declaration
   (`LayoutDifferential.swift:328`) and a header comment (`:18`); 5.4–5.6 use
   `WindowPair` directly, yet `LR-AA` item 4 and spec §5.2 describe it as the
   window comparison. Required: use it in one of 5.4–5.6, or delete it and say
   in `LR-AA` that `WindowPair` is the harness.
3. **The move made the demo's globals lazy, unrecorded until now.** `demoRows`
   (500 `DemoListRow`s) and `demoModel` were eager top-level code in
   `main.swift`; as `@MainActor` library globals they are initialized on first
   access, inside the first frame's `demoContent()`. **The cold frame `MP-I`
   measures now includes the demo's global initialization**, by an unmeasured
   amount. Pixels are unaffected (12 of 12, 0). No code change required.
4. **5.5 passes on an empty element-bounds log.** V5-2 reddened 5.4 and 5.6, not
   5.5 (the implementer's MW row reads the same); 5.5 has no `try
   #require(pair.report().elements == 8)`, so `expectWindowAgreement` compares
   two empty maps. Required: add it, as 5.4 has.

## What landed, in one place

Written by the record pass at `95234ae` (2026-09-17, PDT). Every figure below is
quoted from a section above, or re-read by the record pass where it says so.
The record pass changed only this file and the spec's Status; it ran no build,
no suite and no mutation (`git diff --stat 95234ae -- Sources Tests
Package.swift` is empty at its commit).

Thirty-one commits on `feat/engine-replacement` from `c2290fc`, in order.
**`Sources/` changed behaviour in six** (`68200dc`, `57c6250`, `8a28c4d`,
`35c588e`, `4446336`, `d863ede`); `f508003` moved the demo's content; `95234ae`
touched only doc comments under `Sources/`.

| commit | phase | what |
|---|---|---|
| `59fd180` | design | spec, decisions `LR-A`…`LR-P`, probe revision 1, this record's design round |
| `0db713a` | critic round 1 | thirteen-stage plan, per-site checks, the below-word clamp withdrawn, `LR-Q`…`LR-W`; probe revision 2 (group W) |
| `4ceb3e0`, `68200dc` | lane 1 | red (does not compile); authority, every site's own check, bounds log, harness |
| `ea7ac56`, `a155251`, `3ab7f0f`, `e95cb5f` | lane 1 verifier round | 1.5b backstop exit test, 1.5's amend arm in a child, 1.9 arm d (red); the harness compares the finalized scene and draw list; record |
| `4e15733`, `57c6250`, `913680b`, `8a28c4d`, `73ce03f` | lane 2 | red; childless `Box` and `Text` lowered; 2.8's narrow arms (red on `57c6250`); the wrap-width fix and `measuredNode` removed (`LR-X`); record |
| `a9fceb5`, `a74ce8a` | lane 2 verifier round | floor per axis, `display.none` alone, two-field order and trap (2.3b), animated width (2.3c); record |
| `ae2027a`, `35c588e`, `24fa898`, `3489561` | lane 3 | red; `Row`/`Column`/`Box` with children onto a native linear stack; 3.5's `display: .stack` arm after M3l; record, `LR-Y` |
| `6b8fda1`, `918bbc3` | lane 3 verifier round | 3.8 animated width/padding/gap, 3.9 report order and first-field trap; record |
| `6d0d910`, `4446336`, `1b89197` | lane 4 | red; `Stack` onto a native overlay, padding and frame layers onto the kernel, `FrameSpec` ideals, `FR-D` trap at legacy registration; record, `LR-Z` |
| `cb3dc10`, `f6ffd3b` | lane 4 verifier round | 4.10 animated `Stack`, 4.11 animated frame minima/maxima per axis, 4.12 frame over no node on one axis; record |
| `f508003` | lane 5 | the demo's content moved into the `MetalUIDemoContent` library (`LR-S`) |
| `abd424d`, `d863ede`, `44f6e21`, `95234ae` | lane 5 | red (does not compile); `Window` records element bounds, `AnyElement`'s entry records its bounds; window tests pre-flight their trees; record, `LR-AA` |
| this commit | record | lane 5's verifier round, these summary sections, the spec's Status |

**Source files, `git diff --stat c2290fc 95234ae -- Sources Package.swift`:**

| file | lines | what changed |
|---|---|---|
| `Sources/MetalUI/LayoutAuthority.swift` | +82, new | `LayoutAuthority` (`.legacy`, `.proposal`), `LoweringSite`, `UnlowerableField` — all internal |
| `Sources/MetalUI/LegacyLowering.swift` | +405, new | `lowerLegacyNode`, `lowerLegacyLayer`, `lowerLegacyLeaf`, `legacyLeafDiagnostics`, `legacyContainerDiagnostics`, `legacyFrameLayerDiagnostics`, `paddedAndSized` |
| `Sources/MetalUI/Frame.swift` | 95 | init parameters `layoutAuthority:`, `reportsUnlowerableFields:`, `recordsElementBounds:`; `unlowerableFields`, `elementBounds`, `noteUnlowerable`, `recordElementBounds`; the backstop preconditions in `requestNode`/`requestLeaf`; the root's bounds record in `render` |
| `Sources/MetalUI/Window.swift` | 30 | `layoutAuthority` (a write dirties), `recordsElementBounds`, `lastElementBounds` |
| `Sources/MetalUI/Passes.swift` | 24 | `lowersToProposal`; the public `requestNode`/`requestLeaf` report `customElement` |
| `Sources/MetalUI/Box.swift`, `Stack.swift`, `Text.swift` | 21, 9, 35 | each site's check and lowering branch; `Text` paints wrapped at its element node's width |
| `Sources/MetalUI/ModifiedElement.swift`, `FrameLayer.swift` | 48, 73 | both registrars' checks and lowering; `ModifierLayer.frameSpec`, `isFrame` computed; `FrameSpec.idealWidth`/`idealHeight`, `trapIfLaidOutByTheLegacyEngine()` (`FR-D` moved from construction to legacy registration) |
| `Sources/MetalUI/ScrollView.swift`, `List.swift`, `Component.swift` | 16, 16, 28 | site-level checks: `scrollView.noLowering`; `list.noLowering` before the `Box` is built; `component.amend` (skipping `setStyle`) and `component.wrap` |
| `Sources/MetalUI/ElementGroup.swift`, `StateTable.swift` | 10, 5 | bounds records in `Element.prepaintGroup` and `AnyElement.prepaintGroup`; `StateTable.ids` |
| `Sources/MetalUI/AnimatedStyle.swift`, `NativeModifiedContent.swift` | 3, 5 | doc comments |
| `Sources/MetalUIDemoContent/DemoContent.swift` | +1 045, new | everything in `main.swift` before `runDemo()`; `@MainActor` on the module-level state; `public` only where `main.swift` reads a name |
| `Sources/MetalUIDemo/main.swift` | −1 034 | imports `MetalUIDemoContent` |
| `Package.swift` | 11 | the `MetalUIDemoContent` target (in no product); `MetalUIDemo` and `MetalUITests` depend on it |

**Stored properties changed on public types** (each lane cleaned before its
suite): `Frame` gained five (lane 1); `Window` gained `layoutAuthority` (lane 1)
and `recordsElementBounds`, `lastElementBounds` (lane 5); `ModifierLayer` gained
`frameSpec` and its stored `isFrame` became computed (lane 4 — CLAUDE.md's
incremental-**link** hazard); `Text.Layout` gained `measuredNode` in `57c6250` and
lost it in `8a28c4d`. **The integrator cleans after the merge.**

**Counts at `95234ae`** (lane 5's verifier, native, after `swift package clean`):
`Test run with 1409 tests in 1 suite passed`; 0 `error:`; the only `warning:`
SwiftPM's deprecation notice; only the two gated tests skipped. Goldens **97**, no
`.json` changed since `c2290fc` at any lane. Guards **71**. `@available(*,
deprecated` hits in `Sources/` **34**, unchanged (record pass: `grep -c` summed at
`c2290fc` and at HEAD).

**What stage 1 did not do, by design (`LR-L`):** no production frame runs under
the proposal authority; no legacy element's layout under the default authority
changed; no golden, no CSS-engine test and no engine file was retired or deleted;
no demo pixel moved.

## The stage plan, as decided (`LR-L`, spec §4)

Thirteen stages after critic round 1 (nine in the first design). Each merges on
its own with the suite green; "demo" is the twelve-image `CN-R` comparison
against the previous stage's merge plus the two-authority chrome pair.

| # | stage | depends on | exit test | goldens | demo |
|---|---|---|---|---|---|
| **1** | lowering foundation — **landed here** | — | `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` | 0 | 0 px |
| 2 | flex-item semantics onto SwiftUI's: `flexGrow`, stretch (incl. `MC-Q` finding 7), CSS min/max (`FR-G`), `flexBasis`, `flexShrink`, `justifyContent` distribution, percentages, `margin`, `hidden()` (probe H), leaf padding, `BM-4`, `SA-N` item 4, `Row`/`Column` default spacing (52), overflow compression (55), `Text`/`ProposalText` unification and the below-word answer (T3/T4, W2) | 1 | 5.3 rewritten to require no **field** diagnostic, only `ScrollView`/`List`/`Deferred`/absolute site diagnostics | 0 | legacy 0; preview re-taken (scratch `SA-N` item 4 read 0 in all 12) |
| 3 | `ScrollView` lowered with one clamp/indicator shared with `ProposalScrollView` (54); `Component` distribution without `setStyle` (48, 56, frame over a multi-member component) | 1, 2 | `ScrollRoutingTests`, `ScrollIndicatorTests` under the proposal authority | 0 | 0 px |
| 4 | windowed proposal `List` (`TB-`, `AB-L`, `MP-I`, K6) | 2, 3 | `aListsWorkIsTheSameFor100kRowsAsFor500` and `ListTests`' windowing arms under the proposal authority, counting work | 0 | 0 px |
| 5 | `Deferred` as a presentation root; `.position(.absolute)`/`.inset` (9–11) | 2, 3 | `DeferredTests`, `AbsoluteOverlayTests` under the proposal authority | 0 | 0 px |
| G | grids, probe-backed `ProposalLayout`s | — | its own probe's arms | 0 | 0 px |
| 6a | public `LayoutPass.requestNode`/`requestLeaf` deprecated and every in-repo caller moved in one change (`LR-R`); CSS-answer tests pinned to `.legacy` | 1 | 0 `warning:` with the deprecation, `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne` | 0 | 0 px |
| 6b | **root switch**: `Window`'s default authority becomes proposal; demo re-spelled; root placement (4 vs `CN-J`); depth re-bisected in release | 2, 3, 4, 5, 6a | `noProductionFrameReachesTheLegacyEngine` over `demoContent()`, `nativeLayoutPreviewContent()` and a `List` through a `Window` | 0 | **changes, each named** |
| 7a | the 97 goldens retired, each by ruling naming its replacement or deleted concept | 2 | `find Tests -name "*.json" \| wc -l` reads 0 | **97** | 0 px |
| 7b | the non-golden CSS-engine tests retired (`LR-U`) | 2, 6a, 7a | a retirement table accounting for every removed `@Test`; `grep -rn "computeLayout(" Tests` empty | 0 | 0 px |
| 8 | sizing vocabulary onto `.frame` (`FR-F`/`FR-G`'s recipe), deprecated in the same change | 6b | 0 `warning:`; demo 0 px against 6b | 0 | 0 px |
| 9 | engine deletion (flex files, `LayoutContext`, legacy measure, tokenizer min-content, legacy registrars and authority) | 6b, 7a, 7b, 8 | the suite green with the files gone | — | 0 px |
| 10 | `Style`'s CSS fields and the closing check (`LR-P`) | 9 | `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` (`dlsym`, cannot skip) + plain-import guards + the recorded grep | — | 0 px |
| 11 | modifier unification (`LR-V`): `ModifiedElement`/`ModifiedContent`, legacy `.overlay`, `.opacity` (45, `OM-AA` a) | 9 | the outer-modifier-order probe's G3/G4 and the overlay-primary-shape probe through the unified type | 0 | named per change |

Dependencies were derived from a diagnostics census of each later stage's exit
suite under scratch P2 (critic round 1, above), not asserted. **Stage 2's entry
is 5.3's measured census**: 20 entries, `box.flexGrow` 7, `box.alignItems.stretch`
4, and one each of `modifierLayer.alignItems.stretch`, `stack.alignSelf`,
`box.alignSelf`, `list.noLowering`, `box.flexShrink`, `scrollView.noLowering`,
`box.minSize`, `box.flexBasis`, `modifierLayer.flexGrow`.

## Tests and guards, per file

**1357 → 1409, +52** (lane 1 +12: 10 + G1 + verifier 1.5b; lane 2 +10: 8 +
verifier 2; lane 3 +9: 7 + verifier 2; lane 4 +12: 9 + verifier 3; lane 5 +9).
`@Test` lines per file, `c2290fc` → `95234ae` (record pass, `grep -c '@Test'`):

| file | tests | what |
|---|---|---|
| `Tests/MetalUITests/LayoutAuthorityTests.swift` (new) | 0 → 11 | 1.1–1.10, 1.5b |
| `Tests/MetalUITests/LayoutAuthorityCompileGuards.swift` (new) | 0 → 1 | **one guard**, `typecheckFile`: G1 `aPlainImportCannotChooseTheLayoutAuthority` (prints `LAYOUT-AUTHORITY GUARD G1 choose: succeeded=false` / `control: succeeded=true`); mutated red once (made `public`) |
| `Tests/MetalUITests/LoweringLeafTests.swift` (new) | 0 → 10 | 2.1–2.8, 2.3b, 2.3c |
| `Tests/MetalUITests/LoweringContainerTests.swift` (new) | 0 → 9 | 3.1–3.9 |
| `Tests/MetalUITests/LoweringStackAndLayerTests.swift` (new) | 0 → 12 | 4.1–4.12 |
| `Tests/MetalUITests/LoweringCorpusTests.swift` (new) | 0 → 3 | 5.1–5.3 |
| `Tests/MetalUITests/LoweringPipelineParityTests.swift` (new) | 0 → 6 | 5.4–5.9 |
| `Tests/MetalUITests/LayoutDifferential.swift` (new) | helper | `DifferentialRoot`, `ProbeLeaf`, `LayoutDifferential.compare`, `compareInWindows` (no caller), `WindowPair` |
| `Tests/MetalUITests/FrameSizingTests.swift` | 16 → 16 | `anIdealDimensionOnTheLegacyFrameTraps` amended: its closures **render** under the legacy authority (`LR-H`) |
| `FocusTests`, `MeasurePerformanceTests`, `NestedClipTests`, `ScrollRoutingTests`, `NativeBoundaryIntegrationTests` | unchanged counts | doc comments: `main.swift` → `DemoContent.swift`, `LayoutPass.requestNode` → `Frame.requestNode` |

Guards **70 → 71**, per file: `PhaseSeparationTests` 19,
`ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
`ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
`ElementGroupTrapTests` 5, `ContainerCompileGuards` 4, `AXNodeTests` 3,
`DecorationCompileGuards` 3, `UnitSafetyTests` 2 (3 hits, one a comment),
`ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2,
**`LayoutAuthorityCompileGuards` 1**. `typecheckFile` guards 30 → **31**.

## Probes

| probe | arms | what it settled | positive controls |
|---|---|---|---|
| `docs/probes/swiftui-engine-replacement-stage1.swift`, revision 2 (new) | T0–T9, B0–B3, H0–H2, S0–S3, G0–G2 (revision 1, 61 lines); W0–W5 (revision 2, 79 lines) | `Text`'s answer at nil/narrow/zero/wide/∞ (T1–T6: widest line after wrapping; T3/T4: SwiftUI answers a below-word proposal); a text's own frame in a narrower fixed frame (T7, 60×112 with the text at 7.5); padding inside a fixed frame with alignment (B1, B3: the border-box lowering, `LR-E`); `.hidden()` keeps its space (H, stage 2); cross- and main-axis fill (S, G, stage 2); two texts in a narrow `HStack` (W, `LR-F`'s withdrawn clamp) | every group opens with a control that must differ. `/usr/bin/swift`, Apple Swift 6.4 (swiftlang-6.4.0.33.1), macOS 27.0 (26A428); each revision run at least twice byte-identical, revision 2 additive. Re-run by lanes 1, 2 and 5 and lane 5's verifier (79 lines, verbatim) |
| cited, re-run by lanes 4 and 5: `swiftui-frame-semantics.swift` (291 lines) | A5, B9, C control, C1, D control | the kernel frame's ideal at nil (C1, 4.6), its greedy finite maximum (D control, 4.5, 5.2) | C control 20×20 vs C1 80×20 |
| cited, re-run by lanes 4 and 5: `swiftui-stack-algorithms.swift` (787 lines) | A5, G9, X13 | `ZStack` offers its proposal (4.2), a stack overflows (3.6, 5.2) | X13 the nil-proposal control |
| `docs/probes/appkit-screen-lock-state.swift` (existing) | — | run at design time only: `IOConsoleLocked` `<false/>` but `CGSSessionScreenIsLocked = 1` (`LR-M`) | — |

## Red runs, in one place

| lane | red | green |
|---|---|---|
| 1 | `4ceb3e0`: a `git archive` fails to build, 72 error lines, all naming lane-1 API | `68200dc`: 1368 |
| 1 verifier round | `ea7ac56`: 1.9 arm d, `d.scenesEqual == false` failed (emission bytes only); 1.5b and the amend-arm move pin existing code | `a155251`: 1369 |
| 2 | `4e15733`, filtered: `9 tests … failed … with 195 issues` (2.7 green on arrival, characterization); `913680b` on `57c6250`: 2.8's width(30) and width(5) arms red | `57c6250`: 1377; `8a28c4d`: 1377 |
| 2 verifier round | `a9fceb5`'s additions pin current code; proved by V3, V4, V5, V7 | 1379 |
| 3 | `ae2027a`, filtered: `8 tests … failed … with 144 issues`; **the first red run truncated** (3.7's report check was an `#expect`) | `35c588e`: 1386 |
| 3 verifier round | 3.8, 3.9 green on arrival; proved by V1, V2, V2b | `6b8fda1`: 1388 |
| 4 | `6d0d910`, filtered: `12 tests … failed … with 199 issues`; **the first red run truncated** (`EmptyGroup().frame` resolved to the proposal frame); 4.6's proposal arm respelled after it read 20×20 green-side | `4446336`: 1397 |
| 4 verifier round | 4.10–4.12 green on arrival; proved by V4, V2/V2h/V2x/V2y, V6 | `cb3dc10`: 1400 |
| 5 | 5.1 on `f508003`: `with 1 issue`, `withBranch.elements == 11` (`AnyElement` recorded no bounds); 5.4–5.6 at `abd424d` do not compile; 5.7's literals derived first and matched; 5.2, 5.3, 5.8, 5.9 characterization | `d863ede`: 1409; `95234ae`: 1409 |

## Verifier verdicts, in one place

| lane | verdict | suite the verifier read | fix round |
|---|---|---|---|
| 1 | **`ok: true`**, no issues (second look at `e95cb5f`) | 1369 | `ea7ac56`, `a155251` (four issues from the first look, dispositioned in "Verifier round dispositions") |
| 2 | **`ok: true`**, no issues (second look at `a74ce8a`) | 1379 | `a9fceb5` (V3, V4, V5, V7) |
| 3 | **`ok: true`**, no issues (second look at `918bbc3`) | 1388 | `6b8fda1` (V1, V2, V2b) |
| 4 | **`ok: true`**, no issues (second look at `f6ffd3b`) | 1400, and 1400 again after its mutations | `cb3dc10` (V4, V2…V2y, V6) |
| 5 | **`ok: true`**, four minor issues (first look at `95234ae`) | 1409 | **none**; the four are open (above) |

**All five lanes verified `ok: true`.** Every verifier re-ran its problem
mutations through a full build and the full unfiltered suite, restored each file
from a copy and read `git status --short` empty. The pixel comparison each
verifier relied on is the one taken on the lane's last `Sources/` change (lanes
1–4: `git diff --stat` over `Sources/` empty since); lane 5's verifier re-took it
from archives.

## Mutations that stayed green, and what has no mutation

- **Lane 1 M1n** (`Frame.requestNode`'s backstop removed): green at `68200dc`;
  red after 1.5b (`a155251`), as is M1n′.
- **Lane 1, `scenesEqual`'s `drawList` clause alone**: green, and the verifier
  marks it expected. No harness arm emits glyphs, so no arm differs in the
  rect/glyph interleave alone. Unpinned.
- **Lane 1 M1d′ and "records but still calls `setStyle`"** at `68200dc`:
  **truncated** the suite (not green, not red); red by name after 1.5's amend arm
  moved into a child.
- **1.1's defaults**: no mutation claimed; flipping either default truncates the
  suite at the first legacy frame. Pinned by the printed count only.
- **Lane 2 M2i** (paint wraps at the leaf's answer): green at `57c6250` —
  **because the mutant was the correct spelling**; proven different, the design
  corrected (`LR-X`), red after `8a28c4d` in the re-spelled form.
- **Lane 2 M2k** (a leaf's size frame aligned `.center`): **green, equivalent by
  reading, not demonstrated** — nothing in stage 1 reads the rect of a node
  inside a leaf's frame. Observable once a `Text` gains lowered padding (stage 2).
- **Lane 2 M2h**: truncated in-process at `57c6250`; red by name after 2.8 moved
  into a child.
- **Lane 2 verifier V3, V4, V5, V7**: green at `73ce03f`, red after `a9fceb5`.
- **Lane 3 M3l** (`display: .stack` → `noLowering` deleted): green at `35c588e`,
  red after `24fa898`.
- **Lane 3 M3h** reddens every lane-3 test: it cannot single out 3.7.
- **Lane 3 verifier V1, V2**: green at `3489561`, red after `6b8fda1`.
- **Lane 4 M4e** reddens only 4.5's first `try #require`, which then stops the
  test: the second arm's own sensitivity is unmeasured.
- **Lane 4 verifier V4, V2, V6**: green at `1b89197`, red after `cb3dc10`.
- **Lane 5 M4h re-run**: truncated at `d863ede` (5.6's window trapped); red by
  name after `44f6e21`'s pre-flight.
- **Lane 5 V5-3** (`maxDepth` 89): reddens only 5.9's stderr check; **the exact
  depth boundary is bracketed (87 lays out, 90 traps), not pinned** (minor 1).
- **Lane 5 V5-2 vs 5.5**: 5.5 stays green with an empty bounds log (minor 4).

**Across four lanes the same class stayed green first**: a lowering branch that
reads the **declared** style where it must read the **animated** one (V7 lane 2,
V1 lane 3, V4 and V2 lane 4). Each lane's own tests used static values; each
verifier found the mutant green and a pin was added. Lane 5's V5-6 then reddened
three tests on first try.

**Unpinned or unprobed, by reading:**

- `AnyElement`'s group entry never calls `suppressingAccessibilityIfHidden`
  (`AB-O`): the bounds record was missed there (MA) and, by reading, so is the
  hidden suppression. Unmeasured.
- A tree that becomes unlowerable after input still traps inside its window:
  `WindowPair`'s pre-flight checks the first frame only.
- 5.6's first run found no `StateTable` id for a declared, read, never-written
  `@State` in `LowerableCounter`; CLAUDE.md's "seeding marks" sentence was not
  checked against it.
- W2 (a long text beside a short one in a narrow `HStack` with
  `layoutPriority`): the kernel overflows (−2, 76 + 8 at 80), SwiftUI answers
  59/18; no test pins it (`LR-F` withdrew the clamp that moved it).
- The below-word text answer is pinned wrong on purpose (2.7) on the proposal
  path, which the preview runs in production; it is not in the divergence table.

## Demo comparisons, in one place

Stand-in every lane: `CN-R`'s harness (twelve images through a real `Window` over
`FakePlatformWindow`, pixels and scene dumps, `DEMO_PIXELS_SMALL=1`) on `git
archive` trees, against lane 1's `c2290fc` images (`lr1-px-base`), except where
noted. From `f508003` on, the generator **imports** `MetalUIDemoContent`
(`gen-lib.py`) instead of copying `main.swift`.

Controls, identical at base and at every head: light vs dark f0 1 048 576;
default vs modal 1 030 498; default vs animation 210 027; f0 vs f3 0; preview
light vs dark 1 048 576.

| after | twelve images vs `c2290fc` | who took it |
|---|---|---|
| design, prototype P1 / P2 (not evidence for any lane, `LR-M`) | 0 in 12; P2 with scratch `SA-N` item 4 also 0 in 12 | design, critic round |
| lane 1 (`68200dc`) | 0 in 12, scenes identical | lane 1 verifier, from archives of both |
| lane 2 (`57c6250`, `8a28c4d`) | 0 in 12 at each | lane 2 |
| lane 3 (`35c588e`) | 0 in 12 | lane 3 |
| lane 4 (`4446336`) | 0 in 12 | lane 4 |
| lane 5 move (`f508003`) | 0 in 12 | lane 5 |
| lane 5 (`d863ede`; later `Sources/` changes are doc comments) | 0 in 12 | lane 5; re-taken by its verifier at `95234ae` with **both** sides rebuilt from archives: 0 in 12, default image 544 distinct values |
| **two-authority chrome pair** (`StageOneCorpus.counterChrome()` in a 560² `DifferentialRoot` through a 560² `Window` under each authority) | `chrome-legacy` vs `chrome-proposal` **0**, scene files byte-identical, 216 distinct values; **control M5d** (stack spacing + 50) **8 214** | lane 5; the 0 re-taken by its verifier |

**What the zeros prove:** the default (legacy) authority moved nothing, and the
library move moved nothing. No production root runs under the proposal
authority, so the twelve are not evidence for any lowering; the chrome pair is
the one pixel comparison of a lowered tree, and it is a test tree, not the demo's
own `CounterPanel` (which reports `box.alignSelf`).

**Real release-window captures: none.** `IOConsoleLocked` read `<true/>` at every
lane's end, at every verifier and at this record pass (02:20:36 PDT). At design
time it read `<false/>` while `CGSSessionScreenIsLocked = 1` and the display was
asleep; no capture was taken then either (`LR-M` records the override; the
ruling's "take one capture anyway" branch never came up).

## Goldens retired

**None.** 97 before and after; `git diff --name-only c2290fc 95234ae` lists no
`.json`. Retirement is stage 7a's, each golden by ruling with its replacement.

## Hazards this stage introduced or exposed

1. **Stored properties changed on public types** (`Frame`, `Window`,
   `ModifierLayer` including a stored → computed `isFrame`). **`swift package
   clean` after merging**; the computed-property change is the incremental-link
   hazard, not the SIGSEGV one.
2. **A new legacy registration site must check the authority itself.** Every
   site reports or traps by its own name; `Frame.requestNode`/`requestLeaf`'s
   backstop traps with `Frame.requestNode … reached under the proposal layout
   authority`, which names no site. A new site gains an arm in
   `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.
3. **A group entry that hands off to members must record bounds**, or the
   differential harness is blind to it (MA: `AnyElement` was). Four sites record
   today: `Frame.render`'s root, `Element.prepaintGroup`,
   `AnyElement.prepaintGroup`, each inner `ModifiedElement` layer.
4. **Under the proposal authority a window frame traps, it does not report.** A
   window test that renders an unlowerable tree ends the run with no summary line
   (lane 3's first red run, lane 5's M4h). Pre-flight under diagnostics
   (`WindowPair`) or use an exit test.
5. **`.frame(idealWidth:)` no longer traps at construction**; it traps when the
   legacy engine would register it (render). A test that only constructs one now
   passes silently (the amended pin's evidence).
6. **`EmptyGroup().frame(…)` is the proposal frame** (`EmptyGroup` is a
   `ProposalElementGroup`) and traps on zero nodes (`SA-R`).
7. **Lowered semantics are SwiftUI's where probes say, and they differ from the
   legacy answer** on the same tree: a text hugs its widest line (T2), a `Stack`
   offers its proposal (53), a flexible frame is greedy (35), a row overflows
   (55), an ideal is honoured (39). Proposal authority only; production gains them
   at 6b.
8. **The public `LayoutPass.requestNode`/`requestLeaf` now trap under the
   proposal authority** (`customElement`); in-module callers go through
   `Frame.requestNode`. Deprecation is stage 6a's.
9. **Depth.** A padded, sized legacy container lowers to 3 native levels; a chain
   of 29 as a root is 87 of `maxDepth` 88, and `DifferentialRoot` adds 2. The
   demo's lowered estimate is 22. The boundary is bracketed, not pinned (minor 1).
10. **The demo's globals initialize lazily** in the first frame (minor 3); the
    cold frame now includes 500 `DemoListRow`s' construction.
11. **The non-test targets are nine** (`MetalUIDemoContent`); CLAUDE.md and
    README say eight. Its `public` names are demo content, not framework API.
12. **`LowerableCounter` is a copy of `CounterPanel`'s wiring.** A change to the
    demo's counter does not reach 5.4–5.6; stage 2 replaces it with
    `CounterPanel()`.
13. **CLAUDE.md's "Two layout authorities, chosen by the window root alone"**
    now collides with `LayoutAuthority`, which names the per-frame choice that
    decides what the root is.

## Deferred, each with an owner

| deferral | why | owner |
|---|---|---|
| the stage-2 fields (5.3's census), `SA-N` item 4, text unification and the below-word answer, `Row`/`Column` spacing (52), compression (55) | stage 1's subset lowers only where CSS cannot show a difference (`LR-E`) | stage 2 |
| `ScrollView` lowering and the folded clamp/indicator (54); `Component` amend/wrap (48, 56) | site-level in stage 1 | stage 3 |
| windowed proposal `List` | site-level in stage 1 | stage 4 |
| `Deferred` presentation; absolute positioning (9–11) | site-level in stage 1 | stage 5 |
| grids | no legacy twin | stage G |
| deprecating the public legacy registrars; custom test elements | `FR-I`'s one move (`LR-R`) | stage 6a |
| the root switch, root placement (4), ideal/greedy maximum/single-axis maximum/`ZStack` offer in production (39, 35, `FR-O`, 53), release depth re-bisection, real-window captures, demo human look | no production root lowers in stage 1 | stage 6b |
| the 97 goldens; the non-golden CSS tests | `LR-U` | 7a, 7b |
| sizing vocabulary; `Text(…).width(w)` centring (T7) | `FR-F`/`FR-G` | stage 8 |
| engine, `Style` CSS fields, the mechanical check | — | 9, 10 |
| legacy `.overlay`, `.opacity` ordering (45) | `LR-V` | stage 11 |
| `Component` `background`/`onClick`/`focusable` | not layout | task 8 |
| lane 5 verifier minor 1: 5.8's doc comment and `LR-AA` item 7, or an 88/89 arm | found at `95234ae` | the next change to `LoweringPipelineParityTests`, or stage 6b's depth re-bisection |
| minor 2: `compareInWindows` used or deleted, `LR-AA`/spec §5.2 amended | found at `95234ae` | stage 2 (its window tests), or the integrator |
| minor 4: `try #require(pair.report().elements == 8)` in 5.5 | found at `95234ae` | the integrator (one line) or stage 2 |
| `AnyElement`'s missing `suppressingAccessibilityIfHidden` | by reading, unmeasured | stage 2 (`hidden()` moves off `display`) |
| checking CLAUDE.md's `@State` seeding sentence against 5.6's finding | not investigated | Docs phase |
| W2 unpinned | `LR-F` | stage 2 |

## For the integrator

**Verdict: all five lanes verified `ok: true`.** Lanes 1–4 each had a verifier
round that added pins and a second look with no issues. Lane 5's verifier
returned `ok: true` with **four minor issues and no fix round**; they are open
(lane 5's verifier round, above): 5.8's wrong doc comment and the bracketed depth
boundary, `compareInWindows` with no caller, the lazy demo globals (record-only),
and 5.5 passing on an empty bounds log. Minors 1, 2 and 4 are test or doc edits;
none blocks a merge, and none changes `Sources/`.

This branch's figures at `95234ae`: **1409 tests, 97 goldens, 71 guards, 0
`error:` / 0 `warning:`** (the lone `warning:` in a native log is SwiftPM's
deprecation notice); 34 `@available(*, deprecated` hits (unchanged). Re-take
every count after the merge, after `swift package clean` (hazard 1).

**`CLAUDE.md` (rules only; then `cp CLAUDE.md AGENTS.md` and `cmp`):**

1. **Ruling table.** Add `` | `LR-` | engine replacement, plan task 7 (`LR-A`…`LR-AA`, next is `LR-AB`) | lettered, two-letter tails deliberate | ``; add
   `LR-3` to the bare-typo sentence. Add to "Where things are": `` - engine
   replacement (task 7, `LR-`, stage 1 of thirteen):
   `specs/2026-09-17-engine-replacement-design.md` (the stage plan is its §4),
   `2026-09-17-engine-replacement-decisions.md`, record §18; probe
   `docs/probes/swiftui-engine-replacement-stage1.swift` (revision 2). ``
2. **Counts.** 1357 / 97 / 70 → **1409 / 97 / 71** on `feat/engine-replacement`
   at `95234ae` (+52 tests: lane 1 +12, lane 2 +10, lane 3 +9, lane 4 +12, lane 5
   +9; +1 guard, `LayoutAuthorityCompileGuards`), then re-take after the merge.
   Add `LayoutAuthorityCompileGuards` 1 to the per-file list and to the "count
   with per-file `grep -c canTypecheck` across …" sentence. "the other 30 — …" →
   "the other 31 — … `LayoutAuthorityCompileGuards`' one …". In "CI — what lapses
   silently", "all 70 guards skip" → 71.
3. **Targets.** "eight one-way-dependent non-test targets (… `MetalUIDemo`)" →
   nine, adding `MetalUIDemoContent`: "the demo's content (`demoContent()`,
   `CounterPanel`, `nativeLayoutPreviewContent()`), a library in no product so
   tests import the demo's own tree (`LR-S`); `MetalUIDemo` is `runDemo()`
   only". Change "`PreviewToggle` does, `main.swift:921`" → "`DemoContent.swift:932`".
4. **A new paragraph, after "Two layout authorities …"** (and rename that
   paragraph's lead to "**Two layout engines, chosen by the window root
   alone.**", since `LayoutAuthority` now names the per-frame choice):
   > "**The layout authority (task 7 stage 1, `LR-A`…`LR-AA`).** Every `Frame`
   > has an internal `layoutAuthority`, `.legacy` by default and in production;
   > `Window.layoutAuthority` sets it for every frame the window builds (a write
   > dirties) and is not public until stage 6b (guard G1). Under `.proposal`
   > **every legacy site checks the authority itself before registering**:
   > `Box`, `Stack`, `Text` and both `ModifiedElement` registrars lower onto
   > kernel nodes (stage 1's subset, spec §5.4); `ScrollView`, `List` (before it
   > builds its `Box`), `StyledComponent`'s amend and wrap, and the public
   > `LayoutPass.requestNode`/`requestLeaf` (`customElement`) do not lower.
   > Anything unlowerable **traps naming `<site>.<field>`**, or, with
   > `reportsUnlowerableFields`, is recorded and answered by a 0×0 native leaf.
   > `Frame.requestNode`/`requestLeaf` keep a backstop trap that names no site. A
   > report is `display.none` alone if hidden, else the container rows then the
   > every-node rows; production traps on the first. **A new legacy registration
   > site gains its own check and an arm in
   > `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` in the same change.**
   > Lowering is border-box as SwiftUI modifiers — content (leaf / linear stack /
   > overlay) → native padding → fixed `.topLeading` frame — **built from the
   > animated `Style`, checked against the declared one**; a frame layer lowers to
   > one kernel frame from its animated style plus `FrameSpec` (ideals, infinite
   > maxima, alignment), and anything written after `.frame` that changes its
   > style reports `modifierLayer.style`. Stretch and `space-*` lower only where
   > CSS cannot show them (one child and no declared cross size; no main size).
   > **A branch that lowers from a style needs an animated arm**: four lanes'
   > verifiers found a declared-style mutant green. Lowered answers are SwiftUI's
   > where probes say and differ from the legacy engine on the same tree (text
   > hugs its widest line, a `Stack` offers its proposal, a flexible frame is
   > greedy, a row overflows, an ideal is honoured) — proposal authority only.
   > A proposal element inside a lowered container is one authority and lays out;
   > under `.legacy` it still traps (`LR-T`). `.frame(idealWidth:)` traps at
   > **legacy registration**, not at construction (`LR-H`)."
5. **Differential harness (tests).** Add to the same paragraph or to Practices:
   "`LayoutDifferential.compare` renders a tree inside `DifferentialRoot` (a
   top-leading fixed-size root on both sides, `LR-D`) under each authority and
   compares rects per element, the finalized scene and draw list, hitboxes,
   accessibility emissions with geometry, and `StateTable.ids`. Never put a
   wrapping `Text` or a greedy child directly under the root: the root's own
   legacy `Stack` offers fit-content (divergence 53). **Under `.proposal` a
   window frame traps rather than reports**, so a window test pre-flights its
   tree under diagnostics (`WindowPair`) with a `try #require` on an empty report,
   or the run truncates (shape 13). **The bounds log is recorded at four sites** —
   the root in `Frame.render`, `Element.prepaintGroup`, `AnyElement.prepaintGroup`,
   each inner `ModifiedElement` layer; a new group entry that hands off to
   members records too (`LR-AA`, mutation MA)."
6. **The group-default hook rule.** "Any hook added to `Element`'s group defaults
   … must be mirrored per layer in `ModifiedElement`" → add "**and in
   `AnyElement.prepaintGroup`, a hand copy** (`LR-AA`: the bounds record was
   missed there; by reading, `AB-O`'s `suppressingAccessibilityIfHidden` is
   still missing there, unmeasured)".
7. **Frame sizing paragraph.** "`idealWidth`/`idealHeight` **trap** on the legacy
   path (`FR-D`, exit test)" → "… trap when the legacy engine registers the frame
   (at render, not construction, `LR-H`); under the proposal authority a legacy
   frame lowers them onto the kernel frame (4.6)". After "Two legacy divergences
   stay pinned wrong on purpose …" add "; both are SwiftUI's answer under the
   proposal authority already (4.5), and production gains them at the root switch
   (stage 6b)".
8. **Depth guard** (`SA-L`). Add: "A padded, sized legacy container lowers to 3
   native levels; the default demo's deepest lowered path is estimated at 22
   (`LR-Q`); 29 lowered `Box`es as a root (87) lay out and 30 (90) trap
   (5.8/5.9) — the exact 88/89 boundary rests on `SA-L`'s pins and 5.9's
   message."
9. **Practices.** Add: "**A mutant that stays green may be the correct
   spelling.** Prove it different; if it is the better answer, correct the
   design (`LR-X`: lane 2's paint-wrap mutant was right)." And: "**A window test
   in a mode that traps pre-flights in a mode that reports**" (hazard 4).
10. **Performance.** Add after the demo's frame figures: "Since `LR-S` the demo's
    `demoRows` and `demoModel` are lazy library globals initialized inside the
    first frame, so the cold frame includes 500 `DemoListRow`s' construction
    (unmeasured)."
11. **Human verification.** Add a row: "engine replacement stage 1 (task 7):
    release-window capture of the default demo and the preview against
    `c2290fc` | **open**: `IOConsoleLocked` `true` at every lane and at the record
    pass; stand-in offscreen 0 differing pixels in all twelve at every lane and
    from archives by lane 5's verifier; the two-authority chrome pair 0 (control
    8 214). Nothing in production runs under the proposal authority, so no demo
    look is owed until stage 6b (record §18)".
12. **Do not edit**: the "stack children get a nil main offer" sentence lane 4's
    finding names is already absent (`grep -n "nil main" CLAUDE.md` is empty at
    `c2290fc`). Before editing the `@State` "seeding marks" sentence, check it
    against 5.6's finding (an unwritten `@State` in `LowerableCounter` minted no
    `StateTable` id); not investigated.

**Divergence table** (`CLAUDE.md`; record §04 gains the index row):

- **No divergence is retired**: production is unchanged.
- **Edit 39**: "`idealWidth`/`idealHeight` on a legacy frame trap" → "… trap when
  the legacy engine registers the frame (at render; since `LR-H` not at
  construction); under the proposal authority they lower (4.6). Pinned by the
  amended `anIdealDimensionOnTheLegacyFrameTraps`; stage 6b."
- **Edit 35, 53, 55**: append "lowered to SwiftUI's answer under the proposal
  authority (`aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`
  / `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` /
  `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren`); production at
  stage 6b". 52, 54, 56: owner "task 7" → "task 7 stage 2" / "stage 3" / "stage 3".
- **Add 59**: "| 59 | vs SwiftUI | `ProposalText` (and a lowered `Text`) proposed
  a width below its narrowest word answers its widest character with the hung
  space (11.18 at 13pt for probe T's string, 592 tall) where SwiftUI answers the
  proposal (stage-1 probe T3/T4, `LR-X`). Pinned wrong on purpose by
  `aProposalTextBelowItsNarrowestWordAnswersItsWidestCharacterWhereSwiftUIAnswersTheProposal`;
  task 7 stage 2. |" README's "Forty-seven" → forty-eight.

**Declared-but-inert table:**

- **Add** to the test-observables row: "`Frame.elementBounds`,
  `Frame.unlowerableFields`, `Window.recordsElementBounds`/`lastElementBounds`,
  `StateTable.ids`".
- **Add** "`LayoutAuthority.proposal` / `Window.layoutAuthority` | internal;
  works, pinned, and set by no production code until stage 6b — every production
  frame is `.legacy`".
- **Edit** the single-axis `.frame(maxWidth: .infinity)` row: append "under the
  proposal authority the layer lowers to a greedy kernel frame and fills (4.5);
  production unchanged until stage 6b".

**The plan's task 7 entry: do NOT tick it.** Append under the existing notes:

> *Progress 2026-09-17 on `feat/engine-replacement` (`59fd180..`record commit),
> stage 1 of 13, still open.* Spec `specs/2026-09-17-engine-replacement-design.md`
> (stage plan §4); rulings `LR-A`…`LR-AA` in
> `../2026-09-17-engine-replacement-decisions.md`; probe
> `docs/probes/swiftui-engine-replacement-stage1.swift`; record §18. **Stages:**
> 1 lowering foundation; 2 flex-item semantics onto SwiftUI's; 3 `ScrollView` and
> `Component` distribution; 4 windowed proposal `List`; 5 `Deferred`
> presentation and absolute positioning; G grids; 6a custom elements and the
> public legacy registrars deprecated; 6b the root switch
> (`noProductionFrameReachesTheLegacyEngine`); 7a goldens replaced; 7b non-golden
> CSS tests retired; 8 sizing vocabulary onto `.frame`; 9 engine deleted; 10
> `Style`'s CSS fields and the `dlsym` closing check; 11 modifier unification.
> **Stage 1 delivered** (five lanes, each red first, all verified `ok`; lane 5
> with four open minors): a per-frame layout authority (internal, legacy by
> default); every legacy site reporting or trapping by name; an element-bounds
> log and a differential harness comparing rects, scene, hitboxes, accessibility
> and state slots; `Text`, childless and container `Box`, `Row`, `Column`,
> `Stack`, `.padding` and `.frame` layers lowered onto the kernel on the stage-1
> subset, animated; legacy ideal under the proposal authority; mixed trees ruled;
> the demo's content in a `MetalUIDemoContent` library; pipeline parity (clicks,
> focus, keys, accessibility, state slots, animation), work and depth pins.
> Suite 1409 (1357 + 52), 97 goldens unmoved, 71 guards; twelve demo images 0
> differing pixels at every lane. **Not done:** no production frame runs under the
> proposal authority; nothing deleted; no golden retired. Unspecified, ideal,
> min/max, fixed-size, priority, compression, expansion and custom layouts exist
> on the proposal path; grids are still absent (stage G).

**README:**

- The count sentence ("On `feat/containers` … **1357 tests** … **70** guards") →
  "On `feat/engine-replacement` (2026-09-17, plan task 7 stage 1) … **1409** …
  **97** … **71**"; re-take after the merge.
- "Eight one-way-dependent targets" → nine; add a row `` | `MetalUIDemoContent`
  | the demo's content (`demoContent()`, the counter, the proposal preview), a
  library the tests import | ``, and `MetalUIDemo`'s row → "the executable above
  (`runDemo()`)".
- "Forty-seven measured divergences" → forty-eight if 59 is added.
- In the record list, after `17-containers.md`: "and
  [`18-engine-replacement-stage-1.md`](docs/record/18-engine-replacement-stage-1.md)
  for task 7's first stage". In the specs list: "[engine replacement
  spec](docs/superpowers/specs/2026-09-17-engine-replacement-design.md) (plan task
  7, stage 1 of 13 landed: legacy elements lower onto the kernel under an
  internal proposal authority; production still uses the CSS engine)".

**Other owned documents:**

- `docs/record/README.md`: add `` | `18-engine-replacement-stage-1.md` | plan
  task 7 stage 1 on `feat/engine-replacement`: the inventory of `FlexEngine`
  consumers, the thirteen-stage plan, the layout authority and per-site checks,
  the bounds log and differential harness, leaf/container/`Stack`/layer lowering,
  the demo content library, pipeline parity, depth and work pins; five lanes,
  red runs, verifier verdicts (all `ok`, lane 5 four minors) and mutation tables;
  the offscreen pixel stand-in and the chrome pair; counts 1409 / 97 / 71 | ``.
- `docs/record/04-divergences.md`: index 59; edit 39's pin note.
- FR decisions doc: `FR-D` "**Trap moved to legacy registration by `LR-H`**;
  lowered under the proposal authority"; `FR-E`, `FR-O`: "lowered under the
  proposal authority by `LR-H` (stage 1); production at stage 6b".
- CN decisions doc, `CN-Q`: the handed items now have stages (`LR-L`): `List` 4,
  `Deferred` 5, legacy `.overlay` 11, greedy/single-axis maxima 6b, multi-member
  frame 3.
- Decisions doc `LR-AA` items 4 and 7 and spec §5.2 / 5.8's row: amend for minors
  1 and 2 when they are fixed.

## Docs phase (2026-09-17)

- **Re-take.** `swift package clean`, `swift build --build-system native
  --build-tests` → exit 0, 0 `error:`, one `warning:` (SwiftPM's
  `--build-system native` deprecation notice); `swift test --build-system native
  --no-parallel`, unfiltered → `Test run with 1409 tests in 1 suite passed after
  42.786 seconds.`, 0 `error:`, the same lone deprecation `warning:`; skipped:
  `regenerateAllGoldens`, `aListsWorkIsTheSameFor100kRowsAsFor500`; guard output
  lines printed, so the typecheck guards ran. Goldens `find Tests -name "*.json"
  | wc -l` → 97. Guards per file (`grep -c canTypecheck`): `PhaseSeparationTests`
  19, `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
  `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `ContainerCompileGuards` 4, `AXNodeTests` 3,
  `DecorationCompileGuards` 3, `UnitSafetyTests` 3 (one a comment),
  `ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2,
  `LayoutAuthorityCompileGuards` 1 → **71**. `@available(*, deprecated` hits: 34.
- **`IOConsoleLocked`** read `<true/>` again; no real-window capture.
- **Checked against source before writing the rules:** `Window.layoutAuthority`
  (internal, `didSet` dirties), `Frame.unguardedLegacyRegistration` (traps unless
  `reportsUnlowerableFields`, then a 0×0 native leaf), the four
  `recordElementBounds` call sites (`Frame.render`, `Element.prepaintGroup`,
  `AnyElement`'s `prepaintGroup`, the inner `ModifiedElement` layer), the absence
  of `suppressingAccessibilityIfHidden` in `AnyElement`'s entry, every test name
  cited in `CLAUDE.md`'s new text, and `Package.swift`'s nine non-test targets.
  One correction to the integrator notes: `PreviewToggle` is at
  `DemoContent.swift:929`, not 932.
- **Documents changed:** `CLAUDE.md`/`AGENTS.md` (ruling table, Where things are,
  counts, guards, targets, the layout-authority paragraph, the group-default
  hook rule, frame sizing, depth guard, practices, performance, human
  verification, divergences 35/39/52–56 and new 59, inert table), `README.md`,
  `docs/record/README.md`, `docs/record/04-divergences.md`, the frame-sizing
  decisions doc (`FR-D`, `FR-E`, `FR-O` amendment notes), the containers
  decisions doc (`CN-Q` stages), the plan's task 7 progress note (not ticked).
  Lane 5's four minors remain open; `LR-AA` items 4 and 7 and spec §5.2/5.8 are
  unamended because the minors are unfixed.
