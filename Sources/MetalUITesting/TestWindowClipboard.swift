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

    /// Puts `items` on the window's clipboard as another application would, one clipboard item each
    /// (`CP-E`), replacing everything; answers whether it wrote anything. Each item is encoded now.
    @discardableResult
    public func setClipboard<T: Transferable>(items: [T]) -> Bool {
        platformWindow.writeClipboard(items: items.compactMap { $0.clipboardItem() })
    }

    /// Puts `items` on the window's clipboard as they are, `.later` representations included.
    @discardableResult
    public func setClipboard(items: [ClipboardItem]) -> Bool { platformWindow.writeClipboard(items: items) }

    /// The type identifiers of each item on the window's clipboard (`CP-E`).
    public var clipboardItems: [[String]] { platformWindow.clipboardItems() }

    /// How many `.later` clipboard representations have been exported (`CP-F`).
    public var clipboardExportCount: Int { platformWindow.clipboardExportCount }

    /// Puts plain `text` on the window's clipboard, replacing everything else.
    public func setClipboard(text: String) { platformWindow.clipboard = text }
}
