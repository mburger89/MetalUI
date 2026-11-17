import MetalUICore
import MetalUIPlatform

// `ShortcutRecorder` (ruling `KF-AK`; record 366): a field that records the next key chord as a `KeyboardShortcut`.
// Recording is having focus. Built from `@FocusState`, `.focusable`, `.keyCapture()` and `.onKeyPress(phases: .down)`:
// the capture layer hears every key before the keymap, the commands, a `Button`'s shortcut and (on AppKit) the main
// menu, so ⌘Q records instead of quitting. **`interactions: .activate`, not `.edit`, with a press that focuses it**:
// `.edit` makes the element a first-draw seat candidate (`FC-E`), and a settings window would open already recording.

/// What the recorder does with one key press while it records (`KF-AK` item 3). Internal: the whole key table in one
/// pure function the tests also drive.
enum ShortcutRecorderOutcome: Equatable {
    /// Record this shortcut and stop.
    case record(KeyboardShortcut)
    /// Bare Escape: stop without a shortcut.
    case cancel
    /// Bare ⌫ or ⌦: clear the shortcut.
    case clear
    /// Not the recorder's key (bare Tab and ⇧Tab): focus moves on, which cancels.
    case pass

    /// The outcome of `press`, a `.down` (a repeat or a release is never offered here).
    static func of(_ press: KeyPress) -> ShortcutRecorderOutcome {
        let key = press.key
        let modifiers = press.modifiers
        if modifiers.isEmpty {
            if key == .escape { return .cancel }
            if key == .delete || key == .deleteForward { return .clear }
        }
        // AppKit sends ⇧Tab as the backtab character (`KF-AL`).
        let isTab = key == .tab || key.character == "\u{19}"
        if isTab && modifiers.subtracting(.shift).isEmpty { return .pass }
        return .record(KeyboardShortcut(baseKey(of: press), modifiers: modifiers))
    }

    /// The one form a recorded key has on every platform (Alloy's binding answer 3, `KF-AL`): the unshifted base key
    /// lower-cased when Shift is held (`"/"`, not AppKit's `"?"`), else the key lower-cased; ⇧Tab's `"\u{19}"` is `"\t"`.
    private static func baseKey(of press: KeyPress) -> KeyEquivalent {
        if press.key.character == "\u{19}" { return .tab }
        if press.modifiers.contains(.shift), let base = press.unshiftedKey.first {
            return KeyEquivalent(Character(String(base).lowercased()))
        }
        return KeyEquivalent(Character(String(press.key.character).lowercased()))
    }
}

/// Whether a key already reported the end of the recording in progress (`ShortcutRecorder`'s one piece of state that
/// is not read by `content`).
private final class RecordingEnd {
    var reported = false
}

/// The recorder's content, internal so the public ``ShortcutRecorder`` can wrap it in `.equatable()` itself (`KF-AK`
/// item 10): `Equatable` over the shortcut and the label, closures not compared. It holds the `@State`, the
/// `@FocusState` and the environment read, so a recording starting or ending re-evaluates it as a state change.
struct ShortcutRecorderField: Component, @MainActor Equatable {
    var shortcut: KeyboardShortcut?
    var onRecord: @MainActor (KeyboardShortcut) -> Void
    var onClear: @MainActor () -> Void
    var onCancel: @MainActor () -> Void
    var label = "Shortcut"
    /// Whether the end of this recording was already reported (a key ended it), so the focus loss it causes is not a
    /// cancel. A class held in `@State` so that writing it never re-renders the recorder (`content` does not read it):
    /// written from the key handler, read and reset when focus changes.
    @State private var ended = RecordingEnd()
    @FocusState private var isRecording: Bool
    @Environment(\.controlActiveState) private var activeState

