import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI
@testable import MetalUIText

// Lifecycle modifiers — `onAppear`, `onDisappear`, `onChange` (rulings `LC-A`…
// `LC-P`, `docs/superpowers/2026-10-03-lifecycle-decisions.md`; spec
// `docs/superpowers/specs/2026-10-03-lifecycle-design.md` §5.1, tests 1.1–8.2).
// SwiftUI's side is `docs/probes/swiftui-lifecycle.swift`; each test names the
// arm it follows.
//
// **No test sleeps.** Windows are `makeFakeWindowOnDefaultDevice` windows
// driven by `drawFrameIfNeeded()` — a model write between frames is the input
// — and transitions by `simulateTick(timestamp:)` (`LC-K`). Red before, for
// every test here: the file does not compile at `047f0ab` (no `onAppear`,
// `onDisappear`, `onChange` or `LifecycleStore`).

// MARK: - Harness

/// Every callback a test's tree fired, in order.
@MainActor final class LCLog {
    var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
    /// The entries added since the last call, emptied.
    func take() -> [String] {
        defer { entries.removeAll() }
        return entries
    }
}

/// The input every window test writes between frames — an `@Observable`
/// model, so a write dirties the window as a click handler's would.
@Observable @MainActor final class LCModel {
    var shown = false
    var flag = false
    var key = 0
    var value = 0
    var count = 0
    var width: Float = 10
    var level = 0
    var s1 = false
    var s2 = false
    var s3 = false
}

/// A weak handle to a window, for a tree whose action calls back into it.
@MainActor final class LCWindowRef {
    weak var window: Window?
}

/// A frame captured from inside a build (test 4.3).
@MainActor final class LCFrameRef {
    var frame: Frame?
}

/// The 10 × 10 accent tile every presence test toggles.
@MainActor func lcLeaf(_ w: Float = 10, _ h: Float = 10) -> some StyledElement {
    Box().frame(width: Pixels(w), height: Pixels(h)).background(.accent)
}

@MainActor func lcWindow<Root: Element>(size: Int = 200, startsDisplayLink: Bool = false,
                                        _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    try makeFakeWindowOnDefaultDevice(size: size, startsDisplayLink: startsDisplayLink, content: content)
}

private let lcRoot = GlobalElementID.child(of: nil, at: 0, name: nil)

/// The width of the one presented rect `height` tall, or `nil`.
@MainActor func lcWidth(_ window: Window, height: Float) -> Float? {
    let matches = window.lastScene.rects.filter { $0.bounds.size.height == height }
    return matches.count == 1 ? matches[0].bounds.size.width : nil
}

@MainActor private func isLCAccent(_ c: MUIHsla) -> Bool {
    let accent = Theme.light[.accent]
    return abs(c.h - accent.h) < 0.001 && abs(c.s - accent.s) < 0.001 && abs(c.l - accent.l) < 0.001
}

/// Element ids and the table's ids a headless frame records for `element`.
@MainActor private func lcIdentity<E: Element>(_ element: E) -> (bounds: Set<GlobalElementID>,
                                                                 table: Set<GlobalElementID>) {
    var root = element
    let table = StateTable()
    let frame = Frame(contentSize: Size(width: Pixels(300), height: Pixels(300)), scaleFactor: 1,
                      stateTable: table, recordsElementBounds: true)
    frame.render(&root)
    return (Set(frame.elementBounds.keys), table.ids)
}

/// A component with `@State` that writes it, so a reset or a kept value shows.
private struct LCCounter: Component {
    let label: String
    let log: LCLog
    @State var visits = 0
    var content: some ElementGroup {
        Box().frame(width: Pixels(10), height: Pixels(20))
            .onAppear { log.add("appear \(label) \(visits)"); visits += 1 }
            .onDisappear { log.add("disappear \(label) \(visits)") }
    }
}

/// Two leaves and no wrapper: a two-view group (`A6b`).
private struct LCPair: Component {
    var content: some ElementGroup {
        lcLeaf()
        lcLeaf()
    }
}

/// A component whose `@State` an `onAppear` sets, for the departed-state tests.
private struct LCHolder: Component {
    let log: LCLog
    @State var a = 0
    @State var b = 0
    var content: some ElementGroup {
        lcLeaf()
            .onAppear { log.add("appear a=\(a) b=\(b)"); a = 7 }
            .onDisappear { log.add("disappear a=\(a) b=\(b)"); a = 99; b = 99 }
    }
}

/// A component whose width an `onAppear` writes (test 4.1).
private struct LCPresenter: Component {
    @State var width: Float = 10
    var content: some ElementGroup {
        Box().frame(width: Pixels(width), height: Pixels(7)).background(.accent)
            .onAppear { width = 30 }
    }
}

/// A component whose `@State` an `onAppear` sets, read back through its width
/// (test 6.4): 50 wide fresh, 60 once its own `onAppear` ran.
private struct LCGrowingTile: Component {
    @State var grown = false
    var content: some ElementGroup {
        Box().frame(width: Pixels(grown ? 60 : 50), height: Pixels(30)).background(.accent)
            .onAppear { grown = true }
    }
}

/// An element that records the frame building it (test 4.3).
private struct LCFrameSpy: Element {
    let ref: LCFrameRef
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        ref.frame = pass.frame
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

private struct LCRow: Identifiable { let id: String }

// MARK: - Presence and identity (1.1–1.12)

/// **1.1** (`A1`, `LC-C` item 1). An `if` that inserts content runs its
/// `onAppear` once, however many frames follow. Mutation: `endFrame` treats
/// every `current` key as appearing.
@MainActor
@Test func anIfThatInsertsContentRunsItsOnAppearOnce() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow { Column { if m.shown { lcLeaf().onAppear { log.add("appear") } } } }
    window.drawFrameIfNeeded()
    try #require(log.entries.isEmpty, "set up: nothing present")
    m.shown = true
    for _ in 0..<3 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    #expect(log.entries == ["appear"], "\(log.entries)")
}

/// **1.2** (`E1`). An `if` that removes content runs its `onDisappear` once,
/// and nothing after. Mutation: delete the disappearance loop.
@MainActor
@Test func anIfThatRemovesContentRunsItsOnDisappearOnce() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, _) = try lcWindow { Column { if m.shown { lcLeaf().onDisappear { log.add("disappear") } } } }
    window.drawFrameIfNeeded()
    try #require(log.entries.isEmpty, "set up: present, nothing disappeared")
    m.shown = false
    for _ in 0..<3 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    #expect(log.entries == ["disappear"], "\(log.entries)")
}

/// **1.3** (`E2`, `LC-F`). A changed `.id` written outside the modifier is a
/// new element: the new one appears before the old one disappears. Mutation:
/// swap buckets 2 and 3.
@MainActor
@Test func aChangedIdRunsTheNewAppearBeforeTheOldDisappear() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            let k = m.key
            lcLeaf().onAppear { log.add("appear \(k)") }.onDisappear { log.add("disappear \(k)") }.id("k\(k)")
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.take() == ["appear 0"])
    m.key = 1
    window.drawFrameIfNeeded()
    #expect(log.entries == ["appear 1", "disappear 0"], "\(log.entries)")
}

