# Testing a MetalUI app's interface

`MetalUITesting` is MetalUI's headless test harness (rulings `HT-A`…,
[`superpowers/2026-10-09-test-harness-decisions.md`](superpowers/2026-10-09-test-harness-decisions.md)):
a test opens the app's real root element in a real `Window` over a headless
platform, clicks and types into it, reads its laid-out frames and its
accessibility tree, answers its alerts and menus, and counts the work each
frame does. No screen, no real window, no GPU: it runs in CI on macOS, Linux
and Windows, from swift-testing or XCTest. Its shape is gpui's
`TestAppContext`/`VisualTestContext`; its vocabulary is XCUITest's
(`click`, `typeText`, `element(label:)`). SwiftUI has no in-process
equivalent — it tests UI out of process — so the harness is MetalUI-only.

```swift
import Testing
import MetalUI
import MetalUITesting
@testable import MyApp

@MainActor @Test func pressingTheButtonCountsIt() throws {
    let window = try TestWindow(size: Size(width: Pixels(640), height: Pixels(400))) { rootView() }
    try window.click(window.element(label: "Press me"))
    #expect(try window.element(label: "pressed 1 times").role == .staticText)
}
```

`metalui new` generates exactly this test ([`getting-started.md`](getting-started.md)).

## Setting it up

Add a test target that depends on the app's target and the
`MetalUITesting` product; `swift test` runs it.

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: [
        "MyApp",
        .product(name: "MetalUITesting", package: "MetalUI"),
    ]
),
```

An executable target is imported `@testable` (SwiftPM renames its entry
point); keep the root element in a function the test can call
(`rootView()`), not inside `main.swift`'s top-level code.

**Text.** On macOS a window's text goes through CoreText unless you pass
another engine. On Linux and Windows there is no default:
`TestWindow(…)`/`TestApp()` throw `TestHarnessError.textSystemRequired`
without one, so pass the portable text system — over the installed fonts as
an app does, or over a font file of your own for literals that agree on every
platform:

```swift
#if os(Linux) || os(Windows)
let resolver = try SystemFonts.resolver()      // MetalUISystemFonts
let window = try TestWindow(textSystem: { PortableTextSystem(resolver: resolver) }) { rootView() }
#else
let window = try TestWindow { rootView() }
#endif
```

A cross-platform test target lists `MetalUIPortableText` and
`MetalUISystemFonts` **unconditionally**, as the generated one does (`SG-D`:
with a platform condition SwiftPM drops their C modules from a test target on
macOS); `MetalUISDL` keeps its Linux/Windows condition.

Every harness API is `@MainActor`; mark the test (or its suite) so.

## The app and its windows

`TestWindow(size:colorScheme:scaleFactor:options:recordsLayout:textSystem:content:)`
opens one window in an app of its own. For commands, the menu bar, several
windows or the app shell, make the app first:

```swift
let testApp = try TestApp()
testApp.app.commands { CommandMenu("Edit") { Button("Clear") { model.clear() } } }
let window = try testApp.openWindow(title: "Main") { rootView() }
```

`TestApp.app` is the real `App` and `TestWindow.window` the real `Window`:
set `keymap`, `environment`, `onCloseRequest`, themes or the icon on them as
the app does. Opening draws the first frame, so an `onAppear` write is
already in it. `colorScheme:` is the system appearance the window opens in
(a `.dark` window's first frame is dark); `scaleFactor:` the backing scale.

`HeadlessPlatformWindow.Options` holds the platform's answers, each defaulting
to AppKit's: menus, alerts and file dialogs present natively, the toolbar is
native, an accessibility client is active from the start. Turn
`presentsMenusNatively`/`presentsAlertsNatively`/`showsToolbarNatively` off to
test the window's own drawn menu, alert panel and toolbar strip, as on SDL.
`performsWindowDrag` (default `true`, AppKit's answer during a drag) is what the window's
`performWindowDrag()` answers; `TestWindow.windowDrags` counts the requests a
`WindowDragGesture` made (`WD-E`).

## Input

Every action delivers its events at the window's clock and **then draws one
frame** — the frame a display link would draw next — so the next line of the
test sees its effect.

- By point (window points): `click(at:)`, `doubleClick(at:)`,
  `rightClick(at:)`, `otherClick(at:button:)`, `hover(at:)`, `exitPointer()`,
  `scroll(at:byDeltaX:deltaY:)`, `drag(from:to:steps:)`,
  `click(at:forDuration:thenDragTo:)`, `magnify(at:by:)`, `rotate(at:byDegrees:)`,
  `drop(_:at:)`. A click moves the pointer there first, so hover sees it.
- By element (a `TestElement` from a query, aimed at its visible frame's
  centre; `TestHarnessError.notHittable` when nothing of it is visible):
  `click(_:)`, `doubleClick(_:)`, `rightClick(_:)`, `hover(_:)`,
  `scroll(_:byDeltaX:deltaY:)`, `click(_:forDuration:thenDragTo:)`,
  `typeText(_:into:)`.
- Keys: `typeText(_:)` (routed as AppKit routes it: into the focused text
  field as text input, otherwise as key presses, so a plain-letter `Keymap`
  binding is silent while a field is focused), `typeKey(_:modifierFlags:)`,
  `pressModifiers(_:)`. The editing shortcuts are ⌘ on macOS and ⌃ elsewhere.
- Raw: `send(_ event: InputEvent)` delivers one event and draws nothing.

### Recipe: typing into a canvas app's field

A text field that commits on the shortcut-modified Return, submits on a plain
Return, handles Escape, and loses focus to a click on the canvas around it
(a `.hoverKeyRegion()`, `KF-E`). `.primary` is the platform's shortcut
modifier (⌘ on macOS, Ctrl elsewhere), so the same chord works on every
platform; `typeText` reaches the field as text input, and `onKeyPress` runs
before the field's own editing keys, so the handler decides the chord and a
plain Return falls through (`.ignored`) to `onSubmit`. **This exact code is
`Tests/MetalUITestingTests/TestingRecipeTests.swift`, run on every platform, so
it cannot rot; change both together.** (`harnessWindow` is the test target's helper over
`TestWindow(size:textSystem:content:)`, as in "Setting it up".)

```swift
@Observable @MainActor final class RecipeModel {
    var text = ""
    var committed: [String] = []
    var log: [String] = []
}

