// SwiftUI probe: does SwiftUI offer view code any drawn-window-controls API --
// minimise, zoom, a title-bar double-click, window-move regions -- beyond
// `WindowDragGesture` (probe context: ruling CW-C, docs/superpowers/
// 2026-10-13-sdl-chrome-decisions.md)?
//
// HOW TO RUN (typecheck form, SA-O), one arm at a time:
//   xcrun swiftc -typecheck -parse-as-library -DARM_P  docs/probes/swiftui-window-chrome.swift
//   xcrun swiftc -typecheck -parse-as-library -DARM_N1 docs/probes/swiftui-window-chrome.swift
//   (likewise ARM_N2, ARM_N3, ARM_N4)
//
// ARMS. P (positive control, must compile): the names that DO exist --
// `WindowDragGesture`, `.windowMinimizeBehavior(_:)`, 
// `@Environment(\.dismissWindow)`. N1..N4 (separating
// arms, must FAIL to compile): an environment action to minimise
// (`\.minimizeWindow`), one to zoom (`\.zoomWindow`), a `WindowControls` view,
// and a title-bar double-click hook (`.onTitleBarDoubleClick`).
//
// RECORDED 2026-10-13 by the sdl-chrome design session, macOS 27.0.1, Apple Swift 6.4
// (swiftlang-6.4.0.33.1), SwiftUI SDK of that Xcode. Exit codes, verbatim:
//   ARM_P  0 (compiles: WindowDragGesture, windowMinimizeBehavior, dismissWindow exist)
//   ARM_N1 1 (`\.minimizeWindow` is not an EnvironmentValues member)
//   ARM_N2 1 (`\.zoomWindow` is not)
//   ARM_N3 1 (error: cannot find 'WindowControls' in scope)
//   ARM_N4 1 (error: value of type 'Color' has no member 'onTitleBarDoubleClick')
// READING. SwiftUI has behaviour modifiers (minimise disabled) and a move gesture, but no action
// to minimise or zoom from view code, no drawn control set and no title-bar double-click hook:
// every such surface here is MetalUI-only (class M). N1/N2's diagnostics are generic key-path
// errors (the names are absent); a name that SwiftUI adds later would turn them green.
import SwiftUI

#if ARM_P
struct P: View {
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        Color.clear
            .gesture(WindowDragGesture())
            .windowMinimizeBehavior(.disabled)
    }
}
#endif
#if ARM_N1
struct N1: View { @Environment(\.minimizeWindow) private var m; var body: some View { Color.clear } }
#endif
#if ARM_N2
struct N2: View { @Environment(\.zoomWindow) private var z; var body: some View { Color.clear } }
#endif
#if ARM_N3
struct N3: View { var body: some View { WindowControls() } }
#endif
#if ARM_N4
struct N4: View { var body: some View { Color.clear.onTitleBarDoubleClick { } } }
#endif
