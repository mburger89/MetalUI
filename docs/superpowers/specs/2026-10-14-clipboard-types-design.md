# Clipboard beyond text — design

Item S3 (user request 2026-10-02; not a plan task), MetalCreator's SDL-port gap 7 (developer-c0,
2026-10-13). Rulings: [`../2026-10-14-clipboard-types-decisions.md`](../2026-10-14-clipboard-types-decisions.md)
(`CB-A`…`CB-N`). Record: `../../record/115-clipboard-types.md`. Branch `feat/clipboard-types` from
`fb9a7e42`. **Status: DESIGNED, not built.**

## 1 Inventory (what exists)

- Seam: `PlatformWindow.readClipboard() -> String?` / `writeClipboard(_:)`
  (`Sources/MetalUIPlatform/Platform.swift:129`, `TI-A`). AppKit: `NSPasteboard.general` string
  (`AppKitPlatform.swift:863`). SDL: `mui_clipboard_text` / `mui_set_clipboard_text`
  (`SDLBridge.c:1722`, `SDLPlatform.swift:659`). Headless: `HeadlessPlatformWindow.clipboard: String?`.
  Only user: `Window.dispatchTextKey` (`Window.swift:3335`).
- Edit commands: AppKit's `MetalHostView.cut/copy/paste` and the drawn bar's Edit items already
  deliver ⌘X/⌘C/⌘V as `.keyDown` through `onInput` (`AppKitMenus.swift:159`, `Window.deliverStandardEditKey`),
  enabled only with a caret (`validateMenuItem`, `SG-H`). So a key stage serves menu and keystroke.
- `Transferable`/`ContentType` (`Transferable.swift`): synchronous; `dragRepresentations()`;
  `DropDestinationTarget.match` + `init?(importing:contentType:)` (`DragAndDrop.swift`); `PasteboardType`
  (`InputEvent.swift:351`); `DropItem` (lazy `load`).
- Key ladder in `Window.onInput` (`Window.swift:1150–1230`): Keymap, `onKeyPress`, field keys,
  `onKey`, context-menu key, `Button` shortcut, command shortcut, F10, Tab.
- `KeyboardAttachment` (`KeyPress.swift:117`) is the box that carries keyboard modifiers without growing
  `Handlers` (nineteen members).
- SDL3 (3.4.18): `SDL_SetClipboardData/GetClipboardData/HasClipboardData/GetClipboardMimeTypes/
  ClearClipboardData` (probe `docs/probes/sdl-clipboard-data.c`).

## 2 Public API

```swift
// MetalUI — on every StyledElement and, once (KeyboardModifier layer), proposal content
func copyable<T: Transferable>(_ items: @autoclosure @escaping () -> [T]) -> Self
func cuttable<T: Transferable>(for payloadType: T.Type = T.self,
                               action: @escaping @MainActor () -> [T]) -> Self
func pasteDestination<T: Transferable>(for payloadType: T.Type = T.self,
                               action: @escaping @MainActor ([T]) -> Void,
                               validator: @escaping @MainActor ([T]) -> [T] = { $0 }) -> Self
// MetalUI-only (class M)
extension Window { public var clipboard: Clipboard { get } }
public struct Clipboard {            // no public init
    @discardableResult public func write<T: Transferable>(_ item: T) -> Bool
    @discardableResult public func write<T: Transferable>(_ items: [T]) -> Bool
    public func read<T: Transferable>(_ type: T.Type = T.self) -> T?
    public var contentTypes: [String] { get }
    public func hasContent(of type: ContentType) -> Bool
}
// MetalUIPlatform
public struct ClipboardRepresentation: Sendable, Equatable { type: PasteboardType; bytes: [UInt8] }
public struct ClipboardCommands: OptionSet, Sendable { cut, copy, paste }
// PlatformWindow, all defaultless (CB-E)
func writeClipboard(_ representations: [ClipboardRepresentation]) -> Bool
func clipboardTypeIdentifiers() -> [String]
func readClipboard(identifier: String) -> [UInt8]?
func setClipboardCommands(_ commands: ClipboardCommands)
// MetalUIPlatform, package-visible and tested portably (CB-D)
enum ClipboardMime { static func mime(forIdentifier:) -> String; static func identifier(forMime:) -> String }
```
`Clipboard.read` is `CB-F` with the same `init?(importing:)` rule; `hasContent(of:)` is
conformance-aware (`ContentType.conforms`) over the listed identifiers.

## 3 Implementation

- **MetalUIPlatform**: seam types and requirements, `ClipboardMime`, the `ClipboardMime`-aware
  `PasteboardType` construction for built-ins.
- **MetalUI**: `Clipboard.swift` (write: `exportedContentTypes` → `exported(as:)` → representations,
  first item, empty dropped; read: one `DropItem`, `DropDestinationTarget.match`);
  `ClipboardModifiers.swift` (the three modifiers, both vocabularies, into `ClipboardAttachment`, a
  class box in a fifth field of `KeyboardAttachment`; every factory in `KeyPress.swift` carries it);
  `FocusRegistry` records the attachment per id and `clipboardRegionCount`; `Window.dispatchClipboardKey`
  (new stage after `dispatchKey`, `CB-B`); after each frame `Window` computes the chain's
  `ClipboardCommands` and calls `setClipboardCommands` only on change (never a `Window.environment`
  write; never dirties); the drawn bar's `editEnabled` also reads it (`openMenuBarMenu`).
