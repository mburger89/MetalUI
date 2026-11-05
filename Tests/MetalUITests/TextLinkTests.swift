import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUITextSystem
@testable import MetalUI

// Clickable text links (round 4 item R4-4 PR D; rulings `LI-A`..; divergence 150 retired, row 218 added). SwiftUI's
// answers are the probe `docs/probes/swiftui-text-links.swift`; each test names its arm. Windows are 300 x 300 over
// `FakePlatformWindow`, which records `openURL` and opens nothing: **no test here reaches `NSWorkspace`**.

// MARK: - Harness

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

/// `see docs now` with `docs` a link to `dest`.
@MainActor
private func linkText(_ dest: String = "https://x.org") -> Text {
    Text(content: .runs([TextRunRequest(string: "see "), TextRunRequest(string: "docs", link: dest),
                         TextRunRequest(string: " now")]))
}

@MainActor
private func linkWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 300, content: content)
    window.drawFrameIfNeeded()
    for _ in 0..<4 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

/// The link hitboxes of the last frame, in registration order.
@MainActor
private func linkBoxes(_ window: Window) -> [Hitbox] {
    window.lastHitboxes.filter { hit in
        if case .named(let name) = hit.id.component, name.name.hasPrefix("$link") { return hit.handlers.onClick != nil }
        return false
    }
}

private func centre(_ rect: Bounds<Pixels>) -> Point<Pixels> {
    pt(rect.origin.x.value + rect.size.width.value / 2, rect.origin.y.value + rect.size.height.value / 2)
}

@MainActor
private func click(_ platform: FakePlatformWindow, _ point: Point<Pixels>, count: Int = 1) {
    var event = MouseEvent(position: point)
    event.clickCount = count
    platform.simulateInput(.mouseDown(event))
    platform.simulateInput(.mouseUp(event))
}

/// A point on the text's line, left of the link: inside "see ", off the run.
@MainActor
private func offRun(_ window: Window) throws -> Point<Pixels> {
    let box = try #require(linkBoxes(window).first, "no link hitbox").bounds
    return pt(Swift.max(box.origin.x.value - 8, 1), box.origin.y.value + box.size.height.value / 2)
}

/// An action that records its URLs and answers `result`.
@MainActor
private final class LinkRecorder {
    var urls: [String] = []
    func action(_ result: OpenURLAction.Result) -> OpenURLAction {
        OpenURLAction { url in
            self.urls.append(url.absoluteString)
            return result
        }
    }
}

// MARK: - The click

/// **LK0, LK1.** A click on a link run asks the platform to open its URL, once; a click on the text beside it asks for
/// nothing. Mutations: register no link region (the first expectation reddens), a rect for the whole text (the second).
@MainActor
@Test func aClickOnALinkRunOpensItsURLAndOneOffTheRunDoesNot() throws {
    let (window, platform) = try linkWindow { Row { linkText() }.alignItems(.flexStart) }
    let box = try #require(linkBoxes(window).first)
    click(platform, try offRun(window))
    #expect(platform.openedURLs == [], "LK1: off the run: \(platform.openedURLs)")
    click(platform, centre(box.bounds))
    #expect(platform.openedURLs == ["https://x.org"], "LK0: on the run: \(platform.openedURLs)")
    withExtendedLifetime(window) {}
}

