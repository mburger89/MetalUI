# App shell — design

Item C8 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**): window-close veto and app-terminate hook, window title and edited
marker, hidden title bar with full-size content, open-document events.
Requested by MetalCreator (gaps M6-a…M6-d, `MetalCreator/docs/metalui-gaps.md`
on master). Branch `feat/app-shell` from `c62d6ba`. Rulings:
[`../2026-10-08-app-shell-decisions.md`](../2026-10-08-app-shell-decisions.md)
(`AS-A`…`AS-I`; **its "Final spellings" table is what MetalCreator swaps its
stopgaps by**). Record: `docs/record/87-app-shell.md`. Divergence labels from
this branch's reserved range **175–184** (175 and 176 used here; the header's
next-label line is left for the merge).

**Status: designed (2026-10-09).** Lanes 1–3 not started.

## §0 Baseline (`c62d6ba`)

- `swift test --build-system native --no-parallel`: **2873 tests in 3
  suites**, `FR-J no-argument frame: succeeded=` present (lanes re-take it
  before their first change and record it).
- What exists (inventory, decisions doc "Evidence"): `PlatformWindow.title`
  is settable but `Window` exposes none; `App.openWindow` wires
  `platformWindow.onClose` → `runDisappearancesForClose()` and, on AppKit,
  `NSApplication.shared.terminate(nil)` on **every** close; `App.windows`
  never shrinks; no `NSApplicationDelegate`; `AppKitWindow` implements only
  `windowWillClose`; SDL answers `MUI_EVENT_QUIT` with `stop()` and closes a
  window on `MUI_EVENT_CLOSE` at once; a drop with window id 0 reaches nobody.
- Parallel branches: `feat/controls-looks` (record §85; `Window.swift` slider
  edits, `Decoration`, shaders) and `feat/key-focus` (record §88). This item
  keeps its `Window.swift`, `Frame.swift` and `EnvironmentScope.swift` edits to
  a few named lines (§2) and puts its logic in new files, so the merges are
  additive.

## §1 API

### §1.1 The seam (`MetalUIPlatform`; lane 1; `AS-H`)

New file `Sources/MetalUIPlatform/AppShell.swift`:

```swift
/// A close or termination request's answer (rulings AS-B, AS-C).
public enum CloseRequestReply: Sendable, Equatable { case now, cancel, later }
/// A platform window's title-bar style (ruling AS-E).
public enum PlatformTitleBarStyle: Sendable, Equatable { case standard, hidden }
```

`PlatformWindow` (six, no defaults):

```swift
var onCloseRequest: (() -> Bool)? { get set }          // nil or true: close
func close()                                            // no asking; onClose once
func setDocumentEdited(_ edited: Bool)
func setRepresentedFilePath(_ path: String?)
func setTitleBarStyle(_ style: PlatformTitleBarStyle) -> Bool   // true: applied
var titleBarInsets: Edges<Pixels> { get }               // zero unless hidden and overlaid
```

`Platform` (four, no defaults):

```swift
var onTerminateRequest: (() -> CloseRequestReply)? { get set }  // nil answers .now
func replyToTerminateRequest(_ shouldTerminate: Bool)   // answers a request that got .later
func terminate()                                        // ends the loop, asking nobody
var onOpenURLs: (([String]) -> Void)? { get set }       // absolute URL strings; parked until set
```

**AppKit** (`Sources/MetalUIAppKit/AppKitPlatform.swift`, new
`Sources/MetalUIAppKit/AppKitApplicationDelegate.swift`):

- `AppKitWindow`: `windowShouldClose(_:)` → `onCloseRequest?() ?? true`;
  `close()` → `window.close()`; `setDocumentEdited` → `isDocumentEdited`;
  `setRepresentedFilePath` → `representedURL` (`nil` clears);
  `setTitleBarStyle(.hidden)` → insert `.fullSizeContentView`,
  `titlebarAppearsTransparent = true`, `titleVisibility = .hidden` (`H0`),
  `.standard` restores, answers `true`; `titleBarInsets` → hidden only: `top =
  frame.height − contentLayoutRect.height`, `left =` the zoom button's maxX in
  window coordinates, else zero; KVO on `contentLayoutRect` calls
  `syncSurfaceGeometry()` (→ `onResize`).
- `MetalHostView`: `mouseDownCanMoveWindow` → `false`; in `mouseDown(with:)`
  (the primary, non-control branch), when the window's style is hidden, the
  press is in the band (`y < titleBarInsets.top`) and `onInput` answered
  `false`, call `performWindowDrag(event)` (injectable; production
  `window.performDrag(with:)`); clickCount 2 there → `performTitleBarDoubleClick()`
  (injectable; reads `UserDefaults.standard.string(forKey:
  "AppleActionOnDoubleClick")`: `"Minimize"` → `miniaturize`, `"None"` →
  nothing, else `performZoom`) (`AS-F`).
