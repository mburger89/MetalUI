# 67 — CLAUDE.md's accumulated counts history, moved verbatim (2026-10-01)

At plan task 15's close the "Counts" bullets of `CLAUDE.md`'s "Build and test"
section — one per branch and merge from the CSS-engine era through task 13, 1191
lines — were moved here unedited, so `CLAUDE.md` keeps its current counts and
its rules only (the `CLAUDE.md` header's own convention, as for record §19).
Like §19 this file is **frozen**: figures, paths, "not yet merged" and "owed"
sentences are as written on the dates they carry, and several describe
machinery since deleted (the CSS engine, the goldens, the two layout
authorities). Current counts are in `CLAUDE.md` and record §66 §7. Citations
were not re-checked.

**§1** is the Counts bullets (below); **§2–§4** (at the end) are the
"Reference tables" bullets (known divergences, declared-but-inert, human
verification) replaced the same day.

## §1 The Counts bullets

- **Counts (2026-09-30, `feat/transactions-animation` merged with `master`
  at `26ecd17`): 1961 tests** (`Test run with 1961 tests in 3 suites passed`,
  after `swift package clean`; the FR-J line present). **1961 = 1959 + 2**:
  plan task 13's figure below plus the IX-AG pins' two
  (`aHiddenElementsPressIsNotRecordedWhereHitTestingIsDisabled`,
  `thePressOnlyRecordKeepsTheLastRegistrationPerID`, record §63 §13).
- **Counts (2026-09-30, `feat/transactions-animation` — plan task 13,
  transactions and animation, from `2de0973`, not yet merged with `master`):
  1959 tests, 0 goldens, 119 typecheck guards**, 0 `error:` on both build
  systems, the one `warning:` SwiftPM's deprecation notice under native (0
  under the default one), taken after `swift package clean` with `swift
  build --build-system native --build-tests` then unfiltered `swift test
  --build-system native --no-parallel` (**one summary line**, `Test run with
  1959 tests in 3 suites passed after 120.416 seconds`, the `FR-J
  no-argument frame: succeeded=true` line present). **1959 = 1880 + 21 + 18 +
  10 + 24 + 6**: lane 1 (transactions, the store, Reduce Motion, the
  platforms — its own fix round of five previously-unpinned clauses
  included) +21, lane 2 (modifier wrappers at their phase) +18 then its fix
  round (clamps, `escapesOpacity`, the lexical fallback, hover/focus widths)
  +10, lane 3 (transitions and the surface) +24 then its fix round (the
  per-primitive rules, a point-to-pixel conversion, two stacked/insertion
  rules) +6; no test retired, one renamed with its answer flipped by ruling
  (`theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate` →
  `thePaintOnlyDecorationFieldsAnimateAndClipSnaps`, `AN-AA`) and one arm's
  answer flipped by ruling (arm (c) of
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  snap → animates, B-7 fixed, `AN-AC`), one mutation-table row corrected with a
  measured figure (row 16: 21 of 24 fields, 52 issues, 15 tests) and two
  literal corrections (`112.5` → `112.0`, `Animation.swift` and two
  `AnimationTests.swift` copies). Guards **119 = 116 + 2 + 1**
  (`TransactionCompileGuards`, lane 1's 1.14/1.15; `TransitionCompileGuards`,
  lane 3's 3.19 — both whole-file `typecheckFile`). No goldens. **New public
  API**: `Transaction`, `withTransaction`, `.transaction(_:)`,
  `.animation(_:value:)`, `Binding.transaction`/`.animation(_:)`,
  `EnvironmentValues.accessibilityReduceMotion` (get-only outside the
  package), `AnyTransition` and `.transition(_:)`. **Every proposal
  `LayoutModifier` now animates its numeric/finite case at its phase**
  (layout for size/inset/opacity/clip-radius/border-width, paint for
  background/border-colour tokens), state in a window-owned `AnimationStore`
  — no `StateTable` entry added, the seven reserved slot names unmoved. **The
  legacy paint-only fields animate too**: `Decoration.opacity` and the three
  borders' widths in the layout helper, the resolved border colour in paint
  on a store track (`$anim-border`, a store key, not an eighth `StateTable`
  slot); `clipsContent` still snaps. **B-7 is fixed**: a caller's modifier on
  a `Component` animates per member through the store. **Divergences 96–99
  added, none retired** (geometry vs input interpolation; what still snaps
  on the proposal path; no default transition; one transaction per build) —
  live count 68 → 72, next label 100. **0 px against `2de0973` in all
  fourteen offscreen images**, scene identical, controls non-zero,
  independently re-taken by this Record phase; `Backends/SDL` 22 + 32 →
  22 + 33 (lane 1's `anSDLWindowReportsNoReduceMotion`); a `swift:6.4-noble` aarch64 container builds with 0
  `error:`/`warning:` and runs **199 + 10 + 22**, unmoved.
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` (`Expected.swift` unedited)
  and `theSevenRetentionSlotsAreMutuallyDistinct` green. **The real-window
  capture stays owed**: the lock probe read locked at every check across
  design, the critic round, all three lanes and the Record phase's close, so
  `capture.sh` was never run; the transitions, Reduce Motion's cross-fade and
  `.scale`'s soft mid-flight glyphs join it. **Plan task 13 is ticked**: every
  clause of its text closes (modifier wrappers at their phase,
  environment-driven Reduce Motion, the documented transition surface, the
  retained layout/paint distinction, timestamps not sleeps), and the
  still-open real-window capture does not gate the tick (`AN-AG`: the plan's
  text asks for no look).
- **Counts (2026-09-30, `test/ix-ag-pins` — plan task 12 part 2's unpinned
  `IX-AG` clauses, from `2de0973`): 1882 tests**, 0 `error:`, the one
  native deprecation `warning:` (0 under the default one), taken the same way
  (`Test run with 1882 tests in 3 suites passed`; the FR-J line present).
  **1882 = 1880 + 2**: `aHiddenElementsPressIsNotRecordedWhereHitTestingIsDisabled`
  (V7) and `thePressOnlyRecordKeepsTheLastRegistrationPerID` (V9);
  `settingAXSelectedOnARowReplacesTheSelection` gains the lead/anchor arm (V4)
  and keeps its windows alive. No guard, no golden. History: record §63 §13.
- **Counts (2026-09-30, `feat/accessibility-bridge` — plan task 12 part 2,
  the accessibility half, from `31d3565`, not yet merged with `master`): 1880
  tests, 0 goldens, 116 typecheck guards**, 0 `error:` on both build systems,
  the one `warning:` SwiftPM's deprecation notice under native (0 under the
  default one), taken after `swift package clean` with `swift build
  --build-system native --build-tests` then unfiltered `swift test
  --build-system native --no-parallel` (**one summary line**, `Test run with
  1880 tests in 3 suites passed after 117.613 seconds`, the `FR-J
  no-argument frame: succeeded=` line present). **1880 = 1837 + 8 + 25 +
  10**: lane 1's 8 (the neutral tree's new fields on both bridges, the two
  modifier-free requests moved here by the critic round — settable AppKit
  selection, the press under `allowsHitTesting(false)`; two tests renamed
  with an inverted answer, two T rows), lane 2's 25 (22 tests + 3 guards —
  every accessibility modifier, the builder's rules, the proposal path's
  emission, dispatch), lane 3's 10 (the audit's own pins, the demo's modal,
  the VoiceOver script — no test retired or renamed). Guards **116 = 113 + 3**
  (`AccessibilityCompileGuards`, all three whole-file `typecheckFile`). No
  goldens (`find Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0).
  **New public API**: `AccessibilityChildBehavior` (`.ignore`/`.combine`/
  `.contain`), `AccessibilityTraits` (eight cases), `accessibilityHidden`/
  `accessibilityHint`/`accessibilityIdentifier`/`accessibilityAddTraits`/
  `accessibilityRemoveTraits`/`accessibilityAction(_:)`/
  `accessibilityAction(named:_:)` on `StyledElement` and, new, on
  `ProposalElementGroup` through `AccessibilityModifier<Content>` (one
  identity level); `Image(_:scale:label:)`. **`AXNode.actions`/`AXActionKind`
  are deprecated** toward the new actions (no in-repo caller, 0-`warning:`
  baseline held). **Divergence 28 retires** (a press is advertised and runs
  under `allowsHitTesting(false)`); **83 retires on the AppKit bridge**
  (`AXSelected`/`AXSelectedRows` replace the selection; AccessKit still
  selects by `Click`); **95 added, kept, owner none** (an isolated-out
  element a client already holds refuses a request, where SwiftUI's still
  presses); **27, 32, 33 amended**; **82 kept, owner the human VoiceOver
  run** — live count 69 → 68, next label 96. **0 px against `31d3565` in all
  fourteen offscreen images**, scene identical, independently re-taken by
  this Record phase; `Backends/SDL` 22 + 27 → 22 + 32 on macOS (no lane
  touches `Backends/SDL` but lane 1's neutral-field arms and lane 3's SDL
  parity test); a `swift:6.4-noble` aarch64 container builds with 0
  `error:`/`warning:` and runs **199 + 10 + 22**, unmoved. `MemoryLayout<AXNode>.size`
  113 → 121, `MemoryLayout<Handlers>.size` 440 → 448 (one pointer each, as
  designed); smallest thread building every production tree stays **624
  KB**; `everyProductionTreeBuildsOnAOneMegabyteThread` green.
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` (`Expected.swift` unedited),
  `theSevenRetentionSlotsAreMutuallyDistinct` and
  `noConformerEmitsAnAXNodeItDidNotDeclare` green. **No test retired; four
  renamed**, each a T row naming its ruling
  (`aPressIsRefusedWhereHitTestingIsDisabled` → `aPressIsRunWhereHitTestingIsDisabled`,
  `anAccessibilityClientSelectsARowByPressingItAndCannotSetSelectedDirectly` →
  `settingAXSelectedOnARowReplacesTheSelection`, and two literal-only T rows —
  `aMetalUITreeTranslatesToAccessKitsVocabulary`'s `rowCount`/`rowIndex`, the
  AppKit role table's `.table` → `.outline`). **The real-window capture's
  default/preview pair was taken, unlocked, mid-task** (`6c961e3`): the lock
  probe read no `CGSSessionScreenIsLocked` line and `displayAsleep main: 0`,
  so `docs/probes/window-capture/capture.sh` ran and read 0 differing for
  both states against `31d3565` — the first unlocked reading since stage 6b;
  the screen was locked again by lane 3's own check and at the Record
  phase's close, so every other state (the pressed/disabled/inactive looks,
  the focus ring, a real key window, gestures by hand, and now every
  accessibility bridge look, the VoiceOver script itself) stays owed. **Plan
  task 12's box stays unticked**: `docs/verification/voiceover-script.md` is
  written, not run — an agent cannot run VoiceOver or claim the validation
  (`IX-AE`); the box is ticked only after a human runs every step and the
  Record phase re-reads the file.
- **Counts (2026-09-29, `feat/interaction` — plan task 12 part 1, the
  interaction half, from `31f2e7a`, not yet merged with `master`): 1837
  tests, 0 goldens, 113 typecheck guards**, 0 `error:` on both build
  systems, the one `warning:` SwiftPM's deprecation notice under native (0
  under the default one), taken after `swift package clean` with `swift
  build --build-system native --build-tests` then unfiltered `swift test
  --build-system native --no-parallel` (**one summary line**, `Test run with
  1837 tests in 3 suites passed`; the `FR-J no-argument frame: succeeded=`
  line present). **1837 = 1773 + 30 + 22 + 12**: lane 1's 30 (23 tests +
  1.24–1.28 + 2 guards, `IX-P`/`IX-Q`), lane 2's 22 (18 tests + 2.16b/2.4b +
  2 guards, `IX-R`), lane 3's 12 (12 new/net-changed rows + `G3.1`, one test
  retired and three renamed with an inverted answer, `IX-S`/`IX-T`). Guards
  **113 = 108 + 2 (lane 1, `GestureCompileGuards`) + 2 (lane 2, `ButtonCompileGuards`'
  G2.1 and `DecorationCompileGuards`'s new G2.2) + 1 (lane 3,
  `FocusStateCompileGuards`)**. No goldens (`find Tests/MetalUILayoutTests
  -name "*.json" | wc -l` reads 0). **New public API**: `Gesture`/
  `TapGesture`/`LongPressGesture`/`DragGesture` and their composition
  (`.gesture`/`.simultaneousGesture`/`.highPriorityGesture`,
  `.exclusively(before:)`/`.simultaneously(with:)`); `ButtonRole`,
  `ButtonStyle`, `.keyboardShortcut` (`KeyEquivalent`, `KeyboardShortcut`);
  `contentShape<S: Shape>(_:)` on every element; `FocusState<Value>`/
  `.focused(_:)`. **Focus now leaves with its identity and does not come
  back** (`IX-I`, a public behaviour change with a migration note — see
  CLAUDE.md "Focus"). **Divergence 94 added** (a click never focuses a
  `.focusable()` view, kept); **43, 41, 80 amended**; **57 pinned, owner
  none**; **81, 21, 22 re-owned, owner none** — live count 68 → 69, next
  label 95. **0 px against `31f2e7a` in all fourteen offscreen images**,
  scene identical, independently re-taken by this Record phase;
  `Backends/SDL` 22 + 26 on macOS on the branch (no lane touches
  `Backends/SDL`), **22 + 27 after merging `master`'s `f633741`** (PR #32's
  `backToBackFramesNeverReleaseAnUnsignaledFence`); a
  `swift:6.4-noble` aarch64 container builds with 0 `error:`/`warning:` and
  runs **199 + 10 + 22**; `Tests/PortableTests` **21 + 6 + 5**. Windows
  stack budget: `MemoryLayout<Handlers>.size` 408 → 440 across the three
  lanes (`gestures`, `keyboardShortcut`, `contentShape`, `focusBinding`),
  smallest thread building every production tree 592 → 624 KB, well inside
  1 MB; `everyProductionTreeBuildsOnAOneMegabyteThread` green.
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` and
  `theSevenRetentionSlotsAreMutuallyDistinct` green; `Expected.swift`
  unedited. **One test retired** (`focusOutlivesARenameAndAnIfUntilItsElementReturns`,
  replaced by 3.1/3.2), **three renamed with an inverted answer**
  (`focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow` → 3.2,
  C2.8 → 3.3, C2.12 → 3.4), **one re-derived, name unchanged**
  (`hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`).
  Lane 3 stopped once mid-implementation on an unnamed test reddening
  (`IX-S`): `IX-I`'s own fix had closed the `if`-route of a pre-existing,
  deliberately-wrong-pinned `$focus` sticky-retention instrument test
  (`aFocusRequestWhileDisabledLeavesNoRetentionSlot`, `EV-F`); continued by
  re-deriving that test onto the one route the fix does not close (a `List`
  row windowed out, `TB-AH`) — a T row naming `IX-I`, its answer unchanged
  in both arms (`IX-T`). **Plan task 12's box stays unticked**: part 2 (the
  accessibility half — settable `AXSelected`/divergence 83,
  `accessibilityElement(children:)`, the `AB-H` press question/divergence
  28, modal isolation, divergence 32, divergence 82, `AB-Q` proposal-path
  accessibility, an `onTap`/image's VoiceOver presence, `AXNode.actions`,
  and the human VoiceOver script itself) is the next run. History: record
  §62.
- **Counts (2026-09-29, `feat/shapes-and-rendering` — plan task 11 part 2
  — merged with `master` at `0714528`, PR #31, `TI-I`/`TI-J`): 1773 tests, 0
  goldens, 108 typecheck guards**, 0 `error:` on both build systems, the one
  `warning:` SwiftPM's deprecation notice under native (0 under the default
  one), taken after `swift package clean` with `swift build --build-system
  native --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1773 tests in 3 suites
  passed after 110.381 seconds`; the FR-J line present). **1773 = 1715 − 1706
  + 1763 + 1**: master's 1715 over the shared base 1706 (the text-page
  line's 9), the branch's 1763, and the merge's own 1
  (`tabPassesOverImagesAndShapesAndStopsAtAFocusableClippedBox`,
  `FocusTraversalTests`: Tab passes over an `Image`, a filled shape and a
  clipped proposal rectangle, skips an unfocusable legacy `clipShape` box and
  stops at a focusable one — red when that box is made `.focusable()`, the
  tab order reading 4). Guards **108** (master added none). No source file
  touched by both sides; the only conflicts were this file and `AGENTS.md`.
  `Expected.swift` unedited; `theDemoFrameMatchesTheValuesRecordedOnMacOS`,
  `everyProductionTreeBuildsOnAOneMegabyteThread` and
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green. **0 px against
  `0714528` in all fourteen offscreen images**, scene identical. `Backends/SDL` 22 + 25 at the merge, whose
  `--no-parallel` run truncated `MetalUISDLTests` (no summary line, exit 0)
  — **fixed after the merge, 22 + 26** (record §61 §9: HIToolbox's wake
  stopped Swift Testing's outermost run loop; `SDLPlatform` now runs
  `NSApp.run()` once so AppKit installs its own signal; guard
  `windowServerTrafficNeverStopsTheMainRunLoop`, macOS-only, so Linux stays
  22 + 24); **then 22 + 27** (record §61 §10: the offscreen renderer
  released an unsignalled fence, an intermittent D3D12 crash; guard
  `backToBackFramesNeverReleaseAnUnsignaledFence`, all platforms, so Linux
  22 + 25); the root suite unmoved at 1773.
  Record §61 (written as §60, renumbered 60→61 at this merge, §61 §8).
