# Engine replacement decisions (plan task 7)

Rulings for `docs/superpowers/specs/2026-09-17-engine-replacement-design.md`, on
`feat/engine-replacement` from `c2290fc`. Ids are **lettered**, `LR-A`…; next
unused is **`LR-Q`**. A bare `LR-3` is a typo, not a citation.

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
exit 0; run twice, byte-identical, 61 lines, recorded in its header. Arms cited
as T0–T9, B0–B3, H0–H2, S0–S3, G0–G2. Earlier probes cited by their own arm
names: `swiftui-frame-semantics.swift` (D, C), `swiftui-stack-algorithms.swift`
(A5, G1, K6), `swiftui-overlay-presentation.swift` (P4, P5).

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

**Reasoning.** It is the only shape in which each later stage is a local change
to one registration site behind a measurable parity check, and in which the
subsystems that broke in `4aaca40` are untouched code rather than re-implemented
code.

**What it costs if wrong.** Two registration branches live in five files until
stage 8 deletes the legacy one; a fix to one branch does not reach the other
(practices: "a copy of a pinned implementation is unpinned"), which is why every
lowered site gets a differential test of its own.

---

## LR-B — the authority belongs to the frame, is set by the window, defaults to legacy, and stays internal until stage 6

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
Stage 6 makes `.proposal` the default and decides whether any public spelling
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
fields, plus four whole-frame equalities: scene rects and glyphs (bytes),
hitboxes (id, bounds, layer, opacity), accessibility emissions **including
`geometry`**, and `StateTable` ids. Every harness test requires an arm that
disagrees (spec 1.8, 1.9).

**What it costs if wrong.** A tree whose disagreement only shows at the window
root (fill versus centre) passes the harness; that is stage 6's ruling and its
own test.

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

---

## LR-F — a lowered `Text` hugs its widest line, answers the proposal below a word, and keeps its legacy glyph origin

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
  word, so its images are expected unchanged.
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

---

## LR-G — a lowered `Stack` offers its proposal (closing divergence 53 under the proposal authority)

**Evidence.** Stack-algorithms probe A5 (a greedy child in a `ZStack` fills
100×80) and `CN-P` item 2. For fixed-size children the two agree: prototype T3,
6 of 6 rects.

**The ruling.** `display: .stack` lowers to a native overlay with the `Stack`'s
nine-point alignment. Children are proposed the stack's proposal; the legacy
fit-content offer is not reproduced. Spec 4.2 pins the disagreement on a
wrapping `Text`; the legacy pin
`aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` stays until stage 8.

**What it costs if wrong.** A lowered `Stack` over wrapping text lays out
narrower than its legacy twin — visible only under the proposal authority,
which no production root takes before stage 6.

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

---

## LR-I — overflow compression is reported by the harness, not diagnosed at registration

**The question.** CSS shrinks fixed-size children that overflow their container
(`flexShrink` defaults to 1; divergence 55); SwiftUI's stack does not compress a
fixed child. Whether a row overflows is known only after measurement.

**The ruling.** No registration diagnostic. Spec 3.6 pins the disagreement on
`Row { 80; 80 }.width(100)` (legacy 50/50, lowered 80/80 from x 0), with the
stack-algorithms probe's compression arms (G1) as the SwiftUI evidence. Stage 2
decides whether a legacy spelling lowers to priorities or is re-spelled.

**What it costs if wrong.** A tree that agrees in the harness at one size can
disagree at a smaller window; stage 6's root switch re-takes the demo at 560².

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

## LR-L — the whole task is nine stages, and stage 1 is the lowering foundation

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

---

## LR-N — deferrals

Spec §8's table, each with its stage. None of them is needed for stage 1's
exit test; every one of them is either a field stage 1 reports by name (so it
cannot be silently lowered) or a site stage 1 never enters (`ScrollView`,
`List`, `Component` distribution, `Deferred`'s layout, custom elements).

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

---

## LR-P — the mechanical check that closes the task

**The question.** "No production layout request may pass through the legacy
engine" must be checkable, not asserted.

**The ruling** (stage 8's, designed now so stages 1–7 do not paint it into a
corner):

1. plain-import typecheck guards (`typecheckFile`, `SA-P`) that each of these does
   **not** compile: `MetalUILayout.computeLayout(…)`,
   `pass.requestNode(style: Style(), children: [])`,
   `pass.requestLeaf(style: Style()) { _, _ in … }`, `Style().flexGrow = 1`;
   each guard mutated red once by restoring its symbol;
2. stage 6's `noProductionFrameReachesTheLegacyEngine`, which drives the demo's
   content and a `List` through a `Window` and requires the legacy branch of
   `computeRootLayout` never ran, is deleted in stage 8 together with the branch
   — the guards in 1 replace it;
3. the closeout record lists `grep -rn "FlexEngine\|computeLayout(\|requestNode(style" Sources`
   with empty output and `find Tests -name "*.json" | wc -l` reading 0.

**Why guards and not a runtime counter alone.** A counter proves the paths it
drove; a symbol that does not exist proves every path.
