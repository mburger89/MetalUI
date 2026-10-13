# 101 — Material follow-ups: the tint read and Reduce Transparency (C27)

Branch `feat/material-followups` from `930db4a`, merged with master `7f891629` (§99 text over a GPU
surface, §100 continuing press cancel) and `0fb2ea6e` (§98 resign on press; no conflict, number 101
still free). **Not a plan task**: item C27 of the gpui-gap priority list (user request 2026-10-02),
requested by MetalCreator (developer-0a, 2026-10-12, gaps C21-a and C21-b, found planning C21's
adoption; not blocking; MetalCreator was read, never edited). Builds on C21 (§94, `BB-A`…`BB-T`).
Spec `docs/superpowers/specs/2026-10-12-material-followups-design.md`; rulings `MT-A`…`MT-K` in the new
decisions doc `docs/superpowers/2026-10-12-material-followups-decisions.md` (next unused `MT-L`); probe
`docs/probes/swiftui-material-followups.swift` (groups `A`, `O`, `T`).

**Status: LANDED — every agent-doable clause is built; the looks are owed to a human**
(`docs/verification/human-checks.md` group MT, §7). Two lanes, run one after the other (A then B),
each red first, both verified `ok`.

## §1 What landed

**(a) The tint read (lane A, `MT-B`, `MT-C`).** `Material.tint(in: ColorScheme) -> Color` is the fitted
table's `fill(for:)` (`LK-L` item 3) as public API: a grey at an alpha, MetalUI-only (class `M`, SwiftUI
has none). MetalCreator's glass identity `(1 − t)(1 − m) = 1 − g` is then solvable from
`material.tint(in: scheme).resolve(in: env).opacity`: `t = 1 − (1 − g)/(1 − m)`, `t = 0` below `g = m`.
A material that takes a colour, an opacity or an initialiser is **refused** (SwiftUI has none of the
first and last, `A2`, `A5`; `Material.opacity(_:)` is a `ShapeStyle` method there and deferred here,
no owner). `Material.swift`'s stale class comment ("a fitted flat tint, with no backdrop blur
(divergence 166)", wrong since §94) is rewritten to `BB-A`'s truth.

**(b) Reduce Transparency (lane B, `MT-D`…`MT-G`, `MT-J`).**
- `EnvironmentValues.accessibilityReduceTransparency: Bool`, `public internal(set)`, SwiftUI's key
  (read-only outside: `A8` compiles, `A9` fails on `WritableKeyPath`), `false` in a bare value and in
  `renderFrame`.
- Two **defaultless** `PlatformWindow` requirements, `accessibilityReduceTransparency { get }` and
  `onAccessibilityReduceTransparencyChange { get set }`, the reduce-motion pattern exactly: `Window`
  reads at construction, updates through the callback behind a guarded `didSet` (a repeat does not
  repaint), stamps over `environment` beside `accessibilityReduceMotion`, never a `Window.environment`
  write. AppKit reads `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` live and the
  one existing display-options observer refreshes both values, firing on a change only. **SDL answers
  `false` and never fires** (`MT-E`: SDL3 has no accessibility-display query; a platform setting is
  reachable only through a new dependency or a per-OS shell-out; a documented platform constraint, not
  a divergence). `HeadlessPlatform` gains an option (a trailing `Options` parameter, default `false`),
  `HeadlessPlatformWindow.simulateReduceTransparencyChange(to:)` and `TestWindow.setReduceTransparency(_:)`
  (`HT-X` 1). Every test fake and the nine compile-guard conformers carry the pair; `docs/migration.md`
  has the note beside the reduce-motion row.
- **Every material site draws through `Frame.fillMaterial`** (`MaterialTransparency.swift`, a file of
  its own so lane A's `Material.swift` and lane B never shared one). Off, it is
  `fillBackdrop(tint: resolve(material.color))` byte for byte; on, an ordinary rect (or, for a path
  fill, the flat branch) of `Material.opaqueColor(in:)`, the table's grey at alpha 1 (light ultraThin
  0.925 … bar 1.0; dark 0.2248 … 0.1779), through the plain `fill`, so no backdrop record exists and
  the renderer does no split, no blur pass and no frame-target copy (`BB-C`). Opacity, clips, radii,
  transforms, ghosts and drag previews compose as for any rect; a change snaps. The call sites were
  grepped first (`MT-I`): three callers of `fillBackdrop(` — `ModifiedContent`'s `.backgroundMaterial`
  arm, `AnimatedColor`'s legacy decoration and `paintShapeMaterial` (which serves `Shape.fill(_:)`,
  `.background(_:in:)` and the `ShapeView` material layers).
