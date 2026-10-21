# 136 - The sample app (E1: `Examples/Jotter`)

Branch `feat/sample-app` from `1bdead8d`. Not a plan task: item E1 (round 2) of the gpui-gap list, user request 2026-10-21 ("Sample app: `metalui new` gives
a hello-world starter, but no real sample app exists"). Spec `docs/superpowers/specs/2026-10-21-sample-app-design.md`; rulings `EX-A`...`EX-S` in
`docs/superpowers/2026-10-21-sample-app-decisions.md` (next `EX-T`). Divergence labels 655-664 reserved: **none taken** (no `Sources/` change, no public
declaration, no SwiftUI claim, no probe). One lane. Human checks: group `EX` (proposed text in section 7), not yet in `human-checks.md`.

## 1 What landed

`Examples/Jotter/`: a notes app as its own SwiftPM package (library `JotterKit`, executable `Jotter`, `Tests/JotterTests`), depending on the checkout with
`.package(name: "MetalUI", path: "../..", traits: metalUITraits)` and the scaffold's products (`EX-A`, `EX-B`; tools 6.1 accepts `name:` with `traits:`;
built in a checkout directory named `sample-app`, not `MetalUI`). Sources (about 700 lines): `Note`/`NotesModel` (an `@Observable` `@MainActor` model, versioned JSON,
"today" injected), `RootView` (`VStack`, `HStack`, `Divider`, `.toolbar` with six items, `.searchable`), `SidebarView` (`List(_:selection:rowHeight:)` in a
`ScrollView`, an empty state over it), `NoteRow` (`.equatable()`, `.draggable`, `.dropDestination`, `.contextMenu`), `DetailView` (`TextField`, `TextEditor`,
`@FocusState`, `.onChange`, `.task(id:)`, a Markdown literal), `StatsView` (rectangles and a `Shape`), `Presentations` (`.confirmationDialog`, `.alert`,
`.fileExporter`, `.fileImporter`), `JotterApp` (`App.commands`), `Theme` (`ThemeColorKey`, `Color(light:dark:)`, `.preferredColorScheme`). Every section is its own
`Component` (Windows 1 MB stack). The model is created in `main.swift` and passed in (divergence 125).
Root: `Tests/MetalUIScaffoldTests/SampleAppTests.swift` (+2 tests, `EX-S`); CI: a macOS step in `swift.yml` and a Linux-image step in `sdl-gpu-linux.yml`;
`README.md`, `docs/getting-started.md`, `docs/guides/README.md` and `docs/testing.md` link it.

## 2 Findings (API rough edges the app hit; none fixed here)

1. **No `Canvas`/`GraphicsContext`** (known, `drawing-and-gpu.md`): the chart is `Rectangle`s and a `Shape` (`EX-K`).
2. **`.accessibilityIdentifier`/`.accessibilityLabel` on a container reach every child** (as SwiftUI); on a `TextField` placed before `.frame` the node became a plain
   group with no value, after it a `textField` (`EX-N`).
3. **`.focused($flag)` must be applied to the control before any proposal wrapper**; after `.frame`/`.accessibilityIdentifier` it bound a non-focusable wrapper and a
   focus write did nothing, silently (`EX-N`). A focus write from `.onChange` (the lifecycle drain) does apply, in the same frame.
4. **`Toggle` has no `.keyboardShortcut`** (`EX-Q`).
5. **A `List` row must be one `Element`**: an `.equatable()` component needs a `Column { }` around it; the error is a generic-constraint failure naming `EquatableComponent<NoteRow>`.
6. **A `List` created in a frame builds its rows one frame later**, so swapping it for an empty state flashes (`EX-M`).
7. **`Equatable` on a `Component` needs `nonisolated static func ==`** under Swift 6 (main-actor conformance error otherwise).
8. **`.preferredColorScheme` returns an `EnvironmentScope`, not an `Element`**: it cannot end a window's root, only sit inside a container.
9. **`Edges` has `init(all:)` and per-side, no horizontal/vertical**; `.padding` takes `Edges<Length>` on a legacy element (which a legacy `.frame` keeps it) and `Edges<Pixels>` on proposal content, so a modifier order silently changes the type wanted.
10. **A headless platform does not echo `.preferredColorScheme` as the appearance** (`EX-P`); `Text` parses Markdown only in a literal, so there is no live preview.
11. **A main-actor model read through a stdlib closure traps off the main thread**, which bounds a "build on a 1 MB thread" test (`EX-O`).
12. **Delete's ⌘⌫ belongs to a focused text field** (`EX-Q`).
13. **Off macOS a window's first frame has no sidebar rows**: a `List` measures its origin and asks for one more frame; AppKit's synchronous observation hop supplies it, the Linux image did not
    (five tests failed there with `no element matches identifier "note-..."` until the test helper drew two settling frames). Same fact as the `runUntilIdle` note in `docs/testing.md`.

## 3 The app's tests (21; 20 off Darwin) and their mutations

