# Symbol images - decisions (prefix `SYM-`)

Rulings for Alloy gap G3, `Image(systemName:)`. Record 230. PR 0 is the probe (`SYM-A`); PR 1 (`SYM-B`..`SYM-M`) is the shared API and the
macOS raster route, built after the coordinator ruled on the two stop conditions the probe reached. **Next unused id: `SYM-R`.**

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

## SYM-I: the catalogue and licence (PR 2, record 232)

**`MetalUIIconData`** is a new portable target that imports nothing: `package` data only (`IconPathData`: `[UInt8]` opcodes 0 move, 1 line, 2 cubic, 3 close, and `[Float]` coordinates on a 24 x 24 grid), no parser, generated by `scripts/vendor-lucide.py` (run with `python3 -I`) from **one pinned `lucide-static` 1.70.0 tarball** (sha256 `3d1f09df1c468abe512ee6d6596db0dc773fa46c61050e365f0c5fee5120f16a`, the npm registry's sha1 and sha512 integrity checked; licence ISC with the Feather icons under MIT, verified by the script before it writes anything). The script reads the tarball with `tarfile` and executes nothing in it; circles, rects, lines, polylines, polygons, quadratics, smooth curves and SVG arcs are all converted to the four opcodes, so neither the runtime nor `MetalUIPath` needs arc maths. 29 icons, 421 opcodes, 1504 coordinates, about 15 KB of source. `VENDORED.md` and `LICENSE` sit beside the data and are excluded in the manifest, as `CStbImage`'s are; `THIRD-PARTY-NOTICES.md` gains "Lucide (ISC) / Feather (MIT)" and a column in the product table (every `MetalUI` product contains it). **SF Symbols never leave macOS** (drawn through AppKit only, never bundled or cached to disk).

**The name table** (`BundledSymbols.table`, `Sources/MetalUI/BundledSymbols.swift`) maps 38 SF names to the 29 icons: the plan's table (magnifyingglass, doc, doc.text, pencil, square.and.pencil, doc.badge.plus, terminal and apple.terminal, brain and brain.head.profile, sparkles, globe, person, person.crop.circle, exclamationmark.triangle, xmark, xmark.circle, play, stop, stop.circle, checkmark, chevron.right and .down, doc.on.doc, arrow.uturn.backward, arrow.up.right.square, rectangle.split.2x1), `cpu` for the agent (`robot` does not exist on macOS 27.2 or in Lucide's set), and the plain shapes `star`, `circle`, `square`, `triangle`. **`.fill` exists only where the outline is closed and fillable**: `play.fill`, `stop.fill`, `star.fill`, `circle.fill`, `square.fill`, `triangle.fill` (a fill layer under the stroke, so the filled shape keeps the outline's size); every other `.fill` falls back to the base name by `resolveSymbolName`. `Icon.bundled(_:)` takes the exact SF name.

## SYM-J: the portable box, baseline and stroke (PR 2)

Fitted to probes `S1` and `S2` (the sample is 38 names x sizes 9, 11, 13, 17, 26, 48 pt x the three scales, regular weight, macOS 27.2). **Box:** a square of side `pointSize x f[scale]`, `f` the median of the alignment rect's width and the image's height over the sample (the two things `S1` found SwiftUI lays out by): 0.941, 1.154, 1.462, rounded to **0.94, 1.15, 1.46** (small, medium, large). **Baseline:** `S2` found SF's baseline is `height - alignmentRect.minY` (H2); the portable box has no alignment rect, so the baseline is `side - pointSize x a[scale]` with `a` the median of `alignmentRect.minY / pointSize` (0.091, 0.192, 0.346; rounded **0.09, 0.19, 0.35**), first and last alike. Against SF's own `minY` over the sample the fit's mean error is 0.82, 1.01 and 1.28 pt (small, medium, large; the cap-centre model of the plan, H3, 0.99, 1.13 and 1.39); the worst rows are the 48 pt ones and symbols much wider than tall (`brain`, `cpu`), 8-13 pt; the portable box is square where SF's is not, which is divergence 230. **Stroke:** `(side / 24) x w(weight)` in points with `w` 1, 1.25, 1.5, 2 (regular, Lucide's own), 2.25, 2.5, 2.75, 3, 3.25 from ultra-light to black; a custom `Icon` layer stroke of width `u` draws `u x (side / viewBox) x w(weight) / 2`, so Lucide's `2` is the table. The weight is the nearest of the nine `Font.Weight` values. Caps and joins are Lucide's, round. **Paint:** the layers' paths are mapped by one uniform transform (the larger side of the view box fills the smaller side of the bounds, centred) and drawn by `pass.drawPath`, which is the existing raster cache, crisp under transforms, retained replay and both renderers; no shader or primitive change. A secondary layer under `.hierarchical` is the foreground at alpha x 0.5 (`HY-A`'s factor); `.monochrome` and `.multicolor` draw every layer in full (divergence 231). The foreground is the foreground style (`textPrimary` by default), never the tint.

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

## SYM-N: the route and its seam (PR 2)

`SymbolRoute.usesBundled` is `true` wherever AppKit is not importable, and on macOS only while the `package` static `SymbolRoute.forcesBundled` is set (a test seam, default off): the portable layout and paint are tested on every CI platform and by the macOS run. `Image.Content.icon(Icon)` is `Image(icon:label:)` and `Image(decorative:)`, laid out and painted by the same code. A bundled symbol's accessibility label is SwiftUI's table entry for the resolved name (`SYM-H`); a name outside the table records no label rather than an invented one. A missing name is the empty 0 x 0 leaf of `SYM-G`.

## SYM-O: carried by PR 2

An icon or bundled symbol as a cursor or native toolbar image (paths have no raster to hand `PointerStyle.image` or `_toolbarLabel`: the arrow and the label alone stay), a monochrome-only fill rule for open outlines, `.palette`, multi-level bundled icons, Lucide icons beyond the 29, and re-fitting the box if a later probe reads a different macOS.

## SYM-P: a `.circle` SF name with no Lucide circled form is the script's ring composite (record 252, Alloy gap G16)

`eye`, `eye.slash`, `eye.circle` and `eye.slash.circle` draw on Linux and Windows. `eye` and `eye.slash` are Lucide `eye` and `eye-off`. Lucide 1.70.0 has no circled eye (its eye icons are `eye`, `eye-off`, `eye-closed`, `eye-dashed`, `scan-eye`), so `scripts/vendor-lucide.py` builds `eye-circle` and `eye-off-circle` from its `COMPOSITES` table of (synthetic name, inner Lucide icon, scale): Lucide's own `circle` (cx 12, cy 12, r 10) followed by the inner icon's coordinates scaled about (12, 12) by **0.5**, baked into one path. The stroke width is not scaled (the ring and glyph share Lucide's 2, as SF's circled symbols share one weight). 0.5 is the largest simple factor that leaves a visible gap: the off-eye's slash reaches (7, 7) to (17, 17), 8.1 from the centre with its cap against a ring whose inner edge is at 9; 0.6 would touch. No runtime change (`MetalUIIconData` stays pure data, `BundledSymbols.Entry` is unchanged); a later `.circle` request adds a row. This is a MetalUI choice. Divergence 230 already covers the look (a mapped SF name draws Lucide art in a fitted box), so no new label.

## SYM-Q: MetalCreator's toolbar symbols, and a filled-half panel is an outline over a vendored strip (record 279, MetalCreator gap G)

Nine SF names draw on Linux and Windows: `arrow.uturn.forward` -> Lucide `redo-2` (the mirror of `arrow.uturn.backward` -> `undo-2`), `square.and.arrow.up` -> `share`, `plus.magnifyingglass` / `minus.magnifyingglass` -> `zoom-in` / `zoom-out`, `sidebar.left` -> `panel-left`, `house` -> `house`, `camera` -> `camera`, and the two filled-half names `rectangle.lefthalf.inset.filled` and `rectangle.bottomhalf.inset.filled` -> `panel-left` and `panel-bottom` (same 1.70.0 tarball, same licence, nothing new in `LICENSE`). Lucide 1.70.0 has no filled panel, and `Entry.filled` would fill the whole panel (SF fills only the inset half), so `Entry` gains `fillShape`: the name of a vendored closed region filled under the stroke instead of the whole outline. `scripts/vendor-lucide.py` gets a `SHAPES` table of hand-written path data, `panel-left-fill` (x 3...9, y 3...21 with the panel's r 2 corners on the left) and `panel-bottom-fill` (x 3...21, y 15...21, corners at the bottom), so the filled half is exactly the half of the panel the divider cuts off, and the stroke redraws the whole rounded rect over it. 51 icons are vendored. The `.fill` precedent (`play.fill`) is not extended: `sidebar.left`, `house` and the others have no `.fill` entry and `symbolVariant(.fill)` falls back to the outline (`SYM-F`). The look is Lucide's, not SF's, which divergence 230 already covers, so no new label. A segmented `Picker` with `Image` segments needed no change (tested, record 279). The nine names have no measured SwiftUI accessibility label (`SYM-H`'s table is a probe's reading, `S8b`), so on the bundled route they record none until a probe reads them; carried.
