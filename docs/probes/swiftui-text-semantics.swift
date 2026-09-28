// SwiftUI probe: text semantics (plan task 11, part 1) — foreground style,
// `Font` (text styles, weights, designs, italic, custom faces, inheritance),
// dynamic type and `controlSize` on the default font, the integer text answer
// (divergence 60), line heights, `lineLimit` (and `reservesSpace`, ranges, a
// height proposal), truncation (tail/head/middle, single and multi-line),
// `multilineTextAlignment`, text baselines (guide values, HStack and GridRow
// baseline alignment, how containers combine them) and the default spacing
// between a `Text` and its neighbours (divergence 51).
//
// Evidence for rulings TE-A… in
// docs/superpowers/2026-09-28-text-semantics-decisions.md, cited by arm id
// (`F1`, `L5`, `X8` …).
//
// HOW TO RUN (ruling SA-O's two forms), from the repository root (it registers
// `Tests/Fonts/NotoSans-Regular.ttf` for the process by a relative path):
//
//   xcrun swiftc docs/probes/swiftui-text-semantics.swift -o /tmp/text-probe && /tmp/text-probe
//   /usr/bin/swift docs/probes/swiftui-text-semantics.swift
//
// INSTRUMENTS. Everything is headless — no window is ordered front, so a
// locked screen measures the same:
// - MEASURE: a one-child custom `Layout` (`Measure`) asks its child
//   `sizeThatFits(p)` and `dimensions(in: p)[.firstTextBaseline/.lastTextBaseline]`
//   for a fixed proposal `p` (default `.unspecified`), inside an
//   `NSHostingView` whose `fittingSize` drives the pass, under
//   `.environment(\.displayScale, 2)` unless an arm says otherwise.
// - WHERE: a one-child `Layout` (`Where`) records the bounds its parent places
//   it at; an `ImageRenderer` render drives placement. Positions are in the
//   renderer's space, so a stack's children are read against the stack's own
//   `Where`.
// - RENDER: `ImageRenderer` at scale 2 on white, compared pixel for pixel
//   (`differing` counts RGB mismatches). Font identity is read this way: a
//   SwiftUI font "equals" a CoreText face when `Text(s).font(f)` and
//   `Text(s).font(Font(ctFont))` render identically (0 px). Truncation is read
//   the same way against candidate strings, and against CoreText's own
//   `CTLineCreateTruncatedLine` (its kept string, `ctKept`, read from each run's
//   string indices with the token run marked).
// - INK: per 32-device-pixel band, the first and last non-white column (A
//   arms); the darkest pixel's RGB (C arms).
//
// SEPARATING ARMS AND POSITIVE CONTROLS.
// - G0: the default `Text` (72×16) against `.system(size: 26)` (129.5×30) —
//   every size arm is read against a font change that visibly moves it.
// - F1/F2/F3/F4/F5: each font arm has a 0-px match against a named CoreText
//   face AND is separated from its neighbours (F2's nine weights all measure
//   differently; F4's italic differs from upright by 1770 px; F2g's bold from
//   unbolded by 3449 px). F2h/F4b are the no-synthesis arms: with only Noto
//   Sans Regular registered, `.bold()`/`.italic()` change nothing (0 px),
//   while the same modifiers on Helvetica Neue (F2g, X2b) select its faces.
// - F7: dynamic type is read against F1's text styles; F8 against its own
//   `.regular` row.
// - M1: one string at scale 1, 2 and 3 separates "ceil to whole points" from
//   "ceil to the displayScale pixel grid" (71.667 at 3).
// - L1/L5/X9: the unlimited answer (100×96) is the control for every limit.
// - T/X5–X8: the untruncated string is always a candidate; widths are
//   compared with CoreText's truncated width for each mode.
// - B2/X11: `.top` and `.center` are the controls for the baseline rows.
// - X4: two colour blocks (S1b, 28 = 10 + 8 + 10) are the control for the
//   spacing arms.
// - C: C0 (default ink) is the control for every colour arm.
//
// RECORDED 2026-09-28 by the plan task 11 part 1 design session, macOS 27.0
// (26A428), Apple Swift 6.4 (swiftlang-6.4.0.33.1), one built-in 2x display,
// **screen LOCKED** (the lock probe read `CGSSessionScreenIsLocked = 1`,
// `displayAsleep main: 1`) — irrelevant to these arms, which never order a
// window front. The compiled form was run twice (stdout byte-identical, 294
// lines, exit 0, stderr empty) and the interpreted form once (`/usr/bin/swift`,
// stdout byte-identical to the compiled form's, exit 0).
//
//   setup: Noto Sans registered=true
//   --- G0 controls
//     G0a Text("Hello, world"): size=72x16 first=13 last=13
//     G0b .font(.system(size: 26)): size=129.5x30 first=25 last=25
//     G0c CT width of "Hello, world" in systemFont(13): 71.525 ascent=12.568 descent=2.742 leading=0
//   --- F1 text styles ("Hello, world 0123")
//     F1 largeTitle: size=193.5x31 first=25 last=25 preferredFont=26pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 26, weight: Weight(value: 0.0))
//     F1 title: size=164.5x26 first=21 last=21 preferredFont=22pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 22, weight: Weight(value: 0.0))
//     F1 title2: size=132x20.5 first=16 last=16 preferredFont=17pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 17, weight: Weight(value: 0.0))
//     F1 title3: size=119x19 first=15 last=15 preferredFont=15pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 15, weight: Weight(value: 0.0))
//     F1 headline: size=113x16 first=13 last=13 preferredFont=13pt weightTrait=0.4 differsFromFont(preferredCTFont)=0px equals=.system(size: 13, weight: Weight(value: 0.4))
//     F1 subheadline: size=91.5x14 first=11 last=11 preferredFont=11pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 11, weight: Weight(value: 0.0))
//     F1 body: size=105.5x16 first=13 last=13 preferredFont=13pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 13, weight: Weight(value: 0.0))
//     F1 callout: size=98.5x15 first=12 last=12 preferredFont=12pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 12, weight: Weight(value: 0.0))
//     F1 footnote: size=84x13 first=10 last=10 preferredFont=10pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 10, weight: Weight(value: 0.0))
//     F1 caption: size=84x13 first=10 last=10 preferredFont=10pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 10, weight: Weight(value: 0.0))
//     F1 caption2: size=86x13 first=10 last=10 preferredFont=10pt weightTrait=0 differsFromFont(preferredCTFont)=0px equals=.system(size: 10, weight: Weight(value: 0.23))
//   --- F2 weights ("Hello, world" at 13)
//     F2 ultraLight: size=68x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=67.856 differsFromFont(NSFont systemFont weight)=0px
//     F2 thin: size=69x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=68.649 differsFromFont(NSFont systemFont weight)=0px
//     F2 light: size=70.5x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=70.276 differsFromFont(NSFont systemFont weight)=0px
//     F2 regular: size=72x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=71.525 differsFromFont(NSFont systemFont weight)=0px
//     F2 medium: size=74x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=73.614 differsFromFont(NSFont systemFont weight)=0px
//     F2 semibold: size=75.5x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=75.133 differsFromFont(NSFont systemFont weight)=0px
//     F2 bold: size=77.5x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=77.222 differsFromFont(NSFont systemFont weight)=0px
//     F2 heavy: size=80.5x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=80.261 differsFromFont(NSFont systemFont weight)=0px
//     F2 black: size=83x16 first=13 last=13 ctWidth(NSFont.systemFont(13, weight))=82.919 differsFromFont(NSFont systemFont weight)=0px
//     F2b Text.bold() vs .system(13, .bold): 1657px
//     F2c .fontWeight(.bold) vs .system(13, .bold): 0px
//     F2d VStack{Text}.bold() (View modifier) vs .system(13, .bold): 1657px
//     F2e .font(.headline).bold() vs .system(13, .heavy): 0px; vs .system(13, .bold): 2980px
//     F2f .font(.body).fontWeight(.light) vs .system(13, .light): 0px
//     F2g .custom("Helvetica Neue", 15).bold() vs Font(HelveticaNeue-Bold 15): 0px; vs unbolded: 3449px
//     F2h .custom("Noto Sans", 15).bold() (only Regular registered) vs unbolded: 0px size=123x20 first=16 last=16 vs size=123x20 first=16 last=16
//   --- F3 design, F4 italic
//     F3 serif: size=105.5x16 first=12 last=12 resolvedName=.NewYork-Regular differsFromFont(designDescriptor)=0px
//     F3 rounded: size=103x16 first=13 last=13 resolvedName=.AppleSystemUIFontRounded-Regular differsFromFont(designDescriptor)=0px
//     F3 monospaced: size=137x16 first=13 last=13 resolvedName=.AppleSystemUIFontMonospaced-Regular differsFromFont(designDescriptor)=0px
//     F4 Text.italic(): size=105.5x16 first=13 last=13 italicName=.SFNS-RegularItalic differsFromFont(symbolicItalic)=0px differsFromUpright=1770px
//     F4b .custom("Noto Sans", 15).italic() (no italic face registered) vs upright: 0px
//   --- F5 custom
//     F5 custom Helvetica 17: size=131.5x17 first=13 last=13 ctWidth=131.352 ctName=Helvetica differsFromFont(CTFontCreateWithName)=0px
//     F5 custom Noto Sans 17: size=139.5x23 first=18 last=18 ctWidth=139.043 ctName=NotoSans-Regular differsFromFont(CTFontCreateWithName)=0px
//     F5 custom NoSuchFont 17: size=131.5x17 first=13 last=13 ctWidth=131.352 ctName=Helvetica differsFromFont(CTFontCreateWithName)=0px
//     F5b custom(Noto Sans, fixedSize: 17): size=139.5x23 first=18 last=18
//     F5c custom(Noto Sans, size: 17, relativeTo: .body): size=139.5x23 first=18 last=18
//   --- F6 inheritance
//     F6a VStack{Text}.font(.title): size=164.5x26 first=21 last=21
//     F6a' Text.font(.title) alone:  size=164.5x26 first=21 last=21
//     F6b VStack{Text.font(.caption)}.font(.title): size=84x13 first=10 last=10
//     F6b' Text.font(.caption) alone: size=84x13 first=10 last=10
//     F6c VStack{Text.font(nil)}.font(.title): size=105.5x16 first=13 last=13
//     F6d VStack{Text.font(.body)}.fontWeight(.bold): size=113x16 first=13 last=13
//     F6d' Text.font(.system(13, .bold)) alone: size=113x16 first=13 last=13
//     F6e VStack{Text}.font(.title).font(.caption) (outer written last): size=164.5x26 first=21 last=21
//   --- F7 dynamicTypeSize (macOS)
//     F7 xSmall: body=size=105.5x16 first=13 last=13 title=size=164.5x26 first=21 last=21 default=size=105.5x16 first=13 last=13 customRelative=size=139.5x23 first=18 last=18 system13=size=105.5x16 first=13 last=13
//     F7 large: body=size=105.5x16 first=13 last=13 title=size=164.5x26 first=21 last=21 default=size=105.5x16 first=13 last=13 customRelative=size=139.5x23 first=18 last=18 system13=size=105.5x16 first=13 last=13
//     F7 xxxLarge: body=size=105.5x16 first=13 last=13 title=size=164.5x26 first=21 last=21 default=size=105.5x16 first=13 last=13 customRelative=size=139.5x23 first=18 last=18 system13=size=105.5x16 first=13 last=13
//     F7 accessibility5: body=size=105.5x16 first=13 last=13 title=size=164.5x26 first=21 last=21 default=size=105.5x16 first=13 last=13 customRelative=size=139.5x23 first=18 last=18 system13=size=105.5x16 first=13 last=13
//   --- F8 controlSize
//     F8 mini: default=size=76.5x11 first=9 last=9 equals=.system(size: 13) body=size=105.5x16 first=13 last=13 caption=size=84x13 first=10 last=10 TextField=size=35x19 first=13 last=13 TextField.font(.system(20))=size=57x32 first=22.5 last=22.5
//     F8 small: default=size=91.5x14 first=11 last=11 equals=.system(size: 13) body=size=105.5x16 first=13 last=13 caption=size=84x13 first=10 last=10 TextField=size=39x22 first=14.5 last=14.5 TextField.font(.system(20))=size=57x32 first=22.5 last=22.5
//     F8 regular: default=size=105.5x16 first=13 last=13 equals=.system(size: 13) body=size=105.5x16 first=13 last=13 caption=size=84x13 first=10 last=10 TextField=size=43x24 first=17 last=17 TextField.font(.system(20))=size=57x32 first=22.5 last=22.5
//     F8 large: default=size=105.5x16 first=13 last=13 equals=.system(size: 13) body=size=105.5x16 first=13 last=13 caption=size=84x13 first=10 last=10 TextField=size=43x24 first=17 last=17 TextField.font(.system(20))=size=57x32 first=22.5 last=22.5
//     F8 extraLarge: default=size=105.5x16 first=13 last=13 equals=.system(size: 13) body=size=105.5x16 first=13 last=13 caption=size=84x13 first=10 last=10 TextField=size=43x24 first=17 last=17 TextField.font(.system(20))=size=57x32 first=22.5 last=22.5
//     F8h default font under .controlSize(.small) inside .font(.title): size=164.5x26 first=21 last=21
//   --- M metrics
//     M1 "Hello, world" @13: ctWidth=71.525 ascent=12.568 descent=2.742 leading=0 scale1=size=72x16 first=13 last=13 scale2=size=72x16 first=13 last=13 scale3=size=71.667x16 first=13 last=13
//     M1 "iiii" @13: ctWidth=12.543 ascent=12.568 descent=2.742 leading=0 scale1=size=13x16 first=13 last=13 scale2=size=13x16 first=13 last=13 scale3=size=12.667x16 first=13 last=13
//     M1 "W" @13: ctWidth=12.505 ascent=12.568 descent=2.742 leading=0 scale1=size=13x16 first=13 last=13 scale2=size=13x16 first=13 last=13 scale3=size=12.667x16 first=13 last=13
//     M1 "The quick brown fox" @17.5: ctWidth=157.854 ascent=16.919 descent=3.691 leading=0 scale1=size=158x21 first=17 last=17 scale2=size=158x21 first=17 last=17 scale3=size=158x21 first=17 last=17
//     M1 "Hello, world" @11: ctWidth=62.068 ascent=10.635 descent=2.32 leading=0 scale1=size=63x14 first=11 last=11 scale2=size=62.5x14 first=11 last=11 scale3=size=62.333x14 first=11 last=11
//     M2 paragraph at width 100: size=100x96 first=13 last=93
//     M2 paragraph at width 150: size=148x64 first=13 last=61
//     M2 paragraph at width 37: size=37x240 first=13 last=237
//     M3 "A\nB\nC": size=9.5x48 first=13 last=45
//     M3b "A\nB\nC" Noto 17: size=11.5x69 first=18 last=64 ctAscent=18.173 ctDescent=4.981 ctLeading=0
//     M4 "A\nB" .lineSpacing(4): size=9x36 first=13 last=33
//   --- L lineLimit (paragraph, width 100)
//     L1 nil: size=100x96 first=13 last=93
//     L1 0: size=93.5x16 first=13 last=13
//     L1 1: size=93.5x16 first=13 last=13
//     L1 2: size=95.5x32 first=13 last=29
//     L1 3: size=100x48 first=13 last=45
//     L1 10: size=100x96 first=13 last=93
//     L2 "Hi" lineLimit(3, reservesSpace: true): size=13x48 first=13 last=13
//     L2 "Hi" lineLimit(3, reservesSpace: false): size=13x16 first=13 last=13
//     L2 paragraph lineLimit(2, reservesSpace: true): size=95.5x32 first=13 last=29
//     L2 "Hi" lineLimit(3, reservesSpace: true), unspecified: size=13x48 first=13 last=13
//     L3 "Hi" lineLimit(2...3): size=13x32 first=13 last=13
//     L3 paragraph lineLimit(2...3): size=100x48 first=13 last=45
//     L3 paragraph lineLimit(...2): size=95.5x32 first=13 last=29
//     L3 "Hi" lineLimit(3...): size=13x48 first=13 last=13
//     L4 paragraph lineLimit(1), unspecified width: size=461x16 first=13 last=13
//     L5 paragraph, proposal 100x20 (no lineLimit): size=93.5x16 first=13 last=13
//     L5 paragraph, proposal 100x40 (no lineLimit): size=95.5x32 first=13 last=29
//     L5 paragraph, proposal 100x5 (no lineLimit): size=93.5x16 first=13 last=13
//     L5 paragraph, proposal 100x0 (no lineLimit): size=93.5x16 first=13 last=13
//     L6 VStack{Text}.lineLimit(1) (environment), width 100: size=93.5x16 first=13 last=13
//     L6b VStack{Text.lineLimit(3)}.lineLimit(1): size=100x48 first=13 last=45
//   --- T truncation (identified by rendering each candidate)
//     T1 tail width 60: size=58.5x16 first=13 last=13 drawn no exact match; nearest "Hello, w…" (73 px differ) CTLineCreateTruncatedLine(.end): ctWidth=58.31 glyphs=9
//     T1 tail width 80: size=73.5x16 first=13 last=13 drawn == "Hello, won…" CTLineCreateTruncatedLine(.end): ctWidth=73.423 glyphs=11
//     T1 tail width 100: size=99x16 first=13 last=13 drawn no exact match; nearest "Hello, wonderf…" (73 px differ) CTLineCreateTruncatedLine(.end): ctWidth=98.566 glyphs=15
//     T1 tail width 130: size=123x16 first=13 last=13 drawn no exact match; nearest "Hello, wonderful w…" (63 px differ) CTLineCreateTruncatedLine(.end): ctWidth=122.605 glyphs=19
//     T2 head width 60: drawn == "…ul world" CT(.start): ctWidth=58.024 glyphs=9
//     T2 middle width 60: drawn no exact match; nearest "Hello…rld" (355 px differ) CT(.middle): ctWidth=57.332 glyphs=9
//     T2 head width 100: drawn no exact match; nearest "…onderful world" (1236 px differ) CT(.start): ctWidth=98.281 glyphs=15
//     T2 middle width 100: drawn no exact match; nearest "Hello,…ful world" (820 px differ) CT(.middle): ctWidth=85.122 glyphs=14
//     T3 "Alpha beta gamma delta" tail width 70: drawn == "Alpha bet…" CT(.end): ctWidth=68.294 glyphs=10
//     T3 "Alpha beta gamma delta" tail width 75: drawn == "Alpha bet…" CT(.end): ctWidth=68.294 glyphs=10
//     T3 "Alpha beta gamma delta" tail width 80: drawn == "Alpha beta…" CT(.end): ctWidth=75.391 glyphs=11
//     T4 height-driven, frame 100x20: drawn no exact match; nearest "Hello, wonderf…" (73 px differ)
//     T5 lineLimit(2) width 100: size=100x32 first=13 last=29 drawn no exact match; nearest "Alpha beta…" (1702 px differ) (candidates rendered wrapped at 100: prefix+ellipsis)
//     T5b lineLimit(2) width 100, candidates wrapped at 100: == "Alpha beta gamma delta e…" wrapped at 100
//     T5c lineLimit(2).truncationMode(.middle): differs from tail by 1155px
//     T6 three full stops as the token instead of U+2026: no exact match; nearest "Hello, won..." (48 px differ)
//   --- A multilineTextAlignment ("Short\nA much longer line", ink per 32-px band at scale 2)
//     A1 leading: size=113x32 first=13 last=29 ink=["1…64", "1…223"]
//     A1 center: size=113x32 first=13 last=29 ink=["81…144", "1…223"]
//     A1 trailing: size=113x32 first=13 last=29 ink=["161…224", "1…224"]
//     A2 center inside frame(width: 200, alignment: .leading): ink=["81…144", "1…223"]
//     A3 one line, trailing, inside frame(width: 200, alignment: .leading): ink=["2…98"]
//     A4 VStack{Text}.multilineTextAlignment(.trailing): ink=["161…224", "1…224"]
//     A5 paragraph center wrapped at 100: size=100x96 first=13 last=93 ink=["41…158", "2…197", "24…176"]
//     A6 truncated one line, trailing, width 80: ink=["2…144"]
//   --- B baselines
//     B1 Text("Hg") 13: size=17.5x16 first=13 last=13
//     B1 Text("Hg\nHg") 13: size=17.5x32 first=13 last=29
//     B1 Text("Hg") 26: size=33.5x30 first=25 last=25 ctAscent26=25.137
//     B1 Text("Hg") Noto 17: size=23.5x23 first=18 last=18
//     B1 Text("Hg") 11: size=15x14 first=11 last=11 ctAscent11=10.635
//     B1 Color 20x30: size=20x30 first=30 last=30
//     B1 VStack(spacing: 0){Text 13; Text 26}: size=33.5x46 first=13 last=41
//     B1 HStack(spacing: 0){Text 13; Text 26} (center): size=51x30 first=20 last=25
//     B1 Text.padding(8): size=33.5x32 first=21 last=21
//     B1 Text.frame(height: 50): size=17.5x50 first=30 last=30
//     B1 ZStack{Color 40x40; Text}: size=40x40 first=25 last=25
//     B1 Text.background(Color): size=17.5x16 first=13 last=13
//     B1 HStack{Color 10x10}: size=10x10 first=10 last=10
//     B1 Text.lineLimit(1) width 30 (truncated): size=28x16 first=13 last=13
//     B1 Text wrapped at 30 ("Hg Hg Hg"): size=21x48 first=13 last=45
//     B1 VStack{Color 10x10; Text}: size=17.5x26 first=23 last=23
//     B2 HStack(alignment: .firstTextBaseline): size=78.5x44 first=25 last=41
//       B2firstTextBaseline-13: minX=0 minY=12 w=17.5 h=16
//       B2firstTextBaseline-26: minX=17.5 minY=0 w=33.5 h=30
//       B2firstTextBaseline-2line: minX=51 minY=12 w=17.5 h=32
//       B2firstTextBaseline-color: minX=68.5 minY=15 w=10 h=10
//       B2firstTextBaseline-stack: minX=0 minY=0 w=78.5 h=44
//     B2 HStack(alignment: .lastTextBaseline): size=78.5x34 first=13 last=29
//       B2lastTextBaseline-13: minX=0 minY=16 w=17.5 h=16
//       B2lastTextBaseline-26: minX=17.5 minY=4 w=33.5 h=30
//       B2lastTextBaseline-2line: minX=51 minY=0 w=17.5 h=32
//       B2lastTextBaseline-color: minX=68.5 minY=19 w=10 h=10
//       B2lastTextBaseline-stack: minX=0 minY=0 w=78.5 h=34
//     B2 HStack(alignment: .center): size=78.5x32 first=13 last=29
//       B2center-13: minX=0 minY=8 w=17.5 h=16
//       B2center-26: minX=17.5 minY=1 w=33.5 h=30
//       B2center-2line: minX=51 minY=0 w=17.5 h=32
//       B2center-color: minX=68.5 minY=11 w=10 h=10
//       B2center-stack: minX=0 minY=0 w=78.5 h=32
//     B2 HStack(alignment: .top): size=78.5x32 first=13 last=29
//       B2top-13: minX=0 minY=0 w=17.5 h=16
//       B2top-26: minX=17.5 minY=0 w=33.5 h=30
//       B2top-2line: minX=51 minY=0 w=17.5 h=32
//       B2top-color: minX=68.5 minY=0 w=10 h=10
//       B2top-stack: minX=0 minY=0 w=78.5 h=32
//   --- S default spacing between Text views
//     S1 VStack{Text; Text}: size=17.5x32 first=13 last=29
//     S1b VStack{Color 10x10; Color 10x10} (control): size=10x28 first=28 last=28
//     S1c VStack{Text; Color 10x10}: size=17.5x34.151 first=13 last=13
//     S1d VStack{Text 26; Text 26}: size=33.5x60 first=25 last=55
//     S2 HStack{Text; Text}: size=43x16 first=13 last=13
//     S2b HStack{Color; Color} (control): size=28x10 first=10 last=10
//   --- C foreground (darkest ink pixel)
//     C0 default Text: rgb(39,39,39)
//     C1 Text.foregroundStyle(.red): rgb(255,56,60)
//     C2 VStack{Text}.foregroundStyle(.red): rgb(255,56,60)
//     C3 VStack{Text}.foregroundColor(.red): rgb(255,56,60)
//     C4 VStack{Text.foregroundColor(.blue)}.foregroundStyle(.red): rgb(0,136,255)
//     C5 VStack{Text.foregroundStyle(.blue)}.foregroundColor(.red): rgb(0,136,255)
//     C6 VStack{Text}.foregroundStyle(.red).foregroundStyle(.blue) (outer last): rgb(255,56,60)
//     C7 VStack{Text.foregroundColor(nil)}.foregroundStyle(.red): rgb(39,39,39)
//     C8 Text.foregroundStyle(.secondary): rgb(128,128,128)
//     C9 VStack{Rectangle 20x20}.foregroundStyle(.red) (shape fill, part 2's): rgb(255,56,60)
//   --- X follow-ups
//     X1 Text.bold() on the default font equals .system(13, weight: semibold)
//     X1b .system(13, .light).bold() equals .system(13, weight: light)
//     X1c Font.system(size: 13).bold() (Font modifier) equals .system(13, weight: bold)
//     X2 .custom("Helvetica Neue", 15).weight(.ultraLight) draws HelveticaNeue-UltraLight
//     X2 .custom("Helvetica Neue", 15).weight(.thin) draws HelveticaNeue-Thin
//     X2 .custom("Helvetica Neue", 15).weight(.light) draws HelveticaNeue-Light
//     X2 .custom("Helvetica Neue", 15).weight(.regular) draws HelveticaNeue
//     X2 .custom("Helvetica Neue", 15).weight(.medium) draws HelveticaNeue-Medium
//     X2 .custom("Helvetica Neue", 15).weight(.semibold) draws HelveticaNeue-Medium
//     X2 .custom("Helvetica Neue", 15).weight(.bold) draws HelveticaNeue-Bold
//     X2 .custom("Helvetica Neue", 15).weight(.heavy) draws HelveticaNeue-Bold
//     X2 .custom("Helvetica Neue", 15).weight(.black) draws none
//     X2b .custom("Helvetica Neue", 15).italic() vs HelveticaNeue-Italic: 0px
//     X2c .custom("HelveticaNeue-Bold", 15) (a PostScript name) vs HelveticaNeue-Bold: 0px
//     X2d .custom("HelveticaNeue-Bold", 15).weight(.light) draws HelveticaNeue-Light
//     X3 HStack(spacing: 0){Text 26; Text 13} (center): size=51x30 first=20 last=25
//     X3 VStack(spacing: 0){Text 13; Color 10x10}: size=17.5x26 first=13 last=13
//     X3 HStack(alignment: .bottom, spacing: 0){Text 13; Text\nText 13}: size=35x32 first=13 last=29
//     X3 HStack(alignment: .top, spacing: 0){Text\nText 13; Text 13}: size=35x32 first=13 last=29
//     X3 Spacer in HStack: size=8x0 first=0 last=0
//     X3 Text.fixedSize(): size=17.5x16 first=13 last=13
//     X3 Text.overlay(Color): size=17.5x16 first=13 last=13
//     X3 Color.overlay(Text): size=30x30 first=30 last=30
//     X3 Grid{GridRow{Text}}: size=17.5x16 first=13 last=13
//     X3 ScrollView{Text}: size=17.5x100 first=100 last=100
//     X3 Text.offset(y: 7): size=17.5x16 first=13 last=13
//     X3 Text.alignmentGuide(.firstTextBaseline) { _ in 4 }: size=17.5x16 first=4 last=13
//     X4 VStack{Text 13; Color}: size=17.5x34.151 first=13 last=13
//     X4 VStack{Color; Text 13}: size=17.5x30.742 first=27.742 last=27.742
//     X4 VStack{Text 26; Color}: size=33.5x55.802 first=25 last=25
//     X4 VStack{Color; Text 26}: size=33.5x48.984 first=43.984 last=43.984
//     X4 VStack{Text 13; Text 26}: size=33.5x46 first=13 last=41
//     X4 VStack{Text Noto 17; Color}: size=23.5x46.516 first=18 last=18
//     X4 VStack{Text 13 padded 1; Color}: size=19.5x36 first=14 last=14
//     X4 VStack{Text 13 framed h20; Color}: size=17.5x38 first=15 last=15
//     X4 HStack{Text 13; Color}: size=35.5x16 first=13 last=13
//     X5 tail width 60: SwiftUI size=58.5x16 first=13 last=13 CT kept "Hello, w…" ctWidth=58.31 glyphs=9
//     X5 head width 60: SwiftUI size=58.5x16 first=13 last=13 CT kept "…ul world" ctWidth=58.024 glyphs=9
//     X5 middle width 60: SwiftUI size=57.5x16 first=13 last=13 CT kept "Hell…orld" ctWidth=57.332 glyphs=9
//     X5 tail width 100: SwiftUI size=99x16 first=13 last=13 CT kept "Hello, wonderf…" ctWidth=98.566 glyphs=15
//     X5 head width 100: SwiftUI size=98.5x16 first=13 last=13 CT kept "…onderful world" ctWidth=98.281 glyphs=15
//     X5 middle width 100: SwiftUI size=97.5x16 first=13 last=13 CT kept "Hello,…l world" ctWidth=85.122 glyphs=14
//     X6 "Alpha beta gamma delta" tail width 70: CT kept "Alpha bet…" width("Alpha beta…")=75.391 width("Alpha beta …")=78.971 SwiftUI size=68.5x16 first=13 last=13
//     X6 "Alpha beta gamma delta" tail width 75: CT kept "Alpha bet…" width("Alpha beta…")=75.391 width("Alpha beta …")=78.971 SwiftUI size=68.5x16 first=13 last=13
//     X6 "Alpha beta gamma delta" tail width 78: CT kept "Alpha beta…" width("Alpha beta…")=75.391 width("Alpha beta …")=78.971 SwiftUI size=75.5x16 first=13 last=13
//     X6 "Alpha beta gamma delta" tail width 79: CT kept "Alpha beta…" width("Alpha beta…")=75.391 width("Alpha beta …")=78.971 SwiftUI size=75.5x16 first=13 last=13
//     X6 "Alpha beta gamma delta" tail width 80: CT kept "Alpha beta…" width("Alpha beta…")=75.391 width("Alpha beta …")=78.971 SwiftUI size=75.5x16 first=13 last=13
//     X6 "Alpha beta gamma delta" tail width 84: CT kept "Alpha beta…" width("Alpha beta…")=75.391 width("Alpha beta …")=78.971 SwiftUI size=75.5x16 first=13 last=13
//     X7 head width 60: SwiftUI render vs Text(CT kept "…ul world"): 0px
//     X7 head width 100: SwiftUI render vs Text(CT kept "…onderful world"): 1236px
//     X7 middle width 60: SwiftUI render vs Text(CT kept "Hell…orld"): 361px
//     X7 middle width 100: SwiftUI render vs Text(CT kept "Hello,…l world"): 1136px
//     X7 tail width 60: SwiftUI render vs Text(CT kept "Hello, w…"): 73px
//     X7 tail width 100: SwiftUI render vs Text(CT kept "Hello, wonderf…"): 73px
//     X8 line 1 at width 100: "Alpha beta " rest: "gamma delta epsilon zeta eta theta"
//     X8 lineLimit(2) tail: rest truncated by CT = "gamma delta e…"; SwiftUI vs Text(line1 + \n + that): 0px
//     X8 lineLimit(2) head: rest truncated by CT = "…zeta eta theta"; SwiftUI vs Text(line1 + \n + that): 0px
//     X8 lineLimit(2) middle: rest truncated by CT = "gamma…a theta"; SwiftUI vs Text(line1 + \n + that): 0px
//     X9 paragraph lineLimit(2) at 100, height proposal 20: size=93.5x16 first=13 last=13
//     X9 "Hi" lineLimit(3, reservesSpace: true), height proposal 20: size=13x48 first=13 last=13
//     X9 paragraph, proposal 100x47.9: size=95.5x32 first=13 last=29
//     X9 paragraph, proposal 100x48: size=100x48 first=13 last=45
//     X9 paragraph, proposal nil x 20: size=461x16 first=13 last=13
//     X9 paragraph, proposal 100 x infinity: size=100x96 first=13 last=93
//     X10 empty Text(""): size=0x14 first=11 last=11 lineLimit(2, reservesSpace: true): size=0x14 first=11 last=11
//     X11 Grid, GridRow(alignment: .firstTextBaseline): size=78.5x37 first=13 last=29
//       X11firstTextBaseline-13: minX=0 minY=0 w=17.5 h=16
//       X11firstTextBaseline-26: minX=17.5 minY=-12 w=33.5 h=30
//       X11firstTextBaseline-2line: minX=51 minY=0 w=17.5 h=32
//       X11firstTextBaseline-color: minX=68.5 minY=3 w=10 h=10
//       X11firstTextBaseline-grid: minX=0 minY=0 w=78.5 h=37
//       X11firstTextBaseline-row2: minX=6.25 minY=32 w=5 h=5
//     X11 Grid, GridRow(alignment: .lastTextBaseline): size=78.5x37 first=11 last=27
//       X11lastTextBaseline-13: minX=0 minY=14 w=17.5 h=16
//       X11lastTextBaseline-26: minX=17.5 minY=2 w=33.5 h=30
//       X11lastTextBaseline-2line: minX=51 minY=-2 w=17.5 h=32
//       X11lastTextBaseline-color: minX=68.5 minY=17 w=10 h=10
//       X11lastTextBaseline-grid: minX=0 minY=0 w=78.5 h=37
//       X11lastTextBaseline-row2: minX=6.25 minY=32 w=5 h=5
//     X11b Grid(alignment: .leadingFirstTextBaseline) { GridRow { Text 13; Text 26 } }: size=51x30 first=25 last=25
//     X12 CT bold trait on systemFont(13, .regular): .SFNS-Regular weight=0 -> .SFNS-Bold weight=0.4
//     X12 CT bold trait on systemFont(13, .light): .SFNS-Light weight=-0.4 -> .SFNS-Light weight=-0.4
//     X12 CT bold trait on systemFont(13, .bold): .SFNS-Bold weight=0.4 -> .SFNS-Bold weight=0.4
//     X12 CT bold trait on systemFont(13, .semibold): .SFNS-Semibold weight=0.3 -> .SFNS-Semibold weight=0.3
//     X12b Text.bold() vs Font(CT bold trait of systemFont(13)): 2707px
//     X13 system 9: ascent+descent+leading=10.6 ascent=8.701 one line size=13x11 first=9 last=9 two lines size=13x22 first=9 last=20 one line at scale 2 size=12.5x11 first=9 last=9
//     X13 system 10: ascent+descent+leading=11.777 ascent=9.668 one line size=14x13 first=10 last=10 two lines size=14x26 first=10 last=23 one line at scale 2 size=14x13 first=10 last=10
//     X13 system 11: ascent+descent+leading=12.955 ascent=10.635 one line size=15x14 first=11 last=11 two lines size=15x28 first=11 last=25 one line at scale 2 size=15x14 first=11 last=11
//     X13 system 12: ascent+descent+leading=14.133 ascent=11.602 one line size=17x15 first=12 last=12 two lines size=17x30 first=12 last=27 one line at scale 2 size=16.5x15 first=12 last=12
//     X13 system 13: ascent+descent+leading=15.311 ascent=12.568 one line size=18x16 first=13 last=13 two lines size=18x32 first=13 last=29 one line at scale 2 size=17.5x16 first=13 last=13
//     X13 system 14: ascent+descent+leading=16.488 ascent=13.535 one line size=19x17 first=14 last=14 two lines size=19x34 first=14 last=31 one line at scale 2 size=19x17 first=14 last=14
//     X13 system 15: ascent+descent+leading=17.666 ascent=14.502 one line size=20x19 first=15 last=15 two lines size=20x38 first=15 last=34 one line at scale 2 size=20x19 first=15 last=15
//     X13 system 16: ascent+descent+leading=18.844 ascent=15.469 one line size=21x19 first=15 last=15 two lines size=21x38 first=15 last=34 one line at scale 2 size=21x19 first=15 last=15
//     X13 system 17: ascent+descent+leading=20.021 ascent=16.436 one line size=23x20 first=16 last=16 two lines size=23x40 first=16 last=36 one line at scale 2 size=22.5x20 first=16 last=16
//     X13 system 20: ascent+descent+leading=23.555 ascent=19.336 one line size=26x24 first=19 last=19 two lines size=26x48 first=19 last=43 one line at scale 2 size=26x24 first=19 last=19
//     X13 system 22: ascent+descent+leading=25.91 ascent=21.27 one line size=29x26 first=21 last=21 two lines size=29x52 first=21 last=47 one line at scale 2 size=28.5x26 first=21 last=21
//     X13 system 26: ascent+descent+leading=30.621 ascent=25.137 one line size=34x30 first=25 last=25 two lines size=34x60 first=25 last=55 one line at scale 2 size=33.5x30 first=25 last=25
//     X13 system 30: ascent+descent+leading=35.332 ascent=29.004 one line size=39x35 first=29 last=29 two lines size=39x70 first=29 last=64 one line at scale 2 size=38.5x35 first=29 last=29
//     X13 Noto Sans 11: ascent+descent+leading=14.982 ascent=11.759 one line size=15x15 first=12 last=12 two lines size=15x30 first=12 last=27 one line at scale 2 size=15x15 first=12 last=12
//     X13 Noto Sans 13: ascent+descent+leading=17.706 ascent=13.897 one line size=18x18 first=14 last=14 two lines size=18x36 first=14 last=32 one line at scale 2 size=18x18 first=14 last=14
//     X13 Noto Sans 17: ascent+descent+leading=23.154 ascent=18.173 one line size=24x23 first=18 last=18 two lines size=24x46 first=18 last=41 one line at scale 2 size=23.5x23 first=18 last=18
//     X13 Noto Sans 26: ascent+descent+leading=35.412 ascent=27.794 one line size=36x36 first=28 last=28 two lines size=36x72 first=28 last=64 one line at scale 2 size=35.5x36 first=28 last=28
//     X13 Menlo 11: ascent+descent+leading=12.805 ascent=10.21 one line size=14x13 first=10 last=10 two lines size=14x26 first=10 last=23 one line at scale 2 size=13.5x13 first=10 last=10
//     X13 Menlo 13: ascent+descent+leading=15.133 ascent=12.067 one line size=16x15 first=12 last=12 two lines size=16x30 first=12 last=27 one line at scale 2 size=16x15 first=12 last=12
//     X13 Menlo 17: ascent+descent+leading=19.789 ascent=15.78 one line size=21x20 first=16 last=16 two lines size=21x40 first=16 last=36 one line at scale 2 size=20.5x20 first=16 last=16
//     X13 Menlo 26: ascent+descent+leading=30.266 ascent=24.134 one line size=32x30 first=24 last=24 two lines size=32x60 first=24 last=54 one line at scale 2 size=31.5x30 first=24 last=24
//   done
//
// READING (what the TE- rulings rely on; each ruling restates its arms):
// - FONT. Text styles on macOS (F1) are fixed faces: largeTitle 26, title 22,
//   title2 17, title3 15, headline 13 bold (weight 0.4), subheadline 11, body
//   13, callout 12, footnote 10, caption 10, caption2 10 medium (0.23) — each
//   0 px against `NSFont.preferredFont(forTextStyle:)` and against
//   `.system(size:weight:)`. `.system(size:weight:)` is
//   `NSFont.systemFont(ofSize:weight:)` for all nine weights (F2), `design:`
//   is the system face's design descriptor (F3: New York, SF Rounded, SF
//   Mono), `italic()` is CoreText's italic symbolic trait (F4), and
//   `.custom(name, size:)` is `CTFontCreateWithName` (F5, substitution
//   included: an unknown name draws Helvetica). `.custom(_:fixedSize:)` and
//   `relativeTo:` measure as `size:` (F5b/F5c). A custom family's `.weight`
//   selects the family's nearest face (X2: semibold → Medium, heavy → Bold,
//   black → none of the six sampled), from a PostScript name too (X2d). With
//   no other face registered nothing is synthesised (F2h, F4b).
// - BOLD. `Font.bold()` is weight `.bold` (X1c), `.fontWeight(.bold)` is too
//   (F2c), but `Text.bold()` and the `View` modifier draw SEMIBOLD on the
//   default font (X1), HEAVY on `.headline` (F2e) and nothing on `.light`
//   (X1b); CoreText's bold trait gives Bold on regular (X12), so it is not
//   CoreText's trait either. Not reproduced by a simple rule.
// - INHERITANCE. `.font` is an environment value: a container's reaches a
//   `Text` (F6a); a `Text`'s own wins (F6b); the nearest writer wins (F6e);
//   `Text.font(nil)` is the DEFAULT font, not the inherited one (F6c);
//   `.fontWeight` on a container reaches a `Text` with its own `.font` (F6d).
// - DYNAMIC TYPE. No font of any kind moves under any `dynamicTypeSize` on
//   macOS (F7), text styles and `relativeTo:` included.
// - CONTROL SIZE. The default font is 9 pt under `.mini` (76.5×11) and 11 pt
//   under `.small` (91.5×14), 13 pt otherwise (F8; Z2's numbers again); an
//   explicit font — `.body` or `.caption` included — does not move (F8), and
//   an environment font wins over the size (F8h). A `TextField`'s height
//   follows its font (F8: `.system(20)` is 32 tall at every size) and its
//   default font follows the size (19/22/24).
// - METRICS. A `Text`'s width is its widest line ceiled to the displayScale
//   pixel grid (M1: 71.525 → 72 at 1 and 2, 71.667 at 3), capped by a finite
//   width proposal (M2). Its height is lines × a line height that is NOT
//   `ceil(ascent + descent + leading)`: 13 pt → 16 (agrees), 11 pt → 14 and
//   26 pt → 30 and Noto Sans 17 → 23 (M3b) where that formula gives 13, 31 and
//   24 (X13 sweeps 21 sizes over three faces). An empty `Text` is 0×14
//   (X10). `.lineSpacing(4)` adds 4 between lines (M4).
// - LINE LIMIT. `lineLimit(n)` caps the lines at n (L1); 0 acts as 1; the
//   width is then the widest KEPT line (95.5 at 2, 93.5 at 1). `reservesSpace:
//   true` and a range's lower bound pad the height to that many lines, keeping
//   the width and the last baseline (L2, L3); the upper bound caps. A finite
//   height proposal caps too: floor(height / line height), never below one
//   (L5, X9: 47.9 → 2 lines, 48 → 3, 20/5/0 → 1; infinity → unlimited),
//   combined with `lineLimit` by the smaller (X9a) and ignored by
//   `reservesSpace` (X9b). An unspecified width with `lineLimit(1)` is one
//   unwrapped line (L4). `lineLimit` is an environment value, nearest writer
//   winning (L6, L6b).
// - TRUNCATION. The kept string is CoreText's `CTLineCreateTruncatedLine` with
//   a `…` token in the same font: tail and head widths agree with it at every
//   arm (X5), the kept strings match pixel for pixel where no kerning pair
//   straddles the cut (T1 at 80, T2/X7 head at 60), trailing whitespace before
//   the token is dropped (X6: "Alpha beta…", never "Alpha beta …", which
//   fits at 79). **Middle at width 100 disagrees** (SwiftUI 97.5 wide,
//   CoreText 85.12, X5; no candidate matches, T2). With a line limit above 1
//   the dropped lines' text is truncated as ONE line after the kept lines, in
//   every mode (X8: 0 px for tail, head and middle); the token is U+2026,
//   not three full stops (T6).
// - ALIGNMENT. `multilineTextAlignment` places each line inside the text's
//   own box, whose width is the widest line (A1, A2); one line is unaffected
//   (A3); it is an environment value (A4); a wrapped paragraph's lines centre
//   in the wrap width (A5).
// - BASELINES. A `Text`'s first baseline is round(ascent) in whole points at
//   scale 2 (B1: 13, 25, 11, 18, and title2's 16), its last is the first plus
//   (lines − 1) × line height (B1b, M2, M3b). A view with no text reports its
//   height (B1f, X3e, X3h, X3j). Frame and padding move a child's baseline
//   (B1i, B1j); overlay and background keep the primary's (B1l, X3g, X3h);
//   offset does not move it (X3k). A stack's or a ZStack's first baseline is
//   the SMALLEST of its children's that have one, and its last the LARGEST,
//   at their placed offsets (B1g, B1h, X3a, X3c, X3d, B1k); a child with no
//   text is skipped (B1p). `HStack(alignment: .firstTextBaseline)` aligns each
//   child's baseline, a text-less child's bottom, and is as tall as the
//   largest part above plus the largest part below (B2: 44, offsets 12/0/12/15;
//   last: 34, offsets 16/4/0/19). A GridRow's baseline alignment keeps the
//   row's ordinary height and lets cells overflow it (X11: the 26 pt cell at
//   y −12), a shape B2's rule does not produce.
// - SPACING. Between two `Text`s in a `VStack` the default spacing is 0 (S1,
//   S1d, X4); between a `Text` and a colour block it is font-derived and
//   fractional (8.151 below 13 pt text, 4.742 above it, 15.802/8.984 at 26 pt,
//   13.516 below Noto Sans 17); a padding or a frame around the text restores
//   8 (X4). Horizontally it is 8 (S2, X4).
// - FOREGROUND. `.foregroundStyle`/`.foregroundColor` on a container reach a
//   `Text` (C2, C3); a `Text`'s own wins (C4, C5); the nearest writer wins
//   (C6); `Text.foregroundColor(nil)` is the default colour, not the inherited
//   one (C7); `.secondary` is a hierarchical grey (C8); a shape's fill reads
//   the same value (C9, plan task 11 part 2's).