- `AppKitApplicationDelegate: NSObject, NSApplicationDelegate`, owned by
  `AppKitPlatform`: `applicationShouldTerminate(_:)` → `.terminateNow` if
  `terminationApproved`, else maps `onTerminateRequest?() ?? .now`;
  `application(_:open:)` → `onOpenURLs` with `absoluteString`s, parked until
  the handler is set. `AppKitPlatform.installApplicationDelegate()` sets
  `NSApp.delegate` and is called by `run()` before `app.run()`.
  `replyToTerminateRequest(b)` → `terminateReplier(b)` (production
  `NSApp.reply(toApplicationShouldTerminate:)`); `terminate()` →
  `terminationApproved = true; terminator()` (production
  `NSApp.terminate(nil)`). Both closures injectable.

**SDL** (`Backends/SDL/Sources/SDLBridge/{SDLBridge.c,include/SDLBridge.h}`,
`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`):

- `mui_platform_init`: `SDL_SetHint(SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE, "0")`
  before `SDL_Init`. New `bool mui_window_hide(void *)`. `mui_push_event`
  learns `MUI_EVENT_QUIT` → `SDL_EVENT_QUIT` (tests push it). No new
  `MUI_EVENT_*` kind (existing kinds unrenumbered).
- `dispatch`: `MUI_EVENT_QUIT` → `switch onTerminateRequest?() ?? .now {
  .now: stop(); .cancel, .later: break }`, a pending flag kept for `.later`;
  `replyToTerminateRequest(true)` → `stop()` (false: forget); `terminate()` →
  `stop()`. `MUI_EVENT_CLOSE` → ask `window.onCloseRequest?() ?? true`;
  `true` → the existing removal + `window.close()`.
- `SDLWindow.close()` (now public, the requirement): if not closed — hide
  (`mui_window_hide`), ask the platform (weak back-reference or a closure set
  by `openSDLWindow`) to remove it, `closed = true`, `onClose?()` once. The
  platform's own CLOSE path calls the same body.
- Drops with `window_id == 0` (`DROP_FILE`, `DROP_COMPLETE`) are taken in
  `dispatch` before the window default: FILE strings collected, COMPLETE
  delivers `onOpenURLs(collected)` (a string with a scheme + `//` as is, else
  `SDLWindow.fileURLString(fromPath:)`); `DROP_TEXT`/`BEGIN`/`POSITION` with
  window 0 ignored. URLs before a handler are parked.
- `setDocumentEdited`, `setRepresentedFilePath`: recorded
  (`documentEditedCalls`, `representedPaths`), no SDL call;
  `setTitleBarStyle`: recorded (`titleBarStyles`), answers `false`;
  `titleBarInsets`: zero.

### §1.2 MetalUI (`Sources/MetalUI`; lane 2; `AS-B`…`AS-G`)

```swift
// Window (new file WindowShell.swift; stored state added to Window.swift as one
// `var shell = WindowShellState()` line plus the hooks in §2)
public var title: String { get set }
public var isDocumentEdited: Bool { get set }
public var representedURL: URL? { get set }
public var windowStyle: WindowStyle { get set }
public var onCloseRequest: (@MainActor () -> CloseRequestReply)?
public var isCloseRequestPending: Bool { get }
public func replyToCloseRequest(_ shouldClose: Bool)
public func close()
public func performClose()

// App (new file AppShell.swift; stored state as one `var shell = AppShellState()`)
public var onTerminateRequest: (@MainActor () -> CloseRequestReply)?
public func replyToTerminateRequest(_ shouldTerminate: Bool)
public func terminate()
public var onOpenURL: (@MainActor (URL) -> Void)?
public func open(_ urls: [URL])
public func openWindow<Root: Element>(title:size:minSize:maxSize:windowResizability:
    windowStyle: WindowStyle = .automatic, startsDisplayLink:content:) throws -> Window

public struct WindowStyle: Sendable, Equatable {
    public static let automatic, titleBar, hiddenTitleBar: WindowStyle
}

// EnvironmentValues
public internal(set) var titleBarInsets: Edges<Pixels>   // zero by default

// ElementGroup (EnvironmentScope, three new EnvironmentWrite cases)
public func navigationTitle<S: StringProtocol>(_ title: S) -> EnvironmentScope<Self>
public func navigationDocument(_ url: URL) -> EnvironmentScope<Self>
public func onOpenURL(perform action: @escaping @MainActor (URL) -> Void) -> EnvironmentScope<Self>
```

**Window state machine** (`AS-B`). `platformWindow.onCloseRequest = { [weak
self] in self?.answerCloseRequest() ?? true }`. `answerCloseRequest() ->
Bool`: closed → `false`; pending → `false` (handler not run); no handler →
`true`; `.now` → `true`; `.cancel` → `false`; `.later` → pending, `false`.
`replyToCloseRequest(b)`: not pending → nothing; pending cleared; `b` →
`close()`; the app's termination walk is told the outcome (an internal
`closeRequestResolved: ((Bool) -> Void)?`). `close()`: closed → nothing; else
`platformWindow.close()` (whose `onClose` marks `isClosed`, which makes
`drawFrameIfNeeded` return at once). `performClose()`: `if
answerCloseRequest() { close() }`.

