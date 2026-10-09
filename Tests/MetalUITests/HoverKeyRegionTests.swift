import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Key and focus scoping, lane A — `.hoverKeyRegion()` and the key chain
// (rulings `KF-D`, `KF-E`, `KF-U`; spec §4.2, §4.3, tests A18–A24, A45).
// MetalUI-only: SwiftUI routes no key by hover (K1u, K1v), so these rules are
// ruled on MetalCreator's use cases (M5-b, M5-g, M6's `Panel`/`!Panel`).
//
// Windows are 200 × 200 over `FakePlatformWindow`. A region's centre is read
// from the last frame's key-region hitboxes, so the stub (which registers
// none) fails at the `#require` that finds them.

// MARK: - Harness

private func kd(_ c: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: modifiers, timestamp: 0))
}

private func mv(_ p: Point<Pixels>) -> InputEvent { .mouseMoved(MouseEvent(position: p)) }
private func down(_ p: Point<Pixels>) -> InputEvent { .mouseDown(MouseEvent(position: p)) }
private func up(_ p: Point<Pixels>) -> InputEvent { .mouseUp(MouseEvent(position: p)) }
private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class HKLog {
    var log: [String] = []
    var text = ""
    var flags: [Bool] = []
    var selection: Int? = 0
    var selectionWrites: [Int?] = []
}

@MainActor private func hkWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// The last frame's key regions, in registration (outer-first) order.
@MainActor private func keyRegions(_ window: Window, count: Int) throws -> [Hitbox] {
    let regions = window.lastHitboxes.filter { $0.handlers.keyboard?.isKeyRegion == true }
    try #require(regions.count == count, "set up: \(count) key regions registered, got \(regions.count)")
    return regions
}

private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: px(b.origin.x.value + b.size.width.value / 2), y: px(b.origin.y.value + b.size.height.value / 2))
}

/// A 100 × 200 canvas region on the left and a 100 × 200 panel on the right
/// holding one focusable square; the canvas logs `canvas`, the square `square`.
@MainActor private func canvasAndPanel(_ m: HKLog) -> some Element {
    HStack(spacing: 0) {
        Box().frame(width: px(100), height: px(200)).hoverKeyRegion()
            .onKeyPress { press in m.log.append("canvas \(press.characters)"); return .handled }
        Box {
            Box().frame(width: px(20), height: px(20)).focusable()
                .onKeyPress { press in m.log.append("square \(press.characters)"); return .handled }
        }
        .frame(width: px(100), height: px(200))
    }
}

// MARK: - A18–A21: which chain

/// **A18** (`KF-D` item 1, `KF-E`). With nothing focused, the key region under
/// the pointer receives keys. Red before (and at `c62d6ba`): the chain is
/// empty and the key reaches nothing. Mutation: the key chain is the focus
/// chain always.
@MainActor
@Test func withNothingFocusedTheHoveredKeyRegionReceivesKeys() throws {
    let m = HKLog()
    let (window, platform) = try hkWindow { canvasAndPanel(m) }
    let canvas = try keyRegions(window, count: 1)[0]
    platform.simulateInput(mv(centre(canvas.bounds)))
    #expect(platform.simulateInput(kd("x")), "the hovered region claims the key")
    platform.simulateInput(mv(Point(x: px(150), y: px(100))))
    #expect(!platform.simulateInput(kd("y")), "over the panel no region is hovered and nothing is focused")
    platform.simulateInput(.pointerExited)
    #expect(!platform.simulateInput(kd("z")), "the pointer left the window")
    #expect(m.log == ["canvas x"], "only the hovered canvas heard a key: \(m.log)")
}

/// **A19** (`KF-D` item 2). A focused element outside the region keeps the
/// keys while the pointer rests on the region. Mutation: prefer the hover
/// chain when one exists.
@MainActor
@Test func aFocusedElementOutsideTheRegionKeepsTheKeys() throws {
    let m = HKLog()
    let (window, platform) = try hkWindow { canvasAndPanel(m) }
    let canvas = try keyRegions(window, count: 1)[0]
    let first = try #require(window.lastFocusRegistry.tabOrder.first)
    window.focus(first)
    window.drawFrameIfNeeded()
    platform.simulateInput(mv(centre(canvas.bounds)))
    platform.simulateInput(kd("x"))
    #expect(m.log == ["square x"], "focus wins over hover: \(m.log)")
}

