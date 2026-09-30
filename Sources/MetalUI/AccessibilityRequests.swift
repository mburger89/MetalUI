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
