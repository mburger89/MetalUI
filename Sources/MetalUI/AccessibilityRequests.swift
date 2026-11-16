import MetalUICore

/// What an accessibility client's selection request dispatches to a `List`
/// (plan task 12 part 2, ruling `IX-AA` item 1): the rows to select, by their
/// element ids. Internal — only `List(selection:)` registers a handler for it,
/// and only `Window.handleAccessibilityRequest` sends it.
///
/// **An `Action`, so it rides the registry the keyboard already uses** (as
/// `AccessibilityAdjustment` does, AB-I): `Handlers` gains no member, and the
/// disabled gate in `Frame.registerHandlers` — which registers no action for a
/// disabled element — is the whole of "a disabled list refuses".
///
/// `rows` replaces the selection: one row for `AXSelected` (LA2, LB3), exactly
/// the given rows for `AXSelectedRows` (LA3, LB2). A single-selection list
/// ignores more than one row (LA4).
struct AccessibilityRowSelection: Action {
    let rows: [GlobalElementID]
}

/// What an accessibility client's expand or collapse request dispatches to an outline row (`OG-F`): the wanted state.
/// Internal; a content `List` registers a handler for it on each group row, and `Window.handleAccessibilityRequest`
/// sends it for AppKit's `AXDisclosing` set and AccessKit's `EXPAND`/`COLLAPSE`, and for a press on the row's triangle.
///
/// An `Action`, so it rides the registry and its disabled gate (a disabled list registers none, so nothing is
/// advertised and the request is refused), as `AccessibilityRowSelection` does.
struct AccessibilityDisclosure: Action {
    let expand: Bool
}

/// What the tree builder and `Window` send a split view's divider (ruling `HS-K`): `.query` fills the answer the divider
/// publishes (its value, its range, its orientation, whether it can move), `.set` moves it as a drag would. Internal.
///
/// An `Action`, so it rides the registry and its disabled gate as `AccessibilityDisclosure` does: a divider in a
/// disabled subtree registers none, so it publishes no value to set and a set request is refused.
struct SplitterAccessibility: Action {
    enum Request {
        case query(Answer)
        case set(Double)
    }

    /// What a query fills. A class, so the handler (which returns `Void`) can hand it back.
    final class Answer {
        /// The size in points of the pane before the divider (`AXValue`, probe `swiftui-split-divider-ax.swift`).
        var value = 0.0
        /// The sum of the two panes either side (`AXMaxValue`; the minimum is 0).
        var total = 0.0
        /// Whether the divider's line is vertical (an `HSplitView`'s).
        var isVertical = true
        /// Whether a drag could move the divider at all (the panes' limits leave it room).
        var canMove = false
    }

    let request: Request
}
