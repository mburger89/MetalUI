# 170 — `.fileImporter` chooses folders (`SV-AM`, `SV-AN`)

2026-10-31, branch `feat/file-importer-folders` from master `d2797c5d`. **Numbered 170, not 169**: record 169 is
reserved by the concurrent scope-decorations line (`CoordinateSpaceScope`/`TransactionScope`), which was live in
another worktree when this one was written. Request: the MetalFlow app's "Add repo" must pick a git repository
**folder** with `.fileImporter`, which `SV-F` ("files only, never folders") refused.

## What changed

- `ContentType.directory` (`public.directory`, conforming to `.item`) and `ContentType.folder` (`public.folder`,
  conforming to `.directory`), UTType's identifiers and conformance (`SV-AM` item 1).
- The seam derives, it stores nothing: `PlatformFileType.isDirectory`, `PlatformFileDialog.canChooseDirectories` and
  `canChooseFiles` are computed from `kind` and `allowedTypes` — no conformer, fake or the headless platform changed
  (`HT-X` holds without edits), and a `MetalUITesting` test reads a folder dialog off `presentedFileDialog` (item 2).
- AppKit: `openPanelConfiguration(_:)`, pure, sets `canChooseFiles`/`canChooseDirectories` from the seam and keeps
  `UTType.folder` in `allowedContentTypes` (item 3; **assumed, not measured** — the screen was locked; human check `FO1`).
- A dialog over directory types alone completes with directory URLs (`URL(fileURLWithPath:isDirectory: true)`), in
  `.fileImporter` and `FileDialogs.openFiles` (item 4).
- SDL: `dialogMode(_:)` picks `SDL_ShowOpenFolderDialog` (bridge `mui_dialog_request_choose_folders`) for directory
  types alone; a mixed list is the file dialog, files only — **divergence 209** (item 5).
- Not built: `fileDialogConfirmationLabel(_:)`/`fileDialogMessage(_:)` (item 6, documented absence beside
  `fileDialogDefaultDirectory`).
- Docs: shard rule (`app-shell.md`), prefix row (`SV-AO` next), divergence 209 (179 live, next 210; record §04
  section), inventory rows (`folder-importer`), human-check group `FO`, `api-overview.md`.

## Tests and mutations

New: `FolderImporterTests.swift` (F1 `folderAndDirectoryConformAsUTTypesDo`, F2
`theSeamReadsADirectoryTypeAsChoosingDirectories`, F3 `theOpenPanelChoosesFoldersForAFolderType`, F4
`aFolderImporterCompletesWithADirectoryURL`, F5 `openFilesOverAFolderTypeReturnsDirectoryURLs`),
`HarnessPresentationTests.aFolderImporterIsAnsweredWithADirectory` (2.11b, a real temporary directory), an assertion
in 2.11 that a file importer stays files only, and `Backends/SDL` 1.13c `sdlFolderTypesAloneShowTheFolderDialog`.
The table (MF1–MF4, M1.13c, every one red) is `SV-AN` in
`docs/superpowers/2026-10-04-platform-services-decisions.md`.

## Counts

After `swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native
--no-parallel --skip AppKitPresentationTests` (the screen was locked; an unfiltered run hangs in `NSOpenPanel.init`, as
records 165–168 found): **4615 tests passed** (record 168's 4609 + the 6 new root tests), `FR-J no-argument frame:
succeeded=true`. Guards 285, unchanged (none added). `Backends/SDL`: 340 tests, one failure unrelated to this change —
`thePublicLocateDoesNotEvaluateItsBundleWhenTheExecutableCandidateOpens` cannot write beside the test helper inside
Xcode's toolchain (`EACCES` under `/Applications/Xcode.app/…/swift/pm/`, with `DEVELOPER_DIR` set to Xcode); every
`SDLPresentationTests` test passed.

## Open

- `FO1`–`FO3`: the real panel and SDL's folder picker (an agent cannot).
- Whether SwiftUI's importer over `[.item]` lets a folder be chosen is unprobed; MetalUI keeps it files only.
- `fileDialogConfirmationLabel`/`fileDialogMessage` would need an environment read at `PresentationScope` and a stored
  `message` on `PlatformFileDialog` (a `swift package clean` change).
