# Transactions and animation — design (plan task 13)

Branch `feat/transactions-animation` from `2de0973` (master, plan task 12
part 2 landed, record §63). Rulings **`AN-X`…`AN-AH`** appended to the
existing animation decisions doc,
[`../2026-09-03-animation-decisions.md`](../2026-09-03-animation-decisions.md)
(next unused **`AN-AK`**; `AN-AH` is the critic round's, which amended this
spec in place — §4, §5, §6.3, §6.5, §7, §10, §11; `AN-AI` is lane 1's landing,
which amended rows 1.16 and 1.19; `AN-AJ` is lane 2's, which amended rows 2.11,
2.17 and 2.19). Evidence: `docs/probes/swiftui-transactions-animation.swift`
(**new**; arm ids `C…` controls, `W…` which wrapper animates and as what,
`P…` whether layout re-runs mid-flight, `T…` transactions, `X…` transitions,
`R…` Reduce Motion; its header carries the recorded output and how to read
it). Record: `docs/record/64-transactions-animation.md` (the Record phase
writes it).

**Status: DESIGNED, critic round applied (`AN-AH`).** The plan's task 13 text: "Make modifier wrappers
participate in transactions at their correct phase, then add
environment-driven Reduce Motion and document the supported transition
surface. Retain the existing distinction between layout and paint animation,
and drive all animation tests by timestamps rather than sleeps." Every clause
is assigned below (§9); the box is ticked by the Record phase only if every
lane lands (`AN-AG`).

## 1. Baseline

`2de0973`, this worktree with its own `.build`: `swift build --build-system
native --build-tests` then unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1880 tests in 3 suites passed after
117.409 seconds`**, 0 `error:`, the one `warning:` SwiftPM's deprecation
notice (re-taken by this design session; the log carries `FR-J no-argument
frame: succeeded=true`, so the guards ran). 116
typecheck guards, 0 goldens, **68** live divergences, next label **96**
(record §04's 2026-09-30 section). The probe ran with the screen **locked**
(`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`); `CustomAnimation`
is driven by SwiftUI in-process and ticked regardless (control C0), so no arm
depended on the lock. The real-window capture is **not taken** here (screen
locked; each lane re-checks the lock probe).

## 2. The inventory — what exists at `2de0973`

| piece | where | what it does |
|---|---|---|
| `Animation` (curves, springs) | `Animation.swift` | pure value; `linear`/eases/`timingCurve`/`spring`/`default` |
| `withAnimation(_:_:)` | `Animation.swift` | writes `pendingTransaction` (lexical) and `parkedTransaction` (one build), `AN-B`/`AN-C` |
| the build's transaction | `Window.drawFrameIfNeeded` → `Frame.transaction` (a `let`) → `LayoutPass`/`PaintPass.transaction` | one `Animation?` per frame build |
| layout helper `animated(_:_:for:pass:)` | `AnimatedStyle.swift` | `$anim` baseline per registering element: 25 `Style` numbers + `Decoration.cornerRadius`; `Box`, `Stack`, `ScrollView` ×2, every legacy `ModifierLayer` |
| paint helper `animatedColor`/`animatedBackground` | `AnimatedColor.swift` | `$anim-color`, the resolved (pointer/focus) background token, theme re-resolved per frame (`AN-F`/`AN-G`/`AN-H`) |
| liveness | `Frame.noteActiveAnimation()` → `hasActiveAnimations` | `AN-M` |
| reserved names | `$state<n>`, `$focus`, `$ax`, `$anim`, `$anim-color`; prefixes `$anim-content`/`$anim-viewport` | `theSevenRetentionSlotsAreMutuallyDistinct` (`AXNodeTests.swift`) |
| **snaps** | — | `Decoration.opacity`, `border`/`hoverBorder`/`focusBorder`, `clipsContent` (`theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate`, pinned wrong on purpose for this task); **every proposal `LayoutModifier`** (no `$anim`, "No `$anim`, no record", `ModifiedContent.swift`); a caller's modifier on a `Component` (B-7, arm (c) of `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`); `Grid`/`GridRow`/stacks/leaves; an element returning inside an `if`/loop (`ID-C`/`DD-C`); a structure change (`LR-AS`); any `Dimension` case change (`AN-J`) |
| absent | — | `Transaction`, `withTransaction`, `.transaction(_:)`, `.animation(_:value:)`, `Binding.animation`/`.transaction`, transitions of any kind, Reduce Motion |

## 3. Items addressed to plan task 13 (`AN-AF`)

Collected 2026-09-30 by `grep -rn -i -E "task 13([^0-9]|$)"` over `docs/`
(record §19 excluded — frozen), `Sources/` and `Tests/`, and from the
project memory's `animation-followups` file.

| # | item (source) | disposition |
|---|---|---|
| 1 | proposal animation; "animation on proposal wrappers, and wrappers joining transactions" (record §10; `2026-09-15-modifier-composition-decisions.md` carried table) | **built**, lane 2 (`AN-AB`) |
| 2 | the five paint-only `Decoration` fields snap (`OM-` spec §9, record §15, `AnimatedColor.swift` `resolvedBorder`, `DecorationPaintTests` test 11) | **built** for `opacity` and the three borders (colour and widths); `clipsContent` **snaps by ruling** (a `Bool` has no midpoint; SwiftUI's W10 is a structure change animated only by its default cross-fade). Lane 2 (`AN-AA`) |
| 3 | the `$anim` end-to-end per-entry figures with the 80-byte `Decoration` (record §15, §16; `AnimatedStyle.swift` doc) | **re-taken by lane 2** as `MemoryLayout` strides of every retention payload (`AnimatedElementState`, `AnimatedColorState`, the `AnimationStore` entry and its border-colour track) recorded at the lines; the isolated-process per-entry harness is the animation milestone's and uncommitted (`AN-L`) — **re-owned to plan task 15** with that reason, the arithmetic bound carried |
| 4 | Reduce Motion as an environment key (`2026-09-15-environment-decisions.md`, record §11); "system settings (Reduce Motion, Increase Contrast)" (`2026-09-15-accessibility-bridge-design.md` item 6, its decisions doc's carried table, record §12, record §63, the interaction decisions doc) | Reduce Motion **built**, lane 1 (`AN-AD`). **Increase Contrast and the other system accessibility settings** (`colorSchemeContrast`, reduce transparency, differentiate without colour) **re-owned to plan task 15**: task 13's text names Reduce Motion only, and each needs its own probe and a consumer (the theme) this task does not touch |
| 5 | `Binding.transaction`/`animation(_:)` (`DD-D` item 5, `Binding.swift`) | **built**, lane 1 (`AN-Z`) |
| 6 | animated `scrollTo` / an animated scroll offset (`DD-G` item 5, `DD-I` item 2, data-and-scrolling spec) | **kept snapping, re-owned to plan task 15, SwiftUI unmeasured**: `ScrollView` on macOS scrolls through AppKit, which the recorder cannot see, so no probe arm separates; listed in the surface doc as unsupported |
| 7 | followup: `aTransactionWhoseBodyDirtiesNothing…` wants a `try #require` that no live window is dirty | lane 2 (the test's file) |
| 8 | followup: `Window.aFrameBuildIsPending` prunes the weak registry while reading | lane 1: split the prune from the getter, pinned (test 1.19) |
| 9 | followup: `112.5` at `Animation.swift` and twice in `AnimationTests.swift` reads `112.0` measured | lane 1 re-runs mutation 33 and corrects `Animation.swift`; lane 2 corrects the two test lines; **the mechanism** is to be measured, not asserted — the hypothesis to test first is layout's whole-point rounding (divergence 77: 112.5 stored as 112) |
| 10 | followup: the 35 (now 116) guards run only under `--build-system native` | **re-owned to plan task 15**: infrastructure, not transaction semantics, and resolving the modules directory under the default build system needs its own measurement on both systems; `CLAUDE.md`'s hazard stays |
| 11 | followup: decisions doc mutation table row 16 omits its post-fixture re-take | lane 2 re-takes mutation 16 on this tree; the Record phase corrects row 16 with the measured figure |
| 12 | followup: the animation spec's §3 "all thirteen animating tests green" is uncaveated | the Record phase adds `AN-B`'s "lower bound" caveat at the line |
| 13 | followup: `CLAUDE.md`'s dated-counts line cites `b869253` | **already gone** — `CLAUDE.md` was rewritten on 2026-09-21; the frozen §19 keeps it by design |
| 14 | followup "also open": the spring's overshoot and the reverse direction | **closed 2026-09-10 by a scripted measurement** (record §19's human-verification row: overshoot 114→113 pt and colour, reverse 113→73 pt), with that row's own caveat that the readings predate `f1944f8`; the re-take stays a human look in record §03, not this task's |
| 15 | `AN-W`'s unmeasured list: nesting, two calls in one interval | **now measured** (T9, T10): SwiftUI attributes each write to its own call; MetalUI's one-transaction-per-build does not — divergence **99**, kept (`AN-Y`) |

