# 165. MetalFlow gaps (HS-, WA-, BU-, SE-)

Four small lanes, **not plan tasks**, requested from the MetalFlow app session (the macOS app built on MetalUI, which found these gaps while porting: a split view, bringing a window forward from a notification click, a real `.app` bundle for user notifications, and per-segment accessibility identifiers for UI tests). Each ran in its own worktree from master `65e300a0` and merged into `feat/metalflow-gaps`; this record is the integration pass. The rulings, pins and mutation tables are in each lane's decisions doc and are not copied here.

## 1. The lanes

| prefix | what | decisions doc | divergence |
|---|---|---|---|
| `HS-` | `HSplitView` / `VSplitView`: one engine on both axes, a dragged divider (press-time snapshot plus translation, clamped on the two neighbours), per-view autosave | `docs/superpowers/2026-10-30-split-view-decisions.md` | 206 (new) |
| `WA-` | `Window.makeKeyAndOrderFront()`, `App.activate()` over two defaultless requirements (`PlatformWindow.orderFrontAndMakeKey()`, `Platform.activate()`); `Color(hex:)` made public | `docs/superpowers/2026-10-30-window-activation-decisions.md` | none |
| `BU-` | `metalui bundle`: a pure planner over a thin executor, ad hoc signed, not notarized | `docs/superpowers/2026-10-30-bundle-command-decisions.md` | none |
| `SE-` | a segmented `Picker` option's identifier: the content's, else `<picker id>.<tag>` | `docs/superpowers/2026-10-30-segment-accessibility-decisions.md` | none (`SE-B`) |

Mutations: `HS-` has a table (M1 onward), `WA-` and `SE-` each a "Mutations" section, `BU-` is covered by its planner tests; read the docs for names and reddened tests. Divergence 206 is the only new label: 177 live, next label 207 (the segments lane wrote nothing).

## 2. Bookkeeping done here

Four prefixes added to `docs/rules/decision-prefixes.md` (next ids `HS-I`, `WA-D`, `BU-F`, `SE-C`); a rule per lane in `layout.md`, `app-shell.md`, `tooling.md`, `input-focus.md`; CLAUDE.md's defaultless lists (`orderFrontAndMakeKey()` on `PlatformWindow`, `activate()` making `Platform`'s seven), the divergence figures, the human-checks group list (`WA`) and the Counts line; `AGENTS.md` re-copied.

## 3. Counts and the panel-test finding

Measured on the merged tree after `swift package clean` and a native build (0 `error:`): `Test run with 4576 tests in 12 suites passed` with `AppKitPresentationTests` skipped (its 9 tests add to 4585). Master `65e300a0`, same method unfiltered, read `4534 tests in 12 suites failed ... with 5 issues`: exactly the five sheet tests (`appKitOpenDialogIsASheetWithTheDeclaredTypes`, `appKitSaveDialogCarriesTheNameTypesAndExportPrompt`, `appKitCancelledDialogArrivesAsQueuedInput`, `appKitDismissPresentationEndsTheSheetAndAnswersNothing`, `appKitSecondDialogWhileASheetIsUpAnswersFalse`), each failing after 61 s on `turn { nsWindow.attachedSheet != nil }`, the "known locked-screen failures" commit `4b135eed` names. So the branch adds 51 tests.

On the branch the **unfiltered** run did not finish, twice: the sheet tests failed after 61 s as on master, then the process sat at 0% CPU for over eight minutes inside `NSOpenPanel.init` (`-[NSSavePanel _initBridgeAndStuff]`) called from `appKitSecondDialogWhileASheetIsUpAnswersFalse` (`AppKitWindow.presentFileDialog`, `AppKitPresentations.swift`). Run alone (`--filter appKit`, 33 tests), the panel tests **passed in under a second each on both master and the branch**, so the sheets work when run in isolation and the failure is order- and session-dependent. Whether the branch's hang versus master's five clean failures is caused by a lane (no lane touches `AppKitPresentations.swift`, but `WA-` added `orderFrontAndMakeKey()` to `AppKitWindow`) or by the machine (other swift-test processes of other projects ran during the branch runs) was **not settled**: two branch runs hung, one master run did not. A rerun on an unlocked, idle session is owed.

Guards: `FR-J no-argument frame: succeeded=true` printed in the run, so the typecheck guards ran. The figure 279 is 277 plus the two `WA-` guards (one new `@Test` in `WindowActivationCompileGuards.swift`, one in `AppShellSeamCompileGuards.swift`); no grep reproduced 277 (call sites of `typecheck`/`typecheckFile` read 506 on master and 511 on the branch, `succeeded=` lines 366 in the log), so it was not re-tallied. The closeout scripts `closeout-inventory-check.sh` and `closeout-undocumented.sh` both print nothing.
