# Menus, popovers and tooltips — design

**Status: design (2026-10-02), revised by the critic round (2026-10-02,
rulings `MN-U`…`MN-AD`, §11).** User request 2026-10-02, an item of the
gpui-gap priority list; **not a plan task**. Rulings `MN-A`…`MN-AD` in
[`../2026-10-02-menus-popovers-decisions.md`](../2026-10-02-menus-popovers-decisions.md).
Record: `docs/record/74-menus-popovers.md`. Probes:
`docs/probes/swiftui-menus-popovers.swift` (groups C, M, P, H) and
`docs/probes/swiftui-commands.swift` (the menu bar), both new, run twice
byte-identical, outputs in their headers. Branch `feat/menus-popovers` from
`b9da519`.

## 0. Baseline (re-taken by the design session at `b9da519`)

`swift build --build-system native --build-tests`: 0 `error:`, the one
`warning:` SwiftPM's deprecation notice. `swift test --build-system native
--no-parallel`: **`Test run with 2227 tests in 3 suites passed after 117.176
seconds`**, the `FR-J no-argument frame: succeeded=true` line present. 133
typecheck guards (record §73), 0 goldens, 76 live divergences, next label
110. The screen was **locked** throughout (lock probe:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`).

## 1. What MetalUI has, and what SwiftUI does

### 1.1 Inventory (the code this item touches)

| Area | Today | File |
|---|---|---|
| Pointer input | `InputEvent` has `mouseDown/Up/Moved/Dragged` for the **primary** button only. AppKit's `MetalHostView` overrides no `rightMouseDown`; a control-click arrives as a plain `mouseDown`. `SDLBridge.c:815` drops every button but `SDL_BUTTON_LEFT`. | `Sources/MetalUIPlatform/InputEvent.swift`, `Sources/MetalUIAppKit/AppKitPlatform.swift:127`, `Backends/SDL/Sources/SDLBridge/SDLBridge.c:814` |
| Menus | None anywhere. `App.openWindow`'s comment: "no app delegate and no menu bar anywhere in the framework". No `NSApp.mainMenu`, so ⌘Q does nothing on AppKit. | `Sources/MetalUI/App.swift` |
| Key dispatch | `Window.onInput`: drag session → scroll → text input → value track → gestures → keymap → focused field's editing keys → raw `onKey` bubble → `dispatchShortcut` (`Button.keyboardShortcut` via `FocusRegistry`) → Tab traversal → the app's `onInput`. Answers a `Bool` "claimed". AppKit delivers a ⌘-key through `keyDown(with:)` (it bypasses the input context). | `Sources/MetalUI/Window.swift:630–750`, `KeyboardShortcut.swift` |
| Presentations | `Deferred` (portal; an absolute content is a presentation root laid out in its own run before the root, `LR-CH`); click-to-dismiss is the app's own scrim `onClick` (`IN-W`). `DraggablePreviewModifier` shows the one-identity-level wrapper with an evaluated-optional presentation slot at cursor 1. | `Deferred.swift`, `DragAndDrop.swift:267` |
| Non-opaque regions | Drop destinations: registered in `Frame.registerHandlers` outside the `allowsHitTesting` gate, inside the disabled gate, found by `topmostHitbox(in:at:where:)` (`DN-F`). | `Frame.swift`, `Hitbox.swift`, `DragSession.swift` |
| Tick-driven timing | The gesture arena's long press: `advanceGestures(to:)` in the display-link callback, stamps from real ticks, the link kept awake only while pending (`IX-C`). | `Window.swift:764`, `:1733` |
| Accessibility | `AccessibilityRole` (group … link), `AccessibilityActions`, `AccessibilityRequest`; the hint is AppKit `AXHelp` / AccessKit `description` (`IX-AD`), outer-wins distribution (`AccessibilityTreeBuilder.swift:350`). AccessKit 0.23 has `MENU`, `MENU_ITEM`, `MENU_ITEM_CHECK_BOX`, `DIALOG`, `TOOLTIP`, `has_popup`, `SHOW_CONTEXT_MENU`. | `Sources/MetalUIPlatform/AccessibilityTree.swift`, `AppKitAccessibility.swift`, `Backends/SDL/Sources/MetalUISDL/AccessKitTree.swift` |
| `Handlers` | Fifteen members; `MemoryLayout<Handlers>.size` 456. | `Handlers.swift` |
| SDL keys | `SDLPlatform.named` maps keycodes to AppKit characters; F10 → `U+F70D`; no Menu key. | `SDLPlatform.swift:584` |
| Conformers | `PlatformWindow`: `AppKitWindow`, `SDLWindow`, `FakePlatformWindow` and four guard fixtures (`grep -rln "func beginExternalDrag" Sources Tests Backends`). `Platform`: `AppKitPlatform`, `SDLPlatform`, the fake, one guard fixture (`grep -rln "func setApplicationIcon" …`). | |

### 1.2 What SwiftUI does (probe readings; the decisions doc has the reasoning)

- **C1** — `.contextMenu` builds an `NSMenu` (`autoenables=false`): Button
  items (`menuAction:`), a `Divider` separator, `Menu` as a submenu, `Toggle`
  as a state item (`state=on`), `Picker` as a submenu of state items, a
  `.disabled(true)` Button disabled, `.keyboardShortcut("k")` shown as
  `key="k" mods=16`, a `Label` item with an image, `Section` as
  separator + disabled header + items + separator, `Text` as a disabled item.
- **C2–C4c** — performing an item runs its action; the toggle writes its
  binding; the menu is **rebuilt at each open** (`same object=false`, new
  state shown).
- **C5r** — a right-mouse-down begins menu tracking (14 items); **C5l** a
  plain left click does not; **C5c/C5n** a synthesized control-click opens
  nothing, even on a plain `NSView.menu` (broken instrument).
- **C6/C6t/C6n** — a right click presses a SwiftUI `Button` and fires an
  `.onTapGesture`; an `NSButton` ignores it. **C7b/C7b'** — on
  `Button.contextMenu` the right-down opened no menu and the right-up pressed.
- **C8** — nested menus: the inner one at the inner view, the outer elsewhere.
  **C9** — a disabled view's menu opens with its items disabled. **C10** — an
  empty menu: none. **C11** — `accessibilityPerformShowMenu` opens the menu.
  **C12** — a context item's shortcut is inactive while the menu is closed.
- **C11n** (critic round) — show-menu on a node with no context menu
  answers `false` and opens nothing. **C13c/C13** — a right press opens the
  menu; under `.allowsHitTesting(false)` it does not. **C14** — an opaque
  sibling with no menu covering the view blocks its menu.
- **M1** — `Menu("Title")` publishes `AXMenuButton`.
- **P1** — a popover is an `_NSPopoverWindow` (`NSPopover.behavior` 1 =
  `.transient`), placed on `arrowEdge`'s side of the anchor, extending past
  the presenting window (`.bottom` 30 pt below it, `.leading` 69 pt left).
  **P5** — flipped to above when the **screen** has no room below. **P7** —
  the default edge is `.top`. **P6** — `item:` presents. **P2/P2b** — the
  popover window is `AXPopover` holding the content; the main window keeps
  publishing (not modal). **P3/P4** — Escape and dismissal by an outside
  click unmeasured (never key); P4a's outside click **reached** the button
  beneath, as P4b's did with no popover (`MN-Y`).
- **H1–H5** — `.help` sets `AXHelp`; whichever of `.help`/
  `.accessibilityHint` is outer wins; an outer `.help` beats an inner one; a
  container distributes it. **H6/H7** — no `toolTip` property, no tooltip
  window in a locked session (unmeasured).
