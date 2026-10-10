# 88 — Key and focus scoping: `onKeyPress`, key regions, focus on press, `onGeometryChange`, `TimelineView` (item C9)

Branch `feat/key-focus` from `c62d6ba` (master at the time: the `fix/clip-nested-flattening` and
`feat/input-apis` merges), merged with master `70e9389` at the Record phase (§10: controls-looks
§85, `GX-X`/`GX-Y`, the licence notices, app shell §87). **Not a plan task**: item C9 of the
gpui-gap priority list (user request 2026-10-02), requested by MetalCreator (a node-based CAD app
on MetalUI: a 3D viewport in a `MetalView` and a node-graph canvas; gaps M4-a, M4-b, M5-b, M5-g,
M5-h and the M6 `Panel`/`!Panel` keymap vetoes in `MetalCreator/docs/metalui-gaps.md`, read,
never edited; repro package `MetalUIRepro-M4b`, read only). Spec
`docs/superpowers/specs/2026-10-08-key-focus-design.md`; rulings `KF-A`…`KF-AA` in the new
decisions doc `docs/superpowers/2026-10-08-key-focus-decisions.md` (next unused `KF-AB`); probes
`docs/probes/swiftui-key-focus.swift` (arms `K0`–`K12`, `FC1`–`FC7`, `RS0`–`RS5`, `G1`–`G7`,
`T1`–`T5`, and the gated `KX1`–`KX3`) and `docs/probes/swift-builder-for-opaque.sh` (`A1`–`A13`).
Parallel branches at the time: `feat/app-shell` (§87, merged to master as `70e9389`),
`fix/smk-port-gaps` (§89), `perf/shadow-cache` (§90) and `feat/test-harness` (§91).

**Numbering.** This record is §88 as the design reserved it; master published §85 and §87 and no
88 before the merge, so it stands. **Divergence labels 185–188** are this branch's reserved range
185–194 (189–194 unused); the header's next-label line in `docs/divergences.md` is left for the
final merge to settle. **Human-checks group `KF`** (KF-1…KF-7), a provisional letter in the manner
of `RT`, `VL`, `WS`, `AS` and `CL`.

**Status: LANDED — every agent-doable clause is built and verified `ok: true` in all three lanes;
the looks are owed to a human** (`docs/verification/human-checks.md` group KF, §7). A design
session and a critic (`KF-P`), then three lanes in one worktree, A → B → C, each red first and each
with a review round; this Record phase merged master, re-took the suite and the counts, and wrote
the shared docs. The spec's Status line is marked.

## §0 What the request was, and the final spellings

Six asks; five built, one a toolchain limitation pinned (`KF-A`):

| # | Ask (gap) | Answer |
|---|---|---|
| 1 | `onKeyPress` on focusable elements and regions (M5-b, M5-h, M6) | **Built**: SwiftUI's family, focus-scoped, outermost first, after the Keymap and before a focused field's editing keys; plus the MetalUI-only `.hoverKeyRegion()` |
| 2 | Focus on click for a surface (M4-a, focus half) | **Built**: `.focusable(interactions: .edit)`; plain `.focusable()` keeps divergence 94 (narrowed) |
| 3 | A press elsewhere resigns text focus (M5-g) | **Not built as asked — SwiftUI does not** (probe `RS1`–`RS5`); the remedies are a click-focusable surface and a press in a key region |
| 4 | `onGeometryChange(for:of:action:)` (M4-a, size half) | **Built**, through the lifecycle drain: in the first presented frame and the frame of a resize |
| 5 | `for` over an opaque helper in a builder (M4-b (1)) | **A Swift 6.4 compiler defect, not fixable in the builder** (probe `A1`–`A13`); a guard pins it, docs give the remedies |
| 6 | `TimelineView(.animation)` (M4-b (2)) | **Built**, with `.periodic`, `.everyMinute`, `.explicit` and custom schedules |

The spellings an app writes are the block at the head of the decisions doc.

## §1 What landed

