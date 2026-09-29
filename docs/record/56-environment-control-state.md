# 56 — Environment: control state and scale (plan task 9, closing half)

Branch `feat/environment-control-state` from `e732d98`. Spec
`docs/superpowers/specs/2026-09-25-environment-control-state-design.md`;
rulings `EV-AA`…`EV-AF` appended to
`docs/superpowers/2026-09-15-environment-decisions.md`; probe
`docs/probes/swiftui-environment-control-state.swift`. §1–§3 are lanes 1–3's
own sections, written so their measurements were not lost before the Record
phase; §4 is the Record phase's independent close.

## 1. Lane 1 — the values

Commits: `7299051` (red tests), `1f5c221` (implementation).

### 1.1 Baseline

`e732d98`, worktree with its own `.build`: `swift build --build-system native
--build-tests`, then unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1490 tests in 3 suites passed`**; the log
carries `FR-J no-argument frame: succeeded=` (guards ran); the one `warning:`
SwiftPM's deprecation notice.

### 1.2 Red

`7299051` adds T1.1–T1.8 (`Tests/MetalUITests/EnvironmentScaleAndSizeTests.swift`),
extends E13 and G1+/G6, re-premises G3's doc and renames E19. The red reading
is a compile failure of the test target — 32 distinct error sites, of four
kinds: `value of type 'EnvironmentValues' has no member 'displayScale'`
(T1.1–T1.4, E13 ×3, E19′ ×3), `… 'controlActiveState'` (T1.8), `… 'controlSize'`
/ `value of type 'Text'|'TextField'|'ValueRecorder' has no member
'controlSize'` / `cannot find 'ControlSize' in scope` (T1.6, T1.7), and
`cannot convert value of type 'KeyPath<EnvironmentValues, V>' to expected
argument type 'WritableKeyPath<EnvironmentValues, V>'` at every
`.environment(\.displayScale|controlActiveState, _)` (T1.2, T1.4, T1.5, T1.8).
Each test's runtime red is the mutation its row names (§1.4).

### 1.3 The retained test that changed its answer (E19 rename row)

| removed name | new name | assertion that flipped | ruling |
|---|---|---|---|
| `aWholeValueWriteCannotResetTheThemeOrThePixelLength` | `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | both arms' `pixelLength == 0.5` → `displayScale == 1` and `pixelLength == 1` (pixel-length probe X2); theme half unchanged; new: the unscoped control reads `displayScale == 2` | `EV-AA` |

E13 (`theFramesRootEnvironmentCarriesItsThemeAndScale`) keeps every assertion
and gains three (`displayScale` 2 / 1 / 2 on its three arms).

### 1.4 Mutations

Each at `1f5c221`: committed first, the file restored from a copy, the full
unfiltered suite (1498) run, `git status --short` clean after each. Issue
counts are the summary line's.

