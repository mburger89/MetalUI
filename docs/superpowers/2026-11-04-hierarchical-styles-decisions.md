# Hierarchical styles (round 4 item R4-4 PR A) — decisions (prefix `HY-`)

Rulings for divergence 119 (retired). Branch `feat/hierarchical-styles`, on `docs/r4-3b-line-height` (9896b343). Record 213. Evidence: the probe `docs/probes/swiftui-hierarchical-paint.swift` (arm ids below; run twice, byte-identical, 2026-11-04, macOS 27.2, Swift 6.4.2) and its sibling `swiftui-colour-hierarchical.swift` (the inferred TYPE, `CR-U`). Next unused id: `HY-F`.

## HY-A: a level is a factor of the parent style

1. **`HierarchicalShapeStyle`** (public, `.primary`/`.secondary`/`.tertiary`/`.quaternary`/`.quinary`, on the type and on `ShapeStyle where Self == HierarchicalShapeStyle`, as SwiftUI's) is a `ShapeStyle` whose `resolve(in:)` is the level over the environment's inherited `foregroundStyle`.
2. **Over a parent**, the level is the parent at alpha 1 / .5 / .25 / .18 / .18, the same in both schemes (`RL1`..`RL5`, `RD1`..`RD5`; the parent's own opacity multiplies, `P10`). **Over nothing** it is the theme's text colour at 1 / .588 / .306 / .116 / .0555 light and 1 / .648 / .292 / .116 / .0555 dark: SwiftUI's label alphas (`NL`, `ND`: .847 / .498 / .259 / .098 / .047 and .847 / .549 / .247 / .098 / .047) divided by the primary's .847, because MetalUI's text colour is the theme's opaque token (divergence 116) and `Color.secondary` already used .588 and .648.
3. **Levels do not compound** (`P7`, `P8`): a level written over a level replaces it. Stored as `Color.Provider.hierarchical(Level, over: Color?)`, `over` being the parent with any level stripped (`Color.init(level:over:)`).
4. **`Color.secondary` is not a level** (`P6`, `P6d`, the separating arm): under a red parent it stays the grey. So are `foregroundColor(.secondary)` (a `Color?` parameter) and a `Color` value.
5. Not built, carried in `SS-G`: `foregroundStyle(_:_:)` (probes `P11`..`P13c`: a level SELECTS the n-th style and a level past the last repeats it), the instance members `ShapeStyle.secondary` (`T9`, `T9b`), and `overlay(_ style:)`: **MetalUI's `overlay` takes only a builder, so SwiftUI's `S5` (`overlay(.secondary)`) has no spelling**; `overlay { Rectangle().fill(.secondary) }` is the `S1` arm.
6. `HierarchicalShapeStyle` is `Equatable`, which SwiftUI's is not: `AnyShapeStyle` compares an erased custom style only when it is `Equatable`, and a style that equals nothing makes a retained subtree repaint. Not `Hashable`. Mapped as an extra.

## HY-B: where the parent is read (a deviation from the plan, which put it in `resolveTextStyle`)

1. **In the one colour-resolution functions** (`CR-H`: `Frame.resolve`, `ColorContext.resolve`, `Color.resolve(in:)`), not in `resolveTextStyle`. A `.hierarchical(level, over: nil)` colour reads the position's inherited `foregroundStyle` (stripped of its level) and only then falls to the theme; every other colour reads nothing (one tag test, `Color.readsInheritedStyle`).
2. Why: `Text`, a legacy `Box` fill and border, a proposal `.background(Color)` and `.border(Color)` all store a `Color` before any environment exists. Reading the parent where the colour is resolved reaches every one at once, including `S4` and `S6` (background, border) that a text-only rebase misses. A colour that is stored by an environment WRITER takes its `over` at the write (`ElementGroup.foregroundStyle`'s `shapeStyleStorage(style, in:)` sees the parent), so no stored `foregroundStyle` reads its own scope.
3. `ColorContext` gained `inherited`; `TextMeasurer` and `SurfaceText` pass it (the latter resolves through the context rather than `Color.resolved` directly).
4. No new environment key, so no fingerprint row (`TM-G`): `Color`'s `Hashable` already feeds `foregroundStyle` in the fingerprint, and a changed parent changes the stored `over`.

## HY-C: the overload mechanism (replaces the plan's)

1. **No sink's overloads changed.** `Color.primary` and `Color.secondary` are `@_disfavoredOverload` statics, and `ShapeStyle where Self == HierarchicalShapeStyle` has the five statics. `.foregroundStyle(.secondary)` then has a `Color`-overload solution carrying one disfavoured member and a generic `S == HierarchicalShapeStyle` solution carrying none; the generic wins on score. `.red`, `.accentColor` and `.textPrimary` have no such competitor and bind as before; an explicit `Color.secondary`, a `Color` value and `foregroundColor(.secondary)` have only `Color` to pick. `SS-A` item 3's fast path is untouched for every real `Color`.
2. **The plan's design (disfavour every sink's `Color` and generic overload, add a concrete level overload) was built and refuted in the real modules**: every leading-dot token that exists on both `Color` and `ColorToken` (`.surface`, `.background`, `.accent`, `.separator`, `.textPrimary`) tied between the disfavoured `Color` overload and the already-disfavoured `ColorToken` twin ("ambiguous use of" at `ClipShape.swift`, `MenuBarStrip.swift`, `ToolbarStrip.swift`, `WindowControlsStrip.swift`). Its skeleton had not modelled the token twins.
3. The guard `everyHierarchicalOverloadArmTypechecksWithoutAmbiguity` (plain import, Swift 6) covers every sink and spelling, the ternaries included. A typecheck cannot see which overload bound, so `HierarchicalStylePaintTests` pins the binding by pixels.

## HY-D: what a sink reads

`fill`, `stroke`, `strokeBorder`, `background(_:)`, `background(_:in:)`, `border`, `foregroundStyle` on a group, a `Text` and a `ProposalText`, and a bare shape's default fill all read the parent (`S1`..`S4`, `S6`, `T2`, `T3`, `T6`). A legacy `Box` fill or border, which stores its colour before any environment exists, resolves the level at paint (`HY-B`). A gradient parent reaches a level as the gradient with every stop's opacity times the level's factor, as SwiftUI keeps it (`P14l`, `P14r`; built by `TG-B`, record 221, which amends this sentence: it was the first stop under divergence 975); a material parent keeps its representative colour; a `.tint` parent is the tint (`P15`).

## HY-E: unmeasured

A level over an explicit `Color.primary` (or any token) parent; a level on a control's own label colour inside a built-in control (no built-in paints a level); whether SwiftUI's level applies to a `Material` parent. In MetalUI a token parent resolves to its colour and takes the over-a-parent factors.
