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
    var isEditable = true
    var indentsWithSpaces = false
    var scrollStateObject: CodeScrollState?
    var onScrollAction: (@MainActor (CodeScrollPosition) -> Void)?
    var gutterClick: (@MainActor (CodeGutterHit) -> Void)?
    var gutterMenu: (@MainActor (CodeGutterHit) -> MenuItems)?
    var caretBlink = CodeCaretBlink.on
    var geometryObject: CodeViewGeometry?

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

    /// Whether typing, deleting, pasting, Return, Tab and undo change the buffer; on by default (`CV-W`). A view
    /// that is not editable, like a view of a read-only buffer (``CodeBuffer/isReadOnly``), still selects,
    /// copies, moves its caret and scrolls, and leaves Tab to move focus.
    public func codeViewEditable(_ editable: Bool) -> CodeView {
        var copy = self
        copy.isEditable = editable
        return copy
    }

    /// Whether Tab inserts spaces (up to the next tab stop of ``tabWidth(_:)``) and indents lines by that many;
    /// off by default, where Tab inserts a tab character.
    public func indentUsingSpaces(_ spaces: Bool) -> CodeView {
        var copy = self
        copy.indentsWithSpaces = spaces
        return copy
    }

    /// Shares the view's scroll position with `state`: the view publishes where it is scrolled after each
    /// change (a wheel, a drag, an edit above it), and scrolls to a value assigned to
    /// ``CodeScrollState/position``. The vertical position is in display rows (`CV-T`).
    public func scrollState(_ state: CodeScrollState) -> CodeView {
        var copy = self
        copy.scrollStateObject = state
        return copy
    }

    /// Calls `action` after a frame in which the view scrolled by itself: a wheel, a drag, a clamp after the
    /// text shrank, or an edit above that moved the reader's row. It runs outside every frame phase, so it may
    /// write other state (another view's ``CodeScrollState/position``). A position assigned through
    /// ``scrollState(_:)`` is **not** reported, which is what makes two views synced through this callback
    /// settle instead of echoing.
    public func onScroll(_ action: @escaping @MainActor (CodeScrollPosition) -> Void) -> CodeView {
        var copy = self
        copy.onScrollAction = action
        return copy
    }

    /// Calls `action` when the primary button is pressed on a gutter bar (`CV-AB`): the bar of a
    /// ``CodeLineDecoration`` or of a ``CodeVirtualRow``, including the bars beside a diff's removed lines. It
    /// runs from input, never in a frame phase, so it may write state; the press then neither moves the caret
    /// nor selects the line. A press in the gutter where no bar is drawn still selects the line.
    public func onGutterBarClick(_ action: @escaping @MainActor (CodeGutterHit) -> Void) -> CodeView {
        var copy = self
        copy.gutterClick = action
        return copy
    }

    /// A context menu for the gutter bars (`CV-AB`): a secondary press on a bar opens the menu `content` builds
    /// for the ``CodeGutterHit``, evaluated at each open, in input (`MN-D`). A secondary press anywhere else
    /// opens the view's own ``StyledElement/contextMenu(menuItems:)``, if it has one, and nothing otherwise.
    public func gutterBarContextMenu<M: MenuContent>(
        @MenuContentBuilder _ content: @escaping @MainActor (CodeGutterHit) -> M) -> CodeView {
        var copy = self
        copy.gutterMenu = { hit in MenuItems([content(hit)]) }
        return copy
    }

    /// Whether the caret blinks while the view has focus; ``CodeCaretBlink/on`` by default. A blinking caret
    /// costs two frames a second while the view is focused and idle (`CV-AC`); tests and screenshots turn it off.
    public func codeCaretBlink(_ blink: CodeCaretBlink) -> CodeView {
        var copy = self
        copy.caretBlink = blink
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
        // A primary press focuses the view, as a canvas or a text field is (`FC-A`), so the copy key routes to it.
        if handlers.keyboard?.focusInteractions == nil {
            handlers.keyboard = KeyboardAttachment.interactions(.edit, over: handlers.keyboard)
        }
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
        // The text stage's target: the session does the editing from input (`CV-W`); the caret rect is the input
        // method's area, under the view's own render effects (`GX-I`).
        let session = CodeEditSession(buffer: buffer, id: id, table: table, plan: plan, editable: isEditable,
                                      indentUsingSpaces: indentsWithSpaces, tabColumns: tabColumns, gutterClick: gutterClick,
                                      decorations: decorations)
        if let menu = gutterMenu {
            let existing = handlers.contextual
            // The menu's point is relative to the region's origin (`CI-R` item 3); the plan hits in the view's
            // bounds space, like the press's (`CV-AF`): add the origin back.
            let origin = bounds.origin
            handlers.contextual = ContextualAttachment(locatedMenu: { [plan] point in
                if let point, let hit = plan.gutterHit(at: Point(x: point.x + origin.x, y: point.y + origin.y)) { return menu(hit) }
                return existing?.menu?(point) ?? MenuItems([])
            }, help: existing?.help, helpProvider: existing?.helpProvider)
        }
        let caret = plan.caretPosition()
        let scaleF = frame.scaleFactor
        let caretRect = Bounds(origin: Point(x: Pixels(Float(caret?.x ?? plan.originX) / scaleF),
                                             y: Pixels(Float(caret?.top ?? plan.originY) / scaleF)),
                               size: Size(width: Pixels(1), height: Pixels(Float(plan.pitchPx) / scaleF)))
        handlers.textInput = TextInputTarget(code: session,
                                             caretRect: frame.effectBoundingBox(of: caretRect, ownEffects: decoration.renderEffects, bounds: bounds))
        handlers = handlers.copyingSelection(of: buffer)
        // One `.textArea` node, built only while an accessibility client is present (`CV-U`).
        if frame.collectsAccessibility {
            handlers.axNode.fillControl(role: .textArea, label: nil, value: plan.accessibilityText())
        }
        layout.plan = plan
        if let geometry = geometryObject {   // unobserved, like `CodeDecorations.sync()` (`CV-K`)
            geometry.plan = plan
            geometry.origin = bounds.origin
        }
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

/// Whether a ``CodeView``'s caret blinks (`CV-AC`).
public enum CodeCaretBlink: Equatable, Sendable {
    /// The caret is drawn for half a second, hidden for half a second, restarting when it moves or text changes;
    /// the view schedules a frame at each toggle (two a second while it is focused and idle) and nothing else.
    case on
    /// A solid caret: no timer, for tests and screenshots.
    case off

    /// Seconds from one toggle to the next.
    static let halfPeriod = 0.5
}
