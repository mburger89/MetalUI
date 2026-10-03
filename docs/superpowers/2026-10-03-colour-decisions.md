# Colour and colour scheme — decisions

Rulings for colour values, colour scheme and an app palette in the theme
(user request 2026-10-02, an item of the gpui-gap priority list; **not a plan
task**). Spec:
[`specs/2026-10-03-colour-design.md`](specs/2026-10-03-colour-design.md).
Record: `../record/75-colour.md` (written at the Record phase; renumbered
there if another line publishes §75 first). Evidence:
[`../probes/swiftui-colour.swift`](../probes/swiftui-colour.swift) (**new**;
arm ids `R…` literal initialisers, `N…` named statics, `O…` opacity, `Q…`
equality, `D…` dynamic colours, `E…` the environment's scheme, `P…`
`preferredColorScheme`, `V…` an environment write, `T…` a live appearance
change; its header carries the recorded output, run three times
byte-identical, and the reading), and the language probes
[`../probes/swift-colour-overloads.swift`](../probes/swift-colour-overloads.swift)
(arms `O1`…`O7`, `I1`; compiled and run) with its separating arm
[`../probes/swift-colour-isolation-negative.swift`](../probes/swift-colour-isolation-negative.swift)
(must fail). Where SwiftUI has no answer (an app palette, a theme), the
ruling says so and names gpui's approach as the comparison, not as evidence.

Prefix **`CR-`**, lettered. **Next unused: `CR-Q`.** (This line moves in the
commit that appends a ruling; read the last `## CR-` heading.)

