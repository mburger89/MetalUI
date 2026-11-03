# 194 - accessibility display settings (`AD-A`..`AD-L`)

2026-11-02, branch `feat/accessibility-display` from master `76b03e58`; round-3 item R3-10 item 7. Rulings: `docs/superpowers/2026-11-02-accessibility-display-decisions.md`. Rules in
`docs/rules/identity-state.md`, `sdl.md` and `decision-prefixes.md`. Divergences 1075, 1076, 1078, 1079 (1077 and 1080 measured as no SwiftUI change: record 05).

## 1. What was there

Reduce Motion (`AN-AD`) and Reduce Transparency (`MT-D`) were the only accessibility display settings. `colorSchemeContrast`, Differentiate Without Colour and Invert Colours were "not built" (`CR-A`,
`TE-AO`); nothing else existed.

## 2. The probe

`docs/probes/swiftui-accessibility-display.swift`, compiled, screen unlocked, two runs identical (apart from timing). Outcomes:

- **A**: six keys are get-only (`KeyPath`, not `WritableKeyPath`); `legibilityWeight` is writable; `LegibilityWeight` has no `allCases`, `ColorSchemeContrast` has; `accessibilityShowButtonShapes` reads with
  no warning (`-warnings-as-errors`).
- **V0**: a bare `EnvironmentValues()` reads standard, false x4 and `nil`, **and `accessibilityPlayAnimatedImages == false`** (the plan guessed true; a hosted app reads true, H0). The struct's default
  follows V0; SDL and the headless default answer `true` explicitly.
- **H1**: unlike record 315's `T0`, swizzling `NSWorkspace`'s contrast, differentiate and invert getters and posting the display-options notification **did move the hosted values**. The AppKit source for
  those three is therefore the one SwiftUI's hosted view followed. Show borders, dim flashing lights and animated images are not `NSWorkspace` values and are unmeasured against SwiftUI's source.
- **C0/C1**: `Color.primary`, `.secondary`, `.gray`, `.accentColor` change under `_colorSchemeContrast = .increased`; so do the pixels of `Button` `.bordered` and `.plain`, both `Toggle` styles, `Divider` and
  `Picker` `.segmented` (`TextField` and `Button` `.borderless` did not): divergence 1076.
- **B1**: show borders changes `Button` `.bordered` and `Toggle` `.checkbox`: divergence 1078. **D1, I1**: no pixel moved in any control: no divergence, record 05 rows.
- **L1**: `Text` ink widens under `.bold` (207 to 218), `.regular` equals `nil`: divergence 1079. H0: a hosted view reads `legibilityWeight == nil`, so the window stamps none.

## 3. Design (built)

`ColorSchemeContrast`, `LegibilityWeight`, `AccessibilityDisplaySettings` in `MetalUICore` (`AD-B`); one defaultless pair on `PlatformWindow` (`AD-C`); an internal `EnvironmentValues.accessibilityDisplay`
behind six `public internal(set)` keys plus the alias and a writable `legibilityWeight` (`AD-D`); `Window` reads, observes and stamps (`AD-E`); SDL answers the standard values (`AD-F`); AppKit reads
`NSWorkspace`, `Accessibility` and `MediaAccessibility` in one file and re-reads on the display-options notification, the MA and AX notifications and activation (`AD-G`); headless (`AD-H`); fingerprint 29 to 31
fields (`AD-K`). **Deviations from the plan**: the demo is `METALUI_ACCESSIBILITY_DEMO=1`, a root of its own (adding the panel under `looksDemoContent()` failed
`theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges`); `AXShowBordersEnabledStatusDidChangeNotification`'s value is the workspace display-options name, so no separate observer is needed;
`AccessibilityDisplaySettings`'s `playAnimatedImages` default is false (V0); optional test 21 (`EOKey`) was not written.

## 4. Tests
