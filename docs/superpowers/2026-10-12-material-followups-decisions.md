# Material follow-ups — decisions

Rulings for item C27: a public read of a material's tint, and Reduce Transparency
(user request 2026-10-02, an item of the gpui-gap priority list; **not a plan task**).
Requested by MetalCreator (gaps **C21-a**, **C21-b**; read, never edited). Builds on C21
(record §94, `BB-A`…`BB-T`; divergence 166 amended, 245–249).
Spec: [`specs/2026-10-12-material-followups-design.md`](specs/2026-10-12-material-followups-design.md).
Record: `../record/101-material-followups.md` (written at the Record phase).

Evidence: [`../probes/swiftui-material-followups.swift`](../probes/swiftui-material-followups.swift)
(arms `A0`…`A10`, `O`, `T0`, `T1`; macOS 27.0.1, Swift 6.4, screen unlocked; output in its
header). SwiftUI's answer is the authority; gpui is not read (SwiftUI answers the API question,
and the platform seam is the reduce-motion pattern).

Prefix **`MT-`**, lettered. **Next unused: `MT-J`.** (This line moves in the commit that
appends a ruling; read the last `## MT-` heading.)

Branch `feat/material-followups` from `930db4a`. `docs/divergences.md`: this branch's reserved
labels are **315–324**; `MT-F` uses 315; the header's next-label line is the merge's.
Human checks: group **MT** (provisional).

## MT-A — What SwiftUI answers (probe, positive control and separating arm per claim)

**Ruling.** Measured: SwiftUI's `Material` has **no public tint read** (`A3` `.color`, `A4`
`.fill(for:)` do not exist), **takes no colour** (`A2` `.tint(.red)` resolves to the static
`ShapeStyle.tint` and fails; `A5` no initialiser), and its `resolve(in:)` returns `Never`
(`A7`; `A6` compiling is that artefact, not a read). It **does** take `.opacity(_:)` as a
`ShapeStyle` (`A1`), which halves the tint's weight over the backdrop (`O`: regular over
black 150 to 77). `\.accessibilityReduceTransparency` exists and is **read-only** (`A8`
compiles, `A9` fails on `WritableKeyPath`); `.materialActiveAppearance` exists (`A10`; not
built, not asked). **Reduce Transparency's effect on a material is not measurable**: the
swizzled `NSWorkspace` getter reads true while SwiftUI's own environment still reads false
(`T0`), and the pixels do not move (`T1`).

**Reasoning.** Two probes in a row (`BB-I`'s `T`, now `T0`/`T1`) have failed to move SwiftUI
without touching the user's system settings, which an agent does not do.

**Cost if wrong.** The fallback colour (`MT-F`) is a ruling, not a copy; `MT-1` is the
human comparison.

## MT-B — The tint read: `Material.tint(in:) -> Color`, MetalUI-only (class `M`)

**Ruling.** `public func tint(in scheme: ColorScheme) -> Color` on `Material`: the table's
`fill(for:)` (a grey at an alpha), returned as a `Color`. The opacity an app needs is
`material.tint(in: scheme).resolve(in: env).opacity` (`Color.resolve(in:)`, `CR-H`), so there is
**no second declaration**. The name is an instance method with a label, so it cannot be
confused with SwiftUI's static `ShapeStyle.tint` (`A2`). The glass identity
`(1 − t)(1 − m) = 1 − g` is then solvable: the panel colour's opacity is `t = 1 − (1 − g)/(1 − m)`
(`g ≥ m`; below `m` the material alone already hides more than the role asks and `t = 0`).
Inventory class `M` (SwiftUI has none), row in `closeout-inventory-map.tsv`, doc comment.
`fill(for:)` stays internal and now also feeds `MT-F`. `Material.swift`'s stale class comment
("with no backdrop blur") is rewritten to `BB-A`'s truth (blur plus tint; the flat tint alone
where 248 says).

**Reasoning.** The smallest public surface that answers the request; it commits MetalUI to the
fitted table's values as API (a retune moves the number, not the signature).

**Cost if wrong.** A later SwiftUI tint read would be a second spelling; this one stays as an `M`
row.

## MT-C — A material that takes a colour or an opacity is not built

**Ruling.** `Material.tint(_ color:)` and a material initialiser are **refused**: SwiftUI has
neither (`A2`, `A5`) and the read in `MT-B` solves the stated need. `Material.opacity(_:)`
(a `ShapeStyle` in SwiftUI, `A1`/`O`) is **deferred**: MetalUI's materials are not
`ShapeStyle`s, and the element `.opacity` already fades a backdrop record without blur change
(`BB-G`). Owner: none scheduled; take it with a general `ShapeStyle` pass.

**Cost if wrong.** An app spells a faded material through `.opacity` on the element.

## MT-D — Reduce Transparency: SwiftUI's key, the reduce-motion pattern exactly

