# Text

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Text input (`TI-`).** `TextField` is controlled and one line; `TextEditor`
multi-line; both take `Binding<String>`. While a field is focused printable
keys arrive as `.textInput` — **plain-letter `Keymap` bindings are silent**.
`Window.editedText` lets two edits between frames compose. Caret positions
come only from `TextSystem.caretOffsets` (`TI-E`) — never re-derive from
advances. Undo history (`TI-G`) is valid only for the text its last edit
produced.

**Text selection (`SL-`, record §96).** `TextField(_:text:selection:)`/`TextEditor(_:text:selection:)`
over `Binding<TextSelection?>` (macOS 15 like `RangeSet`; the field's state holds it type-erased,
`SL-L`) are **two-way and echo-free**: one `defer` in `Window`'s `onInput` publishes the focused field's
selection after an input that changed it (against `currentText`, under `StateDispatch`), and `prepaint`
applies a binding value that differs from the last one published (`seenBinding`); nil is never an
instruction, a write is held back while composing, a stale index clamps, and a write ends the typing
group but touches no undo stack (`SL-B`…`SL-I`). A field focused from code keeps its stored caret and
focus or resign writes nothing (divergences 265, 266). `TextInputTarget` keeps `Handlers` at 488 bytes
through class-boxed closures (`SL-M`); the demo is `METALUI_SELECTION_DEMO=1`, a root of its own (`SL-N`).

**Text.** `Text`/`ProposalText` measure and draw **only through
`Frame.textSystem`** (`TS-A`); a new text-drawing element goes through the
seam too. Fonts, weight, italic and colour resolve through **one** function,
`resolveTextStyle` (`TE-AA`) — a new text element must call it for both
measure and paint. A finite height proposal caps lines (`textLines`). Never
key a cache on a family or PostScript name — use `FontKey` (its `==` uses the
stored hash as early reject only). `FontResolver.resolve` traps on
non-finite/non-positive sizes. `fonts`/`resolvedFonts` are never swept — move
both or neither. **The glyph atlas reclaims space (`GL-A`..`GL-J`)**: inside a frame it only
*grows* (`GlyphAtlas.packed` doubles it up to `maximumExtent`, every slot keeps
its (x, y)); it is *rebuilt* only by `Window.reclaimAtlasIfNeeded()` at the top of
a draw (`reclaim()` traps mid-frame, `theGlyphAtlasIsReclaimedOnlyAtTheTopOfADraw`).
**Anything that keeps a glyph's rect past the frame must key on
`GlyphAtlas.layoutGeneration` or be dropped when it changes** (`AmbientKey`,
`BuildKey`, the raster key, transition captures, drag snapshots): a new holder
owes the same. Past the cap a glyph is dropped and `droppedGlyphs` counts it; a
new `GlyphAtlas(width:height:)` never grows unless given a `maximumExtent`. Baseline alignment works in a horizontal
stack only.

**Rich text (`RT-`, record §83).** Styled runs in one `Text` cross the seam as
`StyledText` (`MetalUITextSystem`, Foundation-free: text plus runs of
`TextRunStyle` and paint indices; zero-length runs dropped, equal neighbours merged,
a length mismatch traps) through **three defaultless `TextSystem` requirements**
(styled measure, styled layout, decoration metrics) that every conformer and test
fake implements (`RT-F`). **A one-run unstyled `Text` takes the plain calls byte for
byte** — pixels and work of plain text must not move (`RT-M`, test 1.19, the
fourteen images); a `Text` with runs resolves each run once through
`resolveTextStyle`, and CoreText (one `CTTypesetter`) and the portable system
(`shapeCascading` per run, one break table, spacing once per grapheme, ligatures off
for tracked units by feature ranges) agree under the CoreText oracle. Underline,
strikethrough and background are **ordinary rects inside the text's one shadow leaf**
(no shader change, `RT-J`); colours snap (`RT-L`); a link is accent-coloured and
**inert** (divergence 150); accessibility gets the concatenated string. Markdown in
a string **literal** (`LocalizedStringKey`) is parsed by MetalUI's own inline
parser (`MarkdownInline.swift`, checked against Foundation's on 2498 sources); a
`String` value, `Text(verbatim:)` and control titles are never parsed;
`Text(AttributedString)` reads MetalUI's attribute scope (per-key subscripts, never
a generic one: `RT-D`, `RT-T`). `+` is deprecated and traps on a decorated operand
(divergence 155). `TextField`/`TextEditor` stay plain. A new `Text` modifier owes
its field to `resolveRichText`, `ProposalText` and a values test (`RT-S`); the rich
`Text`-level fields stay boxed (`TextRichBox`, the 1 MB stack, `RT-R` 4).

**View-level text modifiers and dash patterns (`TM-`, record 186).** `bold`, `underline`, `strikethrough`, `kerning`, `tracking`, `baselineOffset` and
`monospaced` are also `ElementGroup` environment writes (`EnvironmentValues.textRichBox` + `isBold`): resolution is `run ?? Text ?? environment`, the
nearest writer wins, an own `LineStyle` replaces the environment's whole, and **a new text modifier owes a field to `TextRichFields`, a row in
`resolveRichText`, the `ElementGroup` writer, `ProposalText` and a values test, and a fingerprint row if it adds an environment key** (`TM-A`, `TM-G`).
`plainTextForm` takes the environment's fields: any set makes a text styled (`RT-F` item 3). A pattern is a cycle of multiples of the unit
`max(1, ceil(thickness))` (dot 3/3, dash 10/5, dashDot 10/3/3/3, dashDotDot 10/3/3/3/3/3), cut on the CPU in `drawStyledText` from **the line's own start**
and carried across runs; neighbours join only on one colour and pattern. No shader change (`TM-C`..`TM-E`). View-level `bold()` is a weight of last
resort (`TM-F`). `TextField`/`TextEditor` stay plain (`TM-H`).

