# Clipboard extras — decisions

Rulings for round 2 item 6 of the gpui-gap list (user request 2026-10-21; **not a plan task**): what `CB-N`
(record §115) deferred. Prefix `CP-`. **Next unused: `CP-O`.**
Spec: [`specs/2026-10-22-clipboard-extras-design.md`](specs/2026-10-22-clipboard-extras-design.md).
Record: `../record/142-clipboard-extras.md` (Record phase). Branch `feat/clipboard-extras` from `5f03ab7b`.
Divergence labels reserved 715–724: **715, 716, 717 taken** (715 `CP-C`, 716 `CP-F`/`CP-N`, 717 `CP-B`); 456 amended (`CP-J`).

Sources of truth. SwiftUI: `docs/probes/swiftui-clipboard-extras.swift` (2026-10-21). **Probed:** the SDK's
three `PasteButton` initialisers, the array signatures, and three compile-failure arms (`-DNEG1` no
`EnvironmentValues` clipboard on macOS, `-DNEG2` `PasteButton` takes no label, `-DNEG3` a non-`Transferable`
payload). **Unprobed** (arm R: the hosting window never became key from a command-line process although the
lock probe read unlocked): how many pasteboard items an array copy writes, what a multi-item paste
delivers, `PasteButton`'s enablement and look. Every ruling resting on R says **unprobed**; human check
`CP1` re-takes it. SDL: `docs/probes/sdl-clipboard-update.c` (measured, dummy and offscreen): every own set,
text set and clear posts exactly one `SDL_EVENT_CLIPBOARD_UPDATE` with no window; the data callback runs
at **read** time, not set time; one callback and one mime list per set (no items). gpui: no `PasteButton`,
no change event, `ClipboardItem` is a single item of entries (recalled from memory, source absent): no
precedent used.

## CP-A — `@Environment(\.clipboard)`: not built, and why

**Question.** CB-N lists it as additive. Does SwiftUI have it?
**Ruling.** **No SwiftUI macOS API exists** (`-DNEG1`: `EnvironmentValues` has no `clipboard`; `grep -i
clipboard` over SwiftUI's and SwiftUICore's macOS interfaces finds nothing). Not built, no invented spelling;
`Window.clipboard` (`CB-J`, class `M`) stays the one imperative route, and inside a view a
`PasteButton`/`pasteDestination` is the SwiftUI way. The inventory carries nothing (no declaration);
`docs/api-overview.md`'s absent-API list gains the line.
**Cost if wrong.** An app wanting the clipboard in a view body calls it from an action closure through a
captured `Window`; six lines, as `CB-O` already ruled.

## CP-B — `PasteButton`: SwiftUI's two initialisers, an own drawn look

