# Drag and drop — decisions

Rulings for drag and drop (user request 2026-10-01; **not a plan task** — the
SwiftUI-alignment plan is agent-complete and tasks 12 and 15 wait on human
checks; this is new feature work). Spec:
[`specs/2026-10-01-drag-and-drop-design.md`](specs/2026-10-01-drag-and-drop-design.md).
Record: `../record/68-drag-and-drop.md` (the Record phase writes it).
Evidence: [`../probes/swiftui-drag-and-drop.swift`](../probes/swiftui-drag-and-drop.swift)
(**new**; arm ids `T…` Transferable, `R…` drop sequencing through a fake
`NSDraggingInfo`, `A…` accessibility, `P…` real pointer drags posted at the HID
event tap; its header carries the recorded output and how to read it).

Prefix **`DN-`**, lettered. **Next unused: `DN-S`.** (This line moves in the
commit that appends a ruling; read the last `## DN-` heading.)

Branch `feat/drag-and-drop` from `053a3b3` (master: plan task 15 merged, PR
#35). Baseline at `053a3b3`: **1976 tests in 3 suites, 0 goldens, 121
typecheck guards**, 66 live divergences (next label 100).

**Carried items.** No decisions doc's "Carried…" section addresses drag and
drop, and no ruling anywhere names it (`grep -rn -i "drag and drop\|draggable\|dropDestination\|onDrop\|NSDragging" docs/superpowers docs/record`
reads one hit, `specs/2026-09-23-text-input-design.md:262`, which lists "drag
and drop of text" among `TextField`'s non-goals — unchanged here: a field
keeps its own press, `DN-D` item 6).

**How the probe reads, in one paragraph** (the header has the detail). Group
`R` drives SwiftUI's own drop destination view (`_PlatformDraggingDestinationView`,
`R0b`) with a fake `NSDraggingInfo`. It is **trusted for type filtering,
callback order and the action's arguments only**: every spatial reading it
gave disagrees with the real-pointer group (`R2b` targets a 100×100
destination from outside it, `R6`/`R8` never reach the inner or second
destination, `R5`/`R7` contradict nothing they could see) — SwiftUI resolves
its destination from the live pointer, not from `draggingLocation`. Group `P`
posts real `CGEvent`s at the HID tap (the session had event-posting access and
an unlocked screen, recorded in the header), so every spatial and precedence
ruling below rests on a `P` arm, each read against `P0` (a draggable dropped
on a target: `T=true,T=false,drop["p0"]`) and `P0b` (the same drag from a
plain colour: `-`).

---

## DN-A — the surface: `Transferable`, `draggable(_:)`, `draggable(_:preview:)`, `dropDestination(for:action:isTargeted:)`; nothing older or newer

**Ruling.**

1. **Built**: a MetalUI-owned `Transferable` and `ContentType` (`DN-B`);
   `.draggable(_:)` and `.draggable(_:preview:)` on every `StyledElement` and
   every `ProposalElementGroup`; `.dropDestination(for:action:isTargeted:)` on
   both. Spellings are SwiftUI's except where a type is Apple-only: the
   action's location is `Point<Pixels>` (SwiftUI: `CGPoint`), MetalUI's own
   coordinate type, as `DragGesture.Value` already uses.
2. **Not built, owner none**: `.onDrag`/`.onDrop` (their payload is
   `NSItemProvider`, an Apple-only type that cannot cross the portable surface,
   and `.onDrop(of:delegate:)` adds `DropDelegate`, a second surface for the
   same behaviour); the `DropSession` family —
   `dropDestination(for:isEnabled:action:)` with a `DropSession`,
   `onDropSessionUpdated`, `dropConfiguration`, `onDragSessionUpdated`,
   `dragConfiguration`, `dragContainer`, `draggable(containerItemID:)`,
   `dragPreviewsFormation` (macOS 26 API; a session object with phases,
   multi-item containers and preview formations is a second design, not a
   narrow subset); table-row and tab drop variants. Listed in
   `docs/divergences.md`'s "Not offered" table.
