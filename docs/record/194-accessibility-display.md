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

`AccessibilityDisplaySettingsTests.swift` (2, portable), `AccessibilityDisplayTests.swift` (5: bare defaults and `renderFrame`, window stamp, one key per field, `legibilityWeight` scoping,
no built-in reaction), `AccessibilityDisplayCompileGuards.swift` (3) and `aPlatformWindowWithoutTheDisplaySettingsPairDoesNotCompile` in `TransactionCompileGuards.swift` (1), the fingerprint tables
(two existing tests extended to 31 fields), `AppKitAccessibilityDisplayTests.swift` (4, swizzled `NSWorkspace` getters and an injected reader), `HarnessAccessibilityDisplayTests.swift` (2),
`RetainedAccessibilityDisplayTests.swift` (1), `SDLAccessibilityDisplayTests.swift` (1, in `Backends/SDL`). Eleven conformer fixtures gained the pair (grep `accessibilityReduceTransparency`). The
Media Accessibility, `Accessibility` and show-borders readers cannot be swizzled: human checks AD4-AD6. Optional test 21 (`EOKey.displaySettings`) was not written.

## 5. Mutations

Each applied to the committed tree in a throwaway `git worktree` (removed afterwards), `swift build --build-system native --build-tests`, then the 20 display tests run by name
(`swift test --build-system native --no-parallel --filter`); branch: all on `feat/accessibility-display` at `b9766225`, one mutation at a time, restored by `git checkout -- .`. "Reddened" names
every test of the 20 that failed.

| # | file | mutation | reddened |
|---|---|---|---|
| 1a | `AccessibilityDisplay.swift` init | `playAnimatedImages: Bool = false` to `= true` | `aBareEnvironmentAndRenderFrameReadSwiftUIsAccessibilityDisplayDefaults`, `theSettingsDefaultToSwiftUIsBareValuesV0`, `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 1b | `AccessibilityDisplay.swift` init | `colorSchemeContrast: ... = .standard` to `= .increased` | `aBareEnvironmentAndRenderFrameReadSwiftUIsAccessibilityDisplayDefaults`, `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone`, `theDisplayOptionsNotificationReportsADisplaySettingsChangeOnce`, `theSettingsDefaultToSwiftUIsBareValuesV0`, `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 2 | `AccessibilityDisplay.swift` | `ColorSchemeContrast` cases swapped (`increased` first) | `aBareEnvironmentAndRenderFrameReadSwiftUIsAccessibilityDisplayDefaults`, `colorSchemeContrastCasesAreSwiftUIsInOrder`, `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone`, `theAppKitReaderReadsContrastDifferentiateAndInvertFromNSWorkspace`, `theDisplayOptionsNotificationReportsADisplaySettingsChangeOnce`, `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 3a | `EnvironmentValues.swift` | `colorSchemeContrast` getter `{ .increased }` | `aBareEnvironmentAndRenderFrameReadSwiftUIsAccessibilityDisplayDefaults`, `theWindowStampsAccessibilityDisplaySettingsFromItsPlatformWindow`, `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 3b | `RenderFrame.swift` | stamp `AccessibilityDisplaySettings(colorSchemeContrast: .increased)` | `aBareEnvironmentAndRenderFrameReadSwiftUIsAccessibilityDisplayDefaults` |
| 4a | `Window.swift` `drawFrame` | drop `rootEnvironment.accessibilityDisplay = accessibilityDisplaySettings` | `aRetainedPaintReaderOfContrastRepaintsWhenTheSettingFlips`, `theWindowStampsAccessibilityDisplaySettingsFromItsPlatformWindow`, `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 4b | `Window.swift` `init` | `platformWindow.onAccessibilityDisplaySettingsChange = { ... }` replaced by `_ = { ... }` (not installed) | `aDisplaySettingsReportRedrawsOnlyWhenItChanges`, `aRetainedPaintReaderOfContrastRepaintsWhenTheSettingFlips`, `theWindowStampsAccessibilityDisplaySettingsFromItsPlatformWindow`, `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 4c | `Window.swift` `didSet` | delete `guard accessibilityDisplaySettings != oldValue else { return }` | `aDisplaySettingsReportRedrawsOnlyWhenItChanges`, `theWindowStampsAccessibilityDisplaySettingsFromItsPlatformWindow` |
| 4d | `Window.swift` `didSet` | delete `setNeedsRedraw()` | `aDisplaySettingsReportRedrawsOnlyWhenItChanges`, `aRetainedPaintReaderOfContrastRepaintsWhenTheSettingFlips`, `theWindowStampsAccessibilityDisplaySettingsFromItsPlatformWindow`, `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 5a | `EnvironmentValues.swift` | `accessibilityInvertColors` getter reads `differentiateWithoutColor` | `eachDisplaySettingReachesOnlyItsOwnKey` |
| 5b | `EnvironmentValues.swift` | `accessibilityShowButtonShapes { false }` | `eachDisplaySettingReachesOnlyItsOwnKey` |
| 6 | `Window.swift` `drawFrame` | add `rootEnvironment.legibilityWeight = .regular` | `legibilityWeightIsScopedNearestWriterWins`, `theWindowStampsAccessibilityDisplaySettingsFromItsPlatformWindow`, `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 7 | `Button.swift` `requestChromeLayout` | `if bordered, environment.colorSchemeContrast == .increased { decorated.background = Color(red: 0.1, green: 0.1, blue: 0.1) }` | `noBuiltInControlReactsToAccessibilityDisplaySettings` |
| 8 | `RetainedSubtreeInternalTests.swift` | remove the `"legibilityWeight": "fingerprint"` row | `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` |
| 9 | `EnvironmentValues.swift` `differences(from:)` | delete the `accessibilityDisplay` line | `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone` |
| 10 | `EnvironmentValues.swift` | `public internal(set) var colorSchemeContrast` to `public var` | `theAccessibilityDisplayKeysAreReadOnlyOutsideMetalUI` |
| 11 | `EnvironmentValues.swift` | `public var legibilityWeight` to `public internal(set) var` | `legibilityWeightIsWritableByAScopeOutsideMetalUI` |
| 12b | `AccessibilityDisplay.swift` | `public var showBorders` to `package var showBorders` | `accessibilityDisplaySettingsIsConstructibleOutsideItsModule` |
| 13 | `Platform.swift` | `public extension PlatformWindow { var accessibilityDisplaySettings ... { AccessibilityDisplaySettings() } }` (the getter only; a settable property cannot take a default) | `aPlatformWindowWithoutTheDisplaySettingsPairDoesNotCompile` |
| 14a | `AppKitAccessibilityDisplay.swift` | `invertColors: workspace.accessibilityDisplayShouldDifferentiateWithoutColor` | `theAppKitReaderReadsContrastDifferentiateAndInvertFromNSWorkspace` |
| 14b | `AppKitAccessibilityDisplay.swift` | `colorSchemeContrast: .standard` | `theAppKitReaderReadsContrastDifferentiateAndInvertFromNSWorkspace` |
| 15a | `AppKitPlatform.swift` `accessibilityDisplayOptionsNotification` | delete `refreshAccessibilityDisplaySettings()` | `theDisplayOptionsNotificationReportsADisplaySettingsChangeOnce` |
| 15b | `AppKitPlatform.swift` `refreshAccessibilityDisplaySettings` | delete `guard settings != lastAccessibilityDisplaySettings` | `theDisplayOptionsNotificationReportsADisplaySettingsChangeOnce` |
| 16a | `AppKitAccessibilityDisplay.swift` | delete the Media Accessibility `addObserver` | `theFlashingLightsAndAnimatedImagesNotificationsReReadTheSettings` |
| 16b | `AppKitPlatform.swift` `observeControlActiveState` | delete `observeAccessibilityDisplaySettingsNotifications()` | `theFlashingLightsAndAnimatedImagesNotificationsReReadTheSettings` |
| 17 | `AppKitPlatform.swift` `controlActiveStateNotification` | delete the `didBecomeActiveNotification` refresh | `anApplicationActivationReReadsTheDisplaySettings` |
| 18 | `HeadlessPlatformWindow.swift` `init` | `self.accessibilityDisplaySettings = AccessibilityDisplaySettings(playAnimatedImages: true)` (option ignored) | `theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform` |
| 20 | `EnvironmentValues.swift` `retainedFingerprint` | `accessibilityDisplay: AccessibilityDisplaySettings()` | `aRetainedPaintReaderOfContrastRepaintsWhenTheSettingFlips` |

