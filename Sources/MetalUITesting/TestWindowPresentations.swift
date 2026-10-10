import MetalUI

// Presentations at the seam (ruling `HT-H` items 1–2; spec §3.2 item 3): the
// values the window handed its platform, the latest not yet answered, and the
// answers a platform sends — queued `InputEvent`s — each followed by one
// frame. A request is answered when the harness sends its result or the
// window dismisses its token (`dismissedPresentations`).

/// The tokens the harness has answered, per kind.
struct AnsweredPresentations {
    var alerts = Set<Int>()
    var fileDialogs = Set<Int>()
    var menus = Set<Int>()
}

extension TestWindow {
    /// The alert the window presented natively that is not yet answered or
    /// dismissed; `nil` when the window draws its alerts
    /// (`presentsAlertsNatively` off — drive the drawn alert through the
    /// tree).
    public var presentedAlert: PlatformAlert? {
        guard platformWindow.options.presentsAlertsNatively, let alert = platformWindow.presentedAlerts.last,
              !answered.alerts.contains(alert.token),
              !platformWindow.dismissedPresentations.contains(alert.token) else { return nil }
        return alert
    }

    /// The file dialog the window presented that is not yet answered or
    /// dismissed; `nil` when `presentsFileDialogs` is off.
    public var presentedFileDialog: PlatformFileDialog? {
        guard platformWindow.options.presentsFileDialogs, let dialog = platformWindow.presentedFileDialogs.last,
              !answered.fileDialogs.contains(dialog.token),
              !platformWindow.dismissedPresentations.contains(dialog.token) else { return nil }
        return dialog
    }

    /// The menu the window presented natively that is not yet answered; `nil`
    /// when the window draws its menus (`presentsMenusNatively` off — drive
    /// the drawn menu through the tree).
    public var presentedMenu: PlatformMenu? {
        guard platformWindow.options.presentsMenusNatively, let menu = platformWindow.presentedMenus.last?.menu,
              !answered.menus.contains(menu.token) else { return nil }
        return menu
    }

    /// The toolbar the window last set natively; `nil` for none, or when the
    /// window draws its toolbar strip (`showsToolbarNatively` off).
    public var toolbar: PlatformToolbar? {
        guard platformWindow.options.showsToolbarNatively else { return nil }
        return platformWindow.toolbars.last ?? nil
    }

    /// The pointer style the window last asked for, or `nil` before any.
    public var pointerStyle: PlatformPointerStyle? { platformWindow.pointerStyles.last }

    /// The window's title as the platform shows it.
    public var title: String { platformWindow.title }

    /// Answers the presented alert with its button titled `title`, then draws.
    /// Throws ``TestHarnessError/nothingPresented(_:)`` with no alert,
    /// ``TestHarnessError/noElement(_:)`` for no such button and
    /// ``TestHarnessError/ambiguous(_:count:)`` for several.
    public func respondToAlert(button title: String) throws {
        guard let alert = presentedAlert else { throw TestHarnessError.nothingPresented("alert") }
        let matches = alert.buttons.indices.filter { alert.buttons[$0].title == title }
        let query = "alert button \"\(title)\""
        guard let index = matches.first else { throw TestHarnessError.noElement(query) }
        guard matches.count == 1 else { throw TestHarnessError.ambiguous(query, count: matches.count) }
        try respondToAlert(buttonAt: index)
    }

    /// Answers the presented alert with its button at `index` (`nil`:
    /// dismissed with no button), then draws. Throws
    /// ``TestHarnessError/nothingPresented(_:)`` with no alert.
    public func respondToAlert(buttonAt index: Int?) throws {
        guard let alert = presentedAlert else { throw TestHarnessError.nothingPresented("alert") }
        answered.alerts.insert(alert.token)
        send(.alertResult(AlertResultEvent(token: alert.token, button: index)))
        tick()
    }

    /// Answers the presented file dialog with `paths` chosen, then draws.
    /// Throws ``TestHarnessError/nothingPresented(_:)`` with no dialog.
    public func respondToFileDialog(choosing paths: [String]) throws {
        try answerFileDialog(.chosen(paths))
    }

    /// Cancels the presented file dialog, then draws. Throws
    /// ``TestHarnessError/nothingPresented(_:)`` with no dialog.
    public func cancelFileDialog() throws {
        try answerFileDialog(.cancelled)
    }

    /// Chooses the item of the presented menu at `path` — titles, through
    /// submenus — then draws. Throws
    /// ``TestHarnessError/nothingPresented(_:)`` with no menu,
    /// ``TestHarnessError/noMenuItem(_:)`` for no such command item and
    /// ``TestHarnessError/disabledMenuItem(_:)`` for a disabled one; a
    /// refused choice answers nothing.
    public func chooseMenuItem(_ path: String...) throws {
        guard let menu = presentedMenu else { throw TestHarnessError.nothingPresented("menu") }
        let item = try MenuPath.command(path, in: menu.items, reportedAs: path)
        answered.menus.insert(menu.token)
        send(.menuAction(MenuActionEvent(menu: menu.token, item: item.id)))
        tick()
    }

    /// Dismisses the presented menu with no choice, then draws. Throws
    /// ``TestHarnessError/nothingPresented(_:)`` with no menu.
    public func dismissMenu() throws {
        guard let menu = presentedMenu else { throw TestHarnessError.nothingPresented("menu") }
        answered.menus.insert(menu.token)
        send(.menuAction(MenuActionEvent(menu: menu.token, item: nil)))
        tick()
    }

    /// Triggers the native toolbar item `id` with `action`, then draws.
    /// Throws ``TestHarnessError/nothingPresented(_:)`` with no such item.
    public func performToolbarItem(_ id: String, action: ToolbarActionEvent.Action = .press) throws {
        guard let toolbar, toolbar.items.contains(where: { $0.id == id }) else {
            throw TestHarnessError.nothingPresented("toolbar item \"\(id)\"")
        }
        send(.toolbarAction(ToolbarActionEvent(item: id, action: action)))
        tick()
    }

    private func answerFileDialog(_ outcome: FileDialogResultEvent.Outcome) throws {
        guard let dialog = presentedFileDialog else { throw TestHarnessError.nothingPresented("file dialog") }
        answered.fileDialogs.insert(dialog.token)
        send(.fileDialogResult(FileDialogResultEvent(token: dialog.token, outcome: outcome)))
        tick()
    }
}

/// Walks menu items by a path of titles (`HT-H` item 2).
enum MenuPath {
    /// The item at `path` and whether it and every submenu above it are
    /// enabled, or `nil` when no item lies along the path. The first item of
    /// a title at each level is taken.
    static func resolve(_ path: [String], in items: [PlatformMenuItem]) -> (item: PlatformMenuItem, isEnabled: Bool)? {
        guard let title = path.first, let item = items.first(where: { $0.title == title && $0.kind != .separator })
        else { return nil }
        let rest = Array(path.dropFirst())
        if rest.isEmpty { return (item, item.isEnabled) }
        guard case .submenu(let children) = item.kind,
              let found = resolve(rest, in: children) else { return nil }
        return (found.item, item.isEnabled && found.isEnabled)
    }

    /// The enabled command item at `path`; `reportedAs` names it in an error.
    static func command(_ path: [String], in items: [PlatformMenuItem],
                        reportedAs reported: [String]) throws -> PlatformMenuItem {
        guard let (item, isEnabled) = resolve(path, in: items), item.kind == .action else {
            throw TestHarnessError.noMenuItem(reported)
        }
        guard isEnabled else { throw TestHarnessError.disabledMenuItem(reported) }
        return item
    }
}
