# 155. SDL precise scroll: `isPrecise` and scroll phases for a trackpad (item XP-G28)

Item XP-G28 of the gpui-gap priority list (user request 2026-10-02, MetalCreator's request of 2026-10-24, `docs/metalui-gaps.md` XP-G28; **not a plan task**), on `feat/sdl-precise-scroll` from `935d0096`, merged with master `6c6e039f` (§154 hung SDL test helpers) at the Record phase. Two lanes, both verified `ok`. Rulings `TP-A`..`TP-Q` in `docs/superpowers/2026-10-24-sdl-precise-scroll-decisions.md`; spec `docs/superpowers/specs/2026-10-24-sdl-precise-scroll-design.md` (Status: built, this record). **Numbering:** origin/master moved from `935d0096` to `6c6e039f` while the branch ran (§154 took 154); this record keeps 155, no renumbering was needed. Class `M`, `Backends/SDL` plus root tests and doc comments: **no seam change** (`ScrollEvent`, `InputPhase`, `PlatformWindow`, `Platform`, `WindowRenderer` untouched, no defaultless requirement, no migration note beyond one amended row), no root declaration, no census row, no shader, no `Package.swift` change, no pixel change. Divergences **845, 846** (847-854 unused). Human checks group `TP`.

## 1. What was built

Before: on SDL `ScrollEvent.isPrecise` was always `false` and `phase` always `.none` (`CI-I` item 6), so an app on Linux or Windows could not tell a two-finger trackpad scroll (pan) from a wheel (zoom), and `IF-G`'s latch never engaged. Now:

- **`SDLScrollClassifier`** (`Backends/SDL/Sources/MetalUISDL/SDLScrollClassifier.swift`, internal, pure, time injected). An event is *fractional* when `|v - v.rounded()| > 1e-4` on `x` or `y` (`TP-B`); it is precise when fractional or when a stream is open (`now < lastPreciseTime + 0.15`, `TP-C`); the first precise event after no open stream is `.began`, later ones `.changed`; a wheel (integral, no stream) stays `.none/.none/false`. Any event arriving at or after an open stream's deadline reports `closedStale` so the window delivers the old stream's `.ended` first (`TP-M`). The deadline is inclusive at both ends (`TP-P`).
- **`SDLWindow.handleWheel(dx:dy:timestamp:modifiers:position:)`** (internal): the `MUI_EVENT_WHEEL` arm calls it. `delta` is unchanged (lines times 10, `CI-I` item 1); only the three labels move. **`expireScrollStream(now:)`** delivers **one** zero-delta `.ended` (`isPrecise: true`, last position and modifiers) when the deadline passed; `SDLPlatform.expireScrollStreams(now:)` asks every window; `run()` waits `min(250, scrollWaitTimeoutMilliseconds(now:))` while any stream is open and calls the expiry every pass, with `mui_now()` the same clock as an event's timestamp (`TP-I`, `TP-P`). Focus loss and close drop the stream and emit nothing (`IF-H` owns the `.cancelled`).
- **`SDLScrollPrecision`** (public, `.automatic` default, `.disabled` = today's behaviour byte for byte) and `SDLPlatform.Options.scrollPrecision`, a defaulted last `init` parameter, in both `Options` declarations (the trait-off stub too, `TP-N`). MetalUI-only, class `M`, in `Backends/SDL` so outside the census (`GA-L`); doc comments on it.
- Doc comments on `ScrollEvent.phase`/`momentumPhase`/`isPrecise` (`Sources/MetalUIPlatform/InputEvent.swift`) replace "always on SDL" with the rules. **`Window` is not edited** (`TP-H`, `TP-Q`).

What SDL does not give, and so what this is not (`TP-A`, source of SDL 3.4.16 `fa2c02bb`, read here, no real trackpad in this environment): no device class on any platform (`which` is overwritten with the global id by `SDL_SendMouseWheel`), Wayland's `axis_source`/`axis_stop` bodies are `// unimplemented`, XI2 gives no stop, Windows inertia is the same message stream as the fingers. Touch-device lists, mouse names, `direction`, `integer_x/y` and hints are rejected with the cost of each (`TP-E`). **`isPrecise` is a heuristic over delta granularity; phases are synthesized; `.ended` is inferred and late; momentum stays `.none`** (divergences 845, 846, `TP-F`, `TP-G`).

## 2. Probe

`docs/probes/swiftui-scroll-precision.swift` (typecheck only): control exit 0 (`ScrollPhase`, `ScrollPhaseChangeContext`, `ScrollGeometry` compile); ARM_1 `no member 'isPrecise'` on the context; ARM_2 `no member 'onScrollWheel'`; re-run byte for byte by the critic. SwiftUI shows a view a scroll's phases and never the device class and has no per-view wheel hook, so **no SwiftUI claim is made** and neither divergence is a SwiftUI row: both differ from AppKit's meaning of the same MetalUI fields.

## 3. Tests

`Backends/SDL` (`SDLScrollClassifierTests.swift`, new, 17 Swift Testing functions; `SDLInputAPITests.swift` test 1.16 rewritten, count unchanged):
- Classifier, pure, no window, no sleep: `aWholeNotchIsNotPreciseAndOpensNoStream` (T1), `aFractionalEventIsPreciseAndBegins` (T2), `aSecondEventInsideTheQuietIntervalChanges` (T3), `anIntegralEventInsideAStreamStaysPrecise` (T4), `aNotchAfterTheQuietIntervalIsAWheelAgain` (T5), `anEventAfterTheDeadlineBeginsANewStreamAndReportsTheStaleEnd` (T6), `expireEndsAStreamExactlyOnceAtTheBoundary` (T7), `aHorizontalFractionIsPrecise` (T8), `aHiResWheelStepIsPreciseByDesign` (T9, characterizes divergence 845), `disabledModeIsTodaysBehaviour` (T10), `aNonFiniteDeltaIsNotPreciseAndDoesNotTrap` (T11, a **characterization pin, no mutation can redden it**: NaN and infinity compare false against the tolerance with no guard, `TP-M`), `resetDropsTheStreamWithoutAnEnd` (T12).
- Platform, injected times, `armMainRunLoopExitCheck()` through the helper, none needs a presented frame: `aPreciseStreamIsEndedOnceByExpiry` (P2), `aStaleStreamIsEndedBeforeTheNextBegan` (P3, received `[began, ended, began, ended, none]`), `closingOrLosingFocusDropsTheStreamWithoutEnded` (P4), `theIdleWaitShortensWhileAStreamIsOpen` (P5), `scrollPrecisionDisabledKeepsTheOldWheel` (P6); `sdlWheelNotchIsPhaselessAndAFractionBeginsAPreciseStream` (P1, a real pushed `MUI_EVENT_WHEEL`, `dy = -2` then `-0.25`, `delta.y == -2.5`; red before by behaviour).

Root (`Tests/MetalUITests/SDLShapedScrollWindowTests.swift`, new, 4 tests, **green on arrival by design**: `Window` is unchanged, they are the `TP-H` pins and are red only under the mutations below): `aSyntheticBeganLatchesTheCoverAndTheNextEventEndsOrReplacesIt` (W1, renamed, `TP-Q`), `aNotchDuringAPreciseStreamEndsTheLatch` (W2), `aPreciseSDLStreamScrollsAScrollViewByItsDelta` (W3), `aHandlerAboveAScrollViewVetoStillWorksForAPreciseStream` (W4). Guards: none new (no root public type; the trait-off stub compiles in the root build).

Counts: root **4445 -> 4449** (+4), typecheck guards unmoved (273); `Backends/SDL` macOS 304 -> 321 on the lane (+17), Linux image 300 -> 317; see section 6 for the merged tree.

## 4. Red runs and mutations

Red first: lane 1's commit `e5a10bdd` adds T1-T12 and P1-P6 over no implementation (a compile failure for the classifier arms, a behaviour failure for P1). Lane 2's W tests cannot be red before (the `Window` rule exists), so their proof is the mutation table. Lane 1: the implementer ran 22 mutations over T1-T12, P1-P6 and the stubs (the spec's named list) with `Backends/SDL` unfiltered on macOS (`METALUI_REQUIRE_GPU=1 --no-parallel`); the table of per-mutation reddened tests was **not carried into this record's inputs**, only the two the checker re-ran and the survivor below, which is stated rather than reconstructed. Lane 2: full unfiltered native suite per mutation (baseline the five locked-screen `AppKitPresentationTests` issues of `CI-AF`).

| Mutation (branch, spelling) | Reddened |
|---|---|
| T2 (checker, lane 1) `isFractional` always `false` | `aFractionalEventIsPreciseAndBegins`, `aHiResWheelStepIsPreciseByDesign`, `aHorizontalFractionIsPrecise`, `anEventAfterTheDeadlineBeginsANewStreamAndReportsTheStaleEnd` |
| T7a (checker, lane 1) `expire(at:)` `>` for `>=` | `expireEndsAStreamExactlyOnceAtTheBoundary` |
| P4b (implementer, lane 1) | **survived**: the draft asked `platform.expireScrollStreams` after `close()`, but a closed window leaves the platform's list, so the arm proved nothing; fixed by asking the closed window itself (`45a06f06`) |
| M1 (lane 2) `ScrollLatch.isGestureEvent` without `.changed` | W1 (2 issues), `aTrackpadScrollsMomentumGoesToTheElementItBeganOver`, `aNewBeganReplacesTheLatch`, `aLatchedScrollViewKeepsScrollingWhenThePointerLeavesIt` (checker re-ran W1 filtered: red) |
| M2 (lane 2) `advance` returns `false` on a finger `.ended` | only existing tests (`aTrackpadScrollsMomentumGoesToTheElementItBeganOver`, `leavingKeyMidScrollSynthesizesOneCancelledToTheHandler` x2, `theLatchEndsAtMomentumEndedAndAMayBeginLatchesNothing`): **no W test, by design**, unobservable from SDL (`TP-Q`) |
| M3 (lane 2) delete `applyScroll`'s `phase == .none` reset | W1, W2, `aWheelMouseIsNeverLatchedAndClearsTheLatch` |
| M4 (lane 2) handler-before-scroller order flipped within one id | **survived**: no public spelling gives a handler a scroller's own id (`CI-AH`), the veto is chain order |
| M5 (lane 2) any scroll region on the chain before any handler | W4 (3 issues) and six existing wheel tests |
| W3 (checker) `applyScroll` substitutes the latch's last delta on `.ended` | `aPreciseSDLStreamScrollsAScrollViewByItsDelta`, `aSyntheticBeganLatchesTheCoverAndTheNextEventEndsOrReplacesIt` |

Two spec mutations did not redden and the spec changed to what is real (`TP-Q`): "latch not cleared on `.ended`" (there is no such clear; AppKit's latch lives to the momentum's end and SDL has none, so the next event ends or replaces it) and "`.ended` requests no extra frame" (a zero-delta `scroll(_:by:)` still writes the offset and stamp). W3's own nonzero-repeat mutation was run by the checker (row above); the implementer's version was not.

## 5. Demo and pixels

No demo section, no new env var. `METALUI_INPUT_FOLLOWUPS`'s demo already prints `isPrecise` and phases, so on a Linux desktop it shows `precise` with `began`...`ended` for a trackpad and `wheel` for a notch (a look, group `TP`). Fourteen offscreen images **0 px** against `935d0096` (lane 2's `compare.sh`, scene-identical; the merged tree adds only `Backends/SDL` test files, docs and probes from master, so it is not re-taken). `DemoFrameDeterminismTests` `Expected.swift` unedited.

## 6. Verification on the merged tree

`swift package clean`, native build (`--build-system native --build-tests`) 0 `error:`, the only `warning:` SwiftPM's deprecation notice; native unfiltered `swift test --build-system native --no-parallel` on a **locked screen** (lock probe: `CGSSessionScreenIsLocked = 1`): **`Test run with 4449 tests in 11 suites`, 5 issues, exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else** (782 s, loaded machine); `FR-J no-argument frame: succeeded=true`; `swift build --build-tests` on the default build system 0 `warning:`. Typecheck guards 273, unmoved (no guard added). `Backends/SDL` on the merged tree: macOS `METALUI_REQUIRE_GPU=1 --no-parallel` **31 + 329** (304 at `935d0096` + master's 8 `SDLTestProcessGuardTests` + this branch's 17), Linux image (`metalui-portable`, offscreen driver) **31 + 325**. Inventory and undocumented scripts print nothing; the census was re-recorded (`closeout-public-api.tsv`, 3833 lines, 69 rows moved only in line number by the `InputEvent.swift` doc comments, no row added: `SDLScrollPrecision` is in `Backends/SDL`, outside the census). The fourteen images and `DemoFrameDeterminismTests` were taken at lane 2 against `935d0096` (0 px) and not re-taken on the merge. Windows and every real trackpad not run (group `TP`).

## 7. Hazards

- **A hi-res wheel reads precise** (Wayland `axis_value120`, Windows free-spin): no flag distinguishes it from a finger (`TP-D`, divergence 845); an app with such users sets `scrollPrecision: .disabled` or accepts a pan on that wheel.
- **`.ended` is late by up to 0.15 s plus one loop wake and a pause over 0.15 s inside one gesture splits it into two** (divergence 846). `quietInterval` is a ruling, **unmeasured on hardware**; check `TP1`-`TP3` log the real gaps.
- **A fast flick or Windows inertia is integral and still precise** only through the stream's stickiness; inertia arrives as precise `.changed`, with no momentum phase (`TP-G`).
- **`SDL_HINT_MOUSE_INTEGER_MODE`** makes SDL round for the app: every delta is integral and detection reads wheel (`TP-E`, documented).
- A stored property on a public type (`Options.scrollPrecision`) crossing a module boundary owes `swift package clean` before a suite.
- Every statement about what a desktop sends is a reading of SDL's source; **no real trackpad was available** (`TP-A`).

## 8. Deferrals, with owners

- **Real `axis_source`/`axis_stop` and XI2 flags** (`TP-L` 1): owner a later `TP-` item, trigger an SDL release that forwards them or MetalCreator evidence that the heuristic mis-reads real hardware (checks `TP`).
- **Momentum** (`TP-G`): a consumer applies its own; owner none.
- **A configurable `quietInterval`** (`TP-L` 3): only if `TP` measurements disagree with 0.15 s.
- **Windows precision-touchpad `WM_POINTER` gestures** (`TP-L` 4): SDL's loop does not expose them.
- Lane 1's per-mutation table (section 4): re-take `SDLScrollClassifierTests` and the platform arms under the spec's list if a later change touches the classifier (owner: the next change to `SDLScrollClassifier.swift`).
