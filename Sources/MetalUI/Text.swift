import MetalUICore
import MetalUILayout
#if canImport(MetalUIText)
import MetalUIText
#endif
import MetalUITextSystem

/// The smallest width this module will ever ask the shaper to wrap at.
///
/// **Ruling TX-E, and it is a release crash rather than a note.**
/// `Shaper.shape` preconditions on `width > 0` (spec §3.4: a non-positive width
/// is an ill-formed request, not a narrower line), `precondition` is live in
/// `-O`, and **a flex item shrinking to zero main size is an ordinary layout
/// state**: §9.7 hands a `.definite(0)` available extent to any item on an
/// over-full line whose share runs out. So the clamp lives here, at the measure
/// function's boundary, where "as narrow as you can" is a real request — not in
/// the shaper, where it would silently answer a different question than the one
/// asked.
///
/// The value is arbitrary within `(0, one character wide)`: every width below
/// the narrowest glyph produces the same character-per-line answer, measured at
/// 0.001, 0.5, 1 and 5 (see ``MetalUIText/Shaper/unbreakableRuns(of:)``).
/// 0.5 is the value Task 2's positive control already uses.
let smallestWrapWidth = 0.5

/// Measures `string` the way spec §3.4's table says, for one axis' worth of
/// question at a time.
///
/// | `available.width` | wrapped at | width reported |
/// |---|---|---|
/// | `.maxContent` | nothing — one line per hard line break | the widest line |
/// | `.minContent` | the widest unbreakable run | that run's width |
/// | `.definite(w)` | `max(w, smallestWrapWidth)` | the widest resulting line |
///
/// **The max-content row said "one line" until it was measured wrong.** The
/// unwrapped shape was a single `CTLine` for the whole string, so a label with
/// a hard break (`"Ready\nSet\nGo"`) reported the **sum** of its lines — 75.004
/// where every definite width at or above 37.565 reported 37.565 — and a
/// centring `Column` placed its box on that width while `paint`, which re-wraps
/// at the measured width and lays each line from the box's left edge, drew the
/// ink about 19pt left of centre. The shaper now breaks at hard breaks with no
/// width offered (see `Shaper.shape(_:font:wrappingAt:)`), so the row now
/// gives the answer every definite width at or above the widest line gives.
/// Pinned by `aLabelWithHardBreaksMeasuresItsWidestLineAtMaxContent`.
///
/// The min-content row is the one the design spec words differently — it says
/// "typeset at a small positive width; the widest resulting line". Measured,
/// that is not the same answer, and ``MetalUIText/Shaper/unbreakableRuns(of:)``
/// carries the numbers: `CTTypesetterSuggestLineBreak` breaks *inside* a word it
/// cannot fit, so a tiny width reports the widest **character** (11.489 for the
/// sample below) where CSS's min-content — and §4.5's automatic minimum, whose
/// whole purpose here is to stop a long label being squeezed until it breaks
/// mid-word — needs the longest **run** (110.348).
///
/// `known` wins on either axis (§5.5): a `Text` with an explicit `.width(100)`
/// is typeset at 100 and reports 100 whatever the content measures. That is
/// `measureNode`'s existing contract rather than a new rule; `Text` is simply
/// the first production leaf to exercise it.
///
/// **The height is always the height of the shape the width question produced**
/// — `lines × lineHeight`, uniform in M2 because a `Text` carries one font at
/// one size (§2). `available.height` is therefore not read: a text run's height
/// is a consequence of the width it was wrapped at, so there is no separate
/// min/max-content answer in the block axis. A `known.height` still wins, since
/// the caller is then stating the box rather than asking for one.
///
/// **Two numbers that come from different shapes, on the `.minContent` branch
/// alone.** The width reported there is the unbreakable-run width — 110.348 for
/// `"a bb supercalifragilistic dd"` at 13pt — while the height is the shape at
/// that width, whose widest line is 113.928 because a *trailing space* hangs
/// past the break. Reporting 113.928 as min-content would fold a space nobody
/// sees into §4.5's floor; reporting the run width and the shape's height is
/// CSS's own split.
@MainActor
func textMeasure(_ string: String, font: FontKey, system: any TextSystem,
                 known: OptionalSizeD, available: AvailableSpace) -> SizeD {
    // The width the text is typeset at, and — on the min-content branch — the
    // width to report, which is not the same number. See the doc comment.
    let wrapWidth: Double?
    var reportedWidth: Double?

    if let knownWidth = known.width {
        wrapWidth = max(knownWidth, smallestWrapWidth)
        reportedWidth = knownWidth
    } else {
        switch available {
        case .maxContent:
            wrapWidth = nil
        case .minContent:
            // The widest unbreakable run, memoized per (string, font). `Shaper`
            // character-breaks a word it cannot fit, so `shape(wrappingAt: tiny)`
            // answers "the widest character" (11.489) where §4.5 needs "the
            // longest word" (110.348) — hence runs rather than a narrow typeset.
            let minContent = system.minContentWidth(string, font: font)
            wrapWidth = max(minContent, smallestWrapWidth)
            reportedWidth = minContent
        case .definite(let offered):
            wrapWidth = max(offered, smallestWrapWidth)
        }
    }

    let shaped = system.measure(string, font: font, wrappingAt: wrapWidth)
    return SizeD(width: reportedWidth ?? shaped.widestLine,
                 height: known.height ?? shaped.totalHeight)
}

