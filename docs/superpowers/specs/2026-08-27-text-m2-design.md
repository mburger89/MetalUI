# Text (M2, first cut) — Design

**Date:** 2026-08-27
**Status:** Approved design; implementation plan not yet written.
**Parent spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §5.5 (measure functions), §6 (text), §7.1 (primitive set), §12 (milestones)

---

## 1. Goal

A `Text` element that the layout engine measures and the renderer draws: shaped
by CoreText, wrapped at its offered width, rasterized into an atlas, and painted
as `monochromeSprite`.

This closes the last thing content sizing left open. `newLeaf` is the only way to
attach a `MeasureFunction` and **nothing in `Sources/` called it before this
milestone** — as of Task 4 the caller is `Frame.requestLeaf`, reached from
`Text.requestLayout` — every
production node's `tree.measure()` is `nil`, so §9.2's content branch and §4.5's
automatic minimum are live for *containers* and dead for *leaves*. A leaf's
content is text, and this is the milestone that supplies it.

## 2. Scope

**In:** font resolution, shaping, metrics, wrapping at a width, the
`MeasureFunction`, glyph rasterization, atlas packing and eviction, the
`monochromeSprite` draw path, and a `Text` element.

**Out, deliberately:**

- **The shape-once/wrap-by-advances fast path** (§6.3) and the **hand-rolled
  UAX #14 subset** (§6.4). Both are *optimisations over a working implementation*
  — see §4.2. M6.
- **MSDF glyphs.** Decided for the node canvas, sequenced at M5 with the canvas
  itself (§6.2, revised 2026-08-27). No canvas exists before then, so MSDF
  quality and atlas thrash cannot be measured.
- **Selection, caret, hit-testing, IME** (§6.6). M6.
- **Baseline alignment.** This milestone *removes its blocker* without
  implementing it — see §6.
- **Rich text.** One font, one size, one colour per `Text`.

## 3. Architecture

### 3.1 A new target, and where the seam falls

`MetalUIText`, importing `MetalUICore` and CoreText. **No Metal.**

| Module | Owns |
|---|---|
| `MetalUIText` | font resolution, shaping, metrics, wrapping, glyph rasterization into **CPU bitmaps**, atlas packing |
| `MetalUIRender` | uploading the atlas to an `MTLTexture`, emitting `monochromeSprite`. Gains a dependency on `MetalUIText` |
| `MetalUI` | the `Text` element; attaches the `MeasureFunction` through `newLeaf` |
| `MetalUILayout` | **untouched.** The engine never learns what text is; it calls a `MeasureFunction` |

**Rasterization and packing stay CPU-side and Metal-free, and that is
load-bearing rather than tidy.** This project verifies headlessly — the layout
corpus runs against WebKit with no GPU, and CLAUDE.md records that the ABI probe
*skips* without a Metal device. A shelf packer reachable only behind Metal is a
packer with no CI, and packing is exactly the arithmetic that wants a test.

This also makes the package's eight non-test targets real against §3.1's seven.
CLAUDE.md already predicts that and says not to reconcile the two lists: §3.1's
seven is the module *layering* (including `MetalUIText`, excluding the demo
executable).

### 3.2 Shaping, and the cache

`MetalUIText` vends a `ShapedText`: the typesetter, the resulting lines, each
line's advance, and the vertical metrics (ascent, descent, leading).

**Cache key: `(string, resolvedFontKey, size, width)`**, on the window beside the
`StateTable`.

- **`resolvedFontKey` identifies the resolved `CTFont` including variation
  coordinates and matrix — never a family or PostScript name.** *(Erratum 2026-09-10: it identifies the font for glyph identity, not its shaping behaviour — the UI font and `"System Font"` at one size share a key and shape non-Latin text differently; `twoRequestsWithEqualFontKeysShareOneShapeThoughTheyShapeDifferently`, pinned wrong on purpose.)* §6.1 measured the
  trap: requesting `"SFMono-Regular"` by name on the target machine returned a
  font whose PostScript name is `Helvetica`. A name-keyed cache serves one font's
  glyphs for another's.
