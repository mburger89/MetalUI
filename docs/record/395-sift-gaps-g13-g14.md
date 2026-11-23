# 395: Sift gaps G13 (tertiary colour), G14 (memo-boundary writes) and the Linux first redraw (`CR-AE`, `IV-S`, divergence 243)

Class `D` (one divergence, no API). Branch `fix/sift-gaps-g13-g14`, base master `3f1b2bb7`. Requested by Sift (`~/Developer/Sift`,
design spec section 11, gaps G13 and G14, and a Linux note in `GridCostTests`). All three turned out to be documentation of existing
behaviour; the code is unchanged.

## G13: a tertiary label colour: already there, as a `ShapeStyle`

`Color` has `.primary` and `.secondary` and nothing else in SwiftUI too; `.tertiary` and `.quaternary` are hierarchical `ShapeStyle`s and
MetalUI has had them since `HY-A` (0.306 / 0.292 and 0.116 of the theme text colour over no parent, `Theme.textTertiary` overriding).
`CR-AD` item 2 had already ruled "there is no `Color.tertiary` (SwiftUI has none)". No API added; divergence 116 unchanged; ruling `CR-AE`
points Sift at `.foregroundStyle(.tertiary)` instead of `Color.secondary.opacity(0.6)`. Pin: `TertiaryLabelTests` (an italic sized cell
marker, both appearances, tertiary and quaternary). Mutation: `.tertiary` light 0.306 to 0.3 reddens it.

## G14: a write read only below a memo boundary rebuilds each plain ancestor once: a documented limit, now divergence 243

Reproduced in MetalUI (`MemoBoundaryWriteCostTests`): plain `Top` > plain `Middle` > `.equatable()` reader plus a memoized sibling; one
write to the property only the reader reads gives reader +1, `Top` +1, `Middle` +1, sibling 0, and a settled window afterwards. Cause: not
a mis-attribution. The read dirties the window and a dirty window runs the whole build recursion, which evaluates every plain `Component`
and skips only `.equatable()` ones. Per-scope attribution (SwiftUI's "re-run only the readers": probe `swiftui-incremental-invalidation.swift`
arm `R`, parent not re-run, already on record) was ruled out of C14 slice 1 by `IV-C` item 4 and left to `IV-H`. Not fixed here: it needs every
read site wrapped, a missed one goes silently stale. Ruling `IV-S`, divergence 243 (live 234, next label 244). The remedy that works today is
the one Sift already uses: write the ancestors `.equatable()` (pinned: ancestors 0, reader 1). No new SwiftUI probe: arm `R` answers it.

## Linux: the first redraw after a window settles: not reproduced; one nondeterminism found

Sift's note ("on Linux the first redraw re-requests every element; warm up with one keystroke") has no doc of its own; `IV-Q` and `MO-C` say only that
off Darwin the observation hop lags. Tried in a `swift:6.4-noble` aarch64 container (`metalui-siftgaps-run`, volume `metalui-siftgaps-build`, both
removed): a settled window with a heavy `.equatable()` subtree (text rows, one reading an `@Observable`, and a 1000-row `Table`) beside a
sibling that redraws, driven by an `@Observable` write and by a focused field's typing: the first redraw costs what the second and third cost,
on Linux as on macOS (`theFirstSiblingRedrawBesideASettledMemoReplaysAsTheSecondDoes`, `theFirstKeystrokeBesideASettledMemoCostsAsTheLaterOnesDo`,
8 of 8 Linux runs). The pins are not vacuous: a mutation that drops every other retained record at `finishRetainedPaint` makes the first redraw
cost 10 (and 207 with the table) against 1 (2). What Linux did show is a second frame after some single writes (1 or 2 frames across runs): the
dirty-mark hop. A second frame rebuilds every plain component again and the memoized reader not at all, so the G14 pin counts plain builds per frame
(exactly one frame is asserted on Darwin only). Sift's own first-redraw cost therefore most likely comes from that extra frame arriving after a
warm settle, or from a Sift-side state (its async page load) the fixtures do not have; Sift keeps its warm-up keystroke. Minimal repro to reach it
on Sift's side: log `window.frameWork.count` and `elementRequests` per frame around the first `typeText` on Linux.

## Verification

Mutations (each restored, `git status` checked): `MemoFlags.fireMemo` without `_stale = true` reddens the two cost pins; `MbTop.==` false
reddens the memoized-ancestors pin; the unread write made a read reddens the control; the `finishRetainedPaint` every-other-record drop reddens the
two first-redraw pins; `.tertiary` 0.3 reddens `TertiaryLabelTests`. New tests: `MemoBoundaryWriteCostTests` (7 cases in 5 tests), `TertiaryLabelTests` (2 in 1).
