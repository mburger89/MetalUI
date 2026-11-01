# Drawing and the renderer

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Shapes, images, renderer.** **A new drawable capability lands in both
`Sources/MetalUIRender/Shaders/shaders.metal` and
`Backends/SDL/Shaders/replay.hlsl` identically, checked through the SDL
replay-parity harness, or it is a documented renderer constraint** — never a
silent approximation (`TE-AD`). `Shape.geometry(in:)` returns a rounded rect,
an ellipse or (`GX-D`) a `Path`; `path(in:)` and `geometry(in:)` each default to
the other, so a conformer writes one. Proposal-path `.clipShape` clips hitboxes
to the bounding rect; legacy `.cornerRadius` stays paint-only (divergence 47).
An ellipse or path clip traps (divergence 91). Renderer: no semaphore; the atlas is uploaded
**before** encode (`MetalWindowRenderer.finishFrame`). **Never release an SDL
GPU fence the GPU has not signalled** (`retire_fence`). Image textures are
cached per identity and released when a frame stops referencing them
(`TE-AF`). `Text.requestLayout` uses unguarded `MainActor.assumeIsolated` —
layout must stay synchronous on the main actor.

**Paths, shadows, transforms (`GX-`, record §73).** **A path is rasterized on
the CPU** by `MetalUIPath` (exact-area coverage, nonzero/even-odd, strokes with
caps/joins/miter/dashes) in **device pixels after the composed transform**, and
reaches the scene as an ordinary `MUIImage` (never a new primitive, no shader
change for paths); it stays a vector (`CapturedPrimitive.path`) until
`insertIntoScene`, and a window-owned `RasterCache` keyed by value hands back
the same `ImageTexture` identity on a hit (a key missing a field draws a stale
raster). **Render effects** (`.rotationEffect`/`.scaleEffect`/`.offset`) are
layout-transparent: a 64-byte `MUITransform` side table indexed from words the
primitives already have (`MUIRect.shape` bits 8…31, `MUIImage.filter` bits
8…31, `MUIGlyph.transform`; **index 0 is identity and never stored**, so no
stride or old scene byte moved); a new effect-aware primitive lands in
`shaders.metal` and `replay.hlsl` identically (`TE-AD`). One
`Frame.paintScopes` stack carries transitions, effects and shadows; an empty
stack is the old fast path. **Hitboxes follow the transform** (local rect +
inverse affine + outer clip; `Hitbox.contains` is the one test hover, gestures
and drag read); accessibility frames are the transformed bounding box
(divergence 107). A handler written after an effect shares it through the
**share floor** (a `ZStack`/overlay/background between stops it, `GX-U`).
Proposal effects are `LayoutModifier` layers (one id level each); legacy ones
return `Self` into `Decoration.renderEffects`, around the whole element
(divergence 108). **Shadows are per leaf** (a text draw's glyphs are one leaf
via `beginLeafGroup`/`endLeafGroup` — a new text-drawing site brackets its
draw), silhouette on the CPU, blur sigma = radius, a shadow never hits and a
`Deferred` stops it; text and images under a scale are resampled, not
re-rasterized (divergence 106). **A clip pushed inside a flattening effect (`.offset`, uniform
`.scaleEffect`) is local and, once mapped, cut by the clip at the effect's entry**
(`flatteningClipBase`, `cutToEntryClip`; `GX-X`, record §73 §12); **a nested flattening
effect opened before any clip is pushed inside the enclosing one has no entry clip of its own**
— the outermost's cut, after its map, covers it (`Frame.atFlatteningEntry`, `GX-Y`, §13). A new public declaration spelled
`nonisolated public` hides from the census — write `public nonisolated`.

**Shadow cache (`PF-`, record §90).** The shadow, blur, path and full-gradient rasters are keyed
**relative to a floored device anchor** (`RasterAnchor.swift`: anchor `R`, integer offset `S`,
fractional offset `f` stays in the key): the raster is a pure function of its key, cached
canonical and placed at `+S`, so a whole-device-pixel move or pan hands back the **same
`ImageTexture`** and does no CPU work; a sub-pixel move, a raster cut by its clip (mode 2: the key
holds `clip − S`) and a local mask (mode 3: 2155f1e's absolute key) miss as before (`PF-A`,
`PF-B`, `PF-J`). `keyLeaf` keys a mask only when it decides a byte (`PF-I`); **a new raster site
keys through `RasterAnchor`, never an absolute position, and its extent `E` is conservative**
(`BoxBlur.padding`, nested reach). Pixels equal 2155f1e's (0 px, fourteen images; `PF-N` records the
measured 2× rounding). `RasterCache.lastTexturesMade` joins the work counters (`PF-G`); pins count
work, never time. `.shadow`/`.blur` stay **per leaf**; one shadow of a container is SwiftUI's
`.compositingGroup()` (both vocabularies, one `LayoutModifier` layer, `PF-E`): a
`PaintScope.Kind.composite` pushed **only when a shadow or blur scope is open outside it**,
collecting leaves with their clip depths (`captureDepths`) and re-emitting them as one leaf, stopped
by a `Deferred` barrier; alone it changes nothing, and it does **not** composite an opacity
(divergence 205). `BoxBlur` in `MetalUIPath` runs over unchecked `Int32` buffers, byte-identical to
its reference copy, still importing nothing (`PF-F`).

