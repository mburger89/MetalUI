# Rich text — decisions

Rulings for styled runs inside one `Text` on both text systems: Markdown in a
string literal, `Text` interpolation and `Text + Text`, `Text(AttributedString)`,
per-run font, colour, underline, strikethrough, background, kerning, tracking
and baseline offset, and links as styled (inert) runs (user request
2026-10-02, item 6 of the gpui-gap priority list; **not a plan task**).
Spec: [`specs/2026-10-08-rich-text-design.md`](specs/2026-10-08-rich-text-design.md).
Record: `../record/83-rich-text.md`.

Evidence (each header carries its recorded output and how to run it):

- [`../probes/swiftui-rich-text.swift`](../probes/swiftui-rich-text.swift)
  (**new**; arms `P0a`–`P0c` positive controls, `M1`–`M34` Markdown in a
  literal, `C1`–`C19` concatenation, attributed strings, mixed lines,
  decorations, links, truncation, `F1`–`F4e` the second pass; compiled twice
  byte-identical, interpreted once) — SwiftUI's answers, headless
  (`ImageRenderer` and a measuring `Layout`).
- [`../probes/foundation-markdown-inline.swift`](../probes/foundation-markdown-inline.swift)
  (**new**; `M*` and `N1`–`N20` on macOS, `L1`–`L3` in `swift:6.4-noble`) —
  what Foundation's inline Markdown parser answers on macOS (every `M` row
  agrees with SwiftUI's render), and that neither it nor
  `inlinePresentationIntent` exists on Linux.
- [`../probes/swift-attribute-scope-ambiguity/run.sh`](../probes/swift-attribute-scope-ambiguity/run.sh)
  (**new**) — a MetalUI attribute scope beside AppKit's: a generic dynamic
  member subscript is ambiguous on `.red`, a per-key one is not.

Where SwiftUI has no answer (the seam between `Text` and a text engine, a
Linux Markdown parser, what a portable shaper does with kerning) the ruling
says so; gpui is named as a comparison where it has one (`StyledText`'s
`TextRun { len, font, color, background_color, underline, strikethrough }`,
`InteractiveText` for clickable ranges), never as evidence.

Prefix **`RT-`**, lettered. **Next unused: `RT-S`.** (This line moves in the
commit that appends a ruling; read the last `## RT-` heading.)

Branch `feat/rich-text` from `70ed000` (master: portable app merged, PR #51).
Parallel branches: `feat/input-apis` (record §81) and
`feat/variable-height-list` (record §82); this branch stays off their files
and takes divergence labels from its reserved range **150–159**.

---

## RT-A — Scope: what this branch builds, what it defers

**Ruling.** Built, on both text systems (CoreText on macOS,
`MetalUIPortableText` on Linux and Windows):

1. **Styled runs inside one `Text`** (and `ProposalText`): per-run font
   (family, size, weight, italic, design), foreground colour, background
   colour, underline and strikethrough (solid, with an optional colour),
   kerning, tracking, baseline offset, and a link (styled, inert — `RT-K`).
2. **Three ways to write them**, each SwiftUI's spelling: inline Markdown in a
   string literal (`RT-B`, `RT-C`), `Text` interpolation and the deprecated
   `Text + Text` with per-segment `Text` modifiers (`RT-C`, `RT-E`), and
   `Text(AttributedString)` over MetalUI's own attribute scope (`RT-D`).
3. **One neutral run model at the text seam** (`RT-F`) — Foundation-free, in
   `MetalUITextSystem` — measured, wrapped, truncated, shaped and placed by both
   systems, with per-line metrics (`RT-G`), breaking across run boundaries
   (`RT-H`), and decorations drawn as ordinary rects (`RT-J`).

Deferred, each with its reason and owner (spec §9 repeats the list):

- **Interactive links** (`openURL`, a click or keyboard activation, an
  accessibility link element): needs per-run hit regions inside one leaf and a
  platform URL opener — hit testing and accessibility must not move on this
  branch. Owner: none scheduled (divergence 150).
- **`Text.LineStyle` patterns other than `.solid`** (`.dot`, `.dash`,
  `.dashDot`, `.dashDotDot`; SwiftUI draws them, `C10d`): a dash geometry
  probe and a rect-per-dash emitter. Owner: none (documented absence).
- **View-level `bold()`, `underline()`, `strikethrough()`, `kerning()`,
  `tracking()`, `baselineOffset()`, `monospaced()` on any `ElementGroup`**
  (SwiftUI's environment versions): this branch offers them on `Text` only.
  Owner: none (documented absence; additive later as environment keys read
  by `resolveTextStyle`).
- **Markdown titles on controls** (`Button("**b**")`, `Toggle`, `Picker`,
  `TextField` placeholders: SwiftUI parses them, `M30`, `M31`): their
  initialisers take `String`. Owner: none (divergence 154).
- **Localization**: `LocalizedStringKey` here is a Markdown-and-interpolation
  carrier with no string tables (`tableName:bundle:comment:` not offered).
  Owner: none (documented absence).
- **`Text(Image)` and images interpolated into `Text`**, `textCase`,
  `textScale`, `fontWidth`, `monospacedDigit()`, `Text.DateStyle`/formatters
  in interpolation, `AttributedString` attributes outside MetalUI's scope
  (AppKit/UIKit/SwiftUI scopes, paragraph styles, `languageIdentifier`).
  Owner: none (documented absences).
- **Rich `TextField`/`TextEditor`**: they stay plain `String` editors; caret
  offsets, line ranges and IME are plain-text APIs (`TI-E`, `TI-H`) and do not
  learn runs. Owner: none.
- **Animated run colours**: a run's foreground, underline and background
  colours snap, as a plain `Text`'s glyph colour always has (`RT-L`).

**Cost if wrong.** Each deferral is additive: none changes a type this branch
ships except links (a later interactive link adds a hit region per link run,
behind the same `link` attribute this branch already stores).

---

## RT-B — Markdown: SwiftUI's inline subset, parsed by MetalUI's own parser

**Ruling.**

1. **A string literal handed to `Text` (and `ProposalText`) is parsed as inline
   Markdown; a `String` value is not** — SwiftUI's rule (`M1` literal bold,
   `M2` variable verbatim, `M14` an explicit `LocalizedStringKey(variable)`
   parses). `Text(verbatim:)` never parses.
2. **The grammar is SwiftUI's**, which is Foundation's
   `AttributedString(markdown:options: .inlineOnlyPreservingWhitespace)` on
   macOS — every `M` arm of the SwiftUI probe agrees with the Foundation
   probe's row, including the odd one (`M22`: emphasis inside a link's text is
   dropped). Concretely:
   - emphasis `*a*`/`_a_` → italic, strong `**a**`/`__a__` → bold, both nested
     (`M3a`, `M3b`, `M7`, `M16`, `M27`, `N7`), with CommonMark's
     delimiter-run rules — intraword `*` emphasises, intraword `_` does not
     (`M12a`, `M12b`, `N9`, `N19`, `N20`), an unmatched run stays literal
     (`M17`, `N8`), a lone spaced `*` is literal (`M12c`);
   - strikethrough `~a~` and `~~a~~` (GFM; `M4`, `M4b`), not `~~~a~~~`
     (`N15`);
   - code spans `` `a` `` → the run's font made monospaced (`M5`: ≡
     `.monospaced()`), content literal (`M25`), backtick-string rules and the
     one-space strip (`N6`, `N18`);
   - inline links `[text](dest "title")` and `<dest>` destinations (`M6`,
     `M28`, `N4`, `N5`), autolinks `<https://…>` (`M15`), and GFM's extended
     autolinks — bare `http(s)://…`, `www.…` (→ `http://www.…`) and e-mail
     addresses (→ `mailto:`), with trailing punctuation and unbalanced
     parentheses trimmed (`M15b`, `M20`, `M21`, `M26`, `N10`, `N11`);
   - an image `![alt](src)` is its alt text, plain (`M19`);
   - backslash escapes (`M9`, `N14`), a backslash before a newline is a hard
     break (`M24`), entities decode (`M18`, `M23`, `N13`);
   - **everything else is literal**: block syntax (`M8a`–`M8d`), raw inline
     HTML (`N1`, `M32`), reference links and bare brackets (`N2`, `N16`),
     whitespace and newlines exactly as written (`M13`, `N3`, `N17`, `M33`).
