# Colour and colour scheme — design

**Status: design (2026-10-03).** User request 2026-10-02, an item of the
gpui-gap priority list; **not a plan task**. Rulings `CR-A`…`CR-W` (critic revisions `CR-Q`…`CR-V`, §13; lane 1's findings `CR-W`) in
[`../2026-10-03-colour-decisions.md`](../2026-10-03-colour-decisions.md).
Record: `docs/record/75-colour.md`. Probes (new, outputs in their headers):
`docs/probes/swiftui-colour.swift` (SwiftUI, run three times byte-identical),
`docs/probes/swift-colour-overloads.swift` (compiled and run) and
`docs/probes/swift-colour-isolation-negative.swift` (must fail). Branch
`feat/colour` from `30a3dbf`.

**Motivation.** The user is porting the SMK keyboard configurator
(SwiftCrossUI, ~8,500 lines) whose whole look is RGB colours chosen per
light/dark mode. Today MetalUI can express neither half: every colour-taking
modifier takes one of nine `ColorToken`s, RGB exists only inside a
hand-written paint pass, and no colour scheme is readable while building.

## 0. Baseline (re-taken by the design session at `30a3dbf`)

`swift build --build-system native --build-tests`: **0 `error:`**, the one
`warning:` SwiftPM's deprecation notice. `swift test --build-system native
--no-parallel`: **`Test run with 2328 tests in 3 suites passed after 123.297
seconds`**, the `FR-J no-argument frame: succeeded=true` line present. 141
`canTypecheck`-gated test declarations (`grep -rh "enabled(if: canTypecheck"
Tests | wc -l`), 0 goldens, **82 live divergences, next label 116**
(`docs/divergences.md` lines 4 and 12). Screen **locked** throughout (lock
probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`): no
real-window capture in the design session.

## 1. What MetalUI has, and what SwiftUI does

### 1.1 Inventory

| Area | Today | File |
|---|---|---|
| Colour vocabulary | `ColorToken`, nine cases; `Theme`, nine stored `Hsla`s, an exhaustive `subscript(token:)`, `.light`/`.dark`, `forAppearance(_:)`. The doc says "never literals" (design spec §7.9). | `Sources/MetalUI/Theme.swift` |
| `Color` | `public struct Color: Element` (inferred `@MainActor`) holding `public var color: ColorToken`; fills its proposal, 10 on a nil axis. | `Sources/MetalUI/NativeElements.swift:575` |
| Colour currency | `Hsla` (theme storage, every `PaintPass.fill`), `Rgba` (interpolation, scene). | `Sources/MetalUICore/Color.swift` |
| Token-taking public API | 54 files mention `ColorToken`; the public signatures: `StyledElement.background/hoverBackground/focusBackground/border(×2)/hoverBorder(×2)/focusBorder(×2)` and `Decoration.init(background:hoverBackground:focusBackground:…)`, `BorderStyle.init(_:width:)`/`(_:widths:)` (`Box.swift`); `ProposalBase.background(_:)`/`border(_:width:cornerRadius:)` (+ deprecated `native…`) (`NativeModifiedContent.swift`); `background(_:in:)` (`ClipShape.swift`); `shadow(color:radius:x:y:)` ×2 (`Shadow.swift`); `Shape`/`ShapeView` `fill`, `fill(_:style:)`, `stroke(_:lineWidth:)`, `stroke(_:style:)`, `strokeBorder` ×2 (`ShapeView.swift`); `Text`/`ProposalText`/`TextField`/`TextEditor.foregroundColor(_:)`, `ElementGroup.foregroundStyle/foregroundColor`, `Text`/`ProposalText.foregroundStyle` (`TextModifiers.swift`); `Background.init(_:content:)`, `Rectangle.init(width:height:color:)` (+ deprecated `init(color:)`), `Color.init(_:)` (`NativeElements.swift`); `onTap(hoverColor:_:)`, `OnTapModifier.init(content:hoverColor:…)` (`NativeTappable.swift`). | as listed |
| Stored colour properties (public) | `Decoration.background`, `.hoverBackground`, `.focusBackground` (`ColorToken?`); `BorderStyle.color`; `Background.color`; `Rectangle.color`; `Color.color`; `Text`/`ProposalText`/`TextField`/`TextEditor.foregroundColor`; `OnTapModifier.hoverColor`. | as listed |
| Resolution sites for a caller's colour | `pass.theme[token]` at `NativeTappable.swift:59`, `ShapeView.swift:172,201`, `ProposalText.swift:102`, `ProposalAnimation.swift:62`, `NativeElements.swift:376,603`, `Shape.swift:252`, `TextField.swift:241`, `TextEditor.swift:273`, `Text.swift:324`, `RenderEffects.swift:245`, `AnimatedColor.swift:195,533,596,605,637`. Built-in chrome (`Tooltip`, `MenuPanel`, `AnchoredPresentation`, `Slider`, `ScrollChrome`, `Button`) reads fixed tokens and is untouched. | as listed |
| Colour animation | `animatedColor`/`animatedBackground`/`resolvedBorder` (`$anim-color` slot, `AnimatedColorState { token; inFlight }`), `storedAnimatedColor` (the `AnimationStore`, proposal `LayoutModifier` background/border/shadow at `ModifiedContent.swift:572,584,592` and legacy shadow at `RenderEffects.swift:244`). Baseline is the declared **token**, so a theme swap re-resolves and never fades. RGB lerp. | `AnimatedColor.swift`, `ProposalAnimation.swift` |
| Text colour | `resolveTextStyle` → `ResolvedTextStyle.foreground: ColorToken`; `EnvironmentValues.foregroundStyle: ColorToken?` (internal). Glyph tint is not animated. | `TextStyleResolution.swift`, `EnvironmentValues.swift:221` |
| Control accents | `controlAccent(_:) -> ColorToken` (`.accent` key, `.separator` otherwise). | `ControlLook.swift` |
| Appearance | `MetalUICore.Appearance` (`.light`, `.dark`); `PlatformWindow.appearance` + `onAppearanceChange`; `Window.theme` set from `Theme.forAppearance` at init and on every change, guarded. **No colour scheme in the environment.** | `Sources/MetalUICore/Appearance.swift`, `Sources/MetalUIPlatform/Platform.swift:20,34`, `Sources/MetalUI/Window.swift:119,589,617` |
| Theme in the environment | `EnvironmentValues.theme` internal; `.theme(_:)` the only writer; `Frame.scopedValues` re-stamps it after a transform (`EV-U`); `PaintPass.theme` the only reader (`EV-G`, guarded by `readingTheThemeDuring{Layout,Prepaint}DoesNotCompile`). | `EnvironmentValues.swift:237`, `Frame.swift:359–450`, `EnvironmentScope.swift:188` |
| AppKit appearance | `MetalHostView.viewDidChangeEffectiveAppearance` → `onAppearanceChange(appearance)`; `appearance` reads `effectiveAppearance.bestMatch`. No `NSWindow.appearance` write anywhere. | `AppKitPlatform.swift:123,616,646` |
| SDL appearance | `appearance` = `mui_system_theme()` (`SDL_GetSystemTheme`); `SDL_EVENT_SYSTEM_THEME_CHANGED` → `MUI_EVENT_THEME` → every window's `appearanceChanged()`. | `SDLPlatform.swift:167,250,510`, `SDLBridge.c:813,1036` |
| Platform window conformers | `AppKitWindow`, `SDLWindow`, `FakePlatformWindow`, and fixture conformers in `TransactionCompileGuards`, `MenuCompileGuards`, `ControlStateCompileGuards`, `DragAndDropCompileGuards`. | as listed |
| Canvas | **None**: MetalUI has no `Canvas`; a hand-written element paints `Hsla` through `PaintPass.fill`. `Path` fills go through `ShapeView`. | — |
| Looks demo | `looksDemoContent()`, five section functions; **not** in the fourteen offscreen images nor `DemoFrameDeterminismTests`. Built on a 1 MB thread by `DemoStackBudgetTests`. | `Sources/MetalUIDemoContent/LooksDemo.swift` |

