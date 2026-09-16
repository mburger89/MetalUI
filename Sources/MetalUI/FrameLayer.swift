import MetalUICore
import MetalUILayout

// The legacy (CSS-engine) frame's one semantic home.
//
// `Sources/MetalUI/ModifiedElement.swift` is one of the eight files a parallel
// track also edits, and this milestone's frame work would otherwise land on its
// last lines — the exact hunk boundary that track appends at (frame-sizing
// critic finding 14). So `ModifiedElement.swift` keeps a one-line forwarding
// declaration of the FIXED overload and every change to the legacy frame's
// meaning happens here, in a file no other track touches.
//
// **Why the fixed overload is declared there and the flexible one here**
// (ruling FR-S). It cannot be declared in both places, and it cannot be
// duplicated: two applicable fixed `frame` overloads on `ElementGroup` make a
// long modifier chain EXPONENTIAL for the constraint solver. Measured against
// this module: `Leaf().padding(1).frame(width: 1)…` twelve times over fails
// `-solver-scope-threshold=16000` with both and needs 186 scopes with one —
// the same 186 `ModifiedElementCompileGuards`' budget guard measured before
// this lane. So lane 1's declaration was amended IN PLACE to carry
// `alignment:`, which is the smallest possible edit to the shared file, and the
// flexible overload — a name that file never had — lives here.
//
// Lane 2 (rulings FR-C, FR-D, FR-E, FR-K, FR-N, FR-O, FR-P) grew `FrameSpec`
// from step 0's two fields to SwiftUI's whole parameter surface, and `style()`
// from two rows to the lowering table below.

/// SwiftUI's frame as one value: what `.frame(...)` asked for, before the CSS
/// lowering that ``style()`` performs.
///
/// **INTERNAL on purpose** (ruling FR-C): it appears in no public signature —
/// the frame overloads return `ModifiedElement<LayerBase>` — so a `public`
/// spelling would be a name an outside module can neither construct nor read,
/// which is the declared-but-inert shape CLAUDE.md keeps a table of. There is
/// nothing to narrow later, so no plain-import typecheck guard is owed
/// (practices shape 16 applies to narrowing an EXISTING public name).
///
/// There is no `idealWidth`/`idealHeight` field: an ideal has no CSS lowering,
/// and the overload that accepts one **traps** before building a spec
/// (ruling FR-D).
struct FrameSpec: Sendable, Hashable {
    var width: Pixels?
    var height: Pixels?
    var minWidth: Pixels?
    var maxWidth: Pixels?
    var minHeight: Pixels?
    var maxHeight: Pixels?
    var alignment: ProposalAlignment = .center

