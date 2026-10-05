import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Alerts and confirmation dialogs, lane 2, tests 2.20–2.25 (rulings `SV-I`,
// `SV-J` item 1, `SV-K`, `SV-X`, `SV-Y`; spec §6.2). SwiftUI's side:
// `docs/probes/swiftui-platform-services.swift` arms `A1`–`A9`, `C1` and
// `docs/probes/swiftui-alert-presenting.swift` arms `R0`–`R4`, `K0`–`K3`.
//
// A window over `FakePlatformWindow` with `presentsAlertsNatively = true`
// stands for AppKit (an `NSAlert` sheet answering `.alertResult`); `false`
// (the fake's default, SDL's answer) leaves the alert to the window — whose
// drawn panel is lane 3's; lane 2 holds only its model (`SV-AC`). Red before:
// the file does not compile at `3aa9898` (no `.alert`, `AlertButtons`).

// MARK: - 2.20: the resolver (pure)

private func declared(_ title: String, _ role: ButtonRole? = nil) -> AlertButtons.Declared {
    AlertButtons.Declared(title: title, role: role, action: {})
}

private func button(_ title: String, destructive: Bool = false, isDefault: Bool = false,
                    cancel: Bool = false) -> PlatformAlertButton {
    PlatformAlertButton(title: title, isDestructive: destructive, isDefault: isDefault, isCancel: cancel)
}

/// **2.20** (`SV-I` item 3, `SV-X`). The resolver's table, one row per
/// measured shape: order (non-cancel buttons in declaration order, the cancel
/// button last), the synthesized "Cancel" beside a lone destructive and "OK"
/// for no actions, Escape on the cancel button only, Return on the first plain
/// button only when no declared button is destructive — never on the
/// synthesized "OK". Each row also names which declared button each resolved
/// one runs (`nil`: synthesized, runs nothing). Mutations, each reddening its
/// row only: no synthesized Cancel (A5); a destructive button eligible for
/// default (A1); a destructive button not suppressing the default (A5); the
/// cancel button kept in place (A4); no OK (A3); the OK made default (A3).
@Test func alertButtonsResolveSwiftUIsOrderAndKeys() {
    struct Row {
        let name: String
        let input: [AlertButtons.Declared]
        let buttons: [PlatformAlertButton]
        let runs: [Int?]
    }
    let rows: [Row] = [
        Row(name: "A1", input: [declared("Delete", .destructive), declared("Cancel", .cancel)],
            buttons: [button("Delete", destructive: true), button("Cancel", cancel: true)], runs: [0, 1]),
        Row(name: "A2", input: [declared("A"), declared("B"), declared("C")],
            buttons: [button("A", isDefault: true), button("B"), button("C")], runs: [0, 1, 2]),
        Row(name: "A3", input: [], buttons: [button("OK")], runs: [nil]),
        Row(name: "A4", input: [declared("Cancel", .cancel), declared("Delete", .destructive)],
            buttons: [button("Delete", destructive: true), button("Cancel", cancel: true)], runs: [1, 0]),
        Row(name: "A5", input: [declared("Save"), declared("Discard", .destructive)],
            buttons: [button("Save"), button("Discard", destructive: true), button("Cancel", cancel: true)],
            runs: [0, 1, nil]),
        Row(name: "C1", input: [declared("Delete", .destructive), declared("Cancel", .cancel)],
            buttons: [button("Delete", destructive: true), button("Cancel", cancel: true)], runs: [0, 1]),
        Row(name: "K3", input: [declared("Save"), declared("Cancel", .cancel)],
            buttons: [button("Save", isDefault: true), button("Cancel", cancel: true)], runs: [0, 1]),
        Row(name: "cancel only", input: [declared("Cancel", .cancel)],
            buttons: [button("Cancel", cancel: true)], runs: [0]),
        Row(name: "two plain", input: [declared("A"), declared("B")],
            buttons: [button("A", isDefault: true), button("B")], runs: [0, 1]),
    ]
    for row in rows {
        let resolved = AlertButtons.resolve(row.input)
        #expect(resolved.map(\.platform) == row.buttons, "\(row.name): \(resolved.map(\.platform))")
        #expect(resolved.map(\.declaredIndex) == row.runs, "\(row.name): \(resolved.map(\.declaredIndex))")
    }
}

// MARK: - Harness

@Observable @MainActor final class ALModel {
    var shown = false
    var message = "This cannot be undone."
    var data: String?
    var log: [String] = []
    var owner: GlobalElementID?
    var actionsCalls = 0
    var messageCalls = 0

    /// Notes a call of an actions closure (a `let` is allowed in a builder).
    func noteActions() -> Int { actionsCalls += 1; return actionsCalls }
    func noteMessage() -> Int { messageCalls += 1; return messageCalls }

    var binding: Binding<Bool> {
        Binding(get: { self.shown }, set: { self.shown = $0; self.log.append("isPresented=\($0)") })
    }
}

@MainActor private func alWindow<Root: Element>(native: Bool = true,
                                                _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    platform.presentsAlertsNatively = native
    return (window, platform)
}

@MainActor private func a1Tree(_ m: ALModel) -> some Element {
    Column {
        psLeaf().alert("Delete keymap?", isPresented: m.binding) {
            Button("Delete", role: .destructive) {
                m.log.append("delete")
                m.owner = StateDispatch.owner
            }
            Button("Cancel", role: .cancel) { m.log.append("cancel") }
        } message: {
            Text(m.message)
        }
    }
}

private let a1Buttons = [PlatformAlertButton(title: "Delete", isDestructive: true),
                         PlatformAlertButton(title: "Cancel", isCancel: true)]

// MARK: - 2.21–2.25: presentation

/// **2.21** (`SV-I` item 4, `SV-J` item 1, `A1`). A shown alert presents
/// after the frame, once: one `PlatformAlert` with its title, message and the
/// resolved buttons. A message changing while it is up re-presents nothing.
/// Mutation: evaluate the message every frame and re-present.
@MainActor
@Test func anAlertPresentsAfterTheFrameWithItsTitleMessageAndButtons() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try alWindow { a1Tree(m) }
    #expect(platform.presentedAlerts.isEmpty)
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first)
    #expect(platform.presentedAlerts.count == 1)
    #expect(alert.title == "Delete keymap?")
    #expect(alert.message == "This cannot be undone.")
    #expect(alert.buttons == a1Buttons)
    m.message = "Changed."
    window.drawFrameIfNeeded()
    psRedraw(window)
    #expect(platform.presentedAlerts.count == 1, "evaluated at presentation, not re-presented")
    #expect(platform.dismissedPresentations.isEmpty)
    withExtendedLifetime(window) {}
}