### 1.2 SwiftUI's answers (probe `swiftui-colour.swift`, macOS 27.0.1, system appearance Dark)

- **Literals** are gamma sRGB (`R1`: white 0.5 → 0.5); `.sRGBLinear` converts
  (`R3`); `.displayP3` → extended sRGB (`R4`); out-of-range values are kept
  in `Color.Resolved` and clamped when drawn (`R5`, `O4`, `O5`).
- **Every hue static is dynamic** (`N`), `black`/`white`/`clear` fixed;
  `primary` black/white @ 0.8471, `secondary` @ 0.4980 light / 0.5490 dark,
  `accentColor` the system accent (= `.blue` here).
- `opacity` multiplies (`O2`, `O3`). Equality compares components (`Q4`, `Q5`).
- `EnvironmentValues().colorScheme == .light` (`E0`); a hosted view reads the
  window's appearance and re-runs on a change (`E1`, `E2`, `T1`).
- `.preferredColorScheme` is **window-wide** and sets `NSWindow.appearance`
  (`P1`); first non-nil sibling wins, an outer modifier replaces its content's
  value including `nil` (`P3`–`P7`); `nil` resets the window's appearance
  (`P8b`). `.environment(\.colorScheme, …)` affects only its subtree (`V1`).
- `Color(light:dark:)` **does not exist**; a dynamic colour needs
  `NSColor(name:dynamicProvider:)` (`D1`). An app palette's SwiftUI answer is
  an asset catalog's named colour.

## 2. Public API

Every new declaration has a doc comment citing its ruling and an inventory
row (`A` SwiftUI-aligned, `M` MetalUI-only, `X` deprecated).

### 2.1 `MetalUICore` (lane 1)

```swift
public enum ColorScheme: Sendable, Hashable, CaseIterable { case light, dark }   // A — renamed from Appearance (CR-J)
public typealias Appearance = ColorScheme                                          // M — kept, not deprecated
```
New file `Sources/MetalUICore/ColorScheme.swift`; `Appearance.swift` deleted.

### 2.2 `Color` (lane 1, new file `Sources/MetalUI/Color.swift`)

```swift
public struct Color: Hashable, Sendable {                                   // CR-C, CR-D
    public enum RGBColorSpace: Hashable, Sendable { case sRGB, sRGBLinear }  // A (no displayP3, CR-C 6)
    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1)  // A
    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1)                           // A
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1)                          // A
    public init(_ token: ColorToken)                     // M (kept; moved from NativeElements.swift)
    public init(_ hsla: Hsla)                            // M
    public init(light: Color, dark: Color)               // M (CR-O)
    public init<K: ThemeColorKey>(_ key: K.Type)         // M (CR-N)
    public func opacity(_ opacity: Double) -> Color      // A (CR-G)

    public static let black, white, clear, gray, red, orange, yellow, green, mint, teal,
                      cyan, blue, indigo, purple, pink, brown: Color             // A (CR-F)
    public static let primary, secondary, accentColor: Color                     // A, divergence 116
    public static let background, surface, surfaceSecondary, accent, separator,
                      textPrimary, scrollIndicator, scrim, shadow: Color         // M (CR-E 2)

    public struct Resolved: Hashable, Sendable {                                 // A (CR-H 4)
        public var red: Float; public var green: Float; public var blue: Float; public var opacity: Float
    }
    public func resolve(in environment: EnvironmentValues) -> Resolved          // A, clamped (divergence 118)

    @available(*, deprecated, message: "a Color is a value now: compare it, or resolve it with PaintPass.resolve(_:)")
    public var color: ColorToken? { get }                                        // X
}
extension Color: Element { … }   // in NativeElements.swift, the view half, unchanged behaviour (CR-D)
```

### 2.3 Palette (lane 1, `Theme.swift`)

```swift
public protocol ThemeColorKey { static var defaultValue: Color { get } }          // M (CR-N)
extension Theme {
    public subscript<K: ThemeColorKey>(key: K.Type) -> Color { get set }         // M
}
```

### 2.4 Resolution in paint (lane 1, `Passes.swift`)

```swift
extension PaintPass { public func resolve(_ color: Color) -> Hsla }             // M (CR-H 1)
```

### 2.5 Colour-taking API (lane 1): a `Color` overload at every site

Each existing `ColorToken` declaration below **keeps its text**, gains
`@_disfavoredOverload` and forwards `Color(token)`; the new `Color`
declaration is the implementation (`CR-E`). Deprecated spellings get no twin.

