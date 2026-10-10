import MetalUI

// Input aimed at an element (ruling `HT-F`; spec §2.4, lane 2).
// RED STUB (lane 2): every verb does nothing.

extension TestWindow {
    /// A primary click at the centre of `element`'s visible frame.
    public func click(_ element: TestElement, modifierFlags: EventModifiers = []) throws {}

    /// A double click at the centre of `element`'s visible frame.
    public func doubleClick(_ element: TestElement, modifierFlags: EventModifiers = []) throws {}

    /// A secondary click at the centre of `element`'s visible frame.
    public func rightClick(_ element: TestElement, modifierFlags: EventModifiers = []) throws {}

    /// Moves the pointer to the centre of `element`'s visible frame.
    public func hover(_ element: TestElement) throws {}

    /// A scroll at the centre of `element`'s visible frame.
    public func scroll(_ element: TestElement, byDeltaX dx: Float, deltaY dy: Float) throws {}

    /// XCUITest's press-and-drag from `element` to `target`.
    public func click(_ element: TestElement, forDuration seconds: Double, thenDragTo target: TestElement) throws {}

    /// Clicks `element`, then types `text` into it.
    public func typeText(_ text: String, into element: TestElement) throws {}
}
