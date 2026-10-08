# Rich text — design

Styled runs inside one `Text`, on both text systems. Item 6 of the gpui-gap
priority list (user request 2026-10-02; **not a plan task**). Rulings `RT-A`…
`RT-N` in [`../2026-10-08-rich-text-decisions.md`](../2026-10-08-rich-text-decisions.md);
record `docs/record/83-rich-text.md` (Record phase). Probes:
`docs/probes/swiftui-rich-text.swift`, `docs/probes/foundation-markdown-inline.swift`,
`docs/probes/swift-attribute-scope-ambiguity/run.sh` (arm ids below are theirs).

Branch `feat/rich-text` from `70ed000`. Parallel: `feat/input-apis` (§81),
`feat/variable-height-list` (§82) — stay off their files (`List*.swift`,
the input-API files they name). Divergence labels: **150–155** taken here
from the reserved range 150–159 (the header's next-label line is left for the
merge).

## §0 Baseline (measured at `70ed000` by the design session, 2026-10-08)

- `swift build --build-system native --build-tests`: exit 0, the one
  `warning:` SwiftPM's `--build-system native` deprecation notice.
- `swift test --build-system native --no-parallel`, unfiltered: **2672 tests
  in 3 suites passed**; `FR-J no-argument frame: succeeded=true`; 0 `error:`.
  Guards 175 and census 2536 are record §80 §4's readings (not re-taken).
