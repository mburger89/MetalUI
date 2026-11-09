# 251 — A disabled control in the hidden title-bar band does not drag the window (`AS-R` item 9, `AS-S`)

**Date:** 2026-11-08. Branch `fix/disabled-control-blocks-drag` off master 4a7815ba. Class: behaviour fix, no divergence
(it aligns with macOS: native controls answer NO to `mouseDownCanMoveWindow`, enabled or not).

## Problem
`registerHandlers` registers no hitbox for a disabled element (`EV-E`: a blocker would eat an enabled ancestor's
click), so `ChromeRegions.blocks` never saw it. On SDL the band region covered the control; on AppKit the press went
unclaimed to `answerUnclaimedTitleBarPress` and dragged.

## As built
- `Frame.inertChromeBlockers` (+ `noteInertChromeBlocker`): where a disabled element would have blocked (pointer
  target, draggable, drop destination, contextual; not under `allowsHitTesting(false)`), its clipped window rect, or
  the effect's outer clip under a render effect. Nothing hit-tests it; `EV-E` is untouched.
- `Window.lastInertChromeBlockers` holds the last frame's list.
- `ChromeRegions.compute(..., inert:)` carves the band, the handles and the background. An inert rect has no rank, so it
  carves every handle it overlaps.
- `answerUnclaimedTitleBarPress` returns first for a press inside an inert rect: no drag, no double-click action. This
  also covers the background press. Headless follows (the logic is `Window`'s).
- Retained: `PrepaintLog.inertBlockers` (+ mark) into `PrepaintLedger.inertBlockers`, replayed as recorded in
  `replayPrepaintLedger`; both translation paths and `rebased` handle it (translation refuses by name,
  `inertChromeBlockers`; the copy keeps it); the verify snapshot compares it; `testingCorruptPrepaintLedgers` has an
  `inertBlockers` channel.

Deviation from the sketch: the rect has no registration rank, so handles are carved unconditionally (a handle drawn
above a disabled button loses that patch; conservative).

## Tests (`Tests/MetalUITestingTests/DisabledControlChromeTests.swift`) and mutations (debug, native)
| Mutation | Reddened |
|---|---|
| drop the guard in `answerUnclaimedTitleBarPress` | `aPressOnADisabledButtonInTheBandDoesNotDragOnAppKit` |
| drop `+ inert` from the band's `carving` | `aDisabledButtonInTheBandIsCarvedOutOfTheSDLRegions`, `aReplayedSubtreeStillCarves` |
| drop the inert replay in `replayPrepaintLedger` | `aReplayedSubtreeStillCarves` |
| register the disabled control's hitbox (drop `enabled`) | `aDisabledControlInsideAnEnabledAncestorLeavesTheAncestorsClick` |
| drop the `hitTestingDisabledDepth == 0` gate on the note | `aDisabledControlWithHitTestingOffCarvesNothing` |

`theSameButtonEnabledStillClaimsThePress` is the control arm. Counts: root 5752 tests in 26 suites passed (`--build-system native`, unfiltered, `--no-parallel`, after `swift package clean`); `FR-J no-argument frame: succeeded=true`. `everyFrameChannelIsClassified` gained the row `inertChromeBlockers: .ledger`. The three closeout probes print nothing.
