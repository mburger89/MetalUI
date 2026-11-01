import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI
@testable import MetalUIAppKit

// Dialog and alert extras (round 3, item R3-6; rulings `SV-AO`…; record 179).
// SwiftUI's side: `docs/probes/swiftui-dialog-extras.swift` arms `F0`–`F4`
// (file-dialog label and message), `C1`–`C12` (confirmation dialogs), `L1`–`L11`
// (non-Text button labels) and `T1`–`T3` (text fields, carried).

private func openDialog(_ label: String? = nil, message: String? = nil) -> PlatformFileDialog {
    PlatformFileDialog(token: 1, kind: .open(allowsMultipleSelection: false), prompt: label, message: message)
}

// MARK: - F: the file dialog's label and message

/// **F1** (`SV-AO` item 1). The seam carries the message beside the title and
/// prompt, and defaults to `nil`.
///
/// Mutation **MF1**: drop the `message` assignment in `PlatformFileDialog.init`.
@Test func theSeamCarriesTheFileDialogsMessage() {
    #expect(openDialog(message: "Choose the keymap").message == "Choose the keymap")
    #expect(PlatformFileDialog(token: 1, kind: .open(allowsMultipleSelection: false)).message == nil)
    #expect(openDialog("Pick it") != openDialog("Pick it", message: "m"), "the message is part of the request's value")
}

/// **F2** (`SV-AO` item 1, `F1`/`F2`). `.fileDialogConfirmationLabel` and
/// `.fileDialogMessage` written **outside** a presenter reach its dialog (the
/// confirming button's title and the panel's message); written on the content
/// inside it they do not (`F2`: the importer reads the environment at its own
/// position); the control states neither.
///
/// Mutations **MF2a**: `notePresentation` reads the window's root environment
/// instead of the scope's position; **MF2b**: never copy the label into the
/// dialog; **MF2c**: never copy the message.
@MainActor
@Test func aFileImporterReadsItsLabelAndMessageFromTheEnvironmentAboveIt() throws {
    let m = PSModel()
    m.shown = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json]) { _ in }
                .fileDialogConfirmationLabel(Text("Pick it"))
                .fileDialogMessage(Text("Choose the keymap"))
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    #expect(dialog.prompt == "Pick it")
    #expect(dialog.message == "Choose the keymap")
    withExtendedLifetime(window) {}

    let inside = PSModel()
    inside.shown = true
    let (innerWindow, innerPlatform) = try psWindow {
        Column {
            psLeaf().fileDialogConfirmationLabel(Text("Pick it")).fileDialogMessage(Text("Choose the keymap"))
                .fileImporter(isPresented: inside.binding, allowedContentTypes: [.json]) { _ in }
        }
    }
    innerWindow.drawFrameIfNeeded()
    let innerDialog = try #require(innerPlatform.presentedFileDialogs.first)
    #expect(innerDialog.prompt == nil && innerDialog.message == nil, "inside the presenter is not above it (F2)")

    let control = PSModel()
    control.shown = true
    let (controlWindow, controlPlatform) = try psWindow {
        Column { psLeaf().fileImporter(isPresented: control.binding, allowedContentTypes: [.json]) { _ in } }
    }
    controlWindow.drawFrameIfNeeded()
    let plain = try #require(controlPlatform.presentedFileDialogs.first)
    #expect(plain.prompt == nil && plain.message == nil, "F0: neither stated")
    withExtendedLifetime((innerWindow, controlWindow)) {}
}

/// **F3** (`SV-AO` item 1, `F3`). An exporter's own "Export" prompt gives way
/// to the environment's label; the message arrives; the String spellings read
/// like the `Text` ones; the nearest writer wins.
///
/// Mutation **MF3**: the environment's label ignored when the request has a prompt.
@MainActor
@Test func anExporterTakesTheEnvironmentsLabelOverItsExportPrompt() throws {
    let m = PSModel()
    m.shown = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileExporter(isPresented: m.binding, item: Data("{}".utf8), contentTypes: [.json],
                                  defaultFilename: "k", onCompletion: { _ in })
                .fileDialogConfirmationLabel("Keep").fileDialogMessage("Where to keep it")
                .fileDialogConfirmationLabel("Far")
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    #expect(dialog.prompt == "Keep", "the writer nearest the presenter wins (EV-A), over the exporter's own Export")
    #expect(dialog.title == "Export")
    #expect(dialog.message == "Where to keep it")

    let plain = PSModel()
    plain.shown = true
    let (other, otherPlatform) = try psWindow {
        Column {
            psLeaf().fileExporter(isPresented: plain.binding, item: Data("{}".utf8), contentTypes: [.json],
                                  onCompletion: { _ in })
        }
    }
    other.drawFrameIfNeeded()
    #expect(otherPlatform.presentedFileDialogs.first?.prompt == "Export", "no label: the exporter's own prompt")
    withExtendedLifetime((window, other)) {}
}

