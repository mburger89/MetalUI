import MetalUI
import Observation
import Foundation

/// The text-selection demo (spec `2026-10-12-text-selection-design.md` §4 "Demo",
/// rulings `SL-A`…`SL-N`), reached with `METALUI_SELECTION_DEMO=1 swift run
/// MetalUIDemo` (macOS 15, where `TextSelection` is): MetalCreator's CT-b in one
/// window.
///
/// - **Title**: a title label; a double click turns it into a field with the
///   whole title selected (typing replaces it; Return or Escape ends the
///   rename), and a readout shows `selection a..<b` as the field publishes it.
/// - **Note**: "Open note" writes `insertionPoint: endIndex` and focuses the
///   editor, so a note opens with its caret at the end; "Select all",
///   "Caret to start" and "Caret to end" write the binding.
///
/// It is a root of its own and not a section of the text-input demo, whose
/// three fields `theTextInputDemoRendersAndTypes` and the accessibility audit
/// pin (`SL-N`). Nothing here is in the default demo, so the fourteen offscreen
/// images and `Expected.swift` do not move. Each part is its own function passed
/// to a generic composer (the Windows 1 MB stack rule); built on a 1 MB thread
/// by `everyProductionTreeBuildsOnAOneMegabyteThread`.
@available(macOS 15, *)
@MainActor
public func selectionDemoContent() -> some Element {
    selectionRoot(header: selectionHeader(), title: SelectionTitleRow(), note: SelectionNoteBlock())
}

/// The demo's state, written only from input.
@available(macOS 15, *)
@MainActor
@Observable
public final class SelectionDemoModel {
    /// The title.
    public var title = "Quarterly plan"
    /// Whether the title is being renamed (shown as a field).
    public var renaming = false
    /// The title field's selection binding.
    public var titleSelection: TextSelection?
    /// The note's text.
    public var note = "Line one\nLine two\nLine three"
    /// The note editor's selection binding.
    public var noteSelection: TextSelection?

    /// A fresh model.
    public init() {}

    /// Back to the launch state.
    public func reset() {
        title = "Quarterly plan"; renaming = false; titleSelection = nil
        note = "Line one\nLine two\nLine three"; noteSelection = nil
    }

    /// `selection a..<b` for `selection` in `text`, or `selection none`.
    public static func readout(_ selection: TextSelection?, in text: String) -> String {
        guard case .selection(let range)? = selection?.indices else { return "selection none" }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        return "selection \(lower)..<\(upper)"
    }
}

/// The one model the demo and its tests share.
@available(macOS 15, *)
@MainActor public let selectionDemoModel = SelectionDemoModel()

@available(macOS 15, *)
@MainActor
private func selectionRoot(header: some Element, title: some ElementGroup, note: some ElementGroup) -> some Element {
    Column(gap: Pixels(16)) {
        header
        title
        note
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

@available(macOS 15, *)
@MainActor
private func selectionHeader() -> some Element {
    Text("Selection — double click the title to rename it with all of it selected · the note opens with its caret at the end")
        .font(size: 13)
}

/// The title row: a label, or (renaming) a field opening with the whole title
/// selected and focused from code.
@available(macOS 15, *)
private struct SelectionTitleRow: Component {
    @FocusState var focused: Bool

    var content: some ElementGroup {
        let model = selectionDemoModel
        Column(gap: Pixels(6)) {
            if model.renaming {
                TextField("Title",
                          text: Binding(get: { selectionDemoModel.title }, set: { selectionDemoModel.title = $0 }),
                          selection: Binding(get: { selectionDemoModel.titleSelection },
                                             set: { selectionDemoModel.titleSelection = $0 }))
                    .focused($focused)
                    .onKeyPress(.escape) { selectionDemoModel.renaming = false; return .handled }
                    .onKeyPress(.return) { selectionDemoModel.renaming = false; return .handled }
                    .onAppear { focused = true }
                    .frame(width: Pixels(320))
            } else {
                Text(model.title).font(size: 20)
                    .onTapGesture(count: 2) {
                        selectionDemoModel.titleSelection = TextSelection(
                            range: selectionDemoModel.title.startIndex..<selectionDemoModel.title.endIndex)
                        selectionDemoModel.renaming = true
                    }
            }
            Text(SelectionDemoModel.readout(model.titleSelection, in: model.title)).font(size: 12)
        }
        .alignItems(.flexStart)
    }
}

/// The note editor and the buttons that write its binding.
@available(macOS 15, *)
private struct SelectionNoteBlock: Component {
    @FocusState var focused: Bool

    var content: some ElementGroup {
        let model = selectionDemoModel
        Column(gap: Pixels(8)) {
            Row(gap: Pixels(8)) {
                Button("Open note") {
                    selectionDemoModel.noteSelection = TextSelection(
                        insertionPoint: selectionDemoModel.note.endIndex)
                    focused = true
                }
                Button("Select all") {
                    selectionDemoModel.noteSelection = TextSelection(
                        range: selectionDemoModel.note.startIndex..<selectionDemoModel.note.endIndex)
                }
                Button("Caret to start") {
                    selectionDemoModel.noteSelection = TextSelection(
                        insertionPoint: selectionDemoModel.note.startIndex)
                }
                Button("Caret to end") {
                    selectionDemoModel.noteSelection = TextSelection(
                        insertionPoint: selectionDemoModel.note.endIndex)
                }
            }
            TextEditor("Note",
                       text: Binding(get: { selectionDemoModel.note }, set: { selectionDemoModel.note = $0 }),
                       selection: Binding(get: { selectionDemoModel.noteSelection },
                                          set: { selectionDemoModel.noteSelection = $0 }))
                .focused($focused)
                .frame(width: Pixels(420), height: Pixels(140))
            Text(SelectionDemoModel.readout(model.noteSelection, in: model.note)).font(size: 12)
        }
        .alignItems(.flexStart)
    }
}
