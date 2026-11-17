# 365 — `.focused` on a container reads focus within (`FW-A`..`FW-C`)

Class `A`, no divergence, no public API. Alloy could not tell which `TerminalView` had focus: its pane wrapper is not focusable and MetalUI's `.focused` read only the focused element's own binding. The probe `docs/probes/swiftui-focus-container.swift` shows SwiftUI reads a container's binding true while focus is within it and that writing it focuses the first focusable descendant (even from a later one); MetalUI now does the same, so `TerminalView` needs no parameter.

- `Sources/MetalUI/Focus.swift`: `FocusRegistry.focusBindings(within:)`, `firstFocusable(within:)`.
- `Sources/MetalUI/Window.swift`: `reconcileFocusStates` reads the chain; `applyPendingFocusStateWrites` clears on a container's binding and focuses a non-focusable container's first focusable descendant.
- Tests: `Tests/MetalUITestingTests/FocusWithinTests.swift` (5), `Tests/MetalUITerminalUITests/TerminalViewFocusWithinTests.swift` (1). Mutations shown red: reconcile on the element's own binding (reddens 1, 2, the write test and the cost test), write refused for a non-focusable target, last instead of first descendant, clear needing the element's own binding.
- Cost: no element request beyond the `.focused` wrapper's own (4 without, 5 with, steady and keystroke), one settling frame when focus leaves the container, none for an idle frame or a move within it.
- Decisions `docs/superpowers/2026-11-17-focus-within-decisions.md`. Next record 366.