/// **2.22** (`SV-I` item 4, `A8`). A button's answer writes `isPresented =
/// false`, then runs its action under the declaring element's dispatch; the
/// synthesized "Cancel" of a lone destructive button runs nothing. Mutation:
/// swap the order.
@MainActor
@Test func anAlertResultWritesIsPresentedFalseThenRunsTheAction() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try alWindow { a1Tree(m) }
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first)
    platform.simulateInput(.alertResult(AlertResultEvent(token: alert.token, button: 0)))
    #expect(m.log == ["isPresented=false", "delete"])
    #expect(m.owner == psOwner, "\(String(describing: m.owner))")

    // A5's shape: Save, Discard, and the synthesized Cancel (index 2).
    let a5 = ALModel()
    a5.shown = true
    let (other, otherPlatform) = try alWindow {
        Column {
            psLeaf().alert("Unsaved", isPresented: a5.binding) {
                Button("Save") { a5.log.append("save") }
                Button("Discard", role: .destructive) { a5.log.append("discard") }
            }
        }
    }
    other.drawFrameIfNeeded()
    let shown = try #require(otherPlatform.presentedAlerts.first)
    #expect(shown.buttons.map(\.title) == ["Save", "Discard", "Cancel"])
    #expect(shown.message == nil)
    otherPlatform.simulateInput(.alertResult(AlertResultEvent(token: shown.token, button: 2)))
    #expect(a5.log == ["isPresented=false"], "the synthesized Cancel runs nothing")
    withExtendedLifetime((window, other)) {}
}

/// **2.23** (`A9`). `isPresented` set `false` while the alert is up dismisses
/// it after the next frame, and runs no action. (2.4's site.)
@MainActor
@Test func isPresentedFalseDismissesTheAlert() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try alWindow { a1Tree(m) }
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first)
    m.shown = false
    window.drawFrameIfNeeded()
    #expect(platform.dismissedPresentations == [alert.token])
    platform.simulateInput(.alertResult(AlertResultEvent(token: alert.token, button: 0)))
    #expect(m.log.isEmpty)
    withExtendedLifetime(window) {}
}

@MainActor private func presentingNilTree(_ m: ALModel) -> some Element {
    Column {
        psLeaf().alert("Delete?", isPresented: m.binding, presenting: m.data) { item in
            let _ = m.noteActions()
            Button("Delete \(item)", role: .destructive) { m.log.append("delete \(item)") }
        } message: { item in
            let _ = m.noteMessage()
            return Text("Item \(item).")
        }
    }
}

