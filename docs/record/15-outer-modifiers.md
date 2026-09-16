## Outer modifiers and modifier order (plan task 5) — `feat/outer-modifiers`, from 2026-09-15

The record for plan task 5. Spec
`docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`; rulings
`OM-A`…`OM-AC` in
`docs/superpowers/2026-09-15-outer-modifiers-decisions.md` (next unused
`OM-AD`; the two-letter tails `OM-AA`…`OM-AC` are deliberate). The track runs in
its own worktree,
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

**Display state.** ~~`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` reads
`<false/>` — unlocked, so the implementing lane can take real
`screencapture -R` window captures as well as the offscreen comparison.~~
**Superseded by round 2 (`OM-AC`): the reading is volatile and is not a property
of this machine.** It read `<false/>` in both design sessions and `<true/>` in
the review session. The offscreen comparison is the **primary** evidence; the
real-window capture is conditional on a reading taken **at lane-4 time** and
reported with its timestamp.

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

### Design review round 2, 2026-09-15, at `c4b5853`

Seventeen critic findings against the design commit `981f78b`. Fifteen applied
in full, one applied in part with its second half refuted, one rejected on its
facts and applied on its substance. Ten new rulings, `OM-T`…`OM-AC`; the
disposition table is at the end of the decisions doc. **Still no `Sources/`
change.**

#### Probes extended and re-recorded

Three of the four. Every added arm is additive — no existing arm's expression
changed — and each probe's header carries a `RE-RECORDED` block saying what was
added and why. Both run forms (`/usr/bin/swift` and a compiled `xcrun swiftc`
binary) produced **byte-identical stdout, exit 0, compile stderr 0 bytes, run
stderr 0 bytes** for all three. Every recorded header line was then re-checked
against live stdout for all **four** probes (the unchanged
`swiftui-outer-modifier-order` included): complete, no drift.

| probe | added | what it settled |
|---|---|---|
| `swiftui-border-clip-paint` | sample points `arc(5,5)` and `arc(7,7)`; arm **B3** (border over a filling child); arm **M1** (the MetalUI-equivalent rounded bordered rect) | `OM-V`, `OM-W` |
| `swiftui-component-distribution` | arms **G10–G12** (a content-sized `Text` body); arms **G13–G16** (declaration order of two modifiers) | `OM-E` round-2 block, spec §4.4 |
| `swiftui-content-shape-hit-region` | arm **N2** (`.allowsHitTesting(false)` written **before** the gesture) | `OM-T` |

Verbatim, the new readings:

```
B3 box{fillingChild}.border(blue, 4)    : corner(1,1)=rgb(0.02,0.20,1.00) in(3,3)=rgb(0.02,0.20,1.00) arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
D2 red.border(blue, 4).cornerRadius(12) : corner(1,1)=white in(3,3)=white arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
M1 RoundedRect(12) fill+strokeBorder 4  : corner(1,1)=white in(3,3)=white arc(5,5)=rgb(0.02,0.20,1.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(0.28,0.16,0.83) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)

G10 SoloText()                   : outer 13x16 a (0, 0) 13x16 b none bg none
G11 SoloText().padding(20)       : outer 53x56 a (20, 20) 13x16 b none bg none
G12 Solo().padding(20)           : outer 70x50 a (20, 20) 30x10 b none bg none
G13 Pair().padding(4).frame(w:70): outer 148x18 a (20, 4) 30x10 b (88, 4) 50x10 bg none
G14 Pair().frame(w:70).padding(4): outer 164x18 a (24, 4) 30x10 b (100, 4) 50x10 bg none
G15 Solo().padding(4).frame(w:70): outer 70x18 a (20, 4) 30x10 b none bg none
G16 Solo().frame(w:70).padding(4): outer 78x18 a (24, 4) 30x10 b none bg none

N1 full Color + tap, hit testing off   : centre 0 edge 0
N2 full Color, hit testing off, THEN tap: centre 0 edge 0
```

Reading them:

- **B3** (`OM-V`): SwiftUI's `.border` is an **overlay** — a child filling the
  whole 40x40 does not hide it. MetalUI's single `MUIRect` emitted before the
  children would be hidden by that child, which would have made the **focus
  ring invisible on the exact call it exists for**. The border becomes a second
  emission after `content()`; `OM-O` is superseded.
