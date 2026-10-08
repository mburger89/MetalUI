import MetalUI
import MetalUIDemoContent
import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Metal)
import Metal
#endif

// The demo's content — its model, actions, counter, `demoContent()` and the
// proposal preview — lives in the `MetalUIDemoContent` library target
// (`Sources/MetalUIDemoContent/DemoContent.swift`), which the tests import (plan
// task 7, stage 1, lane 5; ruling LR-S). This file opens the window and binds
// the keys.

@MainActor
func runDemo() throws {
    let app = try App()
    // The demo's generated icon (ruling `AI-G`; human check O1): the Dock shows
    // it for a bare `swift run`, which has no bundle.
    app.icon = demoIcon()

    let nativeLayoutPreview = ProcessInfo.processInfo.environment["METALUI_NATIVE_LAYOUT_PREVIEW"] == "1"
    // Roadmap item 14's human look (TI-F): two text fields.
    let textInputDemo = ProcessInfo.processInfo.environment["METALUI_TEXT_INPUT_DEMO"] == "1"
    // Plan task 10 part 2's human look (record §58): every control, a
    // selectable list, a `ForEach` over a binding.
    let controlsDemo = ProcessInfo.processInfo.environment["METALUI_CONTROLS_DEMO"] == "1"
    // Plan task 15's human looks (`docs/verification/human-checks.md` H1, I1,
    // J1, K1–K3, Q1–Q6, S1–S3): controlSize's drawn font, shapes/clip/images,
    // gestures, transitions, paths/shadows/transforms, colour and scheme.
    let looksDemo = ProcessInfo.processInfo.environment["METALUI_LOOKS_DEMO"] == "1"
    // Drag and drop's human looks (`docs/verification/human-checks.md` N1–N8,
    // ruling DN-Q): chips, a draggable list, four wells.
    let dragAndDropDemo = ProcessInfo.processInfo.environment["METALUI_DND_DEMO"] == "1"
    // MetalView's human looks (`docs/verification/human-checks.md` section O,
    // ruling MV-J): an animated shader quad drawn by app code, UI over it.
    let metalViewDemo = ProcessInfo.processInfo.environment["METALUI_METALVIEW_DEMO"] == "1"
    // Menus, popovers and tooltips' human looks (`docs/verification/human-checks.md`
    // group R): a context menu, a popover, tooltips, a pull-down and — in
    // this mode only — two commands on the menu bar.
    let menusDemo = ProcessInfo.processInfo.environment["METALUI_MENUS_DEMO"] == "1"
    // Platform services' human looks (`docs/verification/human-checks.md`
    // group U, ruling SV-T): open and save panels, an alert sheet, hover
    // tiles, dividers, a 300-option menu picker; a 900 × 600 minimum.
    let servicesDemo = ProcessInfo.processInfo.environment["METALUI_SERVICES_DEMO"] == "1"
    // Variable-height List's human looks (`docs/verification/human-checks.md`
    // group VL, ruling VL-K): 300 content-sized rows of wrapping text,
    // selectable, with a "Jump to row 250" button.
    let listDemo = ProcessInfo.processInfo.environment["METALUI_LIST_DEMO"] == "1"

    // Non-square on purpose, and wider than tall: a square window cannot show a
    // width/height transposition.
    let window: Window
    if listDemo {
        window = try app.openWindow(title: "MetalUI — Variable-height List",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: variableListDemoContent)
    } else if servicesDemo {
        window = try openServicesDemoWindow(app, title: "MetalUI — Platform Services")
    } else if menusDemo {
        app.commands {
            CommandMenu("Demo") {
                Button("Say Hello") { menusDemoModel.status = "Hello from the menu bar" }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Toggle("Pinned", isOn: menusDemoPinned())
            }
            CommandGroup(after: .newItem) {
                Button("New Note") { menusDemoModel.status = "New Note from the menu bar" }.keyboardShortcut("n")
            }
        }
        window = try app.openWindow(title: "MetalUI — Menus",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: menusDemoContent)
    } else if metalViewDemo {
        // Both made once, outside the content closure that runs every frame:
        // the counter must persist (MV-O) and the shader compiles once.
        let draws = MetalViewDemoDraws()
        let surface = shaderQuadDraw()
        window = try app.openWindow(title: "MetalUI — MetalView",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: { metalViewDemoContent(draws: draws, surface: surface) })
    } else if dragAndDropDemo {
        window = try app.openWindow(title: "MetalUI — Drag and Drop",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: dragAndDropDemoContent)
    } else if looksDemo {
        // Colour and colour scheme's human looks (group S): the palette
        // swatch shows the app's dark override, not `LooksBrand`'s default.
        app.darkTheme[LooksBrand.self] = looksBrandDarkOverride
        window = try app.openWindow(title: "MetalUI — Looks",
                                    size: Size(width: Pixels(1180), height: Pixels(880)),
                                    content: looksDemoContent)
    } else if controlsDemo {
        window = try app.openWindow(title: "MetalUI — Controls",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: controlsDemoContent)
    } else if textInputDemo {
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

/// The MetalView demo's viewport drawing (ruling `MV-J` item 1): an animated
/// full-screen-quad fragment shader, compiled from MSL source at runtime with
/// `makeLibrary(source:)` on the first draw (on the renderer's own device), timed
/// by `ctx.time`, encoded as one render pass into the frame's command buffer.
/// Off Metal (no `MetalDrawContext`), a portable `ctx.clear` cycling with time.
@MainActor
func shaderQuadDraw() -> @MainActor (any GPUSurfaceContext) -> Void {
    #if canImport(Metal)
    var pipeline: (any MTLRenderPipelineState)?
    let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Out { float4 position [[position]]; float2 uv; };
        vertex Out quad_vertex(uint id [[vertex_id]]) {
            float2 p = float2((id & 1) ? 1.0 : -1.0, (id & 2) ? -1.0 : 1.0);
            Out o; o.position = float4(p, 0, 1); o.uv = p * 0.5 + 0.5; return o;
        }
        fragment float4 quad_fragment(Out in [[stage_in]], constant float2 &u [[buffer(0)]]) {
            float t = u.x, aspect = u.y;
            float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * 6.0;
            float v = sin(p.x + t) + sin(p.y * 1.3 - t * 1.1) + sin(length(p) * 1.7 - t * 1.6);
            float3 c = 0.5 + 0.5 * cos(float3(0.0, 2.1, 4.2) + v + t * 0.3);
            return float4(c, 1.0);   // opaque, so premultiplied as written
        }
        """
    return { ctx in
        guard let metal = ctx as? MetalDrawContext else {
            let t = Float(ctx.time)
            ctx.clear(red: 0.5 + 0.5 * sin(t), green: 0.5 + 0.5 * sin(t + 2.1), blue: 0.5 + 0.5 * sin(t + 4.2), alpha: 1)
            return
        }
        if pipeline == nil {
            do {
                let library = try metal.device.makeLibrary(source: source, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "quad_vertex")
                descriptor.fragmentFunction = library.makeFunction(name: "quad_fragment")
                descriptor.colorAttachments[0].pixelFormat = metal.target.pixelFormat
                pipeline = try metal.device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                print("MetalView demo: shader failed to build: \(error)")
                metal.clear(red: 0.6, green: 0, blue: 0, alpha: 1)
                return
            }
        }
        guard let pipeline,
              let encoder = metal.commandBuffer.makeRenderCommandEncoder(descriptor: metal.renderPassDescriptor())
        else { return }
        var uniforms = SIMD2<Float>(Float(metal.time.truncatingRemainder(dividingBy: 3600)),
                                    Float(metal.pixelSize.width.value) / Float(max(metal.pixelSize.height.value, 1)))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()   // never commit or present: MetalUI does (MV-F item 5)
    }
    #else
    return { ctx in
        let t = Float(ctx.time)
        ctx.clear(red: 0.5 + 0.5 * sin(t), green: 0.5 + 0.5 * sin(t + 2.1), blue: 0.5 + 0.5 * sin(t + 4.2), alpha: 1)
    }
    #endif
}

try runDemo()
