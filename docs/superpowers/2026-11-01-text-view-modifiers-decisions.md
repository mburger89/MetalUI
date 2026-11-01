# Text dash patterns and view-level text modifiers (round 3 item R3-10 part 1) - decisions

Prefix `TM-`. **Next unused: `TM-I`.** Record: `../record/186-text-view-modifiers.md`. Branch `feat/text-view-modifiers` from master `b83efde2`.
Divergence labels 995-1004 reserved: **none taken** (`TM-H` explains the one candidate and why it is carried). Probe:
`docs/probes/text-line-patterns.swift` (recorded in its header; arms `P`, `T`, `PL`, `PS`, `PR`, `V`, `W`, `B`). Closes the two "Not offered" rows of
`docs/divergences.md` (`RT-A`, `RT-E` item 3): `Text.LineStyle` patterns beyond `.solid`, and view-level `bold`/`underline`/`strikethrough`/
`kerning`/`tracking`/`baselineOffset`/`monospaced`. Code: `TextLinePattern.swift` (new), `TextModifiers.swift`, `TextRuns.swift`,
`RichTextPaint.swift`, `TextStyleResolution.swift`, `EnvironmentValues.swift`, `Text.swift`, `ProposalText.swift`, `TextMeasurer.swift`. Tests:
`TextViewModifierTests.swift` (CrossPlatform), `TextViewModifierSpyTests.swift`, `RetainedTextViewModifierTests.swift`, `RichTextCompileGuards.swift`
(`TM-1` guard), the two fingerprint tables.

## TM-A: the view-level layer

1. `View.underline(_:pattern:color:)`, `strikethrough(_:pattern:color:)`, `kerning(_:)`, `tracking(_:)`, `baselineOffset(_:)`, `monospaced(_:)` and
   `bold(_:)` exist on every `ElementGroup` as **environment writes** (`EnvironmentScope`, layout- and identity-transparent, the nearest writer
   wins), in SwiftUI's spelling (checked against the macOS SDK's `SwiftUICore.swiftinterface`: `View.bold(_ isActive: Bool = true)`,
   `kerning/tracking/baselineOffset(_ : CGFloat)`, `monospaced(_ isActive: Bool = true)`, `underline/strikethrough(_ isActive: Bool = true, pattern:
   Text.LineStyle.Pattern = .solid, color: Color? = nil)`; a `Double` where SwiftUI says `CGFloat`, as `Text`'s already are). `italic(_:)` was already
   a view modifier (`TE-B`). `monospacedDigit`, `fontWidth` and `fontDesign` are not offered (carried).
2. **Precedence is a chain, inner to outer: the run's own field, the `Text`'s own field, the environment's** (`run.f ?? rich.f ?? view.f`), measured
   (probe `W`): a `Text`'s `kerning(2)` inside `.kerning(5)` draws 2; an inner `.kerning(0)` resets an outer 5; a `Text`'s own underline of any
   pattern or colour **replaces the environment's whole** (a solid black own inside a dashed red view is solid black: no field-wise merge);
   `underline(false)` on the `Text` or on a nearer view is an explicit "none" (`Text.LineStyle.none`) that an outer `underline()` does not reach.
3. **Storage**: `EnvironmentValues.textRichBox` (one reference to a `TextRichFields`, `nil` while none is written - the value is copied through every
   scope, `RT-R` item 4) behind six internal computed keys (`textUnderline`, `textStrikethrough`, `textKerning`, `textTracking`,
   `textBaselineOffset`, `textMonospaced`), so each write changes exactly one field and an outer writer's other fields survive. Internal, as
   SwiftUI has no public keys. A stored property of a public type: `swift package clean`.
4. **Reach**: every text that resolves its runs through `resolveRichText` (`Text`, `ProposalText`, a `Button`'s label, `TextMeasurer.resolve`,
   `drawText`), so layout, paint and the measurer agree. A `Button` label under `.kerning(5)` is wider, as in SwiftUI (probe `B`).

## TM-B: the pattern API

