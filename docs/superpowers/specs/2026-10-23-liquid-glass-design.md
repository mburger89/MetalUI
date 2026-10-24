# Liquid Glass — design

Item LG (user request 2026-10-23, MetalUI only; gpui-gap list; not a plan task): SwiftUI's Liquid Glass on both
renderers, built on the backdrop blur. Branch `feat/liquid-glass` from `f1c422e5`; rulings `LG-A`… in
[`../2026-10-23-liquid-glass-decisions.md`](../2026-10-23-liquid-glass-decisions.md); divergence labels reserved **825–834**
(825–829 planned); record `docs/record/153-liquid-glass.md` (Record phase). **Status: lanes A (`LG-S`), B (`LG-T`) and C (2026-10-23, `LG-U`: one `LayoutModifier` case, ID and union as transparent scopes, `fillGlass` in `MaterialTransparency.swift`, test 21b added) built; Record phase 2026-10-23: LANDED, record §153, looks owed to a human (group `LG`).**

Evidence: [`docs/probes/swiftui-liquid-glass.swift`](../../probes/swiftui-liquid-glass.swift) (recorded output and reading in
its header). **`ImageRenderer` draws no glass; every pixel claim is a real-window capture.** SwiftUI has these APIs only in the
macOS 26+ SDK (installed: MacOSX27); gpui has no glass.

## 1. API (all in `Sources/MetalUI`, spelled as the SDK, `LG-A`)

```text
public struct Glass: Equatable, Sendable            // class A; no init, not Hashable
    static var regular, clear, identity: Glass
    func tint(_ color: Color?) -> Glass
    func interactive(_ isEnabled: Bool = true) -> Glass
modifiers (proposal content, and ElementGroup/StyledElement, both vocabularies):
    glassEffect(_ glass: Glass = .regular, in shape: some Shape = Capsule())     // no isEnabled: the SDK has none
    glassEffectID<ID: Hashable & Sendable>(_ id: ID?, in namespace: Namespace.ID)
    glassEffectUnion<ID: Hashable & Sendable>(id: ID?, namespace: Namespace.ID)
    glassEffectTransition(_ t: GlassEffectTransition)
public struct GlassEffectTransition: Sendable   // .matchedGeometry, .materialize, .identity
public struct GlassEffectContainer<Content>     // init(spacing: Pixels? = nil, @ProposalContentBuilder content:)
ButtonStyle.glass, ButtonStyle.glassProminent
@propertyWrapper public struct Namespace        // wrappedValue: Namespace.ID (Hashable, Sendable)
```

Class A except: the dark-regular fit and tint (D, 825), container/union (D, 826), `interactive` on non-control content (D, 827),
no morph (D, 828), `Path` shapes (D, 829). The signature's default shape is `Capsule()` where SwiftUI's is
`DefaultGlassEffectShape()` (a capsule, probe P; the type is not offered).

**Representation.** `Glass` is `{ variant: regular/clear/identity, tint: Color?, interactive: Bool }`. A `LayoutModifier` case
`.glassEffect(GlassSpec)` (proposal) mirrors `.backgroundMaterial` through `NativeModifiedContent`, `ModifiedContent`,
`ProposalAnimation` and `Transition`'s flatten arms; legacy: `Decoration` extras (`DecorationExtras`, `LK-W` 10), painted where
`backgroundMaterial` is (`AnimatedColor.swift`). `GlassSpec` holds the glass, the shape (`Shape.geometry`: rounded rect or
ellipse → a record; `Path` → a flat path fill, `LG-L`) and the union tag.

## 2. Code inventory (what the item touches; lane in brackets)

