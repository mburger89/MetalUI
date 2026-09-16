# Outer modifiers and modifier order — design

Plan task 5 of [`plans/2026-09-12-swiftui-alignment.md`](../plans/2026-09-12-swiftui-alignment.md),
on `feat/outer-modifiers` in the worktree
`/Users/maxburger/Developer/MetalUI-outer-modifiers`, branched from `c4b5853`.

Rulings are `OM-` and **lettered**, in
[`../2026-09-15-outer-modifiers-decisions.md`](../2026-09-15-outer-modifiers-decisions.md)
(`OM-A`…`OM-S`; next unused `OM-T`). The record is
[`../../record/15-outer-modifiers.md`](../../record/15-outer-modifiers.md).
Probes are in [`../../probes/`](../../probes/); four are new here.

**Status: designed, not implemented.** No `Sources/` change is committed by the
design session. The four probes and the recorded scratch measurements of
today's MetalUI are committed, and everything below is written against them.

**A parallel track (task 4, frame/sizing) is live in another worktree and will
be merged with this one.** Every edit specified below to `ModifiedElement.swift`,
`Box.swift`, `Component.swift`, `Element.swift`, `ElementGroup.swift`,
`Frame.swift`, `Passes.swift` and `Handlers.swift` **appends** — a new member, a
new case, a new extension method — and reorders or renames nothing. `CLAUDE.md`,
`AGENTS.md`, `README.md`, the plan, `docs/record/README.md`, the existing record
files and the other tracks' decisions docs are the integration step's; this
track writes only the three files named above plus tests and probes.

---

## 1. What this task is

The plan's text:

> **5. Finish outer modifiers and modifier order.** Complete the padding
> migration, then audit background, overlay, border, corner/clip shape,
> opacity, hit testing, focus drawing and content shape. Pin whether each
> wraps, distributes through a `Component`, or affects only paint. Test
> order-sensitive chains such as padding/background/frame/clip.

Four deliverables, in the order the lanes deliver them:

1. **The audit, written down and pinned.** §3's matrix, and a table-driven test
   over it.
2. **One documented shape for padding.** Element padding wraps today
   (`ModifiedElement`, `MC-A`). `Component` padding does not: it writes CSS
   border-box `Style.padding` onto each top-level node, which is a different
   thing in three measurable ways (§4.4). Lane 4 makes it wrap per top-level
   node, which is what SwiftUI does (probe `swiftui-component-distribution`,
   G2/G4/G6).
3. **The two named holes.** Focus drawing (today a `focusBackground` token swap
   and nothing else) and content shape (absent). Both land as `Decoration` /
   `Handlers` fields with one shared helper per phase, §5.
4. **Order-sensitive chains**, every expectation from a probe arm run in this
   session, §6.

And the audit's one standing inert row is closed: legacy `borderWidth(_:)`
changes layout and paints nothing. It is **deleted**, and a paint-only
`.border(_:width:)` matching SwiftUI's takes the name (`OM-B`, `OM-M`).

**Not this task.** Frame/`width`/`height`/min/max sizing semantics (task 4);
porting containers (task 6); unifying `ModifiedElement` with the proposal
`ModifiedContent` (task 7); animating the new paint fields (task 13). §9 lists
every deferral with its owner.

---

## 2. What is there today

Measured this session, at `c4b5853`, by scratch tests created in
`Tests/MetalUITests/`, run with `swift test --build-system native --no-parallel
--filter`, and deleted (`git status --short` empty afterwards). The readings are
in record §15 and are quoted where each is used.

- **Legacy `.padding`** wraps: it appends a `ModifierLayer` to a
  `ModifiedElement` (`MC-A`). It wraps a `Text` leaf correctly — `Text("Hi")` is
  13x16 and `Text("Hi").padding(20)` moves a following 1pt marker from x 13 to
  **53** (scratch `T1`/`T2`).
