# How do I show a popover, a menu, an alert or a toolbar, and manage the window?

Presentations and the app shell are where a MetalUI app meets the platform. SwiftUI's modifiers
are the vocabulary (`.popover`, `.contextMenu`, `.alert`, `.fileImporter`, `.toolbar`,
`.navigationTitle`); the difference is who draws them. AppKit shows a native menu, alert, sheet and
toolbar; SDL (Linux and Windows) declines some, and the window then draws its own. This guide
covers the tasks and the divergences you will hit. The reference is
[`api-overview.md`](../api-overview.md#menus-popovers-and-tooltips--a--d--m), and the blocks below
are compiled and driven through a headless window, which reads and answers each presentation at the
platform seam ([`testing.md`](../testing.md); [`README.md`](README.md#how-the-code-blocks-are-checked)).

## How do I show a popover?

`.popover(isPresented:)` anchors a view to the element that declares it. It opens on the side of
`arrowEdge` (default `.top`), is flipped, then clamped inside the window, and has no arrow
(divergences 111, 112). A popover is placed against the last frame's bounds, so it appears one
frame after the press that opened it (pin: `aPopoverAppearsInTheTreeInsideTheWindow`). Nothing but
a modifier may follow a legacy `.popover` on the old vocabulary (divergence 115); on the
SwiftUI vocabulary it composes like any modifier.

```swift
import MetalUI

/// A button whose popover opens beside it.
struct ShellPopoverDemo: Component {
    @State var shown = false

    var content: some ElementGroup {
        Button("Info") { shown.toggle() }
            .popover(isPresented: $shown) {
                Text("Details").frame(width: Pixels(120), height: Pixels(40))
            }
    }
}

@MainActor
func shellPopoverRoot() -> some Element {
    VStack { ShellPopoverDemo() }
}
```

A test presses the button, draws the next frame and finds one popover node (pin:
`theShellGuideAPopoverOpensFromItsButton`). An outside press or Escape writes the binding back to
`false` from input, and the outside press then reaches whatever it lands on (pin:
`aProposalPathPopoverPresentsPlacesAndDismisses`). To place a panel at a point rather than at an
element, use `anchoredOverlay` ([`api-overview.md`](../api-overview.md)).

## How do I ask the user to confirm, or to choose a file?

`.alert` and `.confirmationDialog` take SwiftUI's shapes: a title, an `isPresented` binding and
buttons, with `role: .destructive` and `role: .cancel`. Any button writes `isPresented = false`
first, then runs its action. An `NSAlert` sheet on AppKit; where the platform declines (SDL) the
window draws the alert itself and holds it modal. Both are read and answered by the headless
harness (pins: `anAlertIsReadAndAnsweredByButtonTitle`, `aDeclinedAlertIsDrawnAndPressedThroughTheTree`).

```swift
/// A destructive action behind a confirmation.
struct ShellDeleteConfirmation: Component {
    @State var asking = false
    @State var deleted = 0

    var content: some ElementGroup {
        Button("Remove") { asking = true }
            .alert("Delete the file?", isPresented: $asking) {
                Button("Delete", role: .destructive) { deleted += 1 }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        Text("Deleted \(deleted)")
    }
}

@MainActor
func shellDeleteRoot() -> some Element {
    VStack { ShellDeleteConfirmation() }
}
```

The test answers the native alert by its button's title and, in a second window that declines
alerts, presses the drawn one through the tree (pins: `theShellGuideAnAlertsButtonRunsItsActionAndClosesIt`,
`theShellGuideADrawnAlertIsPressedThroughTheTree`).

`.fileImporter` and `.fileExporter` work the same way: a binding, a list of `ContentType`s and a
completion. A dialog is presented after the frame in which the binding turned `true`, one per
window at a time; a cancelled import calls nothing (pin: `aCancelledFileDialogReachesTheHandler`). Off Apple a type filters by file extension
only (divergence 129; see [cross-platform](cross-platform.md)).

```swift
/// The path a file dialog chose, logged.
@MainActor
final class ShellLog {
    var entries: [String] = []
}

/// A button that asks for one JSON file.
struct ShellImporter: Component {
    @State var asking = false
    let log: ShellLog

    var content: some ElementGroup {
        Button("Import") { asking = true }
            .fileImporter(isPresented: $asking, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { log.entries.append("chose \(url.path)") }
            }
    }
}

@MainActor
func shellImportRoot(_ log: ShellLog) -> some Element {
    VStack { ShellImporter(log: log) }
}
```

The harness answers the dialog with a path (pin: `theShellGuideAnImporterHearsTheChosenFile`).

## How do I add a context menu and menu-bar commands?

`.contextMenu { }` takes `Button` (with `.keyboardShortcut`), `Toggle`, `Menu` and `Divider`, and
is evaluated at each open. A right press opens it and **nothing else**: a secondary click never
presses a `Button` or fires a tap, which SwiftUI's does (divergence 110). The platform shows a
native `NSMenu` on AppKit and the window draws its own menu where it declines.

`App.commands { CommandMenu("…") { } }` fills the menu bar. Every AppKit app gets the standard
main menu; off Apple there is none, so **every window draws the bar** as a 25-point strip above
the toolbar strip, and its titles open on a click (divergence 195). Shortcuts take the same path as
a `Button`'s, and their default modifier is `.primary` (see [cross-platform](cross-platform.md)).

```swift
/// A command menu: the title opens on a click off Apple, in the system bar on Apple.
@MainActor
func shellInstallCommands(_ app: App, log: ShellLog) {
    app.commands {
        CommandMenu("Tools") {
            Button("Run") { log.entries.append("run") }.keyboardShortcut("r")
        }
    }
}

/// A target with a one-item context menu.
@MainActor
func shellContextMenuRoot(_ log: ShellLog) -> some Element {
    VStack {
        Button("Target") {}
            .contextMenu {
                Button("Copy") { log.entries.append("copy") }
            }
    }
}
```

A test right-clicks the target and chooses the item by title, and lists and performs the command
by path (pins: `theShellGuideAContextMenuItemRuns`, `theShellGuideACommandRunsFromTheMenuBar`,
`aContextMenuIsReadAndAnItemChosenByTitle`, `theMenuBarListsCommandsAndPerformsOne`; the drawn bar:
`aMenuBarThePlatformDeclinesIsDrawnAndDrivenThroughTheTree`).

## How do I title the window and add a toolbar?

`.navigationTitle("…")` anywhere in the tree sets the window title in the first presented frame;
the inner one beats an enclosing one (pin: `theTreeTitleWinsInnerBeatsOuterFirstSiblingBeatsSecond`).
`.toolbar { ToolbarItem(id:) { } }` takes a **closed set** of items: a `Button` with a `Text` or
`Image` label, `Toggle`, `Picker`, `TextField` and `Text`, not any view (divergence 135). Write it
inside the root's first container: `.toolbar` returns a transparent scope, not an `Element`.
AppKit shows a real `NSToolbar`; off Apple the window draws a 39-point strip and lays the root out
below it (divergence 136).

```swift
/// A titled root with one toolbar button.
@MainActor
func shellToolbarRoot(_ log: ShellLog) -> some Element {
    VStack {
        Text("Notes")
            .frame(width: Pixels(100), height: Pixels(50))
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(id: "add") { Button("Add") { log.entries.append("add") } }
            }
    }
}
```

The harness reads the title and triggers the toolbar item by id (pins:
`theShellGuideATreeTitlesTheWindowAndAToolbarItemRuns`, `theToolbarIsReadAndAnItemTriggered`; the
drawn strip: `aDeclinedToolbarIsDrawnAndItsButtonClickable`).
`windowStyle: .hiddenTitleBar` lays the root under the bar, unlike SwiftUI (divergence 175);
read `@Environment(\.titleBarInsets)` for what to pad by.

## How do I stop a close, or a quit?

`Window.onCloseRequest` answers `.now`, `.cancel` or `.later`; the close button, ⌘W and the
platform's close request all ask it, and `Window.close()` never does. SwiftUI has no veto, so
this is MetalUI's own. Return `.later` to show an alert from the handler and reply with
`Window.replyToCloseRequest(_:)`. A vetoed window stays open and keeps drawing (pin:
`aVetoedCloseRequestKeepsTheWindowOpen`) and runs no `onDisappear`
(pin: `aCancelledCloseRequestKeepsTheWindowAndRunsNoOnDisappear`).

```swift
/// A document whose window refuses to close while it has unsaved changes.
@MainActor
final class ShellDocument {
    var hasUnsavedChanges = false
}

@MainActor
func shellGuardClose(_ window: Window, document: ShellDocument) {
    window.onCloseRequest = { document.hasUnsavedChanges ? .cancel : .now }
}
```

A test makes the document dirty and asks to close, then cleans it (pin:
`theShellGuideADirtyDocumentVetoesTheCloseAndACleanOneDoesNot`).

A quit asks `App.onTerminateRequest`; with none set it asks each window's handler in turn, so a
one-window app sets only the window's. Closing one of two windows no longer ends the app (pin:
`closingOneOfTwoWindowsDoesNotTerminate`), and a deferred quit ends only on the reply (pin:
`aDeferredTerminateEndsOnlyOnTheReply`). An open-document event goes to the key window with an
`.onOpenURL` handler, never to a new window (divergence 176; the recipe is in
[`packaging.md`](../packaging.md)).

## How do I colour a popover's panel?

`.presentationBackground(_:)` inside a popover's content fills the popover's panel with a colour, a colour
token, a `Material`, a gradient, or content of your own through `presentationBackground(alignment:content:)`.
Only `.popover` reads it, and the innermost report wins. Written on the declarer or elsewhere in the main
tree it does nothing, and `anchoredOverlay`, the drawn alert and the drawn menu have no panel to fill
(the rulings are `BG-A` to `BG-F`).

```swift
/// A button whose popover panel is filled red.
struct ShellTintedPopover: Component {
    @State var shown = false

    var content: some ElementGroup {
        Button("Tint") { shown.toggle() }
            .popover(isPresented: $shown) {
                Text("Details")
                    .frame(width: Pixels(120), height: Pixels(40))
                    .presentationBackground(Color.red)
            }
    }
}

@MainActor
func shellTintedPopoverRoot() -> some Element {
    VStack { ShellTintedPopover() }
}
```

A test opens the popover and finds a red rect in the scene that the closed window does not have (pin:
`theShellGuideAPresentationBackgroundFillsThePopoverPanel`).

## Divergences you will hit

Each row is in [`divergences.md`](../divergences.md); the list is checked against it.

- divergence 110: a right click presses nothing and fires no tap; it opens the context menu only.
- divergence 111: a popover stays inside the window, flipped and clamped.
- divergence 112: a popover has no arrow.
- divergence 115: on the legacy vocabulary, a modifier cannot follow `.popover`.
- divergence 126: `.windowResizability(.automatic)` asks the content nothing.
- divergence 129: off Apple a file dialog filters by filename extension only.
- divergence 135: a toolbar item is one of a closed set.
- divergence 136: where the platform has no toolbar the window draws a strip.
- divergence 175: a hidden title bar lays the content under the bar.
- divergence 176: an open-document event never opens a window.
- divergence 195: where the platform has no menu bar every window draws one.

Next: [drawing and GPU](drawing-and-gpu.md), [cross-platform](cross-platform.md), and
[`api-overview.md`](../api-overview.md) for every declaration.
