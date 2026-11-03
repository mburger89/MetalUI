@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// R3-10 item 7 (`AD-K`): a retained subtree whose paint reads a display setting repaints when
// the setting flips. The reader is a custom element that reads `pass.environment` at paint, so
// no getter is re-evaluated and only the replay key (the environment fingerprint) can notice.

private struct ADContrastLeaf: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 40, height: 20)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        let increased = pass.environment.colorSchemeContrast == .increased
        pass.fill(bounds, color: increased ? Hsla(h: 0, s: 1, l: 0.5, a: 1) : Hsla(h: 0.66, s: 1, l: 0.5, a: 1))
    }
}

private struct ADContrastCard: Component, @MainActor Equatable {
    var content: some ElementGroup { ADContrastLeaf() }
    static func == (l: ADContrastCard, r: ADContrastCard) -> Bool { true }
}

/// **20.** A retained (`.equatable()`) occurrence whose paint reads `colorSchemeContrast` replays
/// while the setting holds, misses exactly once when it flips, paints the new colour, and equals
/// a retention-off twin. Mutation: `retainedFingerprint` passes `AccessibilityDisplaySettings()`.
@Test @MainActor func aRetainedPaintReaderOfContrastRepaintsWhenTheSettingFlips() throws {
    let pair = try RPPair(size: sz(200, 80), warm: 4) { _ in VStack(spacing: 4) { ADContrastCard().equatable() } }
    try pair.compare("warm")
    pair.redraw()
    try #require(pair.frames.last?.retainedHits == 1, "replays while the setting holds")

    let increased = AccessibilityDisplaySettings(colorSchemeContrast: .increased)
    pair.on.setAccessibilityDisplaySettings(increased)
    pair.off.setAccessibilityDisplaySettings(increased)
    let f = pair.on.lastFrameWork
    #expect(f.retainedMisses == 1 && f.retainedHits == 0, "the record under the old setting misses: \(eeCounters(f))")
    #expect(pair.on.scene.rects.contains { $0.background.h == 0 && $0.background.s == 1 }, "and the leaf paints the increased colour")
    try pair.compare("the flip")
}
