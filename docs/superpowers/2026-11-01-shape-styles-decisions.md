# Shape styles and the tint — decisions (prefix `SS-`)

Rulings for round 3, item R3-9: `ShapeStyle` as a public protocol, `AnyShapeStyle`, `TintShapeStyle`, `.tint(_:)` and
`Color.accentColor` following it. Branch `feat/shape-styles` from master `3a2c5715`. Code: `Sources/MetalUI/ShapeStyle.swift` (new),
`Color.swift`, `ControlLook.swift`, `EnvironmentValues.swift`, `ShapeView.swift`, the control files. Tests: `ShapeStyleTests.swift`,
`ShapeStyleCompileGuards.swift`, `RetainedShapeStyleTests.swift`. **Next unused: `SS-H`.** Divergences 975–977 (reserved 975–984;
978–984 unused). Supersedes the "not built" row for `ShapeStyle`, `AnyShapeStyle`, `.tint(_:)` and `.accentColor(_:)` in
`docs/divergences.md` (rule `CR-A`, colour spec §10); `HierarchicalShapeStyle` stays unbuilt (divergence 119, `SS-G`).

## SS-A: the design

1. **`ShapeStyle` is SwiftUI's protocol**: `associatedtype Resolved: ShapeStyle` and `func resolve(in: EnvironmentValues) -> Resolved`,
   `Sendable`. `Color` (its `Resolved` is the existing `Color.Resolved`, which conforms too), `LinearGradient`, `RadialGradient`,
   `Material`, `TintShapeStyle`, `AnyShapeStyle` and the opaque `ResolvedShapeStyle` conform. There is no `ImagePaint` and no
   `HierarchicalShapeStyle` to conform.
2. **The closed resolved form is internal**: `ShapeStyleStorage` is `.color(Color) / .gradient(GradientFill) / .material(Material)`, the
   three paint paths MetalUI already has. A built-in adopts an internal `PrimitiveShapeStyle` (`storage`) and resolves without an
   environment; a `Color` stays a `Color` (its token, dynamic, palette and accent providers resolve at paint against the position's theme,
   scheme and tint) so the colour sites keep their fast path and their retained keys. `ResolvedShapeStyle` wraps a storage and has no
   public initialiser or member.
3. **Concrete overloads stay.** Every `fill`, `stroke`, `strokeBorder`, `background`, `border`, `foregroundStyle` and `background(_:in:)` keeps
   its `Color`, gradient and `Material` overload (and the `ColorToken` twin) and gains one `some ShapeStyle` overload beside it. Overload
   resolution prefers the concrete one, so no existing call site changes meaning (the whole tree, demos and examples, builds unchanged).
   The generic overload is what `AnyShapeStyle`, `.tint` and a custom style bind to. `ShapeView` gets `.styleFill`, `.styleStroke` and
   `.styleStrokeBorder` layers holding an `AnyShapeStyle`, resolved in `pass.frame.environmentTop` (no counted snapshot) at paint, then
   routed to `paintShapeFill` / `paintGradientFill` / `paintShapeMaterial` / `paintStyledStroke` / `paintGradientStroke`.
4. **`ShapeStyle` statics on `Color`** (`.fill(.red)` through the generic arm, `let s: some ShapeStyle = .red`) are **not offered**: the
   concrete `Color` overload already binds `.red`, and a second family of `ShapeStyle where Self == Color` statics buys only the
   standalone spelling (carried, `SS-G`).

## SS-B: who may conform

