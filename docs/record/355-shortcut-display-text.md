# 355 - A shortcut's display text (`KF-AG`)

Branch `feat/shortcut-display-text` from master `a34fd90d`. Class M, no divergence. PR 1 of the shortcut design (`KF-AG` only; `KF-AH`..`KF-AL` follow separately).

**Finding:** `MenuPanel.shortcutText` upper-cased the key string, so a named key (the private-use arrows, Home, F-keys) drew as a blank box in a drawn menu; apps had no public text for a shortcut.

**Change:** `KeyboardShortcut.Platform` (`.macOS`/`.linux`/`.windows`, `CaseIterable`, `current` by compile-time `#if`, `primaryModifiers`), `KeyboardShortcut.displayText` and `displayText(for:)`, all over one internal `ShortcutText.format` that `MenuPanel.shortcutText` also calls. Tables are in `KF-AG` item 4. Modifiers are shown as stored; `.primary` resolves at compile time, so another platform's text of a `.primary` shortcut shows the host's modifier.

**Tests:** `ShortcutDisplayTextTests` (macOS glyph table, Linux and Windows name tables, F1/F12/F20/F35, Super vs Win, `⇧⌘P`, `[.control,.shift]`+p on Linux, `displayText == displayText(for: .current)`, `primaryModifiers`, ß, a drawn menu row with an up-arrow shortcut). Mutation: the old `key.uppercased()` path in the formatter reddens the named-key tests and the drawn-row test. `MenuPanelLabelTests` unchanged and green. Cost: no view structure change.
