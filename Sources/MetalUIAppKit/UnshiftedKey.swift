#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// The character a physical key produces under the current keyboard layout
/// with **no modifiers** (`KF-AL`): `UCKeyTranslate` over the layout's `uchr`
/// data. `NSEvent.charactersIgnoringModifiers` still applies Shift (⇧/ is "?"),
/// so a shortcut spelled "/" + Shift could not match on it.
///
/// The layout is the current keyboard layout input source, or the current
/// ASCII-capable one when that source (an input method) has no `uchr` data.
/// Translations are cached per layout (its input-source ID) and dropped when
/// the ID changes, so a layout switch is picked up on the next key. Dead keys
/// are not entered (`kUCKeyTranslateNoDeadKeysBit`); a key that translates to
/// nothing or a control character answers "".
@MainActor
enum UnshiftedKey {
    private static var layoutID: String?
    private static var cache: [UInt16: String] = [:]

    static func character(forKeyCode keyCode: UInt16) -> String {
        guard let (id, data) = currentLayout() else { return "" }
        if id != layoutID { layoutID = id; cache.removeAll() }
        if let cached = cache[keyCode] { return cached }
        let result = translate(keyCode: keyCode, layoutData: data)
        cache[keyCode] = result
        return result
    }

    /// The input source's ID and `uchr` data.
    private static func currentLayout() -> (String, CFData)? {
        for source in [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()] {
            guard let source = source?.takeRetainedValue() else { continue }
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            var id = ""
            if let idRaw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                id = Unmanaged<CFString>.fromOpaque(idRaw).takeUnretainedValue() as String
            }
            return (id, data)
        }
        return nil
    }

    private static func translate(keyCode: UInt16, layoutData: CFData) -> String {
        guard let bytes = CFDataGetBytePtr(layoutData) else { return "" }
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return "" }
            let text = String(utf16CodeUnits: chars, count: length)
            // A control or private-use result (Return, arrows, F-keys) is not a base key: those
            // keys are spelled by `charactersIgnoringModifiers` already.
            guard let scalar = text.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F,
                  !(0xF700...0xF8FF).contains(scalar.value) else { return "" }
            return text
        }
    }
}
#endif