A third party **may conform, by composition only**, as in SwiftUI: `resolve(in:)` returns an existing style (a `Color`, a gradient, a
`Material`, `.tint`'s `TintShapeStyle`, `AnyShapeStyle` or another custom style), and MetalUI follows the chain against the environment of
the place it is painted (`shapeStyleStorage`, at most 32 steps; a style that resolves to itself traps with a message). A conformer cannot
make a primitive: `ResolvedShapeStyle` has no public initialiser and `PrimitiveShapeStyle` is internal. Every style is usable generically
(`func f(_ s: some ShapeStyle)`). Pinned by the plain-import guard `aThirdPartyModuleCanUseAndComposeShapeStyles` (positive arm: conform, compose,
erase, use at every site; negative arms: a non-style `Resolved`, a forged `ResolvedShapeStyle`, a non-style argument).

## SS-C: the sinks

1. `Shape.fill/stroke/strokeBorder` and `ShapeView`'s, `background(_:in:)`: resolved at paint (item 3 above). A gradient stroke is the
   CPU-stroked gradient (`LK-J`); a gradient `strokeBorder` strokes the shape inset by half the width; a material stroke draws its flat
   tint.
2. **Builder-time sinks resolve before any environment exists.** A `Box`'s decoration (`StyledElement.background`, `.border`), a `Text`'s
   own colour and a proposal-layout `.border` store a `Color`, a gradient or a material at the builder. A primitive style lowers exactly (a
   `Color` including `.tint` keeps following the environment at paint); a custom composition resolves in a bare `EnvironmentValues()`
   there (divergence 976). The proposal-path `background(_:)` generic is `background(style, in: Rectangle())`, which resolves at paint.
3. **A colour-only sink takes a representative colour** from a style that is not a colour: a gradient its first stop, a material its flat
   tint (`ShapeStyleStorage.representativeColor`). Sinks: `foregroundStyle` (text and the default fill, the environment's `foregroundStyle`
   is a `Color?`), `border`, `tint` (divergence 975).
4. `foregroundStyle(_:)` on a scope resolves against the environment at the scope (inherited tint, scheme), at layout, in the transform.

## SS-D: the tint

1. `EnvironmentValues.tint: Color?` (internal, as SwiftUI has no public key), written by `.tint(_ color: Color?)` and `.tint(_ style: S?)` on an
   element group; the nearest writer wins and `nil` removes an outer tint. A stored field of a public type: `swift package clean`. It is a
   field of `EnvironmentFingerprint` and is named `tint` in `differences(from:)`, so a retained subtree and the layout memo miss on a tint
   change and hit on an equal one (`RetainedShapeStyleTests`).
2. **`Color.accentColor` follows the tint**: a new colour provider that resolves the environment's tint, else the theme's `accent` (`Color.resolved(theme:scheme:tint:)`,
   `ColorContext.tint`, `Frame.resolve`, `Color.resolve(in:)`, `TextMeasurer`'s and `drawText`'s colours). The tint resolves with no tint of its
   own, so `.tint(.accentColor)` is the theme accent and cannot loop. **`Color.accent` and `ColorToken.accent` stay the theme's
   token**, ignoring the tint (`ColorToken` is the theme's vocabulary, divergence 116). `accentColor(_:)` is offered deprecated, as in SwiftUI.
3. **The built-in controls read one function**, `controlAccent(_:)`, now returning a `Color`: the key window's `environment.tint ?? Color(.accent)` (the
   token itself when untinted, so no pixel and no equality moves), `.separator` otherwise (`IX-H`: an inactive window shows no tint). Readers:
   `Button .borderedProminent` (fill; its label stays white), `Toggle` (checkbox, switch and button), `Slider`, `ProgressView`
   (bar, sweep and ring), a radio `Picker`'s selection and every focus ring. Also following the tint, without the inactive rule: a `List`'s
   selected row, `TextField`/`TextEditor` selection, a link run and `.link` button (via `Color.accentColor`) and `.glassProminent`.
4. **Surfaces drawn from the theme alone keep the theme accent** (menu highlight, drawn menu bar, alert default button and ring, scroll
   chrome): they have no environment at their paint (divergence 977).
5. `TintShapeStyle` (`.tint`) is the style spelling of `Color.accentColor`.

## SS-E: `AnyShapeStyle`

A struct holding either a primitive storage or a box around a custom style. `init(_:)` is idempotent (wrapping an `AnyShapeStyle` keeps its
form) and lowers a built-in to its storage, so a wrapped `Color` paints on the `Color` path. It is `Equatable`, which the `ShapeView` layer
array needs: equal primitives are equal; two custom boxes are equal when the same box, or when the wrapped value is `Equatable` and equal to the other
(same dynamic type); a non-`Equatable` custom style equals nothing but itself, so a retained subtree holding one repaints rather than
serving a stale hit. It is `@unchecked Sendable` (the box holds a `Sendable` style and an immutable closure).

## SS-F: the Windows and stack rules

No generic recursion in a `Component`'s content: `shapeStyleStorage` is a loop over `any ShapeStyle`, the layers are an enum, and no
protocol of the new code nests a loop in a container inside a `Component` (`LK-X`, `SG-E`). Nothing here deepens a tree frame.

## SS-G: carried

`HierarchicalShapeStyle` (`.primary` … `.quinary`, divergence 119: `.foregroundStyle(.secondary)` is still `Color.secondary`);
`foregroundStyle(_:_:)` and `(_:_:_:)`, which need it; `ForegroundStyle`/`.foreground`; `ImagePaint`; the `ShapeStyle where Self == Color`
statics (`SS-A` item 4); `AngularGradient`/`EllipticalGradient`; `ShapeStyle` shadows; a tint reaching the theme-only surfaces
(`SS-D` item 4); `Text` gradient fills.
