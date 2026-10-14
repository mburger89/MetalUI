# 115 — Clipboard beyond text

Branch `feat/clipboard-types` from `fb9a7e42`, merged with master `ceca59f6` (§112 SDL chrome, §111, §113) and then
`a4ebe288` (§112's depth-ranked carving). **Not a plan task**: item S3 of the gpui-gap priority list (user request
2026-10-02), MetalCreator's SDL-port gap 7 (developer-c0, 2026-10-13): MetalCreator copies and pastes graph fragments as
its own type, and the only clipboard was plain text. Spec
`docs/superpowers/specs/2026-10-14-clipboard-types-design.md`; rulings `CB-A`…`CB-Q` in the new decisions doc
`docs/superpowers/2026-10-14-clipboard-types-decisions.md` (next unused `CB-R`); probes
`docs/probes/swiftui-clipboard-types.swift` and `docs/probes/sdl-clipboard-data.c`.

**Numbering.** Written as §115 on 2026-10-14; master's highest record was §113 (no §110 or §114 on disk) and published no §115
before either merge, so the number stands. The human-checks group is **CB**, the divergence
labels are **455** and **456** (this branch's reserved range 455–464; the header's next-label line is the merge's).

**Status: LANDED — every agent-doable clause is built; the looks and the cross-process paste are owed to a human**
(`docs/verification/human-checks.md` group CB, §7). Two lanes, each red first, each verified `ok: true`; this Record
phase re-took the suite, the counts, the inventory check and the fourteen-image comparison on the merged tree.

## §0 Baseline, design and critique (2026-10-14)

- **Baseline** at `fb9a7e42`: 3717 tests in 3 suites, 0 goldens, 234 typecheck guards; master at `a4ebe288` reads 3803 / 238.
- **Carried items.** Record §68 (`DN-`) keeps `Transferable` synchronous and drag-only; §77 (`SV-`) the platform seam's
  habit of defaultless requirements; `TI-A` the text-only clipboard, which stays. No decisions doc names a typed clipboard;
  `grep -i "clipboard"` finds only `TI-A`, `HT-` (the headless store) and the text-field tests. All discharged here.
- **Probes.** `swiftui-clipboard-types.swift` arm **S** (the three modifiers' and `PasteButton`'s signatures, and a
  separating arm that must fail to compile: a `copyable` of a non-`Transferable`) ran; **arm R** (focus routing, what is
  written, the validator's effect on the Edit menu, multi-item) printed `SKIP (locked)` on 2026-10-14 and was re-checked
  locked at the design session's close. Every ruling resting on R says **unprobed**, divergence 455 is **provisional**, and
  human check `CB1` confirms or retires them. `sdl-clipboard-data.c` ran against SDL 3.4.18 on the dummy and offscreen
  drivers: the whole API round-trips in one process with no window, the callback runs synchronously on the caller's thread,
  an absent type is `NULL`/0, a replace runs the old cleanup once (output in the header).
- **Critic round** (`CB-O`, the commit `661d99fc`): the mime of a custom identifier became lower case with percent-hex
  bytes (X11 atoms are exact, Windows registered formats and some Wayland offers case-fold, identifiers are case-sensitive);
  divergence 455 was marked provisional rather than stated; `PasteButton` and a hover-routed copy were rejected a second
  time; the SDL callback test was made a bounded wait, never a hang.

## §1 What landed

- **Public spelling** (`CB-A`, class **A**, probe arm S): `.copyable(_:)`, `.cuttable(for:action:)`,
  `.pasteDestination(for:action:validator:)` on every `StyledElement` and once on proposal content, each
  `T: MetalUI.Transferable`. `Sources/MetalUI/ClipboardModifiers.swift`.
- **The imperative API** (`CB-J`, class **M**): `Window.clipboard`, a get-only `Clipboard` with no public initialiser
  (`write(_:)` for one item or an array, `read(_:)`, `contentTypes`, `hasContent(of:)`), the same code the modifiers call.
  `Sources/MetalUI/Clipboard.swift`.
- **Routing** (`CB-B`, `CB-M`): `ClipboardAttachment`, a class box in a fifth field of `KeyboardAttachment` (every factory in
  `KeyPress.swift` carries it; `Handlers` keeps nineteen members), recorded by the focus registry and counted apart
  (`clipboardRegionCount`, never `keyPressCount`). `Window.dispatchClipboardKey` runs after `dispatchKey` (the `onKey`
  bubble) and before the context-menu key and every shortcut: exact `primary` + C/X/V, an element that holds focus or is
  an ancestor of the focused one, innermost first. A focused text field's copy, cut and paste is unchanged.
- **What is written and read** (`CB-C`, `CB-F`, `CB-P`): the first item, one representation per exported type most preferred
  first; the text fallback is the type's own `.utf8PlainText` entry. A paste reads the clipboard as one lazy `DropItem`
  and walks the **destination's** `importedContentTypes()` in order, so a `[custom, text]` destination gets the custom
  type whenever it is present; nothing importable, a `nil` initialiser, an empty validator result or an empty clipboard
  **declines** and the next stage (an App command's Paste) runs. A cut claims once its action has run.
- **The seam** (`CB-E`): four **defaultless** `PlatformWindow` requirements — `writeClipboard(_ representations:) -> Bool`,
  `clipboardTypeIdentifiers() -> [String]`, `readClipboard(identifier:) -> [UInt8]?`, `setClipboardCommands(_:)` —
  with `ClipboardRepresentation` and `ClipboardCommands` in `MetalUIPlatform/Clipboard.swift`. Implemented by AppKit,
  SDL, `HeadlessPlatformWindow` and every fake (`Tests/MetalUITests/Fakes.swift`, `PortableFakeWindow.swift`, the
  compile-guard fakes). A third-party conformer adds them (`docs/migration.md`).
- **Identifier to platform type** (`CB-D`): AppKit's identifier is the pasteboard type; SDL's is `ClipboardMime`, a pure
  portable table (`public.utf8-plain-text` is `text/plain;charset=utf-8`, the mime `SDL_GetClipboardText` asks for) plus
  `application/x-<identifier>` with each byte outside `[a-z0-9.+-]` percent-encoded; a foreign mime reads back as
  `mime:<mime>`, listed and readable, never dropped.
- **AppKit** (`AppKitPlatform.swift`, `AppKitMenus.swift`): the window owns an `NSPasteboard` (`.general` in production,
  injected for tests), writes one `NSPasteboardItem`, and `validateMenuItem` also answers from `ClipboardCommands`.
- **SDL** (`SDLBridge.c`, `SDLPlatform.swift`): `mui_clipboard_set` builds **one `malloc`'d box** (entries, mime strings,
  bytes) passed as `userdata`; the data callback only looks up by `strcmp` and returns a pointer into the box; the
  cleanup frees it once (`CB-H`, `CB-Q`). Zero-byte representations are dropped, and an all-empty write is a no-op that
  keeps the clipboard (`CB-I`). `SDLBridge.h` gained `<stddef.h>` (the Linux image caught `size_t`).
- **Enablement** (`CB-G`, divergence 455): Copy, Cut and Paste are enabled by the **presence** of a handler on the focus
  chain, or a focused text field, sent to the platform after a frame on change only; the drawn bar's Edit items read the
  same state.
- **Headless** (`CB-K`): `HeadlessPlatformWindow` keeps one representation store; its `clipboard: String?` is now a view of
  the `public.utf8-plain-text` representation so every existing test is unchanged; `TestWindow.clipboardRepresentations`
  and `TestWindow.setClipboard(_:)` are the read-backs.
- **Demo** `METALUI_CLIPBOARD_DEMO=1` (`ClipboardDemo.swift`, its own function for Windows' 1 MB stack): a source of a
  `Graph` with a text fallback, a destination showing what arrived and as which type, a text field. The default demo tree
  is unchanged.
- **Guide**: `docs/guides/input.md` "Copy and paste your own type", mirrored byte for byte as `// guide: input #8` in
  `GuideMirrorsLane1.swift` (`DG-C`); `docs/testing.md` read-backs; `docs/api-overview.md`; `docs/migration.md`.

## §2 Tests and guards, by file

| file | tests |
|---|---|
| `Tests/MetalUITestingTests/ClipboardTypesTests.swift` | 17: 1.1 copy with fallback, 1.2 no focus no write (the separating arm: a hover key region does not count), 1.3 cut, 1.4 the destination's order, 1.5 text fallback import, 1.6 decline and the next stage runs, 1.7 validator, 1.8 a focused text field keeps its keys, 1.9 `onKeyPress` and the Keymap win, 1.10 innermost wins and every keyboard factory keeps the attachment, 1.11 the drawn bar's Edit items, 1.12 `setClipboardCommands` on change only, 1.13 `Window.clipboard` round trip, empty and absent, 1.14 8 MiB byte for byte, 1.15 the text property is a view, 455's pin |
| `Tests/MetalUICrossPlatformTests/ClipboardMimeTests.swift` | 3: the round trip over built-ins, a custom, a mixed-case and a hostile identifier (the mime all lower case); either hex case and a stray `%`; a foreign mime |
| `Tests/MetalUIPlatformTests/AppKitClipboardTests.swift` | 3, on a private `NSPasteboard(name:)` released after each: write, list, read and replace; `validateMenuItem` follows `setClipboardCommands`; the general pasteboard's change count never moves |
| `Tests/MetalUITests/ClipboardDemoTests.swift` | 1: copy the graph, paste it and its text fallback |
| `Tests/MetalUITests/ClipboardCompileGuards.swift` | 2 typecheck guards: 3.1 a conformer without the four members does not compile (a default `setClipboardCommands` extension reddens it), 3.2 the spellings compile from a plain import and `Clipboard()` does not |
| `Backends/SDL/Tests/MetalUISDLTests/SDLClipboardTests.swift` | 8, `.serialized`, each clearing first, `armMainRunLoopExitCheck()`: custom type plus text fallback, cleanup once per box and no leak, empty dropped and an all-empty write keeps the clipboard, 8 MiB, two representations of one mime keep the first, a mixed-case identifier, `setClipboardCommands` records, the callback needs no main actor (a bounded wait) |
| `DemoStackBudgetTests`, `GuideMirrorsLane1` | the clipboard demo's own builder in the stack-budget loop; the guide mirror |

Typecheck guards 238 to 240 (3.1, 3.2). **Probes:** the two above. **Red runs** (each test written first and red before
its subject): lane 1's `2de0a80f` red on the unbuilt `Clipboard`, `copyable`, `cuttable`, `pasteDestination` and
`TestWindow.clipboardRepresentations`; lane 2's `034faf3d` red on `type 'SDLWindow' does not conform to protocol
'PlatformWindow'`.

## §3 Mutations

**Lane 1** (25 behavioural mutants compiled into one native build behind `CB_MUT=<id>`, run with `--skip-build`, filtered to
the 452-test clipboard-bearing set, unmutated 452 passed; the unfiltered unmutated run is §4). Every one reddened, named in the
decisions doc's "Mutation record, lane 1": M1/M1b one representation written; M2 the stage walks `keyChain`
(`aCopyOnAnUnfocusedAncestorlessElementWritesNothing`); M3a/M3b cut twice or writes nothing
(`cutWritesTheItemsThenRunsTheActionOnce`, `theInnermostHandlerOnTheChainWins`); M4 import order reversed; M5 text import
skipped; M6 paste claims with nothing imported (`aPasteWithNoImportableTypeDeclinesAndTheNextStageRuns`); M7 validator
ignored; M8/M9 the stage ordered before the text keys or the keymap; M10 chain reversed; M11 a factory drops the attachment
(`eachKeyboardModifierFactoryKeepsTheClipboardAttachment`); M12/M12b drawn-bar enablement; M13 commands sent every frame;
M14 empty representation kept; M15 headless store truncates; M16 the `clipboard` read-back; M17a/b/c the mime table,
percent-hex digits and foreign mimes; M18a/b/c AppKit's `clearContents`, copy never enabled, a write to the general
pasteboard; M20 the demo copies nothing. Two guards each rebuilt red. A predecessor's identical mutation set was found
unreverted in the worktree, reverted, and retaken.
**Lane 1 verifier** re-took four on the filtered set: A (copy drops `writeClipboard`) reddened the 13 round-trip issues,
C (chain reversed) reddened `theInnermostHandlerOnTheChainWins`; **B** (`== .primary` relaxed to `.contains(.primary)`, so
Cmd+Shift+C is claimed) and **D** (paste's empty-clipboard early return removed) **reddened nothing** (§8).
**Lane 2** (Backends/SDL, `SDLClipboardTests` filtered, tree clean after): callback size 0 reddened the round trip, replace,
empty, 8 MiB, duplicate, mixed-case and 4.2 tests; cleanup counted twice, `theCleanupRunsOnceForEveryBoxAndNoBoxLeaks`; a
main-queue hop off the main thread, `theCallbackNeedsNoMainActor` by timeout (an unconditional hop deadlocks the first
main-thread read and kills the run, so the off-main form is the instrument); empty filter removed,
`emptyRepresentationsAreDroppedAndAnAllEmptyWriteKeepsTheClipboard`; dedupe removed, `twoRepresentationsOfOneMimeKeepTheFirst`.
**A skipped `free(userdata)` stayed green**: a leak is not observable in-process (the counters are the cleanup's own); held by
review of the one `free`, not pinned.

## §4 Counts (merged tree, 2026-10-14)

**3832 tests in 3 suites, 0 goldens, 240 typecheck guards** (master `a4ebe288`'s 3803 + the branch's 29 tests, 238 + 2 guards
3.1 and 3.2; the branch's own 3746 at lane 1/2 on `fb9a7e42`'s base is 3717 + 29). `swift package clean`, then
`swift build --build-system native --build-tests`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `swift build
--build-tests` (default build system) 0 `warning:`; `FR-J no-argument frame: succeeded=true`; inventory and undocumented
scripts print nothing; census 3625 re-recorded and unchanged by the merge with `a4ebe288` (no public declaration there).
**The first merged-tree run found one real issue**: guard 3.1a's control fixture lacked window chrome's four defaultless
requirements (`setWindowDragRegions`, `performWindowAction`, `hasNativeWindowControls`, `isZoomed`, §112), so "the
control must compile" failed after the merge; the fixture carries them (`0cf607c8`) and the guard passes (its four
negatives each still fail to compile naming their member). **The re-run read exactly the five `AppKitPresentationTests`
sheet issues of `CI-AF` and nothing else**: the screen locked between the two runs (lock probe: `CGSSessionScreenIsLocked =
1`, `displayAsleep main: 1`), and the first run, on an unlocked screen, had none. So the unfiltered summary is
"3832 tests in 3 suites" with 1 issue (the guard, fixed) and then 5 (the locked sheets), and the clean pass is the
union: every test passed on one run or the other, the guard on the second.
`Backends/SDL` 30 + 133 on macOS and 30 + 130 in the `metalui-portable` image at lane 2; not re-taken after the merge
(no `Backends/SDL` file changed by it). Windows by CI.

## §5 Demo comparison

`docs/probes/demo-pixels/compare.sh <scratch> fb9a7e42 HEAD` on the merged tree (HEAD `0cf607c8`): **all fourteen images 0
differing pixels, scene identical** (default light and dark at f0 and f3, modal, animation, preview, both chrome images, the
two production images). The controls came first and read non-zero where they must (light vs dark 1048576, default vs modal
1031003, default vs animation 454895 against the older recorded 1030498 and 210027, the demo having grown since those were
taken; f0 vs f3 and chrome legacy vs proposal 0 by design). The clipboard demo is env-gated, so it enters no image. Lane 1
had taken the same comparison against `fb9a7e42` on its own tree, also 0 px.

## §6 Hazards found

- **`size_t` without `<stddef.h>`** in `SDLBridge.h`: compiled on macOS, failed in the Linux image (fixed `e86bea1c`).
- **`pasteDestination`'s closure captured the metatype** and warned on the native build; it reads `T.self` instead
  (`4c11c7d0`).
- **A mutation set left unreverted** in the worktree by an interrupted predecessor: found, reverted, retaken.
- **An unconditional main-queue hop in SDL's callback deadlocks the run** rather than reddening one test; the instrument
  hops only off the main thread.
- **Locked screen.** Arm R of the SwiftUI probe could not run twice on 2026-10-14; three rulings and divergence 455 rest on
  documentation and are marked.

## §7 Human checks owed (group CB, `docs/verification/human-checks.md`)

`CB1` SwiftUI's own behaviour (arm R); `CB2` pasting between applications and between two demo processes on macOS, Linux
X11, Wayland and Windows; `CB3` the Edit menu's enablement with the focus; `CB4` a 100 MB payload; `CB5` another application
taking the clipboard. Record §03 carries the same list.

## §8 Deferred, with owners

Owner **S3b** in the gpui-gap list, reasons in `CB-N`: `PasteButton` (its look and the macOS 15 paste prompt are unprobed on
a locked screen; a `Button` over `Window.clipboard` composes in six lines), `@Environment(\.clipboard)`, lazy or promised
export (the callback's thread), multi-item copy and paste (divergence 456), change observation, the X11 primary selection,
image and file-URL constants, Insert-key shortcuts, a hover-routed copy. **Unpinned, carried to S3b:** the exact-modifier
rule of `CB-B` (no test sends Cmd+Shift+C or Cmd+Option+V to a focused `copyable`; mutation B survived) and the paste
stage's `item.types.isEmpty` early return (mutation D survived; probably equivalent, since `importClipboardItem` returns
`nil` on an empty item). **Not re-taken at the Record phase:** the Linux image (30 + 130 at lane 2; the merge touched no
`Backends/SDL` file) and Windows, which is CI's.