- **Commands** — PLAIN: App (About, Services, Hide ⌘H, Hide Others ⌥⌘H, Show
  All, Quit ⌘Q), File (New *name* Window ⌘N, Close ⌘W, Close All ⌥⌘W), Edit
  (Undo, Redo, Cut, Copy, Paste, Delete, Select All, Writing Tools,
  AutoFill, Dictation, Emoji), View, Window (Minimize ⌘M, Zoom, Bring All to
  Front, window list), Help. FULL: `CommandGroup(after: .newItem)` after New;
  `CommandMenu("Tools")` between View and Window; `replacing: .help` empties
  Help. A shortcut bound by both a menu item and a window Button: each claims
  it when asked directly; through `NSApp.sendEvent` **with no key window** the
  menu fired, once.

## 2. Public API

Every new public declaration carries a doc comment and an inventory map row
(`closeout-inventory-map.tsv`, families below); `zsh
docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print
nothing; the census is re-recorded with `closeout-public-api.sh`.

### 2.1 `MetalUIPlatform` — the seam (lane 1, except `setMenuBar`: lane 2)

```swift
// InputEvent.swift
public enum InputEvent {
    …
    /// A secondary-button press (AppKit: also a control-press, `MN-B`).
    case rightMouseDown(MouseEvent)
    case rightMouseUp(MouseEvent)
    /// A natively presented menu's outcome, delivered after `presentMenu`
    /// returned, never inside it (`MN-C` item 4).
    case menuAction(MenuActionEvent)
}
public struct MenuActionEvent: Sendable, Equatable {
    public var menu: Int          // the PlatformMenu's token
    public var item: Int?         // nil: dismissed with no choice
    public init(menu: Int, item: Int?)
}

// Menus.swift (new, MetalUIPlatform)
public struct PlatformKeyEquivalent: Sendable, Equatable {
    public var key: String; public var modifiers: Modifiers
    public init(key: String, modifiers: Modifiers)
}
public enum StandardMenuAction: Sendable, Equatable, CaseIterable {
    case about, hide, hideOthers, showAll, quit, close,
         undo, redo, cut, copy, paste, delete, selectAll,
         minimize, zoom, bringAllToFront
}
public struct PlatformMenuItem: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case action, separator, submenu([PlatformMenuItem]) }
    public var id: Int
    public var kind: Kind
    public var title: String
    public var isEnabled: Bool
    public var isOn: Bool
    public var shortcut: PlatformKeyEquivalent?
    public var standardAction: StandardMenuAction?
    public init(id:kind:title:isEnabled:isOn:shortcut:standardAction:)   // defaults for the last four
}
public struct PlatformMenu: Sendable, Equatable {
    public var token: Int; public var title: String; public var items: [PlatformMenuItem]
    public init(token: Int, title: String = "", items: [PlatformMenuItem])
}
/// The application's menu bar (`MN-I`): content asked for whenever the
/// platform needs it, and the callback a chosen command item runs.
public struct PlatformMenuBar {
    public var content: @MainActor () -> [PlatformMenu]
    public var perform: @MainActor (_ item: Int) -> Void
    public init(content:perform:)
}

// Platform.swift
public protocol PlatformWindow: AnyObject {
    …
    /// Shows `menu` itself at `position` (window points) and answers whether
    /// it did; `false` — SDL — means the window draws it (`MN-C`). The outcome
    /// arrives later as `.menuAction`. **No default implementation.**
    func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool
}
public protocol Platform: AnyObject {
    …
    /// Installs the application's menu bar (`MN-I`); SDL records it and draws
    /// nothing. **No default implementation.** (lane 2)
    func setMenuBar(_ menuBar: PlatformMenuBar)
}

// AccessibilityTree.swift (MN-R)
public enum AccessibilityRole { …; case menu, menuItem, menuItemCheckBox, menuButton, popover }
public struct AccessibilityActions { …; public static let showMenu }
public enum AccessibilityRequest { …; case showMenu(AccessibilityNodeID) }
```

**Migration notes** (in `docs/migration.md`, lane 1): an exhaustive external
`switch` over `InputEvent`, `AccessibilityRole` or `AccessibilityRequest`
adds the new cases or a `default:`; a `PlatformWindow` conformer implements
`presentMenu(_:at:)`; a `Platform` conformer implements `setMenuBar(_:)`
(lane 2); an AppKit app gains a menu bar (lane 2, `MN-I` item 4).

### 2.2 `MetalUI` — menu content (`MenuContent.swift`, new; lane 1)

```swift
public protocol MenuContent { /* one @_spi(MenuInternals) requirement */ }
@resultBuilder public enum MenuContentBuilder { /* buildBlock, buildOptional,
    buildEither, buildArray, buildExpression(some MenuContent) */ }
