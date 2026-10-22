import AppKit
import MetalUIPlatform

// Clipboard change notification (ruling `CP-G`). `NSPasteboard` posts nothing, so the window compares
// `changeCount` (an `Int`) at the points a foreign write could first matter: the window becoming key, a
// mouse-down, a key-down, and after its own write. A manager rewriting the pasteboard while the window
// is key and idle shows at the next press (the named residue).

extension AppKitWindow {
    /// Records the count after an own write and tells the handler (`CP-G`).
    func noteClipboardWrite() {
        lastClipboardChangeCount = pasteboard.changeCount
        clipboardChangeHandler?()
    }

    /// Calls the handler when `changeCount` differs from the last one seen; never otherwise, and
    /// nothing while no handler is installed.
    func pollClipboardChange() {
        guard let handler = clipboardChangeHandler, let last = lastClipboardChangeCount else { return }
        let count = pasteboard.changeCount
        guard count != last else { return }
        lastClipboardChangeCount = count
        handler()
    }
}
