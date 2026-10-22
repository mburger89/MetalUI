import MetalUI
import Observation

/// The window chrome demo (rulings `CW-A`…`CW-E`; spec `2026-10-13-sdl-chrome-design.md` "Demo"), reached
/// with `METALUI_CHROME_DEMO=1 swift run MetalUIDemo` (and `MetalUISDLDemo`): a 900 × 560 window with a
/// hidden title bar and a 32-point glass bar padded by `@Environment(\.titleBarInsets)` — the title, a
/// button that counts, a search field and a `WindowDragGesture` handle — over a body of ordinary content.
///
/// **The human looks** (`docs/verification/human-checks.md` group CW): the window drags by the empty bar and
/// by the handle; the button, the field and a tap in the bar still work (they are carved out of the drag
/// region); the edges and corners resize; minimise, zoom and close are the window's drawn buttons (SDL) or
/// the traffic lights (AppKit); the content is not covered by the cluster.
///
/// **Presentation extras** (`BG-G`...`BG-M`, group BG): the window also drags from empty space in the body
/// (`Window.backgroundDragBehavior = .enabled`, switched by a button), the button, the field and the rest
/// still work, and a labelled region shows a star-shaped pointer (`PointerStyle.shape`, an even-odd fill).
///
/// Nothing here is in the default demo, so the fourteen offscreen images and `Expected.swift` do not move.
/// Built in its own function and built on a 1 MB thread by `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func chromeDemoContent() -> some Element {
    Column(gap: Pixels(0)) {
        ChromeDemoBar()
        ChromeDemoBody()
    }
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.background)
}

/// The demo window's size: 900 × 560.
public let chromeDemoSize = Size(width: Pixels(900), height: Pixels(560))

/// Opens the chrome demo in `app` (900 × 560, `.hiddenTitleBar`) — what both demos' `main.swift` call.
@MainActor
public func openChromeDemoWindow(_ app: App, title: String, startsDisplayLink: Bool = true) throws -> Window {
    let window = try app.openWindow(title: title, size: chromeDemoSize, windowStyle: .hiddenTitleBar,
                                    startsDisplayLink: startsDisplayLink, content: chromeDemoContent)
    chromeDemoModel.applyBackgroundDrag = { [weak window] on in
        window?.backgroundDragBehavior = on ? .enabled : .automatic
    }
    chromeDemoModel.applyBackgroundDrag?(chromeDemoModel.backgroundDrag)
    return window
}

/// The demo's state.
@MainActor
@Observable
public final class ChromeDemoModel {
    /// How many times the bar's button was pressed.
    public var presses = 0
    /// How many times the bar's tap target was tapped.
    public var taps = 0
    /// The search field's text.
    public var search = ""
    /// Whether the window drags from empty space in the body (`BG-G`); on at launch.
    public var backgroundDrag = true
    /// Applies `backgroundDrag` to the demo's window (set by ``openChromeDemoWindow(_:title:startsDisplayLink:)``).
    var applyBackgroundDrag: (@MainActor (Bool) -> Void)?

    /// A fresh model.
    public init() {}

    /// Back to a fresh model's values (tests share the one instance).
    public func reset() {
        presses = 0
        taps = 0
        search = ""
        backgroundDrag = true
    }
}

/// The one model the demo reads.
@MainActor public let chromeDemoModel = ChromeDemoModel()

/// The glass bar: at least the title bar's band tall and padded by the insets on both sides (the cluster's
/// edge is `left` on macOS-through-SDL, `right` elsewhere; AppKit's traffic lights are `left`). A
/// `Component`, so the environment read happens at layout.
struct ChromeDemoBar: Component {
    @Environment(\.titleBarInsets) var insets

    var content: some ElementGroup {
        Row(gap: Pixels(10)) {
            Text("Chrome").font(size: 13)
            Button("Count \(chromeDemoModel.presses)") { chromeDemoModel.presses += 1 }
            TextField("Search", text: Binding(get: { chromeDemoModel.search },
                                              set: { chromeDemoModel.search = $0 }))
                .frame(width: Pixels(140))
            Box()
                .frame(width: Pixels(60), height: Pixels(24))
                .background(.surface)
                .onTapGesture { chromeDemoModel.taps += 1 }
            Box()
                .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(24), alignment: .leading)
                .gesture(WindowDragGesture())
        }
        .alignItems(.center)
        .padding(Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(insets.right.value + 12)),
                       bottom: .pixels(Pixels(0)), left: .pixels(Pixels(insets.left.value + 12))))
        .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(max(32, insets.top.value)), alignment: .leading)
        .background(.surfaceSecondary)
    }
}

/// The body: the readout and some ordinary content to keep clear of the bar.
struct ChromeDemoBody: Component {
    var content: some ElementGroup {
        Column(gap: Pixels(8)) {
            Text("Window chrome").font(size: 22)
            Text("Drag the empty bar or the handle at its end; resize from any edge or corner.")
            Text("Button presses: \(chromeDemoModel.presses), taps: \(chromeDemoModel.taps), search: “\(chromeDemoModel.search)”")
            ChromeDemoBackground()
        }
        .alignItems(.flexStart)
        .padding(Pixels(24))
    }
}

/// A five-pointed star wound twice, so an even-odd fill leaves its middle pentagon clear.
@MainActor func chromeDemoStar() -> Path {
    var path = Path()
    // The vertices of a pentagon of radius 30 about (32, 32), taken every second one.
    let corners: [(Float, Float)] = [(32, 2), (49.6, 56.3), (3.5, 22.7), (60.5, 22.7), (14.4, 56.3)]
    let points = corners.map { Point(x: Pixels($0.0), y: Pixels($0.1)) }
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
}

/// The presentation-extras section (`BG-G`...`BG-M`), its own `Component` and function so the 1 MB stack
/// budget sees it on its own: the background-drag switch and a star-pointer region.
struct ChromeDemoBackground: Component {
    var content: some ElementGroup {
        Column(gap: Pixels(8)) {
            Button("Background drag: \(chromeDemoModel.backgroundDrag ? "on" : "off")") {
                chromeDemoModel.backgroundDrag.toggle()
                chromeDemoModel.applyBackgroundDrag?(chromeDemoModel.backgroundDrag)
            }
            Text("With it on, drag the window from any empty space below; the star region shows a shape pointer.")
            Box()
                .frame(width: Pixels(180), height: Pixels(64))
                .background(.surfaceSecondary)
                .pointerStyle(.shape(chromeDemoStar(), eoFill: true, size: Size(width: Pixels(64), height: Pixels(64)),
                                     fill: .red))
        }
        .alignItems(.flexStart)
    }
}
