import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// R3-9 (`SS-D`): a tint reaches a retained decision through exactly one value, `EnvironmentFingerprint.tint`. Eight `.equatable()`
// panels paint `fill(.tint)`, `Color.accentColor` and a `ShapeStyle` composition that reads the colour scheme; a tint change must
// miss every panel and paint the new tint, an equal tint rebuilt every frame must hit. Colours are read from the scene's rects, the
// whole frame is compared to a retention-off twin. Counts and values, never time.

@Observable @MainActor final class SSTintBox { var tint: Color? = Color(red: 0.8, green: 0.2, blue: 0.6) }

struct SSSchemeStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.colorScheme == .dark ? Color(red: 0.9, green: 0.9, blue: 0.1) : Color(red: 0.1, green: 0.1, blue: 0.9)
    }
}

struct SSNode: Component, @MainActor Equatable {
    let index: Int
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(.tint).frame(width: Pixels(60), height: Pixels(8))
            Rectangle().fill(Color.accentColor).frame(width: Pixels(60), height: Pixels(8))
            Rectangle().fill(SSSchemeStyle()).frame(width: Pixels(60), height: Pixels(8))
        }
    }
    // The tint is deliberately not part of the value: it enters from outside the occurrence.
    static func == (l: SSNode, r: SSNode) -> Bool { l.index == r.index }
}

struct SSParent: Component {
    let box: SSTintBox
    var content: some ElementGroup {
        let tint = box.tint
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(0..<8), id: \.self) { i in
                SSNode(index: i).equatable().tint(tint)
            }
        }
    }
}

@MainActor func ssWindow(retain: Bool = true) throws -> (TestWindow, SSTintBox) {
    let box = SSTintBox()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(900, 160), colorScheme: .light, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { SSParent(box: box) }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, box)
}

@MainActor func ssCount(_ window: TestWindow, _ color: Color) -> Int {
    let c = color.resolved(theme: .light, scheme: .light)
    return window.scene.rects.filter { rtSameHsla($0.background, c) }.count
}

private func rtSameHsla(_ a: MUIHsla, _ b: Hsla) -> Bool {
    abs(a.h - b.h) < 1e-4 && abs(a.s - b.s) < 1e-4 && abs(a.l - b.l) < 1e-4 && abs(a.a - b.a) < 1e-4
}

@Suite(.serialized) @MainActor
struct RetainedShapeStyleTests {
    private let old = Color(red: 0.8, green: 0.2, blue: 0.6)
    private let new = Color(red: 0.1, green: 0.7, blue: 0.3)

    /// A tint change misses every panel naming it and repaints in the new tint; the frame equals a retention-off twin and
    /// settles to all hits. **Mutation:** `retainedFingerprint` without `tint` (reddens: no miss, stale colour).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func aTintChangeMissesEveryPanelAndRepaints() throws {
        let (on, onBox) = try ssWindow()
        let (off, offBox) = try ssWindow(retain: false)
        try #require(ssCount(on, old) >= 16, "set up: tint and accentColor panels paint the old tint (\(ssCount(on, old)))")
        var missed = 0
        let lines = collectTrace {
            on.resetFrameWork()
            onBox.tint = new
            on.window.setNeedsRedraw(); on.tick()
            missed = on.frameWork.reduce(0) { $0 + $1.retainedMisses }
        }
        offBox.tint = new
        off.window.setNeedsRedraw(); off.tick()
        let reasons = Set(lines.compactMap(traceReasons).flatMap { $0 })
        #expect(reasons.contains { $0.contains("environment.tint") }, "\(reasons.sorted())")
        #expect(missed >= 8, "every panel misses: \(missed)")
        #expect(ssCount(on, new) >= 16, "the new tint is painted: \(ssCount(on, new))")
        #expect(ssCount(on, old) == 0, "no stale tint: \(ssCount(on, old))")
        #expect(try RPSnapshot(on).differences(from: RPSnapshot(off)).isEmpty)
        var settled = ""
        for _ in 0..<3 {
            on.resetFrameWork()
            on.window.setNeedsRedraw(); on.tick()
            settled = on.frameWork.map { "h\($0.retainedHits) m\($0.retainedMisses)" }.joined(separator: ",")
        }
        #expect(settled == "h8 m0", Comment(rawValue: settled))
    }

    /// An equal tint rebuilt every frame is no change: all eight panels hit. **Mutation:** a fingerprint comparing the tint
    /// by identity (reddens: misses).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func anEqualTintRebuiltIsAllHits() throws {
        let (on, box) = try ssWindow()
        on.resetFrameWork()
        box.tint = Color(red: 0.8, green: 0.2, blue: 0.6)
        on.window.setNeedsRedraw(); on.tick()
        let frame = try #require(on.frameWork.last)
        #expect(frame.retainedMisses == 0 && frame.retainedHits == 8, "h\(frame.retainedHits) m\(frame.retainedMisses)")
    }

    /// Removing the tint (`nil`) is a change too, and the panels fall back to the theme's accent. **Mutation:** as above.
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func removingTheTintMissesAndFallsBackToTheAccent() throws {
        let (on, box) = try ssWindow()
        on.resetFrameWork()
        box.tint = nil
        on.window.setNeedsRedraw(); on.tick()
        #expect(on.frameWork.reduce(0) { $0 + $1.retainedMisses } >= 8)
        #expect(ssCount(on, Color(.accent)) >= 16, "the theme accent: \(ssCount(on, Color(.accent)))")
        #expect(ssCount(on, old) == 0)
    }
}
