## Outer modifiers and modifier order (plan task 5) — `feat/outer-modifiers`, from 2026-09-15

The record for plan task 5. Spec
`docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`; rulings
`OM-A`…`OM-S` in
`docs/superpowers/2026-09-15-outer-modifiers-decisions.md` (next unused
`OM-T`). The track runs in its own worktree,
`/Users/maxburger/Developer/MetalUI-outer-modifiers`, beside the task-4
frame/sizing track, and is merged by an integration step that owns `CLAUDE.md`,
`AGENTS.md`, `README.md`, the plan, `docs/record/README.md`, the existing record
files and the other track's decisions doc. **Nothing in this file has been
copied into those.**

Branch point `c4b5853` (`feat/review-fixes`, after the three-track integration
of tasks 3, 9 and 12).

---

### Design session, 2026-09-15, at `c4b5853`

**No `Sources/` change was committed.** The commit carries four probes, the
spec, the decisions doc and this file.

**Toolchains.** macOS 26.6.2 (25G83). `/usr/bin/swift` and `xcrun swiftc` both
report Apple Swift 6.4 (swiftlang-6.4.0.33.1, clang-2100.3.33.1), target
arm64-apple-macosx26.0. (The modifier-composition track's correction holds:
`xcrun` is 6.4 here, and only a PATH `swiftc` from swiftly is 6.3.3. This
session used `/usr/bin/swift` and `xcrun swiftc` only.)

**Display state.** `ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` reads
`<false/>` — unlocked, so the implementing lane can take real
`screencapture -R` window captures as well as the offscreen comparison.

**Baseline at `c4b5853`, re-taken in this worktree** (`swift build
--build-system native`, then `swift test --build-system native --no-parallel`):

```
Test run with 1226 tests in 1 suite passed after 30.231 seconds.
```

0 `error:`, 0 `warning:`. `find Tests -name "*.json" | wc -l` = 97. Guards, by
`grep -c canTypecheck` per file: PhaseSeparationTests 19, ErasureCompileGuards
10, ElementGroupTrapTests 5, UnitSafetyTests 3 (one a comment),
AXNodeTests 3, ModifiedElementCompileGuards 2, ProposalLayoutCompileGuards 6,
ProposalNodeIDCompileGuards 6, EnvironmentCompileGuards 8 — **62 hits, 61
guards**. All three agree with record §13.

#### What was run

| run | result | where recorded |
|---|---|---|
| SwiftUI probe `docs/probes/swiftui-outer-modifier-order.swift`, `/usr/bin/swift` and compiled `xcrun swiftc` | byte-identical stdout, exit 0, compiled stderr 0 bytes. 22 arms | the probe's header; `OM-A`, `OM-C`, `OM-E` |
| SwiftUI probe `docs/probes/swiftui-border-clip-paint.swift`, both forms | byte-identical, exit 0, stderr 0 bytes. 17 arms | the probe's header; `OM-B`, `OM-G`, `OM-H`, `OM-N` |
| SwiftUI probe `docs/probes/swiftui-content-shape-hit-region.swift`, both forms | byte-identical, exit 0. 11 arms, each a pair of real clicks into a real `NSWindow` | the probe's header; `OM-I`, `OM-J`, `OM-K` |
| SwiftUI probe `docs/probes/swiftui-component-distribution.swift`, both forms | byte-identical, exit 0, stderr 0 bytes. 11 arms | the probe's header; `OM-D`, `OM-E`, `OM-F` |
| scratch test `zzScratchBackgroundOrder` (uncommitted, `--filter`, deleted) | today's legacy chain, emitted rects | below; `OM-C`, `OM-E` |
| scratch test `zzScratchPaddingHitRegion` (deleted) | `.padding(80).onClick`: centre 1, **edge 1** | below; `OM-K` |
| scratch test `zzScratchComponentPadding` (deleted) | today's `Component` distribution, six arms | below; `OM-D`, `OM-F` |
| scratch test `zzScratchTextPadding` (deleted) | legacy `.padding` around a `Text` leaf, four arms | below; `OM-C` |
| `grep -rn borderWidth Sources/` | only its own two declarations in `Box.swift` and the proposal `.border`'s `pass.fill` line; **no production caller** | `OM-M` |
| `grep -rn ": ProposalElement" Sources/MetalUI/*.swift` and a cross-grep for a type naming both protocols | **no type conforms to both** `StyledElement` and `ProposalElementGroup` | the spec's risk table |