**Ruling.** Built: `PasteButton(payloadType:onPaste:)` (`T: MetalUI.Transferable`, `onPaste: ([T]) -> Void`,
macOS 13) and `PasteButton(supportedContentTypes: [ContentType], payloadAction: ([DropItem]) -> Void)` (macOS
11; MetalUI's lazy `DropItem` stands where `NSItemProvider` does, `DN-`). The deprecated-on-macOS
`validator:` form is **not built**. It is a control, composed over `Button` (one hitbox, focusable, `ControlKeys`
Space/Return, the `.disabled` gate, `.buttonStyle` honoured, role `button`, so **no new `AccessibilityRole`
and no bridge row**); it takes **no label** (`-DNEG2`). Look: a bordered `Button` chrome with the text
"Paste" (no glyph asset exists; SwiftUI's icon and system look are unprobed). A click reads **every** clipboard
item (`CP-D`) through `importClipboardItem` and calls the action once with the array; it does not go through
`dispatchClipboardKey`, so `Cmd+V` routing and the one stage's order are untouched. **Enablement** (probed
claim: SwiftUI disables it from the pasteboard's contents, unprobed in behaviour): enabled iff some clipboard
item offers a type that satisfies one of the payload's `importedContentTypes()` (or `supportedContentTypes`),
by the platform's current list (`clipboardTypeIdentifiers`/`clipboardItems`), never the validator (`CB-G`'s
"by presence"). No macOS 15 paste-permission prompt exists in MetalUI (a platform clipboard read is not gated)
and the look is a ruling: divergence **717**.
**Cost if wrong.** A look change is a restyle; a wrong enablement shows a dead or live button (pin below).

## CP-C — Multi-item: SwiftUI's array semantics, platform-native where one exists

**Question.** Divergence 456: `copyable([a, b])` writes only `a`; a paste action receives at most one value.
**Ruling.** Built. `copyable`/`cuttable`/`Clipboard.write(_ items: [T])` write **every** item; a
`pasteDestination` imports **every** clipboard item it can (items it cannot import are skipped, none
importable declines, `CB-P`), runs the validator over the whole array, and the action receives all accepted
values in order. New read API `Clipboard.read(_:)` stays the first item; `Clipboard.readAll(_:) -> [T]`
and `Clipboard.itemCount` are added (class `M`). **AppKit:** N `NSPasteboardItem`s via one `writeObjects`.
**SDL: one mime set per clipboard, measured** (`sdl-clipboard-update.c`): item 0's representations are written
under their ordinary mimes (so another app pastes the first item, as today), and **when more than one item
is written** one extra private mime `application/x-com.metalui.clipboard-items` (a `ClipboardMime` custom
identifier) carries a framed pack of **all** items' representations (`ClipboardItemPack`, portable,
Foundation-free, bounded: 1024 items, 1024 representations an item, 1 MiB per type name, 64 MiB total; a
malformed pack is ignored and the native single item is used). A one-item write adds no pack: byte for byte
`CB-H`'s box. Reads on SDL prefer a present pack. SwiftUI's array behaviour is **unprobed** (arm R), so
456 is **retired** (the signature question is answered: arrays are honoured) and the **platform difference**
is divergence **715** (SDL: other applications see item 0 only). The new seam is three **defaultless**
requirements (`CP-E`).
**Cost if wrong.** If SwiftUI writes only the first on macOS, MetalUI's N items are a superset a human
check (`CP1`) can retire by a one-line change in the write path; the pack is MetalUI-to-MetalUI only.

## CP-D — Reading: items, not types

**Ruling.** `PasteButton` and `pasteDestination` read item by item through `Clipboard.itemAt(_:)`
(`DropItem` per item, lazily loaded, `CB-F`); `importClipboardItem` is unchanged per item. A clipboard
with N items and a destination for `T` yields at most N values. The single-type read of item 0
(`clipboardTypeIdentifiers()`, `readClipboard(identifier:)`) stays and means item 0, so the existing
requirements, every fake and every `CB` pin are unmoved.

## CP-E — The seam: four defaultless requirements

