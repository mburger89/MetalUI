import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// `DropDelegate` (record 192, rulings `DE-A`…`DE-J`). Every SwiftUI answer is an
// arm of `docs/probes/swiftui-drop-delegate.swift` (named per test). Everything
// runs through a real `Window` on a `FakePlatformWindow` (400 × 200), driven by
// `simulateInput`/`simulateDrop` — nothing sleeps. The fixture is a 200 × 200
// source at the left and a 200 × 200 destination at the right.

// MARK: - Fixtures

@MainActor
private final class DLog { var entries: [String] = [] }

/// A delegate that logs every callback (`V`alidate, `E`ntered, `U`pdated,
/// e`X`ited, `P`erform) and answers what its fields say.
@MainActor
private final class DelegateProbe: DropDelegate {
    let name: String
    let log: DLog
    var validates = true
    var proposal: DropProposal?
    var performs = true
    var infos: [(String, DropInfo)] = []
    var types: [ContentType] = [.plainText]
    init(_ name: String = "", log: DLog) { self.name = name; self.log = log }

    private func note(_ tag: String, _ info: DropInfo) {
        log.entries.append(name + tag)
        infos.append((tag, info))
    }
    func validateDrop(info: DropInfo) -> Bool { note("V", info); return validates }
    func dropEntered(info: DropInfo) { note("E", info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { note("U", info); return proposal }
    func dropExited(info: DropInfo) { note("X", info) }
    func performDrop(info: DropInfo) -> Bool { note("P", info); return performs }
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h)))
}
private func down(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y), clickCount: 1)) }
private func up(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y), clickCount: 1)) }
private func drag(_ x: Float, _ y: Float) -> InputEvent { .mouseDragged(MouseEvent(position: pt(x, y))) }
private func escape() -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: "\u{1b}", characters: "\u{1b}", timestamp: 0))
}
private let right = rect(200, 0, 200, 200)

@MainActor
private func dndWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true,
                                                content: content)
    platform.simulateResize(to: Size(width: px(400), height: px(200)))
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor
private func square() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200))
}

/// A 200 × 200 delegate destination for `.plainText`.
@MainActor
private func well(_ probe: DelegateProbe) -> ModifiedElement<Box<EmptyGroup>> {
    square().onDrop(of: probe.types, delegate: probe)
}

@MainActor
private func destinationRegions(_ window: Window) -> [Hitbox] {
    window.lastHitboxes.filter { !$0.opaque && $0.handlers.dropDestination != nil }
}

@MainActor private final class LoadLog { var loaded: [String] = [] }

private let pngType = ContentType("public.png", conformingTo: [.data])
private let png = PasteboardType(identifier: "public.png", conformsTo: ["public.image", "public.data", "public.item"])
private let utf8 = PasteboardType(identifier: "public.utf8-plain-text",
                                  conformsTo: ["public.plain-text", "public.text", "public.data", "public.item"])

@MainActor
private func item(_ types: [PasteboardType], text: String = "x", log: LoadLog = LoadLog()) -> DropItem {
    DropItem(types: types) { identifier in
        log.loaded.append(identifier)
        return Array(text.utf8)
    }
}
@MainActor private func textItem(_ text: String = "x") -> DropItem { item([utf8], text: text) }
@MainActor private func pngItem() -> DropItem { item([png]) }

@MainActor
private func dragAndDrop(_ platform: FakePlatformWindow, through path: [Point<Pixels>]) {
    platform.simulateInput(down(100, 100))
    for p in path { platform.simulateInput(.mouseDragged(MouseEvent(position: p))) }
    platform.simulateInput(.mouseUp(MouseEvent(position: path.last ?? pt(100, 100))))
}

// MARK: - Call order (`DE-B`; probe D0, D0x)

