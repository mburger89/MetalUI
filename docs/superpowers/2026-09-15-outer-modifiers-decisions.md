# Outer modifiers and modifier order — decisions

Plan task 5. Spec:
[`specs/2026-09-15-outer-modifiers-design.md`](specs/2026-09-15-outer-modifiers-design.md).
Record: [`../record/15-outer-modifiers.md`](../record/15-outer-modifiers.md).
Branch `feat/outer-modifiers`, from `c4b5853`.

Rulings are **lettered**: `OM-A` … `OM-AG`. **Next unused: `OM-AH`.** A bare
`OM-1` is a typo, not a citation; the two-letter tails (`OM-AA`…`OM-AG`) are
deliberate, as `CO-`'s and `TB-`'s are.

**Status: design revised twice; lanes 1 and 2 built.** `OM-AE`, `OM-AF` and
`OM-AG` are lane 2's, each written from a run rather than from a probe. `OM-AD` is lane 1's, and it is
the first ruling here written from a test run rather than from a probe: two of
the instruments this document specified could not fail, and the mutation round
that found them is recorded in record §15's lane 1 entry. Nothing in `Sources/`
has changed — lane 1 adds one test file and no production line. Every
ruling below states what was measured and what was only read; `OM-S` is the
summary of that split and **`OM-AC` is round 2's correction to it**. The
dispositions of seventeen critic findings are tabled at the end, under "Design
review round 2"; rulings amended in round 2 carry a **Round 2** paragraph
rather than being silently rewritten. Four SwiftUI probes were written and run
in this session, and **three were extended and re-recorded in round 2** (each
carries a `RE-RECORDED` block in its own header saying what was added and why):

| probe | what it settles |
|---|---|
| `docs/probes/swiftui-outer-modifier-order.swift` | which modifiers change layout; what area a `.background` covers per chain order; that padding accumulates |
| `docs/probes/swiftui-border-clip-paint.swift` | where `.border` draws; corner-radius/border/background/opacity ordering, by pixels |
| `docs/probes/swiftui-content-shape-hit-region.swift` | the default hit region, `.contentShape`, `.allowsHitTesting`, and whether padding is hittable — by synthesized clicks into real windows |
| `docs/probes/swiftui-component-distribution.swift` | what a modifier on a custom view with a multi-view body does, and with a single-leaf body |

Each carries its recorded stdout, its positive controls and its toolchains in
its own header. Both run forms (`/usr/bin/swift` and a compiled `xcrun swiftc`
binary, Apple Swift 6.4, swiftlang-6.4.0.33.1, macOS 26.6.2 / 25G83) produced
byte-identical stdout with empty stderr and exit 0.

MetalUI's own current behaviour was measured the same session by scratch tests
in `Tests/MetalUITests/`, run under `swift test --build-system native
--no-parallel --filter`, and deleted; `git status --short` was clean after the
deletion. Their readings are quoted in the rulings that use them and listed in
record §15.

---

## OM-A — the taxonomy: wraps / self / paint-only / prepaint-only / distributes

**Ruling.** Every outer modifier is classified as exactly one of five kinds, and
the spec's §3 matrix is the written form the plan asks for:

- **wraps** — contributes a layout node around the receiver;
- **self** — writes the receiver's own `Style`/`Decoration`/`Handlers`, which on
  a `ModifiedElement` chain is **the outermost layer**;
- **paint-only** — emits or scopes primitives, contributes no node;
- **prepaint-only** — changes what is registered for hit testing, emits nothing;
- **distributes** — applied to each of a `Component`'s top-level nodes.

The classification is not documentation-only: lane 1's
`everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` derives each
row's kind from a measured triple (node delta, outer-size delta, rect delta)
through a real `Window`, so a row whose declared kind is wrong fails.

**Reasoning.** The plan asks to "pin whether each wraps, distributes through a
`Component`, or affects only paint", which is three kinds. Two more were forced
by what is actually there. **"self"** because the legacy path's
`background`/`cornerRadius`/`onClick` do not wrap and do not distribute — they
write the receiver, and the receiver of a chained modifier is the outermost
layer, which is what makes them order-sensitive at all (`OM-C`).
**"prepaint-only"** because hit testing is registered in a phase of its own and
a modifier that changes it emits nothing: folding it into "paint-only" would
have made `allowsHitTesting` and `contentShape` look like paint effects, and
the one lane-3 mutation that matters (applying a content-shape inset to
`bounds` before `registerHandlers` rather than inside it) is invisible unless
the two are distinguished.

**Evidence.** Layout-neutrality of the paint-only set is probe
`swiftui-outer-modifier-order` L2…L9: `.border`, `.opacity`, `.clipShape`,
`.cornerRadius`, `.allowsHitTesting`, `.contentShape`, `.focusable`, `.overlay`
all leave a 20x20 leaf at outer 20x20, where `.padding(8)` (L1) reads 36x36.

**Cost if wrong.** A modifier filed under the wrong kind is a wrong sentence in
the matrix and a wrong row in one test; the test is table-driven, so the
correction is one row. The kinds are not encoded in any type, so nothing else
depends on them.

---

## OM-B — a legacy `.border` is paint-only and draws inside the box

**Ruling.** `Decoration` gains `border: BorderStyle?`, and
`StyledElement.border(_ token: ColorToken, width: Pixels)` writes it. It
contributes no layout node, changes no size, and is drawn **inside** the
element's own box, as `MUIRect.borderWidths` already draws. It is emitted in the
**same** `pass.fill` call as the background (`OM-O`), rounded by the same
`Decoration.cornerRadius`.

**Reasoning.** `Frame.fill` and `PaintPass.fill` already take `borderColor` and
`borderWidths`; the proposal `.border` is their only caller today. The blocker
recorded at `Frame.fill` and in `Decoration`'s doc — "paint has no *resolved*
border width to pair a colour with, because the engine computes one inside
`contentBox` and discards it" — is a blocker for a width derived from
`Style.border`, whose `Length` percentage case must resolve against the
containing block's width. A width declared on `Decoration` in `Pixels` has
nothing to resolve, so the blocker does not apply to it. That is the whole of
why this is now cheap and was not before.

**Evidence.** SwiftUI's `.border` is layout-neutral (L2: outer 20x20) and draws
inside: `swiftui-border-clip-paint` B1 reads the border colour at (1,1) and
(3,3) and the content at (6,6) on a 40x40 with width 4; B2 shows the same over
a transparent leaf, so it is the border and not a fill.

**Cost if wrong.** If SwiftUI's border were actually centred on the edge or
outset, every bordered element would be 2·w too small or too large relative to
SwiftUI. B2's `clear` arm rules the alternative out directly: an outset border
would have painted outside the 40x40 and a centred one would have shown the
backdrop at (1,1).

---

## OM-C — legacy `background`/`cornerRadius`/`onClick` already order correctly; pin, do not change

**Ruling.** The "self" modifiers write the outermost `ModifierLayer`, and that
is the behaviour this task **pins**, not one it introduces. No source change.

**Evidence.** SwiftUI (`swiftui-outer-modifier-order`): A1 `.padding(8)
.background` covers `(0,0) 36x36`; A2 `.background.padding(8)` covers
`(8,8) 20x20`; B1/B2 the same one level up with `.frame(60x60)`; A3 and D1/D2
the same three-deep. MetalUI, measured this session on a 13x16 `Text` leaf
(scratch `zzScratchBackgroundOrder`, `T3`/`T4`): `.padding(20).background`
emits `(0,0) 53x56`; `.background.padding(20)` emits `(20,20) 13x16`. Same
shape, both orders.

**Reasoning.** This is `MC-A`'s storage rule (`ModifiedElement`'s
`StyledElement` accessors read and write `outermost`) seen from the caller's
side. Nothing about it was designed for SwiftUI ordering, and it happens to be
exactly SwiftUI's ordering — which is worth a test precisely because it is
accidental and one line in `ModifiedElement.paint` could break it silently.