- **Divergence 315** (the grey is a ruling: SwiftUI's own fallback is unmeasured, §2); **249 retired**
  (never reused); 166 unchanged.

## §2 The SwiftUI probe (`MT-A`)

`docs/probes/swiftui-material-followups.swift`, macOS 27.0.1, Swift 6.4, screen unlocked, output in its
header. **A** (compiled snippets, positive control and separating arm each): `Material` has no
`.color` (`A3`), no `fill(for:)` (`A4`), no initialiser (`A5`), takes no `.tint(.red)` (`A2`: it resolves
to the static `ShapeStyle.tint`); `resolve(in:)` returns `Never` (`A7`; `A6` compiling is that artefact,
not a read); `.opacity(_:)` exists (`A1`), `.materialActiveAppearance` exists (`A10`, not built). **O**:
`.opacity(0.5)` halves the tint's weight over the backdrop (regular over black 150 → 77). **T**
(Reduce Transparency in a real window): **inconclusive again, now with a failing positive control** —
the swizzled `NSWorkspace` getter reads true while SwiftUI's own `@Environment` still reads false
(`T0`), and `T1`'s pixels are identical off and on, per material and scheme. Only the system setting
would move it, and an agent does not touch the user's settings; so the fallback grey is ruled
(`MT-F`), and human check MT-1 compares it.

## §3 Red first

- Lane A (`4d46fef2`): `MaterialTintTests.swift:30:26` and `:43:37` `error: value of type 'Material' has
  no member 'tint'`.
- Lane B (`d4d1824b`): `AppKitReduceTransparencyTests.swift:63` `value of type 'AppKitWindow' has no
  member 'accessibilityReduceTransparency'` (the build stops there; the other targets lack the key, the
  pair and the options too).

## §4 Tests and guards, per file

| file | tests |
|---|---|
| `MaterialTintTests` | `materialTintMatchesTheFillTableForEveryKindAndScheme` (twelve literals), `theGlassIdentityHoldsForTheSolvedTint` |
| `MaterialTintCompileGuards` | guards `materialTintInIsReachableFromAPlainImport` (plain import, `SA-P`), `aMaterialCannotTakeAColourOrBeConstructed` (positive control and two separating arms) |
| `ReduceTransparencyTests` | `everyMaterialSiteDrawsAnOpaqueRectUnderReduceTransparency` (every site arm reports, none aborts the loop), `aPathFilledWithAMaterialDrawsTheOpaqueGreyUnderReduceTransparency`, `reduceTransparencyCostsNoBlurWork` (splits, blurs, passes, copies all 0; in `MetalUITests`, not `MetalUIRenderTests`, which does not depend on `MetalUI`), `aWindowWithoutReduceTransparencyDrawsTheSameSceneAsBefore`, `anOpaqueMaterialComposesWithOpacityClipAndTheDarkScheme`, `togglingReduceTransparencySnapsAMaterial` (a fact pin, see §5), guard-test `noMaterialSiteBypassesFillMaterial` |
| `TransactionCompileGuards` | guards `aScopeCannotWriteReduceTransparency`, `aPlatformWindowWithoutTheReduceTransparencyPairDoesNotCompile` |
| `AppKitReduceTransparencyTests` (`MetalUIPlatformTests`) | `theAppKitWindowReadsReduceTransparencyFromNSWorkspace` (live read, one callback per change, none on a repeat) |
| `HarnessReduceTransparencyTests` (`MetalUITestingTests`) | `theWindowStampsReduceTransparencyFromItsPlatformWindow`, `reduceTransparencyRedrawsOnceAndNotOnARepeat` |
| `SDLReduceTransparencyTests` (`Backends/SDL`) | `anSDLWindowReportsNoReduceTransparency` |

## §5 Mutations

Commit first, restore from a copy, full unfiltered native run, `git status --short` after each.
**Lane A** (implementer's filtered runs; the lane A verifier re-ran none):

| mutation | reddened |
|---|---|
| `tint(in:)` made `internal` | `materialTintInIsReachableFromAPlainImport`, `aMaterialCannotTakeAColourOrBeConstructed` |
| a public `Material.tint(_:)` added | `aMaterialCannotTakeAColourOrBeConstructed` |
| one alpha changed in `fill(for:)`, or `tint(in:)` ignoring the scheme | `materialTintMatchesTheFillTableForEveryKindAndScheme` |
| `tint(in:)` returns an opaque grey | `materialTintMatchesTheFillTableForEveryKindAndScheme`, `theGlassIdentityHoldsForTheSolvedTint` |
| `tint(in:)` returns `fill.opacity(1)` | **nothing — an equivalent mutant** (`Color.opacity` multiplies); the spec's wording is corrected (`MT-K` 5) |

**Lane B** (the lane B verifier ran four, full suite, each restored clean):

| mutation | reddened |
|---|---|
| `fillMaterial` ignores the setting | `anOpaqueMaterialComposesWithOpacityClipAndTheDarkScheme`, `aWindowWithoutReduceTransparencyDrawsTheSameSceneAsBefore`, `everyMaterialSiteDrawsAnOpaqueRectUnderReduceTransparency`, `reduceTransparencyCostsNoBlurWork`, `theWindowStampsReduceTransparencyFromItsPlatformWindow`, `togglingReduceTransparencySnapsAMaterial` |
| the `rootEnvironment` stamp removed | `theWindowStampsReduceTransparencyFromItsPlatformWindow` |
| the `didSet` guard removed | `reduceTransparencyRedrawsOnceAndNotOnARepeat` |
| `ModifiedContent`'s `.backgroundMaterial` arm back to `fillBackdrop(… resolve(material.color))` | `anOpaqueMaterialComposesWithOpacityClipAndTheDarkScheme`, `aWindowWithoutReduceTransparencyDrawsTheSameSceneAsBefore`, `everyMaterialSiteDrawsAnOpaqueRectUnderReduceTransparency`, `noMaterialSiteBypassesFillMaterial`, `reduceTransparencyCostsNoBlurWork` (plus the five `AppKitPresentationTests` sheet issues of a locked screen, `CI-AF`, not the mutation's) |

**Findings.** (1) Test 12 (`togglingReduceTransparencySnapsAMaterial`) **has no mutation that reddens
it** (`MT-J` 6): the animation store keeps a track only from a previous value and the previous frame drew
a backdrop record (no colour), so routing through `animatedBackground` would also start nowhere. It is a
fact pin; the snap is by construction. (2) The lane B verifier ran four of the implementer's nine
guard mutations (host load made each suite 7–13 minutes); the remaining five are **not claimed**.
(3) Each new typecheck guard is reddened by its table row: `materialTintInIsReachableFromAPlainImport` and
`aMaterialCannotTakeAColourOrBeConstructed` by lane A's first two rows; the two `TransactionCompileGuards`
arms were reddened by the implementer (setter public; a default given), not re-run by the verifier.

## §6 Suite, pixels, other evidence

`swift package clean`, native build, then the unfiltered `swift test --build-system native --no-parallel` on
the merged tree (`4e82dab5`): **3565 tests in 3 suites passed** (master's 3549 + 16: lane A's 4, lane B's
12), 0 `Issue` recorded, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument
frame: succeeded=true`; **228 typecheck guards** (master's 224 + 4: the two `MaterialTintCompileGuards` and
the two `TransactionCompileGuards` arms, each seen to run, not skip). A first full run on the same build
ended with no summary line (the process was cut off mid-suite, no failure printed); the re-run is the
number above. Census: the inventory map's `materials` family gained `315`, `MT-B MT-C MT-F`; `closeout-inventory-check.sh`
and `closeout-undocumented.sh` print nothing; the census was re-recorded after lane B (`f3eb746f`) and
no public declaration has been added since.

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> 930db4a HEAD`: all fourteen images `differing=0`,
"scene identical" (controls as recorded); `DemoFrameDeterminismTests` Expected unedited.

**Not re-run by the record writer, owed to the next checker:** `Backends/SDL` tests on macOS and in the
Linux image (the SDL change is `SDLPlatform`'s nine-line answer `false` and
`SDLReduceTransparencyTests`; the lane verifier did not run them either), and the real-window capture.
Both lane verifiers' notes agree.

## §7 Owed to a human, hazards, deferrals

**Looks owed (group MT, none performed — an agent cannot):** MT-1 the system's Reduce transparency on and
off turns every material to its grey and back with no relaunch, and the grey is compared with a SwiftUI
material; MT-2 no blur passes while it is on; MT-3 MetalCreator's glass panel at the solved tint hides
`g` of a grey backdrop.

**Hazards.** The fallback grey is a ruling, not a measurement (divergence 315, `MT-A`). `Material.tint(in:)`
commits the fitted table's values as API: a retune moves the number, not the signature. A new material
site must call `Frame.fillMaterial` (the guard scans `Sources/MetalUI`); a direct `fillBackdrop(` is
red. A third-party `PlatformWindow` conformer fails to compile until it adds the pair (migration note).

**Deferrals.** A material that takes a colour: refused (`MT-C`). `Material.opacity(_:)` as a `ShapeStyle`
and `.materialActiveAppearance`: not built, no owner. An SDL query of the OS setting: deferred behind a
documented constraint (`MT-E`), owner a platform-services follow-up. SwiftUI's own fallback colour:
unmeasured, retune after MT-1.