- **Counts (2026-09-29, `feat/shapes-and-rendering` — plan task 11, part 2,
  from `ff2ae92`; closes task 11): 1763 tests, 0 goldens, 108 typecheck
  guards**, 0 `error:` on both build systems, the one `warning:` SwiftPM's
  deprecation notice under native (0 under the default one), taken after
  `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1763 tests in 3
  suites passed after 108.877 seconds`; the guards ran — the log carries
  `FR-J no-argument frame: succeeded=`). **1763 = 1706 + 12 + 25 + 15 + 1**:
  lane 1 (the renderer: an ellipse kind on `MUIRect`, an image primitive,
  both on Metal and SDL) +12 (1.1–1.12, `Backends/SDL`'s S1.1/S1.2 outside
  this count), lane 2 (`Shape`, the built-ins, fill/stroke, clipping,
  backgrounds in a shape) +25 (2.1–2.23, G2.1, G2.2, the fix round's
  2.13b/2.15b/2.18b/2.18c), lane 3 (`Image`, `aspectRatio(nil)`, the
  `UnitPoint` grid anchor) +15 (3.1–3.12b, G3.2 — G3.1 renames
  `GridCompileGuards`' G4, adding no test), and the fix round's 3.12c +1. No
  `@Test` was removed; three retained tests re-answer or invert (T rows, one
  per lane: `sceneSideTablesArePlainIntArraysThatKeepCapacityAcrossClear`'s
  side-table count 4 → 6, `theLegacyAndProposalDecorationModifiersDoNotCollide`'s
  `crossed` fixture re-spelled for SwiftUI's proposal `.clipped()`, and guard
  G4 → G3.1 inverted from "a `UnitPoint` anchor does not compile" to "it does,
  and the nine-point spellings still resolve"). Guards **108 = 105 + 0 + 2 +
  1**: `ShapeCompileGuards` (new, G2.1 `anOutsideShapeNeedsOnlyItsGeometry`,
  G2.2 `theRectangleColorInitialiserIsDeprecatedTowardFill`) and
  `ImageCompileGuards` (new, G3.2 `anImageHasNoSystemNameOrAssetInitialiser`).
  No goldens to move (stage 7a). New public API: `Shape` (`ProposalElement,
  Sendable`, `geometry(in:) -> ShapeGeometry`, `sizeThatFits(_:)` defaulted
  and `nonisolated`), `RoundedRectangle`/`Circle`/`Capsule`/`Ellipse`,
  `RoundedCornerStyle`, `ShapeView<S>` (`.fill`/`.stroke`/`.strokeBorder`),
  `Rectangle: Shape` (`.color` now `ColorToken?`, a ruled public break;
  `init(color:)` deprecated toward `.fill(_:)`); `clipShape(_:)`/
  `.clipped()`/`.cornerRadius(_:)` on `ProposalElementGroup`,
  `StyledElement.clipShape<S: Shape & Hashable>`; `background(_:in:)`/
  `background(in:)` on `ElementGroup`; `Image`, `ImageBitmap`,
  `Image.Interpolation`, `aspectRatio(_:contentMode:)`'s optional ratio,
  `scaledToFit()`/`scaledToFill()`, `ContentMode`; `gridCellAnchor(UnitPoint)`
  (`@_disfavoredOverload`); `MetalUIScene`'s `PrimitiveKind.image`,
  `Scene.images`/`.textures`, `ImageTexture`; `PaintPass.fill(…, shape:)`/
  `.drawImage(_:in:filter:)`. **Divergences 90–93 are added, 64 retires**
  (65 → 68 live, next label 94; record §04's 2026-09-29 task-11-part-2
  section, rulings `TE-AD`, `TE-AE`, `TE-AG`, `TE-AJ`, `TE-AL`, `TE-AN`): 90
  (`RoundedCornerStyle.continuous` draws circular — the SDF has no closed
  form for Apple's continuous curve, 196 px at r = 20 in 100×60 — kept,
  owner none, `TE-AG` item 2), 91 (`clipShape(Ellipse())` traps naming the
  divergence — the mask is a rounded rect on every primitive — kept, owner
  none, `TE-AJ` item 4), 92 (two crossing rounded clips still intersect as
  the square box — one mask per primitive — kept, owner none, `TE-AJ` item
  5), 93 (`.interpolation(.high)` draws bilinear, same as `.low`/`.medium` —
  880 px from SwiftUI's own `.high` — kept, owner none, `TE-AL`). **Divergence
  64 retires** (a `gridCellAnchor` took only the nine `ProposalAlignment`
  spellings; the kernel's anchor is now a factor pair, `ProposalAnchor`, and
  a plain `UnitPoint` resolves too, `TE-AN`). **0 px against `ff2ae92` in all
  fourteen offscreen images**, scene identical, independently re-taken by
  this Record phase from a fresh `git archive`; no demo tree calls a new API
  (the preview's `Rectangle(width:height:color:)` keeps its explicit
  colour), so nothing could move. **The real-window capture is still owed**:
  the lock probe read locked at design time, at every lane's own check, at
  the critic round and at this Record phase's close. `Backends/SDL`
  (`PKG_CONFIG_PATH=.accesskit`) **22 + 25** (21 + 23 at `ff2ae92`); a
  `swift:6.4-noble` aarch64 container builds the root package with 0
  `error:`/`warning:` and runs `MetalUILayoutTests` + `MetalUICoreTests` +
  `MetalUICrossPlatformTests` **199 + 22 + 10** (198 before this task; lane
  3's 3.4 is portable); `Tests/PortableTests` **21 + 6 + 5**, unaffected
  (corrected from a stale "20 + 6 + 5" carried since task 11 part 1 — see
  below). `Experiments/SDLGPU`'s `Replay --portable --record` records a
  seventh frame (an ellipse fill, an ellipse band, a stroked circle, a
  capsule, a linear and a nearest image, a half-alpha image, an image under
  a rounded mask); `PortableReplay --expect 7` and `DemoCapture` PASS on
  Metal and on Mesa llvmpipe Vulkan in the container; two positive shader
  controls (the image stage forced to nearest, the ellipse branch dropped)
  each fail frame 6 alone. **Task 11 is ticked**: parts 1 and 2 together
  close every clause of its text — the text half (part 1) and shapes,
  images, fills/strokes, overlays and clipping with every renderer
  constraint stated explicitly (part 2, spec §9). **A part-1 documentation
  slip is corrected here**: `Tests/PortableTests`' figure at task 11 part
  1's close (below, and record §59) read "20 + 6 + 5"; the correct figure
  is **21 + 6 + 5** (`PortableTextDeterminismTests.swift`'s pre-existing 18
  plus `TruncationDeterminismTests.swift`'s 3 = 21, confirmed on macOS and
  in a Linux container) — fixed at every occurrence in record §59 and in
  this file's own task-11-part-1 entry below (`TE-AV`, record §61 §6).
  History: record §61.
- **Counts (2026-09-28, `feat/text-page` — `TI-I`, `TI-J` — merged with
  `master` at `ff2ae92`, plan task 11 part 1): 1715 tests, 0 goldens, 105
  typecheck guards**, 0 `error:` on both build systems, the one `warning:`
  SwiftPM's deprecation notice under native (0 under the default one), taken
  after `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1715 tests in 3 suites
  passed`; the FR-J line present). **1715 = 1706 + 7 + 1 + 1**: master's
  1706, the branch's 7 (`TextEditingTests` +2, `TextEditorTests` +1,
  `FocusTraversalTests` +4), the first merge's 1
  (`tabVisitsTheControlsAndAControlItFocusedTakesItsKeys`, Tab reaching
  master's focusable controls, `TI-J` amended) and the second merge's 1
  (`aPageIsMeasuredInTheEnvironmentsResolvedFont`, a page measured in the
  editor's environment-resolved font, `TE-F` item 2). No guard, no golden;
  `Backends/SDL` 21 + 23. At the first merge (`169d166`) it read 1652 = 1644
  + 7 + 1. Record §60 (written as §53, renumbered 53→59→60).
- **Counts (2026-09-28, `feat/text-semantics` — plan task 11, part 1, from
  `169d166`): 1706 tests, 0 goldens, 105 typecheck guards**, 0 `error:` on
  both build systems, the one `warning:` SwiftPM's deprecation notice under
  native (0 under the default one), taken after `swift package clean` with
  `swift build --build-system native --build-tests` then unfiltered `swift
  test --build-system native --no-parallel` (**one summary line**, `Test run
  with 1706 tests in 3 suites passed after 105.602 seconds`; **twelve** gated
  tests skip — the eleven below plus `measureTruncationDifferences`; the
  guards ran — the log carries `FR-J no-argument frame: succeeded=`).
  **1706 = 1644 + 13 + 21 + 27 + 1**: lane 1 (seam layout options and metrics
  on both text systems) +13 (1.5–1.10, 1.7b, `TruncationOracleTests`' four,
  G1.1), lane 2 (font selection on both systems; kernel baselines; the legacy
  `baseline` fields) +21 (1.1–1.4, 2.1–2.13, G1.2, G2.1, the fix round's
  2.11b/2.1c/1.1b), lane 3 (the element surface: `Font`, the text modifiers,
  `TextStyleResolution`) +27 (3.1–3.23, G3.1, G3.2, the fix round's
  3.13b/3.13c/3.17b/3.18b), and the Record phase's own branch check +1
  (**2.1d**, pinning a `GridRow`'s own baseline-alignment factor in
  `nativeGridCellOffsetsY`, which 2.1c's arms never gave a row — `TE-AB`); no
  test retired outright, two renamed with new answers and one fixture
  re-recorded (record §59 §4.6). Guards **105 = 100 + 2 + 3 + 2 + (no branch-check
  guard)**: `TextSystemCompileGuards` (new, `G1.1` lane 1, `G1.2` lane 2's fix
  round), `BaselineCompileGuards` (new, `G2.1`) and `TextCompileGuards` (new,
  `G3.1`/`G3.2`). No goldens to move (stage 7a). New public API: `Font`
  (`.system(size:weight:design:)`, `.system(_:design:weight:)`, the eleven
  text-style statics, `.custom`, `.weight(_:)`, `.italic()`), `Font.Weight`,
  `Font.Design`, `Font.TextStyle`, `TextAlignment`, `Text.TruncationMode`;
  `.font`/`.fontWeight`/`.italic`/`.foregroundStyle`/`.foregroundColor` on
  `ElementGroup` (environment writes) and on `Text`/`ProposalText` (own);
  `.lineLimit`'s five spellings, `.truncationMode`, `.multilineTextAlignment`;
  `VerticalAlignment.firstTextBaseline`/`.lastTextBaseline`; the seam's
  `options:` overloads of `measure`/`placeGlyphs`/`lineRanges` and
  `fontMetrics(_:)`/`resolveFont(_:)` (`MetalUITextSystem`, for an external
  `TextSystem` conformer). **Divergences 86–89 are added, 76 amended a third
  time** (61 → 65 live, next label 90; record §04's 2026-09-28
  task-11-part-1 section, rulings `TE-G`, `TE-I`, `TE-K`, `TE-Z`, `TE-F`):
  86 (MetalUI's line advance is `ceil(ascent + descent + leading)` on both
  text systems, where SwiftUI's TextKit line-fragment height fits no formula
  tried over those three numbers, `TE-G` item 3), 87 (a middle-truncated line
  keeps what `CTLineCreateTruncatedLine(.middle)` keeps, where SwiftUI
  sometimes keeps more at the same width, `TE-I`), 88
  (`GridRow(alignment: .firstTextBaseline/.lastTextBaseline)` traps at
  registration rather than reproducing SwiftUI's row-overflowing answer,
  `TE-K` item 4), 89 (a wrapping text beside a bare `Spacer` in a
  height-limited stack is offered the height less the spacer's minimum,
  where SwiftUI shares the height with the spacer, `TE-Z`) — all kept, owner
  none. Divergence 76 amended a third time, kept, owner none (`TE-F` item 4):
  `controlSize` now reaches every text's default font (`Text`, `ProposalText`,
  `TextField`, `TextEditor`) in addition to `Button`'s chrome from task 10
  part 2; still reaches no other control's chrome. The legacy `baseline`
  fields (`alignItems.baseline`, `alignSelf.baseline`) now lower on a row/
  column or are permanent refusals by name (`owner: nil`) — `TE-L` deletes
  `UnlowerableField.owner`'s `"plan task 11"` branch, so no report anywhere
  in the kernel still names task 11 as an owner. **0 px against `169d166` in
  all fourteen offscreen images**, scene identical, independently re-taken by
  this Record phase — a height census taken before any source change
  predicted this, and the one text leaf it found squeezed
  (`demoMainPane()`'s wrapping paragraph under the **A** state at the demo's
  own 920×560) is not in any of the fourteen (their animation images are
  1024², where it still fits); the paragraph's **cross-platform** demo frame
  (Noto Sans through the portable system at 920×560, `XP-C`) does move —
  named by `TE-Y` item 2, `Expected.swift` re-recorded, Linux and Windows CI
  confirming on push. **The real-window capture is half taken**: the lock
  probe read locked at every check but once, during the lane-3 fix round,
  when `capture.sh` read the default and preview states at 0 differing; the
  paragraph's own look under **A** at 920×560 (four lines where it drew
  five) and `TE-Q`'s drawn `controlSize` font are still owed.
  `Backends/SDL` (`PKG_CONFIG_PATH=Backends/SDL/.accesskit`) 21 + 23,
  unmoved; a `swift:6.4-noble` aarch64 container builds the root package with
  0 `error:`/`warning:` and runs `MetalUILayoutTests` + `MetalUICoreTests` +
  `MetalUICrossPlatformTests` **198 + 22 + 10** (188 before this task; +2
  from 2.1c and this Record phase's own 2.1d, both in `MetalUILayoutTests`);
  `Tests/PortableTests` 21 + 6 + 5 (`TruncationDeterminismTests`, 1.11;
  corrected from a stale "20 + 6 + 5" by task 11 part 2's Record phase,
  `TE-AV`, record §61 §6 — `PortableTextDeterminismTests.swift`'s
  pre-existing 18 plus `TruncationDeterminismTests.swift`'s 3 is 21).
  **Plan task 11's box stays unticked here**: part 2 (shapes, images, fills/
  strokes, overlays, clipping) is the next run. History: record §59.
- **Counts (2026-09-28, `test/covered-slider` — the branch check's MX2
  pin): 1644 tests, 0 goldens, 100 typecheck guards**, taken the same way
  (`Test run with 1644 tests in 3 suites passed`; the FR-J line present).
  **1644 = 1643 + 1**: `aPressOnASliderCoveredByAnOpaqueClickTargetRunsTheClickAndWritesNothing`,
  which MX2 now reddens. History: record §58 §11.
- **Counts (2026-09-28, `feat/controls-and-selection` — plan task 10, part 2,
  from `27b2fcc`): 1643 tests, 0 goldens, 100 typecheck guards**, 0 `error:`
  on both build systems, the one `warning:` SwiftPM's deprecation notice
  under native (0 under the default one), taken after `swift package clean`
  with `swift build --build-system native --build-tests` then unfiltered
  `swift test --build-system native --no-parallel` (**one summary line**,
  `Test run with 1643 tests in 3 suites passed`; the guards ran — the log
  carries `FR-J no-argument frame: succeeded=` and the three new `CONTROLS
  GUARD`/`SLIDER STEPPER GUARD`/`SELECTION GUARD` lines). **1643 = 1556 + 26
  + 6 + 24 + 9 + 22**: lane 1's 26 (`Button`/`Toggle`/`Picker`/`.tag` + 2
  guards) plus its fix round's 6, lane 2's 24 (`Slider`/`Stepper` +
  `ClickDispatch` + 1 guard) plus its fix round's 9, lane 3's 22
  (`List(selection:)`/`ForEach(Binding)`/the controls demo + 1 guard); the
  design's own running total (1628) did not carry the two fix rounds' 15
  (`DD-AG` item 4). Guards **100 = 96 + 2 + 1 + 1**: `ControlsCompileGuards`
  (new, G1.1/G1.2), `SliderStepperCompileGuards` (new, G2.1),
  `SelectionCompileGuards` (new, G3.1) — **the design's baseline was right
  the whole time**: lane 1 flagged "94, not 96" by summing `grep -c
  canTypecheck` over `Tests/MetalUITests` alone, which excludes
  `UnitSafetyTests` (`Tests/MetalUICoreTests`, 3 hits, one a comment); the
  canonical count this file's own "Guards" bullet defines spans both
  targets and reads 96 at `27b2fcc`, 100 now. **No test retired; one
  renamed with its answer changed** (`aClickTargetInsideAScrollViewSwallowsTheWheel`
  → `aClickTargetInsideAScrollViewPassesTheWheelToItsScroller`, its first
  arm 0 → 37 by `DD-Y`, record §58 §2.5 — not counted in the 87; the
  Record phase's write-up read "none renamed", corrected by the branch
  checker, record §58 §11). New public API: `Button(action:label:)`/`Button(_:action:)`,
  `Toggle(isOn:label:)`/`Toggle(_:isOn:)`, `Slider(value:in:step:)`,
  `Stepper` (three initialisers), `Picker(_:selection:content:)`/`.tag(_:)`/
  `PickerStyle`, `List(_:selection:rowHeight:row:)` over `Binding<ID?>` or
  `Binding<Set<ID>>`, `ForEach(_: Binding<C>)`. **Divergence 16 retires**
  (the wheel now passes to the nearest enclosing scroller registered on the
  same layer, so a button, toggle, slider, selectable `List` row or
  single-line `TextField` inside a `ScrollView` no longer blocks it,
  `DD-Y`); **divergences 80–84 are added** (a focused control takes its
  keys whether or not a system full-keyboard-access setting would allow it
  in SwiftUI, unmeasured there, `DD-T`; the accessibility partial fold gives
  `.incrementor`/`.radioGroup` an accessible name where SwiftUI publishes a
  sibling static text beside an unlabelled control, `DD-U`; the automatic
  `Picker` is segmented, not SwiftUI's pop-up menu, `DD-V`; a selection
  client selects a row by pressing it — `AXSelected`/`AXSelectedRows` write
  nothing, where SwiftUI's do, `DD-Z`; a `List` stays virtualized,
  uniform-row and data-driven rather than SwiftUI's greedy self-scrolling
  one, `DD-AB`); **divergence 76 is amended, kept** (`Button`'s chrome now
  reads `controlSize`; every other consumer — `Text`'s default font and
  every other control's metrics — stays plan task 11's, `DD-R` item 4) —
  live count **56 → 61** (one retires, six are added: 80, 81, 82, 83, 84,
  and 85 below). **The Record phase closes the one item the lanes left
  open** (`DD-AG` item 3, `DD-AH` item 4, ruling `DD-AI`): a pre-existing
  bug in `StateTable.peek`/`State.wrappedValue` reads an optional `@State`
  with a non-`nil` initial value as `nil` until its first write (the cast
  of an absent entry to an optional type succeeds as `.some(nil)`, so `??
  initialValue` never runs) — a real, measured divergence from SwiftUI
  (which shows the initial value), not merely an untested corner; **added
  as divergence 85**, kept, owner **plan task 15** (closeout) — a one-line
  fix changes every optional `@State` with a non-`nil` default and wants
  its own ruling, red-first test and migration note, not a docs-phase edit.
  The controls demo works around it with a `Set` (record §58 §3.4b, §4).
  **0 px against `27b2fcc` in all fourteen offscreen images**, scene
  identical, independently re-taken by this Record phase; `Backends/SDL`
  `ReplayFixtureTests` 21 + `MetalUISDLTests` 23 (22 + 1, the five new AX
  roles) on macOS, 21 + 22 in a `swift:6.4-noble` aarch64 container (no
  NSAccessibility test there); the root package builds with 0
  `error:`/`warning:` in a `swift:6.4-noble` container and runs
  `MetalUILayoutTests` + `MetalUICoreTests` + `MetalUICrossPlatformTests`
  **188 + 22 + 10**, unmoved. **Native depth, measured through a real
  `Window`** (`DD-AG` item 5): each control alone in its own root —
  `Button` 6, `Toggle` 5, `Slider` 3, `Stepper` 10, `Picker` segmented 10,
  `Picker` `.radioGroup` 7, `List(selection:)` in a `ScrollView` 13 — and
  the controls demo **15**, all well inside `maxDepth` 72.
  `everyProductionTreeBuildsOnAOneMegabyteThread` (now building the
  controls demo too) and `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
  green. **Task 10 is ticked**: part 1 (`ForEach`, `Binding`,
  `ScrollViewReader`/`scrollTo`, indicators, the `List` origin fix) and
  part 2 (this run) close every clause of the task's text — `List`'s own
  scrolling/greedy answer, non-uniform rows, `List { ForEach }`, two-axis
  scrolling and divergence 54, `scrollPosition(id:)`, and every style
  protocol/gesture-composition item are each re-owned by name rather than
  left implicit (`DD-AB`). **The real-window capture is still owed**,
  unmoved from part 1 and the tasks before it — the screen was locked at
  every lane's own check and at this Record phase's close (lock probe:
  `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`) — and this task
  adds the controls demo's own pointer rules (a slider press/drag, stepper
  halves, the wheel over a button, a field or a selectable row, ⌘/⇧-click
  and arrow selection, the reveal) and VoiceOver on the five new roles to
  it: none of SwiftUI's click/wheel/full-keyboard-access controls ran in
  either lane's probe session (CK0, WH0, the FKA setting), so every pointer
  rule and the "no system setting" reading of `DD-T` are MetalUI's own
  until a human looks. History: record §58.
- **Counts (2026-09-25, `feat/data-and-scrolling` — plan task 10, part 1,
  from `e7bc2e7`): 1556 tests, 0 goldens, 96 typecheck guards**, 0 `error:`
  on both build systems, the one `warning:` SwiftPM's deprecation notice
  under native (0 under the default one), taken after `swift package clean`
  with `swift build --build-system native --build-tests` then unfiltered
  `swift test --build-system native --no-parallel` (**one summary line**,
  `Test run with 1556 tests in 3 suites passed`; the guards ran — the log
  carries `FR-J no-argument frame: succeeded=`). **1556 = 1506 + 18 + 18 +
  14**: lane 1's 18 (`ForEach`'s 15 tests + 2 guards, plus 1.14b, a pin
  `DD-C` item 3 needed beyond the design table), lane 2's 18 (`Binding`'s 15
  tests + 3 guards − 1 guard `EV-N`'s deleted −1 retired test, plus 2 tests
  the verifier round added, 3.6 and 2.3b), lane 3's 14 (the scroll APIs' 11
  tests + 2 guards, plus 3.13b, a fix-round pin for a second, unpinned copy
  of the reader-scope check). Guards **96 = 90 + 2 + 2 (+3 − 1)**:
  `ForEachCompileGuards` 2 (new), `BindingCompileGuards` 3 (new),
  `EnvironmentCompileGuards` 8 → 7 (`EV-N`'s deprecated-alias guard deleted
  with the alias, `DD-D` item 6), `ScrollCompileGuards` 2 (new). **One test
  retired** (`aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`
  — its synthetic harness had no scroller, so it could never see a measured
  origin and would have stayed green asserting the retired wrong answer,
  replaced by 3.1 through a real `ScrollView`), **one renamed**
  (`aReturningAnimatingElementSnapsInsideAnIfAndResumesInsideALoop` →
  `…AndInsideALoop`, its loop arm's value inverted 175 → 200 by ruling, not
  a retirement — `DD-N`). `ForEach<Data, ID, Content>` (SwiftUI's three
  initialisers), a `Binding<Value>` (`@MainActor`, divergence 78), and
  `ScrollViewReader`/`ScrollViewProxy.scrollTo(_:anchor:)`/`UnitPoint` are
  new public API; **the deprecated `typealias Binding = KeyBinding` is
  deleted** (`EV-N`'s announced break — `Binding("cmd-k", A())` no longer
  typechecks). **Divergence 74 retires** (an element a `for` loop or
  `ForEach` stops producing now starts fresh on return, matching SwiftUI);
  **divergence 14 retires** (a `List` inside a scroller now windows against
  its own measured origin, so a header or other sibling above it no longer
  blanks it); **divergence 13 is amended, kept** (a `List` now asks for
  exactly one more frame when its window goes stale, so the frame *after*
  a resize is drawn correct); **divergences 78 and 79 are added** (`Binding`
  is main-actor isolated where SwiftUI's is not; a `ForEach` whose ids
  collide in description produces only the first, where SwiftUI evaluates
  both) — live count **56 → 56** (two retire, two are added; the branch's
  first write-up read 56 → 57, omitting 14's retirement from the arithmetic). **0 px against `e7bc2e7` in all fourteen
  offscreen images**, scene identical, independently re-taken by this Record
  phase; `Backends/SDL` 21 + 22 on macOS, 21 + 21 in a `swift:6.4-noble`
  aarch64 container (unmoved — no source in `Backends/SDL` touched); the
  root package builds with 0 `error:`/`warning:` in a `swift:6.4-noble`
  container too. **Plan task 10's box stays unticked at this point**: part 2
  (common controls and selection, and every item `DD-J` re-owns to it) is
  the next run — superseded above (2026-09-28): part 2 landed and task 10 is
  now ticked (record §58). **A new look is owed**: wheel scrolling under
  `.disabled` (`EV-Q`'s
  item for this task) — SwiftUI's own answer is unmeasured, the screen
  locked at every check across all three lanes and this phase's own close;
  MetalUI's disabled `ScrollView` still scrolls, unchanged. History: record
  §57.
- **Counts (2026-09-25, `feat/environment-control-state` — plan task 9's
  closing half, from `e732d98`): 1506 tests, 0 goldens, 90 typecheck guards**,
  0 `error:` on both build systems, the one `warning:` SwiftPM's deprecation
  notice under native (0 under the default one), taken after `swift package
  clean` with `swift build --build-system native --build-tests` then
  unfiltered `swift test --build-system native --no-parallel` (**one summary
  line**, `Test run with 1506 tests in 3 suites passed after 85.157 seconds`;
  eleven gated tests skipped, unchanged; the guards ran — the log carries
  `FR-J no-argument frame: succeeded=` and both new `EV-AB` guard lines).
  **1506 = 1490 + 16**: lane 1's 8 (`displayScale`, derived `pixelLength`,
  `controlActiveState`, `controlSize`, `EV-AA`…`EV-AC`; E13 extended, E19
  renamed, not added), lane 2's 3 (`AppKitControlStateTests`; three more are
  in `Backends/SDL`, not this count), lane 3's 3 tests + 2 guards (the
  `PlatformWindow` pair and `Window`'s stamp, `EV-AB`;
  `ControlStateCompileGuards`). Guards **90 = 88 + 2**
  (`ControlStateCompileGuards`, new, both whole-file `typecheckFile`
  fixtures). **One retained test renamed, none deleted** (`goldensUnchanged`):
  E19 `aWholeValueWriteCannotResetTheThemeOrThePixelLength` →
  `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` (`EV-AA`). **Divergence
  24 retires** (a scoped `displayScale` write and a `\.self` reset now agree
  with SwiftUI, S3 refuting the old withholding reason); **76 and 77 are
  added** (`controlSize` and layout rounding reach no built-in SwiftUI-shaped
  behaviour, `EV-AC`, `EV-AD`) — live count **55 → 56**. **0 px against
  `e732d98` in all fourteen offscreen images**, scene identical, independently
  re-taken by this Record phase; `Backends/SDL` 21 + 22 on macOS, 21 + 21 in a
  `swift:6.4-noble` aarch64 container. **Plan task 9 is ticked**: both halves
  of the 2026-09-15 progress note (control state, scale) have landed; their
  built-in consumers stay distributed to tasks 10, 11, 12 and 14 (`EV-AE`).
  **The real-window capture is still owed**, and this task adds two more
  looks to it — the probe's key/active mapping arms and a `displayScale`
  change from moving the window between displays — screen locked at every
  check across all three lanes and the Record phase's own close. History:
  record §56.
- **Counts (2026-09-25, `feat/composition-identity-closeout` — the sweep's
  cost, `ID-R` items 8–9): 1490 tests, 0 goldens, 88 typecheck guards**, 0
  `error:` on both build systems, the one `warning:` SwiftPM's deprecation
  notice under native (0 under the default one), taken after `swift package
  clean` the same way (`Test run with 1490 tests in 3 suites passed`).
  **1490 = 1488 + 2**: E3.13 `theResetsScanTheTableOncePerSweep` and C2.13
  `focusOutlivesARenameAndAnIfUntilItsElementReturns`. No guard, no golden;
  0 px against `89a8337` in all fourteen. History: record §55 §10.6.
- **Counts (2026-09-25, `feat/composition-identity-closeout` — plan task 8's
  closeout, from `89a8337`): 1488 tests, 0 goldens, 88 typecheck guards**, 0
  `error:` on both build systems, the one `warning:` SwiftPM's deprecation
  notice under native (0 under the default one), taken after `swift package
  clean` the same way (`Test run with 1488 tests in 3 suites passed`; eleven
  gated tests skipped; the guards ran). **1488 = 1483 + 5**: `ID-R`'s three
  (`anIDThatReturnsToAnEarlierNameStartsFresh`,
  `aNameThatMovesToASiblingsPositionKeepsItsState`,
  `everyNamingSiteStartsAReturningNameFresh`) and `ID-F`'s generation clause
  pinned on both copies (`O1.11`, `O1.12`). No guard, no golden; 0 px against
  `89a8337` in all fourteen offscreen images. History: record §55 §10.
- **Counts (2026-09-25, `feat/composition-identity` — plan task 8, composition
  and identity, from `e3cb3e9`, merged at `89a8337`): 1483 tests, 0
  goldens, 88 typecheck guards**, 0 `error:` on both build systems, the one
  `warning:` SwiftPM's deprecation notice under native (0 under the default
  one, `swift build --build-tests`), taken after `swift package clean` with
  `swift build --build-system native --build-tests` then unfiltered `swift
  test --build-system native --no-parallel` (**one summary line**, `Test run
  with 1483 tests in 3 suites passed`; eleven gated tests skipped, unchanged;
  the guards ran — the log carries `FR-J no-argument frame: succeeded=`).
  **1483 = 1444 + 10 + 12 + 17**: lane 1 (`ID-E`, `ID-F`) +10 (`O1.1`–`O1.8`,
  the review round's `O1.9`–`O1.10`), lane 2 (`ID-B`, `ID-C`, `ID-D`) +12
  (`C2.2`–`C2.12`, `G2.1`, the review round's `C2.13`), lane 3 (`ID-G`,
  `ID-J`) +17 (`E3.1`–`E3.9`, `B3.1`–`B3.3`, `N3.1`, `G3.1`–`G3.3`, the fix
  round's `B3.4`); no test deleted outright, nine retirement rows
  (`goldensUnchanged`: one in lane 1, eight in lane 2). Guards **88 = 84 + 1
  + 3** (`ConditionalIdentityCompileGuards`, new, `G2.1`; then
  `ExplicitIdentityCompileGuards`, new, `G3.1`–`G3.3`). **Fixed to SwiftUI's
  answer**: an `if`/`for` each take one structural slot so a vanishing `if`'s
  trailing sibling keeps its own state (`ID-B`); an evaluated conditional's
  content resets on return, `$focus`/`$ax` exempted (`ID-C`); `if`/`else`/
  `switch` compile in every proposal container (`ID-D`); `@State`/
  `@Environment` bind inside an `AnyElement` (`ID-E`); a handler run by input
  dispatch resolves the occurrence that dispatched it, new
  `StateDispatch.swift` (`ID-F`); `.id(_:)` on every element group via
  `IdentifiedGroup` (`ID-G`); a legacy `.background(alignment:content:)`
  (`ID-J`). **Divergences 18, 19, 48 and 69 retire; 71–74 are added; 56 is
  amended** (its cross-axis alignment sub-row pinned, `N3.1`) — live count
  stays **55** (record §04). **0 px against `e3cb3e9` in all fourteen
  offscreen images**, scene identical, independently re-taken by this Record
  phase; `Backends/SDL` 21 + 19; a `swift:6.4-noble` aarch64 container builds
  with 0 `error:`/`warning:` and runs **188 + 10 + 22**. **The real-window
  capture is still owed** (screen locked at every check across all three
  lanes and the Record phase's own close, unrelated to stage 6b's own
  still-open real-window debt). History: record §55 (§1–§4 design audit
  table and divergence plan, §5 lane 1, §6 lane 2, §7 lane 3, §8 the Record
  phase's independent close).
- **Counts (2026-09-25, `feat/engine-stage-11` — plan task 7 stage 11,
  modifier unification, from `47c0d98`, not yet merged with `master`): 1444
  tests, 0 goldens, 84 typecheck guards**, 0 `error:` on both build systems,
  the one `warning:` SwiftPM's deprecation notice under native (0 under the
  default one, `swift build --build-tests`), taken after `swift package
  clean` with `swift build --build-system native --build-tests` then
  unfiltered `swift test --build-system native --no-parallel` (**one summary
  line**, `Test run with 1444 tests in 3 suites passed`; eleven gated tests
  skipped, unchanged; the guards ran — the log carries `FR-J no-argument
  frame: succeeded=`). **1444 = 1426 + 18**: lane 1 +4 (`N1.1`, `N1.2`,
  `G1.1`, `G1.2`), lane 2 +9 (`N1.3`–`N1.7`, its fix round's `N1.8`–`N1.11`),
  lane 3 +5 (`N2.1`–`N2.4`, its fix round's `N2.5`); no test retired. Guards
  **84 = 82 + 2** (`UnifiedModifiedContentCompileGuards`). `ModifiedElement`/
  `ModifiedContent` are now one flat `ModifiedContent<Content, Modifier>`,
  the second parameter a per-vocabulary witness (`ModifierLayerKind`);
  `ModifiedElement` is a typealias for its legacy arm. The legacy `.overlay`
  is `OverlayModifier<Content, Overlay>` generalized over `ElementGroup`,
  lowered like a frame layer's child. **Divergence 45 retires**
  (`Decoration.escapesOpacity`, one member per slot, fixes the write-order
  bug on both paths — whatever is written after `.opacity` is outside it
  everywhere); `deferred.amended` now lowers exactly as a `.frame` layer
  already did, with no report. **0 px against `47c0d98` in all fourteen
  offscreen images**, scene identical, independently re-taken by this Record
  phase; `Backends/SDL` 21 + 19; `Tests/PortableTests` 18 + 6 + 5; a
  `swift:6.4-noble` aarch64 container builds with 0 `error:`/`warning:` and
  runs **22 + 188 + 10**. **This closes task 7**: no production layout
  request passes through the legacy engine (stage 9), the CSS layout paths
  and dead `Style` fields are gone (stages 9–10), and the two modifier
  vocabularies are unified (this stage) — task 7's own three clauses all hold
  on this branch, and the adversarial branch check (`LR-GG`, record §54
  §11) confirmed every row of the parent spec's §4.1 (1–11 and G) and every
  clause of the stage spec's §9.1 on the branch, re-owning three stage-11
  hand-offs the inventory missed (two `ProposalScrollView` items → plan task
  10, the per-member row's alignment → plan task 8). History: record §54
  (§1–§6 design, skeleton probe, three scratch measurements and critic round;
  §7 lane 1, §8 lane 2, §9 lane 3, §10 the Record phase's independent close,
  §11 the adversarial branch check).
- **Counts (2026-09-24, `feat/engine-stage-10` — plan task 7 stage 10 —
  merged with `master` at `0843866`, PR #29, `TextEditor`): 1426 tests, 0
  goldens, 82 typecheck guards**, 0 `error:` on both build systems, the one
  `warning:` SwiftPM's deprecation notice under native (0 under the default
  one, `swift build --build-tests`), taken after `swift package clean` with
  `swift build --build-system native --build-tests` then unfiltered `swift
  test --build-system native --no-parallel` (**one summary line**, `Test run
  with 1426 tests in 3 suites passed`; eleven gated tests skipped; the guards
  ran — the log carries `FR-J no-argument frame: succeeded=`). **1426 = 1423
  − 1411 + 1414**: master's 1423 (its `TextEditor` 12 over the shared
  stage-9 base 1411) plus stage 10's net +3; no test was added or removed by
  the merge. **Three merge edits beyond the conflict markers**: `TextEditor`
  is a ninth leaf/recording site, so `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s
  `TextEditor` arm is re-spelled from `.position(.relative)` (a spelling
  stage 10 deleted) to `.inset(px(1))`, reporting `textEditor.inset`, and
  `everyReportNamesALiveOwnerOrIsRefusedByName`'s table gains `.textEditor`
  in its leaf sites (**218 → 242** entries: +4 leaf, +11 item, +9
  unconsumed, every one a permanent refusal by name — `owner` decides by
  site `deferred` and the baseline prefixes, never by leaf site, so
  `LayoutAuthority.swift` needed no arm for it); and the text-input demo's
  `TextEditor` `.height(Pixels(160))` (deprecated since stage 8, `LR-ES`, and
  a `warning:` on both build systems on the merged tree) becomes
  `.frame(height: Pixels(160))` — its rects, glyphs and hitboxes read
  identical to the `.height` spelling through a real `Window` (136 lines, the
  editor's 352×160 box among them). `Expected.swift` unedited;
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` and
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green. **0 px against `0843866` in all fourteen offscreen images**, scene
  identical (`docs/probes/demo-pixels/compare.sh`, controls non-zero).
  `Backends/SDL` 21 + 19 on macOS; a `swift:6.4-noble` aarch64 container
  builds with 0 `error:`/`warning:` and runs **22 + 188 + 10** (the closing
  check and the demo frame green off Apple). Record §53's header.
- **Stage 10's counts before the merge (2026-09-24, `feat/engine-stage-10` — plan task 7 stage 10,
  `Style`'s CSS fields and the closing check, from `8095fd9`, stage 9's tip,
  not yet merged with `master`): 1414 tests, 0 goldens, 82 typecheck
  guards**, 0 `error:` on both build systems, the one `warning:` SwiftPM's
  deprecation notice under native (0 under the default one), taken after
  `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1414 tests in 3
  suites passed`; **eleven** gated tests skipped, unchanged; the guards ran —
  the log carries `FR-J no-argument frame: succeeded=`). **1414 = 1411 − 3 +
  2 + 4**: lane 1 (`LR-FS`) retires `D1.1`
  `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs`, `D1.2`
  `aStyleBorderLowersAsInsetsInsideTheDeclaredSize` and `T1.16`'s old name,
  and adds `N1.1` `everyReportNamesALiveOwnerOrIsRefusedByName` and `T1.16`'s
  new name, `allTwentyFourAnimatableFieldsInterpolateAndLeaveInFlightOnSettle`;
  lane 2 (`LR-FT`) adds `N2.1` `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `G1` `aPlainImportCannotWriteAStyleField`, `G2`
  `theDeletedStyleSpellingsDoNotCompile` and `G3`
  `theLayoutKernelDeclaresNoStyle`, removing none. Guards **82 = 79 + 3**
  (`StyleSurfaceCompileGuards`, new). No goldens to move (`find
  Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0, as at `8095fd9`).
  **`Style`'s CSS fields are resolved field by field**: `aspectRatio`,
  `overflow`, `Style.border` (`Box(style:)` its only writer), `flexWrap`,
  `alignContent` and `Position.relative` deleted with the enums
  `FlexWrap`/`AlignContent`/`Overflow` and the modifiers
  `flexWrap(_:)`/`alignContent(_:)`; every surviving stored field (seventeen)
  and `Display`/`JustifyItems` narrowed to `package`; `Style.swift` moved
  from `MetalUILayout` to `MetalUI`. Every inherited `Style`-field report
  becomes a permanent refusal by name (`LR-FO`); the mechanical closing check
  lands: `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` (`dlsym`, macOS
  and Linux, compiled out on Windows), three plain-import guards
  (`StyleSurfaceCompileGuards`, a fix round widening `G1` to pin all
  seventeen narrowed fields rather than one) and a recorded grep (`LR-FP`).
  **0 px against `8095fd9` in all fourteen offscreen images**, scene
  identical, independently re-taken by the Record phase along with the
  suite, guard and golden counts, `Backends/SDL` (21 + 19), `Tests/PortableTests`
  (18 + 6 + 5), a `swift:6.4-noble` container (**22 + 188 + 10**, unmoved
  from stage 9) and the recorded greps (record §53 §6). **The Windows stack
  budget improves, measured**: `MemoryLayout<Style>.size` 226 → 178, the
  smallest thread building every production tree on macOS arm64 debug 528 →
  484 KB. **Not done, owners already assigned**:
  `ModifiedElement`/`ModifiedContent` unification, legacy `.overlay`,
  `.opacity` G4 and `deferred.amended` with `Component.width` over a
  presentation member stay for **stage 11**; divergence 52, the eight
  deprecated sizing modifiers and the `fraction:` spellings, and whether
  `Box`'s public `style:` parameter (inert outside the package
  since narrowing) is deprecated or removed, stay for **plan task 15**
  (closeout). History: record §53 (§1–§3 baseline and critic round, §4 lane
  1, §5 lane 2, §6 the Record phase's independent close).
- **Master's counts before stage 10 met it (2026-09-24, `feat/text-editor` — `TI-H` — merged with `master`
  at `8095fd9`): 1423 tests, 0 goldens, 79 typecheck guards**, 0 `error:`,
  the same one `warning:` under native, taken the same way; **1423 = 1411 +
  12** (`TextEditingTests` +4, `TextEditorTests` +7, `TextSystemSeamTests`
  +1); record §52.
- **Stage 9's counts, merged with `master` (2026-09-24, `feat/engine-stage-9`
  merged with `master` at
  `1895e4a`, PR #30 — the Windows demo-stack fix): 1411 tests, 0 goldens, 79
  typecheck guards**, 0 `error:` on both build systems, the one `warning:`
  SwiftPM's deprecation notice under native (0 under the default one), taken
  after `swift package clean` the same way as the paragraph below (`Test run
  with 1411 tests in 3 suites passed`; eleven gated tests skipped; the FR-J
  line present). **1411 = 1409 + 2**: stage 9's figure below plus
  `DemoStackBudgetTests`' two (`everyProductionTreeBuildsOnAOneMegabyteThread`
  and its 256 KB control, `aThreadTooSmallForTheDemoFailsTheSameHarness`),
  both green over PR #30's per-section `demoContent()` with stage 9's one
  comment re-spelled into it; `theDemoFrameMatchesTheValuesRecordedOnMacOS`
  green with `Expected.swift` unedited; the fourteen offscreen images read 0
  against `1895e4a`; `swift:6.4-noble` reads 192 + 22 + 5; record §51 §9.7.
- **Stage 9's counts (2026-09-24, `feat/engine-stage-9` from `b9a5d7f`,
  plan task 7 stage 9, before it met `master`'s `1895e4a`): 1409 tests, 0 goldens,
  79 typecheck guards**, 0 `error:` on both build systems, the one `warning:`
  SwiftPM's deprecation notice under native (0 under the default one), taken
  after `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1409 tests in 3 suites
  passed`; **eleven** gated tests skipped, unchanged; the guards ran — the log
  carries `FR-J no-argument frame: succeeded=`). No goldens (`find
  Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0, as at `b9a5d7f`).
  **The CSS engine is deleted**: `FlexEngine.swift`, `ResolveFlexibleLengths.swift`,
  `FlexBaseSize.swift`, `FlexLines.swift`, `Alignment.swift`'s flex half,
  `LayoutContext.swift`, `Resolve.swift`'s percentage half, the legacy
  `MeasureFunction`, `textMeasure`, tokenizer min-content, the legacy
  registrars (`LayoutPass.requestNode`/`requestLeaf`, deprecated at stage 6a,
  and the internal `Frame.requestNode`/`requestLeaf`) and the layout authority
  itself (`LayoutAuthority.legacy`, `Frame.layoutAuthority`,
  `computeRootLayout`'s legacy branch, `Frame.legacyRootLayoutCounter`) are
  gone (`git ls-files Sources/MetalUILayout` lists none of the seven engine
  files; `grep -h '^import' Sources/MetalUILayout/*.swift | sort -u` reads
  `import MetalUICore` alone). **Every legacy element keeps working — through
  the lowering, now its only path** (`Box`, `Row`, `Column`, `Stack`,
  `ScrollView`, `List`, legacy `.frame`); `LegacyLowering.swift` keeps its
  name and its comparisons with what "the legacy engine" used to answer, each
  the reason a lowering reads as it does, not a claim that engine runs
  (`LR-FC` item 4). `LayoutAuthority.swift` keeps its name too, holding only
  the lowering's surviving diagnostic vocabulary, `LoweringSite` and
  `UnlowerableField` (`Frame.noteUnlowerable`, `reportsUnlowerableFields`,
  set only by tests) — a legacy site with no proposal lowering still traps
  naming `<site>.<field>`, or reports under diagnostics; there is no more
  authority to choose. **1409 = 1452 − 93 + 50**: three lanes, each red first
  (`docs/probes/stage-9-legacy-reach-instrument.patch`,
  `stage-9-legacy-reference-census.tsv`, `stage-9-site-coverage.txt`), all
  verified `ok`. Lane 1 (`LayoutDifferential.swift` and its 27 users)
  collapsed the two-engine differential harness to one authority and retired
  11 rows → **1441**; lane 2 (the `AuthorityCoverage` registry's other ten
  contributors and every other test naming a deleted symbol) retired 33 →
  **1408** (one more than designed, `LR-FJ` item 1); lane 3 (the deletion
  itself) added N3.1, a presentation's containing block is the window
  whatever surrounds it → **1409**. Guards **79 unmoved**
  (`LayoutAuthorityCompileGuards`' two re-spelled: `aPlainImportCannotChooseTheLayoutAuthority`,
  `aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles`;
  `ErasureCompileGuards`' `layoutPassStyleAccessorsAreNotPublic` re-spelled).
  **0 px against `b9a5d7f` in all fourteen offscreen images**, scene
  identical (`docs/probes/demo-pixels/ZZDemoPixels-stage9.swift`,
  `compare.sh` selecting it by `Fakes.swift`'s declaration rather than a
  comment naming it, `LR-FK` item 3); `DemoFrameDeterminismTests` unedited
  and green. `Backends/SDL` (`PKG_CONFIG_PATH=.accesskit`): 21 + 19 passed,
  its fixtures re-recorded, `PortableReplay`/`DemoCapture` PASS unedited;
  `Tests/PortableTests` 18 + 6 + 5. **Portable CI drops 200 + 22 + 3 → 192 +
  22 + 3** (lane 2's eight `MetalUILayoutTests` retirements). **Divergence 11
  retires** (57 → 56 live): it was legacy-authority only, and the legacy
  authority is gone. **Not done, owners already assigned**: `Style`'s CSS
  fields, `CSSSizing.swift` and every `Style`-field report this stage
  inherited stay for **stage 10**, which also gets
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` in place of the retired
  `noProductionFrameReachesTheLegacyEngine`; `deferred.amended` (`LR-FF`)
  stays for **stage 11**, with `Component.width` over a presentation member;
  `ModifiedElement`/`ModifiedContent` are not unified (stage 11). History:
  record §51 (§1–§4 design and critic round, §5 lane 1, §6 lane 2, §7 lane 3,
  §8 the close, §9 the adversarial branch check, `LR-FL`).
- **Counts (2026-09-24, `fix/windows-demo-stack` from `b9a5d7f`, stage 8
  merged): 1454 tests**, 0 `error:`, 0 `warning:` under the default build
  system, taken the same way as the paragraph below (`Test run with 1454
  tests in 3 suites passed`; the FR-J line present). **1454 = 1452 + 2**:
  `DemoStackBudgetTests`' two (the 1 MB-thread build of every production tree
  and its 256 KB control); record §50 §14.
- **Stage 8's counts (2026-09-24, `feat/engine-stage-8` from `85217e3`,
  plan task 7 stage 8 — merged with `master` at `b9a5d7f`): 1452 tests, 0 goldens,
  79 typecheck guards**, 0 `error:` on both build systems, the one `warning:`
  SwiftPM's deprecation notice under native (0 under the default one), taken
  after `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1452 tests in 3 suites
  passed`; **eleven** gated tests skipped, unchanged by this stage; the guards
  ran — the log carries `FR-J no-argument frame: succeeded=` and `N3.1 sizing
  deprecations: succeeded=true count=8`). No goldens to move (`find
  Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0, as at `85217e3`).
  **1452 = 1445 + 7**, 0 removed: the seven are new tests — lane 1's
  N1.1–N1.6 and lane 3's N3.1 (the `@Test` diff against `85217e3` adds exactly
  these and removes none). Seven existing tests are **T rows**, literals
  re-derived, not additions: `LR-EZ`'s six (the demo's element counts, its
  deepest native level, the whole-demo census, the `…absolute` owning stage)
  and G4's control arm (T3.1); `ModifierTests`' eight sizing rows moved into
  `DeprecatedSizingCases`, a `DeprecatedSpelling` witness (class D), are the
  same test relocated. Guards move **78 → 79**
  (`FrameSizingCompileGuards` 2 → 3: N3.1, one guard whose control arm is a
  second `typecheckFile` call in the same test; `typecheckFile`'s helper count
  38 → 39). **The eight `StyledElement`
  sizing modifiers are deprecated toward `.frame`** (`FR-I`, `LR-ER`; the
  design first said "ten", `Box.swift` declares eight, `LR-EY` item 1): the
  entry census read 1692 warnings (25 in the demo, 1667 in
  `Tests/MetalUITests`, 0 in every other target). Every in-repo caller
  converts in the same change, by class (`LR-EW`, `LR-FB`): **F, converted to
  `.frame`** by the recipe (`LR-ES`) — measured at 129 of the 22 lane-3 files'
  425 sites plus lane 1's 37 (`PresentationWindowTests` 24,
  `FrameSizingTests` 13) and the demo's 25; **K, the `Style` write kept** through
  `Tests/MetalUITests/CSSSizing.swift`'s eight one-line helpers (`.cssWidth(`
  etc., exactly at the census's positions, same closure body, N1.1 pins it) —
  1115 sites in 28 files (lane 2, `LR-EW`) plus 296 of lane 3's 425 (the
  site-coverage check's per-test fallback, `LR-FB`: a test whose sized `Box`
  carries its own handler, focus, key context, action, accessibility node or
  own background paint stays K, or R2's move onto the frame layer would pin
  `ModifiedElement`'s registration instead of the named site's); **D**,
  `ModifierTests`' eight rows into `DeprecatedSizingCases`, a
  `DeprecatedSpelling` witness reached through `oldSpelling(_:)`, which warns
  nothing (`docs/probes/swift-deprecated-witness-silence.sh`, stage 6a's
  precedent); **R (retired) is empty** — no test died for this stage. **A
  framed box can now be an absolute presentation's content** (`LR-EV`: a
  `.frame` layer over at most one node whose declared style is
  `position: .absolute` reports neither `modifierLayer.style` nor
  `modifierLayer.position`/`.inset` inside a `Deferred`, and answers SwiftUI's
  frame bounds on an auto axis where the legacy engine ignores them — a
  proposal-only answer, `LR-CJ`'s precedent), discharging the two `…absolute`
  fields stage 5 left owned here (over several nodes it still reports,
  owner stage 11). The demo is converted by
  `docs/probes/stage-8-demo-recipe.patch`'s recipe (29 insertions, 41
  deletions in `DemoContent.swift`) and reads **0 px against `85217e3` in all
  fourteen images**, scene identical; the demo's hitboxes, accessibility tree
  and hovered-scene comparison (`docs/probes/stage-8-demo-hit-ax-hover.swift`)
  are byte-identical; `DemoFrameDeterminismTests` is unedited and green.
  **Portable CI is untouched** (`MetalUICoreTests`, `MetalUILayoutTests`,
  `MetalUICrossPlatformTests` stay **200 + 22 + 3**; no census site falls in
  `Backends/SDL`, `Tests/PortableTests`, `Tests/MetalUICrossPlatformTests`,
  `Experiments` or any `Sources/` target but the demo's comments). `git grep`
  finds no call of the eight outside a `D`-class witness in any of those; a
  `Backends/SDL` build with the deprecation in draws **0** deprecation
  warnings, and its `PortableReplay`/`DemoCapture` pass unedited. **The
  `Style()` writes in tests (232 lines, 50 files) and lane 2's/lane 3's ≈ 1411
  `css*` sites are re-owned to stage 10** (`LR-ER` item 6, `LR-FB`), which
  deletes the `Style` fields and touches every writer once rather than twice;
  every `Style`-field report this stage inherited (percentages, a non-greedy
  `maxSize`, a length `flexBasis`, a root's auto-axis min/max and margin, a
  floored `space-*`, `…absolute` on a `Style`-written box) **stays reported**
  and — this paragraph predicted — dies with its field at stage 10 (`LR-ER`
  item 4). **Refuted at stage 10**: none of these fields (`size`, `padding`,
  `margin`, `minSize`, `maxSize`, `gap`, `flexBasis`, `justifyContent`) is
  itself deleted — only `aspectRatio`, `overflow`, `border`, `flexWrap`,
  `alignContent` and `Position.relative` are — so every one of these reports
  instead becomes a **permanent refusal by name** (`LR-FO` item 1); `css*`
  and its ≈ 1411 sites stay too, for the same reason (`LR-FO` item 6). Divergence 52
  (`Row`/`Column` default spacing) moves from stage 10 to **plan task 15**
  (closeout), because both stages' exit is "0 px against the prior stage" and
  a public default under every default-gap caller's pixels cannot satisfy
  both (`LR-EY`, amending the design's stage-10 assignment). History: record
  §50 (§7 the design critic round, §8–§9 lane 1, §10 lane 2, §11 lane 3).
- **Stage 7b's counts (2026-09-24, `feat/engine-stage-7b` from `41344e5`,
  plan task 7 stage 7b — merged with `master` at `85217e3`): 1445 tests, 0 goldens,
  78 typecheck guards**, 0 `error:` on both build systems, the one `warning:`
  SwiftPM's deprecation notice under native (0 under the default one), taken after `swift package clean` with
  `swift build --build-system native --build-tests` then unfiltered `swift
  test --build-system native --no-parallel` (**one summary line**, `Test run
  with 1445 tests in 3 suites passed after 86.235 seconds`; **eleven** gated
  tests skipped — the same eleven named below, unchanged by this stage; the
  guards ran — the log carries `FR-J no-argument frame: succeeded=`). No
  goldens to move (`find Tests/MetalUILayoutTests -name "*.json" | wc -l`
  reads 0, as at `41344e5`; none remained since stage 7a). **1445 = 1670 −
  236 + 11**: 236 non-golden CSS-engine tests retired (190 the eighteen
  engine files spec §2.6 left after stage 7a, plus `NativeBoundaryTrapTests`'
  three `computeLayout(` callers; 36 frame/component/container/modifier-chain
  tests; 10 text/style-reader/decoration/matrix/divergence-4 tests) and 11
  new proposal-authority tests added (2 + 4 + 5) — every retired test's row
  in record §49 §4 (245 rows) names either a native test that asserts the
  same fact under the proposal engine, the CSS-only concept it dies with, or
  the new test written first, red-before-green. `grep -rn "computeLayout("
  Tests` is empty (the stage's exit criterion: no test calls the CSS engine's
  entry any more).
  **Divergence 4 retires as a CSS-engine row** (`LR-EH`, `LR-EP`): its two
  D-row tests (`autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot`,
  `anAutoRootWithNoOfferedExtentMeasuresItsContent`) and
  `RootSwitchTests`' `.legacy` arm are gone, but `CS-I`'s behaviour (a
  hugging legacy root fills the offered extent from (0, 0)) stayed exercised,
  unnamed, by the `.legacy` arm of roughly thirty `AuthorityCoverage`-
  parameterised tests until stage 9 deleted the legacy authority and those
  arms with it — at 7b it was not yet "no pin left" (it is, since stage 9).
  `Sources/` diff against `41344e5`
  is comment-only (`git diff 41344e5 -- Sources | grep -E '^[-+]' | grep -vE
  '^(\+\+\+|---)' | grep -vE '^[-+]\s*//'` prints nothing); **no `Sources/`
  line of production behaviour moves**. The fourteen-image offscreen
  comparison (`docs/probes/demo-pixels/compare.sh`) reads 0 differing pixels
  and identical scenes against `41344e5`; `DemoFrameDeterminismTests` is
  unedited and green. **Portable CI drops from 388 to 200** (record §49 §6.1,
  `LR-EM` item 5): **200 = 388 − 189 + 1** — 190 of `MetalUILayoutTests`'
  tests retired with the stage, one of them
  (`freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine`) already
  `#if canImport(Darwin)`-gated on Linux/Windows, plus one replacement
  (N1.2); Linux and Windows CI now run **200 + 22 + 3** for
  `MetalUILayoutTests` + `MetalUICoreTests` + `MetalUICrossPlatformTests`
  (measured in `swift:6.4-noble`). Guards stay **78** (no guard file touched)
  and goldens stay **0**. History: record §49 (its §8 is an independent
  re-check of all three lanes, which corrected the gated count from a
  carried-over "nine" to the measured **eleven** and restated divergence 4's
  retirement as above; its §9, the adversarial branch check, re-read row 190
  as D — `LR-EQ`, the legacy half of `SA-I`'s one flag, unpinned until stage 9
  deleted it along with `computeLayout`).
- **Counts (2026-09-24, `feat/engine-stage-7a` — plan task 7 stage 7a —
  merged with `master` at `6e01d9e`, records §42–§47): 1670 tests, 0 goldens,
  78 typecheck guards**, 0 `error:`, 0 `warning:` on both build systems,
  taken after `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1670 tests in 3 suites
  passed`; eleven gated tests skipped; the guards ran — the log carries `FR-J
  no-argument frame: succeeded=`). **1670 = 1758 − 104 + 16**: `master`'s
  `6e01d9e` (1758, its own figure below) less the 104 tests stage 7a removed
  with the goldens (96 consumers, `GeneratorTests`' 5, `OracleTests`' 3) plus
  its 16 replacements (record §48 §5.3, §6.3). No master-side test consumed a
  golden, so none was lost at the merge. The fourteen offscreen images read 0
  px against `6e01d9e`.
- **Stage 7a's counts before the merge (2026-09-23, `feat/engine-stage-7a` from
  `2cc763d`): 1616 tests, 0 goldens, 78 typecheck guards**, 0 `error:`, 0
  `warning:` on both build systems, taken with `swift build --build-system
  native --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1616 tests in 3 suites
  passed`; nine gated tests skipped; the guards ran — the log carries `FR-J
  no-argument frame: succeeded=`). **1616 = 1704 − 96 − 5 − 3 + 8 + 8**: the
  96 golden-consuming tests, `GeneratorTests`' 5 and `OracleTests`' 3 removed
  with the goldens, and the 8 + 8 replacement tests of `GoldenReplacementFlexTests`
  and `GoldenReplacementStackTests` added (record §48 §5.3, §6.3). **The
  goldens are gone**: `Golden/`, `Fixtures/`, `Oracle/` and the WebKit oracle
  with them, so no test in the repository imports WebKit. The twelve-image
  offscreen comparison (and the two `prod-*` images) read 0 px against
  `2cc763d`.