/// **LK4, LK5, LK5b, LK6.** Press on the run and release off it, press off and release on, press on one link and
/// release on another, and a right press: none opens.
/// Mutation: drop the pressed-id test in `Window.dispatchClick` (LK4 and LK5 redden).
@MainActor
@Test func onlyAPressAndReleaseOnTheRunOpensIt() throws {
    let (window, platform) = try linkWindow { Row { linkText() }.alignItems(.flexStart) }
    let on = centre(try #require(linkBoxes(window).first).bounds)
    let off = try offRun(window)
    platform.simulateInput(.mouseDown(MouseEvent(position: on)))
    platform.simulateInput(.mouseUp(MouseEvent(position: off)))
    #expect(platform.openedURLs == [], "LK4: press on, release off")
    platform.simulateInput(.mouseDown(MouseEvent(position: off)))
    platform.simulateInput(.mouseUp(MouseEvent(position: on)))
    #expect(platform.openedURLs == [], "LK5: press off, release on")
    platform.simulateInput(.rightMouseDown(MouseEvent(position: on)))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: on)))
    #expect(platform.openedURLs == [], "LK6: a right press")
    withExtendedLifetime(window) {}

    // Two links: a press on one and a release on the other opens neither (the pressed-id rule of `dispatchClick`; the
    // single-link arms above cannot separate it, because a press off the run leaves nothing pressed).
    let two = Text(content: .runs([TextRunRequest(string: "aa", link: "https://a.org"), TextRunRequest(string: " "),
                                   TextRunRequest(string: "bb", link: "https://b.org")]))
    let (twoWindow, twoPlatform) = try linkWindow { Row { two }.alignItems(.flexStart) }
    let boxes = linkBoxes(twoWindow).sorted { $0.bounds.origin.x.value < $1.bounds.origin.x.value }
    try #require(boxes.count == 2, "two links: \(boxes.count)")
    twoPlatform.simulateInput(.mouseDown(MouseEvent(position: centre(boxes[0].bounds))))
    twoPlatform.simulateInput(.mouseUp(MouseEvent(position: centre(boxes[1].bounds))))
    #expect(twoPlatform.openedURLs == [], "LK5b: press on one link, release on the other: \(twoPlatform.openedURLs)")
    click(twoPlatform, centre(boxes[1].bounds))
    #expect(twoPlatform.openedURLs == ["https://b.org"], "control: the second link alone opens its own URL")
    withExtendedLifetime(twoWindow) {}
}

/// **LK8.** `.allowsHitTesting(false)` withdraws the region. Mutation: register outside the pointer gate.
@MainActor
@Test func aLinkUnderAllowsHitTestingFalseOpensNothing() throws {
    let (window, platform) = try linkWindow { Row { linkText().allowsHitTesting(false) }.alignItems(.flexStart) }
    #expect(linkBoxes(window).isEmpty, "no hitbox: \(linkBoxes(window).count)")
    click(platform, pt(40, 10))
    #expect(platform.openedURLs == [])
    withExtendedLifetime(window) {}
}

