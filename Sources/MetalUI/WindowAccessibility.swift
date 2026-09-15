import MetalUICore
import MetalUIPlatform

@MainActor
final class WindowAccessibility {
    private(set) var isActive = false
    private(set) var lastPublished = AccessibilityTree.empty
    private(set) var buildCount = 0
    private(set) var publishCount = 0
    private(set) var lastEmissionCount = 0

    func activate() -> Bool { false } // SKELETON (lane 1, red run)

    func frameDidRender(emissionCount: Int,
                        _ tree: @autoclosure () -> AccessibilityTree,
                        to platformWindow: any PlatformWindow) {
        // SKELETON (lane 1, red run)
    }
}

extension Window {
    func handleAccessibilityRequest(_ request: AccessibilityRequest) -> Bool {
        false // SKELETON (lane 1, red run)
    }
}
