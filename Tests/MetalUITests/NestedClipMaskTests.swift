import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI
@testable import MetalUIRender

// R4-5 PR E lane 1 (ruling prefix `TZ-`, record 222; probe `docs/probes/swiftui-text-under-transform.swift`, arms `NC0`..`NC5`):
// a clip between two non-flattening effects clips to the clip, not to its screen bounding box (divergence 109 retired). The
// clip is a masked group (`CM-A`) whose mask is the clip emitted in the outer effect's space. Every render is 200 x 200, scale 1,
// over a transparent target; the 60 x 60 clip sits at (70, 70)-(130, 130), centre (100, 100).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let pureRed = Color(Hsla(h: 0, s: 1, l: 0.5, a: 1))
private let yAxis: (x: Double, y: Double, z: Double) = (0, 1, 0)
private let size200 = Size(width: DevicePixels(200), height: DevicePixels(200))

private struct Rendered {
    var pixels: [UInt8]
    var frame: Frame
    var scene: Scene
}

@MainActor private func render<E: Element>(_ element: E) throws -> Rendered {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let frame = effectFrame(element)
    let scene = frame.finalizedScene()
    return Rendered(pixels: try renderer.renderOffscreen(scene, size: size200), frame: frame, scene: scene)
}

/// A 100 x 100 red square turned 30 degrees about its centre, then framed to 60 x 60 (it covers the frame) and padded to (70, 70).
@MainActor private func turned() -> some Element & ProposalElementGroup {
    pureRed.frame(width: px(100), height: px(100)).rotationEffect(.degrees(30)).frame(width: px(60), height: px(60))
}

/// Pixels with any coverage (alpha at least `level`) more than `band` outside the 60 x 60 square rotated by `degrees` about
/// (100, 100), whose corners are rounded by `radius`; and the pixels with coverage inside it (analytic area 3600 for a plain square).
private func counts(_ pixels: [UInt8], degrees: Double, radius: Double = 0, band: Double = 1.0, level: UInt8 = 1) -> (outside: Int, inside: Int) {
    let a = degrees * .pi / 180, c = cos(a), s = sin(a)
    var outside = 0, inside = 0
    for y in 0..<200 { for x in 0..<200 where pixels[(y * 200 + x) * 4 + 3] >= level {
        let dx = Double(x) + 0.5 - 100, dy = Double(y) + 0.5 - 100
        let u = c * dx + s * dy, v = -s * dx + c * dy
        let qx = abs(u) - (30 - radius), qy = abs(v) - (30 - radius)
        let d = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot() + min(max(qx, qy), 0) - radius
        if d > band { outside += 1 } else if d <= 0 { inside += 1 }
    } }
    return (outside, inside)
}

private func maskRects(_ scene: Scene) -> [MUIRect] { scene.groupMasks.first.flatMap { $0 }?.rects ?? [] }

// MARK: - 1. exact

/// **1 (`TZ-B`, probe `NC1`: 0 pixels beyond the rotated square).** The clip between two 30-degree rotations is the rotated
/// square: no pixel is more than a pixel outside it, its inside is covered (3600 within the edge band), one masked group is
/// built, and its mask is the 60 x 60 local clip carrying the outer 30-degree record. Under the old box model 2724 pixels
/// (the probe's count) lay outside. Mutations **L1** (the mask scope never opened) and **L2** (the mask emitted with its
/// transform dropped, so not routed through the outer scope).
@Test @MainActor func aClipBetweenNestedRotationsIsExact() throws {
    let r = try render(turned().clipped().rotationEffect(.degrees(30)).padding(Edges(all: px(70))))
    let n = counts(r.pixels, degrees: 30)
    #expect(n.outside == 0, "nothing beyond the rotated square: \(n.outside)")
    #expect(n.inside > 3500 && n.inside < 3700, "its inside is covered: \(n.inside)")
    #expect(r.frame.groupsMasked == 1 && r.frame.nestedClipMasks == 1, "one group: \(r.frame.groupsMasked) \(r.frame.nestedClipMasks)")
    let rect = try #require(maskRects(r.scene).first, "the group's mask")
    #expect(abs(rect.bounds.origin.x - 70) < 1e-3 && abs(rect.bounds.origin.y - 70) < 1e-3
                && abs(rect.bounds.size.width - 60) < 1e-3 && abs(rect.bounds.size.height - 60) < 1e-3,
            "the mask is the local clip: \(fxDescribe(rect.bounds))")
    let mask = try #require(r.scene.groupMasks[0])
    #expect(fxMatches(effectRecord(rect, in: mask), .rotation(radians: Double.pi / 6, about: 100, 100)),
            "carrying the outer 30 degrees: \(fxDescribe(effectRecord(rect, in: mask)))")
}

