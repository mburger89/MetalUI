import MetalUI

/// The area right of the sidebar: the editor for the selected note, the
/// statistics, or a prompt when there is no note.
struct DetailArea: Component {
    let model: NotesModel

    var content: some ElementGroup {
        if model.showsStats {
            StatsView(model: model)
        } else if let note = model.selectedNote {
            DetailEditor(model: model, note: note)
        } else {
            Text("Select a note, or press New").foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// What `.task(id:)` re-runs on: the note shown and its text.
struct WordCountKey: Hashable {
    let id: Note.ID
    let body: String
}

/// A title field over a body editor and a footer.
struct DetailEditor: Component {
    let model: NotesModel
    let note: Note
    @FocusState var titleFocused: Bool

    var content: some ElementGroup {
        let id = note.id
        VStack(alignment: .leading, spacing: Pixels(12)) {
            TextField("Title", text: Binding(get: { note.title }, set: { model.setTitle($0, of: id) }))
                .focused($titleFocused)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("title-field")
            TextEditor(text: Binding(get: { note.body }, set: { model.setBody($0, of: id) }))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("body-field")
            DetailFooter(model: model)
        }
        .padding(Edges(all: Pixels(16)))
        // A new note asks for the title's focus by counting up; the lifecycle drain runs
        // this outside every phase, so the write is legal.
        .onChange(of: model.titleFocusRequest) { titleFocused = true }
        // Recomputed when the note shown or its body changes; counted, never timed.
        .task(id: WordCountKey(id: id, body: note.body)) { model.selectedWordCount = note.wordCount }
    }
}

/// The word count and a hint whose Markdown is parsed because it is a literal.
struct DetailFooter: Component {
    let model: NotesModel

    var content: some ElementGroup {
        HStack {
            Text("\(model.selectedWordCount) words").font(size: 12).foregroundColor(.secondary)
            Spacer()
            Text("**Tip:** `#tags` in the body show in the sidebar; drag rows to reorder.")
                .font(size: 12).foregroundColor(.secondary)
        }
    }
}
