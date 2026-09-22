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

## Lane 1 — item records, the bounds alias, the cross axis, unconsumed records (2026-09-17, PDT)

Implementer's record. Commits: `0e4a209` (red), `ba908ad` (implementation and
amended pins), and this record's commit (docs, doc comments, probe revision 3).
Rulings: `LR-AW` (the lane's corrections to the design; the spec's lane-1 rows are
amended in place and marked *lane 1*).

### Red first (`0e4a209`, on the stage-1 lowering)

`swift build --build-system native --build-tests`: 0 `error:` (the first build of
the new file had two — an `@ElementBuilder` missing on a local builder and
`lastNativeLayoutWork` needing `@testable import MetalUILayout` — both fixed before
the run). `swift test --build-system native --no-parallel --skip-build`: **`Test run
with 1424 tests in 1 suite failed after 44.154 seconds with 197 issues`**, 17 tests
red:

| test | issues | first red line |
|---|---|---|
| 1.1 `aStretchedChildFillsTheLineOnItsCrossAxis` | 80 | `:184 r.unlowerable.isEmpty` (`box.alignItems.stretch`), `:186` cross size ≠ 70 |
| 1.2 `aStretchedContainersContentSitsByItsOwnAlignment` | 18 | `:236` lowered rects (the container a reported 0×0 leaf) |
| 1.3 `aStretchedSingleChildContainerDoesNotStretchItsChild` | 3 | `:285 r.loweredBounds[m] == bounds(0, 0, 200, 10)` |
| 1.4 `aStretchedItemIsClampedByItsOwnMinimumAndMaximum` | 8 | `:325`, `:334` lowered rects |
| 1.5 `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer` | 3 | `:361` lowered rects (`box.alignSelf` reported) |
| 1.6 `anAlignSelfWrapperFillsAnIndefiniteContainerWhereCSSHugs` | 2 | `:385` lowered rects |
| 1.7 `aStretchedItemInsideAHuggingItemFillsItsProposal` | 2 | `:409` lowered rects |
| 1.8 `aNilAxisFrameLayerUnderAStretchingContainerIsStretched` | 12 | `:435`, `:443`, `:450` |
| 1.9 `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields` | 15 | `:487`, `:499`, `:509`, `:517`, `:525 fill.unlowerable.isEmpty` |
| 1.10 `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap` | 7 | `:561`, `:563` |
| 1.11 `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork` | 6 | `:618` report, `:619 nodeCount == 19`, `:621`–`:623` work |
| 1.13 `anItemFieldNoLoweredContainerConsumesIsReportedByName` | 27 | `:774` arm entries (`box.flexGrow`, not `…unconsumed`), `:764` root rects |
| 1.14 `aStretchedUnsizedSpaceDistributionContainerIsReported` | 9 | `:799` report, `:807` rects |
| 1.15 `anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt` | 2 | `:833` lowered rects |
| 5.4 `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements` | 1 | `LayoutDifferential.swift:274 preflight.unlowerable.isEmpty` — `[box.alignSelf]` |
| 5.5 `aLoweredWindowPublishesTheSameAccessibilityTree` | 1 | the same pre-flight |
| 5.6 `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths` | 1 | the same pre-flight |

1.12 `theCentringDefaultOfRowAndColumnStretchesNothing` passed (characterization,
as the spec marks it). **Every legacy-side literal passed** (1.3, 1.6, 1.7, 1.9's
X16 arm, 1.15), and 1.13's recorded root literal (the legacy root ignores
`flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`) passed — the measurement the
root exception rests on (`LR-AW` item 4).

**1.11's literals** (19 nodes; 92 misses, 74 hits, 15 calls) were derived by hand
in the doc comment before the red run. The bookkeeping was checked with a Python
transcription of the kernel's documented rules (`scratchpad/s2l1/workmodel.py`),
first validated against stage 1's committed hand derivation of 5.7 (it reproduces
118/94/4, 16 nodes, the column 40×38 and the second row at (1, 20)); the first
derivation by hand missed placement's second solve of `SC` (9 hits), which the
transcription's trace showed before any test ran. The implementation's first run
matched all four literals and the five rects.

### Implementation (`ba908ad`)

- `Sources/MetalUI/LoweringState.swift` (new): `LoweredItem`, `LoweringState`
  (records, registration order, aliases), `Frame.reportUnconsumedLoweredItems(root:)`.
- `Frame.swift`: the stored `var lowering = LoweringState()` (with its doc), one
  expression in `bounds(of:)`, one call in `render` after the root registers.
  `Passes.swift`: one expression in `PaintPass.measuredWidth(of:)`.
  `ScrollView.swift`: the proposal branch consumes its content's records.
- `LegacyLowering.swift`: every site records its item; containers and the frame
  layer consume their children's records; `planLegacyItems` / `registerLegacyItems`
  (appended); the stretch rows removed from `legacyContainerDiagnostics` and the
  item rows from `legacyLeafDiagnostics`.
- `swift package clean` before the full run (`Frame` gained a stored property).

