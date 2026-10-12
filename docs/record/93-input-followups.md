# 93 — Input follow-ups: modifiers on a tap and a still hover, click count, wheel latch, gesture cancellation, a terminal scroll phase (item C16)

Branch `feat/input-followups` from `f2fe54a` (master at the time), **merged with master
`0abce86`** (item 8's `MetalUITesting` harness, §91, and C15's overlays, §92; §4.4). No
renumbering: 93 was free. **Not a plan task**: item C16 of the gpui-gap priority list
(user request 2026-10-02), reported by MetalCreator (`docs/metalui-gaps.md` there:
**GI-a, GI-b, S5-a, S5-b, VI-a**; read, never edited). Spec
`docs/superpowers/specs/2026-10-10-input-followups-design.md`; rulings `IF-A`…`IF-N` in
`docs/superpowers/2026-10-10-input-followups-decisions.md` (next unused `IF-O`); probe
`docs/probes/swiftui-input-followups.swift`. Divergence labels reserved for the branch:
235–244, **235 and 236 used** (the header's count and next label are the merge's).
Parallel branches: `feat/test-harness` (§91, 215–224), `feat/overlays-coords` (§92, 225–234).

**Status: three lanes landed (2026-10-12), lanes 1 and 2 verified `ok`, lane 3
verified by its implementer (the interrupted run's weekly limit stopped it mid-lane;
this section was finished by its continuation).** §1 lane 1, §2 lane 2, §3 lane 3, §4 the
Record phase (suite, counts, pixels, docs), §5 deferrals and hazards.

## 1. Lane 1 — gesture values and cancellation (`IF-B`, `IF-C`, `IF-E`, `IF-F`, `IF-L`)

Commits `d9f31ff` (red: no `Value.modifiers`/`clickCount`, no `onCancelled`, compile
errors), `ff295a3` (the code; divergences 235, 236; inventory rows).

- `SpatialTapGesture.Value.modifiers` is the **last press's** (a `count: 2` sequence
  reports the second press); `DragGesture.Value.clickCount` is the **press's**, never a
  move's or a release's (test 1.3 sends 1 on the moves). Both MetalUI-only (235).
- `onCancelled` on `DragGesture`, `MagnifyGesture`, `RotateGesture`: once, only for a leaf
  that **had reported**, from a dropped primary arena (`abandon()`, ready leaves still end),
  a replaced stale button or pinch arena, a `.mouseMoved` while a button arena is live (a lost
  release: AppKit and SDL send `*Dragged` while a button is held), the pinch arena on key
  loss, and window close (before `onDisappear`). A disabled gesture or removed owner gets
  none (`IF-K` 3). SwiftUI's own answer is `@GestureState` reset (236); not built.
- Verifier (`ok`): unmutated suite 3255 tests; 4 of the implementer's 16 mutations
  re-run (M4, M9, M13, M3), each reddening exactly the tests named; the other twelve left to
  the merge-time checker. The platform event sequences are pinned by existing SDL and AppKit
  tests, not new ones (`IF-L` item 5).

## 2. Lane 2 — wheel latch, terminal scroll phase, platform modifier sends (`IF-G`, `IF-H`, `IF-I`, `IF-M`)

Commits `3209ca8` (red; 8 red, 2.3/2.6/2.8 pin unchanged behaviour), `ba786e5` (the code),
`831ad46`, `e489252` (2.8 and 2.9 sharpened after two green mutants).

- `ScrollLatch` (own file): a scroll's events, momentum included, go to the cover of its
  `.began`; a latch is set at every `.began`; a gone latched id falls back to the pointer
  path; the pointer path is byte for byte unchanged (`DD-Y`, `CI-AH`, `CI-AL` pins green).
- A synthesized `.cancelled` reaches the latched handlers (innermost first, stopping at
  the first claim or scroller) on key loss and window close, only for a scroll still in
  flight; it moves no scroller (2.9 counts `StateTable.writeCount`, since offset and stamp
  could not see it: mutation M9 was green on both).
- AppKit sends `.modifiersChanged` on becoming key (`currentModifierFlags`); SDL's bridge
  fills a focus-gained event's modifiers from `SDL_GetModState` and `SDLWindow.handle`
  forwards it. No new platform requirement.
- Verifier (`ok`): 3266 tests; mutations M8, M9, M2 reddened `aScrollThatEndedNormallySynthesizesNothingAndPhaselessEventsNeverDo`,
  `aSynthesizedCancelMovesNoScroller`, `aNewBeganReplacesTheLatch`. `Backends/SDL`
  24 + 113 on macOS and 24 + 110 in the Linux image (the implementer's runs, before the
  `831ad46` test edits, which touched only `ScrollLatchTests`).

## 3. Lane 3 — `onModifierKeysChanged`, the demo pad (`IF-D`, `IF-K` 2 and 5, `IF-N`)