**Lane A — keys and focus** (`8e83342` red, `7d00e5b`, `33bc4ba` KX, review `aa27b9d`/`ab6871f`).
`KeyPress` (`key`, `characters`, `modifiers`, `phase`; internal initialiser), `KeyPress.Phases`,
`KeyPress.Result`, `FocusInteractions`, the five `onKeyPress` spellings on `StyledElement`,
`focusable(_ isFocusable: Bool = true)` and `focusable(_:interactions:)`, `KeyEquivalent: Hashable`
(`KeyPress.swift`). `Handlers.keyboard` — the **nineteenth** member, one class box
(`KeyboardAttachment`: handlers in written order, the interactions, the key-region flag; 480 → 488
bytes; `KF-I`). `Window.dispatchKeyPress` after `dispatchAction` and before `dispatchTextKey`,
outermost first and last-written first per element; its `.textInput` arm just before
`dispatchTextInput` (`KF-Q`: one grapheme, no composition, `.down`, no modifiers). **The key chain**
(`keyChain`): the focus chain, else the chain of the innermost hovered key region, feeding the
Keymap's contexts, action dispatch and `onKeyPress` only — `dispatchKey` keeps `focusChain`, so the
controls' keys still need focus (`KF-D`, `KF-U`). `.hoverKeyRegion()` (`HoverKeyRegion.swift`): a
non-opaque pointer region found on demand through the one ranking (`topmostHitbox`), counted
(`keyRegionLookups`), inside the disabled, `allowsHitTesting` and `.hidden()` gates; `focusOnPress`,
a non-claiming stage before the text-field stage that focuses the innermost click-focusable element
(`.edit`) and clears focus on a press inside a key region. **Commands before `onKeyPress`** (`KX2`):
a `keyDown` an enabled command shortcut matches is declined by `dispatchKeyPress`; a `Button`'s
⌘-/⌃-key stays after it (`KX1`) (`KF-X`; divergence 188 for the native-only items).

**Lane B — geometry and timeline** (`08114da` red, `e540c60`, review `2ed2e5e`).
`onGeometryChange` in both forms as `GeometryChangeScope` — `LifecycleScope`'s shape, transparent,
no node, key `$geometry<depth>` in the window's `LifecycleStore` (never a `StateTable` slot); the
value is computed in prepaint (union of the content's bounds; `frame(in: .global)` through the
composed effect affine and the scroll offset) and compared in `endFrame`; events run in
`Window.drainLifecycle()`, geometry before lifecycle (`GeometryChange.swift`, `Lifecycle.swift`;
`KF-J`, `KF-S`). `TimelineView` with `AnimationTimelineSchedule`, `PeriodicTimelineSchedule`,
`EveryMinuteTimelineSchedule`, `ExplicitTimelineSchedule`, the public `TimelineSchedule`,
`TimelineViewDefaultContext` and the SwiftUI nested spellings (`TimelineView.Context`,
`TimelineSchedule.Mode`; `KF-T`). `.animation` calls `noteActiveAnimation()` every build and never
`requestAnotherFrame()`; every other schedule goes through a window-owned `TimelineStore`
(`AnimationStore.timeline`, keyed `$timeline<depth>` with an occurrence ordinal) and **one wake**,
an injectable main-actor `Task` firing the window's own dirty path (`TimelineView.swift`,
`TimelineSchedule.swift`, `TimelineStore.swift`; `KF-K`, `KF-L`, `KF-V`). The clock offset is
taken at the first nonzero timestamp (`KF-Y` item 1).

