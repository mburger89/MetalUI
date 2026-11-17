# `.focused` on a container: focus within (prefix `FW-`) — decisions

Alloy request: its pane wrapper (a non-focusable container) could not learn which `TerminalView` had focus; the view keeps a private `@FocusState` on its own `.focusable()` surface leaf. Branch `feat/focused-within-container`, record 365, class `A` (SwiftUI parity), no divergence, no public API. Probe `docs/probes/swiftui-focus-container.swift` (arms `F0`..`F5`, macOS 27.2.1).

Next unused id: `FW-D`.

## FW-A: a container's binding reads true while focus is within it

1. **SwiftUI** (`F0`, `F2`, `F3`, `F4`, `F5`): `.focused($flag)` / `.focused($f, equals: v)` on a view that is not focusable reads `true` / `v` while a descendant holds focus (a `.focusable()` leaf, a `TextField`), and `false` / `nil` when focus is elsewhere or cleared. Two panes on one `FocusState<P?>` read their own value; a leaf's own binding reads true at the same time (`F0`: `container=true,inner=true`). A `.focusable()` container (`F1`) takes the seat itself, as before.
2. **MetalUI**: `Window.reconcileFocusStates` reads the bindings on the focused element **and every ancestor of it** (`FocusRegistry.focusBindings(within:)`, a walk of `GlobalElementID.parent`, empty and allocation-free when no element carries a binding), nearest first; a state reads the nearest binding naming it. Before, only the focused element's own binding counted. A clear (`false`/`nil` write) applies when the focused element **or a container around it** carries the binding; written while focus is outside, it leaves focus alone (`F5` t4).
3. **Cost**: nothing per frame when focus does not change. The walk runs once per drawn frame in the window's between-frames reconcile, only when a `@FocusState` was bound, adds no element request (the `.focused` modifier's own wrapper element is the one it always cost: literal 4 requests steady and keystroke without, 5 with, `aContainerBindingCostsNoRequestAndOneWritePerChange`), and writes the state only when it changed (an idle redraw is one frame, a move inside the container no extra frame, leaving it exactly one more).

## FW-B: writing a container's value focuses its first focusable descendant

SwiftUI (`F0` tick3, `F3`, `F5` t2, t5): writing `true` / the value to a container's state focuses its **first focusable descendant**, from outside it and also from inside it on a later descendant (`F5`: focus on `b`, `c = true` moves it to `a`). MetalUI: `Window.applyPendingFocusStateWrites` focuses the bound element if focusable (unchanged), otherwise `FocusRegistry.firstFocusable(within:)`, the first entry of the tab order that is the container or inside it; a container with no focusable descendant leaves focus where it is (`IX-J` item 2's rule). Before, a write naming a non-focusable element was refused.

## FW-C: `TerminalView` gains nothing

`TerminalView`'s init stays frozen (`TRM-B`): Alloy wraps it in a container and binds `.focused($pane)` / `.focused($pane, equals:)` on the wrapper. The view's private `@FocusState` on its surface leaf is unchanged and reads true at the same time. No `onFocusChange` and no `isFocused:` parameter (SwiftUI has no such modifier; not invented). Pinned by `TerminalViewFocusWithinTests`.

Unmeasured: a mouse press into a descendant (the focus movers all end in the same `focusedElement` write, so the container follows; the press path is `FC-A`'s), Full Keyboard Access, and a container inside a `List` row.
