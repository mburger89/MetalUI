import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14-m (`EO-`): MetalCreator's glass panels, reduced: N `.equatable()` panels under a drag, each panel's content wrapped in
// `.environment(\.colorScheme, <the inherited value>)`. Counts only.

enum EOArm: Sendable { case none, insideScheme, outsideScheme, insideMaterial }

struct EONode: Component, @MainActor Equatable {
    let index: Int
    let model: DMModel
    let arm: EOArm
    let scheme: ColorScheme
    var content: some ElementGroup {
        let shown = model.params[index].radius
        switch arm {
        case .insideScheme, .insideMaterial:
            body(shown).environment(\.colorScheme, scheme)
        default:
            body(shown)
        }
    }
    @ElementBuilder func body(_ shown: Double) -> some ElementGroup {
        VStack(alignment: .leading, spacing: 2) {
            RoundedRectangle(cornerRadius: Pixels(4)).fill(Color(red: 0.2 + shown * 0.1, green: 0.4, blue: 0.7))
                .frame(width: Pixels(90), height: Pixels(10))
            Text("node \(index)").frame(width: Pixels(90), height: Pixels(12))
        }
    }
    static func == (l: EONode, r: EONode) -> Bool { l.index == r.index && l.model === r.model && l.arm == r.arm && l.scheme == r.scheme }
}

struct EOParent: Component {
    let model: DMModel
    let arm: EOArm
    let scheme: ColorScheme
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Color(red: 0.5, green: 0.5, blue: 0.5)).frame(width: Pixels(880), height: Pixels(20))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in model.params[2].radius = 1 + Double(value.translation.width.value) / 100 })
                .id("strip")
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(0..<8), id: \.self) { i in
                    if arm == .outsideScheme {
                        EONode(index: i, model: model, arm: arm, scheme: scheme).equatable().environment(\.colorScheme, scheme)
                    } else {
                        EONode(index: i, model: model, arm: arm, scheme: scheme).equatable()
                    }
                }
            }
        }
    }
}

@MainActor func envOverrideWindow(_ arm: EOArm, scheme: ColorScheme = .light, retain: Bool = true) throws -> (TestWindow, DMModel) {
    let model = DMModel()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(900, 160), colorScheme: .light, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { EOParent(model: model, arm: arm, scheme: scheme) }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, model)
}

@Suite(.serialized) @MainActor
struct EnvOverrideTests {
    @Test(arguments: [EOArm.none, .insideScheme, .outsideScheme], [ColorScheme.light, .dark]) func anEqualOverrideDoesNotMissAnOccurrence(arm: EOArm, scheme: ColorScheme) throws {
        let (window, _) = try envOverrideWindow(arm, scheme: scheme)
        var frames: [FrameWork] = []
        let lines = collectTrace {
            let strip = try! window.frame(ofID: "strip")
            let y = strip.origin.y.value + strip.size.height.value / 2
            window.resetFrameWork()
            window.drag(from: pt(strip.origin.x.value + 20, y), to: pt(strip.origin.x.value + 320, y), steps: 6)
            frames = window.frameWork
        }
        let reasons = Set(lines.compactMap(traceReasons).flatMap { $0 })
        // EO-A: an override equal to its previous frame's value is not a change: the drag writes one panel's observed radius, so each
        // drag frame misses that panel alone (reason `serial`) and never on an environment field.
        #expect(!reasons.contains { $0.contains("environment") }, "\(arm) \(scheme): \(reasons.sorted())")
        let drag = frames.dropLast()
        #expect(!drag.isEmpty && drag.allSatisfy { $0.retainedMisses == 1 && $0.retainedHits == 7 },
                "\(arm) \(scheme): \(frames.map { "h\($0.retainedHits) m\($0.retainedMisses)" })")
    }
}
