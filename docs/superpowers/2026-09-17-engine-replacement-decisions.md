# Engine replacement decisions (plan task 7)

Rulings for `docs/superpowers/specs/2026-09-17-engine-replacement-design.md`, on
`feat/engine-replacement` from `c2290fc`. Ids are **lettered**, `LR-A`…; next
unused is **`LR-CH`** (stage 4's design took `LR-BQ`…`LR-BW`, its critic round 1 `LR-BX`…`LR-CB`, its lane 1 `LR-CC`, its lane 2 `LR-CD`, its lane 3 `LR-CE`, its lane 4 `LR-CF` and its lane 5 `LR-CG`, appended at the end; stage-4 rulings amended by that round carry a paragraph headed **Amended, stage-4 critic round 1**; stage 3's design took `LR-BB`…`LR-BJ`, its critic round 1 `LR-BK`, its lane 1 `LR-BL`, its lane 2 `LR-BM`, its lane 3 `LR-BN`, its lane 4 `LR-BO` and its lane 5 `LR-BP`, appended at the end; rulings amended by that round carry a paragraph headed **Amended, stage-3 critic round 1**; stage 2's design took `LR-AB`…`LR-AO`, its critic round 1 `LR-AP`…`LR-AV`, its lane 1 `LR-AW`, its lane 2 `LR-AX`, its lane 3 `LR-AY`, its lane 4 `LR-AZ` and its lane 5 `LR-BA`, appended at the end; stage-2 rulings amended by that round carry a paragraph headed **Amended, stage-2 critic round 1**). A bare `LR-3` is a typo, not a citation.

**Critic round 1 (2026-09-16, 21:05–21:30 PDT).** 24 findings; each is applied
or rejected in `LR-W`, which names where. Rulings amended in place carry a
paragraph headed **Critic round 1**; `LR-Q`…`LR-W` are new. New measurements
come from prototype **P2** (`LR-O`) and probe revision 2 (group W), and are in
record §18's "Critic round 1" section.

**Status, 2026-09-16 (PDT), design only.** No file under `Sources/` or `Tests/`
changed in a commit. Every source patch cited as a *prototype* was applied in
this worktree, built, run and restored with `git checkout Sources Tests` (new
files deleted), with `git status --short` showing only this design's docs and
probe afterwards; the patches are kept in the session scratchpad (`lr/`), never
committed. Baseline at `c2290fc`: `swift build --build-system native
--build-tests`, then `swift test --build-system native --no-parallel` → `Test
run with 1357 tests in 1 suite passed`, 0 `error:`, no `warning:` besides
SwiftPM's deprecation notice.

Probe: `docs/probes/swiftui-engine-replacement-stage1.swift`, run under
`/usr/bin/swift` (Apple Swift 6.4, swiftlang-6.4.0.33.1), macOS 27.0 (26A428);
exit 0; run twice, byte-identical, 61 lines, recorded in its header; revision 2
(critic round 1) appends group W, 79 lines, the first 61 unchanged. Arms cited
as T0–T9, B0–B3, H0–H2, S0–S3, G0–G2, W0–W5 ("stage-1 probe"). Earlier probes
cited by their own arm names: `swiftui-frame-semantics.swift` (D, C),
`swiftui-stack-algorithms.swift` (A5, G1, G9, G18, X13, K6),
`swiftui-overlay-presentation.swift` (P4, P5). **The stage-1 probe's G1 and the
stack-algorithms probe's G1 are different arms**; every citation names the
probe.

Measurements are in `docs/record/18-engine-replacement-stage-1.md`; the figures
below are copied from it.

---

## LR-A — the migration shape: lower legacy elements in place, under a per-frame layout authority

**The question.** Task 7 must end with no production layout request reaching
`FlexEngine`, while everything load-bearing — the default demo root, `List`
windowing, identity slots, hit testing, focus, accessibility records, animation,
the disabled gate, every legacy modifier, text measurement — runs on the legacy
path today, and an earlier wholesale conversion (`4aaca40`, reverted by
`d0a04d3`) broke three of them. Four shapes:

1. rewrite every caller onto the proposal vocabulary and delete the legacy types;
2. port `FlexEngine`'s algorithm into a `ProposalLayout` and keep the legacy
   types registering one node each;
3. conform the legacy types to `ProposalElementGroup` so proposal containers call
   a typed lowering entry;
4. keep the legacy types, and branch only their node registration on a layout
   authority chosen for the whole frame.

**What was measured.**

- **The pipeline after layout does not see the engine.** Prototype P1 (record
  §18) lowered `Box`, `Stack`, `Text` and `ModifiedElement` layers onto kernel
  nodes under a frame flag. On a counter chrome with `onClick`, `hoverBackground`,
  `focusBackground`, `.focusable()`, `.keyContext`, `accessibilityLabel`s, a
  padding layer and a background, rendered at scale 2 with accessibility on and
  a pointer over the minus button, the two authorities produced identical scene
  rects (3), glyph sprites (8), hitboxes (2), accessibility emissions (6, id,
  node and text), element bounds and `StateTable` counts (11). **Control:** the
  lowered stack's spacing + 1 made rects, glyphs, hitboxes and bounds differ.
- **Animation survives lowering.** A `Box` width 196 → 320 under
  `.linear(duration: 1)`, read at t = 0 (declared), 0 (transaction) and 0.5,
  was **196, 196, 258** under both authorities.
- **Shape 3 is refuted.** Adding only `extension Text: ProposalElement` and
  `extension Box: ProposalElement, ProposalElementGroup where Content:
  ProposalElementGroup` (bodies `fatalError()`) broke the demo target (`ambiguous
  use of 'background'`, `main.swift:429`) and, building `MetalUITests` alone,
  **83 errors in 13 files**: 66 `ambiguous use of 'background'`, 3 each of
  `opacity` and `allowsHitTesting`, 3 solver time-outs, 8 others. CLAUDE.md's
  "unambiguous only because no built-in type is both" is the mechanism.
- **Shape 1** needs the proposal vocabulary to gain handlers, focus, key
  contexts, accessibility records, decorations, the disabled gate and animation
  first (CLAUDE.md: nothing on the proposal path is focusable, handles keys or
  publishes to accessibility; everything on it snaps) — a second element pipeline
  in parallel with the first.
- **Shape 2** keeps CSS as the layout authority behind a new name; the task
  deletes the CSS paths.

**The ruling.** Shape 4. A frame has one `LayoutAuthority`. Under `.legacy`
(default) nothing changes. Under `.proposal` each legacy registration site
lowers its (animated) `Style` onto kernel nodes, keeping its ids, `prepaint` and
`paint`; `SA-G`'s one authority per root is unchanged, because the whole tree
lowers or the frame traps.

**Critic round 1** (finding 21). "Unchanged" was incomplete: once legacy
containers lower, a proposal element inside one is a tree of native nodes only,
which `SA-G`'s `newNode` trap no longer meets. That is ruled in `LR-T`
(allowed under the proposal authority, still a trap under the legacy one).

**Reasoning.** It is the only shape in which each later stage is a local change
to one registration site behind a measurable parity check, and in which the
subsystems that broke in `4aaca40` are untouched code rather than re-implemented
code.

**What it costs if wrong.** Two registration branches live in five files until
stage 9 deletes the legacy one; a fix to one branch does not reach the other
(practices: "a copy of a pinned implementation is unpinned"), which is why every
lowered site gets a differential test of its own.

---

## LR-B — the authority belongs to the frame, is set by the window, defaults to legacy, and stays internal until stage 6b

**The question.** Where the authority is chosen: by the root element's type, by
an environment value, or by the frame.

**Reasoning.** The root element cannot say: `Column { … }` is the same value
under either authority. An environment value is readable mid-tree, and a tree
that switched authority below its root would be `SA-G`'s mixed tree. The frame
is the unit `computeRootLayout` already decides on (`Frame.swift:1596`).
`Window` builds a frame per draw (`Window.swift:861`), so it carries the
setting.

**The ruling.** `Frame.init(…, layoutAuthority: LayoutAuthority = .legacy)` and
`Window.layoutAuthority` (a write marks the window dirty), both `internal`.
Stage 6b makes `.proposal` the default and decides whether any public spelling
survives. A plain-import typecheck guard pins the access level (practices shape
16: a `@testable` test cannot).

**What it costs if wrong.** If a later stage needs a per-subtree switch, it is
`SA-G`'s adapter and needs its own ruling; nothing here makes that easier or
harder.

---

## LR-C — under the proposal authority the legacy registrars trap; the harness gets diagnostics instead

**The question.** What an element with no lowering yet does under the proposal
authority.

**What was measured.** Prototype P1 recorded unlowerable fields instead of
trapping, which is what made the inventory in spec §2.7 possible in one run
(21 demo elements; stretch 8, grow 8, basis 1, `alignSelf` 1). A trap would have
stopped at the first.

**The ruling.** In production (`reportsUnlowerableFields == false`)
`Frame.requestNode`, `Frame.requestLeaf` and every lowering site's unhandled
field `preconditionFailure` with a message naming site and field. With
`reportsUnlowerableFields == true` — set only by tests — the site records an
`UnlowerableField` and registers a 0×0 native leaf so the frame completes. Each
trap is pinned by an exit test (spec 1.3, 1.4); the reporting branch cannot leak
into production because 1.3 and 1.4 run with it off.

**Why a red lowering test is a diagnostic, not a trap.** A trap in a
pre-implementation run truncates the suite (practices shape 13); a diagnostic
makes every lowering test red by an `#expect` on `report.unlowerable`.

**What it costs if wrong.** An orphaned native subtree under a diagnostic leaf
is not rejected (`ProposalNodeID.swift`'s orphan hole); its rects are unset and
the harness reports them as disagreements, which is noise, not silence.

**Critic round 1** (findings 1, 2). The first ruling put the checks in
`Frame.requestNode`/`requestLeaf` only, which cannot see two sites:

- **`StyledComponent`'s amend** writes through `LayoutTree.setStyle`, whose `SA-G`
  precondition (`LayoutTree.swift:603`) fires on an already-native member — so
  `MyComponent().width(70)` under the proposal authority died with `SA-G`'s
  message even with diagnostics on, truncating the suite (by reading; P2 routed
  the amend through the authority — skip the write, count it — but **no tree P2
  ran exercised an amend**: the census counted 0 `component.amend` in the five
  exit suites and the demo, so the fix is unmeasured and spec 1.4/1.5 are its
  pins).
- **`List`** registers no node of its own; it builds `Box`es and returns
  `built.requestLayout` (`List.swift:373–422`), so its only report was `box`,
  and once `Box` lowers its missing fields (`minSize.height`, `flexShrink`) an
  unwindowed `List` would lay out through `Box` silently.

**Amended ruling.** Every legacy site checks the authority **itself**, before it
registers, and passes **its own** `LoweringSite` (`Frame` never infers the
caller): `Box`, `Stack`, `Text`, both `ModifiedElement` registrars,
`ScrollView`, `List` (before building its `Box`; under diagnostics it then lays
out a zero-row `Box`, whose report is additional), `StyledComponent`'s amend
(reports `component.amend` and skips `setStyle`) and wrap (`component.wrap`),
and the public `LayoutPass.requestNode`/`requestLeaf` (`customElement`). Lane 1
therefore edits all of those files. Pinned by spec 1.3–1.5.

---

## LR-D — the differential harness: a top-leading, fixed-size root on both sides, compared element by element and observation by observation

**What was measured.** Prototype P1 rendered twelve trees (T0–T8 in record §18)
both ways.

| harness root | element rects agreeing |
|---|---|
| none — each tree is the frame's root | **4 of 50** (all in the `Stack` cluster) |
| `Stack(alignment: .topLeading) { tree }.width(W).height(H)` on both sides | **57 of 62**; 45 of 50 excluding the harness roots |

Without a common root every descendant is offset by the roots' own
disagreement (legacy fills the window, divergence 4; native centres at its
answer, `CN-J`). With it, the five disagreements are T4's four (stretch and
grow, outside the stage-1 subset) and T8's one (text hug, probe T7).

**The ruling.** `LayoutDifferential.compare` renders `DifferentialRoot { tree }`
at W×H under each authority — legacy: a `.topLeading` `Stack` node sized W×H;
proposal: a native `.topLeading` overlay in a W×H fixed frame — with bounds
recording, accessibility collection and a fresh `StateTable` each, and reports
per `GlobalElementID` agreement, disagreement, one-sided ids and unlowerable
fields, plus four whole-frame equalities: the scene (bytes, both as emitted —
rects and glyphs with their clips — and as finalized for the GPU — rects, glyphs
and `drawList` after the layer/order sort, so paint order and layer are compared;
lane-1 verifier finding, arm 1.9d),
hitboxes (id, bounds, layer, opacity), accessibility emissions **including
`geometry`**, and `StateTable` ids. Every harness test requires an arm that
disagrees (spec 1.8, 1.9).

**What it costs if wrong.** A tree whose disagreement only shows at the window
root (fill versus centre) passes the harness; that is stage 6b's ruling and its
own test.

**Critic round 1** (finding 12). **The root has a divergence of its own**: its
legacy side is a `Stack`, which offers fit-content, and its proposal side an
overlay, which offers W×H (divergence 53, `LR-G`). A wrapping `Text` or a greedy
child directly under the root disagrees because of the harness. So corpus trees
wrap such content in a container, 1.10 uses fixed children, and lane 5's
`Window` tests and two-authority images put `DifferentialRoot` in the window,
never a bare tree — without it legacy fills the window (divergence 4) and native
centres (`CN-J`), and a click at a fixed point would miss for a reason unrelated
to lowering.

---

## LR-E — the stage-1 lowering table: border-box as SwiftUI modifiers, and CSS-only behaviour lowered only where CSS cannot show it

**The table** is spec §5.4. Its three principles:

1. **Order.** Content → native padding → fixed frame: `Style.size` is
   border-box (spec §5.2), so padding sits inside it. Probe **B1** places a
   10×26 child at (12, 12) in `.padding(12).frame(width: 60, height: 60,
   alignment: .topLeading)` against control **B0**'s (0, 0); **B3** reproduces
   the counter chrome's legacy child rects (12, 60, 212).
2. **Alignment.** A container's size frame aligns its content by
   `justifyContent` on the main axis and `alignItems` on the cross axis — where
   CSS puts a content-sized flex line inside a larger box. Prototype T1 (a
   36×36 centred button) and T1b (the chrome) agreed rect for rect.
3. **Observable-only CSS.** `stretch` and `space-*` distribution change
   nothing when there is no free space to distribute: `stretch` with at most one
   child and no declared cross size, `space-*` with no declared main size.
   Prototype T5b and T6 carried a `stretch` container of one child and agreed;
   T4 (two stretched children in a declared-width column) disagreed at four
   rects. Anything else with no SwiftUI spelling in stage 1 is unlowerable by
   name.

**Why CSS `minSize`/`maxSize` are unlowerable rather than flexible frames.** They
are clamps on the element's own size (`FR-G`); a flexible frame is greedy at a
concrete proposal (`FR-A`, frame probe D control: 80 where the CSS clamp reads
40). Prototype P1 lowered `minHeight` as a frame and the demo tree could not tell
(its `minHeight(0)` is also `flexBasis(0)` + `flexGrow`); stage 2 owns the
decision with its own probe.

**Why rem lowers and percent does not.** A rem is `rootFontSize`-relative and
deterministic at registration; a percentage resolves against a containing block
the kernel does not have (`FR-H`, `FR-T`).

**What it costs if wrong.** A field lowered where CSS *can* show it would pass
registration and disagree only in the harness; spec 3.5 carries an arm per rule
that must disagree once the rule is removed (mutation M3f).

**Critic round 1** (finding 6). The table said both "a leaf ignores
`flexDirection`" and "`.rowReverse` is unlowerable", and test 2.3 put container
rows on a leaf while 2.4 said container fields on a leaf are ignored. **Amended:**
the legacy engine lays out no children for a leaf, so **every container field
is ignored on a leaf whatever its value** (reverse, `gap %`, `.baseline`,
`.stretch`, `space-*`, `justifyItems`, `flexWrap`, `alignContent`, `display:
.stack`); every **node** field (`display: none`, `%` size and padding, the
padding floor, padding on a `Text`, `minSize`/`maxSize`, `margin`, `border`,
`position`, `inset`, `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`) is
reported on a leaf. The spec's table is split into "containers", "leaves" and
"every node"; 2.3 carries the node rows, 2.4 the container rows on a leaf. And
the overflow evidence is stack-algorithms **G9**/X13, not G1 (finding 9; `LR-I`).

---

## LR-F — a lowered `Text` hugs its widest line and keeps its legacy glyph origin; the below-word clamp is withdrawn (critic round 1)

**What was measured.** Probe T: `Text("alpha bravo charlie delta echo foxtrot
golf")` answers **252×16** at nil, 1000 and ∞ (T1, T5, T6); **45×112** at 60
(T2); **0×592** at 0 (T3); **5×592** at 5 (T4). Inside `.frame(width: 60)` the
text's own frame is 45 wide at x 7.5 (T7, T8), or x 0 under a leading stack
(T9). Control T0 (`"alpha"`, 33×16) differs. Prototype T8: the legacy text box in
a 60-wide column is **60** wide; the lowered leaf **44** (MetalUI's shaper) at
x 8.

**The ruling.**

- The lowered leaf is measured by `proposalTextMeasurement`, amended to answer
  `min(widest line, proposed width)` when a width is proposed. The amendment is
  in the shared function, so `ProposalText` gains the same clamp: one
  implementation, one pin (spec 2.7). The preview never proposes a width below a
  word, so its images are expected unchanged. **Superseded by critic round 1
  below: the clamp is withdrawn, and the last sentence was false.**
- A `Text`'s declared `size` wraps the leaf in a fixed frame aligned
  `.topLeading`; the element's node is the frame (bounds, decoration and hitbox
  as legacy border-box) and glyphs are painted at the element's bounds origin,
  wrapped at the leaf's measured width (`Text.Layout.measuredNode`). T7's
  centring is SwiftUI's answer for `.frame(width:)`, which a legacy `.width` is
  not until stage 8 converts it (`FR-F`).
- Legacy text in a container wider than its widest line (T8) disagrees by
  design; pinned by spec 2.6 and 5.2.

**Why not keep the legacy width (fit-content).** Fit-content is a CSS item rule
with no proposal counterpart; T2 shows SwiftUI answering the hug.

**What it costs if wrong.** If the 44/45 difference is a measurement rule rather
than font metrics, lowered text is 1pt narrower than SwiftUI's everywhere; task
11 owns font metrics, and the test computes its expectation from the shaping
cache rather than hard-coding either figure.

**Critic round 1** (finding 10). "The preview never proposes a width below a
word" was false as a statement about allocation: `solveLinearStack` probes every
member of a group of two or more at main `offer(0)`, and a lower-priority
child's reserved minimum at `offer(0)` (`LayoutTree.swift:1227–1236`), so a
clamp changes what a `ProposalText` answers inside **every** horizontal stack
with a finite width, not only answers the caller sees. Measured:

| arm (HStack spacing 0) | SwiftUI (stage-1 probe W) | kernel, no clamp | kernel, clamp |
|---|---|---|---|
| W0 control `{label; "Short"}` at 400 | 105 / 34 | 105 / 33 | 105 / 33 |
| W1 (stack-algorithms G18) at 80 | 46×48 / 34 | 45×48 / 33 | 45×48 / 33 |
| W2 label `.layoutPriority(1)` at 80 | **59×32 / 18×32** (77) | 76×32 / 8×80 (84) | 75×32 / 5×80 (80) |
| W3 "Short" `.layoutPriority(1)` at 80 | 46 / 34 | 45 / 33 | 45 / 33 |
| W4 `{label; fixed 40×10}` at 80 | 34×64 / 40 | 34×64 / 40 | 34×64 / 40 |
| W5 `{"alpha bravo"; "charlie"}` at 40 | 20 / 19 | 20 / 18 | 20 / 18 |

The clamp moves exactly one allocation, W2, and not toward SwiftUI (which gives
the lower-priority text less than its widest word by a rule the kernel does not
have). **Amended ruling: the clamp is withdrawn from stage 1.** A lowered `Text`
is measured by `proposalTextMeasurement` unchanged; stage 1 changes nothing on
the proposal path that a production root reads. The below-word answer (T3/T4)
and W2 go to stage 2's `Text`/`ProposalText` unification with these arms as its
evidence; spec 2.7 becomes a characterization pin of today's answer, pinned
wrong on purpose, whose mutation is adding the clamp.

**Lane 2** amended two sentences of this ruling by measurement; see `LR-X`. The
below-word answer is the widest *character*, not word, and glyphs wrap at the
frame's width, not the leaf's (`Text.Layout.measuredNode` is gone).

---

## LR-G — a lowered `Stack` offers its proposal (closing divergence 53 under the proposal authority)

**Evidence.** Stack-algorithms probe A5 (a greedy child in a `ZStack` fills
100×80) and `CN-P` item 2. For fixed-size children the two agree: prototype T3,
6 of 6 rects.

**The ruling.** `display: .stack` lowers to a native overlay with the `Stack`'s
nine-point alignment. Children are proposed the stack's proposal; the legacy
fit-content offer is not reproduced. Spec 4.2 pins the disagreement on a
wrapping `Text`; the legacy pin
`aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` stays until stage 9.

**What it costs if wrong.** A lowered `Stack` over wrapping text lays out
narrower than its legacy twin — visible only under the proposal authority,
which no production root takes before stage 6b.

---

## LR-H — a legacy frame layer lowers onto the kernel frame, from its animated `Style` plus `FrameSpec`; the `FR-D` ideal trap moves to legacy registration

**The question.** `FrameLayer.style()` flattens a `FrameSpec` into `Style`
(`size`+`minSize` for a fixed axis, finite `maxSize`, `flexGrow`+`alignSelf` for
a two-axis infinite maximum) and cannot carry an ideal (`FR-D`: trap at
construction). Lowering from `FrameSpec` alone would lose animation, which
interpolates the layer's `Style` (`AnimatedStyle.swift`); lowering from `Style`
alone would lose ideals, single-axis infinite maxima and the difference between
a CSS clamp and a frame.

**The ruling.**

- `ModifierLayer` stores `frameSpec: FrameSpec?` (a public type's stored
  property: `swift package clean`).
- A frame layer lowers to `newNativeFrame`: fixed width/height and finite
  min/max from the layer's **animated** `Style` fields that `style()` wrote;
  ideals, infinite maxima and alignment from `frameSpec`. A layer whose `Style`
  differs from `frameSpec.style()` in any other field is unlowerable
  (`modifierLayer.style`).
- The kernel frame is SwiftUI's (`FR-A`/`FR-M`), so under the proposal authority
  divergence 35 (`FR-E`, frame probe D control: legacy 40, lowered 80) and
  `FR-O`'s inert single-axis maximum (legacy 20, lowered 100) do not arise; spec
  4.5 pins both disagreements, and the legacy pins stay.
- **`FR-D`'s trap moves** from `frame(minWidth:idealWidth:…)` to the legacy
  registration branch, so `.frame(idealWidth: 80)` builds, lowers under the
  proposal authority (frame probe C1: the ideal is the answer on an unspecified
  axis), and still traps when laid out by the legacy engine. The pin
  `anIdealDimensionOnTheLegacyFrameTraps` is amended to render its closures; its
  message check is unchanged.

**What it costs if wrong.** A value that only exists as a constructed modifier
(never rendered) no longer traps; the plan item "ideal on the legacy path" is
exactly that relaxation, and divergence 39's pin moves with it.

**Critic round 1** (findings 4, 5).

1. **The trap had nowhere to read an ideal from.** `FrameSpec` has no ideal
   field — its doc says the overload that accepts one traps before building a
   spec (`FrameLayer.swift:37–40`). **Amended:** `FrameSpec` gains `idealWidth:
   Pixels?` and `idealHeight: Pixels?`; `style()` does not read them; the
   flexible overload builds the spec instead of trapping; the legacy
   registration branch of a frame layer traps when either is non-nil (message
   still names `idealWidth`/`idealHeight`); the lowering passes them to
   `newNativeFrame`.
2. **"Ideal on the legacy path is stage 1" was false as written**, because under
   the legacy authority `.frame(idealWidth:)` still traps. The handed item has
   two halves: **ideal under the proposal authority** is stage 1 (lane 4, spec
   4.6); **ideal under the legacy authority** is never implemented — an ideal
   has no CSS lowering (`FR-D`) — and production gains the legacy *spelling* at
   stage 6b, when the default authority becomes proposal; stage 9 deletes the
   legacy authority and the trap with it.
3. **"`Style` differs from `frameSpec.style()` ⇒ unlowerable" would have
   rejected every one-node frame layer**, because `ModifiedElement.requestLayout`
   stores `lowered(_:childCount:)` (`display = .stack`, `ModifiedElement.swift:88–90`)
   back into the layer before `animated(…)` (`:217`, `:225`), and `style()` never
   writes `display`. **Amended check:** compare the layer's **declared** style
   (after `lowered`, before `animated`) with `lowered(frameSpec.style(),
   childCount:)`. `display: .none` is checked first and reported as
   `display.none`. Values are then read from the **animated** style, so an
   animation never trips the check (spec 4.7, with the mutation that compares the
   animated style instead). **A caller's `Self`-returning modifier after
   `.frame`** — `.width`, `.minWidth`, `.maxHeight`, `.flexGrow`, `.alignItems`
   — lands on the frame layer, makes the declared style differ, and is reported
   `modifierLayer.style` (spec 4.8, with a `.background` control that reports
   nothing; `Decoration` is not `Style`).

---

## LR-I — overflow compression is reported by the harness, not diagnosed at registration

**The question.** CSS shrinks fixed-size children that overflow their container
(`flexShrink` defaults to 1; divergence 55); SwiftUI's stack does not compress a
fixed child. Whether a row overflows is known only after measurement.

**The ruling.** No registration diagnostic. Spec 3.6 pins the disagreement on
`Row { 80; 80 }.width(100)` (legacy 50/50, lowered 80/80 from x 0), with the
stack-algorithms probe's **G9** (`HStack(0){a fixed 80; b fixed 80}` at 100×50
answers 160×20, a at 0, b at 80) and its nil-proposal control **X13** (160×20) as
the SwiftUI evidence. Stage 2 decides whether a legacy spelling lowers to
priorities or is re-spelled.

**Critic round 1** (finding 9). The first text cited G1, which is
`HStack(0){a 20..100; b 60..100}` — flexible children sharing space, the
evidence for *order* among flexible children (divergence 55's other half), not
for a fixed child's overflow. Corrected here and in the spec; divergence 55's
row in record §04 cites `CN-P` 4's G1 and is the Docs phase's to annotate with
G9.

**What it costs if wrong.** A tree that agrees in the harness at one size can
disagree at a smaller window; stage 6b's root switch re-takes the demo at 560².

---

## LR-J — `display: none` (`hidden()`) is unlowerable in stage 1

**Evidence.** Probe H: `.hidden()` keeps its space (H1: c at y 40, as control
H0), a removed `if` does not (H2: y 20). The legacy `hidden()` is `display:
none`, H2's answer, and three sites read it (`Frame.swift:1092`, `:1804`,
`ModifierLayer.lowered`).

**The ruling.** Unlowerable by name in stage 1; stage 2 decides between
SwiftUI's space-keeping `hidden()` (a deliberate change) and a removal spelling,
and moves the `AB-O` suppression off `Style.display` in the same change.

**What it costs if wrong.** Nothing hidden can be in a stage-1 corpus tree.

---

## LR-K — identity, slots, hit testing, focus, accessibility and animation are unmoved by construction, and lane 5 pins them anyway

**Reasoning.** Lowering changes only which registrar a `requestLayout` calls:
ids come from the group walk and the cursor, both untouched; `animated(…)` runs
before the branch; `prepaint`/`paint` read `pass.bounds(of:)`. Prototype P1's
equalities (`LR-A`) are the measurement. "By construction" is a reading, so
spec 5.4–5.6 pin clicks, focus, key actions, the published accessibility tree,
`StateTable` ids and two animated widths through a real `Window` under each
authority.

**What it costs if wrong.** A pipeline dependency on `Style` that this design
missed would show as a lane-5 disagreement on an agreeing-rect tree — the
reason those tests exist.

---

## LR-L — the whole task is fourteen stages (nine before critic round 1), and stage 1 is the lowering foundation

**The plan** is spec §4. Its ordering constraints:

- **2 before 6**: the demo cannot lower until flex-item fields do (spec §2.7).
- **3 before 4**: a windowed `List` windows against a `ScrollContext` published
  by a lowered scroller.
- **1 and 3 before 5**: the portal's content is lowered legacy elements, and the
  demo's modal sits inside a scroller.
- **2 before 7**: a golden is replaced by a deterministic native test of the
  SwiftUI semantics stage 2 fixes for its fields, or retired with the field.
- **6 and 7 before 8**: nothing may be deleted while a production root or a
  golden still needs it.
- **G** (grids) depends only on stage 1's harness and can land any time after.

**Why stage 1 is this and not the alternatives.**

- *The proposal-path equivalents a root switch needs* (a lowered `List`,
  `Deferred`, `ScrollView` first): each needs a way to compare its lowering with
  its legacy twin on real trees, which is stage 1's harness, and each lowers a
  container whose children are `Box`/`Text`/layers, which stage 1 lowers.
- *A root switch behind parity*: measured impossible without stage 2 — 0 of 21
  demo rects agree and 18 unlowerable-field occurrences are reported, in four
  fields (spec §2.7).
- *Goldens first*: their replacements are native tests of semantics stage 2
  decides.

Stage 1 is also the largest block that can be verified entirely by the harness
with no deliberate pixel change.

**What it costs if wrong.** If stage 2's decisions change a stage-1 lowering
rule (e.g. stretch), stage 1's tests that pin the observable-only rule change
with them; they are few (spec 3.5) and named.

**Critic round 1** (findings 11, 14, 16, 18, 20). The plan above is replaced by
spec §4's fourteen stages: 1, 2, 3, 4, 5, G, **6a** (custom elements and
CSS-answer tests, `LR-R`), **6b** (root switch), **7a** (goldens), **7b**
(non-golden CSS-engine tests, `LR-U`), **8** (sizing recipe), **9** (engine
deletion), **10** (`Style` fields and the closing check, `LR-P`), **11**
(modifier unification, `LR-V`). Changed ordering constraints:

- **2 before 3, 4 and 5**, measured, not asserted (spec §4.2): P2 ran each exit
  suite under the proposal authority with diagnostics and every one reports
  stretch (`ScrollRoutingTests` 35 + 4 `Stack`, `ScrollIndicatorTests` 11,
  `ListTests` 251, `DeferredTests` 3, `AbsoluteOverlayTests` 2); `ListTests`
  also `flexShrink` 249 and `minSize` 222. **3 before 4 and 5**: `DeferredTests`
  and `AbsoluteOverlayTests` register `ScrollView`s (10, 2).
- **G depends on nothing**: grids have no legacy twin, so the harness has nothing
  to compare.
- **6a before 6b**: once the default is proposal, every custom element calling
  the public legacy registrars traps (24 test files, 18 533 nodes).
- **7a, 7b and 8 before 9; 9 before 10 and 11.**

**"0 of 21 demo rects agree" is withdrawn** (finding 11): it was taken with the
tree as the frame's own root, which `LR-D` shows offsets every descendant.
Re-measured inside `DifferentialRoot` at 920×560: **2 of 22** agree (the harness
root and one other), with the same field multiset (stretch 8, grow 8, basis 1,
`alignSelf` 1). The conclusion — a root switch cannot precede stage 2 — stands on
the multiset, not on the agreement count.

---

## LR-M — the demo comparison expects zero in every image at every lane

**Evidence.** The twelve `CN-R` images of the lanes-1–4 prototype built with the
default authority read **0 differing pixels, scene identical** in 12 of 12
against `c2290fc`. Base controls (spec §1) read as record §16/§17 did.

**The ruling.** Spec §7: 0 everywhere; the legacy images are not evidence for any
lane; the preview images are evidence for lane 2's shared clamp only; lane 5 adds
a two-authority chrome image pair with the M5d mutant as the control. Real
captures only when the lock probe reads unlocked and awake (`FR-V`); at design
time `IOConsoleLocked` read `<false/>` and the session dictionary read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`, so none were attempted.

**Critic round 1** (findings 8, 24).

- **The "12 of 12 read 0" figure is prototype P1's**, not the lanes'. P1 had no
  `measuredNode`, no `frameSpec`, no `FR-D` trap move and no clamp. It is
  evidence only that a default-authority branch moved nothing. Every lane
  re-takes the twelve images on its own tree with its real change (spec §7).
- **With the clamp withdrawn (`LR-F`) no stage-1 change reaches a production
  root**; the preview images are no longer evidence for lane 2. Lane 5's library
  move (`LR-S`) is the one lane whose images carry weight.
- **The skipped captures were an override.** The orchestrator's instruction
  was: if `IOConsoleLocked` reads `<false/>`, also take real release-window
  captures. It read `<false/>` at 20:36:28 PDT; the design applied `FR-V` (the
  session dictionary decides) and skipped them without saying it overrode the
  instruction. Recorded now as an override, with `FR-V`'s reason. At the critic
  round, 21:16 PDT, `IOConsoleLocked` read `<true/>`, so the trigger was not met
  and no capture was attempted. **Rule for the lanes:** when `IOConsoleLocked`
  reads `<false/>` at a lane's end, run the lock probe; if unlocked and awake,
  take the captures (`MC-J`'s method, no input); if the session dictionary reads
  locked, take one capture anyway and record both readings and what it shows, so
  the override rests on an observation.

---

## LR-N — deferrals

Spec §8's table, each with its stage. None of them is needed for stage 1's
exit test; every one of them is either a field stage 1 reports by name (so it
cannot be silently lowered) or a site stage 1 never enters (`ScrollView`,
`List`, `Component` distribution, `Deferred`'s layout, custom elements).

**Critic round 1** (finding 18). The table now also carries the handed items the
first version omitted — legacy `.overlay` (`CN-Q`), `MC-Q` finding 7, `FR-I`,
`CN-A`/`CN-T`, and outer-modifiers spec §9's task-7 rows — each with a stage or
a ruling that moves it out (`LR-V`).

---

## LR-O — method: what was run, and where

- **Baseline suite**, as in the header.
- **Prototype P1** (record §18 "Scratch differential"): `ScratchLowering.swift`
  plus branches in `Box`, `Stack`, `Text`, `ModifiedElement`, a `Frame` flag,
  bounds recording in `Element.prepaintGroup`, the root and inner layers, and a
  scratch test file with the twelve trees, the demo tree, the pipeline-parity
  tree and the animation arms. Built, run filtered, reverted.
- **Instrument I1** (record §18 "Instrument"): counters in
  `Frame.requestNode`/`requestLeaf` keyed by the caller's `#fileID`, in
  `computeRootLayout` by root kind, and in `computeLayout`; printed at exit;
  one unfiltered suite run (`Test run with 1357 tests … passed`); reverted.
- **Conformance measurement C1** (`LR-A`): the two conformances, `swift build
  --build-tests` (stops at the demo), then `swift build --target MetalUITests`
  for the error census; reverted, and a clean `--build-tests` read 0 errors.
- **Pixels**: `CN-R`'s harness generated into the prototype tree and into
  `c2290fc`; `cmp.py` per image; controls on the base.
- **Probe**, as in the header.
- **Prototype P2** (critic round 1; record §18 "Critic round 1"): P1 re-applied
  from its saved patch, plus: `SCRATCH_ALL=1` puts every frame under the
  proposal authority, makes the legacy registrars return a 0×0 native leaf and
  count the caller's `#fileID`, skips and counts `Component` amends, and makes
  `NativeLayoutRun.enter` record instead of trap; a counter of the deepest native
  run; at each legacy root, the legacy node depth and an **estimated lowered
  depth** (1 per node, +1 for non-zero padding, +1 for a declared size, +1 for a
  `minSize` different from the size or any `maxSize`); `minSize`/`maxSize`
  reported (still lowered as frames); `SCRATCH_CLAMP` for the below-word clamp;
  `SCRATCH_PADCHILD` placing a native padding's child at origin + inset at its
  own size (`SA-N` item 4); scratch tests for the demo inside the harness root,
  the W arms, a mixed tree and `dlsym`. Runs: the scratch tests filtered; the
  `CN-R` harness filtered, default and with `SCRATCH_PADCHILD`; the five later
  exit suites and the harness filtered with `SCRATCH_ALL`; one unfiltered suite
  (`Test run with 1365 tests in 1 suite passed`, the 1357 plus 7 scratch tests and
  the harness); the `dlsym` test also under the **default** build system. Saved
  as `lr/prototype-p2.diff`; reverted with `git checkout Sources Tests` and the
  new files deleted; `git status --short` then showed only the probe; `swift
  build --build-system native --build-tests` → `Build complete!`.

---

## LR-P — the mechanical check that closes the task

**The question.** "No production layout request may pass through the legacy
engine" must be checkable, not asserted.

**Critic round 1** (finding 17) — **amends item 2 and adds item 0 below.** The
guards in item 1 **skip silently** whenever `.build/<triple>/debug/Modules` is
missing, which includes every run under the default build system (CLAUDE.md's CI
section), and CI runs the default build system. A closing check that can skip is
not a check, and item 2 deleted the only runtime check in its favour.

**Item 0, the check that cannot skip:**
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` resolves, with
`dlsym(RTLD_DEFAULT, …)`, the mangled names of the removed public symbols —
`MetalUILayout.computeLayout(_:root:available:rootFontSize:)`,
`LayoutPass.requestNode(style:children:)`, `LayoutPass.requestLeaf(style:measure:)`,
`Style.flexGrow`'s getter — captured with `nm` **before** stage 9 deletes them and
written into the test with the command that produced them, and requires each to
be `nil`; the same test requires **positive controls** — the kernel's
`computeNativeLayout`, `LayoutPass.requestNativeLeaf` — to resolve non-`nil`, so
a broken instrument reads red rather than green. **Measured now** (P2): the
mangled `computeLayout` name resolves non-`nil` in the test process under both
`--build-system native` and the default build system, and the same name with its
last character changed resolves `nil` under both; a debug test build keeps
public symbols. Only `computeLayout`'s name was measured; a symbol `nm` does not
list as an exported text symbol before deletion (a stored property's accessor may
be inlined away) is dropped from the list with that reason recorded. Mutation at
stage 10: restore `computeLayout` as a public function (red). What it cannot see is a *renamed* engine entry point; the guards
and the grep are for that.

**Item 2, amended:** `noProductionFrameReachesTheLegacyEngine` lives from stage
6b until stage 9 deletes the branch it counts; item 0 replaces it, not the
guards. Item 1's guards stay as compile-level evidence, documented as skippable;
item 3's grep is a recorded command, not the only evidence.

**The ruling** (stages 9–10's, designed now so stages 1–8 do not paint it into a
corner):

1. plain-import typecheck guards (`typecheckFile`, `SA-P`) that each of these does
   **not** compile: `MetalUILayout.computeLayout(…)`,
   `pass.requestNode(style: Style(), children: [])`,
   `pass.requestLeaf(style: Style()) { _, _ in … }`, `Style().flexGrow = 1`;
   each guard mutated red once by restoring its symbol;
2. stage 6b's `noProductionFrameReachesTheLegacyEngine`, which drives the demo's
   content and a `List` through a `Window` and requires the legacy branch of
   `computeRootLayout` never ran, is deleted in stage 9 together with the branch
   — the guards in 1 replace it;
3. the closeout record lists `grep -rn "FlexEngine\|computeLayout(\|requestNode(style" Sources`
   with empty output and `find Tests -name "*.json" | wc -l` reading 0.

**Why guards and not a runtime counter alone.** A counter proves the paths it
drove; a symbol that does not exist proves every path.

---

## LR-Q — the native depth guard under lowering: measured far below the limit in stage 1, its boundary pinned, re-bisected before the root switch

**The question** (critic round 1 finding 3). `NativeLayoutRun.maxDepth` is 88
(`SA-L`), and its own doc says one legacy level ported as padding + frame is at
least three native levels, so a ported tree near legacy's 64 can trap where
legacy laid it out. The first design lowered a `Box` to content → padding →
frame and never mentioned the guard.

**What was measured** (P2, record §18).

- Over **one unfiltered suite plus the demo harness**, 2 440 legacy element
  roots: the deepest legacy element tree is **13** node levels (the default
  demo; `ModifiedElement` layers count, one node each), and the deepest
  **estimated** lowered depth is **22**; **no** root estimates above 64, and none
  above 88. (Direct `computeLayout` tests in `MetalUILayoutTests` were not
  element roots and were not counted; `LayoutContextTests` nests 65 on purpose,
  a CSS-engine test retired in 7b.)
- The deepest **actual** native run: **12** for the demo minus its scroll area
  lowered by P2 (inside the harness root), 12 for the whole demo with every
  unlowered site reporting, **10** for the preview, 9 or less for every scratch
  tree, 8 or less for the five later exit suites.

**The ruling.**

1. Stage 1 does not change `maxDepth`: the deepest tree the repository builds
   lowers to about a quarter of it.
2. Stage 1 pins the boundary under lowering (spec 5.8/5.9): a chain of 29
   padded, sized `Box`es (87 native levels) lays out, 30 (90) traps with
   `SA-L`'s message — both as exit tests, so a mutation on either side reddens
   without truncating.
3. **Stage 6b re-bisects the limit in release** (`SA-L` records release as
   unmeasured) and re-measures the lowered depth of every production root before
   the default changes. If a production root needs more, the limit is raised only
   with that re-bisection; a legacy caller whose tree lowers past it gets
   `SA-L`'s trap naming the node, which the root switch's ruling must name.

**What it costs if wrong.** A caller's legacy tree between about 29 and 64
levels deep, with padding and size on every level, lays out today and traps
after 6b. The estimate's +1 rules are this design's lowering table; a lowering
that adds levels (a flexible frame for `minSize` in stage 2, for example) moves
it, which is why 6b re-measures rather than trusting 22.

---

## LR-R — stage 6a: the public legacy registrars are deprecated and every in-repo caller moved in one change, before the root switch

**The question** (critic round 1 finding 14). Stage 6 as first planned made
`.proposal` the default while the public `LayoutPass.requestNode`/`requestLeaf`
still existed (`SA-F`: "a legacy root is unchanged"). Every custom element would
trap at run time — 24 test files, 18 533 nodes and 3 leaves in the suite
(`MeasurePerformanceTests` 17 494) — and every `Window`-driven test whose
expectations are CSS answers would go red. `FR-I` requires migration and
deprecation in one move under the 0-warning gate. Two options for callers
outside the repository: a compile-time deprecation, or only a run-time trap.

**The ruling.** Both, in order.

- **Stage 6a (default still legacy):** `@available(*, deprecated, message:)` on
  the public `requestNode`/`requestLeaf`, naming `requestNativeLeaf` and
  `ProposalLayout`; in the same change every in-repo caller moves — each custom
  test element onto `requestNativeLeaf`/`ProposalLayout`, or, where the test is
  **about a CSS answer**, pinned to the internal `.legacy` authority and
  registering through the internal, undeprecated `Frame.requestNode`, so the
  pinned test warns nothing. Which tests are "about a CSS answer" is **measured,
  not guessed**: the stage's entry measurement runs the suite with the default
  flipped and diagnostics on, and classifies each red test as a lowering gap
  (owned by a stage) or a CSS answer (retired in 7b). `Sources/`' own sites
  (`Box`, `Stack`, `ModifiedElement`, `ScrollView`, `Text`, `Component`) call the
  public forwarders today; they move to the internal `Frame` registrars in the
  same change, or the deprecation warns inside the module.
- **Stage 6b (default proposal):** an external caller that ignored the warning
  traps under the proposal authority with the `customElement` message stage 1
  already writes.
- **Stage 9** deletes the public pair.

**Why not only the trap.** A trap is found at run time, per path; a deprecation is
found at build time, for every call site, and costs nothing extra because the
0-warning gate already forces the in-repo migration.

**What it costs if wrong.** A test pinned to `.legacy` is a CSS answer that will be
retired, not ported; if the classification is wrong, 7b retires a test whose
behaviour should have been ported. The classification table is 6a's record, so
7b can check each row.

---

## LR-S — the demo's content moves into a library target the tests import

**The question** (critic round 1 finding 15). `MetalUIDemo` is an
`executableTarget` and `grep demoContent Tests` is empty, so stage 6b's exit test
("drives the demo's content") and spec 5.3 could only use a hand copy — and a copy
of a pinned implementation is unpinned, drifting the moment the demo changes.
`CN-R`'s `ZZDemoPixels.swift` is generated by copying `main.swift`'s text, which
is a copy too, and it is never committed.

**The ruling.** Lane 5 of stage 1 moves everything in
`Sources/MetalUIDemo/main.swift` before `runDemo()` — `DemoModel`, the row data,
the actions, `CounterPanel`, `demoContent()`, `PreviewToggle`,
`PriorityPreviewPanel`, `nativeLayoutPreviewContent()` — into a new library target
`MetalUIDemoContent`, which `MetalUIDemo` and the tests import. Module-level state
gains `@MainActor` (the generator today rewrites it to `nonisolated(unsafe)`,
which is the evidence that a library needs an isolation spelling). The move is
its own commit, verified by the unchanged suite count and the twelve images at 0
against `c2290fc`, with the generator switched from copying `main.swift` to
importing the library.

**Why not generate.** Generation happens outside `swift test`, so the pinned tree
and the demo can still disagree in any run that skipped the generator.

**What it costs if wrong.** A ninth non-test target (CLAUDE.md's "eight" is the
Docs phase's to update), and the library's access levels become API a reader may
mistake for framework API; the target is named for what it is.

---

## LR-T — a proposal element inside a lowered legacy container is allowed under the proposal authority and still traps under the legacy one

**The question** (critic round 1 finding 21). `Column { HStack {…} }` traps today
in `newNode` (`SA-G`: a native child under a legacy node). Under the proposal
authority the `Column` lowers to native nodes, so the trap is not met and the tree
lays out — a behaviour no ruling or test named, and one the first §5.1 item 3
("nothing outside the subset silently lays out") seemed to forbid.

**What was measured** (P2). `Column(gap: 4) { Box().width(30).height(10);
HStack(spacing: 0) { Rectangle 20×20; Rectangle 20×20 };
ProposalScrollView(.vertical) { VStack { Rectangle 100×400 } }.frame(width: 100,
height: 100) }` at 300×300 under the proposal authority: no diagnostic, no trap,
**one** scroll region, the scroll view's content 100×400 inside a 100×100
viewport, the column's children centred as a legacy `Column` centres them.

**The ruling.** Allowed. `SA-G`'s rule is one layout authority per root; under the
proposal authority every node is native, so the tree has one. Proposal elements
are **defined** under that authority — §5.1 item 3 is amended to "nothing whose
lowering is undefined lays out silently". Under the legacy authority the same
tree still traps, unchanged. Spec 3.7 pins both, including a wheel event moving
the `ProposalScrollView` through a `Window`.

**What it costs if wrong.** A caller who writes a mixed tree gets a trap until 6b
and a layout after it; a change of behaviour on the root switch that the
switch's ruling must list.

---

## LR-U — the non-golden CSS-engine tests get their own retirement stage, and stage 8 is split three ways

**The question** (critic round 1 finding 16). The first stage 8 carried the engine
deletion, `FR-F`/`FR-G`'s recipe (557 `.width` + 519 `.height` test sites), 651
`Style()` uses, deleting CSS fields from a public protocol requirement, and "tests
migrated" — while stage 7 accounted only for the 97 goldens. `MetalUILayoutTests`
has 440 `@Test`s; **295** are in 24 files that test the CSS engine or its inputs
(spec §2.6), most not goldens.

**The ruling.**

- **Stage 7b** retires the non-golden CSS-engine tests (and 6a's `.legacy`-pinned
  element tests) with 7a's rigour: a table with one row per removed `@Test`,
  naming a replacement native test or probe arm, or the deleted concept; exit
  criterion "tests removed = rows" and `grep -rn "computeLayout(" Tests` empty.
  The spec names the known replacements up front (`LayoutContextTests` →
  `NativeDepthGuardTests`; `StackLayoutTests` → native overlay tests and stage 1's
  4.1; `AlignmentTests` → `NativeStackDistributionTests` or deleted concept;
  the freeze-loop, leaf-probe, flex-base-size, intrinsic-mode and CSS measure-cache
  files → deleted concept with `NativeLayoutWorkTests` as the kernel's work pin;
  `AbsolutePositioningTests` → stage 5; `MeasurePerformanceTests` → a native
  work-count test).
- **Stage 8** is the sizing vocabulary only (the recipe and its deprecation in one
  move, the `Style()` writes).
- **Stage 9** deletes the engine, the legacy registrars, `textMeasure` and the
  legacy authority.
- **Stage 10** deletes `Style`'s CSS fields, narrows `StyledElement.style`, and
  runs the closing check (`LR-P`).

**What it costs if wrong.** More stages, more merges; each is small enough to
verify, which the single stage 8 was not.

---

## LR-V — handed items the first plan omitted: a modifier-unification stage, and `Component`'s decorations move to task 8

**The question** (critic round 1 finding 18). Handed to task 7 by `CN-Q` and
outer-modifiers spec §9, absent from the first design: legacy `.overlay`;
`ModifiedElement`/`ModifiedContent` unification; `.opacity` not reaching a
background written after it (G4, divergence 45); `.opacity` answering differently
on the two paths (`OM-AA` a); `Component` `background`/`onClick`/`focusable`
("task 7 or later"); `MC-Q` finding 7; `FR-I`; `CN-A`/`CN-T`.

**The ruling.**

- **Stage 11, modifier unification** (after 9, when one engine remains, which is
  the precondition outer-modifiers spec §9 names — "two engines until task 7"):
  `ModifiedElement`/`ModifiedContent` unified, legacy `.overlay` as the unified
  type's second subtree, G4 and `OM-AA` a. Exit test: the outer-modifier-order
  probe's G3/G4 arms and the overlay-primary-shape probe through the unified
  type.
- **`Component` `background`/`onClick`/`focusable` → task 8** (the composition
  audit). They are not layout; nothing in the engine's deletion needs them; the
  spec that deferred them allowed "or later". The Docs phase adds the transfer
  to the plan's task 8 note.
- **`MC-Q` finding 7** (a nil-axis frame under a stretching `Box`) → stage 2, with
  stretch.
- **`FR-I`** → 6a (the registrars) and 8 (the sizing vocabulary): each migrates
  and deprecates in one change.
- **`CN-A`** is stages 1–5 as a whole; **`CN-T`**'s transfers are stage 4 (`List`)
  and stage 5 (`Deferred`).
- **Divergences 35, 52–56**: 35 and 53 are lowered to SwiftUI's answer under the
  proposal authority in stage 1 (4.5, 4.2) and reach production at 6b; 52 and 55
  are stage 2; 54 and 56 are stage 3.

**What it costs if wrong.** Stage 11 is optional for the task's closing sentence;
if it slips, the unification's owner is still named.

---

## LR-W — critic round 1 dispositions

| # | finding | disposition | where |
|---|---|---|---|
| 1 | `Component` amend traps with `SA-G`'s message under diagnostics | **applied** (by reading: P2 routed it, but none of its runs exercised an amend — 0 counted) | `LR-C`; spec §5.1 item 3, lane 1, 1.4, 1.5 |
| 2 | `List` never reaches its own site; lane 1 files incomplete | **applied** | `LR-C`; spec §2.2, lane 1 files, 1.4, 1.5 (M1e′) |
| 3 | native depth guard unmentioned | **applied**, measured (legacy 13, lowered ≤ 22 estimated, runs ≤ 12) | `LR-Q`; spec §1, §5.1 item 5, 5.8, 5.9, stage 6b |
| 4 | `FrameSpec` has no ideal field; "ideal on the legacy path" misstated | **applied** | `LR-H` 1–2; spec §4.1, lane 4 |
| 5 | frame-layer check rejects every one-node frame; writes after a frame unspecified | **applied** | `LR-H` 3; spec §5.4, 4.7 (M4g′), 4.8, 4.9 |
| 6 | 2.3 and 2.4 contradict on leaves | **applied** | `LR-E`; spec §5.4 split, 2.3, 2.4 |
| 7 | `stateSlotsEqual` never false | **applied** | spec 1.9 arm b, M1l |
| 8 | "12 of 12" is not about lanes 1–4 | **applied** | `LR-M`; spec §7 |
| 9 | G1 cited for overflow | **applied** (G9/X13) | `LR-I`, `LR-E`; spec §5.4, 3.6, stage 2 |
| 10 | the clamp reaches allocation; "never below a word" false | **applied, and more**: measured (W arms, kernel with/without clamp); the clamp is withdrawn from stage 1 | `LR-F`; probe revision 2; spec 2.7, §7 |
| 11 | "0 of 21" confounded by root placement | **applied**, re-measured: 2 of 22 | `LR-L`; spec §2.7 |
| 12 | lane 5 `Window` tests and images do not name their root; root's own divergence | **applied** | `LR-D`; spec §5.3, 5.4–5.6, §7 |
| 13 | M1a's truncation is not evidence | **applied** (no mutation claimed for 1.1; the suite count pins the default) | spec 1.1 |
| 14 | stage 6 cannot merge green | **applied** (6a) | `LR-R`; spec §4.1 |
| 15 | exit tests cannot import the demo | **applied** (library target) | `LR-S`; spec lane 5, 5.3, stage 6b |
| 16 | stage 8 too big; non-golden engine tests unaccounted | **applied** (7b; 8/9/10) | `LR-U`; spec §2.6, §4.1 |
| 17 | closing check rests on skippable guards | **applied**, measured (`dlsym` under both build systems) | `LR-P`; spec stage 10 |
| 18 | handed items missing | **applied**; `Component` decorations moved to task 8 | `LR-V`; spec §4.1 stage 11, §8 |
| 19 | stage 2's "0 px" unmeasured | **applied**, measured: `SA-N` item 4 implemented in scratch reads 0 in all 12 images, instrument live; stage 2 re-takes with its real change | spec §4.1 stage 2; record §18 |
| 20 | stage dependencies asserted | **applied**, measured (diagnostics census of each exit suite) | `LR-L`; spec §4.2 |
| 21 | mixed trees unruled | **applied**, measured | `LR-T`, `LR-A`; spec §3, 3.7 |
| 22 | no work-count baseline | **applied** | spec 5.7 |
| 23 | "13 files"; `AnimatedStyle.swift` "27 lines" | **applied** (12 guard files; 568 lines) | spec §1, §2.3 |
| 24 | captures skipped although the trigger was met | **applied**: recorded as an override; a lane rule that takes a capture even when the session dictionary reads locked | `LR-M`; spec §7 |

**Not applied as proposed.** Finding 10 asked lane 2 to measure the clamp's
allocation effect; it was measured in this round instead, and the measurement
removed the clamp from stage 1, so lane 2 has nothing to measure. Finding 13
offered "an arm-level check 1.1 can fail inside the unfiltered suite, e.g. the
default read through a `Window` observer": any change to the default traps the
suite's first legacy frame before such an observer's assertion can be reported,
so the second option (the whole suite pins it) was taken.

---

## LR-X — lane 2's corrections: a lowered `Text` wraps at its element node's width, answers its widest character below a word, and 2.6 uses the harness root

**What was measured** (record §18, lane 2).

1. **The wrap width.** `LR-F` and spec §5.2 had a lowered `Text` with a declared
   size paint at `Text.Layout.measuredNode`'s measured width — the native leaf
   inside the frame. Implemented that way (`57c6250`), 2.8's `width(100)` and
   `height(40)` arms agreed and mutation M2i (wrap at `layout.node`, the frame)
   left the whole suite green. Measured on the two spellings with
   `Text(long).width(w)` in a 1000-wide root: at `w` = 45 and 100 both agree with
   the legacy text; at `w` = 30 and 5 the **leaf** spelling's scene differs
   (`scenesEqual` false, 37 glyphs each, bounds equal) and the **frame** spelling
   agrees. The frame proposes `w`; the leaf's shape answers "wrap at `w`", and its
   stored width is that shape's widest line — wider than `w` when `w` is below a
   word. Wrapping again at that wider width puts more characters on a line than
   the height the leaf reported. The frame's measured width is `w` itself, the
   question the leaf answered, and is what the legacy text wraps at (its known
   width).
2. **The below-word answer.** Spec 2.7 said widths 0 and 5 answer the widest word.
   `proposalTextMeasurement` wraps at `smallestWrapWidth`, the typesetter breaks
   inside a word it cannot fit, and every line is one character: measured
   11.18 (the widest character with the space hung on its line; 7.91 without),
   against a tokenizer min-content of 40.44, 592 tall (37 lines × 16) — the same
   split `textMeasure`'s doc comment records for the legacy measure.
3. **2.6's container.** Spec 2.6 put `Text(long)` in a 60-wide `Column`; a
   `Column` is a container, which lowers only in lane 3, so in lane 2 the test
   could only read `box.noLowering`. Directly under a 60-wide harness root, the
   legacy side measured 60 — the root `Stack` offers fit-content, the same rule as
   a column item's cross size (ST-H, TX-H) — and the lowered side the widest line.

**The ruling.**

- Glyphs wrap at the **element node's** measured width under both authorities;
  `Text.Layout` keeps its one `node` field (`measuredNode` removed, `swift package
  clean` both times). 2.8 gains `.width(30)` and `.width(5)` arms, which were red
  on the `measuredNode` spelling.
- 2.7 is renamed `…AnswersItsWidestCharacterWhereSwiftUIAnswersTheProposal`, with
  an oracle that shapes each one-character line (and its hanging space) unwrapped.
- 2.6 uses the harness root directly; lane 3 may add the `Column` spelling.
- **2.8 runs its arms in a child process.** Mutation M2h (the text leaf returned
  as the element's node while its frame also holds it) traps on `CN-L`'s
  one-parent precondition, which in-process ended the run with no summary line
  (practices shape 13).

**What it costs if wrong.** If a later stage lowers padding on a `Text` (stage 2),
the element's node is no longer the node the leaf was proposed by — the wrap width
must then be read from the node directly around the leaf, and this ruling's
reasoning (wrap at the width the leaf was proposed) says which one.

---

## LR-Y — lane 3's container checks: field names, order, the main-axis gap, and `display: .stack` on a `Box`

**The question.** Spec §5.4's container table named what is reported but not the
entries' spellings for every row, their order against the every-node rows, which
axis `gap %` means, or what a `Box` container declaring `display: .stack` reports
before lane 4 lowers the overlay.

**What was measured** (record §18, lane 3). The seven lane-3 tests agree element
by element, scene, hitboxes, accessibility and state slots on every agreeing arm
(including the demo's counter chrome with its glyphs, B3), at literal rects
derived by hand. Mutations M3a–M3s each reddened named tests, except **M3l** (the
`display: .stack` check deleted, so a stack `Box` lowered as a flex row) — green,
and non-equivalent by construction (the report goes from `[box.noLowering]` to
empty and the stack's children are placed in a row rather than overlaid); 3.5
gained an arm and M3l then reddened it.

**The ruling.**

- Entries: `reverse`, `gap.percent`, `alignItems.baseline`, `alignItems.stretch`,
  `justifyContent.spaceBetween`/`.spaceAround`/`.spaceEvenly`, `flexWrap`,
  `alignContent`; the site is the caller's (`box` for `Box`, `Row`, `Column`).
- Order: `display.none` alone if hidden (`LR-J`); `noLowering` alone for
  `display: .stack`; else the container rows in the table's order, then the
  every-node rows (`legacyLeafDiagnostics`, including `padding.floor` and `margin`
  on a container). Production traps on the first.
- `gap.percent` is checked on the **main axis only** (`Axes.horizontal` for a row,
  `vertical` for a column). The cross-axis gap separates lines; with `flexWrap`
  reported, a lowerable container has one line, so it is read by nothing. 3.5 pins
  both halves.
- A `Box` container with `display: .stack` reports `noLowering` until lane 4, which
  replaces it with the overlay lowering.

**What it costs if wrong.** If a later stage lowers wrapping, the cross-axis gap
becomes observable and its `%` must be checked; M3i's arm names only the main
axis. If lane 4 routes `Stack` through `lowerLegacyNode`, it must remove the
`noLowering` row and amend 3.5's arm in the same change.

---

## LR-Z — lane 4's lowering: what a stack reads, a frame over zero or several nodes, where the frame check lives, and where an ideal can be seen

**The question.** Spec §5.4 said a `display: .stack` container lowers to an overlay
and reports "either `.stretch`", but not what the flex container rows do on a
stack, nor the entries' names. `LR-H` ruled a frame layer's lowering and check but
not a frame layer over zero or several nodes, which `ModifierLayer.lowered` keeps
on `FR-C`'s flex row. §5.2 said lane 4 adds `frameSpec:` to `lowerLegacyNode`. Spec
4.6 said the proposal arm is "measured at a nil proposal" without saying what
proposes nil.

**What was measured** (record §18, lane 4). The nine tests agree element by
element, scene, hitboxes, accessibility and state slots on every agreeing arm at
literal rects derived by hand. A sized `.bottomTrailing` `Stack` declaring
`flexDirection(.column)`, a gap, `justifyContent(.spaceBetween)`, `flexWrap(.wrap)`
and `alignContent(.center)` agrees with the legacy stack with an empty report: the
legacy engine branches to `layOutStack` before `collectItems`
(`FlexEngine.swift`, the `display == .stack` branch), so none is read. The first
spelling of 4.6's proposal arm put `.frame(idealWidth: 80)` in a lowered `Row` and
read **20×20**, not 80×20: the kernel stack proposes its own finite proposal to
its child, where a frame with only an ideal answers its child (frame probe
**C control**: 300×200 → 20×20, re-run this lane). CLAUDE.md's "stack children get
a nil main offer" is stale on this point; the Docs phase owns it.

**The ruling.**

- **A stack** (any site whose declared `display` is `.stack`) reports, after
  `display.none` alone: `alignItems.stretch` (`nil`/`.stretch`),
  `alignItems.baseline`, `justifyItems.stretch` (`nil`/`.stretch`), then the
  every-node rows. The flex container rows (`reverse`, `gap.percent`,
  `justifyContent.space*`, `flexWrap`, `alignContent`) are **not checked** on a
  stack, as a leaf ignores them (§5.4's leaf paragraph): the legacy engine does not
  read them. It lowers overlay (the nine-point alignment, `justifyItems` horizontal,
  `alignItems` vertical) → padding → fixed frame with the same alignment. `LR-Y`'s
  `noLowering` row for a `display: .stack` `Box` is removed and 3.5's arm amended
  in the same change, as `LR-Y` required.
- **A frame layer over more than one node** reports `frame.multipleNodes` (after
  `style`, if both), because the kernel frame has exactly one child and neither the
  legacy row nor a single frame is SwiftUI's per-member answer
  (component-distribution `G7`); stage 3 owns it with `Component` distribution.
  **Retired by `LR-BH` (stage 3, lane 5):** the row is deleted and the layer
  lowers to a row of per-member frames instead, which is `G7`'s answer.
  **Over no node** it lowers over a 0×0 native leaf: the legacy row with no children
  answers its declared size or 0, which the kernel frame answers for a fixed or
  min-only frame (4.4's arm agrees); a maximum over nothing is greedy on the
  proposal side, `FR-E`'s disagreement again.
- **API.** The frame lowering and check are `LayoutPass.lowerLegacyLayer(_:declared:children:)`
  and `legacyFrameLayerDiagnostics(_:declared:childCount:)`, taking the
  `ModifierLayer`, instead of a `frameSpec:` parameter on `lowerLegacyNode`: the
  check compares with `layer.lowered(frameSpec.style(), childCount:)`, which is the
  layer's method, and re-deriving it in the lowering would be an unpinned copy
  (practices: a copy of a pinned implementation is unpinned). A `.padding` layer
  goes through `lowerLegacyNode` at site `modifierLayer`. `ModifierLayer.isFrame`
  is computed from `frameSpec`, so the two cannot disagree.
- **Where an ideal can be seen.** Nothing the stage-1 lowering registers proposes
  nil on an axis — the harness root, the lowered stacks and overlays and fixed
  frames all propose finite sizes — so a lowered ideal is observable only under a
  node that proposes nil: 4.6 uses a test-only `ProposalLayout` (`NilProposal`),
  which is what frame probe C1 measures. In a production tree an ideal shows under
  a `ProposalScrollView`'s scrolling axis or a custom layout, which cannot yet
  hold legacy content (`requestProposalGroupLayout`); by design, stage 3's
  lowered `ScrollView` would be the first legacy node that proposes nil.

**What it costs if wrong.** If a later stage lowers a stack's flex rows (it will
not: a stack has no main axis), 4.1's ignoring arm must change with it. If stage 3
frames each member of a multi-member component, `frame.multipleNodes` goes and 4.9's
arm with it. A caller expecting `.frame(idealWidth:)` to show in a lowered `Row`
gets the child's size. Whether SwiftUI's `HStack` answers the same for that frame
is **unprobed**: frame probe C control is the same frame at a finite proposal
outside a stack, and no stack-algorithms arm puts an ideal-only frame over a fixed
child in one.

---

## LR-AA — lane 5's corrections: what the corpus may spell, what the bounds log missed, what a window test must check first, and where the depth boundary is measured

**The questions.** Spec 5.1 names "the counter chrome" and "the demo header … in
lowerable spelling" without saying what is changed; 5.4–5.6 put "the counter
chrome inside `DifferentialRoot`" in a real `Window`, whose frames trap rather
than report; §5.2 gave `compareInWindows` a width and a height; 5.6 named the
counter's `$state0`, `$focus`, `$anim` slots and a `$ax` slot; 5.8 said 29 padded
`Box`es are 87 native levels without saying under what root; M5f and M5g were
two mutants.

**What was measured** (record §18, lane 5).

- **The demo's own `CounterPanel` does not lower**: `CounterPanel.chrome` ends
  with `.alignSelf(.flexStart)`, reported `box.alignSelf` (5.3's entry 7). **The
  demo's header does not lower either**, and not only for its `flexGrow`s: its
  `.height(72)` is written after `.padding(16)`, so it lands on the padding
  layer, a one-child row whose default alignment is stretch — reported
  `modifierLayer.alignItems.stretch` (5.3's entry 3), although the row is 40 tall
  and nothing could show the stretch.
- **The bounds log missed `AnyElement`.** 5.1's transparent-groups tree read 10
  elements where the hand derivation said 11: `AnyElement`'s own
  `prepaintGroup` — a copy of `Element.prepaintGroup`'s hand-off — did not call
  `recordElementBounds`, so the harness could not see an erased element's rect.
  Removing the record again (mutation MA) reddens only 5.1.
- **A window test can truncate the run.** The first re-run of M4h (the frame-layer
  check compares without `lowered`) ended with no summary line: 5.6's `.frame`
  layer reported inside a proposal-authority `Window`, and a window's frame traps
  (`Frame.swift:1532`, `modifierLayer.style`).
- 5.6's first run: an **unwritten** `@State` count has no `StateTable` entry, and
  the unlabelled counter has no `$ax` slot (a synthesized node is a record,
  `AB-U`); the "+" button, whose label is declared, has one.
- The depth chain: `NativeLayoutRun.enter` is entered once per `measureNative` and
  `placeNative` frame; the chain's deepest path is frame → padding → stack per
  `Box` and frame → padding → leaf for the innermost, so **3n** as the frame's
  root. Inside `DifferentialRoot` the root's frame and overlay add 2: 29 boxes
  would be 89 and trap.
- M5f (every lowered `Box` wrapped in a `padding(0)`) and M5g (a fourth native
  level per `Box`) are the same edit.

**The ruling.**

1. **The corpus spells the demo's trees with the stage-2 fields removed, and
   says so per tree.** The chrome is `CounterPanel.chrome(count:minus:plus:)`,
   imported from `MetalUIDemoContent`, with `style.alignSelf = nil`
   (`StageOneCorpus.counterChrome`); the header's bar declares a width instead of
   growing, the row's `flexGrow` is dropped, and the padding layer carrying
   `.height(72)` also declares `.alignItems(.center)`; the stack cluster drops its
   `alignSelf`. The whole demo, unchanged, is 5.3's.
2. **5.4–5.6 use a test-only `LowerableCounter`**, which repeats
   `CounterPanel.requestLayout`'s wiring (one `@State`, the chrome's closures, the
   two `onAction` handlers) over the corpus chrome, and drops only publishing
   `counterID` and focusing itself. It is the lane's one copy; stage 2 replaces it
   with `CounterPanel()`.
3. **`AnyElement`'s group entry records its bounds** (`ElementGroup.swift`), and
   `Frame.elementBounds`' doc names four sites, not three.
4. **`Window` gains two internal test observables**, `recordsElementBounds`
   (passed to every `Frame`) and `lastElementBounds` (captured beside
   `lastScene`). `compareInWindows` is `WindowPair` plus a drive: two windows,
   **square**, the harness root the window's size — the fake surface is square,
   and a native root is centred at its answer (`CN-J`) where the legacy root
   sits at the origin, so only a root the window's own size is at (0, 0) under
   both. It takes the Metal device from the caller's
   `try #require(MTLCreateSystemDefaultDevice())`.
5. **Every window test pre-flights its tree under diagnostics** (in
   `WindowPair.init`, and per animation end state in 5.6) and requires an empty
   report before it opens a window, so a reporting mutant reddens by name
   (practices shape 13).
6. **5.6's slots are owned where they are minted**: `$state0` (after a click on
   "+"), `$focus` and `$anim` under the counter; `$ax` under "+".
7. **5.8/5.9 render the chain as a production frame's root**, not inside
   `DifferentialRoot`: 29 boxes = 87 levels lays out, 30 = 90 traps. The nodes
   are counted too (87).
8. **M5f and M5g are one mutant** (a native `padding(0)` around every lowered
   `Box`); the record names what it reddened under both labels.

**What it costs if wrong.** If a later stage lowers `alignSelf` and forgets
`LowerableCounter`, the window tests keep proving a counter the demo does not
build; stage 2's exit test must swap it. A `WindowPair` of a non-square root
cannot be built; a stage that needs one (a root placement ruling, stage 6b)
resizes the fake window. `AnyElement`'s group entry still skips `AB-O`'s
`display: none` suppression — by reading, it never calls
`suppressingAccessibilityIfHidden`; unmeasured, outside stage 1, recorded as a
finding and not fixed here. The pre-flight
checks the first frame's tree only: a tree that becomes unlowerable after input
still traps inside its window.


---

# Stage 2 — flex-item semantics onto SwiftUI's (design, 2026-09-17)

Rulings `LR-AB`…`LR-AO` belong to
[`specs/2026-09-17-engine-stage-2-design.md`](specs/2026-09-17-engine-stage-2-design.md),
on `feat/engine-stage-2` from `cb2e708`. **Design only**: no file under
`Sources/` or `Tests/` changed in a commit. Measurements are in
`docs/record/21-engine-replacement-stage-2.md`.

**Probe**: `docs/probes/swiftui-engine-replacement-stage2.swift`, run under
`/usr/bin/swift` (Apple Swift 6.4, swiftlang-6.4.0.33.1), macOS 27.0 (26A428),
exit 0, run twice byte-identical, 157 lines; arms F0–F8, X0–X10, P0–P6, J0–J9,
R0–R2, C0–C1, V0–V3, each group with a control that differs. Cited below as
*stage-2 probe* arms; stage 1's as *stage-1 probe*, the containers probe's as
*stack-algorithms*.

**Prototype P3**: §3's mechanism for lanes 1–2, applied to this worktree, built,
run and restored (`git checkout Sources`, the scratch test deleted, `git status
--short` showing only this design's probe afterwards); patch kept in the session
scratchpad, never committed. Baseline at `cb2e708`: `Test run with 1409 tests in
1 suite passed after 42.660 seconds`, 0 `error:`, no `warning:` besides SwiftPM's
deprecation notice, 97 goldens.

---

## LR-AB — item fields are lowered by the parent: the child records, the container wraps, and a grown or stretched box's rect is its item frame

**The question.** `flexGrow`, stretch, `alignSelf`, `flexShrink`, `flexBasis`,
`minSize`/`maxSize` and `margin` mean something only on the **parent's** axes, and
legacy registration is post-order: `Box.requestLayout` registers its children
before it knows its own lowering, and a child has no reference to its parent.
Stage 2 needs the child's fields and the parent's axis at one place.

**Alternatives weighed.**

1. **A downward context** (the container pushes its axis and `alignItems` onto the
   pass before its children register). Rejected: every proposal container
   (`HStack`, `ProposalFrame`, `ModifiedContent`, `.overlay`, `ProposalScrollView`,
   custom layouts) would have to reset it, or a legacy grandchild would read its
   grandparent's axis; `CN-Q`'s containers ruling already named this exact shape
   ("a pass-scoped value every legacy container would have to set … none
   enforced") as the reason the legacy frame could not do it.
2. **Split a parent-facing node from the bounds node in the group entries.**
   Rejected: `Element.requestGroupLayout`, `AnyElement`'s copy, `ModifiedElement`'s
   outermost layer and the typed builder entries are line-for-line copies pinned
   one by one (`MC-H`); every one would change.
3. **A kernel "amend" API** so the parent re-parameterizes the child's size frame.
   Rejected: it needs every lowered element to end in a frame (extra nodes in
   every tree, moving stage 1's hand-derived work counts and depth pins) and a
   mutation of `NativeNode` storage after registration in `LayoutTree.swift`, a
   shared file.

**The ruling.** Each lowering records a `LoweredItem` (declared and animated
`Style`, site, content alignment, kind) for the node it returns, in
`Frame.loweredItems`, and reports no item field. A lowered container wraps each
recorded child before registering its stack or overlay — `fixedSize` for
`flexShrink: 0`, the **item frame** W (greedy for grow/stretch, carrying
`minSize`/`maxSize`), the **alignment frame** for a non-stretch `alignSelf`, and
padding for `margin` — and aliases the child's node to W:
`Frame.bounds(of:)` and `PaintPass.measuredWidth(of:)` resolve the alias.

**Evidence.** Prototype P3: the whole demo reports only
`[list.noLowering, scrollView.noLowering]` (modal on: plus `stack.position`,
`stack.inset`), and with `LR-AC`'s elision the full suite (1410 with the scratch
test) reds exactly the five tests that pin the old diagnostics. Why the alias:
in CSS a grown box's background, hitbox, accessibility frame and text wrap width
are the grown ones; a greedy frame in SwiftUI is the rect a `.background`
written after it paints (stage-2 probe F1's `bframe`, X1). Why the alignment
frame and the margin padding are not aliased: both lie outside the CSS box (X5's
`b` keeps its own rect; P3's background is at (8, 8)).

**What it costs if wrong.** Every reader of an element's rect goes through
`Frame.bounds(of:)` or `measuredWidth(of:)` today (grep at `cb2e708`: one
definition each, the two `PrepaintPass`/`PaintPass` forwarders); a future reader
of `tree.layout(node)` for an element bypasses the alias and sees the hugging
content rect. Lane 1's 1.10 pins the four observations that exist. A record no
lowered container consumes is silently item-less; under the legacy authority
only the root is such a position, and the legacy engine ignores a root's item
fields too.

**Amended, stage-2 critic round 1 (`LR-AP`).** Four corrections. (1) `measuredWidth(of:)` is `PaintPass`'s (`Passes.swift:607`),
not `LayoutPass`'s; the alias is resolved there and in `Frame.bounds(of:)`, the
only two rect readers (grep at `cb2e708`). (2) The lowering's per-frame state is
one stored property, `Frame.lowering: LoweringState`, defined in a new file
(`LR-AT`). (3) "A record nobody consumes lowers as though its item fields were
absent" is **withdrawn**: it made `HStack { Box().flexGrow(1) }`, a root
`.maxWidth(600)` and a `.margin(8)` under a proposal container do nothing without
a word, and CSS does apply `minSize`/`maxSize`/`margin` to a root. `LR-AQ`
replaces it. (4) The depth cost: an item registers up to **four** wrappers —
`fixedSize`, W, the alignment frame and the margin padding — not two, and
`NativeLayoutRun.maxDepth` (88) counts each; lane 2 pins the limit with three
wrappers per level, lane 4 with four, and lane 2 records the demo's deepest
native run under the proposal authority.

---

## LR-AC — stretch lowers to a greedy cross-axis item frame, except for a single child with no declared cross size; a greedy item inside a hugging item fills

**Evidence.** Stage-2 probe X1 (a greedy cross frame answers the stack's own
cross size at an unspecified proposal, 40) and X2 (the concrete one, 100): CSS's
line cross size in both. X4: a greedy view inside a **hugging** container fills
the container's proposal (200) where CSS's fit-content container is 30. X9: an
outer greedy frame stretches a nil-axis frame and leaves its content at its own
size. Prototype P3 without the elision: a `.padding` layer's implicit stretch
(its `Style.alignItems` is `nil`, EP-8's `Box` default) made the padded content
greedy, and three stage-1 tests went red on X4-shaped fills
(`aLoweredPaddingLayerAgreesWithTheLegacyWrapper` 9 issues,
`theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` 4,
`aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` 5); with
it, none.

**The ruling.**

- A child whose cross `size` is `auto` and whose effective alignment (`alignSelf
  ?? the parent's alignItems`) is `nil`/`.stretch` gets W greedy on the cross
  axis, aliased — **unless the parent has exactly one child and no declared
  cross size** (stage 1's `LR-E` principle 3, kept). SwiftUI's `.padding` never
  makes content greedy; a one-child `Box` is a padded, framed child.
- The stretched single-child case is a **new divergence**: a one-child container
  that is itself stretched does not stretch its child (legacy stretches it to the
  line; lowered, X9's content keeps its size). Pinned by lane 1's 1.3.
- A greedy item inside a container that hugs on that axis fills the container's
  proposal (X4; **new divergence**, pinned by 1.7). Not emulated: CSS's
  fit-content would need a custom `ProposalLayout` measuring each hugging item
  at nil and clamping — a lowering with no SwiftUI spelling, on the one path
  stage 6b deliberately re-spells (the demo re-spelled "for the semantics stage 2
  changed").
- A stack parent (`Stack`, and a one-node frame layer, `CN-N`) stretches per axis
  by `justifyItems`/`alignItems` with the same rule.
- **`MC-Q` finding 7**: a frame layer child with a nil axis is an auto item on
  that axis and is stretched like any other (X8 is SwiftUI's un-stretched frame;
  X9 the outer greedy frame this lowering registers). W carries the layer's
  finite `minSize`/`maxSize` on the stretched axis, where CSS stretches and then
  clamps (X10).

**What it costs if wrong.** If a real tree nests a stretched single-child
container around content that must fill (a card whose inner column paints a
background edge to edge), the lowered inner box hugs; the author re-spells with
an explicit `.alignItems(.stretch)` on a two-child container or a width. The
demo has one such row (the sidebar column, 282 → 160 tall, no decoration of its
own). If fit-content turns out to be needed widely, the custom layout above is
the fallback, measured against 1.7 and the demo's cause-R rows.

**Amended, stage-2 critic round 1 (`LR-AP`).** The single-child elision covers **stretch only** — the default or declared
`alignItems` of a one-child container — and not a declared `flexGrow` or
`alignSelf` in one (`LR-AR`). Two more fills this ruling admits now have pins
against probe arms re-run this round: a greedy child in a **hugging `Stack`**
fills it (stage-2 probe X16, 200 against control X15's 30; spec 1.9's divergence
arm), and a grower on a **hugging container's main axis** fills its proposal
(X18, 200 tall against X17's 30; spec 2.10, the isolating pin for the exit test's
cause R). Every stretch arm in the spec now declares `.alignItems(.stretch)` or
uses a `Box`: `Row` and `Column` centre by default (`Flex.swift:55`, `:111`,
EP-8), and spec 1.12 pins that the default stretches nothing.

---

## LR-AD — a non-stretch `alignSelf` lowers to an unaliased greedy alignment frame; `baseline` stays reported

**Evidence.** Stage-2 probe X5: `.frame(maxWidth: .infinity, alignment:
.leading)` places one child at the leading edge of a definite column while its
siblings stay centred (b at 0, a at 100) — CSS's `align-self: flex-start`. X7 (with
control X6): in an indefinite column the same spelling makes the column fill its
proposal (300 against 100). SwiftUI has no per-child cross alignment that
references the container's edge; an `alignmentGuide` aligns guides, not edges.

**The ruling.** `alignSelf` `.flexStart`/`.center`/`.flexEnd` differing from the
parent's `alignItems` wraps the (possibly W-wrapped) child in a frame greedy on
the cross axis with that factor, not aliased. A flex parent consumes it; a stack
parent ignores it, as the legacy stack does (inert table). `.baseline` reports
`alignSelf.baseline` (task 11). The X7 fill is a new divergence, pinned by 1.6.

**What it costs if wrong.** An `alignSelf` inside a hugging column widens the
column to its proposal. The demo's two uses (`CounterPanel`, the stack cluster)
sit in the main pane's column, which is itself grown and stretched, so they
agree (P3).

---

## LR-AE — `flexGrow` lowers to a greedy main-axis item frame shared equally; unequal weights and non-zero bases report

**Evidence.** Stage-2 probe F1 (a greedy frame takes the rigid sibling's leftover:
CSS's `flex-grow: 1`); F2 (two greedy frames over 100 and 20 at 300 answer
150/150 — CSS with `flex-basis: auto` answers 190/110, with `flex-basis: 0`
150/150); F3 (a greedy frame without a minimum never answers below its child:
200/100); F4, F8 (a declared minimum's **presence** lets it: 150 over a 200
child). No SwiftUI spelling carries a weight.

**The ruling.**

- `flexGrow > 0` → W greedy on the main axis, aliased, when every growing
  sibling's factor is equal (any equal value); SwiftUI's equal share. With
  `flexBasis: auto` and unequal content this differs from CSS (F2): a **new
  divergence**, pinned by lane 2's 2.2.
- Unequal positive factors among siblings → `flexGrow.weights`, once, on the
  **parent's** site (the only place all factors are visible): a deleted concept,
  stage 10; its tests retire in 7b.
- `flexBasis: 0` **with** `flexGrow > 0` → W's main-axis minimum 0 (F4/F8: a
  minimum's presence makes the greedy frame answer the equal share even over
  wider content, CSS's zero basis). A declared main `size` stays on the element's
  own frame — the child registers before it can know its parent's main axis — so
  a sized **container** with a zero basis lays its children out at the declared
  size inside the smaller item rect (F4's overflow): a new divergence, pinned by
  2.4's container arm.
- `flexBasis` `.auto` → nothing. Any other basis — `0` without grow, a non-zero
  length, a fraction — reports `flexBasis` (stage 8's recipe / stage 10).

**What it costs if wrong.** Two growers with different content widths and an
`auto` basis are equal under the proposal authority; a caller who relied on CSS's
base-plus-share re-spells at stage 6b/8 with explicit widths. By reading
`demoContent()`, every demo container holds at most one grower (the header row's
bar, the body row's main pane, the outer column's body row, the main pane's
scroller box), so no demo rect depends on it; P3 implemented no weights check and
is not evidence for this sentence.

**Amended, stage-2 critic round 1 (`LR-AP`).** **The zero-basis minimum is withdrawn** (finding 3). CSS §4.5 floors a
zero-basis grower at its automatic minimum, min(specified size, content size),
which the legacy engine implements; "W's minimum is 0" dropped it. Re-ruled:
- W's main-axis minimum comes **only** from a declared `minSize` (`LR-AG`), with
  or without a basis. Without one, W is "never below its child" (F3), which is
  CSS's automatic minimum for rigid content: stage-2 probe F10 (a greedy frame
  over a rigid 200 stack at a 75 share answers 200) is CSS's answer. For a
  `Text` it is not: F9 (a greedy frame over "alphabravocharlie" at a 50 share is
  50, the text breaking inside its word) against CSS's min-content (the word) —
  a **new divergence**, pinned by spec 2.4's text arm.
- A zero basis with `flexGrow > 0` on an element with a **declared main size**
  and no declared `minSize` **reports `flexBasis`**: CSS's floor is
  min(declared size, content), and the lowering sees neither the content minimum
  nor its parent's axis at the element's registration. With a declared
  `minSize` it lowers (W's minimum = that minimum) and the old sized-container
  divergence (children laid out at the declared size inside the item rect) stays,
  pinned by 2.4.
- `flexBasis: 0` with grow and no declared size lowers exactly as `auto` does;
  the two differ in CSS only by base + share (F2), which stays the pinned
  divergence of 2.2.
Stage 2's 2.2 `flexBasis(0)` arms therefore declare `.minWidth(0)` to agree at
150/150.

---

## LR-AF — `flexShrink: 0` lowers to `fixedSize`; any positive shrink lowers as SwiftUI's compression; divergence 55's SwiftUI answer stands

**Evidence.** Stage-2 probe F7 against F6: `.fixedSize()` keeps a Text on one line
and overflows (302 wide against 95) — CSS's `flex-shrink: 0` on a max-content
item. F5: a rigid 196 beside a greedy text frame at 400 keeps 196; CSS shrinks a
declared 196 to its content floor when a sibling's base size demands it (`SZ-L`;
the demo's sidebar reads 88 at 920). Stack-algorithms G9 (`HStack(0){80; 80}` at
100 answers 160, overflowing) and G1 (flexible children served least flexible
first). `LR-I` handed stage 2 the choice between lowering a legacy spelling to
priorities and re-spelling it.

**The ruling.** `flexShrink == 0` on an axis whose main `size` is `auto` → a
`fixedSize` on the parent's main axis (a declared size is already rigid). Every
positive `flexShrink`, whatever its value, lowers to nothing: the kernel's
compression order is the answer, and the weight has no spelling. **No priorities
are synthesized**: a `layoutPriority` derived from CSS base sizes would be a
lowering with no SwiftUI author behind it, and it would change allocation among
flexible children, not rigid overflow. Divergence 55 keeps SwiftUI's answer under
the proposal authority (pinned by 2.6 for weights and 2.9 on the demo's body-row
shape); production takes it at stage 6b.

**What it costs if wrong.** Rows that rely on CSS shrinking fixed-size children
overflow under the proposal authority; stage 6b's demo re-spelling meets the
sidebar first (P3: 88 → 196 moves every main-pane rect 108 to the right at 920).

---

## LR-AG — CSS minima floor the item frame by presence; maxima lower only where the item is greedy or sized

**Evidence.** Stage-2 probe F4/F8 (a greedy frame with a declared minimum answers
the proposal share even below its child), X10 (`.frame(maxHeight: 25)` is 25 in a
100-tall stack: greedy up to the maximum). Frame probe D4 (`swiftui-frame-semantics`,
`FR-A`): a finite maximum is greedy. `FR-G`: `.minHeight(0)` is the legacy
spelling that cancels flex §4.5's automatic minimum.

**The ruling.**

- `minSize` px/rem on an `auto` axis → W's minimum on that axis (aliased). With a
  greedy axis this is CSS's explicit minimum replacing the automatic one — the
  demo's scroller box (`flexGrow(1).flexBasis(0).minHeight(0)`) takes its share
  below its content; without, a floor.
- `maxSize` px/rem on a **greedy** axis (grown or stretched) → W's maximum.
- `minSize`/`maxSize` on an axis with a declared `size` → folded at registration
  into the element's own fixed frame as `clamp(size, min, max)`, CSS's used size.
- `maxSize` on a non-greedy `auto` axis → report `maxSize`: SwiftUI's maximum is
  greedy, CSS's clamps content, and stage 8's recipe converts `.maxWidth` to
  `.frame(maxWidth:)` and takes SwiftUI's answer there.
- A fraction → `minSize.percent`/`maxSize.percent` (`LR-AI`).
- A frame layer's own `FrameSpec` bounds stay on its kernel frame (`LR-H`); W
  repeats them only on a stretched axis.

**What it costs if wrong.** A `maxWidth` on a hugging text stays unlowerable until
stage 8; the census shows no such use in the demo.

**Amended, stage-2 critic round 1 (`LR-AP`).** The design's own test 1.4 contradicted this ruling: it put `.maxHeight(25)` on an
item of a **centring** `Row`, a non-greedy axis, and expected 25. Measured with
prototype P3 plus `SA-N` item 4 (record §21, critic round 1, scratch R2 arm S4:
P3 put every `maxSize` onto W): legacy 20×0 at y 50, P3 20×25 at y 38. Under this
ruling that maximum reports `box.maxSize`; spec 1.4 now declares
`.alignItems(.stretch)` and 1.12 pins the centring case's report. Frame probe D4
re-run 2026-09-17: `frame(maxWidth: 80)` at 100 is 80, identical to its record.

---

## LR-AH — the box model: border as insets, padding on a Text, the fixed frame over the BM-4 floor, margin as outer padding, and `SA-N` item 4

**Evidence.** Stage-2 probe P1 (a 12pt padding inside a fixed 10×10 frame: the
frame stays 10×10 and the padding overflows; CSS's border box floors at 34×34,
`BM-4`), P3 (padding outside a background is CSS's margin: background at (8, 8),
sibling at 36), P4 (negative padding overlaps, sibling at 4, and the response
clamps at 0 per axis, `SA-K` item 3), P6 (`Text("alpha").padding(10)`: 53×36,
text at (10, 10); the legacy leaf ignores Style padding, inert table). `SA-N`
item 4 and its pinned-wrong kernel test
`negativePaddingIsAcceptedAndItsResponseClampsPerAxis` (SwiftUI keeps a padded
child at its own size, P2b). Record §18's critic round measured a scratch of
`SA-N` item 4 at 0 differing pixels in all twelve images, and found the same
scratch made that test's child exit on `SIGTRAP`.

**The ruling.**

- `Style.border` px/rem adds to the native padding's insets, inside the declared
  size (CSS's border box; SwiftUI has no layout border, and padding is the
  spelling). A fraction reports `border.percent`.
- `Style.padding` on a `Text` lowers to native padding around the text leaf, with
  glyphs painted at the leaf's origin (`Frame.textLeafNodes`) — SwiftUI's P6, a
  deliberate change from the legacy inert answer, pinned by 4.2.
- A declared size below the padding (+ border) sum keeps the fixed frame (P1),
  a deliberate change from `BM-4`, pinned by 4.3.
- `margin` px/rem, either sign → native padding outermost around the child, not
  aliased (P3, P4); agreeing with CSS until SwiftUI's clamp (4.5 pins the
  clamp). `margin: .auto` → 0, which is what the legacy engine resolves (inert
  table). A fraction → `margin.percent`.
- `SA-N` item 4: `LayoutTree.placeNative`'s `.padding` case places the child at
  origin + leading/top inset at **its measured size**; the kernel pin is
  re-derived, and the lane finds the checkpoint behind the scratch's `SIGTRAP`
  before writing the placement.

**What it costs if wrong.** The `SA-N` change reaches production roots: every
proposal-path padding in the preview. The scratch read 0 px; if the real change
does not, the lane stops and explains each differing image against P2b before
continuing.

**Amended, stage-2 critic round 1 (`LR-AP`).** (1) **`SA-N` item 4 leaves this ruling** for its own lane and commit (`LR-AU`),
with the `SIGTRAP` explained by measurement. (2) A padded lowered `Text` **wraps
at its leaf's measured width** (`PaintPass.measuredWidth(of: leaf)`), not the
element's: with `LR-AB`'s alias a stretched or grown padded text's element
width is W, and wrapping there would overflow the trailing padding and re-line
(finding 5); spec 4.2 has the stretched arm and the mutation. (3) The fixed frame
over the padding overflows **by the frame's alignment** (stage-2 probe P7, P8,
P9, re-run this round): a lowered `Row`'s content alignment is `.leading`-shaped
(child at (12, 0) on P7), a `Column`'s `.top`-shaped ((0, 12), P8); P1's
`.topLeading` (a `Box`) is (12, 12). Spec 4.3 pins all three against legacy
`BM-4`'s 34×34. Test numbers here are the spec's lane 4 (the box model is lane
4 after `LR-AU`): 3.2 → 4.2, 3.3 → 4.3, 3.5 → 4.5.

---

## LR-AI — percentages keep reporting, owned by stage 8's recipe

**Evidence.** Stage-2 probe C1: `containerRelativeFrame(.horizontal) { $0 * 0.5 }`
inside a 200-wide `VStack` is 500 wide — half the 1000-wide host — against control
C0's 100. `containerRelativeFrame` is relative to the nearest *container* (window,
scroll view), not the parent; `GeometryReader` is a view with its own sizing
(see the amendment: it can express a parent fraction, greedily). `FR-H`/`FR-T` recorded the legacy fractions resolving against the
containing block.

**The ruling.** `size.percent`, `padding.percent`, `border.percent`,
`margin.percent`, `gap.percent`, `minSize.percent`, `maxSize.percent` and a
fractional `flexBasis` stay unlowerable by name. Each call site needs a respelling
decision (a fixed length, a greedy frame, a `ProposalLayout`), which is stage 8's
recipe; stage 10 deletes the fields.

**What it costs if wrong.** Nothing silent: a tree with a percentage traps under
the proposal authority until stage 8. `width(fraction:)` has test callers that
stage 6a's flipped-default census classifies.

**Amended, stage-2 critic round 1 (`LR-AP`).** "SwiftUI has no parent-relative spelling" was not probed and is **false as
written**: stage-2 probe C2 (added this round) sizes a child
`g.size.width * 0.5` inside a `GeometryReader` in a 200-wide stack and gets 100 —
half the parent's proposal — while the reader itself takes the whole 200. The
ruling stands on the narrower reason: no SwiftUI spelling makes a **child** a
fraction of its parent without a greedy reader around it, so a percentage has no
one-to-one lowering and each call site needs stage 8's respelling decision (which
may use a reader).

---

## LR-AJ — justify distribution lowers to spacers and rigid gap leaves; reverse lowers to reversed node order and a mirrored main alignment

**Evidence.** Stage-2 probe J1/J2 (`Spacer(minLength: gap)` between children is
`space-between`: 0, 90, 180 at 200), J3 (overflowing, packed from the start at
the minimum — CSS's `space-between` fallback is `flex-start`, the same), J4
(`space-evenly` at gap 0), J7 (`space-around`: 23.33, 90, 156.67), J8 (a rigid
10-wide leaf beside a `Spacer(minLength: 0)` is `space-evenly` with a 10 gap: 50,
130), J5 (a `Spacer(minLength: 10)` is **not**: 53.33), J9 (overflowing, spacers
pack from the start where CSS's `space-around`/`space-evenly` fall back to
`center`), J6 (a greedy frame beside a spacer takes all of it). R1/R2 (reversed
children in a trailing frame are `row-reverse`, overflow toward the start).

**The ruling.** Under a declared main size (stage 1 already lowered the unsized
case):

- `spaceBetween` → `Spacer(minLength: main gap)` between children, stack
  spacing 0;
- `spaceEvenly` → `Spacer(minLength: 0)` at both ends and between, a non-zero
  gap as a rigid native leaf of that length beside each between-spacer;
  `spaceAround` → the same with the between-spacers doubled;
- `rowReverse`/`columnReverse` → the children's **nodes** in reverse order
  (their group order, ids, paint and hit order untouched) and the main factor
  mirrored (`flexStart` → 1, `flexEnd` → 0), the spacer pattern reversed with
  them.

The J9 overflow is a new divergence, pinned by 5.3.

**What it costs if wrong.** Spacer nodes are native children with no element, so
the harness sees only the children's rects; a spacer mis-marked by `markSpacers`
would answer the cross proposal (`CN-C`), which 4.1's column arms see.

**Amended, stage-2 critic round 1 (`LR-AP`).** Unchanged in substance; its tests are spec **lane 5** (5.1–5.9, formerly 4.1–4.8),
and the J9 pin is 5.3. Lane 5 adds 5.9, a reverse container that its parent grows
(its mirrored main factor sits in W's content alignment). `space-*` on a
container with **no** declared main size that its parent grows or stretches on
that axis still reports (`LR-AR`): the spacers would have to be registered by the
child before it knows it is grown.

---

## LR-AK — `hidden()` keeps its space, paints nothing, takes no pointer and publishes nothing; accessibility suppression moves off `display`

**Evidence.** Stage-1 probe H1 (`.hidden()` keeps its layout space; H2, a removed
`if`, does not). Stage-2 probe V1 (nothing painted; control V0 painted) and V3 (no
tap; the tap reaches the view under it; control V2 the reverse). Accessibility
bridge rules R9 (`.hidden()` content is not published, `AB-O`). `LR-J` handed
stage 2 the choice and the move of `AB-O` off `Style.display`; record §18 found by
reading that `AnyElement`'s group entry never calls
`suppressingAccessibilityIfHidden`.

**The ruling.** Under the proposal authority a `display: .none` node lowers as if
shown and joins `Frame.hiddenNodes`. `Frame.isHidden(node)` is
`style(node).display == .none || hiddenNodes.contains(node)`, read by
`suppressingAccessibilityIfHidden` and `render`'s root check — so the legacy path
reads exactly what it read. `Element.prepaintGroup` registers a hidden subtree
under the existing `hitTestingDisabled` scope, `Element.paintGroup` skips its
paint, `AnyElement`'s entry mirrors both and gains the missing suppression, and
`ModifiedElement` mirrors them per inner layer (`MC-B`). Focus and keys are not
gated (SwiftUI unprobed; task 12), characterized by 5.5.

**What it costs if wrong.** A hidden scroll region still takes the wheel
(`hitTestingDisabled` does not gate scroll regions, the inert row); `ScrollView`
is site-level until stage 3, which inherits it.

**Amended, stage-2 critic round 1 (`LR-AP`).** **Superseded by `LR-AV`: `hidden()` is not lowered in stage 2.** The evidence
above stands and is re-checked (accessibility-bridge-rules R9 re-run 2026-09-17,
identical: `Text(Shown)` is the only published node). The mechanism was wrong for
the legacy path (finding 4): `isHidden` read `style(node).display == .none`,
which is true for every legacy `hidden()`, so skipping paint and hitboxes on it
would have changed production. `LR-AV` hands the owner the corrected constraints.

---

## LR-AL — `Row`/`Column` default spacing (divergence 52) is a spelling default, not a lowering

**Evidence.** Stack-algorithms S: `HStack`/`VStack` default to per-pair spacing
(8 between two leaves); `HStack(spacing: 0)` is 0. `Style.gap` defaults to
`.pixels(0)` and cannot say "unset", so a lowered `Row { a; b }` cannot tell a
caller's `gap: 0` from the initializer's default.

**The ruling.** A lowered stack's spacing is the declared main-axis gap, always
explicit (stage 1's behaviour, now characterized by 5.8). Closing divergence 52
means changing `Row`/`Column`'s public default — a vocabulary change with every
legacy caller's pixels behind it — so it is stage 8's, with the sizing recipe.

**What it costs if wrong.** Nothing moves; the divergence stays pinned by
`aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`.

**Amended, stage-2 critic round 1 (`LR-AP`).** Stack-algorithms probe re-run 2026-09-17 under macOS 27.0: 787 lines, identical
to its recorded OUTPUT line for line (leading spaces ignored), including group S
(`rect|rect: hstack 8 vstack 8`). Characterization 4.8 is spec **5.8**.

---

## LR-AM — text: the measurement is already one on the proposal path; the below-word answer and W2 go to task 11, the legacy measure's deletion to stage 9

**Evidence.** `LR-F`/`LR-X`: a lowered `Text` and `ProposalText` share
`proposalTextMeasurement`; below its narrowest word it answers the widest
character with its hung space (11.18 at 13pt) where SwiftUI answers the proposal
(stage-1 probe T3/T4, divergence 59). W2: with the long label at priority 1,
SwiftUI gives "Short" 18×32 — it breaks inside a word — and the kernel disagrees
with the clamp and without it (record §18, critic round 1).

**The ruling.** Stage 2 does not change text measurement. "Unified" is already
true under the proposal authority; the legacy `textMeasure` and tokenizer
min-content disappear with the engine at **stage 9**. The below-word answer and
W2 need a characterization of SwiftUI's in-word breaking that no probe has made;
it is text semantics, not a flex-item field, and nothing in the engine's removal
depends on it, so it moves to **task 11** (text, shape and rendering-facing
semantics). Divergence 59's owner changes accordingly (the integrator edits the
divergence table).

**What it costs if wrong.** Divergence 59 reaches production at stage 6b
unchanged. It is visible only for a text proposed below a word's width.

**Amended, stage-2 critic round 1 (`LR-AP`).** **Superseded in part by `LR-AU`.** "No probe has characterized SwiftUI's
in-word breaking" is no longer true: stage-2 probe group **Y** (added this round)
shows SwiftUI's line count equal to CoreText's own line-break loop at ten widths
and its width `min(proposal, ceil(widest line with its trailing space))`. The
kernel's `proposalTextMeasurement` already breaks the same lines (scratch, record
§21): it lacks only the `min(proposal, …)`. So the below-word answer (T3/T4,
divergence 59) **is stage 2's**, in lane 3. **W2 stays out**: with that clamp the
stage-1 scratch put the priority-1 text at 75 and "Short" at 5 where SwiftUI
gives 59 and 18, and Y6/Y7 show "Short" measures 18 at 21 on both sides — W2 is
the stack's allocation around a text, not text measurement; owner task 11 (text
in stacks; with divergence 51). The legacy measure's deletion stays at stage 9.

---

## LR-AN — stage 2's exit test pins the demo's report exactly and every disagreement as a literal with a named cause

**Evidence.** Prototype P3 (modal off): report `[list.noLowering,
scrollView.noLowering]`; 2036 ids, 6 agreeing, 30 disagreeing, 2000 legacy-only.
Every disagreement falls under five causes: **R** — the harness root's proposal
(divergence 53, stack-algorithms A5) filled by the demo's greedy column (X4); **55**
— the sidebar kept at 196 (F5, G9, G4r), shifting the main pane 108 right and
re-wrapping the paragraph; **X9** — the sidebar column not stretched in its
one-child padding layer; the `ScrollView` and the `List` (site-level, stages 3
and 4). Modal on: 2042 ids, 36 disagreeing, the extra rows the modal's `Stack`
(stage 5) and its descendants.

**The ruling.** `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` is
rewritten in lane 2 (spec §7): the report as an exact array for both modal
states; `try #require` on the id and agreement counts; each disagreeing rect pair
a literal grouped by cause, each cause with an isolating pin (`LR-AC`'s 1.3 and
1.7, `LR-AF`'s 2.9, the stage-1 `Stack` offer pin). The lane measures its own
table; P3's figures are the prediction it checks first, and a row under no named
cause is a finding before the literal is written. Lanes 3–5 re-run it unchanged.

**What it costs if wrong.** A literal of 30 rect pairs is brittle by design: any
lowering change that moves a demo rect reddens it, which is its job; the cause
grouping is what makes the red readable.

**Amended, stage-2 critic round 1 (`LR-AP`).** (1) **Text-dependent rows are derived, not literal** (finding 7, `LR-F`): the
paragraph's lowered height and every rect below it in the main column, the
"Text renders" and "Library" widths and heights, and the three counter texts'
sizes are computed in the test from `proposalTextMeasurement` (lowered) and the
legacy `textMeasure` path (legacy) at the widths the test itself derives;
literals remain only for rects no text reaches (the sidebar bars, the badge
frame, the chrome, the paddings' widths). (2) **The census was re-measured with
`SA-N` item 4 applied on top of P3** (record §21, scratch R2): the same 2036 /
6 / 30 and 2042 / 6 / 36, and all 30 (36) rect pairs identical to P3's — the
prediction the rewritten test checks first is now a measurement with lane 3's
kernel change in it. (3) The stage-2 exit test is spec **2.15**; its cause-R
isolating pins are `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`,
1.7 and the new 2.10 (X18).

---

## LR-AO — stage 2's scope: five lanes, and the rest deferred by name

**The ruling.** Lanes: (1) item records, the bounds alias, the cross axis; (2) the
main axis and the exit test; (3) the box model and `SA-N` item 4; (4) justify
distribution and reverse; (5) `hidden()`. Deferred (spec §9): percentages (stage
8/10, `LR-AI`), a non-greedy `maxSize` (stage 8), a non-zero `flexBasis` (stage
8/10), unequal grow weights (stage 10), divergence 55 in production (6b), 52
(stage 8, `LR-AL`), the below-word text answer and W2 (task 11) and the legacy
text measure (stage 9) (`LR-AM`), `hidden()` focus and keys (task 12), baselines
(task 11), a greedy child in a hugging stack (6b), `compareInWindows` (the
integrator), 5.8's doc and the 88/89 boundary (6b).

**Why this order.** Lane 1 builds the mechanism every other lane's wrappers use;
lane 2 empties the demo's report, so the exit test lands there; lanes 3–5 are
independent of each other and of the demo.

**What it costs if wrong.** Stages 3 (census, record §18: stretch 35 + 4 on a
`Stack` + 11, `minSize` 3), 4 (stretch ×251,
`flexShrink` ×249, `minSize` ×222) and 5 depend on lanes 1–2 only; a slip in
lanes 3–5 delays none of them.

**Amended, stage-2 critic round 1 (`LR-AP`).** **Lanes re-cut** (`LR-AU`, `LR-AV`): (1) item records, the bounds alias and the
cross axis, with the unconsumed-record report (`LR-AQ`) and the stretch half of
the free-space re-check (`LR-AR`); (2) the main axis, the animated-field rule
(`LR-AS`), the grow half of the re-check, the depth pins and the exit test; (3)
the two proposal-path answers that reach production — `SA-N` item 4 and the
below-word text clamp — each its own commit; (4) the box model; (5) justify
distribution and reverse. **`hidden()` is deferred** (`LR-AV`); W2 goes to task 11
(`LR-AM` as amended). Lanes 1–2 are ordered; 3 is independent of every other
lane; 4 and 5 need lane 1's records.

---

## LR-AP — stage-2 critic round 1: dispositions

**Round.** 2026-09-17, after the stage-2 design commit `5b67545`. Sixteen
findings (1–7 serious, 8–16 smaller). The critic re-ran the stage-1 and stage-2
probes twice each and found both byte-identical to their records; the defects
were in how the design mapped the answers onto legacy fields and MetalUI's code.
New evidence this round, all in record §21's "Critic round 1" section: stage-2
probe revision 2 (groups C2, X11–X18, F9–F10, P7–P9, Y; 235 lines, run twice,
identical); re-runs of the stack-algorithms, accessibility-bridge-rules and
frame-semantics probes; scratch R2 (prototype P3 + `SA-N` item 4, the demo census
and four critic shapes); the `SIGTRAP` experiment; the kernel text measurement at
probe Y's widths. Every scratch was restored (`git checkout Sources`, scratch
tests deleted, `git status --short` showing only the probe) and `swift package
clean` run afterwards.

| # | finding | disposition | where |
|---|---|---|---|
| 1 | an unconsumed item record does nothing silently | **applied**: every item field no lowered container consumes reports `<site>.<field>.unconsumed` | `LR-AQ`; spec §3, 1.13 |
| 2 | stage 1's "no free space" conditions break once stage 2 creates it | **applied, measured** (scratch R2 S1–S3): `space-*` in a grown or stretched unsized container reports; a declared `flexGrow`/`alignSelf` in a one-child container is lowered and its fill pinned against X12/X14 — **not** elided, with the reason | `LR-AR`; spec 1.14, 1.15, 2.11, 2.12 |
| 3 | `flexBasis(0)` dropped CSS's automatic minimum | **applied**: W's minimum only from a declared `minSize`; a sized zero-basis grower without one reports; F9/F10 probed | `LR-AE` amended; spec 2.2, 2.4 |
| 4 | lane 5 changed legacy paint and hitboxes through `display` | **applied by deferral**: `hidden()` leaves stage 2 with corrected constraints for its owner | `LR-AV`; `LR-AK` superseded |
| 5 | a padded text would wrap at the aliased width | **applied**: wraps at the leaf's measured width | `LR-AH` amended; spec 4.2 |
| 6 | animated item fields had no ruling | **applied**: structure from the declared style, values from the animated one; snap pinned with `simulateTick` | `LR-AS`; spec 2.13 |
| 7 | the exit test used literals where text decides a rect | **applied** | `LR-AN` amended; spec §7 |
| 8 | 1.11 could not redden under its mutation and truncated the suite red-before | **applied**: a one-child `Box` added; red-before is a report and a count mismatch that compile | spec 1.11 |
| 9 | stretch arms contradicted `Row`/`Column`'s centring default | **applied, measured** (S4) | `LR-AC`, `LR-AG` amended; spec 1.1, 1.4, 1.12 |
| 10 | designed-in merge collisions | **applied**: one stored `lowering` property; `SA-N` item 4 its own lane and commit, named for the other track | `LR-AT`, `LR-AU` |
| 11 | lane 3 too large; `SA-N` item 4's trap unexplained and unmeasured with W | **applied, measured**: the trap is the test's own pinned-wrong precondition; the census with item 4 on P3 is identical | `LR-AU` |
| 12 | depth budget understated | **applied**: four wrappers per item; depth pins per lane | `LR-AB` amended; spec 2.14, 4.8 |
| 13 | divergence claims with no pin | **applied**: X16 (hugging `Stack`), X18 (main-axis fill, cause R), P7/P8 (BM-4 on `Row`/`Column`) probed and pinned | spec 1.9, 2.10, 4.3 |
| 14 | the below-word answer and W2 deferred on an unprobed premise | **applied**: probe group Y characterizes in-word breaking; the below-word clamp is lane 3's; W2 re-deferred as a stack-allocation question | `LR-AM` amended, `LR-AU` |
| 15 | claims resting on probes not re-run; `LR-AI`'s sentence | **applied**: stack-algorithms (787 lines) and accessibility-bridge-rules (62) re-run identical; frame-semantics D4 identical, its G1 child-proposal sequence differs on this OS (sizes and rects identical); `GeometryReader` arm C2 added and `LR-AI` softened | `LR-AI`, `LR-AK`, `LR-AL`, `LR-AG` amended; record §21 |
| 16 | `measuredWidth(of:)` is `PaintPass`'s; 5.4–5.6 need a `CounterPanel`-specific mutation | **applied** | `LR-AB` amended; spec §5, lane 1 amended pins (M1n) |

No finding is rejected.

---

## LR-AQ — an item field no lowered container consumes reports by name

**Evidence.** Finding 1. At `cb2e708` `legacyLeafDiagnostics`
(`LegacyLowering.swift:331-373`) reports `flexGrow`, `flexShrink`, `flexBasis`,
`alignSelf`, `minSize`, `maxSize` and `margin` whatever the parent is; stage 2
moves the decision to the parent, so a position with no lowered parent — the
root, and a child of `HStack`/`VStack`/`ZStack`, `ProposalFrame`,
`ModifiedContent`, either `.overlay` slot, `ProposalLayoutContainer` or
`ProposalScrollView` — would have silently dropped the fields. A spelling that
compiles and does nothing is the failure CLAUDE.md's inert table exists for.

**The ruling.**

- Every `LoweredItem` carries `consumed = false`. A lowered flex container, stack
  or frame layer sets it for **every** record it receives, whether or not a field
  lowered to a node. A site that reports `<site>.noLowering` (`ScrollView`,
  `List`) sets it for the records it receives too: its own entry already makes
  the tree unlowerable, and the exit test's report must stay exactly
  `[list.noLowering, scrollView.noLowering]`.
- When the root's registration returns, before `computeNativeLayout`, every
  unconsumed record with a non-default item field (`flexGrow != 0`,
  `flexShrink != 1`, `flexBasis != .auto`, `alignSelf != nil`, `minSize`/`maxSize`
  not `.auto`, non-zero `margin`) reports `<site>.<field>.unconsumed`, per field in
  that order, records in registration order. Production traps on the first, as
  every report does.
- The root is not exempt. **One exception, only by measurement**: a field whose
  legacy answer at the root is "ignored" (by reading, `flexGrow`, `flexShrink`,
  `flexBasis` and `alignSelf` — the root is no flex item) lowers as absent if and
  only if lane 1's differential arm shows the two authorities agree for it;
  otherwise it reports. `minSize`, `maxSize` and `margin` at the root always
  report in stage 2 (CSS applies them; a root frame is stage 6b's placement
  ruling).

**What it costs if wrong.** A proposal-path author who writes a legacy item
modifier under an `HStack` gets a trap under the proposal authority instead of a
no-op; stage 8's recipe respells it. If a `noLowering` site fails to mark its
records, a tree already unlowerable by site also reports its fields; 1.13's
`ScrollView` arm pins the marking (mutation M1m′), and the exit test shows whether
the demo reaches it.

---

## LR-AR — a parent re-checks the free space it creates; the one-child elision is for stretch only

**Evidence.** Finding 2, measured with scratch R2 (P3 + `SA-N` item 4, record
§21), legacy → lowered, the report empty in every shape:
- **S1** `Row { Row { a20; b20 }.justifyContent(.spaceBetween).flexGrow(1); c40 }.width(300)`:
  b at x 240 → 20. Stage 1 lowers `space-*` on a container with no declared main
  size as flex-start because it has no free space; W gives it some.
- **S2** `Row { a40; x30.flexGrow(1).padding(8) }.width(200)`: the padding layer
  46×26 → 160×26, x 30 → 144 wide. SwiftUI's spelling answers the same fill
  (stage-2 probe X12: 160 against control X11's 46).
- **S3** `Column { a100; x20.alignSelf(.flexEnd).padding(8) }` in a 300×100 root:
  the padding layer 36×26 → 36×90, x at y 18 → 82 (the layer is a row `Box`, so
  x's `alignSelf` is vertical). SwiftUI's transposed spelling fills too (X14: an
  indefinite `VStack` 300 against X13's 100, b at the trailing 272).

**The ruling.**

- **Justify.** When a parent registers W greedy on a child's **own** main axis
  (grow along a parallel axis, stretch across a perpendicular one) and the child's
  record is a flex container with `justifyContent` `spaceBetween`/`spaceAround`/
  `spaceEvenly` and no declared main size, the parent reports
  `<child site>.justifyContent.<case>` (stage 1's string) at the child's position
  in its child reports. `flexStart`/`center`/`flexEnd` need nothing: W's content
  alignment carries the main factor (1.2, 2.1). Lane 5 does not change this: a
  child cannot register spacers before it knows it is grown, and spacers in a
  hugging container would fill it (X4).
- **Grow and `alignSelf` in a one-child container are lowered, not elided.** Both
  are fields an author declared; the fill is SwiftUI's answer for the SwiftUI
  spelling (X12, X14). Eliding grow would break the legacy idiom CLAUDE.md
  prescribes — "`.flexGrow(1)` before `.padding`" — wherever the padding layer is
  itself grown: by reading `demoContent()` (lines 902–905, the main pane's
  `.flexGrow(1).padding(16).flexGrow(1)`), the main column would stop filling its
  pane. Each fill is a **new divergence**, pinned: 2.11 (S2) and 1.15 (S3).
- **Stretch keeps the elision** (`LR-AC`, stage 1's `LR-E` principle 3): a
  padding layer's stretch is the `Box` default, which no author wrote.

**What it costs if wrong.** An unsized `space-between` row that is grown traps
under the proposal authority until an author sizes it or stage 8 respells it. A
legacy `x.flexGrow(1).padding(8)` in a hugging parent widens the padding to its
proposal under the proposal authority; stage 6b's demo re-spelling meets none
(every demo instance sits in a grown or sized layer).

---

## LR-AS — animated item fields: structure from the declared style, values from the animated one

**Evidence.** Finding 6. `AnimatedStyle.swift:381-396` interpolates `flexGrow`,
`flexShrink` and `margin`; `LoweredItem` carries both styles. Stage 1's `LR-H`
already reads a frame layer's bounds from the animated style.

**The ruling.**

- **Structure reads the declared style**: whether `fixedSize`, W, the alignment
  frame and the margin padding exist, on which axis W is greedy, the alignment
  frame's factor, the weights check, the zero-basis and unconsumed checks, and
  every report.
- **Values read the animated style**: W's `minSize`/`maxSize`, the margin
  padding's insets, and (stage 1) the element's own frame.
- Consequences, each a **new divergence** from the legacy engine (no SwiftUI claim:
  SwiftUI has no `flexGrow`): `withAnimation { flexGrow 0 → 1 }` snaps W greedy on
  the frame the change is declared, where legacy grows through intermediate
  factors; `(1 → 2, 2)` lowers equal at every tick, where legacy distributes
  unequally mid-flight. Neither traps: the weights check never sees an animated
  factor. Pinned by spec 2.13 through `WindowPair`, driven by `simulateTick`
  (no sleep). The integrator adds both to CLAUDE.md's snap list.

**Amended, stage-2 lanes 2 and 4 (`LR-AX` item 3, `LR-AZ` as amended).** Two
corrections to the pin half. (1) **Not `WindowPair`:** a parked transaction is
consumed by exactly one frame build, so two windows driven together cannot both see
it; spec 2.13 drives **one fake window per authority, in turn**
(`animatedWidths(_:ids:_:)`), which is what landed. (2) **The values half has a
second path, and it was unpinned until after lane 4's verification.** `margin`'s
insets are not read through the `style` argument `paddedAndSized` receives — the
argument spec 2.3c pins as the animated one — but through `planLegacyItems`'
`plan.marginInsets`, four `marginEdge(a.margin.…)` calls of its own; reading the
declared style there passed the whole 1450-test suite (verifier mutation **V4n**).
Spec 4.9 (`aLoweredMarginRegistersItsAnimatedValue`) is the arm that sees it: a
margin going 0 → 40 under `withAnimation(.linear(duration: 1))` reads 0 at the
transaction's first frame and **20** half-way, on both authorities. `Style.border`,
lane 4's other new animated consumer, needs no arm of its own: it is read from the
same single `style` argument, in a function with no declared style in scope, so the
only mutant that can reach it is the call site 2.3c already reddens.

**What it costs if wrong.** An animated grow or shrink factor jumps under the
proposal authority; stage 6b's demo has none (the **A** look animates a width and
a colour).

---

## LR-AT — the lowering's frame state is one stored property, in its own file

**Evidence.** Finding 10. The design appended stored properties to `Frame` in
three lanes; the parallel track appends to the same class, and `bounds(of:)`
(`Frame.swift:1709`) and `PaintPass.measuredWidth(of:)` (`Passes.swift:607`) are
one-line hot spots either track may touch.

**The ruling.** `Frame` gains exactly one line, `var lowering = LoweringState()`,
in lane 1; `LoweringState` (`Sources/MetalUI/LoweringState.swift`, new) holds the
item records, the bounds aliases and lane 4's text leaves, and gains fields there
rather than on `Frame`. `bounds(of:)` and `measuredWidth(of:)` each change by one
expression, `frame.lowering.alias(node)`. The record names both lines for the
integrator. `swift package clean` still follows lane 1 (`Frame` is public and
crosses a module boundary).

**What it costs if wrong.** Nothing semantic: a textual merge conflict on one
line instead of three blocks.

---

## LR-AU — the proposal-path answers that reach production are one lane, each its own commit: `SA-N` item 4 and the below-word text answer

**Evidence.**

- **The `SIGTRAP` is the test's own pin** (finding 11). With `placeNative`'s
  `.padding` case placing the child at its measured size, a native build, then
  `swift test --filter negativePaddingIsAcceptedAndItsResponseClampsPerAxis`:
  `.success → .signal(SIGTRAP)`. With the same change and that test's
  pinned-wrong precondition (`clampedRect.width == 30 && … == 30`) set to SwiftUI's
  20×20: `Test run with 1 test … passed`. The trap is the precondition the test's
  doc comment says "reddens deliberately" when task 5 fixes item 4; nothing else
  fires.
- **Item 4 measured with W** (finding 11): P3's patch plus the change, the demo
  census: 2036 / 6 agreeing / 30 disagreeing (modal on 2042 / 6 / 36), report
  `[list.noLowering, scrollView.noLowering]` (modal on with `stack.position`,
  `stack.inset`), and every rect pair identical to P3's run without it.
- **The below-word answer** (finding 14). Stage-2 probe Y: SwiftUI's lines equal
  CoreText's line-break loop at ten widths; its width is `min(proposal,
  ceil(widest line with its trailing space))`. `proposalTextMeasurement` at the
  same widths (scratch, 13pt system font): the same line counts in every arm, and
  widths 32.84, 18.17, 18.17, 10.31, **7.86** (Y5 at 5), 17.25, 17.25, **33.31**
  (Y8 at 30), 44.02; at 0 (T3) **11.18**. The bold three are the missing clamp;
  the rest differ from SwiftUI only by the ceiling, which the kernel leaves to
  rect rounding (stage-1 record: 45/33 against SwiftUI's 46/34).

**The ruling.** Lane 3 has two commits, each with its own full suite:
1. **`SA-N` item 4**: the `.padding` case places the child at origin + leading/top
   inset at its measured size; `negativePaddingIsAcceptedAndItsResponseClampsPerAxis`
   is re-derived to 20×20; the kernel test 3.1 pins it. The record names this
   commit for the other track: any padding test written against bounds minus
   insets must be re-checked after the merge.
2. **The below-word clamp**: `proposalTextMeasurement` answers
   `min(proposal.width, widestLine)` for a concrete width (unchanged at nil).
   `aProposalTextBelowItsNarrowestWordAnswersItsWidestCharacterWhereSwiftUIAnswersTheProposal`
   (stage 1's 2.7) is re-derived to the proposal and renamed; divergence 59 closes
   (the integrator edits the table). The ceiling is not taken.

Both reach the preview (a production proposal root). Expected: **0 differing
pixels** in both preview images after each commit (stage 1's scratch of item 4
read 0 in all twelve; the preview's texts are not proposed below a word at its
default size — a prediction). A non-zero preview image stops the lane and comes
back as a ruling before the commit, per the brief: the preview may move only
where a probe-backed kernel change moves it.

**What it costs if wrong.** Item 4 changes every proposal padding's stored child
rect (hit testing and paint of a padded proposal element when the padding is
placed larger than its answer); the clamp changes a text's width below its word
in every proposal stack. W2 stays disagreeing (`LR-AM` as amended).

---

## LR-AV — `hidden()` is deferred out of stage 2, with constraints for its owner

**Evidence.** The five-lane cap after `LR-AU` split lane 3; finding 4 (the design's
`isHidden` read `display == .none`, true for every legacy `hidden()`, so its paint
and hitbox skips would have changed production, and `AnyElement` would have gained
accessibility suppression on the legacy path); finding 10 (its hooks sit in
`ElementGroup.swift`'s group defaults and `ModifiedElement`'s per-layer mirror,
`MC-B`, the files the parallel track is most likely to touch). No production
source calls `.hidden()` (grep: three doc-comment hits in `Box.swift`); 42 test
uses in 8 files.

**The ruling.** Under the proposal authority `display.none` keeps reporting by
name. The owner is **task 7, before stage 9** (stage 9 deletes the legacy
authority those tests would otherwise be pinned to) — proposed to the integrator
as stage 5's companion, whose `Deferred` presentation root needs the same subtree
gates; focus and keys under `hidden()` stay task 12's. The design it inherits:
`LR-AK`'s evidence, plus
- the paint skip and the hitbox scope read **`hiddenNodes` only** (nodes the
  proposal lowering marked), so the legacy path paints and hit-tests exactly as
  today until the inert-table row "layout filters it, paint does not" is ruled on
  by its own change with legacy-side pins;
- accessibility suppression may read `display == .none || hiddenNodes`;
- `AnyElement`'s missing `suppressingAccessibilityIfHidden` (record §18) is a
  **legacy production change** and needs its own legacy pins for paint, hitbox and
  accessibility; the integrator hands the row;
- the former tests 5.1–5.5 plus those legacy pins.

**What it costs if wrong.** A proposal-authority tree containing `hidden()` traps
until the owner lands; stage 6a's flipped-default census classifies the 42 test
uses; production content has none.

---

## LR-AW — stage 2 lane 1's corrections: W's minimum, where unlowered item fields report, the unconsumed check's reach, and the test shapes the harness root forces

**Evidence.** Record §21, lane 1: the red run on the stage-1 lowering (1424 tests,
17 red, every legacy-side literal passing), the implementation's first full run
(1424, 7 red — exactly the pins below), stage-2 probe revision 3 (Z0/Z1, run twice,
byte-identical), and the lane's mutations.

**The rulings.**

1. **W's minimum is 0 on a stretched axis when the item declares none.** CSS's
   stretched cross size is the line's, below the item's content if the line is
   smaller (the content overflows); a bare `.frame(maxHeight: .infinity)` never
   answers below its child (stage-2 probe Z0: 20×50 in a 30-tall row) and
   `.frame(minHeight: 0, maxHeight: .infinity)` answers the line (Z1: 20×30, the
   child overflowing) — F4's presence rule on the cross axis. So W is
   `frame(min: declared minSize ?? 0, max: declared maxSize ?? ∞)` on that axis,
   the SwiftUI spelling whose answer is CSS's; a declared maximum below the minimum
   is raised to it (CSS's minimum wins; the kernel would trap on `min > max`).
   Pinned by 1.4's stretched arm (a row stretched to 40 over a 60-tall minimum
   child: 40 on both sides), mutation **M1r**.
2. **Item fields lane 1 does not lower are reported by the consuming parent**, at
   the child's site under the stage-1 names — `flexGrow`, `flexShrink`,
   `flexBasis`, `alignSelf.baseline`, `minSize`/`maxSize` off a stretched axis (or a
   percentage on one), `margin` — after the parent's own rows (spec §4's order),
   each child's in `LR-AQ`'s field order. **A reporting element still records its
   item** (except `display: none`, reported alone, `LR-J`), so its own item fields
   are reported by its parent: the whole demo reports each field once (5.3's
   13-entry literal). A frame layer over one node is a stack parent: it ignores the
   flex fields and reports a child's `minSize`/`maxSize`/`margin`, as the child
   itself did in stage 1.
3. **The unconsumed check lands in lane 1, so every item field under the harness
   root reports `…unconsumed`** (the root is a proposal overlay). The spec listed
   five amended pins; seven moved: 1.5 (`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`:
   arms re-spelled with `position` and `inset`), 2.3 (item rows `…unconsumed`, and
   seven in-`Row` arms per site for the consumed names; 51 arms), **2.3b** (lane 2's
   amendment to `size.percent` + `inset` taken now), 3.5 (the stretch arms agree, a
   container's `margin` is unconsumed; **name kept** — its `space-*` half is still
   the subject until lane 5), **3.9** (re-spelled `[reverse, flexWrap, position,
   inset]`), 4.1 (the two stretch arms moved to 1.9; `margin` unconsumed) and 5.3 (an
   exact ordered literal). Stage 1's M3f and M5c mutated a stretch row that no
   longer exists and are retired.
4. **The root exception, measured**: 1.13's root arms compare a legacy frame root
   with and without each field; the legacy root ignores `flexGrow(1)`,
   `flexShrink(0)`, `flexBasis(0)` and `alignSelf(.flexEnd)` (recorded literal), so
   those lower as absent at the root; `minSize`/`maxSize`/`margin` report. Mutation
   **M1u** (the root not exempt).
5. **`alignSelf(.stretch)` on an item with a declared cross size** sits at the
   start in CSS; in a centring parent it gets an alignment frame at factor 0 (1.5's
   third child). The alignment frame is registered wherever the child's factor
   differs from the parent's, not only for a non-`nil`, non-`stretch` `alignSelf`.
6. **Test shapes the harness root forces** (spec §6 lane 1 amended in place):
   the kernel offers a lowered item a concrete cross proposal wherever a root
   proposes one, and a stack serves a group of one its whole finite main proposal —
   there is no nil-offer in a lowered tree — so "an unsized parent whose line is
   its tallest sibling" (X1) cannot agree under the harness root. 1.1's unsized arm
   is a parent stretched to 60 by a sized grandparent; 1.4, 1.8 and 1.14 declare the
   container's size; 1.6 and 1.7 keep the design's `Row { … }` spelling (the row
   offers its whole width). 1.3's middle container is a **column** `Box` (in a row
   `Box` the child's width is its main axis, 0 on both sides). 1.4's literal was
   wrong: a 60 minimum on a 100 line is 100 (the 60 is the stretched-to-40 arm).
   1.9's X16 arm needs `nil` items (`Stack(alignment:)` never stretches).
7. **`CounterPanel()` needs a lowered flex parent** in 5.4–5.6: directly under the
   harness root its chrome's `alignSelf` is unconsumed. `Column { CounterPanel()
   }.width(400)`: 9 elements.
8. M1d (the elision removed) and M1l (W also for an elided single child) are one
   edit in this implementation; the record runs it once under both names.

**What it costs if wrong.** (1) A stretched item whose content exceeds the line
paints past its W where a greedy frame without a minimum would have grown the line;
the alternative disagrees with the legacy engine and hides the overflow. (2) A
reported tree's census lists more entries than the fields an author must fix first;
production traps on the first either way. (3) An author placing a legacy element
with an item field directly under a proposal container gets a trap naming
`…unconsumed`, which is the ruling's intent (`LR-AQ`).

---

## LR-AX — stage 2 lane 2's corrections: arms the design spelled that could not show their subject, the re-check's reach, negative factors, and how the animated and depth pins are driven

**Evidence.** Record §21, lane 2: the red run on lane 1's lowering (1439 tests, all
16 lane-2 tests red, every legacy-side literal passing), the legacy measurements
taken before the literals were written (scratch, deleted), the implementation's first
full run (1439, 9 issues in 4 tests — three amended pins and one test's own
spelling), 43 mutations each reddening named tests, the stage-2 probe (revision 3,
243 lines) and stack-algorithms probe (787 lines) re-run twice / once this lane,
identical to their records.

**The rulings.**

1. **2.4's sized-container arm is re-spelled.** The design's arm (`Row { a40; b40 }
   .width(200).justifyContent(.flexEnd)…` in a 150 share) cannot show the
   divergence it names: the element's own 200 frame sits in W at the row's content
   factor f and its rigid content at f again inside it, so every child lands at
   f·(150 − 200) + f·(200 − 80) = f·(150 − 80) — CSS's position under any one
   factor. A **grower** inside can: `Row { a40; g.flexGrow(1) }.width(200)…` lays g
   out 160 wide lowered (at the declared 200) against legacy 110 (in 150), the item
   rect agreeing at 150.
2. **2.5's sibling declares `flexShrink(0)`.** Measured before the literal: legacy
   shrinks a childless `Box().width(50)` beside a max-content text to **0** (its
   automatic minimum is its content's), where the lowered row keeps a declared 50
   rigid — divergence 55, already pinned by 2.6 and 2.9, not 2.5's subject.
3. **2.13 is driven one window per authority, in turn, not through `WindowPair`.**
   `withAnimation`'s parked transaction is consumed by exactly one frame build
   (CLAUDE.md, Animation), and `WindowPair`'s one `make` closure cannot give each
   window its own model. Each state is still pre-flighted through
   `LayoutDifferential.compare` (`LR-AA`). **Arm B is `(0 → 2, 2)`, not `(1 → 2, 2)`**:
   the design's start state reports `flexGrow.weights` and would trap the proposal
   window before any tick; (0 → 2, 2) starts with one grower and is unequal
   mid-flight all the same. **Arm B runs in a child process**, because its mutation
   (M2o) makes a production window trap mid-flight, which in-process ends the run
   with no summary line (practices shape 13). **Arm C's row declares 300** beside a
   rigid 260: the design's "hugging row" is offered the harness root's width and a
   grower fills it (cause R).
4. **The free-space re-check covers any W on the child's own main axis**, not only
   a greedy one: a declared `minSize` on an unsized `space-*` container is W's
   floor, and a floor above the content is free space CSS distributes (legacy b at
   180 in `Row { Row { 20; 20 }.justifyContent(.spaceBetween).minWidth(200); 40 }`)
   where the lowered stack would pack from the start. It reports; 2.12's minimum arm
   pins it (M2m′). `LR-AR` is extended, not changed.
5. **A negative `flexGrow` or `flexShrink` reports `flexGrow` / `flexShrink`.** CSS
   rejects both; lowering them as absent would be silent. The leaf report test's
   in-`Row` arms, whose positive grow and zero shrink now lower, are re-spelled to
   the negative values (M2r).
6. **Report order**: `flexGrow.weights` (at the parent's site) comes first among a
   container's child reports, before any child's own fields. **A percentage
   `minSize`/`maxSize` keeps stage 1's `minSize`/`maxSize` name**; lane 4's 4.7
   renames it `…percent`.
7. **W on a declared axis.** A grown item with a declared main size keeps its size
   (folded with its own `minSize`/`maxSize`) on its own frame; W is greedy with the
   declared maximum and a minimum only for a zero basis with a declared minimum
   (`LR-AE` as amended). A non-greedy `auto` axis with a px/rem minimum registers W
   with that minimum and no maximum (a floor), in a stack parent too.
8. **2.14's shape** — 21 nested `Row`s, each inner row declaring `flexShrink(0)`,
   `flexGrow(1)` and `alignSelf(.flexEnd)` beside a fixed 10×10, the outermost a
   sized production root — reaches **88** native levels exactly with a sized, padded
   leaf innermost and **89** with a padded one-child container innermost, so the
   pair pins the boundary to one level (stage 1's 5.8/5.9 bracket 87–90). Node counts
   130 and 131, derived by hand. The whole demo's deepest native run under the
   proposal authority is **18** in both modal states (scratch counter in
   `NativeLayoutRun.enter`, restored; stage 1 measured 12).
9. **2.15 asserts the modal's six ids by presence only** (their rects are stage 5's
   `position`/`inset`), and the `List`'s two ids one index later when the modal is
   shown. The 30 modal-off pairs are asserted in both states. Stage 1's M1t (the
   parent's `flexGrow` report dropped) is retired: the report no longer exists.
10. **A builder `if`/`else` at the harness content's top adds an id level**: 2.1's
    first spelling put its container one level down and found no rect at
    `child(containerID, 1)`; the arm is spelled with `AnyElement` instead. Measured
    (scratch, deleted): `if flag { Row { a; b } } else { Column { … } }` under the
    harness root records the row at `0/0/0` and its children at `0/0/0/0` and
    `0/0/0/1` — the branch's own `0/0` records no rect.

**What it costs if wrong.** (1)–(3) are test shapes: a wrong one leaves a divergence
unpinned, which the named mutations check. (4) A floored `space-*` container traps
under the proposal authority until stage 8's recipe respells it. (5) An author's
negative factor traps instead of being ignored. (8) Raising `maxDepth` or adding a
fifth wrapper per item moves both depth pins; lane 4 re-derives them with a margin.

---

## LR-AY — stage 2 lane 3's corrections: which string each probe-Y arm holds, the shape that can actually reach the padding placement, and what the lane measured that the design predicted

**Evidence.** Record §21, lane 3: the stage-2 probe re-run twice this lane (254
lines, byte-identical, filtered stderr empty, matching its revision-4 header); the
red runs of both commits; the kernel's own answers at probe Y's nine widths,
dumped from a scratch test before any literal was written (scratch deleted); two
full suites (1440, then 1441, 0 `error:`/`warning:`); three mutations (M3a, M3b,
M3c) each reddening named tests; and two twelve-image `CN-R` comparisons against
`cb2e708`, one per commit.

**The rulings.**

1. **Probe group Y holds three strings, not one, and 3.4 must say which.** The
   design's row reads "probe Y's strings and widths (Y1–Y9)" and gives the line
   counts 1, 2, 2, 4, 5, 2, 2, 12, 7 without pairing an arm to a string. Y1–Y5 are
   `Text("alpha")`, Y6–Y7 `Text("Short")`, Y8–Y9 the sentence; the probe's labels
   say so (`Y1 Text(alpha) at 33`) and its `arms` table is the authority. A first
   pass read all of Y1–Y5 as the sentence and the kernel answered 10, 13, 16, 28
   and 37 lines against the design's 1, 2, 2, 4, 5 — **a red test that looked like
   a finding about the engine and was a misread table**. With the three strings in
   place every line count is the probe's exactly and every widest line matches the
   probe's printed CoreText reading to two decimals (32.84, 18.17, 18.17, 10.31,
   7.86, 17.25, 17.25, 33.31, 44.02). The lesson is the general one: when an arm
   table is red, dump what the code answers before deciding which side is wrong.
2. **Exactly two of the nine arms can see the clamp, and the test pins that
   count.** Only Y5 (7.86 against a 5 proposal) and Y8 (33.31 against 30) have a
   widest line above their proposal; the other seven hug and would pass under any
   clamp or none. 3.4 carries `try #require(clamped == 2)` computed from the cache,
   so an arm table edited to all-hugging arms fails loudly instead of passing
   vacuously (practices shape 15). M3b confirms it: with the clamp removed both 3.3
   and 3.4 redden.
3. **3.1's shape is the clamped response in a stack and the caller-bounds entry,
   not a custom `ProposalLayout`.** The design proposed "a custom `ProposalLayout`
   placing it at 100×100". A custom layout's `place(at:anchor:proposal:)` stores a
   subview at **its own answer** (`SA-C`), so a custom parent cannot hand a padding
   bounds larger than its answer and cannot show the change at all. Two shapes can:
   a padding whose **response clamps** — `HStack(spacing: 0) { a20×20.padding(−15);
   b20×20 }`, where the pad answers 0×0 and the child is still 20×20 rather than
   the rect-minus-insets 30×30 (probe N1, and the shape a lowered element reaches
   in production) — and `computeNativeLayout(root:proposal:in:)`, the one entry
   that places a node in bounds of the caller's choosing (`CN-J`). The third arm
   (N2, a proposal-filling child under asymmetric insets) is the control both rules
   agree on and must NOT move.
4. **SwiftUI ceils its text answer and MetalUI does not; the widths come from the
   shaping cache.** Y2 reads 19 against 18.17 and Y9 45 against 44.02. That is
   `LR-F`'s rule applied, not a new divergence: the clamp is `min(proposal,
   widestLine)` in Double, and the probe's printed integers are its ceiling. A
   literal-for-literal test against the probe would have failed for the rounding
   and hidden the clamp.
5. **What the design predicted, this lane measured.** The preview images were
   expected at 0 for commit 1 (from stage 1's scratch) and at 0 for commit 2 **by
   prediction**. Both read 0, and so did all twelve images at both commits, scenes
   identical — so neither production answer reaches a production root's pixels. The
   exit test (2.15) re-ran unchanged at both commits, as did the 97 goldens. The
   `SIGTRAP` `LR-AU` measured is exactly what commit 1's red run showed: 3.2 exits
   on its own pinned-wrong precondition and passes once it reads 20.
6. **Divergence 59 closes here, not in task 11.** `LR-AM` as amended already
   assigned the below-word clamp to this lane; commit 2 lands it, so critic finding
   14's consequence — "stage 6b ships divergence 59 to production" — does not
   arise. **W2 stays deferred** to task 11 as a stack-allocation question, untouched
   by the clamp.

**What it costs if wrong.** (1) and (3) are test shapes: a wrong one leaves the
change unpinned, which M3a and M3b check. (2) Without the count the arm table can
rot into arms that cannot fail. (4) Adopting SwiftUI's ceiling would move every
lowered text rect by up to a point and is a separate decision with its own pixels.
(6) If a later stage finds a below-word shape the clamp answers differently from
SwiftUI, divergence 59 reopens with task 11's owner.

---

## LR-AZ — stage 2 lane 4's corrections: the legacy box under the `BM-4` floor, the stack's indifference to margins, what an `.auto` margin can be seen by, and the pin lane 3 retired

**Evidence.** Record §21, lane 4: the stage-2 probe re-run twice this lane (254
lines, byte-identical, filtered stderr empty, matching its revision-4 header); a
scratch differential that dumped the **legacy** answer for every shape in the lane
before a literal was written (deleted before the red commit); the red run (`Test run
with 1450 tests in 1 suite failed after 45.717 seconds with 72 issues`, exactly the
nine lane-4 tests); the implementation's first full run (three pins to amend and
nothing else); a clean-build suite of 1450 passing; twelve `CN-R` images at 0
differing pixels with the stage-1 controls; and the mutation table below.

**The rulings.**

1. **The legacy border box under the `BM-4` floor is 24×24, not probe P1's 34×34,
   and a centring container puts the child *outside* the padding's inner edge.** The
   design's 4.3 row predicted "legacy 34×34 with the child at (12, 12) in all
   three". Measured: a 10×10 box padded 12 is **24×24** — `max(specified, padding +
   border)`, so the content box is 0 on each floored axis — and the child of a
   `Row` sits at (12, **7**) and of a `Column` at (**7**, 12), because a 10-tall
   child centred in a 0-tall content box starts 5 above it. 34×34 is SwiftUI's
   *padding* geometry from P1, which is a different box from the legacy element's.
   The lowered answers (10×10 with the child at (12, 12) / (12, 0) / (0, 12)) are
   the design's and were confirmed. The general lesson is stage 1's: a probe reading
   is evidence about SwiftUI, never about the legacy engine — the differential is
   the only source for the other side.
2. **A `Stack` and a `.frame` layer ignore a child's margin entirely, so the
   lowering ignores it too.** Spec §4.1's `margin` row said a stack parent lowers it
   "the same" as a flex parent. Measured on the legacy engine: `Stack { 20×10
   .margin(2, 3, 4, 5); 30×20 }` is 30×20 — the *other* child's size, so the margin
   box does not enlarge the stack — with the margined child centred at (5, 5) by its
   **border** box, where a margin-aware centring would put it at (6, 4); at a
   symmetric margin 20 the stack is still 30×20. A `.frame(width: 80, height: 60)`
   layer over a margined child places it at (30, 25), the margin-blind answer, not
   (31, 24). A stack parent therefore plans no margin padding **and reports
   nothing** — the margin is lowered as absent because the legacy engine treats it
   as absent, which is the same disposition `alignSelf` already has there (`LR-AD`).
   A symmetric margin cannot tell the two hypotheses apart; the measurement that
   settled it used a distinct value per edge.
3. **An `.auto` margin's lowering is only visible through `LR-AQ`'s unconsumed
   report.** `margin: .auto` resolves to 0 on both axes, so counting it as a margin
   registers a native padding whose insets are all 0: one node more, the same
   geometry, no report. Mutation **M4g** (`LoweredItem.hasMargin` counting `.auto`)
   therefore left the **whole suite green** on 4.6's first spelling. 4.6 gained a
   second arm — the same box directly under the harness root, where no lowered
   container consumes its record — and there the difference is a report:
   `.auto` must report nothing where a px margin reports `margin.unconsumed`. The
   general shape is practices' "a mutation that reddens nothing is a broken
   instrument or the finding": here it was the instrument, and the arm that can see
   it is not the arm that shows the behaviour.
4. **Lane 3's below-word clamp retired lane 1's M1k pin, and nothing in lane 4 can
   restore it.** M1k (the bounds alias resolved in `Frame.bounds(of:)` but **not**
   `PaintPass.measuredWidth(of:)`) left the suite green again. Attributed by
   measurement, not by argument: with lane 3's commit-2 clamp reverted **and** M1k
   applied, `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap` (1.10)
   reddens again (1 issue) alongside lane 3's own 3.3 and 3.4. The reason is
   structural: `proposalTextMeasurement` now answers `min(proposal, widestLine)`, so
   a lowered text leaf can never be wider than the item frame that proposed to it,
   and re-wrapping at a hugged width reproduces the same greedy breaks — which was
   exactly the window lane 1 opened at a 4-wide column. Lane 4's padded path does
   not reopen it either: `Text.paintGlyphs` asks for the **leaf's** node, which
   carries no alias. **The alias in `PaintPass.measuredWidth(of:)` is therefore
   redundant as the code now stands**; it is kept because it states the intent
   `LR-AB` item 3 gives (a grown or stretched box *is* the bigger box, and the width
   to measure at is its), and because deleting it is a behaviour change nothing
   would catch. The integrator inherits the choice: keep it as intent, or delete it
   with `LR-AB` item 3 amended. `Frame.bounds(of:)`'s alias — the load-bearing half
   — stays pinned by M1a, which reddens 26 tests.
5. **`padding.floor` and `padding.text` leave the report, `border` becomes
   `border.percent`, and three stage-1 pins move with them.** 2.2's floor arm now
   asserts the divergence instead of the report (legacy 16×16, lowered 10×10); 2.3's
   every-node table drops `padding.floor` (both axes and both combined arms),
   `padding.text` and `border`, gains `border.percent` and a combined
   percent-padding-and-border row, and renames its consumed `minSize` and `margin`
   arms `minSize.percent` and `margin.percent` — 46 arms, from 51; 3.5's container
   arm swaps `padding.floor` for `border.percent`. Every one of those was found by
   the implementation's first full run, not predicted.

**Amended after the lane's verification.** Item 2's claim — a `.stack`, `.leaf` or
`.frameLayer` parent plans no margin padding — and lane 4's renaming of the `border`
report to `border.percent` (item 5) each carry a mutation of their own, added to
record §21's lane-4 table by the verifier: **V4j** (a stack or frame-layer parent
plans the margin like a flex parent, i.e. this item reversed) reddens 4.4 with 4
issues, and **V4q** (the `border.percent` entry removed) reddens 2.3 (4), 4.7 (1)
and the container inventory (1). A sixth ruling follows from the same round:
6. **`plan.marginInsets` reads the animated style, and that read now has its own
   arm.** See `LR-AS` as amended: mutation **V4n** left the whole suite green, and
   spec 4.9 closes it. Stage 1's mutation **V3** (the height half of the
   `padding.floor` check deleted) is **retired** by item 5 — the branch it targets no
   longer exists — and 2.3's doc comment no longer cites it.

**What it costs if wrong.** (1) A wrong legacy literal would have made 4.3 a pin on
a fiction, and the divergence it names is the one stage 6b ships to production. (2)
If the legacy stack does honour margins in some shape this lane did not reach, a
`Stack` child's margin silently vanishes under the proposal authority rather than
reporting — the failure mode `LR-AQ` exists to prevent; the mitigation is that the
same shape disagrees in the differential, which is what 4.4's stack arm checks. (3)
Nothing: the behaviour is identical either way, only the report differs. (4) If the
alias is deleted and a later stage reintroduces a leaf that can answer wider than
its proposal, a padded or stretched text re-lines at paint with no test to see it.
(5) A renamed report is a spelling stage 8's recipe reads; a wrong name sends a call
site to the wrong owner.

---

## LR-BA — stage 2 lane 5's corrections: the overflow fallback the legacy engine actually takes, the arrangement's third return value, and the shape that can show a mispaired item plan

**Evidence.** Record §21, lane 5: the stage-2 probe re-run twice this lane (254
lines, the two runs byte-identical and identical to its header's OUTPUT block line
for line, filtered stderr empty, `exit 0`); three rounds of a scratch differential
that dumped the **legacy** answer for every shape in the lane before a literal was
written (deleted before the red commit, `git status --short` clean); the red run
(`Test run with 1459 tests in 1 suite failed after 48.683 seconds with 145 issues`,
exactly the eight lane-5 tests that are not characterization); the implementation's
first full run (15 issues: two pins to amend and one literal of the lane's own);
a passing suite of 1459; twelve `CN-R` images at 0 differing pixels with the
stage-1 controls exactly, the two-authority chrome pair at 0 and its M5d control at
8 214; and the mutation table below.

**The rulings.**

1. **`space-around` and `space-evenly` overflow to `flex-start` in the legacy
   engine, not to CSS's `center`, so spec 5.3 is not a divergence pin.** The design
   predicted one from probe J9 (SwiftUI packs overflowing spacers from the start)
   against CSS's documented fallback to `center`. Measured, three `.flexShrink(0)`
   20s in a 40-long container: **0, 20, 40 for `spaceBetween`, `spaceEvenly` and
   `spaceAround` alike** — because `Alignment.swift`'s `distributeMainAxis` clamps
   its free space with `max(0, freeSpace)` in all three cases, so a negative free
   space distributes nothing. The lowered spacers answer the same, so 5.3 became an
   **agreement** arm, renamed
   `spaceAroundAndSpaceEvenlyOverflowFromTheStartOnBothPaths`, with the overflow
   itself (content 60 past a 40 container) as its `try #require`. The legacy
   engine's own disagreement with CSS there is pre-existing, is encoded by no
   golden, and is handed to the integrator rather than pinned here. The general
   lesson is `LR-AZ` item 1's again, in the opposite direction: a CSS *reading* is
   evidence about the spec, never about this engine.
2. **The design's `arrangeLegacyMainAxis(_:_:) -> (nodes:, mainFactor:)` returns a
   third value, the stack's spacing, and the factor is also available on its own.**
   A distributed container's stack spacing must drop to 0 (a spacer already carries
   the gap as its minimum, or a rigid leaf carries it), so the predicate "is this
   container distributing?" decides the spacing too and the caller cannot recompute
   it without duplicating the predicate. The signature is therefore
   `arrangeLegacyMainAxis(_ items:, declared:, animated:) -> (nodes:, mainFactor:,
   spacing:)`. Its `mainFactor` half is also needed **before** the diagnostics
   bail-out, where no node may be registered (a reported container still records its
   content alignment for its parent's item frame), so the mirroring lives in a
   separate `legacyMainFactor(_:)` that registers nothing and the arrangement calls.
3. **`alignSelf` cannot be the field that makes 5.7's item plans differ.** The test
   needs three children whose item plans are distinguishable, so that mutation
   **MJh** — the reversal applied before the wrappers, pairing each child with a
   sibling's plan — is visible. The design's obvious choice, one child with
   `.alignSelf(.flexEnd)`, made the **forward control** disagree: in a row with no
   declared cross size the greedy alignment frame hugs where the legacy line places
   at its end, which is lane 1's own divergence (1.6, probe X7). Measured, then
   replaced by a grower / plain / `minWidth`-floored trio, whose forward control
   agrees in every observation and whose plans are W-greedy-on-main / none /
   W-with-a-minimum. MJh reddens 5.7 and nothing else.
4. **MJd is the end spacers' minimum, not "the overflow centred".** The design named
   5.3's mutation "the overflow centred". No spacer lowering can express that: the
   spacers fill the stack, so the container's own main alignment factor has no free
   space to place and changing it moves nothing. The mutation run instead is the end
   spacers given the platform default minimum (`nil`, 8) in place of 0, which moves
   only the overflowing arms — a fitting spacer's share is far above 8 — and reddens
   5.3 (6 issues) beside 5.1 (8) and 5.4 (2).
5. **`stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` is
   renamed, and `fourFieldContainer` loses `reverse`.** Lane 1 kept the first name
   because its `space-*` half was still reported; this lane lowers that half too, so
   both halves of the name are false and it is renamed
   `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName` — the container
   table's inventory, whose five `space-*` and reverse arms stay in place expecting
   `[]` (their rects are pinned in depth by lane 5's own tests) and whose hidden
   reverse container still reports `display.none` alone. `fourFieldContainer`, the
   report-order pin's subject, takes a percentage main-axis gap as its first
   container row in `reverse`'s place, so the report is `[gap.percent, flexWrap,
   position, inset]` and the production trap names `box.gap.percent`. Both were
   found by the implementation's first full run, not predicted.
6. **The two axes of 5.5 have different tables.** The reverse row's children are 20
   and 30 long, the reverse column's 10 and 30, so their main-axis offsets differ
   (`nil`: 180/150 against 190/160; `.center`: 105/75 against 110/80). The red
   commit reused the row's figures for the column and the implementation's first run
   named all eight, with `disagreeing` empty throughout — the two authorities agreed
   and the literal was wrong. Corrected from the scratch dump taken before the red
   run.

**Amended after the lane's verification.** Three corrections, none behavioural but
each a claim a later reader would act on. (1) **Item 2's third return value is
withdrawn.** Nothing reads the tuple's `mainFactor`: `lowerLegacyNode` needs the
factor *before* the arrangement (the diagnostics bail-out registers no node and
still records its content alignment), so it calls `legacyMainFactor(_:)` itself and
the copy in the tuple is API that compiles and does nothing. The signature is
`arrangeLegacyMainAxis(_ items:, declared:, animated:) -> (nodes:, spacing:)`; the
separate `legacyMainFactor(_:)` stays, for the reason item 2 gives. (2) **Item 4's
MJd is *every* spacer's minimum, not the end spacers'.** As item 4 spelled it the
mutation cannot reach 5.1 or 5.4 at all — both are `space-between`, which registers
no end spacer — so the recorded counts (5.1 8, 5.3 6, 5.4 2) belong to
`func spacer() { requestNativeSpacer(minLength: nil) }`, every spacer's minimum
replaced with the platform default. The end-spacers-only variant is a real but
weaker mutant: 5.3 alone, 4 issues. (3) **Item 5's five inventory arms now compare,
not just report.** They went through a proposal-only render, so the *agrees* half of
the test's new name was unchecked for them, and the two reverse arms are unsized and
ungrown — a shape `LoweringDistributionTests.swift` does not carry, every reverse arm
there declaring a main size or being grown by its parent. They now go through
`LayoutDifferential.compare` with `expectFullAgreement`; all five agree in rects,
hitboxes, accessibility and state slots.

**What it costs if wrong.** (1) A divergence pinned where none exists would have
frozen a fiction into stage 6b's production behaviour and made any later fix of the
legacy engine's fallback look like a regression; as it stands the two paths agree,
and if the legacy fallback is ever corrected to CSS's `center` the lowering diverges
and 5.3 goes red, which is the right alarm. (2) A caller that recomputed the spacing
predicate would drift from the arrangement's; the single return keeps one predicate.
(3) A shape whose control disagrees cannot tell a mutation from the divergence it
already carries, so MJh would have been unreadable. (4) A mutation that reddens
nothing is a broken instrument (practices); naming the real one keeps the coverage
claim honest. (5) A name that no longer describes its subject sends the next reader
to the wrong file. (6) A wrong literal on a passing test is a pin on a fiction.

---

# Stage 3 — scrolling and `Component` distribution (design, 2026-09-22)

Rulings for
[`specs/2026-09-22-engine-stage-3-design.md`](specs/2026-09-22-engine-stage-3-design.md),
on `feat/engine-stage-3` from `57893d0`. **Design only: no file under
`Sources/` or `Tests/` changed in a commit.** Every source patch cited as
**prototype P4** was applied in this worktree, built, run and restored with
`git checkout Sources Tests` (the scratch test file deleted), `git status
--short` empty afterwards, and the suite re-measured green
(`Test run with 1550 tests in 1 suite passed after 56.481 seconds`); the patch
is kept in the session scratchpad (`s3proto-final.patch`, 133 lines), never
committed.

Probe: `docs/probes/swiftui-engine-replacement-stage3.swift`, groups **V** and
**W**, cited below as the *stage-3 probe*. Run under `/usr/bin/swift` (Apple
Swift 6.4, swiftlang-6.4.0.33.1) on macOS 27.0 (26A428); exit 0, run twice
byte-identical, and `xcrun swiftc -O` produced the same lines with empty
stderr. **Revision 2** (critic round 1, same day and toolchain) appends
**W7–W9**: 18 lines, the first 15 unchanged, both forms identical, and the
header block re-extracted and `diff`ed clean against the fresh run. Two existing probes were **re-run today and are byte-identical to their
headers**: `swiftui-stack-algorithms.swift` (787 lines; its SC/SCG arms) and
`swiftui-component-distribution.swift` (**25** output lines; G0–G16 — the
first writing said 22, corrected in critic round 1 finding 10).

Measurements are in `docs/record/25-engine-replacement-stage-3.md`.

---

## LR-BB — a lowered `ScrollView` is stage 2's container lowering under a kernel scroll viewport, and records the viewport as its own item

**The ruling.** Under the proposal authority `ScrollView.requestLayout`:

1. builds its content inside `pass.withScrollContext(…)`, unchanged;
2. registers a **content node** through
   `lowerLegacyNode(style, declared:children:site: .scrollView)` with a style
   carrying **only** `flexDirection`;
3. registers the **viewport** through `frame.requestNativeScrollViewport(child:axis:)`;
4. records the viewport as this element's own `LoweredItem` — declared
   `Style()`, animated the viewport style, `kind: .leaf`, content alignment
   `.topLeading`.

`Layout.node` stays the viewport and `Layout.contentNode` the content node, so
`prepaint`, `paint`, `registerScrollRegion`, the clip and the indicator read the
same two rects under both authorities.

**The content node's record is left UNCONSUMED, and that is the diagnostic.**
The viewport lowers no item field of its content — it measures the content with
the scrolling axis unspecified and places it at its own answer — so an
unconsumed record is the truthful state. Today the content style carries only
`flexDirection`, every item field is at its default, and
`reportUnconsumedLoweredItems` therefore names nothing; if a later stage puts a
field on that style it reports `scrollView.<field>.unconsumed` instead of being
dropped in silence.

**Site `scrollView` is reachable, but not through the `ScrollView`'s own
style.** `lowerLegacyNode` passes `site:` on to `planLegacyItems` as
`parentSite:`, so a **child of the scroller** carrying **unequal grow weights**
(`LR-AE`) reports at `scrollView.flexGrow.weights`. That, and the unconsumed
content style above, are why the case stays in `LoweringSite`.

*(This paragraph first also named `alignSelf: .baseline` and a percentage
`flexBasis`. Both report at the **child's** site, not the parent's:
`planLegacyItems` raises exactly one entry at `parentSite:` and every per-child
entry at `item.site`. Corrected in lane 2 — `LR-BM` item 1, which is also where
test 2.5 (c)'s shape comes from.)*

**`flexShrink: 0` is not carried.** The legacy content node needs it so the
freeze loop does not shrink it from max-content towards min-content — measured
through the type itself (200 vs 508 for two `Text`s in a 200pt horizontal
scroller; `ScrollView.swift`'s own doc). The kernel viewport has no freeze loop:
it measures its content with the scrolling axis unspecified and places it at its
own answer. With the record left unconsumed (above), carrying the field is not
merely pointless but **reports**: `scrollView.flexShrink.unconsumed`. That is
the lane's **M2d**, and it is what makes the omission observable at all.

**Evidence.** Prototype P4, `LayoutDifferential.compare`, "agrees" meaning empty
report, no disagreement, and equal scenes, hitboxes, accessibility records and
state slots:

| arm | shape | result |
|---|---|---|
| A1 | `Box { ScrollView(.vertical) { 3 × 80×40 } }.width(80).height(60)` | agrees, 6 ids |
| A2 | the demo's own spelling (`.width(80).flexGrow(1).flexBasis(0).minHeight(0)` in a stretching column) | agrees, 8 ids |
| A5 | 50×30 content in a 100×100 viewport | agrees, 4 ids |
| A8 | 160×30 content in an 80×60 vertical viewport | agrees, 4 ids |
| A9 | a `ScrollView` inside a `ScrollView` | agrees, 7 ids |

and, over the whole suite, P4 produced **no new diagnostic anywhere**: the only
red tests were five diagnostics expectations this stage owns (spec §2.3), and
the demo's report lost `scrollView.noLowering` in both modal states.

**Why the content goes through `lowerLegacyNode` rather than straight to
`requestNativeLinearStack`** (which is what `ProposalScrollView` does): the
legacy content node is an ordinary flex container, so its children's stretch,
grow, margins, gaps and `justifyContent` are stage 2's business, already
implemented and already pinned. Registering a bare stack would silently drop all
of it — A2's stretch rows are what would move.

**What it costs if wrong.** A content node registered the wrong way is invisible
until a scroller holds anything but fixed-size rows: the demo's own scroller is
a `List` of pinned-height rows, so the harness would agree and a caller's text
or stretched row would be wrong in production at stage 6b. That is why A6 (a
`Text` in a horizontal scroller) and A2 (the demo's spelling) are both in the
lane and both carry their own mutation.

**Amended, stage-3 critic round 1 (findings 2 and 9).** Prototype P4 *consumed*
the content node's record, and the ruling as first written kept that step and
justified `LoweringSite.scrollView`'s survival by "`LoweredItem.site` names it
in a `…unconsumed` report". Both were wrong, and provably so from source:

- `reportUnconsumedLoweredItems` skips consumed records
  (`LoweringState.swift`'s `!item.consumed`), so the consumption made the
  record invisible; and the content style's item fields are all at their
  defaults, so **not** consuming it was equally silent. Neither the step nor
  its absence could be seen — the design's **M2d** ("carry `flexShrink: 0`, the
  viewport swallows the record, the report grows") and **M2e** ("the record is
  not consumed, `scrollView.…unconsumed` appears") were **both inert**, and
  §9's "nothing at site `scrollView` reports" was unpinned.
- The viewport's own record (`declared: Style()`) can never carry an item
  field: `ScrollView` is not a `StyledElement` and has no modifier surface. So
  the reason given for keeping the case was unreachable too.

Step 3 is therefore **deleted**: the content record stays unconsumed, which
makes M2d live in one edit and turns a future field on that style into a
diagnostic rather than a silent drop. The case stays for the reason now stated
above — a scroller child's unlowerable item field reports at site `scrollView`
through `planLegacyItems`' `parentSite:` — which spec test 2.5 produces on
purpose with `alignSelf: .baseline`. `UnlowerableField.owningStage`'s
`case .scrollView: return "3"` stays live with it.

**Unpinned sub-clause, recorded rather than hidden.** Nothing distinguishes
"the viewport deliberately lowers no item field of its content" from "the
lowering forgot to"; they are the same code. What the lane pins is the
consequence — the report names a carried field (M2d) and the content's rects
agree (2.1, 2.4).

## LR-BC — the lowered viewport fills its proposal on the scrolling axis; the cross axis agrees with the legacy engine, and divergence 54 is NOT what that shows

**The ruling.** The kernel viewport answers its **proposal** on the scrolling
axis when it has one, and its **content's answer** on the other (`CN-M`,
`CN-F`). Lowering `ScrollView` onto it therefore changes the scrolling axis and
leaves the cross axis where stage 2 put it. The scrolling-axis change is pinned
as a legacy-vs-lowered divergence under the proposal authority and retires at
the root switch. **Divergence 54 is a different proposition and does not retire
here** (see the amendment below).

**Measured, prototype P4:**

| arm | parent | cross axis | scrolling axis |
|---|---|---|---|
| A10 | stretching column, declared 120×100 | **120 on both sides — agrees** | 60 → **100** |
| A11 | centring `Column`, 120×100 | 50 on both sides — agrees | 60 → **100** |
| A7 | centring `Row`, 120×100 | 50 — agrees | (0, 20) 50×60 → (0, 0) 50×**100**; both children move up 20 |
| A4 | `Box`, 100×50, **horizontal** scroller | 50 — agrees | **160** → **100** (the legacy viewport overflowed its parent; the lowered one is bounded by it), `scenesEqual` and `hitboxesEqual` both false |

**So divergence 54 is not what the lowering shows.** `CN-P` 3 records it as "a
legacy `ScrollView` takes its cross axis from its parent where a proposal
`ScrollView` takes its contents'" — a `ScrollView`-vs-`ProposalScrollView`
difference. Under the lowering the **legacy-vs-lowered** cross axis agrees in
every arm measured, because stage 2's stretch wrapper gives a stretched
viewport the line's cross size (A10) and both sides hug when nothing stretches
(A7, A11). What actually moves is the **scrolling** axis, and in the direction
that makes a scroller a scroller.

**Amended, stage-3 critic round 1 (finding 5): the lowering PRESERVES
divergence 54; it does not close it.** The first wording said "divergence 54's
cross-axis half is therefore closed by the lowering". That inverts the
mechanism. The kernel viewport's own cross answer is `content.width`
(`LayoutTree.swift`'s `scrollViewportSize`) — the **`ProposalScrollView`**
side. A lowered `ScrollView` reads its parent's 120 in A10 only because it
**records a `LoweredItem`**, so stage 2 wraps it in a stretch item frame and
`LoweringState.alias` reports the frame's rect as the element's.
`ProposalScrollView` records nothing (`ProposalScrollView.swift` calls
`requestNativeScrollViewport` and no `recordLoweredItem`), so `consume` returns
`nil` and it gets no such frame. In a stretching container the two therefore
**still** disagree exactly as 54 says, after the lowering as before it. What the
lowering closed is a *legacy-vs-lowered* cross-axis gap, which is a different
proposition and is what A10/A11's "agrees" measures.

Consequences, all applied:

- **54 is removed from stage 6b's retirement row** (`LR-BJ`). The root switch
  makes production `ScrollView` the lowered one; in the pin's own fixture (both
  elements as window roots, where neither has a parent to stretch it) the two
  would then agree, but under any stretching container they do not. Retiring 54
  needs the two scroll types unified, which `LR-BF` already sends to **stage 11
  / task 10**. That stage owns it.
- The design's §2.3 and §3.2 sentences are softened to "legacy and lowered
  agree on the cross axis", which is what was measured.
- Lane 2 test 2.2 gains an arm that measures the **surviving** difference — a
  lowered `ScrollView` and a `ProposalScrollView` as the two children of one
  stretching lowered `Box` — so 54's persistence is a pinned literal rather
  than a paragraph. `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents`
  keeps its name and its legacy-authority assertions untouched.

**SwiftUI's answer, stage-3 probe group V** (with V0 and V2 as controls):

- **V1 vs V0/V2**: `VStack { 60×30; ScrollView { 60×300 } }` at 200 gives the
  scroller **162** = 200 − 30 − 8, exactly what a maximally flexible `Color`
  takes in the same shape (V2), while the same stack of two fixed colours hugs
  (V0, a 68pt block centred at y 66). A `ScrollView` answers its proposal on the
  scrolling axis.
- **V3**: it fills even over a 20pt child, and places that child at the
  viewport's own origin — `SCG2`'s leading-edge rule seen inside a stack.
- **V4**: the horizontal axis is identical (62 = 100 − 30 − 8, content 300 and
  overflowing).
- **V5**: `.fixedSize()` **does** opt out — the viewport becomes its content's
  300 and the 338pt stack overflows the 200pt host (`a` at y −69). So the
  flexibility is a response to the proposal, and the ideal on the scrolling axis
  is the content's size, which is also what stack-algorithms SC1 reads at nil×nil
  (50×300).

**Consequence named here, owned by stage 6b.** The demo's
`.flexGrow(1).flexBasis(Pixels(0)).minHeight(Pixels(0))` on the scroller `Box`
exists only to bound a viewport that would otherwise hug its 14 000pt content —
`DemoContent.swift`'s own comment says so at length. A lowered viewport is
bounded by construction, so that incantation becomes removable at the root
switch; removing it before then would change a legacy production frame.

**What it costs if wrong.** Pinning this the other way — lowering the viewport
as a `fixedSize` over its content, which is the mutation the lane runs — would
reproduce the legacy hug and make every lowered scroller un-scrollable at stage
6b while every fixed-size test still agreed. Pinning it as stated when SwiftUI
does something else would bake a wrong bound into production at 6b; V1–V5 are
what stand behind it, with V0 and V2 making V1 attributable.

## LR-BD — one clamp and one indicator, computed rather than stored

**The ruling.** `ProposalScrollView.swift:97-170`'s seven private members —
`clamp`, both `resolvedOffset` overloads, `paintIndicator`, `indicatorBounds`,
`delta`, `extent` — are deleted and replaced by a `ScrollChrome` value
(`Sources/MetalUI/ScrollChrome.swift`) carrying the axis, the corner radius and
the indicator visibility. Both elements build it **computed from their existing
stored properties**.

**Computed, not stored**, deliberately: adding a stored property to a public
type that crosses a module boundary is CLAUDE.md's incremental-build hazard
(`Scene` twice, `Display`, `FontKey`), and it would put a `swift package clean`
in a lane whose whole claim is that nothing observable changed. Computing it
from `axis`, `cornerRadius` and `indicatorVisibility` changes no storage at all.

**Two things do not fold.** (1) The two `resolvedOffset` overloads stay two
functions: `PrepaintPass` and `PaintPass` have no common protocol, and
`Passes.swift` records why inventing one would leak `PaintPass.frame` and with
it `scaleFactor`. Four copies become two. (2) `ScrollContext` publication stays
`ScrollView`'s alone (`LR-BF`).

**Evidence that the copies had already drifted**: `ScrollView.paintIndicator`
seeds `lastScroll` at `0` and `ProposalScrollView`'s at `-Double.infinity`.
Both are dead — `withState` always runs its closure — but they are two different
answers to the same question living ten lines apart, which is the shape
CLAUDE.md's "a copy of a pinned implementation is unpinned" exists to catch.
`ProposalScrollView`'s clamp, write-back, thumb floor, ramp and indicator clip
have **no test of their own** today; the fold gives them `ScrollView`'s.

**What it costs if wrong.** This is the one lane that edits production paint
under **both** authorities, so a mistake here is visible in the shipping demo
and the preview rather than only under the proposal authority. That is why its
demo expectation (§8) treats a non-zero image as a finding that stops the lane,
and why its mutations (**M1a** the write-back, **M1b** the indicator's clip
offset, **M1c** the thumb floor, **M1d** `.hidden`'s position relative to
`requestAnotherFrame`) must each redden a named `ScrollView` test **and** its
new `ProposalScrollView` twin.

**Amended, stage-3 critic round 1 (findings 3 and 12).** Four corrections, each
from source:

1. **The seven private members are at `:97-170`**, not `:94-166` (line 94 is a
   call site inside `paint`). The stale citation was inherited from CLAUDE.md
   and is corrected here; CLAUDE.md's own copy is the Docs phase's.
2. **The fold carries the doc comments with the code.** Four pieces of prose at
   the old sites are the only record of why their lines exist and must arrive
   at `ScrollChrome` with them: the prepaint overload's overscroll measurement
   ("twenty −37 events stored 740, seventeen of the twenty dead"),
   `paintIndicator`'s `offsetBy: .zero` rationale, the `guard alpha > 0` /
   `requestAnotherFrame()` ordering note, and why `.hidden` is checked first. A
   fold that moves the code and leaves the prose behind is a silent loss of the
   evidence the mutations M1b–M1d are named for.
3. **`ScrollView.clamp` is not kept as a forwarder.** It is named by five
   assertions (`ScrollViewTests.swift:78,79,80,89,97`) and by nothing in
   `Sources/` once the fold lands; keeping it would add a production member
   with no production caller — CLAUDE.md's declared-but-inert shape. The five
   assertions re-point at `ScrollChrome.clamp` in lane 1.
4. **Test 1.4 was unrunnable as specified.** The design claimed it was RED
   before the fold because "the `lastScroll` seeds differ" — but this ruling
   itself says both seeds are dead (`StateTable.withState` unconditionally
   calls its closure, `StateTable.swift:334-342`), and the two implementations
   are otherwise line-equivalent, so the test is **green at `57893d0`**. Its
   specified mutation **M1f** ("either element's indicator given a different
   thumb-floor constant") also cannot redden it *after* the fold, since there
   is then one constant and both sides move together. 1.4 becomes a
   **characterization** test of the property the fold creates — the two
   elements' indicator rect, colour and clamped offset are equal for one
   fixture — and its mutation becomes **re-inlining a private copy of
   `paintIndicator` into one element with a different thumb floor**, which is
   precisely the drift it guards against. Its `try #require` that the two
   viewports agree first is satisfiable only with a fixture whose content
   **fills the cross axis** (divergence 54, `LR-BC`), so the fixture is
   specified that way.

## LR-BE — `$anim-content` and `$anim-viewport` survive the lowering unchanged, and `ProposalScrollView` still never animates

**The ruling.** The lowered branch calls `animated(_:_:for:pass:)` on the content
style under `scrollViewContentAnimID(for: id)` and on the viewport style under
`scrollViewViewportAnimID(for: id)`, exactly as the legacy branch does, and
feeds the **animated** style to the lowering's lengths and the **declared** one
to its structure (`LR-AS`). `ScrollView` therefore remains one of the nine
animation-registering sites, with two named children and the `$anim` slot at a
grandchild, and `theSevenRetentionSlotsAreMutuallyDistinct` is unaffected.

`ProposalScrollView` gains nothing: it has no `Style` and no modifier surface,
so there is nothing to interpolate. The fold shares **chrome**, not animation.

**Evidence.** P4 kept both `animated` calls and every agreement arm reported
`stateSlotsEqual == true`; the demo's `$anim` census (divergence 18's `2n + 7`
shape) did not move — the exit test's 2036/2042 id counts and its state-slot
comparison are unchanged.

**What it costs if wrong.** Passing the bare `id` to both calls collapses the
two nodes' fields onto one `$anim` retention slot — M4 spec 3 §5's original
defect — and a scroller mid-animation would interpolate the viewport's style
into the content's. It is silent: no test outside 2.6 and the slot-distinctness
test can see it.

## LR-BF — `ScrollContext` publication is unchanged, and `ProposalScrollView` does not get one

**The ruling.** Nothing about `ScrollContext` changes. It is published from
`ScrollState` during layout, its `viewportExtent` is written by the prepaint
`resolvedOffset` from the element's `bounds`, and `Frame.bounds(of:)` resolves
that through stage 2's alias. A native viewport is just another node to it.

`ProposalScrollView` gains **no** publisher.

**Evidence.** P4, a custom element recording `pass.scrollContext` inside and
after a scroller, rendered under each authority:
`["off=0.0 vp=0.0 ax=vertical", "nil"]` — identical, including the `nil` for the
sibling declared after the scroller.

**Why `ProposalScrollView` gets none.** Nothing can read it. No proposal element
reads `pass.scrollContext`, and `List` is an `ElementGroup`, not a
`ProposalElementGroup`, so it cannot be a `ProposalScrollView`'s content at all
— the compiler refuses. A published-but-unreadable context is exactly the
declared-but-inert row CLAUDE.md's table exists to keep out, and it would have to
be deleted again by whoever unifies the two scroll types. Named deferral: stage
11 / task 10.

**What it costs if wrong.** `ScrollContext` is what `List` windows against, so
if publication had moved with the viewport the failure would be a `List` that
windows against a stale or absent context — one frame of blank rows, or a
permanently unwindowed 500-row list, neither of which the legacy suite would
see (it runs the legacy authority). Test 3.5 drives **two** frames per
authority with a wheel between them, because on frame 1 `viewportExtent` is 0 on
both sides and a one-frame comparison would be vacuous.

## LR-BG — a `Component` amend lowers to one native frame per member, aligned per axis, and the op's payload becomes a size

**The ruling.** `ComponentModifierOp.amend` stops carrying a
`(inout Style) -> Void` closure and carries a **`Size<Dimension>`** — the only
thing `Component.width`/`.height` ever wrote. The legacy branch applies it
through `setStyle` exactly as before; the lowered branch registers **one native
frame per member** with the declared axes, recorded with `kind: .frameLayer` so
a parent stretches it only on an axis it leaves `nil` (`MC-Q` finding 7).

**The frame's alignment is per axis**: `.center`'s factor on an axis the patch
declares, `0` on an axis it leaves `auto`. The same value is recorded as the
item's `contentAlignment`.

**Evidence, prototype P4** (`Box` 300 wide, 40 tall, members 30×10 and 50×10):

| arm | legacy | lowered | SwiftUI |
|---|---|---|---|
| C1 `Pair().width(70)` | members **70**×10 at x 0, 70 | 30 at x **20**, 50 at x **80** | W1 / component-distribution G7 |
| C2 `Solo().width(70)` | 70×10 at x 0 | 30×10 at x **20** | G8 |
| C4 `.padding(4).width(70)` | x 4, 74 | x **20**, **80** | G13's x 20 |
| C5 `.width(70).padding(4)` | 70 wide at x 4, 82 | 30 at x **24**, 50 at x **92** | G14's x 24 |
| C7 `Pair().height(20)` | 30×**20**, 50×**20** at y 0 | 30×**10**, 50×**10** at y **5** | W2's per-axis rule |
| C3 `Pair().padding(8)` | — | **agrees** (the wrap needs no divergence) | G2 |

**The per-axis alignment is a correction the prototype forced, and its ground
is the legacy answer it must preserve.** Recording the amend frame's content
alignment as `.center` unconditionally moved C1's members from y 0 to y **15**
and C4's from y 4 to y 15: the item frame the parent registers reads
`LoweredItem.contentAlignment`, so a width-only amend was centring its member
on the height axis too. **The constraint that forced the fix is that the
undeclared axis must not move** — divergence 48 is about the axis the caller
declares, and an amend that also relocates the other axis is a second,
undesigned divergence. Making the alignment per axis restored y 0 and y 4.

**What SwiftUI contributes here, honestly stated.** Stage-3 probe arms
**W7/W8** (`Pair().frame(height: 40, alignment: .top)` puts both members at
y **30**, `.bottom` at y **60**, against the W0 control's y 45) and **W9** (the
same for a single member) show that a frame declaring one axis is a **real**
frame that aligns on the axis it declares. Given that, **W2**'s x 106/144 and
**W5**'s x 135 — the control's own numbers with the frame now proved present —
say the **undeclared** axis is passed through at the child's own size. But note
what that means: in SwiftUI an undeclared axis leaves no free space, so *how* a
frame would align a child on such an axis is **unobservable in principle**, and
`LoweredItem.contentAlignment` — how a **parent's** item frame places a grown
child — has no SwiftUI counterpart at all. So W2/W5/W7–W9 are the consistency
check on this ruling, not its source.

(The first writing of this ruling cited W2's byte-identity with the W0 control
as positive evidence. It is not: "a per-member frame passing the undeclared
axis through" and "no frame at all" predict the same W2 and W5 output — the
host centres either way. That is practices shape 15, and W7–W9 were run to fix
it; see the amendment below.)

**Why the payload becomes a size rather than the lowering reporting a non-size
amend.** `ComponentModifierOp.amend` takes an arbitrary closure, so a lowering
that framed by `size` alone would silently drop anything else an amend wrote —
the prototype did exactly that. The alternatives were a `component.amend`
diagnostic for a non-size amend (a case no public API can reach today: the
inert shape) or making the case unable to express one. The second deletes the
hole instead of reporting it.

**Divergence 48 is answered here under the proposal authority and retires at
6b.** `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` keeps its name
and its wrong-on-purpose legacy assertion.

**What it costs if wrong.** A frame registered around the whole group rather
than per member reads the same OUTER size in every fixture — it is only the
members' own rects that tell the two apart, which is why 4.1 asserts the member
rects and not the group's. Getting the alignment wrong is invisible on any
fixture whose members declare both axes, which is most of them; 4.3 exists for
exactly that and pins the y 5 and y 0 the prototype measured.

**Amended, stage-3 critic round 1 (findings 6 and 8).**

1. **The evidence is re-grounded** (finding 6): the ruling's ground is the
   legacy agreement it must preserve, with W7–W9 run **now** (2026-09-22,
   both script and `-O` forms, byte-identical, recorded in the probe's header)
   as the discriminating SwiftUI arms and W2/W5 demoted to "consistent with".
   The probe's header carries the same reading.
2. **`loweredComponentFrame` CONSUMES AND PLANS the member's own record**
   (finding 8). As first specified it registered a `.frameLayer` frame around
   the member and recorded *that*; the parent then consumed the frame and the
   **member's** record was left unconsumed. `reportUnconsumedLoweredItems`
   emits `<site>.<field>.unconsumed` for any non-default item field on an
   unconsumed record, and in a production frame every report is a **trap** — so
   `MyComponent().width(70)` over a member declaring `.flexGrow(1)` would work
   under the legacy authority and **abort** under the proposal one at 6b. That
   is not a divergence; it is a crash. `loweredComponentFrame` therefore
   consumes the member's record and plans it through `planLegacyItems` exactly
   as `lowerLegacyLayer`'s single-node arm does (`.wrap`, which routes through
   `lowerLegacyNode`, already did this — which is why arm C3 agrees). Lane 4
   gains an arm whose member declares `flexGrow` and one whose member declares
   `margin`, with the mutation "do not consume" — and none of C1–C7 had one,
   which is why the hole survived the prototype.

## LR-BH — a `.frame` layer over several member nodes lowers to a row of per-member frames

**The ruling.** `lowerLegacyLayer`'s frame arm, over more than one node, registers
one native frame per node carrying the whole `FrameSpec` and rows them with
`requestNativeLinearStack(axis: .horizontal, spacing: 0, alignment: spec.alignment)`.
The `frame.multipleNodes` row is deleted from `legacyFrameLayerDiagnostics`;
`display.none` is still checked first and alone (`LR-J`).

**Evidence.** P4 arm C6, `Pair().frame(width: 70, height: 40)` in a 300×60 `Box`:
legacy registers **one 70×40 frame** and the flex row squeezes the members to
**26** and **44**; lowered registers a **140×40** row of two 70-wide frames with
the members at their own 30 and 50, centred at x **20** and **80**, y 15 on both
sides. Probe **W1**/**W4** read a at 96 and b at 164 in a 300pt host — a 148pt
pair, which is 140 plus the enclosing `HStack`'s 8pt spacing. Spacing 0 is
MetalUI's own container default (divergence 52), so the lowered rects are
SwiftUI's geometry in MetalUI's spacing.

**What still diverges, and why it cannot close here.** SwiftUI's framed members
stay **siblings of the enclosing stack**; MetalUI's `ModifiedElement.requestLayout`
returns one `LayoutNodeID`, so they are one flex item of the parent. Closing that
needs `ElementGroup`'s associated-type change (`TB-M`). Stage 11 owns it, with the
`ModifiedElement`/`ModifiedContent` unification.

**Divergence 56 is answered here under the proposal authority.**
`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` and
`chainedFramesRemainConcreteAndNestTheirLayoutNodes` keep their names and their
legacy assertions.

**What it costs if wrong.** Rowing the per-member frames at the platform default
spacing instead of 0 (the lane's **M5a**) reads 148 instead of 140 and would be
indistinguishable from SwiftUI's own number while being wrong for MetalUI, where
the enclosing container supplies the spacing. Applying the spec to only the first
member is invisible on a single-member component, which is what most fixtures
use.

**Amended, stage-3 critic round 1 (finding 7): the multi-node arm must PLAN the
members' item fields, not only frame them.** `lowerLegacyLayer` consumes every
child's record up front (`children.map { frame.lowering.consume($0) }`) but
runs `planLegacyItems` only when `children.count == 1`; for more it leaves
`plans` as default `LegacyItemPlan()`s, which `registerLegacyItems` turns into
a no-op, and returns `.first`. Today that path is unreachable because the
`frame.multipleNodes` diagnostic short-circuits into `report(fields)`. Deleting
that row — which this ruling does — makes the path live, and with the plans
still defaulted **every member's `minSize`, `maxSize`, `margin`, `alignSelf`
and `flexGrow` would be consumed and dropped with no diagnostic**, because a
consumed record is skipped by `reportUnconsumedLoweredItems`. Lane 5 therefore
runs `planLegacyItems(received, parent: declared, parentKind: .stack,
parentSite: .modifierLayer, fields: &fields)` for the multi-child case too and
registers the resulting item wrappers **per member**, rowing
`registerLegacyItems(children, plans)` in full rather than taking `.first`. A
new test whose two members declare `margin` and `minSize` pins it, with the
mutation "skip the planning for `count > 1`". Lane 5's 5.1–5.3 as first
specified used fixtures of two bare `Color`-like members, none of which could
see this.

## LR-BI — the scroll suites are parameterised by authority, and their two custom element types re-spell as native probe leaves

**The ruling.** Every scenario in `ScrollRoutingTests` (16) and
`ScrollIndicatorTests` (14), and `ScrollViewTests`' 7, becomes
`@Test(arguments: LayoutAuthority.allCases)` and builds its frame or fake window
under the argument. `LayoutAuthority` gains `CaseIterable` (internal, as the enum
is). The two custom elements — `ScrollContextRecorder` (5 call sites) and
`HitboxProbe` (2), which §4.2's census counted as **9** legacy registrations in
its filtered run — take `ProbeLeaf`'s shape:
`pass.lowersToProposal ? pass.frame.requestNativeLeaf { … } : pass.requestLeaf(…)`,
answering the same size from the same `Style`.

**A parameterised test counts as ONE test in the summary line** — measured on
this suite: `aHardLineBreakEndsALineWhenNoWidthIsOffered(separator:)` runs 8
cases and the total counts it once. So the suite total does not move for these
37 scenarios, and the exit criterion cannot be read off the count. That is why
`everyScrollScenarioRanUnderBothLayoutAuthorities` exists: a counter the
parameterised arms increment, with a `try #require` on the arm count derived by
hand (practices shape 13) and on both authorities having been seen.

**Why parameterisation rather than a second copy of each suite.** A copy of a
pinned implementation is unpinned (practices); a copy of a pinned *test* is
worse, because the two drift silently and the mutation that reddens one leaves
the other green. Parameterising keeps one body and one set of literals.

**Red before.** See the amendment: lane 3 runs **after** lane 2, its red-before
is a single exit test taken at lane 1's HEAD, and its evidence is its
mutations.

**What it costs if wrong.** Leaving the `arguments:` list at `[.legacy]` — the
lane's **M3c** — passes every test and delivers nothing, and the suite count
would not move to say so.

**Amended, stage-3 critic round 1 (findings 1, 4, 11 and 12).**

1. **The lane-3 red-before as first written could not be run: it aborts the
   process and truncates the suite** (finding 1).
   `Frame.noteUnlowerable` is `guard reportsUnlowerableFields else {
   preconditionFailure(…) }` (`Frame.swift:1536`), and **`Window` never sets
   `reportsUnlowerableFields`** — the only writers in the tree are test
   helpers; `Window.swift`'s `Frame(...)` call passes `layoutAuthority` and
   `recordsElementBounds` and nothing else. So a proposal-authority `Window`
   holding a `ScrollView` aborts: no summary line, no list of which arms
   failed, and nothing to record. That contradicts the design's own §6
   preamble and CLAUDE.md ("a precondition … truncates the suite unless its
   pinning test becomes an exit test first"). **Applied, option (a) plus one
   exit test**: lane 3 is ordered **after lane 2**, so its arms are written
   against a working lowering and its evidence is **M3a/M3b** plus lane 2's
   **M2a** and lane 1's **M1c**; and the trap itself is pinned by **one** new
   arm on the existing exit test
   `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority`, added
   in **lane 1** (where it passes) and converted to an agreement arm in lane 2.
   Option (b) — an internal `Window.reportsUnlowerableFields` — is **rejected**:
   it adds production surface whose only caller is a test, to buy a list that
   the per-arm mutations give for free.
2. **Test 3.5 was named for something stage 3 cannot do** (finding 4).
   `aListInsideALoweredScrollerWindowsAgainstTheSameContextAsTheLegacyOne` runs
   two frames through a `Window` per authority — and a `List` under the
   proposal authority calls `noteUnlowerable(.list, "noLowering")` **before any
   row** (`List.swift:351`), so through a `Window` it traps (item 1). Under
   diagnostics, where P4 measured it, the `List` builds **zero** rows (record
   §3.6: 45 ids, 40 legacy-only), so "windows against the same context" was
   vacuous there too. Re-scoped and renamed to
   `aScrollContextSurvivesALoweredViewportAcrossTwoFrames`: a **non-`List`**
   recorder inside and after the scroller, two frames with a wheel between
   them, comparing `offset`, `viewportExtent` and `axis` per authority. §9's
   `List` row now says plainly that `List` windowing is checked **only under
   the legacy authority** this stage, and stage 4 owns the proposal half.
3. **Each lane states its predicted end-of-lane test count** (finding 11), so
   "the count did not move unexpectedly" is falsifiable. A parameterised test
   counts as one, re-verified this round: 1551 `@Test` hits minus one in a doc
   comment = 1550, matching the summary line.
4. **The baseline's one unattributed issue is attributed or retired BEFORE
   lane 3** (finding 11), because lane 3 takes the count of real `Window`s in
   `ScrollRoutingTests` + `ScrollIndicatorTests` from 37 to 74 — each a Metal
   device on one shared main run loop — and four of those scenarios are
   display-link timing tests. If the flake lives there, lane 3 doubles its
   rate and the exit test becomes the flakiest thing in the suite. The check is
   the two suites run unfiltered, whole log kept, enough times to attribute or
   retire it; the result is recorded either way.
5. **`ScrollViewTests`' dependency census is taken** in lane 3 (finding 12): it
   was added to the lane without appearing in §4.2's census. If it registers no
   custom legacy node the row says so; if it does, the type re-spells like the
   other two.

## LR-BJ — deferrals

| item | why not stage 3 | owner |
|---|---|---|
| the demo scroll subtree's remaining width disagreement (0 vs 420) | it is the `List` reporting and building no rows, not the `ScrollView` | stage 4 |
| `ProposalScrollView` publishing a `ScrollContext` | nothing can read one (`LR-BF`) | stage 11 / task 10 |
| `ProposalScrollView`'s animation | no `Style`, no modifier surface | stage 11 |
| the demo's `.flexGrow(1).flexBasis(0).minHeight(0)` on the scroller `Box` | a production respelling, and `LR-BC` makes it removable only once the root switches | stage 6b |
| divergences 48 and 56 retiring | each is answered under the proposal authority here and pinned wrong-on-purpose under the legacy one | stage 6b |
| **divergence 54 retiring** | the lowering **preserves** it, it does not close it: the kernel viewport's cross answer is the `ProposalScrollView` side, and a lowered `ScrollView` reads its parent's cross size only because it records a `LoweredItem` and `ProposalScrollView` does not (`LR-BC`, amended). Retiring it needs the two scroll types unified | stage 11 / task 10, with `LR-BF`'s unification |
| framed component members staying one flex item | needs `ElementGroup`'s associated type (`TB-M`) | stage 11 |
| the single-child stretch elision inside a scroller (A6, 40 → 16) | stage 2's `LR-AC`, unchanged here | stage 6b |
| `Style.overflow`'s inert write in `ScrollView.requestLayout` | it documents intent on the legacy path; the lowering does not carry it | stage 10 |
| two-axis scrolling | never designed | task 10 |

---

## LR-BK — stage-3 critic round 1: dispositions

**Round.** 2026-09-22, after the stage-3 design commits `ca7272a` and
`ec83625`. Twelve findings (1–11 individually, 12 a bundle of six smaller
ones). The critic re-ran all three probes the design leans on
(`swiftui-engine-replacement-stage3.swift`, `swiftui-component-distribution.swift`,
`swiftui-stack-algorithms.swift`) and found each byte-identical to its header,
and confirmed the worktree clean and the 97 goldens untouched; every defect
was in how the design mapped those answers onto MetalUI's code, or in
mutations and red-before runs that could not do what they claimed.

**New evidence this round.** Stage-3 probe revision 2: arms **W7, W8, W9**
(`Pair().frame(height: 40, alignment: .top/.bottom)` and the single-member
`Solo` version), run 2026-09-22 under `/usr/bin/swift` twice byte-identical and
under `xcrun swiftc -O` identical with empty stderr and exit 0; the header's
recorded block was re-extracted and `diff`ed clean against the fresh run. The
first 15 lines are unchanged. `swiftui-component-distribution.swift` re-run:
**25** output lines, not the 22 two documents claimed. Everything else in this
round is read from source and cited by file and line.

| # | finding | disposition | where |
|---|---|---|---|
| 1 | lane 3's red-before aborts the process and truncates the suite (`Window` never sets `reportsUnlowerableFields`) | **applied**, option (a) + one exit-test arm: lane 3 moves after lane 2; the trap is pinned by an arm on the existing exit test, added in lane 1. Option (b), an internal `Window.reportsUnlowerableFields`, **rejected** — production surface whose only caller is a test | `LR-BI` amended; spec §6 preamble, lanes 1 and 3; record §5 |
| 2 | **M2d** and **M2e** are provably inert (a consumed record is skipped; the content style carries no item field) | **applied**: step 3, the consumption, is **deleted** — the content record stays unconsumed, which makes M2d (`flexShrink: 0` carried → `scrollView.flexShrink.unconsumed`) live in one edit; M2e becomes the wrong `site:` argument | `LR-BB` amended; spec §3.1, §4.1, 2.4, 2.5 |
| 3 | test 1.4 can be red neither before (the two implementations are line-equivalent and both `lastScroll` seeds are dead) nor after (**M1f** moves both sides together) | **applied**: 1.4 becomes characterization, its mutation becomes re-inlining a private `paintIndicator` copy with a different thumb floor, and its fixture's content fills the cross axis so the `#require` is satisfiable | `LR-BD` amended; spec 1.4 |
| 4 | test 3.5 is named for something stage 3 cannot do, and §9's `List` row rests on it | **applied**: renamed and re-scoped to a non-`List` recorder over two frames; §9's row says `List` windowing is checked only under the legacy authority this stage | `LR-BI` amended; spec 3.5, §9 |
| 5 | `LR-BC`'s headline is inverted — the lowering **preserves** divergence 54 — so "54 retires at 6b" is wrong | **applied**: 54 removed from the 6b row and sent to stage 11 / task 10 with the scroll types' unification; §2.3/§3.2 softened to "legacy and lowered agree"; lane 2 gains an arm measuring the surviving difference | `LR-BC`, `LR-BJ` amended; spec §2.3, §3.2, 2.2, §10 |
| 6 | `LR-BG` cites probe arms that cannot discriminate, for a mechanism SwiftUI does not have | **applied, measured**: W7/W8/W9 run now (y 30 / y 60 / y 30 against the control's y 45); the ruling's ground restated as the legacy agreement; W2/W5 demoted to "consistent with"; the probe header carries the same reading | `LR-BG` amended; probe revision 2; spec §2.2, §2.3, §3.5 |
| 7 | lane 5 drops every member's item fields silently (`planLegacyItems` runs only at `count == 1`; the result is `.first`) | **applied**: the multi-child arm plans and registers per member and rows them all; a new test whose members declare `margin` and `minSize`, mutation "skip the planning for `count > 1`" | `LR-BH` amended; spec 5.1a |
| 8 | lane 4's amend orphans the member's `LoweredItem` — a production **trap** at 6b, not a divergence | **applied**: `loweredComponentFrame` consumes and plans the member as `lowerLegacyLayer`'s single-node arm does; a new arm whose member declares `flexGrow`/`margin`, mutation "do not consume" | `LR-BG` amended; spec §3.5, 4.6 |
| 9 | `LoweringSite.scrollView` becomes unreachable and §4.1 gives the wrong reason | **applied, with a correction to the finding**: the site is **not** unreachable — `lowerLegacyNode` passes `site:` to `planLegacyItems` as `parentSite:`, so a scroller child's unlowerable item field reports at `scrollView.<field>`. §4.1's reason is replaced by that one and test 2.5 produces such a report on purpose (`alignSelf: .baseline`); the unconsumed content record (finding 2) is the second route | `LR-BB` amended; spec §4.1, 2.5 |
| 10 | a recorded probe length does not reproduce (22 vs 25) in two documents | **applied, measured**: a fresh run emits **25** output lines, content byte-identical; both documents corrected | spec §2.1; record §2.1 |
| 11 | the unattributed baseline failure is left live under the lane that doubles the most timing-dependent suite; no lane states its expected count | **applied**: the two scroll suites are re-run unfiltered, whole log kept, to attribute or retire it **before** lane 3, result recorded either way; every lane states a predicted end-of-lane total | `LR-BI` amended; spec §6, §1 |
| 12 | six smaller ones: the `:94-166` citation; the fold losing its doc comments; `ScrollView.clamp`'s forwarder; `ComponentModifierOp`'s payload size; **M1e**'s false parenthetical; `ScrollViewTests` absent from the census | **all applied**: `:97-170`; the four doc comments named and required to move with the code; the forwarder dropped and the five assertions re-pointed at `ScrollChrome.clamp`; the clean **measured** in lane 4 rather than asserted; M1e restated as an arm that exists today; the census taken in lane 3 | `LR-BD`, `LR-BI` amended; spec §3.3, §5, 1.3, lanes 3–4 |

**Nothing is rejected outright**; finding 1's option (b) and finding 9's
premise are the two places where the disposition differs from what the finding
asked for, each with its reason above.

**What this round changes about the stage's shape.** Lane order becomes
1 → 2 → 3 → 4 → 5 (lane 3 after lane 2, item 1), lanes 4 and 5 each gain one
test for an item-field hole neither prototype fixture could see (findings 7 and
8), and three of the design's mutations (M1f, M2d, M2e) are replaced because
they could not redden anything. The count of lanes is unchanged at five.

---

## LR-BL — stage 3 lane 1's corrections: what was already pinned, two mutations that could not redden their test, and the harness that had to be rebuilt

**Round.** 2026-09-22, implementing lane 1 (the shared scroll chrome, `LR-BD`)
at `f0590d3`…`440fd78` on `feat/engine-stage-3`. Six corrections, every one of
them forced by a measurement taken in the lane rather than by re-reading the
design.

**1. `ProposalScrollView`'s prepaint write-back was already pinned, and
`LR-BD` says it was not.** That ruling's evidence paragraph reads
"`ProposalScrollView`'s clamp, write-back, thumb floor, ramp and indicator clip
have **no test of their own** today". Four of the five are right; the
write-back is not.
`aProposalScrollViewClampsAnOffsetPastItsContentEndOnPrepaint`
(`NativeLayoutIntegrationTests.swift`) seeds a stored offset of 999, renders,
and reads 170 back out of the state table — which is the write-back, and
nothing else. **Mutation M1a reddens it**, alongside the two tests the ruling
names. The claim is corrected here rather than in `LR-BD`, which keeps its own
text as written; the fold's justification does not depend on it, because the
thumb floor, the ramp, the indicator clip and the `.hidden` guard genuinely had
no `ProposalScrollView` pin.

**2. M1d cannot redden test 1.2 as specified, and the gap was real.** Moving
`guard indicatorVisibility != .hidden` below `pass.requestAnotherFrame()`
leaves every *rect* assertion unchanged: the guard still returns before the
fill, so a `.hidden` scroller still paints nothing. The first run of M1d
reddened `hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake` and nothing
else. The mutant is observably different — it asks for a frame on every tick
while nothing fades, which is spec §4.4's exit criterion — so this is a gap in
1.2, not a broken instrument (practices, "a mutation that reddens nothing is a
broken instrument or it is the finding"). **1.2's `.hidden` arm now reads
`Frame.wantsAnotherFrame` on both halves of its differential**, `false` for
`.hidden` and `true` for `.automatic`, and M1d then reddens it. No test was
added; the arm was strengthened in place.

**3. M1f cannot redden test 1.4 as specified, because 1.4's fixture makes the
thumb floor inactive.** The design fixed 1.4's content at 200pt behind a 100pt
viewport, where the thumb is the proportional `100 × (100/200) = 50` and
`max(20, 50)` and `max(30, 50)` are the same number. A re-inlined private
`paintIndicator` with a 30pt floor — the drift `LR-BD`'s amended finding 3 says
only 1.4 can see — therefore left 1.4 green while reddening 1.2. Practices
shape 2, a fixture too shallow to distinguish two models. **1.4 now runs two
content heights**, 200 (the proportional regime) and 1000 (`100 × (100/1000) =
10`, floored to 20, against a drifted 30), parameterised in place so the count
does not move. M1f then reddens 1.4 and 1.2 both.

**4. `ScrollChrome`'s isolation is per method, not per type.** The three
members that take a pass (`resolvedOffset` ×2, `paintIndicator`) are
`@MainActor`, because `PrepaintPass` and `PaintPass` are; `clamp`, `extent`,
`delta` and `indicatorBounds` are not, so `ScrollChrome.clamp` stays the pure
function `ScrollView.clamp` was and the five re-pointed `ScrollViewTests`
assertions reach it unchanged. Marking the whole struct `@MainActor` would have
worked and would have isolated a pure value for no reason.

**5. `ScrollView.extent` folded with the rest.** §5 of the design listed
`extent` among `ScrollChrome`'s members but described only
`ProposalScrollView`'s copies as deleted. `ScrollView.extent` was `internal`
rather than `private`, so it could have had a caller outside the type; it had
none (an anchored grep, then the build), and it is deleted with the other six.

**6. `CN-R`'s generator was not in the repository, and the rebuilt one is
validated by its controls.** Record §18 cites `scratchpad/harness/gen-lib.py`;
session scratchpads do not survive, and it is gone. Lane 1 rebuilt it from
§18's and `CN-R`'s description — a test file injected into a `git archive` of
the commit under test, `@testable import MetalUIDemoContent`, twelve images
through a real `Window` over `FakePlatformWindow`, raw BGRA plus a scene dump
per image. **It is the same instrument, and that is measured rather than
assumed**: on an archive of `57893d0` it reproduces all five recorded controls
exactly — light vs dark f0 **1 048 576**, default vs modal **1 030 498**,
default vs animation **210 027**, f0 vs f3 **0**, preview light vs dark
**1 048 576** — and both recorded distinct-value counts, **544** for
`default-light-f0` and **216** for `chrome-legacy`. The harness lives in the
session scratchpad again; **whoever needs it after this stage will have to
rebuild it again, and the five controls plus the two counts above are what
tells them they got it right.** Committing it is a named deferral (stage 6b,
which owns the root switch and will want this comparison most).

**What it costs if wrong.** Items 2 and 3 are the expensive ones: each was a
test that looked like a pin and was not, in the one lane whose edit production
runs. Had either stayed as written, the fold would have shipped with its two
headline claims — "`.hidden` still costs nothing" and "the two elements cannot
drift apart" — resting on assertions that a drifting implementation passes.

**Amended, verification round (2026-09-22).** Three additions, none of them a
defect in the fold (record §25 §7.6, §7.8, §7.9, §12.3):

**7. The twelve `CN-R` images are blind to the indicator.** Item 6 and record
§7.6 presented them as this lane's pixel evidence, "the lane where a non-zero
reading would have been a finding". True for the clamp, the prepaint write-back
and the content clip; **not** for the indicator: none of the twelve scenes is
ever scrolled, so `lastScrollTime` is `-.infinity`, `alpha` is 0 and
`paintIndicator` returns at its `guard alpha > 0` before the `pass.fill`.
Measured by scanning every scene dump for the thumb's 3pt cross-axis rect — zero
hits in `default-light-f0`, `chrome-legacy`, `chrome-proposal` and
`preview-light`. The indicator half of the fold is pinned by **M1b–M1e** alone.

**8. This lane falsifies `CLAUDE.md`/`AGENTS.md` lines 472–473** — "
`ProposalScrollView`'s clamp and indicator are private copies of `ScrollView`'s
— fix both" — and nothing recorded the obligation. Item 4 of the critic round's
amendment deferred only the stale **line-range** citation
(`ProposalScrollView.swift:97-170`), not the claim. A lane may not edit
`CLAUDE.md`, so it is a **Docs-phase** obligation, now a deferral row in record
§25 §7.8 with the replacement text in that record's "For the integrator"
(followed by `cp CLAUDE.md AGENTS.md` and `cmp`). Practices: when a claim is
refuted, grep for everywhere it was copied.

**9. The fold concentrates a scroller's axis into one assignable property**,
`var chrome`, and mis-wiring `ScrollView`'s is caught by exactly one test whose
subject is the indicator rather than the scroll. Verifier mutation **V3**
(`ScrollChrome(axis: .vertical, …)` at `ScrollView.swift:245`, so a horizontal
scroller measures, translates and draws on the wrong axis) reddens only
`theHorizontalIndicatorLiesAlongTheBottomOfItsViewport`;
`aHorizontalScrollViewMovesOnDeltaXNotDeltaY` survives it, because it reads the
stored offset and the region's axis and never a painted rect — so **the
horizontal content clip's `chrome.delta(-offset)` translation is pinned
nowhere**. Pre-existing thinness; the fold is what concentrates it. Recorded as
a named unpinned sub-clause (record §25 §7.9); closing it is one assertion on
the scrolled content rect's x translation, owed by whoever next edits
`ScrollRoutingTests`, stage 6b at the latest. The verifier's other seven
mutations (V1, V2, V4–V7, V9) are in record §25 §12.2; only **V1** — the
`PaintPass` overload's read clamp — stayed green, and it is argued equivalent by
reading (the prepaint overload writes the clamp back) rather than measured.


## LR-BM — stage 3 lane 2's corrections: `parentSite:` names exactly one report, and two fixtures that were measuring the harness

**Round.** 2026-09-22, implementing lane 2 (the `ScrollView` lowering, `LR-BB`
and `LR-BC`) on `feat/engine-stage-3`. Everything below was measured in that
lane: the lowering itself landed with all eight predicted literals green on the
first implementation run, including test 2.7's hand-derived node and work
counts, and the corrections are to the **design's supporting claims**, not to
the mechanism.

### 1. `planLegacyItems` raises exactly ONE report at `parentSite:`

**The claim corrected.** `LR-BB`'s "Amended, stage-3 critic round 1" paragraph
(critic round 1 finding 9) says `LoweringSite.scrollView` stays reachable
because "a **child of the scroller** carrying an item field stage 2 does not
lower — `alignSelf: .baseline` (`LR-AD`), a percentage `flexBasis` (`LR-AI`),
unequal grow weights (`LR-AE`) — reports at `scrollView.<field>`", and spec
§4.1 and test 2.5 (c) were written to produce `scrollView.alignSelf` from a
child declaring `alignSelf: .baseline`.

**It reports `box.alignSelf.baseline`.** `planLegacyItems` collects each child's
entries into a local `reports` array and appends them as
`fields += reports.map { UnlowerableField(site: item.site, field: $0) }` — the
**child's** site. The **only** entry it raises at `parentSite:` is
`flexGrow.weights`, appended once by the weights check before the per-child
loop. Provable from source in two lines; no measurement was needed to find it,
only reading the function the ruling cited.

**So the route is the weights check**, which is a genuine scroller-**child**
fact reported at the parent's site: two children of one `ScrollView` declaring
unequal grow factors report `scrollView.flexGrow.weights`. Test 2.5 (c)
produces exactly that, and `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s
`ScrollView` arm — which lane 2 had to change anyway — uses the same shape, so
the site is now pinned live at field level by two tests instead of by a
paragraph. The **second** route `LR-BB` names, a field carried onto the content
node's unconsumed record, is unaffected and is what mutation **M2d** exercises
(`scrollView.flexShrink.unconsumed` appears in the demo's own report).

`UnlowerableField.owningStage`'s `case .scrollView: return "3"` stays live, and
`planLegacyItems`' doc comment now states the `parentSite:` rule where the
function is, so the next reader does not have to re-derive it.

**What it costs if wrong.** Nothing about the lowering moves; what moved is
whether the site's survival is *pinned*. Had 2.5 (c) been written as designed it
would have asserted `[scrollView.alignSelf]`, failed, and — on a less careful
day — been "fixed" by asserting whatever came out, which is
`box.alignSelf.baseline`: a green test proving the site is reachable while
proving nothing of the kind.

### 2. Two fixtures were measuring the harness, not the lowering

Both were found by running a mutation and reading **which** tests it reddened,
not how many.

**(a) `ProbeLeaf` is never stretched under the proposal authority, and test 2.3
was reading that.** `ProbeLeaf` registers a raw native leaf and records no
`LoweredItem`, so `planLegacyItems` gives it no wrapper — where the legacy
content container stretches it on the cross axis like any other flex item. Test
2.3's first fixture was `Box { ScrollView(.horizontal) { 2 × 80×40 } }` in a
100×**50** parent, so its two leaves read 80×50 legacy against 80×40 lowered and
the arm's "the content itself does not move" assertion was measuring the probe
type. The parent is now 40 tall, making the legacy stretch a no-op, and both
sides read 80×40. **The same property holds for all five of 2.1's agreement
arms** — every leaf's cross size already equals its container's — which is
recorded in that test's own doc so the next fixture is not written by accident.

**(b) Mutation M2b reddened four tests and test 2.1 was not among them.** The
design predicted that registering the scroll content through
`requestNativeLinearStack` instead of `lowerLegacyNode` would move "A2's stretch
rows". It does not: every 2.1 arm's scroll content is fixed-size leaves that
record no item field, so `planLegacyItems`, `arrangeLegacyMainAxis` and
`paddedAndSized` are all no-ops over them and a bare stack produces **identical**
geometry. The mutation was caught only by the three diagnostics tests and the
demo census — that is, by "the records were not consumed", never by "the layout
is wrong".

Arm **A2b** closes it: the scroll content's second child declares
`alignSelf(.center)`, 40 wide in an 80-wide content column, so the legacy column
centres it at x 20 and only `lowerLegacyNode`'s alignment frame reproduces that.
Re-run, M2b reddens 2.1 as well. It is an arm, not a test, so the lane's total
stays at the predicted 1561.

**What it costs if wrong.** This is the one that would have shipped. Without
A2b, "the content node goes through the container lowering" — `LR-BB`'s central
claim, and the reason the demo's own scroller is not the test — was pinned by
**nothing geometric at all**. A future simplification that replaced
`lowerLegacyNode` with a bare stack would have left every rect in the lane
green, and would have been caught only by whichever diagnostics expectation
happened to still name a consumed record.

### 3. The demo's modal state changes two lowered widths in the scroll subtree

Measured while amending `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`:
with the modal on, the lowered `ScrollView` and the lowered `List` read **420**
wide where they read 0 with it off. The cause is neither the modal nor the
lowering. `Deferred` registers no node of its own and hands its child's node
straight up (`Deferred.requestLayout` returns `nodes[0]`), so with the modal on
the lowered content node has **two** children instead of one; stage 2's
single-child stretch elision (`LR-AC`) applies only to a single child under a
parent with no declared cross size, so both children are now stretched, the
`List` takes a greedy item frame and reads the 420 its scroller was proposed,
and the content stack — hence the viewport's non-scrolling axis (`CN-M`) —
reads 420 with it. The `List`'s row `Box` stays 0×0 because the `List` still
reports and still builds no rows.

Recorded as three per-id overrides in the modal half of the exit test, with the
cause named there. Nothing is wrong: it is stage 2 behaviour made visible by
stage 3, and it disappears when stage 4 lowers `List`.

### 4. Lane 2's evidence

Full unfiltered `swift test --build-system native --no-parallel` after each
edit; every mutation committed first, applied to a copy, and restored with
`git status --short` empty afterwards.

| # | mutation | tests reddened (by name) |
|---|---|---|
| **M2a** | the viewport registered as a plain native leaf | **8**: 2.1, 2.2, 2.2a, 2.3, 2.4, 2.5, 2.7, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` |
| **M2b** | the content node registered through `requestNativeLinearStack` instead of `lowerLegacyNode` | **5** (after A2b; **4** before it): 2.1, 2.5, `anItemFieldNoLoweredContainerConsumesIsReportedByName`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`, the demo census |
| **M2c** | the viewport lowered as a `fixedSize` over its content | **6**: 2.1, 2.2, 2.2a, 2.3, 2.5, the demo census |
| **M2d** | `flexShrink: 0` carried onto the lowered content style | **10**: 2.1, 2.2, 2.2a, 2.3, 2.4, 2.5, 2.7, both diagnostics tests and the demo census — whose report becomes `[list.noLowering, scrollView.flexShrink.unconsumed]`, which is the entry the omission is observable through |
| **M2e** | the content node registered with `site: .modifierLayer` | **2**: 2.5, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| **M2f** = **M2i** | `recordLoweredItem` dropped from the lowered `ScrollView` (the design lists these separately; they are the same edit) | **4**: 2.2, 2.2a, 2.5, 2.7 |
| **M2g** | both `animated(…)` calls given the bare `id` | **4**: 2.1, 2.6, `everyRegisteringSiteAnimatesItsStyle`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows` |
| **M2h** | the content node registered twice | **1**: 2.7 |

Suite at the lane's HEAD: **`Test run with 1561 tests in 1 suite passed`** — the
design's predicted total exactly. Goldens unchanged (97, `git diff --name-only
57893d0 HEAD -- 'Tests/**/*.json'` empty). Typecheck guards 77, unchanged; the
lane adds no public spelling and no guard.

**Pixels: twelve of twelve read 0 differing pixels** against `57893d0`, every
scene dump byte-identical. The `CN-R` harness had to be rebuilt again (it is
still uncommitted; `LR-BL` item 6 and the stage's §10 own that), and it
reproduces **all eight** of the control figures the record keeps for exactly
this purpose — 1 048 576 / 1 030 498 / 210 027 / 0 / 1 048 576, 544 distinct
values in `default-light-f0`, 216 in `chrome-legacy`, and 0 between the two
chrome images.

**No real-window capture.** The screen was **locked** when the lane finished
(`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`; `IOConsoleLocked` not
read, `FR-V`), as it was at the end of lane 1. The twelve offscreen images
stand in.

**Amended, verification round (2026-09-22).** Three rows of the table above are
attribution defects — the behaviours are right, the mutations are not what the
rows say — and one sentence of `loweredLayout`'s doc comment is broader than the
code. Corrected in record §25 §8.5 and §12.3, and in the source comment:

1. **M2g is two different mutations.** Scoped to `loweredLayout`'s two
   `animated(…)` calls it reddens **2** —
   `aLoweredScrollViewKeepsItsTwoAnimationSlots` and
   `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape` (8 issues).
   The recorded set is the **whole-file** spelling's, which also hits the legacy
   branch's byte-identical pair (`ScrollView.swift:319/330`, `386/396`) and
   reddens `aLoweredScrollViewKeepsItsTwoAnimationSlots` (once per authority),
   `everyRegisteringSiteAnimatesItsStyle` and
   `theResidentEntrySetStaysBoundedWhileScrolling10kRows` — and **not** 2.1,
   because mutating both branches keeps the two `StateTable.ids` sets equal so
   `stateSlotsEqual` stays true (`LayoutDifferential.swift:232`). Record which
   branch a mutation touched.
2. **M2c reddens 7, not 6**: 2.7's hand-derived node and work counts move when
   the viewport's node kind changes. Spelled
   `pass.frame.requestNativeFixedSize(child: contentNode)`.
3. **M2h is not applicable as literally written.** The same children under a
   second `requestNativeLinearStack` traps at `LayoutTree.swift:743` (`CN-L`'s
   one node, one parent) and truncates the run with no summary line; the
   recorded reddening is the **orphan childless** duplicate's.
4. **`reportUnconsumedLoweredItems` reads `item.declared` only**, never
   `item.animated`, so "a field a later stage puts on it reports rather than
   vanishing" holds for the **declared** content style alone — a field added to
   `contentStyle` would be dropped with no diagnostic, which is also why M2d has
   to be applied to `declaredContent` to be observable. `LR-AS`'s convention
   (structural item fields on the declared style) is the only thing that keeps
   the case narrow; the doc comment now says so.

---

## LR-BN — stage 3 lane 3's corrections: a roll call rather than a counter, 34 scenarios rather than 37, and the fixtures whose cross axis had to be declared

**Round.** 2026-09-22, implementing lane 3 (the scroll suites under both layout
authorities, `LR-BI`) on `feat/engine-stage-3`. Everything below was measured in
that lane; each item corrects or extends `LR-BI` rather than replacing it.

### 1. The exit test is a roll call, not a counter

**`LR-BI` asked for "a counter incremented by the parameterised arms, with a
`try #require` on the arm count".** That shape cannot be made falsifiable in
Swift Testing. Test ordering is not part of the framework's contract, so a
counter read by a test that happens to run before the arms reads zero and
passes — practices shape 14's "a test that cannot fail", paid for with the
stage's exit criterion. `Test.all`, which would have let the check read the
declared parameterisation instead of its executions, **does not exist in this
toolchain** (Swift 6.4, `swiftlang-6.4.0.33.1`: `type 'Test' has no member
'all'`, measured).

**Applied.** `ScrollAuthorityCoverage` (`Tests/MetalUITests/`) holds the 34
scenario names by hand and the single `arguments:` list every scenario is
declared over, and the claim is split in two:

- **Order-independent**: `record(_:_:)` verifies the whole set the moment the
  last expected name first arrives. It skips the name it is called with, and
  that is not a hole — Swift Testing runs one test's argument cases back to back
  (measured: `… → .legacy` then `… → .proposal` for the same function), so every
  *other* name has had all its arms by then, while that one has had exactly one.
  A scenario recording a name not in `expected` reddens in its own arm.
- **Order-dependent, and measured rather than assumed**:
  `everyScrollScenarioRanUnderBothLayoutAuthorities` holds the literals — the
  34, and `authorities == LayoutAuthority.allCases` — and reads what has been
  recorded. Swift Testing runs a file's tests in source order and the files in
  path order (measured twice, identical: `ScrollIndicatorTests` →
  `ScrollRoutingTests` → `ScrollViewTests`), so the test is declared at the end
  of the last of the three. If that order ever changes it fails **naming the
  scenarios it had not yet seen**, rather than passing quietly.

**M3c still reddens both halves**, which is the point: reducing `authorities`
to `[.legacy]` fails the literal `#require` in 3.4 *and* raises 33 issues from
`record`'s whole-set check (measured: 34 issues across 2 test names).

### 2. 34 scenarios, not 37 — `ScrollViewTests`' census

`LR-BI` counts `ScrollViewTests`' 7. **It declares no custom element type at
all** (the census `LR-BI` item 5 asked for: no `requestNode`, no `requestLeaf`,
nothing to re-spell), and **three of its seven are pure `ScrollChrome.clamp`
tests** — `theOffsetClampsToTheScrollableRange`,
`contentShorterThanTheViewportDoesNotScroll`,
`aStoredOffsetPastTheEndIsClampedWhenItIsRead` — each one static call with three
`Double`s. No element, no `Frame`, no authority anywhere in the call path, so an
authority argument would be one the body never reads and the two cases would run
the identical assertions: a parameter that cannot make either arm fail
differently from the other. They stay unparameterised, and 34 is the hand-derived
count 3.4 requires.

### 3. Seven fixtures had to declare their cross axis, and it moved no legacy number

A `ScrollView` whose **only** child declares just the scrolling axis relied on
the legacy engine stretching that child across the definite viewport. The kernel
viewport's cross answer is its CONTENT's (`CN-M`) and a single child is exempt
from the stretch item frame (stage 2's elision, `LR-AC`), so the same fixture
measures a **0-wide viewport centred at the window's midpoint** under the
proposal authority — stage 2's ruled divergence, already pinned by lane 2's test
2.4, and not what these scenarios are about. Measured, at 120×100:
`ScrollView(.vertical) { Box(style: fixedHeight(200)) }` registers `(0, 0)
120×100` under the legacy authority and `(60, 0) 0×100` under the proposal one.

**Applied**: the single-child fixtures declare both axes, and the padded-row
wrapper of `theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt`
declares its width (a native root is centred at its own answer, `CN-J`, so that
column's 117pt hug would put the viewport at x 39 rather than 17). **No legacy
literal moves**: the stretch already produced exactly these numbers, which is
what the unchanged legacy arms of all 34 scenarios say.

The same could not be done for 3.5. A **vertical** scroller in a 100pt wrapper
measures 200 under the legacy engine (the viewport hugs its content and
overflows) and 100 under the proposal authority — which is `LR-BC`, pinned by
2.2 — so 3.5 uses a **horizontal** scroller, whose scrolling axis is the cross
axis of its column parent and where the two authorities agree at 120.

### 4. Two probe types, and what the re-spelling does not carry

`ScrollContextRecorder` and `HitboxProbe` take `ProbeLeaf`'s shape, as `LR-BI`
says. Their declared `Style`s become a `width`/`height` pair, so the two arms
cannot drift. **The cross axis they used to leave `.auto` is not carried**: under
the legacy authority the parent stretches it, under the proposal authority it is
the leaf's own answer. No scenario reads it — checked call site by call site —
and `HitboxProbe`'s two sites declared both axes already, so the scrim covers
the same 200×200 under either engine.

### 5. Mutations, and one that becomes a process abort

Re-taken at the lane's HEAD (`a1b8ff3`), full unfiltered runs, restored from a
copy with `git status --short` empty after each.

| # | mutation | tests reddened (by name) |
|---|---|---|
| **M3a** | `registerScrollRegion` given the content node's rect instead of the element's | **6** (8 issues): `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove` (**both** arms), `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting`, `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents`, `aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows`, `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`, `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` |
| **M3b** | the bounds alias dropped in `Frame.bounds(of:)` | **34** (202 issues) — and **none of them is a lane-3 arm**: see below |
| **M3c** | the `arguments:` list reduced to `[.legacy]` | **2** (34 issues): `everyScrollScenarioRanUnderBothLayoutAuthorities`, `aScrollViewWithNoCornerRadiusClipsSquare` (the arm whose `record` completes the set) |
| **M3d** | `withScrollContext` moved after the content build | **15**: `aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`, `rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange` and `nestedScrollViewsInnermostWinsAndPoppingRestoresTheOuterContext` (each under **both** authorities), plus 11 `List` and accessibility tests |
| **M3e** | the prepaint overload's `viewportExtent` write removed | **13**: `aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout` (both authorities), plus 11 `List` and accessibility tests |
| **M2a** (re-taken) | the viewport registered as a plain native leaf | **31** (77 issues), where lane 2 read **8** — 21 of the 34 parameterised scenarios are among the new ones. This is the lane's own headline: the scroll suites can now see the lowering |
| **M2d** (re-taken) | `flexShrink: 0` carried onto the lowered content style | **aborts the process**: see below |
| **M1c** (re-taken) | the 20pt thumb floor removed | **3**: `theThumbIsProportionalAndFlooredAtTwentyPoints` under **both** authorities (lane 1 read one arm), `theTwoScrollElementsShareOneChromeImplementation`, `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent` |

**M3b reddens 34 tests and not one of them is a scroll scenario.** The alias is
load-bearing for a scroller whose lowered parent stretches or grows it, and no
fixture in the two scroll suites is in that position — they are window roots or
single children. The claim is pinned, by lane 2's
`aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` and by stage
2's `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`, both of
which M3b reddens. **Lane 3 owes no new test for it**; the design's expectation
that "the lowered arms' regions move" was wrong about which fixtures could see
it.

**M2d no longer produces a list of red tests: it aborts the run.** At lane 3's
HEAD the first proposal-authority `Window` holding a `ScrollView` is test #1251,
`aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, and a production frame
traps rather than reporting:

```
MetalUI/Frame.swift:1536: Fatal error: MetalUI: scrollView.flexShrink.unconsumed
has no proposal lowering (plan task 7, stage 3); a tree containing it cannot run
under the proposal layout authority.
```

Ten tests had already recorded issues by then — lane 2's ten exactly — so the
mutation's evidence is unchanged; what is lost is the summary line. **This is the
trade `LR-BI`'s amendment took deliberately** when it put real `Window`s under
the proposal authority, and it is now a standing property of the suite: from this
lane onward, an unlowerable-field regression reachable from a scroll fixture
truncates the run at that test, with the field named on `stderr`. A per-fixture
diagnostics pre-flight (what `WindowPair.init` does) would convert it back into a
named failure, and was **not** applied.

**Amended, verification round (2026-09-22).** The reason as first written —
"these fixtures' content closures capture shared recorder boxes" — is broader
than the measurement, and scopes the deferral larger than it needs to be.
Measured (`awk '/^func |^@Test/{last=$0} /Seen\(\)/{print NR": "last}'` over
`ScrollRoutingTests.swift`): **exactly four** of the 34 scenarios construct a
`Seen` box —
`scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`,
`rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange`,
`nestedScrollViewsInnermostWinsAndPoppingRestoresTheOuterContext` (two boxes)
and `aSiblingAfterAScrollViewSeesNoScrollContext`. For those four a second
render would add a phantom entry to every `Seen` and break the tests the
pre-flight was protecting. `HitboxProbe` (`ScrollRoutingTests.swift:864`,
`:902`) is stateless and captures nothing, so **the remaining 30 scenarios are
eligible** for a `WindowPair`-style pre-flight. Stage 6b inherits a
four-fixture problem, not an all-or-nothing one. (Record §25 §9.6, §12.3.)

### 6. What it costs if wrong

If item 1's ordering claim goes stale, 3.4 fails loudly and names what it had
not seen — recoverable. If item 3's fixture changes had moved a legacy number,
the 34 legacy arms would have said so on the first run; they did not. The
genuine exposure is item 5's last paragraph: a future regression of the
`…unconsumed` shape costs a run with no summary line before anyone sees the
field's name.

**Amended, verification round (2026-09-22).** Item 1's ordering dependence and
item 5's truncation are both **CI-visible failure modes that `CLAUDE.md`'s "CI —
what lapses silently" list does not carry**, and a lane may not edit that file.
Two rows are owed in the Docs phase, with the text record §25's "For the
integrator" gives: `everyScrollScenarioRanUnderBothLayoutAuthorities` is
order-dependent (measured only on Swift 6.4, `swiftlang-6.4.0.33.1`) and
`--filter`-hostile, and an `…unconsumed` regression truncates the run rather
than failing by name.

## LR-BO — stage 3 lane 4's corrections: a frame parent drops what a flex parent carries, `component` loses its last reachable report, and two fixtures that could not see their own subject

Lane 4 implemented `LR-BG` as written; the amend frames each member, the wrap
lowers through `lowerLegacyNode`, and **all seven of the design's prototype arms
(C1, C2, C3, C4, C5, C7 and C1's y) reproduced on the first run**, literal for
literal. Four things the design said were wrong or unreachable, and one mutation
reddened nothing.

**1. "The frame lowers with the field applied" is wrong for `flexGrow` and
`margin`; they are consumed and DROPPED.** `LR-BG`'s amendment says
`loweredComponentFrame` plans the member "exactly as `lowerLegacyLayer`'s
single-node arm does", which is `parentKind: .stack` — and a stack or
frame-layer parent ignores a child's `flexGrow`, `flexShrink`, `flexBasis`,
`alignSelf` and `margin` outright (`LR-AZ`, `MC-Q` finding 7). The two claims
cannot both hold. **The parent kind stays `.stack`**: a frame has one child and
no axis, so there is no non-arbitrary `isRow` for it, and every other frame in
the lowering already behaves this way. What planning buys is the rest:
a `minSize` on an `auto` axis becomes the item frame W's minimum, a `maxSize`
off a greedy axis reports at the member's site, and — the whole point of the
amendment — the record is **consumed**, so nothing reaches
`reportUnconsumedLoweredItems` and nothing traps at 6b.

So `MyComponent().width(70)` over a member declaring `.flexGrow(1)` lays out
differently under the two authorities: the legacy member grows to the enclosing
row's 300, the lowered member stays 30 inside its own 70pt frame. That is a rect
disagreement the differential harness prints, not a silent one and not a crash,
and it is the same shape of loss `.frame(…)` over one member has had since
`LR-H`. Making it **report** instead was considered and rejected for the reason
critic round 1 finding 8 gave: a report is a trap in a production frame, and
turning a working legacy tree into an abort is worse than laying it out
differently. Applying the fields instead — `parentKind: .flex(isRow:)`, with
`isRow` guessed from the patch — is **deferred to stage 6b**, which owns what
production trips over; it needs a probe of its own, because SwiftUI has no
`flexGrow` to be measured against.

**2. `component` has no reachable report left, and the site survives for its
trap message alone.** `component.amend` and `component.wrap` were its only two
entries. After lane 4 neither op can raise anything at its own site: an amend
records its frame with `kind: .frameLayer`, which `reportUnconsumedLoweredItems`
skips by construction, and **both** ops plan exactly one child, so neither can
raise `flexGrow.weights` — the one entry `parentSite:` names (`LR-BM`). Nothing
else in `legacyContainerDiagnostics` or `legacyLeafDiagnostics` can fire on
`paddingWrapperStyle`, whose every field is a default but a pixel `padding`.

This is the shape critic round 1 finding 9 caught for `scrollView`, with the
opposite outcome: `scrollView` had a route (`flexGrow.weights`, two scroller
children) and `component` has none. The case stays in `LoweringSite` so that
`UnlowerableField.owningStage` gives the right stage number to whatever field a
later stage puts there, and
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s two `Component` arms
**invert**: they now assert the absence of an entry, which is what would notice
a regression that made either op report again. The amend arm stays a child
process, because in-process a regression that removes the branch entirely
reaches `SA-G`'s `setStyle` precondition and ends the run with no summary line.

**3. The `…unconsumed` entries the design predicted carry the MEMBER's site,
not `component`'s.** The design's 4.6 row says mutation M4f produces
`component.flexGrow.unconsumed` / `component.margin.unconsumed`.
`reportUnconsumedLoweredItems` reports at `item.site` — the record's own — and
the record belongs to the member. Measured under M4f: `[box.flexGrow.unconsumed]`,
`[box.margin.unconsumed]`, `[box.minSize.unconsumed]`. The test asserts
emptiness, which is site-agnostic and was unaffected.

**4. Two fixtures could not see their own subject.**

- **Test 4.6 needed a third arm.** With `parentKind: .stack`, neither of the
  design's two arms (`flexGrow`, `margin`) is planned at all, so **M4g** —
  "consumed but not planned" — could not redden either. A third arm whose member
  declares `minWidth(40)` on an **`auto`** width is the discriminating one: only
  the parent's plan can apply it, and M4g drops the member from 40 wide at x 15
  to 0 wide at x 35. A declared width would not do: `paddedAndSized` folds
  `max(min, min(size, max))` into the member's own frame, so the minimum would
  be applied whether or not anything planned.
- **Test 4.2 needed arm C3a, because M4b left all 1569 tests green.** C3's
  members are fixed 30×10 leaves declaring no item field, so over them
  `planLegacyItems`, `arrangeLegacyMainAxis` and `paddedAndSized` are no-ops and
  a bare `requestNativePadding` produces byte-identical geometry. This is
  `LR-BM`'s M2b finding again, in the same shape and for the same reason, one
  lane later. C3a's member declares a `margin`, which only the container
  lowering carries (the legacy wrapper's content box is the member's **margin**
  box): both authorities read (12, 12, 30, 10), and M4b moves the lowered side
  to (8, 8) and reports `box.margin.unconsumed`.

**5. `swift package clean` was not needed, and that is a measurement.** Critic
round 1 finding 12 asked for it either way. `ComponentModifierOp.amend`'s
payload changed from a 2-word closure to a `Size<Dimension>`, and the enum is
the element type of `ops` on the **public** generic `StyledComponent`. The
incremental build over that change was correct — 1569 tests, all passing — and
a `swift package clean` plus full rebuild read the same 1569. The reasoning
("an `Array` is one word either way") held; it was still checked rather than
asserted.

**What it costs if any of this is wrong.** Item 1 is the load-bearing one: if
dropping `flexGrow` and `margin` at an amend frame turns out to matter, stage 6b
finds it as a demo pixel or a rect disagreement, not as a crash, and the fix is
one argument. Item 2 costs a site that reports nothing; the risk is that a later
stage adds a `component` field and forgets that the two arms assert absence —
which is why both arms carry the reason at the arm.

**Amended, verification round (2026-09-22).** Two of item 2's and the helper's
claims are true but not where the load is; both are now in the source doc
comments as well (record §25 §10.2, §12.3):

- **`kind: .frameLayer` is the second reason `component` cannot report, and not
  today's decisive one.** Verifier mutation **Vj** recorded the amend frame as
  `kind: .stack` and the full 1569-test suite stayed **green**. Traced by
  reading: `componentFrameStyle` carries no field
  `reportUnconsumedLoweredItems` names — no `minSize`, no `maxSize`, no
  `margin`, no grow or shrink — so the record would stay silent even unconsumed
  and even as a `.stack`; and `planLegacyItems`' three `.frameLayer` branches
  raise no report and plan no extra wrapper for it. `.frameLayer` is the guard
  that **takes over** when that stops being true, so **whoever puts a bound into
  `componentFrameStyle` — to carry a member's dropped minimum, say — owes a pin
  in the same change**, or a stage-6b production trap arrives with nothing
  seeing it go.
- **`componentFrameStyle`'s `display = .stack` and its per-axis ternaries are
  cosmetic.** Verifier mutation **Vk** (both ternaries a constant `.center`,
  `display` deleted) stayed green, while **Vi** (both assignments deleted)
  reddens four tests: so "non-nil and non-stretching" is the whole content of
  those lines. `alignsByStretching` and `stretches` are false for `.start`,
  `.flexStart` and `.center` alike, and `parentKind: .stack` is passed
  explicitly at the call site, so this style's `display` is never consulted. The
  per-axis alignment lives entirely in `componentFrameAlignment`; the spelling
  is kept as documentation and the doc comment now warns that mutating it moves
  no rect.

## LR-BP — stage 3 lane 5's corrections: a dropped margin the mutation cannot see, an M5d with no subject left, and an M5a the demo cannot reach

Lane 5 implemented `LR-BH` as written and as amended. `lowerLegacyLayer`'s frame
arm registers one native frame per child node, rows more than one with
`requestNativeLinearStack(axis: .horizontal, spacing: 0, alignment:
spec.alignment)`, runs `planLegacyItems` for **every** child count and rows
`registerLegacyItems(children, plans)` in full; `legacyFrameLayerDiagnostics`
loses its `frame.multipleNodes` row. **Prototype arm C6 reproduced on the first
run, literal for literal** — legacy one 70×40 frame with the members squeezed to
26 and 44 at y 15, lowered a 140×40 row with the members at their own 30 and 50,
centred at x 20 and 80, y 15 — and the whole suite read the design's predicted
**1572**, to the test. Four things the design said were wrong.

**1. The margin in 5.1a is consumed and DROPPED, so M5e cannot see it.** The
design's M5e row says skipping the planning makes "both rects lose the margin
and the floor". The parent kind is `.stack`, which `LR-BH`'s amendment
prescribes and which `LR-BO` item 1 already established drops a child's
`margin`, `flexGrow`, `flexShrink`, `flexBasis` and `alignSelf` outright
(`LR-AZ`). A dropped field is dropped with or without the planning, so member
a's rect is **identical** under M5e. Measured: M5e reddens exactly **one**
assertion — member b's `auto` width with a 40pt `minWidth`, which reads
(100, 15) 40×10 planned and (120, 15) **0**×10 unplanned. The margin member
stays in the fixture because a dropped field should be pinned as dropped rather
than left unmeasured, and the test says at the arm which half the mutation can
see. This is `LR-BO` item 1 one lane later, in the same shape: the same wrong
sentence was written twice, about the two frames that share the same
`parentKind`.

**2. M5d has no subject after the row is deleted, and restated it is stage 1's
M4i.** §6's M5d is "`display.none` checked after the multi-node arm" —
but `legacyFrameLayerDiagnostics` has no multi-node arm once
`frame.multipleNodes` is gone; the only thing `display.none` can be moved behind
is the `style` comparison, which is exactly M4i. Run as that: it reddens
`aHiddenFrameLayerIsReportedAsDisplayNone`, 4 issues, the hidden arms reading
`[modifierLayer.style]`. The re-spelled control arm is kept anyway, and its
value is now the opposite of what it was: as a `frame.multipleNodes` expectation
it pinned a diagnostic, and as an **empty** expectation it is the only
discriminator in that test for "`display.none` is checked first **and alone**" —
four arms that all expect one entry cannot tell that apart from a check that
never reaches a second one.

**3. M5a cannot redden the demo exit test, and §7's list is wrong to name it.**
`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` stayed green under
M5a (which reddens 5.1 and 5.1a, 3 issues, and nothing else in 1572). The cause
is structural, not incidental: `demoContent()` contains **no** `.frame` at all,
and `DemoContent.swift`'s only two `.frame(` sites are inside
`nativeLayoutPreviewContent()`, where they are proposal `ModifiedContent`
wrappers and never reach `lowerLegacyLayer`. No shape in the demo is a
`ModifiedElement` frame layer over a multi-member `Component`, so no lane-5
mutation can reach that test. Same shape as `LR-BN` item 5's M3b: a mutation
attributed to the corpus test by the milestone that wrote the corpus test,
without checking that the corpus contains the shape.

**4. The row is invisible to every rect; the node count is what pins it.**
**M5c** — the `count > 1` arm entered at `count == 1`, so a lone frame is wrapped
in a one-child row — moved **no rect anywhere in the suite** and reddened exactly
one issue, 5.2's hand-derived node count. A one-child linear stack at spacing 0
is geometrically transparent. So the design was right to spell 5.2 as a count,
and the lane added the same instrument to 5.1: two per-member frames and one row
are **+3** native nodes over the same component with no frame, where one member
is **+1**. Without those two counts, "one frame per member, rowed, and no row
wrapper at one node" would have been three claims pinned by two rect tables that
cannot see any of them.

**What the lane added to the design's test list.** 5.1 gained the +3 node count
(the design had rects only) and the frame layer's own bounds as a third row
(legacy 70×40, lowered **140**×40, which is what M5a's 148 moves); 5.2 gained a
rect arm asserting the single-node geometry is unchanged, `mustDiffer: false` on
both sides. No test was added or removed: 1569 + 3 = **1572**, as predicted.

**What it costs if any of this is wrong.** Item 1 is a documentation defect with
a live consequence only if someone later reads "the planning applies the margin"
and removes the arm that pins the drop. Item 3 costs a false sense that the
demo's corpus covers this lane; it does not, and the lane's own two tests are
the whole coverage. Item 4 is the one that would have cost a real hole:
everything about the row's *shape* is unobservable in a rect.

**Amended, verification round (2026-09-22).** Item 4's "the node counts are the
whole pin" is right about the row's presence and **wrong about one of its
arguments**: the row's cross-axis `alignment: spec.alignment` is pinned by
nothing. Verifier mutation **M5g** — the argument hard-coded to `.center` — left
the full unfiltered suite green at **1572**, and the mutant is **not
equivalent**: over uneven members (30×10 and 50×30) under
`.frame(width: 70, alignment:)` a scratch differential reads y 0 / 0 for
`.top`, 25 / 15 for `.center` and 50 / 30 for `.bottom`. Both committed tests
declare a height (`.frame(width: 70/80, height: 40)`), which makes every
per-member frame the same height and the row's alignment invisible; probe arms
W7/W8 are equal-height frames for the same reason; and SwiftUI has **no row**
here at all — the framed members are siblings of the enclosing stack, whose own
alignment governs the cross axis — so `spec.alignment` on the row is an unprobed
MetalUI choice rather than a measured one. Recorded as a green mutation in
record §25 §11.5 and deferred in §11.10: **stage 11**, with the siblings
question `TB-M` owns, or one uneven-height, height-free arm on 5.1 from whoever
next edits `LoweringComponentTests`.

---

## LR-BQ — `List` lowers to a windowed `ProposalLayout`, although its CSS structure already lowers for free

**The question.** §4.1 row 4 asks for "a windowed `ProposalLayout` placing
realized rows at `index × rowHeight`". Before designing one, stage 4 measured
what it would replace. Prototype **P1b** (record §26 §2.2) deleted `List`'s
four-line site check and changed nothing else, so the existing structure — a
leading spacer `Box` sized `window.lowerBound × rowHeight`, `flexShrink: 0` and
`minSize.height: 0` on every row, a declared `size.height` of
`count × rowHeight` on the container — went through stage 2's container
lowering as an ordinary flex column.

**What the measurement said.** It lowers, cleanly. In a container with a
declared width and `Box` row content (arm **P1a6**): **0 unlowerable fields, 11
ids, 0 disagreeing, `stateSlotsEqual` true** — the container, the spacer, every
row `Box` and every row's content byte-identical to the legacy engine. Padded
and scrolled (arm **P1a3**), rows land at y = 60, 88, 116 … 312 on both sides.
Windowed, unwindowed, padded, and with a row taller than `rowHeight`: every
row's **y** and every row's **height** agree in every arm. The width
disagreements in the arms without a declared container width are
`DifferentialRoot`'s divergence 53 and `ProbeLeaf` recording no `LoweredItem`,
not `List`'s.

So the honest statement is: **stage 4 could have been four deleted lines plus
test work.** The decision is to build the layout anyway.

**The decision, and the four reasons, in the order of their weight.**

1. **Stage 9 forces it.** Stage 9 deletes `FlexEngine`, the legacy registrars
   and the legacy authority; stage 10 deletes `Style`'s CSS fields and narrows
   `StyledElement.style` to what paint and animation read. At that point
   `List` has no `flexShrink`, no `minSize`, no `flexDirection` and no
   `size.height` to write, and the free lowering has nothing to lower. The
   windowed layout is not optional work; it is work stage 4 or stage 9 must
   do, and stage 4 is where the differential oracle still exists to check it
   against. §8's stage-4 row already assigns it here.
2. **It states the invariant once.** `index × rowHeight` currently emerges
   from four independent CSS devices, and `List.swift` spends roughly sixty
   lines of doc comment explaining that two of them no longer do what they were
   written for (`minSize.height = 0`'s mechanism "NO LONGER FIRES"; the
   `flexShrink` half "was NOT re-measured"). A layout that computes
   `bounds.y + index × rowHeight` cannot drift from its own documentation.
3. **The free lowering is a better oracle than a shipped mechanism.** P1b's
   agreement is exactly what lane 2's test 2.1 asserts the windowed layout must
   reproduce: the literals in that test are P2's and P3's measured tables, and
   they were taken from the free lowering before the windowed one existed.
   Keeping the free lowering as the thing we *check against* rather than the
   thing we *ship* is what makes lane 2 red-first with real numbers.
4. **Work.** Marginal, and named last because it is the weakest. A linear
   stack over the window measures every realized row to answer its own size;
   the windowed layout answers a concrete proposal with **zero** subview
   measurements. Both are O(window) and independent of `logicalCount`, which is
   what the exit test asserts, so **the exit test cannot tell them apart** —
   said here so that nobody later reads the work count as this ruling's
   evidence.

**What it costs if wrong.** If the windowed layout is the wrong shape, the cost
is one lane: lane 2 is a single commit over lane 1's, and lane 1 (the group,
legacy only) stands on its own. The fallback is P1b — delete the site check,
keep the CSS structure, and hand the layout to stage 9 — and the fallback's
correctness is already measured rather than hoped for. The larger risk is the
opposite one: shipping the free lowering and discovering at stage 9, with no
legacy engine left to diff against, that `index × rowHeight` was resting on a
flex behaviour nobody had pinned.

**Amended, stage-4 critic round 1 (defect D10).** Reason 4's "zero subview
measurements" is **wrong**, and its conclusion survives.
`LayoutTree.placeCustom` (`Sources/MetalUILayout/LayoutTree.swift:1040-1070`)
measures every child again after `placeSubviews` returns, to turn each
placement record into a rect — so the windowed layout costs **one
`measureNative` lookup per realized row** on a concrete proposal, not zero, the
same order the linear stack costs. Reason 4 was already the weakest of the four
and already said the exit test cannot tell the two arrangements apart; after the
correction it says so more strongly, since the two are not merely the same order
but the same count. The corrected arithmetic — including the nil-width path,
where it is `O(logicalCount)` rather than `O(window)` — is `LR-CA` and spec
§3.2.1. **Reasons 1–3 do not move, and they are what this ruling rests on.**

---

## LR-BR — the windowed layout answers its content extent on the stacking axis and its proposal on the other; probe K6 is consulted and deliberately not followed

**The question.** §4.1 row 4 names "probe K6's layout answer" as an input.
What should `List` answer?

**What K6 says, re-run today.** `docs/probes/swiftui-stack-algorithms.swift`
under `/usr/bin/swift` (Apple Swift 6.4, swiftlang-6.4.0.33.1), macOS 27.0,
exit 0, **the whole 787-line stdout byte-identical to the reading in the
probe's own header** (`diff` empty):

```
K6 control fixed 30x30 at 100x100 @100x100: size 30x30
K6a List{Text} at 100x100 @100x100: size 100x100
K6b List{Text} at nil @nilxnil: size 0x0
K6c List{Text} at 100 x nil @100xnil: size 100x0
K6d List{Text} at nil x 100 @nilx100: size 0x100
K6e List{Text} at inf x inf @infxinf (measured only): size infxinf
K6f List{leaf l 30x30} at 100x100 (is a row laid out?) @100x100: size 100x100
```

SwiftUI's `List` is greedy and content-blind: the proposal on a concrete axis,
0 on a nil one, ∞ at ∞, and K6f shows a row's own 30×30 never reaching the
answer — against the K6 control, which does answer 30×30.

**The decision.** `WindowedRowsLayout` answers:

- **height** (the stacking axis) = `rowHeight × Double(logicalCount)`, at every
  proposal — **not** K6's;
- **width** = `proposal.width` when there is one — K6's — and otherwise the
  maximum of the realized subviews' answers at `(nil, rowHeight)` — **not**
  K6's 0.

**Why K6 does not transfer, on either axis.** SwiftUI's `List` *is* a scroller:
it owns its scrolling, so the size it reports is its viewport's and answering
the proposal is right. MetalUI's `List` is a scroller's **content** — one of
the four load-bearing requirements in its own type doc is "an enclosing
`ScrollView`", and the framework's scroller is `ScrollView`. A content node
that answered the viewport's proposal would report 400pt for a 14 000pt list,
and the offset clamp, the indicator thumb and `List`'s own windowing arithmetic
all read that extent. The greedy answer is not lost: it belongs to the kernel's
`scrollViewport`, which stage 3 lowered `ScrollView` onto and which already
answers its proposal on the scrolling axis (`CN-M`, `LR-BC`, probe SC1/SC2/SC4).
**So the K6 answer and the MetalUI answer are the same answer, assigned to the
two different nodes SwiftUI fuses into one.**

The width axis follows the same split for the concrete half and departs for the
nil half. A vertical `List` measured at a nil width happens in exactly one
composition — inside a horizontal `ScrollView`, which `visibleRange` already
refuses to window against and which CLAUDE.md documents — and K6's answer there
is 0, i.e. a blank list. The framework already has one silent blank-list mode
(divergence 14) and does not need a second, so the nil axis answers the content
as the legacy engine does. The cost is one subview measurement per realized row
**on the nil axis only**; the concrete path measures nothing.

**Pinned by** `aWindowedListAnswersItsFullContentHeightAndItsProposedWidth`
(the height half), `aWindowedListAtANilWidthAnswersItsWidestRow` (the nil-width
half, the one place this ruling departs from K6), and mutations **M2b** (the
height made greedy) and **M2c** (the nil width made 0) — M2c must redden 2.4
and *only* 2.4, which is what makes 2.4 rather than 2.1 the pin for the
departure.

**What it costs if wrong.** If the height answer is wrong the scrollbar, the
offset clamp and every windowing test are wrong together and loudly — this is
the most heavily pinned number in the stage. If the nil-width answer is wrong
the cost is confined to the horizontal-scroller composition, which no test and
no production caller builds; the failure mode is a blank list, identical to
what K6's answer would give, so the downside of being wrong here is exactly the
alternative.

**Amended, stage-4 critic round 1 (defect D10).** "The cost is one subview
measurement per realized row **on the nil axis only**; the concrete path
measures nothing" is wrong in both halves, and the **decision is unchanged** —
the answers this ruling picks are the answers, and only their price was
mis-stated. Corrected in `LR-CA` and spec §3.2.1: placement measures every
realized row on **both** paths, the nil path measures each row **twice** at two
different proposals (so the second lookup is a miss, not a hit), and on that
path **every logical row is realized**, because `visibleRange` declines to
window a non-`.vertical` context. The nil-width answer is therefore
`O(logicalCount)`, not `O(window)`. That is a real cost, it is not a regression
against the legacy engine (which lays out every row in the same composition),
and it is on no path production or the demo builds — but it is named rather than
hidden, measured by lane 2's test **2.4b** at two row counts, and its mitigation
is deferred in §9 because mitigating it would mean changing `visibleRange`,
which `LR-BT` pins shut.

---

## LR-BS — the arranging thing is a GROUP, and the spacer stops being an element

**The question.** Something must place the realized rows at `index × rowHeight`
under the proposal authority. Where does it live, given that **row identity
must not move**?

**The constraint, stated exactly.** `TombstoneTests.rowID` and
`FocusTests.rowID` hand-compute
`scrollerID → listID → child(of: listID, at: 0, name: datum.id) → child(at: 0, name: nil)`,
with a `$state0`/`$focus` slot below. `List.requestLayout` passes its **own**
`id` into the `Box` it builds, so the rows are direct named children of the
`List`'s id. An **element** introduced between the `List` and its rows adds an
id level and resets every row's `@State`, focus, `$anim` and accessibility node
once, and silently re-points both hand-computed chains. A **group** does not:
groups consume cursor indices and introduce no id level.

**The decision.** `ListRows<Row>: ElementGroup` replaces
`Pair(Box<EmptyGroup>, ArrayGroup<Box<Row>>)` as the outer `Box`'s content. It
registers each row `Box` under the `List`'s id as before, and then:

- under the **legacy** authority registers the leading spacer as a **bare
  node** (`pass.frame.requestNode(style: spacerStyle, children: [])`, the
  identical `Style`) and returns `[spacer] + rowNodes`, flat — byte-identical
  to what `Pair` returned;
- under the **proposal** authority consumes each row's `LoweredItem`, plans and
  registers the item wrappers with `planLegacyItems`/`registerLegacyItems`
  (`parent:` the `List`'s declared style, `parentKind: .flex(isRow: false)`,
  `parentSite: .list`), registers one `WindowedRowsLayout` over the wrapped
  nodes, records **that** node as the group's own `LoweredItem`, and returns
  `[windowedNode]`.

**Three things prototype P2 established, none of which was assumed** (record
§26 §2.4): a group may return one node that wraps its members, and the
enclosing `Box`'s `lowerLegacyNode` consumes its record exactly as it consumes
a child element's, with `reportUnconsumedLoweredItems` naming nothing; the rows
get their cross-axis stretch from the group's own `planLegacyItems` call, which
is also what keeps `LoweringSite.list` reachable after the site check goes; and
the two authorities' `StateTable` id sets are **equal**.

**The spacer's demotion is what buys that last one, and it is the stage's one
moving legacy number.** If the spacer stayed a `Box` element it would mint a
`$anim` entry on the legacy path and none on the proposal path, so every
`List` would have unequal `StateTable` id sets between the two authorities —
which stage 1's §5.1 item 4 forbids and which the differential harness reports.
Keeping a dead element on the proposal path purely to hold a number equal was
rejected as the shape the practices doc exists to keep out. So the spacer
becomes a node on both paths, and
`theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s cold-frame literal
goes from `2 * n + 6` to `2 * n + 5`, **re-measured rather than adjusted**, its
doc comment's enumeration of the six fixed entries losing the spacer's line,
and its three checkpoints (256 / 256 / 150 today) re-run.

**The row style is written once and kept identical on both paths.** The two
remaining CSS-defeating lines — `flexShrink: 0` against the freeze loop and
`minSize.height: 0` against the automatic minimum — have no counterpart in the
kernel, and `ScrollView`'s own lowering set the precedent of simply not
carrying such a line (`LR-BB`). They are nevertheless **kept** on both paths
rather than stripped on one, because `planLegacyItems` renders them inert
(`flexShrink: 0` becomes a `fixedSize` over a node whose frame already declares
`rowHeight`; a `minSize` of 0 folds into that declared size) and prototype P3
measured both sides identical with them present. One style that is inert on one
path beats two styles that can drift.

**What it costs if wrong.** If a group cannot in fact return a wrapping node in
some shape P2 did not reach, lane 2 fails loudly at
`reportUnconsumedLoweredItems` or at `SA-G`, and the fallback is `LR-BQ`'s.
If the spacer's demotion moves a pixel or a hitbox — it should not; an empty
`Decoration` emits nothing and an empty `Handlers` registers nothing — lane 1's
`aListsSceneAndHitboxesAreUnchangedByTheGroup` and the twelve `CN-R` images
catch it before lane 2 exists.

**Amended, stage-4 critic round 1 (defects D6, D7, D8).** Three corrections,
none of which changes the decision; all three are `LR-BZ`.

1. **The `flexShrink: 0` mechanism is mis-stated above.** "`flexShrink: 0`
   becomes a `fixedSize` over a node whose frame already declares `rowHeight`"
   is false for a `List` row: `plan.fixedSizeHorizontal` is assigned only under
   `d.flexShrink == 0 && mainAuto` (`LegacyLowering.swift:858-861`), and it is
   assigned `isRow`. A row in a column parent fails `mainAuto` (which is
   `d.size.height == .auto`, and a row declares `rowHeight`) and would be
   assigned `false` even if it did not. **`flexShrink: 0` lowers to nothing at
   all — no wrapper, no report.** The `minSize` half is right as written
   (`paddedAndSized`'s `folded(...)`, `LegacyLowering.swift:490-491`). The
   conclusion — one style, inert on the proposal path, rather than two that can
   drift — is **strengthened**, not weakened: the line is dropped on the floor
   rather than compensated for. Lane 2's mutation **M2g** is what keeps this
   honest, with its "reddens nothing" prediction written down first.
2. **The spacer's demotion moves divergence 18's crossing point, by one row.**
   `2n + 7` becomes `2n + 6` on `demoLikeRows`, and the reap gate is
   `storage.count > Self.sweepThreshold` with `sweepThreshold == 256`
   (`StateTable.swift:228`, `:543`), so crossing needs **257**: today at
   *n* = 125, after this ruling at *n* = **126**, since *n* = 125 then reads
   256 and does not cross. Spec §4.2(a) said the crossing does not move, and
   was wrong. CLAUDE.md's divergence-18 row and `List.swift`'s type doc
   (`:50-62`) both quote the old pair and are Docs-phase obligations; lane 1
   re-measures the formula **and** the crossing by rendering 125 and 126 rows.
3. **`List` needs two public wrappers, not one.** `List.prepaint` returns
   `Pair<…>.GroupPrepaint` (`List.swift:439-442`) and `paint` takes it `inout`
   (`:462-465`); with `ListRows` internal, that witness is an internal type in a
   public signature just as `Layout` is. `PrepaintState` gets the same
   `public struct` with internal storage, and `swift package clean` covers both.

---

## LR-BT — divergences 13 and 14 survive stage 4 unchanged, and 14's fix becomes mechanically available for the first time

**The question.** §4.1's brief says divergences 13 and 14 "must either stay
exactly as they are or be retired by a ruling that says so and re-point their
pins". Which?

**The decision: stay, unchanged, and be pinned on BOTH authorities.**

**Why nothing about them moves.** Both follow from one line:
`List.visibleRange(count:pass:)` reads `pass.scrollContext` during
`requestLayout`, a phase with no geometry. Divergence 13 is that the context's
`viewportExtent` is last frame's; divergence 14 is that its `offset` describes
the **scroller**, so a `List` that is not at its scroller's content origin
windows against rows that are not on screen and renders blank. Stage 3 measured
the published context identical under both authorities (record §25 §3.3), and
stage 4 changes not one line of `visibleRange`, of `ScrollContext`, or of its
publication: the window is the same range on both paths, and the windowed
layout receives it as `firstIndex` exactly as the spacer received it as a
height. `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` keeps
asserting the wrong answer on purpose, and **gains a proposal arm**, so the
wrong-on-purpose behaviour is pinned on the path production takes at stage 6b
rather than only on the one it is leaving.

**What did change, and it is a finding rather than a fix.** A `ProposalLayout`'s
`placeSubviews` receives **root-absolute `bounds`** (`SA-E`). For the first time
the windowed arrangement knows where the `List` actually sits inside its
scroller's content — one phase too late to choose the window, but early enough
to store for the next frame. So divergence 14 is now fixable by the same
one-frame-feedback shape `ScrollView` already uses for its viewport extent,
which is to say by trading divergence 14 for one more instance of divergence
13. Under the legacy engine that option did not exist at all: the CSS engine
hands an element no position in any phase, which is exactly what the divergence
14 entry and ruling `MP-L` say ("`requestLayout` has no position — that is the
phase's contract, not an oversight").

**Why stage 4 does not take it.** It retires a wrong-on-purpose pin, which
needs its own before/after measurement of the first-frame behaviour it trades
for (a list that windows against a stale own-offset on the frame after a resize
or a re-parent); it is a `List` feature rather than an engine replacement; and
it would land in the same stage as the layout it depends on, so a regression in
either would be indistinguishable. Deferred to **stage 6b**, where production
changes engines and the human-verification rows that read demo layout re-open.

**What it costs if wrong.** If divergence 14 is in fact *worse* under the
proposal authority than under the legacy one — a possibility no measurement
here rules out for shapes the prototypes did not build — the new proposal arm of
its pin is what says so, and it says so with the rows it actually built. If the
deferral is wrong, the cost is that stage 6b's human look sees a blank list in
a composition the demo does not build; the demo's list is its scroller's only
layout-contributing child, which is why the divergence has survived this long.

**Amended, stage-4 critic round 1 (defect D11): the "finding" above is ONE TERM
of a mechanism, and was written as a whole one.** The decision — stay unchanged,
pin on both authorities, defer to 6b — is untouched; the deferral's description
was overstated and is corrected here.

Root-absolute `bounds` in `placeSubviews` is real, and critic round 1 re-ran
`docs/probes/swiftui-layout-protocol-contract.swift` to confirm SwiftUI agrees
(arm **I2**, `I parent bounds (120.0, 70.0, 100.0, 100.0)`, byte-identical to
the recorded header). But divergence 14 needs the `List`'s offset **within the
scroller's content**, which is

```
absolute-List-y  −  absolute-scroller-content-y
```

and `ScrollContext` carries only `offset`, `viewportExtent` and `axis`
(`ScrollView.swift:82-100`). **The second term does not exist anywhere a `List`
can read it.** So "now fixable by the same one-frame-feedback shape `ScrollView`
already uses for its viewport extent" is wrong: that shape needs both terms, and
supplying the second means adding a field to a public type and publishing it
from the native viewport stage 3 built. Nothing in stage 4 measures or
prototypes that, and prototyping it was rejected rather than deferred by
oversight — it would mean designing a `ScrollContext` change inside the one
stage that has ruled itself out of touching `ScrollContext` at all.

Read the finding as: **one of the two terms became available for the first
time** — under the legacy engine neither did, since the CSS engine hands an
element no position in any phase (`MP-L`) — **and the other still has to be
published.** Stage 6b inherits a fix that is mechanically *possible*, not
mechanically *available*, and its first task there is the `ScrollContext`
change, not the feedback loop. The reasons stage 4 declines are unchanged, and
one is added: it is a two-part change whose first part is a public type's
storage, so a regression in either part would be indistinguishable from the
other.

---

## LR-BU — accessibility is untouched by construction, and what stage 4 must still prove

**The question.** `AB-L` and `AB-X` are named in §4.1's "what must not move".
What in stage 4 could reach them?

**The decision: nothing in the mechanism, and three things in the geometry, so
the records are pinned under both authorities rather than reasoned about.**

**Untouched by construction.** Every mechanism `AB-L`/`AB-X` names lives
outside `ListRows`: the `List`'s own `AXNode` (`role: .container` unless the
caller declared one, carrying `logicalCount = data.count`) is written onto
`built.handlers` in `requestLayout` and emitted by the outer `Box`'s
`registerAndScope`; each realized row's `handlers.axNode.logicalIndex` is
written onto the row `Box` in `requestLayout`, gated on `windowIsBounded &&
pass.collectsAccessibility`; `windowIsBounded` and `windowAwaitsViewport` are
computed from the same `pass.scrollContext` read; and `prepaint`'s
`requestAccessibilityRetry()` and `withAccessibilitySuppressed(except: id)` are
unchanged. `List.prepaint` and `List.paint` are not edited at all.

**What must be proved rather than assumed.** A published record carries its
**geometry**, and under the proposal authority a row's rect arrives through the
item-frame **alias** stage 2 introduced (`LoweringState.aliases`) rather than
from the row node directly. Prototype P2 measured the rects equal (rows 100×10
on both sides, windowed and unwindowed); that is the rect, not the record. So
lane 4 pins the **records**: `LayoutDifferential`'s `accessibilityEqual` — id,
declared node, text and geometry of every record, in order — in lane 2's test
2.1, and `AXNodeTests`' three `List` tests and `AccessibilityTreeTests`' two
run under both authorities, including
`aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount`, whose whole
subject is that `logicalCount` and the realized row count are different
numbers.

**Three mutations must redden it**, and each must redden it on **both**
authorities — four failures where two would mean an arm is vacuous: **M4b**
(`indexesRows` forced true regardless of `windowIsBounded`, which `AB-X` rule 1
forbids), **M4c** (`windowAwaitsViewport`'s `requestAccessibilityRetry()`
removed, `AB-X` rule 3), and **M4a** (`staleAfterGenerations` 2 → 3, which is
the retention pin rather than the accessibility one but shares the parameterised
harness).

**What it costs if wrong.** An accessibility regression here is invisible to
every rect test and to every pixel comparison, and reaches a user only through
VoiceOver, which nobody has run against this build (record §12's script is
still open). That asymmetry is the whole reason the records rather than the
rects are what lane 4 pins.

**Amended, stage-4 critic round 1 (defect D3): this ruling named the wrong
file, which would have made its own three-mutation rule unsatisfiable.** The
`AXTable`, its `rowCount`, its realized rows' `rowIndex`es, the unbounded-window
rule and the one-more-frame rule are pinned in
**`Tests/MetalUITests/AccessibilityDefaultsTests.swift`**, not in
`AccessibilityTreeTests`, which holds exactly two `List` usages (`:144`, `:734`)
— and `:144` sits inside `anInactiveWindowBuildsAndPublishesNothing`, which
asserts absence and can pin nothing about a table. Parameterising the file this
ruling named would have left **M4b** and **M4c** reddening legacy arms only,
i.e. two failures, which this ruling's own text says means an arm is vacuous.

The six tests lane 4 owes, by name:
`aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`
(`:461`, with `table.rowCount == 500` at `:475` and
`rows.map(\.rowIndex) == (38..<50)…` at `:480`),
`activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` (`:502`,
`AB-X` rules 1 and 3 at `:515-524`),
`scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` (`:570`),
`combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` (`:381`),
`aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` (`:740`) and
`aClientDoesNotChangeStateRetention` (`:662`). **M4b** must redden the second
and fifth of those on both authorities (at least four failures); **M4c** the
second's rule-3 half on both (at least two). Lane 4 **names every test each
mutation reddens**, not only the count.

One claim of this ruling was checked independently by the round and holds, now
by measurement rather than by reasoning: the spacer's demotion emits **no**
accessibility record either way, because `registerHandlers` appends only when
`hasSomethingToSay` (`Frame.swift:962-972`) and an empty-`Handlers` `Box` says
nothing.

---

## LR-BV — `LoweringSite.list` survives the site check's deletion

**The question.** `list.noLowering` disappears with the site check. Does the
`.list` case go with it?

**The decision: the case stays, and stays reachable.** Two entries can still be
raised at it: `flexGrow.weights`, which `planLegacyItems` raises once at its
`parentSite:` — the group passes `.list` — if two rows ever declared unequal
grow factors; and `<field>.unconsumed`, if a later stage put a field on the
windowed node's record and nothing consumed it. No row declares a grow factor
today (`rowStyle` sets none and `List` exposes no way to), so the first is the
same "kept so a later stage gets the right stage number rather than a fresh
`switch` arm nobody remembers to add" shape `component` has had since `LR-BO`.
`UnlowerableField.owningStage` keeps `case .list: return "4"`, with its comment
amended to say the site-level entry is gone.

Two pins change with it, and lane 2 owns both.
`aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` loses its
`List` arm — it asserts a process exit on `list.noLowering has no proposal
lowering`, which can no longer happen — and is renamed to name its surviving
arm, exactly as stage 3's lane 2 retired that test's `ScrollView` arm and left
the name naming what survives. `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s
`List` arm becomes either a `flexGrow.weights` arm (two rows with unequal
declared grow factors) or an **agreement** arm, and **lane 2 decides by
measurement, not by this ruling**: whether that shape can be spelled at all
from outside `List` is a question about the row closure's reach, and the lane
records which it found, as stage 3's lane 2 did for
`anItemFieldNoLoweredContainerConsumesIsReportedByName`.

**What it costs if wrong.** If `.list` is in fact unreachable after this stage,
the cost is a dead `switch` arm and a slightly dishonest §3.5 — recoverable by
a note. If the case had been *deleted* and a later stage needed it, the cost
would be a diagnostic reported at the wrong site with the wrong stage number,
which is the failure `LR-C` exists to prevent.

**Amended, stage-4 critic round 1 (defect D9): the question this ruling handed
to lane 2 "by measurement" is already answered by the source, and deferring it
was the mistake.** `planLegacyItems`' weights check filters
`$0.declared.flexGrow > 0` and fires only at **two or more distinct** factors
(`LegacyLowering.swift:810-823`). Every record the group hands it is a row
`Box` carrying `rowStyle`, built inside `List.requestLayout`
(`List.swift:360-363`), which sets no `flexGrow`; the caller's closure produces
the row's **content**, one level below the row `Box`, whose records are planned
at the row `Box`'s own site rather than at `.list`. So `flexGrow.weights` at
`.list` is **unreachable from outside `List`** — provably, and `.list` sits in
exactly `component`'s post-`LR-BO` position.

`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s `List` arm therefore
becomes an **absence** arm, in the shape the two `Component` arms already have,
and `try #require(arms.count == 10)` **stays at 10**. Lane 2 still runs it:
what the source proves is that the weights entry cannot be raised, not that the
arm reports nothing at all — test 2.7's first half (a plain `List`'s
`unlowerableFields.isEmpty`) is the measurement that says the absence is total,
and a non-empty report there is a finding. This ruling's remaining claim is
unchanged: the `.list` case stays, for `<field>.unconsumed` and for
`UnlowerableField.owningStage`'s trap message.

---

## LR-BW — `ListTests`' rows re-spell as LOWERED nodes, not as native probe leaves

**The question.** §4.1 row 4 says `ListTests`' "224 custom nodes and 3 leaves
re-spelled as native probe leaves". Stage 3's lane 3 re-spelled its nine custom
nodes as `ProbeLeaf` (`LayoutDifferential.swift`), which registers
`pass.frame.requestNativeLeaf` directly under the proposal authority. Does that
transfer?

**The decision: no — `ListTests`' `Row` re-spells through the LOWERING, not
through a bare native leaf,** and §4.1's wording is followed in intent rather
than literally.

**The measurement that settles it.** `ProbeLeaf`'s proposal branch registers a
native node directly, so it records **no `LoweredItem`**, so `planLegacyItems`
has nothing to plan and the leaf is never stretched — `LR-T`'s "a proposal
element inside a lowered container is defined, not silent", seen from the
inside. Prototype arms **P1a2** and **P1a4** measured it: a `ProbeLeaf(7×3)`
inside a 10pt row reads 7×10 under the legacy authority (stretched to the row)
and 7×3 under the proposal one; a `ProbeLeaf(7×60)` inside a 28pt row reads
7×28 and 7×60. `ListTests` reads a row's own **height** in two tests —
`aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` asserts exactly 28 for
a 60pt content — so `ProbeLeaf` would turn a real assertion into a false
failure and hide whatever the lowering actually does.

**The spelling that works**, measured as prototype **P3**: `Row.requestLayout`
branches on `pass.lowersToProposal` and calls
`pass.lowerLegacyNode(Style(), declared: Style(), children: [], site: .customElement)`
— and, for the `contentHeight` arms, `pass.lowerLegacyLeaf(…) { pass.frame.requestNativeLeaf { … } }`
— where it called `pass.requestNode`/`pass.requestLeaf`. Inside
`Box(width 100, column) { List(3 rows, 28) { … } }` with P1b applied: **0
unlowerable and 0 disagreeing in both arms**, the tall arm included, the row
box reading 100×28 and the row's own node 0×28 on both sides.

**Mutation M3b** is what keeps this ruling honest: the re-spelled `Row`'s
proposal branch reduced to a bare `requestNativeLeaf` must redden
`aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` under `.proposal`. If it
does not, the tall arm is not seeing its subject and the lane says so.

**A second reason, weaker but real.** `site: .customElement` is what stage 6a
will deprecate and move; a test fixture already spelled through
`lowerLegacyNode` is a fixture stage 6a does not have to re-reach.

**What it costs if wrong.** If some `ListTests` shape needs a genuinely
un-lowered native leaf — a row whose content must NOT be stretched — that arm
uses `ProbeLeaf` and says why in its own doc comment. The failure mode of
getting this backwards is the expensive one: a test that passes under both
authorities while measuring two different things, which is practices shape 15
(require the arms to disagree before believing they agree).

**Amended, stage-4 critic round 1 (defect D2): the re-spelling rule reaches
three MORE fixtures than `ListTests`' `Row`, and each is a process abort until
it does.** `TombstoneTests.ExcursionRow` (`:93-101`),
`MeasurePerformanceTests.StatefulListRow` (`:533-541`) and `FocusTests`' row
fixture all call `pass.requestNode(style:children:)` directly, which under the
proposal authority hits the `Frame.requestNode` backstop that
`aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` pins as an **exit test** —
so in a production frame the first `.proposal` build of any of them ends the
whole run with no summary line. This ruling's spelling
(`lowerLegacyNode` / `lowerLegacyLeaf`) is what each of them takes, and
`LR-BX` is the rule that it lands **in the same commit as the `.proposal`
arm**, never after it. Nothing about the choice between the lowered spelling
and `ProbeLeaf` changes.

---

## LR-BX — no lane takes a red-before by aborting the process, and three row fixtures re-spell before they can have a proposal arm

**The question.** Stage 4's design prescribed, in three separate lanes, a
red-before consisting of "run these tests under `.proposal` and record what
fails". Critic round 1 (defects **D1**, **D2**, **D12**) showed that in each
case the run does not fail — it **aborts**.

**The mechanism, already written down and already ignored once.**
`Frame.noteUnlowerable` traps unless the frame sets `reportsUnlowerableFields`
(`Frame.swift:1535-1538`), and a `Frame` built for production does not.
`LayoutAuthorityTests.swift:180-199` records stage 3 discovering exactly this,
in the sentence that says lane 3 could not take its red-before that way: the
process ends with **no summary line and no list of what failed**. A red-before
whose output is a truncated run is not a red-before; it cannot be read, it
cannot be compared against the green-after, and a mutation cannot be aimed at
it.

**The decision — two legal shapes, and no third.** A lane that needs a red
under `.proposal` from something that would trap takes it either:

- **(a)** by re-spelling the fixture through `lowerLegacyNode` /
  `lowerLegacyLeaf` (`LR-BW`'s rule) **in the same commit** that adds the
  `.proposal` arm, so the red is an assertion failure; or
- **(b)** in a **child process**, with `#expect(processExitsWith:)`, recording
  the trap message from the child's captured output — the shape
  `LayoutAuthorityTests` already uses for its own two arms.

**The three fixtures this reaches**, each of which registers through
`pass.requestNode` directly: `TombstoneTests.ExcursionRow` (`:93-101`),
`MeasurePerformanceTests.StatefulListRow` (`:533-541`), and `FocusTests`' row
fixture. `ListTests`' `Row` was already named by `LR-BW`; these three were not,
and spec §5's "Tests touched" listed them as edits rather than as re-spellings.

**A fourth site, which no re-spelling fixes** (defect D1).
`MeasurePerformanceTests.render` (`:19-27`) builds a production `Frame`, and
`demoLikeRows` declares `.minHeight(Pixels(0))` on its root `Box` (`:505-519`)
— a `Self`-returning modifier (`Box.swift:905`), so it lands on the root's own
`Style`. `reportUnconsumedLoweredItems` skips only `flexGrow`, `flexShrink`,
`flexBasis` and `alignSelf` for the root and **still reports a non-`.auto`
`minSize`** (`LoweringState.swift:109-133`), which traps. The fix is a
`reportsUnlowerableFields:` parameter on `render`, defaulting `false`, set
`true` for the `.proposal` arms.

**Why not simply drop `.minHeight(0)` from `demoLikeRows`.** That fixture's own
header says removing a pin from it "would silently inflate every later
before/after ratio measured against this harness", and every committed literal
in the file is measured against it. Changing the fixture so that one new arm can
run would move numbers this stage exists to hold still — the opposite trade from
the one being made.

**What the diagnostics frame costs, stated before the lane starts.** Under
`reportsUnlowerableFields`, a site with no lowering gets a 0×0 native leaf in
place of its node (`Frame.unlowerable`), so a non-empty report means the work
counts were taken over a partly degenerate tree. Lane 5 therefore asserts the
report **exactly**: the only entry permitted is the root's own
`minSize.unconsumed`, an artifact of the root being unconsumed and nothing to do
with `List`. Any other entry is a finding, and work numbers taken alongside one
are not recorded as this stage's.

**And the corollary for lane 2** (defect D12). Four of that lane's eight
"red-befores" — 2.2, 2.3, 2.4 and 2.6 — read `WindowedRowsLayout`'s own answer,
a type the lane introduces, so at lane 1's HEAD they do not **compile**. A test
that does not compile is not a red-before either. They are re-classified as
"arrives with its subject", their evidence is their mutations, and the lane's
commit message says which four so that the absence of a red is not read as an
oversight. **Splitting lane 2 in two was considered and rejected**: the layout
and the site-check deletion cannot be green independently, since until the check
goes nothing in `List` reaches the layout.

**What it costs if wrong.** If a lane takes shape (b) where (a) would have done,
the cost is a child process and a slower test. If a lane ignores this ruling,
the cost is the one stage 3 already paid and wrote down: a run with no summary
line, indistinguishable from a build failure, and a lane that believes it has
measured a red it never saw.

---

## LR-BY — two test harnesses cannot observe what stage 4 asks them to, and both are fixed in lane 1 or lane 3 rather than worked around

**The question.** Stage 4's design assigned its central agreement test to
`LayoutDifferential.compare` and its `ListTests` fix to `elementBounds`. Critic
round 1 (defects **D4**, **D5**) showed neither observable exists on the path
the design names.

**Harness one: `LayoutDifferential` never windows a `List`.**
`LayoutDifferential.render` (`Tests/MetalUITests/LayoutDifferential.swift:171-184`)
constructs its own `stateTable: StateTable()` and renders **one** frame.
`ScrollContext.viewportExtent` is one frame stale by construction, written only
by `ScrollChrome.resolvedOffset`'s `PrepaintPass` overload
(`ScrollView.swift:79-84`), so on frame 1 it is 0. `List.visibleRange` then
takes its `context.viewportExtent > 0` guard (`List.swift:323-327`) and returns
`0..<count`, and `windowIsBounded` is false (`:370`), which sends
`List.prepaint` down the `withAccessibilitySuppressed(except: id)` branch
publishing **the table and no rows**. Prototype **P1a3** shows the first half
directly: ten rows at y = 60…312, all ten, no window.

So today, through this harness: the "windowed at `firstIndex 3`" arm the design
specifies is **unreachable**, and `accessibilityEqual` over a `List` compares
one record with one record and passes **vacuously** — the "a harness that
compares nothing agrees" shape record §26 §2.4 warns about in its own note, hit
by the design that wrote the note.

**And the literals the design offered for that arm are not the real thing
either.** Prototypes **P2** and **P2b** got `firstIndex: 3` by handing it to a
scratch group, not by windowing a real `List`, so the design's own oracle never
exercised the path its central test claims.

**The decision.** `render` gains `stateTable:` and `frames:` (default 1) in
**lane 1**, threading one `StateTable` through the frames of one side and
returning the last; `compare` grows the same two. Every `List` arm that uses it
**must `try #require` a bounded window and a non-empty row-record set on both
sides before asserting anything** — the anti-vacuity check is part of the arm,
not a review note — and lane 1 re-takes the windowed legacy-side literals
through the real `List`, which is what makes lane 2's test 2.1 a red-first
oracle rather than a transcription. Lane 1's **M1f** (`frames:` forced back to
1) must redden the new
`aListInTheDifferentialHarnessReachesABoundedWindow`; if it does not, the
anti-vacuity check is itself vacuous.

**Harness two: `ListTests`' helpers produce no element bounds at all.** The
design said both helpers "read the `List`'s bounds from `elementBounds`".
`Frame.elementBounds` is written only when `recordsElementBounds` is set
(`Frame.swift:1524-1527`), which defaults to `false` (`:1463`), and it is
written by `Element.prepaintGroup` (`ElementGroup.swift:158`) and by
`Frame.render` for the root — both **prepaint-time**. `laidOut`
(`ListTests.swift:68-78`) runs `requestLayout` + `computeRootLayout` and never
prepaints; `renderWindowed` (`:204-224`) prepaints but builds
`Frame(contentSize:scaleFactor:)`. Neither records anything.

**The decision.** Both helpers pass `recordsElementBounds: true`, and `laidOut`
gains a prepaint pass, in **lane 3**. Both are `private` to `ListTests.swift`,
so this is a local copy rather than an edit to the `ScrollViewTests` /
`TextMeasureTests` idiom they were modelled on, and neither of those files
changes. **Adding a prepaint pass to `laidOut` is a behaviour change for every
test that uses it** — hitboxes, scroll regions, focus entries and accessibility
records all register in prepaint — so lane 3 runs the full unfiltered suite
afterwards and names anything that moves, and the three tests' literals are
**re-measured by running them**, not predicted. Mutation **M3c**
(`recordsElementBounds` dropped back to its default) must redden those three.

**What it costs if wrong.** If the harness change is wrong the whole of lane 2
is measuring nothing, which is the failure this ruling exists to prevent and
which the `try #require` makes loud rather than silent. If the `laidOut` prepaint
pass disturbs a test this ruling did not anticipate, the full-suite run names it
in lane 3 rather than at the merge — which is the cheaper place to find it, and
the reason the run is required rather than suggested.

---

## LR-BZ — four mechanism and arithmetic claims the design asserted without reading the code that implements them

**The question.** Critic round 1 (defects **D6**, **D7**, **D8**, **D9**) found
four statements in the stage-4 design that are wrong about MetalUI's own source.
None of them changes a decision. They are gathered here because they share a
cause worth naming, and because three of them would have survived into the
implementation as things a later reader believed.

**The cause.** Each was derived from what the surrounding prose says the code
does rather than from the code — `List.swift`'s type doc for the `flexShrink`
mechanism, divergence 18's entry for the crossing point, `LR-BV`'s own framing
for the reachability question. The practices document's rule is "walk every
measurement back to the mutated line in the same pass"; the same rule applies to
a mechanism claim, and these four did not.

**(1) `flexShrink: 0` on a `List` row lowers to NOTHING** (spec §3.1, `LR-BS`
amended). Not to a `fixedSize`. `plan.fixedSizeHorizontal` is assigned only
under `d.flexShrink == 0 && mainAuto` (`LegacyLowering.swift:858-861`), and it
is assigned `isRow`; a row in a column parent fails `mainAuto` (which is
`d.size.height == .auto`, and a row declares `rowHeight`) and would be assigned
`false` even if it did not. The `minSize` half of the claim is right
(`paddedAndSized`'s `folded(...)`, `:490-491`). **The conclusion strengthens**:
the line is dropped on the floor, not compensated for by a wrapper. Lane 2's
mutation **M2g** (`rowStyle.flexShrink` dropped from the record handed to
`planLegacyItems`, proposal path only) is predicted to **redden nothing**, said
in advance in the shape `LR-BQ` reason 4 uses, and the lane shows the two
`LegacyItemPlan`s differing — or not — before banking the prediction.

**(2) Divergence 18's crossing point moves from 125 rows to 126** (spec
§4.2(a), `LR-BS` amended). The reap gate is
`storage.count > Self.sweepThreshold` with `sweepThreshold == 256`
(`StateTable.swift:228`, `:543`), so crossing needs **257**. `2n + 7 ≥ 257`
first holds at *n* = 125; `2n + 6 ≥ 257` first holds at *n* = **126**, and
*n* = 125 reads 256, which does not cross. Spec §4.2(a) said the crossing does
not move. Lane 1 re-measures the formula **and** the crossing by rendering 125
and 126 rows; CLAUDE.md's divergence-18 row and `List.swift`'s type doc
(`:50-62`) both quote the old pair and are **Docs-phase obligations**.

**(3) `List` needs two public wrappers, not one** (spec §5, `LR-BS` amended).
`List.prepaint` returns `Pair<…>.GroupPrepaint` (`List.swift:439-442`) and
`paint` takes it `inout` (`:462-465`), so with `ListRows` internal that witness
is an internal type in a public signature exactly as `Layout` is.
`PrepaintState` gets the same `public struct` with internal storage, and
`swift package clean` covers both.

**(4) `LoweringSite.list`'s weights entry is provably unreachable** (spec
§4.2(d), `LR-BV` amended), so the choice `LR-BV` deferred to lane 2 "by
measurement" is settled by reading `LegacyLowering.swift:810-823` and
`List.swift:360-363`. The arm becomes an **absence** arm and
`try #require(arms.count == 10)` stays at 10.

**What it costs if wrong.** Individually: (1) a reader who believes a wrapper
protects `List` that is never registered, and looks for it at stage 9; (2) two
documents quoting a crossing point off by one row, in the entry whose whole
subject is where the crossing is; (3) a compile error at lane 1, which is the
cheap failure; (4) a lane spending a measurement on a question already answered.
Collectively the cost is the expensive one — a design whose prose is checkable
and was not checked, which is the failure mode this project's record files exist
to make visible.

---

## LR-CA — the windowed layout's measurement cost, corrected: one lookup per realized row on the concrete path, two per LOGICAL row on the nil-width one

**The question.** Spec §3.2 priced the windowed layout at "zero measure calls
on the common path" and "one subview measurement per realized row … only on the
axis that is nil". Critic round 1 (defect **D10**) showed both halves understate,
and the second badly.

**The corrected arithmetic**, read off `LayoutTree.placeCustom`
(`Sources/MetalUILayout/LayoutTree.swift:1040-1070`) and `List.visibleRange`
(`Sources/MetalUI/List.swift:323-339`):

- **`placeCustom` measures every child again after `placeSubviews` returns**, at
  the recorded proposal, to turn each record into a rect. So placement alone
  costs **one `measureNative` lookup per realized row on both paths**. "Zero
  measure calls on the common path" was true of `sizeThatFits` and false of the
  layout.
- **Concrete-width path**: that is the whole cost — 1 lookup per realized row,
  `O(window)`, independent of `logicalCount`, which is the exit test's claim and
  is unaffected.
- **Nil-width path**: 2 lookups per row at two different proposals —
  `sizeThatFits` at `(nil, rowHeight)`, the placement record at
  `(bounds.width, rowHeight)` — so the second is a cache **miss**, not a hit.
- **And on that path every row is realized.** The only composition reaching a
  nil width is a vertical `List` inside a horizontal `ScrollView`, and
  `visibleRange` declines to window a non-`.vertical` context, returning
  `0..<count`. So the nil-width answer is **2 lookups per LOGICAL row** —
  `O(logicalCount)`, unbounded, at any row count.

**The decision: name it, measure it, and do not mitigate it here.** `LR-BR`'s
answers do not change — the nil-axis answer is still the content rather than
K6's 0, for the reason `LR-BR` gives, and a blank list is still worse than a
measured one. What changes is that the price is stated honestly and pinned:
**lane 2's test 2.4b** takes `lastNativeLayoutWork` on the nil-width path at
**two row counts** and records the slope, with the predicted 2-per-logical-row
written down before the run; a different slope is a finding, not a number to
write down.

**Why not mitigate.** Every mitigation — windowing a nil-width `List` against
something other than a scroll context, caching a widest row across frames,
answering from a stored measurement — changes `visibleRange` or the run-scoped
cache, and `LR-BT` pins `visibleRange` shut for this whole stage while `SA-H`
pins the cache's lifetime. §9 carries it to stage 6b alongside divergences 13
and 14, which is where `visibleRange` re-opens.

**Context that keeps this in proportion.** It is not a regression: the legacy
engine lays out every row in the same composition, for the same reason. It is on
no path production or the demo builds — no test and no caller puts a vertical
`List` inside a horizontal `ScrollView` — and `CLAUDE.md` already documents the
composition as one the framework declines to window.

**What it costs if wrong.** If the slope is not 2 per logical row, the lane has
found a cache behaviour neither this ruling nor `SA-H` predicts, and that is
worth more than the cost estimate it came from. If the cost had stayed
unmeasured, a later stage would have inherited an `O(logicalCount)` path
believed to be `O(window)` — which is precisely the claim the stage's exit test
exists to make, so it would have been inherited with a green test over it.

---

## LR-CB — the pixel harness is committed here, and the authority roll call is renamed in the change that makes its name wrong

**The question.** Two pieces of stage-4 scaffolding are inherited rather than
owned, and critic round 1 (defects **D13**, **D14**) showed both are about to
become false.

**The `CN-R` harness: committed in lane 1, retiring `LR-BJ`'s carry.** Spec §8
makes "0 differing pixels in all twelve `CN-R` images" the acceptance criterion
of **every** lane, while §9 deferred "committing the `CN-R` harness" to stage
6b. Five lanes' acceptance criterion was therefore not reproducible from
anything in the repository. The harness has now been lost and rebuilt **three
times in stage 3 alone** (record §25 §7.6, §8.8, §9.8), at about an hour each,
certified only against a handful of control numbers.

The decision is the stronger of the two the finding offered: **lane 1 rebuilds
it from record §25 §7.6's recipe, re-takes the control figures by running them
rather than quoting them, and commits it** under `docs/probes/demo-pixels/`
with the recipe in its own header. Lanes 2–5 run the committed script. A
rebuild that disagrees with a quoted control is a finding, and the quoted number
is what gets corrected. This is within stage 4's reach — it is a shell script
and three Swift scripts under `docs/probes/`, which is this stage's own file
scope — and it pays for itself inside the stage.

**The roll call: renamed in the same change that extends it.**
`ScrollAuthorityCoverage` / `everyScrollScenarioRanUnderBothLayoutAuthorities`
(`ScrollViewTests.swift:251-282`, `ScrollAuthorityCoverage.swift`) verify a
**scroll** set. Lane 3 adds `ListTests`' scenarios to it, at which point the
name says "scroll" over a set that is not one. They become **`AuthorityCoverage`**
/ **`everyParameterisedScenarioRanUnderBothLayoutAuthorities`**, in the same
commit, with the 34 literal bumped — not in a later tidy-up, because a registry
whose name lies is one a later stage adds a second registry beside.

**And its order argument is extended and re-measured, not inherited.** The
registry's second half depends on Swift Testing running files in path order, and
the header argues today that `ScrollIndicatorTests` → `ScrollRoutingTests` →
`ScrollViewTests` with the roll call declared at the END of the last of the three
(`ScrollAuthorityCoverage.swift:31-38`). Adding `ListTests.swift` and
`ListLoweringTests.swift` is safe **only because both sort before `Scroll*`** —
an accident the header does not state and which the next file added may not
share. Lane 3 names the new files in the argument and **re-measures the ordering
twice at its own HEAD**, as the header's own claim was measured twice.

**What it costs if wrong.** If the rebuilt harness is subtly different from
stage 3's, the re-taken controls are what say so, and they are re-taken rather
than quoted for exactly that reason; the failure mode of *not* committing it is
the one already observed three times, which is an hour and a set of numbers
nobody can reproduce. If the ordering claim is wrong, the roll call fails
**naming the scenarios it had not yet seen**, which is the behaviour its own
header describes and the reason the completeness check does not live in the test.

---

## LR-CC — stage 4 lane 1's corrections: a mutation that found two blind pins, a harness parameter that cannot exist, and the numbers that moved

Lane 1 built `ListRows`, demoted the spacer, extended `LayoutDifferential` and
committed the `CN-R` harness. Four things the design did not have right, each
measured rather than argued.

**1. `compare` cannot grow `stateTable:`, and `LR-BY` says it does.** `LR-BY`'s
decision reads "`render` gains `stateTable:` and `frames:` … `compare` grows the
same two." `render` does. `compare` cannot: `Report.stateSlotsEqual` is
`legacy.stateTable.ids == lowered.stateTable.ids`, so a single table handed to
both sides would make that field compare a set with itself and read `true` for
every tree — the exact vacuity the `frames:` parameter exists to remove, arriving
through the parameter added to remove it. `compare` therefore grows **`frames:`
only**, and each side keeps its own fresh `StateTable`, threaded through its own
`frames` frames. Said in `LayoutDifferential.compare`'s own doc comment, so the
next reader who checks it against `LR-BY` finds the answer beside the code.

**2. Mutation M1b reddens nothing, and it is a broken instrument rather than the
finding — but the instrument was already broken at `f2e981f`.** The design
predicted M1b (`spacerStyle.flexShrink = 0` deleted) would redden
`aScrolledListsSpacerDoesNotShrinkUnderPadding`. It reddens nothing on the whole
unfiltered suite. Measured on an **unmodified `f2e981f` tree**, before this lane
changed anything: deleting the spacer's `flexShrink` leaves that test green, and
deleting `rowStyle.flexShrink = 0` leaves the **whole 1580-test suite** green.

The cause is `f1944f8`, the commit that made `.padding(_:)` a wrapper. The
padding lands on an outer `ModifiedElement` layer, so the `List`'s own content
box keeps its full `count × rowHeight` and there is no negative free space left
for a spacer or a row to absorb. Both tests' doc comments describe a mechanism
their fixtures stopped reaching, in a file the modifier-composition track never
opened — the same shape as `List.swift`'s own `minSize.height` paragraph, which
records exactly this kind of decay two milestones earlier.

`Style.padding` written directly still shrinks the `List`'s own content box
(CLAUDE.md's declared-but-inert table draws that distinction), so each test gains
a second arm that writes it. Both new arms were then verified red under the
mutation they exist for: `aScrolledListsSpacerDoesNotShrinkUnderPadding` on the
spacer's line, `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` on the row's
(four issues). Each test's first arm is kept — it still pins the wrapper
spelling's answer, which is the one a caller writes.

**This sharpens `LR-BS`'s "the row style is kept identical on both paths".** That
ruling's reason was that `planLegacyItems` renders both lines inert on the
proposal path. It is now measured that on the **legacy** path they are unpinned
too, for a different reason. They are still kept — `LR-BS`'s "one style that is
inert on one path beats two that can drift" stands, and the two new arms mean a
future change to either line is no longer silent.

**3. Mutation M1c reddens nothing, and that is a proof rather than a gap.**
Advancing the group's cursor past the spacer, as `Pair` did, changes no test. The
practice's rule is to show the mutant behaves differently before banking that,
and here the stronger statement is available by reading: the cursor's only
consumer is each row's `GlobalElementID.enteringGroupMember`, every row supplies
a `name` (`.id(String(describing: datum.id))`), and `child(of:at:name:)` never
consults `at:` once a `name:` is supplied — and the enclosing `Box` discards the
cursor afterwards. So the mutation changes a value nothing can observe. That is
the measured reason row identity survives the spacer leaving cursor 0, which is
what `LR-BS` claimed and critic round 1 checked by reading.

**4. Two numbers moved exactly as `LR-BZ` predicted, and both were re-measured by
running rather than by arithmetic.** Divergence 18's formula on `demoLikeRows(_:)`
goes `2n + 7` → `2n + 6` and its crossing point 125 → **126**. Measured by
rendering *n* rows, then three frames of an empty list — past
`staleAfterGenerations` — and reading whether the rows were actually reaped:

| *n* | before, `table.count` | reaped? | after, `table.count` | reaped? |
|---|---|---|---|---|
| 40 | 87 | no | 86 | no |
| 124 | 255 | no | 254 | no |
| 125 | 257 | **yes** | 256 | **no** |
| 126 | 259 | yes | 258 | **yes** |
| 500 | 1007 | yes | 1006 | yes |

`theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s three checkpoints move
256 / 256 / 150 → **255 / 255 / 149**. `List.swift`'s and `ElementGroup.swift`'s
doc comments take the new numbers in the same commit; CLAUDE.md's divergence-18
row stays a Docs-phase obligation.

**And one the design assigned to lane 5 that lane 1 has to pay.** The demo census
`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` loses the spacer's
`Frame.elementBounds` row the moment the spacer stops being an element: 2036 →
**2035** ids and 30 → **29** disagreements, 2042 → **2041** and 36 → **35** with
the modal on, with `agreeing` 6 and `legacyOnly` 2000 unmoved. Lane 1 makes that
single-row edit and says so in the test's own doc comment; lane 5 still owns the
census's real re-derivation, which is what happens when the site check goes.

**What it costs if wrong.** Item 1 is the expensive one: a `compare(stateTable:)`
would have made `stateSlotsEqual` — one of the six fields every lane of every
stage reads — trivially true, in the same change that advertised the harness as
fixed. Item 2 costs a reader who believes two `List` lines are pinned; it is
recorded rather than only fixed because the decay mechanism (`.padding` became a
wrapper) will have hit other fixtures nobody has re-checked.

---

## LR-CD — stage 4 lane 2's corrections: the elision that must not fire, a masked height answer, and a record nothing can observe

Lane 2 built `WindowedRowsLayout`, gave `ListRows` its proposal branch and
deleted `List`'s site check. Four things the design (`LR-BQ`, `LR-BR`, `LR-CA`,
spec §3.1, §3.2 and §6 lane 2) got wrong, each found by running rather than by
reading, each corrected here. Measurements are record §26 §7.

### 1. `planLegacyItems`' single-child stretch elision must NOT fire under this layout

**The question.** The group plans its rows with
`planLegacyItems(received, parent: <the List's declared style>, parentKind:
.flex(isRow: false), parentSite: .list)`, which is what prototype P2 measured and
what spec §3.1 prescribes. `planLegacyItems` elides a child's stretch when the
parent has **exactly one** child and no declared size on that axis (`LR-AC`,
stage 1's `LR-E` principle 3), because a fit-content parent stretching its only
child is the identity.

**What is wrong with it here.** `WindowedRowsLayout` is **not** fit-content on
the cross axis: `sizeThatFits` answers `proposal.width` whenever one is offered.
So the elision's premise fails, and a `List` with exactly **one** row and no
declared width of its own leaves that row unstretched — 0 wide, against the
legacy engine's stretch to the list's width. Six rows hide it completely, which
is why none of the five arms spec §6 lane 2 prescribed for test 2.1 could see
it, and why the prototypes did not either (P1a6 and P2 both used three or more
rows).

**The ruling.** `ListRows.loweredNode` gives the planning parent a declared
cross size when the `List` has none. Nothing else in `planLegacyItems` reads
`parent.size.width` for a column parent — it is the elision's only consumer
there — so the correction is exactly as narrow as the defect. Test 2.1 gains a
**sixth** arm, **B6**, one row under a `List` declaring no width; mutation
**M2h** (the correction removed) reddens B6 **and nothing else**, measured.

**What it costs if wrong.** A one-row `List` is not an edge case in an app — it
is every list whose filter matched once — and the failure is a row that renders
at zero width with no diagnostic. The correction's own risk is the opposite: if
a later stage makes the windowed layout hug its content on the cross axis, the
forced cross size becomes a lie and the row is stretched where it should not be.
B6 is the arm that would then read the legacy answer and disagree.

### 2. The layout's height answer is masked in every composed tree

`LR-BR` makes `sizeThatFits` answer `rowHeight × logicalCount` on the stacking
axis at every proposal, against SwiftUI's greedy `List` (probe K6). Spec §6 lane
2 predicted that **M2b** — the height answer made greedy, i.e. K6's — would
redden test 2.1 as well as 2.2.

**It does not redden 2.1 at all.** `List.init` declares
`style.size.height = rowHeight × data.count` on the `List`'s own `Box`, and
`paddedAndSized` turns that into a fixed native frame **around** the
arrangement, so the arrangement's own height answer never reaches a rect. The
layout's height is observable only through the kernel — tests 2.2, 2.3 and 2.4b,
which register the layout with no `List` and no `Box` above it.

**Recorded rather than silently fixed** because it is the reason 2.2 is not
redundant with 2.1, and because it says where the invariant actually lives
today: in two places that must agree, `List.init`'s declared height and
`WindowedRowsLayout.sizeThatFits`, with no test that they do. (They cannot
disagree while both read `rowHeight × data.count`; a stage that makes either
conditional owes that test.)

### 3. The windowed node's `LoweredItem` record is unobservable, and is kept anyway

Spec §6 lane 2's **M2e** — the windowed node's `recordLoweredItem` dropped —
"must redden 2.7 with an `…unconsumed` entry". **M2e reddens nothing**, and both
halves of the prediction are wrong for reasons provable by reading, in the shape
lane 1's M1c took:

- a **dropped** record never joins `LoweringState.order`, which
  `reportUnconsumedLoweredItems` iterates, so it cannot produce an
  `…unconsumed` entry at all. An **unconsumed** record can, which is mutation
  M2f, and M2f does redden 2.7 (three `box.flexShrink.unconsumed` and three
  `box.minSize.unconsumed`);
- the record's only other effect is the stretch item frame the enclosing `Box`
  would wrap the arrangement in. That frame is greedy on the width axis — and
  `WindowedRowsLayout` already answers `proposal.width`, so the wrapper changes
  no number. Its minimum is 0 and its maximum ∞ (the arrangement's `declared` is
  a bare `Style()`), and the alias it installs points at a node no element owns,
  so nothing reads it either.

**The record stays.** `LR-AB` item 1 is a uniform convention — every lowered
site records a `LoweredItem` for the node it returns — and
`UnlowerableField.owningStage`'s `.list` comment claims `<field>.unconsumed`
reachability that only a record can provide. Deleting it would make `List`'s
arrangement the one lowered node that does not record, and a later stage that
gives the arrangement a non-default declared style, or a container that is not
proposal-greedy above it, would lose the wiring silently. It is documented as
inert-today in `loweredNode`'s own comment and in test 2.7's.

**What it costs if wrong.** Keeping it costs three lines and a reader who
believes more is pinned than is. Deleting it costs a silent gap the next stage
would have to rediscover.

### 4. M2g changed no program; M2g′ is what measures the same claim

Spec §3.1 predicted that **M2g** — `rowStyle.flexShrink` dropped from the record
the group hands `planLegacyItems`, proposal path only — reddens nothing, and
required the lane to "show the mutant's `LegacyItemPlan` differing from the
original's before banking the prediction — or, if the plans are byte-identical,
say that the 'mutation' changed no program and find another."

**The plans are byte-identical**, printed for all six rows of a plain list:
`fixedSizeH=nil W=(min: 0.0, max: inf) H=nil align=topLeading alignFrame=nil
margin=nil fields=[]`, with and without. `plan.fixedSizeHorizontal` is assigned
only under `d.flexShrink == 0 && mainAuto`, and a `List` row declares
`size.height = rowHeight` in a column parent, so `mainAuto` is false. So M2g is
not a mutation at all at that boundary.

**The replacement, M2g′**, deletes `rowStyle.flexShrink = 0` from
`List.requestLayout` outright. It reddens
`paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` and
`aScrolledListsSpacerDoesNotShrinkUnderPadding` — lane 1's two new
`Style.padding` arms — and **nothing on the proposal path**. That pair of facts
is the measurement `LR-BS`'s "inert rather than removed" needed: the line is
load-bearing under the legacy engine and reaches nothing under the kernel, so
keeping one row style rather than two costs nothing.

### 5. M2c is broader than predicted, which is not a defect

Spec §6 lane 2 said M2c (the width answer made 0 on a nil axis, K6's) "reddens
2.4 only — which is what makes 2.4 the pin for the half of `LR-BR` that
diverges". Measured, it reddens **2.4, 2.2's two nil-width arms and 2.4b**.
Three pins for the diverging half rather than one; 2.4 is the one that names it.
Recorded because the spec's sentence would otherwise read as a claim about
coverage that the suite contradicts.

---

## LR-CE — stage 4 lane 3's corrections: a host that needs a height, a pin that could not see its subject, and two rows the design put in the wrong lane

Lane 3 re-spelled `ListTests`' `Row` through the legacy lowering, parameterised
its scenarios over both authorities, and renamed the roll call. Four things the
design (`LR-BW`, `LR-BY`, `LR-CB`, spec §6 lane 3 and §6 lane 4) got wrong or
left unstated, each found by running rather than by reading. Measurements are
record §26 §8.

### 1. The host box needs a declared HEIGHT, not only a width

**The design says** both helpers gain "a fixed-size `Box` wrapper (P1a6's shape,
a declared width and a column direction)". P1a6 declared a width and left the
height `auto`, which is correct for P1a6's three-row list and wrong for this
file.

**Why.** A root with an `auto` main axis takes the definite space offered
(divergence 4, `CS-I`), so an auto-height host in a 600pt frame is 600pt. Six of
this file's fixtures are 40-row or 100-row lists — 1120pt and 2800pt — which as
flex items of that host have hundreds of points of negative free space. The
legacy engine shrinks the `List`'s own box; the kernel does not, because
`paddedAndSized` turns the `List`'s declared height into a fixed native frame
and a native stack shrinks nothing. That is a disagreement between the two
authorities that the **harness** would have introduced, in the one file whose
whole point this lane is to read both authorities against each other.

**The ruling.** `hostStyle(width:height:)` declares both axes, at the frame's
own size. Where a subject is taller than the frame and its own height is the
assertion — `aWindowedListStillReportsItsFullContentHeight`, 40 × 28 = 1120 —
the test raises the frame instead (`frameHeight: 1200`), which is one literal,
named at its call site with the arithmetic. Every other literal in the file is
unchanged on both authorities, measured.

**Amended, verification round (2026-09-23).** *The ruling stands and the code is
right; the mechanism above was an inference presented as a measurement, and the
lane never ran the mutation that would have checked it.* The verifier did, and
the reading is record §26 §8.4.2: dropping the declared height back to `.auto`
— P1a6's shape exactly — reddens **eleven** scenarios, not six, **`.proposal`
arms only**, 14 issues, every `.legacy` arm green. **Four of the eleven are
three-row, 84pt fixtures with no negative free space at all**; for those the
mechanism is **centring** — with an `auto` main axis the kernel centres the
host's content, so `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` reads
ys `[258, 286, 314]`, i.e. `(600 − 84)/2`, instead of `[0, 28, 56]`. And the
sentence "the host is exactly the window and the subject is never squeezed" was
**false for the very fixtures this item names**: a 1120pt list is still a flex
item inside the 600pt declared-height host, and a 2800pt one inside the 2000pt
host — which is why `aWindowedListStillReportsItsFullContentHeight` needs
`frameHeight: 1200` at all. That sentence is deleted above. **The criterion a
later reader should apply is not "is there negative free space?" but "does the
host's main axis resolve to something other than the frame — by squeezing **or**
by centring?"** Spec §6 lane 3 and record §26 §8.3 carry the correction; two doc
comments in `ListTests.swift` still repeat the old reason and are named as an
obligation in record §26 §11.3.

**What it costs if wrong.** Nothing production-visible: this is a test harness.
The cost of *not* doing it is worse than a wrong number — it is a file of
two-authority comparisons whose disagreements are its own.

### 2. `M3c` reddened two of three, and the third could not see its subject

Spec §6 lane 3 requires **M3c** (`recordsElementBounds` dropped back to its
default in `laidOut`) to "redden the three tests that read the `List`'s bounds;
if it reddens nothing, they are not reading what the lane thinks they read". It
reddened **two**: `aListSizesItselfToCountTimesRowHeight` and
`aWidthModifierOnAListReachesItsLayoutNode`, one issue per arm.

**`anEmptyListHasZeroHeightAndTrapsNothing` stayed green**, and the reason is
the helper, not the test: it returned `frame.elementBounds[subject] ?? <0×0>`,
so an unrecorded bounds and a zero one were the same value — and that test
asserts a height of **0**, which is the mutation's own answer. Practices shape
14's "a test that cannot fail", arrived at through a convenience.

**The ruling.** Both helpers return `Bounds<Pixels>?` and every reader
`try #require`s it. M3c re-run against the corrected commit reddens **all
three**, six issues. The `??` spelling is not to be reintroduced: any fixture
whose expected answer is zero on some axis is blind behind it, and this file has
one such fixture today and will gain more.

### 3. Divergence 14's pin is parameterised in lane 3, not lane 4

Spec §6 lane 4's table lists `ListTests`'
`aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` among the
suites lane 4 parameterises. Lane 3 parameterises **every** scenario in
`ListTests` in one commit — it has to, because the re-spelling and the
`.proposal` arms must land together (`LR-BX`) and a half-parameterised file
would leave the roll call's literal wrong between the two lanes.

So that row is delivered here. Lane 4 owns the rest of its table; for this one
it need only confirm the test still asserts the **wrong** answer on purpose and
now says so on both paths. The divergence is `visibleRange`'s, which is
authority-blind, and the second arm's content is exactly that claim: the
lowering neither fixes it nor makes it worse.

### 4. `ListLoweringTests.swift` is not in the roll call's order argument, and the argument now says why

`LR-CB` has the lane extend the header's path-order argument "to the new files",
naming `ListTests.swift` and `ListLoweringTests.swift`. Only the first belongs
there. `ListLoweringTests`' nine tests each run **both** authorities inside one
body, through `LayoutDifferential.compare`; none is a `@Test(arguments:)` case
and none calls `AuthorityCoverage.record`, so the file contributes no name and
the roll call cannot be affected by where it sorts.

The argument's real content — which the stage-3 version left unstated, and which
`LR-CB` was right that a reader needs — is the **sort**:
`Tests/MetalUITests/ListTests.swift` sorts before every
`Tests/MetalUITests/Scroll*.swift`, so the roll call, declared at the end of
`ScrollViewTests.swift`, still runs last. That is now written down, together
with the case it warns about: a file added later whose path sorts *after*
`ScrollViewTests.swift` breaks the second half of the check — which is precisely
why `ZZDemoPixels.swift` carries a `ZZ…` prefix. Re-measured twice at this HEAD,
identical both times: `ListTests` → `ScrollIndicatorTests` → `ScrollRoutingTests`
→ `ScrollViewTests`, roll call last.

---

## LR-CF — stage 4 lane 4's corrections: one fixture that does not abort, one modifier that does, a test that cannot cross, a roll call that had to move, and a mutation that is not one

Five corrections, each found by running the lane rather than by reading its
brief. The first four are the design's; the fifth is the source's.

### 1. `FocusTests`' row does not abort under `.proposal`, and only `TombstoneTests`' does

Spec §6 lane 4 says the lane's red-befores are "child-process probes plus
same-commit re-spellings of `ExcursionRow` and `FocusTests`' row, **both of
which abort under `.proposal` today**". Measured in a child process before
either was touched: only `ExcursionRow` does.
`aFocusedListRowSurvivesABoundedExcursionButNotALongerOne` builds its rows as
`Box().focusable()` — a `Box`, which stage 1 lowered, and `focusable()` is a
`Self`-returning modifier that writes `handlers` rather than registering
anything — so the identical tree under the proposal authority runs to
completion and exits 0.

**The ruling.** That fixture is **not** re-spelled: a `lowersToProposal` branch
over a `Box` would be a branch with nothing on either side of it. The
measurement is kept as a committed positive control,
`TombstoneTests.aBoxSpelledListRowDoesNotAbortAProductionProposalFrame`, beside
the abort it controls for — without it the abort probe would pass just as well
if the `List`, the `ScrollView` or `@State` were what aborted.

**What it costs if wrong.** Nothing: the arm runs, and it runs on the same tree
production would build. What the correction buys is that a later reader does
not add a branch to a fixture that never needed one.

### 2. `scrolledList`'s `.minHeight(px(0))` is what kept four accessibility tests off the proposal authority — and it goes

The design's lane-4 table names the two row spellings and nothing else. It
missed the fixture: `AccessibilityDefaultsTests.scrolledList` returned
`Box { ScrollView { list } }.width(200).height(h).minHeight(px(0))`, and four of
the six `List` tests make that value the **root** of their frame or of their
window. A root's `LoweredItem` is unconsumed by definition, and
`reportUnconsumedLoweredItems` reports a root's non-`.auto` `minSize`
(`LoweringState.swift:120-127`), which in a production frame is
`preconditionFailure`. So those four aborted before their first assertion, at
`box.minSize.unconsumed`, with nothing to do with the `List`.

Three shapes were available: wrap the fixture in a host `Box` (`LR-BY`'s answer
for `ListTests`), give the four tests a reporting frame, or drop the modifier.

**The ruling.** Drop the modifier, because it was measured **inert** first. The
box declares `height`, so no automatic minimum is in play where it is a root,
and in the one place it is a flex item (`aClientDoesNotChangeStateRetention`'s
`Row`) the axis it names is the cross one. The measurement is a mutation in
reverse: with it dropped and nothing else changed, the whole suite unfiltered
read 1593 tests / 3 issues — the three lane 2 left red for lane 5 — so no test
in the repository can see it. Wrapping would have changed the tree every one of
the file's forty-odd assertions is written against, to fix four; a reporting
frame would have measured a partly degenerate tree (`Frame.unlowerable`
substitutes a 0×0 leaf), which is exactly what lane 5's brief refuses.

**This is not `demoLikeRows`.** Spec §6 lane 5 forbids removing the same
spelling from that fixture, and the reason is stated there: every committed
performance literal is measured against it. `AccessibilityDefaultsTests` holds
no such literal — its numbers are row counts and emission counts, which the
modifier does not touch, as the 1593/3 run shows.

**What it costs if wrong.** A fixture that no longer exercises a root's
unconsumed `minSize`. Nothing is lost:
`anItemFieldNoLoweredContainerConsumesIsReportedByName`'s root arms are that
test, and the abort itself is now pinned here too, by
`aRootMinHeightOnTheScrollerFixtureAbortsAProductionProposalFrame` and its
control.

### 3. `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` cannot be a both-authorities arm

Spec §6 lane 4 lists it in the table and makes it half of mutation M4b's
required failure count. It can be neither. Its subject **is** `hidden()`, and
`display: none` has no proposal lowering at all: `LegacyLowering.swift:161`
returns `display.none` before any other field is read, and the parent design's
§4.1 assigns `hidden()` to a stage that has not run. A `.proposal` frame over
that fixture aborts at `box.display.none`, measured in a child process
(`aHiddenListAbortsAProductionProposalFrame`, with the shown tree as its
control).

**The ruling.** It stays legacy-only, its declaration says why, and it is **not**
in `AuthorityCoverage.expected` — the same shape lane 3 gave
`aListInsideADeferredIgnoresTheEscapedScrollersOffset`. When a later stage
lowers `display`, it gains its arm and the registry gains its name. M4b's
required count is restated in item 5.

**What it costs if wrong.** `AB-X` rule 1 under the proposal authority would be
unpinned. It is not: the same rule is pinned on both paths by
`activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` and by
`combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`'
zero-`rowHeight` arm, and M4b′ reddens both on both.

### 4. The roll call moves to `ZZAuthorityRollCall.swift`

`everyParameterisedScenarioRanUnderBothLayoutAuthorities` reads what
`AuthorityCoverage` has recorded by the time it runs, so it must run last, and
it ran last because `Tests/MetalUITests/ScrollViewTests.swift` happened to sort
after every other contributing file (`LR-BI`, `LR-CB`). Lane 4's subjects
include `Tests/MetalUITests/TombstoneTests.swift`, which sorts **after** it —
precisely the case `AuthorityCoverage`'s own doc warned a later file would hit.

**The ruling.** The test moves into a file of its own whose name is chosen for
the purpose, `ZZAuthorityRollCall.swift`, the `ZZ…` prefix being
`ZZDemoPixels.swift`'s. Nothing else moves: the registry stays in
`AuthorityCoverage.swift` and the literals stay hand-derived in the test. The
alternative — leaving `TombstoneTests`' scenario out of `expected` — would have
bought the arrangement's convenience at the price of the stage's exit criterion
over the one suite that holds `TB-AH`.

Re-measured twice at this lane's HEAD, identical both times, off the unfiltered
run's own `started` lines: `AXNodeTests` → `AccessibilityDefaultsTests` →
`AccessibilityTreeTests` → `FocusTests` → `ListTests` → `ScrollIndicatorTests` →
`ScrollRoutingTests` → `ScrollViewTests` → `TombstoneTests` →
`ZZAuthorityRollCall`. Mutation **M4d** (the `arguments:` list reduced to
`[.legacy]`) reddens the roll call *and* 64 issues raised by `record`'s
order-independent half inside `TombstoneTests`' arm, so the move is measured by
a mutation as well as by a healthy run.

**What it costs if wrong.** If Swift Testing ever stops running files in path
order the check fails **naming the scenarios it had not yet seen**, which is the
same failure mode it has always had — not a silent pass.

### 5. M4b is not a mutation; M4b′ is, and the finding is a redundancy nothing can pin

Spec §6 lane 4's **M4b** is "`indexesRows` forced true regardless of
`windowIsBounded`", required to redden at least four arms. Run on the full
unfiltered suite it reddens **nothing** — the same shape `LR-CD` item 4 found
for M2g.

The mechanism, read off the source after the run: `indexesRows` sets
`rowBox.handlers.axNode.logicalIndex` and nothing else, and on an unbounded
window both things a hint could reach are already shut. `List.prepaint` wraps
the rows in `withAccessibilitySuppressed(except: id)`, which is the exact
condition `Frame.registerHandlers`' record branch tests
(`isAccessibilitySuppressed(for:)`); and that method assigns
`declaration.logicalIndex = nil` **before** its `declaration.isEmpty` test, so a
row carrying only a hint emits no `AXNode` and writes no `$ax` slot either
(`AB-L`, `AB-U`). The `windowIsBounded &&` conjunct is therefore belt-and-braces
with a guard one method away.

**The ruling.** The conjunct stays — it states what the value means, and
removing it would make the line depend on a distant invariant to be correct —
but the measurement is written into the source beside it, so a later reader does
not take it for a tested guard. The claim the design wanted M4b to defend is
`AB-X` rule 1, and it is pinned through the suppression: **M4b′**,
`windowIsBounded` forced true, reddens six arms and twenty-two issues across
`activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`,
`combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` and
`scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, symmetrically on
both authorities.

**What it costs if wrong.** Nothing behavioural: two gates where one would do,
on a path that is already correct. What it would have cost to leave unrecorded
is a reader believing a mutation round had exercised that conjunct.

---

## LR-CG — stage 4 lane 5's corrections: a diagnostics parameter rather than a fixture edit, work literals derived from the cold sweep, a vacuous half named, a gated scenario kept out of the roll call, and the census's 2 000 rows attributed by formula

Five decisions the lane had to take, three of them because running it answered a
question the brief had left open.

### 1. The `.proposal` arms run on a diagnostics frame, and `demoLikeRows` is not touched

Spec §6 lane 5 already ruled this (`LR-BX`, critic finding D1): `render` gains
`reportsUnlowerableFields:`, the fixture keeps `.minHeight(Pixels(0))`. The lane
adds the two measurements the ruling was written without.

**What the diagnostics frame actually reports**, read off the run and now
asserted exactly at all four `.proposal` call sites:
`[box.minSize.unconsumed]` — one entry, the root's own, at 40, 160, 500 and
100 000 rows alike. Nothing else. So the tree the work counters were taken over
is **not** partly degenerate: `Frame.unlowerable` substitutes a 0×0 native leaf
only for a *site* with no lowering, and there is none here.

**And the abort it replaces is real**: a production `.proposal` frame over
`demoLikeRows(40)` dies at
`box.minSize.unconsumed has no proposal lowering (plan task 7, stage 2)`, with
the identical tree under `reportsUnlowerableFields: true` exiting 0 beside it as
the control (`aProductionFrameOverDemoLikeRowsAbortsUnderTheProposalAuthority`,
`aDiagnosticsFrameOverDemoLikeRowsRunsUnderTheProposalAuthority`).

**Contrast `LR-CF` item 2**, which dropped the same modifier from
`AccessibilityDefaultsTests.scrolledList`. The two fixtures differ in exactly the
way that ruling says: that one holds no literal measured against the modifier,
this one holds every performance literal in the repository.

**What it costs if wrong.** A performance harness whose frame is one flag away
from production's. The flag changes nothing but the trap-versus-record branch,
and the report being empty of everything but the root's own entry is the
measurement that says so.

### 2. The work literals are derived from the cold sweep and the window, not read off the warm run

Spec §7 asks for `measureCalls`, `cacheHits` and `cacheMisses` "each equal to a
literal hand-derived before the run … on a branching count, not by reading them
off the first run" (`SA-M`). The shape §2.6's prototype P1d offered — a bare
kernel stack of rows — is not the shape the exit test measures, which is a whole
`demoLikeRows` frame with the row `Box`es, the `.padding`-free row wrapper, the
`Text` leaves and the scroll viewport around them.

**What was done instead, and it is a prediction rather than a fit.** A cold
frame realizes every row (`MP-I`), so the cold column is the same function of
the realized row count `r` sampled at r = 40, 160, 500 and 2000. It is exactly
linear — `r + 1`, `6r + 7`, `7r + 8`, reproducing all twelve measured numbers
with no residue. The *warm* window is derived independently, from
`visibleRange`'s own arithmetic: at `offset == 0` over a 370pt viewport of 28pt
rows, `first = max(0, 0 − 2) = 0` and `last = ceil(370/28) + 2 = 16`, so
**r = 16**. The model evaluated there predicts **17 / 103 / 120**, and the warm
frames read exactly that at all four row counts. The prediction was made on the
cold column and confirmed on the warm one, two orders of magnitude from where
the coefficients were taken.

**Stated plainly, because the practices doc asks for it**: the coefficients 6 and
7 were obtained by measuring, not by counting nodes in `LegacyLowering.swift`.
What makes them more than a transcription is that they predict a point the fit
never saw, and that **M5a** moves the literals exactly as `r + 1 / 6r + 7 /
7r + 8` says it must at r = 17 (18 / 109 / 127).

**What it costs if wrong.** The three literals would be a per-frame constant
somebody had written down rather than a function of the window. M5a is the
measurement that refutes that reading: it moves them and leaves the 500-vs-100k
equality alone.

### 3. The tokenizer half of the exit test is vacuous under `.proposal`, and the test says so

`aListsWorkIsTheSameFor100kRowsAsFor500` and its ungated twin have counted
`Shaper.runCallCounter` since the measure-performance milestone. Under the
proposal authority that counter reads **0** at every row count: a lowered `Text`
measures through `proposalTextMeasurement`, which hugs its widest line at the
proposed width and never takes a min-content probe, so `Shaper.unbreakableRuns`
is never reached. `#expect(calls100k == calls500)` is `0 == 0` on that arm —
precisely the failure CLAUDE.md warns about for this instrument.

**The ruling.** Do not delete the half and do not paper over it. The `.legacy`
arm gains `try #require(calls500 > 0)` as a reachability control, the
`.proposal` arm asserts the zero **by name**, with the mechanism, and the native
work counters are what carry the proposal arm. `ShapingCache.storageCount` is
not vacuous on either arm (72 legacy, 32 proposal, equal across row counts).

**What it costs if wrong.** Nothing measured moves; what changes is that a
reader of a green proposal arm no longer believes the tokenizer count is
watching anything there.

### 4. The gated 100 000-row scenario is parameterised but is NOT in `AuthorityCoverage.expected`

`everyParameterisedScenarioRanUnderBothLayoutAuthorities` requires every name in
`expected` to have been `record`ed by the time it runs. A scenario gated on
`METALUI_RUN_100K_LIST_TEST` never records on an ordinary run, so listing it
would redden the roll call on every healthy suite, and `record`ing without
listing it reddens in its own arm. Either way the roll call would stop meaning
what it says.

**The ruling.** `aListsWorkIsTheSameFor100kRowsAsFor500` takes both authorities
and calls nothing; its ungated twin `aListsWorkIsTheSameFor160RowsAsFor40`
carries the name and runs the identical instrument at 40 against 160, and
`theResidentEntrySetStaysBoundedWhileScrolling10kRows` carries the second.
`expected` goes 65 → **67**, and a tenth file joins the path-order list.

**What it costs if wrong.** A lane could reduce the gated test to `[.legacy]`
and no roll call would say so. The exit test is run by hand, once, and its
result is recorded (record §26 §10.4); the two ungated twins are what a later
regression would trip over.

**Amended, verification round (2026-09-23).** *Only one of the two twins can
trip over anything.* `aListsWorkIsTheSameFor160RowsAsFor40` is discriminating —
its `.proposal` arm expects `NativeLayoutWork(17, 103, 120)` where `.legacy`
expects `NativeLayoutWork()`. `theResidentEntrySetStaysBoundedWhileScrolling10kRows`
is **not**: hard-coding its `renderFrame` to `layoutAuthority: .legacy` leaves
the whole 1602-test suite green (mutation MV5e, record §26 §10.6). The mutant is
**not equivalent** — it deletes a production `.proposal` frame over a 10 000-row
`List`, which is what says the re-spelled `StatefulListRow` does not abort at
scale and that reaping is unchanged — so this is a banked gap, not an
equivalence. The roll call cannot close it: `AuthorityCoverage.record` sees the
argument, not the frame. The fix is one authority-discriminating read per arm
(`frame.tree.lastNativeLayoutWork != NativeLayoutWork()` under `.proposal`,
`==` under `.legacy`), the same control the work test already uses; owner in
record §26 §11.3. Four prose and message literals in `AuthorityCoverage.swift`
and `ZZAuthorityRollCall.swift` also still say `65` and "nine files" after this
item moved `expected` to 67 and added a tenth.

### 5. The census's 2 000 row ids are attributed by formula under three existing causes, and the sub-pixel tail is one of them

Spec §4.2(c) requires every disagreement to be attributable to a named cause (R,
55, X9, 3) and calls anything else a finding. The 2 000 ids that moved from
*legacy-only* to *disagreeing* are the demo `List`'s 500 rows, four apiece, and
they attribute as follows, with no new cause:

- **55** twice — x + 108 (the served 196 sidebar against the shrunk 88) and
  y + 16 (the narrower main column wraps the paragraph one line taller);
- **X9** — the inner `Box` 28 → 16 tall, a stretched single-child container not
  stretching its child (`LR-AC`), which also moves the `Text` from the row's
  vertical centre to its top;
- **55's sub-pixel tail** — 42 of the 500 texts are one point narrower on the
  legacy side.

**That last one was nearly written down as an anomaly, and it is not.** The
lowered sidebar is served its declared 196 exactly, so every lowered row text
starts at the integer x = 252 and cumulative-edge rounding gives
`round(natural)`. The legacy sidebar is flex-shrunk (`SZ-L`) to a width a hair
under 88, so the legacy text starts at `144 − d` and the same rounding gives
`floor(natural)` for exactly the rows whose natural width has a fraction in
`[0.5, 0.5 + d)`. **210 of the 500 have a fraction at or above 0.5 and only 42
floor**, so "the legacy engine floors" is the wrong reading and was the first
one tried.

**The ruling.** `d` is not available to the test — no rect records an unrounded
origin, and `LayoutTree.measuredWidth` records a width and not an x — so the
test **solves for it from the 500 rows** and asserts the bracket
`d ∈ (0.0615234375, 0.076171875]`, measured, together with the fact that the
bracket is non-empty. A single fractional origin explaining all 500 is the
falsifiable claim; a row wrong for any other reason empties the bracket, and a
change to the sidebar's shrunk width moves its endpoints and names itself.

**What it costs if wrong.** Two committed literals that describe the legacy
sidebar's sub-point rather than deriving it. Deriving it would mean either a
§9.7 shrink computation in a test or a new harness field recording unrounded
origins; both were judged out of a lane whose subject is `List`.

**And the census cannot see the windowing.** Measured by **M5d** (placement at
the realized index rather than the logical one): 57 issues across nine tests,
and `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` is not one of
them. `LayoutDifferential.render` builds one frame, so the demo's `List` is
always cold, always `firstIndex == 0`, and the census pins the placement formula
only at its origin. The windowing itself is pinned by `ListLoweringTests` and
`ListTests` (`LR-BY`, `LR-BW`), which is where it belongs; recorded so a later
reader does not treat the census's 2 000 rows as a windowing test.
