# Menus, popovers and tooltips — decisions

Rulings for context menus, the menu bar, popovers and tooltips (user request
2026-10-02, an item of the gpui-gap priority list; **not a plan task** —
feature work after plan task 15, like drag and drop, MetalView and paths,
shadows and transforms). Spec:
[`specs/2026-10-02-menus-popovers-design.md`](specs/2026-10-02-menus-popovers-design.md).
Record: `../record/74-menus-popovers.md` (design section now; the Record phase
completes it, renumbered there if another line publishes §74 first).
Evidence (both **new**, both run twice byte-identical, outputs in their
headers):

- [`../probes/swiftui-menus-popovers.swift`](../probes/swiftui-menus-popovers.swift)
  — arm ids `C…` context menus (the `NSMenu` SwiftUI builds, synthesized
  right/control clicks, a Button's right click, nesting, disabled, empty,
  VoiceOver's show-menu, a closed menu's shortcut), `M…` the `Menu` pull-down,
  `P…` popovers (placement per edge, the default edge, screen flipping,
  `item:`, accessibility, Escape and outside clicks), `H…` `.help`.
- [`../probes/swiftui-commands.swift`](../probes/swiftui-commands.swift) —
  a SwiftUI `App` dumping `NSApp.mainMenu` without (`PLAIN`) and with
  `.commands`, and the dispatch of a shortcut bound by a menu item and a
  window `Button` three ways.

