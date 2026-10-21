import MetalUI

/// The window the app opens at, and the smallest it may be resized to.
public let jotterWindowSize = Size(width: Pixels(900), height: Pixels(600))
public let jotterMinimumSize = Size(width: Pixels(640), height: Pixels(400))

/// The window's one root element, rebuilt every frame: the screen is small
/// `Component`s (sidebar, detail, status bar), each its own type, so no one
/// builder holds the whole tree (a Windows thread has a 1 MB stack).
@MainActor
public func rootView(model: NotesModel) -> some Element {
    VStack(spacing: 0) {
        JotterScreen(model: model)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.surface)
}

/// Sidebar | divider | detail, with the toolbar and the search field.
struct JotterScreen: Component {
    let model: NotesModel

    var content: some ElementGroup {
        HStack(spacing: 0) {
            SidebarView(model: model)
            Divider()
            DetailArea(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Window-wide: the Theme button picks the scheme, nil leaves it to the system.
        .preferredColorScheme(model.scheme)
        .toolbar { jotterToolbar(model) }
        .searchable(text: model.binding(\.query), prompt: "Search notes")
    }
}

/// The toolbar's items, each with the id a test (and the platform) names it by.
@MainActor
@ToolbarContentBuilder
func jotterToolbar(_ model: NotesModel) -> some ToolbarContent {
    ToolbarItem(id: "new", placement: .primaryAction) { Button("New") { model.newNote() } }
    ToolbarItem(id: "delete", placement: .primaryAction) {
        Button("Delete") { if let id = model.selection { model.requestDelete(id) } }
            .disabled(model.selection == nil)
    }
    ToolbarItem(id: "stats", placement: .primaryAction) {
        Button(model.showsStats ? "Notes" : "Stats") { model.showsStats.toggle() }
    }
    ToolbarItem(id: "export", placement: .primaryAction) { Button("Export") { model.exporting = true } }
    ToolbarItem(id: "import", placement: .primaryAction) { Button("Import") { model.importing = true } }
    ToolbarItem(id: "scheme", placement: .primaryAction) {
        Button("Theme") { model.scheme = model.scheme == .dark ? .light : .dark }
    }
}