Commits `e6b334f` (red: `ModifierKeysTests` 3.1–3.9 did not compile, "no member
`onModifierKeysChanged`"), `4e41b38` (the code, demo, inventory, human checks),
`eb08412` (the flags-report fix below, census), then the 3.7 sharpening.

### 3.1 What was built

- `ModifierKeysChange.swift`: `ModifierKeysScope` (transparent; `ElementGroup` and
  `ProposalElementGroup` entries copied from `GeometryChangeScope`), the public
  `onModifierKeysChanged(mask:initial:_:)` on `ElementGroup`. `LifecycleStore` gains
  `currentModifiers`, `hasModifierObservers`, `modifierDepth`, `noteModifierKeys` and
  `closeModifierKeys` (events after geometry's, before lifecycle's, reverse note order);
  the key is `$modkeys<depth>`, never a `StateTable` slot.
- `Window.currentModifiers` from `.modifiersChanged` and the modifiers of key, pointer,
  scroll, magnify and rotate events; `[]` on leaving key; dirties only when the last build
  held a scope.
- `InputFollowupsDemo.swift`: `inputFollowupsPad()` in its own function, one line in
  `CanvasDemo.swift`'s root column; `@Observable` model written only from input.

### 3.2 A finding on the way (`IF-N` item 3)

The first full run read 5 issues beyond the locked-screen sheets: test 3.6 (a window with
no scope was still dirtied — the input hook ends in an unconditional `setNeedsRedraw()`),
and 3.7/3.8 (a mis-aimed hover point in the test, and the same dirt). Cutting
`.modifiersChanged` out of the blanket dirt then reddened three `ColorSchemeTests`, which use
`flip(platform)` — a `.modifiersChanged` — as their poke into `window.onInput` and rely on
the dirt when `onInput` claims it. The shipped rule: a flags report dirties through
`currentModifiers`' guard, or when the app's `onInput` claims it. Pinned by 3.6 and the
three `ColorSchemeTests` together (`ColorSchemeTests` unedited).

### 3.3 Mutations (full unfiltered native suite each; committed first, restored from a copy,
`git status --short` clean after each; every run also carries the five locked-screen
`AppKitPresentationTests` sheet issues, listed below as the baseline)

| # | mutation (spelling, file) | reddened |
|---|---|---|
| M1 | drop `closeModifierKeys()` from the pending list (skip the drain), `Lifecycle.swift` | 3.1 `aModifierChangeRunsTheActionWithOldAndNewAfterTheBuild`, 3.2 `aMaskFiltersTheChange`, 3.3 `initialTrueReportsAtTheFirstFrameAndFalseDoesNot`, 3.4 `modifiersCanComeFromAKeyEventAlone`, 3.5 `leavingKeyReportsTheModifiersAsReleasedAndBecomingKeyTheCurrentOnes`, 3.6 `aWindowWithNoScopeIsNotDirtiedByAModifierChange`, 3.7 `aRemovedScopeStopsReporting`, `twoStackedScopesBothReport`, 3.8 `aStillPointerHoverSeesACommandPress` (the run ended with no summary line after 3121 tests, a macOS-SDL `exit(0)`-shaped end; the reddened list is from the issues recorded before it) |
| M2 | ignore the mask, `value: currentModifiers` | `aMaskFiltersTheChange` |
| M3 | invert `initial` | `initialTrueReportsAtTheFirstFrameAndFalseDoesNot`, `aRemovedScopeStopsReporting` |
| M4 | read `.modifiersChanged` only (key events ignored), `Window.swift` | `modifiersCanComeFromAKeyEventAlone` |
| M5 | remove the key-loss reset, `Window.swift` | `leavingKeyReportsTheModifiersAsReleasedAndBecomingKeyTheCurrentOnes` |
| M6 | always dirty on a modifier change, `Window.swift` | `aWindowWithNoScopeIsNotDirtiedByAModifierChange`, `aRemovedScopeStopsReporting` |
| M7a | share one key name, `ElementID("$modkeys0")` | **none — green, and correct**: the store key also holds an *occurrence* number, so two scopes at one position still get distinct keys; the depth in the name is belt and braces, not the separator. `twoStackedScopesBothReport` is therefore pinned by M1 only. |
| M7b | leak the store entry (do not clear `modifierCurrent` after the swap) | **green against the first 3.7**: the leak shows only on a third build with the scope gone. 3.7 now builds twice more with ⇧ held (`aRemovedScopeStopsReporting`); M7c, §3.4. |
| 3.9 | — | `aHeadlessRenderRunsNoModifierAction` is an invariance pin: `renderFrame` has no window and no drain and an empty held set reports nothing under `initial: true`, so no one-line mutation reddens it (`IF-N` item 5). |

### 3.4 M7c