| # | spelling | reddened | issues |
|---|---|---|---|
| M1.1 | `Frame.displayScale(forScaleFactor:)` returns 1 for a usable scale (the helper both stamps call) | `theRootDisplayScaleIsTheFramesScaleFactorAndThePixelLengthFollows`, `aScopeCanWriteTheDisplayScaleAndThePixelLengthFollows`, `aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses`, `theFramesRootEnvironmentCarriesItsThemeAndScale`, `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | 14 |
| M1.2 | `scopedValues` adds `values.displayScale = environmentTop.displayScale` after a transform | `aScopeCanWriteTheDisplayScaleAndThePixelLengthFollows`, `aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses`, `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | 9 |
| M1.3a | `pixelLength` = `1 / displayScale` | `aPixelLengthIsSwiftUIsFunctionOfTheDisplayScale` | 1 |
| M1.3b | `displayScale <= 0 ? 1 : 1 / displayScale` | `aPixelLengthIsSwiftUIsFunctionOfTheDisplayScale` | 1 |
| M1.4 | `Frame.fill`'s `bounds:` scaled by `Float(environmentTop.displayScale)` (mask, radii, borders left on `scaleFactor`) | `aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses`, `layoutRoundsToWholePointsWhateverTheDisplayScale` | 2 |
| M1.5 | `roundLayout` rounds all four edges to half points, `(v * 2).rounded() / 2` | 27 tests, §1.5 | 68 |
| M1.6 | `.controlSize(_:)` writes `.regular` | `controlSizeIsScopedByTheNearestWriter` | 2 |
| M1.7 | `Text.requestLayout` resolves its font at `fontSize * 0.7` under `.mini` | `controlSizeReachesNoBuiltInMeasurement` | 2 |
| M1.7b | (added: M1.7 leaves the `TextField` arm unmutated) the same in `TextField.requestLayout` | `controlSizeReachesNoBuiltInMeasurement` | 1 |
| M1.8 | bare `controlActiveState` default `.inactive` | `controlActiveStateIsKeyInABareValueAndAWindowlessFrameAndAScopeCanWriteIt` | 3 |
| M1.9 | the `rootEnvironment` setter stops re-stamping `displayScale` | `theFramesRootEnvironmentCarriesItsThemeAndScale` | 2 |
| M1.10 | `scopedValues` stops re-stamping `theme` | `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | 2 |
| MG1 | `var displayScale` (internal) | `environmentValuesAreReadableInEveryPhase`, `theEnvironmentsPublicWritersCompileFromOutsideTheModule` | 2 |
| MG3 | `pixelLength` gains `set { displayScale = 1 / newValue }` | `pixelLengthIsNotWritableFromOutsideButAWholeValueWriteCompiles` | 2 |
| MG6a | `public internal(set) var displayScale` | `theEnvironmentsPublicWritersCompileFromOutsideTheModule` | 1 |
| MG6b | `func controlSize(_:)` (internal) | `theEnvironmentsPublicWritersCompileFromOutsideTheModule` | 1 |

MG3 red with G3's `WritableKeyPath` expectation unchanged: the negative half's
message still names `WritableKeyPath` for a computed get-only property, so the
spec's "amend the expectation" branch was not needed. MG6a reddens G6 and not
G1+, so the pair separates read from write.

### 1.5 M1.5's reddened tests, by file

- **AXEmitSiteTests**: `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`
- **ContainerIntegrationTests**: `aZStackRootPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`, `overlayAndBackgroundContentIsPlacedAtThePrimarysSize`, `severalViewsInAnOverlayOrBackgroundAreACentredZStackPositionedByTheAlignment`
- **DemoFrameDeterminismTests**: `theDemoFrameMatchesTheValuesRecordedOnMacOS`
- **ElementLayoutTests**: `anExplicitAnyElementIsStillAcceptedAsAChild`, `columnStacksOnTheAxisRowDoesNot`
- **EnvironmentScaleAndSizeTests**: `layoutRoundsToWholePointsWhateverTheDisplayScale`
- **GlyphEmitterTests**: `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox`, `theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor`
- **GoldenReplacementFlexTests**: `equalGrowersShareTheLineAndAMaximumCapsItsGrower`
- **GoldenReplacementStackTests**: `aGrowFactorSumBelowOneStillFillsTheLine`, `aStackHugsItsLargestChildInsideARowAndAroundOne`
- **LoweringContainerTests**: `everyContainerFieldEitherLowersOrIsReportedByName`
- **LoweringDistributionTests**: `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit`
- **LoweringLeafTests**: `aLoweredTextLaysOutAndDrawsAtItsNaturalWidth`
- **LoweringScrollTests**: `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent`
- **NativeLayoutTests**: `nativeLayoutRoundsStoredRectanglesAfterFractionalPlacement`
- **NativeStackDistributionTests**: `aStackAnswersTheSumOfItsChildrensAnswers`, `aStackMeasuresItsCrossSizeAtItsAllocations`, `aZStackPlacesEachChildWithItsOwnSizeAsTheProposal`, `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`
- **PresentationLoweringTests**: `aFramesOwnBoundsOnAnAbsoluteAutoAxisAnswerAsSwiftUIsFrameDoes`
- **ProposalLayoutIntegrationTests**: `aProposalLayoutContainerRendersThroughTheFramePipeline`
- **RoundingTests**: `roundingHandlesTheMeasuredWebKitCase`, `roundingRoundsYIndependentlyOfX`, `roundingUsesCumulativeCoordinatesSoWidthsDoNotDrift`

No layout mutation that follows `displayScale` exists without plumbing the
scale into `MetalUILayout`, which this design does not do (`EV-AD`); a
half-point grid is the nearest stand-in and is what divergence 77's pin sees.

### 1.6 `MemoryLayout<EnvironmentValues>`

Before (`e732d98`): size 176, stride 176, alignment 8. After (`1f5c221`):
size 184, stride 184, alignment 8 — `+8`: one stored `Double` (`pixelLength`)
out and one (`displayScale`) in, plus the two one-byte enums, which spill into
one more 8-byte word. Measured with a throwaway filtered test printing the
three numbers, deleted after each reading. The gate is
`everyProductionTreeBuildsOnAOneMegabyteThread` (green on macOS; Windows CI on
push).

### 1.7 Exit

After `swift package clean` (a stored property left a public struct crossing a
module boundary): **`Test run with 1498 tests in 3 suites passed`** (1490 + 8),
guards ran (`FR-J no-argument frame: succeeded=`), 0 `error:`, the one
`warning:` SwiftPM's notice. Guards: 88, none added (G1+ and G6 extended).
`everyProductionTreeBuildsOnAOneMegabyteThread` and
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green in that run.

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> e732d98 1f5c221` —
controls at `e732d98` as the script's stage-9 correction records (light vs
dark 1048576, default vs modal 1031003, default vs animation 454895, f0 vs f3
0, preview light vs dark 1048576, chrome pair 0, distinct 544 / 216, prod
default vs modal 491221, distinct prod 529, indicator rects 0); **all fourteen
images `differing=0`, scene identical**.