- **`width` is in the key because wrapping is width-dependent** — this is §5.6's
  "wrap cache with real per-width cost".
- **The cache is keyed on CONTENT, not on element identity.** Two elements
  showing the same string shape once. It is deliberately not the `StateTable`:
  §4.3 is for state that *cannot* be recomputed from the element values, and a
  shaped line can be. Putting it there would also key on identity and shape the
  same string twice.

**Why a cache at all, measured rather than assumed:** §4.5's automatic minimum
probes every item and an `auto`-cross item probes again, so a leaf's
`MeasureFunction` is called up to three times per layout — at up to three
distinct widths. Uncached, that is three typesets per text node per frame.

### 3.3 Wrapping is CoreText's job in this milestone

`CTTypesetterSuggestLineBreak` + `CTTypesetterCreateLine`, per display line, at
the offered width.

**§6.4 says CoreText exposes no width-independent line-break API, and that is a
complaint about the fast path, not about correctness.** A width-taking API is the
wrong shape for an *arithmetic re-wrap from cached advances*; it is exactly the
right shape for "wrap at this width". Re-typesetting per display line is also
what §6.3 requires for base-RTL paragraphs regardless — where the measured run
origins (`-3.6 / 0.0 / 20.2 …`) are not reproducible from full-line advances. So
this milestone ships the branch that is **always** correct, and M6 adds the fast
path over it, measurable against a working implementation.

### 3.4 The measure function

| `available` | answer |
|---|---|
| `.maxContent` | one line per **hard** line break (no soft wrapping); width is the widest line, height is `lines × lineHeight` |
| `.minContent` | the **widest unbreakable run**, from `CFStringTokenizer(kCFStringTokenizerUnitLineBreak)`, trailing whitespace trimmed |
| `.definite(w)` | typeset at `w`; width is the widest line, height is `lines × lineHeight` |

**The max-content row said "one line, full advance" until 2026-09-10, and that
was wrong for any string containing a hard line break (ruling TX-K).** The shaper
built one `CTLine` for the whole string, which lays every hard break's segments
side by side, while the definite-width branch's `CTTypesetterSuggestLineBreak`
breaks after each one. So max-content was the **sum** of a label's lines where
every definite width gave the widest: `"Ready\nSet\nGo"` at 13pt measured 75.004
against 37.565. The shaper now runs its typesetter loop at width `+infinity` when
no width is offered. For a break-free string that is byte-identical to the
whole-string line, measured over bidi, CJK, clusters and a 136,000-unit string. A
finite large width is not equivalent: that string soft-breaks at `1e4` and `1e5`.
The separators are CoreText's: U+000A, U+000D, CR LF, U+2028, U+2029, U+0085,
U+000B and U+000C. A trailing break opens no empty last line.

**The min-content recipe in this section's first two drafts was wrong, and it
would have shipped a §4.5 floor an order of magnitude too small.** They said
"typeset at a small positive width; the widest resulting line — the longest
unbreakable run". Measured: `CTTypesetterSuggestLineBreak` **breaks inside a word
it cannot fit**, so at any width below the longest word that recipe returns the
widest *character*. For `"a bb supercalifragilistic dd"` at 13pt it answers
**11.489** where CSS's min-content is **110.348** — the exact mid-word squeeze the
rule exists to prevent. Attaching `kCTLineBreakByWordWrapping` via a
`CTParagraphStyle` changes nothing: byte-identical line arrays at widths 0.5, 10
and 50.

The replacement is width-independent and does not typeset at all:
`CFStringTokenizer` with `kCFStringTokenizerUnitLineBreak` yields the run
boundaries directly. See §6.4's revision — this is the API that section says does
not exist.

