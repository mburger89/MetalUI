# 307 - A menu `Picker`'s title no longer wraps (`BY-P`)

Branch `fix/picker-label-wrap` from master `62c834e7`. Alloy composer pills, class M, no divergence label. Ruling `BY-P` in `docs/superpowers/2026-10-31-styles-decisions.md`.

**Symptom.** In a 300 to 320 wide column the picker's title "Mode" wrapped mid-word ("Mod" / "e") beside two capsule `Menu`s.

**SwiftUI (probe `docs/probes/swiftui-picker-label-compression.swift`).** The picker is 166.5 ideal and 137, 117, 97 wide at rows of 320, 300, 280, all 24 tall: the capsule shrinks (54 at 97) and the title stays whole. Only at 240 (picker 75.5) does the title wrap (32 tall). Plain `Text("sourcekit-lsp")` in a squeezed `HStack` wraps at the hyphen and then mid-word (62 x 32 at 160, 29 x 48 at 80): MetalUI does the same.

**Cause.** `BY-O` gave the selected value's title a floor of the widest option less the chevron, so the capsule stayed about 98 wide and `PickerTitleLayout` squeezed the title to 12.

**Fix.** The title's `minWidth` is the old floor capped at 24 (`Sources/MetalUI/PickerMenu.swift`). A floor of 0 also fixed the wrap but moved the `Picker.menu` zero-proposal pin 67 to 43.4 (`ProposalControlsTests`), so the cap is the smallest that keeps it. Ideal 109 x 24 and the chevron pins hold.

**Red and green.** `aMenuPickersTitleNeverWrapsWhenTheRowIsNarrow` (`ButtonBorderShapeTests.swift`, widths 600 to 280, the `Mode`/`Model`/`Effort` row) fails at 360 to 280 on the `BY-O` floor and passes on the new.
