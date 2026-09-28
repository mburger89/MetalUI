# Text semantics — design (plan task 11, part 1)

Branch `feat/text-semantics` from `169d166` (plan task 10's tip). Rulings
`TE-A`…`TE-U` in a new decisions doc,
[`../2026-09-28-text-semantics-decisions.md`](../2026-09-28-text-semantics-decisions.md)
(next unused **`TE-Y`**; lane 1 added `TE-T`…`TE-V`, lane 2 `TE-W`, `TE-X`). Evidence: `docs/probes/swiftui-text-semantics.swift`
(**new**, this design; arm ids `F1`, `L5`, `X8` …; its header carries the
recorded output and the reading). Record: `docs/record/59-text-semantics.md`
(written by the lanes and the Record phase).

**Status: DESIGNED; critic round applied** (`TE-Q`…`TE-S`: two new probes,
`swiftui-controlsize-text-render.swift` and `swiftui-text-in-stacks.swift`;
lanes rebalanced; `TE-L`'s stack branch ruled; a stack-compression pin and
census added).

## 1. Baseline

`169d166`, this worktree with its own `.build`: `swift build --build-system
native --build-tests` (0 `error:`, the one `warning:` SwiftPM's deprecation
notice), then unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1644 tests in 3 suites passed`**; the log carries `FR-J
no-argument frame: succeeded=` (guards ran). 0 goldens, **100** typecheck guards
(record §58's figure, `DD-AI`'s counting), **61** live divergences, next label
**86**. Re-taken by this design session.

The probe ran with the screen **locked** (lock probe:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). No arm needs a
window: every measurement is a custom `Layout`'s `sizeThatFits` inside an
`NSHostingView`'s `fittingSize`, or an `ImageRenderer` render.

## 2. Scope

`TE-A` collects every item addressed to plan task 11 and disposes of each;
`TE-O` re-owns the non-text ones to part 2 and plan task 12. Built here:
foreground style (`TE-D`), `Font` and font selection (`TE-B`, `TE-C`), line
limit (`TE-H`), truncation (`TE-I`), multiline alignment (`TE-J`), baseline
alignment (`TE-K`, `TE-L`), `controlSize` on the default font (`TE-F`);
dynamic type is SwiftUI's macOS answer already (`TE-E`); divergences 60, 77,
51 and W2 are decided and kept (`TE-G`, `TE-M`); **86, 87 and 88 are added**.
Live count **61 → 64**.

## 3. Public API (`MetalUI` unless named)

Every spelling is SwiftUI's; each departure is named.

```swift
public struct Font: Hashable, Sendable {
    public static func system(size: Double, weight: Weight? = nil, design: Design? = nil) -> Font
    public static func system(_ style: TextStyle, design: Design? = nil, weight: Weight? = nil) -> Font
    public static let largeTitle, title, title2, title3, headline, subheadline,
                      body, callout, footnote, caption, caption2: Font
    public static func custom(_ name: String, size: Double) -> Font
    public static func custom(_ name: String, fixedSize: Double) -> Font
    public static func custom(_ name: String, size: Double, relativeTo textStyle: TextStyle) -> Font
    public func weight(_ weight: Weight) -> Font
    public func bold() -> Font            // weight(.bold), X1c
    public func italic() -> Font
    public struct Weight: Hashable, Sendable {   // ultraLight … black; value is CoreText's trait
        public static let ultraLight, thin, light, regular, medium, semibold, bold, heavy, black: Weight
    }
    public enum Design: Hashable, Sendable { case `default`, serif, rounded, monospaced }
    public enum TextStyle: Hashable, Sendable, CaseIterable { case largeTitle, title, title2, title3,
        headline, subheadline, body, callout, footnote, caption, caption2 }
}
public enum TextAlignment: Hashable, Sendable { case leading, center, trailing }
extension Text { public enum TruncationMode: Hashable, Sendable { case head, tail, middle } }

extension EnvironmentValues {
    public var font: Font?                          // nearest writer (F6e)
    public var lineLimit: Int?                      // the upper bound of the internal pair (TE-H)
    public var truncationMode: Text.TruncationMode  // .tail
    public var multilineTextAlignment: TextAlignment // .leading
    // internal: foregroundStyle: ColorToken?, fontWeight: Font.Weight?, italic: Bool,
    //           textLineLimit: (min: Int?, max: Int?)
}

extension ElementGroup {           // environment writes, EnvironmentScope<Self>
    func font(_ font: Font?)
    func fontWeight(_ weight: Font.Weight?)
    func italic(_ isActive: Bool = true)
    func foregroundStyle(_ token: ColorToken)
    func foregroundColor(_ token: ColorToken)      // alias (SwiftUI's older spelling)
    func lineLimit(_ number: Int?)
    func lineLimit(_ limit: Int, reservesSpace: Bool)
    func lineLimit(_ limit: ClosedRange<Int>)
    func lineLimit(_ limit: PartialRangeFrom<Int>)
    func lineLimit(_ limit: PartialRangeThrough<Int>)
    func truncationMode(_ mode: Text.TruncationMode)
    func multilineTextAlignment(_ alignment: TextAlignment)
}

extension Text {                  // the element's own (wins over the environment)
    func font(_ font: Font?) -> Text        // nil: the default font, not the inherited one (F6c)
    func fontWeight(_ weight: Font.Weight?) -> Text
    func italic(_ isActive: Bool = true) -> Text
    func foregroundStyle(_ token: ColorToken) -> Text
    // kept: font(family:size:) (an explicit .custom/.system font), foregroundColor(_:);
    // fontFamily / fontSize become computed over the request (TE-B item 5)
}
// ProposalText: the same five, returning ProposalText.
// TextField, TextEditor: font(_ font: Font?) added; font(family:size:) kept; their
// fontFamily/fontSize computed the same way (TE-F item 2).

public enum VerticalAlignment { case top, center, bottom, firstTextBaseline, lastTextBaseline }
```

**Not offered** (`TE-B` item 4, `TE-B` item 6, `TE-D`, `TE-I`, `TE-K` item 5):
`Text.bold()`/`ElementGroup.bold()`, `fontDesign`, `fontWidth`,
`monospacedDigit`, `Font.leading`, `lineSpacing`, `Font(CTFont)`,
`ShapeStyle` foregrounds (`.secondary`, gradients), `Text.foregroundColor(nil)`,
`allowsTightening`, `minimumScaleFactor`, `alignmentGuide`, baseline `Alignment`s.

**Resolution** (lane 3's `TextStyleResolution.swift`, one pure function used by
layout and paint alike):

- font request = the element's own (explicit font / explicit default /
  inherit) → the environment's `font` → the **default font**
  `.system(size: controlSize == .mini ? 9 : controlSize == .small ? 11 : 13)`
  (`TE-F`); then the environment's (or the element's own) `fontWeight` and
  `italic` over it; then `Font` → `FontDescriptor` (a text style through F1's
  table: largeTitle 26, title 22, title2 17, title3 15, headline 13 bold,
  subheadline 11, body 13, callout 12, footnote 10, caption 10, caption2 10
  medium; `custom(_:fixedSize:)` and `relativeTo:` as `size:`, `TE-E`).
- colour = own token → environment `foregroundStyle` → `.textPrimary`.
- limit = environment `textLineLimit` (`TE-H`); lines =
  `min(max ?? ∞, heightLines, natural)` with
  `heightLines = max(1, ⌊h / lineHeight⌋)` for a finite height proposal `h`;
  a limit ≤ 0 is 1; height = `max(lines, min ?? 0) × lineHeight`.
- baselines = `round(ascent)` and `round(ascent) + (lines − 1) × lineHeight`
  (`TE-G` item 4).

## 4. The `TextSystem` seam (`MetalUITextSystem`, lane 1)

```swift
public enum FontDesign: Hashable, Sendable { case `default`, serif, rounded, monospaced }
public struct FontDescriptor: Hashable, Sendable {
    public var family: String?; public var size: Double; public var weight: Double?
    public var italic: Bool; public var design: FontDesign
    public init(family: String? = nil, size: Double, weight: Double? = nil,
                italic: Bool = false, design: FontDesign = .default)
}
public struct TextFontMetrics: Hashable, Sendable {
    public let ascent, descent, leading, lineHeight: Double
}
public enum TextTruncation: Hashable, Sendable { case tail, head, middle }
public enum TextLineAlignment: Hashable, Sendable { case leading, center, trailing }
public struct TextLayoutOptions: Hashable, Sendable {
    public var maxLines: Int?; public var truncation: TextTruncation; public var alignment: TextLineAlignment
    public init(maxLines: Int? = nil, truncation: TextTruncation = .tail, alignment: TextLineAlignment = .leading)
}
protocol TextSystem {
    func resolveFont(_ descriptor: FontDescriptor) -> FontKey                     // new
    func fontMetrics(_ font: FontKey) -> TextFontMetrics                          // new
    func measure(_:font:wrappingAt:options:) -> TextMeasurement                   // gains options
    func placeGlyphs(_:font:wrappingAt:options:origin:scaleFactor:) -> [TextGlyph] // gains options
    func lineRanges(_:font:wrappingAt:options:) -> [Range<Int>]                   // gains options
    // unchanged: caretOffsets, rasterize, beginFrame, endFrame
}
// Extensions keep every old spelling: resolveFont(family:size:), measure(_:font:wrappingAt:),
// placeGlyphs(_:font:wrappingAt:origin:scaleFactor:), lineRanges(_:font:wrappingAt:) — each
// passing FontDescriptor(family:size:) / TextLayoutOptions().
```

Semantics are `TE-C`'s. **Migration note**: a `TextSystem` conformer outside
the package must implement the three new requirements (none exists in this
repository or in `Backends/SDL`).

- **CoreText** (`MetalUIText`): `FontResolver.resolve(_ descriptor:)`
  (system face by weight and design, `CTFontCreateWithName` plus the family's
  nearest-weight face, the italic symbolic trait); truncation through
  `CTLineCreateTruncatedLine` with a `…` token line in the run's font, applied
  in `ShapedText`/`ShapingCache` (the cache key gains the options) so
  `measure`, `placeGlyphs` and `lineRanges` agree by construction; alignment
  as a per-line x offset in `PlacedGlyph`'s walk.
- **Portable** (`MetalUIPortableText`, `MetalUIFreeType`, `MetalUISystemFonts`):
  `FreeTypeFont` reads OS/2 `usWeightClass` and the italic bits
  (`fsSelection`/`macStyle`); `FreeTypeFaceNames` carries them so a lazy face
  (`SF-B`) is selectable without its bytes; `PortableFontResolver` selects by
  family then nearest weight then italic, and `register(design:family:)`;
  `PortableText` gains truncation (a new `Truncation.swift`, its `…` token
  shaped in the text's resolved font through `shapeCascading`, never
  `HarfBuzzShaper` directly — `FB-A`, `TE-C` item 3) and alignment in
  `emitLines`/`placements`; `PortableTextSystem` caches by (string, font,
  width, options).

## 5. The kernel (`MetalUILayout`, lane 2)

`TE-K`. `LayoutMeasurement.firstBaseline`/`lastBaseline` (already declared,
already carried by `frame` and `padding`) are filled for every node kind;
`NativeNode.linearStack` gains `baseline: ProposalTextBaseline?`, a new public
enum `ProposalTextBaseline { case first, last }`; `newNativeLinearStack` and
`LayoutPass.requestNativeLinearStack` gain `baseline: ProposalTextBaseline? =
nil`. Placement reuses the measurement's offsets, so `placeNative` and
`measureNative` agree by construction. `HStack(alignment:)` passes the
baseline for the two new cases; `GridRow`'s registration traps on them
(divergence 88); `LegacyLowering` maps `alignItems.baseline` (`TE-L`).

## 6. What each element does (lane 3)

- **`Text`/`ProposalText`**: resolve (§3) in `requestLayout` and again in
  `paint` (same environment, same answer); the measure closure captures the
  descriptor's `FontKey`, the metrics and the options and answers width
  `min(proposal, widest kept line)`, height per §3, and both baselines; paint
  re-derives the line cap from the leaf's final height
  (`max(1, ⌊h / lineHeight⌋)`, capped by the limit — robust to a reserved or
  framed height) and calls `placeGlyphs` with the options at the measured
  width. The false comment "the height proposal does not truncate" in
  `ProposalText.swift` is corrected (`TE-H` item 2). `Text.proposalLayout()`
  carries the request, not only `fontFamily`/`fontSize`.
- **`TextField`/`TextEditor`**: resolve their font the same way (own,
  environment, default by `controlSize`); nothing else changes (`TE-F` item 2).
- **`Button`**: no code change; its label `Text` follows the environment
  (`TE-F` item 3) — doc comment corrected.

## 7. Demo, pixels, and what must not move (`TE-N`, `TE-P`)

No demo tree writes `font`, a line limit, an alignment, `controlSize`,
`foregroundStyle` or a baseline alignment; every `Text(…).font(size:)` there
stays an explicit font. Expected: **0 px against `169d166` in all fourteen
offscreen images** (`docs/probes/demo-pixels/compare.sh`), taken at each lane's
close and at the Record phase; `DemoFrameDeterminismTests`'s `Expected.swift`
unedited; `everyProductionTreeBuildsOnAOneMegabyteThread` green (lane 3
re-measures the demo's builder frames, since `Text` grows by the request and
its fields); `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green;
`MetalUILayout` imports only `MetalUICore`; 0 `warning:` on both build systems
beyond SwiftPM's notice; `Backends/SDL` builds and runs (21 + 23) with
`PKG_CONFIG_PATH=$PWD/.accesskit`, and a `swift:6.4-noble` container builds the
root package and runs 188 + 22 + 10 (+ any new `MetalUILayoutTests`) if Docker
is available. A moved pixel stops the lane until a ruling names it. **`TE-R`**: `TE-H` makes
every wrapping text vertically flexible in a stack (SwiftUI's answer, probe
K1–K4), so 0 px holds only if no production text is proposed less than its
natural height; lane 3 takes the height census (`TE-R` item 2) before
implementing, and a non-empty census predicts which images move and names each
by ruling.
Real-window capture: lock probe first; locked → owed (record §03).

## 8. Lanes

Three lanes, run in order **1, 2, 3** (**rebalanced by `TE-S` item 1**: font
selection moved from lane 1 to lane 2; lanes 1 and 2 share the three seam files
`TextSystem.swift`, `CoreTextTextSystem.swift`, `PortableTextSystem.swift`,
safe only because they run one at a time). Each lane commits its red tests first
(against a compiling skeleton where a new API is needed), then the
implementation, then a mutation table: commit, mutate from a copy, run the
**whole unfiltered suite**, `git status --short` after each restore, name every
reddened test. Each new typecheck guard is mutated red once. **`swift package
clean` before re-taking counts** after a lane adds stored properties to a public
type crossing a module boundary — lane 1's `FontDescriptor`/options in
`ShapingCache`'s key, lane 2's `NativeNode` case payload, lane 3's `Text`,
`ProposalText`, `TextField`, `TextEditor` and `EnvironmentValues` fields. Each lane appends
its readings to `TE-` as a new lettered ruling (moving the "next unused" line)
and its section to record §59.

### Lane 1 — the seam's layout options and metrics, on both text systems

**Files** (only these in `Sources/`): `MetalUITextSystem/TextSystem.swift`
(`TextFontMetrics`, `TextLayoutOptions` and its enums, `fontMetrics`, the
`options:` requirements and the old spellings' extensions);
`MetalUIText/{CoreTextTextSystem,ShapedText,ShapingCache,PlacedGlyph}.swift`;
`MetalUIPortableText/{PortableTextSystem,PortableText,LineEmission,LineBreaking}.swift`
and new `MetalUIPortableText/Truncation.swift`.
**Tests**: new `Tests/MetalUIPortableTextTests/TruncationOracleTests.swift`,
new `Tests/MetalUITests/TextSystemCompileGuards.swift` (G1.1), arms appended to
`Tests/MetalUITests/TextSystemSeamTests.swift`, and
`Tests/PortableTests/Tests/PortableTextDeterminismTests/` (new pins, macOS-recorded).
Rows **1.1–1.4 below belong to lane 2** (`TE-S` item 1); the table keeps their
numbers so every citation stands.

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `thePortableResolverPicksCoreTextsFaceForEveryWeightAndItalic` — every (family, weight, italic) over the installed multi-weight families found (`#require` ≥ 2 families of ≥ 4 faces) equals CoreText's PostScript name, **except exactly the ten rows `TE-W` item 4 pins** (590 of 600 over 30 families); registering the lazy faces loads none, one request loads its answer (**amended by `TE-W`**) | portable ignores `weight` | M1a: nearest weight → the family's first face |
| 1.2 | `aWeightOrItalicTheFamilyLacksDrawsTheRegisteredFaceUnchanged` — Noto Sans Regular only, bold/italic → `NotoSans-Regular` on both systems (F2h, F4b) | portable picks another registered face | M1b: fall back to the cascade's first face |
| 1.3 | `theSystemDescriptorIsNSFontsSystemFontAtEveryWeightAndDesign` — CoreText, nine weights (F2) and three designs (F3) by PostScript name | `weight`/`design` ignored | M1c: weight dropped on the system path |
| 1.4 | `aCustomFamilysWeightSelectsItsNearestFace` — Helvetica Neue per X2 (semibold → Medium, heavy → Bold, `HelveticaNeue-Bold` + light → Light) | exact match only | M1d: no nearest, request's face kept |
| 1.5 | `thePortableTruncationKeepsCoreTextsStringInEveryMode` — corpus (Latin with kerning pairs and spaces, CJK, Arabic, a combining mark) × widths × modes: kept string and width equal `CTLineCreateTruncatedLine`'s | no portable truncation | M1e: keep trailing whitespace before a tail token (X6); M1f: middle split one grapheme off |
| 1.6 | `theDroppedLinesAreTruncatedAsOneLineAfterTheKeptOnes` — `maxLines: 2` at 100: line 1 kept, the rest truncated as one line, both systems' glyphs equal (X8); a limit of 0 or −1 equals 1 at the seam on both systems (`TE-H` item 3, arm added in `TE-V`'s round; dropping the clamp traps here) | untruncated | M1g: truncate line n−1's own text only |
| 1.6b | `aHardBreakEndsTheTruncatedLineAtItsParagraph` (**added by `TE-T`**) — the last kept line is the rest's first paragraph: "Ready\nSet\nGo" at `maxLines: 2` draws "Set…" in tail, "Set" in head/middle; an overflowing paragraph is CoreText's truncation of it alone; an EMPTY last paragraph takes no token in any mode, glyphs and `measure` ("A\n\nB" at 2, "\nB\nC" at 1; **`TE-V`**, E5); both systems | the whole rest truncated as one line | M1l: truncate the whole rest (E1's tail and E4's head/middle redden) |
| 1.6c | `aWidthNarrowerThanTheTokenKeepsTheLongestPrefixThatFits` (**added by `TE-T`**) — "Hello" at 10 and 4 draws "H", no token, every mode, both systems | nothing drawn | M1m: draw nothing when the token does not fit |
| 1.5b | `aRightToLeftHeadTruncationKeepsOneClusterLessThanCoreText` (**added by `TE-U`**) — the pinned, unmatched class: one Arabic head case, both answers glyph for glyph; 1.5 requires every difference to be in this class and their count to be 38 | — (pins both answers) | M1g reddens it (the Apple answer moves) |
| 1.7 | `theSeamsLayoutOptionsPlaceTheSameGlyphsOnBothSystems` — limit × mode × alignment through `placeGlyphs` on Noto Sans at scales 1 and 2 | options ignored | M1h: portable alignment factor 0 |
| 1.7b | `aLineIsAlignedByItsWidthWithoutItsTrailingWhitespace` (**added in `TE-V`'s round**) — "Alpha beta " (line 1 at 100) centred and trailing, both systems, against `(100 − (L − T)) × ½, 1` from a `CTLine` built in the test (A5), exact at scale 64 | — | V1: centre/trailing factors swapped on both systems; V3: trailing whitespace counted on both |
| 1.8 | `theSeamsMetricsAgreeOnBothSystems` — `fontMetrics` of Noto Sans at 11, 13, 17, 26 equal | no requirement | M1i: portable `lineHeight` rounded to nearest |
| 1.9 | `anUnspecifiedWidthCutsKeptLinesWithoutAnEllipsis` — `"A\nB\nC"`, `maxLines: 2`, width `nil`: two lines, no token glyph (L4) | a token appended | M1j: token at `nil` width |
| 1.10 | `measureAnswersTheWidestKeptLine` — width is the widest of the kept (and truncated) lines, height `kept × lineHeight`, both systems; one system asked the same string and width under two option sets, in either order, answers each set's own (the cache key; arm added in `TE-V`'s round, V2 reddens it) | widest of all lines | M1k: widest over every line |
| 1.11 | `truncatedAndAlignedEmissionIsByteIdentical` (`Tests/PortableTests`) — emission of 1.6/1.7's cases, recorded on macOS (the bold-request half is lane 2's 1.12) | no expected values | recorded pin; Linux/Windows CI confirm |
| G1.1 | `theSeamsNewSpellingsArePublicAndTheOldOnesStillCompile` — plain `import MetalUITextSystem`: old and new `measure`/`placeGlyphs`/`lineRanges` spellings and `TextLayoutOptions(maxLines:truncation:alignment:)` compile; control: `TextLayoutOptions(truncation: .ellipsis)` fails | — | MG1: `TextLayoutOptions.init` made `internal` (**does not build**: `emitLines`' public default argument references it; replaced by **MG1b**, the old `measure` extension made `package`, record §59 §2) |

`theCoreTextAndPortableSystemsDrawTheSameSprites` and every existing seam,
oracle and portable pin must stay green unedited (the old spellings are the
default options).

### Lane 2 — font selection on both systems; baselines in the kernel, and the legacy `baseline` fields

**Font selection files** (`TE-S` item 1): `MetalUITextSystem/TextSystem.swift`
(`FontDesign`, `FontDescriptor`, `resolveFont(_:)` and the
`resolveFont(family:size:)` extension); `MetalUIText/{CoreTextTextSystem,FontResolver}.swift`;
`MetalUIPortableText/{PortableTextSystem,PortableFontResolver}.swift`;
`MetalUIFreeType/FreeTypeFont.swift`; `MetalUISystemFonts/SystemFonts.swift`.
**Font selection tests**: rows 1.1–1.4 above, in new
`Tests/MetalUIPortableTextTests/FontSelectionOracleTests.swift` and
`Tests/MetalUITextTests/FontDescriptorResolutionTests.swift`; **1.12**
`aWeightedRequestOnARegularOnlyResolverEmitsTheRegularFaceByteIdentically`
(`Tests/PortableTests`, macOS-recorded, Linux/Windows CI confirm); **G1.2**
`theFontDescriptorSpellingIsPublic` in `TextSystemCompileGuards.swift` — plain
import: `resolveFont(FontDescriptor(size: 13, weight: 0.4, italic: true,
design: .serif))` and `resolveFont(family:size:)` compile; control
`FontDescriptor(size: 13, weight: .bold)` fails (the seam's weight is a
`Double`, `Font.Weight` is `MetalUI`'s); **MG1c** (lane 1 took the name MG1b): `FontDescriptor.init` made
`package`.

**Baseline files**: `MetalUILayout/{LayoutTree,NativeGrid,ProposedSize}.swift`;
`MetalUI/{StackAlignment,NativeElements,Grid,Passes,LegacyLowering,LayoutAuthority,Style}.swift`
(`Style.swift`: doc comment only). **Tests**: new
`Tests/MetalUILayoutTests/BaselineMeasurementTests.swift` (portable CI runs
it), new `Tests/MetalUITests/{BaselineAlignmentTests,BaselineCompileGuards}.swift`,
edits to `LayoutAuthorityTests.swift`, `LoweringContainerTests.swift`,
`GridElementTests.swift` (the exit test). Leaves report baselines through
`newNativeLeaf`/`requestNativeLeaf` closures — **no `Text`** (lane 3 wires it).

| # | test | red before | mutation |
|---|---|---|---|
| 2.1 | `everyNodeKindReportsItsBaselineAsSwiftUIDoes` — B1/X3 per kind: ZStack of 40×40 and a (16, first 13) leaf → 25 (B1k); overlay/background keep the primary's (X3g, X3h); fixedSize/priority/aspectRatio pass through; spacer/scroll `nil`; custom what its `sizeThatFits` returns (**`TE-X` item 1**: `nil` unless it reports one); stacks min/max at offsets (B1g 13/41, B1h 20/25, X3a 20/25, B1p 23); a one-cell grid 13 (X3i) | `nil` everywhere but frame/padding | M2a: stack takes its first child's (X3a → 25); M2b: attachment takes the overlay's (X3h); M2c: a text-less child counted as its height (B1p → 10) |
| 2.1b | `anInfiniteAnswerNeverMakesABaselineNaN` (**added by `TE-X` item 6**, exit `.success`) — one and two greedy frames over a text inside an `HStack` (factor, first, last) inside a two-child `VStack`: no NaN trap, and the row reports no baseline at its infinite probe | the run traps (checkpoint 2) | M2y: the frame's NaN guard dropped; M2x: the combination's finite guard dropped |
| 2.2 | `anHStackAlignedByFirstTextBaselinePlacesAndSizesAsSwiftUI` — B2 first: 44 tall, offsets 12/0/12/15 | factor alignment | M2d: height = max child height; M2e: a text-less guard read as 0 |
| 2.3 | `anHStackAlignedByLastTextBaselinePlacesAndSizesAsSwiftUI` — B2 last: 34, 16/4/0/19 | — | M2f: `.last` reads `firstBaseline` |
| 2.4 | `existingStackAlignmentsAnswerUnchanged` — the same children, reporting baselines, under `.top`/`.center`/`.bottom`: B2's top and centre rows (32; 8/1/0/11) | — (green before and after: the control) | M2g: baseline alignment used whenever a child reports one |
| 2.5 | `aBaselineAlignedStackReportsTheMinAndMaxOfItsChildren` — B2's stack rows: first-aligned 25/41, last-aligned 13/29 | `nil` | M2h: a stack's first = its last |
| 2.6 | `aVerticalStackWithATextBaselineTraps` (exit test) | no trap | — |
| 2.7 | `hStackTextBaselineCasesReachTheKernel` — `HStack(alignment: .firstTextBaseline/.lastTextBaseline)` over synthetic leaves, element bounds equal 2.2/2.3's | cases do not exist | M2i: the cases mapped to `.bottom` |
| 2.8 | `aGridRowWithATextBaselineAlignmentTraps` (exit test; `stderr` names divergence 88) | lays out at a factor | — |
| 2.9 | `aLegacyBaselineRowLowersToFirstTextBaselineAndAColumnToItsStart` — `Row{…}.alignItems(.baseline)` over baseline-reporting leaves places as 2.2; a `Column` as `flexStart`; empty report | reported | M2j: column lowers as centre |
| 2.10 | `everyReportNamesALiveOwnerOrIsRefusedByName` — **T row** (amended by `TE-S` item 2): the table keeps **265** entries; its 16 baseline rows (5 `alignItems.baseline`, 11 `alignSelf.baseline`) change owner from `"plan task 11"` to `nil` | — | M2k: restore `"plan task 11"` |
| 2.11 | `anAlignSelfBaselineIsConsumedUnderABaselineRowAndRefusedByNameElsewhere` | always reported | M2l: consume it everywhere |
| 2.12 | `everyContainerFieldEitherLowersOrIsReportedByName` — **T row**: its `baseline` arm becomes a row-lowering and a column-lowering arm, and a `Stack` (`display: .stack`) arm still reports `stack.alignItems.baseline` (`TE-L`, `TE-S` item 2) | — | M2m: report `alignItems.baseline` again on a row; M2n: lower it on a stack display (the stack arm reddens) |
| 2.13 | `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` — **T row, added by `TE-X` item 3**: the report reads `[gap.percent, size.percent, inset]` (was `[gap.percent, alignItems.baseline, size.percent, inset]`); the trap still names `box.gap.percent` | — | M2m reddens it (the row restored) |
| G2.1 | `aTextBaselineIsAVerticalAlignmentButNotAHorizontalOne` — plain import: `HStack(alignment: .firstTextBaseline)` compiles; control `VStack(alignment: .firstTextBaseline)` fails | — | MG2: `firstTextBaseline` added to `HorizontalAlignment` (does not build: an exhaustive switch; **MG2b** adds the switch arm too) |

Every existing stack, grid, lowering and depth test stays green unedited
except the two T rows (three since `TE-X` item 3: 2.13); `SA-M`'s work literals must not move (baselines are
computed from answers already in hand — the lane states it and a work-counter
test proves it).

### Lane 3 — the element surface

**Files**: new `MetalUI/{Font,TextModifiers,TextStyleResolution}.swift`;
`MetalUI/{Text,ProposalText,EnvironmentValues,TextField,TextEditor,Button}.swift`
(`Button.swift`: doc comment only). **First, before any source change**: the
height census, `docs/probes/text-semantics-height-census.patch` (`TE-R` item
2), applied in a scratch worktree, its rows recorded in record §59 and the
patch committed under `docs/probes/`, never to `Sources/`. 3.23 goes in
`LineLimitTests.swift`. **Tests**: new
`Tests/MetalUITests/{FontTests,ForegroundStyleTests,LineLimitTests,TruncationTests,TextAlignmentTests,TextBaselineTests,TextCompileGuards}.swift`;
edits to `EnvironmentScaleAndSizeTests.swift` (T1.7), `ButtonTests.swift`
(1.2), `EnvironmentTests.swift` (none edited; 3.9 is new beside it). Literals
are derived from the frame's text system (its metrics and `measure`), never
typed from SwiftUI's numbers where MetalUI's line height differs (divergence
86); SwiftUI's numbers are used only where the two agree, and each test says
which.

| # | test | red before | mutation |
|---|---|---|---|
| 3.1 | `aTextStyleResolvesToMacOSsFace` — all eleven styles resolve to F1's (size, weight) `FontKey` | `Font` absent | M3a: title2 17 → 18 |
| 3.2 | `theEnvironmentFontReachesATextAndTheTextsOwnWins` — F6a, F6b, F6e | — | M3b: environment read before the text's own |
| 3.3 | `aTextsNilFontIsTheDefaultNotTheInheritedOne` — F6c | — | M3c: `nil` means inherit |
| 3.4 | `fontWeightAndItalicApplyOverWhicheverFontTheTextResolves` — F6d, F2f, X1c | — | M3d: environment weight dropped under an own font |
| 3.5 | `theLegacyFontSpellingIsAnExplicitFont` — `font(size: 22)` inside `.font(.title)` stays 22; `fontSize`/`fontFamily` read back 13/`nil` unconfigured and set an explicit font | — | M3e: `font(family:size:)` stores "inherit" |
| 3.6 | `aContainersForegroundStyleReachesATextAndTheTextsOwnWins` — C2–C6 on the scene's glyph colours | — | M3f: environment before own |
| 3.7 | `aProposalTextReadsTheEnvironmentsFontAndForegroundStyle` | — | M3g: `ProposalText` skips the environment |
| 3.8 | `aLineLimitCapsLinesAndAnswersTheWidestKeptLine` — L1's shape: 1, 2, 3, `nil`, 0 (as 1), −1 (as 1), environment nearest writer (L6b) | limit ignored | M3h: limit not passed to the seam |
| 3.9 | `noFontRespondsToDynamicTypeSize` — F7: `.body`, `.title`, default, `.custom(relativeTo:)`, `.system(size:)` at four sizes; positive control a 26 pt font | — (green: SwiftUI's answer, pinned) | M3i: text styles scaled by the size |
| 3.10 | `reservesSpaceAndARangesLowerBoundPadTheHeight` — L2, L3 (height padded; width and last baseline kept) | — | M3j: `min` ignored |
| 3.11 | `controlSizeReachesTheDefaultFontButNoControlsChrome` — **T row**, renamed from T1.7 `controlSizeReachesNoBuiltInMeasurement`: default font 9/11/13 (F8), an explicit or environment font unmoved (F8, F8h), a `TextField`'s height follows its default font, its padding does not | — | M3k: `controlSize` ignored |
| 3.12 | `aButtonReadsControlSizeForItsChromeAndItsLabelsDefaultFont` — **T row**, renamed from `…ButNotItsLabelsFont` (ButtonTests 1.2): label width is the 9/11/13 pt text's | — | M3k reddens it too |
| 3.13 | `aFiniteHeightProposalCapsTheLines` — X9: `⌊h/lh⌋` (47.9 → 2, 48 → 3 at a 16 pt line), never below 1, combined with the limit by the smaller, ignored by `reservesSpace`, infinity unlimited, `nil` width with a height is one line | height ignored | M3l: `ceil` for `floor` |
| 3.14 | `aTextAnswersItsUnroundedWidestLineWhereSwiftUICeilsToThePixelGrid` — **divergence 60, pinned wrong on purpose**: "Hello, world" at 13 and at 11 answer the seam's unrounded widths (71.525- and 62.068-class, read through `measuredWidth`), not 72 and 63 (M1); the 11 pt arm's stored rect is 62 wide, where a `ceil` gives 63 (`TE-S` item 3: at 13 both round to 72) | — (pins today's answer) | M3m: `ceil` in the measurement (reddens both the measured and the rect half) |
| 3.15 | `aNotoSansLineIsTwentyFourPointsWhereSwiftUIsIsTwentyThree` — **divergence 86, pinned**: one line of Noto Sans 17 is 24 tall (X13: SwiftUI 23) | — | M3n: `lineHeight` rounded to nearest (both systems) |
| 3.16 | `aMiddleTruncationKeepsCoreTextsStringWhereSwiftUIKeepsMore` — **divergence 87, pinned**: "Hello, wonderful world" at 13, width 100, middle → CoreText's 85.12-class width, not 97.5 (X5) | — | M3o: widen the middle split |
| 3.17 | `aTruncatedTextDrawsTheSameSpritesThroughEitherSystem` — `lineLimit(1)`/`(2)` × three modes on Noto Sans; `#require` fewer glyphs than untruncated | untruncated | M3p: options not passed at paint |
| 3.18 | `multilineTextAlignmentPlacesLinesInsideTheTextsBox` — A1 (line offsets `(box − w) × factor`), A2 (a wider frame changes nothing), A3 (one line unmoved), A4 (environment) | leading only | M3q: box = the proposal |
| 3.19 | `aTextReportsRoundAscentAndItsLastLinesBaseline` — B1: first `round(ascent)`, last `first + (n − 1) × lh`, with a limit (kept lines) and with `reservesSpace` (the actual last line) | `nil` baselines | M3r: unrounded ascent |
| 3.20 | `anHStackAlignsRealTextsByTheirBaselines` — B2's tree with real `Text`s: first-aligned 44 / 12, 0, 12, 15 (agrees with SwiftUI); last-aligned offsets from MetalUI's 26 pt line height (divergence 86) | — | M3s: `Text` reports no baseline |
| 3.21 | `aLegacyBaselineRowAlignsRealTexts` — `Row { Text 13; Text 26 }.alignItems(.baseline)` | — | M3s reddens it too |
| 3.22 | `aTextFieldAndATextEditorTakeTheEnvironmentFont` — `.font(.system(size: 20))` on a container grows both; the default environment draws what it drew | — | M3t: fields keep `fontSize` 13 |
| 3.23 | `aStackSharesItsHeightWithAWrappingTextAsSwiftUIDoes` — **`TE-R`**: probe K1 (60, 100, 200 → 1, 3, 6 lines) and K2 (80 → 2) on a `VStack(spacing: 0)` of `ProposalText` 100 wide; K2 on a legacy `Column` of a `Text` and a 40-tall `Box`; line counts, never SwiftUI's half-point heights | every arm 6 lines | M3u: the measure ignores a finite height proposal |
| G3.1 | `theTextModifiersAreSwiftUIsSpellings` — plain import: every §3 spelling on `Text`, on a `ProposalText` inside an `HStack`, and on a container | — | MG3a: `lineLimit(_: ClosedRange<Int>)` made `internal` |
| G3.2 | `textBoldIsNotOffered` — `Text("a").bold()` fails; control `Text("a").font(.body.bold())` compiles | — | MG3b: add `Text.bold()` |

`dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority`,
`controlSizeIsScopedByTheNearestWriter`,
`layoutRoundsToWholePointsWhateverTheDisplayScale`,
`aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing`,
`textRowsTakeTheDefaultRowSpacing`, every `TextField`/`TextEditor` test and
every existing text test stay green unedited except the two T rows.

## 9. Verification (each lane, and the Record phase)

Full unfiltered suite, summary line read (≈ **1690** = 1644 + 41 new
tests + 5 guards after `TE-S`: lane 1 six (1.5–1.10) + G1.1, lane 2 fourteen
(1.1–1.4, 2.1–2.9, 2.11) + G1.2 + G2.1, lane 3 twenty-one (3.1–3.10,
3.13–3.23) + G3.1 + G3.2; the four T rows rename or re-answer, adding none;
1.11 and 1.12 run in `Tests/PortableTests`, outside this count; the lanes give
the exact figure), guards ran
(`FR-J` line), 0 `error:`, one `warning:`; fourteen images 0 px; the probe
re-run byte-identical to its header; `Backends/SDL`; a `swift:6.4-noble`
container if Docker; `goldensUnchanged`: every T row above has its retirement
row and no other retained test changes its answer. The Record phase writes
record §59's close, records §03/§04/§05 dated sections (divergences 60, 76, 77,
51 re-read; 86, 87, 88 added; §05's `AlignItems.baseline`, `dynamicTypeSize`
and `controlSize` rows), CLAUDE.md/AGENTS.md, the plan's dated progress note
(**box unticked**), and `docs/record/README.md`.

## 10. Not built (owner none unless named)

`TE-B` item 4/6, `TE-D`, `TE-I`, `TE-K` item 5, and `TE-O`'s table (part 2:
shapes, images, fills/strokes, overlays, clipping, divergence 47, `UnitPoint`
grid anchors, `appearance`, colour glyphs, a shape's foreground; task 12: the
`onTap` VoiceOver gap).
