# App shell, presentations, platform services

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**`Deferred`** is a portal: one child, no layout node, hoists to the root
layer, resets clip and scroll offset but **not opacity** (`OM-AA`). A
`Deferred` whose content is `.position(.absolute)` is a **presentation root**
(`LR-CH`…): laid out in its own run before the root; its containing block is
always the window. An absolute box outside a `Deferred` is a permanent
refusal by name.

**App icon** (`AI-`, record §70): `App.icon: [ImageBitmap]` is the one
application-wide, runtime-settable icon (default `[]` = never touch the
platform's own; every assignment calls `Platform.setApplicationIcon` once with
the list sorted smallest first and `width × height` duplicates dropped). SwiftUI
has no runtime icon API (bundle asset catalog), so it is MetalUI-only by design.
**The alpha rule**: `ImageTexture` is premultiplied sRGB — AppKit wraps the
bytes as stored (`premultipliedLast`, never re-premultiplied, `AI-E`); SDL
icons are straight alpha, so `SDLIcon.straightRGBA` un-premultiplies (`AI-F`).
SDL applies the icon to every open and later window and cannot clear it.
`AppKitPlatform.run()`'s re-assignment is unpinned (`AI-K`, human check O1).
Packaging (bundle/`.desktop`/`.ico`) is build-side: `docs/packaging.md`.
**The shader resource bundle is found by `ShaderLibrary`, never
`Bundle.module`** (`AI-N`): `MetalUI_MetalUIRender.bundle` goes in an `.app`'s
`Contents/Resources` on both build systems; a missing one makes `App.init`
throw `ShaderLibraryError.resourceMissing` naming every directory tried, not
trap. A new resource lookup in `MetalUIRender` goes through
`ShaderLibrary.resourceBundle(candidates:)` too.

**Menus, popovers, tooltips (`MN-`, record §74).** A secondary press is its own
`InputEvent` and **never presses, taps, drags or focuses** (divergence 110);
`.contextMenu { }` (both vocabularies, a closed `MenuContent` evaluated at each
open) goes to the platform through the defaultless `PlatformWindow.presentMenu`
— a native `NSMenu` on AppKit, MetalUI's drawn menu where it answers `false`
(SDL) — and the choice returns as a queued `InputEvent.menuAction`, run under
`StateDispatch`. `App.commands { CommandMenu/CommandGroup }` reaches
`Platform.setMenuBar` (every AppKit app gets the standard main menu); **the
window's shortcut pipeline is the one shortcut path** (`Button` first, commands
one stage after, AppKit offering a ⌘- or ⌃-key to it before the main menu,
once; a ⌃-key not while composing — `MN-J`, `MN-AI`). `.popover` is an anchored presentation root, flipped then clamped
inside the window, no arrow, dismissed from input; `.help` is the accessibility
hint plus a drawn, tick-timed tooltip. The new handler member `contextual` is
non-opaque and sits inside the `allowsHitTesting` gate; **a new accessibility
role/request needs a row on both bridges**; a new `StyledElement` modifier
cannot follow a legacy `.popover` (divergence 115).