/// **A20** (`KF-E` item 3). Nested regions: the innermost hovered region's
/// chain is the key chain, so both handlers run, outermost first. Mutation:
/// take the outermost member (`["outer"]`).
@MainActor
@Test func theInnermostHoveredKeyRegionWins() throws {
    let m = HKLog()
    let (window, platform) = try hkWindow {
        Box {
            Box().frame(width: px(60), height: px(60)).hoverKeyRegion()
                .onKeyPress { _ in m.log.append("inner"); return .ignored }
        }
        .frame(width: px(160), height: px(160))
        .hoverKeyRegion()
        .onKeyPress { _ in m.log.append("outer"); return .ignored }
    }
    let inner = try keyRegions(window, count: 2)[1]
    platform.simulateInput(mv(centre(inner.bounds)))
    platform.simulateInput(kd("x"))
    #expect(m.log == ["outer", "inner"], "the inner region's chain, outermost first: \(m.log)")
}

/// **A21** (`KF-E` item 3: the one ranking). A key region covered by an opaque
/// sibling drawn above it is not hovered where the sibling covers it, nor
/// through a popover declared inside it. Mutations: drop the cover / `isOrDescends` test
/// (first arm); V1, drop the layer test (second arm).
@MainActor
@Test func aKeyRegionUnderAnOpaqueSiblingOrAPresentationIsNotHovered() throws {
    let m = HKLog()
    let (window, platform) = try hkWindow {
        ZStack {
            Box().frame(width: px(200), height: px(200)).hoverKeyRegion()
                .onKeyPress { _ in m.log.append("region"); return .handled }
            Box().frame(width: px(40), height: px(40)).onClick { m.log.append("click") }
        }
    }
    _ = try keyRegions(window, count: 1)
    platform.simulateInput(mv(Point(x: px(100), y: px(100))))
    platform.simulateInput(kd("x"))
    platform.simulateInput(mv(Point(x: px(20), y: px(20))))
    platform.simulateInput(kd("y"))
    #expect(m.log == ["region"], "covered at the centre, hovered at the corner: \(m.log)")

    // The presentation arm (`KF-E` item 3: on the cover's layer). A popover
    // declared inside the region — a `Deferred` presentation whose content
    // descends from the region and lies inside its bounds — is on another
    // layer, so a key typed over it reaches nothing. (A popover written on the
    // region's own element does not descend from the region's id, so it
    // would not separate the layer test.) Mutation V1: drop `box.layer == cover.layer` in
    // `hoveredKeyRegion` (the region hears `p`).
    let p = HKLog()
    let (popWindow, popPlatform) = try hkWindow {
        Box {
            Box().frame(width: px(20), height: px(20))
                .popover(isPresented: .constant(true)) {
                    Box().frame(width: px(40), height: px(40)).onClick { p.log.append("click") }
                }
        }
        .frame(width: px(200), height: px(200)).hoverKeyRegion()
        .onKeyPress { press in p.log.append("region \(press.characters)"); return .handled }
    }
    for _ in 0..<4 where popWindow.needsRedraw { popWindow.drawFrameIfNeeded() }
    let region = try keyRegions(popWindow, count: 1)[0]
    let popover = try #require(popWindow.lastHitboxes.first { $0.handlers.onClick != nil },
                               "set up: the popover's click box registered")
    try #require(popover.layer != region.layer, "set up: the popover is on its own layer")
    try #require(region.contains(centre(popover.bounds)), "set up: the popover lies inside the region")
    let corner = Point(x: px(5), y: px(5))
    try #require(!popover.contains(corner), "set up: the corner is off the popover")
    popPlatform.simulateInput(mv(centre(popover.bounds)))
    popPlatform.simulateInput(kd("p"))
    popPlatform.simulateInput(mv(corner))
    popPlatform.simulateInput(kd("q"))
    #expect(p.log == ["region q"], "over the popover nothing; over the region's corner the region: \(p.log)")
}

// MARK: - A22: Keymap contexts

private struct ZoomGraph: Action {}
private struct PanelOther: Action {}
private struct FrameAll: Action {}

