# 179 — Dialog and alert extras (`SV-AO`, `SV-AP`)

2026-10-31, branch `feat/dialog-extras` from master `28a819e9` (round-3 item R3-6; MetalFlow's folder importer wanted
a word on its confirming button, and the alert surface still refused three SwiftUI shapes). SwiftUI is the design
authority: `docs/probes/swiftui-dialog-extras.swift` (arms `F`, `C`, `L`, `T`; 109 lines, run twice byte-identical,
screen locked) measured every shape before it was built.

## What changed

- `.fileDialogConfirmationLabel(_:)` and `.fileDialogMessage(_:)` (`Text` and `StringProtocol`, environment writes).
  `Frame.notePresentation` reads two internal custom keys at the presenting scope's **own position**, so a writer after
  the presenter reaches it and one on the content inside does not (probe `F1`/`F2`); `present` puts the label in
  `PlatformFileDialog.prompt` (replacing an exporter's "Export", `F3`) and the message in the new stored
  `PlatformFileDialog.message` (`swift package clean`). AppKit sets `prompt`/`message` through the pure `panelTexts(_:)`;
  SDL passes the accept label and the message-or-title to `SDL_ShowFileDialogWithProperties` (bridge
  `mui_dialog_request_set_labels`), only when either is set — **divergence 935**. The headless platform records the whole
  request, so `presentedFileDialog` shows both (`HT-X` 1, no edit).
- `confirmationDialog(…titleVisibility:…)` with the new public `Visibility`: accepted, inert, because `NSAlert` shows the
  title for all three (`C1`–`C8`). **The probe also found a real confirmation-dialog difference**: it synthesizes a
  "Cancel" whenever none is declared and then has no default (`C10`, `C12`; an alert only beside a destructive button);
  `AlertButtons.resolve(_:confirmation:)` carries it.
- `Button` is an `AlertActions` whatever its label: the title is the first `Text` in the label (a `Mirror` walk, a `Text`
  label cast directly), a textless button is left out and none left shows the lone "OK" (`L1`–`L11`). MetalUI has no
  `Label` view; the probe's `Label` arms map to a `Row` of a shape and a `Text`.
- **Carried:** a `TextField`/`SecureField` in an alert's actions (`T1`–`T3`: an accessory view, the binding written
  live). SDL's alert is drawn by the window and has no text input, so an AppKit-only half would make one alert two
  controls; the seam would also need `textFields`/values. It stays "Not offered", narrowed to the field (guard 2.G6).
  Also carried: the async `FileDialogs` calls read neither value (no environment position); `presenting:` forms of
  `confirmationDialog`.
- Demo: the Services demo's **Import folder…** carries label "Use folder" and a message (human checks `DX1`–`DX3`).
- Docs: `SV-AO`/`SV-AP` (decisions doc; `SV-AM` item 6 now points here), shard rule (`app-shell.md`), divergence 935
  (179 live, next label 210; 935 used and 936–944 unused by `SV-AO`) and two "Not offered" rows removed/narrowed,
  inventory family `dialog-extras`, `api-overview.md`, `migration.md`, the presentations guide, human-check group `DX`.

## Tests and mutations

New: `DialogExtrasTests.swift` (11 tests: `theSeamCarriesTheFileDialogsMessage`,
`aFileImporterReadsItsLabelAndMessageFromTheEnvironmentAboveIt`, `anExporterTakesTheEnvironmentsLabelOverItsExportPrompt`,
`theHeadlessHarnessShowsTheLabelAndMessageOfThePresentedDialog`, `theAppKitPanelTextsAreTheSeams`,
`titleVisibilityIsAcceptedAndNeverHidesTheTitle`, `aConfirmationDialogSynthesizesItsCancelButton`,
`theConfirmationDialogModifierShowsTheSynthesizedCancel`, `aButtonsTitleIsTheFirstTextInItsLabel`,
`aButtonWithNoTextIsLeftOutOfAnAlert`, `aConfirmationDialogTakesAButtonsTitleFromItsLabelToo`),
`HarnessPresentationTests.aFileDialogsLabelAndMessageAreReadAtTheHarness` (2.11c), two guards flipped
(`aNonTextButtonIsAnAlertActionButATextFieldIsNot` 2.G6, `titleVisibilityIsOffered` 2.G10; the second is now a positive
guard) and `Backends/SDL` 1.12b/1.12c. Red first: the test files did not compile at `28a819e9` (no `message`, no
`Visibility`, no `fileDialogMessage`). Mutations MF1–MF5, MC1–MC2b, ML1a–ML2b and M1.12b-a/b, **every one red**, are
`SV-AP` in the decisions doc; a `rootEnvironment` read (MF2a) is what the "inside the presenter" arm separates.

## Counts

After `swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native
--no-parallel --skip AppKitPresentationTests` (the screen was locked, as in records 165-170): **4647 tests** in the first
full run, one red (`aBehaviourWordHasAPinOnItsLine`: the presentations guide's new sentence cited no pin, fixed and re-run
alone green), so a second full run printed **`Test run with 4647 tests in 12 suites passed`** (master's 4635 + 11 `DialogExtrasTests` + `HarnessPresentationTests` 2.11c;
the two flipped guards keep their count), `FR-J no-argument frame: succeeded=true` printed (285 guards, the two flipped
ones included: `SV-AO non-text button: succeeded=true`, `titleVisibility: ... offered succeeded=true`).
`Backends/SDL` `swift test $(python3 scripts/fetch-accesskit.py --print-flags) --filter 'Dialog|Alert'`: 8 tests passed
(7 + 1.12b; 1.12c is Linux-image only and skipped here). `zsh docs/probes/closeout-inventory-check.sh` and
`closeout-undocumented.sh` print nothing; `closeout-public-api.tsv` is not re-recorded (it lags master by 174 rows
before this branch, an unrelated re-record).

## Human checks

Group `DX` (`docs/verification/human-checks.md`): the sheet's confirming button and message on macOS (`DX1`, `DX2`),
the SDL title and accept label on Linux and Windows (`DX3`).
