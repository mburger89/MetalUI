# Outer modifiers and modifier order — design

Plan task 5 of [`plans/2026-09-12-swiftui-alignment.md`](../plans/2026-09-12-swiftui-alignment.md),
on `feat/outer-modifiers` in the worktree
`/Users/maxburger/Developer/MetalUI-outer-modifiers`, branched from `c4b5853`.

Rulings are `OM-` and **lettered**, in
[`../2026-09-15-outer-modifiers-decisions.md`](../2026-09-15-outer-modifiers-decisions.md)
(`OM-A`…`OM-AG`; next unused `OM-AH`). The record is
[`../../record/15-outer-modifiers.md`](../../record/15-outer-modifiers.md).
Probes are in [`../../probes/`](../../probes/); four are new here, three of them
extended and re-recorded in round 2.

**Status: lanes 1 and 2 built; lanes 3–4 designed, not implemented. Revised
once after review, once by lane 1's mutation round (`OM-AD`), and once by lane
2's (`OM-AE`, `OM-AF`, `OM-AG`).** No `Sources/` change is committed by the
design session, and lane 1 adds none either; **lane 2 is the first `Sources/`
change on this branch**. The four probes and the recorded
scratch measurements of today's MetalUI are committed, and everything below is
written against them.

**Round 2 changed seven things a reader of the first draft would get wrong**,
each on an arm taken in this session. The decisions doc's "Design review round
2" section carries all seventeen dispositions; these are the ones that change
what gets built:

1. `allowsHitTesting(false)` now disables the **receiver's own** hitbox, not
   only its subtree's (`OM-T`; arms N1 and the new N2). The first draft's
   mechanism could not have produced N1.
2. The border is a **second emission, after the children**. One before them is
   hidden by any child that fills the box — which would have made the focus ring
   invisible on the exact call it exists for (`OM-V`; the new arm B3). `OM-O` is
   superseded.
3. `.border(w).cornerRadius(r)` is a **fourth** not-expressible order, not an
   agreeing one. The first draft's five sample points all agreed by construction
   (`OM-W`; the new arc sample points and reference arm M1).
4. `.clipped()` takes divergence 15's one-line fix rather than inheriting it
   (`OM-U`): `.clipped()` makes the defect reachable from every element, not
   only from a nested `ScrollView`.
5. `registerAndScope` carries `Text`'s accessibility payload (`OM-X`); the first
   draft's signature deleted every text leaf's AX string.
6. The matrix test measures a **five**-tuple with per-kind witnesses. A triple
   cannot separate "self", "prepaint-only" and "inert" — all three read
   `(0, 0, 0)`, as does the pre-deletion `borderWidth` this audit exists to
   expose (`OM-X`).
7. The demo **does** declare a `Component` (`PreviewToggle`), and `MC-G` hole 5
   is this task's and is closed here (`OM-Z`).

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
| `border(_:width:)` / `border(_:widths:)` | **self**, paint-only (lane 2, `OM-B`); emitted **after** the children, as SwiftUI's overlay is (`OM-V`) | — | **wraps** the value, paint-only |
| `hoverBorder`/`focusBorder` (both `width:` and `widths:`) | **self**, paint-only (lane 2) — **the focus ring** | — | — |
| `cornerRadius(_:)` | **self**, paint-only; rounds this element's own fill and border | — | — (`clip(cornerRadius:)`) |
| `clipped()` | **self**, paint-**and-prepaint**-only scope (lane 2, `OM-G`); lane 2 also takes divergence 15's `pushClip` fix so it is correct inside a scrolled `ScrollView` (`OM-U`). **In the matrix TEST it is filed `paintOnly` alone**, because that instrument treats paint-only and prepaint-only as exclusive; its prepaint half is pinned by `clippedAlsoClipsTheHitboxesInsideIt` | — | **wraps** the value (`.clip`) |
| `opacity(_:)` | **self**, paint-only scope (lane 2, `OM-N`); **fades the receiver's own fill in both orders, where the proposal path fades it in only one** (`OM-AA` a) | — | **wraps** the value |
| `onClick(_:)` | **self**, prepaint-only (an opaque hitbox at the receiver's box) | — | `onTapGesture` on the value |
| `contentShape(inset:)` | **self**, prepaint-only (lane 3, `OM-J`); **configures a region, does not create one — inert with no `onClick`** (`OM-AB`) | — | — (task 12) |
| `allowsHitTesting(_:)` | **self**, prepaint-only **scope** covering the receiver's own hitbox as well as its subtree's (lane 3, `OM-T`) | — | **wraps** the value |
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
- **The proposal column is pinned by the proposal path's own tests, not by
  the matrix instrument** (`OuterModifierMatrixTests` carries legacy rows
  only — 19 `legacy Element`, 2 `legacy Component`). For `allowsHitTesting`
  those are `allowsHitTestingFalsePreventsDescendantOnTapDispatch`
  (`NativeLayoutIntegrationTests`) and `aPressIsRefusedWhereHitTestingIsDisabled`
  (`AccessibilityTreeTests`); for the paint-only wrappers, the proposal
  tests each modifier landed with (task 2). Adding a proposal-row shape to the
  matrix is the integration step's call, not a lane's.
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
| a component whose body is one **content-sized `Text`**, `.padding(20)` | **inert** — a following marker stays at x 13 | 13x16 becomes **53x56**, the leaf at (20, 20) | **G10/G11** |
| a component whose body is one fixed 30x10 leaf, `.padding(20)` | node becomes **40x40** (CSS border-box padding absorbed into the declared size) | **70x50**, the leaf at (20, 20) | **G12** |
| the same at `.padding(8)` | — | 30x10 becomes **46x26** | G5/G6 |
| `.padding(4).padding(4)` | **30x10** — replaced, then absorbed | equals `.padding(8)` | G4, E2/E3 |

**Round 2 (critic finding 13): the first two rows were mis-cited and are
re-measured.** The first draft's row read "a component whose body is one `Text`,
`.padding(20)` … SwiftUI pads: 30x10 becomes 46x26 … G5/G6" — but G5/G6 is
`Solo`, whose body is a fixed 30x10 `Color`, at `.padding(8)`. Three things were
wrong at once: the body kind, the padding value, and therefore the numbers. It
matters because MetalUI's inertness in that row comes **specifically** from the
content-sized-measured-leaf box model (CLAUDE.md's inert table: padding on a
content-sized leaf is ignored), which no arm of the first recording exercised.
G10–G12 were added and the probe re-recorded.

**The corrected numbers are a stronger result than the wrong ones.** SwiftUI's
`SoloText()` measures 13x16 on this machine — the same 13x16 a MetalUI
`Text("Hi")` measures (record §15, scratch T1) — and `.padding(20)` takes it to
53x56, the same 53 MetalUI's **element** path produces (scratch T2, marker
13 → 53). So SwiftUI and MetalUI's element path agree exactly, digit for digit,
and it is the **component** path alone that is inert. Lane 4's test 1 asserts
those numbers.

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
    /// `private(set)`: a negative width reaches `max(halfSize - border, 0.0)`
    /// in the fragment shader and produces an inner rect LARGER than the outer
    /// one, with no diagnostic above it. Every WRITE is validated, not only
    /// every init (ruling OM-Y) — a public stored `var` beside a validating
    /// `init` is a door beside an open window.
    public private(set) var widths: Edges<Pixels>
    /// Traps on a negative or non-finite width. Pinned by an exit test.
    public init(_ color: ColorToken, width: Pixels)
    public init(_ color: ColorToken, widths: Edges<Pixels>)
    /// The only other way to set `widths`; validates identically.
    public func withWidths(_ widths: Edges<Pixels>) -> BorderStyle
}

