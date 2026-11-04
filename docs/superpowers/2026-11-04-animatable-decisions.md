# `Animatable` on shapes and keyframes (round 4 item R4-3 PR D) — decisions (prefix `VA-`)

Rulings for divergences 947 (retired), 169 (narrowed), 215 and 216 (added). Branch `feat/r4-3-animatable`, on `feat/r4-3-leaver-moves` (PR C, #203). Record 208. Evidence: `XF-C` (`docs/superpowers/2026-11-03-default-transition-decisions.md`) and the probe `docs/probes/swiftui-animatable.swift` (`VT1`..`VT16`, `VA1`..`VA8`, recorded in `swiftui-animatable-run.txt`; `VA6d` was added in this PR and **not run**, the screen being locked on 2026-11-04). `Component & Animatable` is PR E (record 209), decided in `VA-I`..`VA-M` below. **Class `A`** (SwiftUI-aligned) with two documented divergences. **Next unused: `VA-N`.**

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

## VA-I: `Component & Animatable` interpolates in layout (R4-3 PR E, record 209)

1. **The rule** (`VA5`): a `Component` that is `Animatable` runs its `content` at the interpolated data, so a child laid out from it is proposed every intermediate size. The spelling is SwiftUI's `View` (`VT2`, `VT3`; the spike's `S3`/`S4`): `nonisolated var animatableData`.
2. **Where**: in the layout phase (`AN-AA`'s number-in-layout rule), in `requestGroupLayout`, **into `self`**, through `animatedVector` at `layerAnimationKey(component id, "animatable")` in the `AnimationStore` (no `StateTable` slot, `VA-D` item 2). One internal helper, `interpolateAnimatableComponent(_:id:pass:)` in `Component.swift`, is the whole body; a component whose data is `EmptyAnimatableData` returns at a metatype comparison and stores nothing.
3. **How a non-conformer pays nothing**: `extension Component where Self: Animatable` supplies a more specialised `requestGroupLayout` witness, so the unconstrained default (`enterComponent`, `content`, `finishComponent`) is byte for byte what it was. The `[PREDICTED]` item held: **the witness is selected for a conformance written in another file** (and another module: the test target), pinned by `aWitnessDeclaredInAnotherFileIsSelected` with the `Animatable` extension in `AnimatableComponentSplit.swift`. No dynamic check was built or counted.
4. **One requirement had to be added to `Component`**, `_interpolateAnimatableData(id:pass:)` (default: no-op; `Self: Animatable`: the helper). `EquatableComponent` is generic over `Component & Equatable` and cannot see `Animatable` without a cast, so it reaches the constrained witness through the requirement. **`package` is refused on a protocol requirement** ("'package' modifier cannot be used in protocols") **and an `@_spi` requirement is refused downstream** (its default is invisible to a module that does not import the SPI, so every outside `Component` failed to conform: measured, MetalUIDemoContent). It is therefore `public`, underscored, documented "framework-internal, never implement or call it"; the inventory classes it M. The bare path does not use it (it calls the helper directly), so the two entries fail independently.

## VA-J: before the bind, so a setter that rebuilds `self` keeps its state

The interpolation is written after the component's id is known and **before** `StateBinder.bind(self)`. A setter that replaces `self` (`self = Counter(x: newValue)`) makes a copy with fresh, unbound `@State` wrappers; bound afterwards, the copy's state writes are discarded (an unbound `@State` ignores writes). Bound after the interpolation, the state survives. Pinned by `aSetterThatRebuildsSelfKeepsItsState` (the separating arm for the ordering; mutation `ME4`).

## VA-K: `.equatable()` interpolates before `==` (`VA7`, `VA7s`)

`EquatableComponent` calls the hook before `enterComponent`, so the value the memo compares and stores is the interpolated one: every frame of a flight misses and runs the body once (the change frame reads its own `from`, which equals the last evaluation and hits, as the probe's first tick), and a frame after the landing, on an unrelated parent change, hits and runs none. The call sits after the occurrence's `RetainedBuildWindow` opens, so the interpolation it notes is inside the window; **that placement is not load-bearing** (mutation `ME6`, the call before the window, is green: a moving value misses the memo and the occurrence is rebuilt anyway).

## VA-L: a grafted or memoized occurrence is not frozen in flight

`animatedVector` counts an interpolation and notes an active animation (`noteInterpolation`, `noteActiveAnimation`), never `requestAnotherFrame()`. A moving value misses the `==` memo, so the occurrence is rebuilt, and the noted interpolation keeps its record from being replayed: no graft, no prepaint or paint replay. Pinned by `anAnimatableComponentInARetainedOccurrenceIsNotFrozen` (equal to the retention-off oracle, no redo). The `VA6` retarget rule (divergence 216) applies unchanged: a retarget restarts the whole vector at rest.

## VA-M: no mirror in `StyledComponent`

The plan mirrored the body in `StyledComponent.requestGroupLayout`. It is not needed: `StyledComponent` calls `component.requestGroupLayout`, a requirement, so the witness table picks the constrained one; its ops animate on their own keys under the component's id, so the two tracks cannot collide. `aTypedEntryAnimatesToo` pins `Counter(x:).padding(2)`. **No new divergence**: `S3`/`S4` and `VT2`/`VT3` agree; the row-96 residue (a child re-laid out per frame) is unchanged.

**Next unused: `VA-N`.**
