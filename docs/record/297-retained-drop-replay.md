# 297. A drop destination rides the prepaint ledger (`RW-W`)

Renumbered 293 to 297 at its merge with `master` (record 293 is `293-glass-immediate-input.md`, published first).

Branch `fix/retained-drop-replay` (built on `fix/retained-presentation-taint`, PR #294, now merged). Ruling `RW-W`. Class `M`; no public API, no divergence.
Source: Alloy G45 (the composer split into a drop-destination shell and `.equatable()` leaves: "because dragAndDrop" 97, steady frame 132 requests).

## Why

`closePrepaintWindow` refused a ledger when any hitbox in the window's range was a draggable or a drop destination. The range includes every nested occurrence's hitboxes, so a destination anywhere under an equatable ancestor made the ancestor, and with it the graft (which needs a ledger), ineligible. Scoping the taint cannot work (the holder of the destination has no ledger to compose from), so the destination has to be replayable.

## Change

One clause: `dropDestination != nil` leaves the prepaint taint; `hasDraggable` stays (a source captures paint into the drag snapshot and preview). `RW-W` reads why the rest needs nothing: the destination is a non-opaque hitbox with a closure bundle, `DragSession` reads `lastHitboxes` only, and the drag fields on `Frame` serve sources.

## Numbers (counts; `RetainedDropReplayTests`)

A plain root (typing above) over a retained column holding a card and the composer (a `.dropDestination` over the card, a menu `Picker`, a closed `.menuPresented` menu): element requests per steady frame **21 before, 2 after**; the column grafts every frame.

## Tests

Differentials against a retention-off window after the ancestors replayed: a drop (items and destination-local location, targeting true, false, true, false), a refused type, a code-opened menu then a drop, a moved composer (redone like any moved occurrence, the destination follows it), and a draggable that still refuses by name. Mutation: the destination's hitbox left out of the ledger (the drop and targeting logs differ; first three pins red); the taint clause restored (the count pin reads 21).