3. **SwiftUI soft-deprecates the requested spelling.** The SDK's interface
   marks `dropDestination(for:action:isTargeted:)` `deprecated: 100000.0`
   toward the `DropSession` overload (`SwiftUI.swiftinterface` line 2709–2713
   on this machine's macOS 27 SDK): a deprecation that warns nothing until a
   future SDK names a version. MetalUI's spelling is **not** deprecated — it
   is the only drop surface MetalUI offers.

**Evidence.** The SDK interface grep (recorded in the spec §1); `T…` for the
content types; `A…` for accessibility (`DN-N`).

**Cost if wrong.** If SwiftUI hard-deprecates the requested spelling, MetalUI
callers porting from SwiftUI see the old spelling only; adding the
`DropSession` overload later is additive.

---

## DN-B — `Transferable` is MetalUI's own, synchronous, `Data`-based protocol with conformance-carrying content types; String, URL and Data conform as SwiftUI's do

**Ruling.**

1. **Not CoreTransferable.** `CoreTransferable` does not exist off Apple, and
   its representation builder is asynchronous; MetalUI's drop path delivers
   items inside one input event on every platform, so an `async` import would
   need a second frame and a callback MetalUI's surface does not have. The
   protocol (spec §3.1):
   ```swift
   public protocol Transferable {
       var exportedContentTypes: [ContentType] { get }          // instance: a web URL and a file URL differ (T4)
       static var importedContentTypes: [ContentType] { get }
       func exported(as contentType: ContentType) -> Data?
       init?(importing data: Data, contentType: ContentType)
   }
   ```
   The member names are CoreTransferable's (`exportedContentTypes`,
   `importedContentTypes`, `exported(as:)`, `init(importing:contentType:)`);
   synchronous and non-throwing. A file importing both MetalUI and
   CoreTransferable spells `MetalUI.Transferable` (migration note).
2. **`ContentType`** is an identifier plus the identifiers it conforms to:
   `ContentType(_ identifier:, conformingTo: [ContentType])`, conformance
   transitive, every type conforming to `public.data` and `public.item`
   except `public.item` itself. Built-ins, each with UTType's own chain:
   `.item`, `.data`, `.text`, `.plainText` (⊂ text), `.utf8PlainText`
   (⊂ plainText), `.url` (⊂ data), `.fileURL` (⊂ url). Matching: an offered
   type `o` satisfies an imported type `i` when `o == i` or `o` conforms to
   `i`.
3. **Built-in conformances, measured.** `String`: exported and imported
   `[utf8PlainText]`; export is UTF-8 (`T1`, `T5`–`T5c`); does **not** import
   from URL data (`T7b`). `URL`: imported `[url, fileURL]`; a web URL exports
   `[url]`, a file URL `[url, fileURL]` (`T2`, `T4`); bytes are the absolute
   string in UTF-8 (`T6`, `T6b`); does **not** import from plain text
   (`T7c`, `R3c`, `P16`) and does not export as plain text (`T6c`). `Data`:
   exported and imported `[data]`; imports any offered type, since every type
   conforms to `public.data` (`T3`, `P16b`: a String dropped on a `Data`
   destination arrives as its one byte). `AttributedString` (`T3b`) is not
   conformed — MetalUI has no attributed text.
4. **The platform seam carries no Foundation type** (`MetalUIPlatform` imports
   only `MetalUICore`/`MetalUIScene`): an outgoing representation is
   `DragRepresentation(type: PasteboardType, bytes: [UInt8])`, an incoming
   item a `DropItem` (its types, and a main-actor `load` closure per type);
   `PasteboardType` is `identifier` + `conformsTo`. MetalUI converts
   `Data ↔ [UInt8]` (`DN-C`).

**Evidence.** `T1`–`T7e`, `R3`–`R3g`, `P16`, `P16b`.

**Cost if wrong.** A caller needing an asynchronous or file-backed
representation (a large file promise) cannot express it; the protocol can grow
an optional requirement with a default later without breaking a conformer.

---

## DN-C — the platform seam: one new `InputEvent` case for drops in, one defaultless `PlatformWindow` requirement for drags out

**Ruling.**

