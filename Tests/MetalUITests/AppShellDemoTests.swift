import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

// App shell, lane 3 — the app shell demo (rulings `AS-B`…`AS-G`; spec
// `docs/superpowers/specs/2026-10-08-app-shell-design.md` §6, §4.3 test 3.4).
// `METALUI_APP_SHELL_DEMO=1` opens `appShellDemoContent()` through
// `openAppShellDemoWindow(_:title:launchArguments:)` in both demos; these pin
// what human checks AS1–AS9 then look at. Headless: an `App` over
// `FakePlatform` (lane 1's fakes). Red before: the demo does not exist at
// `d3da951` — every test here fails by not compiling.

/// An `App` over a fresh `FakePlatform` with the demo window open (display
/// link off, accessibility active, the shared model reset), and its fake.
@MainActor private func appShellDemo(launchArguments: [String] = []) throws -> (App, Window, FakePlatformWindow) {
    appShellDemoModel.reset()
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    let app = App(platform: platform)
    let window = try openAppShellDemoWindow(app, title: "MetalUI — App Shell", launchArguments: launchArguments,
                                            startsDisplayLink: false)
    let fake = try #require(platform.openedWindows.last)
    fake.simulateAccessibilityRequest(.activate)
    fake.simulateResize(to: appShellDemoSize)
    window.drawFrameIfNeeded()
    return (app, window, fake)
}

/// Presses the accessibility node labelled `label` (a `Button`).
@MainActor private func press(_ label: String, _ window: Window, _ fake: FakePlatformWindow,
                              sourceLocation: SourceLocation = #_sourceLocation) throws {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let tree = try #require(fake.publishedAccessibilityTrees.last, sourceLocation: sourceLocation)
    let (id, _) = try #require(tree.nodes.first { $0.value.role == .button && $0.value.label == label },
                               "a button labelled \(label)", sourceLocation: sourceLocation)
    #expect(fake.simulateAccessibilityRequest(.press(id)), sourceLocation: sourceLocation)
}

/// Clicks the drawn alert's button titled `title` (the fake declines to
/// present alerts natively, SDL's answer).
@MainActor private func pressDrawnAlertButton(_ title: String, _ window: Window, _ fake: FakePlatformWindow,
                                              sourceLocation: SourceLocation = #_sourceLocation) throws {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()   // presents the alert
    let drawn = try #require(window.drawnAlert, "the close alert is drawn", sourceLocation: sourceLocation)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()   // draws it
    let panel = try #require(window.drawnAlertPanel, sourceLocation: sourceLocation)
    let index = try #require(drawn.buttons.firstIndex { $0.platform.title == title }, sourceLocation: sourceLocation)
    let button = panel.layout.buttons[index]
    let centre = Point(x: Pixels(button.origin.x.value + button.size.width.value / 2),
                       y: Pixels(button.origin.y.value + button.size.height.value / 2))
    fake.simulateInput(.mouseDown(MouseEvent(position: centre)))
    fake.simulateInput(.mouseUp(MouseEvent(position: centre)))
}

