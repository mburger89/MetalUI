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
