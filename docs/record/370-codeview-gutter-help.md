# 370 - `CodeView.gutterHelp` (`CV-BT`)

Branch `feat/codeview-gutter-help` from master `9dc1e9a8`. Class M, no divergence (labels untouched). Wave-2 design item (b), Alloy request.

**API.** `CodeView.gutterHelp(_ text: @escaping @MainActor (CodeGutterHit) -> String?) -> CodeView`.

**Mechanism.** In `CodeView.prepaint`, a `ContextualAttachment` whose `helpProvider` (`MN-AJ`) maps the region-local point to bounds space, asks the last frame's `plan.gutterHit(at:)` and answers `text(hit)`; any other point goes to the view's existing `helpProvider` or static `help`. The menu and selection menu of the existing attachment are kept. No state write, no element, no per-frame work: the provider runs in `trackTooltip`, in input.

**Tests** (`CodeViewGutterHelpTests`): per-hit answers with fallback to the view's `.help`; no view help gives no tooltip in the text area; the tooltip follows bar to bar with the delay; the provider is not called on steady frames; steady and keystroke costs equal with and without the modifier. Mutations are in the doc comments.
