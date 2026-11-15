# 306 - A menu `Picker`'s chevron never shrinks (`BY-O`)

Branch `fix/menu-picker-chevron` from master `9639c33f`. Alloy composer pills, class M, no divergence label. Ruling `BY-O` in `docs/superpowers/2026-10-31-styles-decisions.md`.

**Symptom.** With `BY-N` merged, a capsule menu `Picker` beside two capsule `Menu`s drew "Auto" and empty space with no chevron; the `Menu`s kept theirs.

**Root cause (measured).** `PickerMenuLabel`'s title box and chevron text both had `flexShrink` 1. In a row too narrow for the three controls the picker is compressed (98 against 109, row widths 200 to 340) and the chevron text, narrower than its glyph, painted nothing. A probe of `allGlyphs` and the chrome rects: at 600 wide the chevron was at x 261 in a capsule 172 to 281; at 300 wide the capsule was 12 to 110 and its last glyph was the "o" of "Auto" at 44. Not the clip, not the fill colour, not the capsule width.

**Fix.** The chevron is in a `flexShrink = 0` `Box`; the title is `lineLimit(1)` in a frame (ideal and max the widest option, min that less the chevron's width) so it truncates first (`Sources/MetalUI/PickerMenu.swift`). Ideal 109 x 24 and the `Picker.menu` floor 67 hold. A rigid title was tried and moved the floor to 78.4.

**Red and green.** `aMenuPickerBesideMenusAlwaysPaintsItsChevronInsideItsCapsule` (`ButtonBorderShapeTests.swift`, widths 600, 440, 340, 300, 260, 200) fails 4 arms (340, 300, 260, 200) on the old `PickerMenuLabel`, passes on the new.