extension Decoration {                    // appended members, in this order
    public var border: BorderStyle?       // nil = draw none
    public var hoverBorder: BorderStyle?
    public var focusBorder: BorderStyle?  // the focus ring
    /// `private(set)` for OM-Y's reason: `Decoration` is public and reachable
    /// through `Box(style:decoration:)`, so `d.opacity = 2` would otherwise
    /// reach paint unchecked. Set it with `setOpacity(_:)`, which traps outside
    /// `0...1`, or through the memberwise `init` below, which validates.
    public private(set) var opacity: Float   // default 1
    public var clipsContent: Bool            // default false
    public mutating func setOpacity(_ value: Float)   // traps outside 0...1
}

// Box.swift: the EXISTING explicit public memberwise init (Box.swift:220)
// gains all five parameters and validates the two that need it. Without this
// the new fields are unreachable through `Box(decoration:)` — the first draft
// omitted it (critic finding 17c).
extension Decoration {
    public init(background: ColorToken? = nil, cornerRadius: Pixels = Pixels(0),
                /* …existing parameters… */
                border: BorderStyle? = nil, hoverBorder: BorderStyle? = nil,
                focusBorder: BorderStyle? = nil, opacity: Float = 1,
                clipsContent: Bool = false)
}

// Handlers.swift, appended.
extension Handlers {
    public var allowsHitTesting: Bool          // default true; scopes the receiver AND its subtree
    public var contentShapeInset: Edges<Pixels>?   // nil = the element's own box
}

// Box.swift, appended to `extension StyledElement`. ELEVEN for the TASK;
// **lane 2 ships the first EIGHT and lane 3 the last three** (`OM-AE`) —
// `allowsHitTesting` and `contentShape` need `Handlers` members and prepaint
// wiring, and shipping them without those is three modifiers that compile and
// do nothing. ELEVEN, not nine: the
// hover and focus borders gain the `widths:` form, so all three border
// modifiers offer the same two spellings. The first draft offered `border` in
// both forms and the other two in one, with no reason given (critic finding
// 17b); symmetry is the cheaper rule to remember, and the cost is two rows in
// `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`.
public func border(_ token: ColorToken, width: Pixels) -> Self
public func border(_ token: ColorToken, widths: Edges<Pixels>) -> Self
public func hoverBorder(_ token: ColorToken, width: Pixels) -> Self
public func hoverBorder(_ token: ColorToken, widths: Edges<Pixels>) -> Self
public func focusBorder(_ token: ColorToken, width: Pixels) -> Self
public func focusBorder(_ token: ColorToken, widths: Edges<Pixels>) -> Self
public func opacity(_ value: Float) -> Self          // traps outside 0...1
public func clipped() -> Self
public func allowsHitTesting(_ enabled: Bool) -> Self
public func contentShape(inset: Pixels) -> Self
public func contentShape(inset: Edges<Pixels>) -> Self

// DELETED from `extension StyledElement`:
//   public func borderWidth(_ points: Pixels) -> Self
//   public func borderWidth(_ edges: Edges<Length>) -> Self
```

`Decoration`'s new members are stored properties on an existing public struct
that crosses a module boundary, so **`swift package clean` before testing** the
commit that adds them (CLAUDE.md's build note; `Decoration` is
`MetalUI`-internal to the engine but public API, and the same hazard that bit
`Scene` and `FontKey` applies).

**Where they are appended matters for the merge.** All eleven go at the **end**
of the existing `extension StyledElement` in `Box.swift` — the same extension
task 4 must edit for `width`/`height`/min/max. Appending at the end keeps the
conflict to added-lines-at-a-known-anchor rather than an interleave; §8 carries
it as a coordination item.

### 5.2 One paint helper, one prepaint helper

**Both are METHODS on their pass, not free functions taking `inout`**
(`OM-AF`, measured in lane 2): `content()` writes `pass` at all four sites, and
an `inout` parameter holds an exclusive access open across the whole call, so
the closure's write overlaps it — four `#ExclusivityViolation` errors. A
non-mutating method borrows `self`, which is what
`pass.clipped(to:offsetBy:) { … pass … }` has always relied on. The signatures
below are shown in their original free-function form because the bodies are
what §5.2 specifies; the built spelling is
`pass.paintDecoration(decoration, in: bounds, for: id) { … }` and
`pass.registerAndScope(handlers, decoration, at: bounds, for: id) { … }`.

```swift
// AnimatedColor.swift (paint) — beside `animatedBackground`, which it calls.
@MainActor
func paintDecoration(_ decoration: Decoration, in bounds: Bounds<Pixels>,
                     for id: GlobalElementID, pass: inout PaintPass,
                     content: () -> Void)

// `DecorationScope.swift` (prepaint) — a new file, so the parallel
// frame/sizing track cannot collide with it.
//
// `accessibleText`/`synthesizesAccessibility` are NOT optional decoration:
// `Text.prepaint` (Text.swift:311-313) calls the five-argument internal
// overload today, and a helper that forwards only the three-argument form
// deletes every text leaf's AX string — AB-F/AB-Y's whole subject. Ruling OM-X.
// The defaults reproduce what `Box`, `Stack` and `ModifiedElement` pass today.
@MainActor
func registerAndScope<R>(_ handlers: Handlers, _ decoration: Decoration,
                         at bounds: Bounds<Pixels>, for id: GlobalElementID,
                         pass: inout PrepaintPass,
                         accessibleText: String? = nil,
                         synthesizesAccessibility: Bool = true,
                         content: () -> R) -> R
```

`paintDecoration`, in order (**revised in round 2 by `OM-V`**; step 3 was one
emission carrying both a fill and a border, and it is now two, with the children
between them):

1. `pass.opacity(decoration.opacity)` when it is below 1, wrapping **everything
   below** — including this element's own fill and border. `OM-N` records the
   consequence: `.background(x).opacity(0.5)` fades the fill (SwiftUI G3,
   agreeing) and `.opacity(0.5).background(x)` fades it too (SwiftUI G4,
   **disagreeing** — SwiftUI leaves a background written after an opacity
   opaque). Divergence, pinned wrong on purpose. `OM-AA` (a) adds that the
   **proposal path already answers the second order SwiftUI's way**, so this is
   a cross-path inconsistency as well as a cross-framework one.
2. resolve the background through `animatedBackground(decoration, for:pass:)`
   (unchanged) and the border through `resolvedBorder(decoration, for:pass:)`,
   a new function in the same file using the **same** hover/focus selection
   helper, extracted so the two chains cannot disagree about precedence.
3. **the background rect, before the children** — `pass.fill(bounds, color:
   background, cornerRadii: Corners(all: decoration.cornerRadius))`, and **not
   at all** when no background resolves, so an undecorated `Box` still emits
   nothing.
4. `pass.clipped(to: bounds, offsetBy: .zero, cornerRadii: Corners(all:
   decoration.cornerRadius))` around `content()` when `clipsContent`, else
   `content()` bare.
