## Outer modifiers and modifier order (plan task 5) — `feat/outer-modifiers`, from 2026-09-15

The record for plan task 5. Spec
`docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`; rulings
`OM-A`…`OM-AM` in
`docs/superpowers/2026-09-15-outer-modifiers-decisions.md` (next unused
`OM-AN`; the two-letter tails `OM-AA`…`OM-AM` are deliberate). The track runs in
its own worktree,
`/Users/maxburger/Developer/MetalUI-outer-modifiers`, beside the task-4
frame/sizing track, and is merged by an integration step that owns `CLAUDE.md`,
`AGENTS.md`, `README.md`, the plan, `docs/record/README.md`, the existing record
files and the other track's decisions doc. **Nothing in this file has been
copied into those.**

Branch point `c4b5853` (`feat/review-fixes`, after the three-track integration
of tasks 3, 9 and 12).

**Status, 2026-09-16: all four lanes built and verified; the track is
complete at `2fb0800` plus this record's final commit.** Twenty commits
`981f78b..2fb0800`, three of them design, the rest lanes 1–4 in order — each
lane a red-first commit, the lane, and its record — then two review rounds
(lane 2's `09a7f7c`, lane 3's `641c91c`). The lane-by-lane entries below were
written by the lanes as they ran; the **"Verifier's verdict"** subsection
under each lane and the two closing sections (**"Track totals"** and **"For
the integrator"**) were written last, by the record pass, after the
continuation that finished lanes 3 and 4. The verdicts for lanes 1 and 2 were
lost with the run that was cut off at 21:46 PDT on 2026-09-15, and their
subsections say what is reconstructed and from where; the verdicts for lanes 3
and 4 are quoted from the verifiers' reports.

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

**Commits.** `a4c5dc6` (the five tests) and `c07f141` (the mutation round's two
corrections). No `Sources/` change in either — every `Sources/` edit below was a
mutation, applied, run, and reverted with `git checkout`; `git status --short`
was clean of `Sources/` after each.

One new file, `Tests/MetalUITests/OuterModifierMatrixTests.swift`. Nothing else
in `Tests/` or `Sources/` is touched, so `ModifierTests.swift`'s `cases.count`
tripwire is still **38** and this track's pre-agreed 47 is untouched.

##### Counts, re-taken at `c07f141`

| reading | value | against the baseline |
|---|---|---|
| `swift test --build-system native --no-parallel` | `Test run with 1231 tests in 1 suite passed after 30.068 seconds.` | **+5** on `c4b5853`'s 1226 |
| `error:` / `warning:` in the run | **0** / **0** | unchanged |
| `find Tests -name "*.json" \| wc -l` | **97** | unchanged; `git diff --stat c4b5853 -- Tests` lists no `.json` |
| guards, `grep -c canTypecheck` per file | 19 / 10 / 5 / 3 / 3 / 2 / 6 / 6 / 8 = **62 hits, 61 guards** | unchanged — this lane adds no guard |

##### The first run

Four of the five were green on arrival and one was red. The red line, verbatim:

```
􀢄  Test aBareCornerRadiusDoesNotClipTheChildren() recorded an issue at
   OuterModifierMatrixTests.swift:853:5: Expectation failed:
   (child.bounds.size.width == 60 → false) && (child.bounds.size.height == 60 → <not evaluated>)
􀄵  the child overflows its rounded parent at full size; got [0.0 0.0 40.0x60.0] …
```

**The 60x60 child came back 40x60**: flex-shrunk to its 40pt parent, so it never
overflowed and "unclipped" and "clipped exactly to the box" were the same
picture. `.flexShrink(0)` on the child, and on the `ScrollView` control's child,
is the fix.

**The matrix test passed on its first run**, with all sixteen rows classified as
§3.1 claims them. That is a weaker result than a red one and it is recorded as
such: what makes the table an instrument rather than a transcript is the
mutation round below, not the run above.

##### Mutations — thirteen, and two of them found the tests

Each applied singly, run against the five tests under
`swift test --build-system native --no-parallel --filter`, then reverted.

| # | mutation | site | reddened |
|---|---|---|---|
| M1 | transpose two rows' claimed kinds: `padding` → `paintOnly`, `background` → `wraps` | the table | matrix, **6 issues** — `nodeDelta == 0`, `nodeDelta > 0`, `outerSizeDelta > 0`, `rectsMoved`, `!rectsMoved`, and the paint-only layout clause |
| M2 | the `borderWidth on a sized box` row's declared arm loses the modifier (both tuple and storage) | the table | matrix, 1 issue, at the **BROKEN INSTRUMENT `#require`** — before any kind is derived, exactly as `OM-X` requires |
| M3 | `_wrap` assigns `outermost` without appending | `ModifiedElement.swift` | `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, at its **control**: `twice.outer` 28 == `single.outer` 28 |
| M4 | `ModifiedElement.paint` fills the outermost decoration at `pass.bounds(of: layout.inner[0].node)` | `ModifiedElement.swift` | **nothing, the first time.** See "What the mutations found" |
| M5 | `prepaintLayerBody` recurses with the outer `bounds` instead of `pass.bounds(of: next.node)` | `ModifiedElement.swift` | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`, `middleLayerEdge` 1 ≠ 0 — after M4's arm was added |
| M6 | `Frame.registerHandlers` inserts a hitbox for `isFocusable` too | `Frame.swift:863` | matrix, the `focusable()` row's **prepaint-only negative** (`!hitRegionsMoved`) |
| M7 | `borderWidth(_ points:)` also writes `decoration.cornerRadius` | `Box.swift` | matrix, the `borderWidth on a sized box` row's **paint negative** (`!rectsMoved`) |
| M8 | `Box.paint` wraps its children in `pass.clipped(to: bounds, cornerRadii: Corners(all: decoration.cornerRadius))` | `Box.swift` | `aBareCornerRadiusDoesNotClipTheChildren`, 2 issues (the mask and its radii) |
| M9 | `StyledComponent.requestGroupLayout` amends `nodes.prefix(1)` | `Component.swift` | **nothing, the first time.** See below |
| M9b | the same, after the witness moved to sizes | `Component.swift` | matrix, **both** `Component` rows, on member 1's unchanged `50.0x20.0` |
| M10 | `padding(_ edges:)` wraps a layer carrying no padding | `Box.swift` | 4 issues across 4 tests: the matrix's `outerSizeDelta > 0`, test 2's order `#require`, test 3's control, test 4's set-up |
| M11 | `Box.paint` emits no background at all | `Box.swift` | 4 issues, but all of them **set-up `#require`s** — it kills the 1x1 marker the instrument measures with, so it is not a discriminating mutation and is recorded as one that is not |
| M11b | `animatedBackground` drops the `focusBackground ?? hoverBackground ??` chain | `AnimatedColor.swift` | matrix, the **hover and focus rows'** paint-only witness (`rectsMoved`), both |
| M12 | `id(_:)` writes no `elementID` | `Box.swift` | matrix, the `id(_:)` row at the **BROKEN INSTRUMENT `#require`** — a modifier that stops writing anything fails as a broken fixture rather than being reclassified as inert |

##### What the mutations found — `OM-AD`

**M9: the `distributes` witness was reading a member's POSITION.** `OM-X`'s
witness was "the delta appears twice, once per member". A component's top-level
nodes sit in one flex line, so growing member 0 pushes member 1 sideways: member
1's rect string moved, the per-member check passed, and an amend that reached
only the first member reddened nothing at all. `Observation` gains `rectSizes`
and the witness reads that instead. A member's **size** is what the modifier did
to it; its **position** is what its siblings did to it.

**M4 and M5: two order tests had no two-layer chain to bite.** Every fixture in
`aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten` and
`aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` was ONE
`ModifierLayer` with `inner` empty — `.padding(8).background`,
`.background.padding(8)`, `.padding(80).onClick`, `.onClick.padding(80)` — so
`ModifiedElement.paint`'s loop over the inner layers and `prepaintLayerBody`'s
recursion never ran. The mutation the spec's own lane-1 table names for test 2,
by its source line, reddened nothing. Three probe-backed arms were added:

- `.padding(4).padding(4).background(.accent)` → the outermost layer is filled,
  `(0,0) 36x36` — SwiftUI A1 reached through E1;
- `.padding(8).background(.accent).padding(4)` → probe arm **A3** exactly: outer
  44x44, the inner layer's fill at `(4,4) 36x36`;
- `.padding(40).onClick.padding(40)` → the handler is on the inner layer, whose
  box is 100x100 at `(40, 40)`, so `(50, 50)` hits and `(5, 5)` does not.

Both mutations redden after that. Taxonomy shape 2 (fixtures too shallow) and,
for M9, shape 12 read sideways: the witness was reading a side effect the code
under test produced and calling it the effect.

##### What the audit itself established

The sixteen rows and their measured readings. Deltas are `declared − bare`;
`rects` and `hit regions` are "identical" or "moved".

| row | path | kinds | node | outer | rects | hit |
|---|---|---|---|---|---|---|
| `padding(_:)` | Element | wraps | +1 | +16 | identical | identical |
| `frame(width:height:)` | Element | wraps | +1 | +40 | identical | identical |
| `width(_:)` | Element | self | 0 | +40 | identical | identical |
| `margin(_:)` | Element | self | 0 | +20 | identical | identical |
| `hidden()` | Element | self | 0 | **−20** | identical | identical |
| `id(_:)` | Element | self | 0 | 0 | identical | identical |
| `focusable()` | Element | self | 0 | 0 | identical | identical |
| `borderWidth(_:)`, sized box | Element | self | 0 | **0** | **identical** | identical |
| `borderWidth(_:)`, content-sized box | Element | self | 0 | **+8** | identical | identical |
| `background(_:)` | Element | self + paint-only | 0 | 0 | moved | identical |
| `cornerRadius(_:)` | Element | self + paint-only | 0 | 0 | moved | identical |
| `hoverBackground(_:)`, hovered | Element | self + paint-only | 0 | 0 | moved | identical |
| `focusBackground(_:)`, focused | Element | self + paint-only | 0 | 0 | moved | identical |
| `onClick(_:)` | Element | self + prepaint-only | 0 | 0 | identical | **moved**, 0 → 1 click |
| `padding(_:)` | Component | distributes | 0 | +10 | both member sizes moved | identical |
| `width(_:)` | Component | distributes | 0 | +60 | both member sizes moved | identical |

Those are not predictions. The table is a transcription of a `print` added to
the matrix test's loop, run once and reverted (`git checkout` immediately
after); the dump, verbatim, with the two `Component` rows' member sizes:

```
AUDIT | padding(_:) | legacy Element | wraps | node 1 | outer 16.0 | rects identical | hitRegions identical | clicks 0->0 | storage nil | sizes [] -> []
AUDIT | frame(width:height:) | legacy Element | wraps | node 1 | outer 40.0 | rects identical | hitRegions identical | clicks 0->0 | storage nil | sizes [] -> []
AUDIT | width(_:) | legacy Element | selfStorage | node 0 | outer 40.0 | rects identical | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes [] -> []
AUDIT | margin(_:) | legacy Element | selfStorage | node 0 | outer 20.0 | rects identical | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes [] -> []
AUDIT | hidden() | legacy Element | selfStorage | node 0 | outer -20.0 | rects identical | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes [] -> []
AUDIT | id(_:) | legacy Element | selfStorage | node 0 | outer 0.0 | rects identical | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes [] -> []
AUDIT | focusable() | legacy Element | selfStorage | node 0 | outer 0.0 | rects identical | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes [] -> []
AUDIT | borderWidth(_:) on a sized box | legacy Element | selfStorage | node 0 | outer 0.0 | rects identical | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes ["40.0x40.0"] -> ["40.0x40.0"]
AUDIT | borderWidth(_:) on a content-sized box | legacy Element | selfStorage | node 0 | outer 8.0 | rects identical | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes [] -> []
AUDIT | background(_:) | legacy Element | paintOnly+selfStorage | node 0 | outer 0.0 | rects moved | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes [] -> ["40.0x40.0"]
AUDIT | cornerRadius(_:) | legacy Element | paintOnly+selfStorage | node 0 | outer 0.0 | rects moved | hitRegions identical | clicks 0->0 | storage Optional(true) | sizes ["40.0x40.0"] -> ["40.0x40.0"]
AUDIT | hoverBackground(_:), genuinely hovered | legacy Element | paintOnly+selfStorage | node 0 | outer 0.0 | rects moved | hitRegions identical | clicks 1->1 | storage Optional(true) | sizes ["40.0x40.0"] -> ["40.0x40.0"]
AUDIT | focusBackground(_:), genuinely focused | legacy Element | paintOnly+selfStorage | node 0 | outer 0.0 | rects moved | hitRegions identical | clicks 1->1 | storage Optional(true) | sizes ["40.0x40.0"] -> ["40.0x40.0"]
AUDIT | onClick(_:) | legacy Element | prepaintOnly+selfStorage | node 0 | outer 0.0 | rects identical | hitRegions moved | clicks 0->1 | storage Optional(true) | sizes [] -> []
AUDIT | padding(_:) | legacy Component | distributes | node 0 | outer 10.0 | rects moved | hitRegions identical | clicks 0->0 | storage nil | sizes ["30.0x10.0", "50.0x20.0"] -> ["40.0x40.0", "50.0x40.0"]
AUDIT | width(_:) | legacy Component | distributes | node 0 | outer 60.0 | rects moved | hitRegions identical | clicks 0->0 | storage nil | sizes ["30.0x10.0", "50.0x20.0"] -> ["70.0x10.0", "70.0x20.0"]
```

`Component.padding(20)` takes 30x10 to **40x40** and 50x20 to **50x40** — CSS
border-box padding absorbed into each declared size, agreeing digit for digit
with record §15's scratch `C4` (30x10 → 40x40) and with `OM-D`'s reading of it.
SwiftUI's per-member wrap would give 70x50 and 90x60 (probe G12's shape); lane 4
is where those numbers move, and this row is what will notice.

Four readings worth quoting on their own:

- **`borderWidth(_:)` on a sized box moves nothing at all** — not the outer
  size, not the emitted rect's `borderWidths`, not its `borderColor`. The
  subject carries a background in both arms, so "the rects are identical" is a
  statement about a live rect rather than about an empty scene. This is the
  standing inert row of `CLAUDE.md`'s declared-but-inert table, pinned, and it
  is precisely the API `OM-X` says a triple could not have seen.
- **On a content-sized box the same modifier moves the box by +8 and still
  paints nothing** — the other half of the finding, and why `OM-M` deletes the
  name rather than fixing it.
- **`hidden()` reads node 0 / outer −20**, so the `wraps` witness
  (`nodeDelta > 0` **and** `outerSizeDelta > 0`) does not claim it. Under an
  outer-size-only witness it would have classified as `wraps`, which is `OM-X`'s
  second counterexample, confirmed here on a real reading.
- **`focusable()` registers no pointer target.** All five components zero, only
  storage differs — the keyboard gate and the pointer gate are separate, as
  `CLAUDE.md` says they must stay.

##### Hazards the lane leaves for lanes 2–4

- **`Observation.rects` is compared as a whole, `rectSizes` only for
  `distributes`.** Lane 2 adds fields to `MUIRect`'s emission (`borderColor`,
  `borderWidths`, a rounded mask) that `describe(_ r: MUIRect)` already prints,
  so a new paint-only modifier gets the right answer for free — but a new
  modifier that only moves a rect's POSITION and adds no member needs its own
  thought before it is filed as `distributes`.
- **`hitCountAtEdge` is a probe point the row chooses**, defaulting to `(2, 2)`
  — just inside the subject's outer box. A lane-3 row for
  `contentShape(inset:)` will want a point chosen against that inset, not this
  one.
- **The node count comes from a second render** through a directly built
  `Frame`, because `Window` does not retain its own. If `Window` ever exposes
  its frame, the two renders collapse to one and the doc comment on `observe`
  says so.
- **One stale source doc comment, found and deliberately NOT edited.**
  `StyledElement.borderWidth(_ points:)`'s own doc (`Box.swift:666-671`) says
  "**There is no border colour anywhere in the framework**, so a border width
  changes where the children sit and draws nothing: `Frame.fill` emits
  `borderColor: .transparent` and `borderWidths: 0` **unconditionally**". The
  last word is false as of the proposal path: `Frame.fill`'s signature
  (`Frame.swift:1577-1580`) takes `borderColor` and `borderWidths` as
  parameters, defaulted, and `NativeModifiedContent`'s `.border` passes
  non-defaults. It is true of every legacy caller, which is the only reason the
  sentence still reads plausibly. **Lane 2 deletes both `borderWidth` overloads
  and this doc with them** (`OM-M`), and `Box.swift` is on the brief's
  merge-collision list, so editing four lines that are about to be removed would
  buy a conflict for nothing. Lane 2 owns it; if `OM-M` is ever reversed, the
  word is `unconditionally`.
