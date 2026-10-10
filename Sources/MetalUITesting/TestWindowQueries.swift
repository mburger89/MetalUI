import MetalUI

// Queries over the published accessibility tree (ruling `HT-G` items 1, 3,
// 4): XCUITest's model — identifier, label, role — on the tree the window
// last handed its platform, so a query that works is also a VoiceOver fact.
// RED STUB (lane 2): every query throws or answers nothing.

extension TestWindow {
    /// The accessibility tree the window last published.
    public var accessibilityTree: AccessibilityTree {
        get throws { throw TestHarnessError.notRecorded("accessibility") }
    }

    /// The one element whose `.accessibilityIdentifier` is `identifier`.
    public func element(identifier: String) throws -> TestElement {
        throw TestHarnessError.noElement("identifier \"\(identifier)\"")
    }

    /// The one element whose accessible name is `label`.
    public func element(label: String) throws -> TestElement {
        throw TestHarnessError.noElement("label \"\(label)\"")
    }

    /// Every element of `role`, in tree order.
    public func elements(role: AccessibilityRole) throws -> [TestElement] { [] }

    /// Every element `predicate` accepts, in tree order.
    public func elements(where predicate: (TestElement) -> Bool) throws -> [TestElement] { [] }

    /// The element with the window's keyboard focus, or `nil`.
    public var focusedElement: TestElement? {
        get throws { nil }
    }

    /// Asks the window to perform `action` on `element`.
    @discardableResult
    public func performAccessibilityAction(_ action: AccessibilityActions, on element: TestElement) throws -> Bool {
        false
    }

    /// Moves keyboard focus to `element`.
    public func focus(_ element: TestElement) throws {}
}
