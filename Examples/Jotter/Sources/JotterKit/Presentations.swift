import Foundation
import MetalUI

/// The line under the sidebar, and the four presentations the app uses. They sit
/// on this one element because a presentation is anchored to the element it
/// modifies and only one is in flight per window.
///
/// This is a `Component`: the alert forms call their builder closures while the
/// tree builds, so building them inside a component keeps that on the main
/// actor, at layout (the Windows 1 MB stack test builds the tree on a thread).
struct StatusBar: Component {
    let model: NotesModel

    var content: some ElementGroup {
        let title = model.pendingDelete.flatMap { id in model.notes.first { $0.id == id }?.title } ?? "this note"
        Text(model.status).font(size: 11).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Pixels(8))
            // One note, confirmed: Delete runs the deletion, Cancel forgets it.
            .confirmationDialog("Delete this note?", isPresented: model.binding(\.confirmingDelete)) {
                Button("Delete", role: .destructive) { model.confirmDelete() }
                Button("Cancel", role: .cancel) { model.cancelDelete() }
            } message: {
                Text("\"\(title)\" will be removed.")
            }
            // A file that cannot be read: the notes in memory are never replaced.
            .alert("Could not open the file", isPresented: model.binding(\.showsLoadError)) {
                Button("OK") {}
            } message: {
                Text(model.loadError)
            }
            // Save: the exporter writes the bytes the item gives to the chosen file.
            .fileExporter(isPresented: model.binding(\.exporting),
                          item: model.exporting ? (try? model.exportData()) : nil,
                          contentTypes: [.json], defaultFilename: "Jotter",
                          onCompletion: { result in
                              switch result {
                              case .success(let url): model.didExport(to: url)
                              case .failure(let error): model.didFailExport(error)
                              }
                          })
            // Open: the file's notes replace the ones in memory, or an alert says why not.
            .fileImporter(isPresented: model.binding(\.importing), allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): model.load(from: url)
                case .failure(let error): model.fail(loading: error)
                }
            }
    }
}
