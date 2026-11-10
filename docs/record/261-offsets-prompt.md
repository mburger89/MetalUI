# 261. `selectedOffsets:` with `prompt:` (Alloy gap G29, `VT-K`)

Branch `feat/textfield-offsets-prompt` (master `1b281127`). Decision `VT-K` in `docs/superpowers/2026-11-09-vertical-text-field-decisions.md`. Class `M` (the offsets binding is MetalUI-only, `SL-Q`); no divergence added or retired. Record 260 is open PR #260's.

- **API.** `TextField(_:text:selectedOffsets:prompt:)` and `(_:text:selectedOffsets:prompt:axis:)`, each the offsets initialiser plus `applyPrompt` (`VT-J`); not macOS 15. The closeout map has a class-`M` row ahead of the class-`A` `prompt:` row.
- **`onChange:` spellings.** Not given `prompt:`: they are MetalUI-only controlled forms with no SwiftUI counterpart, so there is no spelling to mirror (`VT-K`).
- **Tests** (`Tests/MetalUITestingTests/OffsetsPromptTests.swift`, plain imports; guard 22 in `Tests/MetalUITests/VerticalTextFieldCompileGuards.swift`, `typecheckFile`).
- **Mutations** (each alone, restored):

| mutation | reddened |
|---|---|
| M1 `applyPrompt` dropped from both new initialisers | `anOffsetsFieldDrawsItsPromptInThePromptsColour` (both spellings; the prompt string and colour); the two tests that find the field by its prompt label error too |
| M2 the new initialisers not forwarding `selectedOffsets` | `theOffsetsBindingStillTracksTheCaret` (both spellings) |
| M3 the `axis:` form not setting the axis | `theVerticalOffsetsFieldGrowsPerLineLimit` |
| M4 both initialisers renamed away (external spelling does not resolve) | `selectedOffsetsAndPromptCombineFromAnExternalModule` (guard 22 positive arm fails) |

Counts: see the line in `CLAUDE.md`.
