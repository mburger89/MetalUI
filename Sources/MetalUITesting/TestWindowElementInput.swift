import MetalUI

// Input aimed at an element (ruling `HT-F`; spec §2.4, lane 2): the point
// verbs of `TestWindowInput.swift`, aimed at the centre of the element's
// `visibleFrame` — the part of it a click can reach — so a row half scrolled
// out of view is still hit inside the viewport. A zero-area visible frame is
// ``TestHarnessError/notHittable(_:)``.

extension TestWindow {
    /// A primary click at the centre of `element`'s visible frame.
    public func click(_ element: TestElement, modifierFlags: EventModifiers = []) throws {
        click(at: try aim(at: element), modifierFlags: modifierFlags)
    }

    /// A double click at the centre of `element`'s visible frame.
    public func doubleClick(_ element: TestElement, modifierFlags: EventModifiers = []) throws {
        doubleClick(at: try aim(at: element), modifierFlags: modifierFlags)
    }

    /// A secondary click at the centre of `element`'s visible frame — what
    /// opens its context menu.
    public func rightClick(_ element: TestElement, modifierFlags: EventModifiers = []) throws {
        rightClick(at: try aim(at: element), modifierFlags: modifierFlags)
    }

    /// Moves the pointer to the centre of `element`'s visible frame.
    public func hover(_ element: TestElement) throws {
        hover(at: try aim(at: element))
    }

    /// A scroll by (`byDeltaX`, `deltaY`) at the centre of `element`'s visible
    /// frame.
    public func scroll(_ element: TestElement, byDeltaX dx: Float, deltaY dy: Float) throws {
        scroll(at: try aim(at: element), byDeltaX: dx, deltaY: dy)
    }

    /// XCUITest's press-and-drag from `element`'s visible centre, held for
    /// `seconds`, to `target`'s.
    public func click(_ element: TestElement, forDuration seconds: Double, thenDragTo target: TestElement) throws {
        let start = try aim(at: element)
        let end = try aim(at: target)
        click(at: start, forDuration: seconds, thenDragTo: end)
    }

    /// Clicks `element` (a field takes the caret on a click), then types
    /// `text` into it.
    public func typeText(_ text: String, into element: TestElement) throws {
        try click(element)
        typeText(text)
    }

    /// The centre of `element`'s visible frame, or
    /// ``TestHarnessError/notHittable(_:)`` when it has no area.
    func aim(at element: TestElement) throws -> Point<Pixels> {
        let visible = element.visibleFrame
        guard visible.size.width.value > 0, visible.size.height.value > 0 else {
            throw TestHarnessError.notHittable(element.summary)
        }
        return Point(x: Pixels(visible.origin.x.value + visible.size.width.value / 2),
                     y: Pixels(visible.origin.y.value + visible.size.height.value / 2))
    }
}