**First full run**: `Test run with 1424 tests in 1 suite failed after 43.754 seconds
with 33 issues`, 7 red — exactly the pins below, every new test green:
`everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (16),
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (5),
`stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (5),
`aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` (3),
`aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction` (2),
`aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` (1),
`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (1). Their red lines
named what moved: item fields under the harness root now read `…unconsumed`
(`Box flexGrow: [box.flexGrow.unconsumed]`; the 2.3b child trapped on
`box.flexGrow.unconsumed`), the stretch arms reported nothing, and the demo census
read 13 entries (`LR-AW` item 3). Each was amended as `LR-AW` records.

**Suite after the amendments**: `Test run with 1424 tests in 1 suite passed after
43.391 seconds` (1409 + 15 new tests; 0 `error:`, only SwiftPM's deprecation
`warning:`). Goldens 97, `git diff --name-only cb2e708 -- '*.json'` empty. Guards
71 (none added).

### The whole demo's census after lane 1 (5.3)

`[box.flexGrow ×3, list.noLowering, box.flexShrink, scrollView.noLowering,
box.flexGrow, box.flexBasis, box.minSize, box.flexGrow, modifierLayer.flexGrow,
box.flexGrow, box.flexGrow]` — every stretch and `alignSelf` entry gone (four
`box.alignItems.stretch`, `modifierLayer.alignItems.stretch`, `stack.alignSelf`,
`box.alignSelf`), no `…unconsumed`. Annotated in the test's doc comment.

**Follow-up commit `9245c1f`**: M1k (below) left the suite green, so 1.10 gained a
second arm (a stretched `Text("Wii il")` in a 4-wide column) and two doc comments
in `LegacyLowering.swift` were updated. Suite: `Test run with 1424 tests in 1 suite
passed after 43.038 seconds`. **Final**, after `swift package clean` (09:02 PDT):
build 0 `error:`, one `warning:` (SwiftPM's `--build-system native` notice); `Test
run with 1424 tests in 1 suite passed after 43.466 seconds`, 0 `error:`, no
`warning:`; goldens 97; no `.json` differs from `cb2e708`.

### Mutations

Each by `scratchpad/s2l1/mut/run.py`: file copied aside, the target asserted
unique, applied, `swift build --build-system native --build-tests`, full unfiltered
`swift test --build-system native --no-parallel --skip-build`, restored from the
copy, `git status --short` read after every one (it listed no `Sources/` or
`Tests/` path; the uncommitted docs of this record showed). All on `ba908ad`
except M1k's re-run on `9245c1f`. No build error, no truncated run. Issue counts in
parentheses.

| mutation | what | reddened |
|---|---|---|
| **M1a** | W registered, not aliased | 1.1 (54), 1.2 (12), 1.3 (1), 1.4 (6), 1.7 (1), 1.8 (6), 1.9 (4), 1.10 (6), 1.11 (1), 1.14 (2), `stretchAndSpaceDistribution…` (6) — 99 |
| **M1b** | W greedy on the main axis instead of the cross | 1.1 (56), 1.2 (12), 1.3 (1), 1.4 (8), 1.7 (1), 1.8 (6), 1.10 (6), 1.11 (4), 1.14 (7), `stretchAndSpaceDistribution…` (6) — 107 |
| **M1c** | W aligned `.topLeading` | 1.1 (8), 1.2 (8), 1.8 (4), 1.14 (4) |
| **M1d** = **M1l** | the one-child elision removed (`LR-AW` item 8) | 1.3 (1), 1.11 (4), `stretchAndSpaceDistribution…` (2), `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (9), `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (4), `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` (5) — P3 run 1's three, as the spec predicted |
| **M1e** | W drops `maxSize` | 1.4 (6) |
| **M1r** | W's minimum absent when undeclared (`LR-AW` item 1) | 1.4 (2) |
| **M1f** | the alignment frame's factor always 0 | 1.5 (2), 1.15 (1) |
| **M1g** | the alignment frame not greedy | 1.5 (2), 1.6 (1), 1.15 (1), 5.4 (18), 5.5 (1), 5.6 (2) |
| **M1h** | stretch only in a parent declaring its cross size | 1.1 (28), 1.4 (4), 1.7 (1), 1.11 (5) |
| **M1i** | frame-layer records skipped by the parent | 1.8 (6) |
| **M1j** | a stack parent lowers `alignSelf` | 1.9 (2) |
| **M1j′** | a stack parent's stretch not greedy | 1.9 (4) |
| **M1k** | alias in `bounds(of:)` but not `measuredWidth(of:)` | **none on `ba908ad`** — the finding: at 120 the leaf's widest line re-wraps to W's lines, so no test could see the width paint asks. Proven different first: a scratch arm below a glyph's width read `scenesEqual` false under the mutant at widths 4 and 6 (true at 9). Re-run on `9245c1f` with that arm in 1.10: 1.10 (1) |
| **M1m** | the unconsumed check removed | 1.13 (18), 2.3 (16), 4.1 (1), `stretchAndSpaceDistribution…` (1) |
| **M1m′** | `ScrollView` does not mark its records | 1.13 (1). The demo census stayed green: the demo's `ScrollView` receives only the `List`'s `Box` and the modal's `Deferred` stack, neither declaring an item field (spec §7 asked for this either way) |
| **M1n** | the alignment frame aliased | 1.5 (2), 1.6 (1), 1.15 (1), **5.4 (9), 5.5 (3)** — not 5.6, whose slots are id-keyed and whose width half has no `alignSelf`; the `CounterPanel`-specific mutations that do redden 5.6 are M1g and M1q (the chrome moves off x 0 and the "+" click misses, so `$state0` is never written) and stage 1's M5d (below) |
| **M1o** | stretch applied for `.center` | 1.12 (9), 1.15 (1), 5.4 (8), 5.5 (3), 5.1 (23), 5.2 (1), 5.7 (6), `aLoweredContainerPaddingSitsInsideItsDeclaredSize` (3) |
| **M1p** | the free-space re-check removed | 1.14 (3) |
| **M1q** | `alignSelf` elided in a one-child container | 1.15 (1), 5.4 (18), 5.5 (1), 5.6 (2) |
| **M1t** | the parent's `flexGrow` report dropped | 1.13 (1), 2.3 (2), 5.3 (1) |
| **M1u** | the root not exempt | 1.13 (4) |
| **M5d** (stage 1's, re-run) | lowered stack spacing + 50 | 26 tests, 217 issues: 5.4 (18), 5.5 (1), 5.6 (2), 5.1 (23), 5.2 (1), 5.7 (3), lane 3's 3.1 (24), 3.2 (6), 3.3 (36), 3.4 (5), 3.5 → `stretchAndSpaceDistribution…` (7), 3.6 (1), 3.7 (6), 3.8 (3), 1.1 (42), 1.2 (12), 1.4 (6), 1.5 (2), 1.6 (1), 1.7 (1), 1.8 (3), 1.10 (3), 1.11 (4), 1.12 (3), 1.14 (3), 1.15 (1) |

Every lane-1 test is reddened by its spec mutation; no mutation left the suite
green except M1k on the first tree, now closed.

### Pixels (CN-R)

`gen-lib.py` into `git archive`s of `cb2e708` and `ba908ad` (the last commit
changing behaviour under `Sources/`; `9245c1f` changes doc comments only),
`DEMO_PIXELS_SMALL=1`: **12 of 12 read 0 differing pixels, scene identical.**
Controls on the head images: light vs dark f0 1 048 576; vs modal-light
1 030 498; vs animation-light 210 027; f0 vs f3 0; preview light vs dark
1 048 576 — the stage-1 figures.

**The two-authority chrome pair, re-taken with `CounterPanel()`**
(`DifferentialRoot(560) { Column { CounterPanel() }.width(560) }` through a 560²
fake `Window` per authority, on `ba908ad`): **`chrome-legacy` vs `chrome-proposal`
0 differing pixels, scene files identical**; not blank (216 distinct pixel values;
308 354 against `small560-default-light`). **Control, M5d** on an archive of
`ba908ad`: 8 214 differing pixels, scenes differ.

### Probe

Stage-2 probe revision 3 (group Z, `LR-AW` item 1): exit 0, run twice,
byte-identical, 243 lines; the first 234 identical to the revision-2 OUTPUT, then
Z0/Z1 and DONE; filtered stderr empty. Z0 (control) `b20x50.frame(maxHeight:.inf)`
in a 30-tall row: 20×50 at y −10. Z1 with `minHeight: 0`: frame 20×30 at y 0, the
child at y −10. Recorded in the header.

### Screen lock and captures

`appkit-screen-lock-state` at 08:40, 08:44 and 09:02 PDT: `CGSSessionScreenIsLocked
= 1`, `displayAsleep main: 1`. No real-window capture was taken. `IOConsoleLocked`
not read (`FR-V`).

### Deferred from lane 1, by name

- **Every item field lane 1 still reports** — `flexGrow`, `flexShrink`,
  `flexBasis`, `minSize`/`maxSize` off a stretched axis: lane 2; `margin`, and a
  percentage on a stretched axis: lane 4; `alignSelf.baseline`: task 11.
- **The exit test** (5.3's rewrite to `[list.noLowering, scrollView.noLowering]`
  with its rect causes): lane 2.
- **1.1's "line = tallest sibling" (X1)**: not expressible as an agreeing arm under
  the harness root (`LR-AW` item 6); X1 is exercised by the kernel's own stack
  placement at a nil cross proposal, which no lowered tree produces.

### For the integrator

- `Frame.lowering` is a new stored property on a public class: `swift package
  clean` after merging. `Frame.bounds(of:)` and `PaintPass.measuredWidth(of:)`
  each changed by one expression; `Frame.render` gained one call
  (`reportUnconsumedLoweredItems(root:)`).
- `ScrollView.swift` gained one line in its proposal branch (marks records).
- New divergences pinned by this lane (proposal authority only): X9 (1.3), X7
  (1.6), X4 (1.7), X16 (1.9), X14 (1.15). The stage-1 census (5.3) is now an
  ordered literal of 13 entries.
- Retired stage-1 mutations: M3f and M5c (the stretch rows they mutated are gone).

## Lane 2 — the main axis, animated fields, depth, the exit test (2026-09-17, PDT)

Implementer's record. Commits: `27a9e23` (red), `f25889a` (implementation and
amended pins), `30737bd` (2.12's minimum arm), and this record's commit (docs, probe
re-run note, `LR-AX`, spec rows marked *lane 2*). Rulings: `LR-AX`.

### Probes re-run before the tests

- `swiftui-engine-replacement-stage2.swift` (revision 3, unchanged source), its HOW
  TO RUN filter: run twice, exit 0, 243 lines, the two runs byte-identical and
  identical to the header's OUTPUT (leading whitespace ignored). Lane 2 cites F1–F10,
  X4, X10, X12, X18.
- `swiftui-stack-algorithms.swift`: exit 0, 787 lines, identical to its OUTPUT block
  (G1, G9, G4r, A5, S cited).

### Legacy answers measured before literals were written (scratch, deleted)

`LayoutDifferential.render(authority: .legacy, …)` in a scratch test: the demo's
element ids and legacy rects (2036 ids; the table in 2.15's doc comment); 2.5's
design shape — the text 252×16, the `Box().width(50)` beside it **0×10 at x 252**
(`LR-AX` item 2); F9's text 107×16 (min-content 107.22), the zero-basis box 0 wide;
the 2.9 replica — sidebar **88**, main pane at x 100, 788 wide, as on the demo; the
shaping cache: "-" 9.62, "+" 13.31, "Count 0" 76.42 (22pt, 26 tall), "3" 8.07 (13pt,
16), the paragraph 48 tall at 756 and 64 at 648 (`proposalTextMeasurement` 751.87×48
and 641.89×64), "Text renders" 26 at both.

### Red first (`27a9e23`, on lane 1's lowering `25fd9fb`)

`swift build --build-system native --build-tests`: 0 `error:` (the first build had
one class of error — an exit test's body calling a local `@ElementBuilder` function,
moved to file scope as `animatedWeightsArm`). `swift test --build-system native
--no-parallel --skip-build`: **`Test run with 1439 tests in 1 suite failed after
45.627 seconds with 92 issues`**, exactly the 16 lane-2 tests red:

| test | issues | first red line |
|---|---|---|
| 2.15 `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` | 4 | `LoweringCorpusTests.swift:494` report ≠ `[list.noLowering, scrollView.noLowering]` |
| 2.1 `aGrowingChildTakesTheRemainingMainSpace` | 4 | `LoweringItemTests.swift:912` `r.unlowerable.isEmpty` |
| 2.2 `growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases` | 12 | `:963` `r.unlowerable.isEmpty` |
| 2.3 `unequalGrowWeightsAreReportedOnTheParent` | 7 | `:996` report ≠ `[box.flexGrow.weights]` |
| 2.4 `aZeroBasisGrowerTakesItsShareDownToItsContent` | 14 | `:1048` `r.unlowerable.isEmpty` |
| 2.5 `aZeroShrinkKeepsItsNaturalMainSizeAndOverflows` | 12 | `:1138` `r.unlowerable.isEmpty` |
| 2.6 `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` | 2 | `:1179` `r.unlowerable.isEmpty` |
| 2.7 `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent` | 12 | `:1209` `r.unlowerable.isEmpty` |
| 2.8 `aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere` | 8 | `:1251` `r.unlowerable.isEmpty` |
| 2.9 `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt` | 2 | `:1298` `r.unlowerable.isEmpty` |
| 2.10 `aGrowerOnAHuggingContainersMainAxisFillsItsProposal` | 2 | `:1336` `r.unlowerable.isEmpty` |
| 2.11 `aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown` | 2 | `:1358` `r.unlowerable.isEmpty` |
| 2.12 `aGrownUnsizedSpaceDistributionContainerIsReported` | 7 | `:1379` report ≠ `[box.justifyContent.spaceBetween]` |
| 2.13 `anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues` | 1 | `:1476` arm A's pre-flight `unlowerable.isEmpty` |
| 2.14 limit `aLoweredItemChainWithThreeWrappersPerLevelAtTheNativeDepthLimitLaysOut` | 2 | `LoweringPipelineParityTests.swift:479` exit `.signal(SIGTRAP)` (the chain's first report) |
| 2.14 trap `…OnePastTheNativeDepthLimitTraps` | 1 | `:508` stderr lacks `native layout recursion exceeded 88 levels` |

**Every legacy-side literal passed** (2.2's 190/110 and 240/60, 2.4's F9 text and
sized-container arm, 2.6's 50/50 and 65/35, 2.9's 88/100/788, 2.10, 2.11), and 2.15's
derived figures reproduced P3's (`[439, 310, 26, 48, 439, 26, 64, 455, 16]`, the
expectation at its line 594 passed). 2.13's legacy series were not reached (its
pre-flight `#require` threw first) and are first checked by the implementation run.

