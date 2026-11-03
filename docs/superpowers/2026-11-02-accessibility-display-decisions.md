# Accessibility display settings — decisions (prefix `AD-`)

Rulings for round-3 item R3-10 item 7: `colorSchemeContrast`, `accessibilityDifferentiateWithoutColor`, `accessibilityInvertColors`, `accessibilityShowBorders` (and its alias
`accessibilityShowButtonShapes`), `accessibilityDimFlashingLights`, `accessibilityPlayAnimatedImages`, `legibilityWeight`. Branch `feat/accessibility-display` from master `76b03e58`.
Code: `Sources/MetalUICore/AccessibilityDisplay.swift`, `Sources/MetalUIAppKit/AppKitAccessibilityDisplay.swift`, `Sources/MetalUI/EnvironmentValues.swift`, `Window.swift`,
`Sources/MetalUIPlatform/Platform.swift`. Probe: `docs/probes/swiftui-accessibility-display.swift` (recorded, compiled, two identical runs). Tests: `AccessibilityDisplayTests.swift`,
`AccessibilityDisplayCompileGuards.swift`, `Tests/MetalUICoreTests/AccessibilityDisplaySettingsTests.swift`, `AppKitAccessibilityDisplayTests.swift`,
`HarnessAccessibilityDisplayTests.swift`, `RetainedAccessibilityDisplayTests.swift`, `SDLAccessibilityDisplayTests.swift`. Record: `docs/record/194-accessibility-display.md`.

**State.** Every ruling is built. Divergences 1075, 1076, 1078 and 1079 used; 1077 and 1080 were reserved for probe arms D1 and I1 and came out zero (section-05 rows, labels unused), 1081-1084
unused. **Next unused: `AD-M`.**

## AD-A: scope

Built: the six get-only keys above and writable `legibilityWeight`. Carried (rows in `docs/divergences.md` "Not offered"): `accessibilityVoiceOverEnabled` and
`accessibilitySwitchControlEnabled`, `accessibilityPrefersCrossFadeTransitions`, `accessibilityIgnoresInvertColors`, assistive access. Consumers: values are exposed; no built-in reacts
(`AD-I`).

## AD-B: types, in `MetalUICore`

`ColorSchemeContrast` (`standard`, `increased`; `CaseIterable`), `LegibilityWeight` (`regular`, `bold`; not `CaseIterable`, as SwiftUI's is not: probe A), and
`AccessibilityDisplaySettings` (six public vars, a public memberwise init). **Its defaults are a bare SwiftUI `EnvironmentValues()`'s (probe V0), including `playAnimatedImages == false`**: the
plan guessed `true`, V0 read `false` (a hosted app reads `true`, H0). A platform with no such setting therefore answers `true` explicitly (`AD-F`, `AD-H`).

## AD-C: one seam pair

`PlatformWindow.accessibilityDisplaySettings` and `onAccessibilityDisplaySettingsChange`, no defaults (a conformer that forgets them fails to compile, guard 13). Reduce Motion and Reduce
Transparency keep their own pairs (`AN-AD`, `MT-D`).

## AD-D: environment

An internal stored `accessibilityDisplay: AccessibilityDisplaySettings` and six `public internal(set)` computed keys forwarding to it; `accessibilityShowButtonShapes` is a get-only alias of
`accessibilityShowBorders`, not deprecated (SwiftUI marks it deprecated and warns nowhere: probe A). `legibilityWeight: LegibilityWeight?` is a stored writable key, `nil` bare.

## AD-E: window

`Window.accessibilityDisplaySettings` is `private(set)` with a guarded `didSet` -> `setNeedsRedraw()`, read in `init`, updated by the callback `Window.init` installs, stamped over
`rootEnvironment` in `drawFrame` beside `MT-D`'s stamp; never written through `Window.environment`. `renderFrame` stamps the bare value.

## AD-F: SDL

Answers `AccessibilityDisplaySettings(playAnimatedImages: true)` and never fires (divergence 1075). Carried: Windows `SPI_GETHIGHCONTRAST`, GNOME `high-contrast`, KDE.

## AD-G: AppKit

`AppKitWindow.systemAccessibilityDisplaySettings()` (the only file importing `Accessibility` and `MediaAccessibility`): contrast, differentiate and invert from `NSWorkspace`; show borders from
`AccessibilitySettings.showBordersEnabled` under `#available(macOS 26.1, *)`; dim flashing lights from `MADimFlashingLightsEnabled()`; animated images from
`AccessibilitySettings.animatedImagesEnabled` (macOS 15) or `AXAnimatedImagesEnabled()`. Re-read on the workspace display-options notification, the Media Accessibility and Accessibility
notifications on `notificationCenter`, and `NSApplication.didBecomeActiveNotification`; reported only when the struct differs from the last reading. **Measured while building:**
`AXShowBordersEnabledStatusDidChangeNotification`'s string value is `NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification`, so the existing workspace observer already carries it. Doc
comments say what MetalUI reads, never "as SwiftUI does", except for the three `NSWorkspace` values, where probe H1 moved SwiftUI's hosted value with the swizzled getter.

## AD-H: headless (`HT-X` item 1)

`HeadlessPlatformWindow.Options.accessibilityDisplaySettings` (default: nothing on, `playAnimatedImages` true, AppKit's answer), `accessibilityDisplaySettings`,
`onAccessibilityDisplaySettingsChange`, `simulateAccessibilityDisplaySettingsChange(to:)`; `TestWindow.setAccessibilityDisplaySettings(_:)` draws.

## AD-I: no built-in consumer

Probe C0/C1: SwiftUI's colours and its bordered/plain `Button`, both `Toggle` styles, `Divider` and segmented `Picker` change under `.increased` (divergence 1076); B1: bordered `Button` and
checkbox `Toggle` change under show borders (1078); D1 and I1: nothing changes (no divergence; section-05 rows); L1: `Text` widens under `.bold` (1079). MetalUI draws none of these:
guard `noBuiltInControlReactsToAccessibilityDisplaySettings`. The demo panel (`METALUI_ACCESSIBILITY_DEMO=1`) is the visible consumer; it is a root of its own because the looks demo's
pins read its layout (adding the panel there failed `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges`).

## AD-J: `legibilityWeight`

Writable, bare `nil`. H0: a hosted view reads `nil`, so the window stamps none. `Text` does not read it (divergence 1079).

## AD-K: retained

`EnvironmentFingerprint` gains `accessibilityDisplay` and `legibilityWeight` (29 to 31 fields); `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` and
`everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone` carry the rows.

## AD-L: migration

A `PlatformWindow` conformer outside this repository adds `var accessibilityDisplaySettings: AccessibilityDisplaySettings { AccessibilityDisplaySettings() }` and
`var onAccessibilityDisplaySettingsChange: ((AccessibilityDisplaySettings) -> Void)?` (`docs/migration.md`).

## Carried

VoiceOver and Switch Control enabled, cross-fade transitions, `accessibilityIgnoresInvertColors`; Windows, GNOME and KDE high-contrast sources; high-contrast theme variants for MetalUI's
own colours and controls (divergence 1076); folding `MT-D`'s and `AN-AD`'s pairs into `AccessibilityDisplaySettings`; whether Media Accessibility posts on the default centre (unmeasured:
the activation backstop covers it, human checks AD5-AD7).