| File | New `Color` declarations |
|---|---|
| `Box.swift` | `StyledElement.background(_ color: Color) -> Self`, `hoverBackground(_:)`, `focusBackground(_:)`, `border(_ color: Color, width:)`, `border(_:widths:)`, `hoverBorder(_:width:)`, `hoverBorder(_:widths:)`, `focusBorder(_:width:)`, `focusBorder(_:widths:)`; `Decoration.init(background: Color? = nil, cornerRadius:, hoverBackground: Color? = nil, focusBackground: Color? = nil, border:, hoverBorder:, focusBorder:, opacity:, clipsContent:)`; `BorderStyle.init(_ color: Color, width:)`, `init(_:widths:)` |
| `NativeModifiedContent.swift` | `ProposalBase.background(_ color: Color)`, `border(_ color: Color, width:cornerRadius:)` |
| `ClipShape.swift` | `background<S: Shape>(_ color: Color, in shape: S)` |
| `Shadow.swift` | `shadow(color: Color = .shadow, radius:x:y:)` on both vocabularies |
| `ShapeView.swift` | on `Shape` and `ShapeView`: `fill(_ color: Color)`, `fill(_:style:)`, `stroke(_:lineWidth:)`, `stroke(_:style:)`, `strokeBorder(_:lineWidth:)`, `strokeBorder(_:style:)` |
| `TextModifiers.swift` | `ElementGroup.foregroundStyle(_ color: Color)`, `foregroundColor(_ color: Color?)`; `Text.foregroundStyle(_:)`, `ProposalText.foregroundStyle(_:)` |
| `Text.swift`, `ProposalText.swift`, `TextField.swift`, `TextEditor.swift` | `foregroundColor(_ color: Color?)` (`nil` = inherit, SwiftUI's optional) |
| `NativeElements.swift` | `Background.init(_ color: Color, content:)`, `Rectangle.init(width:height:color: Color = .surface)` |
| `NativeTappable.swift` | `onTap(hoverColor: Color? = nil, _:)`, `OnTapModifier.init(content:hoverColor: Color?…)` |

Stored properties retyped to `Color`/`Color?` (`CR-E` 3): the list in §1.1's
"Stored colour properties" row, `Color.color` excepted (deprecated getter).

### 2.6 Colour scheme (lane 2)

```swift
extension EnvironmentValues { public var colorScheme: ColorScheme }    // A — stored field added by lane 1 (EnvironmentValues.swift is lane 1's), stamped by lane 2; the theme variants are NOT environment fields (CR-S)
extension ElementGroup {
    public func preferredColorScheme(_ colorScheme: ColorScheme?) -> EnvironmentScope<Self>   // A (CR-L)
}
// Window
public private(set) var colorScheme: ColorScheme        // M (CR-J 3)
public var preferredColorScheme: ColorScheme?           // M (CR-L 4)
public var lightTheme: Theme                            // M (CR-K 1)
public var darkTheme: Theme                             // M
// App
public var preferredColorScheme: ColorScheme?           // M
public var lightTheme: Theme                            // M (CR-N 4)
public var darkTheme: Theme                             // M
// PlatformWindow (defaultless, CR-M)
func setPreferredColorScheme(_ colorScheme: ColorScheme?)
```

## 3. Semantics

### 3.1 Resolution (`CR-H`)

One internal function, `Color.resolved(theme: Theme, scheme: ColorScheme, depth: Int = 0) -> Hsla`:

| Provider | Result |
|---|---|
| `srgb(r,g,b,a)` | each component clamped to `0…1` (NaN → 0), `Rgba(…).toHsla()` |
| `token(t)` | `theme[t]` — **the same `Hsla` value, no round trip** |
| `dynamic(l, d)` | `(scheme == .dark ? d : l).resolved(…)` |
| `palette(id, def)` | `(theme.palette[id] ?? def).resolved(…, depth + 1)`; `depth == 16` traps `"ThemeColorKey cycle through <Key>"` |

then, when the stored opacity is not 1, `a *= clamp(opacity)` (clamped to
`0…1`). `PaintPass.resolve(_:)` and the frame's internal twin pass the
**element's environment theme and `colorScheme`** (`pass.theme`,
`pass.environment.colorScheme` — read in place, not through a counted
snapshot). `Color.resolve(in:)` passes `environment.theme` and
`environment.colorScheme` and converts to `Resolved` through `toRgba()`.

### 3.2 Named statics (`CR-F`), the hue table (probe `N`, sRGB hex)

| Static | light | dark |
|---|---|---|
| gray | `8E8E93` | `98989D` |
| red | `FF383C` | `FF4245` |
| orange | `FF8D28` | `FF9230` |
| yellow | `FFCC00` | `FFD600` |
| green | `34C759` | `30D158` |
| mint | `00C8B3` | `00DAC3` |
| teal | `00C3D0` | `00D2E0` |
| cyan | `00C0E8` | `3CD3FE` |
| blue | `0088FF` | `0091FF` |
| indigo | `6155F5` | `6D7CFF` |
| purple | `CB30E0` | `DB34F2` |
| pink | `FF2D55` | `FF375F` |
| brown | `AC7F5E` | `B78A66` |

Each is `Color(light: Color(red: 0xRR/255, …), dark: …)`. `black`/`white`
are `Color(white: 0)`/`Color(white: 1)`, `clear` `Color(white: 0, opacity:
0)`. `primary` = `.textPrimary`; `secondary` = `Color(light:
Color(.textPrimary).opacity(0.588), dark: Color(.textPrimary).opacity(0.648))`;
`accentColor` = `.accent`.

### 3.3 Animation (`CR-H` 3)

`AnimatedColorState { var color: Color; var inFlight: ColorAnimation? }`,
`ColorAnimation.to: Color`, `ColorEnd.declared(Color)` /
`.fixed(Rgba)`; `advanceColor(_ color: Color, from:, context:, now:,
transaction:)` compares **declared `Color`s** (never resolved values) and
resolves both ends against this frame's context. `animatedColor`,
`animatedBackground`, `resolvedBorder`, `storedAnimatedColor` keep their
shapes with `Color` for `ColorToken`. Everything else in `AnimatedColor.swift`
— the RGB lerp, clamping in flight, the interruption rule, `noteActiveAnimation`,
the `$anim-color` slot name — is unchanged. Re-measure
`MemoryLayout<AnimatedColorState>.stride` (120 at `30a3dbf`) and record it.

### 3.4 Colour scheme (`CR-J`, `CR-K`, `CR-L`)

`Window` holds `platformAppearance` (last reported), `treePreference`
(collected from the last frame), `preferredColorScheme` (programmatic),
`lightTheme`, `darkTheme`. `requested = treePreference ?? preferredColorScheme`;
`colorScheme = requested ?? platformAppearance`. When `requested` changes:
`platformWindow.setPreferredColorScheme(requested)`. When `colorScheme`,
`lightTheme` or `darkTheme` changes: `theme = colorScheme == .dark ? darkTheme
: lightTheme` (the existing guarded `didSet` repaints). `colorScheme` itself
is guarded. At each draw: `rootEnvironment.colorScheme = colorScheme` beside
`controlActiveState`; the frame **holds** the window's `lightTheme`/`darkTheme`
(new `Frame.init` parameters defaulting to `.light`/`.dark`, so every
existing `Frame(…)` test call compiles) as frame fields, not environment
fields (`CR-S`).

`Frame.scopedValues(applying: .transform)`: after the transform, re-stamp
`theme` from the top (as today); then if
`values.colorScheme != environmentTop.colorScheme`, set `values.theme` to the
frame's variant for the new scheme (`CR-S`). `.theme(t)` sets `theme` only.