3. **MetalUI's own parser** (`Sources/MetalUI/MarkdownInline.swift`, internal,
   pure Swift, no Foundation), on every platform, macOS included — because
   **`AttributedString(markdown:)` does not exist on Linux** (`L2`: "no exact
   matches in call to initializer" under both `import Foundation` and
   `import FoundationEssentials`, Swift 6.4-RELEASE in `swift:6.4-noble`), nor
   does `inlinePresentationIntent` (`L3`). One parser everywhere keeps the
   platforms bit-identical (`PX-C`'s reasoning for the image decoder). On macOS
   the suite uses Foundation's parser as an **oracle**: a corpus of inline
   sources parsed by both must produce the same runs (spec test 3.2).
4. **Named entities: a fixed subset**, decoded on every platform — the five
   XML entities (`amp`, `lt`, `gt`, `quot`, `apos`) and `nbsp`, `copy`, `reg`,
   `trade`, `hellip`, `mdash`, `ndash`, `lsquo`, `rsquo`, `ldquo`, `rdquo`,
   `bull`, `middot`, `deg`, `plusmn`, `times`, `divide`, `euro`, `pound`,
   `yen`, `cent`, `sect`, `para`, `laquo`, `raquo`, `larr`, `rarr`, `uarr`,
   `darr` — plus every decimal and hexadecimal numeric reference. Any other
   named reference is left literal. SwiftUI decodes HTML5's named entities
   beyond any such subset (`M35`: `&alpha;&hearts;` draws `α♥`; Foundation's
   parser also decodes `&ThickSpace;`, `N21`), and keeps a name that is no
   entity literal (`N12`). **Divergence 153.**
   Vendoring the HTML5 table (a licence question and ~30 KB of data) is not
   worth it for a `Text` literal.
5. **Mapping to run attributes**: strong → `fontWeight(.bold)` (`M1` ≡
   `.bold()`), emphasis → `italic()`, strikethrough → `strikethrough()` (no
   colour), code → `monospaced()`, link → the `link` attribute (`RT-K`).
   These are the same run fields `Text`'s modifiers set, so a literal and
   its modifier spelling resolve through one function (`TE-AA`).

**Alternatives.** Parse with Foundation on Apple and a portable parser
elsewhere (two parsers, two answers to every edge case, and a Linux-only
code path nobody on macOS exercises); Markdown only on Apple (a literal that
renders bold on macOS and shows asterisks on Linux); no Markdown at all
(SwiftUI's most common rich-text spelling, silently showing `**`).

**Cost if wrong.** A literal that SwiftUI renders one way and MetalUI another
— caught by the oracle corpus on macOS; a missed case is a parser fix, not an
API change. A literal **already in an app** that contains Markdown syntax
changes rendering when the app upgrades (`**`, `_x_`, `` ` ``, a URL): the
migration note says so and names `Text(verbatim:)` as the escape. The demo's
literals contain none in their format parts (census in spec §0).

---

## RT-C — `LocalizedStringKey`, the initialisers and interpolation

**Ruling.**

1. **`public struct LocalizedStringKey: ExpressibleByStringInterpolation,
   Equatable, Sendable`** with `init(_ value: String)` (parses, `M14`) and
   `init(stringLiteral:)`. It carries the literal's format and its
   interpolated values; parsing happens when `Text` is made from it.
2. **`Text`'s initialisers become SwiftUI's three**: `init(_ key:
   LocalizedStringKey)` (a literal lands here), **`@_disfavoredOverload
   init<S: StringProtocol>(_ content: S)`** (a `String`/`Substring` value,
   never parsed — replaces today's `init(_ string: String)`), and
   `init(verbatim content: String)`. `ProposalText` gets the same three. A
   typecheck guard pins which one each spelling reaches (spec test 3.10).
   Source compatibility: `Text(someString)` still compiles and still renders
   verbatim; `Text.init` used as a function reference (`map(Text.init)`) now
   needs a type annotation — the migration note says so.
3. **Interpolation**: the format (the literal's text between interpolations)
   is parsed as Markdown, and **an interpolated value is inserted verbatim,
   never parsed** (`M10`: `"a \(v)"` with `v = "**x**"` draws the asterisks),
   but it takes the format's attributes at its position (`M10b`:
   `"**\(name)**"` is bold). An interpolated value is written with
   `String(describing:)` for every type — integers agree with SwiftUI
   (`M11b`, `M29`); **floating point does not** (`M11`: SwiftUI's `%lf`
   prints `3.500000`, MetalUI prints `3.5`). **Divergence 151.** Matching
   `%lf` would change every existing `Text("… \(double)")` in every MetalUI
   app for a format SwiftUI users routinely work around. (SwiftUI deprecates
   the generic overload; MetalUI does not — divergence 156, `RT-O` item 6;
   an `AttributedString` keeps its runs and an `Image` is unavailable, items
   4–5.)
4. **A `Text` interpolated into a literal keeps its runs** (`C14`:
   `Text("a \(Text("b").bold())")` ≡ `Text("a ") + Text("b").bold()`), the
   spelling SwiftUI now recommends over `+` (`RT-E`). It obeys `+`'s
   operand rule (a decorated `Text` traps, `RT-E` item 4).
5. **No string tables.** SwiftUI's key is looked up in the bundle's tables
   before parsing; MetalUI has none (documented absence; the
   `tableName:bundle:comment:` parameters are not offered).

**Cost if wrong.** The initialiser change is the one place an existing app's
code can resolve differently: a literal moves from `init(String)` to
`init(LocalizedStringKey)`. It renders the same unless it contains Markdown
(`RT-B` cost) — and `Text("… \(x)")` keeps `x`'s description exactly.

---

## RT-D — `Text(AttributedString)`: MetalUI's own attribute scope

**Ruling.**

1. **Foundation's `AttributedString` exists on Linux** (`L1`: a custom
   `AttributeScope` with dynamic member lookup and Foundation's `link` work in
   `swift:6.4-noble` under both `import Foundation` and
   `import FoundationEssentials`). `Sources/MetalUI` already imports
   Foundation on every platform (`Color.swift`, `EnvironmentValues.swift`), so
   the conversion lives there; `MetalUIScene`, `MetalUITextSystem` and
   `MetalUIPortableText` stay Foundation-free (`TS-A`, `PT-A`): what crosses
   the seam is the neutral run model (`RT-F`). Windows runs the same
   swift-foundation sources; CI's `root-windows` job confirms it on push (not
   run locally by the design session).
2. **`AttributeScopes.MetalUIAttributes`** declares SwiftUI's keys over
   MetalUI's types: `font: Font`, `foregroundColor: Color`,
   `backgroundColor: Color`, `underlineStyle: Text.LineStyle`,
   `strikethroughStyle: Text.LineStyle`, `kern: Double`, `tracking: Double`,
   `baselineOffset: Double`, plus `foundation:
   AttributeScopes.FoundationAttributes` (for `link`). `AttributeScopes.metalUI`
   names it. Doubles where SwiftUI has `CGFloat` (MetalUI measures text in
   `Double` everywhere; a `CGFloat` converts implicitly on Apple).
3. **One non-generic dynamic-member subscript per key**, beside the generic
   one. With only the generic subscript, `attributed.foregroundColor = .red`
   is **ambiguous** in an app that imports MetalUI — even without importing
   AppKit, because `Sources/MetalUI` imports AppKit and extension members leak
   through imports (the probe's `generic UsePlain` row); AppKit's own subscript
   is `@_disfavoredOverload` and still ties. The per-key subscripts win in
   both arms (`per-key UsePlain`, `per-key UseAppKit`). A typecheck guard with
   a plain `import MetalUI` pins every key's spelling (spec test 3.12, `SA-P`).
4. **`Text(_ attributedContent: AttributedString)`** reads the MetalUI keys and
   Foundation's `link` from each run; adjacent runs that resolve alike merge.
   The result is the same run model the other spellings build (`C11`: SwiftUI's
   attributed text ≡ the concatenation, pixel for pixel).
5. **On Darwin it also reads `inlinePresentationIntent`** (bold, italic,
   strikethrough, code; `C12c`: SwiftUI honours it), so
   `Text(try AttributedString(markdown: s))` on macOS draws what SwiftUI draws.
   The attribute does not exist off Darwin (`L3`), so no code that uses it
   compiles there — no silent platform difference (`#if canImport(Darwin)`,
   `PC-B`).
6. **Attributes outside the scope are ignored**: AppKit's, UIKit's, SwiftUI's
   own scope, paragraph styles. (`C12d`: SwiftUI's handling of
   `appKit.foregroundColor` matched neither red nor plain — not a rule this
   branch can copy; documented absence.)

**Alternatives.** Reuse SwiftUI's scope (impossible off Apple; on Apple it
would make `import SwiftUI` a MetalUI dependency); MetalUI's own
`StyledString` type instead of `AttributedString` (a second vocabulary for
what Foundation already ships everywhere).

**Cost if wrong.** A key spelling that turns ambiguous in some import
combination: the guard file names each, and the explicit spelling
(`Color.red`, `attributed[AttributeScopes.MetalUIAttributes.ForegroundColorAttribute.self]`)
always works.

---

## RT-E — `Text + Text`, precedence, and the `Text` modifiers

**Ruling.**

1. **`static func + (Text, Text) -> Text` is offered and deprecated**, with
   SwiftUI's own message: SwiftUI deprecates it in macOS 26.0 — "Use string
   interpolation on `Text` instead: `Text("Hello \(name)")`" (146 warnings
   compiling the probe; 138 when first recorded, `RT-O`). MetalUI's attribute is `@available(*, deprecated,
   message: …)`; the inventory map classifies it `X`. Tests that exercise it
   live in `@available(*, deprecated)` helpers so the suite stays at 0
   warnings (the house pattern, `swift-deprecated-witness-silence.sh`).
2. **Precedence: a segment's own attribute wins; a modifier on the combined
   `Text` reaches only the segments that did not set it** — colour (`C2`),
   weight (`C2b`: `(light + plain).bold()` keeps the light segment light),
   font (`C3`, `C12b`), and a whole-`Text` modifier styles every unset segment
   (`C3b`, `C12`). Implementation: `+` pushes each operand's `Text`-level
   fields into its runs' unset fields; the result's own `Text`-level fields
   start empty and act as the outer layer.
3. **New `Text` modifiers (each returns `Text`)**: `bold()`, `bold(_:)`,
   `underline(_ isActive: Bool = true, pattern: .solid, color: Color? = nil)`,
   `strikethrough(_ isActive: Bool = true, pattern: .solid, color: Color? = nil)`
   (the `pattern:` parameter added by `RT-O` item 8),
   `kerning(_:)`, `tracking(_:)`, `baselineOffset(_:)`, `monospaced(_:)`, and
   on `Font`, `monospaced()`. `Text.LineStyle` is offered with
   `init(pattern: .solid, color: Color? = nil)` and `static let single`;
   `Text.LineStyle.Pattern` has only `.solid` (`C10d`: SwiftUI's dashes are
   real; MetalUI does not draw them — a documented absence, not a silent
   solid). `ProposalText` gets the same modifiers. Kerning and tracking
   differ (`C8e`: on a face with a ligature, `kerning` keeps it and
   `tracking` breaks it — CoreText's `kCTKernAttributeName` and
   `kCTTrackingAttributeName`).
4. **An operand that carries anything but text traps** — a `Style` other than
   `Style()`, a `Decoration` other than `Decoration()`, an `elementID`, or any
   handler (`onClick`, `.padding`, `.background`, `.id`, `.accessibilityLabel`
   …). SwiftUI cannot compile `Text("a").padding() + Text("b")` (those
   modifiers return `some View`); MetalUI's return `Self`, so the refusal
   moves to run time, naming the operand and the field, as every unlowerable
   field does (`LR-AQ`'s spirit). **Divergence 155.** Pinned by an exit test.
   The same rule applies to a `Text` interpolated into a literal (`RT-C`
   item 4).

**Cost if wrong.** A trap where a user expected the decoration to be kept: the
message names the field and the fix (decorate the combined `Text`).

---

## RT-F — The seam: a neutral run model and three defaultless requirements

**Ruling.**

1. **New public types in `MetalUITextSystem`** (no Foundation, `TS-A`):
   `TextRunStyle` (`font: FontKey`, `kerning`, `tracking`, `baselineOffset` —
   the attributes that change layout), `StyledTextRun` (`length` in UTF-16
   units, `style`) and `StyledText` (`string`, `runs`; the initialiser drops
   zero-length runs, merges adjacent equal styles and traps when the lengths
   do not sum to the string's UTF-16 count; an empty string keeps its first
   run's style for its one empty line). UTF-16 lengths because every range at
   the seam is UTF-16 (`TI-H`); gpui's `TextRun.len` is UTF-8 bytes for the
   same reason in Rust. Paint-only attributes (colours, underline,
   strikethrough, background, link) never cross the seam: they are MetalUI's
   and are applied to the layout's run indices.
2. **Three new `TextSystem` requirements, defaultless** (a conformer that
   forgets one must not compile, the `PlatformWindow` rule):
   - `measure(_ text: StyledText, wrappingAt: Double?, options:
     TextLayoutOptions) -> StyledTextMeasurement` — the widest kept line, the
     total height, and each kept line's box (`TextLineBox`: UTF-16 range, top,
     height, baseline, width, visible extent);
   - `layOut(_ text: StyledText, wrappingAt: Double?, options:
     TextLayoutOptions, origin: (x: Double, y: Double), scaleFactor: Float) ->
     StyledTextLayout` — the measurement's lines, every placed glyph with the
     index of the run it belongs to (`StyledGlyph`), and every run segment
     (`TextRunSegment`: run, line, x extent in points, the run's baseline);
   - `decorationMetrics(_ font: FontKey) -> TextDecorationMetrics` —
     underline position and thickness, and the strikethrough position
     (`RT-J`).
   Both systems and the one test fake (`CountingTextSystem`,
   `MenuPickerTests.swift`) implement all three; the migration note names
   them for an external conformer.
3. **The plain path does not move.** A `Text` whose runs collapse to one run
   with no run-level attribute beyond what plain `Text` already had (font,
   weight, italic, colour) calls exactly the calls it calls today — same
   arguments, same cache keys, same order. Only a `Text` with two or more
   distinct runs, or any of underline, strikethrough, background, kerning,
   tracking, baseline offset or link, takes the styled calls. **A one-run
   `StyledText` measures and places exactly what the plain calls do, on both
   systems** (spec tests 1.1, 1.2) — the rule that lets a later branch route
   every `Text` through the styled path without moving a pixel.
4. **Caret offsets and line ranges stay plain** (`TI-E`, `TI-H`): they serve
   text input, which stays plain (`RT-A`).
5. **Caches**: `ShapingCache` and `PortableTextSystem` key styled work by the
   `StyledText` value (it is `Hashable`), in their own dictionaries, under the
   same sweep; a warm frame of a styled `Text` shapes nothing (spec test 2.9).

**Alternatives.** Defaults that degrade (a styled measure falling back to
the concatenated plain string — silently wrong on any external conformer);
passing runs through the existing methods with an optional parameter (every
plain call site changes, and a missing argument compiles).

**Cost if wrong.** An external `TextSystem` conformer fails to compile until it
adds three methods — the intended, named cost.

---

## RT-G — The metrics of a styled line

**Ruling.** For each laid-out line, over the runs that have at least one UTF-16
unit on it (an empty run contributes nothing — `C17`, `C17b`), using each run's
**requested** face (fallback faces never enlarge a line, as on the plain path):

1. `ascent = max(runAscent + max(0, baselineOffset))`,
   `descent = max(runDescent + max(0, −baselineOffset))`,
   `leading = max(runLeading)`; the line's height is
   `ceil(ascent + descent + leading)` — divergence 86's rule, so a one-run
   line is exactly today's `lineHeight`. A baseline offset only grows the line
   (`C7`, `C7d`: +5 and −5 both make a 16-point line 21; CoreText's own
   `CTLineGetTypographicBounds` instead shrinks the descent, measured by the
   design session, which is why MetalUI computes line boxes itself rather than
   asking CoreText for them). Mixed sizes take the largest (`C5`: 10 pt + 30 pt
   is the 30-point line; `C6`: a 10-point line then a 30-point line stack to
   their sum, 13 + 35 = 48 in SwiftUI).
2. The baseline sits `ascent` below the line's top; the next line's top is
   this line's top plus its height. The measurement's first baseline is
   `round(first line's ascent)` and its last `top(last) + round(last line's
   ascent)` — the plain rule when every line is alike (`C5`, `C6`, `C7`
   baselines agree: 29; 10 and 42; 18).
3. **A finite height caps lines cumulatively**: as many leading lines as fit
   their summed heights, at least one (`C16`: two 13-point lines in 30, not
   ⌊30 / 35⌋; `C16b`, the separating arm added by `RT-O` item 3: a 10-point
   then a 30-point line keep one line in 47 and two in 48). The line limit still caps first. `reservesSpace` pads with the
   **first run's** line height (`C18`: `B(30 pt) + a(10 pt)` reserves 3 × 35,
   `a + B` reserves 3 × 12).
4. Every line's alignment offset is computed from its own width, as today.

**Cost if wrong.** A mixed line one point off SwiftUI's TextKit height — the
existing divergence 86, unchanged in kind.

---

## RT-H — Shaping and breaking across runs

**Ruling.**

1. **Breaking is done once over the whole string**: a run boundary is never a
   break opportunity (`C4`, `C4c`: `Text("foo") + Text("bar")` at a width
   narrower than "foobar" draws exactly what `Text("foobar")` draws), and
   breaks between runs at spaces fall where CoreText's typesetter puts them
   (`C4d`: 5 + 5 + 4 units, three lines). Portable: libunibreak over the
   whole string as today (`LB-A`); CoreText: one `CTTypesetter` over the whole
   attributed string.
2. **Portable shaping stays one function** (`FB-A`): `shapeCascading` takes a
   per-UTF-16-unit run index and a font per run, chooses the covering face
   from **that run's** font and its fallbacks, and splits a shaping run at a
   style change as it already splits at a face, bidi level or script change
   (`BD-B`, `BD-C`). The existing single-font signature becomes a call with one
   run. No other shaping entry point is added.
3. **Kerning** adds its value after every glyph of the run, including the
   last, a ligature counting once (`C8`, `C8ct`: +12 for three glyphs; `F1`;
   CoreText `kCTKernAttributeName`, measured on Helvetica "office": 5 glyphs,
   +20; a kerning of 0 is no extra space and keeps the font's pair kerning —
   CoreText's kern attribute is omitted at 0, `RT-O` item 7). **Tracking** adds after every glyph **and disables ligatures**
   (CoreText: 6 glyphs; `C8e`: SwiftUI ≡ CoreText for both). Portable:
   kerning is added to the run's glyph advances after HarfBuzz; tracking also
   shapes the run with the `liga`, `clig`, `dlig` and `hlig` features off
   (`MetalUIHarfBuzz` gains a features argument). Lane 1's oracle measures
   this on Noto Sans before it is relied on; a disagreement is a ruling
   amendment, not a silent approximation.
4. **Baseline offset** moves the run's glyphs up by its value (and its
   underline/strikethrough with them, `C9bo`), and grows the line (`RT-G`).
5. **The CoreText oracle decides agreement**: a corpus of styled strings in
   the three test faces (Noto Sans, Noto Sans Arabic, Source Sans 3) — mixed
   sizes, kerning, tracking, baseline offsets, wraps, bidi — placed by both
   systems from the same font files must place the same glyphs (spec test
   1.10), as `LineEmissionOracleTests` does for plain text.

---

## RT-I — Truncating a styled line

**Ruling.** The ellipsis takes **the style of the first character the
truncation removes** — its font, colour and decorations: tail truncation cut
inside the green run gives a green ellipsis (`C13`), cut inside the red run a
red one (`C13b`), head truncation (which removes from the start) a red one
(`C13d`), and a 30-point removed run a 30-point ellipsis that makes the line
35 tall (`C19`). The truncated line's metrics include the ellipsis's run.
CoreText: the token line passed to `CTLineCreateTruncatedLine` is attributed
with that run's attributes; portable: `Truncation.swift` shapes the token in
that run's font. Middle truncation follows the same rule (unprobed; it is
the rule that explains all three probed arms).

---

## RT-J — Underline, strikethrough and background: rects, by the font's metrics

**Ruling.**

1. **Drawn as ordinary filled rects through `Frame.fill`** — no new primitive,
   no shader change on either renderer (`TE-AD` is satisfied by construction).
   A styled `Text`'s backgrounds, glyphs and lines are emitted **inside one
   `beginLeafGroup`/`endLeafGroup` bracket**, so a shadow treats the whole
   `Text` as one leaf (`GX-J`), and they sit inside the text's
   `paintDecoration` content closure (clip, opacity, border order: `OM-V`).
   Order: backgrounds, then glyphs, then underlines and strikethroughs (ruled;
   SwiftUI's order is not separable in the probe's renders).
2. **Geometry from the face's metrics** (`decorationMetrics`): underline
   centred at `baseline − underlinePosition` (the position is negative below
   the baseline) with the face's `underlineThickness`; strikethrough centred
   at `baseline − xHeight / 2` with the underline thickness (`C9s`, `C9ms`: the
   13-point and 30-point strikes sit on their own x-heights). CoreText:
   `CTFontGetUnderlinePosition`, `CTFontGetUnderlineThickness`,
   `CTFontGetXHeight`; FreeType: the face's `underline_position`/
   `underline_thickness` (the `post` table) and OS/2 `sxHeight` (the `x`
   glyph's height when the table has none), scaled as `PT-B`'s metrics are.
   The oracle compares the two systems' numbers for the three test faces.
   **TextKit snaps the line to device pixels** (`C9`: rows 28–29 at 13 pt,
   scale 2 — a one-point band one to two points below the baseline);
   MetalUI draws the unsnapped band. **Divergence 152.**
3. **Extent**: a segment's x extent (kerning included, `C9k`) **clipped to its
   line's visible extent** — leading and trailing whitespace of a line is not
   underlined or struck (`C9w`), interior whitespace is, including a run of
   only spaces (`F4`, `F4b`, `F4c`); each line separately (`C9l`, `F4d`).
3a. **Merging**: on one line, adjacent underlined segments **with the same
   resolved colour** join into one rect at the lowest position and the
   greatest thickness of the faces involved (`C9m`: a 10-point and a 30-point
   run underline as one 30-point line; `C9b`: two equal segments ≡ one); with
   different colours each keeps its own geometry (`F3`). Strikethroughs never
   merge (`F2`).
4. **Colour**: the given colour, else the run's resolved foreground (`C10`,
   `C10b`, `C10c`).
5. **Background**: the run's segment x extent, whitespace included (`F4e`),
   by the **line's** full box height (`C11bg`: 32 device rows for a 16-point
   line; `C11bg2`: a 30-point run's background beside a 10-point run fills
   the 35-point line).

---

## RT-K — Links: styled, inert

**Ruling.** A run with a link (Markdown, `AttributedString.link`) draws in the
`.accent` token **unless the run or its `Text` sets its own colour** (`M6`,
`C11ln`: ≡ `accentColor`, no underline; `C11lnc`: a red link is red). The
environment's `foregroundStyle` does not reach a link (`C11lne`). SwiftUI
recolours links with `.tint` (`C11lnt`); MetalUI has no `tint`, so a link is
always the theme's `.accent` (`Color.accentColor`, divergence 116). **A link
does nothing**: no click, no keyboard activation, no `openURL`, no
accessibility link element — the run is published as part of the text's
string. **Divergence 150.** The URL is stored on the run (`TextRunRequest.link`)
so a later branch can add the hit region without changing the model.

---

## RT-L — Accessibility, animation and identity

**Ruling.**

1. **Accessibility**: a styled `Text` publishes its concatenated, rendered
   string (Markdown markers removed, interpolations inserted) exactly where a
   plain `Text` publishes its string (`AB-F`; `Text.prepaint`'s
   `accessibleText:`). No new `AccessibilityNode` field, no bridge row. An
   empty concatenation is no text (`E0`'s rule).
2. **Animation**: run colours (foreground, underline, strikethrough,
   background) **snap**, as a plain `Text`'s glyph colour always has (the
   note at `Text.paint`: animating text colour is spec §8's named hole). No
   new animated field, no `AnimationStore` entry. Whether SwiftUI animates a
   text colour is not measured (an `ImageRenderer` cannot sample mid-flight);
   no divergence is claimed.
3. **Identity and layout**: a styled `Text` is one leaf, one identity slot,
   one hitbox — exactly a plain `Text`. `theSevenRetentionSlotsAreMutuallyDistinct`,
   `MC-A`/`MC-C`/`MC-P` numbering, `.id()` outermost, hit testing, focus,
   `List` windowing, `Deferred` and text input are untouched.

---

## RT-M — Plain text does not move

**Ruling.**

1. **Pixels**: all fourteen offscreen images 0 px against `70ed000`
   (`docs/probes/demo-pixels/compare.sh`); `DemoFrameDeterminismTests`'
   `Expected.swift` unedited. **Work**: `ShapingCache.misses`, the portable
   measurement cache and `LayoutTree.lastNativeLayoutWork` unchanged for the
   demo (spec test 2.10).
2. **The demo's literals parse to themselves**: no format part of a `Text`
   literal under `Sources/` contains `*`, `_`, `~`, `` ` ``, `[`, `\`, `&`,
   `<`, `http`, `www.` or `@` (census, spec §0) — so moving them to
   `LocalizedStringKey` changes no glyph.
3. **A test literal that changes because it now parses** is converted to
   `Text(verbatim:)` with a one-line comment naming `RT-B` — never an edited
   expectation. Lane 3 lists every such conversion in the record.

---

## RT-N — Lanes, order, demo and human checks

**Ruling.** Three lanes, run one at a time in order 1 → 2 → 3, on disjoint
source files (spec §3): **lane 1** the seam and both text systems; **lane 2**
the `Text` element (run model, modifiers, `+`, styled layout and paint,
decorations, links, accessibility string; the demo section moved to lane 3,
`RT-O` item 10); **lane 3** the
front ends (`LocalizedStringKey`, the Markdown parser, the attribute scope)
and the shared registries (divergences 150–156, human checks group "RT" —
provisional, `RT-O` item 2 —
migration, API overview). The shared inventory map takes each lane's own rows
in its own commits (append-only). The demo is a new env-gated tree,
`METALUI_RICH_TEXT_DEMO=1` (`RichTextDemo.swift`), built in its own
`@inline(never)` function in `everyProductionTreeBuildsOnAOneMegabyteThread`;
it is not one of the fourteen images. Human checks: group **"RT"** (spec §7,
letter settled at the merge, `RT-O` item 2) —
an agent cannot run them.

---

## RT-O — Critic pass: sixteen corrections to the design

The critic pass attacked the committed design (`c89c94b`): every claim against
a probe run, every file against the parallel branches, every test against its
mutation. Evidence it added: `swiftui-rich-text.swift` re-run (every row byte
for byte except `P0a`'s self-compare wobble) plus arm `C16b`;
[`../probes/swiftui-text-interpolation.swift`](../probes/swiftui-text-interpolation.swift)
(new, `I0`–`I4`); [`../probes/swiftui-kerning-zero.swift`](../probes/swiftui-kerning-zero.swift)
(new, `K1`, `K2`); `foundation-markdown-inline.swift` re-run on macOS (every
`M`/`N` row identical). Each item amends the spec in the same commit.

**Ruling.**

1. **`Handlers.swift` is not this branch's file.** `feat/input-apis` (record
   §81, its lane 3) edits it and adds an eighteenth member (`pointer`, `CI-Q`).
   A hand-written `Handlers.isDefault` there would conflict and, after the
   merge, miss the new member silently (a `.pointerStyle` operand would
   concatenate). Instead the `+`/interpolation operand check is an internal
   function in `TextRuns.swift` that compares a `Handlers` against `Handlers()`
   **child by child through `Mirror`**: an optional by nil-ness, a collection
   or dictionary by emptiness, an `Equatable` value by `==` (opened
   existential); any other child kind is unrecognised. Test 2.20 becomes:
   `try #require` that every child of `Handlers()` is recognised and that the
   child count is **17** (the merge with §81 moves it to 18 and adds an arm),
   plus one arm per member as before. The `MC-B`/`HandlerShape`/
   `HandlerFingerprint` places do not change.
