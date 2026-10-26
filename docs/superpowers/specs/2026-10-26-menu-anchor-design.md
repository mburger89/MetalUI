# Menu anchor under render effects - design (XP-G29)

Rulings: [`../2026-10-26-menu-anchor-decisions.md`](../2026-10-26-menu-anchor-decisions.md) (`MA-A`...`MA-F`). Branch `fix/menu-anchor` from `bc747b6b`. Root `Sources/MetalUI` and tests only.

## 1. Goal

A `Menu`, `Picker(.menu)`, `.popover`, `anchoredOverlay` or a keyboard-opened `.contextMenu` presents at its label's **drawn** frame in window points, whatever render effects (`.offset`, `.scaleEffect`,
`.rotationEffect`), scroll offsets and container origins sit above it. MetalCreator's `cubeControls` (`Menu("View")` in a `VStack` under `.offset`, over a `GPUSurface` in a split's right pane) opens at
about (1000, 410) instead of (10, 100).

## 2. API

None. No public declaration, no divergence (855-864 untouched), no seam requirement, no shader. One internal function: `Frame.presentationWindowBounds(_:)` (MA-B).

## 3. Implementation

Lane 1 (`Sources/MetalUI`, `Tests/MetalUITestingTests`):
- `Frame.swift`: add `presentationWindowBounds(_ bounds:)`; `recordPresentationAnchor` uses it (drop its private offset arithmetic); `ContextMenuRecord(... bounds:)` at ~1759 uses it. Doc comments of
  `MenuPresenter.openPullDown`, `Window.openPullDownMenu`, `recordPresentationAnchor` say "drawn bounds, effects included".
- `Tests/MetalUITestingTests/MenuAnchorTests.swift` (new; absorbs `MenuAnchorReproTests.swift`, which stays as T1 until then).
Lane 2 (disjoint, demo and checks):
- `Sources/MetalUIDemoContent/MenusDemo.swift`: a section in **its own function** (1 MB stacks, `everyProductionTreeBuildsOnAOneMegabyteThread`): a `Menu` and a `Picker(.menu)` under `.offset` and a
  `.scaleEffect(1.5)`, in the right half of an `HStack` split, behind `METALUI_MENUS_DEMO=1`. Expectation: each pop-up opens at the label's drawn bottom-leading corner (native and, with the drawn style, in-window).
- `docs/verification/human-checks.md` group `MA` (record phase): `MA1` AppKit real popup under `.offset` and `.scaleEffect`; `MA2` SDL drawn menu, same; `MA3` MetalCreator's View menu in the real app.
Before the Record phase neither lane edits CLAUDE.md / AGENTS.md / README / record index. Pixels: 0 px in the fourteen images (the demo section is env-gated; verify with `compare.sh`).

## 4. Tests (all in `MenuAnchorTests.swift`, plain imports, `harnessWindow`; each red before the fix)

Truth in every test: the label's `element(label:).frame` (transformed bounding box; the accessibility rule) and the platform's `presentedMenus.last.at` (native) or the drawn panel's `.menuItem` node frames (drawn).
Expected point: `(frame.minX, frame.maxY)`.
- T1 `aMenuUnderOffsetPresentsAtItsDrawnLabel` (exists, red). Mutation M1: `presentationWindowBounds` returns `scrolled(bounds)`. Reddens T1-T9.
- T2 `aMenuInAPaneUnderOffsetAndScaleAnchorsToTheDrawnBox` (split with a 120-wide non-zero-origin pane, `.offset` then `.scaleEffect(1.5, anchor: .topLeading)`, and the reverse order). Mutation M2: use the innermost
  effect's `map` instead of `composed` (reddens the nested-order arm only).
- T2b `aMenuUnderMetalCreatorsShapeAnchorsToTheDrawnBox`: MA-F's tree (offset of ~990 x 310 taken from a model, `.overlay(alignment: .topLeading)` over a `GPUSurface` in the right pane of a 1200-wide split whose left pane holds a list); asserts the point is within 1 of the label frame's bottom-leading corner and far from the layout origin. Reddens with M1.
- T3 `aMenuUnderRotationAnchorsToTheBoundingBoxCorner` (`.rotationEffect(.degrees(30))`; MA-B's approximation, pinned).
- T4 `aMenuInAScrolledScrollViewUnderOffsetAnchorsToTheDrawnBox` (scroll offset 50 plus `.offset`; guards against double-adding `activeOffset`). Mutation M3: add `activeOffset` twice.
- T5 `aMenuInAnEquatableComponentReplaysItsAnchor` (unchanged key frame replays: assert a prepaint replay counter > 0 via `frameWork`, anchor equal; then change the `.offset` value: re-anchors, no stale replay).
  Mutation M4: make `replayPresentationAnchor` store the stored bounds shifted by `activeOffset` (double offset) reddens the replay arm.
- T6 `aPickerMenuUnderOffsetAnchorsToTheDrawnBox` (`SV-AK` path).
- T7 `aKeyboardOpenedContextMenuUnderOffsetAnchorsToTheDrawnBox` (accessibility/keyboard open of `.contextMenu`; the pointer-opened one stays at the press point, pinned in the same test). Mutation M5: revert only the
  `ContextMenuRecord` site (reddens T7 alone).
- T8 `aPopoverAndAnchoredOverlayUnderOffsetPlaceFromTheDrawnBox` (read `OpenPopover.anchor` through the drawn panel's frame: below the drawn box, flipped at the window edge).
- T9 `aDrawnMenuOpensAtTheDrawnLabelUnderOffset` (`presentsMenusNatively: false`: the first `.menuItem` frame's origin is the point, clamped).
- T10 `aLegacyElementsOwnEffectIsInTheAnchor` (legacy `Menu` with decoration `.offset`, MA-B).
- T11 `everyPresentationBoundsSiteGoesThroughTheOneFunction` (source scan of `Sources/MetalUI` for `presentationAnchors[` / `contextMenuRecords[` writes and `ContextMenuRecord(`; green after, red on a copy that reintroduces
  `activeOffset` arithmetic).
- T12 `anAppKitPopUpReceivesTheDrawnPoint` (extend `Tests/MetalUITests/AppKitMenuTests.swift`, injected `menuPresenter`, hosted window; skipped where AppKit tests cannot run; the unfiltered run is the evidence).
- T13 (existing, unchanged, must stay green) the retained `presentationAnchor` refusal pins (`RZ-`, `RW-K`) and every `MN-`/`SV-AK` menu test with no effect (value-identical).
Counts expected: 4449 + 13 tests (T1 included), 0 guards beyond T11 (a test, not a typecheck guard).

## 5. Verification

Per CLAUDE.md: native build/test (4462 expected), default-build-system 0 warnings, inventory/undocumented scripts print nothing (no public declaration), fourteen images 0 px, mutations M1-M5 each by name on the
full suite. Not run: real AppKit popup, SDL window, MetalCreator (human checks `MA1`-`MA3`).

## 6. Deferred (named)

- Lifting the `presentationAnchor` retained refusal (MA-D): owner a later retained milestone, trigger a trace naming it.
- A rotated-edge anchor (MA-B): no consumer.
- SwiftUI probe of `Menu` under `.offset` (MA-E): needs an interactive window; human check `MA1`.
