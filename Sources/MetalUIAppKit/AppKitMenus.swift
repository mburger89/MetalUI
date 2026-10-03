#if os(macOS)
import AppKit
import MetalUICore
import MetalUIPlatform

// Menus, popovers and tooltips, lane 2 — AppKit's native menus (rulings `MN-C`,
// `MN-I`, `MN-J`, `MN-K`, `MN-AA`; spec §3.5). Lane 2 red stubs.

/// Where a native context menu's chosen item lands (`MN-C` item 4).
@MainActor
final class AppKitMenuTarget: NSObject {
    /// The chosen item's id, `nil` until one is chosen.
    private(set) var chosen: Int?

    @objc func choose(_ sender: NSMenuItem) { chosen = sender.tag }
}

/// Builds `NSMenu`s from `PlatformMenu`s (`MN-C` item 2) — stub.
@MainActor
enum AppKitMenuBuilder {
    static func menu(from menu: PlatformMenu, target: AppKitMenuTarget) -> NSMenu { NSMenu(title: menu.title) }
}

extension MetalHostView {
    @objc func cut(_ sender: Any?) {}
    @objc func copy(_ sender: Any?) {}
    @objc func paste(_ sender: Any?) {}
    @objc func undo(_ sender: Any?) {}
    @objc func redo(_ sender: Any?) {}
    override func selectAll(_ sender: Any?) {}
    @objc func delete(_ sender: Any?) {}
}

extension MetalHostView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }
}
#endif