**Lane C — proposal layer, builder guard, demo, docs** (`3a4953a` red, `c5df112`, review
`5f09634`). `KeyboardModifier<Content>` (`KeyboardModifier.swift`): the proposal spellings of
`.focusable`, `.onKeyPress`, `.keyContext`, `.focused` and `.hoverKeyRegion` return it, and on a
`KeyboardModifier` the same names return `Self` — **a chain of keyboard modifiers is one layer, one
node-less id**, so focusability, the binding, the context and the handlers sit on the focus target
(`KF-H`, divergence 185). It registers through `pass.registerHandlers` inside
`frame.sharingRegistrationsWithEffects`, so its hitboxes follow an `.offset` written inside it
(`KF-AA` item 1). **A shortcut-modified Return is no longer a `TextEditor` editing key**
(`TextEditing.handleKey`; `.command` on macOS, `.control` elsewhere): ⌘↩ reaches `onKey`, a
`Button`'s shortcut, the commands and `Window.onInput` (`KF-Z` item 2; MetalCreator CM-a; **names
text input** from the must-not-move list, with a migration note). Guard C1 pins the opaque
`for`-loop failure as a toolchain limit (`KF-M`); `KeyFocusDemo` in its own function behind
`METALUI_KEY_FOCUS_DEMO=1` in `MetalUIDemo` and `MetalUISDLDemo`, with `DemoStackBudgetTests`' arm.
No `PlatformWindow`, `Platform` or `WindowRenderer` requirement, no shader, no `Backends/SDL`
source beyond the demo's opt-in root (`KF-N`).

## §2 Tests and guards, per file

The branch adds **103** tests to the baseline's 2873 (2976 at `91bb724`, master's 2873 + 103; seven
of them typecheck guards).

| File | Tests | Holds |
|---|---|---|
| `Tests/MetalUITests/KeyPressTests.swift` | 27 | the family, matching, phases, outermost-first, the pipeline order, typed characters, KX2/KX3 (A1–A17, A36–A44) |
| `Tests/MetalUITests/HoverKeyRegionTests.swift` | 9 | the key chain, one ranking, layers, focus wins, `onKey` untouched (A18–A24, A45) |
| `Tests/MetalUITests/FocusOnPressTests.swift` | 12 | press focus, `.edit`/`.activate`/`.automatic`, the key-region clear, the cover-descends and layer pins (A25–A33, A31b/c, A26b) |
| `Tests/MetalUITests/GeometryChangeTests.swift` | 15 | first call before `onAppear`, resize, union, offsets, re-insertion, work counts (B1–B15) |
| `Tests/MetalUITests/TimelineViewTests.swift` | 17 | `.animation` and the link, periodic/explicit/custom wakes, dates, identity, both entries (T1–T16, T1u, T5b) |
| `Tests/MetalUITests/KeyboardModifierTests.swift` | 6 | one layer, binding and context, the later `onKeyPress` first, `TextEditor` ⌘↩, C12 (C4, C5, C7, CM-a, C10, C12) |
| `Tests/MetalUITests/KeyFocusDemoTests.swift` | 1 | the demo tree builds and the status line walks |
| `Tests/MetalUICrossPlatformTests/KeyPressPortableTests.swift` | 5 | the pipeline on Linux/Windows CI (portable copies of A6, A38–A42) |
| `Tests/MetalUICrossPlatformTests/GeometryTimelinePortableTests.swift` | 4 | portable T13: B1, B3, T1, T4 |
| `Tests/MetalUITests/KeyFocusCompileGuards.swift` | 3 | G1/G2/G4: the five spellings, `focusable()` still compiles, `KeyPress` has no public initialiser (with its positive control, `KF-W` item 2) |
| `Tests/MetalUITests/GeometryTimelineCompileGuards.swift` | 2 | B-G1/B-G2: both `onGeometryChange` forms (the `@Sendable` arm, `KF-S`), `TimelineView.Context`, `Mode`, divergence 120's arm (`KF-T`, `KF-V`) |
| `Tests/MetalUITests/KeyboardModifierCompileGuards.swift` | 1 | C8: a chain infers to one `KeyboardModifier<MetalView>`, the nested type does not (`KF-Z` item 1) |
| `Tests/MetalUITests/BuilderForLoopCompileGuards.swift` | 1 | C1: the opaque `for` fails with the opaque-type diagnostic; `ForEach`, a concrete helper and the inline chain compile |
| `DisabledTests`, `HitRegionTests` | (arms) | the `KeyboardModifier` arm in the three `everyHandlerRegisteringSite…` guards (C6) |
| `ModifierTests`, `OuterModifierMatrixTests` | (fields) | `HandlerShape`/`HandlerFingerprint` gain `keyboard` (nineteenth member) |
| `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift` | (arm) | `buildTheKeyFocusDemo()` (C2), merged beside the app shell's |

