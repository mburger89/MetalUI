import Testing
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Pointer extras (rulings `PH-A`..`PH-I`; decisions
// `docs/superpowers/2026-11-01-pointer-extras-decisions.md`): the one-way
// `columnResize(directions:)` / `rowResize(directions:)` and
// `pointerVisibility(_:)`, through a real `Window` on a `FakePlatformWindow`.
// Geometry as `InputAPIWindowTests`: a 300 x 300 window whose 200 x 200 root is
// centred at (50, 50)-(250, 250), so a window point (x, y) is the root's local
// point (x - 50, y - 50). Nothing sleeps.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func moved(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func ldown(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y))) }
private func ldrag(_ x: Float, _ y: Float) -> InputEvent { .mouseDragged(MouseEvent(position: pt(x, y))) }
private func lup(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y))) }

@MainActor
private func pWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 300, content: content)
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

@MainActor private func settle(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor private func square() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200))
}

// MARK: - The direction sets

/// **1** (`PH-A`). `HorizontalDirection.Set` and `VerticalDirection.Set` are
/// SwiftUI's option sets: two bits, `all` both, `init(_:)` the single one,
/// raw values `Int8`. Mutation: make `all` the first bit only.
@Test func theDirectionSetsAreSwiftUIsOptionSets() {
    #expect(HorizontalDirection.Set.all == [.leading, .trailing])
    #expect(HorizontalDirection.Set(.leading) == .leading && HorizontalDirection.Set(.trailing) == .trailing)
    #expect(HorizontalDirection.Set.leading.rawValue != HorizontalDirection.Set.trailing.rawValue)
    #expect(VerticalDirection.Set.all == [.up, .down])
    #expect(VerticalDirection.Set(.up) == .up && VerticalDirection.Set(.down) == .down)
    #expect(VerticalDirection.Set.up.rawValue != VerticalDirection.Set.down.rawValue)
    #expect(HorizontalDirection.allCases == [.leading, .trailing] && VerticalDirection.allCases == [.up, .down])
}

// MARK: - columnResize(directions:), rowResize(directions:)

/// **2** (`PH-A`, probe `D0`-`D9`). Both directions is the plain resize, one
/// direction a one-way arrow towards that side, the empty set the arrow; the
/// four one-way styles are pairwise distinct. Mutations: lower `.leading` to
/// the trailing arrow; treat the empty set as `.all`.
@Test func aDirectionalResizeLowersAsProbeDMeasured() {
    #expect(PointerStyle.columnResize(directions: .all) == .columnResize)
    #expect(PointerStyle.rowResize(directions: .all) == .rowResize)
    #expect(PointerStyle.columnResize(directions: []) == .default)
    #expect(PointerStyle.rowResize(directions: []) == .default)
    let lowered: [PlatformPointerStyle] = [
        PointerStyle.columnResize(directions: .leading).platformStyle,
        PointerStyle.columnResize(directions: .trailing).platformStyle,
        PointerStyle.rowResize(directions: .up).platformStyle,
        PointerStyle.rowResize(directions: .down).platformStyle,
    ]
    #expect(lowered == [.columnResizeOneWay(towardTrailing: false), .columnResizeOneWay(towardTrailing: true),
                        .rowResizeOneWay(towardDown: false), .rowResizeOneWay(towardDown: true)])
    #expect(Set(lowered).count == 4)
    #expect(PointerStyle.columnResize(directions: .leading) != .columnResize)
}

/// **3** (`PH-A`). A one-way style reaches the platform through the window as
/// the seam's one-way case, on both vocabularies. Mutation: send `.columnResize`
/// whatever the directions.
@MainActor
@Test func aOneWayResizeReachesThePlatformOnBothVocabularies() throws {
    let (w1, p1) = try pWindow { square().pointerStyle(.columnResize(directions: .trailing)) }
    let (w2, p2) = try pWindow { VStack { Rectangle().frame(width: px(200), height: px(200))
        .pointerStyle(.rowResize(directions: .up)) } }
    p1.simulateInput(moved(150, 150))
    p2.simulateInput(moved(150, 150))
    #expect(p1.pointerStyles == [.columnResizeOneWay(towardTrailing: true)], "\(p1.pointerStyles)")
    #expect(p2.pointerStyles == [.rowResizeOneWay(towardDown: false)], "\(p2.pointerStyles)")
    withExtendedLifetime((w1, w2)) {}
}

