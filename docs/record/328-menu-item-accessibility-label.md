# 328 - A menu item's `.accessibilityLabel` (`MN-AQ`)

Branch `feat/menu-item-accessibility-label` from master `facb1f63`. Class `M`, no divergence. Alloy's request: a session menu item whose title is the session name with a tinted dot and whose VoiceOver label is "<name>, <status>", written `Button { … } label: { Label(name, systemImage: "circle.fill") }.tint(.green).accessibilityLabel("\(name), \(status)")`.

**Probe** (`docs/probes/swiftui-menu-item-accessibility.swift`, macOS 27.0, run twice, byte-identical): the request's premise does not hold on the `NSMenuItem` API. SwiftUI's `SwiftUIMenuItem` carries none of `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityIdentifier`, `.accessibilityValue` wherever it is written (Button, Button after `.tint`, Label, Text, Image, Toggle, Menu, disabled, empty), closed or open under `popUp`: `accessibilityLabel()` is the title, the title and `attributedTitle` unchanged. `.help` is honoured as `toolTip`. Unmeasured: the real AX tree (the in-process `AXUIElement` query returned no role), a pull-down `Menu`'s menu, `CommandMenu`. Placement on the Label vs the Button is therefore moot for SwiftUI.

**Landed** (the `MN-AL` precedent, MetalUI-only): `.accessibilityLabel` on a `Button`/`Toggle`/`Menu` item -> `MenuNode.accessibilityLabel` -> `PlatformMenuItem.accessibilityLabel`; `NSMenuItem.setAccessibilityLabel` (title unchanged); the drawn menu's row node publishes it as its label. A label on the `Text` inside the button's label is not read; an empty one is none. `MenuContent` stays closed; no steady-frame cost (menus evaluate at open): 1 element request with and without labels. `Backends/SDL` untouched (the drawn menu is the portable `MenuSession` path).

**Not added:** `accessibilityHint`/`accessibilityValue` on items (nothing to match; `.help` is the hint).

**Tests** (`MenuItemAccessibilityLabelTests`, `AppKitMenuTests`), each shown red under a mutation: `Button._menuNodes` dropping the label; the drawn row publishing the title; `setAccessibilityLabel` dropped; a wrapper added to the cost shape.

**Not run:** a human VoiceOver pass over a native menu (an agent cannot); the drawn menu on Linux/Windows (portable path, covered by the macOS suite).
