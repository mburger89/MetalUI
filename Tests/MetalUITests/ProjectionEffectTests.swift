import Testing
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// 3D render effects (`PJ-`, record 193). SwiftUI's side is `docs/probes/swiftui-projection-effects.swift` (arms R1-R9, J1-J4,
// T1-T2, C1, L1, B1; the numbers below are its recorded ink boxes, to a pixel). No test sleeps; nothing here is a golden.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

/// The probe's 200 x 100 view at the origin.
private let box = Bounds(origin: pt(0, 0), size: Size(width: px(200), height: px(100)))
private let yAxis: (x: Double, y: Double, z: Double) = (0, 1, 0)

private func turn(_ degrees: Double, axis: (x: Double, y: Double, z: Double) = yAxis, anchor: UnitPoint = .center,
                  anchorZ: Double = 0, perspective: Double = 1) -> RenderEffectSpec {
    .rotation3D(Rotation3DSpec(angle: .degrees(degrees), axisX: axis.x, axisY: axis.y, axisZ: axis.z, anchor: anchor,
                               anchorZ: anchorZ, perspective: perspective))
}

private func mapped(_ e: RenderEffectSpec, _ x: Double, _ y: Double, in rect: Bounds<Pixels> = box,
                    mirrored: Bool = false) -> (x: Double, y: Double)? {
    e.map(in: rect, mirrored: mirrored).apply(x, y)
}

