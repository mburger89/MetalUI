import Testing
import Foundation
import Metal
import AppKit
import Observation
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// Lane 3 of the accessibility bridge: what a `Text`, an `onClick` element, a
// focusable element and a `List` publish without a declaration; the public
// `accessibilityLabel`/`accessibilityValue`/`accessibilityAdjustableAction`
// modifiers with SwiftUI's distribution through containers and wrappers; a
// button's combined label and value; and a `List` that publishes no rows while
// its window is unbounded (spec
// `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`, "Lane 3").
//
// **Footings.** Lane 1's: Frame-level tests render a bare collecting `Frame`
// and build the tree exactly as `Window` does (no Metal device); window-level
// tests use `makeFakeWindow` and begin with
// `try #require(MTLCreateSystemDefaultDevice())`. The cost tests also hand the
// fake platform's published trees to a real `AppKitAccessibilityBridge` over a
// plain `NSView`, with a recording poster, and count its elements and posts.
//
// **Fixture rules.** Lane 1's: explicit sizes wherever geometry or a hitbox
// matters, distinct strings per node, and `try #require` on every looked-up
// node a later assertion reads (taxonomy shape 13).

/// `Accessibility.framework` (imported through `AppKit`) also exports a Swift
/// `AccessibilityRequest`, so the bare name is ambiguous here (AB-AF item 1).
private typealias Request = MetalUIPlatform.AccessibilityRequest

private func px(_ v: Float) -> Pixels { Pixels(v) }

private struct Item: Identifiable { let id: Int }

/// Renders `element` into a collecting `Frame` and builds the tree the way
/// `Window.drawFrameIfNeeded` does.
///
/// **`authority` since stage 4's lane 4** (`LR-BU`): the four `List` tests that
/// go through this helper run under both. Every other caller takes the default
/// `.legacy`, which is what production uses until stage 6b — this file's
/// subject is the accessibility tree, not the engine, and an authority argument
/// on a fixture with no `List` in it would be an argument two arms could not
/// disagree about (`LR-BN`'s rule).
@MainActor private func collect<E: Element>(_ element: E, stateTable: StateTable = StateTable(),
                                           width: Float = 300, height: Float = 300,
                                           collects: Bool = true,
                                           authority: LayoutAuthority = Frame.defaultLayoutAuthority)
    -> (Frame, AccessibilityTree) {
    var element = element
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1,
                      stateTable: stateTable, theme: Theme.forAppearance(.light),
                      collectsAccessibility: collects, layoutAuthority: authority)
    frame.render(&element)
    let tree = AccessibilityTreeBuilder.build(emissions: frame.axEmissions,
                                              focused: frame.focusedElement,
                                              hitboxes: frame.hitboxes,
                                              focusRegistry: frame.focusRegistry)
    return (frame, tree)
}

private extension AccessibilityTree {
    /// The roots' nodes, in published order.
    var rootNodes: [AccessibilityNode] { roots.compactMap { nodes[$0] } }

    /// A node's children's nodes, in published order.
    func childNodes(of id: AccessibilityNodeID) -> [AccessibilityNode] {
        (nodes[id]?.children ?? []).compactMap { nodes[$0] }
    }

    /// Every node with `role`, in record order.
    func all(_ role: AccessibilityRole) -> [(id: AccessibilityNodeID, node: AccessibilityNode)] {
        nodes.filter { $0.value.role == role }
            .sorted { (geometry[$0.key]?.order ?? 0) < (geometry[$1.key]?.order ?? 0) }
            .map { (id: $0.key, node: $0.value) }
    }
}

/// Draws until the window reports clean, at most `limit` times.
@MainActor private func drawUntilClean(_ window: Window, limit: Int = 5) {
    for _ in 0..<limit where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor private final class Tally {
    var count = 0
    var directions: [AccessibilityAdjustmentDirection] = []
}

// MARK: - The two red-befores for this file's `.proposal` arms (`LR-BX`, `LR-CF`)

/// **`scrolledList`'s root exactly as it stood at `16d6696`**, kept as a live
/// fixture so the probe below keeps a subject after the `.minHeight(px(0))` is
/// dropped from `scrolledList` itself (stage 4, lane 4).
@MainActor private func legacySpelledScrolledListRoot(_ count: Int, height: Float) -> some Element {
    let list = List((0..<count).map(Item.init), rowHeight: px(28)) { item in
        Box { Text("Row \(item.id)") }.frame(width: px(180), height: px(28), alignment: .topLeading)
    }
    return Box { ScrollView(.vertical) { list } }
        .cssWidth(px(200)).cssHeight(px(height)).cssMinHeight(px(0))
}

/// **The red this lane could not take in-process, and the measured reason
/// `scrolledList` loses one modifier** (`LR-CF`; spec §6 lane 4 did not predict
/// it — it names only the two row spellings).
///
/// Four of this file's six `List` tests make `scrolledList(...)` the **root** of
/// their frame or of their window, and its root `Box` carried
/// `.minHeight(px(0))`. A root's `LoweredItem` is by definition unconsumed, and
/// `reportUnconsumedLoweredItems` reports a root's non-`.auto` `minSize`
/// (`LoweringState.swift:120-127`; `anItemFieldNoLoweredContainerConsumesIsReportedByName`'s
/// root arms already document it) — so a production `.proposal` frame over that
/// fixture aborts before the first assertion. It is **not** the `List`: the
/// identical fixture with the modifier dropped runs to completion, which the
/// second half of this probe is.
///
/// Recorded, with the assertion temporarily pointed at a string that cannot
/// match (reverted; `git status --short` clean afterwards):
///
///     MetalUI/Frame.swift:1536: Fatal error: MetalUI: box.minSize.unconsumed
///     has no proposal lowering (plan task 7, stage 2); a tree containing it
///     cannot run under the proposal layout authority.
///
/// The modifier is **inert under the legacy engine** — the box declares
/// `height`, so no automatic minimum is in play, and where it is a flex item
/// (`aClientDoesNotChangeStateRetention`'s `Row`) the axis it names is the cross
/// one. Measured, not argued: dropping it and running the whole suite unfiltered
/// left 1593 tests / 3 issues, the three lane 2 left red for lane 5 (record §27
/// §9.2). That is why it goes, rather than the fixture being wrapped in a host.
///
/// **Inverted by stage 6b's lane 1** (`LR-DO` item 1; it was
/// `aRootMinHeightOnTheScrollerFixtureAbortsAProductionProposalFrame`, expecting
/// `.failure` on `box.minSize.unconsumed`). The fixture's root declares its height,
/// so its `.minHeight(0)` now folds into it and a production `.proposal` frame over
/// the fixture **completes**. The abort survives only for a root minimum on an
/// **auto** axis, pinned through a production `Window` by `RootFieldLoweringTests`'
/// 1.8. The control below is unchanged: the same tree without the modifier.
///
/// Mutation that must redden it: **M1h**, the root fold removed.
@Test func aRootMinHeightOnTheScrollerFixtureNoLongerAbortsAProductionProposalFrame() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            var element = legacySpelledScrolledListRoot(50, height: 200)
            Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                  stateTable: StateTable(), theme: Theme.forAppearance(.light),
                  collectsAccessibility: true, layoutAuthority: .proposal).render(&element)
        }
    }

    // The control: the same tree without that one modifier completes. Without
    // this half the probe above would pass just as well if the `List`, the
    // `ScrollView` or the `Text` were what aborted.
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let list = List((0..<50).map(Item.init), rowHeight: px(28)) { item in
                Box { Text("Row \(item.id)") }.frame(width: px(180), height: px(28), alignment: .topLeading)
            }
            var element = Box { ScrollView(.vertical) { list } }.cssWidth(px(200)).cssHeight(px(200))
            Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                  stateTable: StateTable(), theme: Theme.forAppearance(.light),
                  collectsAccessibility: true, layoutAuthority: .proposal).render(&element)
        }
    }
}

