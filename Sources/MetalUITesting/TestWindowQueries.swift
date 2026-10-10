import MetalUI

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

    /// The element with the window's keyboard focus, or `nil`.
    public var focusedElement: TestElement? {
        get throws {
            let tree = try accessibilityTree
            return tree.focused.flatMap { TestElement($0, in: tree) }
        }
    }

    /// Asks the window to perform `action` on `element` as a screen reader
    /// does (`AccessibilityRequest`), then draws one frame. Several actions in
    /// the set run in the order press, increment, decrement, show-menu.
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
        var handled = !requests.isEmpty
        for request in requests where !platformWindow.simulateAccessibilityRequest(request) {
            handled = false
        }
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