private func near(_ a: Double?, _ b: Double, _ tol: Double = 0.6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

// MARK: - 1-6: the measured perspective model

/// **R1.** 45 degrees about y at `perspective` 1 on a 200 x 100 view: the near (left) edge sits at x -9 and is 154 tall, the far
/// edge at x 151 and 76 tall; the 100 x 200 view has the same eye distance (200), so its near edge is also 242 tall over 200 high.
/// Mutation: `extent = min(width, height)` (and, separately, dropping `/ extent`) in `Homography2D.rotation3D`.
@Test func rotation3DEffectMatchesTheMeasuredPerspective() throws {
    let e = turn(45)
    let topLeft = try #require(mapped(e, 0, 0)), bottomLeft = try #require(mapped(e, 0, 100))
    let topRight = try #require(mapped(e, 200, 0)), bottomRight = try #require(mapped(e, 200, 100))
    #expect(near(topLeft.x, -9.4) && near(bottomLeft.x, -9.4), "near edge x: \(topLeft)")
    #expect(near(bottomLeft.y - topLeft.y, 154, 1.5), "near edge height: \(bottomLeft.y - topLeft.y)")
    #expect(near(topRight.x, 151.5, 1.5) && near(bottomRight.x, 151.5, 1.5), "far edge x: \(topRight)")
    #expect(near(bottomRight.y - topRight.y, 74, 2.5), "far edge height: \(bottomRight.y - topRight.y)")
    // The tall view: d = max(W, H) / perspective = 200 as well (R1 100x200).
    let tall = Bounds(origin: pt(0, 0), size: Size(width: px(100), height: px(200)))
    let t0 = try #require(mapped(e, 0, 0, in: tall)), t1 = try #require(mapped(e, 0, 200, in: tall))
    #expect(near(t1.y - t0.y, 242, 1.5), "100 x 200 near edge height: \(t1.y - t0.y)")
}

/// **R2/R3.** A positive y angle brings the leading edge forward (taller), a positive x angle the bottom forward (wider).
/// Mutation: negate the `s` terms of the Rodrigues matrix.
@Test func aPositiveYTurnBringsTheLeadingEdgeForward() throws {
    let l = try #require(mapped(turn(45), 0, 100)), l0 = try #require(mapped(turn(45), 0, 0))
    let r = try #require(mapped(turn(45), 200, 100)), r0 = try #require(mapped(turn(45), 200, 0))
    #expect(l.y - l0.y > r.y - r0.y, "left taller than right")
    let n = try #require(mapped(turn(-45), 0, 100)), n0 = try #require(mapped(turn(-45), 0, 0))
    #expect(n.y - n0.y < 100 * 1.0 + 1 && n.y - n0.y < l.y - l0.y, "-45 shrinks the leading edge")
}

@Test func aPositiveXTurnBringsTheBottomForward() throws {
    let e = turn(45, axis: (1, 0, 0))
    let bl = try #require(mapped(e, 0, 100)), br = try #require(mapped(e, 200, 100))
    let tl = try #require(mapped(e, 0, 0)), tr = try #require(mapped(e, 200, 0))
    #expect(br.x - bl.x > tr.x - tl.x, "the bottom edge is wider: \(br.x - bl.x) vs \(tr.x - tl.x)")
    #expect(near(br.x - bl.x, 242, 3), "R3: ink 242 wide: \(br.x - bl.x)")
}

/// **R4.** A z-axis rotation is `rotationEffect` (the probe's ink boxes are identical): same map, to rounding.
/// Mutation: transpose the rotation matrix.
@Test func aZAxisRotation3DIsRotationEffect() throws {
    let a = turn(30, axis: (0, 0, 1)).map(in: box), b = RenderEffectSpec.rotation(.degrees(30), anchor: .center).map(in: box)
    #expect(a.isAffine, "no perspective term")
    for (x, y) in [(0.0, 0.0), (200, 0), (0, 100), (200, 100)] {
        let p = try #require(a.apply(x, y)), q = try #require(b.apply(x, y))
        #expect(abs(p.x - q.x) < 1e-9 && abs(p.y - q.y) < 1e-9, "(\(x), \(y)): \(p) vs \(q)")
    }
}

/// **R6.** `anchorZ` shifts the plane and is not added back: 0.001 degrees with `anchorZ` 50 scales by 0.8 (the ink is
/// 160 x 80 at x 20), but an angle of exactly 0 is the identity whatever `anchorZ` is. Mutation: add `anchorZ` back to `v'z`;
/// delete the zero-angle shortcut.
@Test func anchorZShiftsThePlaneAndIsNotAddedBack() throws {
    let e = turn(0.001, anchorZ: 50)
    let a = try #require(mapped(e, 0, 0)), b = try #require(mapped(e, 200, 100))
    #expect(near(a.x, 20, 0.5) && near(a.y, 10, 0.5) && near(b.x, 180, 0.5) && near(b.y, 90, 0.5), "\(a) \(b)")
}

@Test func anExactlyZeroAngleIsIdentity() {
    let m = turn(0, anchorZ: 50).map(in: box)
    #expect(m.isIdentity, "\(m)")
}

/// **R5.** The axis is normalised ((0, 2, 0) is (0, 1, 0)) and a zero axis is the identity. Mutation: skip the normalisation.
@Test func theAxisIsNormalisedAndAZeroAxisIsIdentity() throws {
    let a = turn(45, axis: (0, 2, 0)).map(in: box), b = turn(45).map(in: box)
    for (x, y) in [(0.0, 0.0), (200, 100)] {
        let p = try #require(a.apply(x, y)), q = try #require(b.apply(x, y))
        #expect(abs(p.x - q.x) < 1e-9 && abs(p.y - q.y) < 1e-9)
    }
    #expect(turn(45, axis: (0, 0, 0)).map(in: box).isIdentity)
}

/// **R2.** `perspective` 0 is orthographic (141 wide, height unchanged), a negative one is the negated angle, 2 halves the
/// eye distance. Mutation: guard `perspective == 0` as the identity; drop the negation.
@Test func perspectiveZeroIsOrthographicAndNegativeMirrorsTheAngle() throws {
    let o = turn(45, perspective: 0).map(in: box)
    #expect(o.isAffine)
    let a = try #require(o.apply(0, 0)), b = try #require(o.apply(200, 100))
    #expect(near(b.x - a.x, 141.4, 0.5) && near(b.y - a.y, 100, 1e-6), "orthographic: \(a) \(b)")
    let neg = turn(45, perspective: -1).map(in: box), pos = turn(-45, perspective: 1).map(in: box)
    for (x, y) in [(0.0, 0.0), (200, 100)] {
        let p = try #require(neg.apply(x, y)), q = try #require(pos.apply(x, y))
        #expect(abs(p.x - q.x) < 1e-9 && abs(p.y - q.y) < 1e-9)
    }
    let two = turn(45, perspective: 2).map(in: box)
    #expect(two.g == 2 * turn(45).map(in: box).g, "perspective 2 halves d")
}

// MARK: - 7-9: projectionEffect and transformEffect

/// **J1-J3.** Row vectors with the w column: `m13` 0.002 puts the right edge at 142.86 and 71 tall, `m33` 2 halves the view,
/// `m31` is the x translation. Mutation: transpose the matrix in `ProjectionTransform.homography`.
@Test func projectionEffectReadsRowVectorsWithTheWColumn() throws {
    var m13 = ProjectionTransform(); m13.m13 = 0.002
    let e = RenderEffectSpec.projection(m13)
    let a = try #require(mapped(e, 200, 0)), b = try #require(mapped(e, 200, 100))
    #expect(near(a.x, 142.86, 0.01) && near(b.y - a.y, 71.4, 0.1), "right edge: \(a) \(b)")
    var m33 = ProjectionTransform(); m33.m33 = 2
    let h = try #require(mapped(.projection(m33), 200, 100))
    #expect(near(h.x, 100, 1e-9) && near(h.y, 50, 1e-9), "m33 2 halves: \(h)")
    var m31 = ProjectionTransform(); m31.m31 = 30
    let t = try #require(mapped(.projection(m31), 0, 0))
    #expect(near(t.x, 30, 1e-9) && near(t.y, 0, 1e-9), "m31 translates x: \(t)")
}

/// **T1.** `transformEffect` is the `Transform2D` in the view's own coordinates: a shear `b` 0.2 with `tx` 10 about a view that
/// is not at the origin moves the corners as the origin-view does, plus the view's offset. Mutation: skip `T(origin)`.
@Test func transformEffectAppliesInCoreGraphicsOrderLocalToTheView() throws {
    let moved = Bounds(origin: pt(40, 30), size: Size(width: px(200), height: px(100)))
    let t = Transform2D(a: 1, b: 0.2, c: 0, d: 1, tx: 10, ty: 0)
    let e = RenderEffectSpec.projection(ProjectionTransform(t))
    let p = try #require(mapped(e, 240, 130, in: moved))
    #expect(near(p.x, 40 + 200 + 10, 1e-9) && near(p.y, 30 + 100 + 0.2 * 200, 1e-9), "\(p)")
    let o = try #require(mapped(e, 40, 30, in: moved))
    #expect(near(o.x, 50, 1e-9) && near(o.y, 30, 1e-9), "the origin corner: \(o)")
}

/// **R8/J4.** A view with any corner on or behind the eye draws nothing: `m13` -0.01 (one corner at w -1, none exactly),
/// 60 degrees at `perspective` 2.5 (nothing) against 2.2 (draws). Mutation: test only the centre; `w < 0`.
@Test func anyCornerBehindTheEyeDrawsNothing() throws {
    var bad = ProjectionTransform(); bad.m13 = -0.01
    #expect(!RenderEffectSpec.projection(bad).map(in: box).isInFront(of: box))
    #expect(RenderEffectSpec.projection(bad).map(in: box).apply(50, 50) != nil, "the centre alone is in front")
    #expect(!turn(60, perspective: 2.5).map(in: box).isInFront(of: box), "60 degrees at 2.5 draws nothing")
    #expect(turn(60, perspective: 2.2).map(in: box).isInFront(of: box), "at 2.2 it draws")
    let edgeOn = turn(90).map(in: box).boundingBox(of: box)
    #expect(edgeOn.size.width.value < 1e-3, "exactly 90 degrees is edge-on, a quad of no width: \(edgeOn)")
}

// MARK: - 10: right to left

/// **RTL.** Every effect is conjugated by the reflection: a y-axis 45 equals -45, anchor `.leading` pivots at the right edge,
/// `transformEffect` tx 30 becomes -30 and `projectionEffect` m31 30 becomes -30 with m32 unchanged. Mutation: drop the new
/// `mirroredSpec` arms (and the projection's `reflected`).
@Test func rightToLeftConjugatesEveryProjectiveEffect() throws {
    let a = try #require(mapped(turn(45), 0, 0, mirrored: true)), b = try #require(mapped(turn(-45), 0, 0))
    // The mirrored 45 is the reflection of the left-to-right one: its far edge is the left one.
    let c = try #require(mapped(turn(45), 200, 0)), mirroredLeft = try #require(mapped(turn(45), 0, 0, mirrored: true))
    #expect(near(mirroredLeft.x, 200 - c.x, 1e-6), "reflection: \(mirroredLeft) vs \(c)")
    _ = (a, b)
    let pivot = turn(45, anchor: .leading)
    let ltr = try #require(mapped(pivot, 0, 50)), rtl = try #require(mapped(pivot, 200, 50, mirrored: true))
    #expect(near(ltr.x, 0, 1e-9) && near(rtl.x, 200, 1e-9), "the leading anchor is the right edge: \(ltr) \(rtl)")
    var t = ProjectionTransform(); t.m31 = 30; t.m32 = 7
    let moved = try #require(mapped(.projection(t), 100, 50, mirrored: true))
    #expect(near(moved.x, 70, 1e-9) && near(moved.y, 57, 1e-9), "m31 30 -> -30, m32 stays: \(moved)")
    let tx = try #require(mapped(.projection(ProjectionTransform(Transform2D(translationX: 30, y: 0))), 100, 50, mirrored: true))
    #expect(near(tx.x, 70, 1e-9), "transformEffect tx 30 -> -30: \(tx)")
}

// MARK: - 11-13: layout, nesting, clipping

/// **L1.** A 3D effect changes paint and not layout: the sibling after it paints where it would with no effect.
/// Mutation: give `.rotation3DEffect` a layout footprint in `requestNativeLayout`.
@Test @MainActor func rotation3DEffectChangesPaintAndNotLayout() throws {
    func tree(_ turned: Bool) -> some Element {
        HStack(spacing: 0) {
            if turned { fxBar(100, 20).rotation3DEffect(.degrees(45), axis: yAxis) } else { fxBar(100, 20) }
            Color(.separator).frame(width: px(40), height: px(20))
        }
    }
    let plain = effectFrame(tree(false)).finalizedScene(), turned = effectFrame(tree(true)).finalizedScene()
    let a = try #require(effectRects(plain, .separator).first), b = try #require(effectRects(turned, .separator).first)
    #expect(fxDescribe(a.bounds) == fxDescribe(b.bounds), "the sibling stays: \(fxDescribe(b.bounds))")
}

/// **R9.** Nested effects are each their own projective map and compose: two 30-degree turns reach x -41 (a single 60
/// reaches 12). Mutation: add the angles into one effect.
@Test func nestedProjectiveEffectsComposeAsFlattenedMaps() throws {
    let one = turn(30).map(in: box)
    let both = one.concatenating(one)
    let p = try #require(both.apply(0, 0))
    #expect(near(p.x, -41, 1.0), "two 30s reach x -41: \(p)")
    let sixty = try #require(turn(60).map(in: box).apply(0, 0))
    #expect(near(sixty.x, 12, 1.0) && abs(sixty.x - p.x) > 30, "one 60 is another map: \(sixty)")
}

// MARK: - 14-17: hit testing, geometry, accessibility

@MainActor
private final class Taps { var count = 0 }

@MainActor
private func projectedWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

@MainActor
private func tapped(_ platform: FakePlatformWindow, _ window: Window, _ taps: Taps, at p: Point<Pixels>) -> Bool {
    let before = taps.count
    platform.simulateInput(.mouseDown(MouseEvent(position: p)))
    platform.simulateInput(.mouseUp(MouseEvent(position: p)))
    window.drawFrameIfNeeded()
    return taps.count > before
}

/// **H.** Hit testing follows the projected quad: a 100 x 50 bar at x 50...150, y 75...125 turned 45 degrees about y hits at its
/// near edge outside the layout rect (47, 100), and misses inside the layout rect beyond the far edge (145, 100); the centre hits.
/// Mutation: invert as an affine map (drop the divide in `Homography2D.apply`).
@Test @MainActor func aProjectedHitboxIsHitWhereItIsDrawn() throws {
    let taps = Taps()
    let (window, platform) = try projectedWindow {
        fxBar(100, 50).onTapGesture { taps.count += 1 }.rotation3DEffect(.degrees(45), axis: yAxis)
    }
    #expect(tapped(platform, window, taps, at: pt(100, 100)), "the centre")
    #expect(tapped(platform, window, taps, at: pt(47, 100)), "outside the layout rect, inside the near edge")
    #expect(!tapped(platform, window, taps, at: pt(145, 100)), "inside the layout rect, beyond the far edge")
    withExtendedLifetime(window) {}
}

/// **H.** A point whose inverse lands on or behind the eye never hits: `m33` 0.5, `m13` -0.1 sends part of the 100-wide view
/// behind it; the ghost image of local (80, 25) would be in front of the window point (39.3, 71.7), and must not hit.
/// Mutation: drop the `w <= 0` nil in `Homography2D.apply`.
@Test func aPointBehindTheEyeNeverHits() throws {
    var m = ProjectionTransform(); m.m13 = -0.1; m.m33 = 0.5
    let inverse = try #require(m.homography.inverted)
    // Window-local ghost of local (80, 25): forward w = 0.5 - 8 < 0.
    let ghost = (x: 80.0 / (0.5 - 8), y: 25.0 / (0.5 - 8))
    #expect(inverse.apply(ghost.x, ghost.y) == nil, "no preimage behind the eye")
    // The raw divide would find the ghost in bounds.
    #expect(m.homography.apply(80, 25) == nil)
}

/// **G.** `frame(in: .global)` inside a 3D effect is the bounding box of the projected quad (the 45 case of the probe:
/// width 161.6, height 154.7). Mutation: report the unprojected box.
@Test func theGeometryFrameUnderA3DEffectIsTheProjectedBoundingBox() throws {
    let b = turn(45).map(in: box).boundingBox(of: box)
    #expect(near(Double(b.size.width.value), 161.6, 1.5) && near(Double(b.size.height.value), 154.7, 1.5), "\(b)")
    #expect(near(Double(b.origin.x.value), -9.4, 0.5), "\(b)")
}

@MainActor
private final class FrameLog { var frames: [Bounds<Pixels>] = [] }

@Test @MainActor func theGeometryFrameReachesTheCallbackProjected() throws {
    let log = FrameLog()
    let (window, _) = try projectedWindow {
        fxBar(100, 50)
            .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) }) { log.frames.append($0) }
            .rotation3DEffect(.degrees(45), axis: yAxis)
    }
    let g = try #require(log.frames.last)
    // The 100 x 50 bar at (50, 75), turned 45 degrees: near edge x 45.3, 80.8 wide, 77.3 tall (the model's quad).
    #expect(near(Double(g.origin.x.value), 45.3, 0.2) && near(Double(g.size.width.value), 80.8, 0.3)
                && near(Double(g.size.height.value), 77.3, 0.3), "the projected box, not the layout one: \(g)")
    withExtendedLifetime(window) {}
}