All four scratch tests were deleted before the commit; `git status --short`
then listed only the four untracked probe files.

#### Scratch readings, verbatim

Rects are printed as `[x y WxH r<cornerRadius>]`, in the order `Scene.rects`
holds them. The fake window is 200 or 300 points square; the marker is a 1x1
`Box` declared after the subject in a `Row` with `.alignItems(.flexStart)`.

```
SCRATCH A1 .padding(8).background: ["[0.0 0.0 36.0x200.0 r0.0]", "[8.0 8.0 20.0x20.0 r0.0]"]
SCRATCH A2 .background.padding(8): ["[8.0 8.0 20.0x20.0 r0.0]"]
SCRATCH A3 .padding(4).padding(4): ["[8.0 8.0 20.0x20.0 r0.0]"]
SCRATCH P1 padding then onClick: centre 1 edge 1
SCRATCH C1 Solo() bare       : ["[13.0 0.0 1.0x1.0 r0.0]"]
SCRATCH C2 Solo().padding(20): ["[13.0 0.0 1.0x1.0 r0.0]"]
SCRATCH C3 SoloBox() bare    : ["[0.0 0.0 30.0x10.0 r0.0]", "[30.0 0.0 1.0x1.0 r0.0]"]
SCRATCH C4 SoloBox().pad(20) : ["[0.0 0.0 40.0x40.0 r0.0]", "[40.0 0.0 1.0x1.0 r0.0]"]
SCRATCH C5 SoloBox().p4.p4   : ["[0.0 0.0 30.0x10.0 r0.0]", "[30.0 0.0 1.0x1.0 r0.0]"]
SCRATCH C6 SoloBox().width70 : ["[0.0 0.0 70.0x10.0 r0.0]", "[70.0 0.0 1.0x1.0 r0.0]"]
SCRATCH T1 Text bare        : ["[13.0 0.0 1.0x1.0 r0.0]"]
SCRATCH T2 Text.padding(20) : ["[53.0 0.0 1.0x1.0 r0.0]"]
SCRATCH T3 Text.bg.padding  : ["[20.0 20.0 13.0x16.0 r0.0]", "[53.0 0.0 1.0x1.0 r0.0]"]
SCRATCH T4 Text.padding.bg  : ["[0.0 0.0 53.0x56.0 r0.0]", "[53.0 0.0 1.0x1.0 r0.0]"]
```

Reading them:

- **A1's 200-tall fill is the enclosing `Box` stretching its child** (EP-8), not
  the padding layer sizing itself; the width, 36 = 20 + 2·8, is the figure the
  ruling uses. Every fixture the implementing lanes write must declare
  `.alignItems(.flexStart)` on the enclosing container, as the C and T arms do,
  or the cross axis is the container's answer rather than the modifier's.
- **A1 vs A2** (`OM-C`): the background covers the padded box when written after
  the padding and the inner box when written before it, matching SwiftUI's A1/A2
  (`(0,0) 36x36` vs `(8,8) 20x20`).
- **A3** (`OM-E`): `.background.padding(4).padding(4)` leaves the leaf at (8, 8)
  — the two paddings accumulate on the `Element` path.
- **T1–T4** (`OM-C`): a `Text` leaf is 13x16; `.padding(20)` moves the marker
  13 → 53, so `.padding` wraps a content-sized leaf correctly on the `Element`
  path. `.background` before and after the padding fills `(20,20) 13x16` and
  `(0,0) 53x56` respectively.
- **P1** (`OM-K`): a padded click target is hittable **in its padding**, where
  SwiftUI reads edge 0 (probe P1/P2) unless a background (P4) or a content shape
  (P3) is declared first.
- **C1/C2** (`OM-D`): `.padding(20)` on a component whose body is one `Text` is
  **completely inert** — the marker does not move. SwiftUI pads (G5 → G6,
  30x10 → 46x26).
- **C3/C4** (`OM-D`): on a component whose body is one 30x10 `Box`,
  `.padding(20)` produces a **40x40** node — CSS border-box padding absorbing the
  declared size — where SwiftUI's per-member wrap gives 70x50.
- **C5** (`OM-E`): `.padding(4).padding(4)` leaves the node at 30x10; the second
  call replaced the first and 4 was then absorbed. SwiftUI's G4 equals its G2.
