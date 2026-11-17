# 368 - Region cursors in `CodeView` (`CV-BO`)

Branch `feat/codeview-region-cursors` from master `9cccde0a`. Class M, no divergence (labels untouched). Alloy's request, matching NSTextView and Xcode.

**Regions.** I-beam over the text area (text, past a line end, below the last row); arrow over the gutter (numbers, marker lane, bars) and virtual rows; pointing hand over a fold chevron that acts, a folded header's `⋯`, and text only when `onTextClick` has no modifiers. The default ⌘/Ctrl `onTextClick` and the text hover (`CV-AS`) leave the I-beam: the cursor would have to follow the modifier state (follow-up: Xcode's hand under ⌘-hover).

**Mechanism.** The terminal pointer branch's `styleProvider` was not on master, so the minimal equivalent was added: `PointerAttachment.styleProvider` (package; kept by the wheel, style and visibility factories), asked in `Window.updatePointerStyle(at:)` beside each region's plain style with the element-local point (`Hitbox.elementLocalPoint`), innermost wins, `nil` defers outward; counted as a style region and eligible cover; asked during a press too. `CodeView.prepaint` installs `CodeViewPlan.regionCursor(at:plainClickTargets:)` over the frame's plan. Resolution rides the existing input path (`FP-T`: the move skips its frame; the style is resolved before that), the platform request only on a change. No state write.

**Costs.** Steady and keystroke literals unchanged (`aFoldGutterCostsWhatNoFoldGutterCosts`, `CodeViewFoldLayoutTests` costs, `CodeViewMultiCaretCostTests`). A move within a region: 0 frames, 0 requests.

**Tests** (`CodeViewRegionCursorTests`): text to gutter to text with no frame; moves within a region; chevron and `⋯`; plain, default and no `onTextClick`; horizontal scroll. Mutations are recorded in the test doc comments.
