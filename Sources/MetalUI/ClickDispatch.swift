import MetalUICore
import MetalUIPlatform

// SKELETON (lane 2 red-first): the context is declared and never set.
@MainActor
enum ClickDispatch {
    static var modifiers: Modifiers = []
    static var focusRequest: GlobalElementID?
}