/// **1.4** (`E3`–`E5`, `LC-C` item 1). Presence is membership, not
/// visibility: a hidden, a transparent, a zero-sized and a clipped-out element
/// each appear, and toggling an element's opacity fires nothing (`E4`).
/// Mutation: note from `paintGroup` instead of layout (hidden nodes skip paint).
@MainActor
@Test func hiddenTransparentZeroSizedAndClippedElementsAppear() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().hidden().onAppear { log.add("hidden") }
            lcLeaf().opacity(m.flag ? 1 : 0).onAppear { log.add("transparent") }.onDisappear { log.add("gone") }
            Box().frame(width: Pixels(0), height: Pixels(0)).onAppear { log.add("zero") }
            Box {
                Box { lcLeaf().onAppear { log.add("clipped") } }.frame(width: Pixels(10), height: Pixels(10))
                    .offset(x: Pixels(100), y: Pixels(100))
            }.frame(width: Pixels(5), height: Pixels(5)).clipped()
        }
    }
    window.drawFrameIfNeeded()
    #expect(Set(log.entries) == ["hidden", "transparent", "zero", "clipped"] && log.entries.count == 4,
            "\(log.entries)")
    log.entries.removeAll()
    m.flag = true
    window.drawFrameIfNeeded()
    m.flag = false
    window.drawFrameIfNeeded()
    #expect(log.entries.isEmpty, "an opacity toggle fires nothing (E4): \(log.entries)")
}

/// The window that scrolls a 12-row `List` (1.5, 5.4): a 20-point viewport, so
/// at offset 0 the window holds the first rows only and row 4 is out.
@MainActor private func listWindow(_ log: LCLog) throws -> (Window, GlobalElementID) {
    let rows = (0..<12).map { LCRow(id: "row\($0)") }
    let (window, _) = try lcWindow(size: 100) {
        Box {
            ScrollView(.vertical, elementID: ElementID("scroller")) {
                List(rows, rowHeight: Pixels(20)) { row in Box { LCCounter(label: row.id, log: log) } }
            }
        }.cssHeight(Pixels(20))
    }
    return (window, GlobalElementID.child(of: lcRoot, at: 0, name: ElementID("scroller")))
}

@MainActor private func scroll(_ window: Window, _ scroller: GlobalElementID, to offset: Double) {
    let current = window.stateTable.peek(scroller, as: ScrollState.self) ?? ScrollState()
    window.stateTable.write(scroller, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                  viewportExtent: current.viewportExtent))
    window.drawFrameIfNeeded()
}

/// **1.5** (`S1`, `LC-C` item 3, `TB-AH`). A `List` row scrolled out of its
/// window is not built, so it disappears; scrolled back within `TB-AH`'s two
/// generations it appears again — and its `@State` was kept (its `onAppear`
/// reads the visit count it wrote). Mutation: exempt a windowed `List`'s rows
/// from disappearance.
@MainActor
@Test func aListRowScrolledOutDisappearsReturnsAsAnAppearanceAndKeepsItsState() throws {
    let log = LCLog()
    let (window, scroller) = try listWindow(log)
    window.drawFrameIfNeeded()          // cold: every row built
    scroll(window, scroller, to: 100)   // row 4 in the window
    scroll(window, scroller, to: 100)
    let visits = try #require(log.entries.last { $0.hasPrefix("appear row4 ") }
        .flatMap { Int($0.split(separator: " ")[2]) }, "set up: row 4 appeared: \(log.entries)") + 1
    try #require(visits >= 1)
    log.entries.removeAll()
    scroll(window, scroller, to: 0)     // row 4 out
    #expect(log.entries.filter { $0.hasPrefix("disappear row4") } == ["disappear row4 \(visits)"],
            "row 4 disappears once when it leaves the window: \(log.entries)")
    #expect(!log.entries.contains { $0.hasPrefix("appear row4") })
    log.entries.removeAll()
    scroll(window, scroller, to: 100)   // row 4 back
    #expect(log.entries.filter { $0.hasPrefix("appear row4") } == ["appear row4 \(visits)"],
            "row 4 appears again with its kept @State (TB-AH): \(log.entries)")
}

/// **1.5b** (`LC-Q`, divergence 124; SwiftUI `S1`). A `List`'s first frame
/// inside its scroller builds every row (`List.visibleRange`: no viewport is
/// measured yet), so every row appears, and the rows outside the window the
/// next build measures disappear — where SwiftUI's lazy `List` creates only
/// the visible rows. Here the rows' `onAppear` writes `@State`, so the next
/// build is the settle build inside the same `drawFrameIfNeeded` (`LC-E` item
/// 2) and both halves run before the first frame is presented; with no write
/// the disappearances run on frame two. Derived before the run: a 20-point
/// viewport at offset 0 windows rows 0..<3 (two rows of overscan), so rows
/// 3…11 — nine — disappear, each having counted one visit. Pins MetalUI's
/// answer; no mutation of its own (the `List` cold-frame rule is outside this
/// lane).
@MainActor
@Test func aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow() throws {
    let log = LCLog()
    let (window, _) = try listWindow(log)
    window.drawFrameIfNeeded()
    let first = log.take()
    #expect(first.filter { $0.hasPrefix("appear row") }.count == 12, "\(first)")
    #expect(Set(first.filter { $0.hasPrefix("disappear") }) == Set((3..<12).map { "disappear row\($0) 1" }),
            "\(first)")
    #expect(window.lastDrawBuildCount == 2)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(log.entries == [], "settled: \(log.entries)")
}

/// **1.6** (divergence 72's shape, `LC-C` item 2). Two siblings sharing one
/// `.id` mint one store key; the occurrence keeps them two elements. Mutation:
/// drop `occurrence` from `Key`.
@MainActor
@Test func twoSiblingsSharingOneIdAppearTwice() throws {
    let log = LCLog()
    let (window, _) = try lcWindow {
        Row {
            lcLeaf().onAppear { log.add("a") }.id("same")
            lcLeaf().onAppear { log.add("b") }.id("same")
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries.sorted() == ["a", "b"], "\(log.entries)")
}

/// **1.7** (`A3`, `LC-C` item 2). Stacked lifecycle modifiers at one position
/// keep separate entries, the inner one first on insertion and on removal.
/// Mutation: M1.7b (drop `depth` and the occurrence). Dropping `depth` alone is
/// green, and since `LC-V` the depth is redundant with the occurrence: every
/// stacked scope notes whenever the shared content is present (`LC-V` item 2).
@MainActor
@Test func stackedLifecycleModifiersKeepSeparateEntriesInnerFirst() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            if m.shown {
                lcLeaf()
                    .onAppear { log.add("appear a") }.onDisappear { log.add("disappear a") }
                    .onAppear { log.add("appear b") }.onDisappear { log.add("disappear b") }
            }
        }
    }
    window.drawFrameIfNeeded()
    m.shown = true
    window.drawFrameIfNeeded()
    #expect(log.take() == ["appear a", "appear b"])
    m.shown = false
    window.drawFrameIfNeeded()
    #expect(log.take() == ["disappear a", "disappear b"])
}

