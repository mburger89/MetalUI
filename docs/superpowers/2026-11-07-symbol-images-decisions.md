# Symbol images - decisions (prefix `SYM-`)

Rulings for Alloy gap G3, `Image(systemName:)`. Record 230. PR 0 is the probe (`SYM-A`); PR 1 (`SYM-B`..`SYM-M`) is the shared API and the
macOS raster route, built after the coordinator ruled on the two stop conditions the probe reached. **Next unused id: `SYM-N`.**

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

**Stop conditions reached and ruled.** The probe reached S1 (two symbols over 0.5 pt) and S9 (over 2% at an integer origin); the coordinator ruled: accept the
AppKit raster after one bounded attempt on the placement (`SYM-C`, divergence 227), use H1' for the size (`SYM-D`), a probe-measured label table with the
AppKit fallback (`SYM-H`, divergence 228), a silent missing name (`SYM-G`).

## SYM-B: the API

Class `A`, SwiftUI's spellings. `Image(systemName:)`; `Image.Scale` (`small`, `medium`, `large`) with `EnvironmentValues.imageScale` and `imageScale(_:)`;
`SymbolRenderingMode` (`monochrome`, `hierarchical`, `multicolor`; **no `.palette`**, `SYM-M`) with `symbolRenderingMode(_:)` as an `ElementGroup` modifier and as a
method on `Image` (the image's own beats the environment's); `SymbolVariants` (`none`, `fill`, `circle`, `square`, `rectangle`, `slash`, chains, `contains`) with
`EnvironmentValues.symbolVariants` and `symbolVariant(_:)`, which adds up through nesting (SwiftUI's nesting is unmeasured, `SYM-M`). The rendering mode has no public
environment key (SwiftUI has none). `Image` stores a `Content` enum (`bitmap(ImageBitmap, scale:)`, `symbol(name:)`): `swift package clean` after pulling.

## SYM-C: the raster route and its cache

macOS draws the symbol through AppKit: `NSImage(systemSymbolName:)` with `NSImage.SymbolConfiguration(pointSize:weight:scale:)`, drawn through
`NSGraphicsContext(cgContext:flipped:)` into a premultiplied RGBA8 sRGB bitmap of `round(bounds x scaleFactor)` pixels, painted by `PaintPass.drawImage` (no shader or
primitive change, `TE-AD` untouched; SDL on macOS gets it too). **Placement.** The plan drew the image at its layout rect. A bounded attempt (header of the probe:
`draw(in:from:operation:fraction:respectFlipped:hints:)`, a ctm-hinted `cgImage(forProposedRect:)`, a snapped rect, 4x configuration, uniform scale search, a +-1 pt
translation search at 0.125 steps) found no rule that closes the gap below 1% off by more than 16: the best translation differs per symbol and the residue after it is
edge coverage. The plain draw ships (divergence 227: 1.8% / 2.1% / 3.5% of a 60 x 50 pt canvas at 13 / 17 / 26 pt over 14 symbols). **Cache.** `SymbolRasterCache` is
process-wide (a window's `RasterCache` drops what a frame did not touch, which would re-rasterise after every retained replay, and a shared cache keeps one texture
identity per key across windows, `TE-AF`): monochrome coverage by (name, point size, weight, scale, pixel size, stretched, device scale), tinted textures by that and the
colour; hierarchical and multicolor are coloured by AppKit and keyed by colour (multicolor without it). LRU 512 per table; counters `rastersMade`, `tintsMade`, `lookups`.
**Linux and Windows: every name is missing in this PR** (an empty 0 x 0 leaf; the bundled icons are PR 2, `SYM-I`).

## SYM-D: sizes and baselines (H1', H2)

Point size and weight are the resolved font's (`resolveTextStyle`), the scale `imageScale`. **Width is the alignment rect's width, height the image's** (probe S1:
`doc.badge.plus` 15 x 18 where `NSImage.size` says 17 x 18); `firstBaseline = lastBaseline = height - alignmentRect.minY` (S2); the paint shifts the image left by
`alignmentRect.minX`. A resizable symbol answers its proposal and stretches the image over the texture (S7); no baselines. Layout is a native leaf, so it measures through
the layout memo (the environment fields are in the fingerprint, `SYM-K`).

## SYM-E: tint and modes

The foreground colour comes from `resolveForeground` (`.textPrimary` by default; SwiftUI's default is `labelColor`, the theme's token stands in) resolved to sRGB. Monochrome:
coverage times colour (a colour change re-tints, no raster, test 14). Hierarchical: `NSImage.SymbolConfiguration(hierarchicalColor:)` with the foreground (secondary layers at
AppKit's 0.5, probe S4). Multicolor: `preferringMulticolor()`, the foreground ignored (S4). `.tint` changes nothing (S4).

## SYM-F: variants

`resolveSymbolName(_:variants:exists:)` is pure and shared: the name with slash, shape, fill appended in that order; a missing full name drops words with priority
slash > shape > fill, then falls to the name; an explicit name is kept (`star.fill` + slash stays); `nil` when the name itself is missing (probes S5, S5b).

## SYM-G: a missing name

An empty 0 x 0 leaf, no hitbox, no accessibility node, **no stderr** (SwiftUI is silent, S6). `SymbolDiagnostics.misses` counts each name once, for tests.

## SYM-H: accessibility

An `.image` node labelled with `SymbolAccessibilityLabels` (SwiftUI's label for the 38 names probe S8b read, verbatim) and otherwise AppKit's `accessibilityDescription`
(divergence 228). `.accessibilityLabel` replaces it, `.accessibilityHidden(true)` records nothing, inside a `Button` the button's rule applies (`BA2`). A symbol is never
`isDecorative`.

## SYM-I: the catalogue and licence (PR 2)

Carried: the bundled Lucide subset for Linux and Windows. **Agent icon suggestion for Alloy:** `robot` does not exist on macOS 27.2; of the existing candidates `cpu` is
the only one that reads as a machine agent at 13 pt; `brain.head.profile` (planned) stays for "thinking".

## SYM-K: the environment fingerprint

`imageScale`, `symbolVariants` and `symbolRenderingMode` are `EnvironmentFingerprint` fields (named in `differences(from:)`); a retained subtree misses when they change
(tests `RetainedSymbolImageTests`).

## SYM-L: cursor and toolbar

`PointerStyle.image(Image(systemName:))` rasterises the symbol once at the body font, medium scale, black, scale 2 (the cache hands back one texture, so one cursor per
name); a missing name is the arrow. A toolbar button's `Image(systemName:)` uses the same raster; **the template flag that would let `NSToolbar` recolour it is not built**
(carried).

## SYM-M: carried

The vector route (no outline exists in AppKit, S10), `Label(_:systemImage:)` (PR 3: S11 icon gap 8, baseline 13), `Text(Image)` (the `RT-A` trap stays), `.palette`,
`variableValue`, `symbolEffect`, a symbol spacing edge (213), the nesting semantics of `symbolVariant`, and a name that already carries a shape (`bell.circle` + slash).