/// **DE-1** (`D0`). Entering runs validate, entered, updated; every move one
/// updated; the release one updated then perform and no exited — for an
/// external drag and for an in-window one.
/// Mutations: drop the same-id `dropUpdated`; call `dropUpdated` before `dropEntered`.
@Test @MainActor func aDelegateGetsValidateEnterUpdateThenUpdatePerMoveThenUpdatePerform() throws {
    do {
        let log = DLog()
        let probe = DelegateProbe(log: log)
        let (window, platform) = try dndWindow { Row { square(); well(probe) } }
        try #require(destinationRegions(window).map(\.bounds) == [right])
        #expect(platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()])))
        #expect(log.entries == ["V", "E", "U"])
        #expect(platform.simulateDrop(.moved(position: pt(310, 100))))
        #expect(log.entries == ["V", "E", "U", "U"])
        #expect(platform.simulateDrop(.performed(position: pt(310, 100), items: [textItem()])))
        #expect(log.entries == ["V", "E", "U", "U", "U", "P"], "drop = updated then perform, no exited")
    }
    do {
        let log = DLog()
        let probe = DelegateProbe(log: log)
        let (window, platform) = try dndWindow { Row { square().draggable("s"); well(probe) } }
        defer { withExtendedLifetime(window) {} }
        dragAndDrop(platform, through: [pt(110, 100), pt(300, 100), pt(310, 100)])
        #expect(log.entries == ["V", "E", "U", "U", "U", "P"], "in-window: the same order")
    }
}

/// **DE-2** (`D0x`, `F2`). Leaving sends only `dropExited`, before the next
/// destination's validate; so do Escape and a platform hand-off.
/// Mutation: `untarget()` skips a delegate.
@Test @MainActor func leavingSendsOnlyDropExitedBeforeTheNextDestinationsValidate() throws {
    do {
        let log = DLog()
        let a = DelegateProbe("A", log: log), b = DelegateProbe("B", log: log)
        let (window, platform) = try dndWindow { Row { well(a); well(b) } }
        defer { withExtendedLifetime(window) {} }
        platform.simulateDrop(.entered(position: pt(100, 100), items: [textItem()]))
        platform.simulateDrop(.moved(position: pt(300, 100)))
        #expect(log.entries == ["AV", "AE", "AU", "AX", "BV", "BE", "BU"])
        log.entries = []
        #expect(!platform.simulateDrop(.exited))
        #expect(log.entries == ["BX"], "leave = exited only")
    }
    do {
        let log = DLog()
        let probe = DelegateProbe(log: log)
        let (window, platform) = try dndWindow { Row { square().draggable("s"); well(probe) } }
        defer { withExtendedLifetime(window) {} }
        platform.simulateInput(down(100, 100))
        platform.simulateInput(drag(110, 100))
        platform.simulateInput(drag(300, 100))
        log.entries = []
        platform.simulateInput(escape())
        #expect(log.entries == ["X"], "Escape: exited, never performed")
    }
    do {
        let log = DLog()
        let probe = DelegateProbe(log: log)
        let (window, platform) = try dndWindow { Row { square().draggable("s"); well(probe) } }
        defer { withExtendedLifetime(window) {} }
        platform.externalDragResult = true
        platform.simulateInput(down(100, 100))
        platform.simulateInput(drag(110, 100))
        platform.simulateInput(drag(300, 100))
        log.entries = []
        platform.simulateInput(drag(300, 250))
        #expect(platform.externalDrags.count == 1)
        #expect(log.entries == ["X"], "the hand-off at the window edge exits the delegate")
    }
}

/// **DE-3** (`D1`, `F2`). `validateDrop` false: no entered, updated or perform,
/// the answer is none — and `dropExited` still runs on leaving.
/// Mutations: ignore the validate result; gate `dropExited` on validated.
@Test @MainActor func validateFalseSuppressesEnterUpdateAndPerformButNotExit() throws {
    let log = DLog()
    let probe = DelegateProbe(log: log)
    probe.validates = false
    let (window, platform) = try dndWindow { Row { square(); well(probe) } }
    defer { withExtendedLifetime(window) {} }
    #expect(!platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()])), "answers none")
    #expect(platform.dropOperations.last == PlatformDropOperation.none)
    #expect(!platform.simulateDrop(.moved(position: pt(310, 100))))
    #expect(log.entries == ["V"], "no E, no U")
    platform.simulateDrop(.exited)
    #expect(log.entries == ["V", "X"], "F2: exited still runs")
    log.entries = []
    platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    #expect(!platform.simulateDrop(.performed(position: pt(300, 100), items: [textItem()])))
    #expect(log.entries == ["V", "X"], "no perform; the release exits")
}

