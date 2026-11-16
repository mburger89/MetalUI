import Observation

/// One view's selections over a `CodeBuffer` (`CV-AV`). A buffer holds its states weakly and moves every
/// live one on every edit, so two views of one buffer can each have a caret. The buffer's own
/// `selections`, `select(_:reveal:)` and friends are the **default state**, `CodeBuffer.selectionState`;
/// a view with no state of its own uses that one.
///
/// Edits made through a state make it the *acting state*: its selections are recorded in the undo step, it
/// keeps its caret after typed or pasted text, and typing coalesces per state. Every other state follows the
/// text by the AppKit rule (`CV-AW`). `undo()` and `redo()` write the step's selections into the state
/// that called them (`CV-AX`).
@MainActor @Observable
public final class CodeSelectionState {
    @ObservationIgnored private weak var weakBuffer: CodeBuffer?
    @ObservationIgnored private var retainedBuffer: CodeBuffer?
    @ObservationIgnored var stored = [CodeSelection(caret: 0)]

    /// What runs, once, after an edit made through another state completes (`CV-AZ`): a view with marked text
    /// registers one to commit it. Keyed by the view; empty unless an input method is composing, so a frame never
    /// reads it.
    @ObservationIgnored package var foreignEditHandlers: [AnyHashable: @MainActor () -> Void] = [:]

    /// Rises each time `select(_:reveal:)` asks views to scroll this selection into view.
    public private(set) var revealSerial: UInt64 = 0

    /// The `revealSerial` a view has last taken in, and the frame it did so in (`CV-BA`): a view mounting with
    /// `revealSerial` ahead of this, or in that same frame, honours the reveal on its first laid-out frame; any
    /// later mount finds it handled and starts at the top. Never observed: writing it wakes nothing.
    @ObservationIgnored package var revealHandledSerial: UInt64 = 0
    @ObservationIgnored package weak var revealHandledFrame: AnyObject?

    /// A state over `buffer`, selecting `selections` (clamped, sorted and merged; at least one). The buffer
    /// holds it weakly: keep the state alive as long as the view uses it.
    public init(buffer: CodeBuffer, selections: [CodeSelection] = [CodeSelection(caret: 0)]) {
        retainedBuffer = buffer
        weakBuffer = buffer
        stored = CodeBuffer.normalize(selections, limit: buffer.rope.summary.utf8)
        buffer.register(self)
    }

    /// The buffer's own state: it does not retain the buffer, which retains it.
    init(defaultFor buffer: CodeBuffer) {
        weakBuffer = buffer
        buffer.register(self)
    }

    /// The buffer this state selects in.
    public var buffer: CodeBuffer { retainedBuffer ?? weakBuffer! }

    /// The selections, sorted and merged: no two overlap and no two carets coincide, at least one. An
    /// edit moves them; assigning replaces them and ends undo coalescing.
    public var selections: [CodeSelection] {
        get { access(keyPath: \.selections); return stored }
        set {
            let buffer = buffer
            withMutation(keyPath: \.selections) { stored = CodeBuffer.normalize(newValue, limit: buffer.rope.summary.utf8) }
            buffer.breakUndoCoalescing()
        }
    }

    /// The first selection, which views reveal and move.
    public var primarySelection: CodeSelection { selections[0] }

    /// Selects `range` (anchor at its start, head at its end), ending undo coalescing. With `reveal`, the
    /// views using this state scroll it into view: they observe `revealSerial`.
    public func select(_ range: Range<Int>, reveal: Bool = true) {
        selections = [CodeSelection(anchor: range.lowerBound, head: range.upperBound)]
        if reveal { revealSerial &+= 1 }
    }

    /// Replaces every selection of this state with `text`, leaving a caret after each insertion; what
    /// typing and pasting do. This state is the acting state.
    @discardableResult
    public func replaceSelections(with text: String, origin: CodeEditOrigin = .typing) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performReplaceSelections(with: text, origin: origin) }
    }

    /// `CodeBuffer.replace(_:with:origin:)` with this state as the acting state.
    @discardableResult
    public func replace(_ range: Range<Int>, with text: String, origin: CodeEditOrigin = .programmatic) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performReplace(range, with: text, origin: origin) }
    }

    /// `CodeBuffer.transaction(_:)` with this state as the acting state: its selections are the step's.
    @discardableResult
    public func transaction(_ body: (CodeBuffer) -> Void) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performTransaction(body) }
    }

    /// Reverts the buffer's latest undo step (one stack per buffer) and puts the step's before-selections
    /// into **this** state, whichever state made the edit; every other state follows the text. Returns
    /// whether anything was reverted.
    @discardableResult
    public func undo() -> Bool {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performUndo() }
    }

    /// Reapplies the step `undo()` reverted and puts the step's after-selections into this state.
    @discardableResult
    public func redo() -> Bool {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performRedo() }
    }

    /// Replaces the selections without ending coalescing or revealing (a buffer moving a state over an
    /// edit). A state whose selections did not change is not mutated, so its observers do not wake; the
    /// default state is the exception and is always mutated, as the buffer's selection was before states
    /// existed (`versionAndSelectionsAreObservable` pins it).
    func setInternal(_ new: [CodeSelection]) {
        let normalized = CodeBuffer.normalize(new, limit: buffer.rope.summary.utf8)
        guard normalized != stored || retainedBuffer == nil else { return }
        withMutation(keyPath: \.selections) { stored = normalized }
    }
}
