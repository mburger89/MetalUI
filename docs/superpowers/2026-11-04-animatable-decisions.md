# `Animatable` on shapes and keyframes (round 4 item R4-3 PR D) — decisions (prefix `VA-`)

Rulings for divergences 947 (retired), 169 (narrowed), 215 and 216 (added). Branch `feat/r4-3-animatable`, on `feat/r4-3-leaver-moves` (PR C, #203). Record 208. Evidence: `XF-C` (`docs/superpowers/2026-11-03-default-transition-decisions.md`) and the probe `docs/probes/swiftui-animatable.swift` (`VT1`..`VT16`, `VA1`..`VA8`, recorded in `swiftui-animatable-run.txt`; `VA6d` was added in this PR and **not run**, the screen being locked on 2026-11-04). `Component & Animatable` is PR E and is not decided here. **Class `A`** (SwiftUI-aligned) with two documented divergences. **Next unused: `VA-I`.**

## VA-A: the isolation of a conformance (the spike, measured in MetalUI)

1. **The protocol is nonisolated**, as SwiftUI's is (`VT`: the SDK interface carries no isolation), so `Double`, `CGFloat` and a keyframe timeline stay free of isolation.
2. **A MetalUI `Shape` is in the position of a SwiftUI `View`, not of a SwiftUI `Shape`**: `Element` and `ProposalElement` are `@MainActor`, so a conformer is main-actor-isolated. Spike arms (typechecked against a plain import in Swift 6 mode, `AnimatableCompileGuards.swift`): **`S1`** `struct S: Shape { var animatableData: Double { get set } }` is an **error** ("conformance of 'S' to protocol 'Animatable' crosses into main actor-isolated code and can cause data races"), unlike SwiftUI's `VT1`; **`S2`** with `nonisolated var animatableData` **compiles** and reads the stored property (so `[PREDICTED]` held); a `nonisolated struct` with the plain spelling compiles; `@MainActor` on the witness does not help. **`S3`/`S4`** (`Component, Animatable`) behave as SwiftUI's `View` (`VT2`, `VT3`): the plain spelling errors, `nonisolated` compiles. `S5` (a shape with no data) and `S6` (`Animatable` generic over the built-ins) compile.
3. **The alternative, measured and not shipped**: marking the `animatableData` requirement `@MainActor` makes `S1` and `S3` compile (and `Double`'s data main-actor), at the cost of putting generic code and the keyframe timeline on the main actor and accepting `S3`, which SwiftUI rejects. The ruling is the nonisolated requirement (`XF-C` 7) with **divergence 215**: a custom `Shape`'s `animatableData` needs `nonisolated`.
4. A stored property of a `Shape` (`TrimmedShape.shape`, `.startFraction`) is main-actor-isolated for a closure that is `@Sendable` (a test helper must be `@MainActor @Sendable`); the `nonisolated` accessor reads them because they are `Sendable` stored properties of the same module.

## VA-B: the surface

1. `Animatable` (`AnimatableData: VectorArithmetic`, `animatableData`), `EmptyAnimatableData`, `AnimatablePair`; `VectorArithmetic.scaled(by:)` is public (`VT12`). Defaults: `where Self: VectorArithmetic` (itself) and `where AnimatableData == EmptyAnimatableData`.
2. Conformers, matching `VT11`: `Double`, `CGFloat`, `Angle`, `UnitPoint`, `CGPoint`, `CGSize`, `CGRect`, `EdgeInsets` (four `CGFloat`s in SwiftUI's order). `Int` and `Color` are not. **`Float` is, a MetalUI extra** (SwiftUI's is a `VectorArithmetic` but not `Animatable`, `VT11`, `VT13`, `VT16`), stated in divergence 169 and the doc comment: removing it would break existing `Float` tracks for no porting gain, and a superset cannot break a port. `Double`, `CGFloat`, `Angle` and `Float` spell `AnimatableData` and `animatableData` out because Foundation exposes SwiftUICore's `Animatable` extensions on `Double` and `CGFloat`, which made the defaulted witness ambiguous.
3. The `@Animatable` macro is not offered (`VT6`, `VT7`): no macro target in this package (`VA-H`).

## VA-C: `Shape: Animatable`

`Shape: ProposalElement, Sendable, Animatable`. Every built-in has `EmptyAnimatableData` (divergence 97 does not move, `RoundedRectangle`'s data is documented in SwiftUI and not built). `any Shape` and `any Shape & Hashable` (`GlassBox`) gained an associated type; every existing member stays usable (the build proves it: MetalCreator's `DimensionLinesShape` and `DimensionArrowsShape` and MetalFlow build unchanged, record 208 section 6).

## VA-D: how a shape's data is interpolated

1. **In PAINT** (`AN-AA`), by `shapeForPaint`, through `animatedVector(_:at:frame:transaction:)` in `ProposalAnimation.swift`. A shape whose `AnimatableData` is `EmptyAnimatableData` returns before touching anything (a metatype comparison, cheaper than the `as? any PaintAnimatedShape` cast it replaces); `PaintAnimatedShape` is deleted.
2. **The track** is a `VectorTrack<V>` in the `AnimationStore` at `layerAnimationKey(id, "animatable")`, never in `StateTable` (no slot, threshold or reserved name moves). A first sighting stores the baseline and returns the declared value. A settled track whose declared value equals its baseline returns before any allocation (`vectorTrackRebuilds` counts the slow path; it is `.frameLocal` in the channel table).
3. **Magnitude**: with `delta = to - from` and `M = |delta|`, the curve is `animation.value(at: t, from: 0, to: M, initialVelocity: 0)` and the result `from + delta.scaled(by: value / M)`. A spring's finishing threshold is `min(0.001 * scale, 0.1667)` of the motion (`Animation.value`), so unit progress would snap a 2000-point motion 2 points short; over `M` it lands within 0.1667. With trim's scale of 128 a whole-range fraction has `M = 128` and a threshold of 0.001 of a fraction, `animatedNumbers`' own. A zero or non-finite `M` snaps. No clamp (trim's `wide` range).
4. In flight it counts one interpolation and notes an active animation (`noteInterpolation()`, `noteActiveAnimation()`), never `requestAnotherFrame()`; a retained occurrence therefore never replays an animatable shape frozen.
5. **A `animatableData` setter must not write an `@Observable`** (a phase-time write is silently stale; doc comment).
6. The setter is called only when the frame's value differs from the declared one, so a settled shape never calls a conformer's setter.

## VA-E: `TrimmedShape` (divergence 947 retired)

`AnimatableData = AnimatablePair<Base.AnimatableData, AnimatablePair<CGFloat, CGFloat>>`, the two fractions **times 128** in the getter and divided in the setter (`VA3a`, `VA3a2`: an end fraction 0 to 1 reads 128, a start 0 to 0.5 reads 64). A power of two, so it is exact. A trim of a trim nests (`VA3e`); a wrapper forwarding the data animates the trim and its base (`VA3d`), one declaring nothing snaps (`VA3b`). The old `$anim-trim` and `$anim-trim.base` tracks are gone, the base's data riding in the trim's.

## VA-F: a retarget restarts at rest (divergence 216)

A retarget starts a new flight over the **whole vector** from the current value with `initialVelocity: 0` (`VA4`: one new animator over both components; `VA6`: position-continuous). **This is a simplification**: the scalar `animatedNumbers` keeps per-field velocity (`animateField`), so moving trim here loses momentum under a spring retarget, and SwiftUI's unchanged component keeps its slope across the other's retarget (`VA6c`). `VA6d` (per-tick `x(t)` for 100 ms after a retarget under a spring, fitted against a velocity-kept and a from-rest model) is **in the probe and was not run: the screen was locked on 2026-11-04**, and the row says so. No superposition (`to + (from - to) * A(t) + v0 * B(t)`) is built; if `VA6d` shows momentum kept, that is the follow-up, with a coordinator's decision.

## VA-G: keyframes over `Animatable`

`LinearKeyframe`, `CubicKeyframe`, `SpringKeyframe`, `MoveKeyframe`, `KeyframeTrack`, `KeyframeTrackContent` and `KeyframeTrackContentBuilder` take `Value: Animatable` (`VT14`, `VT15`; `VA8`: a custom struct interpolates every component). `KeyframeSpec` and `KeyframeSegments` stay on `Value.AnimatableData`; values convert at the keyframe's initialiser and at the track's write-back. `KeyframeTimeline` stays unconstrained and nonisolated. A third-party type that conforms to `VectorArithmetic` only must also conform to `Animatable` to be a track value. Row 169 keeps `Float` and the element-receiving content closure.

## VA-H: not offered

The `@Animatable` and `@AnimatableIgnored` macros (`VT6`, `VT7`; no macro infrastructure in the package; `docs/divergences.md`, not-offered table).

**Next unused: `VA-I`.**
