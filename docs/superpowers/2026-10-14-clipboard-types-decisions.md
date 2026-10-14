# Clipboard beyond text — decisions

Rulings for item S3 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**),
MetalCreator's SDL-port gap 7. Prefix `CB-`. **Next unused: `CB-R`.**
Spec: [`specs/2026-10-14-clipboard-types-design.md`](specs/2026-10-14-clipboard-types-design.md).
Record: `../record/115-clipboard-types.md` (Record phase). Branch `feat/clipboard-types` from
`fb9a7e42`. Divergence labels reserved 455–464: **455 taken** (`CB-G`), **456 taken** (`CB-C`).

Sources of truth. SwiftUI: `docs/probes/swiftui-clipboard-types.swift` — the **signatures** of
`copyable`, `cuttable`, `pasteDestination`, `PasteButton` and the compile-time Transferable
constraint (arm S plus a separating arm). Its behavioural arm R (focus routing, what is written,
validator effect) could not run: the screen was locked. Every ruling resting on R says
**unprobed** and is a human check (`CB1`). gpui, where SwiftUI has none: gpui has
`ClipboardItem` (a list of text/image entries) and `cx.write_to_clipboard` / `read_from_clipboard`
— **recalled from memory, the gpui source is not on this machine**; a design precedent for
`CB-J`'s imperative API only. SDL: `docs/probes/sdl-clipboard-data.c` (measured, SDL 3.4.18, dummy
and offscreen drivers) and `SDL_clipboard.h`.

## CB-A — SwiftUI's modifier spellings, on MetalUI's synchronous `Transferable`

**Question.** What is the public spelling?
**Ruling.** `.copyable(_ items: @autoclosure @escaping () -> [T])`, `.cuttable(for:action:)`
(`action: () -> [T]`) and `.pasteDestination(for:action:validator:)` (`action: ([T]) -> Void`,
`validator: ([T]) -> [T]`, defaulting to identity) on every `StyledElement` and, once, on proposal
content (the `KeyboardModifier` layer, `KF-H`), each `T: MetalUI.Transferable`. Signatures are
SwiftUI's (probe arm S); the constraint is MetalUI's own `Transferable` (`DN-B`), a file importing
CoreTransferable spells `MetalUI.Transferable` (as for `draggable`). `PasteButton` is **not built**
(`CB-N`).
**Cost if wrong.** A spelling change after release breaks callers; low, the shapes are SwiftUI's.

## CB-B — Routing: the focus chain, after the field and `onKey`, before shortcuts

