# Outer modifiers and modifier order — decisions

Plan task 5. Spec:
[`specs/2026-09-15-outer-modifiers-design.md`](specs/2026-09-15-outer-modifiers-design.md).
Record: [`../record/15-outer-modifiers.md`](../record/15-outer-modifiers.md).
Branch `feat/outer-modifiers`, from `c4b5853`.

Rulings are **lettered**: `OM-A` … `OM-S`. **Next unused: `OM-T`.** A bare
`OM-1` is a typo, not a citation.

**Status: design only.** Nothing in `Sources/` has changed. Every ruling below
states what was measured and what was only read; `OM-S` is the summary of that
split. Four SwiftUI probes were written and run in this session:

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

**Cost if wrong.** `Component` has no production caller (`CO-Y`), so the blast
radius is tests. It rewrites the expectation of one existing test
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

## OM-H — every order expectation comes from a probe arm, and three orders are not expressible

**Ruling.** The spec's §6 tables are the expectations, each citing its arm. Three
SwiftUI behaviours are **not expressible** on the legacy path and are recorded
rather than approximated:

- `.cornerRadius(r).background(c)` leaving the background square (C3);
- `.cornerRadius(r).border(w)` drawing a square border over rounded content (D1);
- `.opacity(v).background(c)` leaving the background opaque (G4, `OM-N`).

**Reasoning.** All three are the same mechanism: `background`, `cornerRadius`,
`border` and `opacity` are fields of **one** `Decoration`, so their order
*within one layer* is not observable. The alternative — making each of them open
a new layer — buys the three cases at the cost of a layout node per paint
modifier (which would not be layout-neutral: a bare `Style()` flex wrapper
becomes the flex item in its parent's line in place of its child) or a
node-less layer kind with no well-defined box. Neither is worth three corner
cases. A caller who needs them writes a `Box` between the two modifiers, which
*is* a layer, and layers do order.

**Evidence.** The arms above, plus D2 (`.border.cornerRadius` — the radius DOES
cut a border declared before it, which is MetalUI's single-emission answer, so
that order agrees).

**Cost if wrong.** A caller writing one of the three orders gets the other
answer silently. Each is pinned by a named test that asserts MetalUI's number
and cites the SwiftUI arm it disagrees with.

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
G1/G2 additionally establish that opacity **multiplies** (0.58 after one 0.5,
0.80 after two), which is what `Frame.activeOpacity` already does.

**Cost if wrong.** One order paints differently from SwiftUI. Pinned by
`opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot`.

---

## OM-O — a background and a border are ONE emitted rect

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
under a `Component` and have no production caller.

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
| `MC-G` hole 5 | the typed-node work. Task 7 |
| unifying with `ModifiedContent` | two engines until task 7 |
| divergence NUMBERS for this task's rows | `CLAUDE.md` and `docs/record/04-divergences.md` belong to the integration step; the highest allocated today is 29 |

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
  exercised it. **Lane 2's test 1 is that proof**;
- that the demo declares no `Component` (`CO-Y`'s "no production caller yet"),
  which is what makes lane 4's zero-pixel expectation reasonable. Lane 4's
  verification measures it rather than assuming it.

**Baseline, re-taken in this worktree at `c4b5853`** (`swift build
--build-system native` first, then `swift test --build-system native
--no-parallel`): `Test run with 1226 tests in 1 suite passed after 30.231
seconds`, 0 `error:`, 0 `warning:`; `find Tests -name "*.json" | wc -l` = **97**;
`grep -c canTypecheck` over the nine guard files reads 19 + 10 + 5 + 3 + 3 + 2 +
6 + 6 + 8 = 62, **less the one comment hit in `UnitSafetyTests` = 61 guards**.
All three agree with record §13's post-integration figures.
