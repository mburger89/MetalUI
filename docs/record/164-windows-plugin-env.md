# 164 — The build-tool plugin on Windows (XP-G35)

Item XP-G35 (MetalCreator, 2026-10-30, blocking; computed workflow task, **not a plan task**), on
`fix/windows-plugin-env` from `cc8995d3`, master `5b5ae68a` merged in. Rulings `BT-V`..`BT-Y`
(`docs/superpowers/2026-10-28-build-tool-shaders-decisions.md`).

## 1. The failure

MetalCreator's Windows CI (default build system, swift-build `CustomTask`, Swift 6.4.0) crashed in
`MetalUICompileShaders.exe` at `process.run()` in `ShaderCompiler.processRunner`: `Could not create
wakeup socket pair for CFSocket!!!`, then `Illegal instruction`. `CompileShadersOnBuild` passed no
`environment:` to `.buildCommand`, so the tool ran without `SystemRoot`, and Winsock, which Foundation's
`Process` uses in the parent, cannot start without it. This is the Windows consumer build `BS-D` had left
unmeasured (`BT1`..`BT3`).

## 2. As built

- `BT-V`: the plugin forwards an explicit environment from one region (`ForwardedEnvironment`) kept byte
  for byte in `ChildEnvironment.swift` and `Plugin.swift`, pinned by
  `theBuildPluginForwardsTheSameEnvironmentTheToolListsHere`. Changing only a forwarded key that is not
  also an argument (`METALUI_SHADERCROSS_LIB`, the Windows system keys) does not rerun the command.
- `BT-W`: on Windows the tool sets `SystemRoot`/`WINDIR` from `GetWindowsDirectoryW` before any
  Foundation use when they are missing, and `ChildEnvironment.merged` gives shadercross's child the
  system variables it lacks.
- `BT-X`: `.github/fixtures/build-plugin/` is built with plain `swift build` on Windows and in the Linux
  image, with a stub shadercross compiled in the step, and must produce a non-empty `tri.vert.spv`.

## 3. Red on arrival

The `BT-X` step alone (`c5af5ba9`, branch `probe/xp-g35-red`, run 41044890821): Windows failed with the
reported `Could not create wakeup socket pair for CFSocket` and `Illegal instruction`; both Linux jobs
passed. With `BT-V` and `BT-W` (`9b8814c6`), run 41046771214: all four SDL jobs green, Windows included.
Which of `BT-V` and `BT-W` alone suffices on Windows was not separated.

## 4. Mutations

| Mutant | Reddened |
|---|---|
| `SystemRoot` dropped from the Windows key list | `theForwardedKeysAreThoseTheToolAndShadercrossNeed`, `theSelectionKeepsTheOriginalSpellingAndOnlyPresentListedKeys`, `theBuildPluginForwardsTheSameEnvironmentTheToolListsHere`, `aWindowsChildGetsTheSystemVariablesItLacks` |
| `merged` returns its input | `aWindowsChildGetsTheSystemVariablesItLacks` |
| `PATHEXT` dropped from the plugin's copy only | `theBuildPluginForwardsTheSameEnvironmentTheToolListsHere` |

Dropping `environment: forwarded` and the `main.swift` ordering are covered only by the pin test's text
checks; `BT-X` is their behavioural check on Windows.

## 5. Counts

Before the master merge: `swift package clean`, native build, unfiltered `--no-parallel`: `Test run with
4533 tests in 12 suites` (the five known locked-screen `AppKitPresentationTests` sheet failures),
`FR-J no-argument frame: succeeded=true`. With master's one `VD-` test: **4534** by arithmetic, not
re-measured locally; macOS CI runs the merged tree. Guards unchanged at 277.