/// **Why `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` stays
/// legacy-only** (`LR-CF`). Spec §6 lane 4 lists it as a both-authorities arm and
/// makes it half of mutation M4b's required failure count. It cannot be one:
/// its subject IS `.hidden()`, and `display: none` has no proposal lowering —
/// `LegacyLowering.swift:161` returns `display.none` before any other field is
/// read, and the parent design's §4.1 stage table assigns it to a later stage
/// (the trap says stage 2; stage 2 deferred it, §8).
///
/// Recorded, with the assertion temporarily pointed at a string that cannot
/// match (reverted; `git status --short` clean afterwards):
///
///     MetalUI/Frame.swift:1536: Fatal error: MetalUI: box.display.none has no
///     proposal lowering (plan task 7, stage 2); a tree containing it cannot run
///     under the proposal layout authority.
///
/// M4b's count is restated against a test that CAN run on both paths —
/// `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`' zero-
/// `rowHeight` arm, which is the same `AB-X` rule 1 on the same gate (record §27
/// §9.5).
///
/// **Inverted by stage 6b's lane 1** (`LR-DH`; it was
/// `aHiddenListAbortsAProductionProposalFrame`, expecting `.failure` on
/// `box.display.none`). `hidden()` now lowers as if shown under the proposal
/// authority, so a production frame over the hidden list **completes**, as its
/// shown control always did; the both-authorities arm the paragraph above asked for
/// is `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`.
///
/// Mutation that must redden it: the six `display == .none` report sites restored.
@Test func aHiddenListNoLongerAbortsAProductionProposalFrame() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let box = Box {
                List((0..<50).map(Item.init), rowHeight: px(28)) { _ in
                    Box().frame(width: px(20), height: px(28))
                }
            }
            .frame(width: px(40), height: px(40), alignment: .topLeading)
            var element = Column { box.hidden(); Text("shown") }
            Frame(contentSize: Size(width: px(300), height: px(300)), scaleFactor: 1,
                  stateTable: StateTable(), theme: Theme.forAppearance(.light),
                  collectsAccessibility: true, layoutAuthority: .proposal).render(&element)
        }
    }

    // The control: the same tree SHOWN completes too. Until stage 6b only the
    // hidden arm aborted (on `box.display.none`); both arms now complete (`LR-DH`).
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let box = Box {
                List((0..<50).map(Item.init), rowHeight: px(28)) { _ in
                    Box().frame(width: px(20), height: px(28))
                }
            }
            .frame(width: px(40), height: px(40), alignment: .topLeading)
            var element = Column { box; Text("shown") }
            Frame(contentSize: Size(width: px(300), height: px(300)), scaleFactor: 1,
                  stateTable: StateTable(), theme: Theme.forAppearance(.light),
                  collectsAccessibility: true, layoutAuthority: .proposal).render(&element)
        }
    }
}

/// A 200pt-wide scroller of `height` over a `count`-row `List` whose rows are a
/// 28pt `Box` holding `Text("Row N")` — the demo's row shape, `demoLikeRows`'
/// footing. `rowHeight` is the list's declared row height (each row's content
/// stays 28pt); `clickableRows` puts an `onClick` on each row's content Box,
/// `clickableList` one on the list itself.
///
/// **It carried a `.minHeight(px(0))` on that outer `Box` until stage 4's lane 4,
/// and that one modifier is what kept four of this file's `List` tests off the
/// proposal authority** (`LR-CF`). Four of them make this the ROOT of a frame or
/// of a window; a root's `LoweredItem` is unconsumed by definition, and
/// `reportUnconsumedLoweredItems` reports a root's non-`.auto` `minSize`, so a
/// production `.proposal` frame aborted on it before the first assertion.
/// `aRootMinHeightOnTheScrollerFixtureNoLongerAbortsAProductionProposalFrame`
/// above was that abort and its control; since stage 6b's lane 1 the declared-axis
/// minimum folds (`LR-DO` item 1) and the abort is gone.
///
/// **Dropping it moves nothing under the legacy engine, measured rather than
/// argued**: the box declares `height`, so no automatic minimum is in play, and
/// in the one place it is a flex item (`aClientDoesNotChangeStateRetention`'s
/// `Row`) the axis it names is the cross one. The whole suite unfiltered with it
/// dropped and nothing else changed read 1593 tests / 3 issues — the three lane 2
/// left red for lane 5 (record §27 §9.2).
@MainActor private func scrolledList(_ count: Int, height: Float,
                                     label: String? = nil, rowHeight: Float = 28,
                                     clickableRows: Bool = false,
                                     clickableList: Bool = false) -> some Element {
    var list = List((0..<count).map(Item.init), rowHeight: px(rowHeight)) { item in
        let content = Box { Text("Row \(item.id)") }.frame(width: px(180), height: px(28), alignment: .topLeading)
        return clickableRows ? content.onClick {} : content
    }
    if let label { list = list.accessibilityLabel(label) }
    if clickableList { list = list.onClick {} }
    return Box { ScrollView(.vertical) { list } }
        .cssWidth(px(200)).cssHeight(px(height))
}

