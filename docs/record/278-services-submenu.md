# 278. The Services submenu, `CommandGroupPlacement.systemServices` (Alloy G38, `MN-AO`)

Branch `feat/services-menu` (master `09d57f8e`). Ruling `MN-AO`. Class `A`; no divergence.

A SwiftUI app's application menu is About, Settings, Services, Hide group, Quit. MetalUI's lacked Services.

- New `CommandGroupPlacement.systemServices` (SwiftUI has it; the gap brief guessed it did not, sosumi shows it). The AppKit-style menu builds it between `.appSettings` and `.appVisibility`, one separator between non-empty groups.
- Default content: an empty `.submenu` item "Services" with the new `StandardMenuAction.services`. `AppKitMenuBar` assigns the `NSMenu` it builds to `NSApp.servicesMenu` (at install and at each `menuNeedsUpdate` rebuild); AppKit fills it.
- Drawn and SDL menus: no Services; additions at `.systemServices` go in File after the Settings additions.
- No earlier `servicesMenu` or requestor code existed; `METALUI_SERVICES_DEMO` is the unrelated platform-services demo.

Pinned (fail-before): see `MN-AO`'s mutation paragraph. Human check: group `MN`, Services submenu lists services and acts on a selected text field.
