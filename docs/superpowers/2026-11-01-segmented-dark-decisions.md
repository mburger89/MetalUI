# Segmented picker selected fill in dark - decisions

Rulings for the selected segment of a segmented `Picker` in the dark theme (MetalFlow's report: it read as *less* selected). Prefix `SD-`. Branch `fix/segmented-dark`. Code:
`Sources/MetalUI/Picker.swift` (`PickerScope.selectedSegmentFill`, `TaggedElement.makeChrome`); tests: `Tests/MetalUITests/SegmentedPickerFillTests.swift`; probe:
`docs/probes/swiftui-segmented-dark.swift`. Record: `../record/187-segmented-dark.md`. **Next unused: `SD-D`.** No divergence label was taken (SD-B).

## SD-A - the probe, and what could not be sampled

**Cause (measured).** The track paints `.surfaceSecondary`, the selected segment `.surface`, unselected segments nothing. `Theme.light`: 0xFFFFFF on 0xE4E7EC (lighter: reads selected).
`Theme.dark`: 0x161C2E on 0x27304A (**darker**: reads unselected).

**Probe.** `docs/probes/swiftui-segmented-dark.swift`, a SwiftUI `Picker(.segmented)` and an `NSSegmentedControl` in `NSAppearance` aqua and darkAqua. **No native pixels were obtained.**
Three instruments each failed in this session: `cacheDisplay(in:to:)` and `NSSegmentedCell.draw(withFrame:in:)` into a bitmap and `CALayer.render(in:)` all draw nothing on macOS 27 (the control
draws in the window server's layer tree), and `screencapture -l`/`-x` answer "could not create image from window/display" (no capture permission for the agent). The fallback used is the system
colours AppKit paints a segmented control with, resolved under each appearance (`NSColor.controlColor` over `windowBackgroundColor`): light `#FFFFFF` on a `#FFFFFF` window (the control is a white pill on a
grey-tinted track), dark `controlColor` = white at 0.25 alpha, which over the `#1E1E1E` window composites to `#565656` - **lighter than the dark window and than the quaternary track fill
(`#242424`)**. That orders the pill above the track in dark, the same relationship as light. It is a proxy, not a sampled pixel: a human look (group `SD`, `SD1`) owns the comparison.

## SD-B - the fix: `.textPrimary` at 0.18 in a dark scheme, `.surface` in a light one; no new token

**Ruling.** `PickerScope.selectedSegmentFill = Color(light: .surface, dark: Color.textPrimary.opacity(0.18))`. Light is bit-identical to before. Dark composites to about `#4C5470` over the
`#27304A` track (luminance 0.33 vs 0.19), a visibly lighter pill, translucent like AppKit's own `controlColor`.

**Why not a new `Theme` token.** A token is a public stored property, an exhaustive `switch` arm for every outside `ColorToken` consumer, `everyTokenDiffersBetweenLightAndDark` and
`noTwoTokensCollideWithinAVariant` rows, an inventory row and a migration note, for one control's fill. Existing tokens carry the relationship: `.textPrimary` is by construction the colour that
contrasts with the surfaces, so an alpha of it over the track is lighter in any dark theme and (by the scheme split) is not used in a light one.

**A custom `Theme`.** Gets the selected fill from its own `.surface` (light scheme) or its own `.textPrimary` (dark scheme) with nothing authored. The split is by `colorScheme`, not by theme, so
a `Window` whose theme and scheme disagree (a dark theme under a light scheme, `CR-V` item 2) still gets the pre-fix light-scheme pill; the pre-existing mismatch is out of scope.

**Cost if wrong.** A dark selected pill a few grey levels off native; one constant to retune.

## SD-C - the selected segment's hairline edge (Alloy G23, G28)

**Measurement** (`docs/probes/swiftui-segmented-thumb.swift`, record 260). Pixel readback of the native control did not work again: `cacheDisplay(in:to:)` on macOS 27 returns only an alpha-mask
draw (the SwiftUI hosting view's selected segment is blank, an `NSSegmentedControl`'s pill is a flat text-colour layer at alpha 0.20 over the 0.08 track), with no stroke or halo visible in
the row or column samples, and `CGWindowListCreateImage` no longer compiles (ScreenCaptureKit only). So **neither a stroke nor a shadow was sampled or ruled out**; the semantic colours are the evidence:
`separatorColor` black 0.10 (light) / white 0.12 (dark), `controlColor` white 1.0 / white 0.247, `controlBackgroundColor` and `windowBackgroundColor` #FFFFFF / #1E1E1E.

**Ruling.** `PickerScope.selectedSegmentEdge = Color(light: textPrimary x 0.10, dark: textPrimary x 0.12)`, drawn as a 1-pixel `Decoration.border` (inside the pill, emitted after its content, `OM-V`) on
the selected segment only. No shadow (AppKit's is unmeasured and `Decoration` has none; a shadow would need a wrapper element or a new primitive), no new drawable capability, no `Theme` token (alphas of
`.textPrimary`, as `SD-B`), no layout change, the thumb fill unchanged. `TabStrip` does not use this paint.

**Contrast (reported, not faked; WCAG ratios of the edge composited on the thumb).** A hairline at AppKit's alpha does not reach 3:1 in light. Default light: edge vs thumb 1.23, vs page `#F5F5F7` 1.13
(thumb vs track 1.24, as Alloy measured). Default dark: edge vs page 3.24, vs thumb 1.33 (thumb vs track 1.68). Solarized Light (page = surface = base3 `#FDF6E3`, track base2, text base00 `#657B83`): edge vs
page 1.12 (the test prints 1.1208). So the edge gives the pill an outline where its fill equals the page, but it does **not** meet non-text 3:1 in either light case; a theme that needs that sets a darker
`.textPrimary` or `.surfaceSecondary`. Pinned only as "differs from the page" (> 1.05).

**Mutations** (each alone, restored).

| # | Mutation | Reddened |
|---|---|---|
| SD-M3 | drop `border:` from the segmented chrome `Decoration` | `theSelectedSegmentDrawsAHairlineEdgeAtItsRect`, `anUnselectedSegmentHasNoEdge`, `theEdgeSeparatesTheThumbFromAPageEqualToSurface` |
| SD-M4 | edge alpha 0.5 | `theSelectedSegmentDrawsAHairlineEdgeAtItsRect` |
| SD-M5 | `border:` on every segment | `anUnselectedSegmentHasNoEdge`, `theSelectedSegmentDrawsAHairlineEdgeAtItsRect` |

## Mutations (SD-B)

Applied to `PickerScope.selectedSegmentFill`, one at a time.

| # | Mutation | Reddened |
|---|---|---|
| SD-M1 | revert: `Color.surface` for both schemes (the base's behaviour) | `theSelectedSegmentIsLighterThanTheTrackInDark` |
| SD-M2 | light half `.surfaceSecondary` | `theSelectedSegmentIsStillSurfaceInLight` |

## Carried

- A human run of group `SD` (`SD1`), and a native pixel sample when a capture permission exists (`swiftui-segmented-dark.swift` prints the pixel table when it can capture).
- The same `.surface`-on-`.surfaceSecondary` shape elsewhere (a selected tab, a stepper) was not audited.