/// **2.24** (`SV-Y`, `R0`, `R1`). `presenting: nil` with `isPresented` true
/// still presents: the title, no message, one "OK" — and the actions and
/// message closures are not called; "OK" writes `isPresented = false` and runs
/// nothing (`R4`). With data, the data reaches the actions and the message
/// (`R0`). Mutation: present nothing for `nil`.
@MainActor
@Test func alertPresentingWithNilDataShowsTheTitleAndOK() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try alWindow { presentingNilTree(m) }
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first, "a nil presenting still presents (R1)")
    #expect(alert.title == "Delete?")
    #expect(alert.message == nil)
    #expect(alert.buttons == [PlatformAlertButton(title: "OK")])
    #expect(m.actionsCalls == 0 && m.messageCalls == 0, "nil data calls neither closure")
    platform.simulateInput(.alertResult(AlertResultEvent(token: alert.token, button: 0)))
    #expect(m.log == ["isPresented=false"], "OK runs nothing (R4)")

    let d = ALModel()
    d.shown = true
    d.data = "k1"
    var actionsCalled = 0
    let (other, otherPlatform) = try alWindow {
        Column {
            psLeaf().alert("Delete?", isPresented: d.binding, presenting: d.data) { item in
                actionsCalled += 1
                return Button("Delete \(item)", role: .destructive) { d.log.append("delete \(item)") }
            } message: { item in
                Text("Item \(item).")
            }
        }
    }
    other.drawFrameIfNeeded()
    let withData = try #require(otherPlatform.presentedAlerts.first)
    #expect(withData.message == "Item k1.")
    #expect(withData.buttons.map(\.title) == ["Delete k1", "Cancel"])
    #expect(actionsCalled >= 1)
    otherPlatform.simulateInput(.alertResult(AlertResultEvent(token: withData.token, button: 0)))
    #expect(d.log == ["isPresented=false", "delete k1"])
    withExtendedLifetime((window, other)) {}
}

/// **2.25** (`C1` = `A1`). A confirmation dialog is the same `PlatformAlert`
/// as the `.alert` spelling.
@MainActor
@Test func aConfirmationDialogIsTheSameAlert() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try alWindow {
        Column {
            psLeaf().confirmationDialog("Delete keymap?", isPresented: m.binding) {
                Button("Delete", role: .destructive) { m.log.append("delete") }
                Button("Cancel", role: .cancel) { m.log.append("cancel") }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }
    window.drawFrameIfNeeded()
    let alert = try #require(platform.presentedAlerts.first)
    #expect(alert.title == "Delete keymap?")
    #expect(alert.message == "This cannot be undone.")
    #expect(alert.buttons == a1Buttons)
    platform.simulateInput(.alertResult(AlertResultEvent(token: alert.token, button: 1)))
    #expect(m.log == ["isPresented=false", "cancel"])
    withExtendedLifetime(window) {}
}

/// **2.25b** (`SV-AC`, the drawn alert's model). A platform that declines
/// (`presentAlert` → `false`) leaves the alert to the window: it holds the
/// resolved buttons, and `chooseAlertButton(_:)` runs a button as a native
/// answer would (`isPresented = false` first, then the action, dispatched);
/// `nil` dismisses with no action. Lane 3 draws it. Mutation: drop the model
/// when the platform declines (nothing to choose).
@MainActor
@Test func aDeclinedAlertIsHeldByTheWindowAndChoosingRunsIt() throws {
    let m = ALModel()
    m.shown = true
    let (window, platform) = try alWindow(native: false) { a1Tree(m) }
    window.drawFrameIfNeeded()
    #expect(platform.presentedAlerts.count == 1, "the platform is asked first")
    let drawn = try #require(window.drawnAlert, "a declined alert is the window's to draw")
    #expect(drawn.title == "Delete keymap?")
    #expect(drawn.message == "This cannot be undone.")
    #expect(drawn.buttons.map(\.platform) == a1Buttons)
    window.chooseAlertButton(0)
    #expect(m.log == ["isPresented=false", "delete"])
    #expect(m.owner == psOwner)
    #expect(window.drawnAlert == nil)

    m.log = []
    m.shown = true
    window.drawFrameIfNeeded()
    try #require(window.drawnAlert != nil)
    window.chooseAlertButton(nil)
    #expect(m.log == ["isPresented=false"], "dismissed: no action")
    #expect(window.drawnAlert == nil)
    withExtendedLifetime(window) {}
}
