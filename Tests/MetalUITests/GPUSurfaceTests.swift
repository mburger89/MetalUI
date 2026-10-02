import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// MetalView lane 1, tests 1.11–1.20 and 1.13b (rulings `MV-A`, `MV-B`, `MV-D`,
// `MV-E` item 2, `MV-G`, `MV-I`, `MV-L` items 1 and 3; spec
// `docs/superpowers/specs/2026-10-01-metal-view-design.md` §2, §4, §5, §6,
// §8). The element side of an app-owned surface: `GPUSurface`, its sizing,
// `Frame.drawSurface`, the window's `SurfaceRegistry` and the requests a
// `Window` hands its renderer. SwiftUI's side is
// `docs/probes/swiftui-metal-view.swift` (arms G1, G2, D1, C1–C3, R0–R3).
//
// **No test sleeps**: frames are headless `Frame`s or a real `Window` on a
// `FakePlatformWindow`, drawn by `drawFrameIfNeeded()`/`simulateTick`. A test
// that reads the requests a window hands its renderer installs the fake's
// **spy** renderer, which records them and forwards the frame to the real
// Metal renderer with none — so no surface table runs and a wrong answer is
// read as a value, not a process trap (`MV-L` item 1).

// MARK: - Fixtures

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func size(_ w: Double, _ h: Double) -> SizeD { SizeD(width: w, height: h) }
private func floats(_ b: MUIBounds) -> [Float] { [b.origin.x, b.origin.y, b.size.width, b.size.height] }
private func floats(_ c: MUICorners) -> [Float] { [c.topLeft, c.topRight, c.bottomRight, c.bottomLeft] }

@MainActor
private final class Log { var entries: [String] = [] }

@MainActor
private final class Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

/// A surface whose draw closure does nothing: lane 1 never draws one (no
/// renderer runs the table yet), it only places and requests it.
@MainActor
private func surface(_ policy: RedrawPolicy = .onDemand) -> GPUSurface {
    GPUSurface(redraw: policy) { _ in }
}

/// Renders `root` into a `side × side` frame at `scaleFactor`.
@MainActor
@discardableResult
private func render<E: Element>(_ root: E, side: Float = 300, scaleFactor: Float = 1,
                                accessibility: Bool = false) -> Frame {
    var root = root
    let frame = Frame(contentSize: Size(width: px(side), height: px(side)), scaleFactor: scaleFactor,
                      collectsAccessibility: accessibility)
    frame.render(&root)
    return frame
}

/// A `side × side` window over `content` whose frames go through the fake's
/// spy renderer, one frame drawn. The caller keeps the window alive.
@MainActor
private func spiedWindow<Root: Element>(side: Int = 300, startsDisplayLink: Bool = false,
                                        drawsFirstFrame: Bool = true,
                                        _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow, SpyWindowRenderer) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: side,
                                                startsDisplayLink: startsDisplayLink, content: content)
    let spy = SpyWindowRenderer(inner: platform.windowRenderer)
    platform.spyRenderer = spy
    if drawsFirstFrame { window.drawFrameIfNeeded() }
    return (window, platform, spy)
}

@MainActor
private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

// MARK: - 1.11 sizing (MV-B)

/// **1.11** (`MV-B`; probe G1 = P1: `Canvas` answers like `Color` — the
/// proposal, 10 on a nil axis, ∞ at ∞; G2, an `MTKView` representable, is the
/// separating arm at 0 on a nil axis). Through the kernel at probe S1's five
/// proposals: nil×nil, 100×60, 0×0, ∞×∞, 100×nil.
///
/// Mutation **M1n**: answer 0 on a nil axis (G2's answer).
@Test @MainActor func aSurfaceAnswersItsProposalAndTenOnANilAxis() throws {
    let inf = Double.infinity
    let g1 = [size(10, 10), size(100, 60), size(0, 0), size(inf, inf), size(100, 10)]
    let g2 = [size(0, 0), size(100, 60), size(0, 0), size(inf, inf), size(100, 0)]
    try #require(g1 != g2, "G1 and G2 must separate")
    #expect(kernelAnswers(surface()) == g1, "G1: Canvas's (and Color's, P1) answers")
    #expect(kernelAnswers(surface(.continuous)) == g1, "the policy does not change sizing")
}