// MARK: - Bridge harness (the cost tests)

@MainActor private final class RecordingPoster: AccessibilityNotificationPosting {
    struct Post { let name: NSAccessibility.Notification; let element: AnyObject }
    private(set) var posts: [Post] = []
    func post(_ notification: NSAccessibility.Notification, for element: Any) {
        posts.append(Post(name: notification, element: element as AnyObject))
    }
    func count(_ name: NSAccessibility.Notification) -> Int { posts.filter { $0.name == name }.count }
    func reset() { posts.removeAll() }
}

/// A screen reader that is running from the start: the bridge is active before
/// anything is published, as it is for a window opened under VoiceOver.
@MainActor private final class RunningSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

/// A real `AppKitAccessibilityBridge` over a plain `NSView` in an `NSWindow`,
/// fed every tree the fake platform was handed, in order.
@MainActor private final class BridgeFeed {
    let nsWindow: NSWindow
    let view: NSView
    let poster = RecordingPoster()
    let bridge: AppKitAccessibilityBridge
    private var fed = 0

    init() {
        nsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                            styleMask: [.titled], backing: .buffered, defer: true)
        nsWindow.isReleasedWhenClosed = false
        view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        nsWindow.contentView = view
        bridge = AppKitAccessibilityBridge(signal: RunningSignal(), poster: poster)
        bridge.hostView = view
    }

    /// Publishes every tree the platform received since the last call.
    func sync(_ platform: FakePlatformWindow) {
        for tree in platform.publishedAccessibilityTrees.dropFirst(fed) { bridge.publish(tree) }
        fed = platform.publishedAccessibilityTrees.count
    }
}

// MARK: - Text (AB-F)

/// A `Text` is an `AXStaticText` whose value is its string (arms 1, 3); a
/// container that says nothing publishes nothing; `Text("")` is no text and
/// `Text(" ")` is (arms E0–E2).
@Test @MainActor func aTextIsPublishedAsStaticTextWhoseValueIsItsString() throws {
    let (_, tree) = collect(Column { Text("A"); Text("B") })
    try #require(tree.roots.count == 2)
    let a = tree.rootNodes[0], b = tree.rootNodes[1]
    #expect(a.role == .staticText && a.value == "A" && a.label == nil)
    #expect(b.role == .staticText && b.value == "B" && b.label == nil)
    #expect(tree.nodes.count == 2, "the Column says nothing and publishes nothing")

    let (_, empty) = collect(Column { Text(""); Text("B") })
    #expect(empty.rootNodes.map(\.value) == ["B"], "an empty Text publishes nothing (arm E1)")

    let (_, blank) = collect(Column { Text(" "); Text("B") })
    try #require(blank.roots.count == 2, "a blank Text is not empty and is published (arm E2)")
    #expect(blank.rootNodes[0].value == " " && blank.rootNodes[0].role == .staticText)
}

/// SwiftUI's static-text rules (arms 10a, 11, R1, R2, R12): a label alone
/// becomes the value; a value keeps the string as the label; both are kept; a
/// clickable text keeps its string as its label beside a declared value.
@Test @MainActor func labelAndValueFollowSwiftUIsStaticTextRules() throws {
    let (_, labelled) = collect(Column { Text("Hello").accessibilityLabel("Greeting") })
    let greeting = try #require(labelled.rootNodes.first)
    #expect(greeting.role == .staticText)
    #expect(greeting.value == "Greeting" && greeting.label == nil, "arm 10a: a lone label is the value")

    let (_, valued) = collect(Column { Text("vol").accessibilityValue("5") })
    let volume = try #require(valued.rootNodes.first)
    #expect(volume.label == "vol" && volume.value == "5", "arm R1: a value keeps the string as the label")

    let (_, both) = collect(Column { Text("vol").accessibilityLabel("L").accessibilityValue("5") })
    let declared = try #require(both.rootNodes.first)
    #expect(declared.label == "L" && declared.value == "5", "arm R2: both kept")

    let (_, clickable) = collect(Column { Text("vol").onClick {}.accessibilityValue("5") })
    let button = try #require(clickable.rootNodes.first)
    #expect(button.role == .button && button.label == "vol" && button.value == "5", "arm R12")
    #expect(button.actions == [.press])
}

/// A clickable `Text` is a button labelled by its string (arm 5), unless it
/// declares a label (AB-G).
///
/// **The declared-label arm was added against surviving mutant N49** (the
/// string overriding a declared label): no other fixture declares a label on a
/// clickable text.
@Test @MainActor func aClickableTextIsAButtonLabelledByItsString() throws {
    let (_, tree) = collect(Column { Text("Go").onClick {} })
    try #require(tree.nodes.count == 1)
    let go = try #require(tree.rootNodes.first)
    #expect(go.role == .button)
    #expect(go.label == "Go" && go.value == nil)
    #expect(go.actions == [.press])

    let (_, labelled) = collect(Column { Text("Go").onClick {}.accessibilityLabel("Start") })
    let start = try #require(labelled.rootNodes.first)
    #expect(start.role == .button && start.label == "Start" && start.value == nil,
            "a declared label wins over the string")
}

// MARK: - Distribution (AB-T)

