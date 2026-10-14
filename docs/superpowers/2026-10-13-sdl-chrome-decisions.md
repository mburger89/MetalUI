# SDL custom window chrome — decisions

Rulings for item S1: `windowStyle: .hiddenTitleBar`, title-bar insets, window drag, resize edges and
system buttons on SDL (Linux and Windows; macOS through SDL where it works). User request 2026-10-02
(gpui-gap priority list; **not a plan task**), reported as MetalCreator's SDL-port gap 3
(developer-c0, 2026-10-13; read, never edited).
Spec: [`specs/2026-10-13-sdl-chrome-design.md`](specs/2026-10-13-sdl-chrome-design.md).
Record: `../record/112-sdl-chrome.md`. Divergence labels 425–434 are this
branch's range.

Evidence:

- [`../probes/swiftui-window-chrome.swift`](../probes/swiftui-window-chrome.swift): SwiftUI has no
  minimise/zoom action, no drawn control set and no title-bar double-click hook (arm P compiles, N1–N4
  fail), recorded 2026-10-13.
- [`../probes/appkit-titlebar-hit-test.swift`](../probes/appkit-titlebar-hit-test.swift) and
  `swiftui-app-shell.swift` (`H0`/`H1`): the AppKit band, 32 pt, the buttons' right edge 69 pt (`AS-E`).
- SDL 3.4.18 `SDL_video.h` (read this session, not run): `SDL_SetWindowHitTest` "may fire at any time",
  "mouse input may not be delivered … within a special area", main-thread set only; `SDL_SetWindowBordered`
  cannot change a fullscreen window; no `SDL_StartWindowMove` exists.
- gpui (`WindowDecorations::Client`, `window_control_area`, `start_window_move`/`start_window_resize`):
  **from memory of `crates/gpui`, not re-read this session**; used only to choose the shape (hit-test
  regions plus drawn controls on Linux/Windows). SwiftUI has no analogue, so SwiftUI is not the authority
  for anything below beyond `WindowDragGesture`'s spelling (`WD-B`) and `.hiddenTitleBar`.

Next unused: `CW-V`.

## CW-A — Scope: what is built, what is deferred

**Ruling.** Built: (1) SDL applies `.hiddenTitleBar` (borderless window, `setTitleBarStyle` answers `true`);
(2) `titleBarInsets` on SDL; (3) drag through `SDL_SetWindowHitTest` from a snapshot of regions (the unclaimed
band, `AS-J`, and `WindowDragGesture` handles, `WD-`); (4) resize edges for a borderless window;
(5) drawn system buttons, drawn by the window where the platform has none; (6) `minimize()`/`toggleZoom()`
on `Window`; (7) double-click zoom where a press reaches `Window`, and natively on Windows.
Deferred, named: **Linux (X11/Wayland) double-click-to-zoom on the band** — SDL consumes a press inside a
draggable region, so `Window` never sees the second click (CW-I; owner: a measuring session on real X11 and
Wayland, human check CW6); Windows 11 snap-layout flyout (`HTMAXBUTTON` is not an SDL answer); rounded
corners and the DWM shadow of a borderless Windows window (platform, not ours); client-side shadows and
tiling on Wayland; `windowBackgroundDragBehavior`.
**Cost if wrong.** An item deferred here is a documented constraint in `docs/guides/cross-platform.md`.

## CW-B — `setTitleBarStyle(.hidden)` on SDL: `SDL_SetWindowBordered(false)`, answer `true`

**Ruling.** The bridge gains `mui_window_set_bordered(window, bool) -> bool`. `setTitleBarStyle(.hidden)` calls
it with `false`, `.standard` with `true`; the answer is SDL's result (`true`), so `Window.titleBarStyleApplied`
becomes true and everything `AS-E`/`AS-J` built switches on without a change there. Applied before the first
show (the window is created hidden, `WS-B`), so no frame is seen bordered. A fullscreen window cannot change
border state (SDL): the call answers `false` and `Window` keeps the standard insets; leaving fullscreen
re-sends nothing, so the platform re-applies the *last requested* style on `SDL_EVENT_WINDOW_LEAVE_FULLSCREEN`.
The client area keeps its size (the title bar's pixels are lost, not the content's): `contentSize` does **not**
grow by the band as on AppKit (`AS-E` item 3) — the band is inside the root, as `titleBarInsets.top` says.
The window stays `SDL_WINDOW_RESIZABLE`.
**Why not a `SDL_WINDOW_BORDERLESS` creation flag.** The style is settable after creation (`Window.windowStyle`),
and the creation path has no style yet.
**Cost if wrong.** A platform where `SetWindowBordered` fails answers `false` and keeps its system bar:
today's behaviour, no regression.

## CW-C — System buttons: drawn by the window, no public view; two verbs

