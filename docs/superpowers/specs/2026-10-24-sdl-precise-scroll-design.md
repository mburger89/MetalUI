# SDL precise scroll — design (XP-G28)

Rulings: [`../2026-10-24-sdl-precise-scroll-decisions.md`](../2026-10-24-sdl-precise-scroll-decisions.md) (`TP-A`…`TP-O`). Branch `feat/sdl-precise-scroll` from `935d0096`. Backends/SDL plus root tests; no seam change.

## 1. Goal

On SDL (Linux, Windows, macOS-under-SDL) a two-finger trackpad scroll reaches `ScrollEvent` as `isPrecise: true` with `.began/.changed/.ended` so an app can pan on a trackpad and zoom on a wheel. AppKit untouched.

## 2. API

No new seam API. One public MetalUI-only declaration in `Backends/SDL` (outside the census, `GA-L`; needs a doc comment):

```swift
public enum SDLScrollPrecision: Sendable { case automatic, disabled }
// SDLPlatform.Options gains: public var scrollPrecision: SDLScrollPrecision = .automatic
```
`.disabled` is today's behaviour byte for byte. `Options.default`/`.headless` use `.automatic`. Doc comments on `ScrollEvent.phase/momentumPhase/isPrecise` and `SDLPlatform` replace "always on SDL" with the TP- rules.

## 3. Implementation (files)

Lane 1 (all `Backends/SDL`):
- `Sources/MetalUISDL/SDLScrollClassifier.swift` (new, internal, pure, imports only `MetalUIPlatform`/Foundation-free): `struct SDLScrollClassifier { static let quietInterval = 0.15; static let fractionTolerance: Float = 1e-4; var mode; mutating func classify(dx:dy:at:) -> Result; mutating func expire(at:) -> Bool; var deadline: Double?; mutating func reset() }` with `Result { isPrecise, phase, closedStale }`.
  `closedStale` is true when ANY event (precise or not) arrives after the old stream's deadline (TP-M) (the window then delivers the old stream's `.ended` first).
