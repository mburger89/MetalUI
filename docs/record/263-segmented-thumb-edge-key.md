# 263. The segmented thumb edge is a theme colour key (Alloy gap G31, `SD-D`)

Branch `feat/segmented-thumb-edge-key` (master `f07d6b7b`). Decision `SD-D` in `docs/superpowers/2026-11-01-segmented-dark-decisions.md`. Class `M`; no divergence added or retired (220 live, next label 241).

- **Change.** `PickerScope.selectedSegmentEdge` (record 260, `SD-C`) is now `Color(SegmentedThumbEdge.self)`. `SegmentedThumbEdge` is a new public `ThemeColorKey` enum; its default is the old colour, `Color(light: textPrimary x 0.10, dark: textPrimary x 0.12)`. Alloy overrides it with `theme[SegmentedThumbEdge.self] = c` (or `App`/`Window` `lightTheme`/`darkTheme`) to reach 3:1.
- **Default stays theme-relative.** `Color.textPrimary` is a token colour and `opacity(_:)` keeps a factor applied after resolution, so `Color(light:dark:)` of the two resolves token-relative at paint; no scheme-dependent provider was needed. The default appearance is unchanged (all `SD-C` tests pass untouched).
- **Tests** (`Tests/MetalUITests/SegmentedPickerFillTests.swift`): `theDefaultEdgeIsTextPrimaryAtTheSDCAlphas`, `theDefaultEdgeFollowsAThemesTextPrimary`, `anOverrideOfTheEdgeKeyIsThePaintedEdge`, `changingTheEdgeOverrideRepaintsTheEdge`.
- **Mutations** (each alone, restored): see `SD-D`.
