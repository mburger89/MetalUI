# App shell — decisions

Rulings for item C8 of the gpui-gap priority list (user request 2026-10-02;
**not a plan task**): the window-close veto and the app-terminate hook, the
window title with an edited marker and a represented file, a hidden title bar
with full-size content, and open-document events. Requested by MetalCreator
(gaps M6-a…M6-d in `MetalCreator/docs/metalui-gaps.md`, master). Prefix `AS-`.
Branch `feat/app-shell` from `c62d6ba`. Spec:
[`specs/2026-10-08-app-shell-design.md`](specs/2026-10-08-app-shell-design.md).
Record: `../record/87-app-shell.md` (written in the Record phase).

**Next unused id: `AS-J`.**

## Final spellings (MetalCreator swaps its stopgaps by these names)

| Gap | API | Kind |
| --- | --- | --- |
| M6-b close veto | `Window.onCloseRequest: (@MainActor () -> CloseRequestReply)?` — return `.now`, `.cancel` or `.later`; after `.later`, `Window.replyToCloseRequest(_ shouldClose: Bool)`. `Window.close()` closes without asking; `Window.performClose()` asks as the close button does | MetalUI-only (`AS-B`) |
| M6-b quit | `App.onTerminateRequest: (@MainActor () -> CloseRequestReply)?`, `App.replyToTerminateRequest(_ shouldTerminate: Bool)`, `App.terminate()` (asks, as ⌘Q does). **With no `onTerminateRequest`, a quit asks every window's `onCloseRequest` in turn** — a one-window app sets only the window's handler and ⌘Q asks too | MetalUI-only (`AS-C`) |
| M6-a title | `Window.title` (settable), `.navigationTitle(_:)` in the tree (wins while present) | `Window.title` MetalUI-only; `.navigationTitle` SwiftUI (`AS-D`) |
| M6-a edited | `Window.isDocumentEdited` | MetalUI-only (`AS-D`) |
| M6-a represented file | `.navigationDocument(_ url: URL)` in the tree, `Window.representedURL` | SwiftUI / MetalUI-only (`AS-D`) |
| M6-c | `App.openWindow(…, windowStyle: .hiddenTitleBar, …)`, `Window.windowStyle`; content then lays out **under** the bar; `@Environment(\.titleBarInsets)` (`Edges<Pixels>`: `top` the bar's height, `left` the window buttons' right edge) | SwiftUI's `.windowStyle(.hiddenTitleBar)` as a window parameter; insets MetalUI-only (`AS-E`, `AS-F`) |
| M6-d | `.onOpenURL { url in }` in the tree; `App.onOpenURL` when no window has one; `App.open(_ urls: [URL])` to deliver launch arguments yourself | SwiftUI / MetalUI-only (`AS-G`) |

`CloseRequestReply` is declared in `MetalUIPlatform` (re-exported by
`MetalUI`) because the seam's `Platform.onTerminateRequest` answers with it
too.

Evidence (each header carries its recorded output and how to run it):

- [`../probes/swiftui-app-shell.swift`](../probes/swiftui-app-shell.swift)
  (**new**; arms `N0`–`N5`, `H0`, `H1`, `D0`, `D1`, `T0`–`T3`, `O0`–`O5`; run
  twice, byte-identical but for the handler order in `O1`/`O5`, which was then
  run four more times) — SwiftUI's window title, represented document, hidden
  title bar, dismiss behaviour, termination with a presentation up, and
  `.onOpenURL` delivery, read off the real `NSWindow`s and SwiftUI's own
  application delegate.
- [`../probes/appkit-titlebar-hit-test.swift`](../probes/appkit-titlebar-hit-test.swift)
  (**new**; arms `S0`, `F0`, `F1`; run twice, byte-identical) — what a press in
  the title-bar band hits under a transparent full-size title bar, the band's
  height and the window buttons' extent.