import AppKit
import CoreText
import SwiftUI

// MARK: - instruments

nonisolated(unsafe) var log: [String: String] = [:]

/// Wraps ONE child and records what it answers `proposal` with: its size and
/// its first/last text baselines (`dimensions(in:)`), under `key`.
struct Measure: Layout {
    let key: String
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(proposal)
        let d = subviews[0].dimensions(in: proposal)
        log[key] = "size=\(fmt(s.width))x\(fmt(s.height)) first=\(fmt(d[.firstTextBaseline])) last=\(fmt(d[.lastTextBaseline]))"
        return s
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

/// Records where its one child is placed (the bounds the parent hands it).
struct Where: Layout {
    let key: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log[key] = "minX=\(fmt(bounds.minX)) minY=\(fmt(bounds.minY)) w=\(fmt(bounds.width)) h=\(fmt(bounds.height))"
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

func fmt(_ v: CGFloat) -> String {
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(Double(r))
}

@MainActor
func measure(_ key: String, scale: CGFloat = 2, _ view: some View) -> String {
    measure(key, .unspecified, scale: scale, view)
}

@MainActor
func measure(_ key: String, _ proposal: ProposedViewSize, scale: CGFloat = 2,
             _ view: some View) -> String {
    log[key] = nil
    let host = NSHostingView(rootView: Measure(key: key, proposal: proposal) { view }
        .environment(\.displayScale, scale))
    _ = host.fittingSize
    return log[key] ?? "not measured"
}

/// Renders at scale 2 on white; RGBA bytes plus the size in device pixels.
@MainActor
func bitmap(_ view: some View) -> (bytes: [UInt8], w: Int, h: Int) {
    let r = ImageRenderer(content: view.background(Color.white))
    r.scale = 2
    guard let cg = r.cgImage else { return ([], 0, 0) }
    let w = cg.width, h = cg.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (bytes, w, h)
}

/// Ink (non-white) extent per horizontal band of `bandHeight` device pixels.
func inkBands(_ b: (bytes: [UInt8], w: Int, h: Int), bandHeight: Int) -> [String] {
    var out: [String] = []
    var y0 = 0
    while y0 < b.h {
        var minX = Int.max, maxX = -1
        for y in y0..<min(y0 + bandHeight, b.h) {
            for x in 0..<b.w where b.bytes[(y * b.w + x) * 4] < 200 {
                minX = min(minX, x); maxX = max(maxX, x)
            }
        }
        out.append(maxX < 0 ? "-" : "\(minX)…\(maxX)")
        y0 += bandHeight
    }
    return out
}

/// The dominant ink colour (the darkest pixel's RGB).
func inkColour(_ b: (bytes: [UInt8], w: Int, h: Int)) -> String {
    var best = (sum: 766, r: 0, g: 0, bl: 0)
    for i in stride(from: 0, to: b.bytes.count, by: 4) {
        let s = Int(b.bytes[i]) + Int(b.bytes[i + 1]) + Int(b.bytes[i + 2])
        if s < best.sum { best = (s, Int(b.bytes[i]), Int(b.bytes[i + 1]), Int(b.bytes[i + 2])) }
    }
    return "rgb(\(best.r),\(best.g),\(best.bl))"
}

func differing(_ a: (bytes: [UInt8], w: Int, h: Int), _ b: (bytes: [UInt8], w: Int, h: Int)) -> Int {
    guard a.w == b.w, a.h == b.h else { return Int.max }
    var n = 0
    for i in stride(from: 0, to: a.bytes.count, by: 4) where a.bytes[i] != b.bytes[i]
        || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] { n += 1 }
    return n
}

/// A `Text` drawn in a fixed top-leading canvas, so two renders compare
/// pixel for pixel.
@MainActor
func canvas(_ view: some View, width: CGFloat = 260, height: CGFloat = 70) -> some View {
    view.frame(width: width, height: height, alignment: .topLeading)
}

/// Which candidate string the truncated render equals, pixel for pixel.
@MainActor
func identify(_ target: some View, candidates: [String], font: Font, width: CGFloat = 260,
              height: CGFloat = 70) -> String {
    let t = bitmap(canvas(target, width: width, height: height))
    var best = (n: Int.max, s: "")
    for c in candidates {
        let n = differing(t, bitmap(canvas(Text(c).font(font).fixedSize(), width: width, height: height)))
        if n < best.n { best = (n, c) }
        if n == 0 { return "== \"\(c)\"" }
    }
    return "no exact match; nearest \"\(best.s)\" (\(best.n) px differ)"
}

/// CoreText's own width of `s` in `font` on one line.
func ctWidth(_ s: String, _ font: CTFont) -> Double {
    let a = NSAttributedString(string: s, attributes: [.font: font])
    return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(a), nil, nil, nil)
}

