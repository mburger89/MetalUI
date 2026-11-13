import MetalUICodeBuffer
import MetalUICore
import MetalUILayout

/// Where a text-anchored presentation of a ``CodeView`` points (`CV-AQ`, Alloy G35 E): the caret, or a range of
/// the buffer. MetalUI-only (class `M`, no divergence).
///
/// The anchor is resolved by the view in the frame, against the rows it draws, so a popover follows an edit, a
/// scroll and the caret within one frame without the app reading ``CodeViewGeometry`` and writing a rectangle back.
public enum CodeTextAnchor: Hashable, Sendable {
    /// The primary selection's head: the caret's rectangle (one point wide, a row high).
    case caret
    /// A range of UTF-8 byte offsets of the buffer **as of version `asOf`** (`nil`: the version the view draws).
    /// An older version is mapped through the buffer's edit log, like every other `asOf` (`CodeBuffer/map(_:from:bias:)`),
    /// so a range recorded before an edit above it still names the same text. A range the log no longer reaches
    /// back to anchors at the view's bounds.
    case range(Range<Int>, asOf: UInt64? = nil)
}

/// The rectangle a text anchor resolved to in one build, written by the ``CodeView`` in prepaint and read by the
/// `PopoverModifier` wrapping it in the same prepaint (`CV-AQ`). A new box per build, shared by the view's copy
/// and the wrapper; a class only so the two copies see one value.
@MainActor
final class CodeTextAnchorBox {
    let anchor: CodeTextAnchor
    /// The anchor in window points as drawn, or `nil` when it cannot be resolved (the wrapper then records the
    /// view's bounds).
    var windowRect: Bounds<Pixels>?
    /// Whether the wrapper presents its popover or overlay in this build (`CV-AS`: the hover's grace applies only then).
    var isPresented = false
    /// The view's text hover, when it has a handler: the panel's hover and a dismissal report to it.
    var hover: CodeTextHoverRuntime?

    init(_ anchor: CodeTextAnchor) { self.anchor = anchor }
}

extension CodeViewPlan {
    /// The caret's rectangle in bounds-space points, `nil` when its row is not among the shown rows.
    func caretBounds() -> Bounds<Pixels>? {
        guard let caret = caretPosition(), caret.top + pitchPx > originY, caret.top < originY + heightPx else { return nil }
        let width = max(1, Int(Double(scale).rounded()))
        return Bounds(origin: Point(x: Pixels(Float(caret.x) / scale), y: Pixels(Float(caret.top) / scale)),
                      size: Size(width: Pixels(Float(width) / scale), height: Pixels(Float(pitchPx) / scale)))
    }

    /// What `anchor` points at in bounds-space points (`CV-AQ`): the caret rectangle, or the range's first shown
    /// row segment; **an empty rectangle at the nearest visible edge** when it is on no shown row (above the
    /// first shown row: the view's top; otherwise its bottom), at the text's left. Always cut to the view's
    /// horizontal extent. `nil` only for a range the buffer's edit log no longer reaches back to.
    @MainActor
    func textAnchorRect(for anchor: CodeTextAnchor, buffer: CodeBuffer) -> Bounds<Pixels>? {
        let range: Range<Int>
        switch anchor {
        case .caret:
            if let rect = caretBounds() { return clampedHorizontally(rect) }
            range = head..<head
        case .range(let given, let asOf):
            if let asOf {
                guard let lower = buffer.map(given.lowerBound, from: asOf, bias: .after),
                      let upper = buffer.map(given.upperBound, from: asOf, bias: .before) else { return nil }
                range = lower..<max(lower, upper)
            } else {
                range = given
            }
            if let rect = rects(forBounds: range).first { return clampedHorizontally(rect) }
        }
        var firstShown: Int?
        var i = shownFrom
        while i < shownTo {
            let row = rows[i]
            i += 1
            if !row.isVirtual { firstShown = row.range.lowerBound; break }
        }
        let above = firstShown.map { range.lowerBound < $0 } ?? true
        let y = Float(above ? originY : originY + heightPx) / scale
        let rect = Bounds(origin: Point(x: Pixels(Float(textOriginX) / scale), y: Pixels(y)),
                          size: Size(width: Pixels(0), height: Pixels(0)))
        return clampedHorizontally(rect)
    }

    /// `rect` cut to the view's horizontal extent (a segment scrolled out sideways pins to the edge, zero wide).
    private func clampedHorizontally(_ rect: Bounds<Pixels>) -> Bounds<Pixels> {
        let left = Float(originX) / scale, right = Float(originX + widthPx) / scale
        let x0 = min(max(rect.origin.x.value, left), right)
        let x1 = min(max(rect.origin.x.value + rect.size.width.value, left), right)
        return Bounds(origin: Point(x: Pixels(x0), y: rect.origin.y), size: Size(width: Pixels(x1 - x0), height: rect.size.height))
    }
}