**App termination** (`AS-C`). `platform.onTerminateRequest = { [weak self] in
self?.answerTerminateRequest(fromPlatform: true) ?? .now }`.
`answerTerminateRequest(fromPlatform:)`: `endingApproved` → `.now`; pending →
`.later`; app handler set → its answer (`.now` → `endEverything()`, `.later` →
pending); else the **walk**: windows in open order, each asked through
`answerCloseRequest` — `true` → `window.close()`, next; `false` and the window
now pending → the termination is pending on that window (`.later`); `false`
otherwise → `.cancel`; all closed → `endEverything()`, `.now`. A window's
later reply resumes the walk; when it completes or cancels after a `.later`,
the outcome goes to `platform.replyToTerminateRequest(_:)` if the platform
asked, or to `platform.terminate()` (on success) if `App.terminate()` asked.
`endEverything()`: `endingApproved = true`, close every remaining window
(each `onClose` → `runDisappearancesForClose()` once). `App.terminate()` =
`answerTerminateRequest(fromPlatform: false)`, and `.now` → `platform.terminate()`.
`onClose` (per window): `runDisappearancesForClose()`; drop from `windows`; if
`windows` is empty and not `endingApproved` → `endingApproved = true`,
`platform.terminate()` (the last close asks nobody). The
`#if canImport(AppKit) NSApplication.shared.terminate` and
`terminatesThroughAppKit` go.

**Title and document** (`AS-D`). After each build (where
`treeColorSchemePreference` is read back from the frame): effective title =
`frame.collectedNavigationTitle ?? title`, pushed to `platformWindow.title`
only when it differs from the last pushed; effective path =
`(frame.collectedNavigationDocument ?? representedURL)` if a file URL →
`.path`, pushed through `setRepresentedFilePath` on change.
`isDocumentEdited`'s `didSet` pushes on change. Frame: `EnvironmentScope`'s
`reportingPreference` gains arms — `.navigationTitle(s)` /
`.navigationDocument(u)` run the body, then set
`frame.collectedNavigationTitle`/`…Document` only if still `nil` (post-order,
first report wins: `N2`, `N5`).

**Style and insets** (`AS-E`). `windowStyle` `didSet` (and `openWindow`
before the first frame) → `platformWindow.setTitleBarStyle(style ==
.hiddenTitleBar ? .hidden : .standard)` on change; the answer is kept
(`titleBarStyleApplied`, internal, for tests). Each build stamps
`titleBarInsets = platformWindow.titleBarInsets` at the root, as
`displayScale` is stamped (`Frame.scopedValues` / the root values).

**Open URLs** (`AS-G`). `.onOpenURL`'s `reportingPreference` arm runs the body,
then appends `(owner: .child(of: parent, at: cursor, name: nil), action)` to
`frame.openURLHandlers` (post-order); `Window` keeps the last build's list.
`platform.onOpenURLs = { [weak self] in self?.open($0.compactMap(URL.init(string:))) }`.
`open(_:)`: per URL, the target window = the first in `windows` whose
`controlActiveState == .key` and whose list is non-empty, else the first with a
non-empty list; run its handlers **reversed** (reverse post-order), each
`StateDispatch.dispatching(to: owner) { action(url) }`, then
`setNeedsRedraw()`; no target → `onOpenURL?(url)`; else dropped.

### §1.3 Nothing else changes

No shader, renderer, `Handlers`, hitbox, focus, accessibility, animation or
`StateTable` change. No new `InputEvent` case (`AS-G` item 7). The standard
window style draws exactly as before.

## §2 Files