**2.1's spelling was corrected after the red run** (`f25889a`): its container was
built with a builder `if`/`else`, which adds an id level (`LR-AX` item 10), so the
implementation run found no rect at `child(containerID, 1)`. Re-spelled with
`AnyElement` and re-run against lane 1's `LegacyLowering.swift` (copied aside,
`git checkout`, native build, filtered run, restored; `git status --short` showed
only the test file): red at `:909` `r.unlowerable.isEmpty` and `:912` the grown
extent.

### Implementation (`f25889a`)

`LegacyLowering.swift` only: `LegacyItemPlan` gains `fixedSizeHorizontal`, and W's
per-axis bounds become `(min: Double?, max: Double?)`; `planLegacyItems` takes the
parent's site and plans the weights check, grow, basis, shrink, minima and maxima
(`LR-AE`, `LR-AF`, `LR-AG`, `LR-AS`, `LR-AX`); `registerLegacyItems` registers
`fixedSize` innermost; `paddedAndSized` folds a declared size with its own
`minSize`/`maxSize`. No `Frame`/`Passes` edit, no stored property (no `swift package
clean` needed).

**First full run**: `Test run with 1439 tests in 1 suite failed after 43.351 seconds
with 9 issues` — 2.1's id level (above) and three pins, whose red lines named what
moved: `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (`List: [list.noLowering]`,
expected `[list.noLowering, box.flexShrink]`), `anItemFieldNoLoweredContainerConsumesIsReportedByName`
(`control Row: []`, expected `[box.flexGrow]`), `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf`
(six in-`Row` arms: `minSize`, `flexGrow`, `flexShrink` on `Box` and `Text` read
`[]`). Amended as `LR-AX` item 5 and the spec's lane-2 amended-pins note say. 2.13,
2.14 and 2.15 passed on the first implementation run, 2.15 with all 30 pairs.

**Suite**: `Test run with 1439 tests in 1 suite passed after 44.226 seconds` (1424 +
15; 2.15 replaces stage 1's 5.3). After `30737bd` and this record's docs, **final**,
10:46 PDT: build 0 `error:`, one `warning:` (SwiftPM's `--build-system native`
notice); `Test run with 1439 tests in 1 suite passed after 45.946 seconds`, 0
`error:`, no other `warning:`; goldens 97; `git diff --name-only cb2e708 -- '*.json'`
empty. Guards 71 (none added).

### The exit test's census (2.15)

Modal off: report `[list.noLowering, scrollView.noLowering]`; 2036 ids, 6 agreeing
(root, header layer, header row, avatar, bar, hairline), 30 disagreeing, 2000
legacy-only, 0 lowered-only — every pair equal to P3's and scratch R2's table above
(the literal list and derivations are in the test). Modal on: `[stack.position,
stack.inset, list.noLowering, scrollView.noLowering]`, 2042 ids, 6 agreeing, 36
disagreeing: the 30 (the `List` and its row box one index later) plus the modal's
six ids. No row fell outside the five causes. The whole demo's **deepest native run**
under the proposal authority: **18** in both modal states (78 and 88 native nodes),
by a scratch `max` in `NativeLayoutRun.enter` restored afterwards (`git status
--short` clean); stage 1 measured 12.

### Mutations

`scratchpad/s2l2/mut/run.py` (lane 1's runner, new table): committed tree
(`30737bd`), file copied aside, target asserted unique, applied, native build, full
unfiltered `swift test --build-system native --no-parallel --skip-build`, restored
from the copy, `git status --short` read after each — **empty after all 43**. No
build error, no truncated run (every log has its summary line). Lane 1's mutations
were re-run too, re-spelled against the restructured `planLegacyItems` (the whole
table re-taken, practices record-shape 3). Issue counts in parentheses.

| mutation | what | reddened |
|---|---|---|
| **M2a** | grow on the cross axis | 2.1 (36), 2.2 (8), 2.3 (4), 2.4 (9), 2.7 (3), 2.8 (4), 2.10 (1), 2.11 (1), 2.12 (5), 2.13 (2), 2.15 (3) |
| **M2b** | W's main minimum 0 without a declared one (both branches) | 2.2 (1), 2.4 (3) |
| **M2c** | weights check removed | 2.3 (1) |
| **M2d** | a non-zero length basis lowered as `auto` | 2.4 (1), leaf 2.3 (2) |
| **M2d′** | a zero basis given W's minimum 0 | 2.4 (3) |
| **M2d″** | a sized zero-basis grower lowered | 2.4 (1) |
| **M2e** | `fixedSize` on the cross axis | 2.5 (10) |
| **M2f** | a shrink ≠ 0, 1 reported | 2.6 (2) |
| **M2g** | W drops the minimum (greedy and floor) | 2.7 (6), 2.12 (1), 2.13 (1) |
| **M2h** | the fold's minimum skipped | 2.7 (3) |
| **M2h′** | the fold's maximum skipped | 2.8 (3) |
| **M2i** | a non-greedy maximum lowered onto W | 2.8 (1), leaf 2.3 (2), 1.12 (1) |
| **M2j** | a declared size lowered as `frame(maxWidth:maxHeight:)` | 2.15 (32), stage 1's 4.4 `aLoweredFixedFrameLayerAgrees…` (18), 5.7 (3), 1.11 (3), 2.2 (1), 2.4 (4), 2.5 (4), 2.6 (1), 2.7 (3), 2.13 (1), 3.6 (1), 4.6 `anIdealFrameLowers…` (1), 5.2 (1) |
| **M2k** | grow only where the parent declares its main size | 2.10 (1), 2.11 (1), 2.14 limit (1), 2.14 trap (2), 2.15 (3) |
| **M2l** | grow elided in a one-child container | 2.11 (1) |
| **M2m** | the re-check only for stretch | 2.12 (2) |
| **M2m′** | the re-check only for a greedy W | 2.12 (1) |
| **M2n** | W's existence from `animated.flexGrow > 0.5` | 2.13 (2), 2.3 (2) |
| **M2o** | weights from the animated style | 2.13 (2: arm B's child exits on the trap) |
| **M2p** | W's minimum from the declared style | 2.13 (1) |
| **M2q** | `maxDepth` 96 | 2.14 trap (2), stage 1's 5.9 (2) |
| **M2r** | a negative `flexGrow` not reported | leaf 2.3 (2) |
| **M5c′** | the weights check always reporting | 2.15 (4), 1.13 (1), 2.1 (52), 2.2 (12), 2.3 (6), 2.4 (14), 2.7 (4), 2.8 (4), 2.9 (2), 2.10 (2), 2.11 (2), 2.12 (7), 2.13 (1), 2.14 limit (2), 2.14 trap (1) |
| **M1a** | W not aliased | 1.1 (54), 1.2 (12), 1.3 (1), 1.4 (6), 1.7 (1), 1.8 (6), 1.9 (4), 1.10 (10), 1.11 (1), 1.14 (2), `stretchAndSpaceDistribution…` (6), 2.1 (32), 2.2 (8), 2.3 (4), 2.4 (6), 2.5 (3), 2.7 (6), 2.8 (3), 2.10 (1), 2.11 (1), 2.12 (2), 2.13 (3), 2.15 (3) |
| **M1b** | stretch on the main axis | 1.1 (56), 1.2 (12), 1.3 (1), 1.4 (8), 1.7 (1), 1.8 (6), 1.10 (10), 1.11 (4), 1.14 (7), `stretchAndSpaceDistribution…` (6), 2.5 (5), 2.9 (1), 2.15 (3) |
| **M1c** | W aligned `.topLeading` | 1.1 (8), 1.2 (8), 1.8 (4), 1.14 (4), 2.1 (8), 2.12 (4) |
| **M1d** | the one-child elision removed | 1.3 (1), 1.11 (4), `stretchAndSpaceDistribution…` (2), `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (9), `theStageOneCorpusLowersWith…` (4), 5.7 (5), 2.15 (2) |
| **M1e** | W's maximum always ∞ | 1.4 (6), 2.8 (3) |
| **M1r** | W's minimum absent when undeclared | 1.4 (2), **1.10 (4)** — lane 1's M1r (`min == 0 → nil`) reddened 1.4 alone; this spelling also reaches 1.10's 4-wide column (by reading: W with no minimum answers the text's widest glyph there, not the line) |
| **M1f** | alignment factor 0 | 1.5 (2), 1.15 (1) |
| **M1g** | alignment frame not greedy | 1.5 (2), 1.6 (1), 1.15 (1), 5.4 (18), 5.5 (1), 5.6 (2) |
| **M1h** | stretch only in a parent declaring its cross size | 1.1 (28), 1.4 (4), 1.7 (1), 1.11 (5), 2.15 (3) |
| **M1i** | frame-layer records skipped | 1.8 (6) |
| **M1j′** | a stack parent's stretch removed | 1.9 (4) |
| **M1k** | alias not in `measuredWidth(of:)` | 1.10 (1) |
| **M1m** | the unconsumed check removed | 1.13 (18), leaf 2.3 (16), 4.1 (1), `stretchAndSpaceDistribution…` (1) |
| **M1m′** | `ScrollView` does not mark | 1.13 (1). **Not 2.15**: the demo's `ScrollView` receives the `List`'s `Box` and the modal's `Deferred` stack, neither declaring an item field (as lane 1 found) |
| **M1n** | the alignment frame aliased | 1.5 (2), 1.6 (1), 1.15 (1), 5.4 (9), 5.5 (3) |
| **M1o** | stretch for `.center` | 1.12 (9), 1.15 (1), 2.1 (16), 2.4 (9), 2.5 (4), 2.11 (1), 2.12 (4), 2.15 (8), 5.1 (23), 5.2 (1), 5.4 (8), 5.5 (3), 5.7 (6), `aLoweredContainerPaddingSitsInsideItsDeclaredSize` (3) |
| **M1p** | the re-check removed | 1.14 (3), 2.12 (2) |
| **M1q** | `alignSelf` elided in a one-child container | 1.15 (1), 5.4 (18), 5.5 (1), 5.6 (2) |
| **M1u** | the root not exempt | 1.13 (4) |

