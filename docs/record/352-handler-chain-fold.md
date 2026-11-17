# 352 - Two handlers before a frame cost no request (`KF-AF`)

Branch `perf/handler-chain-fold` from master `49630aaf`. Class M, no divergence; new public declarations are framework entry points (`_wrapInScope`, `_wrapLayoutInScope`, `LifecycleScopeRegistration`).

**Report** (Alloy): on a `CodeView` chain `...suggestionOverlay(...).onKeyPress(...).onDisappear(...).frame(...).accessibilityIdentifier(...)` a keystroke frame costs +1 element request against the chain without the two handlers; either handler alone before `.frame` costs 0, both (either order) +1, both after `.frame` 0.

**Measured** (suggestion overlay open, 49630aaf): 7 requests with neither handler, 7 with either alone, 8 with both in either order, steady and keystroke; both after the frame 7. Cause: `LifecycleScope` used the default `_wrap`, so a `.frame` after `onKeyPress` (a wrapper chain over the `PopoverModifier`) and `onDisappear` (a scope over it) started a second chain around the scope. The same shape cost +1 on a legacy chain (3 vs 2), a `Pair` with a handler (4 vs 3) and a proposal chain (4 vs 3).

**Fix:** `LifecycleScope<C>` declares `LayerBase`/`ProposalBase` as the scope around `C`'s base and forwards `_wrap`/`_wrapLayout` to the new `_wrapInScope`/`_wrapLayoutInScope` requirements, which `ModifiedContent` answers by keeping its layers and putting the scope around its base. Content under such a chain moves one identity level (one chain fewer).

**Tests:** `HandlerChainFoldCostTests` (CodeView literals, six shapes) and `ElementGroupKeyPressCostTests` A-C (legacy chain, `Pair`, proposal chain, handler and lifecycle behaviour). Mutation: revert the Sources diff: both-before-frame 8 against 7 (CodeView), +1 on every family; behaviour test C passes either way.
