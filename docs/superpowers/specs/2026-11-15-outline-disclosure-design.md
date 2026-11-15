# Design draft: hierarchical lists (`OutlineGroup`, `List(_:children:…)`, `DisclosureGroup`)

Status: DRAFT for Alloy review, 2026-11-15. Base: MetalUI master 2fbfcafc. SwiftUI signatures read from the MacOSX27.2 SDK SwiftUI.swiftinterface.

## 0. Today, and the one conflict

- `List<Data, Row>` (Sources/MetalUI/List.swift:228) is data-driven only (`Identifiable`), uniform and variable rows, single and Set `selection:`. No `List(content:)`, no Section in List, no `.listStyle`, no `id:` keypath (divergence 84).
- Lazy engine: `LazyStackEngine` (LazyStack.swift:166) over `LazyUnitSource`s (LazyUnits.swift), `LazyLinePlanner` (LazyCore.swift:105), `RowExtentIndex`, 32-line cold frame. `ForEach` of `Section`s already flattens as nested units (Section.swift:176) — the precedent for a tree.
- `.contextMenu(forSelectionType:primaryAction:)` is **not built** (listed absence). `ClickDispatch` doesn't publish click count.

**Conflict.** App-owned expansion in SwiftUI is only possible through recursive `DisclosureGroup(isExpanded:)` inside `List(selection:) { ForEach … }` — `OutlineGroup` has no expansion binding. To know which children are expanded groups, any engine must evaluate the row content of every row inside an expanded folder (cheap evaluation, no layout). So:
- Content form (`List { ForEach { DisclosureGroup(isExpanded:) } }`): per frame O(rows in expanded folders) of light evaluation until lane 8, then O(window) on scroll frames when the model is `@Observable`.
- Data form (`List(_:children:)` / `OutlineGroup`): O(expanded folders + window) from lane 3.

## 1. API (class A unless marked)

