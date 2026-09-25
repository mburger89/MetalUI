# Environment: control state and scale (design)

Plan task 9 of
[`../plans/2026-09-12-swiftui-alignment.md`](../plans/2026-09-12-swiftui-alignment.md),
its unfinished half. The 2026-09-15 progress note says the box ticks "when
control state and scale land, or when this text is amended to drop them".
**This design lands both**: `displayScale` (the "scale"), and
`controlActiveState` and `controlSize` (the "control state" apart from the
enabled state `.disabled` already delivers). Branch
`feat/environment-control-state` from `e732d98`. Rulings **`EV-AA`…`EV-AE`**,
appended to the existing
[`../2026-09-15-environment-decisions.md`](../2026-09-15-environment-decisions.md);
record `docs/record/56-environment-control-state.md` (Record phase); SwiftUI
evidence in `docs/probes/swiftui-environment-control-state.swift` (new, arms
V, S, C, Z; output in its header), plus a re-run of
`swiftui-environment-pixel-length.swift` (V, X byte-identical to its header).

**Status, 2026-09-25: DESIGNED.** No lane has run.

## Contents

1. Baseline
2. What SwiftUI does (the probe)
3. API
4. Where each value comes from, and how a change reaches the frame
5. What is kept, what flips, and the new divergences
6. Lanes (three), every test with its red and its mutation
7. Accounting, pixels, gates
8. For the Record phase
9. Risks

## 1. Baseline (`e732d98`)

Per the brief: `swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel` unfiltered →
**`Test run with 1490 tests in 3 suites`**, 0 `error:`, the only `warning:`
SwiftPM's deprecation notice; **88 typecheck guards**; no goldens (stage 7a).
Lane 1 re-takes this before its first edit and states the reading.

The screen was **locked** throughout the design session
(`appkit-screen-lock-state.swift`: `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1`), which is why probe arms C1–C3/C5 did not run (§2).

## 2. What SwiftUI does (the probe)

`docs/probes/swiftui-environment-control-state.swift`, macOS 27.0, one 2x
display, compiled and interpreted forms byte-identical. Readings used below
(full output and reading in the header):