/// **DE-4** (`F1`, `F1b`; `DN-F` item 2). Items conforming to none of the
/// declared types reach no callback and answer none; a refusing inner delegate
/// does not pass the drag to an outer `dropDestination`.
/// Mutation: `accepts` answers `true`.
@Test @MainActor func aDelegateIgnoresItemsNotConformingToItsTypes() throws {
    let log = DLog()
    let probe = DelegateProbe(log: log)
    let (window, platform) = try dndWindow { Row { square(); well(probe) } }
    defer { withExtendedLifetime(window) {} }
    #expect(!platform.simulateDrop(.entered(position: pt(300, 100), items: [pngItem()])))
    #expect(log.entries == [], "F1: nothing called")
    #expect(platform.dropOperations.last == PlatformDropOperation.none)

    let outerLog = DLog()
    let inner = DelegateProbe("i", log: outerLog)
    inner.types = [pngType]
    let (window2, platform2) = try dndWindow {
        Row {
            square()
            Column {
                Box().frame(width: px(100), height: px(100)).onDrop(of: inner.types, delegate: inner)
            }
            .frame(width: px(200), height: px(200), alignment: .topLeading)
            .dropDestination(for: String.self, action: { _, _ in outerLog.entries.append("outer"); return true })
        }
    }
    defer { withExtendedLifetime(window2) {} }
    #expect(!platform2.simulateDrop(.entered(position: pt(250, 50), items: [textItem()])))
    #expect(!platform2.simulateDrop(.performed(position: pt(250, 50), items: [textItem()])))
    #expect(outerLog.entries == [], "a refusing deepest destination passes nothing outward")
}

// MARK: - Proposals (`DE-D`; probe D2–D4, D9, F5–F7)

/// **DE-5** (`D2`, `D3`, `D4`, `D5`, `F5`, `F6`, `F7`). Each proposal's platform
/// operation and answer: nil and copy → copy, move → move, forbidden and
/// cancel → none; nil after a move is copy again.
/// Mutations: nil keeps the last operation; forbidden maps to copy.
@Test @MainActor func eachProposalMapsToItsPlatformOperation() throws {
    let table: [(String, DropProposal?, PlatformDropOperation)] = [
        ("nil", nil, .copy), ("copy", DropProposal(operation: .copy), .copy),
        ("move", DropProposal(operation: .move), .move),
        ("forbidden", DropProposal(operation: .forbidden), .none),
        ("cancel", DropProposal(operation: .cancel), .none),
    ]
    for (name, proposal, expected) in table {
        let probe = DelegateProbe(log: DLog())
        probe.proposal = proposal
        let (window, platform) = try dndWindow { Row { square(); well(probe) } }
        defer { withExtendedLifetime(window) {} }
        let answer = platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
        #expect(platform.dropOperations.last == expected, "\(name)")
        #expect(answer == (expected != .none), "\(name): the answer")
    }
    // F5: move, then nil — copy again. F7: copy, forbidden, then nil.
    let probe = DelegateProbe(log: DLog())
    let (window, platform) = try dndWindow { Row { square(); well(probe) } }
    defer { withExtendedLifetime(window) {} }
    probe.proposal = DropProposal(operation: .move)
    platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    probe.proposal = nil
    platform.simulateDrop(.moved(position: pt(301, 100)))
    #expect(platform.dropOperations == [.move, .copy], "F5: nil is copy, not the last operation")
    probe.proposal = DropProposal(operation: .forbidden)
    platform.simulateDrop(.moved(position: pt(302, 100)))
    probe.proposal = nil
    platform.simulateDrop(.moved(position: pt(303, 100)))
    #expect(platform.dropOperations == [.move, .copy, .none, .copy], "F7: forbidden keeps asking")
}