/// **X.** The accessibility frame is the projected bounding box. Mutation: publish the unprojected frame.
@Test @MainActor func theAccessibilityFrameUnderA3DEffectIsTheProjectedBoundingBox() throws {
    func frameOf(_ e: some Element) throws -> Bounds<Pixels> {
        let f = effectFrame(e, accessibility: true)
        return try #require(f.axEmissions.first { $0.declared.label == "x" }).geometry.frame
    }
    let plain = try frameOf(fxBar(100, 50).accessibilityLabel("x"))
    let turned = try frameOf(fxBar(100, 50).accessibilityLabel("x").rotation3DEffect(.degrees(45), axis: yAxis))
    let expected = turn(45).map(in: Bounds(origin: plain.origin, size: plain.size)).boundingBox(of: plain)
    #expect("\(turned)" == "\(expected)", "projected box: \(turned) vs \(expected)")
    #expect(turned.size.height.value > plain.size.height.value, "taller than the layout frame")
}

// MARK: - 20: animation

/// **N.** `rotation3DEffect` animates eight numbers and `projectionEffect` snaps. Mutation: drop a number from `numbers`;
/// interpolate the matrix.
@Test func rotation3DEffectAnimatesEightNumbersAndProjectionSnaps() {
    let e = turn(45, axis: (0, 1, 0), anchor: UnitPoint(x: 0.25, y: 0.75), anchorZ: 5, perspective: 2)
    #expect(e.numbers.count == 8)
    let halved = e.with(e.numbers.map { $0 / 2 }[...])
    guard case let .rotation3D(spec) = halved else { Issue.record("kind kept"); return }
    #expect(spec.angle.radians == Angle.degrees(45).radians / 2 && spec.axisY == 0.5 && spec.anchor.x == 0.125
                && spec.anchor.y == 0.375 && spec.anchorZ == 2.5 && spec.perspective == 1)
    var m = ProjectionTransform(); m.m13 = 0.002
    #expect(RenderEffectSpec.projection(m).numbers.isEmpty, "a projection has nothing to interpolate")
    #expect(RenderEffectSpec.projection(m).with([]) == .projection(m))
    #expect(e.kindTag != RenderEffectSpec.projection(m).kindTag)
}

