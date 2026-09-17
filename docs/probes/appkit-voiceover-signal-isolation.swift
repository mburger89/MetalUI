// Typecheck-and-run probe: the isolation of lane 2's `VoiceOverSignal`
// (ruling AB-B's second trigger; the spelling is ruling AB-AB in
// docs/superpowers/2026-09-15-accessibility-bridge-decisions.md).
//
// The second critic found that the spec's first spelling — a `@MainActor`
// handler called straight from `NSWorkspace.observe(\.isVoiceOverEnabled,
// options: [.initial, .new]) { ws, _ in handler(ws.isVoiceOverEnabled) }` —
// emits `warning: call to main actor-isolated parameter 'handler' in a
// synchronous nonisolated context`, and that `-warnings-as-errors` does NOT turn
// that diagnostic group into an error: the typecheck exits 0 with a warning. The
// committed overrides probe never called a handler, so its "exit 0" said nothing
// about this. **So this probe is read by grepping for `warning:`, never by its
// exit status.**
//
// The adopted spelling (the default build of this file):
//   - the initial value is read and delivered SYNCHRONOUSLY, on the main actor,
//     inside `observe` — after the KVO observation is installed, so a flip
//     between the two is delivered (late) rather than lost;
//   - a later change is delivered through `Task { @MainActor in handler(v) }`,
//     with `v` taken from `change.newValue` (a `Bool`, `Sendable`) so no
//     `NSWorkspace` crosses the hop;
//   - no `MainActor.assumeIsolated` anywhere: it traps if a `.new` change is
//     delivered off the main thread (CLAUDE.md's SIGTRAP history), and nothing
//     documents the KVO delivery thread for this property.
// A duplicate `true` (initial true, then a late hop also true) is harmless:
// the bridge's activation is sticky and sends `.activate` once.
//
// HOW TO RUN:
//
//   # adopted spelling: must print NO `warning:` line
//   xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors \
//     docs/probes/appkit-voiceover-signal-isolation.swift 2>&1 | grep -c 'warning:'; echo "exit=${PIPESTATUS[0]}"
//   # NEGATIVE CONTROL, the spec's first spelling: must print the warning
//   xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors -D SPEC_SHAPE \
//     docs/probes/appkit-voiceover-signal-isolation.swift 2>&1 | grep 'warning:'
//   # POSITIVE CONTROL for the grep: an unused variable, same flags
//   xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors -D UNUSED_CONTROL \
//     docs/probes/appkit-voiceover-signal-isolation.swift 2>&1 | grep -c 'error:\|warning:'
//   # and the adopted spelling RUNS: the initial value arrives before observe returns
//   /usr/bin/swift docs/probes/appkit-voiceover-signal-isolation.swift
//
// RECORDED 2026-09-15 by the accessibility-bridge design session (second critic
// round), macOS 26.6.2 (25G83), Apple Swift 6.4 (swiftlang-6.4.0.33.1):
//
//   adopted spelling:  no output; grep -c 'warning:' = 0; exit=0
//   -D SPEC_SHAPE:     :69:13: warning: call to main actor-isolated parameter 'handler'
//                      in a synchronous nonisolated context [#ActorIsolatedCall]
//                      exit=0 — despite -warnings-as-errors: the critic's finding,
//                      reproduced
//   -D UNUSED_CONTROL: :87:22: error: initialization of immutable value 'unused' was
//                      never used … [#NoUsage]; exit=1 — the flag does turn an
//                      ordinary warning into an error, so exit 0 above is this
//                      diagnostic group escaping it, not a flag that was ignored
//   run:               initial values delivered before observe returned: [false]

import AppKit

@MainActor protocol AccessibilityClientSignal: AnyObject {
    /// Calls `handler` with the current value before returning, then on every
    /// change (possibly after a main-actor hop).
    func observe(_ handler: @escaping @MainActor (Bool) -> Void)
}

#if SPEC_SHAPE
@MainActor final class VoiceOverSignal: AccessibilityClientSignal {
    private var observation: NSKeyValueObservation?
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) {
        observation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.initial, .new]) { ws, _ in
            handler(ws.isVoiceOverEnabled)
        }
    }
}
#else
@MainActor final class VoiceOverSignal: AccessibilityClientSignal {
    private var observation: NSKeyValueObservation?
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) {
        observation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new]) { _, change in
            let value = change.newValue ?? false
            Task { @MainActor in handler(value) }
        }
        handler(NSWorkspace.shared.isVoiceOverEnabled)
    }
}
#endif

#if UNUSED_CONTROL
func control() { let unused = 1 }
#endif

MainActor.assumeIsolated {
    let signal = VoiceOverSignal()
    var delivered: [Bool] = []
    signal.observe { delivered.append($0) }
    print("initial values delivered before observe returned: \(delivered)")
}