**Question.** Which key reaches a clipboard handler, and where in `Window.onInput`'s ladder?
**Ruling.** The three modifiers fire on `EventModifiers.primary` + `C`/`X`/`V` (exact modifiers; `SG-B`)
for an element that **holds focus or is an ancestor of the focused element**, innermost first
(the opposite of `onKeyPress`, the same as `onKey`: a copy is the nearest owner's). One new stage
`dispatchClipboardKey` runs after `dispatchKey` (the raw `onKey` bubble) and before
`dispatchContextMenuKey`/`dispatchShortcut`. So: the Keymap and `onKeyPress` still see the key first
(an app rebinds ⌘C), a focused `TextField`/`TextEditor` keeps its own copy, cut and paste unchanged
(`TI-D`; text input must not move), and a `Button` shortcut or an App command bound to the same key
runs only when no handler claimed it. The Edit menu needs no code: AppKit's `cut:`/`copy:`/`paste:`
and the drawn bar's Edit items already deliver exactly these keys (`MN-K`, `SG-H` item 2). The key chain
of `hoverKeyRegion` is **not** used (`KF-U`: it feeds only the keymap and `onKeyPress`); a clipboard
handler needs focus, which `copyable` does not give (add `.focusable()`; a click does not focus,
divergence 94). SwiftUI's own routing (responder-chain `copy:` to the focused view) is **unprobed**
(R); human check `CB1`.
**Cost if wrong.** If SwiftUI routes by hover or without focus, ports silently lose a copy; fixed by
widening the chain, no seam change.

## CB-C — What is written: one representation per exported type; the text fallback is the `Transferable`'s own

**Question.** How does an app offer its own type plus plain text?
**Ruling.** A copy writes, for each item, one clipboard representation per exported type that
exports (`Transferable.dragRepresentations()`'s rule, `DN-H`), most preferred first. The fallback
is not a parameter: a type that wants plain text lists `.utf8PlainText` after its own type in
`exportedContentTypes()` and returns UTF-8 from `exported(as:)`. Multiple items: the **first** item
is written (the clipboard here is one item; SwiftUI's array form writes several pasteboard items on
AppKit — **unprobed**, `CB-N` carries multi-item). An empty array, or items exporting nothing,
**clears nothing and writes nothing** (`CB-I`). A write replaces everything the clipboard held,
text included, as `writeClipboard(_:)` does. **Divergence 456**: `copyable([a, b])` and `cuttable` returning several write only the first, and a paste action receives at most one value (SwiftUI's array is unprobed; arm R). Reason: one clipboard item here.
**Cost if wrong.** A multi-item destination on another platform sees one item; low.

## CB-D — Identifier ↔ platform type

**Question.** How does a `ContentType` become a UTI and a mime type?
**Ruling.** AppKit: the identifier **is** the pasteboard type (`NSPasteboard.PasteboardType(identifier)`;
a reverse-DNS string an app declares needs no registration to be written and read, and
`public.utf8-plain-text` is `NSPasteboard.PasteboardType.string`). SDL: a pure, portable table in
`MetalUIPlatform` (`ClipboardMime`): `public.utf8-plain-text` ↔ `text/plain;charset=utf-8` (the exact
mime `SDL_GetClipboardText` asks for, probe), `public.plain-text` ↔ `text/plain`, `public.json` ↔
`application/json`, `public.url` ↔ `text/uri-list`, `public.data` ↔ `application/octet-stream`;
every other identifier ↔ `application/x-` + the identifier with each byte outside
`[a-z0-9.+-]` (so every upper-case letter too) percent-encoded as `%xx` (lower-case hex), decoded on the way back, accepting either hex case. The mime is then all lower case and survives a platform that case-folds mime types (X11 atoms are exact, Windows registered formats and some Wayland offers are not); identifiers are case-sensitive, mimes are not. A mime with no entry and
no `application/x-` prefix (e.g. `image/png`) reads back as the identifier `mime:` + the mime, so a
foreign type is listed and readable by a destination that names it, never dropped. The round trip
`id → mime → id` is the identity for every `ContentType` (a test over the built-ins, a custom id and a
hostile one).
**Cost if wrong.** An app on another toolkit expecting a different mime for a custom type cannot read
it; the table is one function and `application/x-<id>` is the rule the item asked for.

## CB-E — The seam: four defaultless `PlatformWindow` requirements

**Ruling.** `PlatformWindow` gains, **without defaults** (a conformer that forgets fails to compile;
migration note in `docs/migration.md`): `writeClipboard(_ representations: [ClipboardRepresentation]) -> Bool`
(replaces everything; `true` when the platform accepted at least one),
`clipboardTypeIdentifiers() -> [String]` (most preferred first, as the platform lists them),
`readClipboard(identifier: String) -> [UInt8]?` (`nil` when absent) and
`setClipboardCommands(_ commands: ClipboardCommands)` (an `OptionSet` cut/copy/paste: what the focus
chain can currently do, sent on change only after a frame, for AppKit's menu validation, `CB-G`).
`ClipboardRepresentation` is `{ type: PasteboardType, bytes: [UInt8] }`, `Sendable, Equatable`.
`readClipboard() -> String?` and `writeClipboard(_ text:)` stay and keep text fields' path byte for
byte. The clipboard is process-global on every real platform; it lives on the window because the
seam's other services do. `HeadlessPlatformWindow` and every test fake implement all four (`HT-X` 1).
**Cost if wrong.** A fifth requirement later is another migration note; accepted.

## CB-F — Paste is one `DropItem` through the one import path

**Question.** How does `pasteDestination` choose a type, and what when the type is absent?
**Ruling.** The clipboard is read as **one `DropItem`** whose `types` are the platform's identifiers
(each a `PasteboardType` with `conformsTo` empty, except the table's built-ins in `CB-D`, which carry
their parents) and whose lazy `load` is `readClipboard(identifier:)`. It then runs through
`DropDestinationTarget`'s existing `match` and `T(importing:contentType:)` (`DN-S`): the destination's
`importedContentTypes()` order decides, the **destination's** type is what `init?(importing:)` is told,
and a `T` importing `[custom, utf8PlainText]` falls back to text with no new rule. When nothing
imports, the key is **declined** (no action, no write), so later stages run (an App command's Paste).
A `nil` from `init?(importing:)` for every offered type is the same decline. Reading is lazy: only
the chosen type's bytes are fetched.
**Cost if wrong.** None observable beyond `DN-S`'s own.

## CB-G — The validator and the Edit menu's enablement

**Ruling.** `validator` runs on the imported values at paste time; an empty result declines, a
non-empty one is passed to `action` and the key is claimed. Enablement is by presence: Copy is
enabled when a `copyable` is on the chain, Cut a `cuttable`, Paste a `pasteDestination` — or a
focused text field, as today. A destination whose validator would reject the current clipboard
therefore shows Paste enabled and does nothing. SwiftUI disables it (documented behaviour, **unprobed**
here). **Divergence 455** (MetalUI-only enablement), **provisional**: it rests on SwiftUI's documented disabling, which no probe has measured (arm R needs an unlocked screen; re-checked 2026-10-14, still locked). The divergences.md row says so and CB1 confirms or retires it. Reason: the clipboard changes outside the
frame and AppKit's `validateMenuItem` has no frame to read; polling per menu open would need a
fifth requirement and a synchronous read of foreign data on the main thread.
**Cost if wrong.** A Paste item enabled with nothing to paste; cosmetic.

## CB-H — SDL's data callback: eager snapshot, pure callback, cleanup frees

**Question.** Who owns the bytes SDL asks for, and on which thread is the callback called?
**Evidence.** Probe: `SDL_GetClipboardData` of our own data calls our callback synchronously on the
caller's thread; a remote request (X11 selection, Wayland data offer, Windows delayed render) is
served from SDL's event pumping on the thread that pumps (the main thread, `SDL_clipboard.h`'s
threadsafety note: set on the main thread); the returned pointer "will not be freed" and must stay
valid; the cleanup runs when new data is set, the clipboard is cleared or `SDL_Quit`.
**Ruling.** `Synchronous Transferable` means the bytes exist at copy time (`CB-C`): the bridge
copies every representation into one malloc'd box (`mui_clipboard_set(items, count)`: a struct of
mime strings and byte ranges), passes it as `userdata`, and the callback does a lookup by mime and
returns a pointer **into the box** with the size — no Swift closure, no actor hop, no allocation, so
it is correct on whichever thread SDL calls it. The cleanup callback frees the box exactly once. A
mime not in the box returns `NULL`, size 0 (SDL's "zero-length"). **Lazy export is not offered**
(the export closure would have to run on the main actor from a foreign thread or deadlock; `CB-N`).
**Another app owns the clipboard.** Our box is cleaned up when SDL learns we lost it (or when we
write again); reads go to the owner through `SDL_GetClipboardData`; we never hold stale data.
`SDL_HasClipboardData` gates every read.
**Cost if wrong.** Copying a very large value costs one eager copy; bounded by `CB-I`'s rule.

## CB-I — Empty, large, absent

**Ruling.** A zero-byte representation is **dropped on write** (SDL's callback cannot tell empty from
absent; AppKit would write an empty item); when nothing remains the write is a no-op returning
`false` and the clipboard keeps its contents. No size cap: the bytes are the app's, SDL streams them
(X11 INCR is SDL's), AppKit's pasteboard takes `Data`. A read of an absent type is `nil`; a read of
a present empty type cannot occur. A `Transferable` whose `exported(as:)` returns `nil` for an
exported type is skipped (`dragRepresentations`' rule).
**Cost if wrong.** An app that means "an empty document" cannot put zero bytes on the clipboard;
it writes a non-empty one (a header); the item's use case does not need empty.

## CB-J — An imperative API, MetalUI-only

**Question.** What does code outside a view use?
**Ruling.** `Window.clipboard`, a get-only `Clipboard` value (`write(_ item: some Transferable) -> Bool`,
`write(_ items: [some Transferable]) -> Bool` per `CB-C`, `read<T: Transferable>(_ type: T.Type) -> T?`,
`contentTypes: [String]` and `hasContent(of:)`), running on the window's platform seam and, like
`TextMeasurer`, with no public initialiser. It is the same code the modifiers call. MetalUI-only,
class `M`; SwiftUI has none (apps use NSPasteboard). `@Environment(\.clipboard)` is the natural way a
handler would reach it and is **deferred** (`CB-N`); until then a handler captures the window it was
given, as the app shell's do. Reading must run from input (a main-actor call; it reads foreign
data and may block briefly).
**Cost if wrong.** An environment value later is additive.

## CB-K — Tests drive it headless; AppKit tests use a private pasteboard

**Ruling.** `HeadlessPlatformWindow` keeps one `[ClipboardRepresentation]` store; its existing
`clipboard: String?` becomes a computed view of the `public.utf8-plain-text` representation (get its
bytes as UTF-8; set replaces the whole store with one text representation, `nil` clears), so every
existing test is unchanged. New read-backs: `clipboardRepresentations`. `TestWindow` gains no copy verbs: a test sends `typeKey("c", modifierFlags: .primary)`, the real
path (`HT-`), and reads `TestWindow.clipboardRepresentations`; `TestWindow.setClipboard(_:)` puts
what "another app" copied. AppKit: the window owns an `NSPasteboard` (`.general` in production, injected by an
internal initialiser); every AppKit test passes `NSPasteboard(name: <unique>)` and releases it
(`releaseGlobally()`), so no test touches the user's clipboard. SDL: one test process-global, so SDL
tests serialise (`.serialized`) and clear the clipboard first; the measured skip (`CB-L`).
**Cost if wrong.** None.

## CB-L — SDL tests: real round trip in the dummy and offscreen drivers

**Evidence.** The probe shows the whole API round-trips in one process with no window on the dummy and
offscreen drivers (the generic SDL layer holds the callback; no X11/Wayland server needed). **Ruling.**
`Backends/SDL` tests do a real set/has/get/types/replace/clear round trip, on macOS and in the Linux
image, `SDL_VIDEO_DRIVER` untouched (the image sets offscreen). What cannot be tested headless —
another process reading it — is human check `CB2`. If the Linux image's X11/Wayland-less measurement
differs from the macOS one, the test is gated `.enabled(if:)` on a measured predicate and the record
says so (`CB-N`'s owner re-takes); Windows by CI.

## CB-M — Text fields and everything else stay put

**Ruling.** `Window.dispatchTextKey` and `TextEditing` are unmodified. A text field's copy writes
text through `writeClipboard(_ text:)`, which on AppKit/SDL **replaces** the custom representations
(one clipboard); a field's paste reads text only. A `copyable` ancestor of a focused field never sees
⌘C (`CB-B`). No `Handlers` member is added (stays nineteen): the three closures ride a fifth field of
`KeyboardAttachment` (`ClipboardAttachment`, a class box, `KF-I`'s way), registered where
`keyPresses` are and counted apart (`clipboardRegionCount`, never `keyPressCount`); no identity,
state, accessibility, hit-test, animation or layout code moves.
**Cost if wrong.** A `KeyboardAttachment` factory missing the new field drops a modifier chain's
clipboard; spec test 1.10 pins every factory.

## CB-O — Rejected on review: building `PasteButton` now, and a hover-routed copy

**Ruling.** Rejected again after the design critique. `PasteButton` is a third control look plus
permission behaviour (macOS 15 paste prompt) with no probe possible on a locked screen, and a button
over `Window.clipboard` composes in six lines (the guide block shows it); a hover-routed copy
contradicts `KF-U`. The deferral stays in `CB-N` with owner S3b. Also rejected: a text-fallback
parameter on `copyable` (SwiftUI has none; `CB-C`). The SDL callback test must fail by a bounded wait,
never a hang (spec 4.2).

## CB-N — Deferred, named

Not built, each with a reason and an owner (the S3 follow-up, `S3b`, in the gpui-gap list):
`PasteButton` (its look and permission behaviour are unprobed on a locked screen; compose a `Button`
over `Window.clipboard`); `@Environment(\.clipboard)` (additive); lazy/promised export
(`CB-H`: thread); multi-item copy and paste (`CB-C`); clipboard change observation / a change
count (SDL has none, AppKit's `changeCount` is not worth a requirement alone); the X11 primary
selection; image and file-URL constants (`public.png` as a `ContentType`) and `Image` as
`Transferable`; Shift-Insert / Ctrl-Insert / Shift-Delete; a hover-routed copy.

## CB-P — Paste walks the destination's types; what claims the key

**Question.** `CB-F` says the clipboard runs through `DropDestinationTarget.match`; that function walks the
*offered* types first. Which order decides on a clipboard, and which outcomes claim the key?
**Ruling.** The order is the **destination's**: `importClipboardItem` walks `T.importedContentTypes()` in
declared order and, for each, takes the first offered type that is it or conforms to it, reads those bytes and
asks `T(importing:contentType:)` (told the destination's type); an absent type or a `nil` initialiser moves on to
the next imported type. Reason: the order of `NSPasteboard.types` and of SDL's mime list is the platform's, not the
writer's, and a destination that lists `[custom, text]` must get the custom type whenever it is there (test 1.4);
the drop path keeps `match` unchanged. **Claims** (the innermost handler of a kind decides; a decline does not try
its ancestors): a copy claims the key once it has a non-empty result to write (an empty result declines, nothing is
written, a later stage runs); a cut claims once its action has run, even when it returned nothing to write (the
action's effect happened); a paste claims only when the action ran, so an empty clipboard, nothing importable and
an empty validator result all decline and an App command's Paste runs.
**Cost if wrong.** A cut that must not claim on an empty result is an `if` away; low.


## Mutation record, lane 1 (not a ruling)

Taken on `def3fdd8` plus the `T.self` warning fix: all 25 behavioural mutants were compiled into one
`--build-system native` build behind `CB_MUT=<id>` (gated reads, removed before commit) and run with
`--skip-build`, **filtered** to the clipboard-bearing set (`MetalUITestingTests`, `MetalUIPlatformTests`,
`MetalUICrossPlatformTests`, and the `MetalUITests` functions of `ClipboardDemoTests`, `MenuBarStripTests`,
`CommandsTests`, `TextFieldTests`, `TextEditingTests`, `ClipboardCompileGuards`, `AppKitDragAndDropTests`:
452 tests, unmutated 452 passed); the unmutated unfiltered suite is the 3746-test run. Every mutant reddened:
M1 copy writes one representation (the two Window round-trip tests); M1b the key path writes one (14 issues, six
tests); M2 the stage walks `keyChain` (`aCopyOnAnUnfocusedAncestorlessElementWritesNothing`); M3a cut action twice,
M3b cut writes nothing (`cutWritesTheItemsThenRunsTheActionOnce`, `theInnermostHandlerOnTheChainWins`); M4 import order
reversed; M5 text import skipped; M6 paste reports `true` when nothing imported (`aPasteWithNoImportableTypeDeclinesAndTheNextStageRuns`);
M7 validator ignored; M8/M9 stage ordered before the text keys or the keymap (`aFocusedTextFieldKeepsItsOwnCopyCutPasteUnderACopyableAncestor`,
`onKeyPressAndTheKeymapStillBeatAClipboardHandler`); M10 chain reversed (`theInnermostHandlerOnTheChainWins`); M11 a keyboard factory drops the
attachment (`eachKeyboardModifierFactoryKeepsTheClipboardAttachment`); M12/M12b drawn-bar enablement; M13 commands sent every frame
(`setClipboardCommandsIsSentOnChangeOnly`); M14 empty representation kept; M15 headless store truncates a large payload
(`aLargePayloadRoundTripsByteForByte`); M16 headless `clipboard` read-back; M17a/b/c the mime table, percent-hex digits and the
foreign-mime path (`clipboardMimeRoundTripsEveryBuiltInACustomAMixedCaseAndAHostileIdentifier`, `aForeignMimeIsListedAndReadableByItsMimeIdentifier`);
M18a missing `clearContents`, M18b copy never enabled, M18c a write to the general pasteboard
(`aWriteListsReadsAndReplacesOnAPrivatePasteboard`, `validateMenuItemFollowsSetClipboardCommands`, `theGeneralPasteboardIsNeverTouched`); M20 the demo copies nothing.
Typecheck guards, each rebuilt: a default `setClipboardCommands` extension reddens
`aPlatformWindowWithoutAClipboardRequirementDoesNotCompile` (3.1); a public `Clipboard.init()` reddens
`theClipboardSpellingsCompileFromAPlainImportAndClipboardHasNoInitialiser` (3.2). Tree clean after each (`git status --short`).
A predecessor's identical mutation set was found unreverted in the worktree and was reverted, and its results (not recorded) retaken here.

## CB-Q — SDL measured: the bridge, the Linux image and the Windows expectation

**Evidence (lane 2, 2026-10-14, `f0bcd3ca`, `e86bea1c`).** `SDLClipboardTests` (8 tests, `.serialized`, each clearing first,
`armMainRunLoopExitCheck()`) run **unfiltered and ungated** on macOS (Backends/SDL 30 + 133 pass) and in the
`metalui-portable` image on the offscreen driver (30 + 130 pass, three macOS-only): the dummy and offscreen drivers keep
the callback in SDL's generic layer, so no `.enabled(if:)` predicate is needed (`CB-L` stands, no skip to measure). The
Linux image also caught `SDLBridge.h` lacking `<stddef.h>` for `size_t`, invisible on macOS.
**Ruling.** (1) The bridge is one `malloc` holding the entries, mime strings and bytes (`mui_clipboard_set`); the data callback
only looks up by `strcmp` and returns a pointer into the box; the cleanup counts and frees. A **failed** set calls
`SDL_ClearClipboardData()` and never frees itself, so only SDL's cleanup frees the box, once, whether or not SDL stored it.
(2) Two representations that map to one mime keep the first (a callback cannot tell them apart). (3) Test counters
`mui_clipboard_cleanup_count`/`live_count`/`callback_probe` are bridge test hooks, not API. (4) **Windows is by CI**: the
Windows delayed-render path calls the callback from SDL's pumping thread, which the pure callback tolerates; unmeasured here.
(5) Pasting across processes is human check `CB2`.
**Mutations** (Backends/SDL, each committed-first, restored from a copy, `SDLClipboardTests` filtered, tree clean after):
callback size 0 reddens the round trip, replace, empty, 8 MiB, duplicate, mixed-case and 4.2 tests; cleanup counted twice
reddens `theCleanupRunsOnceForEveryBoxAndNoBoxLeaks`; a main-queue hop in the callback (off the main thread only) reddens
`theCallbackNeedsNoMainActor` by timeout (an unconditional hop deadlocks the first main-thread read and kills the run, so the
off-main form is the instrument); empty filter removed reddens `emptyRepresentationsAreDroppedAndAnAllEmptyWriteKeepsTheClipboard`;
dedupe removed reddens `twoRepresentationsOfOneMimeKeepTheFirst`. **A skipped `free(userdata)` stayed green**: a leak is not
observable in-process (the counters are the cleanup's own); it is held by review of the one `free`, and recorded here, not pinned.
**Cost if wrong.** A leak of one box per replace would pass the tests.