/// **DE-6** (`D5`, `F4`). `.cancel` stops `dropUpdated` until the drag leaves;
/// re-entry validates again.
/// Mutation: omit `cancelled`.
@Test @MainActor func cancelStopsUpdatesUntilExitAndReEntryResets() throws {
    let log = DLog()
    let probe = DelegateProbe(log: log)
    probe.proposal = DropProposal(operation: .cancel)
    let (window, platform) = try dndWindow { Row { square(); well(probe) } }
    defer { withExtendedLifetime(window) {} }
    platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    platform.simulateDrop(.moved(position: pt(301, 100)))
    platform.simulateDrop(.moved(position: pt(302, 100)))
    #expect(log.entries == ["V", "E", "U"], "no further update")
    platform.simulateDrop(.exited)
    probe.proposal = nil
    platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    #expect(log.entries == ["V", "E", "U", "X", "V", "E", "U"], "re-entry resets")
    #expect(platform.dropOperations.last == .copy)
}

/// **DE-7** (`D4`, `D1`; AppKit's `prepareForDragOperation`). A release over a
/// forbidden, cancelled or invalid delegate performs nothing, exits, and
/// answers `false` — in-window and external.
/// Mutation: call `performDrop` regardless.
@Test @MainActor func aForbiddenCancelledOrInvalidReleasePerformsNothingAndExits() throws {
    for kind in ["forbidden", "cancel", "invalid"] {
        let log = DLog()
        let probe = DelegateProbe(log: log)
        switch kind {
        case "forbidden": probe.proposal = DropProposal(operation: .forbidden)
        case "cancel": probe.proposal = DropProposal(operation: .cancel)
        default: probe.validates = false
        }
        let (window, platform) = try dndWindow { Row { square().draggable("s"); well(probe) } }
        defer { withExtendedLifetime(window) {} }
        platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
        #expect(!platform.simulateDrop(.performed(position: pt(300, 100), items: [textItem()])), "\(kind)")
        #expect(!log.entries.contains("P"), "\(kind) external: \(log.entries)")
        #expect(log.entries.last == "X", "\(kind) external exits")
        log.entries = []
        dragAndDrop(platform, through: [pt(110, 100), pt(300, 100)])
        #expect(!log.entries.contains("P"), "\(kind) in-window: \(log.entries)")
        #expect(log.entries.last == "X", "\(kind) in-window exits")
    }
}

// MARK: - Perform (`DE-E`; probe D7, D0)

/// **DE-8** (`D7`, `R4`). The platform is told `performDrop`'s answer; a
/// `dropDestination` always answers `true`.
/// Mutation: return `true` after `performDrop`.
@Test @MainActor func performDropsBoolIsWhatThePlatformIsTold() throws {
    for answer in [true, false] {
        let probe = DelegateProbe(log: DLog())
        probe.performs = answer
        let (window, platform) = try dndWindow { Row { square(); well(probe) } }
        defer { withExtendedLifetime(window) {} }
        platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
        #expect(platform.simulateDrop(.performed(position: pt(300, 100), items: [textItem()])) == answer)
    }
    let (window, platform) = try dndWindow {
        Row { square(); square().dropDestination(for: String.self, action: { _, _ in false }) }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    #expect(platform.simulateDrop(.performed(position: pt(300, 100), items: [textItem()])),
            "R4: a destination's action returning false still answers true")
}

/// **DE-9** (`D0`). A performed drop sends no `dropExited`.
/// Mutation: `untarget()` before `performDrop`.
@Test @MainActor func performDropSendsNoDropExited() throws {
    let log = DLog()
    let probe = DelegateProbe(log: log)
    let (window, platform) = try dndWindow { Row { square(); well(probe) } }
    defer { withExtendedLifetime(window) {} }
    platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    platform.simulateDrop(.performed(position: pt(300, 100), items: [textItem()]))
    #expect(!log.entries.contains("X"), "\(log.entries)")
    #expect(window.dropTarget == nil, "and nothing stays targeted")
}