/// **LK19.** A double click opens twice (the press and release of each click are one activation).
@MainActor
@Test func aDoubleClickOnALinkOpensItTwice() throws {
    let (window, platform) = try linkWindow { Row { linkText() }.alignItems(.flexStart) }
    let on = centre(try #require(linkBoxes(window).first).bounds)
    click(platform, on, count: 1)
    click(platform, on, count: 2)
    #expect(platform.openedURLs == ["https://x.org", "https://x.org"], "\(platform.openedURLs)")
    withExtendedLifetime(window) {}
}

// MARK: - The action

/// **The result decides what reaches the platform** (`LI-D`). `.handled` and `.discarded` ask it for nothing
/// (probe `LK14`, `LK14b`); `.systemAction` asks for the link's URL, `.systemAction(_:)` for the one it names; the
/// action runs once with the URL as written, a scheme-less one (`LK20`) and a custom scheme (`LK21`) included.
/// Mutation: call the platform on `.handled` (the first row).
@MainActor
@Test func theActionsResultDecidesWhatReachesThePlatform() throws {
    func run(_ result: OpenURLAction.Result, _ dest: String = "https://x.org") throws -> (urls: [String], opened: [String]) {
        let recorder = LinkRecorder()
        let action = recorder.action(result)
        let (window, platform) = try linkWindow { Row { linkText(dest) }.alignItems(.flexStart).environment(\.openURL, action) }
        click(platform, centre(try #require(linkBoxes(window).first).bounds))
        withExtendedLifetime(window) {}
        return (recorder.urls, platform.openedURLs)
    }
    let handled = try run(.handled)
    #expect(handled.urls == ["https://x.org"] && handled.opened == [], "LK14-handled: \(handled)")
    let discarded = try run(.discarded)
    #expect(discarded.urls == ["https://x.org"] && discarded.opened == [], "LK14: \(discarded)")
    let system = try run(.systemAction)
    #expect(system.urls == ["https://x.org"] && system.opened == ["https://x.org"], "systemAction: \(system)")
    let other = try run(.systemAction(URL(string: "https://other.org")!))
    #expect(other.opened == ["https://other.org"], "systemAction(_:): \(other)")
    let custom = try run(.handled, "probe://x")
    #expect(custom.urls == ["probe://x"], "LK21: a custom scheme reaches the action: \(custom)")
    let bare = try run(.handled, "example.com")
    #expect(bare.urls == ["example.com"], "LK20: a scheme-less destination reaches the action: \(bare)")
}

/// **LK15, LK14b.** The nearest `\.openURL` runs, and an outer one does not run after an inner `.discarded`.
/// Mutation: run every enclosing action.
@MainActor
@Test func theNearestActionRunsAndNoOuterOneFollows() throws {
    let inner = LinkRecorder(), outer = LinkRecorder()
    let (window, platform) = try linkWindow {
        Row { linkText() }.alignItems(.flexStart)
            .environment(\.openURL, inner.action(.discarded))
            .environment(\.openURL, outer.action(.handled))
    }
    // `.environment` is outermost-last: the second call wraps the first, so `inner` is the nearer writer.
    click(platform, centre(try #require(linkBoxes(window).first).bounds))
    #expect(inner.urls == ["https://x.org"], "the nearer action ran: \(inner.urls)")
    #expect(outer.urls == [], "the outer one did not: \(outer.urls)")
    #expect(platform.openedURLs == [])
    withExtendedLifetime(window) {}
}

/// **A window's default action** opens through the platform window; one that outlives the window opens nothing and
/// holds no cycle (`LI-D`). Mutation: capture the platform window strongly (the weak read-back reddens).
@MainActor
@Test func theDefaultActionHoldsThePlatformWindowWeakly() throws {
    weak var weakPlatform: FakePlatformWindow?
    var opener: URLOpener?
    do {
        let (window, platform) = try linkWindow { Row { linkText() }.alignItems(.flexStart) }
        weakPlatform = platform
        opener = window.urlOpener
        #expect(opener?.open(URL(string: "https://x.org")!) == true)
        #expect(platform.openedURLs == ["https://x.org"])
    }
    #expect(weakPlatform == nil, "the opener does not keep the platform window alive")
    #expect(opener?.open(URL(string: "https://x.org")!) == false, "and opens nothing once it is gone")
}

// MARK: - Wrapping, bidi, ranking

/// **LK12.** A run wrapped over two lines has one piece per line: a click on each opens, a click on the text beside
/// the run on either line does not. Mutations: one rect per run (the union covers the text before the run on line 1),
/// a wrong line top (the second piece is a line high).
@MainActor
@Test func aWrappedRunOpensOverEachOfItsPiecesOnly() throws {
    let text = Text(content: .runs([TextRunRequest(string: "aa "),
                                    TextRunRequest(string: "bb cc dd", link: "https://w.org"),
                                    TextRunRequest(string: " ee")]))
    let (window, platform) = try linkWindow { Row { text.frame(width: Pixels(60)) }.alignItems(.flexStart) }
    let boxes = linkBoxes(window)
    try #require(boxes.count == 2, "two pieces: \(boxes.map(\.bounds))")
    #expect(boxes[0].id == boxes[1].id, "under one id")
    let first = boxes[0].bounds, second = boxes[1].bounds
    #expect(second.origin.y.value > first.origin.y.value + first.size.height.value - 1, "the second piece is on the next line")
    for piece in [first, second] {
        click(platform, centre(piece))
    }
    #expect(platform.openedURLs == ["https://w.org", "https://w.org"], "\(platform.openedURLs)")
    platform.openedURLs.removeAll()
    click(platform, pt(2, first.origin.y.value + 3))   // "aa " before the run on line 1
    click(platform, pt(first.origin.x.value + first.size.width.value + 2, second.origin.y.value + 3))   // right of the piece on line 2
    #expect(platform.openedURLs == [], "off the pieces: \(platform.openedURLs)")
    withExtendedLifetime(window) {}
}

/// **O0, O1, O2.** The link beats a tap on the `Text`, on an ancestor, and a `Button` label; off the run those
/// fire. **O5:** a tap on an overlay ABOVE the text wins. Mutation: register the link hitbox before the element's
/// own (the tap fires too).
@MainActor
@Test func aLinkBeatsTheTapsBelowItAndAnOverlayTapAboveBeatsTheLink() throws {
    let log = LinkLog()
    func probe<E: Element>(_ label: String, _ make: @escaping @MainActor () -> E, onRun: [String], offRun expectedOff: [String],
                           sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (window, platform) = try linkWindow(make)
        log.entries = []
        platform.openedURLs = []
        click(platform, centre(try #require(linkBoxes(window).first, sourceLocation: sourceLocation).bounds))
        #expect(log.entries + platform.openedURLs.map { _ in "open" } == onRun, "\(label) on the run: \(log.entries) \(platform.openedURLs)",
                sourceLocation: sourceLocation)
        log.entries = []
        platform.openedURLs = []
        click(platform, try offRun(window))
        #expect(log.entries + platform.openedURLs.map { _ in "open" } == expectedOff, "\(label) off the run: \(log.entries)",
                sourceLocation: sourceLocation)
        withExtendedLifetime(window) {}
    }
    try probe("O0 Text.onTapGesture", { Row { linkText().onTapGesture { log.entries.append("tap") } }.alignItems(.flexStart) },
              onRun: ["open"], offRun: ["tap"])
    try probe("O1 Button label", { Row { Button(action: { log.entries.append("tap") }) { linkText() } }.alignItems(.flexStart) },
              onRun: ["open"], offRun: ["tap"])
    try probe("O2 ancestor tap", { Row { Row { linkText() }.alignItems(.flexStart) }.alignItems(.flexStart)
                .onTapGesture { log.entries.append("tap") } },
              onRun: ["open"], offRun: ["tap"])
    try probe("O5 overlay tap above", { Row { linkText().overlay { Box().frame(width: Pixels(300), height: Pixels(300)).onTapGesture { log.entries.append("tap") } } }.alignItems(.flexStart) },
              onRun: ["tap"], offRun: ["tap"])
}

@MainActor private final class LinkLog { var entries: [String] = [] }

/// **O6, O6b.** A `simultaneousGesture(TapGesture)` on the `Text` fires beside the link, the tap first; a
/// `highPriorityGesture` fires and the link does not open (probe `O6`, `O6b`). Mutation: the link hitbox swallows the
/// click before the gesture arena (O6 reads `["open"]`).
@MainActor
@Test func aSimultaneousTapFiresBesideALinkAndAHighPriorityOneInsteadOfIt() throws {
    let log = LinkLog()
    let record = OpenURLAction { _ in log.entries.append("open"); return .handled }
    func run<E: Element>(_ make: @escaping @MainActor () -> E) throws -> [String] {
        log.entries = []
        let (window, platform) = try linkWindow(make)
        click(platform, centre(try #require(linkBoxes(window).first).bounds))
        withExtendedLifetime(window) {}
        return log.entries
    }
    #expect(try run {
        Row { linkText().simultaneousGesture(TapGesture().onEnded { log.entries.append("tap") }) }
            .alignItems(.flexStart).environment(\.openURL, record)
    } == ["tap", "open"], "O6")
    #expect(try run {
        Row { linkText().highPriorityGesture(TapGesture().onEnded { log.entries.append("tap") }) }
            .alignItems(.flexStart).environment(\.openURL, record)
    } == ["tap"], "O6b")
}

/// **Bidi: two pieces, one id.** In a right-to-left paragraph a link run that contains left-to-right and right-to-left
/// text is laid out as two visual pieces with another run between them; each piece opens, the gap between them does
/// not, and both are under one run id. Mutation: one rect per run (the gap opens).
@MainActor
@Test func aBidiRunWithTwoVisualPiecesHasTwoRegionsUnderOneID() throws {
    let text = Text(content: .runs([TextRunRequest(string: "\u{05D0}\u{05D1} ab "),
                                    TextRunRequest(string: "cd \u{05D2}\u{05D3} ef", link: "https://bidi.org"),
                                    TextRunRequest(string: " \u{05D4}")]))
    let (window, platform) = try linkWindow { Row { text }.alignItems(.flexStart) }
    let boxes = linkBoxes(window).sorted { $0.bounds.origin.x.value < $1.bounds.origin.x.value }
    try #require(boxes.count == 2, "two visual pieces: \(boxes.map(\.bounds))")
    #expect(boxes[0].id == boxes[1].id, "under one id")
    for box in boxes { click(platform, centre(box.bounds)) }
    #expect(platform.openedURLs == ["https://bidi.org", "https://bidi.org"], "\(platform.openedURLs)")
    platform.openedURLs.removeAll()
    let gap = (boxes[0].bounds.origin.x.value + boxes[0].bounds.size.width.value + boxes[1].bounds.origin.x.value) / 2
    click(platform, pt(gap, boxes[0].bounds.origin.y.value + 4))
    #expect(platform.openedURLs == [], "between the pieces: \(platform.openedURLs)")
    withExtendedLifetime(window) {}
}

// MARK: - Focus, AX, the cursor

/// **LK23.** A click on a link leaves a focused field focused (probe: `focused=true` and no `false` after the
/// click, the control click on a second focusable moves it). Mutation: the link region takes click focus.
@MainActor
@Test func aClickOnALinkDoesNotMoveAFocusedField() throws {
    let (window, platform) = try linkWindow {
        Column {
            linkText()
            TextField("t", text: "abc") { _ in }.frame(width: Pixels(200), height: Pixels(24))
        }.alignItems(.flexStart)
    }
    let field = try #require(window.lastFocusRegistry.tabOrder.first, "the field is a stop")
    window.focus(field)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == field, "control: the field holds focus before the click")
    click(platform, centre(try #require(linkBoxes(window).first).bounds))
    #expect(platform.openedURLs == ["https://x.org"])
    #expect(window.focusedElement == field, "the field keeps focus: \(String(describing: window.focusedElement))")
    withExtendedLifetime(window) {}
}

/// Renders `element` into a collecting `Frame` and builds the tree as `Window.drawFrameIfNeeded` does.
@MainActor
private func collect<E: Element>(_ element: E) -> (Frame, AccessibilityTree) {
    var element = element
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)), scaleFactor: 1,
                      theme: Theme.forAppearance(.light), collectsAccessibility: true)
    frame.render(&element)
    let tree = AccessibilityTreeBuilder.build(emissions: frame.axEmissions, focused: frame.focusedElement,
                                              hitboxes: frame.hitboxes, focusRegistry: frame.focusRegistry)
    return (frame, tree)
}

/// **AX.** `two aa and bb` with two links publishes the text with its whole string and, under it, one link per run
/// labelled with its text, each pressable (probe `AX1`: `AXStaticText` with `AXLink` children). The press runs the
/// action. Mutations: drop the AX record (no children), label with the whole string.
@MainActor
@Test func aTextWithTwoLinksPublishesTwoLinkChildren() throws {
    let text = Text(content: .runs([TextRunRequest(string: "two "), TextRunRequest(string: "aa", link: "https://a.org"),
                                    TextRunRequest(string: " and "), TextRunRequest(string: "bb", link: "probe://b")]))
    let (frame, tree) = collect(rtTopLeft(text))
    let root = try #require(tree.nodes.values.first { $0.value == "two aa and bb" }, "the text keeps its string as its value")
    #expect(root.role == .staticText)
    let children = root.children.compactMap { tree.nodes[$0] }
    #expect(children.map(\.label) == ["aa", "bb"], "\(children.map(\.label))")
    #expect(children.map(\.role) == [.link, .link], "\(children.map(\.role))")
    #expect(children.allSatisfy { $0.actions.contains(.press) }, "each link advertises a press")
    #expect(frame.axNodes.isEmpty, "a synthesized record writes no `axNodes` entry (AB-U)")
    let (_, idle) = collect(rtTopLeft(text), collecting: false)
    #expect(idle.nodes.isEmpty, "with no client nothing is recorded")
}

@MainActor
private func collect<E: Element>(_ element: E, collecting: Bool) -> (Frame, AccessibilityTree) {
    var element = element
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)), scaleFactor: 1,
                      theme: Theme.forAppearance(.light), collectsAccessibility: collecting)
    frame.render(&element)
    return (frame, AccessibilityTreeBuilder.build(emissions: frame.axEmissions, focused: nil, hitboxes: frame.hitboxes,
                                                  focusRegistry: frame.focusRegistry))
}