- **Legacy `.background` / `.cornerRadius` / `.onClick` / `.focusable` /
  `.hoverBackground` / `.focusBackground` / `.id`** write the receiver's own
  `Decoration` / `Handlers` / `ElementID`, and on a `ModifiedElement` that is
  **the outermost layer** (`ModifiedElement`'s `StyledElement` accessors). So
  they already compose in SwiftUI's order for free: `Text("Hi").padding(20)
  .background(.accent)` fills `(0,0) 53x56` and
  `Text("Hi").background(.accent).padding(20)` fills `(20,20) 13x16`
  (scratch `T3`/`T4`), which is exactly SwiftUI's A1/A2
  (`swiftui-outer-modifier-order`: bg `(0,0) 36x36` vs `(8,8) 20x20`).
- **Legacy `borderWidth(_:)`** writes `Style.border`, which the engine consumes
  inside `contentBox` and discards; `Frame.fill` emits `borderColor:
  .transparent` and zero widths from `Box`/`Stack`/`Text`. It has **no
  production caller** (`grep -rn borderWidth Sources` finds only its own
  declaration and the proposal `.border`'s `pass.fill` call).
- **`Frame.fill` and `PaintPass.fill` already take `borderColor` and
  `borderWidths`**, and the proposal `.border` is their only caller
  (`NativeModifiedContent.swift:103-106`). The blocker `Box.swift` and
  `Frame.fill` document — "paint has no resolved border width to pair a colour
  with" — is a blocker for a `Style.border`-derived width, not for a
  `Decoration`-declared one in `Pixels`.
- **Proposal path** already has `background`, `clip(cornerRadius:)`, `border`,
  `opacity`, `allowsHitTesting`, `overlay`, each a `ModifiedContent` case; the
  five paint-only ones return the child node unchanged from
  `nativeWrapperNode`, so none of them has a layout footprint.
- **`Component`** has `padding` / `width` / `height` only, all through
  `StyledComponent`'s single `amend: (inout Style) -> Void`, applied to each
  top-level node after the component's own `requestGroupLayout` returns.
  `background`, `onClick`, `focusable` and `keyContext` are deliberately absent
  (`CO-U`; the typecheck guard in `ErasureCompileGuards.swift`).
- **Focus drawing** is `focusBackground`'s token swap, resolved by
  `animatedBackground` at three sites plus `ModifiedElement`'s two.
- **Content shape** does not exist, in any spelling, on either path.

---

## 3. The matrix

**Legend.**

| value | meaning |
|---|---|
| **wraps** | adds a layout node around the receiver; the receiver's own size is unchanged and its container sees a bigger box |
| **self** | writes the receiver's own `Decoration`/`Handlers`; on a chain that is the **outermost layer**, so the chain position decides which box it applies to |
| **paint-only** | emits or scopes primitives; contributes no layout node and moves nothing |
| **prepaint-only** | changes what is registered for hit testing; emits nothing and moves nothing |
| **distributes** | applied to each of a `Component`'s top-level nodes |
| **—** | not offered; the cell says what to write instead |

### 3.1 After this task

| modifier | legacy `Element` | legacy `Component` | proposal |
|---|---|---|---|
| `padding(_:)` | **wraps** (one `ModifierLayer` per call, accumulating) | **wraps each top-level node**, accumulating (lane 4, `OM-D`) | **wraps** (`.padding` case) |
| `frame(width:height:)` | **wraps** (`ModifierLayer`, centred) | — (`width`/`height` **distribute** as an amend, task 4's) | **wraps** (`.frame`/`.flexibleFrame`) |
| `width`/`height`/min/max | **self** (writes `Style`) | **distributes** (amend; overwrites the member's own value — `OM-F`) | — (use `frame`) |
| `background(_:)` | **self**, paint-only | — (use a `Box`; `CO-U`) | **wraps** the value, paint-only |
| `hoverBackground`/`focusBackground` | **self**, paint-only | — | — |
| `border(_:width:)` | **self**, paint-only (lane 2, `OM-B`) | — | **wraps** the value, paint-only |
| `hoverBorder`/`focusBorder` | **self**, paint-only (lane 2) — **the focus ring** | — | — |
| `cornerRadius(_:)` | **self**, paint-only; rounds this element's own fill and border | — | — (`clip(cornerRadius:)`) |
| `clipped()` | **self**, paint-**and-prepaint**-only scope (lane 2, `OM-G`) | — | **wraps** the value (`.clip`) |
| `opacity(_:)` | **self**, paint-only scope (lane 2, `OM-N`) | — | **wraps** the value |
| `onClick(_:)` | **self**, prepaint-only (an opaque hitbox at the receiver's box) | — | `onTapGesture` on the value |
| `contentShape(inset:)` | **self**, prepaint-only (lane 3, `OM-J`) | — | — (task 12) |
| `allowsHitTesting(_:)` | **self**, prepaint-only **scope** (lane 3) | — | **wraps** the value |
| `overlay` | — (use `Stack`, or `Deferred` to escape a clip) | — | **wraps** two values (`OverlayModifier`, `MC-P`) |
| `hidden()` | **self**, layout (`display: .none`); paint does not honour it | — | — |

`Column`, `Row` and `List` reach the `Box` row: they forward to an internal
`Box`. `Stack` and `Text` are `StyledElement` conformers in their own right and
each has its own paint and prepaint site — which is exactly why §5's helpers
exist.

### 3.2 What the matrix says that a reader will otherwise get wrong

- **"self" is not "the innermost thing".** On a chain the receiver of a `Self`-
  returning modifier is the whole `ModifiedElement`, whose accessors read and
  write `outermost`. `.padding(8).background(x)` therefore fills the padded box
  and `.background(x).padding(8)` fills the inner one. This is not a new rule;
  it is `MC-A`'s storage rule seen from the caller's side, and §6 pins it.
- **Nothing in the "paint-only" column changes a number the layout engine
  produced**, in MetalUI or in SwiftUI — probe `swiftui-outer-modifier-order`
  L2…L9: `.border`, `.opacity`, `.clipShape`, `.cornerRadius`,
  `.allowsHitTesting`, `.contentShape`, `.focusable` and `.overlay` all leave a
  20x20 leaf 20x20 where `.padding(8)` (L1) reads 36x36.
- **A `Component` has no "self" column.** It contributes no node and owns no
  `Decoration`, so every modifier on it distributes or does not exist. That is
  why the focus ring, the border, opacity and the clip are **not** offered on a
  `Component`: they are `Decoration` fields, and `CO-U`'s last paragraph
  ("`LayoutTree.setStyle` reaches a node's `Style`; nothing reaches
  `Decoration`") is the mechanism, unchanged by this task.

---

## 4. The four findings the audit produced

Each was measured this session; each has a lane.

### 4.1 `borderWidth(_:)` is reachable, changes layout, and draws nothing

Closed by deleting it and giving the name to a paint-only `.border`
(`OM-B`, `OM-M`). SwiftUI's `.border` is layout-neutral (L2) and draws **inside**
the box (`swiftui-border-clip-paint` B1/B2: the border colour at (1,1) and
(3,3), the content at (6,6)), which is what `MUIRect.borderWidths` already
does in the shader. Keeping a layout-affecting `borderWidth` beside it would be
two border concepts with one name.

### 4.2 Focus drawing has one spelling and it is a fill

Closed by `focusBorder(_:width:)`, resolved through the same
`focusBorder ?? hoverBorder ?? border` chain that backgrounds already use, drawn
in the **same** `pass.fill` call as the background (`OM-L`). A ring and a fill
are then one emission, and the precedence cannot drift between the two chains
because §5's helper resolves both.

### 4.3 Content shape does not exist, and MetalUI's default is not SwiftUI's

Probe `swiftui-content-shape-hit-region`:

- SwiftUI's default hit region is derived from what a view draws — a stack's
  empty middle is not hittable (H1, 0/0) until `.contentShape(Rectangle())`
  makes it so (H2, 1/1). **MetalUI's default already is the element's frame**,
  for everything that registers a hitbox. So `.contentShape(Rectangle())` would
  be an API that compiles and does nothing, which this repo does not ship.
- `.contentShape(Rectangle().inset(by: 60))` **shrinks** the region: centre 1,
  edge 0 (H3). That is the one thing MetalUI cannot express, and it is
  expressible in a rect-only hitbox world. So the deliverable is
  `contentShape(inset:)` (`OM-J`) — a faithful subset, non-inert by
  construction, with the identity case reachable as `inset: Pixels(0)` rather
  than as a separate no-op spelling.
- Padding is **not** hit-testable in SwiftUI in either order (P1/P2, edge 0);
  MetalUI's `.padding(80).onClick { }` reads edge **1** (scratch
  `zzScratchPaddingHitRegion`). But a `.background` declared before the gesture
  makes SwiftUI's padding hittable too (P4, edge 1), which is the filled-panel
  case every real caller writes. So the divergence is narrow: a **padded,
  background-less** click target. Recorded and pinned, not changed (`OM-K`) —
  changing it would make a padded row unclickable at its edges, and
  `contentShape(inset:)` is the opt-in.

### 4.4 `Component` padding is not the same modifier as `Element` padding

Three measured disagreements (scratch `C1`–`C6`, against probe
`swiftui-component-distribution`):

| | MetalUI today | SwiftUI | probe |
|---|---|---|---|
| a component whose body is one `Text`, `.padding(20)` | **inert** — a following marker stays at x 13 | pads: 30x10 becomes 46x26 | G5/G6 |
| a component whose body is one 30x10 `Box`, `.padding(20)` | node becomes **40x40** (CSS border-box padding absorbed into the declared size) | **70x50** | G2 |
| `.padding(4).padding(4)` | **30x10** — replaced, then absorbed | equals `.padding(8)` | G4, E2/E3 |

Lane 4 replaces the amend with a **wrap per top-level node**, which produces
SwiftUI's three answers with the same `ModifierLayer` style the `Element` path
already uses — hence "one documented shape". `width`/`height` keep their amend
(`OM-F`): they are task 4's, and SwiftUI's `.frame` on a component wraps each
member and keeps the member's own size (G7: members stay 30 and 50, centred in
70), which is a sizing-semantics change this task must not make.

---

## 5. The mechanism: two fields' worth of state, two helpers, four sites

### 5.1 New public API

```swift
// Box.swift, appended to `Decoration`.

/// A paint-only border: a semantic colour and four widths in points.
public struct BorderStyle: Sendable, Hashable {
    public var color: ColorToken
    public var widths: Edges<Pixels>
    /// Traps on a negative or non-finite width: it reaches the shader with no
    /// diagnostic anywhere above it. Pinned by an exit test (lane 2, test 15).
    public init(_ color: ColorToken, width: Pixels)
    public init(_ color: ColorToken, widths: Edges<Pixels>)
}

extension Decoration {                    // appended members, in this order
    public var border: BorderStyle?       // nil = draw none
    public var hoverBorder: BorderStyle?
    public var focusBorder: BorderStyle?  // the focus ring
    public var opacity: Float             // default 1
    public var clipsContent: Bool         // default false
}

// Handlers.swift, appended.
extension Handlers {
    public var allowsHitTesting: Bool          // default true; scopes the subtree
    public var contentShapeInset: Edges<Pixels>?   // nil = the element's own box
}

// Box.swift, appended to `extension StyledElement`.
public func border(_ token: ColorToken, width: Pixels) -> Self
public func border(_ token: ColorToken, widths: Edges<Pixels>) -> Self
public func hoverBorder(_ token: ColorToken, width: Pixels) -> Self
public func focusBorder(_ token: ColorToken, width: Pixels) -> Self
public func opacity(_ value: Float) -> Self          // traps outside 0...1
public func clipped() -> Self
public func allowsHitTesting(_ enabled: Bool) -> Self
public func contentShape(inset: Pixels) -> Self
public func contentShape(inset: Edges<Pixels>) -> Self

// DELETED from `extension StyledElement`:
//   public func borderWidth(_ points: Pixels) -> Self
//   public func borderWidth(_ edges: Edges<Length>) -> Self
```

`Decoration`'s new members are `public var`s on an existing public struct that
crosses a module boundary, so **`swift package clean` before testing** the
commit that adds them (CLAUDE.md's build note; `Decoration` is
`MetalUI`-internal to the engine but public API, and the same hazard that bit
`Scene` and `FontKey` applies).

### 5.2 One paint helper, one prepaint helper

```swift
// AnimatedColor.swift (paint) — beside `animatedBackground`, which it calls.
@MainActor
func paintDecoration(_ decoration: Decoration, in bounds: Bounds<Pixels>,
                     for id: GlobalElementID, pass: inout PaintPass,
                     content: () -> Void)

// Frame.swift or a new `HitRegion.swift` (prepaint).
@MainActor
func registerAndScope<R>(_ handlers: Handlers, _ decoration: Decoration,
                         at bounds: Bounds<Pixels>, for id: GlobalElementID,
                         pass: inout PrepaintPass, content: () -> R) -> R
```

`paintDecoration`, in order:

1. `pass.opacity(decoration.opacity)` when it is below 1, wrapping **everything
   below** — including this element's own fill. `OM-N` records the consequence:
   `.background(x).opacity(0.5)` fades the fill (SwiftUI G3, agreeing) and
   `.opacity(0.5).background(x)` fades it too (SwiftUI G4, **disagreeing** —
   SwiftUI leaves a background written after an opacity opaque). Divergence,
   pinned wrong on purpose.
2. resolve the background through `animatedBackground(decoration, for:pass:)`
   (unchanged) and the border through `resolvedBorder(decoration, for:pass:)`,
   a new function in the same file using the **same** hover/focus selection
   helper, extracted so the two chains cannot disagree about precedence.
3. **one** `pass.fill(bounds, color: background ?? .transparent, cornerRadii:
   Corners(all: decoration.cornerRadius), borderColor:, borderWidths:)` when
   either is non-nil, and none at all when both are nil (so an undecorated
   `Box` still emits nothing, and a border on a background costs no second
   rect).
4. `pass.clipped(to: bounds, offsetBy: .zero, cornerRadii: Corners(all:
   decoration.cornerRadius))` around `content()` when `clipsContent`, else
   `content()` bare.

`registerAndScope`:

1. `pass.registerHandlers(handlers, at: bounds, id: id)` — unchanged, and the
   **only** place the content-shape inset is applied is inside
   `Frame.registerHandlers`, on the bounds it hands `insertHitbox`
   (`OM-J`). Focus registration, the `$focus` write, the declared `AXNode` and
   the accessibility emission all keep the element's own `bounds`.
2. `content()`, inside `pass.allowsHitTesting(false) { }` when
   `!handlers.allowsHitTesting` and inside `pass.clipped(...)` when
   `decoration.clipsContent` — the prepaint half of the clip, so a hitbox
   inside a clipped box is registered against the clip, exactly as
   `ScrollView.prepaint` does.

### 5.3 The four sites

`Box.paint`, `Stack.paint`, `Text.paint` and `ModifiedElement.paint` (its
outermost layer and each inner layer) call `paintDecoration`; `Box.prepaint`,
`Stack.prepaint`, `Text.prepaint` and `ModifiedElement.prepaintLayerBody` call
`registerAndScope`. `Text`'s content closure draws its glyphs; a site with no
children passes an empty closure.

**`ModifiedElement.paint` changes shape.** Today it emits every layer's fill in
one loop and then paints the content once, which is correct only because a fill
is a leaf operation. An opacity or a clip is a **scope**, so the layers must
nest: outermost layer's `paintDecoration { next layer's paintDecoration { … {
content } } }`, by the same recursion `prepaintLayer` already uses. That is the
one structural edit in `ModifiedElement.swift`, and it is an edit to the body of
`paint`, not to the type's storage or member order.

**Nothing new contributes a layout node.** That is what keeps the goldens still
(`find Tests -name '*.json' | wc -l` stays 97, unchanged content) and what makes
the `L2…L9` layout-neutrality arms reproducible on the MetalUI side.

### 5.4 `StyledComponent` gains an ordered op list (lane 4)

```swift
enum ComponentModifierOp {
    case amend(@Sendable (inout Style) -> Void)   // today's behaviour
    case wrap(Style)                              // a real node around the member
}

