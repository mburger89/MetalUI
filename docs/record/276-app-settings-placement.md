# 276. `CommandGroupPlacement.appSettings` (Alloy G37, `MN-AN`)

Branch `feat/app-settings-placement` (master `ac4bd366`). Ruling `MN-AN`. Class `A`; no divergence.

Alloy wanted Settings... with Command-comma in its own group between About and the rest of the application menu. `CommandGroup(after: .appInfo)` plus a Divider put the item inside the About group.

- New `CommandGroupPlacement.appSettings`; the AppKit-style application menu is About, `.appSettings`, Hide group, Quit, one separator between non-empty groups (an empty group draws none).
- Empty by default: MetalUI has no `Settings` scene, so SwiftUI's default item has nothing to open. Apps fill it with `replacing`, `before` or `after`.
- No Services group exists in MetalUI; nothing to order against.
- Drawn style: the additions go in File before the visibility additions.

Pinned (fail-before): dropping the group from the app menu reddens the group test and the Command-comma test; moving it after visibility reddens the group test; dropping it from the drawn File reddens the drawn-bar test.
