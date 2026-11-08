# Record 239: the model-driven tooltip (MetalCreator gap)

Branch `feat/help-provider` (master `8f1e25bc`). Ruling `MN-AJ` in `docs/superpowers/2026-10-02-menus-popovers-decisions.md` (next `MN-AK`). Class `M`; no divergence added.

## 1. What was asked and built

MetalCreator draws its graph canvas (nodes, socket dots, wires) under `.allowsHitTesting(false)` because its model does the hit testing; one gesture sits on a hit-testing surface. Socket dots carry `.help("...")`, but the tooltip lookup skips non-hit-testing elements (`MN-U`, SwiftUI's behaviour, unchanged). The requested shape: a tooltip on the hit-testing surface whose text depends on where the pointer is.

`StyledElement.help(_ text: @escaping @MainActor (Point<Pixels>) -> String?) -> Self` and `ProposalElementGroup.help(...) -> ContextualModifier<Self>` (`Sources/MetalUI/Tooltip.swift`). `ContextualAttachment` gained `helpProvider`, carried through `.contextMenu` (both static helpers and `CodeView`'s gutter menu). The closure is handed the pointer in the element's local space and answers the text, `nil` for none.

## 2. Behaviour

- Asked in input only: `Window.trackTooltip` calls it on each pointer move or drag over the region, under `StateDispatch.dispatching(to:)` the declaring element. Never in layout, prepaint, paint or the timer tick.
- The tracker remembers the last answer (`providedText`). The same text keeps the phase (pending timer not restarted, shown bubble kept, spent stays spent); a different one replaces it: a shown bubble is hidden at once (redraw requested) and a non-nil text starts the usual 1.0 s pending phase; `nil` is idle.
- After a press hid it, the bubble returns when the text at the pointer changes (a static `.help` only after leaving).
- Press, wheel, key, a menu session, the window leaving key and leaving hide it as before; placement is `TooltipPlacement.origin` at the latest pointer.
- Accessibility records nothing (a function of a point has no static string; an AX node has no pointer).
- Observed, not changed: `.pointerExited` does not hide a shown tooltip for any `.help` (human check HL5).

## 3. Tests

`Tests/MetalUITestingTests/HelpProviderTests.swift` (9), portable (`@testable import MetalUI`, `harnessTextSystem`), run under `METALUI_VERIFY_RETAINED=1` too: shows after the delay; local point; another text restarts; same text neither restarts nor hides; nil region; press/wheel/key/leave and the spent/other-text arm; call counts (one per move, none per frame or tick); `MN-U` with a provider surface under a non-hit-testing `.help` child; the proposal-path spelling.

## 4. Mutations (each alone, in place after the commit, restored with `git checkout`; filtered run `--filter HelpProviderTests`)

| # | mutation | reddened |
|---|---|---|
| M1 | `trackTooltip`'s `wanted` ignores `helpProvider` | all 9 |
| M2 | location left in window space | `theProviderIsHandedTheLocalPoint`, `aProviderTooltipAppearsAfterTheDelay`, `movingToAnotherText...`, `movingWithinTheSameText...`, `aNilAnswer...`, `pressWheelKeyAndLeavingHideIt`, `theProposalPathSpellingShowsToo` |
| M3 | text comparison always true | `movingToAnotherTextHidesAndRestartsTheDelay`, `aNilAnswerShowsNothingAndHidesTheBubble`, `pressWheelKeyAndLeavingHideIt` |
| M4 | `providedText` never stored | `movingWithinTheSameTextKeepsItAndDoesNotRestart`, `aNilAnswer...`, `pressWheelKeyAndLeavingHideIt` |
| M5 | `.mouseDown` removed from the hiding arm | `pressWheelKeyAndLeavingHideIt` |
| M6 | provider also asked from `advanceTooltip` | `theProviderRunsInInputNeverInAPhase` |
| M7 | the `hitTestingDisabledDepth == 0` gate dropped in `Frame.registerHandlers` | `aNonHitTestingChildShowsNothingWhileTheSurfaceAnswers` |
| M8 | `ProposalElementGroup` overload drops the provider | `theProposalPathSpellingShowsToo`, `aNonHitTestingChild...` |
| M9 | a nil answer leaves the phase | `aNilAnswerShowsNothingAndHidesTheBubble`, `pressWheelKeyAndLeavingHideIt` |
| M10 | `.scrollWheel` removed from the hiding arm | `pressWheelKeyAndLeavingHideIt` |
| M11 | `.keyDown` removed from the hiding arm | `pressWheelKeyAndLeavingHideIt` |

## 5. Verification

Native, unfiltered, `--no-parallel` after `swift package clean`: `Test run with 5669 tests in 26 suites passed after 572.673 seconds` (0 failures; `FR-J no-argument frame: succeeded=true`); under `METALUI_VERIFY_RETAINED=1`: `Test run with 5669 tests in 26 suites passed after 832.278 seconds`. Master's 5660 + 9 new. Portable container (`git archive HEAD` over stdin to `docker run --rm -i metalui-portable:latest`): `swift build --build-tests` complete (122.17 s); `Test run with 957 tests in 11 suites passed` (`MetalUITestingTests`, including the 9 new), then 9, 16, 73, 68, 53, 25, 290, 165, 24, 45 tests, all passed. The closeout inventory and undocumented scripts print nothing.
