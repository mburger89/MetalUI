# Record §05 re-derived — decisions (prefix `RD-`)

Rulings for round-3 item R3-10 item 8: re-derive the declared-but-inert list from the source instead of from
the dated record. Branch `docs/record-05-rederive` from master `e92c1751`. No `Sources/`, `Tests/` or
`Package.swift` change. Artifacts: `docs/record/05-declared-but-inert.md` (the list),
`docs/probes/record-05-check.sh` (the check), `docs/probes/closeout-inventory-map.tsv` (the `record §05` family
tokens). Record: `docs/record/196-record-05-rederived.md` (the method, the verdict ledger, the old text frozen).

**State.** Every ruling is built. No divergence label used or reserved. **Next unused: `RD-G`.**

## RD-A: what a row is

A row is a declaration the compiler accepts that an author can write or read in expectation that the framework
acts on it, and that, in the context named in the row, is stored and has no production reader that changes
layout, paint, input, accessibility or platform output.

- **Not production readers:** tests; `MetalUIDemo*`/`MetalUIDemoContent`; the retained verify snapshots
  (`captureRetainedVerifySnapshot`, the retained ledger); equality, diff and fingerprint code
  (`EnvironmentValues.swift`'s diff list); a named test seam (`TestingHooks.swift`).
- **Context scoping.** A declaration that works somewhere is a row only for the contexts where it does nothing,
  and the `inert where` column names them (`controlSize` on a switch `Toggle`, a `Picker`, a `Slider`; `tag`
  outside a `Picker`; `margin` under a stack parent).
- **Not rows:** a function that does what it says (no caller is dead code, not inertness: `LayoutTree.reset`);
  a deprecated declaration whose message says what it does (the warning is the non-silence: `AXNode.actions`,
  `frame()`); a value the framework produces for an author's code to read (events, metrics, queries, a draw
  context: outputs); the discarded component of a value that has no meaning in the context (`scrollTo`'s
  cross-axis anchor on a one-axis scroller); a protocol-conformer hazard documented at the requirement
  (`_wrap`); a renderer limit that is not a declaration (colour glyphs); a lowering rule (`margin: .auto`
  lowers as 0).
- **Environment keys are inputs** when SwiftUI has a namesake whose built-ins can react, even when the window
  stamps the value (`colorSchemeContrast`, `locale`); a MetalUI-only stamped value (`windowSize`,
  `titleBarInsets`) is an output.

This supersedes the old file's implicit scope (stored-and-unread anywhere, including functions with no caller
and deprecated spellings). Items that left because of it are in record 196 section 3.1 with their reasons.

## RD-B: the boundary with `docs/divergences.md`

Generalises `AD-`'s line (`2026-11-02-accessibility-display-decisions.md`, `AD-I`). If SwiftUI's built-ins
measurably react in the inert context, the row carries that divergence label and is in both lists: §05 indexes
the inertness, the divergence compares with SwiftUI. If SwiftUI does not react, or it was not measured, the
divergence column is `none`. A documented absence (class R, not declared) and a renderer limit that is not a
declaration are not rows. The `SwiftUI (macOS) does` column is carried from the cited probes and rulings; a
row's author re-measures it only when the row is about SwiftUI.

## RD-C: keys

One public row per census key `(target, owner, name)`; overloads share it, and an overload set spanning two
inventory families names one family. `closeout-public-api.sh` lists `public` and `open` declarations only, so a
protocol requirement (`PlatformWindow.onInput`), an internal declaration and a `package` one go in the internal
table, keyed by `file` and an ERE of the declaration line. The internal table is the set the old file named,
re-verified, plus what the 196 sweep found; it is not a census of internal counters.

## RD-D: history and future edits

The old §05 is frozen verbatim in record 196 (section 7, behind a marker line; `cmp` checks it). The file gets
no new dated sections: a milestone that adds, narrows or deletes an inert declaration edits the table in place,
says so in its own record, adds or removes `record §05` on the inventory family and runs the check. A new
inert row owes a reader grep, as the ledger in 196 shows.

## RD-E: the inventory link and the check

A family carries `record §05` in its behaviour column if and only if it has a public row. A family shared by live
and inert members carries the token if any member has a row. `zsh docs/probes/record-05-check.sh` prints one line
per problem and nothing when consistent: `MARKER`, `CELLS`, `NODECL`, `DUP`, `FAMILY`, `NOFAMILY`, `UNLINKED`,
`ORPHAN`, `PIN`, `LIVE`, `RULING`, `INTERNAL`. It is not wired into the suite, as the closeout probes are not;
CLAUDE.md names it. It cannot read meaning: that a declaration is inert is the reader grep's claim.

## RD-F: carried, not fixed here

Recorded in record 196 section 6 for a follow-up; each would need a `Sources/` or `Tests/` change or belongs to
another document.

- Divergence 76's `Toggle … read nothing` cell is false for the `.button` style (`Toggle.swift:146`).
- `Box.swift`'s doc still says baseline "falls back to flexStart until text metrics exist"; fixed at `TE-L`.
- `docs/probes/closeout-public-api.tsv` is stale (3874 lines against 4422 live).
- 31 comments in `Sources/` and `Tests/` still say "CLAUDE.md's inert table"; the table is this file.
- `FrameLayer.swift`'s doc table still describes the legacy single-infinite-maximum arm as inert.
- The census omits protocol requirements; the internal counters (`buildCount`, `publishCount`, …) are not
  enumerated; context-scoped inertness is found only where something documents it (the sweeps cannot see an
  undocumented one: `margin` under a stack parent was found by reading the lowering, not by a sweep).
- `ElementGroup.transition` nested is measured inert (probes X15, X15b, X16) but has no divergence label; if SwiftUI
  applies a nested transition it is an unlabelled divergence.
- Four pins named by the old text are gone or renamed (`paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt`,
  `aPopoverHasNoAttachmentAnchorParameter`, `autoMarginsResolveToZeroForNow`, `controlSizeReachesNoBuiltInMeasurement`).
