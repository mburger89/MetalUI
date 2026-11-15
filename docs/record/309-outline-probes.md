# 309 - Outline and disclosure probes (`OG-`, lane 0)

Branch `feat/outline-probes` from master `2fbfcafc`. Lane 0 of the hierarchical-list work (design `docs/superpowers/specs/2026-11-15-outline-disclosure-design.md`, committed here): no product code, only the SwiftUI probes, the decisions skeleton and the bookkeeping. The gate of the design (lane 0): no look or key value ships unmeasured.

**Probes.** `docs/probes/swiftui-outline.swift` (a `List(selection:)` read through the NSOutlineView SwiftUI builds; arms `P-L1`..`P-L4` geometry and look, `P-K1`..`P-K7` keys, `P-C1` chevron click, `P-E5` retention, `P-I1` identity, `P-N` animation, `P-A` accessibility, `P-M` context menu and primary action, `P-R1` reveal; the full output is `docs/probes/swiftui-outline.recorded.txt`) and `docs/probes/swiftui-disclosure-group.swift` (`D1`..`D4`, `P-A3`). Run in both SA-O forms; macOS 27.2.1, Swift 6.4.2, screen unlocked.

**What the probes found (the surprises, against the design draft).**
- `.sidebar` is 32 pt rows (default and `.inset` 24), 12 pt per level, labels at 25, 37, 49; **a leaf's label is at its sibling group's x** (it reserves the chevron slot). Selection highlight inset 10 each side, full row height, radius about 8.
- **The chevron is not rotated**: the glyph is swapped on the button state (right-pointing 5 x 8 pt, down-pointing 8.5 x 5 pt). The design's "chevron rotates 0 to 90" is wrong for macOS.
- **Keys:** → on an expanded group does nothing (not the first child); ← on a leaf or a collapsed child goes to the parent; ⌥→ on a collapsed group expands every descendant and, in the content form, writes all their `isExpanded` bindings in one turn (including rows never built); ⌥→ on an already expanded group does nothing.
- **Collapsing an ancestor of the selection** keeps the hidden id in the binding (no write) with no selected row; ↓ then selects the first row and ↑ the last.
- **The chevron click does not select.** A double-click on a group does not toggle it; Return runs `primaryAction`.
- **Uncontrolled outlines keep descendants' expansion** across an ancestor's collapse. **A moved node's `@State` resets.**
- **Animation:** a chevron click slides the rows below over about 245 ms (AppKit's curve); a bare `isExpanded = true` snaps; `withAnimation` slides over the same 245 ms (its duration is ignored). A standalone `DisclosureGroup` honours `withAnimation` (503 ms for 0.5 s) and snaps on a bare write.
- **Reveal:** `scrollTo` in the same transaction as the expansion, or on the next main-queue turn, does NOT land the row in view in SwiftUI (60 frames); one frame later it does (row bottom on the view's bottom). The requester's "same update" is stronger than SwiftUI (`OG-D`).
- **AX:** a row's expansion attribute is `AXDisclosing` (settable), not `AXExpanded`; the row's cell holds an `AXDisclosureTriangle` with `AXPress`.
- **Context menu:** the set is `{clicked row}` without changing the selection, `{}` on empty space.
- A standalone `DisclosureGroup`: 24 pt label row, no indentation, the content a centre-aligned stack.

**Unmeasured (and why).** The selection highlight colour (the snapshot cannot capture the material blend and the probe process is not the active app); real mouse events through SwiftUI's own gestures (synthetic events are swallowed by the cell hosting view, so clicks went to the AppKit views); a real right-click popup; SwiftUI's own accessibility elements (an `AXUIElement` client of the process saw only application-role elements, the in-process tree of the hosting view is empty), so a standalone `DisclosureGroup`'s AX (`P-A3`) and the default click animation (`D3c`) are open.

**Method notes (for the next probe).** A process that is not the active app never has a key window, and a table view in a non-key window ignores clicks: the probe's window class answers `isKeyWindow` true. A click on the disclosure triangle goes through the NSApp queue; every other click goes to `NSOutlineView.mouseDown` with the mouse-up queued first (the table's tracking loop consumes it). A backgrounded run of a probe with offscreen windows is throttled to a crawl: run it in the foreground.

**Bookkeeping.** `docs/superpowers/2026-11-15-outline-disclosure-decisions.md` (`OG-A`..`OG-J`, all provisional, next `OG-K`); prefix registered in `docs/rules/decision-prefixes.md`; divergence labels 1085-1094 reserved in `CLAUDE.md`/`AGENTS.md`. Number 309 follows 307; 308 is held by the open PR `feat/image-max-pixel-size`.
