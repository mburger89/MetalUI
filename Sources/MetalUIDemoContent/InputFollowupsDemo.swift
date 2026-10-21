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
        gestureStateChips()
    }
    .alignItems(.flexStart)
}

// `@GestureState` (item G1, `GS-M`): a chip that follows the pointer and glides home, and one that grows while
// pressed. Written only by the gestures; nothing paints before input. Human checks GS1, GS2.

/// The two chips: their own function (the 1 MB stack).
@MainActor
func gestureStateChips() -> some Element {
    Row(gap: Pixels(12)) {
        GestureStateDragChip()
        GestureStateHoldChip()
    }
}

/// Follows a drag, then eases home over 0.25 s (`resetTransaction`).
struct GestureStateDragChip: Component {
    @GestureState(wrappedValue: Size(width: Pixels(0), height: Pixels(0)),
                  resetTransaction: Transaction(animation: .easeOut(duration: 0.25))) var drag: Size<Pixels>

    var content: some ElementGroup {
        Box().frame(width: Pixels(40), height: Pixels(24)).background(.accent)
            .offset(drag)
            .gesture(DragGesture(minimumDistance: 0).updating($drag) { value, state, _ in state = value.translation })
    }
}

/// Wider while pressed and held; the pressed look turns off at the maturity and at the release.
struct GestureStateHoldChip: Component {
    @GestureState var held = false

    var content: some ElementGroup {
        Box().frame(width: Pixels(held ? 56 : 40), height: Pixels(24)).background(.surfaceSecondary)
            .gesture(LongPressGesture(minimumDuration: 0.5).updating($held) { value, state, _ in state = value })
    }
}