**Pan rasters (`PN-`, record §118).** Value-identical, no public API, no divergence (labels 485–494 untouched). A path with
**no local mask** whose conservative extent `E` (`RasterAnchor.pathExtent`: bounds with the stroke pad, grown 1) meets the clip, has
area ≤ `RasterAnchor.overscanLimit` (2^20) and lies within half the target's size of it on every side is rasterized over `E`
and keyed `.uncut`, **not by its clip**: the image's content mask cuts at draw time, so a whole-device-pixel pan across a
`.clipped()` edge hands back the same `ImageTexture` and rasterizes 0 pixels (`PN-A`, `PN-B`; amends `PF-J` item 2 for paths only,
bytes measured equal, T2). A placed mask wholly outside the clip draws no image (`PN-G`). Mode 3 keeps today's keys (`PN-C`); shadows, blurs and full
gradients took the same overscan in `OS-` (below). `RasterCache.tint` zero-fills and multiplies only the 8-byte words holding
coverage, byte for byte the reference loop (`RasterCache.lastTintedPixels` counts the pixels multiplied, `PN-D`); R8 coverage with a
shader tint is not built (P3c, `TE-AD`). A cubic whose endpoint moves and a sub-pixel pan miss by design (`PN-E`). Pins count work
(`PanRasterTests`).

**Raster overscan and the pooled scratch (`OS-`, record §124).** Value-identical, no public API, no divergence (labels 545–554 untouched).
`shadowImage`, `blurImage` and the full `gradientImage` call `RasterAnchor.overscanned` as `pathImage` does (`PN-A`; `OS-A`): rastered over
the kind's conservative extent `E` (`RasterAnchor.shadowExtent`/`blurExtent`/`gradientExtent`, the expressions the keys already held, nested
reach and `BoxBlur.padding` included), keyed `.uncut`, the image's content mask cutting at draw time, so a whole-device-pixel pan across a
`.clipped()` edge hands back the same `ImageTexture` and rasterizes 0 pixels. Same predicate and `overscanLimit` as paths (`OS-D`); **mode 3
(a local mask) and the gradient strip keep today's keys** (`OS-E`, `OS-G`; S7 characterizes the miss). **A pin that reads a raster's bounds
reads the extent `E`, not the clip.** `RGBALayer.init(mask:color:)` returns `.empty` for an empty mask (`OS-N`, a latent
`0×12 has a zero side` trap). **`RasterScratch`** (`MetalUIPath`, `package`, imports nothing) is one reusable cell buffer and three `Int32`
buffers owned by `RasterCache` and borrowed `inout` per call, zero-filled on take, an over-`2^22` buffer dropped on return, empty while out so
a nested raster cannot alias (`OS-L`); a call site never holds `&cache.scratch` across a `make` closure. Its win is memory traffic
(allocated bytes -20.6 % on `shadow-drag`), **not time** (`OS-P`). Pins count work, never time (`RasterOverscanTests`, `RasterScratchTests`).

**GPU surfaces — `GPUSurface`/`MetalView` (`MV-`, record §71).** App code
encodes its own GPU work into an offscreen target that MetalUI composites as
an `Image` (clip, radii, opacity, layer, transitions, drag preview), through
the image pipeline with **no shader change on either renderer**. The portable
leaf is `GPUSurface(redraw:value:draw:)`, sized like `Canvas` (the proposal,
10 on a nil axis); its closure takes `any GPUSurfaceContext` and downcasts to
the backend's context (`MetalDrawContext`; `SDLGPUDrawContext` in
`Backends/SDL`); `MetalView` is the macOS-only typed spelling and traps on a
non-Metal context. **The draw contract**: `WindowRenderer.finishFrame(scene:
atlas:surfaces:)` is **defaultless**; each draw runs on the main actor inside
it, into the frame's own command buffer, **before** MetalUI's pass, and must
not commit, enqueue, present or wait (Metal traps, SDL cannot tell). **Redraw**:
`.onDemand` draws on a new target or a changed `value:` — read what the draw
depends on as `value:`, since reads inside `draw` are untracked (divergence
103); `.continuous` draws every painted frame through `noteActiveAnimation()`,
never `requestAnotherFrame()`; a hidden, zero-size, clipped or transparent
surface does no GPU work and releases its target. **Portability split**:
`MetalUIScene` holds only an opaque `SurfaceTarget` (`PS-A`: no Metal, SDL or
closure type); `MetalUIPlatform` holds `SurfaceTargetTable<Handle>`, **the one
per-window target lifecycle every renderer must use** (a copy would drift);
`MetalUIRender` and `Backends/SDL` supply `create`/`release` and composite;
targets are `bgra8Unorm`, never `_sRGB`, premultiplied, clamped to 8192,
**per window** (not on the shared `Renderer`), and are **not** `StateTable`
entries (`SurfaceRegistry`, the seven slots unmoved). **A new backend** adds the
`finishFrame` requirement, composites `.surface` runs as image runs, never adds
a submission for a surface (the fence rule), records a draw only after its
frame commits, and clears a new target. A `FixtureRun` cannot record a surface.
A draw's counter or state must be passed in, never a never-written `@State`
(re-seeded every build).