- **Literal census** (`RT-M` item 2), a script over every `Text("…")`/
  `ProposalText("…")` literal with interpolations removed and Swift escapes
  (`\n`, `\t`, `\u{…}`, `\"`) discounted, looking for `*`, `_`, `~`, `` ` ``,
  `[`, `\`, `&`, `<`, `@`, `http`, `www.`: `Sources/` 88 literals, 1 hit — the
  scaffold's generated `Text("Hello from \#(options.name)")`, whose
  substituted package name is a Swift identifier (intraword `_` stays literal,
  `M12a`); `Tests/` and `Backends/` 1254 literals, 9 hits, all escaped
  interpolations inside typecheck-guard fixture strings (not literals the
  suite renders). **No rendered literal changes when it starts parsing.**
- SwiftUI facts this design rests on are the probes' recorded rows; the ones
  that shaped the API: Markdown parses in a literal and not in a value
  (`M1`, `M2`); `Text + Text` is deprecated in macOS 26.0 in favour of
  interpolation (the probe's 138 warnings) and interpolation renders as the
  concatenation (`C14`); `AttributedString(markdown:)` does not exist on
  Linux (`L2`).

## §1 API

### §1.1 Writing styled text (lanes 2 and 3)

```swift
// Markdown in a literal (RT-B; lane 3)
Text("**Bold**, _italic_, ~~struck~~, `code`, [a link](https://example.com)")
Text(verbatim: "**not parsed**")
Text(someString)                       // a value: never parsed (M2)
Text(LocalizedStringKey(someString))   // parsed (M14)

// Interpolation, the spelling SwiftUI recommends (RT-C; lane 3)
Text("Total: \(Text("12").bold()) items")
Text("**\(name)**")                    // the value is verbatim, bold (M10, M10b)

// Concatenation, deprecated as in SwiftUI (RT-E; lane 2)
Text("a").foregroundColor(.red) + Text("b")

// Per-segment Text modifiers (RT-E; lane 2) — each returns Text
Text("x").bold().underline(color: .red).kerning(1).baselineOffset(3)

// AttributedString over MetalUI's scope (RT-D; lane 3)
var s = AttributedString("Warning")
s.foregroundColor = .orange
s.underlineStyle = .single
s.link = URL(string: "https://example.com")
Text(s)
```

### §1.2 New public declarations

**`MetalUITextSystem`** (lane 1; `StyledText.swift`, no Foundation):

```swift
public struct TextRunStyle: Hashable, Sendable {
    public var font: FontKey
    public var kerning: Double          // points after every glyph (RT-H 3)
    public var tracking: Double         // points after every glyph, ligatures off
    public var baselineOffset: Double   // points, positive raises (RT-H 4)
    public init(font: FontKey, kerning: Double = 0, tracking: Double = 0, baselineOffset: Double = 0)
}
public struct StyledTextRun: Hashable, Sendable {
    public var length: Int              // UTF-16 units
    public var style: TextRunStyle
    public init(length: Int, style: TextRunStyle)
}
public struct StyledText: Hashable, Sendable {
    public let string: String
    public let runs: [StyledTextRun]    // normalized: no empty run (unless the string is empty), no equal neighbours
    public init(_ string: String, runs: [StyledTextRun])   // traps unless the lengths sum to string.utf16.count
    public init(_ string: String, style: TextRunStyle)     // one run
}
public struct TextLineBox: Hashable, Sendable {
    public let range: Range<Int>        // UTF-16, CTLineGetStringRange's (trailing whitespace and break included)
    public let top: Double              // from the text box's top, points
    public let height: Double           // ceil(ascent + descent + leading) over the line's runs (RT-G)
    public let baseline: Double         // from the text box's top, unrounded: top + ascent
    public let width: Double            // advance including trailing whitespace
    public let visibleMinX: Double      // first non-whitespace pen x, from the line's aligned start
    public let visibleMaxX: Double      // end of the last non-whitespace glyph
    public let offsetX: Double          // the alignment offset applied to this line
}
public struct StyledTextMeasurement: Hashable, Sendable {
    public let widestLine: Double
    public let totalHeight: Double      // sum of the kept lines' heights
    public let lines: [TextLineBox]
}
public struct StyledGlyph: Hashable, Sendable {
    public let glyph: TextGlyph
    public let run: Int                 // index into StyledText.runs; the ellipsis takes RT-I's run
}
public struct TextRunSegment: Hashable, Sendable {
    public let run: Int
    public let line: Int
    public let minX: Double             // window points (origin applied), kerning included
    public let maxX: Double
    public let baseline: Double         // window points: the line's baseline less the run's offset
}
public struct StyledTextLayout: Sendable {
    public let measurement: StyledTextMeasurement
    public let glyphs: [StyledGlyph]
    public let segments: [TextRunSegment]   // one per (run, line, visual piece), visual order
}
public struct TextDecorationMetrics: Hashable, Sendable {
    public let underlinePosition: Double    // points, negative below the baseline (CTFontGetUnderlinePosition)
    public let underlineThickness: Double
    public let strikethroughPosition: Double // points above the baseline: xHeight / 2 (RT-J 2)
}

// TextSystem gains three DEFAULTLESS requirements (RT-F item 2):
func measure(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions) -> StyledTextMeasurement
func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
            origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout
func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics
```

All public members carry doc comments (`closeout-undocumented.sh` prints
nothing). `TextGlyph`, `TextMeasurement`, `TextFontMetrics` and every
existing requirement are unchanged.

**`MetalUIHarfBuzz`** (lane 1, `package`): `HarfBuzzShaper.shape(_:font:direction:features:)`
with `features: [ShapingFeature]` (tag + value), the existing spelling
forwarding `[]`. **`MetalUIFreeType`** (lane 1): `FreeTypeFont.underlinePosition`,
`underlineThickness` (design units from `FT_Face`), `xHeight` (OS/2
`sxHeight`, else the `x` glyph's bounding box) — `package`, like the rest.

**`MetalUI`, lane 2** (`Text.swift`, `ProposalText.swift`, `TextModifiers.swift`,
new `TextRuns.swift`):

```swift
extension Text {
    public init<S: StringProtocol>(_ content: S)          // @_disfavoredOverload; replaces init(_ string: String)
    public init(verbatim content: String)
    @available(*, deprecated, message: "Use string interpolation on `Text` instead: `Text(\"Hello \\(name)\")`")
    public static func + (lhs: Text, rhs: Text) -> Text  // traps on a decorated operand (RT-E 4)
    public func bold() -> Text
    public func bold(_ isActive: Bool) -> Text
    public func underline(_ isActive: Bool = true, color: Color? = nil) -> Text
    public func strikethrough(_ isActive: Bool = true, color: Color? = nil) -> Text
    public func kerning(_ kerning: Double) -> Text
    public func tracking(_ tracking: Double) -> Text
    public func baselineOffset(_ baselineOffset: Double) -> Text
    public func monospaced(_ isActive: Bool = true) -> Text
    public struct LineStyle: Hashable, Sendable {
        public struct Pattern: Hashable, Sendable { public static let solid: Pattern }
        public init(pattern: Pattern = .solid, color: Color? = nil)
        public static let single: LineStyle
    }
}
extension Font { public func monospaced() -> Font }       // the system face's .monospaced design (TE-B)
// ProposalText: the same initialisers and modifiers (no `+`: concatenate Texts, then `proposalLayout()`).
```

`Text.string` stays public and readable — the concatenated rendered string;
**writing it replaces the content with one plain run** (doc comment says so).
`fontFamily`/`fontSize` unchanged.

**`MetalUI`, lane 3** (new `LocalizedStringKey.swift`, `MarkdownInline.swift`,
`TextAttributes.swift`):

```swift
public struct LocalizedStringKey: ExpressibleByStringInterpolation, Equatable, Sendable {
    public init(_ value: String)
    public init(stringLiteral value: String)
    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        public init(literalCapacity: Int, interpolationCount: Int)
        public mutating func appendLiteral(_ literal: String)
        public mutating func appendInterpolation<T>(_ value: T)   // String(describing:) (RT-C 3)
        public mutating func appendInterpolation(_ text: Text)    // keeps runs (RT-C 4); stores runs, not the Text
    }
}
extension Text { public init(_ key: LocalizedStringKey) }
extension Text { public init(_ attributedContent: AttributedString) }
extension ProposalText { public init(_ key: LocalizedStringKey); public init(_ attributedContent: AttributedString) }
extension AttributeScopes {
    public struct MetalUIAttributes: AttributeScope {
        public let font: FontAttribute                  // Value = Font
        public let foregroundColor: ForegroundColorAttribute   // Color
        public let backgroundColor: BackgroundColorAttribute   // Color
        public let underlineStyle: UnderlineStyleAttribute     // Text.LineStyle
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let kern: KerningAttribute               // Double
        public let tracking: TrackingAttribute          // Double
        public let baselineOffset: BaselineOffsetAttribute     // Double
        public let foundation: AttributeScopes.FoundationAttributes
        // each attribute: public enum …: AttributedStringKey, name "MetalUI.<key>"
    }
    public var metalUI: MetalUIAttributes.Type { get }
}
extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, T>) -> T
    // plus one NON-generic subscript per key above (RT-D 3)
}
```

`LocalizedStringKey.StringInterpolation` stores the runs of an interpolated
`Text` (all `Sendable` values: strings, `Color`, `Font`, `Double`,
`Text.LineStyle`, the link string) — never the `Text` itself, which holds
handlers.

### §1.3 The run model (lane 2, internal, `TextRuns.swift`)

```swift
struct TextRunRequest: Sendable, Hashable {   // one segment as written
    var string: String
    var font: TextFontRequest?; var weight: Font.Weight?; var italic: Bool?; var monospaced: Bool?
    var foreground: Color?; var background: Color?
    var underline: Text.LineStyle?; var strikethrough: Text.LineStyle?   // isActive false → explicit "none"
    var kerning: Double?; var tracking: Double?; var baselineOffset: Double?
    var link: String?
}
enum TextContent: Sendable { case plain(String); case runs([TextRunRequest]) }
```

`Text` stores `content` and its `Text`-level fields (the existing four plus
underline, strikethrough, kerning, tracking, baselineOffset, monospaced) — the
**outer layer**. Resolution per run (`RT-E` 2): `run.field ?? text.field`,
then `resolveTextStyle` (`TE-AA`) with the run's merged `TextStyleRequest`,
**called once per run in layout and again in paint**; a link run with no
colour at either layer gets `Color.accentColor` before the environment is
consulted (`RT-K`). Resolved runs whose `TextRunStyle` and paint attributes
are equal merge before the seam (`C9b`).

**The fast path** (`RT-F` 3): `content` is `.plain`, or one run whose only
set fields are font/weight/italic/foreground, and no `Text`-level rich field
is set → the existing code, byte for byte (same calls, same arguments).
Otherwise the styled path: `requestLayout` builds the `StyledText` (keys from
`system.resolveFont`) and paint attributes once, captured by value in the
measurement closure; `paint` rebuilds them through the same functions and
calls `layOut` at the measured width (the existing `measuredWidth` rule,
divergence 8's fix).

**Styled measurement** (`RT-G`): the `textLines` analogue `styledTextLines`
applies the line limit, then the cumulative height cap (`C16`), then
`reservesSpace` with the first run's line height (`C18`); widths never exceed
a finite proposal (`LR-AU`); baselines from the line boxes (`RT-G` 2).

**Styled paint** (`RT-J`), a `PaintPass` helper `drawStyledText(_:paint:)` in
new `RichTextPaint.swift`, inside `paintDecoration`'s content closure and
inside one `frame.beginLeafGroup()`/`endLeafGroup()`: (1) backgrounds — per
segment, `minX…maxX` × the line box; (2) glyphs — each `StyledGlyph` in its
run's resolved colour through `frame.draw(_:color:)`; (3) underlines (merged
per `RT-J` 3a, clipped to the line's visible extent) then strikethroughs,
through `pass.fill`. Colours resolve through `pass.resolve` (snap, `RT-L` 2).

## §2 Files

| lane | sources | tests |
|---|---|---|
| 1 | new `Sources/MetalUITextSystem/StyledText.swift`; `TextSystem.swift` (3 requirements); `Sources/MetalUIText/CoreTextTextSystem.swift`, `ShapingCache.swift`, `ShapedText.swift`, `PlacedGlyph.swift`, new `StyledShaping.swift`, `FontResolver.swift` (decoration metrics); `Sources/MetalUIPortableText/FontFallback.swift`, `LineBreaking.swift`, `LineEmission.swift`, `Truncation.swift`, `PortableTextSystem.swift`, `PortableText.swift` (decoration metrics), new `StyledLayout.swift`; `Sources/MetalUIHarfBuzz/*` (features); `Sources/MetalUIFreeType/FreeTypeFont.swift` | new `Tests/MetalUITests/StyledTextSeamTests.swift`; new `Tests/MetalUIPortableTextTests/StyledTextOracleTests.swift`; new `Tests/MetalUICrossPlatformTests/StyledTextPortableTests.swift`; `Tests/MetalUIHarfBuzzTests/` (one test, new file `ShapingFeatureTests.swift`); `Tests/MetalUITests/MenuPickerTests.swift` (`CountingTextSystem` gains the three requirements — its only change) |
| 2 | `Sources/MetalUI/Text.swift`, `ProposalText.swift`, `TextModifiers.swift`, `TextStyleResolution.swift`, `Font.swift` (`monospaced()`), `Handlers.swift` (internal `isDefault`), new `TextRuns.swift`, new `RichTextPaint.swift`; `Sources/MetalUIDemoContent/RichTextDemo.swift` (new); `Sources/MetalUIDemo/main.swift` (the env switch) | new `Tests/MetalUITests/RichTextTests.swift`, `RichTextPaintTests.swift`, `RichTextCompileGuards.swift`; new `Tests/MetalUICrossPlatformTests/RichTextPortableWindowTests.swift`; `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift` (the new tree, own `@inline(never)` function); the `Text` arm of `everyDecorationScopingSiteContainsItsOwnContent` (its file, one arm added) |
| 3 | new `Sources/MetalUI/LocalizedStringKey.swift`, `MarkdownInline.swift`, `TextAttributes.swift` | new `Tests/MetalUICrossPlatformTests/MarkdownInlineTests.swift`, `LocalizedStringKeyTests.swift`, `AttributedTextTests.swift`; new `Tests/MetalUITests/MarkdownOracleTests.swift` (Darwin, Foundation's parser), `TextLiteralCompileGuards.swift` |

**Shared registries** (append-only, each lane its own rows, in its own
commits): `docs/probes/closeout-inventory-map.tsv` (+ the census re-recorded
with `closeout-public-api.sh` at each lane's end). Lane 3 alone writes
`docs/divergences.md` rows 150–155, `docs/verification/human-checks.md` group
Y, `docs/migration.md`, `docs/api-overview.md`, and the decisions doc's
amendment rulings for anything a lane measured differently.

## §3 Lanes (ruling `RT-N`; order 1 → 2 → 3; one agent at a time)

- **Lane 1 — the seam and both text systems.** Types and requirements (§1.2),
  CoreText styled shaping (one `CTTypesetter` over an attributed string with
  `kCTFontAttributeName`, `kCTKernAttributeName`, `kCTTrackingAttributeName`
  per run; baseline offset applied by MetalUI to the run's glyphs and line
  box, not by `kCTBaselineOffsetAttributeName`, whose bounds rule differs from
  `RT-G`'s; line boxes computed from the runs' requested faces; truncation
  token attributed per `RT-I`), portable styled layout (`shapeCascading`
  per-unit runs, breaking over the whole string, kerning/tracking/offset,
  line boxes, truncation, segments, bidi visual pieces), decoration metrics on
  both, the oracle corpus. Runs the Linux image (§5) — the portable path is
  what Linux and Windows draw. Measures `RT-H` item 3's tracking rule on Noto
  Sans before relying on it; a disagreement is an amendment ruling.
- **Lane 2 — the `Text` element.** Run model, initialisers
  `init<S: StringProtocol>`/`init(verbatim:)`, `Text`-level modifiers, `+`
  with its trap, styled layout and paint, decorations, links (styled, inert),
  accessibility string, `ProposalText` parity, `Handlers.isDefault`, the demo
  section. Its tests build styled text with modifiers and `+` (in deprecated
  helpers) — no Markdown, which is lane 3's.
- **Lane 3 — the front ends and registries.** `LocalizedStringKey` (literals
  start parsing here), the Markdown parser, interpolation, the attribute scope
  and `Text(AttributedString)`, the Foundation oracle, and the shared
  registries (§2). Runs the full demo-pixel compare and the Linux image again
  (the parser is portable code).

Each lane ends green on its own: full unfiltered native suite (one summary
line, the `FR-J` line), `swift build --build-tests` 0 warnings, inventory
scripts silent, each new typecheck guard mutated red once, every mutation in
§4 run on a committed tree restored from a copy with `git status --short`
after.

## §4 Tests — by name, red before, and the mutation that must redden each

"Red before" is how the test fails on the tree before its lane's
implementation (a compile failure counts only where noted; otherwise the lane
first lands a stub that compiles and returns a wrong answer, and the test
must fail on the stub). Literals are derived in the test from the faces'
metrics, never pasted from a run. Every mutation names the declaration and
the spelling it edits; the lane records which tests it reddened (by name).

### §4.1 Lane 1 — seam and systems

| # | test (file) | asserts | red before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aOneRunStyledTextMeasuresAsThePlainCallsOnBothSystems` (`StyledTextSeamTests`) | for a corpus (Latin, Arabic, a hard break, an emoji that falls back) × widths nil/40/0.5 × options (limit 2 tail/head/middle, centre), a one-run `measure(StyledText)` equals the plain `measure` (widest, total) and its lines' heights are all `fontMetrics.lineHeight` | stub returns zeros | CoreText: take the line height from `CTLineGetTypographicBounds` (fallback faces included) — the emoji arm reddens |
| 1.2 | `aOneRunStyledTextPlacesThePlainGlyphsOnBothSystems` | `layOut(...).glyphs.map(\.glyph)` == `placeGlyphs(...)` for the same corpus at scale 1 and 2; every run index 0 | stub returns `[]` | portable `StyledLayout`: round the baseline before scaling (`(baseline).rounded() * scale`) |
| 1.3 | `aRunBoundaryIsNotABreakOpportunity` (`C4`, `C4c`) | `"foo"` + `"bar"` (two runs, regular/bold) at `width("foobar") − 3` keeps one line (lines == the plain `"foobar"`'s) on both systems | stub breaks per run | portable: mark `.allowed` at each run boundary in the break table |
| 1.4 | `breaksBetweenRunsFallWhereCoreTextPutsThem` (`C4d`) | `"word "`+bold `"next"`+`" more"` at 40 → ranges `0..<5`, `5..<10`, `10..<14` on both | stub | portable: reshape from each line start with run 0's font (`font: runs[0]`) |
| 1.5 | `aMixedLineTakesTheLargestAscentAndDescent` (`C5`, `C6`; `RT-G` 1–2) | 10 pt + 30 pt on one line: height == 30 pt `lineHeight`, baseline == 30 pt ascent; wrapped so line 1 is 10 pt only and line 2 holds the 30 pt run: heights `[lh10, lh30]`, line 2 top == `lh10` | stub uses the first run | sum ascents instead of taking the max (`ascent += …`) |
| 1.6 | `aBaselineOffsetGrowsTheLineAndMovesItsGlyphs` (`C7`, `C7d`) | +5 and −5 on a run: line height == `lineHeight + 5` both; the run's glyphs' `baselineY` == line baseline ∓ 5·scale | stub ignores offset | shrink the descent for a positive offset (CoreText's rule, `descent − offset`) — the +5 arm reddens; flip the glyph sign — the glyph arm reddens |
| 1.7 | `kerningAddsAfterEveryGlyphAndKeepsLigatures` (`C8`, `C8e`, `F1`) | kerning 4: widest == plain + 4 × glyph count (last glyph included) on both; glyph count unchanged on a ligature string in a face that ligates it (lane 1 picks it from the test faces, e.g. Noto Sans "office") | stub | skip the last glyph's kern (`dropLast()`) |
| 1.8 | `trackingBreaksLigaturesOnBothSystems` (`C8e`) | tracking 4 on the same string: glyph count == the unligated count; widths agree between systems to 1e-3 | stub | `HarfBuzzShaper.shape` ignores `features` |
| 1.9 | `theEllipsisTakesTheFirstRemovedCharactersRun` (`C13`, `C13b`, `C13d`, `C19`; `RT-I`) | tail, head and middle: the ellipsis glyph's run index is the first removed character's; a removed 30 pt run makes the truncated 10 pt line `lh30` tall | stub uses run 0 | attribute the token with the last **kept** character's run — the head arm and the `C19` arm redden (the tail arms alone cannot separate) |
| 1.10 | `everyStyledCorpusCasePlacesTheSameGlyphsAsTheApplePath` (`StyledTextOracleTests`) | the CoreText oracle (`RT-H` 5): a corpus over the three test faces (mixed sizes and faces, kerning, tracking, offsets, wraps, Arabic + Latin bidi, limits) at scales 1 and 2 — same glyph keys, positions, line boxes and segments | stub | portable `shapeCascading`: choose the covering face from the base font for every unit (`coveringFace(c, font: runFonts[0])`) |
| 1.11 | `theDecorationMetricsAgreeOnBothSystems` | `decorationMetrics` for the three faces × five sizes: position and thickness to 1e-4 (TrueType exact, `PT-B`'s fraction rule), strikethrough == xHeight / 2 | stub zeros | FreeType: take the strikethrough from OS/2 `yStrikeoutPosition` |
| 1.12 | `segmentsSpanTheirAdvanceAndLinesKnowTheirVisibleExtent` (`C9k`, `C9w`, `F4`) | `"x   "` / `"   x"` / `"x"`+`"   "`+`"x"` with kerning: segment extents include kerning; `visibleMinX/MaxX` exclude a line's leading/trailing whitespace and include interior whitespace, both systems | stub | include trailing whitespace in `visibleMaxX` |
| 1.13 | `bidiRunsSplitIntoOneSegmentPerVisualPiece` | Latin–Arabic–Latin with a run spanning the switch: segment count, order and extents equal on both systems | stub one segment per run | emit segments in logical order |
| 1.14 | `aWarmStyledFrameShapesNothing` | two frames over the same `StyledText`: `ShapingCache.misses` unmoved on the second; the portable measurement cache answers the second from its entry (counted) | stub uncached | key the styled cache entry by `string` only (two styled texts with one string share an entry — the arm with two run splits reddens) |
| 1.15 | `aStyledTextWhoseLengthsDoNotSumTraps` (exit test) | `StyledText("abc", runs: [length 2])` exits with a signal | — (new trap) | delete the precondition |
| 1.16 | `zeroLengthRunsAreDroppedAndEqualNeighboursMerge` (`StyledTextPortableTests`, runs on Linux) | normalization; an empty string keeps its first run's style (`C17`) | stub | skip the merge |
| 1.17 | `thePortableSystemLaysOutAStyledTextOnEveryPlatform` (`StyledTextPortableTests`) | Noto Sans 10/30 mixed line and a +5 offset: heights and baselines from `PortableFontMetrics`, on Linux too | stub | as 1.5 |
| 1.18 | `disablingLigaturesShapesTheLigatureAsSeparateGlyphs` (`ShapingFeatureTests`) | HarfBuzz with `liga`/`clig` off: one glyph per letter of the ligated string | stub | ignore `features` |

### §4.2 Lane 2 — the `Text` element

Tests that use `+` live in `@available(*, deprecated)` helpers.

| # | test (file) | asserts | red before | mutation |
|---|---|---|---|---|
| 2.1 | `concatenationPushesEachSidesTextFieldsIntoItsUnsetRuns` (`RichTextTests`; `C2`, `C2b`, `C3`, `C3b`, `C12b`) | per-run resolved descriptors and colours: an inner colour/weight/font wins, the outer reaches only unset runs | compile (no `+`) | `resolve`: `text.field ?? run.field` (outer wins) |
| 2.2 | `aStyledTextMeasuresAsCoreTextsAttributedLine` (`C1`) | `Text("Ab").bold() + Text("cd")` answers CoreText's attributed line width (derived in the test with `CTLineGetTypographicBounds`) | stub plain | measure the concatenated plain string |
| 2.3 | `aPlainTextTakesThePlainCalls` (`RT-F` 3) | a spy `TextSystem` records calls: `Text("a")`, `Text("a").bold().foregroundColor(.red).italic()`, `Text("a").font(.title)` reach only the plain requirements; `Text("a").underline()`, `.kerning(0)`, a two-run text reach only the styled ones | stub | invert the fast-path predicate's `kerning` clause |
| 2.4 | `aStyledTextPaintsEachRunsColour` | scene sprites: run 1's glyphs red, run 2's blue | stub single colour | colour every glyph with run 0's colour |
| 2.5 | `anUnderlineIsARectAtTheFacesPosition` (`RT-J` 2–3, `C9w`) | the rect's centre `baseline − underlinePosition`, height `underlineThickness`, x extent the segment clipped to the visible extent (`"x   "` arm) | stub none | drop the visible-extent clip |
| 2.6 | `aStrikethroughSitsOnHalfTheXHeight` (`C9s`, `C9ms`) | centre `baseline − xHeight/2` for 13 pt and 30 pt runs on one line | stub | use the line's tallest run's metrics for every strike |
| 2.7 | `sameColouredUnderlinesMergeAndOthersDoNot` (`C9m`, `C9b`, `F3`, `F2`) | 10 pt + 30 pt both underlined, one colour: one rect at the 30 pt geometry across both; different colours: two rects, own geometry; strikethroughs: two rects | stub | (a) never merge — the `C9m` arm; (b) merge regardless of colour — the `F3` arm |
| 2.8 | `aBackgroundFillsTheRunByTheLineBox` (`C11bg`, `C11bg2`, `F4e`) | rect: segment extent (trailing spaces included) × the line box; a 10 pt run beside a 30 pt one fills the 30 pt line | stub | use the run's own font line height |
| 2.9 | `aWarmFrameOfAStyledTextShapesNothing` | a window, two frames: `ShapingCache.misses` unmoved on the second (layout and paint ask the same question) | stub | paint lays out at `bounds` width instead of `measuredWidth` |
| 2.10 | `theDemoDoesTheSameTextWorkAsBefore` (`RT-M` 1) | the main demo's first and warm frames: `ShapingCache` misses and lookups equal literals recorded at `70ed000` by the lane before its change (stated in the test with the commit) | green on arrival by design (a must-not-move pin) | route every `Text` through the styled path (predicate `true`) |
| 2.11 | `aStyledTextIsOneShadowLeaf` (`GX-J`) | under `.shadow`, one shadow raster whose leaf holds the background rect, glyphs and underline | stub | emit the underline after `endLeafGroup` |
| 2.12 | the styled `Text` arm of `everyDecorationScopingSiteContainsItsOwnContent` (`OM-AI`, `OM-V`) | a faded, clipped, bordered styled `Text`: rects and glyphs at alpha 0.5, inside the clip, before the border | stub | call `drawStyledText` outside `paintDecoration`'s closure |
| 2.13 | `aStyledTextPublishesItsConcatenatedString` (`RT-L` 1) | the AX record's text is the whole string; an all-empty concatenation publishes none | stub | publish the first run's string |
| 2.14 | `aMixedTextCapsLinesByTheirSummedHeights` (`C16`) | lines `[lh10, lh30, …]` with proposal height `lh10 + lh30 − 1`: one line (`⌊h / lh10⌋` would keep more) | stub | cap by `⌊h / firstLineHeight⌋` |
| 2.15 | `reservedSpaceUsesTheFirstRunsLineHeight` (`C18`) | `lineLimit(3, reservesSpace: true)`: `B30 + a10` → 3 × lh30; `a10 + B30` → max(3 × lh10, lh30) | stub | use the tallest line |
| 2.16 | `aMixedTextReportsBaselinesFromItsLines` (`RT-G` 2) | first `round(ascent₁)`, last `top(last) + round(ascentₙ)` for the `C6` shape | stub | plain formula `first + (n−1) × lineHeight₀` |
| 2.17 | `aLinkDrawsInTheAccentUnlessItsRunIsColoured` (`RT-K`; `M6`, `C11lnc`, `C11lne`) | link run colour `.accent`; red run red; under `.foregroundStyle(.green)` still accent | stub | let the environment's `foregroundStyle` reach a link run |
| 2.18 | `aLinkRegistersNothingAPlainTextDoesNot` (`RT-K`, divergence 150) | hitboxes, focus entries and AX records equal those of the same text without the link | stub | register a pointer hitbox per link segment |
| 2.19 | `concatenatingADecoratedTextTraps` (exit tests: `.padding`, `.onClick`, `.id`) (`RT-E` 4, divergence 155) | each exits with a signal | — | delete the precondition |
| 2.20 | `handlersIsDefaultSeesEveryMember` | 17 arms: setting any one `Handlers` member makes `isDefault` false | stub `true` | drop one member from `isDefault` (each arm is its own mutation; the lane runs three, chosen across public and internal members) |
| 2.21 | `aOneRunStyledTextDrawsThePlainSprites` | a window: `Text("Hello").kerning(0)` (styled path) and `Text("Hello")` (plain) draw identical glyph primitives | stub | offset the styled paint origin by the line's `offsetX` twice |
| 2.22 | `proposalTextDrawsTheSameStyledSpritesAsText` | `ProposalText` and `Text` of one styled content: equal scene glyphs and rects | stub | `proposalLayout()` drops `content` |
| 2.23 | `aRunsColourSnapsUnderAnAnimation` (`RT-L` 2) | `withAnimation` changing a run's colour: the next frame draws the new colour | green on arrival (pin) | route run colour through `animatedColor` |
| 2.24 | `theTextModifiersComposeAsSwiftUIs` (`RichTextCompileGuards`, `typecheckFile`, plain import) | compiles: `Text("a").bold().underline(color: .red).kerning(1) + Text("b")` (in a deprecated function), `Font.body.monospaced()`; does **not** compile: `Text("a").lineLimit(1) + Text("b")`, `.underline(pattern: .dash)`, `Text.LineStyle.Pattern.dash` | compile | each arm mutated red once (e.g. add a `dash` static) |
| 2.25 | `theConcatenationOperatorIsDeprecated` (guard) | compiling `Text("a") + Text("b")` in a non-deprecated context emits the deprecation warning with SwiftUI's message | compile | remove the `@available(*, deprecated…)` |
| 2.26 | `aStyledTextDrawsThroughThePortableSystem` (`RichTextPortableWindowTests`, Linux too) | a headless frame over `PortableTextSystem`: two glyph colours and an underline rect at the Noto Sans geometry | stub | as 2.4 |

### §4.3 Lane 3 — front ends

| # | test (file) | asserts | red before | mutation |
|---|---|---|---|---|
| 3.1 | `theInlineGrammarMatchesTheProbedRuns` (`MarkdownInlineTests`, Linux too) | every `M` and `N` row of the Foundation probe (text, bold/italic/strike/code, link) as literals from the probe header | stub returns the source as one run | (a) intraword `_` opens emphasis — `M12a`, `N9`, `N20`; (b) no extended autolinks — `M15b`, `M20`, `M21`, `M26`, `N10`, `N11`; (c) keep emphasis inside link text — `M22`; (d) parse block syntax — `M8a` |
| 3.2 | `theParserAgreesWithFoundationOnTheCorpus` (`MarkdownOracleTests`, Darwin) | the probe corpus plus every 4-token combination of `*`, `**`, `_`, `~~`, `` ` ``, `a`, space (generated, `try #require` on the count) parsed by both → equal runs | stub | drop CommonMark's rule of 3 (`(open + close) % 3`) |
| 3.3 | `onlyTheEntitySubsetDecodes` (divergence 153) | `&amp;`, `&#65;`, `&#x41;`, `&copy;`, `&nbsp;` decode; `&bogus;` and `&alpha;` stay literal | stub | decode an unknown name to U+FFFD |
| 3.4 | `aLiteralParsesAndAValueDoesNot` (`M1`, `M2`, `M14`) | `Text("**b**")` one bold run; `Text(s)` and `Text(verbatim:)` verbatim; `Text(LocalizedStringKey(s))` bold | stub | make `init<S: StringProtocol>` parse |
| 3.5 | `anInterpolatedValueIsVerbatimButTakesTheFormatsStyle` (`M10`, `M10b`) | `"a \(v)"` keeps `**x**`; `"**\(n)**"` bold `n` | stub | substitute before parsing |
| 3.6 | `anInterpolatedValueIsItsDescription` (`M11`, `M11b`, `M29`; divergence 151) | `3.5` → `"3.5"`, `7` → `"7"` | stub | format `Double` with `%lf` |
| 3.7 | `anInterpolatedTextKeepsItsRuns` (`C14`) | `Text("a \(Text("b").bold())")` runs == `Text("a ") + Text("b").bold()`'s | stub | interpolate the text's `.string` |
| 3.8 | `interpolatingADecoratedTextTraps` (exit test) | `Text("a \(Text("b").onClick {})")` exits | — | delete the check |
| 3.9 | `anAttributedStringBuildsTheConcatenationsRuns` (`C11`, `C12`, `C12b`) | every key's run equals the modifier spelling's | stub | ignore `kern` |
| 3.10 | `theInitialisersReachSwiftUIsOverloads` (`TextLiteralCompileGuards`, plain import) | compiles `Text("lit")`, `Text(substring)`, `Text(verbatim:)`, `Text("n \(1.5) \(Text("b"))")`; `let k: LocalizedStringKey = "x"` | compile | remove `@_disfavoredOverload` from `init<S>` (the literal arm turns ambiguous) |
| 3.11 | `inlinePresentationIntentIsHonouredOnDarwin` (`C12c`; `#if canImport(Darwin)`) | `Text(try AttributedString(markdown: "**b** _i_ ~~s~~ `c`"))` runs == `Text("**b** _i_ ~~s~~ `c`")`'s | stub | ignore the intent |
| 3.12 | `everyAttributeKeyIsWritableWithAPlainImport` (guard, `typecheckFile`, `SA-P`) | `s.font = .body`, `s.foregroundColor = .red`, `s.backgroundColor = .yellow`, `s.underlineStyle = .single`, `s.strikethroughStyle = .single`, `s.kern = 1`, `s.tracking = 1`, `s.baselineOffset = 1`, `s.link = …` with `import MetalUI` only, and again with `import AppKit` | compile | delete the per-key `foregroundColor` subscript — ambiguous (probe `generic UsePlain`) |
| 3.13 | `theCodeSpanIsMonospaced` (`M5`) | the code run's descriptor has design `.monospaced` (system face) | stub | map code to italic |
| 3.14 | `aMarkdownLinkAndAnAttributedLinkBuildOneRunKind` | both store the destination on `link`; `M20`'s is `http://www.x.org`, `M21`'s `mailto:a@b.org` | stub | drop the `http://` prefix for `www.` |
| 3.15 | `aControlTitleIsVerbatim` (divergence 154) | `Button("**b**") {}` and `Toggle("**b**", isOn:)` publish and draw the title `**b**` (the label text's string and its AX text) | green on arrival (pins the divergence) | route the `String` title through `LocalizedStringKey` |

## §5 CI and commands

- macOS, every lane: `swift build --build-system native --build-tests`, then
  `swift test --build-system native --no-parallel` unfiltered (background,
  poll the tail): one summary line, `FR-J no-argument frame: succeeded=`;
  `swift build --build-tests` 0 warnings; `zsh
  docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh`
  print nothing; `swift package clean` after changing stored properties of
  `Text`/`ProposalText` (public types crossing into `MetalUIDemoContent`).
- **Linux image**, lanes 1 and 3 (portable text and the parser are what
  Linux and Windows run; lane 2's portable window test too): the root
  package's portable test targets in `swift:6.4-noble` (`MetalUILayoutTests`,
  `MetalUICoreTests`, `MetalUICrossPlatformTests`, as CI), and
  `Backends/SDL`: `docker build -t metalui-portable -f
  Backends/SDL/linux/Dockerfile Backends/SDL`, then `docker run --rm -v
  "$PWD":/work -v metalui-sdl-build-rich-text:/tmp/build -w /work/Backends/SDL
  metalui-portable bash -c 'swift build --build-tests --scratch-path
  /tmp/build && swift test --skip-build --scratch-path /tmp/build'`. No file
  under `Backends/SDL` changes on this branch; it must still build (its
  `PortableTextSystem` use compiles against the new requirements).
- **Pixels**, lanes 2 and 3: `docs/probes/demo-pixels/compare.sh <scratch>
  70ed000 HEAD` — fourteen images, 0 px.
- Windows: CI's `root-windows` on push (FoundationEssentials'
  `AttributedString` there is the same swift-foundation code `L1` ran on
  Linux; not run locally by the design session). The UTM VM may be used by
  lane 3 if CI disagrees.

## §6 Demo expectation (lane 2)

`METALUI_RICH_TEXT_DEMO=1 swift run MetalUIDemo` opens a window of sections,
each its own function (1 MB Windows stack): **Markdown** (one literal with
bold, italic, bold-italic, strikethrough, code, a link and a bare URL — lane 3
switches its literal from interpolation-built `Text` to the Markdown literal
when `LocalizedStringKey` lands); **concatenation** (coloured and weighted
segments, `C2`'s shape); **mixed sizes** (a 10/20/30-point paragraph wrapping
across lines); **decorations** (underline, coloured underline, strikethrough,
background, kerning, tracking, baseline offset as superscript); **truncation**
(a two-colour line under `lineLimit(1)` in tail and head modes);
**attributed** (`Text(AttributedString)` with every key). Not one of the
fourteen images; added to `buildEveryProductionTree`. Launched only when the
lock probe allows, killed after a few seconds.

## §7 Human checks — group Y (lane 3 writes it; an agent cannot run it)

(If a parallel branch merges a group Y first, the later merge renames this
one and says so.)

- **Y1** The rich-text demo on macOS: every Markdown form reads as styled
  (bold, italic, struck, monospaced, accent-coloured links and URL), in light
  and dark.
- **Y2** Underlines and strikethroughs at 1× and 2× displays: crisp enough
  beside a SwiftUI `Text(…).underline()` (divergence 152's unsnapped band).
- **Y3** The mixed-size paragraph: line spacing looks even and no glyph is
  clipped by its line; the superscript sits above the line without touching
  the line above.
- **Y4** The same demo on Linux and Windows (SDL): matches macOS by eye.
- **Y5** VoiceOver on a styled `Text` reads the whole sentence once, without
  Markdown markers; a link is read as plain text (divergence 150).
- **Y6** Clicking a link does nothing and the cursor does not change
  (divergence 150).

## §8 Migration notes and records owed

### §8.1 Migration (lane 3 writes `docs/migration.md`)

- **String literals in `Text` parse Markdown** (`RT-B`): a literal containing
  `**`, `_x_`, `` ` ``, `~`, `[…](…)`, a URL, `&…;` or a backslash now
  renders styled or decoded. Use `Text(verbatim:)` to keep it literal.
- `Text(_ string: String)` is now `Text<S: StringProtocol>(_ content: S)`
  (disfavoured) beside `Text(_ key: LocalizedStringKey)`; a `Text.init`
  function reference needs a type annotation.
- `Text + Text` is deprecated (as in SwiftUI); interpolate instead. A `+`
  operand with a style, decoration, handler or id traps (divergence 155).
- **`TextSystem` gains three requirements** with no defaults (`RT-F`): an
  external conformer implements `measure(_: StyledText, …)`,
  `layOut(_:…)` and `decorationMetrics(_:)`.
- An interpolated floating-point value prints its Swift description
  (divergence 151).

### §8.2 Divergences lane 3 writes (`docs/divergences.md`, labels 150–155)

| # | what differs | SwiftUI | MetalUI | ruling | pin |
|---|---|---|---|---|---|
| 150 | links in text | a link run opens its URL through `openURL` on click and is an accessibility link (rendered `M6`, `C11ln`; the action not probed headless) | a link run is styled (accent unless coloured) and inert; its text is part of the text's string | `RT-K` | `aLinkRegistersNothingAPlainTextDoesNot` (2.18) |
| 151 | an interpolated floating-point value in a `Text` literal | formatted with `%lf`: `"v \(3.5)"` draws `v 3.500000` (`M11`) | `String(describing:)`: `v 3.5`; integers agree (`M11b`) | `RT-C` 3 | `anInterpolatedValueIsItsDescription` (3.6) |
| 152 | underline and strikethrough placement | snapped to device pixels by TextKit (`C9`: rows 28–29 at 13 pt, scale 2) | the face's unsnapped band (underline position/thickness; strikethrough at x-height / 2) | `RT-J` 2 | `anUnderlineIsARectAtTheFacesPosition` (2.5) |
| 153 | named character references in a literal | HTML5's named entities decode (`M35`: `&alpha;&hearts;` → `α♥`; Foundation's parser `N21`); a name that is no entity stays literal (`N12`) | numeric references and a fixed subset of 34 names decode; any other name stays literal | `RT-B` 4 | `onlyTheEntitySubsetDecodes` (3.3) |
| 154 | Markdown in control titles | `Button("**b**")`, `Toggle("**b**", …)` draw bold labels (`M30`, `M31`) | controls' `String` titles are verbatim | `RT-A` | `aControlTitleIsVerbatim` (3.15) |
| 155 | concatenating a decorated `Text` | does not compile (`.padding()` etc. return `some View`) | compiles (they return `Self`) and traps at the `+` (or the interpolation), naming the field | `RT-E` 4 | `concatenatingADecoratedTextTraps` (2.19) |

**Not offered rows** (documented absences): `Text.LineStyle` patterns other
than `.solid`; view-level `bold`/`underline`/`strikethrough`/`kerning`/
`tracking`/`baselineOffset`/`monospaced`; localization tables
(`tableName:bundle:comment:`); `Text(Image)`, `textCase`, `textScale`,
`fontWidth`, `monospacedDigit()`, formatter interpolations; `.tint`;
`AttributedString` attributes outside MetalUI's scope; rich `TextField`/
`TextEditor`.

### §8.3 Owed to the Record phase (files no lane may edit)

`docs/record/83-rich-text.md` (the lanes' measurements, every mutation and the
tests it reddened, the conversions `RT-M` 3 lists, the census); record §04
sections for divergences 150–155; record §03/§05 rows; `docs/record/README.md`
row; CLAUDE.md/AGENTS.md: the `RT-` prefix line, one rule paragraph (the run
model at the seam, the fast path, decorations as rects inside the text leaf,
Markdown via MetalUI's own parser), the three new defaultless `TextSystem`
requirements beside `PlatformWindow`'s, counts; README.

## §9 Deferred (each with reason and owner; `RT-A`)

Interactive links (hit testing and accessibility must not move; owner none);
line-style patterns (a dash probe and emitter; none); view-level text
modifiers (additive environment keys; none); Markdown in control titles
(divergence 154; none); localization tables (no string-table system; none);
`Text(Image)`, `textCase`, `textScale`, `fontWidth`, `monospacedDigit`,
formatter interpolation (none); rich text input (`TI-` stays plain; none);
animated run colours (unmeasured in SwiftUI; the plain hole; none); named
entities beyond the subset (licence and size; none); descender-skipping
underlines (not measured — `C9g` cannot separate it; none).

## §10 Must not move (checked by every lane)

Identity and state retention (`theSevenRetentionSlotsAreMutuallyDistinct`,
`MC-A`/`MC-C`/`MC-P` numbering, `.id()` outermost), hit testing,
accessibility (no new node field or bridge row), animation (no new animated
field), focus, `List` windowing and `TB-AH`, `Deferred`, text input (caret
offsets and line ranges are plain-text APIs). Fourteen offscreen images 0 px
against `70ed000`; `DemoFrameDeterminismTests`' `Expected.swift` unedited;
0 `warning:` on both build systems; `MetalUILayout` imports only
`MetalUICore`; `MetalUIScene` only `MetalUIShaderTypes`; `MetalUITextSystem`
only `MetalUIScene`; `MetalUIPortableText`'s import list unchanged (`PT-A`);
`MetalUIHarfBuzz` only `CHarfBuzz`; `MetalUIFreeType` only `MetalUIScene`,
`CFreeType`; no shader change (`shaders.metal`, `replay.hlsl` untouched);
`Backends/SDL` and `swift:6.4-noble` build;
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.
