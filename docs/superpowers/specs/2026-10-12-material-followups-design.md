# Material follow-ups — design (C27)

Rulings: [`../2026-10-12-material-followups-decisions.md`](../2026-10-12-material-followups-decisions.md)
(`MT-A`…`MT-H`). Probe: `docs/probes/swiftui-material-followups.swift`. Branch
`feat/material-followups` from `930db4a`.

## API

```swift
extension Material {
    /// MetalUI-only (class M): the tint a material draws over its blur in `scheme`.
    public func tint(in scheme: ColorScheme) -> Color
}
extension EnvironmentValues {
    public internal(set) var accessibilityReduceTransparency: Bool   // SwiftUI's key, get-only outside
}
// MetalUIPlatform.PlatformWindow, defaultless:
var accessibilityReduceTransparency: Bool { get }
var onAccessibilityReduceTransparencyChange: ((Bool) -> Void)? { get set }
// MetalUITesting
HeadlessPlatform option `accessibilityReduceTransparency`; HeadlessPlatformWindow.simulateReduceTransparencyChange(to:);
TestWindow.setReduceTransparency(_:)
```

Internal: `Material.opaqueColor(in:)` (a new file `MaterialTransparency.swift`, so lane A's
`Material.swift` and lane B never share a file), `Frame.fillMaterial(...)`. Test 8's site list is not trusted from this spec: lane B first greps every caller of `fillBackdrop(` / `material.color` (today `AnimatedColor.swift:521`, `ModifiedContent.swift:577`, `Shape.swift:280`, the `ShapeView` material layers) and gives each its own arm, plus a guard that no caller outside `fillMaterial` remains (`MT-I`).

## Lanes (disjoint files)

**Lane A — the tint read.** `Sources/MetalUI/Material.swift` (the `tint(in:)` method and the stale
class comment, `MT-B`), `docs/probes/closeout-inventory-map.tsv` (row for `Material.tint(in:)`, class
`M`, group `materials`), `Tests/MetalUITests/MaterialTintTests.swift`,
`Tests/MetalUITests/MaterialTintCompileGuards.swift`, `docs/api-overview.md` line, census.
**Lane B — Reduce Transparency.** `Sources/MetalUIPlatform/Platform.swift`,
`Sources/MetalUI/EnvironmentValues.swift`, `Window.swift`, `RenderFrame.swift`,
`Frame.swift` (`fillMaterial`), `Shape.swift`, `ModifiedContent.swift`, `AnimatedColor.swift`,
new `MaterialTransparency.swift`, `Sources/MetalUIAppKit/AppKitPlatform.swift`,
`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`, `Sources/MetalUITesting/*`,
`Tests/MetalUITests/Fakes.swift`, `Tests/MetalUICrossPlatformTests/PortableFakeWindow.swift`,
new tests, `docs/migration.md`, inventory rows for the environment value, **and every test file that declares a `PlatformWindow` conformer** (found by `grep -rl onAccessibilityReduceMotionChange Tests Backends`: `InputAPISeamCompileGuards`, `MenuCompileGuards`, `TransactionCompileGuards`, `AppShellSeamCompileGuards`, `ToolbarCompileGuards`, `ColorSchemeCompileGuards`, `ControlStateCompileGuards`, `PlatformServicesCompileGuards`, `DragAndDropCompileGuards`; `MT-I`). Lanes run one after the other (A, then B); the shared `closeout-inventory-map.tsv` and `api-overview.md` are edited by each lane for its own rows only, and the census is re-recorded once, after B. Lane B calls
`fill(for:)` (internal) only; no lane A symbol. Record/CLAUDE.md/divergence 315 + retire 249 at
the Record phase.

## Tests (each red before, with the mutation that must redden it)

Lane A (red before: does not compile / no such member).
1. `materialTintMatchesTheFillTableForEveryKindAndScheme` — twelve `(kind, scheme)` literals from
   `LK-L` item 3's table. Mutations: change one alpha in `fill(for:)`; make `tint(in:)` ignore
   `scheme`.
2. `theGlassIdentityHoldsForTheSolvedTint` — for three materials and two glass opacities,
   `(1 − t)(1 − m) = 1 − g` within 1e-6 with `t` solved from `tint(in:).resolve(in:).opacity`.
   Mutation: `tint(in:)` returns `opacity(1)`.
3. Guard `materialTintInIsReachableFromAPlainImport` (`typecheckFile`, plain import, `SA-P`).
   Mutation: narrow the method to `internal`.
