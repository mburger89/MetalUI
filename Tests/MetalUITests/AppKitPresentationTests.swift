import Testing
import Foundation
import Metal
import AppKit
import UniformTypeIdentifiers
import MetalUICore
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// Platform services, lane 1, tests 1.1–1.9 (rulings `SV-B`, `SV-E`, `SV-F`,
// `SV-J` item 1, `SV-M`, `SV-N` item 7, `SV-X`; spec
// `docs/superpowers/specs/2026-10-04-platform-services-design.md` §6.1). A real
// `AppKitPlatform` window: open and save panels and `NSAlert`s attach as real
// sheets headless (the probe's `D1`, `X1`, `A1` were recorded so, on a locked
// screen with the app inactive). Nothing sleeps: a sheet's attachment and a
// queued answer are waited for by **bounded run-loop turns**
// (`RunLoop.main.run(until:)` of a few milliseconds, at most `turnLimit`
// times) — a turn, not a sleep. Every test ends every sheet it began.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class ConstantSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private final class Log {
    var events: [InputEvent] = []
    var resizes: [Size<Pixels>] = []
}

/// The most turns a wait takes before it gives up.
private let turnLimit = 200

/// Runs the main run loop in short turns until `done` holds or `turnLimit`
/// turns have passed; answers whether `done` held.
@MainActor @discardableResult
private func turn(until done: () -> Bool) -> Bool {
    for _ in 0..<turnLimit {
        if done() { return true }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
    }
    return done()
}

/// Runs `count` short turns, for "nothing more arrives".
@MainActor private func turns(_ count: Int) {
    for _ in 0..<count { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005)) }
}

/// A real AppKit window of `width × height`, its `onInput` and `onResize`
/// logging.
@MainActor private func hostWindow(width: Float = 400, height: Float = 300)
    throws -> (AppKitPlatform, AppKitWindow, NSWindow, Log) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let platformWindow = try platform.openWindow(title: "Services \(UUID().uuidString)",
                                                 size: Size(width: px(width), height: px(height)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    let log = Log()
    appKit.onInput = { event in log.events.append(event); return true }
    appKit.onResize = { size, _ in log.resizes.append(size) }
    return (platform, appKit, nsWindow, log)
}

/// Ends whatever sheet is attached to `window`, then closes it.
@MainActor private func tearDown(_ window: NSWindow) {
    if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .abort) }
    turns(2)
    window.close()
}

/// `ContentType.json`'s seam value (`SV-E`): `public.json`, conforming to
/// `public.text` and its parents, extension `json`.
private let jsonType = PlatformFileType(identifier: "public.json",
                                        conformsTo: ["public.text", "public.data", "public.item"],
                                        filenameExtensions: ["json"])

private func fileResults(_ log: Log) -> [FileDialogResultEvent] {
    log.events.compactMap { if case .fileDialogResult(let r) = $0 { r } else { nil } }
}

private func alertResults(_ log: Log) -> [AlertResultEvent] {
    log.events.compactMap { if case .alertResult(let r) = $0 { r } else { nil } }
}

/// **1.1** (`SV-F`, `D1`). An open dialog is a **sheet** on the window — not
/// app-modal — filtering to the declared types, files only, multiple selection
/// as asked.
///
/// Mutation **M1.1**: `allowsMultipleSelection` not copied (and, separately,
/// `canChooseDirectories = true`).
@MainActor
@Test func appKitOpenDialogIsASheetWithTheDeclaredTypes() throws {
    let (_, appKit, nsWindow, _) = try hostWindow()
    defer { tearDown(nsWindow) }
    let shown = appKit.presentFileDialog(PlatformFileDialog(token: 1, kind: .open(allowsMultipleSelection: true),
                                                            allowedTypes: [jsonType]))
    #expect(shown)
    try #require(turn { nsWindow.attachedSheet != nil }, "no sheet attached")
    let panel = try #require(nsWindow.attachedSheet as? NSOpenPanel, "\(String(describing: nsWindow.attachedSheet))")
    #expect(panel.allowedContentTypes == [.json])
    #expect(panel.allowsMultipleSelection)
    #expect(panel.canChooseFiles && !panel.canChooseDirectories)
    #expect(NSApplication.shared.modalWindow == nil, "a sheet, not an application-modal panel")
}

