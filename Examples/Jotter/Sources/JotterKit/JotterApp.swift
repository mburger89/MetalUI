import MetalUI

/// The menu bar: File items (new, duplicate, delete, export, open) after the
/// standard New group, and a View menu. Every File item has a shortcut on
/// `EventModifiers.primary`, which is ⌘ on macOS and Ctrl on Linux and Windows.
///
/// On macOS these join AppKit's main menu; on SDL, where there is no native bar,
/// every window draws it (the platform answers `false` to `setMenuBar`).
/// The window's shortcut pipeline is the one path for a key either way: a
/// `Button`'s shortcut first, then these commands.
@MainActor
public func installJotterCommands(on app: App, model: NotesModel) {
    app.commands {
        CommandGroup(after: .newItem) {
            Button("New Note") { model.newNote() }
                .keyboardShortcut("n")
            Button("Duplicate Note") { if let id = model.selection { model.duplicate(id) } }
                .keyboardShortcut("d")
                .disabled(model.selection == nil)
            Button("Delete Note") { if let id = model.selection { model.requestDelete(id) } }
                .keyboardShortcut(.delete)
                .disabled(model.selection == nil)
            Divider()
            Button("Export...") { model.exporting = true }
                .keyboardShortcut("e")
            Button("Open...") { model.importing = true }
                .keyboardShortcut("o")
        }
        CommandMenu("View") {
            // A `Toggle` takes no `.keyboardShortcut` in MetalUI (a finding, record 136): these two are menu-only.
            Toggle("Statistics", isOn: model.binding(\.showsStats))
            Toggle("Dark Appearance", isOn: Binding(get: { model.scheme == .dark },
                                                    set: { model.scheme = $0 ? .dark : .light }))
        }
    }
}