/// **1.7c** (`LC-V`, the branch check's `LC-U` item 2). An action that
/// toggles to or from `nil` while its element stays built changes no presence:
/// `onDisappear(perform: flag ? f : nil)` going non-nil → nil runs no
/// `onDisappear`, and `onAppear(perform: flag ? f : nil)` going nil → non-nil
/// runs no `onAppear`; a later real removal still runs the disappearance the
/// action then holds. Mutation: note a scope only when its write is non-nil
/// (`if let write, !nodes.isEmpty`).
@MainActor
@Test func anActionTogglingToOrFromNilChangesNoPresence() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    m.flag = true
    let (window, _) = try lcWindow {
        Column {
            if m.shown {
                lcLeaf()
                    .onAppear(perform: m.flag ? nil : { log.add("appear") })
                    .onDisappear(perform: m.flag ? { log.add("disappear on") } : nil)
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.take().isEmpty, "set up: present, the appear action nil")
    m.flag = false
    for _ in 0..<3 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    #expect(log.take().isEmpty, "a toggled action ran: the element never left or arrived")
    m.flag = true
    for _ in 0..<3 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    #expect(log.take().isEmpty, "toggling back ran nothing either")
    m.shown = false
    for _ in 0..<3 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    #expect(log.take() == ["disappear on"], "the real removal runs the action it holds")
}

/// **1.8** (`LC-B` item 2). Adding a lifecycle modifier moves no identity: the
/// recorded element ids and a nested `@State`'s table ids are equal with and
/// without it, on both vocabularies. Mutation: `cursor += 1` in
/// `requestGroupLayout`.
@MainActor
@Test func addingALifecycleModifierMovesNoIdentity() throws {
    let log = LCLog()
    let with = lcIdentity(Row {
        LCCounter(label: "c", log: log).onAppear {}.onChange(of: 1) {}
        lcLeaf().onDisappear {}
        lcLeaf()
    })
    // `LCCounter` carries its own lifecycle modifiers; the control drops only the outer ones.
    let without = lcIdentity(Row {
        LCCounter(label: "c", log: log)
        lcLeaf()
        lcLeaf()
    })
    #expect(with.bounds == without.bounds, "legacy: element ids moved")
    #expect(with.table == without.table, "a nested @State moved")
    let proposalWith = lcIdentity(HStack(spacing: 0) {
        Rectangle().frame(width: Pixels(10), height: Pixels(10)).onAppear {}
        Rectangle().frame(width: Pixels(11), height: Pixels(10))
    })
    let proposalWithout = lcIdentity(HStack(spacing: 0) {
        Rectangle().frame(width: Pixels(10), height: Pixels(10))
        Rectangle().frame(width: Pixels(11), height: Pixels(10))
    })
    #expect(proposalWith.bounds == proposalWithout.bounds, "proposal: element ids moved")
}

/// **1.9** (`LC-C`). Lifecycle modifiers fire inside a `Component`, an
/// `EnvironmentScope` and a `Deferred`, each once. A composition test: pinned
/// by 1.1's mutation (no own).
@MainActor
@Test func lifecycleModifiersFireInsideAComponentAnEnvironmentScopeAndADeferred() throws {
    let log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            LCCounter(label: "component", log: log)
            Column { lcLeaf().onAppear { log.add("environment") }.environment(\.isEnabled, true) }
            Deferred { Box { lcLeaf().onAppear { log.add("deferred") } } }
        }
    }
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(log.entries.sorted() == ["appear component 0", "deferred", "environment"], "\(log.entries)")
}

/// **1.10** (`LC-B` item 2). The typed proposal scope notes like the untyped
/// one: a `ProposalText().onAppear` inside an `HStack` fires, and the ids are
/// those without the scope. Mutation: delete `noteLifecycle` from
/// `requestProposalGroupLayout` only.
@MainActor
@Test func theTypedProposalScopeNotesLikeTheUntypedOne() throws {
    let log = LCLog()
    let (window, _) = try lcWindow {
        Column { HStack(spacing: 0) { ProposalText("a").onAppear { log.add("proposal") } } }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["proposal"], "\(log.entries)")
    let with = lcIdentity(HStack(spacing: 0) { ProposalText("a").onAppear {}; ProposalText("b") })
    let without = lcIdentity(HStack(spacing: 0) { ProposalText("a"); ProposalText("b") })
    #expect(with.bounds == without.bounds, "the typed scope moved an id")
}

/// **1.11** (`E2b`, `LC-P` item 2). A lifecycle modifier written outside `.id`
/// keys on the position: `k` and `v` changed in one write fire no appear, no
/// disappear and one change `(0, 1)`; the recorded ids are those without the
/// scope. Mutation: key the entry on the content's element id (its name)
/// instead of the scope's position.
@MainActor
@Test func aLifecycleModifierWrittenOutsideIdKeysOnThePosition() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().id("k\(m.key)")
                .onAppear { log.add("appear") }
                .onDisappear { log.add("disappear") }
                .onChange(of: m.value) { old, new in log.add("change \(old) \(new)") }
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.take() == ["appear"])
    m.key = 1
    m.value = 1
    window.drawFrameIfNeeded()
    #expect(log.entries == ["change 0 1"], "\(log.entries)")
    let with = lcIdentity(Column { lcLeaf().id("k1").onAppear {}.onChange(of: 1) {} })
    let without = lcIdentity(Column { lcLeaf().id("k1") })
    #expect(with.bounds == without.bounds)
}

/// **1.12** (`A6`, `A6b`, `LC-P` item 1). A modifier on a group fires once per
/// group, and only while the group has content: `ForEach(0..<n)`, n 0 → 3 → 1
/// → 0 → 2, appears at 3, nothing at 1, disappears at 0, appears at 2, and
/// nothing for the empty first build; a two-child group under an `if` appears
/// once and disappears once. Mutation: note the entry whether or not `nodes`
/// is empty.
@MainActor
@Test func aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            ForEach(0..<m.count) { _ in lcLeaf() }
                .onAppear { log.add("appear") }.onDisappear { log.add("disappear") }
            if m.shown { LCPair().onAppear { log.add("pair appear") }.onDisappear { log.add("pair disappear") } }
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.take() == [], "an empty ForEach does not appear")
    var steps: [[String]] = []
    for n in [3, 1, 0, 2] {
        m.count = n
        window.drawFrameIfNeeded()
        steps.append(log.take())
    }
    #expect(steps == [["appear"], [], ["disappear"], ["appear"]], "\(steps)")
    m.shown = true
    window.drawFrameIfNeeded()
    m.shown = false
    window.drawFrameIfNeeded()
    #expect(log.take() == ["pair appear", "pair disappear"])
}