/// **A22** (`KF-D` item 3; M6). The Keymap's contexts come from the key chain:
/// over the `Graph` region a `Graph` binding beats a `!Panel` one by depth;
/// over a region inside a `Panel` contributor `!Panel` is vetoed; a focused
/// field inside `Panel` keeps the keys (and its contexts) wherever the pointer
/// is. Red before (and at `c62d6ba`): the contexts come from the empty focus
/// chain, so `+` runs `PanelOther` and `f` fires over the viewport. Mutation:
/// build `contextsByLevel` from the focus chain.
@MainActor
@Test func keymapContextsReadTheHoveredRegionsChain() throws {
    let m = HKLog()
    let (window, platform) = try hkWindow {
        HStack(spacing: 0) {
            Box().frame(width: px(100), height: px(200)).hoverKeyRegion().keyContext("Graph")
            Column {
                Box().frame(width: px(100), height: px(100)).hoverKeyRegion()
                TextField("t", text: m.text) { m.text = $0 }.frame(width: px(100), height: px(24))
            }
            .keyContext("Panel")
        }
    }
    window.keymap = Keymap([
        KeyBinding("+", PanelOther(), context: "!Panel"),
        KeyBinding("+", ZoomGraph(), context: "Graph"),
        KeyBinding("f", FrameAll(), context: "!Panel"),
    ])
    window.onAction = { action in
        m.log.append(String(describing: type(of: action)))
        return true
    }
    let regions = try keyRegions(window, count: 2)
    platform.simulateInput(mv(centre(regions[0].bounds)))
    platform.simulateInput(kd("+"))
    platform.simulateInput(kd("f"))
    #expect(m.log == ["ZoomGraph", "FrameAll"], "over the graph: Graph beats !Panel, !Panel holds: \(m.log)")

    m.log = []
    platform.simulateInput(mv(centre(regions[1].bounds)))
    platform.simulateInput(kd("f"))
    platform.simulateInput(kd("+"))
    #expect(m.log.isEmpty, "over the viewport inside Panel both !Panel bindings are vetoed: \(m.log)")

    m.log = []
    let first = try #require(window.lastFocusRegistry.tabOrder.first)
    window.focus(first)
    window.drawFrameIfNeeded()
    platform.simulateInput(mv(centre(regions[0].bounds)))
    platform.simulateInput(kd("+"))
    #expect(m.log.isEmpty, "the focused field inside Panel keeps the keys over the graph: \(m.log)")
}

// MARK: - A23: a press in a region

/// **A23a** (`KF-E` item 5; M5-g). A primary press in a key region clears
/// focus held by an element outside it. Red before (and at `c62d6ba`): focus
/// kept. Mutation: delete §4.3's step 3.
@MainActor
@Test func aPressInAKeyRegionClearsFocus() throws {
    let m = HKLog()
    let (window, platform) = try hkWindow { canvasAndPanel(m) }
    let canvas = try keyRegions(window, count: 1)[0]
    let first = try #require(window.lastFocusRegistry.tabOrder.first)
    window.focus(first)
    window.drawFrameIfNeeded()
    platform.simulateInput(down(centre(canvas.bounds)))
    platform.simulateInput(up(centre(canvas.bounds)))
    #expect(window.focusedElement == nil, "the press in the canvas cleared focus")
    platform.simulateInput(kd("x"))
    #expect(m.log == ["canvas x"], "and the canvas under the pointer takes the keys: \(m.log)")
}

/// A key region holding a `TextField` bound to a `@FocusState`.
private struct HKFieldInRegion: Component {
    @FocusState var focused: Bool
    let m: HKLog
    var content: some ElementGroup {
        let _ = m.flags.append(focused)
        Box {
            TextField("t", text: m.text) { m.text = $0 }.focused($focused).frame(width: px(100), height: px(24))
        }
        .frame(width: px(200), height: px(200))
        .hoverKeyRegion()
    }
}

