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
  `changed, changed, cancelled, changed, ended` (pin: `theInputGuideALostReleaseRunsOnCancelledOnce`, `aPrimaryPressOnTheSameElementAfterALostReleaseCancelsTheReportedDrag`).

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

## How do I end editing when the user clicks empty chrome?

A click does not resign a focused field, as in SwiftUI. An app that wants "click anywhere else to
finish editing" says so on a container: `.resignsFocusOnPress()` makes a primary press inside it
resign the focused field. It is opt-in, MetalUI-only (SwiftUI has no such modifier), and it routes
no key by hover (pin: `aResignRegionRoutesNoKeysByHover`). A secondary or other-button press never
resigns (pin: `aSecondaryAndOtherPressResignNothing`). Without the modifier a press elsewhere leaves a
focused field alone (pin: `aPressElsewhereDoesNotResignAFocusedField`). The headless test types "Ada",
clicks the panel, and reads that nothing is focused while the typed text stays (pin:
`theInputGuideAClickOnInertChromeEndsEditing`, `aPressOnInertChromeResignsAFocusedField`).

```swift
/// A field and an inert panel: a click on the panel ends editing.
struct InputCommit: Component {
    @State var name = ""

    var content: some ElementGroup {
        TextField("Name", text: $name)
            .frame(width: Pixels(200), height: Pixels(24))
            .accessibilityIdentifier("name")
        Box().frame(width: Pixels(200), height: Pixels(80)).background(.surface).id("panel")
        Text("Hello \(name)")
    }
}

@MainActor
func inputResignRoot() -> some Element {
    VStack(alignment: .leading) { InputCommit() }
        .resignsFocusOnPress()
}
```

## How do I test a field with an input method?