Typecheck guards: the seven above are the branch's new ones (baseline 188 at `c62d6ba`; the merged
tree's count is in §11). Each was mutated red once (§5).

## §3 Probes

- **`docs/probes/swiftui-key-focus.swift`** (new): arms `K0`–`K12` (matching, phases, order, the
  field, the `Button` shortcut, `onKeyPress` inside `.focusable()` = `K12`), `FC1`–`FC7` (what a
  click focuses), `RS0`–`RS5` (a press elsewhere), `G1`–`G7` (`onGeometryChange`), `T1`–`T5`
  (`TimelineView`). macOS 27.0.1, Swift 6.4, screen unlocked; runs 10 and 11 byte-identical, 69
  lines; the instrument's discarded runs are listed in its header (run 1 read `RS1`/`RS2`
  `focused=false` with every earlier window alive — the arms read the answer once each hosting view
  is released). The gated arms `KX1`–`KX3` (`KF_PROBE_KX=1`, 73 lines, run twice byte-identical)
  were taken by lane A once the lock cleared (`KF-X` item 1); lane A also re-ran `K2t`, `K2v`,
  `K4c`, `K4a` byte for byte.
- **`docs/probes/swift-builder-for-opaque.sh`** (new): `A1`–`A8` reproduce the M4-b (1) failure with
  no MetalUI import (a twelve-line builder; a concrete helper `A2` and a hand-built array `A3`
  compile; a non-generic `buildArray` `A4` and a wrapper naming the type `A5` fail; only erasing
  every expression compiles `A6`; SwiftUI has no `buildArray` `A7`; `ForEach` `A8`); the critic
  added `A9`–`A13` (`KF-P` item 1). Run twice, byte-identical.
- The SDK's `SwiftUI.swiftinterface` was read line by line for the five `onKeyPress` overloads,
  `KeyPress`, `FocusInteractions`, `focusable` (`KF-P` item 3); two differences were ruled
  (`KF-S`, `KF-T`).
- gpui is **recalled, not re-read**: nothing rests on it alone.

## §4 Red runs

- **Design and critic** (`61265bc`, `450d450`): the critic's defects (`KF-Q`…`KF-W`) were fixed in
  the spec before any code; the SwiftUI probe could not be re-run under the lock (`KF-P` item 2).
- **Lane A** (`8e83342`, against a compiling stub): A1–A33 and A36–A45 and guards G1/G2/G4 red or
  controls; A43 re-taken red against `7d00e5b` (`["all-j", "all-j"]`) before `33bc4ba` inverted it
  by KX2/KX3. These red runs are **the implementer's**, not re-taken by the verifier (`KF-X`
  item 12). A21's presentation arm, A26b, A31b and A31c were added green (they pin shipped
  behaviour); their failing runs are their mutations'.
- **Lane B** (`08114da`, 34 tests, 41 issues on a stub that compiles the whole API and does
  nothing): B1 `entries == ["appear"]`; B2 `[]`; B3/B13 label width nil; T1 one date, link paused;
  T2 date 0 not 0.5; T4 no wake; T9 no mode asked; T15 second `[0]` and the rest as the commit
  message lists them. T8, T14 and the two guards were green on the stub, red by their named
  mutation. **Lane B's review round** added T1u, T16, T5b and B15, each red by its mutation (§5),
  not by a stub.