// MARK: - pointerVisibility(_:)

/// **4** (`PH-F`, probe `V2`, `V1`). A hidden region sends `.hidden` on entering
/// and the pointer leaving the window sends the arrow back (SwiftUI unhides on
/// leaving); a re-entry hides again. The control (no modifier) never hides.
/// Mutations: drop the exit's `.arrow`; resolve `.hidden` to `.default`.
@MainActor
@Test func aHiddenPointerIsSentOnEntryAndShownAgainOnExit() throws {
    let (window, platform) = try pWindow { square().pointerVisibility(.hidden) }
    platform.simulateInput(moved(150, 150))
    platform.simulateInput(moved(160, 160))
    #expect(platform.pointerStyles == [.hidden], "one send for two moves: \(platform.pointerStyles)")
    platform.simulateInput(.pointerExited)
    #expect(platform.pointerStyles == [.hidden, .arrow], "shown again on exit: \(platform.pointerStyles)")
    platform.simulateInput(moved(150, 150))
    #expect(platform.pointerStyles == [.hidden, .arrow, .hidden], "\(platform.pointerStyles)")
    platform.simulateInput(moved(10, 10))
    #expect(platform.pointerStyles.last == .arrow, "off the region: \(platform.pointerStyles)")
    let (control, controlPlatform) = try pWindow { square() }
    controlPlatform.simulateInput(moved(150, 150))
    #expect(!controlPlatform.pointerStyles.contains(.hidden))
    withExtendedLifetime((window, control)) {}
}

/// **5** (`PH-F`, probe `V5`, `V6`, `V3`, `V4`). The innermost declaration wins
/// and `.automatic` attaches nothing, on both vocabularies: an outer `.hidden`
/// with a top half `.visible` shows the pointer there (`V5`), with `.automatic`
/// hides there too (`V6`); `.visible` and `.automatic` alone hide nothing.
/// Mutations: take the outermost; make `.automatic` an explicit "visible".
@MainActor
@Test func theInnermostVisibilityWinsAndAutomaticDefers() throws {
    func legacy(_ inner: Visibility) -> some StyledElement {
        Column {
            Box().frame(width: px(200), height: px(100)).pointerVisibility(inner)
            Box().frame(width: px(200), height: px(100))
        }.pointerVisibility(.hidden)
    }
    func proposal(_ inner: Visibility) -> some ProposalElementGroup {
        VStack(spacing: 0) {
            Rectangle().frame(width: px(200), height: px(100)).pointerVisibility(inner)
            Rectangle().frame(width: px(200), height: px(100))
        }.pointerVisibility(.hidden)
    }
    func check(_ platform: FakePlatformWindow, top: PlatformPointerStyle, _ label: String) {
        platform.simulateInput(moved(150, 100))
        #expect(platform.pointerStyles.last == top, "\(label) top: \(platform.pointerStyles)")
        platform.simulateInput(moved(150, 200))
        #expect(platform.pointerStyles.last == .hidden, "\(label) bottom: \(platform.pointerStyles)")
    }
    let (w1, p1) = try pWindow { legacy(.visible) }
    let (w2, p2) = try pWindow { legacy(.automatic) }
    let (w3, p3) = try pWindow { VStack { proposal(.visible) } }
    let (w4, p4) = try pWindow { VStack { proposal(.automatic) } }
    check(p1, top: .arrow, "legacy visible")
    check(p2, top: .hidden, "legacy automatic")
    check(p3, top: .arrow, "proposal visible")
    check(p4, top: .hidden, "proposal automatic")
    let (w5, p5) = try pWindow { square().pointerVisibility(.visible) }
    let (w6, p6) = try pWindow { square().pointerVisibility(.automatic) }
    p5.simulateInput(moved(150, 150)); p6.simulateInput(moved(150, 150))
    #expect(!p5.pointerStyles.contains(.hidden) && !p6.pointerStyles.contains(.hidden))
    let (w7, p7) = try pWindow { square().pointerVisibility(.hidden).pointerVisibility(.visible) }
    p7.simulateInput(moved(150, 150))
    #expect(p7.pointerStyles == [.hidden], "on one element the first written is the inner: \(p7.pointerStyles)")
    withExtendedLifetime((w1, w2, w3, w4, w5, w6, w7)) {}
}

