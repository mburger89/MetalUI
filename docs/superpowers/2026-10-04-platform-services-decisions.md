# Platform services — decisions

Rulings for file dialogs, alerts, window sizing, hover, `Divider` as a view and
the menu `Picker` (user request 2026-10-02, an item of the gpui-gap priority
list — the SMK configurator port's gaps 4, 5, 7, 8, 9, 10 and 12; **not a plan
task**). Spec:
[`specs/2026-10-04-platform-services-design.md`](specs/2026-10-04-platform-services-design.md).
Record: `../record/77-platform-services.md`. Evidence (all new,
outputs and readings in their headers):
[`../probes/swiftui-platform-services.swift`](../probes/swiftui-platform-services.swift)
(arm ids `D…` the importer, `X…` the exporter, `A…`/`C1` alerts and the
confirmation dialog, `H…` hover — **a recorded broken instrument**, `V…`
`Divider`, `P…` the menu picker; run twice, 163 lines byte-identical),
[`../probes/swiftui-window-sizing.swift`](../probes/swiftui-window-sizing.swift)
(arms `W0`…`W5`, one build per arm, run twice from clean defaults) and
[`../probes/swift-main-queue-drain-nested.swift`](../probes/swift-main-queue-drain-nested.swift)
(arms `J0`…`J3`, macOS and `swift:6.4-noble`; it extends
`swift-main-actor-task-loop.swift`'s `B1`/`B2`, whose Linux lines it
reproduced), and — added by the critic pass —
[`../probes/swiftui-alert-presenting.swift`](../probes/swiftui-alert-presenting.swift)
(arms `R0`…`R4` `presenting:`, `K0`…`K3` the Return key; run twice, 38 lines
byte-identical). The critic pass's corrections are `SV-X`…`SV-AD`; where they
refute a line above, that line is corrected in place and names them. Where SwiftUI has no answer (Linux and Windows, an async platform
call, hover — unmeasurable headless) the ruling says so and names gpui's
approach as the comparison, not as evidence.

Prefix **`SV-`**, lettered. **Next unused: `SV-AJ`.** (This line moves in the
commit that appends a ruling; read the last `## SV-` heading.)