- **Lane C** (`3a4953a`, against a stub registering nothing): C4 `tabOrder.count → 0`; C5 likewise;
  C6's three arms (`keyboard-proposal heard 0` control, `regions 0, keys heard 0`, `keyboardOrder
  []`); C7 `0 focusable elements`; CM-a `m.log ["heard"]`, `m.text "ab\n"`; C1 and C8 green on
  arrival (C1 pins today's toolchain, C8 checks types the stub already had). **Lane C's review
  round** added C12, red by M14 only (§5).

## §5 Mutation tables

Every mutation from a copy of the committed file, the full unfiltered suite
(`swift test --build-system native --no-parallel`), `git status --short` clean after each restore,
reddened tests named. From the verifiers' measured runs (`KF-X` item 10, `KF-Y` item 5, `KF-AA`).

**Lane A** (`ab6871f`, unmutated 2929):

| Mutation | Reddened |
|---|---|
| V1 `hoveredKeyRegion`: drop `box.layer == cover.layer` | `aKeyRegionUnderAnOpaqueSiblingOrAPresentationIsNotHovered` |
| V1′ `focusOnPress`: drop `box.layer == cover.layer` | `aPressOnAKeyRegionsOwnPopoverChangesNoFocus` |
| V4 `focusOnPress`: drop `cover.id.isOrDescends(from: box.id)` | `aPressOnAnOpaqueSiblingAboveAKeyRegionChangesNoFocus` |
| V9a `Box.focusable(_:)`: `isFocusable = true` regardless | `focusableFalseRegistersNoFocusableAndALaterCallReplacesAnEarlierOne` |
| V9b `focusable(_:interactions:)`: likewise | that test and `aPressDoesNotFocusPlainOrActivateFocusables` |
| A2 (the walk iterates every handler id, ignoring the chain; re-spelled, `KF-X` item 7) | A2 |
| V5, V6, V8, V10, V11 (the verifier's own) | named tests, `KF-X` item 10 |

**Lane B** (`2ed2e5e`, unmutated 2967 with the five lock-dependent tests failing, `KF-Y` item 5):
T1u (drop `noteActiveAnimation()` in the untyped `requestGroupLayout`) →
`aTimelineInALegacyColumnKeepsTheLinkRunning`; Tx (delete the zero-timestamp guard in
`TimelineStore.date(at:)`) → `aZeroTimestampFrameDoesNotFixTheClockOffset`; T5b (delete the
equal-earliest guard in `endFrame`) → `anEqualEarliestEntryKeepsThePendingWake`; Bx-order-forward
(sort `closeGeometry`'s events ascending) → `geometryActionsRunChildrenFirst`. The new typecheck
guards B-G1/B-G2 were each mutated red once.

**Lane C** (`91bb724`, unmutated 2976, the lane's verifier): M14 (register directly, outside
`frame.sharingRegistrationsWithEffects`) → `aKeyboardLayerAfterAnOffsetFollowsItForPressAndHover`
(4 issues); M8 (delete the shortcut-modified Return arm in `TextEditing`) →
`aDeclinedCommandReturnInATextEditorReachesTheWindowsOnInput` (2); M9 (move `dispatchKeyPress`
after `dispatchTextKey`) → `onKeyPressOnAFocusedTextFieldClaimsUpArrowAheadOfTheField`, its
portable copy, `anIgnoredKeyPressLetsTheFieldEdit`, `aHandledReturnDoesNotSubmitTheField` (5);
**M13 = M8 + M9** → exactly the six named in `KF-AA` item 2 (11 issues). C10's handled test is
red only under M13.

## §6 Green mutations and pins that prove less than they look

Equivalent mutations (`LR-X`: the green mutant is a correct spelling). **The record must not say
these are pinned.**

- **A23b**: delete §4.3 step 1 (the text-field early return in `focusOnPress`) — the text stage that
  follows claims the same presses and `Window.focus(_:)` is a plain assignment, so no `@FocusState`
  observer sees an intermediate `nil` (`KF-X` item 6).
- **V2** `!hoverIsSuppressed` in `hoveredKeyRegion` (a drawn alert and the menu session claim every
  key earlier); **V7** `keyboardHiddenDepth == 0` in the key/press region gate
  (`disablingHitTestingIfHidden` raises `hitTestingDisabledDepth` with it); **V3** the `KF-I` strip
  `pointerHandlers.keyboard = nil` (the same ids are found either way) (`KF-X` item 11).
- **T14**: routing `TimelineView`'s untyped entry through the typed one — the `.flexGrow(1)` item
  survives `LegacyContent`; `KF-V` item 2's premise was refuted, T14 stays a value pin and T1u pins
  the live behaviour (`KF-Y` item 2). **Bx-depth**: `$geometry\(depth)` → `$geometry0` — the
  occurrence ordinal already separates stacked scopes (`KF-Y` item 4).
- **M9 alone** does not redden the `TextEditor` ⌘↩ handled test, since the editor now declines ⌘↩
  itself (`KF-AA` item 2).
- A **locked screen** reads the five `AppKitPresentationTests` sheet tests red on every run
  (`KF-X` item 8); they are unmutated-red then, green unlocked, and never counted as reddened.

## §7 Demo comparison and looks

- **Fourteen offscreen images, `docs/probes/demo-pixels/compare.sh`** (the Record phase did not re-take it, §11;
  the branch checker's re-take against `c62d6ba` is §12): the key-focus demo is its own tree behind
  `METALUI_KEY_FOCUS_DEMO` and is in none of the fourteen; `DemoFrameDeterminismTests`'
  `Expected.swift` is unedited.
- **The SwiftUI probe was taken with the screen unlocked for lane A** (`KF-X` item 1); lane B and
  C ran with the screen locked. No real-window capture was taken at any lane.
- **Owed, new here — `docs/verification/human-checks.md` group KF, none performed (an agent
  cannot)**: KF-1 order and the palette with a real keyboard (`root › canvas`, ↑/↓ and Return in the
  focused search field); KF-2 hover routing (Tab over the canvas, focus wins); KF-3 clicks and focus
  (a press elsewhere keeps a field focused, a canvas press clears it, the viewport takes focus);
  KF-4 the viewport size in the first frame and during live resize; KF-5 the orbit label's
  smoothness and the display link stopping when it leaves; KF-6 native menu items (⌘Q/⌘H swallowed
  by a focused catch-all, divergence 188); KF-7 the digit filter and an input method's composition
  (`KF-Q`, divergence 187). Nothing headless sees a real keyboard, a real pointer, an input method,
  the display link or the menu bar.

## §8 Hazards

- **`onKeyPress` runs before the field's editing keys and after the Keymap** — the opposite of
  `onKey`'s bubble (innermost first), by design (`KF-C` item 2). A catch-all `.onKeyPress
  { .handled }` on a canvas swallows ⌘Q and the Edit menu's native items (divergence 188); an app
  command's ⌘-key still runs (`KX2`).
- **Typed characters** reach a handler only through the `.textInput` arm, one grapheme, no
  composition, `.down` with empty modifiers; on SDL a release is not delivered (divergence 187).
- **A hover key region never moves focus or control keys** (`KF-U`): a `Slider`/`Stepper`/`List`
  under the pointer with nothing focused sees nothing; only `onKeyPress` and the Keymap's contexts
  follow the hover chain. A region nested in a `Panel` contributor makes `!Panel` false while
  hovered (`KF-D` item 3; migration note).
- **`Handlers` is nineteen members** (`HandlerShape`/`HandlerFingerprint` each gained a field); a
  new member is one pointer, not a field.
- **A `KeyboardModifier` chain annotated with the nested type compiles** (`KF-Z` item 1): the
  annotation selects the generic overload; nothing an app writes by accident reaches it, and Swift
  cannot exclude one type from a generic extension.
- **`TimelineView`'s wake relies on the SDL loop draining the main queue each iteration** (`SV-H`);
  macOS cannot see a break there, only the Linux image can.
- **A `TextEditor` no longer inserts a line break for ⌘↩/⌃↩** (`KF-Z` item 2): a changed text-input
  behaviour with a migration note (`docs/migration.md`); the commit spelling tests `.command` on
  macOS and `.control` elsewhere (`KF-AA` item 3).
- **A demo section builds in its own function** (the Windows 1 MB stack): `buildTheKeyFocusDemo()`.
- **Agents share one scratchpad**: a verifier's `mut.sh` was overwritten by another workflow's and
  ran in the wrong worktree once (lane A's verifier, no source edit, re-run privately). Give each
  agent its own scratchpad subdirectory.

## §9 Deferrals, with owners

| Deferred | Reason | Owner |
|---|---|---|
| `.focusEffectDisabled()` | MetalUI draws no generic focus effect | a controls-looks follow-up |
| proposal `.onKey` / `.onAction` | no request | the next request that needs them |
| `.focusSection()`, `GeometryReader`, named coordinate spaces | not asked; `CI-AC`'s migration | none scheduled |
| `TimelineScheduleMode.lowFrequency` | MetalUI's windows never enter it | none |
| default focus on show (divergence 186) | SwiftUI focuses the first focusable; MetalUI waits for Tab/press | a focus item when requested |
| `onKeyPress` with an option-modified key | unmeasured in SwiftUI (`KF-B` item 3) | a probe when requested |
| `hoverKeyRegion(priority:)` | additive widening if `KF-D` item 2 is wrong | on request |
| a `keyUp` declined for a command's keystroke | unmeasured (`KF-X` item 2) | none |
| SwiftUI/`NSTextView` ⌘↩ in a `TextEditor` | unmeasured; MetalUI's rule is its own (`KF-Z` item 2) | none |
| `for`-over-an-opaque-helper in a builder | a Swift 6.4 defect, guard C1 turns green when fixed | the toolchain |
| a real-window capture and the KF looks | the lock; an agent cannot | a human (group KF) |

## §10 Merge with master (2026-10-10, `70e9389`)

`git merge origin/master` into the branch at `91bb724`: seven conflicts, all additive.
`Sources/MetalUI/AnimationStore.swift` keeps both `timeline` (lane B) and the keyframe depth
counter (controls-looks); `Sources/MetalUIDemo/main.swift` and
`Backends/SDL/Sources/MetalUISDLDemo/main.swift` keep both demo switches (`METALUI_APP_SHELL_DEMO`,
`METALUI_KEY_FOCUS_DEMO`); `DemoStackBudgetTests` keeps `buildTheKeyFocusDemo()` and
`buildTheAppShellDemo()`; `docs/divergences.md` keeps master's 165–176 beside 185–188 and row 120
carries both the app shell's `EnvironmentScope` clause and `GeometryChangeScope`; the human-checks
file keeps groups KF, AS and CL; `docs/probes/closeout-public-api.tsv` was re-recorded from
`closeout-public-api.sh` rather than merged by hand. Both inventory scripts print nothing after
the merge.

## §11 Counts on the merged tree (2026-10-10)

`swift package clean`, `swift build --build-system native --build-tests` (0 `error:`, the only
`warning:` SwiftPM's deprecation notice), then `swift test --build-system native --no-parallel`
unfiltered: **3172 tests in 3 suites passed** (master `70e9389`'s 3069 + the branch's 103), 0
goldens, `FR-J no-argument frame: succeeded=` line present, 0 `error:`. Typecheck guards: 202
(master's 195 + the branch's seven; derived, not separately re-grepped). Not re-taken in this
run: `Backends/SDL`, the Linux image and the fourteen-image comparison (unmoved since the lanes'
verdicts, §5, §6).


## §12 Branch checker (2026-10-10, on `667e831`)

- **Suite.** `swift package clean`, native build (0 `error:`, the only `warning:` SwiftPM's
  deprecation notice), unfiltered `swift test --build-system native --no-parallel`: **`Test run
  with 3172 tests in 3 suites passed after 317.595 seconds.`**; `FR-J no-argument frame:
  succeeded=true` present. `swift build --build-tests` (default build system): 0 warnings, 0
  errors. The seven new guards counted by file (3 + 2 + 1 + 1); 202 stays derived.
- **`Backends/SDL`** on macOS: 24 + 108 passed. **Linux image** (`swift:6.4`, offscreen driver):
  24 + 105 passed — both unmoved from master's §87 §13. The image prints one `warning:` in
  `AccessKitControlsParityTests.swift:83` (an unnecessary `try`), a file this branch does not touch.
- **Fourteen offscreen images**, `compare.sh <scratch> c62d6ba 667e831`: every control at its
  corrected value (1048576, 1031003, 454895, 0, 1048576, 0, 544, 216), and **0 differing pixels,
  scene identical, in all fourteen**. `Expected.swift` unedited since `c62d6ba`.
- **Inventory**: `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing;
  `closeout-public-api.sh` re-run reproduces the committed TSV byte for byte. `cmp CLAUDE.md
  AGENTS.md` clean. Every `KF-` id cited in the changed docs resolves (`KF-A`…`KF-AA`, next
  `KF-AB`); every backticked test name of 25+ characters in them resolves, except two pre-existing
  lines (`fileDialogDefaultDirectory`, a SwiftUI name; `theRunCounterIgnoresCallsMadeOffTheMainThread`,
  record §03's history).
- **Record §04** gained the 185–188 section (94 narrowed, 120 amended), missing until now.
- **The checker's mutations** (each from a copy, full unfiltered suite, `git status --short` clean
  after each restore):