@Test @MainActor func typingIntoAFieldCommitsOnTheShortcutReturnAndAClickInAKeyRegionResignsFocus() throws {
    let model = RecipeModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            TextField("Name", text: model.text) { model.text = $0 }
                .onSubmit { model.log.append("submit") }
                .frame(width: Pixels(200), height: Pixels(24))
                .accessibilityIdentifier("name")
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.contains(.primary) else { return .ignored }
                    model.committed.append(model.text)
                    return .handled
                }
                .onKeyPress(keys: [.escape]) { _ in
                    model.log.append("escape")
                    return .handled
                }
            Box().frame(width: Pixels(100), height: Pixels(100)).background(.surface)
                .hoverKeyRegion()
                .id("canvas")
        }
    }

    // Focus the field: a click focuses a TextField.
    let field = try window.element(identifier: "name")
    try window.click(field)
    #expect(try window.focusedElement?.identifier == "name")

    // Text arrives as text input; the shortcut-modified Return commits.
    window.typeText("Ada")
    #expect(model.text == "Ada")
    window.typeKey(.return, modifierFlags: .primary)
    #expect(model.committed == ["Ada"], "the chord reached onKeyPress")
    #expect(model.log.isEmpty, "and did not submit the field")

    // Plain Return is declined by the handler and submits; Escape is claimed.
    window.typeKey(.return)
    window.typeKey(.escape)
    #expect(model.log == ["submit", "escape"])
    #expect(model.committed == ["Ada"], "a plain Return commits nothing")

    // A click inside the key region outside the field clears focus.
    let canvas = try window.frame(ofID: "canvas")
    window.click(at: Point(x: canvas.origin.x + Pixels(50), y: canvas.origin.y + Pixels(50)))
    #expect(try window.focusedElement == nil)
    #expect(model.text == "Ada", "the committed text is untouched")
}
```

## Queries

**The accessibility tree** is XCUITest's model: `element(identifier:)`,
`element(label:)`, `elements(role:)`, `elements(where:)`, `focusedElement`,
and `accessibilityTree` itself. A query walks the tree in pre-order and throws
`TestHarnessError.noElement` for no match and `.ambiguous` for more than one.
A `Text` matches `element(label:)` by its string. Give an element
`.accessibilityIdentifier(_:)` to find it without depending on its words.
`performAccessibilityAction(_:on:)` and `focus(_:)` act as an assistive
client does.

**Laid-out frames** are gpui's `debug_bounds`: `frame(ofID: "name")` reads
the rect an element named with `.id("name")` was laid out at, in window
points, **before** any scroll offset or render effect (the visible rect is the
accessibility element's `visibleFrame`); `frames(ofID:)` lists every element
of that name. **Adding `.id` changes identity** — it is the outermost
modifier and names a new element, resetting its `@State` — so name what the
test reads, not everything. A window opened with `recordsLayout: false` (a
benchmark's) throws `.notRecorded`.

`scene` is the last presented frame's scene, in device pixels, for a test
that reads draw rects.

## Alerts, dialogs, menus and the toolbar

What the window asked the platform to present is read at the seam and
answered as the platform would:

- `presentedAlert` then `respondToAlert(button:)` or `respondToAlert(buttonAt:)`;
- `presentedFileDialog` then `respondToFileDialog(choosing:)` or
  `cancelFileDialog()`;
- `presentedMenu` (a context menu, a menu picker) then
  `chooseMenuItem("More", "A")` or `dismissMenu()`;
- `toolbar` then `performToolbarItem(_:action:)`;
- `pointerStyle`, `title`, and `platformWindow`'s records for the rest
  (pointer styles, size limits, edited marker, preferred scheme, drags).

Each getter answers the latest unanswered request, or `nil` when the window
draws it itself (the option off): then drive the drawn panel through the
accessibility tree like any other content. A popover is in the tree one tick
after the frame that opens it.

**The menu bar**: `testApp.menuBar` reads `App.commands` as the platform
receives it, and `testApp.performMenuBarItem("Edit", "Clear")` runs an item
and draws every window. A standard item (Quit, Copy) is the platform's and is
not performed. **A menu's content alone**: `MenuEvaluation { … }` evaluates a
`@MenuContentBuilder` closure without a window — `items`, `item(_:)`,
`perform(_:)`.

## The clock and `runUntilIdle`

Nothing reads a wall clock and no test sleeps. The window's clock (`now`)
starts at 0 and moves only by `advance(by:)` (one tick there: a long press
matures, an animation advances) and `advanceFrames(_:)` (ticks 1/60 s apart);
`tick()` fires one display-link tick without moving it. A model written
outside input — from a test, a timer, a `Task` — reaches the window through
observation; call `window.window.setNeedsRedraw()` then `tick()` to draw its
frame on every platform (the observation hop is asynchronous off macOS).

`try await runUntilIdle()` lets main-actor work run — a `.task`'s
continuation, an observation hop — drawing whenever the window is dirty,
**without moving the clock**, and throws `.notIdle` after 64 rounds of a
window that never settles (a phase-time write). A task awaiting real time
(`Task.sleep`) does not finish there: inject a clock into the model.

`resize(to:)`, `setScaleFactor(_:)`, `setAppearance(_:)`,
`setControlActiveState(_:)`, `setReduceMotion(_:)`, `close()` and
`requestClose()` simulate what the system does to a window;
`testApp.platform.simulateTerminateRequest()` and
`simulateOpenURLs(_:)` what it does to the app.

## Warm frames and benchmarks

A `TestWindow` is one `Window` for its life, so every frame after the first is
**warm**: state, shaping, rasters and textures persist, as in the app.
`lastFrameWork` counts what the last frame did — builds, layout measure calls,
cache hits and misses, rasterized and blurred pixels, atlas uploads, new
textures, rects, glyphs and images — and `frameWork` keeps the history until
`resetFrameWork()`. A performance test **counts work, never time**: open the
window with `recordsLayout: false` (so it does only production work), drive
the interaction, and assert the counters — for example that a drag frame
re-measures only what moved, or that a second unchanged frame uploads nothing.

```swift
let window = try TestWindow(recordsLayout: false) { Inspector(model: model) }
window.drag(from: start, to: end, steps: 8)
#expect(window.lastFrameWork.layoutCacheMisses <= 6)
#expect(window.lastFrameWork.rasterizedPixels == 0)
```

## Measuring text

`@Environment(\.textMeasurer)` answers the size a `Text` would lay out at, in
a `Component`, with no layout (rulings `GT-B`…`GT-D`). A test measures in a
component body, stores the answer in a plain class, and asserts it against the
laid-out frame (within one point: frames are rounded to whole points):

```swift
@MainActor final class Measured { var size = Size<Pixels>(width: 0, height: 0) }
struct Probe: Component {
    let measured: Measured
    @Environment(\.textMeasurer) var measurer
    var content: some ElementGroup {
        let _ = measured.size = measurer.resolve(Text("12.5 mm"))
            .measure(in: Size(width: .infinity, height: .infinity))
        Box().frame(width: 1, height: 1)
    }
}
let window = try TestWindow { VStack(spacing: 0) { Probe(measured: m); Text("12.5 mm").id("t") } }
let laid = try window.frame(ofID: "t")
#expect(abs(m.size.width.value - laid.size.width.value) < 1)
```

Measuring adds no layout measure call and no build to a frame (test 1.4 counts
it), so it is safe in a per-frame body.

## What it cannot do

Each is a ruled deferral (`HT-Q`):

- **Pixels.** There is no CPU renderer; a test reads scene rects, frames and
  the accessibility tree, not an image (`HT-L`).
- **`GPUSurface`/`MetalView` draws** are recorded, not run: there is no GPU
  context to hand the closure.
- **Shaping counters** are not in `FrameWork` (the cache is CoreText's).
- **Virtual time inside `.task`**: Swift's clocks are not the harness's;
  inject one.
- **An IME composition helper**: `send(.textComposition(…))` works.
- **Key-window switching** between several windows:
  `setControlActiveState(_:)` per window covers what an element observes.
- **An in-window menu bar** (SDL draws none); `menuBar` reads the seam
  regardless.

## Replacing an app's own platform fake

An app that wrote its own headless `Platform`/`PlatformWindow` for tests can
use `HeadlessPlatform`, `HeadlessPlatformWindow` and `HeadlessWindowRenderer`
instead: they implement every requirement honestly (recording each request,
answering as AppKit does by default), and MetalUI adds each new platform
requirement to them in the change that introduces it
([`migration.md`](migration.md)).