- **D2 vs M1** (`OM-W`): at `arc(5,5)` SwiftUI reads the **fill** and a single
  rounded rect with a 4pt inset border reads the **border**; `in(6,6)` differs
  too (fill versus the antialiased blend `rgb(0.28,0.16,0.83)` across M1's inner
  edge). SwiftUI clips a *square* border by the radius; a rounded stroke follows
  the arc. **The first draft's five sample points all agreed** — the corner and
  (3,3) outside the arc, (6,6) and the centre deep inside, the edge midpoint
  border in both — so "same as MetalUI's one-emission answer" was unfalsifiable
  rather than true. Taxonomy shape 15, reached through a probe instead of a
  test.
- **G10/G11** (spec §4.4): SwiftUI's content-sized `Text` body measures
  **13x16** — the same 13x16 a MetalUI `Text("Hi")` measures (scratch T1) — and
  `.padding(20)` takes it to **53x56**, the same 53 MetalUI's **element** path
  produces (scratch T2). So SwiftUI and MetalUI's element path agree digit for
  digit and only the **component** path is inert. The first draft's row cited
  G5/G6, which is a fixed 30x10 body at `.padding(8)`: wrong body kind, wrong
  padding, wrong numbers, and it missed that the inertness comes specifically
  from the content-sized-measured-leaf box model.
- **G13–G16** (`OM-E`): declaration order **is** observable on a custom view.
  That is the warrant for `ops` being ordered. It also shows what MetalUI cannot
  match: SwiftUI's `.frame` wraps and keeps the member 30 wide, `OM-F`'s amend
  overwrites it, so lane 4 test 4 pins MetalUI's own numbers and names `OM-F`.
- **N1 == N2** (`OM-T`): `.allowsHitTesting(false)` kills a gesture written
  **after** it as well as before it, so the order is not observable in SwiftUI —
  and MetalUI's one-`Handlers` storage **agrees** here. That removes a row that
  would otherwise have joined `OM-H`'s not-expressible list. N1 also refutes the
  first draft's mechanism outright: it registered the receiver's own handlers
  *outside* the scope it opened.

#### Other measurements taken this round

| run | result | finding |
|---|---|---|
| `grep -oE "^\| [0-9]+ \|" docs/record/04-divergences.md` | 20 … **34**, under "2026-09-15: divergences 20–34 (tasks 3, 9 and 12, integrated)". **Next free 35** | 5 |
| `grep -n "Component" Sources/MetalUIDemo/main.swift` | `918: private struct PreviewToggle: Component`, used bare at line 1017 inside `nativeLayoutPreviewContent()` | 6 |
| read `LayoutTree.newNode(style:children:)` (`LayoutTree.swift:130-136`) | it **already traps** on a native child, message naming `SA-G`, and the trap is pinned by an existing exit test at `Tests/MetalUILayoutTests/NativeBoundaryTrapTests.swift:42` | 6 (second half **refuted**) |
| read `Frame.registerHandlers` (`Frame.swift:759-880`) | the hitbox insert alone is gated on `hitTestingDisabledDepth == 0`; focus registration, the `$focus` write, `focusedElementProducedThisFrame`, the declared `AXNode` and the accessibility record all sit **above** that gate | 1 |
| read `Text.prepaint` (`Text.swift:311-313`) | calls the five-argument overload with `accessibleText: string.isEmpty ? nil : string, synthesizesAccessibility: true` | 7 |
| read `Frame.pushClip` (`Frame.swift:393-400`) | intersects `bounds` **untranslated**; composes the offset for descendants only. Record §04 lines 560–561: the fix's added term is a no-op wherever `activeOffset == 0` | 2 |
| read `PaintPass.opacity` (`Passes.swift:639`) | `precondition((0...1).contains(value))` — so an exit test using a **negative** opacity cannot see the modifier's own precondition go missing | 10 |
| read `Decoration`'s explicit public memberwise `init` (`Box.swift:220`) | present, and the first draft's §5.1 did not extend it, so the five new fields would have been unreachable through `Box(decoration:)` | 17c |
| `grep -n "cases.count" Tests/MetalUITests/ModifierTests.swift` | `289: #expect(cases.count == 38)` — the tripwire three lanes and another track will all touch | 15c |
| `ioreg -n Root -d1 -a \| grep -A1 IOConsoleLocked` | `<false/>` — **not** the `<true/>` the critic read. Both are true of their moment; the reading is volatile | 14 |

