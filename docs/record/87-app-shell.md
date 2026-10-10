# 87 — App shell: the close veto, the quit hook, the window title and edited marker, the hidden title bar, open-document events (item C8)

Branch `feat/app-shell` from `c62d6ba` (master at the time: the `fix/clip-nested-flattening` and
`feat/input-apis` merges). **Not a plan task**: item C8 of the gpui-gap priority list (user request
2026-10-02), requested by MetalCreator (a node-based CAD app on MetalUI; gaps M6-a…M6-d in
`MetalCreator/docs/metalui-gaps.md`, read, never edited). Spec
`docs/superpowers/specs/2026-10-08-app-shell-design.md`; rulings `AS-A`…`AS-Q` in
`docs/superpowers/2026-10-08-app-shell-decisions.md` (next unused `AS-R`); probes
`docs/probes/swiftui-app-shell.swift` (arms `N0`–`N5`, `H0`, `H1`, `D0`, `D1`, `T0`–`T3`,
`O0`–`O5`), `appkit-titlebar-hit-test.swift` (`S0`, `F0`, `F1`) and
`appkit-launch-arguments-open.swift` (`A0`–`A6`). Parallel branches at the time:
`feat/controls-looks` (§85, merged into this branch at `2155f1e`, §11) and `feat/key-focus` (§88).

