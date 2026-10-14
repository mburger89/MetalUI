import MetalUI
import MetalUIPlatform

// The clipboard read-backs (rulings `CB-K`, `HT-`): a test sends the real
// ⌘C / ⌘V keystroke (`typeKey`) and reads what the window put on its private
// clipboard, or puts there what "another app" copied.

extension TestWindow {
    /// What the window's clipboard holds, most preferred first (`CB-K`): the
    /// representations the last copy, cut or text-field copy wrote. Empty when
    /// nothing was copied.
    public var clipboardRepresentations: [ClipboardRepresentation] { platformWindow.clipboardRepresentations }

    /// Puts `item` on the window's clipboard as another application would
    /// (`Window.clipboard`'s write), without a keystroke. Answers whether it
    /// wrote anything.
    @discardableResult
    public func setClipboard<T: Transferable>(_ item: T) -> Bool { window.clipboard.write(item) }

    /// Puts plain `text` on the window's clipboard, replacing everything else.
    public func setClipboard(text: String) { platformWindow.clipboard = text }
}
