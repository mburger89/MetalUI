# 433: `CommandGroupPlacement.saveItem` (`MN-AT`)

Class `A`, no divergence row. Branch `feat/save-item-placement`, base master `e051f257`. Requested by the Alloy code-editor app: its File menu wants Close Tab ⌘W, Close Window ⇧⌘W, Save ⌘S, Save As… ⇧⌘S and Save All ⌥⌘S, and there was no placement to replace or re-key the standard Close. Ruling: `docs/superpowers/2026-10-02-menus-popovers-decisions.md`, `MN-AT`.

## What changed

- `CommandGroupPlacement.saveItem` (public, documented). The standard Close, in `MenuBarModel`'s AppKit builder and in `buildDrawn` (the drawn bar, which SDL draws, so the portable menu is the same code), is now `group(.saveItem, [standard Close])`. `before:`, `after:` and `replacing:` work as for every placement.
- Nothing else builds a File Close: the two builders were the only places (`grep` for `.close` standard actions: `Commands.swift` and the AppKit bridge's selector table, which only maps an item's action).
- Default menus unchanged: the standard item is numbered where it was (AppKit File Close id 10, drawn id 1), so ids, order and separators are the same; pinned.

## What ⌘W does when `.saveItem` is replaced

- With an app item on ⌘W: the window's shortcut pipeline (commands one stage after `Button`) fires it once; the standard Close is not in the bar, so it cannot also fire.
- With no close item: the bar has no Close, ⌘W is not claimed and does nothing, as SwiftUI. The title-bar close button and `Window.close()` are not menu-routed (`performClose` is reached only through the standard item's selector) and still close the window.

## Tests and mutation

`CommandsTests`: `theDefaultFileMenuIsUnchangedByTheSaveItemPlacement`, `theSaveItemGroupTakesBeforeAfterAndReplacing` (AppKit and drawn, an empty replacement leaves no Close and no separator), `anAppItemOnCommandWRunsAndTheStandardCloseIsGone`; `CommandsCompileGuards` lists `.saveItem`. Mutation: dropping the `group(.saveItem, …)` wrapper in both builders reddens the last two (the first stays green by design).

## Not done

Human check `MSI1` (the real menu bar). The spec's "not offered" row and `Commands.swift`'s doc comment now omit `.saveItem`.
