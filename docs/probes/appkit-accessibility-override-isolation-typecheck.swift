// Typecheck probe, arm A of appkit-accessibility-override-isolation.swift:
// which spelling lets a NONISOLATED NSAccessibility override read `@MainActor`
// state with 0 diagnostics? Evidence for ruling AB-AE in
// docs/superpowers/2026-09-15-accessibility-bridge-decisions.md.
//
// A separate file because the controls need library mode (`-parse-as-library`),
// and compiled to SIL (`-emit-sil`), not merely typechecked: the CAPTURE
// control's diagnostic, `sending 'self' risks causing data races`, comes from
// region-based isolation checking, which runs on SIL. **`-typecheck` reports 0
// for CAPTURE** (measured), so a typecheck-only run could not tell the adopted
// spelling from the rejected one — the committed overrides probe's blind spot
// again, one stage later. Read by grepping for diagnostics, never by exit
// status (AB-AB's lesson).
//
// HOW TO RUN (bash):
//
//   for D in NONE NEGATIVE CAPTURE UNBOXED; do
//     echo "$D: $(xcrun swiftc -emit-sil -o /dev/null -swift-version 6 -parse-as-library -D $D \
//       docs/probes/appkit-accessibility-override-isolation-typecheck.swift 2>&1 | grep -c 'warning:\|error:')"
//   done
//
//   NONE      the adopted spelling (AppKitAccessibility.swift's `mainActorAnswer`): must be 0
//   NEGATIVE  the override body reads main-actor state directly
//   CAPTURE   the helper's body captures `self` instead of taking it as a parameter
//   UNBOXED   `assumeIsolated` returns the non-`Sendable` answer unboxed
//
// RECORDED: see appkit-accessibility-override-isolation.swift's header.

import AppKit

// The adopted helper (the spelling in AppKitAccessibility.swift), and its controls.

/// Never crosses a thread: built and unwrapped on the main thread.
struct MainThreadAnswer<T>: @unchecked Sendable { let value: T }

nonisolated func mainActorAnswer<Object: AnyObject, T>(_ object: Object, fallback: T,
                                                      _ body: @MainActor (Object) -> T) -> T {
    guard Thread.isMainThread else { return fallback }
    let boxed = MainThreadAnswer(value: object)
    #if UNBOXED
    return MainActor.assumeIsolated { body(boxed.value) }
    #else
    return MainActor.assumeIsolated { MainThreadAnswer(value: body(boxed.value)) }.value
    #endif
}

#if CAPTURE
nonisolated func mainActorAnswerCapturing<T>(fallback: T, _ body: @MainActor () -> T) -> T {
    guard Thread.isMainThread else { return fallback }
    return MainActor.assumeIsolated { MainThreadAnswer(value: body()) }.value
}
#endif

@MainActor final class Bridge { var label = "live" }

@MainActor final class Element: NSAccessibilityElement {
    let bridge: Bridge
    init(bridge: Bridge) { self.bridge = bridge; super.init() }
    #if NEGATIVE
    override func accessibilityLabel() -> String? { bridge.label }
    #elseif CAPTURE
    override func accessibilityLabel() -> String? { mainActorAnswerCapturing(fallback: nil) { bridge.label } }
    #else
    override func accessibilityLabel() -> String? { mainActorAnswer(self, fallback: nil) { $0.bridge.label } }
    override func accessibilityChildren() -> [Any]? { mainActorAnswer(self, fallback: []) { [$0] } }
    #endif
}