// MARK: - DropInfo (`DE-F`; probe D8, P12a)

/// **DE-10** (`P12a`). Every callback's `location` is local to the
/// destination: window (330, 140) on a destination at x = 200 reads (130, 140).
/// Mutation: pass the window point.
@Test @MainActor func dropInfoLocationIsLocalInEveryCallback() throws {
    let log = DLog()
    let probe = DelegateProbe(log: log)
    let (window, platform) = try dndWindow { Row { square(); well(probe) } }
    defer { withExtendedLifetime(window) {} }
    platform.simulateDrop(.entered(position: pt(330, 140), items: [textItem()]))
    platform.simulateDrop(.performed(position: pt(330, 140), items: [textItem()]))
    #expect(probe.infos.map(\.0) == ["V", "E", "U", "U", "P"])
    #expect(probe.infos.map(\.1.location) == Array(repeating: pt(130, 140), count: 5),
            "\(probe.infos.map(\.1.location))")
}

/// **DE-11** (`D8`, `F1b`). `hasItemsConforming` and `itemProviders` match by
/// conformance: two strings are two providers, `.item` finds a string, a png is
/// not plain text.
/// Mutation: match the identifier exactly.
@Test @MainActor func dropInfoMatchesByConformance() throws {
    let probe = DelegateProbe(log: DLog())
    let (window, platform) = try dndWindow { Row { square(); well(probe) } }
    defer { withExtendedLifetime(window) {} }
    platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem("a"), textItem("b"), pngItem()]))
    let info = try #require(probe.infos.first?.1)
    #expect(info.itemProviders(for: [.plainText]).count == 2)
    #expect(info.itemProviders(for: [.item]).count == 3, ".item finds them all")
    #expect(info.itemProviders(for: [pngType]).count == 1)
    #expect(info.hasItemsConforming(to: [.plainText]))
    #expect(!info.hasItemsConforming(to: [ContentType("com.adobe.pdf", conformingTo: [.data])]))
    let loaded = info.itemProviders(for: [.plainText]).compactMap { $0.load("public.utf8-plain-text") }
    #expect(loaded.map { String(decoding: $0, as: UTF8.self) } == ["a", "b"])
}

/// **DE-12** (divergence amendment 102). With the items unknown (SDL),
/// validate runs optimistically: `hasItemsConforming` answers `true` and
/// `itemProviders` is empty until `performDrop`, which sees the items.
/// Mutation: `hasItemsConforming` answers `false` on `nil`.
@Test @MainActor func sdlHoverIsOptimisticAndPerformSeesItems() throws {
    let probe = DelegateProbe(log: DLog())
    let (window, platform) = try dndWindow { Row { square(); well(probe) } }
    defer { withExtendedLifetime(window) {} }
    #expect(platform.simulateDrop(.entered(position: pt(300, 100), items: nil)))
    let hover = try #require(probe.infos.first?.1)
    #expect(hover.hasItemsConforming(to: [pngType]), "unknown items: optimistic")
    #expect(hover.itemProviders(for: [pngType]).isEmpty)
    platform.simulateDrop(.performed(position: pt(300, 100), items: [textItem()]))
    let performed = try #require(probe.infos.last?.1)
    #expect(probe.infos.last?.0 == "P")
    #expect(performed.itemProviders(for: [.plainText]).count == 1)
}

// MARK: - Coexistence (`DE-G`; probe F8–F10)