**Status: implemented and recorded (2026-10-09)** — a design session and critic, three lanes
(1 the seam and both platforms; 2 `App`, `Window` and the tree modifiers; 3 the demo, the SDL
`App`-level tests and the registries), each red first and each verified `ok`, then this Record
phase. Divergence labels **175 and 176** (the branch's reserved range 175–184; 177–184 unused, the
header's next-label line left for the merge). Human checks group **AS** (AS1–AS10) owed.

## §0 What the request was, and the final spellings

MetalCreator stopped on four gaps and wrote stopgaps named after the APIs it expected. The decisions
doc's table names each final spelling prominently (`AS-A`); in short:

| Gap | Final spelling | Kind |
| --- | --- | --- |
| M6-b close veto | `Window.onCloseRequest: (@MainActor () -> CloseRequestReply)?` returning `.now`, `.cancel` or `.later`; after `.later`, `Window.replyToCloseRequest(_:)`; `Window.close()` closes without asking, `Window.performClose()` asks | MetalUI-only (`AS-B`) |
| M6-b quit | `App.onTerminateRequest`, `App.replyToTerminateRequest(_:)`, `App.terminate()`; **with no app handler a quit asks every window's `onCloseRequest` in turn** | MetalUI-only (`AS-C`) |
| M6-a | `Window.title`, `.navigationTitle(_:)`, `Window.isDocumentEdited`, `.navigationDocument(_:)`, `Window.representedURL` | SwiftUI where it has one (`AS-D`) |
| M6-c | `App.openWindow(…, windowStyle: .hiddenTitleBar)`, `Window.windowStyle`, `@Environment(\.titleBarInsets)` | SwiftUI's `.windowStyle` as a window parameter; insets MetalUI-only (`AS-E`) |
| M6-d | `.onOpenURL { url in }`, `App.onOpenURL`, `App.open(_:)` | SwiftUI / MetalUI-only (`AS-G`) |

SwiftUI has no close-veto, terminate-hook or edited-marker API (the SDK interface grep of
`swiftui-app-shell`'s notes: only `presentationPreventsAppTermination`,
`dialogPreventsAppTermination` and `windowDismissBehavior` are adjacent), so those spellings follow
AppKit (`windowShouldClose`, `applicationShouldTerminate` with `.terminateLater`, `isDocumentEdited`,
`representedURL`) and gpui, by ruling.

## §1 What landed

**The seam (lane 1, `AS-H`, `AS-J`, `AS-O`).** Eleven defaultless requirements: seven on
`PlatformWindow` (`onCloseRequest`, `close()`, `setDocumentEdited(_:)`,
`setRepresentedFilePath(_:)`, `setTitleBarStyle(_:) -> Bool`, `titleBarInsets`,
`performTitleBarPress(clickCount:) -> Bool`) and four on `Platform` (`onTerminateRequest`,
`replyToTerminateRequest(_:)`, `terminate()`, `onOpenURLs`), plus `CloseRequestReply` and
`PlatformTitleBarStyle` in `Sources/MetalUIPlatform/AppShell.swift`. A migration note names the
minimal honest spelling for a conformer with none of the features.

- **AppKit.** `windowShouldClose` asks `onCloseRequest`; `close()` is `NSWindow.close()` (asks
  nothing); `isDocumentEdited` and `representedURL` set the native dot and proxy icon; the hidden
  style sets SwiftUI's three flags (`.fullSizeContentView`, transparent title bar, hidden title) and
  **restores the frame it found** (`AS-O` item 1: inserting the flag on a window already on screen
  keeps the content size and shrinks the frame, measured), insets from the frame less
  `contentLayoutRect` and the zoom button (32 and 69 measured), a KVO on `contentLayoutRect` reports
  a deeper band (a toolbar under it, `AS-O` item 2); a new `AppKitApplicationDelegate`
  (`applicationShouldTerminate` mapped `.now`/`.cancel`/`.later` to
  `.terminateNow`/`.terminateCancel`/`.terminateLater`, a reply only for its own pending
  `.terminateLater`, `application(_:open:)` parking until a handler) installed by `run()`.
- **SDL.** `SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE` set to `"0"` (SDL would otherwise send a quit
  after the last visible window's close request, and a hidden window counts as none, `AS-L`);
  `SDL_EVENT_WINDOW_CLOSE_REQUESTED` asks the window's handler; `SDL_EVENT_QUIT` asks
  `onTerminateRequest`; `close()` hides, removes and fires `onClose` once; a drop with window id 0
  (SDL's own `application:openFile:` and URL events) is an open URL, a path made a file URL, a
  scheme string itself; the edited marker, represented path and title-bar style are recorded no-ops
  and `setTitleBarStyle` answers `false` (a documented constraint: no borderless drag region,
  divergence 175's SDL half).
- **Fakes.** `FakePlatformWindow`/`FakePlatform` record every call and gain
  `simulateCloseRequest()`, `simulateTerminateRequest()`, `simulateOpenURLs(_:)`, a scriptable
  title-bar answer and insets; the ten `*CompileGuards.swift` conformer templates and
  `RecordingSDLPlatform` implement all eleven.

**`Window` and `App` (lane 2, `AS-B`…`AS-G`, `AS-J`, `AS-K`, `AS-P`, `AS-Q`).** `Window`'s shell
(`WindowShell.swift`): the title, edited marker, represented URL, style, the close handler and its
pending reply; a closed window draws no more frames. `App` (`AppShell.swift`): the terminate hook
and **the walk that owns the end** (`AS-K`: with no app handler each window is asked in turn, a
`.later` pauses the walk, the window's real close resumes it, the app ends only when the walk has
closed everything); closing one of several windows no longer terminates (the old
`NSApplication.terminate` on every close is gone, with a migration note); the last window's close
ends the app asking nobody; closed windows are retired after the main queue's next turn. The tree
modifiers `.navigationTitle`, `.navigationDocument` and `.onOpenURL` are three `EnvironmentWrite`
cases in `WindowPreferences.swift`: transparent (no node, no id level, no cursor index, the seven
retention slots unmoved), title and document taken from the first report in post-order, handlers
appended in post-order and run in reverse post-order under `StateDispatch`. The insets are stamped
by `Window` beside its other root stamps (`AS-P` item 2) and follow the platform's *answer* to
`setTitleBarStyle`, never its report, so the standard style reads zero everywhere. The band press
(`AS-J`): an unclaimed primary press in the hidden bar's band, with no active hitbox and no
gesture arena, asks the platform to drag the window (a double click performs the title bar's
action).

**Demo (lane 3).** `METALUI_APP_SHELL_DEMO=1` in `MetalUIDemo` and `MetalUISDLDemo`: a 900 × 600
hidden-title-bar window, a top bar padded by `titleBarInsets`, a name field driving
`.navigationTitle`, "Make a change" / "Save" for the edited marker, a close alert answering
`.later`, and the URLs received through `.onOpenURL` fed by the launch-argument recipe
(`AS-M`: AppKit delivers no command-line path to `application(_:open:)`, probe `A0`–`A6`, so the
recipe delivers each document once through `App.open`). Built in its own function
(`appShellDemoContent()`), registered in `buildEveryProductionTree`; one arm in
`everyProductionTreeBuildsOnAOneMegabyteThread`.

**Registries.** Divergences 175 (a hidden title bar's content: SwiftUI keeps it below the bar in a
32-point safe area, MetalUI lays it under, probes `H0`/`H1`) and 176 (an open-document event never
opens a window: key window with a handler, else the first, else the app; probes `O0`–`O5`); row 120
extended (`AS-N`: the window-preference modifiers share its constraint); inventory families
`app-shell-seam`, `window-shell`, `navigation-title`, `on-open-url`; `docs/api-overview.md`,
`docs/packaging.md` (document types, URL schemes and the launch-argument recipe),
`docs/migration.md` (the eleven requirements; one-of-several window close; quit closes every window
first); human checks AS1–AS10.

## §2 Tests and guards, per file

Baseline `c62d6ba`: 2873 tests, 0 goldens, 185 guards. Root +48 tests; `Backends/SDL` +9.

| File | Tests | Notes |
| --- | --- | --- |
| `AppShellCompileGuards.swift` | 1 | 2.1: every public spelling from outside the module (plain `import MetalUI`) |
| `AppShellSeamCompileGuards.swift` | 2 | 1.1/1.2: a conformer missing any of the seven / four requirements does not compile; a complete one does (`typecheckFile`) |
| `AppKitAppShellTests.swift` | 11 | 1.3–1.11, 1.7b, 1.18's AppKit half: real `AppKitWindow` and delegate |
| `AppShellTests.swift` | 19 | 2.2–2.15, 2.12b, 2.14b, 2.21, 2.21b, 2.22: close, quit, band press, style |
| `WindowTitleTests.swift` | 6 | 2.16–2.20, 2.27: title, document, edited, transparency |
| `OpenURLTests.swift` | 6 | 2.23–2.26 with 2.23b and 2.25b: routing, order, parking |
| `AppShellDemoTests.swift` | 3 | 3.4, 3.4b, 3.4c: the demo asks before closing an edited document, pads its bar, lists opens |
| `DemoStackBudgetTests.swift` | 0 new | one arm (3.5) in `everyProductionTreeBuildsOnAOneMegabyteThread` |
| `Backends/SDL` `SDLAppShellTests.swift` | 6 | 1.12–1.17 over a hidden window, pushed events, no presented frame |
| `Backends/SDL` `SDLAppShellAppTests.swift` | 3 | 3.1–3.3: an `App` over `SDLPlatform(hiddenWindows:offscreenRenderers:)`, ungated, runs under the Linux image's offscreen driver |

Ten existing guard files (the `*CompileGuards.swift` conformer templates) gained the eleven conformer members (test support). New typecheck
guards: three (1.1, 1.2, 2.1), each mutated red once (§5 G1–G3).

## §3 Probes

Run on the real objects, headers carry the output and how to run them.

- **`swiftui-app-shell.swift`**: `N0`–`N5` title (`.navigationTitle` sets the `NSWindow`'s title,
  the innermost wins, the first sibling wins), `N3`/`N4` `.navigationDocument` sets
  `representedURL` and leaves the title; `H0`/`H1` the hidden title bar leaves the content below the
  bar in a 32-point safe area (divergence 175); `D0`/`D1` dismiss behaviour; `T0`–`T3` termination
  with a presentation up; `O0`–`O5` `.onOpenURL`: a new window per open, handler order varying
  between runs (divergence 176). Re-run by the critic with the screen unlocked: `N5` and `H0`
  byte-identical.
- **`appkit-titlebar-hit-test.swift`**: what a press in the band hits under a transparent
  full-size title bar, its height and the buttons' extent (`AS-F`, `AS-J`).
- **`appkit-launch-arguments-open.swift`**: AppKit delivers no command-line path to
  `application(_:open:)`; a LaunchServices open does, before `didFinishLaunching` (`AS-M`).
- The Xcode 27 SDK interface and gpui (zed `4f6d97b9`) read for the MetalUI-only spellings
  (decisions doc, evidence list).

## §4 Red runs

- **Lane 1** (at `cd0b143`, 2873 passing): 1.1 and 1.2's positive arms failed ("cannot find type
  'PlatformTitleBarStyle'", "'CloseRequestReply'"); 1.3–1.11 and 1.18 failed with 71 compile
  errors; 1.12–1.17 failed to compile in `Backends/SDL`.
- **Lane 2** (at `3356851`, baseline re-taken 2886): the test target did not compile, 177 errors,
  by file (`AppShellTests`, `WindowTitleTests`, `OpenURLTests`); 2.1's positive arm could not run.
- **Lane 3** (`e586151`): `DemoStackBudgetTests.swift:47`: "cannot find 'appShellDemoContent' in
  scope", and `appShellDocumentSectionBody` (`AppShellDemoTests` likewise), so 3.4–3.4c and the
  1 MB-stack arm could not compile. 3.1–3.3 compile against lanes 1–2 and arrive green by design;
  each is shown able to fail by mutations D–F below.

## §5 Mutation tables

Each applied once to a committed tree, restored from a copy, the full unfiltered suite,
`git status --short` after each. Named tests, not counts.

**Lane 2** (M1–M37): the table is in `AS-P` (decisions doc), the reviewer's M35–M37 on `5e101c0`
included. The review's re-runs: V1 (`title` setter only stores) reddened
`windowTitleReachesThePlatformOnChangeOnly`; V2 (`.onOpenURL` owner `.child(of: parent, at:
cursor + 1)`) reddened `anOnOpenURLOutsideAnAliasedElementWritesThatOccurrencesState`; V2b (owner
the parent) reddened that and `everyOnOpenURLInTheTargetWindowRunsInReversePostOrder`; V10
(`answerCloseRequest` without `!shell.isClosed`) reddened `performCloseAsksAndCloseDoesNot`.

**Lane 1** (the verifier's re-runs on `3356851`; the lane's earlier mutations are not tabulated
in the decisions doc, so only these three are claimed):

| # | mutation | reddened |
| --- | --- | --- |
| S1 | `SDLPlatform.replyToTerminateRequest(_:)`'s nothing-pending guard removed (`SDLPlatform.swift`) | `sdlQuitAsksOnTerminateRequest` (`ticks == 3`, line 120) |
| S4 | `mui_window_hide` removed from `SDLWindow.close()` | `sdlCloseHidesRemovesAndFiresOnCloseOnce` (`!mui_window_is_shown`, line 142) |
| R-close2 | `AppKitWindow.close()` fires `onClose` on every close after the first | `appKitCloseClosesWithoutAskingAndFiresOnCloseOnce` (`closed.count == 1`, line 106; only the new second-close arm separates it) |

**Lane 3.**

| # | mutation (file) | reddened |
| --- | --- | --- |
| M1 | `closeRequested()`'s `guard isEdited else { return .now }` replaced by `return .now` (`AppShellDemo.swift`) | `theAppShellDemoAsksBeforeClosingAnEditedDocument` |
| M2 | the top bar's left padding `insets.left.value + 12` replaced by `12` | `theAppShellDemoPadsItsTopBarByTheTitleBarInsets` |
| M3 | `appShellDemoLaunchURLs` without its file-exists filter (the first run was killed by an external signal, exit 144; restored and re-run to completion) | `theAppShellDemoListsLaunchArgumentsAndLaterOpens` |
| M4 | `openAppShellDemoWindow`'s `windowStyle: .hiddenTitleBar` replaced by `.automatic` | `theAppShellDemoPadsItsTopBarByTheTitleBarInsets` |
| D | `if closed { return }` before `switch walkWindows` in `windowCloseRequestResolved` (`AppShell.swift`); run on the `Backends/SDL` suite (24 passed; 107 tests, 5 issues). Also run on the full unfiltered root suite in this Record phase (3069 tests, 8 issues: the five sheet tests of §9 and these three) | `anSDLAppAsksOnQuitAndEndsOnTheWindowsReply` (SDL); root: `withoutAnAppHandlerQuitAsksEachWindowInTurn` (line 359), `aPendingWindowClosedDirectlyResumesTheQuit` (385), `appTerminateAsksThenEndsThroughThePlatform` (413) |
| E | `SDLPlatform.dispatch`'s `MUI_EVENT_CLOSE` ignores the veto (`_ = window.onCloseRequest?()`) | `anSDLWindowCloseVetoKeepsTheAppRunning`, `sdlACloseRequestAsksTheWindowAndAVetoKeepsItOpen` |
| F | window-0 drops not routed to the application (`if event.window_id == 0 && false`) | `anSDLAppDeliversAnAppLevelFileDropToOnOpenURL`, `sdlAFileDroppedOnTheAppIsAnOpenURL` |

The three new typecheck guards, each mutated red once (Record phase; G1 and G2 applied together
to `Sources/MetalUIPlatform/Platform.swift`, two protocol-extension defaults, run with
`--filter DoesNotCompile` on the native build: 33 tests, 4 issues — filtered, since each guard is
its own test and the filter selects the two that read the source; restored from a copy, `git
status` clean):

| # | mutation | reddened |
| --- | --- | --- |
| G1 | `extension PlatformWindow { public func close() {} }` | `aPlatformWindowWithoutEachAppShellRequirementDoesNotCompile` (lines 121, 122: `!without.succeeded`, the message naming the member) |
| G2 | `extension Platform { public func terminate() {} }` | `aPlatformWithoutEachAppShellRequirementDoesNotCompile` (lines 142, 143) |
| G3 | `titleBarInsets`' setter `public` (`AS-P` M1, lane 2, full suite) | `anOutsideModuleCanSpellTheAppShellAPI` |

## §6 Green mutations and pins that prove less than they look

- **`AS-P` item 9**: "skip `endEverything()`'s closes" left 2.9 green, since with no handlers the
  walk closes each window itself; 2.9 gained an app-handler-`.now` arm that the mutation reddens.
- **`AS-L`**: test 1.13 as specified could not be red — SDL's last-window quit lives in
  `SDL_SendWindowEvent`, which a pushed event never reaches; the hint's value is pinned directly,
  and the behaviour is human check AS10.
- **`AS-O` item 7**: 1.3 asks the window's delegate through `NSWindowDelegate`, not through
  `performClose(_:)`, whose nested event loop ended the test process with exit 0 (six of six
  filtered runs). The close button and ⌘W themselves are human check AS1.
- **`AS-Q`**: parking in the platforms covers only URLs that arrive before `App`'s initialiser, and
  `App` drops them; `AS-M` item 2's earlier claim was refuted by a scratch test and corrected, 2.25b
  pins it.
- **Test 2.14b** pins that a closed `Window` outlives its own close callback; the release after the
  main-queue drain is documented, unpinned.
- **Unmeasured**: the proxy icon, the edited dot, traffic-light placement, the real ⌘Q alert and the
  band drag are looks (§8); nothing in the suite sees them.

## §7 Demo comparison

`docs/probes/demo-pixels/compare.sh <scratch> c62d6ba HEAD` at lane 3: **0 differing pixels and an
identical scene in all fourteen offscreen images**, every control non-zero where required. The
standard window style is unchanged and the app shell section sits behind its own switch, so none of
the fourteen can see it (the zero is a statement about what must not move, not about the new
section). The Record phase's re-run **after the merge**, against master `2155f1e` (the right
base once master's own rendering work is in; `compare.sh <scratch> 2155f1e c2cd8f9`, `c2cd8f9` this
branch's merge-plus-docs commit, which touches no `Sources/` file): **0 differing pixels and an
identical scene in all fourteen images**. `DemoFrameDeterminismTests`'
`Expected.swift` unedited; `git diff c62d6ba..HEAD` touches no file under `Sources/MetalUILayout`,
`Sources/MetalUIScene` or `Expected.swift`.

## §8 Looks owed (none performed; an agent cannot)

`docs/verification/human-checks.md` group **AS**: AS1 the close button with unsaved changes (the
alert sheet); AS2 ⌘Q with unsaved changes; AS3 Log Out with unsaved changes (`T0`–`T3`: a quit with
a presentation up); AS4 the edited dot; AS5 a represented document's proxy icon; AS6 the hidden
title bar (traffic lights over the top bar, the 12-point left padding); AS7 the band drag; AS8 full
screen (the band goes, the insets follow); AS9 open-document events from a packaged app (Finder
double-click, `open -a`, a drop on the Dock icon, launch with a path); AS10 SDL on Linux, Windows
and macOS (the drawn alert, Alt-F4/WM close vetoed, a drop on the app). No real-window capture was
taken at any lane (the lock probe read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`); the
real `NSWindow` readings in `AS-O` and the probes were taken in short unlocked windows.

## §9 Hazards

- **Five `AppKitPresentationTests` sheet tests fail while the screen is locked** (`NSOpenPanel`,
  `NSSavePanel` sheets): `appKitOpenDialogIsASheetWithTheDeclaredTypes`,
  `appKitSaveDialogCarriesTheNameTypesAndExportPrompt`, `appKitCancelledDialogArrivesAsQueuedInput`,
  `appKitDismissPresentationEndsTheSheetAndAnswersNothing`,
  `appKitSecondDialogWhileASheetIsUpAnswersFalse`. They fail identically at `c62d6ba` in the same
  environment (base run: 2873 with the same five issues) and pass filtered or unlocked.
- **A real `performClose(_:)` in a test ends the process** with exit 0 and no summary line
  (`AS-O` item 7; record §61 §9's HIToolbox stop). Ask the delegate instead.
- **A new `PlatformWindow`/`Platform` conformer must add eleven members** (migration note).
- **`NSApplication.terminate` is no longer called on every window close**: an app relying on
  closing one of several windows quitting must call `App.terminate()` (migration note).
- **An SDL window test needing a presented frame** is gated on the driver; 3.1–3.3 and 1.12–1.17 use
  hidden windows and pushed events and run ungated in the Linux image.
- **Windows 1 MB stack**: the demo's tree is built in its own function and has its arm in
  `everyProductionTreeBuildsOnAOneMegabyteThread`.
- **A `Window` closed by the platform mid-callback** is retired after the main queue's next turn
  (`AS-K` item 3), not dropped inside its own `onClose`.

## §10 Deferrals, with owners

- Client-side decorations on SDL: a borderless window with a drag region and drawn
  close/minimise/maximise controls, so the hidden title bar works on Linux and Windows
  (`AS-E` item 6: `setTitleBarStyle` answers `false` there, the insets read zero); owner none.
- `windowDismissBehavior` (probe `D0`) is not offered, and a window-scoped "closed" modifier is not
  built (`AS-B` items 5 and 6); a queue for URLs arriving before a receiver exists is not kept
  (`AS-Q`; additive). Owner none.
- Human checks AS1–AS10; owner: a human with an unlocked Mac and a Linux and a Windows machine.

## §11 Merge with master (2026-10-09, `2155f1e`, controls and looks)

`git fetch` found `origin/master` at `2155f1e` (39 commits past `c62d6ba`: `feat/controls-looks`,
record §85, and the clip-nesting fix). No record numbered 87 exists on master (`85`, `86`), so this
record keeps its number. Conflicts: `docs/divergences.md` (master's 165–171 and this branch's
175–176, both kept, master's first), `docs/verification/human-checks.md` (groups AS and CL, both
kept), `docs/probes/closeout-public-api.tsv` (re-generated by `closeout-public-api.sh`). No source
conflict. Counts after the merge are in §12.

## §12 Counts

| Where | Tests | Goldens | Guards | Notes |
| --- | --- | --- | --- | --- |
| `c62d6ba` (baseline) | 2873 | 0 | 185 | |
| lane 1 (`3356851`) | 2886 | 0 | 187 | +13: the 11 of `AppKitAppShellTests` and guards 1.1, 1.2 |
| lane 2 (`d3da951`) | 2918 | 0 | 188 | +32: 19 + 6 + 6 and guard 2.1 (2.23b and 2.25b are the review's) |
| lane 3 (`cfc7e00`) | 2921 | 0 | 188 | +3 (`AppShellDemoTests`); the arm 3.5 is inside an existing test |
| **merge with `2155f1e`** | **3069** | **0** | **195** | master's 3021 + 48; guards 192 + 3 |

The merge's native run (`swift package clean`, `swift build --build-system native --build-tests`,
unfiltered `swift test --build-system native --no-parallel`, 568 s) printed one summary line,
"Test run with 3069 tests in 3 suites failed after 568.215 seconds with 5 issues": exactly the five
`AppKitPresentationTests` sheet tests of §9, which fail identically on a locked screen at
`c62d6ba`. `FR-J no-argument frame: succeeded=true` present; 0 `error:`; the only `warning:` is
SwiftPM's `--build-system native` deprecation notice; `swift build --build-tests` after the clean
build above printed 0 warnings. The guard count is the number of `canTypecheck(module:` gates in
`Tests` (194 on `2155f1e`, 197 here: +3, 1.1, 1.2 and 2.1) added to master's recorded 192.

`Backends/SDL` on macOS (`swift test $(python3 scripts/fetch-accesskit.py --print-flags)`): **24 + 108
passed**. CI's Linux image (`docker build -t metalui-portable …`, the `metalui-sdl-build-app-shell`
volume): **24 + 105 passed**, the app shell tests running ungated under the offscreen driver.
Census: `closeout-public-api.sh` re-recorded, **3021** declarations (master 2977, +44);
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. Divergences 175, 176
added; the header's live count and next label are left for the merge to settle (this branch's
reserved range is 175–184). Human checks group AS (AS1–AS10) owed.
