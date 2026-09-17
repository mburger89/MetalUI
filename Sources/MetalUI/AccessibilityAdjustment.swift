/// Which way an accessibility client asked an adjustable element to move.
public enum AccessibilityAdjustmentDirection: Equatable, Sendable {
    case increment, decrement
}

/// The action an accessibility increment or decrement request dispatches
/// (ruling AB-I). **An `Action`, so it rides the registry the keyboard already
/// uses** and `Handlers` gains no member.
///
/// Register a handler with `onAction(AccessibilityAdjustment.self) { … }`; the
/// element then advertises `.increment` and `.decrement` to a client. A request
/// runs the element's **own** handler only, never an ancestor's: an ancestor's
/// handler would make one node claim an action on behalf of another.
public struct AccessibilityAdjustment: Action {
    public let direction: AccessibilityAdjustmentDirection
    public init(direction: AccessibilityAdjustmentDirection) { self.direction = direction }
}
