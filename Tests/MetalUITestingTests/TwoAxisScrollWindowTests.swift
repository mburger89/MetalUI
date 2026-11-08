import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// `ScrollView([.horizontal, .vertical])` through a real `Window` over the harness (Alloy gap G5, rulings `XS-D`, `XS-B`; probe
// `docs/probes/swiftui-two-axis-scroll.swift` arm `R1`). Counts and frames, never time.

private func direction(_ rtl: Bool) -> LayoutDirection { rtl ? .rightToLeft : .leftToRight }

/// A 100 x 40 window over a two-axis scroller: 300 x 100 of content (a 10 x 10 first leaf and a 290 x 100 filler), so 200 of
/// travel on x and 60 on y.
@MainActor private func twoAxis(rtl: Bool) throws -> TestWindow {
    try harnessWindow(size: Size(width: Pixels(100), height: Pixels(40))) {
        ProposalScrollView([.horizontal, .vertical]) {
            HStack(spacing: Pixels(0)) {
                Color.red.frame(width: Pixels(10), height: Pixels(10)).id("first")
                Color.blue.frame(width: Pixels(290), height: Pixels(100))
            }
        }
        .frame(width: Pixels(100), height: Pixels(40), alignment: .topLeading)
        .environment(\.layoutDirection, direction(rtl))
    }
}

@MainActor private func first(_ window: TestWindow) throws -> (x: Float, y: Float) {
    let found = window.scene.rects.filter { $0.bounds.size.width == 10 && $0.bounds.size.height == 10 }
    let rect = try #require(found.first)
    return (rect.bounds.origin.x, rect.bounds.origin.y)
}

/// **X6** (`LD-E`, `XS-D`, probe `R1`). Right-to-left: the two-axis scroller opens at the content's right edge (the first leaf at
/// 90, left-to-right 0), the wheel's sign is mirrored on x only (`dx +50` scrolls forward to 140, `dx -50` is clamped at 90), and
/// the vertical axis is untouched by the direction (`dy -20` moves the leaf 20 up either way). Left-to-right is the separating
/// arm. **Mutation:** `ScrollChrome.resolveLayoutDirection` leaving `crossMirrored` false: the content opens at 0 and translates
/// the wrong way, reddening every right-to-left row.
@Test @MainActor func aRightToLeftTwoAxisScrollerMirrorsItsHorizontalAxisOnly() throws {
    func after(rtl: Bool, dx: Float, dy: Float) throws -> (x: Float, y: Float) {
        let window = try twoAxis(rtl: rtl)
        if dx != 0 { window.scroll(at: Point(x: Pixels(50), y: Pixels(5)), byDeltaX: dx, deltaY: 0) }
        if dy != 0 { window.scroll(at: Point(x: Pixels(50), y: Pixels(5)), byDeltaX: 0, deltaY: dy) }
        for _ in 0..<3 { window.tick() }
        return try first(window)
    }
    #expect(try first(try twoAxis(rtl: false)).x == 0)
    #expect(try first(try twoAxis(rtl: true)).x == 90)
    #expect(try after(rtl: false, dx: -50, dy: 0).x == -50)
    #expect(try after(rtl: false, dx: 50, dy: 0).x == 0)
    #expect(try after(rtl: true, dx: 50, dy: 0).x == 140)
    #expect(try after(rtl: true, dx: -50, dy: 0).x == 90)
    let at = try after(rtl: false, dx: 0, dy: 0).y, atRTL = try after(rtl: true, dx: 0, dy: 0).y
    #expect(try after(rtl: false, dx: 0, dy: -20).y == at - 20)
    #expect(try after(rtl: true, dx: 0, dy: -20).y == atRTL - 20)
}