- **`HandlerFingerprint` in this file is a second copy** of
  `ModifierTests.swift`'s `HandlerShape` projection, and `CLAUDE.md`'s rule
  ("`HandlerShape` must gain a field in the same change `Handlers` gains a
  member") now applies to **two** structs. Lane 3 adds `allowsHitTesting` and
  `contentShapeInset` to `Handlers`; both must gain them.

##### Verifier's verdict — lost; what is reconstructed, and from where

The verifier's report for this lane did not survive the cut-off run. What is
known of it is one sentence in the continuation brief: *lanes 1 and 2 were
verified ok after one fix round*. Nothing on the branch identifies a lane-1
fix commit distinct from the lane's own work — `c07f141` is the
**implementer's** mutation round (its message names the two instruments that
could not fail) and `cfc5c4d` records the one stale doc comment — so whether
"one fix round" refers to lane 1 at all, or only to lane 2's `09a7f7c`, cannot
be settled from the record and is left open here.

**Reconstructed mutation table.** No verifier-authored mutation of lane 1 is
recorded anywhere. The only mutation evidence for the lane is the
implementer's thirteen (M1–M12, M9b, M11b) in the table above, taken from
`8526b51`'s record entry and `c07f141`'s message, and `OM-AD`'s "Mutations"
line in the decisions doc, which cites the same M4/M5/M9 findings. Every figure
in that table is therefore the implementer's, not a verifier's, and the
verdict's "ok" rests on the brief's sentence alone. The two mutations that
stayed green on the first try (M4, M9) and the one that is recorded as
non-discriminating (M11) are the lane's own findings, not a verifier's.

What a later reader can still check without the verdict: the five tests of
`OuterModifierMatrixTests.swift` are on the branch and every mutation in the
table names a `Sources/` line, so the table is re-runnable; the suite figure
`1231` at `c07f141` is quoted from that commit's record entry and was not
re-taken by the record pass (the branch has moved on to 1274, below).

#### Lane 2 — paint-only decoration: border, focus ring, opacity, clip

**Commits.** `c624d13` (red-first: the divergence-15 inversion and three new
compile guards), `9f37d10` (the lane — source, `DecorationPaintTests.swift`,
`ModifierTests` and the matrix rows), then the two-layer scope test and the
`OM-AG` doc correction the mutation round produced.

**The first `Sources/` change on this branch.** `swift package clean` was run
before the first test run of the commit that adds five stored properties to
`Decoration`, a public type that crosses a module boundary (CLAUDE.md's build
note; the same hazard that bit `Scene` twice and `FontKey` once).

##### What was built, and the three places it departs from the spec

Eight modifiers, not §5.1's eleven (`OM-AE`). `allowsHitTesting(_:)` and the
two `contentShape(inset:)` overloads need `Handlers` members and prepaint
wiring that are lane 3's; shipping them here would be three modifiers that
compile and do nothing, in the commit that deletes `borderWidth` for being
exactly that.

`paintDecoration` and `registerAndScope` are **methods on their pass**, not
free functions taking `inout` (`OM-AF`). The free-function form does not
compile: `content()` writes `pass` at all four sites and an `inout` parameter
holds an exclusive access open across the whole call. Verbatim, the four:

```
Sources/MetalUI/Stack.swift:131:82: error: overlapping accesses to 'pass', but modification requires exclusive access; consider copying to a local variable [#ExclusivityViolation]
Sources/MetalUI/Stack.swift:175:64: error: overlapping accesses to 'pass', ... [#ExclusivityViolation]
Sources/MetalUI/ModifiedElement.swift:231:39: error: overlapping accesses to 'pass', ... [#ExclusivityViolation]
Sources/MetalUI/ModifiedElement.swift:272:64: error: overlapping accesses to 'pass', ... [#ExclusivityViolation]
```

The three guards live in a new `Tests/MetalUITests/DecorationCompileGuards.swift`
rather than in `ErasureCompileGuards.swift`, which the other tracks also touch
and whose per-file `grep -c canTypecheck` is how the guard count is taken.

##### The red run, before any source change (`c624d13`)

`swift test --build-system native --no-parallel --filter`, four tests, all red:

```
aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask, 9 issues (3 rows x 3):
  NestedClipTests.swift:141:9  (row.contentMask.size.height -> 0.0) == (100 -> 100.0)
  NestedClipTests.swift:148:9  (row.contentMask.origin.y -> 300.0) == (100 -> 100.0)
  NestedClipTests.swift:150:9  (row.contentMask.origin.y == region.origin.y.value -> false)
borderWidthIsNoLongerSpellable, 1 issue:
  DecorationCompileGuards.swift:64:9 (control.succeeded && !points.succeeded -> false)
  printed: points succeeded=true edges succeeded=true control succeeded=true
theValidatedDecorationFieldsAreNotAssignableFromOutsideTheModule, 1 issue:
  DecorationCompileGuards.swift:128:9 (control.succeeded && !opacity.succeeded -> false)
  printed: "value of type 'Decoration' has no member 'opacity'",
           "cannot find type 'BorderStyle' in scope"
theLegacyAndProposalDecorationModifiersDoNotCollide, 1 issue:
  DecorationCompileGuards.swift:183:9 (both.succeeded -> false) != (crossed.succeeded -> false)
  printed: "value of type 'Box<EmptyGroup>' has no member 'border'"
Test run with 4 tests in 0 suites failed after 1.522 seconds with 12 issues.
```

The rest of the lane's tests cannot be red before the API exists (they do not
compile), so they landed with the source; the mutation round below is what
makes them instruments rather than transcripts.

**Two tests were red as instruments on their first run and were fixed rather
than believed**, both recorded because the fix changed what the test measures:

- `theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate` used a **plain class**
  as its model. `withAnimation` parks a transaction only when a frame build is
  coming, which it decides from the observation counter, so a plain class parks
  nothing, the window never rebuilds, and the control arm read the resting
  token. `@Observable` fixes it. It then failed again at `t = 100.5`: the frame
  that STARTS a fade reads its own `from`, so the first post-write tick is not
  mid-flight. The test now reads both frames — `t = 100.2`, where the
  background is still at `surface` and the border is **already** `accent`, and
  `t = 100.7`, where the background is at neither endpoint.
- `theValidatedDecorationFieldsAreNotAssignableFromOutsideTheModule` asserted
  the diagnostic text `"setter for 'opacity' is inaccessible"`. Swift 6.4 emits
  `"cannot assign to property: 'opacity' setter is inaccessible"`. Corrected
  against the printed message, not guessed.

##### Mutations — twenty-one, applied singly, run filtered, reverted

`git checkout -- Sources Tests` after each; `git status --short` clean of
`Sources/` throughout. Every one reddened.

| # | mutation | site | reddened |
|---|---|---|---|
| M1 | `paintDecoration` passes `borderWidths: Edges(all: Pixels(0))` | `AnimatedColor.swift` | `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout` (2 pixel issues, `[235,99,37,255]` where `[214,205,200,255]` is the border), `aBorderIsVisibleOverAChildThatFillsTheBox`, `everyDecorationPaintingSiteDrawsItsBorder` (5 arms) — **8 issues** |
| M2 | the two emissions swapped: border first, background after the children | `AnimatedColor.swift` | `aBackgroundIsEmittedBeforeTheChildrenAndABorderAfter` (both clauses: `2 < 1`, `1 < 0`), `aBorderIsVisibleOverAChildThatFillsTheBox`, and the pre-existing `aContainerPaintsItsBackgroundBeneathItsChildren` (4 issues) — **7 issues** |
| M2b | both emitted **before** `content()` | `AnimatedColor.swift` | `aBackgroundIsEmittedBeforeTheChildrenAndABorderAfter` (`childIndex 2 < borderIndex 1`), `aBorderIsVisibleOverAChildThatFillsTheBox` |
| M3 | `paintDecorationBody` fills unconditionally (`background ?? .transparent`) | `AnimatedColor.swift` | `anElementWithNeitherABackgroundNorABorderEmitsNoRect` |
| M3a | the border rect emitted unconditionally | `AnimatedColor.swift` | `anElementWithNeitherABackgroundNorABorderEmitsNoRect`, `aBackgroundOnlyElementStillEmitsExactlyOneRect` (`plainCount 2 == 1`) |
| M4 | `Stack.paint` reverted to its pre-lane fill (the `paintDecoration` call dropped at ONE site) | `Stack.swift` | `everyDecorationPaintingSiteDrawsItsBorder` at its **`Stack` arm** (`bordered.count 0 == 1`), `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` at the same arm |
| M5 | `resolvedBorder`'s chain reversed (hover outranks focus) | `AnimatedColor.swift` | `aFocusRingOutranksAHoverBorderAndABorder`, `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` — **13 issues** |
| M6 | `resolvedBorder` resolves `decoration.border` alone | `AnimatedColor.swift` | the same two, **and** the matrix's `focusBorder(_:width:), genuinely focused` row at its `paintOnly` witness (`rectsMoved`) — **14 issues** |
| M7 | the opacity scope opened **after** the element's own fill | `AnimatedColor.swift` | `opacityMultipliesAndFadesTheElementsOwnBackground` (both the half and the quarter), `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot` at its control |
| M8 | the paint clip loses its radii (`Corners(all: Pixels(0))`) | `AnimatedColor.swift` | `clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius` |
| M9 | `pushClip`'s `+ activeOffset` reverted | `Frame.swift` | `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints` (`scrolled.mask 150` vs paint), `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` (9 issues). **The four regression-bound tests stayed green** in the same run: `nestedClipsIntersectRatherThanReplace`, `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`, `aHitboxInsideAScrolledRegionIsRecordedWhereItPaints`, `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` |
| M10 | the prepaint half of the clip dropped | `DecorationScope.swift` | `clippedAlsoClipsTheHitboxesInsideIt`, at its **`#require`**: both arms read 60, which is the defect stated as a broken instrument |
| M11 | `pushRootClip`/`popClip` reset `opacityStack` | `Frame.swift` | `aDeferredPortalInsideAFadedSubtreeIsStillFaded` |
| M12 | `StyledElement.opacity(_:)`'s precondition removed (and the value dropped) | `Box.swift` | `anOpacityAboveOneTraps` (both arms, `.failure -> .exitCode(0)`) **and the positive control** `theAdmittedOpacitiesAndBorderWidthsBehave` (`.success -> .signal(SIGTRAP)`), which is what says the control checks what it admits |
| M13 | `BorderStyle.init(_:widths:)` stops validating | `Box.swift` | `aNegativeBorderWidthTraps` (3 arms), `aBorderWidthSetAfterInitIsStillValidated` |
| M14 | `Decoration.setOpacity` stops validating | `Box.swift` | `anOpacitySetAfterInitIsStillValidated`, its `setOpacity` arm |
| M14b | the memberwise `init` stops validating opacity | `Box.swift` | `anOpacitySetAfterInitIsStillValidated`, its `Decoration(opacity: 2)` arm |
| M15 | `ModifiedElement.paint` restored to its pre-lane **loop** | `ModifiedElement.swift` | `aChainsOuterLayerScopesContainTheLayersInsideIt`, all three clauses. **Nothing else** — see below |
| M16 | `paintLayer` recurses with the OUTER bounds | `ModifiedElement.swift` | `aChainsOuterLayerScopesContainTheLayersInsideIt`, `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`, `everyBackgroundPaintingSiteHonoursHoverAndFocus` |
| G1 | the `borderWidth` guard's two negatives pointed at `padding` | the guard | `borderWidthIsNoLongerSpellable` |
| G2 / G2b | `Decoration.opacity` / `BorderStyle.widths` made a plain `public var` | `Box.swift` | `theValidatedDecorationFieldsAreNotAssignableFromOutsideTheModule`, each |
| G3b | `clipped()` declared on `ElementGroup` | `Box.swift` | `theLegacyAndProposalDecorationModifiersDoNotCollide` (`both true != crossed true`) |

**All three new guards ran rather than skipped**: `canTypecheck(module:
"MetalUI")` is true in this worktree after `swift build --build-system native`,
and each was reddened by its own mutation above.

##### What the mutations found — `OM-AF`, `OM-AG`, and one missing test

**M15 found a missing test, not a bug.** Restoring `ModifiedElement.paint`'s
pre-lane loop — every layer's decoration emitted in sequence, then the content
once — reddened **nothing**, because every opacity and clip fixture in
`DecorationPaintTests.swift` was ONE element. An opacity on the outermost layer
of a two-layer chain would have left the inner layer's fill opaque and a
`.clipped()` there would have bounded nothing but the content, with no
diagnostic. `aChainsOuterLayerScopesContainTheLayersInsideIt` was added: a
`.padding(4).background(.accent).padding(8)` chain with the fade or the clip on
the outer layer, asserting the INNER layer's 28x28 rect. M15 reddens all three
of its clauses afterwards. Taxonomy shape 2 (fixtures too shallow), and
`OM-AD`'s lane-1 finding reappearing in the paint phase — this lane read that
finding, applied it to the two order tests it named, and did not apply it to
the new scopes.

**G3 is a mutation that could not redden its guard, and it is `OM-AG`.**
Declaring the legacy `opacity(_:)` on `ElementGroup` — the collision §8's risk
row describes — leaves `HStack { … }.opacity(0.5)` unambiguous, because
`ProposalElementGroup` refines `ElementGroup` and Swift prefers the more
refined protocol's extension. The guard's doc named that mutation; it now names
G3b, the collision that IS reachable (a legacy-only spelling leaking onto every
proposal element).

##### The audit table, re-taken where lane 2 moved it

Lane 1's sixteen matrix rows are eighteen. The two `borderWidth(_:)` rows are
gone with the modifier and four rows replace them:

| row | kinds | node | outer | rects | hit |
|---|---|---|---|---|---|
| `border(_:width:)`, sized box | self + paint-only | 0 | 0 | **moved** | identical |
| `border(_:width:)`, content-sized box | self + paint-only | 0 | **0** | **moved** | identical |
| `focusBorder(_:width:)`, focused | self + paint-only | 0 | 0 | moved | identical |
| `opacity(_:)` | self + paint-only | 0 | 0 | moved | identical |
| `clipped()` | self + paint-only | 0 | 0 | moved | identical |

The content-sized row is the whole of `OM-B`/`OM-M` in one line. Lane 1
measured `borderWidth(_:)` on that same box at **node 0 / outer +8 / rects
identical** — it moved the layout by twice its width and painted nothing.
`border(_:width:)` reads **outer 0 / rects moved**: layout-neutral, as SwiftUI's
is (probe L2), and visible.

`clipped()` claims `paintOnly` and not `prepaintOnly`, because lane 1's
instrument treats the two as exclusive (`prepaintOnly` asserts `!rectsMoved`).
Its prepaint half is pinned by `clippedAlsoClipsTheHitboxesInsideIt` instead,
and the row's note says so.

##### Counts, re-taken at the end of the lane

| reading | value | against lane 1's `c07f141` |
|---|---|---|
| `swift test --build-system native --no-parallel` | `Test run with 1256 tests in 1 suite passed after 34.192 seconds.` | **+25** on 1231 |
| `error:` / `warning:` in the run | **0** / **0** | unchanged |
| `find Tests -name "*.json" \| wc -l` | **97** | unchanged; `git diff --stat c4b5853 -- Tests` lists no `.json` |
| guards, `grep -c canTypecheck` per file | 19 / 10 / 5 / 3 / 3 / 2 / 6 / 6 / 8 / **3** = **65 hits, 64 guards** | **+3**, all in `DecorationCompileGuards.swift` |
| `grep -c "public func" Sources/MetalUI/Box.swift` | **47** | 40 − 2 + 8 + `BorderStyle.withWidths` |
| `ModifierTests`' `cases.count` tripwire | **44** | 38 − 2 + 8; lane 3 takes it to the pre-agreed 47 |

##### The demo and the preview: 0 differing pixels, and the instrument that proves it can see one

`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` read **`<true/>`** at
**2026-09-15 20:22:34 PDT**, so no real-window `screencapture -R` was taken and
none was attempted; no demo was launched and no input was sent. The offscreen
comparison is the primary evidence (`OM-AC`), and it is sufficient on its own.

Method, `MC-J`'s: `git archive c4b5853` and `git archive HEAD` into two scratch
directories; in each, a generated test file holds that tree's `main.swift` up
to `runDemo()` (types prefixed `SI`, globals `nonisolated(unsafe)`) and renders
through a real `Window` over `FakePlatformWindow` at 1024x1024, scale 1, writing
`fakeSurface.readPixels()`. Ten images per tree, debug builds. `Sources/MetalUIDemo`
is byte-identical between the two commits (`git diff --stat c4b5853 -- Sources/MetalUIDemo`
is empty), so the demo's own declarations are not a variable here.

| comparison | differing pixels |
|---|---|
| control: base light vs base dark | 1 048 576 (all) |
| control: base default vs base modal | 1 030 499 |
| control: base default vs base animation look | 210 043, bbox (16, 113)–(981, 1007) |
| control: base frame 0 vs base frame 3 | 0 (deterministic clock) |
| **base vs lane 2, all ten images** | **0** |
| instrument: lane 2 vs lane 2 with `paintDecoration`'s background emitted AFTER `content()` | demo/modal/animation, light and dark: **949 108** each, bbox (16, 16)–(1007, 1007); **preview 0** |

The ten are `demoContent()` light and dark at frame 0 and after three ticks, the
modal (`showModal = true`) light and dark, the settled animation look
(`animationDemoActive = true`) light and dark, and
`nativeLayoutPreviewContent()` light and dark.

