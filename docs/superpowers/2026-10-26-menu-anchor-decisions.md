# Menu anchor under render effects (XP-G29) - decisions

Rulings for item XP-G29 of the gpui-gap priority list (MetalCreator report 2026-10-26, user screenshot; **not a plan task**). Prefix `MA-`.
**Next unused: `MA-I`.** Spec: [`specs/2026-10-26-menu-anchor-design.md`](specs/2026-10-26-menu-anchor-design.md). Record: `../record/156-menu-anchor.md`.
Branch `fix/menu-anchor` from `bc747b6b`. Amends `MN-H` item 1 and `MN-AD` (the anchor is the label's **drawn** frame). Divergence labels reserved 855-864: none taken.

Sources of truth. Reproduction: `MenuAnchorReproTests.swift` (committed red at `ce901edb`, since absorbed into `Tests/MetalUITestingTests/MenuAnchorTests.swift` as T1; see MA-A). SwiftUI: **not probed** (MA-E). gpui has no pull-down menu element; its `deferred`/`anchored`
placement uses the element's window bounds, which already include every transform, so it agrees with MA-B but is recalled, not verified here.

## MA-A - the defect: every presentation anchor is recorded without the open render effects

**Evidence.** `Frame.recordPresentationAnchor(_:bounds:)` (`Frame.swift`, ~2104) moves `bounds` by `activeOffset` (the scroll translation) only. `.offset`, `.scaleEffect` and `.rotationEffect` are render effects
(`GX-`): layout-transparent, composed in `Frame.prepaintEffects`, applied at paint and by `insertHitbox` / `emitAXNode` / `noteGeometry` / `effectBoundingBox(of:ownEffects:bounds:)`. The anchor never reads them, so a `Menu`
under `.offset(x:y:)` presents at its layout position while its label, hitbox and accessibility frame are drawn elsewhere. `bounds` itself already carries every container origin (a split pane's origin is in
layout), which is why the report's popup landed at the pane-less spot (10, 100) rather than the label's (1000, 410): the missing term is the effect, not the pane.
The same function feeds **four** consumers, so all four share the defect: `Menu` (`PullDownMenu.swift:64`), `.pickerStyle(.menu)` (`PickerMenu.swift:43`), `.popover` / `anchoredOverlay`
(`Popover.swift:141`, read back by `AnchoredPresentation.swift:118` as `OpenPopover.anchor`), and, through a separate copy of the same arithmetic, `.contextMenu`'s keyboard / accessibility record
(`ContextMenuRecord.bounds`, `Frame.swift` ~1759, which opens at the record's bottom-leading corner). A pointer-opened context menu uses the press point and is unaffected.
**Reproduced red (run at the design phase, native build: 2 issues, x and y both differ)** with `MetalUITesting` (`aMenuUnderOffsetPresentsAtItsDrawnLabel`, the committed repro): `presentedMenus.last.at` is the layout origin, `element(label:).frame` (the transformed bounding box) is
`(+60, +40)` away. Not a pane or retained problem: no pane term was found missing, and a retained same-key replay stores window bounds (`replayPresentationAnchor`) and so replays whatever the build recorded.
**Cost if wrong.** If the report's pane also lost an origin, T-pane (spec 4) goes red after the fix and a second ruling is owed; it is a test of the whole shape, not just the effect.

## MA-B - the anchor is the label's drawn bounding box in window points

**Ruling.** One function, `Frame.presentationWindowBounds(_ bounds:)` = `effectBoundingBox(of: scrolled(bounds), bounds: bounds)`: scroll translation, then the innermost open effect's composed map as a bounding box,
exactly how accessibility frames and `noteGeometry`'s `globalFrame` are made (divergence 107; `GX-I`). `recordPresentationAnchor` and `ContextMenuRecord` both call it; a source-scan test pins that no other
site builds a presentation or context-menu bounds. The menu opens at the box's bottom-leading corner (unchanged, `MN-H` item 1); a popover flips and clamps against the box (unchanged).
With no effect open it returns `scrolled(bounds)` bit for bit, so every existing tree is value-identical. A rotation or non-uniform case anchors to the bounding box's bottom-leading corner, not the rotated edge (the same
approximation every accessibility frame makes; a menu has no rotated geometry to follow). **Amended by MA-G:** a legacy element's own effects are *not* open when its `prepaint` records; it passes them (`ownEffects:`), T10 pins it. The function is `presentationWindowBounds(_:ownEffects:)`.
**Cost if wrong.** A bounding box of a rotated label can sit a few points off the visual corner; cheaper than a rotated-corner rule and consistent with VoiceOver's frame. Unchanged for scale-1 offsets, the whole report.

## MA-C - the platforms are untouched

The seam already carries window points: AppKit pops `NSMenu` at that point in the flipped host view (`AppKitWindow.presentMenu`), SDL answers `false` and `Window` draws the panel at it
(`openContextMenu`, `MenuPanel.place`). Both consume the corrected number with no change, so `Backends/SDL` and `MetalUIAppKit` are not edited and the Linux image is not owed. AppKit is pinned through the
existing injected `menuPresenter` (the point reaches `NSMenu.popUp` unchanged); a real popup is human check `MA1`.

## MA-D - retained replays

A presentation anchor stays a **refusal** for a translated replay (`RetainedPrepaint` `presentationAnchor`, `RetainedTranslation` `.refused("presentationAnchor")`, `RZ-`): after the fix the recorded value
depends on the effect, which makes the refusal strictly more necessary, and it is not lifted. A same-key replay (`replayPresentationAnchor`) stores window bounds already and is correct; a changed effect
changes the key (`RZ-B`), so a stale anchor cannot replay. **Amended by MA-H:** wrong for a pure translation (`RK-G`), which does replay a stale rect; the replay now shifts it by its own delta (T5, T5b, T5c). The affine and layout/scroll-shift refusals stand.
**Carried:** lifting the refusal by re-deriving anchors through the effect chain (as `AT-A` does for accessibility), owner: a later retained milestone, only if a trace shows a miss named `presentationAnchor` costing frames.

## MA-E - SwiftUI

SwiftUI's menu pops from the label's displayed position (a `Menu` is an `NSPopUpButton`-class control whose layer follows `.offset`); that is MetalCreator's stated expectation and the only behaviour that does not detach
the pop-up from its label. A probe needs a real window and a click on a pop-up that AppKit runs a tracking loop for; **not cheap, not run**. The claim is therefore classed `A` by expectation, not by probe, and no
divergence is recorded: the change moves MetalUI to the behaviour its documentation (`MN-H`: "at its bottom-leading corner") already promised. Human check `MA1` includes the comparison on a real SwiftUI `Menu` under `.offset`.

## MA-F - critic review: the report's 990-point gap is the offset, and the repro must be that shape

**Checked.** MetalCreator's `cubeControls` offset is `cubeLayout.origin` (+ side + 6), a model value of hundreds of points, applied to a `VStack` laid out at the overlay's top-leading corner; the layout position (10, 100) and the drawn one
(1000, 410) differ by exactly that offset, so MA-A's single missing term (the render effect) explains the report without a pane term. The committed repro used +60/+40, which proves the mechanism but not the report's shape: T2b adds the large
offset, overlay attachment over a `GPUSurface` and a split. **Rejected:** a separate pane-origin fix (no pane term is missing: `bounds` carries container origins from layout) and lifting the retained `presentationAnchor` refusal (MA-D stands).
**Corrected in the spec:** T12 lives in the existing `Tests/MetalUITests/AppKitMenuTests.swift` (there is no `MetalUIAppKitTests` target); counts are 4449 + 13 = 4462. T11 (source scan) is weak evidence alone and is backed by M5 and M1; it stays.
**Re-checked clean:** no public declaration, no platform requirement, no shader, no divergence label (855-864 untouched), no seam or C enum change; demo section env-gated so the fourteen images stay 0 px.

## MA-G - a legacy `Menu` records its anchor before its own effects open (found at the implementation phase; amends MA-B)

**Evidence.** MA-B said "own-effects of a legacy element are already open when its `prepaint` runs". They are not: `registerAndScope` opens `Decoration.renderEffects` inside the element's registration, and `Menu.prepaint` records its
anchor *before* it calls `button.prepaint`. T10 (`aLegacyElementsOwnEffectIsInTheAnchor`, a legacy `Menu(...).offset(x: 55, y: 25)`) stayed red (55 / 25 points off) after the ambient-only fix. **Ruling.**
`presentationWindowBounds(_:ownEffects:)` and `recordPresentationAnchor(_:bounds:ownEffects:)` take the element's own effects (default `[]`), exactly as `TextField`/`TextEditor` pass them to `effectBoundingBox`; `Menu` passes
`decoration.renderEffects`. `PickerMenuButton` needs no argument (the `Picker`'s `MenuBox` opens its effects around the button's prepaint) and the `ContextMenuRecord` site is already inside `registerAndScope`. Proposal modifiers
(`Popover`) have no own effect.

## MA-H - a pure-translation replay shifts the stored window rects (found at the implementation phase; amends MA-D)

**Evidence.** MA-D claimed "a changed effect changes the key (`RZ-B`), so a stale anchor cannot replay". Wrong for a translation: `retainedPrepaintDecisionInner` admits a pure-translation effect change (`.translation(dx, dy)`, `RK-G`, the
report's own shape: a moving `.offset`) and replays the ledger, whose `anchors` and `contextMenus` were window rects recorded **without** the effect before this item (so replaying them was exact) and **with** it after. T5
(`aMenuInAnEquatableComponentReplaysItsAnchor`, `.equatable()` Menu, model offset 60,40 to 10,90) was red with only the ambient fix: the retained replay popped the menu at the old place (278, 216) while the label was drawn at (228, 242).
**First attempt, rejected.** Refusing `presentationAnchor`/`contextMenus` for a translation too (as the affine arm does, `RZ-F`) fixed T5 but reddened 22 existing pins (`aTranslatedReplayEqualsAFreshFrameAtEveryScale` x10 arms,
`aPurePanStillTakesTheTranslationArm` x2 and their kin: `RPCard` carries a `.contextMenu`, and Z10's text says a pan "still replays the prepaint and counts no refusal"), and cost a redo plus the eight-build backoff per change. **Ruling.**
`PrepaintMode.replay` gains `windowShift: (dx: Float, dy: Float)?`, the translation arm's own delta; `replayPrepaintLedger` adds it to every replayed anchor and context-menu record's origin. Exact algebra: the translation arm requires equal
linear parts and the innermost composed translation moved by `(dx, dy)`, and a bounding box of `M x + t` moves by `Delta t` whatever `M` is. The affine arm and the layout/scroll shift arm (`movedPrepaintLedger`) keep their by-name refusals
(a bounding box of an affine change is not a shift). The shifted rect equals a fresh frame's bit for bit where the sum is exact in Float (whole points, halves, quarters: T5c) and within one ulp elsewhere - an anchor is a placement hint,
not a pixel. **Mutation** M4 removes the shift (T5, T5b, T5c red) and M4b drops the stored rects' replay entirely.

## MA-I - the shifted replay is bit-exact under a dyadic outer scale and within an ulp under a non-dyadic one; the refusal was tried and rejected (open arm of MA-H, closed)

**Evidence.** T5d (`aShiftedReplayUnderAnOuterScalePresentsWhereAFreshFrameDoes`, an `.equatable()` `Menu` and a `.contextMenu` declarer under an outer `.scaleEffect(s, anchor: .topLeading)` with a moving fractional inner
`.offset`, five steps, replays counted) against a retention-off run: `s = 1.5` bit-equal for menu and context-menu points; `s = 1.3` one ulp off on some steps (`288.90997` against `288.91`, `227.38101` against `227.381`), the Float cast of
the Double delta added to an already rounded Float rect. **Refusal tried.** Refusing `presentationAnchor`/`contextMenus` in the translation arm unless the delta and every stored origin are exact sixteenths made T5d bit-equal, but
reddened 16 existing pins (`aTranslatedReplayEqualsAFreshFrameAtEveryScale` x10, `aPurePanStillTakesTheTranslationArm` at 0.8), whose `RPCard` carries a `.contextMenu` and whose pans are fractional: they assert a pan replays with no
refusal (`refused == 0`), the same cost MA-H already rejected. **Ruling.** Keep MA-H's shift; an anchor is a placement hint, so T5d asserts bit-equality at the dyadic scale and 1e-3 point at the non-dyadic one (a lost dx or dy is
whole points and reddens it). Not a pixel; no divergence label. **Mutation** M7 drops `dy` from the shift: T5, T5b, T5c and T5d (1.5) red. Next unused id `MA-J`.
