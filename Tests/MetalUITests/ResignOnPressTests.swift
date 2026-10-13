import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Resign on press (C24; rulings `RF-A`…`RF-G`, spec
// `docs/superpowers/specs/2026-10-12-resign-on-press-design.md` §4, tests 1-15).
// MetalUI-only: SwiftUI has no such modifier (probe `swiftui-resign-on-press.swift`
// RP0-RP12). The modifier rides `KF-F`'s non-claiming `focusOnPress` stage and
// registers the one non-opaque key/press region; it routes no key by hover.
//
// Windows are 200 × 200 over `FakePlatformWindow`, roots centred (`CN-J`).
// Focus is read right after the press, before any frame. Red before: the
// modifier does not exist (these do not compile).

// MARK: - Harness

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func down(_ p: Point<Pixels>) -> InputEvent { .mouseDown(MouseEvent(position: p)) }
private func up(_ p: Point<Pixels>) -> InputEvent { .mouseUp(MouseEvent(position: p)) }
private func kd(_ c: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, timestamp: 0))
}

@MainActor private final class RPLog {
    var log: [String] = []
    var text = "abc"
    var texts = ["a", "b"]
    var flags: [Bool] = []
    var fields: [RPField?] = []
    var enabled = true
}

private enum RPField: Hashable { case a, b }

@MainActor private func rpWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor private func click(_ platform: FakePlatformWindow, _ p: Point<Pixels>) {
    platform.simulateInput(down(p))
    platform.simulateInput(up(p))
}

@MainActor private func square(_ size: Float) -> some StyledElement {
    Box().frame(width: px(size), height: px(size))
}

private func centreOf(_ b: Bounds<Pixels>) -> Point<Pixels> {
    pt(b.origin.x.value + b.size.width.value / 2, b.origin.y.value + b.size.height.value / 2)
}

/// The corner of `b` nearest its far corner, 5 inside.
private func farCorner(_ b: Bounds<Pixels>) -> Point<Pixels> {
    pt(b.origin.x.value + b.size.width.value - 5, b.origin.y.value + b.size.height.value - 5)
}

/// The last frame's resign-flagged regions.
@MainActor private func resignRegions(_ window: Window) -> [Hitbox] {
    window.lastHitboxes.filter { $0.handlers.keyboard?.resignsOnPress == true }
}

/// A 200-square region (optionally resigning) holding one plain focusable
/// square in its top-left corner; focus is given to the square.
@MainActor private func focusedRegionWindow(resigns: Bool = true) throws
    -> (Window, FakePlatformWindow, GlobalElementID, Bounds<Pixels>) {
    let (window, platform) = try rpWindow {
        Box { square(20).focusable() }
            .frame(width: px(200), height: px(200))
            .resignsFocusOnPress(resigns)
    }
    let id = try #require(window.lastFocusRegistry.tabOrder.first)
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "set up: focused")
    // The root is centred in the 200-point window, so the region is the whole of it.
    let region = Bounds(origin: pt(0, 0), size: Size(width: px(200), height: px(200)))
    if resigns { try #require(resignRegions(window).count == 1, "set up: the region registered") }
    return (window, platform, id, region)
}

// MARK: - 1: the press resigns

/// **1** (`RF-C` item 3). A primary press on inert chrome inside a resign
/// region clears a focused element's focus. Red before: does not compile.
/// Mutation: drop `|| resignsOnPress` from `focusOnPress`'s `region` predicate.
@MainActor
@Test func aPressOnInertChromeResignsAFocusedField() throws {
    let (window, platform, _, region) = try focusedRegionWindow()
    click(platform, farCorner(region))
    #expect(window.focusedElement == nil, "the press on the region's blank corner resigned")

    let (plain, plainPlatform, id, plainRegion) = try focusedRegionWindow(resigns: false)
    click(plainPlatform, farCorner(plainRegion))
    #expect(plain.focusedElement == id, "control: without the modifier a press elsewhere resigns nothing (KF-G)")
}

// MARK: - 2: no key routed by hover

@MainActor private func routedTree(_ m: RPLog, key: Bool) -> some Element {
    let base = Box().frame(width: px(200), height: px(200))
        .onKeyPress { press in m.log.append("heard \(press.characters)"); return .handled }
    return Box { if key { base.hoverKeyRegion() } else { base.resignsFocusOnPress() } }
}

