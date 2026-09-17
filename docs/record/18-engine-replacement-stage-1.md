# 18 — Engine replacement, stage 1 (plan task 7)

`feat/engine-replacement`, from `c2290fc`. Design:
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`; rulings `LR-A`…
in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`; probe
`docs/probes/swiftui-engine-replacement-stage1.swift`.

This section holds the **design round's** measurements. Lanes append below it.
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