/// **F4** (`SV-AO` item 1, HT-X 1). The harness exposes the label and message
/// of the dialog on screen.
@MainActor
@Test func theHeadlessHarnessShowsTheLabelAndMessageOfThePresentedDialog() throws {
    let (window, platform) = try psWindow { Column { psLeaf() } }
    let dialog = openDialog("Use folder", message: "Pick a folder")
    #expect(platform.presentFileDialog(dialog))
    #expect(platform.presentedFileDialogs.last?.prompt == "Use folder")
    #expect(platform.presentedFileDialogs.last?.message == "Pick a folder")
    withExtendedLifetime(window) {}
}

/// **F5** (`SV-AO` item 2). AppKit's panel texts are the seam's: the title,
/// the confirming button's `prompt` and the `message` — read without an
/// `NSOpenPanel`, whose initialiser does not return under a locked screen.
///
/// Mutation **MF5**: `panelTexts` drops the message.
@Test func theAppKitPanelTextsAreTheSeams() {
    let texts = AppKitWindow.panelTexts(PlatformFileDialog(token: 1, kind: .open(allowsMultipleSelection: false),
                                                           title: "T", prompt: "P", message: "M"))
    #expect(texts.title == "T" && texts.prompt == "P" && texts.message == "M")
    let none = AppKitWindow.panelTexts(openDialog())
    #expect(none.title == nil && none.prompt == nil && none.message == nil)
}

// MARK: - C: confirmationDialog

private let cdVisibilities: [Visibility] = [.automatic, .visible, .hidden]

/// **C1** (`SV-AO` item 3, `C1`–`C8`). `Visibility` has SwiftUI's three cases,
/// and `titleVisibility:` changes nothing shown: AppKit's `NSAlert` shows the
/// title whatever it is — with a message, without one, hidden — so the request
/// is the same for all three and for the omitted argument.
///
/// Mutation **MC1**: `.hidden` blanks the title.
@MainActor
@Test func titleVisibilityIsAcceptedAndNeverHidesTheTitle() throws {
    #expect(Visibility.allCases == [.automatic, .visible, .hidden])
    for visibility in cdVisibilities {
        for withMessage in [true, false] {
            let m = ALModel()
            m.shown = true
            let (window, platform) = try dxAlertWindow {
                Column {
                    if withMessage {
                        psLeaf().confirmationDialog("Title", isPresented: m.binding, titleVisibility: visibility) {
                            Button("Go") {}
                        } message: { Text("Message") }
                    } else {
                        psLeaf().confirmationDialog("Title", isPresented: m.binding, titleVisibility: visibility) {
                            Button("Go") {}
                        }
                    }
                }
            }
            window.drawFrameIfNeeded()
            let alert = try #require(platform.presentedAlerts.first)
            #expect(alert.title == "Title", "\(visibility) message=\(withMessage)")
            #expect(alert.message == (withMessage ? "Message" : nil))
            withExtendedLifetime(window) {}
        }
    }
}

private func plat(_ title: String, destructive: Bool = false, isDefault: Bool = false,
                  cancel: Bool = false) -> PlatformAlertButton {
    PlatformAlertButton(title: title, isDestructive: destructive, isDefault: isDefault, isCancel: cancel)
}

private func decl(_ title: String, _ role: ButtonRole? = nil) -> AlertButtons.Declared {
    AlertButtons.Declared(title: title, role: role, action: {})
}

/// **C2** (`SV-AO` item 3, `C9`–`C12`, `L7`). A confirmation dialog's buttons
/// are an alert's with two differences measured on AppKit: a missing cancel
/// button is always synthesized when there are actions (an alert's plain
/// buttons get none, `A2`), and then nothing is the default — Return needs a
/// *declared* cancel button beside a plain one (`C11`).
///
/// Mutations **MC2a**: confirmation resolves as an alert (no synthesized
/// Cancel for plain buttons); **MC2b**: a synthesized Cancel still leaves the
/// first plain button default.
@Test func aConfirmationDialogSynthesizesItsCancelButton() {
    let rows: [(String, [AlertButtons.Declared], [PlatformAlertButton], [Int?])] = [
        ("C9", [], [plat("OK")], [nil]),
        ("C10", [decl("A"), decl("B")], [plat("A"), plat("B"), plat("Cancel", cancel: true)], [0, 1, nil]),
        ("C11", [decl("A"), decl("Stop", .cancel)], [plat("A", isDefault: true), plat("Stop", cancel: true)], [0, 1]),
        ("C12", [decl("Delete", .destructive)],
         [plat("Delete", destructive: true), plat("Cancel", cancel: true)], [0, nil]),
        ("C1", [decl("Delete", .destructive), decl("Cancel", .cancel)],
         [plat("Delete", destructive: true), plat("Cancel", cancel: true)], [0, 1]),
    ]
    for (name, input, buttons, runs) in rows {
        let resolved = AlertButtons.resolve(input, confirmation: true)
        #expect(resolved.map(\.platform) == buttons, "\(name): \(resolved.map(\.platform))")
        #expect(resolved.map(\.declaredIndex) == runs, "\(name): \(resolved.map(\.declaredIndex))")
    }
    // The alert's own rule is unchanged (A2): plain buttons alone get no Cancel.
    #expect(AlertButtons.resolve([decl("A"), decl("B")]).map(\.platform) == [plat("A", isDefault: true), plat("B")])
}