/// **2** (`RF-C` item 3, `KF-U`). Nothing focused, the pointer over a resign
/// region: the key chain is empty, an `onKeyPress` on it hears nothing. The same
/// tree with `hoverKeyRegion()` hears the key (the separating arm).
/// Mutation: count a resign region in `keyRegionCount` / admit it in
/// `coversKeys(withPressRegions: false)`.
@MainActor
@Test func aResignRegionRoutesNoKeysByHover() throws {
    for key in [true, false] {
        let m = RPLog()
        let (window, platform) = try rpWindow { routedTree(m, key: key) }
        platform.simulateInput(.mouseMoved(MouseEvent(position: pt(100, 100))))
        platform.simulateInput(kd("x"))
        if key {
            #expect(m.log == ["heard x"], "control: a key region routes the key: \(m.log)")
        } else {
            #expect(window.keyChain.isEmpty, "a resign region contributes no chain")
            #expect(m.log.isEmpty, "and its onKeyPress heard nothing: \(m.log)")
            #expect(window.lastKeyRegionCount == 0 && window.lastResignRegionCount == 1,
                    "it is a resign region, not a key region")
        }
    }
}

// MARK: - 3: field to field

@MainActor private struct RPTwoFields: Component {
    @FocusState var focused: RPField?
    let m: RPLog
    var content: some ElementGroup {
        let _ = m.fields.append(focused)
        Column {
            TextField("a", text: m.texts[0]) { m.texts[0] = $0 }.focused($focused, equals: .a)
                .frame(width: px(100), height: px(24))
            TextField("b", text: m.texts[1]) { m.texts[1] = $0 }.focused($focused, equals: .b)
                .frame(width: px(100), height: px(24))
        }
        .frame(width: px(200), height: px(200))
        .resignsFocusOnPress()
    }
}

/// **3** (`RF-E`, `KF-E` item 5). A press from field A onto field B moves
/// focus directly: B is focused at the end of the event and the `@FocusState`
/// reads `.a` then `.b`, never `nil` between. (An intermediate `nil` inside
/// one event is invisible to a frame-based reading, `KX`: the end state is the
/// pin.) Mutations (`RF-G` 2): delete the text-field early return in
/// `focusOnPress`; if green, put ladder step 3 before step 2.
@MainActor
@Test func aPressFromOneFieldToAnotherMovesFocusDirectly() throws {
    let m = RPLog()
    let (window, platform) = try rpWindow { Row { RPTwoFields(m: m) } }
    let fields = window.lastHitboxes.filter { $0.handlers.textInput != nil }
    try #require(fields.count == 2, "set up: two fields")
    click(platform, centreOf(fields[0].bounds))
    for _ in 0..<3 { window.drawFrameIfNeeded() }
    try #require(window.focusedElement == fields[0].id, "set up: A focused")
    m.fields = []
    click(platform, centreOf(fields[1].bounds))
    #expect(window.focusedElement == fields[1].id, "B holds focus at the end of the event")
    for _ in 0..<3 { window.drawFrameIfNeeded() }
    let seen = m.fields
    #expect(!seen.contains { $0 == nil }, "no nil between: \(seen)")
    #expect(seen.last == .some(.b), "ends on b: \(seen)")
}

// MARK: - 4: a click-focusable inside

/// **4** (`RF-E`). A press on a `.focusable(interactions: .edit)` element inside
/// a resign region focuses it (one change), a press on blank space beside it
/// resigns. Mutation: test `else if region != nil` before the `focusable` arm.
@MainActor
@Test func aPressOnAClickFocusableInsideFocusesItNotNil() throws {
    let (window, platform) = try rpWindow {
        Box {
            square(20).focusable()
            square(60).focusable(interactions: .edit)
        }
        .frame(width: px(200), height: px(200))
        .resignsFocusOnPress()
    }
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 2, "set up: \(order)")
    window.focus(order[0])
    window.drawFrameIfNeeded()
    let edit = try #require(window.lastHitboxes.first { $0.id == order[1] && $0.handlers.keyboard != nil })
    click(platform, centreOf(edit.bounds))
    #expect(window.focusedElement == order[1], "the click-focusable took focus, not nil")
    let region = try #require(resignRegions(window).first { $0.bounds.size.width.value == 200 })
    click(platform, farCorner(region.bounds))
    #expect(window.focusedElement == nil, "control: blank space beside it resigned")
}

// MARK: - 5: secondary and other presses