**Cost if wrong.** None to this task; the risk is the opposite — that the
agreement is coincidental for the fixtures chosen. Mitigated by testing three
shapes (padding, frame, three-deep) and by the mutation
(`ModifiedElement.paint` filling at `layout.inner[0]`'s bounds) reddening it.

---

## OM-D — `Component` padding wraps each top-level node

**Ruling.** `Component.padding(_:)` stops writing `Style.padding` onto each
top-level node and instead **wraps each top-level node in a real padding node**
carrying the same `Style` a `ModifiedElement` layer carries. `width` and
`height` keep today's amend (`OM-F`).

**Reasoning.** The plan's first sentence for this task is "complete the padding
migration", and the migration's whole point (`MC-A`) is that `.padding` is a
SwiftUI wrapper modifier rather than a CSS `Style` field. Today the `Element`
path is migrated and the `Component` path is not, so `.padding` means two
different things depending on the receiver — and the `Component` meaning is
CSS border-box padding, which disagrees with SwiftUI in three ways at once.

**Evidence.** Probe `swiftui-component-distribution` versus MetalUI, measured
this session (scratch `zzScratchComponentPadding`, `C1`–`C6`):

| case | MetalUI today | SwiftUI |
|---|---|---|
| one-`Text` body, `.padding(20)` | inert — a following 1pt marker stays at x **13** | pads (G5 30x10 → G6 46x26) |
| one-30x10-`Box` body, `.padding(20)` | node becomes **40x40** (the declared 30x10 absorbed into 40 of padding) | **70x50** (G2's per-member shape) |
| `.padding(4).padding(4)` | **30x10**, marker back at 30 — replaced and then absorbed | equals `.padding(8)` (G4 = G2) |

The wrap produces SwiftUI's three answers with no new mechanism: the same
`Style` value, in a `pass.requestNode(style:children:)` around the member.

**Why distribution and not wrapping-the-group.** G2 = G3 = 120x26 says SwiftUI
applies the modifier to **each** member, not around the pair — a wrapping
implementation predicts 96–104, as `CO-U` already recorded and this session
re-measured from source rather than citing.

**Cost if wrong.** ~~`Component` has no production caller (`CO-Y`)~~ — **round 2:
false, and `OM-Z` is the correction.** The demo declares `PreviewToggle:
Component` (`main.swift:918`), used at line 1017 inside the proposal preview.
The blast radius is still tests, but for a checkable reason rather than an
inherited one: `PreviewToggle()` is used **bare**, so no `StyledComponent` is
ever constructed for it and this ruling's change cannot reach it. It rewrites
the expectation of one existing test
(`chainedPaddingReplacesRatherThanAccumulates`, `OM-E`) and moves the readings
of `everyRegisteringSiteAnimatesItsStyle`'s `Component` arm, both named in the
spec's lane 4. If the wrap turned out to disagree with SwiftUI on some shape not
probed — a component whose body is a `Component` — the fix is the same node, one
level in.

---

## OM-E — chained padding accumulates, and a component's ops apply in declaration order

**Ruling.** `.padding(4).padding(4)` equals `.padding(8)` on **both** paths.
`StyledComponent` stores an **ordered** `[ComponentModifierOp]` — `.amend` for
`width`/`height`, `.wrap` for `padding` — applied in the order written, keeping
a "current node" per member. The existing test
`chainedPaddingReplacesRatherThanAccumulates` is **replaced** by
`chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement`.

**Reasoning.** The `Element` path already accumulates, because each `.padding`
appends a layer (measured: `.background.padding(4).padding(4)` puts the leaf at
(8, 8), scratch `A3`). The `Component` path replaces, because `amend` assigns
one `Style` field — and `StyledComponent`'s own doc argues for that by analogy
with `StyledElement.modifying`, which was the right analogy while `.padding`
*was* a `Style` field and stopped being one when `MC-A` landed. Inverting a
documented expectation needs evidence, not preference, so the probe is the
warrant.

Declaration order matters once `.wrap` exists: `.padding(4).width(10)` must
size the padded box to 10 and `.width(10).padding(4)` must size the member to
10 and then pad it to 18. Applying every amend before every wrap (or the
reverse) collapses those two into one answer.

**Evidence.** `swiftui-outer-modifier-order` E1/E2/E3 (28x28, 36x36, 36x36:
`.padding(4).padding(4)` = `.padding(8)`), and
`swiftui-component-distribution` G4 = G2 = 120x26 for the same on a component.

**Round 2 (critic finding 11): the declaration-order half was derived, and now
it is probed — with a caveat the first draft hid.** The accumulation arms
(E1–E3, G4) cannot see order at all: two paddings commute. Arms G13–G16 were
added to `swiftui-component-distribution` and do see it:

| arm | SwiftUI |
|---|---|
| G13 `Pair().padding(4).frame(width: 70)` | outer **148x18**, member `a` at (20, 4), still 30 wide |
| G14 `Pair().frame(width: 70).padding(4)` | outer **164x18**, member `a` at (24, 4), still 30 wide |
| G15 `Solo().padding(4).frame(width: 70)` | outer **70x18**, member at (20, 4) |
| G16 `Solo().frame(width: 70).padding(4)` | outer **78x18**, member at (24, 4) |

So order **is** observable on a custom view, which is the warrant for `ops`
being an ordered list rather than an amend-set plus a wrap-set.

**But MetalUI cannot reproduce SwiftUI's numbers here and must not be written as
if it could.** SwiftUI's `.frame` WRAPS each member, leaving it 30 wide;
MetalUI's `Component.width` AMENDS, overwriting the member's own width — that is
`OM-F`, deliberately unchanged by this task. MetalUI's two answers under lane 4
therefore differ from each other (the property `ops` exists to deliver) while
differing from SwiftUI's member geometry (the property `OM-F` defers to task 4).
The spec's lane-4 test 4 is accordingly re-specified: it pins **MetalUI's own**
two readings, requires them to disagree, and names `OM-F` in its own doc
comment. The earlier sentence "differ the way SwiftUI's nesting does" is
withdrawn — it was a prediction about numbers no arm had taken.

**Cost if wrong.** A caller who wrote `.padding(4).padding(4)` expecting 4 gets
8. No such caller exists in `Sources/`. The old expectation survives in the
record as a superseded measurement rather than being deleted.

---

## OM-F — `Component` `width`/`height` keep today's overwrite, and it is a recorded divergence

**Ruling.** `width`/`height` on a `Component` stay `.amend`, so a caller's
`.width(70)` still overwrites the member's own declared width. Recorded as a
divergence from SwiftUI, pinned wrong on purpose, owned by **task 4**.

**Reasoning.** The brief for this task says not to change frame/width/height
sizing semantics. It is also the right split: SwiftUI's answer is a **wrapping
frame** — the member keeps its own size and is aligned inside the caller's — and
"a frame wraps and aligns" is exactly what task 4 specifies for the legacy path
generally. Making the component case wrap before the element case does would put
two different frame semantics in the tree at once.

**Evidence.** `swiftui-component-distribution` G7: `Pair().frame(width: 70)`
reads outer 148 (70 + 8 + 70) with the members still 30 and 50 wide, centred
(member `a` at x 20 of 0…70). G8: the single-leaf case, 70 outer, member 30 at
x 20. MetalUI, scratch `C6`: `SoloBox().width(70)` makes the member itself 70
wide. `CO-U`'s doc already states the mechanism ("`amend` runs … a plain `=` on
one `Style` field") and gave a 30/50 → 70/70 measurement; this session
re-measured it and measured SwiftUI's side, which `CO-U` had not.

**Cost if wrong.** The divergence stays one release longer. It is pinned by
`aComponentsWidthStillOverwritesItsMembersDeclaredWidth`, so task 4 cannot
close it silently.

---

## OM-G — `clipped()` is a separate modifier from `cornerRadius(_:)`

**Ruling.** `Decoration.clipsContent` and `StyledElement.clipped()` are added.
`cornerRadius(_:)` keeps today's meaning — it rounds this element's own fill and
border and clips nothing. `.cornerRadius(12).clipped()` is the spelling for
SwiftUI's `.cornerRadius(12)`. The clip is pushed in **both** prepaint and
paint, as `ScrollView` does, so hitboxes inside a clipped box are registered
against the clip.

**Reasoning.** SwiftUI's `.cornerRadius` clips content; MetalUI's rounds a fill.
Making `cornerRadius` clip would be more faithful and would change every one of
the demo's sixteen `cornerRadius` call sites in the same commit — a visual
change to production made as a side effect of an audit. The separation costs one
extra modifier at the call site and keeps the demo pixel-identical, which is
what §7's verification asks for.

**Evidence.** `swiftui-border-clip-paint` C1: `red.cornerRadius(12)` reads white
at (1,1) and (3,3) — the **leaf's own colour** is gone at the corner, so the
radius clipped content and did not merely round a fill. E1/E2 show `.clipShape`
behaving identically. F1/F2 show the background covering the padding in both
orders with only the rounding differing.

**Cost if wrong.** A caller who expects `.cornerRadius` to clip gets square
children with no diagnostic. Pinned by `aBareCornerRadiusDoesNotClipTheChildren`
(lane 1, wrong on purpose) so the gap is visible, and the deferral row names
task 11 as the owner of closing it.

---

## OM-H — every order expectation comes from a probe arm, and FIVE orders are not expressible

**Ruling.** The spec's §6 tables are the expectations, each citing its arm. Five
SwiftUI behaviours are **not expressible** on the legacy path and are recorded
rather than approximated (the fourth added in round 2 by `OM-W`, the fifth in
the lane-2 review round by `OM-AH`; the heading and count are corrected here
rather than left to be reconciled):

- `.cornerRadius(r).background(c)` leaving the background square (C3);
- `.cornerRadius(r).border(w)` drawing a square border over rounded content (D1);
- `.opacity(v).background(c)` leaving the background opaque (G4, `OM-N`);
- **`.border(w).cornerRadius(r)` clipping a SQUARE border by the radius, so the
  corner arc's interior is unbordered** (D2 vs M1, `OM-W`) — the row the first
  draft called an agreement.
- **`.opacity(v).opacity(v)` on one view multiplying to `v²`** (G1/G2, `OM-AH`)
  — the row the first draft *also* called an agreement, and the only one of the
  five that is a second write to the SAME field rather than two fields whose
  order is lost.

A fifth candidate was **measured and is not one**: `.allowsHitTesting(false)`
written before rather than after a gesture reads the same in SwiftUI (N1 == N2,
`OM-T`), so MetalUI's inability to tell the two orders apart is agreement.

**Reasoning.** All five are the same mechanism: `background`, `cornerRadius`,
`border` and `opacity` are fields of **one** `Decoration`, so their order
*within one layer* is not observable — and neither is a second write to one of
them. The alternative — making each of them open
a new layer — buys the four cases at the cost of a layout node per paint
modifier (which would not be layout-neutral: a bare `Style()` flex wrapper
becomes the flex item in its parent's line in place of its child) or a
node-less layer kind with no well-defined box. Neither is worth five corner
cases. A caller who needs them writes a `Box` between the two modifiers, which
*is* a layer, and layers do order.

**Evidence.** The arms above.

**Round 2 (critic finding 4): the fourth row was originally filed as an
agreement, and the first draft's own evidence could not have seen otherwise.**
`OM-W` carries the measurement and supersedes the sentence that closed this
ruling — `.border(w).cornerRadius(r)` (D2) is **not** MetalUI's single-emission
answer (M1). The mechanism is identical to the other three, so only the count
and the list changed.

**Cost if wrong.** A caller writing one of the five orders gets the other
answer silently. Each is pinned by a named test that asserts MetalUI's number
and cites the SwiftUI arm it disagrees with.

**Review round (`OM-AH`): the fifth row was the second one filed as an
agreement, which makes the pattern the finding.** Both mistakes have the same
shape — a spec row written from what the MECHANISM could do (`Frame.activeOpacity`
multiplies; `MUIRect` can carry a radius and a border) rather than from what the
two modifiers the row names actually produce together. The rule that follows: a
§6 row may only be filed "same" when MetalUI's answer for **that exact
spelling** has been read off a run, not derived from a helper that is capable of
the behaviour.

---

## OM-I — MetalUI's default hit region is the element's whole frame

**Ruling.** Recorded as a divergence and left alone: every MetalUI element that
registers a hitbox is hittable over its **entire** box, including areas it does
not paint. SwiftUI's default is derived from what the view draws.

**Reasoning.** MetalUI's hitbox is a rect taken from the layout node; there is
no drawn-content geometry anywhere in the frame to derive a shape from, and
building one would mean tracking emitted primitives per element — a paint-time
structure feeding a prepaint-time registry, across the phase boundary the whole
design exists to keep. The practical gap is also small: the cases where
SwiftUI's default bites are stacks with empty space, and those are exactly the
cases where a real caller writes `.contentShape(Rectangle())`, which is
MetalUI's default already.

**Evidence.** `swiftui-content-shape-hit-region` H1 (a 200x200 stack with an
empty middle and an `.onTapGesture` reads centre 0, edge 0) versus H2 (the same
with `.contentShape(Rectangle())` reads 1 / 1). H0 is the control at 1 / 1.

**Cost if wrong.** A MetalUI container with a click handler swallows clicks over
its empty regions where SwiftUI would pass them through — which is also
divergence 16's shape (an `onClick` inside a `ScrollView` swallows the wheel).
Pinned by `metalUIsDefaultHitRegionIsTheElementsWholeFrame`.

---

## OM-J — `contentShape(inset:)` is the deliverable subset, applied at one site

**Ruling.** `Handlers.contentShapeInset: Edges<Pixels>?`, written by
`contentShape(inset:)`, and applied in exactly one place:
`Frame.registerHandlers`, to the bounds it passes to `insertHitbox`. Focus
registration, the `$focus` retention write, the declared `AXNode`, and the
accessibility emission all keep the element's own `bounds`. A **negative** inset
grows the region and is accepted; the result is still intersected with the
active clip by `insertHitbox`, as every hitbox is.

**Reasoning.** SwiftUI's `.contentShape(Rectangle())` is MetalUI's default
(`OM-I`), so shipping that spelling would be an API that compiles and does
nothing — the shape this repo's inert-API discipline refuses. What SwiftUI can
express and MetalUI cannot is a hit region **smaller than the frame**, and in a
rect-only world an inset is the whole of it. The identity case is reachable as
`inset: Pixels(0)` — a parameter value, not a second no-op spelling.

One site because the alternative is four: every conformer calling
`registerHandlers` would have to inset its own bounds, and a conformer that
forgot would be silently wrong, which is the failure `registerHandlers` was
centralised to prevent (`Frame.registerHandlers`' own doc). It also keeps the
inset out of AX and focus by construction rather than by four correct call
sites.

**Evidence.** `swiftui-content-shape-hit-region` H3:
`.contentShape(Rectangle().inset(by: 60))` on the 200x200 stack reads centre 1,
edge 0, against H2's 1 / 1 — so a content shape really can be smaller than the
frame, and the instrument sees the difference.

**Cost if wrong.** If a caller expected the inset to move the accessibility
frame too (SwiftUI has `.contentShape(_:eoFill:)` and a separate
`.accessibility` kind), they get the element's own frame in VoiceOver. Pinned by
`aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration`, and
the kind-parameterised form is deferred to task 12 by name.

---

## OM-K — a padded click target stays hittable in its padding

**Ruling.** `.padding(8).onClick { }` keeps registering at the padded bounds.
Recorded as a divergence from SwiftUI, pinned wrong on purpose.
`contentShape(inset:)` is the opt-out.

**Reasoning.** The MetalUI behaviour follows from `OM-C`: `.onClick` writes the
outermost layer, and every layer registers at its own box. Changing it would
mean a layer's handlers registering at some inner node's bounds, which
contradicts `MC-A`'s "a layer contributes … one hitbox registration" and would
make a padded row unclickable at its edges — the commonest shape in a list.

SwiftUI's own answer is not as far away as P1 alone suggests: a `.background`
declared **before** the gesture makes the padding hittable there too. So the
divergence is confined to a padded, background-less click target, which is a
shape a caller rarely writes and never sees.

**Evidence.** `swiftui-content-shape-hit-region` P1 and P2 (centre 1, edge 0 —
in both orders), P4 (`.padding(80).background.onTapGesture`: centre 1, **edge
1**), P5 (the background after the gesture: edge 0). MetalUI, scratch
`zzScratchPaddingHitRegion`: `.padding(80).onClick` reads centre 1, **edge 1**.

**Cost if wrong.** A caller porting from SwiftUI finds a padded element clicks
where SwiftUI's would not. Pinned by
`aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`.

---

## OM-L — the focus ring is `focusBorder`, resolved through the border chain

**Ruling.** `Decoration.focusBorder` and `Decoration.hoverBorder` join
`border`, and `resolvedBorder` picks `focusBorder ?? hoverBorder ?? border`
with the **same** precedence and the **same** hover/focus selection helper that
`animatedBackground` uses for the three background fields. A focus ring is drawn
in the same `pass.fill` as the background (`OM-O`).

**Reasoning.** "Nothing above the renderer can draw a border" and "the framework
has no focus ring" are the same hole seen twice — `Decoration`'s own doc says so
("A border is the obvious spelling for a hover or focus affordance and it is
unreachable"). One mechanism closes both. Mirroring the background chain rather
than inventing a `focusRing(_:)` modifier means the precedence rule ("focus
outranks hover", already argued in `Decoration.focusBackground`'s doc) is stated
once and shared, so the two chains cannot drift.

The ring is drawn **inside** the element's box, because that is the only border
geometry the renderer has (`OM-B`). AppKit's own focus ring is a halo outside
the control's bounds; MetalUI's is not, and that is a recorded difference rather
than a claim about SwiftUI — SwiftUI exposes no focus-ring drawing for an
arbitrary view at all, so there is nothing to probe. What **was** probed is that
focus does not change layout (`swiftui-outer-modifier-order` L8: `.focusable()`
leaves a 20x20 leaf 20x20), which is the property a ring must not violate.

**Cost if wrong.** If an outset ring turns out to be required for it to look
right, the fix is a second emitted rect at an outset bounds and a second
`Corners` — a paint-only change at one site, `paintDecoration`. It cannot be
decided from a test; it is a human look, and the spec's §7 lane 4 says so.

---

## OM-M — `borderWidth(_:)` is deleted rather than kept or fixed

**Ruling.** Both `borderWidth` overloads are removed from `extension
StyledElement`. `Style.border` stays (the engine reads it) and is reachable only
through `Box(style:)`, on `margin: .auto`'s footing. `CLAUDE.md`'s
declared-but-inert row for it is the integration step's to delete.

**Reasoning.** Three options were on the table.

1. **Keep and document.** Rejected: the property is not inert, it is *worse* —
   it changes layout and paints nothing, so a caller who writes it sees their
   content move and no border appear, with no diagnostic. That is the exact
   shape CLAUDE.md's inert table exists to remove rather than annotate.
2. **Make it paint.** Rejected: it would then be a layout-affecting border,
   where SwiftUI's is layout-neutral (L2). It also needs the resolved-width
   plumbing `Frame.fill` documents (storing resolved edges on `LayoutTree`),
   which is engine work in a task that must not touch the engine.
3. **Delete, and give the name to a paint-only `.border`.** Taken.

**Evidence that deleting is cheap.** `grep -rn borderWidth Sources/` finds only
its own two declarations; the demo does not use it; its only test coverage is
two rows of `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`.

**Cost if wrong.** An out-of-module caller relying on border-box layout padding
loses the spelling. There is none, this is pre-1.0, and `Box(style:)` keeps the
capability. A typecheck guard (plain import — `@testable` cannot demonstrate a
narrowing, taxonomy shape 16) pins the removal.

---

## OM-N — an opacity scope includes the layer's own fill

**Ruling.** `paintDecoration` opens `pass.opacity(decoration.opacity)` **around**
this element's own background/border fill as well as its content. Consequence:
`.background(x).opacity(0.5)` fades the fill (agreeing with SwiftUI) and
`.opacity(0.5).background(x)` fades it too (disagreeing). The disagreement is a
recorded divergence, pinned wrong on purpose.

**Reasoning.** Only one of the two can be right while both modifiers are fields
of one `Decoration` (`OM-H`). `.background(x).opacity(0.5)` — fade a whole
panel, fill included — is the case a caller actually writes; leaving the fill
opaque there would look like a bug at every call site. The reverse order is
rare and has a spelling (`Box { … }.opacity(0.5).background(x)` puts a layer
between them).

**Evidence.** `swiftui-border-clip-paint` G3 (`background(red).opacity(0.5)`
samples rgb(1.00,0.58,0.58) over white — faded) and G4
(`opacity(0.5).background(red)` samples rgb(1.00,0.15,0.00) — the full fill).

**G1/G2 are NOT evidence for this ruling, and this paragraph used to claim they
were** (review round, `OM-AH`). They establish that SwiftUI's opacity multiplies
across two calls **on one view** — 0.58 after one 0.5, 0.80 after two — which
`Frame.activeOpacity` does *not* reproduce for that spelling, because both calls
write this one field. What `Frame.activeOpacity` multiplies is nested *scopes*.
The divergence is `OM-AH`'s; nothing in this ruling rests on it, and the
sentence that read "which is what `Frame.activeOpacity` already does" is struck.

**Cost if wrong.** One order paints differently from SwiftUI. Pinned by
`opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot`.

---

## OM-O — a background and a border are ONE emitted rect

> **SUPERSEDED IN ROUND 2 by `OM-V`, on the critic's finding 3 and a new probe
> arm (B3).** The ruling as written below is kept verbatim because its "Cost if
> wrong" paragraph named the exact defect that then materialised, and because
> the reasoning for *keeping the background emission before the children* still
> holds. **What changed: the BORDER is a second emission, after `content()`.**
> Read `OM-V` for the current rule.

**Ruling.** `paintDecoration` emits at most one `MUIRect` per element per layer:
none when neither a background nor a border resolves; one carrying both
otherwise, with `color: .transparent` when there is a border and no background.

**Reasoning.** `MUIRect` already carries `background`, `borderColor`,
`borderWidths` and `cornerRadii` — the fragment shader draws a bordered rounded
rect in one instance, which the M0 demo proved end to end. Emitting two would
double the primitive count of every bordered element for nothing, and the
renderer's per-frame budget is measured in rects (`Frame.fill`'s own doc).
Keeping the "no decoration, no rect" case is what stops an ordinary `Box`
becoming a primitive.

**Cost if wrong.** If a future border needs to paint *over* children (SwiftUI's
`.border` is an overlay, and D1 shows it drawn over rounded content), one
emission before the children cannot do it. Today MetalUI's border is inside the
box and its children are inside the box too, so a wide border would be painted
under a child that covers it. Recorded here rather than left to be found; the
fix is a second emission after `content()` and it is a one-line change inside
the one helper.

---

## OM-P — two helpers, four sites, and a guard per site

**Ruling.** `paintDecoration` (paint) and `registerAndScope` (prepaint) are the
only places the new fields are read. The four sites are `Box`, `Stack`, `Text`
and `ModifiedElement` (outermost layer plus each inner layer). Each phase's
per-site guard is table-driven with one arm per site:
`everyDecorationPaintingSiteDrawsItsBorder`,
`everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain`,
`everyHandlerRegisteringSiteHonoursAllowsHitTesting`.

**Reasoning.** This repo has the measurement already: the
`focusBackground`/`hoverBackground` chain lived in `Box.paint` alone for a
milestone, so both modifiers compiled on `Stack` and `Text` and painted nothing,
and neither the per-site animation guard (whose arms declare no `onClick`) nor
the pointer-state tests (whose fixtures are all `Box`) could see it —
`BackgroundChainTests.swift`'s header records exactly that. Five fields added at
one site would reproduce it five times. One helper per phase makes the omission
a missing **call**, which a per-site arm can see.

`ModifiedElement.paint` must become a nested recursion rather than a loop,
because an opacity and a clip are scopes: the outermost layer's scope has to
contain the inner layers' emissions. `prepaintLayer` is already written that way
and says why in its own doc.

**Cost if wrong.** A site that skips its helper is silently unanimated /
unbordered / unclipped, with no diagnostic — this framework's most-recorded
failure shape. The two guards are the answer, and each must be shown to redden
when the call is dropped at exactly one site.

---

## OM-Q — nothing new contributes a layout node, and the goldens must not move

**Ruling.** Every modifier added by this task is paint-only or prepaint-only.
`find Tests -name "*.json" | wc -l` stays **97** and no golden's content changes
(`git diff --stat c4b5853 -- Tests` lists no `.json`). The only new layout nodes
in the whole task are lane 4's per-member padding wrappers, which exist only
under a **modified** `Component` — and the demo's one `Component`,
`PreviewToggle`, is used bare (`OM-Z`; round 2's correction to "no production
caller"). No fixture builds a `Component` at all.

**Reasoning.** CLAUDE.md: "Goldens must not move on any milestone that does not
touch `Sources/MetalUILayout/`; a moved golden means something reached the
engine." This task touches no file in `MetalUILayout`. Stating the rule as a
ruling rather than a constraint makes the lane-4 exception explicit — a
`Component` padding wrapper IS a new node, and the reason it cannot move a
golden is that no fixture and no demo builds a `Component`.

**Cost if wrong.** A moved golden means an outer modifier reached the engine,
which would falsify the layout-neutrality half of the matrix. It fails loudly.

---

## OM-R — what is deliberately not delivered

Listed so a green run of this track is not read as covering it. The spec's §9
carries the same table with owners.

| item | why not |
|---|---|
| legacy `.overlay` | `ModifiedElement` is flat and holds one subtree; a second needs a second generic parameter. Task 6/7 |
| animating the five new `Decoration` fields | a second animated colour needs an eighth reserved retention slot beside `$anim-color`, and the paint-phase helper's shape. Pinned snapping by `theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate`. Task 13 |
| `.contentShape` with a non-rect shape, or a `kind:` | `Hitbox.bounds` is a rect. Task 12 |
| `.cornerRadius` clipping by default (SwiftUI C1) | it would repaint the demo's sixteen call sites. Task 11 |
| `Component` `background`/`onClick`/`focusable` | `CO-U`'s mechanism, unchanged |
| ~~`MC-G` hole 5~~ | **withdrawn in round 2 (critic finding 6): hole 5 is THIS task's, it is closed here, and `OM-Z` is the ruling.** The modifier-composition decisions doc assigns it to task 5 by name; the first draft moved it to task 7 without saying so |
| unifying with `ModifiedContent` | two engines until task 7 |
| divergence NUMBERS for this task's rows | `CLAUDE.md` and `docs/record/04-divergences.md` belong to the integration step. **Round 2 (critic finding 5): the highest number allocated today is 34, not 29** — `grep -oE "^\| [0-9]+ \|" docs/record/04-divergences.md` runs 20…34 under "2026-09-15: divergences 20–34 (tasks 3, 9 and 12, integrated)". **Next free: 35.** The wrong figure appeared three times (here, spec §9, record §15) and is corrected in all three |
| divergence-15's one-line fix | **withdrawn in round 2: taken here.** `.clipped()` makes it reachable from every element rather than only from a nested `ScrollView`. `OM-U` |

---

## OM-S — method: what was measured, and what was only read

**Measured this session.**

- All four probes, both run forms, with positive controls, output recorded in
  each header: `swiftui-outer-modifier-order` (controls C0–C2, layout-neutrality
  L1–L9, order A/B/D, accumulation E, clip F), `swiftui-border-clip-paint`
  (controls K0/K1, border B, radius C, radius×border D, clipShape E, opacity G,
  padding F), `swiftui-content-shape-hit-region` (control H0, default H1,
  contentShape H2/H3, padding P1–P5, allowsHitTesting N1),
  `swiftui-component-distribution` (controls G0/G1/C2, padding G2–G6, frame
  G7/G8, background G9).
- MetalUI's current behaviour, by four scratch tests created, run under
  `--build-system native --no-parallel --filter`, and deleted:
  `zzScratchBackgroundOrder` (A1–A3), `zzScratchPaddingHitRegion` (P1),
  `zzScratchComponentPadding` (C1–C6), `zzScratchTextPadding` (T1–T4). The
  readings are in record §15.
- That `borderWidth` has no production caller, that no type conforms to both
  `StyledElement` and `ProposalElementGroup`, and that the display is unlocked
  on this machine — each by a command whose output is in record §15.

**Read, not measured** (each is a design input that the implementing lane must
re-check rather than trust):

- that `Frame.fill`'s `borderColor`/`borderWidths` parameters reach the shader —
  read from `Frame.fill` and `NativeModifiedContent.paint`; the M0 demo is cited
  by `Frame.fill`'s doc as the end-to-end proof, and no run in this session
  exercised it. **Lane 2's test 1 is that proof**, and round 2 re-specifies it
  to read PIXELS off the fake surface's texture rather than to re-read
  `MUIRect.borderWidths`, which is the field it was handed;
- ~~that the demo declares no `Component`~~ — **false, and `OM-AC` is the
  correction.** See `OM-Z`.

**Baseline, re-taken in this worktree at `c4b5853`** (`swift build
--build-system native` first, then `swift test --build-system native
--no-parallel`): `Test run with 1226 tests in 1 suite passed after 30.231
seconds`, 0 `error:`, 0 `warning:`; `find Tests -name "*.json" | wc -l` = **97**;
`grep -c canTypecheck` over the nine guard files reads 19 + 10 + 5 + 3 + 3 + 2 +
6 + 6 + 8 = 62, **less the one comment hit in `UnitSafetyTests` = 61 guards**.
All three agree with record §13's post-integration figures.

---

# Design review round 2 — rulings OM-T … OM-AC

Seventeen critic findings against the design commit `981f78b`. Each is applied
or explicitly rejected below; the disposition table is at the very end. Three
probes were extended and re-run in this round, and every new claim below cites
an arm taken in this session.

---

## OM-T — `allowsHitTesting(false)` disables the receiver's own hitbox, and the order is not observable in SwiftUI either

**Ruling.** `registerAndScope` opens the disabled scope **before** the
receiver's own `registerHandlers`, not only around `content()`:

```swift
if handlers.allowsHitTesting {
    pass.registerHandlers(handlers, at: bounds, id: id, accessibleText:, synthesizesAccessibility:)
    …content, inside the clip scope when clipsContent…
} else {
    pass.allowsHitTesting(false) {
        pass.registerHandlers(handlers, at: bounds, id: id, accessibleText:, synthesizesAccessibility:)
        …content, inside the clip scope when clipsContent…
    }
}
```

The receiver's own registration stays **inside** the scope rather than being
skipped, because `Frame.registerHandlers` gates only the hitbox insert on
`hitTestingDisabledDepth == 0` (`Frame.swift:863`) — focus registration, the
`$focus` retention write, the `focusedElementProducedThisFrame` signal, the
declared `AXNode` and the accessibility record all sit **above** that gate and
must keep firing. So the scope removes the pointer target and nothing else,
which is precisely what the spec's §6.3 row `N1` and lane 3's test name already
claimed.

**Reasoning.** The first draft ordered it "register, then scope the children",
which cannot produce `N1` at all: `Box().onClick { }.allowsHitTesting(false)`
writes **one** `Handlers` — both modifiers land on the outermost `ModifierLayer`
(`ModifiedElement.swift:110-114`) — so the receiver's own registration, made
outside the scope, would still insert an opaque hitbox. That is the common
spelling, not a corner, and the proposal path already gets it right
(`NativeModifiedContent.prepaint` wraps the whole child including its
`OnTapModifier`), so the two paths would have disagreed on a spelling the demo
ships live (`MetalUIDemo/main.swift:1019-1023`).

**Evidence.** `swiftui-content-shape-hit-region`:

- **N1** `Color.blue.onTapGesture { }.allowsHitTesting(false)` — centre **0**,
  edge **0**. The receiver's own gesture is dead. (This arm was in the first
  recording; the first draft's mechanism contradicted it.)
- **N2**, added this round, `Color.blue.allowsHitTesting(false)
  .onTapGesture { }` — centre **0**, edge **0** as well.

**N2 is why this is one clause and not two.** `.allowsHitTesting` is a wrapping
modifier in SwiftUI, so a gesture written outside it *could* have survived; it
does not, because the modifier empties the subtree's hit region and the later
gesture has nothing to attach to. MetalUI's legacy path stores both on one
`Handlers` and so cannot tell the two orders apart — here that is **agreement**,
and it removes a row that would otherwise have joined `OM-H`'s not-expressible
list. Recorded because a reader will assume the opposite from `OM-H`'s
neighbours.

**Cost if wrong.** If the scope were somehow to reach focus, a
`.focusable().allowsHitTesting(false)` element would stop answering the
keyboard, which is the half SwiftUI keeps. Lane 3's test 1 carries both halves
and its second mutation — extending the scope to the focus registry — must
redden the keyboard half specifically.

---

## OM-U — `.clipped()` takes divergence 15's one-line fix rather than inheriting it

**Ruling.** `Frame.pushClip` adds `activeOffset` to the incoming `bounds` before
intersecting:

```swift
let translated = Bounds(origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                                      y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
                        size: bounds.size)
let (clip, clipRadii) = Self.intersect(activeClip, radii: activeClipRadii, translated, radii: radii)
```

This closes divergence 15. `Tests/MetalUITests/NestedClipTests.swift`'s
`aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` — today a
pinned-wrong-on-purpose assertion of the defect — is **inverted** in the same
commit, and the divergence row's retirement is carried to the integration step
(which owns `CLAUDE.md` and `docs/record/04-divergences.md`).

**Reasoning.** The first draft put `pass.clipped(to: bounds, …)` on every
`Box`/`Stack`/`Text`/`ModifierLayer` and never mentioned that `pushClip`
intersects untranslated. That is not a pre-existing bug this task merely fails
to fix — it is a **severity change this task causes**. Today the only caller is
`ScrollView`, which is why the divergence reads as "a `ScrollView` inside a
scrolled `ScrollView`". After lane 2, any `.clipped()` element anywhere inside a
scrolled `ScrollView` clips at its *unscrolled* rect and, once scrolled past the
viewport, gets an empty mask and draws nothing — a `.clipped()` row in the
demo's 500-row list would blank itself on the first scroll. Shipping that under
a new modifier, annotated, is exactly the shape CLAUDE.md's inert table exists
to remove.

**Why it is safe to take here, against the "deferred to a paint milestone"
deferral.** Record §04's own analysis of the fix (lines 560–561): "the added
term is `+ activeOffset`, so the fix is a **no-op wherever `activeOffset == 0`**
— which is every non-nested `ScrollView` in existence". The demo has no nested
scroller, so the fix cannot move a demo pixel, which lane 4's offscreen
comparison then measures rather than assumes. It is also outside
`Sources/MetalUILayout/`, so no golden can move (`OM-Q`).

**Cost if wrong.** If some caller depended on the untranslated intersection, a
clip would shrink where it used to pass everything. The existing pins are
`nestedClipsIntersectRatherThanReplace`,
`aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`,
`aHitboxInsideAScrolledRegionIsRecordedWhereItPaints` and
`aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`; all four must stay
green, and lane 2's mutation table must name them. If the fix turns out to cost
more than a line, the fallback is the critic's alternative — a ruling, a
`aClippedBoxInsideAScrolledScrollViewClipsAtTheWrongRect` pinned wrong on
purpose, and a divergence row — and the lane records which was taken.

---

## OM-V — the border is a SECOND emission, drawn AFTER the children

**Ruling.** Supersedes `OM-O`. `paintDecoration` emits:

1. the **background** rect before `content()` — `pass.fill(bounds, color:
   resolvedBackground, cornerRadii:)`, with no border, and **not at all** when
   no background resolves;
2. `content()`;
3. the **border** rect after `content()` — `pass.fill(bounds, color:
   .transparent, cornerRadii:, borderColor:, borderWidths:)`, only when a border
   resolves.

An undecorated element still emits nothing. A background-only element still
emits exactly one rect (the overwhelmingly common case, and the whole of the
demo). A bordered element costs two.

**Reasoning.** SwiftUI's `.border` is an **overlay**, and MetalUI's children
live inside the same box the border is drawn inside, so one emission before the
children means a child that fills the box hides the border completely. The first
draft filed this in `OM-O`'s "Cost if wrong" paragraph and nowhere else — not in
the matrix, not in the order table, not in the divergence list, not in a test.

**It is fatal specifically for the focus ring**, which is this task's deliverable
(`OM-L`). The shape a caller writes is `Box { content }.focusBorder(.accent,
width: 2)`; if `content` fills the box — a `Text` with a background, a `Row`
stretched by `EP-8` — the ring is invisible, with no diagnostic, on the exact
call it was added for. A focus affordance that is sometimes not drawn is worse
than none.

**Evidence.** `swiftui-border-clip-paint` **B3**, added this round:
`Color.clear.frame(40, 40).overlay(red).border(blue, width: 4)` reads the
**border colour** at corner (1,1) and (3,3) with the red child at arc(5,5),
arc(7,7), in(6,6) and the centre. A filling child does not hide SwiftUI's
border. B1 shows the same shape with the leaf as its own content, and B2 shows
the border over a transparent leaf, so the three together separate "border" from
"fill" unambiguously.

**Cost if wrong.** Every bordered element costs one extra `MUIRect`. `OM-O`'s
budget argument is real but small: `grep -c cornerRadius Sources/MetalUIDemo` is
16 and the demo declares no border at all, so today the cost is zero rects and
after this task it is one per element that opts in. The alternative — a caller
writing `Stack { content; Box().border(…) }` by hand — reintroduces the
per-site-omission failure `OM-P` exists to prevent. Lane 2's test 2 is
re-specified accordingly: `aBackgroundIsEmittedBeforeTheChildrenAndABorderAfter`,
asserting the order of `Scene.rects` around the child's rect, mutated by
swapping the two emissions.

---

## OM-W — `.border(w).cornerRadius(r)` is a FOURTH order that is not expressible

**Ruling.** Joins `OM-H`'s list. MetalUI's rounded bordered rect follows the
arc; SwiftUI's `.border` clipped by a later radius does not. Pinned wrong on
purpose by `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot`,
which asserts MetalUI's emitted `cornerRadii`/`borderWidths` pair and cites arm
M1.

**Reasoning — and this is a methodology finding as much as a behaviour one.**
The first draft's §6.2 called this row "same as MetalUI's one-emission answer".
It was not measured; it was **inferred from five sample points that all agree**.
The corner (1,1) and (3,3) are outside the arc (white in both), in(6,6) and the
centre are deep inside (fill in both), and the edge midpoint is border in both.
Every point the instrument had was one the two answers share. That is taxonomy
shape 15 — arms that agree by construction — reached through a probe rather than
a test.

**Evidence.** Two sample points inside the corner arc, and a reference arm, both
added this round:

```
D2 red.border(blue, 4).cornerRadius(12) : arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00)
M1 RoundedRect(12) fill+strokeBorder 4  : arc(5,5)=rgb(0.02,0.20,1.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(0.28,0.16,0.83)
```

`M1` is not another SwiftUI question — it is the MetalUI equivalent written in
SwiftUI, one rounded rect carrying a fill, a radius and an inset border, which
is exactly what `paintDecoration`'s emission is. At arc(5,5) SwiftUI reads the
**fill** and the single rounded rect reads the **border**; in(6,6) differs too
(fill versus the antialiased blend across M1's inner edge). SwiftUI clips a
*square* border by the radius, leaving the arc's interior unbordered; a rounded
stroke follows the arc.

**Cost if wrong.** A caller writing `.border(…).cornerRadius(…)` and expecting
SwiftUI's clipped-square border gets a rounded stroke. It is the more useful of
the two answers and the one every design system draws, so the divergence is
recorded rather than chased. The general escape is `OM-H`'s: put a `Box` between
them.

---

## OM-X — `registerAndScope` carries the accessibility payload, and the matrix instrument gets mechanism-specific witnesses

**Ruling, part 1 — the signature.**

```swift
@MainActor
func registerAndScope<R>(_ handlers: Handlers, _ decoration: Decoration,
                         at bounds: Bounds<Pixels>, for id: GlobalElementID,
                         pass: inout PrepaintPass,
                         accessibleText: String? = nil,
                         synthesizesAccessibility: Bool = true,
                         content: () -> R) -> R
```

and it forwards both to `PrepaintPass`'s five-argument internal overload.
`Text.prepaint` passes `accessibleText: string.isEmpty ? nil : string,
synthesizesAccessibility: true`, exactly as it does today
(`Text.swift:311-313`).

**Reasoning.** The first draft's helper forwarded only the public
three-argument form while naming `Text.prepaint` as one of its four call sites.
Routing `Text` through it as written deletes every text leaf's accessibility
string, which is `AB-F`/`AB-Y`'s whole subject — a silent, total regression of
another track's deliverable, introduced by a refactor whose stated purpose was
to stop per-site omissions. The defaults keep `Box`, `Stack` and
`ModifiedElement` writing what they write today.

**Lane 3's mutation table must name the tests that catch it.** Dropping the two
parameters must redden the `Text` arms of `aTextLeafPublishesItsStringAsAValue`
and `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, plus the
`Text` arms of the environment track's `D2`; the lane records the actual names
and counts from the red run rather than these, which are read from source.

**Ruling, part 2 — the matrix instrument.** Lane 1's
`everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` measures a
**five**-tuple, not a triple:

`(nodeDelta, outerSizeDelta, rectDelta, hitRegionDelta, hitCountAtEdge)`

— the last two read from `Window.lastHitboxes` (the registered region for the
row's id, and whether a synthesized click at the box's edge reaches it). And the
derivation is **not** "read the kind off the tuple": each kind is asserted
against its own mechanism-specific witness, because the tuple alone cannot
separate them.

**Reasoning.** The critic's finding 8 is right and its counterexamples are all
real: "self" (`.id()`), "prepaint-only" (`onClick`) and a genuinely inert
modifier all read `(0, 0, 0)`; `hidden()` reads a non-zero `outerDelta` and
would classify as "wraps"; pre-deletion `borderWidth` on a sized box reads
`(0, 0, 0)` — the very API this audit exists to expose. An instrument that
cannot see the thing the audit is for is the audit agreeing with itself.

The witnesses:

| kind | witness |
|---|---|
| **wraps** | `nodeDelta > 0` **and** `outerSizeDelta > 0` |
| **self** | `nodeDelta == 0`, and the written field differs between "declared" and "not declared" on the **outermost** `ModifierLayer` — the same reflection `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` uses |
| **paint-only** | `nodeDelta == 0 && outerSizeDelta == 0` **and** `rectDelta != 0` (a rect appears, disappears, or changes a field) |
| **prepaint-only** | `nodeDelta == 0 && outerSizeDelta == 0 && rectDelta == 0` **and** `hitRegionDelta != 0` or `hitCountAtEdge` moves |
| **distributes** | the measurement is repeated on a two-member `Component` and the delta appears **twice**, once per member |

Every row still `#require`s its two arms to disagree before any kind is
compared, and **the kind derivation itself carries that requirement** — a row
whose "declared" and "not declared" measurements are equal fails as a broken
instrument rather than passing as "inert".

**Cost if wrong.** A modifier filed under the wrong kind in a table that cannot
tell the kinds apart is a documentation artefact wearing a test's name. The
per-kind witnesses are more code than one tuple comparison; that is the price of
the instrument being able to fail.

---

## OM-Y — the new public state is validated where it is WRITTEN, not only where it is initialised

**Ruling.** `BorderStyle.widths` is `public private(set)`, with the validating
`init`s and a `withWidths(_:) -> BorderStyle` builder as the only ways to set
it. `Decoration.opacity` is likewise `public private(set)` with a validating
`setOpacity(_:)`; `Decoration`'s explicit public memberwise `init`
(`Box.swift:220`) gains all five new parameters and validates the two that need
it.

**Reasoning.** The first draft put the preconditions on `BorderStyle.init` and
`StyledElement.opacity(_:)` while leaving both fields public stored `var`s, and
`Decoration` is public and reachable through `Box(style:decoration:)`. So
`var d = Decoration(); d.opacity = 2` and `var b = BorderStyle(.accent, width:
px(1)); b.widths = Edges(all: px(-5))` both reach paint unchecked. Two exit
tests would then have pinned a door beside an open window — the shape this
repo's trap discipline exists to prevent, arrived at by writing the trap at the
modifier "so the failure names the call site" and forgetting that the field is
the other call site.

**Ruling, part 2 — lane 2 test 14's arm must use a value ABOVE 1.**
`PaintPass.opacity` already carries `precondition((0...1).contains(value))`
(`Passes.swift:639`). An exit test that paints with a **negative** opacity
aborts in the pass whether or not `StyledElement.opacity`'s own precondition is
there, so the mutation "remove the modifier's precondition" reddens nothing —
the test passes for the wrong reason over half its input range. A value `> 1`
does not have that problem, because `paintDecoration` opens the opacity scope
only when the value is **below** 1, so an unvalidated `1.5` never reaches
`PaintPass.opacity` at all and the mutation is visible. **The lane records which
value was run.** The same reasoning is why the negative-border-width test is
sound as written: nothing downstream of `BorderStyle` validates a width.

**Cost if wrong.** A negative width reaches `max(halfSize - border, 0.0)` in the
fragment shader (`shaders.metal:129-133`) and produces an inner rect *larger*
than the outer one, with no diagnostic anywhere above it; an out-of-range
opacity either traps far from its call site or multiplies the frame's opacity
above 1. Both are pinned by exit tests, and after this ruling both are pinned at
every public write.

---

## OM-Z — `Component` distribution over a proposal body: hole 5 is closed here, by a trap that already exists

**Ruling.** `MC-G` hole 5 — "a legacy style modifier on a proposal `Component`
compiles" — is **this task's**, as the modifier-composition decisions doc
assigns it (`2026-09-15-modifier-composition-decisions.md:1679`, owner "task
5"), and lane 4 closes it rather than deferring it. Both
`ComponentModifierOp` kinds trap on a native top-level node:

- `.amend` reaches `LayoutTree.setStyle`, which traps on a native node
  (`LayoutTree.swift:465-471`, ruling `SA-G`) — today's behaviour, unchanged;
- `.wrap` reaches `LayoutTree.newNode(style:children:)`, which **also already
  traps**: `for child in children { precondition(nativeNodes[slot(child)] ==
  nil, "legacy layout node given a native child — a proposal subtree cannot sit
  under a CSS container (SA-G)") }` (`LayoutTree.swift:130-136`).

Lane 4 adds one exit test for the `.wrap` route —
`aPaddingModifierOnAProposalComponentTraps` — beside the existing `.amend` pin.
No new precondition is written.

**Round 2 correction to the critic (finding 6, second half): the claim that
`newNode(style:children:)` does not trap is FALSE.** It traps, the message names
`SA-G`, and the trap is already pinned by an exit test in
`Tests/MetalUILayoutTests/NativeBoundaryTrapTests.swift` (the arm at its line
42: "A native node handed to a legacy `newNode` as a child traps at
registration"). So lane 4 does **not** silently build a legacy flex node around
a native node; it swaps one named `SA-G` trap for another. The finding's first
half is upheld in full and is what follows.

**Round 2 correction to this track (finding 6, first half): "the demo declares
no `Component`" is FALSE, and it was a citation rather than a measurement.**
`Sources/MetalUIDemo/main.swift:918` declares `private struct PreviewToggle:
Component`, used at line 1017 inside `nativeLayoutPreviewContent()` — inside the
very proposal preview lane 4's verification requires to be pixel-identical. The
first draft cited `CO-Y`'s "no production caller yet", which is a claim about a
milestone that has since been overtaken by task 3's preview.

**So the zero-pixel expectation is re-derived on the right premise.**
`PreviewToggle()` is used **bare** — no modifier — so no `StyledComponent` is
ever constructed for it, so lane 4, which changes `StyledComponent` alone,
cannot reach it. That is a statement about a call site, checkable by grep and
measured by the comparison itself, rather than a statement about the codebase
having no components. Lane 4 states it that way and reports the grep.

**Cost if wrong.** If some other `Component` call site acquires a modifier
before this lands, the comparison reports a non-zero pixel count and the lane
explains it rather than discovering it later. If `PreviewToggle` ever gains a
`.padding`, it traps loudly at `SA-G` — which is hole 5 behaving as designed and
not a regression.

---

## OM-AA — opacity is path-dependent, and `Deferred` does not reset it

**Ruling, part (a).** `.background(x).opacity(0.5)` and
`.opacity(0.5).background(x)` both fade the fill on the **legacy** path
(`OM-N`), and on the **proposal** path they already differ — `.opacity` is its
own `ModifiedContent` layer there, so the second order leaves the fill opaque,
which is SwiftUI's answer and ships today. Recorded as a **cross-path**
inconsistency in its own right: the same-looking chain answers differently
depending on which element system the caller is on. It is not fixed here — task
7's unification is the fix — and `OM-N`'s divergence row gains the sentence
"…and the proposal path, which agrees with SwiftUI, disagrees with the legacy
path".

**Reasoning.** `OM-N` filed only the SwiftUI disagreement. A caller porting a
subtree between the two paths — which is what tasks 6 and 7 are for — would find
a fade appear or vanish with no modifier changed. Two paths disagreeing with
each other is a different and more dangerous fact than one path disagreeing with
SwiftUI, and it belongs in the audit the plan asked for.

**Ruling, part (b).** `Deferred` resets clip and scroll offset (`AP-I`) and
**does not reset opacity**: `Frame.pushLayer` and `pushRootClip`
(`Frame.swift:367, 416`) leave `opacityStack` untouched. That stays true, and
the answer is pinned rather than changed:
`aDeferredPortalInsideAFadedSubtreeIsStillFaded` (lane 2).

**Reasoning for keeping it.** The moment `.opacity` exists on the legacy path,
`AP-I`'s two-member reset acquires a newly reachable third candidate, so the
answer has to be chosen deliberately. Keeping today's behaviour is right for
two reasons. First, the mechanism: `Deferred`'s resets exist because a portal
must not inherit *geometry* it has escaped — a modal must not slide with the
content it covers. Opacity is not geometry; a subtree faded to 0.5 with a
tooltip inside it reads as one faded thing, which is what a caller writing the
fade meant. Second, the cost of the alternative is unbounded and unprobed:
SwiftUI has no `Deferred`, so there is nothing to measure, and a reset would
make a scrim inside a faded panel jump to full opacity with no spelling to get
the other answer back. Zero code, one test, recorded reasoning.

**Cost if wrong.** A modal presented from inside a faded subtree is faded. The
escape, if it is ever wanted, is to declare the `Deferred` outside the faded
element — which is a structural change, not a modifier, and the test names that
as the workaround.

---

## OM-AB — `contentShape(inset:)` with no click handler registers nothing, and says so

**Ruling.** `contentShape(inset:)`'s doc comment states that it configures a hit
region and does not create one: `Frame.registerHandlers` inserts a hitbox only
when `handlers.isPointerTarget` (`onClick != nil`), so
`Box().contentShape(inset: Pixels(20))` with no `onClick` compiles, writes the
field, and registers nothing. Pinned by
`aContentShapeWithoutAClickHandlerRegistersNothing` (lane 3).

**Reasoning.** `OM-J` argued at length that shipping `.contentShape(Rectangle())`
would be an API that compiles and does nothing, and then shipped a modifier with
its own inert configuration undocumented. The repo already treats the identical
shape as worth a named test one field over —
`hoverBackgroundWithoutAClickHandlerNeverPaints` — so the precedent is set and
the cost is a paragraph and an assertion.

**Why it is documented rather than made non-inert.** Making it register a hitbox
on its own would turn a hit-region *modifier* into a hit-region *creator*,
which is neither SwiftUI's behaviour (`.contentShape` on a gesture-less view is
inert there too, for the same reason: nothing is listening) nor expressible
without deciding what an opaque, handler-less hitbox means for
`topmostOpaqueHitbox` ranking. The honest answer is that this modifier
configures something another modifier creates, and saying so is the fix.

**Cost if wrong.** A caller writes `.contentShape(inset:)` expecting a hit
region and gets none. One test and one paragraph; the failure is now named.

---

## OM-AC — method, round 2: what was re-measured, what was corrected, and what the verification rests on

**Corrections to `OM-S`'s two "read, not measured" entries.**

1. "The demo declares no `Component`" — **false**, corrected by `OM-Z` and by
   `grep -n "Component" Sources/MetalUIDemo/main.swift`. It was an inherited
   citation (`CO-Y`) presented as a fact about the current tree. The lesson is
   the practices doc's: a claim copied from another milestone's ruling is read,
   not measured, however confident the ruling was.
2. "`Frame.fill`'s border parameters reach the shader" — still read, and lane
   2's test 1 is re-specified so that it is the proof rather than a re-read of
   the field: `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout` must
   sample **pixels** from the fake surface's readable texture
   (`Tests/MetalUITests/Fakes.swift:20-63` already renders to one), not assert
   `MUIRect.borderWidths`, which is the value the test itself handed in.

**The display-lock reading: the critic's correction is REJECTED on its facts and
APPLIED on its substance.**

- Re-run in this session: `ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked`
  reads `<false/>` — unlocked, agreeing with the first draft's reading and not
  with the critic's `<true/>`.
- Both readings are true of their moment. The conclusion is that **the reading is
  volatile and is not a property of the machine**, so recording it in a design
  document as a standing fact was the error, whichever value it held.
- Applied: the **offscreen comparison is the primary evidence**, not a fallback;
  the real-window capture is conditional and **the lock state is re-taken at
  lane-4 time and reported with its timestamp**. The unqualified sentence "the
  display is unlocked on this machine" is removed from the spec and the record.

**Measured this round** (all in this worktree, at `c4b5853`, `git status
--short` clean throughout):

| run | result |
|---|---|
| `swiftui-border-clip-paint`, both forms, +2 sample points, +B3, +M1 | byte-identical stdout, exit 0, compile and run stderr both 0 bytes |
| `swiftui-component-distribution`, both forms, +G10–G12, +G13–G16 | byte-identical, exit 0, stderr 0 bytes |
| `swiftui-content-shape-hit-region`, both forms, +N2 | byte-identical, exit 0, stderr 0 bytes |
| `swiftui-outer-modifier-order`, unchanged, re-run | exit 0, stderr 0 bytes; stdout still matches its header line for line |
| every recorded header line re-checked against live stdout, all four probes | complete, no drift |
| `grep -oE "^\| [0-9]+ \|" docs/record/04-divergences.md` | 20…**34** |
| `grep -n "Component" Sources/MetalUIDemo/main.swift` | `918: private struct PreviewToggle: Component` |
| `LayoutTree.newNode`'s native-child precondition, and its existing exit-test pin | present (`LayoutTree.swift:130-136`; `NativeBoundaryTrapTests.swift:42`) |
| `Frame.registerHandlers`' gate placement (hitbox gated, focus/AX not) | `Frame.swift:863` below the focus block |
| `ioreg … IOConsoleLocked` | `<false/>` |

**Still read, not measured, and the implementing lane must re-check:** that
`pushClip`'s one-line fix is genuinely one line and genuinely a no-op at
`activeOffset == 0` (`OM-U` — lane 2 measures it by keeping four named tests
green and by the demo comparison); and that no site other than the four named
calls `registerHandlers` in a way `registerAndScope` would bypass (`grep -rn
"registerHandlers(" Sources` at lane-3 time, not at design time).

---

## OM-AD — the `distributes` witness is a member's SIZE, and an order test needs a TWO-layer chain

**Ruling, part 1.** `OM-X`'s witness for `distributes` — "the measurement is
repeated on a two-member `Component` and the delta appears **twice**, once per
member" — is **replaced** by: each member's own **size** must change, all
`memberCount` of them. `Observation` carries `rectSizes` beside `rects`, and the
`distributes` arm of
`everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` reads that.

**Reasoning, measured.** A component's top-level nodes sit in one flex line, so
growing member 0 **pushes member 1 sideways**. With the whole rect compared, a
`StyledComponent.requestGroupLayout` that amended only `nodes.prefix(1)` still
moved member 1's rect — its origin — and the mutation **reddened nothing at
all** on either `Component` row. A delta "appearing twice" is therefore not
evidence that the modifier reached twice; what a member's *size* records is what
the modifier did to it, and what its *position* records is what its siblings did
to it. After the change the same mutation reddens both rows, on member 1's
unchanged `50.0x20.0`.

This is the taxonomy's shape-12 hazard read sideways: the second member's
movement was produced by the code under test, so the witness was reading the
mutation's own side effect and calling it the effect.

**Ruling, part 2.** Every order test whose named mutation lives in
`ModifiedElement`'s per-layer recursion must use a **two-layer** chain, and the
lane-1 table's "red before?" column is amended to say so.

**Reasoning, measured.** `Box(20x20).padding(8).background(.accent)` and
`Box(20x20).background(.accent).padding(8)` are both **one** `ModifierLayer`
with `inner` empty. `ModifiedElement.paint`'s loop over the inner layers and
`prepaintLayerBody`'s recursion therefore never run, and the mutation the spec's
lane-1 table names for test 2 by its own source line — filling the outermost
decoration at `pass.bounds(of: layout.inner[0].node)` instead of `bounds` —
reddened nothing. The same held of the hit-testing test: `.padding(80).onClick`
and `.onClick.padding(80)` are one layer each, so the layer-to-bounds pairing
had nothing to get wrong. Taxonomy shape 2, fixtures too shallow to distinguish
two models.

The arms added are probe-backed rather than invented: `.padding(4).padding(4)
.background` is A1 reached through E1 (the outermost layer filled, `(0,0)
36x36`) and `.padding(8).background.padding(4)` is probe arm **A3** exactly
(`44x44` outer, the inner layer's fill at `(4,4) 36x36`). The hit-testing arm is
`.padding(40).onClick.padding(40)`, whose handler sits on the inner layer's
100x100 box at `(40, 40)`, so `(50, 50)` is inside it and `(5, 5)` is not.

**Cost if wrong.** Both instruments were green, on true claims, and could not
have gone red for the defects they were written for — the exact shape this
repo's practices doc calls a broken instrument rather than a finding. The cost
of the fix is one extra field on `Observation` and three extra arms; the cost of
leaving it was two tests whose passing said nothing.

---

## Disposition of the seventeen round-2 findings

| # | subject | disposition | where |
|---|---|---|---|
| 1 | `allowsHitTesting(false)` does not disable the receiver | **applied** — scope opened before the receiver's own registration; N2 added | `OM-T` |
| 2 | `.clipped()` inherits divergence 15 | **applied** — the one-line `pushClip` fix is taken in lane 2, its pinned-wrong test inverted | `OM-U` |
| 3 | the border paints under the children | **applied** — second emission after `content()`; B3 added; `OM-O` superseded | `OM-V` |
| 4 | `.border.cornerRadius` row false; five points cannot see it | **applied** — arc points and reference arm M1 added, row moved to not-expressible | `OM-W` |
| 5 | highest divergence is 34, not 29 | **applied** — corrected in all three places; next free 35 | `OM-R`, spec §9, record §15 |
| 6 | the demo DOES declare a `Component`; `.wrap` over a native child | **applied in part, corrected in part** — premise re-measured and the expectation re-derived; hole 5 claimed for this task; the claim that `newNode` does not trap is refuted by source and an existing exit test | `OM-Z` |
| 7 | `registerAndScope` drops `Text`'s AX payload | **applied** — two parameters added, defaulted; mutation named | `OM-X` part 1 |
| 8 | the matrix instrument cannot derive its five kinds | **applied** — five-tuple, per-kind witnesses, disagreement required of the derivation | `OM-X` part 2 |
| 9 | the two new traps are bypassable | **applied** — `public private(set)` plus validating setters; memberwise `init` updated | `OM-Y` part 1 |
| 10 | lane 2 test 14's mutation masked below zero | **applied** — the arm must use a value above 1, and the lane records it | `OM-Y` part 2 |
| 11 | `OM-E`'s order claim is derived | **applied** — G13–G16 added; the "the way SwiftUI's nesting does" clause withdrawn | `OM-E` round-2 block |
| 12 | `contentShape(inset:)` inert with no `onClick` | **applied** — doc paragraph and a pin | `OM-AB` |
| 13 | §4.4's SwiftUI column mis-cites its arms | **applied** — `SoloText` arms G10–G12 added, the row restated with the right numbers | spec §4.4, probe header |
| 14 | the display-lock reading does not reproduce | **rejected on facts, applied on substance** — it reads `<false/>` here too; the reading is volatile, so the offscreen comparison becomes primary and the lock is re-taken at lane-4 time | `OM-AC` |
| 15 | merge collisions larger than the risk table says | **applied** — three collisions added, `StyledComponent`'s storage named as a coordination item, the tripwire pre-agreed | spec §8 |
| 16 | opacity path-dependence; `Deferred` does not reset opacity | **applied** — a ruling each, and a pin for (b) | `OM-AA` |
| 17 | five smaller items | **applied, all five** — `border(_:widths:)` row added; `hoverBorder`/`focusBorder` gain the `widths:` form for symmetry; `Decoration`'s memberwise `init` updated; lane 2 test 1 reads pixels; the order-sensitive padded-hit-region row added to §6.3 | spec §5.1, §6.3, §7 |

---

## OM-AE — lane 2 ships EIGHT of §5.1's eleven modifiers; the other three are lane 3's

**Ruling.** `extension StyledElement` gains `border(_:width:)`,
`border(_:widths:)`, `hoverBorder` ×2, `focusBorder` ×2, `opacity(_:)` and
`clipped()` — **eight**. `allowsHitTesting(_:)` and the two
`contentShape(inset:)` overloads stay unwritten until lane 3, which adds
`Handlers.allowsHitTesting` and `Handlers.contentShapeInset` and the prepaint
wiring that makes them do anything.

**Reasoning.** §5.1 lists eleven because eleven is the **task's** surface, and
the lane brief inherited the number. Shipping the three hit-testing modifiers
in this lane would mean three public methods that compile, store nothing and
change nothing — exactly the shape `OM-M` deletes `borderWidth` for, introduced
in the commit that deletes it. There is no intermediate: `allowsHitTesting`
needs a `Handlers` member (lane 3 owns `Handlers.swift`, and `HandlerShape` and
`HandlerFingerprint` must gain fields in the same change), and
`contentShape(inset:)` needs `Frame.registerHandlers` to apply an inset to the
bounds it hands `insertHitbox`.

**Consequence for the tripwire.** `ModifierTests`' `cases.count` moves
38 − 2 + 8 = **44** in lane 2 and 44 + 3 = **47** in lane 3. 47 is unchanged as
this track's pre-agreed number (spec §8 risk (c)); only the intermediate is new.

**Cost if wrong.** A caller reading §5.1 finds three modifiers missing between
lane 2 and lane 3. `DecorationCompileGuards.swift`'s collision guard names
`clipped()` as legacy-only and would need a row for each when they land.

---

## OM-AF — `paintDecoration` and `registerAndScope` are METHODS on their pass, not free functions

**Ruling.** Both helpers are non-mutating methods in an `extension PaintPass` /
`extension PrepaintPass` rather than the free functions taking
`pass: inout PaintPass` that §5.2 specifies. Every call site reads
`pass.paintDecoration(decoration, in: bounds, for: id) { … }`.

**Reasoning, and it is the compiler's.** The free-function form does not
compile. `content()` at all four sites writes `pass` —
`content.paintGroup(layout:prepaint:pass: &pass)` — and an `inout` parameter
holds an **exclusive access open for the whole call**, so the closure's write
overlaps it. Measured: four `error: overlapping accesses to 'pass', but
modification requires exclusive access [#ExclusivityViolation]`, at
`Stack.swift:131`, `Stack.swift:175`, `ModifiedElement.swift:231` and
`ModifiedElement.swift:272`. A non-mutating method takes `self` as a borrow
instead, which is what `pass.clipped(to:offsetBy:) { … pass … }` — the idiom
`ScrollView.paint` has used since the clipping milestone — has always relied on.

`PaintPass` and `PrepaintPass` each hold exactly one stored property, `let
frame: Frame`, so `self` is a handle and the borrow costs nothing. Inside
`paintDecoration` one local copy (`var resolving = self`) exists solely to
satisfy `animatedBackground(_:for:pass:)`'s `inout` parameter, whose signature
about fifty test call sites are written against; the copy is the same pass by
construction.

**Cost if wrong.** None observable — the helper's behaviour is identical and
the call sites read better. It is recorded because §5.2's signature is quoted
in the spec and a reader would otherwise think the lane departed from it for
taste.

---

## OM-AG — the collision guard cannot be reddened by adding a member to a SUPERprotocol

**Ruling.** `theLegacyAndProposalDecorationModifiersDoNotCollide`'s recorded
mutation is **G3b** — declaring `clipped()` on `ElementGroup`, which makes the
`crossed` fixture compile and the `#require` fire. The mutation the spec's §8
risk row implies, declaring the legacy `opacity(_:)` on `ElementGroup` where a
proposal element also sees it, **reddens nothing**.

**Evidence, measured this lane (mutation G3).** With

```swift
extension ElementGroup { public func opacity(_ value: Float) -> Self { self } }
```

added beside the real one, `HStack { ProposalText("hi") }.border(.accent, width:
Pixels(2)).opacity(0.5)` still compiles and still selects
`ProposalElementGroup`'s. `ProposalElementGroup` **refines** `ElementGroup`, and
Swift's overload resolution prefers the more refined protocol's extension, so
there is no ambiguity to produce. The guard ran (it is not a skip: G3b reddens
it in the same session).

**Why this matters beyond one mutation.** §8's risk row reads "a new
`StyledElement` modifier collides with the proposal extension's same-named
one", and the mechanism it had in mind cannot happen for any pair where one
protocol refines the other. The collision that IS reachable is the one G3b
produces: a member on the **shared** superprotocol that the proposal side does
not also declare, which then leaks a legacy-only spelling onto every proposal
element. That is what the guard's `crossed` arm states, and the guard's doc
comment now says so instead of naming the mutation that does not work.

**Cost if wrong.** A guard whose recorded mutation does not redden it is a
decoration; this ruling is what keeps the recorded mutation honest.


---

## OM-AH — a second `.opacity` on one element REPLACES the first; SwiftUI multiplies

**Ruling.** `.opacity(v)` written twice on the same legacy element reads `v`,
not `v²`: both calls write `Decoration.opacity` and the last one wins. SwiftUI's
two calls on one view compose by multiplication. This is a **recorded
divergence**, pinned wrong on purpose, and the fifth instance of `OM-H`'s
mechanism — not, as the spec's §6.2 matrix said until this round, an agreement.

**Reasoning.** `Frame.activeOpacity` multiplies, and that is what made the wrong
row plausible: nested scopes genuinely compose to a quarter. But an element
contributes exactly **one** scope, whose value is one field, so two writes to
that field cannot become two scopes. Keeping today's behaviour rather than
making `opacity(_:)` multiply into the field: multiplying would make
`.opacity(1)` non-idempotent in a way no other `StyledElement` modifier is
(`.background(a).background(b)` is `b`, `.cornerRadius(4).cornerRadius(8)` is
8), would make the value a function of how many times the modifier was applied
rather than of what was declared, and would break the one spelling callers do
write — a conditional re-application, `base.opacity(x)` where `base` already
carries one. The spelling that multiplies is a scope between the two calls, and
it already works.

**Evidence.** Probe `docs/probes/swiftui-border-clip-paint.swift`, arms G1 and
G2, re-read this round: `red.opacity(0.5)` samples rgb(1.00,0.58,0.58) over
white and `red.opacity(0.5).opacity(0.5)` samples rgb(1.00,0.80,0.80) — one
view, two calls, a quarter. MetalUI, measured in this worktree through a real
`Window` over `FakePlatformWindow` (the emitted rect's alpha, which *is* the
composition — `Frame.fill` multiplies `color.a * activeOpacity` on the way into
the scene):

| spelling | alpha |
|---|---|
| `Box().background(.accent)` | 1.0 (the token's own) |
| `…​.opacity(0.5)` | 0.5 |
| `…​.opacity(0.5).opacity(0.5)` | **0.5** — the divergence |
| `Box { Box()…​.opacity(0.5) }.opacity(0.5)` | 0.25 |
| `…​.opacity(0.5).padding(2).opacity(0.5)` | 0.25 |

**Cost if wrong.** A caller who writes two `.opacity` calls on one element gets
a half where SwiftUI gives a quarter, silently. Pinned by
`aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies`, whose
disagreeing arms are the two spellings that do multiply. The doc comments on
`StyledElement.opacity(_:)` and `Decoration.opacity` say it at the call site,
because a caller reading "opacities compose by multiplication, as SwiftUI's do"
— which is what they said — would write exactly the spelling that does not.

---

## OM-AI — the SCOPE half of `paintDecoration`/`registerAndScope` needs its own per-site guard

**Ruling.** `OM-P`'s "a guard per site" is two guards per phase, not one. A site
that calls the helper with an **empty** `content()` closure and paints its own
children afterwards satisfies every existing site guard and is wrong in three
ways at once. The paint-side scope guard is
`everyDecorationScopingSiteContainsItsOwnContent` (four arms: `Box`, `Stack`,
`Text`, a two-layer `ModifiedElement`); the prepaint-side one is
`clippedAlsoClipsTheHitboxesInsideIt`, which is a three-arm table rather than
the single `Box` fixture it was.

**Reasoning.** `everyDecorationPaintingSiteDrawsItsBorder` asserts that ONE rect
exists carrying the right box and the right widths. That is a claim about the
helper's *emissions*, and the helper's other half is a *scope*: the opacity, the
clip, and the border's position relative to the content are all properties of
what the closure contains. A site can keep the call and lose all three. The same
asymmetry on the prepaint side is worse, because one fixture covered three
sites.

**Evidence, measured this round — four mutations, applied singly, FULL suite,
all green** at `Test run with 1256 tests in 1 suite passed`:

| mutation | what it breaks | what saw it before |
|---|---|---|
| `Text.paint` keeps `paintDecoration(…) { }` and calls `paintGlyphs` after it | glyph alpha 1.0 where it should be 0.5; glyphs escape the clip; ring drawn under them | nothing |
| `Stack.paint` likewise with `content.paintGroup` | child rect alpha 1.0 where it should be 0.5 (the element's own fill stays 0.5, which is why the emission guard is blind) | nothing |
| `Stack.prepaint` passes `Decoration()` to `registerAndScope` | a `.clipped()` `Stack` registers hitboxes outside the box it draws | nothing |
| `ModifiedElement.prepaintLayerBody` passes `Decoration()` | the same, per layer | nothing |

All four redden their own arm now, and `Box.paint`, `Box.prepaint` and
`ModifiedElement.paintLayer` were mutated the same way to confirm the tables
bite at every site rather than at one.

**Cost if wrong.** The failure is invisible in every other instrument: the
element still draws its background, its border, its focus ring and its hover
colour at the right box in the right colour. What is lost is everything *inside*
it — which is the half a reader of `DecorationScope.swift` was told was pinned.
Those doc claims are corrected in the same change (`Text.paint`'s "a faded one
fades them with its fill" and `DecorationScope.swift`'s "`clippedAlsoClips…` is
the pin") rather than left standing over a test that could not see them.

---

## OM-AJ — a grown content shape is bounded by an ancestor's clip; SwiftUI's is not

**Ruling.** A negative `contentShape(inset:)` grows the hit region past the
element's own box and is **not clamped** (`Frame.hitRegion(_:inset:)`), and
the grown region is then intersected with the active clip by `insertHitbox`,
exactly as every other hitbox is. SwiftUI's grown region is not: an ancestor
`.clipped()` does not bound it, and a click outside the clip still lands.
Recorded as a divergence and left alone; pinned by
`aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`
(lane 3), whose `(100, 100)` click outside an 80x80 `.clipped()` parent must
**miss** while its `(60, 60)` click outside the 40x40 child must hit.

**Reasoning.** The clip intersection is one rule in one place, and it is the
rule that keeps a hitbox from covering pixels the element does not draw — a
scroller's rows outside its viewport are its commonest subject, and `OM-U`
just spent divergence 15's fix making that rule correct inside a scrolled
`ScrollView`. Exempting a content shape from it would mean a second rule
("intersect, unless the region was grown") for a shape no caller has asked
for, and a hitbox on screen where nothing is. SwiftUI's own answer here is a
consequence of its `.clipped()` being purely visual (its documentation says
the modifier does not affect hit testing), which MetalUI's `.clipped()` is
not: since lane 2 it also clips the hitboxes inside it
(`clippedAlsoClipsTheHitboxesInsideIt`), and a content shape is a hitbox.

**Evidence.** `swiftui-content-shape-hit-region`, re-recorded for lane 3 with
three additive arms:

- **H4** an 80x80 `Color` with a tap, no shape — centre 1, edge **0** (the
  control: a point 40pt outside the leaf misses);
- **H5** the same at `.contentShape(Rectangle().inset(by: -60))` — centre 1,
  edge **1**: the grown region reaches the point;
- **H6** H5 inside a 100x100 `.clipped()` — centre 1, edge **1**: the clip did
  not bound it.

MetalUI, the test's fixture: the 40x40 child at `inset: -100` registers
`(0, 0) 80x80` — the parent's clip — where the unclipped answer would be
`(-100, -100) 240x240`.

**Cost if wrong.** A caller porting a SwiftUI view that grows its hit region
through a clipped ancestor finds the region stops at the clip. The opt-out is
the same as for every clip: `Deferred`, which resets the clip (`AP-I`). The
divergence table's number is the integration step's (next free was 35 at
round 2; lane 2 added none).

---

## OM-AK — a scroll region inside `allowsHitTesting(false)` is still registered, and it is recorded rather than fixed

**Ruling.** `Frame.registerScrollRegion` calls `insertHitbox` directly and
does not consult `hitTestingDisabledDepth`, so a `ScrollView` under a legacy
`.allowsHitTesting(false)` scope still registers its scroll region, still
takes the wheel, and still wins the topmost-opaque slot. **Pinned wrong on
purpose** by `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`
(lane 3): its control arm `#require`s that the fixture scrolls at all, and
its scoped arm asserts the same region count and the same offset. No SwiftUI
claim is made: whether a SwiftUI `ScrollView` under `.allowsHitTesting(false)`
still scrolls on the wheel is **unprobed**, so this is a hole recorded, not a
divergence measured.

**Reasoning.** The hole is older than this lane — CLAUDE.md's inert table
already carries "`.allowsHitTesting(false)` over a scroller — gates click
hitboxes only; a `ScrollView`/`ProposalScrollView` inside still scrolls" for
the proposal path — and lane 3 changes its **reach**, from "a proposal
subtree" to "any legacy element", which is exactly `OM-U`'s shape one modifier
over. `OM-U` took the fix because it was one line at the one site the lane
was already editing. This one is not: the site is `registerScrollRegion`,
which this lane's brief does not name, the same bypass is what keeps a
`.disabled` `ScrollView` scrolling (`EV-Q`, `aDisabledScrollViewStillScrollsOnTheWheel`,
SwiftUI likewise unmeasured), and a fix to one without the other would make
the two gates disagree about what a scope covers. The fix is one `guard` when
someone has probed SwiftUI's answer for both.

**Cost if wrong.** A caller who dims a pane with `.allowsHitTesting(false)`
expecting its scroller to go inert finds the wheel still moves it, while every
click inside is dead. The behaviour is named at `Handlers.allowsHitTesting`'s
doc and at the modifier's, and the test's failure message says "PINNED WRONG
ON PURPOSE". Integration extends the inert-table row's reach to the legacy
path rather than adding a row.
