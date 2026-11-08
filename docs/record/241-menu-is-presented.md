# Record 241: a Menu opened from code (Alloy gap G9)

Branch `feat/menu-is-presented` (master `dfc21168`). Ruling `MN-AK` in `docs/superpowers/2026-10-02-menus-popovers-decisions.md` (`MN-AJ` is the `feat/help-provider` branch's, record 239; next `MN-AL`). Class `M`; no divergence added (SwiftUI has no such API).

## 1. What was asked and built

A chat composer wants `/model` to open its model `Menu` the way a click does. `Menu(isPresented:content:label:)`, `Menu(_:isPresented:content:)` (the `LocalizedStringKey` and `StringProtocol` spellings) and `Menu.menuPresented(_:)` (`Sources/MetalUI/MenuIsPresented.swift`; the `Menu.isPresented` storage is in `MenuContent.swift`, the behaviour in `PullDownMenu.swift`). `Menu` exists in one vocabulary only.

- Writing `true` from input opens the menu through the click path's own `Window.openPullDownMenu` (same anchor, same native-or-drawn choice), **after the frame** that read `true`: the `Menu` notes a `PresentationRequest.menu` record in layout (`notePresentation`), and `Window.reconcileMenuBindings`, called from `reconcilePresentations`, opens it. Dialogs/alerts skip `.menu` records and menus take no registry slot.
- Every end of a session writes `false`: the session carries `pullDownBinding`, and `Window.menuSession`'s `didSet` (`menuSessionDidChange`) writes the old owner's binding `false` when the session ends or another owner's replaces it.
- A click writes `true` once the menu is up; writing `false` while open drops a drawn session and tells a native one through `dismissPresentation(token:)`; the `Menu` leaving the tree closes it; an open that cannot happen (disabled, empty, no anchor) writes `false` back.
- Harness: `TestWindow.presentedMenu` is `nil` for a token the platform was told to dismiss. No demo: a `Model` menu and a button added to `MenusDemo` (even as one more argument to its root composer, `@inline(never)`) made `everyProductionTreeBuildsOnAOneMegabyteThread` exit SIGBUS (stack overflow at 0.08 s), and it passed again with the demo restored; the human check says to use a throwaway app.

## 2. Findings along the way

- The pull-down is an imperative session on `Window`, so the dialog registry's record-and-reconcile shape fits better than a popover's per-frame content, and brings `ViewThatFits` retraction (`VF-D`) and the graft audit's `presentationRecords` count for free.
- AppKit's `NSMenu.popUp` is modal: the reconcile runs it inside `beginFrame`, so `reconcilingMenuBindings` guards re-entry. No agent sees a real `NSMenu`; human check `MIP1`. A `false` write cannot land while a native menu is shown on a real Mac.
- First `ViewThatFits` test was vacuous (the unchosen candidate has no anchor, so its open fails anyway); it now asserts the unchosen binding is left `true` with no write, which `M5` reddens.
- `Menu.menuPresented` and the inits live in their own file so the inventory map can classify them `M` (the census cannot tell `init`s apart by signature).

## 3. Tests

`Tests/MetalUITestingTests/MenuIsPresentedTests.swift`: 10 test functions, 9 of them run with `presentsMenusNatively` true and false; portable (plain imports, `harnessTextSystem`).

## 4. Mutations (each alone, in place after the commit, restored with `git checkout`; filtered run `--filter MenuIsPresentedTests`)

| Mutation | Reddened |
| --- | --- |
| `reconcileMenuBindings()` call removed | `writingTrueFromAnActionOpensTheMenuAtTheLabelsAnchor`, `choosingAnItemRunsItAndWritesFalse`, `dismissalWritesFalse`, `writingFalseDismissesAnOpenMenu`, `theModifierIsTheSameAsTheInitialiser`, `aMenuThatLeavesTheTreeIsClosed`, `aMenuInAViewThatFitsCandidateStillWorks`, `aDisabledMenuWritesFalseBack`, `anOutsidePressOnTheDrawnMenuWritesFalse` |
| `menuSessionDidChange` guard `false` | `choosingAnItemRunsItAndWritesFalse`, `dismissalWritesFalse`, `clickingTheLabelSetsTrue`, `theModifierIsTheSameAsTheInitialiser`, `anOutsidePressOnTheDrawnMenuWritesFalse`, `aMenuThatLeavesTheTreeIsClosed` |
| close branch of `reconcileMenuBindings` removed | `writingFalseDismissesAnOpenMenu`, `aMenuThatLeavesTheTreeIsClosed` |
| click path passes `isPresented: nil` | `clickingTheLabelSetsTrue` |
| `fitNotes` append removed from `notePresentation` | green first (vacuous test, section 2); `aMenuInAViewThatFitsCandidateStillWorks` after the fix |
| `isEnabled &&` removed from the open | `aDisabledMenuWritesFalseBack` |
| harness `presentedMenu` ignores dismissed tokens | `writingFalseDismissesAnOpenMenu`, `aMenuThatLeavesTheTreeIsClosed` |
| native `dismissPresentationOnPlatform` removed | `writingFalseDismissesAnOpenMenu`, `aMenuThatLeavesTheTreeIsClosed` |
| no `false` written back when an open fails | `aDisabledMenuWritesFalseBack` |

Not covered by a mutation: `reconcilingMenuBindings` (re-entry needs a nested frame inside `popUp`; `MIP1`).

## 5. Verification

Native, unfiltered, `--no-parallel` after `swift package clean`: `Test run with 5685 tests in 26 suites passed after 644.649 seconds` (0 failures; the same 5685 under `METALUI_VERIFY_RETAINED=1`, `387.089 seconds`), `FR-J no-argument frame: succeeded=true`. A first run before the demo was reverted failed only `everyProductionTreeBuildsOnAOneMegabyteThread` (SIGBUS, section 2). Portable container (`git archive HEAD` into `docker run --rm -i metalui-portable:latest`): `Test run with 973 tests in 11 suites passed`, then 9, 16, 73, 68, 53, 25, 290, 165, 24, 45 (an earlier archive failed two tests that wrote an `@Observable` from the test and ticked; off Apple they now settle through `runUntilIdle()`). Closeout scripts `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. `M5` was re-run after that change and still reddens.
