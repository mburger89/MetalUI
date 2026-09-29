# Text semantics decisions (plan task 11, part 1)

Rulings for [`specs/2026-09-28-text-semantics-design.md`](specs/2026-09-28-text-semantics-design.md),
on `feat/text-semantics` from `169d166`. Ids are **lettered**, `TE-A`…`TE-AA`;
next unused is **`TE-AB`**. A bare `TE-3` is a typo, not a citation. **A round
that appends a ruling moves this line in the same commit.**

**Status, 2026-09-28: DESIGNED; critic round applied (`TE-Q`…`TE-S`).** Plan task 11 is split in two by the workflow
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
   never swept, as `TX-C`/`fonts` require.

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
   offsets themselves against `docs/probes/swiftui-baseline-offsets.swift`:
   two rows at vertical spacing 8 report 25/73 centred (O2) and 13/73 at
   `.top` (O3), a bottom-anchored cell 37 (O4) — every offset 0 (mutation V5)
   reddens it. 2.1c also pins a vertical stack's gaps (O1, 13/49 at spacing 8;
   V4, the cursor without its gaps, reddens it).
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
