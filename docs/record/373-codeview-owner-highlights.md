# 373 - Owner-keyed range highlights in `CodeView` (`CV-BV`)

Branch `feat/code-owner-highlights` from master `9dc1e9a8`. Class M, no divergence (labels untouched). Alloy plugins request #1: a language server's diagnostics and a plugin's underlines must coexist in one layer. Alloy's binding answer 10: per-field priority merge, not the winning owner's whole style.

**API.** `CodeDecorations.setHighlights(_:in:layer:asOf:owner:)` and `highlights(in:layer:owner:)`. The overloads without `owner:` are unchanged.

**Merge.** Each (layer, named owner) is a sub-layer `RunTree`. `stylingOfLine` and `underlinesOfLine` walk `sources`, the default layer trees plus the sub-layers, ordered by (layer, priority, name), a tie to the later name as in `CV-AO`; the last foreground and the last underline win per stretch, backgrounds paint in order. `sources` is rebuilt at a set that creates a sub-layer or re-prioritises its owner, and at `removeDecorations(of:)`, never per frame. With no sub-layer the list is the layers array and the path is the old one.

**Validity.** Named owners are push-only and always valid: `rowsNeedingHighlights` and the provider ask read only the default syntax tree, edits splice sub-layers without staling them, a `.resync` empties them. A set that changes nothing creates nothing and does not redraw (`CV-AG`). `removeDecorations(of:)` drops the owner's sub-layers in every layer.

**Costs.** No named owner: `runsVisited`, `stylingComputations`, `needingHighlightScans` and the frame counters are the same as on master (`noNamedOwnerStylingIsByteIdentical`). A sub-layer costs one tree walk per line read and O(log n) per edit while it exists.

**Tests** (`CodeViewOwnerHighlightsTests`): `noNamedOwnerStylingIsByteIdentical`, `pluginUnderlineDoesNotReplaceLanguageServers`, `higherPriorityWinsPerField`, `removeDecorationsClearsHighlights`, `namedOwnerNeverAsksProvider`, `subLayerFollowsEdits`, `setThatChangesNothingDoesNotRedraw`. Mutations are in the doc comments.