**Ruling.** `EnvironmentValues.accessibilityReduceTransparency: Bool`,
`public internal(set)`, `false` in a bare value and in `renderFrame`. `PlatformWindow` gains two
**defaultless** requirements, `accessibilityReduceTransparency: Bool { get }` and
`onAccessibilityReduceTransparencyChange: ((Bool) -> Void)? { get set }`. `Window` reads it at
construction, updates it through the callback with a **guarded `didSet`** (a repeat does not
repaint), and stamps it over `environment` beside `accessibilityReduceMotion`
(`rootEnvironment.accessibilityReduceTransparency = …`) — never a `Window.environment` write
(that dirties every draw). Conformers: AppKit reads
`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` live and re-reads on
`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, firing on a change only (the
existing observer in `AppKitPlatform` serves both values); every test fake gets the pair;
`docs/migration.md` gains the note beside the reduce-motion row.

**Reasoning.** Same seam, same pins; the 2026-09 reduce-motion work is the template.

**Cost if wrong.** A third-party conformer fails to compile (intended, migration note).

## MT-E — SDL answers `false`, with a documented constraint

**Ruling.** `SDLPlatform`'s window answers `false` and never fires, as for reduce motion:
SDL3 has no accessibility-display query, and a platform setting (GNOME `gsettings`, the
Windows `UISettings`/`SPI_*` transparency effect) is reachable only through a new dependency or
a per-OS shell-out — neither is taken. It is a documented renderer/platform constraint, not a
divergence label: the value `false` is the SwiftUI default. Tested by
`SDLReduceTransparencyTests` (answers `false`, callback unused) and in the Linux image.

**Cost if wrong.** Linux and Windows users with the OS setting still see the blur. A follow-up
can read `SDL_GetSystemTheme`-style settings if SDL grows one.

## MT-F — The fallback: the material's tint colour at opacity 1, a plain rect

**Ruling.** With the value true, every material site resolves `material.opaqueColor` — the
fitted grey of `fill(for: scheme)` at **alpha 1**, so the panel is the scheme's material grey
(light ultraThin 0.925 … bar 1.0; dark 0.2248 … 0.1779) — and draws it with the ordinary
`fill` (a plain rect or `drawPath` for a path), **never a backdrop record**: no split, no blur
pass, no frame-target copy (`lastBackdropSplits == 0`, `lastBackdropBlurs == 0`). One
chokepoint, `Frame.fillMaterial(_:material:cornerRadii:shape:)`, reads
`environmentTop.accessibilityReduceTransparency` and the scheme; the four sites (proposal
`.background(material)`, legacy decoration, `Shape.fill(_:)`, `background(_:in:)`) call it
instead of `fillBackdrop(tint: resolve(material.color))`. Element opacity, clips, radii, ghosts
and drag previews compose as for any rect. A change snaps (no animation). **Divergence 315**:
SwiftUI's fallback is unmeasured (`MT-A`); MetalUI's is a ruling.

**Reasoning.** The grey is already the lightness SwiftUI's material sits at over a window
background; alpha 1 is the definition of "opaque material"; the plain-rect path is the cheapest
and the unaffected window never reaches it.

**Cost if wrong.** A different grey or a wash of the window background: one function
(`opaqueColor`). Retire 249 in the same change (a retired label is never reused).

## MT-G — How tests drive it headless

**Ruling.** `HeadlessPlatform` gains an option `accessibilityReduceTransparency` (default
`false`, AppKit's answer when the setting is off — `HT-X` 1) and `HeadlessPlatformWindow`
`simulateReduceTransparencyChange(to:)`; `TestWindow.setReduceTransparency(_:)` beside
`setReduceMotion`. Scene-level facts read the window's captured scene (`scene.backdrops`
count 0, the rect's colour).

## MT-H — Lanes, pixels, MUST-NOT-MOVE

**Ruling.** Two lanes on disjoint files (spec §Lanes). The fourteen images 0 px against
`930db4a` (the setting is `false` offscreen and `renderFrame` stamps `false`, so no
changed path runs); `DemoFrameDeterminismTests` Expected unedited; identity, hit testing,
accessibility, animation, focus, `List`, `Deferred`, text input untouched. The material
sites' ordering is unchanged when the setting is off: `fillMaterial` calls
`fillBackdrop(tint: resolve(material.color))` byte for byte.

## MT-I — Critic's corrections: conformers, call sites, shared files

**Ruling.** Three defects in the first design, fixed in the spec. (1) Nine compile-guard test
files declare their own `PlatformWindow` conformers (all carry the reduce-motion pair) and were
missing from lane B, so the defaultless pair would break the test build; they are now lane B's.
(2) The four-site list for `fillMaterial` was written from memory; the callers of `fillBackdrop(`
are `AnimatedColor.swift:521`, `ModifiedContent.swift:577`, `Shape.swift:280` and the `ShapeView`
material layers, so lane B greps first, arms each caller, and adds a guard that nothing outside
`fillMaterial` calls `fillBackdrop(tint: resolve(material.color))`. (3) The lanes share the
inventory map, `api-overview.md` and the census; they run in order A then B, each editing only its
own rows, the census re-recorded once after B. Rejected: a probe that forces Reduce Transparency
(touches the user's system setting; `MT-A`); an SDL OS query (`MT-E`); a coloured material
(`MT-C`). No other defect found: `Color.resolve(in:)` and the BB counters exist as the spec cites,
and the `fill(for:)` table matches `MT-F`'s quoted greys.
