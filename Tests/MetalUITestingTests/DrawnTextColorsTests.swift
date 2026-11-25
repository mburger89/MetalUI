import Foundation
import MetalUI
import MetalUICore
import MetalUIScene
import MetalUITesting
import Testing

// `TestWindow.drawnTextColors(in:)` (ruling `HT-AE`, Sift gap G19): the colours a test element's text was drawn in, read
// from the frame's own scene. Counters and colours, never a clock; the harness text system; PLAIN imports.

private let red = Hsla.rgb(0xFF0000), blue = Hsla.rgb(0x0000FF)

/// Whether two colours are the same within what a trip through HSLA loses.
private func same(_ a: Hsla, _ b: Hsla) -> Bool {
    let x = a.toRgba(), y = b.toRgba()
    return abs(x.r - y.r) < 0.01 && abs(x.g - y.g) < 0.01 && abs(x.b - y.b) < 0.01 && abs(x.a - y.a) < 0.01
}

@MainActor private func options() -> HeadlessPlatformWindow.Options { .init(accessibilityClientActive: true) }

private func mixed() -> AttributedString {
    var plain = AttributedString("see ")
    plain.foregroundColor = Color(red)
    var tail = AttributedString("docs")
    tail.foregroundColor = Color(blue)
    return plain + tail
}

@MainActor private func openDemo(scale: Float = 1) throws -> TestWindow {
    try harnessWindow(size: sz(300, 120), scaleFactor: scale, options: options()) {
        VStack(alignment: .leading, spacing: 8) {
            Text("solid").foregroundColor(Color(red)).accessibilityIdentifier("solid")
            Text(mixed()).accessibilityIdentifier("mixed")
            Text("faded").foregroundColor(Color(blue)).opacity(0.5).accessibilityIdentifier("faded")
            Text("round").foregroundColor(Color(red)).clipShape(Ellipse()).accessibilityIdentifier("round")
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("all")
    }
}

/// One colour for a `Text` of one colour; each element answers its own text only, so a neighbour's colour does not leak.
/// Mutation: the query ignores the element's frame (returns every glyph's colour) must redden it.
@Test @MainActor func aTextOfOneColourAnswersThatColourAlone() throws {
    let w = try openDemo()
    let solid = try w.drawnTextColors(in: w.element(identifier: "solid"))
    #expect(solid.count == 1 && same(solid[0], red), "\(solid)")
}

/// A styled run is its own entry, in paint order: red, then blue. Mutation: the dedupe is dropped (one entry per glyph)
/// or the order reversed must redden it.
@Test @MainActor func aStyledRunAddsItsColourInPaintOrder() throws {
    let w = try openDemo()
    let runs = try w.drawnTextColors(in: w.element(identifier: "mixed"))
    #expect(runs.count == 2 && same(runs[0], red) && same(runs[1], blue), "\(runs)")
}

/// A container answers the colours of everything inside it; an element that drew no text answers none; the same
/// answers at 2x, where the scene is in device pixels. Mutation: the query forgets the scale factor must redden it.
@Test @MainActor func aContainerAnswersEveryTextInsideAndTheScaleFactorIsApplied() throws {
    for scale: Float in [1, 2] {
        let w = try openDemo(scale: scale)
        let all = try w.drawnTextColors(in: w.element(identifier: "all"))
        // red (the solid text and the first run share one), blue, the faded blue, red: runs merge across elements.
        #expect(all.count == 4 && same(all[0], red) && same(all[1], blue) && all[2].a < 0.6 && same(all[3], red), "x\(scale): \(all)")
        let solid = try w.drawnTextColors(in: w.element(identifier: "solid"))
        #expect(solid.count == 1 && same(solid[0], red), "x\(scale): \(solid)")
    }
}

/// Text inside an offscreen group (an ellipse clip, which the per-primitive mask cannot express) is reached too
/// (`allGlyphs`, `CT-A`): it is in `scene.groupScenes`, not `scene.glyphs`.
/// Mutation: the query reads `scene.glyphs` instead of `allGlyphs` must redden it.
@Test @MainActor func textInsideAnOffscreenGroupIsReached() throws {
    let w = try openDemo()
    #expect(w.scene.groupScenes.count >= 1, "control: the ellipse clip made a group")
    let round = try w.drawnTextColors(in: w.element(identifier: "round"))
    #expect(round.count == 1 && same(round[0], red), "\(round)")
}

/// The opacity in effect is folded into the alpha of text drawn under it.
/// Mutation: the opacity dropped from the colour must redden it.
@Test @MainActor func textUnderAnOpacityKeepsItsOpacityInItsAlpha() throws {
    let w = try openDemo()
    let faded = try w.drawnTextColors(in: w.element(identifier: "faded"))
    try #require(faded.count == 1, "\(faded)")
    #expect(abs(faded[0].toRgba().a - 0.5) < 0.01 && same(Hsla(h: faded[0].h, s: faded[0].s, l: faded[0].l, a: 1), blue),
            "\(faded)")
}

/// Zero production cost (`HT-AE`): the query reads the finished frame and records nothing while one draws, so a window
/// asked every frame did the same work per frame as a window never asked, and a glyph is the record it was.
/// Mutation: a recording hook in the frame (a counter bumped per frame inside `Window`) is NOT what this guards; the
/// guard is that `FrameWork` and the glyph record are equal with and without the query.
@Test @MainActor func askingForDrawnTextColorsCostsTheFrameNothing() throws {
    let asked = try openDemo(), quiet = try openDemo()
    for w in [asked, quiet] { w.window.testingTimelineClockOffset = 0 }
    func step(_ w: TestWindow) { w.window.setNeedsRedraw(); w.tick() }
    for _ in 0..<6 { step(asked); step(quiet) }
    var askedWork = FrameWork(), quietWork = FrameWork()
    for _ in 0..<4 {
        step(asked)
        _ = try asked.drawnTextColors(in: asked.element(identifier: "mixed"))
        // swiftlint:disable:next shorthand_operator - `FrameWork` has `+` but no `+=`
        askedWork = askedWork + asked.lastFrameWork
        step(quiet)
        // swiftlint:disable:next shorthand_operator - `FrameWork` has `+` but no `+=`
        quietWork = quietWork + quiet.lastFrameWork
    }
    #expect(askedWork == quietWork && askedWork.builds >= 4, "asked \(askedWork) quiet \(quietWork)")
    #expect(asked.scene.glyphs.count == quiet.scene.glyphs.count && !asked.scene.glyphs.isEmpty)
    #expect(MemoryLayout<MUIGlyph>.stride == 88, "a glyph record gained a field: \(MemoryLayout<MUIGlyph>.stride)")
}