**"A small positive width", not zero — and this section's first draft got that
reason wrong too.** It claimed `CTTypesetterSuggestLineBreak` at width 0 "may return
a zero-length break, which turns the min-content loop into a non-terminating one
— a hang, not a wrong answer." **Measured during execution: width 0 does not
hang.** The call returns ≥ 1 for every `start < length` at every width — 84,300
samples over 10 fonts, 52 strings (including break-sensitive, degenerate and
cluster-heavy leads) and 15 widths from −∞ to +∞, with zero non-positive returns.
The only input returning 0 is `start == length`, which the loop excludes.

**The live guard is the positive-width precondition, not the zero-length-break
one.** A non-positive width is an ill-formed request rather than a narrower line,
so `shape` preconditions on `width > 0`; deleting *that* reddens
`shapingAtAZeroWidthTraps` and nothing else, and deleting it makes the subprocess
exit **0** — independent confirmation there is no hang.

**The zero-length-break precondition is kept and is unreachable from any input.**
It is a contract assertion against a future CoreText: Apple documents no minimum
return, which is what makes the ≥ 1 behaviour a dependency worth asserting rather
than paranoia. It is doubly unreachable — `width > 0` is guaranteed above it, so
the non-positive widths are ones the call site cannot pass. **Deleting it reddens
nothing and does not hang. Do not write a test for it, and do not add an
injection seam to make one possible** — a seam would manufacture an input class
the API cannot produce and yield a test that passes because it tests the seam.

**A `.definite(0)` available extent is therefore the MEASURE FUNCTION's problem,
not the shaper's.** `precondition` is live in `-O`, so an unclamped zero width
terminates the app in release — and a flex item shrinking to zero main size is an
ordinary layout state, not a pathological one. **The measure function clamps to a
small positive width at its boundary**, with a test that a zero available extent
measures rather than traps.

**A `known` size wins over the measured one**, as `measureNode` already
guarantees: a `Text` with an explicit `.width(100)` is typeset at 100 and reports
100, whatever the content measures. That is the existing contract, not a new
rule — §5.5's `known` versus `available` distinction — and it needs a test here
only because `Text` is the first production leaf to exercise it.

**Line height is uniform in this milestone** — one font, one size per `Text` (§2)
— so total height is `lines × (ascent + descent + leading)`. Rich text makes that
per-line, and is out.

**This is what makes a long label behave.** With real min-content, §4.5's
automatic minimum floors a text item at its longest *word* rather than its whole
string, so a long label in a narrow `Row` wraps instead of overflowing. A
single-line implementation would have made min-content equal max-content and
floored at the full string — CSS-correct for `nowrap`, and indistinguishable from
a bug.

### 3.5 The atlas

Rasterization is `CTFontDrawGlyphs` into a CPU bitmap; a shelf packer places it;
the key is `(resolvedFontKey, glyphID, size, subpixelVariant, scaleFactor)` per
§6.1. Carried unchanged from §6.1 because each was decided with a reason:

- **Subpixel positioning** — a few fractional x-offsets, nearest wins. Without it
  spacing visibly wobbles during horizontal scroll.
- **Grayscale AA only** — macOS retired LCD subpixel AA.
- **Colour glyphs** route to the polychrome atlas and skip tinting.

**Eviction may run only between frames, never during scene construction, and
that is enforced rather than conventional.** Evicting a glyph the current frame's
scene still references yields a wrong glyph or a blank, on one frame,
intermittently — the hardest possible thing to reproduce. The enforcement is the
same shape as `LayoutTree.isLayingOut`: a flag set for the duration, with a
`precondition` on the eviction path.

## 4. Testing

### 4.1 What has a real oracle

| Layer | Verified against |
|---|---|
| Shaping, metrics, wrapping | **CoreText itself** — assert `ShapedText` matches what `CTLine`/`CTTypesetter` report. Headless |
| The measure function | The three sizing modes; and that a text leaf floors at its longest word, which is `min-content` reaching §4.5 |
| Shelf packer, atlas keys | Pure arithmetic. Headless, no GPU |
| Eviction ordering | The between-frames precondition, with a positive control (ruling CS-C: a non-trap assertion runs in a subprocess) |

### 4.2 What nothing can verify

