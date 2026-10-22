import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14-l (`AM-D`, `AM-J`): MetalCreator's fillet drag, reduced to its ambient: a strip holds a `DragGesture` whose `updating` body sets
// `transaction.disablesAnimations` (SwiftUI's idiom, `GS-`) and whose `onChanged` writes one panel's observed radius. Eight
// `.equatable()` panels below it (`DMNode`, `.observed` arm) hold no animation at all. The gesture's transaction is parked for exactly
// one build (`AN-Y`), so the drag frames' root transaction differs from the settle frames'. Counts only.

/// A panel whose colour animates with its observed radius (`.animation(_:value:)`), so a `withAnimation` write starts an animation inside it.
struct DAAnimatedNode: Component, @MainActor Equatable {
    let index: Int
    let model: DMModel
    var content: some ElementGroup {
        let shown = model.params[index].radius
        VStack(alignment: .leading, spacing: 2) {
            RoundedRectangle(cornerRadius: Pixels(4)).fill(Color(red: 0.2 + shown * 0.1, green: 0.4, blue: 0.7))
                .frame(width: Pixels(90), height: Pixels(10))
            Text("node \(index)").frame(width: Pixels(90), height: Pixels(12))
        }
        .animation(.linear(duration: 0.3), value: shown)
    }
    static func == (l: DAAnimatedNode, r: DAAnimatedNode) -> Bool { l.index == r.index && l.model === r.model }
}

struct DAParent: Component {
    let model: DMModel
    let setsDisablesAnimations: Bool
    var animated = false
    @GestureState var dragging = false
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Color(red: 0.5, green: 0.5, blue: 0.5)).frame(width: Pixels(880), height: Pixels(20))
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($dragging) { _, state, transaction in
                        state = true
                        if setsDisablesAnimations { transaction.disablesAnimations = true }
                    }
                    .onChanged { value in model.params[2].radius = 1 + Double(value.translation.width.value) / 100 })
                .id("strip")
            Text(dragging ? "dragging" : "idle").frame(width: Pixels(100), height: Pixels(12))
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(0..<8), id: \.self) { i in
                    if animated {
                        DAAnimatedNode(index: i, model: model).equatable()
                    } else {
                        DMNode(index: i, value: 1, model: model, arm: .observed).equatable()
                    }
                }
            }
        }
    }
}

@MainActor func dragAmbientWindow(setsDisablesAnimations: Bool = true, retain: Bool = true, animated: Bool = false) throws -> (TestWindow, DMModel) {
    let model = DMModel()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(900, 160), colorScheme: .light, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { DAParent(model: model, setsDisablesAnimations: setsDisablesAnimations, animated: animated) }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, model)
}

/// One drag across the strip, then two settle frames; returns every frame's work (press and moves each draw one frame, the release one).
@MainActor func dragAmbientRun(_ window: TestWindow, steps: Int = 6) throws -> [FrameWork] {
    let strip = try window.frame(ofID: "strip")
    let y = strip.origin.y.value + strip.size.height.value / 2
    window.resetFrameWork()
    window.drag(from: pt(strip.origin.x.value + 20, y), to: pt(strip.origin.x.value + 320, y), steps: steps)
    window.window.setNeedsRedraw(); window.tick()
    window.window.setNeedsRedraw(); window.tick()
    return window.frameWork
}
