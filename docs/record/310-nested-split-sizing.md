# 310 - A bare nested split view is flexible (`HS-J`)

Branch `test/nested-split-views` from master `2fbfcafc`. Alloy editor-group trees, class M, no new divergence label (divergence 206 amended). Ruling `HS-J` in `docs/superpowers/2026-10-30-split-view-decisions.md`.

**Found by** `NestedSplitViewTests` (depth-5 alternating nest in a clipped island, three clipped sibling islands): every nested layout, drag, autosave and hit-test case held, but a `VSplitView` that was a direct pane of an `HSplitView` stayed 10 wide of 600 while the plain pane took the rest, unless the nested split was wrapped in `.frame(maxWidth: .infinity, maxHeight: .infinity)`. The three-clipped-islands crash (`EXC_BAD_ACCESS` in `swift_retain`) did not reproduce.

**Cause.** `SplitLayout.sizeThatFits` answered the sum of the panes' ideals plus dividers for any non-finite main proposal, and the widest child's ideal for a non-finite cross proposal, so the parent's maximum probe (infinity) read back the ideal and the nested pane's maximum equalled its ideal.

**SwiftUI (probe `docs/probes/swiftui-nested-split-sizing.swift`, macOS 27.2.1).** A bare `VSplitView` beside `Color` in an `HSplitView` of 600 x 400 is 300 wide and the `Color` 299 at x 301; `H{V, V}` is 300 and 299. Asked through a custom `Layout`, both split views answer the proposal whatever their panes: zero 0 x 0, unspecified 0 x 0, infinity inf x inf, 300 x 200 itself, (inf, 200) inf x 200.

**Fix.** `SplitLayout.sizeThatFits` answers infinity for an infinite proposal on either axis (the panes are not solved against an infinite main axis; their ideals stand in for the cross-axis measure). A nil proposal still answers the sum of the panes' ideals where SwiftUI answers 0.

**Tests.** `aBareNestedSplitViewStretchesLikeSwiftUIs` (literals from the probe) fails without the fix (width 10); `aBareNestedHSplitViewInAVSplitViewStretches` was green before (the cross-axis case). The old known-issue test is now a plain passing test.

**Behaviour, not API.** See `docs/migration.md`.