// MARK: - Order (2.1–2.4)

@MainActor private func nestedTree(_ m: LCModel, _ log: LCLog) -> some Element {
    Column {
        if m.shown {
            Column {
                Column {
                    lcLeaf().onAppear { log.add("+child1") }.onDisappear { log.add("-child1") }
                    lcLeaf().onAppear { log.add("+child2") }.onDisappear { log.add("-child2") }
                }
                .onAppear { log.add("+parent") }.onDisappear { log.add("-parent") }
            }
            .onAppear { log.add("+grandparent") }.onDisappear { log.add("-grandparent") }
        }
        if m.s1 { lcLeaf().onAppear { log.add("+s1") }.onDisappear { log.add("-s1") } }
        if m.s2 { lcLeaf().onAppear { log.add("+s2") }.onDisappear { log.add("-s2") } }
        if m.s3 { lcLeaf().onAppear { log.add("+s3") }.onDisappear { log.add("-s3") } }
    }
}

/// **2.1** (`A1`, `A2`, `LC-F`). Insertion runs children before parents and
/// later siblings first. Mutation: sort ascending.
@MainActor
@Test func insertionRunsChildrenBeforeParentsAndLaterSiblingsFirst() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow { nestedTree(m, log) }
    window.drawFrameIfNeeded()
    m.shown = true
    window.drawFrameIfNeeded()
    #expect(log.take() == ["+child2", "+child1", "+parent", "+grandparent"])
    m.s1 = true; m.s2 = true; m.s3 = true
    window.drawFrameIfNeeded()
    #expect(log.take() == ["+s3", "+s2", "+s1"])
}

/// **2.2** (`A1`, `A2`, divergence 122). Removal runs in reverse pre-order —
/// for separately removed siblings too, where SwiftUI goes forward. Mutation:
/// sort bucket 3 ascending (or by this build's order).
@MainActor
@Test func removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true; m.s1 = true; m.s2 = true; m.s3 = true
    let (window, _) = try lcWindow { nestedTree(m, log) }
    window.drawFrameIfNeeded()
    log.entries.removeAll()
    m.shown = false
    window.drawFrameIfNeeded()
    #expect(log.take() == ["-child2", "-child1", "-parent", "-grandparent"])
    m.s1 = false; m.s2 = false; m.s3 = false
    window.drawFrameIfNeeded()
    #expect(log.take() == ["-s3", "-s2", "-s1"])
}

/// **2.3** (`C12`, `A5`, `LC-F`). A build's changes run before its
/// appearances, and its appearances before its disappearances — whatever the
/// tree order (the changed element is first in pre-order here). Mutation:
/// concatenate buckets 2, 1, 3.
@MainActor
@Test func changesRunBeforeAppearsAndAppearsBeforeDisappears() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().onChange(of: m.value) { log.add("change a") }
            if m.flag {
                lcLeaf().onAppear { log.add("appear new") }
            } else {
                lcLeaf().onDisappear { log.add("disappear old") }
            }
        }
    }
    window.drawFrameIfNeeded()
    m.value = 1
    m.flag = true
    window.drawFrameIfNeeded()
    #expect(log.entries == ["change a", "appear new", "disappear old"], "\(log.entries)")
}

/// **2.4** (`C3`, `C3b`). `initial: true` fires with `onAppear`, in modifier
/// order: inner first. Mutation: put initial firings in bucket 1.
@MainActor
@Test func initialTrueFiresWithAppearInModifierOrder() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            if m.s1 {
                lcLeaf().onAppear { log.add("appear") }
                    .onChange(of: 5, initial: true) { old, new in log.add("change \(old) \(new)") }
            }
            if m.s2 {
                lcLeaf().onChange(of: 5, initial: true) { old, new in log.add("change \(old) \(new)") }
                    .onAppear { log.add("appear") }
            }
        }
    }
    window.drawFrameIfNeeded()
    m.s1 = true
    window.drawFrameIfNeeded()
    #expect(log.take() == ["appear", "change 5 5"])
    m.s2 = true
    window.drawFrameIfNeeded()
    #expect(log.take() == ["change 5 5", "appear"])
}

// MARK: - onChange (3.1–3.6)

/// **3.1** (`C1`, `LC-G` item 1). The two-parameter form gets (old, new).
/// Mutation: pass `(new, old)`.
@MainActor
@Test func onChangePassesTheOldAndNewValues() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column { lcLeaf().onChange(of: m.value) { old, new in log.add("\(old) \(new)") } }
    }
    window.drawFrameIfNeeded()
    m.value = 1
    window.drawFrameIfNeeded()
    #expect(log.entries == ["0 1"], "\(log.entries)")
}

/// **3.2** (`C2`). The zero-parameter form fires. Mutation: the
/// zero-parameter overload builds a no-op.
@MainActor
@Test func theZeroParameterFormFires() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow { Column { lcLeaf().onChange(of: m.value) { log.add("fired") } } }
    window.drawFrameIfNeeded()
    m.value = 1
    window.drawFrameIfNeeded()
    #expect(log.entries == ["fired"], "\(log.entries)")
}

/// **3.3** (`C3`, `C4`, `LC-G` item 2). A first sighting stores and does not
/// fire, unless `initial: true`, which fires (5, 5). Mutation: fire on first
/// sighting regardless.
@MainActor
@Test func aFirstSightingFiresOnlyWithInitialTrue() throws {
    let log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().onChange(of: 5) { old, new in log.add("default \(old) \(new)") }
            lcLeaf().onChange(of: 5, initial: true) { old, new in log.add("initial \(old) \(new)") }
        }
    }
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(log.entries == ["initial 5 5"], "\(log.entries)")
}

/// **3.4** (`C5`–`C7`, `LC-G` item 3). Builds coalesce writes: `1; 0` fires
/// nothing, `0` again nothing, `1; 2` fires once with (0, 2). Mutation: count
/// every build after a write as a change (compare by writes, not `isEqual`).
@MainActor
@Test func writesBetweenFramesCoalesceAndAnUndoneChangeFiresNothing() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column { lcLeaf().onChange(of: m.value) { old, new in log.add("\(old) \(new)") } }
    }
    window.drawFrameIfNeeded()
    m.value = 1; m.value = 0
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(log.take() == [], "an undone change fires nothing (C6)")
    m.value = 0
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(log.take() == [], "a write of the same value fires nothing (C7)")
    m.value = 1; m.value = 2
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(log.take() == ["0 2"], "two writes fire once, first old, last new (C5)")
}

