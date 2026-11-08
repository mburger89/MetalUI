# Tab strip - decisions (prefix `TBS-`)

Alloy gap G4: a closable, reorderable tab strip for an editor's file panel. Branch `feat/tab-strip` from master `7523f587`; record 238. Class `M` (SwiftUI's `TabView` is a page switcher with no closable strip). No divergence added. Next unused: `TBS-J`.

## TBS-A: the API (agreed with the app)

`TabStrip<ID: Hashable>(selection: Binding<ID>, tabs: [TabStripItem<ID>])` with `.onCloseTab((ID) -> Void)` and `.onMoveTab((Int, Int) -> Void)`; `TabStripItem<ID>(id:title:icon:isDirty:isClosable:accent:)`. A `Component`, not a `StyledElement`: it has no style of its own and is placed like any view; its content is `some ElementGroup` (a `ProposalScrollView` is not a `ProposalElementGroup`), so it is laid out as legacy content inside a stack and takes the proposal width of its parent (a `Spacer`-bearing `VStack`, or the window root). Built from existing views only; no new platform requirement, no `Handlers` member, no seam.

## TBS-B: structure

`VStack(0) { ScrollViewReader { ProposalScrollView(.horizontal) { HStack(0) { ForEach(tabs) { TabStripTab } } } } (31 tall); 1-point .separator rule }`, 32 tall in all, `.surfaceSecondary`. One `TabStripTab` component per tab holds its hover `@State`; the label (accent bar, icon, title) and the close slot are components of their own because one tab body in one builder did not type-check in reasonable time. A tab's width is `TabStripWidthLayout`, a `ProposalLayout`: the content's natural width clamped to 96...220 **whatever the proposal**, with the content then laid out at that width. A flexible `.frame(minWidth:maxWidth:)` was tried first and is wrong here: under the scroller's unspecified proposal it clamps the frame and lets the title overflow it (the dot landed 100 points outside its tab), so truncation needs the content proposed the clamped width.

## TBS-C: the strip owns the pointer, the app owns the data and the keys

A click writes `selection` from the tab's tap gesture (input). The close button and a middle click call `onCloseTab(id)` and change nothing: the app removes the tab and moves the selection (closing the selected tab must pick a neighbour, which only the app knows). The middle click is a `DragGesture(minimumDistance: 0, button: .middle)` (`CI-F`: a middle press forms a button arena that reaches only drags naming it) whose release closes only if it lands inside the tab. **No key is bound**: ⌃Tab, ⌘1-9, ⌘W are the app's (`onKeyPress`/keymap, writing `selection`). Tabs are not focusable and a click focuses nothing (`FC-A`).

## TBS-D: the close slot

An 18-point slot ends every closable or dirty tab. A closable tab shows the × (an `Image(systemName: "xmark")`, so Lucide off Apple) while hovered or selected; a dirty tab shows an 8-point dot (`textPrimary` at 0.7) there instead **unless it is closable and hovered**; a dirty tab that is not closable keeps the dot hovered or not and has no close button. The slot's hit area and its accessibility button exist for every closable tab whether or not the glyph shows (a click that reaches it has hovered it first). Hover is the tab's `@State` written by `onHover` (input).

## TBS-E: reorder

A `DragGesture` of 4 points' slop on the whole tab. Each tab reports its width from `onGeometryChange` (a lifecycle action, so the write is legal and costs one settle build) into the strip's `@State` widths; the strip's `@State` drag holds the tab and the translation. The destination is pure (`TabStrip.destination`): the number of **other** tabs whose middle lies left of the dragged tab's middle after the translation, which is the index the tab has after `insert(remove(at: from), at: to)`. `onMoveTab(from, to)` is called **once, at the release, and never with `to == from`**; a drag under the slop is a click (it selects). While dragging the tab is drawn at half opacity and a 2-point `.accent` bar marks the edge it would land on (the destination's leading edge going left, trailing going right); the others do not shift and there is no ghost under the pointer (no z-order exists to draw one above later siblings). `onCancelled` clears the drag. SwiftUI's `onMove` takes a destination offset in the array before removal; the app asked for final indices and that is what is passed.

## TBS-F: equality

`TabStrip` is `@MainActor Equatable` over the selection's value and the items' fields (`TabStripItem.isSame`; an icon by what it draws, `Image.isSameDrawing`: symbol name, `Icon` value, bitmap texture identity, options), so `.equatable()` replays it. **The closures are not compared**, as `MarkdownView` does not compare its highlighter's calls: a handler must reach changing state through a model, not a captured copy.

## TBS-G: overflow

Tabs keep their width and the horizontal scroller scrolls (indicator never: a tab bar has none). The selected tab is scrolled into view with `ScrollViewProxy.scrollTo` from `.onChange(of: selection, initial: true)`, a lifecycle action, so it fires for a selection written by the app's key handler as well as a click and once on appearing. A vertical wheel over the strip passes to the parent (`XS-F`, PR 233); this needs nothing here.

## TBS-H: accessibility

No tab roles exist (`AccessibilityRole` has none, and a new role owes both bridges and the `Mirror` count), so the strip is a `.group` labelled "Tabs" (`accessibilityElement(children: .contain)`) of buttons: each tab a `.button` labelled with its title, selected when it is, valued "edited" when dirty (no value otherwise), pressing it selects; each closable tab a second button "Close <title>" beside it (a sibling, not a child: a button folds its descendants). A real tab-group role is carried (AppKit `AXTabGroup` with radio-button tabs, AccessKit `TAB_LIST`/`TAB`).

## TBS-I: look

Bar `.surfaceSecondary`; the selected tab `.background` (the panel it fronts) with `textPrimary` text, the others `textPrimary` at 0.62 with a 0.06 wash while hovered; a `.separator` hairline after each tab and under the bar; title 12 points, one line, tail truncation; the accent a 3 x 14 bar before the icon. All tokens, so light and dark follow the theme.
