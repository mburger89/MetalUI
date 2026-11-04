# Record 200: the layer is tagged sRGB (round 4 item R4-1 PR C)

Branch `feat/r4-1-layer-srgb`, from master `09d2457b`. Decisions: `docs/superpowers/2026-11-03-layer-colour-space-decisions.md` (`LS-A`..`LS-C`). Human checks: group LS. Divergences: **1 narrowed** (207 live unchanged; next label 211).

## 1. What the probes showed (macOS 27.2, 2026-11-03; headers hold the output)

| gate | result | consequence |
|---|---|---|
| `coregraphics-layer-colourspace.swift` (run) | `#38BDF8` read as Display P3 is, in sRGB, (-73, 192, 254) (red clipped to 0), where SwiftUI draws (56, 189, 248); `#FF0000` clips to (255, 0, 0); `#808080` moves by 0 | sizes the old shift: strong on saturated colours, none on neutrals; `#38BDF8` separates the tags even on an sRGB display |
| `appkit-layer-colourspace.swift` (the plan's window gate: `S == C == L1 != L2`) | **not run to a verdict.** `appkit-screen-lock-state.swift`: `CGSSessionScreenIsLocked = 1`, `preflightScreenCaptureAccess: false`. The probe compiles, opens its window and exits 2 with "could not create image from window" | **the gate was not met.** Not a contradiction of the plan, so the change was made on the arithmetic, and the row is narrowed rather than retired (`LS-C`); a person runs the probe and group LS. **Update 2026-11-04:** an unlocked session ran it, see below |

**Update 2026-11-04 (master a88eb210, macOS 27.2).** An unlocked session ran the gate by capturing real windows. One display, 1920x1080, backing scale 1.0, colour space sRGB IEC61966-2.1: not a Display P3 panel and not Retina. `appkit-screen-lock-state.swift` printed no `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`, `preflightScreenCaptureAccess: true`. `appkit-layer-colourspace.swift`, two runs, both exit 0 and identical: `S [56, 189, 248]`, `C [56, 189, 248]`, `L1 [56, 189, 248]`, `L2 [0, 192, 254]`, all `kCGColorSpaceSRGB`, `bitmapInfo 3`; `S == C: true`, `S == L1: true`, `L2 != L1: true`. **The gate is met on an sRGB display.** It is not measured on a P3 panel, so the claim that the layer equals SwiftUI's pixels on a wide-gamut display still rests on the tag and the arithmetic. The row stays narrowed. The readings above are the original finding as it stood on 2026-11-03; they are kept as written.

## 2. What changed

- `MetalLayerSurface.swift`: `layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)`. The pixel format is untouched (`bgra8Unorm`, never `_sRGB`).
- Test: `theLayerColourSpaceIsSRGB` (`Tests/MetalUIPlatformTests/PlatformTests.swift`): the layer's colour space name is sRGB, and the format is still `bgra8Unorm`. The plan's "no headless reading" was wrong; `PlatformTests.swift` already built a surface with no window.
- Row 1 reworded (the P3 clause gone; the `.displayP3` clause and the P3-profiled image direction stay, `LS-B`); comments in `Theme.swift`, `Color.swift`; spec §7.8 amended, `CR-I` and `CR-C` item 6 noted; `docs/migration.md` (every colour less saturated on a wide-gamut display), `api-overview.md`, `drawing.md`, human checks `A1` and group LS, the closeout map cells for `core-color` and `color-value`.
- `Tasks.md`: R4-1 ticked, `R4-1a` (divergence 210) added. `docs/record/05-declared-but-inert.md` has no row about the layer's colour space; no public declaration changed (the three closeout checks print nothing).
- No test flipped (the plan predicted none); the fourteen-image comparison and every parity fixture are unaffected because none reads the drawable.

## 3. Mutations (applied to `MetalLayerSurface.swift` from the committed tree, restored from a copy; `git status` clean after each)

| mutation | reddened |
|---|---|
| `displayP3` (the old value) | `theLayerColourSpaceIsSRGB` (`space.name == CGColorSpace.sRGB`) |
| `layer.colorspace = nil` | `theLayerColourSpaceIsSRGB` (the `#require`) |
| `layer.pixelFormat = .bgra8Unorm_srgb` | `theLayerColourSpaceIsSRGB` (its pixel-format arm) |

## 4. Counts

`swift package clean`, then `swift build --build-system native --build-tests && swift test --build-system native --no-parallel`, unfiltered, at the docs commit: **`Test run with 4998 tests in 14 suites passed`**, 0 failures; `FR-J no-argument frame: succeeded=true` (guards ran). The three closeout checks (`record-05-check.sh`, `closeout-inventory-check.sh`, `closeout-undocumented.sh`) print nothing. `Backends/SDL` tests not run (nothing there changed).

## 5. Not verified

- The window gate and human checks LS1-LS4 (no unlocked session, no Screen Recording permission). Update 2026-11-04: the gate ran and is met on an sRGB display; on a P3 panel and in the human looks it is still unmeasured (section 1).
- That Linux and Windows are unchanged is argued (`SDL_gpu.h:1351`, no composition set), not run; CI covers the build.
