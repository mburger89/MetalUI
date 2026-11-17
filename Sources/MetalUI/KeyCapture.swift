import MetalUICore
import MetalUIPlatform

// `keyCapture(except:optionAsMeta:)`'s window stage (rulings `TRM-U`..`TRM-Y`, `TRM-D`; record 338). The capture
// state is a field of `KeyboardAttachment` (`KeyPress.swift`), registered per id in `FocusRegistry`.

extension Window {
    /// Whether the focused text target is composing marked text: a field's stored composition or a code
    /// view's session (`TRM-V`). Nothing is captured then — the key belongs to the input method.
    var isComposingMarkedText: Bool {
        guard let id = focusedElement, let target = lastFocusRegistry.textTarget(for: id) else { return false }
        if let session = target.codeSession { return session.isComposing }
        return !editState(id).composition.text.isEmpty
    }

    /// Offers a key event to the capture layers on the focus chain, outermost first, each layer's handlers
    /// last-written first (`KF-C`), before every other key stage (`TRM-U`). A layer whose `except` matches the
    /// key is skipped (`TRM-V`); every layer offered is remembered so `onKeyPress`'s own stage does not offer
    /// the same handlers again after `.ignored`.
    func dispatchKeyCapture(_ event: InputEvent) -> Bool {
        keyCaptureOffered = []
        guard lastFocusRegistry.keyCaptureCount > 0, focusedElement != nil else { return false }
        let key: KeyEvent
        let phase: KeyPress.Phases
        switch event {
        case .keyDown(let down): key = down; phase = down.isRepeat ? .repeat : .down
        case .keyUp(let up): key = up; phase = .up
        default: return false
        }
        guard let first = key.charactersIgnoringModifiers.first, !isComposingMarkedText else { return false }
        let press = KeyPress(phase: phase, key: KeyEquivalent(first), characters: key.characters,
                             modifiers: key.modifiers, unshiftedKey: key.unshiftedKey)
        for id in focusChain.reversed() {
            guard let capture = lastFocusRegistry.keyCapture(for: id),
                  !capture.exceptions.contains(where: { $0.matches(key) }) else { continue }
            keyCaptureOffered.insert(id)
            for handler in lastFocusRegistry.keyPresses(for: id).reversed() where handler.accepts(press) {
                if StateDispatch.dispatching(to: id, { handler.action(press) }) == .handled { return true }
            }
        }
        return false
    }

    /// Sends `PlatformWindow.setRawOptionKeys(_:)` when the focus chain's capture layers say Option should (or
    /// no longer should) act as meta (`TRM-X`): true while any capture layer on the chain asks for it.
    func syncRawOptionKeys() {
        var wanted = false
        if lastFocusRegistry.keyCaptureCount > 0, focusedElement != nil {
            wanted = focusChain.contains { lastFocusRegistry.keyCapture(for: $0)?.optionAsMeta == true }
        }
        guard wanted != sentRawOptionKeys else { return }
        sentRawOptionKeys = wanted
        platformWindow.setRawOptionKeys(wanted)
    }
}
