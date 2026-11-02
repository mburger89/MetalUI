# `DropDelegate` — decisions (prefix `DE-`)

Rulings for round-3 item R3-10 item 5: SwiftUI's `DropDelegate` family. Branch `feat/drop-delegate` from master `4026f5ab`. Code:
`Sources/MetalUI/DropDelegate.swift` (new), `DragAndDrop.swift`, `DragSession.swift`, the `PlatformWindow.setDropOperation` seam
(`Platform.swift`, `InputEvent.swift`, AppKit, SDL, `MetalUITesting`). Probe: `docs/probes/swiftui-drop-delegate.swift`. Tests:
`DropDelegateTests.swift`, `DropDelegateHeadlessTests.swift`, an AppKit arm in `AppKitDragAndDropTests.swift`, three guards in
`DragAndDropCompileGuards.swift`, a row in `OuterModifierMatrixTests.swift`. Record: `docs/record/192-drop-delegate.md`.
**Next unused: `DE-K`.** Divergences 1055 and 1056 (reserved 1055–1064; 1057–1064 unused — 1057 was measured, fixed, and is not a divergence).

SwiftUI's declarations (macOS 27 SDK): `protocol DropDelegate { validateDrop(info:) -> Bool; dropEntered(info:); dropUpdated(info:) -> DropProposal?;
dropExited(info:); performDrop(info:) -> Bool }` with defaults for all but `performDrop`; `enum DropOperation { cancel, forbidden, copy, move }`
(`delete`, `alias` and the `Set` conformance are macOS 26); `struct DropProposal { init(operation:) }`; `struct DropInfo { location; hasItemsConforming(to:);
itemProviders(for:) }`; `View.onDrop(of:delegate:)`.

**How the probe reads.** It reuses group R of `swiftui-drag-and-drop.swift` (a fake `NSDraggingInfo`). It is trusted for which callbacks run, their order and
the `NSDragOperation` answered; **not for space** and **not for whether `performDrop` runs after a refusal** (the fake always calls prepare and perform). Two
readings that look odd rest on the fake alone and are labelled: F5 (a `nil` proposal after `.move` answers copy again) and F2 (`dropExited` after a
`validateDrop` that answered `false`).

## DE-A: the surface; `DN-A` item 2 reversed for the delegate

1. **Built**: `DropDelegate` (`@MainActor`, five methods, four defaults: validate `true`, entered/exited nothing, updated `nil`), `DropOperation`
   (`cancel`, `forbidden`, `copy`, `move`), `DropProposal(operation:)`, `DropInfo`, `onDrop(of: [ContentType], delegate: any DropDelegate)` on every
   `StyledElement` (returns `Self`) and every `ProposalElementGroup` (returns the existing `DropDestinationModifier`, one wrapper).
2. **`DN-A` item 2 is reversed for the delegate.** It left `DropDelegate` out because its payload is `NSItemProvider`, Apple-only. That reason no longer holds:
   `PasteButton` already stands `DropItem` in for `NSItemProvider` (`CP-B`, `CP-D`), and `DropInfo` does the same. The closure forms
   (`onDrag`, `onDrop(of:isTargeted:perform:)`) and the `[String]` overloads stay unbuilt.
3. One destination class: `DropDestinationTarget` gains an optional `delegate` (the existential lives in the class box, never on `Handlers`, `IX-N`).
   `onDrop(of:delegate:)` writes the same `Handlers.dropDestination` field, so no registration site is new: the gated insertion in `Frame.registerHandlers`
   carries it, and retained paths keyed on `dropDestination != nil` are unchanged.

## DE-B: call order

Probe `D0`, `D0x`, `F2`. Entering a destination runs `validateDrop`, then (when `true`) `dropEntered` and `dropUpdated`. Every pointer move over the same
destination runs one `dropUpdated`. A release runs `dropUpdated` then `performDrop` and **no** `dropExited`. Leaving (pointer out, Escape, the platform taking the
drag at the window's edge, the next destination) runs `dropExited` alone, before the next destination's `validateDrop`. After a `validateDrop` that answered
`false`, `dropEntered` and `dropUpdated` never run but `dropExited` still does on leaving (`F2`, harness-only). `Window.retarget` is the one place: a record on the
`DropTargetState` (validated, cancelled, operation, last point and items) is carried while the destination stays the same. Every callback runs through
`StateDispatch.dispatching(to:)`, from input, and writes no `StateTable` entry (`DN-H` item 6 holds). SwiftUI calls `dropUpdated` per `mouseDragged` and not while
stationary (`wantsPeriodicDraggingUpdates` is `false` in MetalUI); that rate is unmeasured for delegates.

## DE-C: `validateDrop`

Probe `D1`, `F1`, `F1b`. A drag whose items conform to none of the declared types reaches no callback and answers none (a refusing deepest destination passes
the drag to no outer one, `DN-F` item 2). Items are matched by conformance (`.item` finds a string), through `DropDestinationTarget.match`. With `validateDrop`
`false` the destination is still the target: the answer is none and an outer `dropDestination` is not consulted.

## DE-D: the proposal

Probe `D2`–`D5`, `D9`, `F4`–`F7`. `nil` proposes `.copy`, every time (even after `.move`, `F5`, harness-only); `.copy` answers copy; `.move` answers move (even for a
copy-only source mask, `D3b`); `.forbidden` answers none and `dropUpdated` keeps coming (`F6`, `F7`); `.cancel` answers none and no more `dropUpdated` comes until the
drag leaves (`F4`); re-entry validates afresh. The window tells the platform each answer through the new defaultless `PlatformWindow.setDropOperation(_:)` (`DE-H`).

## DE-E: perform

Probe `D0`, `D7`. A release performs only when the delegate was validated, did not cancel, and its last operation is copy or move; then `performDrop`'s `Bool` is what
the platform is told (a `dropDestination` always answers `true`, `DN-H` item 3). After forbidden, cancel or invalid, nothing is performed and the delegate gets
`dropExited` (AppKit does not call `performDragOperation` after a `none` answer; the probe's fake does, so its `[U,P]` after `none` is an artifact). Inferred from
AppKit's `prepareForDragOperation` documentation, not measured.

## DE-F: `DropInfo`

`location` is `Point<Pixels>` in the destination's own space (SwiftUI: `CGPoint`; probe `P12a` of the drag-and-drop probe agrees), the same in every callback.
`hasItemsConforming(to:)` and `itemProviders(for:)` match by conformance (`D8`: two strings are two providers). `itemProviders(for:)` returns `[DropItem]`, read
synchronously with `DropItem.load` (SwiftUI: asynchronous `NSItemProvider`; divergence 1056). While a drag from outside hovers on SDL the items are unknown
(`DN-M`): `hasItemsConforming` answers `true` and `itemProviders` is empty until `performDrop` (amends 102). `DropInfo` has no public initialiser. The delegate a
callback runs is the one in the last drawn frame (a snapshot, as every destination).

## DE-G: coexistence

Probe `F8`–`F10`. The outermost drop modifier on one view wins, for `onDrop(of:delegate:)` and `dropDestination` in either order: both write one `Handlers` field and
the later (outer) write replaces. **On the proposal path two chained drop wrappers registered outermost-first and the later region ranks higher, so the inner won
against SwiftUI's outer** (measured by `theOuterOfTwoProposalDropWrappersWins` before the fix: `AV,AE,AU` and `inner=true`). Fixed, contained: a
`DropDestinationModifier` tells a `DropDestinationWrapping` content directly inside it to register nothing (and that one passes it on), so exactly one region
exists per stack of wrappers. This corrects `dropDestination` as well. A wrapper over a view that registers its own destination at other bounds still follows
`DN-F`'s deepest-wins. No divergence is recorded for 1057.

## DE-H: the platform seam

`PlatformWindow.setDropOperation(_ operation: PlatformDropOperation)` is defaultless (`EV-AB`'s reason) beside `beginExternalDrag`;
`PlatformDropOperation` (`none`, `copy`, `move`) is public in `MetalUIPlatform`. `Window` calls it after resolving each external `.entered` and `.moved`: no target,
a refusing delegate, forbidden and cancel report `.none`; a `dropDestination` reports `.copy`; a delegate its mapped operation. The drop event's `Bool` answer is now
"an operation is not none". AppKit stores the last operation on `MetalHostView` and answers `.move` for `.move`, else `.copy`, `[]` when not accepting; the outgoing
source mask stays `.copy`. SDL ignores it (no feedback channel). `HeadlessPlatformWindow.dropOperations` records each call (`HT-X` 1). In-window drags report nothing:
there is no pointer drag cursor (divergence 1055).

## DE-I: not built

`DropOperation.delete`/`.alias`/`Set` conformance, `DropProposal.operationOutsideApplication` and `init(withinApplication:outsideApplication:)` (macOS 26, no
session design behind them; "Not offered" row). The closure `onDrop` forms stay unbuilt (`DE-A` item 2).

## DE-J: demo and human checks

The drag-and-drop demo gains a delegate destination chip (its own function, the 1 MB stack rule, `CI-AI`). Human-check group `DE` in
`docs/verification/human-checks.md`: (1) a Finder file onto `.copy`, `.move` and `.forbidden` delegates: the badge and Finder's outcome; (2) TextEdit text onto a
`.move` delegate; (3) a MetalUI drag handed to the system at the window edge and returned onto a `.move` delegate; (4) an in-window drag shows no badge (1055);
(5) SDL on Linux: a Nautilus file onto a delegate.