    /// A recorder showing `shortcut`, or "Record Shortcut" when it is `nil`.
    ///
    /// - Parameters:
    ///   - shortcut: The current shortcut.
    ///   - onRecord: Runs with the chord recorded, in the one form `KF-AK` describes; the recorder has already resigned focus.
    ///   - onClear: Runs on a bare ⌫ or ⌦.
    ///   - onCancel: Runs once when recording ends with no key: bare Escape, focus lost or the window resigning key.
    init(_ shortcut: KeyboardShortcut?,
                onRecord: @escaping @MainActor (KeyboardShortcut) -> Void,
                onClear: @escaping @MainActor () -> Void,
                onCancel: @escaping @MainActor () -> Void) {
        self.shortcut = shortcut
        self.onRecord = onRecord
        self.onClear = onClear
        self.onCancel = onCancel
    }

    /// Replaces the accessibility label, "Shortcut" by default (SwiftUI's `accessibilityLabel(_:)` spelling).
    func accessibilityLabel(_ label: String) -> ShortcutRecorderField {
        var copy = self
        copy.label = label
        return copy
    }

    /// Two recorders are equal when they show the same shortcut under the same label. The closures are not compared.
    static func == (lhs: ShortcutRecorderField, rhs: ShortcutRecorderField) -> Bool {
        lhs.shortcut == rhs.shortcut && lhs.label == rhs.label
    }

    /// The field's content. Not for callers.
    var content: some ElementGroup {
        let recording = isRecording, shortcut = shortcut, label = label
        let ended = ended, focus = $isRecording
        let onRecord = onRecord, onClear = onClear, onCancel = onCancel
        let text: String
        let ink: Color
        if recording {
            text = "Press Shortcut"; ink = .secondary
        } else if let shortcut {
            text = shortcut.displayText; ink = Color(.textPrimary)
        } else {
            text = "Record Shortcut"; ink = .secondary
        }
        let value = recording ? "Press Shortcut" : (shortcut?.displayText ?? "None")
        let accent = (activeState == .key) ? Color(.accent) : Color(.separator)
        let inset = Edges<Length>(top: .pixels(Pixels(0)), right: .pixels(Pixels(8)), bottom: .pixels(Pixels(0)),
                                  left: .pixels(Pixels(8)))
        return Box { Text(text).font(size: 12).foregroundColor(ink).lineLimit(1).padding(inset) }
            .alignItems(.center)
            .justifyContent(.center)
            .background(Color(.surfaceSecondary))
            .cornerRadius(Pixels(5))
            .border(Color(.separator), width: Pixels(1))
            .focusBorder(accent, width: Pixels(2))
            .frame(minWidth: Pixels(96), minHeight: Pixels(22), maxHeight: Pixels(22))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { focus.wrappedValue = true }
            .onClick { focus.wrappedValue = true }
            .focusable(interactions: .activate)
            .focused(focus)
            .keyCapture()
            .onKeyPress(phases: .down) { press in
                switch ShortcutRecorderOutcome.of(press) {
                case .pass:
                    return .ignored
                case .cancel:
                    ended.reported = true
                    focus.wrappedValue = false
                    onCancel()
                case .clear:
                    ended.reported = true
                    focus.wrappedValue = false
                    onClear()
                case .record(let recorded):
                    ended.reported = true
                    focus.wrappedValue = false
                    onRecord(recorded)
                }
                return .handled
            }
            .onChange(of: recording) { _, nowRecording in
                if nowRecording { ended.reported = false; return }
                if ended.reported { ended.reported = false } else { onCancel() }
            }
            .onChange(of: activeState) { _, state in
                if state != .key, focus.wrappedValue { focus.wrappedValue = false }
            }
    }
}