/// A label or value on a plain container or a wrapper is distributed to its
/// children, and the outer declaration wins (arms R3, R4, R5, R8, R10, R15,
/// R18). Arms 2–5 are the modifier-composition merge's joint check (AB-Z).
///
/// **Arm 7 is a divergence pin, not a control.** SwiftUI distributes a label
/// from a focusable container (arm C1) and from an adjustable one, copying the
/// action to each child (arms C5, C5i); MetalUI keeps the labelled group,
/// because actions route by the node's own id and focus needs a node to land
/// on (AB-T).
@Test @MainActor func aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren() throws {
    // (1) R3
    let (_, container) = collect(Column { Text("A"); Text("B") }.accessibilityLabel("L"))
    try #require(container.nodes.count == 2, "arm 1: no group for the Column")
    #expect(container.rootNodes.map(\.value) == ["L", "L"])
    #expect(container.rootNodes.allSatisfy { $0.role == .staticText && $0.label == nil })

    // (2) R4
    let (_, padded) = collect(Text("Go").padding(px(4)).accessibilityLabel("X"))
    try #require(padded.nodes.count == 1, "arm 2: no group for the padding wrapper")
    #expect(padded.rootNodes.first?.role == .staticText && padded.rootNodes.first?.value == "X")

    // (3) R8
    let (_, chained) = collect(Text("Go").accessibilityLabel("In").padding(px(4)).accessibilityLabel("Out"))
    try #require(chained.nodes.count == 1, "arm 3")
    #expect(chained.rootNodes.first?.value == "Out", "the outer declaration wins")

    // (4) R10
    let (_, framed) = collect(Text("Go").frame(width: px(120)).accessibilityLabel("X"))
    try #require(framed.nodes.count == 1, "arm 4: no group for the frame wrapper")
    #expect(framed.rootNodes.first?.value == "X")

    // (5) R5
    let (_, button) = collect(Row { Text("Go") }.frame(width: px(40), height: px(20), alignment: .leading).onClick {}
        .padding(px(4)).accessibilityLabel("X"))
    try #require(button.nodes.count == 1, "arm 5: one button, no wrapper group, no text child")
    let pressable = try #require(button.rootNodes.first)
    #expect(pressable.role == .button && pressable.label == "X" && pressable.children.isEmpty)

    // (6) R18. The first text declares its own value, so the outer value must
    // overwrite it (surviving mutant N09v let the inner value win; R15 is the
    // label's side of the same rule).
    let (_, valued) = collect(Column { Text("A").accessibilityValue("own"); Text("B") }
        .accessibilityValue("V"))
    try #require(valued.roots.count == 2, "arm 6")
    #expect(valued.rootNodes.map(\.label) == ["A", "B"])
    #expect(valued.rootNodes.map(\.value) == ["V", "V"], "the outer value wins")

    // (7) Divergence pins (C1, C5) and the no-child control (R6, R11).
    let (_, focusable) = collect(Column { Text("A") }.frame(width: px(40), height: px(20), alignment: .top).focusable()
        .accessibilityLabel("L"))
    let group = try #require(focusable.roots.first)
    #expect(focusable.nodes[group]?.role == .group && focusable.nodes[group]?.label == "L",
            "a focusable labelled container keeps its group (SwiftUI's arm C1 distributes)")
    #expect(focusable.childNodes(of: group).map(\.value) == ["A"])

    let (_, adjustable) = collect(Column { Text("A") }.frame(width: px(40), height: px(20), alignment: .top)
        .accessibilityAdjustableAction { _ in }.accessibilityLabel("L"))
    let adjustableGroup = try #require(adjustable.roots.first)
    #expect(adjustable.nodes[adjustableGroup]?.role == .group
            && adjustable.nodes[adjustableGroup]?.label == "L",
            "an adjustable labelled container keeps its group (SwiftUI's arms C5, C5i distribute)")
    #expect(adjustable.childNodes(of: adjustableGroup).map(\.value) == ["A"])

    let (_, leaf) = collect(Column { Box().frame(width: px(20), height: px(0)).accessibilityLabel("L") })
    let labelledLeaf = try #require(leaf.rootNodes.first)
    #expect(labelledLeaf.role == .group && labelledLeaf.label == "L" && labelledLeaf.children.isEmpty,
            "a labelled generic node with no child is not a distributor")
}

// MARK: - Combination (AB-G, AB-V)

/// A clickable container whose descendants are all non-interactive is one
/// button: its texts join into its label, and a descendant carrying both a
/// label and a value contributes that value (arms 6, C3, C4, C6, C7). An
/// interactive descendant keeps the children (the divergence from arm R7).
@Test @MainActor func aClickableContainerCombinesItsTextsIntoOneButtonLabel() throws {
    let (_, plain) = collect(Row { Text("A"); Text("B") }.frame(width: px(60), height: px(20), alignment: .leading).onClick {})
    try #require(plain.nodes.count == 1)
    let combined = try #require(plain.rootNodes.first)
    #expect(combined.role == .button)
    #expect(combined.label == "A, B" && combined.value == nil)
    #expect(combined.children.isEmpty)

    let (_, interactive) = collect(Row {
        Text("A"); Text("B"); Box().frame(width: px(10), height: px(10)).focusable()
    }.frame(width: px(60), height: px(20), alignment: .leading).onClick {})
    let kept = try #require(interactive.roots.first)
    #expect(interactive.nodes[kept]?.role == .button)
    #expect(interactive.nodes[kept]?.label == nil, "an interactive descendant stops the combination")
    #expect(interactive.nodes[kept]?.children.count == 3)

    // A click target is interactive too, not only a focusable box (surviving
    // mutant N60 counted focusability alone): the inner button keeps its own
    // node and the outer one its children.
    let (_, clickableChild) = collect(Row { Text("A"); Text("B").onClick {} }
        .frame(width: px(60), height: px(20), alignment: .leading).onClick {})
    let outer = try #require(clickableChild.roots.first)
    #expect(clickableChild.nodes[outer]?.label == nil, "a clickable descendant stops the combination")
    #expect(clickableChild.childNodes(of: outer).map(\.role) == [.staticText, .button])

    func combine<C: ElementGroup>(@ElementBuilder _ content: () -> C) throws -> AccessibilityNode {
        let (_, tree) = collect(Row(content: content).frame(width: px(60), height: px(20), alignment: .leading).onClick {})
        try #require(tree.nodes.count == 1)
        return try #require(tree.rootNodes.first)
    }
    let c3 = try combine { Text("vol").accessibilityValue("5"); Text("B") }
    #expect(c3.label == "vol, B" && c3.value == "5", "arm C3")
    let c7 = try combine { Text("A"); Text("vol").accessibilityValue("5") }
    #expect(c7.label == "A, vol" && c7.value == "5", "arm C7: the value follows the text carrying it")
    let c6 = try combine { Text("a").accessibilityValue("1"); Text("b").accessibilityValue("2") }
    #expect(c6.label == "a, b" && c6.value == "1, 2", "arm C6")
    let c4 = try combine { Text("A").accessibilityLabel("X"); Text("B") }
    #expect(c4.label == "X, B" && c4.value == nil, "arm C4: a labelled text contributes to the label only")

    // **Descendants, not children** (surviving mutant N46 looked one level
    // down). A kept, non-interactive node with children of its own sits between
    // the button and its texts: the public API reaches that shape through a
    // `List` table inside a click target; a declared `.container` (`@testable`)
    // stands in for it here. Its texts still join the label, and a focusable
    // box beneath it still stops the fold.
    let (_, nested) = collect(Row {
        Column { Text("A"); Text("B") }.handling { $0.axNode.role = .container }
    }.frame(width: px(60), height: px(20), alignment: .leading).onClick {})
    let deep = try #require(nested.rootNodes.first)
    #expect(deep.role == .button && deep.label == "A, B" && deep.children.isEmpty,
            "a grandchild text contributes to the label")
    let (_, nestedInteractive) = collect(Row {
        Column { Text("A"); Box().frame(width: px(10), height: px(10)).focusable() }
            .handling { $0.axNode.role = .container }
    }.frame(width: px(60), height: px(20), alignment: .leading).onClick {})
    let unfolded = try #require(nestedInteractive.rootNodes.first)
    #expect(unfolded.label == nil && unfolded.children.count == 1,
            "a focusable grandchild keeps the button's children")

    // **A button below a kept node that is not a button still combines**
    // (the verifier's surviving mutant L3V01 stopped the walk at the first kept
    // non-button). The demo's `CounterPanel` shape: a focusable container
    // holding click targets that wrap texts. Each inner button folds its own
    // text, and a declared label wins over it.
    let (_, panelTree) = collect(Row {
        Box { Text("-") }.frame(width: px(20), height: px(20), alignment: .topLeading).onClick {}.accessibilityLabel("Decrement")
        Box { Text("go") }.frame(width: px(20), height: px(20), alignment: .topLeading).onClick {}
    }.frame(width: px(60), height: px(20), alignment: .leading).focusable())
    let panelID = try #require(panelTree.roots.first)
    try #require(panelTree.roots.count == 1)
    #expect(panelTree.nodes[panelID]?.role == .group)
    #expect(panelTree.nodes[panelID]?.label == nil)
    let inner = panelTree.childNodes(of: panelID)
    try #require(inner.count == 2, "control: the focusable panel keeps both buttons")
    #expect(inner.map(\.role) == [.button, .button])
    #expect(inner.map(\.label) == ["Decrement", "go"], "each nested button takes its own text")
    #expect(inner.allSatisfy { $0.children.isEmpty }, "each nested button folds its text away")
    #expect(panelTree.all(.staticText).isEmpty)
}

