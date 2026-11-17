# 340 - A closed popover costs no element request (`MN-AR`)

Branch `perf/closed-popover-free` from master `66cfba26`. Class M, no divergence, no public API change (no inventory rows).

**Report** (Alloy): a closed `popover(item:attachmentAnchor:)` on a `CodeView` costs +1 element request per frame (+2 in larger trees). **Measured:** +1 for every closed `PopoverModifier` form, steady and keystroke, from `enteringGroupMember`'s count; modifiers after it add nothing (the claimed second +1 did not reproduce; a larger Alloy tree may carry a second popover).

**Fix:** `PopoverModifier` overrides `requestGroupLayout` and `requestProposalGroupLayout` to enter its identity level with `counted: false` and counts itself in `layOutPopover` once `presented()` is non-nil. Identity, state and node are untouched, so the anchor is not remounted on open/close.

**Tests:** `ClosedPopoverCostTests` (closed equals twin x5, closed literals, open literals, state across open/close/open); mutations in `MN-AR`.