**Platform services (`SV-`, record §77).**
`.fileImporter`/`.fileExporter`/`.alert`/`.confirmationDialog` are one
transparent `PresentationScope` (no node, no id level; the record lives in the
window's registry keyed `$presentation<depth>`, never a `StateTable` slot; a
legacy decoration after it lands on its content, `ES-A`; divergence 120 retired); they present
after the frame, one in flight per window (`FileDialogs` async calls share the
slot, `.busy`), and answers come back as queued `InputEvent`s that the window
claims first (`SV-B`, `SV-K`, `SV-AH`). AppKit shows sheets (`NSOpenPanel`,
`NSSavePanel`, `NSAlert`); SDL shows file dialogs and **declines alerts, which
the window draws and holds modal** (`AlertPanel.swift`: an input stage ahead of
the menu, Return the default, Escape the cancel, `SV-AK` item 1). SDL
drains the main queue each iteration (`SV-H`; macOS cannot see it, only the
Linux image can). `Window.minSize`/`maxSize`/`windowResizability` reach the
platform through `setContentSizeLimits` only on change; `.automatic` asks the
content nothing (divergence 126); SDL's bridge lifts the maximum before
raising the minimum (`SV-AG`). **Hover is `Handlers`' seventeenth member, a
non-opaque region through the one ranking** (`SV-N`); the opaque and draggable
hitboxes carry no hover attachment (`SV-AH` item 2); `.pointerExited` clears
the sticky pointer. **`Divider` is a view** whose axis is `Frame`'s stack,
pushed by every linear container and read only by layout (a new container owes
a `withStackAxis`, `SV-AK` item 2); `.pickerStyle(.menu)` opens a native menu or
the **scrolling** drawn one, options recorded without layout, widths cached on
the window (`SV-AK` items 3–6). A demo section's alert builds in a `Component`
at layout, never in the tree's own function (`SV-AK` item 7).

**Field chrome, environment objects, toolbar (`MD-`, record §79).** `TextField`
draws SwiftUI's bordered field by default (24 tall, `.surface` fill,
`.separator` border, the control focus ring from `controlActiveState`;
`.textFieldStyle(_:)`/`.textEditorStyle(_:)` on the control or a container,
innermost wins, `MD-B`, `MD-C`); caret, selection and IME are untouched.
A legacy container sees through a `layoutPriority` layer (`MD-G`).
`@Environment(Type.self)` reads an `@Observable` object provided by
`.environment(_ object:)`, nearest writer wins, a missing one traps
(divergence 134, `MD-H`). `.toolbar`/`.searchable` are one transparent
`ToolbarScope` (not an `Element`: write it inside the root's first container,
`MD-S`) over a **closed item set** (divergence 135); the platform seam is the
defaultless `PlatformWindow.setToolbar(_:) -> Bool` — a native `NSToolbar` on
AppKit, **`false` on SDL, where the window draws a 39-point strip under the
named root `$toolbar` and lays the root out below it** (`MD-K`, `MD-Z`;
divergence 136); outcomes return as queued `InputEvent.toolbarAction`.

**App shell (`AS-`, record §87).** `Window.onCloseRequest` answers
`CloseRequestReply` (`.now`, `.cancel`, `.later` plus `replyToCloseRequest(_:)`);
`close()` never asks, `performClose()` does; `App.onTerminateRequest`/
`replyToTerminateRequest(_:)`/`terminate()` hook a quit, and **with no app handler
the walk asks every window in turn and owns the end** (a `.later` pauses it, the
window's real close resumes it); closing one of several windows no longer
terminates and the last close ends the app asking nobody (`AS-B`, `AS-C`,
`AS-K`). MetalUI-only by ruling: SwiftUI has no veto API. The platform seam is
**eleven defaultless requirements** (seven on `PlatformWindow`, four on
`Platform`; a conformer adds them, `AS-H`, `AS-J`); AppKit asks through
`windowShouldClose` and `AppKitApplicationDelegate`, SDL through
`SDL_EVENT_WINDOW_CLOSE_REQUESTED`/`SDL_EVENT_QUIT` with its quit-on-last-window
hint off (`AS-L`). `.navigationTitle`, `.navigationDocument` and `.onOpenURL`
are three transparent `EnvironmentWrite` cases (no node, no id level, first
report in post-order wins, handlers run in reverse post-order under
`StateDispatch`); `Window.title`/`isDocumentEdited`/`representedURL` reach the
platform on change only (SDL records the edited marker and path, no-ops).
`windowStyle: .hiddenTitleBar` lays the root **under** the bar (divergence 175)
and `@Environment(\.titleBarInsets)` is stamped by `Window` from the
platform's *answer* (on SDL the band and the drawn buttons' cluster, `CW-D`; zero where the
platform answers `false`); an unclaimed primary press in the band drags the
window (`AS-J`). An open-document event goes to the key window with a handler,
else the first window with one, else `App.onOpenURL`, never a new window (divergence 176);
AppKit delivers no launch argument, so `App.open(_:)` is the recipe (`AS-M`);
URLs arriving before `App`'s initialiser are dropped (`AS-Q`). A test never
calls a real `performClose(_:)` (its nested loop ends the process, `AS-O`
item 7).