`preferredColorScheme` is an `EnvironmentWrite.preferredColorScheme(ColorScheme?)`
case: values unchanged; in **both** `EnvironmentScope.requestGroupLayout` and
`requestProposalGroupLayout`, `frame.withColorSchemePreference(value) { content }`:
if `frame.preferenceScopeDepth == 0 && frame.preferredColorScheme == nil`,
record `value` — into the main root's slot, or, while a presentation root is
being laid out, the presentation slot; the main root's non-nil value wins
(`CR-T`); depth `+= 1` around the content. Prepaint and paint do
nothing. After `renderRoot(frame)`: if `framesDrawn == 0` and the collected
preference changes the effective scheme, apply it, **adopt the first build in
full** and run the build-and-adopt half once more inside the same
`beginFrame()`; only the second build is published to accessibility and
encoded (`CR-Q` — nothing is discarded); otherwise, on a change, apply it and
`setNeedsRedraw()`.

### 3.5 Palette (`CR-N`)

`Theme` gains `var palette: [ObjectIdentifier: Color] = [:]` (internal,
synthesized into `==`/`hash`). `Theme.light`/`.dark` hold none. The
subscript reads `palette[ObjectIdentifier(K.self)] ?? K.defaultValue` and
writes the dictionary. `Color(K.self)` stores `palette(ObjectIdentifier(K.self),
defaultValue: K.defaultValue)` and the key's type name for the trap message.

## 4. Implementation by platform

- **Portable (all of `MetalUI`)**: everything in §2–§3 except the two
  platform conformances. `Color.swift` uses `Foundation.pow` for the sRGB
  transfer function (`MetalUI` already imports Foundation).
- **Renderer**: none (`CR-I`). `shaders.metal` and `replay.hlsl` unchanged;
  the replay-parity harness has nothing new to compare.
- **AppKit** (`AppKitWindow.setPreferredColorScheme`): `window.appearance =
  scheme.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }`.
- **SDL** (`SDLWindow.setPreferredColorScheme`): stores
  `private(set) var preferredColorScheme` and does nothing else; `appearance`
  still reads `mui_system_theme()`. Doc comment states the decoration
  constraint (`CR-M`).
- **Fakes**: `FakePlatformWindow.preferredColorSchemeRequests: [ColorScheme?]`;
  the four fixture conformers add an empty method.

## 5. How tests drive it headless

- **Values**: `Color.resolve(in:)` against an `EnvironmentValues` whose
  `colorScheme` (public) and `theme` (internal, `@testable`) are set — no
  frame, no Metal; these live in **`Tests/MetalUICrossPlatformTests`** so
  Linux and Windows CI run them.
- **Paint**: `Frame(contentSize:scaleFactor:theme:)` + `render`, reading
  `finalizedScene()` rects/glyphs, as `ThemeTests` and `AnimationTests` do;
  `colorFrame`/`probeTheme` from `AnimationTests` for fades.
- **Scheme**: `makeFakeWindow(device:appearance:)` +
  `FakePlatformWindow.simulateAppearanceChange(to:)`; a `Component` whose body
  appends `@Environment(\.colorScheme)` to a test-owned log records what the
  build read; `drawFrameIfNeeded()`, `needsRedraw`, `framesDrawn`,
  `pausesEntered` for wake-up and pause facts; state flipped from input via
  `window.dispatch`/the fake's `onInput`, never from a phase.
- **AppKit**: a real `AppKitWindow` in `MetalUIPlatformTests`, as
  `theWindowFollowsTheApplicationsEffectiveAppearance` does (headless; a
  locked screen does not stop it).
- **SDL**: `Backends/SDL/Tests/MetalUISDLTests`, every helper creating an
  `SDLPlatform` arming `armMainRunLoopExitCheck()`.
- **Typecheck guards**: `typecheckFile(_:importing:)` with a **plain**
  `import MetalUI` (what an external module can write, `SA-P`).

## 6. Tests, by lane — each with its red-before and the mutation that must redden it

"Red-before" is the state at the lane's starting commit. Every mutation is
committed-first, restored from a copy, run in the **full unfiltered** suite,
and every reddened test is named in the lane's report (and record §75).

### 6.1 Lane 1 — the colour value, palette, every colour-taking API

**`Tests/MetalUICrossPlatformTests/ColorValueTests.swift` (new, portable)**

| # | Test | Asserts | Red-before | Mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `literalInitialisersAuthorGammaSRGB` | `R0`, `R1` (white 0.5 → 0.5 ± 1e-6), `R2`, `R7` | does not compile (no `Color(red:…)`) | store `w * w` in `Color(white:)` |
| 1.2 | `sRGBLinearConvertsToGammaAtInit` | `R3`: 0.4845/0.6652/0.7977 ± 1e-4 | does not compile | treat `.sRGBLinear` as `.sRGB` |
| 1.3 | `hueSaturationBrightnessConvertsLikeSwiftUI` | `R6` (0.5,1,1)→(0,1,1); a hand-derived mid arm (0.1, 0.5, 0.8) → (0.8, 0.64, 0.4) (C = 0.4, X = 0.24, m = 0.4) | does not compile | HSL instead of HSB in the conversion |
| 1.4 | `everyNamedStaticResolvesToTheProbedValueInBothSchemes` | §3.2 table, 13 hues + black/white/clear, light and dark, `± 0.5/255` | does not compile | swap the halves in `dynamic` resolution; and, separately, one hex digit in `red`'s light value (only the `red` arm reddens) |
| 1.5 | `theSemanticStaticsResolveThroughTheTheme` | `.primary` = theme `textPrimary`, `.accentColor` = theme `accent`, `.secondary` = `textPrimary` at alpha × 0.588 / 0.648, under `Theme.light` and `Theme.dark` | does not compile | `accentColor` = fixed `.blue` |
| 1.6 | `opacityMultipliesAndClampsAtResolution` | `O1` 0.5, `O3` 0.25, `O4` → 1, `O5` → 0, `R5` → (1, 0, 0.5), NaN component → 0 | does not compile | `opacity(_:)` assigns instead of multiplying (O3 arm); and, separately, remove the clamp |
| 1.7 | `equalityComparesComponentsLikeSwiftUI` | `Q1`–`Q5`; `Color(.surface) == .surface`; `Color(Brand.self) == Color(Brand.self)` | does not compile | give `Color(white:)` its own provider case (Q4/Q5 redden) |
| 1.8 | `aTokenBackedColorResolvesBitExactlyToItsToken` | every `ColorToken.allCases` × both themes: `resolved == theme[token]` (`Hsla` `==`, not a tolerance) | does not compile | resolve `token` through `toRgba().toHsla()`; if that is bit-exact on every token, record it and use "resolve against `Theme.light` always" (dark arm) |
| 1.9 | `aDynamicColourFollowsTheEnvironmentsScheme` | `Color(light:dark:)` in both schemes; a dynamic of dynamics; `D2` opacity after selection | does not compile | ignore the scheme |
| 1.10 | `aBareEnvironmentReadsLightLikeSwiftUI` | `EnvironmentValues().colorScheme == .light` (`E0`); `ColorScheme.allCases == [.light, .dark]` (`Q6`) | does not compile | default `.dark` |