/// **LI-F.** Each link region carries the pointing-hand style and nothing else carries one: the cursor over the run
/// is `.link`, over the text beside it the default. (A person confirms the look, human check LI1.)
@MainActor
@Test func aLinkRegionCarriesThePointingHandStyle() throws {
    let (window, platform) = try linkWindow { Row { linkText() }.alignItems(.flexStart) }
    let styled = window.lastHitboxes.filter { $0.handlers.pointer?.style != nil }
    try #require(styled.count == 1, "one pointer-style region: \(styled.count)")
    #expect(styled[0].bounds == linkBoxes(window)[0].bounds, "at the run's piece")
    platform.simulateInput(.mouseMoved(MouseEvent(position: centre(styled[0].bounds))))
    #expect(platform.pointerStyles.last == .pointingHand, "over the run: \(String(describing: platform.pointerStyles.last))")
    platform.simulateInput(.mouseMoved(MouseEvent(position: try offRun(window))))
    #expect(platform.pointerStyles.last == .arrow, "off it: \(String(describing: platform.pointerStyles.last))")
    withExtendedLifetime(window) {}
}

// MARK: - The proposal path, the work count, row 218

/// **The proposal bridge registers the same regions** (`LI-A`: `ProposalText.prepaint` as `Text.prepaint`): a link
/// run in a `VStack` opens on its piece and not beside it, and publishes its link under the text's record. Mutation:
/// drop the registration in `ProposalText.prepaint` (the click opens nothing).
@MainActor
@Test func aProposalTextRegistersTheSameLinkRegions() throws {
    let (window, platform) = try linkWindow { VStack(alignment: .leading) { linkText().proposalLayout() } }
    let boxes = linkBoxes(window)
    try #require(boxes.count == 1, "one piece: \(boxes.count)")
    click(platform, try offRun(window))
    #expect(platform.openedURLs == [])
    click(platform, centre(boxes[0].bounds))
    #expect(platform.openedURLs == ["https://x.org"], "\(platform.openedURLs)")
    // And the same geometry as the legacy path: the run starts after "see " at the same x.
    let (legacy, _) = try linkWindow { Row { linkText() }.alignItems(.flexStart) }
    let a = boxes[0].bounds, b = try #require(linkBoxes(legacy).first).bounds
    #expect(a.origin.x == b.origin.x && a.size.width == b.size.width, "x and width agree: \(a) vs \(b)")
    withExtendedLifetime((window, legacy)) {}
}