/// Combination inside a bounded `List` (AB-G, AB-L): a click target inside each
/// row folds its text into its label, below a table and a row that are kept
/// and are not buttons. A **clickable list** is still a table and keeps its
/// rows, because step C gates on the published role, not on clickability. And
/// a non-positive `rowHeight` leaves the window unbounded even inside a
/// measured scroller, so no row is published (`AB-AG` item 5).
///
/// Each arm is the second frame over one state table, so the scroller has
/// measured its 200pt viewport. The window at offset 0 is rows 0..<10 (200 / 28
/// = 7.1, rounded up, plus 2 of overscan).
///
/// **Added against the verifier's surviving mutants** L3V01 (step C does not
/// recurse below a kept non-button), L3V02 (step C gates on `isClickable`) and
/// L3V05 (`windowIsBounded` ignores `rowHeight`).
///
/// **Both authorities since stage 4's lane 4** (`LR-BU`, `LR-CF`). Its
/// zero-`rowHeight` arm is `AB-X` rule 1 — an unbounded window publishes the
/// table and no rows — on a tree that lowers on both paths, which is why
/// mutation **M4b** (`indexesRows` forced true) is counted against this test and
/// `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` rather
/// than against `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`,
/// which the design named and which cannot run under `.proposal` at all.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func secondFrame<E: Element>(_ make: () -> E) throws -> AccessibilityTree {
        let stateTable = StateTable()
        let (first, _) = collect(make(), stateTable: stateTable, width: 200, height: 200,
                                 authority: authority)
        let scroller = try #require(first.scrollRegions.first).id
        try #require(stateTable.peek(scroller, as: ScrollState.self)?.viewportExtent == 200,
                     "control: the first frame measured a 200pt viewport")
        return collect(make(), stateTable: stateTable, width: 200, height: 200,
                       authority: authority).1
    }

    let clickableRows = try secondFrame { scrolledList(50, height: 200, clickableRows: true) }
    let rowsTableID = try #require(clickableRows.all(.table).first).id
    let rowIDs = clickableRows.nodes[rowsTableID]?.children ?? []
    try #require(rowIDs.count == 10, "control: the bounded window publishes rows 0..<10")
    let buttons = rowIDs.map { clickableRows.childNodes(of: $0) }
    try #require(buttons.allSatisfy { $0.count == 1 }, "each row holds one click target")
    #expect(buttons.map { $0[0].role } == Array(repeating: AccessibilityRole.button, count: 10))
    #expect(buttons.map { $0[0].label } == (0..<10).map { "Row \($0)" },
            "a row's button is labelled by its text")
    #expect(buttons.allSatisfy { $0[0].children.isEmpty }, "and folds that text away")
    #expect(clickableRows.all(.staticText).isEmpty)

    let clickableList = try secondFrame { scrolledList(50, height: 200, clickableList: true) }
    let (listID, list) = try #require(clickableList.all(.table).first)
    #expect(clickableList.roots == [listID])
    #expect(list.actions == [.press], "control: the list is clickable")
    #expect(list.label == nil, "a clickable table takes no combined label")
    let listRowIDs = list.children
    #expect(listRowIDs.count == 10, "a clickable table keeps its rows")
    #expect(listRowIDs.map { clickableList.childNodes(of: $0).map(\.value) } == (0..<10).map { ["Row \($0)"] })

    let zeroHeight = try secondFrame { scrolledList(50, height: 200, rowHeight: 0) }
    let zero = try #require(zeroHeight.all(.table).first).node
    #expect(zero.rowCount == 50, "control: the table and its row count still publish")
    #expect(zero.children.isEmpty, "a zero rowHeight is an unbounded window: no rows")
    #expect(zeroHeight.all(.staticText).isEmpty, "and none of their texts")
}

/// Portal content is a root, so it is never folded into a button's label
/// (AB-V).
@Test @MainActor func aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel() throws {
    let (_, tree) = collect(Row {
        Text("A")
        Deferred { Text("Tip") }
    }.cssWidth(px(60)).cssHeight(px(20)).onClick {})
    try #require(tree.roots.count == 2)
    let button = tree.rootNodes[0], tip = tree.rootNodes[1]
    #expect(button.role == .button && button.label == "A")
    #expect(tip.role == .staticText && tip.value == "Tip")
}