1. **Incoming drops are input events**: `InputEvent.drop(DropEvent)` with
   `DropEvent` `.entered(position:items:)` / `.moved(position:)` / `.exited` /
   `.performed(position:items:)`. `items` is `[DropItem]?` on `.entered` —
   `nil` when the platform cannot know the payload until it is dropped (SDL,
   `DN-M`). **`onInput`'s existing `Bool` carries the answer**: for
   `.entered`/`.moved`, "an accepting destination is under the pointer" (the
   platform's copy-or-none operation); for `.performed`, "a destination took
   the drop". No new requirement is needed for incoming drops.
2. **Outgoing**: `func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool`
   on `PlatformWindow`, **with no default implementation** (`EV-AB`/`AN-AD`'s
   reason: a conformer that forgets it fails to compile rather than silently
   keeping every drag in the window). AppKit starts an `NSDraggingSession`
   (`DN-K`); SDL answers `false`, honestly (`DN-K` item 4); the test fake
   records each call and answers a settable value. Guard
   `aPlatformWindowWithoutBeginExternalDragDoesNotCompile`.
3. **Migration notes** (both public): a conformer outside this repository adds
   `func beginExternalDrag(_: [DragRepresentation], at: Point<Pixels>) -> Bool { false }`;
   an exhaustive `switch` over `InputEvent` outside the package adds a
   `.drop` case (or `default:`). The two in-repo compile-guard fixtures that
   spell a complete `PlatformWindow` (`ControlStateCompileGuards`,
   `TransactionCompileGuards`) gain the member — T rows, answers unchanged.

**Cost if wrong.** A platform that can start an OS drag only from inside its
own event loop (not from a callback) would need the hand-off to be a request
answered later; the `Bool` would then mean "requested". Neither platform here
needs that.

---

## DN-D — a drag starts on the first pointer move from a draggable; it outranks taps, long presses and clicks, and yields to a `DragGesture` that outranks it

**Ruling.** A `.draggable` is a **gesture-arena member** (`IX-D`) at normal
priority, in declaration order on its element (a later modifier is an outer
layer, `IX-D` item 3). Its recognizer:

1. **Begins on the first move of more than zero points** (`P17`: a 1 pt move
   begins a session; `P17z`: a zero-distance dragged event does not, and the
   element's tap fires). No slop: SwiftUI's own tap slop (`IX-C`) does not
   apply to it.
2. **Taps, long presses and clicks never hold it off**, on its own element or
   any other arena member, and all of them fail when the drag begins
   (`P1b`/`P1c` either declaration order, `P2f`, `P3b`/`P3c` a `Button`'s own
   `.draggable`, `P21` a double tap, `P22b`/`P22c` a draggable parent over a
   `Button` or tapped child). With no movement the drag fails at the release
   and the click or tap runs (`P1a`, `P3a`, `P22a`). This is a narrow
   exception in `GestureArena.isBlocked` for the draggable's leaf alone.
3. **A `DragGesture` that outranks it wins** by the arena's existing rule:
   an inner one (`P2b`: the gesture declared before the draggable; `P22d`: a
   child's), a high-priority one (`P2d`). An outer normal one loses (`P2a`,
   `P2c`).
4. **A simultaneous member runs its callbacks for the event that begins the
   drag, then stops, with no end** (`P2e`: `chg` once, then the drop, no
   `dEnd`).
5. **An inner draggable beats an outer one** (`P22e`).
6. **Unchanged dispatch order**: a `TextField`/`TextEditor`'s press and a
   `Slider`'s track run ahead of the arena (`Window.onInput`), and SwiftUI
   agrees — a draggable field selects and never drags (`P20`), a draggable
   slider slides (`P20b`).
7. **When it begins**: the arena is abandoned (every other member fails,
   none ends), `Window.active` is cleared (no pressed look, and the release
   is not a click), and `Window` opens a drag session (`DN-H`). A selectable
   `List` row's click therefore never runs: dragging a row does not select it
   (`P4b`); clicking it still does (`P4a`, `DN-E`). A pointer drag in a
   `ScrollView` never scrolled in either framework (`P5a`, offset 0).

**Cost if wrong.** If a real trackpad shows SwiftUI tolerating a jitter
before a drag begins, a draggable button becomes harder to click on a
trackpad in MetalUI than in SwiftUI; the threshold is one constant.

---

## DN-E — a draggable adds no opaque hit target: its region is a non-opaque hitbox that joins the arena by identity

**Ruling.**

1. `Handlers.isPointerTarget` does **not** count a draggable. An element whose
   only pointer ask is a draggable registers a **non-opaque** hitbox carrying
   its handlers (the primitive `insertHitbox(_:id:opaque:)` already allows
   one), so it blocks no click, hover or wheel that reached what is under it
   before — the "hit testing must not move" constraint, and the reason a
   `List` row whose *content* is draggable still selects on a click (`P4a`:
   the row's `onClick` is an ancestor of the draggable text, and
   `IX-D` item 2 keeps an ancestor's `onClick` out of the arena — an opaque
   draggable would have become the target and swallowed the click).
2. **Joining the arena**, against `lastHitboxes` and the one ranking
   (`DN-F` item 1): the target is still `topmostOpaqueHitbox`; its ancestors
   with gestures join as before (a non-opaque draggable ancestor is found by
   the same walk); additionally the **topmost draggable region above the
   target** in the target's layer — a later `(layer, index)` than the target —
   joins as the innermost member. With **no** opaque target at the point, the
   topmost draggable region alone forms the arena.
3. **Gated like a pointer handler**: by the one disabled gate (`DN-G`) and by
   `allowsHitTesting(false)` (a pointer-only scope, `OM-AK`; SwiftUI
   unmeasured), and absent under `hidden()`.
4. **The consequence, ruled, not numbered**: a draggable overlay over an
   unrelated button does not block the button's click in MetalUI, where a
   hit-testable SwiftUI view would. SwiftUI was not measured with a
   non-hit-testable draggable, so there is no measured answer to diverge
   from; the remedy is an `onClick`/`contentShape` on the overlay.

**Cost if wrong.** A tree relying on a draggable to block clicks to what it
covers sees clicks fall through; the fix is local to that tree.

---

## DN-F — the drop target is the topmost destination region by the one `(layer, index)` ranking; covering views do not block it, a presentation does

**Ruling.**

1. **One ranking, two eligibilities.** `topmostOpaqueHitbox(in:at:)` becomes
   `topmostHitbox(in:at:where:)` with the opaque filter as one instance; the
   `(layer, registration index)` ordering exists once. A destination
   registers a **non-opaque** hitbox carrying only its drop handler; the
   target is the topmost of those containing the point.
2. **Covering views do not block a drop** (`P15a` a plain colour, `P15b` a
   tapped one, `P15c` a non-hit-testable one, `P15d` a `Button` — each over a
   destination, each drop delivered), **the deepest destination wins**
   (`P13a`: the inner of two nested String destinations takes the drop, and
   the outer turns `false` when the pointer enters the inner), and **a
   deepest destination that refuses the type targets nothing and does not
   pass the drop outward** (`P13c`: over an inner URL destination a String
   drag un-targets the outer and drops nowhere; `P16`: a URL dragged onto a
   String destination never targets it).
3. **`allowsHitTesting(false)` does not gate a destination** (`P15e`): its
   region is registered outside that gate, as a scroll region is (`OM-AK`).
   **`hidden()` does** (`R5d`: a hidden destination answers `none`).
4. **A presentation blocks a drop beneath it** (MetalUI's choice,
   unmeasured — SwiftUI's sheets and popovers are separate windows): when the
   topmost **opaque** hitbox at the point is on a higher layer than the
   destination, nothing is targeted. `IX-Q`'s reasoning (a presentation's
   press does not reach its presenter) applied in the other direction; it
   keeps a modal's scrim from leaking drops to the page under it.
5. Resolved against `lastHitboxes` (the last drawn frame), as every pointer
   event is.

**Cost if wrong.** A layered presentation designed to *accept* drops on the
page beneath (none exists in-repo) would need its own destination.

---

## DN-G — a disabled source does not drag and a disabled destination refuses (divergence 100)

**Ruling.** Both registrations sit inside `Frame.registerHandlers`' one
disabled gate (`EV-D`, `EV-E`): a disabled element registers no draggable
region and no destination region. **SwiftUI disagrees on both** — a
`.disabled(true)` source still drags (`P9`) and a disabled destination still
takes the drop (`P8`; `R5`/`R5b` agree through the fake) — so this is
**divergence 100, added, kept, owner none**. Reasons: the task's own
requirement ("a drop on a disabled destination is refused"); MetalUI's
`.disabled` has meant "no pointer target" since `EV-E` (divergence 23 is the
same choice for clicks), and making drag and drop the one pointer behaviour
that ignores it would need a second, ungated registration path; SwiftUI's own
answer to "refuse while disabled" is the `isEnabled:` parameter of the
`DropSession` overload MetalUI does not offer (`DN-A`).

**Cost if wrong.** A SwiftUI port that disables a well while still wanting
drops loses them; the remedy is not to disable it.

---

## DN-H — the drag session: `isTargeted` order, the action's arguments, what the platform is told

**Ruling.** `Window` holds at most one drag session (source id, the payload's
representations exported at the start, the press point, the pointer, the
current target). Every transition below runs from input, under
`StateDispatch` to the element whose closure it is (`ID-F`):

1. **`isTargeted(true)`** when the pointer enters an accepting destination
   (`DN-F`); **`isTargeted(false)`** when it leaves, before the next
   destination's `true` (`P14`: `AT=false,BT=true`; `P13a`), when the drag
   is cancelled (`P7`), and **before the action** on a drop (`P0`, `R1b`:
   `dT=false` then the action). Re-entering targets again (`P10`); holding
   still sends nothing more (`P19`). A refusing destination is never
   targeted (`P16`).
2. **The action** receives every offered item that imports, in offered order
   (`R3f`: two strings → `["one", "two"]`), at the drop point **in the
   destination's own coordinates** (`P12a`: window (330, 140) on a target at
   x = 200 reads (130, 140)). An item imports through the first of its
   offered types that satisfies one of `T.importedContentTypes`. If no item
   imports, the action does not run.
3. **What the platform is told** (`.performed`'s `Bool`): `true` when the
   action ran, whatever it returned (`R4`: SwiftUI's
   `performDragOperation` answered `true` for an action returning `false`).
4. **Drops resolve against the last drawn frame**; a source that vanishes
   mid-drag (a `List` row windowed out, an `if` gone false) does not end the
   session — the payload was exported at the start (`DN-J` keeps its last
   snapshot).
5. **A self-drop is allowed** (`P11`: a draggable that is also a destination
   takes its own drop).
6. **No `StateTable` entry**: the session lives on `Window`, so
   `theSevenRetentionSlotsAreMutuallyDistinct` and every id path are
   untouched; the session's own state never enters a frame's `@State`.

---

## DN-I — Escape cancels; so does a release over nothing that accepts

**Ruling.** During an in-window session, `keyDown` Escape cancels — target
`false`, no action, the preview gone — and is claimed **ahead of the keymap**
(`P7`: `T=false`, `ended with operation cancel`, no drop). A release over no
accepting destination cancels the same way; the release is never a click
(`DN-D` item 7). Other keys pass through unchanged. After an AppKit hand-off
(`DN-K`) Escape is the system session's.

---

## DN-J — the preview: the source's own primitives, replayed above everything at 70% opacity; a `preview:` closure replaces it

**Ruling.**

1. **Default: a snapshot.** While a session is open, the source element's
   paint is captured through the transition machinery's capture scope
   (`Frame.transitionScopes`, an identity `TransitionPaintScope` pushed by
   `paintDecoration`'s caller for a `StyledElement` source and by the
   proposal wrapper for a proposal one) — so a frame with no session pays
   nothing and emits exactly what it emitted before. After every other paint
   (after `paintGhosts`), the captured primitives are re-emitted **translated
   by (pointer − press point)**, at **opacity 0.7**, on a layer above every
   layer the frame used, each masked to the snapshot's own translated bounds
   (so a source half-clipped by a scroller shows whole). The source keeps
   drawing where it is (`P18`: the source's pixels read the same mean colour
   mid-drag as the no-drag control `P18c`). A source not painted this frame
   keeps its last snapshot (`DN-H` item 4).
2. **Opacity 0.7 is MetalUI's reading of an imprecise measurement**: `P18`'s
   preview over white reads mean (246, 176, 108), an alpha between 0.58 and
   0.75 depending on the channel (the drag image's shadow blends in); `P18b`
   (a blue custom preview) reads 0.62–0.70. The grab-point anchor (the
   preview keeps the press point under the pointer) is AppKit's default drag
   image placement, **unmeasured** in SwiftUI.
3. **`draggable(_:preview:)`** replaces the snapshot with the closure's
   element (`P18b`), laid out while the session is open as a `Deferred`
   presentation root positioned at the pointer (its own native run, `LR-CH`),
   opacity 0.7, registering no hitbox. It is a **wrapper on both
   vocabularies** (`DraggablePreviewModifier`, one identity level: content
   numbered from 0 under it, the preview at cursor 1 — never `-1`, which is
   `.overlay`'s, `MC-P`), so only callers of this new spelling get a new
   level; no existing id moves.
4. The preview is a look a human checks (spec §8, human-checks group N);
   every number above is pinned headless.

---

## DN-K — leaving the window: AppKit hands the drag to an `NSDraggingSession`; SDL keeps it in the window (divergence 101)

**Ruling.**

1. **SwiftUI's drag is a system session from the start** (`P6`: phases
   `initial`/`active`/`ended with operation cancel` for a 1–8 pt drag;
   `P6c`: a drag 300 pt out of the window stays active and ends cancelled),
   so it leaves the window with its preview. MetalUI's session is in-window
   (it must work on SDL and under the test fake), and **hands off at the
   window's edge**: the first `mouseDragged` outside the content bounds calls
   `beginExternalDrag(representations, at:)`; on `true` the in-window session
   ends silently (target `false`, preview gone, `active` and the arena
   cleared — AppKit's session swallows the release, so nothing else would
   clear them); on `false` it continues, and a release outside cancels.
2. **AppKit**: `MetalHostView` keeps the last `mouseDragged` `NSEvent` and
   calls `beginDraggingSession(with:event:source:)` with one
   `NSDraggingItem` whose `NSPasteboardItem` carries every representation;
   its own `NSDraggingSource` answers `.copy` (`P6b`: `ended with operation
   copy`). **The drag image is AppKit's representation of the payload, not
   MetalUI's preview**: a file URL's Finder icon, otherwise a rounded badge
   with the text (MetalUI's renderer draws into a drawable, not an `NSImage`;
   `renderFrame` returns a `Scene`).
3. **A handed-off drag that comes back** arrives through `NSDraggingDestination`
   as an external drop (`DN-L`) and reaches the same destinations.
4. **SDL answers `false`**: SDL3 has no API to start an operating-system drag
   (`SDL_events.h` 3.4.16 lists only the five `SDL_EVENT_DROP_*` *incoming*
   events). With SDL's default mouse auto-capture the window keeps receiving
   motion outside itself, so the preview follows and a release outside
   cancels.
5. **Divergence 101, added, kept, owner none**: outside the window the
   AppKit drag image is the payload's, not the preview (`P18`'s translucent
   snapshot travels with SwiftUI's), and on SDL a drag cannot leave the
   window at all.

---

## DN-L — AppKit drops in: the host view registers once and maps `NSDraggingDestination` onto `InputEvent.drop`

**Ruling.** `MetalHostView` registers for `public.item`, `public.data`,
`public.url`, `public.file-url` and `public.utf8-plain-text` once, at
creation (SwiftUI's destination view registers `public.data|public.item`,
`R0b`–`R0e`, and only while a destination exists, `R0a`; registering always
costs nothing visible — with no accepting destination `draggingEntered`
answers no operation). `draggingEntered`/`Updated` → `.entered`/`.moved`
(the location flipped to MetalUI's top-left points), answering `.copy` when
`onInput` says a destination accepts, else none — whatever the source's
operation mask (`R10`: SwiftUI answers `copy` to a move-only source too); `draggingExited` →
`.exited`; `performDragOperation` → `.performed`, answering its `Bool`.
Each pasteboard item becomes a `DropItem` whose types are its
`pasteboardItem.types` with each one's `UTType` supertypes as `conformsTo`,
and whose `load` reads `data(forType:)` **only when a destination imports
that type** (lazily: a Finder drag of a large image reads nothing it does not
deliver).

---

## DN-M — SDL drops in: the five `SDL_EVENT_DROP_*` events become one drop session; types are unknown until the drop (divergence 102)

**Ruling.**

1. `SDLBridge.c` translates `SDL_EVENT_DROP_BEGIN/POSITION/FILE/TEXT/COMPLETE`
   into five new `MUI_EVENT_DROP_*` kinds carrying `x`, `y` (window points)
   and `text` (the path or the text). `SDLWindow` turns a run of them into
   one session: the first position (or the first item, if no position came)
   sends `.entered(position:, items: nil)`; each later position `.moved`;
   `COMPLETE` sends `.performed(position:, items:)` with the items gathered
   since `BEGIN` — a `FILE` as `public.file-url` (its bytes the file URL
   string, percent-encoded, a Windows drive path as `file:///C:/…`), a `TEXT`
   as `public.utf8-plain-text` — or `.exited` when none arrived. Positions
   arrive where SDL gives them (Cocoa, X11, Wayland, and Windows' OLE drop
   target in SDL 3.4); a platform that gives none drops at the last known
   pointer position. An ordinary pointer motion event while a session is open
   ends it with `.exited` (a backend that sends no `COMPLETE` on leaving).
2. **Types are unknown while hovering** (SDL delivers data only at the drop),
   so `.entered`'s items are `nil` and `Window` **targets the deepest
   destination optimistically** — `isTargeted(true)` whatever its type; at
   the drop, items that do not import are filtered and a destination that
   imports none runs no action (and turns `false`). SwiftUI targets only a
   destination whose type matches (`P16`) — **divergence 102, added, kept,
   owner none** (SDL-only; the AppKit backend knows the types and matches
   SwiftUI). Also SDL-only, inside the same row: a URL dragged from a browser
   arrives as text, so a `URL` destination refuses it (`T7c`'s rule).
3. **The C enum hazard**: every new `MUI_EVENT_DROP_*` comparison converts
   explicitly (`Int(MUI_EVENT_DROP_FILE)`, as every existing case does);
   Windows CI alone sees a miss.

---

## DN-N — accessibility: SwiftUI publishes nothing for a draggable or a drop destination, and neither does MetalUI

**Ruling.** Arms `A1`–`A4` publish exactly `A0`'s tree — same roles, values,
perform selectors (`Press`, `ShowMenu`), attribute counts, no custom actions,
no drag or drop attribute — for `.draggable`, `.dropDestination`, a
draggable `Button`, a labelled destination colour and `.onDrag`/`.onDrop`.
macOS has no accessibility drag action (`accessibilityDragSourceDescriptors`
is UIKit's). So MetalUI adds **no** `AXNode` field, role, action or custom
action: an element's published node is identical with and without
`.draggable`/`.dropDestination`, on the neutral tree, the AppKit bridge and
AccessKit — pinned on each (spec §6, lane 3). Not a divergence: the answers
agree. A VoiceOver user drags as a pointer user does (VoiceOver's own
mouse-down/up commands), which the human-checks list notes and does not
require.

---

## DN-O — focus, hover, animation: unchanged

**Ruling.** A drag neither focuses its source nor its destination (no
`ClickDispatch` focus request runs; a selectable row's click never runs,
`DN-D` item 7). Hover tracking is unchanged — a `mouseDragged` already moved
`lastMousePosition` before this work. An `isTargeted` write is an input write
(a `@State` highlight animates under `withAnimation` inside the closure, like
any other input write). No `StateTable` slot is added (`DN-H` item 6); the
preview closure's subtree has ordinary identity under its wrapper.

---

## DN-P — identity: the `StyledElement` spellings return `Self`; the proposal spellings wrap once

**Ruling.** On `StyledElement`, `.draggable(_:)` appends to `Handlers.gestures`
and `.dropDestination` sets the new internal `Handlers.dropDestination`
(replaced by a later write, `onClick`'s one-field rule — SwiftUI agrees:
`R6e`, two chained destinations on one view, delivers to the outer only);
both return `Self`, so no id moves. On `ProposalElementGroup` each wraps the
receiver once (`DraggableModifier`, `DropDestinationModifier`, the
`GestureModifier` recipe: one identity level, one native child). `Handlers`
gains **one** member (`dropDestination`, a class box — one reference,
`IX-N`'s Windows stack budget); the draggable rides `gestures`.

---

## DN-Q — the demo variant and the human checks

**Ruling.** `METALUI_DND_DEMO=1 swift run MetalUIDemo` (and the same variable
for `Backends/SDL`'s `MetalUISDLDemo`) opens "MetalUI — Drag and Drop",
920×560, built by `dragAndDropDemoContent()` in
`Sources/MetalUIDemoContent/DragAndDropDemo.swift`, each section its own
function (the Windows stack rule). Contents and expected looks: spec §7.
`docs/verification/human-checks.md` gains group **N** (spec §8). Neither the
default demo nor any of the fourteen offscreen images builds a draggable or
a destination, so all fourteen read 0 px against `053a3b3` and
`Expected.swift` is unedited.

---

## DN-R — lanes, verification, what must not move

**Ruling.** Three lanes, run strictly in order (one agent at a time), files
disjoint except for the two one-line seam conformances lane 1 adds (spec §5):
**lane 1** the seam and everything in `MetalUI`; **lane 2** AppKit in and
out; **lane 3** SDL, accessibility parity, the demo, human checks and the
divergence/API docs. Every test is named in spec §6 with its red-before and
the mutation that must redden it. Must not move: spec §9.
