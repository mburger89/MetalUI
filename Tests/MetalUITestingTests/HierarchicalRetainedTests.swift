import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// R4-4 PR A (`HY-B`): an `.equatable()` child holding a level reads its parent through the environment, never
// through its own value, so a parent that changes from red to blue must repaint it (the retained key sees the
// changed `foregroundStyle`, whose `over` is part of `Color`'s `Hashable`). Colours are read from the scene's rects
// (a retention-off twin is compared whole). Mutation 9: `Color.Provider`'s equality ignoring `over`.

@Observable @MainActor final class HYParentBox { var color: Color = .red }

struct HYChip: Component, @MainActor Equatable {
    let tag: Int
    var content: some ElementGroup {
        Circle().fill(.secondary).frame(width: Pixels(40), height: Pixels(40))
    }
    static func == (l: HYChip, r: HYChip) -> Bool { l.tag == r.tag }
}

struct HYParent: Component {
    let box: HYParentBox
    var content: some ElementGroup {
        let parent = box.color
        VStack(spacing: 4) {
            HYChip(tag: 1).equatable()
            Circle().fill(.secondary).frame(width: Pixels(40), height: Pixels(40))
        }.foregroundStyle(parent)
    }
}

@MainActor private func hyWindow(retain: Bool) throws -> (TestWindow, HYParentBox) {
    let box = HYParentBox()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(120, 120), colorScheme: .light, scaleFactor: 2, options: options,
                                textSystem: harnessTextSystem) { VStack(spacing: 0) { HYParent(box: box) } }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, box)
}

/// Rects of the first circle (the `.equatable()` chip) and the second (the plain one), as resolved colours.
@MainActor private func hyColours(_ w: TestWindow) -> [Rgba] {
    w.scene.rects.map { Hsla(h: $0.background.h, s: $0.background.s, l: $0.background.l, a: $0.background.a).toRgba() }
        .filter { $0.a > 0 }
}

private func hyNear(_ c: Rgba, _ rgb: (Float, Float, Float), _ a: Float) -> Bool {
    abs(c.r - rgb.0) < 2 / 255 && abs(c.g - rgb.1) < 2 / 255 && abs(c.b - rgb.2) < 2 / 255 && abs(c.a - a) < 1.5 / 255
}

/// **HY-B** — red then blue: both circles read red at .5, then both blue at .5, with retention on and off, and the
/// retained frame equals the retention-off twin's. Mutation 9 (equality ignoring `over`): the chip stays red.
@Test @MainActor func anEquatableChildUnderAChangedParentRepaintsItsLevel() throws {
    let redLight: (Float, Float, Float) = (1, 56 / 255, 60 / 255)
    let blue: (Float, Float, Float) = (0, 0x88 / 255, 1)
    var seen: [[Rgba]] = []
    for retain in [true, false] {
        let (w, box) = try hyWindow(retain: retain)
        let first = hyColours(w)
        #expect(first.filter { hyNear($0, redLight, 0.5) }.count == 2, "retain \(retain), red: \(first)")
        box.color = .blue
        w.window.setNeedsRedraw(); w.tick()
        w.window.setNeedsRedraw(); w.tick()
        let second = hyColours(w)
        #expect(second.filter { hyNear($0, blue, 0.5) }.count == 2, "retain \(retain), blue: \(second)")
        #expect(!second.contains { hyNear($0, redLight, 0.5) }, "retain \(retain): a stale red level: \(second)")
        seen.append(second)
    }
    #expect(seen[0].count == seen[1].count && zip(seen[0], seen[1]).allSatisfy { abs($0.a - $1.a) < 1e-4 },
            "retained frame differs from the retention-off twin: \(seen)")
}