public struct StyledComponent<C: Component>: ElementGroup {
    var component: C
    var ops: [ComponentModifierOp]                // applied in declaration order
}
```

`requestGroupLayout` forwards `parent` and `cursor` **unchanged** (that is what
`addingAModifierDoesNotResetAComponentsState` pins and it must stay true), then
for each returned node walks `ops` in order, keeping a "current node": `.amend`
reads/amends/sets that node's `Style`; `.wrap(style)` replaces it with
`pass.requestNode(style: style, children: [current])`. The mapped nodes are
returned.

Applying in declaration order is what makes `.padding(4).width(10)` and
`.width(10).padding(4)` differ, and differ the way SwiftUI's nesting does
(`OM-E`). `Component.padding` contributes `.wrap`; `width`/`height` contribute
`.amend`; `StyledComponent.padding/width/height` append.

---

## 6. Order-sensitive chains, and where each expectation comes from

Every row is a probe arm run in this session. The MetalUI column is what the
test asserts; a row marked **pinned wrong on purpose** asserts MetalUI's number
and names the divergence.

### 6.1 Layout (probe `swiftui-outer-modifier-order`)

| chain on a 20x20 leaf | outer | leaf origin | background rect | arm |
|---|---|---|---|---|
| `.padding(8)` | 36x36 | (8, 8) | — | C1 |
| `.padding(8).background` | 36x36 | (8, 8) | (0, 0) 36x36 | A1 |
| `.background.padding(8)` | 36x36 | (8, 8) | (8, 8) 20x20 | A2 |
| `.padding(8).background.padding(4)` | 44x44 | (12, 12) | (4, 4) 36x36 | A3 |
| `.frame(60x60).background` | 60x60 | (20, 20) | (0, 0) 60x60 | B1 |
| `.background.frame(60x60)` | 60x60 | (20, 20) | (20, 20) 20x20 | B2 |
| `.padding(8).frame(60x60).background` | 60x60 | (20, 20) | (0, 0) 60x60 | D1 |
| `.background.padding(8).frame(60x60)` | 60x60 | (20, 20) | (20, 20) 20x20 | D2 |
| `.padding(4).padding(4)` = `.padding(8)` | 36x36 | (8, 8) | — | E1/E2/E3 |

MetalUI's own readings for the A-row shape were taken this session on a `Text`
leaf (13x16): `.padding(20).background` fills `(0,0) 53x56`, `.background
.padding(20)` fills `(20,20) 13x16`, `.background.padding(4).padding(4)` puts
the leaf at (8, 8). All three agree with SwiftUI's shape.

### 6.2 Paint (probe `swiftui-border-clip-paint`)

| chain | what changes | arm | MetalUI |
|---|---|---|---|
| `.background.cornerRadius(12)` | the fill is rounded | C2 | same |
| `.cornerRadius(12).background` | the fill is **square** | C3 | **not expressible**: both write one `Decoration`, so MetalUI always rounds. Divergence, pinned |
| `.cornerRadius(12)` on a leaf | the **content** is clipped | C1 | **not** clipped without `.clipped()`. Divergence, pinned |
| `.cornerRadius(12).border` | a square border over rounded content | D1 | MetalUI's border always follows the radius. Divergence, pinned |
| `.border.cornerRadius(12)` | the border is cut at the corner | D2 | same as MetalUI's one-emission answer |
| `.border(w)` | drawn **inside** the box | B1/B2 | same (`MUIRect.borderWidths`) |
| `.opacity(0.5).opacity(0.5)` | multiplies | G1/G2 | same (`Frame.activeOpacity`) |
| `.background.opacity(0.5)` | the fill fades | G3 | same |
| `.opacity(0.5).background` | the fill does **not** fade | G4 | it does fade. Divergence, pinned (`OM-N`) |

The three "not expressible" rows are all the same mechanism: on the legacy path
`background`, `cornerRadius`, `border` and `opacity` are fields of **one**
`Decoration`, so their relative order within one layer is not observable. A
caller who needs SwiftUI's answer puts a `Box` between them — which is a layer,
and layers do order.

### 6.3 Hit testing (probe `swiftui-content-shape-hit-region`)

| chain | SwiftUI centre/edge | arm | MetalUI |
|---|---|---|---|
| tappable filling the box | 1 / 1 | H0 | same |
| stack with an empty middle + tap | 0 / 0 | H1 | **1 / 1**. Divergence, pinned (`OM-I`) |
| the same + `contentShape(Rectangle())` | 1 / 1 | H2 | MetalUI's default |
| the same + `contentShape(inset: 60)` | 1 / 0 | H3 | same, after lane 3 |
| `.padding(80).onClick` | 1 / 0 | P1 | **1 / 1**. Divergence, pinned (`OM-K`) |
| `.padding(80).background.onClick` | 1 / 1 | P4 | same |
| `.allowsHitTesting(false)` | 0 / 0 | N1 | same, after lane 3 |

### 6.4 `Component` (probe `swiftui-component-distribution`)

| chain | SwiftUI | arm | MetalUI after lane 4 |
|---|---|---|---|
| two-member component, `.padding(8)` | 120x26, members at (8,8) and (62,8) | G2 | same shape (`Row` spacing is explicit in MetalUI, so the fixture uses `gap(8)`) |
| `.padding(4).padding(4)` | equals `.padding(8)` | G4 | same |
| one-`Text` component, `.padding(20)` | pads | G6 | same (today: inert) |
| `.frame(width: 70)` | wraps each member, members keep 30/50 | G7/G8 | **overwrites** the member's width. Divergence, pinned, task 4's (`OM-F`) |
| `.background` | one background **per member** | G9 | **not offered**. `CO-U` |

---

## 7. Lanes

Four lanes, in order. Each is one or more commits; each commits its tests
before its source change where the test can be red, and records in
`docs/record/15-outer-modifiers.md`: the red run's summary line and issue
lines, the mutation table, and the counts it re-took.

**Counts to re-take in every lane:** `swift test --no-parallel` total (read the
`Test run with N tests` line), `find Tests -name "*.json" | wc -l` (must stay
**97**, content unchanged versus `c4b5853` — `git diff --stat c4b5853 -- Tests`
must list no `.json`), the guard count under `--build-system native`, and 0
`error:` / 0 `warning:`.

**Every NEW typecheck guard must be mutated red once** and the mutation
recorded — guards skip silently in a worktree unless `.build/<triple>/debug/
Modules` exists, so run `swift build --build-system native` first (CLAUDE.md's
CI section).

### Lane 1 — the audit, pinned as it stands

No `Sources/` change. New file `Tests/MetalUITests/OuterModifierMatrixTests.swift`.

| # | test | red before? | mutation that must redden it |
|---|---|---|---|
| 1 | `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` | **new, and must be red until its table is filled from measurements**: write it with the expected kinds first and let the arms disagree | swapping any two rows' expected kind; and, per row, the row's own mechanism (e.g. making `ModifiedElement.requestLayout` skip a layer's `requestNode`) | 
| 2 | `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten` | green on arrival (§6.1) | `ModifiedElement.paint` filling the outermost decoration at `pass.bounds(of: layout.inner[0].node)` instead of `bounds` |
| 3 | `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes` | green on arrival | `_wrap` assigning `outermost` without appending the old one to `inner` |
| 4 | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` | green on arrival, **pinned wrong on purpose** | registering the hitbox at the innermost layer's node bounds |
| 5 | `aBareCornerRadiusDoesNotClipTheChildren` | green on arrival, **pinned wrong on purpose** (SwiftUI C1) | making `Box.paint` push a rounded clip for its own radius |