**SMK port gaps (`SG-`, record §89).** `Platform.setMenuBar(_:) -> Bool` (defaultless;
`true` AppKit, `false` SDL): where it answers `false` and the app declared `commands`, **every
window draws the bar** — a 25-point strip above the toolbar strip under the named root `$menubar`
at cursor index 2 (a name, not a slot; `noteNamed`), titles are `Text`+`onClick` (opens on the
click; divergence 195), a `MenuSession` remembering the bar index (hover switches, Left/Right
wrap), **F10** an unclaimed-key stage after `onKeyPress` and the command stage
(`MenuBarStrip.swift`); the model's drawn style has no application menu, and its Edit items are
delivered as AppKit's seven keys (Delete `\u{7f}`) and enabled only while a text field is
focused. **`EventModifiers.primary`** (`.command` on Apple, `.control` elsewhere) is the default
of every shortcut, so macOS is value-identical and `.command` stays Super off Apple (`SG-B`);
`SystemFonts.designFamilies` registers monospaced/serif lazily (`SG-C`); the cross-platform
manifest names the two portable-text products unconditionally (a SwiftPM defect, `SG-D`);
**`Window.drawnChromeHeight`** is the bar plus the strip, and an explicit `minSize`/`maxSize` is
measured below it (`SG-F`). A `Component`'s prepaint record is one heap box (`ComponentPrepaint`,
`SG-E`).

**Presentation extras (`BG-`, record §144).** `.presentationBackground` (colour, token, `Material`, gradients, `alignment:content:`) is a reported preference read **only by `.popover`'s panel**, innermost wins, a report outside a presentation bracket is nothing; a `Material` goes through `Frame.fillMaterial` and the panel then has **no drop shadow** (`BG-A`…`BG-F`, `BG-P`; `anchoredOverlay`, alerts and menus ignore it). `Window.backgroundDragBehavior: WindowInteractionBehavior` (divergence 736): only `.enabled` drags from a press no stage claimed, AppKit through `performTitleBarPress(clickCount: 1)` (**never `isMovableByWindowBackground`**), SDL through one more `ChromeRegions` candidate carved by every blocker, dropped whole at the 64-rect cap (`BG-G`…`BG-J`); the band is untouched. `PointerStyle.shape(_:eoFill:size:hotSpot:fill:outline:)` is SwiftUI's visionOS spelling made MetalUI's own (divergence 735): a CPU raster resolved into the existing image cursor at send time, one cursor per value (`BG-K`…`BG-M`), no seam requirement. No `Retained*.swift`, no `Handlers` member, no shader; divergences 735-737 (738-744 unused); group `BG`.