**Reading.** Lane 2 renders the default demo, the modal, the settled animation
look and the proposal preview byte-identical to `c4b5853` in both themes. The
instrument moves every legacy image when this lane's own helper changes its
emission order, so the zeros are a statement about a code path the comparison
actually exercises — and it moves **no** preview pixel, because the preview is
the proposal path and reaches no `paintDecoration` at all, so the preview's zero
is the weaker of the two claims (as record §13 said of the same pair).

**Not covered**, unchanged from record §13: the drawable, the display's colour
space, the real 920x560 window and AppKit appearance, anything input-, focus-,
hover- or scroll-driven, a mid-flight animation, and a release build.

**No deliberate demo change.** The focus ring is opt-in and the demo declares no
`.focusBorder`; `grep -rnE "\.(border|hoverBorder|focusBorder|opacity|clipped)\(" Sources/MetalUIDemo`
finds only the proposal preview's `.border`/`.opacity`, which are
`ProposalElementGroup`'s and untouched. If a reviewer wants the ring seen on
screen, it is a separate commit whose diff is the demo file alone (spec §7 lane
4, step 3).

##### Hazards the lane leaves for lanes 3 and 4

- **`registerAndScope` is where lane 3's `allowsHitTesting` scope goes**, at the
  TOP of the function, wrapping the receiver's own `registerHandlers` as well as
  `content()` (`OM-T`, probe N1). The function is already shaped for it — the
  closure and the generic return type are there — and its doc says so.
- **`HandlerShape` and `HandlerFingerprint` must both gain `allowsHitTesting`
  and `contentShapeInset`** in the same change `Handlers` does (CLAUDE.md's rule,
  now covering two structs — lane 1's note).
- **The tripwire is at 44, not 38.** Lane 3 adds three and lands on the
  pre-agreed 47.
- **`DecorationCompileGuards.swift`'s collision guard names `clipped()` as
  legacy-only.** When lane 3 adds `allowsHitTesting(_:)` to `StyledElement` —
  a name the proposal path also declares — the `both` fixture should gain a
  legacy `.allowsHitTesting` arm, and `OM-AG`'s finding says the resulting
  ambiguity cannot be produced by a superprotocol member.
- **The matrix instrument treats `paintOnly` and `prepaintOnly` as exclusive.**
  Lane 3's `contentShape(inset:)` row is `prepaintOnly` and must not also claim
  `paintOnly`; `clipped()` is filed `paintOnly` for this reason and its prepaint
  half is pinned separately.
- **`Decoration` now has nine stored properties and five of them are new.**
  `swift package clean` before the first run of any commit that adds a tenth.

##### Review round — three issues, two of them findings about instruments

The lane's verifier ran twenty-one mutations of its own, sixteen of which
reddened as recorded. **Two did not**, and they are the round's substance.

**Issue 1 (major, `OM-AI`) — the SCOPE half of both helpers was pinned at one
site each.** Four mutations, applied singly with the FULL suite run, all green
at `Test run with 1256 tests in 1 suite passed`:

| mutation | behaviourally | seen by |
|---|---|---|
| `Text.paint` keeps `paintDecoration(…) { }` and calls `paintGlyphs` after it | `Text("hi").background(.accent).opacity(0.5)` emits glyph alphas **1.0** where the unmutated tree emits **0.5**; the background rect stays 0.5 in both | nothing |
| `Stack.paint` likewise with `content.paintGroup` | `Stack { Box().background(.accent) }.opacity(0.5)` emits the child at **1.0** where the unmutated tree emits **0.5** | nothing |
| `Stack.prepaint` passes `Decoration()` to `registerAndScope` | a `.clipped()` `Stack` registers hitboxes outside the box it draws | nothing |
| `ModifiedElement.prepaintLayerBody` passes `Decoration()` | the same, per layer | nothing |

The lane's own M4 and M10 dropped the whole helper call, or the clip *inside*
the helper, so neither reached this finer shape:
`everyDecorationPaintingSiteDrawsItsBorder` asserts that ONE rect exists with
the right box and widths, which a site that keeps the call and paints its
children outside the closure satisfies completely.

Two instruments answer it:

- **`everyDecorationScopingSiteContainsItsOwnContent`** (new) — four arms,
  `Box` / `Stack` / `Text` / a **two-layer** `ModifiedElement` (`OM-AD`'s
  reason), each asserting three things about the site's own content: its alpha
  is the element's `opacity` multiple, its `contentMask` is the element's own
  40x40 box under `.clipped()`, and the border's position in the **finalized**
  paint order is after it. The order clause needs `Scene.drawList` rather than
  either array's indices, because a `Text`'s content is glyphs and its border is
  a rect (`paintPositions(_:)` in the test file).
- **`clippedAlsoClipsTheHitboxesInsideIt`** — was one `Box` fixture, is now a
  three-arm table (`Box` 60, `Stack` 50, `ModifiedElement` 50; `Stack` and
  `.frame` both centre, so the overflowing child starts at −10 and
  `Frame.insertHitbox` meets the root clip first). `Text` has no children and no
  arm. The click moved from y 50 to y 45, which is inside the 60x60 child at
  every site and below the 40x40 clip at every site.

The mutation round for them, each applied singly and reverted:

| # | mutation | reddened |
|---|---|---|
| MV1 | `Text.paint` glyphs outside the closure | `everyDecorationScopingSiteContainsItsOwnContent`, all three clauses at the `Text` arm (`faded.alpha` off by 0.5, mask, `border 0 > content 2`) |
| MV2 | `Stack.paint` children outside the closure | the same three at the `Stack` arm |
| MV5 | `Box.paint` children outside the closure | the same three at the `Box` arm |
| MV6 | `ModifiedElement.paintLayer` content outside the closure | the same three at the `ModifiedElement` arm |
| MV3 | `Stack.prepaint` passes `Decoration()` | `clippedAlsoClipsTheHitboxesInsideIt`, `Stack` arm, at its `#require` (both arms read 50) |
| MV4 | `ModifiedElement.prepaintLayerBody` passes `Decoration()` | the same, `ModifiedElement` arm (both read 50) |
| MV7 | `Box.prepaint` passes `Decoration()` | the same, `Box` arm (both read 60) |

Three doc claims were corrected in the same change rather than left standing
over tests that could not see them: `DecorationScope.swift`'s "`clippedAlsoClips…`
is the pin", `Text.paint`'s "a faded one fades them with its fill" and "a
bordered `Text` draws its ring over its own glyphs", and `paintDecoration`'s
"`everyDecorationPaintingSiteDrawsItsBorder` is the per-site guard here" — now
"two per-site guards, because the call has two halves".

**Issue 2 (major, `OM-AH`) — spec §6.2's `.opacity(0.5).opacity(0.5)` row was
filed as an AGREEMENT and is a divergence.** Measured in this worktree through a
real `Window`, reading the emitted rect's alpha:

| spelling | alpha |
|---|---|
| `Box().width(40).height(40).background(.accent)` | 1.0 |
| `…​.opacity(0.5)` | 0.5 |
| `…​.opacity(0.5).opacity(0.5)` | **0.5** |
| `Box { Box()…​.opacity(0.5) }.opacity(0.5)` | 0.25 |
| `…​.opacity(0.5).padding(2).opacity(0.5)` | 0.25 |

`Frame.activeOpacity` multiplies *scopes*; an element contributes exactly one
scope whose value is one field, so two writes to that field cannot become two.
SwiftUI's G1/G2 is **one view with two calls**. `docs/probes/swiftui-border-clip-paint.swift` was **re-run in this round**
(`/usr/bin/swift docs/probes/swiftui-border-clip-paint.swift`, empty stderr): all
twenty-six recorded lines reproduce, controls K0/K1 included, so the header is
evidence taken now and not a transcript. The row is now "not
expressible", `OM-H`'s count goes four → five, and `OM-N`'s evidence paragraph
loses the sentence that cited G1/G2 as support for it. `StyledElement.opacity(_:)`'s
doc comment said "Opacities compose by multiplication, as SwiftUI's do", which
is the sentence that would make a caller write the one spelling that does not;
it and `Decoration.opacity`'s doc now name the divergence and the two spellings
that multiply.

`aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies` is the pin.
Its disagreeing arms are the nested and the layered spellings; mutating
`StyledElement.opacity(_:)` to `$0.setOpacity($0.opacity * value)` reddens it
(`abs(twice - once) → 0.25`) **and nothing else in the suite**, which is the gap
restated as a measurement.

`opacityMultipliesAndFadesTheElementsOwnBackground`'s own doc previously read as
a G1/G2 agreement while its fixture silently substituted nested boxes for
SwiftUI's single-view chain; the substitution is now named in the doc and at the
line.

**Issue 3 (minor) — `Decoration` grew and a measured number in `Sources/` went
stale.** `AnimatedStyle.swift`'s storage doc said a settled `$anim` entry costs
"one `Style` (228) plus one `Decoration` (**12**)". Re-measured at this commit:

| type | stride | size |
|---|---|---|
| `Decoration` | **80** | 77 |
| `BorderStyle` | **20** | — |
| `Style` | 228 | — |
| `AnimatedElementState` | **320** | — |

The line is corrected and carries the arithmetic consequence: 68 bytes of extra
payload per settled entry, and a `$anim` entry is minted unconditionally per
registering element (a 500-row `List` is 1,007), so ~6.8 MB at n = 100,000
against the ~51 MB the animation milestone measured. **The end-to-end per-entry
figures (643 bytes at n = 20,000) are NOT re-taken**, and the reason is stated at
the line rather than left implicit: the harness that produced them is the
animation milestone's isolated-process one, and task 13 — which stops these
fields snapping — is where it should be re-run.

##### Counts, re-taken after the review round

| reading | value | against `5a28933` |
|---|---|---|
| `swift test --build-system native --no-parallel` | `Test run with 1258 tests in 1 suite passed after 37.688 seconds.` | **+2** on 1256 |
| `error:` / `warning:` in the run | **0** / **0** | unchanged |
| `find Tests -name "*.json" \| wc -l` | **97** | unchanged; `git diff --stat c4b5853 -- Tests` lists no `.json` |
| guards, `grep -c canTypecheck` per file | 19 / 10 / 5 / 3 / 3 / 2 / 6 / 6 / 8 / 3 = **65 hits, 64 guards** | unchanged |

`swift package clean` was run before this suite: `Decoration` did not change
shape in this round, but `AnimatedStyle.swift`'s doc sits beside the type whose
storage did, and the clean is cheap against the symptom (record §06).

No `Sources/` behaviour changed in the review round — every source edit is a doc
comment — so the demo/preview pixel comparison recorded above stands unchanged
and was not re-taken.

##### Verifier's verdict — lost; what is reconstructed, and from where

The verifier's report itself is gone with the cut-off run. Unlike lane 1, its
substance survives in two places written from it at the time: the "Review
round" subsection above (written by the fix-round agent from the verifier's
three issues) and the fix commit `09a7f7c`, whose message restates the four
green mutations with the alphas measured in the mutated trees (a faded
`Stack`'s child and a faded `Text`'s glyphs at **1.0** where the unmutated tree
emits **0.5**). So the following is reconstructed, not quoted:

