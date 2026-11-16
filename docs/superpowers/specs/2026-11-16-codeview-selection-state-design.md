# Design draft: per-view selections for CodeView over a shared CodeBuffer

Status: DRAFT for Alloy review, 2026-11-16; probes run 2026-11-15 (record 325), their changes marked "probe changed". MetalUI master 9b612f73. Prefix `CV-`, next id `CV-AV`; record 325.

## 0. Today
- One selection list on the buffer (`storedSelections`, CodeBuffer.swift:68; `selections`, `primarySelection`, `select(_:reveal:)`, `revealSerial` 153-171), moved in `applyEvent` (328-359) by `mapSelectionOffset` (199-205); sticky caret only for `.typing`/`.paste` (353-357). Undo groups store undo/redo selections; undo/redo write them back; one coalescing flag `openKind`.
- Every view reader goes through the buffer: plan (CodeViewPlan.swift:461-463, reveal 545-551, marked text 465-487, blink 778-790), session (CodeEditSession.swift: find 284, undo/redo 328/330 …), copy (CodeView.swift:306-316). Already per-view via the plan: `CodeTextAnchor.caret`, `caretRect()`, IME caret rect, blink state.
- Accessibility and the text input client expose no selection today (CV-U; `selectedRange` is {0,0}, CV-AA) — nothing to change now.
- Alloy reads the buffer selection at CodePanel.swift:214,219,319-321,393-403,581; SideBySideView.swift:71,88; Workspace.swift:1479,1495; ~10 test sites.

**SwiftUI check:** `TextEditor(text:selection:)` keeps a per-view `Binding<TextSelection?>`, but record 242's probe (SL-P) shows an external change to the text does NOT move a bound selection (old offset kept, clamped). So the requested "an edit in one view moves the other's caret" is NSTextView-with-shared-NSTextStorage / Xcode behaviour, not SwiftUI's. CodeView is class M, so following AppKit/Xcode needs no divergence; the record will say SwiftUI was checked.

## 1. Ownership (recommended: B with C's compatibility)
A `CodeSelectionState` object (`@Observable`, main actor), registered weakly with the buffer and moved eagerly by every edit — same pattern as the existing weak `CodeEditCursor` registry and `CodeScrollState` + `.scrollState(_:)`. The buffer's existing selection becomes its built-in **default state**; all existing buffer selection API forwards to it, so single-view users and every existing test are unchanged. A view with no state uses the default (two such views still share a caret). Alloy opts in by giving each split its own state. Rejected: (A) keyed sets on the buffer (leaks keys, wakes every view); (C) alone (two code paths).

## 2. API
```swift
@MainActor @Observable public final class CodeSelectionState {
    public init(buffer: CodeBuffer, selections: [CodeSelection] = [CodeSelection(caret: 0)])
    public var buffer: CodeBuffer { get }
    public var selections: [CodeSelection] { get set }       // sorted, merged, ≥1; a write ends undo coalescing
    public var primarySelection: CodeSelection { get }
    public private(set) var revealSerial: UInt64
    public func select(_ range: Range<Int>, reveal: Bool = true)
    @discardableResult public func replaceSelections(with text: String, origin: CodeEditOrigin = .typing) -> CodeTransactionID
    @discardableResult public func replace(_ range: Range<Int>, with text: String, origin: CodeEditOrigin = .programmatic) -> CodeTransactionID
    @discardableResult public func transaction(_ body: (CodeBuffer) -> Void) -> CodeTransactionID
    @discardableResult public func undo() -> Bool
    @discardableResult public func redo() -> Bool
}
extension CodeBuffer { public var selectionState: CodeSelectionState { get } }        // the default state
extension CodeView { public func selectionState(_ state: CodeSelectionState) -> CodeView } // state.buffer === buffer
```
Edits made through a state record it as the **acting state** (its before-selections, sticky caret, coalescing). Reference type, not a Binding, because an edit elsewhere must move this view's selection immediately from inside the buffer. A new split: `CodeSelectionState(buffer:, selections: source.selections)`.

