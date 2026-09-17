# 19 — Engine replacement, stage 2 (plan task 7): design

Spec: `docs/superpowers/specs/2026-09-17-engine-stage-2-design.md`. Rulings
`LR-AB`…`LR-AO` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Probe: `docs/probes/swiftui-engine-replacement-stage2.swift`. Branch
`feat/engine-stage-2` from `cb2e708`, worktree
`/Users/maxburger/Developer/MetalUI-engine-stage-2`. **Design only**: nothing
under `Sources/` or `Tests/` is committed by this record's commit.

## Baseline (2026-09-17, PDT)

- `swift build --build-system native --build-tests`: `Build complete!`, 0
  `error:`, the one `warning:` SwiftPM's `--build-system native` deprecation.
- `swift test --build-system native --no-parallel --skip-build`: `Test run with
  1409 tests in 1 suite passed after 42.660 seconds.` 0 `error:`, no other
  `warning:`.
- `find Tests -name "*.json" | wc -l`: 97.
- Guards: not re-taken (71 at stage 1's end, record §18); this design adds none.

## Screen lock

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate`, ~07:15 PDT: `session CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1`, `displayActive main: 0`,
`preflightScreenCaptureAccess: true`. No real-window capture was taken.
`IOConsoleLocked` was not read (`FR-V`).

## Probe

`/usr/bin/swift docs/probes/swiftui-engine-replacement-stage2.swift`, macOS 27.0
(26A428), Apple Swift 6.4 (swiftlang-6.4.0.33.1): exit 0 both runs; stdout 157
lines, `diff` of the two runs empty. The first run (before arms J7–J9 were added
and V's pixel classifier printed RGB) was exit 0 with the same readings for every
arm it had; V0 then classified the centre pixel as "other" (not white), which the
revision prints as `not white [255, 66, 69]` (Display P3 red read back through
sRGB). The whole output and its reading are in the probe's header. Summary by
group:

| group | control | arms | reading |
|---|---|---|---|
| F | F0: pair centred, b 0 wide | F1–F8 | greedy takes leftover (260); equal share (150/150 over 100/20); never below child without a minimum (200/100); a minimum's presence allows it (150 over 200); rigid 196 served first; `.fixedSize()` overflows (302) |
| X | X0: b centred 10 tall; X3: VStack 30; X6: VStack 100 | X1, X2, X4, X5, X7–X10 | cross fill 40 / 100; hugging container fills (200); leading alignment frame exact when definite, fills when not (300); nil-axis frame not stretched (30×10), outer greedy frame is (30×40); `maxHeight: 25` → 25 centred |
| P | P0: child at 0; P2: b at 20; P5: 33×16 | P1, P3, P4, P6 | frame 10×10 keeps its size, padding 34×34 overflows; margin spelling (bg (8, 8), b 36); negative overlaps (a −8, b 4, 24×20); text padding 53×36 |
| J | J0: centred at 70 | J1–J9 | between (0, 90, 180); between at gap 10 (same) and overflow (0, 30, 60); evenly at gap 0 (35, 90, 145); `Spacer(minLength: 10)` not evenly (53.33, 126.67); around (23.33, 90, 156.67); rigid gap leaf is evenly (50, 130); overflow packs from 0; greedy beside spacer 180 |
| R | R0: a 0, b 20 | R1, R2 | reverse (b 150, a 180); overflow (b −60, a 20) |
| C | C0: 100 at 50 | C1 | 500 at −150 (window-relative) |
| V | V0: not white; V2: top 1 under 0 | V1, V3 | white; top 0 under 1 |

## Prototype P3 — lanes 1–2's mechanism, scratch

**What it was.** Applied to this worktree's `Sources/` (185-line patch, kept as
`p3.patch` in the session scratchpad): `Frame.loweredItems` and
`Frame.boundsAliases`, `Frame.bounds(of:)` and `PaintPass.measuredWidth(of:)`
resolving the alias, a `LoweredItem` type; `lowerLegacyLeaf`, both
`lowerLegacyNode` branches and the frame-layer branch of `lowerLegacyLayer`
recording items; the flex container branch wrapping each child
(`itemNode`); the stretch row removed from `legacyContainerDiagnostics` and
`minSize`, `maxSize`, `flexGrow`, `flexShrink`, `flexBasis` and `alignSelf` (but
`.baseline`) removed from `legacyLeafDiagnostics`. A scratch test file
(`ScratchP3Tests.swift`) ran the demo census. Restored with `git checkout
Sources` and the file deleted; `git status --short` afterwards showed only the
probe.

**Where P3 differs from the spec** (so its figures are a prediction, not
evidence for the rows it did not implement): the stack (overlay) branch did not
consume items; a non-greedy `maxSize` went onto W instead of reporting; `flexBasis`
was neither reported nor given W's zero minimum; no weights check; the alignment
frame was registered whenever `alignSelf` was declared, not only when it differed
from the parent's `alignItems`; no margin, border, text padding, justify, reverse
or hidden change.

### Runs

1. **Without the single-child elision** — full suite `swift test --build-system
   native --no-parallel --skip-build`: `Test run with 1410 tests in 1 suite`
   (1409 + the scratch test), 8 failing:
   `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`
   (1 issue), `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork`
   (5), `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (9),
   `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (6),
   `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (14),
   `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (5),
   `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (4),
   `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (1).
2. **With the elision** (`children.count == 1 && parent cross size auto` → no
   stretch) — the three non-diagnostic tests, filtered: all passed. Full suite:
   `Test run with 1410 tests in 1 suite failed after 43.172 seconds with 25
   issues`, 5 failing, all diagnostics pins:
   `aContainersReportLists…` (1), `everyLegacySiteIsReported…` (6),
   `everyStageOneUnlowerableNodeFieldIsReported…` (14),
   `stretchAndSpaceDistribution…` (3), `theWholeDemoReports…` (1).

### Whole-demo census (run 2)

`LayoutDifferential.compare(width: 920, height: 560) { demoContent() }`,
animation off.

- Modal off: `unlowerable = [list.noLowering, scrollView.noLowering]`; elements
  2036, agreeing 6, disagreeing 30, legacy-only 2000, lowered-only 0.
- Modal on: `[stack.position, stack.inset, list.noLowering,
  scrollView.noLowering]`; elements 2042, agreeing 6, disagreeing 36.

Disagreements, modal off (legacy → lowered; `x,y w×h`), attributed by reading the
demo tree (spec §7's causes):

| legacy | lowered | element (by reading) | cause |
|---|---|---|---|
| 0,0 920×439 | 0,0 920×560 | outer `.padding(16)` layer | R |
| 16,16 888×407 | 16,16 888×528 | outer `Column` | R |
| 16,113 888×310 | 16,113 888×431 | body `Row` | R |
| 16,113 88×310 | 16,113 196×431 | sidebar padding layer | 55 (width), R (height) |
| 30,127 60×282 | 30,127 168×160 | sidebar `Column` | 55 (width), X9 (height) |
| 30,127 60×16 | 30,127 168×16 | "Library" | 55 |
| 30,153 / 189 / 225 / 261 60×26 | same y, 168×26 | the four sidebar bars | 55 |
| 116,113 788×310 | 224,113 680×431 | main-pane padding layer | 55, R |
| 132,129 756×278 | 240,129 648×399 | main-pane `Column` | 55, R |
| 132,129 360×128 (×2) | 240,129 360×128 | stack cluster `Stack` and its backdrop | 55 |
| 232,157 160×72 | 340,157 160×72 | panel | 55 |
| 298,179 28×28 | 406,179 28×28 | badge | 55 |
| 308,185 8×16 | 416,185 8×16 | "3" | 55 |
| 132,269 260×60 | 240,269 260×60 | counter chrome | 55 |
| 144,281 36×36; 344,281 36×36 | 252,281; 452,281 | "−" and "+" buttons | 55 |
| 192,281 140×36 | 300,281 140×36 | readout | 55 |
| 157,286 10×26; 224,286 76×26; 355,286 14×26 | +108 x | the three button/readout texts | 55 |
| 132,341 756×26 | 240,341 648×26 | "Text renders" | 55 |
| 132,379 756×48 | 240,379 648×64 | the paragraph | 55 (one more line at 648) |
| 132,439 420×0 | 240,455 420×73 | the `Box` around the scroller | 55 (y), R (height) |
| 132,439 420×0 | 240,455 0×0 | `ScrollView` id | stage 3 |
| 132,439 420×0 | 0,0 0×0 | `ScrollView`'s second id | stage 3 |
| 132,439 420×14000 | 0,0 0×0 | `List` | stage 4 |

Agreeing (6): the harness root, the header padding layer, header `Row`, avatar,
bar, hairline — by elimination from the rects above, not printed per id.

## Decisions taken at design time, with what they rest on

| ruling | rests on |
|---|---|
| `LR-AB` parent-side item records + bounds alias | P3 runs 1–2; the grep of rect readers (`Frame.bounds(of:)`, `measuredWidth(of:)`) |
| `LR-AC` stretch + elision; X4 and X9 divergences | X1, X2, X4, X9; P3 run 1 vs run 2 |
| `LR-AD` `alignSelf` alignment frame | X5, X6, X7 |
| `LR-AE` grow equal share; weights; zero basis | F1–F4, F8 |
| `LR-AF` shrink 0 → `fixedSize`; 55 kept | F5, F6, F7; stack-algorithms G1, G9 |
| `LR-AG` min/max | F4, F8, X10; frame probe D4 |
| `LR-AH` border, text padding, BM-4, margin, `SA-N` item 4 | P1, P3, P4, P6; record §18's scratch `SA-N` pixels |
| `LR-AI` percentages report | C0, C1 |
| `LR-AJ` justify, reverse | J1–J9, R0–R2 |
| `LR-AK` `hidden()` | stage-1 H1/H2; V0–V3; accessibility-bridge-rules R9 |
| `LR-AL` spacing 52 | stack-algorithms S |
| `LR-AM` text | stage-1 T3/T4, W2; `LR-F`, `LR-X` |
| `LR-AN` exit test | P3's census |
| `LR-AO` scope | the brief's five-lane cap |

## For the integrator

- **New divergences the lanes pin** (numbers are the integrator's): a stretched
  one-child container does not stretch its child (X9, 1.3); a greedy item inside
  a hugging item fills its proposal (X4, 1.7); an `alignSelf` makes an indefinite
  container fill (X7, 1.6); growing siblings share equally (F2, 2.2); a sized
  container with a zero basis lays out at its declared size (F4, 2.4); padding on
  a lowered `Text` pads it (P6, 3.2); a declared size below the padding keeps the
  frame (P1, 3.3); a negative margin past SwiftUI's clamp (P4, 3.5);
  `space-around`/`space-evenly` overflow from the start (J9, 4.3); `hidden()` keeps
  its space (H1, 5.1). All under the proposal authority only; production at 6b.
- **Owners that change**: divergence 59 → task 11 (`LR-AM`); divergence 52 →
  stage 8 (`LR-AL`); divergence 55's lowered answer confirmed, production at 6b
  (`LR-AF`); `SA-N` item 4 closed by lane 3 (the plan's "probed, and the kernel
  disagrees" list and `negativePaddingIsAcceptedAndItsResponseClampsPerAxis`'s doc).
- **Hazards**: `Frame` gains stored properties in lanes 1, 3 and 5 (`swift package
  clean` after merging); any new reader of an element's rect must go through
  `Frame.bounds(of:)` or it misses the alias (`LR-AB`); `hiddenNodes` is a hook in
  `Element`'s group defaults and must be mirrored per `ModifiedElement` layer
  (`MC-B`).
- The other track's shared-file edits meet this stage's in `Frame.swift`,
  `Passes.swift`, `LegacyLowering.swift`, `LayoutTree.swift` (lane 3's padding
  case only), `ElementGroup.swift` and `ModifiedElement.swift` (lane 5).

## Critic round 1 (2026-09-17, 07:40–08:10 PDT)

Sixteen findings against `5b67545`; dispositions in `LR-AP` (none rejected), new
rulings `LR-AQ`…`LR-AV`, amendments to `LR-AB`, `LR-AC`, `LR-AE`, `LR-AG`–`LR-AO`.
The spec was rewritten in place. Every scratch below was applied in this
worktree and restored (`git checkout Sources`, scratch tests deleted, `git status
--short` showing only the staged probe), and `swift package clean` was run after
the scratches that added `Frame` stored properties. Nothing under `Sources/` or
`Tests/` is committed.

### Probes re-run and extended

- **Stage-2 probe revision 2** (`/usr/bin/swift`, macOS 27.0 (26A428), Apple Swift
  6.4): exit 0, run twice, byte-identical, **235 lines**; the 157 revision-1 lines
  unchanged and in order. New arms: C2 (a `GeometryReader` fraction: 100 of a
  200 parent), X11–X18 (padding, `ZStack` and main-axis fills: 46 → 160, 100 →
  300, 30 → 200, 30 → 200 tall), F9 (a greedy frame over "alphabravocharlie" at
  a 50 share: 50, the text 48×48), F10 (over a rigid 200 stack: 200, row 220), P7
  (child (12, 0)), P8 ((0, 12)), P9 ((0, 0)), Y0–Y9 (word breaking). The group was
  first named B and renamed Y (the stage-1 probe has a B group); the reported
  235-line run is after the rename, and the header's OUTPUT matched it line for
  line (0 mismatches by script).
- **Group Y, SwiftUI against CoreText** (13pt system font, `ct` = the
  `CTTypesetterSuggestLineBreak` loop): lines equal in Y1–Y9 (1, 2, 2, 4, 5, 2, 2,
  12, 7); SwiftUI width = min(proposal, ceil(widest line with trailing space)) in
  all nine: 33 (32.84), 19 (18.17) ×2, 11 (10.31), **5** (7.86), 18 (17.25) ×2,
  **30** (33.31), 45 (44.02; 40.44 without the space).
- **stack-algorithms**: exit 0, 787 lines, identical to its OUTPUT block after
  stripping leading spaces (A5, G1, G9, G4r, S included).
- **accessibility-bridge-rules** (its HOW TO RUN filter): exit 0, 62 lines,
  identical to its recorded block (R9: only `Text(Shown)` published).
- **frame-semantics** (script form): exit 0, 291 lines against a 295-line record.
  The first 275 lines are identical, D4 included (`frame(maxWidth: 80)` at 100:
  80×20). The last group differs: G1's `child proposed` lines no longer include
  the leading `0.0xnil` / `infxnil` probe pairs (four fewer lines) and order the
  remaining ones differently; every `size` and `child at` line is identical. The
  record was taken on macOS 26.6.2; nothing in stage 2 cites G1's proposal
  sequence.

### Scratch `SIGTRAP` (finding 11)

`placeNative`'s `.padding` case changed to place the child at its measured size;
native build (0 errors); `swift test --build-system native --skip-build --filter
negativePaddingIsAcceptedAndItsResponseClampsPerAxis`: `expected exit status
".success", but ".signal(SIGTRAP)"`, 1 issue. Then that test's precondition
`clampedRect.width == 30 && clampedRect.height == 30` set to 20 and 20, rebuilt,
same filter: `Test run with 1 test in 0 suites passed`. The trap is the pin's own
"reddens deliberately" precondition. Both files restored from copies.

### Scratch R2 — P3 plus `SA-N` item 4 (findings 2, 9, 11)

`p3.patch` applied, the item-4 change on top, `ScratchR2Tests.swift`; native
build 0 errors (no `swift package clean` before the run: a stored property on
`Frame`; the run completed with its summary line; cleaned afterwards).

- **Demo census**: modal off 2036 / 6 agreeing / 30 disagreeing / 2000 legacy-only /
  0 lowered-only, report `[list.noLowering, scrollView.noLowering]`; modal on 2042
  / 6 / 36, `[stack.position, stack.inset, list.noLowering, scrollView.noLowering]`.
  All 66 disagreeing rect pairs compared by script against P3's run 2
  (`p3b-suite.log`): identical.
- **S1** `Row { Row { a20; b20 }.justifyContent(.spaceBetween).flexGrow(1); c40 }.width(300)`,
  root 300×100: 6 ids, 5 agree, 1 differs (b: legacy (240, 0) → lowered (20, 0)),
  report `[]`.
- **S2** `Row { a40; x30.flexGrow(1).padding(8) }.width(200)`: padding layer
  (40, 0) 46×26 → 160×26; x (48, 8) 30×10 → 144×10; report `[]`.
- **S3** `Column { a100; x20.alignSelf(.flexEnd).padding(8) }`, root 300×100:
  column 100×36 → 100×100; padding layer (32, 10) 36×26 → 36×90; x (40, 18) →
  (40, 82); report `[]`.
- **S4** `Row { Box().width(20).maxHeight(25); Box().width(20).minHeight(60) }.height(100)`
  (centring default): a (0, 50) 20×0 → (0, 38) 20×25 (P3 put every maximum on W,
  which `LR-AG` does not); b agrees; report `[]`.

### Scratch text (finding 14)

`proposalTextMeasurement` with `ShapingCache().resolveFont(family: nil, size: 13)`
at probe Y's strings and widths (filtered scratch test, restored):

| arm | width | kernel answer | lines | SwiftUI |
|---|---|---|---|---|
| Y0 | nil | 32.84×16 | 1 | 33×16 |
| Y1 | 33 | 32.84×16 | 1 | 33×16 |
| Y2 / Y3 | 25 / 20 | 18.17×32 | 2 | 19×32 |
| Y4 | 12 | 10.31×64 | 4 | 11×64 |
| Y5 | 5 | **7.86**×80 | 5 | **5**×80 |
| Y6 / Y7 | 21 / 18 | 17.25×32 | 2 | 18×32 |
| Y8 | 30 | **33.31**×192 | 12 | **30**×192 |
| Y9 | 45 | 44.02×112 | 7 | 45×112 |
| T3 (stage 1) | 0 | **11.18**×592 | 37 | **0**×592 |
| T2 (stage 1) | 60 | 44.02×112 | 7 | 45×112 |

Line counts agree everywhere; the kernel lacks only `min(proposal, …)` (bold);
the remaining sub-point differences are SwiftUI's ceiling (`LR-AU`).

### Screen lock

07:49 PDT: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`,
`displayActive main: 0`. No capture taken.

### Lane list after the round (`LR-AO` as amended)

1. Item records (`LoweringState`), the bounds alias, the cross axis (stretch,
   `alignSelf`, `MC-Q` finding 7), unconsumed-record reports (`LR-AQ`), the
   stretch half of the free-space re-check (`LR-AR`) — 1.1–1.15.
2. The main axis (grow, basis, shrink, min/max, weights), animated fields
   (`LR-AS`), the grow half of the re-check, depth with three wrappers, the exit
   test — 2.1–2.15.
3. `SA-N` item 4 (commit 1) and the below-word text clamp (commit 2) — 3.1–3.4.
4. The box model (border, `Text` padding with leaf-width wrapping, `BM-4` under
   three alignments, margin, depth with four wrappers) — 4.1–4.8.
5. Justify distribution and reverse — 5.1–5.9.

Deferred by name: `hidden()` (`LR-AV`), W2 (task 11), the others in spec §9.

### For the integrator (additions)

- **Divergences added by the round** (under the proposal authority): a grow
  inside a one-child padding fills it (X12, 2.11); an `alignSelf` inside one fills
  it (X14, 1.15); a greedy child fills a hugging `Stack` (X16, 1.9); a grower on a
  hugging container's main axis fills its proposal (X18, 2.10); a zero-basis `Text`
  grower breaks inside its word (F9, 2.4); a declared size below the padding
  overflows by the container's alignment (P7/P8, 4.3); an animated `flexGrow`
  snaps its structure (2.13 — also a CLAUDE.md snap-list entry).
- **Closed by lane 3**: `SA-N` item 4 (the plan's "probed, and the kernel
  disagrees" list; `negativePaddingIsAcceptedAndItsResponseClampsPerAxis`'s doc);
  divergence 59 (the below-word answer). **Commit 1 of lane 3 changes where every
  proposal padding stores its child**: the other track's padding tests must be
  re-checked against it after the merge.
- **Owners that change**: W2 → task 11 as a stack-allocation question, with
  divergence 51; `hidden()` under the proposal authority → task 7 before stage 9
  (proposed as stage 5's companion), focus and keys task 12; `AnyElement`'s
  missing `hidden()` accessibility suppression → a legacy production change with
  its own pins (`LR-AV`); the inert-table `hidden()` row stays until then.
- **Merge shape** (`LR-AT`): `Frame` gains one stored line (`lowering`);
  `Frame.bounds(of:)` and `PaintPass.measuredWidth(of:)` change by one expression
  each; lane 5 no longer touches `ElementGroup.swift` or `ModifiedElement.swift`.
- `LR-AK`'s paragraph in the "Decisions taken at design time" table above is
  superseded by `LR-AV`; `LR-AM`'s by `LR-AU` for the below-word answer.