// MARK: - Adjustment (AB-I)

/// `accessibilityAdjustableAction` registers the element's own
/// `AccessibilityAdjustment` handler (arm 11).
@Test @MainActor func theAdjustableActionModifierRegistersTheAdjustmentHandler() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let tally = Tally()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column { Text("vol").accessibilityAdjustableAction { tally.directions.append($0) } }
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let volume = try #require(tree.roots.first)
    #expect(tree.nodes[volume]?.actions == [.increment, .decrement])
    #expect(platform.simulateAccessibilityRequest(.increment(volume)))
    #expect(platform.simulateAccessibilityRequest(.decrement(volume)))
    #expect(tally.directions == [.increment, .decrement])
}

// MARK: - List (AB-L, AB-X)

/// A scrolled `List` is a table whose row count is its logical count, whose
/// children are its realized rows, each carrying its logical index and holding
/// its text. Labelled, it is still a table (arm R16).
///
/// The window, by `List.visibleRange`'s arithmetic: a 200pt viewport at offset
/// 1120 (28 × 40) over 28pt rows covers rows 40 through 47 (1320 / 28 = 47.1,
/// rounded up to 48), widened by the 2-row overscan to **38..<50**.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    for label in [nil, "Contacts"] as [String?] {
        let stateTable = StateTable()
        let (first, _) = collect(scrolledList(500, height: 200, label: label),
                                 stateTable: stateTable, width: 200, height: 200,
                                 authority: authority)
        let scroller = try #require(first.scrollRegions.first).id
        try #require(stateTable.peek(scroller, as: ScrollState.self)?.viewportExtent == 200,
                     "control: the first frame measured a 200pt viewport")
        stateTable.withState(scroller, initial: ScrollState()) { $0.offset = 28 * 40 }

        let (_, tree) = collect(scrolledList(500, height: 200, label: label),
                                stateTable: stateTable, width: 200, height: 200,
                                authority: authority)
        let (tableID, table) = try #require(tree.all(.table).first)
        #expect(tree.roots == [tableID])
        #expect(table.rowCount == 500)
        #expect(table.label == label, "label: \(label ?? "nil")")
        let rows = tree.childNodes(of: tableID)
        try #require(rows.count == 12, "the realized window 38..<50 (label: \(label ?? "nil"))")
        #expect(rows.allSatisfy { $0.role == .row })
        #expect(rows.map(\.rowIndex) == (38..<50).map { $0 }, "label: \(label ?? "nil")")
        let texts = table.children.map { tree.childNodes(of: $0).map(\.value) }
        #expect(texts == (38..<50).map { ["Row \($0)"] }, "each row holds its own text")
    }
}

/// Activated before the first draw, a window's `List` publishes its table and
/// row count with **no rows** on frame 0, whose window is unbounded, and asks
/// for exactly one more frame, which publishes the realized window (AB-X).
///
/// **Frame 1 is reached only through the list's own retry**: nothing calls
/// `setNeedsRedraw()` between frames 0 and 1. The cap arm is a scroller of
/// height 0, which never measures a viewport: one retry, then clean. The
/// inactive arm is the 200pt window with no client: frame 0 leaves it clean.
/// The no-context arm is an active list outside any scroller: unbounded for
/// good, so it never asks.
///
/// The two published trees go into a real bridge: no element is created and
/// nothing is destroyed across them.
///
/// **The table on frame 0 is the suppression scope's exception**, so this is
/// the first reader of it (lane 1's surviving mutant M33).
///
/// **Both authorities since stage 4's lane 4** (`LR-BU`; spec §4.1 row 4). It
/// holds `AB-X` rules 1 and 3 — no rows while the window is unbounded, and
/// exactly one retry frame — and stage 4 changed what a bounded window's rows
/// lower to. `makeFakeWindow` builds PRODUCTION frames, so the `.proposal` arm
/// traps on anything unlowered rather than reporting it; every fixture it
/// reaches was measured in a child process first (`LR-CF`).
///
/// Mutations **M4b** (`indexesRows` forced true) and **M4c**
/// (`requestAccessibilityRetry()` removed) are both counted against this test on
/// both authorities.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded(_ authority: LayoutAuthority) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    AuthorityCoverage.record(#function, authority)
    let feed = BridgeFeed()
    defer { feed.nsWindow.close() }
    let (window, platform) = try makeFakeWindow(device: device, size: 200,
                                                layoutAuthority: authority) {
        scrolledList(5000, height: 200)
    }
    #expect(platform.simulateAccessibilityRequest(.activate))

    window.drawFrameIfNeeded()
    try #require(window.framesDrawn == 1)
    #expect(window.accessibility.lastEmissionCount <= 3, "frame 0 records the table, not 10,000 rows and texts")
    let frame0 = try #require(platform.publishedAccessibilityTrees.last)
    let (_, table0) = try #require(frame0.all(.table).first, "the table is published on frame 0")
    #expect(table0.rowCount == 5000)
    #expect(table0.children.isEmpty, "no rows while the window is unbounded")
    #expect(window.needsRedraw, "the list asked for one more frame")
    feed.sync(platform)

    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == 2, "frame 1 is drawn with no input and no setNeedsRedraw")
    let frame1 = try #require(platform.publishedAccessibilityTrees.last)
    let (_, table1) = try #require(frame1.all(.table).first)
    // Offset 0, viewport 200, rows 28: rows 0..<8 (200 / 28 = 7.1, rounded up), plus 2 of overscan.
    #expect(table1.children.count == 10, "frame 1 publishes the realized window")
    #expect(!window.needsRedraw, "and asks for nothing more")
    feed.sync(platform)
    #expect(feed.bridge.createdElementCount == 0)
    #expect(feed.poster.count(.uiElementDestroyed) == 0)

    // Cap: a scroller that never measures a viewport retries once, not forever.
    let (capped, cappedPlatform) = try makeFakeWindow(device: device, size: 200,
                                                      layoutAuthority: authority) {
        scrolledList(500, height: 0)
    }
    cappedPlatform.simulateAccessibilityRequest(.activate)
    capped.drawFrameIfNeeded()
    #expect(capped.needsRedraw, "cap arm: frame 0 asks for one retry")
    capped.drawFrameIfNeeded()
    #expect(capped.framesDrawn == 2, "cap arm: the retry frame is drawn")
    #expect(!capped.needsRedraw, "cap arm: a second unbounded frame in a row does not ask again")

    // Inactive: nothing collects, so nothing retries.
    let (idle, _) = try makeFakeWindow(device: device, size: 200,
                                       layoutAuthority: authority) {
        scrolledList(500, height: 200)
    }
    idle.drawFrameIfNeeded()
    try #require(idle.framesDrawn == 1)
    #expect(!idle.needsRedraw, "inactive arm: rendering is unchanged, the window goes clean")

    // No scroll context: nothing the next frame learns could bound the window,
    // so the list never asks (surviving mutant N52 asked once).
    let (unscrolled, unscrolledPlatform) = try makeFakeWindow(device: device, size: 200,
                                                              layoutAuthority: authority) {
        Box { List((0..<50).map(Item.init), rowHeight: px(28)) { _ in Box().cssWidth(px(20)).cssHeight(px(28)) } }
            .cssWidth(px(200)).cssHeight(px(200))
    }
    unscrolledPlatform.simulateAccessibilityRequest(.activate)
    unscrolled.drawFrameIfNeeded()
    try #require(unscrolled.framesDrawn == 1)
    let unscrolledTable = try #require(unscrolledPlatform.publishedAccessibilityTrees.last?.all(.table).first)
    #expect(unscrolledTable.node.children.isEmpty, "control: its window is unbounded, so no rows")
    #expect(!unscrolled.needsRedraw, "no-context arm: a list outside a scroller does not retry")
}