/// **5** (`RF-D`, `MN-B`). A secondary or other-button press never resigns.
/// Control: the primary press does. Mutation: run the stage on `.rightMouseDown`.
@MainActor
@Test func aSecondaryAndOtherPressResignNothing() throws {
    let (window, platform, id, region) = try focusedRegionWindow()
    let p = farCorner(region)
    platform.simulateInput(.rightMouseDown(MouseEvent(position: p)))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: p)))
    platform.simulateInput(.otherMouseDown(MouseEvent(position: p)))
    platform.simulateInput(.otherMouseUp(MouseEvent(position: p)))
    #expect(window.focusedElement == id, "only a primary press resigns")
    click(platform, p)
    #expect(window.focusedElement == nil, "control: the primary press resigned")
}

// MARK: - 6: the gates

/// **6** (`RF-D`). `.disabled(true)`, `.hidden()` and `.allowsHitTesting(false)`
/// each withdraw the region: a press on it resigns nothing (arm `none` is the
/// control that does). Mutations, one each: drop `enabled`,
/// `hitTestingDisabledDepth == 0`, `keyboardHiddenDepth == 0` from the
/// registration condition.
@MainActor
@Test func disabledHiddenAndAllowsHitTestingWithdrawTheResignRegion() throws {
    for gate in ["none", "disabled", "hidden", "allowsHitTesting"] {
        let (window, platform) = try rpWindow {
            HStack(spacing: 0) {
                let region = square(100).resignsFocusOnPress()
                switch gate {
                case "disabled": region.disabled(true)
                case "hidden": region.hidden()
                case "allowsHitTesting": region.allowsHitTesting(false)
                default: region
                }
                square(100).focusable()
            }
        }
        let id = try #require(window.lastFocusRegistry.tabOrder.first, "\(gate): set up")
        window.focus(id)
        window.drawFrameIfNeeded()
        click(platform, pt(50, 100))
        if gate == "none" {
            #expect(window.focusedElement == nil, "control: the ungated region resigned")
        } else {
            #expect(window.focusedElement == id, "\(gate): a press on the withdrawn region resigned nothing")
            #expect(resignRegions(window).isEmpty, "\(gate): no region registered")
        }
    }
}

// MARK: - 7, 8: the one ranking

/// **7** (`RF-D`, `IX-Q`). A press on a popover declared inside a region is on
/// another layer: no resign. Control: the region's corner resigns. Mutation:
/// drop `box.layer == cover.layer` in `focusOnPress`.
@MainActor
@Test func aDeferredPresentationPressDoesNotResignThroughARegionBelow() throws {
    let m = RPLog()
    let (window, platform) = try rpWindow {
        Box {
            Column {
                square(20).focusable()
                square(20).popover(isPresented: .constant(true)) {
                    square(40).onClick { m.log.append("click") }
                }
            }
        }
        .frame(width: px(200), height: px(200))
        .resignsFocusOnPress()
    }
    for _ in 0..<4 where window.needsRedraw { window.drawFrameIfNeeded() }
    let focusable = try #require(window.lastFocusRegistry.tabOrder.first)
    let region = try #require(resignRegions(window).first)
    let popover = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil })
    try #require(popover.layer != region.layer && region.contains(centreOf(popover.bounds)),
                 "set up: the popover is on its own layer, inside the region")
    window.focus(focusable)
    window.drawFrameIfNeeded()
    click(platform, centreOf(popover.bounds))
    #expect(m.log == ["click"], "the popover's click landed: \(m.log)")
    #expect(window.focusedElement == focusable, "a press on the region's own popover resigned nothing")
    click(platform, farCorner(region.bounds))
    #expect(window.focusedElement == nil, "control: the region's corner resigned")
}

/// **8** (`RF-C` item 4). A press on an opaque sibling drawn above the region
/// changes no focus and the click lands; the region beside it resigns.
/// Mutation: drop `cover.id.isOrDescends(from: box.id)` in `focusOnPress`.
@MainActor
@Test func aPressOnAnOpaqueSiblingAboveTheRegionChangesNoFocus() throws {
    let m = RPLog()
    let (window, platform) = try rpWindow {
        VStack {
            ZStack {
                Box().frame(width: px(200), height: px(150)).resignsFocusOnPress()
                square(40).onClick { m.log.append("click") }
            }
            square(20).focusable()
        }
    }
    let focusable = try #require(window.lastFocusRegistry.tabOrder.first)
    let button = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil })
    let region = try #require(resignRegions(window).first)
    window.focus(focusable)
    window.drawFrameIfNeeded()
    click(platform, centreOf(button.bounds))
    #expect(m.log == ["click"], "the click landed: \(m.log)")
    #expect(window.focusedElement == focusable, "a press on the sibling above the region kept focus")
    let corner = pt(region.bounds.origin.x.value + 5, region.bounds.origin.y.value + 5)
    try #require(!button.contains(corner), "set up: the corner is off the button")
    click(platform, corner)
    #expect(window.focusedElement == nil, "control: the region itself resigns")
}

