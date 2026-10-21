import Foundation
import MetalUI

/// One sidebar row: title, the first line of the body, and the note's tags.
///
/// **`.equatable()`** (used where the row is placed): MetalUI skips this
/// `content` getter while the row's `==` holds, so editing one note re-evaluates
/// one row and not every row. `==` is the decision: it must compare everything
/// the body reads - the note, and the model by identity, which its menu's actions use.
struct NoteRow: Component, Equatable {
    let note: Note
    let model: NotesModel

    nonisolated static func == (lhs: NoteRow, rhs: NoteRow) -> Bool { lhs.note == rhs.note && lhs.model === rhs.model }

    var content: some ElementGroup {
        let id = note.id
        VStack(alignment: .leading, spacing: Pixels(2)) {
            Text(note.title).font(size: 14).accessibilityIdentifier("note-\(id.uuidString)")
            Text(note.snippet()).font(size: 12).foregroundColor(.secondary)
            Text(note.tags.map { "#\($0)" }.joined(separator: " ")).font(size: 11).foregroundColor(.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(inset(10, 4))
        // Reorder: the row's payload is its id; dropping another row's id on it moves that row here.
        .draggable(id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            model.move(dragged, onto: id)
            return true
        }
        .contextMenu {
            Button("Duplicate") { model.duplicate(id) }
            Divider()
            Button("Delete") { model.requestDelete(id) }
        }
    }
}