- **C6** (`OM-F`): `.width(70)` **overwrites** the member's own 30. SwiftUI's
  G7/G8 wrap and centre, leaving the member at 30.

#### Probe outputs

Each probe's own header carries its full recorded stdout, its positive controls
and its "WHAT IT SHOWS" reading. The four one-line summaries:

- `swiftui-outer-modifier-order`: eight modifiers are layout-neutral where
  `.padding(8)` moves a 20x20 leaf to 36x36; `.background` covers the box as it
  stood where it was written; `.padding(4).padding(4)` == `.padding(8)`.
- `swiftui-border-clip-paint`: `.border` draws inside the box; a corner radius
  rounds and **clips** what was declared before it and leaves a later background
  square; a border does not inherit a radius applied before it; opacity
  multiplies and does not reach a background written after it.
- `swiftui-content-shape-hit-region`: SwiftUI's default hit region is
  content-derived (a stack's empty middle reads 0/0);
  `.contentShape(Rectangle())` makes it the frame; `.contentShape(Rectangle()
  .inset(by: 60))` shrinks it to 1/0; padding is not hittable unless a
  background or a content shape is declared before the gesture.
- `swiftui-component-distribution`: a modifier on a custom view with a
  multi-view body is applied to **each** member (120x26, = `Group`'s); padding
  accumulates; a single-leaf body pads; `.frame(width:)` wraps each member and
  keeps the member's own size; `.background` produces one background per member.

#### Harness notes, so the shapes are reproducible

- `NSBitmapImageRep`'s `colorAt(x:y:)` is in **pixels**, not points: the probe
  scales its sample points by `pixelsWide / side`.
- Neither `Color.red` nor an sRGB-authored `Color(.sRGB, …)` round-trips through
  `cacheDisplay` on this machine — compositing happens in the display's own
  space, and the fill samples as rgb(1.00,0.15,0.00), the border as
  rgb(0.02,0.20,1.00). The classifier prints the triple when it is not within
  0.02 of a named colour, which is why the recorded block is numeric. The three
  values are mutually unconfusable, which is all the arms need. An earlier
  threshold of 0.15 classified a double-faded fill as "white" and was tightened
  after that reading was spotted.
- The hit-region probe reuses the environment track's harness
  (`swiftui-disabled-interaction.swift`): `FirstMouseHost`, a down / 50 ms spin
  / up through `NSWindow.sendEvent`, and a spin after. Its history section
  explains why any other order measures nothing. Each arm here builds **two**
  windows, one per click point, so one click cannot mask the other.
- `ElementBuilder` closures passed to a test helper must be
  `@escaping @MainActor` for `makeFakeWindow`'s `content` parameter; the scratch
  helpers wrap the subject in a `Row { subject; marker }`.

---

### Lanes

*Each lane appends here: its commits, the red run (quoted summary and issue
lines), the mutation table with the tests each mutation reddened, the
suite/guard/golden counts it re-took, and — for lanes 2 and 4 — the demo and
preview comparisons against `c4b5853` (image dimensions, differing-pixel count
and coordinates).*

#### Lane 1 — the audit, pinned as it stands

*Not started.*

#### Lane 2 — paint-only decoration: border, focus ring, opacity, clip

*Not started.*

#### Lane 3 — hit testing: `allowsHitTesting` and `contentShape`

*Not started.*

#### Lane 4 — `Component` padding wraps, and the verification

*Not started.*

---

### Carried into the integration step

- Five divergence rows with no numbers yet: the default hit region (`OM-I`), a
  padded click target (`OM-K`), `.opacity` reaching a later background
  (`OM-N`), `.cornerRadius` not clipping (`OM-G`), and a `Component`'s
  `width`/`height` overwriting (`OM-F`). The highest number allocated in
  `docs/record/04-divergences.md` today is **29**.
- `CLAUDE.md`'s declared-but-inert table loses its `borderWidth(_:)` row
  (`OM-M`) and its `MUIRect.borderColor`/`borderWidths` row becomes "reachable
  through `Decoration.border`".
- `CLAUDE.md`'s "three `pass.fill` sites" and "four `pass.fill` sites"
  sentences, the animation section's registering-point counts, and
  `ModifierTests`' "40 public funcs in `Box.swift`" reconciliation all move.
- The focus-ring look is a **human** check: nothing in the suite can see whether
  a ring reads as a focus affordance. It belongs in CLAUDE.md's human
  verification table, open, with the demo key that shows it (if lane 4 adds
  one).