| figure | value | source |
|---|---|---|
| verifier mutations run | **21**, "sixteen of which reddened as recorded" | the review-round subsection above |
| stayed green | the **four** tabled above (`Text.paint` and `Stack.paint` painting content outside the closure; `Stack.prepaint` and `ModifiedElement.prepaintLayerBody` passing `Decoration()`) | the subsection and `09a7f7c` |
| unaccounted for | 21 − 16 − 4 = **1** mutation whose outcome the surviving text does not state | arithmetic on the two figures above; the verdict is the only place it was recorded |
| issues raised | one major (`OM-AI`), one major (`OM-AH`), one minor (`AnimatedStyle.swift`'s stale byte count) | the subsection, `09a7f7c` |
| fix round's own mutations | MV1–MV7, each reddening its own site's arm (tabled above) | the subsection |
| suite at re-verification | `Test run with 1258 tests in 1 suite passed after 37.688 seconds.` | the subsection; the brief's "suite 1258 at lane 2's re-verification" agrees |

The verdict's "ok" is the brief's sentence plus the 1258 figure the brief and
the subsection independently carry; the mutation the arithmetic leaves
unaccounted for is the one thing a later reader cannot recover from the branch.

#### Lane 3 — hit testing: `allowsHitTesting` and `contentShape`

**Commits.** `6279f59` (red-first: the collision guard's two new names, the
default-hit-region test pinned wrong on purpose, and the two probes —
`swiftui-content-shape-hit-region` re-recorded with H4–H6,
`swiftui-allows-hit-testing-side-effects` new), `e1c33b5` (the lane: source,
`HitRegionTests.swift`, the `ModifierTests` and matrix rows), then this record
with `OM-AJ`, `OM-AK` and two stale doc comments.

**A continuation.** The run that began this lane stopped at 2026-09-15 21:46
PDT with `6279f59` committed and the implementation partly written and
uncommitted (`Box.swift`, `DecorationScope.swift`, `Frame.swift`,
`Handlers.swift`, `HitRegionTests.swift`). The continuation read that diff and
kept it. What it lacked: `HandlerShape` and `HandlerFingerprint`'s two fields,
the three `ModifierTests` rows and the 47 tripwire, the two matrix rows, a
per-edge arm for test 3, and the two rulings the source and tests already cited
by letter — `OM-AJ` was being used for two different claims (the H6 clip
divergence and the scroll-region bypass), so the second became `OM-AK` and
every citation was re-pointed.

##### What was built, and the five places it departs from the spec

`Handlers.allowsHitTesting: Bool = true` and `Handlers.contentShapeInset:
Edges<Pixels>?`, appended at the end of the stored members.
`PrepaintPass.registerAndScope` opens the pointer-disable scope at the top,
around the receiver's own `registerHandlers` and `content()` alike (`OM-T`),
with the body split into `registerAndScopeBody` rather than written twice.
`Frame.registerHandlers` applies the inset to the bounds handed to
`insertHitbox` and nowhere else, through `Frame.hitRegion(_:inset:)`, which
does not clamp a negative inset (`OM-J`). Three modifiers at the end of
`extension StyledElement` in `Box.swift`. `swift package clean` before the
first test run: `Handlers` is a public struct crossing a module boundary and
gained two stored members.

1. **Test 3 has a per-edge arm** (top 5 / right 10 / bottom 15 / left 20 on a
   100x100 box, four clicks each deciding on one edge). The spec's uniform
   `inset: 20` is taxonomy shape 1: `hitRegion` subtracting `left` twice gives
   100 − 20 − 20 = 60 either way, and the mutation round confirmed the uniform
   arm cannot see it (M12 below).
2. **`OM-AJ`**: the probe's H6 arm (recorded in `6279f59`) says SwiftUI's grown
   region hits through an ancestor `.clipped()`; MetalUI's is intersected with
   the active clip like every hitbox. A new divergence, pinned by test 4.
3. **`OM-AK`**: a `ScrollView` under a legacy `.allowsHitTesting(false)` still
   registers its scroll region and still scrolls — `registerScrollRegion`
   bypasses `hitTestingDisabledDepth`. Pinned wrong on purpose by
   `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`; no SwiftUI claim.
4. **The matrix gains two rows**, `contentShape(inset:)` and
   `allowsHitTesting(_:)`, both `self` + `prepaint-only`, both arms carrying an
   `onClick` because neither modifier creates a region (`OM-AB`). Lane 1's
   table had no row for either; `HandlerFingerprint` gained the two fields in
   the same change, as lane 1's hazard note required.
5. **The spec's row 2a named the wrong tests.** See the mutation table.

##### The red run

Against the committed source (`git stash push -- Sources/`, `swift package
clean`, `swift build --build-system native --build-tests`): 33 diagnostics,
all "has no member" —

```
HitRegionTests.swift:186:35, 198:14, 216:10, 262:32, 268:32, 273:32, 279:33, 318:26,
  322:26, 325:26, 329:40, 336:45, 602:36
    value of type 'Box<EmptyGroup>' / 'Stack<Box<EmptyGroup>>' / 'Text' /
    'ModifiedElement<Box<EmptyGroup>>' / 'Box<Box<EmptyGroup>>' /
    'Box<ScrollView<Box<EmptyGroup>>>' has no member 'allowsHitTesting'
HitRegionTests.swift:384:55, 420:12, 466:41, 515:34, 557:14, 566:14
    value of type 'Box<EmptyGroup>' has no member 'contentShape'
HitRegionTests.swift:463:13  type '() -> Box<EmptyGroup>' cannot conform to 'ElementGroup'
HitRegionTests.swift:532:35  cannot infer key path type from context
HitRegionTests.swift:610:99  failed to produce diagnostic for expression
ModifierTests.swift:386:61, 387:62   'Handlers' has no member 'allowsHitTesting' / 'contentShapeInset'
OuterModifierMatrixTests.swift:125:30, 126:31 (the fingerprint), 594:33, 598:44,
  610:33, 614:44
```

(the three odd ones are the compiler giving up on a closure whose member
lookup already failed). With the source in and the three `ModifierTests` rows
out, `swift test --build-system native --no-parallel --filter <the lane>`:

```
everyPublicModifierWritesItsOwnFieldAndOnlyThatField, 1 issue:
  ModifierTests.swift:361:5 Expectation failed: cases.count == 47     (reads 44)
Test run with 14 tests in 0 suites failed after 0.989 seconds with 1 issue.
```

Every other lane test was green on that run, including the collision guard
that `6279f59` recorded red for the missing names (it ran: `canTypecheck` is
true in this worktree after `swift build --build-system native`). The rest
cannot be red before the API exists — lane 2's precedent — and the mutation
round is what makes them instruments.

##### Mutations — sixteen, applied singly, reverted with `git checkout` after `e1c33b5`

Run filtered (`--filter` over the lane's tests plus `clippedAlsoClips`, the D2
guard, `onClickIsLiveOnEveryConformerThatCanRegisterOne`,
`aPaddedClickTargetIsHittable`, `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`
and `aTextIsPublishedAsStaticTextWhoseValueIsItsString`), except M5 on the full
suite. Every one reddened. `git status --short` clean of `Sources/` after each,
checked by the driver with `git diff -G "// MUTATION"` — **not** by a grep for
the marker over `Sources/`, because `Component.swift` carries that literal in
four committed comment lines (its own mutation records) and the first version
of the check reported a phantom dirty file on every run.

| # | mutation | reddened (issues) |
|---|---|---|
| M1 | `registerAndScope` registers OUTSIDE the scope and scopes children only (the first draft's mechanism) | test 1 at `n1.clicks == 0 && n1.regions.isEmpty` (N2 is asserted as `n2 == n1` and both register, so it fails as one); test 2 all four arms; test 2a's `frame.hitboxes.isEmpty` set-up; the matrix `allowsHitTesting` row — 10. **The child arm stays green**, as the spec required |
| M2 | `guard !handlers.allowsHitTesting` | 14 tests, 43 issues: every control `#require` in the file, D2's `control == 1`, `onClickIsLive…`, `clippedAlsoClips…`, `aPressIsRefusedWhereHitTestingIsDisabled`, the matrix, `aPaddedClickTarget…` |
| M3 | `focusRegistry.register` gated on `hitTestingDisabledDepth == 0` | test 1 **only**, its two keyboard assertions (N1's `keyRan && focusable` and the child's) — 2 |
| M4a–d | one site passes handlers with `allowsHitTesting` forced `true` (`Box.prepaint`, `Stack.prepaint`, `Text.prepaint`, `ModifiedElement.prepaintLayerBody`) | each: test 2's own arm and test 2a's own set-up (2 each); `Box` also test 1 (N1 and the child, whose parent is a `Box`) and the matrix row — 5 |
| M5 | `registerAndScopeBody` forwards the three-argument `registerHandlers` | **full suite, 11 tests, 24 issues**: test 2a's `strings.contains("hi")` and ten in `AccessibilityDefaultsTests.swift` — `aTextIsPublishedAsStaticTextWhoseValueIsItsString`, `labelAndValueFollowSwiftUIsStaticTextRules`, `aClickableTextIsAButtonLabelledByItsString`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`, `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `aClientDoesNotChangeStateRetention`, `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` |
| M6 | the inset applied at the call site (`registerAndScopeBody` insets `bounds`; `registerHandlers` inserts bare `bounds`) | test 5 only: the emitted `AXNode`'s frame and the client record's geometry — 2. Test 3 stays green, as the spec predicted |
| M7 | `hitRegion` clamps each inset at 0 | test 4's `#require(plain.regions != grown.regions)` — 1 |
| M8 | `Box.prepaint` hands `registerAndScope` empty handlers when `background == nil` | test 6 (all three assertions) plus nine others — 25 |
| M9 | the hitbox insert also fires on `contentShapeInset != nil` | test 6a's `bare.lastHitboxes.isEmpty` — 1 |
| M10 | `contentShape(inset: Edges)` writes `top` for `left` | `ModifierTests` (the per-edge row) and test 3's per-edge arm (its region string, its left-edge and right-edge clicks) — 4 |
| M11 | `registerScrollRegion` consults the depth | `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`, both scoped-arm assertions — 2 |
| M12 | `hitRegion` subtracts `left` twice | test 3's per-edge region assertion **alone** — 1. The uniform arm (line 391) and `ModifierTests` cannot see it |
| M13 | `focusable()` also writes `contentShapeInset = 0` | `ModifierTests` alone — 1: the projection tracks the struct (the closure the practices doc names for `HandlerShape`) |
| M14 | `contentShape(inset: Pixels)` writes nothing | tests 3, 4, 5, 6a, `ModifierTests`, and the matrix row's broken-instrument `#require` — 6 |
| M15 | `allowsHitTesting(_:)` writes `!enabled` | tests 1, 2, 2a, `ModifierTests`, the matrix row's `#require` — 12 |

##### What the mutations found

- **The spec's row 2a predicted two test names and both were wrong**
  (`OM-X` said the lane must take the names from the red run, and this is why).
  `aTextLeafPublishesItsStringAsAValue` does not exist.
  `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` exists and
  **stays green** under M5: a declared `AXNode` is emitted by the
  three-argument overload too (`Frame.registerHandlers` reads `handlers.axNode`,
  not `accessibleText`), so that test cannot see the payload and was never
  going to. The spec's row now carries the eleven measured names.
- **The uniform-inset arm is blind to an edge transposition** (M12), which is
  why the per-edge arm exists; `ModifierTests`' per-edge row catches the
  modifier transposing (M10) but not `hitRegion` doing so, because it reads
  the field and never the registered region. The two instruments overlap on
  M10 and separate on M12 and M13 — a differential between named tests, not
  an exclusivity claim.
- **M3 reddens exactly the two keyboard assertions**, so the "removes the
  pointer target and nothing else" half of `OM-T` is pinned as its own clause
  and not as a side effect of the pointer half.
- **M1 leaves the child arm green** and M4a reddens it — the two together say
  the child arm measures the SUBTREE half of the scope and the N1 arm the
  receiver half.

##### Counts, re-taken at `e1c33b5`

| reading | value | against lane 2's re-verification |
|---|---|---|
| `swift test --build-system native --no-parallel` | `Test run with 1267 tests in 1 suite passed after 40.730 seconds.` (and 44.344 s after the mutation round's reverts) | **+9** on 1258: the nine tests of `HitRegionTests.swift` |
| `error:` / `warning:` | **0** / **1** — SwiftPM's own `--build-system native` deprecation notice | unchanged |
| skipped | the two gated tests only | unchanged |
| `find Tests -name "*.json" \| wc -l` | **97**; `git diff --stat c4b5853 -- Tests` lists no `.json` | unchanged |
| guards, `grep -c canTypecheck` per file | 19 / 10 / 5 / 6 / 2 / 6 / 8 / 3 / 3 / 3 = **65 hits, 64 guards** | unchanged; the collision guard was extended, not added |
| `grep -c "public func" Sources/MetalUI/Box.swift` | **50** | +3 |
| `ModifierTests`' `cases.count` tripwire | **47** | the pre-agreed number |
| `Handlers` stored members | **8** | +2 |

##### The demo and the preview: lane 4's, and the display was unlocked

Lane 3 changes no paint path and no layout node: `allowsHitTesting` and
`contentShapeInset` are read in `registerAndScope` and `registerHandlers` only,
and `git diff --stat c4b5853 -- Sources/MetalUIDemo` is empty. The offscreen
pixel comparison is the spec's **lane 4** deliverable ("the verification") and
is not re-taken here. **One reading for lane 4:** `ioreg -n Root -d1 -a | grep
-A1 IOConsoleLocked` read **`<false/>`** at **2026-09-15 23:33:05 PDT** — the
first unlocked reading since the design sessions — so if it still reads so at
lane-4 time, the real release-window captures the spec's step 2 asks for are
possible. No demo was launched and no input was sent in this lane.

##### Hazards the lane leaves for lane 4 and the integration step

- **`OM-AK` extends an inert-table row's reach.** CLAUDE.md's
  "`.allowsHitTesting(false)` over a scroller — gates click hitboxes only" was
  written for the proposal path; it is now true of any legacy element too.
- **`OM-AJ` and `OM-AL` need divergence numbers** (the carried list below is
  now ten).
- **`CLAUDE.md`'s `HandlerShape` sentence must name both structs** — both
  gained the two fields in `e1c33b5`, and the doc comment on `HandlerShape`
  now says `Handlers` has EIGHT members.
- **`grep -c "public func" Sources/MetalUI/Box.swift` is 50**, and
  `ModifierTests`' reconciliation note says so; task 4's additions count from
  there.
- **`Component.swift` contains the literal `// MUTATION`** in four committed
  comment lines. Any driver that greps `Sources/` for a marker to prove a
  revert will report it dirty on every run; grep the diff instead.
- **The other track was building in its own worktree throughout**
  (`MetalUI-frame-sizing`, seen in `ps`); nothing touched this checkout, and
  no measurement here was taken in a contended window.

##### Review round — one major, three minors, and a probe extended

The verifier (2026-09-15 23:50–00:00 PDT, at `2859350`) re-ran both probes
byte for byte, ran nineteen mutations (V1–V19b; every one reddened what the
table above predicted, and V0 — a scratch hover test — confirmed a doc claim),
and raised one major and three minors. Fixed at the commit after `2859350`.

**Major — an order-sensitive chain across a layer boundary was an unrecorded
divergence.** `OM-T` and spec §6.3's N2 row said "the order is not
observable"; that holds only while both modifiers land on one
`ModifierLayer`. With `.padding(40)` between them, `Box().allowsHitTesting(false)
.padding(40).onClick { }` scopes the inner layer and leaves the outer layer's
200x200 hitbox live (centre 1 / edge 1), where SwiftUI reads 0 / 0; the
reverse order reads 0 / 0 on both. Disposition:

- `swiftui-content-shape-hit-region.swift` gained arms **X0–X3**, re-recorded
  2026-09-16 00:03 PDT under `/usr/bin/swift`, exit 0, every pre-existing arm
  byte for byte: X0 `colour.padding(40).tap` (control) **1 / 0**; X1
  `colour.hitOff.padding(40).tap` **0 / 0**; X2 `colour.padding(40).hitOff.tap`
  **0 / 0** (new — the verifier probed X0, X1 and X3 only); X3 X1 +
  `.contentShape(Rectangle())` then tap **1 / 1**.
- **X3 decides the disposition: recorded, not fixed.** SwiftUI's modifier
  empties the subtree's hit *region* and a later `.contentShape` restores it
  for the outer gesture; MetalUI's region is always the frame (`OM-I`), so its
  X1 answer *is* SwiftUI's X3. A fix that let an inner layer's scope suppress
  the layers written after it would reproduce X1 and contradict X3 in one
  stroke. Ruling **`OM-AL`**; `OM-T` narrowed in place to "within one
  `ModifierLayer`"; spec §6.3 gains the four X rows and the N2 row's caveat.
- Pinned wrong on purpose by
  `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`
  (`HitRegionTests.swift`): X0 `#require`d live at both points, X1 and X2
  `#require`d to **disagree**, then X1 asserted 1 / 1 with one `(0,0) 200x200`
  region and X2 0 / 0 with none. The doc comments on `Handlers.allowsHitTesting`,
  `StyledElement.allowsHitTesting` (with the remedy: write the scope last)
  and `registerAndScope` now say the scope is per layer.

**Minor 1 — "hover follows the hitbox" was unpinned.** Now
`aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse`: two arms under one
`mouseMoved` over a 40x40 `Box().background(.surface).hoverBackground(.accent)
.onClick { }`; the control `#require`d to paint `.accent`, the scoped arm
asserted `.surface`. The `isActive` half of the sentence is marked by reading,
unpinned, in the doc comment (nothing paints a pressed state).

**Minor 2 — the display-lock reading below is stale.** `ioreg` read
`<true/>` at 23:50:41 and 00:00:01 (the verifier) and again at **00:03:44 PDT
2026-09-16** (this round); the `<false/>` at 23:33:05 was a window, not a
state. Lane 4 re-reads the lock before attempting `screencapture -R`.

**Minor 3 — the matrix carries legacy rows only.** Spec §3.2 now says so and
names the proposal-path pins for `allowsHitTesting`
(`allowsHitTestingFalsePreventsDescendantOnTapDispatch`,
`aPressIsRefusedWhereHitTestingIsDisabled`); adding a proposal-row shape to
the instrument is left to the integration step, as the verifier suggested.

**Mutations of the round — three, applied singly, run filtered over
`HitRegionTests|OuterModifierMatrixTests|ModifierTests` plus
`clippedAlsoClipsTheHitboxesInsideIt`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`,
`aPressIsRefusedWhereHitTestingIsDisabled` and
`allowsHitTestingFalsePreventsDescendantOnTapDispatch` (21 tests), reverted
from a `cp` backup, `git diff -- Sources | grep -c MUTATION` = 0 after.**

| # | mutation | reddened (issues) |
|---|---|---|
| MA | **the candidate fix**: `ModifiedElement.prepaint` opens `pass.allowsHitTesting(false)` around the whole chain when any layer, or the content read through `as? any StyledElement`, has the flag off | `anInnerLayersAllowsHitTesting…`'s `#require(x1 != x2)` **alone** — 1. The only test in the suite that sees the fix; test 1's N1/N2 both stay on one layer and cannot |
| MB | `registerAndScope` registers the receiver OUTSIDE the scope and scopes the children only (the verifier's V1) | 12: test 1 N1, test 2 ×4, test 2a ×4, the matrix row, **the new hover test's scoped arm** (`:824`, the control is hovered and so is the scoped arm), and the new X test's `x1 != x2` (both orders now register the outer hitbox) |
| MC | `Box.prepaint` forces `allowsHitTesting = true` (the verifier's V4 at the `Box` site) | 6: test 1 N1 and child, test 2 `Box`, test 2a `Box`, the matrix row, **the hover test's scoped arm** |

MB and MC together say the hover test measures the scope through the `Box`
site's registration and not a pointer that never arrived; MA says the X test
is the one instrument for the layer-crossing rule.

##### Counts, re-taken after the review round

| reading | value | against `e1c33b5` |
|---|---|---|
| `swift test --build-system native --no-parallel` (after `swift build --build-system native --build-tests`) | `Test run with 1269 tests in 1 suite passed after 40.034 seconds.` (and 39.302 s on the first run of the re-verification, before the mutation round) | **+2** on 1267: the `OM-AL` pin and the hover pin, both in `HitRegionTests.swift` |
| `error:` / `warning:` | **0** / **1** — SwiftPM's own `--build-system native` deprecation notice | unchanged |
| skipped | the two gated tests only (`grep -i skipped` also matches two test *names*, `displayNoneChildrenAreSkipped…` and `skippedFrameKeeps…`, which passed) | unchanged |
| `find Tests -name "*.json" \| wc -l` | **97**; `git diff --stat c4b5853 -- Tests` lists no `.json` | unchanged |
| guards, `grep -c canTypecheck` per file | 19 / 10 / 5 / 6 / 2 / 6 / 8 / 3 / 3 / 3 = **65 hits, 64 guards** | unchanged; the round adds no guard |
| `grep -c "public func" Sources/MetalUI/Box.swift` | **50** | unchanged |
| `ModifierTests`' `cases.count` tripwire | **47** | unchanged |
| `grep -cE "sleep" Tests/MetalUITests/HitRegionTests.swift` | **0** | unchanged |
| `swiftui-content-shape-hit-region.swift` under `/usr/bin/swift` | exit 0; all **18** arm lines (H0–H6, P1–P5, N1–N2, X0–X3) byte-identical to the header, re-run 2026-09-16 00:10 PDT | X0–X3 new |

**Re-verification, 2026-09-16 00:05–00:15 PDT, on the fixed tree.** The
review-round agent was cut off after writing the fix and before running the
suite (this table was a placeholder in its uncommitted tree); the re-verifier
took every reading above, re-ran the probe, and re-applied MA, MB and MC from
a `cp` backup with the same 21-test filter, each restored byte for byte
(`cmp` against the backup; `git diff -- Sources | grep -c MUTATION` = 0):

| # | reddened (issues) | as the table above predicted |
|---|---|---|
| MA | **1**: `anInnerLayersAllowsHitTesting…` `:765`, the `#require(x1 != x2)` | yes — alone |
| MB | **12**: test 1 `:188`, test 2 ×4 `:254`, test 2a ×4 `:305`, matrix `:697`, hover `:824` (`#expect(scoped == "surface")`), X test `:765` | yes |
| MC | **6**: test 1 `:188` and `:218`, test 2 `:254`, test 2a `:305`, matrix `:697`, hover `:824` | yes |

The display lock, re-read for minor 2: `<false/>` at **00:10:11** and again at
**00:13:24 PDT** — so it flips on this machine within minutes (`<true/>` at
23:50, 00:00 and 00:03; `<false/>` at 23:33, 00:10 and 00:13). Lane 4 reads
it immediately before each `screencapture -R`, not once.

##### Verifier's verdict, 2026-09-16 ~04:03 PDT, at `641c91c` — **ok**, one minor

Quoted from the verifier's report; this is the verdict for the lane **after**
its review round (the fixed tree), and it is the first verifier verdict on
this branch that survives verbatim.

**Suite.** `Test run with 1269 tests in 1 suite passed after 47.111 seconds.`
— unfiltered `swift test --build-system native --no-parallel` after `swift
build --build-system native --build-tests`; 0 `error:`, the one `warning:`
SwiftPM's `--build-system native` deprecation notice; only the two gated tests
skipped; 97 goldens, no `.json` in `git diff --stat c4b5853 -- Tests`;
`Sources/MetalUIDemo` byte-identical to `c4b5853`. **The extended collision
guard demonstrably ran**: its `crossedShape` diagnostic is in the log. Both
SwiftUI probes re-run under `/usr/bin/swift` at 04:03 PDT, exit 0, all 18
hit-region arms (H0–H6, P1–P5, N1–N2, X0–X3) and all 7 side-effect lines
identical to their headers. Display lock read `<true/>`.

**Mutations — seventeen, every one reddened what was expected.** Line numbers
are the verifier's, in `HitRegionTests.swift` unless another file is named.

| # | mutation | reddened |
|---|---|---|
| V1 | `registerAndScope` registers the receiver OUTSIDE the pointer-disable scope and scopes the children only (the first draft's mechanism) | `allowsHitTestingFalseRemovesTheRECEIVERSOwnPointerTarget…` (`:188`, N1; the child arm stays green), `everyHandlerRegisteringSiteHonoursAllowsHitTesting` (`:254` ×4), `everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload` (`:305` ×4), the matrix (`OuterModifierMatrixTests.swift:697`), `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse` (`:824`), `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt` (`:765`, the `#require(x1 != x2)`) |
| V2 | `Frame.hitRegion` ignores the inset (returns `bounds`) | `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout` (`:386`), `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` (`:479`), `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration` (`:520`), `aContentShapeWithoutAClickHandlerRegistersNothing` (`:569`), the matrix (`:697`) |
| V3 | `Frame.hitRegion` clamps each negative inset at 0 | `aNegativeContentShapeInset…` (`:479`, the `#require` that the arms disagree) — **alone** |
| V4 | `Frame.hitRegion` subtracts `left` twice (right ignored) | `aContentShapeInsetShrinks…` (`:422`, the per-edge arm's region) — **alone**; the uniform arm cannot see it (the lane's M12, confirmed) |
| V5 | `focusRegistry.register` gated on `hitTestingDisabledDepth == 0` (the scope reaches the keyboard) | `allowsHitTestingFalseRemoves…` (`:191` N1 keyboard, `:221` child keyboard) — **exactly the two keyboard assertions** (the lane's M3, confirmed) |
| V6 | `Text.prepaint` forces `handlers.allowsHitTesting = true` before `registerAndScope` | `everyHandlerRegisteringSiteHonoursAllowsHitTesting` (`:254`, `Text` arm), `…StillPublishesItsAccessibilityPayload` (`:305`, `Text` arm) |
| V7 | `Stack.prepaint` forces the flag true | the same two, `Stack` arm |
| V8 | `ModifiedElement.prepaintLayerBody` forces the flag true per layer | `…HonoursAllowsHitTesting` (`:254`, inner-layer arm), `…StillPublishesItsAccessibilityPayload` (`:305`, outermost-layer arm), `anInnerLayersAllowsHitTesting…` (`:765` — X2 now registers too, so `x1 == x2`) |
| V9 | `contentShape(inset: Pixels)` writes nothing | `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (`ModifierTests.swift:403`), the matrix (`:660`), tests 3, 4, 5, 6a (`:386`, `:479`, `:520`, `:569`) |
| V10 | `allowsHitTesting(_:)` writes nothing | `ModifierTests.swift:403`, the matrix (`:660`), test 1 (`:188`, `:218`), test 2 (`:254` ×4), test 2a (`:305` ×4), the hover pin (`:824`), the X test (`:765`) |
| V11 | **the NEW guard fixture**: a `contentShape(inset:)` declared on `extension ProposalElementGroup` | `theLegacyAndProposalDecorationModifiersDoNotCollide` (`DecorationCompileGuards.swift:211`, `both.succeeded != crossedShape.succeeded`; log shows `crossedShape succeeded=true`) — **proves the extended typecheck guard runs in this worktree** |
| V12 | `registerScrollRegion` consults `hitTestingDisabledDepth` (the `OM-AK` fix) | `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered` (`:620`, `:623`) — both scoped-arm assertions, **alone** |
| V13 | `registerHandlers` inserts a hitbox when `contentShapeInset != nil` even with no `onClick` | `aContentShapeWithoutAClickHandlerRegistersNothing` (`:560`) — **alone** |
| V14 | the inset applied at the call site (`registerAndScopeBody` insets `bounds`; `insertHitbox` gets bare bounds) — moves focus/AX with it | `aContentShapeMovesNeither…` (`:525` emitted `AXNode` frame, `:530` client record geometry) — **alone**; test 3 stays green as the spec predicted (the lane's M6, confirmed) |
| V15 | the `hitTestingDisabledDepth == 0` gate removed from `Frame.registerHandlers` | test 1 (`:188`, `:218`), test 2 (`:254` ×4), test 2a (`:305` ×4), the hover pin (`:824`), the X test (`:765`), the matrix (`:697`), **`aPressIsRefusedWhereHitTestingIsDisabled`** (`AccessibilityTreeTests.swift:471-473`), **`allowsHitTestingFalsePreventsDescendantOnTapDispatch`** (`NativeLayoutIntegrationTests.swift:985`, `:991`) — the two proposal-path pins spec §3.2 names, seen by a legacy mutation because the gate is shared |
| V16 | `contentShape(inset: Edges)` transposes top and bottom | `ModifierTests.swift:403`, `aContentShapeInsetShrinks…` (`:422` per-edge region, `:433` top-edge click) |
| V17 | `Frame.hitRegion` moves the origin by the inset but does not shrink the height | `aContentShapeInsetShrinks…` (`:391`, `:422`, `:435`), `aNegativeContentShapeInset…` (`:484`, `:493`, `:497`), `aContentShapeMovesNeither…` (`:520`), `aContentShapeWithoutAClickHandler…` (`:569`) |

Read against the lane's own table: V1/V5/V4/V14 reproduce M1/M3/M12/M6 with
the same "alone" shapes, which is the differential the lane claimed; V11 is
new and is the one mutation that establishes the guard ran here rather than
skipped; V15 is new and shows the legacy and proposal `allowsHitTesting` share
one gate in `Frame.registerHandlers` — a mutation there reddens both paths'
pins.

**Minor — `contentShape(inset:)` written before a wrapping modifier, with the
`onClick` after it, is silently dropped, and nothing says so.** The verifier's
scratch test (deleted; worktree clean) through a real `Window` over
`FakePlatformWindow`, 200x200, at `641c91c`:

| chain | registered region | (5, 60) | (60, 60) |
|---|---|---|---|
| `Box().width(100).height(100).contentShape(inset: 20).padding(10).onClick {}` | `[0 0 200x200]` | **hits** (1) | 2 |
| `…​.padding(10).contentShape(inset: 20).onClick {}` | `[20 20 160x160]` | misses (0) | 1 |

The inset lands on the inner layer's `Handlers`, which has no `onClick` and so
registers nothing (`OM-AB`), while the outer layer registers its whole frame
(`OM-I`). It is `OM-AL`'s layer-crossing shape one modifier over and the
mechanism `OM-AB` + `MC-A` already imply; but unlike `allowsHitTesting` after
the review round, neither `StyledElement.contentShape(inset:)`'s doc nor
`Handlers.contentShapeInset`'s names the order, no test pins the two orders,
and **SwiftUI's answer for the chain is unprobed** — the probe's X arms cover
`allowsHitTesting` only. The verifier offered two dispositions: a doc sentence
plus a `#require`-disagree pin beside
`anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt` and a
probe arm (`colour.contentShape(Rectangle().inset(by: 20)).padding(10)
.onTapGesture` vs the reverse), or carrying it as "unprobed". **The record pass
carries it** (see "For the integrator", open items): it is a doc sentence and
a test in a merge-collision file (`Box.swift`, `Handlers.swift`), the row can
only be classified as agreement or divergence once the probe arm is run, and no
false claim stands meanwhile — the modifier's doc says the inset is applied at
one site to the bounds `registerHandlers` hands `insertHitbox`, which is
exactly what happens on each layer.

#### Lane 4 — `Component` padding wraps, and the verification

**Commits.** `5cadec0` (red-first: the seven rows' tests, the exit test, the
matrix row's two kinds and the animation arm's re-specification, with the 21
red issues in the message), `367de92` (the lane: `Component.swift` only), then
this record with `OM-AM`, the spec's built notes, and five stale doc comments.

**A continuation, second time.** The run that began the track stopped at
2026-09-15 21:46 PDT mid-lane 3; lane 3 was finished and reviewed by a
continuation (`641c91c`). This lane started 2026-09-16 04:1x PDT on a clean
worktree at `641c91c` with nothing uncommitted.

##### What was built, and the two places it departs from the spec

`ComponentModifierOp` (`.amend(@Sendable (inout Style) -> Void)`, `.wrap(Style)`)
and `StyledComponent.ops: [ComponentModifierOp]` replacing `amend`.
`requestGroupLayout` forwards `parent` and `cursor` unchanged, then maps each
returned node through the ops in order with a current node: an amend reads,
amends and sets the current node's `Style`; a wrap registers
`pass.requestNode(style:children: [current])` and replaces it. `Component.padding`
contributes `.wrap(paddingWrapperStyle(points))`, where `paddingWrapperStyle`
is `Style()` with `padding` set — the `Style` `StyledElement.padding` gives a
`ModifierLayer` (`Box.swift`); `width`/`height` contribute `.amend`
(`OM-F`); `StyledComponent`'s three append. No new precondition (`OM-Z`).
`Component.swift` is the only source file the lane commit touches.

1. **The exit test drives `StyledComponent.requestGroupLayout` directly, not
   under a `Column`** (spec row 1a says "the route through `StyledComponent`"
   and the `.amend` pin beside it uses a `Column`). A `Column` traps at its own
   `newNode` with the SAME "given a native child" fragment once its content
   returns, so a `.padding` that did nothing would still pass on the fragment.
   With the direct call (`LayoutPass(frame:)`, `@testable`) the wrap's
   registration is the only legacy `newNode` in the process; red-first it
   trapped at `setStyle` (the amend), and M2 makes it exit 0.
2. **The matrix instrument's `distributes` witness branches** (`OM-AM`). Lane
   1's witness — each member's own SIZE changes, `OM-AD` — is an amend's; a
   per-member wrap leaves the size unchanged by construction and adds a node
   per member, so the red-first run failed the lane's own deliverable on
   `nodeDelta == 0` and `pair.0 != pair.1`. The Component `padding(_:)` row now
   claims `[.distributes, .wraps]`: exactly `memberCount` new nodes, member
   sizes unchanged, and the `wraps` witness's bigger outer box. The spec's
   lane-1 note "the kind does not change, the numbers do" was wrong on the
   kind.

The seventh row's arm (`everyRegisteringSiteAnimatesItsStyle`, Component)
reads the wrapper `group` returns and the member as its only child through
`pass.frame.tree.children`, `#require`ing exactly one of each; the readings
moved from one node's (320, 80, 20) to the wrapper's `padding.left` 20 and the
member's (320, 80), at both samples — B-7 unchanged.

##### The red run

`swift test --build-system native --no-parallel --filter` over the ten named
tests, against the source at `641c91c` (8 failed, 2 passed, 21 issues; the
full list is in `5cadec0`'s message):

```
everyRegisteringSiteAnimatesItsStyle       AnimationTests.swift:1025  wrapperAndMember(...) != nil
aModifierOnAComponentDistributesToEachTopLevelChild  ComponentTests.swift:602/613/617
    nodes 3 against 3; a (0.0, 26.0, 8.0, 8.0); b (8.0, 26.0, 8.0, 8.0)
chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement  :849  four.x != eight.x — both (x: 0.0, nodes: 3)
aComponentsPaddingWrapsEachTopLevelNode    :952/954/956/965/967/972
    SoloText padded (13.0, 16.0, nodes 3) = bare — inert; Solo padded (40.0, 40.0); leaf (0, 0, 40, 40)
aTwoMemberComponentsPaddingIsAppliedToEachMember  :1007/1008/1010/1011
    a (0, 0, 30, 16); b (38, 0, 50, 16); outer 88; nodes 4 against 4
aModifierOnAComponentAppliesInTheOrderItIsWritten  :1054  the two orders read identically
aPaddingModifierOnAProposalComponentTraps  NativeBoundaryIntegrationTests.swift:117
    stderr.contains("given a native child") — trapped at setStyle instead
everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays
    OuterModifierMatrixTests.swift:669 nodeDelta > 0; :722 nodeDelta == members; :727 pair.0 == pair.1 (x2)
addingAModifierDoesNotResetAComponentsState            passed
aComponentsWidthStillOverwritesItsMembersDeclaredWidth passed
Test run with 10 tests in 0 suites failed after 0.297 seconds with 21 issues.
```

The 13x16 in `aComponentsPaddingWrapsEachTopLevelNode` is the system font's
`Text("Hi")` on this machine — the same 13x16 the design session's scratch T1
read and SwiftUI's G10 reads — and the red run confirms it: the bare arm
already read (13.0, 16.0) before the lane, and the padded arm read the same,
which is the inertness the spec's §4.4 first row describes.

##### Mutations — eight, applied singly by script, restored from a `cp` backup after `367de92`

Run filtered over `ComponentTests`, the two boundary-trap pins, the direct
`newNode` pin, the animation guard, the matrix and
`legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes` (32 tests); after each,
`git status --short` read 0 dirty files.

| # | mutation | reddened (issues) |
|---|---|---|
| M1 | `.wrap` re-implemented as `.amend { $0.padding = … }` at both padding sites — the spec's named mutation for row 1 | **8 tests, 21 issues: the red-first reading exactly** — the animation arm's `#require`, `aModifierOnAComponentDistributesToEachTopLevelChild` ×3, the chain test's `#require`, `aComponentsPaddingWrapsEachTopLevelNode` ×6, `aTwoMemberComponentsPaddingIsAppliedToEachMember` ×4, the order test's `#require`, the exit test's fragment, the matrix ×4 |
| M2 | `LayoutTree.newNode`'s native-child precondition deleted — row 1a's named mutation | **3 tests, 6 issues**: `aPaddingModifierOnAProposalComponentTraps` and `aNativeNodeRegisteredUnderALegacyNodeTraps`, each on both its exit expectation (`EXIT_SUCCESS` reported) and its fragment — the two the ruling predicted — **and `aProposalElementInsideALegacyContainerTrapsAtRegistration`** (`NativeBoundaryIntegrationTests.swift:48/57`), which pins the same precondition through a `Column`. *Corrected by the lane's verifier (2026-09-16): the implementer's filter named three tests rather than the file and could not see the third; the verifier's run (`mut-M2.log`) reads 3 tests, 6 issues at `NativeBoundaryIntegrationTests.swift:48, :57, :106, :117` and `NativeBoundaryTrapTests.swift:47, :54`. This row first read "2 tests, 4 issues … and no other".* |
| M3 | only the last op applied (`ops.suffix(1)`) — row 2's | **4 tests, 9 issues**: the chain test's `chain.x == 12` and `+4` nodes, the order test's three pins (its `#require` stays green: one op each still differs), the animation arm's member half ×2, and `widthAndHeightComposeOnAChainedModifier` ×2 |
| M4 | one wrapper around the member LIST instead of one per member — row 3's | **4 tests, 8 issues**: `aTwoMemberComponentsPaddingIsAppliedToEachMember`'s `b`, outer 120 and `+2` nodes; the distributes test's `+2` and `b`; the chain test's two node counts; the matrix's `nodeDelta == members` (`OM-AM`'s branch, alone in the matrix) |
| M5 | every amend applied before every wrap — row 4's | **1 test, 1 issue**: `aModifierOnAComponentAppliesInTheOrderItIsWritten`'s `#require` that the two orders disagree. Nothing else in the 32 sees order, which is what the row predicted |
| M6 | `StyledComponent` mints an id and hands it down as the parent — Step 8's, row 5's | **1 test, 1 issue**: `addingAModifierDoesNotResetAComponentsState` (reads 1, not 3) — exactly, as the `Component` milestone recorded |
| M7 | lane 4 reverted (`git show 5cadec0:Sources/MetalUI/Component.swift`) — row 7's | **8 tests, 21 issues**, the same list as M1 |
| M8 | the wrapper registered but the MEMBER returned as outermost (`_ = pass.requestNode(...)`) — not in the spec; added because M1 and M4 both move the node count, and this one does not | **7 tests, 13 issues** (*first written "6 tests"; the list that follows is seven, and the verifier's `mut-M8.log` reads seven*): the animation `#require`, the distributes test's `a`/`b`, the chain `#require`, test 1's four geometric assertions (its node counts stay green — the node IS registered), test 3's `a` and outer, the order `#require`, and in the matrix **only `outerSizeDelta > 0`** — the `wraps` witness, which is why the row claims two kinds |

##### What the mutations found

- **M5 reddening one assertion is the point, not a gap**: order is observable
  only where an amend and a wrap meet on one member, and the suite has one
  such fixture on purpose. A second one would be the same test.
- **M8 says the matrix row's two kinds are both load-bearing.** With
  `distributes` alone (even branched), a wrapper that is registered and
  discarded reads `nodeDelta == members` and unchanged sizes — green. The
  `wraps` witness's `outerSizeDelta > 0` is what sees it.
- **M3 reaches `widthAndHeightComposeOnAChainedModifier`**, a Component-milestone
  test that never knew about ops: two amends are two ops, and dropping all but
  the last drops the width. The old amend-closure composition had the same
  property under a different mutation ("drop `previous`"), which that test's doc
  still describes; it holds for the list too.

##### Counts, re-taken at `367de92`

| reading | value | against `641c91c` |
|---|---|---|
| `swift test --build-system native --no-parallel` (after `swift build --build-system native --build-tests`) | `Test run with 1274 tests in 1 suite passed after 38.749 seconds.` (and 38.472 s re-run on the tree with the doc-comment corrections below, 0 issues) | **+5** on 1269: `aComponentsPaddingWrapsEachTopLevelNode`, `aTwoMemberComponentsPaddingIsAppliedToEachMember`, `aModifierOnAComponentAppliesInTheOrderItIsWritten`, `aComponentsWidthStillOverwritesItsMembersDeclaredWidth`, `aPaddingModifierOnAProposalComponentTraps`; `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement` replaces `chainedPaddingReplacesRatherThanAccumulates` one for one |
| `error:` / `warning:` | **0** / **1** — SwiftPM's own `--build-system native` deprecation notice | unchanged |
| skipped | the two gated tests only | unchanged |
| `find Tests -name "*.json" \| wc -l` | **97**; `git diff --stat c4b5853 -- Tests` lists no `.json` | unchanged — `Component.swift` is outside `Sources/MetalUILayout/` (`OM-Q`) |
| guards, `grep -c canTypecheck` per file | 19 / 10 / 5 / 6 / 2 / 6 / 8 / 3 / 3 / 3 = **65 hits, 64 guards** | unchanged; the lane adds no guard |
| `grep -c "public func" Sources/MetalUI/Box.swift` | **50** | unchanged |
| `ModifierTests`' `cases.count` tripwire | **47** | unchanged |
| `grep -c sleep` over the two test files touched | **0** / **0** | — |
| exit tests | one new, `#expect(processExitsWith: .failure)` with its fragment | — |

##### The demo and the preview: 0 differing pixels in all ten, scene dumps identical, and the instrument that says what the zero can and cannot see

**Display state.** `ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` read
**`<true/>`** at **2026-09-16 04:30:10 PDT** and again at **04:35:54 PDT**
and **`<true/>`** at **2026-09-16 04:38:03 PDT**, the lane's last reading. No real-window `screencapture -R` was
attempted, no demo was launched and no input was sent. The offscreen
comparison is the primary evidence (`OM-AC`).

**Method, record §13's and lane 2's, with the scene dump added.**
`git archive c4b5853` and `git archive 367de92` into two scratch directories
(`Sources/MetalUIDemo` is byte-identical between them: `git diff --stat
c4b5853 -- Sources/MetalUIDemo` is empty). In each, a generated
`Tests/MetalUITests/ZZSnapshotHarness.swift` holds that tree's `main.swift`
up to `func runDemo()` — thirteen top-level types prefixed `SI`, the seven
top-level globals `nonisolated(unsafe)` — and one test that renders through a
real `Window` over `FakePlatformWindow` at 1024x1024, scale 1, and writes both
`fakeSurface.readPixels()` and `String(describing: window.lastScene)` (9.2 MB
per default-demo frame, 64 KB per preview frame). The generated file is
byte-identical in the two trees (`cmp`). Ten images per tree, debug builds:
`demoContent()` light and dark at frame 0 and after three ticks, the modal
(`showModal = true`) light and dark, the settled animation look
(`animationDemoActive = true`, no transaction) light and dark, and
`nativeLayoutPreviewContent()` light and dark. Frame 0 emits 518 rects (520
with the modal), the preview 16 — record §13's counts.

| comparison | differing pixels | scene dump |
|---|---|---|
| control: base light vs base dark | 1 048 576 (all) | differs |
| control: base default vs base modal | 1 030 498 | differs |
| control: base default vs base animation look | 210 027, bbox (16, 113)–(981, 1007) | differs |
| control: base frame 0 vs base frame 3 | 0 | identical |
| **base `c4b5853` vs lane 4 `367de92`, all ten images** | **0** | **identical, all ten** |
| instrument A: `367de92` with the COMPONENT wrapper's padding doubled (`paddingWrapperStyle`) | **0, all ten** | identical |
| instrument B: `367de92` with the ELEMENT path's `padding(_ points:)` doubled (`Box.swift`) | default 402 223 light / 402 218 dark, modal 395 220 / 395 199, animation 414 103 / 414 100, bbox (16, 16)–(1007, 1007) each; **preview 0** | differs (preview identical) |

**Reading.** Lane 4 renders the default demo, the modal, the settled animation
look and the proposal preview byte-identical to `c4b5853` in both themes, in
pixels and in emitted primitives. **Instrument A is the honest half of the
claim**: the harness cannot see this lane's code path at all, because the demo
constructs no `StyledComponent` — `grep -n "PreviewToggle()"
Sources/MetalUIDemo/main.swift` reads one hit, line 1017, bare, the premise
`OM-Z` re-derived the zero on; and `grep -rnE "\.(border|hoverBorder|focusBorder|opacity|clipped|allowsHitTesting|contentShape)\("
Sources/MetalUIDemo` reads five hits, all in the proposal preview and all
`ProposalElementGroup`'s. So the ten zeros are a regression check that lane 4
moved nothing ELSE, not evidence about the wrap. Instrument B is the control
for the harness itself: a padding change on the element path moves ~400 000
pixels in every legacy image and none in the preview, so a legacy-path
regression would have been seen.

**Not covered**, unchanged from record §13 and lane 2: the drawable, the
display's colour space, the real 920x560 window and AppKit appearance, anything
input-, focus-, hover- or scroll-driven, a mid-flight animation, and a release
build. The release-window captures stay owed, by `MC-J`'s method, on an
unlocked session.

**No deliberate demo change.** The focus ring stays opt-in (lane 2), and no
`Component` in the demo carries a modifier. If a reviewer wants either seen on
screen, it is a separate commit whose diff is the demo file alone (spec §7 lane
4, step 3).

##### Stale doc comments corrected

Five, each of which described `Component` padding as an amend: `Frame.setStyle`
("distributes by amending … rather than by wrapping"), `LayoutPass.style`'s
narrowing note, `ProposalNodeID.swift`'s hole 5 (now names both traps and both
pins), `LayoutTree.setStyle` ("the reachable route"), and in `ComponentTests`
the distributes test's "not reproducible as a literal number here" (G2's 120x26
now is, literally) and `TwoAutoLeaves`' discriminator. `Component.swift`'s own
type doc was rewritten in the lane commit: the "padding on a single-leaf
component is completely inert" paragraph is gone, the chained extension's "not
accumulation" is inverted with the probe cited, and the B-7 measurement is
re-stated on two nodes. `AnimationTests`' Component arm no longer names
`chainedPaddingReplacesRatherThanAccumulates`; `OuterModifierMatrixTests`'
element-half doc points at the replacement.

##### Hazards the lane leaves for the integration step

- **CLAUDE.md's `Component` paragraph is stale in three sentences**: "chained
  `.padding` replaces rather than accumulates" (now accumulates, `OM-E`);
  "`.padding()` on a single-`Text` component is inert while that leaf is
  content-sized" (now 13x16 → 53x56, `OM-D`); and the inert table's row
  "…and a `Component`'s distributed `.padding`: ignored on a content-sized
  leaf" (the distributed `.padding` no longer writes `Style.padding` at all).
  "`width`/`height` overwrite" stays true (`OM-F`).
- **CLAUDE.md's animation section**: "A caller's modifier on a `Component`
  always snaps … `MyComponent().width(196)` → `.width(320)` … reads 320 at
  t = 0 and t = 0.5" stays true; its `padding` example now reads on the wrapper
  node (20 at both samples) rather than on the member.
- **`ProposalNodeID.swift`'s hole 5 is closed at run time by two traps**, both
  pre-existing (`OM-Z`); the modifier-composition decisions doc's "task 5"
  assignment is discharged.
- **`OM-AM` changes what the matrix's `distributes` kind means for a row that
  also claims `wraps`**; if task 4 makes `width`/`height` wrap per member, those
  two rows add `.wraps` and move to the same branch.
- **`Component.swift` still contains the literal `// MUTATION`** in the
  Component-milestone comments (lane 3's note); this lane's mutation script
  verified reverts by `git status --short` and `cp` backups, not by grepping
  `Sources/`.

##### Verifier's verdict, 2026-09-16, at `2fb0800` — **ok**, two doc-only minors (both applied above)

Quoted from the verifier's report.

**Suite.** `Test run with 1274 tests in 1 suite passed after 38.457 seconds.`
— `swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`; 0 `error:`, the only `warning:` line
SwiftPM's own `--build-system native` deprecation notice; the two gated tests
skipped as usual; `.build/<triple>/debug/Modules` present, so the guards ran.
Goldens unchanged.

**Mutations — the lane's eight re-run (M1–M8), two of the verifier's own
(M9, M11; the verifier's numbering has no M10), and one instrument on the
demo harness. Every one reddened what was expected.**

| # | mutation | reddened |
|---|---|---|
| M1 | `.wrap(paddingWrapperStyle(points))` re-implemented as `.amend { $0.padding = Edges(all: .pixels(points)) }` at both `Component.swift` padding sites (the spec's row-1 mutation) | `aComponentsPaddingWrapsEachTopLevelNode`, `aModifierOnAComponentAppliesInTheOrderItIsWritten`, `aModifierOnAComponentDistributesToEachTopLevelChild`, `aPaddingModifierOnAProposalComponentTraps`, `aTwoMemberComponentsPaddingIsAppliedToEachMember`, `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement`, `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays`, `everyRegisteringSiteAnimatesItsStyle` — 8 tests, the lane's list |
| M2 | `LayoutTree.newNode`'s native-child `for child in children { precondition(...) }` deleted (row 1a's) | `aPaddingModifierOnAProposalComponentTraps`, `aNativeNodeRegisteredUnderALegacyNodeTraps`, **and `aProposalElementInsideALegacyContainerTrapsAtRegistration`** — 3 tests, 6 issues (the lane's row said 2 / 4 "and no other"; corrected above and in `OM-Z`'s built note) |
| M3 | only the last op applied (`for op in ops.suffix(1)`) | `aModifierOnAComponentAppliesInTheOrderItIsWritten`, `chainedPaddingAccumulatesOnAComponent…`, `everyRegisteringSiteAnimatesItsStyle`, `widthAndHeightComposeOnAChainedModifier` — 4 tests, the lane's list |
| M4 | one wrapper around the member LIST instead of one per member (amends still per member) | `aModifierOnAComponentDistributesToEachTopLevelChild`, `aTwoMemberComponentsPaddingIsAppliedToEachMember`, `chainedPaddingAccumulatesOnAComponent…`, the matrix — 4 tests, the lane's list |
| M5 | every `.amend` applied before every `.wrap` (`amends + wraps`) | `aModifierOnAComponentAppliesInTheOrderItIsWritten` — **alone**, as the lane recorded |
| M6 | `StyledComponent.requestGroupLayout` mints `GlobalElementID.child(of: parent, at: cursor, name: nil)` and hands it down as the parent (Step 8's) | `addingAModifierDoesNotResetAComponentsState` — **alone**, as the lane recorded |
| M7 | lane 4 reverted: `git show 5cadec0:Sources/MetalUI/Component.swift` under HEAD's tests (red-first reproduction) | the same 8 as M1 |
| M8 | wrapper registered but the MEMBER returned as outermost (`_ = pass.requestNode(...)`) | `aComponentsPaddingWrapsEachTopLevelNode`, `aModifierOnAComponentAppliesInTheOrderItIsWritten`, `aModifierOnAComponentDistributesToEachTopLevelChild`, `aTwoMemberComponentsPaddingIsAppliedToEachMember`, `chainedPaddingAccumulatesOnAComponent…`, the matrix (**only `OuterModifierMatrixTests.swift:671 outerSizeDelta > 0`** — the `wraps` witness, confirming the row's second kind is load-bearing), `everyRegisteringSiteAnimatesItsStyle` — **7 tests**, 13 issues (the lane's row said 6; corrected above) |
| M9 (verifier's) | `paddingWrapperStyle` returns a bare `Style()` — a wrapper with zero padding | the same 7 as M8 — 7 tests, 16 issues |
| M11 (verifier's) | ops applied to the FIRST member only (`index == 0 ? ops : []`) | `aComponentsWidthStillOverwritesItsMembersDeclaredWidth`, `aModifierOnAComponentDistributesToEachTopLevelChild`, `aTwoMemberComponentsPaddingIsAppliedToEachMember`, `chainedPaddingAccumulatesOnAComponent…`, the matrix, `heightAloneDistributesToEachTopLevelChild`, `widthAloneDistributesToEachTopLevelChild`, `widthAndHeightComposeOnAChainedModifier` — 8 tests, 13 issues. **This is `OM-AD`'s M9 re-run on the wrap**: lane 1's position-reading witness could not see a first-member-only amend; the size-reading witness and the per-member node count both can |
| demo instrument B (verifier's own harness, a scratch copy of `2fb0800`) | element-path `padding(_ points:)` doubled in `Box.swift`; eight 1024x1024 offscreen images through a real `Window` over `FakePlatformWindow` | default-light **402 223** px, default-dark 402 218, modal-light 395 220, modal-dark 395 199, anim-light 414 103, anim-dark 414 100, **preview-light 0, preview-dark 0** — the lane's instrument B reproduced independently, to the pixel on the light default and within 5 px elsewhere |

**Issues.** Both doc-only, both applied in this record pass: the M2 row's
"2 tests, 4 issues … and no other" is "3 tests, 6 issues" naming
`aProposalElementInsideALegacyContainerTrapsAtRegistration`
(`NativeBoundaryIntegrationTests.swift:48/57`), in the row above and in `OM-Z`'s
built note; the M8 row's "6 tests" is "7 tests" (the list it gives is seven
and the run reads seven).

---

### Carried into the integration step (the lanes' running list)

*Written by the lanes as they ran; "For the integrator" below is the
consolidated version and, where the two differ, the later one.*

- **Ten** divergence rows with no numbers yet: the default hit region
  (`OM-I`), a padded click target (`OM-K` — and its order-sensitivity, which
  SwiftUI's P1/P2 do not have), **a grown content shape bounded by an
  ancestor's clip where SwiftUI's hits through it (`OM-AJ`, lane 3)**, **an
  inner layer's `allowsHitTesting(false)` not reaching a click on a layer
  written after it, where SwiftUI's two orders both read 0 / 0 (`OM-AL`, lane
  3's review round; `OM-I` seen across a layer, probe arms X0–X3)**,
  `.opacity` reaching a later background (`OM-N`),
  **a second `.opacity` on one element REPLACING the first where SwiftUI's two
  calls multiply (`OM-AH`, the review round)**,
  `.cornerRadius` not clipping (`OM-G`), a `Component`'s `width`/`height`
  overwriting (`OM-F`), **`.border.cornerRadius` following the arc where
  SwiftUI's clipped square border does not (`OM-W`, round 2)**, and **`.opacity`
  answering differently on the legacy and proposal paths (`OM-AA` a, round 2)**.
  **The highest number allocated in `docs/record/04-divergences.md` today is 34,
  not 29** (round 2, critic finding 5): `grep -oE "^\| [0-9]+ \|"` runs 20…34
  under "2026-09-15: divergences 20–34 (tasks 3, 9 and 12, integrated)".
  **Next free: 35.** The wrong figure appeared in three places and is corrected
  in all three.
- **Divergence 15 is RETIRED** (`OM-U`, round 2) — **done in lane 2**
  (`c624d13` inverted the test, `9f37d10` added the term).
  `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` keeps its name
  deliberately, because CLAUDE.md, record §04 and the spec all cite it; every
  expectation in it is inverted and its doc says which answer it now asserts.
  Retiring the row from `CLAUDE.md` and `docs/record/04-divergences.md` is the
  integration step's.
- `CLAUDE.md`'s declared-but-inert table loses its `borderWidth(_:)` row
  (`OM-M`, **done in lane 2**) and its `MUIRect.borderColor`/`borderWidths` row
  becomes "reachable through `Decoration.border`/`hoverBorder`/`focusBorder` on
  the legacy path and `.border` on the proposal one". `CLAUDE.md`'s **focus**
  sentence also moves: "nothing above the renderer can draw a border
  (`Frame.fill` hard-codes zero widths)" is false as of lane 2, and
  `focusBorder(_:width:)` is the ring. So is the animation section's
  "`Text`'s glyph colour and its measured *style* are still spec §8's holes"
  neighbourhood: the **new** paint-only fields are unanimated too, deferred to
  task 13 and pinned by
  `theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate`.
- `CLAUDE.md`'s `Deferred` sentence — "hoists to the root layer and resets clip
  and scroll offset together (AP-I)" — gains "and **not** opacity, which a faded
  subtree's portal inherits" (`OM-AA` b), which only becomes reachable once
  `.opacity` exists on the legacy path.
- `MC-G` hole 5's owner: the modifier-composition decisions doc says task 5, and
  task 5 closes it (`OM-Z`). No reassignment for integration to reconcile.
- `CLAUDE.md`'s "three `pass.fill` sites" and "four `pass.fill` sites"
  sentences, and the animation section's registering-point counts, all move:
  after lane 2 the background sites go through `paintDecoration` and a bordered
  element emits a **second** rect after its children. `ModifierTests`' "40
  public funcs in `Box.swift`" reconciliation is re-taken **in the test file
  itself** at 47, with a note that `grep -c "public func"` does not see
  `Decoration.setOpacity` because it is `public mutating func`.
- **`CLAUDE.md`'s `HandlerShape` sentence now covers TWO structs** (lane 1). It
  reads "`HandlerShape` in `ModifierTests.swift` must gain a field in the same
  change `Handlers` gains a member — it has fallen behind twice."
  `OuterModifierMatrixTests.swift` carries a second projection of the same
  shape, `HandlerFingerprint`, because the storage witness must compare
  `Handlers` and `Handlers` is not `Equatable`. **Lane 3 added
  `allowsHitTesting` and `contentShapeInset` to `Handlers` and to both structs
  in the same commit (`e1c33b5`)**; the sentence must name both.
- The focus-ring look is a **human** check: nothing in the suite can see whether
  a ring reads as a focus affordance. It belongs in CLAUDE.md's human
  verification table, open, with the demo key that shows it (if lane 4 adds
  one). **Lane 2 deliberately did not add one** — the demo is pixel-identical
  and a ring in production would be a visual change made as a side effect of an
  audit (`OM-G`'s argument, one field over).
- **`OM-AE`'s eight-of-eleven split is closed**: lane 3 landed the other three
  (`e1c33b5`), and §5.1's eleven are all live. `Box.swift`'s lane 2 MARK
  comment says so.
- **`OM-AK` (lane 3)**: CLAUDE.md's inert-table row "`.allowsHitTesting(false)`
  over a scroller — gates click hitboxes only" now covers the legacy path too;
  extend the row's reach rather than adding one.
- **`OM-AG`** refutes a mechanism the spec's §8 risk table implies. If that
  table is ever copied into `CLAUDE.md` or the plan, the corrected sentence is
  the one in `OM-AG`.
- **Lane 4 (`OM-D`, `OM-E`, `OM-F`, `OM-Z`, `OM-AM`)**: CLAUDE.md's `Component`
  paragraph loses "chained `.padding` replaces rather than accumulates" and
  "`.padding()` on a single-`Text` component is inert"; the inert table's
  `Style.padding` row loses its "and a `Component`'s distributed `.padding`"
  clause; the divergence table gains `OM-F` (a component's `width`/`height`
  overwriting its members' own, where SwiftUI's `.frame` wraps) with the next
  free number; `MC-G` hole 5 is closed by two existing traps and two exit
  tests; and the demo comparison for the whole track is on record above with
  its instrument.

---

### Track totals at `2fb0800`, re-taken by the record pass (2026-09-16 04:51 PDT)

`swift build --build-system native --build-tests`, then unfiltered `swift test
--build-system native --no-parallel`, in this worktree, nothing else building:

```
Test run with 1274 tests in 1 suite passed after 38.318 seconds.
```

0 `error:` in the build and the run; the one `warning:` is SwiftPM's
`--build-system native` deprecation notice (it appears once in the build log
and once interleaved into a test's name in the run log); skipped: the two gated
tests only. `find Tests -name "*.json" | wc -l` = **97**; `git diff --stat
c4b5853 -- Tests` lists no `.json`. Guards, `grep -c canTypecheck` per file:
PhaseSeparationTests 19, ErasureCompileGuards 10, ElementGroupTrapTests 5,
UnitSafetyTests 3 (one a comment), AXNodeTests 3, ModifiedElementCompileGuards
2, ProposalLayoutCompileGuards 6, ProposalNodeIDCompileGuards 6,
EnvironmentCompileGuards 8, **DecorationCompileGuards 3** — **65 hits, 64
guards**. Against `c4b5853`'s 1226 / 97 / 61: **+48 tests, 0 goldens, +3
guards.** `git status --short` was clean before the run.

**What landed, by commit** (`git log --oneline c4b5853..2fb0800`, oldest
first):

| commit | lane | what |
|---|---|---|
| `981f78b` | design | spec, `OM-A`…`OM-S`, this record, four probes |
| `aa7b9f5` | design round 2 | `OM-T`…`OM-AC`, three probes extended, seven mechanism corrections |
| `a4c5dc6` | 1 | `OuterModifierMatrixTests.swift`: the matrix as a table and four order tests; no `Sources/` change |
| `c07f141` | 1 | the mutation round's two corrections (`OM-AD`) |
| `8526b51`, `cfc5c4d` | 1 | record; the stale `borderWidth` doc left for lane 2 |
| `c624d13` | 2 red-first | divergence 15 inverted, `DecorationCompileGuards.swift` (three guards) |
| `9f37d10` | 2 | `BorderStyle`, five `Decoration` fields, eight modifiers, `paintDecoration` / `registerAndScope`, `ModifiedElement.paint` as a recursion, `pushClip` + `activeOffset`; `borderWidth` deleted; `DecorationPaintTests.swift` |
| `10f0e40`, `5a28933` | 2 | the two-layer scope arm; record, `OM-AE`…`OM-AG` |
| `09a7f7c` | 2 review | `OM-AH`, `OM-AI`; `everyDecorationScopingSiteContainsItsOwnContent`, `clippedAlsoClipsTheHitboxesInsideIt` as three arms |
| `6279f59` | 3 red-first | the collision guard's two new names, `metalUIsDefaultHitRegionIsTheElementsWholeFrame`, `swiftui-allows-hit-testing-side-effects.swift` new, `swiftui-content-shape-hit-region.swift` + H4–H6 |
| `e1c33b5` | 3 | `Handlers.allowsHitTesting` / `contentShapeInset`, the scope at the top of `registerAndScope`, `Frame.hitRegion`, three modifiers; `HitRegionTests.swift` |
| `2859350` | 3 | record, `OM-AJ`, `OM-AK` |
| `641c91c` | 3 review | `OM-AL`, probe arms X0–X3, the layer-crossing pin and the hover pin |
| `5cadec0` | 4 red-first | seven rows' tests, the hole-5 exit test, the matrix row's two kinds, the animation arm re-specified |
| `367de92` | 4 | `ComponentModifierOp`, `StyledComponent.ops`, per-member padding wrap — `Component.swift` only |
| `2fb0800` | 4 | record, `OM-AM`, five stale doc comments |

**`Sources/` touched** (`git diff --stat c4b5853 -- Sources`): thirteen files,
+1174/−203. `AnimatedColor.swift` (+156: `paintDecoration`, `resolvedBorder`,
`effectiveForPointerState`), `AnimatedStyle.swift` (21: the storage doc's
re-measured sizes), `Box.swift` (+473/−: `BorderStyle`, `Decoration`'s five
fields and extended `init`, eleven modifiers appended, two `borderWidth`
overloads deleted), `Component.swift` (262 lines moved: `ops`),
`DecorationScope.swift` (new, 133), `Frame.swift` (111: `hitRegion`, the
scope depth, `pushClip`'s term, `registerHandlers`' inset), `Handlers.swift`
(+82: two members and their docs), `ModifiedElement.swift` (66: paint as a
recursion, per-layer `registerAndScope`), `Passes.swift` (3),
`ProposalNodeID.swift` (5: hole 5's note), `Stack.swift` (23), `Text.swift`
(38), `MetalUILayout/LayoutTree.swift` (**4, doc only** — a `setStyle` comment;
no golden moved). Shared files on the brief's minimal-edits list were touched
by appending (`Box.swift`'s modifiers at the end of the extension,
`Handlers`' two members at the end of the stored members, `ModifiedElement`'s
per-layer calls) except `Component.swift`, whose `StyledComponent` storage this
track owns by the pre-agreed boundary (spec §8 b).

**Tests per file** (`@Test` count at `2fb0800` vs `c4b5853`; guards counted
separately):

| file | base | now | delta | note |
|---|---|---|---|---|
| `OuterModifierMatrixTests.swift` | — | 5 | **+5** | new (lane 1): the matrix (21 rows: 19 `legacy Element`, 2 `legacy Component`) and four order tests |
| `DecorationPaintTests.swift` | — | 24 | **+24** | new (lane 2 + review): includes five exit tests with a positive control |
| `DecorationCompileGuards.swift` | — | 3 | **+3** | new (lane 2), guards; one extended by lane 3 |
| `HitRegionTests.swift` | — | 11 | **+11** | new (lane 3 + review) |
| `ComponentTests.swift` | 22 | 26 | **+4** | lane 4; `chainedPaddingReplacesRatherThanAccumulates` renamed and inverted to `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement` |
| `NativeBoundaryIntegrationTests.swift` | 3 | 4 | **+1** | lane 4: `aPaddingModifierOnAProposalComponentTraps`, an exit test |
| `NestedClipTests.swift` | 1 | 1 | 0 | lane 2: `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` inverted, name kept |
| `ModifierTests.swift` | 1 | 1 | 0 | rows 38 → **47** (−2 `borderWidth`, +8 lane 2, +3 lane 3); `HandlerShape` +2 fields |
| `AnimationTests.swift` | 49 | 49 | 0 | `everyRegisteringSiteAnimatesItsStyle`'s `Component` arm re-specified on a wrapper + member |

+48 in all, which is the suite delta. Exit tests added: six
(`anOpacityAboveOneTraps`, `aNegativeBorderWidthTraps`,
`aBorderWidthSetAfterInitIsStillValidated`, `anOpacitySetAfterInitIsStillValidated`,
their positive control `theAdmittedOpacitiesAndBorderWidthsBehave`, and
`aPaddingModifierOnAProposalComponentTraps`). `grep -c sleep` over every file
in the table: 0.

**Probes** (`docs/probes/`, five files, +1087 lines, each with its recorded
stdout, positive controls and toolchains in its header; every arm cited by a
test is listed by the test):

| probe | arms | new / re-recorded | cited by |
|---|---|---|---|
| `swiftui-outer-modifier-order.swift` | 25 labelled lines (L1–L9, A1–A3, B1–B2, C0–C2, D1–D2, E1–E3, F1–F3; the design session counted 22 arms) | new, design | matrix (L2/L5/L7, A1–A3, E1–E3), `DecorationPaintTests` (L2), `HitRegionTests` (L7), `ComponentTests` (E1/E3) |
| `swiftui-border-clip-paint.swift` | 26 lines incl. controls (B1–B3, C1–C3, D1–D2, G1–G4, K0–K1, M1, …) | new; +B3, +M1 and two arc points in round 2; re-run in lane 2's review | `DecorationPaintTests` (B1, B3, D2, M1, G1–G4), matrix (C1) |
| `swiftui-content-shape-hit-region.swift` | 18 (H0–H6, P1–P5, N1–N2, X0–X3) | new; +N2 round 2, +H4–H6 lane 3, +X0–X3 lane 3's review; re-run at each | `HitRegionTests` (H0–H6, N1–N2, X0–X3), matrix (P1, P2, P4, N1) |
| `swiftui-component-distribution.swift` | G0–G16 | new; +G10–G16 round 2 | `ComponentTests` (G0–G2, G4–G5, G7–G8, G10–G12, G15–G16) |
| `swiftui-allows-hit-testing-side-effects.swift` | 7 side-effect lines (K1, A0–A2, …: focus, keys and the `AXButton` under `.allowsHitTesting(false)`) | new, lane 3 | `HitRegionTests` (K1, A0–A2) |

**Probe arms with no MetalUI test** — found by the record pass by grepping
the test files for arm labels, and named here so the plan entry below is
honest: `swiftui-outer-modifier-order` **B1, B2, D1, D2** (the `.frame(60x60)`
chains of spec §6.1, i.e. the plan text's own "frame" chain) and
`swiftui-border-clip-paint` **C2, C3, D1** (the `.cornerRadius`/`.background`
and `.cornerRadius`/`.border` orders of §6.2, whose "not expressible" cells
are pinned by mechanism — one `Decoration` field per modifier,
`everyPublicModifierWritesItsOwnFieldAndOnlyThatField` — but by no test that
builds both orders). The spec's §6.2 cells for C3 and D1 said "Divergence,
pinned" and are corrected to say what is pinned.

**Red runs**, one per lane, quoted in the lane entries above: lane 1 one red
line (the 40x60 flex-shrunk child); lane 2 four tests, 12 issues before any
source change; lane 3 thirty-three "has no member" diagnostics, then the 47
tripwire alone; lane 4 eight of ten red, 21 issues, the same 21 mutation M1
and the revert M7 reproduce.

**Mutations that stayed green, whole track** — each one a finding, each
closed by a test the lane then added, none left standing:

| lane | mutation | what it found | closed by |
|---|---|---|---|
| 1 | M4: outermost decoration filled at the inner node's bounds | two order tests had no two-layer chain | three probe-backed arms (`OM-AD`) |
| 1 | M9: amend `nodes.prefix(1)` | the `distributes` witness read a member's POSITION | `Observation.rectSizes` (`OM-AD`) |
| 1 | M11: `Box.paint` emits no background | kills the instrument's own 1x1 marker — recorded as non-discriminating, not as a gap | — |
| 2 | M15: `ModifiedElement.paint` restored to a loop | every opacity/clip fixture was one element | `aChainsOuterLayerScopesContainTheLayersInsideIt` |
| 2 | G3: legacy `opacity(_:)` declared on `ElementGroup` | cannot collide — Swift prefers the refined protocol's extension (`OM-AG`) | the guard's recorded mutation became G3b |
| 2 review | four (helpers called with an empty closure / `Decoration()`) | the SCOPE half of both helpers was pinned at one site each (`OM-AI`) | `everyDecorationScopingSiteContainsItsOwnContent`, `clippedAlsoClipsTheHitboxesInsideIt` ×3 |
| 3 | (none stayed green; the spec's row 2a had named two wrong test names, found by the red run) | — | the eleven measured names |
| 3 review | MA: the candidate fix for `OM-AL` reddens only the new X test | the layer-crossing rule had one instrument | `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt` |
| 4 | (none; M5 and M6 redden exactly one assertion each, by design) | — | — |

**Hazards, whole track**, beyond each lane's own list: `Decoration` (nine
stored properties, 80 bytes) and `Handlers` (eight) both grew across a module
boundary — `swift package clean` before the first run after a merge that
touches either; the two helpers' SCOPE halves are the shape a future site
will get wrong (a call with an empty closure passes the "draws its border"
guard); `Component.swift` carries the literal `// MUTATION` in committed
comments, so a driver must prove reverts by `git diff`, not by grepping
`Sources/`; the display lock flips within minutes on this machine, so a
capture session reads it immediately before each `screencapture`.

---

### For the integrator

What each owned document should say, in the words to use. The lanes' running
list above is the source; where a bullet there and one here differ, this one
is later and wins. Divergence numbers are **not** allocated here: the highest
at `c4b5853` is **34** (record §04, "divergences 20–34"), so this track's rows
start at **35** only if the task-4 track allocates none; the integrator
numbers both tracks' rows in one pass.

#### `CLAUDE.md` — rules only

- **Counts line.** This track alone: **1274 tests / 97 goldens / 64 guards**
  at `2fb0800` (+48 / 0 / +3 on `c4b5853`'s 1226 / 97 / 61), guards per file
  gaining `DecorationCompileGuards 3`. Re-measure after the merge with task 4
  rather than adding the two tracks' deltas.
- **Component paragraph** (the sentence beginning "Its `.padding`/`.width`/
  `.height` **distribute** …"). Replace with: "Its `.padding` **wraps each
  top-level node** in its own padding node, accumulating on a chain (`OM-D`,
  `OM-E`; probe `swiftui-component-distribution` G2/G10–G12: a one-`Text`
  component measures 13x16 bare and 53x56 padded, the same numbers the element
  path gives), so `.padding()` on a single-`Text` component is no longer inert;
  `.width`/`.height` still **distribute** as an amend that overwrites the
  member's own value (`OM-F`, a divergence: SwiftUI's `.frame` wraps and keeps
  the member at 30). Ops apply in declaration order (`StyledComponent.ops`;
  `aModifierOnAComponentAppliesInTheOrderItIsWritten`). `.padding` now means
  the same thing on both receiver types; only `width`/`height` keep two
  meanings." Delete "chained `.padding` replaces rather than accumulates" and
  "`.padding()` on a single-`Text` component is inert while that leaf is
  content-sized". Keep "A caller's distributing modifier never animates
  (B-7)" — its `padding` example now reads on the wrapper node (20 at both
  samples), the `width` example is unchanged. Hole 5: "a legacy style modifier
  on a proposal `Component` compiles, then traps" — now both op kinds trap on
  an existing `SA-G` precondition (`.amend` at `setStyle`, `.wrap` at
  `newNode`), pinned by `aPaddingModifierOnAProposalComponentTraps` beside the
  amend pin (`OM-Z`); the modifier-composition doc's "task 5" assignment is
  discharged.
- **`StyledElement` paragraph.** "a conformer must also call
  `registerHandlers` in its own `prepaint`" becomes: a conformer calls
  **`registerAndScope(handlers, decoration, …) { content }`** in `prepaint`
  (opens the `allowsHitTesting` scope around the receiver's own registration
  AND its content, pushes `.clipped()`'s clip, then `registerHandlers` with the
  accessibility payload) and **`paintDecoration(decoration, in:, for:) {
  content }`** in `paint` (opens the opacity scope, emits the background before
  the content and the border **after** it, `OM-V`). Four sites: `Box`, `Stack`,
  `Text`, `ModifiedElement` (per layer). **Each helper has two halves and each
  half has its own per-site guard** (`OM-AI`): `everyDecorationPaintingSiteDrawsItsBorder`
  and `everyDecorationScopingSiteContainsItsOwnContent` (paint);
  `everyHandlerRegisteringSiteHonoursAllowsHitTesting`,
  `everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload` and
  `clippedAlsoClipsTheHitboxesInsideIt` (prepaint); the hover/focus chain by
  `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain`. A site that
  calls a helper with an **empty closure** and paints its content after it
  passes the first guard and fails the second. The `HandlerShape` sentence
  becomes: "`Handlers` is not `Equatable` and has **eight** stored members;
  `HandlerShape` (`ModifierTests.swift`) **and `HandlerFingerprint`**
  (`OuterModifierMatrixTests.swift`) must each gain a field in the same change
  `Handlers` gains a member." `ModifierTests`' tripwire is **47**; `grep -c
  "public func" Sources/MetalUI/Box.swift` is **50** (task 4 counts from
  there).
- **Hitbox paragraph.** After "`PrepaintPass.allowsHitTesting(false)` (and the
  proposal `.allowsHitTesting(false)`) gates only `registerHandlers`' pointer
  hitbox": add the legacy **`StyledElement.allowsHitTesting(false)`** — a
  prepaint-only scope on the layer it is written on, covering the receiver's
  own hitbox and its subtree's (`OM-T`, probe N1/N2), leaving focus, `onKey`,
  actions and the accessibility payload untouched; **per layer**, so written
  before a wrapping modifier that carries the `onClick` it does not reach that
  click (`OM-AL`, probe X1/X2 — a divergence, pinned wrong on purpose); a
  `ScrollView` inside still scrolls (`OM-AK`). Hover follows the hitbox
  (`aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse`). **`contentShape(inset:)`**
  moves the pointer region only — not the accessibility frame, not the focus
  registration — applied in `Frame.registerHandlers` to the bounds handed to
  `insertHitbox` through `Frame.hitRegion` (`OM-J`); a negative inset grows
  the region as SwiftUI's does (H5) and is still intersected with the active
  clip where SwiftUI's is not (`OM-AJ`, divergence); with no `onClick` it
  writes a field and registers nothing (`OM-AB`). **MetalUI's default hit
  region is the element's whole frame** where SwiftUI's is content-derived
  (`OM-I`, H1; divergence), so a padded click target is hittable in its
  padding (`OM-K`, P1) — order-sensitively, because only the outermost layer
  carries handlers (P2).
- **Focus paragraph.** Replace "Focus is drawn by `focusBackground` token
  swap. `PaintPass.fill` now takes `borderColor:`/`borderWidths:` (the
  proposal `.border` uses them), but no legacy element or focus path passes a
  border." with: "Focus is drawn by `focusBackground` and/or
  **`focusBorder(_:width:)` — the focus ring** (`OM-L`); background and border
  resolve through one `focus ?? hover ?? plain` selector
  (`effectiveForPointerState`, `AnimatedColor.swift`), so focus outranks hover
  for both; every legacy decoration site passes its border to `pass.fill`
  through `paintDecoration`, as a second rect **after** the children (`OM-V`).
  Nothing in the demo declares a `.focusBorder`; the ring is opt-in."
- **Animation section.** "Of the thirteen library `pass.fill` sites five
  animate …" is stale: `grep -rn "pass\.fill(" Sources/MetalUI` now reads
  **8**, all proposal-path or the `ScrollView` indicator; the four legacy
  background sites fill inside `paintDecorationBody` (`AnimatedColor.swift`),
  one animated background fill through `animatedBackground` and one border
  fill that does not animate. **The five new `Decoration` fields (`border`,
  `hoverBorder`, `focusBorder`, `opacity`, `clipsContent`) snap**, pinned by
  `theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate`, deferred to task 13
  (spec §9). A settled `$anim` entry now carries an 80-byte `Decoration`, not
  12 (`AnimatedStyle.swift`'s doc, re-measured; the end-to-end per-entry
  figures are not re-taken).
- **`Deferred` sentence.** "resets clip and scroll offset together (AP-I)" →
  "… and **not opacity**, which a faded subtree's portal inherits (`OM-AA` b,
  `aDeferredPortalInsideAFadedSubtreeIsStillFaded`)".
- **`.opacity` on the legacy path** (a new sentence beside the `Deferred`
  one): scopes multiply (`Frame.activeOpacity`), an element contributes ONE
  scope, so `.opacity(0.5).opacity(0.5)` on one element reads **0.5** where
  SwiftUI reads 0.25 (`OM-AH`); a nested `Box` or a layer between them reads
  0.25. `.opacity` fades the receiver's own fill in both orders on the legacy
  path and in one on the proposal path (`OM-AA` a).
- **Identity section.** Unchanged: `.padding`/`.frame` still return one flat
  `ModifiedElement`, `.id()` is still outermost. Add one clause: the
  decoration and handler modifiers written after a wrapper configure the
  **outermost layer** (`self` in the matrix's sense), which is why
  `.padding(8).background` fills the padded box and `.background.padding(8)`
  the inner one (`OM-C`, probe A1/A2).
- **Human verification table.** Two open rows: the focus ring's look (nothing
  in the suite can see whether `focusBorder` reads as a focus affordance; the
  demo declares none, so a look needs a demo-only commit first) and this
  track's release-window captures by `MC-J`'s method (never taken: the display
  read `<true/>` at every capture moment — 20:22, 23:50, 00:00, 00:03, 04:30,
  04:35, 04:38 — and `<false/>` only between them). The offscreen stand-in is
  on record twice (lane 2 and lane 4): **0 differing pixels in all ten images,
  scene dumps identical**, with an instrument that moves ~400 000–949 000
  pixels per legacy image and 0 in the preview.
- **Build note.** `Decoration` (nine stored properties) and `Handlers` (eight)
  crossed the module boundary with new storage; the `swift package clean` rule
  gains both names.
- **Practices, two bullets.** "A helper with two halves needs two per-site
  guards: a site that keeps the call and does its work outside the closure
  passes a guard that looks for the helper's own emission" (`OM-AI`). "A
  `distributes` witness reads each member's SIZE; a member's position is what
  its siblings did to it, and an order test needs a TWO-layer chain before a
  per-layer mutation can bite" (`OM-AD`).

#### The plan's task 5 entry — **do not tick**; replace the progress note

The task's own text is four clauses. Three are met and the fourth is met for
two of its three named chains:

1. *Complete the padding migration* — **done.** `Element` padding wraps
   (`f1944f8`, before this track); `Component` padding wraps each top-level
   node, accumulating (lane 4, `OM-D`/`OM-E`); one documented shape, spec
   §3.1's `padding(_:)` row, on all three columns.
2. *Audit background, overlay, border, corner/clip shape, opacity, hit
   testing, focus drawing and content shape* — **done**, spec §3.1, three
   columns (legacy `Element`, legacy `Component`, proposal). Legacy `overlay`
   is audited as "not offered; use `Stack` or `Deferred`" and deferred to
   task 6/7 (spec §9); the proposal `.overlay` is `MC-P`'s.
3. *Pin whether each wraps, distributes through a `Component`, or affects
   only paint* — **done for the legacy columns** by the table-driven
   `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` (21 rows,
   per-kind witnesses, `OM-X`/`OM-AD`/`OM-AM`); the **proposal column is
   pinned by the proposal path's own tests, not by the matrix** (spec §3.2),
   and adding a proposal-row shape to the instrument was left to integration.
4. *Test order-sensitive chains such as padding/background/frame/clip* —
   **padding/background** pinned (A1/A2/A3, E1–E3), **clip** pinned
   (`.clipped()` scopes on a two-layer chain; `.cornerRadius` C1 pinned wrong
   on purpose; the border/radius D2-vs-M1 arm), hit-testing and `Component`
   orders pinned (P1/P2, N1/N2, X0–X3, G13–G16). **The `.frame` chains — probe
   arms B1, B2, D1, D2 of `swiftui-outer-modifier-order` — are probed and
   recorded in spec §6.1 and pinned by NO MetalUI test**; nor are the
   `.cornerRadius`/`.background` and `.cornerRadius`/`.border` orders (C3, D1
   of `swiftui-border-clip-paint`). Four probe-backed arms the size of test
   2's would close the first; the second needs only a test that builds both
   orders and asserts they read the same.

Suggested note: *Progress 2026-09-16 (`feat/outer-modifiers` at `2fb0800`,
record §15, rulings `OM-A`…`OM-AM`). Padding wraps on both receiver types;
the matrix is written (spec §3.1) and table-driven for the legacy columns;
focus drawing is `focusBorder` and content shape is `contentShape(inset:)`,
both delivered; ten new divergences and one retirement (15). Open: the
`.frame` order chains (probe B1/B2/D1/D2) have no test; the proposal column
is not in the matrix instrument; `contentShape` across a layer boundary is
unprobed.* Also strike "Focus drawing and content shape are absent, and no
written wrap/distribute/paint-only matrix exists" from the 2026-09-14 note,
and under **Owned by later tasks** (`SA-N`) leave "padding places its child
at the child's size (task 5)" **as is** — that item is the proposal
`Padding` node's placement (kernel, `LayoutTree.swift`), which this track did
not touch (`OM-Q`: no `Sources/MetalUILayout` behaviour change); it needs a
new owner, and the honest edit is "(task 5 did not take it; reassign)".

#### `README.md`

- The paragraph "On an ordinary element, `.padding` **wraps** its receiver in
  a `ModifiedElement` layer …" gains: "On a `Component` it wraps each
  top-level node of the body, and chained paddings accumulate on both;
  `width`/`height` on a component still overwrite the members' own sizes."
- The legacy-path feature list gains the decoration and hit-testing
  modifiers: `.border`, `.hoverBorder`, `.focusBorder` (the focus ring),
  `.opacity`, `.clipped()`, `.allowsHitTesting`, `.contentShape(inset:)`;
  and `borderWidth(_:)` is gone.
- "Twelve measured divergences … Two are unfixed defects (15 and 19)": 15 is
  retired (fixed, `OM-U`), and the count grows by this track's ten (and task
  4's); re-count from `CLAUDE.md`'s table after numbering rather than from
  this sentence.

#### The declared-but-inert table

- **Delete** the `legacy borderWidth(_:)` row: the API is deleted (`OM-M`),
  guarded by `borderWidthIsNoLongerSpellable`.
- **`Style.padding`/`border`/`margin` on a leaf** row: delete the clause "and
  a `Component`'s distributed `.padding`: ignored on a content-sized leaf" —
  the distributed `.padding` no longer writes `Style.padding`.
- **`.allowsHitTesting(false)` over a scroller** row: extend to "on either
  path — the legacy modifier too (`OM-AK`, pinned by
  `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`)".
- **Add** `contentShape(inset:)` on an element with no `onClick` — writes
  `Handlers.contentShapeInset`, registers nothing (`OM-AB`,
  `aContentShapeWithoutAClickHandlerRegistersNothing`); and, on a chain,
  `contentShape(inset:)` or `allowsHitTesting(false)` written on an inner
  layer while the `onClick` is on a layer written after it — the inner
  layer's field is set and reaches no click (`OM-AL` for `allowsHitTesting`,
  probe-backed and pinned; for `contentShape` measured by lane 3's verifier,
  unprobed and unpinned — see open items).
- `Style.overflow`'s row stands: clipping is `Decoration.clipsContent`, not
  `Style.overflow`. `PaintPass.isActive`'s row stands (the hover pin's doc
  says the pressed half is by reading).

#### The divergence table

Ten new rows, one retirement. Each row's pin is named; the probe arm is the
SwiftUI side.

| ruling | one line | SwiftUI (arm) | pin |
|---|---|---|---|
| `OM-I` | the default hit region is the element's whole frame | content-derived: a stack's empty middle reads 0/0 (H1) | `metalUIsDefaultHitRegionIsTheElementsWholeFrame` |
| `OM-K` | a padded click target is hittable in its padding, and only when the `onClick` is written after the padding | 1/0 in both orders (P1, P2) | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` |
| `OM-AJ` | a grown (negative-inset) content shape is intersected with an ancestor's clip | hits through `.clipped()` (H6) | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` |
| `OM-AL` | an inner layer's `allowsHitTesting(false)` does not reach a click on a layer written after it | 0/0 in both orders (X1, X2); a later `.contentShape` restores it (X3) | `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt` |
| `OM-N` | `.opacity` fades a background written after it | does not (G4) | `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot` |
| `OM-AH` | a second `.opacity` on one element replaces the first (0.5) | multiplies (0.25; G1/G2) | `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies` |
| `OM-G` | `.cornerRadius` rounds the fill and border and does not clip the children; `.clipped()` clips | clips (C1); `.cornerRadius.background` is square (C3) | `aBareCornerRadiusDoesNotClipTheChildren` (C1); C3/D1 unpinned by order (mechanism only) |
| `OM-F` | a `Component`'s `width`/`height` overwrite each member's own size | `.frame` wraps and keeps the member's size (G7/G8) | `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` (task 4's to fix) |
| `OM-W` | `.border.cornerRadius` draws a rounded stroke that follows the arc | a square border clipped by the radius; the arc's interior is fill (D2 vs M1) | `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot` |
| `OM-AA` a | `.opacity` fades the receiver's own fill in both orders on the legacy path and in one order on the proposal path | G3/G4 | the legacy pin above and the proposal path's own G4-agreeing test (task 2) |
| **15** | **retired** (`OM-U`): `pushClip` adds `activeOffset`; a `ScrollView` inside a scrolled `ScrollView` now gets its own mask | — | `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` (inverted, name kept), `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints` |

Add 15 to the "Retired and never reused" list. `OM-AK` (the scroll region
under `allowsHitTesting(false)`) is an inert-table extension, not a
divergence: SwiftUI's answer is unprobed.

#### `docs/record/README.md`

One row, in the table's form: `15-outer-modifiers.md` — plan task 5 on
`feat/outer-modifiers` (`981f78b..2fb0800`, 2026-09-15 … 09-16): the
wraps / self / paint-only / prepaint-only / distributes matrix and its
table-driven test, `Component` padding wrapping per member, the legacy
`border`/`focusBorder`/`opacity`/`clipped`/`allowsHitTesting`/`contentShape`
modifiers with their two helpers and per-site guards, `borderWidth` deleted,
divergence 15 fixed, five SwiftUI probes, four lanes' red runs and mutation
tables, two verifier verdicts verbatim and two reconstructed, the offscreen
demo comparison (0 pixels, twice, with instruments), counts 1274 / 97 / 64,
and the integrator's list. **Section 14 is the task-4 track's**; do not
renumber.

#### Open items, in one place

| item | state | owner |
|---|---|---|
| `contentShape(inset:)` written before the wrapping modifier that carries the `onClick` — inert on the inner layer | measured by lane 3's verifier (regions `[0 0 200x200]` vs `[20 20 160x160]`), **unprobed in SwiftUI, unpinned, undocumented at the modifier** | a probe arm (`colour.contentShape(Rectangle().inset(by: 20)).padding(10).onTapGesture` vs the reverse), a doc sentence on `StyledElement.contentShape(inset:)` and `Handlers.contentShapeInset`, and a `#require`-disagree pin beside the X test — `Box.swift`/`Handlers.swift` are merge-collision files, so after the merge |
| the `.frame` order chains B1/B2/D1/D2 and the radius orders C3/D1 | probed, recorded in spec §6, no MetalUI test | task 5's tick |
| the proposal column in the matrix instrument | pinned by the proposal path's own tests only | integration's call (spec §3.2) |
| release-window captures by `MC-J`'s method | never taken; display locked at every capture moment, re-read by a lane-4 re-dispatch at `792893f`: `<true/>` at 2026-09-16 09:02:05 and 09:04:18 PDT, so no capture, no launch, no input (that run re-took the suite: `Test run with 1274 tests in 1 suite passed after 41.023 seconds.` native; six default-build-system lines summing 65+692+55+28+412+22 = 1274; 97 goldens, no `.json` in `git diff c4b5853 -- Tests`) | the next unlocked session |
| the focus ring's look | needs a demo commit declaring a `.focusBorder` first | human verification |
| lanes 1 and 2's verifier verdicts | lost; reconstructed above from the record and `09a7f7c`; one lane-2 mutation's outcome unrecoverable | — |
| `OM-AK`: a `ScrollView` under `allowsHitTesting(false)` | pinned as it stands; SwiftUI unprobed | whoever probes `ScrollView` under `.allowsHitTesting(false)` and `.disabled` together (`EV-Q`) |
| `SA-N`'s "padding places its child at the child's size (task 5)" | not taken here — proposal-kernel placement, `Sources/MetalUILayout` untouched | reassign |
| the `$anim` end-to-end per-entry figures with the 80-byte `Decoration` | not re-taken | task 13 |
