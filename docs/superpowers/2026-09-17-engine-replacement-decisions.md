# Engine replacement decisions (plan task 7)

Rulings for `docs/superpowers/specs/2026-09-17-engine-replacement-design.md`, on
`feat/engine-replacement` from `c2290fc`. Ids are **lettered**, `LR-A`…; next
unused is **`LR-AP`** (stage 2's design took `LR-AB`…`LR-AO`, appended at the end). A bare `LR-3` is a typo, not a citation.

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
`docs/record/19-engine-replacement-stage-2.md`.

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
`Frame.bounds(of:)` and `LayoutPass.measuredWidth(of:)` resolve the alias.

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
  deliberate change from the legacy inert answer, pinned by 3.2.
- A declared size below the padding (+ border) sum keeps the fixed frame (P1),
  a deliberate change from `BM-4`, pinned by 3.3.
- `margin` px/rem, either sign → native padding outermost around the child, not
  aliased (P3, P4); agreeing with CSS until SwiftUI's clamp (3.5 pins the
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

---

## LR-AI — percentages keep reporting, owned by stage 8's recipe

**Evidence.** Stage-2 probe C1: `containerRelativeFrame(.horizontal) { $0 * 0.5 }`
inside a 200-wide `VStack` is 500 wide — half the 1000-wide host — against control
C0's 100. SwiftUI's relative sizing is relative to the nearest *container*
(window, scroll view), not the parent; `GeometryReader` is a view with its own
sizing. `FR-H`/`FR-T` recorded the legacy fractions resolving against the
containing block.

**The ruling.** `size.percent`, `padding.percent`, `border.percent`,
`margin.percent`, `gap.percent`, `minSize.percent`, `maxSize.percent` and a
fractional `flexBasis` stay unlowerable by name. Each call site needs a respelling
decision (a fixed length, a greedy frame, a `ProposalLayout`), which is stage 8's
recipe; stage 10 deletes the fields.

**What it costs if wrong.** Nothing silent: a tree with a percentage traps under
the proposal authority until stage 8. `width(fraction:)` has test callers that
stage 6a's flipped-default census classifies.

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

The J9 overflow is a new divergence, pinned by 4.3.

**What it costs if wrong.** Spacer nodes are native children with no element, so
the harness sees only the children's rects; a spacer mis-marked by `markSpacers`
would answer the cross proposal (`CN-C`), which 4.1's column arms see.

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

---

## LR-AL — `Row`/`Column` default spacing (divergence 52) is a spelling default, not a lowering

**Evidence.** Stack-algorithms S: `HStack`/`VStack` default to per-pair spacing
(8 between two leaves); `HStack(spacing: 0)` is 0. `Style.gap` defaults to
`.pixels(0)` and cannot say "unset", so a lowered `Row { a; b }` cannot tell a
caller's `gap: 0` from the initializer's default.

**The ruling.** A lowered stack's spacing is the declared main-axis gap, always
explicit (stage 1's behaviour, now characterized by 4.8). Closing divergence 52
means changing `Row`/`Column`'s public default — a vocabulary change with every
legacy caller's pixels behind it — so it is stage 8's, with the sizing recipe.

**What it costs if wrong.** Nothing moves; the divergence stays pinned by
`aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`.

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