5. **the border rect, after the children** — `pass.fill(bounds, color:
   .transparent, cornerRadii:, borderColor:, borderWidths:)`, only when a border
   resolves. SwiftUI's `.border` is an overlay (probe arm B3: a child filling
   the whole box does not hide it), and MetalUI's children live inside the same
   box the border is drawn inside, so one emission before them is hidden by any
   filling child — which would make the **focus ring invisible on the exact call
   it exists for**. A bordered element costs two rects; a background-only one,
   which is the whole demo, still costs one.

`registerAndScope` (**revised in round 2 by `OM-T`**: the scope wraps the
receiver's own registration, not only `content()`):

1. When `handlers.allowsHitTesting` is **false**, everything below runs inside
   `pass.allowsHitTesting(false) { }`. It covers the receiver's own
   `registerHandlers` because `.onClick` and `.allowsHitTesting` write the
   **same** outermost `ModifierLayer`'s `Handlers`
   (`ModifiedElement.swift:110-114`), so registering outside the scope leaves
   `Box().onClick { }.allowsHitTesting(false)` an opaque pointer target — which
   is SwiftUI's N1 read backwards, and the common spelling rather than a corner.
   It removes the pointer target and **nothing else**: `Frame.registerHandlers`
   gates only the hitbox insert on `hitTestingDisabledDepth == 0`
   (`Frame.swift:863`), while focus registration, the `$focus` write, the
   `focusedElementProducedThisFrame` signal, the declared `AXNode` and the
   accessibility record all sit above that gate.
2. `pass.registerHandlers(handlers, at: bounds, id: id, accessibleText:,
   synthesizesAccessibility:)` — and the **only** place the content-shape inset
   is applied is inside `Frame.registerHandlers`, on the bounds it hands
   `insertHitbox` (`OM-J`). Focus registration, the `$focus` write, the declared
   `AXNode` and the accessibility emission all keep the element's own `bounds`.
3. `content()`, inside `pass.clipped(...)` when `decoration.clipsContent` — the
   prepaint half of the clip, so a hitbox inside a clipped box is registered
   against the clip, exactly as `ScrollView.prepaint` does.

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

### 5.3a `Frame.pushClip` takes divergence 15's one-line fix (`OM-U`, lane 2)

```swift
// Frame.swift, inside pushClip — the ONE added term.
let translated = Bounds(origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                                      y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
                        size: bounds.size)
let (clip, clipRadii) = Self.intersect(activeClip, radii: activeClipRadii,
                                       translated, radii: radii)
```

Today `pushClip` intersects `bounds` **untranslated** and composes the offset
only for descendants (`Frame.swift:393-400`). Its only caller is `ScrollView`,
which is why CLAUDE.md's divergence 15 reads as "a `ScrollView` inside a scrolled
`ScrollView`". Lane 2 puts `pass.clipped(to: bounds, …)` on every
`Box`/`Stack`/`Text`/`ModifierLayer`, so **the defect's reach changes**: any
`.clipped()` element inside a scrolled `ScrollView` would clip at its unscrolled
rect and, once scrolled past the viewport, draw nothing. A `.clipped()` row in
the demo's 500-row list would blank itself on the first scroll.

Taking the fix is safe here for a reason record §04 already states: the added
term is a **no-op wherever `activeOffset == 0`**, which is every non-nested
`ScrollView` in existence, so it cannot move a demo pixel — and lane 4's
comparison measures that rather than assuming it. It is outside
`Sources/MetalUILayout/`, so no golden can move.

**In the same commit**, `Tests/MetalUITests/NestedClipTests.swift`'s
`aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` is **inverted** — it
is a pinned-wrong-on-purpose assertion of this defect today — and these four
must stay green: `nestedClipsIntersectRatherThanReplace`,
`aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`,
`aHitboxInsideAScrolledRegionIsRecordedWhereItPaints`,
`aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`. Retiring divergence 15
from `CLAUDE.md` and `docs/record/04-divergences.md` is the integration step's.

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
`.width(10).padding(4)` differ (`OM-E`). `Component.padding` contributes
`.wrap`; `width`/`height` contribute `.amend`;
`StyledComponent.padding/width/height` append.

**Round 2 (`OM-E`, critic finding 11): "and differ the way SwiftUI's nesting
does" is withdrawn.** Probe arms G13–G16, added this round, show SwiftUI's order
IS observable (`Solo().padding(4).frame(70)` = 70x18 with the member centred at
x 20; `Solo().frame(70).padding(4)` = 78x18 with the member at x 24), which is
the warrant for `ops` being ordered. But SwiftUI's `.frame` **wraps** and keeps
the member 30 wide, while MetalUI's `Component.width` **amends** and overwrites
it (`OM-F`, deliberately unchanged here). MetalUI therefore reproduces the
order-sensitivity and not the member geometry. Lane 4's test 4 pins MetalUI's
own two readings, requires them to disagree, and names `OM-F` in its doc.

**Round 2 (`OM-Z`, critic finding 6): both op kinds trap on a native top-level
node, and `MC-G` hole 5 is closed here rather than deferred.** `.amend` reaches
`LayoutTree.setStyle`, which traps (`SA-G`); `.wrap` reaches
`LayoutTree.newNode(style:children:)`, which **also already traps** — its own
`for child in children { precondition(nativeNodes[slot(child)] == nil, …) }` at
`LayoutTree.swift:130-136`, pinned by an existing exit test at
`Tests/MetalUILayoutTests/NativeBoundaryTrapTests.swift:42`. Lane 4 adds one
exit test for the `.wrap` route and writes no new precondition. The
modifier-composition decisions doc assigns hole 5 to **task 5** by name; the
first draft's §9 moved it to task 7 without saying so, and that row is
withdrawn.

**Round 2 — merge coordination with task 4.** Lane 4 **replaces**
`StyledComponent`'s stored `amend: @Sendable (inout Style) -> Void` with `ops:
[ComponentModifierOp]` and rewrites all six modifier methods, in
`Component.swift` — a file on the brief's minimal-edits list. Keeping `amend`
*alongside* `ops` was considered and rejected: two separate orderings cannot
interleave, so `.padding(4).width(10)` and `.width(10).padding(4)` would collapse
to one answer and `OM-E`'s whole point would be lost. The coordination item
instead is a **boundary**: `OM-F` freezes `Component.width`/`height` semantics as
today's amend, so task 4 has no reason to edit `StyledComponent.width`/`height`
at all, and this track owns `StyledComponent`'s storage. §8 carries it.

**Built, 2026-09-16 (lane 4, `5cadec0` red-first, `367de92`).** As specified,
with one wording correction: the current-node walk is a `nodes.map` per member,
and the wrapper's `Style` comes from a private `paddingWrapperStyle(_:)` so the
component and element paths share one box model by construction rather than by
copy. Mutation M4 (one wrapper around the member LIST) and M5 (every amend
before every wrap) are the two shapes this section rules out, and each reddens
the test written for it and nothing else it should not (record §15, lane 4).

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
| `.border.cornerRadius(12)` | a **square** border clipped by the radius: the arc's interior is unbordered | D2 vs **M1** | **not expressible**: MetalUI's rounded stroke follows the arc. Divergence, pinned (`OM-W`) |
| `.border(w)` | drawn **inside** the box | B1/B2 | same (`MUIRect.borderWidths`) |
| `.border(w)` over a child that fills the box | an **overlay** — the child does not hide it | **B3** | same, after `OM-V` makes the border a second emission **after** the children |
| `.opacity(0.5).opacity(0.5)` on ONE view | multiplies to a quarter | G1/G2 | **not expressible**: the second call REPLACES the first (both write one `Decoration` field), so it reads 0.5. Divergence, pinned (`OM-AH`) |
| `.opacity(0.5)` then a SCOPE then `.opacity(0.5)` | — | — | multiplies (`Frame.activeOpacity`): a nested `Box` or a layer reads 0.25. Same as SwiftUI's nested spelling |
| `.background.opacity(0.5)` | the fill fades | G3 | same |
| `.opacity(0.5).background` | the fill does **not** fade | G4 | it does fade. Divergence, pinned (`OM-N`) |

The **five** "not expressible" rows are all the same mechanism: on the legacy
path `background`, `cornerRadius`, `border` and `opacity` are fields of **one**
`Decoration`, so their relative order within one layer — and a second write to
the same field — is not observable. A caller who needs SwiftUI's answer puts a
`Box` between them — which is a layer, and layers do order.

**Review round (`OM-AH`): the double-`.opacity` row was the fifth, and the first
draft filed it as an AGREEMENT on a confusion between two things that both
multiply.** `Frame.activeOpacity` does multiply, and nested scopes do compose to
a quarter — but SwiftUI's G1/G2 is one view with two `.opacity` calls, which on
the legacy path puts two values into one field. Measured in this worktree
through a real `Window`: `Box().background(.accent).opacity(0.5)` → alpha
**0.5**; `…​.opacity(0.5).opacity(0.5)` → alpha **0.5**; nested boxes → **0.25**;
`…​.opacity(0.5).padding(2).opacity(0.5)` → **0.25**. The row above it, the one
with no probe arm, is the spelling that agrees.

**Round 2 (`OM-W`, critic finding 4): the `.border.cornerRadius` row was the
fourth, and the first draft called it an agreement on evidence that could not
have seen a disagreement.** All five of the originally-sampled points agree
between "a square border clipped by a later radius" and "a rounded stroke": the
corner and (3,3) are outside the arc (white in both), (6,6) and the centre are
deep inside (fill in both), the edge midpoint is border in both. Two points
inside the corner arc and a reference arm were added and re-recorded:

```
D2 red.border(blue, 4).cornerRadius(12) : arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00)
M1 RoundedRect(12) fill+strokeBorder 4  : arc(5,5)=rgb(0.02,0.20,1.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(0.28,0.16,0.83)
```

`M1` is MetalUI's single emission written in SwiftUI. At arc(5,5) SwiftUI reads
the **fill** where the rounded bordered rect reads the **border**. Pinned by
`aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot`.

### 6.3 Hit testing (probe `swiftui-content-shape-hit-region`)

| chain | SwiftUI centre/edge | arm | MetalUI |
|---|---|---|---|
| tappable filling the box | 1 / 1 | H0 | same |
| stack with an empty middle + tap | 0 / 0 | H1 | **1 / 1**. Divergence, pinned (`OM-I`) |
| the same + `contentShape(Rectangle())` | 1 / 1 | H2 | MetalUI's default |
| the same + `contentShape(inset: 60)` | 1 / 0 | H3 | same, after lane 3 |
| an 80x80 leaf + tap (control) | 1 / 0 | H4 | same |
| the same + `contentShape(inset: -60)` | 1 / **1** | H5 | same: a negative inset GROWS the region past the box and is not clamped (`OM-J`) |
| H5 inside a 100x100 `.clipped()` | 1 / **1** | H6 | **1 / 0**. The grown region is intersected with the active clip, as every hitbox is. Divergence, pinned (`OM-AJ`, lane 3) |
| `.padding(80).onClick` | 1 / 0 | P1 | **1 / 1**. Divergence, pinned (`OM-K`) |
| `.onClick.padding(80)` | 1 / 0 | P2 | **1 / 0** — but for a different reason, and **order-sensitively**: only the OUTERMOST layer carries handlers, so the hitbox is at the inner box here and at the padded box above. SwiftUI's two orders agree; MetalUI's do not. Pinned (`OM-K`, extended) |
| `.padding(80).background.onClick` | 1 / 1 | P4 | same |
| `.onClick.allowsHitTesting(false)` | 0 / 0 | N1 | same, after lane 3 — **including the receiver's own hitbox** (`OM-T`) |
| `.allowsHitTesting(false).onClick` | 0 / 0 | **N2** | same. The order is not observable in SwiftUI either, so MetalUI's one-`Handlers` storage **agrees** here — this is not a not-expressible row (`OM-T`). **Within one `ModifierLayer` only** — see the X rows |
| `.padding(40).onClick` (120x120 colour, padding 40; control) | 1 / 0 | X0 | **1 / 1** (`OM-K` again) |
| `.allowsHitTesting(false).padding(40).onClick` | 0 / 0 | **X1** | **1 / 1**, a live (0, 0) 200x200 region: the scope is on the INNER layer, the click on the OUTER one, and the outer layer's region is its frame. Divergence, pinned wrong on purpose (`OM-AL`, lane 3's review round) |
| `.padding(40).allowsHitTesting(false).onClick` | 0 / 0 | **X2** | 0 / 0 — both on the outer layer; N1 again. **So MetalUI's two orders differ here and SwiftUI's do not** |
| X1's chain + `.contentShape(Rectangle())` before the tap | 1 / 1 | **X3** | — . X3 is why `OM-AL` is `OM-I` across a layer and not fixed: SwiftUI's scope empties the REGION and a later shape restores it; MetalUI's region is always the frame |

### 6.4 `Component` (probe `swiftui-component-distribution`)

| chain | SwiftUI | arm | MetalUI after lane 4 |
|---|---|---|---|
| two-member component, `.padding(8)` | 120x26, members at (8,8) and (62,8) | G2 | same shape (`Row` spacing is explicit in MetalUI, so the fixture uses `gap(8)`) |
| `.padding(4).padding(4)` | equals `.padding(8)` | G4 | same |
| one-`Text` (content-sized) component, `.padding(20)` | 13x16 → **53x56**, leaf at (20, 20) | **G10/G11** | same, and it is the SAME 13x16/53 MetalUI's element path already produces (record §15 T1/T2). Today: inert |
| one fixed-30x10-leaf component, `.padding(20)` | **70x50**, leaf at (20, 20) | **G12** | same (today: 40x40) |
| `.frame(width: 70)` | wraps each member, members keep 30/50 | G7/G8 | **overwrites** the member's width. Divergence, pinned, task 4's (`OM-F`) |
| `.padding(4)` then `.frame(70)` vs the reverse | **differ**: 70x18 member at x 20 vs 78x18 member at x 24 (`Solo`); 148x18 vs 164x18 (`Pair`) | **G13–G16** | **differ too**, but with the member's own width overwritten (`OM-F`). Lane 4 test 4 pins MetalUI's own numbers and names the divergence |
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
| 2 | `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten` | green on arrival (§6.1) | `ModifiedElement.paint` filling the outermost decoration at `pass.bounds(of: layout.inner[0].node)` instead of `bounds`. **`OM-AD`: this needs a TWO-layer arm — both §6.1 A-row chains are one `ModifierLayer` with `inner` empty, and against those the mutation reddens nothing** |
| 3 | `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes` | green on arrival | `_wrap` assigning `outermost` without appending the old one to `inner` |
| 4 | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` | green on arrival, **pinned wrong on purpose** | registering the hitbox at the innermost layer's node bounds. **`OM-AD`: also a two-layer arm — `.padding(40).onClick.padding(40)`, whose handler is on the inner layer** |
| 5 | `aBareCornerRadiusDoesNotClipTheChildren` | green on arrival, **pinned wrong on purpose** (SwiftUI C1) | making `Box.paint` push a rounded clip for its own radius. The overflowing child needs `.flexShrink(0)`, or it is shrunk to the parent and never overflows |

**Built, 2026-09-15.** All five landed; the matrix's sixteen rows all classified
as §3.1 claims them on the first run, and the mutation round — thirteen
mutations, recorded in record §15 — is what establishes that they could have
done otherwise. Two of the mutations found the tests rather than the source, and
`OM-AD` is that finding.

Test 1's table is the matrix. Each row is `(name, path, expected kind)` plus a
closure returning a **five**-tuple measured through a real `Window`:

`(nodeDelta, outerSizeDelta, rectDelta, hitRegionDelta, hitCountAtEdge)`

— the last two from `Window.lastHitboxes` (the region registered for the row's
id) and a synthesized click at the box's edge. **Round 2 (`OM-X`, critic finding
8): the first draft's triple, and its claim that the kind is derived from it,
could not have worked.** "self" (`.id()`), "prepaint-only" (`onClick`) and a
genuinely inert modifier all read `(0, 0, 0)`; `hidden()` reads a non-zero
`outerDelta` and would classify as **wraps**; pre-deletion `borderWidth` on a
sized box reads `(0, 0, 0)` — the exact API this audit exists to expose. An
instrument that cannot see the thing the audit is for is the audit agreeing with
itself.

