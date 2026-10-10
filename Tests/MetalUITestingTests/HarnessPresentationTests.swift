import Foundation
import MetalUI
import MetalUITesting
import Observation
import Testing

// Spec §4.2 tests 2.9–2.12, 2.21, 2.22 (lane 2): alerts, file dialogs and the
// toolbar read at the seam and answered as a platform answers — queued
// `InputEvent`s (ruling `HT-H`) — and, with the option off, drawn by the
// window and driven through the tree. PLAIN imports.

/// What a presentation fixture shows and logs.
@Observable @MainActor private final class PresentModel {
    var shown = false
    var log: [String] = []
    var count = 0

    var binding: Binding<Bool> {
        Binding(get: { self.shown }, set: { self.shown = $0 })
    }
}

/// A button that shows `m`'s alert: Delete (destructive), Cancel (cancel), a
/// message.
@MainActor private func alertTree(_ m: PresentModel) -> some Element {
    VStack(spacing: 0) {
        Button("Ask") { m.shown = true }
            .alert("Delete keymap?", isPresented: m.binding) {
                Button("Delete", role: .destructive) { m.log.append("delete") }
                Button("Cancel", role: .cancel) { m.log.append("cancel") }
            } message: {
                Text("This cannot be undone.")
            }
    }
}

/// 2.9 — a native alert is read at the seam (title, message, buttons) and
/// answered by its button's title: the action runs, `isPresented` is written
/// `false`, and `presentedAlert` is `nil` after. Mutation: the answer's token
/// off by one.
@Test @MainActor func anAlertIsReadAndAnsweredByButtonTitle() throws {
    let m = PresentModel()
    let window = try harnessWindow { alertTree(m) }
    #expect(window.presentedAlert == nil)
    try window.click(window.element(label: "Ask"))
    let alert = try #require(window.presentedAlert)
    #expect(alert.title == "Delete keymap?")
    #expect(alert.message == "This cannot be undone.")
    #expect(alert.buttons.map(\.title) == ["Delete", "Cancel"])
    try window.respondToAlert(button: "Delete")
    #expect(m.log == ["delete"])
    #expect(!m.shown)
    #expect(window.presentedAlert == nil)
    #expect(throws: TestHarnessError.nothingPresented("alert")) { try window.respondToAlert(button: "Delete") }
}

/// 2.10 — with `presentsAlertsNatively` off (SDL's answer) the window draws
/// the alert: an `.alert` node whose `Delete` button is pressed by a click
/// through the tree; `presentedAlert` stays `nil`. Mutation: the option
/// ignored (`presentAlert` answers `true`).
@Test @MainActor func aDeclinedAlertIsDrawnAndPressedThroughTheTree() throws {
    let m = PresentModel()
    let window = try harnessWindow(options: .init(presentsAlertsNatively: false)) { alertTree(m) }
    try window.click(window.element(label: "Ask"))
    #expect(window.presentedAlert == nil, "a drawn alert is the window's, not the platform's")
    let alerts = try window.elements(role: .alert)
    try #require(alerts.count == 1)
    #expect(alerts[0].label == "Delete keymap?")
    let delete = try #require(try window.elements { $0.role == .button && $0.label == "Delete" }.first)
    try window.click(delete)
    #expect(m.log == ["delete"])
    #expect(try window.elements(role: .alert).isEmpty)
}

/// A file importer fixture: a button that shows it, the result logged.
@MainActor private func importerTree(_ m: PresentModel) -> some Element {
    VStack(spacing: 0) {
        Button("Import") { m.shown = true }
            .fileImporter(isPresented: m.binding, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): m.log.append("chose \(url.path)")
                case .failure: m.log.append("failed")
                }
            }
    }
}

/// 2.11 — a `.fileImporter` is read at the seam (an open dialog, one file)
/// and answered with a path: the handler hears `.success` with it, and
/// `presentedFileDialog` is `nil` after. Mutation: the outcome sent as
/// `.cancelled`.
@Test @MainActor func aFileImporterIsAnsweredWithPaths() throws {
    let m = PresentModel()
    let window = try harnessWindow { importerTree(m) }
    try window.click(window.element(label: "Import"))
    let dialog = try #require(window.presentedFileDialog)
    #expect(dialog.kind == .open(allowsMultipleSelection: false))
    try window.respondToFileDialog(choosing: ["/tmp/a.json"])
    #expect(m.log == ["chose /tmp/a.json"])
    #expect(!m.shown)
    #expect(window.presentedFileDialog == nil)
}

/// 2.12 — a cancelled file dialog writes `isPresented = false` and calls no
/// completion (`D2`); the dialog is answered. The named control for 2.11's
/// arm (no mutation of its own).
@Test @MainActor func aCancelledFileDialogReachesTheHandler() throws {
    let m = PresentModel()
    let window = try harnessWindow { importerTree(m) }
    try window.click(window.element(label: "Import"))
    try #require(window.presentedFileDialog != nil)
    try window.cancelFileDialog()
    #expect(!m.shown, "the binding is written false")
    #expect(m.log.isEmpty, "a cancel calls no completion")
    #expect(window.presentedFileDialog == nil)
    #expect(throws: TestHarnessError.nothingPresented("file dialog")) { try window.cancelFileDialog() }
}

/// A root with a toolbar of one button, `Add`, and a body.
@MainActor private func toolbarTree(_ m: PresentModel) -> some Element {
    VStack(spacing: 0) {
        Text("count \(m.count)")
            .frame(width: Pixels(100), height: Pixels(50))
            .toolbar {
                ToolbarItem(id: "add") { Button("Add") { m.count += 1 } }
            }
    }
}

/// 2.21 — a native toolbar is read at the seam and its item triggered by id:
/// the button's action runs and the next frame shows it. Mutation: the
/// `.toolbarAction` names the wrong item.
@Test @MainActor func theToolbarIsReadAndAnItemTriggered() throws {
    let m = PresentModel()
    let window = try harnessWindow { toolbarTree(m) }
    let toolbar = try #require(window.toolbar)
    #expect(toolbar.items.map(\.id) == ["add"])
    try window.performToolbarItem("add")
    #expect(m.count == 1)
    #expect(try window.element(label: "count 1").role == .staticText)
    #expect(throws: TestHarnessError.nothingPresented("toolbar item \"nope\"")) {
        try window.performToolbarItem("nope")
    }
}

/// 2.22 — with `showsToolbarNatively` off (SDL's answer) the window draws its
/// 39-point strip (`MD-K`) and the button in it is found by label and
/// clicked; `toolbar` is `nil`. Mutation: the option ignored (`setToolbar`
/// answers `true`).
@Test @MainActor func aDeclinedToolbarIsDrawnAndItsButtonClickable() throws {
    let m = PresentModel()
    let window = try harnessWindow(options: .init(showsToolbarNatively: false)) { toolbarTree(m) }
    #expect(window.toolbar == nil)
    let add = try window.element(label: "Add")
    #expect(add.frame.origin.y.value + add.frame.size.height.value <= 39, "in the strip")
    try window.click(add)
    #expect(m.count == 1)
}
