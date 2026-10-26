# 156. Menu anchor under render effects (item XP-G29)

Item XP-G29 of the gpui-gap priority list (user request 2026-10-02, MetalCreator's report of 2026-10-26 with a user screenshot; **not a plan task**), on `fix/menu-anchor` from `bc747b6b`. Rulings `MA-A`..`MA-H`, next `MA-I`
(`docs/superpowers/2026-10-26-menu-anchor-decisions.md`; spec `docs/superpowers/specs/2026-10-26-menu-anchor-design.md`). Root `Sources/MetalUI` and tests only; no public declaration, no seam requirement, no shader, no divergence
(855-864 untouched). Human checks group `MA`.

## 1. What was wrong and what was built

MetalCreator's `Menu("View")` inside a `VStack` that carries `.offset(x:y:)`, layered over a `GPUSurface` in the right pane of a split, popped up at about window (10, 100) instead of under its label at about (1000, 410).
**Cause (`MA-A`, `MA-F`):** `Frame.recordPresentationAnchor` moved the label's layout bounds by the scroll translation only. `.offset`, `.scaleEffect` and `.rotationEffect` are render effects (`GX-`): layout-transparent, applied at
paint and by hitboxes, accessibility and `noteGeometry`, never by the anchor. The report's gap is exactly the model-driven offset; no pane term was missing (`bounds` already carries every container origin from layout). The same function
fed four consumers, so all four shared the defect: `Menu`, `.pickerStyle(.menu)`, `.popover`/`anchoredOverlay` and, through a copy of the arithmetic, a keyboard- or accessibility-opened `.contextMenu` (`ContextMenuRecord.bounds`).

**Fix (`MA-B`, `MA-G`, `MA-H`).** One function, `Frame.presentationWindowBounds(_:ownEffects:)` = `effectBoundingBox(of: scrolled(bounds))`, the way accessibility frames are made (divergence 107); `recordPresentationAnchor` and the
context-menu record both call it, and a legacy `Menu` passes its own render effects (`MA-G`: they are not yet open when its `prepaint` records). With no effect open it is `scrolled(bounds)` bit for bit, so every existing tree is
value-identical. A pure-translation retained prepaint replay (a moving `.offset`, `RK-G`) adds the arm's own delta to every replayed anchor and context-menu record (`PrepaintMode.replay.windowShift`, `MA-H`); the affine arm and the
layout/scroll shift arm keep their by-name `presentationAnchor`/`contextMenus` refusals (`MA-D`). The platforms are untouched (`MA-C`): the seam already carries window points, AppKit pops `NSMenu` at that point, SDL draws the panel at it.
Rotation anchors to the bounding box's bottom-leading corner (the accessibility approximation, `MA-B`).

## 2. SwiftUI

Not probed (`MA-E`): a `Menu`'s pop-up tracking loop needs a real window. The claim is MetalCreator's stated expectation (the menu below the label as drawn) and `MN-H`'s own promise, so no divergence; human check `MA1` compares a real SwiftUI `Menu` under `.offset`.

## 3. Tests

`Tests/MetalUITestingTests/MenuAnchorTests.swift` (new, 14 functions; absorbs the design-phase repro `MenuAnchorReproTests.swift`) over `harnessWindow`, truth being the label's accessibility frame: `aMenuUnderOffsetPresentsAtItsDrawnLabel` (T1),
`aMenuInAPaneUnderOffsetAndScaleAnchorsToTheDrawnBox` (T2, both nestings), `aMenuUnderMetalCreatorsShapeAnchorsToTheDrawnBox` (T2b: the report's shape), `aMenuUnderRotationAnchorsToTheBoundingBoxCorner` (T3),
`aMenuInAScrolledScrollViewUnderOffsetAnchorsToTheDrawnBox` (T4), `aMenuInAnEquatableComponentReplaysItsAnchor` (T5), `aContextMenuRecordInAnEquatableComponentFollowsAMovedOffset` (T5b), `aShiftedReplayPresentsWhereAFreshFrameDoes` (T5c),
`aPickerMenuUnderOffsetAnchorsToTheDrawnBox` (T6), `aKeyboardOpenedContextMenuUnderOffsetAnchorsToTheDrawnBox` (T7), `aPopoverAndAnchoredOverlayUnderOffsetPlaceFromTheDrawnBox` (T8), `aDrawnMenuOpensAtTheDrawnLabelUnderOffset` (T9),
`aLegacyElementsOwnEffectIsInTheAnchor` (T10), `everyPresentationBoundsSiteGoesThroughTheOneFunction` (T11, a source scan, weak alone). `Tests/MetalUITests/AppKitMenuTests.swift` gains `anAppKitPopUpReceivesTheDrawnPointUnchanged` (T12: the point reaches
`NSMenu.popUp` unchanged through the injected `menuPresenter`). The existing retained `presentationAnchor` refusal pins and every no-effect `MN-`/`SV-AK` test stay green unedited.

## 4. Red runs and mutations

Red first: `ce901edb` (the repro, 2 issues, x and y both off by the offset), then `5c92d671` (T1-T11): **MenuAnchorTests 12 tests, 34 issues, every test red** (`presentedMenus.last.at` differs from the label's drawn frame; T11 finds `activeOffset`
arithmetic in `recordPresentationAnchor` and `ContextMenuRecord`). Two further reds were found at the implementation phase and are the rulings `MA-G` (T10 stayed red after the ambient-only fix, 55 / 25 points off) and `MA-H` (T5 red:
278, 216 against the label at 228, 242; a refuse-by-name attempt fixed T5 but reddened 22 existing pins and was rejected). **Mutations named in the spec**, each on the full unfiltered suite (about 770 s, finished normally, only the five locked-screen sheet issues extra; baseline 4464 tests, 5 issues), reddened tests by name:

| Mutation | Reddened |
|---|---|
| M1 `presentationWindowBounds` returns `scrolled(bounds)` (effects dropped) | 13: `aShiftedReplayPresentsWhereAFreshFrameDoes`, `aMenuInAPaneUnderOffsetAndScaleAnchorsToTheDrawnBox`, `aMenuInAnEquatableComponentReplaysItsAnchor`, `aMenuUnderMetalCreatorsShapeAnchorsToTheDrawnBox`, `aPopoverAndAnchoredOverlayUnderOffsetPlaceFromTheDrawnBox`, `aPickerMenuUnderOffsetAnchorsToTheDrawnBox`, `aMenuUnderRotationAnchorsToTheBoundingBoxCorner`, `aMenuUnderOffsetPresentsAtItsDrawnLabel`, `aMenuInAScrolledScrollViewUnderOffsetAnchorsToTheDrawnBox`, `aLegacyElementsOwnEffectIsInTheAnchor`, `aKeyboardOpenedContextMenuUnderOffsetAnchorsToTheDrawnBox`, `aDrawnMenuOpensAtTheDrawnLabelUnderOffset`, `aContextMenuRecordInAnEquatableComponentFollowsAMovedOffset` |
| M2 `effectBoundingBox` uses the innermost effect's map, not the composed one | 2: `aMenuInAPaneUnderOffsetAndScaleAnchorsToTheDrawnBox`, `aMenuUnderRotationAnchorsToTheBoundingBoxCorner` |
| M3 `activeOffset` applied twice in `presentationWindowBounds` | 2: `aMenuInAScrolledScrollViewUnderOffsetAnchorsToTheDrawnBox`, `aPullDownMenuInsideAScrolledScrollerOpensBelowItsScrolledFrame` (existing) |
| M4 the `windowShift` of `replayPrepaintLedger` disabled (filtered, 27 tests of the MenuAnchor, TranslatedReplay and aPurePan families) | 3: `aMenuInAnEquatableComponentReplaysItsAnchor`, `aContextMenuRecordInAnEquatableComponentFollowsAMovedOffset`, `aShiftedReplayPresentsWhereAFreshFrameDoes` |
| M5 only the `ContextMenuRecord` site reverted to scroll-only arithmetic | 3: `aKeyboardOpenedContextMenuUnderOffsetAnchorsToTheDrawnBox`, `aContextMenuRecordInAnEquatableComponentFollowsAMovedOffset`, `everyPresentationBoundsSiteGoesThroughTheOneFunction` |
| M6 `Menu.prepaint` no longer passes `ownEffects:` (filtered, MenuAnchor family) | 1: `aLegacyElementsOwnEffectIsInTheAnchor` |
| T12 mutant: `AppKitWindow.presentMenu` adds 1 to the x it hands `menuPresenter` (filtered) | 1: `anAppKitPopUpReceivesTheDrawnPointUnchanged` |

Branch checker's own mutations (filtered to `MenuAnchorTests|PullDown|TranslatedReplay|AppKitMenuTests`, 45 tests): B1 `presentationWindowBounds` drops `scrolled(...)` reddens `aMenuInAScrolledScrollViewUnderOffsetAnchorsToTheDrawnBox` and `aPullDownMenuInsideAScrolledScrollerOpensBelowItsScrolledFrame`; B2 `replayPrepaintLedger`'s shift drops `dy` reddens `aContextMenuRecordInAnEquatableComponentFollowsAMovedOffset`, `aMenuInAnEquatableComponentReplaysItsAnchor`, `aShiftedReplayPresentsWhereAFreshFrameDoes`. Checker re-took the clean-build native run (4464 tests, 5 sheet issues, 773 s) and the fourteen images (`compare.sh bc747b6b HEAD`, all scene identical, 0 px).

M4 and M6 are filtered runs, not full-suite runs. **Open arm closed (`MA-I`):** T5d (`aShiftedReplayUnderAnOuterScalePresentsWhereAFreshFrameDoes`, scales 1.5 and 1.3, fractional inner `.offset`, a `Menu` and a `.contextMenu` declarer in one `.equatable()` component, five steps, retention on against off) is bit-equal at 1.5 and within 1e-3 pt at 1.3 (one ulp). The refusal (`presentationAnchor`/`contextMenus` unless every number is an exact sixteenth) made it bit-equal but reddened 16 existing pins (`aTranslatedReplayEqualsAFreshFrameAtEveryScale` x10, `aPurePanStillTakesTheTranslationArm` at 0.8) and was rejected. M7 (dropping `dy` from the `windowShift` cast, filtered to the MenuAnchor, TranslatedReplay and aPurePan families) reddens T5, T5b, T5c (5 issues) and T5d at 1.5.

## 5. Demo and counts

`METALUI_MENUS_DEMO=1` gains an "Anchor check" strip in `Sources/MetalUIDemoContent/MenusDemo.swift`, its own function (`menusAnchorSplit()`, a `Menu("View")` under `.offset(x: 40, y: 20)` and a `Picker(.menu)` under
`.scaleEffect(1.5, anchor: .topLeading)` in the right half of an `HStack` split); `MenusDemoModel.anchorMode` is its one new member. Env-gated, so the default demo and the fourteen images do not move.
Counts (2026-10-26, `fix/menu-anchor` from `bc747b6b`): root **4465 tests** (4449 + 15 in `MenuAnchorTests`, T5d's two arms one function, + 1 in `AppKitMenuTests`), 0 goldens, typecheck guards unmoved (273; T11 is a test). Native build 0 `error:` and 0 `warning:` but SwiftPM's deprecation
notice; native unfiltered run, re-taken after `swift package clean` at the Record phase (799 s), `Test run with 4464 tests in 11 suites ... with 5 issues` on a **locked screen**, the five being exactly `AppKitPresentationTests`' sheet issues of `CI-AF` (`turn { nsWindow.attachedSheet != nil }` at lines 120, 139, 161, 183, 200) and nothing else;
`FR-J no-argument frame: succeeded=true`. The fourteen offscreen images are **0 px and scene-identical against `bc747b6b`** (`docs/probes/demo-pixels/compare.sh`, controls as recorded). `swift build --build-tests` on the default build system 0 `warning:`. `swift:6.4-noble` via `metalui-portable`
(volume `metalui-root-build-menu-anchor`): root build complete, `--filter "MenuAnchorTests|MetalUITestingTests"` **592 tests in 8 suites passed**. Inventory and undocumented scripts print nothing (no public declaration); no divergence label taken
(855-864); `Backends/SDL` and `MetalUIAppKit` untouched, so the SDL package run is not owed (`MA-C`). Not run: a real AppKit pop-up, the SDL drawn menu in a window, MetalCreator (group `MA`); Windows (CI only).

## 6. Carried

An outer-scale plus moving-offset replay arm (see section 4); lifting the `presentationAnchor` refusal for the affine and layout-shift arms (`MA-D`; only if a trace shows a miss named `presentationAnchor` costing frames); a rotated-edge anchor (no consumer); a SwiftUI probe of `Menu` under `.offset` (`MA-E`);
the real AppKit pop-up, the SDL drawn menu and MetalCreator itself (group `MA`, `MA1`-`MA3`, not run: an agent cannot).

Open-arm re-take (2026-10-26, after `swift package clean`): native unfiltered `Test run with 4465 tests in 11 suites ... with 5 issues`, exactly the five locked-screen `AppKitPresentationTests` sheet issues; `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1 ... --skip AppKitPresentationTests`: `Test run with 4456 tests in 11 suites passed`.
