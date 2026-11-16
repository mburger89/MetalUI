# 323 - A per-tab context menu on `TabStrip` (`TBS-O`)

Branch `feat/tab-context-menu` from master `f9e2af33`. Class `M` (MetalUI-only), no divergence. Alloy's request: "Split Right / Split Down" on a tab.

**API.** `TabStrip.tabContextMenu(_ menu: @MenuContentBuilder (ID) -> M)`, an instance method beside `onCloseTab(_:)`. SwiftUI's `TabView` has no tab context menu on macOS and a `TabStrip`'s tabs are `TabStripItem` data, not views, so there is nowhere to write `.contextMenu`; the id-taking closure mirrors `onCloseTab` and `MN-Q`'s attachment is reused underneath. Not compared by `==`, like every strip closure.

**Behaviour.** A secondary press on a tab, close slot included, opens the menu built for that tab's id at that open. It does not select the tab (Safari, Xcode, Chrome) and does not close it. An empty menu opens nothing; empty bar space has no menu; a strip without `tabContextMenu` shadows no outer `contextMenu` (the attachment is menu-less, one tree shape either way). Shift-F10/Menu key and an accessibility show-menu ride the attachment (`MN-G`); `.showMenu` is advertised only with a menu. Native (AppKit) and drawn (SDL) menus both get the items: the attachment is `contextMenu`'s.

**Tests** (`TabStripContextMenuTests`), each shown red under a mutation: handing the menu the selection instead of the tab id; selecting on the press; menu on the title only (close slot closes); menu on the whole strip; always attaching an empty menu (shadows an outer menu); a captured first id.

**Not run:** a human look at the menu over a real AppKit tab bar (no human-check row added).
