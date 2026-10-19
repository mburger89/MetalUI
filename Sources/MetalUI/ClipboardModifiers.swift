import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform

// `copyable`, `cuttable`, `pasteDestination` (rulings `CB-A`, `CB-B`, `CB-C`,
// `CB-F`, `CB-G`, `CB-M`): SwiftUI's spellings over MetalUI's synchronous
// `Transferable`, on every `StyledElement` and, once, on proposal content (the
// `KeyboardModifier` layer, `KF-H`). Each hangs a `ClipboardAttachment` on the
// element's `KeyboardAttachment`; `Window.dispatchClipboardKey` runs it.

extension StyledElement {
    /// Makes this element offer `items` to the clipboard on Copy — SwiftUI's
    /// `copyable(_:)` (ruling `CB-A`).
    ///
    /// **Routing** (`CB-B`): the primary modifier (⌘ on Apple, Ctrl elsewhere)
    /// with `C`, and the Edit menu's Copy, reach the handler of the element that
    /// **holds focus or is an ancestor of the focused element**, innermost first.
    /// It does not make the element focusable (`focusable()`; a click does not
    /// focus, divergence 94). It runs after the `Keymap`, `onKeyPress`, a
    /// focused text field's own editing keys and `onKey`, and before a `Button`'s
    /// shortcut and the app's commands, so a focused `TextField` keeps its own
    /// copy (`CB-M`). `items` is evaluated at copy time; only its **first** item
    /// is written (divergence 456), as one representation per type it exports,
    /// so list `.utf8PlainText` after your own type for a text fallback. An empty
    /// result writes nothing and leaves the key to later stages. Menu enablement
    /// is by presence of the handler (divergence 455).
    public func copyable<T: Transferable>(_ items: @autoclosure @escaping () -> [T]) -> Self {
        handling { $0.keyboard = KeyboardAttachment.clipboard(
            ClipboardAttachment.copying(items, over: $0.keyboard?.clipboard), over: $0.keyboard) }
    }

    /// Makes this element cut to the clipboard — SwiftUI's `cuttable(for:action:)`.
    /// `action` runs once, from input, removes the items from the app's model and
    /// returns them; the first is written as `copyable` writes (`CB-C`). Routing
    /// and enablement as `copyable(_:)`. The key is claimed once `action` has
    /// run, even when it returned nothing.
    public func cuttable<T: Transferable>(for payloadType: T.Type = T.self,
                                          action: @escaping @MainActor () -> [T]) -> Self {
        handling { $0.keyboard = KeyboardAttachment.clipboard(
            ClipboardAttachment.cutting(action, over: $0.keyboard?.clipboard), over: $0.keyboard) }
    }

    /// Makes this element accept a paste of `T` — SwiftUI's
    /// `pasteDestination(for:action:validator:)`.
    ///
    /// The clipboard is read as one item through `T.importedContentTypes()` in
    /// its order (`CB-F`), so a type importing `[custom, .utf8PlainText]` falls
    /// back to text. `validator` runs on the imported value; an empty result
    /// **declines** and `action` receives at most one value (divergence 456). When
    /// nothing imports, the key is declined and later stages run (an app command's
    /// Paste). Routing as `copyable(_:)`. The Edit menu's Paste is enabled by
    /// presence of the handler, not by the validator (`CB-G`, divergence 455).
    public func pasteDestination<T: Transferable>(for payloadType: T.Type = T.self,
                                                  action: @escaping @MainActor ([T]) -> Void,
                                                  validator: @escaping @MainActor ([T]) -> [T] = { $0 }) -> Self {
        handling { $0.keyboard = KeyboardAttachment.clipboard(
            ClipboardAttachment.pasting(payloadType, action: action, validator: validator,
                                        over: $0.keyboard?.clipboard), over: $0.keyboard) }
    }
}

extension ProposalElementGroup {
    /// `StyledElement.copyable(_:)` on the proposal path: wraps once in a
    /// `KeyboardModifier`; a later keyboard modifier joins the same layer (`KF-H`).
    public func copyable<T: Transferable>(_ items: @autoclosure @escaping () -> [T]) -> KeyboardModifier<Self> {
        KeyboardModifier(content: self, handlers: Handlers()).copyable(items())
    }