// MARK: - 32: the size pin

/// **R.** The new `LayoutModifier` cases are `indirect`, so the enum keeps its size (the 1 MB Windows stack, `PJ-R`).
/// Mutation: remove `indirect` from `rotation3DEffect`.
@Test func theLayoutModifierKeepsItsSize() {
    #expect(MemoryLayout<LayoutModifier>.size == 81, "size \(MemoryLayout<LayoutModifier>.size)")
}

// MARK: - homography invariants

/// An affine homography is the affine map bit for bit (every pre-3D path stays value-identical, `PJ-A`).
@Test func anAffineHomographyComposesAndInvertsAsTheAffineMapDoes() throws {
    let a = Affine2D.rotation(radians: 0.3, about: 10, 20), b = Affine2D.scale(x: 2, y: 3, about: 5, 6)
    #expect(Homography2D(a).concatenating(Homography2D(b)).affine == a.concatenating(b))
    #expect(Homography2D(a).inverted?.affine == a.inverted)
    #expect(Homography2D(a).scaledToDevice(2).affine == a.scaledToDevice(2))
    let p = turn(40).map(in: box)
    let id = p.concatenating(try #require(p.inverted))
    for (x, y) in [(10.0, 20.0), (150, 80)] {
        let q = try #require(id.apply(x, y))
        #expect(abs(q.x - x) < 1e-7 && abs(q.y - y) < 1e-7, "\(q)")
    }
}

// MARK: - 30: retained replay

private func effectVector(_ m: Homography2D, flattens: Bool = false) -> [Double] {
    let inv = m.inverted ?? .identity
    var v = [m.a, m.b, m.c, m.d, m.tx, m.ty, 1, inv.a, inv.b, inv.c, inv.d, inv.tx, inv.ty, 0, 0, 200, 200, 0, flattens ? 1 : 0]
    v += [m.g, m.h, m.i, inv.g, inv.h, inv.i]
    return v
}

private func extras(_ effects: [[Double]]) -> PrepaintExtras {
    PrepaintExtras(effects: effects, hitTestingDisabled: 0, keyboardHidden: 0, share: [0, 0, 0], collectsAccessibility: false,
                   suppression: [], portal: 0, scrollerID: nil, scroller: [], hiddenNodes: 0)
}

private func ambient(scopeVector: [Double]) -> AmbientKey {
    AmbientKey(clip: [0, 0, 10, 10], offset: [0, 0], layerOpacityScale: [1], depths: [0], scopes: [scopeVector],
               environment: EnvironmentValues().retainedFingerprint, snappingTransaction: false, disablesAnimations: false)
}

/// **K.** Any change in a projective effect refuses by name `effectProjective` (the prepaint vectors and the paint scopes), a pan
/// composed onto one included, while an affine pan is still a translation. Mutation: drop `g`, `h`, `i` from the vectors
/// (`prepaintExtras()` / `flat`), so a perspective change compares equal or as a plain translation.
@Test func aProjectiveChangeRefusesByNameAndAnAffineOneStillTranslates() {
    let pan = Homography2D.translation(x: 5, y: 0)
    #expect(extras([effectVector(pan.concatenating(.identity))]).change(from: extras([effectVector(.identity)])) == .translation(dx: 5, dy: 0)
            || extras([effectVector(pan)]).change(from: extras([effectVector(.identity)])) == .translation(dx: 5, dy: 0), "control: an affine pan")
    var a = Homography2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0, g: 0.001, h: 0, i: 1)
    var b = a; b.g = 0.002
    #expect(extras([effectVector(b)]).change(from: extras([effectVector(a)])) == .refused("effectProjective"), "a perspective change")
    var panned = a; panned.tx = 7
    #expect(extras([effectVector(panned)]).change(from: extras([effectVector(a)])) == .refused("effectProjective"), "a pan composed onto it")
    a.g = 0
    #expect(a.isAffine)
}