// MARK: - 9: counted work

/// **9** (`RF-C` item 3). A window with no region does no press lookup; with a
/// resign region each primary press costs one. Mutation: remove the
/// `lastResignRegionCount` term from the count guard (the empty window then
/// would look up, or the region's window not at all).
@MainActor
@Test func aWindowWithNoRegionDoesNoPressLookup() throws {
    let (bare, barePlatform) = try rpWindow { square(100).onClick { } }
    for _ in 0..<3 { click(barePlatform, pt(100, 100)) }
    #expect(bare.keyRegionLookups == 0, "no region registered: no lookup")

    let (window, platform) = try rpWindow { square(100).resignsFocusOnPress() }
    #expect(window.lastResignRegionCount == 1 && window.lastKeyRegionCount == 0, "set up")
    let start = window.keyRegionLookups
    for _ in 0..<3 { click(platform, pt(100, 100)) }
    #expect(window.keyRegionLookups == start + 3, "one lookup per press: \(window.keyRegionLookups - start)")
    for i in 0..<20 { platform.simulateInput(.mouseMoved(MouseEvent(position: pt(90 + Float(i), 100)))) }
    #expect(window.keyRegionLookups == start + 3, "pointer moves cost none")
}

// MARK: - 10: non-opaque

@MainActor private func rpA32Tree(_ m: RPLog, region: Bool) -> some Element {
    let cover = square(200)
    return ZStack {
        square(200)
            .onClick { m.log.append("click") }
            .onHover { m.log.append("hover \($0)") }
            .onScrollWheel { _ in m.log.append("wheel"); return true }
        square(30).onTapGesture { m.log.append("tap") }
        if region { cover.resignsFocusOnPress() } else { cover }
    }
}

@MainActor private func rpScript(region: Bool) throws -> [String] {
    let m = RPLog()
    let (window, platform) = try rpWindow { rpA32Tree(m, region: region) }
    if region { try #require(resignRegions(window).count == 1, "set up: the region registers") }
    platform.simulateInput(.mouseMoved(MouseEvent(position: pt(50, 50))))
    click(platform, pt(50, 50))
    click(platform, pt(100, 100))
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(50, 50), delta: Point(x: px(0), y: px(5)))))
    platform.simulateInput(.pointerExited)
    return m.log
}

/// **10** (`RF-D`, `RF-E`). The region is non-opaque: click, hover, wheel and a
/// tap beneath behave identically with it; and a `Button` inside fires **and**
/// resigns. Mutation: register the region `opaque: true`.
@MainActor
@Test func aResignRegionIsNonOpaqueAndABeneathTapStillRuns() throws {
    let without = try rpScript(region: false)
    try #require(without.contains("click") && without.contains("tap") && without.contains("wheel")
                    && without.contains("hover true"), "control: every outcome happens without it: \(without)")
    #expect(try rpScript(region: true) == without, "identical with the region")

    let m = RPLog()
    let (window, platform) = try rpWindow {
        Box {
            square(20).focusable()
            Button("B") { m.log.append("button") }.frame(width: px(60), height: px(60))
        }
        .frame(width: px(200), height: px(200))
        .resignsFocusOnPress()
    }
    let focusable = try #require(window.lastFocusRegistry.tabOrder.first)
    window.focus(focusable)
    window.drawFrameIfNeeded()
    let button = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil })
    click(platform, centreOf(button.bounds))
    #expect(m.log == ["button"], "the Button fired: \(m.log)")
    #expect(window.focusedElement == nil, "and the press resigned (RF-E)")
}

// MARK: - 11: one write, or none

@MainActor private struct RPBoolFocus: Component {
    @FocusState var focused: Bool
    let m: RPLog
    let region: Bool
    var content: some ElementGroup {
        let _ = m.flags.append(focused)
        let field = Column {
            square(20).focusable().focused($focused)
        }
        .frame(width: px(200), height: px(200))
        if region { field.resignsFocusOnPress() } else { field }
    }
}

