import MetalUI

/// The MetalView demo (ruling `MV-J`; spec `2026-10-01-metal-view-design.md`
/// §7), reached with `METALUI_METALVIEW_DEMO=1 swift run MetalUIDemo` (and the
/// same variable for `Backends/SDL`'s `MetalUISDLDemo`). A title; a large
/// `.continuous` GPU surface in a rounded clip with a translucent label
/// composited over it — UI over app GPU content, §1's point — that a tap
/// pauses (it becomes `.onDemand`, so it stops drawing and the window idles)
/// and resumes; a count of the large surface's draws; and a small `.onDemand`
/// surface redrawn only when a `Stepper`'s value changes (its `value:`).
///
/// **`surface` is the executable's drawing for the large viewport** — this
/// target is portable and imports no GPU API: `MetalUIDemo` downcasts to
/// `MetalDrawContext` and runs an animated fragment shader; `MetalUISDLDemo`
/// clears to a colour cycling with `ctx.time`. The small surface draws
/// portably, through `ctx.clear`.
///
/// **The draw count is read during the build**, from a plain (untracked)
/// counter the large surface's draw increments: a draw runs in the renderer,
/// after the build, and must not write `@State` (write from input, never from
/// a phase). So the number lags the drawing by one frame and freezes — with
/// the window idle — while paused. **The caller creates the counter once and
/// passes it in** (`main.swift` does so outside `openWindow`'s content
/// closure, which runs every frame): held in a never-written `@State` it was
/// re-seeded from the freshly built struct's initial value every frame —
/// `StateTable.peek` reads an absent entry as absent — so the header read 0
/// forever (`MV-O`; pinned by `theMetalViewDemosDrawCountAdvances`).
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move (`MV-K` item 1). Each section is its own
/// function, passed as an argument to a generic composing function — the
/// Windows stack rule `demoContent()`'s note records; built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func metalViewDemoContent(draws: MetalViewDemoDraws,
                                 surface: @escaping @MainActor (any GPUSurfaceContext) -> Void) -> some Element {
    metalViewDemoRoot(MetalViewDemo(draw: surface, draws: draws))
}

/// The MetalView demo's untracked draw counter (see `metalViewDemoContent`'s
/// doc): the large surface's draw increments it, the header reads it. Create
/// one per demo window, outside the window's content closure.
@MainActor
public final class MetalViewDemoDraws {
    /// The large surface's draws so far.
    public internal(set) var count = 0
    /// A counter at zero.
    public init() {}
}

/// The demo's state: whether the large surface is paused and the small one's
/// tint. The draw counter is the caller's, not `@State` (see
/// `metalViewDemoContent`'s doc).
struct MetalViewDemo: Component {
    let draw: @MainActor (any GPUSurfaceContext) -> Void
    let draws: MetalViewDemoDraws
    @State var paused = false
    @State var tint = 2

    var content: some ElementGroup {
        metalViewDemoHeader(paused: paused, draws: draws.count)
        metalViewDemoViewport(paused: paused, draws: draws, draw: draw, toggle: { paused.toggle() })
        metalViewDemoStepper(tint: $tint)
    }
}

/// The root: the component's three members — the header, the viewport, the
/// stepper row — in a column.
@MainActor
private func metalViewDemoRoot(_ demo: MetalViewDemo) -> some Element {
    Column(gap: Pixels(16)) {
        demo
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

@MainActor
private func metalViewDemoHeader(paused: Bool, draws: Int) -> some Element {
    Column(gap: Pixels(4)) {
        Text("MetalView").font(size: 22)
        Text(paused ? "Paused: tap the viewport to resume." : "Animating: tap the viewport to pause.")
        Text("Viewport draws: \(draws)")
    }
    .alignItems(.flexStart)
}

/// The large `.continuous` surface, its label composited over it.
@MainActor
private func metalViewDemoViewport(paused: Bool, draws: MetalViewDemoDraws,
                                   draw: @escaping @MainActor (any GPUSurfaceContext) -> Void,
                                   toggle: @escaping @MainActor () -> Void) -> some Element {
    HStack(spacing: Pixels(0)) {
        GPUSurface(redraw: paused ? .onDemand : .continuous) { ctx in
            draws.count += 1
            draw(ctx)
        }
        .frame(width: Pixels(520), height: Pixels(300))
        .overlay(alignment: .topLeading) {
            ProposalText("App-drawn GPU content, UI composited over it")
                .padding(Edges(all: Pixels(8)))
                .background(.surface)
                .opacity(0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: Pixels(16)))
        .onTapGesture(perform: toggle)
    }
}

/// Eight tints for the small surface, premultiplied opaque (r, g, b).
private let metalViewDemoTints: [(Float, Float, Float)] = [
    (0.85, 0.25, 0.25), (0.90, 0.55, 0.20), (0.90, 0.80, 0.25), (0.35, 0.75, 0.35),
    (0.25, 0.70, 0.75), (0.25, 0.45, 0.85), (0.55, 0.35, 0.85), (0.80, 0.35, 0.65)
]

/// A `Stepper` and the small `.onDemand` surface it redraws through `value:`.
@MainActor
private func metalViewDemoStepper(tint: Binding<Int>) -> some Element {
    let index = tint.wrappedValue
    return Row(gap: Pixels(12)) {
        Stepper("Tint \(index)", value: tint, in: 0...(metalViewDemoTints.count - 1))
        HStack(spacing: Pixels(0)) {
            GPUSurface(value: index) { ctx in
                let (r, g, b) = metalViewDemoTints[index]
                ctx.clear(red: r, green: g, blue: b, alpha: 1)
            }
            .frame(width: Pixels(80), height: Pixels(40))
            .clipShape(RoundedRectangle(cornerRadius: Pixels(8)))
        }
    }
}
