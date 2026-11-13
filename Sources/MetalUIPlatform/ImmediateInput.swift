import Foundation

/// Immediate-input drawing (ruling `FP-M`, record 275): whether a key, text or button event that arrives at an
/// idle window draws its frame at the end of the input handler instead of waiting for the next display-link
/// tick. **Not API**: `package`, undocumented outside `docs/frame-timing.md`.
///
/// The default is on for the AppKit platform (measured: 37.6-39.0 ms to 16.2-16.4 ms median, keystroke to
/// visible, `FP-M`) and off elsewhere (unmeasured on SDL). `METALUI_IMMEDIATE_INPUT=1` turns it on anywhere and
/// `METALUI_IMMEDIATE_INPUT=0` turns it off everywhere; any other value, or none, keeps the platform default.
/// Read once per process.
package enum ImmediateInput {
    /// The environment variable.
    package static let variable = "METALUI_IMMEDIATE_INPUT"

    /// What `environment` says: `true` (`1`), `false` (`0`), `nil` (unset or anything else).
    package static func override(in environment: [String: String]) -> Bool? {
        switch environment[variable] {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }

    /// Whether a window on a platform whose default is `platformDefault` draws immediately.
    package static func isEnabled(platformDefault: Bool, environment: [String: String]) -> Bool {
        override(in: environment) ?? platformDefault
    }

    /// The process's override, read once.
    package static let environmentOverride = override(in: ProcessInfo.processInfo.environment)

    /// ``isEnabled(platformDefault:environment:)`` with the process's environment.
    package static func isEnabled(platformDefault: Bool) -> Bool { environmentOverride ?? platformDefault }

    /// The trace header's `immediate=` field: `default` (platform default), `on` or `off`.
    package static var label: String {
        switch environmentOverride {
        case true?: return "on"
        case false?: return "off"
        case nil: return "default"
        }
    }

    /// The refresh interval assumed until the display link has shown one: 60 Hz.
    package static let fallbackInterval: UInt64 = 16_666_667
}