/// **11** (`RF-C`). A resign is one `@FocusState` write when something is
/// focused (`true` then `false`, once) and none when nothing is: a press with
/// nothing focused costs the frames a press without the region costs.
/// Mutation: an unconditional `focusState` write on the press (instrument may
/// be equivalent, `focus(_:)` is guarded; recorded).
@MainActor
@Test func aResignIsOneFocusStateWriteAndNothingWhenNothingIsFocused() throws {
    let m = RPLog()
    let (window, platform) = try rpWindow { Row { RPBoolFocus(m: m, region: true) } }
    let id = try #require(window.lastFocusRegistry.tabOrder.first)
    window.focus(id)
    for _ in 0..<3 { window.drawFrameIfNeeded() }
    try #require(m.flags.last == true, "set up: the state reads true")
    let region = try #require(resignRegions(window).first)
    m.flags = []
    click(platform, farCorner(region.bounds))
    for _ in 0..<3 { window.drawFrameIfNeeded() }
    var changes = 0
    var previous = true
    for f in m.flags where f != previous { changes += 1; previous = f }
    #expect(changes == 1 && m.flags.last == false, "one true to false change: \(m.flags)")

    // Nothing focused: the same press builds exactly what it builds without the region.
    func builds(region: Bool) throws -> Int {
        let m = RPLog()
        let (window, platform) = try rpWindow { Row { RPBoolFocus(m: m, region: region) } }
        for _ in 0..<3 { window.drawFrameIfNeeded() }
        let start = m.flags.count
        click(platform, pt(190, 190))
        for _ in 0..<3 { window.drawFrameIfNeeded() }
        return m.flags.count - start
    }
    #expect(try builds(region: true) == builds(region: false), "no focus change, no extra build")
}

// MARK: - 12: every order keeps the flag

private enum RPOp: CaseIterable { case key, edit, hover, resign }

private func permutations(_ ops: [RPOp]) -> [[RPOp]] {
    guard ops.count > 1 else { return [ops] }
    return ops.indices.flatMap { i -> [[RPOp]] in
        var rest = ops
        let head = rest.remove(at: i)
        return permutations(rest).map { [head] + $0 }
    }
}

@MainActor private func applyLegacy<E: StyledElement>(_ e: E, _ op: RPOp) -> E {
    switch op {
    case .key: return e.onKeyPress { _ in .ignored }
    case .edit: return e.focusable(interactions: .edit)
    case .hover: return e.hoverKeyRegion()
    case .resign: return e.resignsFocusOnPress()
    }
}

@MainActor private func applyFirst(_ e: Rectangle, _ op: RPOp) -> KeyboardModifier<Rectangle> {
    switch op {
    case .key: return e.onKeyPress { _ in .ignored }
    case .edit: return e.focusable(interactions: .edit)
    case .hover: return e.hoverKeyRegion()
    case .resign: return e.resignsFocusOnPress()
    }
}

@MainActor private func applyNext(_ e: KeyboardModifier<Rectangle>, _ op: RPOp) -> KeyboardModifier<Rectangle> {
    switch op {
    case .key: return e.onKeyPress { _ in .ignored }
    case .edit: return e.focusable(interactions: .edit)
    case .hover: return e.hoverKeyRegion()
    case .resign: return e.resignsFocusOnPress()
    }
}

@MainActor private func checkAttachment(_ window: Window, _ order: [RPOp], _ vocabulary: String) {
    let boxes = window.lastHitboxes.filter { $0.handlers.keyboard != nil }
    guard let keyboard = boxes.first?.handlers.keyboard, boxes.count == 1 else {
        Issue.record("\(vocabulary) \(order): expected one keyboard hitbox, got \(boxes.count)")
        return
    }
    let ok = keyboard.keyPresses.count == 1 && keyboard.focusInteractions?.contains(.edit) == true
        && keyboard.isKeyRegion && keyboard.resignsOnPress
    #expect(ok, "\(vocabulary) \(order) lost a field: presses \(keyboard.keyPresses.count), edit \(keyboard.focusInteractions != nil), key \(keyboard.isKeyRegion), resign \(keyboard.resignsOnPress)")
}

