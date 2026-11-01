# 176 - test hygiene (`TK-A`..`TK-D`)

2026-10-31, branch `fix/test-hygiene` from `7d3d1b80`; round-3 item R3-3. Rulings: `docs/superpowers/2026-10-31-test-hygiene-decisions.md`.

## 1. Unfiltered run on a locked Mac (`TK-A`, `TK-B`)

Baseline (`swift test --build-system native --no-parallel`, screen locked, `CGSSessionScreenIsLocked = 1`): 4644 tests, 5 issues, 664 s. The four file-dialog tests and `appKitSecondDialogWhileASheetIsUpAnswersFalse` each spent 61 s in `NSOpenPanel.init`, then failed "no sheet attached"; the two alert tests passed. Alone, all nine pass (about 7 s). Measured non-causes: window count (200 key windows), 330 s idle, fds (136, 71 threads), each module with the panel test; test-name ranges 1-899, 900-1668, 1669-1768 pass, 1-1768 together fails (an accumulated-state trigger, not found). Lock state is identical in the passing and failing runs, so the lock is the condition the failure was seen under, not a proven cause. The guard reads `CGSessionCopyCurrentDictionary` (nil / not on console / locked) and gates seven tests with `.enabled(if:)`, two with the console flag only.

After: unfiltered, native, after `swift package clean`: **4644 tests passed in 12 suites, 262 s, no `--skip`**; the 7 sheet tests print "skipped" with the reason, the others run. Mutation (the guard removed, `canShowSheets = true`): the run fails again at `appKitOpenDialogIsASheetWithTheDeclaredTypes` after 61.5 s (reproduced three times: the baseline and two diagnostic builds). Unverified: an unlocked run (the Mac stayed locked), and the CI job (`.github/workflows` `build` runs `swift test -v --build-system native --no-parallel` unfiltered on an `xcode-27` runner; not runnable here, expected unlocked console).

## 2. EO-H, the Linux flake (`TK-C`)

`metalui-portable` image (aarch64, Swift 6.4.1, via OrbStack docker), 12 `yes` processes on 12 CPUs, 40 runs each. Before (the post-`HT-Y`/`HT-Z` loop of up to 64 `runUntilIdle()`): 36 pass, 4 fail, all `loader.value → 0` at the first check (the task never ran in 64 rounds). After (`runUntil { loader.value == 42 && drawn() == [50] }`): 40 of 40. `HT-Y`/`HT-Z` did not fix it; they were about idleness, not scheduling.

## 3. SDL file-drop flake (`TK-D`)

Reproduced on macOS: `swift test --filter SDLAppShell` in `Backends/SDL`, 1 failure in 6 and 1 in 7. The failing `opened` held `file:///SDLAppShell` and the test binary's path before our batch: AppKit's launch `openFile:` delivered through SDL as window-0 drops, parked until the handler was assigned. After: 30 of 30 clean. Mutations: a stray window-0 batch before the handler passes with the filter, fails without it (`opened == [...]` and `opened.count == 1`).

## Scratch

Docker was reachable at `/Applications/OrbStack.app/Contents/MacOS/xbin/docker` (not on `PATH`). Logs and bisect scripts stayed in the session scratchpad.