Lane 1's **M1j** (a stack lowering `alignSelf`) was not re-run: its insertion
point is the same stack branch as M1j′ and nothing in lane 2 touched the stack's
`alignSelf` handling. **M1t** is retired (`LR-AX` item 9). Every lane-2 test is
reddened by its spec mutation; 2.15 by M1a, M2a, M1d, M2k and M5c′ (M1m′: not, as
spec §7 allowed).

### Pixels (CN-R)

`gen-lib.py` with lane 1's chrome lines (`Column { CounterPanel() }.width(560)`),
generated into a `git archive` of `f25889a` (the last commit changing `Sources/`),
`DEMO_PIXELS_SMALL=1`, compared with lane 1's `cb2e708` images (`s2l1/px-base`, the
same commit's archive): **12 of 12 read 0 differing pixels, scene identical.**
Controls on the head images: light vs dark f0 1 048 576; vs modal-light 1 030 498;
vs animation-light 210 027; f0 vs f3 0; preview light vs dark 1 048 576. **The
two-authority chrome pair** on `f25889a`: 0 differing pixels, scenes identical, 216
distinct pixel values; **control**, M5d (lowered stack spacing + 50) applied to the
same archive and restored: 8 214 differing pixels, scenes differ.

### Screen lock and captures

`appkit-screen-lock-state` at 10:09 and 10:44 PDT: `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1`. No real-window capture was taken. `IOConsoleLocked` not
read (`FR-V`).

### Deferred from lane 2, by name

- **Unequal grow weights**: reported (`flexGrow.weights`), deleted concept, stage 10.
- **A non-zero or fractional `flexBasis`, a zero basis on a sized grower without a
  minimum**: reported, stage 8 / 10.
- **`maxSize` on a non-greedy axis**: reported, stage 8.
- **Percentage `minSize`/`maxSize`**: reported under stage 1's names; lane 4's 4.7
  renames them.
- **A floored `space-*` container** (`LR-AX` item 4) and a grown or stretched one
  (`LR-AR`): reported, stage 8's recipe.
- **Negative grow or shrink**: reported; no owner needed beyond stage 8's recipe.
- **Divergence 55 in production**: stage 6b.
- `margin`, `border`, `Style` padding on a `Text`, the `BM-4` floor and depth with
  four wrappers per level: lane 4. Justify distribution and reverse: lane 5.

### For the integrator

- **New divergences pinned by this lane** (proposal authority only): growers share
  equally (F2/F3, 2.2); a zero-basis `Text` grower breaks inside its word (F9,
  2.4); a sized zero-basis container lays out at its declared size inside its item
  rect (F4, 2.4, re-spelled); positive shrink is SwiftUI's compression whatever its
  weight (55, 2.6, 2.9); a grower fills a hugging container's main axis (X18, 2.10);
  a grow inside a one-child padding fills it (X12, 2.11); an animated `flexGrow`
  snaps its structure and equal declared factors stay equal mid-flight (2.13 — the
  CLAUDE.md snap list gains both).
- **CLAUDE.md's "Unprobed kernel behaviour" and inert tables**: a legacy
  `flexGrow` under the proposal authority now reaches a greedy frame; divergence 55
  is lowered to SwiftUI's answer (6b brings it to production).
- **Depth**: the demo's deepest native run is 18 (was 12); 2.14 pins 88/89 exactly
  with three wrappers per level. Lane 4 re-derives the pair with four.
