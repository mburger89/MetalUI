import Testing
import MetalUIPlatform
@testable import MetalUI

// SMK port gaps, lane 2 — test 2.1 (rulings `SG-A` item 3, `SG-B` item 3;
// spec `docs/superpowers/specs/2026-10-09-smk-gaps-design.md` §3.4, §5).
// Portable: the drawn bar's standard Edit items carry `.primary` — ⌘ on
// Apple, Ctrl on Linux and Windows. On macOS `.primary == .command`, so the
// separating run is the Linux image's (and Windows CI's). Red before: the file
// does not compile (no `style:`).

/// **2.1** (`SG-B` item 3). The drawn model's Edit items: Undo, Cut, Copy,
/// Paste and Select All on `.primary`, Redo on `[.primary, .shift]`, Delete
/// with no shortcut. Mutation: the standard items' default back to `.command`
/// — reddens in `swift:6.4-noble`.
@MainActor
@Test func theDrawnBarsStandardShortcutsUseThePrimaryModifier() throws {
    let model = MenuBarModel(entries: [], appName: "App", style: .drawn)
    let edit = try #require(model.menus.first { $0.title == "Edit" }, "\(model.menus.map(\.title))")
    let shortcuts = edit.items.filter { $0.standardAction != nil }.map { ($0.title, $0.shortcut) }
    try #require(shortcuts.count == 7, "\(shortcuts.map(\.0))")
    for (title, shortcut) in shortcuts {
        switch title {
        case "Redo": #expect(shortcut?.modifiers == [.primary, .shift], "\(title): \(String(describing: shortcut))")
        case "Delete": #expect(shortcut == nil, "Delete is delivered as its own key, no shortcut shown")
        default: #expect(shortcut?.modifiers == .primary, "\(title): \(String(describing: shortcut))")
        }
    }
    #if !canImport(Darwin)
    #expect(edit.items.first?.shortcut?.modifiers == .control, "Ctrl off Apple")
    #endif
}
