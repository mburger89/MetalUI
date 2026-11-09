# Record 250: title-bar insets stale after a live resize (follow-up to record 249)

Branch `fix/title-bar-insets-after-resize` (master `4a7a898f`). Ruling `AS-R` items 8 and 9. No public declaration, no divergence.

## 1. Bug

With `.windowTitleBarMetrics(height: 68, controlsLeading: 27)`, `titleBarInsets.left` was 87 at launch and about 78 after one live resize, while the buttons stayed placed.

## 2. Cause and fix

`AppKitWindow.titleBarInsets` reads the zoom button's frame when asked; `Window` asks while building a frame, and `onResize` requests that frame. A resize resets the buttons, the host's resize reports the geometry mid-reset, and `TitleBarPlacement`'s deferred pass (one run-loop pass later) moves the buttons back with nothing reporting again. Fix: `TitleBarPlacement.onReplaced`, called by the deferred pass when `writeCount` moved, wired to `syncSurfaceGeometry()`.

## 3. Test and mutation

`appKitTitleBarInsetsArePublishedAgainAfterTheReplacement` records the insets each `onResize` sees over three real `setFrame`s and requires the last to be the settled value. Mutation: the `onReplaced` call removed from the deferred pass: the test reddens (`published.last == settled`, three times). Restored, it passes.

## 4. Bug 2 (carried)

A disabled control in the band registers no hitbox (`EV-E`), so it carves nothing from the drag region (SDL) or from the unclaimed band press (AppKit, `AS-J`). Same before `AS-R`; a taller band widens it. See `AS-R` item 9.