**Text over a GPU surface (`GT-`, record §99).** A `Text` overlay over a `GPUSurface` costs
1 leaf measure, 2 seam measures and 1 `placeGlyphs` per label per frame, linear in N, no raster or
upload (`GT-A`; re-take with `theOverlayCostIsLinearAndCounted`), so the
overlay stays the recommended path (`DT-I`) and **`drawText` is built, in `DT-` above** (`GT-F` closed). `@Environment(\.textMeasurer)` is a
get-only `TextMeasurer` (no public initialiser; SwiftUI's `resolve(_:)` + `ResolvedText.measure(in:)`
carried by the environment, divergence 296) that calls the one layout measure through
`resolveTextStyle` and `Frame.textSystem`: the **unrounded** leaf answer, a laid-out frame being
it rounded; an empty `Text` is one line tall (divergence 295, `GT-I`); the frame stamps its system
box and a `\.self` reset keeps it (`GT-D`). `PortableTextSystem` caches an **origin-free**
`[LaidOutLine]` per `MeasureKey` (two-frame lifetime) so a moving plain label shapes once; rich text
still shapes per frame there (`GT-E`, `GT-H`).

**`drawText` in a GPU surface (`DT-`, record §141).** `GPUSurfaceContext.drawText(_:at:anchor:width:color:)` (MetalUI-only, class `M`, no
divergence, labels 705-714 untouched; `GraphicsContext.draw(_:at:anchor:)`'s arithmetic, probe `swiftui-draw-text.swift`) draws a
`TextMeasurer.ResolvedText` through the **one `Text` placement and `resolveTextStyle`** (`DT-C`, `DT-J`): it records `MUIGlyph` sprites into a per-frame
`SurfaceTextSink` (`package`, `MetalUIScene`; contexts adopt the `package` `SurfaceTextSinkProviding`, `DT-F`, `DT-K`), and the renderer runs **one
MetalUI-owned load-op pass per surface that recorded text, after every surface draw returned, over the app's own drawing**, in the frame's own command
buffer (no submission, fence or wait; `MV-F` untouched). **`renderer.upload(atlas)` now runs after the surface draws** (`DT-B`) so a glyph a draw first
inserted is uploaded before use. No shader change on either renderer (the glyph pipelines already blend premultiplied source-over into `bgra8Unorm`),
so `TE-AD` has nothing to land; SDL appends the sink's glyphs after the scene's and passes `ReplaySurfaceText` entries to `mui_renderer_finish`, which
validates each range first (`DT-G`, `DT-L`). **Limits, by name:** plain text only (a rich one traps naming `DT-E`), a context with no sink traps naming
`DT-F`, text is drawn only after the draw returns (never under later app drawing), the headless renderer records no glyphs and runs no pass.
The basis is capability, not speed: the overlay is 1 measure and 1 `placeGlyphs` per label (`DT-I`). Pins are pixel readbacks (macOS hardware, Linux
lavapipe) and counters (`lastSurfaceTextPasses`, `mui_renderer_last_text_passes`); looks are group `DT`.

**Input-method driver (`IM-`, record §102, `docs/testing.md`).** `TestWindow.setMarkedText(_:selectedRange:)`,
`commitMarkedText()` (AppKit's `unmarkText`, which is a commit), `commitMarkedText(_:)` (`insertText`) and
`cancelMarkedText()` (SDL's empty `TEXT_EDITING`) send the platforms' own `InputEvent`s through `onInput`, so the
real `Window` composition path runs, never a test-only shortcut; with no text field holding the caret they send
nothing and answer `false` (`IM-B`, `IM-C`). `HeadlessPlatformWindow.markedText` mirrors `MetalHostView`'s. A field's
AX value is the **committed** text while composing (divergence 325) and a selection write while composing is held
back until the commit (`SL-H`, divergence 326). `Window.focusedElement`'s `didSet` drops the composition of a field
that lost focus (`IM-I`). A selection write ends the open typing group (`SL-O`, measured and pinned).

## Portable text rules (measured against CoreText — re-run the oracle before simplifying)

- `PortableFont` opens one file in FreeType and HarfBuzz and checks they agree
  (`PT-B`). Metrics are `hhea`'s; TrueType metrics round to a 16.16 fraction
  of the em; design units scale `units × (size / unitsPerEm)`; `drawnGlyph`
  drops default ignorables and draws the space glyph for controls/hard breaks.
- Line breaking is libunibreak under `"en-strict"` (`LB-A`, `LB-L`); the four
  fitting rules of `LB-D` are measured.
- **Every shaping path goes through `shapeCascading`** (`FB-A`) — calling
  `HarfBuzzShaper` directly loses fallback. Runs split by bidi level and
  script (`BD-B`, `BD-C`).
- The subpixel placement rule lives once, in
  `GlyphImage.subpixelPlacement(forDeviceX:)` (`PT-C`) — never re-inline it.
- The portable package's Arabic case is the only test that sees a shaping
  offset (`PT-H`).
