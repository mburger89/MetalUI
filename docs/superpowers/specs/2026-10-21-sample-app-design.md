# Sample app (E1) - design

Item E1, round 2 of the gpui-gap list (user request 2026-10-21; original item 1: "`metalui new` gives a hello-world starter, but no
real sample app exists"). Branch `feat/sample-app` from `1bdead8d`. Rulings: [`../2026-10-21-sample-app-decisions.md`](../2026-10-21-sample-app-decisions.md)
(prefix `EX-`). Record: `docs/record/136-sample-app.md` (Record phase). Divergence labels 655-664 reserved: **none expected**.

## Goal and non-goals

One real, multi-screen app, **Jotter** (a notes app), that shows an author how a MetalUI program is written, the way gpui's `examples/`
and a SwiftUI sample do: a model, a root view split into small `Component`s, presentations, commands, persistence, a chart, tests.
It is the repo's reference for "what a finished app looks like", not a framework feature: **no `Sources/` change, no public API**.
A bug the app finds is its own ruling, pinned and minimal. A rough edge that is not a bug is a finding in record 136, not a fix.
Not built: lazy containers (`LazyVStack`/`LazyVGrid` are lane L1's, not on master), `phaseAnimator`, `@GestureState` (G1), multi-window,
rich-text editing (the `TextEditor` stays plain, `RT-`), a Windows CI step.

## Where it lives (EX-A, EX-B)

`Examples/Jotter/`, its own SwiftPM package depending on the checkout by path (`.package(path: "../..", traits: ...)`), so it builds the
way a user's app does and counts nothing in the root manifest or its CI (PC-A). Shape taken from `metalui new --cross-platform`
(`Scaffold.swift` `manifest`): tools 6.1, `platforms: [.macOS(.v14)]`, the `metalUITraits` block (`SDL`+`AccessKit` on Linux/Windows,
`.defaults` on macOS), `MetalUISDL` on `.when(platforms: [.linux, .windows])`, `MetalUIPortableText` and `MetalUISystemFonts`
unconditional (`SG-D`), Swift 6 mode. Precedent: `Experiments/SDLGPU`.

```
Examples/Jotter/
  Package.swift
  README.md                          what it shows, how to run, a map from feature to file
  Sources/JotterKit/                 library: everything but the entry point (so a test imports it plainly, no @testable executable)
    Note.swift                       Note (Codable, Identifiable, Hashable, Transferable), NoteStore payload (JSON, versioned)
    NotesModel.swift                 @Observable @MainActor model: notes, selection, query, sort, create/edit/delete/move, load/save
    JotterApp.swift                  makeApp(), the window, commands (File/Edit menus + shortcuts), rootView()
    RootView.swift                   NavigationSplit-style HStack: sidebar | divider | detail; toolbar and .searchable
    SidebarView.swift                List(selection:) of NoteRow, context menu, drag-to-reorder, empty state
    NoteRow.swift                    .equatable() Component row: title, snippet, relative-date, tag chips
    DetailView.swift                 title TextField + body TextEditor + rich Text preview (markdown literal) tab
    StatsView.swift                  Canvas chart: words per note (bars) and notes per day (line) from the model
    Presentations.swift              .confirmationDialog (delete), .alert (load error), .fileExporter, .fileImporter
    Theme.swift                      palette keys (ThemeColorKey), light/dark through Color(light:dark:)
  Sources/Jotter/main.swift          the executable: makeApp(), open window, app.run(); cross-platform platform choice as the starter's
  Tests/JotterTests/                 swift-testing over MetalUITesting (one file per flow group, below)
  Packaging/{macOS,linux}/           the starter's Info.plist / .desktop and scripts/bundle-macos.sh, bundle id com.example.Jotter
```

Every screen section is its own function or `Component` (Windows 1 MB stack, `PE-K`, `CI-AI`): the root `body` composes five
`Component`s and no `switch` holds a subtree. The model is a plain `@Observable` class held by the root `Component`'s `@State`
instance assigned in `onAppear`-free initial state (a never-written `@State` default re-seeds every build, divergence 125, so the model is
created once in `makeApp()` and passed in, never defaulted in a `@State`).

## Screens and the API each exercises

| Screen / flow | MetalUI API shown |
| --- | --- |
| sidebar | `List(selection:)` over `Identifiable` rows with `rowHeight:`, `.equatable()` `NoteRow`, `.contextMenu` (Rename-focus, Duplicate, Delete), `.draggable(_:)`/`.dropDestination` reorder, `Text` markdown literals for tag chips |
| detail | `TextField(_:text:)`, `TextEditor(_:text:)`, `@FocusState`, `.onKeyPress` (primary-Return = done), `Text` with a markdown **literal** preview, `ScrollView`, `.task(id:)` autosave debounce counted by ticks not time |
| toolbar | `.toolbar` items (New, Delete, Export, Import, Stats toggle), `.searchable(text:)` filtering the sidebar |
| delete | `.confirmationDialog` for one note, `.alert` for a load failure |
| persistence | `.fileExporter` (a `Data` of versioned JSON as `.json`), `.fileImporter`, `Codable` |
| commands | `App.commands { CommandMenu / CommandGroup }`, `.keyboardShortcut` (`EventModifiers.primary`: N new, F focus search, Delete, S export, O import) |
| stats | `Canvas` (bars + line from `Path`), `Color(light:dark:)`, `@Environment(\.colorScheme)`, `.accessibilityLabel` summary |
| lifecycle | `.onAppear` (load last file path from the model), `.task` |
| theme | a palette `ThemeColorKey`, `.preferredColorScheme` from a toolbar toggle |

Persistence target: the user picks the file through the dialog; the app keeps **no hidden state file** (cross-platform, no sandbox
questions, `EX-F`). Load errors (not JSON, wrong version) surface as an alert and never replace the in-memory notes.

## Verification wiring (EX-C, EX-D)

- **The app's own tests** (`Tests/JotterTests`) are written as `docs/testing.md` tells an app author to: `TestWindow`/`TestApp`, queries
  by accessibility label, presentations answered at the seam (`presentedAlert`, `presentedFileDialog`), the portable text system on
  Linux/Windows, a simulated clock, work counters for the row-skip claim. `swift test` in `Examples/Jotter` on macOS and in the Linux image.
- **Root env-gated test** `aSampleAppBuildsAndItsTestsPassAgainstThisCheckout` (`METALUI_RUN_SAMPLE_APP_TEST=1`, `Tests/MetalUIScaffoldTests/SampleAppTests.swift`, counts
  while skipped): runs `swift build`, `swift build --build-tests`, `swift test --skip-build` in `Examples/Jotter` (macOS and Linux only)
  and expects the named tests and the swift-testing summary line. It also checks the manifest still names every product a generated
  cross-platform package names (a text comparison against `manifest(ScaffoldOptions(crossPlatform: true))`'s dependency lines) so the example
  cannot drift from the scaffold. Root suite count moves by +2 tests (the build test, the manifest-shape test), no guard.
- **CI**: macOS job gains a step `swift test --package-path Examples/Jotter` after the root tests (about one more MetalUI build, ~5 min,
  `EX-E`); the Linux `scene-linux` job is **not** touched (it builds portable targets only, no SDL libraries); the SDL image job
  (`sdl-gpu-linux.yml`'s image) runs the example with the `SDL` trait only if its steps already build that image, else the
  Linux run is the documented local `docker run` recipe in the README. Decided at implementation by reading the workflow; the PR says which.
- **Capture**: `docs/probes/window-capture/capture.sh` of the running macOS app when the lock probe allows; else "owed", and human
  check group `EX` (EX1 looks on macOS, EX2 looks under SDL on Linux, EX3 a real save/load round trip through the native panels, EX4 dark mode).

## Docs

`Examples/Jotter/README.md`; one link each from `README.md`, `docs/getting-started.md` ("A bigger example") and `docs/guides/README.md`
(table row "Sample app"). **No guide snippet is added** (so no DG-C mirror): the README quotes no compiled-by-the-guides block, it points
at files that the example's own tests compile (`EX-G`). `docs/testing.md` gains a one-line pointer to `Jotter`'s tests as a worked example.

## Tests (the app's own, by name)

Each names its red-before (what is absent on the first commit of the test, so it cannot pass vacuously) and the mutation that must
redden it. Mutations are run in the Implementation phase against the app's sources, committed first, restored from a copy.

| # | Test (file) | Red before | Mutation that must redden it |
| --- | --- | --- | --- |
| 1 | `launchShowsTheSeededNotesAndSelectsTheFirst` (FlowTests) | no `NotesModel` | seed returns `[]`: the sidebar rows are absent |
| 2 | `newNoteAddsARowSelectsItAndFocusesTheTitle` (FlowTests) | no New action | New appends without selecting; or selects without focus |
| 3 | `typingInTheTitleAndBodyEditsTheSelectedNoteOnly` (EditTests) | no detail | binding writes to `notes[0]` instead of the selection |
| 4 | `searchFiltersTheSidebarAndClearingRestoresIt` (SearchTests) | no `.searchable` | filter compares case-sensitively / ignores body |
| 5 | `selectingARowShowsItsNoteInTheDetail` (FlowTests) | no selection binding | selection never published (`List(selection:)` binding dropped) |
| 6 | `deleteAsksForConfirmationAndOnlyConfirmDeletes` (DeleteTests) | no dialog | delete without the dialog; cancel path deletes |
| 7 | `deletingTheSelectedNoteSelectsTheNeighbour` (DeleteTests) | no rule | selection left dangling on a removed id |
| 8 | `exportWritesVersionedJSONAndImportReadsItBack` (PersistenceTests) | no codec | version field dropped; or import appends instead of replacing |
| 9 | `importingGarbageShowsAnAlertAndKeepsTheNotes` (PersistenceTests) | no error path | failure replaces notes with `[]` |
| 10 | `draggingARowOntoAnotherReordersTheModel` (ReorderTests) | no drag | drop inserts at the wrong index (off by one after removal) |
| 11 | `theCommandsMenuShortcutsRunTheirActions` (CommandTests) | no commands | New bound to the wrong key; shortcut gate missing |
| 12 | `contextMenuDuplicateCopiesTheNote` (ContextMenuTests) | no menu | duplicate shares the id |
| 13 | `anUnchangedRowIsNotEvaluatedWhenAnotherNoteIsEdited` (RowSkipTests) | row not `.equatable()` | drop `.equatable()`: `FrameWork` content-evaluation counter rises |
| 14 | `theStatsCanvasSummaryNamesTheCountsAndFollowsEdits` (StatsTests) | no chart | summary uses stale model snapshot |
| 15 | `darkSchemeChangesTheSidebarFill` (ThemeTests) | no palette | palette ignores the scheme |
| 16 | `aWindowShrunkToMinimumKeepsEveryControlHittable` (LayoutTests) | no layout | detail given a fixed width wider than the minimum |

Counting rule: each is `@MainActor @Test`, no sleeps, work counted not timed, a count the loop indexes on is `try #require`.
The root `everyProductionTreeBuildsOnAOneMegabyteThread` is **not** extended (the example is not in the root package); instead test 17,
`theRootTreeBuildsOnAOneMegabyteThread` (`StackTests`), builds `rootView()` on a `Thread` with a 1 MB stack, mutation: inline the five
sections into one `body`, expecting the overflow only if the tree is large enough (if no such inline version overflows, the test is kept
as a pin and its limits are recorded, not claimed as red).

## Lanes

**One lane** (the app is one package, files not shared): Examples/Jotter, the root build test, README/doc links, CI step. The record,
the human-checks group `EX` and the CLAUDE.md rule are the Record phase's. Order inside the lane: package skeleton and the scaffold
manifest test first (builds on both platforms), then model + tests 1-9, then views' polish, drag/commands/stats/theme (10-17), then
docs and the capture.

## Open points carried to implementation (each becomes a ruling when settled)

1. `package:` name of the product dependency (see `EX-B`: the identity of a `path: "../.."` dependency is the checkout directory's name).
2. Whether `.searchable` is shown by the SDL drawn toolbar strip with the same label (`MD-K`); if not, a finding.
3. Drag preview on SDL; reorder driven by `drop(_:at:)` in the harness, real drags only in human check EX2.