// MARK: - 1.12 the target's device-pixel size (MV-E item 2)

/// **1.12** (`MV-E` item 2; probe D1: a 100×60-pt `MTKView` at backing scale
/// 2.0 has a 200×120-px drawable). A surface's target is its laid-out bounds ×
/// the frame's scale, each side `Int((pt × scale).rounded())`, clamped to
/// 8192: 100×60 @2 → 200×120; 101×61 @1.5 → 152×92 (151.5 and 91.5 round
/// up); 9000×10 @1 → 8192×10 — the quad itself keeps the full 9000 pt (the
/// target is sampled stretched).
///
/// Mutations **M1o**: `floor` for `rounded` (151×91); **M1p**: drop the clamp.
@Test @MainActor func aSurfacesTargetIsItsBoundsTimesTheScaleRounded() throws {
    func target(_ w: Float, _ h: Float, _ scale: Float) throws -> (SurfaceTarget, MUIImage) {
        let frame = render(surface().frame(width: px(w), height: px(h)), scaleFactor: scale)
        try #require(frame.scene.surfaceTargets.count == 1 && frame.scene.surfaces.count == 1,
                     "set up: one surface at \(w)×\(h)@\(scale)")
        return (frame.scene.surfaceTargets[0], frame.scene.surfaces[0])
    }
    let d1 = try target(100, 60, 2)
    #expect([d1.0.width, d1.0.height] == [200, 120], "D1: bounds × scale")
    #expect(floats(d1.1.bounds).suffix(2) == [200, 120], "the quad in device pixels")
    let fractional = try target(101, 61, 1.5)
    #expect([fractional.0.width, fractional.0.height] == [152, 92], "rounded, not floored")
    let huge = try target(9000, 10, 1)
    #expect([huge.0.width, huge.0.height] == [8192, 10], "clamped to 8192")
    #expect(huge.1.bounds.size.width == 9000, "the quad is not clamped")
}

// MARK: - 1.13, 1.13b identity (SurfaceRegistry)

/// **1.13** (`MV-E` items 1 and 3). A surface keeps its `SurfaceID` across
/// frames — so its target is reused — and two placements get two.
///
/// Mutation **M1q**: mint a fresh id every frame.
@Test @MainActor func aSurfaceKeepsItsIDAcrossFramesAndTwoPlacementsGetTwo() throws {
    let (window, _, spy) = try spiedWindow {
        HStack(spacing: px(0)) {
            surface().frame(width: px(50), height: px(50))
            surface().frame(width: px(60), height: px(50))
        }
    }
    defer { withExtendedLifetime(window) {} }
    redraw(window)
    try #require(spy.frames.count == 2, "set up: two frames drawn")
    let first = spy.frames[0].map(\.target), second = spy.frames[1].map(\.target)
    try #require(first.count == 2 && second.count == 2, "two requests a frame: \(first), \(second)")
    #expect(first[0].id != first[1].id, "two placements, two ids")
    #expect(first == second, "the same ids and sizes next frame")
    #expect([first[0].width, first[1].width] == [50, 60], "in paint order")
}

/// **1.13b** (`MV-L` item 1; divergence 72's shape). Two siblings sharing one
/// `.id` share one `GlobalElementID`; the registry's key is
/// (`GlobalElementID`, occurrence), so each still gets its own target —
/// keyed by the id alone, both would request one target and a real
/// renderer's table would trap.
///
/// Mutation **M1q′**: key the registry by `GlobalElementID` alone.
@Test @MainActor func twoSiblingSurfacesSharingOneIDGetTwoTargets() throws {
    let (window, _, spy) = try spiedWindow {
        HStack(spacing: px(0)) {
            surface().frame(width: px(50), height: px(50)).id("a")
            surface().frame(width: px(50), height: px(50)).id("a")
        }
    }
    defer { withExtendedLifetime(window) {} }
    redraw(window)
    try #require(spy.frames.count == 2, "set up: two frames drawn")
    let first = spy.frames[0].map(\.target.id), second = spy.frames[1].map(\.target.id)
    try #require(first.count == 2 && second.count == 2, "two requests a frame: \(first), \(second)")
    #expect(first[0] != first[1], "one target per placement: \(first)")
    #expect(first == second, "kept across frames while the order holds: \(first) vs \(second)")
}