#if canImport(MetalUIText)
/// ``textMeasure(_:font:system:known:available:)`` over a CoreText shaping
/// cache — the spelling the measurement tests use to ask the Apple path
/// directly.
@MainActor
func textMeasure(_ string: String, font: ResolvedFont, cache: ShapingCache,
                 known: OptionalSizeD, available: AvailableSpace) -> SizeD {
    cache.registerFont(font)
    return textMeasure(string, font: font.key, system: CoreTextTextSystem(cache: cache),
                       known: known, available: available)
}
#endif

/// The overload the engine's `MeasureFunction` shape calls, which takes the
/// whole `AvailableSpaceSize` and reads only its width. Separate so that the
/// function above cannot be *given* a height question it silently ignores.
@MainActor
func textMeasure(_ string: String, font: FontKey, system: any TextSystem,
                 known: OptionalSizeD, available: AvailableSpaceSize) -> SizeD {
    textMeasure(string, font: font, system: system, known: known, available: available.width)
}

/// A run of text: the framework's first leaf, and `newLeaf`'s first production
/// caller.
///
/// **What this element makes live.** `newLeaf` is the only thing that attaches a
/// `MeasureFunction`, and until this type nothing in `Sources/` called it — so
/// every production node's `tree.measure()` was `nil`, and §9.2's content branch
/// and §4.5's automatic minimum were live for *containers* and dead for
/// *leaves*. A `Text` measures.
///
/// **It draws.** ``paint(_:bounds:layout:prepaint:pass:)`` shapes the string at
/// the width layout settled on, walks each line's runs, and hands every glyph to
/// the frame's ``MetalUIText/GlyphAtlas`` — which rasterizes it once and keeps
/// the bitmap for every later frame. That is the unit joining the two halves
/// this milestone built: the shaper, the rasterizer and the packer on one side,
/// `MUIGlyph` and the glyph pipeline on the other.
///
/// **One font at one size per `Text`** (spec §2): rich text, per-run attributes
/// and per-line metrics are out of M2, which is what lets height be
/// `lines × lineHeight` with a single line height.
public struct Text: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()

    /// The string to lay out. `let`-like in practice — the measure closure
    /// captures a copy at `requestLayout`, so mutating this afterwards affects
    /// the *next* frame's element value, which is the same rebuild-per-frame
    /// model every other element follows.
    public var string: String

    /// `nil` means the platform UI font. Resolution happens in `requestLayout`
    /// and again in `paint`, both through the window's
    /// `ShapingCache.resolveFont(family:size:)`, which memoizes `FontResolver`
    /// — and `FontResolver` substitutes rather than failing, so see `FontKey`
    /// for why nothing downstream may be keyed on this name.
    public var fontFamily: String?
    /// **Must be finite and positive.** Not checked here — this is a settable
    /// property — but `FontResolver.resolve(family:size:)` traps on anything
    /// else the first frame this `Text` is laid out, because CoreText would
    /// otherwise substitute 12 or 13pt or keep a NaN.
    public var fontSize: Double

    /// The colour the glyphs are tinted with. `nil` means
    /// ``ColorToken/textPrimary``, resolved against the frame's theme like any
    /// other token — never a literal, so unthemed text cannot end up black in a
    /// dark window.
    public var foregroundColor: ColorToken?

    public init(_ string: String) {
        self.style = Style()
        self.decoration = Decoration()
        self.string = string
        self.fontFamily = nil
        self.fontSize = 13
    }

    /// The face and size this run is shaped at. `family: nil` keeps the
    /// platform UI font.
    public func font(family: String? = nil, size: Double) -> Text {
        var copy = self
        copy.fontFamily = family
        copy.fontSize = size
        return copy
    }

    /// The token the glyphs are tinted with. A semantic token rather than an
    /// `Hsla`, for §7.9's reason: a literal would paint identically in both
    /// appearances while looking exactly like a themed colour at the call site.
    public func foregroundColor(_ token: ColorToken) -> Text {
        var copy = self
        copy.foregroundColor = token
        return copy
    }

    public struct Layout {
        public var node: LayoutNodeID
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let system = pass.textSystem
        // Resolved and registered by the text system under its `Sendable`
        // key; the closures below capture the key and the system, never a
        // font or the request (`FontKey`'s rule). `paint` asks the same
        // question and gets the same key back.
        let key = system.resolveFont(family: fontFamily, size: fontSize)
        let string = self.string

        if pass.lowersToProposal {
            let node = pass.lowerLegacyLeaf(style, declared: style, site: .text) {
                pass.frame.requestNativeLeaf { proposal in
                    MainActor.assumeIsolated {
                        proposalTextMeasurement(string, font: key, system: system, proposal: proposal)
                    }
                }
            }
            return (node, Layout(node: node))
        }
        let node = pass.frame.requestLeaf(style: style) { known, available in
            MainActor.assumeIsolated {
                textMeasure(string, font: key, system: system, known: known, available: available)
            }
        }
        return (node, Layout(node: node))
    }

    /// Registers a click target when — and only when — `onClick(_:)` was
    /// called. A `Text` with no handler registers nothing, exactly as a `Box`
    /// with none does; `prepaint` was empty before this and is still empty for
    /// every `Text` in the demo.
    ///
    /// The same call registers focus and emits a declared `handlers.axNode`
    /// (`Frame.registerHandlers` holds all three gates). **The AX half used to
    /// be missing here**: only `Box.prepaint` emitted, so a node declared on a
    /// `Text` was dropped silently. The `text` arm of
    /// `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` pins it.
    ///
    /// **The string reaches an accessibility client** (ruling AB-F): while a
    /// client is active the frame records it beside the handlers, and
    /// `AccessibilityTreeBuilder` publishes it as the text's value, or as a
    /// button's label. Nothing derives an `AXNode` from it, so `Frame.axNodes`
    /// and `StateTable` are the same whether or not a client is active (AB-U).
    /// **An empty string is no text** (arms E0–E2): SwiftUI omits `Text("")`
    /// and publishes `Text(" ")`.
    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {
        // Through `registerAndScope` since plan task 5's lane 2, exactly as
        // `Box.prepaint` and `Stack.prepaint` are. **The two accessibility
        // arguments are forwarded and are not optional decoration** (`OM-X`):
        // a helper that took only the three-argument form would delete every
        // text leaf's accessibility string. `Text` has no children, so the
        // content closure is empty and the clip scope is a no-op here — it is
        // written out anyway so a future `Text` that draws through the helper
        // gets the same answer the other three sites do.
        pass.registerAndScope(handlers, decoration, at: bounds, for: id,
                              accessibleText: string.isEmpty ? nil : string,
                              synthesizesAccessibility: true) { }
    }

    /// Emits the background, then one sprite per inked glyph.
    ///
    /// ## Why this shapes again rather than carrying the shape from layout
    ///
    /// The measure function was asked about several widths — §4.5's automatic
    /// minimum probes min-content, the flex algorithm probes the offered
    /// extent, and `roundLayout` then rounds the answer to a whole point — so
    /// the width a `Text` *ends up* occupying is not necessarily any of the
    /// widths it was measured at, and it is the one the glyphs must wrap to. So
    /// paint asks for the shape at the final box width. That is a `ShapingCache`
    /// lookup, not a re-typeset, whenever layout happened to ask the same
    /// question — and a genuine miss when rounding moved the width, which is
    /// correct rather than wasteful: shaping at the measured width and drawing
    /// in the rounded box is what would put a glyph outside its own box.
    ///
    /// `Layout` deliberately does not carry the `ShapedText` forward for the
    /// same reason: it would be the shape at a width that is one rounding step
    /// stale, and the staleness would be invisible.
    ///
    /// ## The origin is the box, and today the box has no inside
    ///
    /// Glyphs are laid from `bounds.origin`, the node's **border box**. For a
    /// `Text` those are the same rectangle, because a leaf's `padding` and
    /// `border` reach nothing: `measureNode` returns a leaf's measured size
    /// unchanged where it adds a container's `edges` back on, and `contentBox`
    /// only ever runs on a node with children. So `Text(…).padding(…)` is inert
    /// in layout *and* in paint, consistently — CLAUDE.md's inert table carries
    /// the row. When a leaf's box model is implemented, the origin here becomes
    /// the content box and must come from the engine rather than be re-resolved
    /// here, for the percentage-inset reason recorded at `Frame.fill`.
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void,
                               pass: inout PaintPass) {
        // Through `animatedBackground`, exactly as `Box.paint` and
        // `Stack.paint` do — see Task 5's note at `Stack.paint` for why this
        // was wired here rather than left as a named hole. That helper
        // resolves the `focusBackground ?? hoverBackground ?? background`
        // chain; `prepaint` registers this text's own hitbox and focus
        // registration, so an `onClick`/`focusable()` `Text` is hovered and
        // focused like any `Box`. Before the chain was hoisted this line passed
        // `decoration.background` and both modifiers compiled here and painted
        // nothing (`BackgroundChainTests.swift`).
        //
        // **This is a `Text`'s BACKGROUND, not its style and not its glyph
        // colour, and the distinction is what keeps it inside spec §8's
        // exclusion rather than in breach of it.** §5 and §8 exclude animating
        // a `Text`'s own *style* because its style participates in
        // MEASUREMENT — animating it means re-running `CTTypesetter` every
        // frame, a different cost question from substituting a number. A
        // background fill participates in neither: it is the same paint-phase
        // rect `Box` and `Stack` emit, at the same bounds layout already
        // computed. The glyph fill below (`foregroundColor ?? .textPrimary`)
        // is genuinely still unanimated — it is not in spec §4's animatable
        // list, and animating text colour is §8's named hole, unchanged.
        //
        // **Through `paintDecoration` since plan task 5's lane 2.** The glyphs
        // are this leaf's `content()`, so they sit between the background and
        // the border and inside the opacity scope and the clip — a bordered
        // `Text` draws its ring over its own glyphs (`OM-V`), and a faded one
        // fades them with its fill rather than leaving them opaque.
        //
        // **Both of those sentences are pinned — by the `Text` arm of
        // `everyDecorationScopingSiteContainsItsOwnContent` — and neither was
        // until the lane's review round** (`OM-AI`). Keeping this call and
        // moving `paintGlyphs` OUTSIDE the closure leaves the border at the
        // right box with the right widths and this element's own fill correctly
        // faded, so `everyDecorationPaintingSiteDrawsItsBorder` cannot see it,
        // while the glyphs read alpha 1.0 where they should read 0.5, escape
        // the clip, and are drawn OVER the ring rather than under it — measured:
        // the border rect lands at paint position 0 and the two glyphs at 1
        // and 2.
        pass.paintDecoration(decoration, in: bounds, for: id) {
            paintGlyphs(bounds: bounds, layout: &layout, pass: &pass)
        }
    }

    /// The glyph half of `paint`, as `paintDecoration`'s `content()`.
    private mutating func paintGlyphs(bounds: Bounds<Pixels>, layout: inout Layout,
                                      pass: inout PaintPass) {
        // The same memoized request `requestLayout` made — a dictionary hit,
        // not a second `CTFont` creation.
        let system = pass.textSystem
        let font = system.resolveFont(family: fontFamily, size: fontSize)
        // **The width layout MEASURED at, not the rounded box it stored** —
        // the fix for what CLAUDE.md carried as divergence 8, and the reason
        // this reads `pass.measuredWidth(of:)` rather than `bounds`.
        //
        // `roundLayout` stores `round(x + w) - round(x)`, which keeps a row
        // closed on its parent and is not in question here. But that number
        // lands *below* `w` about half the time, and re-asking `CTTypesetter`
        // at it is asking a different question from the one the measure
        // function answered: the last word no longer fits, so layout said one
        // line and this drew two, into a box one line tall. Measured on
        // `"Count N"` at 22pt — at the unrounded width every count is one line,
        // at `floor` of it every count is two.
        //
        // **It is now the same number layout used, so this is a cache HIT
        // rather than a second typeset pass.** That is a side benefit and not
        // the reason: the reason is that the two phases now agree by
        // construction. `ShapingCache.misses` is where a regression would show.
        //
        // The cost, stated because it is real: a glyph may extend up to a point
        // past the rounded box, recovering exactly what rounding removed. That
        // is not the paint-side epsilon this repo measured and rejected — an
        // epsilon is a blind additive fudge and could not be bounded, this is
        // the width the box was measured at.
        //
        // **Under the proposal authority too** (plan task 7, ruling LR-X): a
        // lowered `Text` with a declared size registers a fixed frame around its
        // native leaf, and `layout.node` is the frame, whose measured width is the
        // width the leaf was proposed — the question its shape answered. The
        // leaf's own width is its widest line, which is wider than the frame when
        // the frame is narrower than a word (2.7), and wrapping there draws fewer
        // lines than were measured.
        //
        // **And under a `Style.padding` that node is the LEAF, not the element**
        // (stage 2, lane 4, ruling LR-AH as amended). A lowered padded `Text`
        // registers its leaf inside a native padding, and the element's node is that
        // padding (or a fixed frame above it): the glyphs belong at the leaf's origin
        // and wrap at the leaf's measured width — the element's width less the
        // horizontal insets. Wrapping at the element's width instead — W's, when the
        // text is stretched or grown — would overflow the trailing padding and re-line
        // (critic round 1's finding 5; spec 4.2's stretched arm pins it).
        // `Frame.lowering.textLeaves` is empty under the legacy authority and for an
        // unpadded text, so both keep painting at `bounds.origin` at `layout.node`'s
        // measured width.
        let glyphNode = pass.frame.lowering.textLeaves[layout.node]
        let origin = glyphNode.map { pass.bounds(of: $0).origin } ?? bounds.origin
        let width = max(pass.measuredWidth(of: glyphNode ?? layout.node), smallestWrapWidth)
        let color = pass.theme[foregroundColor ?? .textPrimary]

        for glyph in system.placeGlyphs(string, font: font, wrappingAt: width,
                                        origin: (x: Double(origin.x.value), y: Double(origin.y.value)),
                                        scaleFactor: pass.scaleFactor) {
            pass.draw(glyph, color: color)
        }
    }
}
