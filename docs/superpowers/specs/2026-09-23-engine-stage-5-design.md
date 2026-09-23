# Engine replacement, stage 5 — `Deferred`'s absolute content as a presentation root (plan task 7)

**Status, 2026-09-23 (PDT): DESIGN.** No file under `Sources/` or `Tests/`
changed in a commit. Every measurement below was taken on
`feat/engine-stage-5` at `e5caefb` in
`/Users/maxburger/Developer/worktrees/MetalUI/stage-5`, from a scratch test file
(`ZZScratchStage5.swift`) and one temporary edit to `ListTests.swift`, both
restored before commit with `git status --short` showing only this design's
docs and probe; the measurements are in `docs/record/28-engine-replacement-stage-5.md`
§2. Rulings `LR-CH`…`LR-CO`, and critic round 1's `LR-CP`, in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md).
Probe: `docs/probes/swiftui-overlay-presentation.swift`, **revision 2** (group Q
added; P and H unchanged and re-run).

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row 5 and §8's stage-5 row. Stage 1 is record §18, stage 2 §21, stage 3
§25, stage 4 §27.

**What §4.1 row 5 asks for.** *"`Deferred` as a presentation root laid out
against the window (overlay-presentation P4/P5), `.position(.absolute)`/`.inset`
(census: 1 each in `AbsoluteOverlayTests`, 2 each in the demo) lowered onto it
or removed; divergences 9–11. Exit test: `DeferredTests` and
`AbsoluteOverlayTests` under the proposal authority."*

**The sentence this design turns on.** Under the legacy authority `Deferred`
has **no layout meaning at all** — its content is an ordinary member of its
parent's flow, and only paint and prepaint change (layer 1, whole-surface clip,
zero translation). What takes a box out of flow and places it "against the
window" is `.position(.absolute)` with no positioned ancestor. So this stage
makes **the pair** — a `Deferred` whose one content node is `.position(.absolute)`
— the presentation root, and leaves an in-flow `Deferred` exactly as it lowers
today (it already agrees with the legacy engine, measured, §2.2). An absolute
box **outside** a `Deferred` is removed from the proposal authority: it keeps
reporting by name, now with owner stage 10. Every other case reports by name
(`deferred.containingBlock`, `deferred.nested`, `deferred.root`,
`deferred.amended`, `minSize.absolute`, `maxSize.absolute`) rather than lower
to a different answer.

## Contents

