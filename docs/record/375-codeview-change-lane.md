# 375 - The change lane in `CodeView` (`CV-BS`)

Branch `feat/codeview-change-lane` from master `9dc1e9a8`. Class M, no divergence (labels untouched). Alloy's wave-2 request: a version-control mark that shows beside an author's gutter bar on one row.

**Rule.** `CodeLineDecoration.changeBar: CodeChangeBar?` (`.added`, `.modified`, `.deletedAbove`, each with a colour) draws in a 4 pt lane (3 pt bar, 1 pt gap) between the numbers and the fold chevrons; the gutter bar stays at the right edge. The lane is sticky by default and `CodeView.changeLane(_:)` reserves or removes it (`false` also hides the bars). Merged per field by owner priority (`CV-AO`). `.deletedAbove` is VS Code's triangle at the row's top edge, drawn as one-pixel rect strips in the gutter pass. A press is `CodeGutterHit.Source.changeBar` (`lines` the run with the same bar and tag, `tag`, owner; a folded header shows the first hidden change as `.modified`). `Source` is not frozen: it may gain cases.

**Costs.** Steady and keystroke literals unchanged with and without change bars (`changeBarsCostWhatNoneCost`).

**Tests** (`CodeViewChangeLaneTests`); mutations are recorded in the test doc comments.
