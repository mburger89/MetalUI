# 257. Placeholder and TabStrip contrast (Alloy WCAG AA gaps, `VT-I`, `VT-J`, `TBS-K`)

Branch `fix/placeholder-tabstrip-contrast` (master `2f0b43c5`). Decisions `docs/superpowers/2026-11-09-vertical-text-field-decisions.md` (`VT-I`, `VT-J`) and `docs/superpowers/2026-11-07-tab-strip-decisions.md` (`TBS-K`); SwiftUI measurements are probe P of `docs/probes/swiftui-vertical-text-field.swift` (macOS 27). Class `A` for `prompt:`, no divergence added or retired (the live count stays 220, the next label 241).

- **Placeholder.** Drawn in `foregroundColor ?? textPrimary` x 0.45 (2.925:1 on the light surface); now `Color.secondary` resolved with no inherited style: 4.479 light, 6.741 dark (surface). The field's own colour no longer reaches it. `MultilineText.placeholderColor` is the one site (horizontal, vertical, `TextEditor`).
- **`prompt:`.** Four initialisers (`VT-J`); the prompt's string and flat/hierarchical colour are the placeholder; gradient and material lower to their representative colour.
- **TabStrip.** Ink 0.62 -> 0.64: light hovered 4.399 -> 4.669, dark hovered 4.723 -> 4.920, rest 4.903 / 5.548.
- **Tests** (`Tests/MetalUITestingTests/PlaceholderContrastTests.swift`; `aFieldPaintsItsPlaceholderCaretSelectionAndComposition` re-pinned 0.45 -> 0.588).
- **Mutations** (each alone, restored):

| mutation | reddened |
|---|---|
| M1 placeholder back to textPrimary x 0.45 | `theDefaultPlaceholderIsColorSecondaryAndReadable`, `aPromptsStyleColoursThePlaceholder`, `theTextEditorPlaceholderTakesTheSameDefault`, `aFieldPaintsItsPlaceholderCaretSelectionAndComposition` |
| M2 placeholder source `foregroundColor` again | `aFieldsForegroundColorDoesNotChangeItsPlaceholder` |
| M3 `applyPrompt` ignores the prompt's colour | `aPromptsStyleColoursThePlaceholder` |
| M4 `TextEditor` on the old rule | `theTextEditorPlaceholderTakesTheSameDefault` |
| M5 tab ink 0.62 | `anUnselectedHoveredTabStripTabsInkIsAA` |

Counts (2026-11-09): root 5793 tests in 26 suites passed, native build system, unfiltered, `--no-parallel`; `FR-J no-argument frame: succeeded=true`.
