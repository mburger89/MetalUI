import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// App shell, lane 2, tests 2.16–2.20 and 2.27 (ruling `AS-D`; probe
// `docs/probes/swiftui-app-shell.swift` `N1`–`N5`; spec §4.2). The window
// title, the tree's `.navigationTitle` (first report in post-order: the inner
// beats the outer, `N2`; the first sibling beats the second, `N5`), the
// represented file and the edited marker — each reaching the platform only
// when its effective value changes. Headless over `FakePlatform`.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let fileURL = URL(fileURLWithPath: "/tmp/x.mcgraph")

@Observable @MainActor private final class TitleModel {
    var mode = 0
    var title = "a"
}

/// **2.16** (`AS-D` item 1). `Window.title` reaches the platform when it
/// changes, never per build, and at once from the setter. Mutations: push
/// every build; the setter only stores (`AS-P` V1).
@MainActor
@Test func windowTitleReachesThePlatformOnChangeOnly() throws {
    let (app, platform) = try shellApp()
    let window = try app.openWindow(title: "Start", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column { Box().frame(width: px(10), height: px(10)) }
    }
    let fake = try #require(platform.openedWindows.last)
    #expect(window.title == "Start")
    let writesAfterOpen = fake.titleWrites.count
    for _ in 0..<3 {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    #expect(fake.titleWrites.count == writesAfterOpen, "an unchanged title is not re-sent per build")

    window.title = "Renamed"
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(fake.title == "Renamed")
    #expect(fake.titleWrites.count == writesAfterOpen + 1, "\(fake.titleWrites)")
    window.title = "Renamed"
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(fake.titleWrites.count == writesAfterOpen + 1)
    #expect(window.title == "Renamed")

    // The setter sends at once (`AS-D` item 1, `AS-P` item 8): no redraw
    // requested, no frame drawn — an idle window whose display link is
    // paused still shows a runtime rename. Mutation: the setter only stores.
    window.title = "Immediate"
    #expect(fake.title == "Immediate", "the setter itself reaches the platform")
    #expect(fake.titleWrites.count == writesAfterOpen + 2, "\(fake.titleWrites)")
}

/// **2.17** (`AS-D` item 2, `N1`, `N2`, `N5`). Inner beats outer; the first
/// sibling beats the second; removing the tree's title falls back to
/// `Window.title`; a change of the tree's title is followed. Mutations: last
/// report wins (siblings red); outer wins (nesting red).
@MainActor
@Test func theTreeTitleWinsInnerBeatsOuterFirstSiblingBeatsSecond() throws {
    let (app, platform) = try shellApp()
    let model = TitleModel()
    let window = try app.openWindow(title: "Window", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column {
            if model.mode == 0 {
                Column { Box().frame(width: px(10), height: px(10)).navigationTitle("inner") }
                    .navigationTitle("outer")
            }
            if model.mode == 1 {
                Box().frame(width: px(10), height: px(10)).navigationTitle("first")
                Box().frame(width: px(10), height: px(10)).navigationTitle("second")
            }
            if model.mode == 3 {
                Box().frame(width: px(10), height: px(10)).navigationTitle(model.title)
            }
        }
    }
    let fake = try #require(platform.openedWindows.last)
    #expect(fake.title == "inner", "the inner title beats an enclosing one (N2)")

    model.mode = 1
    window.drawFrameIfNeeded()
    #expect(fake.title == "first", "the first of two siblings wins (N5)")

    model.mode = 2
    window.drawFrameIfNeeded()
    #expect(fake.title == "Window", "removed: Window.title again")

    model.mode = 3
    window.drawFrameIfNeeded()
    #expect(fake.title == "a")
    model.title = "b"
    window.drawFrameIfNeeded()
    #expect(fake.title == "b", "a changed tree title is followed (N1)")
    window.title = "Ignored while the tree has one"
    #expect(fake.title == "b")
    #expect(window.title == "Ignored while the tree has one", "Window.title reads back what was assigned")
}

/// **2.18** (`AS-D` item 2). A tree title is in the first presented frame:
/// after `openWindow` the platform's title is already the tree's. Mutation:
/// apply it before the build (one frame late).
@MainActor
@Test func aTreeTitleIsInTheFirstPresentedFrame() throws {
    let (app, platform) = try shellApp()
    _ = try app.openWindow(title: "Window", size: Size(width: px(64), height: px(64)),
                           startsDisplayLink: false) {
        Column { Box().frame(width: px(10), height: px(10)).navigationTitle("Tree") }
    }
    let fake = try #require(platform.openedWindows.last)
    #expect(fake.fakeSurface.presentCalls == 1, "control: exactly the first frame was drawn")
    #expect(fake.title == "Tree")
}

/// **2.19** (`AS-D` item 3, `N3`, `N4`). `.navigationDocument` sets the
/// represented path and leaves the title; a non-file URL forwards `nil`;
/// with no tree document `Window.representedURL` is used. Mutation: forward
/// `absoluteString`.
@MainActor
@Test func navigationDocumentSetsTheRepresentedPathAndLeavesTheTitle() throws {
    let (app, platform) = try shellApp()
    let model = TitleModel()
    let window = try app.openWindow(title: "Window", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column {
            if model.mode == 0 {
                Box().frame(width: px(10), height: px(10)).navigationDocument(fileURL)
            }
            if model.mode == 1 {
                Box().frame(width: px(10), height: px(10))
                    .navigationDocument(URL(string: "https://example.com/doc")!)
            }
        }
    }
    let fake = try #require(platform.openedWindows.last)
    #expect(fake.representedPaths == ["/tmp/x.mcgraph"])
    #expect(fake.title == "Window", "the document never changes the title (N3)")

    model.mode = 1
    window.drawFrameIfNeeded()
    #expect(fake.representedPaths == ["/tmp/x.mcgraph", nil], "a non-file URL is not forwarded")

    model.mode = 2
    window.representedURL = URL(fileURLWithPath: "/tmp/window.mcgraph")
    window.drawFrameIfNeeded()
    #expect(fake.representedPaths == ["/tmp/x.mcgraph", nil, "/tmp/window.mcgraph"],
            "the window's own when the tree has none")
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(fake.representedPaths.count == 3, "sent on change only")
    #expect(window.representedURL == URL(fileURLWithPath: "/tmp/window.mcgraph"))
    window.representedURL = nil
    #expect(fake.representedPaths == ["/tmp/x.mcgraph", nil, "/tmp/window.mcgraph", nil])
}