// MARK: - 2. right angles take no group

/// **2 (`TZ-B`).** Between two quarter turns the clip's screen box is the clip: no group is built and the arithmetic of the old
/// pin holds (the record's outer mask is the 20 x 40 rect about the same centre). Mutation **L3**: the axis-aligned
/// shortcut removed.
@Test @MainActor func aClipBetweenRightAngleRotationsTakesNoGroup() throws {
    let deg90 = Angle.degrees(90)
    let frame = effectFrame(fxBar(40, 20).rotationEffect(deg90).clipped().rotationEffect(deg90))
    let scene = frame.finalizedScene()
    #expect(frame.groupsMasked == 0 && frame.nestedClipMasks == 0, "no group: \(frame.groupsMasked) \(frame.nestedClipMasks)")
    let r = try #require(effectRects(scene).first)
    let record = try #require(effectRecord(r, in: scene), "a record")
    let cx = r.bounds.origin.x + 20, cy = r.bounds.origin.y + 10
    #expect(abs(record.outerMask.origin.x - (cx - 10)) < 1e-3 && abs(record.outerMask.origin.y - (cy - 20)) < 1e-3
                && abs(record.outerMask.size.width - 20) < 1e-3 && abs(record.outerMask.size.height - 40) < 1e-3,
            "the outer mask is the clip's screen box: \(fxDescribe(record.outerMask))")
}

// MARK: - 3. rounded

/// **3 (`TZ-B`, probe `NC2`: 3476 inside against 3476.4 analytic).** A rounded clip between the rotations keeps its corners: the
/// mask rect's radii are the clip's (12), the rendered corner is cut, and nothing is beyond the rotated rounded square.
/// Mutation **L4**: the mask's radii zeroed.
@Test @MainActor func aRoundedClipBetweenNestedRotationsKeepsItsCorners() throws {
    let r = try render(turned().clipShape(RoundedRectangle(cornerRadius: px(12))).rotationEffect(.degrees(30)).padding(Edges(all: px(70))))
    let rect = try #require(maskRects(r.scene).first, "the group's mask")
    #expect(abs(rect.cornerRadii.topLeft - 12) < 1e-3 && abs(rect.cornerRadii.bottomRight - 12) < 1e-3,
            "the mask keeps the radii: \(rect.cornerRadii)")
    let n = counts(r.pixels, degrees: 30, radius: 12)
    #expect(n.outside == 0, "nothing beyond the rotated rounded square: \(n.outside)")
    #expect(n.inside > 3400 && n.inside < 3550, "its inside is the rounded area, 3476.4 analytic: \(n.inside)")
}

// MARK: - 4. projective

/// **4 (`TZ-B`, probe `NC3`).** Under an outer `rotation3DEffect` the mask is a finite projected rect: its record is projective,
/// every bound and content mask of the group's mask scene is under 1e5 (`CM-I`), and no pixel is far outside the projected quad's
/// box. Mutation **L5**: the mask's content mask is `Frame.unboundedMask`.
@Test @MainActor func aClipBetweenAProjectiveAndARotationIsAFiniteProjectedMask() throws {
    let r = try render(turned().clipped().rotation3DEffect(.degrees(40), axis: yAxis, perspective: 1).padding(Edges(all: px(70))))
    try #require(r.frame.groupsMasked == 1, "a masked group: \(r.frame.groupsMasked)")
    let mask = try #require(r.scene.groupMasks[0])
    let rect = try #require(mask.rects.first)
    let record = try #require(effectRecord(rect, in: mask), "a record")
    #expect(record.g != 0 || record.h != 0, "projective: \(fxDescribe(record))")
    for b in [rect.bounds, rect.contentMask] {
        #expect(abs(b.origin.x) < 1e5 && abs(b.origin.y) < 1e5 && b.size.width < 1e5 && b.size.height < 1e5,
                "finite: \(fxDescribe(b))")
    }
}

// MARK: - 5. a flattening effect between