**`Tests/MetalUICrossPlatformTests/ColorPaletteTests.swift` (new, portable)**

| # | Test | Asserts | Red-before | Mutation |
|---|---|---|---|---|
| 1.11 | `aPaletteKeyResolvesItsDefaultPerScheme` | `Color(Brand.self)` light/dark = the key's `Color(light:dark:)` halves | does not compile | palette resolution always takes the light half |
| 1.12 | `aThemeOverrideWinsAndIsPerTheme` | `t = .dark; t[Brand.self] = X` → resolves X under `t`, the default under `.light`; `t[Brand.self]` reads X, `Theme.light[Brand.self]` reads the default | does not compile | getter ignores `palette` |
| 1.13 | `aPaletteOverrideIsPartOfTheThemesEquality` | `t != .dark` after the override (an override equal to the key's default is still an entry, so still `!=`); a second theme with the same override `==` `t` and hashes equal | does not compile | custom `==` that skips `palette` |
| 1.14 | `everyBuiltInTokenIsUntouchedByAPalette` | a theme with three overrides: `ColorToken.allCases` resolve exactly as `Theme.dark`'s | does not compile | `subscript(token:)` consulting `palette` first |

**`Tests/MetalUITests/ColorPaintTests.swift` (new)**

| # | Test | Asserts | Red-before | Mutation |
|---|---|---|---|---|
| 1.15 | `aLiteralColourReachesEveryColourTakingSite` | one arm per §2.5 row and vocabulary (≈24 arms): render with `.red` (light), read the emitted rect/glyph/raster tint = `FF383C` | does not compile | in three sites — `StyledElement.background(_ color:)`, `Text.foregroundColor(_ color:)`, `Shape.fill(_ color:)` — replace the forwarded colour with `.surface`, one at a time; that arm reddens each time, and `Shape.fill`'s also reddens the `background(_:in:)` arm, which forwards to `shape.fill` (`CR-X` item 3) |
| 1.16 | `aColorViewFillsWithItsColourAndOpacityIsTheValueMethod` | `Color.red` as a view: one rect `FF383C`; `Color.red.opacity(0.5)`: one rect at alpha 0.5, and with `recordsElementBounds` the frame records as many element ids as for a bare `Color.red` (no opacity layer, so no extra identity level) | does not compile | make `Color.opacity` `@_disfavoredOverload` (the layer wins: scope count 1) |
| 1.17 | `paintPassResolveUsesTheElementsScopedThemeAndScheme` | inside `.theme(.dark)` and `.environment(\.colorScheme, .dark)` scopes, `pass.resolve(.surface)` and `pass.resolve(.red)` read the scoped answers | does not compile | `PaintPass.resolve` uses the root theme |
| 1.18 | `aSchemeChangeNeverStartsAFadeOnADynamicColour` | `Box().background(Color(light:A, dark:B))` under `.environment(\.colorScheme, s)`; frame 1 light; then inside `withAnimation(.linear(duration: 1))` frame 2 with `s = .dark`: reads B at once, `hasActiveAnimations == false` | does not compile | key the baseline on the resolved colour instead of the declared `Color` |
| 1.19 | `aFadeFromATokenToALiteralReResolvesTheTokenEnd` | `.surface` → `.red` under linear; at t = 0.5 swap `Theme.light` → `Theme.dark`: the midpoint moves by the token end only | does not compile | `ColorEnd.declared` resolved once at start (frozen) |
| 1.20 | `aPaletteCycleTrapsNamingTheKey` | exit test: `t[Brand.self] = Color(Brand.self)`, resolve → exits with failure (and, where the exit-test API captures stderr, the message names `Brand`) | does not compile | replace the trap with returning `.clear` (the test then sees no exit) |

**`Tests/MetalUITests/AnimationTests.swift` (edit)**

| # | Test | Change | Red-before | Mutation |
|---|---|---|---|---|
| 1.21 | `everyBackgroundPaintingSiteAnimatesItsColour` | a second `check` pass over all five sites with **literal** colours (`Color(red:0,green:0,blue:1)` → `Color(red:1,green:0.5,blue:0)`), hand-computed RGB midpoint at t = 0.5 (0.5, 0.25, 0.5) | the literal arms do not compile | in `animatedColor` and `storedAnimatedColor`, snap whenever the declared colour is not token-backed — **the literal arms redden, the token arms stay green** (the separating property) |
| 1.22 | the tests that pin border and shadow colour fades (`grep -n "border.colour\|shadow.colour\|borderColourStoreKey" Tests`) | each gains one literal arm | do not compile | the same mutation as 1.21 |

**`Tests/MetalUITests/ColorCompileGuards.swift` (new; three guards, each mutated red once)**

| # | Guard | Fixture (plain `import MetalUI`, `typecheckFile`) | Mutation that must redden it |
|---|---|---|---|
| 1.23 | `colourStaticsAreUsableOffTheMainActor` | `nonisolated func f(_ c: Color = .red) -> Color { c.opacity(0.5) }`; `struct K: ThemeColorKey { static let defaultValue = Color(light: .red, dark: Color(red: 0.1, green: 0.2, blue: 0.3)) }` | move `Element` onto `Color`'s primary declaration (`CR-D`) |
| 1.24 | `everyColorTokenSpellingStillCompiles` | every §2.5 site with a leading-dot token **and** with a `let t: ColorToken` variable; `x.decoration.background = .surface`; `rect.color == .accent` | delete `Text.foregroundColor(_ token:)`'s twin (the variable line fails); separately, remove `@_disfavoredOverload` from `StyledElement.background(_ token:)` (`.background(.surface)` becomes ambiguous) |
| 1.25 | `theSwiftUISpellingsTypecheckWithoutAmbiguity` | `Text("x").foregroundColor(.red)`, `.foregroundColor(nil)`, `.foregroundStyle(.secondary)`, `Box().background(.surface)`, `Rectangle().fill(.red)`, `.stroke(.blue, lineWidth: 2)`, `.shadow(radius: Pixels(4))`, `let c: Color = Color.red.opacity(0.5)`, `Color(.sRGB, red: 1, green: 0, blue: 0)`, `Color(white: 0.5)`, `Color(hue: 0.5, saturation: 1, brightness: 1)` | remove `@_disfavoredOverload` from `Shadow.swift`'s token twin (`shadow(radius:)` becomes ambiguous) |

Existing tests that **must stay green unchanged**: `everyTokenDiffersBetweenLightAndDark`,
`noTwoTokensCollideWithinAVariant`, `aThemeSwapAloneNeverStartsAFadeOnASettledElement`,
`aThemeChangeMidFlightMovesBothOfTheAnimationsEndpoints`,
`anInterruptedFadeFreezesItsFromEndAgainstALaterThemeSwap`,
`interruptingAColourFadeReTargetsFromItsCurrentValueAndVelocity`,
`aColorAnswersItsProposalAndTenOnANilAxis`, `readingTheThemeDuring{Paint,Layout,Prepaint}…`,
`theThemeIsNotReachableThroughTheEnvironment`, `theSevenRetentionSlotsAreMutuallyDistinct`,
the `BackgroundChainTests`. A test broken only by a stored property's retyping
(`CR-E` 3) is fixed at the read and named in the lane's commit.

### 6.2 Lane 2 — colour scheme, variants, preference, platform

**`Tests/MetalUITests/ColorSchemeTests.swift` (new)**

| # | Test | Asserts | Red-before | Mutation |
|---|---|---|---|---|
| 2.1 | `theWindowStampsItsPlatformsAppearanceAsTheColorScheme` | a `Component` reading `@Environment(\.colorScheme)` in its body logs `.dark` in a `.dark` fake, `.light` in a `.light` one; `window.colorScheme` agrees | `window.colorScheme` does not compile | do not stamp (root stays `.light`): the dark arm reddens |
| 2.2 | `anAppearanceChangeRebuildsWithTheNewScheme` | `simulateAppearanceChange(.dark)` → `needsRedraw`; next frame's body logs `.dark` and a `Color(light:dark:)` rect is the dark half | stamp absent | stamp the scheme captured at `init` |
| 2.3 | `aReportOfTheCurrentSchemeDoesNotWakeTheDisplay` | after a settled frame, `simulateAppearanceChange(.light)` in a light window leaves `needsRedraw == false` | `window.colorScheme` does not compile | remove `colorScheme`'s equality guard |
| 2.4 | `readingTheColorSchemeInEveryPhaseLetsTheDisplayLinkPause` | an element reading `pass.environment.colorScheme` in layout, prepaint and paint; after two draws a third `drawFrameIfNeeded()` pauses (`pausesEntered` + 1, `framesDrawn` unchanged) | stamp absent | write the stamp into `Window.environment` each draw (its `didSet` dirties) |
| 2.5 | `aColorSchemeScopeSelectsTheWindowsVariantForItsSubtree` | light window, `window.darkTheme = custom`: a `.background(.surface)` under `.environment(\.colorScheme, .dark)` reads `custom.surface`, its sibling `Theme.light.surface` (probe `V1`) | `darkTheme` does not compile | drop the variant re-stamp in `scopedValues` |
| 2.6 | `aSelfResetBelowADarkScopeReadsLightAndTheLightVariant` | `.environment(\.self, EnvironmentValues())` under a dark scope: scheme `.light`, `.surface` = light variant | — | re-stamp `colorScheme` from the top after a transform |
| 2.7 | `anExplicitThemeScopePinsTokensButNotTheScheme` | `.theme(.dark)` in a light window: `.surface` dark, `colorScheme` `.light`, `.red` the light half (`CR-K` 3) | — | `.theme(_:)` also writes `colorScheme = .dark` |
| 2.8 | `preferredColorSchemeIsWindowWide` | child `.preferredColorScheme(.dark)` (probe `P1`): the **sibling** logs `.dark` next frame; the fake recorded `[.dark]` | modifier does not compile | implement it as a scope write (`.environment(\.colorScheme, …)`): the sibling arm reddens |
| 2.9 | `thePreferredColorSchemeReductionMatchesSwiftUI` | arms `P3` dark, `P4` light, `P5` light, `P6` none (platform's), `P7` dark — each its own window | — | last-wins (P3, P4 redden); separately, inner-wins (P5, P6 redden) |
| 2.10 | `aPreferenceOnBothVocabulariesIsTransparentToLayoutAndIdentity` | legacy and proposal arms: the same tree with and without `.preferredColorScheme(.dark)` lays out identically, and a `@State` counter below it survives a change of the preferred value | — | make the scope consume a cursor slot (both arms); separately, record the preference only in `requestGroupLayout` (the proposal arm reddens, `OM-AI`) |
| 2.11 | `aRootPreferenceIsInTheFirstPresentedFrame` | root `.preferredColorScheme(.dark)` in a light fake: after the window's first `drawFrameIfNeeded()`, `framesDrawn == 1` and `lastScene`'s `.surface` rect is `Theme.dark.surface` | — | drop the first-frame rebuild |
| 2.12 | `aLaterPreferenceChangeAppliesOnTheNextFrame` | state flipped from input: the next frame is light and dirty, the one after dark, then `needsRedraw == false` | — | never re-dirty on a changed preference |
| 2.13 | `clearingThePreferenceReturnsToThePlatformsAppearance` | `.dark` → `nil` (`P8b`): the fake records `[.dark, nil]`, scheme = the fake's appearance | — | keep the last non-nil |
| 2.14 | `theTreesPreferenceWinsOverTheWindowsAndTheWindowsOverThePlatform` | `window.preferredColorScheme = .light`, tree `.dark` → dark; tree `nil` → light; both `nil` → platform | — | swap tree and window precedence |
| 2.15 | `theWindowsThemeFollowsItsVariantsAndADirectWriteLastsUntilTheNextChange` | `darkTheme = custom`, appearance → dark → `theme == custom`; `window.theme = .light` in dark → painted light until the next scheme change | — | `theme = Theme.forAppearance(…)` ignoring the variants |
| 2.16 | `appSchemeAndThemesReachEveryWindowBeforeItsFirstFrame` | `App(platform: FakePlatform)`; `app.darkTheme[Brand.self] = X`, `app.preferredColorScheme = .dark`, then `openWindow`: its first scene shows X; assigning again re-themes open windows | — | assign after `openWindow`'s first draw |
| 2.17 | `aPaletteOverrideOnTheWindowsVariantRepaints` | `window.darkTheme[Brand.self] = X` in a dark window → `needsRedraw`, next frame X | — | drop the variant → `theme` propagation |

**`Tests/MetalUITests/ColorSchemeCompileGuards.swift` (new; two guards, each mutated red once)**

| # | Guard | Mutation |
|---|---|---|
| 2.18 | `aPlatformWindowWithoutSetPreferredColorSchemeDoesNotCompile` (the `aPlatformWindowWithoutTheControlActiveStatePairDoesNotCompile` shape; expects the requirement's name in the diagnostic) | give the requirement a default in a protocol extension |
| 2.19 | `theAppearanceSpellingStillCompiles` (`let a: Appearance = ColorScheme.dark; let s: ColorScheme = a`, `Theme.forAppearance(.dark)`) | delete the typealias |

**Platform tests**

| # | Test | Where | Mutation |
|---|---|---|---|
| 2.20 | `settingAPreferredColorSchemeSetsTheNSWindowsAppearanceAndReportsIt` | `Tests/MetalUIPlatformTests/PlatformTests.swift`: `NSApp.appearance = aqua` first; `.dark` → `nsWindow.appearance?.name == .darkAqua` and `onAppearanceChange` fired `.dark`; `nil` → `appearance == nil` and `.light` reported | map `.dark` to `.aqua` |
| 2.21 | `setPreferredColorSchemeIsRecordedAndTheSystemThemeStillReports` | `Backends/SDL/Tests/MetalUISDLTests/SDLColorSchemeTests.swift` (new; helper arms `armMainRunLoopExitCheck()`): the stored value follows the calls; `appearance` equals `mui_system_theme() == 1 ? .dark : .light` | store nothing |

The four fixture conformers and `FakePlatformWindow` gain the method; the
`MUST NOT MOVE` guards (`theSevenRetentionSlotsAreMutuallyDistinct`, MC-A/C/P
numbering tests, `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`) stay
green unchanged.

### 6.3 Lane 3 — demo, docs, inventory

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 3.1 | `theLooksColourSectionPaintsLiteralDynamicAndPaletteColours` (`Tests/MetalUITests/LooksColourDemoTests.swift`, new) | `looksDemoContent()` in a light and a dark fake window: the `.red` swatch is `FF383C`/`FF4245`; the `Color(light:dark:)` swatch flips; the palette swatch shows the demo's dark override in the dark window | the demo's dynamic swatch written as a light-only literal |
| 3.2 | `everyProductionTreeBuildsOnAOneMegabyteThread` (existing) | stays green with the sixth section | — |
| 3.3 | `CloseoutTests` F1.3 / `ShadowTests` 3.28 (existing, build `looksDemoContent()`) | stay green; any count they pin that the new section moves is re-derived and the change named | — |

## 7. Demo expectation (lane 3)

`looksColourSection()` in `LooksDemo.swift`, its own function passed as a
sixth argument to `looksRoot` (1 MB Windows stack budget). It shows:

1. A row of 22 swatches (`Color` views, 28 × 28): the 13 hues, `black`,
   `white`, `clear` over a `.separator` border, `primary`, `secondary`,
   `accentColor`, a literal `Color(red: 0.2, green: 0.4, blue: 0.6)`, a
   `Color(light:dark:)` and the palette colour `Color(LooksBrand.self)`
   (`LooksBrand: ThemeColorKey`, declared in the demo content module), each
   labelled with a `Text` tinted `.secondary`.
2. A `Text` that reads `@Environment(\.colorScheme)` while building and
   prints `scheme: light`/`scheme: dark`.
3. A scheme toggle: a `Component` with `@State var choice` cycling System →
   Light → Dark through a `Button`, applying `.preferredColorScheme(choice)`
   to the section (window-wide by `CR-L`).
4. `MetalUIDemo/main.swift` sets `app.darkTheme[LooksBrand.self]` to a value
   different from `LooksBrand`'s dark default when `METALUI_LOOKS_DEMO=1`, so
   the palette override is visible.

The fourteen offscreen images do not contain the looks demo:
`docs/probes/demo-pixels/compare.sh <scratch> 30a3dbf HEAD` must read **0
differing in all fourteen** (every token path resolves bit-exactly, `CR-H`;
any non-zero is a finding, not a re-baseline). `Expected.swift` unedited.

## 8. Lanes and files (disjoint; run one at a time in the worktree)

| Lane | Model | Owns |
|---|---|---|
| **L1** colour value, palette, every colour-taking API | opus | `Sources/MetalUICore/ColorScheme.swift` (new), `Sources/MetalUICore/Appearance.swift` (deleted); `Sources/MetalUI/`: `Color.swift` (new), `NativeElements.swift`, `Theme.swift`, `EnvironmentValues.swift` (the `colorScheme` field only — the variants are frame fields, `CR-S`), `Passes.swift`, `AnimatedColor.swift`, `ProposalAnimation.swift`, `ModifiedContent.swift`, `RenderEffects.swift`, `Shadow.swift`, `Box.swift`, `NativeModifiedContent.swift`, `ClipShape.swift`, `ShapeView.swift`, `Shape.swift`, `Text.swift`, `ProposalText.swift`, `TextField.swift`, `TextEditor.swift`, `TextModifiers.swift`, `TextStyleResolution.swift`, `NativeTappable.swift`, `ControlLook.swift`, `Picker.swift`, `Slider.swift`, `Button.swift`, `Stack.swift` (the last five only if the retyping forces it); tests §6.1 and any test the retyping breaks |
| **L2** colour scheme, variants, preference, platform | opus | `Sources/MetalUIPlatform/Platform.swift`, `Sources/MetalUIAppKit/AppKitPlatform.swift`, `Sources/MetalUI/Window.swift`, `Frame.swift`, `EnvironmentScope.swift`, `App.swift`; `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`; `Tests/MetalUITests/Fakes.swift`, `TransactionCompileGuards.swift`, `MenuCompileGuards.swift`, `ControlStateCompileGuards.swift`, `DragAndDropCompileGuards.swift`, `ThemeTests.swift` (only if forced); `Tests/MetalUIPlatformTests/PlatformTests.swift`; tests §6.2 |
| **L3** demo, docs, inventory, cross-platform verification | sonnet for docs/inventory, opus for the demo | `Sources/MetalUIDemoContent/LooksDemo.swift`, `Sources/MetalUIDemo/main.swift`; `docs/divergences.md`, `docs/migration.md`, `docs/api-overview.md`, `docs/verification/human-checks.md`, `docs/probes/closeout-inventory-map.tsv`, `docs/probes/closeout-public-api.tsv`; tests §6.3 |

Shared, append-only, sequential: this spec and the decisions doc. A
compile-forced edit to another lane's file (type plumbing only) is allowed
and named in the commit. L1 and L2 leave `closeout-undocumented.sh` empty; L3
leaves `closeout-inventory-check.sh` empty and re-records the census.
`swift package clean` after L1 (the `ColorScheme` rename and `Color`'s
isolation cross module boundaries) and after L2 (new requirement).

## 9. Human checks — group S (lane 3 writes it in `docs/verification/human-checks.md`)

- **S1** Colours against a SwiftUI reference, side by side: run
  `METALUI_LOOKS_DEMO=1 swift run MetalUIDemo` next to a SwiftUI window built
  from the probe's named statics (a short snippet in the check). Expect each
  hue to match in hue and lightness, **slightly more saturated** in MetalUI
  (divergence 1), and `primary`/`secondary`/`accentColor` to differ by design
  (divergence 116). Both schemes.
- **S2** Live appearance switching: toggle System Settings → Appearance with
  the demo open. Content, title bar and the dynamic and palette swatches flip
  within a frame; nothing fades (`CR-H`); the `scheme:` label updates.
- **S3** The demo's scheme toggle: Light/Dark force the whole window (title
  bar, a context menu, a tooltip) regardless of the system; System returns to
  it. No one-frame flash visible on toggling.
- **S4** SDL (Linux or Windows): the system theme switch is followed; under
  the toggle the content flips while the native decorations stay with the
  system (`CR-M`).

## 10. Deferred (named, with reason and owner)

| Item | Reason | Owner |
|---|---|---|
| `ShapeStyle`, gradients, materials, hierarchical `.secondary` style | a second style type and its own probe surface; `Color` covers the port | none (a later gpui-gap item) |
| `.tint(_:)` / `.accentColor(_:)` modifiers | controls read the theme's accent today; needs its own probe of which controls follow tint | none |
| `Color.RGBColorSpace.displayP3` | needs a colour-managed pipeline; divergence 1 | none (divergence 1's) |
| `Color("Name", bundle:)` asset catalogs | no catalog compiler on Linux/Windows; `ThemeColorKey` is the typed answer | none |
| `Color(nsColor:)`, `Color(cgColor:)` | AppKit-only interop | none |
| `Color.Resolved` initialiser, linear accessors, `Color(_ resolved:)` | not needed by the port | none |
| `colorSchemeContrast`, Increase Contrast variants, the user's system accent | no portable source (SDL has none) | none |
| `preferredColorScheme` per presentation | MetalUI's popovers are in-window (`MN-M`) | none |
| `Text` glyph colour fades | unchanged behaviour; not requested | none |
| SDL native decorations following a preference | SDL3 has no API (`CR-M`) | none |

## 11. Acceptance (branch check)

- Unfiltered native suite: the summary line read, `FR-J … succeeded=` present;
  count = 2328 + the tests above (record the exact figure); every new guard
  mutated red once; 0 `error:`, the only native `warning:` the deprecation
  notice; `swift build --build-tests` 0 warnings.
- **MUST NOT MOVE** (unless a ruling names it, with a migration note):
  identity and state retention (`theSevenRetentionSlotsAreMutuallyDistinct`,
  `MC-A`/`MC-C`/`MC-P` numbering, `.id()` outermost), hit testing,
  accessibility, animation (beyond `CR-H`'s generalisation), focus, `List`
  windowing and `TB-AH`, `Deferred`, text input. `CR-G` is the one named
  identity change (a `Color` view's `.opacity(Double)` no longer adds a layer).
- Pixels: `compare.sh <scratch> 30a3dbf HEAD` 0 differing in all fourteen;
  `Expected.swift` unedited; `git diff 30a3dbf -- Sources/MetalUIRender/Shaders
  Backends/SDL/Shaders` empty.
- `MetalUILayout` imports only `MetalUICore`; `MetalUIScene` only
  `MetalUIShaderTypes` (unchanged; `ColorScheme` lives in `MetalUICore`).
- `Backends/SDL` builds and its tests pass (`PKG_CONFIG_PATH=$PWD/.accesskit`);
  a `swift:6.4-noble` container builds and runs the portable suites (the new
  `ColorValueTests`/`ColorPaletteTests` among them); C enum `rawValue`s
  converted explicitly.
- `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing;
  census re-recorded.
- Real-window capture only if the lock probe allows; otherwise S1–S4 stay
  human checks.

## 12. Documents (lane 3)

- **`docs/divergences.md`**: **116** (semantic statics through the theme, pin
  1.5), **117** (hue statics frozen at macOS 27 values on every platform, pin
  1.4), **118** (`Color.Resolved` clamped where SwiftUI keeps extended range,
  pin 1.6); amend **1** (literals share it, `CR-I`); the documented-absences
  table gains `displayP3`, asset-catalog colours, `ShapeStyle`/gradients
  (already listed: extend the row), `tint`. **119** (`.foregroundStyle(.secondary)`/`.primary`
  resolve the `Color` statics where SwiftUI infers `HierarchicalShapeStyle`,
  `CR-U`, probe `swiftui-colour-hierarchical.swift`). Header count and next
  label (120) updated.
- **`docs/migration.md`**: literals and `Color(light:dark:)`; palette keys;
  the stored properties' retyping (`CR-E` 3) with the `pass.resolve(_:)` /
  `Color(.token)` recipe; `Color(…).opacity(0.5)` is now a value (`CR-G`);
  `PlatformWindow.setPreferredColorScheme(_:)` for third-party conformers
  (`CR-M`); `Appearance` → `ColorScheme`.
- **`docs/api-overview.md`**: a Colour section (values, statics, scheme,
  preference, palette).

## 13. Critic revisions (2026-10-03, `CR-Q`…`CR-V`)

The three committed probes were re-run: identical output. Revisions, each a
ruling in the decisions doc; the sections above are edited to match:

- **`CR-Q`** (§3.4): the first-frame preference adopts the first build and
  builds again in the same `beginFrame()`; nothing is discarded. Test 2.11
  gains a `StateTable`-entry arm.
- **`CR-R`** (§2.2, §3.1): `Color` stores `Float`; NaN → 0 at init (a NaN
  declared colour would compare unequal to itself on every build and re-arm a
  fade on each build made under a transaction — the link stays awake only
  while such builds keep arriving, `CR-X` item 1); `MemoryLayout<Color>.size <= 24`
  pinned; `Decoration`/`BorderStyle`/`Text`/`EnvironmentValues` sizes recorded
  before and after. Lane 1 adds the NaN arm to 1.6 and
  `aNaNColourSettlesAndLetsTheDisplayLinkPause`.
- **`CR-S`** (§2.6, §3.4, §8): the light/dark variants are `Frame` fields, not
  `EnvironmentValues` fields.
- **`CR-T`** (§3.4): the main root's preference ranks before presentation
  roots'. Test 2.9 gains arm `PR`.
- **`CR-U`** (§12): divergence **119**, `.foregroundStyle(.secondary)` /
  `.primary`; 1.15 gains the tinted-parent arm; next label 120.
- **`CR-V`** (§6.2): 2.10 compares element-id sets with a following sibling;
  new **2.22** `aSchemeChangeRepaintsEvenWhenBothVariantsAreTheSameTheme`.
- **`CR-W`** (lane 1, implementation): `LayoutModifier`'s `.background`,
  `.border` and `.shadow` payloads are retyped to `Color` (a public enum the
  §1.1 inventory missed; migration note owed by lane 3); `CR-D`'s extension
  is `@MainActor extension Color: Element`; a literal folds `opacity(_:)`
  into its own opacity (§3.1's multiplier stays for the other providers); a
  palette colour stores its key's metatype (§3.5).
