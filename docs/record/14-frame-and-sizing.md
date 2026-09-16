## Frame and sizing (plan task 4) — `feat/frame-sizing`, from 2026-09-15

The record for plan task 4. Spec
`docs/superpowers/specs/2026-09-15-frame-sizing-design.md`; rulings `FR-A`…
`FR-K` in `docs/superpowers/2026-09-15-frame-sizing-decisions.md` (next unused
`FR-L`); probe `docs/probes/swiftui-frame-semantics.swift`. The track runs in
its own worktree, `/Users/maxburger/Developer/MetalUI-frame-sizing`, beside the
paint-modifier track, and is merged by an integration step that owns
`CLAUDE.md`, the plan, `docs/record/README.md` and the other track's files.
**Nothing in this file has been copied into those yet.**

### Design session, 2026-09-15, at `c4b5853`

No source file changed. Baseline, re-taken in this worktree with
`swift test --build-system native --no-parallel`: **1226 tests passed**, 0
`error:`, 0 `warning:`; `find Tests -name '*.json' | wc -l` = **97**;
`grep -c canTypecheck` per file sums to 62 with one comment hit in
`UnitSafetyTests.swift`, so **61** guards.

Toolchains: macOS 26.6.2 (25G83); `/usr/bin/swift` and `xcrun swiftc` report
Apple Swift 6.4 (swiftlang-6.4.0.33.1); PATH `swiftc` (swiftly) reports Apple
Swift 6.3.3.

