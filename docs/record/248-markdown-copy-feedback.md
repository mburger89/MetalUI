# Record 248: markdown copy button identifiers and "Copied" feedback (Alloy gap G15)

Branch `feat/markdown-copy-button-polish` (master `ab869fda`). Ruling `BM-L` in `docs/superpowers/2026-11-07-block-markdown-decisions.md`. Class `M`, no divergence. One new public property, `MarkdownTheme.codeCopyButtonIdentifierPrefix`.

## 1. The gap

`BM-K` (record 240) shipped the copy glyph with a label only, and no sign a press worked. Alloy found the button by its "Copy code" label in tests and had a 1.5 s checkmark stopgap.

## 2. What was built

- `codeCopyButtonIdentifierPrefix: String?` (default nil). The index is derived: `markdownCodeBases` / `markdownCodeItemBases` hand each block the count of code blocks before it (`codeBase` on `MarkdownBlockView`, quote, list and item; `codeIndex` on the fence). Only counted with a prefix.
- `MarkdownCopyButton` (in `MarkdownCodeBlock.swift`): own component with `@State presses`, a trigger `phaseAnimator` over `idle, pressed, copied`, `copied` held by `.linear(duration: 1.5)`. Glyph `checkmark` (in `BundledSymbols`, Lucide `check`) and label "Copied" while not `idle`.

## 3. The finding that shaped it

A trigger change while the animator sits in the last phase re-enters that same phase, and `PhaseStepping.enter` holds an equal phase for 0, so a plain `[idle, copied]` animator ended the window at once on a second press. Measured by the restart test; the `pressed` phase (hold 0, drawn as `copied`) fixes it. Mutation "no pressed phase" reddens `aSecondPressRestartsTheWindow` alone.

## 4. Tests and mutations (`MarkdownCopyButtonTests.swift`, 6 tests)

| Mutation | Reddened |
|---|---|
| a paragraph counts toward the index | `eachCopyButtonCarriesItsCodeBlockIndex`, `indicesAreStableWhileTheDocumentGrows` |
| lists not counted | `eachCopyButtonCarriesItsCodeBlockIndex` |
| identifier never written | the same two, and `aPressShowsCopiedForOneAndAHalfSeconds` (it reads `x0`) |
| hold 3 s / 0.5 s | `aPressShowsCopiedForOneAndAHalfSeconds`, `aSecondPressRestartsTheWindow` |
| no `pressed` phase | `aSecondPressRestartsTheWindow` |
| label fixed "Copy code" | `aPressShows…`, `aSecondPress…`, `theAccessibilityActionAlsoShowsFeedback` |
| glyph fixed | `aPressShowsCopiedForOneAndAHalfSeconds` (compares the drawn images) |

The `BM-K` tests (record 240) stay green, including that a press does not reshape the code.

## 5. Carried

A theme flag to turn feedback off; a failed write shows nothing; a standalone `MarkdownBlockView` in a lazy stack numbers every block from 0 (no public base). Human check BM6 extended.