/// **1.2** (`SV-F`, `X1`). A save dialog carries the default name (extension
/// hidden), the types, and the seam's prompt and title.
///
/// Mutation **M1.2**: the name not copied.
@MainActor
@Test func appKitSaveDialogCarriesTheNameTypesAndExportPrompt() throws {
    let (_, appKit, nsWindow, _) = try hostWindow()
    defer { tearDown(nsWindow) }
    #expect(appKit.presentFileDialog(PlatformFileDialog(token: 2, kind: .save(defaultFilename: "keymap"),
                                                        allowedTypes: [jsonType],
                                                        title: "Export", prompt: "Export")))
    try #require(turn { nsWindow.attachedSheet != nil }, "no sheet attached")
    let panel = try #require(nsWindow.attachedSheet as? NSSavePanel)
    #expect(!(panel is NSOpenPanel))
    #expect(panel.nameFieldStringValue == "keymap")
    #expect(panel.isExtensionHidden)
    #expect(panel.allowedContentTypes == [.json])
    #expect(panel.prompt == "Export")
    #expect(panel.title == "Export")
}

/// **1.3** (`SV-B` item 2, `SV-F`). A cancelled dialog's answer is queued: no
/// `onInput` while AppKit ends the sheet, then exactly one
/// `.fileDialogResult(token, .cancelled)` after a run-loop turn.
///
/// Mutation **M1.3**: deliver synchronously inside the completion handler (the
/// count during the call is 1).
@MainActor
@Test func appKitCancelledDialogArrivesAsQueuedInput() throws {
    let (_, appKit, nsWindow, log) = try hostWindow()
    defer { tearDown(nsWindow) }
    #expect(appKit.presentFileDialog(PlatformFileDialog(token: 3, kind: .open(allowsMultipleSelection: false),
                                                        allowedTypes: [jsonType])))
    try #require(turn { nsWindow.attachedSheet != nil }, "no sheet attached")
    let panel = try #require(nsWindow.attachedSheet as? NSOpenPanel)
    var duringCall = -1
    appKit.onSheetCompletionForTesting = { duringCall = log.events.count }
    panel.cancel(nil)
    try #require(turn { !fileResults(log).isEmpty }, "no answer arrived")
    turns(5)
    #expect(duringCall == 0, "nothing may be delivered inside AppKit's completion handler: \(duringCall)")
    #expect(fileResults(log) == [FileDialogResultEvent(token: 3, outcome: .cancelled)])
}

/// **1.4** (`SV-F`). `dismissPresentation(token:)` ends the sheet and answers
/// nothing.
///
/// Mutation **M1.4**: not suppressing the `.abort` answer (a `.cancelled`
/// arrives).
@MainActor
@Test func appKitDismissPresentationEndsTheSheetAndAnswersNothing() throws {
    let (_, appKit, nsWindow, log) = try hostWindow()
    defer { tearDown(nsWindow) }
    #expect(appKit.presentFileDialog(PlatformFileDialog(token: 4, kind: .open(allowsMultipleSelection: false),
                                                        allowedTypes: [])))
    try #require(turn { nsWindow.attachedSheet != nil }, "no sheet attached")
    appKit.dismissPresentation(token: 4)
    #expect(turn { nsWindow.attachedSheet == nil }, "the sheet must end")
    turns(20)
    #expect(fileResults(log).isEmpty, "a dismissed dialog answers nothing: \(fileResults(log))")
}

/// **1.5** (`SV-F`). A second dialog while a sheet is attached answers `false`
/// (AppKit shows one sheet at a time); so does an alert.
///
/// Mutation **M1.5**: drop the attached-sheet check.
@MainActor
@Test func appKitSecondDialogWhileASheetIsUpAnswersFalse() throws {
    let (_, appKit, nsWindow, _) = try hostWindow()
    defer { tearDown(nsWindow) }
    #expect(appKit.presentFileDialog(PlatformFileDialog(token: 5, kind: .open(allowsMultipleSelection: false),
                                                        allowedTypes: [])))
    try #require(turn { nsWindow.attachedSheet != nil }, "no sheet attached")
    #expect(!appKit.presentFileDialog(PlatformFileDialog(token: 6, kind: .save(defaultFilename: nil),
                                                         allowedTypes: [])))
    #expect(!appKit.presentAlert(PlatformAlert(token: 7, title: "T", message: nil,
                                               buttons: [PlatformAlertButton(title: "OK")])))
}

private func button(_ title: String, destructive: Bool = false, isDefault: Bool = false,
                    cancel: Bool = false) -> PlatformAlertButton {
    PlatformAlertButton(title: title, isDestructive: destructive, isDefault: isDefault, isCancel: cancel)
}

