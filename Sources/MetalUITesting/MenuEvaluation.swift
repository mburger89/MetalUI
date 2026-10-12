import MetalUI

/// Menu content evaluated outside any window (ruling `HT-H` item 4, TH-a):
/// the items a window would present for the same `@MenuContentBuilder` block
/// — numbered by the window's own numbering — and a way to run one.
///
/// No window means no `StateDispatch`: an action runs directly, so this suits
/// model-driven menus (an `@Observable` model's View ▸ Theme), not a
/// `@State` write. MetalUI-only (`HT-B`).
///
/// ```swift
/// let menu = MenuEvaluation { Button("Save") { model.save() }.keyboardShortcut("s") }
/// #expect(try menu.item("Save").shortcut?.key == "s")
/// try menu.perform("Save")
/// ```
@MainActor
public struct MenuEvaluation {
    /// The evaluated items, in order, ids depth-first from 1.
    public let items: [PlatformMenuItem]
    private let actions: [Int: @MainActor () -> Void]

    /// Evaluates `content` once, as a window does at a menu's open; with
    /// `isEnabled` false every item is disabled, as under `.disabled(true)`.
    public init(isEnabled: Bool = true, @MenuContentBuilder content: () -> some MenuContent) {
        let evaluated = content().testingEvaluateMenu(isEnabled: isEnabled)
        items = evaluated.items
        actions = evaluated.actions
    }

    /// The item at `path` — titles, through submenus. Throws
    /// ``TestHarnessError/noMenuItem(_:)`` for none.
    public func item(_ path: String...) throws -> PlatformMenuItem {
        guard let found = MenuPath.resolve(path, in: items) else { throw TestHarnessError.noMenuItem(path) }
        return found.item
    }

    /// Runs the command item at `path`. Throws
    /// ``TestHarnessError/noMenuItem(_:)`` for none or a non-command item and
    /// ``TestHarnessError/disabledMenuItem(_:)`` for a disabled one.
    public func perform(_ path: String...) throws {
        let item = try MenuPath.command(path, in: items, reportedAs: path)
        guard let action = actions[item.id] else { throw TestHarnessError.noMenuItem(path) }
        action()
    }
}
