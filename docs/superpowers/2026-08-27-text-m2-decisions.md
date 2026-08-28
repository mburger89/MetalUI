# Text (M2) — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-27-metalui-text-m2.md`, in order. Each says what
was decided, why, and what it costs if wrong.

**Ruling IDs here are prefixed `TX-` and are LETTERED, `TX-A`…`TX-J`.** A bare
`TX-3` is therefore a typo, not a citation. `PF-`/`C-` belong to m1a, `FS-` to
flex sizing, `AL-` to alignment, `BM-` to the box model, `WR-` to wrapping,
`EP-` to the element pipeline, `CS-` to content sizing, `SI-` to structural
identity. `EP-2` and `EP-4` were never assigned and must not be reused. A bare
`F-n` is ambiguous across three documents — sweep for stray citations
**case-insensitively**, since a `Ruling F-3` survived two branches' greps for
lowercase `ruling`.

**Spec:** `docs/superpowers/specs/2026-08-27-text-m2-design.md`.
**Parent spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §5.5,
§6, §7.1.
**Ruling this milestone serves:** the design spec's §6 — one `Text` element the
layout engine measures and the renderer draws.

## During execution

| # | Ruling | Cost if wrong |
|---|---|---|
| TX-A | **The plan's test bodies are drafts against interfaces that may have moved; an implementer who finds one that does not compile fixes it and says so.** Three were already wrong before execution began (`tree.rootNode` does not exist; two symbols were missing from their task's Interfaces block), and **nine more** did not survive contact: `ResolvedFont` is not `Sendable`, so a file-scope `private let font = FontResolver.resolve(…)` does not compile under Swift 6 — carried into a *second* brief after being reported once; `NSAttributedString.Key.font` is AppKit's rather than CoreText's; `ShapedText: Sendable` was unhonourable; `noWrappedLineExceedsTheOfferedWidth` could not fail; a suggested wrap width of 20 put `"ccc"` (21.59 at 13pt) past the line so CoreText character-wrapped it and the widest line became the *middle* one; `twoGlyphsNeverOverlapInTheAtlas`' twenty bitmaps were all 12 tall, so a packer ignoring shelf height passed; all five briefed atlas tests passed against an atlas that returns coordinates and writes nothing; and `aGlyphUsedThisFrameSurvivesEviction` stayed green with all three generation-stamp sites removed. **The pattern is specific: prose in a brief was reliable, hand-derived numbers and hand-asserted API shapes were not.** The sharpened form: a defect an implementer reports is not fixed until it is removed from the *source* the next brief is generated from. | Production shaped to fit a mistaken test, which is the worst direction this can fail. Ten briefed test bodies would have shipped as coverage that could not fail. |
| TX-B | **No golden may move at any commit, and a moved one is a stop-and-report rather than a regenerate.** The corpus has no text fixtures and deliberately never will: a text golden would have to agree with WebKit on a *shaped* width, and WebKit shapes with its own font stack at its own hinting, so the golden would pin the browser's typography rather than this engine's rule. A moved golden therefore means something reached the engine's **container** path. Held at every commit: digest `fe511c49619e690adf4ba43d633054f2` over all 67 goldens is unchanged from the branch point through Task 8. | The one signal that this milestone stayed inside its own layer gets regenerated away, and an engine change ships inside a text milestone with nothing naming it. |
| TX-C | **The `opsz` pin is removed from M2, and §6.2 was wrong twice.** The first draft claimed the pin was free; the second claimed it delivered linear advances. Measured on §6.2's own 28-character string: unpinned ratio **1.8303** (reproducing the spec's own 1.8307), pinned **2.0653** — not 2.0. A second mechanism defeats it independently of the axis: CoreText hints advances in integer **design units**, not by ppem rounding, so a 0.125pt sweep moves at every step, converging on the unhinted value at **80pt** rather than 96. Helvetica and Menlo, having no hinting and no axes, are exactly linear, which isolates the cause. **The decisive measurement was one nobody had made:** unpinned `opsz` is `clamp(size, 17, 96)`, so at every M2 size (8–17pt) the axis is already at its minimum and constant — the pin bought **zero** linearity there while costing 11.7% at 8pt rising to 13.0% at 17pt (SF's *display* cut used at text size, exactly what the optical axis exists to avoid) and changing nothing at 28pt and above. It cost where M2 lives and paid nowhere M2 goes. Removal verified: the 13pt advance moves **157.76 → 180.25**. Linear advances are re-recorded as an **M5 canvas** requirement solved by a reference size carried in the font *matrix* (measured exactly 2.00000000; zoom drift 30.6px unpinned, 10.3px pinned, **0.0px** matrix), and why that is M5 is recorded too: the matrix makes `CTFontGetSize` report the reference size, so `FontKey`'s identity moves off `size` onto the matrix — a type the shaping cache, the atlas key and the renderer all key on. | Every M2 surface renders in the wrong optical cut of the system font, by up to 13%, to buy a property M2 does not use — and `FontKey`'s identity moves for M5's benefit a milestone before M5 can measure it. |
| TX-D | **§3.4's zero-width hang does not exist, and the live guard is a different one.** `CTTypesetterSuggestLineBreak` returns **≥ 1** for every `start < length` at every width: **84,300 samples**, 10 fonts × 52 strings × 15 widths from −∞ to +∞, including denormal-min, NaN, Zalgo clusters, regional indicators, noncharacters and lone combining marks. Zero non-positive returns. The only input returning 0 is `start == length`, which the loop excludes. The guard that actually fires is the **positive-width** precondition: deleting it reddens `shapingAtAZeroWidthTraps` and makes the subprocess **exit 0**, which is independent proof there is no hang. The zero-length-break precondition is **doubly unreachable** (`width > 0` is guaranteed above it) and is kept as a contract assertion because **Apple documents no minimum return** — with no test and no injection seam, since a seam would manufacture an input class the API cannot produce and yield a test that passes by testing the seam. **Do not re-bank "mutation 1a proves the guard unnecessary"**: it proves the guard is *unreachable*, which is a different claim. | A precondition is deleted on the strength of "the mutation reddened nothing", and a future CoreText that returns 0 turns a wrong answer into a silent infinite loop. In the other direction: a seam is added and the suite grows a test of itself. |
| TX-E | **A `.definite(0)` available extent is the MEASURE FUNCTION's obligation, and it is a live release crash rather than a note.** `precondition` is active in `-O`, and a flex item shrinking to zero main size is an ordinary layout state — §9.7 hands `.definite(0)` to any item on an over-full line whose share runs out — so an unclamped zero width terminates the app in release. The clamp lives at the measure function's boundary (`smallestWrapWidth = 0.5` in `Text.swift`), where "as narrow as you can" is a real request, not in the shaper, where it would silently answer a different question than the one asked. The value is arbitrary within `(0, one character wide)`: every width below the narrowest glyph gives the same answer, measured at 0.001, 0.5, 1 and 5. Pinned by a test that a zero extent **measures rather than traps**. | The first user to drag a window narrow enough to squeeze a `Text` to zero gets a process termination in a release build, from a `precondition` written to describe an ill-formed *request*. |
| TX-F | **§3.4's min-content recipe was wrong and would have shipped a §4.5 floor an order of magnitude too small.** The recipe said "typeset at a small positive width, take the widest line". `CTTypesetterSuggestLineBreak` breaks **inside** a word it cannot fit, so that returns the widest *character*: **11.489** against CSS's **110.348** for `"a bb supercalifragilistic dd"` at 13pt — the exact mid-word squeeze §4.5's automatic minimum exists to prevent. `kCTLineBreakByWordWrapping` via a `CTParagraphStyle` changes nothing: byte-identical line arrays at widths 0.5, 10 and 50. Replaced by `CFStringTokenizer(kCFStringTokenizerUnitLineBreak)`, which is width-independent and typesets nothing. **A measurement distinction worth keeping:** 19.894 vs 20.084 for `"per"` is not an error but in-paragraph line advance versus standalone shape — 0.19 of kerning context — and it matters because min-content shapes each run **standalone**, so its answer is the width a run needs on a line of its own, which is the right question for §4.5. | Every long label in a narrow container squeezes to one character per line instead of wrapping at word boundaries — CSS-incorrect, and indistinguishable from a bug in the flex engine rather than in the shaper. |
| TX-G | **M6's hand-rolled UAX #14 subset is demoted from planned work to a contingency, and M6 should start by trying to delete it.** §6.4's "CoreText exposes no width-independent line-break-opportunity API" is true of CoreText and materially misleading: CoreFoundation has one, and that sentence was the sole justification for the subset. Measured against §6.4's own class list, `CFStringTokenizer` covers every class enumerated **plus Thai `SA`**, which the subset explicitly excludes; its ranges partition the string contiguously; it costs 93.6 ns/char and is cacheable *because* it is width-independent. | A milestone's worth of Unicode work is written to replace a system API that already does the job better, and the replacement inherits a correctness surface (`SA`, tailoring, future Unicode versions) the system API maintains for free. |
| TX-H | **The max-content/fit-content contradiction is an INLINE-vs-BLOCK axis distinction, not container-vs-leaf.** CSS sizes an `auto` inline axis by shrink-to-fit and an `auto` block axis by content height. In a **row** the cross axis *is* the block axis (max-content correct); in a **column** it is the inline axis (fit-content correct). `ownCross` was axis-agnostic and therefore right for one and wrong for the other. Four WebKit measurements confirm. **Content sizing's defending comment could not support its own conclusion**: it inferred "max-content, not fit-content" from a *rigid* box, where min-content == max-content, so fit-content floors at min-content and overflows identically — sound measurement, invalid inference, and "a fixture too uniform to distinguish the thing it claims to pin" living in a justification rather than in a test. Implemented in an inserted task: `ownCross` computes `min(max(min-content, available), max-content)` on `!isRow` and stays max-content on a row. `Column { Text(…) }`, which laid out **270 wide at `x = -75`** in a 120-wide column, is now 120 wide at `x = 0` and agrees with WebKit. Ruling CS-K's row in the content-sizing decisions doc carries a superseded note. | `Column { Text }` — the single most ordinary thing anyone will write on top of this milestone — lays a label out at its whole unwrapped width, hanging off both sides of its container, and EP-8's centring default makes the overflow symmetric rather than merely rightward. |
| TX-I | **"Reddens exactly the pins written for it and nothing else" is NOT a sufficient acceptance criterion, and the plan stated it as one.** Three *wrong* implementations of TX-H all satisfy it — one that stretches instead of fitting, one that ignores cross margins, one that gets the indefinite case wrong — because where `min-content ≤ available ≤ max-content` fit-content and stretch produce the **identical number**, so the existing pins could not discriminate. Both needed a *new* discriminator: a 30-wide column, and a 20pt text column. Same shape as the "no golden moved" caveat: **an acceptance criterion satisfied by the right answer and by three wrong ones is not an acceptance criterion.** It then materialised against its own author twice more — `aGlyphUsedThisFrameSurvivesEviction` is green with eviction removed entirely (a used glyph surviving is trivially true when nothing is evicted), and the atlas subpixel test compared the only equal-sized variant pair, straddling the surviving boundary. | Every mutation measurement on the branch reads as coverage when it is only consistency, and a fix ships that satisfies its acceptance criteria and is wrong. |
| TX-J | **The plan has a hole where the emitter should be, and it would have made the milestone's exit criterion meaningless.** `grep -rn "GlyphAtlas(\|\.upload(" Sources/` returned **nothing** after Task 7: Task 7's file list is renderer-only, Task 4's `Text.paint` emitted a background and no glyphs, and Task 8 touches only the demo and CLAUDE.md. **Every piece was built and nothing connected them**, so Task 8's human look — the one check no test can perform — would have shown a window with no text in it and passed. An emitter task was inserted before Task 8; the same grep now returns three lines (the `Frame` default argument, the `Window`'s stored atlas, `renderer.upload(glyphAtlas)` before `encode`). | The milestone ships with a complete, tested, entirely unreachable text pipeline, and the exit criterion that exists precisely to catch what tests cannot certifies it. |

## Two findings that are not rulings but must not be lost

### A mutation that reddens nothing is a broken instrument or the finding — and telling which is the work

Three instances on this branch, and they split two ways.

**Broken instrument, twice.** In Swift, replacing a stored property with a
**computed** one over surviving storage does not mutate synthesized
`Hashable`/`Equatable` at all — the first attempt at dropping `size` from
`FontKey` reddened nothing for that reason and was correctly reported as an
instrument failure rather than banked as a coverage gap. And
`glyphs.sort { $0.order < $1.order }` is not an unstable sort: Swift's sort is
already recorded as stable at every measured size in this repo, so "make it
unstable" mutates nothing. Reversing the tiebreaker, and deleting the sort, each
redden `finalizeSortsGlyphsStablyByOrder` alone.

**The finding, three times.** Deleting `!isRow` — the operator carrying the
whole of TX-H's axis distinction — left **all 395 tests green**; CS-K's own
measurement of the row case had been recorded in a comment and never pinned, and
`flex_row_block_axis_max_content` closes it with a **wrapping** child, because a
rigid box cannot distinguish the two rules. Turning font subpixel *quantization*
back on left the whole suite green at 412: it collapses four variants onto two
positions (centroid steps 0.258/0.267/0.250 → 0.000/0.525/0.000) and the test
compared the only equal-sized pair. And storing `left: 0, top: 0` in the atlas
while still *returning* the real bearings from the miss path left all 442 green,
because every test in the repo drew each glyph exactly once against a fresh
atlas — **the cache-hit path the `PackedGlyph` seam exists for had no coverage at
all**. On screen that last one is text correct on the frame it appears and
displaced by a pixel or two on every frame after: precisely the intermittent
class §4.2 says nothing here can see. `theSecondFrameOfTheSameTextPlacesItsSpritesIdentically`
closes it and the mutation now reddens exactly it, 1 issue out of 443.

### A name that asserts coverage which never existed is worse than an absent test

`aTextPaintsItsBackgroundAndNoGlyphsYet` predates `Scene.glyphs`, so its body
only ever counted rects — and it stayed green through the entire commit that
made a `Text` emit forty-odd sprites. An audit of "what pins text drawing
nothing" would have found it, read the name, and stopped. Rewritten in place as
`aTextPaintsItsBackgroundAndItsGlyphs`, with the count taken from CoreText's own
line and the history kept in its doc comment.

## The design decisions this milestone rests on

Settled in the design rather than during execution, but each load-bearing enough
that a future change will want the reasoning.

### Nothing may be keyed on a font family or PostScript name

`FontKey` identifies the *resolved* `CTFont` — variation coordinates and matrix
included. §6.1 measured the trap: requesting `"SFMono-Regular"` by name on the
target machine returns a font whose PostScript name is `Helvetica`. A name-keyed
shaping cache or atlas serves one font's glyphs for another's, and **that is the
first of the three failure modes §4.2 says nothing in this repo can see** — the
CPU and the GPU agree on a wrong answer together, so every byte-exact test
passes.

### The shaping cache is keyed on CONTENT, not on element identity

Two elements showing the same string shape once. It is deliberately not the
`StateTable`: §4.3 is for state that *cannot* be recomputed from the element
values, and a shaped line can be. Putting it there would also key on identity
and shape the same string twice. **Why a cache at all is measured rather than
assumed:** §4.5's automatic minimum probes every item and an `auto`-cross item
probes again, so a leaf's `MeasureFunction` is called up to three times per
layout, at up to three distinct widths. `theCacheIsActuallyConsulted` is the only
test that can see it working — a store that never stores leaves the engine
correct and typesets three times per node per frame.

### The concurrency shape is settled by the compiler, not by argument

`@MainActor final class ShapingCache`, owned by `Window` beside the
`StateTable`, keyed on a `Sendable` struct, vending **non-`Sendable`**
`ShapedText` that never leaves the main actor. `MeasureFunction` is `@Sendable`
and non-isolated, so the closure may capture the cache (a global-actor class is
implicitly `Sendable`) but **not** a `ResolvedFont` — that lives on the cache and
is looked up by `FontKey` inside the isolated block. `MainActor.assumeIsolated`
requires `T: Sendable`, so the closure must reduce to `SizeD` *inside* the block.
No `@unchecked Sendable`, no lock; nothing needs to cross.

**That leaves one latent release trap with no test, and it is recorded in
CLAUDE.md rather than guarded.** `assumeIsolated` is sound only because
`computeLayout` runs synchronously inside `Frame.computeRootLayout`, which is
`@MainActor`. Drive layout over a tree holding a text leaf from any other
executor and the process terminates. Nothing here can notice: every existing
off-main-actor layout builds its own leafless tree, and a test that got this
wrong would crash the run rather than redden it.

### Eviction is guarded, uncalled, and a caller would make things worse

The between-frames precondition is live and pinned two ways
(`evictingDuringFrameConstructionTraps`, `beginningAFrameTwiceInARowTraps`), and
`Frame.render` brackets the paint phase with `beginFrame`/`endFrame`. What is
absent is any call to `evictUnusedSince`, and **the reason is a mechanism rather
than a milestone**: the shelf packer never revisits a closed shelf, so evicting a
key frees a dictionary entry and **strands its pixels**, and the next frame that
wants that glyph packs a second copy further down. Calling eviction every frame
would make the atlas fill *faster*. The atlas is therefore grow-only and
`Frame.draw` silently drops a glyph that will not fit; what unblocks it is a
repacker or a whole-atlas rebuild, not a call site. One story, one CLAUDE.md row.

## What this milestone falsified, and what it did not

- **`MeasureFunction` / `newLeaf`'s inert row is deleted.** `grep -rn "newLeaf"
  Sources/` returns seven lines and **one of them is a call**:
  `Sources/MetalUI/Frame.swift:154`, reached by `Text.requestLayout` →
  `LayoutPass.requestLeaf` → `Frame.requestLeaf`. Pinned two ways — replacing
  `requestLeaf` with `newNode` reddens 7 tests, and making `requestNode` attach a
  trivial measure function reddens `aTextLeafCarriesAMeasureFunctionWhereABoxDoesNot`
  **alone** out of 389, so the `Box` half is not incidental.
- **`AlignItems.baseline`'s stated blocker is gone and the work is not done.**
  The metrics exist (`FontMetrics`, pinned against `CTFontGetAscent`/`Descent`/
  `Leading` by `metricsMatchCoreText`). What is missing is engine work, now named
  as three mechanisms at `crossAxisOffset` rather than as a milestone: a
  `MeasureFunction` returns a `SizeD` and cannot carry a baseline;
  `crossAxisOffset`'s `(itemCross, lineCross)` signature is the wrong shape for a
  per-*line* common baseline; and AL-6's `wrap-reverse` clause (§8.3 swaps first-
  and last-baseline alignment) is not an offset flip.
- **The colour-glyph gap outlives M2 and is wrong output rather than an absent
  feature.** §6.1 routes emoji to a *polychrome* atlas that skips tinting; there
  is none in M2, and `GlyphRaster.rasterize` does not detect one either — so
  `CTFontDrawGlyphs` renders an emoji into the `DeviceGray` context as a
  luminance silhouette, it packs into the R8 atlas like any other glyph, and
  `glyph_fragment` multiplies it by the text colour. `Text("hi 🎉")` paints a flat
  blob in the text's colour. It does not trap and it is not blank, which is
  exactly why it is written down: nothing here can see it. The fix is a second
  atlas and a second draw path, not a branch in the rasterizer.
- **Divergence 6 was fixed (TX-H); divergence 7 was renumbered to 6 and stays.**
  §9.4 step 7 takes an item's cross size from its *hypothetical* rather than its
  used main size, so `Row { Text(long) }` is one line tall while §4.5 shrinks it
  to three lines' worth of width. Measured end to end once the emitter landed: a
  120×600 frame gives the text a box of **120 × 16 at y = 292** while glyphs run
  from y = 294 to **y = 339**. **Not clamped in paint** — the box is what is
  wrong, the glyphs are where the box says, and a clamp would move the defect
  somewhere nothing can see it.
- **`rootFontSize` did not become settable**, though a comment on it predicted
  M2 would do that. `Text` carries its own `fontSize` in points and never
  consults it; nothing in `Sources/` or `Tests/` passes `rootFontSize:` to a
  `Frame`. The two are unrelated quantities sharing a word — CSS's *document*
  root font size against M2's *per-element* size — and wiring one to the other
  needs a root-level text style no element has.

## Deliberately not done

- **The shape-once/wrap-by-advances fast path** (§6.3) and the **hand-rolled
  UAX #14 subset** (§6.4). Optimisations over a working implementation; M6, and
  TX-G says the second should begin by trying to delete itself.
- **MSDF glyphs.** Decided for the node canvas and sequenced with it at M5
  (§6.2, revised 2026-08-27). No canvas exists before then, so MSDF quality and
  atlas thrash cannot be measured.
- **Selection, caret, hit-testing, IME** (§6.6). M6.
- **Baseline alignment.** This milestone removes its blocker without
  implementing it.
- **Rich text.** One font, one size, one colour per `Text` — which is what lets
  height be `lines × lineHeight` with a single line height.
- **Colour emoji.** Recorded as a gap, not built.
- **A leaf's box model.** `Text(…).padding(Pixels(8))` changes no size and moves
  no glyph: `measureNode` returns a leaf's measure result unchanged where it adds
  a container's `edges` back on, and `contentBox` only ever runs on a node with
  children. Consistent, and consistently wrong against CSS. Recorded as a
  CLAUDE.md row because the modifiers are public and live on a `Box`.
- **Ruling FS-3's specified size suggestion.** Untouched; still divergence 5.

## A process note worth keeping

**Shape 11 applies to the coordinator as much as to the implementer.** A
mutation run whose build failed produced **no summary line**, and the absence
was nearly read as a pass. The rule that caught it is the one this branch put in
the plan after Task 1: *the evidence of a failing test is an `error:` line or a
non-zero issue count, never the absence of a summary line.* Task 1 had the
converse failure written into its step order — "run the test, confirm it fails"
before the target existed yields `Test run with 0 tests … passed`, a green run
that compiled nothing.