- `Sources/MetalUISDL/SDLPlatform.swift`: `SDLWindow.handle` `MUI_EVENT_WHEEL` arm calls internal `handleWheel(dx:dy:timestamp:modifiers:position:)`; `expireScrollStreams(now:)` on platform and window; `run()` idle wait `min(250, scrollWaitTimeoutMilliseconds(now:))`; focus loss and close call `classifier.reset()` (emit nothing); `Options.scrollPrecision`; doc comments.
- Tests: `Tests/MetalUISDLTests/SDLScrollClassifierTests.swift` (new), `SDLInputAPITests.swift` (test 1.16 rewritten).
Lane 2 (root tests and comments, disjoint):
- `Tests/MetalUITests/SDLShapedScrollWindowTests.swift` (new): W1-W4.
- `Sources/MetalUIPlatform/InputEvent.swift`: doc comments only.
Record phase (not a lane): `docs/divergences.md` 845, 846 (leave the header's next label), `docs/verification/human-checks.md` group TP, `docs/record/155-...md`, CLAUDE.md rule, closeout scripts (no census change expected: no `Sources/` declaration).

Order: lane 2's tests pass on arrival (Window is unchanged), so lanes are independent. Lane 1 needs Linux image and macOS `Backends/SDL` runs; lane 2 the root native suite.

## 4. Tests (name; red before; mutation that must redden)

Pure classifier (`SDLScrollClassifierTests`, run on macOS and in the Linux image; red before = the type does not exist, so each fails to compile at `935d0096`; mutations are the real red-proof):
- T1 `aWholeNotchIsNotPreciseAndOpensNoStream` — (0,-1): `isPrecise false`, `.none`, deadline nil. Mut: tolerance `> 1e-4` → `>= 0` (fraction test on `x != 0`).
- T2 `aFractionalEventIsPreciseAndBegins` — (0,0.25): precise, `.began`, deadline `t+0.15`. Mut: classify on `integer_y`-style truncation (`Int(v) != 0`).
- T3 `aSecondEventInsideTheQuietIntervalChanges` — `.changed`, deadline moved. Mut: always `.began`.
- T4 `anIntegralEventInsideAStreamStaysPrecise` — (0,0.3) then (0,1) at +0.05: second precise `.changed`. Mut: drop the sticky clause.
- T5 `aNotchAfterTheQuietIntervalIsAWheelAgain` — also `closedStale == true` for the notch (TP-M). Mut: quietInterval 0.15 → 1.5 (the notch then stays precise).
- T6 `anEventAfterTheDeadlineBeginsANewStreamAndReportsTheStaleEnd` — `closedStale == true`, `.began`. Mut: never set `closedStale`.
- T7 `expireEndsAStreamExactlyOnceAtTheBoundary` — at `t+0.149` false, at `t+0.15` true, again false. Mut: `<` for `<=`; not clearing the stream (a second `true`).
- T8 `aHorizontalFractionIsPrecise` — (0.2,0). Mut: test y only.
- T9 `aHiResWheelStepIsPreciseByDesign` (characterization of divergence 845) — (0,1/120). Red before: type missing; mutation: tolerance `1e-2` reddens it (pins the tolerance choice).
- T10 `disabledModeIsTodaysBehaviour` — fractional with `.disabled`: false/`.none`/no deadline. Mut: ignore mode.
- T11 `aNonFiniteDeltaIsNotPreciseAndDoesNotTrap` — NaN, inf. **No mutation can redden it** (NaN/inf compare false against the tolerance without any guard: it is a characterization pin, recorded as such in the record, TP-M); no `isFinite` guard is written.
- T12 `resetDropsTheStreamWithoutAnEnd` — after reset `expire` is false, deadline nil. Mut: reset leaves the deadline.
Platform (`SDLInputAPITests`, arm `armMainRunLoopExitCheck()` via `inputWindow()`; run in the Linux image too, none needs a presented frame):
- P1 (1.16 rewritten) `sdlWheelNotchIsPhaselessAndAFractionBeginsAPreciseStream` — pushes a real `MUI_EVENT_WHEEL` with `dy = -2` (phase none, not precise) then `dy = -0.25` (precise, `.began`, `delta.y == -2.5`). **Red before: behaviour** (`isPrecise` false). Mut: `isPrecise: false` literal (reddens), `phase: .none` literal.
- P2 `aPreciseStreamIsEndedOnceByExpiry` — `handleWheel` at injected `t`, `expireScrollStreams(now: t+0.2)`: window gets one zero-delta `.ended`, `isPrecise true`, same position/modifiers; a second expiry delivers none. Mut: expiry delivers nothing / twice.
- P3 `aStaleStreamIsEndedBeforeTheNextBegan` — event at `t`, event at `t+1` without a poll: received `[began, ended, began]`. Mut: skip `closedStale`.
- P4 `closingOrLosingFocusDropsTheStreamWithoutEnded` — Mut: do not reset.
- P5 `theIdleWaitShortensWhileAStreamIsOpen` — `scrollWaitTimeoutMilliseconds`: 250 with none, `ceil(remaining*1000)` with a stream, never below 1. Mut: constant 250.
- P6 `scrollPrecisionDisabledKeepsTheOldWheel` through the platform. Mut: ignore option.
Window (`SDLShapedScrollWindowTests`, root; **green on arrival by design — Window is unchanged; these are the TP-H pins, red only under the named mutations**):
- W1 `aSyntheticBeganLatchesTheCoverAndEndedClearsIt` — handler claims; `.began` at cover A, pointer moved, `.changed` still reaches A, `.ended` zero delta reaches A, next phaseless event dispatches by pointer (renamed, `TP-Q`: an `.ended` does not clear the latch). Mut: `ScrollLatch.isGestureEvent` returns false for `.changed`; delete the `phase == .none` reset.
- W2 `aNotchDuringAPreciseStreamEndsTheLatch` — Mut: delete `Window.applyScroll`'s `phase == .none` latch reset.
- W3 `aPreciseSDLStreamScrollsAScrollViewByItsDelta` — offsets equal the summed deltas; `.ended` zero delta leaves the offset (no frame claim, `TP-Q`). Mut: apply `ended` with a nonzero repeat of `last` delta.
- W4 `aHandlerAboveAScrollViewVetoStillWorksForAPreciseStream` (`CI-AH` unchanged). Mut: dispatch order flip.
P1 note: `mui_push_event` may stamp timestamp 0 or now; the lane reads `SDLBridge.c` and, if the stamp is not mui_now, P1 drives `handleWheel` directly for the stream arms and keeps the push only for the bridge round trip.
Guards: none new (a trait-off stub compile is covered by the root build; run `swift build` without the SDL trait) (no new public type in the root; `SDLScrollPrecision` is `Backends/SDL`). Existing tests that must stay green: `ScrollLatchTests`, `InputAPIWindowTests`, `PlatformTests`, AppKit scroll tests, the fourteen images 0 px, `DemoFrameDeterminismTests`.

## 5. Demo

No new demo section, no pixel change. `METALUI_INPUT_FOLLOWUPS` (InputFollowupsDemo) already prints `isPrecise` and phases; on a Linux desktop it now shows `precise` with `began…ended` for a trackpad and `wheel` for a notch (look, group TP).

## 6. Human checks (group `TP`, added at Record; not run by an agent)

TP1 Wayland (GNOME and KDE) trackpad two-finger scroll: `isPrecise` true, one `.began`, `.changed`, one `.ended` about 150 ms after the last motion; log the inter-event gaps (measures `quietInterval`). TP2 X11 (XI2) the same. TP3 Windows precision touchpad, including inertia (precise `.changed`, no momentum phase) and
a fast flick (integral deltas stay precise). TP4 notched wheel: false, `.none`, on all three. TP5 hi-res wheel (Wayland `value120`, Windows free-spin): record what it reads (expected precise, divergence 845). TP6 macOS under the SDL trait. TP7 a notch within 150 ms after a trackpad stream; first-event misclassification rate over 50 gestures.
TP8 `Options.scrollPrecision = .disabled` restores old behaviour.

## 7. Divergences (labels from 845-854)

845 `isPrecise` heuristic on SDL; 846 synthesized phases, inferred late `.ended`, no momentum. Header's next-label line left to the merge.

## 8. Deferred (TP-L)

Real `axis_source`/`axis_stop`, momentum, configurable quiet interval, `WM_POINTER`.
