import MetalUICore
import MetalUILayout
import MetalUIText

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
private let smallestWrapWidth = 0.5

/// Measures `string` the way spec §3.4's table says, for one axis' worth of
/// question at a time.
///
/// | `available.width` | wrapped at | width reported |
/// |---|---|---|
/// | `.maxContent` | nothing — one line | the line's advance |
/// | `.minContent` | the widest unbreakable run | that run's width |
/// | `.definite(w)` | `max(w, smallestWrapWidth)` | the widest resulting line |
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
func textMeasure(_ string: String, font: ResolvedFont, cache: ShapingCache,
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
            // The widest unbreakable run, shaped one run at a time **through
            // the cache** — so the runs a min-content probe measures are shared
            // between frames exactly as whole strings are, and a second frame
            // adds no misses. `Shaper.unbreakableRuns` carries the measurement
            // of why this is not `shape(wrappingAt: someTinyWidth)`: the
            // typesetter character-breaks a word it cannot fit, so a tiny width
            // answers "the widest character" (11.489) where §4.5 needs "the
            // longest word" (110.348).
            var minContent = 0.0
            for run in Shaper.unbreakableRuns(of: string) {
                minContent = max(minContent,
                                 cache.shaped(run, font: font, wrappingAt: nil).widestLine)
            }
            wrapWidth = max(minContent, smallestWrapWidth)
            reportedWidth = minContent
        case .definite(let offered):
            wrapWidth = max(offered, smallestWrapWidth)
        }
    }

    let shaped = cache.shaped(string, font: font, wrappingAt: wrapWidth)
    return SizeD(width: reportedWidth ?? shaped.widestLine,
                 height: known.height ?? shaped.totalHeight)
}

/// The overload the engine's `MeasureFunction` shape calls, which takes the
/// whole `AvailableSpaceSize` and reads only its width. Separate so that the
/// function above cannot be *given* a height question it silently ignores.
@MainActor
func textMeasure(_ string: String, font: ResolvedFont, cache: ShapingCache,
                 known: OptionalSizeD, available: AvailableSpaceSize) -> SizeD {
    textMeasure(string, font: font, cache: cache, known: known, available: available.width)
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
/// **It does not draw yet, and that is the whole of what is missing.** `paint`
/// emits this element's background if one is set and nothing else: glyphs need
/// the atlas and the renderer's text pipeline, which are Tasks 5–7 of this
/// milestone. So a `Text` today occupies exactly the right box and shows
/// nothing inside it. ``foregroundColor(_:)`` is stored against that arrival and
/// is read by no production code — CLAUDE.md's inert table carries the row.
///
/// **One font at one size per `Text`** (spec §2): rich text, per-run attributes
/// and per-line metrics are out of M2, which is what lets height be
/// `lines × lineHeight` with a single line height.
public struct Text: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?

    /// The string to lay out. `let`-like in practice — the measure closure
    /// captures a copy at `requestLayout`, so mutating this afterwards affects
    /// the *next* frame's element value, which is the same rebuild-per-frame
    /// model every other element follows.
    public var string: String

    /// `nil` means the platform UI font. Resolution happens in `requestLayout`,
    /// through `FontResolver`, which substitutes rather than failing — see
    /// `FontKey` for why nothing may be keyed on this name.
    public var fontFamily: String?
    public var fontSize: Double

    /// The colour glyphs will be tinted with **when this element can draw
    /// them** (Task 7). Read by nothing today.
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

    /// The token glyphs will be tinted with once text can draw (Task 7). A
    /// semantic token rather than an `Hsla`, for §7.9's reason: a literal would
    /// paint identically in both appearances while looking exactly like a themed
    /// colour at the call site.
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
        let cache = pass.shapingCache
        let font = FontResolver.resolve(family: fontFamily, size: fontSize)
        // Registered here, on the main actor, so that the `@Sendable` closure
        // below can reach the font by its `Sendable` key instead of capturing
        // the font itself — see the capture list note below.
        cache.registerFont(font)

        let key = font.key
        let string = self.string

        // **The captures are the whole concurrency story, and each one is
        // settled by the compiler rather than by argument.**
        //
        // - `cache` is a `@MainActor final class`, so it is implicitly
        //   `Sendable` and a `@Sendable` closure may hold it.
        // - `font` is **not** capturable: `ResolvedFont` wraps a `CTFont`, a
        //   CoreFoundation class with no `Sendable` guarantee. `key` is the
        //   `Sendable` stand-in that crosses instead, and the font is fetched
        //   back out of the cache once the block is already isolated.
        // - `MainActor.assumeIsolated<T>` requires `T: Sendable`, so the block
        //   must reduce to `SizeD` before returning. A `ShapedText` never
        //   escapes it — which is the same reason it may hold a `CTLine`.
        //
        // The assumption itself is sound because `computeLayout` runs
        // synchronously inside `Frame.computeRootLayout`, which is `@MainActor`;
        // the engine is non-isolated code on the caller's thread, not a hop.
        //
        // **It is also a latent release trap that no test can guard, which is
        // why it is stated here and in CLAUDE.md rather than only implied.**
        // `assumeIsolated` terminates the process when the assumption is false,
        // so laying out a tree containing a text leaf from any other executor —
        // a background actor, a `Task.detached`, the 4 MB worker thread
        // `LayoutContext`'s depth test spins up — kills the app. Nothing in the
        // repo can notice: every off-main-actor layout here builds a leafless
        // tree, and a test that got it wrong would crash the run rather than
        // redden. If layout ever moves off the main actor, this closure is the
        // first thing to rewrite — the cache would have to become an actor, or
        // the shaped size would have to be computed before the closure is
        // built.
        let node = pass.requestLeaf(style: style) { known, available in
            MainActor.assumeIsolated {
                // **Cannot fire: same instance, and the cache has no removal
                // path.** `registerFont` ran on this exact `ShapingCache`
                // object four lines above (the closure captures the object, not
                // a copy), and `ShapingCache` exposes no eviction, no clear and
                // no re-key — `fonts` is only ever written by `registerFont`.
                // A miss would therefore mean the closure is holding a
                // different cache than the one that registered, which no call
                // path can produce. It traps rather than substituting a zero
                // size, because a text run silently measuring 0x0 is precisely
                // the invisible failure this milestone has no test for.
                guard let font = cache.font(for: key) else {
                    preconditionFailure("""
                        No font registered for \(key) on the shaping cache this \
                        measure function captured. Text.requestLayout registers \
                        the font on that same instance before building the \
                        closure, and ShapingCache never removes one.
                        """)
                }
                return textMeasure(string, font: font, cache: cache,
                                   known: known, available: available)
            }
        }
        return (node, Layout(node: node))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void,
                               pass: inout PaintPass) {
        // The background is all this can draw. Glyphs arrive with the atlas and
        // the text pipeline (Tasks 5-7); see the type's doc comment.
        if let token = decoration.background {
            pass.fill(bounds, color: pass.theme[token],
                      cornerRadii: Corners(all: decoration.cornerRadius))
        }
    }
}
