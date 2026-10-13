import MetalUILayout
import MetalUITextSystem

// The layout memo's leaf keys (C14 lane 1, `IV-E`, `IV-N`). A key covers **every
// input its leaf's measure closure reads besides the proposal**; the closure must
// be a pure function of the key and the proposal. Only these leaves are keyed;
// every other leaf (rich text, images, controls, third-party) is unkeyed and makes
// its ancestors unmatchable. Adding a site is one key here plus a "key covers the
// closure" test (`LayoutMemoKeyTests`).

/// A plain text leaf: what `proposalTextMeasurement` reads — the string, the
/// resolved font, the line limit, truncation and alignment of the resolved style,
/// and the text system (a different system measures differently). **Not** the
/// foreground colour, which the measure ignores, so a colour change is
/// signature-identical, and **not** the scale factor, which no measure call takes
/// (`placeGlyphs` does; `IV-N`).
struct TextLeafKey: Hashable {
    let string: String
    let font: FontKey
    let minLines: Int?
    let maxLines: Int?
    let truncation: TextTruncation
    let alignment: TextLineAlignment
    let system: ObjectIdentifier

    @MainActor
    init(_ string: String, font: FontKey, style: ResolvedTextStyle, system: any TextSystem) {
        self.string = string
        self.font = font
        minLines = style.lineLimit.min
        maxLines = style.lineLimit.max
        truncation = style.truncation
        alignment = style.alignment
        self.system = ObjectIdentifier(system)
    }
}

/// A `Divider`: its axis (`Divider.measurement(for:vertical:)`).
struct DividerLeafKey: Hashable { let vertical: Bool }

/// A built-in shape with the default `sizeThatFits` (the proposal, 10 on a nil
/// axis) or `Circle`'s: a function of its type alone.
struct ShapeLeafKey: Hashable { let type: ObjectIdentifier }

/// `Rectangle`: `Rectangle.measurement(for:width:height:respondsToProposal:)`.
struct RectangleLeafKey: Hashable {
    let width: Double
    let height: Double
    let respondsToProposal: Bool
}

/// The gradient fill leaf: the proposal, 10 on a nil axis.
struct GradientLeafKey: Hashable {}

/// A `GPUSurface`: the proposal, 10 on a nil axis (`MV-B`). Its draw closure,
/// policy and value are paint's and cannot reach layout.
struct GPUSurfaceLeafKey: Hashable {}

/// The key of a shape the memo may reuse, `nil` for a conformer outside the
/// built-ins (its `sizeThatFits` is user code).
func builtInShapeLeafKey<S: Shape>(_ shape: S) -> ShapeLeafKey? {
    switch shape {
    case is RoundedRectangle, is Circle, is Capsule, is Ellipse:
        ShapeLeafKey(type: ObjectIdentifier(S.self))
    default:
        nil
    }
}
