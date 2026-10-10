import MetalUI

// Presentations at the seam (ruling `HT-H` items 1–2; spec §3.2 item 3).
// RED STUB (lane 2): nothing is presented and every answer does nothing.

/// The tokens the harness has answered, per kind.
struct AnsweredPresentations {
    var alerts = Set<Int>()
    var fileDialogs = Set<Int>()
    var menus = Set<Int>()
}

extension TestWindow {
    /// The alert the window presented natively that is not yet answered.
    public var presentedAlert: PlatformAlert? { nil }
    /// The file dialog the window presented that is not yet answered.
    public var presentedFileDialog: PlatformFileDialog? { nil }
    /// The menu the window presented natively that is not yet answered.
    public var presentedMenu: PlatformMenu? { nil }
    /// The toolbar the window last set natively.
    public var toolbar: PlatformToolbar? { nil }
    /// The pointer style the window last asked for.
    public var pointerStyle: PlatformPointerStyle? { nil }
    /// The window's title.
    public var title: String { "" }
    /// Answers the presented alert with its button titled `title`.
    public func respondToAlert(button title: String) throws {}
    /// Answers the presented alert with its button at `index`.
    public func respondToAlert(buttonAt index: Int?) throws {}
    /// Answers the presented file dialog with `paths` chosen.
    public func respondToFileDialog(choosing paths: [String]) throws {}
    /// Cancels the presented file dialog.
    public func cancelFileDialog() throws {}
    /// Chooses the item of the presented menu at `path`.
    public func chooseMenuItem(_ path: String...) throws {}
    /// Dismisses the presented menu with no choice.
    public func dismissMenu() throws {}
    /// Triggers the native toolbar item `id` with `action`.
    public func performToolbarItem(_ id: String, action: ToolbarActionEvent.Action = .press) throws {}
}