Test 1's table is the matrix. Each row is `(name, path, expected kind)` plus a
closure returning a triple `(nodeDelta, outerDelta, rectDelta)` measured through
a real `Window`; `expected kind` is asserted **from** the triple, so a row whose
kind is wrong cannot pass by coincidence. Rows must not be uniform: at least one
row of each kind, and `#require` on the arms disagreeing before the kinds are
compared (shape 15).

### Lane 2 — paint-only decoration: border, focus ring, opacity, clip

Source: `Box.swift` (`BorderStyle`, five `Decoration` members, five modifiers,
delete `borderWidth`), `AnimatedColor.swift` (`resolvedBorder`,
`paintDecoration`, the extracted hover/focus selector), `Box.swift`/
`Stack.swift`/`Text.swift`/`ModifiedElement.swift` paint sites.
`swift package clean` before the first test run of the `Decoration` commit.

New file `Tests/MetalUITests/DecorationPaintTests.swift`, plus one new
typecheck guard in `ErasureCompileGuards.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 1 | `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout` | does not compile | `paintDecoration` passing `borderWidths: Edges(all: Pixels(0))` |
| 2 | `aBackgroundAndABorderAreOneEmittedRect` | does not compile | emitting the border as a second `pass.fill` |
| 3 | `anElementWithNeitherABackgroundNorABorderEmitsNoRect` | green (today's behaviour) — the guard against "one rect per element" | `paintDecoration` filling unconditionally |
| 4 | `everyDecorationPaintingSiteDrawsItsBorder` (one arm per site: `Box`, `Stack`, `Text`, a `ModifiedElement` layer) | does not compile | dropping the `paintDecoration` call at any ONE site reddens exactly that arm |
| 5 | `aFocusRingOutranksAHoverBorderAndABorder` | does not compile | reversing the two clauses of `resolvedBorder`'s chain |
| 6 | `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` — arms genuinely hovered and focused through a real `Window`, `BackgroundChainTests`' shape | does not compile | resolving the chain against `decoration.border` alone at one site |
| 7 | `opacityMultipliesAndFadesTheElementsOwnBackground` (G1/G2/G3) | does not compile | opening the opacity scope after the fill |
| 8 | `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot` | **pinned wrong on purpose** (G4) | — (its value is the record; the mutation for the mechanism is test 7's) |
| 9 | `clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius` | does not compile | passing `Corners(all: Pixels(0))` to the clip |
| 10 | `clippedAlsoClipsTheHitboxesInsideIt` | does not compile | dropping the prepaint half of the clip |
| 11 | `theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate` | does not compile | — **pinned wrong on purpose**, deferral to task 13 |
| 12 | `borderWidthIsNoLongerSpellable` — typecheck guard, **plain import** | compiles today | restoring either `borderWidth` overload; **and** the guard itself must be mutated red once (point it at `padding`, confirm it fails) |
| 13 | `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (existing) — drop the two `borderWidth` rows, add `border`, `hoverBorder`, `focusBorder`, `opacity`, `clipped`, and update the count tripwire and its `grep -c "public func" Sources/MetalUI/Box.swift` reconciliation | red the moment `borderWidth` is deleted | transposing any new row's field |