4. Guard `aMaterialCannotTakeAColourOrBeConstructed` (separating arm: `.tint(color)` and
   `Material(kind:)` do not compile; positive control: `Material.tint(in:)` compiles in the same
   file). Mutation: add a public `Material.tint(_:)`.
5. The inventory and undocumented scripts print nothing (run, not a test).

Lane B (red before: no key / no requirement).
6. `theWindowStampsReduceTransparencyFromItsPlatformWindow` + `…RedrawsOnceAndNotOnARepeat` —
   headless `TestWindow`, `setReduceTransparency`. Mutations: drop the stamp; drop the
   `didSet` guard (the repeat test).
7. Guards: `aScopeCannotWriteReduceTransparency` (A9's arm; read compiles) and
   `aPlatformWindowWithoutTheReduceTransparencyPairDoesNotCompile`. Mutations: make the setter
   public; give the requirements a default.
8. `everyMaterialSiteDrawsAnOpaqueRectUnderReduceTransparency` — four sites (proposal background,
   legacy decoration, `Shape.fill`, `background(_:in:)`) × light/dark: `scene.backdrops` is empty
   and the rect's colour is `opaqueColor`; includes a path fill. Mutation per site: restore its
   `fillBackdrop(tint:)` call (each reddens its own arm; name them).
9. `reduceTransparencyCostsNoBlurWork` — `MetalUIRenderTests`: a frame of materials with the
   setting on counts `lastBackdropSplits == 0`, `lastBackdropBlurs == 0`,
   `lastBackdropPasses == 0`, `lastFrameTargetCopies == 0`. Mutation: `fillMaterial` ignores the
   setting.
10. `aWindowWithoutReduceTransparencyDrawsTheSameSceneAsBefore` — scene equality of a material
    tree, setting false, against the `renderFrame` scene (`MT-H`). Mutation: `fillMaterial`
    uses `opaqueColor` unconditionally.
11. `anOpaqueMaterialComposesWithOpacityClipAndTheDarkScheme` — `.opacity(0.5)` multiplies the rect,
    a clip cuts it, `.preferredColorScheme(.dark)` picks the dark grey. Mutation: resolve the
    scheme from the root instead of `environmentTop`.
12. `togglingReduceTransparencySnapsAMaterial` — no animation store entry (transaction
    `withAnimation`). Mutation: route through `animatedBackground`.
13. `AppKitReduceTransparencyTests` (mirrors `AppKitReduceMotionTests`): live read, notification
    fires once on a change, not on a repeat. Mutation: drop the observer's refresh.
14. `Backends/SDL`: `SDLReduceTransparencyTests` (answers `false`, callback never fires; arms
    `armMainRunLoopExitCheck()`); run on macOS and in the Linux image.
15. `MetalUITestingTests`: `HeadlessPlatform` option default `false`, `setReduceTransparency`
    reaches the tree (`HT-X` 1). Mutation: option ignored.
16. Every PlatformWindow fake implements the pair (compile is the test; `Fakes.swift`,
    `PortableFakeWindow.swift`, `HeadlessPlatformWindow`).
17. Existing: `aFailedBlurTextureDrawsTheFlatTint`, `BackdropRenderTests`, the fourteen images
    (0 px), `DemoFrameDeterminismTests`, `theSevenRetentionSlotsAreMutuallyDistinct` stay green.

Mutation order: commit first, restore from a copy, full unfiltered native run, `git status --short`
after each; the guards of 3, 4 and 7 are each reddened once.

## Demo

None. `METALUI_LOOKS_DEMO=1`'s material section is unchanged (its images must stay at 0 px). The
setting is exercised only by tests and the human check below.

## Human checks (group MT, added to `docs/verification/human-checks.md`)

- **MT-1** AppKit: turn System Settings ▸ Accessibility ▸ Display ▸ Reduce transparency on and off with
  the looks demo open; materials go to flat grey and back with no relaunch; compare against a
  SwiftUI app's material to confirm or retune `MT-F`'s grey (divergence 315).
- **MT-2** AppKit: Activity Monitor / Instruments GPU shows no blur passes while on.
- **MT-3** MetalCreator adoption: the glass panel at the solved tint hides `g` of the backdrop
  (compare a grey backdrop's panel pixel with `1 − g`).

## Scope, deferred

- Material that takes a colour: refused (`MT-C`). `Material.opacity(_:)` as a fill style, and
  `.materialActiveAppearance`: not built, no owner.
- SDL honest platform query: deferred with a documented constraint (`MT-E`); owner a platform
  services follow-up.
- SwiftUI's own fallback colour: unmeasured (`MT-A`); retune after `MT-1`.