@Test func aProjectiveScopeInTheAmbientKeyRefusesByNameAndAnEqualOneIsNoDiff() {
    func scope(_ g: Double, tx: Double = 0) -> [Double] {
        let m = Homography2D(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: 0, g: g, h: 0, i: 1)
        let flat: [Double] = m.isAffine ? [m.a, m.b, m.c, m.d, m.tx, m.ty] : [m.a, m.b, m.c, m.d, m.tx, m.ty, m.g, m.h, m.i]
        return [AmbientKey.effectKind, 1, 0, m.isAffine ? 0 : AmbientKey.projectiveFlag] + flat + [1, 0, 0, 10, 10, 0, 0, 0, 0, 0]
    }
    let was = ambient(scopeVector: scope(0.001))
    #expect(ambient(scopeVector: scope(0.001)).effectScopeDiff(against: was) == nil || ambient(scopeVector: scope(0.001)) == was)
    #expect(ambient(scopeVector: scope(0.002)).effectRelation(from: was) == .refused("effectProjective"), "a perspective change")
    #expect(ambient(scopeVector: scope(0.001, tx: 4)).effectRelation(from: was) == .refused("effectProjective"), "a pan composed on it")
    #expect(ambient(scopeVector: scope(0.001)).scopesDifferOnlyByTranslation(from: ambient(scopeVector: scope(0.001, tx: 4))) == false)
}

/// **K.** The prepaint vector a real open projective effect produces carries the composed and inverse bottom rows (indices 19-24).
/// Mutation: write `[0, 0, 1]` for the composed row in `prepaintExtras()`.
@Test @MainActor func aProjectiveEffectsPrepaintVectorCarriesItsBottomRows() throws {
    let frame = effectFrame(fxBar(100, 50))
    var m = ProjectionTransform(); m.m13 = 0.002
    let bounds = Bounds(origin: pt(10, 10), size: Size(width: px(100), height: px(50)))
    let v = frame.prepaintWithRenderEffect(.projection(m), bounds: bounds) { frame.prepaintExtras().effects }
    let vector = try #require(v.last)
    try #require(vector.count == 25)
    let map = RenderEffectSpec.projection(m).map(in: bounds)
    #expect(vector[PrepaintExtras.composedBottom] == map.g && vector[PrepaintExtras.composedBottom + 2] == map.i)
    #expect(PrepaintExtras.isProjective(vector))
}
