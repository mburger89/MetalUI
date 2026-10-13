import MetalUI
import MetalUIPlatform

// The input-method driver (spec 2026-10-12, rulings `IM-A`…`IM-D`): verbs beside
// `typeText` that deliver the events the two real platforms deliver for an input
// method, through `onInput` — `Window.editedText`, `TextEditing.compose` and
// `TextEditing.insert` run unmodified. A verb with no text field holding the
// caret sends nothing and answers `false` (`IM-C`).

extension TestWindow {
    /// Marked text of an input method, as `NSTextInputClient.setMarkedText` and
    /// SDL's non-empty `TEXT_EDITING` deliver it: the focused field shows `text`
    /// underlined at its caret and the binding is not written. `selectedRange` is
    /// in Character offsets of `text` (`nil`: a caret at its end) and is clamped
    /// to it. Then one frame. Answers `false`, sending nothing, when no text
    /// field has the caret or `text` is empty (use ``cancelMarkedText()``).
    @discardableResult
    public func setMarkedText(_ text: String, selectedRange: Range<Int>? = nil) -> Bool {
        guard isTextInputActive, !text.isEmpty else { return false }
        let count = text.count
        let range = selectedRange ?? count..<count
        let lower = min(max(range.lowerBound, 0), count)
        let upper = min(max(range.upperBound, lower), count)
        send(.textComposition(TextComposition(text: text, selection: lower..<upper)))
        tick()
        return true
    }

    /// AppKit's `unmarkText`: the marked text as it stands becomes the committed
    /// text (`.textInput(<marked text>)`). Then one frame. Answers `false`,
    /// sending nothing, when nothing is marked.
    @discardableResult
    public func commitMarkedText() -> Bool {
        guard isTextInputActive, !markedText.isEmpty else { return false }
        send(.textInput(markedText))
        tick()
        return true
    }

    /// AppKit's `insertText`: `text` — the candidate the input method chose —
    /// replaces the marked text and is committed. Then one frame. Answers
    /// `false`, sending nothing, when no text field has the caret.
    @discardableResult
    public func commitMarkedText(_ text: String) -> Bool {
        guard isTextInputActive else { return false }
        send(.textInput(text))
        tick()
        return true
    }

    /// SDL's empty `TEXT_EDITING`: the composition ends and nothing is committed;
    /// the field shows its text and selection as before. Then one frame. Answers
    /// `false`, sending nothing, when no text field has the caret.
    @discardableResult
    public func cancelMarkedText() -> Bool {
        guard isTextInputActive else { return false }
        send(.textComposition(.none))
        tick()
        return true
    }

    /// The focused field's marked text as the window holds it, `""` when none
    /// (or nothing focused, or the focus is not a text field).
    public var markedText: String { window.testingComposition?.text ?? "" }

    /// The selection within ``markedText`` in Character offsets, `nil` when none.
    public var markedSelection: Range<Int>? { window.testingComposition?.selection }
}
