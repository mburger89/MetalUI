# Rich text — design

**Status: LANDED** (2026-10-08, record `docs/record/83-rich-text.md`): all three lanes built red first and verified `ok: true`; the looks are owed to a human (group RT). Suite 2672 -> 2790 after the merge with master.

Styled runs inside one `Text`, on both text systems. Item 6 of the gpui-gap
priority list (user request 2026-10-02; **not a plan task**). Rulings `RT-A`…
`RT-T` in [`../2026-10-08-rich-text-decisions.md`](../2026-10-08-rich-text-decisions.md);
record `docs/record/83-rich-text.md` (Record phase). Probes:
`docs/probes/swiftui-rich-text.swift`, `docs/probes/foundation-markdown-inline.swift`,
`docs/probes/swift-attribute-scope-ambiguity/run.sh`, and the critic pass's
`docs/probes/swiftui-text-interpolation.swift` (`I0`–`I4`) and
`docs/probes/swiftui-kerning-zero.swift` (`K1`, `K2`) (arm ids below are theirs).
**The critic pass's corrections are ruling `RT-O`; this spec carries them.**
**Lane 1's measured amendments are ruling `RT-P`** (the ellipsis in two
attempts, trailing tracking, no shaping-run split at a style change that
keeps the face, spacing once per grapheme, CoreText's kashidas — divergence
157 for lane 3 — and test 1.13's fixture); where this spec says "after every
glyph" or "splits a shaping run at a style change", `RT-P` items 3–4 govern.
**Lane 2's amendments are ruling `RT-R`** (a `Text`'s styled text keeps
neighbours that differ only in paint, the rich fields boxed for the 1 MB
stack, `+` joining equal segments, `Text.bold()` as divergence 158, and the
instruments of tests 2.9, 2.19 and 2.21). **Lane 3's amendments are ruling
`RT-T`** (an interpolated `Image` is deprecated and traps — an unavailable
overload loses to the generic one; `~` as a skip character; placeholders; the
trigger list's `://`; the key's content built off the main actor; Foundation's
link conversion; test 3.10b and the demo's render test).

Branch `feat/rich-text` from `70ed000`. Parallel: `feat/input-apis` (§81),
`feat/variable-height-list` (§82) — stay off their files (`List*.swift`,
the input-API files they name — `Handlers.swift` among them, `RT-O` item 1). Divergence labels: **150–156** taken here
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
  interpolation (the probe's 146 warnings) and interpolation renders as the
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
Text("x").underline(true, pattern: .solid, color: .red)   // SwiftUI's full spelling (RT-O 8)

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
    public func underline(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text   // RT-O 8
    public func strikethrough(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text
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
        public mutating func appendInterpolation<T>(_ value: T)   // String(describing:), not deprecated (RT-C 3, RT-O 6; divergence 156)
        public mutating func appendInterpolation(_ text: Text)    // keeps runs (RT-C 4); stores runs, not the Text
        public mutating func appendInterpolation(_ attributedString: AttributedString)   // keeps runs (RT-O 4, I3)
        @available(*, deprecated, message: "…") public mutating func appendInterpolation(_ image: Image)   // traps; RT-T 1 (amends RT-O 5), I4
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
divergence 8's fix). **A kerning or tracking of 0 is "no extra space"**: the
CoreText styled path omits `kCTKernAttributeName`/`kCTTrackingAttributeName`
for such a run, because a kern of 0 switches the font's pair kerning off (`K2`;
SwiftUI's `kerning(0)` ≡ plain, `K1`; `RT-O` item 7).

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
| 2 | `Sources/MetalUI/Text.swift`, `ProposalText.swift`, `TextModifiers.swift`, `TextStyleResolution.swift`, `Font.swift` (`monospaced()`), new `TextRuns.swift` (the run model and the `Mirror` operand check, `RT-O` 1 — **not** `Handlers.swift`, which `feat/input-apis` edits), new `RichTextPaint.swift` | new `Tests/MetalUITests/RichTextTests.swift`, `RichTextPaintTests.swift`, `RichTextCompileGuards.swift`; new `Tests/MetalUICrossPlatformTests/RichTextPortableWindowTests.swift`; the `Text` arm of `everyDecorationScopingSiteContainsItsOwnContent` (its file, one arm added); `Tests/MetalUITests/AnimationTests.swift` (doc comment of `everyBackgroundPaintingSiteAnimatesItsColour` only, `RT-O` 13) |
| 3 | new `Sources/MetalUI/LocalizedStringKey.swift`, `MarkdownInline.swift`, `TextAttributes.swift`; the demo (`RT-O` 10): `Sources/MetalUIDemoContent/RichTextDemo.swift` (new), `Sources/MetalUIDemo/main.swift` and `Backends/SDL/Sources/MetalUISDLDemo/main.swift` (the env switches) | new `Tests/MetalUICrossPlatformTests/MarkdownInlineTests.swift`, `LocalizedStringKeyTests.swift`, `AttributedTextTests.swift`; new `Tests/MetalUITests/MarkdownOracleTests.swift` (Darwin, Foundation's parser), `TextLiteralCompileGuards.swift`; `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift` (the new tree, own `@inline(never)` function) |

**Shared registries** (append-only, each lane its own rows, in its own
commits): `docs/probes/closeout-inventory-map.tsv` (+ the census re-recorded
with `closeout-public-api.sh` at each lane's end). Lane 3 alone writes
`docs/divergences.md` rows 150–156, `docs/verification/human-checks.md` group
"RT" (provisional letter, settled at the merge, `RT-O` 2), `docs/migration.md`, `docs/api-overview.md`, and the decisions doc's
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
  Sans before relying on it; a disagreement is an amendment ruling. Records
  test 1.19's literals on `70ed000`'s code **before its first source change**,
  and runs the demo-pixel compare (it changes the plain path's internals,
  `RT-O` 11).
- **Lane 2 — the `Text` element.** Run model, initialisers
  `init<S: StringProtocol>`/`init(verbatim:)`, `Text`-level modifiers, `+`
  with its trap, styled layout and paint, decorations, links (styled, inert),
  accessibility string, `ProposalText` parity, the `Mirror` operand check.
  Its tests build styled text with modifiers and `+` (through a deprecated
  protocol witness called generically, `LR-CV`'s pattern, `RT-O` 9) — no
  Markdown, which is lane 3's. No demo (it moved to lane 3).
- **Lane 3 — the front ends and registries.** `LocalizedStringKey` (literals
  start parsing here), the Markdown parser, interpolation, the attribute scope
  and `Text(AttributedString)`, the Foundation oracle, the demo (§6, macOS
  and SDL switches) and the shared registries (§2). Runs the full demo-pixel
  compare and the Linux image again (the parser is portable code, and the SDL
  demo switch is a `Backends/SDL` change).

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
| 1.1 | `aOneRunStyledTextMeasuresAsThePlainCallsOnBothSystems` (`StyledTextSeamTests`) | for a corpus (Latin, a pair-kerned Latin string — `try #require` its plain width is below the sum of its glyph advances, `RT-O` 7 — Arabic, a hard break, an emoji that falls back) × widths nil/40/0.5 × options (limit 2 tail/head/middle, centre), a one-run `measure(StyledText)` equals the plain `measure` (widest, total) and its lines' heights are all `fontMetrics.lineHeight` | stub returns zeros | (a) CoreText: take the line height from `CTLineGetTypographicBounds` (fallback faces included) — the emoji arm reddens; (b) CoreText: always set `kCTKernAttributeName` (0 included) — the kern-pair arm reddens (`K2`) |
| 1.2 | `aOneRunStyledTextPlacesThePlainGlyphsOnBothSystems` | `layOut(...).glyphs.map(\.glyph)` == `placeGlyphs(...)` for the same corpus at scale 1 and 2; every run index 0 | stub returns `[]` | portable `StyledLayout`: round the baseline before scaling (`(baseline).rounded() * scale`) |
| 1.3 | `aRunBoundaryIsNotABreakOpportunity` (`C4`, `C4c`) | `"foo"` + `"bar"` (two runs, regular/bold) at `width("foobar") − 3` keeps one line (lines == the plain `"foobar"`'s) on both systems | stub breaks per run | portable: mark `.allowed` at each run boundary in the break table |
| 1.4 | `breaksBetweenRunsFallWhereCoreTextPutsThem` (`C4d`) | `"word "`+bold `"next"`+`" more"` at 40 → ranges `0..<5`, `5..<10`, `10..<14` on both | stub | portable: reshape from each line start with run 0's font (`font: runs[0]`) — unreachable from 1.4 (re-shaping happens only at a line start inside a cluster); reddens 1.10's narrow arm (`RT-Q` 2) |
| 1.5 | `aMixedLineTakesTheLargestAscentAndDescent` (`C5`, `C6`; `RT-G` 1–2) | 10 pt + 30 pt on one line: height == 30 pt `lineHeight`, baseline == 30 pt ascent; wrapped so line 1 is 10 pt only and line 2 holds the 30 pt run: heights `[lh10, lh30]`, line 2 top == `lh10` | stub uses the first run | sum ascents instead of taking the max (`ascent += …`) |
| 1.6 | `aBaselineOffsetGrowsTheLineAndMovesItsGlyphs` (`C7`, `C7d`) | +5 and −5 on a run: line height == `lineHeight + 5` both; the run's glyphs' `baselineY` == line baseline ∓ 5·scale | stub ignores offset | shrink the descent for a positive offset (CoreText's rule, `descent − offset`) — the +5 single-run arm reddens (`RT-Q` 1); flip the glyph sign — the glyph arm reddens |
| 1.7 | `kerningAddsAfterEveryGlyphAndKeepsLigatures` (`C8`, `C8e`, `F1`) | kerning 4: widest == plain + 4 × glyph count (last glyph included) on both; glyph count unchanged on a ligature string in a face that ligates it (lane 1 picks it from the test faces, e.g. Noto Sans "office") | stub | skip the last glyph's kern (`dropLast()`) |
| 1.8 | `trackingBreaksLigaturesOnBothSystems` (`C8e`) | tracking 4 on the same string: glyph count == the unligated count; widths agree between systems to 1e-3 | stub | `HarfBuzzShaper.shape` ignores `features` |
| 1.9 | `theEllipsisTakesTheFirstRemovedCharactersRun` (`C13`, `C13b`, `C13d`, `C19`; `RT-I`) | tail, head and middle: the ellipsis glyph's run index is the first removed character's; a removed 30 pt run makes the truncated 10 pt line `lh30` tall | stub uses run 0 | attribute the token with the last **kept** character's run — the head arm and the `C19` arm redden (the tail arms alone cannot separate) |
| 1.10 | `everyStyledCorpusCasePlacesTheSameGlyphsAsTheApplePath` (`StyledTextOracleTests`) | the CoreText oracle (`RT-H` 5): a corpus over the three test faces (mixed sizes and faces, kerning, tracking, offsets, wraps, Arabic + Latin bidi, limits) at scales 1 and 2 — same glyph keys, positions, line boxes and segments | stub | portable `shapeCascading`: choose the covering face from the base font for every unit (`coveringFace(c, font: runFonts[0])`) |
| 1.11 | `theDecorationMetricsAgreeOnBothSystems` | `decorationMetrics` for the three faces × five sizes: position and thickness to 1e-4 (TrueType exact, `PT-B`'s fraction rule), strikethrough == xHeight / 2 | stub zeros | FreeType: take the strikethrough from OS/2 `yStrikeoutPosition` |
| 1.12 | `segmentsSpanTheirAdvanceAndLinesKnowTheirVisibleExtent` (`C9k`, `C9w`, `F4`) | `"x   "` / `"   x"` / `"x"`+`"   "`+`"x"` with kerning: segment extents include kerning; `visibleMinX/MaxX` exclude a line's leading/trailing whitespace and include interior whitespace, both systems | stub | include trailing whitespace in `visibleMaxX` |
| 1.13 | `bidiRunsSplitIntoOneSegmentPerVisualPiece` | Latin–Arabic–Latin, the Arabic split into two runs at its digits (`RT-P` item 6: a visual piece is a maximal visually contiguous span of one run, so one Arabic run is one piece): runs `[0, 2, 1, 2, 1, 3]` in visual order, extents equal on both systems | stub one segment per run | emit segments in logical order |
| 1.14 | `aWarmStyledFrameShapesNothing` | two frames over the same `StyledText`: `ShapingCache.misses` unmoved on the second; the portable measurement cache answers the second from its entry (counted) | stub uncached | key the styled cache entry by `string` only (two styled texts with one string share an entry — the arm with two run splits reddens) |
| 1.15 | `aStyledTextWhoseLengthsDoNotSumTraps` (exit test) | `StyledText("abc", runs: [length 2])` exits with a signal | — (new trap) | delete the precondition |
| 1.16 | `zeroLengthRunsAreDroppedAndEqualNeighboursMerge` (`StyledTextPortableTests`, runs on Linux) | normalization; an empty string keeps its first run's style (`C17`) | stub | skip the merge |
| 1.17 | `thePortableSystemLaysOutAStyledTextOnEveryPlatform` (`StyledTextPortableTests`) | Noto Sans 10/30 mixed line and a +5 offset: heights and baselines from `PortableFontMetrics`, on Linux too | stub | as 1.5 |
| 1.18 | `disablingLigaturesShapesTheLigatureAsSeparateGlyphs` (`ShapingFeatureTests`) | HarfBuzz with `liga`/`clig` off: one glyph per letter of the ligated string | stub | ignore `features` |
| 1.20 | `spacingIsOncePerGraphemeAndKeepsPairKerningAcrossRuns` (`StyledTextSeamTests`; added by lane 1, `RT-P` items 3–5) | kerning/tracking once per grapheme (`"e\u{301}\u{302}x"` +2×), pair kerning kept across a kerning/tracking boundary (`"A"`+tracked `"V"` = plain `"AV"` + 1), both systems' glyphs equal except CoreText's tatweels in kerned/tracked joined Arabic (present on CoreText, absent on portable) | written after the implementation; red on the predecessor's per-glyph spacing (mutation) | add the spacing to every glyph — mark and Arabic arms; split a shaping run where tracking starts — the `"AV"` arm |
| 1.19 | `theDemoDoesTheSameTextWorkAsBefore` (`Tests/MetalUITests/StyledTextSeamTests.swift`; `RT-M` 1, moved from lane 2 by `RT-O` 11) | the main demo's first and warm frames: `ShapingCache` misses and lookups equal literals **recorded on `70ed000`'s code before lane 1's first source change** (stated in the test with the commit) | green on arrival by design (a must-not-move pin) | (lane 1) key the plain cache by `(string, font, width)` without the options — the warm-frame literal moves; (lane 2, re-run) route every `Text` through the styled path (predicate `true`) |

### §4.2 Lane 2 — the `Text` element

Tests that use `+` call it through a `@available(*, deprecated)` protocol
witness reached through a generic constraint (`LR-CV`, `swift-deprecated-witness-silence.sh`;
a bare deprecated helper called from a `@Test` warns — `RT-O` 9).

| # | test (file) | asserts | red before | mutation |
|---|---|---|---|---|
| 2.1 | `concatenationPushesEachSidesTextFieldsIntoItsUnsetRuns` (`RichTextTests`; `C2`, `C2b`, `C3`, `C3b`, `C12b`) | per-run resolved descriptors and colours: an inner colour/weight/font wins, the outer reaches only unset runs | compile (no `+`) | `resolve`: `text.field ?? run.field` (outer wins) |
| 2.2 | `aStyledTextMeasuresAsCoreTextsAttributedLine` (`C1`) | `Text("Ab").bold() + Text("cd")` answers CoreText's attributed line width (derived in the test with `CTLineGetTypographicBounds`) | stub plain | measure the concatenated plain string |
| 2.3 | `aPlainTextTakesThePlainCalls` (`RT-F` 3) | a spy `TextSystem` (forwarding every requirement to the real system, `RT-O` 15) records calls: `Text("a")`, `Text("a").bold().foregroundColor(.red).italic()`, `Text("a").font(.title)` reach only the plain requirements; `Text("a").underline()`, `.kerning(0)`, a two-run text reach only the styled ones | stub | invert the fast-path predicate's `kerning` clause |
| 2.4 | `aStyledTextPaintsEachRunsColour` | scene sprites: run 1's glyphs red, run 2's blue | stub single colour | colour every glyph with run 0's colour |
| 2.5 | `anUnderlineIsARectAtTheFacesPosition` (`RT-J` 2–3, `C9w`) | the rect's centre `baseline − underlinePosition`, height `underlineThickness`, x extent the segment clipped to the visible extent (`"x   "` arm) | stub none | drop the visible-extent clip |
| 2.6 | `aStrikethroughSitsOnHalfTheXHeight` (`C9s`, `C9ms`) | centre `baseline − xHeight/2` for 13 pt and 30 pt runs on one line | stub | use the line's tallest run's metrics for every strike |
| 2.7 | `sameColouredUnderlinesMergeAndOthersDoNot` (`C9m`, `C9b`, `F3`, `F2`) | 10 pt + 30 pt both underlined, one colour: one rect at the 30 pt geometry across both; different colours: two rects, own geometry; strikethroughs: two rects | stub | (a) never merge — the `C9m` arm; (b) merge regardless of colour — the `F3` arm |
| 2.8 | `aBackgroundFillsTheRunByTheLineBox` (`C11bg`, `C11bg2`, `F4e`) | rect: segment extent (trailing spaces included) × the line box; a 10 pt run beside a 30 pt one fills the 30 pt line | stub | use the run's own font line height |
| 2.9 | `aWarmFrameOfAStyledTextShapesNothing` | a window, two frames: `ShapingCache.misses` unmoved on the second (layout and paint ask the same question); every first-frame `layOut` width equals the text's own (fractional) answer (`RT-R` item 3) | stub | paint lays out at `bounds` width instead of `measuredWidth` |
| 2.10 | (moved to lane 1 as 1.19, `RT-O` 11; lane 2 re-runs its styled-path mutation) | — | — | — |
| 2.11 | `aStyledTextIsOneShadowLeaf` (`GX-J`) | under `.shadow`, one shadow raster whose leaf holds the background rect, glyphs and underline | stub | emit the underline after `endLeafGroup` |
| 2.12 | the styled `Text` arm of `everyDecorationScopingSiteContainsItsOwnContent` (`OM-AI`, `OM-V`) | a faded, clipped, bordered styled `Text`: rects and glyphs at alpha 0.5, inside the clip, before the border | stub | call `drawStyledText` outside `paintDecoration`'s closure |
| 2.13 | `aStyledTextPublishesItsConcatenatedString` (`RT-L` 1) | the AX record's text is the whole string; an all-empty concatenation publishes none | stub | publish the first run's string |
| 2.14 | `aMixedTextCapsLinesByTheirSummedHeights` (`C16`, `C16b`) | a 10-pt line then a 30-pt line: proposal height `lh10 + lh30 − 1` keeps one line, `lh10 + lh30` keeps two (`C16b`: 47 → 13 tall, 48 → 48) | stub | (a) cap by `⌊h / firstLineHeight⌋` — the first arm; (b) cap by `⌊h / tallestLineHeight⌋` — the second |
| 2.15 | `reservedSpaceUsesTheFirstRunsLineHeight` (`C18`) | `lineLimit(3, reservesSpace: true)`: `B30 + a10` → 3 × lh30; `a10 + B30` → max(3 × lh10, lh30) | stub | use the tallest line |
| 2.16 | `aMixedTextReportsBaselinesFromItsLines` (`RT-G` 2) | first `round(ascent₁)`, last `top(last) + round(ascentₙ)` for the `C6` shape | stub | plain formula `first + (n−1) × lineHeight₀` |
| 2.17 | `aLinkDrawsInTheAccentUnlessItsRunIsColoured` (`RT-K`; `M6`, `C11lnc`, `C11lne`) | link run colour `.accent`; red run red; under `.foregroundStyle(.green)` still accent | stub | let the environment's `foregroundStyle` reach a link run |
| 2.18 | `aLinkRegistersNothingAPlainTextDoesNot` (`RT-K`, divergence 150) | hitboxes, focus entries and AX records equal those of the same text without the link | stub | register a pointer hitbox per link segment |
| 2.19 | `concatenatingADecoratedTextTraps` (exit tests: `.margin` — `.padding` cannot be an operand, `RT-R` item 2 — `.background`, `.onClick`, `.id`, and a plain control) (`RT-E` 4, divergence 155) | each exits with a signal | — | delete the precondition |
| 2.20 | `theOperandCheckSeesEveryHandlersMember` (`RT-O` 1) | `try #require` every `Mirror` child of `Handlers()` is a recognised kind (optional, collection/dictionary, `Equatable`) and the child count is 17; 17 arms: setting any one member fails the check | stub `true` | (a) drop the optional rule — the optional members' arms; (b) drop the `Equatable` rule — `isFocusable`, `allowsHitTesting`, `axNode`; (c) drop the collection rule — `actions`, `gestures` |
| 2.21 | `aOneRunStyledTextDrawsThePlainSprites` | a window: `Text(s).kerning(0)` (styled path) and `Text(s)` (plain), `s` a pair-kerned string on two centred lines, the first shorter (`RT-R` item 7), draw identical glyph primitives | stub | (a) offset the styled paint origin by the line's `offsetX` twice; (b) lane 1's always-set-kern mutation |
| 2.22 | `proposalTextDrawsTheSameStyledSpritesAsText` | `ProposalText` and `Text` of one styled content: equal scene glyphs and rects | stub | `proposalLayout()` drops `content` |
| 2.23 | `aRunsColourSnapsUnderAnAnimation` (`RT-L` 2) | `withAnimation` changing a run's colour: the next frame draws the new colour | green on arrival (pin) | route run colour through `animatedColor` |
| 2.24 | `theTextModifiersComposeAsSwiftUIs` (`RichTextCompileGuards`, `typecheckFile`, plain import) | compiles: `Text("a").bold().underline(color: .red).kerning(1) + Text("b")` (in a deprecated function), `Font.body.monospaced()`, `.underline(true, pattern: .solid, color: .red)` (`RT-O` 8); does **not** compile: `Text("a").lineLimit(1) + Text("b")`, `.underline(pattern: .dash)`, `Text.LineStyle.Pattern.dash` | compile | each arm mutated red once (e.g. add a `dash` static) |
| 2.25 | `theConcatenationOperatorIsDeprecated` (guard) | compiling `Text("a") + Text("b")` in a non-deprecated context emits the deprecation warning with SwiftUI's message | compile | remove the `@available(*, deprecated…)` |
| 2.26 | `aStyledTextDrawsThroughThePortableSystem` (`RichTextPortableWindowTests`, Linux too) | a headless frame over `PortableTextSystem`: two glyph colours and an underline rect at the Noto Sans geometry | stub | as 2.4 |

### §4.3 Lane 3 — front ends

| # | test (file) | asserts | red before | mutation |
|---|---|---|---|---|
| 3.1 | `theInlineGrammarMatchesTheProbedRuns` (`MarkdownInlineTests`, Linux too) | every `M` and `N` row of the Foundation probe (text, bold/italic/strike/code, link) as literals from the probe header | stub returns the source as one run | (a) intraword `_` opens emphasis — `M12a`, `N9`, `N20`; (b) no extended autolinks — `M15b`, `M20`, `M21`, `M26`, `N10`, `N11`; (c) keep emphasis inside link text — `M22`; (d) parse block syntax — `M8a` |
| 3.2 | `theParserAgreesWithFoundationOnTheCorpus` (`MarkdownOracleTests`, Darwin) | the probe corpus plus every 4-token combination of `*`, `**`, `_`, `~~`, `` ` ``, `a`, space (generated, `try #require` on the count) parsed by both → equal runs | stub | drop CommonMark's rule of 3 (`(open + close) % 3`) |
| 3.2b | `aFormatTheTriggerScanSkipsParsesToItself` (`MarkdownOracleTests`, Darwin; `RT-T` items 4, 9) | every source of 3.2's corpus that `markdownMayApply` skips parses to itself as one unstyled run; 3.14 gains `ftp://x.org`/`HTTP://x.org` literal arms | added after review (green on arrival, its mutation proves it) | the pre-amendment `http` trigger in place of `://` |
| 3.3 | `onlyTheEntitySubsetDecodes` (divergence 153) | `&amp;`, `&#65;`, `&#x41;`, `&copy;`, `&nbsp;` decode; `&bogus;` and `&alpha;` stay literal | stub | decode an unknown name to U+FFFD |
| 3.4 | `aLiteralParsesAndAValueDoesNot` (`M1`, `M2`, `M14`) | `Text("**b**")` one bold run; `Text(s)` and `Text(verbatim:)` verbatim; `Text(LocalizedStringKey(s))` bold | stub | make `init<S: StringProtocol>` parse |
| 3.5 | `anInterpolatedValueIsVerbatimButTakesTheFormatsStyle` (`M10`, `M10b`) | `"a \(v)"` keeps `**x**`; `"**\(n)**"` bold `n` | stub | substitute before parsing |
| 3.6 | `anInterpolatedValueIsItsDescription` (`M11`, `M11b`, `M29`; divergence 151) | `3.5` → `"3.5"`, `7` → `"7"` | stub | format `Double` with `%lf` |
| 3.7 | `anInterpolatedTextKeepsItsRuns` (`C14`) | `Text("a \(Text("b").bold())")` runs == `Text("a ") + Text("b").bold()`'s | stub | interpolate the text's `.string` |
| 3.7b | `anInterpolatedAttributedStringKeepsItsRuns` (`I3`, `RT-O` 4) | `Text("v \(bold)")` with a bold `AttributedString` runs == `Text("v ") + Text("BOLD").bold()`'s, never its description | stub | delete the `AttributedString` overload (the generic one takes it) |
| 3.8 | `interpolatingADecoratedTextTraps` (exit test) | `Text("a \(Text("b").onClick {})")` exits | — | delete the check |
| 3.9 | `anAttributedStringBuildsTheConcatenationsRuns` (`C11`, `C12`, `C12b`) | every key's run equals the modifier spelling's | stub | ignore `kern` |
| 3.10 | `theInitialisersReachSwiftUIsOverloads` (`TextLiteralCompileGuards`, plain import) | compiles `Text("lit")`, `Text(substring)`, `Text(verbatim:)`, `Text("n \(1.5) \(Text("b"))")`; `let k: LocalizedStringKey = "x"`; `Text("v \(Plain())")` with **no** message (divergence 156, `I1`/`I2`); `Text("v \(Image(…))")` compiles **with the deprecation message** naming the absence (`RT-T` item 1, amending `RT-O` 5) | compile; the Image arm red on the unavailable stub | (a) remove `@_disfavoredOverload` from `init<S>` (the literal arm turns ambiguous); (b) deprecate the generic overload — the no-message arm; (c) delete the deprecated `Image` overload — the `Image` arm |
| 3.10b | `interpolatingAnImageTraps` (`LocalizedStringKeyTests`, exit test; `RT-T` item 1) | interpolating an `Image` (through a deprecated witness) exits naming the absence | the unavailable stub wrote the description | make the overload append the description |
| 3.11 | `inlinePresentationIntentIsHonouredOnDarwin` (`C12c`; `#if canImport(Darwin)`) | `Text(try AttributedString(markdown: "**b** _i_ ~~s~~ `c`"))` runs == `Text("**b** _i_ ~~s~~ `c`")`'s | stub | ignore the intent |
| 3.12 | `everyAttributeKeyIsWritableWithAPlainImport` (guard, `typecheckFile`, `SA-P`) | `s.font = .body`, `s.foregroundColor = .red`, `s.backgroundColor = .yellow`, `s.underlineStyle = .single`, `s.strikethroughStyle = .single`, `s.kern = 1`, `s.tracking = 1`, `s.baselineOffset = 1`, `s.link = …` with `import MetalUI` only, and again with `import AppKit` | compile | delete the per-key `foregroundColor` subscript — ambiguous (probe `generic UsePlain`) |
| 3.13 | `theCodeSpanIsMonospaced` (`M5`; `RT-O` 12) | the code run's descriptor has design `.monospaced` (system face) — on the portable system the face is whatever `TE-B` resolves for that design (registered family, else default) | stub | map code to italic |
| 3.14 | `aMarkdownLinkAndAnAttributedLinkBuildOneRunKind` | both store the destination on `link`; `M20`'s is `http://www.x.org`, `M21`'s `mailto:a@b.org` | stub | drop the `http://` prefix for `www.` |
| 3.16 | `aLiteralWithNoMarkupRunsNoParser` (`RT-O` 14) | building the main demo tree: an internal parse counter stays 0 (every literal there has no trigger character); `Text("**b**")` moves it by 1 | stub counter always 0 → the `**b**` arm | always run the parser — the demo arm |
| 3.17 | `theRichTextDemoDrawsThroughThePortableSystem` (`LocalizedStringKeyTests`; `RT-T`) | the demo renders headlessly over `PortableTextSystem` without a trap: > 300 glyphs in ≥ 5 colours, red/blue/orange glyphs and the yellow background drawn, the parser run | written with the demo (not red-first: a must-not-trap pin) | drop a section's styling (e.g. the attributed string's keys) — the colour arms |
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
  Linux and Windows run; lane 2's portable window test too; lane 3's SDL demo
  switch): the root
  package's portable test targets in `swift:6.4-noble` (`MetalUILayoutTests`,
  `MetalUICoreTests`, `MetalUICrossPlatformTests`, as CI), and
  `Backends/SDL`: `docker build -t metalui-portable -f
  Backends/SDL/linux/Dockerfile Backends/SDL`, then `docker run --rm -v
  "$PWD":/work -v metalui-sdl-build-rich-text:/tmp/build -w /work/Backends/SDL
  metalui-portable bash -c 'swift build --build-tests --scratch-path
  /tmp/build && swift test --skip-build --scratch-path /tmp/build'`. The only file
  under `Backends/SDL` that changes is lane 3's demo switch
  (`MetalUISDLDemo/main.swift`, `RT-O` 10); the package must still build (its
  `PortableTextSystem` use compiles against the new requirements).
- **Pixels**, lanes 1, 2 and 3 (`RT-O` 11): `docs/probes/demo-pixels/compare.sh <scratch>
  70ed000 HEAD` — fourteen images, 0 px.
- Windows: CI's `root-windows` on push (FoundationEssentials'
  `AttributedString` there is the same swift-foundation code `L1` ran on
  Linux; not run locally by the design session). The UTM VM may be used by
  lane 3 if CI disagrees.

## §6 Demo expectation (lane 3, `RT-O` 10)

`METALUI_RICH_TEXT_DEMO=1 swift run MetalUIDemo` opens a window of sections,
each its own function (1 MB Windows stack): **Markdown** (one literal with
bold, italic, bold-italic, strikethrough, code, a link and a bare URL);
**interpolation** (coloured and weighted `Text` segments interpolated into a
literal, `C2`'s shape — **never `+`**, which warns, `RT-O` 9); **mixed sizes** (a 10/20/30-point paragraph wrapping
across lines); **decorations** (underline, coloured underline, strikethrough,
background, kerning, tracking, baseline offset as superscript); **truncation**
(a two-colour line under `lineLimit(1)` in tail and head modes);
**attributed** (`Text(AttributedString)` with every key). Not one of the
fourteen images; added to `buildEveryProductionTree`. The SDL demo gets the same switch
(human check RT4). Launched only when the lock probe allows, killed after a
few seconds.

## §7 Human checks — group "RT" (provisional letter; lane 3 writes it; an agent cannot run it)

`feat/input-apis` also writes a group Y; the letter is settled at the merge
(`RT-O` 2, `feat/variable-height-list`'s precedent).

- **RT1** The rich-text demo on macOS: every Markdown form reads as styled
  (bold, italic, struck, monospaced, accent-coloured links and URL), in light
  and dark.
- **RT2** Underlines and strikethroughs at 1× and 2× displays: crisp enough
  beside a SwiftUI `Text(…).underline()` (divergence 152's unsnapped band).
- **RT3** The mixed-size paragraph: line spacing looks even and no glyph is
  clipped by its line; the superscript sits above the line without touching
  the line above.
- **RT4** The same demo on Linux and Windows (SDL, `METALUI_RICH_TEXT_DEMO=1`):
  matches macOS by eye, except code spans, which draw the default face unless
  the app registered a monospaced family (`TE-B`, `RT-O` 12).
- **RT5** VoiceOver on a styled `Text` reads the whole sentence once, without
  Markdown markers; a link is read as plain text (divergence 150).
- **RT6** Clicking a link does nothing and the cursor does not change
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
  (divergence 151); any other interpolated value prints its description with
  no warning (divergence 156); an `AttributedString` keeps its runs; an
  `Image` does not compile (`Text(Image)` is not offered).
- On Linux and Windows a code span (`` `x` ``) draws the family registered for
  the `.monospaced` design (`PortableFontResolver.register(design:family:)`),
  else the default face (`TE-B`).

### §8.2 Divergences lane 3 writes (`docs/divergences.md`, labels 150–158; 157 added by `RT-P` 5, 158 by `RT-R` 6)

| # | what differs | SwiftUI | MetalUI | ruling | pin |
|---|---|---|---|---|---|
| 150 | links in text | a link run opens its URL through `openURL` on click and is an accessibility link (rendered `M6`, `C11ln`; the action not probed headless) | a link run is styled (accent unless coloured) and inert; its text is part of the text's string | `RT-K` | `aLinkRegistersNothingAPlainTextDoesNot` (2.18) |
| 151 | an interpolated floating-point value in a `Text` literal | formatted with `%lf`: `"v \(3.5)"` draws `v 3.500000` (`M11`) | `String(describing:)`: `v 3.5`; integers agree (`M11b`) | `RT-C` 3 | `anInterpolatedValueIsItsDescription` (3.6) |
| 152 | underline and strikethrough placement | snapped to device pixels by TextKit (`C9`: rows 28–29 at 13 pt, scale 2) | the face's unsnapped band (underline position/thickness; strikethrough at x-height / 2) | `RT-J` 2 | `anUnderlineIsARectAtTheFacesPosition` (2.5) |
| 153 | named character references in a literal | HTML5's named entities decode (`M35`: `&alpha;&hearts;` → `α♥`; Foundation's parser `N21`); a name that is no entity stays literal (`N12`) | numeric references and a fixed subset of 34 names decode; any other name stays literal | `RT-B` 4 | `onlyTheEntitySubsetDecodes` (3.3) |
| 154 | Markdown in control titles | `Button("**b**")`, `Toggle("**b**", …)` draw bold labels (`M30`, `M31`) | controls' `String` titles are verbatim | `RT-A` | `aControlTitleIsVerbatim` (3.15) |
| 155 | concatenating a decorated `Text` | does not compile (`.padding()` etc. return `some View`) | compiles (they return `Self`) and traps at the `+` (or the interpolation), naming the field | `RT-E` 4 | `concatenatingADecoratedTextTraps` (2.19) |
| 156 | interpolating a value of a type with no dedicated overload | `String(describing:)`, through a **deprecated** overload (`I1`, `I2`: two warnings, "Localized string interpolation produces an unlocalized, debug description…") | the same text, no warning | `RT-O` 6 | `theInitialisersReachSwiftUIsOverloads` (3.10) |
| 158 | `Text.bold()` | semibold on the default font, heavy on `.headline`, nothing on `.light` (`swiftui-text-semantics.swift` X1, F2e, X1b) | the bold weight over whichever font resolves (`Font.bold()`'s, X1c) | `RT-R` 6 | `concatenationPushesEachSidesTextFieldsIntoItsUnsetRuns` (2.1, `C2b` arm) |
| 157 | kerning or tracking on joined Arabic, on Linux and Windows | CoreText (macOS) inserts tatweel (kashida) glyphs carrying the space between joined letters (`S2b`, `coretext-styled-spacing.swift`; SwiftUI draws through CoreText, not probed separately) | the portable system adds the same space as a gap; widths and every other glyph agree | `RT-P` 5 | `spacingIsOncePerGraphemeAndKeepsPairKerningAcrossRuns` (1.20) |

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
sections for divergences 150–156; record §03/§05 rows; `docs/record/README.md`
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
offsets and line ranges are plain-text APIs); `Handlers.swift` untouched
(`RT-O` 1). Fourteen offscreen images 0 px
against `70ed000`; `DemoFrameDeterminismTests`' `Expected.swift` unedited;
0 `warning:` on both build systems; `MetalUILayout` imports only
`MetalUICore`; `MetalUIScene` only `MetalUIShaderTypes`; `MetalUITextSystem`
only `MetalUIScene`; `MetalUIPortableText`'s import list unchanged (`PT-A`);
`MetalUIHarfBuzz` only `CHarfBuzz`; `MetalUIFreeType` only `MetalUIScene`,
`CFreeType`; no shader change (`shaders.metal`, `replay.hlsl` untouched);
`Backends/SDL` and `swift:6.4-noble` build;
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.
