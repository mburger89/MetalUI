# Right-to-left layout direction — decisions (prefix `LD-`)

Rulings for round-3 item R3-10 item 4: `.environment(\.layoutDirection, .rightToLeft)` was carried and readable but mirrored nothing
(divergence 25, `EV-K`, pinned wrong by `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack`). Branch `feat/layout-direction` from master
`d6d0bbc9`. Code: `Sources/MetalUILayout/LayoutTree.swift` (`rightToLeftNodes`, `registersRightToLeft`, `mirroredChildRect`, the `place` helper in
`placeNative`, `placeCustom`, `placeGrid`, the segment/graft/digest/signature rows), `Sources/MetalUI/Frame.swift` (`environmentTop`'s `didSet`,
`registerScrollRegion`, `noteScrollTarget`, `scrollOffset(bringing:into:anchor:)`, the prepaint extras), `RenderEffects.swift`, `TextStyleResolution.swift`,
`ScrollChrome.swift`, `ScrollView.swift`, `ProposalScrollView.swift`, `Hitbox.swift`, `Window.swift`, `LazyCore.swift`. Probe:
`docs/probes/swiftui-layout-direction.swift` (header holds the recorded output). Tests: `Tests/MetalUILayoutTests/LayoutDirectionTests.swift`,
`Tests/MetalUITests/LayoutDirectionTests.swift`, `Tests/MetalUITestingTests/LayoutDirectionWindowTests.swift`, and the flipped E17 in
`EnvironmentTests.swift`. **Next unused: `LD-I`.** Divergence 25 retired, 1045 added (reserved 1045–1054; 1046–1054 unused).

## LD-A: SwiftUI's semantics, and the one mechanism

Measured (probe, macOS 27.2): every container places its children as if left to right and the result is reflected about the middle of the
container's own bounds. `HStack` (spacing 0, 10 and 20 wide) 0/10 becomes 90/70 in a 100 wide leading frame, spacing 5 0/15 becomes 90/65 (A1, A2);
`frame(maxWidth: .infinity, alignment: .leading)` 0 becomes 90, `.trailing` 90 becomes 0, `.center` stays (B); `ZStack(alignment: .leading)` 0/0
becomes 70/90 (C1); `overlay`/`background(alignment: .leading)` moves the overlay to 90 and not the base (D); `padding(.leading, 10)` puts the pad
on the right, child at 80 (E1), `.trailing` child at 90 (E2); `offset(x: 10)` inside the writer lands at 80 (F1), outside it at 100 = 90 + 10 (F2);
`position(x: 20)` 15 becomes 75 (G1); `VStack(.leading)` 90/70 (H1); a custom `Layout` packing from the left 90/70 (I1); `Grid` 90/70 (J1); a
horizontal `ScrollView` opens at the right edge (L1). **The parent's direction decides where a child goes**: a left-to-right `HStack` nested in a
right-to-left one keeps its own order inside the box the outer one mirrored (K1: 90, inner 60/70, 50).

The mechanism is therefore **one reflection per placed child, at placement time**: `mirroredChildRect(rect, within: bounds)` =
`x' = 2·bounds.x + bounds.width − x − width`, applied to every child of a marked parent by the `place` helper in `placeNative` (overlay, attachment,
frame, padding, fixedSize, aspectRatio, layoutPriority, scroll viewport, linear stack), by `placeCustom` (both the recorded and the unrecorded child) and
by `placeGrid`. **Measurement is untouched**, so a right-to-left tree measures exactly what its left-to-right twin does (pinned by
`mirroringDoesTheSameMeasurementWorkAsLeftToRight`, a counted-work test that arrives green). A child placed in a parent's whole bounds
(`layoutPriority`, the overlay attachment's primary) reflects onto itself; the call is kept so a new case goes through one door.

## LD-B: the registration mark, its signature, its graft

A node is marked when it **registers** while `LayoutTree.registersRightToLeft` is set (`appendNode` inserts into `rightToLeftNodes`, which covers every
registrar, the grid included). `Frame.environmentTop` keeps the flag equal to the environment in effect with a `didSet`, which covers the root
setter, every `withEnvironment` push and its restoring pop; the nodes of a writer's scope are therefore marked and a sibling after it is not. The mark is
part of what a node is: `nodeSignature` mixes a fixed tag **for marked nodes only**, so every left-to-right signature is bit-identical to before and a
placement root restored by the subtree memo (`SB-AD`) is never restored across a direction flip (`aPlacementRootIsNotRestoredAcrossADirectionFlip`: same
shape, keys, proposal and bounds; the separating arm, the same direction twice, hits once). `captureSegment` carries the marks of the captured range and
`graft` copies those, **never the flag in force at graft time** (`aGraftCarriesTheDirectionItWasCapturedUnder`); `structureDigest` prints `|rtl`;
`reset(generation:)` clears. A stored property on the public `LayoutTree`: `swift package clean` after the change (`CN-R`). A direction flip
misses the layout memo and the retained subtrees once, by design.

## LD-C: render effects are conjugated by the reflection

An effect's map is defined against the element's rect, so under a right-to-left environment `RenderEffectSpec.affine(in:mirrored:)` builds the
left-to-right map of the spec reflected: an offset's x is negated, an anchor's x becomes `1 − x`, a rotation's angle is negated (the sense reverses), a
scale's factors stand (probe P1 `scaleEffect(2, anchor: .leading)`: ink 0...39 becomes 60...99; P2 `rotationEffect(30°, anchor: .leading)`: the same
rows, the rectangle extending left from the right anchor). The direction is **the environment at the effect's site** (`environmentTop` in prepaint,
paint and `effectBoundingBox`), so an `offset` outside the writer is not flipped (F2) and one inside is (F1). Hit testing, accessibility and the
caret rectangle derive from these maps and need nothing else (`aClickFollowsAnOffsetInsideARightToLeftWriter`, `theCaretRectFollowsAnOffsetInsideARightToLeftWriter`).
A shadow's x offset, a blur and a compositing group have no map and are not changed (unprobed).