## 4. What the probe measured (the short form)

**Controls.** C0 records a geometry line; C1 (no transaction), C2 (no change),
X1n (a transition with no transaction) and T11c (a plain `@State` binding)
record nothing.

**Which wrapper animates, and as what (W, P).**

| arm | change | SwiftUI animates |
|---|---|---|
| W1 | `.frame(width:)` 100→300 | the view's **geometry** (size +200) |
| W2 | `.padding` 10→30 | geometry: the padded box (+40, +40) and the child's origin (+20, +20) |
| W3 | `.opacity` 1→0.2 | a `Double` −0.8 (a render effect, no geometry) |
| W4, W9 | `.background` / `Rectangle().fill` red→blue | a ShapeStyle **colour** |
| W5, W5c | `.border` width 1→5 / colour | the stroke (width +4) / a colour |
| W6 | `.clipShape(RoundedRectangle(cornerRadius: 2→12))` | the corner size (+10) |
| W7 | `.frame(maxWidth: 100→300)` | geometry |
| W8 | an overlay's child frame | the overlay child's geometry |
| W10 | `.clipped()` added (an `if`/`else` swap) | ±1 opacity: the **default cross-fade** of a structure change, not a clip value |
| W11 | `HStack(spacing: 0→20)` | the second child's geometry (+20) |
| **P1** | a custom `Layout` inside `.frame(width: 100→300)` | proposed **only 300** — layout is not re-run at intermediate widths |
| **P2** | a wrapping `Text` inside `.frame(width: 60→200)` | its geometry, plus a `Double` +1 (the text's content cross-fade) |

**SwiftUI lays out once, at the final values, and interpolates each view's
placed geometry and render effects.** MetalUI interpolates the *declared
input* (a `Style` field) and re-runs layout every frame (`AN-E`). For a
wrapper's own rectangle the two agree; they differ for a child that re-lays
out (P1, P2) and for siblings that move (W11, X00). Kept — divergence **96**
(`AN-X`).

**Transactions (T).**

| arm | SwiftUI |
|---|---|
| T1 / T2 | `.animation(A, value: v)` animates when `v` changes, with no `withAnimation`; a change of anything else under it snaps |
| T3 / T3b | it reaches only its **content** — a sibling snaps, and a modifier written **after** it snaps |
| T4 / T4n | inside `withAnimation(A)`, `.animation(B, value:)` **overrides** to B; `.animation(nil, value:)` snaps |
| T5 / T5n | `withTransaction(Transaction(animation: A))` animates; `animation: nil` snaps |
| T6 / T7 / T7c | `.transaction { $0.animation = nil }` snaps its subtree only; `= B` rewrites to B, **even with no transaction at all** (T7c) |
| T8 / T8b / T8c | `disablesAnimations` suppresses `.animation(_:value:)` (A still applies, T8; nothing, T8b) and never the explicit animation (T8c) |
| T9 | `withAnimation(A) { withAnimation(B) { a }; b }` → `a` with B, `b` with A |
| T10 | two calls in one interval → each change with its own call's animation |
| T11 / T11s / T12s | `Binding.animation(A)`/`.transaction(_:)` animate a write through a **`@State`** binding; a `Binding(get:set:)` over a model **snaps** |
| T13 | a retarget runs the new animation |

**Transitions (X)** — all in a `ZStack` (no sibling shift), the transitioning
view 50×30:

| arm | insertion | removal |
|---|---|---|
| X0 (no `.transition`) | opacity +1 | opacity −1 — **SwiftUI's default is a cross-fade** |
| X1 `.opacity` | +1 | −1 |
| X2 / X3 / X3t / X3b `.move(edge:)` | offset from the edge by the view's **own** size (+50 leading, −50 trailing, +30 top) | to the edge (−50 leading, −30 top, +30 bottom) |
| X4 / X4a `.scale` | scale +1 / +0.5 | −1 |
| X5 `.slide` | +50 (from leading) | +50 (to trailing) |
| X6 `.asymmetric(.opacity, .move(.trailing))` | opacity +1 | offset +50 |
| X7 `.identity` | nothing | nothing |
| X8 `.opacity.combined(with: .move(.bottom))` | opacity +1 and offset −30 | — |
| X9 `.offset(x: 30, y: 5)` | offset (−30, −5) | — |
| X10 `.push(from: .leading)` | opacity +1, offset +50 | opacity −1, offset +50 |
| X11 / X12 `ForEach` | inserted element opacity +1 | removed element opacity −1, the next element's geometry −10 |
| X13 | `.animation(A, value: flag)` on the container animates the insertion | — |
| X14 | `.transaction { $0.animation = nil }` written outside `.transition` **inside** the `if` does **not** stop it: the transition uses the transaction at the conditional | — |
| X15 / X15b | a `.transition` **nested** inside the inserted view does not apply (the inserted `VStack` gets the default fade; with `.identity` on it, nothing animates) | — |
| X16 | `.transition` on a view that is never inserted or removed does nothing | — |
| X00 (`VStack`) | — | the sibling below slides up (geometry −30) while the removed view fades |
| **X17** / X17c (critic round) | content present in the **first render**, under a `.transaction` that forces an animation, runs **no** insertion; the same tree with the flag turned on after it appeared records opacity +1 (the separating arm) | — |

**Conformances (typecheck, critic round, recorded in the probe header).**
SwiftUI's `Transaction` is **neither `Equatable` nor `Sendable`**, and
`AnyTransition` is not `Sendable`.

**Reduce Motion (R).** `accessibilityReduceMotion` is **get-only** in SwiftUI
(typecheck, header). SwiftUI reads `NSWorkspace.accessibilityDisplayShouldReduceMotion`
and re-reads it **on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`**
(R1 false, R2 true after the post). With it true: **property animations are
unchanged** (R3 frame, R4 opacity, R6 `.animation(_:value:)`; R7 the
transaction still carries `DefaultAnimation`), and **every transition except
`.identity` becomes an opacity cross-fade on the same animation** — `.move`
insert/remove, `.scale`, `.slide`, `.offset`, `.push`, `.asymmetric`,
`.combined` (R5, R5r, R5s, R5l, R5o, R5p, R5a, R5c); `.identity` stays nothing
(R5i). The separating controls R10 (reader false) record the offset and the
scale again.

## 5. Public API (spelled against SwiftUI)

```swift
// Transaction.swift (lane 1)
public struct Transaction: Sendable {   // not Equatable (SwiftUI's is not; AN-AH item 5)
    public var animation: Animation?
    public var disablesAnimations: Bool          // default false
    public init()
    public init(animation: Animation?)
}
@MainActor public func withTransaction<Result>(_ transaction: Transaction,
                                               _ body: () throws -> Result) rethrows -> Result
@MainActor public func withAnimation<Result>(_ animation: Animation? = .default,
                                             _ body: () throws -> Result) rethrows -> Result
// (replaces `withAnimation(_: Animation = .default, _: () -> Void)`; every
//  existing call compiles unchanged)

// AnimationScope.swift (lane 1) — on ElementGroup, and on ProposalElementGroup
// through a typed conformance, returning one type:
func animation<V: Equatable>(_ animation: Animation?, value: V) -> TransactionScope<Self>
func transaction(_ transform: @escaping (inout Transaction) -> Void) -> TransactionScope<Self>

// Binding.swift (lane 1)
public var transaction: Transaction                         // get/set
public func animation(_ animation: Animation? = .default) -> Binding<Value>
public func transaction(_ transaction: Transaction) -> Binding<Value>

// EnvironmentValues.swift (lane 1)
public internal(set) var accessibilityReduceMotion: Bool   // false in a bare value

// MetalUIPlatform.PlatformWindow (lane 1) — NO default implementation (EV-AB's rule)
var accessibilityReduceMotion: Bool { get }
var onAccessibilityReduceMotionChange: ((Bool) -> Void)? { get set }

// Transition.swift (lane 3)
public enum Edge: Sendable { case top, leading, bottom, trailing }
public struct AnyTransition: Sendable {
    public static let identity: AnyTransition
    public static let opacity: AnyTransition
    public static let slide: AnyTransition
    public static let scale: AnyTransition                        // AN-AH item 1
    public static func scale(scale: Double, anchor: UnitPoint = .center) -> AnyTransition
    public static func move(edge: Edge) -> AnyTransition
    public static func offset(x: Pixels = Pixels(0), y: Pixels = Pixels(0)) -> AnyTransition
    public static func push(from edge: Edge) -> AnyTransition
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition
    public func combined(with other: AnyTransition) -> AnyTransition
}
// on ElementGroup and ProposalElementGroup:
func transition(_ t: AnyTransition) -> TransitionGroup<Self>
```

`Sendable` on `Transaction` and `AnyTransition` is additive beyond SwiftUI and
needed for Swift 6 `static let`s and the frame's value-typed stack (`AN-AH`
item 5).

**Not offered, listed** (the surface doc, `AN-AE` as amended by `AN-AH`):
`.blurReplace`, `.modifier(active:identity:)`, the deprecated value-less
`.animation(_:)`,
the `Transition` protocol and custom transitions, `AnyTransition.animation(_:)`,
`matchedGeometryEffect`, `contentTransition`, `.transaction(value:_:)`,
`.animation(_:body:)`, `withAnimation(_:completionCriteria:_:completion:)`,
`Animation.delay`/`speed`/`repeatCount`/`repeatForever`, and an animated scroll
offset. A plain-import guard pins `.blurReplace`'s absence (3.19). **`.scale`
is supported** (`AN-AH` item 1): the design's reason for omitting it — "a
glyph cannot be scaled without a re-rasterized atlas entry" — was an
unmeasured "cannot", refuted by `glyph_vertex` (`shaders.metal`), which
interpolates `atlasPosition` from `atlasBounds` across the destination
`bounds` independently, with a `filter::linear` sampler, so a scaled glyph
quad resamples the atlas.

## 6. Semantics

### 6.1 Transactions (`AN-Y`, lane 1)

- **The frame carries a transaction STACK.** Its root is `Transaction(animation:
  <parked>, disablesAnimations: <parked flag>)`; `LayoutPass.transaction` and
  `PaintPass.transaction` read the **top**'s `animation` (type unchanged,
  `Animation?`). `withTransaction` parks the animation exactly as `withAnimation`
  does today — **`AN-C`'s predicate is untouched** — and parks
  `disablesAnimations` beside it under the same predicate, consumed by the same
  `takeParkedTransaction`. `Animation.parkedTransaction` keeps its type (tests
  read it through `@testable`).
- **`TransactionScope<Content>` is layout- and identity-TRANSPARENT**, like
  `EnvironmentScope` (SwiftUI modifiers carry no identity; `EV-X`'s "a modifier
  written after a scope sits outside it" is T3b's answer exactly). It pushes
  its resolved transaction around its content in **layout and paint** — the
  two phases a helper reads it in — and pops after. Prepaint pushes nothing.
  Its typed `ProposalElementGroup` entry is a line-for-line copy of the
  untyped one, with its own pin (1.4's proposal arm).
- **`.transaction(transform)`** applies `transform` to a copy of the current
  top, every frame (T7c: even when the root has no animation).
- **`.animation(anim, value:)`** compares `value` with the value it stored last
  frame; when they differ and the current top's `disablesAnimations` is false,
  it pushes the top with `animation = anim` (T1, T4, T4n, T8, T8b); otherwise
  it pushes the top unchanged. The stored value lives in the window's
  `AnimationStore` (§6.2), keyed by `.named("$anim-value<d>")` under
  `.child(of: parent, at: cursor)` — the position it sits at — where `d` is
  the current transaction-stack depth, so two scopes nested at one position
  keep separate values (1.11). **A first sighting stores and does not
  animate.** The layout decision is remembered for the same frame's paint.
- **One transaction still reaches one build** at the root: T9 and T10 are not
  matched (divergence **99**, kept, owner none — per-write attribution needs
  dependency tracking the rebuild-everything model does not have;
  `.animation(_:value:)` is the per-value remedy, and it works).
- **`Binding`**: `animation(_:)` returns a copy whose `transaction.animation`
  is set; `transaction(_:)` replaces it. A write through a binding whose
  source is `@State` (`State.projectedValue`, and every binding derived from
  one by dynamic member or the optional initialisers) runs inside
  `withTransaction(transaction)` when its transaction carries an animation;
  a `Binding(get:set:)` ignores its transaction (T11 vs T11s — `AN-Z`).

### 6.2 `AnimationStore` (lane 1 builds it; lanes 2 and 3 use it)

A window-owned `final class` handed to each `Frame` (and a fresh one per
headless `renderFrame`), holding animation state that must **not** be
`StateTable` state: entries keyed by `GlobalElementID`, each marked when
touched, and **every entry not touched by a frame dropped at the end of that
frame**. So content that leaves and returns starts fresh — the same answer
`ID-C`/`DD-C` give the `$anim` slots — without adding `StateTable` entries
(no `TB-AH` threshold moves, no pinned table count moves, no reserved name),
and a `List` row out of its window drops its entries (it is not evaluated;
its return is a first sighting, which snaps, as today). It also holds the
transition seam (§6.5): `var transitions: TransitionStore`, whose type lane 1
declares as a stub in `TransitionStore.swift` with three no-op hooks the
frame calls — `afterLayout(_ frame:)`, `paintGhosts(_ pass:)`,
`endFrame()` — and which lane 3 fills. A work counter
(`AnimationStore.lastFrameInterpolations`) counts interpolations performed,
for 2.12.

### 6.3 Modifier wrappers (lane 2)

**Per wrapper, per vocabulary** (`AN-AA`, `AN-AB`, `AN-AC`). "Layout" means
interpolated in `requestLayout` (the element or layer rewrites its own value,
which prepaint and paint then read — the mechanism `cornerRadius` already
uses); "paint" means interpolated in paint off the theme.

| wrapper | legacy (`ModifierLayer`/`Box`/`Stack`/`Text`) | proposal (`LayoutModifier`) | SwiftUI |
|---|---|---|---|
| size, min/max, padding, margin, gap, inset, flex numbers | layout, `$anim` (unchanged) | `.frame(width:height:)`, finite `.flexibleFrame` bounds, `.padding`: **layout, new**, `AnimationStore` | W1, W2, W7 |
| `cornerRadius` | layout, `$anim` (unchanged) | `.clip(cornerRadius:)`: **layout, new** | W6 |
| `opacity` | **layout, new** — the `$anim` baseline already stores `Decoration.opacity` | `.opacity`: **layout, new** | W3 |
| border widths (`border`/`hoverBorder`/`focusBorder`) | **layout, new** — in the `$anim` baseline, per field | `.border(_:width:)` width: **layout, new** | W5 |
| background colour (resolved) | paint, `$anim-color` (unchanged) | `.background(token)`: **paint, new** | W4 |
| border colour (resolved) | **paint, new** — a token track in the **`AnimationStore`** (`AN-AH` item 3; no `StateTable` entry, no eighth reserved name) | `.border` colour: **paint, new** | W5c |
| `clipsContent`, `allowsHitTesting`, `fixedSize`, `layoutPriority`, `aspectRatio`, alignment, a `clipShape`'s shape, `nil` ↔ value, finite ↔ infinite | snap | snap | a `Bool`/structure has no midpoint (W10); shape parameters, `aspectRatio` and alignment — divergence **97** |
| a caller's `.padding`/`.width`/`.height` on a `Component` | **layout, new** (B-7 fixed), `AnimationStore` keyed per op per member | — | SwiftUI animates any view's geometry |

- **The phase rule, restated so it holds** (`AN-AA`): a value that needs the
  **theme** (a colour token) or the **pointer/focus state** (which of three
  variants wins) is interpolated in paint, where both exist (`AN-F`). A number
  that needs neither interpolates in the layout helper that already stores it
  — `cornerRadius`'s precedent. Both run off the same frame timestamp, so a
  number interpolated in layout and read in paint is the value SwiftUI's
  render-effect animation shows at that instant.
- **The legacy border-colour track lives in the `AnimationStore`** (`AN-AH`
  item 3, replacing the design's eighth `StateTable` slot `$anim-border`),
  keyed by the element's id and the name `border`, and otherwise mirrors
  `$anim-color`'s recipe exactly (touched only when a border resolves; the
  resolved token by pointer/focus state; tokens stored, re-resolved per frame;
  interrupt from the current colour and velocity). A border appearing from
  none is a first sighting and snaps, as a background appearing from none
  does. **Nothing in `StateTable` moves**: no entry per bordered element, so
  no `TB-AH` eviction point, pinned table count or `List` retention moves, and
  the reserved names stay **seven** —
  `theSevenRetentionSlotsAreMutuallyDistinct` is untouched. The store's
  one-frame drop applies: an element whose paint is skipped for a frame (a
  hidden layer, `Frame.swift`'s paint gate) loses its border track and its
  next change from there is a first sighting (snaps) — stated, where
  `$anim-color` would resume.
- **Proposal layers**: `LayoutModifier._requestLayout` rewrites `self` to the
  interpolated case for the numeric cases; `_paint` resolves the colour cases
  through a token track in the `AnimationStore` (the `animatedColor` recipe,
  theme re-resolved per frame, keyed by the layer's id and a case name). The
  prepaint clip reads the same interpolated radius the paint does, as a
  legacy `cornerRadius` already does. Every in-flight layer calls
  `noteActiveAnimation()`.
- **A `Component`'s ops** (B-7): `StyledComponent.requestGroupLayout` knows its
  own id (`.child(of: parent, at: cursor)` before the component consumes it),
  each member's index and each op's index; it interpolates the op's value in
  the `AnimationStore` under `.named("$anim-op<k>")` below
  `.child(of: componentID, at: member)`. The member's own baseline is never
  touched (the unsound fix `Component.swift`'s doc rejects is not this one).
  Arm (c) of `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`
  **changes its answer by ruling** (snap → animates; `goldensUnchanged`: the
  test is retained, its arm re-derived, the ruling cited in the arm).
- **What still snaps and SwiftUI animates** — proposal leaves' colours
  (`Color`, `Rectangle`, `ShapeView` fill/stroke, W9), stack and grid spacing
  and alignment (W11), `Text`'s foreground colour and font, a `clipShape`'s
  shape parameters (W6), `aspectRatio`, a frame's alignment — divergence
  **97**, kept, owner none, the list in the surface doc.

### 6.4 Reduce Motion (`AN-AD`, lane 1)

- `EnvironmentValues.accessibilityReduceMotion`, `public internal(set)` (SwiftUI's
  get-only key path; a scope cannot write it — guard 1.14).
- **Source**: `PlatformWindow.accessibilityReduceMotion` and
  `onAccessibilityReduceMotionChange`, **defaultless** (EV-AB's reason; guard
  1.15). `Window` reads it at construction, keeps a guarded copy updated by the
  callback (which marks the window dirty), and stamps it over the root
  environment at draw beside `controlActiveState` — so, like
  `controlActiveState`, `theme` and `displayScale`, `Window.environment`'s own
  value is not the root's source. `renderFrame` stamps `false`.
- **AppKit**: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`,
  re-read on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`
  from `NSWorkspace.shared.notificationCenter` — the same source and the same
  refresh SwiftUI uses (R1, R2).
- **SDL**: `false`, and the callback never fires — documented at the
  conformer. SDL3 has no query; a platform-specific read (GNOME's
  `enable-animations`, Windows' `SPI_GETCLIENTAREAANIMATION`) is listed for
  the cross-platform roadmap, not built here.
- **Behaviour**: property animations, `withAnimation`, `.animation(_:value:)`
  and `.transaction` are **unchanged** (R3, R4, R6, R7). Every transition
  except `.identity` resolves to `.opacity` on the same animation (R5…) —
  implemented in lane 3's transition code, reading the environment at the
  transition's position.

### 6.5 Transitions (`AN-AE`, lane 3)

- **`TransitionGroup<Content>` is layout- AND identity-TRANSPARENT**
  (`AN-AH` item 4, replacing the design's one-identity-level shape):
  `EnvironmentScope`'s and `TransactionScope`'s shape, consuming no cursor
  index. Its captures and progress live in the `AnimationStore` under
  `.named("$transition")` below `.child(of: parent, at: cursor)` — the
  position it sits at, `.animation(_:value:)`'s keying — so adding or
  removing `.transition` moves **no** id and resets no `@State`, focus or
  `$anim` baseline, as in SwiftUI, where a modifier carries no identity. No
  migration note is owed. Its typed `ProposalElementGroup` entry is a copy of
  the untyped one with its own pin (3.20's proposal arm).
- **Only the outermost group of content a conditional or loop inserts or
  removes transitions** (X15, X15b): an `if`'s content, an `if`/`else`/`switch`
  branch, a `ForEach` element or a `for` iteration whose group is the content
  itself (through transparent wrappers). A nested `.transition` is inert.
- **Insertion** is detected at layout time, and only against a conditional
  **evaluated in the last completed frame** (`AN-AH` item 2): an `if` whose
  slot was evaluated absent last frame and is produced now, an `EitherGroup`
  whose other branch was taken last frame, a `ForEach` key or loop index
  absent from a loop evaluated last frame. **Content in the first render,
  content inside a newly evaluated parent (nested content — X15 — and a `List`
  row entering its window, `TB-AH`) and a returning `List` row are not
  insertions** — probe X17 (a first render under a forced animation runs no
  transition; X17c separates). Every recording copy (`OptionalGroup`,
  `EitherGroup`, `ArrayGroup` untyped and typed, `ForEach`'s two entries)
  notes its evaluation and transaction; each gets an arm in 3.23. **Removal** is the evaluated-removal set the
  sweep already computes — `noteAbsent`'s slots, the loop tails and names
  `queueLoopResets` drops, and departed names — **read before paint** through
  a non-mutating `StateTable` query lane 3 adds. A `List` row leaving its
  window is not a removal (`TB-AH`; 3.17).
- **The transaction is the one in effect at the conditional**, recorded when
  the conditional notes its slot (X13, X14), not the one at the group. No
  animation → the insertion or removal is instant (X1n).
- **Insertion** paints the group's content with the transition's active state
  moving to identity over the animation: `.opacity` through `PaintPass.opacity`,
  `.move`/`.slide`/`.offset`/`.push` through a paint-time translation
  (`clipped(to:offsetBy:)` with the active clip), `.move`'s distance the
  group's **own** laid-out size (X2). **`.scale`** (X4, X4a; `AN-AH` item 1)
  post-transforms the scene range the group emitted this frame: every
  primitive's `bounds` scales about the anchor point of the group's laid-out
  rect (default `.center`), with a rect's corner radii and border widths
  scaled by the same factor; a `contentMask` equal to the clip in effect at the
  group's entry stays (the container still clips), a narrower one — set inside
  the group — scales with its content. A glyph resamples the atlas (bilinear,
  `glyph_vertex`'s independent `atlasPosition`), so it is soft mid-flight and
  exact at identity. Lane 3 reads `Backends/SDL`'s glyph shader first and, if
  it does not interpolate the atlas position the same way, stops and reports
  (a ruling, not a silent macOS-only transition). Hit testing, focus and accessibility use
  the final geometry: hitboxes are never translated (3.18; SwiftUI's
  mid-transition hit behaviour is unmeasured and not claimed).
- **Removal** paints a **ghost**: every frame, a group records the primitives
  its content emitted (rects, glyphs, images, with their layer and order) in
  the `AnimationStore`'s transition store; on removal the last capture is
  re-emitted each frame at its last position with the removal transition
  applied (alpha multiplied, bounds offset or scaled by the rule above),
  until the animation finishes. A
  ghost registers no hitbox, no focus, no accessibility node and no `@State`
  (its content's entries are reset as `ID-C`/`DD-C` already reset them). It
  draws with the paint order it last had. Siblings move at once (divergence
  96's X00 half).
- **Reduce Motion**: when `accessibilityReduceMotion` is true at the group
  (captured with the ghost for a removal), every transition but `.identity`
  resolves to `.opacity` (R5…, `.scale` included — R5s; R10 the controls).
  The value is read from the environment in layout, never written from a
  phase; a platform change dirties the window (1.13), so the next frame reads
  it.
- **No default transition**: without `.transition`, insertion and removal are
  instant — divergence **98**, kept, owner none (SwiftUI cross-fades by
  default, X0; giving every conditional a ghost would make every conditional
  capture its primitives every frame).
- **Liveness**: an insertion in flight and every live ghost call
  `noteActiveAnimation()`; a tree with no `.transition` captures nothing
  (`TransitionStore.lastFrameCapturedPrimitives == 0`, 3.16).
- **A removal during an insertion** starts the ghost from the insertion's
  current progress (MetalUI's own choice, stated; unprobed).

## 7. Lanes — AT MOST THREE, run in order 1, 2, 3 (`AN-AG`)

Files are disjoint. The one seam is deliberate: lane 1 creates
`TransitionStore.swift` as a stub (the type, three no-op hooks and the frame's
three call sites) and never touches it again; lane 3 owns it from then on.
Every lane: build with `--build-system native --build-tests`, run the suite
unfiltered, read the summary line, 0 `error:`, the one `warning:` the
deprecation notice; every new test red first (or "does not compile" first,
the prior specs' precedent), every mutation in the tables applied after a
commit, restored from a copy, full unfiltered suite, `git status --short`
after, every reddened test named. No test sleeps: every animation test
drives `simulateTick(timestamp:)` (or a `Frame` timestamp in a headless
render).

### Lane 1 — transactions, the store, Reduce Motion, the platforms

**Files**: `Animation.swift`, `Transaction.swift` (new), `AnimationScope.swift`
(new), `AnimationStore.swift` (new), `TransitionStore.swift` (new, stub —
then lane 3's), `Binding.swift`, `Frame.swift`, `Window.swift`, `Passes.swift`,
`RenderFrame.swift`, `EnvironmentValues.swift`,
`Sources/MetalUIPlatform/Platform.swift`, `Sources/MetalUIAppKit/AppKitPlatform.swift`,
`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`; tests
`TransactionTests.swift` (new), `ReduceMotionTests.swift` (new),
`TransactionCompileGuards.swift` (new), `Tests/MetalUIPlatformTests/AppKitReduceMotionTests.swift`
(new), `Tests/MetalUITests/Fakes.swift`, `ControlStateCompileGuards.swift`'s
`Conformer` (it must gain the new pair to keep compiling), the SDL test
target.

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `withTransactionAnimatesAChangeAsWithAnimationDoes` (T5) | does not compile | `withTransaction` parks `nil` |
| 1.2 | `aTransactionWithNoAnimationSnaps` (T5n) | does not compile | a `nil` animation parks `.default` |
| 1.3 | `anAnimationModifierAnimatesOnlyWhenItsValueChanges` (T1, T2) | does not compile | drop the value comparison (always push `anim`) — the T2 arm |
| 1.4 | `anAnimationModifierReachesOnlyItsContent` (T3, T3b; legacy and proposal arms) | does not compile | never pop the pushed transaction — the sibling arm; skip the typed entry's push — the proposal arm |
| 1.5 | `anAnimationModifierOverridesTheExplicitTransaction` (T4, T4n) | does not compile | keep the explicit animation when the root has one |
| 1.6 | `disablesAnimationsSuppressesOnlyTheAnimationModifier` (T8, T8b, T8c) | does not compile | ignore `disablesAnimations` (T8, T8b arms); let it also clear the explicit animation (T8c arm) |
| 1.7 | `aTransactionModifierRewritesItsSubtreesAnimation` (T6, T7, T7c) | does not compile | apply the transform only when the root has an animation (T7c arm) |
| 1.8 | `theAnimationModifierAppliesInPaintAsInLayout` (a `Box`'s width and background under `.animation(A, value:)`) | does not compile | skip the push in `paintGroup` — the colour arm |
| 1.9 | `aBindingAnimationAnimatesAStateWrite` (T11s, T12s) | does not compile | `animation(_:)` returns `self` unchanged |
| 1.10 | `aClosureBindingIgnoresItsTransaction` (T11) | does not compile | apply the transaction to every binding's write |
| 1.11 | `twoAnimationScopesAtOnePositionKeepSeparateValues` | does not compile | drop the depth from the store key |
| 1.12 | `anAnimationScopeStoresNoStateTableEntry` (`StateTable` count equal with and without the scope) | does not compile | store the value in `StateTable` |
| 1.13 | `theWindowStampsReduceMotionFromItsPlatformWindow` (construction value; a change redraws and restamps; `Window.environment` cannot override it) | does not compile | omit the stamp; do not wire the callback (second arm) |
| 1.14 | guard `aScopeCannotWriteReduceMotion` (plain import: `.environment(\.accessibilityReduceMotion, true)` fails, a read compiles) | — | make the setter `public` — mutate once red |
| 1.15 | guard `aPlatformWindowWithoutTheReduceMotionPairDoesNotCompile` | — | give the pair a default in an extension — mutate once red |
| 1.16 | `propertyAnimationsRunUnchangedUnderReduceMotion` (R3, R4, R6 — R4 read as a background fade until lane 2 animates opacity, `AN-AI` item 2) | does not compile | snap every helper when the root reads Reduce Motion |
| 1.17 | `theAppKitWindowReadsReduceMotionFromNSWorkspace` (in-process swizzle of the getter, restored in a `defer`; the notification fires the callback) | does not compile | observe a different notification |
| 1.18 | SDL: `anSDLWindowReportsNoReduceMotion` | does not compile | answer `true` |
| 1.19 | `aFrameBuildIsPendingDoesNotPruneTheRegistry` | does not compile (new hook); "reads the pruned count" is M1.19, `AN-AI` item 3 | put the prune back into the getter |

Also: correct `Animation.swift`'s `112.5` after re-running mutation 33 (drop
`|| previouslyParked != nil`) on this tree, and measure the mechanism (read the
unrounded interpolated value; the hypothesis is divergence 77's whole-point
rounding). **Must not move**: `AN-C`'s three clauses (mutations 28–34
re-run, each reddening what the animation decisions doc's table says),
`theSevenRetentionSlotsAreMutuallyDistinct`, every `$anim`/`$anim-color` test.

**Landed** (`AN-AI`): 1898 tests (+16 tests, +2 guards), `Backends/SDL` 22 +
33 (+1); every mutation above reddens its test, `AN-C`'s 28–34 re-taken;
`112.5` measured as 112 by whole-point edge rounding (`Animation.swift`
corrected; the two `AnimationTests.swift` lines stay lane 2's).

### Lane 2 — modifier wrappers at their phase

**Files**: `ModifiedContent.swift` (the proposal arm), `ProposalAnimation.swift`
(new: the proposal layer and component-op helpers over `AnimationStore`),
`AnimatedStyle.swift`, `AnimatedColor.swift`, `Component.swift`; tests
`ModifierAnimationTests.swift` (new), `AnimationTests.swift`,
`DecorationPaintTests.swift` (`AXNodeTests.swift` is **not** touched since
`AN-AH` item 3: the seven reserved names stand).

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 2.1 | `aProposalFrameAnimatesItsWidthUnderATransaction` (W1: 100→300 linear 1 s reads 200 at 0.5 s) | reads 300 | skip the helper for `.frame` |
| 2.2 | `aProposalPaddingAnimatesItsInsets` (W2) | snaps | skip it for `.padding` |
| 2.3 | `aProposalFlexibleFrameAnimatesAFiniteBoundAndSnapsAnInfiniteOne` (W7) | snaps | interpolate across finite ↔ infinite (a non-finite rect traps, `SA-K` — the lane pins the snap instead) |
| 2.4 | `aProposalOpacityAnimates` (W3) | snaps | skip it for `.opacity` |
| 2.5 | `aProposalBackgroundFadesItsTokenAndReResolvesOnAThemeSwap` (W4) | snaps | store the resolved colour instead of the token (`AN-H`'s mutation 25 shape) |
| 2.6 | `aProposalBorderAnimatesItsColourAndWidth` (W5, W5c) | snaps | skip the width; skip the colour |
| 2.7 | `aProposalClipAnimatesItsCornerRadiusInPaintAndHitTesting` | snaps | prepaint reads the declared radius |
| 2.8 | `everyAnimatableProposalModifierAnimates` (one arm per animatable case) | reds | remove any one case's helper call — exactly its arm (take `.padding`) |
| 2.9 | `aProposalModifierReturningInsideAnIfSnaps` | — (green-first; pin) | keep untouched entries across a frame |
| 2.10 | `aProposalAnimationKeepsTheDisplayLinkAwakeUntilItSettles` | — | omit `noteActiveAnimation()` |
| 2.11 | `aProposalTreeMintsNoStateTableEntryForItsModifiers` | — (its store-count set-up only; the table arms are the pin, `AN-AJ` item 5) | store proposal baselines in `StateTable` |
| 2.12 | `aSettledProposalTreeInterpolatesNothing` (`AnimationStore.lastFrameInterpolations == 0` on steady frames; `n` while `n` layers move) | — | interpolate every frame |
| 2.13 | `thePaintOnlyDecorationFieldsAnimateAndClipSnaps` — **renamed from** `theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate` (answer flipped by `AN-AA`; the background control kept) | the old test | drop opacity from `animated()`; drop a border width; route the border colour around its `AnimationStore` track — three mutations, each its arm |
| 2.14 | `aBorderFadeDoesNotRetargetTheBackgroundFade` | — | key the border track on the `$anim-color` entry |
| 2.15 | `theBorderColourTrackMintsNoStateTableEntry` (new, `AN-AH` item 3; a bordered `Box` under a colour change: `StateTable` count equal with and without the border, the fade still read at mid-flight) | — | store the track in `StateTable` under a named child |
| 2.16 | `aHoverBorderFadesItsResolvedColour` (through a real `Window`, genuinely hovered) | snaps | resolve the border track from the plain field only |
| 2.17 | `aComponentsCallerModifierAnimates` + arm (c) of `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` re-derived (B-7) | snaps | drop the op interpolation — both |
| 2.18 | `aComponentsOpsAnimateEachMemberSeparately` | — | key without the member index |
| 2.19 | `aProposalFrameReLaysItsChildAtEachIntermediateWidth` — pins divergence **96** wrong on purpose (a child `ProposalLayout` is proposed intermediate widths; SwiftUI's P1 sees only 300) | — | lay out at the final value (M2.1; `AN-AJ` item 5 — "interpolate the placed rect" has no mechanism to substitute) |

Also in `AnimationTests.swift`: the `try #require` that no live window is
dirty at the top of `aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`;
the two `112.5` lines corrected to lane 1's measured value; mutation 16
re-taken (delete 25 of the 28 field assignments) and its figure handed to the
Record phase; every retention payload's `MemoryLayout` stride recorded at its
line. **No `StateTable` count moves in this lane** (`AN-AH` item 3): a test
pinning a table count that moves is a defect to stop on, not a literal to
re-derive.

**Landed** (`AN-AJ`): 1919 tests (+18), guards unmoved; every mutation above
reddens its test (the table is `AN-AJ` item 9); no `StateTable` count moved;
0 px against `2de0973`; `Box.swift` gained `Decoration.setInterpolatedOpacity`
(item 3); mutation 16 re-taken as 21 of 24, 52 issues in 15 tests (item 6).

### Lane 3 — transitions and the surface

**Files**: `Transition.swift` (new), `TransitionGroup.swift` (new),
`TransitionStore.swift` (fills lane 1's stub), `StateTable.swift` (the
non-mutating insertion/removal query), `ElementGroup.swift` and `ForEach.swift`
(record the evaluation and the transaction at the conditional/loop, every
copy); tests `TransitionTests.swift` (new), `TransitionCompileGuards.swift`
(new). Reads (does not edit) `Backends/SDL`'s glyph shader for `.scale`
(§6.5).

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 3.1 | `anOpacityTransitionFadesAnInsertedElementIn` (X1: alpha 0 on the starting frame, ½ at mid, 1 at end) | does not compile | skip insertion |
| 3.2 | `anOpacityTransitionFadesARemovedElementOut` (the ghost at its last place, no hitbox, no AX node; gone after) | does not compile | capture nothing (no ghost); register the ghost's hitbox |
| 3.3 | `aMoveTransitionOffsetsByTheElementsOwnSize` (X2, X3, X3t, X3b — four edges) | does not compile | use the container's size |
| 3.4 | `aSlideTransitionEntersLeadingAndLeavesTrailing` (X5) | does not compile | remove toward leading |
| 3.5 | `offsetAndPushTransitions` (X9, X10 both directions) | does not compile | drop `.push`'s opacity |
| 3.6 | `anAsymmetricTransitionUsesEachSide` (X6) | does not compile | swap insertion and removal |
| 3.7 | `aCombinedTransitionAppliesBoth` (X8) | does not compile | keep only the first |
| 3.8 | `anIdentityTransitionIsInstant` (X7) | does not compile | treat identity as opacity |
| 3.9 | `aTransitionWithoutATransactionIsInstant` (X1n) | does not compile | default the animation |
| 3.10 | `forEachInsertionAndRemovalTransition` (X11, X12) | does not compile | skip the loop's insertion noting |
| 3.11 | `aTransitionUsesTheTransactionAtItsConditional` (X13, X14) | does not compile | read the transaction at the group — the X14 arm |
| 3.12 | `aNestedTransitionIsInert` (X15b) | does not compile | let every group inside inserted content transition |
| 3.13 | `anUnannotatedInsertionAndRemovalAreInstant` — pins divergence **98** wrong on purpose | green (today's answer) | give an unannotated conditional's content a default `.opacity` transition (`AN-AH` item 6: the design named 3.12's mutation, which cannot redden a tree with no `.transition`) |
| 3.14 | `underReduceMotionEveryTransitionButIdentityIsAnOpacityFade` (R5…, R10 control) | does not compile | no substitution; substitute `.identity` too |
| 3.15 | `aTransitionKeepsTheDisplayLinkAwakeThenLeavesNothing` | does not compile | omit `noteActiveAnimation()` |
| 3.16 | `aTreeWithoutTransitionsCapturesNothing` (`demoContent()` and a fixture: 0, and exactly the group's primitives) | does not compile | capture at every element |
| 3.17 | `aListRowScrolledOutOfItsWindowRunsNoRemovalTransition` | does not compile | ghost any group not produced this frame |
| 3.18 | `anInsertingElementIsHitTestedAtItsFinalPlace` | does not compile | translate its hitboxes |
| 3.19 | guard `theUnsupportedTransitionsDoNotCompile` (plain import: `AnyTransition.blurReplace` fails, `.opacity` and `.scale` compile) | — | add a `blurReplace` — mutate once red |
| 3.20 | `aTransitionTakesNoIdentityLevel` (`AN-AH` item 4: adding `.transition` around a `@State`-holding element keeps its value; legacy and proposal arms) | does not compile | give the group an identity level — the legacy arm; the same in the typed proposal entry only — the proposal arm |
| 3.21 | `aRemovalDuringAnInsertionStartsFromItsCurrentProgress` | does not compile | restart the ghost from the removal's start value |
| 3.22 | `contentInTheFirstRenderOrANewlyEvaluatedParentIsNotInserted` (X17: frame 0 under a `.transaction` forcing an animation; a `List` row with a `.transition`ed `if` scrolled into its window; nested content under an inserted `if` — none transitions; X17c's toggle-after-appearance control does) | does not compile | treat "not produced last frame" as an insertion without the evaluated-last-frame check — the frame-0 and `List` arms |
| 3.23 | `everyConditionalSiteRecordsItsTransaction` (one arm per recording copy: `OptionalGroup`, `EitherGroup`, `ArrayGroup` untyped and typed, `ForEach`'s untyped and typed entries) | does not compile | skip the note in any one copy — exactly its arm (take the typed `ArrayGroup`) |
| 3.24 | `aScaleTransitionScalesTheGroupsPrimitivesAboutItsAnchor` (X4, X4a: a 50×30 rect with a glyph child reads scale ½ at mid-flight about the centre, `.topLeading` about its corner; an outer clip unscaled, an inner one scaled; hitboxes unscaled) | does not compile | scale about the container's rect; scale the entry clip too |

Also: **the supported-transition surface is documented** on `AnyTransition`'s
public doc comment (supported, with the probe arm for each; unsupported, with
the reason for each; the Reduce Motion rule; the no-default rule) — the
source is the authority; the Record phase copies it into `CLAUDE.md` and
`README.md`.

## 8. The demo

**Unchanged.** No demo tree gains a transition, a transaction scope or a new
animation, so the fourteen offscreen images (`docs/probes/demo-pixels/compare.sh`)
read **0 px against `2de0973`** at every lane, `DemoFrameDeterminismTests`'
`Expected.swift` is unedited, and `everyProductionTreeBuildsOnAOneMegabyteThread`
stays green. The demo's existing **A** press (`withAnimation(.spring…)`) runs
through the new transaction stack unchanged. A lane that moves a pixel stops
and reports; it is a ruling, not a re-record.

## 9. The plan's clauses

| clause | closed by |
|---|---|
| modifier wrappers participate in transactions at their correct phase | lane 2 (legacy paint-only fields, proposal layers, component ops) on lane 1's transaction stack and `.animation(_:value:)`/`.transaction` |
| environment-driven Reduce Motion | lane 1 (environment, platforms), lane 3 (what it changes: transitions) |
| document the supported transition surface | lane 3 (`AnyTransition`'s doc comment), the Record phase (`CLAUDE.md`, `README.md`) |
| retain the layout/paint distinction | §6.3's phase rule; `AN-F` untouched |
| timestamps, not sleeps | every test drives `simulateTick(timestamp:)` |

## 10. For the Record phase

Divergences **96–99 added** (68 → 72 live, next label **100**; the critic
round added none and retired none): 96 geometry vs
input interpolation (P1, P2, X00, W11), 97 what still snaps where SwiftUI
animates (§6.3's list), 98 no default transition (X0, W10), 99 one
transaction per build (T9, T10). None retires. Declared-but-inert: no row
added; `EnvironmentValues.accessibilityReduceMotion` is read by the
transition code, so it is not inert. Record §03: the transitions and Reduce
Motion's cross-fade are looks a human owes (the real-window capture, per the
lock probe) — `.scale`'s soft mid-flight glyphs among them. The decisions
doc's row 16 and the animation spec's §3 caveat (§3 items 11, 12).
`CLAUDE.md`'s "Animation (`AN-`)" snap list, the reserved names (**still
seven**, `AN-AH` item 3), the environment paragraph (Reduce Motion beside
`controlActiveState`) and a transitions paragraph.

## 11. Counts (expected, re-measured by each lane)

Baseline `2de0973` (this session): **1880 / 0 goldens / 116 guards** (a
guard is a `@Test` and counts in the 1880). Expected additions, each lane
re-measuring: lane 1 **+18** in the root package (16 tests — 1.1–1.13, 1.16,
1.17, 1.19 — and 2 guards, 1.14, 1.15), and 1.18 in `Backends/SDL`; lane 2
**+18** (2.1–2.12, 2.14, 2.15, 2.16, 2.18, 2.19 and 2.17's
`aComponentsCallerModifierAnimates`; 2.13 is a rename, 2.17's arm a
re-derivation); lane 3 **+24** (23 tests — 3.1–3.18, 3.20–3.24 — and guard
3.19). So about **1940 / 0 / 119**, each lane's own figure authoritative over
this estimate (the critic round's `AN-AH` moved lane 2 from +17 and lane 3
from +21).