M7c is M7b's spelling against the sharpened test. 3.7 now holds ⇧ across the removal
(the stale value of a leaked entry is the *masked value it last held*, which was empty in the
first draft, so the leak reported nothing), builds twice more with the scope gone, and expects
the return to report ⇧⌘. The mutated suite ran to a summary line: **3276 tests, 9 issues** =
the five locked-screen sheet issues plus four in `aRemovedScopeStopsReporting`
(`!window.needsRedraw` at 269, the three `log.entries` arms at 271, 278, 281). Unmutated, the
same test passes (10 `ModifierKeysTests` in a filtered run, and in the full run below).

## 4. Record phase

### 4.1 Suite

`swift test --build-system native --no-parallel`, unfiltered, at `eb08412`: **3276 tests in
3 suites** (3237 + 18 lane 1 + 11 lane 2 + 10 lane 3), `FR-J no-argument frame: succeeded=true`,
0 `error:`. Screen locked (lock probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`),
so the run reads **exactly the five `AppKitPresentationTests` sheet issues** (`CI-AF`) and
nothing else. The first lane-3 run read 13 issues (the five plus the 3.6–3.8 and
`ColorSchemeTests` findings of §3.2), the corrected run 5.

### 4.2 Counts, census, docs

- Public-API census re-recorded: `docs/probes/closeout-public-api.tsv` 3152 lines before the merge (3405 after, §4.4);
  `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. Inventory
  rows: families `input-followups-values` (D, 235), `input-followups-cancel` (D, 236),
  `input-followups-modkeys` (M); `ModifierKeysChange.swift` mapped.
- Human checks: group **IF** (IF1–IF7) in `docs/verification/human-checks.md`, **not run — an
  agent cannot**. CLAUDE.md gains the `IF-` rule paragraph and prefix; AGENTS.md is the
  copy.
- Divergences: 235 (a tap's modifiers and a drag's click count), 236 (a cancelled
  gesture's owner). `onModifierKeysChanged`'s SwiftUI timing is unprobed (the probe's `M`
  arms read "-" including their controls), so no label is spent; if human check IF1 shows a
  difference it takes 237 (`IF-K` 5).

### 4.3 Pixels

`docs/probes/demo-pixels/compare.sh <scratch> f2fe54a HEAD` (HEAD `fb2b81f`): **all fourteen
images `differing=0`, scene identical**; controls at `f2fe54a` as recorded (1048576, 1031003,
454895, 0, 1048576, 0, distinct 544 and 216, prod 491221, distinct 529, indicator rects 0).
The pad paints text from an `@Observable` model with initial values, but it is only in the
canvas demo (`METALUI_CANVAS_DEMO=1`), not in the fourteen. `swift build --build-tests`
(default build system): 0 `warning:` lines; native: SwiftPM's deprecation notice only. No
real-window capture (screen locked).

### 4.4 The merge with master `0abce86`

Master moved to `0abce86` (item 8's harness, §91, `HT-`; C15's overlays, §92, `OV-`).
Conflicts were documentation only: `CLAUDE.md`/`AGENTS.md` (the prefix list gained `IF-`
beside `HT-` and `OV-`, the human-check groups read "SG, HT, OV and IF", the counts
bullet is this branch's and master's follows), `docs/divergences.md` (225 beside 235, 236),
`docs/record/README.md` (rows 91, 92, 93), `docs/verification/human-checks.md` (IF after HT)
and both census files (the inventory map keeps both blocks; the census was regenerated, **3405
lines** = 3392 + 13). `Gesture.swift`, `SpatialGestures.swift` and `Window.swift` merged
without a conflict. After `swift package clean`: native build 0 `error:`, only SwiftPM's
deprecation `warning:`; `swift test --build-system native --no-parallel` unfiltered: **3402
tests in 3 suites** (master's 3363 + 39), 5 issues, exactly the five locked-screen
`AppKitPresentationTests` sheet issues; `FR-J no-argument frame: succeeded=true` present;
guards 215 (213 + lane 1's two). Not re-taken after the merge: `Backends/SDL` and the Linux
image (this branch's SDL files are `SDLBridge.c`, `SDLPlatform.swift` and one test; master
touched none), the fourteen images (master's `OverlaysDemo` is not among them; re-take at the
checker), lane 1's un-re-run mutations.

## 5. Deferrals and hazards

- `@GestureState`/`updating(_:body:)` not built (`IF-A`); a drag per button, lost-release
  detection for the primary arena, `modifiers` on other taps, a probe of AppKit's wheel
  latching and of `onModifierKeysChanged`'s timing: no owner (`IF-A`, no ruling).
- The merge-time checker should re-take lane 1's twelve un-re-run mutations and
  `Backends/SDL` (macOS and the `metalui-portable` image) after the lane 2 test edits; lane 3
  touches no `Backends/SDL` file.
- The mutation M1 run ended without a summary line (see §3.3): re-take it on the checker's
  machine unlocked. M7a is an equivalent mutant (the occurrence number separates keys).
- A `.modifiersChanged` poke into `window.onInput` is how three `ColorSchemeTests` reach
  their handler; anything changing that event's dirt reddens them (`IF-N` item 3).