- The SwiftUI interface (`SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
  in the Xcode 27 SDK), grepped for `shouldClose|terminat|documentEdited|
  navigationDocument|navigationTitle|onOpenURL|hiddenTitleBar|windowStyle|
  WindowInteractionBehavior|WindowDragGesture`: there is **no** close-veto,
  terminate-hook or edited-marker API; the termination-adjacent declarations
  are `presentationPreventsAppTermination(_:)` and
  `dialogPreventsAppTermination(_:)` (macOS 15.4) and
  `windowDismissBehavior(_:)` (macOS 15).
- gpui (zed `main` at `4f6d97b9de7d9f167da8b7832eeecea22c5a9efa`,
  `crates/gpui/src/{window,app,platform}.rs`): `Window::on_window_should_close`
  (a synchronous `bool`; Zed answers `false`, prompts, and removes the window
  itself later), `App::on_app_quit` ("It is not possible to cancel the quit
  event at this point"; futures awaited up to `SHUTDOWN_TIMEOUT` = 200 ms),
  `App::on_open_urls(FnMut(Vec<String>))`, `Window::set_window_title`,
  `set_window_edited`, `set_document_path`, `TitlebarOptions {
  appears_transparent, traffic_light_position }`, `WindowControlArea::Drag`
  and `start_window_move`.
- SDL 3.2 (`release-3.2.x`): `src/events/SDL_windowevents.c` sends
  `SDL_EVENT_QUIT` after the **last visible** top-level window's
  `SDL_EVENT_WINDOW_CLOSE_REQUESTED` unless `SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE`
  is `"0"` (a hidden window counts as none, so with every window hidden any
  close request sends a quit); `src/video/cocoa/SDL_cocoaevents.m`
  `-[SDL3Application terminate:]` sends `SDL_EVENT_QUIT` (⌘Q and system
  shutdown), `application:openFile:` and the `kAEGetURL` handler each send
  `SDL_EVENT_DROP_FILE` with **no window** (window id 0) — a path, or the URL
  string for a URL event — then `SDL_EVENT_DROP_COMPLETE`.
- The source at `c62d6ba`: `App.openWindow` wires `platformWindow.onClose` to
  `runDisappearancesForClose()` and, on AppKit, `NSApplication.shared.terminate`
  on **every** window's close; `App.windows` never shrinks; `AppKitPlatform`
  has no `NSApplicationDelegate`; `AppKitWindow` is the `NSWindowDelegate` and
  implements only `windowWillClose`; `SDLPlatform.dispatch` answers
  `MUI_EVENT_QUIT` with `stop()` and `MUI_EVENT_CLOSE` by closing the window at
  once; a drop with window id 0 reaches `windows[0]`, nobody.

## AS-A — Scope: four parts, each built on AppKit and SDL; SwiftUI's spelling where SwiftUI has one

**Ruling.**

1. **Built:** the close veto and the terminate hook (`AS-B`, `AS-C`); the
   title, edited marker and represented file (`AS-D`); the hidden title bar
   with full-size content and its insets (`AS-E`), dragging from the band
   (`AS-F`); open-document events (`AS-G`).
2. **SwiftUI-aligned** where the probe found an API: `.navigationTitle`
   (`N1`, `N2`, `N5`), `.navigationDocument(_ url:)` (`N3`, `N4`),
   `.windowStyle(.hiddenTitleBar)` (`H0`; a window parameter, MetalUI having no
   `Scene`, as `SV-L` did for `.windowResizability`), `.onOpenURL` (`O0`–`O5`).
3. **MetalUI-only by ruling** where SwiftUI has none (the interface grep): the
   close veto, the terminate hook, `isDocumentEdited`, `Window.title`,
   `Window.representedURL`, `titleBarInsets`, `App.onOpenURL`, `App.open`.
   Their shape follows AppKit (`windowShouldClose`, `applicationShouldTerminate`
   with `.terminateLater` + `reply(toApplicationShouldTerminate:)`,
   `isDocumentEdited`, `representedURL`) and gpui (`on_window_should_close`,
   `set_window_edited`, `on_open_urls`), not an invented vocabulary.
4. **Ten defaultless seam requirements** (`AS-H`): six on `PlatformWindow`,
   four on `Platform`, each with an honest AppKit, SDL and test-fake answer.

**Cost if wrong.** A SwiftUI spelling shipped where SwiftUI's semantics differ
would mislead a porter; each such difference is a divergence row (175, 176).

## AS-B — The window-close veto: a handler answering now, cancel or later, and a reply

**Ruling.**

1. **API** (`Sources/MetalUI/WindowShell.swift`):
   `public enum CloseRequestReply: Sendable, Equatable { case now, cancel, later }`
   (in `MetalUIPlatform`); `Window.onCloseRequest: (@MainActor () ->
   CloseRequestReply)?` (default `nil`: close at once);
   `Window.replyToCloseRequest(_ shouldClose: Bool)`;
   `Window.isCloseRequestPending: Bool { get }`; `Window.close()` (closes now,
   never asks — AppKit's `close()`); `Window.performClose()` (asks exactly as
   the close button does — AppKit's `performClose(_:)`).
2. **Semantics.** A close request — the title bar's close button, ⌘W through
   the standard menu's Close (`performClose:`), SDL's
   `SDL_EVENT_WINDOW_CLOSE_REQUESTED` (the WM's close, Alt-F4), or
   `performClose()` — runs the handler once. `.now` closes; `.cancel` keeps
   the window and forgets the request; `.later` keeps the window and marks the
   request **pending**: further requests while pending run nothing and keep
   the window (no second alert); `replyToCloseRequest(true)` closes,
   `replyToCloseRequest(false)` forgets the request; a reply with nothing
   pending does nothing (`close()` is the unconditional spelling).
3. **The alert.** The handler runs outside every phase (a platform callback,
   never inside a frame), so it may write an `@Observable` model that a
   `.alert(isPresented:)` in the window's tree reads; the alert presents after
   the next frame through the existing `SV-` path — an `NSAlert` sheet on
   AppKit, the drawn modal `AlertPanel` on SDL — and its button calls
   `replyToCloseRequest`. Nothing new in the presentation machinery. (`@State`
   is unreachable from a window-level closure; a tree-level spelling is
   deferred, item 7.)
4. **The real close is the only close that runs `onClose`.** `onClose` →
   `runDisappearancesForClose()` (`LC-J`) runs once, when the platform window
   actually closes — never on `.cancel`, `.later` or a pending repeat. After
   it the `Window` draws nothing more (`drawFrameIfNeeded` returns at once once
   closed) and `App` drops it from `windows`.
5. **Seam** (`AS-H`): `PlatformWindow.onCloseRequest: (() -> Bool)?` (the
   platform's question; `nil` or `true` closes) and `PlatformWindow.close()`
   (closes without asking; `onClose` follows exactly once). `Window` installs
   the handler and turns `.later` into `false` plus its own pending flag — no
   platform has a window-level "later", so the seam has none.
6. **AppKit**: `AppKitWindow.windowShouldClose(_:)` answers
   `onCloseRequest?() ?? true`; `close()` is `NSWindow.close()` (which fires
   `windowWillClose` → `onClose`). **SDL**: `SDLPlatform.dispatch`'s
   `MUI_EVENT_CLOSE` asks `window.onCloseRequest?() ?? true` and closes only on
   `true`; `close()` hides the window (`SDL_HideWindow`, new
   `mui_window_hide`), removes it from the platform and fires `onClose` once;
   `mui_platform_init` sets `SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE` to `"0"`, so a
   vetoed close of the last window sends no `SDL_EVENT_QUIT` (the SDL source;
   pinned by test 1.13, whose hidden windows make SDL send a quit on every close
   request with the hint at its default).
7. **Deferred:** a tree-level `.onCloseRequest { }` modifier (reading
   `@State`); owner none — it needs presence semantics per window and the
   window-level handler covers M6-b. SwiftUI's `.windowDismissBehavior(.disabled)`
   (`D0`: clears `.closable`, a static switch, not a veto) is **not offered**;
   owner none.

**Evidence.** Interface grep (no SwiftUI veto); `D0`/`D1`; gpui's
`on_window_should_close` (synchronous bool, Zed closes later itself — this
ruling's `.cancel` + `close()` is that pattern, `.later` the AppKit-shaped
convenience that also blocks a second alert).

**Cost if wrong.** A pending request that is never answered leaves a window the
user cannot close except through `close()`; documented on `.later`. A handler
that writes `@State` would need item 7.

## AS-C — The terminate hook: App decides, or every window is asked in turn; the last window's close ends the app without asking

**Ruling.**

1. **API** (`Sources/MetalUI/AppShell.swift`): `App.onTerminateRequest:
   (@MainActor () -> CloseRequestReply)?`; `App.replyToTerminateRequest(_
   shouldTerminate: Bool)`; `App.terminate()` — a termination request exactly
   as ⌘Q makes one (it asks).
2. **Who is asked.** A termination request — ⌘Q / the application menu's
   Quit, a system logout or shutdown (AppKit's `applicationShouldTerminate`),
   SDL's `SDL_EVENT_QUIT` (⌘Q under SDL's Cocoa backend, SIGINT on Unix, a
   desktop's session end), or `App.terminate()`:
   - **With `onTerminateRequest` set, it alone decides**; windows are not asked.
   - **Without it, every open window's `onCloseRequest` is asked in turn**, in
     open order: `.now` (or no handler) closes that window and moves on;
     `.cancel` cancels the termination (windows already closed stay closed);
     `.later` waits for that window's `replyToCloseRequest` — `true` closes it
     and moves on, `false` cancels. When every window has closed, the app
     ends. This is DocumentGroup's behaviour (each document asked) made
     general, and it means a one-window app that sets only the window handler
     is asked on ⌘Q as well (M6-b's stopgap: "close and quit don't" ask).
3. **Approved termination closes every remaining window first**, each through
   `PlatformWindow.close()` — so every window's `onDisappear` runs once (`LC-J`)
   before the process ends, on ⌘Q as on the close button. **Migration**: at
   `c62d6ba` ⌘Q and `SDL_EVENT_QUIT` ended the app without running any
   `onDisappear`.
4. **Pending.** `.later` from the app handler or a window makes the request
   pending; a repeated request while pending answers `.later` and asks
   nobody. `replyToTerminateRequest(true)` ends the app (item 3),
   `false` cancels. A reply with nothing pending does nothing.
5. **The last window's close ends the app without asking** — the close was
   already the user's answer. **Closing one of several windows no longer ends
   the app** (migration: at `c62d6ba` AppKit terminated on *every* window's
   close). `App.windows` drops a window when it closes.
6. **Seam** (`AS-H`): `Platform.onTerminateRequest: (() -> CloseRequestReply)?`
   (`nil` answers `.now`), `Platform.replyToTerminateRequest(_:)` (the answer
   to a request this platform asked that got `.later`), `Platform.terminate()`
   (ends the event loop now, asking nobody). `App` installs the handler in its
   initialiser; its own approved paths (the last window, `App.terminate()`
   approved synchronously or by reply) call `platform.terminate()`; a platform
   request answered `.later` and later approved is answered with
   `replyToTerminateRequest(true)`.
7. **AppKit** (`Sources/MetalUIAppKit/AppKitApplicationDelegate.swift`, new):
   an `NSApplicationDelegate` owned by `AppKitPlatform`, **installed as
   `NSApp.delegate` in `run()`** before `NSApplication.run()` (so a test
   process never gets one, and the launch-time `odoc` Apple Event, dispatched
   by `finishLaunching` inside `run()`, finds it). `applicationShouldTerminate`
   maps `.now/.cancel/.later` to `.terminateNow/.terminateCancel/.terminateLater`
   and answers `.terminateNow` without asking once `terminate()` approved;
   `replyToTerminateRequest` is `NSApp.reply(toApplicationShouldTerminate:)`;
   `terminate()` sets the approval and calls `NSApp.terminate(nil)`. Both
   AppKit calls go through injectable closures (`terminator`,
   `terminateReplier`), so no test ends the test process.
   **Migration**: `run()` replaces any `NSApp.delegate` the app set.
8. **SDL**: `MUI_EVENT_QUIT` asks `onTerminateRequest`: `.now` → `stop()`,
   `.cancel` → nothing, `.later` → nothing until
   `replyToTerminateRequest(true)` → `stop()`. `terminate()` is `stop()`.
   SIGINT in a terminal is therefore vetoable too (SDL turns it into the same
   event) — documented.
9. **`.terminateLater` and the run loop.** While a `.later` termination is
   pending AppKit runs its loop in `NSModalPanelRunLoopMode`; the display link
   is added in `.common` (which includes it) and main-queue work drains in
   common modes, so frames and the alert sheet keep working. Unmeasured by the
   suite (no test can call `run()`); human check AS3.
10. **Not offered:** `presentationPreventsAppTermination(_:)` /
    `dialogPreventsAppTermination(_:)` — the probe's instrument (`T1`–`T3`)
    could not separate the modifier (`terminateNow` with or without it), so
    nothing rests on it; owner none.

**Evidence.** Interface grep; `T0`–`T3`; gpui's `on_app_quit` cannot cancel
(this ruling can — M6-b needs it); SDL's cocoa `terminate:`; the
`c62d6ba` source (terminate on every close).

**Cost if wrong.** If asking every window on quit surprises an app with
non-document windows, it sets `App.onTerminateRequest` (which then decides
alone). The last-window rule changes multi-window apps on AppKit (migration
note); single-window apps behave as before.

## AS-D — The window title, the edited marker and the represented file

**Ruling.**

1. **`Window.title: String`** — get/set, initially `openWindow(title:)`'s.
   The platform's title is the tree's navigation title when it has one, else
   `Window.title`; it reaches `PlatformWindow.title` only when that effective
   value changes.
2. **`.navigationTitle(_ title: some StringProtocol)`** on every
   `ElementGroup` (proposal content keeps its type): SwiftUI's window title on
   macOS with no navigation container (`N1`), followed when it changes (`N1`).
   **Precedence, probed:** the inner title wins over an enclosing one (`N2`),
   the first of two siblings wins (`N5`) — together "the first report in
   post-order": each scope builds its content, then reports its own title only
   if nothing has been reported this build. A tree title is in the **first
   presented frame** (applied after the build, as `CR-Q` does for the scheme).
   Removing it falls back to `Window.title`.
3. **`.navigationDocument(_ url: URL)`** and **`Window.representedURL: URL?`**:
   the represented file (`N3`): the tree's (same precedence) else the
   window's. **It never changes the title** (`N3`: the title stayed "Probe";
   `N4`: both). A non-file URL is not forwarded (the seam carries a path).
4. **`Window.isDocumentEdited: Bool`** (default `false`): AppKit's edited dot
   in the close button. SwiftUI has no view-level marker (`isDocumentEdited`
   read `false` in every arm; only `DocumentGroup` sets it); MetalUI-only.
5. **Seam** (`AS-H`): the existing settable `PlatformWindow.title`;
   `setDocumentEdited(_:)` and `setRepresentedFilePath(_ path: String?)`,
   called only on change. **AppKit**: `isDocumentEdited`, `representedURL =
   URL(fileURLWithPath:)` (`nil` clears). **SDL**: both **recorded and
   otherwise no-ops** — the title is never altered behind the app's back (a
   `" *"` suffix would make `Window.title` read differently from the screen);
   an app wanting a marker on Linux/Windows writes it into its title.
6. **Mechanism**: `.navigationTitle` and `.navigationDocument` are new
   `EnvironmentWrite` cases reported through `EnvironmentScope`'s existing
   `reportingPreference` path (`CR-L`'s), so they are layout- and
   identity-transparent with proposal conformance for free; like
   `.preferredColorScheme`, a legacy decoration directly after one does not
   compile (`EV-B`).
7. **Not offered**: the `Text`, `LocalizedStringKey` (a literal resolves to
   the `StringProtocol` overload), `Binding<String>` (an editable title) and
   view-builder `navigationTitle` overloads; the `Transferable`
   `navigationDocument` overloads; `navigationSubtitle`. Owner none.

**Evidence.** `N0`–`N5`; gpui `set_window_title`/`set_window_edited`/
`set_document_path`.

**Cost if wrong.** A sibling or nesting case SwiftUI resolves differently from
`N2`/`N5` would show as a wrong title; both shapes are pinned (test 2.17).

## AS-E — A hidden title bar: `windowStyle: .hiddenTitleBar`, content under the bar, the insets in the environment

**Ruling.**

1. **API**: `public struct WindowStyle: Sendable, Equatable` with
   `.automatic` (= `.titleBar`), `.titleBar`, `.hiddenTitleBar`;
   `App.openWindow(…, windowStyle: WindowStyle = .automatic, …)` (applied
   before the first frame, as `SV-L`'s limits are) and `Window.windowStyle`
   (settable later). SwiftUI's `WindowStyle` is a protocol with style types;
   MetalUI's is a closed struct — `.windowStyle(HiddenTitleBarWindowStyle())`
   and `.plain` are not offered (owner none).
2. **AppKit**, the flags SwiftUI sets (`H0`): `.fullSizeContentView` inserted,
   `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`; the
   traffic lights stay. `.titleBar` restores all three. (MetalUI's standard
   window is **not** full-size content — SwiftUI's always is, `N0` — and does
   not become so: the standard style's pixels must not move.)
3. **Content lays out under the bar.** The host view then fills the window
   frame, `contentSize` grows by the band and the root lays out over it.
   SwiftUI instead keeps content in a 32-pt safe area unless
   `.ignoresSafeArea()` (`H0` vs `H1`); MetalUI has no safe area, and M6-c
   wants exactly `H1`'s layout — **divergence 175**.
4. **`EnvironmentValues.titleBarInsets: Edges<Pixels>`**, `public
   internal(set)`, stamped by the frame at the root from the window (as
   `displayScale` is, never from `Window.environment`): `top` = the band's
   height (`frame − contentLayoutRect`: 32 pt, 66 with a toolbar, `F0`/`F1`),
   `left` = the zoom button's right edge in window coordinates (69 pt, 79 with
   a toolbar), `right`/`bottom` 0; all zero under `.titleBar`, in full screen
   (the band is gone) and on SDL. An app pads its top bar by them.
5. **Seam** (`AS-H`): `PlatformWindow.setTitleBarStyle(_ style:
   PlatformTitleBarStyle) -> Bool` (`.standard`, `.hidden`; `true` when
   applied) and `PlatformWindow.titleBarInsets: Edges<Pixels> { get }`, read by
   `Window` at each build. A change of the insets without a size change (a
   toolbar added under the hidden bar) reaches `onResize`: `AppKitWindow`
   observes `contentLayoutRect` (KVO) and reports.
6. **SDL: a documented constraint.** `setTitleBarStyle(.hidden)` records the
   request and answers `false`; the window keeps its system decoration and the
   insets read zero, so content laid out with them is still correct.
   Client-side decorations (`SDL_WINDOW_BORDERLESS`, `SDL_SetWindowHitTest`
   for the drag and resize regions, drawn close/minimise/maximise controls) are
   **deferred**, owner none: on Linux and Windows a borderless window loses
   the system's resize border and buttons, so MetalUI would have to draw and
   hit-test all of them (gpui's `window_decorations`/`WindowControlArea` is
   that machinery).

**Evidence.** `N0`, `H0`, `H1`; `appkit-titlebar-hit-test.swift` `F0`, `F1`;
gpui `TitlebarOptions`.

**Cost if wrong.** If apps expect SwiftUI's safe-area layout, divergence 175
names the difference and the insets give the padding.

## AS-F — Under a hidden title bar, a press the content does not claim in the band drags the window

**Ruling.**

1. **Measured** (`F0`): under the transparent full-size bar, a press anywhere
   in the band but on a window button reaches the **content view** — MetalUI's
   host view. AppKit drags the window from there only if that view's
   `mouseDownCanMoveWindow` allows, so a band full of MetalUI content would
   either never drag the window or drag it over MetalUI's own controls.
2. **Rule**: `MetalHostView.mouseDownCanMoveWindow` is `false`; in
   `mouseDown(with:)`, when the window style is hidden, the press lies in the
   band (`y < titleBarInsets.top`) and `onInput(.mouseDown)` answered `false`
   (no stage claimed it — no hitbox, no gesture), the host view calls
   `window.performDrag(with: event)`; an unclaimed **double**-click there runs
   the system's title-bar double-click action (`AppleActionOnDoubleClick`:
   zoom, minimise or nothing). A claimed press is MetalUI's as anywhere else.
   No hit-testing change: the answer is the one `onInput` already returns.
3. **Not offered**: SwiftUI's `WindowDragGesture` and
   `.windowBackgroundDragBehavior` (macOS 15); owner none — the band rule
   covers M6-c. **SDL**: nothing (the system title bar drags).

**Evidence.** `F0`; gpui's `WindowControlArea::Drag` + `start_window_move`
(the same idea, explicit regions).

**Cost if wrong.** A real drag cannot run headless; `performDrag` is reached
through an injectable closure (test 1.7b), the drag itself is human check AS7.

## AS-G — Open-document events: `.onOpenURL`, routed by `App` to existing windows; never a new window

**Ruling.**

1. **API**: `.onOpenURL(perform: @escaping @MainActor (URL) -> Void)` on every
   `ElementGroup` (a third new `EnvironmentWrite` case, transparent as `AS-D`
   item 6); `App.onOpenURL: (@MainActor (URL) -> Void)?` (the catch-all);
   `App.open(_ urls: [URL])` — delivers as the platform does (for launch
   arguments, item 6, and tests).
2. **Routing** (MetalUI's, `O4`'s answer): each URL goes to **one window** —
   the key window if it has a handler, else the first open window (open order)
   that has one; there **every** handler present in the window's last build
   runs once, under `StateDispatch` for its owner (the id `LifecycleScope`
   uses: `.child(of: parent, at: cursor)`), in **reverse post-order**; then
   the window is marked dirty. No window with a handler → `App.onOpenURL`; none
   → dropped. URLs arrive outside every phase (a platform callback), so a
   handler may write `@State` and open a window.
3. **SwiftUI, probed**: a `WindowGroup` opens a **new** window per external
   open and runs that window's handlers (`O0`, `O1`, `O3`), opens one even
   with no handler (`O2`), and uses the existing window only with
   `.handlesExternalEvents(preferring:allowing:)` (`O4`, `O5`). MetalUI has no
   `WindowGroup` and never opens a window itself — **divergence 176**; an app
   that wants a window per document opens one from `App.onOpenURL` (with no
   handler in any window) or from its handler. **Order**: SwiftUI runs every
   handler once in an order that varied between runs (`O1` outer-first five
   times of six, `O5` right-first five of six); MetalUI fixes reverse
   post-order, which is that majority order (outer before inner, later sibling
   first).
4. **Seam** (`AS-H`): `Platform.onOpenURLs: (([String]) -> Void)?` —
   absolute URL strings; a platform **parks** URLs that arrive before the
   handler is set and delivers them on assignment. `App` sets it in its
   initialiser and converts with `URL(string:)` (an unparsable string is
   dropped).
5. **AppKit**: the delegate's `application(_:open:)` (Finder double-click,
   `open -a`, a drop on the Dock icon, Open Recent, a URL scheme — the bundle
   must declare `CFBundleDocumentTypes`/`CFBundleURLTypes`, build-side,
   `docs/packaging.md`) → `onOpenURLs(urls.map(\.absoluteString))`. **SDL**:
   `SDL_EVENT_DROP_FILE` with window id **0** (SDL's Cocoa `openFile:` and URL
   events; a drop onto a window keeps going to drag and drop, `DN-M`) is
   collected until its `DROP_COMPLETE` (window 0) and delivered as one call —
   a string with a URL scheme (`[A-Za-z][A-Za-z0-9+.-]*:` followed by `//`)
   as is, anything else as a path through the existing
   `fileURLString(fromPath:)`. A `DROP_TEXT` with window 0 is ignored.
6. **Launch arguments are the app's** (Linux, Windows, and `swift run` on
   macOS): MetalUI reads no `CommandLine.arguments` — a test runner's and
   SwiftPM's flags are there too, and only the app knows which arguments are
   documents. The recipe (`docs/packaging.md`, `docs/migration.md`): after
   opening the window, `app.open(CommandLine.arguments.dropFirst().filter {
   FileManager.default.fileExists(atPath: $0) }.map(URL.init(fileURLWithPath:)))`.
   A second instance forwarding its arguments to the first (single-instance
   apps on Linux/Windows) is **deferred**, owner none.