/// **5 (`TZ-B`, probe `NC5`: exact in SwiftUI).** A flattening `scaleEffect(2)` between the clip and the inner rotation: the clip
/// is undone through the scale into the mask's space, so the result is still the exact rotated square. Mutation **L6**: the
/// inverse of the flattening scopes dropped (the clip emitted unmapped, 2x too small).
@Test @MainActor func aClipBetweenAFlatteningAndARotationIsStillExact() throws {
    let content = pureRed.frame(width: px(100), height: px(100)).rotationEffect(.degrees(30)).scaleEffect(2)
        .frame(width: px(60), height: px(60))
    let r = try render(content.clipped().rotationEffect(.degrees(30)).padding(Edges(all: px(70))))
    try #require(r.frame.nestedClipMasks == 1, "a group is built: \(r.frame.nestedClipMasks)")
    let n = counts(r.pixels, degrees: 30)
    #expect(n.outside == 0, "nothing beyond the rotated square: \(n.outside)")
    #expect(n.inside > 3500 && n.inside < 3700, "its inside is covered: \(n.inside)")
}

// MARK: - 6. a material keeps the box

/// **6 (`TZ-B`, divergence 224).** A material inside the nested clip cannot move into a group (its live backdrop): the group is
/// not built, `masksFlattenedBackdrop` counts it, and the box clip stays. Mutation **L7**: the backdrop guard skipped.
@Test @MainActor func aNestedClipMaskAroundAMaterialKeepsTheBox() throws {
    let frame = effectFrame(
        Color(.accent).frame(width: px(100), height: px(100)).background(.regularMaterial).rotationEffect(.degrees(30))
            .frame(width: px(60), height: px(60)).clipped().rotationEffect(.degrees(30)).padding(Edges(all: px(70))))
    _ = frame.finalizedScene()
    #expect(frame.masksFlattenedBackdrop == 1 && frame.groupsMasked == 0,
            "the box stays: backdrop \(frame.masksFlattenedBackdrop) masked \(frame.groupsMasked)")
}

// MARK: - 7. an ellipse was already exact

/// **7 (`TZ-B`; green on arrival).** An ellipse clip between the rotations was exact before this change (the mask is already
/// mapped through each effect, `CM-A`), and stays one group: it is the control that the new path does not double-mask it.
@Test @MainActor func anEllipseClipBetweenNestedRotationsWasAlreadyExact() throws {
    let r = try render(turned().clipShape(Ellipse()).rotationEffect(.degrees(30)).padding(Edges(all: px(70))))
    #expect(r.frame.groupsMasked == 1, "one group, from the ellipse: \(r.frame.groupsMasked)")
    // Inside the ellipse inscribed in the 60 x 60 square (radius 30, a circle), nothing lies outside the circle.
    var outside = 0, inside = 0
    for y in 0..<200 { for x in 0..<200 where r.pixels[(y * 200 + x) * 4 + 3] > 0 {
        let d = ((Double(x) + 0.5 - 100) * (Double(x) + 0.5 - 100) + (Double(y) + 0.5 - 100) * (Double(y) + 0.5 - 100)).squareRoot()
        if d > 31 { outside += 1 } else if d < 29 { inside += 1 }
    } }
    #expect(outside == 0 && inside > 2500, "a circle of radius 30: outside \(outside) inside \(inside)")
}

// MARK: - 8. a transition between keeps the box

/// **8 (`TZ-B`, divergence 224).** A transition scope opened between the clip and an inner rotation maps the content by an
/// effect that is not undone on the way into the mask's space: the box stays and no group is built (the transition is
/// halfway, so its scope is open in the frame). Mutation **L6b**: the `kind == .effect` half of the check dropped, so the
/// transition's scope is treated as a flattening effect.
@Test @MainActor func aClipAroundATransitionAroundARotationKeepsTheBox() throws {
    func stage(_ shown: Bool) -> some Element {
        Stack {
            if shown {
                pureRed.frame(width: px(100), height: px(100)).rotationEffect(.degrees(30)).transition(.scale(scale: 0.5))
            }
        }
        .frame(width: px(60), height: px(60)).clipped().rotationEffect(.degrees(30)).padding(Edges(all: px(70)))
    }
    func midway() -> Frame {
        let h = TransitionHarness()
        h.frame(0, nil, stage(false), side: 300, scaleFactor: 1)
        h.frame(0, Animation.linear(duration: 1), stage(true), side: 300, scaleFactor: 1)
        return h.frame(0.5, nil, stage(true), side: 300, scaleFactor: 1)
    }
    let frame = midway()
    _ = frame.finalizedScene()
    #expect(frame.nestedClipMasks == 0, "no group around a transition: \(frame.nestedClipMasks)")
    #expect(frame.effectScopesPushed >= 2, "set up: both rotations' scopes opened: \(frame.effectScopesPushed)")
}