- `DisclosureGroup<Label: Element, Content>`: `init(content:label:)`, `init(isExpanded:content:label:)`, `Label == Text` forms with `LocalizedStringKey` and `StringProtocol` (`@_disfavoredOverload`), with and without `isExpanded:`. Content is `@escaping`, evaluated only when expanded. `LocalizedStringResource` forms absent (R).
- `OutlineGroup<Data, ID, Parent, Leaf, Subgroup>` (SwiftUI's five generics), four inits: root/data × Identifiable/`id:` keypath, `children: KeyPath<DataElement, Data?>`. Works in VStack/LazyVStack too. `OutlineSubgroupChildren` placeholder (M).
- Content-form `List`: `init(selection: Binding<V?>, content:)`, Set twin, `init(content:)` (amends divergence 84). Row selection value: `.tag(_:)` first, else ForEach element id when it casts.
- Outline `List` inits exactly as SwiftUI (Set / optional / `@_disfavoredOverload` non-optional / none, plus `id:` twins), each literally `List(selection:) { OutlineGroup(...) }`.
- `.contextMenu(forSelectionType:menu:primaryAction:)` on both List forms.
- Not offered (R): `DisclosureGroupStyle`, Table outlines, `.listStyle`, Section in List.

## 2. Flattening and identity

- One engine: content `List` runs `LazyStackEngine` behind a new `ListContentEngine` (selection, keys, AX). Data List untouched.
- New unit sources: `DisclosureGroup: LazyFlattenable` → label unit + (expanded ? content units : []); `LazyTreeForEachSource` (prefix sums per element, O(depth·log siblings) locate); `OutlineGroupSource` (reads `children` only for expanded nodes).
- `OG-C` extends `LZ-B`: a Component whose content flattens, and the taken branch of an if/else, stay lazy inside a tree.
- Identity: nested named scopes per depth, same in both forms; moving a file to another folder gives new identity (as SwiftUI, probe P-I1). Selection/scroll ids are the element ids, so **ids must be unique across the whole tree**.
- Expansion: controlled `isExpanded:` read during flatten, written only from input (chevron, keys, AX, ⌥-cascade). Uncontrolled DisclosureGroup: state slot, collapsed initially. Uncontrolled OutlineGroup: one slot per subgroup (as SwiftUI's per-subgroup @State): collapsing an ancestor keeps descendants' expansion (probe P-E5).
- `OutlineIndex` cache in the list's lazy origin: rebuilt only on expansion change or failed validation; validated per frame in O(expanded groups + window). Lane 8 adds an observation session for the content form.

## 3. Keyboard, selection, focus

- List is the single focusable; rows aren't (FC-F).
- Extract `ListSelectionController<ID>` from List.swift (1028–1289) over "id at position / position of id"; both forms use it.
- Keys (defaults per NSOutlineView, confirmed by probe P-K): ↑↓ move; → expands a collapsed group (expanded: first child if SwiftUI does that); ← collapses, or moves to parent; ⌥→/⌥← expand/collapse all descendants (for `isExpanded:` bindings: one level per frame, since unbuilt descendants' bindings are unknowable). Collapsing an ancestor of the selection: per P-K7. Key moves reveal the lead.
- Chevron click toggles without selecting (P-C1); ⌥-click cascades. Row click selects.
- Primary action: add `ClickDispatch.clickCount`; double-click (the clicked row) or Return (the selection) → `primaryAction`. Secondary click → menu(row ∈ selection ? selection : [row]); empty space → menu([]).

## 4. Accessibility

- Neutral model gains outline level, expanded, disclosed-by, and expand/collapse actions.
- macOS: list stays `.outline`, rows `AXRow`/`AXOutlineRow` with disclosure level, `isAccessibilityExpanded` (settable, disabled-gated), disclosedBy/disclosedRows (realised rows); triangle child if probe P-A shows one.
- SDL/AccessKit: `TREE` / `TREE_ITEM` with expanded + level, EXPAND/COLLAPSE actions; rows nested under their realised parent row. AccessKit 0.23 names verified in lane 5.

## 5. Animation

- Chevron rotates 0°→90° under the toggle's transaction; click animates with the probed curve, bare binding writes snap unless the probe says otherwise.
- Eager contexts: existing insertion fade (XF-H).
- Lazy list: new splice animation (OG-H) — rows after the splice slide by the inserted height, inserted rows fade in, removed rows ghost from the previous scene; realised rows only; Reduce Motion → cross-fade.

## 6. Performance (counts, never times)

- Collapsed subtree: 0 content evaluations / 0 children reads.
- Warm scroll frame: realised units and layout work identical for 500 and 100k outline rows.
- Data form: validations = expanded groups + window; 0 rebuilds on scroll frames.
- Expanding a 10k-child folder: one rebuild that frame, zero next frame, realised = window.
- Gated: `METALUI_RUN_100K_OUTLINE_TEST=1 swift test --filter anOutlinesWorkIsTheSameFor100kPathsAsFor500`; demo `METALUI_OUTLINE_DEMO=1`.

## 7. Bookkeeping

Prefix `OG-` (A API … J look), decisions doc `docs/superpowers/2026-11-15-outline-disclosure-decisions.md`; divergence labels 1085–1094 reserved (expected: tree-wide unique ids, no listStyle, unobserved out-of-window change re-indexes when realised, one-level-per-frame ⌥ cascade over bindings, splice animation realised-only, AX disclosed rows realised-only, SDL nesting, maybe → behaviour). Human-check group OG. Probes: `docs/probes/swiftui-outline.swift` (geometry per style, keys, chevron click, expansion retention, identity, animation, AX, contextMenu primaryAction) and `docs/probes/swiftui-disclosure-group.swift`.

## 8. Lanes (each a PR)

0. SwiftUI probes recorded + decisions skeleton (gate: no look/key values ship unmeasured).
1. `DisclosureGroup` in eager contexts (state, chevron, fade, AX).
2. Lazy flatten through DisclosureGroup/Component/if-else in LazyVStack.
3. `OutlineGroup` + `OutlineIndex`.
4. Content `List(selection:content:)` + outline `List` inits; `ListSelectionController` extraction (behaviour-neutral for the data List).
5. Outline keys and accessibility (AppKit + AccessKit).
6. `contextMenu(forSelectionType:menu:primaryAction:)` + click count.
7. Lazy splice animation.
8. Performance: content-form observation cache, counters, gated 100k test, demo.

## 9a. Alloy's answers (2026-11-15) — binding

1. Content form. Model is `@Observable` classes; expanded set lives on the model. Alloy adopts only after lane 8. **After lane 8, an idle frame (no scroll, no model change) does zero outline evaluation; Alloy's steady-frame guard (ViewRerunTests) must not rise — lane 8 owes a count test for this.**
2. Look: `.sidebar`.
3. Ids unique tree-wide (repo-relative path).
4. ⌥ cascade one level per frame is fine; no cap.
5. Collapse with a hidden selection: follow SwiftUI/NSOutlineView per probe.
6. Out of scope: type-select, drag-and-drop/onMove, rename-in-place, multi-select.
7. Expanded folder scroll: whatever SwiftUI does per probe.
8. Persist expansion only.
Requests: (a) Reveal: setting ancestors' `isExpanded = true` and `ScrollViewReader.scrollTo(path)` in the same transaction must land the row in view — test it (lane 4 or 5). (b) Order: lanes 0–6, then 8, then 7. (c) Selection is `Binding<String?>`, set programmatically for reveal.

## 9. Open questions for Alloy (answered above)

1. Is the tree model `@Observable` classes or value snapshots? Is O(rows in expanded folders) light evaluation per frame acceptable in the recursive `DisclosureGroup(isExpanded:)` form until lane 8? Or would `List(_:children:)` with internal expansion + your own persistence via `onChange` do?
2. Which SwiftUI look: `.sidebar` (typical for a project tree), default, or `.inset`? MetalUI offers one, no `.listStyle`.
3. Are ids unique across the whole tree (e.g. full paths)? Required.
4. ⌥-expand-all on huge trees: per-frame cascade OK? Cap it?
5. Collapsing a folder containing the selection: follow SwiftUI/NSOutlineView (pending probe) or keep the hidden selection?
6. Out of scope for now: type-select, drag-and-drop / onMove, rename-in-place, multi-selection?
7. Should a newly expanded folder scroll its children into view?
8. Should expansion state persistence also cover scroll position?