| 14 | `anOpacityOutsideZeroToOneTraps` — an **exit test**, `#expect(processExitsWith:)` | does not compile | removing the `precondition` from `StyledElement.opacity(_:)` |
| 15 | `aNegativeBorderWidthTraps` — an **exit test** | does not compile | removing the `precondition` from `BorderStyle.init` |

Tests 14 and 15 exist because `PaintPass.opacity` already has a
`precondition((0...1).contains(value))` that a caller can now reach from element
code, and because a negative `borderWidths` reaches the shader with no
diagnostic anywhere. Both traps are declared at the **modifier**, not left to
the pass, so the failure names the call site; CLAUDE.md's constraint is that a
trap is pinned with an exit test, and these are the two this task adds.

`HandlerShape` in `ModifierTests.swift` **must gain a field in the same change
`Handlers` gains a member** (CLAUDE.md; it has fallen behind twice) — that is
lane 3's obligation, not this one's, but the same test file.

### Lane 3 — hit testing: `allowsHitTesting` and `contentShape`

Source: `Handlers.swift` (two members, and `isPointerTarget`/`isKeyTarget`
unchanged — `allowsHitTesting` gates the **scope**, not the gate),
`Frame.swift` (`registerHandlers` applying `contentShapeInset` to the hitbox
bounds only), `Passes.swift` (nothing new — `allowsHitTesting(_:_:)` already
exists on `PrepaintPass`), the four prepaint sites, `Box.swift` (three
modifiers).

