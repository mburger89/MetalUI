# 173 — `runUntilIdle()` after a scroll: clock-driven work never dirties the window (`HT-Z`)

2026-10-31, branch `fix/settle-scroll-momentum`, stacked on `fix/run-until-idle-load` (PR #158, `HT-Y`, record 171). Report from
MetalFlow: `runUntilIdle()` threw `notIdle` ("still drawing after 64 rounds") straight after `window.scroll` over a `ScrollView` in
a `VStack`; `advance(by: 5)` first made it settle. MetalFlow suspected scroll momentum decaying on the clock.

## The mechanism, measured

A throwaway trace test (not kept) scrolled a 300 × 150 `ScrollView` over 800 pt of rows by −2000 and printed, per tick at
`now == 0`, `needsRedraw` before and after and `hasActiveAnimations`:

- `.scrollIndicators(.automatic)`: every round `needsRedraw` true before and after, `hasActiveAnimations` false, one frame drawn;
  after `advance(by: 0.5)` still dirty, after `advance(by: 0.6)` more (age 1.1) clean.
- `.scrollIndicators(.hidden)`, the same scroll: clean from the first round.

So the scroll itself settled in one frame and the **indicator fade** kept the window dirty: `ScrollChrome.paintIndicator` called
`pass.requestAnotherFrame()` while the thumb's alpha was above 0, `Window` honours `wantsAnotherFrame` with `setNeedsRedraw()`, and
the alpha is a function of `timestamp − lastScrollTime`, which a frozen clock never moves. It is not momentum: MetalUI has no
momentum of its own (the platform sends momentum events; `ScrollLatch` only tracks their phases). The same probe found two more
clock-driven effects with the same failure: a held long press (`gestureArena?.needsTicks`) and a pending tooltip
(`tooltipTracker.isPending`), each dirtied the window at the end of every frame and `runUntilIdle()` threw `.notIdle(64)`.

## What changed (`HT-Z`)

- The fade raises `pass.frame.noteActiveAnimation()` (the rule for live animation; `wantsAnotherFrame` is left to one-shot
  corrections: a stale `List`/lazy window, a scroll resolution).
- `Window.awaitsATimer` (internal: `gestureArena?.needsTicks == true || tooltipTracker.isPending`) joins `drawFrameIfNeeded`'s
  guard and replaces the two end-of-frame `setNeedsRedraw()` calls. The frames drawn per tick are unchanged (the two pinned
  frame-count tests are untouched), so the display link pauses on the same frames.
- No new API: `runUntilIdle()`'s contract ("a running animation does not count: it needs the clock") is now true, so neither a
  `settleScroll()` nor a `runUntilIdle(advancingClock:)` is warranted; moving the clock is `advance(by:)`.
- Tests that read the fade through `needsRedraw`/`wantsAnotherFrame` (`ScrollIndicatorTests`, `LoweringScrollTests`, a comment in
  `ObservationTests`) read `hasActiveAnimations` and also pin `!needsRedraw`/`!wantsAnotherFrame` during the fade.
- Docs: `HT-Z` in `docs/superpowers/2026-10-09-test-harness-decisions.md` (next `HT-AA`), the prefix row, `docs/rules/identity-state.md`
  (clock-driven work never dirties), `docs/rules/tooling.md`, `docs/testing.md` (the clock section), a `docs/migration.md` row.

## For MetalFlow

No change is needed: `runUntilIdle()` returns after a scroll with the scroll drawn and the thumb still showing. To see the fade
finished, move the clock:

```swift
window.scroll(at: point, byDeltaX: 0, deltaY: -2000)
try await window.runUntilIdle()     // drawn; the indicator is still fading
window.advance(by: 1)               // 0.6 s opaque + 0.4 s ramp: gone
```

## Tests

`Tests/MetalUITestingTests/ClockOnlySettleTests.swift` (plain imports): `runUntilIdleReturnsAfterAScrollWhileTheIndicatorIsStillFading`
(MetalFlow's repro: returns at `now == 0` with `hasActiveAnimations` true and the thumb painted; `advance(by: 1.1)` ends it),
`aHiddenIndicatorsScrollWasAlwaysIdle` (the separating arm: the content moved), `runUntilIdleReturnsWhileALongPressIsHeldShortOfItsDuration`
(and `advance(by: 0.6)` then runs it), `runUntilIdleReturnsWhileATooltipIsPending` (and `advance(by: 1.5)` paints the panel).
Mutation table in `HT-Z`: each of the four mutations reddens named tests (the fade's six, the long press's one, the tooltip's one,
the guard's two pinned frame-count tests).

## Counts

Root 4635 tests passed (`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel --skip AppKitPresentationTests`, 311 s, one summary line, 12 suites), 0 goldens; guards ran (`FR-J no-argument frame: succeeded=true` printed), 285 typecheck guards (`HT-Z` adds none; not re-tallied). The four new tests over record 171's rebased total of about 4631.