/// **A plain `Text` does no extra work** (`RT-M`, `LI-A`). Over the spy text system, a styled text with no link lays
/// out once (paint's) and a text with a link twice (the prepaint's registration, at paint's own width), and the
/// environment is snapshotted once more; a plain `Text` makes no styled call at all. Mutation: resolve and register
/// for every `Text` (the unlinked counts rise by the snapshot and the layout).
@MainActor
@Test func aTextWithoutALinkDoesNoLinkWork() throws {
    func work(_ text: Text) -> (layOuts: Int, styled: Int, snapshots: Int) {
        let spy = RichTextSpySystem()
        let frame = rtFrame(rtTopLeft(text), system: spy)
        return (spy.styledCalls.filter { $0 == "layOut" }.count, spy.styledCalls.count, frame.environmentSnapshotCount)
    }
    let bold = Text(content: .runs([TextRunRequest(string: "see "), TextRunRequest(string: "docs", weight: .bold)]))
    let linked = Text(content: .runs([TextRunRequest(string: "see "), TextRunRequest(string: "docs", link: "https://x.org")]))
    let styled = work(bold), link = work(linked), plain = work(Text("see docs"))
    #expect(plain.styled == 0, "a plain Text makes no styled call: \(plain)")
    #expect(styled.layOuts == 1, "paint's one layOut: \(styled)")
    #expect(link.layOuts == 2, "paint's and the registration's: \(link)")
    #expect(link.snapshots == styled.snapshots + 1, "one environment read more: \(styled) vs \(link)")
}