Branch `feat/colour` from `30a3dbf` (master: menus, popovers and tooltips
merged, PR #44). Baseline at `30a3dbf`: see spec §0. `docs/divergences.md`
line 12: **next label 116** (CLAUDE.md's "next label 104" is stale; the file
is the authority).

**Carried items.** Design spec §7.9 (binding): "Colors in element code are
**semantic tokens** … never literals" — `ColorToken`'s own doc repeats it as
the reason `background(_:)` takes a token. `CR-B` supersedes that sentence.
Divergence 1 (sRGB authored on a Display P3 layer) — `CR-I` extends it to
literals. `EV-G` (the theme is readable only in `PaintPass`, `.theme(_:)` its
only writer) — kept by `CR-H`/`CR-K`. `EV-AB`/`AN-AD` (a platform value
stamped over the root environment, guarded) — the pattern `CR-J` copies.
`AN-` colour rulings (`animatedColor`/`animatedBackground`, RGB interpolation,
a theme swap never starts a fade) — kept by `CR-H`. `TE-AD` (a new drawable
capability lands in both shaders) — not triggered (`CR-I`). No decisions
doc's "Carried…" section names a literal colour, a colour scheme or a palette.

---

## CR-A — Scope: what this branch builds, what it defers

**Ruling.** Build, SwiftUI-spelled and probe-backed:

1. A `Color` **value** (`CR-C`): `Color(red:green:blue:opacity:)`,
   `Color(_:red:green:blue:opacity:)` over `Color.RGBColorSpace`
   (`.sRGB`, `.sRGBLinear`), `Color(white:opacity:)`,
   `Color(_:white:opacity:)`, `Color(hue:saturation:brightness:opacity:)`,
   SwiftUI's nineteen named statics (`CR-F`), `opacity(_:)` (`CR-G`),
   `Color.Resolved` and `resolve(in:)` (`CR-H`); MetalUI-only
   `Color(_ token:)` (kept), `Color(_ hsla:)`, `Color(light:dark:)` (`CR-O`),
   `Color(_ key:)` over a `ThemeColorKey` (`CR-N`) and nine token-named
   statics (`CR-E`). It stays a view that fills its proposal.
2. `Color` accepted **everywhere a `ColorToken` is** on both vocabularies,
   every `ColorToken` spelling still compiling (`CR-E`), animating exactly as
   tokens do (`CR-H`), drawing identically on Metal and SDL with no shader
   change (`CR-I`).
3. `ColorScheme` and `@Environment(\.colorScheme)` readable while building
   (`CR-J`), the window's light/dark theme variants (`CR-K`),
   `.preferredColorScheme(_:)` window-wide with SwiftUI's reduction rule
   (`CR-L`), one new defaultless `PlatformWindow` requirement (`CR-M`).
4. An app palette in the theme: `ThemeColorKey`, `Theme` subscript, app-wide
   theme variants (`CR-N`).
5. A looks-demo section and human-checks group S.

**Deferred, each named in spec §10 with a reason and owner (none unless
named)**: a `ShapeStyle` protocol, gradients, materials and hierarchical
styles (`.foregroundStyle(.secondary)` resolves the `Color.secondary` value,
not SwiftUI's hierarchical level); `.tint(_:)`/`.accentColor(_:)`;
`Color.RGBColorSpace.displayP3` (divergence 1's owner: none — needs a
colour-managed pipeline); asset-catalog `Color("Name", bundle:)`;
`Color(nsColor:)`/`Color(cgColor:)` interop; `Color.Resolved`'s initialiser,
`linearRed`… accessors and `Color(_ resolved:)`; `colorSchemeContrast` and
Increase Contrast variants; reading the user's system accent colour;
`preferredColorScheme` scoped to a presentation (MetalUI's popovers are
in-window, `MN-M`); a `Text` glyph colour fade (unchanged: glyph tint does not
animate today); SDL native decorations following a preference (`CR-M`).

**Reasoning.** The request is a port of a real ~8,500-line app whose whole look
is RGB colours chosen per scheme; the five items are the minimum that lets it
be written without a hand-written paint pass. Everything deferred is either a
second feature with its own probe surface (`ShapeStyle`, gradients, tint) or
needs a pipeline MetalUI does not have (P3).

**Cost if wrong.** A deferred item a port needs first is a later item, not a
redesign: every deferral is additive over the `Color` value.

## CR-B — Literal colours are admitted; design spec §7.9's ban is superseded

**Ruling.** Element code may write a literal colour. Design spec §7.9's
"semantic tokens … never literals" and `ColorToken`'s doc that repeats it are
superseded by this ruling (the Record phase amends both texts with a pointer
here). `ColorToken` stays, unchanged, as the theme's built-in vocabulary.

**Reasoning.** SwiftUI is the design authority and its whole colour surface is
literals plus dynamic system colours (probe `N`: every hue static is dynamic).
§7.9's risk — "a literal would paint the same pixels in both appearances,
invisibly" — is answered by two mechanisms that make following the scheme
the easy spelling: dynamic colours (`CR-O`, and every named hue is one,
`CR-F`) and palette keys (`CR-N`). A ban leaves the port's ~hundreds of RGB
call sites with no spelling at all.

**Cost if wrong.** An app can paint a fixed colour that ignores dark mode —
exactly SwiftUI's exposure; the demo and migration guide steer to
`Color(light:dark:)` and palette keys.

## CR-C — The `Color` value: initialisers, storage, equality

**Ruling.**

1. `Color(red:green:blue:opacity:)` and `Color(.sRGB, …)` author
   **gamma-encoded sRGB** (probe `R0`, `R1`: white 0.5 resolves 0.5, not
   0.214; `R2`). `Color(.sRGBLinear, …)` converts to gamma at once with the
   sRGB transfer function (`R3`: 0.2 → 0.4845). `Color(white:opacity:)` is
   `(w, w, w)`; `Color(_:white:opacity:)` the same through the colour space.
   `Color(hue:saturation:brightness:opacity:)` converts HSB to sRGB at once
   (`R6`). `opacity` defaults to 1 everywhere, as in SwiftUI.
2. **Stored as written, clamped when resolved.** Components and opacity are
   stored unclamped (SwiftUI keeps `1.2`/`-0.1`/`1.5` in its resolved value,
   `R5`, `O4`, `O5`); resolution clamps each to `0…1`, NaN to 0. SwiftUI's
   `Color.Resolved` keeps the extended values and clamps only at draw — the
   one observable difference is `Color.Resolved`'s fields (**divergence 118**,
   `CR-H`). Nothing non-finite reaches a primitive.
3. **Storage** is one internal enum plus an opacity multiplier:
   `srgb(r, g, b, a)` (Doubles, as written), `token(ColorToken)`,
   `indirect dynamic(light: Color, dark: Color)`,
   `indirect palette(ObjectIdentifier, defaultValue: Color)`.
   `Color` is `Hashable` and `Sendable`. **Equality compares components**:
   `Color(white: 1) == .white` and `Color(red: 1, green: 1, blue: 1) ==
   Color(white: 1)` (probe `Q4`, `Q5`) — `.white`/`.black`/`.clear` and
   `Color(white:)` all store `srgb`. A dynamic colour equals only a dynamic
   colour with equal halves (MetalUI's rule; SwiftUI's answer for a system
   colour against its literal value was not probed and is not claimed).
4. `Color(_ hsla: Hsla)` (MetalUI-only): the `Hsla` converted to `srgb` —
   the bridge from MetalUI's existing colour currency and `Hsla.rgb(0x…)` hex.
5. `Color(_ token:)` keeps its spelling and meaning (token-backed: follows the
   active theme). The old stored `public var color: ColorToken` becomes a
   deprecated get-only `ColorToken?` (the token, or `nil` for any other
   colour); no source in the repository reads it (grep at `30a3dbf`).
6. `.displayP3` is **not** a case (`CR-A`): SwiftUI converts P3 to extended
   sRGB (`R4`), and MetalUI would then clamp and draw those numbers into a P3
   layer (divergence 1) — wrong twice. A SwiftUI source line naming it fails
   to compile rather than drawing the wrong colour.

**Cost if wrong.** Clamping at resolution instead of draw differs only for an
app that reads `Color.Resolved` of an out-of-gamut colour; additive to fix.

## CR-D — `Color`'s `Element` conformance moves to an extension

**Ruling.** `public struct Color: Hashable, Sendable` on its primary
declaration; `extension Color: Element` separately.

**Reasoning.** `Element` is `@MainActor`. A conformance on the primary
declaration infers `@MainActor` for the whole type, so `Color.red` cannot be
a nonisolated default argument or a `ThemeColorKey`'s nonisolated
`static let defaultValue` (probe `swift-colour-isolation-negative.swift`:
"main actor-isolated default value in a nonisolated context"); in an extension
only the conformance's members are isolated (probe `swift-colour-overloads.swift`
`I1`: clean). SwiftUI's `Color` is likewise usable off the main actor.