1. [Baseline](#1-baseline)
2. [Evidence gathered for this design](#2-evidence-gathered-for-this-design)
3. [Decisions, concept by concept](#3-decisions-concept-by-concept)
4. [The mechanism](#4-the-mechanism)
5. [What must not move, and what does](#5-what-must-not-move-and-what-does)
6. [API and files](#6-api-and-files)
7. [Lanes](#7-lanes)
8. [The exit test](#8-the-exit-test)
9. [Demo, pixels and captures](#9-demo-pixels-and-captures)
10. [Deferred, each with an owner](#10-deferred-each-with-an-owner)

---

## 1. Baseline

At `e5caefb`, measured 2026-09-23:

| measure | value | how |
|---|---|---|
| suite | **1617 tests in 3 suites**, passed; 0 `error:`; the only `warning:` is SwiftPM's deprecation notice | `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel`, unfiltered |
| goldens | **97** | `find Tests/MetalUILayoutTests -name "*.json" \| wc -l` |
| guards | 77 | CLAUDE.md's per-file `grep -c canTypecheck` |
| the two exit suites, filtered | **10 tests** (`DeferredTests` 9, `AbsoluteOverlayTests` 1), passed, all legacy-only | `--filter "DeferredTests\|AbsoluteOverlayTests"` |
| `AuthorityCoverage.expected` | **67** | `ZZAuthorityRollCall.swift`'s `#require` |
| screen | unlocked: no `CGSSessionScreenIsLocked` line, `displayAsleep main: 0` (01:32 PDT) | `docs/probes/appkit-screen-lock-state.swift` |

**Stage 5 retires no golden and must move none.** Nothing here touches
`Sources/MetalUILayout/`. Check: `git diff --name-only e5caefb HEAD -- 'Tests/**/*.json'` empty.

## 2. Evidence gathered for this design

### 2.1 What the two exit suites assert today

`DeferredTests` (9, all legacy): **five are pass-level** — they drive
`PaintPass.deferred`/`PrepaintPass.deferred` on a bare `Frame` and never lay
anything out (`aDeferredFillDrawsAfterAPlainSiblingEmittedLater`,
`aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface`,
`deferredsLayerAndClipBothPopOnExit`,
`deferredOnPrepaintEscapesTheActiveClipForScrollRegistration`,
`nestedDeferredsAllLandOnTheSameRootLayer`); **four render a tree** straight into
a `Frame` whose root is the tree
(`aNamedChildUnderDeferredResolvesTheSameAsUnderABox` — identity;
`aDeferredElementHoistsItsChildAboveASiblingDeclaredAfterIt` — paint order and
widths; `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting` — the
inner region at x 30, 150 wide; `aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll`
— the deferred marker's y unchanged by a 40pt scroll that moves its sibling).
**Every `Deferred` in them is in-flow**; none is absolute.

`AbsoluteOverlayTests` (1): `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`
— divergence 11 (an absolute box in a 41×60 viewport at (60, 30) lands at the
window-space (5, 5) and is masked out; scrolled 12 it moves to y −7) and, as
its differential, the same box inside `Deferred` at (5, 5) with the whole
200×200 mask.

### 2.2 Both suites' trees under the proposal authority, today

Scratch **S5** (plain `Frame`, the tree as root) and **S6**
(`LayoutDifferential.compare`), record §28 §2.2:

- **The four in-flow trees lower with no diagnostic.** In the harness, the
  hoist tree agrees in all 5 ids with scenes, hitboxes, accessibility and state
  equal; the other three disagree only in `ScrollView` viewport heights (stage
  3's cause 3, `LR-BC`: the lowered viewport fills its proposal on the scrolling
  axis where the legacy one hugs), never on the axes the tests assert.
- **Rendered as the frame's root, they move** — the hoist row to x 65/95, the
  nested scroller to x 125 — because a native root is centred at its answer
  (`CN-J`, divergence 4, stage 6b's). So the exit arms are hosted (§7, lane 2).
- **Both `AbsoluteOverlayTests` trees report `[box.position, box.inset]`**, and
  so does every absolute arm S5 tried; the demo with the modal on reports
  `[stack.position, stack.inset]`
  (`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`).

### 2.3 A stage-4 claim refuted

Record §27 §8.2 says `aListInsideADeferredIgnoresTheEscapedScrollersOffset`
"under `.proposal` … **aborts** the run rather than failing a test". **Measured
false at `e5caefb`**: with both `renderWindowed` calls switched to `.proposal`
the test **passes** (filtered run; scratch S7 reproduces it with diagnostics on:
0 fields, 82 bounds wrapped, 17 unwrapped — the same as legacy). The claim was
never measured (the "confident cannot" shape). Lane 2 parameterises the test and
the record carries the erratum (`LR-CN`).

### 2.4 The legacy engine's absolute answers, measured

Scratch **S5**/**L** inside `Box { Deferred { … } }` (record §28 §2.4); the
columns are what the lowering must reproduce or rule:

| shape (window 200×100 unless noted) | legacy rect |
|---|---|
| top 5, left 5, 30×20 content | (5, 5) 30×20 |
| same, plus `margin` 7, `flexGrow` 1, `alignSelf .center` | (5, 5) 30×20 — **ignored** |
| right 7, bottom 9, declared 30×20 | (163, 71) 30×20 |
| no insets, declared 30×20, after a 40×20 in-flow sibling | (0, 0) — divergence 9 |
| top 50 %, left 25 %, declared 10×10 | (50, 50) — per axis (`AP-D`) |
| top 10, right 90, bottom 80, left 100, padding 10, auto size | (100, 10) **20×20** — stretched 10×10, floored (`BM-4`) |
| top/left 5, auto width, `minSize.width` 50 (content 30) | 30 wide — **min ignored** |
| same, `maxSize.width` 10 | 30 wide — **max ignored** |
| left/right 5, auto width, `maxSize.width` 10 / `minSize.width` 300 | 190 wide — **both ignored** |
| declared width 40, `minSize.width` 50 | 50 — clamped (declared axes only, `AP-E`) |
| declared 8×8, padding 10 | 20×20 (`BM-4`) |
| auto-width `Text` (58 chars), left 0 / 50 / 150, window 200×200 | **196×32 at every inset** — measured against the window, not the window minus the inset |
| root with `border` 4, top/left 5 | (9, 9) — the containing block is the root's padding box |
| root `width` 100 (window 200), right/bottom 5, 10×10 | (85, 85) |
| the absolute box **as** the root, top/left 5 | (0, 0) — a root's insets are ignored |
| `Deferred` as the root, same content | (0, 0) |
| root `.frame(maxWidth: 100)` over `Box { Deferred { … } }`, right/bottom 5, 10×10 | (85, 85) — the clamped root is the containing block (critic round 1) |
| root `.frame(minWidth: 300)`, same | (285, 85) |
| root `.frame(maxWidth: 300)`, and no frame, same | (185, 85) |
| `.relative` bordered ancestor at (0, 30), top/left 5 | (58, 38) |
| gapped column [10×10, `Deferred` absolute, 11×10], gap 12 | second box at y **22** — out of flow, no gap |

### 2.5 The probe, re-run and extended

`xcrun swiftc docs/probes/swiftui-overlay-presentation.swift`, Apple Swift 6.4
(swiftlang-6.4.0.33.1), macOS 27.0 (26A428), exit 0. **Revision 1's P and H
lines re-ran byte-identical** to the header, before and after the new arms.
**Revision 2 adds group Q** (29 lines, run twice, byte-identical), each arm with
a positive control:

- **Q1/Q1c** — one inset per axis is `.padding` on that edge inside
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment:)` aligned to it:
  (5, 5) top-leading; (63, 71) = (100 − 7 − 30, 100 − 9 − 20) bottom-trailing.
  Each reads a pixel just inside and just outside the predicted box.
- **Q2** — both insets and no size: a greedy frame inside the padding fills the
  gap (x 20..<60, y 10..<70).
- **Q3/Q3c** — a leading inset of 50 proposes the content **50** of the root's
  100; with no inset, 100.
- **Q4/Q4c** — an overlay is proposed its host's size: 100×100 at the root,
  20×20 on a 20×20 view. An overlay at the declaration site is **not** laid out
  against the window.
- **Q5/Q5c** — an overlay centres by default; `.topLeading` puts it at the origin.
- **Q6/Q6c** — an overlay adds nothing to its host's size (40, against 100 when
  the same view is a stack member).

P4/P5 (revision 1): a presented `.sheet`/`.popover` is laid out 0 times and drawn
nowhere in the presenter's tree; P1/P2: an `.overlay` is clipped by an ancestor
and is not hoisted over a later sibling.

## 3. Decisions, concept by concept

| concept | decision | spelling / owner | ruling |
|---|---|---|---|
| **the portal's paint and prepaint half** (layer 1, whole-surface clip, zero translation, scroll context cleared in layout) | unchanged, authority-independent | — | `LR-CH` |
| **an in-flow `Deferred`** (content not absolute) | stays layout-transparent under both authorities — it already agrees (§2.2). No SwiftUI spelling is needed: no **probed** SwiftUI spelling is an in-flow portal (P1/P2: `.overlay` is clipped and not hoisted; P3's `.zIndex` hoists within one `ZStack` only) — a narrower claim than "SwiftUI has none", which no probe arm tests (`LR-CP` item 5) | — | `LR-CH` |
| **a `Deferred` whose content is `.position(.absolute)`** | **a presentation root**: laid out in its own native run against the window, contributing nothing to its parent's layout | SwiftUI's window-root overlay: Q4, Q6; P4/P5 for "outside the presenter's layout" | `LR-CH`, `LR-CM` |
| **all-inset absolute** (`inset(0)`, the demo's scrim) | lowered: a greedy item frame W on both axes, aliased as the element's rect, inside the (zero) padding, inside a window-sized frame | Q2 | `LR-CI` |
| **partial insets** | lowered per axis: the given edge as padding, the window frame aligned to it; both edges with a declared size → the leading one wins (legacy's rule) | Q1, Q1c | `LR-CI` |
| **no insets** | lowered to `.topLeading` at the window's origin — the legacy answer | Q5c; **divergence 9 survives, on both authorities** | `LR-CI`, `LR-CN` |
| **percentage insets** | lowered: `left`/`right` against the window's width, `top`/`bottom` against its height (`AP-D`) | resolved at registration from `Frame.contentSize` | `LR-CI` |
| **the containing block** | the window, by construction; every tree where the legacy engine's containing block is **not** the window reports by name: a positioned ancestor already reports `position` at its own site; a bordered or non-window-sized root reports `deferred.containingBlock`; a presentation inside a non-covering presentation `deferred.nested`; a `Deferred` root `deferred.root`; a root `.frame(minWidth:)`/`.frame(maxWidth:)` that clamps it off the window also `deferred.containingBlock` (`LR-CP` item 2) | owner **stage 9** (the reports exist only to keep the differential honest) | `LR-CL` |
| **content measured on an axis with one inset** | lowered with SwiftUI's proposal (window − inset, Q3), a **deliberate proposal-only change** from the legacy engine's (window), pinned by name | — | `LR-CJ` |
| **stretched below padding + border** | lowered with the inset box kept and the padding overflowing (`LR-AH`/`LR-AW`'s answer), a deliberate proposal-only change from legacy's `BM-4` floor, pinned by name | — | `LR-CJ` |
| **`minSize`/`maxSize` on an auto axis of an absolute box** | reports `<site>.minSize.absolute` / `<site>.maxSize.absolute` — legacy **ignores** them (measured), SwiftUI and CSS would not | owner **stage 8** | `LR-CJ` |
| **flex item fields and `margin` on an absolute box** | consumed and dropped — the legacy engine ignores every one (measured) | — | `LR-CK` |
| **an absolute box outside a `Deferred`** | **removed** from the proposal authority: reports `<site>.position` and `<site>.inset` at its consumer (unchanged names), `…unconsumed` with none; trap message names **stage 10** | — | `LR-CK` |
| **divergence 9** | survives, now on both authorities | new pin under both | `LR-CN` |
| **divergence 10** | unchanged; amended: agrees with SwiftUI's presentation (P4/P5), disagrees with its overlay (P1/P2) | pins parameterised | `LR-CN` |
| **divergence 11** | **legacy-only** from this stage: the spelling reports under the proposal authority; retires when the legacy authority does (stage 9) | legacy arm keeps pinning it | `LR-CN` |

## 4. The mechanism

### 4.1 `Deferred.requestLayout` under the proposal authority (`LR-CH`)

```
let before = frame.lowering.presentations.count
let (nodes, contentLayout) = pass.withoutScrollContext { content.requestGroupLayout(…) }   // unchanged
let node = nodes[0]
guard pass.lowersToProposal,
      let item = frame.lowering.items[node], item.declared.position == .absolute
else { return (node, …) }                          // in-flow: exactly today's path
if frame.lowering.presentations.count > before && !coversWindow(item.declared) {
    noteUnlowerable(.deferred, "nested")           // LR-CL
}
frame.lowering.consume(node)
let root = pass.lowerPresentation(node, item)      // §4.2
let placeholder = frame.requestNativeLeaf { 0×0 }
frame.lowering.record(LoweredItem(declared: Style(), animated: Style(), site: .deferred,
                                  contentAlignment: .topLeading, kind: .presentation), for: placeholder)
frame.lowering.alias(placeholder, to: frame.lowering.alias(node))   // the content's ELEMENT rect
frame.lowering.presentations.append((placeholder: placeholder, root: root))
return (placeholder, …)
```

`coversWindow(declared)` is true when all four insets are zero lengths, both
sizes `auto` and every border edge zero: the enclosing box's padding box is then
the window, which is the one nested case the legacy engine answers the same way
(the demo's card could hold a tooltip).

The legacy branch is untouched: under `.legacy` this function returns `nodes[0]`
exactly as today.

### 4.2 `lowerPresentation` — the placement (`LR-CI`)

Per axis (horizontal reads `left`/`right` and `size.width`; vertical
`top`/`bottom` and `size.height`), **which insets are given and whether the size
is `auto` from the declared style; the inset lengths from the animated style**
(`LR-AS`; `inset` animates, `AnimatedStyle.swift:371`):

| declared size | insets given | W on this axis | padding edges | frame alignment |
|---|---|---|---|---|
| `auto` | both | greedy: min 0, max ∞ (aliased) | leading and trailing | leading |
| `auto` | leading only | none | leading | leading |
| `auto` | trailing only | none | trailing | trailing |
| `auto` | neither | none | none | leading (divergence 9) |
| px/rem (min/max folded, `AP-E`) | leading, or both | none | leading | leading |
| px/rem | trailing only | none | trailing | trailing |
| px/rem | neither | none | none | leading |

Registered innermost first: the element's own lowered node (unchanged: its
padding, border and declared size are its own site's) → **W** (one
`requestNativeFrame` carrying both axes' bounds, aligned by the element's
`contentAlignment`, registered only when an axis is stretched, and **aliased**
as the element's rect — `LR-AB` item 3) → `requestNativePadding(insets)` (only
when an edge is non-zero) → `requestNativeFrame(width: W_window, height:
H_window, alignment:)`. The last is the presentation root.

- **Lengths**: px as points, rem × `rootFontSize`, `.percent(f)` × the window's
  extent on that axis (`Frame.contentSize`).
- **Reported instead** (`LR-CJ`): `minSize`/`maxSize` on an `auto` axis →
  `<site>.minSize.absolute`/`<site>.maxSize.absolute`; the presentation then
  still registers (the frame completes, as every report does).
- **Dropped** (`LR-CK`): `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`,
  `margin` — consumed with the record, as a stack parent drops them (`LR-AZ`).

### 4.3 Where presentations are laid out (`LR-CM`)

`Frame.computeRootLayout(root:)` under the proposal authority, when
`lowering.presentations` is non-empty:

1. **The checks** (`LR-CL`): `deferred.root` if `root` is a placeholder;
   otherwise, if the root's record exists, `deferred.containingBlock` when its
   **declared** style has a non-zero border on any edge, a non-`auto` size on
   an axis that does not resolve to the window's extent there, **or a
   `minSize` resolving above / `maxSize` resolving below the window's extent on
   an axis (any percentage `minSize`/`maxSize` counts)** — critic round 1,
   `LR-CP` item 2: a `.frame(maxWidth:)`/`.frame(minWidth:)` root is a
   `.frameLayer` record, which `reportUnconsumedLoweredItems` never reads, and
   the legacy engine's containing block follows the clamped root (measured:
   `Box { Deferred { 10×10 right/bottom 5 } }` in 200×100 is (85, 85) under
   `.frame(maxWidth: 100)`, (285, 85) under `.frame(minWidth: 300)`, (185, 85)
   under `.frame(maxWidth: 300)` and with no frame). A root with no record (the
   harness's native root) is the window by construction.
2. **Each presentation root, in registration order**, through
   `tree.computeNativeLayout(root:proposal:in:)` with the window as proposal and
   bounds — **before the root**, so `LayoutTree.lastNativeLayoutWork` still
   reads the root's own run after the frame (`SA-M`'s pins are unchanged).
3. The root, exactly as today.

Separate runs, so each presentation's depth counts from its own root (`SA-L`).
`renderWindowed`-style helpers that call `computeRootLayout` directly get the
same behaviour.

### 4.4 Consumers drop the placeholder, and the absolute content's fields move to them (`LR-CK`)

- **The frame arm's style check keeps the UNDROPPED count** (critic round 1,
  `LR-CP` item 1). `legacyFrameLayerDiagnostics(_:declared:childCount:)`
  compares `declared` with `layer.lowered(spec.style(), childCount:)`, and
  `ModifiedElement.requestLayout` built `declared` from
  `lowered(_:childCount: children.count)` over the undropped children — the
  placeholder counted. Handing it the dropped count turns a one-node frame over
  a presentation (count 1 → 0) into `display: .stack` declared against a flex
  row expected, and a two-member frame (2 → 1) into the reverse: both report a
  spurious `modifierLayer.style` and 1.4's two `.frame` arms read it. So the
  frame arm passes `children.count` to the diagnostics and the dropped list to
  `consume`, `planLegacyItems` and `registerLegacyItems`; `lowerLegacyNode`'s
  `legacyContainerDiagnostics` reads no count today and may take either.
- **The placeholder is removed from `children` at entry** — before `consume`,
  `planLegacyItems` and the single-child stretch elision count (but **not**
  before the frame arm's style check, above) — by `lowerLegacyNode` (flex, stack, a
  `.padding` layer, a `ScrollView`'s content), `lowerLegacyLayer`'s frame arm and
  `loweredComponentFrame`, through one helper
  `LoweringState.droppingPresentations(_:)`. **`ListRows` cannot receive one**
  (its children are the `List`'s own row `Box`es, never a `Deferred`) and says so
  in a comment rather than calling the helper. A container whose only child was
  a placeholder lowers as an empty container, as the legacy one lays out an empty
  flow.
- **`loweredComponentFrame` over a placeholder member reports
  `deferred.amended`** and frames nothing: the legacy amend overwrites the
  absolute box's own size (divergence 48's mechanism), an answer this stage
  does not reproduce.
- **`.absolute` leaves `legacyLeafDiagnostics`**: `position` is reported there
  only for `.relative`, and `inset` only when the position is not `.absolute`
  (so `.relative` and static rows — `LoweringLeafTests`' and
  `LayoutAuthorityTests`' existing arms — are unchanged). For `.absolute`,
  `planLegacyItems` appends `position` and `inset` (when any inset is given) at
  the **child's** site after the child's other item fields, and
  `reportUnconsumedLoweredItems` appends `position.unconsumed` /
  `inset.unconsumed` — so the names a reader already knows are the names that
  stay.
- `UnlowerableField.owningStage`: a field beginning `position` or `inset` →
  **"10"**; ending `.absolute` → **"8"**; site `deferred` → **"9"**.

## 5. What must not move, and what does

### 5.1 Must not move — each with its pin

| property | pin (existing unless marked new) |
|---|---|
| the demo scrim hoists over everything, escapes the `ScrollView`'s clip **and** its translation (`AP-I`) | `aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface`, `aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll(_:)`; **new** `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities(_:)` |
| click-to-dismiss, and the wheel NOT scrolling the list beneath (`IN-W`) | `anOpaqueDeferredScrimSwallowsAWheelEventInsteadOfScrollingTheListBeneath(_:)` (both authorities already); **new** `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities(_:)` |
| declaring scope's environment; opacity NOT reset (`OM-AA`, divergence 46) | `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`, `aDeferredPortalInsideAFadedSubtreeIsStillFaded`; **new** presentation-shaped twins under both authorities (lane 3) |
| nested `Deferred` on one layer (`AP-H`) | `nestedDeferredsAllLandOnTheSameRootLayer`; **new** `nestedPresentationsLandOnOneLayerUnderBothAuthorities(_:)` |
| identity (`AP-K`) | `aNamedChildUnderDeferredResolvesTheSameAsUnderABox(_:)`; the census's modal ids |
| hit testing, accessibility, focus, disabled | `aDeferredHitboxOutranksAndEscapesTheOneItPaintsOver`, `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `focusSurvivesAndDispatchesInsideADeferredSubtree`, `aDisabledScopeReachesIntoDeferredContent`; **new** `aPresentationsAccessibilityRecordAndFocusMatchUnderBothAuthorities(_:)` |
| animation | **new** `anAnimatedInsetInterpolatesItsValueUnderBothAuthorities(_:)` |
| production (legacy) layout | the twelve `CN-R` images at 0 (§9) |

### 5.2 What moves, each with a ruling

- **Under the proposal authority only**: a `Deferred` + absolute tree stops
  reporting and lays out (the demo's modal-on census report goes from
  `[stack.position, stack.inset]` to `[]`); an absolute box outside a `Deferred`
  keeps reporting but its trap names stage 10 instead of 2; two deliberate
  answers differ from the legacy engine (`LR-CJ`), pinned by name, unnumbered
  per the 2026-09-21 precedent (record §04), the Docs phase deciding.
- **Under the legacy authority: nothing.**

## 6. API and files

All internal; no public API changes, so no new typecheck guard.

| file | change |
|---|---|
| `Sources/MetalUI/Deferred.swift` | §4.1's proposal branch; doc comment's layout paragraph |
| `Sources/MetalUI/LegacyLowering.swift` | `lowerPresentation(_:_:)`; the placeholder filter at the three consumers; `position`/`inset` for `.absolute` moved from `legacyLeafDiagnostics` to `planLegacyItems`; `deferred.amended` |
| `Sources/MetalUI/LoweringState.swift` | `LoweredItem.Kind.presentation`; `LoweringState.presentations`, `droppingPresentations(_:)`; `position.unconsumed`/`inset.unconsumed` in `reportUnconsumedLoweredItems` |
| `Sources/MetalUI/Frame.swift` | `computeRootLayout`: the checks, then the presentations, then the root |
| `Sources/MetalUI/LayoutAuthority.swift` | `LoweringSite.deferred`; `owningStage` |
| `Sources/MetalUI/ListRows.swift` | one comment |
| `Tests/MetalUITests/PresentationLoweringTests.swift` | **new** (lane 1) |
| `Tests/MetalUITests/PresentationWindowTests.swift` | **new** (lane 3) |
| `DeferredTests`, `AbsoluteOverlayTests`, `ListTests`, `AuthorityCoverage`, `ZZAuthorityRollCall`, `LoweringCorpusTests`, `LayoutAuthorityTests`, `DecorationPaintTests`, `EnvironmentTests` | as each lane says |

`swift package clean` is **not** owed: no stored property or case is added to a
**public** type crossing a module boundary (`LoweredItem`, `LoweringState`,
`LoweringSite` are internal to `MetalUI`). Take it anyway if the impossible
happens (CLAUDE.md).

## 7. Lanes

Three, sequential in one worktree. Each lane commits its implementation first,
then runs its mutations (commit, restore from a `cp` copy, full unfiltered
suite, `git status --short` after each, every reddened test named), then appends
its section to record §28 and its corrections ruling (the next unused `LR-`
letter), and re-takes the twelve `CN-R` images. **No lane takes a red-before by
aborting the process** (`LR-BX`): every proposal-authority window or production
frame in a new test is pre-flighted under diagnostics with `try #require` on an
empty report, and every trap is pinned by an exit test.

### Lane 1 — the presentation root (`LR-CH`, `LR-CI`, `LR-CJ`, `LR-CK`, `LR-CL`, `LR-CM`)

Source: every `Sources/` row of §6. Tests: `PresentationLoweringTests.swift`
(new), the modal half of `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`,
one arm of `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.

| # | test | what it asserts | red-before (at `e5caefb` source) | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` | `LayoutDifferential.compare` at **200×100** (non-square, `AP-D`), one arm per §2.4 row that lowers: top/left px; right/bottom px declared; all four, auto size (stretched both axes); left/right auto + declared height; all four + declared size (leading wins); none, after an in-flow sibling (divergence 9, (0, 0)); percent; rem; declared 40 with `minSize` 50 (→ 50); `margin`/`flexGrow`/`alignSelf` present (dropped). Each: report `[]`, `disagreeing`/`legacyOnly`/`loweredOnly` empty, scenes and hitboxes equal, and the box's and the `Deferred`'s rect equal to §2.4's literal | every arm reports `[box.position, box.inset]` (`[box.position]` for "none") | **M1a** the trailing alignment written as leading (the right/bottom arm); **M1b** `top`'s percentage resolved against the width (the percent arm: y 100 against 50); **M1c** W registered but not aliased (the stretched arms: the element's rect and its background); **M1d** the placeholder's alias removed (every arm's `Deferred` id reads 0×0) |
| 1.2 | `anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBoxWhereTheLegacyEngineFloorsIt` | pinned by name, both literals: legacy (100, 10) 20×20; lowered (100, 10) 10×10, the padding overflowing (`LR-CJ`) | reports | **M1e** W's minimum set to the padding + border sum (lowered reads 20×20) |
| 1.3 | `anAbsoluteTextWrapsAtTheWindowMinusItsInsetWhereTheLegacyEngineWrapsAtTheWindow` | pinned by name: at left 150 in 200×200 the legacy text is 196×32 at (150, 0); the lowered one is at (150, 0), at most 50 wide and taller than 32 (Q3) | reports | **M1f** the padding's leading edge forced to 0 (lowered x 0, width 196) |
| 1.4 | `aPresentationPlaceholderIsDroppedByEveryLoweredContainer` | differential, report `[]`, no disagreement, in six parents: a gapped column [10×10, `Deferred` absolute, 11×10] (second box y **22**); a `Stack` [10×10, it]; a `ScrollView`'s content [it, a tall `Box`]; and — since `Deferred` has no modifier surface, a `Component` whose body is the `Deferred` is how a layer receives the placeholder directly — that component with `.padding(4)` (the wrap op, `OM-D`), with `.frame(width: 50, height: 50)` (a one-node frame layer), and a two-member one [10×10, it] with the same `.frame` (the per-member row, `LR-BH`) | reports | **M1g** the filter removed from `lowerLegacyNode` (the column, stack, scroll and `.padding` arms); **M1h** removed from `lowerLegacyLayer`'s frame arm only (**the two-member `.frame` arm only** — lane 1's corrections, `LR-CQ`: measured, the one-node arm agrees over the undropped 0×0 placeholder; this row read "the two `.frame` arms"); **M1o** (critic round 1, `LR-CP` item 1) the frame arm's `legacyFrameLayerDiagnostics` handed the **dropped** count (both `.frame` arms report `[modifierLayer.style]`) |
| 1.5 | `aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName` | plain `Frame`, proposal, diagnostics; each arm's report exactly: bordered root → `[deferred.containingBlock]`; root width 100 in 200 → same; root width 200 → `[]`; auto root → `[]`; `Deferred` root → `[deferred.root]`; presentation inside a top/left-5 presentation → `[deferred.nested]`; inside an `inset(0)` one → `[]`; inside a `.relative` ancestor → `[box.position]` (the ancestor's) ; absolute in a column, no `Deferred` → `[box.position, box.inset]`; absolute root → `[box.position.unconsumed, box.inset.unconsumed]`; `minSize` on an auto axis → `[box.minSize.absolute]`; `Component().width(70)` over a `Deferred`-absolute member → `[deferred.amended]`; **critic round 1 (`LR-CP` item 2)**: root `.frame(maxWidth: 100)` in 200 → `[deferred.containingBlock]`; root `.frame(minWidth: 300)` → same; root `.frame(maxWidth: 300)` → `[]` (the separating arm) | every `Deferred` arm reads `[box.position, box.inset]`; the absolute-root arm reads `[box.position, box.inset]` | **M1i** the containing-block check deleted (border, width-100 arms); **M1j** the nested check deleted; **M1k** `coversWindow` always false (the `inset(0)` arm reads `[deferred.nested]`); **M1l** `planLegacyItems`' `position` entry deleted (the column arm reads `[box.inset]`); **M1p** the check's `minSize`/`maxSize` clause deleted (the two clamped-frame arms read `[]`); lane 1's corrections (`LR-CQ`) add three arms (`maxHeight` on an auto axis → `[box.maxSize.absolute]`, a percentage `minWidth` on a declared axis → `[box.minSize.percent]`, inside a bordered `inset(0)` presentation → `[deferred.nested]`), an owning-stage-8 assertion on the reported `…absolute` fields, and **M1q** (`.absolute` → "2"), **M1r** (`maxSize.absolute` deleted), **M1s** (`minSize.percent` deleted), **M1t** (`presentationCoversWindow` ignoring the border) |
| 1.6 | `aPresentationTrapsAProductionProposalFrameNamingItsField` | exit test, diagnostics off, bordered root: exits with failure; stderr contains `MetalUI: deferred.containingBlock has no proposal lowering (plan task 7, stage 9)` | the child traps on `box.position … stage 2` | **M1m** `owningStage` for `.deferred` → "5" |
| 1.7 | `presentationsAreLaidOutBeforeTheRootSoTheRootsWorkRecordIsUnchanged` | `lastNativeLayoutWork` after a frame with a presentation equals the same tree's with the `Deferred` removed | the tree with the `Deferred` reports and its reported 0×0 leaf sits **in** the root's flow, so the two roots' work differs | **M1n** presentations laid out after the root |
| 1.8 | `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (modal half re-derived) | modal on: report `[]`; the six modal ids each either agreeing or attributed by literal to a named cause; counts re-derived (`#require`) | red after lane 1's source (the old expectation reads two entries) | **M1c**, **M1d** |
| 1.9 | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (one arm) | a bordered root over `Deferred`-absolute reports `[deferred.containingBlock]` | reports `[box.position, box.inset]` | **M1i** |

### Lane 2 — the exit suites under both authorities (`LR-CN`, `LR-CO`)

Tests only: `DeferredTests.swift`, `AbsoluteOverlayTests.swift`,
`ListTests.swift`, `AuthorityCoverage.swift`, `ZZAuthorityRollCall.swift`.

- **Hosting** (`LR-CO`): `aNamedChildUnderDeferredResolvesTheSameAsUnderABox`,
  `aDeferredElementHoistsItsChildAboveASiblingDeclaredAfterIt` and
  `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting` render through
  `LayoutDifferential.render(authority:width:height:)` (`DifferentialRoot`,
  top-leading, fixed size); `aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll`
  and `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt` need a
  scroller that can scroll, so they host in a **sized column `Box`** of the
  frame's size (`ListTests`' `hostStyle` pattern) over one shared `StateTable`
  — `DifferentialRoot`'s legacy stack offers fit-content and the viewport would
  hug its 340pt content (§2.2, S6). **Every legacy literal must be unchanged by
  hosting; one that moves is a finding the lane records before changing it.**
- **The five pass-level tests are not parameterised** — no element, no layout,
  no authority in their call path (`LR-BN`) — and each says so at its
  declaration.

| # | test | red-before | mutation |
|---|---|---|---|
| 2.1–2.4 | the four element-level `DeferredTests`, parameterised `(_ authority:)` with `AuthorityCoverage.record` | parameterised **before** hosting, measured per test (S5 predicts the nested-scroll test fails under `.proposal`: region x 155); recorded | **M2a** `Deferred.prepaint` without `pass.deferred` (the nested-scroll test, both authorities); **M2b** `Deferred.paint` without it (hoist and scrolled tests, both) |
| 2.5 | **new** `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities(_:)` — the demo's shape (`ScrollView { Deferred { Stack { card }.position(.absolute).inset(0).background(.scrim).onClick {} }; tall content }`), two frames, offset 40: the scrim's rect and mask are the window on both frames, layer 1; its hitbox opaque at the window rect, layer 1; the card centred; the in-flow content moved by 40 | lane 1's `Deferred` branch disabled in a scratch copy: the proposal pre-flight reads `[stack.position, stack.inset]` | **M1c** (the scrim's rect and hitbox shrink to the card-sized stack), **M2b** (the scrim's mask becomes the viewport) |
| 2.6 | `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt(_:)` — legacy arm as today; proposal arm: the plain half reports exactly `[box.position, box.inset]` (divergence 11 unspellable), the `Deferred` half's geometry and mask as legacy | parameterised before hosting: the proposal geometry moves (S5: (100, 85)) | **M1l** (the proposal plain half reads `[box.inset]`) |
| 2.7 | **new** `anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame` — exit test: stderr contains `MetalUI: box.position has no proposal lowering (plan task 7, stage 10)` at `e5caefb` the child traps naming **stage 2**, so the `stage 10` assertion is red (critic round 1, `LR-CP` item 4: this row said none was possible) | **M2d** `owningStage` for `position` back to "2" |
| 2.8 | `aListInsideADeferredIgnoresTheEscapedScrollersOffset(_:)`, parameterised | **none** — it passes under `.proposal` at `e5caefb` (§2.3); the lane says so at its declaration | **M2e** `withoutScrollContext` removed from `Deferred.requestLayout` (both arms) |

`AuthorityCoverage.expected` **67 → 74** (+4, +1, +1, +1); the roll call's
literal moves with it, and its header records the seven.

### Lane 3 — the must-not-move set through real windows, pixels, the record (`LR-CO`)

Tests: `PresentationWindowTests.swift` (new), `DecorationPaintTests`'
`aDeferredPortalInsideAFadedSubtreeIsStillFaded` and `EnvironmentTests`'
`aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`
parameterised, `AuthorityCoverage`/roll call. Every window under `.proposal` is
opened only after the same content's `LayoutDifferential.compare` report is
`try #require`d empty.

| # | test (all `(_ authority:)`) | red-before | mutation |
|---|---|---|---|
| 3.1 | `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities` — `demoContent()` with `showModal` in a 920 fake window: a wheel over the scrim leaves the list at offset 0 and is claimed; a click on the card keeps the modal; a click on the scrim outside the card sets `showModal` false | lane 1's branch disabled: the pre-flight reads two entries | **M1c** (the scrim's hitbox shrinks to the card-sized stack: the scrim click misses) |
| 3.2 | `aPresentationInsideAFadedSubtreeIsStillFadedUnderBothAuthorities` (`OM-AA`) | as 3.1 | **M3a** `pass.deferred` resets the opacity stack (both) |
| 3.3 | `aPresentationKeepsItsDeclaringScopesEnvironmentUnderBothAuthorities` (theme and `.disabled`) | as 3.1 | **M3b** `Deferred.requestLayout` wraps content in the root environment (both) |
| 3.4 | `aPresentationsAccessibilityRecordAndFocusMatchUnderBothAuthorities` — the scrim's "Close modal" button record with window geometry; focus inside the presentation dispatches a key | as 3.1 | **M1c** (the record's geometry) |
| 3.5 | `anAnimatedInsetInterpolatesItsValueUnderBothAuthorities` — `withAnimation(.linear(duration: 1))` top 10 → 50 on a presentation, `simulateTick` at half: y 30 on both, and `try #require` that 30 differs from both endpoints. **Linear, named** (critic round 1, `LR-CP` item 3): `withAnimation`'s default is `Animation.spring(duration: 0.5, bounce: 0)` (`Animation.swift:230`), whose half-way value is not 30 | as 3.1 | **M3c** `lowerPresentation` reads the declared insets (proposal reads 50 mid-flight) |
| 3.6 | `nestedPresentationsLandOnOneLayerUnderBothAuthorities` (`AP-H`) — a tooltip presentation inside the demo-shaped `inset(0)` scrim: both on layer 1, no report | as 3.1 | **M3d** `pushLayer` → `activeLayer + rootLayer` (both) |
| 3.7–3.8 | the two parameterised existing pins | parameterised before anything else: measured, expected green (in-flow `Deferred`s lower today) | **M3a**, **M3b** |

`AuthorityCoverage.expected` **74 → 82**. Then §9, and the stage's closing
record sections (what landed, tests per file, red runs, mutations, demo
comparisons, hazards, deferrals, **For the integrator**).

## 8. The exit test

`DeferredTests` and `AbsoluteOverlayTests` under the proposal authority: every
element-level scenario in both files parameterised over `LayoutAuthority.allCases`,
recorded in `AuthorityCoverage` and read back by
`everyParameterisedScenarioRanUnderBothLayoutAuthorities` — **5 of `DeferredTests`'
10** (the other five pass-level, each saying why) and **1 of 1** in
`AbsoluteOverlayTests`, plus its exit test 2.7. Green in one unfiltered run,
with the counts read from the summary line.

## 9. Demo, pixels and captures

**Production runs the legacy authority until 6b, and no legacy path changes**, so
every lane's twelve-image offscreen comparison (`docs/probes/demo-pixels/compare.sh`,
against `e5caefb`) must read **0 differing pixels in all twelve**, the
two-authority chrome pair included; non-zero is a finding. When the lock probe
shows no `CGSSessionScreenIsLocked` line and `displayAsleep main: 0` — true at
design time (§1) — lane 3 also runs `docs/probes/window-capture/capture.sh
<scratch> e5caefb <HEAD>` and records each capture's reading. **No demo look is
owed**: nothing in production runs the proposal authority.

**Proposal-authority expectation, recorded not shipped:** the demo with the
modal on lowers with an empty report (lane 1's 1.8), which removes the last
`Deferred`/absolute entry stage 6b would otherwise have trapped on.

## 10. Deferred, each with an owner

| item | owner |
|---|---|
| `deferred.containingBlock`, `deferred.nested`, `deferred.root`, `deferred.amended` — deleted with the legacy authority, the presentation's containing block then being the window by definition | stage 9 |
| an absolute box outside a `Deferred`; `Position.relative`; `inset` on a static box; the public spelling of a presentation's insets once `Style`'s CSS fields go | stage 10 |
| `minSize`/`maxSize` on an absolute box's `auto` axis (`…absolute`) | stage 8 |
| `size.percent` on an absolute box (still reported at its own site, `LR-AI`) | stage 8 |
| divergence 11's retirement (legacy-only from here) | stage 9 |
| root placement (divergence 4 vs `CN-J`), which is why every exit arm is hosted | stage 6b |
| numbering the two `LR-CJ` answers, divergence rows 9/10/11's amendments | the Docs phase |