/// **3.5** (`C10`, `LC-D`). Content that leaves and returns compares against
/// nothing; so does a new `.id`. Mutation: `endFrame` keeps untouched
/// `previous` entries one more build.
@MainActor
@Test func contentThatReturnsComparesAgainstNothing() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, _) = try lcWindow {
        Column {
            if m.shown { lcLeaf().onChange(of: m.value) { old, new in log.add("returned \(old) \(new)") } }
            lcLeaf().onChange(of: m.value) { old, new in log.add("renamed \(old) \(new)") }.id("k\(m.key)")
        }
    }
    window.drawFrameIfNeeded()
    m.shown = false
    window.drawFrameIfNeeded()
    m.value = 5
    m.shown = true
    m.key = 1
    window.drawFrameIfNeeded()
    #expect(log.entries == [], "\(log.entries)")
}

/// **3.6** (`C12`, `C13`, `LC-G` item 4). Content the change inserts does not
/// see it, and content it removes is not built. Mutation: fire a first
/// sighting (compare an absent key against its own value).
@MainActor
@Test func insertedAndRemovedElementsDoNotSeeTheChangeThatMovedThem() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            if m.value > 0 { lcLeaf().onChange(of: m.value) { old, new in log.add("inserted \(old) \(new)") } }
            if m.value == 0 { lcLeaf().onChange(of: m.value) { old, new in log.add("removed \(old) \(new)") } }
        }
    }
    window.drawFrameIfNeeded()
    m.value = 1
    window.drawFrameIfNeeded()
    #expect(log.entries == [], "\(log.entries)")
}

// MARK: - Timing, dispatch, settle (4.1–4.7)

/// **4.1** (`F1`, `LC-E` item 2). An `onAppear` that writes `@State` is
/// presented in the first frame: one `drawFrameIfNeeded` builds twice and
/// presents the written width. Mutation: delete the settle build.
@MainActor
@Test func anOnAppearWriteIsPresentedInTheFirstFrame() throws {
    let (window, _) = try lcWindow { Column { LCPresenter() } }
    window.drawFrameIfNeeded()
    #expect(lcWidth(window, height: 7) == 30, "presented: \(String(describing: lcWidth(window, height: 7)))")
    #expect(window.lastDrawBuildCount == 2)
}

/// **4.2** (`LC-E` item 2). An action that writes nothing costs no second
/// build. Mutation: settle unconditionally.
@MainActor
@Test func anActionThatWritesNothingCostsNoSecondBuild() throws {
    let log = LCLog()
    let (window, _) = try lcWindow { Column { lcLeaf().onAppear { log.add("appear") } } }
    window.drawFrameIfNeeded()
    try #require(log.entries == ["appear"])
    #expect(window.lastDrawBuildCount == 1)
}

/// **4.3** (`LC-E` item 1). An action runs outside every phase, under its
/// element's dispatch: `StateDispatch.owner` is the scope's position, the
/// frame is not rendering, and an `@Observable` write dirties the window (it
/// is outside `withObservationTracking`, so the settle build follows).
/// Mutation: run the drain inside `renderRoot` (end of `Frame.render`).
@MainActor
@Test func actionsRunOutsideEveryPhaseUnderTheirElementsDispatch() throws {
    let m = LCModel(), ref = LCFrameRef()
    var owner: GlobalElementID?
    var rendering: Bool?
    let (window, _) = try lcWindow {
        Column {
            lcLeaf(m.width, 7).onAppear {
                owner = StateDispatch.owner
                rendering = ref.frame?.isRendering
                m.width = 30
            }
            LCFrameSpy(ref: ref)
        }
    }
    window.drawFrameIfNeeded()
    #expect(owner == GlobalElementID.child(of: lcRoot, at: 0, name: nil), "\(String(describing: owner))")
    #expect(rendering == false)
    #expect(window.lastDrawBuildCount == 2, "the observable write must dirty the window")
    #expect(lcWidth(window, height: 7) == 30)
}

/// **4.4** (`F2b`, `RX-S`). An `@Observable` write in `onAppear` reaches the
/// first presented frame and is not lost; the window goes clean once nothing
/// changes. Mutation: run the drain inside the `withObservationTracking` apply
/// closure.
@MainActor
@Test func anObservableWriteInOnAppearIsPresentedAndNotLost() throws {
    let m = LCModel()
    let (window, _) = try lcWindow { Column { lcLeaf(m.width, 7).onAppear { m.width = 30 } } }
    window.drawFrameIfNeeded()
    #expect(lcWidth(window, height: 7) == 30)
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw, "settled: nothing more to draw")
}

/// **4.5** (`LC-E` item 2). A settled window goes idle: after the events, two
/// `drawFrameIfNeeded` leave it clean and enter a pause. Mutation:
/// `drainLifecycle` returns and sets dirty unconditionally.
@MainActor
@Test func aSettledWindowGoesIdle() throws {
    let log = LCLog()
    let (window, _) = try lcWindow { Column { LCPresenter(); lcLeaf().onAppear { log.add("appear") } } }
    window.drawFrameIfNeeded()
    let pauses = window.pausesEntered
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw)
    #expect(window.pausesEntered > pauses, "the window paused")
}

/// **4.6** (`LC-E` item 4). An action that draws a frame synchronously does
/// not drain re-entrantly: it runs once, start to end, and the content it
/// inserted appears exactly once, after it. Mutation: delete the
/// `isDrainingLifecycle` guard.
@MainActor
@Test func anActionThatDrawsAFrameDoesNotDrainReentrantly() throws {
    let m = LCModel(), log = LCLog(), ref = LCWindowRef()
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().onAppear {
                log.add("first begin")
                m.shown = true
                ref.window?.drawFrameIfNeeded()
                log.add("first end")
            }
            if m.shown { lcLeaf().onAppear { log.add("inserted") } }
        }
    }
    ref.window = window
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(log.entries == ["first begin", "first end", "inserted"], "\(log.entries)")
}

/// **4.7** (`F3`, divergence 121). A chain settles one level of writes per
/// presented frame: the first frame presents the second level, the next frame
/// the third. Mutation: loop the settle until clean (SwiftUI's fixed point) —
/// reddens by design; the test pins MetalUI's bound.
@MainActor
@Test func aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame() throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().onAppear { m.level = 1 }
            if m.level >= 1 { lcLeaf().onAppear { m.level = 2 } }
            Box().frame(width: Pixels(Float(10 * (m.level + 1))), height: Pixels(7)).background(.accent)
        }
    }
    window.drawFrameIfNeeded()
    #expect(lcWidth(window, height: 7) == 20, "frame 1 presents the first level's write")
    #expect(window.needsRedraw, "the second level's write schedules the next frame")
    window.drawFrameIfNeeded()
    #expect(lcWidth(window, height: 7) == 30, "frame 2 presents the second level's write")
}

// MARK: - Departed state (5.1–5.4)