New file `Tests/MetalUITests/HitRegionTests.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 1 | `allowsHitTestingFalseRemovesTheSubtreesPointerTargetsAndKeepsItsKeyboardOnes` | does not compile | calling `pass.allowsHitTesting` with the flag un-negated; and separately, extending it to the focus registry (must redden the keyboard half) |
| 2 | `everyHandlerRegisteringSiteHonoursAllowsHitTesting` (four arms) | does not compile | dropping the scope at any ONE site |
| 3 | `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout` (H3, L7) | does not compile | applying the inset to `bounds` before `registerHandlers` rather than inside it — which would also move focus and AX, and must redden test 5 |
| 4 | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` | does not compile | clamping the inset at 0 |
| 5 | `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration` | does not compile | test 3's mutation |
| 6 | `metalUIsDefaultHitRegionIsTheElementsWholeFrame` (H1/H2) | green on arrival, **pinned wrong on purpose** | making `registerHandlers` register nothing for an element with no background |
| 7 | `HandlerShape` gains `allowsHitTesting` and `contentShapeInset`, and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` gains three rows | red once `Handlers` changes | transposing a row |

### Lane 4 — `Component` padding wraps, and the verification

Source: `Component.swift` (`ComponentModifierOp`, `StyledComponent.ops`, the
three `Component` and three `StyledComponent` methods).

| # | test | red before | mutation |
|---|---|---|---|
| 1 | `aComponentsPaddingWrapsEachTopLevelNode` — a one-`Text` component and a one-`Box` component, against G6 and G2 | red: today reads the §4.4 numbers | `.wrap` implemented as `.amend { $0.padding = … }` restores today's numbers |
| 2 | `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement` — **replaces** `chainedPaddingReplacesRatherThanAccumulates`, whose expectation this task inverts on probe evidence (G4, E2/E3) | red | applying only the last `.wrap` |
| 3 | `aTwoMemberComponentsPaddingIsAppliedToEachMember` (G2's 120x26 shape) | red | wrapping the member list once instead of per member |
| 4 | `aModifierOnAComponentNestsInTheOrderItIsWritten` — `.padding(4).width(10)` vs `.width(10).padding(4)` | red | applying every `.amend` before every `.wrap` |
| 5 | `addingAModifierDoesNotResetAComponentsState` (existing) must stay green | — | minting an id in `StyledComponent.requestGroupLayout` (Step 8's mutation, still valid) |
| 6 | `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` (G7/G8) | green, **pinned wrong on purpose**, owner task 4 | — |
| 7 | `everyRegisteringSiteAnimatesItsStyle`'s `Component` arm — **re-measure and rewrite its readings**: the padding half now lands on a wrapper node the member's `animated` never sees, so B-7's "a caller's modifier never animates" still holds but the numbers it reads move | red the moment lane 4 lands | reverting lane 4 |

**Verification, in this lane, against `c4b5853`:**

1. Render the **default demo root** and the **proposal preview** offscreen
   through the fake window at `c4b5853` and at `HEAD`, and compare the emitted
   `Scene` primitive-by-primitive and the drawable pixel-by-pixel. Report the
   differing-pixel count and coordinates (the modifier-composition track's
   `MC-J` shape; record §13 read 0). **Expected: 0.** Nothing in lanes 1–3
   changes an element that does not declare a new field, and the demo declares
   none; lane 4 changes only `Component`, which has no production caller
   (`CO-Y`).
2. The display is unlocked on this machine (`ioreg -n Root -d1 -a | grep -A1
   IOConsoleLocked` reads `false`), so also take **real release-window
   captures** with `screencapture -R`, sending no input, of `swift run -c
   release MetalUIDemo` at both commits, and diff them.
3. Any deliberate difference must be **shown and explained**, not hidden. None
   is expected: the focus ring is opt-in and the demo declares no
   `.focusBorder`. If a reviewer wants the ring seen, add it to the demo in a
   **separate commit** whose diff is the demo file alone, and record the
   before/after capture.

---

## 8. Risks

| risk | why it is real | what catches it |
|---|---|---|
| The other track edits `ModifiedElement.paint` too | both tracks touch the file | lane 2 rewrites `paint`'s **body** only; the merge conflict is one function, and lane 2's test 4 fails loudly if a layer's decoration stops being painted |
| `Decoration` gains stored properties across a module boundary | observed twice with `Scene`, once with `FontKey` | `swift package clean` before the first run of that commit, stated in lane 2 |
| A new `StyledElement` modifier collides with the proposal extension's same-named one | `.background`, `.border`, `.opacity`, `.allowsHitTesting`, `.clip` exist on `ProposalElementGroup` | no type conforms to both today (`grep`), and `.background` already exists on both without ambiguity; lane 2 adds a typecheck guard asserting the inferred types on a `Box` and on an `HStack` |
| The matrix test agrees with itself by construction | shape 15 | `#require` the arms disagree before comparing kinds; at least one row per kind |
| Lane 4 moves numbers a mutation record elsewhere cites | `Component.swift` carries eight mutation records | lane 4 re-runs and re-writes the `everyRegisteringSiteAnimatesItsStyle` `Component` arm rather than assuming it; the practices doc's "re-take the whole table" |
| `contentShape` silently widening AX or focus | one call site handles all three | lane 3 test 5 |
| A guard that never runs | guards skip in a worktree | `swift build --build-system native` first, and mutate each new guard red once |

