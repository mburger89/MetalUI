# Text drawn inside a GPU surface (`drawText`) — decisions

Round 2 item 5 (user request 2026-10-21; the item `GT-F` deferred, record §99).
Prefix `DT-`. Spec: [`specs/2026-10-22-draw-text-design.md`](specs/2026-10-22-draw-text-design.md).
Record: `../record/141-draw-text.md`. Branch `feat/draw-text` from `5f03ab7b`.
Divergence labels reserved for this branch: 705–714 (none taken by the design;
`DT-H` says why).

SwiftUI's side: `docs/probes/swiftui-draw-text.swift` (arms A0, A, B, C, D; run
2026-10-21, output in its header). SwiftUI's only "draw a text into a surface"
is `GraphicsContext.draw(_:at:anchor:)` / `draw(_:in:)` in a `Canvas`. gpui's
side, where SwiftUI has nothing: gpui's `ShapedLine::paint` pushes monochrome
sprites into the **window's own scene**, never into an app pass — gpui has no
app-owned GPU pass at all, so it cannot answer the pass question; the answer
below is MetalUI's own.

**Next unused id: `DT-K`.**

## DT-A — Build it, as a MetalUI-owned text pass over the surface target

**Question.** `GT-F` deferred `drawText` because it needed "a glyph pipeline
bound to the surface's render pass", a shader change with parity, an atlas that
is uploaded before encode, and it saved nothing while the app kept rebuilding.
Is it sound to build now?

**Evidence.** (1) The three renderers' glyph pipelines are already the right
ones for a surface target: Metal `Renderer.makePipeline` and SDL
`make_pipeline` both build `glyph_vertex`/`glyph_fragment` (`glyph` in
`replay.hlsl`) into `bgra8Unorm` / `B8G8R8A8_UNORM` with premultiplied
source-over (`one`, `oneMinusSourceAlpha` on colour **and** alpha), and a
surface target is the same format, transparent-cleared, premultiplied
(`MV-D`). **No shader change, no blend change, so `TE-AD` has nothing to
land** and replay parity is unmoved (the shader bytes are the checked-in ones).
(2) What `GT-F` called the machinery (`MetalUI`'s transform, backdrop and
segment code of §94) is not involved: a text pass is a bare glyph run with an
identity transform and a clip of the whole target. (3) `GT-A`'s cost table was
re-taken at the head of this branch (recorded in record §141 §2): the overlay is still linear in labels; what the pass saves is the per-label
build, layout and paint, not the text system's work, which `GT-E` already made
a cache hit.

**Ruling.** Build it. The text is **not encoded by the app into its own
encoder**. `drawText` *records* glyph sprites (`MUIGlyph`, the scene's own
record) into a per-frame `SurfaceTextSink`, and the renderer, after every
surface's draw has returned, runs one **MetalUI-owned render pass per surface
that recorded text**: load action `.load`, the target as colour attachment 0,
the existing glyph pipeline, viewport = the target's pixel size. The text is
therefore drawn **after, and on top of, everything the app drew into that
surface**, in `drawText` call order among texts, in the same command buffer
(no new submission, so the fence rule holds by construction; no committed,
enqueued or waited buffer, so the `MV-F` contract is untouched).

**Why not an `encoder`-taking verb** (`drawText(_:at:in: MTLRenderCommandEncoder)`):
(a) the atlas texture bound by an app-owned encoder is `atlasTextureWasEncoded`
the moment it is bound, so a glyph first inserted **later in the same frame**
forces a replacement texture while the app's encoder keeps the old one — a
glyph drawn by the first call and missing from the texture the second call
needs; (b) the pipeline state would be handed to the app, a public surface that
pins our blend; (c) SDL has no equivalent that an app encoder can use without
raw pointers; (d) the app would have to know the pass's load action. A recorded
pass avoids all four and is the same on both backends.

**Cost if wrong.** The one thing an app cannot do is put text **under** its own
later drawing in the same surface (a grid line over a label). The workaround is
two surfaces (a text surface above the drawing one) or the `Text` overlay, and
`DT-E` carries a layered verb with a named trigger. Everything else in the
design is additive: the sink is `package`, the verb is one extension.

## DT-B — The atlas upload moves after the surface draws; one upload per frame