An input method (Chinese pinyin, Japanese kana) marks text in the field before it commits a
candidate. `TestWindow` drives that with four verbs that send the platforms' own events through the
real window: `setMarkedText(_:selectedRange:)`, `commitMarkedText()` (AppKit's `unmarkText`),
`commitMarkedText(_:)` (`insertText`, a candidate replaces the marked text) and `cancelMarkedText()`.
Each answers `false` and sends nothing when no text field holds the caret (pin:
`anInputMethodCannotBeDrivenWithoutAFocusedField`). While text is marked the field shows it and the
model has heard nothing (pin: `aMarkedTextIsInTheFieldNotInTheBinding`); a commit writes once (pin:
`commitMarkedTextCommitsTheMarkedTextOnce`, `commitMarkedTextWithACandidateReplacesTheMarkedText`);
a cancel restores the field and writes nothing (pin: `cancelMarkedTextRestoresTheFieldAndWritesNothing`).
The recipe is in [`testing.md`](../testing.md#recipe-driving-an-input-method); the test below runs this
block (pin: `theInputGuideAnInputMethodComposesCommitsAndCancels`, `theInputMethodRecipeRuns`).

```swift
/// What a field's model heard, in order.
@MainActor
final class InputComposeModel {
    var text = "hello"
    var writes: [String] = []
}

/// A field over a plain class, so a test sees every write.
@MainActor
func inputComposeRoot(_ model: InputComposeModel) -> some Element {
    VStack(alignment: .leading) {
        TextField("Name", text: model.text) { model.writes.append($0); model.text = $0 }
            .frame(width: Pixels(200), height: Pixels(24))
            .accessibilityIdentifier("name")
    }
}
```

Two divergences follow from MetalUI's field. The accessibility value of a composing field is the
committed text, not the marked text (divergence 325; pin:
`theFieldsAccessibilityValueIsTheCommittedTextWhileComposing`), and a selection binding written while
composing is held back until the commit, whose publish supersedes it (divergence 326; pin:
`aSelectionWrittenWhileComposingIsHeldBackAndSupersededByTheCommit`).

## How do I give a region my own cursor, and a hand on SDL?

`.pointerStyle(.image(_:hotSpot:))` shows a bitmap as the pointer, SwiftUI's macOS 15 spelling. The
cursor is the `Image`'s bitmap at `pixels / scale` points, so a 48-pixel bitmap at `scale: 2` is a
24-point cursor on every display (pin: `anImageCursorSendsItsPointSizeAndHotSpot`). `hotSpot` is a
fraction of that size from the top-left, and one outside the unit square is clamped onto the image
(divergence 465; pin: `aHotSpotOutsideTheUnitSquareClampsToTheImage`). The cursor is identified by the
bitmap, so building the `Image` again each frame still sends the platform one cursor (pin:
`aBitmapRebuiltEveryFrameSendsOneCursor`). The test reads what the window sent through
`TestWindow.pointerStyle` (pin: `theInputGuideAnImageCursorSendsItsBitmap`).

SDL has no hand or zoom cursor: `.grabIdle` shows its move cursor and `.zoomIn` its arrow, and no art is
bundled. Where that is wrong for your app, draw a hand yourself and put it on the region with
`.image`, keeping a 2x bitmap for 2x displays (`scale: 2`). The platform picks by display scale on SDL;
AppKit scales from the bitmap.

```swift
/// A bitmap drawn in code: a filled disc of `side` pixels.
func inputDisc(side: Int) -> ImageBitmap {
    var rgba: [UInt8] = []
    let centre = Double(side) / 2
    for y in 0..<side {
        for x in 0..<side {
            let dx = Double(x) + 0.5 - centre, dy = Double(y) + 0.5 - centre
            let inside = dx * dx + dy * dy <= centre * centre
            rgba += inside ? [30, 120, 255, 255] : [0, 0, 0, 0]
        }
    }
    return ImageBitmap(width: side, height: side, rgba: rgba)
}

/// A region whose pointer is the disc, hot spot at its centre, drawn at 2x.
@MainActor
func inputCursorRegion(_ disc: ImageBitmap) -> some Element {
    Rectangle()
        .frame(width: Pixels(120), height: Pixels(80))
        .pointerStyle(.image(Image(decorative: disc, scale: 2), hotSpot: .center))
}
```

## How do I copy and paste my own type?

`copyable(_:)`, `cuttable(for:action:)` and `pasteDestination(for:action:validator:)` are SwiftUI's
spellings over MetalUI's `Transferable`. The primary-modifier C, X and V (and the Edit menu's items)
reach the handler of the element that holds focus or is an ancestor of the focused element, innermost
first, so a handler needs `.focusable()` (pin: `theInputGuideACopyableGraphWritesItsTypeAndItsTextFallback`). A
copy writes one representation per type the value exports, most preferred first; the plain-text
fallback is the value's own second type, not a parameter. A paste walks the destination's
`importedContentTypes()` in order, so the same destination takes the custom type and, when only text is
on the clipboard, the text import (pin: `theInputGuidePasteTakesTheCustomTypeThenTheTextFallback`). A
focused text field keeps its own copy and paste (pin: `aFocusedTextFieldKeepsItsOwnCopyCutPasteUnderACopyableAncestor`).
Code outside a view uses `window.clipboard`, which writes and reads the same representations (pin:
`theInputGuideTheWindowClipboardRoundTripsFromCode`). Copying more than one item writes the first
(divergence 456), and the Edit menu's Paste is enabled by the presence of a destination, not by what its
validator would accept (divergence 455). Pasting between applications is a human check.

```swift
/// A graph fragment: it copies as its own type and, after it, as plain text.
struct InputGraph: Transferable, Equatable {
    static let contentType = ContentType("com.example.graph", conformingTo: [.data])
    var nodes: Int

    func exportedContentTypes() -> [ContentType] { [InputGraph.contentType, .utf8PlainText] }
    static func importedContentTypes() -> [ContentType] { [InputGraph.contentType, .utf8PlainText] }

    func exported(as contentType: ContentType) -> Data? {
        if contentType == InputGraph.contentType { return Data("nodes:\(nodes)".utf8) }
        if contentType == .utf8PlainText { return Data("graph with \(nodes) nodes".utf8) }
        return nil
    }

    init(nodes: Int) { self.nodes = nodes }

    init?(importing data: Data, contentType: ContentType) {
        let text = String(decoding: data, as: UTF8.self)
        if contentType == InputGraph.contentType {
            guard text.hasPrefix("nodes:"), let count = Int(text.dropFirst(6)) else { return nil }
            nodes = count
        } else if contentType == .utf8PlainText {
            nodes = text.count
        } else {
            return nil
        }
    }
}

/// What the destination received, in order.
@MainActor
final class InputClipboardModel {
    var graph = InputGraph(nodes: 3)
    var pasted: [InputGraph] = []
}

/// A focusable source that copies and a focusable destination that pastes.
@MainActor
func inputClipboardRoot(_ model: InputClipboardModel) -> some Element {
    VStack(alignment: .leading) {
        Box().frame(width: Pixels(120), height: Pixels(40)).background(.surface)
            .accessibilityIdentifier("source")
            .focusable()
            .copyable([model.graph])
        Box().frame(width: Pixels(120), height: Pixels(40)).background(.surface)
            .accessibilityIdentifier("destination")
            .focusable()
            .pasteDestination(for: InputGraph.self) { model.pasted += $0 }
    }
}

/// Code outside a view writes and reads through the window's clipboard.
@MainActor
func inputCopyFromCode(_ window: Window, _ graph: InputGraph) -> InputGraph? {
    window.clipboard.write(graph)
    return window.clipboard.read(InputGraph.self)
}
```

## How do I make a view follow a drag and snap back?

Declare the offset as `@GestureState` and write it with `updating(_:body:)` on the gesture
(SwiftUI's spelling, on `DragGesture`, `LongPressGesture`, `MagnifyGesture` and `RotateGesture`;
on a tap it compiles and never runs). It is a `@State` slot that only a gesture writes: each
update starts from the value committed before the event, and the state returns to its initial
value once when the gesture ends, fails or is cancelled, before `onEnded` runs (pin:
`theInputGuideAGestureStateSnapsBackAtTheRelease`). A `resetTransaction` animates the return,
as the chip below eases home over a quarter second (pin:
`theInputGuideTheResetTransactionAnimatesTheReturn`). Two simultaneous gestures that write one
state in one event resolve in declaration order, where SwiftUI's differ (divergence 645).

```swift
/// A chip that follows a drag and eases home: its offset is `@GestureState`.
struct InputSnapBackChip: Component {
    @GestureState(wrappedValue: Size(width: Pixels(0), height: Pixels(0)),
                  resetTransaction: Transaction(animation: .easeOut(duration: 0.25))) var drag: Size<Pixels>

    var content: some ElementGroup {
        Rectangle().frame(width: Pixels(60), height: Pixels(40))
            .offset(drag)
            .accessibilityIdentifier("snap-chip")
            .gesture(DragGesture(minimumDistance: 0).updating($drag) { value, state, _ in state = value.translation })
    }
}
```

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
- divergence 645: two simultaneous gestures writing one `GestureState` resolve in declaration order.
- divergence 277: an `.opacity(0)` window-drag handle still captures.
- divergence 465: an image cursor's hot spot clamps onto the image.
- divergence 325: a composing field's accessibility value is the committed text.
- divergence 326: a selection written while composing waits for the commit.

Back to [layout](layout.md) and [state and identity](state-and-identity.md).
- divergence 455: the Edit menu's Paste is enabled by the destination, not by its validator.
- divergence 456: a copy writes, and a paste receives, one item.
