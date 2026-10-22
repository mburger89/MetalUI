# Clipboard extras — design

Round 2 item 6 (user request 2026-10-21; record §142; rulings `CP-A`…`CP-I` in
[`../2026-10-22-clipboard-extras-decisions.md`](../2026-10-22-clipboard-extras-decisions.md)). Branch
`feat/clipboard-extras` from `5f03ab7b`. Discharges `CB-N` (record §115). Probes:
`docs/probes/swiftui-clipboard-extras.swift`, `docs/probes/sdl-clipboard-update.c` (outputs in their headers).

## 1 Scope and verdicts

| gap | verdict | ruling |
|---|---|---|
| `@Environment(\.clipboard)` | **not built**: no such SwiftUI macOS API (probe `-DNEG1`) | `CP-A` |
| `PasteButton` | built: two SwiftUI initialisers, own look | `CP-B` |
| multi-item copy/paste | built; divergence 456 narrowed (CP-J); SDL packs extras in a private mime (715) | `CP-C`, `CP-D` |
| lazy export | built on AppKit and headless, SDL realises at write (716) | `CP-F` |
| change notification (for `PasteButton`) | internal platform push, AppKit polls `changeCount` | `CP-G` |

## 2 Public API (all with doc comments and inventory map rows)

- `PasteButton<T>` (class **A**; `Element, StyledElement`, composed over `Button`):
  `init(payloadType: T.Type, onPaste: @escaping @MainActor ([T]) -> Void) where T: MetalUI.Transferable`;
  `PasteButton(supportedContentTypes: [ContentType], payloadAction: @escaping @MainActor ([DropItem]) -> Void)`
  (class **D**: `DropItem` for `NSItemProvider`, divergence 717 covers look and the missing prompt).
- `Clipboard.readAll<T: Transferable>(_:) -> [T]`, `Clipboard.itemCount: Int`, and `Clipboard.write(_ items:
  [T])` now writing all items (class **M**); `contentTypes`/`hasContent(of:)` keep meaning item 0.
- Seam (`MetalUIPlatform`, public, class **M**): `ClipboardItem`, `ClipboardPayload`, `ClipboardBytes`; four
  defaultless `PlatformWindow` requirements (`CP-E`). `MetalUITesting`: `TestWindow.setClipboard(items:)`,
  `clipboardItems` read-back, `clipboardExportCount`, `HeadlessPlatform.Options.clipboardExportsLazily`.
- No declaration for the environment clipboard (inventory row not added; `docs/api-overview.md` lists it absent).

## 3 Design

**Items.** A write is `[ClipboardItem]`; each item is representations in preference order, each representation
`.now(bytes)` or `.later(closure)`. `Transferable.clipboardRepresentations()` becomes `clipboardItem(lazily:)`;
zero-byte `.now` representations are dropped (`CB-I`) and an item with none is dropped; all items empty writes
nothing and answers `false`. `copyable`, `cuttable` and `Clipboard.write` capture the `Transferable` **values**
and defer only the byte encoding. `ClipboardAttachment.copy`/`.cut` return `[ClipboardItem]`; `.pasting`
imports every item, runs the validator on the array, declines on none (`CP-C`). The one clipboard stage
(`dispatchClipboardKey`) and its order, `Handlers`' nineteen members, and the text-field path are untouched.
**AppKit** (`AppKitPlatform.swift`): N `NSPasteboardItem`s, `.later` through a retained provider object;
change poll on `didBecomeKey`, after a write, at mouse/key down. **SDL** (`SDLPlatform.swift`, `SDLBridge.c`):
item 0 as today (one `malloc` box, pure C, `CB-H`); more than one item adds the `ClipboardItemPack` mime;
`.later` realised at write; `SDL_EVENT_CLIPBOARD_UPDATE` calls the handler.
**`ClipboardItemPack`** (`MetalUIPlatform/Clipboard.swift`, portable, `package`, Foundation-free): magic,
count, then per item a count of (length-prefixed UTF-8 type name, length-prefixed bytes); decode is
bounds-checked and answers `nil` on any violation, never traps.
**`PasteButton`** (`Sources/MetalUI/PasteButton.swift`): holds the payload spec; builds a `Button("Paste")` whose
`isEnabled` is the clipboard snapshot satisfying the spec (`Frame.clipboardSnapshot`, stamped by `Window`,
refreshed by the change handler and at creation); the action reads the platform's items through the
`Window` clipboard box on the frame (`ClipboardAccess`, a class, weak over the platform window), imports
each, calls the action once under `StateDispatch`. `Window` counts buttons in the focus registry
(`pasteButtonCount`) and dirties on a platform change only when the last build had one. Retention: `CP-H`.

## 4 Files and lanes

**Final shape (CP-K): two lanes. Lane 1 = S0 below plus `PasteButton`; lane 2 = multi-item, lazy, demo, guide, after lane 1; the demo section moves to lane 2.**

