# 371 - A focused `TextField` in `CodeView`'s text-anchored popover, pinned (`CV-BW`)

Branch `test/popover-field-focus` from master `9dc1e9a8`. Class M, no divergence, no public API, no product change (370 is a parallel gutterHelp branch). Alloy's code-intel request (a rename field in the popover).

**What was pinned** (`CodeViewTextAnchorTests`): the field takes the keys and the buffer is unchanged; `onSubmit` fires and the app dismisses by setting the item nil; Escape dismisses and the field's own `onKeyPress(.escape)` does not run (the popover key stage is first); a `@FocusState` write in the opening handler is dropped while `.onAppear { focused = true }` works on the second frame; focus after the dismissal is nil (`IX-I`, the test `MN-AS` will flip).

**Probe** `docs/probes/swiftui-popover-focus.swift` (PF1 first responder on open, PF2 focus back after dismiss, PF3 field Escape before close, with two positive controls). It compiles and ran once; the screen was locked, no window became key, every arm printed `UNRESOLVED`. Nothing was inferred; human checks `CV31`..`CV33` carry the arms.

**Follow-ups, waiting on the probe:** PF1 yes means a popover seats focus on its first `TextField`; PF3 yes means a divergence or reordered stages; `MN-AS` and `KF-AM` per the wave-2 design.
