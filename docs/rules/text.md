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
focus or resign writes nothing (divergences 265, 266). **`selectedOffsets:`** (`Binding<Range<Int>?>`, Character offsets, MetalUI-only) is the same
binding without `RangeSet`, so it is the macOS 14 spelling (`SL-Q`): `reconcile` tries the `Range<Int>` cast before the `#available(macOS 15, *)` one, and a new
selection spelling must not add an availability gate to that path. **A text replaced from outside moves the caret to the end of a field with no selection binding**
(`SL-P`; SwiftUI's measured rule: any change, only identical text keeps it; with a binding the old offset stays, clamped): `TextEditState.seenText` is set by every own
edit (`recording`, `restored`), so only a replacement differs, and `followExternalText` (focused fields only) runs in the same compared `withState` as `reconcile` — a new text-producing path
must set `seenText` or the next frame jumps the caret. `TextInputTarget` keeps `Handlers` pinned (488, then 480
once its boxes merged into `TextTargetHooks`, `CV-W`) through class-boxed closures (`SL-M`); the demo is `METALUI_SELECTION_DEMO=1`, a root of its own (`SL-N`).

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
owes the same. **A glyph under a flattening scale is re-keyed at `Frame.insertIntoScene` (`TZ-A`): the atlas keeps a `package` slot-to-key map (written on a pack miss, emptied by `reclaim()`) so a holder of a slot can find the key again — a new holder keeps keys, not slots, and a text-drawing site emits the base key and slot as before.** Past the cap a glyph is dropped and `droppedGlyphs` counts it; a
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
**clickable** (`LI-A`; divergence 150 retired): `Text.prepaint` and `ProposalText.prepaint` register one click region per laid-out
piece of a link run, through `registerHandlers` (`Frame.registerTextLinks`, only for a `Text` with a link run, `Text.hasLinkRun`; a plain
`Text` does no extra work, `RT-M`), under one `$link<n>` child id per resolved run, with the geometry paint draws
(`Text.glyphBox`); `TextRunPaint.link` keeps two destinations two runs; accessibility gets the concatenated string and one `.link` child per
run (union frame, no `AXURL`, `LI-E`). The action is `OpenURLAction` over `\.openURL` (uncomparable: a writer refuses retention, `LI-C`),
the default asks `PlatformWindow.openURL(_:)` through the window's weak `URLOpener` (`LI-D`); a link under `.disabled` is inert (218). Markdown in
a string **literal** (`LocalizedStringKey`) is parsed by MetalUI's own inline
parser (`MarkdownInline.swift`, checked against Foundation's on 2498 sources); a
`String` value and `Text(verbatim:)` are never parsed, and a **control's string literal title is** (`Button`, `Toggle`, `Stepper`, `Picker`, `ColorPicker`, `ProgressView`, `Menu`: a `LocalizedStringKey` initialiser and a disfavoured `StringProtocol` one, `SR-C`; `TextField` placeholders and alert titles stay plain);
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
it rounded; an empty `Text` is one line of the resolved font tall where SwiftUI's is a constant 14, and never 0 by 0 (divergence 295, `GT-I`, `SR-A`); the frame stamps its system
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

- **A gradient `foregroundStyle` on text (`TG-`, record 221).** The environment's `foregroundStorage: ShapeStyleStorage?` is the field; `foregroundStyle: Color?` and `Text`/`ProposalText.foregroundColor` are computed over it (a colour written below a gradient clears it; `swift package clean` after touching them). Text paints a gradient through `PaintPass.drawGradientGlyphs` (plain) and `drawStyledText.inkGroups` (rich: one ink group per **equal gradient**, so `g, green, g` shares one span); an underline or strikethrough with no colour of its own follows the gradient and extends the span (`TextRunPaint.underlineFollowsInk`). The gradient spans the **ink**, not the box (`TG-C`). `ResolvedTextStyle.foreground` stays the representative colour (selection, links). **A setter that runs during a tree build must not use a `Color?` map closure** (`TG-A`: it traps off the main thread; write `if let`). A material on text, a `TextField`/`TextEditor`/`drawText` colour still lower (975).

- **A code buffer is `MetalUICodeBuffer`, UTF-8 bytes throughout (`CV-`, record 225).** It imports only `Observation` and lives in the portable manifest list; every edit event is in the coordinates of the text just before it (a multi-range edit applies highest range first), `version` rises by exactly 1 per event, a snapshot is O(1) and `Sendable`, and a rope operation's cost is pinned by `RopeStats.nodesVisited`, never by a clock. A chunk never starts inside a scalar or between a CRLF's `\r` and `\n` (`Rope.problems()` checks it); a view built on the buffer converts to UTF-16 only at the text-system seam, one line at a time.

- **`CodeView` draws a buffer as one leaf with a two-frame line-layout cache (`CV-J`..`CV-R`, record 227).** The cache is keyed by line content (a hash of the bytes, the foreground-partition digest, `FontKey`, scale, tab width, text system, long-line window) and holds glyph keys at pixel offsets from the line's top-left, **never atlas slots**, so a hit is a whole-device-pixel translation and a new holder keeps keys (`TZ-A`); it is an idempotent memo (no `rollbackBuild`), and `METALUI_VERIFY_CODE_CACHE=1` re-lays every hit. Tabs never reach the text system (cut at `\t`, each segment placed at the next multiple of `tabWidth` advances from the pen's real end); a line over 4096 bytes is shaped as a column window. A hot scan over a rope chunk uses a buffer pointer and a `while` loop, never `for … where` over an array element (it allocated per byte). **A per-frame loop over rows, glyphs or bytes is a `while` over an index, never `for … in`, `.enumerated()`, `.last`, `.contains` or `reduce`** (each allocates once per element in a debug build, `CV-R`; the allocation pin is debug-only). Virtual rows are read-only lines in `CodeRowMap`, never buffer text and never selectable (`CV-S`); the scroll position is in display rows and an assigned position is never reported back (`CV-T`); the accessibility value is the visible rows, capped at 64 KB and built only while a client is active (`CV-U`).

- **An editable `CodeView` is a text target whose session does the editing (`CV-W`..`CV-Z`, record 228).** Its `TextInputTarget` carries a `CodeEditSession` in the one `TextTargetHooks` box (a new part of a target goes there, never as a member: `Handlers` is pinned at 480), and `Window` branches on `codeSession` at the top of `dispatchTextInput` (press, drag, text, composition), `dispatchTextKey`, `dispatchTypedKeyPress`, `dispatchFocusTraversal` (no select-all on Tab-in; Control passes so ⌃Tab leaves), `focusedElement.didSet` and `testingComposition`, **never reaching `TextEditing` or a `TextEditState` over a code view's id**; a new text stage owes the same branch and an arm in `aCodeTargetReachesEveryTextStage`. Edits go to the live buffer in input (`replaceSelections` is the typing primitive) and set `CodeViewState.revealsCaret`; the keys are the pure table `CodeEditing.command(for:platform:)` (⌘/⌥ on a Mac, ⌃ elsewhere), run for both platforms by `CodeEditingKeysTests`. A vertical move reads x from `CodeViewPlan.layoutRow` (one row laid out from the text now through the line cache), never from the frame's older rows. The hit test takes window points. An edit key on a read-only view is not claimed. **Marked text, the blink, the autoscroll and the gutter bars (`CV-AA`..`CV-AD`, record 228):** the composition is `CodeViewState.composition`, never in the buffer or its edit stream, laid out in the composing row alone (`Row.marked`, `layoutByte`); the caret's blink is a pure function of `frame.timestamp` read in paint, its frames come from `TimelineStore.noteDeadline` (never `noteActiveAnimation`) and paint taints retention; a drag's autoscroll is stored by input (`start`, bases, velocity) and evaluated by every phase from the frame time, written by none, and rests at a limit; a gutter bar is a hit (`CodeGutterHit`) through `CodeViewPlan.gutterHit(at:)`, its click run in the session's press and its menu through `Handlers.contextual`.
- **Find matches are decorations that follow the buffer and paint only the shown rows (`CV-AE`, record 229).** `CodeDecorations.findMatches` are sorted disjoint UTF-8 ranges mapped through every edit in `apply(edit)` (an edit that touches one drops it, `currentMatch` follows), never painted from stale coordinates; paint takes each shown row's span by a binary search (`findSpan(in:)`), never a loop over all matches (`FrameWork.codeFindMatchesVisited`), under the selection and above the run backgrounds. ⌘G / ⇧⌘G (⌃ off Apple) wrap, select the match with `reveal: true` and are claimed only while matches exist. The search itself is the app's, O(n) per query, never per frame.

- **Block Markdown is `MetalUIMarkdown`, UTF-8 bytes, and imports nothing (`BM-`, record 231).** `MarkdownDocument.append` re-parses only the last top-level block, plus the one above it while the input ends in a line that is still only structure characters (`-`, `#`, `|`, digits, spaces; a half-typed line can turn into a continuation of the block above, `BM-C`); blocks carry ordinal ids that never move, never hashes (`BM-D`); inline content stays raw text for `parseInlineMarkdown`, which keeps a line break as written and the spaces before a hard break, so a view maps soft breaks and trims first. Parser changes owe the 28,561-source streaming corpus and, on Darwin, the Foundation oracle.

- **The Markdown views are values and equatable components (`BM-E`..`BM-J`, record 235).** `MarkdownView`/`MarkdownBlockView` take the theme and the highlighter as stored values (`.markdownTheme(_:)`, `.codeHighlighter(_:)`), never an environment key; **every nested block, list item, fence, chunk and table is `.equatable()` itself** (a component inside a memoized getter's value is otherwise evaluated by the layout recursion each frame); a highlighter is a pure read called once per changed fence and compared by identity; a fence is chunks of at most 32 lines; **a horizontal `ProposalScrollView` takes a vertical wheel for itself, so code wraps and tables do not scroll by default**; a rich `Text` has no layout-memo key, so the unchanged rich blocks of the changed reply are measured again (carried, `BM-J`).