/// **DE-13** (`F8`, `F9`, `F10`). One element, two drop modifiers: the outermost wins.
/// Mutation: a second field instead of replacing.
@Test @MainActor func theOuterOfTwoDropModifiersOnOneElementWins() throws {
    let log = DLog()
    let a = DelegateProbe("A", log: log), b = DelegateProbe("B", log: log)
    let (w1, p1) = try dndWindow { Row { square(); square().onDrop(of: a.types, delegate: a).onDrop(of: b.types, delegate: b) } }
    defer { withExtendedLifetime(w1) {} }
    p1.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    #expect(log.entries == ["BV", "BE", "BU"], "F8: only B")
    log.entries = []
    let (w2, p2) = try dndWindow {
        Row {
            square()
            square().dropDestination(for: String.self, action: { _, _ in false }, isTargeted: { log.entries.append("T=\($0)") })
                .onDrop(of: b.types, delegate: b)
        }
    }
    defer { withExtendedLifetime(w2) {} }
    p2.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    #expect(log.entries == ["BV", "BE", "BU"], "F9: only B")
    log.entries = []
    let (w3, p3) = try dndWindow {
        Row {
            square()
            square().onDrop(of: a.types, delegate: a)
                .dropDestination(for: String.self, action: { _, _ in false }, isTargeted: { log.entries.append("T=\($0)") })
        }
    }
    defer { withExtendedLifetime(w3) {} }
    p3.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    #expect(log.entries == ["T=true"], "F10: only dropDestination")
}

/// **DE-14** (divergence 1057). The same on the proposal path, where two wrappers
/// register in nesting order: the outer wrapper wins for `onDrop(of:delegate:)`
/// and for `dropDestination`, as SwiftUI's does.
/// Mutation: the outer wrapper registers its region too (inner topmost).
@Test @MainActor func theOuterOfTwoProposalDropWrappersWins() throws {
    let log = DLog()
    let a = DelegateProbe("A", log: log), b = DelegateProbe("B", log: log)
    let (w1, p1) = try dndWindow { Rectangle().onDrop(of: a.types, delegate: a).onDrop(of: b.types, delegate: b) }
    defer { withExtendedLifetime(w1) {} }
    p1.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    #expect(log.entries == ["BV", "BE", "BU"], "delegate over delegate: \(log.entries)")
    log.entries = []
    let (w2, p2) = try dndWindow {
        Rectangle().dropDestination(for: String.self, action: { _, _ in false }, isTargeted: { log.entries.append("inner=\($0)") })
            .dropDestination(for: String.self, action: { _, _ in false }, isTargeted: { log.entries.append("outer=\($0)") })
    }
    defer { withExtendedLifetime(w2) {} }
    p2.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    #expect(log.entries == ["outer=true"], "dropDestination over dropDestination: \(log.entries)")
}

// MARK: - Gating (divergence 100, `R5d`)

/// **DE-15** (divergence 100). A disabled or hidden delegate is never validated.
/// Mutation: insert the destination region outside the gate.
@Test @MainActor func aDisabledOrHiddenDelegateIsNeverValidated() throws {
    @MainActor func check<Root: Element>(_ kind: String, _ make: @escaping @MainActor (DelegateProbe) -> Root) throws {
        let log = DLog()
        let probe = DelegateProbe(log: log)
        let (window, platform) = try dndWindow { make(probe) }
        defer { withExtendedLifetime(window) {} }
        #expect(destinationRegions(window).isEmpty, "\(kind): no region")
        #expect(!platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()])), "\(kind)")
        #expect(log.entries == [], "\(kind)")
    }
    try check("disabled") { probe in Row { square(); well(probe).disabled(true) } }
    try check("hidden") { probe in Row { square(); well(probe).hidden() } }
}

// MARK: - What must not move

/// **DE-16**. Transferable destinations still report copy over themselves and none elsewhere.
/// Mutation: report `.move` for a transferable.
@Test @MainActor func transferableDestinationsStillReportCopyOrNone() throws {
    let (window, platform) = try dndWindow {
        Row { square(); square().dropDestination(for: String.self, action: { _, _ in true }) }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateDrop(.entered(position: pt(300, 100), items: [textItem()]))
    platform.simulateDrop(.moved(position: pt(100, 100)))
    platform.simulateDrop(.moved(position: pt(300, 100)))
    #expect(platform.dropOperations == [.copy, .none, .copy])
}
