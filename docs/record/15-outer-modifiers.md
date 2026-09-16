## Outer modifiers and modifier order (plan task 5) — `feat/outer-modifiers`, from 2026-09-15

The record for plan task 5. Spec
`docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`; rulings
`OM-A`…`OM-AG` in
`docs/superpowers/2026-09-15-outer-modifiers-decisions.md` (next unused
`OM-AH`; the two-letter tails `OM-AA`…`OM-AG` are deliberate). The track runs in
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

#### Lane 4 — `Component` padding wraps, and the verification

*Not started.*

---

### Carried into the integration step

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
