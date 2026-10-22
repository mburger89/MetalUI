# 142 — Clipboard extras: PasteButton, several items, lazy export

Branch `feat/clipboard-extras` from `5f03ab7b`, merged with master `d062168c` (the D1 divergence recount, docs only) at the Record phase.
**Not a plan task**: round 2 item 6 of the gpui-gap list, requested by the user on 2026-10-21; it discharges `CB-N` (record §115), which deferred
`PasteButton`, `@Environment(\.clipboard)`, multi-item and lazy export. Spec `docs/superpowers/specs/2026-10-22-clipboard-extras-design.md`; rulings
`CP-A`…`CP-O` in the new decisions doc `docs/superpowers/2026-10-22-clipboard-extras-decisions.md` (next unused `CP-P`); probes
`docs/probes/swiftui-clipboard-extras.swift`, `sdl-clipboard-update.c`, `appkit-pasteboard-provider-retention.swift`; human-checks group **CP**.

**Numbering.** Written as §142 on the assignment of the orchestrator (siblings: §140 C14-j, §141 item 5 `drawText`). Master published no record 142
before this merge, so §142 stands. Divergence labels 715–717 are taken from this branch's reserved range 715–724 (718–724 unused); the header's
count and next-label line are left to the merge (the live count is 164 at the header, 167 with these three; 456 stays live, amended).

**Status: LANDED — every agent-doable clause is built; what an agent cannot see is owed to a human** (group CP, §8). Two lanes after a seam step, each
red first, each verified `ok: true` by a checker; this Record phase re-took the suite on the merged tree (§5).

## §0 Baseline, design session and critic round

- **Baseline** at `5f03ab7b`: **4248 tests in 3 suites** (as the native build system prints), 0 goldens, 261 typecheck guards, public census 3749 rows, 164 live
  divergences.
- **Carried items.** `CB-N` (record §115): not built — `PasteButton`, `@Environment(\.clipboard)`, lazy export, multi-item. All four are discharged
  here: three built, one ruled not built.
