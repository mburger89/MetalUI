# 75 — Colour and colour scheme

Branch `feat/colour` from `30a3dbf` (master: menus, popovers and tooltips
merged, PR #44). **Not a plan task**: new feature work requested by the user
on 2026-10-02, an item of the gpui-gap priority list. Motivation: the user is
porting the SMK keyboard configurator (SwiftCrossUI, ~8,500 lines) whose whole
look is RGB colours chosen per light/dark mode; MetalUI could express neither
half. Spec `docs/superpowers/specs/2026-10-03-colour-design.md`; rulings
`CR-A`…`CR-AB` in the new decisions doc
`docs/superpowers/2026-10-03-colour-decisions.md` (next unused `CR-AC`);
probes `docs/probes/swiftui-colour.swift`, `swiftui-colour-hierarchical.swift`,
`swift-colour-overloads.swift`, `swift-colour-isolation-negative.swift`.

**Numbering.** Written as §75 against master `30a3dbf`; `git fetch` at the
Record phase showed `origin/master` still at `30a3dbf` and §74 the last
record, so §75 stands. The human-checks group is **S** (Q paths, R menus).

**Status: LANDED — every agent-doable clause is built; the looks are owed to a
human** (`docs/verification/human-checks.md` group S, §7). Three lanes, each
red first, lanes 1 and 2 with a review round, all verified `ok: true`; the
Record phase (§9) re-took the suite and the counts.

## §0 Baseline, design session and critic round (2026-10-03)

- **Baseline** at `30a3dbf`: **2328 tests in 3 suites**, 0 goldens, 142
  typecheck guards (141 `canTypecheck`-gated declarations), 82 live divergences (next label 116; `CLAUDE.md`'s "70 /
  104" was stale), `Backends/SDL` 24 + 62, fourteen offscreen demo images.
  The screen was **locked** throughout: no real-window capture, no SwiftUI
  window seen by a human.
- **Carried item.** Design spec §7.9 ("colours in element code are semantic
  tokens, never literals") is superseded by `CR-B`: literal colours are part
  of the API, tokens stay.
- **Probes.** `swiftui-colour.swift` (arm ids `R` literal initialisers, `N`
  named statics in light and dark, `O` opacity, `Q` equality, `D` dynamic
  colours, `E` the environment scheme, `P` `preferredColorScheme`, `V` an
  environment write, `T` a live appearance change): 102 output lines, run
  three times byte-identical, re-run by the critic byte for byte. The two
  language probes settle the overload design: `swift-colour-overloads.swift`
  (arms `O1`…`O7`, `I1`, compiled and run) and its separating arm
  `swift-colour-isolation-negative.swift` (must fail, does).
  `swiftui-colour-hierarchical.swift` (arm `H`) found `.foregroundStyle(.secondary)`
  is a hierarchical level, not a colour (divergence 119, `CR-U`).
- **Critic round** (`CR-Q`…`CR-V`): the first frame needs two ordinary builds
  with one presented (`CR-Q`); `Color` stores `Float` and canonicalises NaN
  (`CR-R`); the theme variants live on `Frame`, not in `EnvironmentValues`
  (`CR-S`); a presentation root's preference ranks after the main root's
  (`CR-T`); two lane-2 test-design defects (`CR-V`).

## §1 What landed

- **`ColorScheme`** (`MetalUICore/ColorScheme.swift`, `CR-J`): `.light`/`.dark`;
  `Appearance` is kept as a non-deprecated typealias, `Appearance.swift`
  deleted, so every `Appearance` spelling compiles.
- **`Color` the value** (`MetalUI/Color.swift`, `CR-C`…`CR-H`): 24 bytes,
  `Hashable, Sendable`, nonisolated. Initialisers `Color(_:red:green:blue:opacity:)`,
  `Color(_:white:opacity:)`, `Color(hue:saturation:brightness:opacity:)`
  (`RGBColorSpace` is `.sRGB`/`.sRGBLinear`, no P3), `Color(_ token:)` (kept),
  `Color(_ hsla:)`, `Color(light:dark:)` (`CR-O`), `Color(_ key: K.Type)`
  (`CR-N`); `opacity(_:)` multiplies (a literal folds it into its own opacity,
  clamped once at resolution, `CR-W` 3); thirteen hue statics plus
  `black/white/clear/gray` (fixed macOS 27 values in light and dark, divergence
  117), `primary/secondary/accentColor` through the theme (divergence 116), the
  nine token statics (`Color.surface`, …, `CR-E` 2); `Color.Resolved` and
  `resolve(in:)` clamped (divergence 118). `Color: Element` is a
  `@MainActor extension` in `NativeElements.swift` (`CR-D`, `CR-W` 2): still a
  view that fills its proposal. The old `Color.color` is a deprecated
  `ColorToken?`.
- **A `Color` overload at every colour-taking site** (`CR-E`): `background`,
  `hoverBackground`, `focusBackground`, `border` (and hover/focus), `fill`,
  `stroke`, `strokeBorder`, `shadow(color:)`, `foregroundColor`/`foregroundStyle`,
  `Background`, `Rectangle`, `onTap(hoverColor:)`, `Decoration`, `BorderStyle`,
  on both vocabularies. Each `ColorToken` declaration keeps its text, becomes
  `@_disfavoredOverload` and forwards `Color(token)`; the `Color` declaration
  is the implementation. Stored colour properties are `Color`/`Color?`;
  `LayoutModifier`'s three payloads too (`CR-W` 1, a one-token migration).
- **One resolution function** (`CR-H`): `PaintPass.resolve(_ color:) -> Hsla`
  reads the element's scoped theme and scheme; animation keys on the declared
  `Color` (`animatedColor`, `animatedBackground`), a dynamic or palette colour
  never fades on a scheme switch, a token-to-literal fade re-resolves the token
  end. **No renderer change** (`CR-I`): primitives already carry resolved
  colour; `shaders.metal`, `replay.hlsl`, `MetalUIScene` and
  `MetalUIShaderTypes` are byte-unchanged.
- **App palette** (`CR-N`, `Theme.swift`): `ThemeColorKey { static var
  defaultValue: Color }` and `Theme[key]` get/set; the palette is part of
  `Theme`'s equality; the nine built-in tokens keep the exhaustive switch and
  are untouched. A key whose default refers to itself traps naming the key.
- **Colour scheme** (`CR-J`, `CR-K`, `CR-L`, `CR-M`, `CR-Q`, `CR-S`, `CR-Y`,
  `CR-Z`): `EnvironmentValues.colorScheme`, stamped by `Window`/`Frame` from
  the platform's appearance (never a `Window.environment` write, so a phase
  read cannot keep the display link awake); `Window.lightTheme`/`darkTheme`
  (active variant selects `theme`; a direct `theme` write lasts until the next
  scheme change), `App.lightTheme`/`darkTheme`/`preferredColorScheme`;
  `.preferredColorScheme(_:)` window-wide with SwiftUI's reduction, collected
  during the element walk (main tree, then presentation roots); the defaultless
  `PlatformWindow.setPreferredColorScheme(_:)` — AppKit sets `NSWindow.appearance`
  and reports once, SDL records the preference and keeps following
  `SDL_GetSystemTheme`/`SDL_EVENT_SYSTEM_THEME_CHANGED` (decorations stay with
  the system, `CR-M`), every fake records. A scheme from the tree is in the
  first presented frame: two ordinary builds, the second snapping every change.
- **Demo** (`LooksDemo.swift`, `looksColourSection()` in its own function, `CR-AA`):
  22 labelled swatches, a `@Environment(\.colorScheme)` label, a System/Light/Dark
  toggle; `LooksBrand: ThemeColorKey` with the demo's dark override; the looks
  window is 1180 × 880; `MetalUISDLDemo` gained `METALUI_LOOKS_DEMO=1`.
- **Documents**: divergences 116–119 and an amended 1; migration, api-overview
  "Colour", human checks S1–S4, inventory map rows and census (2305 rows).

## §2 Tests and guards, per file

Suite **2328 → 2376** (+48); typecheck guards **142 → 147** (+5; 141 → 146 `canTypecheck`-gated declarations); `Backends/SDL`
**24 + 62 → 24 + 63**.

| File | Tests | Pins |
|---|---|---|
| `MetalUICrossPlatformTests/ColorValueTests.swift` | 11 | initialisers, linear to gamma, HSB, every named static in both schemes (probe values), the semantic statics through the theme, opacity and clamping, equality, a token colour bit-exact to its token, dynamic colour per scheme, bare environment reads light, 24-byte size |
| `MetalUICrossPlatformTests/ColorPaletteTests.swift` | 4 | default per scheme, a per-theme override, palette in `Theme` equality, built-in tokens untouched |
| `MetalUITests/ColorPaintTests.swift` | 7 | a literal reaches every colour-taking site (arms per site, both vocabularies), a `Color` view fills and `opacity` is the value method, `PaintPass.resolve` uses the scoped theme and scheme, a scheme change fades nothing, a token-to-literal fade, a palette cycle traps naming its key (exit test), NaN settles and the link pauses |
| `MetalUITests/ColorCompileGuards.swift` | 3 guards | statics usable off the main actor (1.23), every `ColorToken` spelling compiles with the result types (1.24, `CR-E` token spellings), SwiftUI's spellings typecheck without ambiguity incl. `Text("x").foregroundColor(.red)`, `.background(.surface)` and `nil` (1.25) |
| `MetalUITests/ColorSchemeTests.swift` | 19 | the stamp, an appearance change rebuilds, a same-scheme report wakes nothing, a phase read lets the link pause, variant selection under a scope, a self-reset below a dark scope, `.theme` pins tokens not the scheme, window-wide preference, SwiftUI's reduction (arms P3…PD), layout and identity transparency, first-frame preference and its snapping rebuild (2.11, 2.11b), later change and clearing, tree over window over platform, variants and direct writes, `App` before the first frame, a palette override repaints, a scheme change repaints when both variants are equal |
| `MetalUITests/ColorSchemeCompileGuards.swift` | 2 guards | a conformer without `setPreferredColorScheme` does not compile (2.18), `Appearance` still compiles (2.19) |
| `MetalUIPlatformTests/PlatformTests.swift` | 1 | AppKit: `setPreferredColorScheme` sets `NSWindow.appearance` and reports once |
| `MetalUITests/LooksColourDemoTests.swift` | 1 | the colour section paints literal, dynamic and palette swatches, the toggle drives the window |
| `Backends/SDL/.../SDLColorSchemeTests.swift` | 1 | a preference is recorded and the system theme still reports |
| edited: `AnimationTests`, `ModifierAnimationTests`, `ShadowTests`, `CloseoutTests` (F1.3: nine `onClick` hitboxes became ten, the scheme toggle), `Fakes`, four other guard files (conformer arm) | — | existing arms re-spelled or extended |

Linux (`swift:6.4-noble`): 199 + 22 + **36** + 31 + 18 + 6 (the third group was
21; the 15 portable colour tests). 0 `error:`/`warning:`.

## §3 Probes

All four live in `docs/probes/`, outputs in their headers. SwiftUI's resolved
values (probe `N`) are the thirteen hues, black, white, gray, `primary`,
`secondary` and the system accent in light and dark; they became
`everyNamedStaticResolvesToTheProbedValueInBothSchemes`. Positive control and
separating arm are in each (`P`/`E`/`T` for the scheme: a forced preference
changes the environment value; the unforced does not). SwiftUI's `D` arms found
no dynamic-colour initialiser, so `Color(light:dark:)` is MetalUI-only by
design. Every probe ran with the screen locked; the `T` arm (a live appearance
change) was measured through a headless window, not a visible one.

## §4 Red runs

Each lane committed its tests before the source: `ff24334` (lane 1, 25 tests;
did not compile: no `Color(red:…)`), `c4ccff2` (lane 2, 2.1–2.22), `8fa0b51`
(lane 2 review: 2.11b, 2.15 and 2.17 light arms; red before `49f4bd8`),
`31eb460` (lane 3: references `LooksBrand` and `looksBrandDarkOverride`, which
Sources did not define, so the test target failed to compile).

## §5 Mutation tables

Every mutation applied by exact-string replacement, restored from a copy, full
unfiltered native suite, `git status --short` empty after each. Spellings and
the earlier reviewer's rows are in `CR-X` (lane 1, M12–M29), `CR-Y` and `CR-Z`
(lane 2, M2.1–M2.22, MK, MJ, MD), `CR-AA` (lane 3).

**Lane 1 review verdict** (2353 tests):

| Id | Mutation | Reddened |
|---|---|---|
| M23 | `canonical(_:)` returns `value` | `aNaNColourSettlesAndLetsTheDisplayLinkPause` (five per-frame arms), `opacityMultipliesAndClampsAtResolution` |
| M20 | delete `Text`'s token `foregroundColor` twin | `everyColorTokenSpellingStillCompiles` |
| M13 | `Shape.fill(_ color:)` forwards `.surface` | `aLiteralColourReachesEveryColourTakingSite` (`background(_:in:)` and `Shape.fill` arms), plus six shape tests (`theCacheKeyIncludesColourTransformAndClip`, `aStrokeDrawsOverTheFill`, `aBorderWiderThanHalfTheShapeFillsIt`, `aFillWinsOverTheForegroundStyle`, `aShapeBackgroundOrOverlayTakesTheContentsSize`, `backgroundInAShapeIsTheFilledShapeAndDefaultsToTheBackgroundToken`) |
| M26 | delete `onTap(hoverColor: ColorToken?)` twin | `everyColorTokenSpellingStillCompiles` |
| M27 | `Text.foregroundColor` non-optional | `theSwiftUISpellingsTypecheckWithoutAmbiguity` |
| M19, M19b, M21, M22, M25, M28, M29 | `Element` on `Color`'s primary declaration; `@MainActor` statics, key initialiser and `opacity`; token twins not disfavoured | build failures (the guards are the second line of defence, `CR-X` 4) |

**Lane 2 review verdict** (2375 tests): **MK** (second build without
`snapsEveryChange`) reddens `theFirstFrameRebuildStartsNoAnimationFromTheFirstBuild`;
**MJ** (delete `theme = lightTheme`) reddens `aPaletteOverrideOnTheWindowsVariantRepaints`;
**MD** (drop `colorScheme == .light` from `lightTheme`'s guard) reddens
`theWindowsThemeFollowsItsVariantsAndADirectWriteLastsUntilTheNextChange`. The
measured M2.1–M2.22 table (`CR-Y`) names reddened tests per row.

**Lane 3 verdict** (2376 tests):

| Id | Mutation | Reddened |
|---|---|---|
| M3.1 | the `light/dark` swatch as a light-only literal | `theLooksColourSectionPaintsLiteralDynamicAndPaletteColours` ("dynamic, dark" arm) |
| M3.3 | `.preferredColorScheme(choice)` removed from the section | same test, lines 103–105, 117 |
| M3.5 | the toggle's Dark case goes to Light, never back to System | same test, lines 116–117 |
| M3.6 | the palette swatch bypasses the theme (`LooksBrand.defaultValue`) | same test, lines 97, 111 |
| **M3.4** | `LooksSchemeLabel` shows the constant `scheme: light` | **none — green** (§6) |

## §6 Green mutations and pins that prove less than they look

- **M3.4: the demo's `scheme:` label is unpinned** (`CR-AB`). Nothing reads
  the label's glyphs; the behaviour underneath (a view reading
  `@Environment(\.colorScheme)` while building, following an appearance change
  and a preference) is pinned by lane 2's `ColorSchemeTests`. The label is
  covered by human checks S2 and S3 only, on purpose: asserting text in a
  scene needs a text-run reader no demo test has.
- **M2.20b**: AppKit's explicit report after the `NSWindow.appearance` write
  is insurance — headless AppKit calls `viewDidChangeEffectiveAppearance`
  synchronously (`CR-Y` 5).
- **`CR-Q`'s "skip adoption of the first build"** mutation has no spelling (the
  window has no store snapshot); the 2.11 arm guards only against duplicated
  entries.
- **NaN and the display link** (`CR-X` 1): the link pauses with or without
  the canonicalisation after one transactionless build; M23 reddens through the
  per-frame arms under `withAnimation`, and the final pause arm stays green.
- **Guard 1.23** has no single mutation of its own: every member it touches is
  also used nonisolated in the package or the cross-platform tests (`CR-X` 4).
- A predecessor's uncommitted `Color(white:)` mutation was found unreverted and
  reverted by the lane 1 reviewer; its results are not claimed.

## §7 Demo comparison and looks

`docs/probes/demo-pixels/compare.sh <scratch> 30a3dbf HEAD`: the controls at
`30a3dbf` print their expected non-zero and zero values and **all fourteen
images read differing = 0, scene identical** (no production tree uses a new
API; the looks demo's colour section is in an image only under
`METALUI_LOOKS_DEMO`, and the looks image's window size change is the demo
window's, not a rendered fixture). `DemoFrameDeterminismTests`' `Expected.swift`
is unedited. Real-window capture: lock probe read locked, none taken.

**Owed, group S, none performed (an agent cannot)**: S1 the swatches against a
SwiftUI reference side by side, light and dark (slightly more saturated, `primary`/
`secondary`/`accentColor` differ by design); S2 live appearance switching, no
fade; S3 the System/Light/Dark toggle forces the whole window including the
title bar, no flash; S4 SDL follows the system theme, decorations stay.

## §8 Hazards

- A **new colour-taking site** takes a `Color` implementation and a
  `@_disfavoredOverload` token twin; without the disfavouring `.background(.surface)`
  is ambiguous (M21, M22, M25 break the build).
- **`Element` must stay on `Color`'s `@MainActor` extension**, never its primary
  declaration: otherwise every static and initialiser becomes main-actor
  isolated and the portable tests stop compiling (M19, M19b).
- **`.opacity(_:)` on a `Color` is the value method**; an opacity layer needs a
  non-`Color` view. A stored `Color` keeps written values (including NaN
  canonicalised to 0); only resolution clamps.
- **The scheme is never a `Window.environment` write**: that write always
  dirties (M2.4 reddened 59 tests).
- **`Deferred.swift` and `AnchoredPresentation.swift` changed** (`CR-Z` 3):
  only `begin`/`endPresentationPreferences` bookkeeping around the content build;
  layout, identity and pixels unchanged.
- A palette key whose default reads itself traps naming the key; a key whose
  default differs between the two variants must be a `Color(light:dark:)`.
- A first spelling of a test arm that assigns a theme equal to the current one
  stays green under its mutation (MD): assign a third, `#require`d distinct.
- Swift 6.4 infers `extension Color: Element`'s members nonisolated; the
  explicit `@MainActor` on the extension is load-bearing.

## §9 The Record phase's own close (2026-10-03)

`swift package clean`, `swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel` unfiltered at the Record
phase's HEAD: **`Test run with 2376 tests in 3 suites passed after 125.643 seconds`**, the `FR-J no-argument frame: succeeded=true` line present, 0 `error:`, the only `warning:` SwiftPM's native deprecation notice; 146 `canTypecheck`-gated declarations (`grep -rh "enabled(if: canTypecheck" Tests | wc -l`), 0 goldens. Inventory check and
undocumented check print nothing; the census is the committed one (2305 rows).
Documents changed at this phase: `CLAUDE.md`/`AGENTS.md` (the `CR-` prefix,
the paragraph, the counts, "groups A–S", "86 live, next label 120"),
`docs/record/README.md`, record §03, `README.md`, the spec's Status, the
decisions doc (`CR-AB`).

## §10 Deferrals, with owners

| Item | Reason | Owner |
|---|---|---|
| `ShapeStyle`, gradients, materials, hierarchical `.secondary`, `.tint`/`.accentColor` | a second style type and its own probe surface (divergence 119) | none (a later gpui-gap item) |
| `Color.RGBColorSpace.displayP3`, asset-catalog `Color("Name")`, `Color(nsColor:)`, `Color.Resolved` initialisers | colour-managed pipeline (divergence 1); no catalog compiler off Apple | none |
| `colorSchemeContrast`, Increase Contrast, the user's accent | no portable source | none |
| `preferredColorScheme` per presentation | popovers are in-window (`MN-M`) | none |
| SDL native decorations following a preference | SDL3 has no API (`CR-M`) | none |
| the demo's `scheme:` label pinned by a test | needs a text-run reader (§6) | none |
| groups S1–S4 | an agent cannot look | the user |