/// Scrolling a list a client has read posts one `.layoutChanged`, destroys each
/// vended row once as it leaves, and builds once per drawn frame (AB-K, AB-X).
///
/// 60 frames of 20pt carry the view 1,200pt, from rows 0..<10 to 40..<52, so
/// every row vended at the start leaves.
///
/// **Both authorities since stage 4's lane 4** (`LR-BU`; spec §4.1 row 4). A
/// scrolling list is where the window slides, so it is where the realized set —
/// and therefore which rows are vended, destroyed and re-published — depends on
/// what stage 4 replaced. `makeFakeWindow` builds PRODUCTION frames.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame(_ authority: LayoutAuthority) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    AuthorityCoverage.record(#function, authority)
    let feed = BridgeFeed()
    defer { feed.nsWindow.close() }
    let (window, platform) = try makeFakeWindow(device: device, size: 200,
                                                layoutAuthority: authority) {
        scrolledList(500, height: 200)
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    try #require(!window.needsRedraw)
    feed.sync(platform)

    feed.bridge.noteClientRead()
    let roots = feed.bridge.rootElements().compactMap { $0 as? NSAccessibilityElement }
    try #require(roots.count == 1)
    let table = roots[0]
    let vended = (table.accessibilityRows() ?? []).compactMap { $0 as? NSAccessibilityElement }
    try #require(vended.count == 10, "rows 0..<10 are realized at offset 0")
    let created = feed.bridge.createdElementCount
    let builds = window.accessibility.buildCount
    feed.poster.reset()

    for _ in 0..<60 {
        platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: px(100), y: px(100)),
                                                        delta: Point(x: px(0), y: px(-20)))))
        window.drawFrameIfNeeded()
        feed.sync(platform)
    }
    #expect(window.accessibility.buildCount == builds + 60, "one build per drawn frame")
    #expect(feed.poster.count(.layoutChanged) == 1, "one per client read, however many structural publishes")
    let destroyed = feed.poster.posts.filter { $0.name == .uiElementDestroyed }.map(\.element)
    #expect(destroyed.count == vended.count, "each vended row, once")
    #expect(vended.allSatisfy { row in destroyed.contains { $0 === row } })
    #expect(feed.poster.count(.titleChanged) == 0 && feed.poster.count(.valueChanged) == 0)
    #expect(feed.bridge.createdElementCount == created, "nothing is created that no client read")
}

/// The one model the animation test drives, so the write reaches the window
/// through `@Observable`'s production dirty path.
@Observable private final class GrowModel {
    var wide = false
}

/// A geometry-only animation with a client active posts nothing, republishes
/// only geometry, and keeps the vended element, whose frame follows (AB-K).
@Test @MainActor func anAnimationWithAClientActivePostsNothingAndTouchesNoElement() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let feed = BridgeFeed()
    defer { feed.nsWindow.close() }
    let model = GrowModel()
    let (window, platform) = try makeFakeWindow(device: device, size: 200, startsDisplayLink: true) {
        Column { Box().cssWidth(px(model.wide ? 120 : 40)).cssHeight(px(20)).accessibilityLabel("Grow") }
    }
    platform.simulateAccessibilityRequest(.activate)
    platform.simulateTick(timestamp: 100)
    try #require(!window.needsRedraw)
    feed.sync(platform)
    feed.bridge.noteClientRead()
    let element = try #require(feed.bridge.rootElements().first as? NSAccessibilityElement)
    try #require(element.accessibilityLabel() == "Grow")
    let structural = feed.bridge.structuralPublishCount
    let geometric = feed.bridge.geometryPublishCount
    let publishes = window.accessibility.publishCount
    feed.poster.reset()

    withAnimation(.linear(duration: 1)) { model.wide = true }
    for tick in 1...30 {
        platform.simulateTick(timestamp: 100 + Double(tick) * 0.04)
        feed.sync(platform)
    }
    #expect(feed.poster.posts.isEmpty, "an animation posts nothing")
    #expect(feed.bridge.structuralPublishCount == structural)
    let rise = window.accessibility.publishCount - publishes
    #expect(rise > 0 && rise <= 30)
    #expect(feed.bridge.geometryPublishCount - geometric == rise, "every publish was geometry only")
    #expect(feed.bridge.rootElements().first as? NSAccessibilityElement === element)
    let lastWidth = try #require(platform.publishedAccessibilityTrees.last?.geometry.values.first)
        .frame.size.width.value
    #expect(lastWidth == 120, "control: the animation landed at 1.2 s of a 1 s curve")
    #expect(element.accessibilityFrame().width == CGFloat(lastWidth))
}

// MARK: - Cost (AB-U, AB-M, AB-L)

