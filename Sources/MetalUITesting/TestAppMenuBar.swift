import MetalUI

// The application menu bar (ruling `HT-H` item 3, TH-a): read from the
// `PlatformMenuBar` the app installed, evaluated afresh at each read as
// AppKit evaluates it at each open, and a command performed through it.

extension TestApp {
    /// The menu bar's menus, left to right — `PlatformMenuBar.content()`
    /// evaluated now, so a toggle's state and a `.disabled` item are live.
    /// Empty before the app installs a bar.
    public var menuBar: [PlatformMenu] { platform.menuBar?.content() ?? [] }

    /// Performs the menu-bar command at `path` (a menu title, then item
    /// titles through submenus) from a fresh evaluation, then draws a frame in
    /// every window. Throws ``TestHarnessError/noMenuItem(_:)`` for no such
    /// command — a standard item (Quit, Copy …) is the platform's own command
    /// and has none here (ruling `HT-T`) — and
    /// ``TestHarnessError/disabledMenuItem(_:)`` for a disabled one.
    public func performMenuBarItem(_ path: String...) throws {
        // `perform` runs ids of the last `content()`, so evaluate once, here.
        guard let bar = platform.menuBar, let title = path.first,
              let menu = bar.content().first(where: { $0.title == title }) else {
            throw TestHarnessError.noMenuItem(path)
        }
        let item = try MenuPath.command(Array(path.dropFirst()), in: menu.items, reportedAs: path)
        guard item.standardAction == nil else { throw TestHarnessError.noMenuItem(path) }
        bar.perform(item.id)
        for window in windows { window.tick() }
    }
}