**Real-window capture: not taken.** Lock probe at lane 1's end:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`. The probe's C arms
(`EV-AB`'s mapping) were not re-run for the same reason.

## 2. Lane 2 — the platform windows: SDL and AppKit

Commits: `cb1231f` (red tests), `e42dfdc` (implementation), `8418d43` (T2.1
strengthened after M2.3, below).

### 2.1 What landed

- `Backends/SDL/Sources/SDLBridge`: `MUI_EVENT_FOCUS_GAINED`,
  `MUI_EVENT_FOCUS_LOST` **appended** to the kind enum (no kind renumbers;
  `ReplayFixtureTests` 21 green); `translate` and `mui_push_event` arms;
  `mui_window_has_input_focus`; the test-only `mui_push_raw_window_event(sdl_type,
  window_id)` (refuses a type outside `SDL_EVENT_WINDOW_FIRST…LAST`) with the
  two SDL event types it needs exported as `mui_sdl_event_window_display_scale_changed`
  and `mui_sdl_event_window_pixel_size_changed` — the test module does not
  import SDL's headers, so it cannot name `SDL_EVENT_WINDOW_*` itself.
- `SDLPlatform`: one `focusedID` — seeded from `SDL_WINDOW_INPUT_FOCUS` when a
  window opens, set by an owned `GAINED`, cleared by `LOST` of that window and
  by closing it; `controlActiveState(of:)` spells §4's rule; states published
  once at the end of `pumpEvents()` (and after a window opens).
  `SDLWindow.controlActiveState` reads the platform (weak) and
  `onControlActiveStateChange` fires against a last-reported value.
- `AppKitWindow`: `static controlActiveState(isKeyWindow:isApplicationActive:)`;
  internal `keyStatus` (the live `isKeyWindow`/`NSApp.isActive` reads,
  assigned in `init` over the `NSWindow` local, so it captures no `self`);
  live `controlActiveState`; `onControlActiveStateChange`; selector observers
  for the window's `didBecomeKey`/`didResignKey` (object: its `NSWindow`) and
  the application's `didBecomeActive`/`didResignActive` on an internal
  `notificationCenter` (default `.default`; re-registering on assignment); an
  internal `refreshControlActiveState()` that re-reads and fires on a change,
  updating the last value whether or not a callback is set. **The test primes
  the last value through `refreshControlActiveState()`** with no callback set,
  so neither arm posts an application notification on the default center.

Neither conformer's pair is a `PlatformWindow` requirement yet (lane 3).

### 2.2 Red

Root, `swift build --build-system native --build-tests` at `cb1231f`: 16
distinct `error:` lines, all in `AppKitControlStateTests.swift` —
`value of type 'AppKitWindow' has no member 'notificationCenter'` / `'keyStatus'`
/ `'refreshControlActiveState'` / `'controlActiveState'` /
`'onControlActiveStateChange'`, and `type 'AppKitWindow' has no member
'controlActiveState'` (T2.5). `Backends/SDL`, `swift build --build-tests`
with `PKG_CONFIG_PATH=.accesskit`: 32 distinct `error:` lines in
`SDLControlStateTests.swift` — `cannot find 'MUI_EVENT_FOCUS_GAINED'` /
`'MUI_EVENT_FOCUS_LOST'` / `'mui_push_raw_window_event'` /
`'mui_sdl_event_window_display_scale_changed'` /
`'mui_sdl_event_window_pixel_size_changed'` in scope, `value of type
'SDLWindow' has no member 'controlActiveState'` / `'onControlActiveStateChange'`.
T2.3 and T2.6 pin pre-existing paths; their red is M2.7 and M2.12.

### 2.3 Mutations

Each committed first, applied by exact-string substitution to one site,
restored from a copy, `git status --short` clean after each. SDL mutations ran
the whole `Backends/SDL` suite (`ReplayFixtureTests` 21 passed each time, then
`MetalUISDLTests` 22); AppKit ones a native build and the full unfiltered root
suite (1501, one summary line each).

| # | mutation | reddened | issues |
|---|---|---|---|
| M2.1 | `focusedID == id ? .key : .inactive` | `focusEventsMakeAWindowKeyItsSiblingActiveAndNeitherInactive`, `focusTrackingIgnoresWindowsThePlatformDoesNotOwnAndForgetsAClosedOne` | 5 |
| M2.2 | the `FOCUS_LOST` arm `break`s | `focusEventsMakeAWindowKeyItsSiblingActiveAndNeitherInactive` | 4 |
| M2.3 | `publishControlActiveStateIfChanged` without its guard | at `e42dfdc`: `focusTrackingIgnoresWindowsThePlatformDoesNotOwnAndForgetsAClosedOne` alone (1); at `8418d43`: that and `focusEventsMakeAWindowKeyItsSiblingActiveAndNeitherInactive` | 3 |
| M2.4 | `GAINED` without `windows[id] != nil` | `focusTrackingIgnoresWindowsThePlatformDoesNotOwnAndForgetsAClosedOne` | 3 |
| M2.5 | `publishControlActiveStates()` after every `dispatch` | `focusEventsMakeAWindowKeyItsSiblingActiveAndNeitherInactive` | 2 |
| M2.6 | `MUI_EVENT_CLOSE` does not clear `focusedID` | `focusTrackingIgnoresWindowsThePlatformDoesNotOwnAndForgetsAClosedOne` | 1 |
| M2.7 | `translate` drops `SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED` | `aScaleOrPixelSizeChangeReachesOnResize` | 2 |
| M2.8 | both application-activation observers removed | `theAppKitWindowReportsKeyChangesThroughItsCallback` | 3 |
| M2.9 | `refreshControlActiveState` without its guard | `theAppKitWindowReportsKeyChangesThroughItsCallback` | 2 |
| M2.10 | `notificationCenter` defaults to `NotificationCenter()` | `theAppKitWindowReportsKeyChangesThroughItsCallback` (the wiring arm's line alone) | 1 |
| M2.11 | `!isApplicationActive → .inactive` first | `theAppKitMappingPutsKeyBeforeActiveBeforeInactive` | 1 |
| M2.12 | `viewDidChangeBackingProperties` stops calling `onGeometryChange` | `aBackingPropertiesChangeReachesOnResize` | 1 |

**M2.3 was a broken instrument until `8418d43`.** The spec named T2.1's logs
as its target, but every pump in T2.1 changes both windows' states, so an
unguarded callback writes exactly the guarded logs; only T2.2's foreign-id pump
(nothing changes, `calls == 0`) saw it. T2.1 gained one idle pump before the
log check; the re-run reddens both tests. The other SDL mutations were re-run
at `8418d43` with the same reddened sets.

### 2.4 Exit

Root: `swift build --build-system native --build-tests` then unfiltered
`swift test --build-system native --no-parallel`: **`Test run with 1501 tests
in 3 suites passed`** (1498 + 3), guards ran (`FR-J no-argument frame:
succeeded=`), 88 guards (none added). 0 `error:`; the only `warning:` under
native is SwiftPM's notice; the default build system's `swift build
--build-tests` printed no `warning:` or `error:`. `MetalUILayout` imports only
`MetalUICore`. `everyProductionTreeBuildsOnAOneMegabyteThread` and
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green in that run.

`Backends/SDL` on macOS (`PKG_CONFIG_PATH=.accesskit swift test`):
`ReplayFixtureTests` 21, `MetalUISDLTests` **22** (19 + 3). In a
`swift:6.4-noble` container (`metalui-portable-ax`, `linux/Dockerfile`, SDL's
offscreen driver, `--scratch-path` inside the container): 21 and **21** (18 +
3), the three new tests passing by name — so pushed focus events and raw
window events reach the platform on Linux too, and no window manager focused
a hidden window. The linker's `built for newer version 26.0` notes about
Homebrew's SDL3 and the `prohibited flag(s)` pkg-config note are
pre-existing, not this lane's.

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> e732d98 e42dfdc` —
controls as lane 1 read them (1048576, 1031003, 454895, 0, 1048576, 0, 544 /
216, 491221, 529, indicator rects 0); **all fourteen images `differing=0`,
scene identical**. (`8418d43` changes only an SDL test.)

**Real-window capture: not taken.** Lock probe at lane 2's end (13:54 PDT):
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`, `displayActive main:
0`. The probe's C arms were not re-run.

## 3. Lane 3 — the seam

Commits: `a52132a` (red tests), `d860bdb` (implementation).

### 3.1 What landed

- **Conformers, by grep before the requirement** (`(class|struct|actor|extension)
  … PlatformWindow` over `Sources`, `Tests`, `Backends/SDL`, `Experiments`):
  `AppKitWindow` (`Sources/MetalUIAppKit/AppKitPlatform.swift`), `SDLWindow`
  (`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`), `FakePlatformWindow`
  (`Tests/MetalUITests/Fakes.swift`) — the spec's three, no fourth.
- `PlatformWindow` requires `controlActiveState` and
  `onControlActiveStateChange`, no default.
- `Window`: `public private(set) var controlActiveState`, read from the
  platform window in `init`, its `didSet` guarded by `!=` then
  `setNeedsRedraw()`; the callback assigns it; `drawFrameIfNeeded` builds the
  root as `environment` with `controlActiveState` stamped over it before
  `frame.rootEnvironment = …`. `environment`'s doc now names **three** fields
  that are not the root's source (`theme`, `displayScale` — `pixelLength`
  derived — and `controlActiveState`), replacing the stale "`pixelLength` from
  the surface's scale factor"; the `onResize` hook's comment names it the
  backing-scale path.
- Fakes: the pair on `FakePlatformWindow` (default `.key`, so no existing test
  moved); `simulateControlActiveStateChange(to:)`, which fires on every call so
  `Window`'s own guard is what T3.1's no-op arm tests; `FakeRenderSurface.scaleFactor`
  (settable, returned by `nextFrame()`, so `beginFrame()`); and
  `simulateBackingScaleChange(to:)`, which sets both scales and fires `onResize`.
- Tests: `Tests/MetalUITests/WindowControlStateTests.swift` (T3.1–T3.3),
  `Tests/MetalUITests/ControlStateCompileGuards.swift` (T3.4, T3.5; 2
  `canTypecheck` lines). **T3.4 imports `MetalUIPlatform` itself**: its
  module is in `.build/<triple>/debug/Modules`, so `typecheckFile` sees it.

### 3.2 Red

`swift build --build-system native --build-tests` at `a52132a`: 10 `error:`
sites, all in `WindowControlStateTests.swift` — `value of type
'FakePlatformWindow' has no member 'controlActiveState'` /
`'simulateControlActiveStateChange'` / `'simulateBackingScaleChange'`, `value
of type 'Window' has no member 'controlActiveState'`, `value of type
'FakeRenderSurface' has no member 'scaleFactor'`. The guards, run alone with
that file set aside (and restored before the commit): T3.4 `without
succeeded=true` (the conformer without the pair compiled — no requirement
yet), failing its `#require`; T3.5 `read succeeded=false … value of type
'Window' has no member 'controlActiveState'`, failing its `#require`. Both
ran, not skipped.

### 3.3 Mutations

Each committed first (`d860bdb`), applied by exact-string substitution to one
site, restored from a copy, native build and the full unfiltered root suite
(1506, one summary line each), `git status --short` empty after each.

| # | mutation | reddened | issues |
|---|---|---|---|
| M3.1 | `Window.init` does not assign `onControlActiveStateChange` | `theWindowStampsItsPlatformsControlActiveStateAndAChangeRepaints` | 5 |
| M3.2 | `rootEnvironment.controlActiveState = controlActiveState` deleted | `theWindowStampsItsPlatformsControlActiveStateAndAChangeRepaints` (2), `aScopeWriteOfControlActiveStateWinsBelowItAndTheWindowsEnvironmentDoesNot` (2) | 4 |
| M3.3 | `controlActiveState`'s `didSet` without `guard … != oldValue` | `theWindowStampsItsPlatformsControlActiveStateAndAChangeRepaints` (the no-op arm) | 1 |
| M3.4 | the stamp written into `frame.rootEnvironment`, then `frame.rootEnvironment = environment` over it | as M3.2, the same four lines | 4 |
| M3.5 | `platformWindow.onResize = { _, _ in }` | `aBackingScaleChangeReachesTheDisplayScaleOnTheNextFrame` (3), `resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize` (4), `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows` (4) | 11 |
| M3.6 | `Frame(scaleFactor: platformWindow.scaleFactor, …)` | `aBackingScaleChangeReachesTheDisplayScaleOnTheNextFrame` (the separating arm's two lines) | 2 |
| MG7 | `extension PlatformWindow` defaulting both requirements | `aPlatformWindowWithoutTheControlActiveStatePairDoesNotCompile` | 1 |
| MG8 | `public var controlActiveState` on `Window` | `theWindowsControlActiveStateIsReadableButNotSettableOutsideTheModule` | 1 |

**M3.4 does not separate from M3.2**, and the spec's "(the second arm)" is
narrower than what it reddens: `Window.environment.controlActiveState` holds
the bare `.key` while the fake starts `.inactive`, so under M3.4 the first
root read of T3.1 and of T3.2 already sees `Window.environment` win, exactly
as with the stamp deleted. T3.2's `Window.environment` write arm (its last
root read, `:141`) is among the reddened lines, as named. No mutation of this
lane reddened nothing.

### 3.4 Exit

Root, after `swift package clean` (`Window` gained a stored property):
`swift build --build-system native --build-tests` then unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1506 tests in 3 suites
passed`** (1501 + 3 + 2), guards ran (`FR-J no-argument frame: succeeded=`,
and both new guards printed their `EV-AB` lines), **90 guards** (88 +
`ControlStateCompileGuards` 2). 0 `error:`; the only `warning:` under native
is SwiftPM's notice; the default build system's `swift build --build-tests`
printed no `warning:` or `error:`. `MetalUILayout` imports only
`MetalUICore`. `everyProductionTreeBuildsOnAOneMegabyteThread` and
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` passed in that run.

`Backends/SDL` on macOS (`PKG_CONFIG_PATH=$PWD/.accesskit swift test` in
`Backends/SDL`): `ReplayFixtureTests` 21, `MetalUISDLTests` 22 — `SDLWindow`
satisfies the new requirement with lane 2's public pair. In a
`swift:6.4-noble` container (`metalui-portable-ax`, repository at `/work`,
`--scratch-path /tmp/sb`): 21 and 21, passed.

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> e732d98 d860bdb` —
controls 1048576, 1031003, 454895, 0, 1048576, 0, 544 / 216, 491221, 529,
indicator rects 0; **all fourteen images `differing=0`, scene identical**.
`Expected.swift` unedited.

**Real-window capture: not taken.** Lock probe at lane 3's end (14:26 PDT):
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`, `displayActive main:
0`. The probe's C arms were not re-run; `EV-AB`'s key/active mapping stays
MetalUI's choice, owed that re-run.

## 4. The task's close (Record phase, 2026-09-25, PDT)

All three lane verdicts read `ok: true` (mutation tables above), so no
fix/re-verify round was owed (Practices: "Re-verify only on a finding"). Every
reading below was re-taken independently at `fb92808` (lane 3's own commit,
the branch tip), not copied from any lane's own claim.

### 4.1 Suite, guards, goldens

`swift package clean`, then `swift build --build-system native --build-tests`
and `swift build --build-tests` (default): both `Build complete!`, 0 `error:`
on either, the only `warning:` SwiftPM's own deprecation notice under native
(0 under the default). Unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1506 tests in 3 suites passed after 85.157
seconds`**, the log carrying `FR-J no-argument frame: succeeded=true
deprecations=2` (guards ran) and both new guard lines, `EV-AB pair required:
without succeeded=false …` and `EV-AB window state: read succeeded=true …
write succeeded=false …`. **Eleven** gated tests skipped, unchanged from
`e732d98` (ten `() skipped` lines plus the FreeType oracle's
`measure(file:)`, which prints without the empty parenthesis pattern).
**1506 = 1490 + 16**: lane 1's 8 (T1.1–T1.8; E13 extended and E19 renamed, not
added), lane 2's 3 (T2.4–T2.6, `AppKitControlStateTests`; T2.1–T2.3 are in
`Backends/SDL`, not the root count), lane 3's 3 tests + 2 guards
(T3.1–T3.3, `ControlStateCompileGuards`'s T3.4/T3.5).

`find Tests/MetalUILayoutTests -name "*.json" | wc -l` reads **0** (stage 7a;
unmoved — no `Sources/MetalUILayout` file is touched by this task). Guards:
`grep -c canTypecheck` per file across the nineteen files CLAUDE.md's "Guards"
bullet now names, plus `ControlStateCompileGuards` (new, T3.4/T3.5), sums to
**91** raw hits; less `UnitSafetyTests`' one comment-line hit gives **90 = 88
+ 2**, matching lane 3's §3.4 figure exactly. Both `ControlStateCompileGuards`
tests typecheck a whole-file `typecheckFile` fixture under a plain
`import MetalUIPlatform`/`import MetalUI` (T3.4 sees `MetalUIPlatform` under
`#filePath`'s layout, as the spec asked lane 3 to check), so the "two
helpers" split moves 40/48 → **40/50**.

**Retirement accounting (`goldensUnchanged`).** No test was deleted. **One**
retirement row (§1.3): E19 `aWholeValueWriteCannotResetTheThemeOrThePixelLength`
is renamed `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme`, its theme
half kept and its `pixelLength == 0.5` half flipped to `displayScale == 1`/
`pixelLength == 1` (`EV-AA`). Spot-checked: a grep for the old name in
`Tests/` returns zero hits; a grep for the new name returns exactly one, at
its declaration. E13 (`theFramesRootEnvironmentCarriesItsThemeAndScale`) kept
every assertion and gained three — a retained test that changed its answer by
gaining rows is not a retirement. No other retained test's answer moved.

### 4.2 Must-not-move greens

All read `passed` in the 1506-test run above:
`theSevenRetentionSlotsAreMutuallyDistinct`,
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`theDemoFrameMatchesTheValuesRecordedOnMacOS`. `StateTable`, `MC-A`/`MC-C`/
`MC-P` numbering, `.id()` outermost, hit testing, accessibility, animation,
focus, the scrim, `List` windowing and `TB-AH`, `Deferred`, `TextField`/
`TextEditor` are untouched by any lane's diff (no lane's file list names any
of their sources).