Branch `feat/platform-services` from `c2b8f48` (master: lifecycle merged, PR
#46). Baseline at `c2b8f48`, re-taken by the design session: spec §0.
`docs/divergences.md` lines 4 and 12: **92 live, next label 126** (CLAUDE.md's
"70 live, next label 104" is stale; the file is the authority).

**Carried items.** `MN-C` (a native menu or "draw it yourself" through one
defaultless `Bool` requirement; a choice comes back as a queued
`InputEvent`, never re-entrantly) — the shape `SV-B` copies for dialogs and
alerts. `MN-F` (the window-owned in-window menu panel: no id, no `StateTable`
entry, painted after everything) — the shape `SV-J`'s drawn alert copies, and
the panel `SV-Q` makes scroll. `MN-H` item 3 (`Divider` is menu-only, "the
enclosing stack's axis … MetalUI's environment does not carry") — amended by
`SV-O`. `MN-Q` (one new `Handlers` member plus one proposal wrapper per
attachment) — the shape `SV-N` copies for hover. `DD-V`/`DD-AB` item 7 and
divergence 81 (`.menu` not offered; the picker scope finds options during
layout) — amended by `SV-P`. `LC-B`/`LC-C`/`LC-U` (a transparent scope keyed by
position and depth; a registry outside `StateTable`) — the shape `SV-K`
copies. `LC-E` (actions after the build, outside every phase, under
`StateDispatch`) — where `SV-K` and `SV-N` run their callbacks. `LC-L` (`.task`
deferred because the SDL loop starves main-actor tasks; owner: the plan's gap
10) — `SV-H` is that owner. `IX-D`/`DN-E`/`DN-F` (the one ranking,
`topmostHitbox(in:at:where:)`; arena membership by identity and layer) — the
rule `SV-N` reuses. `GX-I`/`GX-P` (hitboxes follow render effects;
`Hitbox.contains` is the one region test) — inherited by `SV-N` unchanged.
`EV-AB`/`AB-R`/`DN-C`/`MN-C`/`AI-B`/`MV-F` (a new platform requirement has no
default) — `SV-B`. `AI-N` is not triggered (no resource lookup). Window.swift's
`lastMousePosition` doc ("deliberately sticky … a future task adding a real
`mouseExited`-driven feature … can add the case") — `SV-N` item 7 is that task.

---

## SV-A — Scope: what this branch builds, what it defers

**Ruling.** Build, SwiftUI-spelled where SwiftUI has a spelling, probe-backed,
on AppKit **and** SDL (Linux, Windows; SDL on macOS too):

1. **File dialogs** — `.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)`,
   its single-URL overload, `.fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)`
   (`SV-C`); a MetalUI-only async call usable from a `Button` action,
   `FileDialogs.openFiles(…)`/`saveFile(…)` (`SV-D`); `ContentType` filename
   extensions and `.json` (`SV-E`); AppKit sheets (`SV-F`), SDL's async dialogs
   with the thread hop (`SV-G`); the SDL main-queue drain (`SV-H`, gap 10).
2. **Alerts** — `.alert(_:isPresented:actions:message:)`, the `presenting:`
   form, `.confirmationDialog(_:isPresented:actions:message:)` (`SV-I`):
   native `NSAlert` sheets on AppKit, a drawn window-owned alert elsewhere
   (`SV-J`), through one transparent presentation scope (`SV-K`).
3. **Window sizing** — `minSize`/`maxSize` and `WindowResizability`
   (`.automatic`, `.contentMinSize`, `.contentSize`) on `Window` and
   `App.openWindow` (`SV-L`, `SV-M`).
4. **Hover** — `.onHover(perform:)` and `.onContinuousHover(perform:)` from
   input through the one ranking, plus `InputEvent.pointerExited` (`SV-N`).
5. **`Divider()` as a view** in `HStack`/`VStack`/`Row`/`Column`, menus
   unchanged (`SV-O`).
6. **`.pickerStyle(.menu)`** over the native/in-window menu machinery
   (`SV-P`), with a scrolling in-window menu for hundreds of options
   (`SV-Q`).
7. Two accessibility roles, `.popUpButton` and `.alert` (`SV-S`); a services
   demo and human-checks group U (`SV-T`).

**Deferred** (`SV-W`, spec §11): clipboard beyond text (`SV-R`), `.task`,
`fileExporter(document:)`/`FileDocument`, folder selection, `fileMover`,
dialog-customisation modifiers, alert text fields, `confirmationDialog`'s
`titleVisibility:`, type-select in the drawn menu, the pop-up placement of the
drawn picker menu, other hover coordinate spaces.

**Cost if wrong.** Scope only; every item is independently removable.

---

## SV-B — The platform seam: four defaultless requirements, three input cases

**Ruling.**

1. `PlatformWindow` gains, **each with no default implementation**
   (`AB-R`/`EV-AB`/`DN-C`/`MN-C`'s reason — a conformer that forgets one fails
   to compile rather than silently never showing a dialog):
   - `func presentFileDialog(_ dialog: PlatformFileDialog) -> Bool` — `true`:
     the platform shows it and will answer with
     `InputEvent.fileDialogResult`; `false`: it cannot (the caller completes
     with `FileDialogError.unavailable`).
   - `func presentAlert(_ alert: PlatformAlert) -> Bool` — `true`: shown
     natively, answered with `InputEvent.alertResult`; `false`: "draw it
     yourself" (`SV-J`), `presentMenu`'s contract.
   - `func dismissPresentation(token: Int)` — ends the dialog or alert
     `token` names without an answer; a platform that cannot (SDL's file
     dialogs) does nothing, and `Window` ignores the late answer (`SV-G`
     item 5).
   - `func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?)`
     — `SV-M`.
2. `InputEvent` gains `.pointerExited` (the pointer left the window, `SV-N`
   item 7), `.fileDialogResult(FileDialogResultEvent)` and
   `.alertResult(AlertResultEvent)`. A result is **queued** by the platform and
   delivered after the presenting call returned, never inside it (`MN-C` item
   4's reason: `Window`'s dispatch is not re-entrant).
3. Seam types live in a new `Sources/MetalUIPlatform/Presentations.swift`,
   Foundation-free (`MetalUIPlatform` imports only `MetalUICore` and
   `MetalUIScene`): paths are file-system path `String`s; `MetalUI` turns them
   into `URL`s.
4. **Every conformer implements all four honestly**: `AppKitWindow`
   (`SV-F`, `SV-J`, `SV-M`), `SDLWindow` (`SV-G`, `SV-J` — `presentAlert`
   answers `false`, `SV-M`), `FakePlatformWindow` (records every call; the two
   `Bool`s are settable, `presentFileDialog` default `true`, `presentAlert`
   default `false`, as `presentMenu`'s), `SDLLifecycleTests`' fake, and every
   compile-guard conformer fixture (7 files; their positive controls stop
   compiling the moment a requirement lands — the lane re-greens each by adding
   the four members, which is the check that the guards still test what they
   name).
5. **Migration**: a conformer outside this repository adds
   `func presentFileDialog(_: PlatformFileDialog) -> Bool { false }`,
   `func presentAlert(_: PlatformAlert) -> Bool { false }`,
   `func dismissPresentation(token: Int) {}` and
   `func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}`;
   a `switch` over `InputEvent` outside this package adds the three cases or a
   `default:`. Three new cases and new stored types crossing the
   `MetalUIPlatform` → `MetalUI` boundary: `swift package clean` before the
   first measured run (CLAUDE.md).

**Reasoning.** One seam for every presentation keeps `Window` the single place
that owns state, `StateDispatch` and the input order; the platform shows,
answers and forgets. `MN-C`'s `Bool` lets one `Window` path serve a native
platform and one that draws.

**Cost if wrong.** A requirement too many is one external conformer's
one-line stub; a missing one is a silent no-op — the asymmetry the precedent
rulings chose.

---

## SV-C — File dialogs: SwiftUI's modifier subset and its semantics

**Ruling.**

1. **Offered** (macOS 14 SDK spellings, on `ElementGroup`, returning a
   transparent `PresentationScope<Self>`, `SV-K`):
   - `fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [ContentType], allowsMultipleSelection: Bool, onCompletion: @escaping (Result<[URL], Error>) -> Void)`
   - `fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [ContentType], onCompletion: @escaping (Result<URL, Error>) -> Void)`
   - `fileExporter<T: Transferable>(isPresented: Binding<Bool>, item: T?, contentTypes: [ContentType] = [], defaultFilename: String? = nil, onCompletion: @escaping (Result<URL, Error>) -> Void, onCancellation: @escaping () -> Void = {})`
   `ContentType` is MetalUI's (`DN-B`), not `UTType`; `Transferable` is
   MetalUI's synchronous one (`DN-S`). A file importing both MetalUI and
   UniformTypeIdentifiers spells `[ContentType.json]` where `.json` is
   ambiguous.
2. **Presentation.** `isPresented` turning `true` presents after the frame
   (`SV-K`); a modifier whose dialog is up is not presented again (`D5`).
   Open: files only, `allowsMultipleSelection` as declared, the types as the
   filter (`D1`, `D4`). Save: the name field is `defaultFilename` (extension
   hidden), the filter `contentTypes`, prompt and title "Export" (`X1`, `X4`).
   An exporter with `item == nil` still presents (`X5`).
3. **Outcomes**, each delivered from input under `StateDispatch` to the
   declaring element, **`isPresented` written `false` first**, then the
   callback:
   - importer chosen → `onCompletion(.success(urls))` (file URLs from the
     platform's paths; the single-URL overload passes the first);
   - importer cancelled → **no callback**, `isPresented = false` (`D2`, `D4`);
   - exporter chosen → MetalUI writes the bytes (item 4) atomically to the
     URL, then `onCompletion(.success(url))`, or `.failure(error)` when the
     write throws or `item` is `nil` (`FileExportError.noItem`);
   - exporter cancelled → `onCancellation()`, `isPresented = false` (`X3`,
     `X4`);
   - the platform failed (`.failed(message)`) or cannot show one (`false`)
     → `onCompletion(.failure(FileDialogError.platform(message)/.unavailable))`,
     `isPresented = false`;
   - `isPresented` set `false` while shown → `dismissPresentation(token:)`, no
     callback (`D3`).
4. **The exported bytes**: `item.exported(as: t)` for the first of
   `item.exportedContentTypes()` that conforms to the chosen content type `t`
   (`contentTypes.first`, or the item's first exported type when
   `contentTypes` is empty); when none conforms, the bytes of the item's
   **first** exported representation. A `Data` exported as `.json` therefore
   writes the data (the configurator's case: `JSONEncoder` output). The
   type names the file; the item supplies the bytes.

**Evidence.** `D1`–`D5`, `X1`, `X3`–`X5`. Completing a dialog headlessly is a
broken instrument (`NSSavePanel.ok(_:)` raises "not implemented" — the panel is
out of process), so **what SwiftUI writes for a save (item 4) and what it
passes on an importer's success are unmeasured**: item 4 is MetalUI's rule,
chosen so the port's `Data` + `.json` export works.

**Cost if wrong.** If SwiftUI refuses a non-conforming representation, item 4
writes a file SwiftUI would not; the app chose both the bytes and the type.

---

## SV-D — The async call: `FileDialogs`, from the environment and from `Window`

**Ruling.**

1. MetalUI-only (SwiftUI has no async file-panel call; the comparison is
   gpui's `cx.prompt_for_paths(PathPromptOptions)` / `prompt_for_new_path`,
   each a future of the chosen paths):
   ```swift
   public struct FileDialogs {
       public func openFiles(allowedContentTypes: [ContentType], allowsMultipleSelection: Bool = false) async throws -> [URL]
       public func saveFile(contentTypes: [ContentType] = [], defaultFilename: String? = nil) async throws -> URL?
   }
   extension EnvironmentValues { public internal(set) var fileDialogs: FileDialogs }  // stamped by Window
   extension Window { public var fileDialogs: FileDialogs }
   ```
   The environment entry serves a `Button` action (`@Environment(\.fileDialogs)
   var dialogs` … `Task { let urls = try await dialogs.openFiles(…) }`); the
   `Window` property serves a menu-bar command, which runs outside any view.
2. Cancellation returns `[]` / `nil` — **not** an error (gpui's `None`).
   `FileDialogError`: `.noWindow` (an unbound environment's default, or the
   window is gone — the struct holds the window **weakly**, so a captured
   value never retains it: CLAUDE.md's `.onClick { window.x() }` cycle),
   `.unavailable` (the platform answered `false`), `.busy` (a dialog or alert
   is already up in that window — one at a time, as AppKit's one sheet),
   `.platform(String)` (the platform reported a failure).
3. **Cancelling the awaiting task** dismisses the dialog
   (`dismissPresentation`) and throws `CancellationError`, so a test that
   abandons an await does not hang (spec §6.2's bounded pattern).
4. `fileDialogs` is `public internal(set)`, stamped by `Window`/`Frame` like
   `displayScale` (CLAUDE.md "Environment"), never sourced from
   `Window.environment`.

**Reasoning.** The configurator's ~10 import/export sites are buttons and menu
commands; an `await` keeps each one a few lines. The modifiers (`SV-C`) remain
the SwiftUI spelling.

**Cost if wrong.** A naming choice on a MetalUI-only type.

---

## SV-E — `ContentType` gains filename extensions and `.json`

**Ruling.** `ContentType.init(_:conformingTo:filenameExtensions: [String] = [])`,
`public var preferredFilenameExtension: String?` (UTType's spelling; the first
extension), a stored `filenameExtensions` (internal), and new statics `.json`
(`public.json`, conforming to `.text`, `["json"]`); `.plainText` gains `["txt"]`
and `.utf8PlainText` inherits nothing (its own list is empty). The seam carries
`PlatformFileType(identifier:conformsTo:filenameExtensions:)`.

**Mapping.** AppKit: `UTType(identifier)` when the system knows it, else
`UTType(filenameExtension:conformingTo: .data)` from the first extension; a
list containing `.data` or `.item`, or one resolving to nothing, allows every
file (`allowedContentTypes = []`). SDL: one `SDL_DialogFileFilter` per type
with extensions (`name` = identifier, `pattern` = extensions joined by `;`);
a type with no extensions contributes no filter, and a list with no filter
passes `NULL` (every file) — **divergence 129**: off Apple a type is matched
by extension only (`.text` filters nothing).

**Cost if wrong.** A new stored property on a public struct crossing a module
boundary: `swift package clean`; drag and drop's matching (`conformance`) is
untouched.

---

## SV-F — AppKit: open and save panels are sheets on the window

**Ruling.** `AppKitWindow.presentFileDialog` builds an `NSOpenPanel`
(`canChooseFiles = true`, `canChooseDirectories = false`,
`allowsMultipleSelection`, `allowedContentTypes`) or an `NSSavePanel`
(`nameFieldStringValue`, `allowedContentTypes`, `isExtensionHidden = true`,
`prompt`/`title` from the seam) and calls `beginSheetModal(for:)` — a sheet,
not app-modal (`D1`: `attachedSheet=NSOpenPanel modalWindow=nil isSheet=true`;
`X1` the same for the save panel). Its completion handler queues
`.fileDialogResult` with `RunLoop.main.perform` (`MN-C` item 4). Answers
`false` when the window already has an attached sheet.
`dismissPresentation(token:)` ends the sheet (`endSheet(_:returnCode:
.abort)`) and suppresses that answer.

**Cost if wrong.** A look (human check U1).

---

## SV-G — SDL: async dialogs, a callback on any thread, a wake event

**Ruling.**

1. `SDLWindow.presentFileDialog` calls `SDL_ShowOpenFileDialog` /
   `SDL_ShowSaveFileDialog` (since SDL 3.2; `allow_many`; `default_location` =
   `defaultFilename` for a save, else `NULL`) with the window as parent and
   answers `true` — failures arrive through the callback (`filelist == NULL`
   → `.failed(SDL_GetError())`, empty → `.cancelled`).
2. **The thread hop is C's, not Swift's.** SDL's callback "may be invoked
   from a different thread" (SDL_dialog.h). `SDLBridge` copies the filters
   onto the heap (SDL requires them valid until the callback) and frees them
   in the callback; the callback copies the paths into a mutex-guarded result
   queue keyed by token and calls `SDL_PushEvent` with a new
   `MUI_EVENT_DIALOG` (thread-safe, `mui_wake_for_accessibility`'s
   precedent). The main thread's `dispatch` takes the result
   (`mui_take_dialog_result`) and calls `onInput(.fileDialogResult)`. No Swift
   closure crosses the C callback; no main-queue hop is needed to *deliver*
   the result.
3. A bridge test hook, `mui_test_complete_dialog(token, paths, count)`, runs
   the **same** callback from a new thread (`SDL_CreateThread`), so the thread
   hop is tested without a real dialog.
4. **In CI's Linux image** the real-call test runs, gated `.enabled(if:)` on
   `SDL_GetCurrentVideoDriver() == "offscreen"`; **what it asserts is measured
   there first, not assumed** (`SV-AB`: SDL's Linux dialogs go through the XDG
   portal or zenity, not the video driver, so "offscreen cannot show one" was
   an unmeasured reason); no test shows a real dialog on macOS or a desktop (it
   would wait for a human).
5. `dismissPresentation(token:)` cannot close an SDL dialog (SDL3 has no
   call); `Window` forgets the token, so the eventual answer runs nothing.
   Recorded in the spec's deferred table, owner none.

**gpui comparison.** gpui's Linux backend uses the XDG desktop portal and
delivers on its own executor; SDL3 does the same internally (portal, zenity
fallback), so the bridge only owns the hop.

**Cost if wrong.** If a backend calls back synchronously (Windows' modal
dialog on the main thread), the push lands before `presentFileDialog` returns
and is delivered next pump — still never re-entrant.

---

## SV-H — The SDL main-queue drain (gap 10), measured where it can work

**Ruling.**

1. `SDLPlatform.run(maxIterations:)` runs
   `RunLoop.main.run(mode: .default, before: .distantPast)` once per
   iteration, after dispatching events and before ticking (`B2`: a main-actor
   `Task` then runs, macOS and Linux). Nothing else in the loop changes.
2. **It works only outside a main-actor job** (`J1`, both OSes: inside a job
   the drain starves the task; `J3`: so does the AppKit platform's run-loop
   shape). Every MetalUI `main.swift` calls `app.run()` from synchronous
   top-level code (the scaffold's generated mains, both demos), the shape
   `B2` measured. **Documented** (`docs/getting-started.md`, `App.run()`'s
   doc comment): call `App.run()` from synchronous top-level code, not from an
   `async` main — on either platform, by `J1` and `J3`.
3. **The test runs the loop in a process of its own**: a new executable target
   in `Backends/SDL`, `MainQueueDrainCheck`, top-level code opening a hidden
   `SDLPlatform` window, creating a main-actor `Task`, and running the loop
   for a bounded number of iterations; mode `task` prints whether it ran and
   resumed after a yield; mode `dialog` awaits `window.fileDialogs.openFiles`
   on an `App` over `SDLPlatform` and completes it through the test hook from
   another thread (`SV-G` item 3), printing the paths. `SDLMainQueueDrainTests`
   launch it (`Process`, found beside the test product in the build
   directory — its absence fails, never skips) and assert the output. A
   Swift Testing test cannot run the loop itself: it is a main-actor job
   (`J1`).
4. The latency of main-queue work enqueued **from another thread** while every
   display link is paused is up to the loop's 250 ms `mui_wait_event` timeout;
   work enqueued from input (a `Task` in a button action) runs in the same
   iteration. Measured as a count of iterations, not wall clock.
5. `.task` stays deferred (`LC-L`); this branch removes its blocker. Owner:
   none named (a lifecycle follow-up).

**Cost if wrong.** If a platform's pump already drains the queue (SDL's Cocoa
pump on macOS may), the extra pass is a no-op there; the Linux container is
the separating run (spec §6.1 test 1.18's recorded mutation).

---

## SV-I — Alerts: SwiftUI's spellings, a closed actions builder, SwiftUI's buttons

**Ruling.**

1. **Offered** on `ElementGroup`, returning `PresentationScope<Self>`:
   - `alert<A: AlertActions>(_ title: String, isPresented: Binding<Bool>, @AlertActionsBuilder actions: () -> A)` and with `message: () -> Text`;
   - `alert<T>(_ title: String, isPresented: Binding<Bool>, presenting data: T?, @AlertActionsBuilder actions: (T) -> A, message: (T) -> Text)` (and without `message:`) — presented whenever `isPresented` is `true`; a `nil` `data` presents the title and one "OK" with no message (**`SV-Y`**, which refutes this line's first draft, "shown only while `data` is non-`nil`");
   - `confirmationDialog(_ title: String, isPresented: Binding<Bool>, @AlertActionsBuilder actions: () -> A)` and with `message:` — the same presentation (`C1` = `A1`).
   `titleVisibility:` is **not offered** (only `.visible` was measured; a call
   site passing it does not compile — "Not offered" row).
2. **`AlertActions` is closed** (one SPI requirement, `MenuContent`'s
   precedent): `Button where Label == Text` (its title, `role`, action — the
   role, stored and "read by nothing" since `IX-E`, is now read here; record
   §05's row amends), `if`/`if-else`/`for` through `@AlertActionsBuilder`.
   A `TextField` in an alert is not offered (deferred).
3. **The buttons** — a pure resolver, `AlertButtons.resolve(_:)`, shared by
   AppKit and the drawn alert, from `A1`–`A5`, `C1`:
   - no actions → one "OK", the default (`A3`);
   - order: the non-cancel buttons in declaration order, then the cancel
     button (declared anywhere, `A4`) last;
   - a destructive button with no cancel button gets a synthesized "Cancel"
     (`A5`); plain buttons only get none (`A2`);
   - **Escape** presses the cancel button (declared or synthesized), else
     nothing (`A1`/`A6`, `A5`, `A2`, `A3`);
   - **Return** presses the first plain (role-less) declared button when no
     declared button is destructive; otherwise, and for the synthesized "OK",
     nothing (**`SV-X`**: `A2`/`K0`, `K3` get `"\r"`; `A1`/`A7`, `A5`/`K1`,
     `A3`/`K2` get none and Return runs nothing — the first draft's "first
     button neither cancel nor destructive" is refuted by `A5`);
   - a destructive button is marked (`hasDestructiveAction`).
4. **Outcomes** — any button: `isPresented = false` first, then its action,
   under `StateDispatch` to the declaring element (`A8`; a synthesized button
   runs nothing); `isPresented` set `false` while shown dismisses, no action
   (`A9`). Actions and message are evaluated **at presentation**, not
   re-evaluated while shown (`MN-D` item 4's footing: content is data at open).

**Cost if wrong.** A button rule is one row of the resolver's table test.

---

## SV-J — Native `NSAlert` on AppKit, a drawn alert everywhere else

**Ruling.**

1. **AppKit answers `true`**: an `NSAlert` (`messageText` = title,
   `informativeText` = message) with buttons added in the resolver's order
   (NSAlert lays two side by side with the first on the right and stacks three
   or more top-down — matching `A1`'s Cancel-left and `A5`'s Save-top), key
   equivalents set explicitly (`"\r"` on the default, `"\u{1b}"` on the
   cancel, `""` otherwise — NSAlert's own default would give the first button
   Return, which `A1` refutes), `hasDestructiveAction`, and
   `beginSheetModal(for:)` (`_NSAlertPanel` attached sheet, `A1`). The
   completion queues `.alertResult(token, index)`.
2. **SDL answers `false`**: `SDL_ShowMessageBox` is blocking (a nested loop:
   no frames, no display link, no AccessKit updates while it is up) and fails
   under the offscreen driver; `MN-F`'s precedent draws in-window instead.
   **The drawn alert** is window-owned (no id in the app's tree, no
   `StateTable` entry, `theSevenRetentionSlotsAreMutuallyDistinct` unmoved),
   painted after everything else including the in-window menu (a menu open
   when an alert presents is dismissed): a scrim over the window
   (`.background` at 0.3 opacity), a `.surface` panel 260 wide, centred
   horizontally, 24 from the top (a sheet's place), radius 10, the default
   shadow; bold title, message, then the buttons — one or two side by side
   (the resolver's first on the trailing side), three or more stacked; 28-pt
   buttons, the default one `.accent` with `.background` text. Text through
   `Frame.textSystem` (`TS-A`). Constants in one file, `AlertPanel.swift`.
3. **It is modal**: while it is up it takes every pointer and key event first
   (ahead of the drag session and the menu), consuming them; Return/Escape per
   `SV-I` item 3; Tab, ←/→/↑/↓ move a focus ring among its buttons, Space
   presses the ringed one; a click on a button presses it; anything else is
   swallowed. The hover set is empty while it is up (`SV-N` item 6).
   `.menuAction`, results and `.pointerExited` still pass.
4. **Accessibility**: one `.alert` node (label = title, value = message),
   children `.button` nodes, focus on the ringed button; a `press` chooses
   (synthesized ids under a window-reserved name, `MN-F` item 4's footing).

**gpui comparison.** gpui's `window.prompt(level, message, detail, answers)`
is native where the platform has one and falls back to an in-window prompt
renderer (`set_prompt_builder`) where it does not — the same split.

**Cost if wrong.** If SDL's message box is wanted, `SDLWindow.presentAlert`
returns `true` and calls it — one function, no API move.

---

## SV-K — One transparent `PresentationScope`, reconciled after the frame

**Ruling.**

1. `PresentationScope<Content: ElementGroup>: ElementGroup` (typed copy
   `ProposalElementGroup where Content: ProposalElementGroup`) — **layout- and
   identity-transparent**, `LifecycleScope`'s shape (`LC-B` item 2): no node,
   no `ModifiedContent` layer, no cursor index, `Handlers` unchanged, no
   `Element` group-default hook (`MC-B` not triggered). A legacy `Self`-
   returning decoration after it does not compile, as after a lifecycle
   modifier — divergence 120's row gains the presentation modifiers.
2. **Registration** in layout, keyed as `LifecycleScope` keys
   (`.named("$presentation<depth>")` under `.child(of: parent, at: cursor)`,
   `LC-C`/`LC-U`'s depth): a record of the binding's current value, the
   owner (`parent`, for `StateDispatch`) and closures that build the
   `PlatformFileDialog`/`PlatformAlert` and run the outcome. Reads only — no
   write in a phase. A window-owned `PresentationRegistry` holds the records
   of the last build; never a `StateTable` entry.
3. **Reconcile after the frame** (after `drainLifecycle`, outside every phase,
   `LC-E`'s place): a record presented `true` with nothing in flight for its
   key → present (one in flight per window: a later one waits while the first
   is up, its `isPresented` still `true`); a key in flight whose record is
   gone or `false` → `dismissPresentation`. An outcome arrives as input and
   runs from input (`SV-C` item 3, `SV-I` item 4).
4. A headless `renderFrame` presents nothing (`MV-H`'s footing).

**Cost if wrong.** Internal to `Presentations.swift` and `Window`.

---

## SV-L — Window sizing: `minSize`, `maxSize`, `WindowResizability`

**Ruling.**

1. MetalUI's `App` is not a `Scene`, so SwiftUI's scene modifiers become
   window state:
   ```swift
   public struct WindowResizability: Sendable, Equatable {
       public static let automatic, contentSize, contentMinSize: WindowResizability
   }
   extension Window {
       public var minSize: Size<Pixels>?            // window points
       public var maxSize: Size<Pixels>?
       public var windowResizability: WindowResizability
   }
   // App.openWindow(title:size:minSize:maxSize:windowResizability:startsDisplayLink:content:)
   ```
   `size:` is already `defaultSize` (`W3`). The new parameters default to
   `nil`/`nil`/`.automatic`, so every existing call compiles and the scaffold's
   generated text is unchanged.
2. **`.contentMinSize`**: the minimum is the root's answer at a **zero**
   proposal; **`.contentSize`** adds the maximum, its answer at an
   **infinite** proposal (`W1`, `W2`: 400 × 300 and 900 × 600 for
   `frame(minWidth: 400, maxWidth: 900, minHeight: 300, maxHeight: 600)`), each
   measured once per drawn frame through the kernel's measure-only entry
   (`LayoutTree.measureNativeLayout`, made `package`) **before** the real
   layout, so `lastNativeLayoutWork` keeps the real run's work. The minimum
   follows the content (`W5`). **`.automatic` measures nothing.**
3. **Divergence 126**: SwiftUI's `.automatic` on macOS *is* `.contentMinSize`
   (`W0` = `W1`); MetalUI's asks the content nothing (changing it would grow
   every existing window whose content's minimum exceeds its size — the
   fourteen demo images among them). Also: SwiftUI's limits include the
   title-bar inset (+32 in `W0`–`W5`; full-size content), MetalUI's are the
   root's (it has no safe areas, `PB-A`).
4. **Effective limits** per axis: minimum = max(explicit, content), maximum =
   min(explicit, content), a maximum below the minimum raised to it.
   Negative values clamp to 0, an infinite maximum means none, NaN traps
   (`SA-J`'s rule; an exit test pins it). `Window` calls
   `setContentSizeLimits` only when the effective pair changes, and before the
   first frame when `openWindow` was given limits.

**Cost if wrong.** If `.automatic` should follow SwiftUI, it is one default —
measured cost is one extra kernel measurement per frame per window.

---

## SV-M — Window sizing on the platforms: limits, and resize into them

**Ruling.** `setContentSizeLimits(minimum:maximum:)` sets AppKit's
`contentMinSize`/`contentMaxSize` (`nil` → `.zero` /
`greatestFiniteMagnitude`) and SDL's `SDL_SetWindowMinimumSize` /
`SDL_SetWindowMaximumSize` (minimum rounded up, maximum down; `nil` → 0, SDL's
"no limit"). **Contract**: a window whose content size lies outside the new
limits is resized into them by the platform (AppKit `setContentSize` of the
clamped size — AppKit clamps a programmatic resize, `W0`; SDL clamps on its
own), and the resize reaches `Window` through `onResize`. Fakes record the
calls and apply the clamp to their `contentSize`.

**Cost if wrong.** A look (human check U9: dragging the window edge stops).

---

## SV-N — `onHover` and `onContinuousHover`: from input, through the one ranking

**Ruling.**

1. **Spelling**: `onHover(perform: @escaping (Bool) -> Void)` and
   `onContinuousHover(perform: @escaping (HoverPhase) -> Void)` with
   `public enum HoverPhase: Equatable { case active(Point<Pixels>), ended }`
   (local points — `DragGesture.Value`'s precedent for `Point<Pixels>`; the
   `coordinateSpace:` parameter is not offered, `.local` only). On both
   vocabularies by `MN-Q`'s shape: on a `StyledElement` it returns `Self`
   through one new `Handlers` member, `hover: HoverAttachment?` (seventeen
   members, `SV-AH` item 1 correcting this line's "sixteen" — `HandlerShape` and `HandlerFingerprint` each gain a field), no
   identity level; on the typed path a `HoverModifier<Self>` wrapper
   (`ContextualModifier`'s recipe: no node, one identity level for its caller
   only, the region at its own bounds).
2. **A hover region** is a **non-opaque** hitbox carrying only the attachment,
   registered by `Frame.registerHandlers` at the element's hit region (its
   content shape, as a draggable region's), after the element's own opaque
   hitbox so it ranks above it — inside the `allowsHitTesting` gate and the
   `.disabled` gate (unmeasured in SwiftUI; a disabled element is inert, as for
   every pointer ask), and inside `hidden()`. The D2 guard gains the arm. A
   tree with no hover attachment registers no extra hitbox (pinned). A hover
   region never blocks a click beneath it.
3. **The hovered set at a point `p`** — never a second lookup:
   `t = topmostHitbox(in:at: p, where: { $0.opaque || $0.handlers.hover != nil })`;
   the set is every hover region `h` with `h.layer == t.layer`,
   `h.contains(p)` (the one region test, so render effects and content shapes
   apply, `GX-I`) and `t.id` equal to or descending from `h.id` — the same
   membership rule as the gesture arena's ancestors (`IX-D`). Nothing under
   `p` → empty. A painted-only cover blocks nothing (divergence 114's rule);
   an opaque target or a higher layer (a `Deferred` presentation, `IX-Q`)
   covers hover beneath it.
4. **When it is recomputed**: on every pointer event (`mouseMoved`,
   `mouseDragged`, presses and releases), on `.pointerExited` (`p = nil`), and
   after every drawn frame against the new hitboxes (content moving, appearing
   or leaving under a still pointer). Callbacks run **from input** for the
   first three and **after the frame** (with `drainLifecycle`, `LC-E`) for the
   last; each under `StateDispatch.dispatching(to:)` its element.
5. **Order and departure**: leavings first, innermost first; then enterings,
   outermost first. An element that **leaves the tree** while hovered gets
   `onHover(false)` (and `.ended`) after the frame, through the closure of the
   last frame it was in — so a parent tracking "which key is hovered" never
   keeps a stale `true`. `onContinuousHover` gets `.active(local)` on every
   move inside, `local` = `Hitbox.localPoint(p) − origin`.
6. While an in-window menu (`MN-F`) or a drawn alert (`SV-J`) is up, the
   hovered set is empty.
7. **`.pointerExited`** (AppKit: the existing tracking area's `mouseExited`,
   `.mouseEnteredAndExited` already declared; SDL:
   `SDL_EVENT_WINDOW_MOUSE_LEAVE` → `MUI_EVENT_MOUSE_LEAVE`) clears
   `Window.lastMousePosition` — **amending its "deliberately sticky" decision**:
   `PaintPass.isHovered` reads `false` after the pointer leaves the window.
   No other paint-time query changes; `topmostOpaqueHitbox` and click
   dispatch are untouched.

**Evidence and comparison.** SwiftUI's hover is **unmeasured**: every `H` arm
read `[]` under both instruments (synthesized `mouseMoved` through
`NSWindow.sendEvent` and straight to the hosting view's `mouseMoved(with:)`),
including H1's plain enter/leave — a broken instrument in an inactive app, so
no rule here rests on SwiftUI. gpui's model is the comparison: a hitbox is
hovered when it is under the mouse at or above the topmost hitbox that blocks
the mouse (`HitboxBehavior::BlockMouse`), and `on_hover` fires on change.
Item 3 is **not** that rule: under item 3 a hover region is itself eligible,
so a sibling's hover region drawn above covers the one beneath, where gpui
would hover both — `SV-Z` rules it and pins it. Human check U8.

**Cost if wrong.** If SwiftUI fires a covered sibling or a disabled element,
item 3's eligibility or item 2's gate moves — one predicate each.

---

## SV-O — `Divider()` as a view: the nearest stack's cross axis

**Ruling** (amends `MN-H` item 3).

1. `Divider` (today a `MenuContent`) also conforms to `Element` and
   `ProposalElement`: a native leaf. Inside a menu builder it is still a
   separator; inside an element builder it is a line.
2. **Orientation** (`V1`–`V11`): vertical (1 wide) inside an `HStack` or
   legacy `Row`; horizontal (1 tall) inside a `VStack` or `Column` and
   **outside any stack** (`V3`, `V4`: a `ZStack` is no stack). The nearest of
   those decides (`V5`, `V6`); every other wrapper is transparent (`V8` frame,
   `V9` padding, `V11` group). Implementation: an internal axis stack on
   `Frame`, pushed by `HStack`/`VStack`/`Row`/`Column` around their children's
   layout request and by `ZStack` and `Grid` as "none", popped by `defer`;
   the `Divider` reads the top at its layout and carries the axis to paint in
   its layout state. A plain `Box` pushes nothing (its CSS-default
   `flexDirection` would make every internal row a stack).
3. **Size**: 1 point across (2 device pixels at 2×, `V12`); along, the
   proposal (`proposal ?? 10`, `V3`, `V7`) — greedy, so a `Divider` in an
   `HStack` makes the stack fill the proposed height (`V7`).
4. **Colour**: the theme's `.separator` token — **divergence 127**: SwiftUI's
   is black (light) / white (dark) at alpha 0.098 (`V12`, `V13`), MetalUI's
   theme separator is opaque (`0xC8CDD6` / `0x3A4260`), the menus' separator
   colour.
5. **Accessibility**: none (`V15`: SwiftUI publishes only the texts).

**Cost if wrong.** A look (human check U10) and one table of push sites.

---

## SV-P — `.pickerStyle(.menu)`: a pull-down showing the selection

**Ruling** (amends `DD-V` item 4, `DD-AB` item 7 and divergence 81).

1. `PickerStyle.menu` is offered. **`.automatic` stays segmented** —
   divergence 81 narrows to "the automatic `Picker` is segmented where
   SwiftUI's is a pop-up menu (`P0` = `P1`)"; the guard
   `aMenuPickerStyleIsNotOffered` is replaced by its positive
   (`aMenuPickerStyleCompiles`). **Migration**: none for callers.
2. **Look and layout** (`P1`–`P3`): the title, 8, a pull-down button 24 tall
   (`Menu`'s chrome, `MN-H` item 1, with the `⌄` indicator) whose label is the
   selected option's title and whose width is its **widest** option title's
   (`P1` 86 vs `P3` 102 — not stretched by a wider frame), measured once per
   change of the option titles, not per frame (`SV-AA`); a selection
   matching no tag shows an empty label (`P5`).
3. **Options are discovered without layout**: inside a `.menu` picker scope a
   `TaggedElement` records `(tag, title)` and lays out **nothing** through its
   group entry (one identity slot, no node), so a 300-option picker builds 300
   records, not 300 subtrees. Reached through the single-element entry (a
   modifier written after `.tag`) it registers one zero-size leaf. The title
   is the content's `Text` string; any other content is titled
   `String(describing: tag)` — **divergence 128** (SwiftUI draws the option's
   view in its menu).
4. **The menu at open**: a click, Space/Return when focused, or an
   accessibility press opens the options recorded by **the last frame's**
   layout (the scope is a class captured by the button's action, `DD-V`'s
   footing) as toggle items, the selected one on (`P1`: `state=on`), through
   `Window.openPullDownMenu` — `NSMenu` on AppKit (300 items in `P3`), the
   in-window panel elsewhere (`SV-Q`); choosing writes the tag (`P1`: pick=1).
   Placement below the button (the pull-down's, `MN-H`); SwiftUI's pop-up
   placement is unmeasured — deferred.
5. **Accessibility**: a new `.popUpButton` role (`SV-S`; `P0`–`P3`
   `AXPopUpButton`), value = the selected title, label = the picker's title
   through the partial fold (divergence 82's footing).
6. Disabled: `Button`'s one gate.

**Cost if wrong.** The look is human check U6; option discovery is internal to
`Picker.swift`.

---

## SV-Q — The in-window menu scrolls (amends `MN-F` items 1–3)

**Ruling.** A menu level taller than the window less two margins is clamped to
that height and **scrolls**: a per-level offset; a wheel over the level scrolls
it (today consumed and ignored); ↑/↓ moving the highlight scroll it into view;
only rows intersecting the visible band are painted and hit-tested (paint and
hit work O(visible), counted); a 12-pt band at a scrollable edge shows `▴`/`▾`.
A pull-down opened by a menu picker starts with the **selected row**
highlighted and scrolled into view. The accessibility node still lists every
row. Type-select is deferred.

**Cost if wrong.** A look (human check U7); constants in `MenuPanel.swift`.

---

## SV-R — Clipboard beyond text: deferred

**Ruling.** Not built. Images or arbitrary `ContentType` data need two more
defaultless requirements (typed read and write), an AppKit `NSPasteboard`
mapping and SDL3's MIME-typed clipboard, for a use the configurator does not
have (its clipboard is `TextField`/`TextEditor` text, which works). Owner:
the gpui-gap priority list — the Record phase adds a "typed clipboard" row
there (`SV-AD` item 4).

---

## SV-S — Two accessibility roles: `.popUpButton`, `.alert`

**Ruling.** `AccessibilityRole` gains `.popUpButton` (AppKit
`AXPopUpButton`, `P0`–`P3`; AccessKit's pop-up button role if the header has
one, else `COMBO_BOX` with `has_popup = MENU` — the lane reads
`accesskit.h` and records which) and `.alert` (AppKit `AXGroup` with
subrole `AXDialog` — never published on AppKit, whose alert is native;
AccessKit `ALERT_DIALOG`). Both bridges translate both (the bridges' exhaustive
role switches). New enum cases crossing a module boundary: `swift package
clean`.

---

## SV-T — Demo and human checks

**Ruling.** A new flag, `METALUI_SERVICES_DEMO=1` (`swift run MetalUIDemo`, and
the same flag in `MetalUISDLDemo`), showing `servicesDemoContent()` from a new
`Sources/MetalUIDemoContent/ServicesDemo.swift`, each section its own function
handed to a generic composer (the 1 MB stack rule): Import/Export buttons
(modifiers and the async call; the last result as text), a "Delete…" alert,
three hover tiles (colour and an enter counter as text and a bar), `Divider`s
in all four stacks, a 300-option menu picker; the window opened with
`minSize: 900 × 600`. Not in the default demo: the fourteen offscreen images
and `Expected.swift` do not move. **Human-checks group U** (spec §9).

---

## SV-U — Performance: counted, zero where unused

**Ruling.** Counted work, literals derived before the run (`SA-M`): hover
recompute visits each hitbox once per pointer event and once per frame **only
when the tree has a hover region** (0 otherwise); `.automatic` resizability
adds no measurement (`lastNativeLayoutWork` identical to a window without
sizing); a `.menu` picker's options cost one record each and no layout node;
the drawn menu paints O(visible rows). No wall clock.

---

## SV-V — Lanes: three, in order, with append-only shared registries

**Amended by `SV-AC`** (window sizing moves to lane 1, the drawn alert to lane
3; "source files disjoint" corrected — the lanes are sequential and three
files are shared, named there).

**Ruling.** Three lanes run one at a time in this worktree (spec §10):
**lane 1** the seam on every platform (`MetalUIPlatform`, `MetalUIAppKit`,
`Backends/SDL`, fakes and guard fixtures, the drain), **lane 2** `Window`-side
presentations, sizing and hover (`MetalUI` core files), **lane 3** `Divider`,
the menu picker, the scrolling panel, the demo and the docs. Their source files
are disjoint. Four registries are **append-only per lane** (each lane adds only
its own rows): `docs/divergences.md`, `docs/probes/closeout-inventory-map.tsv`,
`docs/probes/closeout-public-api.tsv` (re-recorded by each lane after its rows)
and `Tests/MetalUITests/ModifierTests.swift`/`OuterModifierMatrixTests.swift`
(lane 2 only). **Reasoning**: a new public declaration owes its row in the
change that introduces it (CLAUDE.md), so each lane must pass
`closeout-inventory-check.sh` at its own end; the lanes do not run
concurrently, so an append-only file cannot conflict.

---

## SV-W — Deferred, with owners

**Ruling.** Spec §11's table is the list; every item is owner none unless it
names one. None blocks the branch.

---

## SV-X — Return on an alert: the measured key equivalents (amends `SV-I` item 3)

**Ruling.** `AlertButtons.resolve` marks a **default** (the Return button) only
when the declared actions hold **no destructive button**: the first plain
(role-less) declared button. With a destructive button anywhere, and for the
synthesized "OK" of an empty action list, there is **no** default and Return
does nothing. Escape is unchanged (the cancel button, declared or synthesized).
AppKit sets exactly these key equivalents (`"\r"` on the default only); the
drawn alert accents only the default, so the `A1`, `A3` and `A5` shapes draw no
accented button.

**Evidence.** `swiftui-alert-presenting.swift` `K0`…`K3` (run twice,
byte-identical): Return runs the first plain button under both instruments when
it carries `"\r"` (`K0` = `A2`, three plain; `K3`, plain + cancel — a shape the
design's probe had not measured), and runs nothing for `K1` (= `A5`: Save
`key=""` although `defaultButtonCell` is Save) and `K2` (= `A3`: OK `key=""`).
`K0` is the positive control that separates the instrument: Return **is**
delivered with the sheet not key, so the first draft's reading ("Return reached
neither because the sheet is not key, unmeasured") was an untested "cannot",
and its rule ("Return presses the first button neither cancel nor destructive")
gave `A5`'s Save a Return SwiftUI does not give it.

**Consequences.** Spec test 2.20's table gains a `K3` row and its `A3`/`A5`
rows expect no default (a mutation "destructive does not suppress the default"
reddens `A5` only); 1.6 asserts `"\r"` on Save for `K3` and on nothing for
`A5`; 2.28 adds `A5`: Return nothing, Escape → the synthesized Cancel. Whether
an **active** app's key sheet routes Return to `defaultButtonCell` anyway is
human check U4 (added there); if it does, AppKit already behaves so natively
and only the drawn alert's rule moves — one resolver row.

---

## SV-Y — `alert(presenting:)` with `nil` data still presents (amends `SV-I` item 1)

**Ruling.** The `presenting:` forms present whenever `isPresented` is `true`.
With `data == nil` the alert shows the title, no message and one "OK" (the
empty-actions resolution, `SV-I` item 3); the `actions`/`message` closures are
not called. Data changing while the alert is up re-evaluates nothing (`SV-I`
item 4 — evaluated at presentation). "OK" writes `isPresented = false` and runs
nothing.

**Evidence.** `swiftui-alert-presenting.swift` `R0` (data `"k1"`: title,
message "Item k1.", "Delete k1"/"Cancel"; Delete runs `delete k1`) against `R1`
(a fresh window, `data` `nil`, `isPresented` `true`: a sheet with title only and
"OK"), `R2` (data arriving while up: still "OK"), `R3` (data back to `nil`:
still up), `R4` (OK: `isPresented=false`, nothing runs). The first draft's
"shown only while `data` is non-`nil`" — Apple's documentation's wording — was
not probed, and macOS 27 does otherwise.

**Consequences.** Spec test 2.24 becomes
`alertPresentingWithNilDataShowsTheTitleAndOK` (asserts the `R1` shape and that
the actions closure is not called; mutation: "ignore `data == nil`" no longer
applies — use "present nothing for `nil`", which reddens it) plus the data path
(data reaches the actions and message).

---

## SV-Z — A hover region covers the hover regions beneath it (amends `SV-N` item 3's comparison)

**Ruling.** `SV-N` item 3's predicate stands — `t` is the topmost hitbox that
is opaque **or carries a hover attachment** — and its consequence is ruled, not
left implicit: of two overlapping **siblings** that both declare `onHover`, only
the one ranked above (and its ancestors) is hovered; the one beneath reads
`false` while the pointer is over the overlap. A hover region never blocks a
click (click dispatch is still `topmostOpaqueHitbox`). The alternative — gpui's
"every hover region at or above the topmost blocker" — needs an index
comparison outside `topmostHitbox`, a second copy of the ranking (`DN-F`'s "do
not add a fourth copy of this rule"), so it is rejected. SwiftUI is unmeasured
(`H` is a broken instrument), so the rule is MetalUI's; human check U8 gains
"two overlapping hover tiles: only the top one highlights over the overlap".

**Consequences.** New spec test 2.57
`anOverlappingSiblingHoverRegionCoversTheOneBeneath` (`ZStack` of two
`onHover` boxes: over the overlap `[top true]` only; mutation: eligibility
`\.opaque` alone — the beneath one then reads `true`).

---

## SV-AA — A menu picker measures its option titles once per change (amends `SV-P` item 2)

**Ruling.** The button's width is the widest option title's measured width
plus chrome. The measurement goes through `Frame.textSystem` (`TS-A`) and is
**cached on the picker scope** keyed by the option titles (in order), the
resolved `FontKey` and `displayScale`; a frame whose key equals the last one
measures **no** title. The 300-option chooser is the configurator's common
case, and it has several on one screen — 300 text measurements per picker per
frame would be the frame's dominant cost while `SV-U` claims the options cost
one record each.

**Consequences.** New spec test 5.17
`aWarmMenuPickerFrameMeasuresNoOptionTitle` (counted through a counting
`TextSystem`: first frame 300 title measurements, the next frame 0, a frame
after one title changes 300 — literals derived before the run; mutation:
drop the cache key comparison).

---

## SV-AB — SDL's real dialog in the Linux image: measure the answer first (amends `SV-G` item 4)

**Ruling.** SDL3's Linux dialogs go through the XDG desktop portal (D-Bus) or
zenity, independent of the video driver, so "under the offscreen driver a
dialog cannot be shown" is not a reason. Lane 1 first runs the real call in
`Backends/SDL/linux/Dockerfile`'s image and records what arrives (expected:
`.failed` — the image has neither a session bus nor zenity; recorded either
way in the record, with `SDL_GetError()`'s text). Test 1.12 asserts the
recorded outcome, gated on the offscreen driver **and** on the absence of
`zenity` on `PATH` and of `DBUS_SESSION_BUS_ADDRESS` (so a developer's Linux
desktop running the suite with the offscreen driver never waits on a real
dialog). If the image's answer is no callback at all within the bounded pumps,
1.12 is rewritten to assert that and the ruling records it.

---

## SV-AC — Lanes rebalanced; shared files named (amends `SV-V`, spec §10)

**Ruling.** The design's lane 2 owned ~70 tests across five features (the
largest lane this repository has run as one agent); the other two ~24 and
~33. Rebalanced, still three lanes, still in order, one agent at a time:

- **Lane 1 — seam + window sizing**: everything `SV-V` gave it, plus `SV-L`'s
  `Window`/`App` side (`Window.minSize`/`maxSize`/`windowResizability`, the
  limit reconcile, `App.openWindow`'s three parameters, the content-limit
  measurement in `Frame.swift`, `LayoutTree.measureNativeLayout` → `package`)
  and tests 2.33–2.42 (`WindowSizingTests.swift`) and divergence 126.
- **Lane 2 — presentations + hover**: the registry, file dialogs, the alert
  spellings, resolver and native path, the drawn alert's **model only** (when
  `presentAlert` answers `false`, `Window` holds the resolved buttons and a
  `chooseAlertButton(_:)` entry point; nothing is drawn yet), hover; tests
  2.1–2.25, 2.43–2.57, the guards 2.G5–2.G11. 2.53 covers the menu half only.
- **Lane 3 — drawn alert + views + demo + docs**: `AlertPanel.swift` (paint,
  modal input stage, accessibility append) and tests 2.26–2.32 plus 2.53's
  alert half, then `Divider`, the menu picker, the scrolling panel, the demo,
  the docs. It owns `MenuPanel`/`MenuSession`, which the drawn alert's ordering
  rules (dismiss an open menu, paint after it) touch.

**Shared files** (the lanes are sequential, so a later lane edits a file an
earlier one committed; none is "disjoint"): `Window.swift` (lane 1 sizing,
lane 2 presentations/hover/`.pointerExited`, lane 3 the drawn alert's input
stage and paint call), `Frame.swift` (lane 1 content limits, lane 2 hover
region and stamp, lane 3 the axis stack), `docs/migration.md` and
`docs/api-overview.md` (each lane appends its own declarations' rows and
migration stubs in its own commits — a new requirement's migration note lands
with the requirement, lane 1). The append-only registries of `SV-V` are
unchanged. Estimated root-test additions: lane 1 ≈ 30 (+ the SDL package's),
lane 2 ≈ 47, lane 3 ≈ 43.

---

## SV-AD — Spec corrections found by the critic pass

**Ruling.**

1. **The design probe did not compile as committed**: a raw carriage return in
   `swiftui-platform-services.swift`'s READING block ended a `//` comment.
   Fixed (the text `"\r"`); re-run twice, both byte-identical to its OUTPUT
   block — the recorded lines stand. `swiftui-window-sizing.swift` `W0` and
   `W2` re-run twice each from clean defaults: byte-identical to their
   recorded lines.
2. **`FileDialogs` is `@MainActor`** (`public struct FileDialogs` holds a weak
   `Window`, a main-actor class; its two methods are main-actor `async`), as
   `Binding` is (divergence 78's footing). The external-module guard 2.G7 calls
   it from a `Task` in a `Button` action.
3. **"Not offered" row added** (lane 2, `docs/divergences.md`): an alert or
   confirmation dialog action whose `Button` label is not a `Text` (SwiftUI
   accepts any view there); pinned by 2.G6.
4. **Owners for the two deferrals the port can feel**: typed clipboard (`SV-R`)
   and `.task` (`SV-H` item 5) are owned by the gpui-gap priority list — the
   Record phase adds a row for each there. The rest of spec §11 stays owner
   none (none is a configurator gap).

---

## SV-AE — Lane 1's findings: what the seam and the platforms measured (amends `SV-B` item 4, `SV-G` item 4, `SV-H` items 3–4, `SV-J` item 1, `SV-L` item 4, `SV-S`)

**Ruling.** Each item was measured on lane 1's branch; where it refutes a line
above, that line stands corrected by this one.

1. **The real SDL dialog in CI's Linux image fails** (`SV-AB`, measured):
   `SDL_ShowOpenFileDialog` answers through its callback, at once, with `NULL`
   and `SDL_GetError()` = `File dialog driver unsupported (supported values for
   SDL_HINT_FILE_DIALOG_DRIVER are 'zenity' and 'portal')` — delivered as
   `.fileDialogResult(.failed(that text))` within the bounded pumps, two runs
   of two. Test 1.12 asserts `.failed` and prints the text.
2. **Main-queue latency on Linux is passes, not one pass** (corrects `SV-H`
   item 4's "runs in the same iteration"): in `swift:6.4-noble`, under the
   offscreen driver (a pass does almost no work), a main-actor task created
   before the loop ran and resumed after **36 and 133** passes in two runs, and
   a dialog answer resumed its awaiting task after **44** passes — and once
   not within the first draft's 400-pass bound, which read a working drain as
   broken; macOS took **2** and **5**. The drain works (1.18 and 1.19 green on
   both); its latency is a short wall-clock interval, not a pass count, so
   `MainQueueDrainCheck` bounds its loop at 200 000 passes and stops as soon as
   the task finishes. Nothing in a frame depends on it.
3. **`MainQueueDrainCheck`'s `dialog` mode awaits a raw continuation over
   `SDLWindow.onInput`** (amends `SV-H` item 3, which named
   `window.fileDialogs.openFiles` on an `App`): `FileDialogs` is lane 2's. The
   check depends on `MetalUISDL`, `SDLBridge`, `MetalUIPlatform` and
   `MetalUICore` only, and `SDLWindow.id` became `public` so the executable can
   name the window to the bridge's test hook. Lane 2 may switch the mode to
   `FileDialogs`; the thread hop and the drain it pins are the same.
4. **`NSAlert` re-derives its buttons' key equivalents when it lays itself out
   for the sheet** (amends `SV-J` item 1's mechanism, not its rule): a `"\r"`
   set on `K3`'s Save while adding the buttons read `""` once attached. The
   roles are applied after `beginSheetModal(for:)`; 1.6 asserts them on the
   attached alert.
5. **Ending an `NSSavePanel` sheet stops the main run loop it is called in**:
   an interposed `CFRunLoopStop` traced `-[NSSavePanel didEndPanelWithReturnCode:]`
   → `induceEventLoopIterationSoon` → `-[NSEvent _postAtStart:]` →
   `CFRunLoopStop(main)`. From a Swift Testing job that stop lands on the
   executor's outermost `CFRunLoopRun`, which returns, and the process exits 0
   with no summary line (measured: the run ended at the next test; record
   §61 §9's `NSApp.run` signal fix does not prevent it). The AppKit tests end
   every sheet inside a **nested** run (`inNestedRun`), where the stop ends
   only that run. Production is unaffected: under `-[NSApplication run]` the
   stop lands on AppKit's own nested event wait.
6. **Exactly one limits call before the first frame** (amends `SV-L` item 4):
   `App.openWindow` assigns its three sizing parameters through
   `Window.applySizing`, which reconciles once — assigning the properties one
   by one sent `(min, nil)` then `(min, max)`. Test 2.40 asserts one call.
7. **Conformers** (amends `SV-B` item 4): of the seven compile-guard files,
   five hold a `PlatformWindow` conformer and gained the four members
   (`ColorScheme`, `ControlState`, `DragAndDrop`, `Menu`, `Transaction`);
   `AppIcon` and `Commands` hold only `Platform` conformers and need nothing,
   as does `SDLLifecycleTests`' `RecordingSDLPlatform` (a `Platform`). Every
   positive control is green.
8. **AccessKit has no pop-up-button role** (`SV-S`, read from `accesskit.h`
   0.23.0): `.popUpButton` is `COMBO_BOX` with `has_popup = MENU`, `.alert` is
   `ALERT_DIALOG`.
9. **SDL details**: `presentFileDialog` answers `false` only for a token
   outside `Int32` (the bridge's event carries an `Int32`); the seam's
   `title`/`prompt` are not parameters of SDL3's two calls and are not shown;
   a window closed before its dialog answers frees the queued answer
   unseen. `Window.onFrameAdopted` (internal) is the test hook 2.39 reads the
   frame's recorded work through.

---

## SV-AF — Lane 1's mutation table (measured)

**Ruling.** Each mutation was applied to `feat/platform-services` after
`02aaa81` (the spelling below), the whole unfiltered suite run (root: `swift
test --build-system native --no-parallel`; `Backends/SDL`: `swift test
--skip-build --no-parallel` on macOS, the task's container recipe on Linux),
the source restored from a copy and `git status --short` read clean. Every
reddened test is named; the root baseline is **2453 tests**, `Backends/SDL`
**76** (macOS) and **73** (`swift:6.4-noble`).

| # | Mutation (site) | Reddened |
|---|---|---|
| MG1 | a `PlatformWindow` extension defaulting all four members (`Platform.swift`) | `aPlatformWindowWithoutPresentFileDialogDoesNotCompile`, `…WithoutPresentAlert…`, `…WithoutDismissPresentation…`, `…WithoutSetContentSizeLimits…` (each new guard red once) |
| M1.1 | `allowsMultipleSelection = false` (`AppKitPresentations.swift`) | `appKitOpenDialogIsASheetWithTheDeclaredTypes` |
| M1.2 | the name not copied | `appKitSaveDialogCarriesTheNameTypesAndExportPrompt` |
| M1.3 | the answer delivered inside the completion handler | `appKitCancelledDialogArrivesAsQueuedInput` |
| M1.4 | the `.abort` answer not suppressed | `appKitDismissPresentationEndsTheSheetAndAnswersNothing` |
| M1.5 | the attached-sheet check dropped from `presentFileDialog` | `appKitSecondDialogWhileASheetIsUpAnswersFalse` |
| M1.6 | the post-sheet key-equivalent loop removed (NSAlert's own) | `appKitAlertIsASheetWithSwiftUIsKeysAndOrder` |
| M1.7 | the response code reported for the index | `appKitAlertButtonReportsItsIndexAfterTheSheetEnds` |
| M1.8 | no resize into the limits | `appKitContentSizeLimitsReachTheWindowAndClampIt` |
| M1.9 | `mouseExited` calls `super` only | `appKitMouseExitedDeliversPointerExited` |
| M2.33 | measure under `.automatic` too (`Frame.computeRootLayout`) | `automaticResizabilityAsksTheContentNothing`, and five existing pins of the root's run: `aNativeRootIsCentredAtItsAnswer`, `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`, `aProposalTextInAStackIsShapedOncePerDistinctWidth`, `aZStackRootPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`, `fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal` |
| M2.34 | the change check dropped (`Window.reconcileContentSizeLimits`) | `explicitLimitsReachThePlatformOnlyWhenTheyChange`, `theContentMinimumFollowsTheContent` |
| M2.35 | the minimum measured at the window's proposal | `contentMinSizeIsTheRootsAnswerAtAZeroProposal` |
| M2.36 | no maximum measured | `contentSizeAddsTheRootsAnswerAtAnInfiniteProposal`, `explicitAndContentLimitsCombinePerAxis`, `limitsAreMeasuredBeforeTheRealLayout` |
| M2.37 | the first content answer cached | `theContentMinimumFollowsTheContent` |
| M2.38 | the explicit minimum ignored (`ContentSizeLimits.effective`) | `explicitAndContentLimitsCombinePerAxis`, `explicitLimitsReachThePlatformOnlyWhenTheyChange`, `negativeLimitsClampAndInfiniteMaximumMeansNone`, `openWindowAppliesLimitsBeforeTheFirstFrame` |
| M2.39 | the measurement moved after the real layout | `contentMinSizeIsTheRootsAnswerAtAZeroProposal`, `contentSizeAddsTheRootsAnswerAtAnInfiniteProposal`, `limitsAreMeasuredBeforeTheRealLayout` |
| M2.40 | `applySizing` deferred past the first `drawFrameIfNeeded` (`App.openWindow`) | `openWindowAppliesLimitsBeforeTheFirstFrame` |
| M2.41 | each value's clamp to 0 removed | **nothing** — a broken instrument or dead code: the minimum's 0 start and the raise of the maximum to it already clamp. The clamp was dead and is deleted (`ce632d1`); M2.41b below is the mutation of the live spelling |
| M2.41b | the minimum starting at `-infinity` | `negativeLimitsClampAndInfiniteMaximumMeansNone` |
| M2.42 | the NaN precondition removed | `aNaNLimitTraps` |
| M1.10 | `SDL_PushEvent` removed from the dialog callback (`SDLBridge.c`) | `sdlDialogResultFromAnotherThreadArrivesAsInput`, `sdlCancelledAndFailedDialogsMapTheirOutcomes`, `sdlDismissPresentationForgetsAndALateResultStillArrives`, `aDialogAnsweredOnAnotherThreadResumesAnAwaitingTask` (macOS) |
| M1.11 | cancel and failure swapped (`SDLWindow.deliverDialogResult`) | `sdlCancelledAndFailedDialogsMapTheirOutcomes` |
| M1.12 | `presentFileDialog` answers `false` without calling SDL (Linux image) | `sdlDialogInTheLinuxImageAnswersItsRecordedOutcome` |
| M1.13 | `"*"` for a type without extensions | `sdlFiltersCarryExtensionsAndATypeWithoutOneFiltersNothing` |
| M1.14 | `presentAlert` answers `true` | `sdlPresentAlertDeclines` |
| M1.15 | the minimum rounded down | `sdlContentSizeLimitsReachSDLAndClamp` |
| M1.16 | the `MOUSE_LEAVE` mapping removed (`translate`) | `sdlMouseLeaveDeliversPointerExited` |
| M1.15b | the original call order — the minimum, then the maximum, no lift first (`SDLBridge.c` `mui_window_set_size_limits`, after `9b2c32e`, spelled `bool lifted = true;`) | `sdlContentSizeLimitsApplyInEitherOrder` (macOS and `swift:6.4-noble`: the raised minimum reads `[100, 100, 1440, 400]`, and the `600.5` pair's minimum is refused too) |
| M1.15c | the maximum not raised to its rounded minimum (`SDLPlatform.setContentSizeLimits`' `atLeast` answering `high`) | `sdlContentSizeLimitsApplyInEitherOrder` |
| M2.42b | the `maxSize` NaN precondition removed (`Window.maxSize`) | `aNaNLimitTraps` (the new `maxSize` arm; before it the suite was green — the review's V8) |
| M2.43 | the frame's resize no longer re-raises the redraw (`drawFrameIfNeeded`'s `resizeCount` check removed) | `aResizeIntoContentLimitsOnALifecycleFrameOwesTheNextFrame` |
| M2.44 | the content maximum kept when the mode leaves `.contentSize` (`windowResizability`'s `didSet`) | `leavingContentSizeDropsTheContentMaximumAtOnce` |
| M1.18 | the drain removed (`SDLPlatform+MainQueue.swift`) | **Linux**: `theSDLLoopRunsAMainActorTaskStartedFromTopLevelCode` (`task ran=false resumed=false iterations=200000`), `aDialogAnsweredOnAnotherThreadResumesAnAwaitingTask` (`paths=[]`). **macOS: nothing** — SDL's Cocoa pump drains the main queue itself (`task … iterations=3`, `dialog … iterations=6`), recorded as `SV-H`'s "Cost if wrong" foresaw; the Linux container is the separating run |

1.17 and 1.20 owe no mutation (spec §6.1). M1.15b…M2.44 were added by the
lane's review fixes (`SV-AG`), applied after `9b2c32e`; root baseline then
**2455**, `Backends/SDL` **77** (macOS) and **74** (`swift:6.4-noble`).

## SV-AG — Lane 1's review fixes: SDL limit order, the `maxSize` NaN pin, a resize during a settle build, leaving `.contentSize` (amends `SV-M`, `SV-L` items 2 and 4)

**Ruling.** Four findings of lane 1's review, each red first and mutated
(`SV-AF` M1.15b…M2.44).

1. **SDL applies the limits whatever order they change in.** SDL refuses a
   minimum above the maximum still set ("Tried to set minimum size larger than
   maximum size"), and the bridge set the minimum first and discarded the
   answer — so raising the minimum past an old maximum (the configurator's
   1440-wide minimum after a smaller `maxSize`, or a content minimum growing,
   `W5`) kept the old minimum on Linux and Windows while AppKit and the fake
   read correctly. `mui_window_set_size_limits` now lifts the maximum
   (`SDL_SetWindowMaximumSize(w, 0, 0)`), sets the minimum, then the new
   maximum; `SDLWindow.setContentSizeLimits` raises a maximum that rounds below
   its minimum (one fractional value rounded up and down, `600.5` → 601/600)
   to it, 0 staying "no limit". Test **1.15b**
   `sdlContentSizeLimitsApplyInEitherOrder` (red at `214ff46` on macOS SDL:
   `[100, 100, 1440, 400]`); green on macOS and in `swift:6.4-noble`.
2. **`Window.maxSize`'s NaN trap is pinned**: `aNaNLimitTraps` gains a
   `maxSize` arm (the review's V8 removed the precondition and the suite stayed
   green).
3. **A resize that arrives during a frame's builds owes the next frame**
   (measured, confirming the review's inspection): a `.contentMinSize` root
   larger than the window, on a frame whose `onAppear` writes what the build
   read, resized the window inside the first build; the lifecycle's settle
   build's `needsRedraw = false` cleared that resize's dirt, so the frame
   encoded into a drawable taken before the resize was the last one drawn
   until other input arrived (`aResizeIntoContentLimitsOnALifecycleFrameOwesTheNextFrame`
   red at `214ff46`: no second present). `Window` counts `onResize` deliveries;
   `drawFrameIfNeeded` re-raises the redraw after its builds when the count
   moved since `beginFrame()`. The colour-scheme rebuild's clear is covered by
   the same check. A frame with no resize is unchanged (no extra
   `setNeedsRedraw`).
4. **Leaving `.contentSize` drops the content maximum at once**: the
   `windowResizability` setter clears the last frame's content maximum for
   every mode but `.contentSize`, so the switch to `.contentMinSize` reaches
   the platform without it rather than a frame later (red at `214ff46`: no
   call was made, the platform kept `900 × 600`).
   `leavingContentSizeDropsTheContentMaximumAtOnce`.

**Cost if wrong.** Item 3 raises at most one extra frame per resize that lands
inside a build; item 1's lift leaves the window momentarily without a maximum
between two SDL calls on the main thread, where no event can be delivered.

---

## SV-AH — Lane 2's findings: what presentations and hover measured (amends `SV-N` items 1–2, `SV-K` item 3, `SV-AC`, spec §6.2)

**Ruling.** Each item was found while implementing lane 2 at `9b51130`; where it
refutes a line above, that line stands corrected by this one.

1. **`hover` is `Handlers`' seventeenth member, not its sixteenth** (corrects
   `SV-N` item 1 and spec §4.2's "the sixteenth member"): `contextual` was the
   sixteenth (`MN-Q`). `Handlers` grows by one reference, 464 → 472 bytes; the
   two existing size pins move with a note —
   `handlersGainsOneReferenceMember` (`ContextMenuTests`, now `== 472`) and
   `theNewDeclarationsCostHandlersAtMostOnePointer` (its bound gains `+ 8`).
   `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`'s case count moves
   55 → 57 (the two hover modifiers' cases). All three reddened when the member
   landed and are fixes, not regressions.
2. **The pointer target's and the draggable region's handlers carry no hover
   attachment** (amends `SV-N` item 2): `Frame.registerHandlers` registers the
   opaque hitbox with the element's whole `Handlers`, so an element with both
   `.onClick` and `.onHover` had two hitboxes carrying the attachment and
   hovered twice (measured: `pointerExitedClearsHoverAndIsHovered` read
   `["t true", "t true", "t false", "t false"]`). The opaque and draggable
   inserts now pass the handlers with `hover` cleared; the hover region is the
   one hitbox carrying it, so "carries a hover attachment" is "is a hover
   region" — the predicate `SV-N` item 3 and `SV-Z` name. Click dispatch reads
   `onClick`, never `hover`, and no other reader of the opaque hitbox's
   handlers moves.
3. **Where the after-frame steps run** (`SV-K` item 3, `SV-N` item 4):
   `reconcilePresentations()` then `updateHover(at:reportsMoves: false)`, after
   the lifecycle's drain and settle build and the resize re-raise, before
   accessibility and `finishFrame` — presentations first, so a drawn alert
   presented on this frame empties the hovered set on the same frame. Their
   callbacks' writes schedule the next frame (no further settle build).
4. **The registry, the drawn-alert model and the async call share one "in
   flight" slot** (`SV-D` item 2, `SV-K` item 3): `PresentationRegistry.inFlight`
   is a scope's dialog or alert, or a `FileDialogs` call; a call while anything
   is up throws `.busy`, and a scope waits while a call is up. A window that
   deinitialises with a call awaiting resumes it with `.noWindow`
   (`isolated deinit`). Answers are handled first in `onInput` after
   `updatePointerState`; an answer for a token not in flight runs nothing.
5. **The drawn alert's model** (`SV-AC`): when `presentAlert` answers `false`,
   `Window.drawnAlert` holds the token, title, message and resolved buttons, and
   `Window.chooseAlertButton(_:)` (an index, or `nil` to dismiss) answers it as
   a native `.alertResult` would. Pinned by an added test,
   **2.25b** `aDeclinedAlertIsHeldByTheWindowAndChoosingRunsIt`. Nothing is
   painted; lane 3 draws it and calls `chooseAlertButton` from its input stage
   and accessibility press. `hoverIsSuppressed` already reads `drawnAlert`
   (2.53's alert half, lane 3's test).
6. **`PresentationScope` reuses `LifecycleScopeLayout` as its group layout**
   (no new public type; its doc comment names both scopes). The scope's key is
   `.named("$presentation<depth>")` under its position with an occurrence
   count — a registry key, never a `StateTable` id (no `noteNamed`, the seven
   slots unmoved).
7. **The non-presenting alert forms evaluate their actions and message while
   building** (`SV-I` item 4's mechanism, not its rule): SwiftUI's `actions:`
   and `message:` there are non-escaping, so they are called in the modifier and
   the resulting content is captured; the alert shows the content of the build
   it was presented in, and a later build's content is ignored while it is up
   (2.21). The `presenting:` forms' closures are escaping and called at
   presentation, never for `nil` data (2.24).
8. **The hover inventory family is class A on the spelling alone**: its cited
   arm `H1` is a recorded broken instrument, and the row and test 2.43's doc
   comment say so — the semantics are MetalUI's (`SV-N`'s evidence paragraph).

**Cost if wrong.** Item 2: a future reader that wants the whole handler set
from the opaque hitbox must not read `hover` there — the hover region holds it.

## SV-AI — Lane 2's guard mutations (measured)

**Ruling.** Each new typecheck guard of lane 2 (2.G5–2.G11) was mutated red
once on `feat/platform-services` at `8ee6d13`: the mutation applied (the
spelling below), the whole unfiltered suite run (`swift build --build-system
native --build-tests && swift test --build-system native --no-parallel`), the
file restored from a copy and `git status --short` read clean. Baseline
**2503 tests in 3 suites passed**, the `FR-J no-argument frame: succeeded=`
line and all seven guards' log lines present (none skipped). Each mutant
failed the run with exactly one issue, in the guard named:

| # | Mutation (site) | Reddened |
|---|---|---|
| MG2.5 | `@_spi(AlertInternals)` dropped from both `_AlertButtons` and the `AlertActions` requirement (`Alert.swift`) — the fabricated conformance compiles | `anOutsideTypeCannotConformToAlertActions` |
| MG2.6 | `extension Button: AlertActions` with no `where Label == Text` (title read through `as? Text`) — the `Box`-labelled action compiles | `aNonTextButtonIsNotAnAlertAction` |
| MG2.7 | fixture: the first importer's `allowedContentTypes:` → `contentTypes:` | `thePresentationSpellingsTypecheckFromAnExternalModule` |
| MG2.8 | fixture: the negative's `.onClick {}` moved before `.alert` | `aLegacyDecorationAfterAPresentationModifierDoesNotCompile` |
| MG2.9 | `EnvironmentValues.fileDialogs` `public internal(set)` → `public` | `fileDialogsIsReadOnlyOutsideMetalUI` |
| MG2.10 | an added `confirmationDialog(_:isPresented:titleVisibility:actions:)` overload and a public `Visibility` enum (`Alert.swift`) | `titleVisibilityIsNotOffered` |
| MG2.11 | fixture: `.onContinuousHover { phase in` → `.onContinousHover` | `onHoverTypechecksOnBothVocabularies` |

Dropping the SPI from `_AlertButtons` alone was not run as a separate arm:
MG2.5 measures the spelling the guard's doc comment names ("make the
requirement public"). The negative arm of 2.G10 reads either "extra arguments
at positions #3, #4" or "generic parameter 'A' could not be inferred" from run
to run; the guard checks success only, so both are a refusal.

**Cost if wrong.** None to the code; a guard here that a later change makes
unable to fail is caught only by re-running its row.
