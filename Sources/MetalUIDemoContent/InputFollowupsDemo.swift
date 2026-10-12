import MetalUI
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import Observation

// The input follow-ups' demo section (rulings `IF-D`, `IF-K` 2): a probe pad
// under the canvas demo (`METALUI_CANVAS_DEMO=1`) that reads out what the
// follow-ups deliver — the modifiers held (a still pointer included), the last
// tap's modifiers, the last drag's click count, and the last cancel or scroll
// phase. It paints nothing before input, so the default images are unmoved.
// Human checks IF1–IF7 (`docs/verification/human-checks.md`).

/// What the pad reports. Written only from input (gesture, wheel and
/// modifier-keys callbacks).
@MainActor
@Observable
final class InputFollowupsModel {
    var held = "none"
    var tap = "none"
    var drag = "none"
    var scroll = "none"
    var cancelled = 0
}

@MainActor
let inputFollowupsModel = InputFollowupsModel()

/// The pad and its readout: its own function (the 1 MB stack, `IF-K` 2).
@MainActor
func inputFollowupsPad() -> some Element {
    let model = inputFollowupsModel
    return Column(gap: Pixels(4)) {
        Text("held \(model.held) · tap \(model.tap) · drag \(model.drag) · scroll \(model.scroll) · cancelled \(model.cancelled)")
            .font(size: 12)
        Box()
            .frame(width: Pixels(260), height: Pixels(40))
            .background(.surfaceSecondary)
            .gesture(SpatialTapGesture().onEnded {
                inputFollowupsModel.tap = canvasDemoDescribe($0.modifiers)
            })
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { inputFollowupsModel.drag = "×\($0.clickCount)" }
                .onEnded { inputFollowupsModel.drag = "×\($0.clickCount) ended" }
                .onCancelled {
                    inputFollowupsModel.cancelled += 1
                    inputFollowupsModel.drag = "cancelled"
                })
            .onScrollWheel { event in
                inputFollowupsModel.scroll = "\(event.phase)/\(event.momentumPhase)"
                return false
            }
            .onModifierKeysChanged { _, new in inputFollowupsModel.held = canvasDemoDescribe(new) }
    }
    .alignItems(.flexStart)
}