/// **2.20** (`AS-D` item 4). `isDocumentEdited` reaches the platform on
/// change. Mutation: no push.
@MainActor
@Test func isDocumentEditedReachesThePlatformOnChange() throws {
    let (app, platform) = try shellApp()
    let window = try app.openWindow(title: "Window", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column { Box().frame(width: px(10), height: px(10)) }
    }
    let fake = try #require(platform.openedWindows.last)
    #expect(fake.documentEditedCalls.isEmpty, "a clean window never tells the platform")
    window.isDocumentEdited = true
    #expect(fake.documentEditedCalls == [true])
    window.isDocumentEdited = true
    #expect(fake.documentEditedCalls == [true])
    window.isDocumentEdited = false
    #expect(fake.documentEditedCalls == [true, false])
    #expect(!window.isDocumentEdited)
    #expect(fake.title == "Window", "the marker never alters the title")
}

// MARK: - 2.27: transparency

/// A 20 × 20 clickable leaf with one `@State` counter, recording its id.
private struct CountingLeaf: Element {
    @State var count = 0
    let ids: IDLog
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        ids.last = id
        let count = _count
        var handlers = Handlers()
        handlers.onClick = { count.wrappedValue += 1 }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor private final class IDLog {
    var last: GlobalElementID?
}

/// **2.27** (`AS-D` item 6, `AS-G` item 1, spec §9). Content under
/// `.navigationTitle`, `.navigationDocument` and `.onOpenURL` has the same
/// `GlobalElementID` as without them — the scopes mint no id and consume no
/// cursor index — and its `@State` survives a change of the title.
/// Mutation: bump the cursor in the scope.
@MainActor
@Test func theWindowPreferenceScopesAreTransparent() throws {
    let (app, platform) = try shellApp()
    let plain = IDLog(), scoped = IDLog()
    _ = try app.openWindow(title: "P", size: Size(width: px(64), height: px(64)), startsDisplayLink: false) {
        Column { Box().frame(width: px(4), height: px(4)); CountingLeaf(ids: plain) }
    }
    let model = TitleModel()
    let window = try app.openWindow(title: "S", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column {
            Box().frame(width: px(4), height: px(4))
            CountingLeaf(ids: scoped)
                .navigationTitle(model.title)
                .navigationDocument(fileURL)
                .onOpenURL { _ in }
        }
    }
    let plainID = try #require(plain.last)
    let scopedID = try #require(scoped.last)
    #expect(plainID == scopedID, "the scopes are not levels: \(plainID) vs \(scopedID)")

    let fake = try #require(platform.openedWindows.last)
    let hit = try #require(window.lastHitboxes.first { $0.id == scopedID })
    let centre = Point(x: hit.bounds.origin.x + px(10), y: hit.bounds.origin.y + px(10))
    fake.simulateInput(.mouseDown(MouseEvent(position: centre)))
    fake.simulateInput(.mouseUp(MouseEvent(position: centre)))
    window.drawFrameIfNeeded()
    let slot = GlobalElementID.child(of: scopedID, at: 0, name: ElementID("$state0"))
    #expect(window.stateTable.peek(slot, as: Int.self) == 1)
    model.title = "b"
    window.drawFrameIfNeeded()
    #expect(fake.title == "b")
    #expect(scoped.last == scopedID)
    #expect(window.stateTable.peek(slot, as: Int.self) == 1, "a changed title keeps the state below it")
}