/// **6** (`PH-F`, probe `V7`, `V7b`, `V7c`). Visibility and style are
/// independent declarations: a hidden region hides whatever the style says, and
/// the style is back the moment the pointer is over a visible part: the column
/// is `.link`, its top half `.hidden`. Order on one element does not matter.
/// Mutation: let `.hidden` drop the style it sits with.
@MainActor
@Test func visibilityAndStyleAreIndependentDeclarations() throws {
    let (w1, p1) = try pWindow {
        Column {
            Box().frame(width: px(200), height: px(100)).pointerVisibility(.hidden)
            Box().frame(width: px(200), height: px(100))
        }.pointerStyle(.link)
    }
    p1.simulateInput(moved(150, 100))
    p1.simulateInput(moved(150, 200))
    #expect(p1.pointerStyles == [.hidden, .pointingHand], "\(p1.pointerStyles)")
    let (w2, p2) = try pWindow { square().pointerStyle(.link).pointerVisibility(.hidden) }
    let (w3, p3) = try pWindow { square().pointerVisibility(.hidden).pointerStyle(.link) }
    p2.simulateInput(moved(150, 150)); p3.simulateInput(moved(150, 150))
    #expect(p2.pointerStyles == [.hidden] && p3.pointerStyles == [.hidden], "\(p2.pointerStyles) \(p3.pointerStyles)")
    // An inner `.visible` over an outer `.hidden` shows the pointer in its own style.
    let (w4, p4) = try pWindow {
        Column {
            Box().frame(width: px(200), height: px(100)).pointerVisibility(.visible).pointerStyle(.rectSelection)
            Box().frame(width: px(200), height: px(100))
        }.pointerVisibility(.hidden)
    }
    p4.simulateInput(moved(150, 100))
    #expect(p4.pointerStyles == [.crosshair], "\(p4.pointerStyles)")
    withExtendedLifetime((w1, w2, w3, w4)) {}
}