/// A field that records a keyboard shortcut: press it (or Tab to it, or activate it with an accessibility client) and
/// the next chord is reported (`KF-AK`; MetalUI-only, class M). It mirrors macOS's shortcut fields (System Settings
/// ▸ Keyboard Shortcuts, Xcode's Key Bindings).
///
/// ```swift
/// ShortcutRecorder(binding,
///                  onRecord: { binding = $0 },
///                  onClear: { binding = nil },
///                  onCancel: { })
///     .equatable()
/// ```
///
/// **Recording is having focus.** A primary press, Tab, or an accessibility activate focuses it; losing focus (a press
/// elsewhere, Tab, the window resigning key) ends it. While it records:
/// - Any key with a non-empty key is **recorded**: `onRecord` runs with a `KeyboardShortcut` in one form on every
///   platform, the unshifted base key lower-cased plus the modifiers held (`⇧/` is `"/"` with `.shift`, not `"?"`;
///   ⇧Tab is `"\t"` with `.shift`), and the recorder gives up focus. **Nothing is validated**: plain letters record
///   too, and the app decides what it accepts.
/// - **Escape** alone calls `onCancel`; **⌫ or ⌦** alone calls `onClear` (both, because Windows names the forward-delete
///   key "Delete"). With a modifier, Escape and Delete record like any other key.
/// - **Tab and ⇧Tab alone are not taken**: focus moves on, which is a cancel. ⌃Tab and ⌥Tab record.
/// - Key repeats, releases and modifier-only presses are ignored, and so is every key while an input method composes.
/// - **`onCancel` runs once** when focus is lost or the window stops being key without a key having ended the recording,
///   and never after `onRecord` or `onClear`.
///
/// **The app does not hear the key.** The capture runs before the menu bar, `CommandMenu` items and `Button` shortcuts,
/// so ⌘Q records instead of quitting and a ⌘K item does not run. The system takes some keys first and the recorder
/// never sees them (⌘Tab, ⌘Space on a Mac; Super+L on GNOME; Alt+F4 on Windows).
///
/// **Look.** A rounded field 22 points tall and at least 96 wide, `.surfaceSecondary` fill, a `.separator` hairline
/// and the controls' focus ring while it records. It shows the shortcut's ``KeyboardShortcut/displayText``, "Record
/// Shortcut" in `.secondary` when there is none, and "Press Shortcut" while recording.
///
/// **Accessibility.** A button labelled "Shortcut" (``accessibilityLabel(_:)`` replaces it) whose value is the display
/// text, "None" or "Press Shortcut"; activating it starts recording.
///
/// The recorder is `Equatable` over the shortcut and the label, so `.equatable()` replays it while they are unchanged;
/// **the closures are not compared**, as ``TabStrip``'s are not: a handler that captures changing state should read it
/// from a model, not capture a copy.
///
/// **Idle, it costs nothing extra on a rebuilt frame without the caller adding `.equatable()`**: the public type is a
/// thin component whose content is the internal field under `.equatable()`, so the field's content is skipped and its
/// paint replayed while the shortcut and label are unchanged. A recording starting or ending is the field's own
/// `@FocusState` change and re-evaluates it.
public struct ShortcutRecorder: Component, @MainActor Equatable {
    var field: ShortcutRecorderField

    /// A recorder showing `shortcut`, or "Record Shortcut" when it is `nil`.
    ///
    /// - Parameters:
    ///   - shortcut: The current shortcut.
    ///   - onRecord: Runs with the chord recorded, in the one form `KF-AK` describes; the recorder has already resigned focus.
    ///   - onClear: Runs on a bare ⌫ or ⌦.
    ///   - onCancel: Runs once when recording ends with no key: bare Escape, focus lost or the window resigning key.
    public init(_ shortcut: KeyboardShortcut?,
                onRecord: @escaping @MainActor (KeyboardShortcut) -> Void,
                onClear: @escaping @MainActor () -> Void,
                onCancel: @escaping @MainActor () -> Void) {
        field = ShortcutRecorderField(shortcut, onRecord: onRecord, onClear: onClear, onCancel: onCancel)
    }

    /// Replaces the accessibility label, "Shortcut" by default (SwiftUI's `accessibilityLabel(_:)` spelling).
    public func accessibilityLabel(_ label: String) -> ShortcutRecorder {
        var copy = self
        copy.field.label = label
        return copy
    }

    /// Two recorders are equal when they show the same shortcut under the same label. The closures are not compared.
    public static func == (lhs: ShortcutRecorder, rhs: ShortcutRecorder) -> Bool { lhs.field == rhs.field }

    /// The field under `.equatable()`. Not for callers.
    public var content: some ElementGroup { field.equatable() }
}