**Clipboard beyond text (`CB-`, record §115).** `.copyable(_:)`, `.cuttable(for:action:)` and
`.pasteDestination(for:action:validator:)` are SwiftUI's signatures (probe arm S) over MetalUI's own synchronous `Transferable`
(spell `MetalUI.Transferable` beside CoreTransferable), on every `StyledElement` and once on proposal content (the
`KeyboardModifier` layer, `ClipboardAttachment` a class box in `KeyboardAttachment`'s fifth field, `Handlers` stays nineteen).
**One stage, `dispatchClipboardKey`, after `onKey` and before the context-menu key and every shortcut** (`CB-B`): exact
`EventModifiers.primary` + C/X/V for an element holding focus or an ancestor of it, innermost first; the Keymap, `onKeyPress` and a
focused text field (whose path is untouched, `CB-M`) still win; the Edit menu needs no code (AppKit's `cut:`/`copy:`/`paste:` and the
drawn bar already send these keys). A copy writes **the first item**, one representation per exported type, the text fallback being the
type's own `.utf8PlainText` entry (`CB-C`; since `CP-` every item, divergence 456); a paste walks the **destination's** `importedContentTypes()` against the
platform's list and **declines** (the next stage runs) unless the action ran (`CB-P`). **Four defaultless `PlatformWindow` requirements**
(`writeClipboard(_ representations:) -> Bool`, `clipboardTypeIdentifiers()`, `readClipboard(identifier:)`, `setClipboardCommands(_:)`;
`CB-E`; every conformer, the headless platform and every fake implements them, migration note); the text-only pair stays. AppKit's
identifier is the pasteboard type; **SDL's mime is a pure table plus `application/x-` + the identifier with every byte outside
`[a-z0-9.+-]` percent-encoded** (`ClipboardMime`, `CB-D`). **SDL's data callback is pure**: one `malloc`'d box copied at copy time, a
lookup by mime, a pointer into the box, one cleanup that frees (`CB-H`, `CB-Q`) — no Swift closure, no actor hop, so any thread is safe;
zero-byte representations are dropped, an all-empty write keeps the clipboard (`CB-I`). Enablement is by presence, not the validator
(divergence 455, provisional until `CB1`). `Window.clipboard` is the MetalUI-only imperative API, no public initialiser (`CB-J`); an AppKit
test uses a private `NSPasteboard(name:)`, never `.general` (`CB-K`). Not built: `@Environment(\.clipboard)` (SwiftUI has none on macOS, `CP-A`), multi-item and `PasteButton`
and lazy export are built since `CP-` (below). The demo is `METALUI_CLIPBOARD_DEMO=1`.

**Clipboard extras (`CP-`, record §142).** `PasteButton` (SwiftUI's two initialisers, no label, class A/D) is a `Button` underneath (no new role, no bridge row), enabled
iff some clipboard item offers a type the payload imports, and a click reads **every** importable item once; it never goes through `dispatchClipboardKey`. Its snapshot is
`ClipboardAccess`, read **lazily by the first button that lays out** and invalidated by `PlatformWindow.setClipboardChangeHandler` (SDL's `SDL_EVENT_CLIPBOARD_UPDATE`,
AppKit's `changeCount` polled at becoming key, own writes and presses, headless on a change); `Window` redraws for it only while the last build held a button
(`pasteButtonCount`), and a button under `.equatable()` refuses retention by the taint `pasteButton` (`CP-H`). **Several items:** `copyable`/`cuttable`/`Clipboard.write` write
all, a paste imports all and calls the action once, `readAll`/`itemCount`; AppKit N `NSPasteboardItem`s, **SDL holds one mime set per clipboard so item 0 goes out natively and
more than one item adds the private `ClipboardItemPack` mime** (a malformed pack falls back to item 0, divergence 715). **Lazy export:** `ClipboardBytes.later` runs at read on
AppKit and headless, at write on SDL (a pure-C callback cannot call Swift, `CB-H`), `copyable`/`cuttable` lazy, `Clipboard.write` eager, `CB-I` exact there (divergence 716). **Four
more defaultless `PlatformWindow` requirements** (`writeClipboard(items:)`, `clipboardItems()`, `readClipboard(item:identifier:)`, `setClipboardChangeHandler(_:)`; every
conformer, the headless platform and every fake implements them, migration note). `Handlers` stays nineteen; the stage order and the text-field path are untouched.

**Window activation (`WA-`, record §165).** `PlatformWindow.orderFrontAndMakeKey()` and `Platform.activate()` have no default (two verbs: order one window front, activate the application); `Window.makeKeyAndOrderFront()` and `App.activate()` call them and do not change `controlActiveState` themselves (the platform reports it back). SDL cannot activate an application, so `SDLPlatform.activate()` is the nearest honest answer; AppKit's bodies are checked by human group WA only. `Color(hex:)` is public.
