import MetalUICore
import MetalUIPlatform

@MainActor
enum AccessibilityTreeBuilder {
    static func build(emissions: [AXEmission],
                      focused: GlobalElementID?,
                      hitboxes: [Hitbox],
                      focusRegistry: FocusRegistry) -> AccessibilityTree {
        .empty // SKELETON (lane 1, red run)
    }
}