| Lane | Files (only these; new files **bold**) |
| --- | --- |
| 1 | **`Sources/MetalUIPlatform/AppShell.swift`**, `Sources/MetalUIPlatform/Platform.swift` (the ten requirements), `Sources/MetalUIAppKit/AppKitPlatform.swift`, **`Sources/MetalUIAppKit/AppKitApplicationDelegate.swift`**, `Backends/SDL/Sources/SDLBridge/SDLBridge.c`, `Backends/SDL/Sources/SDLBridge/include/SDLBridge.h`, `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`, `Tests/MetalUITests/Fakes.swift`, every `Tests/MetalUITests/*CompileGuards.swift` conformer template (`InputAPISeam`, `Transaction`, `Menu`, `Toolbar`, `ControlState`, `ColorScheme`, `PlatformServices`, `DragAndDrop` for `PlatformWindow`; `AppIcon`, `Commands` for `Platform`), `Backends/SDL/Tests/MetalUISDLTests/SDLLifecycleTests.swift` (`RecordingSDLPlatform` forwards the four), **`Tests/MetalUITests/AppShellSeamCompileGuards.swift`**, **`Tests/MetalUITests/AppKitAppShellTests.swift`**, **`Backends/SDL/Tests/MetalUISDLTests/SDLAppShellTests.swift`**, `docs/migration.md` (seam note), `docs/probes/closeout-inventory-map.tsv` + `closeout-public-api.tsv` (its declarations) |
| 2 | `Sources/MetalUI/App.swift` (the `onClose` wiring, the `openWindow` parameter, one stored `shell` line, the initialiser's two handler assignments), **`Sources/MetalUI/AppShell.swift`**, `Sources/MetalUI/Window.swift` (**only**: one stored `shell` line, the `onCloseRequest` installation beside the other `platformWindow.on…` assignments, the early return in `drawFrameIfNeeded` when closed, the post-build title/document/handler read-back beside the colour-scheme read-back), **`Sources/MetalUI/WindowShell.swift`**, `Sources/MetalUI/EnvironmentScope.swift` (three cases, three `reportingPreference` arms, three modifiers — or the modifiers in a **`Sources/MetalUI/WindowPreferences.swift`**), `Sources/MetalUI/Frame.swift` (the collected fields, the root stamp of `titleBarInsets`), `Sources/MetalUI/EnvironmentValues.swift` (`titleBarInsets`), **`Tests/MetalUITests/AppShellTests.swift`**, **`Tests/MetalUITests/WindowTitleTests.swift`**, **`Tests/MetalUITests/OpenURLTests.swift`**, **`Tests/MetalUITests/AppShellCompileGuards.swift`**, `Tests/MetalUITests/LifecycleTests.swift` (only if test 7.1's direct `fake.onClose?()` must become `fake.close()` — it need not: `onClose` stays the platform's notification), `docs/migration.md` (API notes), inventory map + census (its declarations) |
| 3 | **`Sources/MetalUIDemoContent/AppShellDemo.swift`**, `Sources/MetalUIDemo/main.swift` (the switch), `Backends/SDL/Sources/MetalUISDLDemo/main.swift` (the same switch), `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift` (one own-frame builder), **`Tests/MetalUITests/AppShellDemoTests.swift`**, **`Backends/SDL/Tests/MetalUISDLTests/SDLAppShellAppTests.swift`**, `docs/divergences.md` (175, 176 and the Not-offered rows), `docs/api-overview.md`, `docs/packaging.md` (document types, URL schemes, the launch-argument recipe), `docs/verification/human-checks.md` (group AS), inventory map + census re-recorded, the decisions doc's final-spellings table re-checked against the source, `docs/record/87-app-shell.md` and the Record phase's CLAUDE.md/AGENTS.md/README/record-index rows |

Every lane appends rulings to the decisions doc (moving its "next unused" line
in the same commit) and amendments to this spec.

## §3 Lanes (order 1 → 2 → 3; one agent at a time)

- **Lane 1 — seam and platforms.** §1.1. `Window`/`App` need no change to
  compile (they assign none of the new members yet); lane 1's suite count is
  the baseline plus its own tests. `swift package clean` after the stored
  properties land (public types crossing modules). Runs `Backends/SDL` and the
  Linux image (§5). Mutates each new guard red once.
- **Lane 2 — `App`, `Window`, the tree modifiers.** §1.2, headless over
  `FakePlatform`/`FakePlatformWindow`. Inventory rows + doc comments for every
  new public declaration. Pixel compare (the standard style must not move).
- **Lane 3 — demo, SDL `App`-level tests, registries, human checks, Record.**
  §6, §7, §8; the SDL `App` tests run in the Linux image ungated (offscreen
  renderers, `TF-C`); divergences; census; the Record phase.

## §4 Tests — by name, red before, and the mutation that must redden each

"Red before" is the state at the lane's start (a test of a declaration that
does not exist yet is red by not compiling, recorded as such). Each mutation
is applied once, committed first, restored from a copy, with the full
unfiltered suite; the lane names every test it reddened. A mutation that
reddens nothing is a finding.

### §4.1 Lane 1 — seam and platforms

