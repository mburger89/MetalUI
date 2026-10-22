import MetalUIPlatform

// A clipboard change reaches the window (rulings `CP-G`, `CP-M`).

extension Window {
    /// The platform's change handler: the next `PasteButton` read of the clipboard goes to the platform
    /// again, and the window redraws **only when the last build held a `PasteButton`**, so a window
    /// without one costs nothing (`IF-N`'s shape).
    func clipboardDidChange() {
        clipboardAccess.invalidate()
        if lastPasteButtonCount > 0 { setNeedsRedraw() }
    }
}

extension Window {
    /// How many times a `PasteButton` made the window read the platform's clipboard types (`CP-M`): a pin
    /// counts work. `package` for `MetalUITesting`'s tests.
    package var testingClipboardReads: Int { clipboardAccess.reads }
}
