import MetalUI
import Observation

/// The tab strip demo (`TBS-`, record 238, human checks group TBS), reached with
/// `METALUI_TABS_DEMO=1 swift run MetalUIDemo`: an editor-like panel with a `TabStrip` of eleven files (a few dirty, a few
/// with an accent colour, one not closable, a long title) over a body that names the selected file. The demo plays the
/// app's part: closing removes the tab and selects a neighbour, a move reorders the array, "Next tab" selects the next one
/// (scrolling it into view at the strip's end) and "Add tab" appends one.
///
/// **The human looks** (group TBS): the native-tab-bar look in light and dark, the hover and dirty-dot swap, the drag marker,
/// the sideways scroll and a vertical wheel that does not scroll the strip.
///
/// Nothing here is in the default demo, so the fourteen offscreen images do not move. The builder is its own function (the
/// Windows 1 MB stack rule), built on a 1 MB thread by `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func tabStripDemoContent() -> some Element {
    tabStripDemoRoot()
}

@MainActor
private func tabStripDemoRoot() -> some Element {
    VStack(alignment: .leading, spacing: Pixels(0)) {
        TabStripDemoStrip()
        TabStripDemoBody()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.background)
}

/// The demo's files and what the app does with the strip's reports.
@Observable @MainActor
public final class TabStripDemoModel {
    /// One open file.
    public struct File: Identifiable {
        /// The tab's id.
        public var id: Int
        /// The file name, the tab's title.
        public var name: String
        /// Whether the file has unsaved edits (the dirty dot).
        public var isDirty = false
        /// Whether the tab can be closed.
        public var isClosable = true
        /// The colour of the session that changed the file, if any.
        public var accent: Color?
    }

    /// The open files, in tab order.
    public var files: [File] = [
        File(id: 0, name: "main.swift", isDirty: true),
        File(id: 1, name: "Package.swift"),
        File(id: 2, name: "README.md", isClosable: false),
        File(id: 3, name: "TabStrip.swift", isDirty: true, accent: .orange),
        File(id: 4, name: "A file with a very long name that truncates at the maximum width.swift", accent: .purple),
        File(id: 5, name: "Window.swift"),
        File(id: 6, name: "Frame.swift", accent: .green),
        File(id: 7, name: "Picker.swift"),
        File(id: 8, name: "Slider.swift", isDirty: true),
        File(id: 9, name: "Toggle.swift"),
        File(id: 10, name: "Theme.swift"),
    ]
    /// The selected file's id.
    public var selected = 0
    var nextID = 11

    /// A model of the eleven demo files.
    public init() {}

    /// Closes `id`, selecting the file that takes its place (the next, else the previous) when it was selected.
    public func close(_ id: Int) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files.remove(at: index)
        if selected == id, !files.isEmpty { selected = files[Swift.min(index, files.count - 1)].id }
    }

    /// Moves the tab at `from` to index `to`.
    public func move(_ from: Int, _ to: Int) {
        guard files.indices.contains(from), to >= 0, to < files.count else { return }
        files.insert(files.remove(at: from), at: to)
    }

    /// Selects the next file, wrapping.
    public func next() {
        guard let index = files.firstIndex(where: { $0.id == selected }) else { return }
        selected = files[(index + 1) % files.count].id
    }

    /// Opens a new file and selects it.
    public func add() {
        files.append(File(id: nextID, name: "Untitled \(nextID).swift", isDirty: true))
        selected = nextID
        nextID += 1
    }
}

/// The model the tab strip demo shares between its strip and its buttons.
@MainActor public let tabStripDemoModel = TabStripDemoModel()

/// The strip over the shared model.
struct TabStripDemoStrip: Component {
    /// The model to show; `nil` reads the shared one when laid out (a main-actor global, never at construction).
    var model: TabStripDemoModel?

    var content: some ElementGroup {
        let model = model ?? tabStripDemoModel
        let tabs = model.files.map {
            TabStripItem(id: $0.id, title: $0.name, icon: Image(systemName: "doc.text"), isDirty: $0.isDirty,
                         isClosable: $0.isClosable, accent: $0.accent)
        }
        return TabStrip(selection: Binding(get: { model.selected }, set: { model.selected = $0 }), tabs: tabs)
            .onCloseTab { model.close($0) }
            .onMoveTab { model.move($0, $1) }
    }
}

/// The body: the selected file's name and the two buttons that drive the strip from outside.
struct TabStripDemoBody: Component {
    /// The model to show; `nil` reads the shared one when laid out (a main-actor global, never at construction).
    var model: TabStripDemoModel?

    var content: some ElementGroup {
        let model = model ?? tabStripDemoModel
        let name = model.files.first { $0.id == model.selected }?.name ?? "No file open"
        return VStack(alignment: .leading, spacing: Pixels(12)) {
            Text(name)
            HStack(spacing: Pixels(8)) {
                Button("Next tab") { model.next() }
                Button("Add tab") { model.add() }
            }
        }
        .padding(Pixels(16))
    }
}
