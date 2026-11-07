# Symbol images - decisions (prefix `SYM-`)

Rulings for Alloy gap G3, `Image(systemName:)`. Record 230. PR 0 (the probe) lands `SYM-A` only; PR 1 stopped at the plan's stop conditions
(below) and waits for a ruling. **Next unused id: `SYM-B`.**

## SYM-A: the probe's verdicts

Probe `docs/probes/swiftui-symbol-images.swift` (arms S0-S11, macOS 27.2, run twice, `cmp` clean; the header holds the output verbatim).

1. **Size (S1): H1 refined.** SwiftUI's size at a nil proposal is `(NSImage.alignmentRect.width, NSImage.size.height)` of the image configured with
   `NSImage.SymbolConfiguration(pointSize:weight:scale:)`, for all 38 names tried (the Alloy set plus eight robot candidates that exist) over 6 sizes,
   3 scales and 2 weights (maximum difference 0). Plain `NSImage.size` differs for `doc.badge.plus` (up to 9 pt) and `square.and.pencil` (up to 1 pt):
   that is two symbols over the plan's 0.5 pt stop condition, resolved by the refinement, not by a fudge, but it changes the plan's size rule.
2. **Baselines (S2): H2 holds, H3 does not.** First = last baseline = `size.height - alignmentRect.minY` in all 14 rows; the cap-centre model is
   off by up to 2.8 pt. `robot`/`robot.fill` do not exist on macOS 27.2 (`cpu`, `desktopcomputer`, `brain.filled.head.profile`, `gearshape.2`, `ant` do).
3. **Fonts and scale (S3):** no font = `.body` = 13 pt, `.bold()` = `.fontWeight(.bold)`, default `imageScale` is `.medium`.
4. **Tint (S4):** the foreground colours the symbol exactly, the default is `labelColor`, `.tint` is inert, hierarchical secondary layers are at 0.5,
   multicolor ignores the foreground.
5. **Variants (S5):** `symbolVariant` appends to the name in the order slash, then circle/square/rectangle, then fill, and falls back to the
   base name when the result does not exist; an explicit variant name is kept.
6. **Missing name (S6):** a 0 x 0 leaf, empty render, **no stderr**. MetalUI logs once per name anyway (a MetalUI-only diagnostic).
7. **Accessibility (S8):** an `.image` node whose label is SwiftUI's own table (`Favorite`, `Search`, `Document`), which AppKit does not expose:
   `NSImage.accessibilityDescription` reads `favorite`, `Search`, `Document page`. No AppKit-only route reproduces the label exactly.
8. **Pixels (S9): the planned raster route is refuted.** Drawing the configured `NSImage` into a 2x bitmap disagrees with `ImageRenderer` on
   5.5-8.6% of a 40 x 30 pt canvas at an integer origin (max channel 217-255): same shapes, about one device pixel lower, and no constant offset in
   +-1 pt reconciles them. SwiftUI does not snap a quarter-point origin.
9. **Vector (S10):** an AppKit symbol drawn into a PDF context is a Form plus an Image XObject, with no path operators. No outline route exists.
10. **Label (S11):** `Label("Read", systemImage: "doc")` is 54 x 17, icon gap 8, first baseline 13 (PR 3).

**Stop conditions reached** (plan, "Stop and report if"): S1 (two symbols over 0.5 pt, explained by the refinement in item 1) and S9 (over 2% at an
integer origin). PR 1 (the API, the environment fields and the macOS raster route) is not built; the caller rules on how the symbol is drawn
(accept a one-device-pixel placement difference and record a divergence, find another route to SwiftUI's own rasterisation, or carry the
macOS half) before it is.
