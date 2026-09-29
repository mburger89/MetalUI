# Text semantics decisions (plan task 11, part 1)

Rulings for [`specs/2026-09-28-text-semantics-design.md`](specs/2026-09-28-text-semantics-design.md),
on `feat/text-semantics` from `169d166` (part 1, `TE-A`…`TE-AB`), and for
[`specs/2026-09-28-shapes-and-rendering-design.md`](specs/2026-09-28-shapes-and-rendering-design.md),
on `feat/shapes-and-rendering` from `ff2ae92` (part 2, `TE-AC` onward). Ids
are **lettered**, `TE-A`…`TE-AU`; next unused is **`TE-AV`**. A bare `TE-3` is
a typo, not a citation. **A round that appends a ruling moves this line in the
same commit.**

**Part 2 status, 2026-09-29: DESIGNED, critic round applied** (`TE-AC`…`TE-AQ`);
**lane 1 (the renderer) landed** (`TE-AR`); **lane 2 (shapes, fill/stroke,
clipping, backgrounds in a shape) landed** (`TE-AS`, fix round `TE-AT`);
**lane 3 (`Image`, `aspectRatio(nil)`, the `UnitPoint` grid anchor) landed**
(`TE-AU`).

**Status, 2026-09-28: LANDED — lanes 1–3 and their fix rounds (`TE-T`…`TE-AA`), the Record phase's branch check (`TE-AB`); designed with the critic round applied (`TE-Q`…`TE-S`).** Plan task 11 is split in two by the workflow
that runs it: **part 1** (this doc) is the text half of the task's first
sentence — foreground style, font metrics, line limit, truncation, multiline
alignment, baseline alignment and dynamic type response — plus every item the
records and decisions docs address to task 11 that is about text (`TE-A`).
**Part 2** (the next run) is the second sentence — shapes, images,
fills/strokes, overlays and clipping — plus the items `TE-O` re-owns to it. The
plan's task 11 box stays **unticked** after part 1.

**Evidence, cited below by arm id:**

- `docs/probes/swiftui-text-semantics.swift` (**new**, this design): arms G0
  (controls), F1–F8 (fonts, inheritance, dynamic type, `controlSize`), M1–M4
  (metrics, the integer answer), L1–L6 (line limit), T1–T6 (truncation, by
  rendering), A1–A6 (multiline alignment), B1–B2 (baselines), S1–S2 (default
  spacing), C0–C9 (foreground), X1–X13 (follow-ups added in the same session:
  bold, custom weights, baseline combination, spacing, truncation against
  CoreText's kept strings, height-driven line counts, grid baselines, CoreText's
  bold trait, a 21-size line-height sweep). Headless (no window is ordered
  front); compiled form run twice and interpreted form once, all
  byte-identical, 294 lines, screen locked.
- `docs/probes/swiftui-environment-control-state.swift` Z2/Z3 (task 9), S4
  (divergence 77), re-read, not re-run: F8 reproduces Z2's numbers.
- `docs/probes/swiftui-engine-replacement-stage2.swift` group Y (divergence
  60), re-read: M1 extends it to scales 1, 2 and 3.
- Critic round (`TE-Q`…`TE-S`): `docs/probes/swiftui-controlsize-text-render.swift`
  (**new**, arms R0–R2: which instrument sees `controlSize`) and
  `docs/probes/swiftui-text-in-stacks.swift` (**new**, arms K0–K4: a wrapping
  text beside a sibling in a tight stack), each compiled twice and interpreted
  once, byte-identical; `swiftui-text-semantics.swift` re-run whole by the
  critic, **all 294 lines byte-identical** to its header.

---

## TE-A — part 1's scope: every item addressed to task 11, and three lanes

**The collection** (grep for `task 11` over `docs/superpowers/*.md`,
`docs/superpowers/specs/`, `docs/record/`, `Sources/` and `Tests/`,
2026-09-28, filtered to **plan** task 11 — the 2026-08 "Task 11"s of the input,
sizing and m0 plans and their decisions docs, `AppKitPlatform.swift:146` and
`KeymapTests.swift:193` are m-milestone tasks):

| item | source | disposition |
|---|---|---|
| foreground style | plan text | **built**, `TE-D` |
| font metrics (`Font`, weights, designs, text styles) | plan text | **built**, `TE-B`, `TE-C` |
| line limit | plan text | **built**, `TE-H` |
| truncation | plan text | **built**, `TE-I`; divergence **87** added |
| multiline alignment | plan text | **built**, `TE-J` |
| baseline alignment (`firstTextBaseline`/`lastTextBaseline`) | plan text; `CN-H` table (containers doc), record §17 | **built**, `TE-K`; divergence **88** added (a `GridRow`'s) |
| legacy `alignItems.baseline`/`alignSelf.baseline`, owner `"plan task 11"` | `LR-FO`, `LayoutAuthority.swift:79–91`, `Style.swift:40`, `LegacyLowering.swift:922`, record §21, §49 row 32 | **lowered / refused by name**, `TE-L` |
| dynamic type response | plan text; record §05 (`dynamicTypeSize` carried) | **SwiftUI's macOS answer is none** (F7); unchanged and pinned, `TE-E` |
| `controlSize` → a `Text`'s default font, `TextField`/`TextEditor` | divergence 76; `EV-AC`, `EV-AE`, `DD-AB` item 2; `EnvironmentValues.swift:168`, `Button.swift:32`, record §05, §56 | **built**, `TE-F`; divergence 76 **amended again**, kept for the controls' chrome |
| divergence 77 (layout rounds to whole points) | `EV-AD`, record §04, §56 | **kept**, owner none, `TE-G` |
| divergence 60 (SwiftUI's integer text answer) | `LR-AY` item 4, record §21, §23 | **kept, now pinned**, owner none, `TE-G` |
| divergence 51 and `GR-O` 5 (text-edge default spacing) | `CN-H`, `GR-O`, containers/grids docs, record §17, §22 | **kept**, owner none, `TE-M` |
| W2 (a long label at priority 1 in a stack) | `LR-AM`, `LR-AP`, record §21 | **kept**, owner none, `TE-M` |
| `UnitPoint` in `gridCellAnchor` (`GR-O` 4, divergence 64) | `GR-G`, `DD-P` item 4, `UnitPoint.swift:11`, `Grid.swift:331`, `GridCompileGuards.swift:123` | **re-owned to part 2**, `TE-O` |
| `.cornerRadius` clipping (divergence 47) | `OM-G`, outer-modifiers doc `:337`, `:677`, `Box.swift:1339`, `OuterModifierMatrixTests.swift:1020` | **part 2** (clipping), `TE-O` |
| an `appearance`/`colorScheme` value; the theme before paint | `EV-G` table (environment doc `:1146`), record §11 | **part 2** (rendering-facing), `TE-O` |
| colour glyphs (record §05 row) | record §05 | **part 2** (rendering-facing), `TE-O` |
| an `onTap` control invisible to VoiceOver | `AB-` doc `:1408` | **plan task 12** (accessibility), `TE-O` |

**Three lanes**, run in order 1, 2, 3 (spec §8 names every file; **amended by
`TE-S` item 1**, which moved font selection from lane 1 to lane 2): **1** the
`TextSystem` seam's layout options and metrics on both text systems (line
limit, truncation and alignment in measurement and placement, `fontMetrics`,
each oracle-checked); **2** font selection on both systems (`FontDescriptor`,
weights, italic, designs) and the kernel's baselines and the legacy `baseline`
fields (synthetic leaves only); **3** the element surface (`Font`, the
environment values and modifiers, `Text`/`ProposalText`/`TextField`/
`TextEditor`), which consumes both. Lanes 1 and 2 share three seam files
(`TextSystem.swift`, `CoreTextTextSystem.swift`, `PortableTextSystem.swift`),
which is safe only because the lanes run one at a time, in order; every other
source file is one lane's.

**Cost if wrong.** An item missed here is found by part 2's collection or plan
task 15's inventory; each row names its source so the grep can be re-run.

---

## TE-B — `Font`: SwiftUI's spelling over a descriptor; the environment carries it

**Evidence.** F1 (text styles are fixed faces on macOS), F2 (`.system(size:weight:)`
is `NSFont.systemFont(ofSize:weight:)` at all nine weights), F3 (designs),
F4/X2b (italic is the italic face), F5 (custom is `CTFontCreateWithName`,
substitution included), F5b/F5c (`fixedSize:`/`relativeTo:` measure as `size:`),
X2/X2d (a custom family's weight selects its nearest face), F2h/F4b (no
synthesis), F6a–F6e (inheritance), X1/X1b/F2e/X12 (`Text.bold()`), X1c
(`Font.bold()`), F2c/F2f/F6d (`fontWeight`).

**The ruling.**

1. `public struct Font: Hashable, Sendable` in `MetalUI`, with
   `static func system(size:weight:design:)`, `static func system(_ style:
   Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil)`, the
   eleven text-style statics (`largeTitle` … `caption2`), `static func
   custom(_ name: String, size:)`, `custom(_:fixedSize:)`,
   `custom(_:size:relativeTo:)`, and `func weight(_:)`, `func bold()`
   (= `weight(.bold)`, X1c), `func italic()`. Nested `Font.Weight` (the nine
   SwiftUI weights, carrying CoreText's weight-trait value: −0.8, −0.6, −0.4,
   0, 0.23, 0.3, 0.4, 0.56, 0.62), `Font.Design` (`default`, `serif`,
   `rounded`, `monospaced`) and `Font.TextStyle` (eleven cases). A text style
   resolves to F1's macOS table on **both** text systems (a pure function in
   `MetalUI`, not a platform query).