**Findings.** (1) Mutation 12 as planned, `public init` to `package init`, **does not build**: `HeadlessPlatformWindow.Options.init` uses `AccessibilityDisplaySettings(playAnimatedImages: true)` as a
default argument, which a package initialiser cannot be. The guard's surviving half, "every field is settable from outside", is mutated by 12b. An `internal` initialiser cannot be mutated in at all
(`Window` constructs the type from another module). (2) Mutation 6 reddens only the "the window stamps no weight" arms: a root stamp cannot override a nearer scope, so the nearest-writer arm of
`legibilityWeightIsScopedNearestWriterWins` has no mutation of its own (the scope is `EnvironmentScope`'s, `EV-A`). (3) Mutation 13 defaults the getter only: a settable requirement cannot take a
protocol-extension default alone, and the guard names the callback in the negative. (4) The Media Accessibility read and the show-borders read are unreddenable by mutation of a system setting:
the injected-reader tests pin the wiring, not the OS value. (5) SDL mutation 22, `AccessibilityDisplaySettings(colorSchemeContrast: .increased, playAnimatedImages: true)`, reddens
`anSDLWindowReportsStandardAccessibilityDisplaySettings` (3 issues; run from `Backends/SDL`).

## 6. Counts

2026-11-02, `swift package clean`, `swift build --build-system native --build-tests`, unfiltered `swift test --build-system native --no-parallel`: **4978 tests in 14 suites passed**, 0 failures,
0 goldens; the guards ran (`AD-D`, `AD-J`, `AD-B`, `AD-C` lines printed; `FR-J no-argument frame: succeeded=true`); guards 283 `@Test` functions calling `typecheck(`/`typecheckFile(`, 530 call sites
(279 / 524 on 76b03e58 by the same script). `Backends/SDL` on macOS with the AccessKit flags: 33 + 351 tests, one failure, the known `SDLGPUShaderLibraryTests` temp-directory permission error
(NSCocoaErrorDomain 513); `anSDLWindowReportsStandardAccessibilityDisplaySettings` passed. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

## 7. Human checks

Group AD (`docs/verification/human-checks.md`), AD1-AD8, **not run**: every value changes only with a System Settings toggle, and whether Media Accessibility posts on the default centre is
unmeasured.

