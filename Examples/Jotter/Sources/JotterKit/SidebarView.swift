import MetalUI

/// The sidebar: a selectable, windowed `List` of notes over a status line.
///
/// `List(_:selection:rowHeight:)` is the uniform-row fast path and must sit in a
/// `ScrollView`; it builds only the rows in view. A click selects (and writes the
/// binding), so the model's `selection` is the one source of truth.
struct SidebarView: Component {
    let model: NotesModel

    var content: some ElementGroup {
        VStack(spacing: 0) {
            SidebarList(model: model)
            Divider()
            StatusBar(model: model)
        }
        .frame(width: Pixels(260))
        .frame(maxHeight: .infinity)
        .background(.sidebarFill)
    }
}

/// The list itself, with the empty state drawn over it when nothing matches.
/// The list stays in the tree either way: a `List` created in a frame builds its
/// rows one frame later (it measures its own origin first), so swapping it in
/// and out would flash an empty sidebar when a search is cleared.
struct SidebarList: Component {
    let model: NotesModel

    var content: some ElementGroup {
        let notes = model.visibleNotes
        ZStack {
            ScrollView {
                List(notes, selection: model.binding(\.selection), rowHeight: Pixels(58)) { note in
                    // The list's row is one element; a legacy `Column` holds the equatable component.
                    Column { NoteRow(note: note, model: model).equatable() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if notes.isEmpty {
                Text(model.query.isEmpty ? "No notes yet" : "No notes match").foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
