import MetalUICodeBuffer
import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// A read-only view of a ``CodeBuffer`` for source code (`CV-` rulings, record 227): a monospaced gutter of
/// line numbers, syntax colours and tints from ``CodeDecorations``, mouse selection and copy, and its own
/// vertical and horizontal scrolling.
///
/// It is **one leaf element**, not a view per line: only the visible rows are shaped, through a two-frame
/// cache keyed by line content (`CV-M`), so opening a 100 000-line file costs the visible rows, and a
/// scroll costs the rows that entered. It sizes to its proposal, **never reads the buffer when measured**
/// (so a keystroke in a buffer invalidates no ancestor's layout memo, `CV-N`) and scrolls itself:
///
/// ```swift
/// let buffer = CodeBuffer(utf8: fileBytes)
/// let decorations = CodeDecorations(buffer: buffer)
/// CodeView(buffer: buffer, decorations: decorations)
///     .font(size: 12)
///     .frame(width: Pixels(600), height: Pixels(400))
/// ```
///
/// Line pitch and every row origin are whole device pixels (a fractional scale such as Windows' 1.25
/// included), which is what lets cached glyphs be placed by an integer translation. Tabs are expanded to
/// multiples of ``tabWidth(_:)`` space advances. Code ignores the layout direction: the gutter stays on the
/// left. MetalUI-only (class `M`, no divergence).
public struct CodeView: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()

    /// The text shown.
    public let buffer: CodeBuffer
    /// The highlights and line decorations drawn over it.
    public let decorations: CodeDecorations
    var fontRequest: TextFontRequest = .legacy(family: nil, size: 12)
    var fontIsMonospaceDefault = true
    var showsNumbers = true
    var tabColumns = 4

    /// A view of `buffer` drawn with `decorations`, whose buffer must be the same.
    public init(buffer: CodeBuffer, decorations: CodeDecorations) {
        precondition(decorations.buffer === buffer, "CodeView: the decorations belong to another buffer")
        self.style = Style()
        self.decoration = Decoration()
        self.buffer = buffer
        self.decorations = decorations
    }

    /// The face: a family (`nil`: the system's monospaced face) at `size` points.
    public func font(family: String? = nil, size: Double) -> CodeView {
        var copy = self
        copy.fontRequest = .legacy(family: family, size: size)
        copy.fontIsMonospaceDefault = family == nil
        return copy
    }

    /// Whether the gutter of line numbers is shown; on by default.
    public func showsLineNumbers(_ shown: Bool) -> CodeView {
        var copy = self
        copy.showsNumbers = shown
        return copy
    }

    /// The columns a tab advances to, as multiples of the space's advance; 4 by default.
    public func tabWidth(_ columns: Int) -> CodeView {
        var copy = self
        copy.tabColumns = max(1, columns)
        return copy
    }

    public struct Layout {
        /// The view's layout node.
        public var node: LayoutNodeID
        /// This frame's geometry and rows, built in prepaint for paint.
        var plan: CodeViewPlan?
    }

    @MainActor
    func resolvedFont(in environment: EnvironmentValues, system: any TextSystem) -> FontKey {
        var request = TextStyleRequest(font: fontRequest)
        request.monospaced = fontIsMonospaceDefault
        return system.resolveFont(resolveTextStyle(request, in: environment).descriptor)
    }

    // MARK: Layout

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        // Greedy on both axes, like `TextEditor`; a nil axis answers a fixed nominal size. **The measure
        // reads nothing of the buffer, the decorations or the font** (`CV-N`), so its key is empty.
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .textEditor) {
            pass.frame.requestNativeLeaf(key: AnyHashable(CodeViewLeafKey())) { proposal in
                LayoutMeasurement(size: SizeD(width: proposal.width ?? CodeViewLeafKey.nominalWidth,
                                              height: proposal.height ?? CodeViewLeafKey.nominalHeight))
            }
        }
        return (node, Layout(node: node, plan: nil))
    }

    // MARK: Prepaint

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {
        let frame = pass.frame
        let stored = pass.readState(id, initial: CodeViewState())   // a read, not a write (`RW-J`)
        let (plan, state) = makePlan(id, bounds: bounds, stored: stored, environment: pass.environment, frame: frame)
        // The anchor, the clamps and the measured width are written back in the phase, **compared**: a
        // function of the state, the buffer and the size, so it converges in one frame (`TextEditor`'s precedent).
        if state != stored {
            pass.withState(id, initial: CodeViewState(), unchanged: ==) { $0 = state }
        }
        var handlers = self.handlers
        handlers.isFocusable = true
        let table = frame.stateTable
        handlers.pointer = PointerAttachment.wheel({ [plan] event in
            let scale = Double(plan.scale)
            table.withState(id, initial: CodeViewState()) { state in
                let lineY = Double(plan.topPx) / scale, columnX = Double(plan.scrollXPx) / scale
                let maxY = Double(plan.maxTopPx) / scale, maxX = Double(plan.maxScrollXPx) / scale
                let target = ScrollChrome.wheelOffset(x: columnX + state.pendingX, y: lineY + state.pendingY,
                                                      delta: event.delta, maximum: (maxX, maxY))
                state.pendingX = target.x - columnX
                state.pendingY = target.y - lineY
                state.lastScrollTime = event.timestamp
            }
            return true
        }, over: handlers.pointer)
        let buffer = self.buffer
        handlers.gestures.append(GestureAttachment(
            DragGesture(minimumDistance: Pixels(0)).onChanged { [plan] value in
                plan.select(from: value.startLocation, to: value.location, clickCount: value.clickCount, in: buffer)
            }, priority: .normal))
        handlers = handlers.copyingSelection(of: buffer)
        layout.plan = plan
        pass.registerAndScope(handlers, decoration, at: bounds, for: id) { }
    }

    // MARK: Paint

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void,
                               pass: inout PaintPass) {
        guard let plan = layout.plan else { return }
        pass.paintDecoration(decoration, in: bounds, for: id) {
            paintContent(id, bounds: bounds, plan: plan, pass: &pass)
        }
    }
}

extension Handlers {
    /// This layer's copy handler: the buffer's selection as plain text, nothing for an empty selection.
    fileprivate func copyingSelection(of buffer: CodeBuffer) -> Handlers {
        var copy = self
        copy.keyboard = KeyboardAttachment.clipboard(
            ClipboardAttachment.copying({ () -> [String] in
                MainActor.assumeIsolated {
                    let selection = buffer.primarySelection.range
                    return selection.isEmpty ? [] : [buffer.snapshot().text(in: selection)]
                }
            }, over: copy.keyboard?.clipboard), over: copy.keyboard)
        return copy
    }
}
