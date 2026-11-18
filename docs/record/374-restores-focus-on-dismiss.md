# 374 - `restoresFocusOnDismiss()` and popovers returning focus (`KF-AM`, `MN-AS`)

Branch `feat/restores-focus-on-dismiss` from master `9dc1e9a8`. Class M, no divergence (labels untouched). Alloy's palette request (an in-tree overlay that gives focus back) and the popover-with-a-field follow-up.

**API.** `ElementGroup.restoresFocusOnDismiss(_ enabled: Bool = true) -> RestoresFocusScope<Self>`: a transparent scope (`Sources/MetalUI/RestoresFocus.swift`), `PresentationScope`'s conformances.

**Mechanism.** Layout keys the scope; prepaint pushes the key, and a focusable registered under it names its scopes in `FocusRegistry`. `Window.restoreRecords` holds the element focused when focus entered each scope (`noteRestoreTransition` from `focusedElement`'s `didSet`). `Frame.dropFocus` replaces the two drop sites (`IX-I`'s post-sweep clear, `resolveFocus`'s retention drop): innermost scope not produced and its record focusable gives focus to the record and asks one more frame. Records of unproduced scopes are pruned after each frame, so no scope means no map. A popover's presented content is such a scope, keyed by the modifier's id (`MN-AS`).

**Decisions.** `KF-AM`, `MN-AS` (amends `MN-N` item 3). Alloy's answer 9: a recorded element that is gone leaves nil. No cascade to an outer scope when the innermost target is gone.

**Costs.** No scope: no element request moves (`appsWithNoScopeCostWhatTheyCost`, literals equal to master `9dc1e9a8`); a restore is one extra frame.

**Tests.** `RestoresFocusTests` (portable, harness text system). PR #373's `focusAfterDismissIsNil` (branch `test/popover-field-focus`) asserts the old nil and flips to the view once both are merged.
