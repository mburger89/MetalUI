# 262. TabStrip unselected ink follows `Theme.textSecondary` (Alloy gap G30, `TBS-L`)

Branch `fix/tabstrip-secondary-ink` (master `505cd03c`). Decision `TBS-L` in `docs/superpowers/2026-11-07-tab-strip-decisions.md`. Class `M`; no divergence added or retired (220 live, next label 241).

- **Change.** An unselected tab's ink was `textPrimary` x 0.64 (`TBS-K`). It is now `Color.tabStripUnselectedInk` (internal; new `Color.Provider` case `secondaryOverrideOrPrimary(0.64)`): `Theme.textSecondary` when set, else `textPrimary` x 0.64 exactly. It resolves at paint, so a theme switch repaints only and light/dark variants each use their own override. The derived `Color.secondary` is not used when nil (0.588 would break `TBS-K`'s AA). Close glyph and dirty dot share the ink. No public declaration.
- **Picker.** The segmented `Picker`'s unselected labels stay full `textPrimary` (AppKit `NSSegmentedControl` uses `labelColor`): a non-change, recorded in `TBS-L`.
- **Tests** (`Tests/MetalUITestingTests/PlaceholderContrastTests.swift`): `withoutAnOverrideTheUnselectedInkIsTextPrimaryAt064`, `aThemesTextSecondaryIsTheUnselectedInk`, `switchingTheTextSecondaryRepaintsTheUnselectedInk`.
- **Mutations** (each alone, restored): M6 ink on `Color.secondary` reddens the no-override and switching tests (and `anUnselectedHoveredTabStripTabsInkIsAA`); M7 ink back on literal `textPrimary` x 0.64 reddens the override and switching tests.