[A] `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` (`MUIBackdrop` 96 → 256, first six lanes' offsets pinned);
`shaders.metal` (`backdrop_fragment` gains the glass branch; `backdrop_flat_fragment` per member; **a second texture binding, the
sharp frame target, for the lens read**); `Renderer.swift`, `BackdropBlurPipeline.swift` (bind the frame target as texture 1;
counter `lastGlassRecords`); `Sources/MetalUIScene/Scene.swift` (`flatTintRects`, the `MUIBackdrop` init extension with a defaulted
tail); `Sources/MetalUIPath/GlassReference.swift` (new; imports nothing).
[B] `Backends/SDL/Shaders/replay.hlsl` (the same arithmetic, sixteen `float4` lanes), `SDLBridge.c/.h` (record stride, upload),
`SDLWindowRenderer.swift`, `ReplayFixture.swift` (v5, `backdropStride` 256, v4 widened on decode), `PortableReplay/main.swift`,
`SDLReplayer.swift`, the SDL and replay-fixture tests.
[C] `Sources/MetalUI/Glass.swift`, `GlassContainer.swift`, `GlassLook.swift`, `Namespace.swift` (new); `Button.swift`,
`ButtonStyle.swift`; `NativeModifiedContent.swift`, `ModifiedContent.swift`, `ProposalAnimation.swift`, `Box.swift` (extras);
`MaterialTransparency.swift` (`fillGlass`); `Transition.swift`, `DragSession.swift`, `Shadow.swift`, `Blur.swift` (the `.backdrop`
arms need no new line when members are normalised, but the flatten calls `flatTintRects`); the retention taint list
(`RetainedPrepaint`/`ContentMemoStore`); `Frame.swift` (`glassGroups`, cleared in `render`); `MetalUIDemoContent/LooksDemo.swift`
(own function). Doc comments are lane C's; inventory map rows and the census re-record are the Record phase's.

## 3. The record and the shaders (`LG-B`, `LG-D`, `LG-G`)

`MUIBackdrop` tail (lane A fixes exact offsets in the header and pins them): `look0 = (flags: u32, lensDepth, band, rimStrength)`,
`look1 = (blendK, press, pressLift, reserved)`; `flags` bits: 0 glass, 1 lensRim, 2 dark, 3…5 member count (1…4), 6…9 member k is an
ellipse; members 0…3 each `(x, y, w, h, rTL, rTR, rBR, rBL)` normalised to `bounds` (`LG-B`). One member reads the rect shader's
own SDF (`rect_shade`, so the edge equals a material's); more read the fold `smin` over each member's SDF in local pixels
(`LG-G`). Order in the shader: coverage `c` → blurred read `B` (+ lens: the sharp read at `p − n·d`, mixed by `(1−t)²`) →
`base = T + (1−T.a)·B'` → rim added → `· c · o`. The glass tint and the variant's base colour are merged into the one `tint` `Hsla`
on the CPU by `GlassLook.record(...)` (source-over, `LG-E`), so one record carries one tint; the press lift rides in `look1`.
Everything the shader needs is a number in the record (no scheme read in a shader). **`GlassReference` computes the same pixel
from the same record** (record, blurred sampler, sharp sampler, position → premultiplied RGBA), checked on fields that vary on
both axes (§94 §6).

## 4. Lanes (at most three, disjoint files; run A first, then B and C in either order, because B and C compile against A's header,
init extension and reference)

| lane | files | owns | verifies |
|---|---|---|---|
| A renderer | §2 [A] | header, Metal, `GlassReference`, Scene helpers, Renderer | native build, `MetalUIRenderTests` and `MetalUIPathTests`, the fourteen images 0 px, `swift build --build-tests` 0 warnings |
| B SDL | §2 [B] | HLSL, bridge, fixture v5, replay parity, Linux image | `Backends/SDL` on macOS with `METALUI_REQUIRE_GPU=1`; the Linux image on lavapipe; parity SDL Metal against Metal within `BB-J`'s tolerance |
| C API | §2 [C] | public surface, paint, container, buttons, demo, retention taint | native unfiltered suite, `closeout-*` scripts, `theSevenRetentionSlotsAreMutuallyDistinct`, the fourteen images |

## 5. Tests (each has a red-before and a mutation that must redden it)

Lane A (`Tests/MetalUIPathTests/GlassReferenceTests`, `Tests/MetalUIRenderTests/GlassRenderTests`, `GlassSceneTests`):
1. `aBackdropRecordIs256BytesAndItsFirstSixLanesDidNotMove` — offsets 0/16/32/48/64/80, stride 256. Red before: stride 96. Mutation: a lane before `tint`.
2. `aMaterialRecordWithAZeroTailRendersTodaysBytes` — a material scene's readback equals a stored pre-change array. Mutation: run the glass branch when `flags == 0`.
3. `theSmoothMinCrossesZeroAtSpacingTwiceTheGap` — `GlassReference`: g = 10, k 19 outside, 21 inside; g = 20, 39 outside, 41 inside. Mutation: `h²k/4` → `h²k/2`.
4. `aBlobFoldsMembersInTreeOrderAndFourIsTheCap` — five members make two blobs (4 + 1), no merge across. Mutation: cap 5.
5. `theLensReadsTheSharpTargetOnlyInsideTheEdgeBand` — a diagonal ramp plus a checker: `t = 1` equals the blurred read, `t = 0` differs, zero when the lensRim bit is clear. Mutations: weight `(1−t)` for `(1−t)²`; lens off when dark.
6. `theRimIsBrightestTowardTheUpperLeft` — upper-left over lower-right by the 0.65/0.35 ratio, zero at `t ≥ 1` (`LG-S` 2, was 0.25). Mutation: flip `L`.
7. `aTintCompositesSourceOverTheBase` — alpha 0.3 red over regular-light over gray equals the reference to one byte. Mutation: tint under the base.
8. `aSingleMemberGlassHasAMaterialsEdge` — coverage equals `rect_shade`'s across a rounded edge. Mutation: smooth-min SDF for one member.
9. `aGlassWithAnOpacityIsAHalfWeightCompositeOverTheSharpBackdrop` — `BB-A` with a tail. Mutation: opacity on the tint only.
10. `aGlassUnderATransformKeepsItsMembers` — a rotated blob's member edges follow. Mutation: members in absolute pixels (the hazard `LG-B` closes).
11. `theFlatArmDrawsOneRectPerMember` — `flatTintRects`; one member equals `flatTintRect`. Mutation: return member 0 only.
12. `aSceneHoldingOnlyAGlassIsNotEmptyAndCountsLPlusTwoPasses` — `lastBackdropPasses`, `lastGlassRecords`. Mutation: skip the count.

Lane B (`Backends/SDL/Tests/ReplayFixtureTests`, `SDLBackdropTests`, `SDLGlassTests`):
13. `theFixtureStrideIs256AndVersion4Widens` — a v4 fixture decodes with a zero tail and replays equal. Mutation: widen with 0xFF.
14. `theThreeGlassParityFramesMatchMetalWithinTheBackdropTolerance` — frames 12–14 (`LG-O`). Mutation: one constant changed in `replay.hlsl` only (the rim exponent).
15. `aGlassFrameOnLavapipeMatchesTheReference` — Linux image. Mutation: HLSL `smin` `k/4` → `k/2`.
16. `theSDLBridgeUploadsTheWholeRecord` — a record with a nonzero last member reaches the shader. Mutation: upload 96 bytes per record.

Lane C (`Tests/MetalUITests/Glass*Tests`, `Tests/MetalUITestingTests`, guards):
17. `aGlassEffectEmitsOneBackdropRecordBehindItsContent` — one record, flags glass, scene order before the text's glyphs. Mutation: emit after content.
18. `theDefaultShapeIsACapsule` — radii half the short side. Mutation: radius 0.
19. `identityEmitsNothingAndEqualsNoModifier` — scene equal to the bare tree's. Mutation: identity emits a clear.
20. `regularAndClearAndTintMapToTheFittedTable` — the record's `tint` equals `GlassLook.base` for four (variant, scheme) pairs and the source-over. Mutation: swap the dark clear row.
21. `aContainerMergesShapesCloserThanItsSpacing` — three circles, spacing 40 → one record, count 3; spacing 4 → three records. Mutation: compare against `spacing/2`.
22. `anUnsetSpacingIsEight` — gap 2 merges, gap 6 does not. Mutation: nil → 0.
23. `aUnionIdMergesRegardlessOfDistance` — gap 120, one id → one record. Mutation: ignore the id.
24. `aContainerEmitsBeforeItsContentAndItsMembersEmitNothing` — record order and count; a sibling between members is under the blob (divergence 826). Mutation: members also emit.
25. `aContainerSubtreeRefusesRetentionByName` — counted taint `glassContainer`, an `.equatable()` ancestor evaluates every frame. Mutation: drop the taint (must redden under `METALUI_VERIFY_RETAINED=1`).
26. `aStandaloneGlassReplaysItsRecordUnderRetention` — a retained occurrence hits and the scene equals a fresh frame. Mutation: omit the record from the paint log.
27. `aPathShapeDrawsItsFlatTintAsAPathFill` — no backdrop record, one path primitive. Mutation: a rect.
28. `reduceTransparencyDrawsTheOpaqueGreyWithNoBackdropRecord` — headless platform option. Mutation: ignore the environment.
29. `aGlassInsideACPURasterisedShadowDegradesToItsFlatTint` — `BB-H`'s arm for glass. Mutation: skip the arm.
30. `aPressedGlassButtonLiftsItsTint` — `TestWindow` press then release on a `.glass` button: `look1.press` 1 then 0. Mutation: read hover only.
31. `aBareInteractiveGlassRegistersNoHitbox` — hitbox count equals the bare tree's (`OM-AK`). Mutation: register one.
32. `glassButtonStylesAreNotBordered` and `aGlassButtonKeepsItsKeyboardAndFocus` — Tab reaches it, Space fires. Mutation: bordered true.
33. `aNamespaceIdIsStableAcrossFramesAndDistinctPerDeclaration`, with `theSevenRetentionSlotsAreMutuallyDistinct` run unfiltered. Mutation: a per-frame id.
34. `glassEffectTransitionMaterializeFadesInAndOut` — opacity series over `simulateTick`; `.identity` snaps. Mutation: `.identity` fades.
35. Guards (`GlassCompileGuards`, plain-import `typecheckFile`): `Glass` has no public initialiser and is not `Hashable`; `glassEffect` has no `isEnabled:` (probe A4/A15/A17's separating arms); `GlassLook` and `GlassSpec` stay non-public. Each guard mutated red once (add the init; add `Hashable`; widen access).
36. `everyGlassEmissionSiteGoesThroughFillGlass` — a scan like `MT-`'s. Mutation: a second glass-tailed `fillBackdrop(` call.

## 6. Demo, pixels and gates

`liquidGlassSection()` in `LooksDemo` (`LG-P`); fourteen images 0 px against `f1c422e5`; `DemoFrameDeterminismTests`'
`Expected.swift` untouched; every build and run gate as the brief says. **Counts after the lanes: unknown**, re-measured at Record.
New public declarations: `Glass`, `GlassEffectContainer`, `GlassEffectTransition`, `Namespace`, the four modifiers, the two
`ButtonStyle` statics: each a doc comment and an inventory row.

## 7. Divergences planned (labels 825–829 are taken at Record; 830–834 stay unused)

825 the look beyond the measured affine: lens and rim are MetalUI's, dark regular is a least-squares fit, `regular.tint` is
source-over where SwiftUI gave a colour-independent grey. 826 container: four members per blob, glass drawn before the
container's content, `glassEffectUnion` follows the documentation where SwiftUI measured one circle. 827 `interactive()` on
non-control content is inert. 828 no morph; transitions are opacity. 829 a `Path` shape draws a flat tint.

## 8. Human checks, group `LG` (not run: an agent cannot; added to `docs/verification/human-checks.md` at Record)

LG1 the look in a key window against a SwiftUI app on macOS 26, light and dark, over photos and text (lens depth, rim, sigma, the
carried hairline). LG2 `.glass`/`.glassProminent` buttons and `regular.tint` against SwiftUI. LG3 `glassEffectUnion` and the
container's merge and neck against SwiftUI. LG4 Reduce Transparency's grey. LG5 SDL on a desktop GPU (Linux, Windows D3D12).
LG6 a press on a `.glass` button.

## 9. Scoped down, named (`LG-Q`)

Outer hairline, morph, press scale, more than four members, blurred glass on a `Path`, sigma and lens against SwiftUI, Windows
D3D12 parity: each with its reason and owner in the decisions doc.