/// **3.4** (`AS-B`, `AS-D`; spec §6). The demo asks before closing an edited
/// document: after "Make a change" the window is edited (the platform told
/// once) and a close request shows "Do you want to save…" and answers later;
/// "Don't Save" closes the window. "Cancel" keeps it, still edited; "Save"
/// clears the marker and closes. A clean document closes at once. The name
/// field's model drives the window title through `.navigationTitle`.
///
/// Mutation: the demo's handler returns `.now` → red.
@MainActor
@Test func theAppShellDemoAsksBeforeClosingAnEditedDocument() throws {
    // Clean: closes at once, the title is the tree's.
    do {
        let (_, window, fake) = try appShellDemo()
        #expect(fake.title == "Untitled.mcgraph", "the tree's title: \(fake.title)")
        appShellDemoModel.name = "bracket.mcgraph"
        window.drawFrameIfNeeded()
        #expect(fake.title == "bracket.mcgraph", "the name drives the title: \(fake.title)")
        #expect(fake.simulateCloseRequest(), "a clean document closes at once")
        #expect(fake.isClosed && !appShellDemoModel.confirmingClose)
    }
    // Edited, then Don't Save.
    do {
        let (_, window, fake) = try appShellDemo()
        try press("Make a change", window, fake)
        #expect(window.isDocumentEdited && fake.documentEditedCalls == [true])
        #expect(!fake.simulateCloseRequest(), "an edited document is not closed at once")
        #expect(window.isCloseRequestPending && appShellDemoModel.confirmingClose)
        try pressDrawnAlertButton("Don't Save", window, fake)
        #expect(fake.isClosed, "Don't Save closed the window")
        #expect(window.isDocumentEdited, "Don't Save leaves the document unsaved")
    }
    // Edited, then Cancel, then Save.
    do {
        let (_, window, fake) = try appShellDemo()
        try press("Make a change", window, fake)
        #expect(!fake.simulateCloseRequest())
        try pressDrawnAlertButton("Cancel", window, fake)
        #expect(!fake.isClosed && !window.isCloseRequestPending, "Cancel kept the window")
        #expect(window.isDocumentEdited)
        #expect(!fake.simulateCloseRequest(), "the next close asks again")
        try pressDrawnAlertButton("Save", window, fake)
        #expect(fake.isClosed, "Save closed the window")
        #expect(!window.isDocumentEdited && fake.documentEditedCalls == [true, false], "\(fake.documentEditedCalls)")
    }
}

/// **3.4b** (`AS-E`, spec §6). The demo window asks for the hidden title bar
/// before its first frame, and its top bar follows the insets: at least 40
/// tall and at least the band's height, the name starting at
/// `titleBarInsets.left + 12`.
@MainActor
@Test func theAppShellDemoPadsItsTopBarByTheTitleBarInsets() throws {
    let (_, window, fake) = try appShellDemo()
    #expect(fake.titleBarStyles == [.hidden] && fake.titleBarStylePresentsBefore == [0])
    func nameFrame() throws -> Bounds<Pixels> {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        let tree = try #require(fake.publishedAccessibilityTrees.last)
        let node = try #require(tree.nodes.values.first {
            $0.role == .staticText && ($0.label == "Untitled.mcgraph" || $0.value == "Untitled.mcgraph")
        }, "the top bar's name")
        return node.frame
    }
    func barHeight() -> Float? {
        let fill = window.theme[.surfaceSecondary]
        return window.lastScene.rects.first {
            ixSame(ixHsla($0.background), fill) && $0.bounds.origin.y == 0 && $0.bounds.size.width == 900
        }.map { $0.bounds.size.height }
    }
    #expect(try nameFrame().origin.x.value == 12, "no insets: 12 from the edge")
    #expect(barHeight() == 40)
    fake.titleBarInsets = Edges(top: Pixels(66), right: Pixels(0), bottom: Pixels(0), left: Pixels(79))
    fake.simulateResize(to: appShellDemoSize)
    #expect(try nameFrame().origin.x.value == 91, "right of the window buttons")
    #expect(barHeight() == 66, "the band's height (a toolbar under the hidden bar)")
}

/// **3.4c** (`AS-G` items 2 and 6). The launch-argument recipe delivers the
/// arguments naming existing files, once each, to the demo's `.onOpenURL`;
/// a later open (Finder, the Dock) is listed after them.
@MainActor
@Test func theAppShellDemoListsLaunchArgumentsAndLaterOpens() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("app shell demo.mcgraph")
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let (app, _, _) = try appShellDemo(launchArguments: ["--flag", file.path, "/no/such/file.mcgraph"])
    #expect(appShellDemoModel.openedURLs == [file.absoluteString], "\(appShellDemoModel.openedURLs)")
    app.open([URL(string: "metalcreator://doc/1")!])
    #expect(appShellDemoModel.openedURLs == [file.absoluteString, "metalcreator://doc/1"])
}