`git status --short` was clean of `Sources/` and `Tests/` changes throughout;
the round's diff is the three probes and the three documents.

#### What the round changed about how the lanes are built

- `registerAndScope` opens the disabled scope **before** the receiver's own
  registration and forwards `accessibleText`/`synthesizesAccessibility`
  (`OM-T`, `OM-X`).
- `paintDecoration` emits the background before `content()` and the border
  **after** it (`OM-V`); `OM-O`'s single-emission rule is superseded.
- Lane 2 takes divergence 15's one-line `pushClip` fix and **inverts**
  `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` (`OM-U`).
- `BorderStyle.widths` and `Decoration.opacity` become `public private(set)`
  with validating setters, and two more exit tests plus a plain-import typecheck
  guard pin the narrowing (`OM-Y`); test 14's arm must use a value **above 1**.
- The matrix test measures a five-tuple with per-kind witnesses (`OM-X`).
- Lane 3 gains `aContentShapeWithoutAClickHandlerRegistersNothing` (`OM-AB`);
  lane 2 gains `aDeferredPortalInsideAFadedSubtreeIsStillFaded` (`OM-AA` b).
- `MC-G` hole 5 is claimed for this task and closed in lane 4 by an exit test
  over an existing trap (`OM-Z`).
- `hoverBorder`/`focusBorder` gain the `widths:` form; the modifier count in
  §5.1 is **eleven**, and `ModifierTests`' tripwire moves 38 → **47** for this
  track (38 − 2 + 8 + 3).

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

- **Seven** divergence rows with no numbers yet: the default hit region
  (`OM-I`), a padded click target (`OM-K` — and its order-sensitivity, which
  SwiftUI's P1/P2 do not have), `.opacity` reaching a later background (`OM-N`),
  `.cornerRadius` not clipping (`OM-G`), a `Component`'s `width`/`height`
  overwriting (`OM-F`), **`.border.cornerRadius` following the arc where
  SwiftUI's clipped square border does not (`OM-W`, round 2)**, and **`.opacity`
  answering differently on the legacy and proposal paths (`OM-AA` a, round 2)**.
  **The highest number allocated in `docs/record/04-divergences.md` today is 34,
  not 29** (round 2, critic finding 5): `grep -oE "^\| [0-9]+ \|"` runs 20…34
  under "2026-09-15: divergences 20–34 (tasks 3, 9 and 12, integrated)".
  **Next free: 35.** The wrong figure appeared in three places and is corrected
  in all three.
- **Divergence 15 is RETIRED** (`OM-U`, round 2): lane 2 takes its one-line
  `pushClip` fix, because `.clipped()` changes the defect's reach from "a
  `ScrollView` inside a scrolled `ScrollView`" to "any element inside one".
  `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` is inverted in the
  same commit.
- `CLAUDE.md`'s declared-but-inert table loses its `borderWidth(_:)` row
  (`OM-M`) and its `MUIRect.borderColor`/`borderWidths` row becomes "reachable
  through `Decoration.border`".
- `CLAUDE.md`'s `Deferred` sentence — "hoists to the root layer and resets clip
  and scroll offset together (AP-I)" — gains "and **not** opacity, which a faded
  subtree's portal inherits" (`OM-AA` b), which only becomes reachable once
  `.opacity` exists on the legacy path.
- `MC-G` hole 5's owner: the modifier-composition decisions doc says task 5, and
  task 5 closes it (`OM-Z`). No reassignment for integration to reconcile.
- `CLAUDE.md`'s "three `pass.fill` sites" and "four `pass.fill` sites"
  sentences, the animation section's registering-point counts, and
  `ModifierTests`' "40 public funcs in `Box.swift`" reconciliation all move.
- The focus-ring look is a **human** check: nothing in the suite can see whether
  a ring reads as a focus affordance. It belongs in CLAUDE.md's human
  verification table, open, with the demo key that shows it (if lane 4 adds
  one).
