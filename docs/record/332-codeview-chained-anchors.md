# 332 - Text-anchored presentations chain on a CodeView (`CV-BC`, `CV-BD`)

Branch `feat/codeview-chained-anchors` from master `c625d565`. Class M, no divergence. Alloy code-intel #4 (blocking): a completion list and a hover or signature popover on one editor at once; `CV-AQ` allowed one text-anchored presentation per view.

**What landed.** `_CodeTextAnchoring` (public, MetalUI-only, `_KeyPressFolding`'s precedent), conformed to by `CodeView` and `PopoverModifier where Content: _CodeTextAnchoring`; the three text-anchored spellings moved to its extension and return `PopoverModifier<Self, P>`. `CodeView.textAnchorBoxes` replaces `textAnchorBox`; each `CodeTextAnchorBox` records its kind; the prepaint resolves all of them and each wrapper records its own `windowRect` under its own id (journaled per wrapper, `RW-K`). `CodeTextHoverRuntime` holds a weak list of popover-kind boxes (`CV-BD`). Rulings `CV-BC` (chaining; keys per `CV-AR`) and `CV-BD` (only a popover holds the grace) in `docs/superpowers/2026-11-07-code-view-decisions.md`.

**Probe.** `docs/probes/swiftui-two-popovers-one-view.swift` (compiled, run twice, identical, screen locked): SwiftUI shows one popover window for two presented `.popover`s on one view; writing the second flag while the first is open makes SwiftUI write the first false. Escape was not observable (app inactive, no key window). MetalUI keeps `MN-N` and shows both popovers; recorded in `CV-BC`, not a new divergence row (class M, per the brief). Open question for the owner: whether to add a divergence row for "two popovers on one view".

**Steady-frame cost.** `CodeViewTextAnchorCostTests`: no presentation 3 requests / 1 hit / 0 misses / 0 ineligible, one open presentation 7/1/0/0 (both measured on master c625d565 with the old code, steady and keystroke frame), two 11/1/0/0.

**Tests** (`Tests/MetalUITestingTests/CodeViewTextAnchorTests.swift`, `CodeViewTextAnchorCostTests.swift`), each with its mutation in its doc comment. A press on the anchored text dismisses a popover (`CV-AQ`), so a test opens its popover after it clicks to focus the view.