/// **7** (`PH-F`, probe `V9`). An opaque target drawn above covers a visibility
/// region as it covers a style (the pointer shows over it); off it, hidden.
/// Mutation: eligibility without the visibility arm.
@MainActor
@Test func anOpaqueTargetAboveCoversAVisibilityRegion() throws {
    let (window, platform) = try pWindow {
        ZStack {
            Rectangle().frame(width: px(200), height: px(200)).pointerVisibility(.hidden)
            Rectangle().frame(width: px(50), height: px(50)).onTapGesture {}
        }
    }
    platform.simulateInput(moved(150, 150))
    #expect(platform.pointerStyles.last == .arrow, "covered (V9): \(platform.pointerStyles)")
    platform.simulateInput(moved(60, 60))
    #expect(platform.pointerStyles.last == .hidden, "uncovered: \(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **8** (`PH-F`, `CI-H` item 3). `.disabled(true)`, `.allowsHitTesting(false)`
/// and `.hidden()` each withdraw the visibility region (the arrow); the control
/// hides. Mutation: register outside the disabled gate.
@MainActor
@Test func pointerVisibilityIsWithdrawnByDisabledAllowsHitTestingAndHidden() throws {
    let (disabled, disabledPlatform) = try pWindow { Column { square().pointerVisibility(.hidden).disabled(true) } }
    let (untestable, untestablePlatform) = try pWindow {
        Column { square().pointerVisibility(.hidden).allowsHitTesting(false) }
    }
    let (hidden, hiddenPlatform) = try pWindow { Column { square().pointerVisibility(.hidden).hidden() } }
    let (control, controlPlatform) = try pWindow { Column { square().pointerVisibility(.hidden) } }
    for platform in [disabledPlatform, untestablePlatform, hiddenPlatform, controlPlatform] {
        platform.simulateInput(moved(150, 150))
    }
    #expect(disabledPlatform.pointerStyles == [.arrow], "disabled: \(disabledPlatform.pointerStyles)")
    #expect(untestablePlatform.pointerStyles == [.arrow], "untestable: \(untestablePlatform.pointerStyles)")
    #expect(hiddenPlatform.pointerStyles == [.arrow], "hidden: \(hiddenPlatform.pointerStyles)")
    #expect(controlPlatform.pointerStyles == [.hidden], "control: \(controlPlatform.pointerStyles)")
    withExtendedLifetime((disabled, untestable, hidden, control)) {}
}

/// **9** (`PH-F`, `CI-H` item 6). A press holds the pressed target's visibility
/// while the pointer leaves, as it holds its style: a hidden box with a drag
/// gesture stays hidden at (290, 290); the release resolves under the pointer.
/// Mutation: resolve under the pointer during a press.
@MainActor
@Test func aPressHoldsAHiddenPointerWhileThePointerLeaves() throws {
    let (window, platform) = try pWindow {
        Column { square().pointerVisibility(.hidden).gesture(DragGesture(minimumDistance: 0)) }
    }
    platform.simulateInput(moved(150, 150))
    platform.simulateInput(ldown(150, 150))
    platform.simulateInput(ldrag(290, 290))
    settle(window)
    #expect(platform.pointerStyles == [.hidden], "held off the box: \(platform.pointerStyles)")
    platform.simulateInput(lup(290, 290))
    settle(window)
    #expect(platform.pointerStyles.last == .arrow, "the release resolves under the pointer: \(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **10** (`PH-F`, `SV-N` item 6). While an in-window menu is up the pointer is
/// not hidden: a hidden region under a drawn alert resolves to the arrow.
/// Mutation: skip the suppression for visibility.
@MainActor
@Test func aDrawnAlertShowsThePointerOverAHiddenRegion() throws {
    let model = PEModel()
    let (window, platform) = try pWindow {
        Column { square().pointerVisibility(.hidden) }
            .alert("Title", isPresented: model.binding) { Button("OK") {} }
    }
    platform.presentsAlertsNatively = false
    platform.simulateInput(moved(150, 150))
    #expect(platform.pointerStyles == [.hidden], "\(platform.pointerStyles)")
    model.shown = true
    settle(window); settle(window)
    platform.simulateInput(moved(151, 151))
    #expect(platform.pointerStyles.last == .arrow, "\(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

@Observable @MainActor
private final class PEModel {
    var shown = false
    var binding: Binding<Bool> { Binding(get: { self.shown }, set: { self.shown = $0 }) }
}

/// **11** (`PH-F`, `SV-U`'s shape). A frame whose only pointer regions are
/// visibility regions counts them: the work counter moves for a hidden region
/// and stays 0 for a tree with none. Mutation: count style regions only.
@MainActor
@Test func aVisibilityRegionCountsAsAPointerRegion() throws {
    let (plain, plainPlatform) = try pWindow { Column { square().onClick {} } }
    plainPlatform.simulateInput(moved(150, 150))
    #expect(plain.pointerStyleVisits == 0)
    let (hidden, hiddenPlatform) = try pWindow { Column { square().pointerVisibility(.hidden) } }
    hiddenPlatform.simulateInput(moved(150, 150))
    #expect(hidden.pointerStyleVisits > 0)
    #expect(hidden.lastPointerStyleRegionCount == 1)
    // `.automatic` attaches nothing: no region.
    let (automatic, automaticPlatform) = try pWindow { Column { square().pointerVisibility(.automatic) } }
    automaticPlatform.simulateInput(moved(150, 150))
    #expect(automatic.lastPointerStyleRegionCount == 0)
}