/// **5.1** (`D1`, `LC-I`). `onDisappear` reads its own `@State` as it was in
/// the last frame (7), though the sweep already reset it. Mutation:
/// `withDepartedOverlay` ignores the overlay.
@MainActor
@Test func onDisappearReadsItsOwnStateAsItWasLastFrame() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, _) = try lcWindow { Column { if m.shown { LCHolder(log: log) } } }
    window.drawFrameIfNeeded()
    try #require(log.take() == ["appear a=0 b=0"])
    m.shown = false
    window.drawFrameIfNeeded()
    #expect(log.entries == ["disappear a=7 b=0"], "\(log.entries)")
}

/// **5.2** (`D1`, `LC-I` item 2). A write in `onDisappear` — to a written slot
/// and a never-written one — is lost: content that returns reads 0 for both.
/// Mutation: overlay writes fall through to `storage`.
@MainActor
@Test func aWriteInOnDisappearIsLostAndReturningContentStartsFresh() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, _) = try lcWindow { Column { if m.shown { LCHolder(log: log) } } }
    window.drawFrameIfNeeded()
    m.shown = false
    window.drawFrameIfNeeded()
    log.entries.removeAll()
    m.shown = true
    window.drawFrameIfNeeded()
    #expect(log.entries == ["appear a=0 b=0"], "\(log.entries)")
}

/// **5.3** (`LC-I` item 1, `LC-M`). No departed values are kept for a removal
/// when no element has an `onDisappear`; the control with one keeps some.
/// Mutation: `retainsDepartedValues = true` always.
@MainActor
@Test func noDepartedValuesAreKeptWithoutAnOnDisappear() throws {
    let m = LCModel(), reads = ConditionalReads()
    m.shown = true
    let (window, _) = try lcWindow { Column { if m.shown { ConditionalCounter("c", reads) } } }
    window.drawFrameIfNeeded()
    m.shown = false
    window.drawFrameIfNeeded()
    #expect(window.stateTable.lastDepartedValueCount == 0)

    let control = LCModel()
    control.shown = true
    let (controlWindow, _) = try lcWindow {
        Column { if control.shown { ConditionalCounter("d", reads); lcLeaf().onDisappear {} } }
    }
    controlWindow.drawFrameIfNeeded()
    control.shown = false
    controlWindow.drawFrameIfNeeded()
    #expect(controlWindow.stateTable.lastDepartedValueCount > 0, "the control keeps the reset subtree's values")
}

/// **5.4** (`LC-I` item 3, `LC-P` item 5). A `List` row's `onDisappear` reads
/// its retained, live state — nothing was reset. Mutation: `peek` under
/// `withDepartedOverlay` answers only from the overlay.
@MainActor
@Test func aListRowsOnDisappearReadsItsRetainedLiveState() throws {
    let log = LCLog()
    let (window, scroller) = try listWindow(log)
    window.drawFrameIfNeeded()
    scroll(window, scroller, to: 100)
    scroll(window, scroller, to: 100)
    let visits = try #require(log.entries.last { $0.hasPrefix("appear row4 ") }
        .flatMap { Int($0.split(separator: " ")[2]) }, "set up: \(log.entries)") + 1
    log.entries.removeAll()
    scroll(window, scroller, to: 0)
    let row4 = log.entries.filter { $0.hasPrefix("disappear row4") }
    #expect(visits >= 1 && row4 == ["disappear row4 \(visits)"], "\(log.entries)")
}

// MARK: - Transitions (6.1–6.5)

@MainActor private func transitionWindow<Content: ElementGroup>(
    _ m: LCModel, @ElementBuilder _ content: @escaping @MainActor () -> Content
) throws -> (Window, FakePlatformWindow) {
    try lcWindow(size: 300, startsDisplayLink: true) {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                content()
            }
        }
    }
}

/// **6.1** (`T1`, `LC-H`). An animated removal's `onDisappear` runs when its
/// ghost ends: none at t + 0.3 of a 0.6 s fade, one at t + 0.7. Mutation:
/// never park.
@MainActor
@Test func anAnimatedRemovalDisappearsWhenItsGhostEnds() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try transitionWindow(m) {
        if m.shown { lcLeaf(50, 30).onDisappear { log.add("disappear") }.transition(.opacity) }
    }
    platform.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    try #require(window.animationStore.transitions.ghostCount == 1, "set up: a ghost")
    platform.simulateTick(timestamp: 101.3)
    #expect(log.entries == [], "mid-fade: \(log.entries)")
    #expect(window.animationStore.lifecycle.parkedCount == 1)
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["disappear"], "\(log.entries)")
    #expect(window.animationStore.lifecycle.parkedCount == 0)
}

/// **6.2** (`T3`). An `onDisappear` written outside the transition waits too
/// (its position equals the ghost's). Mutation: park only on strict descent.
@MainActor
@Test func anOnDisappearOutsideTheTransitionAlsoWaits() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try transitionWindow(m) {
        if m.shown { lcLeaf(50, 30).transition(.opacity).onDisappear { log.add("disappear") } }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    platform.simulateTick(timestamp: 101.3)
    #expect(log.entries == [], "mid-fade: \(log.entries)")
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["disappear"], "\(log.entries)")
}

/// **6.3** (`T5`). A parent and an untransitioned child under one ghost
/// disappear together after the fade, child first. Mutation: release parked
/// events in stored order reversed.
@MainActor
@Test func aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try transitionWindow(m) {
        if m.shown {
            Column { lcLeaf(50, 30).onDisappear { log.add("child") } }
                .onDisappear { log.add("parent") }
                .transition(.opacity)
        }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    platform.simulateTick(timestamp: 101.3)
    #expect(log.entries == [])
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["child", "parent"], "\(log.entries)")
}

/// **6.4** (`T4`, divergence 123). Content re-inserted during its removal
/// ghost runs neither callback, ever, and its nested `@State` is fresh (the
/// tile is 50 wide again, not the 60 its own `onAppear` grew it to). An
/// `initial: true` `onChange` on the same content is cancelled the same way
/// (`LC-Q` item 4): it fires with the first appearance and not on the
/// re-insertion. Mutations: do not cancel a parked event whose key returned
/// (M6.4); take the `initial: true` firing out of the `!cancelled` check (V14,
/// `LC-S` item 5).
@MainActor
@Test func reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try transitionWindow(m) {
        if m.shown {
            LCGrowingTile().onAppear { log.add("appear") }.onDisappear { log.add("disappear") }
                .onChange(of: 5, initial: true) { log.add("initial") }
                .transition(.opacity)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(log.take() == ["appear", "initial"])
    try #require(window.lastScene.rects.contains { $0.bounds.size.width == 60 }, "set up: grown")
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    withAnimation(.linear(duration: 0.6)) { m.shown = true }
    platform.simulateTick(timestamp: 101.15)
    for t in [101.4, 101.8, 102.5, 103.0] { platform.simulateTick(timestamp: t) }
    #expect(log.entries == [], "neither callback runs: \(log.entries)")
    let accents = window.lastScene.rects.filter { isLCAccent($0.background) }
    #expect(accents.map(\.bounds.size.width) == [50], "fresh state: \(accents.map(\.bounds.size.width))")
    #expect(window.animationStore.lifecycle.parkedCount == 0)
}

/// **6.5** (`T0`, `T2`). An unanimated removal disappears at once; an animated
/// insertion appears at once. Mutation: park every disappearance for one build.
@MainActor
@Test func anUnanimatedRemovalDisappearsAtOnceAndAnAnimatedInsertionAppearsAtOnce() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try transitionWindow(m) {
        if m.shown {
            lcLeaf(50, 30).onAppear { log.add("appear") }.onDisappear { log.add("disappear") }
                .transition(.opacity)
        }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    try #require(log.take() == ["appear"])
    m.shown = false
    platform.simulateTick(timestamp: 101)
    #expect(log.take() == ["disappear"], "unanimated: at once (T0)")
    withAnimation(.linear(duration: 0.6)) { m.shown = true }
    platform.simulateTick(timestamp: 102)
    #expect(log.take() == ["appear"], "an animated insertion appears at once (T2)")
}

// MARK: - Window and headless (7.1–7.3)

@MainActor private func lcApp() throws -> (App, FakePlatform) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    return (App(platform: platform), platform)
}

