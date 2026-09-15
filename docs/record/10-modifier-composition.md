## Modifier composition (plan task 3) — `feat/modifier-composition`, from 2026-09-15

The record for plan task 3. Spec
`docs/superpowers/specs/2026-09-15-modifier-composition-design.md`; rulings
`MC-A`…`MC-M` in
`docs/superpowers/2026-09-15-modifier-composition-decisions.md` (next unused
`MC-N`). The track runs in its own worktree,
`/Users/maxburger/Developer/MetalUI-modifier-composition`, beside two parallel
tracks, and is merged by an integration step that owns `CLAUDE.md`, the plan,
`docs/record/README.md` and the SA decisions doc. **Nothing in this file has
been copied into those yet.**

### Design session, 2026-09-14/15, at `f64e58a`

No source change was committed. What was run, and where its output lives:

| run | result | where recorded |
|---|---|---|
| SwiftUI probe `docs/probes/swiftui-modifier-identity.swift`, `/usr/bin/swift` and compiled `swiftc` | byte-identical stdout, exit 0. Arms: T (types nest), A/B controls, C/D2 value change keeps state, D1/D3 length change resets, E/F/G overlay/background views own distinct state, H control | the probe's header; `MC-A`, `MC-C`, `MC-E` |
| scratch test `scratchMeasureOverlayIdentity` (uncommitted, `--filter`, deleted) | primary and overlay ids **equal**; three clicks on the primary → primary 3, **overlay 3**; hover on the primary → **2** hover fills, 60 and 10pt | `MC-E` |
| the same, with the overlay's cursor threaded from the primary's | ids unequal; primary 3, overlay 0; 1 hover fill (60pt) | `MC-E` |
| whole suite with only that fix, `swift test --build-system native --no-parallel` | `Test run with 1085 tests in 1 suite passed` (1084 + the scratch test); no `error:`, no `warning:` | `MC-E` |
| scratch test `scratchMeasureOrphanLegacyNode` (deleted) | a marker conformer registering an unattached legacy node beside a native leaf renders with no trap: prepaint bounds 10×10, 1 rect | `MC-G` item 2 |
| typecheck skeleton `docs/probes/modifier-composition-skeletons/FlatChainOverloads.swift` | chains infer `ModifiedElement<Text>`, `ModifiedElement<Two>`, `Row<ModifiedElement<Text>>`; a contextual nested annotation also typechecks | the file's header; `MC-A`, `MC-B` |
| typecheck skeleton `TypedNodeKit.swift` + eight clients, plain import, Swift 6 | five lies rejected with named diagnostics; `liar4` and an overriding `requestLayout` compile; `ProposalElement` must restate `associatedtype LayoutState` | the file's header; `MC-G` |

**Restores.** `NativeOverlayModifier.swift` was restored from a `cp` backup
after the fix trial. `git status --short` then showed only the untracked probe
files, and the scratch test file was deleted before commit.

**Toolchains.** macOS 26.6.2 (25G83); `swiftc` Apple Swift 6.3.3
(swift-6.3.3-RELEASE); `/usr/bin/swift` Apple Swift 6.4
(swiftlang-6.4.0.33.1).

### Lanes

*Each lane appends here: its commits, red runs (quoted lines), mutation runs
with the tests each reddened, the suite/guard/golden counts it re-took, and, for
lanes 2 and 3, the demo captures (`MC-J`): image dimensions, differing-pixel
count and coordinates, and the logged pointer position.*

### For the integration step

Collected here so the merge does not have to re-derive them:

- **`FrameModifier` is deleted by lane 2.** `CLAUDE.md`'s Animation section
  counts registering sites and `pass.fill` sites; record §09's "It is live in
  three places the per-site guards were written to watch" and "Owed before
  this work is cited as done: `FrameModifier` arms" both change.
- **Record §09's hazard 3 (the overlay id collision) is closed by lane 1**
  (`MC-E`), and plan task 3's open-proof bullet "`OverlayModifier` gives its
  primary element and its overlay element the same id, by reading" is
  measured and fixed.
- **`SA-R`'s amended criterion is met by lane 3** (`MC-G`), with three named
  holes. The SA decisions doc is not edited by this track.
- **The guard count moves 45 → 51 by lane 3's design.** Re-count per file.
