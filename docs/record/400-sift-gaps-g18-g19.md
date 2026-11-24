# 400: Sift gaps G18 and G19 (`AB-AH`, `HT-AE`)

Class `A` for G18 (SwiftUI has the modifiers on every view), class `M` for G19 (test harness only). No divergence added or
retired (236 live, next label 244). Branch `fix/sift-gaps-g18-g19`, base master `d871b59c`. **Number picked above the open PRs'
records**: #408 is 397, #409 is 398, #410 is 399.

## G18: `accessibilityValue` on a `Component`

Sift: "a Component has no `.accessibilityValue` modifier, so Sift sets it on each Text branch instead." The finding: it was a
compile error, not an inert overload. `ChipLabel().accessibilityLabel("L")` failed with `value of type 'ChipLabel' has no member
'accessibilityLabel'`, and the same for `accessibilityValue`. `StyledElement` (`AccessibilityModifiers.swift`) and
`ProposalElementGroup` (`ProposalAccessibility.swift`) have them; a `Component` is neither, and the file header said
"Not offered on `Component`, on `onClick`'s footing" (one handler cannot be shared; a declaration can). Sift's only `accessibilityValue`
is `GridToolbar.swift:37`, on the `Text` of a rejected-filter chip. The workaround that already compiled was
`Component.frame(...)` followed by the `StyledElement` modifier.

Fix (`AB-AH`): `Component.accessibilityLabel(_:)` and `accessibilityValue(_:)` in `ComponentAccessibility.swift` return an `AccessibilityGroup`: a
layout-transparent group (`IdentifiedGroup`'s shape) that registers the declaration at the union of its members' rects in prepaint, and the tree builder
distributes it to the texts (`AB-T`, probe P3). A first version wrapped the component in a `ModifierLayer` (a row over several members); the coordinator
rejected it, since an accessibility modifier moves no frame in SwiftUI. A `Component` that is also a `ProposalElementGroup` gets the same overload.
Cost: one identity level.

Tests (`ComponentAccessibilityTests`, 4): the value reaches the text of either `if` branch with its string as the label; a label
and a value chain; two texts both get the declaration; a two-text component in a `VStack` and an `HStack` has identical frames with and without the modifier. Mutations: the value writing the
label; the label dropping its declaration; the group registering nothing; a padded wrapper node around the members. Each seen red, restored.

## G19: the colours a text was drawn in

Sift: "MetalUITesting can't read a cell's drawn text colour." `TestWindow.allGlyphs` (`CT-A`) already returns every glyph with its
colour; what was missing was the element to glyph association. `TestWindow.drawnTextColors(in: TestElement) -> [Hsla]` (`HT-AE`) filters
the scene's glyphs by the element's frame (centre containment, window points times the scale factor) and returns one colour per run in paint
order. It is a method on the window, not `TestElement.drawnTextColors`: a `TestElement` is a snapshot of a tree node with no scene.

**Cost: none.** Nothing is recorded while a frame draws. The association is made at query time from `HeadlessWindowRenderer.lastScene`, which the
headless renderer already keeps, and the element's published frame; `MetalUI`, `MetalUIScene` and the renderer are untouched, so a normal app
runs the same code as on master (the diff touches `MetalUITesting` for G19). `askingForDrawnTextColorsCostsTheFrameNothing` compares two identical
windows, one asked every frame, over four steady frames: equal summed `FrameWork` and glyph counts, and `MemoryLayout<MUIGlyph>.stride` 88.

Tests (`DrawnTextColorsTests`, 6). Mutations: the frame filter dropped; run dedupe dropped; order reversed; scale ignored; `scene.glyphs` for
`allGlyphs` (found unguarded while an opacity-only arm stood in for it, since `.opacity` on a `Text` makes no offscreen group; an ellipse clip arm
was added); opacity dropped from the alpha. Each seen red, restored. 