/// **C3** (`SV-AO` item 3, `C10`). Through the modifier: a confirmation dialog
/// of plain buttons shows them with a trailing Cancel, and the alert spelling
/// does not.
@MainActor
@Test func theConfirmationDialogModifierShowsTheSynthesizedCancel() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try dxAlertWindow {
        Column {
            psLeaf().confirmationDialog("Pick", isPresented: m.binding) {
                Button("A") { m.log.append("A") }
                Button("B") { m.log.append("B") }
            }
        }
    }
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first)
    #expect(alert.buttons == [plat("A"), plat("B"), plat("Cancel", cancel: true)])
    platform.simulateInput(.alertResult(AlertResultEvent(token: alert.token, button: 2)))
    #expect(m.log == ["isPresented=false"], "the synthesized Cancel runs nothing")
    withExtendedLifetime(window) {}
}

// MARK: - L: a Button whose label is not a plain Text

@MainActor private func dxAlertWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    platform.presentsAlertsNatively = true
    return (window, platform)
}

/// **L1** (`SV-AO` item 4, `L1`–`L6`, `L11`). A button's title is the first
/// `Text` in its label, depth first: a row of a shape and a text, a column of
/// two texts (the first), a nested pair after a shape (the first of the
/// pair), a styled `Text`. Its action runs as a plain button's does.
///
/// Mutations **ML1a**: the walk takes the last `Text`; **ML1b**: the walk
/// stops at the first container (no nesting).
@MainActor
@Test func aButtonsTitleIsTheFirstTextInItsLabel() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try dxAlertWindow {
        Column {
            psLeaf().alert("Labels", isPresented: m.binding) {
                Button(action: { m.log.append("row") }) { Row { Box().frame(width: Pixels(4), height: Pixels(4)); Text("Star it") } }
                Button(action: { m.log.append("column") }) { Column { Text("First"); Text("Second") } }
                Button(action: { m.log.append("nested") }) {
                    Column { Box().frame(width: Pixels(4), height: Pixels(4)); Row { Text("Deep"); Text("Other") } }
                }
                Button(action: { m.log.append("plain") }) { Text("Plain") }
            }
        }
    }
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first)
    #expect(alert.buttons.map(\.title) == ["Star it", "First", "Deep", "Plain"])
    platform.simulateInput(.alertResult(AlertResultEvent(token: alert.token, button: 2)))
    #expect(m.log == ["isPresented=false", "nested"])
    withExtendedLifetime(window) {}
}

/// **L2** (`SV-AO` item 4, `L3`, `L8`–`L10`). A button whose label holds no
/// `Text` is left out — SwiftUI shows the others, and when none is left the
/// lone "OK" that runs nothing (`L3`, `L10`). A left-out cancel button does
/// not count as a cancel button (`L9`).
///
/// Mutations **ML2a**: a textless button becomes an empty-titled one;
/// **ML2b**: a textless button still counts for its role.
@MainActor
@Test func aButtonWithNoTextIsLeftOutOfAnAlert() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try dxAlertWindow {
        Column {
            psLeaf().alert("Mixed", isPresented: m.binding) {
                Button("A") { m.log.append("A") }
                Button(action: { m.log.append("shape") }) { Box().frame(width: Pixels(4), height: Pixels(4)) }
                Button(role: .cancel, action: { m.log.append("shape cancel") }) { Box() }
                Button("C") { m.log.append("C") }
            }
        }
    }
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first)
    #expect(alert.buttons == [plat("A", isDefault: true), plat("C")], "L8/L9: no cancel from a left-out button")

    let only = ALModel()
    only.shown = true
    let (other, otherPlatform) = try dxAlertWindow {
        Column {
            psLeaf().alert("Only", isPresented: only.binding) {
                Button(action: { only.log.append("shape") }) { Box() }
            }
        }
    }
    other.drawFrameIfNeeded()
    let ok = try #require(otherPlatform.presentedAlerts.first)
    #expect(ok.buttons == [plat("OK")], "L3/L10")
    otherPlatform.simulateInput(.alertResult(AlertResultEvent(token: ok.token, button: 0)))
    #expect(only.log == ["isPresented=false"], "the lone OK runs nothing")
    withExtendedLifetime((window, other)) {}
}

/// **L3** (`SV-AO` item 4, `L7`). The same walk serves a confirmation dialog.
@MainActor
@Test func aConfirmationDialogTakesAButtonsTitleFromItsLabelToo() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try dxAlertWindow {
        Column {
            psLeaf().confirmationDialog("Trash?", isPresented: m.binding, titleVisibility: .visible) {
                Button(action: { m.log.append("trash") }) { Row { Box(); Text("Trash") } }
            }
        }
    }
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first)
    #expect(alert.buttons == [plat("Trash"), plat("Cancel", cancel: true)])
    withExtendedLifetime(window) {}
}
