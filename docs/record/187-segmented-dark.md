# 187 - the selected segment in dark (`SD-A`, `SD-B`)

2026-11-01, branch `fix/segmented-dark` from master `b83efde2`; MetalFlow's report. Rulings: `docs/superpowers/2026-11-01-segmented-dark-decisions.md`.

## 1. Cause

`Picker.swift` painted the segmented track `.surfaceSecondary` and the selected segment `.surface`. In `Theme.dark` (0x161C2E on 0x27304A) the selected pill was darker than its track and
read as less selected; in `Theme.light` (0xFFFFFF on 0xE4E7EC) it read correctly.

## 2. The native look

Probe `docs/probes/swiftui-segmented-dark.swift`. Every pixel instrument failed in this session (bitmap draws of `NSSegmentedControl` are empty on macOS 27, `screencapture` has no permission), so the
relationship rests on AppKit's resolved system colours: `controlColor` composites lighter than the track in dark (`#565656` over the `#1E1E1E` window vs a `#242424` quaternary fill). Group `SD` owns the look.

## 3. The change

`PickerScope.selectedSegmentFill`: `.surface` in a light scheme (unchanged), `.textPrimary` at 0.18 in a dark scheme. No new `Theme` token, no public API, no divergence (label block 1005-1014
untouched).

## 4. Tests and mutations

`SegmentedPickerFillTests.swift`: `theSelectedSegmentIsLighterThanTheTrackInDark`, `theSelectedSegmentIsStillSurfaceInLight`. SD-M1 (the base's `.surface` for both schemes) reddens the dark test;
SD-M2 (light half `.surfaceSecondary`) reddens the light test.