**Ruling.** SwiftUI has none of this (probe arms N1–N4), so all of it is class M. (1) Where the platform has no
native window buttons under the hidden style (**SDL**: `PlatformWindow.hasNativeWindowControls == false`),
`Window` draws three buttons in a `Deferred` presentation-root strip over the content (the `MenuBarStrip`/
`ToolbarStrip` precedent, named root `$windowcontrols`, a name not a slot, `noteNamed`): minimise, zoom
(maximise/restore glyph by `isZoomed`), close. They are ordinary `Button`s: their hitboxes are opaque, so they
are blockers (CW-E) and work through the existing paths — close goes through `performClose()` (the `AS-B`
veto: `onCloseRequest`, `.later`), minimise and zoom through `PlatformWindow.performWindowAction`. Labels
"Close", "Minimise", "Zoom"/"Restore" reach accessibility. (2) **`Window.drawsWindowControls: Bool`**
(default `true`; MetalUI-only; no effect where the platform has native buttons or the style is standard)
lets an app that draws its own turn them off. (3) **`Window.minimize()` and `Window.toggleZoom()`** are the
verbs an app-supplied control calls (`performClose()` and `close()` exist, `AS-B`), also class M.
(4) **No public `WindowControls` view**: a view cannot know the platform's cluster edge, and a second
spelling of the same three buttons is API surface for no capability the property and verbs lack.
Layout: right-aligned trailing cluster of three 46×32 pt flat rectangles (Windows/Linux); **macOS through
SDL** (`#if os(macOS)` in the strip's builder, driver "cocoa") draws three 12 pt circles at the left edge
(AppKit's order), 70 pt wide cluster. Colours from the theme (`.surface`/`.separator`, destructive red hover
on close); no animation beyond hover wash.
**Cost if wrong.** If the three-button default proves unwanted, `drawsWindowControls = false` is the escape and
the only cost is an app that forgot it reads an extra control cluster.
**Rejected:** an app-supplied-only model (an app that sets `.hiddenTitleBar` and draws nothing would have a
window no mouse can close, which breaks `AS-E` item 2's "the window buttons stay" on the platform that
gained the style); a public `WindowControls` view (above).

## CW-D — `titleBarInsets` on SDL, per platform

**Ruling.** While the hidden style is applied and the window is not fullscreen, SDL answers
`top` = **32** (AppKit's band, so one app layout serves every platform), `bottom` 0; the controls cluster edge:
Linux/Windows `right` = **138** (3 × 46) and `left` 0; macOS-through-SDL `left` = **70** and `right` 0 — **each
only while `drawsWindowControls` is true**, else both 0 (the app owns the cluster). Who computes it: on a
platform whose `hasNativeWindowControls` is false the platform answers the band and the cluster **edge** it
would use (`top` 32 plus the 138 or 70 on `right`/`left`), and `Window.effectiveTitleBarInsets` gains one
clause that zeroes the cluster side when `drawsWindowControls` is false — so the platform never learns the
property and no further requirement exists. The value is read by `Window` at every build as today; a change
without a size change dirties the window through the existing insets path (`AS-E` item 5). Fullscreen answers
all zero and `Window` draws no strip and publishes no regions (the band is gone, as on AppKit).
**Cost if wrong.** A different Windows caption height (30–32 at 100%) shifts a glass bar by at most 2 pt.

## CW-E — Drag is hit-test regions from a snapshot; blockers are carved out

**Ruling.** SDL's callback runs in the OS event path and a `SDL_HITTEST_DRAGGABLE` area **removes the pointer
events inside it from the app** (SDL header; `WD-F` item 1). So a region may only cover pixels where the app
wants no pointer events, and `Window` computes them: after each presented/rendered frame, only when the platform
returned `true` from `setWindowDragRegions` earlier (cost on AppKit: zero), `Window` builds the
**candidate rects** — the band `(0, 0, width, titleBarInsets.top)` while the hidden style is applied (`AS-J`),
plus each `WindowDragGesture` element's rect (`WD-C`) — and **carves out every blocker**: each hitbox of the
frame that is opaque (`onClick`, `textInput`, `valueTrack`), a gesture-arena or draggable member (non-opaque,
`DN-U`), a drop destination, or a `contextual`/secondary-press target (all of which need pointer events). A
blocker's rect is its transformed bounding box clipped by its outer clip (conservative: one pixel too many
blocked, never one too few). Hover regions, scroll regions, tooltips and `.pointerStyle` regions are **not**
blockers (a root-level hover would otherwise forbid all drag) and so **lose their pointer events inside a
drag region on SDL — divergence 425** (SDL's swallow is unmeasured per platform, human check CW5). The
result is a list of disjoint rects (rect subtraction, x-then-y, `ChromeHitMap.carve`), **capped at 64**
(remaining area is simply not draggable; a counter `ChromeHitMap.truncated` is read in tests), ordered
top-to-bottom, left-to-right, deduplicated by value; `Window` publishes it **only when it changed**
(`==` of the arrays). **Any open presentation** (popover, menu, tooltip? no — popover, `anchoredOverlay`,
drawn menu, alert, sheet) **publishes an empty list**: a press outside must dismiss, and the press must reach
`Window`. A drag in progress (`mouseDown` armed arena) never changes the published list mid-gesture.
`performWindowDrag()` on SDL **stays `false`** (it records): SDL has no way to start a move from a callback
that already ran; the move happens in the OS before `Window` sees the press, and a `WindowDragGesture`
handle works because its rect is a region, not because the gesture ran. So the gesture's own semantics
(ends and cuts the others at a slop, `WD-C`) are inert on SDL for that handle, as it never receives the press
— **divergence 276 is amended** (SDL now moves the window from a handle; `performWindowDrag` still answers
`false`) and **divergence 426** names the rule that a handle containing a button or a tap is draggable only
around them.
**Cost if wrong.** A blocker missed makes a button in the band unclickable on SDL (the worst failure; the
carving test and human check CW3 pin it). A blocker over-collected makes a sliver undraggable.
**Rejected:** a region list from `Window.onInput`'s answer (the same trap `AS-J` found); a pure hit-box
copy without carving (kills buttons); letting hover block (kills the band under any root hover).

## CW-F — The seam: four defaultless requirements, every conformer answers

**Ruling.** `PlatformWindow` gains, **without defaults** (`HT-X` 1; migration note in `docs/migration.md`):
1. `func setWindowDragRegions(_ regions: [Rect<Pixels>]) -> Bool` — `true` when the platform uses them
   (AppKit `false`, SDL `true`, headless by `Options.usesWindowDragRegions`, default `false` = AppKit's answer).
   `Window` stops computing once it reads `false` for the platform it holds (it asks once with `[]` when the
   window opens and again on a style change).
2. `func performWindowAction(_ action: PlatformWindowAction) -> Bool` — `public enum PlatformWindowAction:
   Sendable, Equatable { case minimize, toggleZoom }`; AppKit `miniaturize(nil)`/`zoom(nil)` (`true`), SDL
   `SDL_MinimizeWindow` / `SDL_MaximizeWindow` or `SDL_RestoreWindow` by `SDL_WINDOW_MAXIMIZED` (`true` when SDL
   accepted), headless records and answers `true`.
3. `var hasNativeWindowControls: Bool { get }` — AppKit `true` (the traffic lights stay under the hidden style),
   SDL `false`, headless by `Options.hasNativeWindowControls` (default `true`, AppKit's). Plus a read-back
   `var isZoomed: Bool { get }` — AppKit `isZoomed`, SDL the maximized flag, headless a settable value; it is
   **a fourth defaultless member**; the migration note lists all four.
The headless platform's `Options` gains a one-call preset `Options.sdlChrome` (drag regions on, native
controls off, `appliesTitleBarStyle` true, SDL-like insets 32/138) so a test drives SDL's chrome path with no
SDL. **Every test fake** of `PlatformWindow` in `Tests/` and `Backends/SDL/Tests/` adds the four.
**Cost if wrong.** Four requirements are source-breaking for a third-party conformer (documented); a default
would let a conformer silently draw no controls, the failure the rule exists to prevent.

## CW-G — Resize edges: computed in the bridge's snapshot, only for a borderless window

**Ruling.** The hit-test snapshot carries the window's size (points), a **6-point** resize border and the
enabled axes. The callback answers, **in this order**: (1) a corner square (6×6 → 12×12 inside a corner:
`SDL_HITTEST_RESIZE_*` corner); (2) an edge; (3) a drag rect; (4) `SDL_HITTEST_NORMAL`. Edges apply **only while the
window is borderless** (the bridge knows; a bordered window's system frame resizes itself) and the window is not
maximized or fullscreen, and **never on an axis whose min and max size limits are equal** (`setContentSizeLimits`,
`SV-B`). The controls cluster is never reached by an edge on the top: the top edge is cut over the cluster
(a drag region never includes it, edges do — so the top-right 6-pt row over the controls resizes; accepted).
The callback never allocates and reads no MetalUI object other than the snapshot (CW-H).
**Cost if wrong.** A 6-pt border overlapping content (a scrollbar at the right edge) swallows its first 6 points
of pointer events; human check CW4 measures it; the width is a constant in one place.

## CW-H — Thread safety: an immutable snapshot box behind a lock

**Ruling.** SDL says the callback "may fire at any time" and on Windows it runs inside the window procedure.
The callback therefore reads
**one immutable value** and nothing else: `ChromeHitSnapshot` (portable, in `MetalUIPlatform`: size, border,
axes, `[Rect<Pixels>]`, `borderless`, `zoomedOrFullscreen`; `Sendable`, `func hit(at:) -> ChromeHit`, pure)
is the specification. The bridge holds a C copy of it (fixed array of at most 64 rects plus a header, no heap)
behind an **`SDL_Mutex`** created with the window and destroyed with it (`pthread_mutex_t` is not on Windows,
`os_unfair_lock` is Darwin-only; SDL's mutex is the one lock the C bridge already has everywhere). The
publisher (main thread, after a frame) swaps a new copy in under the lock; the callback locks, copies the
struct, unlocks and evaluates the copy with `mui_chrome_hit(const mui_chrome_snapshot *, float x, float y)`,
written in C. **A Swift test calls `mui_chrome_hit` and `ChromeHitSnapshot.hit` over one table of points and
requires equal answers**, so the Swift type specifies and the C function is checked against it (the `BoxBlur`
precedent, `PF-F`). The C enum result is converted explicitly (`Int32` on Windows).
**Why not an atomic pointer.** Retiring the old snapshot safely needs hazard handling; a lock held for a
memcpy is unmeasurably short and obviously correct. **Why not call Swift from the callback.** Reentrancy into
the main-actor world from the window procedure.
**Cost if wrong.** A callback blocked on the lock stalls the OS drag for one memcpy at worst; a deadlock is
impossible because neither side takes another lock while holding it.

## CW-I — Double-click on the band

**Ruling.** `SDLPlatformWindow.performTitleBarPress(clickCount:)` answers `true` and toggles zoom for
`clickCount >= 2` (via the CW-F action), `false` for 1 (the hit test already dragged). This runs only when SDL
delivered the press — i.e. over a region the snapshot made normal (a presentation open, or the band's blocker
gaps). **On Windows `SDL_HITTEST_DRAGGABLE` becomes `HTCAPTION`**, and `DefWindowProc` maximises/restores on a
caption double-click itself, so the user-visible behaviour is native there. **On X11/Wayland a draggable
region consumes both presses, so double-click zoom does not work** — deferred (CW-A), human check CW6,
**divergence 427** reserved for it: not taken until a real-display run confirms the failure.
**Cost if wrong.** If the Windows caption path does not maximise (SDL's `HTCAPTION` handling differs by
version), `performTitleBarPress` is unreachable and double-click zoom is missing there too; CW6 measures it.

## CW-J — What stays put

**Ruling.** Standard-style windows are untouched: no `SDL_SetWindowBordered` call, no strip, regions computed
only when `Window` holds a `true` from the platform **and** (the hidden style is applied or a
`WindowDragGesture` exists in the last frame) — a plain SDL window never installs a hit-test callback
(`SDL_SetWindowHitTest` is called on the first non-empty publish and cleared when the list and edges both become
empty). The 14 offscreen images (standard style) are 0 px; no `Handlers` member, no `StateTable` slot
(`$windowcontrols` is a named root, `noteNamed`), no `Frame` hitbox change (`AS-J`'s two-value read is kept;
the carve reads the existing hitbox list, `topmostHitbox` is not duplicated: the carve is a *region* function
over the list, not a point lookup, and says so in its header).
**Cost if wrong.** The first window with a drag region changes the hit-test state of the SDL window for its
life; clearing is tested.

## CW-K — Public API and class

**Ruling.** New public declarations: `Window.drawsWindowControls`, `Window.minimize()`, `Window.toggleZoom()`,
`Window.isZoomed` (read), `PlatformWindowAction`, the four `PlatformWindow` requirements,
`HeadlessPlatform.Options` additions (`usesWindowDragRegions`, `hasNativeWindowControls`, `sdlChrome`,
`isZoomed`) and the headless read-backs `TestWindow.windowDragRegions`, `.windowActions`. All class `M`
(inventory rows; SwiftUI has no analogue, probe N1–N4); `ChromeHitSnapshot` and `ChromeHit` are `public` in
`MetalUIPlatform` because the SDL module and its tests use them (M, "platform seam"). Each owes a doc comment;
`closeout-inventory-check.sh`, `closeout-undocumented.sh` print nothing; census re-recorded.

## CW-L — Lanes, order and what the first lane must not break

**Ruling.** Two lanes, disjoint files, **sequential** (lane 1's types are lane 2's inputs): lane 1 (root: seam,
`Window`, strip, headless, AppKit, root tests, demo section, docs) lands first with a green root suite; lane 2
(`Backends/SDL`: bridge, `SDLPlatform`, SDL tests, Linux image, docs it owns) follows. Lane 1's `SDLPlatform`
conformer additions are the one cross-lane edit and are made by lane 1 as `fatalError`-free stubs answering
today's values so `Backends/SDL` builds (`swift build` in `Backends/SDL`), which lane 2 replaces.
**Cost if wrong.** A lane 2 that finds the seam wrong sends the fix back to lane 1's files.

## CW-M — Critic: units, stale size, and the strip is not a presentation

**Ruling.** (1) `Rect<Pixels>` in `setWindowDragRegions` and `ChromeHitSnapshot` is the **window-coordinate unit
every other `PlatformWindow` position uses** (`presentMenu(_:at:)`, `Point<Pixels>`), which is SDL's hit-test
unit (window points, not device pixels); the SDL bridge converts nothing, and a test on a 2x headless window
pins that a region equals the hitbox rect in that unit. (2) The snapshot's window size is **not** trusted
between frames: the bridge refreshes the size under the same lock on `SDL_EVENT_WINDOW_RESIZED` (main thread,
before `Window` rebuilds), so a resize drag never evaluates edges against the old size; test: the C table over a
resized snapshot. (3) The `$windowcontrols` strip is a `Deferred` root but is **not an open presentation** for
CW-E's empty-list rule (the rule keys on the popover/menu/alert/sheet registries, never on any `Deferred`);
its buttons are blockers like any. Pinned by `theStripDoesNotEmptyTheRegions` (mutation: count the strip as a
presentation). (4) The strip's buttons are focusable and sit **last in `tabOrder`**, so Tab reaches content
first and the order of existing windows is unmoved (the strip exists only on a hidden-style SDL window).
**Cost if wrong.** (3) wrong makes the band undraggable whenever controls draw, i.e. always.

## CW-N — Critic: platform claims that are reads, not runs

**Ruling.** CW-I's Windows claim (`HTCAPTION` double-click maximise on a borderless SDL window) and CW-B's
"title bar pixels lost, client keeps size" are **SDL source reads, unmeasured**; a borderless Windows window may
lack the maximise box, so `performWindowAction(.toggleZoom)` is the only path that is promised, and the
double-click is promised nowhere until CW6 runs. `docs/guides/cross-platform.md` states only what the Linux
image and the headless pins measured. Windows `HTCAPTION` also yields the system menu on a right press inside a
region (divergence 425's family; CW5).

## CW-O — Critic: a deterministic thread pin

**Ruling.** `aConcurrentPublishNeverTearsAnAnswer` alone cannot be relied on to be red (a race). The pins that
must redden are deterministic: a bridge counter of `lock`/`unlock` pairs around publish and around the
callback's copy (mutation: remove the lock calls, the counter test reddens), plus the C-versus-Swift table. The
two-thread test stays as a smoke run and is not counted as a mutation killer.

## CW-P — Critic: lanes and file ownership

**Ruling.** Lane 1 is large but its files are one seam; it is not split (a split would share `Window`). The
cross-platform guide, `docs/guides/cross-platform.md`, is **lane 2's** (it states SDL behaviour only after the
Linux run; the earlier spec text listing it under lane 1 is superseded); lane 1 owns divergences, api-overview,
migration, testing.md, human checks group CW. The demo section is added to the one-megabyte-stack composer
test's table in the same change (`everyProductionTreeBuildsOnAOneMegabyteThread`), and `Handlers`, `StateTable`
slots and hit testing stay unmoved (the carve reads the hitbox list only).

## CW-Q — Lane 1 build rulings: where the spec's spelling met the code

**Ruling.** Lane 1 (record §112) built the seam, `Window`, the strip and the headless platform, and settled what the
spec left open or spelled wrongly. (1) **The rect type is `Bounds<Pixels>`**: `Rect<Pixels>` does not exist in
`MetalUICore`; `setWindowDragRegions(_:)`, `ChromeHitSnapshot.dragRegions` and the headless read-backs all use
`Bounds<Pixels>` (origin and size, half-open on the max edges, as `Bounds.contains`). (2) **The portable tests live in
`Tests/MetalUICrossPlatformTests/ChromeHitSnapshotTests.swift`**, not `MetalUIPlatformTests` (that target depends on
AppKit and is macOS-only); the Linux and Windows jobs run it. (3) **`ChromeHitMap.carve` is `package` in
`MetalUIPlatform`** beside `ChromeHitSnapshot` (portable, no `MetalUICore` import beyond geometry): it takes
`limit:` and answers `(rects, truncated)`; it subtracts each blocker, makes the candidates disjoint by subtracting the
ones already accepted, sorts in reading order (y, then x, then size), drops empty rects and deduplicates. Order of the
pieces of one subtraction is above, left, right, below. (4) **The strip is a fourth named root, `$windowcontrols` at
cursor index 3, not a `Deferred`**: a `Deferred` presentation root is hoisted above every layer and would rank above
the menu bar's and toolbar's hitboxes and the presentations a popover or alert opens; the `MenuBarStrip` precedent
(named root, own layout run, noted with `noteNamed`, prepainted after the root, the toolbar strip and the bar) gives
the order `CW-M` 4 asks for (last Tab stops) and cannot be mistaken for an open presentation (`CW-M` 3). The
cluster's rect is laid out over the root, taking none of its space. (5) **The cluster's side and style come from the
platform's insets, not `#if os(macOS)`**: `left > 0 && right <= 0` draws the 70-point left cluster of three 12-point
circles in AppKit's order; anything else the 138-point right cluster of flat 46-point rectangles, so a headless test
reaches both and the platform decides. The glyphs are text (`–`, `□`/`◱`, `×`); no hover wash (it would add a hover
region; not built). (6) **The first build asks the platform once**, `setWindowDragRegions([])`; a platform that
answered `false` is never computed for again, and a style change is not a re-ask (the list is recomputed every build
and published on change). A press in progress (`active != nil`) holds the published list still. (7) **A handle is a
hitbox whose only pointer asks are `WindowDragGesture` leaves**; a handle under a render effect is not a candidate
(its bounds are local), a blocker under one takes the clip at the effect's entry (a superset of every point it can be
hit at). A handle wholly under an enclosing element that needs the pointer (a `DragGesture` canvas, as the app shell
demo's) is carved away to nothing: divergence 426 names it. (8) **The work counter is `Window.testingChromeCarveCount`**
(`package`), not a `FrameWork` field: the pins count region computations, which no frame work type carries.
(9) **The headless platform gains `Options.hiddenTitleBarInsets`** (the insets it answers while the hidden style is
applied, `.sdlChrome`'s 32/138) beside the spec's four options, and a `.toggleZoom` action flips
`HeadlessPlatformWindow.isZoomed` as a platform that honoured it does. (10) **Fullscreen is "the band has no
height"**: with the hidden style applied and the platform's `titleBarInsets.top` zero the window draws no strip and
publishes no regions. (11) **`Window.minimize()` answers nothing and `toggleZoom()` dirties the window**; both ignore
the platform's answer. (12) The SDL conformer carries lane 1's four stubs (`CW-L`): `setWindowDragRegions` records and
answers `false`, `performWindowAction` records and answers `false`, `hasNativeWindowControls` `false`, `isZoomed`
`false`; the SDL demo's `main.swift` wiring of `METALUI_CHROME_DEMO` is lane 2's.
**Cost if wrong.** (4): if the strip must rank above a presentation's scrim it becomes a `Deferred` (the strip's
element is unchanged). (7): a handle under a gesture canvas is not draggable on SDL; `CW5`/`CW3` measure it.

## CW-R — Lane 1 verification: how the pins were mutated, and what each reddened

**Ruling.** Lane 1 ended at `3758 tests in 3 suites` passed (3717 + 41: 13 portable snapshot tests, 26 window
chrome tests, two typecheck guards; **236 guards**), `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only
`warning:` SwiftPM's deprecation notice, `swift build --build-tests` (default build system) 0 `warning:`; the fourteen
offscreen images 0 px against `fb9a7e42` (`compare.sh`, controls at their recorded values: light vs dark 1048576,
default vs modal 1031003, default vs animation 454895, `f0` vs `f3` 0). `Backends/SDL` on macOS 30 + 125 and in `swift:6.4-noble`
(`metalui-sdl-build-sdl-chrome`) 30 + 122 passed; the root package in the image (`metalui-root-build-sdl-chrome`) 0
`warning:`, `MetalUITestingTests` 252 and the portable suites passed. **Mutation method, a deviation from the item's letter, stated:** the
unfiltered suite takes eight minutes and a rebuild four, so the mutations were applied as **one instrumented build**
(committed tree first; a temporary `cwMutation` read from `CW_MUT`, each site `cwMutation == k ? mutated : original`, so
the mutated code is real compiled code), and each was run against the **forty-one new tests** by filter — the pins
the mutations name — not the full suite; the instrumentation was removed with `git checkout -- Sources` (restored from
the commit) and `git status --short` read clean, then the full unfiltered suite ran on the clean tree. What this does
not show is collateral reddening of a pre-existing test by a mutation; the reviewer re-takes any of them with the full
suite. Two guards (`CW-1`, `CW-2`) were mutated by an edit and rebuild: a protocol-extension default for
`performWindowAction` reddened `aPlatformWindowWithoutEachChromeRequirementDoesNotCompile` on the `performWindowAction`
arm only (both expectations); `toggleZoom` made `internal` reddened `theChromeVerbsAreReachableFromAPlainImport`
(`'toggleZoom' is inaccessible due to 'internal' protection level`). **Two pins were weak and were fixed** (commit
`test(CW): the standard-style insets pin sets…`): mutation 22 (the `titleBarStyleApplied` guard) reddened nothing
because the headless platform's insets are zero under the standard style anyway, and mutation 34 (regions scaled)
reddened nothing because the helper's `scaleFactor:` never reached `options` — both reddened after the fix.

| # | mutation (site: `ChromeHit.swift` 1–12, `Frame` 17, `Window` chrome 21–48) | reddened |
|---|---|---|
| 1 | `hit` skips the drag-rect loop | aDragRectIsHalfOpenOnItsMaxEdges, aPointInADragRectIsDraggable, anUnborderedWindowHasNoEdges, cornersBeatEdgesBeatDragRects, noEdgeOnAnAxisWithEqualLimits, noEdgesWhenZoomedOrFullscreen |
| 2 | drag rects closed on the max edge (`<=`) | aDragRectIsHalfOpenOnItsMaxEdges |
| 3 | `carve` ignores the blocker's y range | aButtonInTheBandIsCarvedOut, aHandleWithAButtonInsideIsRegionsAroundIt, aPressInProgressHoldsTheRegionsStill, aRectCarvedByABlockerLeavesTheRemainderOnly, aSpanningBlockerSplitsAndAnOutsideBlockerChangesNothing, aTextFieldInTheBandIsCarvedOut, aWindowDragHandleOutsideTheBandIsARegion, overlappingCandidatesAreMadeDisjoint |
| 4 | `carve` does not subtract accepted rects | overlappingCandidatesAreMadeDisjoint |
| 5 | drag rects tested before the edges | cornersBeatEdgesBeatDragRects, noEdgeOnAnAxisWithEqualLimits, theBorderIsSixPointsAndTheCornerTwelve |
| 6 | border 6 to 7 | theBorderIsSixPointsAndTheCornerTwelve |
| 7 | horizontal axis ignored (`resizableHorizontally`) | noEdgeOnAnAxisWithEqualLimits |
| 8 | `zoomedOrFullscreen` ignored | noEdgesWhenZoomedOrFullscreen |
| 9 | `borderless` ignored | anUnborderedWindowHasNoEdges |
| 10 | `maximumRegions` 64 to 65 | aListBeyondSixtyFourRectsIsCappedAndCounted |
| 11 | `carve` skips the reading-order sort | theResultIsInReadingOrderAndDeduplicated |
| 12 | outside-window guard dropped | aPointOutsideTheWindowIsNormal |
| 17 | strip prepainted before the root | theStripIsLastInTabOrder |
| 21 | `effectiveTitleBarInsets` ignores `drawsWindowControls` | aHiddenStyleOnAnSDLLikePlatformStampsBandAndClusterInsets, drawsWindowControlsFalseDrawsNoStripAndZeroesTheCluster |
| 22 | `effectiveTitleBarInsets` drops the `titleBarStyleApplied` guard | aStandardStyleWindowReadsZeroInsets |
| 23 | band candidate dropped | aButtonInTheBandIsCarvedOut, aHandleWithAButtonInsideIsRegionsAroundIt, aHoverRegionInTheBandIsNotABlocker, aPressInProgressHoldsTheRegionsStill, aTapGestureInTheBandIsCarvedOut, aTextFieldInTheBandIsCarvedOut, aWindowDragHandleOutsideTheBandIsARegion, anOpenAlertPublishesNoRegions, regionsAreInWindowPointsOnA2xWindow, regionsArePublishedOnlyOnChange, theBandIsOneRegionWhenNothingIsInIt, theStripDoesNotEmptyTheRegions |
| 24 | `onClick` hitboxes not blockers | aButtonInTheBandIsCarvedOut, aHandleWithAButtonInsideIsRegionsAroundIt, aPressInProgressHoldsTheRegionsStill, regionsArePublishedOnlyOnChange, theStripDoesNotEmptyTheRegions |
| 25 | gesture hitboxes not blockers | aTapGestureInTheBandIsCarvedOut, regionsAreInWindowPointsOnA2xWindow |
| 26 | text-input hitboxes not blockers | aTextFieldInTheBandIsCarvedOut |
| 27 | hover regions are blockers | aHoverRegionInTheBandIsNotABlocker |
| 28 | handles ignored | aHandleWithAButtonInsideIsRegionsAroundIt, aWindowDragHandleOutsideTheBandIsARegion |
| 29 | nothing is a handle | aHandleWithAButtonInsideIsRegionsAroundIt, aWindowDragHandleOutsideTheBandIsARegion |
| 30 | open presentations ignored | anOpenAlertPublishesNoRegions |
| 31 | the strip counts as a presentation | aPressInProgressHoldsTheRegionsStill, fullscreenPublishesNoRegionsAndNoStrip, theStripDoesNotEmptyTheRegions |
| 32 | published every frame | regionsArePublishedOnlyOnChange |
| 33 | a declining platform computed for anyway | aPlatformDecliningRegionsIsNeverAskedAgain |
| 34 | regions multiplied by the scale factor | regionsAreInWindowPointsOnA2xWindow |
| 35 | close button calls `close()` | theCloseButtonGoesThroughTheCloseVeto |
| 36 | minimise and zoom swapped | theMinimiseAndZoomButtonsSendTheirActions, zoomShowsRestoreAfterIsZoomed |
| 37 | zoom label constant | zoomShowsRestoreAfterIsZoomed |
| 38 | strip drawn with no band (fullscreen) | fullscreenPublishesNoRegionsAndNoStrip |
| 40 | preset `hasNativeWindowControls: true` | aHiddenStyleOnAnSDLLikePlatformStampsBandAndClusterInsets, aPressInProgressHoldsTheRegionsStill, drawsWindowControlsFalseDrawsNoStripAndZeroesTheCluster, regionsArePublishedOnlyOnChange, theCloseButtonGoesThroughTheCloseVeto, theMinimiseAndZoomButtonsSendTheirActions, theSDLChromePresetAnswersAsSDLDoes, theStripDoesNotEmptyTheRegions, theStripDrawsThreeButtonsWhereThePlatformHasNone, theStripIsLastInTabOrder, zoomShowsRestoreAfterIsZoomed |
| 41 | regions computed with no band and no handle | aStandardStyleWindowIsUntouched |
| 42 | strip drawn on a native-controls platform | aNativeControlsPlatformDrawsNoStrip |
| 43 | `minimize()` does nothing | theMinimiseAndZoomButtonsSendTheirActions, theWindowVerbsReachThePlatform |
| 44 | button width 46 to 45 | aPressInProgressHoldsTheRegionsStill, theStripDoesNotEmptyTheRegions, theStripDrawsThreeButtonsWhereThePlatformHasNone |
| 45 | `Window.isZoomed` constant `false` | zoomShowsRestoreAfterIsZoomed |
| 46 | headless `.toggleZoom` does not flip `isZoomed` | zoomShowsRestoreAfterIsZoomed |
| 48 | the `active == nil` hold dropped | aPressInProgressHoldsTheRegionsStill |

Not mutated, with the reason: the C bridge's `mui_chrome_hit` (lane 2); divergence 425's platform swallow (a human check,
`CW5`); the AppKit answers (four one-line members; `aPlatformWindowWithoutEachAppShellRequirementDoesNotCompile` and
the root suite compile them). Not run: Windows UTM / CI; a real window, drag or resize (group `CW`).
**Cost if wrong.** A collateral reddening the filtered runs could not see is found by the merge's full suite.


## CW-S — Lane 2 build rulings: where the spec met SDL

**Ruling.** Lane 2 (`Backends/SDL`, record §112) built the bridge and the platform, and settled what the spec
left open or spelled wrongly. (1) **A style asked for in fullscreen is recorded, answered `true` and applied on
leaving it** (supersedes `CW-B`'s "answers `false` and re-sends nothing"): SDL cannot change a fullscreen
window's border, the insets are zero there anyway, and an answer of `false` would have left `Window` believing
the style standard while the platform later made the window borderless. The deferral is a flag (`styleDeferred`)
cleared by the next resize, maximise or fullscreen event that finds the window out of fullscreen
(`SDL_EVENT_WINDOW_ENTER_FULLSCREEN`/`LEAVE_FULLSCREEN`/`MAXIMIZED`/`RESTORED` now translate to
`MUI_EVENT_RESIZE`, harmless extra `onResize` calls); the last request wins. (2) **The style answer is what the
driver did**: `mui_window_set_bordered` reads `SDL_WINDOW_BORDERLESS` back, because SDL answers `true` from
`SDL_SetWindowBordered` where the driver has no implementation. **Measured in the Linux image**: under
`SDL_VIDEO_DRIVER=offscreen` the flag never moves and `SDL_SetWindowHitTest` fails, so the platform answers
`false` to `setTitleBarStyle(.hidden)` (the window keeps its bar, the insets stay zero) and `false` to
`setWindowDragRegions` with a non-empty list (`Window` stops computing); on macOS (cocoa) both succeed on a
hidden window. A window with no edges and no regions installs nothing and still answers `true`. The pins that
need a working border or hit test are gated `.enabled(if:)` on that driver, as `SDLLifecycleTests` gates frames;
`theStyleAnswerIsWhatTheDriverDid` runs on every driver. (3) **The bridge**: one `ChromeState` per window
(`SDL_Mutex`, a `MUIChromeSnapshot` copy of at most 64 rects, counters) held in the window's SDL properties and
freed with it; `mui_window_destroy` clears the callback first. Swift fills the snapshot through
`mui_chrome_snapshot_init`/`_add_rect` (no 64-element tuple) and every result is an `Int32` constant
(`MUI_CHROME_HIT_*`), converted by `SDLChrome.hit(fromBridge:)`. `mui_window_chrome_hit` is the callback's own
body (lock, copy, unlock, evaluate), which the tests call, so the pins read the real locked path. A cleared
callback zeroes the snapshot, so the read-back answers normal. (4) **`titleBarInsets`** is chosen by
`#if os(macOS)` (left 70) else right 138, as lane 1's strip does from the insets; `performTitleBarPress(clickCount ≥ 2)`
is `performWindowAction(.toggleZoom)` and answers SDL's answer. (5) **`aConcurrentPublishNeverTearsAnAnswer`
judges single answers**: two separate calls may straddle a publish, which the first version took for a tear
(it failed in the Linux image); it is a smoke run, not a killer (`CW-O`). (6) **Not run**: Windows (`ssh
metalui-win` timed out, the CI jobs cover it) and any real drag, edge, double-click or snap; group `CW`.
**Cost if wrong.** (1): a window asked for `.hidden` while fullscreen shows a bar until it leaves fullscreen.
(2): a driver that implements the flag but reports it late answers `false` once and `Window` stays standard.

## CW-T — Lane 2 verification

**Ruling.** `Backends/SDL` on macOS 30 + 145 tests passed (lane 1 left 30 + 125; +20: 19 chrome tests and the
re-pinned app-shell answer), in `swift:6.4-noble` (`metalui-sdl-build-sdl-chrome`) 30 + 142 passed with 12 chrome pins
skipped by the offscreen driver. **Red first** (commit `75767811`): `SDLChromeTests.swift:146: cannot find type
'MUIChromeSnapshot' in scope`; the first green run in the image then failed 18 expectations in 9 tests, which
are the measured offscreen facts of `CW-S` (2) (and one flawed smoke test, `CW-S` (5)), each fixed by a gate or
a corrected pin, not by weakening an arm. **Mutation method**: the first seven were applied one at a time by
edit and rebuild (M1–M7); the load on the machine (other workflows, load average 36–80) made a rebuild take
about thirty minutes, so the rest ran as one instrumented build (a `CW_MUT` variable read by `cw_mut()` in C and
`cwMut` in Swift, each site `cwMut == k ? mutated : original`), the instrumentation reverted with
`git checkout -- Backends/SDL/Sources` and `git status --short` read clean. Results are in the table below.

| # | mutation (C `SDLBridge.c` 1–8, 18, 21, 22; Swift `SDLPlatform.swift` 9–17, 19, 20) | reddened (macOS, cocoa) |
|---|---|---|
| 0 | the instrumented tree, `CW_MUT` unset | nothing: 30 + 145 passed |
| 1 | drag rect max `<` to `<=` (C) | theBridgeCallbackAgreesWithTheSwiftReferenceOverATable |
| 2 | `SDL_SetWindowBordered` always `true` | hiddenStyleMakesTheWindowBorderlessAndAnswersTrue, standardStyleRestoresTheBorder (its first line), insetsAreBandPlusClusterPerPlatformAndZeroInFullscreen, leavingFullscreenAppliesTheLastRequestedStyle, theInstalledCallbackAnswersFromThePublishedRegions, aResizeRefreshesTheSnapshotSize, clearingTheRegionsAndEdgesRemovesTheCallback, aFullscreenWindowHasNoEdges, aFixedAxisHasNoEdge |
| 3 | publish without the lock | thePublishAndTheCallbackEachHoldTheLockOnce |
| 4 | callback copy without the lock | thePublishAndTheCallbackEachHoldTheLockOnce |
| 5 | C border 6 to 7 | theBridgeCallbackAgreesWithTheSwiftReferenceOverATable, theConstantsAreTheSwiftSpecifications |
| 6 | `MUI_CHROME_MAX_RECTS` 64 to 65 (header, by edit and rebuild) | theConstantsAreTheSwiftSpecifications |
| 7 | C hit ignores `borderless` | clearingTheRegionsAndEdgesRemovesTheCallback, theBridgeCallbackAgreesWithTheSwiftReferenceOverATable, theInstalledCallbackAnswersFromThePublishedRegions |
| 8 | clearing leaves the old snapshot | clearingTheRegionsAndEdgesRemovesTheCallback |
| 9 | band 32 to 30 | insetsAreBandPlusClusterPerPlatformAndZeroInFullscreen, sdlDocumentEditedRepresentedPathAndTitleBarStyleAreRecordedNoOps, theStyleAnswerIsWhatTheDriverDid |
| 10 | a single click zooms | aDoubleClickPressTogglesZoom, sdlDocumentEditedRepresentedPathAndTitleBarStyleAreRecordedNoOps |
| 11 | `.toggleZoom` always maximises | performWindowActionSendsMinimizeAndZoomRestore |
| 12 | no snapshot refresh on a resize event | aFullscreenWindowHasNoEdges, aResizeRefreshesTheSnapshotSize, leavingFullscreenAppliesTheLastRequestedStyle |
| 13 | never clear the callback | clearingTheRegionsAndEdgesRemovesTheCallback |
| 14 | the leave does not re-apply the style | leavingFullscreenAppliesTheLastRequestedStyle |
| 15 | `performWindowDrag()` answers `true` | performWindowDragStillRecordsAndAnswersFalse, sdlPerformWindowDragRecordsAndAnswersFalse |
| 16 | the zoomed flag ignored by the publish | aFullscreenWindowHasNoEdges |
| 17 | size limits ignored by the publish | aFixedAxisHasNoEdge |
| 18 | `add_rect` unbounded | theConstantsAreTheSwiftSpecifications |
| 19 | `.minimize` calls maximise | **survived** the first test. A first repair (`isZoomed == false` after the minimise) passed alone and failed in a full run (the zoom flag is not stable after a minimise under load), so the pin reads `mui_window_is_minimized` (`SDL_WINDOW_MINIMIZED`, new in the bridge) instead; three full runs green, and a one-off edit-and-rebuild of the mutation reddened `performWindowActionSendsMinimizeAndZoomRestore` on `mui_window_is_minimized(raw)` |
| 20 | fullscreen insets nonzero | insetsAreBandPlusClusterPerPlatformAndZeroInFullscreen |
| 21 | the style answer not read back | **survived on macOS** (cocoa honours the flag); in the Linux image (`CW_MUT=21`, offscreen driver) it reddened sdlDocumentEditedRepresentedPathAndTitleBarStyleAreRecordedNoOps and theStyleAnswerIsWhatTheDriverDid |
| 22 | `mui_window_destroy` keeps the callback installed | **survived**: not observable from a test (SDL's own destroy clears the callback before the state is freed); the line stays as a defensive ordering, named here, unpinned |

Not mutated, with the reason: `SDLChrome.hit(fromBridge:)`'s per-case mapping beyond `.draggable` (the table test compares
every case C returns against the Swift reference, so a swapped case reddens it), the `SDL_SetPointerPropertyWithCleanup`
failure path, the Windows `Int32` conversion (explicit, unrun). Not run: Windows (UTM unreachable, CI), a real drag, edge,
double-click or snap (group `CW`). **Cost if wrong.** A race the lock counter cannot see (the counter proves the lock is
taken, not that every field is under it); the table and counter pins are the checks, and the smoke run is not one.

## CW-U — Record-phase close: the left cluster is pinned, the suite re-taken

**Ruling.** The lane 1 verifier's one finding (forcing `onRight = true` in `WindowChrome.windowControlsSpec` reddened
nothing) is closed by `theMacLikeInsetsDrawTheLeftCluster` (a platform whose insets leave the band on the left, left 70
and right 0, draws three 12-point circles at x 13, 33, 53, y 10, in AppKit's order close, minimise, zoom); red under that
mutation (3 issues), green restored. The clean native run read **3759 tests in 3 suites**, 236 guards, the five known
locked-screen `AppKitPresentationTests` sheet issues and nothing else, `FR-J` true, 0 `error:` (record §112 §10). The lane
verifiers' full-suite mutation re-takes (one on lane 1, four on lane 2) reddened no pre-existing test, which stands for
the filtered runs of `CW-R` and `CW-T`. No divergence is taken beyond 425 and 426; 427 stays reserved for check CW6.
**Cost if wrong.** A collateral reddening of a pre-existing test by one of the other mutations is found by the next
full-suite run.
