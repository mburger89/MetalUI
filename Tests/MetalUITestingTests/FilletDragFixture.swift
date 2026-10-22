import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14-i lane 2 (`RZ-H`, record 133): MetalCreator's fillet drag, rebuilt as a stand-in. A slider drives one value (`FDModel.value`);
// one panel of six `.equatable()` panels shows it (text, rects, a stroked path, six rows each); a readout `Text` outside every panel
// changes on every frame. Three arms put the slider and the reader where the profile's candidate causes live: the slider in a strip
// outside the panels (the value reaches panel 2 as an input, `==` changes), inside panel 2 (a press under an occurrence), and the
// panel reading the model in its getter (an observed read). No time, only `FrameWork` counts.

/// One panel's own observable value (the per-property granularity `.equatable()` observation wants).
@Observable @MainActor final class FDParam { var value: Double; init(_ v: Double) { value = v } }

@Observable @MainActor final class FDModel {
    /// The `sliderEverywhereObjects` arm's values: one object each, the array never written.
    @ObservationIgnored let params = [FDParam(0.1), FDParam(0.3), FDParam(0.2), FDParam(0.5), FDParam(0.7), FDParam(0.9)]
    var value = 0.2
    /// One value per panel (the `sliderEverywhere` arm: every panel holds a slider, only panel 2's is dragged).
    var values = [0.1, 0.3, 0.2, 0.5, 0.7, 0.9]
}

enum FDArm: String, CaseIterable, Sendable, CustomStringConvertible {
    /// The slider is outside every panel; panel 2 takes the value as an input.
    case sliderOutside
    /// The slider sits inside panel 2.
    case sliderInside
    /// Every panel holds a slider (a `valueTrack` hitbox in each ledger); the one in panel 2 is dragged.
    case sliderEverywhere
    /// As `sliderEverywhere`, one `@Observable` object per panel instead of one array property.
    case sliderEverywhereObjects
    /// The slider is outside; panel 2 reads the model in its own getter (an observed read, no input).
    case observedRead
    var description: String { rawValue }
}

/// A panel: text, a filled rect, a stroked path and six rows. `value` is the input panel 2 takes; the others get a constant.
struct FDPanel: Component, @MainActor Equatable {
    let index: Int
    let value: Double
    var model: FDModel?
    var arm: FDArm = .sliderOutside
    var content: some ElementGroup {
        let shown = arm == .observedRead && index == 2 ? (model?.value ?? 0) : value
        VStack(alignment: .leading, spacing: 3) {
            Text("panel \(index)").frame(width: Pixels(150), height: Pixels(14))
            RoundedRectangle(cornerRadius: Pixels(4)).fill(Color(red: 0.2 + shown * 0.5, green: 0.3 + Double(index) * 0.05, blue: 0.7))
                .frame(width: Pixels(150), height: Pixels(14))
            ZWire().stroke(Color(red: 0.9, green: 0.4, blue: 0.2), lineWidth: Pixels(2)).frame(width: Pixels(150), height: Pixels(20))
            if arm == .sliderInside && index == 2, let model {
                Slider(value: Binding(get: { model.value }, set: { model.value = $0 }), in: 0...1)
                    .frame(width: Pixels(150), height: Pixels(20))
            }
            if arm == .sliderEverywhereObjects, let model {
                Slider(value: Binding(get: { model.params[index].value }, set: { model.params[index].value = $0; if index == 2 { model.value = $0 } }), in: 0...1)
                    .frame(width: Pixels(150), height: Pixels(20))
            }
            if arm == .sliderEverywhere, let model {
                Slider(value: Binding(get: { model.values[index] }, set: { model.values[index] = $0; if index == 2 { model.value = $0 } }), in: 0...1)
                    .frame(width: Pixels(150), height: Pixels(20))
            }
            ForEach(Array(0..<6), id: \.self) { row in
                HStack(spacing: 4) {
                    Text("row \(row)").frame(width: Pixels(60), height: Pixels(12))
                    Box().frame(width: Pixels(Float(20 + row * 8) + Float(shown) * 20), height: Pixels(6)).background(.accent)
                }
            }
        }
    }
    static func == (l: FDPanel, r: FDPanel) -> Bool { l.index == r.index && l.value == r.value && l.arm == r.arm && l.model === r.model }
}

struct FDRoot: Component {
    let model: FDModel
    let arm: FDArm
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if arm == .sliderOutside || arm == .observedRead {
                    Slider(value: Binding(get: { model.value }, set: { model.value = $0 }), in: 0...1)
                        .frame(width: Pixels(200), height: Pixels(24))
                }
                // The readout changes on every frame of the drag, outside every panel.
                Text("fillet \(model.value)").frame(width: Pixels(200), height: Pixels(16))
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(0..<6), id: \.self) { i in
                    FDPanel(index: i, value: arm == .sliderEverywhere ? model.values[i] : (arm == .sliderEverywhereObjects ? model.params[i].value : (i == 2 ? model.value : 0)), model: model, arm: arm).equatable()
                }
            }
        }
    }
}

@MainActor func filletDragWindow(_ arm: FDArm, graft: Bool = true, retain: Bool = true, accessibility: Bool = true) throws -> (TestWindow, FDModel) {
    let model = FDModel()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: accessibility)
    let window = try TestWindow(size: sz(1100, 260), colorScheme: .light, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { FDRoot(model: model, arm: arm) }
    }
    window.window.testingRetainedGraft = graft
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<6 { window.window.setNeedsRedraw(); window.tick() }
    return (window, model)
}

/// The slider's press point (its thumb at the model's value) and the far end of its drag, read from the accessibility tree.
@MainActor func filletDragPoints(_ window: TestWindow, value: Double) throws -> (Point<Pixels>, Point<Pixels>) {
    let sliders = try window.elements(role: .slider)
    // The dragged slider is panel 2's when every panel holds one (the third), else the only one.
    let slider = try #require(sliders.count == 6 ? sliders[2] : sliders.first, "the fixture has a slider")
    let f = slider.frame
    let y = f.origin.y.value + f.size.height.value / 2
    let x0 = f.origin.x.value, w = f.size.width.value
    return (pt(x0 + w * Float(value), y), pt(x0 + w * 0.85, y))
}