- **Counts (2026-09-23, `feat/text-undo` — `TI-G`): 1758 tests, 97 goldens,
  78 typecheck guards**, 0 `error:`, 0 `warning:` on both build systems,
  taken the same way; **1758 = 1752 + 6** (`TextEditingTests` +5,
  `TextFieldTests` +1); record §47.
- **Counts (2026-09-23, `feat/system-fonts` — roadmap item 8b): 1752
  tests, 97 goldens, 78 typecheck guards**, 0 `error:`, 0 `warning:` on both
  build systems, taken the same way (`Test run with 1752 tests in 3 suites
  passed`; the guards ran). **1752 = 1746 + 6** (`MetalUISystemFontsTests`,
  which also runs on Linux and Windows); record §46.
- **Counts (2026-09-23, `feat/text-input` — roadmap item 14): 1746 tests,
  97 goldens, 78 typecheck guards**, 0 `error:`, 0 `warning:` on both build
  systems, taken after `swift package clean` the same way (one summary line,
  `Test run with 1746 tests in 3 suites passed`; the guards ran). **1746 = 1712
  + 4 + 30**: the caret-offset lane's 4 (`CaretOffsetOracleTests`) and text
  input's 30 (`TextEditingTests` 10, `TextFieldTests` 13,
  `TextInputPlatformTests` 7); record §45. Goldens and the demo-frame pin
  unmoved. `Backends/SDL`: 21 + 19 on macOS (5 new `SDLTextInputTests`), 21 +
  18 on Linux aarch64.