// MARK: - 1.14 no GPU work (MV-G item 4)

/// **1.14** (`MV-G` item 4). A surface with a zero side, one whose bounds miss
/// the active clip, and one at opacity 0 emit no quad and no request; the
/// control arm — the clipped arm's tree with the surface inside the clip —
/// emits both. The clipped arm: a 60-pt rectangle and a 20-pt surface in a
/// 50-pt clipped frame, so the surface sits at x 60…80, outside 0…50.
///
/// Mutations **M1r**: drop the clip test (the clipped arm only); **M1s**: drop
/// the opacity test (the transparent arm only).
@Test @MainActor func aZeroSizedClippedOrTransparentSurfaceRequestsNothing() throws {
    func strip(lead: Float) -> some ProposalElementGroup {
        HStack(spacing: px(0)) {
            Rectangle().frame(width: px(lead), height: px(10))
            surface().frame(width: px(20), height: px(10))
        }
        .frame(width: px(50), height: px(10), alignment: .leading)
        .clipped()
    }
    let control = render(strip(lead: 10))
    try #require(control.scene.surfaces.count == 1 && control.surfaceRequests.count == 1,
                 "control: the surface inside the clip paints and requests")
    let arms: [(String, Frame)] = [
        ("zero", render(surface().frame(width: px(0), height: px(10)))),
        ("clipped", render(strip(lead: 60))),
        ("transparent", render(surface().frame(width: px(20), height: px(10)).opacity(0))),
    ]
    for (name, frame) in arms {
        #expect(frame.scene.surfaces.isEmpty && frame.scene.surfaceTargets.isEmpty,
                "\(name): no quad (\(frame.scene.surfaces.count))")
        #expect(frame.surfaceRequests.isEmpty, "\(name): no request (\(frame.surfaceRequests.count))")
    }
}

// MARK: - 1.15 .continuous and the display link (MV-G item 3)

/// **1.15** (`MV-G` item 3, `MV-L` item 3; CLAUDE.md "Animation": never raise
/// both). A `.continuous` surface keeps the window drawing through
/// `noteActiveAnimation()` — `hasActiveAnimations` true — and **not** through
/// `requestAnotherFrame()`: `wantsAnotherFrame` stays false, so the window is
/// not dirty. Either flag alone keeps a window drawing, so only the second
/// clause separates them. An `.onDemand` surface raises neither; once the
/// continuous surface stops painting, both read false.
///
/// Mutations **M1t**: delete `noteActiveAnimation()`; **M1u**:
/// `requestAnotherFrame()` in its place.
@Test @MainActor func aContinuousSurfaceKeepsTheWindowAnimatingOnlyWhilePainted() throws {
    let continuous = render(surface(.continuous).frame(width: px(20), height: px(20)))
    #expect(continuous.hasActiveAnimations, "a painted continuous surface notes an active animation")
    #expect(!continuous.wantsAnotherFrame, "and never asks for another frame")
    let onDemand = render(surface(.onDemand).frame(width: px(20), height: px(20)))
    #expect(!onDemand.hasActiveAnimations && !onDemand.wantsAnotherFrame, "an .onDemand surface raises neither")

    let shown = Flag(true)
    let (window, _, _) = try spiedWindow {
        HStack {
            if shown.value { surface(.continuous).frame(width: px(20), height: px(20)) }
        }
    }
    defer { withExtendedLifetime(window) {} }
    #expect(window.hasActiveAnimations, "the window keeps animating while it paints")
    #expect(!window.needsRedraw, "without being dirtied")
    shown.value = false
    redraw(window)
    #expect(!window.hasActiveAnimations && !window.needsRedraw, "gone: the link may pause")
}

// MARK: - 1.16 the seam (MV-F items 1–2)

