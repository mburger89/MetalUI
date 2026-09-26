import MetalUICore
import MetalUIPlatform

/// What an `onClick` may know about the click it is running for, and ask of
/// the window afterwards (ruling `DD-Z` item 9; spec
/// `2026-09-26-controls-and-selection-design.md` §6). **Internal, with one
/// consumer** — a selectable `List`'s rows, which select by modifier and focus
/// their list — and **not a gesture API**: a public tap-with-modifiers is
/// gesture composition, plan task 12 (`DD-AC`'s rejected attack).
///
/// **Set only while `Window` runs a click handler**, through
/// `running(modifiers:_:)`: a mouse click's handler reads the completing
/// mouse-up's modifiers; an accessibility `.press` reads `[]`; anything else —
/// a key handler, a phase — reads `[]`. The window then passes a set
/// `focusRequest` to `Window.focus(_:)` and clears it, so a handler may focus
/// something without holding the window (a handler that captured it would be
/// a retain cycle, CLAUDE.md "Hit testing"). A request naming an id that is not
/// focusable is cleared at the next frame boundary, as any `focus(_:)` of one
/// is (`Frame.resolveFocus`).
@MainActor
enum ClickDispatch {
    /// The completing mouse event's modifiers while a click handler runs;
    /// `[]` otherwise.
    private(set) static var modifiers: Modifiers = []

    /// Set by a click handler to have the window focus an id after it returns.
    static var focusRequest: GlobalElementID?

    /// Runs `body` with `modifiers` published, and returns the focus request it
    /// left, cleared. Both are reset even if `body` throws.
    static func running(modifiers: Modifiers, _ body: () -> Void) -> GlobalElementID? {
        let outerModifiers = self.modifiers
        self.modifiers = modifiers
        focusRequest = nil
        defer {
            self.modifiers = outerModifiers
            focusRequest = nil
        }
        body()
        return focusRequest
    }
}