7. **No `InputEvent` case.** An open names no window: it reaches `App` from
   the platform, and `App` picks the window; a `.openURLs` case on
   `InputEvent` would cost every exhaustive switch a migration for an event no
   platform window ever delivers. The handlers still run under
   `StateDispatch`, outside every phase, as a queued input event's would.
   (This departs from the item's suggestion of "a queued `InputEvent`" for
   that reason.)

**Evidence.** `O0`–`O5`; SDL cocoa source; gpui `on_open_urls`.

**Cost if wrong.** An app relying on SwiftUI's new-window behaviour sees its
URL in the existing window instead; divergence 176 and `App.onOpenURL` say how
to get a window.

## AS-H — Ten defaultless seam requirements, honest on AppKit, SDL and every fake

**Ruling.**

1. **`PlatformWindow`** gains six, none with a default (a conformer that
   forgets one fails to compile, `MD-J`'s rule): `var onCloseRequest: (() ->
   Bool)? { get set }`, `func close()`, `func setDocumentEdited(_ edited:
   Bool)`, `func setRepresentedFilePath(_ path: String?)`, `func
   setTitleBarStyle(_ style: PlatformTitleBarStyle) -> Bool`, `var
   titleBarInsets: Edges<Pixels> { get }`.
2. **`Platform`** gains four: `var onTerminateRequest: (() ->
   CloseRequestReply)? { get set }`, `func replyToTerminateRequest(_
   shouldTerminate: Bool)`, `func terminate()`, `var onOpenURLs: (([String])
   -> Void)? { get set }`.
3. **New types** in `Sources/MetalUIPlatform/AppShell.swift`:
   `CloseRequestReply` and `PlatformTitleBarStyle` (`.standard`, `.hidden`).
4. **Implementations**: AppKit and SDL as `AS-B`…`AS-G`; `FakePlatformWindow`
   and `FakePlatform` record every call and gain `simulateCloseRequest() ->
   Bool`, `simulateTerminateRequest() -> CloseRequestReply`,
   `simulateOpenURLs(_:)`, a scriptable title-bar answer and insets; every
   `*CompileGuards.swift` conformer template and Backends/SDL's
   `RecordingSDLPlatform` gain the members.
5. **Migration note** (`docs/migration.md`): the ten members with the
   minimal honest spelling for a conformer that has no such feature
   (`onCloseRequest` stored and asked before closing; `close()` closing;
   recording no-ops; `setTitleBarStyle` answering `false`; zero insets;
   `onTerminateRequest` asked before ending; `terminate()` ending;
   `onOpenURLs` stored).

**Cost if wrong.** A third-party conformer must add ten members — the
established price of a defaultless seam (`MD-J`, `CR-M`, `MV-F`).

## AS-I — Lanes, tests and what must not move

**Ruling.** Three lanes on disjoint files, in order 1 → 2 → 3 (spec §3):
lane 1 the seam and both platforms; lane 2 `App`/`Window` and the tree
modifiers; lane 3 the demo, the SDL `App`-level tests, the registries, the
human checks and the Record phase. Every test named in spec §4 with its red
state and the mutation that must redden it. Nothing in the must-not-move list
(spec §9) moves: identity and the seven retention slots (the three new
`EnvironmentWrite` cases mint no id and consume no cursor index), hit testing
(the band drag reads `onInput`'s existing answer), accessibility, animation,
focus, `List`, `Deferred`, text input, the fourteen offscreen images (the
standard window style is unchanged and the demo section is behind its own
switch).