/// **Row 218** (divergence, pinned wrong on purpose): `.disabled(true)` withdraws the link's region where SwiftUI
/// still opens it (probe `LK7`, and a disabled `Button`'s label, `O3`). The link is inert, registers no region and
/// opens nothing; the enabled control opens. A fix (register the link outside the disabled gate) reddens this and
/// retires the row. Mutation: ignore the disabled gate.
@MainActor
@Test func aLinkUnderDisabledIsInertWhereSwiftUIOpensIt() throws {
    let (enabled, enabledPlatform) = try linkWindow { Row { linkText() }.alignItems(.flexStart) }
    click(enabledPlatform, centre(try #require(linkBoxes(enabled).first).bounds))
    try #require(enabledPlatform.openedURLs == ["https://x.org"], "control: enabled opens")
    let (disabled, platform) = try linkWindow { Row { linkText() }.alignItems(.flexStart).disabled(true) }
    #expect(linkBoxes(disabled).isEmpty, "row 218: a disabled link registers no region")
    click(platform, pt(40, 8))
    #expect(platform.openedURLs == [], "row 218: and opens nothing (SwiftUI LK7 opens)")
    withExtendedLifetime((enabled, disabled)) {}
}

/// **A drag inside the run opens, as SwiftUI's does** (probe `O9`, `O9b`, `O9c`: the plan's "does not open" is not
/// reproduced, and the control `O9d` shows the drag events arrive). Press, move 25 points inside the run, release
/// inside it: opens once. Mutation: cancel the click when the pointer moved.
@MainActor
@Test func aDragInsideTheRunStillOpensIt() throws {
    let text = Text(content: .runs([TextRunRequest(string: "a very long link run indeed", link: "https://x.org")]))
    let (window, platform) = try linkWindow { Row { text }.alignItems(.flexStart) }
    let box = try #require(linkBoxes(window).first).bounds
    let y = box.origin.y.value + box.size.height.value / 2
    let from = pt(box.origin.x.value + 10, y)
    platform.simulateInput(.mouseDown(MouseEvent(position: from)))
    platform.simulateInput(.mouseDragged(MouseEvent(position: pt(from.x.value + 25, y))))
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(from.x.value + 25, y))))
    #expect(platform.openedURLs == ["https://x.org"], "\(platform.openedURLs)")
    withExtendedLifetime(window) {}
}

/// **An accessibility press on a link runs its action** (`AB-H`: the press is derived from the link's hitboxes). A
/// client activates, the window publishes `see docs now` with a link child labelled `docs`, and `.press` on that node
/// asks the platform to open the URL. Mutation: publish the link without its hitboxes (no press, nothing opens).
@MainActor
@Test func anAccessibilityPressOnALinkOpensIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 300) { Row { linkText() }.alignItems(.flexStart) }
    _ = platform.onAccessibilityRequest?(.activate)
    window.drawFrameIfNeeded()
    for _ in 0..<3 where window.needsRedraw { window.drawFrameIfNeeded() }
    let tree = try #require(platform.publishedAccessibilityTrees.last, "a tree was published")
    let link = try #require(tree.nodes.first { $0.value.role == .link }, "a link node")
    #expect(link.value.label == "docs")
    #expect(link.value.actions.contains(.press))
    #expect(platform.onAccessibilityRequest?(.press(link.key)) == true)
    #expect(platform.openedURLs == ["https://x.org"], "\(platform.openedURLs)")
    withExtendedLifetime(window) {}
}