/// What a `@MenuContentBuilder` block builds.
public struct MenuItems: MenuContent { }
/// A separator between menu items (`MN-H` item 3: menu-only).
public struct Divider: MenuContent { public init() }
extension Button: MenuContent where Label == Text {}
extension Toggle: MenuContent where Label == Text {}
extension Text: MenuContent {}                         // a disabled item
extension EnvironmentScope: MenuContent where Content: MenuContent {}  // reads isEnabled only
extension Menu: MenuContent where Label == Text {}     // a submenu
```

### 2.3 `MetalUI` — `.contextMenu` and `.help` (`ContextMenu.swift`, new; lane 1, `.help`: lane 3)

```swift
extension StyledElement {
    public func contextMenu<M: MenuContent>(
        @MenuContentBuilder menuItems: @escaping @MainActor () -> M) -> Self
    public func help(_ text: String) -> Self                        // lane 3
}
extension ProposalElementGroup {
    public func contextMenu<M: MenuContent>(
        @MenuContentBuilder menuItems: @escaping @MainActor () -> M) -> ContextualModifier<Self>
    public func help(_ text: String) -> ContextualModifier<Self>    // lane 3
}
/// One identity level for its caller only (`MN-Q`).
public struct ContextualModifier<Content: ProposalElementGroup>: ProposalElementGroup { }
```

The closure is `@escaping` where SwiftUI's is not (it runs at each open,
`MN-D` item 4); the call site reads the same.

### 2.4 `MetalUI` — `Menu` (`PullDownMenu.swift`, new; lane 1)

```swift
public struct Menu<Label: ElementGroup, Content: MenuContent>: Element, StyledElement {
    public init(@MenuContentBuilder content: @escaping @MainActor () -> Content,
                @ElementBuilder label: () -> Label)
}
extension Menu where Label == Text {
    public init(_ title: String, @MenuContentBuilder content: @escaping @MainActor () -> Content)
}
```

### 2.5 `MetalUI` — commands (`Commands.swift`, new; lane 2)

```swift
public protocol Commands { /* one @_spi(MenuInternals) requirement */ }
@resultBuilder public enum CommandsBuilder { /* buildBlock, buildOptional, buildEither */ }
public struct CommandMenu<Content: MenuContent>: Commands {
    public init(_ name: String, @MenuContentBuilder content: @escaping @MainActor () -> Content)
}
public struct CommandGroup<Content: MenuContent>: Commands {
    public init(before group: CommandGroupPlacement, @MenuContentBuilder addition: @escaping @MainActor () -> Content)
    public init(after group: CommandGroupPlacement, @MenuContentBuilder addition: @escaping @MainActor () -> Content)
    public init(replacing group: CommandGroupPlacement, @MenuContentBuilder addition: @escaping @MainActor () -> Content)
}
public struct CommandGroupPlacement: Sendable, Hashable {
    public static let appInfo, appVisibility, appTermination, newItem,
                      undoRedo, pasteboard, windowSize, windowArrangement, help
}
extension App {
    /// The menu bar's commands (`MN-I`); a second call replaces the first.
    public func commands<C: Commands>(@CommandsBuilder content: @escaping @MainActor () -> C)   // MN-X item 2
}
```

Standard groups (`MN-I` item 2): `.appInfo` = About; `.appVisibility` = Hide,
Hide Others, Show All; `.appTermination` = Quit; `.newItem` = (empty);
`.undoRedo` = Undo, Redo; `.pasteboard` = Cut, Copy, Paste, Delete, Select
All; `.windowSize` = Minimize, Zoom; `.windowArrangement` = Bring All to
Front; `.help` = (empty). File also holds Close ⌘W after `.newItem`'s slot.

### 2.6 `MetalUI` — popovers (`Popover.swift`, new; lane 3)

```swift
extension StyledElement {   // and the same two on ProposalElementGroup
    public func popover<P: ElementGroup>(isPresented: Binding<Bool>, arrowEdge: Edge? = nil,
        @ElementBuilder content: @escaping @MainActor () -> P) -> PopoverModifier<Self, P>
    public func popover<Item: Identifiable, P: ElementGroup>(item: Binding<Item?>, arrowEdge: Edge? = nil,
        @ElementBuilder content: @escaping @MainActor (Item) -> P) -> PopoverModifier<Self, P>
}
public struct PopoverModifier<Content: ElementGroup, PopoverContent: ElementGroup>: Element { }
```

`arrowEdge` is SwiftUI's own optional (`MN-X` item 1); `nil` is `.top` on
macOS (P7).

(`PopoverModifier` conforms to `ProposalElementGroup` when `Content` does, as
`DraggablePreviewModifier`'s pattern requires; lane 3 follows whichever shape
that file uses.)

## 3. How it works

### 3.1 Registration (lane 1; `.help` lane 3)

`Handlers.contextual: ContextualAttachment?` (sixteenth member; a final
class: `menu: (@MainActor () -> MenuItems)?`, `help: String?`). In the
5-argument `Frame.registerHandlers`, **inside** the `allowsHitTesting`
gate (beside the pointer hitbox — C13, `MN-U`; unlike the drop destination)
and **before** the disabled gate's exit, an element with an attachment
registers a non-opaque **contextual region**
(bounds clipped as every hitbox is, layer, the element's id, the attachment,
and the element's `isEnabled`). `Handlers.isPointerTarget` ignores it (no
new opaque target, `DN-E`'s shape). `ContextualModifier.prepaint` registers
the same region at its own bounds. A `display: none` layer registers nothing
(`AB-O`'s suppression covers it). The region list is frame-scoped (rebuilt
each frame), never `StateTable`.

### 3.2 Opening a context menu (lane 1)

`Window.onInput` gains, **after** the drag-session stage and **before**
scrolling: (1) the open in-window menu's stage (`MenuSession.dispatch`,
`MN-F` item 3), (2) the popover dismissal stage (lane 3, §3.8), (3) the
context-menu stage: on `.rightMouseDown`, `contextualTarget(at:)` (`MN-V`:
the one ranking over opaque pointer hitboxes and contextual regions
together; a region on top is the target, an opaque hitbox on top yields the
region of its element or nearest ancestor with one, an unrelated cover
blocks — C14) restricted to regions with a menu → evaluate the
closure **under `StateDispatch.dispatching(to: id)`** with the region's
environment's `isEnabled` (`MN-D`) → `PlatformMenu` (token = a counter;
items numbered depth-first; a disabled region disables every item) → if it
has no items, the press is not claimed; else `platformWindow.presentMenu(menu,
at: point)`; `false` opens `MenuSession` in-window. The session keeps
`token → [id: (action, declaringID, isEnabled)]`. `.rightMouseUp` is claimed
while a session exists or the down was claimed. Every other stage ignores the
two right-button cases (`MN-B` item 4) — `updatePointerState` does not set
`active` for them. A hover-tracking update (pointer position) still runs.

`.menuAction(e)`: if `e.menu` is the session's token and `e.item` names an
enabled action item, dismiss the session, then run the action **from input,
under `StateDispatch.dispatching(to: declaringID)`**; a toggle item writes
`!isOn` through its binding. Anything else is ignored (stale token, a
disabled id, `nil`). The window marks itself dirty.

Keyboard opener (`MN-G`): `ContextMenuKeys.opens(_ key: KeyEvent, platform:
TextEditing.Platform) -> Bool` (`.other`: Shift-F10 `U+F70D`+shift, or
`U+F735` with no modifiers; `.mac`: never), a stage after `dispatchKey` and
before `dispatchShortcut`, opens the focused element's (or its nearest
ancestor's, by `parentOf` in the last focus registry) menu at the element's
bottom-leading corner. Accessibility `.showMenu(id)` opens that id's menu at
its bottom-leading corner, through the same function.

### 3.3 The in-window menu (lane 1; `MenuSession.swift`, `MenuPanel.swift`)

As `MN-F`. `MenuSession` holds the levels (items, origin, highlighted index,
open submenu index), the token table and whether the opening press has moved.
`MenuPanel` is pure: `layout(items:, textSystem:, font:) -> PanelLayout`
(row rects, width) and `place(size:, at:, in window:) -> origin` (flip then
clamp), and `emit(into: frame)` paints with `Frame`'s rect/text primitives
**after** `paintDragPreview()` (`Frame.swift:2798`) — the window hands the
session to the frame as it hands the drag session. Accessibility: the window
appends the panel's nodes as a root after the content's roots
(`WindowAccessibility.swift`), ids synthesized from a window-reserved
`GlobalElementID` name (`$menu-panel`, never written to `StateTable`),
`focused` = the highlighted row; `.press(itemID)` chooses. The panel's root
is published and its ids accepted **even under modal isolation** (`MN-AB`).

### 3.4 `Menu` pull-down (lane 1)

`Menu` wraps `Button`'s chrome (`Button(action:label:)` with the label plus a
`⌄` text) and sets `role` on its declared node to `.menuButton`. Its action,
running from input, asks the window to present its items anchored at its own
bounds from this frame's prepaint (stored in a window-owned anchor map keyed
by its id, the same map popovers use — lane 2 creates it, lane 3 extends it, `MN-AD`):
native at the bottom-leading point, else the panel below it. Disabled:
`Button`'s gate (no hitbox, no focus).

### 3.5 AppKit (lane 2; `AppKitMenus.swift` new, `AppKitPlatform.swift`)

- `presentMenu`: `AppKitMenuBuilder.menu(from:target:)` (pure, tested) →
  `menuPresenter(menu, point, hostView)` — an internal, test-replaceable
  closure defaulting to `menu.popUp(positioning: nil, at: point, in:
  hostView)` (point flipped into the host view's coordinates) — then
  `RunLoop.main.perform { onInput?(.menuAction(…)) }` with the chosen id or
  `nil`. Returns `true`.
- `rightMouseDown/Up(with:)` → the two cases; `mouseDown(with:)` with
  `.control` → `.rightMouseDown` and a flag so the next `mouseUp(with:)` is
  `.rightMouseUp` (and a `mouseDragged` in between is dropped).
- `performKeyEquivalent(with:)`: when `window?.firstResponder === self`, the
  event is a key-down with `.command`, and it is not the last offered event
  (identity), remember it and return `onInput?(.keyDown(…)) ?? false`.
  `keyDown(with:)` returns at once for the remembered event.
- Edit actions (`MN-K`): `@objc func cut(_:)` … `delete(_:)` deliver the
  key — **unless `NSApp.currentEvent` is the event `performKeyEquivalent`
  already offered** (`MN-AA`: no second delivery of a declined key);
  `validateMenuItem(_:)` answers `textInputCaret != nil` for them.
- Control-click mapping is AppKit's alone (`MN-AC` item 1): SDL keeps a
  ctrl-click a primary press (`List`'s toggle there, `DD-Z`).
- `AppKitPlatform.setMenuBar`: builds `NSApp.mainMenu` from `content()`
  (top-level `NSMenuItem`s with submenus whose `NSMenuDelegate.menuNeedsUpdate`
  rebuilds their items from a fresh `content()`); standard items map to
  selectors (target nil, the responder chain; app-menu items to `NSApp`);
  command items target a small `MenuBarTarget` that calls `perform(id)`.
  Titles of the app-menu items use `ProcessInfo.processInfo.processName`.
- Accessibility (lane 1 adds the role table and `accessibilityPerformShowMenu`
  — §3.9).

### 3.6 Commands (lane 2; `Commands.swift`, `App.swift`, `Window.swift`)

`App.commands` stores the closure; `App.menuBarContent()` composes the
standard menus (§2.5) with the evaluated commands (`CommandMenu`s before
Window; groups before/after/replacing their placement's items) into
`[PlatformMenu]`, item ids stable per evaluation (depth-first), and keeps
`id → action` from the last evaluation for `perform`. `App.init` (every
initialiser) calls `platform.setMenuBar` once with the default content;
`commands` re-installs. Every window the app opens gets
`window.commandShortcuts = { [weak app] in app?.enabledCommandShortcuts() }`
(internal, a `(KeyboardShortcut, action)` list in menu order, re-evaluated
per call). `Window.dispatchCommandShortcut(_:)` sits directly after
`dispatchShortcut` (`MN-J`). A `Window` built without an `App` (tests) has
none unless a test sets it.

### 3.7 Popovers (lane 3; `Popover.swift`, `AnchoredPresentation.swift` new, `LegacyLowering.swift`/`Passes.swift`)

`PopoverModifier.requestLayout`: content at cursor 0; slot at cursor 1 —
`OptionalGroup<AnchoredPresentation<Box<PopoverContent>>>` (the Box is the
chrome: `.surface`, radius 10, `.separator` border, padding 12, the default
shadow) — produced only while presented **and** the anchor map has this id's
bounds (else `requestAnotherFrame()`); under `item:` the content is wrapped
in `IdentifiedGroup` named `"\(item.id)"`. `AnchoredPresentation` copies
`Deferred`'s three halves (`withoutScrollContext` in layout, `pass.deferred`
in prepaint and paint) but lowers through a new
`LayoutPass.lowerAnchoredPresentation(_:_:anchor:edge:)` beside
`lowerPresentation`: the root is a native custom layout,
`PopoverPlacement: ProposalLayout` (window-sized answer; measures the child
at a nil proposal capped to the window less 16; places it by §2's rule —
`PopoverPlacement.origin(anchor:size:edge:window:) -> PointD`, pure), queued
in `frame.lowering.presentations` like `Deferred`'s, the parent handed a 0×0
placeholder. `prepaint` records the wrapper's bounds in the anchor map
(requesting one more frame if they changed while presented) and registers an
open-popover entry `(id, layer, popover bounds, dismiss)` in a frame-scoped
list. The chrome declares an accessibility node with role `.popover`, and
its prepaint inserts a **raw opaque hitbox** at the chrome's bounds (no
handler, not focusable, publishing nothing) before its content registers, so
a press, wheel or drop on the chrome's padding never reaches what lies
beneath (`MN-Z`).

### 3.8 Popover dismissal (lane 3; `Window.swift`)

The stage of §3.2 item (2): on `.mouseDown`/`.rightMouseDown`, walk the open
popovers topmost first; while the point is outside the current one, call its
`dismiss` (binding write from input under `StateDispatch.dispatching(to:
id)`) and continue. **The press then continues through dispatch** (P4a,
`MN-Y`) — except a press on a dismissed popover's own anchor bounds, which
is claimed with its release (a toggling anchor closes rather than
re-presents). Escape (`.keyDown` `U+1B`, no modifiers), as a stage after the
menu's and before `dispatchAction`, dismisses the topmost one.

### 3.9 Accessibility (lane 1; popover role lane 3)

`AccessibilityTreeBuilder`: a node whose element has a contextual menu gains
`.showMenu`; `Window.handleAccessibilityRequest` routes `.showMenu(id)` to
§3.2. AppKit `AppKitAccessibility.swift`: roles per `MN-R`;
`accessibilityPerformShowMenu()` answers through `mainActorAnswer` with
`.showMenu`, `false` when the node lacks the action. AccessKit
(`AccessKitTree.swift`, `AccessKitAdapter.swift`): roles per `MN-R`
(`MENU_ITEM_CHECK_BOX` toggled from the value; `BUTTON` +
`ACCESSKIT_HAS_POPUP_MENU` for `.menuButton`; `DIALOG` without `modal` for
`.popover`); `ACCESSKIT_ACTION_SHOW_CONTEXT_MENU` added when `.showMenu` is
set, mapped back to `.showMenu`. C enum raw values converted explicitly
(Windows `Int32`).

### 3.10 Tooltips (lane 3; `Tooltip.swift` new, `Window.swift`)

`.help(text)` = `accessibilityHint(text)` (same declaration write, so the
same tree) **plus** `contextual.help = text`. `TooltipTracker` (window-owned):
on every pointer move, `contextualTarget(at:)` restricted to help regions
(`MN-V` item 3, the menu's own lookup) is found; entering a new region sets `pending(region, since: nil)`; the next
`advanceTooltip(to: tick)` call (display-link callback, beside
`advanceGestures`) stamps `since`; a later tick ≥ `since + 1.0` shows it at
the latest pointer position inside the region
(`TooltipPlacement.origin(pointer:size:window:)`, pure).
Hide rules per `MN-P` item 2 (`.mouseDown`, `.rightMouseDown`,
`.scrollWheel`, `.keyDown`, leaving, a menu opening, `controlActiveState`
leaving `.key`); after a hide the region is `spent` until left. Painted by
the frame after the menu panel. The link's pause decision adds "a tooltip is
pending".

### 3.11 SDL (lane 1: `presentMenu` and input, `MN-AD`; lane 2: `setMenuBar`)

`SDLWindow.presentMenu` returns `false`. `SDLPlatform.setMenuBar` stores the
bar (`menuBar` internal, read by a test) and draws nothing. `SDLBridge.c`:
`MUI_EVENT_RIGHT_DOWN`/`MUI_EVENT_RIGHT_UP` for `SDL_BUTTON_RIGHT`, exported
as C constants (the Windows rawValue hazard), and the injection path; motion
with only the right button held is a `mouseMoved`. `SDLPlatform.named` gains
`0x4000_0065: "\u{f735}"` (`SDLK_APPLICATION`).

## 4. Divergences and absences (`docs/divergences.md`)

| Label | SwiftUI | MetalUI | Ruling | Pin | Lane |
|---|---|---|---|---|---|
| 110 | a secondary click presses a `Button`, fires `.onTapGesture` (C6, C6t); on `Button.contextMenu` the up pressed and no menu opened (C7b) | a secondary press runs no `onClick`/gesture/drag; it only opens context menus | `MN-B` | `aSecondaryPressNeverRunsOnClickOrATap` | 1 |
| 111 | the popover is its own window, extends past the presenting window and flips against the screen (P1, P5) | drawn inside the window, flipped and clamped against it | `MN-M` | `aPopoverThatWouldLeaveTheWindowFlipsToTheOppositeEdge`, `aPopoverThatFitsNeitherSideIsClampedInsideTheWindow` | 3 |
| 112 | an arrow points at the anchor | no arrow | `MN-M` | `thePopoverChromeIsARoundedPanelWithNoArrow` | 3 |
| 113 | AppKit's native tooltip (look, delay unmeasured) | drawn by MetalUI, 1.0 s of tick time | `MN-P` | `aTooltipAppearsAfterTheHoverDelayOfTickTime` | 3 |
| 114 | an opaque view with no handler covering a context-menu view blocks its menu (C14) | an element registers a hitbox only with pointer handlers, so a cover that only paints does not block; a covering pointer target does | `MN-V` | `aPaintedCoverWithNoHitboxDoesNotBlockTheMenuBeneath`, `aCoveringPointerTargetWithoutAMenuBlocksTheMenuBeneath` | 1 |

Documented absences (the absences table): every row of §10; "SDL draws no
menu bar" and "an in-window context menu off Apple" (no SwiftUI there).

## 5. Lanes (three, strictly in order; a later lane may extend an earlier lane's files, `MN-S`)

| Lane | Owns | Builds |
|---|---|---|
| **1 — the seam and context menus** (Opus) | `MetalUIPlatform/{InputEvent,Platform,AccessibilityTree}.swift`, `MetalUIPlatform/Menus.swift` (new, minus `PlatformMenuBar`'s use); `MetalUI/{MenuContent,ContextMenu,MenuSession,MenuPanel,PullDownMenu}.swift` (new), `Handlers.swift`, `Frame.swift`, `Window.swift`, `WindowAccessibility.swift`, `AccessibilityTreeBuilder.swift`, `AccessibilityRequests.swift`; `MetalUIAppKit/AppKitAccessibility.swift` (roles, show-menu); `AppKitPlatform.swift` **only** an interim `presentMenu` returning `false`; `Backends/SDL/Sources/MetalUISDL/{SDLPlatform,AccessKitTree,AccessKitAdapter}.swift` (`presentMenu` → `false`, roles, `SHOW_CONTEXT_MENU`, the Menu key), `Backends/SDL/Sources/SDLBridge/SDLBridge.c` + header (right button, `MN-AD`); `Tests/MetalUITests/Fakes.swift` and every guard fixture's `presentMenu`; `ModifierTests`'/`OuterModifierMatrixTests`' fingerprints, `AccessibilityModifierTests`' size bound (`MN-AC`); `docs/migration.md` rows (incl. AppKit control-click); divergences 110, 114. | §2.1 (but `setMenuBar`), §2.2–§2.3 (not `.help`), §3.1–§3.3, §3.9, §3.11's `presentMenu` and input. |
| **2 — AppKit, the menu bar and `Menu`** (Opus) | `MetalUIAppKit/AppKitMenus.swift` (new), `AppKitPlatform.swift`; `MetalUI/{Commands,App,PullDownMenu}.swift` (`MN-AD`; lane 2 creates the anchor map); `Window.swift` (the command stage, the pull-down's anchor); `MetalUIPlatform/Platform.swift` + `Menus.swift` (`setMenuBar`, `PlatformMenuBar`); `SDLPlatform.swift` (`setMenuBar`); the fake `Platform` and the guard fixture; migration row. | §2.4, §2.5, §3.4, §3.5, §3.6, §3.11's `setMenuBar`. |
| **3 — popovers, tooltips, SDL input, demo** (Opus) | `MetalUI/{Popover,AnchoredPresentation,Tooltip}.swift` (new), `LegacyLowering.swift`/`Passes.swift` (the anchored lowering), `ContextMenu.swift` (`.help`), `Window.swift` (dismissal, tooltip stages), `Frame.swift` (tooltip paint); `MetalUIDemoContent` (new section file), `MetalUIDemo/main.swift`; `docs/verification/human-checks.md` group R; divergences 111–113. | §2.6, §3.7, §3.8, §3.10, §7, §8. |

Docs (`CLAUDE.md`, `AGENTS.md`, `README.md`, record index, record 03/04/05)
are the Record phase's, Sonnet.

## 6. Tests

Every test is written red first (against the declaration, or a stub
answering the wrong thing) and named in the record with its red reading. The
**mutation** column is the change that must redden it, applied by the lane's
verifier per `docs/practices/verifying-tests-can-fail.md` (commit first,
restore from a copy, full unfiltered suite, name every test reddened). All
root-package tests below are in `Tests/MetalUITests` through
`FakePlatformWindow` unless stated.

### 6.1 Lane 1 — `ContextMenuTests.swift`

| # | Test | Asserts | Mutation that must redden it |
|---|---|---|---|
| 1.1 | `aRightPressOverAContextMenuPresentsItsItemsToThePlatform` | native fake: one `presentMenu` call at the press point; items Copy, Delete, separator, More▸[A, B], Flag (on), Off (disabled), Short (⌘K shown), a disabled Text item | drop `Divider`'s separator (emit nothing) |
| 1.2 | `aChosenItemRunsItsActionFromInputUnderStateDispatch` | one element value placed twice; `.menuAction` for the second occurrence's menu writes the second's `@State` (`ID-F`) | run the action without `StateDispatch.dispatching` |
| 1.3 | `aMenuActionWithAStaleTokenRunsNothing` | an old token's item id runs nothing | skip the token comparison |
| 1.4 | `theMenuIsEvaluatedAtEachOpen` (C4c) | Flag chosen → reopened menu shows it off | cache the evaluated items at registration |
| 1.5 | `theInnermostContextMenuOpens` (C8) | inner menu at inner view, outer at outer-only area | rank the outermost region first |
| 1.6 | `aDisabledElementsMenuOpensWithEveryItemDisabled` (C9) | presented, every item `isEnabled == false`; a `.menuAction` for one runs nothing | register the region after the disabled gate's exit |
| 1.7 | `anEmptyContextMenuPresentsNothingAndDoesNotClaimThePress` (C10) | no call; `onInput` answers `false` | present an empty menu |
| 1.8 | `aSecondaryPressNeverRunsOnClickOrATap` (110) | right press+release over `Button`, `.onTapGesture`, `.draggable`, `TextField` runs/opens/focuses nothing | let `.rightMouseDown` fall through to `dispatchGestures` as a `.mouseDown` |
| 1.9 | `aPresentationOnAHigherLayerBlocksAContextMenuBeneath` | a `Deferred` presentation over the region: no menu | drop the layer rule from the ranking filter |
| 1.10 | `aCoveringPointerTargetWithoutAMenuBlocksTheMenuBeneath` (C14, `MN-V`) | a same-layer `onClick` cover with no menu: no menu; `Box { Button }.contextMenu` over the button: menu opens | rank the contextual regions alone |
| 1.11 | `aContextMenuItemsShortcutDoesNotFireWhileClosed` (C12) | ⌘K runs nothing | register item shortcuts in `FocusRegistry` |
| 1.12 | `aDisabledItemCannotBeChosen` | `.menuAction` naming `.disabled(true)`'s id runs nothing | skip the item's `isEnabled` check |
| 1.13 | `aToggleItemWritesItsBinding` (C4) | `!isOn` written, from input | write `isOn` unchanged |
| 1.14 | `menuItemsResolveDisabledThroughTheEnvironmentScope` | `.disabled(true)` item disabled; `.disabled(false)` under a disabled ancestor disabled | read the scope's own flag instead of applying its write |
| 1.15 | `aContextMenuMovesNoIDAndWritesNoStateTableEntry` | `StyledElement` ids and `StateTable` count unchanged by `.contextMenu`; a proposal content numbers from 0 under `ContextualModifier` | wrap the `StyledElement` spelling in `ContextualModifier` |
| 1.16 | `aDeclinedNativeMenuOpensInWindowAtThePointer` | non-native fake: panel origin = pointer, row rects from `MenuPanel.layout` | open the panel only when `presentMenu` answered `true` |
| 1.17 | `theInWindowMenuFlipsAndClampsInsideTheWindow` | near the right/bottom edges: flipped, then clamped 4 pt | drop the flip (clamp only) |
| 1.18 | `arrowKeysMoveTheHighlightOverEnabledRowsWithoutWrapping` | ↓ skips separator and disabled; ↓ at the last stays | allow disabled rows |
| 1.19 | `returnChoosesTheHighlightedItemAndClosesTheMenu` | action ran once; session gone | leave the session open after choosing |
| 1.20 | `rightArrowOpensASubmenuAndLeftArrowClosesIt` | levels 2 then 1; submenu beside its row | open the submenu at the pointer |
| 1.21 | `hoveringASubmenuRowOpensItAndAShallowerRowClosesIt` | moves open and close levels | never close deeper levels on hover |
| 1.22 | `escapeClosesTheDeepestLevelFirst` | two Escapes: submenu, then root | close every level on the first Escape |
| 1.23 | `aPressOutsideTheMenuDismissesItAndReachesNothingBeneath` | session gone; a `Button` beneath did not run | return `false` after dismissing |
| 1.24 | `aClickOrAPressDragReleaseOnAnItemChoosesIt` | click chooses; right-down, move, right-up over an item chooses; right-up without a move does not | choose on the opening press's release without a move |
| 1.25 | `theOpenMenuIsPaintedAboveEverything` | the panel's primitives are the scene's last, above a drag preview fixture | emit before `paintDragPreview()` |
| 1.26 | `theInWindowMenuPublishesAMenuOfMenuItems` | `.menu` root with `.menuItem`/`.menuItemCheckBox` children, disabled flag, focus on the highlight; `.press(item)` chooses | publish the rows as `.button` |
| 1.27 | `theInWindowMenuWritesNoStateTableEntry` | table count equal open vs closed | store the session under `StateTable` |
| 1.28 | `aResizeOrLosingKeyDismissesTheInWindowMenu` | each closes it | ignore `controlActiveState` |
| 1.29 | `theContextMenuKeysAreShiftF10AndTheMenuKeyOffAppleOnly` | `ContextMenuKeys.opens` rows for `.other` true, `.mac` false; on this platform Shift-F10 opens nothing | answer `true` on `.mac` |
| 1.30 | `aShowMenuRequestOpensTheElementsMenu` (C11) | only a menu-bearing node advertises `.showMenu`; the request presents at its bottom-leading corner | advertise `.showMenu` on every node |
| 1.31 | (**lane 2**, `MN-AD`) `aPullDownMenuPublishesAsAMenuButtonAndOpensBelowItself` (M1) | role `.menuButton`; click presents at bounds' bottom-leading | present at the pointer |
| 1.32 | (**lane 2**) `aPullDownMenuOpensFromSpaceAndReturnAndNotWhenDisabled` | keys open; `.disabled(true)` does not | ignore the disabled gate |
| 1.33 | `handlersGainsOneReferenceMember` | `MemoryLayout<Handlers>.size == 464` (and `AccessibilityModifierTests`' existing bound raised by 8, `MN-AC`) | store the closure and help string inline |
| 1.35 | `aContextMenuUnderAllowsHitTestingFalseDoesNotOpen` (C13, `MN-U`) | no `presentMenu`; the press unclaimed; the show-menu action still advertised | register the region outside the gate |
| 1.36 | `aPaintedCoverWithNoHitboxDoesNotBlockTheMenuBeneath` (114) | a background-only `Box` over the region: menu opens | require a hitbox owned by the region's element or a descendant |
| 1.37 | `theInWindowMenuIsPublishedAndPressableUnderModalIsolation` (`MN-AB`) | inside an `.isModal` sheet: the panel's `.menu` root published, `.press(item)` runs it | build the panel's root inside the isolation filter |

AppKit-side, lane 1, in `AppKitAccessibilityTests` (existing file):
1.34 `theAppKitBridgePublishesTheMenuRolesAndPerformsShowMenu` — roles
`AXMenu`/`AXMenuItem`/`AXMenuButton`/`AXPopover`, the mark char for a `"1"`
checkbox item, `accessibilityPerformShowMenu` → one `.showMenu` request and
`false` without the action. Mutation: map `.menuButton` to `AXButton`.

`Backends/SDL/Tests/MetalUISDLTests/AccessKitMenuTests.swift` (new, lane 1):
S1.1 `theAccessKitBridgeMapsTheMenuRolesAndShowContextMenu` (roles, toggled,
`has_popup`, non-modal dialog, the action both ways; mutation: drop
`SHOW_CONTEXT_MENU`); S1.2 `anSDLWindowDeclinesToPresentAMenu` (`presentMenu`
→ `false`; arms `armMainRunLoopExitCheck()`).

Guards (lane 1), `MenuCompileGuards.swift`, each whole-file `typecheckFile`,
each mutated red once: G1.1 `anOutsideTypeCannotConformToMenuContent`; G1.2
`theMenuSpellingsCompileFromAPlainImport` (`.contextMenu` on `Box` and on an
`HStack`, `Menu("…") { }` as a submenu item, `Divider()`, a `Toggle` and a `.disabled(true)` and a
`.keyboardShortcut` item, `if`/`for` in the builder); G1.3
`aPickerIsNotAMenuItem`; G1.4 `aPlatformWindowWithoutPresentMenuDoesNotCompile`.

### 6.2 Lane 2 — `AppKitMenuTests.swift` (real `AppKitWindow`/host view) and `CommandsTests.swift` (fake)

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 2.1 | `anAppKitMenuIsBuiltFromThePlatformMenu` | titles, separators, submenus, `.on`, disabled, key equivalent + mask, `autoenablesItems == false` | `autoenablesItems = true` |
| 2.2 | `aChosenNativeItemArrivesAsAMenuActionAfterThePopUpReturns` | presenter performs item 3; `onInput` sees `.menuAction(token, 3)` only after `presentMenu` returned (a flag set on return) | deliver inside the presenter |
| 2.3 | `aDismissedNativeMenuArrivesAsANilMenuAction` | presenter chooses nothing → `item: nil` | send nothing on dismissal |
| 2.4 | `aRightMouseDownAndAControlClickReachOnInputAsRightMouseDown` | real `NSEvent`s to the host view; the control-click's up is `.rightMouseUp` | drop the control mapping |
| 2.5 | `theHostViewOffersACommandKeyToTheWindowBeforeTheMainMenu` | `performKeyEquivalent` returns the window's answer (`true` for a claimed ⌘K, `false` for an unclaimed ⌘J) | return `false` always |
| 2.6 | `aButtonsShortcutWinsOverACommandsAndFiresOnce` (`MN-J`) | Button ⌘R + command ⌘R: button ran, command did not | put the command stage before `dispatchShortcut` |
| 2.7 | `aCommandsShortcutFiresWhenNothingInTheWindowClaimsIt` | ⌘J runs the command once | drop the command stage |
| 2.8 | `aDisabledCommandsShortcutDoesNothing` | `.disabled(true)` command: nothing, key unclaimed | skip `isEnabled` |
| 2.9 | `aKeyEquivalentDeclinedByTheWindowIsNotDeliveredAgainAsAKeyDown` | one `.keyDown` reaches `onInput` for performKeyEquivalent + keyDown of one event | remove the identity check |
| 2.10 | `theDefaultMenuBarHasTheStandardMenus` | `menuBarContent()` with no commands: App/File/Edit/Window titles and items, shortcuts, standard actions (§2.5); Help absent while empty | drop `.appTermination` |
| 2.11 | `aCommandMenuIsInsertedBeforeTheWindowMenu` | order …Edit, Tools, Window | append after Window |
| 2.12 | `commandGroupsPlaceTheirItemsBeforeAfterAndReplacing` | after `.newItem`, before `.appTermination`, replacing `.pasteboard`/`.help` | treat `replacing` as `after` |
| 2.13 | `theMainMenuMapsStandardActionsToAppKitSelectors` | `terminate:`, `hide:`, …, `selectAll:` on the built `NSApp.mainMenu` | map `.quit` to `performClose:` |
| 2.14 | `theEditMenuReachesTheFocusedFieldAsItsKeys` | `copy:` delivers ⌘C; `validateMenuItem` true only with a caret | validate `true` always |
| 2.15 | `aMenuBarItemRunsItsCommand` | performing the built item runs the command action once | target nothing |
| 2.16 | `theMenuBarIsRefreshedWhenAMenuOpens` | toggled state after `menuNeedsUpdate` | build items once at install |
| 2.17 | `everyAppInstallsTheDefaultMenuBar` (fake `Platform`) | `setMenuBar` called once by `App(platform:)` | install only from `commands` |
| 2.18 | `anEditKeyTheWindowDeclinedIsNotDeliveredAgainByTheEditMenu` (`MN-AA`) | ⌘Z declined by the window, then `undo:` with that event current: one `.keyDown`; `undo:` from a menu click: one | drop the identity check in the action |

Tests 2.13–2.16 save and restore `NSApp.mainMenu` (`MN-AC` item 3).

`Backends/SDL` (lane 2): S2.1 `sdlRecordsTheMenuBarAndDrawsNothing`.

Guards (lane 2), `CommandsCompileGuards.swift`: G2.1
`theCommandsSpellingsCompileFromAPlainImport` (also `commands(content:)` spelled out and `Menu("…")` as a view, `MN-X`, `MN-AD`); G2.2
`aPlatformWithoutSetMenuBarDoesNotCompile`.

### 6.3 Lane 3 — `PopoverTests.swift`, `TooltipTests.swift`

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 3.1 | `thePopoverSitsOnItsArrowEdgeOfTheAnchor` (×4, P1) | 8-pt gap on each edge's side, centred across | swap `.top`/`.bottom` |
| 3.2 | `theDefaultArrowEdgeIsTop` (P7, `MN-X`) | no edge and `arrowEdge: nil` both above | map `nil` to `.bottom` |
| 3.3 | `aPopoverThatWouldLeaveTheWindowFlipsToTheOppositeEdge` (P5, 111) | flipped | drop the flip |
| 3.4 | `aPopoverThatFitsNeitherSideIsClampedInsideTheWindow` (111) | on its side, clamped 8 pt | flip anyway |
| 3.5 | `aPressOutsideThePopoverWritesFalseAndReachesWhatItLandsOn` (P4a, `MN-Y`) | binding false from input; the `Button` beneath ran once | claim the press after dismissing |
| 3.6 | `aPressInsideThePopoverReachesItsContent` | inner `Button` runs; popover stays | dismiss on every press |
| 3.7 | `escapeDismissesTheTopmostPopoverBeforeTheKeymap` | keymap Escape binding did not run; inner popover first | run the stage after `dispatchAction` |
| 3.8 | `aPopoverIsAPresentationOnAHigherLayer` | a press and a drop on the chrome's padding reach nothing beneath; an ancestor's `DragGesture` does not reach a press inside | drop the chrome's blocking hitbox (`MN-Z`); register at the declarer's layer |
| 3.9 | `thePopoverPublishesAPopoverNodeAndIsolatesNothing` (P2/P2b) | `.popover` node holding the content; the window's other nodes still published | mark it `.isModal` |
| 3.10 | `aPopoverAddsOneIdentityLevelOnlyForItsCaller` | content at 0 under the wrapper; siblings' ids unmoved | put the slot at `-1` (collides with `.overlay`, `MC-P`) |
| 3.11 | `aRepresentedPopoversContentStartsFresh` | `@State` inside reset after dismiss/present (`ID-C`) | keep the slot produced while dismissed |
| 3.12 | `popoverItemFollowsTheItemAndResetsOnANewID` | nil → none; id 1 → shown; id 2 → fresh state | drop the `IdentifiedGroup` |
| 3.13 | `aPopoverFollowsItsAnchorWithinOneFrame` | anchor moved → `requestAnotherFrame`, next frame placed at the new bounds | no another-frame request |
| 3.14 | `anInitiallyPresentedPopoverAppearsOnTheSecondFrame` | frame 0 none, frame 1 shown | produce with a zero anchor on frame 0 |
| 3.15 | `aPopoverWritesNoStateTableEntry` | table count equal shown vs not (beyond its content's own) | keep the anchor in `StateTable` |
| 3.16 | `thePopoverChromeIsARoundedPanelWithNoArrow` (112) | one `.surface` rect radius 10 + shadow, no other primitive than the content's | (pin of the absence: add a triangle path) |
| 3.17 | `aTooltipAppearsAfterTheHoverDelayOfTickTime` (113) | ticks 10.0 (stamp), 10.9 none, 11.0 shown | delay 0 |
| 3.18 | `theTooltipDelayIsStampedFromTheFirstTickAfterEntering` | `lastTick` 0, enter, tick 50.0 stamps, 50.5 none | stamp from the stale `lastTick` |
| 3.19 | `aPressAWheelAKeyOrLeavingHidesTheTooltip` (×4) | hidden | drop the press rule |
| 3.20 | `aHiddenTooltipReturnsOnlyAfterLeavingAndReentering` | moves inside after a press: never; leave + enter + delay: shown | clear `spent` on any move |
| 3.21 | `theTooltipIsPlacedBelowThePointerAndFlippedInsideTheWindow` | 18 pt below; near the bottom, above; clamped 4 pt | no flip |
| 3.22 | `helpPublishesTheSameTreeAsAccessibilityHint` (H1–H5) | trees equal for each shape: one element, Button with outer/inner hint (H3/H3b), container distribution (H4), outer beats inner (H5), both vocabularies | write the help as the label |
| 3.23 | `aHelpRegionAddsNoPointerTarget` | a click passes to the element beneath; `isPointerTarget` unchanged | make the region opaque |
| 3.24 | `thePendingTooltipKeepsTheLinkAwakeOnlyWhilePending` | pause calls: unpaused while pending, paused once shown and idle | leave the link paused |
| 3.25 | `theTooltipIsPaintedAboveEverything` | its primitives last, after an open menu fixture | emit before the panel |
| 3.26 | `aPressOnTheAnchorDismissesThePopoverAndIsConsumed` (`MN-Y` item 2) | a `Button { shown.toggle() }` anchor: false after the press, still false next frame | treat the anchor as any outside point |

`Backends/SDL` (**lane 1** since `MN-AD`): S3.1 `aRightButtonEventBecomesARightMouseDownAndUp`
(C-exported constants; `armMainRunLoopExitCheck()`); S3.2
`theApplicationKeyIsTheMenuFunctionKey`.

Demo: `menusDemoContent()` joins `buildEveryProductionTree` (the existing
`everyProductionTreeBuildsOnAOneMegabyteThread` covers it; no new test).

Guards (lane 3), `PopoverCompileGuards.swift`: G3.1
`thePopoverAndHelpSpellingsCompileFromAPlainImport`; G3.2
`aPopoverHasNoAttachmentAnchorParameter`.

### 6.4 Counts (expected; the lanes re-take them)

Root package (revised by `MN-AD`): 2227 + 35 (lane 1: 1.1–1.30, 1.33–1.37)
+ 20 (lane 2: 2.1–2.18, 1.31, 1.32) + 26 (lane 3: 3.1–3.26; 3.1 and 3.19
count once each if parameterized as one `@Test` with arguments) = **2308**;
guards 133 + 4 + 2 + 2 = **141**; goldens 0. `Backends/SDL`
`MetalUISDLTests` +5. `MemoryLayout<Handlers>.size` 456 → 464; the smallest
thread building every production tree re-measured. Live divergences 76 → 81
(110–114), next label 115.

## 7. The demo (`METALUI_MENUS_DEMO=1`, lane 3)

`Sources/MetalUIDemoContent/MenusDemo.swift`, `menusDemoContent()` in its
own function (Windows 1 MB stack): a 200×100 card with `.contextMenu { Copy,
Rename, Divider, Menu("Colour") { Red, Green, Blue }, Toggle("Pinned"),
Button("Delete") {}.disabled(true), Button("Duplicate") {}.keyboardShortcut("d") }`
and a status line showing the last choice; `Button("Show popover")` with
`.popover(isPresented:)` holding a text, a `TextField` and a Close button;
three `Text`s with `.help(…)`; `Menu("Actions") { … }`. `MetalUIDemo/main.swift`
calls `app.commands { CommandMenu("Demo") { Button("Say Hello") {…}
.keyboardShortcut("h", modifiers: [.command, .shift]); Toggle("Pinned", …) };
CommandGroup(after: .newItem) { Button("New Note") {…}.keyboardShortcut("n") } }`
in this mode only. **The default demo and every other flag are unchanged**:
0 px against `b9da519` in all fourteen offscreen images (the fourteen
include no menus-demo image).

## 8. Human checks (`docs/verification/human-checks.md`, new group R, lane 3)

R1 a right click and a control-click on the card open a native menu with the
items, separator, submenu, ✓ and ⌘D as a SwiftUI app's does (compare against
`swiftui-menus-popovers.swift`'s C1 view hosted in a window); R2 under
`Backends/SDL`'s demo (or `METALUI_MENUS_DEMO=1` with an SDL `App`) the drawn
menu: hover, submenu, ↑↓→←, Return, Escape, outside click, Shift-F10 on
Linux/Windows; R3 the menu bar: About/Hide/Quit, ⌘Q quits, Edit ▸ Copy/Paste
reach a focused `TextField` by click and by key, the Demo menu; R4 ⌘D/⌘⇧H
fire once, and re-run `swiftui-commands.swift` unlocked with a key window to
settle `MN-J` item 4's order; R5 the popover's look and placement, flipping at
the window's edge, Escape, an outside click (and whether a native transient
`NSPopover`'s outside click reaches what it lands on — re-run P3/P4
unlocked; `MN-Y` passes it through on P4a's reading); R6 the tooltip's delay and look against a native AppKit tooltip
(re-run H7 unlocked); R7 VoiceOver: VO-Shift-M on the card opens its menu,
the popover reads as a popover, `.help` is read as help; R8 a right click on
a `Button` does not press it (divergence 110; a SwiftUI `Button` does).
Each item names its headless pin.

## 9. Must not move

Identity and state retention (`theSevenRetentionSlotsAreMutuallyDistinct`,
`MC-A`/`MC-C`/`MC-P` numbering, `.id()` outermost): no existing spelling gains
a level; `.contextMenu`/`.help` on a `StyledElement` return `Self`; the
proposal wrappers and `.popover` add one level for their callers only; the
menu panel and tooltip write no `StateTable` entry. Hit testing: the
contextual regions are non-opaque; a secondary press reaches no existing
stage. Accessibility: additive (five roles, one action, one request);
`.help` reuses the hint path. Animation, focus, `List` windowing and
`TB-AH`, `Deferred` (the popover uses its own `AnchoredPresentation`), text
input (AppKit ⌘-keys now arrive through `performKeyEquivalent` — one
delivery, test 2.9 — and reach the same pipeline). 0 px in all fourteen
offscreen images (`docs/probes/demo-pixels/compare.sh <scratch> b9da519
HEAD`); `DemoFrameDeterminismTests`' `Expected.swift` unedited; 0 `warning:`
on both build systems; `MetalUILayout` imports only `MetalUICore`;
`MetalUIScene` only `MetalUIShaderTypes`; `Backends/SDL` and a
`swift:6.4-noble` container build; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
green. **No new drawable primitive**: the panel, the chrome and the tooltip
are rects, text and the existing shadow, so `TE-AD`'s parity rule is not
triggered.

## 10. Deferred (owner none unless stated)

| Item | Why | Owner |
|---|---|---|
| `Picker`, `Section`, `Label`/image items in a menu | the picker's options are found only inside layout; images need SF Symbols | none |
| `Divider` as a view | needs the stack's axis in the environment | none |
| menu type-select, scrolling a menu taller than the window, a submenu-open delay | not asked for | none |
| `.contextMenu(forSelectionType:)`, `.contextMenu(menuItems:preview:)` | a selection-aware or previewed menu is a second design | none |
| `.popover(attachmentAnchor:)`, `.presentationCompactAdaptation`, a drawn arrow (112) | not asked for; a look | none |
| `.menuStyle`, `.menuIndicator`, `.menuOrder`, `Menu(primaryAction:)` | styles MetalUI does not model | none |
| further `CommandGroupPlacement`s (`.saveItem`, `.printItem`, `.textFormatting`, `.toolbar`, `.sidebar`, `.importExport`, `.systemServices`, `.singleWindowList`), `.commandsRemoved()`, `FocusedValue`/`focusedSceneValue` | scene machinery MetalUI has none of | none |
| an in-window menu bar on Linux/Windows | SDL has no native bar; shortcuts already work | none |
| a native tooltip on AppKit (113) | `MN-P` | none |
| `.help(Text)`, `.help` on a menu item | small; not asked for | none |
| the key-window order of a menu/Button shortcut, a popover's outside-click dismissal and Escape, the tooltip delay, control-click | unmeasured in a locked session | human checks R4, R5, R6, R1 |
| Windows' open-on-release context-menu convention | MetalUI opens on the press everywhere (`MN-E` item 3) | none |

## 11. Critic round (2026-10-02)

Both probes re-run as committed first (byte-identical to their headers);
four arms appended to the menus probe (C11n, C13c, C13, C14) and the SDK's
`SwiftUI.swiftinterface` read for every copied spelling. Fixed in this spec,
each by a ruling: the contextual region sits inside the `allowsHitTesting`
gate (C13, `MN-U`); one lookup ranks pointer hitboxes and regions together
so a covering pointer target blocks, a painted-only cover does not
(divergence 114, `MN-V`); show-menu's `false` on a non-menu node is now
measured (C11n, `MN-W`); `arrowEdge: Edge? = nil` and `commands(content:)`
(`MN-X`); an outside press dismisses and passes through, the anchor's press
is consumed (P4a, `MN-Y`); the popover chrome's blocking hitbox (`MN-Z`); no
second delivery of a declined Edit key (`MN-AA`); the in-window menu above
modal isolation (`MN-AB`); control-click AppKit-only with a migration note,
the existing `Handlers` size pin, the main menu in the shared test process
(`MN-AC`); lanes rebalanced and counts re-derived (`MN-AD`).