/// A client does not change what the state table retains (AB-U): 130 texts, 10
/// click targets and a bounded `List`, three frames in an active and an idle
/// window, equal `StateTable.count`.
///
/// **The `List` is this file's addition to the spec's fixture**, for `AB-AA`'s
/// claim that this test guards the `logicalIndex` strip: only a bounded list's
/// rows carry the hint, and a hint that were a declaration would write a `$ax`
/// slot per realized row only in the active window.
///
/// **Both authorities since stage 4's lane 4** (`LR-BU`). Stage 4 took the
/// spacer `Box` out of the proposal path, and this is the file's only equality
/// between two whole `StateTable`s — the place a per-row entry appearing or
/// disappearing with the client would show. `makeFakeWindow` builds PRODUCTION
/// frames, and here `scrolledList` is a flex ITEM rather than the root, so its
/// record is consumed either way.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aClientDoesNotChangeStateRetention(_ authority: LayoutAuthority) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    AuthorityCoverage.record(#function, authority)
    func content() -> some Element {
        Row {
            Column { for i in 0..<130 { Text("t\(i)") } }
            Column { for _ in 0..<10 { Box().frame(width: px(10), height: px(10)).onClick {} } }
            scrolledList(200, height: 200)
        }
    }
    let (active, activePlatform) = try makeFakeWindow(device: device, size: 300,
                                                      layoutAuthority: authority) { content() }
    let (idle, _) = try makeFakeWindow(device: device, size: 300,
                                       layoutAuthority: authority) { content() }
    activePlatform.simulateAccessibilityRequest(.activate)
    for _ in 0..<3 {
        active.setNeedsRedraw(); active.drawFrameIfNeeded()
        idle.setNeedsRedraw(); idle.drawFrameIfNeeded()
    }
    try #require(active.framesDrawn == 3 && idle.framesDrawn == 3)
    try #require(active.accessibility.lastEmissionCount >= 140,
                 "shape 15: the active window really recorded its texts and click targets")
    let published = try #require(activePlatform.publishedAccessibilityTrees.last)
    try #require(!published.all(.row).isEmpty, "control: the list was bounded, so its rows carried hints")
    #expect(active.stateTable.count == idle.stateTable.count)
}

/// With no client, synthesized content costs no record and no emission; with
/// one, it records and still emits only the list's own node (AB-U, AB-L). The
/// list is bounded on the second frame, so its rows carry the row hint there,
/// and a hint is not a declaration.
@Test @MainActor func synthesizedNodesCostNothingWhileNoClientIsActive() throws {
    func content() -> some Element {
        Column {
            Text("T")
            Box().frame(width: px(40), height: px(20)).onClick {}
            scrolledList(500, height: 200)
        }
    }
    let idleTable = StateTable()
    _ = collect(content(), stateTable: idleTable, collects: false)
    let (idle, _) = collect(content(), stateTable: idleTable, collects: false)
    #expect(idle.axNodes.count == 1, "the list's own node, today's contract")
    #expect(idle.axEmissions.isEmpty)

    let activeTable = StateTable()
    _ = collect(content(), stateTable: activeTable)
    let (active, tree) = collect(content(), stateTable: activeTable)
    try #require(!tree.all(.row).isEmpty, "control: the second frame's window is bounded")
    #expect(active.axEmissions.count > 1)
    #expect(active.axNodes.count == 1, "a row hint and synthesized nodes emit nothing")
}

/// `OnTapModifier` synthesizes nothing, and its hitbox still routes a press by
/// id (AB-Y).
@Test @MainActor func anOnTapModifierPublishesNothingButItsHitboxStillPresses() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let tally = Tally()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        HStack { Rectangle(width: px(40), height: px(20), color: .accent).onTap { tally.count += 1 } }
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    try #require(window.accessibility.buildCount >= 1, "control: the window was active and built")
    #expect(window.accessibility.lastEmissionCount == 0, "onTap records nothing")
    #expect(window.accessibility.lastPublished.nodes.isEmpty)
    #expect(platform.publishedAccessibilityTrees.allSatisfy { $0.nodes.isEmpty })

    let tap = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil }).id
    #expect(platform.simulateAccessibilityRequest(.press(AccessibilityNodeID(tap))))
    #expect(tally.count == 1)
}

/// A `List` inside `display: none` content publishes nothing even on its
/// unbounded frame, where it opens a suppression scope excepting itself: the
/// **outermost** scope's exception decides (`Frame.isAccessibilitySuppressed`),
/// so the hidden ancestor's `nil` wins. The control is the same tree shown.
///
/// **Not in the spec's table; added by lane 3's implementer**, because no other
/// test nests the list's scope inside another, so answering from the innermost
/// scope would be unguarded.
///
/// **Legacy-only, and that is a finding rather than an omission** (`LR-CF`).
/// Spec §6 lane 4 lists this test as a both-authorities arm and makes it half of
/// mutation M4b's required failure count. It cannot be either: its subject is
/// `hidden()`, and `display: none` has no proposal lowering at all
/// (`LegacyLowering.swift:161` returns `display.none` before any other field is
/// read), so a `.proposal` frame over this fixture aborts rather than failing.
/// `aHiddenListNoLongerAbortsAProductionProposalFrame` above was that abort and
/// its shown control (inverted by stage 6b's lane 1); when a later stage lowers `display`, this test
/// gains its `.proposal` arm and `AuthorityCoverage.expected` gains its name.
///
/// **Both authorities since stage 6b's lane 1** (`LR-DH`): the finding above is
/// closed — `hidden()` lowers as if shown under the proposal authority and joins
/// `Frame.hiddenNodes`, which the outermost suppression scope reads — so this test
/// gained its `.proposal` arm and `AuthorityCoverage.expected` its name, as the
/// paragraph above said it would.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func content(hidden: Bool) -> some Element {
        let box = Box {
            List((0..<50).map(Item.init), rowHeight: px(28)) { _ in Box().frame(width: px(20), height: px(28)) }
        }
        .frame(width: px(40), height: px(40), alignment: .topLeading)
        return Column {
            hidden ? box.hidden() : box
            Text("shown")
        }
    }
    let (_, shown) = collect(content(hidden: false), authority: authority)
    try #require(shown.all(.table).count == 1, "control: an unbounded list publishes its table")

    let (_, hidden) = collect(content(hidden: true), authority: authority)
    #expect(hidden.all(.table).isEmpty, "a hidden ancestor silences the list's own exception")
    #expect(hidden.rootNodes.map(\.value) == ["shown"])
}