extension CodeView {
    /// This view with a fresh anchor box for `anchor`, and the box for the wrapper.
    fileprivate func anchored(to anchor: CodeTextAnchor) -> (view: CodeView, box: CodeTextAnchorBox) {
        let box = CodeTextAnchorBox(anchor)
        var copy = self
        copy.textAnchorBox = box
        return (copy, box)
    }

    /// Presents `content` in a popover pointing at the caret or a range of this view's text, while `isPresented` is
    /// `true` (`CV-AQ`, Alloy G35 E): ``StyledElement/popover(isPresented:attachmentAnchor:arrowEdge:content:)``
    /// with a text anchor in place of ``PopoverAttachmentAnchor``. `attachmentAnchor` has no default: the view's
    /// own bounds are the other overload's.
    ///
    /// The view resolves the anchor in the frame against the rows it draws: the caret rectangle, or the range's
    /// first shown row segment; a range on no shown row anchors at an empty rectangle at the nearest visible edge
    /// of the view, so a popover of a range scrolled away stays at the edge the range left by. It follows an edit,
    /// a scroll and the caret within one frame, and survives retained replay. Everything else is the popover's:
    /// placement, flipping, Escape, dismissal by an outside press, `@State` fresh at each presentation. **A press on
    /// the anchored text dismisses and then reaches the view** (it places the caret): unlike an anchor that is a
    /// button, the text is not a toggle, so the press is not consumed. Chain it directly on the ``CodeView``
    /// (after its own modifiers); one text-anchored presentation per view.
    public func popover<P: ElementGroup>(isPresented: Binding<Bool>,
                                         attachmentAnchor: CodeTextAnchor,
                                         arrowEdge: Edge? = nil,
                                         @ElementBuilder content: @escaping @MainActor () -> P)
        -> PopoverModifier<CodeView, P> {
        let (view, box) = anchored(to: attachmentAnchor)
        return PopoverModifier(content: view, kind: .popover(.rect(.bounds), arrowEdge ?? .top),
                               presented: presenting(isPresented, content),
                               dismiss: { isPresented.wrappedValue = false; box.hover?.hardEnd() }, textAnchor: box)
    }

    /// Presents a popover built from `item` while it is non-`nil`, pointing at the caret or a range of this view's
    /// text — ``popover(isPresented:attachmentAnchor:arrowEdge:content:)`` with an item (`CV-AQ`).
    public func popover<Item: Identifiable, P: ElementGroup>(item: Binding<Item?>,
                                                             attachmentAnchor: CodeTextAnchor,
                                                             arrowEdge: Edge? = nil,
                                                             @ElementBuilder content: @escaping @MainActor (Item) -> P)
        -> PopoverModifier<CodeView, P> {
        let (view, box) = anchored(to: attachmentAnchor)
        return PopoverModifier(content: view, kind: .popover(.rect(.bounds), arrowEdge ?? .top),
                               presented: presenting(item, content),
                               dismiss: { item.wrappedValue = nil; box.hover?.hardEnd() }, textAnchor: box)
    }

    /// Shows `content` beside the caret or a range of this view's text on `edge`'s side while `isPresented` is `true`,
    /// without taking focus or keys (`CV-AQ`, `CV-AR`; Alloy G35 E): a completion list that follows the caret as the
    /// user types. ``StyledElement/suggestionOverlay(isPresented:edge:alignment:spacing:content:)`` with a text
    /// anchor; defaults are the editor's (below the text, two points away, its leading edge on the anchor's).
    ///
    /// **Keys stay with the view** (`CV-AR`): nothing but the app dismisses it, and `↑ ↓ Return Tab Esc` reach the
    /// app's ``View/onKeyPress(_:action:)`` on the view first — `.handled` consumes (the view does not move the caret,
    /// insert a line or a tab), `.ignored` lets the view edit as usual — and a typed character is offered before it is
    /// inserted. Nothing is offered while an input method has marked text. The keymap and a command's shortcut still
    /// run before `onKeyPress`.
    public func suggestionOverlay<P: ElementGroup>(isPresented: Binding<Bool>,
                                                   attachmentAnchor: CodeTextAnchor,
                                                   edge: VerticalEdge = .bottom,
                                                   alignment: HorizontalAlignment = .leading,
                                                   spacing: Pixels = Pixels(2),
                                                   @ElementBuilder content: @escaping @MainActor () -> P)
        -> PopoverModifier<CodeView, P> {
        let (view, box) = anchored(to: attachmentAnchor)
        return PopoverModifier(content: view, kind: .suggestion(edge: edge, alignment: alignment, spacing: spacing.value),
                               presented: presenting(isPresented, content), dismiss: {}, textAnchor: box)
    }
}