So the kind is **not** read off the tuple. Each kind is asserted against its own
mechanism-specific witness:

| kind | witness |
|---|---|
| **wraps** | `nodeDelta > 0` **and** `outerSizeDelta > 0` |
| **self** | `nodeDelta == 0`, and the written field differs between arms on the **outermost** `ModifierLayer` — the same reflection `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` uses |
| **paint-only** | `nodeDelta == 0 && outerSizeDelta == 0` **and** `rectDelta != 0` |
| **prepaint-only** | the first three all zero **and** `hitRegionDelta != 0` or `hitCountAtEdge` moves |
| **distributes** | the measurement is repeated on a two-member `Component` and each member's own **SIZE** changes, all of them (`OM-AD`; the first draft said "the delta appears twice", and a delta appearing on member 1 is what member 0's growth does to it). **Lane 4 (`OM-AM`): for a row that also claims `wraps` — the Component `padding(_:)` row once it wraps per member — the witness is exactly `memberCount` new nodes and each member's own size UNCHANGED; the size witness was an amend's, and a per-member wrap leaves the size alone by construction** |

Rows must not be uniform: at least one row of each kind, and `#require` on the
arms disagreeing **before the kind derivation runs, not only before the row
values are compared** (shape 15) — a row whose two arms measure equal fails as a
broken instrument rather than passing as "inert".

