import MetalUI
import MetalUIDemoContent
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// The demo's content — its model, actions, counter, `demoContent()` and the
// proposal preview — lives in the `MetalUIDemoContent` library target
// (`Sources/MetalUIDemoContent/DemoContent.swift`), which the tests import (plan
// task 7, stage 1, lane 5; ruling LR-S). This file opens the window and binds
// the keys.

@MainActor
func runDemo() throws {
    let app = try App()

    let nativeLayoutPreview = ProcessInfo.processInfo.environment["METALUI_NATIVE_LAYOUT_PREVIEW"] == "1"
    // Roadmap item 14's human look (TI-F): two text fields.
    let textInputDemo = ProcessInfo.processInfo.environment["METALUI_TEXT_INPUT_DEMO"] == "1"

    // Non-square on purpose, and wider than tall: a square window cannot show a
    // width/height transposition.
    let window: Window
    if textInputDemo {
        window = try app.openWindow(title: "MetalUI — Text Input",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: textInputDemoContent)
    } else if nativeLayoutPreview {
        window = try app.openWindow(title: "MetalUI — Native Layout Preview",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: nativeLayoutPreviewContent)
    } else {
        window = try app.openWindow(title: "MetalUI — Milestones 1 to 3",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: demoContent)
    }

    // **Every key this demo binds goes through the window's keymap**, and the
    // ad-hoc `onInput` switch that used to hold space and M is gone. That is
    // milestone 3's own dogfooding: a keystroke resolves to an `Action` type,
    // the action bubbles the focus chain, and anything nothing in the chain
    // handles arrives at `Window.onAction` below. The old switch on
    // `charactersIgnoringModifiers` still worked and said nothing about the
    // subsystem this milestone built.
    //
    // **The comment this replaces claimed "there is no hit-testing in the
    // framework yet", and that is now false in three separate ways**: the frame
    // owns one hitbox list, wheel routing and click dispatch both rank against
    // it, and the counter above registers a click target on it.
    //
    // Two independent ways to see the theme switch remain, because they fail
    // separately. The system path (§7.9) is the real one — toggle Appearance in
    // System Settings or Control Center and the window follows
    // `NSApp.effectiveAppearance`. **Space** below sets `window.theme` directly,
    // so a human can compare the two variants without leaving the app; a later
    // system change overwrites it, which is the correct precedence and not a bug
    // to chase.
    //
    // Both paths are covered by tests up to the point where the scene is handed
    // to the renderer. What the demo adds, and no test can, is that the frame
    // reaches a drawable someone is looking at — `MetalLayerSurface` vends
    // drawables just as happily into an orphaned layer.
    //
    // **`=` and `-` carry `context: "Counter"`, and that is design spec §4.3
    // rather than decoration.** The predicate is matched against the contexts
    // contributed by the *focus chain*, and `CounterPanel` is the only element
    // contributing `Counter` — so the two counter bindings exist only while the
    // counter is focused, and the same keys are free for anything else the rest
    // of the time. Unfocus with **Escape** and press `=`: nothing happens, and
    // nothing swallows the keystroke either (an action nobody handles falls
    // through to `onKey` and then to `onInput`).
    //
    // `shift-+` is bound alongside `=` because `charactersIgnoringModifiers`
    // folds shift in: the same physical key reports `"="` with no modifiers and
    // `"+"` with shift, and `Keystroke.matches` compares the modifier set
    // exactly rather than by containment, so one spelling cannot cover both.
    //
    // **Q quits, and the summary below is what makes that worth a binding.**
    // M4 spec 1's instrument. Every other figure for the idle pause is against
    // the fake platform window; this is the only thing that observes the real
    // `CADisplayLink` pausing. It is a printed COUNT, not a human judgement —
    // see the spec's §7.
    func printReactivitySummary() {
        print("""

        --- reactivity counters ---
        frames drawn:          \(window.framesDrawn)
        pauses entered:        \(window.pausesEntered)
        observation dirtyings: \(window.observationDirtyings)
        ---------------------------
        """)
    }
    // Registered once, here, rather than called from `QuitDemo`'s handler or
    // from the window's close button separately — `atexit_b` fires on every
    // path out of the process, so **Q** and the close button print the
    // identical summary through the identical hook rather than two call
    // sites that could drift apart.
    atexit_b { MainActor.assumeIsolated { printReactivitySummary() } }

    window.keymap = Keymap {
        KeyBinding("=", Increment(), context: "Counter")
        KeyBinding("shift-+", Increment(), context: "Counter")
        KeyBinding("-", Decrement(), context: "Counter")
        KeyBinding("f", FocusCounter())
        KeyBinding("escape", ClearFocus())
        KeyBinding("space", ToggleTheme())
        KeyBinding("m", ToggleModal())
        KeyBinding("a", ToggleAnimationDemo())
        KeyBinding("q", QuitDemo())
    }

    // **The window's fallback, which is what makes a binding work with nothing
    // focused.** `Increment` and `Decrement` never reach here — `CounterPanel`
    // registers handlers for both and the chain runs first — so the four cases
    // below are exactly the actions no element owns.
    //
    // `[weak window]`, because this closure is stored **on** the window:
    // `window.onAction = { window.… }` closes a retain cycle immediately, with
    // no frame drawn and nothing that ever clears it (`Window.onAction`'s own
    // doc comment).
    window.onAction = { [weak window] action in
        guard let window else { return false }
        switch action {
        case is ToggleTheme:
            window.theme = window.theme == .dark ? .light : .dark
            return true
        case is ToggleModal:
            demoModel.showModal.toggle()
            return true
        case is ToggleAnimationDemo:
            // A spring rather than a duration curve — Task 1 built both, and
            // the brief asked which reads more convincingly here: a slide
            // with a little give reads as motion rather than a discrete
            // jump, where the milestone's own `.default`
            // (`spring(duration: 0.5, bounce: 0)`) is critically damped and
            // easy to mistake for a fast linear move. `bounce: 0.2` keeps a
            // human's eye on the overshoot without visibly nudging the width
            // back under 196pt.
            withAnimation(.spring(duration: 0.6, bounce: 0.2)) {
                demoModel.animationDemoActive.toggle()
            }
            return true
        case is FocusCounter:
            // `counterID` is `nil` only before the first frame has been laid
            // out, and `focus(nil)` is the correct answer then rather than an
            // error: there is nothing to focus yet.
            window.focus(counterID)
            return true
        case is ClearFocus:
            window.focus(nil)
            return true
        case is QuitDemo:
            // The `return` is INSIDE the `#if` on purpose. Returning `true`
            // unconditionally claims the keystroke on a platform where this
            // handler does nothing, so **Q** would be silently swallowed
            // rather than falling through to `onKey` and `Window.onInput`.
            // Handling an action is what claims it — an action nobody handles
            // does not claim the keystroke — and on a non-AppKit build nobody
            // handles this one.
            #if canImport(AppKit)
            NSApplication.shared.terminate(nil)
            return true
            #else
            return false
            #endif
        default:
            return false
        }
    }

    // Published for `CounterPanel`, which focuses itself once on its first
    // layout so `=` and `-` work without a human having to press **F** first.
    // Assigned before `app.run()` for that reason — the first frame is drawn by
    // the display link, which does not start until then.
    //
    // **That sentence was false for the whole milestone**, and the fix is in
    // `Window`, not here: `drawFrameIfNeeded` read `focusedElement` back from
    // the frame unconditionally, overwriting a `focus(_:)` call made *during*
    // that render with the value the frame had been handed. The counter was
    // never focused at launch. The read-back is guarded now — see its comment,
    // and `focusingFromInsideAFrameSurvivesThatFrame`.
    demoWindow = window

    app.run()
}

try runDemo()