/// **7.1** (`W3`, `LC-J` item 1). Closing a window runs every present
/// element's `onDisappear` once, in reverse pre-order, each under its
/// element's `StateDispatch` — the owner the same scope's `onAppear` saw; a
/// second close runs nothing. Mutations: remove the call from `App`'s
/// `onClose` (M7.1); call `event.action()` directly in
/// `runDisappearancesForClose` (V5, `LC-S` item 4).
@MainActor
@Test func closingTheWindowRunsEveryPresentOnDisappearOnce() throws {
    let log = LCLog()
    var appearOwner: GlobalElementID?
    var closeOwner: GlobalElementID?
    let (app, platform) = try lcApp()
    try app.openWindow(title: "Lifecycle", size: Size(width: Pixels(100), height: Pixels(100)),
                       startsDisplayLink: false) {
        Column {
            Column { lcLeaf().onDisappear { log.add("child") } }.onDisappear { log.add("parent") }
            lcLeaf()
                .onAppear { appearOwner = StateDispatch.owner }
                .onDisappear { closeOwner = StateDispatch.owner; log.add("sibling") }
        }
    }
    let fake = try #require(platform.openedWindows.first)
    try #require(log.entries.isEmpty)
    let expectedOwner = try #require(appearOwner, "set up: the first frame's onAppear ran under a dispatch")
    fake.onClose?()
    #expect(log.take() == ["sibling", "child", "parent"])
    #expect(closeOwner == expectedOwner, "close-time onDisappear dispatch: \(String(describing: closeOwner))")
    fake.onClose?()
    #expect(log.entries == [], "a second close runs nothing")
}

/// **7.2** (`LC-J` item 1). A close mid-ghost runs the parked disappearance
/// too. Mutation: `closeAll` skips `parked`.
@MainActor
@Test func closingTheWindowAlsoRunsParkedDisappearances() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (app, platform) = try lcApp()
    try app.openWindow(title: "Lifecycle", size: Size(width: Pixels(300), height: Pixels(300)),
                       startsDisplayLink: true) {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if m.shown { lcLeaf(50, 30).onDisappear { log.add("parked") }.transition(.opacity) }
            }
            lcLeaf().onDisappear { log.add("present") }
        }
    }
    let fake = try #require(platform.openedWindows.first)
    fake.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    fake.simulateTick(timestamp: 101)
    try #require(log.entries.isEmpty, "set up: parked mid-ghost")
    fake.onClose?()
    #expect(log.entries.sorted() == ["parked", "present"], "\(log.entries)")
}

/// **7.3** (`LC-J` item 4). A headless `renderFrame` runs no action. Mutation:
/// drain in `renderFrame`.
@MainActor
@Test func aHeadlessRenderFrameRunsNoAction() {
    let log = LCLog()
    _ = renderFrame({ Column { lcLeaf().onAppear { log.add("appear") } } },
                    size: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                    textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 64, height: 64))
    #expect(log.entries.isEmpty)
}

// MARK: - Performance (8.1–8.2)

/// **8.1** (`LC-M`). A tree with no lifecycle modifier does no lifecycle work:
/// `demoContent()` through a window, three frames — no entry, no counted
/// work, no departed value. Mutation: note an entry from `Element`'s default
/// `requestGroupLayout`.
@MainActor
@Test func aTreeWithNoLifecycleModifierDoesNoLifecycleWork() throws {
    let (window, _) = try lcWindow(size: 900) { demoContent() }
    for _ in 0..<3 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    try #require(!window.lastScene.rects.isEmpty, "set up: the demo painted")
    #expect(window.animationStore.lifecycle.count == 0)
    #expect(window.animationStore.lifecycle.lastFrameWork == 0)
    #expect(window.stateTable.lastDepartedValueCount == 0)
}

@MainActor private func ternaryLeaf() -> some ElementGroup {
    Box().frame(width: Pixels(2), height: Pixels(2)).onAppear {}
}

@MainActor private func ternaryLevel2(last: Bool, dropsLeaf: Bool) -> some ElementGroup {
    Row {
        ternaryLeaf()
        ternaryLeaf()
        if !(last && dropsLeaf) { ternaryLeaf() }
    }.onAppear {}
}

@MainActor private func ternaryLevel1(last: Bool, dropsLeaf: Bool) -> some ElementGroup {
    Column {
        ternaryLevel2(last: false, dropsLeaf: dropsLeaf)
        ternaryLevel2(last: false, dropsLeaf: dropsLeaf)
        ternaryLevel2(last: last, dropsLeaf: dropsLeaf)
    }.onAppear {}
}

/// **8.2** (`LC-M`, `SA-M`). A ternary tree three levels below its root, a
/// scope on every node: 1 + 3 + 9 + 27 = 40 scopes. Derived before the run:
/// a steady build does registrations (40) + this build's entries (40) + the
/// last build's (40) = **120**. Dropping one leaf: the dropping build does
/// 39 + 39 + 40 = **118**, and steady after it 39 × 3 = **117**. Mutation: a
/// nested-loop diff (the last build scanned per current key).
@MainActor
@Test func aSteadyFrameDoesThreeUnitsOfLifecycleWorkPerScope() throws {
    let m = LCModel()
    let (window, _) = try lcWindow(size: 300) {
        Column {
            Column {
                ternaryLevel1(last: false, dropsLeaf: m.flag)
                ternaryLevel1(last: false, dropsLeaf: m.flag)
                ternaryLevel1(last: true, dropsLeaf: m.flag)
            }.onAppear {}
        }
    }
    window.drawFrameIfNeeded()
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(window.animationStore.lifecycle.count == 40)
    #expect(window.animationStore.lifecycle.lastFrameWork == 120)
    m.flag = true
    window.drawFrameIfNeeded()
    #expect(window.animationStore.lifecycle.lastFrameWork == 118)
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(window.animationStore.lifecycle.lastFrameWork == 117)
}