/// **12** (`RF-C` item 1). All 24 orderings of `resignsFocusOnPress`,
/// `onKeyPress`, `focusable(interactions:)` and `hoverKeyRegion` keep every
/// field of the one `KeyboardAttachment`, on both vocabularies. Mutation:
/// `adding` (then `interactions`, then `keyRegion`) omits `resignsOnPress`.
@MainActor
@Test func everyKeyboardModifierOrderKeepsTheResignFlag() throws {
    let orders = permutations(RPOp.allCases)
    try #require(orders.count == 24)
    for order in orders {
        let (legacy, _) = try rpWindow {
            var e = Box().frame(width: px(100), height: px(100))
            for op in order { e = applyLegacy(e, op) }
            return e
        }
        checkAttachment(legacy, order, "legacy")
        let (proposal, _) = try rpWindow {
            var e = applyFirst(Rectangle(width: px(100), height: px(100)), order[0])
            for op in order.dropFirst() { e = applyNext(e, op) }
            return e
        }
        checkAttachment(proposal, order, "proposal")
    }
}

// MARK: - 13: composition with a key region

/// **13** (`RF-F`). A key region with `resignsFocusOnPress(false)` (either
/// order) still clears focus; the withheld flag is not the key region's own.
/// Mutation: make `isKeyRegion` regions require the resign flag.
@MainActor
@Test func aKeyRegionWithResignFalseStillClears() throws {
    for hoverFirst in [true, false] {
        let (window, platform) = try rpWindow {
            Box { square(20).focusable() }
                .frame(width: px(200), height: px(200))
                .hoverKeyRegionAndResign(hoverFirst)
        }
        let id = try #require(window.lastFocusRegistry.tabOrder.first)
        window.focus(id)
        window.drawFrameIfNeeded()
        let region = try #require(window.lastHitboxes.first { $0.handlers.keyboard?.isKeyRegion == true })
        click(platform, farCorner(region.bounds))
        #expect(window.focusedElement == nil, "hoverFirst \(hoverFirst): the key region still cleared")
    }
}

extension StyledElement {
    fileprivate func hoverKeyRegionAndResign(_ hoverFirst: Bool) -> Self {
        hoverFirst ? hoverKeyRegion().resignsFocusOnPress(false) : resignsFocusOnPress(false).hoverKeyRegion()
    }
}

// MARK: - 14: toggling keeps state

@MainActor private struct RPInner: Component {
    @State var taps = 0
    let m: RPLog
    var content: some ElementGroup {
        let _ = m.log.append("taps \(taps)")
        Box().frame(width: px(100), height: px(100)).onClick { taps += 1 }
    }
}

@MainActor private struct RPToggled: Component {
    let m: RPLog
    var content: some ElementGroup {
        Box { RPInner(m: m) }.resignsFocusOnPress(m.enabled)
    }
}

/// **14** (`RF-F`, `MC-A`). Toggling `isEnabled` changes a value, never a layer
/// count or an identity: the `@State` of the wrapped element's content survives
/// `true` to `false`. Mutation: `.id(isEnabled ? "on" : "off")` on the legacy
/// spelling (the first version kept its state in the outer component and
/// could not see it, M14 green).
@MainActor
@Test func togglingIsEnabledKeepsTheWrappedState() throws {
    let m = RPLog()
    let (window, platform) = try rpWindow { Row { RPToggled(m: m) } }
    click(platform, pt(100, 100))
    for _ in 0..<2 { window.drawFrameIfNeeded() }
    try #require(m.log.last == "taps 1", "set up: one tap counted: \(m.log)")
    m.enabled = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(resignRegions(window).isEmpty, "set up: the region is off")
    #expect(m.log.last == "taps 1", "the state survived the toggle: \(m.log)")
    click(platform, pt(100, 100))
    for _ in 0..<2 { window.drawFrameIfNeeded() }
    #expect(m.log.last == "taps 2", "and keeps counting: \(m.log)")
}

// MARK: - 15: the Keymap is untouched

private struct RPGlobal: Action {}

/// **15** (`RF-F`). After a resign on the root, a plain Keymap binding still
/// fires with nothing focused — the key routing is what it always was.
@MainActor
@Test func aResignOnTheRootStillLeavesAKeymapGlobalShortcutWorking() throws {
    let m = RPLog()
    let (window, platform, _, region) = try focusedRegionWindow()
    window.keymap = Keymap([KeyBinding("g", RPGlobal())])
    window.onAction = { action in m.log.append(String(describing: type(of: action))); return true }
    click(platform, farCorner(region))
    try #require(window.focusedElement == nil, "set up: resigned")
    platform.simulateInput(kd("g"))
    #expect(m.log == ["RPGlobal"], "the global binding fired: \(m.log)")
}
