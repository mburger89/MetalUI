# 153 — Liquid Glass, SwiftUI's `glassEffect` on both renderers

Branch `feat/liquid-glass` from `f1c422e5` (master after PR #132, §152). **Not a plan task**: new feature work
requested by the user on 2026-10-23 ("can we add liquid glass as an option"; an item of the gpui-gap priority list,
MetalUI only, no configurator change). Spec `docs/superpowers/specs/2026-10-23-liquid-glass-design.md`; rulings `LG-A`…`LG-V`
in the new decisions doc `docs/superpowers/2026-10-23-liquid-glass-decisions.md` (next unused `LG-W`); probe
`docs/probes/swiftui-liquid-glass.swift` (groups `A`, `P`, `R`, `W`; recorded output in its header). Builds on the backdrop
blur (§94, `BB-`).

**Numbering.** Master published no record after §152 before this branch's Record phase (`git fetch`, `origin/master` equals
`f1c422e5`), so §153 stands and no citation moved. Divergence labels 825-829 came from this branch's reserved range 825-834
(830-834 unused); the header's count and next label are left to the merge, as the brief asked.

**Status: LANDED — every agent-doable clause is built; the looks are owed to a human** (`docs/verification/human-checks.md`
group `LG`, §7). Three lanes (A renderer, B SDL, C API), each red first, all verified `ok: true`; the Record phase's close (§8)
re-took the suite, the counts, the inventory check and the fourteen-image comparison.

## §0 Baseline and the probe (2026-10-23)

- **Baseline** at `f1c422e5`: **4402 tests in 3 suites** (native; the later runs print 11), 0 goldens, 271 typecheck guards,
  public census 3798 declarations, `Backends/SDL` 30 + 300 on macOS.
- **Probe** `swiftui-liquid-glass.swift` on macOS 27.0.1 (Xcode SDK MacOSX27, Swift 6.4.2, unlocked screen). `A` reads the API by
  `swiftc -typecheck` with a positive control and a separating arm each: **the SDK's `glassEffect` has no `isEnabled:`** (A4, A5), `Glass` is
  `Equatable` and not `Hashable` (A14, A15), `tint(_:)` takes an optional (A7). `P` reads the default shape: a capsule (3972 of 4000
  grid points agree). `R`: **`ImageRenderer` draws no glass at all**, so no test can compare with SwiftUI and every pixel claim is a real-window
  `screencapture` at 2x (`LG-N`). `W`: the fitted affine of the blurred backdrop per variant and scheme (W2), no inner rim or lens
  in the capture (W3, W6, W7), the merge threshold `spacing > 2 × gap` exactly (W9, W10), a union id rendering one circle between the
  two at any gap (W12-W14, against the documentation), `regular.tint` colour-independent (W8).
- **Carried items.** `grep -i "glass\|liquid"` over the decisions docs and plans finds only `BB-` lines that named a glass-like
  material as out of scope; none is a ruling, all are discharged here.

## §1 What landed

