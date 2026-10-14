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
    try app.openWindow(title: title, size: chromeDemoSize, windowStyle: .hiddenTitleBar,
                       startsDisplayLink: startsDisplayLink, content: chromeDemoContent)
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

    /// A fresh model.
    public init() {}

    /// Back to a fresh model's values (tests share the one instance).
    public func reset() {
        presses = 0
        taps = 0
        search = ""
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
        }
        .alignItems(.flexStart)
        .padding(Pixels(24))
    }
}
