# How do I handle clicks, gestures, keys and text?

Input in MetalUI is SwiftUI's vocabulary over one pointer ranking and one key pipeline. Most of
what an app author needs is the same as in SwiftUI; this guide covers the four places where
MetalUI differs enough to cost an afternoon: what a click does and does not focus, the single
gesture arena, where a key goes, and a text field's selection. The reference is
[`api-overview.md`](../api-overview.md#input-gestures-focus--a--m). The blocks below are
compiled by the test suite and the claims are driven through a headless window
([`testing.md`](../testing.md); [`README.md`](README.md#how-the-code-blocks-are-checked)).

## How do I react to a button, and what does a click focus?

`Button` and `Toggle` take a closure and a `Binding`, as in SwiftUI. A click presses them; it does
not focus them. Tab reaches every control, and only a `TextField`, a `TextEditor`, a selectable
`List` and `.focusable(interactions: .edit)` focus on a click (divergence 94; pin:
`aButtonIsFocusableButAClickDoesNotFocusIt`). A right click presses nothing; it opens a context
menu and nothing else (divergence 110; pin: `aSecondaryPressNeverRunsOnClickOrATap`).

```swift
import MetalUI

/// A button and a toggle over `@State`.
struct InputControls: Component {
    @State var count = 0
    @State var notifications = true

    var content: some ElementGroup {
        Button("Add") { count += 1 }
        Toggle("Notifications", isOn: $notifications)
        Text("Count \(count)")
    }
}

@MainActor
func inputControlsRoot() -> some Element {
    VStack(alignment: .leading) { InputControls() }
}
```

A test presses the button and leaves focus alone (pin:
`theInputGuideAClickPressesAButtonWithoutFocusingIt`). Nothing is focused when a window first
shows (divergence 186).

## How do I use gestures, and what is the arena?

`TapGesture`, `LongPressGesture`, `DragGesture`, `SpatialTapGesture`, `MagnifyGesture` and
`RotateGesture` compose with `.exclusively(before:)` and `.simultaneously(with:)` as in SwiftUI.
MetalUI resolves them in **one arena per press**, built from the one hit-test ranking and the
target's ancestors in its own layer. Three consequences you will meet:

- `.gesture` sits beside `onClick`, not instead of it, and a secondary or other-button press
  forms its own arena that runs only drags naming that button (`DragGesture(button:)`; pin:
  `aButtonArenaHasOnlyItsButtonsDragLeaves`).
- `CoordinateSpace.global` is the window's content space, not SwiftUI's (divergence 139; pin:
  `aSpatialTapInGlobalSpaceReportsTheWindowPoint`).
- `DragGesture`, `MagnifyGesture` and `RotateGesture` have `onCancelled`, which SwiftUI does not
  (divergence 236). It runs once for a gesture that had reported a change and whose arena was
  dropped without `onEnded`. The case you will hit is a lost release: a new primary press on the
  same element while the old press is still down ends the old one with `onCancelled`, then
  starts a fresh drag. The headless test below sends exactly those events and reads
  `changed, changed, cancelled, changed, ended` (pins: `theInputGuideALostReleaseRunsOnCancelledOnce`, `aPrimaryPressOnTheSameElementAfterALostReleaseCancelsTheReportedDrag`).

```swift
/// What a gesture saw, in order.
@MainActor
final class InputGestureLog {
    var entries: [String] = []
}

/// A drag pad that logs `changed`, `ended` and `cancelled`.
@MainActor
func inputDragPad(_ log: InputGestureLog) -> some Element {
    Rectangle()
        .frame(width: Pixels(200), height: Pixels(100))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in log.entries.append("changed") }
                .onEnded { _ in log.entries.append("ended") }
                .onCancelled { log.entries.append("cancelled") }
        )
}
```

## How do I let the user drag the window by a custom title bar?

Attach `WindowDragGesture` (SwiftUI's macOS 15 spelling, offered on every platform) to the handle.
After a 5-point move it asks the platform to move the window and ends, cutting the other
gestures of that press (divergence 275). The headless window counts the requests (pin:
`theInputGuideAWindowDragHandleAsksThePlatformOnce`). Only AppKit moves the window; SDL records
the request and the system title bar drags itself (divergence 276). An `.opacity(0)` handle still
captures; use `.hidden()` to remove one (divergence 277).

```swift
/// A full-window viewport with a 32-point drag handle on top of it.
@MainActor
func inputWindowDragHandle() -> some Element {
    ZStack(alignment: .top) {
        Rectangle().frame(width: Pixels(300), height: Pixels(300))
        Rectangle().frame(width: Pixels(300), height: Pixels(32)).gesture(WindowDragGesture())
    }
}
```

## Where does a key go?

Keys walk one pipeline: the window's `Keymap` first, then `onKeyPress` handlers outermost
first, then a focused field's editing keys, then the bubbling `onKey`, then Tab; `onKeyPress` handlers walk the focus chain outermost first (pin:
`onKeyPressRunsOutermostFirstAlongTheFocusChain`). With nothing
focused, keys go to the **key region** under the pointer: `.hoverKeyRegion()` marks one (pin:
`portableWithNothingFocusedTheHoveredKeyRegionReceivesKeys`). That is
how a canvas takes shortcuts without stealing a text field's keys. The test hovers the region,
presses Space and reads the log (pin: `theInputGuideAKeyGoesToTheKeyRegionUnderThePointer`).

```swift
/// What a key handler saw.
@MainActor
final class InputKeyLog {
    var entries: [String] = []
}

/// A canvas stand-in that is a key region and handles Space.
@MainActor
func inputKeyRegion(_ log: InputKeyLog) -> some Element {
    Rectangle()
        .frame(width: Pixels(120), height: Pixels(80))
        .hoverKeyRegion()
        .onKeyPress(keys: [.space]) { _ in
            log.entries.append("space")
            return .handled
        }
}
```

Things that differ from SwiftUI. A character typed in a focused field reaches `onKeyPress` once,
as `.down`, never during composition (divergence 187). A native-only menu item's ⌘-key (Quit,
Hide) is offered to `onKeyPress` first, so a catch-all `.handled` swallows ⌘Q (divergence 188).
A shortcut's default modifier is `EventModifiers.primary`, which is ⌘ on Apple and Control
elsewhere. On one keyboard layer `onKeyPress` and `.focusable()` are order-free (divergence 185).

## How do I read and set a text field's selection?

`TextField` and `TextEditor` take a `Binding<String>`, and, from macOS 15's spelling, a
`Binding<TextSelection?>`. Writing the binding sets the selection; the field publishes its own
as the user moves it. The block needs `@available(macOS 15, *)` because `TextSelection` does
(this package supports macOS 14). The test writes "Select all" and reads the label change
(pin: `theInputGuideSelectAllWritesTheSelectionBinding`).

```swift
/// A field whose selection the app can read and write.
@available(macOS 15, *)
struct InputRename: Component {
    @State var title = "Quarterly plan"
    @State var selection: TextSelection?

    var content: some ElementGroup {
        TextField("Title", text: $title, selection: $selection)
        Button("Select all") {
            selection = TextSelection(range: title.startIndex..<title.endIndex)
        }
        Text(selection == nil ? "no selection" : "selection set")
    }
}

@available(macOS 15, *)
@MainActor
func inputRenameRoot() -> some Element {
    VStack(alignment: .leading) { InputRename() }
}
```

While a field is focused, printable keys arrive as text input, so a plain-letter `Keymap` binding
is silent. [`testing.md`](../testing.md) has a recipe that types into a field and commits on a
shortcut Return.

## Divergences you will hit

Each row is in [`divergences.md`](../divergences.md); the list is checked against it.

- divergence 94: a click does not focus a `Button` or a plain `.focusable()`.
- divergence 110: a secondary click runs no tap, click, drag or text press; it opens context menus.
- divergence 139: `CoordinateSpace.global` is the window's content space.
- divergence 185: `onKeyPress` and `.focusable()` are order-free on one keyboard layer.
- divergence 186: nothing is focused when a window first shows.
- divergence 187: a typed character is offered to `onKeyPress` once, as `.down`.
- divergence 188: a native-only menu item's ⌘-key reaches `onKeyPress` first.
- divergence 236: `onCancelled` exists on drag, magnify and rotate.
- divergence 275: a window drag cuts its neighbours in the press.
- divergence 276: a window drag moves the window on AppKit only.
- divergence 277: an `.opacity(0)` window-drag handle still captures.

Back to [layout](layout.md) and [state and identity](state-and-identity.md).
