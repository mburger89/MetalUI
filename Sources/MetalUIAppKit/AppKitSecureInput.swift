#if os(macOS)
import AppKit
import Carbon.HIToolbox
import MetalUICore
import MetalUIPlatform

/// macOS's secure keyboard entry for `SecureField` (ruling `SCF-B`): Carbon's `EnableSecureEventInput()` while a
/// secure field is focused in a key window, `DisableSecureEventInput()` when focus leaves, the window resigns key or
/// closes, or the field is removed. Carbon counts nested enables itself, so every `acquire()` is matched by exactly one
/// `release()` and a `release()` with nothing held does nothing — the count is what keeps a double blur or a close after
/// a blur from disabling another window's hold. The calls are injectable so a test records them instead of toggling the
/// system's state.
@MainActor
final class SecureEventInput {
    /// The process's one counter.
    static let shared = SecureEventInput(enable: { _ = EnableSecureEventInput() },
                                         disable: { _ = DisableSecureEventInput() })

    private let enable: () -> Void
    private let disable: () -> Void
    /// Holds taken and not yet released.
    private(set) var held = 0
    /// `enable` calls made, and `disable` calls made (tests).
    private(set) var enableCalls = 0
    private(set) var disableCalls = 0

    init(enable: @escaping () -> Void, disable: @escaping () -> Void) {
        self.enable = enable
        self.disable = disable
    }

    /// Takes one hold, enabling secure keyboard entry.
    func acquire() {
        held += 1
        enableCalls += 1
        enable()
    }

    /// Drops one hold, disabling secure keyboard entry; nothing when none is held.
    func release() {
        guard held > 0 else { return }
        held -= 1
        disableCalls += 1
        disable()
    }
}

extension AppKitWindow {
    /// Applies the secure-entry state this window wants: one hold exactly while a secure field is focused, the window is
    /// open and it is the key window.
    func refreshSecureEventInput() {
        let wanted = secureTextInputRequested && secureWindowIsKey && !secureWindowIsClosed
        guard wanted != secureEventInputHeld else { return }
        secureEventInputHeld = wanted
        if wanted { secureEventInput.acquire() } else { secureEventInput.release() }
    }
}
#endif
