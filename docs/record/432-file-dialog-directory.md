# 432: a file dialog's starting directory (`SV-AQ`)

Class A (the modifier), class M (the `directory:` parameters and the seam field), divergence 936 (SDL). Branch `feat/file-dialog-directory`, base master `e051f257`. Requested by the Alloy code-editor app: File > Open... (Cmd-O) calls `FileDialogs.openFiles` from a menu command and should start in the project folder; Save As... should start beside the file being saved. Ruling: `docs/superpowers/2026-10-04-platform-services-decisions.md`, `SV-AQ` (mutations `SV-AR`).

## SwiftUI side

`fileDialogDefaultDirectory(_ defaultDirectory: URL?)` (macOS 15, the SDK `.swiftinterface`). Probe `docs/probes/swiftui-file-dialog-directory.swift`, arms `D0`-`D7`, macOS 27.0, one process per arm: a writer outside the importer or exporter reaches `NSSavePanel.directoryURL` as the URL as written (`D1`, `D3`); inside the presenter nothing (`D2`); the nearest writer wins (`D7`); `nil` and a nonexistent directory leave the panel's own choice (`D4`, `D5`); an https URL reads `directoryURL == nil` (`D6`). The panel remembers its last directory across runs of the same executable, so "no effect" reads as the remembered directory in its resolved `/private/var` form (the header says how to tell).

## What changed

- `.fileDialogDefaultDirectory(_:)` on `ElementGroup`: an internal `URL?` environment key, read in `Frame.notePresentation` at the presenting scope's position (as `fileDialogConfirmationLabel`) and kept on the `PresentationRecord`; `present` turns it into a path with `platformDirectoryPath` (a file URL's path, else `nil`).
- `FileDialogs.openFiles(allowedContentTypes:allowsMultipleSelection:directory:)` and `saveFile(contentTypes:defaultFilename:directory:)`, trailing and defaulted. `FileDialogs` holds only its window, so a call reads no environment: the modifier does not reach it (a call is made where no view environment applies), the argument is the only way.
- `PlatformFileDialog.directory: String?` (defaulted `init` parameter). The headless harness already records the whole struct.
- AppKit: `panel.directoryURL = AppKitWindow.directoryURL(dialog)`. SDL: `SDLWindow.dialogLocation(dialog)` is the bridge's existing `default_location` (the C side already passed it to `SDL_Show*FileDialog` and the properties form).

## SDL and the save filename

SDL3's header says `default_location` is "the default folder or file to start the dialog at ... Not all platforms support this option", for open, save and folder dialogs alike. So for a save dialog with both a directory and a name the documented form is the file path `<directory>/<name>`, which is what is passed; the directory alone with no name; with no directory the bare name, as before this change. Open dialogs get the directory with a trailing separator so a GTK or portal dialog reads it as a folder. What each desktop does (GTK portal, zenity, the Windows common dialog) with a missing folder or the joined form is unmeasured here: human check `FD1`-`FD3`, divergence 936.

## Tests

`FileDialogDirectoryTests` (`D1`-`D4`): the modifier reaches the importer and exporter, inside/`nil`/https/none send `nil`, nearest wins; the arguments reach `openFiles` and `saveFile`; AppKit's `directoryURL` is the seam's; an idle frame's `elementRequests` are the same with and without the modifier. `SDLPresentationTests` 1.12d: `dialogLocation`. Mutation table `SV-AR`: all six reddened.

**Cost.** The record gains one `URL?` (a copy, retained once); nothing is read until a scope notes a presentation, so a window without a file dialog pays no request and no allocation; the existing steady-frame allocation pins did not move.