| run | result | where recorded |
|---|---|---|
| SwiftUI probe `swiftui-frame-semantics.swift`, 54 arms, `/usr/bin/swift <file>` and compiled `xcrun swiftc` + `OS_ACTIVITY_DT_MODE=1` | `diff` of the two forms EMPTY, 295 lines, exit 0 both ways, no SwiftUI diagnostic in either (every input is one SwiftUI accepts) | the probe's header; `FR-A`, `FR-B`, `FR-C`, `FR-D`, `FR-E`, `FR-J` |
| the probe's first pass, which placed the view under test at `bounds.origin` | arm D12 (`frame(maxWidth: .infinity)` at an infinite proposal) **crashed SwiftUI**: `SwiftUICore/Layout.swift:1535: Fatal error: view origin is invalid: (nan, 190.0), UnitPoint(x: 0.0, y: 0.0), (20.0, 20.0)`. Placing at `.zero` instead, the same arm answers `inf x 20` and places the child at `x = inf` | the probe's header (arm D12's comment); `FR-B` |
| trial conversion: `StyledElement.width/height` → `frame(width:)`/`frame(height:)`, `swift build --build-system native` | fails to compile. `Sources/MetalUIDemo/main.swift` (the stored `typealias Chrome` and `button(_:_:) -> Box<Text>`); then, after patching those, `EnvironmentTests` (`surfaceBox -> Box<EmptyGroup>`, `typealias Leaf`), `ModifierTests` (its `ModifierCase` table, which asserts each modifier returns `Self` and writes a named `Style` field), `AccessibilityTreeTests`, `AccessibilityEndToEndTests`, `AnimationTests`, `ProposalNodeIDTests` | `FR-F` |
| `grep -rno` | `.width(` 348, `.height(` 338 across `Sources/` and `Tests/` (one of each is the percentage overload), over 378 distinct lines; `min*`/`max*` 10 in `Tests/` and **one live** in `Sources/` (`main.swift:881`), the other four `Sources/` matches being inside comments | `FR-F`, `FR-G`, `FR-I` |
| scratch `Tests/MetalUITests/ZZScratchFrameTests.swift`, 13 measurements, `swift test --build-system native --no-parallel --filter zzScratch`, **deleted before commit** (`git status --short` then showed only the probe) | below | `FR-C`…`FR-H` |

**Restores.** The trial conversion was reverted from `cp` backups of
`Box.swift`, `main.swift` and `EnvironmentTests.swift`; `git status --short`
afterwards showed only the untracked probe. The scratch test file was deleted.

### What the legacy CSS path actually does — the scratch measurements

Every figure below came from `Frame.render` or a direct `requestLayout` +
`computeRootLayout`, in a 300×200 root unless stated. They are quoted here
because the file that produced them is gone. `Mark` is a childless
`StyledElement` probe recording the bounds its `prepaint` receives.

| arm | shape | measured | SwiftUI (probe arm) |
|---|---|---|---|
| L1 | `Text(…).frame(width: 60)` **as the root** | 60×200, and identical for `.width(60)` and for a `Box` wrapper — the root's auto height takes the offered space (divergence 4), so the root contaminates this measurement | — (superseded by L11) |
| L2 | `Mark.frame(width: 60, height: 40)` | root 60×40; the **Mark is 0×0** at (30, 20) | matches: a contentless child answers 0 and is centred (A-control shape) |
| L3 | `Mark.width(200).height(160).frame(width: 60, height: 40)` | the Mark is **(0, −60, 60, 160)** — width shrunk to the frame, height overflowing | A5: the child keeps 200×160 at (−70, −60) |
| L4 | `Box { Mark }.onClick {}.frame(width: 60, height: 40)` | the hitbox is **0×0 at (30, 20)** | the same in SwiftUI: a handler declared before a frame sits on the content |
| L6 | nine `justifyContent` × `alignItems` combinations on a 60×40 layer over a 20×20 child | `(0,0) (0,10) (0,20) (20,0) (20,10) (20,20) (40,0) (40,10) (40,20)` | B1–B8 exactly |
| L9 | `Row { Mark.frame(200×20); Mark.frame(200×20) }` in 300pt | marks at x = **75 and 225** — each layer shrank to 150 | a fixed frame never shrinks |
| L10 | in a 300pt `Row`, width read from a 5pt sibling's x | `maxWidth 80` over a 20pt child → **20**; `minWidth 40` → **40**; `maxWidth 80` over a 200pt child → **80**; `.frame(width: 80)` → 80 with the child centred at 30 | D4 → 80 (**diverges**); D7 → 40; D14 → 80; A1 |
| L11 | `Column { Text("alpha bravo charlie delta").font(size: 12).frame(width: 60); marker }` | the marker sits at y = **60** — four 15pt lines — against y = **15** unframed; `.width(60)` reads 60 too. In a `Row` the framed and styled advances are 60 against the bare text's **139** | F1 60×60, F control 139×15 — the same numbers |
| L12 | `ScrollView { List(40 rows).frame(width: 200) }` | **40** painted row rects, the same as unframed and as `.width(200)` | — |
| L13 | `Row` of two frames whose children declare 200pt | no shrink either way; the automatic minimum floors them | — |
| L14 | L9 plus `.flexShrink(0)` on each layer | marks at **100 and 300** — 200 each, no shrink | matches SwiftUI |
| M1 | `Mark(20).frame(width: 100).frame(width: 50)` | root **50**, leaf at x = **15**. Reversed: root **100**, leaf at x = **40**. Unchanged without `.flexShrink(0)` — the inner frame does not shrink inside another frame | E1 (50, leaf 15) and E2 (100, leaf 40) exactly |
| M2 | greediness in a 300pt `Row` | `flexGrow(1)` fills to 295; `flexGrow(1) + maxWidth(80)` stops at **80**; plain reads 20. In a `Column`, `alignSelf(.stretch)` puts a child at x = 0 where an unstretched box's child is centred at 140 | D4's 80 — reachable, but only on the axis that happens to be main |
| M4 | `width(percent: 100)` | in a `Row` the sibling moves to x = **300** (fills); capped by `maxWidth(80)` it reads 80. **In a `Column` the child lands at x ≈ −14850**, implying a box about 30000pt wide. Mechanism not investigated | — |

**Three claims the plan made about the reverted 2026-09-12 conversion, tested.**
The plan says the trial "broke list virtualization, hit testing, and text
measurement", and record §09 notes no measurement of it exists.

- **Text measurement: refuted.** L11 — a frame layer's width reaches a measured
  leaf and re-wraps it, to SwiftUI's own numbers.
- **List virtualization: refuted.** L12 — the framed list paints the same rows.
- **Hit testing: confirmed, and it is not a defect.** L4 — a handler declared
  before the frame stays on the content, which is what SwiftUI does with
  `.background` before `.frame`. What actually blocks the conversion is the
  type-level blast radius and the 0-warning gate (`FR-F`).

### Lanes

*Each lane appends here: its commits, red runs (quoted `Test run with N tests`
lines and issue text), mutation runs with the tests each reddened, the
suite/guard/golden counts it re-took, and lane 4's pixel comparison — image
dimensions, differing-pixel counts and the control counts that must be
non-zero.*

(Not started. The design is committed; no source file has changed.)

### Open at the end of the design session

- Two of `MC-Q` finding 7's four handed-over shapes are **not** covered by this
  design: a **nil axis** in a modifier-order chain, and a **stretching `Box`
  parent** (EP-8). The shrinking row is `FR-C`'s `flexShrink = 0` and the
  smaller frame is spec test 2.5.
- The `Column` percentage defect (M4, ≈30000pt) is pinned as measured by spec
  test 3.1 and its mechanism is not investigated.
- `FR-D`'s `flexBasis`-as-ideal idea is unmeasured.
- The release-window captures stay owed (`MC-J`, `EV-P`); lane 4 checks
  `IOConsoleLocked` and records the refusal if the session is locked.