## 3. Edit transformation
- Every edit moves every other live state by the existing rule: before unchanged, after shifted, inside → `start + min(o − start, newLength)` (a deletion collapses to its start), then each state normalizes (merging carets).
- Sticky only for the acting state; other carets exactly at the insertion point **move after it** (**probe changed the draft**: it said "stay in front"; AppKit pushes them after, CV-AW). A replacement containing a caret puts it at the **end of the replacement** (probe changed `start + min(o - start, newLength)`).
- External edits move every live state non-sticky.
- Undo: one stack per document. Groups record the acting state's selections; `state.undo()` replays (all states move) then writes the group's selections into **the state that undid** — ⌘Z in view B brings B's caret to the change even if A made it (Xcode). **Probe: AppKit restores the change's selection into the view that made the edit, not the one that pressed Cmd-Z** (CV-AX); Alloy's answer 3 stays binding, so this is a deliberate difference from NSTextView.
- Coalescing per state: an edit from a different state ends the run (typing in A then B is two undo steps).
- A state an edit didn't move isn't notified (B's line:col UI doesn't wake for edits after B's caret).
- IME: a composition stays in its view, anchored at its own state's caret, moved by other views' edits; **any edit by another view ends the composition** (**probe changed the draft**: AppKit ends it for every foreign edit, not only one touching the anchor; the composed text is committed, CV-AZ). Commit goes through the composing view's state.

## 4. Other readers → per view
Plan, reveal (`revealSerial` per state; changing a view's state reveals nothing), caret-into-view after a key (only the editing view), session commands (press/drag/moves/select-all/delete/cut/paste/newline/indent/undo/redo), find ⌘G (selects and centres only in the stepping view), copy, caret-anchored popovers/overlays/completion, caret blink (another view's edit restarts the focused view's blink, as an external edit does today). Hover/go-to-definition clicks are pointer-based: unchanged. AX/IME selected range: nothing now.

## 5. Tests and probes
Buffer: default state = buffer selections (compat), independence, edit moves other states (table), sticky only for the acting state, undo restores into the undoing state, no cross-state coalescing, external edits, released states dropped, unmoved state not notified.
View: two carets, typing in A moves B's caret not B's scroll, view without a state follows the buffer, reveal per state, swapping state reveals nothing, copy/cut/paste per focused view, find per view, undo in the other view, marked text survives/dropped, `.caret` anchor follows the view's state, A's arrow key doesn't replan B.
Probes: `docs/probes/appkit-shared-storage-selection.swift` (two NSTextViews over one NSTextStorage + shared undo manager: insert at/before/after the other caret, deletions/overlaps, multi-range, undo/redo from the other view, marked text while the other edits); a SwiftUI two-TextEditors arm confirming the "not moved" finding.

## 6. Bookkeeping
Rulings CV-AV (ownership) … CV-AZ (marked text); amend CV-P, CV-V, CV-AE, CV-I, CV-D/CV-F. Record 325. No divergence (class M). Inventory family `code-selection-state` (M); api-overview; migration note (additive). Human check in group CV. Demo split arm in `METALUI_CODE_DEMO`.

## 7. PRs
1. Probes (settle sticky rule, undo target, marked-text drop). 2. Buffer: `CodeSelectionState`, acting state, default-state forwarding, eager moves, per-state coalescing (no view change). 3. View wiring + tests + demo + docs. 4. Alloy: per-view state in `OpenDocumentView` and its call sites.

## Open questions for Alloy
1. When a group splits, does the new view copy the source view's caret and scroll (Xcode), or start at the top?
2. `Workspace` (AlloyCore) selects through `doc.buffer`; per-view states live in AlloyKit's `OpenDocumentView`. Should `open(revealLine:)`/`open(_:selecting:)` take a selection target, or should AlloyCore own a per-(pane, path) state map?
3. One undo stack per document with ⌘Z restoring the caret in the view that pressed it — OK? (Per-view undo not recommended.)
4. Should Chat mode's file panel and a Code-mode group on the same file share a state? Does the caret carry over on a mode switch?
5. Plain and side-by-side presentations of one view: one shared state (the diff toggle keeps the caret)? Assumed yes.
6. Inactive-colour selection in unfocused splits (`CodeTheme.inactiveSelection`, as Xcode)? Out of scope unless asked.
7. Persist per-view carets across relaunch? (`[CodeSelection]` is plain data the app can save.)

## Alloy's answers (2026-11-16) — binding; design approved as drafted
1. Split copies the source view's selections and scroll (`CodeSelectionState(buffer:, selections: source.selections)` + scroll-state copy).
2. AlloyCore owns states in a per-(PaneID, path) map; `open(…, in: pane)` selects through that pane's state. **`CodeSelectionState` must live in the `MetalUICodeBuffer` module** (AlloyCore links it, not MetalUI's UI module).
3. One undo stack per document; ⌘Z restores into the view that pressed it.
4. Chat's file panel and each Code group are separate states; Alloy seeds a new pane's state itself (needs only `init(selections:)`).
5. Plain and side-by-side share one state.
6. Inactive selection colour: later, separate item.
7. No persistence now.