**The screen was locked for the whole design session** (lock probe:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`), so the probes are
headless: synthesized `NSEvent`s through `NSApp.sendEvent`, a view's
`menu(for:)`, the NSAccessibility walk, `NSMenu.didBeginTrackingNotification`.
The app never became active and never had a key window. Four readings are
therefore **broken instruments, not SwiftUI answers**, and every ruling that
would rest on one says "unmeasured" and names the human check that owns it:
control-click (C5c — its separating arm C5n shows a plain `NSView.menu` does
not open on a synthesized control-click either), a popover's Escape and
outside-click dismissal (P3, P3b, P4a, P4c — the popover window never became
key), the tooltip's appearance and delay (H7), and the key-window order of a
shortcut both a menu item and a window `Button` claim (the commands probe ran
with `keyWindow=nil`).

Prefix **`MN-`**, lettered. **Next unused: `MN-AJ`.** (This line moves in the
commit that appends a ruling; read the last `## MN-` heading.)

Branch `feat/menus-popovers` from `b9da519` (master: paths, shadows and
transforms merged, PR #43). Baseline at `b9da519`: **2227 tests in 3 suites,
0 goldens, 133 typecheck guards** (record §73's count line; re-taken by this
session, spec §0), **76 live divergences, next label 110**
(`docs/divergences.md` line 12).

**Carried items.** No decisions doc's "Carried…" section names a menu, a
popover or a tooltip. `App.swift`'s `openWindow` comment says "there is no
app delegate and no menu bar anywhere in the framework, so this close button
is the only way out" — `MN-I` changes that on AppKit and owes the comment.
`Deferred`'s doc names a tooltip as a portal use; `MN-P` draws tooltips
without one (the user's own `Deferred` tooltips are unaffected).
`IN-W`'s scrim, `IX-Q`'s arena and `DN-F`'s destination ranking are the
precedents `MN-E`, `MN-N` and `MN-P` follow.

---

## MN-A — Scope: what this branch builds, what it defers

**Ruling.** Build, SwiftUI-spelled and probe-backed:

1. **Context menus** — `.contextMenu { … }` on every `StyledElement` and
   every `ProposalElementGroup` (`MN-D`, `MN-E`), opened by a right press, a
   control-press on AppKit, Shift-F10 or the Menu key off Apple, and an
   accessibility show-menu request (`MN-B`, `MN-G`); presented natively
   (`NSMenu`) on AppKit and drawn in the window elsewhere (`MN-C`, `MN-F`).
2. **The menu item vocabulary** — `Button` (titled), `Toggle` (titled),
   `Menu` (titled, a submenu), `Divider`, `Text` (a disabled item),
   `.disabled(_:)`, `.keyboardShortcut` (`MN-D`).
3. **`Menu("Title") { … }`** as a pull-down button (`MN-H`).
4. **The menu bar** — `App.commands { CommandMenu…; CommandGroup… }`
   (`MN-I`), one shortcut path (`MN-J`), the standard AppKit menus with the
   Edit menu wired to the focused field (`MN-K`).
5. **Popovers** — `.popover(isPresented:arrowEdge:content:)` and
   `.popover(item:arrowEdge:content:)` on both vocabularies (`MN-L`…`MN-O`).
6. **Tooltips** — `.help(_:)` on both vocabularies (`MN-P`).
7. A demo flag, `METALUI_MENUS_DEMO=1`, and human-checks group R (spec §8, §9).

**Deferred, each named in spec §10 with its owner** (owner none unless
stated): `Picker` and `Section` and `Label`/image items inside a menu;
`Divider` as a view in a stack; menu type-select and scrolling long menus;
`.contextMenu(forSelectionType:)`, `.contextMenu(menuItems:preview:)`;
`.popover(attachmentAnchor:)`, `.presentationCompactAdaptation`, a drawn
popover arrow (divergence 112); `.menuStyle`, `.menuIndicator`,
`.menuOrder`, `primaryAction:` on `Menu`; `CommandGroupPlacement`s beyond
spec §2.5's list, `.commandsRemoved()`, `.commandsReplaced`,
`FocusedValue`/`focusedSceneValue`; an in-window menu bar on Linux and
Windows; a native tooltip on AppKit (divergence 113); `.help` on a menu item.

**Reasoning.** The request names these four features and asks for
SwiftUI's spellings; each deferred item is either a second design
(`FocusedValue` is a scene-scoped value system MetalUI has no scene for), a
renderer feature with no request behind it (the arrow), or cost the request
did not ask for (`Picker` items need the picker's option discovery, which
today runs only inside layout, `Picker.swift`'s picker scope).

**Cost if wrong.** A deferred item is one more branch; nothing here
forecloses one — the menu model is data (`PlatformMenu`), so a new item kind
is a new case.

---

## MN-B — A secondary press is a new input event, and it never presses anything

**Ruling.**

1. `InputEvent` gains `.rightMouseDown(MouseEvent)` and
   `.rightMouseUp(MouseEvent)` (AppKit's and SDL's own word for the button).
   **Migration** (as `DN-C` item 3): an exhaustive external `switch` over
   `InputEvent` adds the cases or a `default:`.
2. **AppKit**: `MetalHostView` overrides `rightMouseDown(with:)` and
   `rightMouseUp(with:)`, and its `mouseDown(with:)` delivers a
   control-modified left press as `.rightMouseDown` (with `.control` in its
   modifiers) and remembers it, so the matching `mouseUp(with:)` becomes
   `.rightMouseUp` — AppKit's documented control-click rule for
   `menu(for:)`. **Unmeasured against SwiftUI** (C5c: the synthesized
   control-click is a broken instrument, C5n), owned by human check R1.
3. **SDL**: `SDLBridge.c` stops dropping `SDL_BUTTON_RIGHT` and reports it as
   two new event kinds, mapped to the two cases; the test-injection path
   gains the same button.
4. **A secondary press runs no `onClick`, no gesture, no drag and no
   `TextField`/`Slider` press, and focuses nothing**: `Window` hands it only
   to the context-menu stage (`MN-E`) and to presentation dismissal
   (`MN-F`, `MN-N`). **SwiftUI disagrees on macOS**: a right click presses a
   plain SwiftUI `Button` (C6) and fires an `.onTapGesture` (C6t), where an
   AppKit `NSButton` ignores it (C6n); on a `Button` that has a context menu
   the right-mouse-down opened no menu and the up pressed the button (C7b,
   C7b'). **Divergence 110, kept, owner none.**

**Reasoning.** Item 4 is the one choice with a SwiftUI reading against it.
Following SwiftUI would make every existing `onClick`, tap and gesture
respond to a second button — moving hit testing and the gesture arena, both
on this branch's must-not-move list — and C7b says SwiftUI's own Button then
never shows its context menu, which is the feature being built. AppKit's
control (C6n) and Windows/Linux convention agree with MetalUI's answer.

**Evidence.** C5r (right-mouse-down begins menu tracking: `["14 items"]`),
C5l (a plain left click does not), C6, C6t, C6n, C7b, C7b', C5c/C5n.

**Cost if wrong.** An app that relies on a right click pressing a button —
rare, and arguably a SwiftUI quirk — adds a context menu or an `onKey`. The
event exists, so following SwiftUI later is a dispatch change, not a seam
change.

---

## MN-C — Native `NSMenu` on AppKit, a drawn menu everywhere else, one seam

**Ruling.**

1. `PlatformWindow` gains `func presentMenu(_ menu: PlatformMenu, at
   position: Point<Pixels>) -> Bool`, **with no default implementation**
   (`AB-R`/`EV-AB`/`DN-C`'s reason). `true` means the platform showed the
   menu itself; `false` means "draw it yourself".
2. **AppKit answers `true`**: `AppKitWindow` builds an `NSMenu` from the
   `PlatformMenu` — titles, separators, submenus, `.on` states, disabled
   items, key equivalents shown with their modifier mask,
   `autoenablesItems = false` (C1 reads `autoenables=false`) — and pops it up
   at `position` in the host view (`NSMenu.popUp(positioning:at:in:)`).
3. **SDL answers `false`**: SDL3 has no menu API; `Window` draws the menu in
   the window (`MN-F`). Every test fake answers a settable value, `false` by
   default (as `beginExternalDrag` does), and records every call.
4. **A choice comes back as input, never re-entrantly**: `InputEvent` gains
   `.menuAction(MenuActionEvent)` (`menu`: the token `PlatformMenu` carried,
   `item`: the chosen item's id, or `nil` for a dismissal with no choice).
   AppKit's popUp runs a nested tracking loop inside `presentMenu`, which
   itself runs inside `onInput`; the AppKit window therefore **queues** the
   event (`RunLoop.main.perform`) and delivers it after `presentMenu` has
   returned. `Window` runs the item's action **from input, under
   `StateDispatch.dispatching(to:)` the declaring element** (`ID-F`) — the
   same footing as an `onClick`. A token that is not the open menu's runs
   nothing.

**Reasoning.** SwiftUI builds a real `NSMenu` (C1: class `NSMenu`, 14 items,
the items' targets `menuAction:`/`submenuAction:`) and AppKit tracks it
(C5r). A native menu is the right look, keyboard behaviour, type-select and
VoiceOver for free on the platform where SwiftUI is the reference. Off Apple
there is nothing native to call, so a drawn menu is the portable
implementation; the seam's `Bool` lets one `Window` code path serve both, as
`beginExternalDrag`'s does. Queuing the choice keeps `Window`'s input
dispatch non-reentrant — a re-entrant `onInput` inside `onInput` would run a
handler while the outer dispatch holds `active`, the drag session and the
arena half-updated.

**Cost if wrong.** If the native menu proves unwanted (a look a designer
wants to own), `AppKitWindow.presentMenu` returns `false` and AppKit draws the
portable menu — a one-line change, no API move.

---

## MN-D — The menu item vocabulary: a closed `MenuContent`, evaluated at each open

**Ruling.**

1. `public protocol MenuContent` whose one requirement is `@_spi`-gated
   (`Gesture`'s precedent, `IX-B`), so it is closed to a plain importer
   (guard). `@MenuContentBuilder` is its result builder: blocks, `if`,
   `if`/`else`, `switch` and `for` (`buildArray`).
2. Conformers: `Button where Label == Text` (its title is the label's
   string; `role:` accepted, drawn the same — C1's "Delete" carries nothing
   extra), `Toggle where Label == Text` (an item with an `.on`/`.off` state
   whose choice writes `!isOn`, C1/C4), `Menu where Label == Text` (a
   submenu, C1/C3), `Divider` (a separator, C1), `Text` (a disabled item,
   C1's "Plain text item" — `disabled`), and `EnvironmentScope<Content:
   MenuContent>`: the scope's write is applied to the menu's environment and
   **only `isEnabled` is read**, so `Button("Off") {}.disabled(true)` is a
   disabled item (C1) and `.disabled(false)` under a disabled ancestor stays
   disabled (`EV-D`'s AND).
3. `.keyboardShortcut` on a `Button` item is **shown** on the item (C1:
   `key="k" mods=16`, i.e. ⌘K) and, in a context menu, **is not active while
   the menu is closed** (C12: `window.performKeyEquivalent(⌘K) -> false`,
   nothing ran). In the menu bar it is active (`MN-J`).
4. **The content closure is evaluated at each open** (C4c: the reopened menu
   is a new object and shows the toggled state), in the declaring element's
   environment and under `StateDispatch` for it, so it may read `@State`,
   `@Environment` and `@Observable` models. It is never evaluated in layout
   or paint, so a context menu costs a steady frame nothing but its stored
   closure.
5. Not offered (absence guard for `Picker`): `Picker` (C1 shows SwiftUI
   renders it as a submenu of state items), `Section` (a header plus
   separators, C1), image/`Label` items (C1's "Labelled … image"), a
   `Button` with a non-`Text` label. Owner none.

**Reasoning.** A context menu's items are data, not views: SwiftUI turns them
into `NSMenuItem`s, and MetalUI's in-window menu draws them from the same data,
so a closed protocol producing `PlatformMenuItem`s is the honest model. Reusing
`Button`/`Toggle` keeps SwiftUI's spellings; a closed protocol stops an outside
type pretending to be an item the platform cannot draw.

**Cost if wrong.** An item kind someone needs is a new conformance and a new
`PlatformMenuItem` field; the protocol's requirement is SPI, so adding one is
not a source break.

---

## MN-E — Which context menu opens, and when

**Ruling.**

1. **A context menu is a non-opaque region**, registered in prepaint at the
   element's clipped bounds, joining the one ranking: `Window` asks
   `topmostHitbox(in:at:where:)` over context-menu regions, the
   innermost/topmost wins — the inner of two nested menus at the inner view,
   the outer elsewhere (C8). A covering view without a menu on the same layer
   does not block it; a presentation on a higher layer does — `DN-F`'s rule
   for drop destinations, adopted unmeasured for menus (MetalUI's own).
2. **It is registered outside the disabled gate and outside the
   `allowsHitTesting` gate**: a disabled element's menu opens with every item
   disabled (C9: `X enabled=false`). An empty menu presents nothing and does
   not claim the press (C10: `menu: nil`).
3. It opens on the **press** (C5r: tracking began on the down), on every
   platform — not on Windows' release convention (a platform-convention
   difference, not a SwiftUI divergence; spec §10).
4. Adds no identity level on a `StyledElement` (it returns `Self`; its
   attachment rides `Handlers`, `MN-Q`) and one level on a
   `ProposalElementGroup` (`ContextualModifier<Content>`, `DN-P`'s shape);
   it writes nothing to `StateTable`.

**Evidence.** C0 (no modifier: `nil`), C1, C5r, C8, C9, C10, C12.

**Cost if wrong.** If SwiftUI lets a covering view block a menu beneath
(unmeasured; the probe's `menu(for:)` asks the hit view only, which is the
covering view), the `where:` filter changes; the region registry does not.

---

## MN-F — The in-window menu (SDL, and any platform that declines)

**Ruling.** When `presentMenu` answers `false`, `Window` opens a
**window-owned** menu panel — not an element in the app's tree, so no id, no
`StateTable` entry and no identity level anywhere — and:

1. **Places** the root at the pointer (a context menu) or below the anchor's
   bottom-leading corner (a pull-down, `MN-H`), flipped up/left where it
   would leave the window and then clamped inside it with a 4-pt margin; a
   submenu opens beside its row (right, flipped left), top-aligned with it.
2. **Draws** after everything else in the frame (above the drag preview and
   transition ghosts), in theme colours: a `.surface` panel with a
   `.separator` border, corner radius 6, the default shadow; 22-pt rows, a
   20-pt check column (`✓`), the title, the shortcut right-aligned
   (`⌘K` on Apple, `Ctrl+K` elsewhere), `▸` on a submenu row, 9-pt separator
   rows; disabled rows at 0.5 opacity; the highlighted row `.accent` with
   `.background` text. Text measures and draws through `Frame.textSystem`
   (`TS-A`) at the default control font.
3. **Takes input first**, right after an open drag session (`DN-H`): a move
   highlights the enabled row under the pointer and opens a hovered submenu
   at once (closing deeper levels when a shallower row is hovered); a click
   on an enabled action row chooses it; a press-drag-release (the opening
   press, a move, the release on a row) chooses the row under the release; a
   press outside every level dismisses all of them **and is consumed** (it
   reaches nothing beneath); a wheel event is consumed; ↓/↑ move the
   highlight over enabled rows without wrapping; → opens the highlighted
   submenu at its first enabled row; ← closes the deepest submenu; Return or
   Space chooses (or opens a submenu); Escape closes the deepest level. A
   resize, a window losing key (`controlActiveState` leaving `.key`) and a
   new menu opening dismiss it. Choosing dismisses every level, then runs the
   action exactly as `MN-C` item 4 does.
4. **Publishes** a `.menu` node (one per open level, the submenu a child of
   its row) whose children are `.menuItem`/`.menuItemCheckBox` nodes (label
   = title, value `"1"`/`"0"` for a toggle, disabled flag), focus on the
   highlighted row; a `press` on an item node chooses it (`MN-R`). Its node
   ids are synthesized under a window-reserved name that never enters
   `StateTable` — `theSevenRetentionSlotsAreMutuallyDistinct` is unmoved.

**Reasoning.** The panel is chrome the platform would draw, so it is owned
like the platform's own menu: by the window, outside the app's identity and
state. Painting it as Window-emitted primitives (the drag preview's and
ghosts' footing) keeps every id path, `StateTable` count and `TB-AH` crossing
exactly where they are. A consumed outside press is NSMenu's own behaviour on
macOS and the demo scrim's (`IN-W`).

**SwiftUI.** None on Linux/Windows; the look is gpui's model (gpui's
`ContextMenu` is an in-window overlay with keyboard navigation and a
`deferred` paint layer) adapted to MetalUI's theme — named as the comparison,
not as evidence.

**Cost if wrong.** A look; every value above is a constant in one file
(`MenuPanel.swift`).

---

## MN-G — Keyboard and accessibility openers

**Ruling.**

1. **Off Apple** (`TextEditing.platform == .other`), Shift-F10 and the Menu
   key open the context menu of the **focused element or its nearest
   ancestor with one**, anchored at that element's bottom-leading corner, as
   a stage after the raw `onKey` bubble (a caller's `onKey` claims first) and
   before shortcuts. SDL translates `SDLK_APPLICATION` (`0x40000065`) to
   AppKit's `NSMenuFunctionKey` (`U+F735`); F10 already maps to `U+F70D`.
   **On macOS** neither key opens anything (macOS has no context-menu key).
   The rule is a pure function of the key and the platform
   (`ContextMenuKeys.opens(_:platform:)`) so both rows are tested on macOS.
2. **Accessibility**: an element with a context menu advertises a new
   `AccessibilityActions.showMenu`; `AccessibilityRequest.showMenu(id)` opens
   its menu anchored at the element. AppKit's node answers
   `accessibilityPerformShowMenu()` with it (C11: SwiftUI's performs and
   opens the 14-item menu); AccessKit's `ACCESSKIT_ACTION_SHOW_CONTEXT_MENU`
   maps to it. An element without a menu does not advertise it (AppKit:
   `accessibilityPerformShowMenu` answers `false`).

**Evidence.** C11 (`accessibilityPerformShowMenu -> true, menu tracking began
["14 items"]`), C11c (the control publishes no action names either — the
modern API answers through `accessibilityPerformShowMenu`, not a name list).

**Cost if wrong.** A key a platform convention does not use; the table is one
function.

---

## MN-H — `Menu("Title") { … }` is a pull-down button; `Divider` is menu-only

**Ruling.**

1. `Menu<Label, Content>` (`Content: MenuContent`) is an `Element` and a
   `StyledElement`: `Button`'s automatic chrome around its label and a `⌄`
   indicator; a click, Space/Return when focused, or an accessibility press
   opens its menu anchored at its bottom-leading corner (native popUp on
   AppKit, the panel elsewhere). `Menu(_ title: String, content:)` is the
   `Label == Text` spelling, and only that one is also a submenu item
   (`MN-D`).
2. It publishes as a new `.menuButton` role (M1: `AXMenuButton`) — AppKit
   `AXMenuButton`, AccessKit `BUTTON` with `has_popup = MENU`.
3. `Divider()` is a `MenuContent` only. As a view (a hairline in a stack) it
   is **not offered** — it would need the enclosing stack's axis, which
   MetalUI's environment does not carry. Owner none.

**Reasoning.** The pull-down falls out of the context-menu machinery (a
different anchor, the same `PlatformMenu`). SwiftUI's `Menu` is a menu button
(M1).

**Cost if wrong.** A look (`Menu`'s chrome is `Button`'s).

---

## MN-I — The menu bar: `App.commands { }`, SwiftUI's builders, the standard menus on AppKit

**Ruling.**

1. **Spelling.** MetalUI's `App` is a class, not a `Scene`, so SwiftUI's
   scene modifier becomes a method on it:
   `app.commands { CommandMenu("Tools") { … }; CommandGroup(after: .newItem) { … } }`
   — `@CommandsBuilder`, a closed `Commands` protocol (`@_spi` requirement),
   `CommandMenu(_ name: String, @MenuContentBuilder content:)`,
   `CommandGroup(before:/after:/replacing: CommandGroupPlacement,
   @MenuContentBuilder addition:)`. Calling it again replaces the commands.
   The closure is stored and **re-evaluated** whenever the platform needs the
   bar's content and at each keystroke reaching the command stage (`MN-J`),
   so a `Toggle` item's state and a `.disabled` item stay live.
2. **The standard menus**, from the commands probe's PLAIN arm, minus what
   MetalUI has no machinery for: the application menu (About *name*, Hide
   *name* ⌘H, Hide Others ⌥⌘H, Show All, Quit *name* ⌘Q); File (an empty
   `.newItem` slot, Close ⌘W); Edit (Undo ⌘Z, Redo ⇧⌘Z, Cut ⌘X, Copy ⌘C,
   Paste ⌘V, Delete, Select All ⌘A); Window (Minimize ⌘M, Zoom, Bring All to
   Front); Help (an empty `.help` slot, not shown while empty). A
   `CommandMenu` is inserted **before Window** (SwiftUI inserts it after
   View, which MetalUI does not build — the FULL arm). Omitted, owner none:
   Services, New Window (no scene model), Close All, the window list, View,
   Writing Tools, AutoFill, Dictation, Emoji & Symbols, *name* Help.
3. `Platform` gains `func setMenuBar(_ menuBar: PlatformMenuBar)` **with no
   default** (content provider plus an action callback). **AppKit** installs
   `NSApp.mainMenu`, rebuilding each top-level menu in `menuNeedsUpdate`,
   mapping standard items to AppKit's selectors (`terminate:`, `hide:`,
   `hideOtherApplications:`, `unhideAllApplications:`,
   `orderFrontStandardAboutPanel:`, `performClose:`, `performMiniaturize:`,
   `performZoom:`, `arrangeInFront:`, `undo:`, `redo:`, `cut:`, `copy:`,
   `paste:`, `delete:`, `selectAll:` — the PLAIN arm's own actions) and a
   command item to the callback. **SDL records it and draws nothing** — Linux
   and Windows SDL windows have no menu bar; command shortcuts still work
   (`MN-J`). An in-window menu bar is deferred, owner none.
4. **The default bar is installed by every AppKit `App`**, commands or not.
   **Migration note**: an AppKit MetalUI app gains a menu bar, so ⌘Q, ⌘H,
   ⌥⌘H, ⌘W and ⌘M now act when no part of the window claims them (`MN-J`
   keeps the window first, so an app binding any of them still wins).
   `App.swift`'s "no menu bar anywhere in the framework" comment is
   corrected.

**Evidence.** The commands probe: PLAIN's full tree and actions; FULL's
"After New" after "New Probe Window", "Tools" between View and Window, Help
emptied by `CommandGroup(replacing: .help) { }`, a disabled item.

**Cost if wrong.** A standard item someone misses is a row in one table; the
migration note's behaviour change is the price of having ⌘Q at all.

---

## MN-J — One shortcut path, the window first

**Ruling.**

1. `Window`'s key pipeline gains **one stage**, the app's commands, directly
   after `dispatchShortcut` (a `Button`'s `.keyboardShortcut` through
   `FocusRegistry`) and before Tab traversal: the first **enabled** command
   item, in menu order, whose shortcut matches (`KeyboardShortcut.matches`,
   exact modifiers, `IX-F`) runs, from input. A disabled one does nothing.
   The `FocusRegistry` table stays the only place a `Button`'s shortcut
   lives; a context menu's items register nowhere (`MN-D` item 3).
2. **A keystroke fires at most one action**: a `Button` and a command bound
   to the same key — the `Button` runs and the command does not, because its
   stage comes first.
3. **AppKit** routes every command-modified key-down to `Window` **before**
   the main menu: `MetalHostView.performKeyEquivalent(with:)` (when it is
   the first responder) offers the event to `onInput` and answers its `Bool`;
   the main menu sees only what the window declined (Quit, Hide, Minimize…).
   The offered event is remembered by identity, so if AppKit then sends the
   same declined event to `keyDown(with:)` it is not offered twice. A
   command item's `NSMenuItem` carries its key equivalent for display; it can
   fire from the menu only when no MetalUI window claimed the key (e.g. no
   window is key), and then runs the same action — one fire either way.
4. **The key-window order is MetalUI's reading of AppKit's documented
   dispatch** (the key window's `performKeyEquivalent:` before the main
   menu), **not a measured SwiftUI answer**: the probe ran with no key window
   and there the menu won (`⌘R: NSApp.sendEvent -> ["menu-R"]`), while each
   side claims the key when asked directly (`window.performKeyEquivalent ->
   true ["button-R"]`, `mainMenu.performKeyEquivalent -> true ["menu-R"]`)
   and neither path fired twice. Owned by human check R4 (re-run the commands
   probe unlocked with a key window).

**Reasoning.** The request's two constraints — one shortcut path and no
double fire — are both met by putting the commands after the window's own
stages in the one pipeline and making AppKit ask that pipeline first. A
second path (letting `NSMenu` dispatch MetalUI command shortcuts) would make
SDL and AppKit dispatch differently and put a command ahead of a focused
field's own ⌘-keys.

**Cost if wrong.** If SwiftUI's key window lets the menu win, the stage
moves ahead of `dispatchShortcut` — one line, pinned by test 2.6 either way.

---

## MN-K — The Edit menu reaches the focused field as its keys

**Ruling.** The standard Edit items' AppKit actions (`cut:`, `copy:`,
`paste:`, `undo:`, `redo:`, `selectAll:`, `delete:`) are implemented on
`MetalHostView` by delivering the key that item's shortcut names (⌘X, ⌘C,
⌘V, ⌘Z, ⇧⌘Z, ⌘A, Delete) to `onInput` as a `.keyDown` — so a menu click and
the keystroke take one path into `TextField`/`TextEditor`'s existing editing
keys (`TI-B`, `TI-D`, `TI-G`). `validateMenuItem(_:)` enables them only while
a field is focused (`textInputCaret != nil`, the state `setTextInputArea`
already gives the host view).

**Reasoning.** The editing keys are the one implementation; a second route
through selectors would duplicate TI-D's table.

**Cost if wrong.** A field-less app's Edit menu is disabled, as SwiftUI's
items are when nothing in the responder chain answers them.

---

## MN-L — `.popover(isPresented:arrowEdge:content:)` and `.popover(item:arrowEdge:content:)`

**Ruling.**

1. Both spellings on every `StyledElement` and `ProposalElementGroup`,
   returning `PopoverModifier<Self, P>`. `arrowEdge: Edge = .top` — SwiftUI's
   default places the popover above its anchor (P7, the same offset as P1's
   `.top`). `item:` takes `Binding<Item?>` with `Item: Identifiable`;
   content is built from the item.
2. **A wrapper, one identity level**, `DraggablePreviewModifier`'s recipe
   (`DN-J` item 3): the content numbers from 0 under the wrapper's id; the
   popover's slot is cursor 1 (never `-1`, `MC-P`), an **evaluated
   optional** produced only while presented, so `ID-C`'s reset gives a
   re-presented popover fresh `@State`. Under `item:`, the slot is
   `IdentifiedGroup`-named by the item's id, so a different item starts fresh
   (`ID-R`). Only a caller of `.popover` gets the new level; no existing id
   moves.
3. `attachmentAnchor:` is not offered (the anchor is always the wrapped
   element's bounds), owner none.

**Evidence.** P1 (four edges), P6 (`item:` presents one popover window), P7.

**Cost if wrong.** A default edge; one constant.

---

## MN-M — Placement: against the anchor, flipped and clamped inside the window; no arrow

**Ruling.**

1. The popover is a presentation root — laid out in its own run before the
   root, hoisted like `Deferred` content (clip and scroll reset, opacity
   kept, scroll context withheld) — through a new internal
   `AnchoredPresentation`, **not** through `Deferred`, whose behaviour is
   unchanged. Its root is a native custom layout (`PopoverPlacement`) that
   measures the popover chrome at a nil proposal (each axis capped at the
   window less 16 pt) and places it in the same pass.
2. **The anchor is the wrapped element's bounds from the last completed
   frame** (presentations run before the root, so this frame's are not yet
   known), kept in a window-owned anchor map, not `StateTable`. If the
   anchor moved, the window asks for one more frame (`requestAnotherFrame`,
   `List`'s `DD-F` footing); a popover presented before its anchor was ever
   laid out appears on the next frame.
3. **Position**: on `arrowEdge`'s side of the anchor with an 8-pt gap (the
   arrow's room), centred on the anchor along the other axis; `.leading`/
   `.trailing` are left/right (left-to-right only, as everywhere in MetalUI).
   **If it does not fit on that side but fits on the opposite one, it
   flips** (P5: SwiftUI flipped `.bottom` to above when the screen had no
   room); if it fits on neither, it stays on its side, clamped. It is then
   clamped inside the window with an 8-pt margin.
4. **Divergence 111, kept, owner none**: SwiftUI's popover is its own window
   (`_NSPopoverWindow`, P1) and extends past the presenting window — P1's
   `.bottom` hangs 30 pt below it, `.leading` 69 pt left of it — and flips
   against the **screen** (P5); MetalUI's is drawn inside the window and
   flips and clamps against the window.
5. **Divergence 112, kept, owner none**: no arrow is drawn (SwiftUI's
   NSPopover draws one). The chrome is a `.surface` rounded rectangle
   (radius 10) with a `.separator` border and the default shadow, its
   content padded by 12.

**Reasoning.** A window-local renderer cannot draw outside the window; the
in-window flip is the nearest honest equivalent of P5's screen flip. An arrow
is a triangle `Path` (now buildable) but a pixel-tested look nobody asked for;
deferring it is cheap.

**Cost if wrong.** A look; the placement is one pure function, unit-tested.

---

## MN-N — Dismissal and interaction

**Ruling.**

1. **An outside press dismisses**: a press (left or right) outside the
   topmost open popover dismisses it — and, if that press is outside the
   next one too, that one, and so on — by writing `false` (or `nil` under
   `item:`) through the binding, **from input, under `StateDispatch` for the
   declaring element**, and **the press is consumed** along with its release
   (nothing beneath runs; no context menu opens on it). A press on the anchor
   counts as outside.
2. **Escape dismisses the topmost popover**, as a key stage after an open
   drag session and an open menu and **before the keymap** (`DN-I`'s
   footing: a presentation is the innermost owner of Escape).
3. Opening moves no focus; focus inside a dismissed popover leaves with its
   identity (`IX-I`, unchanged). Tab traverses popover content in tree order.
4. Hit testing, the gesture arena and drops treat the popover as a
   presentation on a higher layer: it blocks presses and drops beneath its
   own bounds, and a declaring ancestor's gesture does not reach a press
   inside it (`IX-Q`, unchanged).
5. **Unmeasured against SwiftUI**: whether a transient `NSPopover`'s outside
   click also reaches what it lands on, and Escape (P3/P3b/P4a/P4c: the
   popover never became key in a locked session; `behavior=1` is
   `.transient`, whose documented behaviour is to close on outside
   interaction). MetalUI consumes, as its menus and `IN-W`'s scrim do.
   Owned by human check R5.

**Cost if wrong.** If SwiftUI's outside click passes through, the press is
re-offered after dismissal — a dispatch change pinned by test 3.5 either way.

---

## MN-O — Popover accessibility: a popover node, isolating nothing

**Ruling.** The popover's chrome publishes a new `.popover` role node
(AppKit `AXPopover`; AccessKit `DIALOG`, **not** modal) containing its
content; the rest of the window keeps publishing — no `IX-X` isolation, no
`isModal`.

**Evidence.** P2 (`_NSPopoverWindow role=AXPopover` holding the content),
P2b (the main window still publishes `Under` and `Anchor` while it is shown).

**Cost if wrong.** A role; AccessKit has no popover role, and `DIALOG` without
`modal` is its nearest non-modal container.

---

## MN-P — `.help(_:)`: SwiftUI's accessibility hint, and a drawn tooltip

**Ruling.**

1. **Accessibility is exactly `accessibilityHint(_:)`'s** on both
   vocabularies: AppKit `AXHelp`, AccessKit `description`; later-written wins
   on one element (H3, H3b: whichever of `.help`/`.accessibilityHint` is
   outer wins); an outer one wins over an inner one (H5: `help=Outer` on the
   inner text) and a plain container distributes it to each child (H4) —
   `IX-W` item 2's existing rules, which already give these answers. No
   tooltip node is published.
2. **The tooltip is drawn by `Window` on every platform**, not AppKit's
   native tooltip: a non-opaque tooltip region per element (registered in
   prepaint, outside the disabled gate — a disabled control still explains
   itself — found by the one ranking with `DN-F`'s layer rule), shown when
   the pointer has rested in one region for **1.0 s of display-link time**,
   stamped from the **first tick after the pointer entered** (`IX-C`'s
   "a stamp is always a real tick"); moves inside the region do not restart
   it. Hidden by any press, a wheel event, a key-down, leaving the region, a
   menu opening or the window leaving key; after a hide it returns only once
   the pointer has left and re-entered. Placed with its top-left 18 pt below
   the pointer (below the cursor), flipped above when it does not fit, then
   clamped inside the window with 4 pt; a `.surfaceSecondary` panel,
   `.separator` border, radius 4, 11-pt text, padding 4×6, wrapping at 300 pt.
   The window keeps its display link running only while a tooltip timer is
   pending (`IX-C` item 4's footing).
3. **Divergence 113, kept, owner none**: on macOS SwiftUI shows AppKit's
   native tooltip; MetalUI's is drawn, so its look and delay are MetalUI's
   (the native one's delay is unmeasured — H7 found no tooltip window in a
   locked session — owned by human check R6).

**Reasoning.** A native AppKit tooltip needs tooltip rectangles kept in step
with layout on the host view every frame and an active app to appear —
untestable headless (H7) — and a new platform requirement. A drawn tooltip is
one implementation, driven by `simulateTick` in tests.

**Cost if wrong.** A look and a constant; a native path later is an additive
`PlatformWindow` requirement behind the same region registry.

---

## MN-Q — Where the attachments live: one new `Handlers` member, one proposal wrapper

**Ruling.** `Handlers` gains its **sixteenth** member, `contextual`, one
reference (`ContextualAttachment?`, a final class holding the context-menu
closure and the help text) — `MemoryLayout<Handlers>.size` 456 → 464, the
one-megabyte-thread guard re-run. `HandlerShape` (`ModifierTests`) and
`HandlerFingerprint` (`OuterModifierMatrixTests`) gain the field.
`.contextMenu` and `.help` on a `StyledElement` return `Self` through
`handling` (no id moves); on a `ProposalElementGroup` each wraps once in
`ContextualModifier<Content>` (one identity level for the caller only, `DN-P`).
`.popover` is a wrapper on both (`MN-L`). Registration happens in
`Frame.registerHandlers`' 5-argument implementation beside the drop
destination's (`DN-G`'s placement: outside the `allowsHitTesting` gate,
before the disabled gate's early exit — the region must exist for a disabled
element, `MN-E` item 2).

**Cost if wrong.** Eight bytes per `Handlers`; the thread budget is
re-measured by its guard.

---

## MN-R — The accessibility vocabulary grows by five roles, one action, one request

**Ruling.** `AccessibilityRole` gains `.menu`, `.menuItem`,
`.menuItemCheckBox`, `.menuButton`, `.popover`; `AccessibilityActions` gains
`.showMenu`; `AccessibilityRequest` gains `.showMenu(AccessibilityNodeID)`.
AppKit: `AXMenu`, `AXMenuItem`, `AXMenuItem` with `AXMenuItemMarkChar` `✓`
when its value is `"1"`, `AXMenuButton`, `AXPopover`, and
`accessibilityPerformShowMenu`. AccessKit: `MENU`, `MENU_ITEM`,
`MENU_ITEM_CHECK_BOX` (toggled from the value), `BUTTON` + `has_popup MENU`,
`DIALOG`, and `SHOW_CONTEXT_MENU`. Both bridges' field → attribute tables
gain the rows; the `Mirror` parity tests stay the enforcement.
**Migration**: an exhaustive external `switch` over `AccessibilityRole` or
`AccessibilityRequest` adds the cases or a `default:`.

**Cost if wrong.** A role mapping; each is one row.

---

## MN-S — Lanes, requirements, counts

**Ruling.** Three lanes, run strictly in order, each red first; a later lane
may extend an earlier lane's files (`DN-T`'s precedent) but owns only its
own (spec §5). New requirements, each with **no default**: `PlatformWindow.presentMenu(_:at:)`
(lane 1 implements it in every conformer: AppKit's interim `false` until lane
2, SDL's final `false`, every fake and every compile-guard fixture —
`grep -rln "func beginExternalDrag" Sources Tests Backends`) and
`Platform.setMenuBar(_:)` (lane 2, every `Platform` conformer —
`grep -rln "func setApplicationIcon" …`). Each new typecheck guard is mutated
red once. Expected counts in spec §6.6.

---

## MN-T — Deferred, with owners

**Ruling.** Spec §10's table is the list: every item there is owner none
unless it names a human check; none blocks the branch.

---

# Critic round (2026-10-02)

The critic re-ran both probes first: `swiftui-menus-popovers.swift` as
committed reproduced its 130 recorded lines byte for byte; both
`swiftui-commands.swift` builds reproduced theirs (only the process name in
the application menu's titles follows the binary's name). Four arms were then
appended to the menus probe after C10 (C11n, C13c, C13, C14; extended form
run twice, byte-identical, header re-recorded). The SDK's own
`SwiftUI.swiftinterface` (macOS 27.0 SDK) was read for every public spelling
the design copies. The rulings below fix what that found; each names what it
amends. Earlier rulings keep their text; where one is amended, this round's
ruling is the authority.

---

## MN-U — A context menu and a help region sit inside the `allowsHitTesting` gate (C13; amends MN-E item 2, MN-P item 2, MN-Q)

**Ruling.** The contextual region (menu and help) is registered in
`Frame.registerHandlers` **inside** the `allowsHitTesting` gate (beside the
pointer hitbox) and **outside** the disabled gate: `.allowsHitTesting(false)`
opens no context menu and shows no tooltip; a disabled element's menu still
opens with every item disabled (C9, unchanged). This **differs from drop
destinations** (`DN-G` registers outside the `allowsHitTesting` gate) by
measurement, not by oversight. The accessibility show-menu action is not a
hitbox query and is still advertised under `allowsHitTesting(false)` (`IX-Z`'s
footing; MetalUI's own, unmeasured). New test 1.35
`aContextMenuUnderAllowsHitTestingFalseDoesNotOpen` (mutation: register the
region outside the gate).

**Evidence.** C13c (positive control: a right press on the menu view begins
tracking `["X"]`) against C13 (the same view under `.allowsHitTesting(false)`:
tracking `[]`).

**Cost if wrong.** One registration moved; pinned by 1.35 either way.

---

## MN-V — A covering pointer target blocks the menu beneath; a painted-only cover cannot (C14; amends MN-E item 1, test 1.10; divergence 114)

**Ruling.**

1. **One lookup, `contextualTarget(at:)`, shared by menus and tooltips**:
   rank the opaque pointer hitboxes and the contextual regions together by
   the one ranking (`topmostHitbox(in:at:where:)` over the union — no second
   ranking). If the topmost entry is a contextual region, it is the target. If
   it is an opaque hitbox, the target is the region of **that hitbox's element
   or its nearest ancestor with one** (by the `GlobalElementID` parent chain,
   the arena's own ancestry, `IX-Q`) — so `Button("B").contextMenu { … }`
   and `Box { Button }.contextMenu { … }` open, C8's nesting holds, and **an
   unrelated pointer target covering the region blocks it** (C14). `DN-F`'s
   layer rule is subsumed: a presentation's hitbox on a higher layer ranks
   first and is not a descendant.
2. **Divergence 114, kept, owner none**: SwiftUI's opaque cover blocks with no
   handler at all (C14's `Color.blue`); MetalUI registers no hitbox for an
   element without pointer handlers, so a cover that only paints does not
   block — the menu beneath opens. Making every painted element a hitbox
   would move hit testing (must-not-move).
3. The tooltip uses the same lookup — **MetalUI's own for `.help`**,
   unmeasured (H7's instrument shows no tooltip at all headless).

Test 1.10 becomes `aCoveringPointerTargetWithoutAMenuBlocksTheMenuBeneath`
(mutation: rank the contextual regions alone); new test 1.36
`aPaintedCoverWithNoHitboxDoesNotBlockTheMenuBeneath` pins 114 (mutation:
require a hitbox owned by the region's element or a descendant, which also
reddens 1.1 — a `Box` with a menu and no handlers has no hitbox).

**Evidence.** C14 (`menu tracking began []` under the cover) against C13c.

**Cost if wrong.** One function; both tests pin it.

---

## MN-W — Show-menu on a node without a menu answers `false` (C11n; evidence for MN-G item 2)

**Ruling.** Unchanged behaviour, now measured: `accessibilityPerformShowMenu`
on a node with no context menu answers `false` and opens nothing (C11n), as
`MN-G` item 2 ruled. The dumps' `[showMenu]` marks every node (it records
`responds(to:)`, which every accessibility element answers) and is **not**
evidence of an advertised action; neither is C11/C11c's empty
`actionNames`. Test 1.30 stands.

---

## MN-X — The public spellings follow the SDK's (amends MN-I item 1, MN-L item 1, spec §2.5–§2.6)

**Ruling.** Read from the macOS 27.0 SDK's `SwiftUI.swiftinterface`:

1. **`arrowEdge: Edge? = nil`**, not `Edge = .top`: both `.popover`
   spellings take an optional edge defaulting to `nil`; `nil` places the
   popover on the top edge on macOS (P7: the default sat where `.top` did).
   `attachmentAnchor:` (which precedes `arrowEdge:` in SwiftUI) stays not
   offered (`MN-L` item 3), so every SwiftUI call site that omits it compiles
   unchanged. Test 3.2 `theDefaultArrowEdgeIsTop` passes no edge and passes
   `nil` explicitly. Guard G3.1 spells `arrowEdge: nil`.
2. **`App.commands(content:)`**: SwiftUI labels the closure `content:`
   (`func commands<Content: Commands>(@CommandsBuilder content:)`); MetalUI's
   is `public func commands<C: Commands>(@CommandsBuilder content: @escaping
   @MainActor () -> C)`. Trailing-closure call sites read the same; G2.1
   also spells `commands(content:)`.
3. `CommandMenu(_ name: String, content:)` and `CommandGroup(before:/after:/
   replacing:, addition:)` match SwiftUI's labels. `CommandGroupPlacement` is
   `Sendable, Hashable` where SwiftUI's is only `Sendable` — additive (a
   dictionary key in `menuBarContent()`), as `Transaction`'s `Sendable` was
   (`AN-AH` item 5). Every stored menu closure is `@escaping` where SwiftUI's
   are not (evaluated later, `MN-D` item 4, `MN-I` item 1); a call site reads
   the same.

**Cost if wrong.** A spelling; G2.1/G3.1 pin it.

---

## MN-Y — A press outside a popover dismisses it and then reaches what it lands on; a press on the anchor is consumed (P4a; amends MN-N items 1 and 5)

**Ruling.**

1. A press (left or right) outside every open popover dismisses them,
   topmost first, writing `false`/`nil` from input under `StateDispatch`,
   and **then continues through dispatch as an ordinary press** — the
   `Button` it lands on runs, a context menu beneath opens.
2. **A press on a popover's own anchor** dismisses that popover and is
   **consumed** with its release, so `Button { shown.toggle() }` closes the
   popover rather than re-presenting it. MetalUI's own (unmeasured).
3. A press inside a popover reaches its content (test 3.6) and is never a
   pass-through to what lies beneath the popover (`MN-Z`).

**Reasoning.** The design consumed the press on the strength of `IN-W`'s
scrim, but the probe's only reading points the other way: P4a's outside
click reached `Under` (`log ["under"]`) exactly as P4b's did with no popover
(the popover not dismissing is the locked session's broken half — the window
never became key); `NSPopover.Behavior.transient`'s documented rule is to
close when the user interacts with something outside it, which presumes the
interaction happens. Human check R5 re-runs P4 unlocked. Menus still consume
(an `NSMenu`'s tracking loop does; `MN-F` item 3, unchanged).

Test 3.5 becomes `aPressOutsideThePopoverWritesFalseAndReachesWhatItLandsOn`
(mutation: claim the press after dismissing); new test 3.26
`aPressOnTheAnchorDismissesThePopoverAndIsConsumed` (mutation: treat the
anchor as any outside point — the toggling anchor re-presents).

**Cost if wrong.** One `return`; both tests pin it either way.

---

## MN-Z — The popover chrome blocks what lies beneath it (amends MN-N item 4, spec §3.7)

**Ruling.** The chrome `Box` has no handlers, so it would register no hitbox,
and a press on its padding would fall through to a `Button` on a lower layer.
`AnchoredPresentation`'s prepaint therefore inserts a **raw opaque hitbox** at
the chrome's bounds (`PrepaintPass.insertHitbox`, no handler, not focusable,
publishing nothing, never a press for accessibility) **before** the content
registers, so the content ranks above it. It blocks a press, a wheel and a
drop beneath, and is the "not a descendant" entry `MN-V` needs. Test 3.8's
mutation becomes "drop the chrome's blocking hitbox" (its old mutation,
register at the declarer's layer, is kept as a second row).

---

## MN-AA — The Edit menu never re-delivers a key the window declined (amends MN-K)

**Ruling.** With a main menu installed, a ⌘-key the window declines in
`performKeyEquivalent` goes on to the main menu; if an Edit item matches and
validates (a field is focused but did not claim the key — e.g. ⌘Z with an
empty history), its action (`undo:` …) would deliver the same key to
`onInput` a second time. Each Edit action therefore delivers nothing when
`NSApp.currentEvent` is the event `performKeyEquivalent` already offered
(the identity `MN-J` item 3 remembers); a menu **click** (a mouse event as
the current event) delivers the key. New test 2.18
`anEditKeyTheWindowDeclinedIsNotDeliveredAgainByTheEditMenu` (mutation: drop
the identity check in the action).

---

## MN-AB — The in-window menu is exempt from modal isolation (amends MN-F item 4)

**Ruling.** `IX-X`'s isolation publishes only the topmost `.isModal`
subtree and refuses requests outside it (divergence 95). A menu opened from
inside a modal (a context menu on a control in the sheet) would vanish from
the tree and its `press` be refused. The panel's window-owned root is
therefore **always published** (after the isolated subtree) and its item ids
are always accepted — it is the platform's menu, above every modal, as an
`NSMenu` is. New test 1.37
`theInWindowMenuIsPublishedAndPressableUnderModalIsolation` (mutation: build
the panel's root inside the isolation filter).

---

## MN-AC — Control-click is AppKit's alone; existing pins and shared state that move (amends MN-B, MN-Q, MN-I)

**Ruling.**

1. Only `MetalHostView` turns a control-press into `.rightMouseDown`. SDL
   **never** does: off Apple ctrl-click is `List(selection:)`'s toggle
   (`DD-Z`, `ControlKeys`' shortcut modifier), so it stays a primary press.
   **Migration note** (lane 1, `docs/migration.md`): on AppKit a
   control-click no longer presses a `Button` or runs an `onClick`/tap — it
   is a secondary press (`MN-B` item 4, divergence 110).
2. **An existing pin moves**: `AccessibilityModifierTests.swift`'s
   `MemoryLayout<Handlers>.size <= 440 + 8 + 8` is raised by 8 in the change
   that adds `contextual` (lane 1), beside new test 1.33's exact 464.
3. **Shared test-process state**: `App.init` on `AppKitPlatform` now sets
   `NSApp.mainMenu`, and `FrameLoopTests` builds `App(device:)` — so every
   later AppKit test in the process runs with MetalUI's main menu installed.
   Lane 2 runs the whole suite unfiltered (as every AppKit change does), and
   tests 2.13–2.16 save and restore `NSApp.mainMenu`.

---

## MN-AD — Lanes rebalanced (amends MN-S, spec §5)

**Ruling.** Lane 1 also takes the SDL right button and Menu key
(`SDLBridge.c` + header, `SDLPlatform.named`; tests S3.1/S3.2 move to it),
because lane 1's in-window menu is the SDL path and would otherwise land
with no real input until lane 3. The `Menu` pull-down moves to lane 2
(`PullDownMenu.swift`, tests 1.31/1.32 keep their numbers but are lane 2's;
lane 2 creates the window-owned anchor map, lane 3 extends it) — lane 2
already owns native pop-up placement. Lane 1 keeps the `.menuButton` role in
the vocabulary (`MN-R`). Expected counts: lane 1 35 tests (1.1–1.30, 1.33–
1.37), lane 2 20 (2.1–2.18, 1.31, 1.32), lane 3 26 (3.1–3.26): **2227 + 81
= 2308** root tests; guards unchanged at **141**; `Backends/SDL` +5; live
divergences 76 → **81** (110–114), next label **115**. `MN-S`'s "spec §6.6"
is a typo for §6.4.

**The `Menu` type straddles the two lanes**, so the split is by file:
lane 1 declares `public struct Menu<Label, Content>` itself in
`MenuContent.swift` — both initialisers, its stored properties (the four
`StyledElement` requirements' storage included, since stored properties
cannot live in an extension) and its `MenuContent` conformance as a submenu
item (guard G1.2 spells `Menu("Sub") { … }` inside a context menu only);
lane 2 adds `extension Menu: Element, StyledElement` and the pull-down's
behaviour in `PullDownMenu.swift`, and guard G2.1 spells `Menu("…")` as a
view.

---

# Lane 1 (2026-10-02)

## MN-AE — What lane 1 settled in building the seam (amends MN-R, MN-G, spec §3.9, test 1.34)

**Ruling.**

1. **AppKit has no modern spelling for a menu item's mark character**: the
   SDK's `NSAccessibilityProtocols.h` has no `MarkChar` method (grep reads
   nothing), and the attribute-dictionary API that carries
   `AXMenuItemMarkChar` (`accessibilityAttributeValue(_:)`) is deprecated
   since macOS 10.10 — overriding it warns, and the branch gates on 0
   `warning:`. So `.menuItemCheckBox` publishes as `AXMenuItem` whose
   **value is the number 1 or 0** (a check box's footing, `DD-U` item 1),
   not a `✓` mark character. Test 1.34 asserts the value. A native `NSMenu`
   (lane 2) publishes AppKit's own mark; this answer is the drawn menu's
   only. AccessKit's `MENU_ITEM_CHECK_BOX` carries `toggled` (S1.1).
2. **A context menu is something to say** (`MN-G` item 2): an element with a
   menu records an accessibility node even when nothing else would make it
   (a `Box` with only `.contextMenu`, or a proposal `ContextualModifier`, a
   declaration outside the synthesize gate as `accessibilityAction` is,
   `IX-AF` item 3), so a client has a node to ask to show the menu. Additive:
   only a tree holding a menu changes.
3. **`.showMenu` is advertised only by an enabled node** (`AB-H`: a disabled
   node advertises no actions); the request still opens a disabled
   element's menu, every item disabled (C9), and is refused for a node with
   no recorded menu (C11n).
4. **The keyboard opener walks the focus chain** (`Window.focusChain`, the
   focused id and its `GlobalElementID` ancestors) for the nearest element
   with a menu — the same answer as spec §3.2's "`parentOf` in the last focus
   registry", through the walk every other key stage uses.
5. **A native menu's release is claimed for the secondary button only**: an
   AppKit `NSMenu` tracks the right release inside `popUp`, so the host view
   may never see it, and a claim that waited for any next release would eat
   an unrelated primary click. An in-window menu's consumed outside press
   claims the release of its own button.
6. **An open in-window menu treats Return, Enter (`U+0003`) and Space alike**
   (`MN-F` item 3), and a focused `TextField`'s Space — which arrives as
   `.textInput(" ")` — chooses too, so a field under a menu cannot swallow it.

**Reasoning.** Items 1 and 5 are platform facts found while implementing;
items 2–4 make the spec's sentences concrete without moving any existing
answer; item 6 is the panel's own keyboard rule.

**Cost if wrong.** Item 1 is one row of the bridge's role table (a
`MarkChar` method in a future SDK would replace the value). The rest are one
function each, pinned by tests 1.30, 1.34, 1.35 and 1.24.


---

# Lane 2 (2026-10-02)

## MN-AF — What lane 2 settled in building AppKit, the menu bar and the pull-down (amends MN-H item 1, MN-I, MN-C, spec §2.5, §3.4–§3.6, test 1.32)

**Ruling.**

1. **A `Menu` opens from `Button`'s activation keys, not "Space/Return"**:
   the pull-down is `Button`'s chrome and keys (`MN-H` item 1), and
   `ControlKeys.activatesButton` (`DD-R`) is Space on a Mac and Space or
   Return elsewhere — macOS's Return presses the default button, not the
   focused one. `MN-H` item 1's "Space/Return when focused" is amended to that
   table; test 1.32 asserts Space opens it and Return does so only off Apple
   (found by running: the spec's reading was red on this machine).
2. **`CommandsBuilder`'s result type is `CommandItems`** (public, `MenuItems`'s
   shape): a result builder's block must build a public type conforming to
   `Commands`, which spec §2.5's sketch did not name.
3. **The menu bar's ids are numbered depth-first in menu order at every
   evaluation** (`MenuBarModel`), a group's standard items before its
   additions; `PlatformMenuBar.perform` runs the action of the **last**
   `content()` evaluation. AppKit's `menuNeedsUpdate` re-evaluates for the
   menu about to open, so the open menu's tags are always the current
   evaluation's; a closed menu's key equivalents carry the ids of its last
   build, which equal the current ones whenever the commands' structure (not
   only their state) is unchanged. A command whose structure changes between
   evaluations (an `if` in the builder) and whose key the main menu — not the
   window — dispatches may run the item now at that id; the window's command
   stage (`MN-J`), the path every key reaches first, evaluates afresh and has
   no such window. Owner none.
4. **A separator joins two non-empty groups of a menu** (the PLAIN arm's
   separators between About, the visibility group and Quit; between Undo/Redo
   and the pasteboard group; between Minimize/Zoom and Bring All to Front), and
   File's Close is a fixed group after `.newItem`'s. An empty Help group drops
   the Help menu.
5. **The pull-down's open replaces a caller's `.onClick` on the `Menu`**, as a
   caller's `.onClick` replaces a `Button`'s action the other way round: the
   menu's whole point is opening. Its `⌄` indicator is a `Text` marked
   `.accessibilityHidden(true)`, so the button reads as its title alone (M1
   publishes no label; MetalUI's folded label is the title). The `.menuButton`
   role rides an internal `AXNode.menuButtonHint`, stripped before
   `isEmpty`'s gate as `selectionHint` is (`DD-U` item 4), so it writes no
   `$ax` slot and moves no retention. Pinned by test 1.31c
   (`aPullDownMenuWritesNoAXNodeAndNoAXSlot`, fix round).
6. **The window-owned anchor map is `Window.lastPresentationAnchors`**, copied
   from the frame's `presentationAnchors` after each frame (window points, as
   `contextMenuRecords`' bounds are); a `Menu` records its bounds in
   `prepaint`. A frame reaches its window through a `MenuPresenter` handle
   (weak), handed to each frame as `ScrollViewProxy`'s queue is. Lane 3
   extends the map for popovers. The bounds are translated by
   `activeOffset` (the scroll translation), pinned by test 1.31b
   (`aPullDownMenuInsideAScrolledScrollerOpensBelowItsScrolledFrame`, fix
   round): a popover anchored through this map inherits that pin only for
   the recording site it shares.
7. **AppKit seams are test-replaceable closures on `AppKitWindow`**:
   `menuPresenter` (production `NSMenu.popUp(positioning:at:in:)` in the
   flipped host view, so MetalUI's point is the view's) and
   `scheduleMenuOutcome` (production the next main-actor turn,
   `Task { @MainActor }`), and `MetalHostView.currentEvent` (production
   `NSApp.currentEvent`). The production defaults are pinned by no test — a
   locked session cannot run AppKit's tracking loop; human check R1.
8. **Identity is the reading of AppKit's dispatch, not a measurement**: the
   host view assumes AppKit hands the same `NSEvent` object to
   `performKeyEquivalent(with:)` and then `keyDown(with:)` (and leaves it
   `NSApp.currentEvent` while the main menu runs a matched item), the reading
   `MN-J` item 3 and `MN-AA` rest on. If a real session shows a copy instead,
   a ⌘-key the window declined is delivered twice — human check R4.
9. **(fix round) A disabled `Menu`'s gate is `Button`'s**, the disabled
   gate in `Frame.registerHandlers` (no hitbox, no focus entry, a refused
   accessibility press), so a disabled `Menu`'s open never runs. The
   `isEnabled` `Menu.prepaint` forwards to `openPullDown` (and on into the
   `ContextMenuRecord`) is redundant — forcing it `true` reddens nothing
   (mutation M1.32) — and is kept as belt-and-braces so the record a
   pull-down builds says what a context menu's would. Test 1.32's mutation
   is "skip `Button`'s gate"; it was renamed
   `aPullDownMenuOpensFromButtonsActivationKeysAndNotWhenDisabled` to match
   item 1's amended keys.
10. **(fix round) `performKeyEquivalent(with:)` declines an event it has
    already offered** (its own identity guard, beside `keyDown(with:)`'s):
    pinned by test 2.9's repeat offer (mutation M2.9b).

**Reasoning.** Item 1 keeps `Menu` exactly `Button`'s keyboard citizen (one
table, `DD-R`). Items 2–10 make the spec's sentences concrete; none moves an
existing answer.

**Cost if wrong.** Item 1 is one argument (`ControlKeys`' platform); item 3 a
stale id in an edge no test reaches; items 7–8 are what human checks R1/R4
look at.

---

# Lane 3 (2026-10-03)

## MN-AG — What lane 3 settled in building popovers, tooltips and the demo (amends MN-L item 2, MN-M items 2 and 5, MN-P item 2, MN-Q, spec §3.7, §3.10, test 3.15)

**Ruling.**

1. **The chrome's panel is painted by `AnchoredPresentation`, not decorated
   on the `Box`.** A legacy `Box` paints its fill and its border as two
   primitives (`paintDecorationBody`: fill, content, then a transparent
   bordered rect, so the border sits over the content), and a shadow is per
   leaf (`GX-J`) — so a decorated chrome cast two shadows, the ring's a faint
   second outline (found by running test 3.16: two rects, two shadow
   images). The chrome `Box` now only pads (12) and carries the name and the
   popover hint; `AnchoredPresentation.paint` emits one `.surface` rounded
   rect (radius 10) with its 1-pt `.separator` border inside one shadow scope
   (radius 8, y 2 — `MenuPanel`'s), then the content. Still no new drawable
   primitive (`TE-AD` not triggered).
2. **`item:`'s name is the chrome `Box`'s own `elementID`** (a
   `StyledElement`'s own `id(_:)` wins where both apply), not an
   `IdentifiedGroup` wrapper: one type for both spellings
   (`OptionalGroup<AnchoredPresentation<Box<P>>>`) and **no new naming site**
   — `Box`'s `elementID` is an existing one, so `everyNamingSiteStartsAReturningNameFresh`
   needs no arm. A different item's id resets the old name's state (`ID-R`),
   pinned by test 3.12.
3. **Every `PopoverModifier` records its anchor, presented or not** (in its
   prepaint, through `Frame.recordPresentationAnchor`, after its content's
   prepaint), so a popover presented from input appears on the very next
   frame; only one presented before its anchor was ever laid out waits a
   frame (test 3.14). A presented popover whose anchor moved asks for one
   more frame (test 3.13). The previous frame's map reaches layout as
   `Frame.previousPresentationAnchors`, handed in by `Window`.
4. **`PopoverModifier` is not a `StyledElement`** (`DraggablePreviewModifier`'s
   shape): on the legacy vocabulary a `StyledElement` modifier (`.padding`,
   `.cornerRadius`, …) and a second `.popover` cannot follow `.popover` —
   write them before it — while the `ElementGroup`-level modifiers (`.frame`,
   `.id`, `.overlay`, `.background`, `.environment`, …) still do; on the
   proposal path it is a `ProposalElementGroup` and chains. G3.1's first
   fixture chained two legacy popovers and was refused (found by running); it
   was re-spelt. Owner none. *(Wording corrected and made divergence 115 by
   `MN-AH` item 5; it first read "nothing chains".)*
5. **The popover stage holds Escape too**: one `Window.dispatchPopovers`
   between the open menu's stage and the context menu's, so Escape is handled
   after a drag session and an open menu and before scrolling, text input and
   the keymap (`MN-N` item 2's "before the keymap"). A dismissed popover
   leaves `Window.lastOpenPopovers` at once, so a second event before the next
   frame does not dismiss it twice.
6. **The tooltip's "a menu opening" hide rule is every event while a menu is
   open**: the press or key that opens a menu already hides the tooltip by the
   press and key rules, and while `menuSession` exists every event hides it. A
   menu opened by an accessibility request leaves a shown tooltip until the
   next event (test 3.25 uses that to put both on screen). A flipped tooltip's
   bottom sits **4 pt above the pointer** (spec §3.10 named no gap).
7. **`.help` on the proposal path registers as `accessibilityHint`'s wrapper
   does** — `ContextualModifier.prepaint` declares the hint and registers
   synthesizing when its attachment carries help (a menu-only wrapper still
   registers non-synthesizing, as lane 1 built it), so the two publish one
   tree (test 3.22, proposal arm).
8. **Test 3.15 is restated**: a presented popover's chrome and content write
   their own element slots (`$anim`, `$anim-color` — every legacy `Box` does),
   so the count is not equal shown and dismissed. The test now asserts every
   entry presenting adds descends from the popover's slot (cursor 1), and that
   dismissing returns the table to its dismissed count (`ID-C`). The
   mutation (keep the anchor in `StateTable`, under the wrapper) still reddens
   it.
9. **`lowerAnchoredPresentation` lives in `AnchoredPresentation.swift`**, an
   extension of `LayoutPass` beside its one caller, not in
   `LegacyLowering.swift`; `lowerPresentation` and `Deferred` are untouched.

**Reasoning.** Items 1, 4 and 8 were found by running the red tests; the rest
make the spec's sentences concrete. None moves an existing answer: no
existing spelling gains a level, `Deferred` and `lowerPresentation` are
unchanged, and the default demo's pixels are unmoved.

**Cost if wrong.** Item 1 is one paint call; item 2 one line; item 4 a
`StyledElement` conformance (the `DraggablePreviewModifier` precedent would
move with it).

## MN-AH — Lane 3's review fix round (amends MN-AG items 4 and 6, MN-Y items 1–2, MN-P item 2, spec §6.3)

**Ruling.**

1. **The proposal path's popover is pinned at runtime** — test 3.27
   `aProposalPathPopoverPresentsPlacesAndDismisses`: a fixed 40 × 20
   `ProposalText` with a popover **inside an `HStack`** presents on the second
   frame at the legacy placement, is one identity level for its caller (every
   plain element from its position down one level deeper behind cursor 0 with
   its bounds unmoved, the content under cursor 1) and is dismissed by an
   outside press. **`requestProposalLayout` is reached only from a proposal
   container**: a `.popover` at the window's root takes the legacy
   `requestLayout` whatever its content — the first spelling of 3.27 (a root
   `HStack { … }.frame(…).popover`) stayed green under VX.4, found by running.
   Before 3.27, VX.4 (the proposal entry never presenting) left the suite
   green.
2. **"Passes on" (`MN-Y` item 1) is test 3.28's**
   (`theDismissingPressReachesAGestureBeneath`): a `TapGesture` beneath forms
   its arena at the press, so it runs only when the dismissing press reached
   it. Test 3.5 cannot separate the two — a `Button` clicks on the release
   from `active` alone — and its doc comment and spec row now say so; its
   mutation is V3.5a (skip the dismissal).
3. **Two tooltip hide rules are pinned**: the window leaving key (3.30
   `theWindowLeavingKeyHidesTheTooltip`, divergence 113's pin gains it) and
   no tooltip starting while a menu is open (3.31
   `noTooltipStartsWhileAMenuIsOpen`, `MN-AG` item 6).
4. **The anchor press's release claim (`Window.popoverClaimsRelease`) stays**
   and is pinned by 3.29 `theAnchorPressesReleaseIsConsumedToo` (both
   buttons). It is not redundant: `releasePressForMenu()` clears `active`, so
   the release completes no click, but an unclaimed release would still fall
   through every stage to the window's raw `onInput` as a lone release whose
   press it never saw.
5. **Divergence 115**: what may follow a legacy `.popover` (`MN-AG` item 4,
   reworded). SwiftUI chains any modifier after `.popover`, a second one
   included (new probe `docs/probes/swiftui-popover-chaining.swift` CH1,
   control CH2, separating arm NEGATIVE). Pinned by the plain-import guard
   G3.3 `aStyledModifierCannotFollowALegacyPopover` (refuses `.padding` and a
   second `.popover` after a legacy `.popover`; control: `.frame`, `.overlay`,
   `.id` after it and `.padding` before it compile). Owner none.
6. **Spec §6.3's mutation column records what was run** (the lane verifier's
   V3.1–V3.26, V3.5b and VX.1–VX.4, and this round's V3.5a and MG3.3), with
   the tests each reddened; row 3.12's mutation is "drop the chrome `Box`'s
   `elementID`" (there is no `IdentifiedGroup`, `MN-AG` item 2).

**Reasoning.** Each item answers a review finding with a test shown red by
the mutation named for it, or with a doc that no longer claims more than the
suite pins. No `Sources/` behaviour, public declaration or pixel moves.

**Cost if wrong.** Tests and docs only; item 4's claim is one `switch` case.

## MN-AI — A ⌃-key reaches the window before the main menu too (amends MN-J item 3; the branch check's finding, record §74 §6.3)

**Ruling.**

1. `MetalHostView.performKeyEquivalent(with:)` offers a key-down to the
   window first when it carries ⌘ **or ⌃**, so a `Button`'s or a focused
   field's ⌃-key (⌃A, ⌃E, ⌃K…) wins over a menu-bar command bound to the
   same key, as `MN-J` item 2 requires. ⌘ handling is unchanged.
2. **While marked text is composing** (`hasMarkedText()`), a ⌃-key without
   ⌘ is not offered: it stays the input method's (Kotoeri's ⌃J/⌃K convert)
   and follows AppKit's own route.
3. ⌥-only shortcuts are unchanged and unmeasured: ⌥ produces characters
   (⌥E is a dead key), so offering it first would route text through the
   window before the input context. Owner none.

Pinned by 2.9c `theHostViewOffersAControlKeyToTheWindowBeforeTheMainMenu`:
red on the old `.command`-only guard (the ⌃K claim and the log), and red on
the fix without its marked-text condition (the composing arm).

**Reasoning.** The branch check measured `NSApp.sendEvent(⌃K)` running a ⌃K
command with the window never seeing the key. A ⌃-key the window declines
still reaches the main menu, and `keyDown(with:)` skips the same event by
identity, so nothing is delivered twice. A declined ⌃-key no longer passes
through the input context, but with no marked text the context only turns it
into `doCommand(by:)`, which delivers the same key-down.

**Cost if wrong.** One condition in one method.
