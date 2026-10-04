#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import MetalUICore
import MetalUIPlatform

// File dialogs, alerts and size limits on AppKit (rulings `SV-F`, `SV-J` item
// 1, `SV-M`, `SV-X`; spec
// `docs/superpowers/specs/2026-10-04-platform-services-design.md` §4.1). Every
// presentation is a **sheet on the window** — the probe's `D1`/`X1`
// (`attachedSheet=NSOpenPanel modalWindow=nil isSheet=true`) and `A1`
// (`_NSAlertPanel`) — and every answer is queued onto `onInput` with
// `RunLoop.main.perform` after AppKit's completion handler returns, never
// inside it (`SV-B` item 2, `MN-C` item 4's reason).

/// A sheet `AppKitWindow` began and has not yet answered (rulings `SV-F`,
/// `SV-J`).
@MainActor
final class AppKitPresentation {
    /// The panel or alert.
    enum Sheet {
        case fileDialog(NSSavePanel)
        case alert(NSAlert)
    }

    let sheet: Sheet
    /// Set by `dismissPresentation(token:)`: the completion that follows the
    /// `.abort` it sends answers nothing.
    var isSuppressed = false

    init(_ sheet: Sheet) { self.sheet = sheet }

    /// The sheet's window, as `NSWindow.attachedSheet` reports it.
    var window: NSWindow {
        switch sheet {
        case .fileDialog(let panel): panel
        case .alert(let alert): alert.window
        }
    }
}