/// CoreText's truncated line: its width, and which prefix/suffix of `s` it
/// keeps, read by matching the truncated width against each candidate's own.
func ctTruncated(_ s: String, _ font: CTFont, width: Double, type: CTLineTruncationType) -> String {
    let a = NSAttributedString(string: s, attributes: [.font: font])
    let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: [.font: font]))
    guard let t = CTLineCreateTruncatedLine(CTLineCreateWithAttributedString(a), width, type, token) else {
        return "nil"
    }
    let w = CTLineGetTypographicBounds(t, nil, nil, nil)
    var glyphs = 0
    for run in CTLineGetGlyphRuns(t) as! [CTRun] { glyphs += CTRunGetGlyphCount(run) }
    return "ctWidth=\(fmt(w)) glyphs=\(glyphs)"
}

/// CoreText's truncated line, read as a string: the kept characters of `s`
/// (by each run's string indices) with the token spelled `…` where its run
/// sits. The token carries a marker attribute, so its run is told apart.
func ctKept(_ s: String, _ font: CTFont, width: Double, type: CTLineTruncationType) -> String {
    let a = NSAttributedString(string: s, attributes: [.font: font])
    let marker = NSAttributedString.Key("probeToken")
    let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}",
                                                                    attributes: [.font: font, marker: true]))
    guard let t = CTLineCreateTruncatedLine(CTLineCreateWithAttributedString(a), width, type, token) else { return "nil" }
    let utf16 = Array(s.utf16)
    var out = ""
    for run in CTLineGetGlyphRuns(t) as! [CTRun] {
        let attrs = CTRunGetAttributes(run) as NSDictionary
        if attrs[marker] != nil { out += "\u{2026}"; continue }
        let r = CTRunGetStringRange(run)
        out += String(utf16CodeUnits: Array(utf16[r.location..<(r.location + r.length)]), count: r.length)
    }
    return out
}