- **AppKit**: the window holds `pasteboard: NSPasteboard` (default `.general`; an internal initialiser
  parameter for tests). Write = `clearContents()` then one `NSPasteboardItem` with `setData(_:forType:)`
  per representation, `writeObjects`; types = `pasteboard.types` rawValues; read =
  `data(forType:)`. `validateMenuItem` also returns true for the action's `ClipboardCommands` bit.
  `readClipboard()`/`writeClipboard(_ text:)` use the same `pasteboard`.
- **SDL (`SDLBridge.c`, `SDLPlatform.swift`)**: `mui_clipboard_set(const char *const *mimes, const
  uint8_t *const *bytes, const size_t *sizes, size_t count)` builds the box (`CB-H`) and calls
  `SDL_SetClipboardData`; `mui_clipboard_mime_types(size_t *count)`; `mui_clipboard_get(mime, &size)`
  guarded by `SDL_HasClipboardData`. `SDLPlatform` maps identifiers with `ClipboardMime`; the text-only
  calls are unchanged. `setClipboardCommands` records (the drawn bar reads `Window`'s own state).
- **Headless**: `CB-K`.
- **Fakes**: `Tests/MetalUITests/Fakes.swift`, `Tests/MetalUICrossPlatformTests/PortableFakeWindow.swift`,
  the `*CompileGuards.swift` fakes gain four members (lane 1); `Backends/SDL/Tests` fakes are lane 2's alone (grep: every file naming `readClipboard`).

## 4 Lanes (two, disjoint)

**Lane 1 — core, AppKit, headless, fakes, guides** (all of `Sources/`, root `Tests/`, `docs/`):
seam types first (commit 1, so lane 2 compiles), then everything in §3 except SDL, the demo,
the guide block, inventory rows, census. **Lane 2 — SDL** (`Backends/SDL/Sources`,
`Backends/SDL/Tests`, `Backends/SDL/linux`): after lane 1's commit 1; C bridge, `SDLPlatform`, the SDL
fakes, round-trip tests, the Linux image run. Files disjoint; lane 2 edits no `Sources/`.

## 5 Tests (name, red before, mutation that must redden it)

Root (lane 1, `Tests/MetalUITestingTests/ClipboardTypesTests.swift` unless stated; headless `TestApp`):

| # | Test | Red before | Mutation (must redden it) |
|---|---|---|---|
| 1.1 | `aCopyableFocusedElementWritesItsTypeAndItsTextFallback` | no modifier/seam | drop the fallback type from the item's `exportedContentTypes` order; or write only the first representation |
| 1.2 | `aCopyOnAnUnfocusedAncestorlessElementWritesNothing` (separating arm of 1.1) | n/a | make `dispatchClipboardKey` use hover |
| 1.3 | `cutWritesTheItemsThenRunsTheActionOnce` | no modifier | swap order (action before write reads stale) / run action twice |
| 1.4 | `aPasteDestinationReadsTheCustomTypeBeforeTheText` | no modifier | invert `importedContentTypes` preference |
| 1.5 | `aPasteWithOnlyTextFallsBackToTheTextImport` | no modifier | `match` ignoring the text representation |
| 1.6 | `aPasteWithNoImportableTypeDeclinesAndTheNextStageRuns` (an App command Paste runs) | no modifier | claim the key with no import |
| 1.7 | `theValidatorDecidesAndAnEmptyResultDeclines` | no modifier | skip the validator |
| 1.8 | `aFocusedTextFieldKeepsItsOwnCopyCutPasteUnderACopyableAncestor` | n/a (green before: pin) | order the stage before `dispatchTextKey`; the text-field tests of `TI-D` must not move |
| 1.9 | `onKeyPressAndTheKeymapStillBeatAClipboardHandler` | n/a | order the stage first |
| 1.10 | `theInnermostHandlerOnTheChainWins` and `eachKeyboardModifierFactoryKeepsTheClipboardAttachment` (every factory in `KeyPress.swift`) | no field | a factory forgetting the field |
| 1.11 | `theEditMenuItemsCopyCutPasteReachTheHandlerThroughTheDrawnBar` (`showsMenuBarNatively` false) and `theBarItemsAreEnabledOnlyWithAHandlerOrAField` | bar disabled | `editEnabled` ignoring `ClipboardCommands` |
| 1.12 | `setClipboardCommandsIsSentOnChangeOnly` (count) | no requirement | send every frame |
| 1.13 | `windowClipboardRoundTripsATransferableAndReportsEmptyAndAbsent` (empty dropped, `write` returns `false` and keeps contents, absent read `nil`) | no API | write zero-byte reps |
| 1.14 | `aLargePayloadRoundTripsByteForByte` (8 MiB pattern) | n/a | truncate in the headless store |
| 1.15 | `theClipboardTextPropertyIsAViewOfTheTextRepresentation` | n/a | existing `HarnessQueryTests` clipboard test unchanged and green |
| 2.1 | `ClipboardMimeRoundTripsEveryBuiltInACustomAMixedCaseAndAHostileIdentifier` (the mime is all lower case), `…TextIsTheMimeSDLAsksFor` (`Tests/MetalUIPlatformTests`, portable) | no type | off-by-one in the percent-encoder; text mime `text/plain` |
| 2.2 | `aForeignMimeIsListedAndReadableByItsMimeIdentifier` | no type | drop unknown mimes |
| 3.1 | typecheck guards (`Tests/MetalUITests/ClipboardCompileGuards.swift`): a conformer without the four members fails; a plain-import external module can write the three modifiers and `Window.clipboard.write`; `Clipboard()` does not compile; no `Handlers` member added (size pin) | — | each guard mutated red once by deleting its subject |
| 3.2 | `AppKitClipboardTests` (private `NSPasteboard(name:)`, released): write/types/read/replace, text-field text replaces custom types, `validateMenuItem` follows `setClipboardCommands`, `.general` untouched (changeCount equal before/after) | no pasteboard injection | write to `.general`; ignore the bit |
| 4.1 | `Backends/SDL`: `SDLClipboardTests` (`.serialized`, clear first, `armMainRunLoopExitCheck()`): set/has/get/types/replace/clear; custom + text fallback; absent; large (8 MiB); cleanup runs once on replace | no bridge | callback returning a freed box; cleanup twice; wrong text mime |
| 4.2 | `SDLClipboardTests.theCallbackNeedsNoMainActor` (called from a detached thread while the main actor is blocked in `semaphore.wait(timeout:)`, a bounded wait, not a sleep) | n/a | `DispatchQueue.main.sync` in the callback (the wait times out, red, no hang) |
| 5.1 | `GuideMirrors…`: the new guide block (`docs/guides/input.md`, "Copy and paste your own type") mirrored byte for byte (`DG-C`); `GuideDocCheck` green | block unmirrored | edit one byte |

Existing counts to re-take: tests (3717 + the new), typecheck guards (234 + 4), census, `FR-J` line.
Pixels: the fourteen images 0 px against `fb9a7e42` (no paint change; `compare.sh`). Mutations follow
`docs/practices/verifying-tests-can-fail.md`: commit, restore from a copy, full unfiltered suite,
`git status --short`, every reddened test named.

## 6 Demo

`METALUI_CLIPBOARD_DEMO=1` (env-gated: the default demo tree and its fourteen images do not change), `ClipboardDemo.swift` in `MetalUIDemoContent`, in its **own function**
(Windows 1 MB stack): two focusable boxes, one `copyable`/`cuttable` of a `Graph` (custom type with a text
fallback), one `pasteDestination` that shows what arrived and as which type; a status line. Expected
(pinned by a harness test in `DemoContent`): focus A, ⌘C/Ctrl-C, focus B, ⌘V/Ctrl-V shows the node
count; paste into a text field shows the fallback text.

## 7 Docs the change owes

Doc comments on every public declaration; `closeout-inventory-map.tsv` rows (`copyable`, `cuttable`,
`pasteDestination` ×2 vocabularies: class **A**; `Clipboard`, `Window.clipboard`, seam types: **M**;
divergences 455, 456: **D**), `closeout-public-api.sh` census re-recorded; `docs/migration.md` (four defaultless
requirements; a third-party conformer adds them; `MetalUI.Transferable` spelling); `docs/api-overview.md`;
`docs/divergences.md` 455 (provisional, `CB-G`), 456; guide block in `docs/guides/input.md` + mirror; `docs/testing.md` read-backs;
`docs/verification/human-checks.md` group **CB**; record 115. Record phase alone edits CLAUDE.md,
AGENTS.md, README, the record index.

## 8 Human checks (group CB, not run — an agent cannot)

- **CB1** SwiftUI arm R of the probe on an unlocked screen (focus needed? representations written?
  validator disables the item? multi-item?): rewrites `CB-B`, `CB-C`, `CB-G` if it disagrees.
- **CB2** Copy a `Graph` in the demo, paste it into another app (TextEdit gets the text fallback),
  copy text in another app and paste into the demo's destination (text fallback); AppKit, then
  Linux X11 and Wayland, then Windows.
- **CB3** The Edit menu items enable and disable with the focus (native menu on macOS, drawn bar on SDL).
- **CB4** A 100 MB payload copy and paste on each platform: no hang, memory returns.

## 9 Deferred (owner S3b, reasons in `CB-N`)

`PasteButton`, `@Environment(\.clipboard)`, lazy export, multi-item, change observation, primary
selection, image/file constants, Insert-key shortcuts, hover routing.

## 10 Risks

SwiftUI's routing and validator are unprobed (`CB1`); the C bridge's lifetime is the one memory-safety
surface (tests 4.1, 4.2 and a leak pin by cleanup count); `KeyboardAttachment` growing a field must
not move `Handlers` (guard 3.1).
