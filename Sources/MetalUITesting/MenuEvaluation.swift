import MetalUI

/// Menu content evaluated outside any window (ruling `HT-H` item 4, TH-a).
/// RED STUB (lane 2): no items.
@MainActor
public struct MenuEvaluation {
    /// The evaluated items.
    public let items: [PlatformMenuItem]

    /// Evaluates `content` once.
    public init(isEnabled: Bool = true, @MenuContentBuilder content: () -> some MenuContent) {
        items = []
    }

    /// The item at `path`.
    public func item(_ path: String...) throws -> PlatformMenuItem {
        throw TestHarnessError.noMenuItem(path)
    }

    /// Runs the command item at `path`.
    public func perform(_ path: String...) throws {}
}