| Mutation | Reddened |
|---|---|
| MX1 `dispatchKeyPress(_:along:in:)` (`KeyPress.swift`): `for id in chain` (innermost first) instead of `chain.reversed()` | `onKeyPressRunsOutermostFirstAlongTheFocusChain`, `portableOnKeyPressRunsOutermostFirstAlongTheFocusChain`, `aHandledKeyPressStopsTheWalk`, `anAncestorsKeyPressHearsTypedCharactersBeforeTheFieldsOwn`, `theInnermostHoveredKeyRegionWins`, `theKeyFocusDemoRoutesTabOverTheCanvasAndKeysToAClickedViewport` (7 issues) |
| MX2 `LifecycleStore.closeGeometry()` (`Lifecycle.swift`): a change passes `action(new, new)` instead of `action(old, new)` | **nothing — 3172 passed.** The two-argument form's `old` on a change is unpinned: every change test uses the one-value form (`GCResizer`, `w:`), and the two two-argument tests see only initial calls (`old == new`). Probe `G2`/`G5` give SwiftUI's answer (`g:200x180->300x230`). Owed: one pin (resize under the two-argument form, expecting `"200x…->320x…"`), named for this mutation. |

- **Not re-taken here**: the SwiftUI probe and a real-window capture (no claim rests on a new
  run); the looks stay owed to a human (group KF).

## §13 Before the PR: the MX2 pin

The checker's MX2 (§12) reddened nothing, so the pin it owed was added before the PR:
`theTwoArgumentFormPassesThePreviousValueAsOldOnAResize` (`Tests/MetalUITests/GeometryChangeTests.swift`,
B4b): two resizes under the two-argument form read `["200->200", "200->320", "320->250"]`. MX2
(`action(new, new)` on a change in `closeGeometry()`) reddens it alone (`GeometryChangeTests` filtered:
16 tests, 1 issue, at line 183); restored, it passes.

Then, on the merged tree after `swift package clean`: native build 0 `error:`; unfiltered native
`--no-parallel` **`Test run with 3173 tests in 3 suites passed after 231.380 seconds.`** (3172 + 1);
`FR-J no-argument frame: succeeded=true`; default build system 0 warnings; `cmp CLAUDE.md AGENTS.md`
equal; both inventory scripts print nothing. Guards 202, unmoved (the pin is a test, not a guard).