    /// The one place the CSS approximation of a SwiftUI frame lives (ruling
    /// FR-C), row by row with the measurement behind it. The layer is a flex
    /// container on its default `.row` direction, or a one-cell stack over
    /// exactly one node (ruling `CN-N`, the second row).
    ///
    /// | asked for | `Style` | evidence |
    /// |---|---|---|
    /// | any frame | `justifyContent`/`alignItems` from a `switch` over the nine alignment CASES | scratch L6: all nine place a 20×20 child at the probe's B1–B8 offsets exactly (test 2.1) |
    /// | a frame over **exactly one** node | `display: .stack` (set in `ModifiedElement.requestLayout` by `ModifierLayer.lowered`, which alone knows the node count), reading `alignItems` and the `justifyItems` the same `switch` writes (a flex row ignores `justifyItems`, a stack ignores `justifyContent`) | ruling `CN-N`, probe arms A5/B9: a 200×160 child in a 60×40 frame keeps its size at (−70, −60), or (0, 0) top-leading (test 5.1, which replaced 2.8) |
    /// | `width`/`height` | `size.<axis>` **and `minSize.<axis>`** — an axis-named pin, never `flexShrink = 0` | ruling FR-P, scratch N10/N11 (tests 2.2 and 2.10) |
    /// | `minWidth`/`minHeight` | `minSize.<axis>` | scratch L10, agreeing with probe arms D7/D8/D9 |
    /// | a finite `maxWidth`/`maxHeight` | `maxSize.<axis>` — **a clamp, never greedy** | ruling FR-E: MetalUI reads 20 where SwiftUI's D4 reads 80 (test 2.3) |
    /// | BOTH maximums infinite | `flexGrow = 1` **and** `alignSelf = .stretch` — it fills | ruling FR-O, scratch N14 (test 2.9) |
    /// | ONE maximum infinite | nothing: the layer is present and **inert** | ruling FR-O, scratch N15 (test 2.9) |
    ///
    /// **The alignment `switch` is over the cases on purpose** (critic finding
    /// 15). `ProposalAlignment.horizontalFactor`/`verticalFactor` are `Double`s,
    /// and a `switch` over one needs a `default` that would silently pick an
    /// edge for any value that is not exactly 0, 0.5 or 1 — which is what a
    /// later non-standard alignment would produce. Switching over the cases
    /// makes a tenth case a build error here instead. The factors stay the
    /// evidence; they are not the lowering.
    ///
    /// **A fixed axis and that axis's bounds never arrive together**: SwiftUI
    /// has no overload that spells both (`extra argument 'minWidth' in call`),
    /// and neither does MetalUI, so the `minSize` writes below cannot fight.
    func style() -> Style {
        var style = Style()

        switch alignment {
        case .topLeading:     style.justifyContent = .flexStart; style.alignItems = .flexStart;      style.justifyItems = .start
        case .top:            style.justifyContent = .center;    style.alignItems = .flexStart;      style.justifyItems = .center
        case .topTrailing:    style.justifyContent = .flexEnd;   style.alignItems = .flexStart;      style.justifyItems = .end
        case .leading:        style.justifyContent = .flexStart; style.alignItems = .center;         style.justifyItems = .start
        case .center:         style.justifyContent = .center;    style.alignItems = .center;         style.justifyItems = .center
        case .trailing:       style.justifyContent = .flexEnd;   style.alignItems = .center;         style.justifyItems = .end
        case .bottomLeading:  style.justifyContent = .flexStart; style.alignItems = .flexEnd;        style.justifyItems = .start
        case .bottom:         style.justifyContent = .center;    style.alignItems = .flexEnd;        style.justifyItems = .center
        case .bottomTrailing: style.justifyContent = .flexEnd;   style.alignItems = .flexEnd;        style.justifyItems = .end
        }

        // A declared axis is pinned by `minSize` on THAT axis, so an
        // over-constrained parent cannot shrink it (SwiftUI never shrinks a
        // frame). `flexShrink = 0` would pin the parent's main axis whichever
        // one the caller declared — ruling FR-P, test 2.10. `flexGrow = 0` is
        // not written: it is already `Style`'s default.
        if let width {
            style.size.width = .length(.pixels(width))
            style.minSize.width = .length(.pixels(width))
        }
        if let height {
            style.size.height = .length(.pixels(height))
            style.minSize.height = .length(.pixels(height))
        }

        if let minWidth { style.minSize.width = .length(.pixels(minWidth)) }
        if let minHeight { style.minSize.height = .length(.pixels(minHeight)) }
        // Only a FINITE maximum becomes a `maxSize`: an infinite one means
        // "fill", which is the flex lowering below, and `.length(.pixels(inf))`
        // would put an infinity into the engine's arithmetic.
        if let maxWidth, maxWidth.value.isFinite { style.maxSize.width = .length(.pixels(maxWidth)) }
        if let maxHeight, maxHeight.value.isFinite { style.maxSize.height = .length(.pixels(maxHeight)) }

        // `flexGrow` fills the parent's MAIN axis and `alignSelf: .stretch` its
        // CROSS axis, so setting both fills whichever way the parent runs
        // (ruling FR-O, scratch N14). Doing it for a single infinite maximum
        // would consume an axis the caller never mentioned — scratch N15 pushed
        // a `Column` sibling from y = 20 to y = 195 — so a single infinite
        // maximum is left inert, and CLAUDE.md owes it a declared-but-inert row.
        if maxWidth?.value == .infinity && maxHeight?.value == .infinity {
            style.flexGrow = 1
            style.alignSelf = .stretch
        }

        return style
    }
}