**Question.** `MetalWindowRenderer.finishFrame` uploads the atlas first
(`Renderer.upload`, `MV-F` item 3) and the SDL bridge uploads inside
`mui_renderer_finish`, after the draws. A surface draw that inserts glyphs
(`drawText` rasterizes on an atlas miss) must have them uploaded before the
text pass samples them. Order?

**Evidence.** `Renderer.upload` writes in place only while the texture has never
been encoded (`atlasTextureWasEncoded`) and otherwise allocates a full
replacement; it needs no command buffer, so calling it later is the same call.
No app draw binds the atlas (it has no handle to it), so **nothing between the
top of `finishFrame` and the first MetalUI encode binds the atlas texture**:
moving the call from before the draws to after them changes no texture's
lifetime. A glyph inserted by a draw is in `atlas.dirtyRects` by the time the
single `upload` runs, exactly as one inserted by the scene's paint. On SDL the
upload is already after the draws, inside `mui_renderer_finish`'s copy pass,
before `encode_frame`; the text passes are encoded between the copy pass and
`encode_frame`.

**Ruling.** One upload per frame, **after the surface draws and before the text
passes and the main pass**, on both renderers. The call is `renderer.upload(atlas)`
moved; the dirty-rect accounting (`lastAtlasUploadPixels` headless,
`lastAtlasBytes` SDL, `RG-H`) is unchanged for a frame with no surface text.
Pin: a glyph first inserted by a surface draw is in the uploaded rects (the
counted bytes) and its pixels are in the readback.

**Cost if wrong.** A frame whose only new glyphs come from `drawText` uploads
late rather than not at all; a replacement full upload (the existing slow
path, `atlasTextureWasEncoded` true from the previous frame) is the worst case,
and is the cost of any new glyph today.

## DT-C — Measurement equals a `Text`; the placement is the `Text` placement

**Question.** What guarantees a `drawText` label equals the same `Text`?