- **Probes.** `swiftui-clipboard-extras.swift` (2026-10-21): arm **S** compiles the SDK's three `PasteButton` initialisers and the array signatures of
  `copyable`/`cuttable`/`pasteDestination`; the separating arms `-DNEG1` (`EnvironmentValues` has no `clipboard` on macOS), `-DNEG2` (`PasteButton`
  takes no label) and `-DNEG3` (a non-`Transferable` payload) each fail to compile. **Arm R** (behaviour in a hosting window: how many pasteboard
  items an array copy writes, what a multi-item paste delivers, `PasteButton`'s enablement and look) **never ran**: the window did not become key from a
  command-line process although the lock probe read unlocked. Every ruling that rests on R says *unprobed*; human check CP1 re-takes it.
  `sdl-clipboard-update.c` (measured, dummy and offscreen drivers): an own set, a text set and a clear each post exactly one
  `SDL_EVENT_CLIPBOARD_UPDATE` with no window; the data callback runs at **read** time; one callback and one mime list per set, so there are no items.
- **Critic round** (`CP-J`…`CP-L`): divergence 456 was retired on an unprobed claim, so it is **amended, not retired**; the `PasteButton` retention
  hazard is a named refusal, not a fingerprint field; two lanes, not three (`CP-K`); the migration note counts four requirements, not seven.

## §1 What landed

- **`@Environment(\.clipboard)`: not built** (`CP-A`). SwiftUI on macOS has no such key (`-DNEG1`); no spelling was invented. `Window.clipboard` (`CB-J`,
  class `M`) stays the route from code; `docs/api-overview.md` lists the absence.
- **`PasteButton`** (`Sources/MetalUI/PasteButton.swift`, `CP-B`): SwiftUI's `PasteButton(payloadType:onPaste:)` (class A) and
  `PasteButton(supportedContentTypes:payloadAction:)` (class D: MetalUI's lazy `DropItem` stands where `NSItemProvider` does); the macOS-deprecated
  `validator:` form is not built. A `Button` underneath: one hitbox, focusable, `ControlKeys` Space/Return, the `.disabled` gate, `.buttonStyle`
  honoured, role `button`, so **no new `AccessibilityRole` and no bridge row**; no label. Look: a bordered "Paste" button (divergence 717). Enabled iff
  some clipboard item offers a type that satisfies one of the payload's imported types (by presence, never the validator, `CB-G`). A click reads
  **every** importable item and calls the action once with the array. It does **not** go through `dispatchClipboardKey`, so `Cmd+V` routing and the
  stage's order are unmoved.
- **The snapshot** (`CP-M`): a `ClipboardAccess` class (weak over the platform window, stamped on each `Frame`) holds the clipboard's type lists and a
  stale flag. The **first `PasteButton` that lays out reads the platform**; later layouts reuse it; the platform's change handler only invalidates. A
  window with no button never reads (`testingClipboardReads == 0`). `Frame` carries no snapshot field; the read inside layout is idempotent and writes
  no state.
- **Change notification** (`CP-G`, internal, not public API): the defaultless `setClipboardChangeHandler`. **SDL** turns `SDL_EVENT_CLIPBOARD_UPDATE`
  into the handler call (`SDLBridge.c` one case). **AppKit has no notification**: the platform compares `NSPasteboard.changeCount` on
  `NSWindow.didBecomeKey`, after its own write, and at each mouse-down and key-down (an `Int` compare). **Headless** fires on a write that changes the
  store, never on an identical one. `Window` dirties itself **only when the last build held a `PasteButton`** (`lastPasteButtonCount`, counted apart
  the way `clipboardRegionCount` is).
- **Retention** (`CP-H`, `CP-L`): a `PasteButton` under an `.equatable()` occurrence refuses retention by name and counts it. The taint reason the code
  uses is **`pasteButton`** (`Frame.notePasteButton`, the prepaint log; the decisions doc's `pasteButtonUnderRetained` was a working name). Three
  sites carry it (paint-recorder `taintRetention`, the prepaint log's taint, the graft journal); **each alone is redundant** (test 1.9 stays green
  with any two removed), only all three removed redden it. `RetainedSubtreeInternalTests`' field classification gains `clipboardAccess` (frame
  local) and `pasteButtonCount` (prepaint only).
- **Several items** (`CP-C`, `CP-D`): `copyable`, `cuttable` and `Clipboard.write(_ items:)` write **every** item; a `pasteDestination` imports every
  clipboard item it can (skipping the rest, declining when none imports, `CB-P`), runs the validator over the array and calls the action once with the
  accepted values in order. New class-M API `Clipboard.readAll(_:)` and `Clipboard.itemCount`; `read(_:)` and `contentTypes` still mean item 0.
  **AppKit**: N `NSPasteboardItem`s through one `writeObjects` (`AppKitClipboardItems.swift`). **SDL holds one mime set per clipboard**
  (probe): item 0 goes out under its ordinary mimes, so another application pastes the first item; **when more than one item is written** a private
  mime `application/x-com.metalui.clipboard-items` carries a framed `ClipboardItemPack` of all items (`MetalUIPlatform`, portable, Foundation-free,
  bounded: 1024 items, 1024 representations an item, 1 MiB a type name, 64 MiB total; a malformed pack decodes `nil`, never traps, and the single
  native item stands). A one-item write adds no pack: byte for byte `CB-H`'s box (divergence 715).
- **Lazy export** (`CP-F`, `CP-N`, `CP-O`): `ClipboardBytes` is `.now([UInt8])` or `.later(@MainActor () -> [UInt8])`. **AppKit** writes `.later` through
  `NSPasteboardItem.setDataProvider`; the provider runs the closure on read, hopping with `DispatchQueue.main.sync` from another thread (a main-thread
  reader runs it in place), and the window keeps its providers (insurance only, `CP-O`). **SDL stays eager**: a Swift closure cannot run in its
  pure-C data callback and a main-queue hop deadlocks a main-thread read (`CB-Q`), so `Window` realises every `.later` at write. **Headless** follows
  AppKit (`HeadlessPlatform.Options.clipboardExportsLazily`, default `true`) and counts (`TestWindow.clipboardExportCount`). `copyable` and `cuttable`
  capture the **values** and defer only the encoding; `Clipboard.write` and `TestWindow.setClipboard(items:)` encode now and keep `CB-I` exact. A lazily
  encoded representation that exports zero bytes is **listed** and reads `nil` (divergence 716).
- **The seam** (`CP-E`): four **defaultless** `PlatformWindow` requirements — `writeClipboard(items:)`, `clipboardItems()`, `readClipboard(item:identifier:)`,
  `setClipboardChangeHandler(_:)` — and the public `ClipboardItem`, `ClipboardPayload`, `ClipboardBytes`. AppKit, SDL, `HeadlessPlatformWindow`
  (its clipboard moved to `HeadlessPlatformWindow+Clipboard.swift`) and every fake implement them; `docs/migration.md` has the note. The `CB-E` four stay and
  mean item 0.
- **Demo** (`METALUI_CLIPBOARD_DEMO=1`, `ClipboardDemo.swift`): a pair source copying two graphs, a pair destination listing everything received, and a
  `PasteButton(payloadType: Graph.self)` dimmed until a graph is on the clipboard, in its own function (the 1 MB stack rule). The default tree and the
  fourteen images do not move.
- **Guide** (`docs/guides/input.md`): two blocks (`#9` family) mirrored byte for byte in `GuideMirrorsClipboard.swift` (`DG-C`).

## §2 Tests and guards, per file

Count 4248 → **4277** (+29 tests; the checker's lane-1 reading was 4263, lane 2 adds 14), typecheck guards 261 → **263** (G1.1 and G2.1; guard 3.1's fixture gained the four requirements).

| file | what it pins |
|---|---|
| `Tests/MetalUITestingTests/PasteButtonTests.swift` (9) | enablement follows the clipboard through the handler alone; a click delivers every decoded item once; the `supportedContentTypes` form matches by conformance and delivers `DropItem`s; gated and focusable like a `Button`; a change dirties only a window holding a button; one labelled button node; `Cmd+V` runs the destination, not the button; the headless handler fires only on a change; a button under a retained component still follows the clipboard (1.9) |
| `Tests/MetalUITestingTests/ClipboardItemsTests.swift` (7) | two-item round trip in order; skip and decline (`CB-P`); validator over the whole array; a cut of several runs once and writes all; `readAll`/`itemCount`/empty write; lazy versus eager export counts; an empty lazy representation listed and reading `nil` |
| `Tests/MetalUIPlatformTests/AppKitClipboardChangeTests.swift` (2) | a foreign write fires the handler at becoming key, a mouse-down and a key-down and never on an unchanged count; an own write calls it once and a removed handler never (private `NSPasteboard(name:)`, `CB-K`) |
| `Tests/MetalUIPlatformTests/AppKitClipboardItemsTests.swift` (3) | N items written, listed by item and read by `(item, identifier)`; a lazy type exported by the read, from another thread without a hang; `.general` never touched |
| `Tests/MetalUICrossPlatformTests/ClipboardItemPackTests.swift` (3) | round trip of three items, an empty one and a hostile name; `nil` on every violation; the ruled limits and mime |
| `Backends/SDL/Tests/MetalUISDLTests/SDLClipboardChangeTests.swift` (1) | own set, text set and clear each call the handler once (`armMainRunLoopExitCheck()`) |
| `Backends/SDL/Tests/MetalUISDLTests/SDLClipboardItemsTests.swift` (4) | one item writes no pack; three items write item 0 natively plus the pack and read by `(2, id)`; a malformed pack falls back to the single item; `.later` exported at write |
| `Tests/MetalUITests/ClipboardDemoTests.swift` (+1) | the two-graph demo and its button |
| `Tests/MetalUITestingTests/GuideMirrorsClipboard.swift` (2) | the two guide blocks |
| `Tests/MetalUITests/PasteButtonCompileGuards.swift` (guard G1.1) | spellings compile from a plain import; a label and a misspelling do not |
| `Tests/MetalUITests/ClipboardItemsCompileGuards.swift` (guard G2.1) | `ClipboardItem` case spellings reachable, `readAll` present, `ClipboardItemPack` unreachable |
| `Tests/MetalUITests/ClipboardCompileGuards.swift` | guard 3.1's fixture gains the four requirements; its `PasteButton` negative (valid while unbuilt) is retired to G1.1 |

(The per-file figures count functions; parameterised arms make the suite delta differ.) Fakes in `Fakes.swift`, `PortableFakeWindow.swift` and six other
guard fixtures gained the four requirements. Inventory: three map rows (`paste-button` class D, the seam family, the headless clipboard file) and
amended `clipboard`/`clipboard-modifiers` rows; census 3749 → 3784 rows; `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

## §3 Probes

`swiftui-clipboard-extras.swift` (arms S, NEG1–NEG3 recorded; R unrun), `sdl-clipboard-update.c` (recorded output in its tail),
`appkit-pasteboard-provider-retention.swift` (recorded in its header: the pasteboard or its item retains a provider written by `writeObjects`).

## §4 Red runs and mutations

Every test was written first and red on the unbuilt subject (compile failures count): lane 1 at `0aed6070`, lane 2 at `64ab7202`/`16301dad`.

**Lane 1** (checker, one full unfiltered suite per batch, each batch's reddened set equal to the union of the implementer's per-mutation sets, no
collateral red):

| mutation (spelling) | reddened |
|---|---|
| A+B+H1: enablement always on; a click delivers `prefix(1)`; the headless handler fires on every write | `aPasteButtonIsEnabledOnlyWhileTheClipboardHoldsWhatItImports`, `aPasteButtonIsOneLabelledButtonNodeThatFollowsEnablement`, `aPasteButtonUnderARetainedComponentStillFollowsTheClipboard`, `theSupportedContentTypesFormMatchesByConformanceAndDeliversDropItems`, `aClickDeliversEveryDecodedItemOnce`, `theHeadlessChangeHandlerFiresOnlyOnAChange` |
| C+E+H3+I3: exact type match instead of `satisfies`; dirty on every change; AppKit own write does not record `changeCount`; all three retention taints removed | `theSupportedContentTypesFormMatchesByConformanceAndDeliversDropItems`, `aClipboardChangeDirtiesOnlyAWindowHoldingAPasteButton`, `anOwnWriteCallsTheHandlerOnceAndARemovedHandlerNever`, `aPasteButtonUnderARetainedComponentStillFollowsTheClipboard` |
| D+F+G+H2: outer `.disabled` ignored by the gate; label dropped; `keyboardShortcut("v")` on the button; AppKit poll count off by one | `aPasteButtonIsGatedAndFocusableLikeAButton`, `aClickDeliversEveryDecodedItemOnce`, the enablement, labelled-node and retained tests above, `commandVRunsTheDestinationAndNotThePasteButton`, `aForeignWriteFiresTheHandlerAtBecomingKeyAMouseDownAndAKeyDown`, `anOwnWriteCallsTheHandlerOnceAndARemovedHandlerNever` |
| J (Backends/SDL, `SDLClipboard` set): the `SDL_EVENT_CLIPBOARD_UPDATE` case returns false in `SDLBridge.c` | `anOwnSetATextSetAndAClearEachCallTheHandlerOnce` |

Batching means attribution is by test name against the implementer's single-mutation table; `commandVRunsTheDestinationAndNotThePasteButton` is
attributable to G (it is not in F's set). G was not run alone. **Test 1.9's three retention taints are mutually redundant** (each alone reddens
nothing, all three together redden it); the doc comment says so.

**Lane 2** (implementer's table by the mutation each test's doc comment names; the checker re-ran only 2.1, reproducing its two reddened tests):

| mutation | reddened |
|---|---|
| 2.1 `copyable` writes the first item only (`ClipboardModifiers.swift` line 140 `writeClipboard(items: [items[0]])`), re-run by the checker on the `ClipboardItems`/`ClipboardDemo` set | `aCopyOfTwoItemsWritesTwoAndAPasteReceivesBothInOrder`, `theClipboardDemoCopiesTwoGraphsAndAPasteButtonPastesThem` |
| claim the key with an empty array; validate only the first value; run the action twice; `itemCount` from item 0; realise every `.later` at copy; drop an empty lazy representation at the read | the test whose doc comment names it, in `ClipboardItemsTests.swift` |
| AppKit: `clearContents()` once per item; the off-main hop dropped; write to `.general` | `nItemsAreWrittenListedByItemAndReadByItemAndIdentifier`, `aLazyRepresentationIsExportedByTheReadEvenFromAnotherThread`, `theItemsPathNeverTouchesTheGeneralPasteboard` |
| SDL: always write the pack; skip the pack or list its type; trust a bad pack; skip the realise | `oneItemWritesNoPack`, `threeItemsWriteItemZeroNativelyAndThePackForTheRest`, `aMalformedPackFallsBackToTheSingleItem`, `aLaterRepresentationIsExportedAtWrite` |
| pack: skip the `take` bounds check; change the mime string; count representations as items | the three `ClipboardItemPackTests` |
| **2.10 survives**: the window's provider retention removed | **none** — an equivalent mutant on this macOS (`CP-O`: `NSPasteboard` retains the provider itself, probe `appkit-pasteboard-provider-retention.swift`); no pin can be built, the property is insurance |

The headless **listing** half of the empty-lazy rule has no mutation: the listing never drops a representation, so only the read half (`nil` for empty
bytes) is guarded and mutated.

## §5 Verification at the Record phase

Merged `origin/master` `d062168c` (docs only), then `swift package clean`, native build and native unfiltered `--no-parallel` run on a **locked screen**
(§10).
Taken by the lane checkers at their heads and not re-taken here: `Backends/SDL` on macOS (`SDLClipboard` set 9 tests in 2 suites at lane 1; lane 2 adds
five), the Linux image `metalui-portable` (248 tests in 12 suites at lane 1), the fourteen offscreen images against `5f03ab7b` (all scene identical,
`differing=0`, at lane 1; no `Sources/` or `Backends/` file moved after `f8705dcd` except through the lane-2 head the checker re-read), the
verify-switch run (`METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, 4263 in 5 suites at lane 1). **Owed on the merged tree at the end of the item:**
the SDL macOS and Linux-image runs and the fourteen-image comparison (the merge brought no source).

## §6 Hazards and findings

- **Stale enablement between presses on AppKit.** The change poll runs at becoming key, own writes, mouse-down and key-down; a foreign write while the
  window is key and idle shows at the next press. Pinned by name; nothing measures a real window (CP4).
- **A read of the platform inside layout** (`CP-M`): the one exception to "never read the platform inside a phase"; one read per clipboard change per
  window holding a button.
- **SDL multi-item is MetalUI-to-MetalUI** (715): another application sees item 0 only. A hostile or truncated pack is ignored.
- **Lazy export timing differs by platform** (716): the exporter runs at read on AppKit and headless, at write on SDL. A `Transferable` whose exporter reads
  mutable external state sees it at paste time on AppKit.
- **Retention taints are redundant** (§4); removing two of three leaves the refusal intact.
- **The decisions doc's working name `pasteButtonUnderRetained`** differs from the code's taint reason `pasteButton`; CP-H is amended in this commit.
- **`NSPasteboard` retention of the provider is undocumented** (`CP-O`): the window keeps its own references anyway.

## §7 Divergences

New: **715** (several items on SDL), **716** (when a copy's bytes are encoded), **717** (`PasteButton`'s look and no paste prompt). **Amended: 456**
(`CP-J`: was "one item per clipboard"; now "whether SwiftUI writes and receives several items", unprobed, stays live until CP1). Labels 718–724 of this
branch's range unused. Section in record §04.

## §8 Looks owed — human-checks group CP

No real window was driven (arm R never became key; an agent cannot compare a look). **Owed, new here, none performed**: CP1 re-take arm R where a window
becomes key (array copy item count, a two-item paste, `PasteButton`'s enablement on a foreign pasteboard; retires or rewrites 456, 715's AppKit side, 716
and `CP-B`'s enablement), CP2 the `PasteButton` look beside SwiftUI's (light and dark, focus ring, pressed, disabled), CP3 a two-item paste between two real
applications and between two MetalUI windows on Linux X11/Wayland and Windows (the pack), CP4 a clipboard manager rewriting the clipboard while the window
is key.

## §9 Deferred, with owners

`@Environment(\.clipboard)` (no SwiftUI API, owner none); the deprecated `validator:` `PasteButton` (owner none); a `PasteButton` label or look beyond
`Button` (CP2); lazy export on SDL (blocked by the main-actor and pure-C rules, owner none); a public clipboard change observation API (not SwiftUI);
image and file-URL content-type constants and `Image` as `Transferable` (own item, `CB-N`); the X11 primary selection; a lazy `Clipboard.write` overload
(additive, `CP-N`). Real-window and Windows runs are human checks.

## §10 Counts and the measured run

**2026-10-22, `feat/clipboard-extras` at the Record phase** (merged with master `d062168c`; the record, docs and `CLAUDE.md`/`AGENTS.md` edits were in the tree
for the run): `swift package clean`, `swift build --build-system native --build-tests` 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
native unfiltered `--no-parallel` run, one summary line: **`Test run with 4277 tests in 5 suites failed after 979.597 seconds with 5 issues`** — the five
issues are exactly the `AppKitPresentationTests` sheet issues of `CI-AF` (lines 120, 139, 161, 183, 200), the screen being locked
(`CGSSessionScreenIsLocked = 1`), and nothing else; `FR-J no-argument frame: succeeded=true`. `swift build --build-tests` on the default build system:
**0 `warning:`, 0 `error:`**. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; `closeout-public-api.sh` regenerates the checked-in
census byte for byte (3784 rows). **Counts: 4277 tests, 0 goldens, 263 typecheck guards.** Not re-taken at the Record phase (see §5): the
`METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` run, the fourteen-image comparison, `Backends/SDL` on macOS and the Linux image, and an unlocked
screen re-take of the five sheet tests.