/// **1.16** (`MV-F` items 1–2). `Window` hands the frame's requests to its
/// renderer through `finishFrame(scene:atlas:surfaces:)`: one per painted
/// surface, carrying its target (bounds × scale), the frame's scale, the
/// frame's display-link timestamp, its policy and its `value:`.
///
/// Mutation **M1v**: `Window` calls `finishFrame(scene:atlas:)` (the spy
/// receives none).
@Test @MainActor func theWindowHandsTheFramesSurfaceRequestsToItsRenderer() throws {
    let (window, platform, spy) = try spiedWindow(startsDisplayLink: true, drawsFirstFrame: false) {
        GPUSurface(value: 5) { _ in }.frame(width: px(40), height: px(30))
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 2.5)
    try #require(spy.frames.count == 1, "set up: the tick drew one frame")
    let requests = spy.frames[0]
    try #require(requests.count == 1, "one request: \(requests.map(\.target))")
    let r = requests[0]
    #expect([r.target.width, r.target.height] == [40, 30])
    #expect(r.scaleFactor == 1 && r.time == 2.5 && r.policy == .onDemand)
    #expect(r.value == AnyHashable(5))
    #expect(window.lastScene.surfaceTargets == [r.target], "the request names the scene's target")
}

// MARK: - 1.17 compositing exactly as an image (MV-D)

/// **1.17** (`MV-D`; probe C1–C3 against P2: SwiftUI composites an app's Metal
/// surface through the same clip and opacity as any view). A surface's quad
/// takes the active clip, its radii, the opacity and the layer exactly as an
/// `Image` in the same place does; the unclipped arm separates (its mask has
/// square corners).
///
/// Mutation **M1w**: emit with no `activeClip`.
@Test @MainActor func aSurfaceQuadTakesTheActiveClipRadiiOpacityAndLayerAsAnImageDoes() throws {
    let bitmap = ImageBitmap(width: 1, height: 1, rgba: [255, 0, 0, 255])
    func clipped<C: ProposalElementGroup>(_ content: C) -> some ProposalElementGroup {
        HStack(spacing: px(0)) { content }.clipShape(RoundedRectangle(cornerRadius: px(8))).opacity(0.5)
    }
    let s = render(clipped(surface().frame(width: px(40), height: px(40))), scaleFactor: 2).scene
    let i = render(clipped(Image(decorative: bitmap, scale: 1).resizable().frame(width: px(40), height: px(40))),
                   scaleFactor: 2).scene
    let bare = render(HStack(spacing: px(0)) { surface().frame(width: px(40), height: px(40)) }.opacity(0.5),
                      scaleFactor: 2).scene
    try #require(s.surfaces.count == 1 && i.images.count == 1 && bare.surfaces.count == 1, "set up")
    let sq = s.surfaces[0], iq = i.images[0]
    try #require(floats(sq.maskCornerRadii) != floats(bare.surfaces[0].maskCornerRadii),
                 "the unclipped arm must separate")
    #expect(floats(sq.bounds) == floats(iq.bounds), "bounds")
    #expect(floats(sq.contentMask) == floats(iq.contentMask), "C1/C2: the clip")
    #expect(floats(sq.maskCornerRadii) == floats(iq.maskCornerRadii), "C2: its radii")
    #expect(floats(sq.maskCornerRadii) == [16, 16, 16, 16], "8 pt at scale 2")
    #expect(sq.opacity == iq.opacity && sq.opacity == 0.5, "C3: the opacity")
    #expect(s.layer(of: .surface, at: 0) == i.layer(of: .image, at: 0), "the layer")
    #expect(sq.filter == 0, "linear (MV-D)")
}

// MARK: - 1.18 a transition's ghost (MV-E item 1)