### Lane 2 — paint-only decoration: border, focus ring, opacity, clip

**Built, 2026-09-15** (`c624d13` red-first, `9f37d10` the lane, plus two
follow-ups). Record §15's lane 2 entry has the red run, the twenty-one
mutations and the counts. What the build changed about this section is marked
**Round 3** below and in `OM-AE`, `OM-AF` and `OM-AG`.

Source: `Box.swift` (`BorderStyle`, five `Decoration` members, **eight**
modifiers — `OM-AE` — delete `borderWidth`), `AnimatedColor.swift`
(`resolvedBorder`, `paintDecoration`, the extracted hover/focus selector
`effectiveForPointerState`), **`DecorationScope.swift`** (new:
`registerAndScope`), `Box.swift`/`Stack.swift`/`Text.swift`/
`ModifiedElement.swift` paint **and prepaint** sites, `Frame.pushClip`.
`swift package clean` before the first test run of the `Decoration` commit.

New files `Tests/MetalUITests/DecorationPaintTests.swift` and
**`Tests/MetalUITests/DecorationCompileGuards.swift`** — three guards in a file
of their own rather than in `ErasureCompileGuards.swift`, because
`ErasureCompileGuards` is a shared file the other tracks also touch and a
per-file `grep -c canTypecheck` is how the guard count is taken.