**Ruling.** On `PlatformWindow`, **no defaults**: `writeClipboard(items: [ClipboardItem]) -> Bool`,
`clipboardItems() -> [[String]]` (identifiers per item, most preferred first), `readClipboard(item:
Int, identifier: String) -> [UInt8]?`, and `setClipboardChangeHandler(_ handler: (@MainActor () -> Void)?)`
(`CP-G`). `ClipboardItem` (public, `MetalUIPlatform`) is `[ClipboardPayload]` where `ClipboardPayload`
holds `type: PasteboardType` and `bytes: ClipboardBytes`, `enum ClipboardBytes { case now([UInt8]); case
later(@MainActor () -> [UInt8]) }` (`CP-F`). The honest answers of a platform with no typed clipboard:
`false`, `[]`, `nil`, no-op. AppKit, SDL, `HeadlessPlatformWindow` and every fake implement them
(`Tests/MetalUITests/Fakes.swift`, `PortableFakeWindow.swift`, the compile-guard fakes, guard 3.1's fixture);
`docs/migration.md` gets the note. The existing four (`CB-E`) stay.
**Cost if wrong.** A conformer outside the repo breaks at compile time (by design, `HT-X`).

## CP-F — Lazy export: AppKit and headless lazy, SDL realises at write

**Question.** Can the exporter run at paste time?
**Ruling.** Yes where the platform can: **AppKit** writes each `.later` representation with
`NSPasteboardItem.setDataProvider(_:forTypes:)` (a provider object the window retains until
`pasteboardFinishedWithDataProvider`), and the provider calls the closure when a consumer reads; off the main
thread it hops with `DispatchQueue.main.sync` (a main-thread reader runs it in place); the closure captures
the `Transferable` **values** at copy time, so only the byte encoding is deferred. **SDL stays eager**:
its callback is lazy by nature (probe) but `CB-H` ruled it pure C for any-thread safety, and a Swift export
closure cannot run there (a main-queue hop deadlocks a main-thread read, `CB-Q`), so `Window` realises every
`.later` at write time on SDL, and `CB-I` (empty dropped) holds there. `copyable`/`cuttable` and
`Clipboard.write` produce `.later` by default and carry **no new public parameter**. **Headless** follows
AppKit's answer (`HeadlessPlatform.Options.clipboardExportsLazily`, default `true`, `HT-X`) and counts calls
(`TestWindow.clipboardExportCount`). Consequences, divergence **716**: the closure runs at copy time on SDL
and at read time on AppKit; an AppKit lazy representation that exports zero bytes is still listed and yields
no data (`CB-I` cannot be applied before the closure runs). SwiftUI's own timing is **unprobed**.
**Cost if wrong.** A Transferable whose exporter reads mutable external state sees it at paste time on
AppKit; documented, and a value-type payload is unaffected.

## CP-G — Change notification: the platform pushes, the window redraws only for a button

**Question.** `PasteButton` must follow the clipboard; how does the window learn of changes?
**Ruling.** `setClipboardChangeHandler`. **SDL:** `SDL_EVENT_CLIPBOARD_UPDATE` (measured: one event per
own set, text set and clear, no window), turned by the pump into the handler call. **AppKit** has no
notification: the platform compares `NSPasteboard.changeCount` **on `NSWindow.didBecomeKey`, after its own
write, and at each mouse-down and key-down** (an `Int` compare) and calls the handler on a change; a clipboard
manager rewriting it while the window is key and idle shows at the next press or becoming key (a named
residue). **Headless:** the handler runs when `TestWindow.setClipboard(...)` or a window write changes the
store, never on an identical write. `Window` marks itself dirty **only when the last build held a
`PasteButton`** (`lastFocusRegistry.pasteButtonCount`, counted apart as `clipboardRegionCount` is, `IF-N`'s
shape), so a window without one costs nothing. The enablement read comes from a `Frame`-stamped snapshot of
`clipboardItems()` that `Window` refreshes in the handler and at creation, never read inside a phase from the
platform; it joins the retained fingerprint the way `controlActiveState` does (`CP-H`).
**Cost if wrong.** A stale enablement until the next press; bounded and named.

## CP-H — Retention: a `PasteButton` in a retained subtree

**Ruling.** The clipboard snapshot is a paint- and build-time ambient. An `.equatable()` component holding
a `PasteButton` must not replay a stale enabled state: **decided (CP-L): retention refuses by a named counted
reason (`pasteButtonUnderRetained`) when a `PasteButton` is under it**; no fingerprint field, no `AmbientKey` edit. Pinned with `METALUI_VERIFY_RETAINED=1` semantics (`CP-` test
1.9). No identity, state-slot, hit-test, focus, animation or layout rule moves: `PasteButton` is a `Button`
inside, one identity level like `Button` (`MC-A`).

## CP-I — Deferred, named

Not built, each with a reason: an environment clipboard (`CP-A`, no SwiftUI API); the deprecated `validator:`
`PasteButton` (deprecated on macOS); a `PasteButton` label or `buttonStyle` look beyond what `Button` gives
(SwiftUI takes no label; look unprobed, human check `CP2`); image/file-URL constants and `Image` as
`Transferable` (own item, `CB-N`); the X11 primary selection; lazy export on SDL (`CP-F`, blocked by thread
rules, owner none); clipboard change observation as **public** API (not SwiftUI; `CP-G` is internal).

## CP-J — Divergence 456 is narrowed, not retired (critic, 2026-10-22)

**Ruling.** CP-C retired 456 resting on an **unprobed** SwiftUI array behaviour (arm R). A retirement needs a
probe. 456 stays live and is **amended** (MetalUI now writes and receives all items; whether SwiftUI does is
unprobed, human check `CP1`); retirement waits for `CP1`. Labels 715–717 as earmarked.

## CP-K — Steps and lanes (critic, 2026-10-22)

**Ruling.** Two lanes only (`MetalUITesting`'s headless store belongs to the seam, not a lane): **lane 1 = S0 (the
seam, with the headless store and `TestWindow.setClipboard(items:)`/`clipboardItems`/`clipboardExportCount` honest
from the start, so lane 2 never edits lane 1's tests) then `PasteButton` and change notification**; **lane 2 =
multi-item, lazy, the demo's two-item source and the guide snippet**, run after lane 1. The demo section is lane 2's
(it needs both). Rejected: a third S0 agent (agents run one at a time; the commit boundary is enough). The guide
mirror file is `GuideMirrorsClipboard.swift`, not `…Lane1`. The migration note counts **four** new requirements
(not seven).

## CP-L — Retention refusal for `PasteButton` (critic, 2026-10-22)

**Ruling.** See `CP-H`: refusal by name beats a fingerprint field (smaller, cannot go stale). Test 1.9's mutation
becomes "remove the refusal" (must redden: stale enabled state under `METALUI_VERIFY_RETAINED=1`).

## CP-M — The snapshot is read lazily by a `PasteButton`, held in `ClipboardAccess` (lane 1, 2026-10-22)

**Question.** `CP-G` had `Window` stamp a `Frame` snapshot of `clipboardItems()` at creation and in the handler. That reads
the platform's clipboard (AppKit: `pasteboard.types`, SDL: a mime list `malloc`) in **every** window, button or not, and a window
built without a button on its first frame would need a settle build when one appears.
**Ruling.** A `ClipboardAccess` class (`PasteButton.swift`, weak over the platform window, stamped on each `Frame`) holds the
snapshot and a stale flag. The **first `PasteButton` that lays out** reads the platform (inside layout, an idempotent read with
no state write), later layouts reuse the cached snapshot, and the platform's change handler only `invalidate()`s it, so the next
layout reads again. A window with no button never reads (pin 1.5 reads `testingClipboardReads == 0`). The dirty rule is `CP-G`'s:
the handler redraws only when `lastPasteButtonCount > 0`. `Frame` carries no snapshot field.
**Consequence.** Enablement is exact in the first frame with no settle build; the read inside a phase is declared here as the one
exception to "never read the platform inside a phase" and costs one read per clipboard change per window holding a button.
**Cost if wrong.** A platform whose `clipboardItems()` is slow shows it in a layout, once per change; a cache would then move to
the handler under the dirty rule.

## CP-N — Lazy export covers `copyable` and `cuttable`; `Clipboard.write` encodes now (lane 2, 2026-10-22)

**Question.** `CP-F` made every copy lazy, but `CB-I` (zero-byte representations dropped, nothing written and `false` when none
remain) is pinned by `windowClipboardRoundTripsATransferableAndReportsEmptyAndAbsent` (`!clipboard.write(Blob(bytes: []))`), and a
lazy representation cannot be judged empty before its exporter runs.
**Ruling.** `copyable` and `cuttable` (key-driven; nothing consumes an answer) capture the `Transferable` **values** and produce `.later`
representations: the exported types are listed whether or not they will export bytes, and the empty one reads `nil` (divergence 716).
`Clipboard.write(_:)` and `TestWindow.setClipboard(items:)` (public, answering whether anything was written) **encode now** and keep `CB-I`
exact; `ClipboardItem` itself carries both spellings, so an app that wants a lazy write through the platform seam builds the item.
`HeadlessPlatformWindow.readClipboard(item:identifier:)` answers `nil` for a representation that exports zero bytes, as AppKit does (a
provider that supplies no data). A `.later` closure crosses into a main-actor closure through a `nonisolated(unsafe)` copy of the value
(`Transferable` is not `Sendable`); it is read only by that closure.
**Cost if wrong.** `Clipboard.write` of an expensive value pays its encoding at the write; a lazy `write` overload is additive.