Red-first: commit `b9e19743` holds tests 1-9 against a stub root view (9 of 9 red: `no toolbar item "new" is presented`, `no element matches identifier "title-field"`); commit `92dcc24a` holds tests 10-17
(11 issues in 8 tests before the commands, identifiers and stats edits, e.g. `no menu item at File > New Note`, `4 elements match label "Statistics: 4 notes, 46 words"`, `SIGTRAP`;
`draggingARowOntoAnotherReordersTheModel` was green on arrival because the drop destination was already on the row, so it is proven by mutation only).
Mutations, each applied to a committed tree, restored from a copy, the full unfiltered `swift test` in `Examples/Jotter` (25 runs, none hung; `git status --short` clean after the last):

| Mutation | Reddened |
| --- | --- |
| M1 seed returns no notes | process crash (index out of range in a test), no summary line: red |
| M2a New does not select / M2b New does not ask for focus / M19 no focus handler | `newNoteAddsARowSelectsItAndFocusesTheTitle` |
| M3 title binding writes `notes[0]` | `typingInTheTitleAndBodyEditsTheSelectedNoteOnly` |
| M4a case-sensitive search / M4b body ignored | `searchFiltersTheSidebarAndClearingRestoresIt` |
| M5 selection binding dropped | `selectingARowShowsItsNoteInTheDetail`, `typingInTheTitleAndBodyEditsTheSelectedNoteOnly`, `deletingTheSelectedNoteSelectsTheNeighbour`, `theWordCountFollowsTheBodyOfTheSelectedNote` |
| M6a delete without the dialog | `deleteAsksForConfirmationAndOnlyConfirmDeletes`, `deletingTheSelectedNoteSelectsTheNeighbour`, `exportWritesVersionedJSONAndImportReadsItBack`, `theCommandsMenuShortcutsRunTheirActions` |
| M6b Cancel deletes | `deleteAsksForConfirmationAndOnlyConfirmDeletes`, `theCommandsMenuShortcutsRunTheirActions` |
| M7 selection left dangling | `deletingTheSelectedNoteSelectsTheNeighbour` |
| M8a file version 2 | `exportWritesVersionedJSONAndImportReadsItBack`, `importingGarbageShowsAnAlertAndKeepsTheNotes` |
| M8b import appends | `exportWritesVersionedJSONAndImportReadsItBack` |
| M9 failed load empties the notes | `importingGarbageShowsAnAlertAndKeepsTheNotes` |
| M10 drop off by one / M10b row not draggable | `draggingARowOntoAnotherReordersTheModel` |
| M11a New on the wrong key / M11b Duplicate without shortcut | `theCommandsMenuShortcutsRunTheirActions` |
| M12 duplicate shares the id | `contextMenuDuplicateCopiesTheNote`, `theCommandsMenuShortcutsRunTheirActions` |
| M13 row not `.equatable()` | `anUnchangedRowIsNotEvaluatedWhenAnotherNoteIsEdited` |
| M14 summary counts one note | `theStatsCanvasSummaryNamesTheCountsAndFollowsEdits` |
| M15 palette ignores the scheme | `darkSchemeChangesTheSidebarFill`, `theThemeButtonAsksForTheOtherSchemeAndTheFillFollows` |
| M25 Theme always asks for dark | `theThemeButtonAsksForTheOtherSchemeAndTheFillFollows` |
| M16 detail 900 wide | `aWindowShrunkToMinimumKeepsEveryControlHittable` and nine more (a 900-wide detail covers the sidebar's hit area) |
| M18 word-count task keyed on the text only | **nothing: an equivalent mutant** (the count is a function of the text); the source was simplified to key on the text |

Not mutation-red, by name: `theRootTreeBuildsOnAOneMegabyteThread` (a pin; its Darwin non-vacuity arm `aThreadTooSmallForTheTreesFailsTheSameHarness` shows a 64 KB thread fails, `EX-O`);
`theFileCommandsOpenThePanels`; the root manifest-shape test (mutated in section 4).

## 4 Root verification

(Filled at the end of the run; see section 6.)

## 5 CI

`swift.yml` (macOS): `swift test --package-path Examples/Jotter` after the root tests. `sdl-gpu-linux.yml` (Linux, the `metalui-portable` image it already builds): the package is built and tested with the SDL and AccessKit
traits, `Examples/Jotter/**` joining its path filters. `scene-linux` and Windows are untouched. Not run by an agent (CI only).

## 6 Owed

- A real-window capture of the running app (`docs/probes/window-capture/capture.sh` covers `MetalUIDemo` only): the screen was locked (`CGSSessionScreenIsLocked = 1`) so nothing was launched.
- Windows: the package was not built there (compiled by CI only; `Backends/SDL` untouched).
- `CLAUDE.md`/`AGENTS.md` (one rule paragraph for `EX-`), `docs/record/README.md` (a row), `docs/verification/human-checks.md` (group `EX`): the Record phase.

## 7 Proposed human-check group `EX`

EX1 the app on macOS looks right (sidebar, rows, detail, stats, toolbar, native menus); EX2 the same under SDL on Linux (the drawn menu bar and toolbar strip, `Search notes` field, drag preview); EX3 a real Export then Open
round trip through the native panels; EX4 Theme and the system Dark mode on both; EX5 drag a row, right-click Duplicate, Delete with the sheet; EX6 ⌘N/⌘D/⌘⌫ with the title field focused and not.