2. **The environment carries it**: `EnvironmentValues.font: Font?` (public,
   SwiftUI's key), written by `ElementGroup.font(_:)`; nearest writer wins
   (F6e). `Text.font(_:)` and `ProposalText.font(_:)` set the element's own,
   which wins over the environment (F6b). **`Text.font(nil)` is the default
   font, not the inherited one** (F6c): the element stores a three-state
   request (inherit / explicit default / explicit font).
3. `fontWeight(_:)` and `italic(_:)` exist on `Text`, `ProposalText` and
   `ElementGroup` (the last through two internal environment values), and
   apply over whichever font the text resolves — its own, the environment's or
   the default (F6d, F2f). A `nil` weight removes the override.
4. **`Text.bold()` and the `ElementGroup.bold()` modifier are NOT offered.**
   SwiftUI's draws semibold on the default font, heavy on `.headline` and
   nothing on `.light` (X1, F2e, X1b) — neither weight `.bold` (X1c, F2c) nor
   CoreText's bold trait (X12: Bold on regular). No rule fits three arms, and a
   `bold()` that means `.fontWeight(.bold)` would silently disagree on the most
   common font. `Font.bold()` (X1c's exact answer) and `.fontWeight(.bold)`
   are the spellings. Additive later, owner none.
5. **Kept, not deprecated**: `Text.font(family:size:)` (and `ProposalText`'s,
   `TextField`'s, `TextEditor`'s) now means `.custom(family, size:)` for a
   family and `.system(size:)` for `nil` — an explicit font, as it always was.
   The public stored `fontFamily`/`fontSize` become **computed** over the
   request: reading gives the explicit font's family/size (13 and `nil` when
   inheriting or default, exactly what an unconfigured `Text` read before);
   writing sets an explicit `.custom`/`.system` font. Every existing caller
   draws what it drew (spec §7: 0 px).
6. **Not built, additive, owner none**: `fontDesign(_:)`/`fontWidth(_:)`/
   `monospacedDigit()`/`Font.leading(_:)`/`.lineSpacing(_:)` (M4 measured it:
   +4 between lines), `Font(_ ctFont:)`, `Text.bold()` (item 4).

**Cost if wrong.** A caller porting `Text("x").bold()` gets a compile error
naming the missing method rather than a different weight. If the text-style
table is wrong for another macOS version, F1 re-run gives the new sizes; it
is one table.

---

## TE-C — the seam gains a descriptor, metrics and layout options, on both systems

**Evidence.** F1–F5, X2, X2d, F2h, F4b (font selection); B1, X13 (ascent,
baselines); T1–T6, X5–X8 (truncation is CoreText's `CTLineCreateTruncatedLine`);
A1–A6 (alignment inside the box). `TS-A`: text measures and draws only through
`TextSystem`.

**The ruling.** Three additions to `MetalUITextSystem`, each implemented by
`CoreTextTextSystem` and `PortableTextSystem` and each checked equal by an
oracle or a sprite comparison (spec §4):

1. **`FontDescriptor`** (`family: String?`, `size`, `weight: Double?`,
   `italic: Bool`, `design: FontDesign`) and `resolveFont(_: FontDescriptor)
   -> FontKey`. `resolveFont(family:size:)` stays, as a protocol extension
   forwarding to it. CoreText: `family == nil` → the system face at `weight`
   and `design` (`NSFont.systemFont(ofSize:weight:)`'s answer, F2; the design
   descriptor, F3); a family → `CTFontCreateWithName`, then, when `weight` is
   set, the family's face nearest that weight (X2, X2d); `italic` → the italic
   symbolic trait, a no-op when the family has no italic face (F4, X2b, F4b).
   **Portable**: each registered face gains a weight (its OS/2 `usWeightClass`
   mapped onto `Font.Weight`'s values: 100 → −0.8 … 900 → 0.62) and an italic
   flag, read without loading bytes for a lazy face (`SF-B`); `weight` picks
   the nearest face **of the resolved face's family**, `italic` an italic face
   of that family, neither synthesising (F2h/F4b); `design` other than
   `.default` resolves a family registered for that design
   (`PortableFontResolver.register(design:family:)`) or the default face.
   **The oracle** (`FontSelectionOracleTests`, macOS) registers every face of
   several installed multi-weight families (Helvetica Neue, Avenir Next and
   the other `.ttc`s the test finds) with a portable resolver and requires the
   portable choice to equal CoreText's PostScript name for every (family,
   weight, italic) — its tie rule is whatever makes it agree, measured, not
   chosen (`LB-D`'s precedent).
2. **`fontMetrics(_:) -> TextFontMetrics`** (`ascent`, `descent`, `leading`,
   `lineHeight`) — `FontMetrics`/`PortableFontMetrics`' values, already equal
   by `PT-`'s oracle; the element derives baselines from it (`TE-G`).
3. (**Amended by `TE-T`**: with a hard break in the rest, the last kept line
   is the rest's first paragraph, not the whole rest; narrower than the token,
   the longest prefix that fits.) **`TextLayoutOptions`** (`maxLines: Int?`, `truncation: TextTruncation`
   (`.tail`/`.head`/`.middle`), `alignment: TextLineAlignment`
   (`.leading`/`.center`/`.trailing`)) as a new parameter of `measure`,
   `placeGlyphs` and `lineRanges`; the old spellings stay as extensions passing
   `.init()` (no limit, tail, leading), so `TextField`/`TextEditor` and every
   test caller are untouched. With `maxLines == n` and more lines than `n`,
   lines `0..<n−1` are kept and the rest of the string from line `n−1`'s start
   is truncated as **one line** at the wrap width in the given mode (X8, 0 px
   for all three modes), `…` (U+2026) as the token, shaped in the text's **resolved** font — the
request's face, not whichever fallback face drew the truncated run — with
that font's own fallback when the face lacks U+2026 (T6; on the portable path
the token is shaped through `shapeCascading`, `FB-A`, never `HarfBuzzShaper`
directly),
   trailing whitespace before a tail token dropped (X6) — CoreText's
   `CTLineCreateTruncatedLine` on the Apple path, and on the portable path a
   `PortableText` truncation that must equal it over the
   `TruncationOracleTests` corpus (widths, kept string, glyphs placed). **If a
   corpus case cannot be matched** after the lane has measured the rule (as
   `LB-D` measured its four), the lane stops and a new `TE-` ruling names the
   case, the two answers and a pin of each (`LB-M`'s precedent for Thai) —
   never a silent exclusion from the corpus, and never for Latin tail, the
   default mode, which must match. At an
   unspecified width the kept lines are simply cut (L4: no ellipsis without a
   width to fit). `measure` answers the kept lines' widest width and `kept ×
   lineHeight`. `alignment` moves each placed line by
   `(box − lineWidth) × factor`, the box being the wrap width, or the widest
   line when unwrapped (A1, A2, A5).

**Cost if wrong.** A portable answer that differs from CoreText's breaks
`TextSystemSeamTests`' sprite equality on macOS and `Tests/PortableTests`' byte
pins on Linux and Windows — the same two nets every portable text feature has
had. A system that implements only the forwarding extension loses nothing but
the new behaviour.

---

## TE-D — foreground style is an environment value and a token

**Evidence.** C1–C8: a container's `.foregroundStyle`/`.foregroundColor`
reaches a `Text` (C2, C3), a `Text`'s own wins (C4, C5), nearest writer (C6);
C7 (`foregroundColor(nil)` on a `Text` is the default); C8 (`.secondary`); C9
(a shape's fill reads it — part 2).

**The ruling.** `foregroundStyle(_ token: ColorToken)` on `Text`,
`ProposalText` and `ElementGroup`; `ElementGroup.foregroundColor(_:)` as its
alias (SwiftUI's older spelling); `Text.foregroundColor(_:)` unchanged. The
environment value is **internal** (`EnvironmentValues.foregroundStyle:
ColorToken?`, SwiftUI has no public key). A text's colour is its own token,
else the environment's, else `.textPrimary`, resolved against the paint
theme. **Tokens, not `ShapeStyle`** (§7.9's reason: a literal colour would not
follow the theme): hierarchical styles (`.secondary`), gradients and
`Text.foregroundColor(nil)` are not built — additive, owner none; the shape
half (C9) is part 2's. `TextField`/`TextEditor` do not read it (their text
colour is their own chrome, unchanged).

**Cost if wrong.** A caller wanting `.secondary` writes `.textSecondary`-style
tokens instead; nothing silently mis-draws.

---

## TE-E — dynamic type: SwiftUI's macOS answer is no response, and MetalUI keeps it

**Evidence.** F7: under `.xSmall`, `.large`, `.xxxLarge` and
`.accessibility5`, `.body`, `.title`, the default font, `.system(size: 13)`
and `.custom(_:size:relativeTo: .body)` all measure the same. Probe G
(environment track) read the same for `.body`.

**The ruling.** No font scales with `dynamicTypeSize`, on either text system
(Linux and Windows have no SwiftUI answer; the macOS one is taken).
`dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority` stays, and a
new test extends it to a text style and `relativeTo:` (spec 3.9). The record
§05 row changes from "carried, no consumer" to "no consumer, which is SwiftUI's
macOS answer" (Record phase).

**Cost if wrong.** If a later macOS scales text styles, F7 re-run shows it and
the text-style table (`TE-B` item 1) gains a size column.

---

## TE-F — `controlSize` reaches the default font, and through it `TextField` and `Button`'s label

**Evidence.** F8/Z2: the default font is 9 pt at `.mini`, 11 pt at `.small`,
13 pt at `.regular`/`.large`/`.extraLarge` — by **layout**, uniquely (R2);
F8's `equals=.system(size: 13)` field in every row is `ImageRenderer`'s blind
spot, not a drawn 13 pt (`TE-Q`); an explicit font (`.body`,
`.caption`) does not move; an environment font wins (F8h). F8/Z3: a
`TextField`'s height follows its font (32 at `.system(20)` whatever the size),
its default font follows the size.

**The ruling.**

1. The **default font** — what a `Text`, `ProposalText`, `TextField` or
   `TextEditor` resolves when neither it nor the environment names a font — is
   `.system(size: 9 / 11 / 13)` by `controlSize`. An explicit or environment
   font ignores `controlSize`.
2. `TextField` and `TextEditor` resolve their font as `Text` does (own, then
   environment, then the default), so `.font(_:)` on a container and
   `.controlSize(.mini)` reach them; their chrome (padding, the caret, the
   selection) is unchanged — **under the default environment they draw what
   they drew**.
3. `Button`'s label is a `Text`, so its font now follows `controlSize` too —
   `DD-R` item 4's "its label's font does not" is withdrawn, and
   `aButtonReadsControlSizeForItsChromeButNotItsLabelsFont` changes its answer
   (a **T row**, renamed `aButtonReadsControlSizeForItsChromeAndItsLabelsDefaultFont`;
   spec 3.12).
4. **Divergence 76 amended again, kept, owner none**: `controlSize` now
   reaches every text's default font and `Button`'s chrome; it still reaches
   no other control's chrome — `TextField`'s padding (Z3's 19/22/24 are font
   plus a padding that also shrinks), `Toggle`, `Picker`, `Slider`,
   `Stepper`. `controlSizeReachesNoBuiltInMeasurement` (T1.7) flips its `Text`
   and `TextField` arms and is renamed
   `controlSizeReachesTheDefaultFontButNoControlsChrome` (spec 3.11).

**Cost if wrong.** A tree that set `.controlSize(.small)` for a button's chrome
now also gets an 11 pt label — SwiftUI's answer (Z3's button widths shrink with
the label). No in-repo production tree writes `controlSize` (grep of
`Sources/MetalUIDemoContent`, spec §7).

---

## TE-G — metrics: divergences 60 and 77 kept; the line height is divergence 86; baselines are round(ascent)

**Evidence.** M1 (width ceiled to the displayScale pixel grid: 71.525 → 72 at
scales 1 and 2, 71.667 at 3), S4 (positions round to the same grid), X13 (a
21-size line-height sweep: SwiftUI's line height is 16 where
`ceil(ascent + descent + leading)` is 16 at SF 13, but 14 vs 13 at SF 11, 30 vs
31 at SF 26, 23 vs 24 at Noto Sans 17, 36 vs 36 at Noto Sans 26, 15 vs 16 at
Menlo 13 — neither `ceil` nor `round` of CoreText's sum, and not a function
of it alone), X10 (an empty `Text` is 0×14), B1/X13 (first baseline =
round(ascent) in all 25 arms: 13, 25, 11, 18, 16 …; last = first + (lines − 1)
× line height).

**The ruling.**

1. **Divergence 60 kept, pinned, owner none.** SwiftUI ceils a text's width to
   the `displayScale` pixel grid, the text half of divergence 77's grid.
   MetalUI answers the unrounded widest line and rounds positions to whole
   points (77). Adopting a whole-point ceil alone would be SwiftUI's answer only
   at scale 1 and would move every text's width in the demo, `Expected.swift`
   and every test literal reading a text width, for a sub-point difference
   `roundLayout` already absorbs at a box's own edges. Pinned by
   `aTextAnswersItsUnroundedWidestLineWhereSwiftUICeilsToThePixelGrid` (spec
   3.14).
2. **Divergence 77 kept, owner none** (the task's "decide"). Rounding to the
   pixel grid is a whole-framework geometry change — every stored rect, the
   fourteen images, `Expected.swift`, and the cross-platform byte pins that
   rest on whole-point geometry — with no text semantics in it; it is not a
   clause of task 11's text. `layoutRoundsToWholePointsWhateverTheDisplayScale`
   stays. Reopen as its own task if a consumer needs half-point geometry.
3. **Divergence 86, added, kept, owner none**: MetalUI's line advance is
   `ceil(ascent + descent + leading)` on both text systems (`FontMetrics`,
   `PortableFontMetrics`, measured equal by `PT-`), where SwiftUI's is
   TextKit's line-fragment height, which X13's 21 sizes fit by no formula
   tried over those three numbers — neither `ceil` nor `round` of their sum,
   nor `ceil(ascent) + ceil(descent)` (right at 9–15, wrong at 16: 20 against
   19, and at 26: 32 against 30) — so "no public metric gives it" is a
   measured absence of a fit, not a proof (and an empty `Text` is 0×14, X10,
   where MetalUI's is 0×16).
   Matching it would need a metric no public CoreText call returns and no
   portable file carries; changing the formula would move every multi-line
   text's pixels and the portable pins. Pinned by
   `aNotoSansLineIsTwentyFourPointsWhereSwiftUIsIsTwentyThree` (spec 3.15).
4. **Baselines** (consumed by `TE-K`): a text's first baseline is
   `round(ascent)` (whole points, as SwiftUI reports it at scale 2), its last
   `first + (lines − 1) × lineHeight` with MetalUI's own line height (so a
   multi-line last baseline carries divergence 86's difference). Glyphs are
   still drawn at `ascent` snapped to the device pixel (unchanged, 0 px);
   where SwiftUI draws its glyphs relative to its guide is unmeasured and not
   claimed.

**Cost if wrong.** If a later task adopts the pixel grid, 60 and 77 retire
together, as this ruling predicts; 86 stays independent.

---

## TE-H — line limit: SwiftUI's four spellings, `reservesSpace`, and the height proposal

**Evidence.** L1 (`lineLimit(n)`; 0 acts as 1; the width is the widest kept
line), L2/L3 (`reservesSpace` and a range's lower bound pad the height, keep
the width and the last baseline; the upper bound caps), L4 (an unspecified
width is one unwrapped line), L5/X9 (a finite height proposal caps the lines at
`max(1, ⌊height / lineHeight⌋)`, the smaller of it and the limit wins,
`reservesSpace` ignores it, infinity is unlimited), L6/L6b (an environment
value, nearest writer).

**The ruling.**

1. `ElementGroup.lineLimit(_: Int?)`, `lineLimit(_: Int, reservesSpace:
   Bool)`, `lineLimit(_: ClosedRange<Int>)`, `lineLimit(_:
   PartialRangeFrom<Int>)`, `lineLimit(_: PartialRangeThrough<Int>)` — SwiftUI's
   are `View` modifiers, so these are environment writes (internal
   `EnvironmentValues.textLineLimit: (min: Int?, max: Int?)`; the public
   `EnvironmentValues.lineLimit: Int?` reads and writes its upper bound, as
   SwiftUI's does). They apply to a `Text` directly too (it is an
   `ElementGroup`).
2. **The height proposal limits lines** — the source comment in
   `ProposalText.swift` ("the height proposal does not truncate") was
   unprobed and is **refuted** by L5; it is corrected in lane 3. The measured
   answer: `lines = min(limit.max ?? ∞, heightLines, natural)`, `heightLines =
   max(1, ⌊h / lineHeight⌋)` for a finite `h`; height `max(lines, limit.min ??
   0) × lineHeight`; width the widest kept line, capped by the proposal.
   **This makes every wrapping text vertically flexible inside a stack** — a
   consequence the design did not name; `TE-R` measures it against SwiftUI
   and says what it may move.
3. A limit of 0 **or below** acts as 1 (0 is L1's; below 0 is unprobed and
   treated like 0 rather than rejected, `SA-J`: reject only what SwiftUI
   rejects).
4. `TextField` ignores it (one line); `TextEditor` ignores it (it scrolls).

**Cost if wrong.** A text that overflowed a short fixed frame now truncates —
SwiftUI's answer. Spec §7 predicts no demo tree does this; the fourteen images
are the check.

---

## TE-I — truncation is CoreText's truncated line, on both systems; divergence 87

**Evidence.** X5 (tail and head widths equal CoreText's at every arm), T1 at
80 and T2/X7 head at 60 (the kept string drawn pixel for pixel), X6 (trailing
whitespace dropped before the token), X8 (multi-line: the rest truncated as
one line, 0 px in all three modes), T6 (U+2026). **X5 middle at 100**: SwiftUI
97.5, CoreText 85.12; T2 finds no candidate.

**The ruling.** `ElementGroup.truncationMode(_: Text.TruncationMode)` (an
environment write, `Text.TruncationMode` = `.head`/`.tail`/`.middle`, default
`.tail`), carried to the seam as `TextLayoutOptions.truncation` (`TE-C` item
3). **Divergence 87, added, kept, owner none**: a single line truncated in the
middle keeps what `CTLineCreateTruncatedLine(.middle)` keeps, where SwiftUI
sometimes keeps more (X5: 85.12 against 97.5 at width 100; equal at 60). The
portable system follows CoreText, not SwiftUI, so both systems agree; pinned
by `aMiddleTruncationKeepsCoreTextsStringWhereSwiftUIKeepsMore` (spec 3.16).
`allowsTightening`/`minimumScaleFactor` are not built (additive, owner none).

**Cost if wrong.** A middle-truncated label may show fewer characters than
SwiftUI would; tail (the default) and head agree.

---

## TE-J — multiline alignment aligns lines inside the text's own box

**Evidence.** A1 (each line in a box as wide as the widest line), A2 (a wider
frame does not widen the box), A3 (one line unaffected), A4 (environment), A5
(a wrapped paragraph centres in the wrap width), A6 (a truncated line in its
box).

**The ruling.** `public enum TextAlignment { case leading, center, trailing }`
and `ElementGroup.multilineTextAlignment(_:)` (an environment write; public
`EnvironmentValues.multilineTextAlignment`), carried as
`TextLayoutOptions.alignment`; the box is the width paint already wraps at
(`measuredWidth`). Right-to-left mirroring stays unimplemented (`EV-K`,
divergence 25): `.leading` is the left edge.

**Cost if wrong.** None beyond `EV-K`'s existing row.

---

## TE-K — baselines in the kernel: every node reports them; an `HStack` aligns by them; a `GridRow`'s traps (divergence 88)

**Evidence.** B1 (guide values per node kind), B1g/B1h/X3a/X3c/X3d/B1k (a
container's first baseline is the smallest of its children's explicit ones at
their placed offsets, its last the largest), B1p (a text-less child is
skipped), B1f/X3e/X3h/X3j (no text → the view's height), B1i/B1j (padding and
frame move it — the kernel already does this), B1l/X3g/X3h (overlay and
background keep the primary's), B2 (`HStack` alignment by baseline: offsets and
height), X11 (a `GridRow`'s baseline alignment keeps the row's ordinary height
and overflows cells — the 26 pt cell at y −12 — which B2's rule does not
produce).

**The ruling.**

1. `VerticalAlignment` gains `.firstTextBaseline` and `.lastTextBaseline`
   (SwiftUI's). `HorizontalAlignment` gains nothing (SwiftUI's has no
   baseline). **Migration note** (`TE-S` item 5): MetalUI's `VerticalAlignment`
   is a public `enum` (SwiftUI's is a struct), so an exhaustive `switch` over
   it outside the package stops compiling; add a `default:` or the two cases.
   The kernel's two-axis `ProposalAlignment` (every `frame`/`overlay`/
   `ZStack`/`Grid(alignment:)` parameter) is a separate type and gains
   nothing, so no baseline is reachable there (item 5).
2. **Measurement**, per `NativeNode` kind, of the `firstBaseline`/`lastBaseline`
   `LayoutMeasurement` already carries: leaf — its closure's; frame, padding —
   unchanged; overlay (`ZStack`) and `linearStack` — the min (first) / max
   (last) of the children's explicit baselines at their placed offsets, `nil`
   if none has one; `overlayAttachment` — the primary's; `fixedSize`,
   `layoutPriority`, `aspectRatio` — the child's; `spacer`, `scrollViewport`,
   `custom` — `nil`; `grid` — min/max over its cells at their placed offsets.
   `nil` is read as the view's height wherever a guide is needed.
3. **Alignment**: `newNativeLinearStack`/`requestNativeLinearStack` gain
   `baseline: ProposalTextBaseline? = nil` (`.first`/`.last`); on a horizontal
   stack each child is placed so its guide (baseline, else height) sits on the
   largest guide, and the stack is `max(guide) + max(height − guide)` tall (B2:
   44 with offsets 12/0/12/15; 34 with 16/4/0/19). A vertical stack with a
   baseline traps (unreachable from `VStack`, whose alignment type has none).
   Registrar count unchanged (a parameter, not a registrar).
4. **Divergence 88, added, kept, owner none**: `GridRow(alignment:
   .firstTextBaseline/.lastTextBaseline)` traps at registration naming the
   divergence (an exit test pins it). SwiftUI's answer (X11) keeps the row's
   height and overflows cells in a way no rule measured here reproduces; a
   trap is the explicit form of "not supportable yet" the task asks for, and
   `GridRow`'s parameter type is SwiftUI's `VerticalAlignment`, so the cases
   cannot be withheld from it alone.
5. Not built, additive, owner none: `.alignmentGuide(_:computeValue:)` (X3l),
   `Alignment` values with a baseline for `ZStack`/`.frame`/`Grid(alignment:)`
   (X11b).

**Cost if wrong.** A child reporting a wrong baseline misplaces only under a
baseline alignment; every existing alignment reads factors as before, and the
new measurement fields are read by nothing else (spec 2.4 pins that every
existing stack answers unchanged).

---

## TE-L — the legacy `baseline` fields lower, or are refused by name; no report names task 11

**Evidence.** CSS aligns a row's items by their first baselines and
synthesises a baseline from a box's bottom edge when it has none — the same
shape as `TE-K` item 2's `nil`-reads-as-height; in a column the cross axis is
horizontal, where a baseline alignment falls back to the start edge. The legacy
engine that ran CSS is gone (stage 9), so this is the ruling, not a
measurement.

**The ruling.** `alignItems.baseline` on a legacy **row** container lowers to
`baseline: .first` on its native stack; on a **column** it lowers as
`flexStart`; on a **`display: .stack`** container (a legacy `Stack`, or any
container `legacyContainerDiagnostics`' first branch sees) it stays a
**permanent refusal by name** (`owner: nil`) — a layered stack is a `ZStack`,
and `TE-K` item 5 builds no baseline `Alignment` for one (`TE-S` item 2; the
design left this branch unruled). `alignSelf.baseline` on a child is consumed without a report
when its parent's own `alignItems` is `.baseline` (the child already aligns
so); anywhere else it is a **permanent refusal by name** (`owner: nil`) —
per-child baseline alignment among differently aligned siblings has no
SwiftUI stack shape. `UnlowerableField.owner`'s `"plan task 11"` branch is
deleted, so **every remaining report is a permanent refusal**; the property
stays (`String?`, now always `nil`) to avoid an API break.
`everyReportNamesALiveOwnerOrIsRefusedByName` **keeps all 265 entries** — the
table is a pure function of `UnlowerableField` (its own doc: it pins the owner
scheme, not which entries a tree raises), and both baseline fields can still
be raised (`alignItems.baseline` by a stack-display container,
`alignSelf.baseline` outside a baseline row) — so its **16** baseline rows
(5 container, 11 item) change owner from `"plan task 11"` to `nil` (spec 2.10;
**amended by `TE-S` item 2**, the design's "265 → 260" was wrong on both
counts). `everyContainerFieldEitherLowersOrIsReportedByName` gains a row and
a column lowering arm and keeps a stack-display report arm.

5. **Any other explicit `alignSelf` under a baseline row is a permanent
   refusal by name** (lane 2's fix round, found by review): `alignSelf`
   `.flexStart`, `.center`, `.flexEnd` and `.stretch` on a child of a row whose
   `alignItems` is `.baseline` report `<site>.alignSelf.<case>` (`owner:
   nil`). Lowered, each laid out silently wrong — a baseline stack has no
   per-child alignment: `.flexStart` shares the container's factor (0), so no
   alignment frame is built and the child sits baseline-aligned where CSS
   puts it at the top; `.center`, `.flexEnd` and `.stretch` build a frame
   greedy on the cross axis whose guide in a baseline stack is its whole
   height (a text-less node's guide, `TE-K` item 2), so the row answered 110
   at a 100 proposal and pushed its text down. At `169d166` every such row
   reported `box.alignItems.baseline`, so no tree that ran before moves; a
   child with no `alignSelf` (the container's alignment) and a column's
   `alignSelf` (its baseline lowers as `flexStart`) are unaffected. Pinned by
   **2.11b** `aNonBaselineAlignSelfUnderABaselineRowIsRefusedByName` (four
   arms and a `flexStart`-row control reporting nothing); the owner table
   (2.10) gains the four names at the ten recording sites, **265 → 305**. The
   "16 baseline rows (5 container, 11 item)" above miscounted the recording
   sites — there are ten (`box`, `stack`, `scrollView`, `modifierLayer`,
   `component`, `text`, `textField`, `textEditor`, `slider`, `list`), so 15
   rows (5 + 10); the table's 265 was right.

**Cost if wrong.** A legacy tree with `.alignItems(.baseline)` that relied on
the report (it trapped in production) now lays out; no in-repo tree uses it.
A tree combining a baseline row with a child's own `alignSelf` still traps,
by the child's name instead of the container's.

---

## TE-M — text-edge default spacing (divergence 51, `GR-O` 5) and W2 stay, owner none

**Evidence.** S1/S1d/X4: two `Text`s in a `VStack` are 0 apart; a `Text` and a
colour block are 8.151 apart below 13 pt text, 4.742 above it, 15.802/8.984 at
26 pt, 13.516 below Noto Sans 17 — fractional, font- and side-dependent, and
restored to 8 by any padding or frame around the text; horizontally 8.
`LR-AM`/`LR-AP`: W2 is a stack's allocation around a wrapping text.

**The ruling.** Kept, owner none. The vertical values are TextKit spacing
metrics as unreproducible from CoreText's public numbers as divergence 86's
line height (they are not a function of ascent, descent or `lineHeight` that
X4's five arms fit); adopting only "text–text is 0" would change the proposal
preview's pixels and leave the row open anyway. W2 is not a clause of part 1's
text (line limit and truncation do not reach a stack's allocation). Their pins
(`aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing`,
`textRowsTakeTheDefaultRowSpacing`) stay; record §04 re-owns both rows to
"none" with X4 as the new evidence (Record phase).

**Cost if wrong.** A SwiftUI port of a text column is 8 pt looser per gap
between texts, as today.

---

## TE-N — what part 1 must not move

**The ruling.** No id path, `StateTable` slot, hit-test, focus, accessibility,
animation, scrim, `List`, `Deferred` or `TextField`/`TextEditor` editing rule
changes; `theSevenRetentionSlotsAreMutuallyDistinct` is untouched (no slot is
added: the new text state is the element's own value and the environment's).
`Text`'s `$anim` baseline is unaffected (a text's font is still snapped, not
animated, spec §8 of the framework spec). **0 px** against `169d166` in all
fourteen offscreen images, `Expected.swift` unedited,
`everyProductionTreeBuildsOnAOneMegabyteThread` green (`Text` grows by one
optional `Font` and three small fields; the lane re-measures the demo's
builder frames), `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green,
`MetalUILayout` importing only `MetalUICore`.

**Cost if wrong.** Any moved pixel is named by `compare.sh`; a ruling must
then name it or the change is reverted.

**Amended by `TE-Y` item 2 (lane 3):** "`Expected.swift` unedited" above did
not hold — the portable Noto Sans demo frame's paragraph is capped by its
height proposal (`TE-H` item 2), so `Expected.swift` is re-recorded under
`TE-Y`, the one named change that moves it. Every other clause stands (the
fourteen images read 0 px against `169d166`).

---

## TE-O — re-owned: to part 2, and elsewhere

| item | to | why |
|---|---|---|
| shapes, images, fills/strokes, overlays, clipping | **part 2** | the task's second sentence |
| `.cornerRadius` clipping, divergence 47 (`OM-G`) | part 2 | clipping |
| `UnitPoint` anchors in `gridCellAnchor` (`GR-O` 4, divergence 64, `DD-P` item 4's ambiguity) | part 2 | an anchor/alignment surface shared with overlays and shapes, not text |
| `appearance`/`colorScheme` and a pre-paint theme (`EV-G`) | part 2 | rendering-facing |
| colour glyphs (record §05) | part 2 | a renderer constraint (polychrome atlas) |
| `foregroundStyle` reaching a shape's fill (C9) | part 2 | shapes |
| an `onTap` control's VoiceOver presence (`AB-` doc) | plan task 12 | accessibility |

**Cost if wrong.** Part 2's collection starts from this table.

---

## TE-P — tick condition and the demo

**The ruling.** Part 1 does **not** tick task 11 (part 2 remains); the Record
phase writes a dated progress note under the task. The demo is unchanged: no
demo tree writes a font, a line limit, an alignment or `controlSize` through
the new API, and every `Text(…).font(size:)` in it keeps its explicit font
(`TE-B` item 5), so the fourteen images read 0 px and `Expected.swift` stays
(spec §7). The real-window capture follows the lock probe; locked at design
time, so it is owed, as for tasks 8–10.

**Cost if wrong.** A ticked box with part 2 undone would overclaim; this line
forbids it.

---

## TE-Q — F8's render field is `ImageRenderer`'s blind spot; `controlSize` reaches the default font by layout (critic round)

**Evidence.** `docs/probes/swiftui-controlsize-text-render.swift` (new): R0
(each instrument separates 9 from 13 pt: 2404 px by render; 77×11 against
106×16 by fitting size), R1 (`ImageRenderer` identifies the default `Text`
under `.mini`, `.small` and `.regular` as `.system(size: 13)` every time —
reproducing F8's `equals=` field), R2 (the hosting view's fitting size
identifies the same three as exactly 9, 11 and 13, no other candidate
matching). A third instrument, `NSHostingView.cacheDisplay`, drew blank with
the screen locked (its own control read 0 px) and was dropped.

**The ruling.** F8's `equals=.system(size: 13)` in its `.mini` and `.small`
rows is an instrument that does not apply `controlSize`, not evidence against
`TE-F`; `TE-F` rests on the layout answer (F8's sizes, Z2, R2). The **drawn**
font under `controlSize` in an on-screen window is unmeasured (screen locked)
and joins the owed real-window capture (Record phase, record §03). No test or
design row changes: MetalUI draws with the font it measures with, by
construction (one resolution function, spec §3).

**Cost if wrong.** If an on-screen window drew 13 pt under `.mini` while
laying out at 9, SwiftUI would be inconsistent with itself; the capture
would show it and `TE-F` would be revisited.

---

## TE-R — a wrapping text in a tight stack: SwiftUI compresses it, the kernel will too, and that may move pixels (critic round)

**Evidence.** `docs/probes/swiftui-text-in-stacks.swift` (new), the paragraph
of L1 (six lines at width 100, K0): beside a `Spacer` at height 60 it gets one
line and the spacer 44.5, although the spacer could have shrunk to 8 (K1); at
100, three lines; at 200, all six (the separating control). Beside a rigid
40-tall colour at 80: two lines (K2). Two paragraphs at 100: three lines each
(K3). `Spacer(minLength: 0)`: the same (K4).

**The problem the design missed.** `TE-H` item 2 makes a text's answer depend
on a finite height proposal. Today every text is vertically **rigid** in a
stack (its height ignores the proposal); after `TE-H` a wrapping text is
**flexible** between one line and its natural height, so the kernel's
least-flexible-first allocation (`CN-B`) serves it before a spacer with only
its equal share — K1–K4 are exactly that rule over L5/X9's `⌊h / lineHeight⌋`,
so this is **SwiftUI's answer** and needs no new mechanism. But it reaches every
lowered legacy `Column`/`Box` too (a positive `flexShrink` lowers to SwiftUI's
compression, `LR-AB`), so **any production text proposed less than its
natural height now draws fewer lines** — where the design's §7 asserted 0 px
without checking.

**The ruling.**

1. The behaviour is adopted (SwiftUI's, K1–K4); no ruling exempts stacks.
2. **Lane 3 measures before it implements**: a scratch instrument (a
   `docs/probes/text-semantics-height-census.patch`, recorded, not committed
   to `Sources/`) logs every `Text`/`ProposalText` leaf whose finite height
   proposal is below its natural height, over `demoContent()`,
   `nativeLayoutPreviewContent()` and the controls demo at the demo's own
   window size and every size the fourteen offscreen images use. **An empty
   census** confirms spec §7's 0 px; **a non-empty one** is recorded row by
   row in record §59, the fourteen images are compared after implementation,
   and each moved image is named by a new `TE-` ruling (the census row it
   comes from) before the lane closes — `Expected.swift` re-recorded only
   under that ruling, with Linux and Windows CI owed the confirmation.
3. **A pin**: spec 3.23 `aStackSharesItsHeightWithAWrappingTextAsSwiftUIDoes`
   — K1 (60, 100, 200) and K2 (80) as **line counts** (1, 3, 6; 2) on a
   `VStack(spacing: 0)` of `ProposalText` 100 wide, and K2 alone on a legacy
   `Column` (gap 0) of a `Text` and a 40-tall `Box` (the legacy vocabulary has
   no `Spacer`); literals from the frame's own line height (16 at the default
   13 pt, where SwiftUI agrees, X13); red before (every arm reads 6); mutation M3u: the text's measure ignores a finite
   height proposal (the pre-`TE-H` answer) reddens it. The heights SwiftUI
   reports half a point under whole lines are divergence 77's grid, not read.
4. An existing test whose answer moves under this is a **T row** with its
   retirement row, never an edited literal without one (`goldensUnchanged`).

**Cost if wrong.** A caller whose paragraph shared a tight column with a
spacer sees it truncate, as in SwiftUI; the remedy is SwiftUI's too
(`.fixedSize(horizontal: false, vertical: true)`, or `lineLimit(nil)` plus
room).

---

## TE-S — critic round: amendments, and the attacks rejected

**Amendments** (each applied to the ruling or spec row it names, in this
commit):

1. **Lanes rebalanced** (`TE-A`). The design put both oracle-heavy pieces —
   portable truncation matching `CTLineCreateTruncatedLine` over Latin, CJK,
   Arabic and combining marks in three modes, and portable font selection by
   weight and italic over lazy system faces — in lane 1, with lane 2 a
   kernel-only lane. Font selection (`TE-C` item 1, spec 1.1–1.4, the bold
   half of 1.11, `FontDescriptor`'s half of G1.1) moves to **lane 2**; lane 1
   keeps layout options and metrics. The two riskiest measurements no longer
   share one lane's budget.
2. **`TE-L`'s unruled branch and its wrong count.** `legacyContainerDiagnostics`
   raises `alignItems.baseline` on a `display: .stack` container through a
   separate branch the design did not rule; it stays a permanent refusal. The
   report table therefore keeps all 265 entries, 16 changing owner (spec 2.10
   was "265 → 260").
3. **Divergence 60's pin separates at the rect** (spec 3.14): "Hello, world"
   at 13 (71.525) rounds to 72 either way, so a `ceil` mutant (M3m) would move
   no stored rect; the test adds "Hello, world" at **11** (62.068: rect 62
   unrounded-and-rounded, 63 under a `ceil`) and asserts both the measured
   width (`measuredWidth`) and the rect.
4. **Divergence 86's wording** (`TE-G` item 3): "not a function of" replaced
   by the fits actually tried and where each misses.
5. **`VerticalAlignment`'s two new cases are a source break** for an external
   exhaustive `switch` (a public `enum`); `TE-K` item 1 carries the migration
   note.
6. **The truncation token and an unmatched oracle case** (`TE-C` item 3): the
   token is shaped in the text's resolved font through `shapeCascading` on
   the portable path (`FB-A`), and a case the portable truncation cannot match
   stops the lane for a ruling instead of leaving the corpus.
7. **The Windows stack budget is measured, not assumed** (`TE-N`): lane 3
   records `MemoryLayout<Text>.size`, `MemoryLayout<ProposalText>.size` and
   the smallest thread that builds every production tree (record §53's 484 KB
   harness), before and after; `everyProductionTreeBuildsOnAOneMegabyteThread`
   green is the gate, the numbers go to record §59.

**Attacks rejected** (recorded here, the run's own prefix, rather than as
`LR-` rulings, whose decisions doc belongs to plan task 7):

- *A baseline `Alignment` is reachable through `.frame`/`ZStack`/`Grid`*:
  no — those take `ProposalAlignment`, not built from `VerticalAlignment`
  (`StackAlignment.swift`); only `HStack` and `GridRow` take the enum.
- *`ElementGroup.foregroundColor(_:)` collides with `Text`'s*: no — the
  concrete `Text.foregroundColor(_:)` (and `ProposalText`'s, `TextField`'s,
  `TextEditor`'s) is more specific and keeps its answer; G3.1 compiles both.
- *The seam change breaks conformers*: two exist (`CoreTextTextSystem`,
  `PortableTextSystem`), none in `Tests/` or `Backends/SDL` (grep of
  `: TextSystem`); the migration note stands for outside callers.
- *The probe's claims are unreproduced*: the critic re-ran it whole; all 294
  lines are byte-identical to the header.
- *`FontKey` would conflate weights of the variable system face*: no — it
  reads the variation coordinates and the PostScript name (`.SFNS-Semibold`,
  X12) off the resolved font (`FontKey.swift`), never the request.
- *Scope creep into part 2*: none — the shape half of `foregroundStyle` (C9),
  clipping and images are `TE-O`'s.
- *Baseline measurement moves `SA-M`'s work literals*: not by construction
  (baselines come from answers already in hand); the lane's work-counter test
  (spec §8 lane 2) is the check, kept.

---

## TE-T — a hard break ends the truncated line at its paragraph; narrower than the token, the longest prefix that fits (lane 1)

**Evidence.** `docs/probes/swiftui-truncation-edges.swift` (**new**, lane 1;
compiled twice and interpreted once, byte-identical, screen locked): E0
reproduces X8 (positive control, 0 px in all three modes, > 2000 px from the
untruncated text); E1 "Ready\nSet\nGo" at `lineLimit(2)`, width 100 — tail
draws "Ready\nSet…" (0 px), head and middle "Ready\nSet" (0 px), the one-line
truncation of the whole rest "Set\nGo" 327–656 px off in every mode;
`lineLimit(1)` tail "Ready…" (0 px); E2 the same with a longer rest ("gamma…"
tail, "gamma" head/middle, 0 px; the whole rest's truncation 798–1948 px off);
E4 a paragraph that itself overflows, with more text after it — CoreText's
truncation of the PARAGRAPH, all three modes (0 px). E3 "Hello" at
`lineLimit(1)`: CoreText's `CTLineCreateTruncatedLine` answers nil at 4, 8 and
10 (the token is 10.283 wide in SF 13 … every width narrower than it); SwiftUI
draws no token in any mode, exactly "H" at 10 (0 px), a clipped "H" at 8 and 4.

**The ruling** (amends `TE-C` item 3, whose "the rest of the string from line
`n−1`'s start is truncated as one line" X8 measured only for a rest with no
hard break):

1. With `maxLines == n`, a definite width and more than `n` lines, lines
   `0..<n−1` are kept and the last kept line is built from the rest's **first
   paragraph** `P` — from line `n−1`'s start to the first hard break (U+000A,
   U+000B, U+000C, U+000D, U+0085, U+2028, U+2029), the break excluded, or to
   the string's end.
2. `P` wraps at the width (it is wider than one line): `P` is truncated as one
   line in the mode — `CTLineCreateTruncatedLine` on a line of `P` alone on the
   Apple path (E0, E4).
3. (**Amended by `TE-V`**: a NON-EMPTY `P` — an empty `P` takes no token in
   any mode, probe E5.) `P` fits and text follows it: in **tail** mode `P` takes the token anyway
   (E1, E2) — the longest prefix of `P` that fits with the token, as the tail
   rule measures it — on the Apple path CoreText's truncated line of `P`
   followed by one glyph too wide to keep, so the kept prefix is CoreText's;
   in **head** and **middle** mode `P` is drawn whole, no token (E1, E2).
4. The token does not fit the width (CoreText's nil): the line is the longest
   prefix of `P` of whole clusters that fits the width, **at least one
   cluster**, no token, in every mode — `CTTypesetterSuggestClusterBreak` on
   the Apple path. SwiftUI clips that one cluster at its frame where MetalUI,
   which never clips text (`PlacedGlyph`'s doc comment), draws it whole: a
   difference of ink inside one character's width at a width below ~10 pt,
   recorded here and given no divergence number.
5. `lineRanges` gives the kept lines' ranges and, for the last line, `start..<
   string end` — it stands for the whole rest, whatever part of it is drawn.
6. At an unspecified width nothing is truncated: the first `n` lines are kept
   (`TE-C`, L4), hard breaks included.

Pinned by spec rows **1.6b** `aHardBreakEndsTheTruncatedLineAtItsParagraph`
and **1.6c** `aWidthNarrowerThanTheTokenKeepsTheLongestPrefixThatFits` (both
systems, and CoreText's own glyphs read outside the seam), and by the
hard-break strings in `TruncationOracleTests`' corpus (1.5).

**Observed, not ruled on.** E3's head mode at width 20 matches none of its
candidates (nearest CoreText's "…o", 108 px); `swiftui-text-semantics.swift`'s
head arms (X5, X7 at 60) agree with CoreText, and `TE-I` keeps CoreText as the
portable path's oracle.

**Cost if wrong.** A line limit over text with hard breaks would draw the rest
glued onto one line ("SetGo") — the answer `TE-C` as first written gave.

---

## TE-U — the truncation rule, measured on both systems; one right-to-left class pinned, not matched (lane 1)

**Evidence.** `TruncationOracleTests` (`METALUI_TRUNCATION_MEASURE=1`,
2026-09-28, macOS 27.0): 7,980 cases at this ruling, **9,660 since `TE-V`**
added two empty-paragraph strings (7,701 truncated; still 38 differences, the
same class) — Noto Sans and Source Sans 3 over seven
Latin strings (kerning pairs, a ligature, leading and trailing spaces, three
with hard breaks; nine since `TE-V`, five with hard breaks, two of them with an
empty paragraph), a combining-mark string (precomposed and stacked marks),
two CJK strings in the system's Hiragino Sans GB, two Arabic strings in Noto
Sans Arabic with Noto Sans as its cascade on both sides; 13 and 17 pt; `nil`,
4, 8, 10.5 and 12…222 pt by 7; one and two kept lines; all three modes; the
alignment cycling — 6,093 of them truncated. Each case compares every line's
source range and advance (1e-9 pt) and every glyph's face, id, device pixel,
subpixel variant and baseline against the Apple path's
`CTLineCreateTruncatedLine`. Exploratory `CTLine` dumps (a scratch harness,
not committed) supplied the hypotheses; the oracle is what each rule was
kept or dropped by. The first implementation read 156 differences; the rules
below brought it to 38, every one in the class of item 7.

**The ruling** (the rule `PortableText.truncatedLine` implements; each item a
measured disagreement it removed):

1. **Whitespace hangs, asymmetrically.** With `L` the line's advance, `T` its
   trailing whitespace (`CTLineGetTrailingWhitespaceWidth`) and `t` the
   token's advance: tail keeps the longest prefix with `prefix + t ≤ width +
   T`; head the longest suffix with `suffix − T + t ≤ width`; middle a prefix
   and a suffix each within `(width + T − t) / 2`, the suffix measured without
   `T`. A kept prefix drops its trailing whitespace, a kept suffix its leading
   whitespace (X6 for the tail). A line with `L − T ≤ width` is handed back
   untruncated.
2. **Middle splits the room in halves**, not "prefix first, the rest to the
   suffix" (X5's middle arm, CoreText's 85.12 at 100, is this rule).
3. **What is removed is a cluster that is a whole grapheme**: a ligature goes
   whole (its cluster spans graphemes); a base goes with its marks, although
   HarfBuzz may give each stacked mark a cluster of its own (the combining
   string's `q́̂̃`).
4. **Kept glyphs keep their advances in the line's shaping** — the share,
   kerning into a dropped neighbour included — and are not re-shaped (an
   Arabic letter keeps its joined form when its neighbour is dropped).
5. **Narrower than the token** (`TE-T` item 4): the longest run of whole
   GRAPHEMES that fits, at least one; a prefix ending inside a ligature is
   measured and drawn re-shaped — `CTTypesetterSuggestClusterBreak` keeps
   Source Sans 3's "Af" out of "Affix" at 12 pt, splitting "ffi".
6. **Alignment offsets are rounded to 1/256 pt on both paths**
   (`Shaper.alignmentOffset`, `PortableText.alignmentOffset`). The two paths
   measure a line's width to ~1e-13 pt, and an unrounded centring offset put
   pens across subpixel-variant boundaries (the first run's centred Latin
   differences, e.g. "The quick…" at 131 pt, one variant apart); on a 1/256 pt grid
   the offsets are equal and the pen arithmetic after them is the unaligned
   pen's. Visually nothing: a variant is ¼ device pixel.
7. **Not matched: a right-to-left suffix in head or middle mode** (38 cases,
   every Arabic head or middle difference; Arabic TAIL, the default, matches
   in every case, as do Latin, the marks and CJK in all three modes).
   **Scope: this is a claim about the corpus.** As first written the corpus
   held no empty paragraph, and outside it the two systems disagreed on Latin
   in tail mode — CoreText drew a token for an empty last paragraph, the
   portable path none (a reviewer's "A\n\nB" at `lineLimit(2)`) — and, at a
   width narrower than one glyph, in their base wrapping of an empty
   paragraph. `TE-V` measured SwiftUI, fixed both and added the strings; the
   corpus now covers them and the 38 are unchanged.
   CoreText sometimes keeps one more cluster at the suffix's edge than the
   share rule — e.g. "مَرْحَبًا بالعالم يا صديقي" at 13 pt, head, width 26:
   CoreText keeps "قي" (16.003 pt, with the 10.283 pt token 0.286 over the
   width), the portable path "ي" (9.568). Three hypotheses were measured and
   dropped: glyph-position widths (a mark's offset at either edge: 46
   differences), CoreText's kerning bookkeeping at the cut (a right-to-left
   pair's adjustment stored on a different glyph than HarfBuzz stores it: 68),
   and both (68). **Pinned**, both answers: `aRightToLeftHeadTruncationKeepsOneClusterLessThanCoreText`
   (the case above, glyph for glyph), and
   `thePortableTruncationKeepsCoreTextsStringInEveryMode` requires every
   difference to be in this class and their count to be 38. `LB-M`'s
   precedent (Thai): a portable path that differs from CoreText on a named
   class, pinned, never dropped from the corpus. No divergence number: this
   is the portable path against CoreText, not MetalUI against SwiftUI.
8. **The line breaker's emergency break keeps a base with its marks**
   (`PortableText.layOut`, `graphemeBreak`): at a width narrower than one
   grapheme it broke between a base and a mark HarfBuzz had given its own
   cluster, where CoreText keeps the grapheme ("مَ" at 4 pt). Found by this
   oracle's two-line cases; the line-breaking, emission, content-size,
   fallback, bidi and caret oracles stay green (`MetalUIPortableTextTests`,
   64 tests).
9. **A variant tie.** CoreText moves the glyphs after a middle token as a
   run; the portable path walks their pens; the sums differ in the last bit.
   In `theSeamsLayoutOptionsPlaceTheSameGlyphsOnBothSystems`' 864 cases one
   pen lands on an exact variant boundary (59.625 against
   59.624999999999996 device pixels, 15 pt, scale 1) and rounds a quarter
   pixel apart; the test allows exactly that one tie and pins it. Emulating
   the run shift instead (both associations) moved 1.5 from 38 to 44
   differences and 1.7 to four ties, so the pen walk stays.

**Cost if wrong.** A right-to-left label truncated at its head or middle may
keep one letter fewer on Linux and Windows than on macOS. Tail truncation —
the default, and the only mode a `TextField` or a list row is likely to use —
is exact on every script measured.

---

## TE-V — an empty last paragraph takes no token; an overflowing line keeps CoreText's empty-paragraph break (lane 1 fix round)

**Evidence.** `docs/probes/swiftui-truncation-edges.swift` arm **E5** (added
this round; compiled twice and interpreted once on an idle machine, stdout
byte-identical, every earlier line byte-identical to `TE-T`'s recording,
screen locked): "A\n\nB" at `lineLimit(2)`, width 100 — "A" alone 0 px in
tail, head and middle, the token's reading ("A", then "…") 54 px off, the
untruncated text 185 px off; "\nB\nC" at `lineLimit(1)` — nothing drawn, 0 px
in all three modes, the token alone 54 px off. The 54 px is the token's ink,
the same separation E1 read between "Set…" and "Set". CoreText's own
wrapping, read through `CoreTextTextSystem.lineRanges` (the Apple path's
typesetter, no options): "A\n\nB" at 4 pt is `[0..<3, 3..<4]`, at 30 pt
`[0..<2, 2..<3, 3..<4]`; "A \n\nB" at 4 is `[0..<3, 3..<4, 4..<5]`;
"A\r\n\r\nB" at 4 is `[0..<3, 3..<5, 5..<6]`; "A\n\r\nB" at 4 is `[0..<4,
4..<5]`; "A\n\n" at 4 is `[0..<3]`; "ABC\n\nD" at 4 is `[0..<1, 1..<2, 2..<5,
5..<6]`; "A\u{2028}\u{2028}B" and "A\n\u{2029}B" at 4 take the second break
the same way.

**The ruling.**

1. **An empty paragraph as the last kept line takes no token, in any mode**
   (amends `TE-T` item 3, whose tail token is for a non-empty `P`): the line
   is drawn empty, `measure` counts it at 0 width and one line height, and
   `lineRanges` still gives it the whole rest (`TE-T` item 5). The Apple path
   drew CoreText's forced token for it ("A", "…"; widest line 10.283 where
   the answer is 8.307) and is the one fixed (`Shaper.truncatedLine`: `guard
   mode == .tail, attributed.length > 0`); the portable path already drew
   nothing.
2. **A line whose one cluster is wider than the width, ending at a hard break
   straight after that cluster, takes the next paragraph break too when an
   empty paragraph follows** — CoreText's wrapping, now the portable line
   breaker's (`PortableText.layOut`): not after a space or a CR LF ending the
   line, a following CR LF taken whole, and never when the cluster fits. This
   is base wrapping, not truncation, found because the empty-paragraph
   strings reach widths narrower than "A" (4 and 8 pt, and 10.5 in Source
   Sans 3). It moves the portable `lineRanges`, `measure` and placement only
   there, toward CoreText; SwiftUI's answer at such a width is CoreText's
   (`TE-I`), and no probe arm separates it further. The line-breaking,
   emission, content-size, fallback, bidi and caret oracles stay green.
3. `TE-U`'s "every difference is in the right-to-left class" is scoped to
   its corpus, which now holds "A\n\nB" and "\nB\nC": 9,660 cases, 7,701
   truncated, 38 differences, every one of them in `TE-U` item 7's class.

Pinned by **1.6b**'s E5 arm (both systems, glyphs and `measure`, all three
modes), `bothSystemsBreakLinesAtTheSameRanges`' literal arm (item 2, both
systems, the seven strings above), and 1.5 over the enlarged corpus. Mutations
(record §59 §2.7): dropping item 1's empty-`P` guard reddens 1.6b and 1.5;
dropping item 2's absorb reddens `bothSystemsBreakLinesAtTheSameRanges` and
1.5.

**Also pinned this round, no new rule**: the portable measurement cache is
keyed on the options (1.10's arm, both orders, on fresh systems); a limit
below 1 acts as 1 at the seam (`TE-H` item 3; 1.6's arm, 0 and −1 on both
systems); alignment's factors and its leaving out trailing whitespace
(`TE-J`, A5) against a `CTLine` built in the test — **1.7b**
`aLineIsAlignedByItsWidthWithoutItsTrailingWhitespace`.

**Cost if wrong.** A multi-paragraph label with a blank line, limited to end
at that blank line, would draw a stray "…" on macOS alone; a text box
narrower than one glyph would stack one more blank line on Linux and Windows
than on macOS.

---

## TE-W — font selection, measured: CoreText's descriptor matching on the Apple path, the style word over the OS/2 class on the portable one; ten rows pinned (lane 2)

**Evidence.** `docs/probes/swiftui-font-selection.swift` (**new**, this lane;
compiled five times and interpreted once, 186 lines byte-identical, screen
locked; a warm-up render added after the first draft's P0 italic count read
3078 once and 3080 otherwise): arms P0 (HelveticaNeue vs -Bold 4924 px, vs
-Italic 3081 px — a 0-px match names one face), W (nine weights × two slopes
over eight families, **144/144** rows where SwiftUI draws the face CoreText's
prediction names), N (no weight, italic only: **7/7**), S (the system font at
four weights × two slopes × four designs: **32/32** at 0 px). Two scratch
measurements, recorded here and in record §59 §3.2, not committed as probes
(they measure CoreText, not SwiftUI): over the **2 755** faces a stock macOS 27
install lists under `/System/Library/Fonts` and `/Library/Fonts`, CoreText's
weight trait against the OS/2 `usWeightClass` and against the style name's
weight word, and its italic trait against the style name, `fsSelection` bit 0
and `macStyle` bit 1; and CoreText's selection (the W arm's rule) for every
static family of four or more faces, 68 families × ten weights × two slopes.

**The ruling.**

1. **The Apple path is CoreText's descriptor matching, measured equal to
   SwiftUI's `Font`** (`FontResolver.resolve(_:)`, amending `TE-C` item 1's
   "family's face nearest that weight" with the rule that reaches it): the
   system face is the UI font's descriptor plus `kCTFontWeightTrait` and, for
   a design, the traits key `NSCTFontUIFontDesignTrait` (what
   `NSFontDescriptor.withDesign` writes; CoreText exports no constant) — key
   for key `NSFont.systemFont(ofSize:weight:)` and `withDesign` at every
   weight × design, sizes 13 and 26 (1.3) — then the created font slanted by
   `CTFontCreateCopyWithSymbolicTraits`; a family is `CTFontCreateWithName`,
   then with a weight a descriptor of that face's family name plus the weight
   trait, then with italic the **descriptor's** symbolic italic trait. The
   two paths slant differently because SwiftUI does: slanting the system
   descriptor drew another face in 15 of S's 32 rows, and slanting the
   created custom font drew Avenir Next light italic as Italic where SwiftUI
   draws UltraLightItalic (W, the first draft's one miss). A request with no
   weight, no slope and the default design is `resolve(family:size:)`
   unchanged, so every existing caller draws what it drew.
2. **The portable face's traits come from its style word before its OS/2
   class** (amending `TE-C` item 1's "its OS/2 `usWeightClass`"), measured:
   CoreText's weight trait follows the class only where class and name agree
   — Avenir Next UltraLight is class 275 and −0.8, Avenir Heavy class 900 and
   0.56, Avenir Black class 800 and 0.62 — and over 18 of the oracle's families (110 faces) the
   style word reproduces 107 faces' weights where the class reproduces 101. So `FaceTraits` (`PortableFontResolver.swift`) takes the
   first weight word of the style name (ultralight/extralight −0.8, thin −0.6,
   light −0.4, book/regular/roman/normal 0, medium 0.23, semibold/demibold
   0.3, extrabold/heavy 0.56, ultrabold/extrablack/black 0.62, bold 0.4), a
   style of "Italic" alone as 0 (Cochin-Italic is class 500 and CoreText's 0),
   and the class, to the nearest hundred, only for a style with no word. The
   slope is the style's "italic" or "oblique" (CoreText's italic trait agreed
   with it on 2 753 of the 2 755 faces; `fsSelection` on 2 731, `macStyle` on
   2 737), the width `(usWidthClass − 5) / 10` (condensed, class 3, is
   CoreText's −0.2). `FreeTypeFaceNames` carries the class pair and the style,
   read by `FreeTypeFaceNames.read(path:)` without the face's bytes, so a lazy
   system face (`SF-B`) is selected unloaded: registering the oracle's 187
   faces loads none, and one bold italic request loads exactly its answer.
3. **The portable selection** (`PortableFontResolver.resolve(_:)`): a name
   that is a face's **family** name means the family's regular upright face
   (nearest weight 0, normal width) — `CTFontCreateWithName`'s answer ("Futura"
   is Futura-Medium, "Sukhumvit Set" SukhumvitSet-Text), no longer whichever
   face registered first (a PostScript or full name still means its face,
   `FN-A`); a weight picks the upright face of that face's family minimising
   `|Δweight| + |width|`, a tie keeping the named face, then the heavier;
   italic picks, among the family's italic faces of the selected face's
   width, the one nearest the requested weight — the **lighter** on a tie,
   which is how CoreText answers Avenir Next and Seravek (light italic →
   UltraLightItalic, thin italic → ExtraLightItalic, where upright they tie
   the other way) — or, with no weight, nearest the selected face's own.
   Nothing is synthesised (F2h, F4b: 1.2 on both systems). A design with no
   family resolves the family `register(design:family:)` named for it, else
   the default face.
4. **Ten rows differ, pinned by name, not matched** (`LB-M`'s and `TE-U`'s
   precedent; `pinnedSelectionDifferences`, 1.1 requires the differences to
   equal exactly these): over **30** installed families, **187** faces and
   **600** requests (ten weights incl. none × two slopes), 590 equal
   CoreText's face. The ten are three classes, none reachable from the
   traits FreeType reads: (a) a face whose CoreText weight follows neither its
   style word nor its class — Hoefler Text Black is class 700, word "black"
   (0.62), CoreText 0.4, so medium and semibold (0.23, 0.3; each upright and
   italic, 4 rows) select Black on CoreText and Regular on the portable path;
   Futura Condensed ExtraBold is class 800, word "extrabold" (0.56), CoreText
   0.62, so black (0.62) upright is Condensed ExtraBold on CoreText and Bold
   here (1 row); (b) a slant CoreText declines for a nearer italic face —
   Futura bold and heavy italic stay upright Bold on CoreText where the
   portable path takes MediumItalic (2 rows), and black italic keeps
   Condensed ExtraBold (1 row), while Gill Sans ultra-bold italic takes
   BoldItalic on both — no distance rule over the three fits both families;
   (c) an exact face CoreText passes over — Sukhumvit Set thin (−0.6) is
   SukhumvitSet-Light on CoreText although SukhumvitSet-Thin is −0.6 (2 rows).
   A family not installed is skipped; at least two must be (`#require`).
5. `ShapingCache`'s font memo (`resolvedFonts`) is keyed on the whole
   descriptor — weight by `bitPattern`, slope, design — so a weight resolves
   its own face through the seam (1.3's seam arm; `FontRequest`); it stays
   never swept, as `fonts`' doc comment and CLAUDE.md's "Text" paragraph
   require (move both or neither). *(Branch check: this line first cited
   `TX-C`, which is the `opsz` pin ruling and says nothing about sweeping; no
   ruling id carries the never-swept rule.)*

6. **A `W0`…`W9` style takes its weight from the number; the class decides
   only a style with neither a word nor a number** (lane 2's fix round).
   Measured by a scratch CoreText read (record §59 §3.7): Hiragino Sans's ten
   faces are CoreText's −0.8, −0.6, −0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62, 0.62
   for W0…W9, where their OS/2 classes (100, 200, 250, 300, 400 … 900) put W3
   at −0.4 and W4 at 0 — adding the family to 1.1's corpus read **20
   differences** under the class rule, 0 under the number rule. Over the whole
   install the class fallback then decides exactly one face with a class
   (Marker Felt "Wide", class 700, CoreText 0.4; Apple Chancery's "Chancery"
   has no class and is 0), and reading that class as 0 moves no request's
   answer (mutation V9: 1678 green) — so the fallback is **pinned by
   synthetic `FaceTraits` rows**, not by the oracle (1.1b). One more
   difference, pinned in 1.1b: Marker Felt at weight 0 is "Thin" on CoreText,
   which weighs it 0 (class 400) against its own style word, and "Wide" here,
   which reads "thin" as −0.6. Item 4's corpus becomes **31** families, 213
   faces (Hiragino's collection lists faces of other families too) and **620**
   requests; the ten pinned rows are unchanged.

**Cost if wrong.** A portable app asking a Hoefler Text, Futura or Sukhumvit
Set weight in the ten pinned rows draws a neighbouring face of the same
family where macOS draws another; every other row of the corpus is macOS's
face. A future macOS whose CoreText weights move would redden 1.1 and 1.3 —
the probe and the two scratch measurements re-run give the new rule.

---

## TE-X — baselines in the kernel and the legacy fields, as landed: a custom node's own baselines, a grid's from its solve, a third T row, and no NaN from an infinite answer (lane 2)

**Evidence.** Lane 2's implementation against `TE-K`/`TE-L` and the existing
suite: `aNaNCustomMeasurementTraps` (checkpoint 2, SA-J) reddened when a custom
node's baselines were dropped as `TE-K` item 2 said; `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`
(stage 2's 3.9) reddened when `TE-L` lowered its fixture's `alignItems:
.baseline`; `SA-M`'s work literals (every `lastNativeLayoutWork` test) stayed
green unedited; `baselineAlignmentAddsNoMeasurementWork` (new) pins it.

**The ruling.**

1. **A custom node reports the baselines its `sizeThatFits` returns**
   (amends `TE-K` item 2's "`custom` — `nil`"): none unless it says so, which
   is what every in-repo `ProposalLayout` does — the nearest this protocol has
   to SwiftUI's `explicitAlignment`. Dropping them would have silenced
   checkpoint 2 on a custom NaN baseline, an existing pin of `SA-J`. Row 2.1
   pins both arms (a layout reporting none → `nil`; one passing its child's
   → 13).
2. **A grid's baselines are its cells' explicit ones at the offsets its
   placement uses** (the anchor's, else the row's, else the grid's vertical
   factor, `nativeGridCellOffsetsY`), each cell's measurement read back from
   the run's cache at the proposal the solve recorded — a lookup that counts
   no work, so the grid work literals (`GR-U`, `NativeGridWorkTests`) do not
   move. A cell placed at a slot it answers differently is re-measured there
   by `nativeGridCellRects`; its baseline in the grid's answer is the solve's.
   Reachable only where a grid is a child of a baseline-aligned `HStack`; X3i
   (one cell, 13) pins the common case, and **2.1c** (lane 2's fix round) the
   grid's own factor and a cell's anchor against
   `docs/probes/swiftui-baseline-offsets.swift`: two rows at vertical spacing
   8 report 25/73 centred (O2) and 13/73 at `.top` (O3), a bottom-anchored
   cell 37 (O4) — every offset 0 (mutation V5) reddens it. 2.1c also pins a
   vertical stack's gaps (O1, 13/49 at spacing 8; V4, the cursor without its
   gaps, reddens it). **A `GridRow`'s own alignment (as opposed to a cell's
   anchor or the grid's) was left unpinned by 2.1c** — none of its arms call
   `markNativeGridRow` with an `alignment:`, so `nativeGridCellOffsetsY`'s
   `?? plan.rowAlignments[cell.row]?.verticalFactor` fallback read `nil` in
   every one, and dropping it reddened nothing (branch check, `TE-AB`); fixed
   by **2.1d** against probe arm O5 (a `GridRow(alignment: .bottom)` with no
   cell anchor beside a 40-tall colour, in a `.top` grid, reads 37 — the same
   offset as O4's cell anchor, from the row's own factor alone).
3. **Third T row, spec 2.13**: `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`
   expected `[gap.percent, alignItems.baseline, size.percent, inset]`; a flex
   container's `alignItems.baseline` lowers since `TE-L` and no other flex
   container row exists, so it now expects `[gap.percent, size.percent,
   inset]`, its fixture unchanged, and the production trap still names
   `box.gap.percent`. V2 (every-node rows first) still separates: the report
   would read `[size.percent, inset, gap.percent]`. The design listed two T
   rows; this is the third, its retirement row in record §59 §3.
4. **Placement by a baseline is from the stack's top edge** (each child at
   `bounds.y + maxGuide − guide`), the offsets `measureLinearStack` used, so
   measurement and placement agree for a stack placed at its own answer — as
   every kernel container places a child. A vertical stack's baselines are
   its children's at their cursor positions; a horizontal factor-aligned
   one's at `(height − h) × factor`.
5. **No measurement is added**: the new helpers (`measureOverlay`,
   `measureLinearStack`, `gridMeasurement`, `@inline(never)`) read answers
   already in hand, and `measureNative`'s own frame gains no loop locals
   (`SA-L`); `aChainOfMaxDepthNodesOfEveryKindSurvivesAOneMegabyteThread`
   green. `VerticalAlignment.proposalAlignment` reads `.top` for the two
   baseline cases, a factor the kernel ignores whenever `textBaseline` is set.

6. **An infinite answer never makes a baseline NaN** (found by mutation M2c,
   record §59 §3): a greedy frame over a text at an infinite proposal (CN-F;
   a vertical stack's flexibility probe reaches one, CN-B) answers ∞ with a
   baseline of 13 + ∞ × ½ = ∞; a container's offset `(∞ − ∞) × factor`, a
   baseline guide's remainder `∞ − ∞`, and a second greedy frame's own shift
   are NaN, which checkpoint 2 (SA-J) traps. So a frame drops a baseline its
   shift makes NaN, a guide falls back to the height when its baseline is not
   finite, a NaN offset or remainder is 0, and `combinedBaselines` leaves out
   any placed baseline that is not finite. Before lane 3 no production leaf
   reports a baseline, so nothing reached it; pinned by **2.1b**
   `anInfiniteAnswerNeverMakesABaselineNaN` (exit `.success`, one and two
   greedy frames, factor and both baselines; the row reports no baseline at
   the infinite probe).

**Cost if wrong.** A custom layout that returns a baseline it does not mean
would now align by it inside a baseline `HStack`; a grid cell that grows in
its slot would misreport the grid's baseline by that growth — both only
under a baseline alignment, which nothing in the demo or the repo's trees
writes.

---

## TE-Y — the height census, as landed: no image of the fourteen moves; the cross-platform demo frame and one real-window look do, and two more tests re-answer (lane 3)

**Evidence.** The `TE-R` item 2 census (`docs/probes/text-semantics-height-census.patch`,
record §59 §4.1), taken before any source change over every tree and size
the fourteen offscreen images use, the 920×560 window in every demo state and
the controls demo, all through CoreText: **one row** — `demoMainPane()`'s
wrapping paragraph ("CoreText shapes this paragraph…") under the **A** state
at 920×560, placed at (524, 68.5) against its natural 80. After the
implementation the full suite found a second configuration the census had not
covered: `theDemoFrameMatchesTheValuesRecordedOnMacOS` (`XP-C`) renders
`demoContent()` through the **portable** system on **Noto Sans** at 920×560,
whose 18 pt line makes the same paragraph taller; the instrument, extended to
that configuration and re-run (record §59 §4.3), read the same paragraph at
(648, 66.5) against 72 at scales 1 and 2, and nothing else. The fourteen
images read 0 px against `169d166` (record §59 §4.5).

**The ruling.**

1. **No image of the fourteen moves**, as the census predicted.
2. **`Expected.swift` is re-recorded** (the only named change that moves it):
   the portable Noto Sans demo frame draws the paragraph in **three** lines,
   the third ending in `…`, where it drew four — 34 glyphs out, the token in,
   15710 → 15677 glyphs — and the 18 pt it releases goes to the `ScrollView`
   box below it in the same column, which grows 61 → 79 and moves up 18, so
   its 500 content rects and their glyphs move up 18 (36 at scale 2). Nothing
   else moves: a scene diff between `169d166` and the lane's commit, both
   scales, explains every rect and glyph by those two causes (record §59
   §4.5). SwiftUI's answer (`TE-H` item 2, `TE-R` item 1). Linux and Windows
   CI owe the confirmation on push; `Backends/SDL`'s `PortableReplay` frame 5
   and `DemoCapture` render the same configuration and are re-checked (record
   §59 §4.5).
3. **A real-window look is owed**: under **A** at the demo's own 920×560 the
   paragraph draws four lines where it drew five. Not one of the fourteen
   (their animation images are 1024², where the paragraph fits); added to the
   still-owed real-window capture (record §03, Record phase).
4. **Two existing tests re-answer, each a T row** (`TE-R` item 4) with its
   retirement row in record §59 §4:
   `aProposalTextInAStackIsShapedOncePerDistinctWidth` (a capped answer is a
   second seam question at the same width, and paint asks `measure` before it
   places: 12/12 → 13/16 at the finite root, 12/21 → 15/27 in the scroll
   viewport, each re-derived by hand in its doc comment), and
   `proposalTextUsesWidthDrivenSwiftUIMeasurement` (its "a height proposal
   does not truncate" arm asserted the claim L5 refutes; now one line at
   (30, 12), and a height of the run's own lines caps nothing). Together with
   spec 3.11 and 3.12 that is **four** T rows for the lane, where spec §8 named
   two.

**Cost if wrong.** A production text squeezed below its lines in a stack now
truncates; the remedy is room or a limit, as in SwiftUI. The paragraph is the
only production text the census found squeezed.

---

## TE-Z — a text beside a `Spacer` is served before the spacer's share: divergence 89 (lane 3)

**Evidence.** `swiftui-text-in-stacks.swift` K1 and K4 (`VStack(spacing: 0)
{ Text(paragraph); Spacer() }` 100 wide: one line at 60, three at 100 — the
height split evenly — with `minLength: 0` the same) against
`swiftui-stack-algorithms.swift` SP8 (`HStack(0){a20; Spacer(); b20}` at 200:
a and b offered (200 − 8) / 2 = 96, the spacer's minimum reserved first —
`CN-C`'s priority −∞). Under the kernel's one rule a text beside a bare
spacer is a group of one offered everything but the spacer's minimum: spec
3.23's arms read **3** lines at 60 (52 offered) and **5** at 100 (92), where
SwiftUI draws 1 and 3; K2 (a rigid 40-tall block beside the text, 2 lines at
80) and K3 (two texts) agree, and so do the 200 arms (6 lines). `TE-R`'s "K1–K4
are exactly that rule … needs no new mechanism" is wrong for the two spacer
arms: SP8 and K1 cannot both hold under one priority rule, and which
mechanism SwiftUI uses to reconcile them is unmeasured.

**The ruling.** **Divergence 89, added, kept, owner none**: a wrapping text
beside a bare `Spacer` in a height-limited stack is offered the height less
the spacer's minimum (`CN-C`), where SwiftUI shares the height with the spacer.
Changing `CN-C`'s priority would move every spacer allocation the demo's
images rest on and is a stack question, not part of task 11's text; the
line-limit rule itself (`TE-H` item 2) is unchanged. Pinned by spec 3.23's two
spacer arms at MetalUI's answer (3 and 5 lines), its 200 arm and its K2 arms at
SwiftUI's. Live count **64 → 65**; next label **90**.

**Cost if wrong.** A paragraph above a `Spacer` in a short stack keeps more
lines than in SwiftUI, and the spacer shrinks to its minimum; nothing
overflows that did not before.

---

## TE-AA — the element surface, as landed (lane 3)

**Evidence.** Spec rows 3.1–3.23 (record §59 §4), probe arms cited per item.

**The ruling** (each a reading the design left implicit):

1. **Weight precedence**: the text's own `fontWeight`, else the environment's,
   else the font's own weight, else the text style's (headline bold, caption2
   medium) — F6d, F2f, X1c. A `nil` own weight inherits the container's
   (spec 3.4's arm).
2. **Italic is additive**: the font's, the text's own or the environment's
   (the nearest writer's `Bool`) makes it italic; `italic(false)` on a `Text`
   adds nothing, so an italic font stays italic — SwiftUI's parameter is
   "whether italic styling is added". Unprobed beyond F4/X2b.
3. **An empty string reserves nothing** (X10: `Text("")` under
   `lineLimit(2, reservesSpace: true)` is SwiftUI's one-empty-line height,
   not two lines); implemented and pinned in spec 3.10. MetalUI's empty line
   is its own 16 pt line (divergence 86), unchanged.
4. **The line cap at paint** is re-derived from the placed node's rect height
   (the leaf's, or a padded text's leaf, or the frame a declared size lowers
   to) with the same function as measurement (`textLines`), so a text whose
   rect is its answer draws exactly the lines measured and a reserved or
   framed box caps nothing more. Its first `measure` repeats layout's shaping
   key, so paint adds a cache lookup, not a shape, unless a cap applies
   (`TE-Y` item 4).
5. **`TextField`/`TextEditor` resolve through the same function** with only
   their own font request — so an environment `fontWeight`/`italic` reaches
   them too, as `.font(_:)` does; their colour stays their own (`TE-D`).
6. **The `dynamicTypeSize` answer is unchanged by construction**: `Font`'s
   text-style table has no size column (`TE-E`), pinned by spec 3.9.
7. **`TextFontRequest.familyAndSize`** gives `fontFamily`/`fontSize` for a
   text-style font too (`.title` reads `nil`/22); a write replaces the whole
   request, weight and design included, with `.custom`/`.system` (`TE-B`
   item 5).

**Cost if wrong.** Each item is one line in `TextStyleResolution.swift` or
`Font.swift`; a probe that separates it changes one test arm.

---

## TE-AB — a `GridRow`'s own alignment was unpinned by 2.1c; fixed by 2.1d (branch check)

**Evidence.** Lane 2's own fix-round verifier ran `V5c` (dropping
`?? plan.rowAlignments[cell.row]?.verticalFactor` from
`nativeGridCellOffsetsY`, the row-alignment fallback, leaving the cell-anchor
and grid-factor fallbacks in place) against the full unfiltered suite at
`35eb357`: it reddened nothing. 2.1c's two grid tests
(`twoRows(t, alignment:)`) call `markNativeGridRow(first)`/
`markNativeGridRow(second)` with no `alignment:` argument, so
`plan.rowAlignments[cell.row]` reads `nil` on every one of 2.1c's arms — the
row-level branch of the offset's three-way fallback (a cell's own anchor,
else its row's alignment, else the grid's) was never exercised, though TE-X
item 2 read as if "the offsets themselves are pinned by 2.1c" covered it.

New probe arm O5 (`docs/probes/swiftui-baseline-offsets.swift`,
`Grid(alignment: .top){ GridRow(alignment: .bottom){ Text 13; Color 40 } }`,
recompiled and re-run twice, byte-identical): SwiftUI reads `first=37
last=37` — the same number as O4's per-cell `.gridCellAnchor(.bottom)`, from
the row's own alignment alone, with no cell anchor set. New test **2.1d**
`aRowsOwnAlignmentMovesTheBaselinesItReportsToo` pins the kernel's own answer
at the same 37 (`markNativeGridRow(row, alignment: .bottom)` in a `.top`
grid); `V5c`, re-run against the committed test, now reddens exactly this
one test in the full unfiltered suite (`Test run with 1706 tests in 3 suites
failed … with 1 issue`) and none of 2.1c's arms, confirming the gap and its
fix.

**The ruling.** TE-X item 2 is corrected to name what 2.1c pins (the grid's
own factor and a cell's anchor, not a row's) and to cite 2.1d for the row
case, disposed by this ruling. No new divergence: MetalUI's
`nativeGridCellOffsetsY` already read the row-alignment fallback correctly
(the census found a missing *test*, not a missing behaviour — the
implementation was right, `V5c`'s mutant was the only thing this round made
red). Live divergence count and spec row totals are unmoved. Next unused
`TE-AC`.

**Cost if wrong.** A `GridRow`'s own alignment silently not reaching
`nativeGridCellOffsetsY` while still reaching `nativeGridCellRects` (the
"copy of a pinned implementation is unpinned" shape — CLAUDE.md's practices)
would place a row's cells correctly but report the wrong baseline for it
under a baseline-aligned `HStack`; nothing in the demo or the repo's trees
reaches this today.

---

# Part 2 — shapes and rendering (`TE-AC` onward)

**Evidence, cited below by arm id:** `docs/probes/swiftui-shapes-and-rendering.swift`
(**new**, revision 2, 2026-09-29): groups P (controls: the ink reader
separates a 100×60 from a 60×60 fill and from nothing; the recording `Layout`
separates a fixed leaf from `Color` at every proposal), S (shape sizing and
placement), F (fill defaults), K (strokes), C (clipping), O (overlays and
backgrounds), I (images), A (`aspectRatio(nil)`). Headless — `ImageRenderer`
at scale 1 and a recording `Layout`, no window ordered front; screen locked;
compiled twice and interpreted once, byte-identical, 77 lines. **Revision 3**
(the critic round, `TE-AQ`) adds O6 and re-ran the whole the same three ways,
byte-identical, 78 lines. `docs/probes/swiftui-grid.swift` GL14 (grids
track) — re-read at design time; **re-run** by the critic round (compiled,
the GL14 line byte-identical to its header).

---

## TE-AC — part 2's scope: every item re-owned to it, and three lanes

**The collection** (`TE-O`'s table, re-grepped 2026-09-29 for `task 11` over
`docs/superpowers/`, `docs/record/`, `Sources/`, `Tests/`, filtered to plan
task 11 and to what part 1 did not dispose of — divergence 77 is `TE-G`'s,
76's remainder `TE-F`'s): the disposition table in spec §3. Every row is
built, kept with a reason, or re-owned with an owner that has the item in its
own text (plan task 12: accessibility, content shapes).

**Three lanes, run in order 1, 2, 3**: **1** the renderer (an ellipse kind on
`MUIRect`, an image primitive, both renderers, the parity harness, the paint
API); **2** the `Shape` surface, fill/stroke, clipping and backgrounds in a
shape (consumes lane 1's ellipse kind); **3** `Image`, `aspectRatio(nil)` and
the `UnitPoint` grid anchor (consumes lane 1's image primitive). Shared
files are named in spec §8; lanes run one at a time.

**Cost if wrong.** An item missed here is found by plan task 15's inventory;
the grep is re-runnable.

---

## TE-AD — what the renderer can draw decides the surface; two capabilities are added, the rest are constraints

**Evidence.** Inventory at `ff2ae92` (spec §2): `MUIRect`'s SDF draws a
rounded rectangle with **circular** per-corner radii, a per-edge border
**inside** the bounds and a rounded-rect mask; `MUIGlyph` draws a tinted R8
sprite. S2, S3, K1–K7, K10–K12 and C1–C4, C7 are all within that primitive
once corner radii are derived from the frame (a `Circle` is a centred square
of radius side/2, a `Capsule` a rounded rect of radius shorter/2, S3 0 px each
against `RoundedRectangle(…, .circular)`); S2's `Ellipse`, K8's ellipse band,
C5's ellipse clip, I1–I12's textures are not.

**The ruling.**

1. **Add an ellipse shape kind** to `MUIRect` in its unused `_reserved` word
   (renamed `shape`): the stride stays 128, `replay.hlsl`'s 8-lane packing
   stays, every scene recorded before this reads shape 0 (a rounded rect), so
   `Expected.swift` and the replay fixtures' rect bytes do not move.
2. **Add an image primitive** (`MUIImage`, `PrimitiveKind.image`) sampling an
   RGBA8 texture carried by the `Scene` (`TE-AF`).
3. **Everything else in spec §9 is a documented renderer constraint**, not an
   approximation drawn silently: continuous corners (divergence 90), an
   ellipse clip (91, a trap), crossing rounded clips (92), `.high`
   interpolation (93), and the not-offered spellings (`Path`, gradients,
   `StrokeStyle`, `cornerSize:`).

**Why not more.** Continuous corners need Apple's curve, which has no closed
form the SDF can carry, and S3 shows it differs by 196 px at r = 20 — a
drawn approximation would be a second, unmeasured divergence. A path
primitive is a tessellator or a coverage rasterizer, a milestone by itself.
An ellipse mask on every primitive (three structs, two shaders, and a mask
intersection with no exact answer) buys one spelling (`clipShape(Ellipse())`)
the task does not name.

**Cost if wrong.** A renderer that could have drawn a constraint exactly is
one later primitive's work; nothing drawn now is wrong without a numbered row.

---

## TE-AE — the ellipse kind: exact distance, SwiftUI's inset-ellipse band

**Evidence.** K8: SwiftUI's `Ellipse().strokeBorder(10)` on 100×60 differs
from "the ellipse minus a concentric 80×40 ellipse" by **518 px** of 2444 —
`strokeBorder` is `inset(by: w/2).stroke(w)`, and the offset curve of an
ellipse is not an ellipse. K7/K6: `stroke(w)` equals `strokeBorder(w)` over
the shape grown by `w/2` (0 px, circle and rounded rect); for an ellipse this
is true by construction (the inset of the outset rect is the original).

**The ruling.** Shape 1 draws, with `h` the half size and `w =
borderWidths.top`: the fill region `d(p, h) ≤ 0`; for `w > 0`, the **band**
`|d(p, h − w/2)| ≤ w/2` in the border colour and the region inside its inner
edge in the background colour; `d` is the **exact** signed distance to an
ellipse (a closed-form or a fixed-iteration solver — one algorithm, the same
in MSL and HLSL — with a circle branch when the axes agree within 1e-4, where
the closed form divides by zero). **Amended by `TE-AQ` item 6**: the
algorithm is fixed as the trig-free three-iteration closest-point method, not
left to the lane. Coverage uses the rect edge's half-pixel
threshold. `cornerRadii` is ignored for shape 1. A stroke is shape 1 over the
outset bounds (spec §5).

**Cost if wrong.** An approximate distance (`f/|∇f|`) would draw K8's
concentric-looking band on thick strokes — the 518 px the probe separates;
test 1.2 is the instrument that tells the two apart.

---

## TE-AF — the image primitive: textures ride in the `Scene`, cached by identity, released when absent

**The ruling.**

1. `MUIImage` = bounds, content mask and its radii, `opacity`, `texture`
   (index into `Scene.textures`), `filter` (0 linear, 1 nearest), `order`,
   `_reserved` — 64 bytes. No source rectangle: an image always samples its
   whole texture, and a `.fill` image's overflow is cut by the mask, not by
   UVs (I10: SwiftUI draws the whole image unless clipped).
2. `ImageTexture` (`MetalUIScene`, imports nothing new): an immutable
   `final class`, width, height, **premultiplied** RGBA8 in sRGB gamma space
   (no linearization, spec §7.8; I12's half-alpha red over white reads
   (255,127,127), the premultiplied source-over answer).
3. **The `Scene` carries its textures**, so `WindowRenderer.finishFrame(scene:
   atlas:)` keeps its signature (`RS-A`) and neither renderer can receive an
   image without its pixels. Each renderer caches one GPU texture per
   `ImageTexture` identity, the cache holding the object strongly (an
   `ObjectIdentifier` cannot be reused while its object lives), and releases
   every entry the frame's scene does not reference — unlike the grow-only
   glyph atlas, an image stream (a changing bitmap every frame) must not
   accumulate.
4. `finalize()` breaks an image run where the texture changes, so the run
   count stays the draw-call count (`DrawListTests`' promise); `isEmpty` reads
   all three arrays (the hazard `aSceneHoldingOnlyAGlyphIsNotEmpty` names).
5. Sampling: linear with clamped edges is the default (I8: SwiftUI's default
   row is exactly bilinear with texel centres at 25 and 75 of a 2-texel image
   over 100 px, equal to `.low` and `.medium`, I11); nearest is a texel
   **read** (`texture.read`/`Texture2D.Load`), so SDL needs no second sampler
   binding.
6. Parity is the replay harness's: fixture **version 2** carries image
   records and textures; `Experiments/SDLGPU` records **frame 6**; CI's two
   `--expect 6` become 7. Inside image quads the tolerance is the glyph one
   (≤ 8, the same sub-texel filter-weight reason `ParityTolerance` records),
   outside ≤ 1.

**Cost if wrong.** A texture cache keyed by anything weaker than a retained
identity can hand a new bitmap an old texture after deallocation — a wrong
image with no error; 1.9 pins eviction, and holding the object pins the key.

---

## TE-AG — `Shape`: SwiftUI's protocol, its `path(in:)` narrowed to what the renderer draws

**Evidence.** S1: every built-in answers its proposal, nil → 10; `Circle`
answers the square of the smaller side (100×60 → 60×60; 100×nil → 100×100).
S2: a `Circle` in 100×60 draws at x 20…80; tall 40×90 at y 25…65. S4: a
radius clamps to half the shorter side (RR(50) on 100×60 = `Capsule`, 0 px);
S5: a negative radius is 0. S3: `RoundedRectangle`'s and `Capsule`'s default
style is `.continuous` (default vs `.continuous` 0 px, vs `.circular` 196 px
at r 20; `Capsule` 230 px).

**The ruling.**

1. `public protocol Shape: Element` (**amended by `TE-AQ` item 1**:
   `Shape: ProposalElement, Sendable`, with default phase implementations)
   with `geometry(in:) -> ShapeGeometry` —
   SwiftUI's `path(in:)` narrowed to the two geometries the renderer draws
   (`.roundedRectangle(_:cornerRadii:style:)`, `.ellipse(_:)`) — and
   `sizeThatFits(_:)` defaulting to S1's rule. An outside type conforms with
   `geometry(in:)` alone (guard G2.1). No `Path` type (spec §9).
2. `RoundedRectangle(cornerRadius:style:)`, `Circle()`, `Capsule(style:)`,
   `Ellipse()`; `RoundedCornerStyle { circular, continuous }`, **default
   `.continuous`**, SwiftUI's spelling and default. `.continuous` is drawn
   circular: **divergence 90** (kept, owner none; pinned by 2.14).
   `cornerSize:` (elliptical corners) and `UnevenRoundedRectangle` are not
   offered (the second is drawable; the task does not name it).
3. **`strokeBorder` is offered on every `Shape`**, where SwiftUI requires
   `InsettableShape`: every geometry MetalUI can draw is insettable, so the
   superset rejects nothing SwiftUI accepts.

**Cost if wrong.** A custom `Shape` from SwiftUI code does not port (no
`path(in:)`); that is the renderer's constraint stated at the type.

---

## TE-AH — `Rectangle` becomes a `Shape`; a bare shape fills with the foreground style

**Evidence.** F1: a bare `Rectangle()` paints (39,39,39), the foreground
style; F2: a container's `.foregroundStyle(blue)` reaches a `Circle`; F3:
`.fill(red)` wins over it; F5: `Rectangle().foregroundColor(red)` is red.

**The ruling.** `Rectangle` conforms to `Shape`. `Rectangle()` — today
`init(color: .surface)` through a default argument — fills with
`foregroundStyle ?? .textPrimary` (part 1's resolution, `TE-D`), closing
`TE-O`'s C9 row. `init(color:)` is **deprecated** toward `.fill(_:)` (one
in-repo caller, converted in the same change); `init(width:height:color:)`
stays, undeprecated, the documented fixed-leaf convenience the demo's preview
uses (its colour is explicit, so no demo pixel moves). **A `Rectangle()` whose
paint a test asserts changes colour** from `.surface` to `.textPrimary` — lane
2's census lists each as a T row with its literal re-derived, never a silent
edit.

**Cost if wrong.** An author who relied on `Rectangle()` painting `.surface`
sees the text colour instead — SwiftUI's answer; the deprecation names the
replacement for the explicit spelling.

---

## TE-AI — fill, stroke and strokeBorder

**Evidence.** F4 (`fill(red).stroke(blue, 10)`: blue over red, the stroke's
ink (−5,−5,110,70)); K1 (stroke centred, square outer corner on a
`Rectangle`); K2 (strokeBorder inside); K3 (default width 1); K5 (layout
unchanged); K6/K7 (stroke = strokeBorder over the outset shape at radius
r + w/2, 0 px); K9 (width ≤ 0 draws nothing); K10 (strokeBorder 40 on 100×60
fills); K11 (`RR(3).strokeBorder(10)`: square outer corner, (0,0) fully red);
K12 (`RR(3).stroke(10)`: round outer corner, (−4,−4) empty, so radius 8).

**The ruling.** `ShapeView<S>` holds its shape and an ordered list of layers
(fill, stroke, strokeBorder), painted in declaration order. strokeBorder(w):
one `MUIRect` over the bounds, border `w`, clear background, outer radius
`r ≥ w/2 ? r : 0`, inner `max(r − w, 0)` (the shader's rule). stroke(w): the
same over the bounds outset by `w/2` at radius `r > 0 ? r + w/2 : 0`. An
ellipse uses shape 1 (`TE-AE`). A width ≤ 0 emits nothing. `StrokeStyle`,
dashes and gradients are not offered (spec §9).

**Cost if wrong.** Corner radii off by the half width at a thick stroke —
what 2.9 and 2.10 pin against K11/K12.

---

## TE-AJ — clipping: `.clipShape`, `.clipped()` and `.cornerRadius` on the proposal path; the legacy `.cornerRadius` stays paint-only (divergence 47 kept)

**Evidence.** C0 (control: an overflowing child paints outside), C1
(`.cornerRadius(12)` clips, corner (1,1) white), C2 (`clipShape(Circle())` on
100×60 → x 20…80), C3 (`.clipped()`), C4 (`cornerRadius(20)` =
`clipShape(RoundedRectangle(cornerRadius: 20))`, 0 px; vs `.circular` 196 px),
C5 (an ellipse clip), C6 (a capsule clip then a circle = the circle alone,
0 px), C7 (capsule), C8 (`clipShape` changes no layout).

**The ruling.**

1. Proposal path: `clipShape(_:)` is one `LayoutModifier` layer, pushing
   `geometry(in: bounds)`'s rect and radii in prepaint and paint exactly as
   `.clip(cornerRadius:)` does (so hitboxes inside are clipped to the rect,
   as today); `.clipped()` is `.clip()`; `.cornerRadius(r)` is
   `.clipShape(RoundedRectangle(cornerRadius: r))`. `ProposalScrollView`'s
   own `cornerRadius(_:) -> Self` stays more specific.
2. Legacy path: `StyledElement.clipShape(_:) -> Self` (**amended by `TE-AQ`
   item 3**: `<S: Shape & Hashable>`) stores the shape on the
   `Decoration` and clips through the existing clip halves
   (`registerAndScopeBody`, `paintDecoration`); no layer, no id level.
3. **The legacy `StyledElement.cornerRadius(_:)` stays paint-only —
   divergence 47 kept, owner none.** A clip is also a hitbox clip
   (`clippedAlsoClipsTheHitboxesInsideIt`), so making the radius clip changes
   hit testing under every rounded legacy box, the demo's sixteen among them
   (`OM-G`) — a frozen area this task must not move. `.cornerRadius(r).clipped()`
   and now `.clipShape(RoundedRectangle(cornerRadius: r))` are the legacy
   spellings of SwiftUI's `.cornerRadius`.
4. **An ellipse geometry in a clip traps** naming **divergence 91** (kept,
   owner none): the mask is a rounded rect on every primitive (`TE-AD`).
   A trap is the explicit form of "not supportable yet" (divergence 88's
   precedent), and a custom `Shape` can return an ellipse at runtime, so the
   check is at the clip, not in the type.
5. `Frame.intersect(_:radii:_:radii:)` gains one **exact** case before its
   square fallback: an inner rounded rect **contained** in the outer rounded
   rect keeps its radii (and the mirror). A rounded rect with circular corners
   is the convex hull of its four corner discs, so containment in a convex
   outer shape is "each corner disc inside it", `sdf_outer(cᵢ) ≤ −rᵢ` — four
   evaluations of the SDF the shaders already use. C6 then reads SwiftUI's
   answer (the old fallback drew a square box). Every case that answered
   before answers the same (the new case runs only where the old code fell
   back). Two rounded clips that **cross** still intersect as the square box:
   **divergence 92** (kept, owner none; one mask per primitive).

**Cost if wrong.** A legacy author porting SwiftUI's `.cornerRadius` sees
unclipped children — divergence 47's documented shape since `OM-G`.

---

## TE-AK — overlays and backgrounds with shapes: audited, two spellings added, nothing rebuilt

**Evidence.** O1 (`background(Capsule().fill(blue))` on an 80×40 content:
the capsule is 80×40), O3 (`overlay(Circle().stroke(4))` on 100×60: a centred
60×60 circle, band 64×64), O5 (a shape background changes no layout), O2
(`background(blue, in: Capsule())` = O1, 0 px), O4 (`background(in: RR 8)`'s
default fill on a white canvas: no ink — the window background style).
**Erratum (`TE-AQ` item 5):** O4 cannot separate "paints white" from "paints
nothing"; O6 (revision 3) re-takes it over a red canvas and reads white
(255,255,255) covering the rounded rectangle, the blue control covering it
blue — the default style **paints**, which is what the ruling below does.

**The ruling.** The existing `.overlay(alignment:content:)` and
`.background(alignment:content:)` (both vocabularies, `LR-FX`, `ID-J`) already
offer their attachment the content's size; 2.22 pins O1, O3, O5 through them
with the new shapes, no code change. Added: `background(_ token:, in:)` =
`background { shape.fill(token) }` and `background(in:)` with token
`.background` (the window's canvas, `ColorToken.background`'s own doc). Each
adds the attachment's identity level (`MC-P`'s `-1`), as the spelled-out form
does.

**Cost if wrong.** O4's evidence was a white-on-white read, now separated by
O6 (it paints); which *token* SwiftUI's background style corresponds to in a
real window is a token mapping (spec §7.9), not measured by a headless
renderer — visible, one line to change.

---

## TE-AL — `Image`: decorative, from pixels or (on macOS) a file

**Evidence.** I1 (a 40×20 image answers 40×20 at every proposal), I9 (80×40
pixels at scale 2 answer 40×20), I2 (`resizable()` answers the proposal, nil
→ its point size), I3–I5 (fit/fill = `aspectRatio` of its point size;
`scaledToFit`/`scaledToFill` equal them, 0 px), I6 (an explicit ratio), I7 (a
non-resizable image keeps its size under `aspectRatio`), I8/I11 (default =
`.low` = `.medium` = bilinear; `.none` nearest; `.high` differs by 880 px),
I10 (a fill image overflows its frame; `.clipped()` cuts it), I12
(premultiplied source-over).

**The ruling.** `Image(decorative: ImageBitmap, scale: Float)` — SwiftUI's
`Image(decorative:scale:)` with `ImageBitmap` standing in for `CGImage` (no
Apple type crosses the portable module); `.resizable()`; `.interpolation(_:)`
with SwiftUI's four cases, `.high` drawn bilinear (**divergence 93**, kept,
owner none). `ImageBitmap(width:height:rgba:)` takes straight alpha (what an
author writes) and premultiplies; `ImageBitmap(contentsOfFile:)` exists where
`ImageIO` does. Not offered (spec §9): a labelled image and its accessibility
(**plan task 12**), SF Symbols (out of the task's scope), asset names,
`Image(nsImage:)`, cap insets and tiling, decoding off Apple. A decorative
image publishes nothing to accessibility — the meaning of its SwiftUI name,
not a new claim.

**Cost if wrong.** A portable app cannot load a PNG without its own decoder;
the pixel initialiser is the portable path.

---

## TE-AM — `aspectRatio` with no ratio takes the child's ideal ratio

**Evidence.** A1 (`Color.aspectRatio(contentMode: .fit)`: ideal 10×10 →
100×60 gives 60×60), A2 (`.scaledToFill()` → 100×100), A3 (a frame with ideal
40×20 → 100×50), A4 (a fixed 40×20 child keeps 40×20), I5/I7 (images).

**The ruling.** `aspectRatio(_ ratio: Double? = nil, contentMode:)`; the
kernel's `NativeNode.aspectRatio` takes an optional ratio and, when nil,
measures the child at nil×nil and uses `width / height`, then proposes
exactly as `CN-G` does for a given ratio. An ideal with a zero or non-finite
ratio passes the proposal through (AR2's branch) rather than dividing by it.
`scaledToFit()`/`scaledToFill()` are `aspectRatio(nil, contentMode:)`.
`public typealias ContentMode = AspectRatioContentMode`. A given ratio keeps
`SA-K` item 4's checks.

**Cost if wrong.** One extra child measurement per nil-ratio node per layout;
`SA-M`'s work counters see it only in trees that use the spelling.

---

## TE-AN — `gridCellAnchor(UnitPoint)`: divergence 64 retires

**Evidence.** GL14: `gridCellAnchor(UnitPoint(x: 0.25, y: 1))` puts a 10×10
cell at (10, 20) in its 50×30 slot. `DD-P` item 4: a plain `UnitPoint`
overload makes every leading-dot nine-point spelling ambiguous;
`@_disfavoredOverload` does not.

**The ruling.** The kernel's cell anchor becomes a factor pair (the nine
`ProposalAlignment` cases map to their factors, so no nine-point placement
moves); `gridCellAnchor(_: UnitPoint)` is added `@_disfavoredOverload`, so
`.topLeading` still resolves to the `ProposalAlignment` overload. **Divergence
64 retires.** Guard G4 (`aGridCellAnchorIsNinePoint`) is inverted and renamed
(G3.1) with a retirement row; its old named mutation (MG4c, the
`@_disfavoredOverload` spelling) is now the implementation.

**Cost if wrong.** None to existing callers; a fractional anchor's placement
is pinned by 3.12 against GL14.

---

## TE-AO — the rendering-facing leftovers: `colorScheme` and colour glyphs

**The ruling.**

1. **No `colorScheme`/`appearance` environment value** (`EV-G`'s item). The
   theme stays scoped and paint-only (`EV-G`); `.theme(_:)` is MetalUI's
   spelling of a subtree's appearance. A readable `colorScheme` would be a
   second appearance source whose coupling to the theme (does a scoped
   `.colorScheme(.dark)` switch tokens?) no probe here measures, and nothing
   in this task reads it. A documented absence, owner none (plan task 15's
   inventory lists it). Not a numbered divergence: nothing exists to diverge.
2. **Colour glyphs stay record §05's row**, a renderer constraint, owner none.
   The image primitive is now the draw path a polychrome sprite would use; the
   missing half is rasterizing `COLR`/`sbix` into RGBA on both text systems,
   a text-system milestone, not this one.

**Cost if wrong.** An author who wants a light/dark-dependent layout reads the
window's appearance themselves; the paint-only theme is unchanged.

---

## TE-AP — tick condition, the demo, pixels

**The ruling.** Part 1 closed the task's first sentence; this part's three
lanes close the second, and spec §9 states every renderer constraint the
third asks for. **The Record phase ticks task 11 if and only if all three
lanes land and every row of spec §3 reads built, kept with its numbered
divergence, or re-owned to an owner that has it** — else a dated note. The
demo is unchanged (spec §7): fourteen images 0 px against `ff2ae92`,
`Expected.swift` unedited, the 1 MB-thread build green. The real-window
capture follows the lock probe; locked at design time, so owed.

**Cost if wrong.** A tick with a clause open overclaims; the condition is
checkable row by row.

---

## TE-AQ — the critic round: twelve findings fixed in the design, three rejections

**Evidence.** Re-runs by this round, 2026-09-29, screen locked
(`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`):
`swiftui-shapes-and-rendering.swift` revision 2 compiled and run unchanged —
all 77 lines byte-identical to its header (every arm, not two); revision 3
adds O6 and re-ran compiled twice and interpreted once, byte-identical, 78
lines. `swiftui-grid.swift` compiled `-O` and run: GL14's line byte-identical
to its header. Reads of `Element.swift`, `ProposalNodeID.swift`,
`NativeElements.swift` (`Rectangle`), `Box.swift` (`Decoration: Sendable,
Hashable`), `Frame.swift` (`insertHitbox`, `intersect`),
`MetalUIShaderTypes.h`, and `git grep -n _reserved`.

**The ruling — each item amends the spec in this commit.**

1. **`Shape` refines `ProposalElement` and `Sendable`**, not `Element`.
   `Element` has three phase requirements and two associated types; a
   `Shape: Element` whose outside conformer writes only `geometry(in:)`
   (G2.1) cannot compile unless an extension supplies them, and a type
   conforming to a protocol cannot be made a `ProposalElement` retroactively
   by a protocol extension — so a custom shape would not sit in an `HStack`.
   `extension Shape` supplies `requestProposalLayout` (a native leaf over
   `sizeThatFits`), `prepaint` and `paint` (the bare fill) with concrete
   state types. `Sendable` is SwiftUI's own `Shape` refinement. G2.1 gains an
   `HStack` arm and a second mutation (`Shape: Element`).
2. **`Rectangle.color` becomes `ColorToken?`** — a public break, ruled: a
   bare `Rectangle()` must record "no colour" to paint the foreground style,
   and a non-optional field could only lie about it. `nil` is the foreground
   style; `Rectangle(width:height:color:)` keeps its `.surface` default and
   stores it (its paint does not move). `git grep` finds no in-repo reader of
   `Rectangle.color`. **Migration**: a reader writes `rect.color ?? <token>`;
   a writer is unchanged (a `ColorToken` assigns to the optional). A
   `ShapeView`'s layers never read the shape's stored colour.
3. **The legacy `clipShape` is `<S: Shape & Hashable>`**, stored in a
   package `Hashable` box over `any Shape & Hashable` on `Decoration`, which
   is `Sendable, Hashable` with public stored fields — an unconstrained
   `any Shape` field would break both. Every built-in shape is `Hashable`.
   The proposal-path `clipShape` keeps SwiftUI's unconstrained signature
   (`LayoutModifier` stores what it likes). The new field **snaps** under
   animation. A departure from SwiftUI's signature on the legacy vocabulary
   only; a custom shape adds `Hashable` to use it there.
4. **`clipShape` clips hitboxes to its geometry's bounding rect — MetalUI's
   rule, stated, not claimed as SwiftUI's.** `insertHitbox` intersects with
   `activeClip` alone (square), as `.clipped()` and `.clip(cornerRadius:)`
   already do (`clippedAlsoClipsTheHitboxesInsideIt`); `OM-AJ` records that
   SwiftUI's `.clipped()` is visual only (divergence 43's family). SwiftUI's
   hit behaviour under `clipShape` is **not measured** by this headless probe,
   so no number is added; owner **plan task 12** (its text names pointer hit
   testing and content shapes). Nothing about existing hit testing moves.
5. **O4 re-taken as O6.** `background(in:)` paints its default style (white
   over red, 5968 px; blue control 5900 px). `TE-AK`'s ruling (fill the
   `.background` token) was right; its evidence was not separating, now
   amended in place as an erratum.
6. **The ellipse distance algorithm is fixed**, not left to lane 1: the
   trig-free three-iteration closest-point method (`sqrt` and arithmetic
   only), identical constants in MSL and HLSL. The analytic cubic and an
   angle Newton need `acos`/`cbrt`/`pow`/`sin`/`cos`, which Vulkan and D3D
   specify loosely — at the ≤ 1 parity tolerance outside images, an edge
   pixel is exactly where they would disagree. Test 1.2's instrument is
   unchanged.
7. **Renaming `MUIRect._reserved` to `shape` re-spells every memberwise
   call** (a Swift-visible C struct field): the rect sites in
   `ShaderTypesBridge.swift`, six `Tests/MetalUIRenderTests` files,
   `SDLWindowRendererTests.swift` and `Experiments/SDLGPU`'s `Replay` — named
   in lane 1's files. A spelling; no answer moves; no T row.
8. **GL14 re-run** (see Evidence) — the design had re-read it only.
9. **`Image(decorative:scale:)`'s spelling departures, ruled:** `scale` is
   `Float` (MetalUI's scale-factor type, `Frame.scaleFactor`), and SwiftUI's
   `orientation:` parameter is not offered (a renderer that samples the whole
   texture upright; a constraint joining spec §9's image row).
10. **Three stale source comments are named for their lanes**:
    `Box.swift:1339` (the bare `cornerRadius` gap "is task 11's" → divergence
    47 kept, `TE-AJ`; lane 2), `UnitPoint.swift:11` and `Grid.swift:338` (the
    nine-point anchor gap owned by task 11 → divergence 64 retired; lane 3).
11. **Count arithmetic made explicit**: 3.10 and 2.20 are one `@Test` each
    (arms inside), so ≈ 1756 stands.
12. **`Frame.intersect`'s new exact case runs after the two existing cases**,
    so case 2's documented inexactness (containment against `outer`'s
    bounding box) keeps its answer; see rejection (b).

**Rejected, with reasons** (the workflow asks rejections to be `LR-`
rulings; this branch's rulings live under `TE-`, so they are recorded here):

- (a) **Splitting lane 1** (two primitives × two renderers is the largest
  lane). Rejected: the ellipse and the image share one shader recompile
  (`compile-shaders.py`, `SOURCE.sha256`), one fixture version bump and one
  parity frame; splitting would bump the fixture format twice and run the
  `shadercross` setup twice. Lane 3 stays small by design.
- (b) **Replacing `intersect`'s case 2 with the exact disc test.** Rejected:
  it would change answers today's code gives (a small inner clip tucked into
  an outer corner) — a silent pixel move in a frozen area, for a case no
  test or production tree reaches (`Frame.swift`'s doc comment). The new
  case only adds answers where the old code fell back.
- (c) **Numbering a clipShape hit-testing divergence now.** Rejected: no probe
  arm measures SwiftUI's hit region under `clipShape` (the screen is locked
  and the probe is headless); item 4 states the rule and its owner instead.

**Cost if wrong.** Item 2 breaks an outside reader of `Rectangle.color` at
compile time, with the migration above; item 3 rejects a non-`Hashable`
custom shape on the legacy path at compile time, never silently.

---

## TE-AR — the renderer, as landed: a 64-byte `MUIImage` without `_reserved`, the premultiply in `ImageTexture`, a separating frame for 1.2, and nearest sampling on a texel boundary (lane 1)

**Evidence.** Lane 1's red commit `afa7a98` and implementation `7e61deb`
(record §60 §3): suite 1718 = 1706 + 12, green; the fourteen offscreen images
0 px against `ff2ae92`, scenes identical; `Experiments/SDLGPU`'s `Replay
--portable --record` 7 frames, frame 6 0 px on SDL's Metal backend through
both the HLSL → SPIR-V → MSL stages and the adapted native MSL;
`PortableReplay --expect 7` PASS on Metal and in a `swift:6.4-noble` aarch64
container on Mesa llvmpipe Vulkan (frame 6: 1038 px Δ1 outside sprites,
37 819 px Δ2 inside image quads); `DemoCapture` PASS; the two HLSL positive
controls fail frame 6 only. A CPU search over K8's own frame
(`anEllipseBorderIsTheStrokeOfTheInsetEllipse`'s instrument).

**The ruling — each item amends the spec in this commit.**

1. **`MUIImage` is 64 bytes with no `_reserved` word.** The spec's field
   list (bounds, content mask, mask radii, then `opacity`, `texture`,
   `filter`, `order`, `_reserved`) sums to 68 bytes, not the 64 it stated;
   the four scalars after the three 16-byte blocks fill the fourth `float4`
   lane exactly, so `_reserved` is dropped and the struct is four whole
   lanes, uploaded by the SDL bridge as recorded (no repacking, unlike the
   120 → 128 rect and 88 → 96 glyph). Pinned by
   `metalAndSwiftAgreeOnTheImageStructAndTheShapeField` (Swift and MSL both
   64) and `thePrimitiveABIIsTheOneTheShadersRead` (`imageStride == 64`).
2. **`ImageTexture` has two initialisers, and the premultiply lives in it**:
   `init(width:height:premultipliedRGBA:)` stores the bytes, and
   `init(width:height:straightRGBA:)` premultiplies (`(c × a + 127) / 255`)
   first — test 1.7 and mutation M1g name `ImageTexture` as the premultiply
   site. Lane 3's `ImageBitmap` may build its texture through the straight
   initialiser rather than premultiplying a second time.
3. **Test 1.2 uses 120×40, border 16, not K8's 100×60, border 10.** At K8's
   frame the inset-band model and the concentric-hole model classify pixel
   centres at most **0.11 px** apart (measured by the test's own CPU search,
   brute-force distance over 4000 curve points): K8's 518 px are antialiased
   coverage summed over the edge, and no pixel there separates the models by
   a margin a GPU's rounding cannot blur. At 120×40, border 16, the search
   finds pixel (19, 19), classified oppositely with a 1.04 px margin (the
   test requires 0.9), and the renderer follows the band. The instrument
   is unchanged in kind — the test still `#require`s a separating pixel
   before asserting — only its frame moved. M1b (the concentric band)
   reddens it.
4. **The ABI check for the new fields is its own kernel, `image_abi_probe`**
   (out slots 0–13), so `abi_probe`'s two 32-slot readers
   (`metalAndSwiftAgreeOnSharedStructLayout`,
   `metalAndSwiftAgreeOnTheGlyphStructLayout`) keep their buffers. M1j (the
   probe reading `order` for `shape`) is applied to that kernel.
5. **A nearest-sampled texel boundary that falls exactly on a pixel centre
   is backend-dependent — a renderer constraint, stated, not a divergence
   from SwiftUI.** Frame 6's first draft put the nearest image's column
   boundary at x = 250.5; Mesa llvmpipe and Apple's GPU picked opposite
   texels there (55 px, Δ97 — a full-contrast texel pair). Which texel a
   pixel centre exactly on the boundary reads is decided by the
   implementation's interpolation rounding, on every backend including
   SwiftUI's. Frame 6 now places the boundary at 250.25 (0 px on SDL Metal,
   Δ2 on llvmpipe inside image quads), tests 1.6 and S1.2 keep their
   boundaries between pixel centres, and spec §9 gains the row. Owner none.
6. **An ellipse band at least as wide as the shorter diameter fills the
   whole ellipse in the border colour** — the rounded rectangle's K10 rule
   ("a border wider than half fills") carried to the ellipse kind, where the
   inset ellipse would otherwise have a non-positive semi-axis. MetalUI's
   choice: no probe arm measures SwiftUI's `Ellipse().strokeBorder` past
   that width. The circle branch (axes equal within 1e-4, absolute, in
   pixels) and a non-positive half size (no coverage) are the other two
   guards; all three are the same statements in `shaders.metal` and
   `replay.hlsl`.
7. **The texture cache is updated before `Renderer.encode`'s empty-scene
   return**, so a frame with nothing to draw releases every cached texture
   too; the SDL renderer releases in `finishFrame` for the same reason. A
   frame whose texture upload fails is not drawn (`finishFrame` returns
   `false`) rather than drawn with a missing texture.
8. **Parity**: `ReplayFixture.spriteMask()` is the glyph quads plus, since
   version 2, the image quads; `parity(of:)` judges ≤ 8 inside it. The live
   comparison in `Experiments/SDLGPU` keeps frames 0–5 at one UNORM step for
   every pixel, as before, and judges frame 6 by fixture parity.
   `PortableReplay`'s line now counts images and says "sprites".
9. **Re-spellings beyond spec §8's list, no answer moved**: two more
   `MUIRect` memberwise sites (`Tests/MetalUIPortableTextTests/EmitLinesTests.swift`,
   `EmitParameterTests.swift`); an exhaustive-switch arm in
   `SceneFinalizeIdentityTests`' `emit` and `DecorationPaintTests`'
   `paintPositions` (neither emits an image). `git grep -n _reserved` after
   the rename lists only `MUIGlyph` fields (its `_reserved`, the glyph
   memberwise calls) and the header comment naming the old word.
10. **One retained test's literal moves (a T row)**:
    `sceneSideTablesArePlainIntArraysThatKeepCapacityAcrossClear` counted four
    `[Int]` side tables; the image kind adds a sequence and a layer table, so
    it reads six, and it now emits images too (otherwise their tables' capacity
    reads 0). Its subject — plain arrays keeping capacity across `clear()` —
    is unchanged. `Backends/SDL`'s `ReplayFixtureTests` (outside the root
    count) re-spell for version 2: the version bytes read 2, a truncated or
    wrong version is `unsupportedVersion(1)`, the run-kind offset gains the
    fifth stride and two empty sections, an unknown kind is 3 (2 is an image),
    and `strideMismatch` carries the image stride.
11. **The SDL workflow triggers on `Sources/MetalUIRender/**`** too: every
    fixture's reference pixels are the Metal renderer's, and frame 6 is its
    two new capabilities, so a shader change must re-run the replay.

**Cost if wrong.** Item 1: a 68-byte struct would have needed repacking on
SDL and broken the "four lanes" read in `replay.hlsl` — the ABI tests pin 64
on both sides. Item 5: an image scaled so that a texel boundary lands on a
pixel centre can differ between backends by a full texel contrast at those
pixels; the parity mask does not hide it (Δ97 > 8), so a frame that did so
would fail CI loudly rather than pass wrong.

---

## TE-AS — shapes, fill/stroke and clipping, as landed: a `nonisolated` `sizeThatFits`, the clamp in the geometry, M2v's instrument moved, and one retained guard re-answered (lane 2)

**Evidence.** Lane 2's red commit `c73ab50` and implementation `05d6ea0`
(record §60 §4): suite 1743 = 1718 + 23 + 2 guards, green after `swift
package clean`; the fourteen offscreen images 0 px against `ff2ae92`, scenes
identical; the mutation table of record §60 §4 (every named mutation run on
the whole unfiltered suite).

**The ruling — each item amends the spec in this commit.**

1. **`Shape.sizeThatFits(_:)` is a `nonisolated` requirement** (spec §4 said
   `func`). The kernel's leaf measure is a `@Sendable` nonisolated closure
   (`ProposalMeasureFunction`), and `Shape` inherits `@MainActor` from
   `Element`, so a main-actor requirement could not be called from it. The
   default and every built-in override are `nonisolated`; an outside
   conformer that overrides it writes `nonisolated` too. `geometry(in:)`
   stays main-actor (read in prepaint and paint only). G2.1's positive
   writes `geometry(in:)` alone and compiles.
2. **`ShapeLayout` is the public `LayoutState` every shape shares**, and
   `Rectangle.Layout` — a public nested struct until now — is a typealias of
   it, so `Rectangle`'s own `requestProposalLayout`/`paint` and the `Shape`
   defaults infer one associated type. No in-repo reader named
   `Rectangle.Layout`'s members (it had one internal field); a public
   spelling change, listed with `TE-AQ` item 2's break.
3. **The radius clamp lives in `ShapeGeometry.roundedRectangle(_:cornerRadii:style:)`**,
   not in `RoundedRectangle`: each radius clamps to `0…min(w, h)/2`, so an
   outside shape's over-large radius is clamped as S4/S5 read for the
   built-in (2.3's last arm). M2c (no clamp) is applied there.
4. **A legacy `clipShape` wins over `clipsContent`** when both are set: the
   geometry of every built-in lies inside the box, so the shape alone is the
   intersection. `Decoration.clipShape` is internal (`escapesOpacity`'s
   precedent), a `ClipShapeBox` over `any Shape & Hashable` whose `==` opens
   the existential and compares by the concrete type's synthesized `==`;
   `Decoration.clipRegion(in:)` is the one reader of both fields, called by
   both clip halves. The field snaps under animation (nothing interpolates
   it). Hitboxes inside are cut to the geometry's bounding rect (2.18),
   `TE-AQ` item 4's rule.
5. **`Frame.intersect`'s containment case** (`roundedRect(_:radii:liesInside:radii:)`)
   evaluates the rounded-rect SDF at each corner-disc centre with radii
   clamped to half the shorter side, as the shader clamps, and accepts a
   disc reaching **1e-4 pt** past the boundary — C6's circle is tangent to
   the capsule, and the tolerance absorbs float rounding there. The mirror
   (outer inside inner) returns the outer's radii. Both run after cases 1
   and 2, so their answers stand (2.20's case-2 arm).
6. **M2v's instrument is moved** (spec §8 said "O3's band moves"). The
   centred O3 cannot see a `Circle` answering its proposal: the geometry
   centres its square in whatever rect it is given, so the band reads
   (18, −2, 64, 64) either way. 2.22 gains a `.topLeading` overlay arm —
   derived from S1 and the overlay's alignment (a kernel placement, not a
   SwiftUI claim): the circle's own 60×60 at the corner, its band at
   (−2, −2); a proposal-answering circle puts it at (18, −2). M2a (the
   override removed) and M2v (its body answering the proposal) are the same
   answer by two spellings and redden the same tests.
7. **One retained guard re-answers — a T row**:
   `theLegacyAndProposalDecorationModifiersDoNotCollide` asserted that
   `HStack { … }.clipped()` does not compile ("`clipped()` stays
   legacy-only"). `TE-AJ` item 1 adds SwiftUI's proposal `.clipped()` (probe
   C3), so that spelling now compiles: it moves into the `both` fixture's
   proposal half (still inferring the proposal wrapper, while the legacy
   half's `clipped()` still infers `Box` — its `-> Box<EmptyGroup>` return
   type is the assertion), and `crossed` is re-spelled with
   `hoverBackground(_:)`, still legacy-only. Red on the skeleton
   (`DecorationCompileGuards.swift:211`, the fixtures agreeing); the twin of
   its G3b mutation for the new spelling (MG3b′, `hoverBackground` declared on
   `ElementGroup`) reddens it again (record §60 §4).
8. **The `Rectangle()` census gives no T row.** 79 spellings at `ff2ae92`: 5
   in `Sources` comments, 38 in typecheck-guard fixtures (compile only), 19
   in `ElementGroupTrapTests` (construction and traps), 9 in `HitRegionTests`
   comments, 5 in `ProposalModifierValidationTests` (a render asserting a
   probe leaf's bounds) and 3 in `ScrollToTests` (layout and offsets) — none
   asserts a bare `Rectangle()`'s painted colour. The one `Rectangle(color:)`
   caller (`rectangleUsesSwiftUIShapeProposalSizing`) is re-spelled
   `Rectangle().fill(.accent)` and asserts bounds only; its answer does not
   move.
9. **Five tests are green on arrival**, each with a mutation that reddens it:
   2.6 (the skeleton's `ShapeView` painted its fill layers — it had to, or
   the re-spelled `rectangleUsesSwiftUIShapeProposalSizing` indexed an empty
   scene and truncated the run), 2.14 (the skeleton already defaulted
   `.continuous` and drew no style), 2.17 (the skeleton's `clipShape` was
   already paint-only), 2.21 (divergence 92 pins the existing square
   fallback) and G2.1 (the skeleton's protocol extension). 

**Cost if wrong.** Item 1: an outside shape that overrides `sizeThatFits`
without `nonisolated` fails to compile, naming the isolation — loud. Item 5:
a tolerance a hair too loose keeps an inner radius a hair past the outer
edge, sub-pixel.

## TE-AT — lane 2's fix round: four tests and an arm for five unpinned clauses, the tolerance stated as defensive (lane 2)

**Evidence.** The lane-2 verifier's mutations X1, X2, X3, X7 and X9 each left
the whole unfiltered suite green at `05d6ea0` (record §60 §4); `K10` had no
test (`grep -rn K10 Tests` empty). Fix round `a420975`: 1747 = 1743 + 4, green;
each new test red under its mutation on the whole unfiltered suite (record
§60 §4's table).

**The ruling.**

1. **Five clauses gain a pin** (spec §8's lane-2 table gains the rows):
   2.15b `aProposalClipShapeCutsTheHitboxesInsideIt` — the proposal
   `.clipShape`'s **prepaint** half (`OM-AI`: a copy of the legacy half's
   pinned hitbox cut is unpinned), through a `ProposalScrollView`'s
   scroll-region hitbox, (0, 0, 100, 60) cut to (20, 0, 60, 60) under
   `.clipShape(Circle())` (X7); 2.18b `aLegacyClipShapeWinsOverClipped` —
   `TE-AS` item 4's precedence, in both spelling orders, against a
   `clipped()`-alone control (X1); 2.18c
   `aLegacyClipShapeComparesByItsConcreteShape` — `ClipShapeBox.==` by type
   and by value (X3); an arm in 2.20 — `Frame.roundedRect(…liesInside…)`
   chooses the container's radius by quadrant (X9); 2.13b
   `aBorderWiderThanHalfTheShapeFillsIt` — K10 by pixels through a real
   window, `Rectangle().strokeBorder(40)` on 100×60 byte-identical to its
   `fill`, `strokeBorder(10)` the control (K10a, a shader mutation). K10
   probes a **rectangle** only; an over-wide border on a rounded rectangle or
   an ellipse is not claimed (an ellipse's inset band's outer edge is an
   offset curve, not the ellipse — its `strokeBorder(40)` measured unequal to
   its `fill` at the edge in this round's first draft).
2. **`TE-AS` item 5's tolerance is defensive, not needed for C6** — amended:
   C6's tangency is exact in integers, and removing the 1e-4 pt reddens
   nothing (X2). It stays, unpinned, against a non-integer tangency rounding
   a hair outside; the doc comment on `Frame.roundedRect(_:radii:liesInside:radii:)`
   says so. No non-integer tangent case is added: whether one rounds outside
   is a property of float arithmetic this round did not search for.
3. **`TE-AS`'s citation of "the mutation table of record §60 §4" is made
   true** by writing that section (it was missing when `TE-AS` landed).

**Cost if wrong.** Item 2: a too-loose tolerance keeps an inner radius a
sub-pixel past the outer edge; a too-tight one (none) falls back to the square
box at a non-integer tangency — both sub-pixel or square-corner looks, no
trap.

---

## TE-AU — `Image`, `aspectRatio(nil)` and the `UnitPoint` anchor, as landed: two `SA-J` traps added, a two-row PNG, a kernel `ProposalAnchor`, and one guard inverted (lane 3)

**Evidence.** Lane 3's red commit `346c07d` (13 of its 14 new tests red at
the whole unfiltered suite, 23 issues; 3.5 and both guards green by design)
and implementation `02f1e0f`: after `swift package clean`, `Test run with 1762
tests in 3 suites passed`, **1762 = 1747 + 15** (14 tests and 1 guard); the
fourteen offscreen images 0 px against `ff2ae92`, scenes identical; the
mutation table of record §60 §5 — **17 rows, 16 of which build and redden a
named test on the whole unfiltered suite** (MG3a does not build; MG3a′
replaces it) — plus the fix round's V5 and V9 (record §60 §5, "Fix round"),
which redden the fix round's additions, **1763** tests. Probe arms I1–I12, A1–A4 (`swiftui-shapes-and-rendering.swift`)
and GL14 (`swiftui-grid.swift`, re-run by the critic round) — no new probe:
every SwiftUI value asserted is one of those arms'; the two traps below are
`SA-J`'s rule, not SwiftUI claims.

**The ruling — each item amends the spec in this commit.**

1. **`Image` is a `ProposalElement`**, as spec §4's Vocabulary paragraph says
   and its code block's `public struct Image: Element` did not: it sits in an
   `HStack` and takes every proposal modifier (`.scaledToFit()`, `.clipped()`,
   `.frame`), like `Rectangle` and every `Shape`. Its `Interpolation` default
   is `.low` (SwiftUI's default draws as `.low`, I8/I11).
2. **Two traps are added, each with its own exit test, neither a SwiftUI
   claim** (spec §8's lane-3 table gains the rows): **3.10b**
   `anImageOfANonPositiveOrNonFiniteScaleTraps` — `Image(decorative:scale:)`
   traps unless `scale` is finite and positive, because `pixels ÷ scale`
   would be infinite or negative at every proposal and a stored rect may not
   be infinite (`SA-J`); **3.12b** `aNonFiniteGridCellAnchorTraps` — a NaN or
   infinite `UnitPoint` component traps in `LayoutTree.markNativeGridCell`,
   naming `gridCellAnchor`, because it would store a NaN or infinite cell rect
   at a finite proposal; a finite factor outside `0…1` is accepted (the
   test's control, (1.5, −1), lays out). SwiftUI's answers to both are
   unprobed; relaxing either trap later is additive (`SA-K`). The lane's
   count is therefore **14 tests + 1 guard**, not the spec's 12 + 1.
3. **3.11 writes a 2×2 PNG, not 2×1**: a one-row image reads the same
   top-down and bottom-up, so M3k (rows read bottom-up) could not redden it.
   Its texels are opaque and one fully transparent, so the premultiply is
   exact on every path. **The decoded path premultiplies through
   CoreGraphics**, not `ImageTexture(straightRGBA:)`: `contentsOfFile:` draws
   the decoded image into a premultiplied sRGB RGBA8 bitmap context (which
   also converts a file's colour space to sRGB and reads rows top-down) and
   stores the bytes as premultiplied; a translucent texel's rounding is
   CoreGraphics', unpinned against `ImageTexture`'s `(c × a + 127) / 255`. A
   missing or undecodable file is `nil` (3.11's last expectation).
4. **The kernel's cell anchor is `ProposalAnchor`** (public, `MetalUILayout`:
   `horizontalFactor`, `verticalFactor`, `init(_ alignment:)`), stored per
   node in place of `ProposalAlignment`. **`markNativeGridCell` gains a
   defaulted `anchorPoint:` parameter** on `LayoutTree` and `LayoutPass`
   rather than a new overload, so the "13 registrars each plus the two mark
   functions" count stands; the existing `anchor:` stays and is stored as its
   nine-point factors, and a call passing both writes `anchor` first (the
   first mark on a node stands, `GR-I`). **`GridCellAttribute` gains a public
   case, `anchorPoint(UnitPoint)`** — an outside exhaustive `switch` over it
   stops compiling (migration: add the case); nothing in the repository
   switches over it outside `Grid.swift`. **Three test re-spellings, no
   answer moved, no T row**: two `NativeGridTests` comparisons of a plan's
   internal `anchor` against `.topLeading` now read
   `ProposalAnchor(.topLeading)`, and `GridElementTests`' `anchor(_:_:)`
   helper maps its expected `ProposalAlignment?` through
   `ProposalAnchor.init`. `UnitPoint.swift`'s doc comment and both
   `Grid.swift` comments that named the nine-point gap as plan task 11's
   (the `GridCellAttribute.anchor` case and the modifier, spec §8's
   `Grid.swift:338`) now say divergence 64 is retired.
5. **G4 → G3.1 is a retained guard whose answer inverts, by ruling (`TE-AN`)
   — its retirement row**: `aGridCellAnchorIsNinePoint` asserted that
   `Rectangle().gridCellAnchor(UnitPoint(x: 0.25, y: 1))` does **not**
   compile (its positive control, a leading-dot `.topLeading`, did); it is
   renamed `aGridCellAnchorTakesAUnitPointAndTheNinePointSpellingsStillResolve`
   and asserts the fractional anchor **compiles** and four leading-dot
   spellings both types declare (`.topLeading`, `.trailing`, `.bottom`,
   `.center`) still resolve. Its old named mutation (MG4c, a
   `@_disfavoredOverload` `UnitPoint` overload) is now the implementation;
   its new one is MG3a (the attribute removed). Guard count **107 → 108**
   (G3.2 new; G3.1 renames).
6. **A nil ratio reads the child at nil×nil each time the node proposes**
   — in its measurement and in its placement; the run's measurement cache
   (`SA-H`) makes the second a hit, so the cost is one child measurement per
   node per layout run, plus a counted cache hit (`SA-M`), and only in trees
   that spell it. No existing work-counter literal moved (the suite is green
   with every `SA-M` test unedited). A given ratio's path
   is unchanged, byte for byte (the demo's `.aspectRatio(16.0 / 9.0)`
   included: 0 px).
7. **Mutation spellings, where spec §8's one-line description admits two**:
   M3c is "the quad drawn at the bitmap's pixel size" (the only way a
   correct `drawImage` can be handed unscaled bounds); M3e is "the node
   answers the ratio-shaped proposal when both its axes are concrete" (a
   child's answer ignored — A4's 100×60 reads 100×50); 3.10b's and 3.12b's
   mutations are M3m and M3n (their preconditions removed). **MG3a as
   spelled does not build** — removing `@_disfavoredOverload` makes 27
   leading-dot `gridCellAnchor(.…)` sites in the package's own tests
   ambiguous — so the guard is mutated red by **MG3a′**: MG3a plus those
   sites spelled `ProposalAlignment.…`; its nine-point control then fails
   with `ambiguous use of 'topLeading'` (record §60 §5).

**Cost if wrong.** Item 2: a SwiftUI program passing scale 0 or a NaN anchor
traps here where SwiftUI may draw something; the fix is additive. Item 3: a
translucent texel decoded from a file may differ by one step from the same
straight bytes passed to `init(width:height:rgba:)`. Item 4: an outside
exhaustive switch over `GridCellAttribute` breaks at compile time.
