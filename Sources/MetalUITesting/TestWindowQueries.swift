import MetalUI
import MetalUICore

// Queries over the published accessibility tree (ruling `HT-G` items 1, 3,
// 4): XCUITest's model — identifier, label, role — on the tree the window
// last handed its platform, so a query that works is also a VoiceOver fact.

extension TestWindow {
    /// The accessibility tree the window last published. Empty before the
    /// first publish; throws ``TestHarnessError/notRecorded(_:)`` when the
    /// window opened with `accessibilityClientActive` off and nothing has
    /// activated accessibility since.
    public var accessibilityTree: AccessibilityTree {
        get throws {
            if let tree = platformWindow.publishedAccessibilityTrees.last { return tree }
            guard platformWindow.options.accessibilityClientActive else {
                throw TestHarnessError.notRecorded("accessibility")
            }
            return .empty
        }
    }

    /// The one element whose `.accessibilityIdentifier` is `identifier`.
    /// Throws ``TestHarnessError/noElement(_:)`` for none and
    /// ``TestHarnessError/ambiguous(_:count:)`` for several.
    public func element(identifier: String) throws -> TestElement {
        try single("identifier \"\(identifier)\"") { $0.identifier == identifier }
    }

    /// The one element whose accessible name is `label` — for a static text,
    /// whose string is `label` (XCUITest's label of a text; the node carries
    /// it as its value, ruling `HT-T` item 1). Throws
    /// ``TestHarnessError/noElement(_:)`` for none and
    /// ``TestHarnessError/ambiguous(_:count:)`` for several.
    public func element(label: String) throws -> TestElement {
        try single("label \"\(label)\"") { element in
            if let name = element.label { return name == label }
            return element.role == .staticText && element.value == label
        }
    }

    /// Every element of `role`, in tree order (pre-order from the roots, each
    /// node's children in published order).
    public func elements(role: AccessibilityRole) throws -> [TestElement] {
        try elements { $0.role == role }
    }

    /// Every element `predicate` accepts, in tree order.
    public func elements(where predicate: (TestElement) -> Bool) throws -> [TestElement] {
        try Self.preOrder(accessibilityTree).filter(predicate)
    }

    /// The colours the last presented frame drew text in inside `element`'s frame, in paint order, one per
    /// run: consecutive glyphs of one colour are one entry, so a `Text` of one colour answers one colour and a
    /// styled run (a link inside a sentence) adds its own (Sift G19).
    ///
    /// **Read from the frame's own scene, after the fact**: a glyph belongs to the element whose ``TestElement/frame``
    /// holds its centre, so nothing is recorded while a frame draws and a frame's cost is the same whether or not a
    /// test asks. A container answers the colours of every text inside it, an element that drew no text answers
    /// `[]`. The colours are as drawn, theme and colour scheme resolved, with the opacity in effect folded into
    /// their alpha (``allGlyphs``, which also reaches text inside an opacity group or a masked clip). Compare
    /// through ``Hsla/toRgba()``, not `==`, against a colour written by another route. MetalUI-only (`HT-B`).
    public func drawnTextColors(in element: TestElement) -> [Hsla] {
        let scale = platformWindow.scaleFactor
        let frame = element.frame
        let left = Float(frame.origin.x.value) * scale, top = Float(frame.origin.y.value) * scale
        let right = left + Float(frame.size.width.value) * scale, bottom = top + Float(frame.size.height.value) * scale
        var runs: [Hsla] = []
        for glyph in allGlyphs {
            let cx = glyph.bounds.origin.x + glyph.bounds.size.width / 2
            let cy = glyph.bounds.origin.y + glyph.bounds.size.height / 2
            guard cx >= left, cx < right, cy >= top, cy < bottom else { continue }
            let color = Hsla(h: glyph.color.h, s: glyph.color.s, l: glyph.color.l, a: glyph.color.a)
            if runs.last != color { runs.append(color) }
        }
        return runs
    }

    /// The element with the window's keyboard focus, or `nil`.
    public var focusedElement: TestElement? {
        get throws {
            let tree = try accessibilityTree
            return tree.focused.flatMap { TestElement($0, in: tree) }
        }
    }

    /// Asks the window to perform `action` on `element` as a screen reader
    /// does (`AccessibilityRequest`), then draws one frame. Several actions in
    /// the set run in the order press, increment, decrement, show-menu, expand, collapse.
    /// Answers whether the window handled every one (`false` for an empty
    /// set).
    @discardableResult
    public func performAccessibilityAction(_ action: AccessibilityActions, on element: TestElement) throws -> Bool {
        _ = try accessibilityTree
        var requests: [AccessibilityRequest] = []
        if action.contains(.press) { requests.append(.press(element.id)) }
        if action.contains(.increment) { requests.append(.increment(element.id)) }
        if action.contains(.decrement) { requests.append(.decrement(element.id)) }
        if action.contains(.showMenu) { requests.append(.showMenu(element.id)) }
        if action.contains(.expand) { requests.append(.expand(element.id)) }
        if action.contains(.collapse) { requests.append(.collapse(element.id)) }
        var handled = !requests.isEmpty
        for request in requests where !platformWindow.simulateAccessibilityRequest(request) {
            handled = false
        }
        tick()
        return handled
    }

    /// Sets `element`'s numeric value as a screen reader does (`AccessibilityRequest.setValue`, ruling `HS-K`: a split
    /// view's divider, whose value is the size in points of the pane before it), then draws one frame. Answers whether the
    /// window handled it (`false` for an element that does not advertise `.setValue`).
    @discardableResult
    public func setAccessibilityValue(_ value: Double, on element: TestElement) throws -> Bool {
        _ = try accessibilityTree
        let handled = platformWindow.simulateAccessibilityRequest(.setValue(element.id, value))
        tick()
        return handled
    }

    /// Moves keyboard focus to `element` as a screen reader does
    /// (`AccessibilityRequest.focus`), then draws one frame. An element the
    /// last frame found unfocusable keeps focus where it was.
    public func focus(_ element: TestElement) throws {
        _ = try accessibilityTree
        platformWindow.simulateAccessibilityRequest(.focus(element.id))
        tick()
    }

    // MARK: Helpers

    /// The one element `matches` accepts, or the query's error.
    func single(_ query: String, _ matches: (TestElement) -> Bool) throws -> TestElement {
        let found = try elements(where: matches)
        guard let first = found.first else { throw TestHarnessError.noElement(query) }
        guard found.count == 1 else { throw TestHarnessError.ambiguous(query, count: found.count) }
        return first
    }

    /// Every node of `tree` reachable from its roots, pre-order, each node
    /// once.
    static func preOrder(_ tree: AccessibilityTree) -> [TestElement] {
        var result: [TestElement] = []
        var seen = Set<AccessibilityNodeID>()
        var stack = Array(tree.roots.reversed())
        while let id = stack.popLast() {
            guard seen.insert(id).inserted, let element = TestElement(id, in: tree) else { continue }
            result.append(element)
            stack.append(contentsOf: element.children.reversed())
        }
        return result
    }
}