extension AppKitWindow {
    /// Shows `dialog` as an `NSOpenPanel` (files only, `allowsMultipleSelection`
    /// as asked) or an `NSSavePanel` (the name field `defaultFilename`, its
    /// extension hidden, `title`/`prompt` from the seam) **sheet** on this
    /// window, filtered by `allowedContentTypes` (ruling `SV-F`, `SV-E`'s
    /// mapping), and answers `true`; the outcome — the chosen URLs' paths,
    /// or a cancel — is queued as `.fileDialogResult`. `false` while a sheet
    /// is already attached: AppKit shows one at a time.
    func presentFileDialog(_ dialog: PlatformFileDialog) -> Bool {
        guard window.attachedSheet == nil else { return false }
        let panel: NSSavePanel
        switch dialog.kind {
        case .open(let allowsMultipleSelection):
            let open = NSOpenPanel()
            open.canChooseFiles = true
            open.canChooseDirectories = false
            open.allowsMultipleSelection = allowsMultipleSelection
            panel = open
        case .save(let defaultFilename):
            panel = NSSavePanel()
            if let defaultFilename { panel.nameFieldStringValue = defaultFilename }
            panel.isExtensionHidden = true
        }
        panel.allowedContentTypes = Self.contentTypes(dialog.allowedTypes)
        if let title = dialog.title { panel.title = title }
        if let prompt = dialog.prompt { panel.prompt = prompt }
        let presentation = AppKitPresentation(.fileDialog(panel))
        presentations[dialog.token] = presentation
        let token = dialog.token
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                let paths = response == .OK ? Self.paths(of: panel) : []
                let outcome: FileDialogResultEvent.Outcome = paths.isEmpty ? .cancelled : .chosen(paths)
                self.answer(token: token) { .fileDialogResult(FileDialogResultEvent(token: token, outcome: outcome)) }
                self.onSheetCompletionForTesting?()
            }
        }
        return true
    }

    /// The chosen files' paths: every URL of an open panel, the one of a save
    /// panel.
    private static func paths(of panel: NSSavePanel?) -> [String] {
        guard let panel else { return [] }
        if let open = panel as? NSOpenPanel { return open.urls.map(\.path) }
        return panel.url.map { [$0.path] } ?? []
    }

    /// The seam's types as `UTType`s (ruling `SV-E`): the system's type for a
    /// known identifier, else one declared from the first extension, else
    /// nothing. A list holding `public.data` or `public.item` — or one that
    /// resolves to nothing — allows every file (`[]`).
    nonisolated static func contentTypes(_ types: [PlatformFileType]) -> [UTType] {
        if types.contains(where: { $0.identifier == "public.data" || $0.identifier == "public.item" }) { return [] }
        return types.compactMap { type in
            UTType(type.identifier)
                ?? type.filenameExtensions.first.flatMap { UTType(filenameExtension: $0, conformingTo: .data) }
        }
    }

    /// Shows `alert` as an `NSAlert` sheet (ruling `SV-J` item 1): the buttons
    /// added in the seam's order — NSAlert lays two side by side with the
    /// first on the right and stacks three or more top-down, `A1`'s
    /// Cancel-left and `A5`'s Save-top — and the key equivalents set
    /// **explicitly**: `"\r"` on the default button only, `"\u{1b}"` on the
    /// cancel button only, none on any other (`SV-X`: NSAlert's own would give
    /// its first button Return, which `A1`/`A5` refute). A destructive button
    /// is marked `hasDestructiveAction`. The pressed button's **index** is
    /// queued as `.alertResult`. `false` while a sheet is attached.
    func presentAlert(_ alert: PlatformAlert) -> Bool {
        guard window.attachedSheet == nil else { return false }
        let nsAlert = NSAlert()
        nsAlert.messageText = alert.title
        nsAlert.informativeText = alert.message ?? ""
        for button in alert.buttons {
            nsAlert.addButton(withTitle: button.title).hasDestructiveAction = button.isDestructive
        }
        let presentation = AppKitPresentation(.alert(nsAlert))
        presentations[alert.token] = presentation
        let token = alert.token, count = alert.buttons.count
        nsAlert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                let button = (0..<count).contains(index) ? index : nil
                self.answer(token: token) { .alertResult(AlertResultEvent(token: token, button: button)) }
                self.onSheetCompletionForTesting?()
            }
        }
        // After the sheet began: NSAlert re-derives its buttons' key
        // equivalents when it lays itself out for the sheet (measured: a
        // `"\r"` set while adding the buttons read `""` once attached), so
        // the seam's roles are applied last.
        for (button, spec) in zip(nsAlert.buttons, alert.buttons) {
            button.keyEquivalent = spec.isDefault ? "\r" : (spec.isCancel ? "\u{1b}" : "")
        }
        return true
    }

    /// The sheet `token` names, if it is an alert still shown — for tests.
    func presentedAlert(token: Int) -> NSAlert? {
        guard case .alert(let alert)? = presentations[token]?.sheet else { return nil }
        return alert
    }

    /// Forgets `token`'s presentation and, unless it was dismissed, queues
    /// `event` onto `onInput` for after AppKit's completion handler returns
    /// (`SV-B` item 2) — in every run-loop mode, so a modal session elsewhere
    /// does not hold it.
    private func answer(token: Int, _ event: @escaping @MainActor () -> InputEvent) {
        let suppressed = presentations.removeValue(forKey: token)?.isSuppressed ?? true
        guard !suppressed else { return }
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated { _ = self?.onInput?(event()) }
        }
    }

    /// Ends the sheet `token` names with `.abort` and suppresses its answer
    /// (ruling `SV-F`). Nothing when the token names nothing shown.
    func dismissPresentation(token: Int) {
        guard let presentation = presentations[token] else { return }
        presentation.isSuppressed = true
        window.endSheet(presentation.window, returnCode: .abort)
    }

    /// Sets `contentMinSize`/`contentMaxSize` — `nil` as `.zero` / the largest
    /// finite size — and resizes a window lying outside them into them
    /// (ruling `SV-M`): AppKit does not clamp an existing window to new
    /// limits on its own, while `setContentSize` of the clamped size reaches
    /// `onResize` through the host view's `setFrameSize`.
    func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {
        let minSize = minimum.map { NSSize(width: CGFloat($0.width.value), height: CGFloat($0.height.value)) } ?? .zero
        let maxSize = maximum.map { NSSize(width: CGFloat($0.width.value), height: CGFloat($0.height.value)) }
            ?? NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.contentMinSize = minSize
        window.contentMaxSize = maxSize
        let current = hostView.bounds.size
        let clamped = NSSize(width: min(max(current.width, minSize.width), maxSize.width),
                             height: min(max(current.height, minSize.height), maxSize.height))
        if clamped != current { window.setContentSize(clamped) }
    }
}
#endif