    /// `StyledElement.cuttable(for:action:)` on the proposal path: wraps once in a
    /// `KeyboardModifier`.
    public func cuttable<T: Transferable>(for payloadType: T.Type = T.self,
                                          action: @escaping @MainActor () -> [T]) -> KeyboardModifier<Self> {
        KeyboardModifier(content: self, handlers: Handlers()).cuttable(for: payloadType, action: action)
    }

    /// `StyledElement.pasteDestination(for:action:validator:)` on the proposal
    /// path: wraps once in a `KeyboardModifier`.
    public func pasteDestination<T: Transferable>(for payloadType: T.Type = T.self,
                                                  action: @escaping @MainActor ([T]) -> Void,
                                                  validator: @escaping @MainActor ([T]) -> [T] = { $0 }) -> KeyboardModifier<Self> {
        KeyboardModifier(content: self, handlers: Handlers())
            .pasteDestination(for: payloadType, action: action, validator: validator)
    }
}

extension KeyboardModifier {
    /// Adds `copyable(_:)` to this layer — `Self`, so the chain stays one layer.
    public func copyable<T: Transferable>(_ items: @autoclosure @escaping () -> [T]) -> Self {
        var copy = self
        copy.handlers.keyboard = KeyboardAttachment.clipboard(
            ClipboardAttachment.copying(items, over: copy.handlers.keyboard?.clipboard), over: copy.handlers.keyboard)
        return copy
    }

    /// Adds `cuttable(for:action:)` to this layer.
    public func cuttable<T: Transferable>(for payloadType: T.Type = T.self,
                                          action: @escaping @MainActor () -> [T]) -> Self {
        var copy = self
        copy.handlers.keyboard = KeyboardAttachment.clipboard(
            ClipboardAttachment.cutting(action, over: copy.handlers.keyboard?.clipboard), over: copy.handlers.keyboard)
        return copy
    }

    /// Adds `pasteDestination(for:action:validator:)` to this layer.
    public func pasteDestination<T: Transferable>(for payloadType: T.Type = T.self,
                                                  action: @escaping @MainActor ([T]) -> Void,
                                                  validator: @escaping @MainActor ([T]) -> [T] = { $0 }) -> Self {
        var copy = self
        copy.handlers.keyboard = KeyboardAttachment.clipboard(
            ClipboardAttachment.pasting(payloadType, action: action, validator: validator,
                                        over: copy.handlers.keyboard?.clipboard), over: copy.handlers.keyboard)
        return copy
    }
}

// MARK: - Dispatch

extension Window {
    /// The clipboard stage (ruling `CB-B`): primary + C/X/V to the innermost
    /// handler on the focus chain, after `dispatchKey` and before the
    /// context-menu key, shortcuts and commands. `false` (declined) when no
    /// handler of that kind is on the chain, a copy has nothing to write or a
    /// paste imports nothing (`CB-F`).
    func dispatchClipboardKey(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event, lastFocusRegistry.clipboardRegionCount > 0,
              key.modifiers == .primary else { return false }
        let letter = key.charactersIgnoringModifiers.lowercased()
        guard letter == "c" || letter == "x" || letter == "v" else { return false }
        let chain = focusChain
        let clipboard = self.clipboard
        for id in chain {
            guard let attachment = lastFocusRegistry.clipboardHandler(for: id) else { continue }
            switch letter {
            case "c":
                guard let copy = attachment.copy else { continue }
                let representations = StateDispatch.dispatching(to: id) { copy() }
                guard !representations.isEmpty else { return false }
                _ = platformWindow.writeClipboard(representations)
                return true
            case "x":
                guard let cut = attachment.cut else { continue }
                let representations = StateDispatch.dispatching(to: id) { cut() }
                if !representations.isEmpty { _ = platformWindow.writeClipboard(representations) }
                return true
            default:
                guard let paste = attachment.paste else { continue }
                let item = clipboard.item
                return StateDispatch.dispatching(to: id) { paste(item) }
            }
        }
        return false
    }

    /// What the focus chain can do with the clipboard now (`CB-G`).
    var chainClipboardCommands: ClipboardCommands {
        var result: ClipboardCommands = []
        for id in focusChain {
            if let attachment = lastFocusRegistry.clipboardHandler(for: id) { result.formUnion(attachment.commands) }
        }
        return result
    }

    /// Tells the platform what the focus chain can do, on change only (`CB-E`).
    func updateClipboardCommands() {
        let commands = chainClipboardCommands
        guard commands != lastClipboardCommands else { return }
        lastClipboardCommands = commands
        platformWindow.setClipboardCommands(commands)
    }
}