## LD-D: text

`multilineTextAlignment` is resolved against the direction in `resolveTextStyle`: `.leading` and `.trailing` swap under right-to-left, `.center` stands
(probe M1–M3). **Glyphs are never mirrored.** The portable and the CoreText text systems are untouched; they receive the swapped alignment. A
`TextField`/`TextEditor` takes the same path where it reads the resolved style; whether a field's caret and selection agree with right-aligned text is a
human check (LD1), not a measured claim.

## LD-E: a horizontal scroller's offset is logical

SwiftUI opens a right-to-left horizontal scroller at its leading (right) edge (L1). The kernel already placed the content mirrored inside the viewport
(content minX −200 in a 100 viewport over 300 of content), so the stored offset becomes **the distance from the leading edge**: the translation is
`+offset` rather than `−offset` (`ScrollChrome.translation(offset:)`), the wheel adds the delta (`Hitbox.scrollMirrored`, set by `registerScrollRegion` from the
environment at the scroller's site, read by `Window.scroll`), the indicator starts at the right and travels left (`indicatorBounds`), and every reader of a
position along the axis measures from the leading edge (`ScrollerFrame.mirrored`, `logicalStart(of:)`: `noteScrollTarget`, `scrollOffset(bringing:into:anchor:)`,
the lazy planner's origin and `resolveScrollRequests`, so `scrollTo`, `scrollPosition(id:)` and the lazy window need no other change). The flag is appended to the
prepaint extras vector (index 9; the `RZ-M` indices before it stand). Vertical scrollers are never mirrored.

## LD-F: what stays physical

Pointer coordinates, hitbox rects, the `GeometryReader`/coordinate-space reports and accessibility frames are physical (probe: coordinate-space reports
stay physical). They derive from the placed rects and the effect maps, so they mirror because the layout did, not because anything flips them. No SDL
or shader change: the reflection happens before a primitive exists.

## LD-G: deferred, divergence 1045

Not mirrored, on purpose: a `Path`/`Shape` fill's own geometry (probe O1: SwiftUI fills 70...100 where MetalUI fills 0...30), a gradient's
`.leading`/`.trailing` unit points, `trim`'s direction, `UnevenRoundedRectangle`'s leading/trailing corners. `Canvas` is not mirrored in SwiftUI (O2) and
an `Image` only under `flipsForRightToLeftLayoutDirection(true)` (N1, N2), which MetalUI does not offer; MetalUI has no `Canvas` type, and an `Image`
is never mirrored, which is SwiftUI's default. Pin `aRightToLeftShapeIsNotYetMirrored`, which flips when mirrored geometry lands.

## LD-H: carried, no label

A transition's edge (`.move(edge: .leading)`), control internals (a `Stepper`'s buttons, a `Picker`'s chevron side), a vertical scroller's side, caret
movement by the arrow keys, gesture `location`s in a mirrored subtree (physical, as the coordinate spaces are), accessibility reading order, following the
system's direction (`EV-Q`: the root stays left-to-right unless the app writes it), half-pixel ties at a mirrored position, and a custom `ProposalLayout`
reading its own direction (it places as if left to right and the kernel reflects it). Human checks `LD1`–`LD5`.
