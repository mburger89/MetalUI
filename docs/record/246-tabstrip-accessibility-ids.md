# Record 246: per-tab accessibility identifiers (Alloy gap G13)

Branch `feat/tabstrip-accessibility-ids` (master `e630e2c7`). Ruling `TBS-J` in `docs/superpowers/2026-11-07-tab-strip-decisions.md` (next `TBS-K`). Class `M`; no divergence added.

## 1. What was asked and built

Alloy's tests found a tab or its close button only by label. `TabStripItem` (`Sources/MetalUI/TabStrip.swift`) gains `accessibilityIdentifier: String?` (the tab button) and `closeAccessibilityIdentifier: String?` (its close button), each a trailing defaulted `init` parameter of the same name. Every earlier spelling compiles. Each is written with `.accessibilityIdentifier(_:)` on the label (`TabStripLabel`) or the close slot (`TabStripCloseSlot`), the path any button's identifier takes into the AX node (`declarations.identifier`, AppKit `AXIdentifier`, AccessKit `author_id`). `nil` writes nothing. Nothing is derived from `id`. Both identifiers are in `isSame(as:)`, so a changed one rebuilds an `.equatable()` strip.

## 2. Findings along the way

- The label's `if item.isDirty` branch and the identifier made four builder branches; the nil branch must not write `""`, which would give every node an empty identifier (mutation M4).
- The close identifier lands on a non-closable tab's hidden, inert button too, as its label does.

## 3. Tests

`Tests/MetalUITestingTests/TabStripTests.swift` (+3, now 18): `aTabAndItsCloseButtonCarryTheirOwnIdentifiers` (found by `element(identifier:)`, label, role, dirty value and press intact, the two identifiers independent), `aStripWithoutIdentifiersHasNoneInItsTree`, `anIdentifierStaysWithItsItem` (a reorder, a removal and a changed identifier on an `.equatable()` strip).

## 4. Mutations (each alone, filtered `--filter TabStripTests`, restored after)

| Mutation | Reddened |
| --- | --- |
| tab identifier write dropped (both dirty branches) | `aTabAndItsCloseButtonCarryTheirOwnIdentifiers`, `anIdentifierStaysWithItsItem` |
| close identifier write dropped | `aTabAndItsCloseButtonCarryTheirOwnIdentifiers`, `anIdentifierStaysWithItsItem` |
| `isSame` ignores both identifiers | `anIdentifierStaysWithItsItem` |
| nil writes `""` on the tab button | `aStripWithoutIdentifiersHasNoneInItsTree`, `aTabAndItsCloseButtonCarryTheirOwnIdentifiers` |

## 5. Counts

Native build, `swift package clean` first, unfiltered `--no-parallel`: `Test run with 5719 tests in 26 suites passed after 421.762 seconds` (0 failures; `FR-J no-argument frame: succeeded=true`). `closeout-inventory-check.sh`, `closeout-undocumented.sh` and `record-05-check.sh` print nothing. The CLAUDE.md Counts line is not re-taken here.