**Cost if wrong.** None observable at a call site; a `swift package clean` is
owed (a public type's isolation crosses a module boundary).

## CR-E — `Color` is accepted everywhere a `ColorToken` is; every token spelling still compiles

**Ruling.**

1. Every public API that takes a `ColorToken` today gains a **`Color`
   overload**, which becomes the implementation. The existing `ColorToken`
   declaration is kept textually, marked **`@_disfavoredOverload`**, and
   forwards `Color(token)`. Deprecated spellings (`nativeBackground`,
   `nativeBorder`, `Rectangle(color:)`, `NativeTappable.nativeOnTap`) get no
   `Color` twin.
2. `Color` gains **nine token-named statics** (`background`, `surface`,
   `surfaceSecondary`, `accent`, `separator`, `textPrimary`,
   `scrollIndicator`, `scrim`, `shadow`), each `Color(.token)`. So
   `.background(.surface)` is viable on both overloads and resolves to the
   `Color` one (probe `O1`); a `ColorToken`-typed value takes the twin (`O2`);
   `.red` exists only on `Color` (`O3`); a defaulted `color:` on both
   (`shadow(radius:)`) resolves to `Color` (`O4`); an optional `Color?`
   parameter is reached through implicit-member lookup (`O5`); a static
   `shadow`/`background` coexists with the instance modifiers (`O7`).
3. **Stored public colour properties are retyped to `Color`/`Color?`**:
   `Decoration.background`/`hoverBackground`/`focusBackground`,
   `BorderStyle.color`, `Background.color`, `Rectangle.color`,
   `Text`/`ProposalText`/`TextField`/`TextEditor.foregroundColor`,
   `NativeTappable.hoverColor`. A writer (`x.background = .surface`) and a
   comparison (`== .accent`) compile unchanged through the statics; a reader
   that used the value *as a `ColorToken`* (a `switch`, `theme[…]`) breaks —
   migration: `pass.resolve(x)` or compare against `Color(.token)`.
4. SwiftUI's signatures where they differ in optionality:
   `foregroundColor(_ color: Color?)` takes an optional (`nil` = inherit), as
   SwiftUI's does.

**Reasoning.** One concrete type at every site is SwiftUI's shape for
`foregroundColor`/`shadow(color:)`; SwiftUI's `some ShapeStyle` for
`background`/`fill`/`border` is deferred (`CR-A`) because MetalUI has no
second style to justify the protocol. The disfavored twin keeps a token
variable compiling without making `.surface` ambiguous, and `@_disfavoredOverload`
is already used in `Grid.swift`. Keeping the twin textually unchanged keeps
its census row.

**Cost if wrong.** Roughly forty twin declarations to maintain; a future
`ShapeStyle` replaces both with one generic signature, additively.

## CR-F — Named statics: which are fixed, which dynamic, which follow the theme

**Ruling.**

| Static | MetalUI value | Probe |
|---|---|---|
| `black`, `white`, `clear` | fixed sRGB `000000`, `FFFFFF`, `000000` @ 0 | `N` |
| `gray`, `red`, `orange`, `yellow`, `green`, `mint`, `teal`, `cyan`, `blue`, `indigo`, `purple`, `pink`, `brown` | `Color(light:dark:)` of the probed macOS 27 values (spec §3.2 table) | `N` |
| `primary` | `Color(.textPrimary)` | `N` (SwiftUI: label colour, black/white @ 0.8471) |
| `secondary` | `Color(light: Color(.textPrimary).opacity(0.588), dark: Color(.textPrimary).opacity(0.648))` — SwiftUI's secondary/primary alpha ratio per scheme (0.4980/0.8471, 0.5490/0.8471) | `N` |
| `accentColor` | `Color(.accent)` | `N` (SwiftUI: the system accent, here `.blue`) |

**Divergences**: **116** — `primary`, `secondary`, `accentColor` resolve
through MetalUI's theme, not the system's label and accent colours (a theme
is MetalUI's whole colour model; a system label colour on a MetalUI
`.surface` would be another app's palette); **117** — the thirteen hue statics
are the macOS 27 values frozen, on every platform: no Increase Contrast
variant, no tracking of a later OS's palette.

**Cost if wrong.** A reference window side by side differs by these choices
(human check S1); each is a table edit.

## CR-G — `Color.opacity(_:)` multiplies; on a `Color` view it is the value method

**Ruling.** `opacity(_ opacity: Double) -> Color` multiplies the stored
opacity (`O2`, `O3`: twice multiplies), clamped at resolution. Written on a
`Color` used as a view with a literal, `.opacity(0.5)` resolves to this
method — the concrete type's member beats `ProposalBase.opacity(_: Float)`
(probe `O6`), SwiftUI's own `Color.opacity` shape — so it is one fill at half
alpha with **no opacity layer**: one fewer `ModifiedContent` layer than
today's spelling would have built. A `Float`-typed argument still reaches the
view modifier. No source at `30a3dbf` writes `Color(…).opacity(` (grep);
the migration guide states the change.

**Cost if wrong.** A `Color` view relying on an opacity *layer* (a
transition or identity level under it) changes identity depth; a `Color` has
no state, so only a sibling's structural slot could notice — none does.

## CR-H — One resolution function; animation keys on the declared `Color`

**Ruling.**

1. **One internal function** resolves a `Color` against a context of
   `(theme, colorScheme)`: `srgb` clamps; `token` returns `theme[token]`
   **bit-exactly** (the existing `Hsla`, no round trip — so every existing
   token draws 0 differing pixels); `dynamic` picks by the context's scheme;
   `palette` resolves the theme's override or the key's default (`CR-N`);
   opacity multiplies the result's alpha when it is not 1. Every paint site
   that read `theme[token]` for a caller-supplied colour calls it, through
   `PaintPass.resolve(_:) -> Hsla` (public, MetalUI-only) or the internal
   frame equivalent.
2. The context's scheme is the **environment's `colorScheme`** at the element,
   and its theme the environment's theme (`EV-G`), both scoped.
3. **Animation**: `AnimatedColorState.token` and `ColorAnimation.toToken`
   become the declared `Color`, `ColorEnd.token` carries a `Color`. A theme
   swap **or a scheme change** moves what an unchanged `Color` resolves to
   without moving the `Color`, so it re-resolves and never starts a fade —
   the existing `aThemeSwapAloneNeverStartsAFadeOnASettledElement` argument,
   extended. RGB interpolation, clamping in flight, the interruption rule and
   `noteActiveAnimation()` are unchanged. `MemoryLayout<AnimatedColorState>.stride`
   (120 at `30a3dbf`) is re-measured and recorded.
4. `Color.resolve(in: EnvironmentValues) -> Color.Resolved` (SwiftUI's,
   macOS 14) is public: `red`, `green`, `blue`, `opacity` as `Float`,
   gamma-encoded sRGB (probe `R1`), clamped (divergence 118). **The `Theme`
   value stays paint-only** (`EV-G`; `readingTheThemeDuringLayoutDoesNotCompile`
   and its two siblings unchanged): a colour resolves wherever an environment
   is in hand, as in SwiftUI; the theme itself does not leak.

**Cost if wrong.** If keying animation on `Color` misses a case, a scheme
switch fades instead of snapping — pinned by
`aSchemeChangeNeverStartsAFadeOnADynamicColour`.

## CR-I — No renderer change; divergence 1 covers literals

**Ruling.** Every primitive already carries a resolved colour (`MUIRect`
background/border, `MUIGlyph` colour, a path's or shadow's raster tint);
`Color` resolves to the same `Hsla` before emission. **No change to
`shaders.metal` or `replay.hlsl`**; `TE-AD` is not triggered; the branch
check verifies `git diff 30a3dbf -- Sources/MetalUIRender/Shaders
Backends/SDL/Shaders` is empty. A literal is interpreted exactly as a token
is: sRGB numbers written to a layer whose colour space is Display P3 on
AppKit (divergence 1, amended to say literals share it) and to an sRGB
swapchain on SDL.

## CR-J — `ColorScheme`, the environment's `colorScheme`, and the window's stamp

**Ruling.**

1. `MetalUICore`'s `Appearance` enum is **renamed `ColorScheme`** (SwiftUI's
   name; `.light`, `.dark`, `CaseIterable` in that order, probe `Q6`), and
   `public typealias Appearance = ColorScheme` stays, **not deprecated**, so
   every platform conformer, `Theme.forAppearance(_:)` and test fake compiles
   unchanged.
2. `EnvironmentValues.colorScheme` is public get/set, `.light` in a bare value
   (probe `E0`); readable while building (`@Environment(\.colorScheme)`), in
   every phase, and writable by a scope (probe `V1`).
3. `Window` stamps the root's `colorScheme` from its **effective scheme**
   (`CR-L`) at every draw, over `Window.environment`, beside
   `controlActiveState` and `accessibilityReduceMotion` (`EV-AB`'s pattern),
   and exposes it as `public private(set) var colorScheme`. **Guarded**: a
   report of the scheme the window already has does not repaint. An
   appearance change re-renders the whole tree (immediate mode; probe `T1`:
   SwiftUI re-runs the body too).
4. Reading it never writes: a read in any phase leaves the display link free
   to pause.

## CR-K — The window's theme variants; a scheme write selects one

**Ruling.**

1. `Window.lightTheme` and `Window.darkTheme` (public, default `.light`,
   `.dark`) are the variants. Whenever the effective scheme or either variant
   changes, `Window.theme` is set to the scheme's variant. `Window.theme`
   **keeps its meaning**: the active root theme, writable, replaced on the
   next scheme change — exactly today's behaviour, where an appearance change
   replaced it with `Theme.forAppearance`. Defaults reproduce today's theme
   in both schemes, so 0 pixels move.
2. The variants reach the root environment (internal fields, stamped by the
   frame like `theme`, re-stamped after every transform). A scope that
   **changes `colorScheme`** (`.environment(\.colorScheme, .dark)`, or a
   `\.self` reset to a bare value) sets its subtree's theme to that scheme's
   variant — SwiftUI's subtree flips with the write (`V1`), so MetalUI's
   tokens flip too.
3. `.theme(_:)` still pins the subtree's tokens to one theme and does **not**
   change `colorScheme`; dynamic and palette colours inside it follow the
   environment's scheme (`CR-H` item 2). To darken a subtree completely, write
   the scheme.

**gpui comparison** (SwiftUI has no theme): zed's theme family carries a light
and a dark appearance chosen by the window's appearance — the same pair.

## CR-L — `.preferredColorScheme(_:)`: window-wide, SwiftUI's reduction, precedence

**Ruling.**

1. `.preferredColorScheme(_ colorScheme: ColorScheme?)` on `ElementGroup`
   (both vocabularies), returning an `EnvironmentScope` — layout- and
   identity-transparent, values unchanged; it **reports** a preference.
2. **Window-wide** (probe `P1`: the sibling reads it and the `NSWindow`'s
   appearance is set), not a scope write (`V1` is the separating arm).
3. **Reduction** (probes `P3`…`P7`): an outer modifier **replaces** its
   content's value, `nil` included (`P5`, `P6`); among siblings the **first
   non-nil** wins (`P3`, `P4`, `P7`). Implemented as: only a scope with no
   enclosing preference scope counts, and the first such scope with a non-nil
   value, in layout order, decides. A `List` row out of window is not laid out
   and does not count; a `Deferred` presentation root counts in the frame's
   layout order (presentations before the root — stated, unprobed: SwiftUI's
   popover is its own window).
4. **Precedence**: the tree's preference, else `Window.preferredColorScheme`
   (public, MetalUI-only, programmatic), else the platform's appearance.
   `App.preferredColorScheme` (MetalUI-only) assigns every open window's and
   each later window's before its first frame. Clearing the preference
   returns to the platform's appearance (`P8b`).
5. **When it applies.** On a window's **first** frame a preference that
   differs from the scheme it was built with discards that build and rebuilds
   once before presenting (no light flash at launch; nothing was evaluated
   "last frame", so transitions and state are unaffected). After the first
   frame a changed preference applies on the **next** frame (the frame is
   marked dirty; one frame drawn in the old scheme). SwiftUI's own body ran
   light then dark (`P1` reads); whether it presented the light pass is
   unmeasured and not claimed.

**Cost if wrong.** If the first-frame rebuild proves unsafe, the fallback is
next-frame everywhere — a one-frame flash at launch for a root preference;
`App.preferredColorScheme` never flashes.

## CR-M — `PlatformWindow.setPreferredColorScheme(_:)`, defaultless

**Ruling.** `func setPreferredColorScheme(_ colorScheme: ColorScheme?)` on
`PlatformWindow`, **no default** (`EV-AB`'s reason), called by `Window`
whenever the requested preference (tree ?? window) changes, and only then.

- **AppKit**: `NSWindow.appearance` = `NSAppearance(named: .aqua/.darkAqua)`,
  or `nil` to follow the application (`P8b`), so the title bar, native menus
  and context menus match (probe `P1`'s `window.appearance`). The change
  reaches `Window` through the existing `viewDidChangeEffectiveAppearance` →
  `onAppearanceChange` path, which then reports the forced appearance — the
  effective scheme agrees either way.
- **SDL**: SDL3 has no per-window appearance. The window records the value
  (internal, for tests) and keeps reporting `SDL_GetSystemTheme`
  (`mui_system_theme`); `SDL_EVENT_SYSTEM_THEME_CHANGED` already reaches
  `onAppearanceChange`. Content follows the preference; native decorations
  follow the system — a documented platform constraint, not a SwiftUI
  divergence (SwiftUI has no Linux/Windows answer).
- **Fakes** (`FakePlatformWindow` and every compile-guard conformer) record
  the calls. **Migration note**: a third-party conformer adds the method.

## CR-N — An app palette in the theme: `ThemeColorKey`

**Ruling.**

1. `public protocol ThemeColorKey { static var defaultValue: Color { get } }`
   — `EnvironmentKey`'s shape. The default is usually `Color(light:dark:)`.
2. `Color(_ key: K.Type)` (MetalUI-only) is a palette colour; apps spell
   `extension Color { static let brand = Color(Brand.self) }`.
3. `Theme` gains `subscript<K: ThemeColorKey>(key: K.Type) -> Color { get set }`:
   the override if set, else `K.defaultValue`. Overrides are stored in the
   `Theme` (an internal `[ObjectIdentifier: Color]`), so they are part of its
   `==`/hash — a palette change through `Window.theme` repaints by the
   existing guard. Overrides are **per theme value**, hence per variant:
   `window.darkTheme[Brand.self] = …` or `app.darkTheme[Brand.self] = …`.
4. `App.lightTheme`/`App.darkTheme` (MetalUI-only) assign every open window's
   variants and each later window's before its first frame.
5. Resolution of a palette colour that reaches itself again traps naming the
   key (`"ThemeColorKey cycle through Brand"`), at a depth of 16.
6. **The built-in tokens are untouched**: `Theme`'s nine stored properties,
   its exhaustive `switch`, `everyTokenDiffersBetweenLightAndDark` and
   `noTwoTokensCollideWithinAVariant` mean exactly what they meant; a palette
   key is not a `ColorToken`.

**Reasoning.** The user chose palette-in-theme over app-side constants.
SwiftUI's answer is an asset catalog's named colour (`Color("Brand")`, string
keyed, light/dark appearances in the catalog — probe header `D` note); a typed
key gives the same "one name, two appearances" without a catalog or a string,
and an override per theme gives the "re-skin" a catalog cannot. gpui
comparison: zed's `ThemeColors` is a fixed struct of named fields per theme —
closed, where this is open.

**Cost if wrong.** An app that wants a third scheme or contrast variant has
none (`CR-A` deferred); additive.

## CR-O — `Color(light:dark:)`, a dynamic colour

**Ruling.** `Color(light: Color, dark: Color)` (MetalUI-only — SwiftUI has no
such initialiser: `xcrun swiftc -typecheck` of `Color(light: .red, dark:
.blue)` on the macOS 27 SDK reports "extra argument 'dark' in call"; SwiftUI
expresses it only through `NSColor(name:dynamicProvider:)`, probe `D1`). It
resolves by the environment's scheme (`CR-H`); halves may themselves be
dynamic, token-backed or palette colours; `opacity(_:)` on a dynamic colour
applies after the half is chosen (`D2`).

## CR-P — Lanes, ownership and verification

**Ruling.** Three lanes, run one at a time in the worktree, on disjoint
files (spec §8): **L1** the colour value, palette and every colour-taking API;
**L2** the colour scheme, theme variants, `preferredColorScheme`, the
platform requirement on AppKit, SDL and every fake, `App`'s variants;
**L3** the looks demo, human-checks group S, divergences 116–118 and
amendment of 1, migration and API overview, the inventory map and census,
the Linux container and SDL verification. The decisions doc and spec are
append-only and shared (sequential lanes). **L1 and L2 leave
`closeout-undocumented.sh` empty at their commits; the inventory map and
census are L3's** (one file each — a shared file would break disjointness),
and `closeout-inventory-check.sh` is required empty at L3's commit and the
branch check.
