# Jotter

A small notes app, and MetalUI's sample app: a sidebar of notes and an editor, written the way an
application written against MetalUI is written - a model, a root view split into small components,
presentations, menu commands, file persistence, a chart and tests. It is a program, not a test
fixture: read it top to bottom, change it, ship it as the starting point of your own.

It is its own SwiftPM package that depends on the checkout by path, so it builds the way your app
will (`metalui new --cross-platform` writes the same manifest, `docs/getting-started.md`). It is
not part of MetalUI's root package, so it adds nothing to MetalUI's own build.

```sh
swift run --package-path Examples/Jotter Jotter      # macOS: AppKit and Metal
swift test --package-path Examples/Jotter            # the app's own tests, headless
```

On Linux and Windows the same package opens an SDL window (the manifest turns the `SDL` and
`AccessKit` traits on there). A Linux recipe that needs nothing installed but Docker, from the
checkout (the image is `Backends/SDL/linux/Dockerfile`):

```sh
docker build -t metalui-portable -f Backends/SDL/linux/Dockerfile Backends/SDL
docker run --rm -v "$PWD":/work -w /work/Examples/Jotter metalui-portable \
  bash -c 'swift build --build-tests --scratch-path /tmp/jotter && swift test --skip-build --scratch-path /tmp/jotter'
```

## What it shows, and where

| You want to see | MetalUI API | File |
| --- | --- | --- |
| an `@Observable` model, created once and passed in | `@Observable`, `Binding(get:set:)` | `NotesModel.swift`, `Theme.swift` (`binding(_:)`) |
| a root view of small components | `Component`, `VStack`/`HStack`, `.frame`, `.background` | `RootView.swift` |
| a selectable list that only builds what is in view | `List(_:selection:rowHeight:)` in a `ScrollView` | `SidebarView.swift` |
| a row that is skipped when its note did not change | `.equatable()` | `NoteRow.swift` |
| drag a row onto another to reorder | `.draggable(_:)`, `.dropDestination(for:action:)` | `NoteRow.swift` |
| a context menu | `.contextMenu` | `NoteRow.swift` |
| a title field, a body editor, focus from code | `TextField`, `TextEditor`, `@FocusState`, `.onChange(of:)` | `DetailView.swift` |
| work that follows a value | `.task(id:)` | `DetailView.swift` |
| Markdown in a string literal | `Text` with a literal | `DetailView.swift` |
| a toolbar and a search field | `.toolbar`, `ToolbarItem`, `.searchable` | `RootView.swift` |
| asking before deleting; reporting a failed load | `.confirmationDialog`, `.alert` | `Presentations.swift` |
| saving and opening a JSON file | `.fileExporter`, `.fileImporter`, `Codable` | `Presentations.swift`, `NotesModel.swift` |
| menu commands with shortcuts | `App.commands`, `CommandGroup`, `CommandMenu`, `.keyboardShortcut` | `JotterApp.swift` |
| a chart | `Rectangle`, `Shape` and `Path`, `.stroke` | `StatsView.swift` |
| a colour palette, light and dark | `ThemeColorKey`, `Color(light:dark:)`, `.preferredColorScheme` | `Theme.swift`, `RootView.swift` |
| the same app on every platform | the scaffold's manifest and `makeApp()` | `Package.swift`, `Sources/Jotter/main.swift` |

`Sources/JotterKit` is everything but the entry point, so tests import it plainly; `Sources/Jotter`
is `main.swift`: build the model, make the app, install the commands, open the window, run.

## Using it

- **New** (⌘N, Ctrl+N elsewhere) adds a note at the top, selects it and focuses its title.
- Click a row to edit it; type `#tags` in a body and they show under the title in the sidebar.
- **Search** filters by title and body, ignoring case.
- Drag a row onto another to move it there; right-click a row for Duplicate and Delete.
- **Delete** (⌘⌫) asks first. **Export** (⌘E) and **Open** (⌘O) save and read a JSON file you choose;
  Jotter keeps no file of its own, so closing the window forgets what you did not export.
- **Stats** replaces the editor with words per note and notes made per day. **Theme** flips light and dark.

## The tests

`Tests/JotterTests` is written the way `docs/testing.md` tells an app author to: each test opens the
app's real root element in a `TestWindow`, clicks and types as a person does, finds things by
accessibility identifier and label, answers alerts and file dialogs at the platform seam, and counts
the work a frame did. No test sleeps and none reads a clock; the model takes "today" as a function.
Twenty-one tests (twenty off Darwin), one file per group of flows: `FlowTests` (launch, new, select), `EditTests`,
`SearchTests`, `DeleteTests`, `PersistenceTests`, `ReorderTests`, `CommandTests`,
`ContextMenuTests`, `RowSkipTests` (the `.equatable()` claim, counted), `StatsTests`, `ThemeTests`,
`LayoutTests` (the smallest window) and `StackTests` (the trees build on a 1 MB thread).

From MetalUI's root, `METALUI_RUN_SAMPLE_APP_TEST=1 swift test --filter aSampleAppBuildsAndItsTestsPassAgainstThisCheckout`
builds this package and runs its tests; CI runs them on macOS and in the Linux image.

## Things this app does not do (the next steps)

- **Autosave or a document model.** Persistence is the two file dialogs and nothing else, so it behaves the same
  on AppKit and SDL and there is nothing to sandbox. A real notes app would keep a library file.
- **A live Markdown preview.** `Text` parses Markdown only in a string literal; a `String` value is shown as typed.
- **Lazy containers.** The list is `List`, windowed; `LazyVStack`/`LazyVGrid` (MetalUI has them) are not used.
- **Packaging.** `docs/packaging.md` has the recipe (`.app` bundle, `.desktop` file, icons); use bundle id `com.example.Jotter`.