**Backdrop blur (`BB-`, record §94).** A `Material` is one scene primitive, `PrimitiveKind.backdrop`
(`MUIBackdrop`, 96 bytes, `Scene.backdrops`): the blurred backdrop and the tint together,
`c · o · (T + (1 − T.a) · B)`, so an opacity is a half-weight composite over the **sharp** backdrop
(`BB-A`, `BB-B`); the proposal `.background(material)` is the `LayoutModifier.backgroundMaterial`
case, the legacy `Box`'s lives in `DecorationExtras` (`BB-P`). **A scene with no backdrop takes the old
single pass byte for byte** (every counter 0); one with backdrops renders in segments, split at each
backdrop run, into a per-window frame target and copies it to the drawable, which stays
`framebufferOnly` (`BB-C`). The blur is sigma 52 pt in device pixels: `L` bilinear 2× downsamples until
`sigma_dev / 2^L ≤ 4`, a separable Gaussian, then the quad's read at `(p + ½)/2^L − ½` over the
transformed bounding box clamped to the target — `Scene.backdropRegion` is the one region function,
`BackdropBlurReference` (`MetalUIPath`) the one reference (`BB-D`, `BB-R`). **`shaders.metal` and
`replay.hlsl` hold the same arithmetic** (`TE-AD`; `ReplayFixture` v4, parity frames 9–11); counters
count `L + 2` passes a record, never time (`BB-E`, `BB-S` 1). **It degrades to the flat tint rect
`c · o · T` (`MUIBackdrop.flatTintRect`) by name**: a `Path` fill and a leaf inside a CPU-rasterized
`.shadow`/`.blur`/`.compositingGroup()` (divergence 248), and wherever a renderer cannot blur
(`BB-I`); Reduce Transparency is not honoured (249). **A shader test needs a field that varies on both
axes**: a vertical step let four mutations survive (§94 §6).

**Material follow-ups (`MT-`, record §101).** `Material.tint(in: ColorScheme) -> Color` is the
fitted table's tint as API (MetalUI-only, class `M`; SwiftUI has no read, probe
`swiftui-material-followups.swift` `A3`/`A4`); a material takes no colour and has no initialiser
(`MT-C`). `EnvironmentValues.accessibilityReduceTransparency` is SwiftUI's read-only key
(`public internal(set)`), stamped by `Window` from two **defaultless** `PlatformWindow` requirements
(`accessibilityReduceTransparency`, `onAccessibilityReduceTransparencyChange`) the reduce-motion way
(guarded `didSet`, never a `Window.environment` write; AppKit's one display-options observer serves both
values; SDL answers `false` and never fires, `MT-E`; `HeadlessPlatform.Options` and
`TestWindow.setReduceTransparency(_:)`, `MT-G`). **Every material site draws through
`Frame.fillMaterial`** (a guard scans for any other `fillBackdrop(` or `material.color` read): off, it is
`fillBackdrop` byte for byte; on, an ordinary rect or path of `Material.opaqueColor(in:)` (the table's
grey at alpha 1) with no backdrop record, so no split, no blur pass, no copy, and a change snaps.
SwiftUI's own fallback is unmeasured (the probe cannot move it), so the grey is a ruling (divergence
315; 249 retired).