- **Counts (2026-09-23, `feat/accessibility` — roadmap item 13): the root
  package is untouched — 1712 / 97 / 78 as below**. The work is in the
  separate `Backends/SDL` package: `MetalUISDLTests` 14 (5 new
  `AccessKitTests`) + `ReplayFixtureTests` 21 on macOS; 13 + 21 on Linux
  aarch64, where the NSAccessibility test does not exist (record §44).
- **Counts (2026-09-23, `feat/bidi` — roadmap items 11–12 — merged with
  `master` at `2cc763d`, stage 6b): 1712 tests, 97 goldens, 78 typecheck
  guards**, taken the same way: **1712 = 1708 + 4**, font fallback's
  figure below plus bidi's 4 (record §43, one gated, so twelve gated tests
  skip — font fallback's eleven and `measureBidiDifferences`).
- **Counts (2026-09-23, `feat/font-fallback` — roadmap item 11 — merged
  with `master` at `2cc763d`, stage 6b): 1708 tests, 97 goldens, 78
  typecheck guards**, taken the same way: **1708 = 1704 + 4**, master's
  stage-6b figure below plus font fallback's 4 (record §42, one gated, so
  eleven gated tests skip — master's ten and `measureFallbackDifferences`).
- **Counts (2026-09-23, `feat/engine-stage-6b` — plan task 7 stage 6b —
  merged with `master` at `654a503`, PR #22, roadmap items 9 and 10): 1704
  tests, 97 goldens, 78 typecheck guards**, 0 `error:`, 0 `warning:` on both
  build systems (`swift build --build-tests` under the default one too),
  taken after `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1704 tests in 3 suites
  passed`; the ten gated tests of master's paragraph below skipped; the
  guards ran — the log carries `FR-J no-argument frame: succeeded=`). Goldens
  unmoved against `aef88ce`. **1704 = 1691 + 13**: `master`'s `654a503`
  (1691, its own figure below, taken the same way) plus stage 6b's 13 (the
  branch paragraph next). **One pin moved with the switch, by design**:
  `Tests/MetalUICrossPlatformTests/Expected.swift`, the demo frame
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` pins (`XP-C`), was re-recorded
  on macOS — the same frame under `layoutAuthority: .legacy` still reads the
  old values, and every paired rect and glyph delta is one of stage 6b's
  named causes (record §41 §20); a `swift:6.4-noble` aarch64 container read
  the new values, and Linux x86_64 and Windows CI re-confirm them on push.
  `Backends/SDL`'s `PortableReplay` (6 fixtures, frame 5 the demo) and
  `DemoCapture` passed on macOS at 0 px after re-recording the fixtures.
- **Stage 6b's counts before the merge (2026-09-23, `feat/engine-stage-6b`
  from `aef88ce`): 1701 tests, 97 goldens,
  78 typecheck guards**, 0 `error:`, 0 `warning:` on both build systems
  (`swift build --build-tests` under the default one too), taken after
  `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1701 tests in 3 suites
  passed`; the same nine gated tests skipped as below; the guards ran — the
  log carries `FR-J no-argument frame: succeeded=`). Goldens unmoved against
  `aef88ce` (`git diff --name-only aef88ce HEAD -- 'Tests/**/*.json'` empty).
  **1701 = 1688 + 13**: lane 1 (`hidden()` lowered under the proposal
  authority, the root's px/rem `minSize`/`maxSize` folded, the depth guard
  re-bisected in release for the first time) +9 (`HiddenLoweringTests` 6,
  `RootFieldLoweringTests` 2, and the fix-round addition
  `aHiddenTextIsHiddenUnderTheProposalAuthority`), lane 2 (every other red of
  the flipped default made independent of it, `LR-DG`'s fixture rule) +1
  (`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`), lane
  3 (the switch itself and the exit test) +3 (`RootSwitchTests`' 3.1–3.3);
  record §41. **`Frame.defaultLayoutAuthority` is now `.proposal`** (internal;
  `Frame.init`'s default and `Window.layoutAuthority`'s initial value both
  read it) — **production now runs the proposal engine**, and every
  `.legacy`-in-production sentence elsewhere in this file describes history,
  not the present. Root placement is unchanged (`CN-J`: a native root is
  centred at its own answer); `NativeLayoutRun.maxDepth` moves 88 → 72,
  re-bisected in both debug and release for the first time (`LR-DK`); the
  demo's list row gains one declared height
  (`.height(Pixels(28))`, respelled `.frame(height: Pixels(28))` by stage 8's
  deprecation) so its labels stay centred under the switch, its
  deepest native level moving 29 → 30; the fourteen-image offscreen
  comparison (`docs/probes/demo-pixels/compare.sh`) attributes every pixel
  delta to one of four named causes (a sidebar/panel width SwiftUI answers
  where the CSS engine shrank it, that width's paragraph re-wrap, the modal
  card's height at the lowered column's width, and one-point rounding) — none
  outside. Exit test `noProductionFrameReachesTheLegacyEngine` is green:
  `demoContent()`, `nativeLayoutPreviewContent()` (`MetalUIDemoContent`,
  `LR-S`) and a `List`, each driven through a real `Window`, bump
  `Frame.legacyRootLayoutCounter` zero times. **The real-window capture was
  not taken** — the screen was locked at every check across the stage — and
  is owed to the human, along with the demo-layout human-verification rows
  record §03 re-opens (`LR-DM`; sidebar 196, animation panel 320, modal card
  height, list-row labels now vertically centred). **No golden moved; guards
  unmoved** (78; `LR-DR` item 3: no new guard this stage). History: record
  §41.
- **Master's counts before stage 6b met it (2026-09-23, `feat/demo-cross-platform` — roadmap items 9 and 10
  — merged with `master` at `aef88ce`, stage 6a): 1691 tests, 97 goldens, 78
  typecheck guards**, taken the same way: **1691 = 1688 + 3**, master's
  stage-6a figure below plus `MetalUICrossPlatformTests`' 3 (record §39; one
  a gated recorder, so ten gated tests skip — the nine below and
  `recordDemoFrames`). The paragraph after next is this line's figure before
  the merge (1689 = 1686 + 3).
- **Master's counts before items 9 and 10 (2026-09-23, `feat/engine-stage-6a` —
  plan task 7 stage 6a — merged with `master` at `64c5271`, PRs #11–#20): 1688
  tests, 97 goldens, 78 typecheck guards**, 0 `error:`, 0 `warning:` on both
  build systems (`swift build --build-tests` under the default one too),
  taken after `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1688 tests in 3 suites
  passed`; the same nine gated tests skipped as below; the guards ran — the
  log carries `FR-J no-argument frame: succeeded=`). Goldens unmoved against
  `b3c29b9` (`git diff --name-only b3c29b9 HEAD -- 'Tests/**/*.json'` empty). **1688 = 1686 + 2**: `master`'s `64c5271`
  (1686, measured the same way in a detached worktree — the render seam and
  SDL platform lines add nothing to the root package's suite, so it equals
  the text-seam figure below) plus stage 6a's 2. Stage 6a alone read
  1642 / 97 / 78 on `feat/engine-stage-6a` from `b3c29b9` (**1642 = 1640 + 2**: the
  stage's own exit test
  (`aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne`)
  and its plain-import guard
  (`aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes`));
  record §38. **The public `LayoutPass.requestNode`/`requestLeaf` are now
  deprecated, and every in-repo test caller (67 sites, 35 files) moved off
  them** — onto `requestNativeLeaf`/a `ProposalLayout` where the test is
  authority-independent, or onto the internal, undeprecated
  `Frame.requestNode`/`requestLeaf` (through `pass.frame.`) where the test
  is about a CSS answer or a root-placement question stage 6b has not ruled
  yet. **No `Sources/` line of production behaviour moves** beyond those two
  `@available` attributes and one `owningStage` literal
  (`.customElement` → `"9"`, so a custom element under `.proposal` now
  traps naming stage 9, not stage 6a) — the legacy authority stays the
  default until stage 6b, and the twelve `CN-R` demo images read 0
  differing at every lane. **No golden moved; guards move by exactly +1**
  (`LayoutAuthorityCompileGuards` 1 → 2; the per-file list below is the
  stage-5 paragraph's and still reads 1 there, every other file's count
  stands), and
  `typecheckFile`'s helper count moves with it (37 → 38, "Guards" below).
  The entry measurement (the
  default authority flipped, with the eight test-helper `.legacy` defaults
  also flipped, diagnostics on) classified all 153 reds of that flip; the
  table is recorded as stage 6b's (root placement, ~78 reds) and stage 7b's
  (43 CSS reds) own baseline — record §38 §2–§4, §12.
- **Master's counts before stage 6a (2026-09-23, `feat/engine-stage-5` — plan task 7 stage 5 — merged
  with `master` at `42b9ab4`, the portable text line; then `PT-J`, +5; then line breaking, +6; then
  lines emission, +14; then content sizes, +10; then font resolution, +6; then the text seam, +5; then MetalUI off Apple, +3; then font fallback, +4; then bidi, +4): 1697 tests, 97
  goldens, 77 typecheck guards**, 0 `error:`, 0 `warning:`, taken after
  `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1697 tests in 3 suites
  passed`; twelve skipped: the two gated tests, the FreeType, HarfBuzz,
  portable text, line breaking, lines emission (two), content sizes, font
  fallback and bidi oracles' gated measurement tests, and the demo-frame
  recorder; the guards ran — the log
  carries `FR-J no-argument frame: succeeded=`). Goldens unmoved against
  `e5caefb` (`git diff --name-only e5caefb HEAD -- 'Tests/**/*.json'` is
  empty). **1697 = 1640 + 5 + 6 + 14 + 10 + 6 + 5 + 3 + 4 + 4**: the `PT-J` follow-up's
  `EmitParameterTests` (record §28), line breaking's 6 (the `LB-E` oracle,
  its gated measurement, contract tests; record §30) and lines emission's 14
  (ten metric/placement oracle tests, two of them gated, and four
  `EmitLinesTests`; record §31), content sizes' 10 (record §32) and font
  resolution's 6 (record §33), the text seam's 5 (record §35) and
  `MetalUICrossPlatformTests`' 3 (record §39, one a gated recorder) and
  font fallback's 4 (record §42, one gated) and bidi's 4 (record §43, one
  gated; `Tests/PortableTests` separately runs 18 + 6 + 5 since bidi;
  `Tests/PortableTests` separately runs 16 + 6 + 5); **1640 = 1617 + 15 + 8**: master's `e5caefb` (1617) plus stage 5's
  15 (lane 1, the presentation root, +7; lane 2, the exit suites, +2; lane 3,
  the must-not-move set through real windows, +6; record §29) plus the
  portable text line's 8 (`MetalUIPortableTextTests`; record §28;
  `Tests/PortableTests` separately runs 4 + 6 + 5). Each side was taken the
  same way before the merge: 1632 on `feat/engine-stage-5` alone, 1625 at
  `master` `42b9ab4`. **None of these lines added a golden or a guard**, so
  97 / 77 are unchanged, the per-file list below is unchanged and so is the
  "all 77 guards skip under the default build system" sentence. Master's
  1617 was itself **1580 + 15 + 22**: master `f5e5651` (1595) is
  `integrate/stage-3`'s 1580 plus the HarfBuzz line's 15 (record §26), and
  stage 4 adds 22 (lane 1 +3, lane 2 +9, lane 3 +1, lane 4 +5, lane 5 +4;
  record §27). **`List` is
  public and its stored `box`'s generic argument changed at stage 4, so
  `swift package clean` before re-taking.** Before stage 4 met the HarfBuzz line: 1602 /
  97 / 77 on `feat/engine-stage-4` alone, 1595 / 97 / 77 at master
  `f5e5651`, both from 1580 / 97 / 77 on `integrate/stage-3` (2026-09-22,
  task 7 stage 3 merged with the FreeType rasterizer line), itself **1558 +
  22 = 1550 + 8 + 22** — master `b10594c` (1558) is 1550 plus the FreeType
  line's 8, and stage 3 added 22 (lane 1 +3, lane 2 +8, lane 3 +2, lane 4 +6,
  lane 5 +3); records §24 (FreeType) and §25 (stage 3). Guards per file:
  `PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
  `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `ContainerCompileGuards` 4, `GridCompileGuards` 4,
  `AXNodeTests` 3, `DecorationCompileGuards` 3, `UnitSafetyTests` 2 (3 hits,
  one a comment), `ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards`
  2, `SceneBoundaryCompileGuards` 2, `LayoutAuthorityCompileGuards` 1.
  Earlier: 1558 / 97 / 77 at `b10594c` (the FreeType line, record
  §24, +8 tests and no guard) and 1572 / 97 / 77 on `feat/engine-stage-3`
  (record §25), both from 1550 / 97 / 77 at `57893d0` — itself the merge of
  two lines, 1548 / 97 / 75 on `integrate/stage-2-grids`
  (2026-09-21, task 7 stages 2 and G; records §21, §22, §23) and 1411 / 97 / 73
  on `feat/portable-scene` (2026-09-22, `MetalUIScene`; record §20). Both
  descend from 1409 / 97 / 71, so that merged total is 1409 + 139 + 2. History:
  record §06, §19 "Build and test". A count is stale the moment a test lands;
  re-measure.

# The reference-table bullets (moved 2026-10-01)

Verbatim from `CLAUDE.md` "Reference tables", as of `1b093b8` plus record §65; they were replaced there by short current statements pointing at `docs/divergences.md`, record §05 and `docs/verification/human-checks.md`.

## §2 Known divergences bullet

- **Known divergences** (**72 live**, stable labels; retired labels never
  reused: 3, 4, 5–8, 11, 12, 14, 15, 16, 17, 18, 19, 24, 28, 36, 37, 40, 45,
  48, 59, 64, 69, 74, 83) — record §04 is current (its
  2026-09-21 section retires 59 and adds 60–70, the stage 2 and grids rows,
  its 2026-09-22 one amends 48, 54 and 56 for stage 3 without retiring or
  adding a number, its first 2026-09-23 section likewise amends **13, 14 and
  18** for stage 4 — 13 and 14 survive unchanged with 14's pin now running
  under both authorities, and 18's numbers move to `2n + 6`, crossing at
  **126** rows — and its second 2026-09-23 section (stage 5)
  amends **9, 10 and 11** without retiring or adding a number: 9 survives on
  both authorities, 10 is unchanged and gains SwiftUI evidence (agrees with
  SwiftUI's presentation, disagrees with its overlay), 11 becomes
  legacy-only (retires with the legacy authority at stage 9); and its
  2026-09-23 (stage 6b) section amends **4** without retiring or adding a
  number: `CN-J` is production's root placement (a native root is centred at
  its own answer, unchanged by the switch), and divergence 4 (the legacy
  engine's `CS-I`: a hugging root fills the offered extent from (0, 0))
  becomes **legacy-authority only**, pinned by its own CSS-engine tests,
  retired with the legacy engine at 7b; its 2026-09-23 (stage 7a) section
  amends **55**'s pin, which read "covered by the CSS goldens" — the goldens
  are retired, and the row is pinned by name on both sides without them; and
  its 2026-09-24 (stage 7b) section **retires 4** (58 → 57 live; 4 joins the
  never-reused list): its two CSS-engine tests
  (`autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot`,
  `anAutoRootWithNoOfferedExtentMeasuresItsContent`) and
  `RootSwitchTests`' `.legacy` arm are gone, but `CS-I`'s behaviour (a
  hugging legacy root fills the offered extent from (0, 0)) stays exercised,
  unnamed, by the `.legacy` arm of roughly thirty
  `AuthorityCoverage`-parameterised tests until stage 9 deletes the legacy
  authority and those arms with it — **not** "retired with the legacy
  engine" as the stage-6b section above anticipated; it retires here as a row
  about the CSS engine, its behaviour outliving it unnamed (`LR-EH`, `LR-EP`,
  record §49 §8); the same section also re-pins **9, 48, 52, 53 and 55**
  without retiring or adding a number — each lost the single-authority
  CSS-engine test that used to be its only pin, superseded by an
  already-live differential test that carries both engines' answers in one
  body (record §04's 2026-09-24 section names each pair)); and its
  2026-09-24 (stage 9) section **retires 11** (57 → 56 live; 11 joins the
  never-reused list) — it was legacy-only since stage 5, and the legacy
  engine it describes is gone; its proposal-side fact
  (`[box.position, box.inset]` reported at the consumer for an absolute box
  in a `ScrollView` with no `Deferred`) survives as its own thing, now the
  only answer. That section also closes 4's loose end (the unnamed
  `.legacy`-arm exercise the 7b section flagged is gone with
  `AuthorityCoverage` itself) and re-reads **9, 10, 13, 14, 48, 52, 53, 55 and
  56** without retiring or adding a number: none of the nine is *about* the
  authority split, so the single-authority collapse of their differential
  pins (`LR-FI` item 1) leaves every fact unchanged — three of the nine gain a
  renamed pin (record §04's 2026-09-24 stage-9 section names each);
  **18** is untouched (it was never about the authority);
  §19 "Known divergences" is the frozen 48-row copy. Many are *pinned wrong on
  purpose*; a test named for one reddening may be a fix, not a bug. **Stage 10
  moves no divergence number** — 9, 10 and 54 were re-read for the
  permanent-refusal wording (`UnlowerableField.owner`) and hold unchanged in
  substance (record §04's 2026-09-24 stage-10 section, added by the branch
  check, `LR-FU`, which also names 54's live pin,
  `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem` — the
  table's name retired at 7b). **Stage 11 retires 45** (56 → 55 live; 45
  joins the never-reused list): the write-order bug behind it
  (`.opacity`/`.background`/`.opacity` sharing one `Decoration` with the
  order lost, `OM-H`/`OM-N`) is fixed on both paths by
  `Decoration.escapesOpacity`, so a fill or border written after `.opacity`
  is outside its scope everywhere — SwiftUI's own answer — and the row that
  pinned it wrong on purpose is renamed to pin the fix instead
  (`aBackgroundOrBorderWrittenAfterOpacityEscapesIt`, `LR-FW`, record §04's
  2026-09-25 stage-11 section). Divergence **54** (a lowered `ScrollView`
  takes its cross axis from its parent) is re-owned from "stage 11 / task
  10's" to **plan task 10 alone**, and **56**'s remainder (a `.frame` on a
  multi-member `Component` stays one flex item, `TB-M`) to **plan task 8**
  (`Group` semantics) — neither is a modifier question, so stage 11 disposes
  of neither by closing it (`LR-GA` item 5). **Plan task 8 retires 18, 19, 48
  and 69 and adds 71–74** (55 → 55 live, net zero; record §04's 2026-09-25
  task-8 section): 18 (a `@State` behind a removed `if` is retained) and 69
  (a vanishing grid cell/row hands on its state) both retire under
  `ID-B`/`ID-C`'s one-structural-slot fix and reset-on-return rule, which now
  match SwiftUI (probes V1, V5, V7–V9); 19 (a handler writing one value
  placed twice writes the last-bound occurrence) retires under `ID-F`'s
  `StateDispatch`, which resolves the occurrence actually dispatching; 48 (a
  `Component`'s width overwrote its members' under the CSS engine; framing
  each member is SwiftUI's answer and the proposal path's
  since stage 3) retires by `ID-K`'s bookkeeping alone, no code change.
  **Added**: 71 (a write from *outside* input dispatch — a phase, a raw
  closure — still reaches the last-bound occurrence, `ID-F`'s deliberate
  remainder), 72 (two siblings with the same name/`.id` still share one
  identity, kept, `ID-H`), 73 (`.overlay`/`.background { }` on a zero- or
  multi-member primary traps, naming the count, kept, `ID-I` item 3), 74 (an
  element a `for` loop stops producing keeps its state and gets it back if
  the loop regrows, kept, owner plan task 10's `ForEach`). **56 is amended,
  not retired**: its remainder (above) now also names the row's cross-axis
  alignment as the frame's own where SwiftUI's is the parent's (probe L8,
  kept, pinned by new `N3.1`) — task 8's audit closes the row's "owner: none"
  clause with a pin rather than a fix. **Task 8's closeout adds no row**
  (`ID-R`, record §04's closeout section): a name that returns after a
  detour now starts fresh, SwiftUI's answer, so label 75 stays unused.
  **Plan task 9's closing half retires 24 and adds 76 and 77** (55 → 56 live;
  record §04's 2026-09-25 task-9 section): 24 (no `displayScale`; no scope
  could change `pixelLength`; a `\.self` reset kept it) retires under `EV-AA`
  — `displayScale` is now `public var`, `pixelLength` derives from it, a scope
  write moves both, and a `\.self` reset reads 1 and 1, with S3 showing that a
  write changing only the *number* (not the scale `Frame.fill` draws at) is
  SwiftUI's own behaviour, not the MetalUI-only hazard the old ruling named.
  **Added**: 76 (`controlSize` is carried and scoped but reaches no built-in
  measurement, where SwiftUI's `Text`, `TextField` and `Button` all read it,
  kept, owners plan tasks 11 and 10, `EV-AC`), 77 (layout rounds every stored
  rectangle to whole points, not the `displayScale` pixel grid SwiftUI rounds
  to, found by probe S4, kept, owner plan task 11, `EV-AD`). **`controlActiveState`
  gets no row**: its AppKit/SDL mapping is stated as MetalUI's own choice, not
  a measured SwiftUI fact — the probe's C1–C3/C5 arms never ran (screen
  locked), so there is nothing yet to diverge *from* (`EV-AB`).
  **Plan task 10 part 1 retires 74 and 14, amends 13, and adds 78 and 79** (56 → 56 live, net zero; record
  §04's 2026-09-25 task-10-part-1 section, rulings `DD-A`…`DD-P`): 74 (an
  element a `for` loop stops producing kept its state and got it back if the
  loop regrew) retires under `DD-C` — a loop now notes its slot and the
  extent it consumed and resets a dropped positional tail or a dropped named
  child exactly as `ID-C`'s evaluated-conditional reset already does; `ForEach`
  (new, `DD-B`) gets the identical rule. **14** (a `List` below a flow sibling in its
  scroller windowed against the scroller's origin and rendered blank) retires
  under `DD-F` — the list windows against its own origin, last frame's
  measurement; **13** is amended, kept (the first frame after a resize is
  still stale, but the list asks for exactly one more frame). **Added**: 78 (`Binding` is
  `@MainActor`, where SwiftUI's is nonisolated and `Sendable`, kept, `DD-D`
  item 4), 79 (a `ForEach` whose ids collide in description but differ in
  value produces only the first of them, where SwiftUI evaluates both, kept,
  found by probe S6, `DD-L`). **`ScrollIndicatorVisibility`'s new `.visible`/
  `.never` cases get no row**: they are SwiftUI's own measured macOS
  behaviour (`DD-H`), not stored-but-unread state — superseding the enum's
  own doc comment that a third case would be inert. **`KeyBinding`'s
  deprecated `Binding` alias is deleted, not a divergence**: `EV-N` announced
  the break, `DD-D` item 6 lands it.
  **Plan task 10 part 2 retires 16 and adds 80–85** (56 → 61 live; record
  §04's 2026-09-28 task-10-part-2 section, rulings `DD-Q`…`DD-AI`): 16 (a
  click target inside a `ScrollView` swallowed the wheel over itself)
  retires under `DD-Y` — the wheel now passes to the nearest ancestor
  hitbox on the same layer that registered a scroll region, so a button, a
  toggle, a slider, a selectable `List` row or a single-line `TextField`
  no longer blocks it; an overlay sibling and a `Deferred`-hoisted scrim
  still stop it (the ancestry and layer clauses, both pinned). **Added**: 80
  (every control takes its keys once focused whether or not SwiftUI's own
  Full Keyboard Access setting would allow it — unmeasured there, kept,
  `DD-T` item 3), 81 (the automatic `Picker` is segmented, where SwiftUI's
  is a pop-up menu on macOS, kept, owner plan task 12 for the menu
  presentation, `DD-V` item 4), 82 (the accessibility partial fold gives
  `.incrementor`/`.radioGroup` an accessible name from its non-interactive
  descendants, where SwiftUI publishes a sibling static text beside an
  unlabelled control — also missing a slider's `AXValueIndicator` child and
  a stepper's arrows published DISABLED while enabled — kept, owner plan
  task 12's VoiceOver validation, `DD-U` items 3 and 9), 83 (an
  accessibility client selects a `List` row only by pressing it;
  `AXSelected`/`AXSelectedRows` write nothing, where SwiftUI's do, kept,
  owner plan task 12, `DD-Z` item 8), 84 (a `List` answers its content
  height as `rowHeight × count`, needs an enclosing `ScrollView`, is
  data-driven only and shares one row height, where SwiftUI's is greedy,
  self-scrolling and blank beside a header — kept, owner **none**, `DD-AB`
  item 3), 85 (an optional `@State` with a non-`nil` initial value reads
  `nil` until its first write — `StateTable.peek`/`State.wrappedValue` casts
  an absent entry to the optional type as a present `.some(nil)` before the
  `?? initialValue` fallback runs — kept, owner **plan task 15** closeout,
  found by the controls demo and disposed of by the Record phase rather
  than fixed on this branch, `DD-AG` item 3, `DD-AH` item 4, `DD-AI`).
  Divergence 76 is **amended again, not retired** (`Button`'s chrome now
  reads `controlSize`; every other consumer stays plan task 11's, `DD-R`
  item 4).
  **Plan task 11 part 1 adds 86–89, amends 76 a third time** (61 → 65 live;
  record §04's 2026-09-28 task-11-part-1 section, rulings `TE-G`, `TE-I`,
  `TE-K`, `TE-Z`): **added**: 86 (MetalUI's line advance is
  `ceil(ascent + descent + leading)` on both text systems, where SwiftUI's
  TextKit line-fragment height fits no formula tried over those three
  numbers — a Noto Sans line is 24 pt where SwiftUI's is 23 — kept, owner
  none, `TE-G` item 3), 87 (a single line truncated in the middle keeps what
  `CTLineCreateTruncatedLine(.middle)` keeps, where SwiftUI sometimes keeps
  more at the same width — equal in every other mode — kept, owner none,
  `TE-I`), 88 (`GridRow(alignment: .firstTextBaseline/.lastTextBaseline)`
  traps at registration, naming the divergence, rather than reproducing
  SwiftUI's row-overflowing answer — kept, owner none, `TE-K` item 4), 89 (a
  wrapping text beside a bare `Spacer` in a height-limited stack is offered
  the height less the spacer's minimum, where SwiftUI shares the height with
  the spacer — kept, owner none, `TE-Z`). Divergence 76 is **amended a third
  time, kept, owner none** (`TE-F` item 4): `controlSize` now reaches every
  text's default font (`Text`, `ProposalText`, `TextField`, `TextEditor`) in
  addition to `Button`'s chrome from task 10 part 2; it still reaches no
  other control's chrome (`TextField`'s own padding, `Toggle`, `Picker`,
  `Slider`, `Stepper`).
  **Plan task 11 part 2 retires 64 and adds 90–93** (65 → 68 live; record
  §04's 2026-09-29 task-11-part-2 section, rulings `TE-AG`, `TE-AJ`, `TE-AL`,
  `TE-AN`): 64 (`gridCellAnchor` took only the nine `ProposalAlignment`
  spellings, not an arbitrary `UnitPoint`) retires under `TE-AN` — the
  kernel's cell anchor is now a factor pair (`ProposalAnchor`), the
  nine-point spellings map onto it unmoved and a plain `UnitPoint` resolves
  too (`@_disfavoredOverload` keeps the leading-dot spellings unambiguous).
  **Added**: 90 (`RoundedCornerStyle.continuous`, the default corner style
  on `RoundedRectangle`/`Capsule`, draws circular — the renderer's SDF has
  no closed form for Apple's continuous curve, 196 px apart at r = 20 in
  100×60 — kept, owner none, `TE-AG` item 2), 91 (`clipShape(Ellipse())`
  traps naming the divergence — the mask is a rounded rect on every
  primitive the renderer has — kept, owner none, `TE-AJ` item 4), 92 (two
  rounded clips whose corners cross still intersect as the square
  bounding-box fallback, not their exact geometric intersection — one mask
  per primitive — kept, owner none, `TE-AJ` item 5), 93 (`Image.interpolation(.high)`
  draws bilinear, identical to `.low`/`.medium` — 880 px from SwiftUI's own
  `.high` sampling — kept, owner none, `TE-AL`). **A likely-looking fifth
  divergence is NOT added**: `clipShape` clips hitboxes to its geometry's
  bounding rect (square), which SwiftUI's own hit behaviour under
  `clipShape` was never measured against (the probe is headless, no window
  is ordered front) — stated as MetalUI's own rule instead, owner **plan
  task 12** (`TE-AQ` item 4, `TE-AJ` item 1).
  **Plan task 12 part 1 adds 94, amends 43/41/80, pins 57, re-owns 81/21/22**
  (68 → 69 live, next label 95; record §04's 2026-09-29 task-12-part-1
  section, rulings `IX-D`, `IX-K`, `IX-L`, `IX-O`): **94 added** (a click on
  a `.focusable()` view or `Button` does not focus it, kept, owner none,
  `IX-K` item 2 — SwiftUI's own click does, probe F3); **43 amended**
  (`clipShape`'s own hit behaviour intersects the clip's *rect*, not its
  rounded geometry — MetalUI's own rule, unmeasured against SwiftUI,
  `IX-L` item 2); **41 amended** (a bare `Shape`'s default hit region is its
  frame too, same as every other element's); **80 amended** (Full Keyboard
  Access, now measured — probe arms F5/F6 confirm Tab moves nothing with it
  off — rather than merely carried from the text-page merge); **57 pinned**
  (a non-clickable primary passing a click through to its background,
  previously unpinned, kept, owner none, now pinned by 2.18); **81
  re-owned** (menus, still no number, still no owner, `IX-M`); **21 and 22
  re-owned, kept, owner none** (focus retention on disable; raw keys on a
  disabled ancestor — the audit's own two rows this task closes by ruling
  MetalUI's existing behaviour as the answer, no code change, `IX-G` item
  1). `ID-R` item 9's unnumbered focus-identity difference is **closed**
  (fixed to SwiftUI's answer, `IX-I` — see "Focus" above) rather than
  numbered — it never reaches a live-count row.
  **Plan task 12 part 2 retires 28 and 83, adds 95, amends 27/32/33, keeps 82**
  (69 → 68 live, next label 96; record §04's 2026-09-30 task-12-part-2
  section, rulings `IX-Y`, `IX-Z`, `IX-AA`, `IX-AF`): **28 retires** (a press
  under `allowsHitTesting(false)` is now advertised and runs, `IX-Z` item 1);
  **83 retires on the AppKit bridge** (`AXSelected`/`AXSelectedRows` are
  settable and replace the selection, `IX-AA` item 1 — AccessKit still
  selects by `Click`, not a divergence: SwiftUI has no AccessKit side to
  compare); **95 added, kept, owner none** (an isolated-out element a client
  already holds refuses a press/adjust/focus/action/select request, where
  SwiftUI's held element still presses — rejected as avoidable in the critic
  round, `IX-Z` item 3, `IX-AF`); **27 amended** (MetalUI's gestures publish
  no press, matching SwiftUI's G1–G7 exactly now that the fact is pinned;
  `onClick` stays the one pressable surface, `IX-Y` item 3); **32 amended**
  (AppKit now publishes `AXOutline`/`AXRow`/`AXOutlineRow`, SwiftUI's own
  role, in place of `AXTable`; unrealised rows stay unreachable, kept, owner
  none, `IX-AA` item 3); **33 amended** (`.ignore`, a removed `.isButton` and
  a labelled `Rectangle` all read `AXGroup` for SwiftUI's `AXUnknown`,
  `AB-F`'s reasoning); **82 kept, owner the human VoiceOver run** (the
  script has a step for the `.incrementor`/`.radioGroup` partial fold;
  divergence 83's retirement is likewise seen by a human in the same script).
  Live count **69 → 68**, next label **96**.
  **Plan task 13 adds 96–99, retires none** (68 → 72 live, next label 100;
  record §04's 2026-09-30 task-13 section, rulings `AN-X`, `AN-AB`, `AN-AE`,
  `AN-Y`): **96 added, kept, owner none** (SwiftUI lays out once at the final
  values and interpolates each view's placed geometry and render effects;
  MetalUI interpolates the declared input and re-runs layout every frame —
  the two agree for a wrapper's own rectangle and differ where a child
  re-lays out or a sibling moves, probes W1/W11/P1/P2/X00, `AN-X`);
  **97 added, kept, owner none** (what still snaps on the proposal path where
  SwiftUI animates: `nil` ↔ value, finite ↔ infinite, `fixedSize`,
  `layoutPriority`, `aspectRatio`, `allowsHitTesting`, alignment, a
  `clipShape`'s shape, `AN-AB`); **98 added, kept, owner none** (no default
  transition — SwiftUI cross-fades an unannotated insertion/removal, MetalUI
  inserts and removes instantly, since a default would make every
  conditional in every tree capture its primitives every frame for a ghost
  it almost never draws, `AN-AE`); **99 added, kept, owner none** (one
  transaction per build — SwiftUI attributes each write to its own
  `withAnimation`/`.animation` call (T9, T10); MetalUI's frame rebuild
  cannot, so a nested or a second call in one interval shares the one parked
  curve — `.animation(_:value:)` is the per-value remedy, `AN-Y`). Live count
  **68 → 72**, next label **100**.

## §3 Declared but inert bullet

- **Declared but inert** APIs (compile and do nothing:
  `onInput`'s `-> Bool`, colour glyphs, baselines,
  `locale`/`layoutDirection`/`dynamicTypeSize`,
  `controlSize`, `displayScale`, `ButtonRole` (compiles, binds a key, changes
  nothing else drawn — an inert row by design, not a gap, `IX-E` item 1),
  `AXNode.actions`/`AXActionKind` (deprecated toward `accessibilityAction`/
  `accessibilityAdjustableAction`, never read, `IX-Y` item 4),
  `AccessibilityTraits.updatesFrequently` (published on neither bridge, as
  SwiftUI's on macOS),
  one axis each of
  `markNativeGridRow`/`markNativeGridCell`'s alignment, a grid mark outside a
  grid, …) — §19 "Declared but inert", record §05, whose 2026-09-21 section
  carries the stage 2 and grids changes, whose 2026-09-22 one carries stage
  3's and whose first 2026-09-23 one carries stage 4's: `UnlowerableField` site
  `.list` has **no site-level reporter left** (the same shape as site
  `component`). **`margin: .auto` and `Style.border` on a container are
  removed from this list at stage 9**: they were "legacy-authority only" —
  inert under the CSS engine, lowered (to nothing explicit, and to insets)
  under the proposal one — and the CSS engine that made them inert anywhere
  is gone, so they are always lowered now, never inert (record §05's
  2026-09-24 stage-9 section). A `Text`'s `Style.padding` around its leaf was
  the third such row and is likewise always lowered now. `Style.overflow` was
  **not** one of them even before: the lowering never carried it either, and
  `loweredLayout` says so in a comment — it stays in the list, unaffected.
  **`ListRows.GroupLayout.spacer` is deleted, not merely inert**: it went with
  the legacy `List` path it served (`ListRows.swift`'s own comment). Adding
  an unimplementable property: add a row. **Stage 5's (second
  2026-09-23) section adds no row**: its new reports
  (`deferred.containingBlock`/`.nested`/`.root`/`.amended`, the two
  `…absolute` fields, `position`/`inset` moved to the consumer) are
  diagnostics read by the report mechanism itself, not stored-but-unread
  state; the first three of those reports are deleted at stage 9 with the
  legacy engine whose containing block they protected, `deferred.amended`
  survives (re-owned to stage 11). **`LayoutAuthority.proposal` in production
  is no longer inert — its row is deleted** (stage 6b, `LR-DF`: production
  now runs it by default); the
  entry above listed it until this stage. **`Style.aspectRatio`, `overflow`,
  `Style.border` on a container and `Position.relative`'s offset are DELETED
  at stage 10, not merely inert — removed from the inline example list above,
  not narrowed to it** (`LR-FM` item 1, record §05's 2026-09-24 stage-10
  section): the fields themselves, the enums `FlexWrap`/`AlignContent`/
  `Overflow` and the modifiers `flexWrap(_:)`/`alignContent(_:)` no longer
  exist. `margin: .auto`'s row (kept, since `margin` survives) is narrowed
  further: `Style.margin` is no longer public, so the case is unreachable
  from outside the package by any route, not only through
  `StyledElement.margin(_:)`'s `Length` parameter. **A row is added**:
  `Box`'s public `style:` initialiser parameter, inert outside the
  package now that every field it could set is `package` (`LR-FR` F5).
  **Stage 11 deletes `deferred.amended`'s row**: a `Component`'s amend over a
  presentation member no longer reports at all — it lowers exactly as a
  legacy `.frame` layer over the same member already did — so the report
  mechanism has nothing left to answer here, not merely nothing new to say
  (`LR-FY` §6.1, record §05's 2026-09-25 stage-11 section). **Plan task 8
  deletes the `@State`-inside-`AnyElement` row** (`ID-E`, record §05's
  2026-09-25 task-8 section): `AnyElementBox` now binds its concrete element
  before every phase, so the row is fixed rather than merely reassigned —
  the same shape as `deferred.amended` above, not a narrowing. **Plan task
  9's closing half adds three rows, deletes none** (record §05's 2026-09-25
  task-9 section): `controlActiveState` (owner plan task 12, with the
  disabled look), `controlSize` (owner plan task 11 for `Text`'s default
  font, plan task 10 for `TextField`/`Button` and the other common
  controls — divergence 76) and `displayScale` (**no owner named**: it exists
  for an author to read, as `pixelLength` always has, not for a framework
  consumer — `Frame.fill` still scales by the frame's own `scaleFactor`, never
  by `environmentTop.displayScale`, and `roundLayout` still rounds to whole
  points regardless, divergence 77).
  **Plan task 10 part 1 adds no row and deletes none** (record §05's
  2026-09-25 task-10-part-1 section): `ScrollIndicatorVisibility`'s two new
  cases are wired to already-live paths (`.visible` as `.automatic`, `.never`
  as `.hidden`), not new unread state, and `KeyBinding`'s deprecated alias is
  deleted outright, never having held a row here.
  **Plan task 10 part 2 narrows the `controlSize` row, adds no other, deletes
  none** (record §05's 2026-09-28 task-10-part-2 section): `Button`'s
  automatic chrome now reads it (`DD-R` item 4), so the row is no longer a
  flat "inert" example above — narrowed to "reaches `Button`'s chrome only,
  divergence 76 amended"; `Text`'s default font (plan task 11) and every
  other control's metrics (also plan task 10's own remaining consumers, none
  built this part) still read nothing from it. `controlActiveState` and
  `displayScale`'s rows are untouched: neither control this part built reads
  either (`DD-Q`'s table re-points `controlActiveState`'s consumers at plan
  task 12 unchanged).
  **Plan task 11 part 1 deletes the `AlignItems.baseline` row and narrows
  `controlSize`'s further; `dynamicTypeSize`'s is confirmed, unmoved**
  (record §05's 2026-09-28 task-11-part-1 section): `alignItems.baseline` on
  a legacy row or column now lowers (to `baseline: .first` or `flexStart`)
  instead of doing nothing, so it is no longer an example of this list — a
  `display: .stack` container's `alignItems.baseline` and any
  `alignSelf.baseline` outside a baseline row are still reported, but as
  `TE-L`'s permanent refusals (`owner: nil`), the same shape as the rows
  above, not as inert state. `controlSize`'s row narrows again: it now also
  reaches every text's default font (`Text`, `ProposalText`, `TextField`,
  `TextEditor`), in addition to `Button`'s chrome from task 10 part 2
  (`TE-F`); `TextField`'s own padding and every other control's chrome still
  read nothing from it. `dynamicTypeSize` is read by design and stays: `Font`'s
  text-style table has no size column, so the value is carried and scoped but
  reaches no text style (`TE-E`, spec 3.9) — unlike `controlSize`, no built-in
  consumer is owed to a later task, so this row is not narrowed further.
  **Plan task 11 part 2 adds no row and deletes none** (record §05's
  2026-09-29 task-11-part-2 section): the colour-glyphs row is re-confirmed
  unmoved (`TE-AO` item 2) — the new image primitive is now the draw path a
  polychrome glyph would use, but rasterizing `COLR`/`sbix` into RGBA stays a
  text-system milestone this task does not touch; nothing else this part
  declares (`Shape`'s `cornerRadii` ignored on an ellipse, an image's `filter`
  field, the anchor factor pair) reads as inert — each is read by exactly the
  code that consumes it.
  **Plan task 12 part 1 deletes two rows, adds one, narrows none** (record
  §05's 2026-09-29 task-12-part-1 section): `EnvironmentValues.controlActiveState`'s
  row is **deleted** — every accent-carrying control and every control's
  focus ring now read it (`IX-H`); `PaintPass.isActive`'s row is **deleted**
  — `Button`'s pressed look now reads it, pinned by 2.3 (`IX-E` item 3); a
  new row, `ButtonRole`, is **added** (moved into the inline list above,
  `IX-E` item 1) — it compiles and binds a key correctly but changes nothing
  else drawn, an inert row by design; and the `hidden()`-on-focusable hazard
  (`focusable()`'s own doc comment, an earlier row here) is **deleted** — a
  hidden focusable element can no longer take focus or keys at all (`IX-K`
  item 3), so there is no more hazard left to log as inert-but-dangerous.
  **Plan task 12 part 2 amends one row, adds two, narrows none** (record
  §05's 2026-09-30 task-12-part-2 section): `AXNode.actions`'s row is
  **amended** (moved into the inline list above, `IX-Y` item 4) — deprecated
  toward `accessibilityAction`/`accessibilityAdjustableAction`, still never
  read; a new row, `AccessibilityTraits.updatesFrequently`, is **added**
  (moved into the inline list above) — it compiles and publishes on neither
  bridge, as SwiftUI's own trait on macOS, an inert row by design; and
  `ButtonRole`'s row (from part 1) gains its accessibility evidence — B1/B2
  pin that neither bridge publishes anything for it, as SwiftUI's own
  `NSButton` does not either.
  **Plan task 13 adds no row** (record §05's 2026-09-30 task-13 section):
  `EnvironmentValues.accessibilityReduceMotion` is read by the transition
  code (and by `propertyAnimationsRunUnchangedUnderReduceMotion`'s own
  set-up), so it is not stored-but-unread state.

## §4 Human verification bullet

- **Human verification** status per milestone, demo keys (**M** modal,
  **Space** theme, **F**/**Esc** focus, **=**/**-** count, **A** animation,
  **Q** quit) and open looks — §19 "Human verification", record §03, whose
  2026-09-21 section adds the two stage 2 / grids rows, whose 2026-09-22 one
  adds stage 3's, whose first 2026-09-23 one adds stage 5's and whose second
  2026-09-23 one (stage 6b) **re-opens the demo-layout rows**: production now
  runs the proposal engine by default, so every look the demo shows is this
  stage's to own. Nothing
  in the suite sees paint order, portals, scroll direction, presentation, the
  display link or real hover; those are looks. Padded legacy container rule:
  container modifiers and `.flexGrow(1)` before `.padding`; size (a `.frame`
  since stage 8), background, corner radius after. **Four looks are open here**: the stage 2 / grids
  release-window capture (the screen was locked; the offscreen half read nine
  of twelve images at 0 and attributed the three preview images to the grids
  track's four preview cells); the preview's grid itself, which nobody has
  seen on screen (`GR-N`); and stage 3's capture against `57893d0` (the screen
  was locked at every lane, at the verification round and at the Docs phase —
  the offscreen stand-in read 0 in all twelve, twice more in verification, once
  with an independently written harness, and the two-authority chrome pair 0,
  but **none of the twelve scenes is ever scrolled**, so no indicator is
  painted in any of them and the fold's indicator half is pinned by tests, not
  pixels). **Stage 4's capture is taken, and read 0 differing** — three times
  (lane 3 at `352f838`, and two verifiers at `9ad98db` and `a53daeb`), each
  with four a-vs-b stability zeros and a ~921 000-pixel default-vs-preview
  control, plus the twelve offscreen images at 0 at every lane and twice more
  in verification. **The demo's `List` is never windowed in any of them** (one
  cold frame, `firstIndex == 0`), so the windowing is pinned by tests, not by
  pixels. Nothing in production ran under the proposal authority before stage
  6b, so no demo look was owed before it. **Stage 5's capture is open too**:
  the screen was locked at all three lanes (03:11, 04:02, 04:41 PDT), so
  `capture.sh` was never run; the offscreen twelve read 0 differing at every
  lane — no demo look was owed by that stage either, since `Deferred` as a
  presentation root was reachable only under `LayoutAuthority.proposal`, still
  not production's path at the time. **Stage 6b's real-window capture is open
  too, and now IS owed**: `LayoutAuthority.proposal` is production's default
  as of this stage, and the demo's pixels changed (a sidebar/panel width, its
  paragraph's re-wrap, the modal card's height, list-row labels now vertically
  centred — every one probe-backed and named, record §41 §4, §12.6). The
  screen was locked at every check across all three lanes and the critic
  round, so `capture.sh` was never run; the fourteen-image offscreen
  comparison stands in and reads exactly those four named causes and nothing
  else. **Five looks a human still owes**: the real-window capture itself, the
  sidebar now reading 196 where the CSS engine shrank it (to 96 at 1024², 88
  at the demo's own 920×560),
  the animation panel at 320, the modal card's new height, and the list rows'
  labels now centred in their declared 28 pt row — none of these was ever seen
  on a real display. **No look was added by engine-replacement stage 7a,
  stage 11 or plan task 8** (record §03's own dated sections for each — stages
  7b, 8, 9 and 10 recorded no §03 section, so this file makes no claim about
  them): plan task 8 and stage 11 each touch no pixel the demo paints (0
  differing in all fourteen offscreen images) and neither reopens or closes
  the five looks above. Plan task 8's own lock probe ran six times across its
  lanes and Record phase, and a seventh time at its branch check, and read locked every time — the same
  still-owed capture, not a new one. **Plan task 9's closing half adds no
  look but adds two more to the still-owed capture** (record §03's 2026-09-25
  section): `displayScale`, `controlActiveState` and `controlSize` reach no
  built-in element, so 0 px against `e732d98` in all fourteen offscreen
  images at every lane and again at the Record phase's close — but the task's
  own probe could not run its C1–C3/C5 arms (the screen was locked at every
  check), so **the key/active mapping against SwiftUI, and a `displayScale`
  change from moving the window between displays**, are now owed alongside
  the still-open real-window capture, neither reachable without an unlocked
  screen and, for the second, two displays of different scale.
  **Plan task 10 part 1 adds no demo look but adds one more look of its own**
  (record §03's 2026-09-25 task-10-part-1 section): `ForEach`, `Binding`,
  `ScrollViewReader` and the `List`/indicator fixes touch no tree the demo
  builds, so 0 px against `e7bc2e7` in all fourteen offscreen images, taken
  at this task's own close; the lock probe read locked again (a third
  reading this task, after design time and the critic round), so
  `capture.sh` was never run. **Wheel scrolling under `.disabled`**
  (`EV-Q`'s item for this task, `DD-I` item 3) is owed: SwiftUI's positive
  control never ran (screen locked), so whether its disabled scroll view
  scrolls is unmeasured — MetalUI's still does, pinned, unchanged.
  **Plan task 10 part 2 adds one new demo look and a long list of pointer
  and accessibility looks, all still owed** (record §03's 2026-09-28
  task-10-part-2 section): the controls demo
  (`METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo`) is a tree the existing
  demo never built, so it is its own look, not a reopening of the five still
  owed above; the fourteen-image offscreen comparison stands in for the
  ordinary demo (0 px against `27b2fcc`) but says nothing about a tree it
  never renders. The lock probe read locked at every lane's own check and
  again at this Record phase's close (`CGSSessionScreenIsLocked = 1`,
  `displayAsleep main: 1`), so `capture.sh` never ran and SwiftUI's own
  click/wheel/keyboard controls never did either (CK0, WH0 failed in every
  probe session) — **owed**: the controls demo on screen (every control by
  pointer and by key — a slider press and drag, stepper halves, the wheel
  over a button/field/selectable row, ⌘/⇧-click and arrow selection on a
  `List`, the lead reveal); VoiceOver on the five new roles (the partial
  fold's accessible name vs. SwiftUI's sibling title, divergence 82; a
  slider's missing `AXValueIndicator` child and a stepper's arrows read
  DISABLED by AppKit while enabled); and whether SwiftUI's controls take
  Space/Return/arrows without Full Keyboard Access, which the design's own
  probe run never turned on (divergence 80). None of these was ever seen on
  a real display or a real accessibility client.
  **Plan task 11 part 1 adds no image-moving look, but adds one look of its
  own and takes half of the still-open real-window capture** (record §03's
  2026-09-28 task-11-part-1 section): a height census taken before any source
  change (`docs/probes/text-semantics-height-census.patch`) predicted, and
  the fourteen-image offscreen comparison confirmed, 0 px against `169d166`
  in every one — the one text leaf the census found squeezed
  (`demoMainPane()`'s wrapping paragraph under the **A** state, `TE-H` item 2)
  is not in any of the fourteen (their animation images are 1024², where it
  still fits). The lock probe read locked at design time, at every lane's own
  check and at the lane-3 close (18:09 PDT), but **unlocked once during the
  lane-3 fix round** (18:19 PDT): `capture.sh <scratch> 169d166 e39a9b4` was
  run and read `default: 1840x1176 differing=0` and `preview: differing=0`
  (control 958986) — so the default and preview states of the still-open
  real-window capture are **now taken, 0 differing**, narrowing what is owed.
  **Still owed**: the paragraph under **A** at the demo's own 920×560 window
  (four lines where it drew five, `TE-Y` item 3) — the offscreen images never
  show this state at that size; `TE-Q`'s drawn `controlSize` font (`F8`'s
  render field was `ImageRenderer`'s blind spot, so `controlSize`'s effect on
  a drawn glyph, as opposed to a measured layout, is still unconfirmed); and
  everything task 9's and task 10's own sections above already owed
  (`displayScale`/`controlActiveState`/key-active mapping, the two-display
  `displayScale` change, the controls demo's pointer/keyboard/VoiceOver
  looks) — none of those is this task's to close.
  **Plan task 11 part 2 adds no demo look and does not narrow the still-open
  real-window capture** (record §03's 2026-09-29 task-11-part-2 section): no
  demo tree calls a new shape, clip or image API, so the fourteen-image
  offscreen comparison stands in unchanged (0 px against `ff2ae92`) and says
  nothing new about a real window. The lock probe read locked at design
  time, at the critic round, at every lane's own check and at this Record
  phase's close — **owed, new here**: every shape, stroke, clip and image
  look this part built has never been seen on a real display or through a
  real renderer's antialiasing (an ellipse fill and band, a rounded/clipped
  overlay, a resizable/fit/fill image, `.interpolation`'s four cases) —
  pinned only by the offscreen renderer and the SDL replay-parity harness so
  far; it joins, rather than replaces, the still-open capture above.
  **Plan task 12 part 1 adds no demo look and does not narrow the still-open
  real-window capture, but adds a long list of its own** (record §03's
  2026-09-29 task-12-part-1 section): no demo tree builds a gesture,
  `Button`, control, `.focused` binding or `contentShape`, so 0 px against
  `31f2e7a` in all fourteen offscreen images at every lane and again at this
  Record phase's close; the lock probe read locked at design time, the
  critic round, every lane's own check and this close. **Owed, new here**:
  gestures on a trackpad (tap slop, double-tap timing, long press) against
  Finder/SwiftUI; the pressed, disabled and inactive looks and the focus
  ring beside a native SwiftUI window; a real key window's accent and ring
  behaviour (the synthesized harness's `PX23` always read "inactive"). None
  of this reopens or closes the still-open items above — it joins them.
  **Plan task 12 part 2 finally narrows the still-open real-window capture —
  its default and preview pair, 0 differing — and adds the rest of its own
  looks to what remains owed** (record §03's 2026-09-30 task-12-part-2
  section): the lock probe read **unlocked** mid-task, at lane 1's own close
  (`6c961e3`, no `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`) —
  the first unlocked reading since stage 6b — and
  `docs/probes/window-capture/capture.sh <scratch> 31d3565 6c961e3` ran,
  reading 0 differing for both the default and preview states against
  `31d3565`, every a-vs-b stability pair 0 and the default-vs-preview control
  non-zero (958986) as it must. The screen was locked again at lane 3's own
  check and at the Record phase's close, so no other state was added; the
  fourteen-image offscreen comparison stands in for lane 2 and lane 3's own
  changes (0 px against `31d3565`, scene identical). **Owed, new here**:
  every accessibility bridge look this task built has never been operated
  through real VoiceOver — `docs/verification/voiceover-script.md` is
  written and is itself the mechanism for closing this, needing a human, not
  an agent (`IX-AE`). None of this reopens the demo-layout, task 9, task 10
  part 1, task 10 part 2, task 11 part 1/2 or task 12 part 1 looks — they
  stay owed, joined by this task's own.
  **Plan task 13 adds no demo look but adds three of its own to the
  still-open capture** (record §03's 2026-09-30 task-13 section): the
  transitions (a real insertion/removal against a native window),
  Reduce Motion's cross-fade, and `.scale`'s soft mid-flight glyph
  resampling — none of this task's built behaviour draws in the demo (0 px
  against `2de0973` in all fourteen offscreen images, taken at design time,
  the critic round, every lane's own close and this Record phase's close),
  so nothing here reopens or closes the demo-layout look or any other
  earlier task's own; the lock probe read locked at every one of those
  checks, so `capture.sh` was never run this task.
