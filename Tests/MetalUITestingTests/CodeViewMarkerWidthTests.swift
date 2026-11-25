import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// The marker lane's width (`CV-BU`, record 372, Alloy wave 2): `gutterMarkerLane(width:)` takes space advances,
// clamped to 1...16, reserves the lane, keeps markers centred and clips them to it. PLAIN imports; the harness text
// system; counters and scene geometry, never a clock.

private let hue = Color(hue: 0.321, saturation: 1, brightness: 1)
private let owner = CodeDecorationOwner("lsp", priority: 5)

private enum Lane { case none, reserved, width(Int) }

@MainActor private func fixture(_ lane: Lane, marker: String = "!") throws -> (TestWindow, CodeBuffer) {
    let buffer = CodeBuffer((0..<30).map { "row\($0) = x" }.joined(separator: "\n") + "\n")
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([CodeLineDecoration(lines: 3..<4, gutterMarker: CodeGutterMarker(marker, color: hue), tag: 11)],
                                   asOf: buffer.version, owner: owner)
    let base = CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
    let window = try harnessWindow(size: sz(400, 600)) {
        switch lane {
        case .none: base
        case .reserved: base.gutterMarkerLane(true)
        case .width(let n): base.gutterMarkerLane(width: n)
        }
    }
    return (window, buffer)
}

@MainActor private func rowGlyphs(_ w: TestWindow, row: Int) -> [MUIGlyph] {
    let pitch = codePitch(scale: 1)
    return w.scene.glyphs.filter { $0.bounds.origin.y >= Float(row) * pitch - 1 && $0.bounds.origin.y < Float(row + 1) * pitch }
}
@MainActor private func textX(_ w: TestWindow, row: Int) -> Float { rowGlyphs(w, row: row).map(\.bounds.origin.x).max() ?? -1 }
@MainActor private func markerGlyphs(_ w: TestWindow) -> [MUIGlyph] {
    rowGlyphs(w, row: 3).filter { abs($0.color.h - 0.321) < 0.001 }
}
@MainActor private func advance() -> Float {
    let system = harnessTextSystem()
    let font = system.resolveFont(FontDescriptor(family: nil, size: 12, design: .monospaced))
    return Float(system.measure(" ", font: font, wrappingAt: nil).widestLine)
}

/// **1** The text moves once, by the extra advances, and a marker wider than the lane is cut to it. Width 4 puts the
/// text two advances right of the default lane; a nine-column marker in a 2-advance lane has a content mask no wider
/// than the lane. **Mutation:** the lane fixed at two advances (text does not shift); the lane clip removed (mask wider).
@Test @MainActor func markerLaneWidthMovesTextOnceAndClips() throws {
    let (base, _) = try fixture(.reserved)
    let (wide, _) = try fixture(.width(4))
    let delta = textX(wide, row: 3) - textX(base, row: 3)
    #expect(abs(delta - 2 * advance()) <= 2, "text moved by two extra advances: \(delta) vs \(2 * advance())")
    #expect(textX(wide, row: 8) - textX(base, row: 8) == delta, "every row moves alike")

    let (long, _) = try fixture(.width(2), marker: "WWWWWWWWW")
    let laneRight = markerGlyphs(long).map { $0.contentMask.origin.x + $0.contentMask.size.width }
    let laneLeft = markerGlyphs(long).map { $0.contentMask.origin.x }
    let lanePx = (advance() * 2).rounded(.up)
    #expect(markerGlyphs(long).count >= 9)
    let originX = laneLeft.min() ?? -1
    let clipRight = try #require(laneRight.max())
    #expect(clipRight - originX <= lanePx + 1, "the clip is the lane: \(clipRight - originX) vs \(lanePx)")
    // A short marker in a wide lane is centred.
    let (centre, _) = try fixture(.width(6))
    let g = markerGlyphs(centre)
    let lane = (advance() * 6).rounded(.up)
    let lo = try #require(g.map(\.bounds.origin.x).min()), hi = try #require(g.map { $0.bounds.origin.x + $0.bounds.size.width }.max())
    #expect(abs((lo + hi) / 2 - (originX + lane / 2)) <= 3, "centred: \(lo)...\(hi) in lane \(originX)+\(lane)")
}

