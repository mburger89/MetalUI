# Record 224: `defaultScrollAnchor` (Alloy gap G6)

Branch `feat/default-scroll-anchor` (master `4d4c59db`). Rulings `DSA-A`..`DSA-I` in `docs/superpowers/2026-11-07-default-scroll-anchor-decisions.md` (new prefix; next `DSA-J`). Class `A`; divergence 226 added (210 live, next label 227). Probe `docs/probes/swiftui-default-scroll-anchor.swift`. Human checks: group `DA`, not run.

## 1. What SwiftUI does (probe, macOS 27.2)

`defaultScrollAnchor(_:)` (all roles) and `(_:for:)` with `.initialOffset`, `.sizeChanges`, `.alignment` exist. `.bottom` starts a scroller at the end of its content and **keeps the end in view while content grows and the scroller is at the end**, with no second modifier: SwiftUI does follow by itself (`G1`, `W1`, variable heights `V1`). A wheel up releases it (the offset then holds under appends, `W1`), a wheel back to the end re-engages it (`W1`). The roles split that: `.initialOffset` places and follows but never re-engages (`W3`), `.sizeChanges` does not place but follows whenever the scroller is at the end (`W2`), `.alignment` aligns content shorter than the viewport (offset -100 for 100 in 200, `S2`) and follows once it overflows. Other anchors (`.center`, `.top`, a fractional point) place once and never follow (`I3`, `I6`). The idiom for a transcript is therefore `.defaultScrollAnchor(.bottom)` alone; `for: .sizeChanges` is for a scroller that must not jump to the end on its first appearance.

## 2. What was built

`Sources/MetalUI/DefaultScrollAnchor.swift` (the public API, the declarations, the state machine); a `followsEnd` field on `ScrollContext` and a `windowOffset` that the lazy planner, `List` (uniform and variable) and the pinned-section code read; `ScrollState.anchor`; `ScrollChrome.anchors` with `layoutFollowsEnd`, `anchoredOffset` and `clampOffset` (the alignment's one negative offset); both scrollers' `requestLayout` publish the flag; the lazy planner's cold frame is end-aware; `Frame.applyScrollResolutions` skips the `VL-G` adjustment of a scroller that followed its end. Tests `Tests/MetalUITestingTests/DefaultScrollAnchorTests.swift` (16, portable harness).

## 3. Deviations from the brief

- **The modifier is on the scroll view itself** (divergence 226): SwiftUI applies it through the environment, so also on an ancestor (`O7`). MetalUI follows `scrollIndicators` and `scrollPosition(id:)`.
- **No `ScrollPosition` struct / `scrollPosition(_:)`** (iOS 18's) - not part of this gap.
- **A non-trailing anchor repeats its placement up to 6 prepaints** until a lazy container's extent settles (`DSA-B`), where SwiftUI places once (its extent is not an estimate).
- **An instrument limit, not a deviation**: the probe's `clip.scroll(to:)` arms (`G2`, `G6`) are not user scrolls to SwiftUI; the user scroll is a real phased wheel event (`W` arms).

## 4. Mutations (each applied alone, `swift test --no-parallel --filter DefaultScrollAnchorTests`, reverted)

| Mutation | Reddened |
| --- | --- |
| pin never released (`memory.pinned = false` removed) | `aWheelUpReleasesTheEndAndAppendedRowsLeaveTheViewportAlone`, `scrollingBackToTheEndPinsAgain`, `aScrollToAwayFromTheEndReleasesThePin`, `theInitialOffsetRoleFollowsUntilTheUserLeavesAndNeverAgain` |
| anchor applied to the top (the fraction read as `1 - y`) | 14 of the 15 then written (every test that starts at an end or centre) |
| `followsEnd` not published by `ProposalScrollView` | `fiveThousandRowsRealizeOnlyTheWindowAtTheEnd` |
| `followsEnd` not published by the legacy `ScrollView` | `theLegacyScrollViewPinsALazyStackToo` (green before that test was added: a separating arm was missing) |
| the `VL-G` adjustment applied to a following scroller | `aBlockAboveTheViewportGrowingWhilePinnedStaysPinned`, `variableHeightsMeasuredLateStillEndAtTheBottomEdge`, `theInitialOffsetRoleFollowsUntilTheUserLeavesAndNeverAgain` |
| the `.sizeChanges` role ignored | `theSizeChangesRoleFollowsOnlyAScrollerThatIsAtTheEnd`, `scrollingBackToTheEndPinsAgain`, `aScrollToAwayFromTheEndReleasesThePin` |
| alignment never aligns | `shortContentSitsAtTheAnchorAndKeepsToTheEndWhenItGrows` |
| the cold window left at the first 32 lines | `fiveThousandRowsRealizeOnlyTheWindowAtTheEnd` |
| the initial-offset pin re-engages at the end | `theInitialOffsetRoleFollowsUntilTheUserLeavesAndNeverAgain` |
| a horizontal scroller reads the anchor's y | `aHorizontalScrollerReadsTheTrailingAnchor` |
| the placement at the end removed (`offset = end`) | 12 of the 16 (every follow test) |
| a frame requested on every anchored prepaint (an unsettled scroller) | `aSettledPinnedScrollerGoesIdle` |
| the non-end placement not waiting for a settled extent | `aCenterAnchorStartsInTheMiddleAndDoesNotFollow` |

## 5. Measured

The first frame of a 5000-row transcript realises the LAST 32 rows (row 4999 on screen in frame 1); settled, 12 lines (10 on screen + 2 overscan above; none after the last), unchanged after an append; a settled pinned scroller is idle (`runUntilIdle`).

## 6. Carried

SwiftUI's ancestor application (226); `.trailing` in a right-to-left layout (unmeasured); a `List`'s end-aware first frame; `scrollPosition(id:)`'s binding following a pin; a user-scroll tolerance other than 1 point.