- **Shared file**: `LegacyLowering.swift` only (`planLegacyItems` restructured,
  `registerLegacyItems`, `paddedAndSized`'s fold); the call sites of
  `planLegacyItems` gained `parentSite:`.

---

## Lane 3 — the proposal-path answers that reach production (2026-09-17, PDT)

Two commits, each with its own red run, full suite, twelve `CN-R` images and
mutations. Ruling `LR-AU` scoped the lane; `LR-AY` records its corrections.

### Probe re-run before the tests

Stage-2 probe `docs/probes/swiftui-engine-replacement-stage2.swift`, revision 4
(group N, appended before `DONE`): **exit 0, run twice, stdout byte-identical,
254 lines**, filtered stderr empty, matching the revision-4 header line for line.
N0 (control, `.padding(5)`): the child at (5, 5) 20×20 in a 30×30 pad. N1
(`.padding(−15)` beside a sibling): the pad answers 0×0 at (0, 10) and the child
is **(−15, −5) 20×20** where the rect minus the insets reads 30×30. N2 (a
proposal-filling child under insets top 1, leading 4, bottom 3, trailing 2 at
100×100): offered 94×96, placed at (4, 1) 94×96 — the two rules agree.

### Commit 1 — `SA-N` item 4 (`8a2d753`)

`placeNative`'s `.padding` case stored the child at the padding's bounds minus its
insets; it now stores the child's **own** measurement at the origin plus the
leading and top insets, exactly as `.fixedSize` does.

**Red first**: `aNativePaddingPlacesItsChildAtTheChildsOwnSize` (3.1) failed with
2 issues and `negativePaddingIsAcceptedAndItsResponseClampsPerAxis` (3.2) exited
`SIGTRAP` on its own pinned-wrong precondition — the trap `LR-AU` measured at
design time, reproduced here as the red run, and gone once the precondition reads
SwiftUI's 20×20.

3.1 has three arms (`LR-AY` item 3): the clamped stack response (N1), the
caller-bounds entry `computeNativeLayout(root:proposal:in:)` — a rigid 20×20 child
under asymmetric insets in (10, 20, 100, 100) stored at (14, 21) 20×20 where the
old rule read 94×96 — and N2 as the control that must not move. A custom
`ProposalLayout`, which the design proposed, **cannot** show the change: its
`place(at:anchor:proposal:)` sizes a subview by its own answer (`SA-C`).

**Suite 1440** (lane 2 left 1439; +1 is 3.1), 0 `error:`/`warning:` beyond
SwiftPM's deprecation notice. Goldens 97, `git diff --name-only cb2e708 --
'*.json'` empty.

### Commit 2 — the below-word text clamp (`d0c439a`)

`proposalTextMeasurement` now answers `min(proposal, widestLine)` on a finite
proposal and is unchanged on an unspecified one. Divergence 59 closes here rather
than in task 11 (`LR-AY` item 6); W2 stays deferred.

**The kernel's own answers, dumped before any literal** (scratch test, deleted):
at probe Y's nine widths the line counts are 1, 2, 2, 4, 5, 2, 2, 12, 7 — probe
Y's exactly — and the widest lines 32.84, 18.17, 18.17, 10.31, 7.86, 17.25, 17.25,
33.31, 44.02, matching the probe's printed CoreText readings to two decimals. A
first pass read Y1–Y5 as the sentence rather than `"alpha"` and got 10, 13, 16, 28
and 37 lines; the table was the misread, not the engine (`LR-AY` item 1).

**Red first**: 3.3 (stage 1's 2.7 re-derived and renamed
`aProposalTextBelowItsWidestBrokenLineAnswersTheProposal`) failed on
`answer.size.width == width` at both 0 and 5; 3.4
(`aProposalTextBreaksInsideAWordAndAnswersItsWidestLineUpToTheProposal`) failed
with 10 issues, `clamped == 2` among them.

Only **Y5** (7.86 against a 5 proposal) and **Y8** (33.31 against 30) can see the
clamp; the other seven hug. 3.4 pins that count with a `try #require` computed
from the cache. Every width is derived from the shaping cache, never written down:
**SwiftUI ceils and MetalUI does not** (Y2 19 against 18.17, Y9 45 against 44.02),
so a literal-for-literal test would have failed for the rounding and hidden the
clamp (`LR-AY` items 2 and 4).

**Suite 1441**, 0 `error:`/`warning:`. Goldens 97 unchanged.

### Mutations

Commit first, `cp` aside, apply, full unfiltered
`swift test --build-system native --no-parallel`, restore from the copy,
`git status --short` empty each time.

| id | mutation | reddens (issues) |
|---|---|---|
| **M3a** | the padding's bounds-minus-insets placement restored | 3.1 (2), 3.2 (1, the exit test) — 3 issues in 1440, and nothing else |
| **M3b** | the text clamp removed | 3.3 (2), 3.4 (2) — 4 issues in 1441 |
| **M3c** | the clamp applied as the proposal whenever a line breaks | 48 issues in 10 tests: 3.4, `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock`, `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`, `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`, `aLoweredContainerPaddingSitsInsideItsDeclaredSize`, `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`, `aLoweredWindowPublishesTheSameAccessibilityTree`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm`, the exit test (2.15) |

M3a leaves 3.3/3.4 green and M3b leaves 3.1/3.2 green: the two commits' pins are
independent.

### Pixels (CN-R)

`gen-lib.py` into a `git archive` of each commit's tree, `DEMO_PIXELS_SMALL=1`,
against lane 1's `cb2e708` images (`s2l1/px-base`):

| commit | result |
|---|---|
| 1 (`SA-N` item 4) | **12 of 12: 0 differing pixels, scene identical** |
| 2 (the text clamp) | **12 of 12: 0 differing pixels, scene identical** |

The preview is among the twelve in both, so neither production answer reaches a
production root's pixels — measured at both commits, where the design predicted it
for commit 2 (`LR-AY` item 5). **Controls on the head images**: light vs dark f0
1 048 576; vs modal-light 1 030 498; vs animation-light 210 027; f0 vs f3 0;
preview light vs dark 1 048 576 — the stage-1 figures exactly.

### The exit test

`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (2.15) re-ran
**unchanged** after both commits, and M3c reddens it. The demo declares no padding
whose rect differs from its answer and no text below its widest broken line.

### Deferred from lane 3, by name

- **W2** (the long label at priority 1): task 11, as a stack-allocation question
  (`LR-AM` as amended, `LR-AY` item 6). The clamp does not touch it.
- **SwiftUI's ceiling on a text answer**: unowned; a separate decision with its own
  pixels (`LR-AY` item 4).
- `margin`, `border`, `Style` padding on a `Text`, the `BM-4` floor and depth with
  four wrappers per level: lane 4. Justify distribution and reverse: lane 5.

### For the integrator

- **Commit 1 is a production kernel change under the proposal authority, in a
  shared file** (`LayoutTree.swift`, the `.padding` case of `placeNative` only).
  **Any padding test the other track wrote against bounds-minus-insets placement
  must be re-checked after the merge** — this is critic finding 10's semantic
  collision, landed on its own commit so it can be identified.
- **`SA-N` item 4 leaves the open list.** CLAUDE.md's "Probed, and the kernel
  disagrees" section loses its padding row; `NativeValidationAcceptanceTests.swift`
  loses its "pinned wrong on purpose" paragraph.
- **Divergence 59 closes.** It was stage 1's, assigned to task 11 and taken back by
  `LR-AM` as amended; CLAUDE.md's text section and the divergence table both change.
  W2 remains open and is task 11's.
- **Shared files touched**: `LayoutTree.swift` (one case, commit 1) and
  `Sources/MetalUI/ProposalText.swift` (one expression, commit 2). No signature,
  no stored property, no public spelling changed.

---

## Lane 4 — the box model (2026-09-17, PDT)

Implementer's record. Commits: `ff8b05c` (red), `55621aa` (implementation and
amended pins), `9a4a130` (4.6's unconsumed arm), and this record's commit (docs,
`LR-AZ`, the spec's lane-4 rows). Rulings: `LR-AZ`.

### Probe re-run before the tests

Stage-2 probe `docs/probes/swiftui-engine-replacement-stage2.swift` (revision 4,
unchanged source), its HOW TO RUN filter: run twice, exit 0, **254 lines**, the two
runs byte-identical and identical to the header's OUTPUT block line for line
(leading whitespace ignored); filtered stderr empty. Lane 4 cites P1, P3, P4, P6,
P7, P8, N1 and C1/C2 from this run. **No new arm was needed**: every SwiftUI claim
lane 4 makes is one of those.

### Legacy answers measured before any literal was written (scratch, deleted)

A scratch differential test dumped both authorities' rects for every shape in the
lane, in four rounds, and then was deleted (`git status --short` clean before the
red commit). Two of the design's predictions were wrong and one measurement decided
a ruling:

| shape | legacy, measured |
|---|---|
| 60×50 `Box`, padding (2, 3, 4, 5), border (1, 2, 3, 4), over a 10×10 child | 60×50, child at (9, 3) |
| unsized `Box`, border (1, 2, 3, 4) | 6×4; with padding 2 as well, 10×8 |
| `Text("alpha")` with `Style.padding` 10 beside a 20×10 sibling in a flexStart `Column` | text 33×16 at (0, 0), column 33×26, sibling at (0, 16) |
| the same sentence text in a 140-wide stretch `Column` | text 140×32, column 140×42, sibling at (0, 32) |
| a 10×10 rigid child in a 10×10 container padded 12 | **24×24** (not the design's 34×34), child at (12, 12) `Box` / (12, **7**) `Row` / (**7**, 12) `Column` |
| `Row { 20×10.margin(2,3,4,5); 20×10 }` | row 48×16, a at (5, 2), b at (28, 3) |
| `Column {…}` the same | column 28×26, b at (4, 16) |
| the row in rem (0.25, 0.5, 0.75, 1 at root font size 16) | row 64×26, a at (16, 4), b at (44, 8) |
| `Stack { 20×10.margin(2,3,4,5); 30×20 }` | **30×20**, a at (5, 5) — the margin ignored in size and position; at a symmetric margin 20, still 30×20 |
| `20×10.margin(2,3,4,5).frame(80, 60)` | child at (30, 25) — the margin-blind answer, not (31, 24) |
| a stretched item with cross margins in a 60-tall stretch `Row` | row 48×60, a at (5, 2) 20×54 |
| a grown item with main margins in a 200-wide `Row` | a at (5, 2) 172×10, b at (180, 3) |
| `Row { 20×20.margin(−8); 20×20 }` | row 24×20, a at (−8, 0), b at (4, 0) — P4's SwiftUI reading exactly |
| `Row { 20×20.margin(−15); 20×20 }` | row **10**×20, a at (−15, 0), b at (**−10**, 0) |
| `margin: .auto` in a `Row` | 40×10, children at 0 and 20 — resolved to 0 |
| the percentage arms, under stage 1's names | `border` → `box.border`; `margin` → `box.margin`; `minSize` → `box.minSize`; `maxSize` → `box.maxSize` |

Shaping, for 4.2's derivations (13pt, no family): `"alpha"` natural 32.836×16; the
sentence at 120 → **3** lines widest 117.96, at 140/150/160/170/180 → 2 lines
(widest 133.92 at 140, 151.76 from 150 up), at 200 → 2 lines widest 185.07. **The
design's 200-wide stretched arm could not have discriminated M4b′** — the leaf's
180 and the element's 200 break the same two lines — so the arm was re-spelled at
140, where the leaf's 120 breaks three.

### Red first (`ff8b05c`, on lane 3's lowering `51c4628`)

`swift build --build-system native --build-tests`: 0 `error:`. `swift test
--build-system native --no-parallel --skip-build`: **`Test run with 1450 tests in 1
suite failed after 45.717 seconds with 72 issues`**, exactly the nine lane-4 tests:

| test | issues | first red line |
|---|---|---|
| 4.1 `aStyleBorderLowersAsInsetsInsideTheDeclaredSize` | 15 | `LoweringBoxModelTests.swift:118` `r.unlowerable.isEmpty` (`box.border`) |
| 4.2 `paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt` | 10 | `:194` `plain.unlowerable.isEmpty` (`text.padding.text`) |
| 4.3 `aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox` | 9 | `:303` `r.unlowerable.isEmpty` (`box.padding.floor`) |
| 4.4 `aMarginLowersAsPaddingOutsideTheItem` | 23 | `:351` `r.unlowerable.isEmpty` (`box.margin`) |
| 4.5 `aNegativeMarginOverlapsItsSibling` | 5 | `:432` `r.unlowerable.isEmpty` |
| 4.6 `anAutoMarginLowersAsZero` | 3 | `:464` `r.unlowerable.isEmpty` |
| 4.7 `percentagesStillReportByNameWithTheirOwner` | 4 | `:511` `arm.report == [field(.box, arm.name)]` |
| 4.8 limit `…AtTheNativeDepthLimitLaysOut` | 2 | `:562` `expected exit status ".success", but ".signal(SIGTRAP)"` |
| 4.8 trap `…OnePastTheNativeDepthLimitTraps` | 1 | `:591` stderr lacks `native layout recursion exceeded 88 levels` |

**Every legacy-side literal passed** on the red run — 4.1's rects, 4.2's 33×16 /
33×26 / (0, 16), 4.3's 24×24 and all three child positions, 4.4's seven arms'
legacy halves and 4.5's −10 — which is what makes the lowered halves the only thing
the implementation moves.

**4.3's first spelling was corrected before the red run was banked**: its three
containers were built inside the builder closure with a `switch`, which adds an id
level (`LR-AX` item 10), so every id it named read `nil`. Re-spelled by building the
`AnyElement` outside the closure; the corrected run is the one above.

### Implementation (`55621aa`)

- `LegacyLowering.swift`: `paddedAndSized` sums `Style.padding` **and
  `Style.border`** into the native padding's insets and records a padded `Text`'s
  leaf in `Frame.lowering.textLeaves`; `legacyLeafDiagnostics` loses `padding.floor`,
  `padding.text` and `border` and gains `border.percent`; `LegacyItemPlan` gains
  `marginInsets`; `planLegacyItems` plans a px/rem margin as native padding for a
  **flex** parent only, reports `margin.percent`, and renames the percentage
  minimum/maximum entries `minSize.percent`/`maxSize.percent`;
  `registerLegacyItems` registers the margin padding **outermost**, unaliased;
  `marginEdge` resolves an edge (`.auto` → 0).
- `LoweringState.swift`: `textLeaves`; `hasMargin` no longer counts `.auto`;
  `hasPercentMargin` is new.
- `Text.swift`: `paintGlyphs` asks `textLeaves` for the glyph node and paints at
  **its** origin and **its** measured width.
- `swift package clean` before the final run (`LoweringState`, which `Frame`
  stores, gained a stored property).

**First full run**: `Test run with 1450 tests in 1 suite failed after 43.610 seconds
with 15 issues` — every lane-4 test green, including the depth pair at its
hand-derived 122 nodes, and only three pins to amend, each named by its red line:
`aLoweredBoxPaddingSitsInsideItsDeclaredSize` (2.2's floor arm, `[]` for
`[box.padding.floor]`), `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf`
(13 issues: the `padding.floor`, `padding.text` and `border` rows, both
`padding.floor` combined rows, and the consumed `minSize`/`margin` arms) and
`stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (3.5's
"padding floor on a container" arm). Amended as `LR-AZ` item 5 records: 2.2's arm
now asserts the divergence (legacy 16×16, lowered 10×10), 2.3 is 46 arms, and 3.5's
arm carries `border.percent`.

**Suite after a `swift package clean`**: `Test run with 1450 tests in 1 suite passed
after 44.741 seconds` (1441 + 9), 0 `error:`, the only `warning:` SwiftPM's
`--build-system native` deprecation notice. Goldens **97**, `git diff --name-only
cb2e708 -- '*.json'` empty. Guards **71** (73 `canTypecheck` hits less the
declaration in `Typecheck.swift` and the comment in `UnitSafetyTests`); none added.
The exit test (2.15) re-ran **unchanged** and passed.

### Mutations

`scratchpad/s2l4/mut/run.py` (lanes 1–2's runner, new table): committed tree, file
copied aside, the target asserted unique, applied, `swift build --build-system
native --build-tests`, full unfiltered `swift test --build-system native
--no-parallel --skip-build`, restored from the copy, `git status --short` read after
each — **empty after all of them**. No build error, no truncated run. M4g was
re-taken on `9a4a130`. Issue counts in parentheses.

| mutation | what | reddened |
|---|---|---|
| **M4a** | the border insets transposed top ↔ left | 4.1 (6) |
| **M4b** | glyphs painted at the element node's origin | 4.2 (2) |
| **M4b′** | glyphs wrapped at the element's (aliased) width | 4.2 (1) |
| **M4c** | the lowered frame given `max(size, padding sum)` | 4.3 (1), 2.2 `aLoweredBoxPaddingSitsInsideItsDeclaredSize` (1) |
| **M4c′** | the size frame aligned `.topLeading` whatever the container | 4.3 (2), `aLoweredContainerPaddingSitsInsideItsDeclaredSize` (5), `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps` (2), `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems` (32), `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` (18), 5.4 (8), 5.5 (3), 1.12 (6), `theStageOneCorpusLowersWith…` (6), `theStageOneCorpusPinsEvery…` (4), 2.15 (8) — 94 |
| **M4d** | the margin padding aliased as the element's rect | 4.4 (12), 4.5 (3) |
| **M4e** | the margin padding registered inside W | 4.4 (6) |
| **M4f** | negative margin insets clamped at 0 at registration | 4.5 (3) |
| **M4g** | `LoweredItem.hasMargin` counting `.auto` | **none on `55621aa`** — the finding: a 0-inset padding is a no-op, so 4.6's consumed arm cannot see it. 4.6 gained an unconsumed arm (`9a4a130`) with a px margin's `margin.unconsumed` as its control; re-run there: 4.6 (1) |
| **M4h** | `margin.percent` lowered as 0 | 4.7 (1), 2.3 `everyStageOneUnlowerableNodeFieldIsReported…` (2) |
| **M4i** | `NativeLayoutRun.maxDepth` 96 | 4.8 trap (2), 2.14 trap (2), stage 1's 5.9 (2) |

**Re-taken from lanes 1–2** — every mutation whose target sits in code lane 4
changed (`paddedAndSized`, `planLegacyItems`, `registerLegacyItems`, `Text.paint`),
all on `9a4a130`:

| mutation | reddened |
|---|---|
| **M1a** W not aliased | 26 tests, 181 issues, including lane 4's 4.1 (3), 4.2 (1) and 4.4 (6) |
| **M1n** the alignment frame aliased | 1.5 (2), 1.6 (1), 1.15 (1), 5.4 (9), 5.5 (3) |
| **M1k** the alias missing from `PaintPass.measuredWidth(of:)` | **none** — see below |
| **M2h** / **M2h′** the fold's minimum / maximum skipped | 2.7 (3) / 2.8 (3) |
| **M2i** a non-greedy maximum lowered onto W | 2.8 (1), 2.3 (2), 1.12 (1) |
| **M2j** a declared size lowered as `frame(maxWidth:maxHeight:)` | 15 tests, 85 issues, including 4.3 (3) and 4.4 (9) |
| **M5c′** the weights check always reporting | 18 tests, 121 issues, including 4.4 (4) and both 4.8 arms |

### M1k is retired, and the attribution is a measurement

Lane 1 opened a window for M1k by adding 1.10's below-a-glyph arm (a stretched
`Text("Wii il")` in a 4-wide column), and lane 2 re-measured M1k reddening 1.10 with
1 issue. On lane 4's tree M1k leaves the **whole suite green**. Attributed by
experiment, not by argument: **lane 3's commit-2 clamp reverted** (`proposalText
Measurement` answering `shaped.widestLine` again) **together with M1k** reddens
`theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap` (1 issue) beside
lane 3's own `aProposalTextBelowItsWidestBrokenLineAnswersTheProposal` (2) and
`aProposalTextBreaksInsideAWordAndAnswersItsWidestLineUpToTheProposal` (2) — 5
issues in 1450, and `git status --short` clean after restoring both files.

The reason is structural: a lowered text leaf can no longer answer wider than the
proposal its item frame gave it, and re-wrapping at a hugged width reproduces the
same greedy breaks. Lane 4's padded path does not reopen the window either — the
glyphs ask for the **leaf's** node, which carries no alias. So the alias inside
`PaintPass.measuredWidth(of:)` is redundant as the code stands; it is kept as
intent and handed to the integrator (`LR-AZ` item 4). `Frame.bounds(of:)`'s alias,
the load-bearing half, stays pinned by M1a.

### Pixels (CN-R)

`gen-lib.py` with lanes 1–2's chrome lines (`Column { CounterPanel() }.width(560)`)
into a `git archive` of `9a4a130`, `DEMO_PIXELS_SMALL=1`, compared with lane 1's
`cb2e708` images (`s2l1/px-base`): **12 of 12 read 0 differing pixels, scene
identical.** Controls on the head images, the stage-1 figures exactly: light vs dark
f0 **1 048 576**; vs modal-light **1 030 498**; vs animation-light **210 027**; f0
vs f3 **0**; preview light vs dark **1 048 576**.

**The two-authority chrome pair** on the same archive: `chrome-legacy` vs
`chrome-proposal` **0 differing pixels, scenes identical**, not blank (216 distinct
pixel values; 308 354 against `small560-default-light`). **Control, M5d** (lowered
stack spacing + 50) applied to the same archive: **8 214 differing pixels, scenes
differ** — lanes 1 and 2's figure.

### Screen lock and captures

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` at 13:06 PDT: `session CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1`, `displayActive main: 0`. **No real-window capture was
taken.** `IOConsoleLocked` was not read (`FR-V`).

### Deferred from lane 4, by name

- **Percentages** — `size`, `padding`, `border`, `margin`, `gap`,
  `minSize`/`maxSize`, a fractional `flexBasis`: reported by name, stage 8's recipe
  and stage 10's deletion (`LR-AI`). 4.7 is the eight-arm inventory.
- **A `Stack`'s or a `.frame` layer's margin**: lowered as absent because the legacy
  engine treats it as absent (`LR-AZ` item 2). If a later stage wants SwiftUI's
  answer there it is a re-spelling, not a lowering.
- **`alignItems.baseline` / `alignSelf.baseline`**: task 11.
- **`hidden()`**: deferred with constraints (`LR-AV`).
- **The redundant alias in `PaintPass.measuredWidth(of:)`**: the integrator's
  choice (`LR-AZ` item 4).
- Justify distribution and reverse directions: lane 5.

### For the integrator

- **New divergences pinned by this lane** (proposal authority only): a `Text`'s
  `Style.padding` pads it where the legacy leaf ignores it (P6, 4.2); a declared size
  below the padding + border sum keeps its frame where CSS floors the border box
  (P1/P7/P8, 4.3); a negative margin past its own box clamps at 0 where CSS's margin
  box goes negative (N1, 4.5).
- **CLAUDE.md's inert table**: the `Style.padding`/`border`/`margin`-on-a-leaf row
  and the legacy `borderWidth(_:)` row both change under the proposal authority —
  `Style.border` is now live there (it lowers into the padding's insets), and a
  `Text`'s padding is live too. The rows stay true of the **legacy** authority until
  stage 6b.
- **Shared files touched**: `LegacyLowering.swift` (the box model), `Text.swift`
  (`paintGlyphs`'s two lines), `LoweringState.swift` (a stored property — `swift
  package clean` after merging). No signature, no public spelling changed.
- **Amended stage-1/2 pins**: 2.2's floor arm, 2.3's every-node table (51 → 46
  arms), 3.5's container arm. Any other branch's test that expects
  `padding.floor`, `padding.text`, a bare `border`, a bare percentage `minSize`
  or a lowered `margin` report must be re-checked after the merge.
- **Retired mutations**: **M1k** (lane 3's clamp closed its window; see above).

---

## Lane 5 — justify distribution and reverse directions (2026-09-21, PDT)

Implementer's record. Commits: `3ec113b` (red), `32f82d4` (implementation and the
two amended pins), and this record's commit (docs, `LR-BA`, the spec's lane-5 rows).
Rulings: `LR-BA`. This is stage 2's last lane.

### Probe re-run before the tests

Stage-2 probe `docs/probes/swiftui-engine-replacement-stage2.swift` (revision 4,
unchanged source), its HOW TO RUN filter: run twice, exit 0, **254 lines**, the two
runs byte-identical (`diff` empty) and identical to the header's OUTPUT block line
for line (leading whitespace ignored); filtered stderr empty. Lane 5 cites J1–J9 and
R1/R2 from this run. Both groups' controls move: J0 centres its three children at
70/90/110 where J1 puts them at 0/90/180; R0 puts `a` at 0 where R1 puts it at 180.
**No new arm was needed.**

### Legacy answers measured before any literal was written (scratch, deleted)

Three rounds of a scratch differential test (`Tests/MetalUITests/ScratchL5Tests.swift`,
deleted; `git status --short` clean before the red commit) dumped both authorities'
rects for every shape in the lane. Round 1 covered the distributions, round 2 the
reverse arms with real gaps (round 1's gap loop never applied one — the arms it
produced were duplicates and were discarded), round 3 5.7's replacement shape.

| shape (children in declaration order) | legacy, measured |
|---|---|
| `spaceBetween` row, three 20×10 at 200, gap 0 **and** gap 10 | 0, 90, 180 in both |
| the `Column` transpose, three 10×20 at 200 | 0, 90, 180 in both |
| `spaceBetween` row, three rigid 20×10 at 50 | gap 0: 0, 20, 40; gap 10: 0, 30, 60 |
| `spaceEvenly` row, three 20×10 at 200 | gap 0: 35, 90, 145; gap 10: 30, 90, 150 |
| `spaceAround` row, three 20×10 at 200 | gap 0: **23, 90, 157** (23.33/156.67 cumulative-edge rounded); gap 10: 20, 90, 160 |
| the `Column` transposes of both | identical offsets |
| `spaceEvenly` / `spaceAround` / `spaceBetween`, three rigid 20s at **40** | **0, 20, 40 in all three** — the design's predicted divergence does not exist |
| `spaceBetween` row with one child at 200 | child at 0 |
| `spaceEvenly` / `spaceAround` row with one child at 200 | child at 90 (centred) |
| `spaceBetween` row, `20.flexGrow(1)` beside a 20, at 200 | a 180 wide at 0, b at 180 |
| `rowReverse` 200, children 20 and 30 long | `nil`/`flexStart` 180, 150 (gap 10: 180, 140); `center` 105, 75 (110, 70); `flexEnd` 30, 0 (40, 0); `spaceBetween` 180, 0 (180, 0) |
| `columnReverse` 200, children 10 and 30 long | `nil`/`flexStart` 190, 160 (gap 10: 190, 150); `center` 110, 80 (115, 75); `flexEnd` 30, 0 (40, 0); `spaceBetween` 190, 0 (190, 0) |
| forward `Row` gap 10 `.flexEnd` at 200, 20 and 30 | 140, 170 — the control the mirroring is read against |
| `rowReverse` 100, two rigid 80s | a at 20, b at −60 (R2 exactly) |
| unsized `Row { 20×10; 20×10 }`, `Column { 10×20; 10×20 }` | 40×10 and 10×40 — spacing 0, and the `gap: 8` controls 48 |
| `Row { rowReverse.flexGrow(1); 40 }` at 300 | inner 260×10 at 0, its children at 240 and 210, the sibling at 260 |
| the same with the inner row `.spaceBetween` | inner's children at 240 and 0; reports `[box.reverse, box.justifyContent.spaceBetween]` |
| 5.7's trio (grower 20/plain 30/`minWidth` 40) in a 300 row | reverse: 70 (230 wide), 40, 0; forward: 0, 230, 260 |

Two of the design's predictions were wrong, both recorded as `LR-BA`:

- **The `space-around`/`space-evenly` overflow is not a divergence.**
  `Alignment.swift`'s `distributeMainAxis` clamps with `max(0, freeSpace)` in all
  three cases, so a negative free space distributes nothing and every distribution
  degrades to `flex-start` — which is what the spacers answer. 5.3 became an
  agreement arm and was renamed.
- **5.7 could not use `alignSelf`.** With `.alignSelf(.flexEnd)` on one child the
  **forward control** disagreed (lane 1's X7 divergence: a greedy alignment frame
  hugs a cross-indefinite row where the legacy line places at its end). Measured in
  round 3, then replaced by the grower / plain / floored trio above, whose forward
  control agrees in every observation.

### Red first (`3ec113b`, on lane 4's lowering `9a4a130`)

`swift build --build-system native --build-tests`: 0 `error:`. `swift test
--build-system native --no-parallel --skip-build`: **`Test run with 1459 tests in 1
suite failed after 48.683 seconds with 145 issues`**, exactly the eight lane-5 tests
that are not characterization:

| test | issues | first red line |
|---|---|---|
| 5.1 `spaceBetweenLowersToSpacersAtTheGap` | 24 | `LoweringDistributionTests.swift:142` `r.unlowerable.isEmpty` (`box.justifyContent.spaceBetween`) |
| 5.2 `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit` | 33 | `:229` `r.unlowerable.isEmpty` |
| 5.3 `spaceAroundAndSpaceEvenlyOverflowFromTheStartOnBothPaths` | 9 | `:302` `r.unlowerable.isEmpty` |
| 5.4 `aSpacerBesideAGrowingChildTakesNothing` | 3 | `:328` `r.unlowerable.isEmpty` |
| 5.5 `aReverseContainerPlacesItsChildrenFromTheMainEnd` | 60 | `:376` `r.unlowerable.isEmpty` (`box.reverse`) |
| 5.6 `aReverseContainerOverflowsTowardItsMainStart` | 6 | `:417` `r.unlowerable.isEmpty` |
| 5.7 `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` | 6 | `:492` `r.unlowerable.isEmpty` |
| 5.9 `aGrownReverseContainerPlacesFromTheMainEndOfItsItemFrame` | 4 | `:585` `r.unlowerable.isEmpty` |

5.8 `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault` is
characterization and passed on arrival, as spec §6 says. **Every forward control
passed** — 5.5's `.flexEnd` row at 140/170 and 5.7's forward trio in all seven
observations — which is what makes the reverse and distributed halves the only thing
the implementation moves.

**5.7's element count was corrected before the red run was banked**: the first
spelling required 8 elements where a `Component` contributes no layout node, so the
harness records 5 (the root, the row and the three boxes). The corrected run is the
one above.

### Implementation (`32f82d4`)

`LegacyLowering.swift` only — no other source file, no signature and no public
spelling changed:

- `arrangeLegacyMainAxis(_:declared:animated:)` returns `(nodes, mainFactor,
  spacing)`: it interleaves the distribution's spacers when the declared main size
  is not `auto` and the declared `justifyContent` is one of the three (dropping the
  stack's spacing to 0), then reverses the whole node list for a reverse direction.
- `distributedLegacyItems` builds the pattern: `spaceBetween` → `Spacer(minLength:
  gap)` between each pair; `spaceEvenly` → `Spacer(minLength: 0)` at both ends and
  between; `spaceAround` → the same with the between-spacers doubled; a non-zero gap
  under either of the last two → a rigid native leaf of that length (0 on the cross
  axis) after the between-spacers.
- `legacyMainFactor` mirrors `justifyContent`'s factor for a reverse direction
  (`flexStart`/`nil` → 1, `flexEnd` → 0, `center` unchanged). It registers nothing,
  so the diagnostics bail-out path can read it (`LR-BA` item 2).
- `legacyContainerDiagnostics` loses its `reverse` row and its
  `justifyContent.space*` block; `lowerLegacyNode`'s flex tail and the file header's
  stage-2 paragraph say what lane 5 lowers.

**First full run**: `Test run with 1459 tests in 1 suite failed after 48.906 seconds
with 15 issues` — every lane-5 test green except one literal of its own, and only
two pins to amend, each named by its red line:

- `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`
  (2): `fourFieldContainer` lost `reverse`. Re-spelled with a percentage main-axis
  gap as its first container row — report `[gap.percent, flexWrap, position, inset]`,
  trap `box.gap.percent`.
- `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (5): its
  `space-*` and reverse arms stopped reporting. Renamed
  `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, the five arms kept
  expecting `[]` (`LR-BA` item 5).
- `aReverseContainerPlacesItsChildrenFromTheMainEnd` (8, all in its **column** arms,
  `disagreeing` empty throughout): the red commit reused the row's offsets for the
  column, whose children are 10 and 30 long rather than 20 and 30. Corrected from
  the round-2 scratch dump (`LR-BA` item 6).

**Suite after the amendments**: `Test run with 1459 tests in 1 suite passed after
48.703 seconds` (1450 + 9), 0 `error:`, the only `warning:` SwiftPM's
`--build-system native` deprecation notice. Goldens **97**, `git diff --name-only
cb2e708 -- '*.json'` empty. Guards **71** (73 `canTypecheck` hits less the
declaration in `Typecheck.swift` and the comment in `UnitSafetyTests`); none added,
so none to mutate. The exit test (2.15) re-ran **unchanged** and passed. No `swift
package clean` was needed: no stored property on a public type changed.

### Mutations

`scratchpad/s2l5/mut/run.py` (lane 4's runner, new table): committed tree, file
copied aside, the target asserted unique, applied, `swift build --build-system
native --build-tests`, full unfiltered `swift test --build-system native
--no-parallel --skip-build`, restored from the copy, `git status --short` read after
each — **empty after all of them**. No build error, no truncated run; every run read
1459 tests. Issue counts in parentheses.

| mutation | what | reddened |
|---|---|---|
| **MJa** | the spacer's minimum 0 whatever the gap | 5.1 (4) |
| **MJb** | `spaceAround`'s between-spacers not doubled | 5.2 (8) |
| **MJc** | the gap as the between-spacer's minimum instead of a rigid leaf (J5), the leaf dropped | 5.2 (8) |
| **MJd** | the end spacers given the platform default minimum (`nil`, 8) instead of 0 | 5.1 (8), **5.3 (6)**, 5.4 (2) |
| **MJe** | each spacer wrapped in a `layoutPriority(0)` node | 5.4 (2) |
| **MJf** | the node order not reversed | 5.5 (40), 5.7 (5), 5.6 (4), 5.9 (2) — 51 |
| **MJg** | the main factor not mirrored | 5.5 (24), 5.6 (4), 5.9 (2) — 30 |
| **MJh** | the reversal applied before the wrappers, so each child takes a sibling's item plan | **5.7 (5) and nothing else** |
| **MJi** | the lowered stack given `spacing: nil` when the gap is 0 | 42 tests, 277 issues, including 5.8 (1), `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren` (12), `aStretchedChildFillsTheLineOnItsCrossAxis` (42), `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems` (36) |

**Re-taken from lanes 1, 2 and 4** — every mutation whose target sits in
`LegacyLowering.swift`, the one file lane 5 changed:

| mutation | reddened |
|---|---|
| **M1a** W not aliased | 29 tests, 195 issues, including lane 5's 5.4 (2), 5.7 (10), 5.9 (2) and the exit test (3) |
| **M1n** the alignment frame aliased | 5 tests, 16 issues (stage 1's 5.4 and 5.5, lane 1's 1.5, 1.6, 1.15) |
| **M2i** a non-greedy maximum lowered onto W | 3 tests, 4 issues |
| **M2j** a declared size lowered as `frame(maxWidth:maxHeight:)` | 18 tests, 103 issues, including lane 5's 5.1 (8), 5.3 (6), 5.6 (4) |
| **M4c′** the size frame aligned `.topLeading` whatever the container | 13 tests, 124 issues, including lane 5's 5.5 (26) and 5.6 (4) |
| **M5c′** the `flexGrow.weights` check always reporting | 21 tests, 140 issues, including lane 5's 5.4 (3), 5.7 (12), 5.9 (4) |

### Pixels (CN-R)

`gen-lib.py … chrome` into a `git archive` of `32f82d4`, `DEMO_PIXELS_SMALL=1`,
compared with lane 1's `cb2e708` images (`s2l1/px-base`): **12 of 12 read 0
differing pixels, scene identical.** Controls on the head images, the stage-1
figures exactly: light vs dark f0 **1 048 576**; vs modal-light **1 030 498**; vs
animation-light **210 027**; f0 vs f3 **0**; preview light vs dark **1 048 576**.

**The two-authority chrome pair** on the same archive: `chrome-legacy` vs
`chrome-proposal` **0 differing pixels, scene same**, not blank (216 distinct pixel
values; 308 354 against `small560-default-light`). **Control, M5d** (lowered stack
spacing + 50) applied to a second archive of the same commit: **8 214 differing
pixels, scenes differ** — lanes 1, 2 and 4's figure exactly.

So neither the spacers nor the reversal reaches a production root's pixels, as this
lane's row predicted: the legacy authority still runs production, and the preview's
proposal roots spell no `Row`/`Column` distribution or reverse direction.

### Screen lock and captures

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` at 17:02 PDT: `session CGSSessionScreenIsLocked = 1`, `displayAsleep
main: 1`, `displayActive main: 0`. **No real-window capture was taken**, the brief's
gate not being met. `IOConsoleLocked` was not read (`FR-V`).

### Deferred from lane 5, by name

- **`space-*` on a container with no declared main size that its parent grows or
  stretches**: still reported at the child's site (`LR-AR`), because the child
  registers its stack before it knows. Stage 8's recipe (declare the size, or
  respell with `Spacer`s).
- **Unequal `flexGrow` weights, percentages, `flexBasis` with a length, `maxSize` on
  a non-greedy axis, `alignItems.baseline`/`alignSelf.baseline`, `hidden()`**:
  unchanged by this lane; owners in spec §9.
- **`Row`/`Column`'s default spacing (divergence 52)**: 5.8 characterizes it;
  closing it is a vocabulary change, stage 8's (`LR-AL`).
- **A negative main-axis gap under a distribution**: no test and no probe arm. The
  lowering would hand `space-between` a negative `Spacer(minLength:)` (which the
  kernel accepts, `SA-J`) and the other two a negative rigid leaf. Nothing in the
  repo spells one.

### For the integrator

- **No new divergence is pinned by this lane.** The one the design predicted
  (`space-around`/`space-evenly` overflow) does not exist between the two
  authorities.
- **A pre-existing legacy-vs-CSS gap, found here and not owned here**: CSS's
  `space-around` and `space-evenly` fall back to `center` when the line overflows;
  `Alignment.swift`'s `distributeMainAxis` clamps its free space at 0, so this
  engine falls back to `flex-start`. No golden encodes it (the corpus has no
  overflowing `space-*` fixture) and WebKit is the oracle for the CSS engine, so it
  is a real disagreement with the oracle that the fixture corpus does not see. It
  belongs to whoever owns the CSS engine's retirement (stage 9) or to a fixture
  added before then; lane 5 records it rather than changing the engine, since
  changing it would move the lowering's agreement in the opposite direction.
- **Renamed test**: `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem`
  → `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`. Any other branch
  citing the old name must be re-pointed.
- **Re-spelled pin**: `fourFieldContainer` (in `LoweringContainerTests.swift`) no
  longer declares `.rowReverse`; a branch that expects `box.reverse` anywhere must
  be re-checked after the merge.
- **Shared file touched**: `LegacyLowering.swift` only, appended (three new
  functions at the end of the `LayoutPass` extension's body, before
  `alignmentFactor`) plus four lines changed in `lowerLegacyNode`'s flex tail and
  eleven removed from `legacyContainerDiagnostics`. No stored property, so no
  `swift package clean` is needed for this lane's half of a merge.
- **Retired mutations**: none. M1k stays retired (lane 4).