| # | Test | Red before | Mutation that must redden it |
| --- | --- | --- | --- |
| 1.1 | `aPlatformWindowWithoutEachAppShellRequirementDoesNotCompile` (guard, `typecheckFile`, plain `import MetalUIPlatform`; a conformer with all six compiles — the migration note's spelling — and six arms each missing one fail naming it) | positive arm fails (members absent) | a protocol-extension default `func setRepresentedFilePath(_: String?) {}` → that arm compiles |
| 1.2 | `aPlatformWithoutEachAppShellRequirementDoesNotCompile` (guard; four arms) | positive arm fails | a default `func terminate() {}` → that arm compiles |
| 1.3 | `appKitWindowShouldCloseAsksOnCloseRequest`: real `AppKitWindow`; handler `false` → `performClose(nil)` leaves it visible, `onClose` not called; `true` → `onClose` once; `nil` → closes | no requirement | `windowShouldClose` answers `true` always → red |
| 1.4 | `appKitCloseClosesWithoutAskingAndFiresOnCloseOnce` (handler would refuse; `close()` closes, handler call count 0, `onClose` 1) | absent | `close()` calls `performClose(nil)` → red |
| 1.5 | `appKitDocumentEditedAndRepresentedPathReachTheNSWindow`: `isDocumentEdited` follows; `representedURL?.path == "/tmp/x.mcgraph"`; `nil` clears; `title` unchanged (`N3`) | absent | `setRepresentedFilePath(nil)` ignored → red |
| 1.6 | `appKitHiddenTitleBarSetsSwiftUIsFlagsAndReportsTheBand`: `.hidden` → `true`, `.fullSizeContentView`, transparent, title hidden (`H0`); `contentSize.height` grows by the band; `titleBarInsets.top == frame − contentLayoutRect` (> 0), `left ==` zoom button maxX; `.standard` restores all and zero insets | absent | omit `titlebarAppearsTransparent` → red; insets always zero → red |
| 1.7 | `appKitTitleBarBandChangeReportsAResize`: hidden, then `setToolbar(_:)` → `onResize` fired (KVO) and `titleBarInsets.top` larger | absent | drop the KVO → red |
| 1.7b | `anUnclaimedPressInTheHiddenBandDragsTheWindow`: injected `performWindowDrag`; real `NSEvent` mouse-down at band y 10 with `onInput` → `false` → called once; `onInput` → `true` → not; y below the band → not; standard style → not; clickCount 2 unclaimed → injected double-click action | absent | ignore `onInput`'s answer → red |
| 1.8 | `appKitApplicationDelegateMapsTheTerminateReply`: `.now/.cancel/.later` → `.terminateNow/.terminateCancel/.terminateLater`; `nil` → `.terminateNow`; `replyToTerminateRequest(true)` → injected replier got `true` | absent | `.later` → `.terminateCancel` → red |
| 1.9 | `appKitTerminateIsApprovedAndAsksNobody`: `terminate()` → injected terminator called; then `applicationShouldTerminate` → `.terminateNow` with the handler's call count 0 | absent | `terminate()` does not set the approval → red |
| 1.10 | `appKitOpenURLsReachOnOpenURLsAndParkUntilAHandler`: `application(_:open:)` with a file URL and `metalcreator://x` → `onOpenURLs` gets both `absoluteString`s in order; before the handler is set they park and arrive on assignment | absent | no parking → red |
| 1.11 | `runInstallsTheApplicationDelegate`: `installApplicationDelegate()` sets `NSApp.delegate` to the platform's object (the test restores the previous delegate) | absent | install nothing → red |
| 1.12 | `sdlACloseRequestAsksTheWindowAndAVetoKeepsItOpen` (hidden window; pushed `MUI_EVENT_CLOSE`): `false` → `openWindowCount` 1, `onClose` 0; `true` → closed, `onClose` 1 | closes at once | ignore the handler → red |
| 1.13 | `sdlAVetoedLastWindowCloseSendsNoQuit`: one hidden window, handler `false`, close pushed, pumped twice → `onTerminateRequest` call count 0 | QUIT arrives (hidden windows count none) | remove the hint → red |
| 1.14 | `sdlQuitAsksOnTerminateRequest`: pushed `MUI_EVENT_QUIT`; `.cancel` → `run(maxIterations: 3)` runs all three; `.now` → stops after one; `.later` → runs on until `replyToTerminateRequest(true)` | stops at once | QUIT calls `stop()` unconditionally → red |
| 1.15 | `sdlCloseHidesRemovesAndFiresOnCloseOnce`: `close()` → `onClose` 1, `openWindowCount` 0, a second `close()` runs nothing | absent | `close()` leaves the window in the platform → red |
| 1.16 | `sdlAFileDroppedOnTheAppIsAnOpenURL`: raw `DROP_FILE` window 0 `"/tmp/a b.mcgraph"` and `"metalcreator://doc/1"`, then `DROP_COMPLETE` window 0 → one `onOpenURLs(["file:///tmp/a%20b.mcgraph", "metalcreator://doc/1"])`; the same on a window id still reaches `.drop` (the existing DN tests stay green) | dropped | route window-0 drops to a window → red |
| 1.17 | `sdlDocumentEditedRepresentedPathAndTitleBarStyleAreRecordedNoOps`: recorded, `setTitleBarStyle(.hidden)` answers `false`, insets zero, `title` unchanged by `setDocumentEdited(true)` | absent | append `" *"` to the title on edited → red |
| 1.18 | `theFakesRecordTheAppShellCalls`: `FakePlatformWindow`/`FakePlatform` record and simulate (close request, terminate request, open URLs, scripted insets) | absent | the fake's `simulateCloseRequest` ignores `onCloseRequest` → red |

SDL tests convert every C enum `rawValue` explicitly; each helper creating an
`SDLPlatform` arms `armMainRunLoopExitCheck()`; none needs a presented frame.

### §4.2 Lane 2 — `App`, `Window`, tree modifiers (headless)

| # | Test | Red before | Mutation |
| --- | --- | --- | --- |
| 2.1 | `anOutsideModuleCanSpellTheAppShellAPI` (guard, plain `import MetalUI`): every §1.2 spelling incl. `openWindow(…, windowStyle: .hiddenTitleBar)`, `Text("x").navigationTitle("T").navigationDocument(url).onOpenURL { _ in }`, `HStack { … }.navigationTitle(name)` (proposal), `@Environment(\.titleBarInsets) var insets`; negatives: `values.titleBarInsets = …`, `.navigationTitle(Text("x"))`, `WindowStyle.plain`, `Box().navigationTitle("x").padding(4)` (`EV-B`) each fail | positive fails | make `titleBarInsets`' setter public → negative compiles |
| 2.2 | `aCloseRequestWithNoHandlerCloses` (`simulateCloseRequest()` → `true`) | no installation | — (control for 2.3) |
| 2.3 | `aCancelledCloseRequestKeepsTheWindowAndRunsNoOnDisappear` | absent | `answerCloseRequest` returns `true` for `.cancel` → red |
| 2.4 | `aDeferredCloseWaitsForTheReplyAndAsksOnlyOnce`: `.later` → `false`, pending; a second request runs no handler; `reply(false)` → open, next request asks again; `reply(true)` → `fake.closeCalls == 1`, `onDisappear` once | absent | re-run the handler while pending → red; `reply(true)` without `close()` → red |
| 2.5 | `theCloseHandlerPresentsTheDrawnAlertAndItsButtonClosesTheWindow` (M6-b end to end): tree `.alert("Save changes?", isPresented: $model.asking) { Button("Don't Save", role: .destructive) { window.replyToCloseRequest(true) }; Button("Cancel", role: .cancel) { window.replyToCloseRequest(false) } }`; fake `presentAlert` → `false` (drawn); handler sets `asking`, `.later`; tick → the drawn alert is up; a press on "Don't Save" → closed, `onDisappear` ran; second arm: fake presents natively and the `.alertResult` for "Cancel" keeps it open | absent | `replyToCloseRequest(true)` forgets the request without closing → red |
| 2.6 | `performCloseAsksAndCloseDoesNot` | absent | `close()` asks → red |
| 2.7 | `aClosedWindowDrawsNoMoreFrames`: after `close()`, `setNeedsRedraw()` + tick → no new `finishFrame` | draws | drop the early return → red |
| 2.8 | `closingOneOfTwoWindowsDoesNotTerminate`: `FakePlatform.terminateCalls` 0 after the first close, 1 after the second; `app.windows` shrinks | terminates per close | terminate on every close → red |
| 2.9 | `aQuitWithNoHandlersClosesEveryWindowThenEnds`: `simulateTerminateRequest()` → `.now`; both windows closed, each `onDisappear` once; no `platform.terminate()` from the last close (`terminateCalls` 0: the platform ends itself on `.now`) | absent | skip `endEverything()`'s closes → red |
| 2.10 | `theAppHandlerAloneDecides`: `.cancel` → reply `.cancel`, window handlers' counts 0, nothing closed | absent | ask windows too → red |
| 2.11 | `aDeferredTerminateEndsOnlyOnTheReply`: `.later`; `reply(false)` → `platform.replies == [false]`, nothing closed; again `.later`, `reply(true)` → windows closed, `replies == [false, true]` | absent | `reply(true)` calls `terminate()` instead of replying → red |
| 2.12 | `withoutAnAppHandlerQuitAsksEachWindowInTurn`: A `.now`, B `.later` → `.later`; A closed, B open; `B.replyToCloseRequest(true)` → B closed, `replies == [true]`; variant `false` → `replies == [false]`, app runs on | absent | ask only the first window → red; ask B before A closes → red (order log) |
| 2.13 | `appTerminateAsksThenEndsThroughThePlatform`: `app.terminate()` with no handlers → windows closed, `terminateCalls == 1`, `replies == []` | absent | reply instead of terminate → red |
| 2.14 | `theLastWindowsCloseEndsTheAppWithoutAsking`: app handler counts; the last window's close → `terminateCalls == 1`, handler count 0 | asks / no terminate | route the last close through `answerTerminateRequest` → red |
| 2.15 | `aRepeatedTerminateRequestWhilePendingAsksNobody` | absent | re-ask → red |
| 2.16 | `windowTitleReachesThePlatformOnChangeOnly` (fake counts title writes) | absent | push every build → red |
| 2.17 | `theTreeTitleWinsInnerBeatsOuterFirstSiblingBeatsSecond` (`N1`, `N2`, `N5`; removal falls back to `Window.title`) | absent | last report wins → red (siblings); outer wins → red (nesting) |
| 2.18 | `aTreeTitleIsInTheFirstPresentedFrame`: after `openWindow` the fake's title is the tree's | absent | apply before the build (one frame late) → red |
| 2.19 | `navigationDocumentSetsTheRepresentedPathAndLeavesTheTitle` (`N3`, `N4`; a non-file URL forwards `nil`; `Window.representedURL` fallback) | absent | forward `absoluteString` → red |
| 2.20 | `isDocumentEditedReachesThePlatformOnChange` | absent | no push → red |
| 2.21 | `aHiddenTitleBarLaysTheRootOutUnderTheBarAndStampsTheInsets`: fake answers `true` with insets (top 32, left 69) and grows to 450; root laid out at 450; `@Environment(\.titleBarInsets)` read in layout and paint = (32, 69); `.titleBar` → zero, fake told `.standard` | absent | stamp zero → red; never call `setTitleBarStyle` → red |
| 2.22 | `openWindowAppliesTheWindowStyleBeforeTheFirstFrame` | absent | apply after the first frame → red |
| 2.23 | `everyOnOpenURLInTheTargetWindowRunsInReversePostOrder` (nested + siblings; a `@State` write in a handler lands — `StateDispatch`) | absent | pre-order → red; no dispatch → the write is lost → red |
| 2.24 | `anOpenGoesToTheKeyWindowThenTheFirstWithAHandlerThenTheApp` | absent | ignore key state → red |
| 2.25 | `anOpenURLNobodyHandlesIsDroppedAndAppOpenDeliversAsThePlatformDoes` | absent | — |
| 2.26 | `aRemovedOnOpenURLNoLongerHearsURLs` (presence = the last build) | absent | keep handlers across builds → red |
| 2.27 | `theWindowPreferenceScopesAreTransparent`: content under `.navigationTitle`/`.navigationDocument`/`.onOpenURL` has the same `GlobalElementID` and `@State` as without; `theSevenRetentionSlotsAreMutuallyDistinct` untouched | absent | bump the cursor in the scope → red |

### §4.3 Lane 3 — demo and SDL `App` level

| # | Test | Red before | Mutation |
| --- | --- | --- | --- |
| 3.1 | `anSDLAppAsksOnQuitAndEndsOnTheWindowsReply` (`App` over `SDLPlatform(hiddenWindows: true, offscreenRenderers: true)`, ungated): window handler `.later`; pushed `MUI_EVENT_QUIT`; `run(maxIterations: 5)` runs all five; `replyToCloseRequest(true)` → the next `run(maxIterations: 5)` ends early with no window; the window's `onDisappear` ran once | absent | the walk never resumes on the reply → red |
| 3.2 | `anSDLWindowCloseVetoKeepsTheAppRunning` (pushed CLOSE, handler `.cancel`) | closes | — |
| 3.3 | `anSDLAppDeliversAnAppLevelFileDropToOnOpenURL` (raw window-0 drop → the window's handler ran) | absent | — |
| 3.4 | `theAppShellDemoAsksBeforeClosingAnEditedDocument` (`AppShellDemoTests`, fake): edited → close request shows the alert; "Don't Save" closes; clean → closes at once; the name field drives the title | absent | the demo's handler returns `.now` → red |
| 3.5 | the `buildTheAppShellDemo()` arm in `everyProductionTreeBuildsOnAOneMegabyteThread` | absent | — |

## §5 CI and commands

- Every lane: `swift build --build-system native --build-tests`, then the
  unfiltered `swift test --build-system native --no-parallel` (read the one
  summary line; confirm `FR-J no-argument frame: succeeded=`); `swift build
  --build-tests` 0 warnings; `zsh docs/probes/closeout-inventory-check.sh` and
  `zsh docs/probes/closeout-undocumented.sh` print nothing.
- Lanes 1 and 3 (Backends/SDL touched): `python3
  Backends/SDL/scripts/fetch-accesskit.py` once; from `Backends/SDL` `swift test
  $(python3 scripts/fetch-accesskit.py --print-flags)`; the Linux image
  (`docker build -t metalui-portable -f Backends/SDL/linux/Dockerfile
  Backends/SDL`, then `docker run --rm -v "$PWD":/work -v
  metalui-sdl-build-app-shell:/tmp/build -w /work/Backends/SDL metalui-portable
  bash -c 'swift build --build-tests --scratch-path /tmp/build && swift test
  --skip-build --scratch-path /tmp/build'`); a swift:6.4-noble root build.
- Lanes 2 and 3: `docs/probes/demo-pixels/compare.sh <scratch> c62d6ba HEAD` —
  0 px in all fourteen images; `DemoFrameDeterminismTests`' `Expected.swift`
  unedited.

## §6 Demo expectation (lane 3)

`METALUI_APP_SHELL_DEMO=1 swift run MetalUIDemo` (and the same variable for
`MetalUISDLDemo`): a 900 × 600 window, `windowStyle: .hiddenTitleBar`. A
40-point top bar padded by `titleBarInsets` (left by `insets.left + 12`, its
height at least `insets.top`) shows the document name and, when edited,
"— Edited"; the body has a name `TextField` (driving `.navigationTitle`), a
"Make a change" button (sets `window.isDocumentEdited = true`), a "Save"
button (clears it), and a list of URLs received through `.onOpenURL`
(`App.open` fed from the launch arguments by the recipe). The window's
`onCloseRequest` answers `.now` when clean, else shows "Do you want to save
the changes made to “name”?" with Save / Don't Save / Cancel and answers
`.later`; there is no `App.onTerminateRequest`, so ⌘Q asks through the window.
The demo's model holds the `Window` weakly. Built in its own function
(`appShellDemoContent()`), registered in `buildEveryProductionTree`.

## §7 Human checks — group AS (lane 3 writes it; an agent cannot run it)

- **AS1** Close button with unsaved changes → an alert sheet; Don't Save
  closes (and the app quits: last window); Cancel keeps; Save clears the
  marker and closes.
- **AS2** ⌘Q with unsaved changes → the same alert; Cancel keeps the app.
- **AS3** Log out with unsaved changes → the alert appears and logout waits
  (`.terminateLater`); frames keep drawing meanwhile (`AS-C` item 9).
- **AS4** The edited dot in the close button follows "Make a change"/"Save".
- **AS5** `navigationDocument`: the proxy icon beside the title; ⌘-click on
  the title shows the path menu.
- **AS6** Hidden title bar: traffic lights over the top bar, the top bar's
  content starts right of them, no title text.
- **AS7** Dragging the top bar's empty area moves the window; double-click
  zooms (System Settings' choice); a button in the band presses, not drags.
- **AS8** Full screen: the band goes, insets read zero, the top bar sits at
  the top.
- **AS9** A packaged `.app` (`docs/packaging.md` with a document type):
  Finder double-click, `open -a`, a drop on the Dock icon, launched and
  already running, each lists the URL once.
- **AS10** SDL (Linux, Windows): the WM close and Alt-F4 ask; Ctrl-C in the
  terminal asks; a file dropped on the window is a drag (not an open); the
  title shows no edited marker; the window keeps its system title bar.

## §8 Migration notes and registry rows

### §8.1 Migration (`docs/migration.md`)

1. (lane 1) **Ten new seam requirements** (`AS-H`), with the honest minimal
   spelling.
2. (lane 1) `AppKitPlatform.run()` sets `NSApp.delegate`; `MetalHostView`'s
   `mouseDownCanMoveWindow` is `false`.
3. (lane 1) SDL: `SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE` is `"0"`;
   `SDL_EVENT_QUIT` asks before stopping.
4. (lane 2) **Closing one of several windows no longer ends the app on
   AppKit**; the last window's close still does.
5. (lane 2) **⌘Q / system quit / `SDL_EVENT_QUIT` close every window first**:
   each window's `onDisappear` now runs on quit.

### §8.2 Registry rows

- `docs/divergences.md` (lane 3): **175** (hidden title bar: content under
  the bar, no safe area; SwiftUI keeps a 32-pt safe area, `H0`/`H1`; pin 2.21),
  **176** (`.onOpenURL` never opens a window and runs handlers in reverse
  post-order; SwiftUI's WindowGroup opens one per open, order unstable,
  `O0`–`O5`; pin 2.23/2.24). Not-offered rows: `navigationTitle` `Text`/
  `LocalizedStringKey`/`Binding`/builder overloads, `navigationSubtitle`,
  `Transferable` `navigationDocument`, `WindowStyle` as a protocol with style
  types and `.plain`, `windowDismissBehavior`, `WindowDragGesture`,
  `windowBackgroundDragBehavior`, `presentationPreventsAppTermination`,
  `dialogPreventsAppTermination`, `handlesExternalEvents`.
- Inventory map: every new public declaration (each lane its own; lane 3
  re-records the census).
- Record §05 (declared but inert): SDL's `isDocumentEdited`,
  `representedURL`, `.hiddenTitleBar` (recorded no-ops) — Record phase.

## §9 Must not move (every lane checks)

Identity and state retention (`theSevenRetentionSlotsAreMutuallyDistinct`,
MC-A/MC-C/MC-P numbering, `.id()` outermost — the three new
`EnvironmentWrite` cases mint no id, consume no cursor index); hit testing
(the band drag reads `onInput`'s existing answer; no hitbox change);
accessibility; animation; focus; `List` windowing and TB-AH; `Deferred`; text
input. 0 px in the fourteen offscreen images; `Expected.swift` unedited; 0
`warning:` on both build systems; `MetalUILayout` imports only `MetalUICore`;
`MetalUIScene` only `MetalUIShaderTypes`; `MetalUIPlatform` imports nothing new
(`Edges` is `MetalUICore`'s); Backends/SDL and the noble container build;
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.

## §10 Deferred (each with reason and owner)

| What | Why | Owner |
| --- | --- | --- |
| A tree-level `.onCloseRequest { }` (reads `@State`) | presence per window; the window-level handler covers M6-b | none |
| SDL client-side decorations (borderless + hit-test regions + drawn controls) for `.hiddenTitleBar` | MetalUI would draw and hit-test resize borders and buttons on Linux/Windows | none |
| Single-instance argument forwarding on Linux/Windows | IPC per platform; `App.open` takes what the app forwards | none |
| `presentationPreventsAppTermination` / `dialogPreventsAppTermination` | the probe's instrument could not separate them (`T1`–`T3`) | none |
| `windowDismissBehavior`, `WindowDragGesture`, `windowBackgroundDragBehavior`, `.plain` window style | not needed by M6; each a separate AppKit wiring | none |
| A public headless `Window` / test-support product (MetalCreator M6-e) | a separate item (C7's `CI-N` keeps the fakes in the test target) | the gap list's harness item |