- **Lane A, the renderer** (`LG-B`, `LG-D`, `LG-S`). `MUIBackdrop` grows from 96 to **256 bytes** (the six lanes keep their offsets; a glass tail
  of `glassFlags`, `lensDepth`, `band`, `rimStrength`, `blendK`, `press`, `pressLift`, `glassReserved` and four `MUIGlassMember` slots, members normalised to the
  record's own bounds); **a material's tail is zero and `glassFlags == 0` takes today's arithmetic byte for byte**. `shaders.metal` gains
  `glass_shade` (smooth-min fold over the members, lens read from a **sharp copy** of the frame region, specular rim, press lift),
  `Renderer` gains `sharpCopy` (a blit into a `BB-D` pool texture, so `lastBackdropPasses` stays `L + 2`) and the counters `lastGlassRecords`
  and `lastGlassSharpCopies`. `GlassReference` (`MetalUIPath`, imports nothing) is the CPU twin; `MUIBackdrop.flatTintRects` is the flat arm,
  one rect per member. `Scene` keeps one backdrop array: no new `PrimitiveKind`.
- **Lane B, SDL** (`LG-O`, `LG-T`). `replay.hlsl` reads the record as sixteen `float4` lanes, the backdrop fragment has two sampler pairs (blurred, sharp
  copy), `SDLBridge.c` uploads a 256-byte stride with `FLAT_SLOTS = 4` flat rects and a `SDL_BlitGPUTexture` sharp copy,
  `ReplayFixture` is **version 5** (version 4 widens with a zero tail), `GlassParityFrames` holds Replay frames 12-14, the CI `--expect 12`
  became `15`. Only `backdrop.*` blobs in `Shaders/compiled` changed (nine stages byte-identical, built with the pinned shadercross).
- **Lane C, the API** (`LG-A`, `LG-E`…`LG-M`, `LG-R`, `LG-U`). `Glass` (`.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`),
  `glassEffect(_:in:)` in both vocabularies (one `LayoutModifier` case; a `Decoration` extra), `GlassEffectContainer(spacing: Pixels?)`,
  `glassEffectID(_:in:)` and `glassEffectUnion(id:namespace:)` as transparent `GlassTagScope`s, `GlassEffectTransition` with
  `glassEffectTransition(_:)`, `Namespace`/`@Namespace` (a never-written `State<Bool>` slot, no eighth reserved name),
  `ButtonStyle.glass` and `.glassProminent`, `Frame.fillGlass` (beside `fillMaterial`, Reduce Transparency opaque grey), the
  `GlassLook` table (`package`) and a demo root `METALUI_GLASS_DEMO=1` (`LG-U` 13, `LG-V`).
- **Public surface**: 35 census lines (3798 -> 3833), five inventory families (`glass`, `glass-effect`, `glass-container`,
  `glass-id-transition`, `namespace`), each declaration documented; `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- **Divergences** 825-829 (§4 below); a migration note for the `LayoutModifier` arm, the 256-byte `MUIBackdrop` and fixture v5.

## §2 Tests and guards per file

Root +40 test functions (4402 -> 4442), +2 typecheck guards (271 -> 273).

| File | Tests | What it pins |
|---|---|---|
| `Tests/MetalUIPathTests/GlassReferenceTests.swift` | 5 | `GlassReference` alone: the smooth-min crosses zero at `spacing = 2 × gap` (two gaps), a blob folds in tree order and four is the cap, the lens reads the sharp target only inside the edge band, the rim is brightest toward the upper left, a tint composites source-over |
| `Tests/MetalUIRenderTests/GlassRenderTests.swift` | 9 | Metal readbacks: a zero-tail material renders `f1c422e5`'s bytes (test 2), the shader against the reference on a two-axis field, a tint source-over, a one-member glass with a material's edge, an opacity as a half-weight composite, a glass under a transform, a glass-only scene counts `L + 2` passes, the three-member fold (4b), a blob that cannot blur draws one flat rect per member (11b) |
| `Tests/MetalUIRenderTests/GlassSceneTests.swift` | 2 | the record is 256 bytes and its first six lanes did not move, the flat arm is one rect per member |
| `Tests/MetalUITestingTests/GlassHarnessTests.swift` | 5 | through the headless frame: a container subtree refuses retention by name, a standalone glass replays under retention, a pressed glass button lifts its tint, a glass button keeps its keys and focus, a `Namespace` id is stable across frames and distinct per declaration |
| `Tests/MetalUITests/GlassTests.swift` | 17 | emission order, the capsule default, identity, the dark rows, the merge and union rules, a path's flat fill, the degrade arm, Reduce Transparency, interactive, buttons, transitions, the `fillGlass` call-site scan (36), the demo (37) |
| `Tests/MetalUITests/GlassCompileGuards.swift` | 2 guards | `theGlassSpellingsCompileAndTheNonSDKOnesDoNot` (no `Glass()`, no `Hashable`, no `isEnabled:`, `GlassLook` non-public), `theGlassRegistrationTypesStayNonPublic` (`GlassGroup`, `GlassMember`) |
| `Backends/SDL/Tests/MetalUISDLTests/SDLGlassTests.swift` | 3 | `aGlassFrameOnLavapipeMatchesTheReference`, `theSDLBridgeUploadsTheWholeRecord`, `theThreeGlassParityFramesMatchMetalWithinTheBackdropTolerance` (frames 12-14) |
| `Backends/SDL/Tests/ReplayFixtureTests/ReplayFixtureTests.swift` | +2 | `theFixtureVersionIsFiveAndOldVersionsStillLoad`, `theFixtureStrideIs256AndVersion4Widens` |

`RetainedSubtreeInternalTests` gained the three classifications (`glassGroups`, `glassTags`: `.prepaintOnly`; `glassContainerPaintDepth`: `.frameLocal`)
and `DemoStackBudgetTests` the 1 MB-stack build of the glass demo.

## §3 Probes and red runs

Every lane wrote its tests red first: lane C's tests 17-36 were committed as a compile-red commit (`glassEffect`, `GlassEffectContainer`, `Namespace` and the button styles did not exist),
lane B's tests 13-16 red on fixture v5 and the bridge, lane A's on the record layout. The probe's arms are reproduced by the guards (35a) and `GlassHarnessTests`; no SwiftUI
pixel can be compared by a test (`R`).

## §4 Divergences (825-829)

| Label | Subject | One line |
|---|---|---|
| 825 | colour, lens and rim | fitted table; dark regular is the **minimax line** (grey 0.321 at alpha 0.412, off by at most 14.8/255); tint source-over on both variants; lens and rim are MetalUI's own look (class M) |
| 826 | `GlassEffectContainer` and `glassEffectUnion` | smooth-min merge at `spacing > 2 × gap`, four members per blob (greedy chunks), a union follows the documented intent (SwiftUI measured one circle), the container emits before its content |
| 827 | `.interactive()` off a control | inert (no hitbox: hit testing must not move); on a `Button` a 0.12 white wash while pressed, snapping |
| 828 | `glassEffectID` and `glassEffectTransition` | accepted; no morph; the transitions are the opacity transition |
| 829 | a `Path` shape and the degraded arms | flat tint as the path's own fill; flat arm per member in a CPU raster; Reduce Transparency an opaque grey |

## §5 Mutations

The verifiers re-ran a sample; the rest ran as filtered sets, as the brief's `.build` note allowed. **The families ran filtered, never the whole suite per mutation**, except where stated.

**Lane A (verifier, filtered `Glass|Backdrop`, 51 tests):**

| Mutation | Reddened |
|---|---|
| shader: press lift dropped (`lift = 0`) in `glass_shade` | `theGlassShaderMatchesTheReferenceOnATwoAxisField` |
| shader: coverage ignores the transform pixel scale (`saturate(0.5 - d)` for `saturate(0.5 - d * s)`) | **none: a surviving mutation, a finding** (§6) |

Lane A's implementer ran the rest and threw away its first batch (a header edit through the symlink was not noticed, `LG-S` hazard); `LG-S` 5 names the one equivalent mutant (`glass branch when flags == 0`).

**Lane B (verifier, filtered `Backends/SDL`, macOS, `METALUI_REQUIRE_GPU=1`):**

| Mutation | Reddened |
|---|---|
| `replay.hlsl` smooth-min `k * 0.25` to `k * 0.5`, **source only** | none (the tests run the checked-in compiled blobs; only CI's `SOURCE.sha256` step sees an HLSL edit) |
| the same edit in the checked-in `backdrop.fragment.msl`, all five sites | `aGlassFrameOnLavapipeMatchesTheReference` (`off2.levels <= tolerance`), `theThreeGlassParityFramesMatchMetalWithinTheBackdropTolerance(index: 13)` |

**Lane C (the implementer's 28 mutations, `LG-U` 12; a 138-test glass family set, each from a committed tree, restored by `git checkout`, `git status --short` clean after each).** Reddened, by test
number (full names in `LG-U` 12): M17 paint-after-content 17; M18 default `Rectangle()` 18; M19 identity guards 19; M20 swapped dark rows 20; M21 `2 ×` dropped 21 and 22; M21b chunk size 5 21b; M22
`nil` spacing 0 22; M23 union branch off 23; M24 members also emit 24, 21, 21b, 22, 23, 25, 28, 29, 37; M25 both taints dropped 25; M26 `noteDirect` dropped 26 and 25; M27 rect for a path 27; M28 Reduce Transparency off 28;
M29 degrade arm off 29; M30 hover-only 30; M31 interactive layer registers a hitbox 31; M32/M32b button kinds 32, 32b; M33 random namespace id 33 and 23; M34 `.identity` fades 34; M35a-f the four public-surface mutations and the two
registration types 35a, 35b; M36 a second glass-tailed `fillBackdrop(` 36; M37 demo spacing 4 37. **Verifier re-run of M25 on the full unfiltered suite**: `aContainerSubtreeRefusesRetentionByName` (`reasons["glassContainer"] > 0`) reddened; the same run also
reddened `aWheelMouseEventReachesOnInputInPointsAndATrackpadEventIsUnchanged` once, which passed in both unmutated full runs and cannot see the mutated file (read as environmental; not re-run). M25's `METALUI_VERIFY_RETAINED=1` arm was not run.

## §6 Findings, hazards and named residue

1. **Surviving mutation, unpinned**: the glass coverage's use of the transform's pixel scale `s`. `aGlassUnderATransformKeepsItsMembers` runs at scale 1. A glass under a `scaleEffect` other than 1 against a material's edge would pin it. **Carried, owner: the first change to `glass_shade`'s coverage** (not built in this Record phase: docs only).
2. **The sharp-copy fallback is open** (`LG-T` 5): when the blur succeeds and the sharp copy fails, `Renderer.encodeBackdrop` binds the blurred texture as `sharp`, so the lens reads it at the wrong scale (SDL mirrors it). The fix is one line (clear `glassFlags` bit 1 when `sharp == nil`) plus a pin. **Carried, owner: the next change to `Renderer.swift`**; not triggered by any test.
3. **Header hazard**: SwiftPM's native build does not notice an edit to `MetalUIShaderTypes.h` through the `include` symlink: after editing **or restoring** it, `touch Sources/MetalUIShaderTypes/shim.c` or `swift package clean`; a mutation result taken without it is contaminated.
4. **An HLSL source edit reddens no Swift test**: the tests run the compiled blobs; CI's `Compiled shaders match replay.hlsl` step is the instrument. A shader mutation edits the blob or rebuilds it with the pinned shadercross.
5. **Lavapipe parity has no headroom**: frames 12 and 13 read max delta 3, exactly `BB-J`'s tolerance. Windows D3D12 is CI only and unmeasured.
6. **Not taken at the Record phase**: the Linux image run of `Backends/SDL` (the implementer reports 31 + 299 and the verifier did not re-take it: disk was at the limit), Windows, a clean default-build-system warning count (the verifier's was a cached run), and every look.
7. **Mutations were filtered sets** (§5): a pin that only the full suite sees is not excluded.

## §7 Looks owed — `docs/verification/human-checks.md` group `LG`

LG1 the look in a key window against a SwiftUI app on macOS 26, light and dark (lens depth, rim, sigma, the carried hairline); LG2 the glass buttons and `regular.tint`; LG3 `glassEffectUnion` and the merge neck; LG4 Reduce Transparency's grey; LG5 SDL on a desktop GPU (Linux, Windows D3D12); LG6 a press on a `.glass` button. None performed; the screen was unlocked at the design session only.

## §8 Close (2026-10-23)

- `swift package clean`, native build **0 `error:`**, the only `warning:` SwiftPM's deprecation notice; native unfiltered `--no-parallel` run: see the counts bullet in `CLAUDE.md` (filled from the run below).
- The fourteen offscreen images **0 px** against `f1c422e5` (`compare.sh f1c422e5 HEAD`, lanes A and B; scenes identical, controls match their recorded values); `Expected.swift` unedited.
- Inventory and undocumented scripts print nothing; census 3833 lines (3798 + 35 declarations of the glass families).

## §9 Deferrals, each with an owner

The 1 px outer hairline, the morph between `glassEffectID` shapes, press scale/bounce, more than four members, a real blurred glass on a `Path`, sigma and lens depth against SwiftUI, Windows D3D12 parity (`LG-Q`, owners named there); §6 items 1 and 2 above.
