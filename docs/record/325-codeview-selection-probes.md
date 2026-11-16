# 325 - Probes for per-view CodeView selections (`CV-AV`, `CV-AW`, `CV-AX`, `CV-AZ`)

Branch `feat/codeview-selection-probes` from master `9b612f73`. Lane 1 of the per-view-selection work (design `docs/superpowers/specs/2026-11-16-codeview-selection-state-design.md`, committed here). No product code; two probes and four **provisional** rulings in `docs/superpowers/2026-11-07-code-view-decisions.md` (`CV-AY`, the view wiring, is reserved for lane 3). Class M, no divergence.

**Probes** (macOS 27.2.1, Swift 6.4.2, compiled form, one arm per process, each run twice with byte-identical output, screen locked and no input sent; the RECORDED blocks are at the foot of each file):
- `docs/probes/appkit-shared-storage-selection.swift`: two NSTextViews, each with its own NSLayoutManager and NSTextContainer, over one NSTextStorage, one shared NSUndoManager, edits through `insertText(_:replacementRange:)`. TextKit 2 (one NSTextContentStorage, two NSTextLayoutManagers) re-run for ten arms.
- `docs/probes/swiftui-two-text-editors.swift`: two `TextEditor(text:selection:)` on one `@State` string, edits through the bound string and by typing into A's NSTextView.

**Findings.**
- SwiftUI does not move the other editor's selection (binding and NSTextView keep the old offsets, clamped to the new length). Confirms the design's premise; AppKit sharing is not SwiftUI behaviour, so no divergence.
- AppKit non-acting selection, `CV-AW`: a caret or range start at the insertion point moves **after** it (the draft said stay in front, refuted); an insertion at a range end or later changes nothing; inside a range collapses it to the insertion's end; a deletion collapses to its start; a replacement containing the caret puts it at the replacement's **end** (the draft's `start + min(o - start, newLength)` is refuted). Multi-range: untouched ranges survive an edit wholly before or after them; an overlapping edit collapses AppKit's whole selection to one caret (not followed).
- Undo, `CV-AX`: B undoing A's edit restores the change's selection in A (the registering view), not B; B follows the text. TextKit 2 restores none to A. Alloy's binding answer (restore into the pressing view) is therefore a deliberate difference from NSTextView. Coalescing: A types `ab`, B types `c` is two undo steps; one view typing `abc` is one.
- Marked text, `CV-AZ`: any edit by another view ends B's composition (text committed), before, after, at the edges of, inside or over the mark; the draft's "only an edit touching the anchor" is changed.

**Not measured.** Xcode's own behaviour (only AppKit's NSTextView); AppKit's behaviour with an input method actually composing (the arm uses `setMarkedText`, as an IME client does, not a real IME); undo while a different view is the acting view of a coalesced run beyond the two-view case.

**Bookkeeping.** `docs/rules/decision-prefixes.md` CV row, the decisions doc's next-unused line, the spec's "probe changed" notes.