**No test in this repo can see a wrong glyph, a wrong atlas coordinate, or a
blank run.** There is no WebKit oracle for text rendering as there is for layout,
and the ABI probe skips without a Metal device.

So M2 needs a **human look** as an exit criterion, exactly as M1 did — and the
failure modes are specific enough to name in advance:

- **wrong glyph** → atlas key collision (the `resolvedFontKey` trap)
- **fuzzy or wobbling text** → subpixel variant ignored, or scaleFactor missing
  from the key
- **blank runs, intermittent** → eviction during a frame

**"A wrong atlas coordinate" was too broad by one layer, measured in Task 7.**
The three failure modes above stand exactly as written — all three are *key*
failures, where the wrong bitmap is in the slot and the CPU and the GPU agree on
a wrong answer together. But the **renderer's sampling geometry** does have an
oracle the shader does not share: `GlyphAtlas.pixels`, produced entirely on the
CPU by CoreText and a shelf packer that never learns Metal exists. A sprite that
samples the wrong texels for a correctly packed slot produces a different byte,
and `aGlyphSpriteBlitsExactlyTheAtlasPixelsItPointsAt` asserts **every** byte of
two glyphs against it, exactly — white at full alpha over a cleared target makes
the premultiplied result's alpha byte the coverage byte with no arithmetic in
between. That test skips without a Metal device like the ABI probe, so §7's
"guarantees that lapse under configuration" covers it too. Nothing about the
human look changes: it is still the only check on all three modes named above.

### 4.3 Mutations that must redden

| Mutation | Must redden |
|---|---|
| the cache key drops `width` | a wrap test at two widths |
| the cache key drops `resolvedFontKey`'s variation coords | a two-font metrics test |
| `.minContent` returns the full advance | the longest-word floor test |
| a `.definite(0)` available extent | the zero-extent measure test — it must measure, not trap |
| `widestLine` returns the first line rather than the widest | the widest-line test |
| `lineHeight` drops a term | `metricsMatchCoreText`'s independent `CTFontGet*` oracle |
| the shelf packer overlaps two glyphs | a packing test |
| `.minContent` typesets at width 0 | the non-termination guard's test |
| `known.width` ignored in favour of the measured width | the explicit-width test |
| eviction runs mid-frame | the ordering precondition's exit test |

## 5. Exit criteria

- [ ] `swift test` completes with a **summary line** and the full count;
      `swift package clean && swift build` warning-free
- [ ] `MetalUILayout` still imports only `MetalUICore`
- [ ] `MetalUIText` imports no Metal
- [ ] `newLeaf` has a production caller; its CLAUDE.md inert row is **deleted**
- [ ] A text leaf's min-content is its longest word, pinned
- [ ] Text wraps at its offered width, verified against CoreText
- [ ] Every mutation in §4.3 measured under `--no-parallel` with its exact edit quoted
- [ ] Eviction cannot run during scene construction, pinned with a positive control
- [ ] **`swift run MetalUIDemo` shows wrapped text — verified by a human**, with
      the three failure modes in §4.2 looked for by name and the result recorded
      in CLAUDE.md
- [ ] No golden moved — this milestone adds a leaf measure function, and the
      corpus has no text fixtures

## 6. What this falsifies

- **`MeasureFunction` / `newLeaf`'s inert row leaves CLAUDE.md's table.** It is
  the row content sizing narrowed rather than removed.
- **`AlignItems.baseline`'s row loses its stated blocker.** It says baseline
  *"needs font metrics that arrive with the text system in M2."* After this the
  metrics exist — but the implementation is engine work in `crossAxisOffset`
  plus AL-6's `wrap-reverse` clause, which is not an offset flip. **The row must
  be updated to say the blocker is gone and the work is not done**, the same
  correction EP-6 needed when content sizing removed *its* reason. Leaving
  "needs M2" standing after M2 is the shape this project has corrected eight
  times.
- **§6.2's revision** (two pipelines by surface) is already committed; this
  milestone builds the atlas half.
