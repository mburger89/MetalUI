# 78 — Proposal controls: controls in SwiftUI stacks, and a `Component` tree's stack (all three lanes landed; one ruling suspended)

Branch `feat/proposal-controls` from `e54c3f6` (master: platform services
merged, PR #48). **Not a plan task**: user request 2026-10-02, an item of the
gpui-gap priority list — the SMK keyboard configurator port's two high gaps,
**MG-1** (controls are not proposal elements, so `HStack { Button("x") {} }`
does not compile) and **MG-15** (a `Component`'s layout record holds its whole
content type; the configurator's debug build overflowed an 8 MB main-thread
stack), written up with reproductions in the port's
`docs/superpowers/2026-10-06-metalui-gaps.md`. Spec
`docs/superpowers/specs/2026-10-06-proposal-controls-design.md` (Status:
IMPLEMENTED, one clause suspended); rulings `PE-A`…`PE-AA` in the new decisions
doc `docs/superpowers/2026-10-06-proposal-controls-decisions.md` (next unused
`PE-AB`); probe `docs/probes/swiftui-controls-in-stacks.swift` (arms `FX0`–`FX3`
controls, `FL0`–`FL21` each control's answer to six proposals, `FM0`/`FM1` a
form, `ST0` the configurator's status bar, `IN0`/`IN1` the frame-reader
instrument check, `SP0`–`SP2` the separating arm between greedy and hugging,
`MD0`–`MD4` modifiers in a stack).

**Numbering.** `git fetch` on 2026-10-06: `origin/master` is still `e54c3f6`,
whose last record is §77, so §78 stands.

**Status: IMPLEMENTED (2026-10-06), except `PE-L` item 4.** Lane 2 (sizing,
MG-15, the stack meter), lane 1 (builder, adapter, modifiers) and lane 3 (demo,
docs, human checks) each landed and were verified `ok: true`. MG-1 is closed:
every control, the legacy `Text`, `Menu`, a selectable `List`, `Box` and a
`Component` compose inside `HStack`/`VStack`/`ZStack`/`Grid`/`GridRow`/
`ProposalScrollView`/custom `ProposalLayout` containers with their own types,
modifiers and behaviour. MG-15 is closed except its **loud warning**: the box
(`PE-J`) and the rule (`PE-K`) landed and the meter (`PE-L` items 1–3) is an
instrument, but the one-time `Window` warning (item 4, spec tests 2.4/2.5, human
check V5) is **suspended** by `PE-T` because four of the repository's own demos
measure above its 512 KiB threshold with the meter as landed. Owner: §9.

| Lane | Owns | State |
|---|---|---|
| 2 — sizing, MG-15, meter (first, `PE-O`) | `PE-D` (three greedy answers), `ComponentLayout`'s heap box (`PE-J`), `StackMeter`, `GreedyControlSizingTests`, `ComponentStackTests` | **landed**, verified `ok: true` at `c3efc97` (2552 tests; five mutations re-run by the verifier, `PE-U` has the lane's own nine) |
| 1 — builder, adapter, modifiers | `ProposalContentBuilder`, `LegacyContent`, `LegacyProposalModifiers`, `Pixels.infinity`, nine flipped guards, `ProposalControlsTests`, `PE-V`, `PE-W` | **landed**, verified `ok: true` at `58bac04` (2578 tests; 25 lane mutations and the review's five, `PE-X`) |
| 3 — demo, docs, human checks | the controls demo's SwiftUI-vocabulary section, divergences 130/131, migration, api-overview, inventory, human checks group V, `PE-Y`, `PE-Z` | **landed**, verified `ok: true` at `9612731` (2579 tests; five verifier mutations, two green and listed in §6) |

## §0 Baseline, design session and critic pass

- **Baseline** at `e54c3f6`: **2546 tests in 3 suites**, 0 goldens, 163 typecheck
  guards, 96 live divergences (next label 130), public census 2421.
- **Carried items** (decisions doc header): `MC-G` (only native registrars mint
  a `ProposalNodeID`) and `MC-H` (the typed builder copies) — `PE-B` keeps both
  and adds one minting site inside `MetalUI`; `LR-T` (under the proposal
  authority every node is native — what makes `LegacyContent` sound); `LR-AQ` and
  `LR-CK`; `LR-FX`/`ID-J` (overlays already take legacy content — the precedent
  deliberately not copied for stacks); `CN-B`/`CN-H`; the test-only
  `LegacyUnderProposal` (the semantics `PE-C` makes public); the Windows 1 MB
  stack rule (record §50).
- **Probe.** `swiftui-controls-in-stacks.swift` ran three times in the design
  session (95 lines byte-identical) and once more in the critic pass
  (byte-identical to the recorded header). Positive control `FX0`
  (`Color.red`), separating arm `SP0`–`SP2` (two greedy controls split a row,
  two hugging ones do not), instrument check `IN0`/`IN1`.
- **Critic pass** (`PE-O`…`PE-S`): the lanes re-cut so sizing runs first
  (`PE-O`: spec §10 called lane 1 and 2 disjoint while `ProposalNodeID.swift`
  was in both, and its merge order contradicted §6.1); the stack meter
  tolerates a sample from another thread (`PE-P`, so
  `everyProductionTreeBuildsOnAOneMegabyteThread` stays green); `List` keeps
  divergence 84 (`PE-Q`, probe `FL14`); style modifiers are written on the
  control, the container form rejected (`PE-R`); tests that compare vocabularies
  also assert literals (`PE-S`, two mutations were unable to redden).

## §1 What landed

- **The mechanism** (`ProposalContentBuilder.swift`, `PE-B`, `PE-C`, `PE-E`): a
  public result builder, `ProposalContentBuilder`, that is `ElementBuilder` plus
  two `buildExpression` overloads — a `ProposalElementGroup` passes through with
  its type and typed path untouched, any other `ElementGroup` (a control, `Text`,
  `Box`, a `Component`) is wrapped in `LegacyContent<E>` (`@_disfavoredOverload`).
  It is the content builder of `HStack`, `VStack`, `ZStack` (every initializer),
  `Grid`, `GridRow`, `ProposalScrollView`, `ProposalLayoutContainer.init` and
  `ProposalLayout.callAsFunction`. `LegacyContent` is identity-transparent (the
  caller's parent and cursor: no index, no level, so `MC-A`/`MC-C`, the seven
  slots and `.id()` outermost are unmoved), layout-transparent and native (the
  typed entry mints `ProposalNodeID`s through the internal initializer —
  `ProposalNodeID.swift`'s header names the second minting site), drops
  presentation placeholders (`LR-CK`), consumes no record (a legacy item field in
  a stack is reported `<site>.<field>.unconsumed` and traps in production,
  `LR-AQ`) and registers nothing — so it adds no arm to
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` or the D2 guard, and
  `Handlers`' members, `HandlerShape` and `HandlerFingerprint` are unchanged.
  Not switched: `ProposalFrame`, `Padding`, `Background`, `FixedSize`,
  `nativeOverlay`, `ForEach`'s builder, `Popover` content (`PE-E`).
- **SwiftUI's sizing** (`PE-D`, lane 2, three measurement lines in
  `TextField.swift`, `Slider.swift`, `TextEditor.swift`): an infinite proposal is
  answered with infinity — `TextField` and `Slider` wide, `TextEditor` on both
  axes (probe `FL3`–`FL6`). A stack serves its least flexible child first, so a
  `Slider` beside a 39-wide `Text` was served first and took half the row (180
  where SwiftUI's is 321, `FM0`). A `nil` proposal keeps the ideal (divergence
  131). **The legacy containers move too**: a `Row { Text; Slider }` is the same
  native stack. The only existing test that moved was `SliderTests`'
  `aSliderIsGreedyOnTheWidthAndSixteenTall` (infinite arm 30 → ∞); the fourteen
  images did not move. Every other control already answered in SwiftUI's class
  (spec §1.3); `Text` is `ProposalText`'s answer (`PE-G`).
- **Proposal-only modifiers on legacy content** (`LegacyProposalModifiers.swift`,
  `PE-F`): `layoutPriority`, `fixedSize(horizontal:vertical:)`/`fixedSize()`,
  `gridCellColumns`, both `gridCellAnchor` overloads, `gridColumnAlignment` and
  `gridCellUnsizedAxes` on `ElementGroup`, each wrapping `LegacyContent(self)`;
  `Pixels.infinity` (`MetalUICore/Units.swift`) so `.frame(maxWidth: .infinity)`
  compiles. `.frame`/`.padding` are the legacy layers and lower onto the same
  kernel. Not offered: `aspectRatio` family on legacy content.
- **A `List` windows inside a `ProposalScrollView`** (`PE-V`, found by test 1.18):
  `ProposalScrollView.requestProposalLayout` now publishes its `ScrollContext`
  (offset and last viewport, from the one `ScrollState` both scrollers share),
  as `ScrollView` does; before it realised every row. `ScrollChrome`'s header
  comment corrected.
- **MG-15: `ComponentLayout` is one heap box** (`Component.swift`, `PE-J`): a
  `final class` holding the content and its layout, mutated in place through
  `withPayload(_:)` by `prepaintGroup`/`paintGroup`; `ComponentLayout` is 8 bytes.
  A shell `Component` switching over twelve pane `Component`s costs **4 512
  bytes** more stack than one pane (it was 507 744). The cost is **+1.00
  allocation / 96 bytes per `Component` per laid-out frame** (2.00 / 152 vs
  1.00 / 56, test 2.6). `EitherGroup`'s records stay direct (an `indirect` saved
  1.6 % on top of the box for two allocations per conditional per frame).
  `ComponentLayout`'s stored properties changed on a public type: `swift package
  clean`.
- **`StackMeter`** (`StackMeter.swift`, `PE-L` items 1–3, `PE-P`): debug-only
  (`_isDebugAssertConfiguration()`), `@MainActor`, internal. `measuring(_:)`
  returns the high-water mark below its entry; samples come from every
  `ElementBuilder` method, both `Component` layout entries and
  `Frame.requestNativeLeaf`; `sample()` counts only inside a scope and on the
  main thread (no isolation assertion, so the one-megabyte test's secondary
  thread is harmless). Nothing warns: item 4 is suspended (§9).
- **The rule** (`PE-K`): a `switch`/`if` over large inline subtrees inside one
  builder still grows with the sum of its branches in a debug build (inline 2 →
  12: 1 300 704 → 4 300 576 bytes) — a compiler property; the supported
  spelling is a branch that holds a large subtree in its own `Component`
  (`docs/migration.md` "Large trees in a debug build", the `Component` doc
  comment). `AnyElement(Box { … })` keeps working; an `ElementGroup` eraser
  (MG-22) is not needed and deferred.
- **Demo** (`ControlsDemo.swift`, `PE-Y`): a "SwiftUI vocabulary" section in the
  controls demo (`METALUI_CONTROLS_DEMO=1`) beside the legacy controls, in its
  own functions (`swiftUIVocabularySection`, the form and the status bar): the
  probe's form `FM0` and the configurator's status bar `ST0`, wired to three
  `@State`s appended after `picked` (every `$state<n>` slot keeps its number);
  the menu picker and stepper share `flavor`/`quantity` with the legacy
  controls. The section is built inside a `Component`'s `content`, so
  `everyProductionTreeBuildsOnAOneMegabyteThread` does not build it. The
  controls demo is not one of the fourteen offscreen images.
- **Documents**: divergences 130 and 131 (`PE-N`; 96 → 98 live, next label 132),
  `docs/migration.md` ("Migrate inside-out" rewritten; the `Text` →
  `ProposalText` row; the PE-D behaviour row; "Large trees in a debug build"; the
  `List`-in-`ProposalScrollView` sentence, this phase), `docs/api-overview.md`,
  human checks group **V**, three inventory families (`proposal-content-builder`,
  `legacy-content`, `pixels-infinity`) and the census (2421 → 2446), rows for the
  `LegacyProposalModifiers` spellings.

## §2 Tests and guards, per file

Suite **2546 → 2579** (+33, guards counted among them); typecheck guards **163 →
166** (+3; 162 → 165 `canTypecheck`-gated declarations, counted by
`git grep "enabled(if: canTypecheck"` at both commits); `Backends/SDL` unmoved.

| File | Tests | Pins |
|---|---|---|
| `MetalUITests/ProposalControlsTests.swift` (new) | 23 | every control's answer to the six proposals inside a proposal container (1.1, with the `List` row, `PE-Q`/`PE-W`); a control's id equals a proposal element's in its position (1.4); the probe's form `FM0` and the status bar `ST0` as literal frames (1.5, 1.6); a legacy item field reported by name (1.7); a presentation takes no slot (1.8); `Text` equals `ProposalText` element by element (1.10); one hitbox and behaviour as in a `Row` (1.11); paint (1.12); accessibility records agree across vocabularies, with literals (1.13); Tab order (1.14); shortcut, help, hover (1.15); a legacy frame animates (1.16); a drag carries its preview (1.17); a selectable `List` in a `ProposalScrollView` windows and selects (1.18) and at a scrolled offset (1.18b); a popover presents (1.19); the proposal-only modifiers (1.20, 1.20b–e); a grid form gives its field column the rest (1.22) |
| `MetalUITests/ProposalControlsCompileGuards.swift` (new) | 3 guards | the builder keeps proposal content's type and adopts legacy content (1.2); a SwiftUI-vocabulary form typechecks from a plain import, with the rejected style-after-wrapper arm (1.3, `PE-R`); `Pixels.infinity` (1.21) |
| `MetalUITests/GreedyControlSizingTests.swift` (new) | 2 | the three greedy controls answer infinity (1.9, ∞ arms and `nil`/finite controls); a legacy `Row` serves its slider last (1.23) |
| `MetalUITests/ComponentStackTests.swift` (new) | 3 | a shell over twelve `Component` panes uses the stack of one pane (2.1, a counted bound on a fixed-stack thread); the meter sees the `content` getter's own frame (2.2); the meter measures only inside a measurement, on the main thread (2.3) |
| `MetalUITests/CloseoutTests.swift` | 1 (env-gated) | `measureComponentBoxAllocations`, `METALUI_COMPONENT_ALLOC_MEASURE=1` — the box's allocation figure (2.6); counts while skipped |
| `MetalUITests/ControlsDemoSwiftUISectionTests.swift` (new) | 1 | the section lays out in diagnostics mode with literal frames, and the whole controls demo renders without a report (3.1) |
| flipped guards (nine, `PE-H`, `PE-W`) | — | `proposalLayoutConstructorsRequireProposalContent`, `proposalOverlayAcceptsProposalContentAndRejectsLegacyContent`, `aProposalContainerAcceptsAScopeOverLegacyContent`, `anIfElseAndASwitchCompileInEveryProposalContainer`, `anIDOnAProposalGroupEntersAProposalContainer`, `theLegacyBackgroundKeepsTheTokenOverloadAndTheProposalSpelling`, `aForEachOfLegacyContentCompilesInsideAProposalStack`, `aGridAcceptsLegacyContent`, `aCustomLayoutContainerAdoptsLegacyContent` — each keeps a separating control on a `ProposalFrame` |
| edited: `SliderTests` (∞ arm), `AccessibilityAuditTests`' `scriptWindow` and `ListSelectionTests`' window test (diagnostics pre-flight, `PE-Z`), `ElementGroupTrapTests` | — | existing arms flipped or extended |

## §3 The suite at the Record phase

`swift package clean`, then `swift build --build-system native --build-tests`
and `swift test --build-system native --no-parallel`, unfiltered, at the Record
phase's tree (HEAD `9612731` plus this phase's one doc-comment edit in
`Component.swift` and the docs): **`Test run with 2579 tests in 3 suites passed`
(2546 + 33)**; the `FR-J no-argument frame: succeeded=true` line present; 0
`error:`; the only `warning:` SwiftPM's `--build-system native` deprecation
notice. Guards **166** (163 + 3). Counts by step: 2546 (`e54c3f6`) → 2552 (lane
2, `c3efc97`) → 2578 (lane 1, `58bac04`; +5 review tests over its first 2573) →
2579 (lane 3, `9612731`). The portable census is **2446** declarations
(`closeout-public-api.sh`, 2421 → 2446; the recorded TSV is current);
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
`Backends/SDL` and the `swift:6.4-noble` container were **not re-run by this
phase** (no lane touched `Backends/SDL`; the root portable targets `MetalUI` and
`MetalUICore` changed, so Linux/Windows CI confirm on push, including
`DemoFrameDeterminismTests`' unedited `Expected.swift`).

## §4 Red runs

Every lane wrote its tests first and committed them red:

- `c54be58` (lane 2): tests 1.9 and 1.23 and `SliderTests`' flipped infinite arm
  fail against `e54c3f6`'s sizing; `4da5a7f` (`PE-D`) turns them green.
- `da3552d` (lane 2): the `StackMeter` instrument and tests 2.1–2.3, 2.6 — the
  tree does not compile without the meter; `6631623` (`PE-J`) lands the box.
  `9596802` then made 2.2 and 2.3 separating: **M2.2 and M2.3b stayed green on
  their first spellings** and were re-spelled (§5).
- `6ea16b6` (lane 1): the eight `PE-H` guards flipped, guards 1.2/1.3/1.21 and
  tests 1.1, 1.4–1.8, 1.10–1.20, 1.22; `ae49352` lands the builder. The first full
  run found a **ninth** flipped guard (`PE-W`).
- `22f8bb0` (lane 3): test 3.1 — `cannot find 'swiftUIVocabularySection' in
  scope`; `e0e547e` lands the section.

## §5 Mutation tables

Each mutation on a committed tree, restored from git or a copy, the **full
unfiltered** native suite, `git status --short` clean after. The rulings hold
the complete lane tables; this section carries the verifiers' own re-runs.

**Lane 2 (`c3efc97`, 2552 tests)** — `PE-U` has the lane's nine rows (M1.9a–c,
M2.1, M2.2, M2.3, M2.3b, M2.7).

| id | mutation | reddened |
|---|---|---|
| M1.9b | `Slider.swift` — the finite filter restored | `aLegacyRowServesItsSliderLast`, `aSliderIsGreedyOnTheWidthAndSixteenTall`, `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` |
| M1.9a | `TextField.swift` — the finite filter restored (`swift package clean` before) | `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` only (see §6) |
| M2.2 | `ElementBuilder.swift` — all seven `StackMeter.sample()` calls removed | `theStackMeterSeesTheContentGettersFrame` |
| M2.7 | `Component.swift` — `withPayload` runs on a copy | `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` **traps** (`AnyElement.swift:177`, "AnyElement.paint before prepaint"), truncating the run at about 1703 passed; the unmutated suite finishes normally — so a trap, not a count |
| M2.1 | `Component.swift` — `Storage` a `struct`, payload inline (`swift package clean` before and after) | `aShellOverTwelveComponentPanesUsesTheStackOfOnePane` |

**Lane 1 (`PE-X`)** — 25 lane mutations (M1.1a…M1.24; every new test and guard
reddened under its named mutation; M1.2 stops the test target compiling —
`LoweringScrollTests.swift`'s `-> ProposalScrollView<Rectangle>` helper — a second,
compile-time pin; M1.4a reddens ten tests, M1.4b twelve, M1.10 twenty-seven) and
the review's five, on `e3d38b3` (2578 tests):

| id | mutation | reddened |
|---|---|---|
| V1 | `fixedSize` forwards `horizontal: vertical, vertical: horizontal` | `fixedSizeOnLegacyContentForwardsEachAxis` |
| V2a | `gridColumnAlignment(.trailing)` whatever it is given | `gridColumnAlignmentOnLegacyContentAlignsItsColumn` |
| V2b | both `gridCellAnchor` spellings pass `.topLeading` | `gridCellAnchorOnLegacyContentPlacesItInItsCell` |
| V2c | `gridCellUnsizedAxes([])` | `gridCellUnsizedAxesOnALegacyControlTakesItsColumnsWidth` |
| V3 | `ProposalScrollView.swift` — the published context's offset 0 | `aListInAScrolledProposalScrollViewWindowsAtItsOffset` |

Three spec claims were refuted by the mutation table and corrected (`PE-X`):
M1.11 does not redden 1.13 (the tree builder keys records by id), M1.22 does not
redden 1.22 (a grid sizes its column itself; M1.4a/M1.4b do), and M1.6 reddens
only through a multi-node adopted expression.

**Lane 3 (`9612731`, 2579 tests)** — verifier's five:

| id | mutation | reddened |
|---|---|---|
| M3.1 | `ControlsDemo.swift` — the section's `TextField` gains `.flexGrow(1)` | `theControlsDemosSwiftUISectionLaysOutWithoutReports`, `theControlsDemoPublishesTheTreeTheVoiceOverScriptReads`, `theVoiceOverScriptQuotesThePublishedTree`, `theControlsDemoPublishesEveryControlsRole` — a summary line, no trap (the first run trapped before `PE-Z`'s pre-flight) |
| M-V2 | `@State var speed = 0.75` → `0.4` | `theControlsDemoPublishesTheTreeTheVoiceOverScriptReads`, `theVoiceOverScriptQuotesThePublishedTree` |
| M-V1 | the section's call removed from `ControlsDemo.content` | **nothing** (§6) |
| M-V4 | the status bar's `maxWidth: .infinity` removed | nothing — equivalent: the bar's `Spacer()` already fills the 400-wide section |
| M-V5 | Apply's action emptied | **nothing** (§6) |

**Guards mutated red once**: the three new guards (1.2, 1.3, 1.21) by M1.2/M1.3/M1.21
(`PE-X`); the nine flipped guards by M1.24.

## §6 Green mutations and pins that prove less than they look

Listed, not fixed, each with an owner (§9):

1. **The section's presence in the controls demo is unpinned** (M-V1): test 3.1
   calls `swiftUIVocabularySection(...)` directly, and its whole-demo arm only
   asks `controlsDemoContent()` for an empty report. Human checks V1–V4 and
   `PE-Y`'s placement (beside the controls, 828 × 456) rest on it.
2. **The section's wiring to demo state is unpinned** (M-V5): Apply clearing the
   name, and the picker/stepper sharing `flavor`/`quantity` with the legacy
   controls, are checked by hand only (V2).
3. **`TextField`'s `PE-D` half-row fix is pinned by the leaf's answer only**
   (M1.9a, M1.1a): `Slider` has `aLegacyRowServesItsSliderLast`; no `Row`/`HStack`
   ordering test puts a long label beside a `TextField`.
4. `theStackMeterMeasuresOnlyInsideAMeasurement`'s cross-thread arm passes an
   `mmap` hint without `MAP_FIXED` and `try #require`s that the mapping landed
   below the main thread's stack; under another address-space layout it fails
   instead of skipping.
5. `PE-J`'s "59 % less" is a leaf-sample figure; with the meter as landed a pane
   is 1 211 584 → 1 010 368 bytes (about 17 %). `ComponentLayout`'s doc comment
   now says both (this phase).
6. The lane-1 edits to `ProposalScrollView.swift`, `ScrollChrome.swift` (`PE-V`)
   and `ProposalLayoutCompileGuards.swift` (`PE-W`) fell outside its listed
   files; both rulings are kept — `PE-V`'s offset half is pinned by V3, the ninth
   guard by M1.24.

## §7 Demo comparison and looks

- **Fourteen offscreen images** (`docs/probes/demo-pixels/compare.sh <scratch>
  e54c3f6 HEAD`): **0 differing pixels and `scene identical` in all fourteen**,
  taken by the lane-2 verifier at `c3efc97` (and by lane 2 at `4da5a7f` and
  `9596802`) and re-taken by the lane-3 verifier at `9612731`, every control
  matching its recorded value. `DemoFrameDeterminismTests`' `Expected.swift` is
  unedited since `e54c3f6` (Linux/Windows CI confirm on push). The section is in
  the controls demo, which is not an offscreen image.
- **The demo**: `METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo` (920 × 560); the
  section starts at (404, 24) beside the controls.
- **The real-window capture was not taken** (an agent cannot judge the look;
  the lock probe was not run by this phase).
- **Owed — `docs/verification/human-checks.md` group V (V1–V5), none performed
  (an agent cannot)**: V1 the form's rows read as `FM0`'s (field and slider fill,
  Apply trailing, toggle and stepper hug, the divider spans, the status bar one
  26-point row); V2 the controls behave as the legacy ones (Apply, toggle,
  slider, stepper, native menu picker moving the left's Flavor; Tab order);
  V3 VoiceOver announces each control as the same control on the left; V4 a
  narrower window gives up width from the greedy controls first (headless at 600:
  165 and 161); **V5 N/A — suspended with `PE-L` item 4**.

## §8 Hazards

- **An unconsumed legacy item field in a proposal container traps in
  production** (`PE-C` item 4, `LR-AQ`). The controls demo now holds the first
  such site, so a window test over it pre-flights in diagnostics mode (`PE-Z`):
  M3.1 first trapped inside a production window and ended the run with no
  summary line. A new demo window test does the same.
- **`ComponentLayout`'s stored properties changed on a public type**: `swift
  package clean` after pulling this branch (CLAUDE.md's `Undefined symbols …
  direct field offset`).
- **`withPayload` mutates in place**: a copy traps `AnyElement.paint before
  prepaint` (M2.7), which truncates the run — read the last lines of a log.
- **`StackMeter.sample()` asserts no isolation** (`PE-P`): the one-megabyte test
  calls builders on a secondary thread.
- **Windows 1 MB stacks**: the demo section is built at layout inside a
  `Component`, not by the tree builder; four production trees (`demoContent`
  837 904, `controlsDemoContent` 826 336, `looksDemoContent` 1 061 408,
  `menusDemoContent` 668 752 bytes, `PE-T`) read above half a Windows thread with
  the meter as landed; whether `looksDemoContent` overflows 1 MiB there is
  **unmeasured**.
- **A new `StyledElement`/legacy site** inside a stack owes nothing new: the
  adapter registers nothing (`PE-C` item 5).

## §9 Deferrals, with owners

| item | reason | owner |
|---|---|---|
| **`PE-L` item 4: the `Window` warning, spec tests 2.4/2.5, human check V5** | the design's 512 KiB threshold was derived from leaf samples; with builder samples four production trees are above it (`PE-T`); a threshold has to be chosen, and a Windows debug run of the looks demo measured | re-take `PE-L` against `PE-T`'s table (the gpui-gap list; instrument and figures landed) |
| the three unpinned demo claims (§6 items 1–3) | found by the verifiers after the lanes closed | the next item that edits `ControlsDemo.swift` or `TextField` sizing (a test finding the section by its field, one pressing Apply, one `Row` ordering a `TextField`) |
| the `mmap` placement arm (§6 item 4) | flake risk under another address-space layout | whoever next edits `ComponentStackTests` |
| `.padding(.horizontal, 16)`/`.padding()` on legacy elements | a separate surface | MG-11 |
| `.help` after `.disabled` | an `EnvironmentScope` has no node | MG-13 |
| `TextField`/`TextEditor` bezel chrome, `.textFieldStyle` | a look, divergence 131 | MG-20 |
| an `ElementGroup` eraser (`AnyElement` over a group) | `PE-K`'s spelling needs none | MG-22 |
| shrinking element values (copy-on-write `Handlers`/`Decoration`/`Style`: a `Text` is 1040 bytes) | the only lever on an inline `switch` | the gpui-gap list (performance), `StackMeter` as the instrument |
| deprecating `ProposalText`/`proposalLayout()` | warnings in every test using them | a later closeout |
| container-level `.buttonStyle`/`.pickerStyle` (environment values) | changes every control's chrome resolution | the gpui-gap list (`PE-R`) |
| `aspectRatio` family on legacy content; below-ideal compression of hugging controls (divergence 130) | no control needs them; kept | on request; none |

## §10 The Record phase's own close

- `git fetch`: `origin/master` unmoved at `e54c3f6`; no merge, no renumbering.
- Clean native build and unfiltered suite: §3. `swift build --build-tests` (default
  build system) 0 `warning:` was measured by every lane verifier; this phase's
  only source change is one doc comment in `Component.swift`.
- Documents updated: `CLAUDE.md`/`AGENTS.md` (the `PE-` prefix, one paragraph,
  the counts bullet, divergences 98 live next 132, human-check groups A–V),
  `docs/record/README.md`, record §03 (looks owed), `README.md`, `docs/migration.md`
  (the `PE-V` sentence), spec Status, the decisions doc (`PE-AA`). `docs/api-overview.md`,
  `docs/divergences.md`, human checks group V and the inventory map and census
  were landed by lane 3 and re-verified here.

## §11 Branch check (adversarial, at `182c3a1`)

- `swift package clean`, native build, unfiltered `--no-parallel` run: **`Test run
  with 2579 tests in 3 suites passed after 150.237 seconds`**, `FR-J no-argument
  frame: succeeded=true`, 0 `error:`, the only native `warning:` SwiftPM's
  deprecation notice; `swift build --build-tests` (default build system) 0
  `warning:`. `cmp CLAUDE.md AGENTS.md` equal. Inventory and undocumented checks
  print nothing. `MetalUILayout` imports only `MetalUICore`, `MetalUIScene` only
  `MetalUIShaderTypes`. `DemoFrameDeterminismTests`' `Expected.swift` unedited.
- Offscreen demo comparison re-taken (`compare.sh <scratch> e54c3f6 HEAD`): all
  fourteen images **0 differing, scene identical**; the controls read their
  documented values (1048576, 1031003, 454895, 0, 1048576, 0, 544, 216).
- `Backends/SDL` on macOS: 24 + 77 (unmoved from record §77). `swift:6.4-noble`
  container (`metalui-portable`): builds, 24 + 74 (unmoved).
- Unchanged and green by name: `theSevenRetentionSlotsAreMutuallyDistinct`,
  `everyNamingSiteStartsAReturningNameFresh`,
  `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder`,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  `everyBackgroundPaintingSiteAnimatesItsColour`,
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`,
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`; no identity, hit-testing,
  animation or focus test file was edited (the edited pre-existing tests are the
  `PE-H` flipped guards, the `PE-Z` pre-flights and `SliderTests`' `PE-D` arm).
- Two mutations of the checker's own, each on the committed tree, restored from a
  copy, full unfiltered suite, `git status --short` clean after:
  - **MA** `ProposalContentBuilder.swift` — `LegacyContent`'s typed entry does
    `cursor += 1` before the content registers (an identity shift by one slot):
    2579 tests, 53 issues, reddening `aButtonInAProposalStackHasOneHitboxAndActsAsInARow`,
    `aDragFromAControlInAProposalStackCarriesAPreview`, `aGridFormGivesItsFieldColumnTheRest`,
    `aLegacyControlTakesTheIDAProposalElementWouldInItsPosition`,
    `aLegacyFrameAnimatesInsideAProposalStack`, `aPresentationInsideAProposalStackTakesNoSlot`,
    `aShortcutHelpAndHoverWorkOnAButtonInAProposalStack`,
    `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt`,
    `fixedSizeOnLegacyContentForwardsEachAxis`, `gridCellAnchorOnLegacyContentPlacesItInItsCell`,
    `gridCellUnsizedAxesOnALegacyControlTakesItsColumnsWidth`,
    `gridColumnAlignmentOnLegacyContentAlignsItsColumn`,
    `tabVisitsControlsInAProposalStackInTreeOrder`,
    `textInAProposalStackLaysOutAsProposalText`,
    `theConfiguratorsStatusBarLaysOutInTheSwiftUIVocabulary`,
    `theControlsDemosSwiftUISectionLaysOutWithoutReports`,
    `theProposalOnlyModifiersReachLegacyContent`.
  - **MB** `LegacyProposalModifiers.swift` — `fixedSize(horizontal:vertical:)`
    on legacy content forwards its axes swapped: 2 issues, reddening
    `fixedSizeOnLegacyContentForwardsEachAxis` alone.
- Doc defect fixed: `CLAUDE.md`/`AGENTS.md` listed `ForEach` among the
  containers that "do not take legacy content"; `PE-E` says its builder stays
  `ElementBuilder` and a `ForEach` of legacy rows is adopted whole (the
  status-bar test's second spelling), so the sentence now says that.
- Unresolved citations are all planned, suspended or conditional spec tests
  (2.4, 2.5 under `PE-T`; 2.7 not added per `PE-U` M2.7) or pre-branch lines.
  Real-window capture not taken; group V stays owed.