/// **A23b** (`KF-E` item 5, §4.3 step 1). A press on a field inside a key
/// region focuses the field, and its `@FocusState` reads `false` then `true`.
/// Step 1's "no intermediate `nil`" is within one input event, before any
/// frame reconciles the state — so deleting step 1 is an equivalent mutation
/// here (recorded, `KF-X`); the pin is the end state. Red before: the stub
/// registers no region (the `#require`).
@MainActor
@Test func aPressOnAFieldInsideAKeyRegionFocusesItWithOneFocusStateChange() throws {
    let m = HKLog()
    let (window, platform) = try hkWindow { Row { HKFieldInRegion(m: m) } }
    _ = try keyRegions(window, count: 1)
    let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    platform.simulateInput(down(centre(field.bounds)))
    platform.simulateInput(up(centre(field.bounds)))
    for _ in 0..<3 { window.drawFrameIfNeeded() }
    #expect(window.focusedElement == field.id, "the field took focus")
    #expect(m.flags.first == false && m.flags.last == true && Set(m.flags).count == 2
                && m.flags.firstIndex(of: true).map { m.flags[$0...].allSatisfy { $0 } } == true,
            "one change, false then true: \(m.flags)")
}

// MARK: - A24: counted work

/// **A24** (`KF-E` item 4). The hovered region is found at key time, never per
/// pointer move: 50 moves cost 0 lookups, each key event 1; a window with no
/// key region costs 0 for a key too. Red before: the stub counts nothing on
/// the key (`0`, where 1 is due). Mutation: compute the hovered region in
/// `updateHover` (50 lookups for the moves).
@MainActor
@Test func aKeyRegionCostsNoLookupWhileThePointerMoves() throws {
    let m = HKLog()
    let (window, platform) = try hkWindow { canvasAndPanel(m) }
    let canvas = try keyRegions(window, count: 1)[0]
    let start = window.keyRegionLookups
    for i in 0..<50 {
        platform.simulateInput(mv(Point(x: px(10 + Float(i)), y: px(100))))
    }
    #expect(window.keyRegionLookups == start, "50 pointer moves: no lookup (\(window.keyRegionLookups - start))")
    platform.simulateInput(mv(centre(canvas.bounds)))
    platform.simulateInput(kd("x"))
    #expect(window.keyRegionLookups == start + 1, "one key event: one lookup (\(window.keyRegionLookups - start))")

    let (bare, barePlatform) = try hkWindow {
        Box().frame(width: px(100), height: px(100)).onKeyPress { _ in .handled }
    }
    barePlatform.simulateInput(mv(Point(x: px(100), y: px(100))))
    barePlatform.simulateInput(kd("x"))
    #expect(bare.keyRegionLookups == 0, "no key region registered: no lookup")
}

// MARK: - A45: the hover chain drives no `onKey` (`KF-U`)

private struct HKItem: Identifiable, Hashable { let id: Int }

/// **A45** (`KF-U`). A selectable `List` whose row holds a key region, nothing
/// focused, the pointer on the row: ↓ reaches the region's `onKeyPress` (which
/// ignores it) and then nothing — the `List`'s `ControlKeys` and an ancestor's
/// `onKey` live in the `onKey` bubble, which keeps the focus chain. Green
/// against the stub's empty chain except the `onKeyPress` arm; mutation:
/// `dispatchKey` walks the key chain (the selection moves, `onKey` hears it).
@MainActor
@Test func aHoveredRegionDrivesNoControlKeysAndNoOnKey() throws {
    let m = HKLog()
    let items = (0..<3).map(HKItem.init)
    let binding = Binding<Int?>(get: { m.selection }, set: { m.selection = $0; m.selectionWrites.append($0) })
    let (window, platform) = try hkWindow {
        Box {
            List(items, selection: binding, rowHeight: px(20)) { item in
                Text("Row \(item.id)").hoverKeyRegion()
                    .onKeyPress(.downArrow) { m.log.append("kp \(item.id)"); return .ignored }
            }
        }
        .frame(width: px(200), height: px(200))
        .onKey { _ in m.log.append("onKey"); return false }
    }
    let regions = try keyRegions(window, count: 3)
    platform.simulateInput(mv(centre(regions[0].bounds)))
    platform.simulateInput(kd(TextEditing.downArrow))
    #expect(m.log == ["kp 0"], "only the region's onKeyPress heard ↓: \(m.log)")
    #expect(m.selection == 0 && m.selectionWrites.isEmpty, "the selection did not move: \(m.selectionWrites)")
}
