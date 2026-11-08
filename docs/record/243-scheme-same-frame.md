# Record 243: a changed preferredColorScheme applies in the same frame (MetalCreator report)

Branch `fix/picker-skip` (master `6fb5ee3e`). Ruling `CR-AC` in `docs/superpowers/2026-10-03-colour-decisions.md` (next `CR-AD`). No public API, no divergence (labels untouched). Numbers 241 and 242 are taken by open branches.

## 1. The report

MetalCreator: in a window with an `.equatable()` panel holding a segmented `Picker`, `app.picture == app.pictureAfterRebuildingEverything()` failed on steady frames where the panel was skipped (typing in a sibling field, selecting a node, panning a sibling surface). Replacing the Picker with two Buttons passed. The pictures differed at one rect only, the selected segment (77x24): the skipped picture had the dark arm of `PickerScope.selectedSegmentFill` (`textPrimary` at 0.18), the rebuilt one the light arm (`surface`).

## 2. Diagnosis

Not retention. A window with `testingRetainedSubtrees` on and one with it off draw the selected segment identically at every frame of a scheme round trip. `pictureAfterRebuildingEverything()` switches the theme away and back, and the app root applies `.preferredColorScheme(isDark ? .dark : .light)` (`AppRoot.swift:86`). `Window.updateColorScheme` ran after the build that collected the preference, so that frame painted in the old scheme and the window settled on the next frame; MetalCreator's `redraw()` is one `setNeedsRedraw()` plus one `tick()`, so its final picture was the stale one. The Picker's fill is the only scheme-dependent colour in the panel, which is why Buttons passed. On a real window the same lag is a one-frame flash in the old scheme.

Frame trail of the selected fill (lightness/alpha), one redraw per row, retention on and off identical: light 0.912/1.0; dark1 0.249/1.0 (the dark theme's surface, old scheme); dark2 0.902/0.18; light1 0.200/0.18; light2 0.912/1.0.

The reported `METALUI_VERIFY_RETAINED=1` stop (`unrecordedRead`, `Window.swift:2065`) was not reproduced (24 picker cases, none trapped); open.

## 3. The change

`Window.drawFrameIfNeeded` (`Sources/MetalUI/Window.swift`, about 1708-1727): the `CR-Q` second build no longer requires `framesDrawn == 0`. Any frame whose first build collects a preference that changes the effective scheme builds a second time, snapping every change, and presents that. The scheme is written before the second build stamps the environment; the second build only records its preference, so it runs at most once; `needsRedraw` is cleared. The consequence is that a value animated on the scheme no longer animates across a later preference flip (as on the first frame since `CR-Z`; SwiftUI does not animate a flip without `withAnimation`).

## 4. Tests and mutation

`aLaterPreferenceChangeAppliesInTheSameFrame` (replaces `aLaterPreferenceChangeAppliesOnTheNextFrame`, which pinned the lag) and `aSchemeSwitchReachesASegmentedPickersFillInTheSameFrame(retain:)` (new `Tests/MetalUITestingTests/EquatablePickerReplayTests.swift`, with 20 skipped-panel picture cases and an `RPPair` differential). Mutation: restoring `framesDrawn == 0` reddens `aLaterPreferenceChangeAppliesInTheSameFrame` (3 issues), both arms of `aSchemeSwitchReachesASegmentedPickersFillInTheSameFrame` and the picture cases.

## 5. Count

After `swift package clean`, native build, unfiltered `--no-parallel`: root 5696 tests in 26 suites passed; `FR-J no-argument frame: succeeded=true`. (5669 at record 239, plus the new cases.)