| # | test | red before | mutation |
|---|---|---|---|
| 1 | `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout` — **reads PIXELS** off the fake surface's readable texture (`Tests/MetalUITests/Fakes.swift:20-63`), not `MUIRect.borderWidths`, which is the field the test itself handed in. This is `OM-S`'s "the parameters reach the shader" proof, and asserting the field back would not be one (critic finding 17d) | does not compile | `paintDecoration` passing `borderWidths: Edges(all: Pixels(0))` |
| 2 | `aBackgroundIsEmittedBeforeTheChildrenAndABorderAfter` — **replaces** `aBackgroundAndABorderAreOneEmittedRect`, whose expectation `OM-V` inverts (critic finding 3) | does not compile | swapping the two emissions, which must redden it; and separately emitting both before `content()`, which must redden test 2a |
| 2a | `aBorderIsVisibleOverAChildThatFillsTheBox` (probe B3) — a pixel arm, the defect `OM-V` exists to prevent, and the one that would have hidden every focus ring | does not compile | emitting the border before `content()` |
| 3 | `anElementWithNeitherABackgroundNorABorderEmitsNoRect` | green (today's behaviour) — the guard against "one rect per element" | `paintDecoration` filling unconditionally |
| 3a | `aBackgroundOnlyElementStillEmitsExactlyOneRect` — `OM-V`'s cost bound: two rects only when a border resolves | does not compile | emitting the border rect unconditionally |
| 4 | `everyDecorationPaintingSiteDrawsItsBorder` (one arm per site: `Box`, `Stack`, `Text`, a `ModifiedElement` layer) | does not compile | dropping the `paintDecoration` call at any ONE site reddens exactly that arm |
| 5 | `aFocusRingOutranksAHoverBorderAndABorder` | does not compile | reversing the two clauses of `resolvedBorder`'s chain |
| 6 | `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` — arms genuinely hovered and focused through a real `Window`, `BackgroundChainTests`' shape | does not compile | resolving the chain against `decoration.border` alone at one site |
| 7 | `opacityMultipliesAndFadesTheElementsOwnBackground` (G1/G2/G3) | does not compile | opening the opacity scope after the fill |
| 8 | `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot` | **pinned wrong on purpose** (G4) | — (its value is the record; the mutation for the mechanism is test 7's) |
| 9 | `clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius` | does not compile | passing `Corners(all: Pixels(0))` to the clip |
| 9a | `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints` (`OM-U`) | does not compile | reverting `pushClip`'s `+ activeOffset` |
| 9b | `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` (existing) — **inverted**; it pins divergence 15 wrong on purpose today | red the moment `pushClip` is fixed | reverting the fix |
| 9c | the four that must stay green across the `pushClip` fix: `nestedClipsIntersectRatherThanReplace`, `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`, `aHitboxInsideAScrolledRegionIsRecordedWhereItPaints`, `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` | green | — (they are the regression bound, not a new pin) |
| 10 | `clippedAlsoClipsTheHitboxesInsideIt` | does not compile | dropping the prepaint half of the clip |
| 10a | `aDeferredPortalInsideAFadedSubtreeIsStillFaded` (`OM-AA` b) — `Deferred` resets clip and offset and **not** opacity, and that answer is now reachable | does not compile | making `pushLayer`/`pushRootClip` reset `opacityStack`, which must redden it |
| 11 | `theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate` | does not compile | — **pinned wrong on purpose**, deferral to task 13 |
| 12 | `borderWidthIsNoLongerSpellable` — typecheck guard, **plain import** | compiles today | restoring either `borderWidth` overload; **and** the guard itself must be mutated red once (point it at `padding`, confirm it fails) |
| 13 | `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (existing) — drop the two `borderWidth` rows, add **eight**: `border(_:width:)`, `border(_:widths:)`, `hoverBorder` ×2, `focusBorder` ×2, `opacity`, `clipped`; update the count tripwire and its `grep -c "public func" Sources/MetalUI/Box.swift` reconciliation. The first draft said five and omitted `border(_:widths:)` entirely (critic finding 17a) | red the moment `borderWidth` is deleted | transposing any new row's field |
| 14 | `anOpacityAboveOneTraps` — an **exit test**, `#expect(processExitsWith:)`. **The arm must use a value ABOVE 1** (`OM-Y`, critic finding 10) | does not compile | removing the `precondition` from `StyledElement.opacity(_:)` |
| 15 | `aNegativeBorderWidthTraps` — an **exit test** | does not compile | removing the `precondition` from `BorderStyle.init` |
| 15a | `aBorderWidthSetAfterInitIsStillValidated` and `anOpacitySetAfterInitIsStillValidated` — exit tests through `withWidths(_:)` and `setOpacity(_:)` (`OM-Y`) | does not compile | dropping the validation from either |
| 15b | a typecheck guard, **plain import**: `BorderStyle.widths` and `Decoration.opacity` are not assignable from outside the module (`OM-Y`; a `@testable` test cannot demonstrate a narrowing — taxonomy shape 16). Mutate it red once | compiles today, since both are `var` | making either `public var` again |

**Round 3 — what lane 2 changed about this table.**

- Test 2's mutation table gained a second half: "emitting both before
  `content()`" reddens test 2 as well as 2a, and the swap reddens test 2, 2a
  **and** the existing `aContainerPaintsItsBackgroundBeneathItsChildren`.
- Test 3's mutation (fill unconditionally) reddens test 3 alone; test 3a is
  reddened by 3a's own mutation (emit the border unconditionally). The table
  implied one mutation covered both.
- **A test the table did not have:**
  `aChainsOuterLayerScopesContainTheLayersInsideIt`. Every other opacity and
  clip fixture is ONE element, so `ModifiedElement.paint`'s recursion — this
  lane's one structural edit — had nothing that could see it. Restoring the old
  loop reddened nothing until that test existed. `OM-AD`'s finding in its paint
  form; the arm is a two-layer chain with the fade on the outer layer and the
  fill on the inner one.
- Test 12's guard moved to `DecorationCompileGuards.swift`, and 15b's with it.
- The collision guard's recorded mutation is `OM-AG`'s G3b, not the one §8
  implied.

Tests 14 and 15 exist because `PaintPass.opacity` already has a
`precondition((0...1).contains(value))` that a caller can now reach from element
code, and because a negative `borderWidths` reaches the shader with no
diagnostic anywhere. Both traps are declared at the **modifier**, not left to
the pass, so the failure names the call site.

**Round 2 (`OM-Y`, critic finding 10): test 14's arm must be above 1, and the
lane records which value it ran.** `PaintPass.opacity`'s own precondition is
`(0...1)`, so an exit test painting with a **negative** opacity aborts whether or
not `StyledElement.opacity`'s precondition is there — the mutation "remove the
modifier's precondition" would redden nothing and the test would pass for the
wrong reason over half its input range. A value `> 1` does not have that problem:
`paintDecoration` opens the opacity scope only when the value is **below** 1, so
an unvalidated `1.5` never reaches `PaintPass.opacity` at all.

**Round 2 (`OM-Y`, critic finding 9): tests 15a and 15b exist because the first
draft put the preconditions on the `init`s while leaving the fields public
stored `var`s.** `var d = Decoration(); d.opacity = 2` and `var b =
BorderStyle(.accent, width: px(1)); b.widths = Edges(all: px(-5))` both reached
paint unchecked, and `Decoration` is public and settable through
`Box(style:decoration:)` — two exit tests pinning a door beside an open window.

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
| 1 | `allowsHitTestingFalseRemovesTheRECEIVERSOwnPointerTargetAndItsSubtreesAndKeepsTheKeyboardOnes` — **three arms** (`OM-T`, critic finding 1): the receiver itself carrying the `onClick` (`Box().onClick { }.allowsHitTesting(false)`, probe N1, the spelling the demo ships on the proposal path), the reverse order (probe N2, which must read the same), and a child carrying it. **As landed**, each arm is one `HitReading` — clicks, registered regions, whether a key ran, focusability — so the pointer half and the keyboard half are read together | does not compile | opening the scope **after** the receiver's own `registerHandlers` — the first draft's mechanism — which must redden the first two arms and leave the third green (**measured: N1's assertion reddens; N2 is asserted as `n2 == n1` and both register, so the two arms fail as one; the child arm stays green**); the flag un-negated; and separately, extending the scope to the focus registry, which must redden the keyboard half (**measured: exactly the two keyboard assertions, N1's and the child's**) |
| 2 | `everyHandlerRegisteringSiteHonoursAllowsHitTesting` (four arms) | does not compile | dropping the scope at any ONE site |
| 2a | `everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload` (`OM-X`, critic finding 7) — the `Text` arm is the one that matters: `registerAndScope` must forward `accessibleText`/`synthesizesAccessibility` | green after the helper lands, red if the parameters are dropped | dropping the two parameters from the helper (the three-argument overload). **Measured on the full suite: 11 tests, 24 issues** — this test's `strings.contains("hi")`, and ten in `AccessibilityDefaultsTests.swift`: `aTextIsPublishedAsStaticTextWhoseValueIsItsString`, `labelAndValueFollowSwiftUIsStaticTextRules`, `aClickableTextIsAButtonLabelledByItsString`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`, `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `aClientDoesNotChangeStateRetention`, `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`. **The two names this row predicted were wrong**: `aTextLeafPublishesItsStringAsAValue` does not exist, and `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` exists and stays GREEN — a declared `AXNode` is emitted by the three-argument overload too, so it cannot see the payload |
| 3 | `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout` (H3, L7) — **as landed, two arms**: the uniform `inset: 20` and a per-edge `5 / 10 / 15 / 20` whose four clicks each turn on exactly one edge (taxonomy shape 1: a uniform inset cannot see `hitRegion` reading `left` for `right`, since 100 − 20 − 20 is 60 either way) | does not compile | applying the inset to `bounds` before `registerHandlers` rather than inside it — which would also move focus and AX, and must redden test 5 (**measured: test 5 alone reddens, this test stays green**); `hitRegion` subtracting `left` twice (**measured: the per-edge arm's region assertion alone reddens; the uniform arm and `ModifierTests` cannot see it**) |
| 4 | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` (H4/H5; and H6's clip divergence, `OM-AJ`) | does not compile | clamping the inset at 0 (**measured: its `#require` that the arms disagree reddens**) |
| 4a | `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered` — **pinned wrong on purpose** (`OM-AK`): `registerScrollRegion` bypasses `hitTestingDisabledDepth`, so a `ScrollView` under a legacy scope still registers and still scrolls; no SwiftUI claim | green on arrival | making `registerScrollRegion` consult the depth (**measured: both of its scoped-arm assertions redden**) |
| 5 | `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration` | does not compile | test 3's mutation |
| 6 | `metalUIsDefaultHitRegionIsTheElementsWholeFrame` (H1/H2) | green on arrival, **pinned wrong on purpose** | making `Box.prepaint` hand `registerAndScope` empty handlers for an element with no background (**measured: all three of its assertions redden, with nine other tests**) |
| 6a | `aContentShapeWithoutAClickHandlerRegistersNothing` (`OM-AB`, critic finding 12) — the modifier configures a hit region, it does not create one; `Frame.registerHandlers` inserts only when `handlers.isPointerTarget`. The repo already names the identical shape one field over (`hoverBackgroundWithoutAClickHandlerNeverPaints`) | does not compile | making `registerHandlers` insert a hitbox when a content shape is declared |
| 7 | `HandlerShape` gains `allowsHitTesting` and `contentShapeInset` (CLAUDE.md: it **must** gain a field in the same change `Handlers` gains a member), and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` gains three rows; **`OuterModifierMatrixTests`' `HandlerFingerprint` gains the same two fields, and the matrix gains two `self` + `prepaint-only` rows** | red once `Handlers` changes: `cases.count == 47` read 44 with the source in and the rows out | transposing a row (**measured: `contentShape(inset: Edges)` writing `top` for `left` reddens this test and test 3's per-edge arm; `focusable()` also writing `contentShapeInset` reddens this test alone — the projection tracks the struct**) |
| 8 | the `cases.count` tripwire in `ModifierTests.swift` (today **38**) — lane 2 **drops 2** (`borderWidth` ×2) and **adds 8**, lane 3 **adds 3**: 38 − 2 + 8 + 3 = **47**, this track's pre-agreed number, stated here so task 4 adds to it rather than colliding with it (critic finding 15c) | red on each addition | — |

### Lane 4 — `Component` padding wraps, and the verification

Source: `Component.swift` (`ComponentModifierOp`, `StyledComponent.ops`, the
three `Component` and three `StyledComponent` methods).

| # | test | red before | mutation |
|---|---|---|---|
| 1 | `aComponentsPaddingWrapsEachTopLevelNode` — a one-`Text` component and a one-`Box` component at `.padding(20)`, against **G11 and G12** (13x16 → 53x56; 30x10 → 70x50). Round 2: the first draft cited G6/G2, which are `.padding(8)` on a fixed-size body, under a row claiming a `Text` body at `.padding(20)` (critic finding 13) | red: today reads the §4.4 numbers (marker stays at 13; node becomes 40x40) | `.wrap` implemented as `.amend { $0.padding = … }` restores today's numbers |
| 1a | `aPaddingModifierOnAProposalComponentTraps` — an **exit test** for the `.wrap` route over a native top-level node (`OM-Z`, `MC-G` hole 5, which the modifier-composition doc assigns to this task). No new precondition: `LayoutTree.newNode(style:children:)` already traps on a native child (`LayoutTree.swift:130-136`, `SA-G`), pinned for the direct call at `NativeBoundaryTrapTests.swift:42`; this pins the route through `StyledComponent` | does not compile | removing `newNode`'s `for child in children` precondition, which must redden this **and** the existing direct pin |
| 2 | `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement` — **replaces** `chainedPaddingReplacesRatherThanAccumulates`, whose expectation this task inverts on probe evidence (G4, E2/E3) | red | applying only the last `.wrap` |
| 3 | `aTwoMemberComponentsPaddingIsAppliedToEachMember` (G2's 120x26 shape) | red | wrapping the member list once instead of per member |
| 4 | `aModifierOnAComponentAppliesInTheOrderItIsWritten` — `.padding(4).width(70)` vs `.width(70).padding(4)`. It **pins MetalUI's own two readings** and `#require`s them to disagree; its doc names `OM-F` and states that SwiftUI's G15/G16 (70x18 member at x 20 / 78x18 member at x 24) keep the member 30 wide where MetalUI overwrites it. Round 2: the first draft said the two orders "differ the way SwiftUI's nesting does", which was a prediction about numbers no arm had taken and is false in the member geometry (critic finding 11) | red | applying every `.amend` before every `.wrap` (which collapses the two readings into one and must fail the `#require`) |
| 5 | `addingAModifierDoesNotResetAComponentsState` (existing) must stay green | — | minting an id in `StyledComponent.requestGroupLayout` (Step 8's mutation, still valid) |
| 6 | `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` (G7/G8) | green, **pinned wrong on purpose**, owner task 4 | — |
| 7 | `everyRegisteringSiteAnimatesItsStyle`'s `Component` arm — **re-measure and rewrite its readings**: the padding half now lands on a wrapper node the member's `animated` never sees, so B-7's "a caller's modifier never animates" still holds but the numbers it reads move | red the moment lane 4 lands | reverting lane 4 |

**Built, 2026-09-16** (`5cadec0` red-first, `367de92` the lane, then the
record commit). All seven rows landed; two departures from the table as
written, both recorded in `OM-AM` and `OM-Z`'s built notes:

- **Row 1a's exit test drives `StyledComponent.requestGroupLayout` directly,
  not under a `Column`.** A `Column` traps at its own `newNode` with the SAME
  "given a native child" fragment once its content returns, so a `.padding`
  that did nothing would still pass on the fragment; with the direct call the
  wrap's registration is the only legacy `newNode` in the process. Red-first it
  trapped at `setStyle` (the amend); the named mutation (M2) makes it and the
  direct pin both exit 0.
- **The matrix instrument needed a branch** (`OM-AM`): lane 1's `distributes`
  witness — each member's own size changes — is an amend's, and a per-member
  wrap leaves the size unchanged by construction, so the red-first run failed
  the lane's own deliverable on `pair.0 == pair.1`. The Component `padding(_:)`
  row now claims `[.distributes, .wraps]` and is witnessed by exactly
  `memberCount` new nodes, unchanged member sizes and a bigger outer box.

Row 4's numbers, as pinned: `.padding(4).width(70)` → outer 70, member
(4, 4, 30, 10); `.width(70).padding(4)` → outer 78, member (4, 4, 70, 10) —
SwiftUI's outer widths (G15/G16), not its member geometry (`OM-F`). Row 7's
re-measured readings: the wrapper's `padding.left` 20 at both samples, the
member's (w, h) (320, 80) at both — still B-7, on two nodes.

**Verification, in this lane, against `c4b5853`:**

1. **The primary evidence, not a fallback.** Render the **default demo root**
   and the **proposal preview** offscreen through the fake window at `c4b5853`
   and at `HEAD`, and compare the emitted `Scene` primitive-by-primitive and the
   drawable pixel-by-pixel. Report the differing-pixel count and coordinates
   (the modifier-composition track's `MC-J` shape; record §13 read 0).
   **Expected: 0**, on these grounds, each checkable:
   - lanes 1–3 change no element that does not declare one of the new fields,
     and `grep -rnE "\.(border|hoverBorder|focusBorder|opacity|clipped|allowsHitTesting|contentShape)\(" Sources/MetalUIDemo`
     finds no **legacy** call site (the proposal preview's `.border`,
     `.opacity` and `.allowsHitTesting` are `ProposalElementGroup`'s and are
     untouched);
   - `pushClip`'s added term is a no-op wherever `activeOffset == 0`, and the
     demo has no nested `ScrollView`;
   - lane 4 changes `StyledComponent` only, and **the demo's one `Component` is
     used bare**. `Sources/MetalUIDemo/main.swift:918` declares `private struct
     PreviewToggle: Component`, used at line 1017; `grep -n "PreviewToggle()"`
     shows no modifier on it, so no `StyledComponent` is ever constructed.
     **Round 2 (`OM-Z`, critic finding 6): the first draft's ground was "the
     demo declares no `Component` (`CO-Y`)", which is false** — an inherited
     citation presented as a fact about the current tree. The pixels probably
     held anyway; the reasoning did not.
2. **Re-take the display-lock state at lane-4 time and report it with a
   timestamp.** `ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` read
   `<false/>` in both design sessions and `<true/>` in the review session, so it
   is **volatile and is not a property of this machine** — recording it in a
   design document as a standing fact was the error whichever value it held
   (`OM-AC`, critic finding 14). If it reads `<false/>` at lane-4 time, also take
   **real release-window captures** with `screencapture -R`, sending no input,
   of `swift run -c release MetalUIDemo` at both commits, and diff them; if it
   reads `<true/>`, record that and rest on step 1, which is sufficient on its
   own.
3. Any deliberate difference must be **shown and explained**, not hidden. None
   is expected: the focus ring is opt-in and the demo declares no
   `.focusBorder`. If a reviewer wants the ring seen, add it to the demo in a
   **separate commit** whose diff is the demo file alone, and record the
   before/after capture.

---

## 8. Risks

**Round 2 (critic finding 15): the merge-collision row named one collision and
there are four.** The three added below are the ones that touch files on the
brief's minimal-edits list or a shared test fixture.

| risk | why it is real | what catches it |
|---|---|---|
| The other track edits `ModifiedElement.paint` too | both tracks touch the file | lane 2 rewrites `paint`'s **body** only; the merge conflict is one function, and lane 2's test 4 fails loudly if a layer's decoration stops being painted |
| **(a)** lane 2 appends eleven `public func`s to the **same** `extension StyledElement` in `Box.swift` that task 4 must edit for `width`/`height`/min/max | one extension, two tracks | all eleven go at the **end** of the extension (§5.1), so the conflict is added-lines-at-a-known-anchor rather than an interleave |
| **(b)** lane 4 **replaces** `StyledComponent`'s stored `amend` with `ops` and rewrites all six modifier methods, in `Component.swift` — a minimal-edits file — while `OM-F` hands `Component.width`/`height` to task 4 | the two tracks would edit the same property | a **boundary**, pre-agreed: `OM-F` freezes `Component.width`/`height` semantics as today's amend, so task 4 has no reason to edit those two methods; this track owns `StyledComponent`'s storage. Keeping `amend` alongside `ops` was rejected — two orderings cannot interleave, and `OM-E`'s order-sensitivity would be lost (§5.4) |
| **(c)** lane 2 test 13 and lane 3 test 7 both mutate `ModifierTests.swift`'s single `cases` array and its `cases.count == 38` tripwire, as will task 4 | one array, three lanes and another track | the number is **pre-agreed at 47** for this track (38 − 2 + 8 + 3), stated in lane 3's table so task 4 adds to it rather than colliding |
| `Decoration` gains stored properties across a module boundary | observed twice with `Scene`, once with `FontKey` | `swift package clean` before the first run of that commit, stated in lane 2 |
| A new `StyledElement` modifier collides with the proposal extension's same-named one | `.background`, `.border`, `.opacity`, `.allowsHitTesting`, `.clip` exist on `ProposalElementGroup` | no type conforms to both today (`grep`), and `.background` already exists on both without ambiguity; lane 2's `theLegacyAndProposalDecorationModifiersDoNotCollide` asserts the inferred types on a `Box` and on an `HStack`. **Round 3 (`OM-AG`, measured): the collision this row describes cannot be produced by adding a member to a superprotocol** — `ProposalElementGroup` refines `ElementGroup`, so Swift prefers the refined extension and there is no ambiguity. The reachable collision, and the guard's recorded mutation, is a legacy-only spelling leaking onto every proposal element (`clipped()` declared on `ElementGroup`) |
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
| a `ScrollView` inside `allowsHitTesting(false)` still scrolling (`OM-AK`, lane 3) | `registerScrollRegion` bypasses the depth gate, as it bypasses the disabled gate (`EV-Q`); SwiftUI's answer for either is unprobed, and the two gates should move together | whoever probes SwiftUI's `ScrollView` under `.allowsHitTesting(false)` and `.disabled` |
| `.cornerRadius` clipping its children by default (SwiftUI C1) | it would move every one of the demo's 16 `cornerRadius` call sites | task 11 |
| `.opacity` not reaching a background written after it (G4) | not expressible while both are fields of one `Decoration` | task 7 |
| `Component` `width`/`height` wrapping per member (G7/G8) | sizing semantics | task 4 |
| `Component` `background` / `onClick` / `focusable` | `CO-U`'s mechanism: nothing reaches a node's `Decoration` or `Handlers` | task 7 or later |
| ~~`MC-G` hole 5~~ | **withdrawn in round 2 (`OM-Z`, critic finding 6): it is THIS task's** — the modifier-composition decisions doc assigns it to task 5 by name (`2026-09-15-modifier-composition-decisions.md:1679`) and the first draft moved it to task 7 without saying so. Closed in lane 4 by an exit test over a trap that already exists | **task 5 (here)** |
| ~~divergence 15's one-line `pushClip` fix~~ | **withdrawn in round 2 (`OM-U`): taken here**, because `.clipped()` changes its reach from "a nested `ScrollView`" to "any element" | **task 5 (here)** |
| unifying `ModifiedElement` with `ModifiedContent` | two engines until task 7 | task 7 |
| the divergence table's numbers for this task's new rows | `CLAUDE.md` and `docs/record/04-divergences.md` are the integration step's. **Round 2 (critic finding 5): the highest allocated today is 34, not 29** — `grep -oE "^\| [0-9]+ \|" docs/record/04-divergences.md` runs 20…34 under "2026-09-15: divergences 20–34 (tasks 3, 9 and 12, integrated)". **Next free: 35.** The wrong figure appeared three times and is corrected in all three. Integration also **retires divergence 15** (`OM-U`) | integration |
| `.opacity` answering differently on the legacy and proposal paths | task 7's unification is the fix; recorded here so a caller porting a subtree is not surprised | task 7 (`OM-AA` a) |
| CLAUDE.md's declared-but-inert row for `borderWidth`, the "three `pass.fill` sites" sentence, the modifier counts | integration owns `CLAUDE.md` | integration |
