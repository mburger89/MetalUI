import Foundation
import MetalUI
import Observation

/// The app's state, one plain `@Observable` class (no `ObservableObject`, no
/// publishers). Views read it while they build and MetalUI tracks the reads;
/// a write from input redraws only what read it.
///
/// It is created once, in `main.swift`, and passed to `rootView(model:)` - never
/// defaulted in a view's `@State`, which is re-seeded on every build until it is
/// written (divergence 125).
@MainActor
@Observable
public final class NotesModel {
    /// Every note, in the order the sidebar shows them.
    public var notes: [Note]
    /// The selected note's id.
    public var selection: Note.ID?
    /// The search field's text.
    public var query = ""
    /// Whether the statistics panel replaces the detail.
    public var showsStats = false
    /// The scheme the user picked, `nil` for the system's.
    public var scheme: ColorScheme?

    /// Whether the delete confirmation is showing, and for which note.
    public var confirmingDelete = false
    public private(set) var pendingDelete: Note.ID?
    /// Whether the save and open panels are showing.
    public var exporting = false
    public var importing = false
    /// Whether the load-error alert is showing, and what it says.
    public var showsLoadError = false
    public private(set) var loadError = ""
    /// The line under the sidebar: what the last save or load did.
    public private(set) var status = ""
    /// Counts up each time the title field should take focus (a new note).
    public private(set) var titleFocusRequest = 0
    /// The number of words in the selected note, recomputed by a `.task(id:)`.
    public var selectedWordCount = 0

    /// The day a new note is stamped with; injected so a test is deterministic.
    @ObservationIgnored private let today: () -> Int

    public init(notes: [Note] = [], today: @escaping () -> Int = NotesModel.systemToday) {
        self.notes = notes
        self.today = today
    }

    /// Days since 1970-01-01, UTC.
    public nonisolated static func systemToday() -> Int { Int(Date().timeIntervalSince1970 / 86_400) }

    /// The notes a first launch shows.
    public static func seeded(today: @escaping () -> Int = NotesModel.systemToday) -> NotesModel {
        let day = today()
        return NotesModel(notes: [
            Note(title: "Welcome to Jotter", body: "A small notes app written with MetalUI. #welcome\nSelect a note, edit it, search, drag rows to reorder.", day: day),
            Note(title: "Shopping", body: "Oat milk, coffee, lemons. #errands", day: day - 1),
            Note(title: "Ideas", body: "A chart of words per note. A dark mode. Export to JSON. #ideas #app", day: day - 1),
            Note(title: "Reading list", body: "The Swift book. A paper on exact-area coverage. #reading", day: day - 3),
        ], today: today).selectingFirst()
    }

    private func selectingFirst() -> NotesModel {
        selection = notes.first?.id
        return self
    }

    // MARK: Reading

    /// The notes the sidebar lists: those matching the search, in order.
    public var visibleNotes: [Note] { notes.filter { $0.matches(query) } }

    /// The selected note, if it still exists.
    public var selectedNote: Note? { selection.flatMap { id in notes.first { $0.id == id } } }

    /// The index of `id` in `notes`.
    public func index(of id: Note.ID) -> Int? { notes.firstIndex { $0.id == id } }

    // MARK: Editing

    /// Adds an empty note at the top, selects it and asks for the title field's focus.
    @discardableResult
    public func newNote() -> Note.ID {
        let note = Note(title: "Untitled", body: "", day: today())
        notes.insert(note, at: 0)
        selection = note.id
        query = ""
        titleFocusRequest += 1
        return note.id
    }

    /// Sets the title of note `id`.
    public func setTitle(_ title: String, of id: Note.ID) {
        guard let index = index(of: id) else { return }
        notes[index].title = title
    }

    /// Sets the body of note `id`.
    public func setBody(_ body: String, of id: Note.ID) {
        guard let index = index(of: id) else { return }
        notes[index].body = body
    }

    /// Copies note `id` right after itself, with a new id, and selects the copy.
    public func duplicate(_ id: Note.ID) {
        guard let index = index(of: id) else { return }
        var copy = notes[index]
        copy.id = UUID()
        copy.title += " copy"
        notes.insert(copy, at: index + 1)
        selection = copy.id
    }

    /// Moves note `id` to the position note `target` has now: dragged down it
    /// lands after the target, dragged up before it.
    public func move(_ id: Note.ID, onto target: Note.ID) {
        guard id != target, let from = index(of: id), let to = index(of: target) else { return }
        let note = notes.remove(at: from)
        notes.insert(note, at: to)
    }

    // MARK: Deleting

    /// Starts deleting note `id`: remembers it and shows the confirmation.
    public func requestDelete(_ id: Note.ID) {
        guard index(of: id) != nil else { return }
        pendingDelete = id
        confirmingDelete = true
    }

    /// Deletes the note the confirmation was shown for. When it was the
    /// selection, the note that took its place (else the last one) is selected.
    public func confirmDelete() {
        defer { pendingDelete = nil }
        guard let id = pendingDelete, let index = index(of: id) else { return }
        notes.remove(at: index)
        if selection == id { selection = notes.isEmpty ? nil : notes[min(index, notes.count - 1)].id }
    }

    /// Forgets the pending deletion.
    public func cancelDelete() { pendingDelete = nil }

    // MARK: Files

    /// The notes as a versioned JSON file's bytes.
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(NoteFile(version: NoteFile.currentVersion, notes: notes))
    }

    /// Replaces the notes with those in `data`, or throws and changes nothing.
    public func importData(_ data: Data) throws {
        let file: NoteFile
        do { file = try JSONDecoder().decode(NoteFile.self, from: data) } catch { throw JotterFileError.notAJotterFile }
        guard file.version == NoteFile.currentVersion else { throw JotterFileError.unsupportedVersion(file.version) }
        notes = file.notes
        selection = notes.first?.id
    }

    /// Reads the file at `url` into the notes; a failure becomes the alert.
    public func load(from url: URL) {
        do {
            try importData(Data(contentsOf: url))
            status = "Opened \(url.lastPathComponent)"
        } catch {
            fail(loading: error)
        }
    }

    /// Shows the load-error alert for `error`, leaving the notes alone.
    public func fail(loading error: Error) {
        loadError = (error as? JotterFileError)?.description ?? "\(error.localizedDescription)"
        showsLoadError = true
    }

    /// Records a finished export.
    public func didExport(to url: URL) { status = "Saved \(url.lastPathComponent)" }

    /// Records a failed export.
    public func didFailExport(_ error: Error) { status = "Save failed: \(error.localizedDescription)" }

    // MARK: Statistics

    /// The most recent `limit` days up to today with the number of notes made on each, oldest first.
    public func notesPerDay(limit: Int = 7) -> [(day: Int, count: Int)] {
        let last = today()
        return ((last - limit + 1)...last).map { day in (day, notes.filter { $0.day == day }.count) }
    }

    /// A one-line summary of the numbers the chart draws.
    public var statsSummary: String {
        let words = notes.reduce(0) { $0 + $1.wordCount }
        return "\(notes.count) notes, \(words) words"
    }
}
