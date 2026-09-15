import MetalUICore

// Lane 3's public accessibility modifiers — RED SKELETON. Each compiles and
// does nothing, so lane 3's tests build and fail on behaviour; the
// implementation commit replaces every body.

extension StyledElement {
    public func accessibilityLabel(_ label: String) -> Self { self }

    public func accessibilityValue(_ value: String) -> Self { self }

    public func accessibilityAdjustableAction(
        _ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) -> Self { self }
}
