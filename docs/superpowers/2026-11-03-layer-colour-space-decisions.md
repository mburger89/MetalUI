# Layer colour space (round 4 item R4-1 PR C) — decisions (prefix `LS-`)

Rulings for the third of three R4-1 PRs: divergence 1, "the layer's colour space is Display P3 while colours are authored in sRGB". Branch `feat/r4-1-layer-srgb`, from master `09d2457b`. Code:
`MetalLayerSurface.swift` (one line), comments in `Theme.swift` and `Color.swift`. Probes (headers hold the output): `coregraphics-layer-colourspace.swift` (new, run), `appkit-layer-colourspace.swift` (new,
**not run to a verdict**: the session was locked and had no Screen Recording permission). Test: `PlatformTests.swift` `theLayerColourSpaceIsSRGB`. **Next unused: `LS-D`.** Divergences: 1 narrowed; the live
count (207) and the next label (211) do not move. Human checks: group LS.

## LS-A: the presentation layer is tagged sRGB (divergence 1 narrowed; amends spec §7.8, `CR-I`, `CR-C` item 6)

1. `MetalLayerSurface` sets `layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)`. Every colour MetalUI emits is a gamma sRGB number (`CR-C`, probe `swiftui-colour.swift` `R1`) written to a `bgra8Unorm` drawable and
   blended on the stored values (spec §7.8; **unchanged**, never `_sRGB`). The tag only tells the compositor what those bytes mean; Display P3 told it a different thing from what was written, so a hex displayed more saturated than SwiftUI's.
2. SDL already agrees: `SDL_gpu.h:1351` says SDR swapchain content is sRGB-encoded and the backend sets no composition. AppKit now matches it.
3. **What it does not touch.** No shader, renderer or parity fixture reads the property (it is a tag), so nothing but the pin can notice it; the fitted material and glass tables were read through sRGB contexts
   (`swiftui-material-followups.swift:112`, `swiftui-liquid-glass.swift:219`) and are sRGB numbers, so the layer now means what was measured: no refit.
4. **What it changes.** On a wide-gamut display every colour is less saturated, and equal to the same hex in SwiftUI. `coregraphics-layer-colourspace.swift`: `#38BDF8` read as P3 is the sRGB colour
   (-73, 192, 254) (red clipped to 0), where SwiftUI draws (56, 189, 248); a neutral moves by one level at most. A PNG or JPEG with a Display P3 profile (drawn as sRGB by the portable decoder, 138) was right on AppKit by accident and
   desaturates like SDL; ImageIO-decoded formats convert to sRGB and become right; a `MetalView` shader tuned for P3 desaturates, one writing gamma sRGB becomes right. Migration row in `docs/migration.md`.
5. **Plan correction.** The row's "no headless reading" was false: `PlatformTests.swift` already builds a `MetalLayerSurface(device:)` with no window, which is what the pin does.

## LS-B: wide gamut stays unoffered (divergence 1's remaining clause)

`Color.RGBColorSpace` has no `.displayP3` (`CR-C` item 6). With the layer sRGB no colour can leave the sRGB gamut; SwiftUI converts a P3 colour to extended sRGB (`R4`), MetalUI would clamp it. The spelling
stays a compile error rather than a mis-draw. EDR/extended-range output is not built (no source mentions it). A wide-gamut offer is a separate item (a P3 or extended layer plus per-colour conversion), not this PR. Row 1 lives on for this
and for the P3-profiled image direction (138).

## LS-C: the window gate and group LS are owed to a person; the row is narrowed, not retired

1. The plan's gate was the window probe `appkit-layer-colourspace.swift` (`S` SwiftUI `Color(.sRGB)`, `C` a `CALayer` with `CGColor(srgbRed:)`, `L1` a `CAMetalLayer` tagged sRGB cleared to the same bytes, `L2` the same tagged P3 as the
   separating arm; expect `S == C == L1 != L2`; if `S != L1` stop). It compiles and opens its window, but `screencapture -l` could not create an image: `appkit-screen-lock-state.swift` read `CGSSessionScreenIsLocked = 1` and
   `preflightScreenCaptureAccess: false`. The implementer's brief said to stop on a result that contradicts the plan; the probe produced no result, so the change was made on the arithmetic and the argument of `LS-A` 1-2, and the gate was
   not met.
2. Therefore row 1 is **narrowed, not retired**, and the end-to-end claim ("the layer now shows SwiftUI's pixels") is unmeasured. **A person on an unlocked P3 Mac runs the probe, then group LS** (`docs/verification/human-checks.md`; LS1 is the
   side-by-side meter reading). If `S != L1`, revert `LS-A` and record why.
3. Human check `A1` notes that a window differs from `1b093b8` on a wide-gamut display from this commit on.
