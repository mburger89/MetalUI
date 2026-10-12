import Testing
import MetalUI

// SMK port gaps, lane 1 — test 1.1 (ruling `SG-B` items 2–3; spec
// `docs/superpowers/specs/2026-10-09-smk-gaps-design.md` §3.1, §5). Portable:
// `EventModifiers.primary` is the platform's shortcut modifier — ⌘ on Apple
// platforms, Ctrl on Linux and Windows — and the default of
// `KeyboardShortcut(_:modifiers:)`. On macOS `.primary == .command`, so the
// separating run is the Linux image's (and Windows CI's). Red before: the file
// does not compile (no `.primary`).

/// **1.1** (`SG-B` items 2–3). `.primary` is `.command` on Darwin and
/// `.control` elsewhere, and a shortcut written without modifiers takes it.
/// Mutation **M1.1**: `primary = .command` on every platform — reddens in
/// `swift:6.4-noble`.
@Test func thePrimaryModifierIsCommandOnAppleAndControlElsewhere() {
    #if canImport(Darwin)
    #expect(EventModifiers.primary == .command, "⌘ on Apple platforms")
    #else
    #expect(EventModifiers.primary == .control, "Ctrl on Linux and Windows")
    #endif
    #expect(EventModifiers.primary.rawValue.nonzeroBitCount == 1, "one of the four modifier bits, not a new one")
    #expect(KeyboardShortcut("s").modifiers == .primary, "the default shortcut modifier is the primary one")
    #expect(KeyboardShortcut("s", modifiers: .command).modifiers == .command, "an explicit modifier is kept")
}
