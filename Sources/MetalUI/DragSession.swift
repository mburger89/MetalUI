import MetalUICore
import MetalUIPlatform

// RED-FIRST STUB (lane 1): the session's shape, never opened.

/// An in-window drag (ruling `DN-H`).
struct DragSession {
    let sourceID: GlobalElementID
    let representations: [DragRepresentation]
    let pressPoint: Point<Pixels>
    var pointer: Point<Pixels>
    var offeredExternally = false
}

extension Window {
    /// The open in-window drag, or `nil`.
    var dragSession: DragSession? { nil }
}