func tailCandidates(_ s: String) -> [String] {
    (0...s.count).map { String(s.prefix($0)) + "\u{2026}" } + [s]
}
func headCandidates(_ s: String) -> [String] {
    (0...s.count).map { "\u{2026}" + String(s.suffix($0)) } + [s]
}
func middleCandidates(_ s: String) -> [String] {
    var out: [String] = []
    for a in 0...s.count { for b in 0...(s.count - a) { out.append(String(s.prefix(a)) + "\u{2026}" + String(s.suffix(b))) } }
    return out
}

let systemFont13 = NSFont.systemFont(ofSize: 13) as CTFont

// MARK: - probe

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let noto = URL(fileURLWithPath: "Tests/Fonts/NotoSans-Regular.ttf")
    let registered = CTFontManagerRegisterFontsForURL(noto as CFURL, .process, nil)
    print("setup: Noto Sans registered=\(registered)")

    // ---- G0 controls
    print("--- G0 controls")
    print("  G0a Text(\"Hello, world\"): \(measure("G0a", Text("Hello, world")))")
    print("  G0b .font(.system(size: 26)): \(measure("G0b", Text("Hello, world").font(.system(size: 26))))")
    print("  G0c CT width of \"Hello, world\" in systemFont(13): \(fmt(ctWidth("Hello, world", systemFont13))) "
        + "ascent=\(fmt(CTFontGetAscent(systemFont13))) descent=\(fmt(CTFontGetDescent(systemFont13))) "
        + "leading=\(fmt(CTFontGetLeading(systemFont13)))")

    // ---- F1 text styles
    print("--- F1 text styles (\"Hello, world 0123\")")
    let styles: [(String, Font, NSFont.TextStyle)] = [
        ("largeTitle", .largeTitle, .largeTitle), ("title", .title, .title1), ("title2", .title2, .title2),
        ("title3", .title3, .title3), ("headline", .headline, .headline), ("subheadline", .subheadline, .subheadline),
        ("body", .body, .body), ("callout", .callout, .callout), ("footnote", .footnote, .footnote),
        ("caption", .caption, .caption1), ("caption2", .caption2, .caption2),
    ]
    let sample = "Hello, world 0123"
    for (name, font, ns) in styles {
        let pref = NSFont.preferredFont(forTextStyle: ns)
        let traits = pref.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? NSNumber)?.doubleValue ?? .nan
        let target = Text(sample).font(font).fixedSize()
        let eqPreferred = differing(bitmap(canvas(target)),
                                    bitmap(canvas(Text(sample).font(Font(pref as CTFont)).fixedSize())))
        var systemMatch = "none"
        for w: Font.Weight in [.regular, .medium, .semibold, .bold] {
            if differing(bitmap(canvas(target)),
                         bitmap(canvas(Text(sample).font(.system(size: pref.pointSize, weight: w)).fixedSize()))) == 0 {
                systemMatch = ".system(size: \(fmt(pref.pointSize)), weight: \(w))"
                break
            }
        }
        print("  F1 \(name): \(measure("F1\(name)", Text(sample).font(font))) preferredFont=\(fmt(pref.pointSize))pt "
            + "weightTrait=\(fmt(weight)) differsFromFont(preferredCTFont)=\(eqPreferred)px equals=\(systemMatch)")
    }

    // ---- F2 weights
    print("--- F2 weights (\"Hello, world\" at 13)")
    let weights: [(String, Font.Weight, NSFont.Weight)] = [
        ("ultraLight", .ultraLight, .ultraLight), ("thin", .thin, .thin), ("light", .light, .light),
        ("regular", .regular, .regular), ("medium", .medium, .medium), ("semibold", .semibold, .semibold),
        ("bold", .bold, .bold), ("heavy", .heavy, .heavy), ("black", .black, .black),
    ]
    for (name, w, nsw) in weights {
        let t = Text("Hello, world").font(.system(size: 13, weight: w)).fixedSize()
        let ns = NSFont.systemFont(ofSize: 13, weight: nsw)
        let d = differing(bitmap(canvas(t)), bitmap(canvas(Text("Hello, world").font(Font(ns as CTFont)).fixedSize())))
        print("  F2 \(name): \(measure("F2\(name)", t)) ctWidth(NSFont.systemFont(13, weight))=\(fmt(ctWidth("Hello, world", ns as CTFont))) "
            + "differsFromFont(NSFont systemFont weight)=\(d)px")
    }
    let boldRef = bitmap(canvas(Text("Hello, world").font(.system(size: 13, weight: .bold)).fixedSize()))
    print("  F2b Text.bold() vs .system(13, .bold): \(differing(bitmap(canvas(Text("Hello, world").bold().fixedSize())), boldRef))px")
    print("  F2c .fontWeight(.bold) vs .system(13, .bold): \(differing(bitmap(canvas(Text("Hello, world").fontWeight(.bold).fixedSize())), boldRef))px")
    print("  F2d VStack{Text}.bold() (View modifier) vs .system(13, .bold): \(differing(bitmap(canvas(VStack { Text("Hello, world") }.bold().fixedSize())), boldRef))px")
    let heavyRef = bitmap(canvas(Text(sample).font(.system(size: 13, weight: .heavy)).fixedSize()))
    let headlineBold = bitmap(canvas(Text(sample).font(.headline).bold().fixedSize()))
    print("  F2e .font(.headline).bold() vs .system(13, .heavy): \(differing(headlineBold, heavyRef))px; vs .system(13, .bold): "
        + "\(differing(headlineBold, bitmap(canvas(Text(sample).font(.system(size: 13, weight: .bold)).fixedSize()))))px")
    print("  F2f .font(.body).fontWeight(.light) vs .system(13, .light): "
        + "\(differing(bitmap(canvas(Text(sample).font(.body).fontWeight(.light).fixedSize())), bitmap(canvas(Text(sample).font(.system(size: 13, weight: .light)).fixedSize()))))px")
    let customBold = bitmap(canvas(Text(sample).font(.custom("Helvetica Neue", size: 15)).bold().fixedSize()))
    let hnBold = NSFont(name: "HelveticaNeue-Bold", size: 15)!
    print("  F2g .custom(\"Helvetica Neue\", 15).bold() vs Font(HelveticaNeue-Bold 15): "
        + "\(differing(customBold, bitmap(canvas(Text(sample).font(Font(hnBold as CTFont)).fixedSize()))))px; "
        + "vs unbolded: \(differing(customBold, bitmap(canvas(Text(sample).font(.custom("Helvetica Neue", size: 15)).fixedSize()))))px")
    let notoBold = bitmap(canvas(Text(sample).font(.custom("Noto Sans", size: 15)).bold().fixedSize()))
    let notoPlain = bitmap(canvas(Text(sample).font(.custom("Noto Sans", size: 15)).fixedSize()))
    print("  F2h .custom(\"Noto Sans\", 15).bold() (only Regular registered) vs unbolded: \(differing(notoBold, notoPlain))px "
        + "\(measure("F2h-bold", Text(sample).font(.custom("Noto Sans", size: 15)).bold())) vs "
        + "\(measure("F2h-plain", Text(sample).font(.custom("Noto Sans", size: 15))))")

    // ---- F3 design, F4 italic
    print("--- F3 design, F4 italic")
    for (name, d, nsd) in [("serif", Font.Design.serif, NSFontDescriptor.SystemDesign.serif),
                           ("rounded", .rounded, .rounded), ("monospaced", .monospaced, .monospaced)] {
        let t = Text(sample).font(.system(size: 13, design: d)).fixedSize()
        let desc = NSFont.systemFont(ofSize: 13).fontDescriptor.withDesign(nsd)!
        let ns = NSFont(descriptor: desc, size: 13)!
        print("  F3 \(name): \(measure("F3\(name)", t)) resolvedName=\(ns.fontName) "
            + "differsFromFont(designDescriptor)=\(differing(bitmap(canvas(t)), bitmap(canvas(Text(sample).font(Font(ns as CTFont)).fixedSize()))))px")
    }
    do {
        let t = Text(sample).italic().fixedSize()
        let ct = CTFontCreateCopyWithSymbolicTraits(systemFont13, 0, nil, .traitItalic, .traitItalic)!
        print("  F4 Text.italic(): \(measure("F4", t)) italicName=\(CTFontCopyPostScriptName(ct)) "
            + "differsFromFont(symbolicItalic)=\(differing(bitmap(canvas(t)), bitmap(canvas(Text(sample).font(Font(ct)).fixedSize()))))px "
            + "differsFromUpright=\(differing(bitmap(canvas(t)), bitmap(canvas(Text(sample).fixedSize()))))px")
        let ni = bitmap(canvas(Text(sample).font(.custom("Noto Sans", size: 15)).italic().fixedSize()))
        print("  F4b .custom(\"Noto Sans\", 15).italic() (no italic face registered) vs upright: \(differing(ni, notoPlain))px")
    }

    // ---- F5 custom
    print("--- F5 custom")
    for (label, font, ct) in [
        ("custom Helvetica 17", Font.custom("Helvetica", size: 17), CTFontCreateWithName("Helvetica" as CFString, 17, nil)),
        ("custom Noto Sans 17", Font.custom("Noto Sans", size: 17), CTFontCreateWithName("Noto Sans" as CFString, 17, nil)),
        ("custom NoSuchFont 17", Font.custom("NoSuchFont", size: 17), CTFontCreateWithName("NoSuchFont" as CFString, 17, nil)),
    ] {
        let t = Text(sample).font(font).fixedSize()
        print("  F5 \(label): \(measure("F5\(label)", t)) ctWidth=\(fmt(ctWidth(sample, ct))) ctName=\(CTFontCopyPostScriptName(ct)) "
            + "differsFromFont(CTFontCreateWithName)=\(differing(bitmap(canvas(t)), bitmap(canvas(Text(sample).font(Font(ct)).fixedSize()))))px")
    }
    print("  F5b custom(Noto Sans, fixedSize: 17): \(measure("F5b", Text(sample).font(.custom("Noto Sans", fixedSize: 17))))")
    print("  F5c custom(Noto Sans, size: 17, relativeTo: .body): \(measure("F5c", Text(sample).font(.custom("Noto Sans", size: 17, relativeTo: .body))))")

    // ---- F6 inheritance
    print("--- F6 inheritance")
    print("  F6a VStack{Text}.font(.title): \(measure("F6a", VStack { Text(sample) }.font(.title)))")
    print("  F6a' Text.font(.title) alone:  \(measure("F6a'", Text(sample).font(.title)))")
    print("  F6b VStack{Text.font(.caption)}.font(.title): \(measure("F6b", VStack { Text(sample).font(.caption) }.font(.title)))")
    print("  F6b' Text.font(.caption) alone: \(measure("F6b'", Text(sample).font(.caption)))")
    print("  F6c VStack{Text.font(nil)}.font(.title): \(measure("F6c", VStack { Text(sample).font(nil) }.font(.title)))")
    print("  F6d VStack{Text.font(.body)}.fontWeight(.bold): \(measure("F6d", VStack { Text(sample).font(.body) }.fontWeight(.bold)))")
    print("  F6d' Text.font(.system(13, .bold)) alone: \(measure("F6d'", Text(sample).font(.system(size: 13, weight: .bold))))")
    print("  F6e VStack{Text}.font(.title).font(.caption) (outer written last): \(measure("F6e", VStack { Text(sample) }.font(.title).font(.caption)))")

    // ---- F7 dynamic type
    print("--- F7 dynamicTypeSize (macOS)")
    for (label, dts) in [("xSmall", DynamicTypeSize.xSmall), ("large", .large), ("xxxLarge", .xxxLarge), ("accessibility5", .accessibility5)] {
        print("  F7 \(label): body=\(measure("F7b\(label)", Text(sample).font(.body).dynamicTypeSize(dts))) "
            + "title=\(measure("F7t\(label)", Text(sample).font(.title).dynamicTypeSize(dts))) "
            + "default=\(measure("F7d\(label)", Text(sample).dynamicTypeSize(dts))) "
            + "customRelative=\(measure("F7c\(label)", Text(sample).font(.custom("Noto Sans", size: 17, relativeTo: .body)).dynamicTypeSize(dts))) "
            + "system13=\(measure("F7s\(label)", Text(sample).font(.system(size: 13)).dynamicTypeSize(dts)))")
    }

    // ---- F8 controlSize and the default font
    print("--- F8 controlSize")
    for (label, cs) in [("mini", ControlSize.mini), ("small", .small), ("regular", .regular), ("large", .large), ("extraLarge", .extraLarge)] {
        let t = Text(sample).fixedSize().controlSize(cs)
        var eq = "none"
        for s in stride(from: 8.0, through: 14.0, by: 0.5) {
            if differing(bitmap(canvas(t)), bitmap(canvas(Text(sample).font(.system(size: s)).fixedSize()))) == 0 {
                eq = ".system(size: \(fmt(s)))"; break
            }
        }
        print("  F8 \(label): default=\(measure("F8d\(label)", Text(sample).controlSize(cs))) equals=\(eq) "
            + "body=\(measure("F8b\(label)", Text(sample).font(.body).controlSize(cs))) "
            + "caption=\(measure("F8c\(label)", Text(sample).font(.caption).controlSize(cs))) "
            + "TextField=\(measure("F8f\(label)", TextField("Name", text: .constant("Hello")).controlSize(cs))) "
            + "TextField.font(.system(20))=\(measure("F8g\(label)", TextField("Name", text: .constant("Hello")).font(.system(size: 20)).controlSize(cs)))")
    }
    print("  F8h default font under .controlSize(.small) inside .font(.title): \(measure("F8h", VStack { Text(sample) }.controlSize(.small).font(.title)))")

    // ---- M metrics and the integer answer (divergence 60)
    print("--- M metrics")
    for (s, size) in [("Hello, world", 13.0), ("iiii", 13.0), ("W", 13.0), ("The quick brown fox", 17.5), ("Hello, world", 11.0)] {
        let ct = NSFont.systemFont(ofSize: size) as CTFont
        let t = Text(s).font(.system(size: size))
        print("  M1 \"\(s)\" @\(fmt(size)): ctWidth=\(fmt(ctWidth(s, ct))) ascent=\(fmt(CTFontGetAscent(ct))) "
            + "descent=\(fmt(CTFontGetDescent(ct))) leading=\(fmt(CTFontGetLeading(ct))) "
            + "scale1=\(measure("M1a\(s)\(size)", scale: 1, t)) scale2=\(measure("M1b\(s)\(size)", scale: 2, t)) "
            + "scale3=\(measure("M1c\(s)\(size)", scale: 3, t))")
    }
    let para = "The quick brown fox jumps over the lazy dog and keeps on running far away."
    for w: CGFloat in [100, 150, 37] {
        print("  M2 paragraph at width \(fmt(w)): \(measure("M2\(w)", ProposedViewSize(width: w, height: nil), Text(para)))")
    }
    print("  M3 \"A\\nB\\nC\": \(measure("M3", Text("A\nB\nC")))")
    print("  M3b \"A\\nB\\nC\" Noto 17: \(measure("M3b", Text("A\nB\nC").font(.custom("Noto Sans", size: 17)))) "
        + "ctAscent=\(fmt(CTFontGetAscent(CTFontCreateWithName("Noto Sans" as CFString, 17, nil)))) "
        + "ctDescent=\(fmt(CTFontGetDescent(CTFontCreateWithName("Noto Sans" as CFString, 17, nil)))) "
        + "ctLeading=\(fmt(CTFontGetLeading(CTFontCreateWithName("Noto Sans" as CFString, 17, nil))))")
    print("  M4 \"A\\nB\" .lineSpacing(4): \(measure("M4", Text("A\nB").lineSpacing(4)))")

    // ---- L line limit
    print("--- L lineLimit (paragraph, width 100)")
    let p100 = ProposedViewSize(width: 100, height: nil)
    print("  L1 nil: \(measure("L1n", p100, Text(para).lineLimit(nil)))")
    for n in [0, 1, 2, 3, 10] {
        print("  L1 \(n): \(measure("L1\(n)", p100, Text(para).lineLimit(n)))")
    }
    print("  L2 \"Hi\" lineLimit(3, reservesSpace: true): \(measure("L2a", p100, Text("Hi").lineLimit(3, reservesSpace: true)))")
    print("  L2 \"Hi\" lineLimit(3, reservesSpace: false): \(measure("L2b", p100, Text("Hi").lineLimit(3, reservesSpace: false)))")
    print("  L2 paragraph lineLimit(2, reservesSpace: true): \(measure("L2c", p100, Text(para).lineLimit(2, reservesSpace: true)))")
    print("  L2 \"Hi\" lineLimit(3, reservesSpace: true), unspecified: \(measure("L2d", Text("Hi").lineLimit(3, reservesSpace: true)))")
    print("  L3 \"Hi\" lineLimit(2...3): \(measure("L3a", p100, Text("Hi").lineLimit(2...3)))")
    print("  L3 paragraph lineLimit(2...3): \(measure("L3b", p100, Text(para).lineLimit(2...3)))")
    print("  L3 paragraph lineLimit(...2): \(measure("L3c", p100, Text(para).lineLimit(...2)))")
    print("  L3 \"Hi\" lineLimit(3...): \(measure("L3d", p100, Text("Hi").lineLimit(3...)))")
    print("  L4 paragraph lineLimit(1), unspecified width: \(measure("L4", Text(para).lineLimit(1)))")
    print("  L5 paragraph, proposal 100x20 (no lineLimit): \(measure("L5a", ProposedViewSize(width: 100, height: 20), Text(para)))")
    print("  L5 paragraph, proposal 100x40 (no lineLimit): \(measure("L5b", ProposedViewSize(width: 100, height: 40), Text(para)))")
    print("  L5 paragraph, proposal 100x5 (no lineLimit): \(measure("L5c", ProposedViewSize(width: 100, height: 5), Text(para)))")
    print("  L5 paragraph, proposal 100x0 (no lineLimit): \(measure("L5d", ProposedViewSize(width: 100, height: 0), Text(para)))")
    print("  L6 VStack{Text}.lineLimit(1) (environment), width 100: \(measure("L6", p100, VStack { Text(para) }.lineLimit(1)))")
    print("  L6b VStack{Text.lineLimit(3)}.lineLimit(1): \(measure("L6b", p100, VStack { Text(para).lineLimit(3) }.lineLimit(1)))")

    // ---- T truncation (rendered, identified pixel for pixel)
    print("--- T truncation (identified by rendering each candidate)")
    let word = "Hello, wonderful world"
    for w: CGFloat in [60, 80, 100, 130] {
        let t = Text(word).lineLimit(1).frame(width: w, alignment: .leading)
        print("  T1 tail width \(fmt(w)): \(measure("T1\(w)", ProposedViewSize(width: w, height: nil), Text(word).lineLimit(1))) "
            + "drawn \(identify(t, candidates: tailCandidates(word), font: .body)) "
            + "CTLineCreateTruncatedLine(.end): \(ctTruncated(word, systemFont13, width: Double(w), type: .end))")
    }
    for w: CGFloat in [60, 100] {
        let h = Text(word).lineLimit(1).truncationMode(.head).frame(width: w, alignment: .leading)
        print("  T2 head width \(fmt(w)): drawn \(identify(h, candidates: headCandidates(word), font: .body)) "
            + "CT(.start): \(ctTruncated(word, systemFont13, width: Double(w), type: .start))")
        let m = Text(word).lineLimit(1).truncationMode(.middle).frame(width: w, alignment: .leading)
        print("  T2 middle width \(fmt(w)): drawn \(identify(m, candidates: middleCandidates(word), font: .body)) "
            + "CT(.middle): \(ctTruncated(word, systemFont13, width: Double(w), type: .middle))")
    }
    let spaced = "Alpha beta gamma delta"
    for w: CGFloat in [70, 75, 80] {
        let t = Text(spaced).lineLimit(1).frame(width: w, alignment: .leading)
        print("  T3 \"\(spaced)\" tail width \(fmt(w)): drawn \(identify(t, candidates: tailCandidates(spaced), font: .body)) "
            + "CT(.end): \(ctTruncated(spaced, systemFont13, width: Double(w), type: .end))")
    }
    // Truncation from a height proposal (no lineLimit): one line fits 100x20.
    do {
        let t = Text(word + " again and again").frame(width: 100, height: 20, alignment: .topLeading)
        print("  T4 height-driven, frame 100x20: drawn \(identify(t, candidates: tailCandidates(word + " again and again"), font: .body))")
    }
    // Multi-line: lineLimit(2) at 100 — is the last line tail-truncated?
    do {
        let s = "Alpha beta gamma delta epsilon zeta eta theta"
        let t = Text(s).lineLimit(2).frame(width: 100, alignment: .leading)
        var cands: [String] = []
        for k in 0...s.count { cands.append(String(s.prefix(k)) + "\u{2026}") }
        print("  T5 lineLimit(2) width 100: \(measure("T5", p100, Text(s).lineLimit(2))) "
            + "drawn \(identify(t, candidates: cands.map { $0 }, font: .body, width: 100)) "
            + "(candidates rendered wrapped at 100: prefix+ellipsis)")
        // Candidate rendering at the same width: wrapped, not fixedSize.
        let target = bitmap(canvas(t, width: 100))
        var found = "no match"
        for c in cands where differing(target, bitmap(canvas(Text(c).frame(width: 100, alignment: .leading), width: 100))) == 0 {
            found = "== \"\(c)\" wrapped at 100"; break
        }
        print("  T5b lineLimit(2) width 100, candidates wrapped at 100: \(found)")
        let mid = Text(s).lineLimit(2).truncationMode(.middle).frame(width: 100, alignment: .leading)
        print("  T5c lineLimit(2).truncationMode(.middle): differs from tail by "
            + "\(differing(bitmap(canvas(mid, width: 100)), target))px")
    }
    do {
        let t = Text(word).lineLimit(1).frame(width: 80, alignment: .leading)
        let dots = identify(t, candidates: (0...word.count).map { String(word.prefix($0)) + "..." }, font: .body)
        print("  T6 three full stops as the token instead of U+2026: \(dots)")
    }

    // ---- A multiline alignment
    print("--- A multilineTextAlignment (\"Short\\nA much longer line\", ink per 32-px band at scale 2)")
    let two = "Short\nA much longer line"
    for (label, a) in [("leading", TextAlignment.leading), ("center", .center), ("trailing", .trailing)] {
        let t = Text(two).multilineTextAlignment(a).fixedSize()
        print("  A1 \(label): \(measure("A1\(label)", Text(two).multilineTextAlignment(a))) ink=\(inkBands(bitmap(canvas(t)), bandHeight: 32).prefix(2))")
    }
    do {
        let t = Text(two).multilineTextAlignment(.center).frame(width: 200, alignment: .leading)
        print("  A2 center inside frame(width: 200, alignment: .leading): ink=\(inkBands(bitmap(canvas(t)), bandHeight: 32).prefix(2))")
        let s = Text("One line").multilineTextAlignment(.trailing).frame(width: 200, alignment: .leading)
        print("  A3 one line, trailing, inside frame(width: 200, alignment: .leading): ink=\(inkBands(bitmap(canvas(s)), bandHeight: 32).prefix(1))")
        let e = VStack { Text(two) }.multilineTextAlignment(.trailing).fixedSize()
        print("  A4 VStack{Text}.multilineTextAlignment(.trailing): ink=\(inkBands(bitmap(canvas(e)), bandHeight: 32).prefix(2))")
        let w = Text(para).multilineTextAlignment(.center).frame(width: 100, alignment: .leading)
        print("  A5 paragraph center wrapped at 100: \(measure("A5", p100, Text(para).multilineTextAlignment(.center))) ink=\(inkBands(bitmap(canvas(w, width: 100, height: 100)), bandHeight: 32).prefix(3))")
        let tt = Text(word).lineLimit(1).multilineTextAlignment(.trailing).frame(width: 80, alignment: .leading)
        print("  A6 truncated one line, trailing, width 80: ink=\(inkBands(bitmap(canvas(tt)), bandHeight: 32).prefix(1))")
    }

    // ---- B baselines
    print("--- B baselines")
    print("  B1 Text(\"Hg\") 13: \(measure("B1a", Text("Hg")))")
    print("  B1 Text(\"Hg\\nHg\") 13: \(measure("B1b", Text("Hg\nHg")))")
    print("  B1 Text(\"Hg\") 26: \(measure("B1c", Text("Hg").font(.system(size: 26)))) ctAscent26=\(fmt(CTFontGetAscent(NSFont.systemFont(ofSize: 26) as CTFont)))")
    print("  B1 Text(\"Hg\") Noto 17: \(measure("B1d", Text("Hg").font(.custom("Noto Sans", size: 17))))")
    print("  B1 Text(\"Hg\") 11: \(measure("B1e", Text("Hg").font(.system(size: 11)))) ctAscent11=\(fmt(CTFontGetAscent(NSFont.systemFont(ofSize: 11) as CTFont)))")
    print("  B1 Color 20x30: \(measure("B1f", Color.red.frame(width: 20, height: 30)))")
    print("  B1 VStack(spacing: 0){Text 13; Text 26}: \(measure("B1g", VStack(spacing: 0) { Text("Hg"); Text("Hg").font(.system(size: 26)) }))")
    print("  B1 HStack(spacing: 0){Text 13; Text 26} (center): \(measure("B1h", HStack(spacing: 0) { Text("Hg"); Text("Hg").font(.system(size: 26)) }))")
    print("  B1 Text.padding(8): \(measure("B1i", Text("Hg").padding(8)))")
    print("  B1 Text.frame(height: 50): \(measure("B1j", Text("Hg").frame(height: 50)))")
    print("  B1 ZStack{Color 40x40; Text}: \(measure("B1k", ZStack { Color.red.frame(width: 40, height: 40); Text("Hg") }))")
    print("  B1 Text.background(Color): \(measure("B1l", Text("Hg").background(Color.red)))")
    print("  B1 HStack{Color 10x10}: \(measure("B1m", HStack { Color.red.frame(width: 10, height: 10) }))")
    print("  B1 Text.lineLimit(1) width 30 (truncated): \(measure("B1n", ProposedViewSize(width: 30, height: nil), Text("Hg Hg Hg").lineLimit(1)))")
    print("  B1 Text wrapped at 30 (\"Hg Hg Hg\"): \(measure("B1o", ProposedViewSize(width: 30, height: nil), Text("Hg Hg Hg")))")
    print("  B1 VStack{Color 10x10; Text}: \(measure("B1p", VStack(spacing: 0) { Color.red.frame(width: 10, height: 10); Text("Hg") }))")

    func stack(_ alignment: VerticalAlignment, _ tag: String) -> some View {
        HStack(alignment: alignment, spacing: 0) {
            Where(key: "\(tag)-13") { Text("Hg") }
            Where(key: "\(tag)-26") { Text("Hg").font(.system(size: 26)) }
            Where(key: "\(tag)-2line") { Text("Hg\nHg") }
            Where(key: "\(tag)-color") { Color.red.frame(width: 10, height: 10) }
        }
    }
    for (label, a) in [("firstTextBaseline", VerticalAlignment.firstTextBaseline), ("lastTextBaseline", .lastTextBaseline),
                       ("center", .center), ("top", .top)] {
        print("  B2 HStack(alignment: .\(label)): \(measure("B2\(label)", Where(key: "B2\(label)-stack") { stack(a, "B2\(label)") }))")
        _ = bitmap(Where(key: "B2\(label)-stack") { stack(a, "B2\(label)") })
        for k in log.keys.sorted() where k.hasPrefix("B2\(label)-") { print("    \(k): \(log[k]!)") }
    }

    // ---- S spacing between texts (divergence 51)
    print("--- S default spacing between Text views")
    print("  S1 VStack{Text; Text}: \(measure("S1", VStack { Text("Hg"); Text("Hg") }))")
    print("  S1b VStack{Color 10x10; Color 10x10} (control): \(measure("S1b", VStack { Color.red.frame(width: 10, height: 10); Color.red.frame(width: 10, height: 10) }))")
    print("  S1c VStack{Text; Color 10x10}: \(measure("S1c", VStack { Text("Hg"); Color.red.frame(width: 10, height: 10) }))")
    print("  S1d VStack{Text 26; Text 26}: \(measure("S1d", VStack { Text("Hg").font(.system(size: 26)); Text("Hg").font(.system(size: 26)) }))")
    print("  S2 HStack{Text; Text}: \(measure("S2", HStack { Text("Hg"); Text("Hg") }))")
    print("  S2b HStack{Color; Color} (control): \(measure("S2b", HStack { Color.red.frame(width: 10, height: 10); Color.red.frame(width: 10, height: 10) }))")

    // ---- C foreground style
    print("--- C foreground (darkest ink pixel)")
    print("  C0 default Text: \(inkColour(bitmap(canvas(Text("Hg").font(.system(size: 30)).fixedSize()))))")
    print("  C1 Text.foregroundStyle(.red): \(inkColour(bitmap(canvas(Text("Hg").font(.system(size: 30)).foregroundStyle(.red).fixedSize()))))")
    print("  C2 VStack{Text}.foregroundStyle(.red): \(inkColour(bitmap(canvas(VStack { Text("Hg").font(.system(size: 30)) }.foregroundStyle(.red).fixedSize()))))")
    print("  C3 VStack{Text}.foregroundColor(.red): \(inkColour(bitmap(canvas(VStack { Text("Hg").font(.system(size: 30)) }.foregroundColor(.red).fixedSize()))))")
    print("  C4 VStack{Text.foregroundColor(.blue)}.foregroundStyle(.red): \(inkColour(bitmap(canvas(VStack { Text("Hg").font(.system(size: 30)).foregroundColor(.blue) }.foregroundStyle(.red).fixedSize()))))")
    print("  C5 VStack{Text.foregroundStyle(.blue)}.foregroundColor(.red): \(inkColour(bitmap(canvas(VStack { Text("Hg").font(.system(size: 30)).foregroundStyle(.blue) }.foregroundColor(.red).fixedSize()))))")
    print("  C6 VStack{Text}.foregroundStyle(.red).foregroundStyle(.blue) (outer last): \(inkColour(bitmap(canvas(VStack { Text("Hg").font(.system(size: 30)) }.foregroundStyle(.red).foregroundStyle(.blue).fixedSize()))))")
    print("  C7 VStack{Text.foregroundColor(nil)}.foregroundStyle(.red): \(inkColour(bitmap(canvas(VStack { Text("Hg").font(.system(size: 30)).foregroundColor(nil) }.foregroundStyle(.red).fixedSize()))))")
    print("  C8 Text.foregroundStyle(.secondary): \(inkColour(bitmap(canvas(Text("Hg").font(.system(size: 30)).foregroundStyle(.secondary).fixedSize()))))")
    print("  C9 VStack{Rectangle 20x20}.foregroundStyle(.red) (shape fill, part 2's): \(inkColour(bitmap(canvas(VStack { Rectangle().frame(width: 20, height: 20) }.foregroundStyle(.red).fixedSize()))))")

    // ---- X follow-ups (added in the same session, after the first run)
    print("--- X follow-ups")
    do {
        let t = bitmap(canvas(Text(sample).bold().fixedSize()))
        var match = "none"
        for (name, w, _) in weights where differing(t, bitmap(canvas(Text(sample).font(.system(size: 13, weight: w)).fixedSize()))) == 0 {
            match = name; break
        }
        print("  X1 Text.bold() on the default font equals .system(13, weight: \(match))")
        let tb = bitmap(canvas(Text(sample).font(.system(size: 13, weight: .light)).bold().fixedSize()))
        var m2 = "none"
        for (name, w, _) in weights where differing(tb, bitmap(canvas(Text(sample).font(.system(size: 13, weight: w)).fixedSize()))) == 0 {
            m2 = name; break
        }
        print("  X1b .system(13, .light).bold() equals .system(13, weight: \(m2))")
        let fb = bitmap(canvas(Text(sample).font(.system(size: 13).bold()).fixedSize()))
        var m3 = "none"
        for (name, w, _) in weights where differing(fb, bitmap(canvas(Text(sample).font(.system(size: 13, weight: w)).fixedSize()))) == 0 {
            m3 = name; break
        }
        print("  X1c Font.system(size: 13).bold() (Font modifier) equals .system(13, weight: \(m3))")
    }
    do {
        let names = ["HelveticaNeue-UltraLight", "HelveticaNeue-Thin", "HelveticaNeue-Light", "HelveticaNeue",
                     "HelveticaNeue-Medium", "HelveticaNeue-Bold"]
        for (label, w) in [("ultraLight", Font.Weight.ultraLight), ("thin", .thin), ("light", .light), ("regular", .regular),
                           ("medium", .medium), ("semibold", .semibold), ("bold", .bold), ("heavy", .heavy), ("black", .black)] {
            let t = bitmap(canvas(Text(sample).font(.custom("Helvetica Neue", size: 15).weight(w)).fixedSize()))
            var match = "none"
            for n in names where differing(t, bitmap(canvas(Text(sample).font(Font(NSFont(name: n, size: 15)! as CTFont)).fixedSize()))) == 0 {
                match = n; break
            }
            print("  X2 .custom(\"Helvetica Neue\", 15).weight(.\(label)) draws \(match)")
        }
        let it = bitmap(canvas(Text(sample).font(.custom("Helvetica Neue", size: 15)).italic().fixedSize()))
        let hi = NSFont(name: "HelveticaNeue-Italic", size: 15)!
        print("  X2b .custom(\"Helvetica Neue\", 15).italic() vs HelveticaNeue-Italic: \(differing(it, bitmap(canvas(Text(sample).font(Font(hi as CTFont)).fixedSize()))))px")
        let bi = bitmap(canvas(Text(sample).font(.custom("HelveticaNeue-Bold", size: 15)).fixedSize()))
        print("  X2c .custom(\"HelveticaNeue-Bold\", 15) (a PostScript name) vs HelveticaNeue-Bold: \(differing(bi, bitmap(canvas(Text(sample).font(Font(NSFont(name: "HelveticaNeue-Bold", size: 15)! as CTFont)).fixedSize()))))px")
        let bl = bitmap(canvas(Text(sample).font(.custom("HelveticaNeue-Bold", size: 15).weight(.light)).fixedSize()))
        var m = "none"
        for n in names where differing(bl, bitmap(canvas(Text(sample).font(Font(NSFont(name: n, size: 15)! as CTFont)).fixedSize()))) == 0 { m = n; break }
        print("  X2d .custom(\"HelveticaNeue-Bold\", 15).weight(.light) draws \(m)")
    }
    print("  X3 HStack(spacing: 0){Text 26; Text 13} (center): \(measure("X3a", HStack(spacing: 0) { Text("Hg").font(.system(size: 26)); Text("Hg") }))")
    print("  X3 VStack(spacing: 0){Text 13; Color 10x10}: \(measure("X3b", VStack(spacing: 0) { Text("Hg"); Color.red.frame(width: 10, height: 10) }))")
    print("  X3 HStack(alignment: .bottom, spacing: 0){Text 13; Text\\nText 13}: \(measure("X3c", HStack(alignment: .bottom, spacing: 0) { Text("Hg"); Text("Hg\nHg") }))")
    print("  X3 HStack(alignment: .top, spacing: 0){Text\\nText 13; Text 13}: \(measure("X3d", HStack(alignment: .top, spacing: 0) { Text("Hg\nHg"); Text("Hg") }))")
    print("  X3 Spacer in HStack: \(measure("X3e", HStack { Spacer() }))")
    print("  X3 Text.fixedSize(): \(measure("X3f", Text("Hg").fixedSize()))")
    print("  X3 Text.overlay(Color): \(measure("X3g", Text("Hg").overlay(Color.red)))")
    print("  X3 Color.overlay(Text): \(measure("X3h", Color.red.frame(width: 30, height: 30).overlay(Text("Hg"))))")
    print("  X3 Grid{GridRow{Text}}: \(measure("X3i", Grid { GridRow { Text("Hg") } }))")
    print("  X3 ScrollView{Text}: \(measure("X3j", ProposedViewSize(width: 100, height: 100), ScrollView { Text("Hg") }))")
    print("  X3 Text.offset(y: 7): \(measure("X3k", Text("Hg").offset(y: 7)))")
    print("  X3 Text.alignmentGuide(.firstTextBaseline) { _ in 4 }: \(measure("X3l", Text("Hg").alignmentGuide(.firstTextBaseline) { _ in 4 }))")
    // spacing between a text and other views
    for (label, v) in [
        ("VStack{Text 13; Color}", AnyView(VStack { Text("Hg"); Color.red.frame(width: 10, height: 10) })),
        ("VStack{Color; Text 13}", AnyView(VStack { Color.red.frame(width: 10, height: 10); Text("Hg") })),
        ("VStack{Text 26; Color}", AnyView(VStack { Text("Hg").font(.system(size: 26)); Color.red.frame(width: 10, height: 10) })),
        ("VStack{Color; Text 26}", AnyView(VStack { Color.red.frame(width: 10, height: 10); Text("Hg").font(.system(size: 26)) })),
        ("VStack{Text 13; Text 26}", AnyView(VStack { Text("Hg"); Text("Hg").font(.system(size: 26)) })),
        ("VStack{Text Noto 17; Color}", AnyView(VStack { Text("Hg").font(.custom("Noto Sans", size: 17)); Color.red.frame(width: 10, height: 10) })),
        ("VStack{Text 13 padded 1; Color}", AnyView(VStack { Text("Hg").padding(1); Color.red.frame(width: 10, height: 10) })),
        ("VStack{Text 13 framed h20; Color}", AnyView(VStack { Text("Hg").frame(height: 20); Color.red.frame(width: 10, height: 10) })),
        ("HStack{Text 13; Color}", AnyView(HStack { Text("Hg"); Color.red.frame(width: 10, height: 10) })),
    ] {
        print("  X4 \(label): \(measure("X4\(label)", v))")
    }
    // truncation: CoreText's kept strings, and SwiftUI's width per mode
    for w: CGFloat in [60, 100] {
        for (mode, ct) in [("tail", CTLineTruncationType.end), ("head", .start), ("middle", .middle)] {
            let m: Text.TruncationMode = mode == "tail" ? .tail : mode == "head" ? .head : .middle
            print("  X5 \(mode) width \(fmt(w)): SwiftUI \(measure("X5\(mode)\(w)", ProposedViewSize(width: w, height: nil), Text(word).lineLimit(1).truncationMode(m))) "
                + "CT kept \"\(ctKept(word, systemFont13, width: Double(w), type: ct))\" \(ctTruncated(word, systemFont13, width: Double(w), type: ct))")
        }
    }
    for w in [70.0, 75, 78, 79, 80, 84] {
        print("  X6 \"\(spaced)\" tail width \(fmt(w)): CT kept \"\(ctKept(spaced, systemFont13, width: w, type: .end))\" "
            + "width(\"Alpha beta\u{2026}\")=\(fmt(ctWidth("Alpha beta\u{2026}", systemFont13))) "
            + "width(\"Alpha beta \u{2026}\")=\(fmt(ctWidth("Alpha beta \u{2026}", systemFont13))) "
            + "SwiftUI \(measure("X6\(w)", ProposedViewSize(width: w, height: nil), Text(spaced).lineLimit(1)))")
    }
    do {
        // Which string does SwiftUI draw for each mode? Compare against CoreText's own truncated
        // line drawn by SwiftUI as a plain string (the kept string, unkerned token included).
        for (mode, ct, m) in [("head", CTLineTruncationType.start, Text.TruncationMode.head),
                              ("middle", .middle, .middle), ("tail", .end, .tail)] {
            for w: CGFloat in [60, 100] {
                let kept = ctKept(word, systemFont13, width: Double(w), type: ct)
                let t = bitmap(canvas(Text(word).lineLimit(1).truncationMode(m).frame(width: w, alignment: .leading)))
                let c = bitmap(canvas(Text(kept).fixedSize()))
                print("  X7 \(mode) width \(fmt(w)): SwiftUI render vs Text(CT kept \"\(kept)\"): \(differing(t, c))px")
            }
        }
    }
    do {
        // lineLimit(2), middle/head: the second line, against CoreText truncating the rest.
        let s = "Alpha beta gamma delta epsilon zeta eta theta"
        let ctf = systemFont13
        let fs = CTFramesetterCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: ctf]))
        let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0),
                                             CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 1000), transform: nil), nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        let r1 = CTLineGetStringRange(lines[0])
        let u = Array(s.utf16)
        let line1 = String(utf16CodeUnits: Array(u[0..<r1.length]), count: r1.length)
        let rest = String(utf16CodeUnits: Array(u[r1.length...]), count: u.count - r1.length)
        print("  X8 line 1 at width 100: \"\(line1)\" rest: \"\(rest)\"")
        for (mode, ct, m) in [("tail", CTLineTruncationType.end, Text.TruncationMode.tail), ("head", .start, .head), ("middle", .middle, .middle)] {
            let kept = ctKept(rest, ctf, width: 100, type: ct)
            let target = bitmap(canvas(Text(s).lineLimit(2).truncationMode(m).frame(width: 100, alignment: .leading), width: 100))
            let cand = bitmap(canvas(Text(line1.trimmingCharacters(in: .whitespaces) + "\n" + kept).fixedSize(), width: 100))
            print("  X8 lineLimit(2) \(mode): rest truncated by CT = \"\(kept)\"; SwiftUI vs Text(line1 + \\n + that): \(differing(target, cand))px")
        }
    }
    print("  X9 paragraph lineLimit(2) at 100, height proposal 20: \(measure("X9a", ProposedViewSize(width: 100, height: 20), Text(para).lineLimit(2)))")
    print("  X9 \"Hi\" lineLimit(3, reservesSpace: true), height proposal 20: \(measure("X9b", ProposedViewSize(width: 100, height: 20), Text("Hi").lineLimit(3, reservesSpace: true)))")
    print("  X9 paragraph, proposal 100x47.9: \(measure("X9c", ProposedViewSize(width: 100, height: 47.9), Text(para)))")
    print("  X9 paragraph, proposal 100x48: \(measure("X9d", ProposedViewSize(width: 100, height: 48), Text(para)))")
    print("  X9 paragraph, proposal nil x 20: \(measure("X9e", ProposedViewSize(width: nil, height: 20), Text(para)))")
    print("  X9 paragraph, proposal 100 x infinity: \(measure("X9f", ProposedViewSize(width: 100, height: .infinity), Text(para)))")
    print("  X10 empty Text(\"\"): \(measure("X10a", Text(""))) lineLimit(2, reservesSpace: true): \(measure("X10b", Text("").lineLimit(2, reservesSpace: true)))")
    do {
        func gridRow(_ a: VerticalAlignment?, _ tag: String) -> some View {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow(alignment: a) {
                    Where(key: "\(tag)-13") { Text("Hg") }
                    Where(key: "\(tag)-26") { Text("Hg").font(.system(size: 26)) }
                    Where(key: "\(tag)-2line") { Text("Hg\nHg") }
                    Where(key: "\(tag)-color") { Color.red.frame(width: 10, height: 10) }
                }
                GridRow {
                    Where(key: "\(tag)-row2") { Color.blue.frame(width: 5, height: 5) }
                }
            }
        }
        for (label, a) in [("firstTextBaseline", VerticalAlignment.firstTextBaseline), ("lastTextBaseline", .lastTextBaseline)] {
            print("  X11 Grid, GridRow(alignment: .\(label)): \(measure("X11\(label)", Where(key: "X11\(label)-grid") { gridRow(a, "X11\(label)") }))")
            _ = bitmap(Where(key: "X11\(label)-grid") { gridRow(a, "X11\(label)") })
            for k in log.keys.sorted() where k.hasPrefix("X11\(label)-") { print("    \(k): \(log[k]!)") }
        }
        print("  X11b Grid(alignment: .leadingFirstTextBaseline) { GridRow { Text 13; Text 26 } }: \(measure("X11b", Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0) { GridRow { Text("Hg"); Text("Hg").font(.system(size: 26)) } }))")
    }
    do {
        // CoreText's symbolic bold trait, against SwiftUI's Text.bold() (X1, F2e, X1b).
        func weightOf(_ f: CTFont) -> String {
            let t = CTFontCopyTraits(f) as NSDictionary
            let w = (t[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? .nan
            return "\(CTFontCopyPostScriptName(f)) weight=\(fmt(w))"
        }
        for (label, nsw) in [("regular", NSFont.Weight.regular), ("light", .light), ("bold", .bold), ("semibold", .semibold)] {
            let base = NSFont.systemFont(ofSize: 13, weight: nsw) as CTFont
            let bolded = CTFontCreateCopyWithSymbolicTraits(base, 0, nil, .traitBold, .traitBold)
            print("  X12 CT bold trait on systemFont(13, .\(label)): \(weightOf(base)) -> \(bolded.map(weightOf) ?? "nil")")
        }
        let body = bitmap(canvas(Text(sample).bold().fixedSize()))
        let viaTrait = CTFontCreateCopyWithSymbolicTraits(systemFont13, 0, nil, .traitBold, .traitBold)!
        print("  X12b Text.bold() vs Font(CT bold trait of systemFont(13)): \(differing(body, bitmap(canvas(Text(sample).font(Font(viaTrait)).fixedSize()))))px")
    }
    do {
        // Line heights: one line and two lines, against CoreText's own sum.
        for (name, sizes) in [("system", [9.0, 10, 11, 12, 13, 14, 15, 16, 17, 20, 22, 26, 30]),
                              ("Noto Sans", [11.0, 13, 17, 26]), ("Menlo", [11.0, 13, 17, 26])] {
            for size in sizes {
                let ct = name == "system" ? NSFont.systemFont(ofSize: size) as CTFont
                    : CTFontCreateWithName(name as CFString, size, nil)
                let font: Font = name == "system" ? .system(size: size) : .custom(name, size: size)
                let sum = CTFontGetAscent(ct) + CTFontGetDescent(ct) + CTFontGetLeading(ct)
                print("  X13 \(name) \(fmt(size)): ascent+descent+leading=\(fmt(sum)) ascent=\(fmt(CTFontGetAscent(ct))) "
                    + "one line \(measure("X13a\(name)\(size)", scale: 1, Text("Hg").font(font))) "
                    + "two lines \(measure("X13b\(name)\(size)", scale: 1, Text("Hg\nHg").font(font))) "
                    + "one line at scale 2 \(measure("X13c\(name)\(size)", scale: 2, Text("Hg").font(font)))")
            }
        }
    }
    print("done")
}