`Text.LineStyle.Pattern` has SwiftUI's five statics (`solid`, `dot`, `dash`, `dashDot`, `dashDotDot`) over an internal `Kind`; `Text.LineStyle(pattern:
color:)`, `.single` and the `underline`/`strikethrough(_:pattern:color:)` on `Text` and `ProposalText` were already in SwiftUI's shape. `Pattern` is
`Hashable` (SwiftUI's is only `Sendable`; additive). `AttributeScopes.MetalUIAttributes`' `underlineStyle`/`strikethroughStyle` carry a pattern with
no change.

## TM-C: segment and gap lengths (probe `P`, `T`)

1. A pattern is a cycle of whole multiples of the line's **unit**, starting "on", measured identically for underline and strikethrough and at every
   font size: **dot 3 on / 3 off; dash 10 / 5; dashDot 10 / 3 / 3 / 3; dashDotDot 10 / 3 / 3 / 3 / 3 / 3** (`TextLinePattern.swift`, `Pattern.cycle`).
2. The unit is SwiftUI's drawn thickness, which is a **whole number of points** and is exactly `ceil` of CoreText's underline thickness at all eleven
   sizes probed (9-17 pt: 1; 20-28: 2; 36-48: 3; 72: 5). MetalUI's unit is `max(1, ceil(face.underlineThickness - 1e-4))` (`linePatternUnit`); the
   band itself keeps the face's own thickness (divergence 152), so the dashes match SwiftUI's lengths even where the band is thinner. The same rule on
   the portable system (FreeType metrics): the unit is whole by construction.

## TM-D: where a pattern restarts (probe `PL`, `PS`, `PR`)

1. **The phase belongs to the line.** Every line (wrapped, centred or trailing too) starts its cycle "on" at its own start, `x + line.offsetX`; a new
   wrapped line restarts it.
2. An underline that begins mid-line is **cut from the line's cycle**, not restarted at its own start (plain 8 H then a dash underline: the first dash is
   8.38 long = 10 - (76.62 mod 15)).
3. The cycle **carries across runs**: neighbours of one pattern continue it whatever their colour (the probe saw no break at a colour change); at a
   change of pattern the new shape takes over at the same x with **its own cycle counted from the line start** (dash then dot: the dots resume on the dot
   period's grid, x = 78 = 13 x 6).
4. Implementation: the existing join (`pending`) now joins only neighbours of one colour **and** one pattern; each band is split by `linePatternSegments`
   with `origin` the line start. RTL is unprobed (MetalUI does not mirror lines, divergence 25).

## TM-E: the emitter, shared and shaderless

The dash emitter splits one decoration rectangle into segment rects **on the CPU** in `drawStyledText` (`MetalUI`, shared code: macOS, Linux and
Windows run the same function). No shader, no renderer and no replay change, so `shaders.metal`/`replay.hlsl` parity (`TE-AD`) is satisfied by
construction; the segments are ordinary rects inside the text's one leaf group (`RT-J`), colours snap as before (`RT-L`). A solid line is still one rect,
byte for byte as before. Cost: one rect per segment (a 400-point dashed line at 13 pt is about 27); a dotted line more. The cap is the line's width over
the period.

## TM-F: bold, italic, monospaced

1. A view-level `bold()` is `EnvironmentValues.isBold` and a weight of **last resort**: `own.weight ?? environment.fontWeight ?? (isBold && the font
   names no weight ? .bold)` in `resolveTextStyle`. Measured (probe `W`): `.fontWeight(.light)` wins over `.bold()` in either nesting order, a
   `Text`'s own `fontWeight(.light)` inside `.bold()` stays light, a `.light` font stays light, and `.headline` under `.bold()` equals
   `Font.headline.bold()`. The bold weight is MetalUI's full bold, the same difference as `Text.bold()` (divergence 158, amended).
2. `isBold` reaches every text through `resolveTextStyle` - the plain path included, so bold alone never forces the styled path (`RT-F` item 3).
3. A view-level `monospaced()` is read where a run's request is built (`run.monospaced ?? rich.monospaced ?? view.monospaced`); a custom font ignores it.

## TM-G: keying (retained subtrees, the layout memo, the fast path)

1. `EnvironmentFingerprint` gains `isBold` and `textRich` (the fields, by value), with rows in `differences(from:)` and in the `Mirror` guards, so a
   retained subtree under an ancestor's `.kerning`/`.underline(pattern:)`/`.bold()` change misses and repaints and an equal rebuild hits
   (`RetainedTextViewModifierTests`). The layout memo reads the environment through the same fingerprint.
2. `plainTextForm` takes `viewLevel:` and returns `nil` when any view-level rich field is set: a text under `.kerning(0)` takes the styled calls, as its
   own would (`RT-F` item 3, `RT-M`); an environment with none leaves plain text byte for byte (test `aTextUnderAViewLevelModifierTakesTheStyledPath...`).

## TM-H: reach, limits, the divergence not taken

1. `TextField`/`TextEditor` stay plain (`RT-A`): the view-level underline, strikethrough, kerning, tracking, baseline offset and monospaced do not
   reach them; bold and italic do, through `resolveTextStyle`. Whether SwiftUI applies them to a field is **unmeasured**: `ImageRenderer` draws no
   `TextField` (probe in the record). With no measurement there is no divergence label (995 stays unused); carried.
2. The dash lengths on a face with a missing or zero underline thickness use the unit 1 (`max(1, ...)`).
3. `Text` + `Text` still pushes only each side's own fields (`RT-E`); the environment is applied once, at resolution, to the joined text.