2. **Human checks take a provisional group letter, "RT"**, settled at the
   merge: `feat/input-apis` also writes a group Y (its `Y12`), and
   `feat/variable-height-list` already took this route ("provisionally VL").
3. **`RT-G` item 3 had no separating arm.** `C16` (two 13-point lines kept in
   30) is answered equally by cumulative capping and by `⌊h / first line
   height⌋`. Arm `C16b` separates them: a 10-point line then a 30-point line
   keep **one** line under 47 (13 tall) and **two** under 48 (48 tall);
   `⌊h / 13⌋` would keep two under 47, `⌊h / 35⌋` one under 48. Cumulative
   capping stands, now measured; test 2.14 asserts `C16b`'s two arms.
4. **Interpolating an `AttributedString` keeps its runs** (`I3`: ≡ the
   concatenation, 607 px from plain): `LocalizedStringKey.StringInterpolation`
   gains `appendInterpolation(_ attributedString: AttributedString)`, which
   stores the converted runs (`RT-D` item 4's conversion). Without it the
   generic overload would print the attributed string's debug description —
   a silent wrong. Test 3.7b.
5. **Interpolating an `Image` is unavailable**, not described: SwiftUI draws
   the image inline (`I4`); MetalUI defers `Text(Image)` (`RT-A`), so
   `appendInterpolation(_ image: Image)` is `@available(*, unavailable,
   message:)` naming the absence — a compile error, never the struct's
   description. Guard arm in 3.10.
6. **Interpolating any other value is its description, without a warning.**
   SwiftUI renders `String(describing:)` too (`I1`, `I2`) but **deprecates**
   that overload (two warnings: "Localized string interpolation produces an
   unlocalized, debug description for this type of value…"). MetalUI's
   generic `appendInterpolation<T>` is not deprecated: today's
   `Text("… \(x)")` compiles for every `x` with no warning (the demo
   interpolates enums and models), and the 0-warning gate would force edits
   for a message about localization MetalUI does not have. **Divergence 156**,
   pinned by a guard arm in 3.10 (`Text("v \(Plain())")` compiles with no
   `warning:`).
7. **`kerning(0)` is no extra space, not "kerning off"** (`K1`: SwiftUI's
   `kerning(0)` and `tracking(0)` ≡ plain; `K2`: CoreText's
   `kCTKernAttributeName` of **0 turns the font's pair kerning off**, 11.06
   points wider on Helvetica "AVAVAV", while 4 keeps it, plain + 24 on both).
   Lane 1's CoreText styled path **omits the attribute when a run's kerning
   is 0** (and tracking likewise). Test 1.1's corpus gains a pair-kerned
   string in Noto Sans (`try #require` that its plain width is less than the
   sum of its glyph advances) and 2.21 draws one; mutation: always set the
   attribute.
8. **`underline`/`strikethrough` take SwiftUI's `pattern:` parameter**:
   `underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern =
   .solid, color: Color? = nil)` (the probe compiles `underline(pattern:
   .dash)`, `C10d`). With only `.solid` declared, SwiftUI's full spelling
   compiles and `pattern: .dash` still does not. Guard 2.24 gains the
   compiling arm.
9. **`+` in tests goes through a deprecated protocol witness**, not a bare
   deprecated helper: calling a deprecated helper from a `@Test` warns
   (`swift-deprecated-witness-silence.sh`'s `direct` arm); the house pattern
   is a deprecated witness called through a generic constraint (`LR-CV`).
   Non-test code never uses `+`.
10. **The demo moves to lane 3.** It needs Markdown and interpolation (lane 3),
    and a `+` in the demo would warn (item 9). Lane 3 also adds the switch to
    `Backends/SDL/Sources/MetalUISDLDemo/main.swift` (human check RT4 needs
    it), so lane 3's Linux-image run covers a `Backends/SDL` change.
11. **Lane 1 runs the demo-pixel compare** (fourteen images, 0 px): it changes
    the plain path's internals (`shapeCascading`'s signature, HarfBuzz's,
    `ShapingCache`). Test 2.10 moves to lane 1 as **1.19**, its literals
    recorded at `70ed000`'s code before lane 1's first source change, so a
    lane-1 regression in plain work cannot be baked into the pin.
12. **Code spans on the portable system** resolve the system face's
    `.monospaced` design through `TE-B`'s existing rule: the family an app
    registered with `PortableFontResolver.register(design:family:)`, else the
    default face. No new divergence (it is `TE-B`'s); test 3.13 asserts the
    descriptor's design, the migration note and human check RT4 say so.
13. **The run background and decoration fills are named** in
    `everyBackgroundPaintingSiteAnimatesItsColour`'s doc comment among the
    deliberately unanimated fills (`RT-L` item 2), so the guard's "one case
    per site that fills a background" stays true (lane 2, doc comment only).
14. **A literal with no Markdown trigger never runs the parser**: the format's
    segments are scanned for `*`, `_`, `~`, a backtick, `[`, `<`, `&`, `\`,
    `@`, `http` and `www.` (the census's list, spec §0); none →
    `.plain`, no run built. Counted (performance tests count work): test
    3.16 `aLiteralWithNoMarkupRunsNoParser` over the main demo tree's build
    (an internal parse counter stays 0); mutation: always parse.
15. **Test 2.3's spy `TextSystem` forwards every requirement to a real
    system** (an honest fake: it records, it does not answer).
16. **`AttributedTextTests` (Linux too) write every key by its dynamic-member
    spelling**, so the Linux image compiles the per-key subscripts (guard
    3.12 is macOS-only, `MetalUITests`).

Also corrected: `RT-E` item 1's warning count (146 with the arms added since;
138 when first recorded).

**Rejected.** (a) Deprecating the generic interpolation to match SwiftUI
(item 6's cost). (b) Splitting lane 1 by text system: the oracle (1.10)
compares the two systems, so one lane must own both; lane 1 keeps them and
lane 2 sheds the demo instead. (c) Re-running the SwiftUI probe interpreted:
the compiled runs reproduce every verdict; the interpreted form adds only the
known `P0a` wobble.

---

## RT-P — Lane 1: what the two text systems measured, and the amendments

Lane 1 (the seam and both text systems) built `RT-F`…`RT-J` and measured the
places where the design described CoreText from outside. Evidence:
[`../probes/coretext-styled-spacing.swift`](../probes/coretext-styled-spacing.swift)
(**new**; `P0`, `S1`–`S5`, compiled twice byte-identical), the CoreText oracle
(spec test 1.10, its corpus gaining a case for items 3 and 4) and new spec
test **1.20** `spacingIsOncePerGraphemeAndKeepsPairKerningAcrossRuns`.

**Ruling.**

1. **The ellipsis's run is found in two attempts** (`RT-I`). Which characters
   a truncation removes depends on the token's width, which depends on the
   run whose face it is drawn in — the very run being decided. Both systems
   first build the truncated line with the token in the run of the
   paragraph's first unit; when the first removed unit belongs to another run,
   they build it again with the token in that run and keep the second answer.
   There is no third attempt: if the second token's width moves the cut into
   yet another run, the token keeps the second run's style (unmeasured
   against SwiftUI; every arm of test 1.9 and every truncated case of the
   oracle corpus settles on the second). CoreText marks the token's glyphs with a private
   attribute so their run is the token's, never a character's;
   `Truncation.swift` does the same steps on the portable system.
2. **A tracked line's last glyph's tracking is trailing whitespace** (`S4`:
   `CTLineGetTrailingWhitespaceWidth` of "ab" tracked 2 is 2; kerned 2 it is
   0). So `TextLineBox.visibleMaxX` leaves the last visible glyph's tracking
   out and keeps its kerning, and the portable line breaker subtracts it from
   the line's visible width (alignment's `TE-J` input) — 0 on the plain path.
3. **A style boundary that keeps the face does not split a shaping run**
   (`S3`: `A` | `V` tracked 1 is "AV"'s 15.587 + 1 = 16.587, never "A" + "V"'s
   16.107 + 1; likewise a kerning or offset change). `RT-H` item 2's "splits a
   shaping run at a style change" is amended: the portable system splits at a
   **face**, bidi level or script change as before, and turns the optional
   ligatures off for tracked units by **feature ranges** inside the one
   HarfBuzz call (`ShapingFeature` gains a UTF-16 `range`; `[]` is still
   exactly `SH-E`'s call). Measured equal to CoreText on "of" | "fice"
   tracked, "offi" tracked | "ce" and "o" | "ffi" tracked | "ce".
4. **Kerning and tracking are added once per grapheme, on its last glyph**
   (`S1`: "e" + U+0301 + U+0302 + "x", three glyphs in two graphemes, widens
   by 2 × the value, on the mark and the x; `S2`: Arabic "ب", two glyphs, by
   1×). `RT-H` item 3's "after every glyph, a ligature counting once" is
   amended to this: the two agree wherever a grapheme is one glyph or a
   ligature, and differ on combining marks and on Arabic letters drawn in more
   than one glyph. The portable system adds the value to the last glyph of
   each grapheme in HarfBuzz's (visual) order, the grapheme's first unit's run
   deciding the value. Test 1.20's mark and Arabic arms; test 1.7's
   `plain + 4 × glyph count` is unchanged (its strings are one glyph per
   grapheme or ligature).
5. **CoreText fills kerned or tracked joined Arabic with kashidas; the
   portable system does not** (`S2b`: kern 1 on "بالعالم" inserts four
   tatweel glyphs, 111, carrying the space between joined letters; the width
   is plain + 7 either way). Every other glyph lands on the same pixel on both
   systems and the widths, line boxes and segments agree (test 1.20 pins both
   halves: CoreText draws tatweels, the portable system none, and the rest is
   equal). Inserting kashidas is justification machinery HarfBuzz does not
   provide; the portable system leaves the space as a gap between joined
   letters. This is a SwiftUI difference on Linux and Windows only (SwiftUI
   draws through CoreText; its kashidas were not probed separately): **lane 3
   writes it as divergence 157** from this branch's range, with test 1.20 as
   its pin.
6. **Test 1.13's fixture was changed after its red commit.** `RT-F` item 2's
   "one segment per visual piece" is a maximal visually contiguous span of one
   run on one line, so a single Arabic run whose digits UAX #9 reorders inside
   it is still **one** piece (its letters and digits are adjacent on screen) —
   the red fixture's `count > 3` could never be met by a correct
   implementation. The fixture now splits the Arabic text into two runs at the
   digits (`"مرحبا 12"` | `"3 بالعالم"`), so each run draws in two visual
   pieces: runs `[0, 2, 1, 2, 1, 3]` in visual order on both systems, where a
   logical-order emission gives `[0, 1, 2, 3]`.

**Cost if wrong.** Item 4: a combining-mark or Arabic string kerned on one
system wider than on the other by the value per extra glyph — the oracle and
test 1.20 would show it. Item 5: Arabic kerning looks different on Linux and
Windows (gaps instead of stretched joins), named, never silent.

---

## RT-Q — Lane 1: the instruments its mutations corrected, and a plain-path finding

Lane 1 ran every §4.1 mutation (each on a committed tree, restored from a
copy, the full unfiltered native suite, `git status --short` clean after). Two
§4.1 mutations reddened nothing on the first run; each was a broken
instrument, fixed here, and one fixture exposed a difference outside rich
text.

**Ruling.**

1. **Test 1.6 gains a single-run arm** (`C7d`: a line holding only the
   shifted run is `lineHeight + 5`). The mixed line `"a"` + `"b"` raised 5
   keeps run 0's unshifted descent, so `descent − offset` (CoreText's
   shrinking rule, the mutation) left its height `lineHeight + 5` and
   reddened nothing; with the single-run arm it reddens 1.6.
2. **Spec 1.4's mutation is reached from 1.10, not 1.4.** The portable line
   breaker shapes the paragraph once and re-shapes only from a line start
   inside a cluster or one splitting lam-alef (`LB-E`, `BD-C`); test 1.4's
   lines start at clusters, so "re-shape from a line start in run 0's face"
   never runs there. The oracle (1.10) gains a narrow arm — `"a "` (Noto
   Sans) + `"office"` (Source Sans 3, 26 pt) at width 8, so a line starts
   inside the second run's ligature — and the mutation reddens 1.10. Test
   1.4 keeps its assertion (CoreText's break positions between runs).
3. **A plain-path difference, deferred** (not rich text; the plain path must
   not move on this branch, `RT-M`): the portable system centres (or
   trails) a line that starts inside a cluster by the whole cluster's
   paragraph-shaped advance instead of the line's re-shaped one —
   `placeGlyphs("office")`, Source Sans 3 26, width 8, `.center`: the second
   line's glyph at pixel −4 where CoreText draws it at 0. The narrow arm uses
   leading alignment and a tail limit only, and says why. Owner: a portable
   text follow-up (the `trailingWhitespace` of a re-shaped line in
   `LineBreaking.swift`), with this case as its red test.
4. **Mutation spellings, recorded**: M1.9 (the ellipsis from the last kept
   character) and M1.6b (the glyph sign) were applied to the portable
   spellings, M1.14 (the styled key by string) to `ShapingCache`'s; M1.19's
   first spelling (options dropped from `==` only) broke `Hashable` and
   trapped the run — the recorded spelling drops them from `==` and `hash`.
   The reddened tests are listed in record §83.

---

## RT-R — Lane 2: the `Text` element — what it measured, and the amendments

Lane 2 (the run model, the `Text`/`ProposalText` initialisers and modifiers,
`+`, styled layout and paint, links, accessibility) built `RT-E`, `RT-F` item
3, `RT-G` items 2–3, `RT-J`, `RT-K` and `RT-L` on lane 1's seam, red first
(`81032fc`, stubs), then the implementation (`54c5453`). Evidence: spec tests
2.1–2.9, 2.11–2.26 and this ruling's own arm, and every §4.2 mutation run on a
committed tree (listed in record §83 by name).

**Ruling.**

1. **`Text` builds its `StyledText` with a package initialiser that keeps
   equal neighbours** (`StyledText(keepingNeighbours:runs:)`, beside lane 1's
   public one, which still merges, test 1.16 unchanged). Paint attributes are
   applied by run index (`RT-F` item 1), and the public initialiser merges any
   two neighbours whose *layout* styles agree — so `Text("ab").foregroundColor(.red)
   + Text("cd").foregroundColor(.blue)` in one face would reach the seam as one
   run and draw in one colour (test 2.4 under mutation M2.R1). The spec's
   "resolved runs whose `TextRunStyle` and paint attributes are equal merge
   before the seam" stands — `resolveRichText` joins exactly those — and
   neighbours that differ only in paint stay two runs. Both systems lay such a
   text out exactly as the merged one (a style boundary that keeps the face
   splits no shaping run, `RT-P` item 3): pinned by
   `neighboursThatDifferOnlyInPaintLayOutAsOneRun` (CoreText and portable,
   scales 1 and 2, a ligature `of|fice` and a pair `A|V` split across
   boundaries — same glyphs, same lines, one segment per run).
2. **Test 2.19's style arm is `.margin`, not `.padding`.** A legacy element's
   `.padding` returns a `ModifiedElement`, so `Text("a").padding(2) + Text("b")`
   does not compile — SwiftUI's own answer for every view modifier. The trap
   arms are `.margin` (style), `.background` (decoration), `.onClick`
   (handlers) and `.id` (element id), plus a plain control that exits
   normally; each names its field and divergence 155.
3. **Test 2.9's second arm: paint lays out at the width layout answered.**
   "`ShapingCache.misses` unmoved on the warm frame" alone cannot see paint
   laying out at the rounded box width (spec mutation M2.9): the rounded width
   is asked again on the warm frame and hits. The arm compares every styled
   `layOut` width of the first frame with the text's own answer (its widest
   line, `try #require`d fractional so rounding moves it). Its first spelling
   (`layOut` widths ⊆ `measure` widths, `54c5453`) was a broken instrument —
   paint's own `styledTextLines` measures at the width it then lays out at —
   found by M2.9, whose first run left 2.9 green; re-spelled in `e6d1b28`,
   M2.9 reddens it. M2.9's first spelling (the box width unclamped) also
   trapped the run at `StyledShaper.shape`'s positive-width precondition on
   an empty text; the recorded spelling clamps to `smallestWrapWidth` as the
   real path does.
4. **The rich `Text`-level fields are boxed** (`TextRichBox`, one reference,
   `nil` while unset). Stored inline they grew `Text` by about 120 bytes, and
   `everyProductionTreeBuildsOnAOneMegabyteThread` overflowed (SIGBUS) — every
   container holds its content by value. Boxed, a plain `Text` grows by one
   word (the content enum and the box) and the 1 MB build passes.
5. **Requests join at `+`** (`TextContent.joined`): neighbouring segments whose
   fields all agree are one segment, so `Text("a") + Text("b")` is the one run
   `"ab"` and takes the plain calls (`RT-F` item 3; 2.3's fourth plain arm).
   Lane 3's interpolation appends through the same function.
6. **`Text.bold()` is `fontWeight(.bold)` — a SwiftUI difference to write as
   divergence 158.** RT-E item 3 offered it without meeting `TE-B` item 4,
   which had withheld it on a probe: SwiftUI's `Text.bold()` draws **semibold**
   on the default font (`swiftui-text-semantics.swift` X1), heavy on
   `.headline` (F2e) and nothing on `.light` (X1b) — no one rule. MetalUI's is
   the bold weight over whichever font resolves (`Font.bold()`'s, X1c), the
   spelling SwiftUI users write, and `(light + plain).bold()` keeps the light
   run light (`C2b`). Guard G3.2 (`textBoldIsNotOffered`) is re-spelled
   `textBoldIsOfferedSinceRichText`; pin: 2.1's `C2b` arm (the bold run is
   `.bold`). Lane 3 writes divergence 158 from this branch's range.
7. **Route mutations and their instruments.** Spec 1.19's lane-2 re-run
   (every `Text` through the styled path, M2.10) does **not** redden 1.19: the
   demo's one-run styled texts ask the styled cache one question each where
   the plain path asked the plain cache one, so misses and lookups are equal.
   It reddens `aPlainTextTakesThePlainCalls` (2.3),
   `aFrameWithoutATextSystemUsesCoreTextOverItsOwnCache` and
   `aPortableFrameNeverShapesThroughCoreText` — the route is pinned there, and
   1.19 stays the pin of plain *work*. 2.21's fixture is two centred lines,
   the first shorter, so the doubled alignment offset (M2.21a) has an offset
   to double. 2.12's reader takes the glyphs and the underline rect.
8. **Not run: M2.23** (route a run colour through `animatedColor`). The helper
   takes an element id and an `inout PaintPass`; the styled paint resolves run
   colours inside `drawStyledText`, which has neither, so the mutation needs a
   new code path rather than an edit. 2.23 stays a pin of the snap (`RT-L`
   item 2), green on arrival.
9. **2.14–2.16 measure through `richTextMeasurement(resolveRichText(…))`**,
   the two functions `Text.requestLayout` calls, at a chosen proposal; a laid-
   out frame does not expose a leaf's answer to a height proposal.

10. **Mutations, recorded** (each on a committed tree, restored from a copy,
    the full unfiltered native suite, `git status --short` clean after; the
    reddened tests by name are in record §83): M2.1–M2.8, M2.9 (re-spelled),
    M2.10–M2.19, M2.20a–c, M2.21a–b, M2.22, M2.R1 and guard mutations
    MG2.24a–c and MG2.25 each redden their test; MG3b (delete `Text.bold()`)
    reddens the build first — the lane's own tests call `bold()`.

**Cost if wrong.** Item 1: a third system that splits a shaping run at every
run boundary would shape `of|fice` as two runs — the arm reddens on it. Item
6: a port that relied on SwiftUI's semibold `bold()` draws one weight heavier.
