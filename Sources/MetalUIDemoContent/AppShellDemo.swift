import MetalUI
import Observation
import Foundation

/// The app shell demo (rulings `AS-B`…`AS-G`; spec
/// `2026-10-08-app-shell-design.md` §6), reached with
/// `METALUI_APP_SHELL_DEMO=1 swift run MetalUIDemo` (and `MetalUISDLDemo`): a
/// 900 × 600 window with a hidden title bar (`.hiddenTitleBar`), a top bar
/// padded by `@Environment(\.titleBarInsets)` showing the document's name and
/// "— Edited", a name field driving `.navigationTitle(_:)`, "Make a change" and
/// "Save" driving `Window.isDocumentEdited`, a close request that asks before
/// closing an edited document (the window's drawn or native alert, answered
/// later through `Window.replyToCloseRequest(_:)`), and the URLs received
/// through `.onOpenURL` — fed from the launch arguments by the recipe
/// (`appShellDemoLaunchURLs(_:)`, `AS-G` item 6). There is no
/// `App.onTerminateRequest`, so ⌘Q asks through the window (`AS-C` item 2).
///
/// **The human looks** (`docs/verification/human-checks.md` group AS): the
/// traffic lights over the top bar, the edited dot, the quit alert, the band
/// drag, an open from Finder.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Built in its own function and built on a 1 MB
/// thread by `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func appShellDemoContent() -> some Element {
    appShellRoot(topBar: AppShellTopBar(), document: appShellDocumentSection(), opened: AppShellOpenedList())
}

/// The demo window's size: 900 × 600.
public let appShellDemoSize = Size(width: Pixels(900), height: Pixels(600))

/// Opens the app shell demo in `app` (900 × 600, `.hiddenTitleBar`), installs
/// its close handler and delivers the documents among `launchArguments` —
/// what both demos' `main.swift` call, passing
/// `Array(CommandLine.arguments.dropFirst())`. The model holds the window
/// weakly.
@MainActor
public func openAppShellDemoWindow(_ app: App, title: String, launchArguments: [String] = [],
                                   startsDisplayLink: Bool = true) throws -> Window {
    let window = try app.openWindow(title: title, size: appShellDemoSize, windowStyle: .hiddenTitleBar,
                                    startsDisplayLink: startsDisplayLink, content: appShellDemoContent)
    appShellDemoModel.window = window
    // Stored on the window, so it captures only the model (no cycle).
    window.onCloseRequest = { appShellDemoModel.closeRequested() }
    app.open(appShellDemoLaunchURLs(launchArguments))
    return window
}

/// The launch-argument recipe (ruling `AS-G` item 6, `docs/packaging.md`):
/// MetalUI reads no `CommandLine.arguments`, so the app delivers the
/// arguments that name existing files, as file URLs, through `App.open(_:)`.
/// AppKit itself delivers no command-line path (`AS-M`), so each document
/// arrives once on every platform.
public func appShellDemoLaunchURLs(_ arguments: [String]) -> [URL] {
    arguments.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
}

/// The demo's state.
@MainActor
@Observable
public final class AppShellDemoModel {
    /// The document's name — the window title through `.navigationTitle`.
    public var name = "Untitled.mcgraph"
    /// Whether the document has unsaved changes (mirrors
    /// `Window.isDocumentEdited`, which is not observable).
    public private(set) var isEdited = false
    /// Whether the close alert is shown.
    public var confirmingClose = false
    /// Every URL `.onOpenURL` received, in order, as absolute strings.
    public var openedURLs: [String] = []
    /// The demo's window, held weakly (the window owns the content).
    @ObservationIgnored public weak var window: Window?

    /// A fresh model.
    public init() {}

    /// Back to a fresh model's values (tests share the one instance).
    public func reset() {
        name = "Untitled.mcgraph"
        isEdited = false
        confirmingClose = false
        openedURLs = []
        window = nil
    }

    /// Marks the document edited or saved, on the model and the window.
    public func setEdited(_ edited: Bool) {
        isEdited = edited
        window?.isDocumentEdited = edited
    }

    /// The window's close handler (`Window.onCloseRequest`): a clean document
    /// closes now; an edited one shows the alert and answers later.
    public func closeRequested() -> CloseRequestReply {
        guard isEdited else { return .now }
        confirmingClose = true
        return .later
    }

