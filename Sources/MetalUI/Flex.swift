import MetalUICore
import MetalUILayout

// This file holds the flex containers: `Column` and `Row`, each `Box` with a
// `flexDirection` chosen for you. `Stack.swift` holds the one non-flex
// container, `Stack` itself (`display: .stack`).
//
// They **wrap** a `Box` rather than duplicating it, so there is one
// implementation of the three phases in the module and the two names cannot
// drift apart. They are distinct types rather than typealiases so that
// `type(of:)` reads `Column<Pair<…>>` — the spelling §4.6 uses, and the one the
// builder's type-level guard reads back.
//
// Direction is set at construction and there is no modifier for it on these
// two, because `Column(...).flexDirection(.row)` would be a `Column` that is a
// row and the type would then be lying. **That is enforced by where the
// modifier lives, not by this paragraph**: `flexDirection(_:)` is declared in
// `extension Box`, not on `StyledElement`, which `Column` and `Row` also
// conform to. It sat on `StyledElement` for one commit, and the comment saying
// it did not was the fourth shape-10 claim corrected on this branch —
// `columnCannotBeTurnedIntoARowByAModifier` is the guard now. `Box` carries it
// for callers who want to choose, and `.rowReverse` / `.columnReverse` are
// reached that way.

/// A vertical flex container: `flex-direction: column`.
public struct Column<Content: ElementGroup>: Element, StyledElement {
    var box: Box<Content>

    public init(gap: Pixels = Pixels(0), @ElementBuilder content: () -> Content) {
        var style = Style()
        style.flexDirection = .column
        // **Ruling EP-8 — `Column` and `Row` centre on the cross axis, where CSS
        // stretches.** SwiftUI's `VStack`/`HStack` centre, and ruling EP-5 takes
        // SwiftUI's answer where the two differ. It supersedes EP-6, whose
        // `stretch` answer was blocked on recursive subtree measurement that
        // content sizing then supplied.
        //
        // **EP-8, not EP-7.** EP-7 is already spent on "margins stay publicly
        // settable"; the decisions doc's header says to continue from EP-8, and
        // EP-2/EP-4 stay unassigned forever.
        //
        // **This is set here and NOT in `Style`.** The engine keeps CSS's
        // `stretch` default, so the browser fixtures (76 today) stay valid and WebKit
        // stays the oracle for the flex algorithm; the change lives strictly
        // above the engine, which is what EP-5 means by CSS being the substrate
        // rather than the design authority. `Box` is untouched and still
        // stretches.
        //
        // **What it costs an author, and it is not nothing.** A childless `Box`
        // measures 0 — content sizing did not change that — so a box with no
        // cross size now paints nothing instead of filling its container.
        // That is a louder failure than the silent one it replaces, and the
        // remedy is a cross size or an explicit `.alignItems(.stretch)`, which
        // is what the demo's sidebar and separator now say out loud.
        style.alignItems = .center
        style.gap = Axes(both: .pixels(gap))
        box = Box(style: style, content: content())
    }

    public var style: Style {
        get { box.style }
        set { box.style = newValue }
    }

    public var decoration: Decoration {
        get { box.decoration }
        set { box.decoration = newValue }
    }

    public var elementID: ElementID? {
        get { box.elementID }
        set { box.elementID = newValue }
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Content>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Content>.Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Content>.Layout,
                               prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// A horizontal flex container: `flex-direction: row`.
public struct Row<Content: ElementGroup>: Element, StyledElement {
    var box: Box<Content>

    public init(gap: Pixels = Pixels(0), @ElementBuilder content: () -> Content) {
        var style = Style()
        style.flexDirection = .row
        // Ruling EP-8 — see `Column.init` above for why this is here and not in
        // `Style`, and for what a childless `Box` now does.
        style.alignItems = .center
        style.gap = Axes(both: .pixels(gap))
        box = Box(style: style, content: content())
    }

    public var style: Style {
        get { box.style }
        set { box.style = newValue }
    }

    public var decoration: Decoration {
        get { box.decoration }
        set { box.decoration = newValue }
    }

    public var elementID: ElementID? {
        get { box.elementID }
        set { box.elementID = newValue }
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Content>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Content>.Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Content>.Layout,
                               prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