### 4.3 Pixels

`docs/probes/demo-pixels/compare.sh <scratch> e732d98 HEAD` (`HEAD` = `fb92808`,
a fresh scratch directory independent of every lane's own run): every control
at its recorded `e732d98` value (light vs dark 1 048 576, default vs modal
1 031 003, default vs animation 454 895, f0 vs f3 0, preview 1 048 576, chrome
pair 0, distinct 544/216, prod default vs modal 491 221, distinct
`prod-default-light` 529, indicator rects 0 in all twelve) and **all fourteen
images read `differing=0`, scene identical**, matching all three lanes' own
readings (§1.7, §2.4, §3.4). `Expected.swift`
(`DemoFrameDeterminismTests`) is unedited by any lane — no built-in element
reads `displayScale`, `controlActiveState` or `controlSize`, and the demo
sets none of them.

### 4.4 The probe, re-run

`docs/probes/swiftui-environment-control-state.swift` compiled
(`/usr/bin/swiftc … && OS_ACTIVITY_DT_MODE=1 …`) and filtered the same way as
its header: **49 lines, byte-identical to the header** (a `diff` against the
header, modulo the header's `// ` comment prefix and its extra two-space
indent, is empty) — V, S, C and Z alike. The lock probe (below) still reads
locked, so C1–C3/C5 still did not run; `EV-AB`'s mapping stays MetalUI's own
choice, unmeasured against SwiftUI's, exactly as every lane found it.

### 4.5 Elsewhere

- **`MetalUILayout` imports only `MetalUICore`**: anchored grep over
  `Sources/MetalUILayout/*.swift`'s `import` lines, no other hit — this task
  touches no file under `Sources/MetalUILayout`.
- **`Backends/SDL`** (`.accesskit` already fetched;
  `PKG_CONFIG_PATH=$PWD/.accesskit swift build --build-tests` then `swift
  test --no-parallel`): `Build complete!`, 0 `error:`, the only `warning:`
  the pre-existing SDL dylib deployment-target linker note (unrelated to this
  task): **`Test run with 21 tests` and `22 tests` passed**
  (`ReplayFixtureTests`, `MetalUISDLTests`), matching lane 2's and lane 3's own
  readings (§2.4, §3.4) exactly.
- **`swift:6.4-noble`** (Docker, aarch64, the `metalui-portable-ax` image),
  re-run independently over `git archive HEAD` (`fb92808`) rather than
  re-read any lane's own measurement: `swift build --build-tests
  --scratch-path /tmp/b` → `Build complete!`, 0 `error:`; `swift test
  --skip-build --scratch-path /tmp/b --filter
  'MetalUISDLTests|ReplayFixtureTests'` → **21 and 21 passed**
  (`ReplayFixtureTests`, `MetalUISDLTests`), the three new focus/scale tests
  (`focusEventsMakeAWindowKeyItsSiblingActiveAndNeitherInactive`,
  `focusTrackingIgnoresWindowsThePlatformDoesNotOwnAndForgetsAClosedOne`,
  `aScaleOrPixelSizeChangeReachesOnResize`) passing by name — pushed focus
  events and raw window events reach the platform on Linux too, matching lane
  2's and lane 3's readings (**21** on Linux against **22** on macOS, the gap
  being the one macOS-only `NSAccessibility` test the manifest already
  documents). Windows itself was not run locally (no Windows host in this
  environment); `root-windows` CI confirms it on push, unchanged by a task
  that touches only files already portable (`MetalUICore`, `MetalUIPlatform`,
  `Backends/SDL`).

### 4.6 Real window — still owed

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate
&& /tmp/lockstate`, run once more this phase: `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1`, `displayActive main: 0` — the screen was locked
throughout, as it was at all three lanes' own checks (§1.7, §2.4, §3.4).
`docs/probes/window-capture/capture.sh` was not run, and the probe's C arms
were not re-run. **This is not owed as a new debt**: it is the same
screen-locked condition every recent record section has been waiting on since
2026-09-23 (stage 6b), on the same machine, across every task since (record
§03's most recent sections) — this task adds two owed looks of its own to
that list, both requiring an unlocked screen and neither reachable any other
way:

- **The key/active mapping** (`EV-AB`): whether AppKit's `isKeyWindow` →
  `.key`, else `NSApp.isActive` → `.active`, else `.inactive` (and SDL's
  focus-based equivalent) agrees with SwiftUI's own mapping — the probe's C1
  (a window made key in an active app must read `key`), C2/C2′ (switching key
  windows), C3/C3′ (hiding/unhiding the app) and C5 (a non-activating panel)
  arms, all unmeasured because no window has become key or the app active in
  a locked session (§2 of the spec).
- **A `displayScale` change from moving the window between displays**: pinned
  today only through the fakes (`simulateBackingScaleChange`, T3.3) and a
  synthetic raw-event push (T2.3); no lane's suite drags a real window across
  two displays of different backing scale.

### 4.7 Not done, owners already assigned

- **`controlActiveState` has no built-in consumer** (no MetalUI control dims
  in an inactive window): owner **plan task 12**, with the disabled look
  (`EV-AB`, `EV-Q`).
- **`controlSize` reaches no built-in measurement (divergence 76)**: a
  `Text`'s default font is owner **plan task 11** ("font metrics … dynamic
  type response"); `TextField`/`TextEditor`/`Button` and the other common
  controls are owner **plan task 10** ("common controls"). Both wait on
  `controlSizeReachesNoBuiltInMeasurement` (T1.7) as their pin (`EV-AC`).
- **Layout rounds to whole points, not the `displayScale` pixel grid
  (divergence 77)**: owner **plan task 11** (rendering-facing semantics,
  `EV-AD`). Moving it moves every fractional layout's pixels, the demo's
  images and `Expected.swift` — out of scope here by design.
- **SDL's drawable scale is pixel density, not the system's content/UI
  scale** (at 150% on Windows/X11 `displayScale` reads 1 while the system
  scale is 1.5): owner **plan task 14** (platform completeness), named as a
  platform limit rather than a defect (`EV-AA` amended by `EV-AF` finding 7).
- **The real-window capture and the probe's C1–C3/C5 arms**: owed to a human
  with an unlocked screen (§4.6). No owner beyond "whoever next has an
  unlocked session on this machine" — the same shape as stage 6b's and task
  8's still-open real-window debt.
- **`EV-Q`'s other rows are unaffected**: following the system's layout
  direction/locale and locale changes while running stay **plan task 14**; a
  `locale` consumer stays unowned; every row not naming `displayScale`,
  `controlActiveState` or `controlSize` is untouched by this task (`EV-AE`).

### 4.8 Docs updated to match this close

`docs/superpowers/specs/2026-09-25-environment-control-state-design.md`'s
Status line gains a Record-phase close paragraph (DELIVERED); `CLAUDE.md`/
`AGENTS.md` gain: the `EV-` prefix line's next-unused letter (`EV-AG`, already
moved by lane 3 in the decisions doc itself), the intro sentence's
`PlatformWindow` no-default pair, a new "Counts" bullet, the "Guards" bullet's
new file and helper split, the rewritten "Environment (`EV-`)" paragraph
(`displayScale` writable and derived `pixelLength`, `controlActiveState` from
the platform pair stamped by `Window`, `controlSize` carried, three
`Window.environment` fields not the root's source), the Known-divergences
bullet (24 retires, 76 and 77 add, 55 → 56 live), the Declared-but-inert
bullet (`controlActiveState`, `controlSize`, `displayScale` rows with their
owners) and the Human-verification bullet (the two new owed looks, §4.6);
record §04 gets a new dated section (24 retires, 76/77 add); record §05 gets
a new dated section (three rows added, none deleted); record §03 gets a new
dated section (no new look shown — 0 px — but two new looks owed, distinct
from stage 6b's); `docs/record/README.md` gains this file's row; the plan's
task 9 entry gets a dated progress note and its checkbox moves — both
clauses of the 2026-09-15 progress note (control state, scale) have landed,
per `EV-AE`'s own test; the accessibility-bridge decisions doc's and spec's
stale "task 9" citations (written when the interaction work was numbered
task 9) are re-pointed to task 12 or task 10 as `EV-AE`/`EV-AF` disposed them;
the root README gets the divergence count and the task 9 summary line
corrected.