**Liquid Glass (`LG-`, record §153).** `glassEffect(_:in:)` (both vocabularies; default shape a capsule; **no `isEnabled:`, the SDK has none**), `Glass` (`.regular/.clear/.identity`, `tint`, `interactive`; `Equatable`, not `Hashable`, no initialiser), `GlassEffectContainer(spacing: Pixels?)`, `glassEffectID/Union/Transition`, `Namespace`, `.buttonStyle(.glass/.glassProminent)` (`GlassButtonStyle`, `BY-A`) are SwiftUI's spellings (class A/D; probe `swiftui-liquid-glass.swift`; `ImageRenderer` draws no glass, so no pixel test can compare with SwiftUI). **One primitive:** a glass is a `.backdrop` record whose `MUIBackdrop` grew to **256 bytes** (the first six lanes did not move; a material's tail is zero and `glassFlags == 0` takes the material arithmetic byte for byte); `glass_shade` in `shaders.metal` and `replay.hlsl` hold the same arithmetic as `GlassReference` (`MetalUIPath`), the lens reads a **sharp blit copy** of the frame region, never the pass's own target (`LG-S`); fixture v5, Replay frames 12-14. A container's members **register in prepaint** and the container emits its blobs before its content (four members to a blob, greedy chunks; smooth-min merge at `spacing > 2 × gap`); **its subtree refuses retention by the taint `glassContainer`**; a standalone glass is a plain `fillGlass` paint. `fillGlass` lives beside `fillMaterial` (`MT-I` exempts that file; a second glass-tailed `fillBackdrop(` call is a guard failure). **After editing or restoring `MetalUIShaderTypes.h`, `touch Sources/MetalUIShaderTypes/shim.c`** (the symlink hides it from SwiftPM). **A shader source edit reddens no Swift test** (they run the compiled blobs): edit the blob or rebuild with the pinned shadercross. Divergences 825-829 (830-834 unused); `glassEffectID` accepts and does not morph; the demo root is `METALUI_GLASS_DEMO=1`; looks are group `LG`. Carried: the sharp-copy fallback (clear `glassFlags` bit 1 when `sharp == nil`) and a pin on the coverage's pixel scale (`LG-V`).

**Colour and colour scheme (`CR-`, record §75).** `Color` is SwiftUI's **value**
(`Color.swift`: literals are gamma sRGB, drawn on the P3 layer like a token,
divergence 1; 24 bytes, nonisolated; `opacity(_:)` multiplies; `Color(light:dark:)`,
a palette `Color(Key.self)` and a token `Color(.surface)` never fade on a scheme
switch). Every colour-taking site has a `Color` implementation **and** a
`@_disfavoredOverload` `ColorToken` twin forwarding `Color(token)` — a new site
owes both, or `.background(.surface)` is ambiguous (guards 1.24/1.25); `Element`
stays on `Color`'s `@MainActor` extension, never its primary declaration
(`CR-D`, `CR-W` 2). **One resolution function**, `PaintPass.resolve(_:)`, reads
the element's scoped theme and scheme; no renderer or shader change. An app
palette is a `ThemeColorKey` (`Theme[key]`, part of `Theme`'s equality); the nine
built-in tokens keep the exhaustive switch. **The window stamps
`EnvironmentValues.colorScheme` (never a `Window.environment` write: that
dirties every draw) and selects `lightTheme`/`darkTheme`**; `.preferredColorScheme`
is window-wide, collected during the element walk, and reaches the platform
through the defaultless `PlatformWindow.setPreferredColorScheme(_:)` (SDL records
only, `CR-M`). A scheme from the tree is in the first presented frame: two
ordinary builds, the second snapping every change (`CR-Q`, `CR-Z`). `Appearance`
is a typealias of `ColorScheme`.

**Hot paths (`HP-`, record §111).** P1, value-identical, no public API, no divergence: every change leaves the fourteen images
0 px and every work counter equal. CoreText placement is cached **per `ShapedText`** in a `PlacementBox` (runs read once; the
finished `[PlacedGlyph]` and the rich layout memoised by origin x/y, scale and requested font as bit patterns — a key missing a
component draws stale glyphs, pinned per component for plain and rich); `GlyphRaster.subpixelPlacement` stays the one rule (PT-C),
run on a miss. `GlyphKey` and `RasterKey` store a hash folded by their initialisers/`add…` (bijections, `==` still compares fields;
`MetalUIScene` stays Foundation-free); a raster hit is one probe; a `LocalizedStringKey` literal parses once per process
(`MarkdownContentTable`, lock-guarded). Settled animation paths return before allocating (`inFlight` empty and every value
bit-equal; NaN and -0.0 take the old path). **A closure passed from `@MainActor` code to a stdlib generic costs a dynamic
isolation check per call: a hot loop uses a plain loop or a nonisolated function** (`HP-C`, `HP-I`). Counters are read-backs
(`PlacementBox`, `AnimationStore.borderKeyBuilds`/`numberTrackRebuilds`, `RasterCache.keyProbes`), pins count work. Carried:
`Frame.swift` hot sites and `RetainedSubtree` (C14b-2), layout pre-sizing, `measureNative` hashing, `ForEach` (P2), path-raster
clip key and R8 coverage (P3: pixels and shaders).