/// **1.18** (`MV-E` item 1, `MV-D`). A surface removed under
/// `.transition(.opacity)` leaves a ghost that replays its quad over its last
/// target — referenced, so a renderer's table keeps it — with **no request**,
/// so it is not redrawn: the ghost shows the last contents, fading.
///
/// Mutation **M1x**: drop `.surface` from `TransitionEffect.apply`'s replay
/// (the ghost loses the quad).
@Test @MainActor func aRemovedSurfacesGhostReferencesItsTargetWithoutARequest() throws {
    let h = TransitionHarness()
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: px(200), height: px(100))
                if shown { surface().frame(width: px(50), height: px(30)).transition(.opacity) }
            }
        }
    }
    let rest = h.frame(0, nil, tree(true))
    try #require(rest.scene.surfaceTargets.count == 1 && rest.surfaceRequests.count == 1,
                 "set up: the live surface paints and requests")
    let target = rest.scene.surfaceTargets[0]
    let start = h.frame(0, .linear(duration: 1), tree(false))
    let mid = h.frame(0.5, nil, tree(false))
    let end = h.frame(1, nil, tree(false))
    for (name, f, alpha) in [("start", start, Float(1)), ("mid", mid, Float(0.5))] {
        #expect(f.scene.surfaceTargets == [target], "\(name): the ghost references the last target")
        #expect(f.scene.surfaces.map(\.opacity) == [alpha], "\(name): one quad at alpha \(alpha)")
        #expect(f.scene.surfaces.map { floats($0.bounds) } == rest.scene.surfaces.map { floats($0.bounds) },
                "\(name): at its last place")
        #expect(f.surfaceRequests.isEmpty, "\(name): never redrawn")
    }
    #expect(end.scene.surfaces.isEmpty && end.scene.surfaceTargets.isEmpty, "landed: gone, so released")
}

// MARK: - 1.19 a drag preview (MV-D)

/// **1.19** (`MV-D`, `DN-J`). A dragged surface's default preview replays its
/// quad translated by the pointer's move at alpha × 0.7 — over the same
/// target, carried once — while the source keeps painting and requesting.
///
/// Mutation **M1y**: `replayed(mask:layer:)` drops `.surface`.
@Test @MainActor func aDraggedSurfacesPreviewReplaysItsQuad() throws {
    let (window, platform, spy) = try spiedWindow(side: 400, startsDisplayLink: true) {
        HStack(spacing: px(0)) {
            surface().frame(width: px(200), height: px(200)).draggable("s")
            Rectangle().frame(width: px(200), height: px(200))
        }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateResize(to: Size(width: px(400), height: px(200)))
    window.drawFrameIfNeeded()
    let before = window.lastScene.surfaces
    try #require(before.count == 1 && floats(before[0].bounds) == [0, 0, 200, 200],
                 "set up: the source paints at the origin: \(before.map { floats($0.bounds) })")
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(100, 100))))
    platform.simulateInput(.mouseDragged(MouseEvent(position: pt(101, 100))))
    try #require(window.dragSession != nil, "set up: the drag began")
    window.drawFrameIfNeeded()
    platform.simulateInput(.mouseDragged(MouseEvent(position: pt(150, 100))))
    window.drawFrameIfNeeded()
    let scene = window.lastScene
    #expect(scene.surfaceTargets.count == 1, "one target however often it is drawn")
    let copies = scene.surfaces.filter { floats($0.bounds) == [50, 0, 200, 200] }
    try #require(copies.count == 1, "one translated copy: \(scene.surfaces.map { floats($0.bounds) })")
    #expect(abs(copies[0].opacity - 0.7) < 1e-5, "alpha × 0.7 (DN-J item 2)")
    #expect(scene.surfaces.contains { floats($0.bounds) == [0, 0, 200, 200] }, "the source keeps painting")
    #expect(spy.frames.last?.count == 1, "one request: the preview is not a second paint")
}

// MARK: - 1.20 input and accessibility (MV-I)

/// **1.20** (`MV-I`). A bare surface registers no hitbox and no accessibility
/// record — like `Image(decorative:)` and `Rectangle` — and takes a tap through
/// `.onTapGesture` like any proposal leaf, with no special path.
///
/// Mutation **M1z**: `GPUSurface.prepaint` inserts a hitbox (the bare arm).
@Test @MainActor func aSurfaceRegistersNoHitboxOrAccessibilityButTakesATapThroughOnTapGesture() throws {
    let bare = render(surface().frame(width: px(100), height: px(100)), accessibility: true)
    try #require(bare.scene.surfaces.count == 1, "set up: the bare surface paints")
    #expect(bare.hitboxes.isEmpty, "no hitbox: \(bare.hitboxes.map(\.bounds))")
    #expect(bare.axEmissions.isEmpty && bare.axNodes.isEmpty, "no accessibility record")

    let log = Log()
    let (window, platform, _) = try spiedWindow {
        surface().frame(width: px(100), height: px(100)).onTapGesture { log.entries.append("tap") }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(150, 150))))
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(150, 150))))
    #expect(log.entries == ["tap"], "a tap reaches it through onTapGesture")
}