/// **1.6** (`SV-J` item 1, `SV-X`). An alert is an `NSAlert` sheet with the
/// resolver's buttons in order, Return only on the default (`K3`: Save; `A1`,
/// `A5`: none), Escape only on the cancel button, and the destructive button
/// marked.
///
/// Mutation **M1.6**: leave NSAlert's own first-button Return (the `A1` shape
/// gains `"\r"` on Delete).
@MainActor
@Test func appKitAlertIsASheetWithSwiftUIsKeysAndOrder() throws {
    let shapes: [(name: String, buttons: [PlatformAlertButton], keys: [String], destructive: [Bool])] = [
        ("K3", [button("Save", isDefault: true), button("Cancel", cancel: true)],
         ["\r", "\u{1b}"], [false, false]),
        ("A1", [button("Delete", destructive: true), button("Cancel", cancel: true)],
         ["", "\u{1b}"], [true, false]),
        ("A5", [button("Save"), button("Discard", destructive: true), button("Cancel", cancel: true)],
         ["", "", "\u{1b}"], [false, true, false]),
    ]
    for (index, shape) in shapes.enumerated() {
        let (_, appKit, nsWindow, _) = try hostWindow()
        defer { tearDown(nsWindow) }
        let token = 10 + index
        #expect(appKit.presentAlert(PlatformAlert(token: token, title: "Delete?", message: "It goes.",
                                                  buttons: shape.buttons)), "\(shape.name)")
        try #require(turn { nsWindow.attachedSheet != nil }, "\(shape.name): no sheet attached")
        let alert = try #require(appKit.presentedAlert(token: token), "\(shape.name)")
        #expect(alert.messageText == "Delete?" && alert.informativeText == "It goes.", "\(shape.name)")
        #expect(alert.buttons.map(\.title) == shape.buttons.map(\.title), "\(shape.name)")
        #expect(alert.buttons.map(\.keyEquivalent) == shape.keys, "\(shape.name)")
        #expect(alert.buttons.map(\.hasDestructiveAction) == shape.destructive, "\(shape.name)")
        #expect(nsWindow.attachedSheet === alert.window, "\(shape.name): the alert is the attached sheet")
    }
}

/// **1.7** (`SV-J` item 1). A pressed alert button reports its **index** in
/// `PlatformAlert.buttons`, queued after the sheet ends.
///
/// Mutation **M1.7**: report the response code (1001) instead of the index.
@MainActor
@Test func appKitAlertButtonReportsItsIndexAfterTheSheetEnds() throws {
    let (_, appKit, nsWindow, log) = try hostWindow()
    defer { tearDown(nsWindow) }
    #expect(appKit.presentAlert(PlatformAlert(token: 20, title: "Save?", message: nil,
                                              buttons: [button("Save"), button("Discard", destructive: true),
                                                        button("Cancel", cancel: true)])))
    try #require(turn { nsWindow.attachedSheet != nil }, "no sheet attached")
    let alert = try #require(appKit.presentedAlert(token: 20))
    alert.buttons[1].performClick(nil)
    try #require(turn { !alertResults(log).isEmpty }, "no answer arrived")
    turns(5)
    #expect(alertResults(log) == [AlertResultEvent(token: 20, button: 1)])
    #expect(nsWindow.attachedSheet == nil)
}

/// **1.8** (`SV-M`). The limits reach `contentMinSize`/`contentMaxSize`, and a
/// window outside them is resized into them, reported through `onResize`;
/// `nil` lifts each.
///
/// Mutation **M1.8**: skip the resize into the limits.
@MainActor
@Test func appKitContentSizeLimitsReachTheWindowAndClampIt() throws {
    let (_, appKit, nsWindow, log) = try hostWindow(width: 300, height: 200)
    defer { tearDown(nsWindow) }
    appKit.setContentSizeLimits(minimum: Size(width: px(400), height: px(300)),
                                maximum: Size(width: px(900), height: px(600)))
    #expect(nsWindow.contentMinSize == NSSize(width: 400, height: 300))
    #expect(nsWindow.contentMaxSize == NSSize(width: 900, height: 600))
    #expect(appKit.contentSize == Size(width: px(400), height: px(300)))
    #expect(log.resizes.last == Size(width: px(400), height: px(300)), "\(log.resizes)")
    appKit.setContentSizeLimits(minimum: nil, maximum: nil)
    #expect(nsWindow.contentMinSize == .zero)
    #expect(nsWindow.contentMaxSize.width >= CGFloat.greatestFiniteMagnitude / 2)
}

/// **1.9** (`SV-N` item 7). The host view's `mouseExited` delivers
/// `.pointerExited`.
///
/// Mutation **M1.9**: drop the override.
@MainActor
@Test func appKitMouseExitedDeliversPointerExited() throws {
    let (_, appKit, nsWindow, log) = try hostWindow()
    defer { tearDown(nsWindow) }
    let event = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
                                                    timestamp: 0, windowNumber: nsWindow.windowNumber,
                                                    context: nil, eventNumber: 0, trackingNumber: 0,
                                                    userData: nil))
    appKit.hostView.mouseExited(with: event)
    let exits = log.events.filter { if case .pointerExited = $0 { true } else { false } }
    #expect(exits.count == 1, "\(log.events)")
}