extension ElementGroup {
    /// SwiftUI's flexible frame, with the proposal path's exact parameter
    /// names, order and defaults, so a call site ports between the two engines
    /// by changing nothing but the element type.
    ///
    /// **What it does and does not reach.** The legacy path lowers to CSS, and
    /// SwiftUI's answers that one CSS node cannot reach are rulings with tests
    /// (the first and third pin MetalUI's number wrong on purpose; plan task 6
    /// deferred both to task 7, `CN-Q`):
    ///
    /// - a **finite** maximum clamps but never grows into the proposal
    ///   (`FR-E`): `.frame(maxWidth: 80)` over a 20pt child reads 20 where
    ///   SwiftUI's probe arm D4 reads 80, because a CSS layer cannot see a
    ///   proposal for one named axis;
    /// - a child bigger than the frame used to be squeezed on the layer's main
    ///   axis (`FR-N`); since ruling `CN-N` a frame over exactly one node is a
    ///   one-cell stack and the child overflows both axes as in SwiftUI (test
    ///   5.1), while a frame over several nodes (a multi-member `Component`)
    ///   keeps the row and still squeezes;
    /// - a **single** infinite maximum is present and inert, where both
    ///   infinite maximums fill (`FR-O`, test 2.9).
    ///
    /// - Precondition: `idealWidth` and `idealHeight` must be `nil` — an ideal
    ///   dimension answers an *unspecified* proposal, which the CSS engine
    ///   never has, and `Style` carries no such field (ruling `FR-D`). The
    ///   parameters stay in the signature so that a port between paths is a
    ///   type change and nothing else, and so this message can name the way out.
    ///
    /// The fixed overload, `frame(width:height:alignment:)`, is declared in
    /// `ModifiedElement.swift` and must stay the only one — see this file's
    /// header and ruling `FR-S`.
    public func frame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil,
                      minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedElement<LayerBase> {
        precondition(idealWidth == nil, """
            idealWidth has no legacy (CSS) lowering (ruling FR-D): an ideal \
            dimension is what a view answers when NOTHING is proposed, and the \
            CSS engine lays every box out against a containing block. Use the \
            proposal path's .frame(idealWidth:) on a ProposalElement, or \
            declare a width.
            """)
        precondition(idealHeight == nil, """
            idealHeight has no legacy (CSS) lowering (ruling FR-D): an ideal \
            dimension is what a view answers when NOTHING is proposed, and the \
            CSS engine lays every box out against a containing block. Use the \
            proposal path's .frame(idealHeight:) on a ProposalElement, or \
            declare a height.
            """)
        return _wrap(ModifierLayer(style: FrameSpec(minWidth: minWidth, maxWidth: maxWidth,
                                                    minHeight: minHeight, maxHeight: maxHeight,
                                                    alignment: alignment).style(),
                                   isFrame: true))
    }

    /// SwiftUI's own rejection of an argument-less frame, verbatim (ruling
    /// FR-J).
    ///
    /// Every parameter of `frame(width:height:alignment:)` has a default, so
    /// `.frame()` used to compile silently and build a real centring,
    /// size-nothing layer — a node, an identity level and a `$anim` slot for
    /// nothing (`SA-N` item 9). SwiftUI answers that with a separate
    /// zero-parameter overload marked deprecated, which the compiler prefers
    /// for a no-argument call; this is the same overload with the same message,
    /// returning the receiver so it contributes nothing.
    ///
    /// **A matching declaration on `ProposalElementGroup` is load-bearing, not
    /// redundant** (`NativeModifiedContent.swift`). With this one alone, a
    /// no-argument call on a proposal element resolves to that refined
    /// protocol's own all-defaulted `frame(width:height:alignment:)` — more
    /// specialized, so it wins — and infers `ModifiedContent<…>` with no
    /// diagnostic at all, which is `SA-N` item 9 surviving on the path that
    /// matters. Measured; pinned by the typecheck fixture
    /// `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths`.
    ///
    /// `.frame(alignment:)` is deliberately left alone: SwiftUI accepts it too,
    /// and an alignment with nothing to align is a no-op in both.
    @available(*, deprecated, message: "Please pass one or more parameters.")
    public func frame() -> Self { self }
}