    /// The alert's answer: `save` clears the marker first; `close` closes.
    public func answerClose(save: Bool, close: Bool) {
        if save { setEdited(false) }
        window?.replyToCloseRequest(close)
    }
}

/// The one model the demo reads.
@MainActor public let appShellDemoModel = AppShellDemoModel()

/// A section built when the window lays it out (a `Component`'s content), as
/// the services demo's are (`SV-AK`).
struct AppShellPart<Body: ElementGroup>: Component {
    let make: @MainActor () -> Body
    var content: some ElementGroup { make() }
}

/// The root: the top bar over the document section. The window-preference
/// modifiers sit inside the root container (`AS-N`).
@MainActor
func appShellRoot(topBar: some ElementGroup, document: some ElementGroup, opened: some ElementGroup) -> some Element {
    Column(gap: Pixels(0)) {
        topBar
        Column(gap: Pixels(20)) {
            document
            opened
        }
        .alignItems(.flexStart)
        .padding(Pixels(24))
        .frame(maxWidth: Pixels(.infinity), alignment: .topLeading)
        .navigationTitle(appShellDemoModel.name)
        .onOpenURL { url in appShellDemoModel.openedURLs.append(url.absoluteString) }
    }
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.background)
}

/// The top bar: at least 40 tall and at least the title bar's band, its
/// content starting right of the window buttons (`titleBarInsets.left + 12`).
/// Under the standard title bar (and on SDL) the insets read zero.
struct AppShellTopBar: Component {
    @Environment(\.titleBarInsets) var insets

    var content: some ElementGroup {
        Row(gap: Pixels(8)) {
            Text(appShellDemoModel.name).font(size: 13)
            if appShellDemoModel.isEdited {
                Text("— Edited").font(size: 13).foregroundColor(.secondary)
            }
        }
        .alignItems(.center)
        .padding(Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(12)), bottom: .pixels(Pixels(0)),
                       left: .pixels(Pixels(insets.left.value + 12))))
        .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(max(40, insets.top.value)), alignment: .leading)
        .background(.surfaceSecondary)
    }
}

/// The name field, the edit buttons and the close alert.
@MainActor
func appShellDocumentSection() -> some ElementGroup { AppShellPart { appShellDocumentSectionBody() } }

@MainActor
func appShellDocumentSectionBody() -> some Element {
    Column(gap: Pixels(12)) {
        Text("App shell").font(size: 22)
        Text("Close the window or quit with unsaved changes: it asks first.")
        Row(gap: Pixels(12)) {
            Text("Name")
            TextField("Name", text: Binding(get: { appShellDemoModel.name },
                                            set: { appShellDemoModel.name = $0 }))
                .frame(width: Pixels(240))
        }
        .alignItems(.center)
        Row(gap: Pixels(12)) {
            Button("Make a change") { appShellDemoModel.setEdited(true) }
            AppShellSaveButton()
        }
    }
    .alignItems(.flexStart)
}

/// "Save" and the close alert it carries. **A `Component`**, so the alert's
/// actions are evaluated when the window lays it out, not when the tree is
/// built (`SV-AK` item 7: the 1 MB-stack test builds off the main thread).
private struct AppShellSaveButton: Component {
    var content: some ElementGroup {
        Button("Save") { appShellDemoModel.setEdited(false) }
            .alert("Do you want to save the changes made to “\(appShellDemoModel.name)”?",
                   isPresented: Binding(get: { appShellDemoModel.confirmingClose },
                                        set: { appShellDemoModel.confirmingClose = $0 })) {
                Button("Save") { appShellDemoModel.answerClose(save: true, close: true) }
                Button("Don't Save", role: .destructive) { appShellDemoModel.answerClose(save: false, close: true) }
                Button("Cancel", role: .cancel) { appShellDemoModel.answerClose(save: false, close: false) }
            } message: {
                Text("Your changes will be lost if you don't save them.")
            }
    }
}

/// The URLs `.onOpenURL` received.
struct AppShellOpenedList: Component {
    var content: some ElementGroup {
        Column(gap: Pixels(4)) {
            Text("Opened").font(size: 15)
            Text(appShellDemoModel.openedURLs.isEmpty ? "No documents opened yet."
                 : appShellDemoModel.openedURLs.joined(separator: "\n"))
        }
        .alignItems(.flexStart)
    }
}