/// **2** A view that never calls the width has the default lane: geometry equals `gutterMarkerLane(true)` and
/// `width: 2`. **Mutation:** the default raised from 2.
@Test @MainActor func defaultWidthIsByteIdentical() throws {
    let (a, _) = try fixture(.reserved), (b, _) = try fixture(.width(2))
    func boxes(_ b: [MUIBounds]) -> [[Float]] { b.map { [$0.origin.x, $0.origin.y, $0.size.width, $0.size.height] } }
    #expect(boxes(a.scene.glyphs.map(\.bounds)) == boxes(b.scene.glyphs.map(\.bounds)))
    #expect(boxes(a.scene.glyphs.map(\.contentMask)) == boxes(b.scene.glyphs.map(\.contentMask)))
    #expect(boxes(a.scene.rects.map(\.bounds)) == boxes(b.scene.rects.map(\.bounds)))
}

/// **3** The width clamps to 1...16. **Mutation:** the clamp removed (0 gives no lane, 99 a lane of 99).
@Test @MainActor func widthClampsToOneThroughSixteen() throws {
    let (one, _) = try fixture(.width(1)), (zero, _) = try fixture(.width(-5))
    let (sixteen, _) = try fixture(.width(16)), (huge, _) = try fixture(.width(99))
    #expect(textX(zero, row: 3) == textX(one, row: 3), "below 1 is 1")
    #expect(textX(huge, row: 3) == textX(sixteen, row: 3), "above 16 is 16")
    #expect(textX(sixteen, row: 3) > textX(one, row: 3) + 10 * advance())
}

/// **4** A press anywhere in the widened lane on a marker row hits the marker; one past the lane does not.
/// **Mutation:** the hit area kept at two advances.
@Test @MainActor func hitAreaFollowsTheWidth() throws {
    let clicks = Cell<[CodeGutterHit]>([])
    let buffer = CodeBuffer((0..<30).map { "row\($0) = x" }.joined(separator: "\n") + "\n")
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([CodeLineDecoration(lines: 3..<4, gutterMarker: CodeGutterMarker("!"), tag: 11)],
                                   asOf: buffer.version, owner: owner)
    let w = try harnessWindow(size: sz(400, 600)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
            .gutterMarkerLane(width: 16).onGutterBarClick { clicks.value.append($0) }
    }
    let pitch = codePitch(scale: 1)
    let y = 3.5 * pitch
    w.click(at: pt(1, y))
    w.click(at: pt(12 * advance(), y))   // inside the 16-advance lane, far past the default two
    #expect(clicks.value.count == 2 && clicks.value.allSatisfy { $0.source == .gutterMarker && $0.tag == 11 }, "\(clicks.value)")
    w.click(at: pt(16 * advance() + 4, y))   // past the lane: numbers, no hit
    #expect(clicks.value.count == 2)
}

/// **5** The cost literals are the same with and without the width call (a keystroke frame, per frame off Darwin). **Mutation:** a per-width element or retention taint.
@Test @MainActor func costLiteralsAreUnchangedByTheWidth() async throws {
    func steady(_ lane: Lane) async throws -> (Int, Int, Int, Int, Int) {
        let (w, _) = try fixture(lane)
        w.click(at: pt(200, 6))
        for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
        w.resetFrameWork()
        w.typeText("a"); try await w.runUntilIdle()
        let f = totalWork(w)
        return (f.elementRequests, f.retainedHits, f.retainedMisses, f.retainedIneligible, w.frameWork.count)
    }
    let base = try await steady(.reserved)
    #if canImport(Darwin)
    #expect(base == (0, 0, 0, 0, 1), "\(base)")   // measured: the bare view is retained whole
    #endif
    for lane in [Lane.width(2), .width(8), .width(16)] {
        let c = try await steady(lane)
        #if canImport(Darwin)
        #expect(c == base, "\(c) vs \(base)")
        #else
        #expect(c.0 * base.4 == base.0 * c.4 && c.2 * base.4 == base.2 * c.4 && c.3 * base.4 == base.3 * c.4, "\(c) vs \(base)")
        #endif
    }
}