// MARK: - Lane 1's fix pass (ruling `LC-S`): 5.5–5.7, 6.6

/// A device monitor whose every construction takes the next serial, so a test
/// can tell which instance `start()` and `stop()` reached (`D2`).
@MainActor final class LCMonitorFactory {
    var made = 0
    let log: LCLog
    init(_ log: LCLog) { self.log = log }
    func make() -> LCMonitor {
        made += 1
        return LCMonitor(serial: made, log: log)
    }
}

@MainActor final class LCMonitor {
    let serial: Int
    let log: LCLog
    init(serial: Int, log: LCLog) { self.serial = serial; self.log = log }
    func start() { log.add("start \(serial)") }
    func stop() { log.add("stop \(serial)") }
}

/// The SMK shape written with a never-written `@State` default (divergence
/// 125): the default is re-seeded every build, so `onAppear` and `onDisappear`
/// reach different instances.
private struct LCDefaultMonitorPane: Component {
    let factory: LCMonitorFactory
    let value: Int
    @State var monitor: LCMonitor
    init(factory: LCMonitorFactory, value: Int) {
        self.factory = factory
        self.value = value
        _monitor = State(wrappedValue: factory.make())
    }
    var content: some ElementGroup {
        Box().frame(width: Pixels(10 + Float(value)), height: Pixels(20))
            .onAppear { monitor.start() }
            .onDisappear { monitor.stop() }
    }
}

/// The documented spelling (divergence 125, `LC-S` item 1): the instance is
/// assigned in `onAppear`, so it is a written `@State` value — kept while the
/// pane is present and read by `onDisappear` through its departed state.
private struct LCAssignedMonitorPane: Component {
    let factory: LCMonitorFactory
    let value: Int
    @State var monitor: LCMonitor? = nil
    var content: some ElementGroup {
        Box().frame(width: Pixels(10 + Float(value)), height: Pixels(20))
            .onAppear { monitor = factory.make(); monitor?.start() }
            .onDisappear { monitor?.stop() }
    }
}

/// **5.5** (`D2`, divergence 125, `LC-S` item 1). SwiftUI keeps a `@State`
/// default's first evaluation for the view's lifetime (`D2`: start and stop
/// both reach `Mon 1` of four made). MetalUI re-seeds a never-written default
/// every build: four builds while present, then a removal — `onAppear` reached
/// instance 1 and `onDisappear` a later one. This pins the divergence; the
/// separating arm is 5.6. A fix that keeps the first value reddens this test —
/// read divergence 125 first.
@MainActor
@Test func aNeverWrittenStateDefaultIsReseededSoOnAppearAndOnDisappearSeeDifferentInstances() throws {
    let m = LCModel(), log = LCLog()
    let factory = LCMonitorFactory(log)
    m.shown = true
    let (window, _) = try lcWindow { Column { if m.shown { LCDefaultMonitorPane(factory: factory, value: m.value) } } }
    window.drawFrameIfNeeded()
    for v in 1...3 { m.value = v; window.drawFrameIfNeeded() }
    try #require(log.take() == ["start 1"])
    m.shown = false
    window.drawFrameIfNeeded()
    let stops = log.take()
    #expect(stops.count == 1 && stops != ["stop 1"], "re-seeded every build (divergence 125): \(stops)")
    #expect(factory.made > 1, "the default was evaluated per build: \(factory.made)")
}

/// **5.6** (`LC-S` item 1, `LC-I`). The documented spelling — the instance
/// assigned in `onAppear` — starts and stops ONE instance across the same four
/// builds and removal. The separating arm of 5.5. Mutation M5.1 — the
/// overlay ignored (M5.1) reads `nil` and stops nothing.
@MainActor
@Test func aMonitorAssignedInOnAppearIsTheOneOnDisappearStops() throws {
    let m = LCModel(), log = LCLog()
    let factory = LCMonitorFactory(log)
    m.shown = true
    let (window, _) = try lcWindow { Column { if m.shown { LCAssignedMonitorPane(factory: factory, value: m.value) } } }
    window.drawFrameIfNeeded()
    for v in 1...3 { m.value = v; window.drawFrameIfNeeded() }
    try #require(log.take() == ["start 1"])
    m.shown = false
    window.drawFrameIfNeeded()
    #expect(log.entries == ["stop 1"], "\(log.entries)")
    #expect(factory.made == 1)
}

/// **5.7** (`LC-I` item 1, `LC-S` item 3). `takeDepartedState()` empties what
/// it hands over: a build that resets nothing counts 0 departed values, and a
/// second removal counts only its own (the same as the first, for the same
/// shape). Mutation V3: delete the `defer` clearing `departedValues` and
/// `departedRootsKept` (the steady build reports the first removal's values,
/// the second removal both).
@MainActor
@Test func eachRemovalCountsOnlyTheDepartedValuesItsOwnSweepKept() throws {
    let m = LCModel(), log = LCLog()
    m.s1 = true
    m.s2 = true
    let (window, _) = try lcWindow {
        Column {
            if m.s1 { LCHolder(log: log) }
            if m.s2 { LCHolder(log: log) }
            lcLeaf(10, 10 + Float(m.value))
        }
    }
    window.drawFrameIfNeeded()
    m.s1 = false
    window.drawFrameIfNeeded()
    let first = window.stateTable.lastDepartedValueCount
    try #require(first > 0, "set up: the first removal kept values")
    m.value = 1
    window.drawFrameIfNeeded()
    #expect(window.stateTable.lastDepartedValueCount == 0, "a build that reset nothing keeps nothing")
    m.s2 = false
    window.drawFrameIfNeeded()
    #expect(window.stateTable.lastDepartedValueCount == first,
            "the second removal counts its own: \(window.stateTable.lastDepartedValueCount) vs \(first)")
}

/// **6.6** (`LC-I` item 1, `LC-H`, `LC-S` item 2). A disappearance parked on a
/// removal ghost keeps its own departed state: the `onDisappear` that runs
/// after the fade reads the `@State` its `onAppear` wrote (a = 7), not the
/// reset initial value. Mutation V1: build the parked event with
/// `departed: nil` in `LifecycleStore.endFrame`.
@MainActor
@Test func aGhostParkedOnDisappearReadsTheStateItsElementHad() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try transitionWindow(m) {
        if m.shown { LCHolder(log: log).transition(.opacity) }
    }
    platform.simulateTick(timestamp: 100)
    try #require(log.take() == ["appear a=0 b=0"])
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    try #require(window.animationStore.lifecycle.parkedCount == 1, "set up: parked on the ghost")
    platform.simulateTick(timestamp: 101.3)
    try #require(log.entries == [], "mid-fade: \(log.entries)")
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["disappear a=7 b=0"], "\(log.entries)")
}