| arm | reading | used by |
|---|---|---|
| V0 | bare `EnvironmentValues()`: `displayScale` 1, `controlActiveState` **`key`**, `controlSize` `regular` | `EV-AA`, `EV-AB`, `EV-AC` |
| V1 | `pixelLength` is `1 / displayScale`, **except 0 → 1**; −1 → −1, NaN → NaN, ∞ → 0; no write rejected | `EV-AA` |
| S0 | hosted: `displayScale` = `backingScaleFactor` (2.0) | `EV-AA` |
| S1 | `ImageRenderer` scale 1 → reader reads 1; the same renderer set to 3 and re-rendered → 3: the host's **rendering** scale is the source, and a change reaches the reader on the next render | `EV-AA` |
| S2 | `.environment(\.displayScale, 1 / 3)` → read 1 / 3, `pixelLength` 1 / ⅓ | `EV-AA` |
| S3 | at renderer scale 2, a `frame(width: pixelLength)` hairline is 1 device px (control), **2 px under `displayScale = 1`**, 1 px under 3: a write changes the number, **not** the scale drawing uses | `EV-AA` |
| S4 | layout rounds absolute positions to the **`displayScale` pixel grid**, and follows a write (62.65 → 63 / 62.5 / 62.667 at 1 / 2 / 3) | `EV-AD` |
| X0–X2 (re-run) | `\.self` reset in a 2x window reads `displayScale` 1, `pixelLength` 1 | `EV-AA` |
| C0 | app **not active**: every hosted reader reads `inactive` (bare value: `key`) — the host stamps it | `EV-AB` |
| C4 | a scope write `.key` is read beside an unscoped `inactive`, and survives each step | `EV-AB` |
| C1–C3, C5 | **did not run**: screen locked, no window became key, the control (C1 must read `key`) never moved | `EV-AB` (the mapping is MetalUI's choice, owed a re-run) |
| Z1 | `.controlSize(_:)` and `.environment(\.controlSize, _)` write it; nearest writer wins | `EV-AC` |
| Z2 | a `Text`'s **default** font follows it: 53×11 / 63×14 / 72×16 / 72×16 / 72×16 (mini…extraLarge; control 26 pt 130×30); an explicit `.font(.system(size: 13))` or `.font(.body)` under `.mini` stays 72×16 | `EV-AC` (divergence 76) |
| Z3 | `TextField` height 19 / 21 / 24 / 24 / 24; `Button` 30×13 … 55×36 | `EV-AC` (divergence 76) |

## 3. API

In `MetalUICore` (new file `ControlActiveState.swift`, beside `LayoutDirection`
and `Appearance`, so `MetalUIPlatform` and `Backends/SDL` can name it):

```swift
/// SwiftUI's `ControlActiveState` (ruling EV-AB).
public enum ControlActiveState: Sendable, Hashable, CaseIterable {
    case key, active, inactive
}
```

In `MetalUI`, `EnvironmentValues`:

```swift
public var displayScale: Double = 1            // EV-AA: public, writable
public var pixelLength: Double {               // EV-AA: now DERIVED, get-only
    displayScale == 0 ? 1 : 1 / displayScale   // V1, verbatim
}
public var controlActiveState: ControlActiveState = .key   // EV-AB (V0)
public var controlSize: ControlSize = .regular              // EV-AC (V0)
```

`pixelLength` stops being a stored `public internal(set) var` — **a stored
property removed from a public struct crossing a module boundary: `swift
package clean` after lane 1.**

```swift
/// SwiftUI's five control sizes (ruling EV-AC).
public enum ControlSize: Sendable, Hashable, CaseIterable {
    case mini, small, regular, large, extraLarge
}
```

In `EnvironmentScope.swift`'s `extension ElementGroup`, beside
`.dynamicTypeSize(_:)` and spelled the same way:
`public func controlSize(_ size: ControlSize) -> EnvironmentScope<Self>`.

In `MetalUIPlatform`, `PlatformWindow` gains a pair, **with no default
implementation** (AB-R's reason: a conformer that forgets one fails to compile
rather than compiling into a window whose controls never learn it lost key):

```swift
/// The window's key state (ruling EV-AB). Read at window construction and
/// re-read on every `onControlActiveStateChange`.
var controlActiveState: ControlActiveState { get }
/// Fired with the new value when the key state changes — a passed value, for
/// `onAppearanceChange`'s reason.
var onControlActiveStateChange: ((ControlActiveState) -> Void)? { get set }
```

`Window` gains `public private(set) var controlActiveState: ControlActiveState`
(its root's source; `didSet` guarded by `!=`, then `setNeedsRedraw()`).

**No new `PlatformWindow` requirement for the scale**: the frame's scale is
already `renderer.beginFrame()`'s, and a backing change already fires
`onResize` on both platforms (§4).

## 4. Where each value comes from, and how a change reaches the frame

| value | root source | reaches the next frame by | a scope can write it? | re-stamped after a write? |
|---|---|---|---|---|
| `displayScale` | `Frame`'s `scaleFactor` (the drawable's, from `WindowRenderer.beginFrame()`), stamped in `Frame.init` and by the `rootEnvironment` setter; 1 when not finite and positive (the existing guard, moved from `pixelLength`) | AppKit: `viewDidChangeBackingProperties` → `syncSurfaceGeometry` → `onResize` → `Window.setNeedsRedraw()` (pre-existing). SDL: `DISPLAY_SCALE_CHANGED`/`PIXEL_SIZE_CHANGED` → `MUI_EVENT_RESIZE` → `onResize` (pre-existing). Headless: `renderFrame(scaleFactor:)` | **yes** (S2) | **no** — `EV-U`'s `pixelLength` half is withdrawn (`EV-AA`) |
| `pixelLength` | derived from `displayScale` | with it | no (get-only; G3 stands) | — |
| `controlActiveState` | `Window.controlActiveState`, stamped by `Window.drawFrameIfNeeded` over `Window.environment` before `frame.rootEnvironment = …`; a windowless `Frame` and `renderFrame` keep the bare `.key` (V0) | `PlatformWindow.onControlActiveStateChange` → `Window.controlActiveState`'s guarded `didSet` → `setNeedsRedraw()` | **yes** (C4) | no |
| `controlSize` | `Window.environment` (bare `.regular`) | an ordinary `Window.environment` write | **yes** (Z1) | no |
| `theme` | unchanged (`EV-G`, `EV-U`) | unchanged | only `.theme(_:)` | yes, unchanged |

**Why the window stamps `controlActiveState` and not `Window.environment`.**
`Window.environment`'s `didSet` dirties on every write, a no-op included
(`EV-H`); the platform reports key changes that are often no change for the
window (an app activation with the window already key reads the same state),
and an enum is `Equatable`, so the window keeps its own guarded copy, as
`theme` does, and stamps it at draw. So `window.environment.controlActiveState
= .key` changes nothing at the root, the same shape as `theme` and
`displayScale`: **three fields of `Window.environment` are not the root's
source** (the doc says two today, and names `pixelLength`).

**Platform mapping (MetalUI's choice, `EV-AB`; SwiftUI's is unmeasured, §2).**
AppKit: `isKeyWindow` → `.key`; else `NSApp.isActive` → `.active`; else
`.inactive`; re-read on `windowDidBecomeKey`/`windowDidResignKey` (the window
is already its own delegate) and on `NSApplication.didBecomeActive`/
`didResignActive`, firing the callback only when the read differs from the last
reported. SDL: this window has keyboard focus → `.key`; another window of the
same `SDLPlatform` has it → `.active`; none → `.inactive` (SDL has no
application-activation state apart from window focus on the desktop).
Tracked from `SDL_EVENT_WINDOW_FOCUS_GAINED`/`LOST`, flattened as two new
`MUI_EVENT_*` kinds **appended** to the enum (no existing kind renumbers, so
replay fixtures are untouched); the initial value from
`SDL_GetWindowFlags(...) & SDL_WINDOW_INPUT_FOCUS`.

**Dirtying.** Every source dirties through an existing guarded path or a new
guarded one: no phase writes any of these values, and none keeps the display
link awake.

## 5. What is kept, what flips, and the new divergences

- **Divergence 24 retires** (`EV-AA`): `displayScale` is exposed and writable,
  `pixelLength` derives from it, a scope write moves both (X1/S2), a `\.self`
  reset reads 1 and 1 (X2), and a write changes the number and not the scale
  drawing uses — which S3 shows is SwiftUI's own behaviour, not a MetalUI-only
  hazard. The label joins the retired list (never reused).
- **One retained test changes its answer, by ruling `EV-AA`**:
  E19 `aWholeValueWriteCannotResetTheThemeOrThePixelLength` is **renamed**
  `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme`; its theme half is
  kept, its `pixelLength == 0.5` half flips to `displayScale == 1` and
  `pixelLength == 1` (X2). `EV-J`'s "Cost if wrong" named exactly this flip.
  The rename owes a row in record §56 (removed name → new name, the assertion
  that flipped, the ruling).
- **Divergence 76 (new, pinned wrong on purpose)**: `controlSize` reaches no
  built-in measurement. SwiftUI's `Text` default font follows it (Z2; an
  explicit font does not, Z2e/f), and so do `TextField` and `Button` (Z3);
  MetalUI's `Text` stores `fontSize = 13` with no "default font" state
  (`Text.swift:81`), so following Z2 needs a text-model change, and
  `TextField`/`TextEditor` derive their height from their font. Owners: plan
  task 11 (`Text`'s default font — "font metrics … dynamic type response"),
  plan task 10 (`TextField` and the common controls). **Label 75 is skipped**:
  record §04's closeout note tells a reader looking for 75 that it was closed,
  not numbered, and reusing it would contradict that note.
- **Divergence 77 (new, found by S4, pinned wrong on purpose)**: layout rounds
  every stored rect to **whole points** (`roundLayout`), whatever the scale;
  SwiftUI rounds to the `displayScale` pixel grid and follows a write. Not
  changed here: moving it moves every fractional layout's pixels, the demo's
  images and `Expected.swift`. Owner: plan task 11 (rendering-facing
  semantics). A `displayScale` write therefore changes no MetalUI layout.
- **`controlActiveState` has no built-in consumer** (MetalUI's controls do not
  dim in an inactive window; SwiftUI's look there is unprobed): stated as a
  consumer-less value, owner plan task 12 (with the disabled look). Not a
  numbered divergence, since SwiftUI's side is unmeasured.
- **Kept, untouched**: `StateTable`, `theSevenRetentionSlotsAreMutuallyDistinct`
  (no new reserved name), `MC-A`/`MC-C`/`MC-P` numbering, `.id()` outermost,
  hit testing, accessibility, animation, focus, the scrim, `List` windowing and
  `TB-AH`, `Deferred`, `TextField`/`TextEditor`. No id path changes.
  `theme`'s re-stamp (`EV-U`'s first half) and `EV-Z`'s trap are unchanged.
- **`PaintPass`'s "exposes no `scaleFactor`" doc is amended, not the rule**:
  `pass.environment.displayScale` now reveals the scale as a writable value,
  as SwiftUI's does, and `fill` still takes points and scales by the
  **frame's** factor, not the environment's (T1.4 pins that). `pass.frame`
  stays unreachable (`theFrameBehindAPassIsNotReachableFromOutsideTheModule`).

## 6. Lanes

**Three lanes, run in this order, each on disjoint files, each leaving both
build systems and `Backends/SDL` green.** The order is what keeps them green:
lane 2 gives `SDLWindow` the two members before lane 3 makes them a
requirement, and lane 1 puts `ControlActiveState` in `MetalUICore` for both.
Each lane: red first (commit the failing tests, record the red reading),
implement, run the full unfiltered suite, run its mutations (commit first,
restore from a copy, full unfiltered suite, `git status --short` after each,
name every test reddened), and replace each ruling's "Mutations: owed by lane
N" line with what ran.

### Lane 1 — the values (Opus)

**Files**: new `Sources/MetalUICore/ControlActiveState.swift`;
`Sources/MetalUI/EnvironmentValues.swift`, `EnvironmentScope.swift`,
`Frame.swift` (root stamp of `displayScale`; `scopedValues` drops the
`pixelLength` re-stamp and keeps `theme`'s; `rootEnvironment` re-stamps
`theme` and `displayScale`), `Passes.swift` and `RenderFrame.swift` (doc
comments only); `Tests/MetalUITests/EnvironmentTests.swift` (E13, E19),
`EnvironmentCompileGuards.swift` (G1+, G3's doc, G6), new
`Tests/MetalUITests/EnvironmentScaleAndSizeTests.swift`. Not `Window.swift`
(its stale `pixelLength` doc is lane 3's).

| # | test | asserts | red before | mutation that must redden it |
|---|---|---|---|---|
| T1.1 | `theRootDisplayScaleIsTheFramesScaleFactorAndThePixelLengthFollows` | frames at scale 1, 2, 3 read `displayScale` 1/2/3 and `pixelLength` 1/0.5/⅓ at the root in all three phases; scale 0 and NaN frames read 1 and 1; `renderFrame(scaleFactor: 3)` reads 3 | does not compile at `e732d98` (no member); runtime red under M1.1 | **M1.1** the root stamps `displayScale = 1` (also reddens E13) |
| T1.2 | `aScopeCanWriteTheDisplayScaleAndThePixelLengthFollows` | in a scale-2 frame, readers under `.environment(\.displayScale, 3)` and `1` read 3/⅓ and 1/1; an unscoped sibling reads 2/0.5 (S2, X1) | as T1.1; runtime red under M1.2 | **M1.2** `scopedValues` re-stamps `displayScale` from the top after a transform (the withdrawn `EV-U` shape; also reddens E19′) |
| T1.3 | `aPixelLengthIsSwiftUIsFunctionOfTheDisplayScale` | on bare values: 1→1, 4→0.25, 0→**1**, −1→−1, NaN→NaN, ∞→0 (V0, V1) | as T1.1 | **M1.3a** `1 / displayScale` with no 0 case (0 → ∞); **M1.3b** a clamp of non-positive scales to 1 (the −1 row) |
| T1.4 | `aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses` | a leaf that `pass.fill`s a rect `pixelLength` wide, in a scale-2 frame: the scene rect is 1 device px wide with no write and **2 px** under `.environment(\.displayScale, 1)`; `try #require` that the two disagree first (S3) | as T1.1 | **M1.4** `Frame.fill` scales by `environmentTop.displayScale` instead of `scaleFactor` (both arms read 1 px) |
| T1.5 | `layoutRoundsToWholePointsWhateverTheDisplayScale` | **divergence 77, pinned wrong on purpose**: `HStack(spacing: 0) { Rectangle(width: 10.3); leaf }` placed at an **integral** origin in a scale-2 frame (a leading-aligned greedy frame, so root centring, `CN-J`, cannot make the origin fractional; the lane derives every literal from the tree before the run) puts the leaf at x 10 from that origin under writes of 1, 2, 3 (SwiftUI at an integral origin, by S4's rule: 10 / 10.5 / 10.333); control: a 10.6-wide leader puts it at 11 | green at `e732d98` except that it names `displayScale` (does not compile); it is a pin, and its red is the mutation | **M1.5** `roundLayout` rounds to half points (`(v * 2).rounded() / 2`) — reddens T1.5 (10.5) and others; name them |
| T1.6 | `controlSizeIsScopedByTheNearestWriter` | default `.regular`; `.controlSize(.small)` reads small; `.controlSize(.large)` inside it reads large; `.environment(\.controlSize, .mini)` reads mini (Z1); all three phases | does not compile | **M1.6** `.controlSize(_:)` writes `.regular` whatever its argument |
| T1.7 | `controlSizeReachesNoBuiltInMeasurement` | **divergence 76, pinned wrong on purpose**: a `Text`'s ideal and broken measurements under `.mini`, `.small` and `.extraLarge` equal the bare ones (SwiftUI Z2: 53×11, 63×14 vs 72×16); a `TextField`'s measured height under `.mini` equals `.regular`'s (Z3: 19 vs 24); control: `font(size: 26)` measures differently, `#require`d first | does not compile | **M1.7** the lowered `Text` measures at `fontSize * 0.7` under `.mini` |
| T1.8 | `controlActiveStateIsKeyInABareValueAndAWindowlessFrameAndAScopeCanWriteIt` | `EnvironmentValues().controlActiveState == .key`; a `frame()` reader and a `renderFrame` reader read `.key` (V0); a reader under `.environment(\.controlActiveState, .inactive)` reads inactive beside a `.key` sibling (C4) | does not compile | **M1.8** the bare default is `.inactive` |
| E13 (kept, extended) | `theFramesRootEnvironmentCarriesItsThemeAndScale` | gains `displayScale == 2` beside `pixelLength == 0.5`, and the overwritten root re-stamped to 2 | — | M1.1; **M1.9** the `rootEnvironment` setter stops re-stamping `displayScale` (the overwrite arm reads 1) |
| E19′ (renamed) | `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | both arms (`\.self` reset; captured scale-1 snapshot written back) read `displayScale` 1, `pixelLength` 1, and still paint dark; control: `probe` 0 vs 3 as today; an unscoped sibling reads 2 | the old name's `pixelLength == 0.5` is what flips | M1.2; **M1.10** `scopedValues` stops re-stamping `theme` (the theme half) |
| G1+ (extended) | `environmentValuesAreReadableInEveryPhase` | reads `displayScale`, `controlActiveState`, `controlSize` in every phase and `@Environment(\.displayScale)` | — | **MG1** `displayScale` made `internal` |
| G6 (extended) | `theEnvironmentsPublicWritersCompileFromOutsideTheModule` | `.environment(\.displayScale, 3)`, `.environment(\.controlActiveState, .inactive)`, `.environment(\.controlSize, .mini)`, `.controlSize(.small)`, `e.displayScale = 3`, `e.controlActiveState = .active`, `e.controlSize = .large`, `ControlSize.allCases`, `ControlActiveState.allCases` | — | **MG6a** `displayScale` `public internal(set)` (G6 red, G1+ green: the pair separates read from write); **MG6b** `.controlSize(_:)` internal |
| G3 (kept) | `pixelLengthIsNotWritableFromOutsideButAWholeValueWriteCompiles` | unchanged assertions; its doc now says the `\.self` premise is aligned (X2), not re-stamped. **Verify the negative half's message still contains `WritableKeyPath` for a computed get-only property**; if not, amend the expectation with a note in `EV-AA` | — | **MG3** `pixelLength` given a public setter (negative half red) |

**Lane 1 exit**: 1490 + 8 = **1498 tests**, 88 guards (two extended, none
added); `swift package clean` taken before the count (the stored
`pixelLength` went away).

### Lane 2 — the SDL window (Opus)

**Files**: `Backends/SDL/Sources/SDLBridge/include/SDLBridge.h` and
`SDLBridge.c` (`MUI_EVENT_FOCUS_GAINED`, `MUI_EVENT_FOCUS_LOST` appended;
`translate` and `mui_push_event` arms; `mui_window_has_input_focus(void *)`);
`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift` (`SDLWindow`'s public
`controlActiveState` and `onControlActiveStateChange`; `SDLPlatform` tracks the
focused window id from the two events and recomputes every window's state,
firing only on change); new `Backends/SDL/Tests/MetalUISDLTests/SDLControlStateTests.swift`.
The members are declared **before** `PlatformWindow` requires them (lane 3),
so this lane compiles against `e732d98`'s protocol. Build and test with
`PKG_CONFIG_PATH=$PWD/.accesskit` (CLAUDE.md).

| # | test | asserts | red before | mutation |
|---|---|---|---|---|
| T2.1 | `focusEventsMakeAWindowKeyItsSiblingActiveAndNeitherInactive` | two hidden windows start `.inactive` (`try #require`: a hidden window has no focus); push `FOCUS_GAINED(A)` + pump → A `.key`, B `.active`; `FOCUS_LOST(A)`, `FOCUS_GAINED(B)` → A `.active`, B `.key`; `FOCUS_LOST(B)` → both `.inactive`; each window's callback log equals its state sequence exactly (no call for an unchanged state) | does not compile | **M2.1** "another window focused" maps to `.inactive` (the `.active` arms); **M2.2** `FOCUS_LOST` ignored (the last arm); **M2.3** the callback fires without the change guard (the logs) |
| T2.2 | `aFocusEventForAWindowThePlatformDoesNotOwnChangesNothing` | a `FOCUS_GAINED` for an unknown window id leaves both windows `.inactive` and fires nothing | does not compile | **M2.4** an unknown id clears the tracked focus without checking ownership — spell it so it reddens; if no honest spelling reddens it, delete the test and record why |

`ReplayFixtureTests` (21) and every existing `MetalUISDLTests` test stay
green (the appended kinds renumber nothing). Lane 2 also builds the package on
Linux in a `swift:6.4-noble` container if Docker is available.

### Lane 3 — the seam (Opus)

**Files**: `Sources/MetalUIPlatform/Platform.swift` (the requirement pair);
`Sources/MetalUI/Window.swift` (`controlActiveState`, the callback, the stamp
at draw, the three-fields doc); `Sources/MetalUIAppKit/AppKitPlatform.swift`
(`AppKitWindow`'s pair, the mapping as a `static func
controlActiveState(isKeyWindow:isApplicationActive:)`, the observers, and an
internal `keyStatus: @MainActor () -> (isKeyWindow: Bool, isApplicationActive:
Bool)` defaulting to the live reads — the harness seam, since a locked or
headless session cannot make a window key); `Tests/MetalUITests/Fakes.swift`
(the pair on `FakePlatformWindow`, default `.key`;
`simulateControlActiveStateChange(to:)`; `FakeRenderSurface.scaleFactor`
settable; `simulateBackingScaleChange(to:)` setting both scales and firing
`onResize`); new `Tests/MetalUITests/WindowControlStateTests.swift`, new
`Tests/MetalUIPlatformTests/AppKitControlStateTests.swift`, new
`Tests/MetalUITests/ControlStateCompileGuards.swift`.

| # | test | asserts | red before | mutation |
|---|---|---|---|---|
| T3.1 | `theWindowStampsItsPlatformsControlActiveStateAndAChangeRepaints` | a fake starting `.inactive`: the first frame's reader reads inactive; `simulate(.key)` → `needsRedraw`, reads key; `.active` → active; `.active` again → `needsRedraw` stays false | does not compile | **M3.1** `Window.init` does not assign the callback; **M3.2** the stamp omitted at draw (reads `.key`); **M3.3** the `!=` guard dropped (the no-op arm) |
| T3.2 | `aScopeWriteOfControlActiveStateWinsBelowItAndTheWindowsEnvironmentDoesNot` | root `.inactive`; a reader under `.environment(\.controlActiveState, .key)` reads key beside an inactive sibling; `window.environment.controlActiveState = .key` leaves the root inactive | does not compile | **M3.4** the stamp applied before `Window.environment` rather than over it (the second arm) |
| T3.3 | `aBackingScaleChangeReachesTheDisplayScaleOnTheNextFrame` | fake at 1 → reader reads 1; `simulateBackingScaleChange(to: 2)` → `needsRedraw`, reads 2 / 0.5; **separating arm**: the surface's scale set to 3 with `PlatformWindow.scaleFactor` left at 2 → reads 3 (the drawable's scale is the source) | does not compile | **M3.5** `onResize` does not dirty; **M3.6** `Frame(scaleFactor: platformWindow.scaleFactor)` (the separating arm) |
| T3.4 | `theAppKitWindowReportsKeyChangesThroughItsCallback` | a real `AppKitPlatform` window (scripted accessibility signal, as the platform tests build one) with `keyStatus` scripted: `(true, true)` + post `NSWindow.didBecomeKeyNotification` → callback `.key`; `(false, true)` + `didResignKey` → `.active`; `(false, false)` + `NSApplication.didResignActiveNotification` → `.inactive`; the same post again → no call; `controlActiveState` reads each | does not compile | **M3.7** the application-activation observer removed (the `.inactive` arm); **M3.8** the change guard dropped (the repeat arm) |
| T3.5 | `theAppKitMappingPutsKeyBeforeActiveBeforeInactive` | the four `(isKeyWindow, isApplicationActive)` rows → key, key, active, inactive (a key non-activating panel in an inactive app reads key) | does not compile | **M3.9** application activity checked first |
| T3.6 guard | `aPlatformWindowWithoutTheControlActiveStatePairDoesNotCompile` | plain `import MetalUIPlatform`, whole-file: a conformer with every other requirement and without the pair fails naming `controlActiveState`; **positive control**: the same conformer with the pair compiles | — | **MG7** a protocol-extension default for the pair (negative half red) |
| T3.7 guard | `theWindowsControlActiveStateIsReadableButNotSettableOutsideTheModule` | plain `import MetalUI`: reading `w.controlActiveState` compiles; assigning it fails | — | **MG8** the setter made `public` |

The platform tests' AppKit window count and CI hazards are unchanged (T3.4
posts notifications; it does not need an unlocked screen or a key window).
If `typecheckFile(_:importing: "MetalUIPlatform")` cannot see that module
under `#filePath`'s layout, T3.6 imports `MetalUI` (which re-exports it, or
say so) — the lane checks which, and states it.

**Lane 3 exit**: 1498 + 5 tests + 2 guards = **1505 tests, 90 guards**.

## 7. Accounting, pixels, gates

- **Tests**: 1490 → **1505** (lane 1 +8, lane 3 +5 tests +2 guards; lane 2's
  two are in `Backends/SDL`). One rename (E19 → E19′), no removal.
  `goldensUnchanged` verdict: true iff the one renamed test has its row in
  §56 and no other retained test changed its answer.
- **Demo expectation: no pixel moves.** No built-in element reads any of the
  three values; the demo sets none of them; `displayScale` is stamped from the
  scale the frame was already drawn at. **0 px against `e732d98` in all
  fourteen offscreen images** (`docs/probes/demo-pixels/compare.sh`), each
  lane; `DemoFrameDeterminismTests`' `Expected.swift` unedited;
  `Backends/SDL`'s `PortableReplay` and `DemoCapture` at 0 px.
- Every gate in the brief: `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`, 0 `warning:` on both
  build systems, `MetalUILayout` imports only `MetalUICore` (lane 1 adds a
  file to `MetalUICore`, not `MetalUILayout`), `Backends/SDL` built after
  lanes 2 and 3, a `swift:6.4-noble` build if Docker runs.
- **Real-window capture**: per the lock probe at each lane's end; locked at
  design time. If unlocked, `docs/probes/window-capture/capture.sh <scratch>
  e732d98 <HEAD>`; and **re-run the probe's C arms** — if SwiftUI's mapping
  differs from `EV-AB`'s, the lane amends the mapping (T3.5's rows) with the
  measured one and records it.

## 8. For the Record phase

- CLAUDE.md "Environment (EV-)": `displayScale` writable with `pixelLength`
  derived (no `pixelLength` re-stamp; `theme` still re-stamped);
  `controlActiveState` from `PlatformWindow`'s new pair, stamped by `Window`;
  `controlSize` carried; three `Window.environment` fields not the root's
  source. CLAUDE.md's intro sentence on `PlatformWindow` requirements without
  defaults gains the pair.
- Divergences: **24 retired** (label into the never-reused list); **76, 77
  added**; 75 skipped (§5). Record §04 dated section.
- Declared-but-inert: `controlActiveState`, `controlSize` and `displayScale`
  have no built-in reader (rows with owners: tasks 12; 10 and 11; none — for
  authors, as `pixelLength`).
- Counts line, guard-file list (`ControlStateCompileGuards` 2), the
  `typecheckFile` helper count.
- Plan task 9: **tick**, with a closing note; task 10/11/12 notes for 76/77
  and the inactive look; `EV-Q` rows moved (`EV-AE`).
- Record §56 (new): the E19 rename row, every lane's red, mutations, pixel
  readings, lock-probe readings; `docs/record/README.md` row.

## 9. Risks

- **The key/active mapping is unmeasured** (C1–C3 did not run). Cost if wrong:
  a MetalUI reader sees `.active` where SwiftUI would say `.key` or
  `.inactive` in some window configuration; no built-in element reads it, so
  no pixel moves. Owed: the probe's C arms on an unlocked screen (§7).
- **Exposing `displayScale` invites pre-scaling.** `EV-J` withheld it for
  that reason; S3 shows SwiftUI exposes the same number with the same
  points-based drawing, and T1.4 pins that `fill` keeps the frame's factor.
- **T1.5 pins a divergence a later rounding change will flip.** That is its
  job; the flip belongs to the change that implements `EV-AD`'s owner.
- **SDL focus events on hidden windows**: `SDL_PushEvent` of window events is
  what `resizeThemeAndCloseReachTheWindow` already relies on; if a Linux
  window manager focuses a hidden window, T2.1's `#require` names it rather
  than asserting a false sequence.