**Step S0 (one agent, first, committed alone): the seam.** `Sources/MetalUIPlatform/Clipboard.swift` (the
three types, `ClipboardItemPack` with its tests), `Platform.swift` (four requirements), stub-honest
implementations plus **stored properties** for the change handler and the lazy provider in
`AppKitPlatform.swift`, `SDLPlatform.swift`, `HeadlessPlatformWindow.swift`, and every fake, guard 3.1's fixture,
`docs/migration.md`. Compiles on macOS and in the Linux image; the suite is at 4248 + the pack's tests.

Then two lanes, **disjoint after S0** (each lane's platform code goes in **new extension files**):

**Lane 1 — `PasteButton` and change notification.**
`Sources/MetalUI/PasteButton.swift` (new), `Sources/MetalUI/Window.swift` (handler install, snapshot, dirty rule,
`pasteButtonCount` in `FocusRegistry`'s file `Focus.swift`), `Sources/MetalUI/Frame.swift` snapshot stamp
(and the `AmbientKey`/environment-reading treatment, `CP-H`), `Sources/MetalUIAppKit/AppKitClipboardChange.swift`
(new), `Backends/SDL/Sources/MetalUISDL/SDLClipboardChange.swift` (new; the event case in the pump is the one edit
to an existing SDL file, `SDLPlatform.swift`'s event switch: lane 1 owns that function), headless handler firing
(`HeadlessPlatformWindow+Clipboard.swift`, new), `Sources/MetalUIDemo*`'s clipboard demo section
(`ClipboardDemo.swift`), tests below with prefix `1.`.

**Lane 2 — multi-item and lazy.** `Sources/MetalUI/Clipboard.swift`, `ClipboardModifiers.swift`,
`Sources/MetalUIAppKit/AppKitClipboardItems.swift` (new; the write/read/provider functions move here from
`AppKitPlatform.swift`, lane 2 owns them), `Backends/SDL/Sources/MetalUISDL/SDLClipboardItems.swift` (new, same
move), `Backends/SDL/Sources/SDLBridge/` additions if the pack needs C (it should not: the pack is Swift bytes
in one more mime), `HeadlessPlatformWindow+Items.swift` (new), `docs/divergences.md` rows 715, 716 (and 717
text from lane 1's wording, appended by lane 2 last), amend 456 (CP-J, not retired), `docs/guides/input.md` snippet #9
mirrored in `GuideMirrorsClipboard.swift` (`DG-C`), `docs/api-overview.md`, tests with prefix `2.`.

## 5 Tests, with red-before and the mutation that must redden each

Every test is written first and red on the unbuilt subject (compile failure counts); each mutation is applied
once on the named spelling and the full unfiltered suite names the reddened tests.

Lane 1 (`Tests/MetalUITestingTests/PasteButtonTests.swift`):
- **1.1 enablement follows the clipboard**: empty -> disabled, `setClipboard` with a matching item -> enabled,
  non-matching -> disabled, cleared -> disabled, with the frame redrawn by the handler alone (no input).
  Mutation: enablement read once at creation / always `true`.
- **1.2 a click delivers every decoded item**: two `Tag` items, `onPaste` receives `[Tag(7), Tag(8)]` once;
  mutation: deliver `.first` only.
- **1.3 `supportedContentTypes` form** delivers `DropItem`s whose `load` returns each item's bytes; mutation:
  match on exact type instead of `satisfies`.
- **1.4 the `.disabled` gate and the keyboard**: a `.disabled(true)` button does not fire on click or Space;
  enabled fires on Space/Return via `ControlKeys` and takes Tab focus; mutation: skip the gate.
- **1.5 no dirty without a button**: a window with no `PasteButton` is not redrawn by a clipboard change
  (`FrameWork` build counter unchanged); mutation: dirty unconditionally.
- **1.6 accessibility**: one node, role button, label "Paste", disabled flag follows enablement; mutation:
  drop the label. (No new role, no bridge row.)
- **1.7 `Cmd+V` unchanged**: a `pasteDestination` plus a `PasteButton`, `Cmd+V` runs only the destination;
  the stage's order test (`ClipboardTypesTests` 1.9) still green; mutation: route the button through the stage.
- **1.8 the change handler**: headless fires on a changing write once, not on an identical write; AppKit
  (`AppKitClipboardChangeTests`, private `NSPasteboard(name:)`, `CB-K`) fires after a foreign
  `clearContents`+write on `didBecomeKey` and on a mouse-down, never on `changeCount` unchanged; mutation:
  compare against the wrong count / fire every time.
- **1.9 retention**: a `PasteButton` inside an `.equatable()` component re-renders enabled after a clipboard
  change, and the same run under `METALUI_VERIFY_RETAINED=1` does not trap; mutation: remove the named retention
  refusal (CP-H/CP-L; must redden).
- SDL (`SDLClipboardChangeTests.swift`, `.serialized`, `armMainRunLoopExitCheck()`): **1.10** an own set, a text
  set and a clear each call the handler once (probe's numbers); the offscreen Linux image runs it (events need no
  window, measured). Mutation: drop the event case.
- Guard **G1.1** (`PasteButtonCompileGuards.swift`): plain-import spellings compile (`PasteButton(payloadType:onPaste:)`,
  the `supportedContentTypes` form), a trailing label closure and a missing `Transferable` do not, and a
  conformer without `setClipboardChangeHandler` does not compile; each negative rebuilt red once.

Lane 2 (`Tests/MetalUITestingTests/ClipboardItemsTests.swift`):
- **2.1 multi-item round trip**: `copyable([a, b])` writes two items; a `pasteDestination` receives `[a, b]` in
  order; mutation: write the first only (the old `CB-C`).
- **2.2 skipped and declined**: a clipboard of `[text, tag]` for a `Tag` destination yields one value; none
  importable declines and the next stage runs (`CB-P` kept); mutation: claim with an empty array.
- **2.3 validator over the array** filters; the action sees the filtered array; mutation: validate item 0 only.
- **2.4 cut returns several**; the action runs once; all written; mutation: run twice (as `CB-` M3).
- **2.5 `Clipboard.readAll`/`itemCount`/`write([])`** (empty writes nothing, `false`); mutation: `itemCount` from item 0.
- **2.6 lazy export**: with the default option the exporter runs zero times at copy, once at the first
  `readClipboard`, `clipboardExportCount` counts calls; with `clipboardExportsLazily = false` once at copy;
  mutation: realise eagerly always (reddens the lazy assertion).
- **2.7 an empty lazy representation** is listed and reads `nil` (716's pin); mutation: drop at listing.
- **2.8 `ClipboardItemPack`** (`Tests/MetalUICrossPlatformTests/ClipboardItemPackTests.swift`): round trip of 3
  items, an empty item, a hostile name, and decode of truncated/over-count/over-length input answering `nil`;
  mutation: skip a bounds check (a truncated input must then fail the test, which is the instrument).
- AppKit (`AppKitClipboardItemsTests.swift`, private pasteboard): **2.9** N items written and listed by item,
  read by `(item, identifier)`; **2.10** a lazy type's provider runs on read, once per read, and a read from a
  detached `Thread` while the main thread spins the run loop completes (no hang); **2.11** the pasteboard's
  `changeCount` of `.general` never moves. Mutations: `clearContents` per item (leaves one item), provider
  retained by nobody (data absent), `.general` written.
- SDL (`SDLClipboardItemsTests.swift`): **2.12** one item writes no pack (the mime list equals `CB-` 's); **2.13**
  three items write item 0 natively plus the pack, a read by `(2, id)` returns item 2's bytes and a native read
  returns item 0's (715's pin); **2.14** a malformed pack falls back to the single item; **2.15** `.later` is
  realised at write (the exporter's counter is 1 right after the write). Mutations: always write the pack,
  skip the realise, trust a bad pack.
- Guard **G2.1**: a conformer without the three item requirements does not compile; spellings compile from a
  plain import; `ClipboardItem`'s case spellings (`.now`, `.later`) are reachable.
- Guide mirror **`// guide: input #9`** ("Copy several, paste a button") mirrored byte for byte; `GuideDocCheck` green.

Existing pins that must stay green unedited: all of `ClipboardTypesTests`, `ClipboardMimeTests`,
`AppKitClipboardTests`, `SDLClipboardTests`, `ClipboardDemoTests`; `theSevenRetentionSlotsAreMutuallyDistinct`;
`DemoFrameDeterminismTests`' `Expected.swift` unedited.

## 6 Demo

`METALUI_CLIPBOARD_DEMO=1` gains, in its own function (Windows 1 MB stack; the stack-budget loop gains it): a
second source that copies **two** `Graph`s, a destination listing everything received as which type, and a
`PasteButton(payloadType: Graph.self)` beside it that is dimmed until a `Graph` is on the clipboard. The default
demo tree and its fourteen images do not move (env-gated, 0 px against `5f03ab7b`).

## 7 Human checks (group `CP`, `docs/verification/human-checks.md`)

`CP1` re-take probe arm R where a window becomes key: item count of an array copy, what a two-item paste
delivers, whether SwiftUI's `PasteButton` disables on a foreign pasteboard (confirms or retires 715's AppKit side,
716 and CP-B's enablement). `CP2` the `PasteButton` look beside SwiftUI's on macOS, light and dark, focus ring,
pressed, disabled. `CP3` paste of two copied items between two real macOS apps (Finder files are out of scope) and
between two MetalUI windows on Linux X11/Wayland and Windows (the pack). `CP4` an external clipboard manager
rewriting the clipboard while the window is key: the button's enablement at the next press (`CP-G` residue).

## 8 Deferred, named

See `CP-I`. Also the Record phase owes: counts, census, the fourteen images against `5f03ab7b`, the Linux image
runs for `Backends/SDL`, `docs/api-overview.md`, `docs/migration.md` (four new defaultless requirements, CP-K), CLAUDE.md/AGENTS.md rule and record index (§142).
