import MetalUI

// The application menu bar (ruling `HT-H` item 3, TH-a).
// RED STUB (lane 2): no menus, and a perform does nothing.

extension TestApp {
    /// The menu bar's menus, left to right.
    public var menuBar: [PlatformMenu] { [] }

    /// Performs the menu-bar command at `path`.
    public func performMenuBarItem(_ path: String...) throws {}
}