**Ruling.** One resolution path, never a second: the verb takes the `ResolvedText`
`TextMeasurer.resolve(_:)` already makes (`GT-B`: font, weight, italic and
colour fixed at resolve time through `resolveTextStyle` and the frame's text
system; probe arm D shows SwiftUI's resolved value does the same). The verb
lays it out with `textLines` (the leaf's own wrap/cap rule, `TE-H` item 2) and
places it with `system.placeGlyphs(…, origin:, scaleFactor: ctx.scaleFactor)`
(the very call `Text.paint` makes), then packs each `TextGlyph` with
`atlas.packed(for:rasterize: system.rasterize)` (the very call
`Frame.drawSprite` makes) into a `MUIGlyph` with `contentMask` = the whole
target. So the glyph records are the ones a `Text` at the same **device**
position emits, and the pin compares them record for record. The surface's own
space is points from its top-left, y down, scaled by the context's
`scaleFactor` (the target is `pixelSize` = bounds × scale, rounded, so the
surface's origin is on a whole device pixel only when the element's own origin
is: the pixel equality is stated for a surface at a whole-device-pixel origin,
which the compared window does; at a fractional one the surface is composited
by the image pipeline's resampling rule, divergence 106's neighbour).
**Colour** is `color:` if given, else the resolved text's own foreground resolved
against the **theme and scheme at the reading point**, captured at `resolve` time
beside the font (a new internal field of `ResolvedText`, so a token
colour is the frame's own and a scheme switch after resolve is the next
frame's resolve).

**Cost if wrong.** A second path would drift; this one cannot, because both
callers are the same two functions. The captured theme is stale by one frame at
a scheme switch, the same staleness a memoized component's `resolve` has.

## DT-D — The verb is SwiftUI's `draw(_:at:anchor:)` spelled `drawText`, on `GPUSurfaceContext`

**Question.** Spelling, receiver, coordinates, wrapping.

**Evidence.** Probe A: no anchor is `.center` (the call equals the explicit
`.center` call pixel for pixel, and differs from `.topLeading`); B: `.trailing`
and `.bottom` move the ink by half the measured width and height; C: the `in:`
rect form **wraps** to the rect's width, while `at:` is unwrapped; D: a resolved
text keeps the font it was resolved with.

**Ruling.**
`public func drawText(_ text: TextMeasurer.ResolvedText, at point: Point<Pixels>, anchor: UnitPoint = .center, width: Pixels? = nil, color: Color? = nil)`
as an extension of `GPUSurfaceContext` (so `MetalDrawContext`, `SDLGPUDrawContext`
and `MetalView`'s closure all have it, one implementation), `@MainActor`.
`anchor` places the **layout box** (the measured size under `width`) at `point`
(probe B); `width: nil` is unbounded (probe `at:`), a finite `width` wraps (probe
`in:`), a finite proposal height caps lines as `measure(in:)` does. The name is
`drawText`, not `draw`, because the request names it and `MetalDrawContext` is
about to own more `draw…` verbs; the SwiftUI differences (no `Canvas`, receiver
is the surface context, `width:` instead of an `in:` rect, a required resolve
through the environment's measurer, call order does not interleave with the
app's own drawing, `DT-A`) are one **class M** entry — MetalUI-only because
SwiftUI's `GraphicsContext` has no GPU context to be a twin of, so the receiver
and the interleaving have no SwiftUI answer; the `at:`/`anchor:` arithmetic is
class A and probed.

**Cost if wrong.** A label placed at the wrong anchor is one default; the pin
matrix covers all nine anchors against `Text` placed by the measured size.

## DT-E — Rich text refuses by name; layering and per-draw ordering are carried

**Ruling.** A `ResolvedText` of the rich form (runs, backgrounds, underline,
strikethrough: ordinary rects inside the text's leaf group, `RT-J`) **traps**
naming `DT-E`, never a silent drop of the decorations (`TE-AD`'s spirit: no
silent approximation). Plain styled-by-environment text (font, weight, italic,
colour) is built. **Carried, with owners:** (1) rich text in a surface — needs a
rect run in the text pass and a clip-free decoration emit; owner: the first
request (a styled dimension label); (2) text **under** later app drawing
(`drawText(…, layer:)` or a per-call pass split) — owner: the first request
that needs a grid over labels, trigger recorded in the record; (3) shadow, blur,
transform, opacity of a surface label: the surface is composited as an image, so
`.opacity`/`.blur` on the `GPUSurface` already apply to its text; a per-label
effect is not offered.

**Cost if wrong.** A trap at the first rich label an author tries: a loud, named,
one-line failure instead of undecorated text.

## DT-F — The portable seam is one `package` class in `MetalUIPlatform`

**Ruling.** `SurfaceTextSink` (final class, `package`, `MetalUIPlatform`, imports
`MetalUIScene` only): holds the frame's `GlyphAtlas`, an array of recorded
`MUIGlyph` and per-surface batches `(target: SurfaceID, range)`.
`GPUSurfaceContext` gains one `package` requirement `var textSink: SurfaceTextSink? { get }`
with a `package` default of `nil` (no public requirement moves: a conformer in
an app still compiles; `MetalDrawContext` and `SDLGPUDrawContext` gain a
`package` stored sink their `package init`s receive; `HeadlessWindowRenderer`
records requests without running draws, so its answer is "text is never
recorded" and `lastSurfaceRequests` is unchanged). `drawText` on a context with
no sink traps naming `DT-F` (an app-defined fake context). Because the verb
lives in `MetalUI` (it needs `ResolvedText`, `Color`, `Point<Pixels>`) and the
sink in `MetalUIPlatform`, `MetalUIPlatform` stays portable and `MetalUIScene`
imports unchanged.

**Cost if wrong.** A `package` seam is changeable; the inventory sees only the
one public verb.

## DT-G — SDL: the glyph run joins the bridge's glyph buffer; one C parameter

**Ruling.** `SDLWindowRenderer.finishFrame` appends every surface's recorded
glyphs after the scene's glyphs (as surface quads join the image array) and
passes a new array of `ReplaySurfaceText {target handle, start, count, width,
height}`; `mui_renderer_finish` encodes, **after the atlas copy pass and before
`encode_frame`**, one pass per entry (`begin_segment`-style, `SDL_GPU_LOADOP_LOAD`
on the target, the viewport uniform set to the target's size, `draw_primitives`
of `KIND_GLYPH` with `first_instance = start`). No new submission, no new fence,
no new shader, no new pipeline. The count of text passes is a C recorder
(`mui_renderer_last_text_passes`) for the work pin. `armMainRunLoopExitCheck()`
in every new SDL test helper; the test is gated `.enabled(if: windowsPresentFrames)`
only where it needs a presented window — the offscreen renderer path
(`SDLPlatform(offscreenRenderers:)`) reads the target back with
`mui_renderer_read_offscreen`'s sibling for a surface target, so it runs in the
Linux image on lavapipe (`METALUI_REQUIRE_GPU=1` in CI).

**Cost if wrong.** The bridge signature gains one array; the Windows compile is
CI-only (check SI3), the one thing the lane cannot run here.

## DT-H — No SwiftUI-visible divergence label beyond the class-M entry

**Ruling.** Probe A–D show SwiftUI's `draw(_:at:anchor:)` and MetalUI's agree on
the arithmetic; the receiver and the order against the app's own drawing differ
because SwiftUI has no GPU context. That is a class-M declaration in
`closeout-inventory-map.tsv` (`MetalUI-only`), **not a `docs/divergences.md`
row** (a divergence is a difference in a SwiftUI API both have). Labels 705–714
stay unused and are named unused in the record.

**Cost if wrong.** A reviewer asks for a row: `DT-` takes `705`.

## DT-I — The measured case for building is capability, not speed (re-take of `GT-A`)

**Question.** `GT-F`'s trigger was a per-frame cost that still scales with N after
C14 and `GT-E`. Does it?

**Evidence** (`SurfaceTextOverlayCostTests.theOverlayCostIsLinearAndCounted`,
unmodified, run at `5f03ab7b` on 2026-10-21 with `swift test --build-system native
--no-parallel --filter theOverlayCostIsLinearAndCounted`, 20 and 100 labels, both
passed): per frame, **0 layout measures, 0 layout-cache lookups, the layout memo
answering the root whole** (the labels' `.offset` registers no node), **1 seam
measure and 1 `placeGlyphs` per label** (`frames * n` each), 0 atlas pixels, 0
rasterized pixels, 0 new textures. What remains per label is one cache-hit measure,
one cache-hit placement and the leaf's paint.

**Ruling.** The trigger is **not met**: a `Text` overlay is cheap and linear, and
`drawText` saves one measure and the leaf's paint per label, nothing a user can see.
It is built anyway because the request is explicit and the capability is real, not
because of speed: a label that is **part of the surface** (composited with the
surface's opacity, blur, clip and transitions, drawn into an `.onDemand` target that
is not redrawn while its `value:` is unchanged, and present in a surface used as a
texture) cannot be a sibling `Text`. The record states this basis so no later reader
cites `drawText` as a performance feature. Accessibility, selection, `.help` and
theming through the element tree remain the overlay's, as `GT-F` said; the guide
keeps both recipes and says which to use.

**Cost if wrong.** If the capability turns out unwanted, the cost is one extension,
one `package` class, one pass per surface with text and one C array; the old path
is byte for byte unchanged for a frame with no surface text (`DT-B`'s pin).

## DT-J — Critique round: colour goes through the one resolution, and what was rejected

**Ruling.** (1) The captured colour is `Color.resolved(theme:scheme:)` of the
measurer's own `environment` (`theme`, `colorScheme`: the internal environment
holds both, `EV-G`; the same function `PaintPass.resolve(_:)` and
`Color.resolve(in:)` call), never a second table; test 4 pins it against
`PaintPass.resolve` under a dark scheme and a token colour. (2) The pixel pin
compares premultiplied bytes over a transparent clear on both sides; an opaque
backdrop would hide a coverage difference. (3) Portable tests cannot run a draw
headless, so they drive a `package` fake context with a real sink (spec, lane 1).
(4) `Point<Pixels>` is the surface's point space (before `scaleFactor`), stated in
the doc comment. (5) The probe was re-run byte for byte at critique (arms A0, A, B,
C, D reproduced the recorded output); no claim lacks an arm. (6) Rejected, with
reasons: a divergence row (`DT-H` stands: no SwiftUI API has a GPU context); an
encoder-taking verb (`DT-A`); a default for the new `package` requirement being
absent (a default keeps app-defined conformers compiling); splitting into more than
two lanes (files are disjoint and sequential already). No Apple type enters a
portable surface, no shader or primitive changes, no public or defaultless platform
requirement is added, no C enum is introduced (the C parameter is a struct array of
integers and pointers).