---

## 9. Deferred, with owners

| item | why not here | owner |
|---|---|---|
| legacy `.overlay` | `ModifiedElement` is flat and holds one subtree; a second needs a second generic parameter, which is the `ModifiedContent` unification | task 6/7 |
| animating `border`, `focusBorder`, `opacity`, `clipsContent` | a second animated colour needs an eighth reserved slot beside `$anim-color`, and the paint-phase colour helper's shape | task 13 |
| `.contentShape` with a non-rect shape, and `.contentShape(kind:)` | `Hitbox.bounds` is a rect and `Bounds.contains` is the whole test | task 12 |
| `.cornerRadius` clipping its children by default (SwiftUI C1) | it would move every one of the demo's 16 `cornerRadius` call sites | task 11 |
| `.opacity` not reaching a background written after it (G4) | not expressible while both are fields of one `Decoration` | task 7 |
| `Component` `width`/`height` wrapping per member (G7/G8) | sizing semantics | task 4 |
| `Component` `background` / `onClick` / `focusable` | `CO-U`'s mechanism: nothing reaches a node's `Decoration` or `Handlers` | task 7 or later |
| `MC-G` hole 5 (a legacy style modifier on a proposal `Component` compiles and traps) | distribution's shape, but the fix is the typed-node work | task 7 |
| unifying `ModifiedElement` with `ModifiedContent` | two engines until task 7 | task 7 |
| the divergence table's numbers for this task's five new rows | `CLAUDE.md` and `docs/record/04-divergences.md` are the integration step's; the highest allocated today is **29** | integration |
| CLAUDE.md's declared-but-inert row for `borderWidth`, the "three `pass.fill` sites" sentence, the modifier counts | integration owns `CLAUDE.md` | integration |
