import MetalUICore
import MetalUIPlatform

// Key and focus scoping, lane A (rulings `KF-D`, `KF-E`, `KF-F`, `KF-U`).

extension StyledElement {
    /// MetalUI-only key region — stub.
    public func hoverKeyRegion(_ isEnabled: Bool = true) -> Self {
        self
    }
}

extension Window {
    /// The chain the keyboard stages that walk one read — stub.
    var keyChain: [GlobalElementID] { focusChain }
}
