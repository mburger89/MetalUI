import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14-j (`DM-`): MetalCreator's `CanvasLayers` shape. One parent `Component` loops eight value-typed `.equatable()` node views
// in a `ForEach`; each draws a rect, a text and a `Button` (a hitbox, so a prepaint ledger exists). A step changes some of the
// nodes' inputs (`.value`), writes an `@Observable` property one node reads (`.observed`), or does the first of those with a
// `TextField` in every node (`.ledgerGain`: the field's first frame is a creating write, `RW-S`). Counts only.

@Observable @MainActor final class DMParam { var radius: Double; init(_ r: Double) { radius = r } }

@Observable @MainActor final class DMModel {
    /// The `.value` arm's inputs: the parent reads them and hands each node its own.
    var values = [Double](repeating: 1, count: 8)
    /// The `.observed` arm's objects: node `i` reads `params[i].radius` in its own getter (one object a node, so the
    /// write is one occurrence's observed change).
    @ObservationIgnored let params = (0..<8).map { _ in DMParam(1) }
    var texts = [String](repeating: "", count: 8)
}

enum DMArm: String, CaseIterable, Sendable, CustomStringConvertible {
    case value, observed, ledgerGain
    /// A node's own width follows its value by a fractional device pixel, so every later node is moved by a delta the translation refuses (a key-only miss with an equal value, `DM-D`).
    case moved
    /// The node holds a nested `.equatable()` inner view that reads the observed radius: the outer's own getter does not run, a descendant's does (`DM-L`: the outer's build window was closed, its prepaint window opens once the descendant ran).
    case nested
    var description: String { rawValue }
}

struct DMNode: Component, @MainActor Equatable {
    let index: Int
    let value: Double
    var model: DMModel?
    var arm: DMArm = .value
    var content: some ElementGroup {
        let shown = arm == .observed ? (model?.params[index].radius ?? 0) : value
        VStack(alignment: .leading, spacing: 2) {
            RoundedRectangle(cornerRadius: Pixels(4)).fill(Color(red: 0.2 + shown * 0.1, green: 0.4, blue: 0.7))
                .frame(width: Pixels(arm == .moved ? 90 + Float(value) * 0.3 : 90), height: Pixels(10))
            Text("node \(index)").frame(width: Pixels(90), height: Pixels(12))
            if arm == .nested, let model { DMInner(index: index, model: model).equatable() }
            Button("go \(index)") {}.frame(width: Pixels(90), height: Pixels(16))
            if arm == .ledgerGain, let model {
                TextField("t", text: Binding(get: { model.texts[index] }, set: { model.texts[index] = $0 }))
                    .frame(width: Pixels(90), height: Pixels(24))
            }
        }
    }
    static func == (l: DMNode, r: DMNode) -> Bool { l.index == r.index && l.value == r.value && l.arm == r.arm && l.model === r.model }
}

struct DMInner: Component, @MainActor Equatable {
    let index: Int
    let model: DMModel
    var content: some ElementGroup {
        Rectangle().fill(Color(red: 0.1 + model.params[index].radius * 0.1, green: 0.5, blue: 0.3)).frame(width: Pixels(90), height: Pixels(6))
    }
    static func == (l: DMInner, r: DMInner) -> Bool { l.index == r.index && l.model === r.model }
}

struct DMParent: Component {
    let model: DMModel
    let arm: DMArm
    var content: some ElementGroup {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(0..<8), id: \.self) { i in
                DMNode(index: i, value: arm == .observed || arm == .nested ? 1 : model.values[i], model: model, arm: arm).equatable()
            }
        }
    }
}

@MainActor func doubleMissWindow(_ arm: DMArm, retain: Bool = true, graft: Bool = true) throws -> (TestWindow, DMModel) {
    let model = DMModel()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(900, 120), colorScheme: .light, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { DMParent(model: model, arm: arm) }
    }
    window.window.testingRetainedGraft = graft
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, model)
}

/// Changes occurrences `changed` of one arm (a value, or the observed radius), then draws the change frame and one settle frame.
/// Returns the two frames' work.
@MainActor func doubleMissStep(_ window: TestWindow, _ model: DMModel, arm: DMArm, changed: [Int], to value: Double) -> (change: FrameWork, settle: FrameWork) {
    window.resetFrameWork()
    for i in changed {
        switch arm {
        case .value, .ledgerGain, .moved: model.values[i] = value
        case .observed, .nested: model.params[i].radius = value
        }
    }
    window.window.setNeedsRedraw(); window.tick()
    window.window.setNeedsRedraw(); window.tick()
    let frames = window.frameWork
    return (frames[0], frames[frames.count - 1])
}
