# Menu anchor under render effects (XP-G29) - decisions

Rulings for item XP-G29 of the gpui-gap priority list (MetalCreator report 2026-10-26, user screenshot; **not a plan task**). Prefix `MA-`.
**Next unused: `MA-F`.** Spec: [`specs/2026-10-26-menu-anchor-design.md`](specs/2026-10-26-menu-anchor-design.md). Record: `../record/156-menu-anchor.md`.
Branch `fix/menu-anchor` from `bc747b6b`. Amends `MN-H` item 1 and `MN-AD` (the anchor is the label's **drawn** frame). Divergence labels reserved 855-864: none taken.

Sources of truth. Reproduction: `Tests/MetalUITestingTests/MenuAnchorReproTests.swift` (committed red at the design phase, see MA-A). SwiftUI: **not probed** (MA-E). gpui has no pull-down menu element; its `deferred`/`anchored`
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
approximation every accessibility frame makes; a menu has no rotated geometry to follow). Own-effects of a legacy element are already open when its `prepaint` runs (`prepaintWithRenderEffect` wraps it); T-legacy pins it.
**Cost if wrong.** A bounding box of a rotated label can sit a few points off the visual corner; cheaper than a rotated-corner rule and consistent with VoiceOver's frame. Unchanged for scale-1 offsets, the whole report.

## MA-C - the platforms are untouched

The seam already carries window points: AppKit pops `NSMenu` at that point in the flipped host view (`AppKitWindow.presentMenu`), SDL answers `false` and `Window` draws the panel at it
(`openContextMenu`, `MenuPanel.place`). Both consume the corrected number with no change, so `Backends/SDL` and `MetalUIAppKit` are not edited and the Linux image is not owed. AppKit is pinned through the
existing injected `menuPresenter` (the point reaches `NSMenu.popUp` unchanged); a real popup is human check `MA1`.

## MA-D - retained replays

A presentation anchor stays a **refusal** for a translated replay (`RetainedPrepaint` `presentationAnchor`, `RetainedTranslation` `.refused("presentationAnchor")`, `RZ-`): after the fix the recorded value
depends on the effect, which makes the refusal strictly more necessary, and it is not lifted. A same-key replay (`replayPresentationAnchor`) stores window bounds already and is correct; a changed effect
changes the key (`RZ-B`), so a stale anchor cannot replay (T-retained pins both: `.equatable()` Menu under a moving `.offset` re-anchors; under an unchanged one it replays and the anchor is equal).
**Carried:** lifting the refusal by re-deriving anchors through the effect chain (as `AT-A` does for accessibility), owner: a later retained milestone, only if a trace shows a miss named `presentationAnchor` costing frames.

## MA-E - SwiftUI

SwiftUI's menu pops from the label's displayed position (a `Menu` is an `NSPopUpButton`-class control whose layer follows `.offset`); that is MetalCreator's stated expectation and the only behaviour that does not detach
the pop-up from its label. A probe needs a real window and a click on a pop-up that AppKit runs a tracking loop for; **not cheap, not run**. The claim is therefore classed `A` by expectation, not by probe, and no
divergence is recorded: the change moves MetalUI to the behaviour its documentation (`MN-H`: "at its bottom-leading corner") already promised. Human check `MA1` includes the comparison on a real SwiftUI `Menu` under `.offset`.
